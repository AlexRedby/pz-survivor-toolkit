"""The live corridor adapter cannot pass from readiness or screenshots alone."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
import subprocess
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import adapters
from queue_checks.adapters import basement_hall as hall


class BasementHallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        options = {}
        for name in ('ffmpeg', 'ffprobe'):
            executable = self.root / name
            executable.write_text('#!/bin/sh\nexit 0\n')
            executable.chmod(0o755)
            options[name] = str(executable)
        self.selection = dict(suite='basement-hall', cases=['fresh'], kind='sp', mode='toolkit',
                              clients=1, languages=['EN'], mods=hall.MODS, ports=[17343, 17344], options=options)
        self.video = patch.object(hall, '_video', return_value={'presented_frames': []})
        self.video.start()
        self.addCleanup(self.video.stop)

    def evidence(self, native_control=False):
        cache = self.root / 'client1'
        cache.mkdir(exist_ok=True)
        probes = []
        for phase, z in (('surface', 0), ('basement', -1), ('returned', 0)):
            probes.append(hall.MARKER + 'PROBE ' + json.dumps(dict(phase=phase, baseIndex=107, accessIndex=306,
                baseKey='c00d3' if native_control else '505a0000000c00d3', accessKey='c00d3',
                ownerIndex=16, stable=True, z=z, canSee=True, nativeControl=native_control)))
            (cache / ('basement-hall-' + phase + '.png')).write_bytes(b'\x89PNG\r\n\x1a\nfixture')
        save = cache / 'Saves/Sandbox/QueueBasementHall/map_meta.bin'
        save.parent.mkdir(parents=True, exist_ok=True)
        save.write_bytes(b'METAfixture')
        activation = (['[PZToolkitJavaPatches] Experimental B42.21 patch: basementRooms=true, mannequin=true',
                       'ERROR: General > duplicate RoomDef.metaID for room at 10707,9484,0'] if native_control else
                      ['[PZToolkitJavaPatches] Experimental B42.21 patch: basementHall=true, mannequin=true',
                 '[PZToolkitJavaPatches] Basement hall key separated: original=107, key='
                 + str(0x505A0000000C00D3) + ', accessKey=786643'])
        lines = [*activation,
                 hall.MARKER + 'READY',
                 hall.MARKER + 'LIGHT phase=surface held=true active=true charge=1 distance=15 strength=2 cone=false',
                 probes[0], hall.MARKER + 'SURFACE',
                 hall.MARKER + 'LIGHT phase=basement held=true active=true charge=0.99 distance=15 strength=2 cone=false',
                 probes[1], hall.MARKER + 'BASEMENT',
                 hall.MARKER + 'LIGHT phase=returned held=true active=true charge=0.98 distance=15 strength=2 cone=false',
                 probes[2], hall.MARKER + 'RETURNED', hall.MARKER + 'SAVED',
                 hall.MARKER + 'COMPLETE case=' + ('native-control' if native_control else 'fresh')]
        text = '\n'.join(lines) + '\n'
        (self.root / 'client1-launch.log').write_text(text)
        return text

    def test_registration_and_selection_isolate_fresh_and_sealed_reload(self):
        self.assertIs(adapters.get('basement-hall'), hall)
        hall.validate(self.selection)
        hall.validate(dict(self.selection, cases=['native-control']))
        hall.validate(dict(self.selection, cases=['reload'], options=dict(self.selection['options'], world_template='/sealed/template')))
        for change in ({'cases': ['fresh', 'reload']}, {'cases': ['reload']}, {'kind': 'mp'}, {'mode': 'native'},
                       {'languages': ['RU']}, {'clients': True}, {'mods': ['PZSurvivorToolkit']},
                       {'options': {'world_template': '/sealed/template'}}, {'options': {}},
                       {'options': dict(self.selection['options'], ffmpeg='relative')}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                hall.validate(dict(self.selection, **change))

    def test_native_control_requires_old_keys_collision_and_same_functional_evidence(self):
        selection = dict(self.selection, cases=['native-control'])
        text = self.evidence(native_control=True)
        self.assertEqual([], hall.verify(self.root, selection, {})['issues'])
        self.assertTrue(hall.complete(selection, 'client1', text))
        self.assertTrue(hall.verify(self.root, self.selection, {})['issues'])
        for line in text.splitlines(keepends=True):
            (self.root / 'client1-launch.log').write_text(text.replace(line, ''))
            self.assertTrue(hall.verify(self.root, selection, {})['issues'], line)
        for old, new in (('"baseKey": "c00d3"', '"baseKey": "505a0000000c00d3"'),
                         ('"nativeControl": true', '"nativeControl": false'),
                         ('"stable": true', '"stable": false'), ('"ownerIndex": 16', '"ownerIndex": 17'),
                         ('"canSee": true', '"canSee": false'), ('charge=0.99', 'charge=0'),
                         ('active=true', 'active=false'), ('held=true', 'held=false')):
            (self.root / 'client1-launch.log').write_text(text.replace(old, new))
            self.assertTrue(hall.verify(self.root, selection, {})['issues'])
        (self.root / 'client1-launch.log').write_text(text + '[PZToolkitJavaPatches] Basement hall key separated: unexpected\n')
        self.assertTrue(hall.verify(self.root, selection, {})['issues'])
        patch_root = self.root / 'old-patch'
        (patch_root / '42').mkdir(parents=True)
        for version in ('0.1.18', '0.1.17'):
            (patch_root / '42/mod.info').write_text('id=PZToolkitJavaPatches\nversion=' + version + '\n')
            with patch.object(hall.subprocess, 'run', side_effect=RuntimeError('javac reached')):
                with self.assertRaisesRegex(ValueError if version == '0.1.18' else RuntimeError,
                                            '0.1.17' if version == '0.1.18' else 'javac reached'):
                    hall.stage(ROOT, self.root, Path('/game'), Path('/jdk'), selection,
                               {'PZToolkitJavaPatches': patch_root}, {'roles': {'client1': {'cache': '/cache'}}})

    def test_verifier_requires_native_lookup_traversal_save_and_all_screens(self):
        text = self.evidence()
        self.assertEqual([], hall.verify(self.root, self.selection, {})['issues'])
        self.assertTrue(hall.complete(self.selection, 'client1', text))
        self.assertFalse(hall.complete(self.selection, 'client1', text + hall.MARKER + 'COMPLETE case=fresh\n'))
        self.assertFalse(hall.complete(self.selection, 'server', text))
        for line in text.splitlines(keepends=True):
            (self.root / 'client1-launch.log').write_text(text.replace(line, ''))
            self.assertTrue(hall.verify(self.root, self.selection, {})['issues'], line)
        for old, new in (('505a0000000c00d3', 'c00d3'), ('"stable": true', '"stable": false'),
                         ('"ownerIndex": 16', '"ownerIndex": 17'), ('"baseIndex": 107', '"baseIndex": 108'),
                         ('basementHall=true', 'basementHall=false'), ('"canSee": true', '"canSee": false'),
                         ('charge=1 ', 'charge=1.01 '), ('distance=15', 'distance=1'), ('cone=false', 'cone=true')):
            (self.root / 'client1-launch.log').write_text(text.replace(old, new))
            self.assertTrue(hall.verify(self.root, self.selection, {})['issues'])
        (self.root / 'client1-launch.log').write_text(text + 'ERROR: General > duplicate RoomDef.metaID for room at 10707,9484,0\n')
        self.assertTrue(hall.verify(self.root, self.selection, {})['issues'])
        (self.root / 'client1-launch.log').write_text(text)
        shot = self.root / 'client1/basement-hall-basement.png'
        shot.unlink()
        self.assertTrue(hall.verify(self.root, self.selection, {})['issues'])
        self.evidence()
        (self.root / 'client1/Saves/Sandbox/QueueBasementHall/map_meta.bin').unlink()
        self.assertTrue(hall.verify(self.root, self.selection, {})['issues'])

    def test_stage_uses_test_mod_owned_cache_and_common_bootstrap(self):
        cache = self.root / 'client1'
        lua = cache / 'mods/ActionQueueTest/42/media/lua'
        (lua / 'client').mkdir(parents=True)
        (lua / 'shared').mkdir()
        runtime = {'roles': {'client1': {'cache': str(cache)}}, 'fixture': {'mods': []}}
        def compiled(command, **kwargs):
            target = Path(command[command.index('-d') + 1]) / 'net/alexredby/basementhallfixture/Main.class'
            target.parent.mkdir(parents=True)
            target.write_bytes(b'class')
        with patch.object(hall.subprocess, 'run', side_effect=compiled):
            hall.stage(ROOT, self.root, Path('/game'), Path('/jdk'), self.selection, {}, runtime)
        self.assertEqual(runtime['fixture']['mods'], ['BasementHallFixture'])
        self.assertEqual(str(cache), runtime['roles']['client1']['env']['PZ_BASEMENT_HALL_CACHE'])
        self.assertTrue((lua / 'client/ZZBasementHall.lua').is_file())
        self.assertIn('"disposable"', (lua / 'shared/QueueTestSelection.lua').read_text())
        self.assertIn(str(cache / 'videos'), (lua / 'shared/QueueTestSelection.lua').read_text())
        self.assertIn('RoomID', (ROOT / 'tests/native_queue/contributions/basement-hall/Main.java').read_text())

    def test_presented_video_requires_owned_clip_decode_and_three_phase_frames(self):
        self.video.stop()
        video = self.root / 'client1/videos/capture.mp4'
        video.parent.mkdir(parents=True)
        video.write_bytes(b'video')
        text = ''.join(hall.MARKER + f'VIDEO_PHASE phase={name} elapsedMs={ms}\n'
                       for name, ms in [('surface', 1500), ('basement', 5000), ('returned', 8500)])
        text += hall.MARKER + 'VIDEO_STOP elapsedMs=10000\n'
        text += (hall.MARKER + f'VIDEO_RESULT state=completed file={video} frames=300 seconds=10 captured=300 '
                 'dropped=0 width=16 height=16 error=\n')
        metadata = {'streams': [dict(codec_type='video', codec_name='h264', width=16, height=16,
                    r_frame_rate='30/1', avg_frame_rate='30/1', nb_read_frames='300', duration='10.0')]}
        def run(command, **kwargs):
            if Path(command[0]).resolve() == Path(self.selection['options']['ffprobe']).resolve():
                return subprocess.CompletedProcess(command, 0, stdout=json.dumps(metadata))
            if command[-1].endswith('.png'):
                Path(command[-1]).write_bytes(b'\x89PNG\r\n\x1a\nframe')
            return subprocess.CompletedProcess(command, 0)
        with patch.object(hall.subprocess, 'run', side_effect=run) as executed:
            value = hall._video(self.root, self.selection, text)
            self.assertEqual(3, len(value['presented_frames']))
            self.assertEqual(5, executed.call_count)
            self.assertTrue(any('-xerror' in call.args[0] for call in executed.call_args_list))
            for broken in ('', text.replace('phase=surface', 'phase=basement'),
                           text.replace('state=completed', 'state=failed'),
                           text.replace('elapsedMs=8500', 'elapsedMs=11000')):
                with self.subTest(broken=broken), self.assertRaises(ValueError):
                    hall._video(self.root, self.selection, broken)
            metadata['streams'].append({'codec_type': 'audio'})
            with self.assertRaises(ValueError):
                hall._video(self.root, self.selection, text)
            outside = self.root / 'foreign.mp4'
            outside.write_bytes(b'video')
            with self.assertRaises(ValueError):
                hall._video(self.root, self.selection, text.replace(str(video), str(outside)))

    def test_earlier_functional_only_artifacts_cannot_pass_new_visual_capture_gate(self):
        self.video.stop()
        self.evidence()
        value = hall.verify(self.root, self.selection, {})
        self.assertEqual('failed', value['outcomes'][0]['status'])
        self.assertTrue(any('Missing completed presented video' in issue for issue in value['issues']))


if __name__ == '__main__':
    unittest.main()
