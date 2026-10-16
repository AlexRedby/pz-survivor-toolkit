"""Cross-process resource estimates and endpoint leases, without a runner-count limit."""
from contextlib import contextmanager
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
import socket
import time

from . import adapters, host

MIB = 1024 ** 2
STATE = Path('/tmp') / ('pz-native-' + str(os.getuid() if hasattr(os, 'getuid') else 'unsupported'))
LEGACY_LOCK = Path('/tmp/pz-queue-native-launch.lock')
DEFAULTS = {'heap_mib': 2048, 'native_mib': 1024, 'cpu_per_instance': 1.0, 'exclusive': False}


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


def _directory():
    if fcntl is None:
        raise ValueError('Native admission requires POSIX file locks')
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = STATE.lstat()
    if STATE.is_symlink() or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise RuntimeError('Native admission directory must be owned by this user with mode 0700: ' + str(STATE))


@contextmanager
def _locked():
    _directory()
    with (STATE / 'mutex').open('a+') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def _key(root):
    return hashlib.sha256(str(root).encode()).hexdigest()


def _save(record):
    path = STATE / (_key(record['root']) + '.json')
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


def owned(record, snapshot):
    caches = {Path(cache).resolve() for cache in record.get('caches', [])}
    result = []
    for process in snapshot['processes']:
        if not process['game']:
            continue
        # Our launcher appends cachedir last; paths may themselves contain spaces and dashes.
        match = re.search(r'(?:^|\s)-cachedir=(.*)$', process['command'])
        if match and Path(match[1].strip()).resolve() in caches:
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


def capacity(snapshot, records, request):
    pending_memory = pending_cpu = 0
    for item in records:
        if item['phase'] != 'running':
            continue
        processes = owned(item, snapshot)
        pending_memory += max(0, item['budget']['memory'] - sum(p['rss'] for p in processes))
        pending_cpu += max(0, item['budget']['cpu'] - sum(p['cpu'] for p in processes))
    # Available memory already excludes RSS; reserve only each admitted run's unconsumed budget.
    margin = max(1024 * MIB, int(snapshot['total_memory'] * 0.1))
    memory = max(0, snapshot['available_memory'] - pending_memory - margin)
    cpu = max(0, snapshot['cpu_count'] - sum(p['cpu'] for p in snapshot['processes']) - pending_cpu)
    details = {'memory_available': int(memory), 'cpu_available': cpu, 'host_memory_margin': margin,
               'host_available_memory': snapshot['available_memory'], 'host_cpu_count': snapshot['cpu_count'],
               'active_runs': sum(item['phase'] == 'running' for item in records), 'budget': request}
    return memory >= request['memory'] and cpu >= request['cpu'], details


@contextmanager
def acquire(root, selection, runtime, wait=300, legacy_lock=None):
    if type(wait) not in (int, float) or not math.isfinite(wait) or wait < 0:
        raise ValueError('Resource wait must be finite and nonnegative')
    root = Path(root).resolve()
    request = budget(selection)
    caches = [str(Path(value['cache']).resolve()) for value in runtime['roles'].values()]
    if set(runtime['roles']) != set(adapters.roles(selection)) or any(Path(cache) != root / role for role, cache in zip(runtime['roles'], caches)):
        raise ValueError('Native role caches must belong to this run')
    record = {'root': str(root), 'phase': 'running', 'ports': selection.get('ports', []) if selection['kind'] == 'mp' else [],
              'caches': caches, 'budget': request, 'pid': os.getpid()}
    deadline = time.monotonic() + wait
    _directory()
    with (STATE / (_key(root) + '.lease')).open('a+') as lease, Path(legacy_lock or LEGACY_LOCK).open('a+') as legacy:
        try:
            fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError('This native profile is already admitted or waiting: ' + str(root)) from error
        admitted = False
        last_message = None
        try:
            while True:
                reason = None
                try:
                    # Shared lifetime lock allows new runners together, excluding old exclusive runners.
                    fcntl.flock(legacy, (fcntl.LOCK_EX if request['exclusive'] else fcntl.LOCK_SH) | fcntl.LOCK_NB)
                except BlockingIOError:
                    reason = 'Legacy or exclusive native run is using the desktop'
                if reason is None:
                    with _locked():
                        snapshot = host.sample()
                        records = _records(snapshot)
                        peers = [item for item in records if item['root'] != str(root)]
                        current = owned(record, snapshot)
                        if current:
                            raise RuntimeError('Existing game process uses this profile: ' + str([p['pid'] for p in current]))
                        if (root / 'execution.json').exists() or list(root.glob('*-launch.log')):
                            raise ValueError('Run directory has already launched; prepare a fresh snapshot')
                        reserved = {port for item in peers for port in item['ports']}
                        permitted, details = capacity(snapshot, peers, request)
                        if any(item['phase'] == 'running' and (request['exclusive'] or item['budget']['exclusive']) for item in peers):
                            reason = 'Exclusive native run still has live game processes'
                        elif reserved.intersection(record['ports']):
                            reason = 'UDP ports reserved by another native run: ' + str(record['ports'])
                        elif not permitted:
                            reason = ('Insufficient resources: need %.2f GiB / %.2f CPU; available after reserves %.2f GiB / %.2f CPU'
                                      % (request['memory'] / 1024**3, request['cpu'], details['memory_available'] / 1024**3, details['cpu_available']))
                        else:
                            try:
                                with _udp(record['ports']):
                                    _save(record)
                                admitted = True
                            except OSError as error:
                                reason = 'UDP endpoint unavailable: ' + str(error)
                    if admitted:
                        yield details
                        return
                if time.monotonic() >= deadline:
                    raise RuntimeError(reason + '; resource wait expired (no game launched)')
                if reason != last_message:
                    print('WAIT ' + reason, flush=True)
                    last_message = reason
                time.sleep(min(2, max(0, deadline - time.monotonic())))
        finally:
            if admitted:
                with _locked():
                    # Failed sampling/cleanup must retain the record for the next admission to reconcile.
                    if not owned(record, host.sample()):
                        (STATE / (_key(root) + '.json')).unlink(missing_ok=True)
