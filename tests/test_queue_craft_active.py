"""Active craft receipts distinguish native accounting from physical input removal."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import craft


class CraftActiveAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = dict(suite='craft', cases=list(craft.ACTIVE_CASES), kind='sp', mode='toolkit',
                              languages=['EN'], mods=list(craft.MODS), clients=1, options={})

    def evidence(self):
        enabled = self.selection['mode'] == 'toolkit'
        cases = self.selection['cases']
        rows = [dict(event='setup', cases=cases, expected=len(cases), queueEnabled=enabled, nativeDurations=True)]
        raw = []
        for n, case in enumerate(cases):
            late = case == 'late-input'
            tools = [101 + n * 10, 102 + n * 10]
            prep = dict(case=case, tools=tools, bags=[103 + n * 10, 104 + n * 10],
                        material=105 + n * 10, book=106 + n * 10, outputs=1,
                        materialCondition=10, materialUses=0, outputBaseline=[800],
                        sparePlanks=[dict(id=700, condition=8, uses=0)],
                        playerId=42 if self.selection['kind'] == 'mp' else -1,
                        toolMeta=[dict(id=id, kind=kind, condition=10, uses=0)
                                  for id, kind in zip(tools, ('Base.Hammer', 'Base.Saw'))])
            raw.append(('PREPARED', prep))
            # Native cancel may lose the independent reader; native completion can preserve it.
            tail = enabled or late
            receipt = dict(case=case, materialId=prep['material'], bookId=prep['book'], materialPresent=not late,
                           materialCondition=10, materialUses=0, removed=int(late), outputs=int(late),
                           accountedPlanks=int(late), outputIds=[900 + n] if late else [],
                           outputPlankCounts=[1] if late else [], sparePlanks=copy.deepcopy(prep['sparePlanks']),
                           toolsReturned=2 if tail else 0, tailRead=tail,
                           resources=[dict(meta, sourceCount=int(tail), rootCount=int(not tail)) for meta in prep['toolMeta']])
            if late:
                raw.append(('REMOVED', dict(case=case, materialId=prep['material'], removed=1, condition=10, uses=0)))
            raw.append(('ACTIVE_AUTHORITY', receipt))
            trace = []
            if self.selection['kind'] == 'mp':
                identity = dict(protocol=1, player=prep['playerId'], transaction=3 + n,
                                kind='ISHandcraftAction', token=f'12345678-1234-1234-1234-{n:012x}')
                trace = [dict(identity, state='started'), dict(identity, state='completed' if late else 'canceled')]
            row = dict({key: copy.deepcopy(value) for key, value in receipt.items() if key != 'case'},
                       event='case', id=case, status='passed' if tail else 'failed',
                       reason=None if tail else 'native-independent-tail-not-preserved',
                       toolIds=tools, pickupIds=sorted(tools), returnIds=sorted(tools) if tail else [],
                       pickupProgress=True, craftProgress=True, tailProgress=tail, returnsBeforeRead=tail,
                       interrupted=True, missingObserved=late, tokenCancelled=enabled and not late,
                       nativeDuration=150, authorityVerified=True, manualInputs=True, localDeferrals=0,
                       playerId=prep['playerId'], outcomeTrace=trace, interruptionProgress=.1,
                       sharedPerform=enabled and late, sharedComplete=enabled and late and self.selection['kind'] == 'sp')
            rows.append(row)
        rows.append(dict(event='complete', cases=cases, expected=len(cases), performed=len(cases),
                         failed=sum(row.get('status') == 'failed' for row in rows), skipped=0))
        rows = [dict(row, suite='craft', kind=self.selection['kind'], mode=self.selection['mode'], actor='client1') for row in rows]
        return rows, raw

    def verify(self, evidence=None, trace=None, extra='', authority_extra=''):
        rows, raw = evidence or self.evidence()
        if trace is None:
            trace = [entry for row in rows if row.get('event') == 'case' for entry in row['outcomeTrace']]
        authority = '\n'.join('[CRAFT_QUEUE_TEST] ' + kind + ' ' + json.dumps(value) for kind, value in raw)
        authority += '\n' + authority_extra
        text = '\n'.join('[QUEUE_CHECK] ' + json.dumps(row) for row in rows)
        text += '\n' + '\n'.join('[CRAFT_QUEUE_TEST] OUTCOME ' + json.dumps(entry) for entry in trace) + '\n' + extra
        if self.selection['kind'] == 'mp':
            (self.root / 'server-launch.log').write_text(authority)
        else:
            text += '\n' + authority
        (self.root / 'client1-launch.log').write_text(text)
        return craft.verify(self.root, self.selection, {})

    @staticmethod
    def row(evidence, case='late-input'):
        return next(row for row in evidence[0] if row.get('id') == case)

    @staticmethod
    def raw(evidence, kind='ACTIVE_AUTHORITY', case='late-input'):
        return next(value for name, value in evidence[1] if name == kind and value.get('case') == case)

    def test_active_subsets_sp_mp_and_native_observed_outcomes(self):
        for kind in ('sp', 'mp'):
            for mode in ('toolkit', 'native'):
                for cases in (craft.ACTIVE_CASES, ['cancel-craft'], ['late-input']):
                    self.selection.update(kind=kind, mode=mode, cases=list(cases))
                    craft.validate(self.selection)
                    expected = ['native-independent-tail-not-preserved'] if mode == 'native' and 'cancel-craft' in cases else []
                    with self.subTest(kind=kind, mode=mode, cases=cases):
                        result = self.verify()
                        self.assertEqual(result['issues'], expected)
                        self.assertEqual(result['outcomes'][-1]['status'], 'passed' if cases[-1] == 'late-input' or mode == 'toolkit' else 'failed')
                        self.assertNotIn('consumed', result['outcomes'][-1]['outcome'])

    def test_native_effect_difference_is_red_even_with_completed_ack(self):
        self.selection.update(kind='mp', mode='native', cases=['late-input'])
        evidence = self.evidence()
        for row in (self.row(evidence), self.raw(evidence)):
            row.update(outputs=0, accountedPlanks=0, outputIds=[], outputPlankCounts=[])
        self.row(evidence).update(status='failed', reason='native-craft-effect-differs')
        evidence[0][-1]['failed'] = 1
        result = self.verify(evidence)
        self.assertIn('native-craft-effect-differs', result['issues'])
        self.assertEqual(result['outcomes'][0]['status'], 'failed')

    def test_active_effects_boundaries_and_exact_types_are_required(self):
        changes = [('outputs', True), ('accountedPlanks', True), ('outputPlankCounts', [True]),
                   ('removed', False), ('materialPresent', True), ('craftProgress', False), ('pickupProgress', False),
                   ('manualInputs', False), ('missingObserved', False), ('interrupted', False),
                   ('nativeDuration', True), ('authorityVerified', 1), ('localDeferrals', True),
                   ('sharedPerform', False), ('sharedComplete', False), ('tokenCancelled', True),
                   ('tailRead', 1), ('tailProgress', False), ('returnsBeforeRead', False), ('consumed', 1)]
        for key, value in changes:
            evidence = self.evidence(); self.row(evidence)[key] = value
            with self.subTest(key=key):
                self.assertTrue(self.verify(evidence)['issues'])
        for key in ('sharedPerform', 'sharedComplete'):
            evidence = self.evidence(); self.row(evidence, 'cancel-craft')[key] = True
            self.assertTrue(self.verify(evidence)['issues'])
        self.selection['kind'] = 'mp'
        evidence = self.evidence(); self.row(evidence)['sharedComplete'] = True
        self.assertTrue(self.verify(evidence)['issues'])

    def test_intervention_requires_finite_early_native_progress(self):
        for value in (None, False, 0, -.1, .25001, float('nan'), float('inf'), '.1'):
            evidence = self.evidence(); self.row(evidence)['interruptionProgress'] = value
            with self.subTest(value=value):
                self.assertTrue(self.verify(evidence)['issues'])
        for value in (.000001, .25):
            evidence = self.evidence(); self.row(evidence)['interruptionProgress'] = value
            self.assertEqual(self.verify(evidence)['issues'], [])

    def test_new_output_ids_baseline_and_material_identity_are_exact(self):
        for target, key, value in [('row', 'outputIds', []), ('row', 'outputIds', [800]),
                                  ('row', 'outputIds', [700]), ('row', 'outputIds', [True]),
                                  ('row', 'outputIds', [111]), ('row', 'materialId', 999),
                                  ('row', 'bookId', True), ('row', 'playerId', 99),
                                  ('prep', 'outputBaseline', [800, 800]), ('prep', 'outputBaseline', [True]),
                                  ('prep', 'outputBaseline', []), ('prep', 'outputs', True),
                                  ('prep', 'playerId', 0), ('removal', 'materialId', 999),
                                  ('removal', 'removed', True), ('removal', 'condition', 0)]:
            evidence = self.evidence()
            row = self.row(evidence) if target == 'row' else self.raw(evidence, 'PREPARED' if target == 'prep' else 'REMOVED')
            row[key] = value
            with self.subTest(target=target, key=key, value=value):
                self.assertTrue(self.verify(evidence)['issues'])

    def test_spare_planks_cannot_be_substituted_mutated_or_hidden(self):
        for value in (None, {}, [dict(id=True, condition=8, uses=0)], [dict(id=700, condition=True, uses=0)],
                      [dict(id=700, condition=8, uses=-1)], [dict(id=700, condition=8, uses=0, extra=1)],
                      [dict(id=700, condition=8, uses=0)] * 2, [dict(id=800, condition=8, uses=0)],
                      [dict(id=115, condition=8, uses=0)], [dict(id=900, condition=8, uses=0), dict(id=700, condition=8, uses=0)]):
            evidence = self.evidence()
            for row in (self.raw(evidence, 'PREPARED'), self.raw(evidence), self.row(evidence)):
                row['sparePlanks'] = copy.deepcopy(value)
            with self.subTest(value=value):
                self.assertTrue(self.verify(evidence)['issues'])
        for target in ('row', 'receipt'):
            evidence = self.evidence()
            row = self.row(evidence) if target == 'row' else self.raw(evidence)
            row['sparePlanks'][0]['uses'] = 1
            self.assertTrue(self.verify(evidence)['issues'])

    def test_active_authority_is_independent_exact_and_canonical(self):
        for change in ('missing', 'duplicate', 'order', 'wrong-marker', 'extra-field', 'missing-field', 'disagree'):
            evidence = self.evidence()
            if change == 'missing': evidence[1].pop()
            elif change == 'duplicate': evidence[1].append(copy.deepcopy(evidence[1][-1]))
            elif change == 'order': evidence[1][-1], evidence[1][-2] = evidence[1][-2], evidence[1][-1]
            elif change == 'wrong-marker': evidence[1][-1] = ('ABORT_AUTHORITY', evidence[1][-1][1])
            elif change == 'extra-field': self.raw(evidence)['consumed'] = 1
            elif change == 'missing-field': del self.raw(evidence)['outputIds']
            else: self.raw(evidence)['accountedPlanks'] = 0
            with self.subTest(change=change):
                self.assertTrue(self.verify(evidence)['issues'])

    def test_native_state_requires_real_raw_receipts_and_mp_actor(self):
        self.selection['kind'] = 'mp'
        for trace in ([], [{}], [None], [dict(state='started')]):
            evidence = self.evidence(); self.row(evidence)['outcomeTrace'] = trace
            with self.subTest(trace=trace):
                self.assertTrue(self.verify(evidence, trace=[])['issues'])
        evidence = self.evidence()
        self.assertTrue(self.verify(evidence, trace=[])['issues'])
        trace = [entry for row in evidence[0] if row.get('event') == 'case' for entry in row['outcomeTrace']]
        self.assertTrue(self.verify(evidence, trace=trace + trace[-1:])['issues'])
        self.selection['kind'] = 'sp'
        evidence = self.evidence(); self.row(evidence)['outcomeTrace'] = [dict(state='started')]
        self.assertTrue(self.verify(evidence)['issues'])
        for value in ('null', '[]', 'false', 'bad-json'):
            with self.subTest(raw=value), self.assertRaises(ValueError):
                self.verify(extra='[CRAFT_QUEUE_TEST] OUTCOME ' + value)

    def test_native_state_fields_and_terminal_transaction_are_correlated(self):
        self.selection['kind'] = 'mp'
        changes = [('protocol', True), ('player', 99), ('player', True), ('transaction', 0),
                   ('transaction', 128), ('transaction', True), ('kind', 'ISReadABook'),
                   ('token', 'fake'), ('state', 'completed'), ('extra', 1)]
        for key, value in changes:
            evidence = self.evidence(); self.row(evidence)['outcomeTrace'][0][key] = value
            with self.subTest(key=key, value=value):
                self.assertTrue(self.verify(evidence)['issues'])
        for key, value in [('transaction', -12), ('token', 'ffffffff-1234-1234-1234-123456789abc'), ('state', 'canceled')]:
            evidence = self.evidence(); self.row(evidence)['outcomeTrace'][1][key] = value
            self.assertTrue(self.verify(evidence)['issues'])
        evidence = self.evidence()
        shared = self.row(evidence, 'cancel-craft')['outcomeTrace'][0]['token']
        for entry in self.row(evidence)['outcomeTrace']: entry['token'] = shared
        self.assertTrue(self.verify(evidence)['issues'])

    def test_active_tools_conserve_identity_metadata_and_endpoints(self):
        for key, value in [('toolIds', [111, 111]), ('pickupIds', [112, 111]), ('returnIds', []),
                           ('returnIds', [111, 999]), ('toolsReturned', True)]:
            evidence = self.evidence(); self.row(evidence)[key] = value
            with self.subTest(key=key): self.assertTrue(self.verify(evidence)['issues'])
        for key, value in [('id', 999), ('condition', 0), ('uses', True), ('sourceCount', True), ('rootCount', 1)]:
            evidence = self.evidence(); self.row(evidence)['resources'][0][key] = value
            with self.subTest(key=key): self.assertTrue(self.verify(evidence)['issues'])

    def test_native_failed_control_does_not_waive_errors_or_counts(self):
        self.selection['mode'] = 'native'
        for change in ('status', 'count', 'error'):
            evidence = self.evidence()
            if change == 'status': self.row(evidence, 'cancel-craft').update(status='passed', reason=None)
            elif change == 'count': evidence[0][-1]['failed'] = 0
            result = self.verify(evidence, authority_extra='[QUEUE_TEST] FAIL broken' if change == 'error' else '')
            with self.subTest(change=change): self.assertGreater(len(result['issues']), 1)


if __name__ == '__main__':
    unittest.main()
