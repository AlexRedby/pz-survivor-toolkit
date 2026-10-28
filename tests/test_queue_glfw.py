"""Private native input integrity; never patch or load an installed game library."""
import hashlib
from pathlib import Path
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import glfw


class GlfwTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.game = self.root / 'game'
        self.game.mkdir()

    def archive(self, data, folder='arm64'):
        with zipfile.ZipFile(self.game / 'projectzomboid.jar', 'w') as archive:
            archive.writestr('macos/' + folder + '/org/lwjgl/glfw/libglfw.dylib', data)

    def test_private_copy_retains_all_bytes_except_reviewed_branch_and_is_sealed(self):
        for architecture, folder in [('arm64', 'arm64'), ('x86_64', 'x64')]:
            with self.subTest(architecture=architecture):
                before, after, offset = b'branch', b'nopnop', 12
                data = b'header-data!' + before + b'trailer'
                self.archive(data, folder)
                jar_before = (self.game / 'projectzomboid.jar').read_bytes()
                spec = (folder, hashlib.sha256(data).hexdigest(), offset, before, after)
                output = self.root / architecture
                output.mkdir()
                with patch.object(glfw.platform, 'machine', return_value=architecture), \
                     patch.dict(glfw.REVIEWED, {architecture: spec}), \
                     patch.object(glfw.subprocess, 'run') as signing:
                    metadata = glfw.prepare(self.game, output / 'native')
                self.assertEqual((self.game / 'projectzomboid.jar').read_bytes(), jar_before)
                self.assertEqual(Path(metadata['library']).read_bytes(), data[:offset] + after + data[offset + len(before):])
                self.assertEqual(signing.call_count, 2)
                self.assertIn('--verify', signing.call_args.args[0])
                self.assertEqual(glfw.arguments(output, metadata), ['-Dorg.lwjgl.glfw.libname=' + metadata['library']])
                Path(metadata['library']).write_bytes(b'changed')
                with self.assertRaisesRegex(ValueError, 'missing or changed'):
                    glfw.arguments(output, metadata)

    def test_unknown_native_bytes_refuse_before_creating_copy(self):
        self.archive(b'unreviewed')
        with patch.object(glfw.platform, 'machine', return_value='arm64'):
            with self.assertRaisesRegex(ValueError, 'Unreviewed bundled GLFW'):
                glfw.prepare(self.game, self.root / 'native')
        self.assertFalse((self.root / 'native').exists())

    def test_selected_java_architecture_wins_over_python_rosetta_architecture(self):
        for reported, expected in [('aarch64', 'arm64'), ('amd64', 'x86_64')]:
            with self.subTest(reported=reported), \
                 patch.object(glfw.subprocess, 'run', return_value=SimpleNamespace(stderr='    os.arch = ' + reported + '\n')):
                self.assertEqual(glfw.jvm_architecture('/chosen/jdk/bin/java'), expected)
        with patch.object(glfw.subprocess, 'run', return_value=SimpleNamespace(stderr='unknown')):
            with self.assertRaisesRegex(ValueError, 'Cannot identify'):
                glfw.jvm_architecture('/chosen/jdk/bin/java')

    def test_missing_metadata_and_external_library_cannot_select_unsealed_input(self):
        for metadata in (None, {}, {'library': '/tmp/foreign.dylib'}):
            with self.subTest(metadata=metadata), self.assertRaisesRegex(ValueError, 'fresh run'):
                glfw.arguments(self.root, metadata)

    def test_invalid_instruction_is_rejected_even_with_matching_full_hash(self):
        data = b'not-the-branch'
        self.archive(data)
        spec = ('arm64', hashlib.sha256(data).hexdigest(), 0, b'expected', b'replaced')
        with patch.object(glfw.platform, 'machine', return_value='arm64'), \
             patch.dict(glfw.REVIEWED, {'arm64': spec}):
            with self.assertRaisesRegex(ValueError, 'Unreviewed bundled GLFW'):
                glfw.prepare(self.game, self.root / 'native')

    def test_symlinked_native_directory_cannot_redirect_the_owned_input(self):
        external = self.root / 'external'
        external.mkdir()
        library = external / 'libglfw.dylib'
        library.write_bytes(b'valid bytes in wrong directory')
        (self.root / 'native').symlink_to(external, target_is_directory=True)
        metadata = {'library': str(self.root / 'native/libglfw.dylib'),
                    'sha256': hashlib.sha256(library.read_bytes()).hexdigest(),
                    'compatibility': 'retain-online-displays-during-sleep'}
        with self.assertRaisesRegex(ValueError, 'missing or changed'):
            glfw.arguments(self.root, metadata)


if __name__ == '__main__':
    unittest.main()
