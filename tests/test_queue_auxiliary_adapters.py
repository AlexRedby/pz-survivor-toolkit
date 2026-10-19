"""Auxiliary intake adapters are checked without a game process or encoder."""
import json
from pathlib import Path
import sys
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import auxiliary as adapter


class AuxiliaryAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.output = self.root / 'run'
        self.cache = self.output / 'client1'
        self.cache.mkdir(parents=True)
        (self.cache / 'options.ini').write_text('height=720\nvoiceEnable=false\n')
        self.runtime = {'roles': {'client1': {'cache': str(self.cache)}}}
        self.selection = {'suite': 'video-recording', 'cases': ['captures'], 'kind': 'sp',
                          'languages': ['EN'], 'mode': 'native',
                          'mods': ['ZombieBuddy', 'PZToolkitJavaPatches', 'PZSurvivorToolkit'],
                          'ports': [17463, 17464], 'options': {}}
        for name in ('ffmpeg', 'ffprobe', 'patch_jar'):
            path = self.root / name
            path.write_bytes(b'explicit test dependency')
            path.chmod(0o755)
            self.selection['options'][name] = str(path)

    def stage(self, locations=None):
        adapter.stage(ROOT, self.output, self.root / 'game', self.root / 'jdk',
                      self.selection, locations or {}, self.runtime)

    def test_video_stage_reuses_fixture_and_keeps_outputs_inside_profile(self):
        self.stage()
        helper = self.cache / 'mods/VideoFixture/42/media/lua/client'
        self.assertEqual((helper / 'ZZVideoFixture.lua').read_bytes(),
                         (ROOT / 'tests/native_queue/contributions/video-recording/VideoFixture.lua').read_bytes())
        config = (helper / 'ToolkitVideoConfig.lua').read_text()
        self.assertIn(str(self.cache / 'videos'), config)
        self.assertIn(str(self.root / 'ffmpeg'), config)
        self.assertEqual(self.runtime['fixture']['mods'], ['VideoFixture'])
        self.assertIn(self.root / 'ffprobe', adapter.sources(ROOT, self.selection))
        self.selection['options']['ffmpeg'] = 'relative-ffmpeg'
        with self.assertRaisesRegex(ValueError, 'absolute'):
            adapter.validate(self.selection)

    def test_item_stage_retains_all_scene_assertions_and_adds_settings(self):
        self.selection.update(suite='item-tags', cases=['scenes'], languages=['RU'], mods=adapter.ITEM_MODS)
        toolkit = self.root / 'toolkit'
        visuals = toolkit / '42/media/lua/client/PZSurvivorToolkit/TagVisuals.lua'
        visuals.parent.mkdir(parents=True)
        visuals.write_text('return {"Item_Plate","media/ui/test.png"}')
        self.stage({'PZSurvivorToolkit': toolkit})
        client = self.cache / 'mods/QuartermasterScreens/42/media/lua/client'
        fixture = (client / 'ZZQuartermasterScreens.lua').read_text()
        self.assertIn('assert(getTexture(', fixture)
        self.assertIn("shot('05-vanilla-inventory')", fixture)
        self.assertIn('setValue(false)', (client / 'ZZQuartermasterSetup.lua').read_text())
        self.assertIn('height=900', (self.cache / 'options.ini').read_text())
        self.assertEqual(self.runtime['fixture']['mods'], ['QuartermasterScreens'])
        (self.cache / 'console.txt').write_text('[QM_SCREEN] COMPLETE\n')
        self.assertTrue(adapter.verify(self.output, self.selection, {})['issues'])
        intake = ROOT / 'tests/native_queue/contributions/item-tags'
        names = json.loads((intake / 'manifest.json').read_text())['expected_screenshots']
        text = '[QM_SCREEN] COMPLETE\n[QM_SCREEN] SETTINGS_READY\n[QM_SCREEN] VISUAL 2\n'
        text += '[QM_SCREEN] SAVE exact IDs and reopen passed\n[QM_SCREEN] GEOM list width=1\n[QM_SCREEN] GEOM clean row=1\n'
        screenshots = self.cache / 'Screenshots'
        screenshots.mkdir()
        for name in names:
            (screenshots / name).write_bytes(adapter.PNG)
            text += '[QM_SCREEN] SHOT ' + name.removeprefix('tags-').removesuffix('.png') + '\n'
        (self.cache / 'console.txt').write_text(text)
        self.assertFalse(adapter.verify(self.output, self.selection, {})['issues'])
        (screenshots / names[3]).unlink()
        self.assertIn('screenshot', adapter.verify(self.output, self.selection, {})['issues'][0])

    def test_locked_pack_uses_actual_ini_order_but_still_requires_all_tag_dependencies(self):
        mods = list(adapter.ITEM_MODS)
        a, b = mods.index('PZSurvivorToolkit'), mods.index('BravoItemDetails')
        mods[a], mods[b] = mods[b], mods[a]
        self.selection.update(suite='item-tags', cases=['scenes'], languages=['RU'], mods=mods)
        with self.assertRaisesRegex(ValueError, 'load order'):
            adapter.validate(self.selection)
        self.selection['options']['pack_lock'] = '/explicit/validated-by-common-prepare.lock.json'
        adapter.validate(self.selection)
        self.selection['mods'].remove('PZSurvivorToolkit')
        with self.assertRaisesRegex(ValueError, 'Required fixture mods missing'):
            adapter.validate(self.selection)

    def test_animal_stage_uses_exact_builder_and_identical_shared_connect_config(self):
        self.selection.update(suite='animal-trailer', cases=['equipment-fixed'], kind='mp')
        server = self.output / 'server'
        server.mkdir()
        self.runtime['roles']['server'] = {'cache': str(server)}
        calls = []
        def build(game, jdk, patch_jar, output, scenario):
            calls.append((patch_jar, scenario))
            helper = output / 'mods/AnimalTrailerBaseline/42/media/lua/shared'
            helper.mkdir(parents=True)
            (helper / 'ZAnimalTrailerConfig.lua').write_text('AnimalTrailerFixtureConfig={}\n')
            (output / 'runtime-manifest.json').write_text(json.dumps({'helper_mod_ids': ['AnimalTrailerBaseline']}))
        with patch.object(adapter, '_load', return_value=SimpleNamespace(build=build)):
            self.stage()
        relative = 'mods/AnimalTrailerBaseline/42/media/lua/shared/ZAnimalTrailerConfig.lua'
        self.assertEqual((server / relative).read_bytes(), (self.cache / relative).read_bytes())
        self.assertIn('port=17463', (server / relative).read_text())
        self.assertEqual(calls, [(self.root / 'patch_jar', 'equipment')])
        self.assertEqual(self.runtime['fixture']['server_ready'], '[ANIMAL_TRAILER] SERVER READY')
        missing = '[ANIMAL_TRAILER] CLIENT MISSING index=2 ids=101/201,103/203\n'
        self.assertTrue(any(marker in missing for marker in self.runtime['fixture']['failure_markers']))
        self.assertFalse(adapter.complete(self.selection, 'client1', missing))
        (self.cache / 'console.txt').write_text(missing)
        self.assertEqual(adapter.verify(self.output, self.selection, {})['outcomes'][0]['status'], 'failed')
        harness = adapter._load(ROOT / 'tests/test_queue_runner.py').NativeRunnerTests()
        harness.setUp()
        self.addCleanup(harness.doCleanups)
        harness.selection.update(self.selection)
        harness.selection.update(suite='animal-trailer', cases=['equipment-fixed'], kind='mp', clients=1,
                                 ports=[29343, 29344], timeout_seconds=1200)
        server_cache = harness.root / 'server'
        (server_cache / 'Server').mkdir(parents=True)
        (server_cache / 'options.ini').write_text('voiceEnable=false\n')
        (server_cache / 'Server/queue-smoke.ini').write_text('VoiceEnable=false\n')
        harness.runtime.update(server_name='queue-smoke', fixture=self.runtime['fixture'])
        harness.runtime['roles']['server'] = {'cache': str(server_cache)}
        (harness.root / 'selection.json').write_text(json.dumps(harness.selection))
        (harness.root / 'runtime.json').write_text(json.dumps(harness.runtime))
        harness.content = '[ANIMAL_TRAILER] SERVER READY\n' + missing
        with patch('queue_checks.admission.socket.socket'):
            execution, kills = harness.invoke(sleep=lambda _: self.fail('Terminal missing marker waited for timeout'))
        self.assertEqual(execution['status'], 'failed')
        self.assertIn('Native fixture failed', execution['error'])
        self.assertEqual({call.args[0] for call in kills}, {101, 102})
        self.assertEqual(set(execution['processes']), {'server', 'client1'})
        self.assertTrue(all(row['exit_code'] == -15 for row in execution['processes'].values()))
        self.assertEqual(json.loads((harness.root / 'execution.json').read_text())['status'], 'failed')
        self.selection['cases'] = ['equipment-missing']
        with self.assertRaisesRegex(ValueError, 'must omit'):
            adapter.validate(self.selection)

    def test_animal_verification_calls_retained_strict_identity_and_drop_checker(self):
        self.selection.update(suite='animal-trailer', cases=['combined-shared'], kind='mp')
        intake = ROOT / 'tests/native_queue/contributions/animal-trailer'
        verifier = adapter._load(intake / 'verify.py')
        with patch.dict(sys.modules, {'verify': verifier}):
            fixtures = adapter._load(intake / 'test_verify.py')
        server, client = fixtures.logs()
        (self.output / 'server-launch.log').write_text(server)
        (self.cache / 'console.txt').write_text(client.replace('CLIENT COMPLETE', '[ANIMAL_TRAILER] CLIENT COMPLETE'))
        self.assertFalse(adapter.verify(self.output, self.selection, {})['issues'])
        (self.cache / 'console.txt').write_text(client.replace('CLIENT COMPLETE', '[ANIMAL_TRAILER] CLIENT COMPLETE').replace('animal=102', 'animal=999'))
        result = adapter.verify(self.output, self.selection, {})
        self.assertIn('Exact animal', result['issues'][0])
        self.assertEqual(result['outcomes'][0]['status'], 'failed')

    def test_animal_groups_require_the_same_immutable_environment_and_missing_control_isolated(self):
        self.selection.update(suite='animal-trailer', kind='mp', clients=1)
        self.selection['cases'] = ['equipment-fixed', 'ghost', 'timer-starved', 'combined-starved']
        adapter.validate(self.selection)
        self.selection['cases'] = ['timer-shared', 'combined-shared']
        self.selection['mods'].append('AnimalTrailerSyncMPFix')
        adapter.validate(self.selection)
        self.assertIn(ROOT / 'tests/native_queue/support/QueueFixtureSession.lua', adapter.sources(ROOT, self.selection))
        with self.assertRaisesRegex(ValueError, 'one actual client'):
            adapter.validate(dict(self.selection, clients=2))
        for cases in (['equipment-fixed', 'timer-shared'], ['equipment-missing', 'equipment-fixed'],
                      ['timer-starved', 'combined-shared']):
            self.selection['cases'] = cases
            with self.subTest(cases=cases), self.assertRaisesRegex(ValueError, 'immutable'):
                adapter.validate(self.selection)

    def test_animal_group_stage_passes_all_cases_and_uses_real_single_client_identity(self):
        self.selection.update(suite='animal-trailer', kind='mp', cases=['timer-shared', 'combined-shared'])
        self.selection['mods'].append('AnimalTrailerSyncMPFix')
        timer = self.root / 'timer-fix'
        timer.mkdir()
        jar = timer / 'tested.jar'
        jar.write_bytes(b'one immutable timer build')
        intake = self.root / 'animal-intake'
        intake.mkdir()
        (intake / 'manifest.json').write_text(json.dumps({'dependencies': {'timer_fixed': {
            'jar_sha256': adapter.hashlib.sha256(jar.read_bytes()).hexdigest()}}}))
        server = self.output / 'server'
        server.mkdir()
        self.runtime['roles']['server'] = {'cache': str(server)}
        calls = []
        def build(game, jdk, patch_jar, output, scenario, cases=None):
            calls.append((scenario, cases))
            helper = output / 'mods/AnimalTrailerBaseline/42/media/lua/shared'
            helper.mkdir(parents=True)
            (helper / 'ZAnimalTrailerConfig.lua').write_text('AnimalTrailerFixtureConfig={cases={"timer-shared","combined-shared"}}\n')
            (output / 'runtime-manifest.json').write_text(json.dumps({'helper_mod_ids': ['AnimalTrailerBaseline']}))
        with patch.object(adapter, '_intake', return_value=intake), patch.object(adapter, '_load', return_value=SimpleNamespace(build=build)):
            self.stage({'AnimalTrailerSyncMPFix': timer})
            jar.write_bytes(b'changed timer jar')
            with self.assertRaisesRegex(ValueError, 'exact tested 1.3'):
                self.stage({'AnimalTrailerSyncMPFix': timer})
        self.assertEqual([('timer', ['timer-shared', 'combined-shared'])], calls)
        relative = 'mods/AnimalTrailerBaseline/42/media/lua/shared/ZAnimalTrailerConfig.lua'
        self.assertEqual((server / relative).read_bytes(), (self.cache / relative).read_bytes())
        self.assertIn('username="client1"', (self.cache / relative).read_text())
        self.assertIn('[QUEUE_SESSION] QUARANTINE ', self.runtime['fixture']['failure_markers'])

    def test_grouped_animal_verifier_requires_each_strict_case_and_ordered_joint_reset(self):
        self.selection.update(suite='animal-trailer', kind='mp', cases=['timer-shared', 'combined-shared'])
        intake = ROOT / 'tests/native_queue/contributions/animal-trailer'
        verifier = adapter._load(intake / 'verify.py')
        with patch.dict(sys.modules, {'verify': verifier}):
            fixture = adapter._load(intake / 'test_verify.py')
        def marker(event, case, epoch, actor, ok=False):
            return f'[QUEUE_SESSION] {event} case={case} epoch={epoch} actor={actor}' + (' ok=true' if ok else '') + '\n'
        def session(role):
            text = '[AnimalTrailerSyncMPFix] ACTIVE 1.3\n' if role == 'server' else ''
            for epoch, case in enumerate(self.selection['cases'], 1):
                text += marker('BEGIN', case, epoch, role)
                text += marker('PREPARE', case, epoch, 'client1') + marker('START', case, epoch, role)
                text += fixture.logs()[0 if role == 'server' else 1].replace('[AnimalTrailerSyncMPFix] ACTIVE 1.3\n', '')
                text += marker('FINISH', case, epoch, 'client1', True)
                text += f'[ANIMAL_TRAILER] {"SERVER" if role == "server" else "CLIENT"} PROBE_RESET clean=true\n'
                text += f'[ANIMAL_TRAILER] {"SERVER" if role == "server" else "CLIENT"} OWNED_RESET animals=3 items=4 trailer=1\n'
                text += marker('CLEANUP' if role == 'server' else 'LOCAL_CLEAN', case, epoch, role, True)
                text += marker('CLEANUP', case, epoch, 'client1', True)
                text += marker('JOINT_CLEAN', case, epoch, role, True)
            return text + marker('COMPLETE', case, epoch, role).rstrip() + ' cases=2\n'
        originals = {role: session(role) for role in ('server', 'client1')}
        for role, text in originals.items():
            (self.output / (role + '-launch.log')).write_text(text)
        result = adapter.verify(self.output, self.selection, {})
        self.assertEqual([], result['issues'])
        self.assertEqual(self.selection['cases'], [row['case'] for row in result['outcomes']])
        self.assertTrue(all(row['status'] == 'passed' for row in result['outcomes']))
        self.assertFalse(adapter.complete(self.selection, 'client1', 'CLIENT COMPLETE\n'))
        self.assertTrue(adapter.complete(self.selection, 'client1', originals['client1']))
        server_path = self.output / 'server-launch.log'
        clean = marker('JOINT_CLEAN', 'timer-shared', 1, 'server', True)
        for broken in (originals['server'].replace(clean, ''), originals['server'] + clean,
                       originals['server'].replace('OWNED_RESET animals=3 items=4 trailer=1', 'OWNED_RESET animals=2 items=4 trailer=1', 1),
                       originals['server'].replace('{201=4, 202=4, 203=4}', '{201=0, 202=0, 203=4}', 1)):
            server_path.write_text(broken)
            with self.subTest(broken=broken[:80]):
                result = adapter.verify(self.output, self.selection, {})
                self.assertEqual('failed', result['outcomes'][0]['status'])
                self.assertEqual('passed', result['outcomes'][1]['status'])
        server_path.write_text(originals['server'])
        client_path = self.output / 'client1-launch.log'
        client_path.write_text(originals['client1'].replace('releases=1', 'releases=0'))
        self.assertEqual('failed', adapter.verify(self.output, self.selection, {})['outcomes'][1]['status'])

    def test_video_verifier_runs_probe_full_decode_and_extraction_and_rejects_decode_failure(self):
        videos = self.cache / 'videos'
        videos.mkdir()
        text = '[QUEUE_TEST] VOICE_DISABLED\n[VIDEO_TEST] RESTART\n[VIDEO_TEST] PASSED\n'
        for name in ('first.mp4', 'second.mp4'):
            video = videos / name
            video.write_bytes(b'test clip')
            text += '[VIDEO_TEST] STOP wallMs=3515\n'
            text += f'[VIDEO_TEST] RESULT state=completed file={video} frames=106 seconds=3.533333333333333 captured=106 dropped=0 width=63 height=47 error=\n'
        (self.cache / 'console.txt').write_text(text)
        commands = []
        def encoder(command, **kwargs):
            commands.append(command)
            if '-show_streams' in command:
                return SimpleNamespace(stdout=json.dumps({'streams': [{'codec_type':'video', 'codec_name':'h264',
                    'width':64, 'height':48, 'r_frame_rate':'30/1', 'avg_frame_rate':'30/1',
                    'nb_read_frames':'106', 'duration':'3.533333'}]}))
            if '-vf' in command:
                for index in range(1, 4):
                    Path(command[-1].replace('%02d', f'{index:02d}')).write_bytes(adapter.PNG)
            return SimpleNamespace(returncode=0)
        with patch.object(adapter.subprocess, 'run', side_effect=encoder):
            self.assertFalse(adapter.verify(self.output, self.selection, {})['issues'])
        self.assertEqual(len(commands), 6)
        self.assertEqual(sum('-xerror' in command for command in commands), 2)
        self.assertEqual(sum('-show_streams' in command for command in commands), 2)
        with patch.object(adapter.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'decode')):
            self.assertEqual(adapter.verify(self.output, self.selection, {})['outcomes'][0]['status'], 'failed')

    def test_video_requires_terminal_assertion_marker_before_decode(self):
        (self.cache / 'console.txt').write_text('[VIDEO_TEST] RESULT state=completed\n')
        result = adapter.verify(self.output, self.selection, {})
        self.assertIn('completion', result['issues'][0])


if __name__ == '__main__':
    unittest.main()
