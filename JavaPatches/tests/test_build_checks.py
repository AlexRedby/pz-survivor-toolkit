"""Check selection and timeout handling without the game; use a JDK for helper resolution."""
import contextlib
import io
import os
from pathlib import Path
import re
import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

BUILD = Path(__file__).resolve().parents[1] / 'build.py'


class BuildChecks(unittest.TestCase):
    def setUp(self):
        cache = tempfile.TemporaryDirectory()
        self.addCleanup(cache.cleanup)
        self.root = Path(cache.name).resolve()
        self.script = self.root / 'build.py'
        shutil.copyfile(BUILD, self.script)
        self.game = self.root / 'game'
        self.game.mkdir()
        for name in ('projectzomboid.jar', 'ZombieBuddy.jar'):
            (self.game / name).touch()
        self.markers = '\n'.join(re.findall(r"'([A-Z_]+_PASS)'", BUILD.read_text()))
        self.markers += '\nPASS cart transition world/actor roundtrips\n[ZB] Transformed: zombie.core.skinnedmodel.ModelManager (retransformed)'
        self.sentinel = self.root / 'build/PZToolkitJavaPatches/previous.txt'
        self.sentinel.parent.mkdir(parents=True)
        self.sentinel.write_text('previous Java mod')

    def run_build(self, *args, java_result=None):
        def run(command, **kwargs):
            if Path(command[0]).name == 'java':
                output = self.markers if java_result is None else java_result.stdout or ''
                stream = kwargs['stdout']
                stream.flush()
                stream.buffer.write(output if isinstance(output, bytes) else output.encode())
                stream.flush()
                if isinstance(java_result, Exception):
                    raise java_result
                return java_result or subprocess.CompletedProcess(command, 0)
            if '-sourcepath' in command:
                classes = Path(command[command.index('-d') + 1])
                bootstrap = classes / 'net/alexredby/javapatchfixture/CartBootstrapCheck.class'
                bootstrap.parent.mkdir(parents=True)
                bootstrap.touch()
            if '--create' in command:
                Path(command[command.index('--file') + 1]).write_bytes(b'new JAR')
            return subprocess.CompletedProcess(command, 0, stdout='javac 25.0.1')

        self.error = io.StringIO()
        self.output = io.StringIO()
        with patch.object(sys, 'argv', [str(self.script), '--game', str(self.game), '--jdk', str(self.root / 'jdk'), *args]), \
             patch('subprocess.run', side_effect=run) as mocked, \
             contextlib.redirect_stdout(self.output), contextlib.redirect_stderr(self.error):
            self.run = mocked
            return runpy.run_path(str(self.script), run_name='__main__')

    def java_calls(self):
        return [call for call in self.run.call_args_list if Path(call.args[0][0]).name == 'java']

    def test_relative_game_and_jdk_remain_valid_after_regression_changes_cwd(self):
        previous = Path.cwd()
        try:
            os.chdir(self.root)
            self.run_build('--game', 'game', '--jdk', 'jdk', '--test', 'MediaChecks')
        finally:
            os.chdir(previous)
        call = self.java_calls()[0]
        command = call.args[0]
        self.assertEqual(self.root / 'jdk/bin/java', Path(command[0]))
        self.assertEqual(self.game, call.kwargs['cwd'])
        self.assertIn('-javaagent:' + str(self.game / 'ZombieBuddy.jar') + '=', command[1])
        classpath = command[command.index('-cp') + 1].split(os.pathsep)
        self.assertIn(str(self.game / 'projectzomboid.jar'), classpath)
        self.assertIn(str(self.game / 'ZombieBuddy.jar'), classpath)

    def test_named_selection_overrides_groups_and_deduplicates(self):
        self.run_build('--check', '--check-video', '--test', 'MediaChecks', '--test', 'AnimalChecks', '--test', 'MediaChecks')
        calls = self.java_calls()
        self.assertEqual([call.args[0][-1] for call in calls], ['zombie.radio.devices.MediaChecks', 'zombie.characters.AnimalChecks'])
        self.assertTrue(all(call.kwargs['timeout'] == 120 for call in calls))
        self.assertTrue(all(call.kwargs['cwd'] == self.game for call in calls))
        compilation = next(call.args[0] for call in self.run.call_args_list if '-sourcepath' in call.args[0])
        self.assertEqual([Path(arg).name for arg in compilation if arg.endswith('.java')], ['MediaChecks.java', 'AnimalChecks.java'])

    @unittest.skipUnless(shutil.which('javac') and shutil.which('java'), 'requires a local JDK')
    def test_selected_source_compiles_referenced_helper_without_unrelated_checks(self):
        self.run_build('--test', 'MediaChecks')
        command = next(call.args[0] for call in self.run.call_args_list if '-sourcepath' in call.args[0])
        package = self.root / 'tests/zombie/radio/devices'
        package.mkdir(parents=True)
        (package / 'MediaChecks.java').write_text('package zombie.radio.devices; public class MediaChecks { public static void main(String[] args) { System.out.println(MediaHelper.marker()); } }')
        (package / 'MediaHelper.java').write_text('package zombie.radio.devices; class MediaHelper { static String marker() { return "MEDIA_CHECKS_PASS"; } }')
        (package / 'UnrelatedChecks.java').write_text('This must not be compiled.')
        for jar in self.game.glob('*.jar'):
            with zipfile.ZipFile(jar, 'w'):
                pass
        command[0] = shutil.which('javac')
        classes = self.root / 'probe-classes'
        command[command.index('-d') + 1] = str(classes)
        subprocess.run(command, check=True, capture_output=True, text=True, timeout=20)
        self.assertTrue((classes / 'zombie/radio/devices/MediaHelper.class').is_file())
        result = subprocess.run([shutil.which('java'), '-cp', str(classes), 'zombie.radio.devices.MediaChecks'], check=True, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.stdout.strip(), 'MEDIA_CHECKS_PASS')

    def test_default_and_group_selection_remain_compatible(self):
        for flags, count, video in [((), 0, False), (('--check',), 39, False), (('--check-video',), 1, True), (('--check', '--check-video'), 40, True)]:
            with self.subTest(flags=flags):
                self.run_build(*flags)
                calls = self.java_calls()
                self.assertEqual(len(calls), count)
                self.assertEqual(any(call.args[0][-1].endswith('.VideoChecks') for call in calls), video)

    def test_cart_selection_retains_markers_and_isolates_cold_bootstrap(self):
        self.run_build('--test', 'CartTransitionMathTest', '--test', 'CartBootstrapCheck')
        calls = self.java_calls()
        self.assertEqual([call.args[0][-1] for call in calls],
                         ['net.alexredby.pztoolkitjavapatches.CartTransitionMathTest',
                          'net.alexredby.javapatchfixture.CartBootstrapCheck'])
        paths = [call.args[0][call.args[0].index('-cp') + 1].split(os.pathsep) for call in calls]
        self.assertNotEqual(paths[0][0], paths[1][0])
        self.assertEqual(paths[0][1:], paths[1][1:])

    def test_cart_checks_reject_transform_errors_and_missing_bootstrap_recovery(self):
        for name, output, error in (
                ('CartSteeringMathTest', 'CART_STEERING_MATH_PASS\nERROR transforming target', 'bytecode transformation failed'),
                ('CartBootstrapCheck', 'CART_BOOTSTRAP_PASS', 'cold bootstrap did not apply the model recovery patch')):
            with self.subTest(name=name), self.assertRaisesRegex(RuntimeError, error):
                self.run_build('--test', name, java_result=subprocess.CompletedProcess(['java'], 0, stdout=output))
            self.assertEqual(self.sentinel.read_text(), 'previous Java mod')
            self.assertFalse(list((self.root / 'build').glob('.build-*')))

    def test_single_selection_retains_trace_and_cold_font_setup(self):
        self.run_build('--test', 'VehicleTraceChecks', '--test', 'FontColdChecks', '--test-timeout', '9')
        calls = self.java_calls()
        self.assertEqual(len(calls), 3)
        self.assertIn('-Dpz.vehicle.trace=false', calls[0].args[0])
        self.assertIn('-Dpz.vehicle.trace=true', calls[1].args[0])
        self.assertTrue(all(call.kwargs['timeout'] == 9 for call in calls))
        cold_command = calls[2].args[0]
        self.assertIn(',patches_jar=', cold_command[1])
        self.assertNotIn('PZToolkitFonts.jar', cold_command[cold_command.index('-cp') + 1])

    def test_invalid_arguments_fail_before_build_and_help_lists_names(self):
        sentinel = self.root / 'build/classes/keep.txt'
        sentinel.parent.mkdir(parents=True)
        sentinel.write_text('previous build')
        for flags, code in [(('--test', 'MissingChecks'), 2), (('--test-timeout', '0'), 2), (('--test-timeout', '-1'), 2), (('--test-timeout', '1.5'), 2), (('--help',), 0)]:
            with self.subTest(flags=flags), self.assertRaises(SystemExit) as error:
                self.run_build(*flags)
            self.assertEqual(error.exception.code, code)
            self.run.assert_not_called()
            self.assertEqual(sentinel.read_text(), 'previous build')
        self.assertIn('MediaChecks', self.output.getvalue())
        self.assertIn('VideoChecks', self.output.getvalue())

    def test_timeout_keeps_partial_output_even_if_pass_marker_was_printed(self):
        for output in (b'MEDIA_CHECKS_PASS\npartial \xff', 'MEDIA_CHECKS_PASS\npartial', None):
            with self.subTest(output=output):
                timeout = subprocess.TimeoutExpired(['java'], 7, output=output)
                with self.assertRaisesRegex(RuntimeError, r'zombie.radio.devices.MediaChecks timed out after 7 seconds; output saved to .*MediaChecks.log'):
                    self.run_build('--test', 'MediaChecks', '--test-timeout', '7', java_result=timeout)
                expected = output if isinstance(output, bytes) else (output or '').encode()
                self.assertEqual((self.root / 'build/MediaChecks.log').read_bytes(), expected)
                self.assertEqual(len(self.java_calls()), 1)
                self.assertEqual(self.sentinel.read_text(), 'previous Java mod')
                self.assertFalse(list((self.root / 'build').glob('.build-*')))

    def test_completed_checks_still_require_successful_exit_and_marker(self):
        for result, failure in [(subprocess.CompletedProcess(['java'], 1, stdout='MEDIA_CHECKS_PASS'), subprocess.CalledProcessError), (subprocess.CompletedProcess(['java'], 0, stdout='incomplete'), RuntimeError)]:
            with self.subTest(result=result), self.assertRaises(failure):
                self.run_build('--test', 'MediaChecks', java_result=result)
            self.assertEqual((self.root / 'build/MediaChecks.log').read_text(), result.stdout)
            self.assertEqual(self.sentinel.read_text(), 'previous Java mod')
            self.assertFalse(list((self.root / 'build').glob('.build-*')))

    def test_selected_checks_use_a_fresh_classpath_each_run(self):
        stale = self.root / 'build/test-classes/RemovedHelper.class'
        stale.parent.mkdir(parents=True)
        stale.write_bytes(b'stale class')
        paths = []
        for _ in range(2):
            self.run_build('--test', 'MediaChecks')
            compilation = next(call.args[0] for call in self.run.call_args_list if '-sourcepath' in call.args[0])
            classes = Path(compilation[compilation.index('-d') + 1])
            command = self.java_calls()[0].args[0]
            self.assertEqual(command[command.index('-cp') + 1].split(os.pathsep)[0], str(classes))
            self.assertNotEqual(classes, stale.parent)
            self.assertFalse(classes.exists())
            paths.append(classes)
        self.assertNotEqual(*paths)
        self.assertEqual(stale.read_bytes(), b'stale class')


if __name__ == '__main__':
    unittest.main()
