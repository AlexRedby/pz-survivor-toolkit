"""Manual native craft aborts require correlated authority and exact resource conservation."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import craft


class CraftAbortAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = dict(suite='craft', cases=list(craft.CASES), kind='sp', mode='toolkit',
                              languages=['EN'], mods=list(craft.MODS), clients=1, options={})

    def evidence(self):
        enabled = self.selection['mode'] == 'toolkit'
        cases = self.selection['cases']
        rows = [dict(event='setup', cases=cases, expected=len(cases), queueEnabled=enabled, nativeDurations=True)]
        raw = []
        for n, case in enumerate(cases):
            tools = [101 + n * 10, 102 + n * 10]
            prep = dict(case=case, tools=tools, bags=[103 + n * 10, 104 + n * 10],
                        material=105 + n * 10, book=106 + n * 10, outputs=0, materialCondition=10, materialUses=0,
                        toolMeta=[dict(id=id, kind=kind, condition=10, uses=0)
                                  for id, kind in zip(tools, ('Base.Hammer', 'Base.Saw'))])
            if case == 'missing-input':
                prep['blocker'] = 107 + n * 10
            raw.append(('PREPARED', prep))
            if case == 'borrowed-tools':
                row = dict(event='case', id=case, status='passed', consumed=1, outputs=1, toolsReturned=2,
                           tailRead=True, returnsBeforeRead=enabled, sharedPerform=enabled,
                           sharedComplete=enabled and self.selection['kind'] == 'sp', localDeferrals=0,
                           nativeDuration=150, authorityVerified=True, toolIds=tools, returnOrder=tools.copy())
                raw.append(('AUTHORITY', craft.AUTHORITY))
            else:
                missing = case == 'missing-input'
                receipt = dict(case=case, materialId=prep['material'], bookId=prep['book'],
                               materialPresent=not missing, materialCondition=10, materialUses=0,
                               removed=int(missing), consumed=0, outputs=0, toolsReturned=2 if enabled else 0,
                               resources=[dict(meta, sourceCount=int(enabled), rootCount=int(not enabled))
                                          for meta in prep['toolMeta']], tailRead=enabled)
                if missing:
                    raw.append(('REMOVED', dict(case=case, materialId=prep['material'], removed=1, condition=10, uses=0)))
                raw.append(('ABORT_AUTHORITY', receipt))
                row = dict({key: copy.deepcopy(value) for key, value in receipt.items() if key != 'case'},
                           event='case', id=case, status='passed' if enabled else 'failed',
                           reason=None if enabled else 'native-independent-tail-not-preserved',
                           toolIds=tools, pickupIds=sorted(tools), returnIds=sorted(tools) if enabled else [],
                           pickupProgress=True, craftProgress=False, tailProgress=enabled, returnsBeforeRead=enabled,
                           interrupted=True, missingObserved=missing, tokenCancelled=enabled,
                           nativeDuration=150, authorityVerified=True, manualInputs=True, localDeferrals=0)
            rows.append(row)
        rows.append(dict(event='complete', cases=cases, expected=len(cases), performed=len(cases),
                         failed=sum(row.get('status') == 'failed' for row in rows), skipped=0))
        rows = [dict(row, suite='craft', kind=self.selection['kind'], mode=self.selection['mode'], actor='client1') for row in rows]
        return rows, raw

    def verify(self, evidence=None, extra='', authority_extra=''):
        rows, raw = evidence or self.evidence()
        authority = '\n'.join('[CRAFT_QUEUE_TEST] ' + kind + ' ' +
                              (value if kind == 'AUTHORITY' else json.dumps(value)) for kind, value in raw)
        authority += '\n' + authority_extra
        text = '\n'.join('[QUEUE_CHECK] ' + json.dumps(row) for row in rows) + '\n' + extra
        if self.selection['kind'] == 'mp':
            (self.root / 'server-launch.log').write_text(authority)
        else:
            text += '\n' + authority
        (self.root / 'client1-launch.log').write_text(text)
        return craft.verify(self.root, self.selection, {})

    @staticmethod
    def row(evidence, case='missing-input'):
        return next(row for row in evidence[0] if row.get('id') == case)

    @staticmethod
    def raw(evidence, kind='ABORT_AUTHORITY', case='missing-input'):
        return next(value for name, value in evidence[1] if name == kind and value.get('case') == case)

    def test_registered_ordered_subsets_and_old_positive_are_supported(self):
        self.assertEqual([case['id'] for case in craft.definitions()['craft']['cases']], craft.CASES)
        for cases in ([case] for case in craft.CASES):
            self.selection['cases'] = cases
            craft.validate(self.selection)
            self.assertEqual(self.verify()['issues'], [])
        for cases in ([], list(reversed(craft.CASES)), ['cancel-pickup'] * 2, ['unknown']):
            with self.subTest(cases=cases), self.assertRaises(ValueError):
                craft.validate(dict(self.selection, cases=cases))

    def test_toolkit_sp_mp_and_native_observed_failures(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                result = self.verify()
                with self.subTest(kind=kind, mode=mode):
                    self.assertEqual(result['issues'], ['native-independent-tail-not-preserved'] * 2 if mode == 'native' else [])
                    self.assertEqual([row['status'] for row in result['outcomes']],
                                     ['passed', 'failed', 'failed'] if mode == 'native' else ['passed'] * 3)
                    self.assertEqual(result['outcomes'][0]['reason'], '')

    def test_native_cleanup_endpoints_and_returns_remain_observed(self):
        self.selection.update(mode='native', cases=['cancel-pickup'])
        for count in (0, 1, 2):
            evidence = self.evidence()
            row, receipt = self.row(evidence, 'cancel-pickup'), self.raw(evidence, case='cancel-pickup')
            for value in (row, receipt):
                value['toolsReturned'] = count
                for index, resource in enumerate(value['resources']):
                    resource.update(sourceCount=int(index < count), rootCount=int(index >= count))
            row['returnIds'] = row['toolIds'][:count]
            result = self.verify(evidence)
            self.assertEqual(result['issues'], ['native-independent-tail-not-preserved'])
            self.assertEqual(result['outcomes'][0]['outcome']['toolsReturned'], count)

    def test_native_success_and_order_failure_are_derived_from_receipt(self):
        self.selection.update(mode='native', cases=['missing-input'])
        for before in (False, True):
            evidence = self.evidence()
            row, receipt = self.row(evidence), self.raw(evidence)
            for value in (row, receipt):
                value.update(tailRead=True, toolsReturned=2)
                for resource in value['resources']:
                    resource.update(sourceCount=1, rootCount=0)
            row.update(tailProgress=True, returnsBeforeRead=before, returnIds=sorted(row['toolIds']),
                       status='passed' if before else 'failed', reason=None if before else 'native-returns-not-before-tail')
            evidence[0][-1]['failed'] = int(not before)
            self.assertEqual(self.verify(evidence)['issues'], [] if before else ['native-returns-not-before-tail'])

    def test_abort_effects_progress_and_strict_types_cannot_be_forged(self):
        changes = [('consumed', 1), ('outputs', 1), ('removed', False), ('materialPresent', True),
                   ('pickupProgress', False), ('craftProgress', True), ('interrupted', False), ('missingObserved', False),
                   ('tailProgress', False), ('returnsBeforeRead', False), ('tokenCancelled', False),
                   ('nativeDuration', True), ('authorityVerified', 1), ('manualInputs', False), ('localDeferrals', True),
                   ('toolsReturned', True), ('tailRead', 1), ('status', 'skipped'), ('reason', 'waived')]
        for key, value in changes:
            evidence = self.evidence();self.row(evidence)[key] = value
            with self.subTest(key=key):
                self.assertTrue(self.verify(evidence)['issues'])
        self.selection['mode'] = 'native'
        for key, value in [('tokenCancelled', 0), ('tailRead', 0), ('returnsBeforeRead', None), ('tailProgress', False)]:
            evidence = self.evidence();self.row(evidence)[key] = value
            if key == 'tailProgress':
                self.row(evidence)[key] = 0
            with self.subTest(native=key):
                self.assertGreater(len(self.verify(evidence)['issues']), 2)

    def test_exact_ids_and_metadata_are_correlated_to_authority(self):
        for target, key, value in [('row', 'materialId', 999), ('row', 'bookId', True), ('row', 'materialCondition', 0),
                                   ('row', 'materialUses', 1), ('prep', 'materialCondition', False),
                                   ('prep', 'outputs', -1), ('prep', 'blocker', 101),
                                   ('receipt', 'tailRead', False), ('removal', 'materialId', 999),
                                   ('removal', 'condition', 0), ('removal', 'uses', True), ('removal', 'removed', 0)]:
            evidence = self.evidence()
            target_value = self.row(evidence) if target == 'row' else self.raw(evidence, {
                'prep': 'PREPARED', 'receipt': 'ABORT_AUTHORITY', 'removal': 'REMOVED'}[target])
            target_value[key] = value
            with self.subTest(target=target, key=key):
                self.assertTrue(self.verify(evidence)['issues'])
        for field in ('id', 'kind', 'condition', 'uses'):
            evidence = self.evidence()
            self.raw(evidence, 'PREPARED')['toolMeta'][0][field] = 'foreign'
            with self.subTest(meta=field):
                self.assertTrue(self.verify(evidence)['issues'])

    def test_tool_identity_conservation_and_endpoints_are_strict(self):
        for key, values in [('toolIds', [None, [1, 1], [True, 122], [122, 121]]),
                            ('pickupIds', [[], [121], [121, 121], [122, 121], [121.0, 122.0]]),
                            ('returnIds', [None, [], [121], [121, 121], [121, 999], [122, 121]])]:
            for value in values:
                evidence = self.evidence();self.row(evidence)[key] = value
                with self.subTest(key=key, value=value):
                    self.assertTrue(self.verify(evidence)['issues'])
        for key, value in [('id', 999), ('kind', 'Base.Axe'), ('condition', 0), ('uses', True),
                           ('sourceCount', True), ('sourceCount', 0), ('sourceCount', 2), ('rootCount', 1)]:
            evidence = self.evidence();self.row(evidence)['resources'][0][key] = value
            with self.subTest(resource=key, value=value):
                self.assertTrue(self.verify(evidence)['issues'])
        for resources in (None, [], [{}], [{}, {}], 'invalid'):
            evidence = self.evidence();self.row(evidence)['resources'] = resources
            with self.subTest(resources=resources):
                self.assertTrue(self.verify(evidence)['issues'])

    def test_authority_markers_are_unique_and_canonical(self):
        for change in ('missing', 'duplicate', 'reorder', 'wrong-case', 'extra-removal'):
            evidence = self.evidence()
            if change == 'missing':
                evidence[1].pop()
            elif change == 'duplicate':
                evidence[1].append(copy.deepcopy(evidence[1][-1]))
            elif change == 'reorder':
                evidence[1][-1], evidence[1][-2] = evidence[1][-2], evidence[1][-1]
            elif change == 'wrong-case':
                self.raw(evidence)['case'] = 'cancel-pickup'
            else:
                evidence[1].append(('REMOVED', dict(case='cancel-pickup')))
            with self.subTest(change=change):
                self.assertTrue(self.verify(evidence)['issues'])
        for payload in ('[]', 'null', 'false', 'not-json'):
            with self.subTest(payload=payload), self.assertRaises(ValueError):
                self.verify(authority_extra='[CRAFT_QUEUE_TEST] PREPARED ' + payload)

    def test_native_failures_never_waive_bad_status_counters_or_fixture_errors(self):
        self.selection['mode'] = 'native'
        for target in ('status', 'reason', 'counter', 'error'):
            evidence = self.evidence()
            if target == 'status':
                self.row(evidence)['status'] = 'passed'
            elif target == 'reason':
                self.row(evidence)['reason'] = None
            elif target == 'counter':
                evidence[0][-1]['failed'] = 0
            result = self.verify(evidence, authority_extra='[QUEUE_TEST] FAIL native craft' if target == 'error' else '')
            with self.subTest(target=target):
                self.assertGreater(len(result['issues']), 2)
                self.assertEqual(result['outcomes'][0]['status'], 'failed')

    def test_identity_reuse_between_cases_and_wrong_event_context_are_rejected(self):
        evidence = self.evidence();self.raw(evidence, 'PREPARED')['book'] = 106
        self.assertTrue(self.verify(evidence)['issues'])
        for key, value in [('suite', 'fire'), ('kind', 'mp'), ('mode', 'native'), ('actor', 'client2')]:
            evidence = self.evidence();self.row(evidence)[key] = value
            with self.subTest(context=key):
                self.assertTrue(self.verify(evidence)['issues'])


if __name__ == '__main__':
    unittest.main()
