"""Cross-process resource estimates and endpoint leases, without a runner-count limit."""
from contextlib import contextmanager, nullcontext
try:
    import fcntl
except ImportError:
    fcntl = None  # Report/matrix imports also work on hosts without native launch support.
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import socket
import time

from . import adapters, host, preparation_process, progress

MIB = 1024 ** 2
STATE = Path('/tmp') / ('pz-native-' + str(os.getuid() if hasattr(os, 'getuid') else 'unsupported'))
LEGACY_LOCK = Path('/tmp/pz-queue-native-launch.lock')
DEFAULTS = {'heap_mib': 2048, 'native_mib': 1024, 'cpu_per_instance': 1.0, 'exclusive': False}
DISK_MARGIN = 1024 ** 3
DISK_PER_ROLE = 1024 ** 3
# Preparation hashes/copies inputs and compiles helpers; it does not start role JVMs.
PREPARATION_MEMORY = 1024 ** 3
PREPARATION_CPU = 1.0
WINDOWS_HOST_MUTEX = 'Local\\PZToolkitNativeWindowsHost'


def preparation_budget(selection):
    # Validate the selection's resource settings but reserve independently of role count.
    return {'memory': PREPARATION_MEMORY, 'cpu': PREPARATION_CPU,
            'exclusive': budget(selection)['exclusive']}


def timing_budget(heap_mib=2048, native_mib=512, cpu=1):
    """One bounded headless JVM, always isolated from other native work."""
    if type(cpu) is not int or cpu <= 0:
        raise ValueError('Timing CPU budget must be a positive integer')
    return budget({'kind': 'sp', 'clients': 1, 'resources': {
        'heap_mib': heap_mib, 'native_mib': native_mib,
        'cpu_per_instance': cpu, 'exclusive': True}})


def disk_capacity(root, instances, records=(), copy_bytes=0):
    # shortcut: admission estimates are not quotas; add filesystem quotas if concurrent writers exhaust the reserve.
    path = Path(root).resolve()
    while not path.exists():
        path = path.parent
    device = path.stat().st_dev
    reserved = sum(len(item['caches']) * DISK_PER_ROLE for item in records
                   if item['phase'] == 'running' and Path(item['root']).stat().st_dev == device)
    required = copy_bytes + instances * DISK_PER_ROLE + DISK_MARGIN + reserved
    details = {'path': str(path), 'free_bytes': shutil.disk_usage(path).free, 'copy_bytes': copy_bytes,
               'runtime_bytes': instances * DISK_PER_ROLE, 'margin_bytes': DISK_MARGIN,
               'peer_reserved_bytes': reserved, 'required_bytes': required}
    return details['free_bytes'] >= required, details


def require_disk(root, instances, copy_bytes=0):
    if fcntl is None:
        permitted, details = disk_capacity(root, instances, copy_bytes=copy_bytes)
    else:
        with _locked():
            permitted, details = disk_capacity(root, instances, _records(host.sample()), copy_bytes)
    if not permitted:
        raise RuntimeError(disk_reason(details))
    return details


def disk_reason(details):
    return ('Insufficient disk space at %s: need %.2f GiB (copies, world/cache reserves and margin); free %.2f GiB'
            % (details['path'], details['required_bytes'] / 1024**3, details['free_bytes'] / 1024**3))


def budget(selection):
    overrides = selection.get('resources', {})
    if not isinstance(overrides, dict):
        raise ValueError('resources must be an object')
    settings = dict(DEFAULTS, **overrides)
    if settings.keys() != DEFAULTS.keys():
        raise ValueError('Unknown resource budget setting')
    for key in ('heap_mib', 'native_mib'):
        if type(settings[key]) is not int or settings[key] <= 0:
            raise ValueError(key + ' must be a positive integer')
    cpu = settings['cpu_per_instance']
    if type(cpu) not in (int, float) or not math.isfinite(cpu) or cpu <= 0:
        raise ValueError('cpu_per_instance must be finite and positive')
    if type(settings['exclusive']) is not bool:
        raise ValueError('exclusive must be boolean')
    instances = len(adapters.roles(selection))
    return dict(settings, instances=instances, memory=instances * (settings['heap_mib'] + settings['native_mib']) * MIB,
                cpu=instances * cpu)


def _directory(path=None):
    if fcntl is None:
        raise ValueError('Native admission requires POSIX file locks')
    path = STATE if path is None else path
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.lstat()
    if path.is_symlink() or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise RuntimeError('Native admission directory must be owned by this user with mode 0700: ' + str(path))


@contextmanager
def _locked():
    _directory()
    with (STATE / 'mutex').open('a+') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def _key(root):
    return hashlib.sha256(str(root).encode()).hexdigest()


def _save(record, directory=None):
    path = (STATE if directory is None else directory) / (_key(record['root']) + '.json')
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(record) + '\n')
    temporary.replace(path)


def _held(root):
    with (STATE / (_key(root) + '.lease')).open('a+') as stream:
        try:
            fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return True
    return False


def _waiters():
    # Old runners only understand prepared/running in STATE/*.json.
    # shortcut: FIFO orders updated runners only; migrate remaining callers before relying on global fairness.
    directory = STATE / 'waiters'
    _directory(directory)
    result = []
    for path in directory.glob('*.json'):
        try:
            item = json.loads(path.read_text())
            if (not isinstance(item, dict) or not isinstance(item['root'], str)
                    or not Path(item['root']).is_absolute() or path.stem != _key(item['root'])
                    or type(item['sequence']) is not int or item['sequence'] <= 0
                    or type(item['pid']) is not int or item['pid'] <= 0
                    or type(item['queued_at']) not in (int, float) or not math.isfinite(item['queued_at'])
                    or not isinstance(item['reason'], str) or type(item['exclusive']) is not bool
                    or item.get('phase', 'running') not in ('running', 'preparing', 'timing')):
                raise ValueError('invalid waiter')
            if _held(item['root']):
                result.append(item)
            else:
                path.unlink()
        except (ValueError, KeyError, TypeError) as error:
            raise RuntimeError('Invalid native admission waiter: ' + str(path)) from error
    if len({item['sequence'] for item in result}) != len(result):
        raise RuntimeError('Duplicate native admission waiter sequence')
    return sorted(result, key=lambda item: item['sequence'])


def _metadata(selection):
    return {key: selection.get(key) for key in ('suite', 'kind', 'mode', 'cases')}


def status(legacy_lock=None):
    """Inspect reservations and reconcile dead owners without interrupting any process."""
    lock = Path(legacy_lock or LEGACY_LOCK)
    with _locked():
        snapshot = host.sample()
        records = _records(snapshot)
        preparations = _preparations()
        timings = _timings()
        now = time.time()
        waiting = [dict(item, position=index, wait_seconds=max(0, now - item['queued_at']))
                   for index, item in enumerate(_waiters(), 1)]
        running = []
        for item in records:
            if item['phase'] == 'running':
                alive = _held(item['root'])
                processes = owned(item, snapshot)
                if not alive and not processes:
                    processes = owned(item, host.sample())
                running.append(dict(item, processes=processes, owner_alive=alive))
        locks = {}
        with lock.open('a+') as stream:
            for name, mode in (('busy', fcntl.LOCK_EX), ('exclusive', fcntl.LOCK_SH)):
                try:
                    fcntl.flock(stream, mode | fcntl.LOCK_NB)
                    locks[name] = False
                except BlockingIOError:
                    locks[name] = True
                finally:
                    fcntl.flock(stream, fcntl.LOCK_UN)
        return {'schema_version': 1, 'state_directory': str(STATE),
                'running': running, 'preparing': [dict(item, owner_alive=item['pid'] == os.getpid() or any(
                    process['pid'] == item['pid'] for process in snapshot['processes'])) for item in preparations],
                'timing': [dict(item, owner_alive=item['pid'] == os.getpid() or any(
                    process['pid'] == item['pid'] for process in snapshot['processes'])) for item in timings],
                'waiting': waiting, 'prepared': [item for item in records if item['phase'] == 'prepared'],
                'legacy_lock': dict(locks, path=str(lock)),
                'limits': ['FIFO applies to updated runners; older runners do not register waiters.',
                           'An unregistered legacy lock owner cannot be identified reliably.']}


def owned(record, snapshot):
    caches = {Path(cache).resolve() for cache in record.get('caches', [])}
    result = []
    for process in snapshot['processes']:
        if not process['game']:
            continue
        # Only strip the two logging arguments native CoopMaster appends, preserving spaces/dashes in paths.
        match = re.search(r'(?:^|\s)-cachedir=(.*)$', process['command'])
        value = re.sub(r'\s+-useTimeStampedLogFileNames=[01]\s+-debugLogFile=\S*$', '', match[1]) if match else None
        if value is not None and Path(value.strip()).resolve() in caches:
            result.append(process)
    return result


def _records(snapshot=None):
    records = []
    for path in STATE.glob('*.json'):
        try:
            item = json.loads(path.read_text())
            if not isinstance(item, dict) or path.stem != _key(item['root']) or item['phase'] not in ('prepared', 'running'):
                raise ValueError('invalid record')
            root = Path(item['root'])
            if not root.is_absolute() or not isinstance(item['ports'], list) or len(set(item['ports'])) != len(item['ports']) or any(
                    type(port) is not int or not 1024 <= port <= 65535 for port in item['ports']):
                raise ValueError('invalid root or ports')
            if not isinstance(item['caches'], list) or any(not isinstance(cache, str) or not Path(cache).is_relative_to(root) for cache in item['caches']):
                raise ValueError('invalid role caches')
            if item['phase'] == 'running':
                saved = item['budget']
                expected = budget({'kind': 'sp', 'clients': len(item['caches']),
                                   'resources': {key: saved[key] for key in DEFAULTS}})
                if not item['caches'] or saved != expected:
                    raise ValueError('invalid resource reservation')
            live = owned(item, snapshot) if snapshot is not None else []
            held = _held(item['root'])
            # Re-sample after observing owner death: its last Popen may postdate the first sample.
            if snapshot is not None and item['phase'] == 'running' and not held and not live:
                live = owned(item, host.sample())
                held = _held(item['root'])
            removable = not held and not live and (
                item['phase'] == 'prepared' and not Path(item['root']).exists() or snapshot is not None and item['phase'] == 'running')
            if removable:
                path.unlink()
            else:
                records.append(item)
        except (ValueError, KeyError, TypeError) as error:
            raise RuntimeError('Invalid native admission record: ' + str(path)) from error
    return records


def _preparations():
    return _reservations('preparing')


def _timings():
    return _reservations('timing')


def _reservations(phase):
    # Separate from top-level records so older runners retain their schema.
    directory = STATE / phase
    _directory(directory)
    result = []
    for path in directory.glob('*.json'):
        try:
            item = json.loads(path.read_text())
            if (not isinstance(item, dict) or not isinstance(item['root'], str)
                    or not Path(item['root']).is_absolute() or path.stem != _key(item['root'])
                    or item['phase'] != phase or type(item['pid']) is not int or item['pid'] <= 0
                    or type(item['started_at']) not in (int, float) or not math.isfinite(item['started_at'])
                    or not isinstance(item['budget'], dict) or type(item['budget'].get('exclusive')) is not bool
                    or type(item['budget'].get('memory')) is not int
                    or type(item['budget'].get('cpu')) not in (int, float)
                    or (phase == 'preparing' and item['budget'] != {
                        'memory': PREPARATION_MEMORY, 'cpu': PREPARATION_CPU,
                        'exclusive': item['budget']['exclusive']})):
                raise ValueError('invalid preparation')
            if phase == 'timing':
                saved = item['budget']
                if (saved != timing_budget(saved['heap_mib'], saved['native_mib'], saved['cpu_per_instance'])
                        or not isinstance(item.get('bank'), str)
                        or re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', item['bank']) is None):
                    raise ValueError('invalid timing reservation')
            if _held(item['root']):
                result.append(item)
            else:
                path.unlink()
        except (ValueError, KeyError, TypeError) as error:
            label = 'preparation' if phase == 'preparing' else phase
            raise RuntimeError('Invalid native ' + label + ' record: ' + str(path)) from error
    return result


@contextmanager
def _udp(ports):
    sockets = []
    try:
        for port in ports:
            stream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sockets.append(stream)
            stream.bind(('0.0.0.0', port))
        yield
    finally:
        for stream in sockets:
            stream.close()


def allocate_ports(root, selection):
    """Reserve an automatic pair before freezing the snapshot; explicit ports stay explicit."""
    root = Path(root).resolve()
    seed = selection.get('options', {}).get('seed_run')
    if seed:
        return json.loads((Path(seed) / 'selection.json').read_text())['ports']
    with _locked():
        taken = {p for item in _records() for p in item['ports']}
        start = int(_key(root)[:8], 16) % 20000
        for index in range(20000):
            first = 20000 + 2 * ((start + index) % 20000)
            ports = [first, first + 1]
            if taken.intersection(ports):
                continue
            try:
                with _udp(ports):
                    _save({'root': str(root), 'ports': ports, 'phase': 'prepared', 'caches': []})
                return ports
            except OSError:
                continue
    raise RuntimeError('No available adjacent UDP ports for native smoke')


def capacity(snapshot, records, request, request_pid=None):
    pending_memory = pending_cpu = 0
    accounted_pids = set()
    for item in records:
        if item['phase'] not in ('running', 'preparing', 'timing'):
            continue
        processes = (owned(item, snapshot) if item['phase'] == 'running' else
                     [process for process in snapshot['processes'] if process['pid'] == item['pid']])
        processes = [process for process in processes if process['pid'] not in accounted_pids]
        accounted_pids.update(process['pid'] for process in processes)
        pending_memory += max(0, item['budget']['memory'] - sum(p['rss'] for p in processes))
        pending_cpu += max(0, item['budget']['cpu'] - sum(p['cpu'] for p in processes))
    # Available memory already excludes RSS; reserve only each admitted run's unconsumed budget.
    margin = max(1024 * MIB, int(snapshot['total_memory'] * 0.1))
    memory = max(0, snapshot['available_memory'] - pending_memory - margin)
    cpu = max(0, snapshot['cpu_count'] - sum(p['cpu'] for p in snapshot['processes']) - pending_cpu)
    details = {'memory_available': int(memory), 'cpu_available': cpu, 'host_memory_margin': margin,
               'host_available_memory': snapshot['available_memory'], 'host_cpu_count': snapshot['cpu_count'],
               'active_runs': sum(item['phase'] == 'running' for item in records),
               'active_preparations': sum(item['phase'] == 'preparing' for item in records), 'budget': request}
    details['active_timings'] = sum(item['phase'] == 'timing' for item in records)
    # The preparing Python owner's usage is already in the host inventory.
    current = [process for process in snapshot['processes']
               if process['pid'] == request_pid and process['pid'] not in accounted_pids]
    requested_memory = max(0, request['memory'] - sum(process['rss'] for process in current))
    requested_cpu = max(0, request['cpu'] - sum(process['cpu'] for process in current))
    return memory >= requested_memory and cpu >= requested_cpu, details


@contextmanager
def acquire(root, selection, runtime, wait=300, legacy_lock=None):
    _validate_wait(wait)
    root = Path(root).resolve()
    request = budget(selection)
    caches = [str(Path(value['cache']).resolve()) for value in runtime['roles'].values()]
    if set(runtime['roles']) != set(adapters.roles(selection)) or any(Path(cache) != root / role for role, cache in zip(runtime['roles'], caches)):
        raise ValueError('Native role caches must belong to this run')
    record = {'root': str(root), 'phase': 'running', 'ports': selection.get('ports', []) if selection['kind'] == 'mp' else [],
              'caches': caches, 'budget': request, 'pid': os.getpid(), **_metadata(selection)}
    with _admit(root, selection, record, wait, legacy_lock) as details:
        yield details


@contextmanager
def preparing(root, selection, wait=300, legacy_lock=None):
    """Admit hashing, copying and compilation with a 1 GiB / 1 CPU estimate.

    POSIX preparations share run FIFO/exclusive locks. Windows uses the existing
    Host mutex conservatively (serial admission; no FIFO or CPU inventory).
    """
    _validate_wait(wait)
    request = preparation_budget(selection)
    if fcntl is None and os.name == 'nt':
        from . import preparation_windows
        with _windows_preparing(request, wait) as details:
            with preparation_windows.contain() as job, preparation_process.inherit(windows_job=job):
                yield details
        return
    root = Path(root).resolve()
    record = dict(_metadata(selection), root=str(root), phase='preparing',
                  budget=request, pid=os.getpid())
    with _admit(root, selection, record, wait, legacy_lock) as details:
        yield details


@contextmanager
def measuring(root, bank, wait=300, heap_mib=2048, native_mib=512, cpu=1):
    """Reserve a headless measurement through the same FIFO and lifetime locks."""
    _validate_wait(wait)
    if not isinstance(bank, str) or re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]{0,127}', bank) is None:
        raise ValueError('Timing bank must be a nonempty protocol-safe identifier')
    request = timing_budget(heap_mib, native_mib, cpu)
    if fcntl is None and os.name == 'nt':
        from . import preparation_windows
        with _windows_preparing(request, wait) as details:
            with preparation_windows.contain() as job, preparation_process.inherit(windows_job=job):
                yield dict(details, phase='timing', bank=bank, root=os.path.abspath(os.fspath(root)), exclusive=True,
                           pid=os.getpid(), started_at=time.time())
        return
    root = Path(root).resolve()
    record = dict(root=str(root), phase='timing', bank=bank, budget=request, pid=os.getpid())
    with _admit(root, {}, record, wait, None) as details:
        yield dict(details, phase='timing', bank=bank, root=str(root), exclusive=True,
                   pid=record['pid'], started_at=record['started_at'])


def _validate_wait(wait):
    if type(wait) not in (int, float) or not math.isfinite(wait) or wait < 0:
        raise ValueError('Resource wait must be finite and nonnegative')


def _progress_owners(root):
    """Read only registered held leases; diagnostic data never grants admission."""
    owners = []
    for directory in (STATE, STATE / 'preparing', STATE / 'timing'):
        for path in sorted(directory.glob('*.json')):
            try:
                row = json.loads(path.read_text())
                if (row.get('phase') in ('running', 'preparing', 'timing') and row.get('root') != str(root)
                        and isinstance(row.get('root'), str) and _held(row['root'])):
                    owners.append(dict(suite=row.get('suite'), phase=row['phase']))
                    if len(owners) == 8:
                        return owners
            except (OSError, ValueError, TypeError, AttributeError):
                continue
    return owners or None


@contextmanager
def _admit(root, selection, record, wait, legacy_lock):
    _validate_wait(wait)
    request = record['budget']
    phase = record['phase']
    preparation = phase == 'preparing'
    headless = phase == 'timing'
    contained = preparation or headless
    record_directory = STATE / phase if contained else STATE
    deadline = time.monotonic() + wait
    _directory()
    with (STATE / (_key(root) + '.lease')).open('a+') as lease, Path(legacy_lock or LEGACY_LOCK).open('a+') as legacy:
        try:
            fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError('This native profile is already admitted or waiting: ' + str(root)) from error
        admitted = False
        updates = progress.Phase('admission', suite=selection.get('suite'), request_phase=phase,
            request_memory_gib=round(request['memory'] / 1024**3, 2), request_cpu=request['cpu'],
            wait_limit_seconds=wait)
        progress_finished = False
        waiting_path = STATE / 'waiters' / (_key(root) + '.json')
        try:
            with _locked():
                _directory(waiting_path.parent)
                _preparations()  # Validate before reconciling this newly acquired root lease.
                _timings()
                for directory in ('preparing', 'timing'):
                    (STATE / directory / (_key(root) + '.json')).unlink(missing_ok=True)
                # A restarted owner must not inherit its dead predecessor's queue position.
                waiting_path.unlink(missing_ok=True)
                waiters = _waiters()
                waiter = dict(_metadata(selection), root=str(root), pid=os.getpid(),
                              sequence=max((item['sequence'] for item in waiters), default=0) + 1,
                              queued_at=time.time(), exclusive=request['exclusive'], phase=record['phase'], reason='Checking admission')
                if headless:
                    waiter['bank'] = record['bank']
                _save(waiter, waiting_path.parent)
            while True:
                reason = None
                details, peers = None, None
                with _locked():
                    waiters = _waiters()
                    if not waiters or not any(item['root'] == str(root) for item in waiters):
                        raise RuntimeError('Native admission waiter disappeared: ' + str(root))
                    position = next(index for index, item in enumerate(waiters, 1) if item['root'] == str(root))
                    if waiters[0]['root'] != str(root):
                        reason = 'FIFO: waiting behind ' + waiters[0]['root']
                    else:
                        try:
                            # Only the head takes the lifetime lock; blocked requests release it below.
                            fcntl.flock(legacy, (fcntl.LOCK_EX if request['exclusive'] else fcntl.LOCK_SH) | fcntl.LOCK_NB)
                        except BlockingIOError:
                            reason = ('Legacy or exclusive native work owns the resource lease' if headless else
                                      'Legacy or exclusive native run is using the desktop')
                    if reason is None:
                        snapshot = host.sample()
                        records = _records(snapshot) + _preparations() + _timings()
                        peers = [item for item in records if item['root'] != str(root)]
                        current = (owned(record, snapshot) if not contained else
                                   [process for item in records if item['root'] == str(root)
                                    for process in owned(item, snapshot)])
                        if current:
                            raise RuntimeError('Existing game process uses this profile: ' + str([p['pid'] for p in current]))
                        if not contained and ((root / 'execution.json').exists() or list(root.glob('*-launch.log'))):
                            raise ValueError('Run directory has already launched; prepare a fresh snapshot')
                        reserved = {port for item in peers for port in item.get('ports', [])}
                        permitted, details = capacity(snapshot, peers, request, os.getpid() if contained else None)
                        disk_permitted = True
                        if not headless:
                            disk_permitted, details['disk'] = disk_capacity(root, 0 if preparation else request['instances'], peers)
                        if any(item['phase'] in ('running', 'preparing', 'timing') and (request['exclusive'] or item['budget']['exclusive']) for item in peers):
                            reason = ('Exclusive native run still has live game processes' if any(
                                item['phase'] == 'running' for item in peers) else
                                'Exclusive preparation or timing work still holds its lease')
                        elif reserved.intersection(record.get('ports', [])):
                            reason = 'UDP ports reserved by another native run: ' + str(record['ports'])
                        elif not permitted:
                            reason = ('Insufficient resources: need %.2f GiB / %.2f CPU; available after reserves %.2f GiB / %.2f CPU'
                                      % (request['memory'] / 1024**3, request['cpu'], details['memory_available'] / 1024**3, details['cpu_available']))
                        elif not disk_permitted:
                            reason = disk_reason(details['disk'])
                        else:
                            endpoints_available = False
                            try:
                                with (nullcontext() if headless else _udp(record.get('ports', []))):
                                    endpoints_available = True
                                    record['started_at'] = time.time()
                                    _directory(record_directory)
                                    _save(record, record_directory)
                                    admitted = True
                                    waiting_path.unlink()
                            except OSError as error:
                                if endpoints_available:
                                    raise
                                reason = 'UDP endpoint unavailable: ' + str(error)
                    if not admitted:
                        fcntl.flock(legacy, fcntl.LOCK_UN)
                        if reason != waiter['reason']:
                            waiter['reason'] = reason
                            _save(waiter, waiting_path.parent)
                if admitted:
                    updates.update(position=position, remaining_seconds=round(max(0, deadline - time.monotonic()), 1))
                    updates.finish('admitted')
                    progress_finished = True
                    if contained:
                        with preparation_process.inherit((lease.fileno(), legacy.fileno())):
                            yield details
                    else:
                        yield details
                    return
                owners = _progress_owners(root) if peers is None else []
                if peers is not None:
                    owners = [dict(suite=item.get('suite'), phase=item['phase']) for item in peers
                              if item['phase'] in ('running', 'preparing', 'timing')][:8]
                updates.update(reason=reason, position=position,
                    remaining_seconds=round(max(0, deadline - time.monotonic()), 1),
                    active_suites=owners,
                    available_memory_gib=round(details['memory_available'] / 1024**3, 2) if details is not None else None,
                    available_cpu=round(details['cpu_available'], 2) if details is not None else None)
                if time.monotonic() >= deadline:
                    updates.finish('expired')
                    progress_finished = True
                    raise RuntimeError(reason + ('; resource wait expired (no timing JVM launched)' if headless else
                                                 '; resource wait expired (no game launched)'))
                time.sleep(min(2, max(0, deadline - time.monotonic())))
        finally:
            if not progress_finished:
                updates.finish('failed')
            with _locked():
                waiting_path.unlink(missing_ok=True)
                # Failed sampling/cleanup must retain the record for the next admission to reconcile.
                if admitted and contained:
                    # Closing our descriptors preserves a worker's inherited flock.
                    # LOCK_UN would unlock their shared open-file descriptions too.
                    lease.close()
                    legacy.close()
                    if not _held(root):
                        (record_directory / (_key(root) + '.json')).unlink(missing_ok=True)
                elif admitted and not owned(record, host.sample()):
                    (STATE / (_key(root) + '.json')).unlink(missing_ok=True)


@contextmanager
def _windows_preparing(request, wait):
    import ctypes
    from ctypes import wintypes as W

    kernel = ctypes.WinDLL('kernel32', use_last_error=True)
    kernel.CreateMutexW.argtypes = [W.LPVOID, W.BOOL, W.LPCWSTR]
    kernel.CreateMutexW.restype = W.HANDLE
    kernel.WaitForSingleObject.argtypes = [W.HANDLE, W.DWORD]
    kernel.WaitForSingleObject.restype = W.DWORD
    kernel.ReleaseMutex.argtypes = [W.HANDLE]
    kernel.ReleaseMutex.restype = W.BOOL
    kernel.CloseHandle.argtypes = [W.HANDLE]
    kernel.CloseHandle.restype = W.BOOL
    mutex = kernel.CreateMutexW(None, False, WINDOWS_HOST_MUTEX)
    if not mutex:
        raise ctypes.WinError(ctypes.get_last_error())
    acquired = False
    deadline = time.monotonic() + wait
    updates = progress.Phase('admission', request_phase='preparing', wait_limit_seconds=wait,
        request_memory_gib=round(request['memory'] / 1024**3, 2), request_cpu=request['cpu'],
        policy='Windows serial preparation/Host mutex')
    progress_finished = False
    try:
        # Slice large waits to avoid DWORD overflow and retain cancellation points.
        while True:
            remaining = max(0, deadline - time.monotonic())
            result = kernel.WaitForSingleObject(mutex, min(1000, int(remaining * 1000)))
            if result in (0, 0x80):  # WAIT_OBJECT_0 or abandoned (owner died).
                acquired = True
                break
            if result != 0x102:
                raise RuntimeError('Cannot acquire Windows native preparation lease: ' + str(result))
            updates.update(remaining_seconds=round(max(0, deadline - time.monotonic()), 1), reason='Windows preparation or Host lease is busy')
            if time.monotonic() >= deadline:
                raise RuntimeError('Another Windows preparation or Host run owns the lease; resource wait expired (no game launched)')

        class Memory(ctypes.Structure):
            _fields_ = [('length', W.DWORD), ('load', W.DWORD), *[(name, ctypes.c_ulonglong) for name in
                ('total', 'available', 'totalPage', 'availablePage', 'totalVirtual', 'availableVirtual', 'extended')]]

        kernel.GlobalMemoryStatusEx.argtypes = [ctypes.POINTER(Memory)]
        kernel.GlobalMemoryStatusEx.restype = W.BOOL
        memory = Memory()
        memory.length = ctypes.sizeof(memory)
        if not kernel.GlobalMemoryStatusEx(ctypes.byref(memory)):
            raise ctypes.WinError(ctypes.get_last_error())
        if memory.total <= 0 or memory.available > memory.total:
            raise RuntimeError('Cannot sample valid Windows preparation memory capacity')
        margin = max(1024**3, memory.total // 10)
        if memory.available - margin < request['memory']:
            raise RuntimeError('Insufficient available memory after the live host and safety margin; no game launched')
        updates.update(available_memory_gib=round((memory.available - margin) / 1024**3, 2))
        updates.finish('admitted')
        progress_finished = True
        yield {'budget': request, 'memory_available': memory.available - margin,
               'host_available_memory': memory.available, 'host_memory_margin': margin,
               'limits': ['Windows preparation and Host runs use a serial named mutex; no FIFO or CPU inventory.']}
    finally:
        if not progress_finished:
            updates.finish('failed')
        if acquired:
            kernel.ReleaseMutex(mutex)
        kernel.CloseHandle(mutex)
