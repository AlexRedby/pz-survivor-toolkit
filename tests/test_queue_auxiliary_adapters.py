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
        with patch('queue_checks.runner.socket.socket'):
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
