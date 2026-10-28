"""Opt-in real NSGL regression; no visible window, physical display change or game."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import desktop, glfw


@unittest.skipUnless(sys.platform == 'darwin' and os.environ.get('PZ_NATIVE_GLFW_CHECK') == '1',
                     'opt-in native framebuffer check: PZ_NATIVE_GLFW_CHECK=1, PZ_GAME, PZ_JDK; outside sandbox')
class NativeGlfwTests(unittest.TestCase):
    def test_original_sleep_filter_fails_and_private_copy_reads_real_framebuffer(self):
        game, jdk = Path(os.environ['PZ_GAME']), Path(os.environ['PZ_JDK'])
        probe_before = desktop.require_gui_access()
        with tempfile.TemporaryDirectory(prefix='pz-glfw-regression-') as directory:
            root = Path(directory)
            metadata = glfw.prepare(game, root / 'native', jdk / 'bin/java')
            support = ROOT / 'tests/native_queue/support'
            environment = {key: value for key, value in os.environ.items()
                           if key not in ('JAVA_TOOL_OPTIONS', 'JDK_JAVA_OPTIONS', '_JAVA_OPTIONS', 'DYLD_INSERT_LIBRARIES')}
            subprocess.run([str(jdk / 'bin/javac'), '--release', '25', '-cp', str(game / 'projectzomboid.jar'),
                            '-d', str(root), str(support / 'ToolkitGlfwProbe.java')], check=True,
                           capture_output=True, text=True, timeout=30, env=environment)
            stub = root / 'sleep-stub.dylib'
            subprocess.run(['/usr/bin/clang', '-arch', metadata['architecture'], '-dynamiclib', '-framework', 'CoreGraphics',
                            '-o', str(stub), str(support / 'ToolkitDisplaySleepStub.c')], check=True,
                           capture_output=True, text=True, timeout=30, env=environment)
            original = root / 'original.dylib'
            with zipfile.ZipFile(game / 'projectzomboid.jar') as archive:
                original.write_bytes(archive.read(metadata['source_entry']))

            def launch(library, sleeping):
                env = dict(environment)
                if sleeping:
                    env['DYLD_INSERT_LIBRARIES'] = str(stub)
                return subprocess.run([str(jdk / 'bin/java'), '-XstartOnFirstThread',
                                       '--enable-native-access=ALL-UNNAMED',
                                       '-Dorg.lwjgl.glfw.libname=' + str(library),
                                       '-Dorg.lwjgl.system.SharedLibraryExtractPath=' + str(root / 'extracted'),
                                       '-cp', str(root) + os.pathsep + str(game / 'projectzomboid.jar'),
                                       'ToolkitGlfwProbe'], cwd=game, env=env, capture_output=True,
                                      text=True, timeout=30)

            baseline = launch(original, True)
            self.assertNotEqual(baseline.returncode, 0, baseline.stdout + baseline.stderr)
            self.assertIn('Connected display/video mode unavailable', baseline.stderr)
            for simulated_sleep in (False, True):
                result = launch(metadata['library'], simulated_sleep)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('GLFW_FRAMEBUFFER_READY', result.stdout)
                print(json.dumps({'simulated_sleep': simulated_sleep, 'probe': result.stdout.strip(),
                                  'physical_display': desktop.display_state()}))
            # These observations are real, separate from the child-only model;
            # natural physical sleep/wake is allowed while the regression runs.
            print(json.dumps({'physical_before': probe_before, 'physical_after': desktop.display_state()}))


if __name__ == '__main__':
    unittest.main()
