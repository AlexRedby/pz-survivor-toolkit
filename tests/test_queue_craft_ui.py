"""UI craft receipts preserve native callback ownership and exact authoritative effects."""
import copy
import json
from pathlib import Path
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
        self.selection = dict(suite='craft-ui', cases=list(craft_ui.CASES), kind='sp', mode='toolkit',
                              languages=['EN'], mods=list(craft_ui.MODS), clients=1, options={})

    def evidence(self):
        enabled, cases = self.selection['mode'] == 'toolkit', self.selection['cases']
        rows = [dict(event='setup', cases=cases, expected=len(cases), queueEnabled=enabled, nativeDurations=True)]
        raw = []
        for index, case in enumerate(cases):
            count, base = craft_ui.COUNTS[case], 100 + index * 100
            prep = dict(case=case, materials=list(range(base, base + count)), bags=[base + 10, base + 11],
                        book=base + 12, baselineOutputIds=[800],
                        toolMeta=[dict(id=base + 20 + n, kind=kind, condition=10, uses=0)
                                  for n, kind in enumerate(('Base.Hammer', 'Base.Saw'))])
            receipt = dict(case=case, materialIds=prep['materials'].copy(), consumed=count, outputs=count,
                           outputIds=list(range(5000 + index * 10, 5000 + index * 10 + count)),
                           resources=[dict(meta, sourceCount=1, rootCount=0) for meta in prep['toolMeta']],
                           toolsReturned=2, bookId=prep['book'], tailRead=True)
            raw += [('PREPARED', prep), ('VERIFIED', receipt)]
            transfers = [meta['id'] for meta in prep['toolMeta']] if case == 'context' or case.startswith('vanilla-') else []
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
            row.update({key: copy.deepcopy(value) for key, value in receipt.items() if key != 'case'})
            rows.append(row)
        rows.append(dict(event='complete', cases=cases, expected=len(cases), performed=len(cases), failed=0, skipped=0))
        return ([dict(row, suite='craft-ui', kind=self.selection['kind'], mode=self.selection['mode'], actor='client1')
                 for row in rows], raw)

    def verify(self, evidence=None, marker='[CRAFT_UI_TEST] COMPLETE', extra='', wrong_authority=False):
        rows, raw = self.evidence() if evidence is None else evidence
        text = '\n'.join('[QUEUE_CHECK] ' + json.dumps(row) for row in rows) + '\n' + marker + '\n' + extra
        authority = '\n'.join('[CRAFT_UI_TEST] ' + name + ' ' + json.dumps(value) for name, value in raw)
        if self.selection['kind'] == 'mp':
            (self.root / 'server-launch.log').write_text('' if wrong_authority else authority)
            if wrong_authority:
                text += '\n' + authority
        else:
            text += '\n' + authority
        (self.root / 'client1-launch.log').write_text(text)
        return craft_ui.verify(self.root, self.selection, {})

    def test_sp_host_native_and_toolkit_accept_exact_receipts(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                with self.subTest(kind=kind, mode=mode):
                    craft_ui.validate(self.selection)
                    result = self.verify()
                    self.assertEqual([], result['issues'])
                    self.assertEqual(craft_ui.CASES, [row['case'] for row in result['outcomes']])
                    self.assertTrue(all(row['status'] == 'passed' for row in result['outcomes']))
                    self.assertEqual([craft_ui.COUNTS[case] for case in craft_ui.CASES],
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
        self.assertCountEqual([project / 'tests/native_queue' / name for name in paths],
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


if __name__ == '__main__':
    unittest.main()
