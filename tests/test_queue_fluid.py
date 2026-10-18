"""Fluid receipts cannot pass from progress alone or client-only Host claims."""
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
            prep = dict(case=case, bottleId=base, bagId=base + 1, bookId=base + 2,
                        amount=1.0, thirst=.6, source='bag' if bag else 'root', favorite=case.endswith('-favorite'))
            receipt = dict(prep, amount=.5, thirst=.5,
                           bottleCount=1, tailRead=True)
            raw += [('PREPARED', prep), ('VERIFIED', receipt)]
            rows.append(dict(event='case', id=case, status='passed', reason=None,
                             **{key: value for key, value in receipt.items() if key != 'case'},
                             pickupObserved=bag, drinkProgress=True, nativeDuration=460, menuDispatched=True, portion=.5,
                             actionType='ISDrinkFluidAction'))
        rows.append(dict(event='complete', cases=cases, expected=len(cases), performed=len(cases), failed=0, skipped=0))
        return ([dict(row, suite='fluid', kind=self.selection['kind'], mode=self.selection['mode'], actor='client1')
                 for row in rows], raw)

    def verify(self, evidence=None, marker='[FLUID_TEST] COMPLETE', wrong_authority=False, extra=''):
        rows, raw = self.evidence() if evidence is None else evidence
        client = '\n'.join('[QUEUE_CHECK] ' + json.dumps(row) for row in rows) + '\n' + marker + '\n' + extra
        authority = '\n'.join('[FLUID_TEST] ' + name + ' ' + json.dumps(value) for name, value in raw)
        if self.selection['kind'] == 'mp':
            (self.root / 'server-launch.log').write_text('' if wrong_authority else authority)
            if wrong_authority:
                client += '\n' + authority
        else:
            client += '\n' + authority
        (self.root / 'client1-launch.log').write_text(client)
        return fluid.verify(self.root, self.selection, {})

    def test_real_effect_receipts_pass_sp_host_native_and_toolkit(self):
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
                 'craft/scripts/queue_craft.txt', 'health/shared/QueueHealthEvents.lua',
                 'startup/client/ZZStartup.lua', 'startup/server/ZZStartupServer.lua']
        for name in paths + ['fluid/ignored.txt', 'craft/client/Old.lua']:
            path = project / 'tests/native_queue' / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('fixture')
        self.assertCountEqual([project / 'tests/native_queue' / name for name in paths],
                              fluid.sources(project, self.selection))
        with patch.object(fluid.craft, 'stage_common') as common:
            fluid.stage(project, self.root, 'game', 'jdk', self.selection, {}, {})
            common.assert_called_once_with(project, self.root, 'game', 'jdk', self.selection, {}, {})

    def test_marker_event_context_counts_and_order_are_strict(self):
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
            with self.subTest(change=change):
                self.assertTrue(self.verify((rows, raw))['issues'])
        self.assertTrue(self.verify(extra='[QUEUE_TEST] FAIL fluid')['issues'])
        with self.assertRaises(ValueError):
            self.verify(extra='[QUEUE_CHECK] []')

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
                elif change == 'missing-field': del raw[-1][1]['bottleCount']
                elif change == 'disagree': rows[-2]['amount'] = .87
                else: raw[-2][1]['bookId'] = raw[0][1]['bookId']
                with self.subTest(kind=kind, change=change):
                    self.assertTrue(self.verify((rows, raw))['issues'])
        self.assertTrue(self.verify(wrong_authority=True)['issues'])
        with self.assertRaises(ValueError):
            fluid._authority('[FLUID_TEST] PREPARED []')

    def test_progress_alone_cannot_substitute_exact_effects_and_conservation(self):
        for key, value in [('amount', .99), ('amount', True), ('amount', float('nan')),
                           ('thirst', .6), ('thirst', -.1), ('thirst', float('inf')),
                           ('bottleCount', 2), ('bottleCount', True), ('tailRead', False),
                           ('source', 'floor'), ('bottleId', 999), ('bookId', True)]:
            rows, raw = self.evidence()
            rows[1][key] = value
            raw[1][1][key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(self.verify((rows, raw))['issues'])
        for key, value in [('pickupObserved', False), ('pickupObserved', 1), ('drinkProgress', False),
                           ('actionType', 'ISDrinkFromBottle'), ('nativeDuration', 1), ('nativeDuration', 2),
                           ('nativeDuration', 460.0), ('nativeDuration', True)]:
            rows, raw = self.evidence()
            rows[1][key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(self.verify((rows, raw))['issues'])
        rows, raw = self.evidence()
        rows[2]['source'] = raw[3][1]['source'] = 'bag'
        self.assertTrue(self.verify((rows, raw))['issues'])
        rows, raw = self.evidence()
        rows[1]['source'] = raw[1][1]['source'] = 'root'
        self.assertEqual([], self.verify((rows, raw))['issues'], 'P4 may return a bag bottle or leave it in root')

    def test_favorite_must_be_present_and_retained_for_the_selected_case(self):
        for change in ('missing-prepared', 'missing-verified', 'lost', 'mislabelled', 'not-bool', 'client-only'):
            rows, raw = self.evidence()
            if change == 'missing-prepared': del raw[4][1]['favorite']
            elif change == 'missing-verified': del raw[5][1]['favorite']
            elif change == 'lost': rows[3]['favorite'] = raw[5][1]['favorite'] = False
            elif change == 'mislabelled': rows[1]['favorite'] = raw[0][1]['favorite'] = raw[1][1]['favorite'] = True
            elif change == 'not-bool': rows[3]['favorite'] = raw[4][1]['favorite'] = raw[5][1]['favorite'] = 1
            else: rows[3]['favorite'] = False
            with self.subTest(change=change):
                self.assertTrue(self.verify((rows, raw))['issues'])

    def test_native_volume_overshoot_is_narrow_and_preserves_raw_measurements(self):
        self.selection['kind'] = 'mp'
        for amount in (.497, .4971739, .4985328, .499891, .49, .5001):
            rows, raw = self.evidence()
            rows[1]['amount'] = raw[1][1]['amount'] = amount
            with self.subTest(amount=amount):
                result = self.verify((rows, raw))
                self.assertEqual([], result['issues'])
                self.assertEqual(amount, result['outcomes'][0]['outcome']['amount'])
        for amount in (.48999, .50011, .75, 1.0, 0.0):
            rows, raw = self.evidence()
            rows[1]['amount'] = raw[1][1]['amount'] = amount
            with self.subTest(amount=amount):
                self.assertTrue(self.verify((rows, raw))['issues'])


if __name__ == '__main__':
    unittest.main()
