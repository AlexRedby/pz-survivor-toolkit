"""Protect disposable cart compilation without requiring a JDK or game installation."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from JavaPatches import build
from JavaPatches.tests import test_build_kotlin as kotlin_fixture
import cart_jvm


class CartJVMCompilation(unittest.TestCase):
    def setUp(self):
        cache = tempfile.TemporaryDirectory()
        self.addCleanup(cache.cleanup)
        self.root = Path(cache.name).resolve()
        self.home = kotlin_fixture.KotlinBuild(methodName='runTest').distribution(self.root / 'Kotlin distribution')
        self.jdk = self.root / 'JDK'
        self.kotlin = self.root / 'Fixture.kt'
        self.java = self.root / 'FixtureAdvice.java'
        self.kotlin.write_text('object Fixture {}')
        self.java.write_text('class FixtureAdvice {}')
        self.classpath = os.pathsep.join([str(self.root / 'game.jar'), str(self.root / 'patch.jar')])
        self.commands = []
        self.failure = None
        self.emit_classes = True

    def subprocess(self, command, **kwargs):
        self.commands.append((command, kwargs))
        phase = ('kotlin' if '-jar' in command else
                 'relocation' if 'RelocateKotlin' in command else
                 'relocator' if any(arg.endswith('/RelocateKotlin.java') for arg in command) else 'java')
        if self.failure == phase:
            return subprocess.CompletedProcess(command, 7, stdout='compiler output\n', stderr='compiler error\n')
        if self.emit_classes and '-d' in command:
            destination = Path(command[command.index('-d') + 1])
            destination.mkdir(parents=True, exist_ok=True)
            (destination / (phase + '.class')).write_bytes(b'compiled fixture')
        return subprocess.CompletedProcess(command, 0, stdout='', stderr='')

    def compile(self, classes, sources):
        with patch.object(cart_jvm, 'patch_build', return_value=build), \
                patch.object(cart_jvm.subprocess, 'run', side_effect=self.subprocess):
            cart_jvm.compile_sources(self.jdk, self.classpath, classes, sources, kotlin_home=self.home)

    def test_mixed_compilation_keeps_cart_module_private_runtime_and_process_policy(self):
        classes = self.root / 'classes'
        environment = {'JAVA_TOOL_OPTIONS': '-javaagent:foreign.jar', 'JDK_JAVA_OPTIONS': '-Xmx1m',
                       '_JAVA_OPTIONS': '-Xms1m', 'CART_FIXTURE_OPTION': 'retained'}
        with patch.dict(os.environ, environment, clear=True):
            self.compile(classes, [self.kotlin, self.java])
        self.assertEqual(len(self.commands), 4)
        kotlin, java, relocator, relocation = [command for command, _ in self.commands]
        self.assertEqual(kotlin[kotlin.index('-module-name') + 1], 'cart_lab')
        self.assertEqual(kotlin[kotlin.index('-jvm-target') + 1], build.JVM_TARGET)
        self.assertIn('-no-stdlib', kotlin)
        self.assertIn('-no-reflect', kotlin)
        self.assertEqual(set(kotlin[-2:]), {str(self.kotlin), str(self.java)})
        compilepath = os.pathsep.join([str(classes), str(self.home / 'lib/kotlin-stdlib.jar'), self.classpath])
        self.assertEqual(kotlin[kotlin.index('-classpath') + 1], compilepath)
        self.assertEqual(java[java.index('-cp') + 1], compilepath)
        self.assertEqual(java[java.index('--release') + 1], build.JVM_TARGET)
        self.assertEqual(java[-1], str(self.java))
        self.assertNotIn(str(self.kotlin), java)
        self.assertEqual(relocator[relocator.index('-cp') + 1], str(self.home / 'lib/kotlin-compiler.jar'))
        self.assertEqual(relocator[-1], str(ROOT / 'JavaPatches/tools/RelocateKotlin.java'))
        self.assertEqual(relocation[-3:], ['RelocateKotlin', str(classes), '--tests'])
        self.assertEqual((classes / build.KOTLIN_RUNTIME_PACKAGE / 'Unit.class').read_bytes(), b'local runtime fixture')
        self.assertTrue((classes / 'META-INF/licenses/kotlin/LICENSE.txt').is_file())
        self.assertFalse((classes / 'kotlin').exists())
        for command, kwargs in self.commands:
            self.assertTrue(all(isinstance(arg, str) for arg in command))
            self.assertEqual(kwargs, {'capture_output': True, 'text': True, 'timeout': 120,
                                      'env': {'CART_FIXTURE_OPTION': 'retained'}})

    def test_java_only_compilation_does_not_resolve_or_stage_kotlin(self):
        classes = self.root / 'java-only'
        with patch.object(build, 'kotlin_toolchain') as toolchain, \
                patch.object(build, 'stage_kotlin_runtime') as stage:
            self.compile(classes, [self.java])
        toolchain.assert_not_called()
        stage.assert_not_called()
        self.assertEqual(len(self.commands), 1)
        command = self.commands[0][0]
        self.assertEqual(command, [str(self.jdk / 'bin/javac'), '--release', build.JVM_TARGET,
                                  '-cp', self.classpath, '-d', str(classes), str(self.java)])
        self.assertFalse((classes / build.KOTLIN_RUNTIME_PACKAGE).exists())

    def test_failed_compiler_or_relocation_stops_without_false_success(self):
        for index, phase in enumerate(('kotlin', 'java', 'relocator', 'relocation'), start=1):
            with self.subTest(phase=phase):
                self.commands.clear()
                self.failure = phase
                with self.assertRaisesRegex(ValueError, r'Cart JVM compiler failed \(7\):\ncompiler output\ncompiler error'):
                    self.compile(self.root / phase, [self.kotlin, self.java])
                self.assertEqual(len(self.commands), index)

    def test_successful_process_without_class_output_is_rejected_before_runtime_staging(self):
        self.emit_classes = False
        with patch.object(build, 'stage_kotlin_runtime') as stage:
            with self.assertRaisesRegex(ValueError, 'Cart compiler produced no classes'):
                self.compile(self.root / 'empty', [self.kotlin, self.java])
        stage.assert_not_called()
        self.assertEqual(len(self.commands), 2)

    def test_process_timeout_propagates(self):
        timeout = subprocess.TimeoutExpired('kotlinc', 120)
        with patch.object(cart_jvm, 'patch_build', return_value=build), \
                patch.object(cart_jvm.subprocess, 'run', side_effect=timeout) as run, \
                patch.object(build, 'stage_kotlin_runtime') as stage:
            with self.assertRaises(subprocess.TimeoutExpired) as failure:
                cart_jvm.compile_sources(self.jdk, self.classpath, self.root / 'timeout',
                                         [self.kotlin, self.java], kotlin_home=self.home)
        self.assertIs(failure.exception, timeout)
        self.assertEqual(run.call_count, 1)
        stage.assert_not_called()


if __name__ == '__main__':
    unittest.main()
