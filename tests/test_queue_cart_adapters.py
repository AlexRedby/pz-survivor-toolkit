"""Cart adapter staging and evidence boundaries, without native launch/attachment."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import carts


class CartAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.output = self.root / 'run'
        self.output.mkdir()
        self.runtime = {'game': str(self.root / 'game'), 'server_name': 'queue-smoke', 'roles': {}}
        self.options = {}
        for key in ('ffmpeg', 'ffprobe', 'patch_jar', 'mesh_fbx'):
            path = self.root / key
            path.write_bytes(b'explicit dependency')
            path.chmod(0o755)
            self.options[key] = str(path)
        self.locations = {}
        for mod in carts.MODS:
            path = self.root / 'mods' / mod
            path.mkdir(parents=True)
            self.locations[mod] = path
        (self.locations['PZToolkitJavaPatches'] / 'candidate.jar').write_bytes(b'explicit dependency')
        self.options['mod_sources'] = {mod: str(self.locations[mod]) for mod in ('PZSurvivorToolkit', 'PZToolkitJavaPatches')}
        self.selection = dict(suite=carts.SP, cases=['reverse'], kind='sp', mode='toolkit', languages=['RU'],
                              mods=list(carts.MODS), ports=[17373, 17374], options=self.options)
        self.role('client1')

    def role(self, name):
        cache = self.output / name
        for sub in ('classes', 'Lua', 'mods'):
            (cache / sub).mkdir(parents=True)
        (cache / 'options.ini').write_text('height=720\nvoiceEnable=false\n')
        self.runtime['roles'][name] = dict(cache=str(cache), classes=str(cache / 'classes'))
        return cache

    @staticmethod
    def compiler(command, **kwargs):
        classes = Path(command[command.index('-d') + 1])
        for source in [Path(value) for value in command if value.endswith('.java')]:
            target = classes / ('net/alexredby/cartlab/Main.class' if source.stem == 'Main' else source.stem + '.class')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b'compiled test class')
        return SimpleNamespace(returncode=0, stdout='', stderr='')

    def stage(self):
        with patch.object(carts.subprocess, 'run', side_effect=self.compiler) as compiler:
            carts.stage(ROOT, self.output, self.root / 'game', self.root / 'jdk', self.selection, self.locations, self.runtime)
        return compiler

    def test_sp_stage_builds_three_sealed_agents_and_waits_for_owned_probe_gate(self):
        compiler = self.stage()
        self.assertEqual(compiler.call_count, 2)
        self.assertTrue(all('--release' in call.args[0] and '17' in call.args[0] for call in compiler.call_args_list))
        spec = self.runtime['roles']['client1']
        runtime = Path(spec['env']['PZ_CART_RUNTIME_FILE'])
        text = runtime.read_text()
        self.assertIn((ROOT / 'tests/native_queue/contributions/wooden_cart_motion/test-area.lua').read_text(), text)
        self.assertIn('ALL_COMPLETE cases=', text)
        lua = shutil.which('luajit') or shutil.which('lua')
        if lua:
            subprocess.run([lua, '-e', 'assert(loadfile(' + json.dumps(str(runtime)) + '))'], check=True, capture_output=True)
        attaches = self.runtime['fixture']['attach']['client1']
        self.assertEqual(len(attaches), 3)
        for row in attaches:
            self.assertTrue(Path(row['jar']).is_relative_to(self.output / 'client1/classes'))
            self.assertEqual(row['output'], str(self.output / 'client1'))
            self.assertEqual(row['ready'], '[CART_ADAPTER] PROBE_ATTACH_READY')
            with zipfile.ZipFile(row['jar']) as jar:
                self.assertIn(b'Agent-Class:', jar.read('META-INF/MANIFEST.MF'))
        startup = (self.output / 'client1/mods/ActionQueueTest/42/media/lua/client/QueueCartStartup.lua').read_text()
        self.assertIn("getFileReader('queue-probes-ready.txt',false)", startup)
        self.assertIn("assert(ready=='ready'", startup)
        self.assertFalse((self.output / 'client1/Lua/queue-probes-ready.txt').exists())
        self.assertIn('toggleToSprint=false', (self.output / 'client1/options.ini').read_text())

    def test_mp_stage_composes_original_methods_and_identical_selection(self):
        self.selection.update(suite=carts.MP, cases=['owner_observer_motion'], kind='mp', languages=['EN', 'RU'])
        self.role('client2'); server = self.role('server')
        self.stage()
        source = (self.output / 'cart-build/Main.java').read_text()
        self.assertIn((ROOT / 'tests/native_queue/contributions/wooden_cart_multiplayer/MPMain.methods').read_text(), source)
        self.assertEqual(source.count('    public static void main(String[] args)'), 1)
        relative = 'mods/ActionQueueTest/42/media/lua/shared/QueueTestSelection.lua'
        self.assertEqual((server / relative).read_bytes(), (self.output / 'client1' / relative).read_bytes())
        for role in ('client1', 'client2'):
            self.assertEqual(len(self.runtime['fixture']['attach'][role]), 1)
            self.assertIn('CartLab', self.runtime['fixture']['mods'])
        self.assertNotIn('server', self.runtime['fixture']['attach'])

    def test_missing_candidates_and_native_mode_are_rejected(self):
        self.selection['mode'] = 'native'
        with self.assertRaisesRegex(ValueError, 'toolkit mode'):
            carts.validate(self.selection)
        self.selection['mode'] = 'toolkit'
        self.selection['options']['mod_sources'].pop('PZSurvivorToolkit')
        with self.assertRaisesRegex(ValueError, 'Explicit candidate'):
            carts.validate(self.selection)

    def test_mp_exact_analyzer_preserves_captured_and_rejects_render_window_gap(self):
        intake = ROOT / 'tests/native_queue/contributions/wooden_cart_multiplayer'
        fixture = carts._load(intake / 'self_check.py')
        self.temp.cleanup()
        self.temp = tempfile.TemporaryDirectory(); self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name).resolve()
        fixture.fixture(self.output)
        self.selection.update(suite=carts.MP, cases=['owner_observer_motion'], kind='mp', languages=['EN', 'RU'])
        (self.output / 'selection.json').write_text(json.dumps(dict(self.selection)))
        for role in ('client1', 'client2'):
            path = self.output / (role + '-launch.log')
            path.write_text(path.read_text() + '\n[CART_MP] VIDEO_FINAL {}\n')
        with patch.object(carts, '_videos', return_value=[]):
            result = carts.verify(self.output, self.selection, {})
            self.assertFalse(result['issues'])
            self.assertTrue(all(row['status'] == 'captured' and row['outcome']['animationEquivalencePass'] is False for row in result['outcomes']))
            pose = self.output / 'client2/body-clearance.jsonl'
            rows = [json.loads(line) for line in pose.read_text().splitlines()]
            pose.write_text('\n'.join(json.dumps(row) for row in rows if not 110500 <= row['wallTimeMillis'] <= 111500))
            result = carts.verify(self.output, self.selection, {})
            self.assertTrue(result['issues'])
            self.assertTrue(all(row['status'] == 'failed' for row in result['outcomes']))

    def test_sp_coverage_requires_each_probe_window_and_mesh_presence(self):
        cache = self.output / 'client1'
        text = '[WOOD_BANK] RUN_STARTED\n'
        samples, metrics = [], {'cases': []}
        for index in range(20):
            name, start = 'case-' + str(index), 100000 + index * 15000
            text += f'[WOOD_BANK] COMPLETE {name} wall={start}\n'
            samples += [{'wallTimeMillis': start + elapsed} for elapsed in range(900, 11600, 500)]
            metrics['cases'].append(dict(case=name, gripSamples=22, wheelFloorMaxError=.1, body={'samples':22}, pants={'samples':22}))
        for name in ('body-clearance.jsonl', 'wood-grip-poses.jsonl'):
            (cache / name).write_text('\n'.join(map(json.dumps, samples)))
        native = b'actual native test bytes'
        (cache / 'WheelbarrowWood.bin').write_bytes(native)
        (cache / 'wood-wheel-mesh-proof.json').write_text(json.dumps(dict(matchesOriginal=True, proofAfterPhaseChanged=True, bytes=len(native), sha256=hashlib.sha256(native).hexdigest())))
        carts._coverage(cache, text, 20, metrics)
        metrics['cases'][7]['pants']['samples'] = 0
        with self.assertRaisesRegex(ValueError, 'pose/mesh'):
            carts._coverage(cache, text, 20, metrics)
        metrics['cases'][7]['pants']['samples'] = 22
        (cache / 'wood-grip-poses.jsonl').write_text('\n'.join(map(json.dumps, samples[22:])))
        with self.assertRaisesRegex(ValueError, 'probe window'):
            carts._coverage(cache, text, 20, metrics)

    def test_cart_completion_alone_never_produces_capture_evidence(self):
        (self.output / 'client1/console.txt').write_text('[WOOD_BANK] ALL_COMPLETE cases=20\n')
        result = carts.verify(self.output, self.selection, {})
        self.assertTrue(result['issues'])
        self.assertEqual(result['outcomes'][0]['status'], 'failed')
        self.assertIs(result['outcomes'][0]['outcome']['animationEquivalencePass'], False)


if __name__ == '__main__':
    unittest.main()
