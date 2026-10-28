"""The benchmark observer is present in native and optimized arms without changing control admission."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
import optimizer_profile
from queue_checks.adapters import optimizer_benchmark as benchmark


class BenchmarkViewportStagingTests(unittest.TestCase):
    def fixture(self, case='seed', enabled=False):
        temporary = tempfile.TemporaryDirectory(prefix='benchmark-viewport-')
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        project, output, game, jdk = [root / name for name in ('project', 'output', 'game', 'jdk')]
        for folder in (project, output, game, jdk):
            folder.mkdir()
        native = b'reviewed-native'
        archive = root / 'official.zip'
        with zipfile.ZipFile(archive, 'w') as bundle:
            bundle.writestr('pzopt/Config.class', b'official-overlay')
        with zipfile.ZipFile(game / 'projectzomboid.jar', 'w') as bundle:
            bundle.writestr('zombie/Native.class', native)
        manifest = {'release_sha256': hashlib.sha256(archive.read_bytes()).hexdigest(),
                    'native_guards': {'zombie/Native.class': hashlib.sha256(native).hexdigest()},
                    'selected_files': {'pzopt/Config.class': hashlib.sha256(b'official-overlay').hexdigest()},
                    'profile': {'id': 'reviewed-fixture', 'properties': {'enabled': 'true', 'fogPass': 'false'}}}
        files = {'tests/optimizer_trial/candidate-manifest.json': json.dumps(manifest),
                 'tests/native_queue/optimizer-benchmark/java/Main.java': 'class Main {}',
                 'tests/native_queue/optimizer-benchmark/java/mod.info.template': 'id=PZDrivingPerfProbe\n',
                 'tests/native_queue/support/viewport/Main.java': 'class Main {}'}
        cache = output / 'client1'
        for name, text in files.items():
            target = project / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        cache_files = {'classes/ToolkitSmokeLauncher.java': 'public class ToolkitSmokeLauncher { public static void main(String[] args) throws Exception { keepWindowGuards(); } }',
                       'classes/ToolkitWindowBootstrap.java': 'class ToolkitWindowBootstrap {}',
                       'mods/PZDrivingBench/42/media/lua/client/DrivingBenchStart.lua': 'starter',
                       'mods/PZDrivingBench/42/media/lua/client/DrivingBenchClient.lua': 'if C.ready or C.stage=="failed" or not isIngameState() or not F.allowed() then return end',
                       'mods/PZDrivingBench/42/media/lua/shared/DrivingBenchFixture.lua': 'START_X=10818, START_Y=10118',
                       'options.ini': 'fullscreen=false\n', 'Lua/placeholder': ''}
        for name, text in cache_files.items():
            target = cache / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        selection = {'kind': 'sp', 'clients': 1, 'cases': [case], 'languages': ['EN'], 'mode': 'native',
                     'resources': {'exclusive': True}, 'mods': ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit', 'PZDrivingBench'],
                     'options': {'optimizer_enabled': enabled, 'optimizer_archive': str(archive)}}
        if case == 'drive':
            selection['options']['world_template'] = 'sealed-fixture'
        runtime = {'roles': {'client1': {'cache': str(cache), 'classes': str(cache / 'classes')}}, 'fixture': {'mods': []}}
        return project, output, game, jdk, selection, runtime, manifest

    @staticmethod
    def compile_fixture(command, **kwargs):
        if '-d' in command:
            destination = Path(command[command.index('-d') + 1]) / 'net/fixture/Probe.class'
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(b'compiled-probe')

    def stage(self, args):
        project, output, game, jdk, selection, runtime, _ = args
        with patch.object(benchmark.subprocess, 'run', side_effect=self.compile_fixture), \
                patch('prepare_optimizer_trial.build_bridge'), \
                patch.object(optimizer_profile, 'stage', side_effect=AssertionError('Control must not enter full optimizer stage')):
            benchmark.stage(project, output, game, jdk, selection, {}, runtime)

    def test_seed_native_drive_and_optimized_drive_stage_the_same_guarded_observer(self):
        for case, enabled in (('seed', False), ('drive', False), ('drive', True)):
            with self.subTest(case=case, enabled=enabled):
                args = self.fixture(case, enabled)
                self.stage(args)
                project, output, _, _, selection, runtime, manifest = args
                self.assertEqual(runtime['fixture']['mods'].count('NativeViewportProbe'), 1)
                helper = output / 'client1/mods/NativeViewportProbe/42'
                self.assertIn('javaPkgName=net.alexredby.nativeviewport', (helper / 'mod.info').read_text())
                with zipfile.ZipFile(helper / 'media/java/NativeViewportProbe.jar') as bundle:
                    self.assertIn('net/fixture/Probe.class', bundle.namelist())
                    self.assertEqual(bundle.read('native-optimizer-guards.properties').decode(), ''.join(
                        name + '=' + value + '\n' for name, value in sorted(manifest['native_guards'].items())))
                classes = output / 'client1/classes'
                self.assertEqual((classes / 'pzopt/Config.class').exists(), enabled)
                launcher = (classes / 'ToolkitSmokeLauncher.java').read_text()
                self.assertIn('keepWindowGuards();', launcher)
                self.assertEqual('pz.optimizerTrial.profile' in launcher, enabled)
                self.assertEqual('pz.optimizerTrial.prewarm' in launcher, enabled)
                self.assertEqual('pzopt.enabled' in launcher, enabled)
                inventory = {str(path.relative_to(project)) for path in benchmark.sources(project, selection)
                             if path.is_relative_to(project)}
                self.assertTrue({'tools/optimizer_profile.py', 'tests/native_queue/support/viewport/Main.java'} <= inventory)

    def test_changed_native_or_archive_is_rejected_before_observer_staging(self):
        for change in ('native', 'archive'):
            args = self.fixture()
            _, _, game, _, selection, _, _ = args
            if change == 'native':
                with zipfile.ZipFile(game / 'projectzomboid.jar', 'w') as bundle:
                    bundle.writestr('zombie/Native.class', b'changed')
            else:
                Path(selection['options']['optimizer_archive']).write_bytes(b'changed')
            with patch.object(optimizer_profile, 'stage_viewport') as observer:
                with self.assertRaisesRegex(ValueError, 'Unsupported native input|Official archive differs'):
                    self.stage(args)
                observer.assert_not_called()

    def test_shared_helper_still_stages_all_roles_from_one_compilation(self):
        project, output, game, jdk, _, runtime, manifest = self.fixture()
        runtime['roles']['server'] = {'cache': str(output / 'server')}
        with patch.object(optimizer_profile.subprocess, 'run', side_effect=self.compile_fixture) as compiler:
            optimizer_profile.stage_viewport(project, output / 'observer-inputs', game, jdk, runtime, manifest['native_guards'])
            self.assertEqual(compiler.call_count, 1)
        for role in ('client1', 'server'):
            self.assertTrue((output / role / 'mods/NativeViewportProbe/42/media/java/NativeViewportProbe.jar').is_file())
        self.assertEqual(runtime['fixture']['mods'], ['NativeViewportProbe'])
        self.assertNotIn('optimizer_overlay', runtime['roles']['client1'])


if __name__ == '__main__':
    unittest.main()
