"""Active wring interruption must preserve exact paid native effects."""
import copy
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zlib
import zipfile

from tests.test_queue_wring_return_controls import a, capture, control_sample
from tests.test_queue_wring_unavailable import verify_capture
from queue_checks.adapters import wring_clothing_verifier as verifier


def active_sample(kind='sp', mode='toolkit', control='cancel'):
    result = control_sample(kind, mode, control)
    row, selection, ids, final = result; enabled = mode == 'toolkit'; stopping = control in ('cancel', 'cancel-toggle')
    value = row['returnControl']; body = next(command for command in row['commands'] if command['actionRef'] == value['bodyRef'])
    tail = row['commands'][-1]; native = value['bodyNative']; generated = value['generatedRef']
    events = [dict(phase=phase, boundary=boundary, succeeded=boundary == 'finish', nativeRef=native)
              for phase in (() if stopping else ('perform', 'complete') if kind == 'sp' else ('perform',))
              for boundary in ('begin', 'finish')]
    stops = [dict(phase='stop', boundary=boundary, succeeded=boundary == 'returned', nativeRef=native,
                  source='disposable-jvm-stop', probeClass='net.alexredby.wringstopprobe.Main',
                  nativeClass='zombie.characters.CharacterTimedActions.LuaTimedActionNew',
                  callbackObserved=boundary == 'returned', callbackSucceeded=boundary == 'returned', callbackUnchanged=True)
             for boundary in ('entry', 'returned')] if stopping else []
    body['lifecycleEvents'] = events
    value.update(accepted=True, policyMode='active' if enabled and stopping else False,
                 stopped=stopping, stopEvents=stops,
                 originalReturn=dict(actionRef=generated, allocated=False, events=[]) if enabled else False,
                 requiredRef='required-return' if enabled and stopping else False,
                 tailPreserved=enabled or not stopping, tailRef=tail['actionRef'],
                 lifecycleEvents=copy.deepcopy(events), settings=[], blocked=False, kept=False)
    if not stopping:
        value['reenabledDuringBody'] = control == 'toggle'
        if enabled:
            spec = ids['items']['target']
            value['blocked'] = dict(id=7, itemId=spec['id'], itemType=spec['type'], title=spec['type'],
                                    reason='producer', state='revoked')
    labels = [] if control == 'cancel' else ['disable', 're-enable' if enabled else 're-enable-control'] * 2 if control == 'toggle' else ['disable']
    previous = enabled; generation = 7
    for index, label in enumerate(labels):
        requested = enabled and index % 2 == 1; after_generation = generation + int(previous and not requested)
        value['settings'].append(dict(label=label, requested=requested, before=previous, after=requested,
                                     generationBefore=generation, generationAfter=after_generation,
                                     bodySame=True, nativeSame=True, tailRetained=True,
                                     requestRetained=enabled and stopping))
        previous, generation = requested, after_generation
    for snapshot in (value['before'], value['after']):
        snapshot['items']['target'].update(wetness=99, wetWeight=.12475)
    if stopping:
        for snapshot in (row['client'], row['server'], final):
            snapshot['items']['target'].update(wetness=99, wetWeight=.12475,
                counts=dict(actor=1, root=0, source=1) if enabled else dict(actor=1, root=1, source=0))
            if not enabled:
                snapshot['items']['tail'].update(wetness=99, wetWeight=.12475)
        if enabled:
            from tests import test_queue_wring_clothing as fixtures
            receipt = copy.deepcopy(fixtures.WringClothingRestorationProfileTests().sample('toolkit')[0]['prepared']['returns'][0])
            receipt.update(actionRef='required-return', bodyStopped=True, bodySettled=False, tailStarted=False, tailRef=tail['actionRef'],
                           duration=-1 if kind == 'mp' else 50)
            row['prepared']['returns'] = [receipt]
        else:
            tail.update(started=False, progress=False)
            tail.pop('startedAt', None); tail.pop('rootAtStart', None)
    last = row['restoration']['samples'][-1]
    if enabled and control == 'cancel':
        last.update(state='completed', plannedTransfers=0)
    elif control in ('toggle-off', 'toggle', 'cancel-toggle'):
        last.update(state=False, candidates=0, observedPreparation=False, plannedTransfers=0)
    return result


class WringActiveControlTests(unittest.TestCase):
    def test_required_cancel_return_does_not_become_original_body_planned_step(self):
        result = active_sample()
        sample = result[0]['restoration']['samples'][-1]
        self.assertEqual('completed', sample['state'])
        self.assertEqual(0, sample['plannedTransfers'])
        self.assertEqual([], a.check_case(*result))
        sample['plannedTransfers'] = 1
        self.assertTrue(a.check_case(*result), 'fresh required cleanup cannot rewrite the original operation record')

    def test_editor_toggles_preserve_exact_unpaid_notice_without_keep_or_inferred_return(self):
        for control in ('toggle-off', 'toggle'):
            result = active_sample(control=control)
            self.assertEqual([], a.check_case(*result))
            self.assertEqual('revoked', result[0]['returnControl']['blocked']['state'])
            self.assertEqual(dict(actor=1, root=1, source=0), result[0]['server']['items']['target']['counts'])
            self.assertEqual([], result[0]['prepared']['returns'])
            for field, value in (('id', 0), ('id', True), ('itemId', -1), ('itemType', 'other'),
                                 ('title', 'other'), ('reason', 'admission'), ('state', 'blocked')):
                changed = copy.deepcopy(result); changed[0]['returnControl']['blocked'][field] = value
                self.assertTrue(a.check_case(*changed), (control, field))
            for value in (False, None, [], dict(id=7)):
                changed = copy.deepcopy(result); changed[0]['returnControl']['blocked'] = value
                self.assertTrue(a.check_case(*changed), (control, value))
            changed = copy.deepcopy(result); changed[0]['returnControl']['kept'] = True
            self.assertTrue(a.check_case(*changed), 'Keep cannot erase an unresolved notice')
            native = active_sample(mode='native', control=control)
            native[0]['returnControl']['blocked'] = copy.deepcopy(result[0]['returnControl']['blocked'])
            self.assertTrue(a.check_case(*native), 'queue-off control cannot claim a producer debt')

    def test_native_stop_request_retains_current_body_and_tail_until_native_dispatch(self):
        result = active_sample(mode='native', control='cancel-toggle')
        control = result[0]['returnControl']
        self.assertFalse(control['tailPreserved'], 'settled native stop must still discard the independent tail')
        setting = control['settings'][0]
        for field in ('bodySame', 'nativeSame', 'tailRetained'):
            self.assertTrue(setting[field], field)
            changed = copy.deepcopy(result); changed[0]['returnControl']['settings'][0][field] = False
            self.assertTrue(a.check_case(*changed), field)
        self.assertEqual([], a.check_case(*result))

    def test_exact_native_stops_required_cleanup_and_real_editor_transitions(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for control in ('cancel', 'cancel-toggle', 'toggle-off', 'toggle'):
                    with self.subTest(kind=kind, mode=mode, control=control):
                        result = active_sample(kind, mode, control)
                        self.assertEqual([], a.check_case(*result))
                        self.assertEqual([], verify_capture(*capture(result)))

    def test_stop_requires_paid_native_body_and_exact_single_callback_pair(self):
        for mutation in ('missing', 'duplicate', 'failed', 'foreign', 'unpaired', 'complete', 'subset'):
            result = active_sample(); body = next(command for command in result[0]['commands'] if command['name'] == 'target' and command['type'] == 'ISWringClothing')
            events = result[0]['returnControl']['stopEvents']
            if mutation == 'missing': events.clear()
            elif mutation == 'duplicate': events += copy.deepcopy(events)
            elif mutation == 'failed': events[-1]['succeeded'] = False
            elif mutation == 'foreign': events[-1]['nativeRef'] = 'copied-episode'
            elif mutation == 'unpaired': events.pop()
            elif mutation == 'complete': events[-1]['phase'] = 'complete'
            else: body['lifecycleEvents'] = [dict(phase='stop')]
            self.assertTrue(a.check_case(*result), mutation)
        for field, value in (('source', 'lifecycle'), ('probeClass', 'foreign'), ('nativeClass', 'foreign'),
                             ('callbackObserved', False), ('callbackSucceeded', False), ('callbackUnchanged', False)):
            result = active_sample(); result[0]['returnControl']['stopEvents'][-1][field] = value
            self.assertTrue(a.check_case(*result), field)
        for field, value in (('started', False), ('progress', False), ('duration', 1), ('callbacksUntouched', False)):
            result = active_sample(); body = next(command for command in result[0]['commands'] if command['name'] == 'target' and command['type'] == 'ISWringClothing')
            body[field] = value
            self.assertTrue(a.check_case(*result), field)

    def test_grouped_baseline_and_active_bank_preserves_exact_authority_order_and_tail_truth(self):
        from tests import test_queue_wring_clothing as fixtures
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                baseline = control_sample(kind, mode)
                row, _, ids, final = baseline
                for envelope in (row['ids'], ids):
                    envelope['case'] = 'worn-bag'; envelope.pop('returnControl')
                for snapshot in (row['input'], row['client'], row['server'], final,
                                 row['prepared']['before'], row['prepared']['after']):
                    snapshot['case'] = 'worn-bag'
                if kind == 'mp': row['authorityBaseline']['case'] = 'worn-bag'
                row.pop('returnControl')
                for sample in row['restoration']['samples']: sample['case'] = 'worn-bag'
                if mode == 'toolkit':
                    for snapshot in (row['client'], row['server'], final):
                        snapshot['items']['target']['counts'] = dict(actor=1, root=0, source=1)
                    row['prepared']['returns'] = copy.deepcopy(fixtures.WringClothingRestorationProfileTests().sample(mode)[0]['prepared']['returns'])
                    if kind == 'mp': row['prepared']['returns'][0]['duration'] = -1
                    row['restoration']['samples'][-1].update(state='completed', plannedTransfers=1)
                results = [baseline] + [active_sample(kind, mode, control) for control in ('cancel', 'cancel-toggle', 'toggle-off', 'toggle')]
                captures = [capture(result) for result in results]; cases = [result[2]['case'] for result in results]
                selection = dict(captures[0][0], cases=cases)
                setup = dict(suite='wring-clothing', event='setup', cases=cases, queueEnabled=mode == 'toolkit', nativeDurations=True, adapterInstalled=True)
                ending = dict(suite='wring-clothing', event='complete', cases=cases, performed=len(cases), failed=0, skipped=0)
                client = ['[QUEUE_CHECK] ' + json.dumps(setup)]; authority = []
                for _, lines, server in captures:
                    authority.extend(server)
                    for line in lines:
                        if line.startswith('[QUEUE_CHECK] ') and json.loads(line.split(' ', 1)[1]).get('event') != 'case':
                            continue
                        if not line.startswith(a.PREFIX + 'COMPLETE '): client.append(line)
                client += ['[QUEUE_CHECK] ' + json.dumps(ending), a.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=cases))]
                with tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    (root / 'client1-launch.log').write_text('\n'.join(client))
                    (root / 'server-launch.log').write_text('\n'.join(authority))
                    report = verifier.verify(root, selection, {})
                    self.assertEqual([], report['issues'], (kind, mode))
                    for outcome in report['outcomes']:
                        self.assertTrue(outcome['outcome']['tailSemanticsVerified'])
                        expected = mode == 'toolkit' or outcome['case'] not in ('worn-bag-cancel', 'worn-bag-cancel-toggle')
                        self.assertIs(outcome['outcome']['tailCompleted'], expected)
                    stream = client if kind == 'sp' else authority
                    first = next(index for index, line in enumerate(stream) if line.startswith(a.PREFIX + 'PREPARED '))
                    stream.append(stream.pop(first))
                    (root / ('client1-launch.log' if kind == 'sp' else 'server-launch.log')).write_text('\n'.join(stream))
                    self.assertTrue(verifier.verify(root, selection, {})['issues'])

    def test_paid_pickup_stop_wetness_required_identity_and_independent_tail(self):
        for mode in ('native', 'toolkit'):
            for side in ('client', 'server'):
                for name in ('target', 'tail'):
                    result = active_sample(mode=mode)
                    result[0][side]['items'][name]['wetness'] = 10 if name == 'target' or mode == 'native' else 99
                    if side == 'server': result[3]['items'][name]['wetness'] = result[0][side]['items'][name]['wetness']
                    self.assertTrue(a.check_case(*result), (mode, side, name))
            result = active_sample(mode=mode)
            result[0]['client']['items']['target']['counts'] = dict(actor=0, root=0, source=0)
            self.assertTrue(a.check_case(*result))
        for field, value in (('requiredRef', 'native-return'), ('requiredRef', False), ('stopped', False),
                             ('tailPreserved', False), ('bodyNative', 'foreign'), ('policyMode', 'pending'),
                             ('bodyUnchanged', False), ('blocked', dict(id=7)), ('kept', True)):
            result = active_sample(); result[0]['returnControl'][field] = value
            self.assertTrue(a.check_case(*result), field)
        for field, value in (('allocated', True), ('actionRef', 'foreign'), ('events', [dict(phase='perform')])):
            result = active_sample(); result[0]['returnControl']['originalReturn'][field] = value
            self.assertTrue(a.check_case(*result), field)
        for mutation in ('missing', 'duplicate', 'old-ref', 'not-stopped', 'body-settled', 'tail-started', 'tail-ref', 'callback-replay', 'callback-episode'):
            result = active_sample(); returns = result[0]['prepared']['returns']
            if mutation == 'missing': returns.clear()
            elif mutation == 'duplicate': returns += copy.deepcopy(returns)
            elif mutation == 'old-ref': returns[0]['actionRef'] = result[0]['returnControl']['generatedRef']
            elif mutation == 'not-stopped': returns[0]['bodyStopped'] = False
            elif mutation == 'body-settled': returns[0]['bodySettled'] = True
            elif mutation == 'tail-started': returns[0]['tailStarted'] = True
            elif mutation == 'tail-ref': returns[0]['tailRef'] = 'foreign-tail'
            elif mutation == 'callback-replay': returns[0]['events'] += copy.deepcopy(returns[0]['events'])
            else: returns[0]['events'][-1]['nativeRef'] = 'foreign-return-episode'
            self.assertTrue(a.check_case(*result), mutation)

    def test_disabled_editor_requires_actual_generation_transition_and_no_revival(self):
        for control in ('cancel-toggle', 'toggle-off', 'toggle'):
            for field, value in (('requested', True), ('before', False), ('after', True), ('generationAfter', 7),
                                 ('generationBefore', True), ('tailRetained', False), ('requestRetained', False if control == 'cancel-toggle' else True)):
                result = active_sample(control=control); result[0]['returnControl']['settings'][0][field] = value
                self.assertTrue(a.check_case(*result), (control, field))
            result = active_sample(control=control); result[0]['restoration']['samples'][-1]['state'] = 'completed'
            self.assertTrue(a.check_case(*result))
        for field, value in (('bodySame', False), ('nativeSame', False), ('generationBefore', 7), ('after', False)):
            result = active_sample(control='toggle'); result[0]['returnControl']['settings'][1][field] = value
            self.assertTrue(a.check_case(*result), field)
        result = active_sample(control='toggle'); result[0]['returnControl']['requiredRef'] = 'fabricated-cleanup'
        self.assertTrue(a.check_case(*result))
        result = active_sample(mode='native', control='toggle'); result[0]['returnControl']['settings'][1]['requested'] = True
        self.assertTrue(a.check_case(*result))
        result = active_sample(control='toggle'); result[0]['returnControl']['settings'][2]['generationAfter'] -= 1
        self.assertTrue(a.check_case(*result), 'second real disable must invalidate the new editor generation')
        result = active_sample(control='toggle'); result[0]['returnControl']['settings'] = result[0]['returnControl']['settings'][:2]
        self.assertTrue(a.check_case(*result), 'single cycle cannot certify repeated off/on continuation')
        for field, value in (('reenabledDuringBody', False), ('tailRef', 'foreign-tail'), ('lifecycleEvents', [])):
            result = active_sample(control='toggle'); result[0]['returnControl'][field] = value
            self.assertTrue(a.check_case(*result), field)
        for field, value in (('reenabledDuringBody', True), ('stopped', True), ('requiredRef', 'fabricated-cleanup')):
            result = active_sample(control='toggle-off'); result[0]['returnControl'][field] = value
            self.assertTrue(a.check_case(*result), field)
        result = active_sample(control='toggle-off'); result[0]['returnControl']['settings'].append(copy.deepcopy(result[0]['returnControl']['settings'][0]))
        self.assertTrue(a.check_case(*result), 'off-only must not silently re-enable')

    def test_rejections_aggregate_without_normalizing_sealed_evidence(self):
        result = active_sample(); row = result[0]
        row['commands'][-1]['progress'] = False
        row['client']['items']['target']['wetness'] = 10
        row['returnControl']['originalReturn']['allocated'] = True
        before = copy.deepcopy(result)
        domains = [issue.split('[', 1)[1].split(']', 1)[0] for issue in a.check_case(*result)]
        self.assertIn('native execution', domains); self.assertIn('physical state', domains); self.assertIn('return control', domains)
        self.assertEqual(before, result)


class WringNativeStopTests(unittest.TestCase):
    def test_installed_kahlua_inherited_stop_and_callback_advice_api(self):
        game, jdk = os.environ.get('PZ_GAME'), os.environ.get('PZ_JDK')
        if not game or not jdk:
            self.skipTest('PZ_GAME and PZ_JDK required for installed probe API regression')
        from tools.queue_checks import preparation_process
        source = Path(__file__).parent / 'native_queue/wring-clothing/java/ProbeInputsCheck.java'
        result = preparation_process.run([str(Path(jdk) / 'bin/java'), '-cp', str(Path(game) / 'projectzomboid.jar'), str(source)],
                                         check=True, capture_output=True, text=True, timeout=60)
        self.assertIn('WRING_STOP_PROBE_INPUTS_PASS', result.stdout)

    def test_native_stop_preserves_wetness_and_clears_unstarted_tail(self):
        game = os.environ.get('PZ_GAME')
        if not game:
            self.skipTest('PZ_GAME required for installed native stop regression')
        native = Path(game) / 'media/lua/shared/TimedActions/ISWringClothing.lua'
        self.assertEqual(a.NATIVE_CRC['media/lua/shared/TimedActions/ISWringClothing.lua'],
                         zlib.crc32(native.read_bytes()))
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().nativeWringSource = str(native)
        lua.globals().nativeBaseSource = str(Path(game) / 'media/lua/shared/TimedActions/ISBaseTimedAction.lua')
        lua.globals().nativeQueueSource = str(Path(game) / 'media/lua/client/TimedActions/ISTimedActionQueue.lua')
        lua.execute(r'''
require=function()end
ISBaseObject={derive=function(self,name)
 local cls={Type=name};cls.__index=cls;return setmetatable(cls,{__index=self})
end}
function table.wipe(value)for key in pairs(value)do value[key]=nil end end
for _,name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState',
 'ClimbSheetRopeState','ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'})do
 _G[name]={instance=function()return {}end}
end
Events={OnTick={Add=function()end}}
dofile(nativeBaseSource)
dofile(nativeQueueSource)
dofile(nativeWringSource)
local item={wet=99,job=.4,getWetness=function(self)return self.wet end,
 setWetness=function(self,value)self.wet=value end,setJobDelta=function(self,value)self.job=value end}
local player={setIsFarming=function()end}
local tail={cancelled=false,isStarted=function()return false end,
 forceCancel=function(self)self.cancelled=true end}
local action=setmetatable({item=item,character=player,isStarted=function()return true end},ISWringClothing)
local queue=setmetatable({queue={action,tail},current=action,character=player},ISTimedActionQueue)
ISTimedActionQueue.queues[player]=queue
action:stop()
assert(item.wet==99 and item.job==0,'native stop applied completion wetness')
assert(#queue.queue==0 and queue.current==nil and tail.cancelled,'native stop retained unstarted tail')
function instanceof(value,kind)return value==item and kind=='Clothing'end
function item:getBodyLocation()return {}end
function syncItemFields()end
assert(action:complete()and item.wet==10,'native complete no longer owns wetness reduction')
''')


class WringStopProbeStagingTests(unittest.TestCase):
    def test_probe_java_is_sealed_runtime_input_and_compiler_output_is_packaged(self):
        project = Path(__file__).resolve().parents[1]
        source = project / 'tests/native_queue/wring-clothing/java/Main.java'
        self.assertIn(source, a.sources(project, {}))
        def compile_probe(command, **options):
            destination = Path(command[command.index('-d') + 1]) / 'net/alexredby/wringstopprobe/Main.class'
            destination.parent.mkdir(parents=True); destination.write_bytes(b'fixture-compiled-output')
            self.assertEqual(source, Path(command[-1]))
            self.assertTrue(options['check'])
        with tempfile.TemporaryDirectory() as temporary, patch.object(a.preparation_process, 'run', side_effect=compile_probe) as compiler:
            jar = a._stop_probe(project, Path(temporary), Path('game'), Path('jdk'))
            with zipfile.ZipFile(jar) as archive:
                self.assertEqual(['net/alexredby/wringstopprobe/Main.class'], archive.namelist())
            compiler.assert_called_once()

    def test_probe_is_installed_only_for_selected_stop_cases_in_disposable_roles(self):
        project = Path(__file__).resolve().parents[1]
        for case in ('worn-bag', 'worn-bag-cancel', 'worn-bag-cancel-toggle', 'worn-bag-toggle'):
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); jar = root / 'probe.jar'; jar.write_bytes(b'probe')
                runtime = dict(roles={name: dict(cache=str(root / name)) for name in ('client1', 'server')})
                for role in runtime['roles'].values():
                    for side in ('client', 'server', 'shared'):
                        (Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua' / side).mkdir(parents=True)
                selection = dict(cases=[case], options={})
                with patch.object(a, 'validate'), patch.object(a, 'audit_native', return_value={}), \
                     patch.object(a, 'audit_selected', return_value={}), patch.object(a, '_stop_probe', return_value=jar) as compile_probe:
                    a.stage(project, root / 'output', Path('game'), Path('jdk'), selection, {}, runtime)
                enabled = case in ('worn-bag-cancel', 'worn-bag-cancel-toggle')
                self.assertEqual(enabled, compile_probe.called)
                self.assertEqual(['WringStopProbe'] if enabled else [], runtime['fixture'].get('mods', []))
                for role in runtime['roles'].values():
                    layer = Path(role['cache']) / 'mods/WringStopProbe/42'
                    self.assertEqual(enabled, layer.exists())
                    if enabled:
                        self.assertIn('javaPkgName=net.alexredby.wringstopprobe', (layer / 'mod.info').read_text())
                        self.assertEqual(b'probe', (layer / 'media/java/WringStopProbe.jar').read_bytes())


if __name__ == '__main__':
    unittest.main()
