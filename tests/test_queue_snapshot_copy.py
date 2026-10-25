"""Snapshot file copies retain copy2 semantics with an optional clonefile backend."""
import ctypes
import errno
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import snapshot_copy


class SnapshotCopyTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.source = self.root / 'source.bin'
        self.target = self.root / 'snapshot.bin'
        self.payload = bytes(range(256)) * 16 + b'\x00snapshot input\xff'
        self.source.write_bytes(self.payload)
        self.source.chmod(0o640)
        os.utime(self.source, ns=(1_700_000_000_123_456_789, 1_700_000_001_987_654_321))

    @staticmethod
    def clone(source, target, flags):
        # Deliberately copy no metadata, so the successful-clone path must set it.
        shutil.copyfile(os.fsdecode(source), os.fsdecode(target))
        return 0

    @staticmethod
    def clone_error(number):
        def fail(source, target, flags):
            ctypes.set_errno(number)
            return -1
        return fail

    def assert_copy(self, target):
        self.assertEqual(self.payload, target.read_bytes())
        self.assertEqual(stat.S_IMODE(self.source.stat().st_mode), stat.S_IMODE(target.stat().st_mode))
        self.assertEqual(self.source.stat().st_mtime_ns, target.stat().st_mtime_ns)
        self.assertFalse(os.path.samefile(self.source, target))

    def test_clone_preserves_bytes_metadata_and_independent_file_identities(self):
        sibling = self.root / 'sibling.bin'
        with patch.object(snapshot_copy, '_CLONEFILE', side_effect=self.clone) as clone, \
             patch.object(snapshot_copy.shutil, 'copy2') as ordinary:
            self.assertEqual(self.target, snapshot_copy.copy_file(self.source, self.target))
            snapshot_copy.copy_file(self.source, sibling)
        self.assertEqual(2, clone.call_count)
        for call in clone.call_args_list:
            self.assertEqual(os.fsencode(self.source), call.args[0])
            self.assertIsInstance(call.args[1], bytes)
            self.assertEqual(0, call.args[2])
        ordinary.assert_not_called()
        self.assert_copy(self.target)
        self.assert_copy(sibling)
        self.assertFalse(os.path.samefile(self.target, sibling))
        self.target.write_bytes(b'changed snapshot')
        self.assertEqual(self.payload, self.source.read_bytes())
        self.assertEqual(self.payload, sibling.read_bytes())
        self.source.write_bytes(b'changed source')
        self.assertEqual(b'changed snapshot', self.target.read_bytes())
        self.assertEqual(self.payload, sibling.read_bytes())

    def test_unavailable_backend_uses_copy2(self):
        with patch.object(snapshot_copy, '_CLONEFILE', None), \
             patch.object(snapshot_copy.shutil, 'copy2', wraps=shutil.copy2) as ordinary:
            self.assertEqual(self.target, snapshot_copy.copy_file(self.source, self.target))
        ordinary.assert_called_once()
        self.assert_copy(self.target)

    def test_unsupported_and_cross_device_errors_fall_back_to_copy2(self):
        numbers = {errno.ENOTSUP, errno.EOPNOTSUPP, errno.EXDEV, errno.ENOSYS}
        for number in sorted(numbers):
            target = self.root / ('fallback-' + str(number))
            with self.subTest(errno=number), \
                 patch.object(snapshot_copy, '_CLONEFILE', side_effect=self.clone_error(number)), \
                 patch.object(snapshot_copy.shutil, 'copy2', wraps=shutil.copy2) as ordinary:
                self.assertEqual(target, snapshot_copy.copy_file(self.source, target))
                ordinary.assert_called_once()
                self.assert_copy(target)

    def test_existing_destination_keeps_copy2_overwrite_semantics(self):
        self.target.write_bytes(b'old snapshot')
        self.target.chmod(0o600)
        with patch.object(snapshot_copy, '_CLONEFILE', side_effect=self.clone_error(errno.EEXIST)), \
             patch.object(snapshot_copy.shutil, 'copy2', wraps=shutil.copy2) as ordinary:
            self.assertEqual(self.target, snapshot_copy.copy_file(self.source, self.target))
        ordinary.assert_called_once()
        self.assert_copy(self.target)

    def test_storage_permission_and_io_errors_are_not_retried_as_ordinary_copies(self):
        for number in (errno.ENOSPC, errno.EACCES, errno.EIO, errno.ENOENT):
            with self.subTest(errno=number), \
                 patch.object(snapshot_copy, '_CLONEFILE', side_effect=self.clone_error(number)), \
                 patch.object(snapshot_copy.shutil, 'copy2') as ordinary:
                with self.assertRaises(OSError) as raised:
                    snapshot_copy.copy_file(self.source, self.target)
                self.assertEqual(number, raised.exception.errno)
                ordinary.assert_not_called()
                self.assertFalse(self.target.exists())

    def test_symlink_source_uses_copy2_without_cloning(self):
        link = self.root / 'linked-source'
        link.symlink_to(self.source)
        with patch.object(snapshot_copy, '_CLONEFILE') as clone, \
             patch.object(snapshot_copy.shutil, 'copy2', wraps=shutil.copy2) as ordinary:
            snapshot_copy.copy_file(link, self.target)
        clone.assert_not_called()
        ordinary.assert_called_once()
        self.assertFalse(self.target.is_symlink())
        self.assert_copy(self.target)

    def test_directory_source_retains_copy2_error_without_cloning(self):
        with patch.object(snapshot_copy, '_CLONEFILE') as clone:
            with self.assertRaises(IsADirectoryError):
                snapshot_copy.copy_file(self.root, self.target)
        clone.assert_not_called()

    def test_metadata_failure_after_clone_propagates_without_copy2_retry(self):
        with patch.object(snapshot_copy, '_CLONEFILE', side_effect=self.clone), \
             patch.object(snapshot_copy.shutil, 'copystat', side_effect=PermissionError(errno.EACCES, 'metadata')), \
             patch.object(snapshot_copy.shutil, 'copy2') as ordinary:
            with self.assertRaises(PermissionError):
                snapshot_copy.copy_file(self.source, self.target)
        ordinary.assert_not_called()

    @unittest.skipUnless(sys.platform == 'darwin', 'clonefile is a macOS API')
    def test_native_clonefile_produces_isolated_files_when_filesystem_supports_it(self):
        clonefile = snapshot_copy._CLONEFILE
        if clonefile is None:
            self.skipTest('clonefile is unavailable on this macOS system')
        results = []

        def observe(source, target, flags):
            result = clonefile(source, target, flags)
            results.append((result, ctypes.get_errno()))
            return result

        sibling = self.root / 'native-sibling.bin'
        with patch.object(snapshot_copy, '_CLONEFILE', side_effect=observe), \
             patch.object(snapshot_copy.shutil, 'copy2', wraps=shutil.copy2) as ordinary:
            snapshot_copy.copy_file(self.source, self.target)
            if results and results[0][0] != 0 and results[0][1] in {
                    errno.ENOTSUP, errno.EOPNOTSUPP, errno.EXDEV, errno.ENOSYS}:
                self.skipTest('temporary filesystem does not support clonefile: ' + str(results[0][1]))
            snapshot_copy.copy_file(self.source, sibling)
        self.assertEqual(2, len(results))
        self.assertTrue(all(result == 0 for result, _ in results))
        ordinary.assert_not_called()
        self.assert_copy(self.target)
        self.assert_copy(sibling)
        self.assertFalse(os.path.samefile(self.target, sibling))
        self.target.write_bytes(b'changed native clone')
        self.assertEqual(self.payload, self.source.read_bytes())
        self.assertEqual(self.payload, sibling.read_bytes())
        self.source.write_bytes(b'changed native source')
        self.assertEqual(b'changed native clone', self.target.read_bytes())
        self.assertEqual(self.payload, sibling.read_bytes())


if __name__ == '__main__':
    unittest.main()
