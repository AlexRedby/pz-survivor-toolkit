"""Explicit, recoverable retirement of stopped native runs' private mod trees."""
from contextlib import contextmanager, ExitStack
from functools import wraps
import hashlib
import errno
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile
import threading

from . import admission, snapshot_store, progress

MARKER = 'snapshot-storage.json'
_local = threading.local()
_ID = re.compile(r'[0-9a-f]{64}\Z')


def _json(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError('Storage metadata must be a regular file: ' + str(path))
    return json.loads(path.read_text(encoding='utf-8'))


def _digest(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError('Snapshot input must be a regular file: ' + str(path))
    value = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def _root(path):
    path = Path(os.path.abspath(path))
    if any(p.is_symlink() for p in (path, *path.parents)) or not path.is_dir():
        raise ValueError('Storage run must be a real directory without linked parents')
    return path


def _publish(path, value):
    fd, name = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(value, stream, sort_keys=True, indent=2)
            stream.write('\n')
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
        _sync_directory(path.parent)
    finally:
        Path(name).unlink(missing_ok=True)


def _sync_directory(path):
    directory = os.open(path, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0))
    try:
        os.fsync(directory)
    finally:
        os.close(directory)


def _stopped(root):
    path = root / 'execution.json'
    initial = path.lstat()
    identity = snapshot_store._signature(initial)
    execution = _json(path)
    if snapshot_store._signature(path.lstat()) != identity:
        raise ValueError('Execution receipt changed while checking stopped processes')
    if (not isinstance(execution, dict) or execution.get('status') not in ('completed', 'failed')
            or not isinstance(execution.get('processes'), dict) or not execution['processes']):
        raise ValueError('Storage requires an executed, stopped native run')
    reused = []
    for process in execution['processes'].values():
        if (not isinstance(process, dict) or type(process.get('pid')) is not int or process['pid'] <= 0
                or type(process.get('exit_code')) is not int):
            raise ValueError('Storage requires recorded exit codes for every process')
        try:
            os.kill(process['pid'], 0)
        except ProcessLookupError:
            continue
        except PermissionError:
            pass  # EPERM proves liveness, not identity; require the same reuse proof below.
        receipt = _digest(path)
        cutoff = max(initial.st_mtime_ns, initial.st_ctime_ns)
        if (snapshot_store._signature(path.lstat()) != identity
                or not admission.host.process_started_after(process['pid'], cutoff)
                or snapshot_store._signature(path.lstat()) != identity or _digest(path) != receipt):
            raise ValueError('Recorded native PID is still alive without proven reuse; storage refused')
        reused.append({'pid': process['pid'], 'execution_sha256': receipt, 'receipt_timestamp_ns': cutoff})
    if snapshot_store._signature(path.lstat()) != identity:
        raise ValueError('Execution receipt changed while checking stopped processes')
    execution['_storage_pid_reuse'] = reused
    return execution


def _overlaps(a, b):
    return a.is_relative_to(b) or b.is_relative_to(a)


@contextmanager
def _maintenance(root):
    """Same profile lease and legacy lock as preparation/launch; no waiting/retries."""
    held = getattr(_local, 'held', set())
    if root in held:
        yield
        return
    if admission.fcntl is None:
        raise ValueError('Native snapshot maintenance requires qualified POSIX admission locks')
    admission._directory()
    with ExitStack() as stack:
        pinned = root in getattr(_local, 'pins', set())
        legacy = None if held else stack.enter_context(admission.LEGACY_LOCK.open('a+'))
        try:
            if legacy is not None:
                admission.fcntl.flock(legacy, admission.fcntl.LOCK_EX | admission.fcntl.LOCK_NB)
            # Reconcile dead owners before our own profile lease can look like theirs.
            with admission._locked():
                _reconcile()
            lease = None if pinned else stack.enter_context((admission.STATE / (admission._key(root) + '.lease')).open('a+'))
            if lease is not None:
                admission.fcntl.flock(lease, admission.fcntl.LOCK_EX | admission.fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError('Native work owns a lease; snapshot maintenance refused') from error
        with admission._locked():
            sample = admission.host.sample()
            records = admission._records(sample) + admission._preparations() + admission._timings() + admission._waiters()
            if any(_overlaps(root, Path(row['root'])) for row in records):
                raise RuntimeError('Snapshot has a prepared, running or waiting reservation')
            from . import adapters
            roles = [str(root / role) for role in adapters.roles(_json(root / 'selection.json'))]
            if admission.owned({'caches': roles}, sample):
                raise RuntimeError('An owned native process still uses this snapshot')
        _local.held = held | {root}
        try:
            with snapshot_store.verified_payloads():
                yield
        finally:
            _local.held = held


def _reconcile():
    admission._records(admission.host.sample())
    admission._preparations()
    admission._timings()
    admission._waiters()


@contextmanager
def store_maintenance():
    """Quiesce native users before changing descriptor container encoding."""
    if getattr(_local, 'held', set()):
        yield
        return
    if admission.fcntl is None:
        raise ValueError('Native store maintenance requires POSIX admission locks')
    admission._directory()
    with admission.LEGACY_LOCK.open('a+') as stream:
        try:
            admission.fcntl.flock(stream, admission.fcntl.LOCK_EX | admission.fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError('Native work owns a lease; store maintenance refused') from error
        yield


def _binding(root, value=None):
    value = _json(root / MARKER) if value is None else value
    if (not isinstance(value, dict) or set(value) != {'schema_version', 'store', 'snapshot_sha256', 'trees'}
            or type(value['schema_version']) is not int or value['schema_version'] != 1
            or not isinstance(value['store'], str) or not Path(value['store']).is_absolute()
            or Path(value['store']).resolve().is_relative_to(root)
            or value['snapshot_sha256'] != _digest(root / 'snapshot-hashes.json')
            or not isinstance(value['trees'], dict) or not value['trees']):
        raise ValueError('Invalid or changed native snapshot storage binding')
    from . import adapters
    roles = adapters.roles(_json(root / 'selection.json'))
    for name, object_id in value['trees'].items():
        parts = name.split('/') if isinstance(name, str) else []
        if (len(parts) != 3 or parts[0] not in roles or parts[1] != 'mods'
                or parts[2] in ('', '.', '..') or '\\' in parts[2]
                or not isinstance(object_id, str) or not _ID.fullmatch(object_id)):
            raise ValueError('Invalid archived mod-tree identity')
        _owned_parents(root, name)
    return value


def _owned_parents(root, name):
    for part in (root / name, *(root / name).parents):
        if part == root:
            break
        if part.is_symlink():
            raise ValueError('Linked snapshot input ancestor: ' + str(part))


def _tree_hashes(root, name, value):
    path = root / name
    if path.is_symlink() or not path.is_dir():
        raise ValueError('Retained mod tree is not a directory: ' + name)
    snapshot_store.verify_tree(path, value)
    return {name + '/' + key: sha for key, sha in snapshot_store.hashes(value).items()}


def _verify(root, binding):
    frozen = _json(root / 'snapshot-hashes.json')
    if not isinstance(frozen, dict) or not frozen:
        raise ValueError('Invalid native snapshot seal')
    archived = {}
    manifests = {}
    for name, object_id in binding['trees'].items():
        value = snapshot_store.verify(binding['store'], object_id)
        actual = {name + '/' + relative: sha for relative, sha in snapshot_store.hashes(value).items()}
        expected = {key: sha for key, sha in frozen.items() if key.startswith(name + '/')}
        if actual != expected:
            raise ValueError('Archive differs from sealed mod bytes: ' + name)
        if (root / name).exists() or (root / name).is_symlink():
            if _tree_hashes(root, name, value) != actual:
                raise ValueError('Retained mod tree differs from archive: ' + name)
        archived.update(actual)
        manifests[name] = value
    for name, sha in frozen.items():
        if name not in archived:
            path = root / name
            if Path(name).is_absolute() or '..' in Path(name).parts or not path.resolve().is_relative_to(root):
                raise ValueError('Unsafe sealed input path')
            if _digest(path) != sha:
                raise ValueError('Changed sealed input: ' + name)
    # Still reject additions to unarchived trees and loose mod-root files.
    from . import adapters
    actual = set(archived)
    for role in adapters.roles(_json(root / 'selection.json')):
        for sub in ('mods', 'classes'):
            directory = root / role / sub
            if directory.is_symlink():
                raise ValueError('Linked snapshot input directory')
            for path in directory.rglob('*'):
                if path.is_symlink():
                    raise ValueError('Linked snapshot input')
                if path.is_file():
                    actual.add(path.relative_to(root).as_posix())
    expected = {name for name in frozen if any(name.startswith(role + '/' + sub + '/')
                for role in adapters.roles(_json(root / 'selection.json')) for sub in ('mods', 'classes'))}
    if actual != expected:
        raise ValueError('Archived native frozen file set differs')
    return manifests


def verify(run):
    """Verify archived and retained sealed inputs without materializing mod trees."""
    root = _root(run)
    with _maintenance(root):
        binding = _binding(root)
        _verify(root, binding)
        return {'status': 'verified', 'run': str(root), 'trees': binding['trees'], 'store': binding['store']}


def _references(root, scan_roots):
    return _reference_map([root], scan_roots)[root]


def _reference_map(roots, scan_roots):
    with progress.Phase('snapshot-dependencies'):
        return _scan_reference_map(roots, scan_roots)


def _scan_reference_map(roots, scan_roots):
    """Known historical source consumers stay unpacked during the migration."""
    references = {root: set() for root in roots}
    resolved_sources, resolved_parents = {}, {}
    root_names = {root: str(root) for root in roots}
    for scan in scan_roots:
        scan = Path(scan).resolve()
        if not scan.is_dir():
            raise ValueError('Dependency scan root is missing: ' + str(scan))
        for directory, names, files in os.walk(scan, followlinks=False):
            names[:] = [name for name in names if name not in {
                '.git', 'node_modules', '.snapshot-retiring', '.snapshot-restoring'}
                and not (Path(directory) / name).is_symlink()]
            if 'runtime.json' in files and 'selection.json' in files:
                names[:] = [name for name in names if name not in ('client1', 'client2', 'server')]
            for filename in files:
                if not filename.endswith('.json'):
                    continue
                path = Path(directory) / filename
                progress.file(path)
                if path.is_symlink():
                    continue
                try:
                    if filename in ('source-manifest.json', 'manifest.json'):
                        value = _json(path)
                    else:
                        if not path.is_file():
                            continue
                        text = path.read_text(encoding='utf-8')
                        # Skip large hash maps/reports without any supported dependency field.
                        # Escaped key spellings fall back to the full JSON parser.
                        if not any(token in text for token in ('"mods"', '"mod_sources"', '"source_run"', '"seed_run"', '\\u')):
                            continue
                        value = json.loads(text)
                except (OSError, ValueError) as error:
                    if filename in ('source-manifest.json', 'manifest.json'):
                        raise ValueError('Cannot establish source dependencies: ' + str(path)) from error
                    continue
                sources = list(value) if filename == 'source-manifest.json' and isinstance(value, dict) else []
                rows = value.get('mods', []) if isinstance(value, dict) else value
                if isinstance(rows, list):
                    sources += [row['source'] for row in rows if isinstance(row, dict) and isinstance(row.get('source'), str)]
                if isinstance(value, dict):
                    options = value.get('options', {})
                    if isinstance(options, dict) and isinstance(options.get('mod_sources'), dict):
                        sources.extend(options['mod_sources'].values())
                    sources.extend(value[key] for key in ('source_run', 'seed_run') if isinstance(value.get(key), str))
                for source in sources:
                    if not isinstance(source, str) or not os.path.isabs(source):
                        continue
                    if source not in resolved_sources:
                        resolved = _canonical_source(source, resolved_parents)
                        matches = tuple(root for root, name in root_names.items() if resolved == name or resolved.startswith(name + os.sep))
                        resolved_sources[source] = (resolved, matches)
                    resolved, matches = resolved_sources[source]
                    for root in matches:
                        if path.parent != root:
                            references[root].add(resolved)
    return references


def _default_scan(root):
    scans, project = [root.parent], None
    for parent in root.parents:
        if parent.name == '.codex':
            scans = [parent]
        if (parent / '.git').exists():
            project = parent
            break
    # Older worktrees can still run code without archive-aware source resolution.
    if project is not None:
        try:
            result = subprocess.run(['git', '--no-optional-locks', '-C', str(project),
                                     'worktree', 'list', '--porcelain', '-z'],
                                    capture_output=True, check=True, timeout=15)
        except (OSError, subprocess.SubprocessError) as error:
            raise RuntimeError('Cannot establish linked-worktree source dependencies') from error
        for field in os.fsdecode(result.stdout).split('\0'):
            if field.startswith('worktree '):
                path = Path(field[len('worktree '):]) / '.codex'
                if path.is_dir():
                    scans.append(path)
    return list(dict.fromkeys(scans))


def _retire(root, binding, names):
    # Atomic rename makes an interrupted retirement distinguishable from tampering.
    retired = root / '.snapshot-retiring'
    if retired.is_symlink():
        raise ValueError('Linked snapshot retirement journal')
    if retired.exists():
        allowed_files, allowed_dirs = {}, set()
        for name, object_id in binding['trees'].items():
            value = snapshot_store.manifest(binding['store'], object_id)
            for relative, sha in snapshot_store.hashes(value).items():
                allowed_files[name + '/' + relative] = sha
            for relative in [name, *[name + '/' + p for p in value['directories']]]:
                path = Path(relative)
                allowed_dirs.update(str(p) for p in (path, *path.parents) if str(p) != '.')
        for path in retired.rglob('*'):
            relative = path.relative_to(retired).as_posix()
            mode = path.lstat().st_mode
            if not (stat.S_ISDIR(mode) or stat.S_ISREG(mode)) or (path.is_dir() and relative not in allowed_dirs):
                raise ValueError('Unexpected retirement journal entry')
            if path.is_file() and (relative not in allowed_files or _digest(path) != allowed_files[relative]):
                raise ValueError('Changed retirement journal entry')
        _erase_retired(retired)
    retired.mkdir(exist_ok=True)
    for name in names:
        source = root / name
        target = retired / name
        if source.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists():
                raise ValueError('Retirement journal already contains a tree: ' + name)
            source.rename(target)
    # Only remove trees named by the verified binding. Never sweep other run data.
    for name in binding['trees']:
        target = retired / name
        if target.exists():
            if target.is_symlink():
                raise ValueError('Linked retired tree')
            _erase_retired(target)
    for directory in sorted(retired.rglob('*'), key=lambda p: len(p.parts), reverse=True):
        if directory.is_dir():
            directory.rmdir()
    retired.rmdir()


def _erase_retired(path):
    # The archived original metadata is retained; permit deletion of readonly dirs.
    for parent, _, _ in os.walk(path, followlinks=False):
        os.chmod(parent, 0o700)
    shutil.rmtree(path)


def compact(run, store=None, *, apply=False, dependency_roots=()):
    """Preview by default; apply publishes all recoverable archives before retirement."""
    root = _root(run)
    if root in getattr(_local, 'pins', set()):
        raise RuntimeError('A source consumer pins this snapshot')
    with _maintenance(root):
        stopped = _stopped(root)
        previous = _binding(root) if os.path.lexists(root / MARKER) else None
        if previous:
            _verify(root, previous)
            if store is not None and Path(store).resolve() != Path(previous['store']).resolve():
                raise ValueError('Snapshot is bound to another store; keep its original store available')
            store = previous['store']
        if store is None:
            raise ValueError('An explicit shared snapshot store is required')
        store = Path(store).absolute()
        if store.resolve().is_relative_to(root) or any(p.is_symlink() for p in (store, *store.parents)):
            raise ValueError('Snapshot store must be outside the run, without linked parents')
        from . import adapters, report
        if not previous:
            issues = report.verify_manifest(root, 'snapshot-hashes.json')
            if issues:
                first = issues[0]
                summary = first if len(first) <= 1024 else first[:1024] + '...'
                raise ValueError(f'Cannot compact changed snapshot: {len(issues)} issues; first: {summary}')
        grouped = getattr(_local, 'group_references', {}).get(root)
        if grouped is None:
            scans = list(dict.fromkeys([*_default_scan(root), *map(Path, dependency_roots)]))
            refs = _references(root, scans)
        else:
            refs, scans = grouped
        trees = dict(previous['trees']) if previous else {}
        candidates, protected = [], []
        for role in adapters.roles(_json(root / 'selection.json')):
            mods = root / role / 'mods'
            _owned_parents(root, role + '/mods')
            for path in sorted(mods.iterdir()):
                if path.is_symlink():
                    raise ValueError('Linked mod-tree input')
                if not path.is_dir():
                    continue
                name = path.relative_to(root).as_posix()
                if any(_overlaps(path, Path(ref)) for ref in refs):
                    protected.append(name)
                else:
                    candidates.append(name)
        before = shutil.disk_usage(root).free
        result = {'status': 'preview', 'run': str(root), 'store': str(store),
                  'eligible': candidates, 'protected_sources': protected,
                  'dependency_roots': [str(Path(p).resolve()) for p in scans],
                  'logical_bytes': sum(p.stat().st_size for name in candidates for p in (root / name).rglob('*') if p.is_file()),
                  'free_bytes_before': before, 'pid_reuse': stopped['_storage_pid_reuse']}
        if not apply:
            return result
        for name in candidates:
            trees[name] = snapshot_store.capture(root / name, store)
        if not trees:
            return dict(result, status='unchanged', free_bytes_after=shutil.disk_usage(root).free)
        binding = {'schema_version': 1, 'store': str(store),
                   'snapshot_sha256': _digest(root / 'snapshot-hashes.json'), 'trees': trees}
        _verify(root, binding)
        _publish(root / MARKER, binding)
        _retire(root, binding, candidates)
        _verify(root, binding)
        after = shutil.disk_usage(root).free
        return dict(result, status='compacted', free_bytes_after=after,
                    observed_free_bytes_change=after - before,
                    note='Filesystem-wide free-space change includes concurrent unrelated writes and shared blocks.')


def _restore(root, binding):
    manifests = _verify(root, binding)
    staging = root / '.snapshot-restoring'
    for name in manifests:
        _owned_parents(root, '.snapshot-restoring/' + name)
    for name in manifests:
        target = root / name
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            staged = staging / name
            staged.parent.mkdir(parents=True, exist_ok=True)
            if staged.exists():
                snapshot_store.verify_tree(staged, manifests[name])
            else:
                snapshot_store.materialize(binding['store'], binding['trees'][name], staged)
            staged.rename(target)
            _sync_directory(target.parent)
            _sync_directory(staged.parent)
    _verify(root, binding)
    # Hard-kill residue stays outside sealed input trees; never sweep unknown files.
    parents = {staging}
    for name in manifests:
        parent = (staging / name).parent
        while parent.is_relative_to(staging):
            parents.add(parent)
            if parent == staging:
                break
            parent = parent.parent
    for parent in sorted(parents, key=lambda p: len(p.parts), reverse=True):
        if not parent.exists():
            continue
        try:
            parent.rmdir()
        except OSError as error:
            if error.errno not in (errno.ENOTEMPTY, errno.EEXIST):
                raise


def restore(run):
    """Restore archived paths in place without changing sealed manifests or archives."""
    root = _root(run)
    with _maintenance(root):
        _stopped(root)
        binding = _binding(root)
        _restore(root, binding)
        return {'status': 'restored', 'run': str(root), 'trees': binding['trees']}


@contextmanager
def available(run):
    """Physical-input consumers get temporary exact trees; static reports stay retained."""
    root = Path(run).resolve()
    if not os.path.lexists(root / MARKER):
        yield
        return
    if root in getattr(_local, 'pins', set()):
        binding = _binding(root)
        _verify(root, binding)
        yield
        _verify(root, binding)
        return
    with _maintenance(root):
        _stopped(root)
        binding = _binding(root)
        missing = [name for name in binding['trees'] if not (root / name).exists()]
        _restore(root, binding)
        try:
            yield
        finally:
            # A verifier that changes restored inputs cannot cause them to be discarded.
            _verify(root, binding)
            if missing:
                _retire(root, binding, missing)


def with_inputs(function):
    @wraps(function)
    def call(root, *args, **kwargs):
        with available(root):
            return function(root, *args, **kwargs)
    return call


def _canonical_source(value, parents):
    parent, name = os.path.split(value)
    if parent not in parents:
        parents[parent] = str(Path(parent).resolve())
    resolved = os.path.normpath(os.path.join(parents[parent], name))
    return str(Path(resolved).resolve()) if os.path.islink(resolved) else resolved


def _source_owners(paths):
    candidates, parents = set(), {}
    for value in paths:
        if not isinstance(value, (str, os.PathLike)):
            continue
        path = Path(value)
        if not path.is_absolute():
            continue
        path = Path(_canonical_source(os.fspath(path), parents))
        if path.is_dir():
            candidates.add(path)
        candidates.update(path.parents)
    return {path for path in candidates if os.path.lexists(path / MARKER) or all(
        (path / name).is_file() for name in ('selection.json', 'runtime.json', 'snapshot-hashes.json'))}


@contextmanager
def source_inputs(paths):
    """Pin archived source roots through all caller reads, including admission handoff."""
    owners = _source_owners(paths)
    pending = list(owners)
    while pending:
        owner = pending.pop()
        manifest = owner / 'source-manifest.json'
        if manifest.is_file():
            discovered = _source_owners(_json(manifest)) - owners
            owners.update(discovered)
            pending.extend(discovered)
    if admission.fcntl is None:
        if any(os.path.lexists(owner / MARKER) for owner in owners):
            raise ValueError('Archived native sources require qualified POSIX maintenance')
        # This platform cannot compact sources, so legacy raw-source readers need no new lease.
        yield
        return
    previous = getattr(_local, 'pins', set())
    already_held = getattr(_local, 'held', set())
    fresh = owners - previous - already_held
    with ExitStack() as stack:
        if fresh:
            if admission.fcntl is None:
                raise ValueError('Archived source leases require POSIX admission locks')
            admission._directory()
            with admission._locked():
                _reconcile()
        for owner in sorted(fresh):
            lease = stack.enter_context((admission.STATE / (admission._key(owner) + '.lease')).open('a+'))
            try:
                admission.fcntl.flock(lease, admission.fcntl.LOCK_EX | admission.fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise RuntimeError('Archived source is leased by another consumer') from error
        _local.pins = previous | fresh
        try:
            for owner in sorted(owners):
                if not os.path.lexists(owner / MARKER):
                    continue
                binding = _binding(owner)
                if any(not (owner / name).exists() for name in binding['trees']):
                    restore(owner)
            yield
        finally:
            _local.pins = previous


def restore_sources(paths):
    """Explicitly restore source paths; consumers use source_inputs for a lifetime pin."""
    with source_inputs(paths):
        pass


@contextmanager
def selection_inputs(selection, workshop=()):
    options = selection.get('options', {})
    if not isinstance(options, dict):
        yield
        return
    paths = list(workshop)
    sources = options.get('mod_sources', {})
    if isinstance(sources, dict):
        paths.extend(value for value in sources.values() if isinstance(value, str))
    if isinstance(options.get('seed_run'), str):
        paths.append(options['seed_run'])
    if isinstance(options.get('pack_lock'), str):
        from . import pack
        paths.extend(row['source'] for row in pack.read(options['pack_lock'])['mods'])
    with source_inputs(paths):
        yield


def with_run_sources(function):
    @wraps(function)
    def call(root, *args, **kwargs):
        path = Path(root) / 'source-manifest.json'
        paths = _json(path) if path.is_file() else []
        with source_inputs(paths):
            return function(root, *args, **kwargs)
    return call


def with_manifest_sources(function):
    @wraps(function)
    def call(root, filename, absolute=False):
        path = Path(root) / filename
        if not absolute or not path.is_file() or path.is_symlink():
            return function(root, filename, absolute)
        value = _json(path)
        with source_inputs(value if isinstance(value, dict) else []):
            return function(root, filename, absolute)
    return call


def after_report(run, store):
    """Optional lifecycle hook; archival failure never destroys a saved test verdict."""
    root = Path(run).resolve()
    try:
        execution = _json(root / 'execution.json')
        if isinstance(execution, dict) and execution.get('interrupted'):
            value = {'status': 'deferred', 'reason': 'Execution was interrupted; raw inputs retained'}
        else:
            value = compact(root, store, apply=True)
    except (OSError, ValueError, RuntimeError) as error:
        value = {'status': 'deferred', 'reason': str(error)}
    try:
        _publish(root / 'storage-maintenance.json', value)
    except (OSError, ValueError, RuntimeError) as error:
        value = dict(value, maintenance_error=str(error))
    return value


def _group_paths(runs, store, report_path):
    roots = sorted({_root(run) for run in runs})
    if not roots:
        raise ValueError('Snapshot compaction group must not be empty')
    store = Path(os.path.abspath(store))
    if any(path.is_symlink() for path in (store, *store.parents)) or any(store.is_relative_to(root) for root in roots):
        raise ValueError('Group store must be outside every selected run without linked parents')
    device = roots[0].stat().st_dev
    probe = store
    while not probe.exists():
        probe = probe.parent
    if probe.stat().st_dev != device or any(root.stat().st_dev != device for root in roots):
        raise ValueError('Group storage observations require runs and store on one filesystem')
    if report_path is not None:
        report_path = Path(os.path.abspath(report_path))
        if (any(path.is_symlink() for path in (report_path, *report_path.parents))
                or any(report_path.is_relative_to(root) for root in roots)
                or report_path.is_relative_to(store)):
            raise ValueError('Group report must be outside selected runs and store without linked parents')
    return roots, store, report_path


def after_group_report(runs, store, report_path, *, interrupted=False):
    """One retirement after batch accounting; never delay an interrupted command."""
    try:
        roots, store, path = _group_paths(runs, store, report_path)
        if os.path.lexists(path):
            raise FileExistsError('Fresh group maintenance report required')
        if interrupted:
            value = {'status': 'deferred', 'reason': 'Batch was interrupted; raw inputs retained'}
            path.parent.mkdir(parents=True, exist_ok=True)
            descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0), 0o600)
            os.close(descriptor)
            _publish(path, value)
            return value
        return compact_group(roots, store, apply=True, report_path=path)
    except (OSError, ValueError, RuntimeError) as error:
        # compact_group owns its partial ledger; a failed exclusive claim may
        # belong to another operation, so this wrapper must never rewrite it.
        return {'status': 'deferred', 'reason': str(error)}


def compact_group(runs, store, *, apply=False, dependency_roots=(), report_path=None):
    """Hold all profile guards and scan dependencies once for an explicit historical cohort."""
    roots, store, report_path = _group_paths(runs, store, report_path)
    if report_path is not None:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        descriptor = os.open(report_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0), 0o600)
        os.close(descriptor)
    result = {'schema_version': 1, 'status': 'preview' if not apply else 'running',
              'store': str(Path(store).absolute()), 'runs': [], 'blocked': [],
              'remaining': [str(root) for root in roots]}
    def save():
        if report_path is not None:
            _publish(report_path, result)
    save()
    candidates = []
    for root in roots:
        try:
            _stopped(root)
        except (OSError, ValueError) as error:
            result['blocked'].append({'run': str(root), 'reason': str(error)})
        else:
            candidates.append(root)
    if not candidates:
        result.update(status='blocked', remaining=[])
        save()
        return result
    with ExitStack() as stack:
        admitted = []
        for root in candidates:
            try:
                stack.enter_context(_maintenance(root))
                _stopped(root)
            except (OSError, ValueError, RuntimeError) as error:
                # No group owns the legacy lease yet: don't retry global contention per root.
                if not getattr(_local, 'held', set()):
                    result.update(status='blocked', reason=str(error))
                    save()
                    return result
                result['blocked'].append({'run': str(root), 'reason': str(error)})
            else:
                admitted.append(root)
        scans, scan_bases = list(map(Path, dependency_roots)), set()
        for root in admitted:
            base = next((parent for parent in root.parents if parent.name == '.codex'), root.parent)
            if base not in scan_bases:
                scans.extend(_default_scan(root))
                scan_bases.add(base)
        scans = sorted({path.resolve() for path in scans})
        scans = [path for path in scans if not any(path != other and path.is_relative_to(other) for other in scans)]
        references = _reference_map(admitted, scans)
        previous = getattr(_local, 'group_references', {})
        try:
            _local.group_references = {root: (references[root], scans) for root in admitted}
            result['free_bytes_before'] = shutil.disk_usage(roots[0]).free
            save()
            for index, root in enumerate(admitted):
                with progress.Phase('compact-historical-snapshot', run=root.name):
                    try:
                        item = compact(root, store, apply=apply, dependency_roots=dependency_roots)
                    except (snapshot_store.SnapshotStoreError, OSError) as error:
                        result.update(status='stopped', reason=str(error), remaining=[str(p) for p in admitted[index:]])
                        save()
                        return result
                    except (ValueError, RuntimeError) as error:
                        result['blocked'].append({'run': str(root), 'reason': str(error)})
                    else:
                        result['runs'].append(item)
                    result['remaining'] = [str(p) for p in admitted[index + 1:]]
                    result['free_bytes_after'] = shutil.disk_usage(roots[0]).free
                    save()
        except BaseException as error:
            result['status'] = 'interrupted' if isinstance(error, (KeyboardInterrupt, SystemExit)) else 'failed'
            save()
            raise
        finally:
            _local.group_references = previous
        result.update(status='partial' if result['blocked'] else 'compacted' if apply else 'preview', remaining=[])
        result['observed_free_bytes_change'] = result['free_bytes_after'] - result['free_bytes_before'] if result['runs'] else 0
        result['note'] = 'Filesystem-wide free-space observations include delayed reclamation and unrelated writes; logical bytes are not recovered bytes.'
        save()
        return result
