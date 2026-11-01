"""Check dependency discovery and transactional Java mod output without a JDK."""
import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from JavaPatches import build


class BuildPaths(unittest.TestCase):
    def setUp(self):
        self.cache = tempfile.TemporaryDirectory()
        self.addCleanup(self.cache.cleanup)
        self.root = Path(self.cache.name).resolve()
        self.sentinel = self.root / 'build/classes/keep.txt'
        self.sentinel.parent.mkdir(parents=True)
        self.sentinel.write_text('previous build')
        self.mod = self.root / 'build/PZToolkitJavaPatches'
        self.previous_files = {
            '42/mod.info': b'previous metadata',
            '42/media/java/PZToolkitJavaPatches.jar': b'previous patches',
            '42/media/bootstrap/PZToolkitFonts.jar': b'previous fonts',
            'obsolete.txt': b'previous obsolete file',
        }
        for name, content in self.previous_files.items():
            target = self.mod / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
        (self.mod / 'common').mkdir()
        self.game = self.root / 'game'
        self.game.mkdir()
        for name in ('projectzomboid.jar', 'ZombieBuddy.jar'):
            (self.game / name).touch()

    def assert_previous_mod(self, mod=None):
        mod = self.mod if mod is None else mod
        self.assertTrue((mod / 'common').is_dir())
        self.assertEqual({path.relative_to(mod).as_posix(): path.read_bytes()
                          for path in mod.rglob('*') if path.is_file()}, self.previous_files)

    def run_build(self, platform, *args, version='javac 25.0.1', failure=None, hook=None, root=None):
        self.manifests = []

        def run(command, **kwargs):
            if failure is not None:
                raise failure
            if hook is not None:
                hook(command)
            if '--create' in command:
                jar = Path(command[command.index('--file') + 1])
                jar.write_bytes(('new ' + jar.name).encode())
                if '--manifest' in command:
                    self.manifests.append(Path(command[command.index('--manifest') + 1]).read_text())
            return subprocess.CompletedProcess(command, 0, stdout=version)

        stderr = io.StringIO()
        with patch.object(sys, 'platform', platform), patch.object(Path, 'home', return_value=self.root), \
             patch.dict(os.environ, {'ProgramFiles(x86)': str(self.root / 'program files'), 'JAVA_HOME': str(self.root / 'jdk')}), \
             patch.object(build, 'ROOT', self.root if root is None else root), \
             patch('subprocess.run', side_effect=run) as mocked, \
             contextlib.redirect_stderr(stderr), contextlib.redirect_stdout(io.StringIO()):
            try:
                build.main(args)
            except SystemExit as error:
                return error.code, stderr.getvalue(), mocked.call_args_list
        return 0, stderr.getvalue(), mocked.call_args_list

    def test_platform_defaults_and_missing_game_preserve_output(self):
        defaults = {
            'win32': self.root / 'program files/Steam/steamapps/common/ProjectZomboid',
            'darwin': self.root / 'Library/Application Support/Steam/steamapps/common/ProjectZomboid/Project Zomboid.app/Contents/Java',
            'linux': self.root / '.steam/steam/steamapps/common/ProjectZomboid/projectzomboid',
        }
        for platform, expected in defaults.items():
            with self.subTest(platform=platform):
                code, error, calls = self.run_build(platform)
                self.assertEqual(code, 2)
                self.assertIn(str(expected), error)
                self.assertIn('projectzomboid.jar', error)
                self.assertIn('--game', error)
                self.assertFalse(calls)
                self.assertEqual(self.sentinel.read_text(), 'previous build')

    def test_custom_game_overrides_default_and_supplies_classpath(self):
        game = self.root / 'custom steam library'
        game.mkdir()
        for name in ('projectzomboid.jar', 'ZombieBuddy.jar'):
            (game / name).touch()
        for version in ('javac 25.0.1', 'javac 25-ea', 'javac 26.0.1', 'Picked up JAVA_TOOL_OPTIONS: -Dtest=true\njavac 25.0.1\n'):
            with self.subTest(version=version):
                code, error, calls = self.run_build('win32', '--game', str(game), version=version)
                self.assertEqual(code, 0, error)
                command = next(call.args[0] for call in calls if '-cp' in call.args[0])
                self.assertEqual(command[command.index('-cp') + 1], os.pathsep.join(str(game / name) for name in ('projectzomboid.jar', 'ZombieBuddy.jar')))
                self.assertTrue((self.root / 'build/PZToolkitJavaPatches/42/mod.info').is_file())
                metadata = (self.root / 'build/PZToolkitJavaPatches/42/mod.info').read_text()
                self.assertIn('name=Toolkit Java Patches (Experimental)\n', metadata)
                self.assertIn('id=PZToolkitJavaPatches\n', metadata)
                self.assertIn('version=' + build.MOD_INFO['version'] + '\n', metadata)
                self.assertRegex(build.MOD_INFO['version'], r'^\d+\.\d+\.\d+$')
                self.assertIn('versionMin=42.21\n', metadata)
                self.assertIn('versionMax=42.21\n', metadata)
                self.assertIn('require=\\ZombieBuddy\n', metadata)
                self.assertIn('javaPkgName=net.alexredby.pztoolkitjavapatches\n', metadata)
                self.assertIn('javaJarFile=media/java/PZToolkitJavaPatches.jar\n', metadata)
                self.assertNotIn('javaPreload=true\n', metadata)
                self.assertEqual(self.manifests, ['Manifest-Version: 1.0\nZB-Preload: true\n\n'])
                self.assertNotIn('media/java/client/', metadata)
                jars = [call.args[0] for call in calls if '--create' in call.args[0]]
                self.assertEqual(len(jars), 2)
                ordinary = next(command for command in jars if 'net/alexredby/pztoolkitjavapatches' in command)
                early = next(command for command in jars if 'net/alexredby/pztoolkitbootstrap' in command)
                self.assertNotIn('--manifest', ordinary)
                self.assertIn('--manifest', early)
                self.assertTrue(any(arg.endswith('42/media/bootstrap/PZToolkitFonts.jar') for arg in early))

    def test_missing_zombiebuddy_is_explained_before_compiling(self):
        (self.root / 'projectzomboid.jar').touch()
        code, error, calls = self.run_build('win32', '--game', str(self.root))
        self.assertEqual(code, 2)
        self.assertIn('ZombieBuddy.jar', error)
        self.assertIn('Install the ZombieBuddy loader', error)
        self.assertFalse(calls)
        self.assertTrue(self.sentinel.is_file())

    def test_unknown_platform_requires_explicit_game(self):
        code, error, calls = self.run_build('unknown')
        self.assertEqual(code, 2)
        self.assertIn('--game', error)
        self.assertFalse(calls)

    def test_old_or_unknown_compiler_preserves_existing_output(self):
        for name in ('projectzomboid.jar', 'ZombieBuddy.jar'):
            (self.root / name).touch()
        for version in ('javac 21.0.10', 'javac 17.0.1', 'unexpected output'):
            with self.subTest(version=version):
                code, error, calls = self.run_build('win32', '--game', str(self.root), version=version)
                self.assertEqual(code, 2)
                self.assertIn('JDK 25', error)
                self.assertIn('--jdk', error)
                self.assertIn(version, error)
                self.assertEqual(len(calls), 1)
                self.assertEqual(calls[0].args[0][-1], '-version')
                self.assertEqual(self.sentinel.read_text(), 'previous build')

    def test_unavailable_compiler_preserves_existing_output(self):
        for name in ('projectzomboid.jar', 'ZombieBuddy.jar'):
            (self.root / name).touch()
        for failure in (FileNotFoundError('missing javac'), subprocess.CalledProcessError(1, ['javac', '-version'])):
            with self.subTest(failure=type(failure).__name__):
                code, error, calls = self.run_build('win32', '--game', str(self.root), failure=failure)
                self.assertEqual(code, 2)
                self.assertIn('Cannot run javac', error)
                self.assertIn('JDK 25', error)
                self.assertEqual(len(calls), 1)
                self.assertTrue(self.sentinel.is_file())

    def test_failed_compilation_or_jar_creation_preserves_previous_mod(self):
        for phase in ('javac', 'PZToolkitJavaPatches.jar', 'PZToolkitFonts.jar'):
            def fail(command):
                if (phase == 'javac' and '--release' in command
                        or '--file' in command and Path(command[command.index('--file') + 1]).name == phase):
                    raise subprocess.CalledProcessError(1, command)

            with self.subTest(phase=phase), self.assertRaises(subprocess.CalledProcessError):
                self.run_build('darwin', '--game', str(self.game), hook=fail)
            self.assert_previous_mod()
            self.assertEqual(list((self.root / 'build').glob('.build-*')), [])

    def test_success_replaces_complete_mod_and_removes_stale_entries(self):
        code, error, _ = self.run_build('darwin', '--game', str(self.game))
        self.assertEqual(code, 0, error)
        self.assertFalse((self.mod / 'obsolete.txt').exists())
        for name in ('42/media/java/PZToolkitJavaPatches.jar', '42/media/bootstrap/PZToolkitFonts.jar'):
            self.assertEqual((self.mod / name).read_bytes(), ('new ' + Path(name).name).encode())
        self.assertTrue((self.mod / 'common').is_dir())
        self.assertIn('id=PZToolkitJavaPatches\n', (self.mod / '42/mod.info').read_text())
        self.assertEqual(list((self.root / 'build').glob('.build-*')), [])

    def test_symlink_build_preserves_external_output(self):
        build = self.root / 'build'
        external = self.root / 'external'
        build.rename(external)
        build.symlink_to(external, target_is_directory=True)
        code, error, calls = self.run_build('darwin', '--game', str(self.game))
        self.assertEqual(code, 2)
        self.assertIn('Build output must be a regular directory', error)
        self.assertEqual(len(calls), 1)
        self.assert_previous_mod(external / self.mod.name)
        self.assertEqual((external / 'classes/keep.txt').read_text(), 'previous build')
        self.assertEqual(list(external.glob('.build-*')), [])

    def test_symlink_mod_and_selected_log_preserve_external_files(self):
        external = self.root / 'external'
        self.mod.rename(external)
        self.mod.symlink_to(external, target_is_directory=True)
        code, error, calls = self.run_build('darwin', '--game', str(self.game))
        self.assertEqual(code, 2)
        self.assertIn('Build output must be a regular directory', error)
        self.assertEqual(len(calls), 1)
        self.assert_previous_mod(external)
        self.mod.unlink()
        external.rename(self.mod)

        sentinel = self.root / 'external.log'
        sentinel.write_text('external log must survive')
        (self.root / 'build/MediaChecks.log').symlink_to(sentinel)
        code, error, calls = self.run_build('darwin', '--game', str(self.game), '--test', 'MediaChecks')
        self.assertEqual(code, 2)
        self.assertIn('Check log must be a regular file', error)
        self.assertEqual(len(calls), 1)
        self.assertEqual(sentinel.read_text(), 'external log must survive')
        self.assert_previous_mod()
        self.assertEqual(list((self.root / 'build').glob('.build-*')), [])

    def test_failed_promotion_restores_previous_mod(self):
        rename = Path.rename

        def fail_promotion(path, target):
            if path.name == self.mod.name and path.parent.name.startswith('.build-'):
                raise OSError('promotion failed')
            return rename(path, target)

        with patch.object(Path, 'rename', fail_promotion), self.assertRaisesRegex(OSError, 'promotion failed'):
            self.run_build('darwin', '--game', str(self.game))
        self.assert_previous_mod()
        self.assertEqual(list((self.root / 'build').glob('.build-*')), [])

    def test_failed_restore_retains_and_reports_previous_mod(self):
        rename = Path.rename

        def fail_promotion_and_restore(path, target):
            if path.parent.name.startswith('.build-') and path.name in (self.mod.name, 'previous'):
                raise OSError('rename failed')
            return rename(path, target)

        with patch.object(Path, 'rename', fail_promotion_and_restore), self.assertRaisesRegex(
                OSError, 'Previous Java mod is preserved at .*; restore failed') as error:
            self.run_build('darwin', '--game', str(self.game))
        retained = list((self.root / 'build').glob('.build-*/previous'))
        self.assertEqual(len(retained), 1)
        self.assertIn(str(retained[0]), str(error.exception))
        self.assert_previous_mod(retained[0])
        self.assertFalse(self.mod.exists())

    def seed_custom_mod(self, output):
        mod = output / self.mod.name
        for name, content in self.previous_files.items():
            target = mod / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
        (mod / 'common').mkdir()
        return mod

    def test_custom_nested_output_preserves_default_and_replaces_only_its_mod(self):
        output = self.root / 'isolated build' / 'nested' / 'candidate'
        custom = self.seed_custom_mod(output)
        code, error, _ = self.run_build('darwin', '--game', str(self.game), '--output', str(output))
        self.assertEqual(code, 0, error)
        self.assert_previous_mod()
        self.assertEqual(self.sentinel.read_text(), 'previous build')
        self.assertFalse((custom / 'obsolete.txt').exists())
        for name in ('PZToolkitJavaPatches.jar', 'PZToolkitFonts.jar'):
            self.assertEqual(len(list(custom.rglob(name))), 1)
        self.assertEqual(list(output.glob('.build-*')), [])
        self.assertEqual(list((self.root / 'build').glob('.build-*')), [])

    def test_custom_output_creates_missing_parent_directories(self):
        output = self.root / 'missing' / 'nested' / 'output with spaces'
        code, error, _ = self.run_build('darwin', '--game', str(self.game), '--output', str(output))
        self.assertEqual(code, 0, error)
        self.assertTrue((output / self.mod.name / '42/mod.info').is_file())
        self.assert_previous_mod()

    def test_custom_output_failures_and_failed_restore_preserve_both_builds(self):
        output = self.root / 'isolated'
        custom = self.seed_custom_mod(output)
        for phase in ('javac', 'PZToolkitJavaPatches.jar', 'PZToolkitFonts.jar'):
            def fail(command):
                if (phase == 'javac' and '--release' in command or
                        '--file' in command and Path(command[command.index('--file') + 1]).name == phase):
                    raise subprocess.CalledProcessError(1, command)
            with self.subTest(phase=phase), self.assertRaises(subprocess.CalledProcessError):
                self.run_build('darwin', '--game', str(self.game), '--output', str(output), hook=fail)
            self.assert_previous_mod(custom)
            self.assert_previous_mod()
            self.assertEqual(list(output.glob('.build-*')), [])
        rename = Path.rename
        for restore_fails in (False, True):
            def fail_rename(path, target):
                if path.parent.name.startswith('.build-') and (path.name == self.mod.name or restore_fails and path.name == 'previous'):
                    raise OSError('custom promotion failure')
                return rename(path, target)
            with self.subTest(restore_fails=restore_fails), patch.object(Path, 'rename', fail_rename), self.assertRaises(OSError):
                self.run_build('darwin', '--game', str(self.game), '--output', str(output))
            self.assert_previous_mod()
            if restore_fails:
                retained = list(output.glob('.build-*/previous'))
                self.assertEqual(len(retained), 1)
                self.assert_previous_mod(retained[0])
            else:
                self.assert_previous_mod(custom)
                self.assertEqual(list(output.glob('.build-*')), [])

    def test_custom_output_rejects_leaf_symlinks_files_and_invalid_parents(self):
        external = self.root / 'external output'
        external.mkdir()
        for kind in ('symlink', 'dangling', 'file', 'parent-file', 'destination-symlink', 'destination-file'):
            output = self.root / kind
            if kind in ('symlink', 'dangling'):
                output.symlink_to(external if kind == 'symlink' else self.root / 'absent', target_is_directory=True)
            elif kind == 'file':
                output.write_text('untouched')
            elif kind == 'parent-file':
                output.write_text('untouched'); output = output / 'child'
            else:
                output.mkdir()
                destination = output / self.mod.name
                if kind == 'destination-symlink': destination.symlink_to(external, target_is_directory=True)
                else: destination.write_text('untouched')
            with self.subTest(kind=kind):
                code, error, calls = self.run_build('darwin', '--game', str(self.game), '--output', str(output))
                self.assertEqual(code, 2)
                self.assertIn('Build output', error)
                self.assertEqual(len(calls), 1)
                self.assert_previous_mod()
                self.assertEqual(list(external.iterdir()), [])

    def test_output_cannot_overlap_inputs_even_through_parent_alias(self):
        protected = [self.root / name for name in ('src', 'tests', 'tools', 'game', 'jdk')]
        alias = self.root / 'game alias'; alias.symlink_to(self.game, target_is_directory=True)
        for output in [*protected, alias / 'nested']:
            with self.subTest(output=output):
                before = output.exists()
                code, error, calls = self.run_build('darwin', '--game', str(self.game), '--output', str(output))
                self.assertEqual(code, 2)
                self.assertIn('overlaps input', error)
                self.assertEqual(output.exists(), before)
                self.assertEqual(len(calls), 1)
                self.assert_previous_mod()
        output = self.root / 'source container'
        source = output / self.mod.name
        source.mkdir(parents=True)
        code, error, _ = self.run_build('darwin', '--game', str(self.game), '--output', str(output), root=source)
        self.assertEqual(code, 2)
        self.assertIn('overlaps input', error)
        self.assertTrue(source.is_dir())
        game = source / 'game'; game.mkdir()
        for name in ('projectzomboid.jar', 'ZombieBuddy.jar'): (game / name).touch()
        code, error, _ = self.run_build('darwin', '--game', str(game), '--output', str(output))
        self.assertEqual(code, 2)
        self.assertIn('overlaps input', error)
        self.assertTrue((game / 'projectzomboid.jar').is_file())
        self.assert_previous_mod()

    def test_custom_output_allows_safe_parent_alias(self):
        parent = self.root / 'real parent'
        parent.mkdir()
        alias = self.root / 'parent alias'
        alias.symlink_to(parent, target_is_directory=True)
        code, error, calls = self.run_build('darwin', '--game', str(self.game), '--output', str(alias / 'candidate'))
        self.assertEqual(code, 0, error)
        self.assertTrue((parent / 'candidate' / self.mod.name / '42/mod.info').is_file())
        jars = [call.args[0] for call in calls if '--create' in call.args[0]]
        self.assertTrue(all(Path(command[command.index('--file') + 1]).is_relative_to(parent) for command in jars))
        self.assert_previous_mod()


if __name__ == '__main__':
    unittest.main()
