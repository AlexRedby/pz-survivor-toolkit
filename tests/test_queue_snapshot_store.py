"""Immutable native archives must retain exact bytes and fail closed on damage."""
from concurrent.futures import ProcessPoolExecutor
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import snapshot_store as store


def concurrent_capture(arguments):
    return store.capture(*arguments)


@unittest.skipUnless(os.name == 'posix', 'Native archive directory durability is qualified on POSIX only')
class SnapshotStoreTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        self.tree = self.root / 'staged'
        self.tree.mkdir()
        self.archive = self.root / 'store'
        (self.tree / 'nested').mkdir()
        (self.tree / 'nested/empty').mkdir()
        (self.tree / 'nested/data').write_bytes(b'final staged bytes\0' * 100)
        (self.tree / '.private').write_bytes(b'private manifest input')
        for index, path in enumerate(sorted(self.tree.rglob('*')) + [self.tree]):
            os.utime(path, ns=(1_700_000_000_123_456_789 + index, 1_700_000_000_123_456_789 + index))
        (self.tree / 'nested/data').chmod(0o640)
        (self.tree / 'nested/empty').chmod(0o750)

    def capture(self):
        return store.capture(self.tree, self.archive)

    def object(self, object_id, suffix):
        if suffix == '.tar.gz':
            descriptor = json.loads((self.archive / 'objects' / f'{object_id}.json').read_bytes())
            return self.archive / 'payloads' / f"{descriptor['payload_id']}.tar.gz"
        return self.archive / 'objects' / f'{object_id}{suffix}'

    def rewrite_archive(self, object_id, change):
        path = self.object(object_id, '.tar.gz')
        with tarfile.open(path, 'r:gz') as source:
            members = [(member, source.extractfile(member).read() if member.isfile() else None)
                       for member in source]
        with tarfile.open(path, 'w:gz') as target:
            for member, data in change(members):
                target.addfile(member, io.BytesIO(data) if data is not None else None)

    def test_roundtrip_metadata_empty_directories_and_private_files(self):
        object_id = self.capture()
        manifest = store.verify(self.archive, object_id)
        self.assertEqual(hashlib.sha256(store._canonical(manifest)).hexdigest(), object_id)
        self.assertIn('nested/empty', manifest['directories'])
        self.assertIn('.private', manifest['files'])
        self.assertEqual(manifest, store.manifest(self.archive, object_id))
        target = self.root / 'restored'
        self.assertEqual(manifest, store.materialize(self.archive, object_id, target))
        self.assertEqual(manifest, store.verify(self.archive, object_id))
        for name in ['', *manifest['directories'], *manifest['files']]:
            source, destination = self.tree / name, target / name
            self.assertEqual(stat.S_IMODE(source.stat().st_mode), stat.S_IMODE(destination.stat().st_mode))
            self.assertEqual(source.stat().st_mtime_ns, destination.stat().st_mtime_ns)
            if source.is_file():
                self.assertEqual(source.read_bytes(), destination.read_bytes())
                self.assertNotEqual(source.stat().st_ino, destination.stat().st_ino)
        (target / 'nested/data').write_bytes(b'private change')
        self.assertEqual(store.hashes(manifest)['nested/data'], hashlib.sha256((self.tree / 'nested/data').read_bytes()).hexdigest())
        store.verify(self.archive, object_id)

    def test_verify_tree_checks_metadata_membership_types_and_bytes(self):
        object_id = self.capture()
        manifest = store.verify(self.archive, object_id)
        def bytes_change(target):
            path = target / 'nested/data'
            original = path.stat()
            path.write_bytes(b'x' * original.st_size)
            os.utime(path, ns=(original.st_mtime_ns, original.st_mtime_ns))
        def replace_type(target):
            path = target / 'nested/data'
            path.unlink()
            path.mkdir()
        changes = [
            lambda target: (target / 'nested/data').chmod(0o600),
            lambda target: os.utime(target / 'nested/data', ns=(0, 0)),
            lambda target: (target / 'new-empty').mkdir(),
            lambda target: (target / 'nested/empty').rmdir(),
            lambda target: target.chmod(target.stat().st_mode ^ 0o020),
            lambda target: os.utime(target, ns=(0, 0)),
            bytes_change,
            replace_type,
        ]
        for index, change in enumerate(changes):
            with self.subTest(change=change):
                target = self.root / f'verify-{index}'
                store.materialize(self.archive, object_id, target)
                self.assertEqual(manifest, store.verify_tree(target, manifest))
                change(target)
                with self.assertRaises(store.SnapshotStoreError):
                    store.verify_tree(target, manifest)

    def test_verify_tree_rejects_source_mutating_during_hashing(self):
        object_id = self.capture()
        manifest = store.verify(self.archive, object_id)
        original = store._HashingReader.read
        def mutate(reader, size):
            data = original(reader, size)
            (self.tree / 'new').write_bytes(b'changed during verification')
            return data
        with patch.object(store._HashingReader, 'read', side_effect=mutate, autospec=True):
            with self.assertRaisesRegex(store.SnapshotStoreError, 'changed'):
                store.verify_tree(self.tree, manifest)

    def test_dedup_preserves_existing_object_and_metadata_changes_identity(self):
        object_id = self.capture()
        archive = self.object(object_id, '.tar.gz')
        identity = archive.stat()
        self.assertEqual(object_id, self.capture())
        self.assertEqual(identity.st_ino, archive.stat().st_ino)
        self.assertEqual(identity.st_mtime_ns, archive.stat().st_mtime_ns)
        (self.tree / 'nested/data').chmod(0o600)
        self.assertNotEqual(object_id, self.capture())

    def test_fresh_timestamps_share_payload_and_restore_each_descriptor(self):
        first_id = self.capture()
        first = store.verify(self.archive, first_id)
        identity = self.object(first_id, '.tar.gz').stat()
        for path in [self.tree, *self.tree.rglob('*')]:
            os.utime(path, ns=(path.stat().st_mtime_ns + 1_000, path.stat().st_mtime_ns + 1_000))
        second_id = self.capture()
        second = store.verify(self.archive, second_id)
        self.assertNotEqual(first_id, second_id)
        self.assertEqual(first['payload_id'], second['payload_id'])
        self.assertEqual(identity.st_ino, self.object(second_id, '.tar.gz').stat().st_ino)
        for object_id, manifest in ((first_id, first), (second_id, second)):
            target = self.root / object_id
            store.materialize(self.archive, object_id, target)
            self.assertEqual(manifest['root']['mtime_ns'], target.stat().st_mtime_ns)
            self.assertEqual(manifest['files']['nested/data']['mtime_ns'],
                             (target / 'nested/data').stat().st_mtime_ns)

    def test_existing_payload_is_reused_without_compression(self):
        first_id = self.capture()
        original = store.tarfile.open
        def refuse_compression(*args, **kwargs):
            mode = kwargs.get('mode', args[1] if len(args) > 1 else 'r')
            self.assertNotIn('w', mode, 'An existing payload must not be compressed again')
            return original(*args, **kwargs)
        with patch.object(store.tarfile, 'open', side_effect=refuse_compression):
            self.assertEqual(first_id, self.capture())
            os.utime(self.tree, ns=(123_456_789, 123_456_789))
            second_id = self.capture()
            self.assertNotEqual(first_id, second_id)
            store.verify(self.archive, second_id)

    def test_concurrent_writers_publish_one_complete_object(self):
        with ProcessPoolExecutor(max_workers=2) as pool:
            ids = list(pool.map(concurrent_capture, [(self.tree, self.archive)] * 3))
        self.assertEqual(len(set(ids)), 1)
        store.verify(self.archive, ids[0])
        self.assertEqual({f'{ids[0]}.json'},
                         {path.name for path in (self.archive / 'objects').iterdir()})
        self.assertEqual(len(list((self.archive / 'payloads').iterdir())), 1)

    def test_source_mutation_during_streaming_rejects_capture(self):
        original = store._HashingReader.read
        changed = False
        def mutate(reader, size):
            nonlocal changed
            result = original(reader, size)
            if not changed:
                changed = True
                (self.tree / 'added').write_bytes(b'late source file')
            return result
        with patch.object(store._HashingReader, 'read', mutate):
            with self.assertRaisesRegex(store.SnapshotStoreError, 'changed'):
                self.capture()
        self.assertFalse(self.archive.exists())

    def test_source_file_mutation_during_archive_write_is_rejected(self):
        original = store.tarfile.open
        def mutate_before_archive(*args, **kwargs):
            mode = kwargs.get('mode', args[1] if len(args) > 1 else 'r')
            if 'w' in mode:
                (self.tree / 'nested/data').write_bytes(b'changed after manifest hashing')
            return original(*args, **kwargs)
        with patch.object(store.tarfile, 'open', side_effect=mutate_before_archive):
            with self.assertRaisesRegex(store.SnapshotStoreError, 'changed'):
                self.capture()
        self.assertEqual(list((self.archive / 'objects').iterdir()), [])
        self.assertEqual(list((self.archive / 'payloads').iterdir()), [])

    def test_existing_payload_corruption_blocks_new_timestamp_descriptor(self):
        object_id = self.capture()
        archive = self.object(object_id, '.tar.gz')
        archive.write_bytes(b'damaged shared payload')
        os.utime(self.tree, ns=(123_456_789, 123_456_789))
        with self.assertRaises(store.SnapshotStoreError):
            self.capture()
        self.assertEqual(archive.read_bytes(), b'damaged shared payload')
        self.assertEqual({f'{object_id}.json'},
                         {path.name for path in (self.archive / 'objects').iterdir()})

    def test_existing_corrupt_object_is_never_replaced(self):
        object_id = self.capture()
        path = self.object(object_id, '.tar.gz')
        path.write_bytes(b'corrupted')
        with self.assertRaises(store.SnapshotStoreError):
            self.capture()
        self.assertEqual(path.read_bytes(), b'corrupted')

    def test_file_hash_size_missing_extra_and_duplicate_members_rejected(self):
        transforms = [
            lambda rows: [(m, b'x' * len(data) if data is not None else data) for m, data in rows],
            lambda rows: rows[:-1],
            lambda rows: rows + [rows[0]],
        ]
        for transform in transforms:
            with self.subTest(transform=transform):
                object_id = self.capture()
                path = self.object(object_id, '.tar.gz')
                original = path.read_bytes()
                self.rewrite_archive(object_id, transform)
                with self.assertRaises(store.SnapshotStoreError):
                    store.verify(self.archive, object_id)
                path.write_bytes(original)
        object_id = self.capture()
        def resize(rows):
            for member, data in rows:
                if data is not None:
                    member.size += 1
                    data += b'x'
                yield member, data
        self.rewrite_archive(object_id, resize)
        with self.assertRaisesRegex(store.SnapshotStoreError, 'size'):
            store.verify(self.archive, object_id)

    def test_archive_traversal_links_and_special_files_rejected(self):
        object_id = self.capture()
        path = self.object(object_id, '.tar.gz')
        original = path.read_bytes()
        for name, kind in [('../escape', tarfile.REGTYPE), ('/absolute', tarfile.REGTYPE),
                           ('nested/data', tarfile.SYMTYPE), ('nested/data', tarfile.LNKTYPE),
                           ('nested/data', tarfile.FIFOTYPE)]:
            with self.subTest(name=name, kind=kind):
                member = tarfile.TarInfo(name)
                member.type = kind
                member.linkname = 'elsewhere'
                self.rewrite_archive(object_id, lambda rows: [(member, None)])
                with self.assertRaises(store.SnapshotStoreError):
                    store.verify(self.archive, object_id)
                path.write_bytes(original)
        self.assertFalse((self.root / 'escape').exists())

    def test_gzip_truncation_and_trailing_members_are_rejected(self):
        object_id = self.capture()
        path = self.object(object_id, '.tar.gz')
        original = path.read_bytes()
        for damage in (original[:-4], original[:-8], original + gzip.compress(b'not archive padding')):
            with self.subTest(size=len(damage)):
                path.write_bytes(damage)
                with self.assertRaises(store.SnapshotStoreError):
                    store.verify(self.archive, object_id)
        path.write_bytes(original)

    def test_manifest_invalid_ids_paths_duplicates_and_hash_are_rejected(self):
        for object_id in ('../escape', 'A' * 64, 'a' * 63, 'a' * 65, None):
            with self.assertRaises(store.SnapshotStoreError):
                store.verify(self.archive, object_id)
        object_id = self.capture()
        sidecar = self.object(object_id, '.json')
        original = sidecar.read_bytes()
        for content in (b'{', b'{"schema_version":1,"schema_version":1}',
                        original.replace(b'final', b'other'), original.replace(b'"mode":416', b'"mode":420')):
            if content == original:
                continue
            sidecar.write_bytes(content)
            with self.assertRaises(store.SnapshotStoreError):
                store.verify(self.archive, object_id)
        sidecar.write_bytes(original)
        for name in ('../escape', '/absolute', 'a//b', 'a/./b', 'a/../b', 'C:/escape', 'a\\b', 'x:stream', '.. /escape', 'NUL.txt', ''):
            value = {'schema_version': 1, 'files': {}, 'directories': {name: {'mode': 0o700, 'mtime_ns': 0}}}
            value['payload_id'] = store._payload_id(value)
            with self.assertRaises(store.SnapshotStoreError):
                store.hashes(value)

    def test_source_links_and_special_files_rejected(self):
        for target in ('nested/data', 'nested', 'missing'):
            link = self.tree / 'link'
            link.symlink_to(target)
            with self.assertRaises(store.SnapshotStoreError):
                self.capture()
            link.unlink()
        if hasattr(os, 'mkfifo'):
            os.mkfifo(self.tree / 'fifo')
            with self.assertRaises(store.SnapshotStoreError):
                self.capture()

    def test_publication_syncs_payload_and_descriptor_directories_in_order(self):
        events = []
        original_rename = store.os.rename
        original_sync = store._fsync_directory
        def rename(source, target):
            events.append(('rename', Path(target)))
            return original_rename(source, target)
        def sync(path):
            events.append(('sync', Path(path)))
            return original_sync(path)
        with patch.object(store.os, 'rename', side_effect=rename), \
                patch.object(store, '_fsync_directory', side_effect=sync):
            object_id = self.capture()
        payload = self.object(object_id, '.tar.gz')
        descriptor = self.object(object_id, '.json')
        payload_rename = events.index(('rename', payload))
        descriptor_rename = events.index(('rename', descriptor))
        self.assertIn(('sync', self.archive.parent), events[:payload_rename])
        self.assertIn(('sync', self.archive), events[:payload_rename])
        self.assertIn(('sync', payload.parent), events[payload_rename + 1:descriptor_rename])
        self.assertIn(('sync', descriptor.parent), events[descriptor_rename + 1:])

    def test_reused_descriptor_syncs_existing_publication_before_return(self):
        object_id = self.capture()
        original = store._fsync_directory
        synced = []
        def sync(path):
            synced.append(Path(path))
            return original(path)
        with patch.object(store, '_fsync_directory', side_effect=sync):
            self.assertEqual(object_id, self.capture())
        self.assertIn(self.archive / 'payloads', synced)
        self.assertIn(self.archive / 'objects', synced)

    def test_failed_directory_sync_never_exposes_a_descriptor(self):
        original = store._fsync_directory
        def fail_payload_sync(path):
            if Path(path) == self.archive / 'payloads':
                raise OSError('interrupted directory sync')
            return original(path)
        with patch.object(store, '_fsync_directory', side_effect=fail_payload_sync):
            with self.assertRaisesRegex(OSError, 'interrupted directory sync'):
                self.capture()
        self.assertEqual(list((self.archive / 'objects').iterdir()), [])
        self.assertEqual(list((self.archive / 'payloads').iterdir()), [])

    def test_publication_failure_cleans_partial_members(self):
        original = os.rename
        def fail_sidecar(source, target):
            if str(target).endswith('.json'):
                raise OSError('interrupted publication')
            return original(source, target)
        with patch.object(store.os, 'rename', side_effect=fail_sidecar):
            with self.assertRaisesRegex(OSError, 'interrupted'):
                self.capture()
        self.assertEqual(list((self.archive / 'objects').iterdir()), [])
        self.assertEqual(list((self.archive / 'payloads').iterdir()), [])
        store.verify(self.archive, self.capture())

    def test_materialize_syncs_files_and_tree_before_rename_then_parent(self):
        object_id = self.capture()
        destination = self.root / 'durable'
        events = []
        original_sync, original_rename = store.os.fsync, store.os.rename
        def sync(descriptor):
            events.append('file' if stat.S_ISREG(os.fstat(descriptor).st_mode) else 'directory')
            return original_sync(descriptor)
        def rename(source, target):
            events.append('publish')
            return original_rename(source, target)
        with patch.object(store.os, 'fsync', side_effect=sync), \
                patch.object(store.os, 'rename', side_effect=rename):
            store.materialize(self.archive, object_id, destination)
        publication = events.index('publish')
        self.assertIn('file', events[:publication])
        self.assertEqual(events[publication - 1], 'directory')
        self.assertEqual(events[publication + 1:], ['directory'])
        store.verify_tree(destination, store.manifest(self.archive, object_id))

    def test_materialize_file_sync_failure_cleans_unpublished_tree(self):
        object_id = self.capture()
        destination = self.root / 'failed-file-sync'
        original = store.os.fsync
        def fail_file_sync(descriptor):
            if stat.S_ISREG(os.fstat(descriptor).st_mode):
                raise OSError('restored file sync failed')
            return original(descriptor)
        with patch.object(store.os, 'fsync', side_effect=fail_file_sync):
            with self.assertRaisesRegex(OSError, 'restored file sync failed'):
                store.materialize(self.archive, object_id, destination)
        self.assertFalse(destination.exists())
        self.assertFalse(list(self.root.glob('.failed-file-sync.snapshot-*')))
        store.verify(self.archive, object_id)

    def test_materialize_tree_directory_sync_failure_cleans_unpublished_tree(self):
        object_id = self.capture()
        destination = self.root / 'failed-tree-sync'
        original = store.os.fsync
        files_synced = False
        def fail_tree_sync(descriptor):
            nonlocal files_synced
            if stat.S_ISREG(os.fstat(descriptor).st_mode):
                files_synced = True
            elif files_synced:
                raise OSError('restored tree directory sync failed')
            return original(descriptor)
        with patch.object(store.os, 'fsync', side_effect=fail_tree_sync):
            with self.assertRaisesRegex(OSError, 'restored tree directory sync failed'):
                store.materialize(self.archive, object_id, destination)
        self.assertFalse(destination.exists())
        self.assertFalse(list(self.root.glob('.failed-tree-sync.snapshot-*')))
        store.verify(self.archive, object_id)

    def test_materialize_parent_sync_failure_rolls_back_publication(self):
        object_id = self.capture()
        destination = self.root / 'failed-parent-sync'
        original = store._fsync_directory
        def fail_parent_sync(path):
            if Path(path) == destination.parent:
                raise OSError('restored parent sync failed')
            return original(path)
        with patch.object(store, '_fsync_directory', side_effect=fail_parent_sync):
            with self.assertRaisesRegex(OSError, 'restored parent sync failed'):
                store.materialize(self.archive, object_id, destination)
        self.assertFalse(destination.exists())
        self.assertFalse(list(self.root.glob('.failed-parent-sync.snapshot-*')))
        store.verify(self.archive, object_id)

    def test_materialize_requires_fresh_target_and_cleans_failed_publication(self):
        object_id = self.capture()
        destination = self.root / 'restored'
        with patch.object(store.os, 'rename', side_effect=OSError('interrupted restore')):
            with self.assertRaisesRegex(OSError, 'interrupted'):
                store.materialize(self.archive, object_id, destination)
        self.assertFalse(destination.exists())
        self.assertFalse(list(self.root.glob('.restored.snapshot-*')))
        destination.mkdir()
        with self.assertRaises(store.SnapshotStoreError):
            store.materialize(self.archive, object_id, destination)
        destination.rmdir()
        parent = self.root / 'linked'
        parent.symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(store.SnapshotStoreError, 'symlink'):
            store.materialize(self.archive, object_id, parent / 'restored')
        store.verify(self.archive, object_id)


if __name__ == '__main__':
    unittest.main()
