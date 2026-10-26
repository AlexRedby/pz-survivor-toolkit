"""SP trial staging and evidence boundaries; no native process or game loop."""
import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import optimizer_profile
from queue_checks.adapters import optimizer_trial as trial
from queue_checks.adapters import driving_benchmark as driving


class OptimizerTrialAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='optimizer-adapter-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project, self.output, self.game, self.jdk = [self.root / name for name in ('project', 'output', 'game', 'jdk')]
        for path in (self.project, self.output, self.game, self.jdk):
            path.mkdir()
        self.cache = self.output / 'client1'
        for suffix in ('Lua', 'classes', 'mods/ActionQueueTest/42/media/lua/client'):
            (self.cache / suffix).mkdir(parents=True, exist_ok=True)
        (self.cache / 'classes/ToolkitSmokeLauncher.java').write_text(
            'public class ToolkitSmokeLauncher { public static void main(String[] args) throws Exception { keepWindowGuards(); } }')
        (self.cache / 'classes/ToolkitWindowBootstrap.java').write_text('owned window bootstrap')
        for name in ('tests/native_queue/driving-benchmark/client/ZZDrivingBenchCheck.lua',
                     'tests/native_queue/optimizer-trial/client/ZZOptimizerTrialCheck.lua',
                     'tests/driving_benchmark/mods/PZDrivingBench/42/mod.info',
                     'tests/driving_benchmark/mods/PZDrivingBench/42/media/lua/client/DrivingBenchStart.lua',
                     'tests/native_queue/support/viewport/Main.java',
                     'tests/optimizer_trial/PZOptimizerTrialTelemetry.lua'):
            path = self.project / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture:' + path.name)
        resources = {'pzopt/Config.class': b'pinned-helper', 'org/lwjglx/opengl/Display.class': b'pinned-display'}
        self.archive = self.root / 'official.zip'
        with zipfile.ZipFile(self.archive, 'w') as z:
            for name, value in resources.items():
                z.writestr(name, value)
        with zipfile.ZipFile(self.game / 'projectzomboid.jar', 'w') as z:
            z.writestr('zombie/Native.class', b'native')
        self.manifest = {'release_sha256': hashlib.sha256(self.archive.read_bytes()).hexdigest(),
            'selected_files': {name: hashlib.sha256(value).hexdigest() for name, value in resources.items()},
            'native_guards': {'zombie/Native.class': hashlib.sha256(b'native').hexdigest()},
            'native_absences': ['pzopt/Config.class'],
            'profile': {'id': 'fixture-profile', 'properties': {'enabled': 'true', 'instrument': 'false'}}}
        (self.project / 'tests/optimizer_trial/candidate-manifest.json').write_text(json.dumps(self.manifest))
        self.selection = {'suite': 'optimizer-trial', 'kind': 'sp', 'clients': 1, 'cases': ['ready'],
            'languages': ['EN'], 'mode': 'native',
            'mods': ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'],
            'options': {'optimizer_archive': str(self.archive)}}
        self.runtime = {'roles': {'client1': {'cache': str(self.cache), 'classes': str(self.cache / 'classes')}}}

    def stage(self):
        def compile_fixture(command, **kwargs):
            if '-d' in command:
                destination = Path(command[command.index('-d') + 1]) / 'net/fixture/Viewport.class'
                destination.parent.mkdir(parents=True)
                destination.write_bytes(b'compiled-viewport')

        def bridge_fixture(destination, game, jdk, project):
            mod = Path(destination) / 'PZDrivingOptimizerBridge'
            (mod / '42').mkdir(parents=True)
            return mod

        with patch('optimizer_profile.subprocess.run', side_effect=compile_fixture), \
                patch('prepare_optimizer_trial.build_bridge', side_effect=bridge_fixture) as build:
            trial.stage(self.project, self.output, self.game, self.jdk, self.selection, {}, self.runtime)
            return build.call_count

    def test_sp_uses_shared_verified_overlay_bridge_and_viewport_staging(self):
        original = copy.deepcopy(self.selection)
        self.assertEqual(self.stage(), 1)
        self.assertEqual(self.selection, original)
        self.assertEqual(self.runtime['fixture']['mods'], ['PZDrivingBench', 'NativeViewportProbe', 'PZDrivingOptimizerBridge'])
        self.assertEqual((self.cache / 'mods/PZDrivingBench/42/media/lua/client/DrivingBenchStart.lua').read_bytes(),
            (self.project / 'tests/driving_benchmark/mods/PZDrivingBench/42/media/lua/client/DrivingBenchStart.lua').read_bytes())
        overlay = self.cache / 'optimizer-overlay'
        self.assertEqual(self.runtime['roles']['client1']['optimizer_overlay'], str(overlay))
        for name in self.manifest['selected_files']:
            self.assertTrue((overlay / name).is_file())
            self.assertFalse((self.cache / 'classes' / name).exists())
        self.assertTrue((self.cache / 'mods/NativeViewportProbe/42/media/java/NativeViewportProbe.jar').is_file())
        self.assertTrue((self.cache / 'mods/PZDrivingOptimizerBridge/42/media/lua/client/PZOptimizerTrialTelemetry.lua').is_file())
        self.assertEqual((self.cache / 'Lua/DrivingBench-run.txt').read_text(), trial.SP_WORLD + '\n')
        self.assertTrue(trial.SP_WORLD.startswith('PZDrivingBench-OptimizerTrial-'))
        launcher = (self.cache / 'classes/ToolkitSmokeLauncher.java').read_text()
        self.assertIn('keepWindowGuards();', launcher)
        self.assertIn('"pz.optimizerTrial.mode", "singleplayer"', launcher)
        self.assertIn('"pz.optimizerTrial.prewarm", "true"', launcher)
        self.assertIn('"pzopt.instrument", "false"', launcher)
        self.assertEqual(optimizer_profile.client_classpath(self.runtime['roles']['client1']).split(optimizer_profile.os.pathsep)[0], str(overlay))
        receipt = json.loads((self.output / 'optimizer-inputs/receipt.json').read_text())
        self.assertTrue(receipt['prewarm_bridge'])
        self.assertEqual(receipt['roles'], ['client1'])

    def test_staging_still_rejects_changed_archive_and_native_bytes(self):
        for mutation in ('archive', 'native'):
            with self.subTest(mutation=mutation):
                # Each rejected stage owns a fresh output; neither reaches Java compilation.
                self.output = self.root / ('rejected-' + mutation)
                self.output.mkdir()
                self.cache = self.output / 'client1'
                for suffix in ('Lua', 'classes', 'mods/ActionQueueTest/42/media/lua/client'):
                    (self.cache / suffix).mkdir(parents=True, exist_ok=True)
                self.runtime = {'roles': {'client1': {'cache': str(self.cache), 'classes': str(self.cache / 'classes')}}}
                if mutation == 'archive':
                    self.archive.write_bytes(b'changed')
                else:
                    self.manifest['release_sha256'] = hashlib.sha256(self.archive.read_bytes()).hexdigest()
                    (self.project / 'tests/optimizer_trial/candidate-manifest.json').write_text(json.dumps(self.manifest))
                    with zipfile.ZipFile(self.game / 'projectzomboid.jar', 'w') as z:
                        z.writestr('zombie/Native.class', b'changed')
                with self.assertRaisesRegex(ValueError, 'Official archive|Changed native resource'):
                    self.stage()

    def test_trial_cannot_disable_its_production_prewarm_bridge(self):
        self.selection['options']['optimizer_prewarm'] = False
        with self.assertRaisesRegex(ValueError, 'production preload bridge'):
            trial.validate(self.selection)

    def test_gameplay_selection_is_unchanged_and_explicit_legacy_starter_is_supported(self):
        original = copy.deepcopy(self.selection)
        trial.validate(self.selection)
        self.assertEqual(self.selection, original)
        self.selection['mods'].append('PZDrivingBench')
        # Native common staging has already copied explicitly selected production sources.
        shutil.copytree(self.project / 'tests/driving_benchmark/mods/PZDrivingBench', self.cache / 'mods/PZDrivingBench')
        self.stage()
        self.assertEqual(self.runtime['fixture']['mods'], ['NativeViewportProbe', 'PZDrivingOptimizerBridge'])

    def evidence(self, tile_batch='false'):
        return '\n'.join((driving.COMPLETE,
            '[OptimizerTrial] prewarm armed; awaiting OnGameBoot; mode=singleplayer',
            '[OptimizerTrial] official cache and preload active',
            '[OptimizerTrial] OnGameBoot animation preload started mode=singleplayer postClientReset=false',
            '[OptimizerTrial] animation preload joined; animal preload started mode=singleplayer',
            '[OptimizerTrial] bridge ready mode=singleplayer client=false server=false session=1',
            '[OptimizerTrial] animal drain invoked mode=singleplayer client=false server=false',
            '[OptimizerTrial] extended active profile=xd3i-b42.21-d1bbdcf-bounded-v1 tileBatch=' + tile_batch
                + ' bakeScheduler=true occlusionRetain=true chunkHandoffDivisor=8',
            '[OptimizerTrial] bake scheduler used frames=12 grants=20',
            '[pzopt] anim sets preloaded in 1.2 s',
            '[pzopt] animalPreload: 12 animation sets, 6 action groups parsed',
            '[pzopt] animalPreload: 4 action groups handed to the game, 2 it had loaded first',
            '[OPTIMIZER_TRIAL_TEST] COMPLETE mode=native-walk'))

    def test_completion_requires_actual_sp_lifecycle_and_full_animal_handoff(self):
        text = self.evidence()
        self.assertTrue(trial.complete(self.selection, 'client1', text))
        for changed in (text.replace('client=false', 'client=true'),
                        text.replace('session=1', 'session=2'),
                        text.replace('animal drain invoked', 'animal drain missing'),
                        text.replace('4 action groups handed', '3 action groups handed'),
                        text.replace('grants=20', 'grants=0'),
                        text + '\n[OptimizerTrial] telemetry flush failed reason=WorldExit',
                        text + '\n[OptimizerTrial] drive telemetry disabled error=identity',
                        text + '\n[OptimizerTrial] prewarm disabled: restart required'):
            with self.subTest(text=changed):
                self.assertFalse(trial.complete(self.selection, 'client1', changed))

    def test_active_tile_batch_requires_real_merged_stamped_draws(self):
        text = self.evidence('true')
        self.assertFalse(trial.complete(self.selection, 'client1', text))
        self.assertTrue(trial.complete(self.selection, 'client1', text
            + '\n[OptimizerTrial] tile batch used starts=10 merged=20 stamped=30'))

    def test_snapshot_sources_include_shared_stager_and_native_viewport(self):
        sources = trial.sources(ROOT, self.selection)
        for name in ('tools/optimizer_profile.py', 'tools/check_optimizer_compatibility.py',
                     'tests/native_queue/support/viewport/Main.java',
                     'tests/driving_benchmark/mods/PZDrivingBench/42/mod.info',
                     'tests/optimizer_trial/PZOptimizerTrialTelemetry.lua'):
            self.assertIn(ROOT / name, sources)

    def test_failed_walk_is_not_reported_as_disabled_active_bridge(self):
        text = self.evidence().replace('[OPTIMIZER_TRIAL_TEST] COMPLETE mode=native-walk',
                                      '[OPTIMIZER_TRIAL_TEST] FAIL Player died during functional observation')
        (self.output / 'client1-launch.log').write_text(text)
        base = {'issues': [], 'outcomes': [{'actor': 'client1', 'status': 'passed'}], 'evidence': {}}
        with patch.object(driving, 'verify', return_value=base):
            result = trial.verify(self.output, self.selection, {})
        self.assertEqual(result['issues'], ['Functional optimizer walking/observation fixture failed'])
        self.assertEqual(result['outcomes'][0]['status'], 'failed')
        self.assertFalse(trial.complete(self.selection, 'client1', text))

    def test_lifecycle_failure_keeps_its_own_failed_verdict(self):
        text = self.evidence() + '\n[OptimizerTrial] prewarm disabled: fixture gate'
        (self.output / 'client1-launch.log').write_text(text)
        base = {'issues': [], 'outcomes': [{'actor': 'client1', 'status': 'passed'}], 'evidence': {}}
        with patch.object(driving, 'verify', return_value=base):
            result = trial.verify(self.output, self.selection, {})
        self.assertIn('Optimizer lifecycle/preload or observer failed', result['issues'])
        self.assertNotIn('Functional optimizer walking/observation fixture failed', result['issues'])
        self.assertEqual(result['outcomes'][0]['status'], 'failed')

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT required')
    def test_player_death_is_distinct_from_missing_actor_and_square(self):
        script = r'''
for _, name in ipairs({'TimedActions/ISTimedActionQueue','TimedActions/WalkToTimedAction',
    'Vehicles/TimedActions/ISExitVehicle','QueueTestSelection','DrivingBenchFixture'}) do
    package.loaded[name] = {}
end
Events = {OnTick={Add=function() end}}
local input = assert(io.open(arg[1])); local source = input:read('*a'); input:close()
local sample = assert(loadstring(source .. '\nreturn sample'))()
local function rejects(player, reason)
    local ok, problem = pcall(sample, player, 0)
    assert(not ok and problem:find(reason,1,true), tostring(problem))
end
rejects(nil, 'Player missing')
rejects({isDead=function() return true end}, 'Player died during functional observation')
rejects({isDead=function() return false end,getCurrentSquare=function() return nil end}, 'Player current square missing')
'''
        result = subprocess.run([shutil.which('luajit'), '-', str(ROOT / 'tests/native_queue/optimizer-trial/client/ZZOptimizerTrialCheck.lua')],
            input=script, text=True, capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)



if __name__ == '__main__':
    unittest.main()
