"""Protect selected-check discovery and Kotlin/Java test compilation boundaries without a JDK."""
import contextlib
import io
import os
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from JavaPatches import build
from JavaPatches.tests import test_build_kotlin as kotlin_fixture


class KotlinTestCompilation(unittest.TestCase):
    def setUp(self):
        self.fixture = kotlin_fixture.KotlinBuild(methodName='runTest')
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.root = self.fixture.root
        self.failure = None
        self.events = []

    def source(self, name, text):
        path = self.root / 'tests' / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def test_selected_kotlin_check_includes_local_and_imported_helpers_without_poison(self):
        selected = self.source('checks/SelectedCheck.kt', '''package checks
import helpers.ImportedHelper
object SelectedCheck { fun run() = SamePackageHelper.read() + ImportedHelper.read() }
''')
        local = self.source('checks/SamePackageHelper.kt', 'package checks\nobject SamePackageHelper { fun read() = 1 }')
        imported = self.source('helpers/ImportedHelper.kt', 'package helpers\nobject ImportedHelper { fun read() = 2 }')
        self.source('checks/PoisonCheck.kt', 'This unrelated source must never reach the compiler.')
        self.source('elsewhere/SamePackageHelper.kt', 'This same-named source is in another package.')
        with patch.object(build, 'ROOT', self.root):
            sources = build.check_sources(['checks.SelectedCheck', 'checks.SelectedCheck'])
        self.assertEqual(sources[0], selected)
        self.assertEqual(len(sources), 3)
        self.assertEqual(set(sources), {selected, local, imported})

    def test_top_level_kotlin_helpers_do_not_require_class_or_file_name_references(self):
        selected = self.source('checks/SelectedCheck.kt', """package checks
import helpers.importedValue
object SelectedCheck { fun run() = localValue() + importedValue() }
""")
        local = self.source('checks/LocalUtilities.kt', 'package checks\nfun localValue() = 1')
        imported = self.source('helpers/ImportedUtilities.kt', 'package helpers\nfun importedValue() = 2')
        self.source('checks/PoisonCheck.kt', 'This unrelated source must never reach the compiler.')
        with patch.object(build, 'ROOT', self.root):
            sources = build.check_sources(['checks.SelectedCheck'])
        self.assertEqual(set(sources), {selected, local, imported})

    def test_java_helper_chain_discovers_kotlin_dependencies_for_javac_sourcepath(self):
        selected = self.source('checks/SelectedCheck.java', '''package checks;
public class SelectedCheck { public static int run() { return JavaHelper.read(); } }
''')
        java_helper = self.source('checks/JavaHelper.java', '''package checks;
import helpers.KotlinHelper;
class JavaHelper { static int read() { return KotlinHelper.read(); } }
''')
        helper = self.source('helpers/KotlinHelper.kt', '''package helpers
object KotlinHelper { @JvmStatic fun read() = NestedHelper.read() }
''')
        nested = self.source('helpers/NestedHelper.kt', 'package helpers\nobject NestedHelper { fun read() = 1 }')
        self.source('checks/PoisonCheck.kt', 'This unrelated Kotlin source must not be compiled.')
        with patch.object(build, 'ROOT', self.root):
            sources = build.check_sources(['checks.SelectedCheck'])
        # Emit Java helpers as well; their Kotlin dependencies must exist first.
        self.assertEqual(sources[0], selected)
        self.assertEqual(set(sources), {selected, java_helper, helper, nested})

    def test_kotlin_only_selection_emits_java_helpers_and_their_kotlin_dependencies(self):
        selected = self.source('checks/SelectedCheck.kt', '''package checks
object SelectedCheck { fun run() = JavaHelper.read() }
''')
        java_helper = self.source('checks/JavaHelper.java', '''package checks;
import helpers.KotlinHelper;
class JavaHelper { static int read() { return KotlinHelper.read(); } }
''')
        kotlin_helper = self.source('helpers/KotlinHelper.kt', '''package helpers
object KotlinHelper { @JvmStatic fun read() = 1 }
''')
        self.source('checks/PoisonCheck.java', 'This unrelated Java source must not be compiled.')
        with patch.object(build, 'ROOT', self.root):
            sources = build.check_sources(['checks.SelectedCheck'])
        self.assertEqual(set(sources), {selected, java_helper, kotlin_helper})

    def prepare_checks(self):
        self.kotlin_name = 'net.alexredby.pztoolkitjavapatches.MedicineCooldownChecks'
        self.cold_name = 'net.alexredby.javapatchfixture.KotlinRuntimeChecks'
        self.kotlin_check = self.source(self.kotlin_name.replace('.', '/') + '.kt', '''package net.alexredby.pztoolkitjavapatches
object MedicineCooldownChecks { @JvmStatic fun main(args: Array<String>) { LocalHelper.read() } }
''')
        self.kotlin_helper = self.source('net/alexredby/pztoolkitjavapatches/LocalHelper.kt', '''package net.alexredby.pztoolkitjavapatches
object LocalHelper { fun read() = JavaHelper.read() }
''')
        self.java_helper = self.source('net/alexredby/pztoolkitjavapatches/JavaHelper.java', '''package net.alexredby.pztoolkitjavapatches;
class JavaHelper { static Object read() { return MedicineCooldown.read(null, false); } }
''')
        self.cold_check = self.source(self.cold_name.replace('.', '/') + '.java', '''package net.alexredby.javapatchfixture;
public class KotlinRuntimeChecks { public static void main(String[] args) { System.out.println("kotlin.Unit"); } }
''')
        self.source('net/alexredby/pztoolkitjavapatches/PoisonCheck.kt', 'Unrelated invalid Kotlin source.')

    def class_file(self, classes, name):
        return classes / (name.replace('.', '/') + '.class')

    def subprocess(self, command, **kwargs):
        is_test_compiler = '-jar' in command and '-module-name' in command and \
            command[command.index('-module-name') + 1] == build.KOTLIN_MODULE + '_tests'
        is_test_relocation = 'RelocateKotlin' in command and '--tests' in command
        is_java_checks = '-sourcepath' in command
        if is_test_compiler or is_test_relocation or is_java_checks:
            self.fixture.commands.append(command)
            phase = 'test compiler' if is_test_compiler else 'test relocation' if is_test_relocation else 'java checks'
            self.events.append(phase)
            if self.failure == phase:
                raise subprocess.CalledProcessError(1, command)
        if is_test_compiler:
            classes = Path(command[command.index('-d') + 1])
            api = Path(next(arg.split('=', 1)[1] for arg in command if arg.startswith('-Xfriend-paths=')))
            self.assertEqual((api / 'net/alexredby/pztoolkitjavapatches/TVVideoPaths.class').read_bytes(),
                             b'Kotlin application')
            self.assertEqual((api / ('META-INF/' + build.KOTLIN_MODULE + '.kotlin_module')).read_bytes(),
                             b'application module')
            self.assertFalse((api / build.KOTLIN_RUNTIME_PACKAGE).exists())
            for name in (self.kotlin_name, 'net.alexredby.pztoolkitjavapatches.LocalHelper'):
                target = self.class_file(classes, name)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b'kotlin.Unit')
        elif is_test_relocation:
            classes = Path(command[command.index('RelocateKotlin') + 1])
            self.assertEqual({path.relative_to(classes).as_posix() for path in classes.rglob('*.class')},
                             {self.kotlin_name.replace('.', '/') + '.class',
                              'net/alexredby/pztoolkitjavapatches/LocalHelper.class'})
            for path in classes.rglob('*.class'):
                path.write_bytes(path.read_bytes().replace(b'kotlin.Unit', b'private.kotlin.Unit'))
        elif is_java_checks:
            classes = Path(command[command.index('-d') + 1])
            self.assertEqual(self.class_file(classes, self.kotlin_name).read_bytes(), b'private.kotlin.Unit')
            self.assertFalse(self.class_file(classes, self.cold_name).exists())
            target = self.class_file(classes, self.cold_name)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b'kotlin.Unit')
        elif any(arg.startswith('-javaagent:') for arg in command):
            self.fixture.commands.append(command)
            if command[-1] == self.cold_name:
                classes = Path(command[command.index('-cp') + 1].split(os.pathsep)[0])
                self.assertEqual(self.class_file(classes, self.cold_name).read_bytes(), b'kotlin.Unit')
            kwargs['stdout'].write(build.CHECKS[command[-1]] + '\n')
        else:
            result = self.fixture.subprocess(command, **kwargs)
            if 'RelocateKotlin' in command:
                classes = Path(command[command.index('RelocateKotlin') + 1])
                # Distinguish shaded production bytes from the raw module copied for friend compilation.
                (classes / 'net/alexredby/pztoolkitjavapatches/TVVideoPaths.class').write_bytes(b'relocated application')
            return result
        return subprocess.CompletedProcess(command, 0)

    def run_build(self):
        with patch.object(build, 'ROOT', self.root), \
                patch.object(build.subprocess, 'run', side_effect=self.subprocess), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            build.main(['--game', str(self.fixture.game), '--jdk', str(self.root / 'jdk'),
                        '--kotlin-home', str(self.fixture.home), '--test', 'MedicineCooldownChecks',
                        '--test', 'KotlinRuntimeChecks', '--test', 'MedicineCooldownChecks'])

    def test_mixed_tests_use_raw_friend_api_then_shade_before_compiling_cold_java_fixture(self):
        self.prepare_checks()
        self.run_build()
        self.assertEqual(self.events, ['test compiler', 'test relocation', 'java checks'])
        commands = self.fixture.commands
        kotlin = next(command for command in commands if '-Xfriend-paths=' in ' '.join(command))
        java = next(command for command in commands if '-sourcepath' in command)
        self.assertEqual({arg for arg in kotlin if arg.endswith('.kt')},
                         {str(self.kotlin_check), str(self.kotlin_helper)})
        self.assertEqual([arg for arg in java if arg.endswith('.java')],
                         [str(self.cold_check), str(self.java_helper)])
        self.assertEqual(kotlin[kotlin.index('-jvm-target') + 1], '17')
        self.assertEqual(java[java.index('--release') + 1], '17')
        classpath = kotlin[kotlin.index('-classpath') + 1].split(os.pathsep)
        friend = next(arg.split('=', 1)[1] for arg in kotlin if arg.startswith('-Xfriend-paths='))
        self.assertEqual(classpath[:2], [str(self.fixture.home / 'lib/kotlin-stdlib.jar'), friend])
        self.assertNotIn(str(self.fixture.mod / '42/media/java/PZToolkitJavaPatches.jar'), classpath)
        self.assertIn('-Xjava-source-roots=' + str(self.root / 'tests'), kotlin)
        runtime = [command for command in commands if any(arg.startswith('-javaagent:') for arg in command)]
        self.assertEqual([command[-1] for command in runtime], [self.kotlin_name, self.cold_name])
        cold_path = runtime[-1][runtime[-1].index('-cp') + 1]
        self.assertNotIn('PZToolkitJavaPatches.jar', cold_path)
        self.assertNotIn('PZToolkitFonts.jar', cold_path)

    def test_test_compiler_relocation_and_java_compile_failures_preserve_previous_mod(self):
        self.prepare_checks()
        for phase in ('test compiler', 'test relocation', 'java checks'):
            with self.subTest(phase=phase):
                self.fixture.commands.clear()
                self.events.clear()
                self.failure = phase
                with self.assertRaises(subprocess.CalledProcessError):
                    self.run_build()
                self.fixture.assert_previous_output()
                self.assertFalse(any(any(arg.startswith('-javaagent:') for arg in command)
                                     for command in self.fixture.commands))


if __name__ == '__main__':
    unittest.main()
