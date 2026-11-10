"""Immutable, verified, content-addressed archives of complete native mod trees."""
from contextlib import contextmanager
import gzip
import hashlib
import json
import ntpath
import os
from pathlib import Path
import re
import shutil
import stat
import tarfile
import tempfile


class SnapshotStoreError(ValueError):
    """An unsafe, changed, missing, or corrupt snapshot cannot be used."""


_ID = re.compile(r'[0-9a-f]{64}\Z')
_CHUNK = 1024 * 1024
_WINDOWS_RESERVED = {'CON', 'PRN', 'AUX', 'NUL',
                     *(f'COM{i}' for i in range(1, 10)), *(f'LPT{i}' for i in range(1, 10))}


def _canonical(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=True, separators=(',', ':')).encode('ascii')


def _path(value):
    if (not isinstance(value, str) or not value or '\\' in value or '\x00' in value
            or ':' in value or ntpath.splitdrive(value)[0]
            or any(p in ('', '.', '..') or p.endswith((' ', '.'))
                   or p.split('.')[0].upper() in _WINDOWS_RESERVED
                   for p in value.split('/'))):
        raise SnapshotStoreError(f'Invalid snapshot path: {value!r}')
    return value


def _integer(value, minimum=None):
    return type(value) is int and (minimum is None or value >= minimum)


def _attrs(value, file=False):
    keys = {'mode', 'mtime_ns'} | ({'size', 'sha256'} if file else set())
    if (not isinstance(value, dict) or set(value) != keys
            or not _integer(value['mode'], 0) or value['mode'] > 0o7777
            or not _integer(value['mtime_ns'])):
        raise SnapshotStoreError('Invalid snapshot metadata')
    if file and (not _integer(value['size'], 0) or not isinstance(value['sha256'], str)
                 or not _ID.fullmatch(value['sha256'])):
        raise SnapshotStoreError('Invalid snapshot file metadata')


def _payload_id(value):
    content = {
        'files': {name: {key: attrs[key] for key in ('sha256', 'size', 'mode')}
                  for name, attrs in value['files'].items()},
        'directories': {name: {'mode': attrs['mode']}
                        for name, attrs in value['directories'].items()},
    }
    return hashlib.sha256(_canonical(content)).hexdigest()


def _validate(value):
    if (not isinstance(value, dict) or set(value) not in (
            {'schema_version', 'files', 'directories', 'payload_id'},
            {'schema_version', 'files', 'directories', 'payload_id', 'root'})
            or type(value['schema_version']) is not int or value['schema_version'] != 1
            or not isinstance(value['files'], dict) or not isinstance(value['directories'], dict)):
        raise SnapshotStoreError('Invalid snapshot manifest')
    if 'root' in value:
        _attrs(value['root'])
    names = set()
    for kind in ('files', 'directories'):
        for name, attrs in value[kind].items():
            _path(name)
            if name in names:
                raise SnapshotStoreError(f'Duplicate snapshot path: {name}')
            names.add(name)
            _attrs(attrs, file=kind == 'files')
    for name in names:
        parent = name.rpartition('/')[0]
        if parent and parent not in value['directories']:
            raise SnapshotStoreError(f'Missing snapshot parent directory: {parent}')
    if (not isinstance(value['payload_id'], str) or not _ID.fullmatch(value['payload_id'])
            or value['payload_id'] != _payload_id(value)):
        raise SnapshotStoreError('Invalid snapshot payload id')
    return value


def hashes(value):
    """Return the byte hashes recorded by a validated manifest."""
    return {name: attrs['sha256'] for name, attrs in _validate(value)['files'].items()}


def _signature(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns, info.st_ctime_ns)


def _metadata(info):
    return {'mode': stat.S_IMODE(info.st_mode), 'mtime_ns': info.st_mtime_ns}


def _scan(tree):
    result = {}

    def visit(path, name):
        info = path.lstat()
        if not (stat.S_ISDIR(info.st_mode) or stat.S_ISREG(info.st_mode)):
            raise SnapshotStoreError(f'Snapshot source contains a link or special file: {path}')
        result[name] = info
        if stat.S_ISDIR(info.st_mode):
            with os.scandir(path) as entries:
                children = sorted(entries, key=lambda e: e.name)
            for entry in children:
                child = f'{name}/{entry.name}' if name else entry.name
                _path(child)
                visit(path / entry.name, child)

    visit(tree, '')
    if not stat.S_ISDIR(result[''].st_mode):
        raise SnapshotStoreError('Snapshot source must be a directory')
    return result


def _regular(path):
    try:
        if not stat.S_ISREG(path.lstat().st_mode):
            raise SnapshotStoreError(f'Snapshot store member is not a regular file: {path}')
    except FileNotFoundError as exc:
        raise SnapshotStoreError(f'Missing snapshot store member: {path}') from exc


def _fsync_directory(path):
    """Persist directory entry changes before callers may retire source bytes."""
    if os.name != 'posix':
        raise SnapshotStoreError('Durable snapshot publication requires POSIX directory fsync')
    descriptor = os.open(path, os.O_RDONLY | getattr(os, 'O_DIRECTORY', 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


@contextmanager
def _lock(store):
    store = Path(store).absolute()
    missing = []
    parent = store
    while not parent.exists():
        missing.append(parent)
        parent = parent.parent
    store.mkdir(parents=True, exist_ok=True)
    for created in reversed(missing):
        _fsync_directory(created.parent)
    if store.is_symlink() or not store.is_dir():
        raise SnapshotStoreError('Snapshot store must be a real directory')
    objects = store / 'objects'
    objects.mkdir(exist_ok=True)
    if objects.is_symlink() or not objects.is_dir():
        raise SnapshotStoreError('Snapshot objects must be a real directory')
    payloads = store / 'payloads'
    payloads.mkdir(exist_ok=True)
    if payloads.is_symlink() or not payloads.is_dir():
        raise SnapshotStoreError('Snapshot payloads must be a real directory')
    _fsync_directory(store)
    fd = os.open(store / '.lock', os.O_RDWR | os.O_CREAT | getattr(os, 'O_NOFOLLOW', 0), 0o600)
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise SnapshotStoreError('Snapshot lock must be a regular file')
        if os.name == 'posix':
            import fcntl
            fcntl.flock(fd, fcntl.LOCK_EX)
        elif os.name == 'nt':
            import msvcrt
            if os.fstat(fd).st_size == 0:
                os.write(fd, b'\0')
            os.lseek(fd, 0, os.SEEK_SET)
            msvcrt.locking(fd, msvcrt.LK_LOCK, 1)
        else:
            raise SnapshotStoreError('Snapshot store locking is unsupported on this platform')
        yield objects
    finally:
        os.close(fd)


def _paths(objects, object_id):
    if not isinstance(object_id, str) or not _ID.fullmatch(object_id):
        raise SnapshotStoreError('Invalid snapshot object id')
    return objects / f'{object_id}.json'


def _archive_path(objects, value):
    return objects.parent / 'payloads' / f"{value['payload_id']}.tar.gz"


def _unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise SnapshotStoreError(f'Duplicate manifest entry: {key}')
        result[key] = value
    return result


def _read(objects, object_id):
    sidecar = _paths(objects, object_id)
    _regular(sidecar)
    try:
        value = _validate(json.loads(sidecar.read_bytes(), object_pairs_hook=_unique))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise SnapshotStoreError('Unreadable snapshot manifest') from exc
    if hashlib.sha256(_canonical(value)).hexdigest() != object_id:
        raise SnapshotStoreError('Snapshot manifest does not match object id')
    archive = _archive_path(objects, value)
    _regular(archive)
    return value, archive


def _stream(archive, value, destination=None):
    expected = value['files'].keys() | value['directories'].keys()
    seen = set()
    try:
        with gzip.open(archive, 'rb') as compressed, tarfile.open(fileobj=compressed, mode='r|') as stream:
            for member in stream:
                name = _path(member.name)
                if name in seen or name not in expected:
                    raise SnapshotStoreError(f'Unexpected or duplicate archive member: {name}')
                seen.add(name)
                directory = name in value['directories']
                attrs = value['directories' if directory else 'files'][name]
                if ((directory and member.type != tarfile.DIRTYPE)
                        or (not directory and member.type not in (tarfile.REGTYPE, tarfile.AREGTYPE))
                        or member.sparse is not None
                        or member.issym() or member.islnk() or member.mode != attrs['mode']
                        or (directory and member.size != 0)
                        or (not directory and member.size != attrs['size'])):
                    raise SnapshotStoreError(f'Archive type, size, or mode mismatch: {name}')
                if directory:
                    if destination is not None:
                        (destination / name).mkdir(exist_ok=True)
                    continue
                digest = hashlib.sha256()
                size = 0
                output = None
                try:
                    if destination is not None:
                        target = destination / name
                        target.parent.mkdir(parents=True, exist_ok=True)
                        output = target.open('xb')
                    with stream.extractfile(member) as source:
                        while chunk := source.read(_CHUNK):
                            size += len(chunk)
                            if size > attrs['size']:
                                raise SnapshotStoreError(f'Archive file too large: {name}')
                            digest.update(chunk)
                            if output is not None:
                                output.write(chunk)
                finally:
                    if output is not None:
                        output.close()
                if size != attrs['size'] or digest.hexdigest() != attrs['sha256']:
                    raise SnapshotStoreError(f'Archive content mismatch: {name}')
            # Consume gzip through EOF as well, so a truncated trailer is rejected.
            if stream.fileobj is not None:
                while tail := stream.fileobj.read(_CHUNK):
                    if any(tail):
                        raise SnapshotStoreError('Unexpected data after archive members')
    except (tarfile.TarError, EOFError, OSError) as exc:
        raise SnapshotStoreError(f'Unreadable snapshot archive: {exc}') from exc
    if seen != expected:
        raise SnapshotStoreError(f'Missing archive members: {sorted(expected - seen)}')


def manifest(store, object_id):
    """Read and validate the addressed manifest (without hashing archive bytes)."""
    with _lock(store) as objects:
        value, _ = _read(objects, object_id)
        return value


def verify(store, object_id):
    """Verify the manifest and every archive byte without extracting files."""
    with _lock(store) as objects:
        value, archive = _read(objects, object_id)
        _stream(archive, value)
        return value


class _HashingReader:
    def __init__(self, source):
        self.source = source
        self.digest = hashlib.sha256()

    def read(self, size):
        data = self.source.read(size)
        self.digest.update(data)
        return data


@contextmanager
def _source(tree, name, info):
    fd = os.open(tree / name, os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0))
    with os.fdopen(fd, 'rb') as source:
        if _signature(os.fstat(source.fileno())) != _signature(info):
            raise SnapshotStoreError(f'Snapshot source changed during capture: {name}')
        yield source
        if _signature(os.fstat(source.fileno())) != _signature(info):
            raise SnapshotStoreError(f'Snapshot source changed during capture: {name}')


def _unchanged(tree, before):
    after = _scan(tree)
    if ({name: _signature(info) for name, info in before.items()}
            != {name: _signature(info) for name, info in after.items()}):
        raise SnapshotStoreError('Snapshot source changed during capture')


def verify_tree(tree, value):
    """Verify complete live membership, bytes and metadata without compression."""
    _validate(value)
    tree = Path(tree)
    before = _scan(tree)
    expected = {''} | value['files'].keys() | value['directories'].keys()
    if set(before) != expected:
        raise SnapshotStoreError('Snapshot tree differs from manifest membership')
    for name, info in before.items():
        if not name:
            attrs = value.get('root')
            if attrs is None:
                continue
        else:
            directory = name in value['directories']
            if directory != stat.S_ISDIR(info.st_mode):
                raise SnapshotStoreError(f'Snapshot tree differs from manifest type: {name}')
            attrs = value['directories' if directory else 'files'][name]
        if _metadata(info) != {key: attrs[key] for key in ('mode', 'mtime_ns')}:
            raise SnapshotStoreError(f'Snapshot tree differs from manifest metadata: {name}')
        if name in value['files']:
            if info.st_size != attrs['size']:
                raise SnapshotStoreError(f'Snapshot tree differs from manifest size: {name}')
            with _source(tree, name, info) as source:
                reader = _HashingReader(source)
                while reader.read(_CHUNK):
                    pass
                if reader.digest.hexdigest() != attrs['sha256']:
                    raise SnapshotStoreError(f'Snapshot tree differs from manifest content: {name}')
    _unchanged(tree, before)
    return value


def capture(tree, store):
    """Capture exact staged metadata, sharing payload bytes across timestamps.

    The returned id addresses objects/<id>.json, whose payload_id addresses
    payloads/<payload_id>.tar.gz. Existing payloads are verified and reused
    without compression; new payloads are rehashed while being archived.
    """
    tree = Path(tree)
    if Path(store).resolve().is_relative_to(tree.resolve()):
        raise SnapshotStoreError('Snapshot store must be outside the source tree')
    before = _scan(tree)
    value = {'schema_version': 1, 'root': _metadata(before['']), 'files': {}, 'directories': {}}
    for name, info in sorted(before.items()):
        if not name:
            continue
        attrs = _metadata(info)
        if stat.S_ISDIR(info.st_mode):
            value['directories'][name] = attrs
        else:
            with _source(tree, name, info) as source:
                reader = _HashingReader(source)
                while reader.read(_CHUNK):
                    pass
                attrs.update(size=info.st_size, sha256=reader.digest.hexdigest())
            value['files'][name] = attrs
    _unchanged(tree, before)
    value['payload_id'] = _payload_id(value)
    _validate(value)
    encoded = _canonical(value)
    object_id = hashlib.sha256(encoded).hexdigest()
    with _lock(store) as objects:
        sidecar = _paths(objects, object_id)
        final_archive = _archive_path(objects, value)
        if os.path.lexists(sidecar):
            existing, existing_archive = _read(objects, object_id)
            _stream(existing_archive, existing)
            _unchanged(tree, before)
            # A prior writer may have crashed between rename and directory fsync.
            _fsync_directory(existing_archive.parent)
            _fsync_directory(sidecar.parent)
            return object_id
        # Publish shared payload first and descriptor last, under one lock.
        # An existing payload is always verified and never overwritten.
        temporary_archive = None
        temporary_manifest = None
        published = []
        try:
            if os.path.lexists(final_archive):
                _regular(final_archive)
                _stream(final_archive, value)
            else:
                fd, name = tempfile.mkstemp(prefix='.archive-', dir=final_archive.parent)
                temporary_archive = Path(name)
                with os.fdopen(fd, 'wb') as target:
                    with tarfile.open(fileobj=target, mode='w:gz', format=tarfile.PAX_FORMAT) as output:
                        for name, info in sorted(before.items()):
                            if not name:
                                continue
                            member = tarfile.TarInfo(name)
                            member.mode = stat.S_IMODE(info.st_mode)
                            member.mtime = 0
                            if stat.S_ISDIR(info.st_mode):
                                member.type = tarfile.DIRTYPE
                                output.addfile(member)
                            else:
                                member.size = info.st_size
                                with _source(tree, name, info) as source:
                                    reader = _HashingReader(source)
                                    output.addfile(member, reader)
                                    if reader.digest.hexdigest() != value['files'][name]['sha256']:
                                        raise SnapshotStoreError(f'Snapshot source changed during capture: {name}')
                    target.flush()
                    os.fsync(target.fileno())
                _stream(temporary_archive, value)
            _unchanged(tree, before)
            if temporary_archive is not None:
                os.rename(temporary_archive, final_archive)
                published.append(final_archive)
            _fsync_directory(final_archive.parent)
            fd, name = tempfile.mkstemp(prefix='.manifest-', dir=objects)
            temporary_manifest = Path(name)
            with os.fdopen(fd, 'wb') as target:
                target.write(encoded)
                target.flush()
                os.fsync(target.fileno())
            os.rename(temporary_manifest, sidecar)
            published.append(sidecar)
            _fsync_directory(sidecar.parent)
        except BaseException:
            for path in published:
                path.unlink(missing_ok=True)
            raise
        finally:
            for path in (temporary_archive, temporary_manifest):
                if path is not None:
                    path.unlink(missing_ok=True)
    return object_id


def _fresh_parent(destination):
    # Reject lexical symlink parents instead of resolving an escape silently.
    destination = Path(os.path.abspath(destination))
    for parent in (destination.parent, *destination.parent.parents):
        if parent.is_symlink():
            raise SnapshotStoreError(f'Snapshot destination parent is a symlink: {parent}')
        if not parent.is_dir():
            raise SnapshotStoreError(f'Snapshot destination parent is missing: {parent}')
    if os.path.lexists(destination):
        raise SnapshotStoreError('Snapshot destination must not exist')
    return destination


def _remove_tree(path):
    os.chmod(path, 0o700)
    for parent, directories, _ in os.walk(path):
        os.chmod(parent, 0o700)
        for directory in directories:
            os.chmod(Path(parent) / directory, 0o700)
    shutil.rmtree(path)


def materialize(store, object_id, destination):
    """Verify and publish a fresh independent tree with an atomic sibling rename."""
    destination = _fresh_parent(destination)
    with _lock(store) as objects:
        value, archive = _read(objects, object_id)
        _stream(archive, value)
        temporary = Path(tempfile.mkdtemp(prefix=f'.{destination.name}.snapshot-', dir=destination.parent))
        published = False
        try:
            # Create all directories up front; archive ordering is not trusted.
            for name in sorted(value['directories'], key=lambda p: (p.count('/'), p)):
                (temporary / name).mkdir()
            _stream(archive, value, temporary)
            actual = _scan(temporary)
            if set(actual) != {''} | value['files'].keys() | value['directories'].keys():
                raise SnapshotStoreError('Materialized snapshot membership mismatch')
            for name, attrs in value['files'].items():
                digest = hashlib.sha256()
                with (temporary / name).open('rb') as source:
                    while chunk := source.read(_CHUNK):
                        digest.update(chunk)
                if digest.hexdigest() != attrs['sha256'] or actual[name].st_size != attrs['size']:
                    raise SnapshotStoreError(f'Materialized snapshot content mismatch: {name}')
            entries = list(value['files'].items())
            entries.extend(sorted(value['directories'].items(), key=lambda p: p[0].count('/'), reverse=True))
            if 'root' in value:
                entries.append(('', value['root']))
            for name, attrs in entries:
                target = temporary / name
                directory = not name or name in value['directories']
                flags = os.O_RDONLY | getattr(os, 'O_NOFOLLOW', 0)
                if directory:
                    flags |= getattr(os, 'O_DIRECTORY', 0)
                # Open before restoring restrictive permissions. Files are
                # synced before directories, and directories deepest first.
                descriptor = os.open(target, flags)
                try:
                    os.chmod(target, attrs['mode'])
                    os.utime(target, ns=(attrs['mtime_ns'], attrs['mtime_ns']), follow_symlinks=False)
                    if _metadata(os.fstat(descriptor)) != {key: attrs[key] for key in ('mode', 'mtime_ns')}:
                        raise SnapshotStoreError(f'Materialized snapshot metadata mismatch: {name}')
                    os.fsync(descriptor)
                finally:
                    os.close(descriptor)
            if 'root' not in value:
                _fsync_directory(temporary)
            _fresh_parent(destination)
            os.rename(temporary, destination)
            published = True
            _fsync_directory(destination.parent)
        except BaseException:
            if published:
                # A failed parent sync must not leave a successful-looking
                # publication. The verified archive remains recoverable.
                os.rename(destination, temporary)
            raise
        finally:
            if temporary.exists():
                _remove_tree(temporary)
        return value
