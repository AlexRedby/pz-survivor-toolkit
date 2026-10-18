"""Cart adapter staging and evidence boundaries, without native launch/attachment."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import struct
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
        self.assertIn(f'posX={int(carts.AREA["x"])},posY={int(carts.AREA["y"])},posZ=0', startup)
        self.assertIn("getFileReader('queue-probes-ready.txt',false)", startup)
        self.assertIn("assert(ready=='ready'", startup)
        self.assertFalse((self.output / 'client1/Lua/queue-probes-ready.txt').exists())
        self.assertIn('toggleToSprint=false', (self.output / 'client1/options.ini').read_text())
        self.assertEqual(self.runtime['roles']['client1']['env']['PZ_CART_TEST_PAD'], 'true')

    def test_manual_sp_stage_only_bootstraps_without_autonomous_scenarios_or_probes(self):
        self.selection['cases'] = ['manual']
        compiler = self.stage()
        self.assertEqual(compiler.call_count, 1)
        self.assertEqual(carts.scene_names('manual'), [])
        self.assertEqual(carts.selected_scenes(self.selection), [])
        self.assertEqual(self.runtime['fixture']['attach'], {})
        self.assertTrue(self.runtime['fixture']['manual'])
        runtime = Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
        self.assertIn((ROOT / 'tests/native_queue/contributions/wooden_cart_motion/bootstrap.lua').read_text(), runtime)
        for autonomous_source in [row[0] for bank,row in carts.SP_CASES.items() if bank!='manual']:
            self.assertNotIn((ROOT / 'tests/native_queue/contributions/wooden_cart_motion' / autonomous_source).read_text(), runtime)
        self.assertNotIn('["authoredClip"]=', runtime)
        self.assertFalse(carts.complete(self.selection, 'client1', '[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=0\n'))
        self.assertFalse(carts.complete(self.selection, 'client1', '[WOOD_PROTOTYPE] BOOTSTRAP_READY\n'))

    def test_manual_sp_rejects_automatic_scene_selection(self):
        self.selection['cases'] = ['manual']
        self.options['cart_scenes'] = ['male-full-corner']
        with self.assertRaisesRegex(ValueError, 'cart_scenes'):
            carts.validate(self.selection)

    def test_manual_review_never_claims_automated_animation_verification(self):
        self.selection['cases']=['manual']
        for ready in (False,True):
            (self.output/'client1-launch.log').write_text('[WOOD_PROTOTYPE] BOOTSTRAP_READY' if ready else '')
            result=carts.verify(self.output,self.selection,{})
            row=result['outcomes'][0]
            self.assertEqual(row['status'],'captured' if ready else 'failed')
            self.assertTrue(row['outcome']['manualReview'])
            self.assertFalse(row['outcome']['animationEquivalencePass'])
            self.assertFalse(row['outcome']['evidenceComplete'])

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
        for role in ('client1', 'client2', 'server'):
            self.assertEqual(self.runtime['roles'][role]['env']['PZ_CART_TEST_PAD'], 'false')

    def test_stop_and_reversal_stage_their_own_scenarios(self):
        self.assertEqual([case['id'] for case in carts.definitions()[carts.SP]['cases']],
                         ['sprint', 'reverse', 'reversal', 'stop', 'stop-timing', 'stationary', 'maneuvers', 'collision', 'footprint', 'impact', 'wheel', 'interaction', 'interruption', 'interruption-matrix', 'repeat', 'manual', 'path'])
        for case, count in [('stop', 24), ('stop-timing', 4), ('reversal', 20), ('stationary', 20), ('maneuvers', 32), ('collision', 20), ('footprint', 20), ('impact', 8), ('wheel', 1), ('interaction', 4), ('interruption', 12), ('interruption-matrix', 48), ('repeat', 12), ('path', 24)]:
            with self.subTest(case=case):
                self.output = self.root / case
                self.output.mkdir()
                self.role('client1')
                self.selection['cases'] = [case]
                self.stage()
                text = Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
                source='stop' if case=='stop-timing' else 'collision' if case in ('collision','footprint','impact') else 'interaction' if case in ('interruption','interruption-matrix','wheel','repeat') else case
                self.assertIn((ROOT / f'tests/native_queue/contributions/wooden_cart_motion/scenario-{source}.lua').read_text(), text)
                if case in ('collision','footprint'): self.assertIn('["footprint"]=true',text)
                if case == 'impact': self.assertIn('["impact"]=true',text)
                if case == 'wheel': self.assertIn('["wheelCycle"]=true',text)
                if case in ('interruption', 'interruption-matrix'): self.assertIn('["interruptions"]=true',text)
                if case == 'interruption-matrix': self.assertIn('["interruptionMatrix"]=true',text)
                if case == 'repeat': self.assertIn('["rapidRepeats"]=true',text)
                if case == 'stop-timing': self.assertIn('["stopTiming"]=true',text)
                self.assertIn('["size"]=96',text)
                self.assertEqual(len(self.runtime['fixture']['attach']['client1']), 3)
                self.assertTrue(carts.complete(self.selection, 'client1', f'[WOOD_BANK] ALL_COMPLETE cases={count}\n'))
                for wrong in (count + 1, count * 10):
                    self.assertFalse(carts.complete(self.selection, 'client1', f'[WOOD_BANK] ALL_COMPLETE cases={wrong}\n'))
                self.assertFalse(carts.complete(self.selection, 'client1',
                    f'[WOOD_BANK] ALL_COMPLETE cases={count}\n[WOOD_BANK] RUN_STARTED\n'))

    def test_wheel_cycle_detects_phase_reset_from_actual_draws(self):
        analyzer = carts._load(ROOT / 'tests/native_queue/contributions/wooden_cart_motion/analyze-wheel-cycle.py')
        analyzer.self_check()

    def test_interaction_requires_actions_identity_cargo_rendered_ik_and_scoped_coverage(self):
        self.selection['cases'] = ['interaction']
        analyzer = carts._load(ROOT / 'tests/native_queue/contributions/wooden_cart_motion/analyze-interaction.py')
        analyzer.self_check()
        text, body, grip = analyzer.fixture()
        tail, life = analyzer.entry_fixture()
        cache = self.output / 'client1'
        log = self.output / 'client1-launch.log'
        log.write_text(text)
        for filename, rows in [('body-clearance.jsonl', body), ('wood-grip-poses.jsonl', grip),
                               ('action-tail-poses.jsonl', tail), ('action-lifecycle.jsonl', life),
                               ('world-cart-poses.jsonl', analyzer.world_fixture())]:
            (cache / filename).write_text('\n'.join(map(json.dumps, rows)))
        native = struct.pack('<8f', .01,.02,-.03,0,0,0,0,0)
        (cache / 'WheelbarrowWood.bin').write_bytes(native)
        (cache / 'wood-wheel-mesh-proof.json').write_text(json.dumps(dict(matchesOriginal=True,
            proofAfterPhaseChanged=False, bytes=len(native), sha256=hashlib.sha256(native).hexdigest())))
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        commands = {}
        original_run = carts._run
        def run(command, directory, name):
            commands[name] = command
            if name == 'interaction':
                return original_run(command, directory, name)
            return {'exit_code': 0}
        with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
            result = carts.verify(self.output, self.selection, {})
            self.assertFalse(result['issues'], result['issues'])
            self.assertTrue(result['evidence']['interaction']['functionalPass'])
            self.assertTrue(result['evidence']['interaction']['worldHandoff']['pass'])
            self.assertTrue(result['evidence']['interaction']['entryMotion']['pass'])
            self.assertTrue(result['evidence']['nativeMotionNotApplicable'])
            self.assertNotIn('native', commands)
            self.assertNotIn('nativePartialDiagnostic', result['evidence'])
            self.assertEqual(set(commands), {'aabb', 'body', 'pants', 'interaction'})
            self.assertEqual(result['outcomes'][0]['status'], 'captured')
            self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
            bad_tail = json.loads(json.dumps(tail))
            bad_tail[2]['bones']['Bip01_R_Hand'][13] += .10
            (cache / 'action-tail-poses.jsonl').write_text('\n'.join(map(json.dumps, bad_tail)))
            result = carts.verify(self.output, self.selection, {})
            self.assertFalse(result['evidence']['interaction']['entryMotion']['pass'])
            self.assertTrue(result['issues'])
            self.assertEqual(result['outcomes'][0]['status'], 'failed')
            (cache / 'action-tail-poses.jsonl').write_text('\n'.join(map(json.dumps, tail)))
            log.write_text(text.replace('"ik": true', '"ik": false'))
            result = carts.verify(self.output, self.selection, {})
            self.assertTrue(result['issues'])
            self.assertEqual(result['outcomes'][0]['status'], 'failed')
            for stage, changes in [('held', {'heldID': -1, 'secondaryID': -1}),
                                   ('dropped', {'active': True, 'rendered': True, 'ik': False})]:
                with self.subTest(stage=stage):
                    lines = []
                    for line in text.splitlines():
                        if '[WOOD_INTERACTION_SAMPLE]' in line:
                            row = json.loads(line.split('] ', 1)[1])
                            if row['stage'] == stage:
                                row.update(changes)
                            line = '[WOOD_INTERACTION_SAMPLE] ' + json.dumps(row)
                        lines.append(line)
                    log.write_text('\n'.join(lines))
                    result = carts.verify(self.output, self.selection, {})
                    self.assertFalse(result['evidence']['interaction']['functionalPass'])
                    self.assertTrue(result['issues'])
                    self.assertEqual(result['outcomes'][0]['status'], 'failed')
            log.write_text(text)
            late_hidden = analyzer.world_fixture()
            late_hidden.append(dict(late_hidden[2], wallTimeMillis=112000, alpha=0))
            (cache / 'world-cart-poses.jsonl').write_text('\n'.join(map(json.dumps, late_hidden)))
            result = carts.verify(self.output, self.selection, {})
            self.assertTrue(result['evidence']['interaction']['functionalPass'])
            self.assertFalse(result['evidence']['interaction']['worldHandoff']['pass'])
            self.assertTrue(result['issues'])
            self.assertEqual(result['outcomes'][0]['status'], 'failed')

    def test_interruption_adapter_requires_native_stop_retry_and_first_render_receipts(self):
        for case, matrix in [('interruption', False), ('interruption-matrix', True)]:
            self.selection['cases'] = [case]
            fixture = carts._load(ROOT / 'tests/test_cart_interruption.py')
            text, lifecycle, body, grip, world, draws, tail = fixture.fixture(matrix=matrix)
            cache = self.output / 'client1'
            (self.output / 'client1-launch.log').write_text(text)
            (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
            for filename, rows in [('action-lifecycle.jsonl', lifecycle), ('body-clearance.jsonl', body),
                                   ('wood-grip-poses.jsonl', grip), ('world-cart-poses.jsonl', world),
                                   ('wheel-roll-draws.jsonl', draws), ('action-tail-poses.jsonl', tail)]:
                (cache / filename).write_text('\n'.join(map(json.dumps, rows)))
            original_run = carts._run
            commands = []
            def run(command, directory, name):
                commands.append(name)
                return original_run(command, directory, name) if name == case else {'exit_code': 0}
            with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
                result = carts.verify(self.output, self.selection, {})
                self.assertFalse(result['issues'], result['issues'])
                self.assertTrue(result['evidence']['interruption']['functionalPass'])
                self.assertEqual(set(commands), {'aabb', 'body', 'pants', case})
                self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
                lifecycle[1]['event'] = 'complete'
                (cache / 'action-lifecycle.jsonl').write_text('\n'.join(map(json.dumps, lifecycle)))
                result = carts.verify(self.output, self.selection, {})
                self.assertTrue(result['issues'])
                self.assertEqual(result['outcomes'][0]['status'], 'failed')

    def test_repeat_adapter_requires_clock_recovery_and_wheel_gates(self):
        self.selection['cases'] = ['repeat']
        (self.output / 'client1-launch.log').write_text('[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] ALL_COMPLETE cases=12\n')
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        required = ('functionalPass', 'clockVerified', 'recoveryVerified', 'wheelCoverageVerified')
        for failure in (None, *required):
            commands = []
            def run(command, directory, name):
                commands.append(name)
                if name == 'repeat':
                    self.assertIn('analyze-repeat.py', command[1])
                    self.assertIn('--profile', command)
                    report = dict.fromkeys(required, True)
                    if failure: report[failure] = False
                    report['failures'] = [failure] if failure else []
                    Path(command[command.index('--output')+1]).write_text(json.dumps(report))
                return {'exit_code': int(bool(failure)) if name == 'repeat' else 0}
            with self.subTest(failure=failure), patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
                result = carts.verify(self.output, self.selection, {})
                self.assertEqual(bool(result['issues']), bool(failure))
                self.assertEqual(result['outcomes'][0]['status'], 'failed' if failure else 'captured')
                self.assertEqual(set(commands), {'aabb', 'body', 'pants', 'repeat'})
                self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])

    def test_missing_candidates_and_native_mode_are_rejected(self):
        self.selection['mode'] = 'native'
        with self.assertRaisesRegex(ValueError, 'toolkit mode'):
            carts.validate(self.selection)
        self.selection['mode'] = 'toolkit'
        self.selection['options']['mod_sources'].pop('PZSurvivorToolkit')
        with self.assertRaisesRegex(ValueError, 'Explicit candidate'):
            carts.validate(self.selection)

    def test_missing_numpy_fails_before_cart_fixture_compilation(self):
        with patch.object(carts.importlib, 'import_module', side_effect=ModuleNotFoundError('numpy')) as dependency, \
             patch.object(carts, '_compile') as compiler:
            with self.assertRaisesRegex(ValueError, 'NumPy in ' + re.escape(sys.executable)):
                self.stage()
        dependency.assert_called_once_with('numpy')
        compiler.assert_not_called()
        self.assertFalse((self.output / 'cart-build').exists())

    def test_mp_analysis_does_not_require_numpy(self):
        self.selection.update(suite=carts.MP, cases=['owner_observer_motion'], kind='mp', languages=['EN', 'RU'])
        with patch.object(carts.importlib, 'import_module', side_effect=ModuleNotFoundError('numpy')) as dependency:
            carts.validate(self.selection)
        dependency.assert_not_called()

    def test_scene_catalog_matches_every_lua_bank_and_selected_order(self):
        lua=shutil.which('luajit') or shutil.which('lua')
        if not lua: self.skipTest('Lua interpreter unavailable')
        intake=ROOT/'tests/native_queue/contributions/wooden_cart_motion'
        for bank,(source,count) in carts.SP_CASES.items():
            full=carts.scene_names(bank)
            self.assertEqual(len(full),count,bank)
            self.assertEqual(len(set(full)),count,bank)
            if bank=='manual': continue
            text=(intake/source).read_text()
            start=text.index('local cases=')
            marker='cases=CartLabSelectScenes(cases)'
            body=text[start:text.index(marker,start)+len(marker)]
            flags=dict(disposable=True,footprint=bank in ('collision','footprint'),
                       wheelCycle=bank=='wheel',interruptions=bank in ('interruption','interruption-matrix'),
                       interruptionMatrix=bank=='interruption-matrix',rapidRepeats=bank=='repeat',stopTiming=bank=='stop-timing',impact=bank=='impact')
            from queue_checks.native import _lua
            for chosen in (None,[full[-1],full[0]] if count>1 else [full[0]]):
                if chosen: flags['scenes']=chosen
                code='CartMotionConfig='+_lua(flags)+';local config=CartMotionConfig;local footprint=config.footprint==true;dofile('+json.dumps(str(intake/'scene-selection.lua'))+');'+body+';for _,c in ipairs(cases) do print(c.name) end'
                result=subprocess.run([lua,'-e',code],check=True,text=True,capture_output=True)
                self.assertEqual(result.stdout.splitlines(),[n for n in full if chosen is None or n in chosen],bank)

    def test_scene_selection_is_strict_and_is_staged_in_snapshot_order(self):
        self.selection['cases']=['path']
        for bad in (None,[],True,'male-full-corner',['unknown'],['male-full-corner']*2,[2],['male-full-yaw0']):
            self.options['cart_scenes']=bad
            with self.subTest(bad=bad),self.assertRaisesRegex(ValueError,'cart_scenes'):
                carts.validate(self.selection)
        self.options['cart_scenes']=['female-full-corner','male-empty-cancel']
        self.stage()
        text=Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
        self.assertIn('["scenes"]={"male-empty-cancel","female-full-corner"}',text)
        self.assertLess(text.index('function CartLabSelectScenes'),text.index('local cases='))
        log='[WOOD_BANK] RUN_STARTED\n'+''.join('[WOOD_BANK] COMPLETE '+n+' wall=100\n' for n in carts.selected_scenes(self.selection))+'[WOOD_BANK] ALL_COMPLETE cases=2'
        self.assertTrue(carts.complete(self.selection,'client1',log))
        self.assertFalse(carts.complete(self.selection,'client1',log.replace('male-empty-cancel','male-full-cancel')))
        self.assertFalse(carts.complete(self.selection,'client1',log.replace('cases=2','cases=24')))
        self.selection.update(suite=carts.MP,cases=['owner_observer_motion'],kind='mp',languages=['EN','RU'])
        with self.assertRaisesRegex(ValueError,'SP cart'): carts.validate(self.selection)

    def test_authored_clip_pilot_is_explicit_sp_boolean(self):
        for bad in ('true', 1, None):
            self.options['cart_authored_clip']=bad
            with self.subTest(bad=bad), self.assertRaisesRegex(ValueError,'SP boolean'):
                carts.validate(self.selection)
        self.selection['cases']=['interaction']
        self.options['cart_authored_clip']=True
        self.stage()
        text=Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
        self.assertIn('["authoredClip"]=true',text)
        self.assertIn("if config.authoredClip~=nil then player:setVariable('ToolkitWoodCartClipPilot',config.authoredClip) end",text)
        self.selection.update(suite=carts.MP,cases=['owner_observer_motion'],kind='mp',languages=['EN','RU'])
        with self.assertRaisesRegex(ValueError,'SP boolean'): carts.validate(self.selection)

    def test_authored_clip_explicit_false_keeps_legacy_comparison(self):
        self.options['cart_authored_clip']=False
        self.stage()
        text=Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
        self.assertIn('["authoredClip"]=false',text)

    def test_missing_authored_clip_option_preserves_production_default(self):
        self.stage()
        text=Path(self.runtime['roles']['client1']['env']['PZ_CART_RUNTIME_FILE']).read_text()
        self.assertNotIn('["authoredClip"]=',text)

    def test_selected_scene_capture_keeps_diagnostics_and_explicit_partial_scope(self):
        self.selection['cases']=['path'];self.options['cart_scenes']=['male-full-corner']
        cache=self.output/'client1';(self.output/'runtime.json').write_text(json.dumps(self.runtime))
        text='[WOOD_BANK] RUN_STARTED\n[WOOD_BANK] COMPLETE male-full-corner wall=1000 file=owned.mp4 frames=361 seconds=12.033\n[WOOD_BANK] ALL_COMPLETE cases=1'
        (self.output/'client1-launch.log').write_text(text)
        body=[dict(wallTimeMillis=1000+i*100,cart=[1.]*16,female=False) for i in range(120)]
        grip=[dict(wallTimeMillis=1000+i*100,result=i!=4) for i in range(120)]
        for file,rows in [('body-clearance.jsonl',body),('wood-grip-poses.jsonl',grip)]:
            (cache/file).write_text(''.join(json.dumps(r)+'\n' for r in rows))
        data=b'calibrated';(cache/'WheelbarrowWood.bin').write_bytes(data)
        (cache/'wood-wheel-mesh-proof.json').write_text(json.dumps(dict(matchesOriginal=True,proofAfterPhaseChanged=True,bytes=len(data),sha256=hashlib.sha256(data).hexdigest())))
        calls=[]
        def run(command,directory,name):
            calls.append(name)
            if name=='native':
                self.assertIn('--partial',command)
                metrics={'cases':[dict(case='male-full-corner',gripSamples=120,wheelFloorMaxError=.01,body={'samples':120},pants={'samples':120})]}
                (directory/'native-metrics.json').write_text(json.dumps(metrics))
            return dict(exit_code=1 if name=='pants' else 0)
        with patch.object(carts,'_run',side_effect=run),patch.object(carts,'_videos',return_value=[]):
            result=carts.verify(self.output,self.selection,{})
            self.assertFalse(result['issues'],result)
            self.assertEqual(calls,['aabb','body','pants','native'])
            self.assertTrue(result['outcomes'][0]['outcome']['partialCoverage'])
            self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
            self.assertTrue(result['evidence']['diagnosticOnly'])
            self.assertEqual(result['evidence']['sceneProbes'][0]['gripFailures'],1)
            self.assertEqual(result['evidence']['fullSceneCount'],24)
            for failure in ('empty','wrong-body','nonfinite','sparse'):
                rows=json.loads(json.dumps(body))
                if failure=='empty': rows=[]
                if failure=='wrong-body': rows[0]['female']=True
                if failure=='nonfinite': rows[0]['cart'][0]=float('nan')
                if failure=='sparse': rows=rows[:6]
                (cache/'body-clearance.jsonl').write_text(''.join(json.dumps(r)+'\n' for r in rows))
                with self.subTest(failure=failure):
                    failed=carts.verify(self.output,self.selection,{})
                    self.assertTrue(failed['issues'])
                    self.assertTrue(failed['outcomes'][0]['outcome']['partialCoverage'])

    def test_action_debug_requires_pose_coverage_only_during_rendered_and_held_phases(self):
        self.selection['cases']=['interaction'];self.options['cart_scenes']=['male-empty-yaw0']
        cache=self.output/'client1';name='male-empty-yaw0';start=100000
        records=[dict(case=name,start=start,wall=start+t,elapsed=t,id=1,female=False,
                      rendered=1000<=t<=6000,heldID=1 if 3000<=t<=7000 else -1,
                      ToolkitCartMotion=3500<=t<=7000) for t in range(0,16001,100)]
        body=[dict(wallTimeMillis=start+t,cart=[1.]*16,female=False) for t in range(1000,7001,100)]
        grip=[dict(wallTimeMillis=start+t,result=True) for t in range(6100,7001,100)]
        data=b'calibrated static mesh';(cache/'WheelbarrowWood.bin').write_bytes(data)
        (cache/'wood-wheel-mesh-proof.json').write_text(json.dumps(dict(matchesOriginal=True,proofAfterPhaseChanged=False,bytes=len(data),sha256=hashlib.sha256(data).hexdigest())))
        for failure in (None,'body-gap','grip-gap','telemetry-gap','short-tail','missing-held-phase'):
            rows=[dict(r) for r in records]
            poses=list(body);hands=list(grip)
            if failure=='body-gap': poses=poses[:6]
            if failure=='grip-gap': hands=hands[:6]
            if failure=='telemetry-gap': rows=[r for r in rows if not 6000<r['elapsed']<10000]
            if failure=='short-tail': rows=rows[:80]
            if failure=='missing-held-phase':
                for row in rows: row['ToolkitCartMotion']=False
            for file,values in [('body-clearance.jsonl',poses),('wood-grip-poses.jsonl',hands)]:
                (cache/file).write_text(''.join(json.dumps(r)+'\n' for r in values))
            text='[WOOD_BANK] RUN_STARTED\n'+''.join('[WOOD_INTERACTION_SAMPLE] '+json.dumps(r)+'\n' for r in rows)
            text+='[WOOD_BANK] COMPLETE '+name+' wall=100000 file=owned.mp4 frames=481 seconds=16.033\n[WOOD_BANK] ALL_COMPLETE cases=1'
            with self.subTest(failure=failure):
                if failure:
                    with self.assertRaises(ValueError): carts._debug_coverage(cache,text,self.selection)
                else:
                    self.assertEqual(carts._debug_coverage(cache,text,self.selection)[0]['scene'],name)

    def test_unknown_or_combined_sp_cases_are_rejected(self):
        for cases in (['unknown'], ['stop', 'reversal']):
            self.selection['cases'] = cases
            with self.assertRaisesRegex(ValueError, 'one capture case'):
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

    def coverage_fixture(self, count=20, text=None):
        cache = self.output / 'client1'
        if text is None:
            text = '[WOOD_BANK] RUN_STARTED\n' + ''.join(
                f'[WOOD_BANK] COMPLETE case-{index} wall={100000 + index * 15000}\n' for index in range(count))
        samples, metrics = [], {'cases': []}
        for name, start in re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', text):
            start = int(start)
            samples += [{'wallTimeMillis': start + elapsed} for elapsed in range(900, 11600, 500)]
            metrics['cases'].append(dict(case=name, gripSamples=22, wheelFloorMaxError=.1, body={'samples':22}, pants={'samples':22}))
        for name in ('body-clearance.jsonl', 'wood-grip-poses.jsonl'):
            (cache / name).write_text('\n'.join(map(json.dumps, samples)))
        native = b'actual native test bytes'
        (cache / 'WheelbarrowWood.bin').write_bytes(native)
        (cache / 'wood-wheel-mesh-proof.json').write_text(json.dumps(dict(matchesOriginal=True, proofAfterPhaseChanged=True, bytes=len(native), sha256=hashlib.sha256(native).hexdigest())))
        return text, samples, metrics

    def test_sp_coverage_requires_each_probe_window_and_mesh_presence(self):
        cache = self.output / 'client1'
        text, samples, metrics = self.coverage_fixture()
        carts._coverage(cache, text, 20, metrics)
        metrics['cases'][7]['pants']['samples'] = 0
        with self.assertRaisesRegex(ValueError, 'pose/mesh'):
            carts._coverage(cache, text, 20, metrics)
        metrics['cases'][7]['pants']['samples'] = 22
        (cache / 'wood-grip-poses.jsonl').write_text('\n'.join(map(json.dumps, samples[22:])))
        with self.assertRaisesRegex(ValueError, 'probe window'):
            carts._coverage(cache, text, 20, metrics)

    def test_stop_coverage_rejects_wrong_count_case_and_duplicate_completion(self):
        text, _, metrics = self.coverage_fixture(24)
        cache = self.output / 'client1'
        carts._coverage(cache, text, 24, metrics)
        for invalid in (text.replace('COMPLETE case-0 ', 'COMPLETE case-1 '),
                        '\n'.join(text.splitlines()[:-1])):
            with self.assertRaisesRegex(ValueError, 'Missing/duplicate cart cases'):
                carts._coverage(cache, invalid, 24, metrics)
        metrics['cases'][0]['case'] = 'unexpected'
        with self.assertRaisesRegex(ValueError, 'Native metrics'):
            carts._coverage(cache, text, 24, metrics)

    def test_stop_video_count_and_duplicates_are_checked_before_decode(self):
        self.selection['cases'] = ['stop']
        videos = self.output / 'client1/videos'
        videos.mkdir()
        lines = []
        for index in range(24):
            path = videos / f'{index}.mp4'
            path.write_bytes(b'video')
            lines.append(f'[WOOD_BANK] COMPLETE case-{index} wall=100 file={path} frames=360 seconds=12.0')
        probe = SimpleNamespace(stdout=json.dumps({'streams': [dict(codec_type='video', codec_name='h264', nb_read_frames='360', duration='12.0')]}))
        with patch.object(carts.subprocess, 'run', return_value=probe) as decode:
            text = lines[0] + '\n[WOOD_BANK] RUN_STARTED\n' + '\n'.join(lines)
            self.assertEqual(len(carts._videos(self.output, self.selection, 'client1', text)), 24)
            self.assertEqual(decode.call_count, 48)
            decode.reset_mock()
            for invalid in ('\n'.join(lines[:-1]), '\n'.join(lines[:-1] + [lines[0]])):
                with self.assertRaisesRegex(ValueError, 'Missing/duplicate completed cart clips'):
                    carts._videos(self.output, self.selection, 'client1', invalid)
            decode.assert_not_called()

    def test_stop_uses_selected_original_log_and_retains_failed_motion_diagnostics(self):
        self.selection['cases'] = ['stop']
        fixture = carts._load(ROOT / 'tests/test_cart_stop_analyzer.py')
        text = fixture.evidence().replace('Bob_SprintToStop2h_Heavy', 'Bob_RunToStop2H_Heavy')
        _, _, metrics = self.coverage_fixture(text=text)
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        original_run = carts._run
        for filename in ('client1/console.txt', 'client1-launch.log'):
            with self.subTest(log=filename):
                log = self.output / filename
                log.write_text(text)
                console = self.output / 'client1/console.txt'
                if filename == 'client1-launch.log':
                    console.write_text('[WOOD_BANK] ALL_COMPLETE cases=24\n')
                commands = {}
                def run(command, directory, name):
                    commands[name] = command
                    if name == 'stop':
                        return original_run(command, directory, name)
                    if name == 'native':
                        (directory / 'native-metrics.json').write_text(json.dumps(metrics))
                    return {'exit_code': 0}
                with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]) as videos:
                    result = carts.verify(self.output, self.selection, {})
                self.assertFalse(result['issues'], result['issues'])
                self.assertEqual(result['outcomes'][0]['status'], 'captured')
                self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
                self.assertTrue(result['evidence']['nativePartialDiagnostic'])
                self.assertEqual(result['evidence']['analyzers']['stop']['exit_code'], 1)
                self.assertTrue(result['evidence']['motion']['problems'])
                self.assertIn('--partial', commands['native'])
                self.assertEqual(commands['native'][commands['native'].index('--log') + 1], str(log))
                self.assertEqual(commands['stop'][commands['stop'].index('--log') + 1], str(log))
                self.assertEqual(videos.call_args.args[3], text)
                self.assertEqual(log.read_text(), text)
                self.assertFalse((self.output / 'client1/native-launch.log').exists())
                if filename == 'client1-launch.log':
                    self.assertEqual(console.read_text(), '[WOOD_BANK] ALL_COMPLETE cases=24\n')
                log.unlink()

    def test_stationary_uses_original_log_and_preserves_native_motion_report(self):
        import csv
        self.selection['cases'] = ['stationary']
        fixture = carts._load(ROOT / 'tests/test_cart_stationary_analyzer.py')
        text, wheel = fixture.evidence()
        _, _, metrics = self.coverage_fixture(text=text)
        cache = self.output / 'client1'
        with (cache / 'wood-wheel-native.csv').open('w') as stream:
            writer = csv.DictWriter(stream, fieldnames=wheel[0]); writer.writeheader(); writer.writerows(wheel)
        log = self.output / 'client1-launch.log'
        log.write_text(text)
        (cache / 'console.txt').write_text('Wrong console must not replace original stdout')
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        original_run, commands = carts._run, {}
        def run(command, directory, name):
            commands[name] = command
            if name == 'stationary':
                return original_run(command, directory, name)
            if name == 'native':
                (directory / 'native-metrics.json').write_text(json.dumps(metrics))
            return {'exit_code': 0}
        for bad in (False, True):
            with self.subTest(failed_motion=bad):
                captured = text.replace('run=false', 'run=true') if bad else text
                log.write_text(captured)
                with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
                    result = carts.verify(self.output, self.selection, {})
                self.assertFalse(result['issues'], result['issues'])
                self.assertEqual(result['outcomes'][0]['status'], 'captured')
                self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
                self.assertEqual(result['evidence']['motion']['motionPass'], not bad)
                self.assertEqual(result['evidence']['analyzers']['stationary']['exit_code'], int(bad))
                saved = Path(result['evidence']['analysis']) / 'stationary-motion.json'
                self.assertEqual(json.loads(saved.read_text()), result['evidence']['motion'])
                self.assertEqual(commands['stationary'][commands['stationary'].index('--log') + 1], str(log))
                self.assertIn('--partial', commands['native'])
                self.assertEqual(log.read_text(), captured)
                self.assertFalse((cache / 'native-launch.log').exists())

    def test_maneuvers_keep_failed_motion_separate_from_complete_capture(self):
        self.selection['cases'] = ['maneuvers']
        fixture = carts._load(ROOT / 'tests/test_cart_maneuvers_analyzer.py')
        text = fixture.evidence()
        _, _, metrics = self.coverage_fixture(text=text)
        log = self.output / 'client1-launch.log'
        log.write_text(text)
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        original_run = carts._run
        def run(command, directory, name):
            if name == 'maneuvers':
                self.assertEqual(command[command.index('--log') + 1], str(log))
                return original_run(command, directory, name)
            if name == 'native':
                self.assertIn('--partial', command)
                (directory / 'native-metrics.json').write_text(json.dumps(metrics))
            return {'exit_code': 0}
        for bad in (False, True):
            with self.subTest(bad=bad):
                log.write_text(text.replace('run=false', 'run=true') if bad else text)
                with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
                    result = carts.verify(self.output, self.selection, {})
                self.assertFalse(result['issues'], result['issues'])
                self.assertEqual(result['outcomes'][0]['status'], 'captured')
                self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
                self.assertEqual(result['evidence']['motion']['motionPass'], not bad)
                self.assertEqual(result['evidence']['analyzers']['maneuvers']['exit_code'], int(bad))
                saved = Path(result['evidence']['analysis']) / 'maneuvers-motion.json'
                self.assertEqual(json.loads(saved.read_text()), result['evidence']['motion'])

    def test_collision_and_footprint_keep_mesh_motion_and_capture_gates_separate(self):
        fixture = carts._load(ROOT / 'tests/test_cart_footprint_analyzer.py')
        text, _ = fixture.fixture(self.output / 'client1')
        _, _, metrics = self.coverage_fixture(text=text)
        log = self.output / 'client1-launch.log';log.write_text(text)
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        bad = False
        def run(command, directory, name):
            if name in ('collision', 'footprint'):
                self.assertTrue(command[1].endswith('analyze-footprint.py'))
                self.assertEqual(command[command.index('--log') + 1], str(log))
                self.assertEqual(command[command.index('--profile') + 1], str(self.output / 'client1'))
                report = dict(motionPass=not bad, footprintPass=not bad, controlCount=3)
                (directory / (name + '-motion.json')).write_text(json.dumps(report))
                return {'exit_code': int(bad)}
            if name == 'native':
                self.assertIn('--partial', command)
                (directory / 'native-metrics.json').write_text(json.dumps(metrics))
            return {'exit_code': 0}
        for case in ('collision', 'footprint'):
            self.selection['cases'] = [case]
            for bad in (False, True):
                with self.subTest(case=case, failed_diagnostic=bad), patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
                    result = carts.verify(self.output, self.selection, {})
                self.assertFalse(result['issues'], result['issues'])
                self.assertEqual(result['outcomes'][0]['status'], 'captured')
                self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
                self.assertEqual(result['evidence']['motion']['motionPass'], not bad)
                self.assertEqual(result['evidence']['motion']['footprintPass'], not bad)
                self.assertEqual(result['evidence']['analyzers'][case]['exit_code'], int(bad))
                saved = Path(result['evidence']['analysis']) / (case + '-motion.json')
                self.assertEqual(json.loads(saved.read_text()), result['evidence']['motion'])
        bad = False
        with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]), patch.object(carts, '_coverage', side_effect=ValueError('Incomplete grip window')):
            result = carts.verify(self.output, self.selection, {})
        self.assertEqual(result['outcomes'][0]['status'], 'failed')
        self.assertFalse(result['outcomes'][0]['outcome']['evidenceComplete'])
        self.assertIn('Incomplete grip window', result['issues'])
        self.assertTrue(result['evidence']['motion']['motionPass'])
        self.assertTrue((Path(result['evidence']['analysis']) / 'footprint-motion.json').is_file())

    def test_native_path_requires_route_and_footprint_proof(self):
        self.selection['cases'] = ['path']
        fixture = carts._load(ROOT / 'tests/test_cart_path_analyzer.py')
        text, _ = fixture.fixture()
        _, _, metrics = self.coverage_fixture(24, text)
        log = self.output / 'client1-launch.log'; log.write_text(text)
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        for failed in (None, 'motionPass', 'footprintVerified'):
            def run(command, directory, name):
                if name == 'native':
                    (directory / 'native-metrics.json').write_text(json.dumps(metrics))
                if name == 'path':
                    self.assertTrue(command[1].endswith('analyze-path.py'))
                    self.assertEqual(command[command.index('--log')+1], str(log))
                    report = dict(motionPass=failed!='motionPass', footprintVerified=failed!='footprintVerified', failures=[])
                    (directory / 'path-motion.json').write_text(json.dumps(report))
                return {'exit_code': int(name=='path' and failed is not None)}
            with self.subTest(failed=failed), patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
                result = carts.verify(self.output, self.selection, {})
            self.assertEqual(bool(result['issues']), failed is not None, result)
            self.assertEqual(result['outcomes'][0]['status'], 'failed' if failed else 'captured')
            self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])

    def test_reversal_capture_preserves_motion_report_and_failed_diagnostics(self):
        self.selection['cases'] = ['reversal']
        fixture = carts._load(ROOT / 'tests/test_cart_reversal_analyzer.py')
        text, _, metrics = self.coverage_fixture(text=fixture.evidence())
        log = self.output / 'client1-launch.log'
        log.write_text(text)
        (self.output / 'runtime.json').write_text(json.dumps(self.runtime))
        def run(command, directory, name):
            if name == 'native':
                self.assertIn('--partial', command)
                (directory / 'native-metrics.json').write_text(json.dumps(metrics))
            return {'exit_code': 0}
        with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
            result = carts.verify(self.output, self.selection, {})
        self.assertFalse(result['issues'], result['issues'])
        self.assertEqual(result['outcomes'][0]['status'], 'captured')
        self.assertTrue(result['evidence']['motion']['motionPass'])
        self.assertFalse(result['outcomes'][0]['outcome']['animationEquivalencePass'])
        saved = Path(result['evidence']['analysis']) / 'reversal-motion.json'
        self.assertEqual(json.loads(saved.read_text()), result['evidence']['motion'])
        log.write_text(text.replace('run=false', 'run=true'))
        with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
            result = carts.verify(self.output, self.selection, {})
        self.assertEqual(result['outcomes'][0]['status'], 'captured')
        self.assertFalse(result['evidence']['motion']['motionPass'])
        self.assertTrue(result['evidence']['motion']['failures'])
        log.write_text(text.replace('case=male-empty-walk-switch ', 'case=unexpected ').replace('COMPLETE male-empty-walk-switch ', 'COMPLETE unexpected '))
        metrics['cases'][0]['case'] = 'unexpected'
        with patch.object(carts, '_run', side_effect=run), patch.object(carts, '_videos', return_value=[]):
            result = carts.verify(self.output, self.selection, {})
        self.assertEqual(result['outcomes'][0]['status'], 'failed')
        self.assertIn('Missing, duplicate or unexpected reversal cases', result['issues'])

    def test_cart_completion_alone_never_produces_capture_evidence(self):
        (self.output / 'client1/console.txt').write_text('[WOOD_BANK] ALL_COMPLETE cases=20\n')
        result = carts.verify(self.output, self.selection, {})
        self.assertTrue(result['issues'])
        self.assertEqual(result['outcomes'][0]['status'], 'failed')
        self.assertIs(result['outcomes'][0]['outcome']['animationEquivalencePass'], False)


if __name__ == '__main__':
    unittest.main()
