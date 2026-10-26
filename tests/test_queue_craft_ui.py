"""UI craft receipts preserve native callback ownership and exact authoritative effects."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import craft_ui


class CraftUIAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = dict(suite='craft-ui', cases=list(craft_ui.SUCCESS_CASES), kind='sp', mode='toolkit',
                              languages=['EN'], mods=list(craft_ui.MODS), clients=1, options={})

    def joined_selection(self):
        return dict(self.selection, cases=list(craft_ui.JOINED_CASES), kind='mp', clients=2,
                    languages=['EN', 'RU'], actor='client2', options={'mp_host': True})

    def test_joined_cases_declare_an_opt_in_menu_host_topology(self):
        cases = {entry['id']: entry for entry in craft_ui.definitions()['craft-ui']['cases']}
        for case in craft_ui.JOINED_CASES:
            self.assertEqual((2, 'client2', ['mp'], ['EN', 'RU']),
                             tuple(cases[case][key] for key in ('clients', 'actor', 'kinds', 'languages')))
        self.assertNotIn('clients', cases['context'])
        craft_ui.validate(self.joined_selection())
        for change in ({'kind': 'sp'}, {'clients': 1}, {'clients': True}, {'actor': 'client1'},
                       {'actor': None}, {'languages': ['EN']}, {'languages': ['RU', 'EN']},
                       {'options': {}}, {'options': {'mp_host': False}},
                       {'cases': ['context', *craft_ui.JOINED_CASES]}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                craft_ui.validate(dict(self.joined_selection(), **change))

    def test_joined_completion_requires_each_owned_role_and_its_exact_marker(self):
        selection = self.joined_selection()
        for role in ('client1', 'client2'):
            marker = '[CRAFT_UI_TEST] COMPLETE actor=' + role + '\n'
            self.assertTrue(craft_ui.complete(selection, role, marker))
            for wrong in ('[CRAFT_UI_TEST] COMPLETE\n', marker + marker,
                          '[CRAFT_UI_TEST] COMPLETE actor=' + ('client2' if role == 'client1' else 'client1')):
                with self.subTest(role=role, marker=wrong):
                    self.assertFalse(craft_ui.complete(selection, role, wrong))
        self.assertFalse(craft_ui.complete(selection, 'server', '[CRAFT_UI_TEST] COMPLETE actor=server\n'))

    def test_joined_evidence_uses_its_dedicated_verifier_and_sealed_source(self):
        expected = {'issues': [], 'outcomes': [{'actor': 'client2'}]}
        from types import SimpleNamespace
        from unittest.mock import Mock
        verify = Mock(return_value=expected)
        module = SimpleNamespace(verify=verify)
        selection = self.joined_selection()
        with patch.object(craft_ui, 'import_module', return_value=module) as load:
            self.assertIs(expected, craft_ui.verify(self.root, selection, {'suites': {}}))
            load.assert_called_once_with('.craft_ui_sandwich', craft_ui.__package__)
            verify.assert_called_once_with(self.root, selection, {'suites': {}})
        sources = craft_ui.sources(ROOT, selection)
        self.assertIn(Path(craft_ui.__file__).with_name('craft_ui_sandwich.py'), sources)
        self.assertNotIn(Path(craft_ui.__file__).with_name('craft_ui_sandwich.py'), craft_ui.sources(ROOT, self.selection))

    @unittest.skipUnless(shutil.which('luajit'), 'LuaJIT is required for the native server protocol check')
    def test_joined_server_waits_for_independent_host_receipts_before_start_and_completion(self):
        script = r'''
local joined = arg[2] == 'joined'
local cases = {'first', 'second'}
local requests, checkpoints, previousSeen = {}, {}, nil
local callback, tick
Events = {OnClientCommand={Add=function(fn) callback=fn end}, OnTick={Add=function(fn) tick=fn end}}
function isServer() return true end
function getTimestampMs() return 100 end
function sendServerCommand(player,module,command,value)
 requests[#requests+1]={player=player.name,command=command,value=value}
end
local function player(name,id)
 return {name=name,getUsername=function(self)return self.name end,getOnlineID=function()return id end,
  setGhostMode=function()end}
end
local host, actor=player('client1',1),player(joined and 'client2' or 'client1',2)
package.loaded.QueueTestSelection={cases=cases,actor=joined and 'client2' or nil}
package.loaded.QueueHealthEvents={encode=function()return '{}'end}
package.loaded.QueueCraftUIFixture={
 prepare=function(p,case,previous)previousSeen=previous;return {player=p,case=case}end,
 descriptor=function(state)return {case=state.case,source={ownerToken='shared-crate'}}end,
 verify=function(state)return {case=state.case,authoritative=true}end}
package.loaded.QueueCookSandwichFixture={checkpoint=function(state,stage,args)
 checkpoints[#checkpoints+1]={state=state,stage=stage,args=args};return {stage=stage,actual=true}
end}
assert(loadfile(arg[1]))()
local function call(p,command,case,snapshot,stage)
 callback('CraftUITest',command,p,{case=case or 'first',snapshot=snapshot,stage=stage})
end
local function count(command)
 local n=0;for _,request in ipairs(requests)do if request.command==command then n=n+1 end end;return n
end
call(actor,'Prepare')
assert(count('Prepared')==1 and count('Start')==0 and count('Verified')==0)
if joined then
 call(actor,'Verify');assert(count('Failed')==1)
 call(host,'ObserverReady');assert(count('ObservePrepared')==1)
 call(actor,'ObservedBefore',nil,{case='first'});assert(count('Failed')==2 and count('Start')==0)
 call(host,'ObservedBefore',nil,{case='first',items={{id=77,hunger=-.12}}})
 assert(count('Start')==1 and requests[#requests].player=='client2')
 call(actor,'ActorCheckpoint',nil,nil,'BreadAdded')
 assert(#checkpoints==1 and checkpoints[1].stage=='BreadAdded')
 assert(requests[#requests].value.snapshot.actual and requests[#requests].player=='client2')
end
call(actor,'Verify');tick()
if joined then
 assert(count('Verified')==0 and count('Observe')==1 and requests[#requests].player=='client1')
 call(host,'Observed',nil,{case='first',items={{id=77,hunger=-.06}}})
 assert(count('Verified')==1 and count('Done')==1)
 assert(requests[#requests-1].player=='client2' and requests[#requests].player=='client1')
else assert(count('Verified')==1 and count('Observe')==0)end
call(actor,'Prepare','second')
assert(count('Prepared')==2 and previousSeen.case=='first' and previousSeen.player==actor)
print('server role barrier passed')
'''
        for mode in ('joined', 'existing'):
            with self.subTest(mode=mode):
                result = subprocess.run([shutil.which('luajit'), '-', str(ROOT / 'tests/native_queue/craft-ui/server/ZZCraftUIServer.lua'), mode],
                                        input=script, text=True, capture_output=True)
                self.assertEqual(0, result.returncode, result.stdout + result.stderr)
                self.assertIn('server role barrier passed', result.stdout)

    def evidence(self):
        enabled, cases = self.selection['mode'] == 'toolkit', self.selection['cases']
        rows = [dict(event='setup', cases=cases, expected=len(cases), queueEnabled=enabled, nativeDurations=True)]
        raw = []
        for index, case in enumerate(cases):
            count, base = craft_ui.COUNTS[case], 100 + index * 100
            if case == craft_ui.EVOLVED_CASE:
                prep = dict(case=case, bags=[base + 10, base + 11], book=base + 12,
                            base=dict(id=base, kind='Base.Bowl'),
                            ingredient=dict(id=base + 1, kind='Base.Tomato', hunger=-.12),
                            spice=dict(id=base + 2, kind='Base.Pepper', hunger=-.005), baselineDishIds=[800], cookingLevel=0)
                dish = dict(id=5000 + index * 10, kind='Base.Salad', totalCount=1, rootCount=0, sourceCount=1,
                            extras=['Base.Tomato'], spices=['Base.Pepper'])
                receipt = dict(case=case, bags=prep['bags'].copy(), base=dict(id=base, totalCount=0),
                               ingredient=dict(id=base + 1, kind='Base.Tomato', hunger=-.06,
                                               sourceCount=1, rootCount=0, totalCount=1),
                               spice=dict(id=base + 2, kind='Base.Pepper', totalCount=0),
                               dishes=[dish], outputIds=[dish['id']], outputs=1, bookId=prep['book'], tailRead=True)
                raw += [('PREPARED', prep), ('VERIFIED', receipt)]
                row = dict(event='case', id=case, status='passed', reason=None, requested=2, actions=2,
                           actionInputIds=[base + 1, base + 2], progressIds=[1, 2], nativeDurations=[100, 100], cookingLevel=0,
                           sourceMethodsUnchanged=True, callbackClass='PJCK_EvoPanel', sourceDeferred=True,
                           sourceVerified=True, tokensGrouped=enabled, tailIndependent=True, tailProgress=True,
                           returnsBeforeRead=True, selectedDishId=dish['id'])
                row.update({key: copy.deepcopy(value) for key, value in receipt.items() if key != 'case'})
                rows.append(row)
                continue
            prep = dict(case=case, materials=list(range(base, base + count)), bags=[base + 10, base + 11],
                        book=base + 12, baselineOutputIds=[800],
                        toolMeta=[dict(id=base + 20 + n, kind=kind, condition=10, uses=0)
                                  for n, kind in enumerate(('Base.Hammer', 'Base.Saw'))])
            receipt = dict(case=case, materialIds=prep['materials'].copy(), consumed=count, outputs=count,
                           outputIds=list(range(5000 + index * 10, 5000 + index * 10 + count)),
                           resources=[dict(meta, sourceCount=1, rootCount=0) for meta in prep['toolMeta']],
                           toolsReturned=2, bookId=prep['book'], tailRead=True)
            raw += [('PREPARED', prep), ('VERIFIED', receipt)]
            transfers = [meta['id'] for meta in prep['toolMeta']] if case.startswith('context') or case.startswith('vanilla-') else []
            row = dict(event='case', id=case, status='passed', reason=None, requested=count, actions=count,
                       progressIds=list(range(1, count + 1)), callbackClass=craft_ui.OWNERS[case],
                       callbacksUnchanged=True, callbackSafe=True, nativeDuration=150, localDeferrals=0,
                       sharedPerformCount=count if enabled else 0,
                       sharedCompleteCount=count if enabled and self.selection['kind'] == 'sp' else 0,
                       ownerIdle=True, remaining=0, pickupIds=transfers.copy(), returnIds=transfers.copy(),
                       returnsBeforeRead=True)
            if case.endswith('-auto'):
                row.update(manualSelect=False, manualInputTypes=['nil'] * count,
                           automaticToolIds=[[meta['id'] for meta in prep['toolMeta']]] * count)
            if case in craft_ui.FAILURE_CASES:
                prep.update(materialMeta=[dict(id=id, kind='Base.Plank', condition=10, uses=0) for id in prep['materials']],
                            sparePlanks=[dict(id=9000 + index, kind='Base.Plank', condition=10, uses=0)],
                            playerId=3 if self.selection['kind'] == 'mp' else 0)
                receipt.update(consumed=0, outputs=0, outputIds=[],
                               materialStates=[dict(meta, state='surviving') for meta in prep['materialMeta']],
                               sparePlanks=copy.deepcopy(prep['sparePlanks']))
                trace = [dict(protocol=1, player=3, transaction=index + 1, kind='ISHandcraftAction',
                              token=f'12345678-1234-1234-1234-{index + 1:012x}', state=state)
                         for state in ('started', 'canceled')] if self.selection['kind'] == 'mp' else []
                row.update(progressIds=[1], sharedPerformCount=0, sharedCompleteCount=0,
                           interrupted=True, interruptionProgress=.1, outcomeTrace=trace, playerId=prep['playerId'],
                           tailProgress=True, tokenCancelled=enabled)
            if case in craft_ui.POOL_CASES:
                introduced = dict(id=9500 + index, kind='Base.Plank', condition=10, uses=0)
                receipt.update(introducedSpare=introduced, outputs=1, outputIds=[5000 + index * 10], outputPlankCounts=[1],
                               materialStates=[dict(meta, state='removed') for meta in prep['materialMeta']],
                               spentMaterials=[], survivingMaterials=[], removedMaterials=copy.deepcopy(prep['materialMeta']))
                raw.insert(len(raw) - 1, ('REMOVED', dict(case=case, removedMaterials=copy.deepcopy(prep['materialMeta']), introducedSpare=copy.deepcopy(introduced))))
                if trace:
                    trace[1]['state'] = 'completed'
                row.update(sharedPerformCount=int(enabled), sharedCompleteCount=int(enabled and self.selection['kind'] == 'sp'),
                           manualMaterialIds=[prep['materials'].copy()] * 2,
                           manualMaterialIdsAfterRemoval=[prep['materials'].copy()] * 2,
                           poolPhaseProof=dict(secondAllocatedAtRequest=False, secondAllocatedAtRemoval=False,
                                               observedBeforeSecondAllocation=True), secondAllocated=False, secondStarted=False)
            row.update({key: copy.deepcopy(value) for key, value in receipt.items() if key != 'case'})
            rows.append(row)
        rows.append(dict(event='complete', cases=cases, expected=len(cases), performed=len(cases), failed=0, skipped=0))
        return ([dict(row, suite='craft-ui', kind=self.selection['kind'], mode=self.selection['mode'], actor='client1')
                 for row in rows], raw)

    def verify(self, evidence=None, marker='[CRAFT_UI_TEST] COMPLETE', extra='', wrong_authority=False):
        rows, raw = self.evidence() if evidence is None else evidence
        text = '\n'.join('[QUEUE_CHECK] ' + json.dumps(row) for row in rows) + '\n' + marker + '\n' + extra
        text += '\n' + '\n'.join('[CRAFT_UI_TEST] OUTCOME ' + json.dumps(dict(case=row['id'], receipt=entry))
                                 for row in rows if row.get('id') in craft_ui.FAILURE_CASES
                                 for entry in row.get('outcomeTrace', []))
        authority = '\n'.join('[CRAFT_UI_TEST] ' + name + ' ' + json.dumps(value) for name, value in raw)
        if self.selection['kind'] == 'mp':
            (self.root / 'server-launch.log').write_text('' if wrong_authority else authority)
            if wrong_authority:
                text += '\n' + authority
        else:
            text += '\n' + authority
        (self.root / 'client1-launch.log').write_text(text)
        return craft_ui.verify(self.root, self.selection, {})

    def test_evolved_gate_shares_ordered_sessions_in_sp_host_both_modes(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode, cases=['cook-batch', craft_ui.EVOLVED_CASE])
                with self.subTest(kind=kind, mode=mode):
                    craft_ui.validate(self.selection)
                    result = self.verify()
                    self.assertEqual([], result['issues'])
                    self.assertEqual(self.selection['cases'], [row['case'] for row in result['outcomes']])
        with self.assertRaises(ValueError):
            craft_ui.validate(dict(self.selection, cases=[craft_ui.EVOLVED_CASE, 'cook-batch']))

    def test_evolved_effect_source_and_native_phase_falsifications_fail(self):
        self.selection['cases'] = [craft_ui.EVOLVED_CASE]
        changes = [('requested', 1), ('actions', 1), ('actionInputIds', [102, 101]),
                   ('progressIds', [1]), ('nativeDurations', [1, 1]), ('nativeDurations', [True, 100]),
                   ('cookingLevel', True), ('sourceMethodsUnchanged', False), ('sourceDeferred', False),
                   ('sourceVerified', False), ('tokensGrouped', False), ('tailIndependent', False),
                   ('tailProgress', False), ('returnsBeforeRead', False), ('selectedDishId', 999)]
        for key, value in changes:
            evidence = self.evidence()
            evidence[0][1][key] = value
            with self.subTest(key=key):
                self.assertTrue(self.verify(evidence)['issues'])
        for change in ('base-present', 'spice-survivor', 'wrong-leftover', 'changed-input-id', 'changed-spice-id',
                       'dish-at-root', 'duplicate-dish', 'missing-extra', 'duplicate-spice', 'old-dish-id', 'missing-reader'):
            rows, raw = self.evidence()
            row, receipt = rows[1], raw[1][1]
            if change == 'base-present': receipt['base']['totalCount'] = 1
            elif change == 'spice-survivor': receipt['spice']['totalCount'] = 1
            elif change == 'wrong-leftover': receipt['ingredient']['hunger'] = -.01
            elif change == 'changed-input-id': receipt['ingredient']['id'] = 999
            elif change == 'changed-spice-id': receipt['spice']['id'] = 999
            elif change == 'dish-at-root': receipt['dishes'][0].update(sourceCount=0, rootCount=1)
            elif change == 'duplicate-dish': receipt['dishes'][0]['totalCount'] = 2
            elif change == 'missing-extra': receipt['dishes'][0]['extras'] = []
            elif change == 'duplicate-spice': receipt['dishes'][0]['spices'] *= 2
            elif change == 'old-dish-id':
                receipt['dishes'][0]['id'] = 800
                receipt['outputIds'] = [800]
                row['selectedDishId'] = 800
            else: receipt['tailRead'] = False
            row.update({key: copy.deepcopy(value) for key, value in receipt.items() if key != 'case'})
            with self.subTest(change=change):
                self.assertTrue(self.verify((rows, raw))['issues'])

    def test_evolved_receipt_must_be_authoritative_and_preparation_exact(self):
        self.selection.update(kind='mp', cases=[craft_ui.EVOLVED_CASE])
        self.assertTrue(self.verify(wrong_authority=True)['issues'])
        for key, value in [('base', dict(id=100, kind='Base.Salad')),
                           ('ingredient', dict(id=101, kind='Base.Tomato', hunger=-.01)),
                           ('spice', dict(id=102, kind='Base.Pepper', hunger=0)),
                           ('bags', [110, 110]), ('book', True), ('baselineDishIds', [100])]:
            rows, raw = self.evidence()
            raw[0][1][key] = value
            with self.subTest(key=key):
                self.assertTrue(self.verify((rows, raw))['issues'])
        rows, raw = self.evidence()
        raw[1][1]['ingredient']['hunger'] = -.01
        self.assertTrue(self.verify((rows, raw))['issues'])

    def test_evolved_native_deviations_remain_failed_controls(self):
        self.selection.update(mode='native', cases=[craft_ui.EVOLVED_CASE])
        rows, raw = self.evidence()
        raw[1][1]['dishes'][0].update(sourceCount=0, rootCount=1)
        rows[1].update({key: copy.deepcopy(value) for key, value in raw[1][1].items() if key != 'case'})
        rows[1].update(status='failed', reason='native-evolved-effect-differs', returnsBeforeRead=False)
        rows[-1]['failed'] = 1
        result = self.verify((rows, raw))
        self.assertEqual(['native-evolved-effect-differs'], result['issues'])
        self.assertEqual('failed', result['outcomes'][0]['status'])

    def test_sp_host_native_and_toolkit_accept_exact_receipts(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                with self.subTest(kind=kind, mode=mode):
                    craft_ui.validate(self.selection)
                    result = self.verify()
                    self.assertEqual([], result['issues'])
                    self.assertEqual(craft_ui.SUCCESS_CASES, [row['case'] for row in result['outcomes']])
                    self.assertTrue(all(row['status'] == 'passed' for row in result['outcomes']))
                    self.assertEqual([craft_ui.COUNTS[case] for case in craft_ui.SUCCESS_CASES],
                                     [row['outcome']['consumed'] for row in result['outcomes']])
                    self.assertTrue(result['evidence']['limits'])

    def test_automatic_mode_requires_absent_manual_inputs(self):
        for key, value in [('manualSelect', True), ('manualSelect', 0), ('manualInputTypes', ['boolean', 'boolean']),
                           ('manualInputTypes', ['table', 'nil']), ('manualInputTypes', ['nil']),
                           ('automaticToolIds', []), ('automaticToolIds', [[320, 321], [999, 321]])]:
            rows, raw = self.evidence()
            next(row for row in rows if row.get('id') == 'vanilla-auto')[key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(self.verify((rows, raw))['issues'])

    def test_selection_and_registration_are_exact(self):
        self.assertEqual(craft_ui.MODS, craft_ui.definitions()['craft-ui']['default_mods'])
        self.assertEqual(craft_ui.CASES, [row['id'] for row in craft_ui.definitions()['craft-ui']['cases']])
        craft_ui.validate(dict(self.selection, cases=['context', 'cook-batch']))
        for change in ({'cases': []}, {'cases': ['unknown']}, {'cases': ['context', 'context']},
                       {'cases': ['cook-batch', 'context']}, {'kind': 'coop'}, {'mode': 'other'},
                       {'languages': ['RU']}, {'clients': True}, {'clients': 2},
                       {'mods': craft_ui.MODS[:-1]}, {'options': {'world_template': '/old/world'}}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                craft_ui.validate(dict(self.selection, **change))

    def test_sources_and_stage_share_only_native_setup(self):
        project = self.root / 'project'
        paths = ['craft-ui/client/UI.lua', 'craft-ui/shared/Fixture.lua', 'craft-ui/server/Server.lua',
                 'craft/scripts/queue_craft.txt', 'health/shared/QueueHealthEvents.lua',
                 'startup/client/ZZStartup.lua', 'startup/server/ZZStartupServer.lua']
        for name in paths + ['craft-ui/ignored.txt', 'craft/client/Old.lua']:
            path = project / 'tests/native_queue' / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture')
        expected = [Path(craft_ui.craft.__file__), Path(craft_ui.__file__).with_name('craft_ui_water.py'), *(project / 'tests/native_queue' / name for name in paths)]
        self.assertCountEqual(expected,
                              craft_ui.sources(project, self.selection))
        runtime = {'roles': {'client1': {'cache': str(self.root / 'client1')}}}
        with patch.object(craft_ui.craft, 'stage_common', create=True) as common:
            craft_ui.stage(project, self.root, 'game', 'jdk', self.selection, {'mod': 'path'}, runtime)
            common.assert_called_once_with(project, self.root, 'game', 'jdk', self.selection, {'mod': 'path'}, runtime)
            common.reset_mock()
            with self.assertRaises(ValueError):
                craft_ui.stage(project, self.root, 'game', 'jdk', dict(self.selection, clients=2), {}, runtime)
            common.assert_not_called()

    def test_marker_events_and_context_cannot_be_missing_duplicated_or_reordered(self):
        for marker in ('', '[CRAFT_UI_TEST] COMPLETE_PENDING', '[CRAFT_UI_TEST] COMPLETE\n[CRAFT_UI_TEST] COMPLETE'):
            self.assertFalse(craft_ui.complete(self.selection, 'client1', marker))
            self.assertTrue(self.verify(marker=marker)['issues'])
        self.assertTrue(craft_ui.complete(self.selection, 'client1', '[CRAFT_UI_TEST] COMPLETE\n'))
        self.assertFalse(craft_ui.complete(self.selection, 'server', '[CRAFT_UI_TEST] COMPLETE\n'))
        for change in ('missing', 'duplicate', 'order', 'unknown', 'context', 'complete-count', 'error'):
            rows, raw = self.evidence()
            if change == 'missing': rows.pop(1)
            elif change == 'duplicate': rows.insert(2, rows[1])
            elif change == 'order': rows[1], rows[2] = rows[2], rows[1]
            elif change == 'unknown': rows[1]['id'] = 'unknown'
            elif change == 'context': rows[1]['actor'] = 'client2'
            elif change == 'complete-count': rows[-1]['performed'] = True
            else: rows[1]['event'] = 'error'
            with self.subTest(change=change):
                self.assertTrue(self.verify((rows, raw))['issues'])
        with self.assertRaises(ValueError):
            self.verify(extra='[QUEUE_CHECK] []')
        self.assertTrue(self.verify(extra='[QUEUE_TEST] FAIL UI')['issues'])

    def test_native_callback_and_shared_phase_claims_are_strict(self):
        changes = [('requested', 1), ('actions', 1), ('progressIds', [1]), ('progressIds', [2, 1]),
                   ('progressIds', [True, 2]), ('callbackClass', 'custom'), ('callbacksUnchanged', False),
                   ('callbackSafe', False), ('callbackSafe', 1), ('nativeDuration', 1), ('nativeDuration', True),
                   ('localDeferrals', 1), ('sharedPerformCount', 0), ('sharedCompleteCount', 0),
                   ('ownerIdle', 1), ('remaining', True), ('remaining', -1), ('returnsBeforeRead', 1)]
        for key, value in changes:
            evidence = self.evidence()
            evidence[0][2][key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(self.verify(evidence)['issues'])
        for kind, mode, key in [('mp', 'toolkit', 'sharedCompleteCount'), ('sp', 'native', 'sharedPerformCount'),
                                ('mp', 'native', 'sharedCompleteCount')]:
            self.selection.update(kind=kind, mode=mode)
            evidence = self.evidence()
            evidence[0][1][key] = 1
            with self.subTest(kind=kind, mode=mode, key=key):
                self.assertTrue(self.verify(evidence)['issues'])

    def test_authority_must_be_independent_exact_unique_and_ordered(self):
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for change in ('missing', 'duplicate', 'order', 'wrong-marker', 'extra-field', 'missing-field', 'disagree'):
                rows, raw = self.evidence()
                if change == 'missing': raw.pop()
                elif change == 'duplicate': raw.append(copy.deepcopy(raw[-1]))
                elif change == 'order': raw[0], raw[1] = raw[1], raw[0]
                elif change == 'wrong-marker': raw[-1] = ('AUTHORITY', raw[-1][1])
                elif change == 'extra-field': raw[-1][1]['extra'] = 1
                elif change == 'missing-field': del raw[-1][1]['outputs']
                else: raw[-1][1]['tailRead'] = False
                with self.subTest(kind=kind, change=change):
                    self.assertTrue(self.verify((rows, raw))['issues'])
            if kind == 'mp':
                self.assertTrue(self.verify(wrong_authority=True)['issues'])
        (self.root / 'server-launch.log').unlink()
        self.assertTrue(craft_ui.verify(self.root, self.selection, {})['issues'])
        with self.assertRaises(ValueError):
            self.verify(extra='[QUEUE_CHECK] {not-json}')

    def test_prepared_materials_tools_baseline_and_outputs_are_distinct_strict_ids(self):
        changes = [('materials', []), ('materials', [True]), ('materials', [100, 100]), ('materials', [120]),
                   ('bags', [110, 110]), ('bags', [110.0, 111]), ('book', True),
                   ('baselineOutputIds', [100]), ('baselineOutputIds', [800, 800]), ('baselineOutputIds', [True])]
        for key, value in changes:
            evidence = self.evidence()
            evidence[1][0][1][key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(self.verify(evidence)['issues'])
        for value in ([], [800], [100], [120], [True], [5000, 5000]):
            evidence = self.evidence()
            evidence[0][1]['outputIds'] = value
            evidence[1][1][1]['outputIds'] = copy.deepcopy(value)
            with self.subTest(outputIds=value):
                self.assertTrue(self.verify(evidence)['issues'])
        for key, value in [('materialIds', [999]), ('consumed', True), ('outputs', 0), ('bookId', 999)]:
            evidence = self.evidence()
            for row in (evidence[0][1], evidence[1][1][1]):
                row[key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(self.verify(evidence)['issues'])
        evidence = self.evidence()
        evidence[0][2]['outputIds'][0] = evidence[0][1]['outputIds'][0]
        evidence[1][3][1]['outputIds'] = evidence[0][2]['outputIds'].copy()
        self.assertTrue(self.verify(evidence)['issues'])

    def test_tool_identity_conservation_and_observed_transfer_subsets_are_exact(self):
        for key, value in [('id', 999), ('kind', 'Base.Wrench'), ('condition', 0), ('uses', True),
                           ('sourceCount', True), ('sourceCount', 2), ('sourceCount', 0), ('rootCount', 1)]:
            evidence = self.evidence()
            for row in (evidence[0][1], evidence[1][1][1]):
                row['resources'][0][key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(self.verify(evidence)['issues'])
        for value in (None, [], [120], [120, 120], [121, 120], [120, 999], [True, 121]):
            for key in ('pickupIds', 'returnIds'):
                evidence = self.evidence()
                evidence[0][1][key] = value
                with self.subTest(key=key, value=value):
                    self.assertTrue(self.verify(evidence)['issues'])
        evidence = self.evidence()
        neat = next(row for row in evidence[0] if row.get('id') == 'neat-batch')
        tool = neat['resources'][0]['id']
        neat.update(pickupIds=[tool], returnIds=[tool])
        self.assertEqual([], self.verify(evidence)['issues'])
        neat['returnIds'] = [999]
        self.assertTrue(self.verify(evidence)['issues'])

    def test_native_failures_keep_observed_precedence_without_waiving_resources(self):
        self.selection['mode'] = 'native'
        for owner, remaining, tail, returned, reason in [
                (False, 0, False, False, 'owner-still-busy'),
                (True, 1, True, True, 'owner-still-busy'),
                (True, 0, False, False, 'native-independent-tail-not-preserved'),
                (True, 0, True, False, 'native-returns-not-before-tail')]:
            evidence = self.evidence()
            row = evidence[0][1]
            row.update(status='failed', reason=reason, ownerIdle=owner, remaining=remaining,
                       tailRead=tail, returnsBeforeRead=returned)
            evidence[1][1][1]['tailRead'] = tail
            evidence[0][-1]['failed'] = 1
            with self.subTest(reason=reason):
                result = self.verify(evidence)
                self.assertEqual([reason], result['issues'])
                self.assertEqual(reason, result['outcomes'][0]['reason'])
                self.assertTrue(all(row['status'] == 'passed' for row in result['outcomes'][1:]))
                row['reason'] = 'wrong'
                self.assertIn('Craft UI observed native status differs: context', self.verify(evidence)['issues'])
                row['reason'] = reason
                for record in (row, evidence[1][1][1]):
                    record['resources'][0]['id'] = 999
                self.assertIn('Craft UI exact tool conservation/endpoint differs: context', self.verify(evidence)['issues'])

    def test_active_cancellation_requires_real_early_progress_state_and_exact_materials(self):
        self.selection['cases'] = list(craft_ui.CANCEL_CASES)
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                with self.subTest(kind=kind, mode=mode):
                    self.assertEqual([], self.verify()['issues'])
        self.selection.update(kind='mp', mode='toolkit')
        for key, value in [('interruptionProgress', 0), ('interruptionProgress', .251),
                           ('interruptionProgress', True), ('interruptionProgress', float('inf')),
                           ('interrupted', False), ('progressIds', [1, 2]), ('tailProgress', False),
                           ('tokenCancelled', False), ('outcomeTrace', []), ('playerId', -1)]:
            evidence = self.evidence()
            evidence[0][1][key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(self.verify(evidence)['issues'])
        for key, value in [('consumed', 1), ('outputs', 1), ('materialStates', []), ('sparePlanks', [])]:
            rows, raw = self.evidence()
            rows[1][key] = copy.deepcopy(value); raw[1][1][key] = value
            with self.subTest(authority_key=key):
                self.assertTrue(self.verify((rows, raw))['issues'])
        for key, value in [('condition', 9), ('kind', 'Base.Log'), ('uses', True), ('id', 999)]:
            rows, raw = self.evidence()
            rows[1]['materialStates'][0][key] = value; raw[1][1]['materialStates'][0][key] = value
            with self.subTest(material_key=key):
                self.assertTrue(self.verify((rows, raw))['issues'])
        rows, raw = self.evidence()
        rows[1]['outcomeTrace'][1]['token'] = '00000000-0000-0000-0000-000000000000'
        self.assertTrue(self.verify((rows, raw))['issues'])
        self.assertTrue(self.verify(extra='[CRAFT_UI_TEST] OUTCOME {}')['issues'])

    def test_cancellation_native_tail_failure_keeps_tool_conservation_and_neat_stays_in_bags(self):
        self.selection.update(cases=list(craft_ui.CANCEL_CASES), mode='native')
        rows, raw = self.evidence()
        row = rows[1]
        row.update(status='failed', reason='native-independent-tail-not-preserved', tailRead=False,
                   tailProgress=False, returnsBeforeRead=False, returnIds=[], toolsReturned=0)
        raw[1][1].update(tailRead=False, toolsReturned=0)
        for record in (row, raw[1][1]):
            for resource in record['resources']:
                resource.update(sourceCount=0, rootCount=1)
        rows[-1]['failed'] = 1
        for cancelled in (False, True):
            row['tokenCancelled'] = cancelled
            self.assertEqual(['native-independent-tail-not-preserved'], self.verify((rows, raw))['issues'])
        row['tokenCancelled'] = 1
        self.assertTrue(self.verify((rows, raw))['issues'])
        row['tokenCancelled'] = True
        for target in (rows[3], raw[5][1]):
            target['resources'][0].update(sourceCount=0, rootCount=1)
            target['toolsReturned'] = 1
        self.assertTrue(self.verify((rows, raw))['issues'])

    def test_pool_receipts_preserve_removed_identity_and_prestart_proof(self):
        self.selection['cases'] = list(craft_ui.POOL_CASES)
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            self.assertEqual([], self.verify()['issues'])
        for key, value in [('manualMaterialIds', [[100], [101]]), ('manualMaterialIds', [[100, 101], [100, 999]]),
                           ('poolPhaseProof', {}), ('secondAllocated', True), ('secondStarted', True),
                           ('progressIds', [1, 2]), ('consumed', 1), ('spentMaterials', [{'id': 100}]),
                           ('survivingMaterials', [{'id': 100}]), ('removedMaterials', []), ('outputPlankCounts', [True])]:
            rows, raw = self.evidence()
            rows[1][key] = copy.deepcopy(value)
            if key in craft_ui.POOL_RECEIPT_KEYS or key == 'consumed':
                raw[2][1][key] = copy.deepcopy(value)
            with self.subTest(key=key, value=value):
                self.assertTrue(self.verify((rows, raw))['issues'])
        for phase in ('secondAllocatedAtRequest', 'secondAllocatedAtRemoval', 'observedBeforeSecondAllocation'):
            rows, raw = self.evidence()
            rows[1]['poolPhaseProof'][phase] = phase != 'observedBeforeSecondAllocation'
            with self.subTest(phase=phase):
                self.assertTrue(self.verify((rows, raw))['issues'])
        for change in ('missing', 'duplicate', 'late', 'wrong-id', 'wrong-metadata'):
            rows, raw = self.evidence()
            if change == 'missing': raw.pop(1)
            elif change == 'duplicate': raw.insert(1, copy.deepcopy(raw[1]))
            elif change == 'late': raw[1], raw[2] = raw[2], raw[1]
            elif change == 'wrong-id': raw[1][1]['removedMaterials'][0]['id'] = 999
            else: raw[1][1]['removedMaterials'][0]['condition'] = 9
            with self.subTest(removal=change):
                self.assertTrue(self.verify((rows, raw))['issues'])

    def test_previous_owned_outputs_cannot_reappear_as_later_baseline(self):
        self.selection['cases'] = ['context', 'vanilla-batch']
        rows, raw = self.evidence()
        self.assertEqual([], self.verify((rows, raw))['issues'])
        raw[2][1]['baselineOutputIds'].append(raw[1][1]['outputIds'][0])
        self.assertTrue(self.verify((rows, raw))['issues'])

    def test_cancel_then_pool_does_not_retain_owned_materials_as_spares(self):
        self.selection['cases'] = ['vanilla-cancel-active', 'vanilla-missing-batch-pool']
        rows, raw = self.evidence()
        # The unrelated pre-existing spare/baseline persist; canceled owned Planks do not.
        unrelated = copy.deepcopy(raw[0][1]['sparePlanks'])
        for target in (raw[2][1], raw[4][1], rows[2]):
            target['sparePlanks'] = copy.deepcopy(unrelated)
        self.assertEqual([], self.verify((rows, raw))['issues'])
        for meta in raw[0][1]['materialMeta']:
            bad_rows, bad_raw = copy.deepcopy((rows, raw))
            for target in (bad_raw[2][1], bad_raw[4][1], bad_rows[2]):
                target['sparePlanks'].append(copy.deepcopy(meta))
                target['sparePlanks'].sort(key=lambda entry: entry['id'])
            self.assertTrue(self.verify((bad_rows, bad_raw))['issues'])
        # Previous cancellation receipts still prove survival, before fixture cleanup.
        self.assertEqual(['surviving', 'surviving'], [entry['state'] for entry in raw[1][1]['materialStates']])
        self.assertEqual([800], raw[2][1]['baselineOutputIds'])

    def test_pool_probe_is_nonvacuous_with_no_preexisting_spares(self):
        self.selection['cases'] = list(craft_ui.POOL_CASES)
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                rows, raw = self.evidence()
                for row in rows[1:-1]:
                    row['sparePlanks'] = []
                for marker, value in raw:
                    if marker in ('PREPARED', 'VERIFIED'):
                        value['sparePlanks'] = []
                with self.subTest(kind=kind, mode=mode):
                    self.assertEqual([], self.verify((rows, raw))['issues'])
                    del rows[1]['introducedSpare']
                    self.assertTrue(self.verify((rows, raw))['issues'])

    def test_introduced_pool_spare_is_exact_distinct_and_removed_before_next_case(self):
        self.selection['cases'] = list(craft_ui.POOL_CASES)
        for change in ('missing', 'metadata', 'bool-id', 'selected-id', 'spare-id', 'output-id',
                       'after-pool-expanded', 'after-pool-missing', 'next-prep-retains', 'cross-case-reused'):
            rows, raw = self.evidence()
            row, removal, receipt = rows[1], raw[1][1], raw[2][1]
            if change == 'missing':
                del removal['introducedSpare']
            elif change == 'metadata':
                row['introducedSpare']['condition'] = receipt['introducedSpare']['condition'] = 9
            elif change in ('bool-id', 'selected-id', 'spare-id', 'output-id'):
                value = {'bool-id': True, 'selected-id': 100, 'spare-id': 9000, 'output-id': 5000}[change]
                for target in (row, removal, receipt):
                    target['introducedSpare']['id'] = value
            elif change == 'after-pool-expanded':
                row['manualMaterialIdsAfterRemoval'][0].append(removal['introducedSpare']['id'])
            elif change == 'after-pool-missing':
                del row['manualMaterialIdsAfterRemoval']
            elif change == 'next-prep-retains':
                raw[3][1]['sparePlanks'].append(copy.deepcopy(removal['introducedSpare']))
                rows[2]['sparePlanks'] = raw[5][1]['sparePlanks'] = copy.deepcopy(raw[3][1]['sparePlanks'])
            else:
                for target in (rows[2], raw[4][1], raw[5][1]):
                    target['introducedSpare'] = copy.deepcopy(removal['introducedSpare'])
            with self.subTest(change=change):
                self.assertTrue(self.verify((rows, raw))['issues'])

    def test_pool_native_actual_extra_output_or_second_start_is_failure_never_a_toolkit_waiver(self):
        self.selection.update(cases=list(craft_ui.POOL_CASES), mode='native')
        for outputs, allocated, started, reason in [
                (0, False, False, 'native-retained-input-effect-differs'),
                (2, False, False, 'native-retained-input-effect-differs'),
                (1, True, False, 'native-second-craft-allocated'),
                (2, True, True, 'native-second-craft-allocated')]:
            rows, raw = self.evidence()
            rows[1].update(status='failed', reason=reason, secondAllocated=allocated, secondStarted=started,
                           progressIds=[1, 2] if started else [1])
            for target in (rows[1], raw[2][1]):
                target.update(outputs=outputs, outputIds=list(range(5000, 5000 + outputs)), outputPlankCounts=[1] * outputs)
            rows[-1]['failed'] = 1
            with self.subTest(outputs=outputs, allocated=allocated, started=started):
                self.assertEqual([reason], self.verify((rows, raw))['issues'])
                self.selection['mode'] = 'toolkit'
                for row in rows:
                    row['mode'] = 'toolkit'
                rows[0]['queueEnabled'] = True
                for row in rows[1:-1]:
                    row.update(tokenCancelled=True, sharedPerformCount=1, sharedCompleteCount=1)
                self.assertTrue(self.verify((rows, raw))['issues'])
                self.selection['mode'] = 'native'


if __name__ == '__main__':
    unittest.main()
