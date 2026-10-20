"""Fluid evidence must identify both bottles and every real menu command."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks import adapters
from queue_checks.adapters import fluid


class FluidAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = dict(suite='fluid', cases=list(fluid.CASES), kind='sp', mode='toolkit',
                              languages=['EN'], mods=list(fluid.MODS), clients=1, options={})

    def evidence(self):
        cases = self.selection['cases']
        rows = [dict(event='setup', cases=cases, expected=len(cases),
                     queueEnabled=self.selection['mode'] == 'toolkit', nativeDurations=True)]
        raw = []
        for index, case in enumerate(cases):
            base, bag = 100 + index * 10, case.startswith('fluid-bag')
            editing = case == fluid.EDIT_CASE
            favorite = case.endswith('-favorite')
            full = '-full-' in case
            thirst = .04 if '-smart-low-' in case else .2 if '-smart-' in case else .8
            menu, portion = 'half', .5
            if '-all-' in case: menu, portion = 'all', 1
            elif '-quarter-' in case or '-same-serial-' in case: menu, portion = 'quarter', .25
            elif '-smart-' in case: menu, portion = 'smart', thirst / .5
            elif '-sip-' in case: menu, portion = 'sip', .01
            targets = [0, 1] if editing else [0, 1, 2] if '-cancel-' in case else [0, 0] if '-same-' in case else [0, 1] if '-pair-' in case else [1] if '-second-' in case else [0]
            cancelling = '-cancel-' in case and self.selection['mode'] == 'toolkit'
            prep = dict(case=case, bagId=base, bagType='Base.Bag_ALICEpack_Army', thirst=thirst,
                        foodTimer=4000 if full else 0, foodLevel=3 if full else 0,
                        bottles=[dict(id=base + n + 1, amount=1.0, favorite=favorite,
                                      source='root' if editing and n == 0 else 'bag' if bag else 'root', thirstChange=-.5,
                                      **({'weight': 1.1} if editing else {})) for n in range(3 if '-cancel-' in case else 2)])
            amounts = [1.0] * len(prep['bottles'])
            commands = []
            for position, n in enumerate(targets):
                cancelled = cancelling and position == 1
                dispatch_amount = amounts[n] if '-serial-' in case else 1.0
                commands.append(dict(id=prep['bottles'][n]['id'], menu=menu, portion=portion,
                                     pickupObserved=bag and not (editing and position == 0) and not cancelled, drinkProgress=not cancelled, nativeDuration=460, menuDispatched=not (editing and position == 1),
                                     dispatchThirst=thirst, foodLevel=prep['foodLevel'], backpackWorn=True,
                                     queueEmptyBefore=position == 0 or '-serial-' in case,
                                     previousDrinkPending=position > 0 and '-serial-' not in case,
                                     dispatchAmount=dispatch_amount, dispatchSource='root' if editing and position == 0 else 'bag' if bag else 'root', cancelled=cancelled))
                if not cancelled:
                    base_amount = amounts[n] if self.selection['kind'] == 'mp' and '-queued-' in case else dispatch_amount
                    amounts[n] = base_amount * (1 - portion)
            receipt = dict(case=case, bagId=base, bagType=prep['bagType'], thirst=max(0, thirst - .5 * sum(1 - amount for amount in amounts)), foodLevel=prep['foodLevel'],
                           bottles=[dict(id=bottle['id'], amount=amounts[n],
                                         favorite=favorite, source=('root' if n == 0 or self.selection['mode'] == 'toolkit' else 'bag') if editing else bottle['source'], count=1,
                                         **({'weight': 1.1 - (1 - amounts[n])} if editing else {}))
                                    for n, bottle in enumerate(prep['bottles'])])
            edit = dict(anchorRunning=True, bottleId=prep['bottles'][1]['id'], fullWeight=1.1, standalone=True,
                        pickupDuration=-1 if self.selection['kind'] == 'mp' else 52.8,
                        returnDuration=-1 if self.selection['kind'] == 'mp' else 52.8,
                        nativeDurationsUnchanged=True, contractsVerified=self.selection['mode']=='toolkit',
                        reordered=self.selection['mode']=='toolkit', moveRejected=self.selection['mode']=='toolkit',
                        cancelRejected=self.selection['mode']=='toolkit', untouchedBefore=True,
                        returnNoopObserved=self.selection['mode']=='toolkit', returnDontAdd=self.selection['mode']=='toolkit',
                        returnStarted=False, returnTransactionId=0) if editing else None
            raw += [('PREPARED', prep), ('VERIFIED', receipt)]
            rows.append(dict(event='case', id=case, status='passed', reason=None, commands=commands,
                             waitingCancelVerified=cancelling, independentMoveVerified=cancelling and not bag,
                             **({'editEvidence': edit} if editing else {}), **copy.deepcopy({key: value for key, value in receipt.items() if key != 'case'})))
        rows.append(dict(event='complete', cases=cases, expected=len(cases), performed=len(cases), failed=0, skipped=0))
        return ([dict(row, suite='fluid', kind=self.selection['kind'], mode=self.selection['mode'], actor='client1')
                 for row in rows], raw)

    def verify(self, evidence=None, marker='[FLUID_TEST] COMPLETE', wrong_authority=False, extra=''):
        rows, raw = self.evidence() if evidence is None else evidence
        client = '\n'.join('[QUEUE_CHECK] ' + json.dumps(row) for row in rows) + '\n' + marker + '\n' + extra
        authority = '\n'.join('[FLUID_TEST] ' + name + ' ' + json.dumps(value) for name, value in raw)
        if self.selection['kind'] == 'mp':
            (self.root / 'server-launch.log').write_text('' if wrong_authority else authority)
            if wrong_authority: client += '\n' + authority
        else: client += '\n' + authority
        (self.root / 'client1-launch.log').write_text(client)
        return fluid.verify(self.root, self.selection, {})

    def single(self, case='fluid-bag-favorite'):
        self.selection['cases'] = [case]
        return self.evidence()

    def test_matrix_accepts_sp_host_native_and_toolkit(self):
        self.assertEqual(19, len(fluid.CASES))
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                with self.subTest(kind=kind, mode=mode):
                    fluid.validate(self.selection)
                    result = self.verify()
                    self.assertEqual([], result['issues'])
                    self.assertEqual(fluid.CASES, [row['case'] for row in result['outcomes']])
                    self.assertTrue(all(row['status'] == 'passed' for row in result['outcomes']))

    def test_registration_selection_and_shared_staging(self):
        self.assertIs(fluid, adapters.get('fluid'))
        self.assertEqual(fluid.CASES, [case['id'] for case in fluid.definitions()['fluid']['cases']])
        fluid.validate(dict(self.selection, cases=['fluid-bag']))
        for change in ({'cases': []}, {'cases': ['unknown']}, {'cases': ['fluid-bag', 'fluid-bag']},
                       {'cases': ['fluid-root', 'fluid-bag']}, {'cases': ['thirst-bag']}, {'kind': 'coop'}, {'mode': 'other'},
                       {'languages': ['RU']}, {'clients': True}, {'clients': 2},
                       {'mods': fluid.MODS[:-1]}, {'options': {'world_template': '/existing'}}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                fluid.validate(dict(self.selection, **change))
        project = self.root / 'project'
        paths = ['fluid/client/UI.lua', 'fluid/shared/Fixture.lua', 'fluid/server/Server.lua',
                 'craft/scripts/queue_craft.txt', 'health/shared/QueueHealthEvents.lua', 'support/QueueScenarioChecks.lua',
                 'startup/client/ZZStartup.lua', 'startup/server/ZZStartupServer.lua']
        for name in paths + ['fluid/ignored.txt', 'craft/client/Old.lua']:
            path = project / 'tests/native_queue' / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture')
        self.assertCountEqual([project / 'tests/native_queue' / name for name in paths], fluid.sources(project, self.selection))
        with patch.object(fluid.craft, 'stage_common') as common:
            runtime = {'roles': {name: {'cache': self.root / name} for name in ('client1', 'server')}}
            for role in runtime['roles'].values():
                (role['cache'] / 'mods/ActionQueueTest/42/media/lua/shared').mkdir(parents=True)
            fluid.stage(project, self.root, 'game', 'jdk', self.selection, {}, runtime)
            common.assert_called_once_with(project, self.root, 'game', 'jdk', self.selection, {}, runtime)
            for role in runtime['roles'].values():
                self.assertEqual('fixture', (role['cache'] / 'mods/ActionQueueTest/42/media/lua/shared/QueueScenarioChecks.lua').read_text())

    def test_events_markers_context_and_counts_are_strict(self):
        for marker in ('', '[FLUID_TEST] COMPLETE_PENDING', '[FLUID_TEST] COMPLETE\n[FLUID_TEST] COMPLETE'):
            self.assertTrue(self.verify(marker=marker)['issues'])
        self.assertFalse(fluid.complete(self.selection, 'server', '[FLUID_TEST] COMPLETE'))
        for change in ('missing', 'duplicate', 'order', 'unknown', 'context', 'count', 'mode', 'failed'):
            rows, raw = self.evidence()
            if change == 'missing': rows.pop(1)
            elif change == 'duplicate': rows.insert(2, copy.deepcopy(rows[1]))
            elif change == 'order': rows[1], rows[2] = rows[2], rows[1]
            elif change == 'unknown': rows[1]['id'] = 'unknown'
            elif change == 'context': rows[1]['actor'] = 'client2'
            elif change == 'count': rows[-1]['performed'] = True
            elif change == 'mode': rows[0]['queueEnabled'] = False
            else: rows[1]['status'] = 'failed'
            with self.subTest(change=change): self.assertTrue(self.verify((rows, raw))['issues'])
        self.assertTrue(self.verify(extra='[QUEUE_TEST] FAIL fluid')['issues'])
        with self.assertRaises(ValueError): self.verify(extra='[QUEUE_CHECK] []')

    def test_authority_is_exact_ordered_unique_and_server_owned_in_host(self):
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for change in ('missing', 'duplicate', 'order', 'unknown', 'extra', 'missing-field', 'disagree', 'identity-reuse'):
                rows, raw = self.evidence()
                if change == 'missing': raw.pop()
                elif change == 'duplicate': raw.append(copy.deepcopy(raw[-1]))
                elif change == 'order': raw[0], raw[1] = raw[1], raw[0]
                elif change == 'unknown': raw[-1] = ('OTHER', raw[-1][1])
                elif change == 'extra': raw[-1][1]['extra'] = 1
                elif change == 'missing-field': del raw[-1][1]['bottles'][0]['count']
                elif change == 'disagree': rows[-2]['bottles'][0]['amount'] = .87
                else: raw[-2][1]['bottles'][0]['id'] = raw[0][1]['bottles'][0]['id']
                with self.subTest(kind=kind, change=change): self.assertTrue(self.verify((rows, raw))['issues'])
        self.assertTrue(self.verify(wrong_authority=True)['issues'])
        with self.assertRaises(ValueError): fluid._authority('[FLUID_TEST] PREPARED []')

    def test_two_bottle_identity_favorite_and_preparation_are_strict(self):
        for change in ('missing', 'lost', 'mislabelled', 'bool', 'id', 'same-id', 'bag', 'initial-volume', 'initial-thirst', 'thirst-change'):
            rows, raw = self.single()
            if change == 'missing': del raw[0][1]['bottles'][0]['favorite']
            elif change == 'lost': rows[1]['bottles'][0]['favorite'] = raw[1][1]['bottles'][0]['favorite'] = False
            elif change == 'mislabelled': raw[0][1]['bottles'][1]['favorite'] = False
            elif change == 'bool': raw[0][1]['bottles'][0]['favorite'] = 1
            elif change == 'id': rows[1]['bottles'][0]['id'] = raw[1][1]['bottles'][0]['id'] = 999
            elif change == 'same-id': raw[0][1]['bottles'][1]['id'] = raw[0][1]['bagId']
            elif change == 'bag': rows[1]['bagType'] = raw[1][1]['bagType'] = 'Base.Bag_Schoolbag'
            elif change == 'initial-volume': raw[0][1]['bottles'][0]['amount'] = .5
            elif change == 'initial-thirst': raw[0][1]['thirst'] = .1
            else: raw[0][1]['bottles'][0]['thirstChange'] = 0
            with self.subTest(change=change): self.assertTrue(self.verify((rows, raw))['issues'])

    def test_selected_and_unselected_bottles_have_distinct_effect_contracts(self):
        for key, value, index in [('amount', .99, 0), ('amount', True, 0), ('amount', float('nan'), 0),
                                  ('amount', .99, 1), ('source', 'root', 1), ('source', 'floor', 0),
                                  ('count', 2, 0), ('count', True, 1)]:
            rows, raw = self.single()
            rows[1]['bottles'][index][key] = raw[1][1]['bottles'][index][key] = value
            with self.subTest(key=key, value=value, index=index): self.assertTrue(self.verify((rows, raw))['issues'])
        for thirst in (.8, -.1, float('inf'), True):
            rows, raw = self.single()
            rows[1]['thirst'] = raw[1][1]['thirst'] = thirst
            with self.subTest(thirst=thirst): self.assertTrue(self.verify((rows, raw))['issues'])
        rows, raw = self.single('fluid-root-favorite')
        rows[1]['bottles'][0]['source'] = raw[1][1]['bottles'][0]['source'] = 'bag'
        self.assertTrue(self.verify((rows, raw))['issues'])
        rows, raw = self.single()
        rows[1]['bottles'][0]['source'] = raw[1][1]['bottles'][0]['source'] = 'root'
        self.assertEqual([], self.verify((rows, raw))['issues'])

    def test_commands_must_prove_exact_target_order_menu_and_native_progress(self):
        for key, value in [('id', 102), ('menu', 'all'), ('portion', .25), ('portion', True),
                           ('pickupObserved', False), ('drinkProgress', False), ('menuDispatched', 1),
                           ('nativeDuration', 2), ('nativeDuration', 460.0)]:
            rows, raw = self.single()
            rows[1]['commands'][0][key] = value
            with self.subTest(key=key, value=value): self.assertTrue(self.verify((rows, raw))['issues'])
        for case in ('fluid-bag-pair-queued-favorite', 'fluid-bag-pair-serial-favorite'):
            for change in ('missing', 'order', 'stopped', 'duplicate-target'):
                rows, raw = self.single(case)
                commands = rows[1]['commands']
                if change == 'missing': commands.pop()
                elif change == 'order': commands.reverse()
                elif change == 'stopped': commands[1]['drinkProgress'] = False
                else: commands[1]['id'] = commands[0]['id']
                with self.subTest(case=case, change=change): self.assertTrue(self.verify((rows, raw))['issues'])
        rows, raw = self.single('fluid-bag-second-favorite')
        rows[1]['commands'][0]['id'] = raw[0][1]['bottles'][0]['id']
        self.assertTrue(self.verify((rows, raw))['issues'])
        for case in ('fluid-bag-smart-favorite', 'fluid-bag-smart-low-favorite'):
            rows, raw = self.single(case)
            rows[1]['commands'][0]['portion'] = .5
            with self.subTest(case=case): self.assertTrue(self.verify((rows, raw))['issues'])

    def test_native_volume_overshoot_is_narrow_and_preserves_raw_measurements(self):
        self.selection['kind'] = 'mp'
        for amount in (.497, .4971739, .4985328, .499891, .49, .5001):
            rows, raw = self.single()
            rows[1]['bottles'][0]['amount'] = raw[1][1]['bottles'][0]['amount'] = amount
            with self.subTest(amount=amount):
                result = self.verify((rows, raw))
                self.assertEqual([], result['issues'])
                self.assertEqual(amount, result['outcomes'][0]['outcome']['bottles'][0]['amount'])
        for amount in (.48999, .50011, .75, 1.0, 0.0):
            rows, raw = self.single()
            rows[1]['bottles'][0]['amount'] = raw[1][1]['bottles'][0]['amount'] = amount
            with self.subTest(amount=amount): self.assertTrue(self.verify((rows, raw))['issues'])
        rows, raw = self.single('fluid-bag-all-favorite')
        rows[1]['bottles'][0]['amount'] = raw[1][1]['bottles'][0]['amount'] = -.001
        self.assertTrue(self.verify((rows, raw))['issues'])

    def test_dispatch_queue_and_worn_bag_flags_are_required_typed_observations(self):
        for field, wrong_values in (
                ('queueEmptyBefore', (False, 1, 'true', None)),
                ('previousDrinkPending', (True, 0, 'false', None)),
                ('backpackWorn', (False, 1, 'true', None))):
            rows, raw = self.single()
            del rows[1]['commands'][0][field]
            with self.subTest(field=field, change='missing'):
                self.assertTrue(self.verify((rows, raw))['issues'])
            for value in wrong_values:
                rows, raw = self.single()
                rows[1]['commands'][0][field] = value
                with self.subTest(field=field, value=value):
                    self.assertTrue(self.verify((rows, raw))['issues'])

    def test_distinct_bottle_pairs_require_queued_or_serial_dispatch_state(self):
        for case in ('fluid-bag-pair-queued-favorite', 'fluid-bag-pair-serial-favorite'):
            rows, raw = self.single(case)
            commands = rows[1]['commands']
            self.assertNotEqual(commands[0]['id'], commands[1]['id'])
            self.assertEqual([], self.verify((rows, raw))['issues'])
            for position in (0, 1):
                for field in ('queueEmptyBefore', 'previousDrinkPending'):
                    for change in ('missing', 'opposite', 'integer'):
                        rows, raw = self.single(case)
                        command = rows[1]['commands'][position]
                        if change == 'missing': del command[field]
                        elif change == 'opposite': command[field] = not command[field]
                        else: command[field] = int(command[field])
                        with self.subTest(case=case, position=position, field=field, change=change):
                            self.assertTrue(self.verify((rows, raw))['issues'])
            rows, raw = self.single(case)
            rows[1]['commands'][1].update(queueEmptyBefore='-queued-' in case,
                                          previousDrinkPending='-serial-' in case)
            with self.subTest(case=case, change='opposite-dispatch-kind'):
                self.assertTrue(self.verify((rows, raw))['issues'])

    def test_same_bottle_repetition_preserves_native_sp_host_fraction_semantics(self):
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            for case in ('fluid-bag-same-serial-favorite', 'fluid-root-same-queued-favorite'):
                rows, raw = self.single(case)
                commands = rows[1]['commands']
                self.assertEqual(commands[0]['id'], commands[1]['id'])
                self.assertEqual(.75 if '-serial-' in case else 1, commands[1]['dispatchAmount'])
                self.assertEqual(.5625 if '-serial-' in case else .5 if kind == 'sp' else .25, raw[1][1]['bottles'][0]['amount'])
                self.assertEqual([], self.verify((rows, raw))['issues'])
                for fault in ('distinct-target', 'wrong-final-volume', 'wrong-dispatch-volume', 'missing-dispatch-source'):
                    rows, raw = self.single(case)
                    if fault == 'distinct-target': rows[1]['commands'][1]['id'] = raw[0][1]['bottles'][1]['id']
                    elif fault == 'wrong-final-volume':
                        rows[1]['bottles'][0]['amount'] = raw[1][1]['bottles'][0]['amount'] = .75
                    elif fault == 'wrong-dispatch-volume': rows[1]['commands'][1]['dispatchAmount'] = .9
                    else: del rows[1]['commands'][1]['dispatchSource']
                    with self.subTest(kind=kind, case=case, fault=fault):
                        self.assertTrue(self.verify((rows, raw))['issues'])

    def test_serial_dispatch_overshoot_cannot_hide_an_underconsumed_first_quarter(self):
        for kind in ('sp', 'mp'):
            self.selection['kind'] = kind
            rows, raw = self.single('fluid-bag-same-serial-favorite')
            rows[1]['commands'][1]['dispatchAmount'] = .759
            rows[1]['bottles'][0]['amount'] = raw[1][1]['bottles'][0]['amount'] = .56925
            rows[1]['thirst'] = raw[1][1]['thirst'] = .8 - (1 - .56925) * .5
            with self.subTest(kind=kind):
                self.assertIn('Fluid dispatch volume differs: fluid-bag-same-serial-favorite',
                              self.verify((rows, raw))['issues'])

    def test_waiting_cancellation_requires_untouched_middle_and_retained_drinks(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                for case in ('fluid-root-cancel-waiting-favorite', 'fluid-bag-cancel-waiting-favorite'):
                    rows, raw = self.single(case)
                    cancelling = mode == 'toolkit'
                    self.assertEqual([.5, 1 if cancelling else .5, .5], [bottle['amount'] for bottle in raw[1][1]['bottles']])
                    self.assertIs(rows[1]['waitingCancelVerified'], cancelling)
                    self.assertEqual([], self.verify((rows, raw))['issues'])
                    for fault in ('flag', 'integer-flag', 'move-flag', 'command-flag', 'middle-volume', 'middle-source', 'tail-progress', 'tail-target', 'missing-command'):
                        rows, raw = self.single(case)
                        if fault == 'flag': rows[1]['waitingCancelVerified'] = not cancelling
                        elif fault == 'integer-flag': rows[1]['waitingCancelVerified'] = int(cancelling)
                        elif fault == 'move-flag': rows[1]['independentMoveVerified'] = not rows[1]['independentMoveVerified']
                        elif fault == 'command-flag': rows[1]['commands'][1]['cancelled'] = not cancelling
                        elif fault == 'middle-volume':
                            rows[1]['bottles'][1]['amount'] = raw[1][1]['bottles'][1]['amount'] = .5 if cancelling else 1
                        elif fault == 'middle-source':
                            rows[1]['bottles'][1]['source'] = raw[1][1]['bottles'][1]['source'] = 'floor'
                        elif fault == 'tail-progress': rows[1]['commands'][2]['drinkProgress'] = False
                        elif fault == 'tail-target': rows[1]['commands'][2]['id'] = rows[1]['commands'][1]['id']
                        else: rows[1]['commands'].pop(1)
                        with self.subTest(kind=kind, mode=mode, case=case, fault=fault):
                            self.assertTrue(self.verify((rows, raw))['issues'])
                    if cancelling:
                        for field in ('drinkProgress', 'pickupObserved'):
                            rows, raw = self.single(case)
                            rows[1]['commands'][1][field] = True
                            with self.subTest(kind=kind, case=case, field=field):
                                self.assertTrue(self.verify((rows, raw))['issues'])

    def test_dispatch_volume_source_and_cancelled_fields_are_strict(self):
        for field, values in (('dispatchAmount', (True, float('nan'), .5)),
                              ('dispatchSource', ('floor', 'root', None)),
                              ('cancelled', (True, 0, None))):
            rows, raw = self.single()
            del rows[1]['commands'][0][field]
            self.assertTrue(self.verify((rows, raw))['issues'])
            for value in values:
                rows, raw = self.single()
                rows[1]['commands'][0][field] = value
                with self.subTest(field=field, value=value):
                    self.assertTrue(self.verify((rows, raw))['issues'])

    def test_scenario_outcomes_are_derived_from_valid_raw_case_evidence(self):
        fields = ('emptyStartVerified', 'effectsVerified', 'wornBagVerified',
                  'independentRequestsQueued', 'serverAuthorityVerified')
        for kind in ('sp', 'mp'):
            self.selection.update(kind=kind, cases=list(fluid.CASES))
            result = self.verify()
            self.assertEqual([], result['issues'])
            for record in result['outcomes']:
                outcome = record['outcome']
                with self.subTest(kind=kind, case=record['case']):
                    self.assertIs(outcome['emptyStartVerified'], True)
                    self.assertIs(outcome['effectsVerified'], True)
                    self.assertIs(outcome['wornBagVerified'], True)
                    self.assertIs(outcome['independentRequestsQueued'],
                                  record['case'] == 'fluid-bag-pair-queued-favorite')
                    self.assertIs(outcome['serverAuthorityVerified'], kind == 'mp')
                    self.assertIs(outcome['sameBottleRequestsVerified'], '-same-' in record['case'])
                    self.assertIs(outcome['waitingCancelVerified'], '-cancel-' in record['case'])
            for fault in ('historic-command', 'busy-start', 'wrong-volume', 'client-only-authority'):
                rows, raw = self.single('fluid-bag-pair-queued-favorite')
                rows[1].update({field: True for field in fields})
                if fault == 'historic-command':
                    for command in rows[1]['commands']:
                        for field in ('queueEmptyBefore', 'previousDrinkPending', 'backpackWorn'):
                            del command[field]
                elif fault == 'busy-start': rows[1]['commands'][0]['queueEmptyBefore'] = False
                elif fault == 'wrong-volume':
                    rows[1]['bottles'][0]['amount'] = raw[1][1]['bottles'][0]['amount'] = .9
                elif kind != 'mp': continue
                result = self.verify((rows, raw), wrong_authority=fault == 'client-only-authority')
                with self.subTest(kind=kind, fault=fault):
                    self.assertTrue(result['issues'])
                    self.assertEqual('failed', result['outcomes'][0]['status'])
                    self.assertTrue(all(result['outcomes'][0]['outcome'][field] is False for field in fields))

    def test_smart_fraction_uses_bounded_actual_dispatch_thirst(self):
        for case in ('fluid-bag-smart-favorite', 'fluid-bag-smart-low-favorite'):
            rows, raw = self.single(case)
            command = rows[1]['commands'][0]
            command['dispatchThirst'] += .00011511445
            command['portion'] = command['dispatchThirst'] / abs(raw[0][1]['bottles'][0]['thirstChange'])
            rows[1]['bottles'][0]['amount'] = raw[1][1]['bottles'][0]['amount'] = 1 - command['portion']
            with self.subTest(case=case): self.assertEqual([], self.verify((rows, raw))['issues'])
            command['portion'] = .5
            rows[1]['bottles'][0]['amount'] = raw[1][1]['bottles'][0]['amount'] = .5
            self.assertTrue(self.verify((rows, raw))['issues'], 'matching water loss cannot legitimize a forged menu fraction')
        for thirst in (.19, .211, -1, 2, True, float('nan')):
            rows, raw = self.single('fluid-bag-smart-favorite')
            rows[1]['commands'][0]['dispatchThirst'] = thirst
            with self.subTest(thirst=thirst): self.assertTrue(self.verify((rows, raw))['issues'])
        rows, raw = self.single()
        rows[1]['commands'][0]['dispatchThirst'] = True
        self.assertTrue(self.verify((rows, raw))['issues'])

    def test_pending_transfer_edits_require_native_contracts_negative_controls_and_distinct_endpoints(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                rows, raw = self.single(fluid.EDIT_CASE)
                result = self.verify((rows, raw))
                self.assertEqual([], result['issues'])
                self.assertEqual('root' if mode == 'toolkit' else 'bag', raw[1][1]['bottles'][1]['source'])
                self.assertEqual([.5, .5], [bottle['amount'] for bottle in raw[1][1]['bottles']])
                self.assertEqual([False, True], [command['pickupObserved'] for command in rows[1]['commands']])
                self.assertIs(result['outcomes'][0]['outcome']['pendingTransferEditVerified'], mode == 'toolkit')
                self.assertIs(result['outcomes'][0]['outcome']['dependentPickupProtected'], mode == 'toolkit')
                for field in ('anchorRunning', 'standalone', 'contractsVerified', 'reordered', 'moveRejected',
                              'cancelRejected', 'untouchedBefore', 'returnNoopObserved', 'returnDontAdd', 'returnStarted', 'nativeDurationsUnchanged'):
                    for fault in ('missing', 'opposite', 'integer'):
                        rows, raw = self.single(fluid.EDIT_CASE)
                        evidence = rows[1]['editEvidence']
                        if fault == 'missing': evidence.pop(field)
                        elif fault == 'opposite': evidence[field] = not evidence[field]
                        else: evidence[field] = int(evidence[field])
                        with self.subTest(kind=kind, mode=mode, field=field, fault=fault):
                            self.assertTrue(self.verify((rows, raw))['issues'])
                for fault in ('wrong-id', 'full-weight', 'final-weight', 'final-endpoint', 'portion', 'native-menu',
                              'anchor-container', 'transfer-duration', 'drink-progress', 'missing-evidence'):
                    rows, raw = self.single(fluid.EDIT_CASE)
                    if fault == 'wrong-id': rows[1]['editEvidence']['bottleId'] = raw[0][1]['bottles'][0]['id']
                    elif fault == 'full-weight': rows[1]['editEvidence']['fullWeight'] = .6
                    elif fault == 'final-weight': rows[1]['bottles'][1]['weight'] = raw[1][1]['bottles'][1]['weight'] = 1.1
                    elif fault == 'final-endpoint': rows[1]['bottles'][1]['source'] = raw[1][1]['bottles'][1]['source'] = 'bag' if mode == 'toolkit' else 'root'
                    elif fault == 'portion': rows[1]['commands'][1]['portion'] = .25
                    elif fault == 'native-menu': rows[1]['commands'][1]['menuDispatched'] = True
                    elif fault == 'anchor-container': rows[1]['commands'][0]['dispatchSource'] = 'bag'
                    elif fault == 'transfer-duration': rows[1]['editEvidence']['pickupDuration'] = 0
                    elif fault == 'drink-progress': rows[1]['commands'][1]['drinkProgress'] = False
                    else: rows[1].pop('editEvidence')
                    with self.subTest(kind=kind, mode=mode, fault=fault):
                        self.assertTrue(self.verify((rows, raw))['issues'])

    def test_native_return_completion_does_not_imply_an_already_destination_noop(self):
        for kind in ('sp', 'mp'):
            self.selection.update(kind=kind, mode='native')
            rows, raw = self.single(fluid.EDIT_CASE)
            evidence = rows[1]['editEvidence']
            self.assertIs(evidence['returnStarted'], False)
            self.assertEqual(0, evidence['returnTransactionId'])
            self.assertIs(evidence['returnDontAdd'], False)
            self.assertIs(evidence['returnNoopObserved'], False)
            self.assertEqual([], self.verify((rows, raw))['issues'])
            # The former marker would incorrectly label an ordinary completed return as a no-op.
            evidence['returnNoopObserved'] = not evidence['returnStarted'] and evidence['returnTransactionId'] == 0
            self.assertTrue(self.verify((rows, raw))['issues'])
        for value in (None, True, 1, -1):
            rows, raw = self.single(fluid.EDIT_CASE)
            rows[1]['editEvidence']['returnTransactionId'] = value
            self.assertTrue(self.verify((rows, raw))['issues'])

    def test_fullness_requires_authority_metadata_and_actual_dispatch_moodle(self):
        for case in ('fluid-bag-full-favorite', 'fluid-root-full-favorite'):
            for change in ('timer-missing', 'timer-wrong', 'timer-bool', 'prepared-level', 'verified-level',
                           'dispatch-missing', 'dispatch-level', 'dispatch-bool', 'not-started'):
                rows, raw = self.single(case)
                if change == 'timer-missing': del raw[0][1]['foodTimer']
                elif change == 'timer-wrong': raw[0][1]['foodTimer'] = 1600
                elif change == 'timer-bool': raw[0][1]['foodTimer'] = True
                elif change == 'prepared-level': raw[0][1]['foodLevel'] = 0
                elif change == 'verified-level': rows[1]['foodLevel'] = raw[1][1]['foodLevel'] = 0
                elif change == 'dispatch-missing': del rows[1]['commands'][0]['foodLevel']
                elif change == 'dispatch-level': rows[1]['commands'][0]['foodLevel'] = 0
                elif change == 'dispatch-bool': rows[1]['commands'][0]['foodLevel'] = True
                else: rows[1]['commands'][0]['drinkProgress'] = False
                with self.subTest(case=case, change=change): self.assertTrue(self.verify((rows, raw))['issues'])


if __name__ == '__main__':
    unittest.main()
