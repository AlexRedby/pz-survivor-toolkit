"""Exercise local Kotlin preflight, mixed compilation and packaging without a compiler."""
import argparse
import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from JavaPatches import build


class KotlinBuild(unittest.TestCase):
    def setUp(self):
        cache = tempfile.TemporaryDirectory()
        self.addCleanup(cache.cleanup)
        self.root = Path(cache.name).resolve()
        self.game = self.root / 'game'
        self.game.mkdir()
        for name in ('projectzomboid.jar', 'ZombieBuddy.jar'):
            (self.game / name).touch()
        self.kotlin = self.root / 'src/net/alexredby/pztoolkitjavapatches/TVVideoPaths.kt'
        self.java = self.kotlin.with_name('BytecodeSupport.java')
        self.kotlin.parent.mkdir(parents=True)
        self.kotlin.write_text('package net.alexredby.pztoolkitjavapatches\n')
        self.java.write_text('package net.alexredby.pztoolkitjavapatches; class BytecodeSupport {}')
        self.bootstrap = self.root / 'src/net/alexredby/pztoolkitbootstrap/FontBootstrap.java'
        self.bootstrap.parent.mkdir(parents=True)
        self.bootstrap.write_text('package net.alexredby.pztoolkitbootstrap; class FontBootstrap {}')
        self.home = self.distribution(self.root / 'Kotlin distribution')
        self.mod = self.root / 'build/PZToolkitJavaPatches'
        for name, content in {'42/mod.info': b'previous metadata',
                              '42/media/java/PZToolkitJavaPatches.jar': b'previous patches',
                              '42/media/bootstrap/PZToolkitFonts.jar': b'previous fonts'}.items():
            path = self.mod / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
        self.before = self.snapshot(self.root / 'build')
        self.commands = []
        self.failure = None

    def distribution(self, home, compiler_version=None, runtime_version=None, runtime_extra=None):
        (home / 'lib').mkdir(parents=True)
        for name, version in [('kotlin-compiler.jar', compiler_version), ('kotlin-stdlib.jar', runtime_version)]:
            with ZipFile(home / 'lib' / name, 'w') as archive:
                archive.writestr('META-INF/MANIFEST.MF',
                                 'Manifest-Version: 1.0\nImplementation-Version: ' +
                                 (build.KOTLIN_VERSION if version is None else version) + '\n')
                if name == 'kotlin-stdlib.jar':
                    archive.writestr('kotlin/Unit.class', b'local runtime fixture')
                    archive.writestr('META-INF/kotlin-stdlib.kotlin_module', b'runtime module')
                    archive.writestr('META-INF/versions/9/module-info.class', b'not on classpath')
                    archive.writestr('org/jetbrains/annotations/NotNull.class', b'not runtime')
                    for entry, content in (runtime_extra or {}).items():
                        archive.writestr(entry, content)
                else:
                    archive.writestr('org/jetbrains/kotlin/cli/jvm/K2JVMCompiler.class', b'not bundled')
        (home / 'license').mkdir()
        for name in ('LICENSE.txt', 'NOTICE.txt', 'COPYRIGHT.txt'):
            (home / 'license' / name).write_text('fixture ' + name)
        (home / 'bin').mkdir()
        (home / 'bin/kotlinc').touch()
        return home

    @staticmethod
    def snapshot(directory):
        return {path.relative_to(directory).as_posix(): path.read_bytes() if path.is_file() else None
                for path in directory.rglob('*')}

    def assert_previous_output(self):
        self.assertEqual(self.snapshot(self.root / 'build'), self.before)

    def subprocess(self, command, **kwargs):
        self.commands.append(command)
        if command[-1] == '-version':
            return subprocess.CompletedProcess(command, 0, stdout='javac 25.0.1')
        if '-jar' in command:
            if self.failure == 'compiler':
                raise subprocess.CalledProcessError(1, command)
            classes = Path(command[command.index('-d') + 1])
            for name, content in {
                'net/alexredby/pztoolkitjavapatches/TVVideoPaths.class': b'Kotlin application',
                'META-INF/' + build.KOTLIN_MODULE + '.kotlin_module': b'application module',
            }.items():
                target = classes / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(content)
        elif any(arg.endswith('/tools/RelocateKotlin.java') for arg in command):
            classes = Path(command[command.index('-d') + 1])
            (classes / 'RelocateKotlin.class').write_bytes(b'build-only relocator')
        elif '--release' in command:
            classes = Path(command[command.index('-d') + 1])
            # javac depends on Kotlin output, rather than compiling the Kotlin source itself.
            self.assertTrue((classes / 'net/alexredby/pztoolkitjavapatches/TVVideoPaths.class').is_file())
            for source in (self.java, self.bootstrap):
                target = classes / source.relative_to(self.root / 'src').with_suffix('.class')
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b'Java application')
        elif 'RelocateKotlin' in command:
            pass  # Native KotlinRuntimeChecks verifies actual bytecode relocation with the real toolchain.
        elif '--create' in command:
            jar = Path(command[command.index('--file') + 1])
            # Model jar's -C inclusion semantics so assertions inspect the delivered artifacts.
            with ZipFile(jar, 'w') as archive:
                for index, value in enumerate(command):
                    if value == '-C':
                        base = Path(command[index + 1])
                        selected = base / command[index + 2]
                        for path in selected.rglob('*'):
                            if path.is_file():
                                archive.write(path, path.relative_to(base).as_posix())
        else:
            self.fail('Unexpected external command: ' + repr(command))
        return subprocess.CompletedProcess(command, 0)

    def run_build(self, home=None):
        with patch.object(build, 'ROOT', self.root), \
                patch.object(build.subprocess, 'run', side_effect=self.subprocess), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()) as error:
            self.stderr = error
            return build.main(['--game', str(self.game), '--jdk', str(self.root / 'jdk'),
                               '--kotlin-home', str(self.home if home is None else home)])

    def test_missing_or_mismatched_toolchain_fails_before_output_mutation(self):
        for case in ('missing compiler', 'missing runtime', 'compiler mismatch', 'runtime mismatch', 'missing license'):
            with self.subTest(case=case):
                home = self.distribution(self.root / case,
                                         compiler_version='2.2.0' if case == 'compiler mismatch' else None,
                                         runtime_version='2.2.0' if case == 'runtime mismatch' else None)
                missing = {'missing compiler': 'lib/kotlin-compiler.jar',
                           'missing runtime': 'lib/kotlin-stdlib.jar',
                           'missing license': 'license/NOTICE.txt'}.get(case)
                if missing:
                    (home / missing).unlink()
                self.commands.clear()
                with patch.object(Path, 'mkdir') as mkdir, \
                        patch.object(build.tempfile, 'mkdtemp') as temporary, \
                        self.assertRaises(SystemExit) as failure:
                    self.run_build(home)
                self.assertEqual(failure.exception.code, 2)
                self.assertIn('Kotlin', self.stderr.getvalue())
                self.assertIn(str(home), self.stderr.getvalue())
                mkdir.assert_not_called()
                temporary.assert_not_called()
                self.assertEqual(len(self.commands), 1)
                self.assertEqual(self.commands[0][-1], '-version')
                self.assert_previous_output()

    def test_toolchain_can_be_selected_from_environment_or_path_without_running_compiler(self):
        parser = argparse.ArgumentParser()
        with patch.dict(os.environ, {'KOTLIN_HOME': str(self.home)}, clear=True), \
                patch.object(build.shutil, 'which') as which, patch.object(build.subprocess, 'run') as run:
            self.assertEqual(build.kotlin_toolchain(None, parser), self.home)
            which.assert_not_called()
            run.assert_not_called()
        with patch.dict(os.environ, {}, clear=True), \
                patch.object(build.shutil, 'which', return_value=str(self.home / 'bin/kotlinc')), \
                patch.object(build.subprocess, 'run') as run:
            self.assertEqual(build.kotlin_toolchain(None, parser), self.home)
            run.assert_not_called()

    def test_mixed_build_targets_java25_and_bundles_runtime_only_in_ordinary_jar(self):
        with patch.dict(os.environ, {'KOTLIN_HOME': str(self.root / 'wrong environment distribution')}):
            self.run_build()
        kotlin = next(command for command in self.commands if '-jar' in command)
        java = next(command for command in self.commands if '--release' in command)
        self.assertLess(self.commands.index(kotlin), self.commands.index(java))
        self.assertEqual(kotlin[kotlin.index('-jvm-target') + 1], '25')
        self.assertEqual(java[java.index('--release') + 1], '25')
        self.assertEqual(kotlin[kotlin.index('-module-name') + 1], build.KOTLIN_MODULE)
        self.assertIn(str(self.kotlin), kotlin)
        self.assertIn(str(self.java), kotlin)
        self.assertIn(str(self.bootstrap), kotlin)
        self.assertIn(str(self.java), java)
        self.assertIn(str(self.bootstrap), java)
        self.assertNotIn(str(self.kotlin), java)
        classes = kotlin[kotlin.index('-d') + 1]
        self.assertEqual(java[java.index('-d') + 1], classes)
        kotlin_classpath = kotlin[kotlin.index('-classpath') + 1].split(os.pathsep)
        java_classpath = java[java.index('-cp') + 1].split(os.pathsep)
        self.assertEqual(kotlin_classpath[0], str(self.home / 'lib/kotlin-stdlib.jar'))
        self.assertEqual(java_classpath[:2], [classes, str(self.home / 'lib/kotlin-stdlib.jar')])
        for jar in (self.game / 'projectzomboid.jar', self.game / 'ZombieBuddy.jar',
                    self.home / 'lib/kotlin-stdlib.jar'):
            self.assertIn(str(jar), kotlin_classpath)
            self.assertIn(str(jar), java_classpath)
        self.assertIn(classes, java_classpath)
        with ZipFile(self.mod / '42/media/java/PZToolkitJavaPatches.jar') as ordinary:
            self.assertIn('net/alexredby/pztoolkitjavapatches/TVVideoPaths.class', ordinary.namelist())
            self.assertEqual(ordinary.read(build.KOTLIN_RUNTIME_PACKAGE + '/Unit.class'), b'local runtime fixture')
            self.assertEqual(ordinary.read('META-INF/kotlin-stdlib.kotlin_module'), b'runtime module')
            self.assertEqual(ordinary.read('META-INF/' + build.KOTLIN_MODULE + '.kotlin_module'), b'application module')
            for name in ('LICENSE.txt', 'NOTICE.txt', 'COPYRIGHT.txt'):
                self.assertEqual(ordinary.read('META-INF/licenses/kotlin/' + name), ('fixture ' + name).encode())
            self.assertFalse(any(name.startswith(('org/', 'META-INF/versions/')) for name in ordinary.namelist()))
            self.assertFalse(any(name.startswith('kotlin/') for name in ordinary.namelist()))
        with ZipFile(self.mod / '42/media/bootstrap/PZToolkitFonts.jar') as early:
            self.assertEqual(early.namelist(), ['net/alexredby/pztoolkitbootstrap/FontBootstrap.class'])
        self.assertFalse(list((self.root / 'build').glob('.build-*')))

    def test_kotlin_compiler_failure_preserves_previous_mod(self):
        self.failure = 'compiler'
        with self.assertRaises(subprocess.CalledProcessError):
            self.run_build()
        self.assertFalse(any('--release' in command or '--create' in command for command in self.commands))
        self.assert_previous_output()

    def test_runtime_staging_failure_preserves_previous_mod(self):
        home = self.distribution(self.root / 'invalid runtime', runtime_extra={'kotlin/../../escaped.class': b'invalid'})
        with self.assertRaisesRegex(ValueError, 'Invalid Kotlin runtime entry'):
            self.run_build(home)
        self.assertFalse(any('--create' in command for command in self.commands))
        self.assert_previous_output()
        self.assertFalse(list(self.root.rglob('escaped.class')))


if __name__ == '__main__':
    unittest.main()
