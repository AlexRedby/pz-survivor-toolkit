"""Ignition receipts prove exact effects, trial coverage and native queue outcomes."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks.adapters import fire, fire_ignition as ignition


class FireIgnitionVerifierTests(unittest.TestCase):
    def setUp(self):
        self.selection = {'kind': 'sp', 'mode': 'toolkit'}

    def evidence(self, case='literature', trials=1):
        classes = {'literature': ('ISLightFromLiterature', 100), 'petrol': ('ISLightFromPetrol', 20),
                   'last-match': ('ISLightFromPetrol', 20), 'kindle-retry': ('ISLightFromKindle', 1500),
                   'bbq-fuel': ('ISBBQAddFuel', 100), 'bbq-literature': ('ISBBQLightFromLiterature', 100),
                   'bbq-petrol': ('ISBBQLightFromPetrol', 20)}
        action, duration = classes[case]
        def resource(role, kind, uses=0, amount=0, debit=0, fluid=0, consumed=False, optional=False,
                     returned=False, source='crate'):
            return dict(role=role, kind=kind, condition=100, initialUses=uses, initialAmount=amount,
                        expectedUse=debit, expectedAmountDelta=fluid, consumed=consumed,
                        optionalConsume=optional, returnToSource=returned, source=source)
        if case == 'bbq-fuel':
            resources = [resource('fuel', 'Base.Log', consumed=True)]
        elif case == 'kindle-retry':
            resources = [resource('plank', 'Base.PercedWood', returned=True),
                         resource('stick', 'Base.WoodenStick2', optional=True, returned=True),
                         resource('reserve1', 'Base.WoodenStick2', optional=True, source='root')]
        elif case in ('literature', 'bbq-literature'):
            resources = [resource('tinder', 'Base.SheetPaper2', consumed=True),
                         resource('starter', 'Base.Matches', uses=2, debit=1, returned=True)]
        else:
            last = case in ('last-match', 'bbq-petrol')
            resources = [resource('starter', 'Base.Matches', uses=1 if last else 2, debit=1,
                                  consumed=last, returned=True),
                         resource('petrol', 'Base.PetrolCan', amount=2, fluid=0.1)]
        prepared, receipts = [], []
        lit = case != 'bbq-fuel'
        for trial in range(1, trials + 1):
            specs = copy.deepcopy(resources)
            for n, row in enumerate(specs): row['id'] = trial * 100 + n
            initial = 360 if lit else 0
            effect = initial + (1.5 if case == 'literature' else 1 if case == 'bbq-literature' else 360 if not lit else 0)
            prep = dict(case=case, trial=trial, book=trial * 100 + 90, actionType=action, nativeDuration=duration,
                        x=20, y=30, z=0, objectIndex=2, crateX=20, crateY=30, crateZ=0, crateIndex=1,
                        initialFuel=initial, expectedFuel=effect, resources=specs)
            actual = []
            for spec in specs:
                gone = spec['consumed'] or case == 'kindle-retry' and spec['role'] == 'stick'
                returned = spec['returnToSource'] and not gone
                actual.append(dict(role=spec['role'], id=spec['id'], kind=spec['kind'],
                    sourceCount=int(returned), rootCount=int(not gone and not returned), condition=100,
                    uses=spec['initialUses'] - spec['expectedUse'], amount=spec['initialAmount'] - spec['expectedAmountDelta'],
                    consumed=gone))
            receipt = dict(case=case, trial=trial, bookId=prep['book'], resources=actual,
                           lit=lit, effectFuel=effect, fuel=effect - 1 if lit else effect, tailRead=True)
            prepared.append(prep); receipts.append(receipt)
        result = dict(receipts[-1], id=case, actionType=action, nativeDuration=duration,
                      attempts=2 if case == 'kindle-retry' else 1, expanded=True, actionProgress=True, tokenCancelled=False,
                      pickupProgress=True, tailProgress=True, returnedBeforeTail=True,
                      retryBeforeReturns=case == 'kindle-retry', status='passed', reason=None,
                      pickupIds=[row['id'] for row in prepared[-1]['resources'] if row['source'] == 'crate'],
                      returnIds=[row['id'] for row in receipts[-1]['resources'] if row['sourceCount']])
        del result['case']
        return copy.deepcopy((result, prepared, receipts))

    def verify(self, evidence, case=None):
        result, prepared, receipts = evidence
        return ignition.verify_case(case or result['id'], self.selection, result, prepared, receipts)

    def test_every_profile_passes_sp_and_host_in_both_modes(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                for case in ignition.CASES:
                    with self.subTest(kind=kind, mode=mode, case=case):
                        issues, outcome, reason = self.verify(self.evidence(case, 2 if case == 'kindle-retry' else 1))
                        self.assertEqual(issues, [])
                        self.assertIsNone(reason)
                        self.assertEqual(outcome['actor'], 'client1')
                        self.assertEqual(outcome['case'], case)
                        self.assertEqual(outcome['outcome']['nativeDuration'], 1500 if case == 'kindle-retry' else 20 if case in
                                         ('petrol', 'last-match', 'bbq-petrol') else 100)

    def test_native_real_failures_have_ordered_per_case_reasons(self):
        self.selection['mode'] = 'native'
        for failed, reason in ((('tail', 'return', 'retry'), 'native-independent-tail-not-preserved'),
                               (('return', 'retry'), 'native-returns-not-before-tail'),
                               (('retry',), 'native-retry-not-before-returns')):
            evidence = self.evidence('kindle-retry', 2)
            result, _, receipts = evidence
            if 'tail' in failed:
                result['tailRead'] = receipts[-1]['tailRead'] = False;result['tailProgress'] = False
            if 'return' in failed: result['returnedBeforeTail'] = False
            if 'retry' in failed: result['retryBeforeReturns'] = False
            result.update(status='failed', reason=reason)
            with self.subTest(failed=failed):
                issues, _, actual = self.verify(evidence)
                self.assertEqual(issues, [])
                self.assertEqual(actual, reason)
        evidence = self.evidence('kindle-retry', 2)
        evidence[2][0]['tailRead'] = False
        evidence[0].update(status='failed', reason='native-independent-tail-not-preserved')
        self.assertEqual(self.verify(evidence)[::2], ([], 'native-independent-tail-not-preserved'))

    def test_native_conserved_root_endpoint_and_return_subset_are_observable(self):
        self.selection['mode'] = 'native'
        evidence = self.evidence('literature')
        result, _, receipts = evidence
        for resource in (result['resources'][1], receipts[-1]['resources'][1]):
            resource.update(sourceCount=0, rootCount=1)
        result.update(returnIds=[], returnedBeforeTail=False, status='failed', reason='native-returns-not-before-tail')
        self.assertEqual(self.verify(evidence)[::2], ([], 'native-returns-not-before-tail'))
        self.selection['mode'] = 'toolkit'
        self.assertTrue(self.verify(evidence)[0])

    def test_trial_sequence_limit_and_native_retry_evidence_are_required(self):
        original = self.evidence('kindle-retry', 2)
        for change in ('prep-missing', 'receipt-duplicate', 'reordered', 'trial-bool', 'too-many', 'no-retry'):
            evidence = copy.deepcopy(original)
            if change == 'prep-missing': evidence[1].pop(0)
            elif change == 'receipt-duplicate': evidence[2].append(evidence[2][-1])
            elif change == 'reordered': evidence[1].reverse()
            elif change == 'trial-bool': evidence[2][0]['trial'] = True
            elif change == 'too-many': evidence[0]['trial'] = 9
            else: evidence[0]['attempts'] = 1
            with self.subTest(change=change): self.assertTrue(self.verify(evidence)[0])
        evidence = self.evidence('petrol', 2)
        self.assertTrue(self.verify(evidence)[0])

    def test_consumption_identity_duplicates_and_float_debits_remain_strict(self):
        for key, value in (('id', True), ('id', [100]), ('kind', 'Base.Lighter'), ('sourceCount', 2),
                           ('rootCount', True), ('condition', 99), ('consumed', True), ('uses', 2), ('amount', 1.8)):
            evidence = self.evidence('petrol')
            evidence[2][0]['resources'][1][key] = value
            with self.subTest(key=key, value=value): self.assertTrue(self.verify(evidence)[0])
        for target in (0, 1, 2):
            evidence = self.evidence('literature')
            resources = evidence[0]['resources'] if target == 0 else evidence[target][0]['resources']
            resources.append(copy.deepcopy(resources[-1]))
            self.assertTrue(self.verify(evidence)[0])
        evidence = self.evidence('petrol')
        evidence[0]['resources'][1]['amount'] += 0.0000001
        self.assertEqual(self.verify(evidence)[0], [])
        evidence[0]['resources'][1]['amount'] += 0.00001
        self.assertTrue(self.verify(evidence)[0])

    def test_missing_and_consumed_items_never_gain_native_return_evidence(self):
        for case in ('last-match', 'bbq-petrol', 'kindle-retry'):
            evidence = self.evidence(case)
            evidence[0]['returnIds'].append(evidence[1][-1]['resources'][0 if case != 'kindle-retry' else 1]['id'])
            with self.subTest(case=case): self.assertTrue(self.verify(evidence)[0])
        for key, values in (('pickupIds', []), ('pickupIds', [True, 101]), ('returnIds', [101, 101]),
                            ('returnIds', [100]), ('returnIds', [101.0])):
            evidence = self.evidence('literature');evidence[0][key] = values
            with self.subTest(key=key, values=values): self.assertTrue(self.verify(evidence)[0])

    def test_only_kindle_sticks_may_be_optionally_consumed(self):
        evidence = self.evidence('kindle-retry')
        evidence[1][0]['resources'][0]['optionalConsume'] = True
        self.assertTrue(self.verify(evidence)[0])
        for case in ('literature', 'petrol'):
            evidence = self.evidence(case)
            evidence[1][0]['resources'][0]['optionalConsume'] = True
            self.assertTrue(self.verify(evidence)[0])
        evidence = self.evidence('kindle-retry')
        for row in (evidence[0]['resources'][1], evidence[2][0]['resources'][1]):
            row.update(consumed=False, sourceCount=1)
        evidence[0]['returnIds'].append(evidence[0]['resources'][1]['id'])
        self.assertEqual(self.verify(evidence)[0], [])

    def exhausted_kindling(self):
        evidence = self.evidence('kindle-retry')
        result, prepared, receipts = evidence
        for row in receipts[0]['resources']:
            if row['role'] in ('stick', 'reserve1'):
                row.update(sourceCount=0, rootCount=0, consumed=True)
        receipts[0].update(lit=False, effectFuel=prepared[0]['initialFuel'], fuel=prepared[0]['initialFuel'])
        result.update(resources=copy.deepcopy(receipts[0]['resources']), lit=False,
                      effectFuel=receipts[0]['effectFuel'], fuel=receipts[0]['fuel'])
        return evidence

    def test_exhausted_kindling_proves_retry_returns_and_reading_without_fire(self):
        issues, outcome, reason = self.verify(self.exhausted_kindling())
        self.assertEqual(issues, [])
        self.assertIsNone(reason)
        self.assertFalse(outcome['outcome']['lit'])
        self.assertEqual(outcome['outcome']['attempts'], 2)
        self.assertTrue(outcome['outcome']['tailRead'])

    def test_unlit_kindling_rejects_surviving_stick_changed_fuel_or_missing_retry(self):
        for change in ('survivor', 'effect', 'fuel', 'expected', 'attempts', 'return', 'tail'):
            evidence = self.exhausted_kindling()
            result, prepared, receipts = evidence
            if change == 'survivor':
                for rows in (result['resources'], receipts[0]['resources']):
                    rows[-1].update(consumed=False, rootCount=1)
            elif change in ('effect', 'fuel'):
                key = 'effectFuel' if change == 'effect' else 'fuel'
                result[key] = receipts[0][key] = 359
            elif change == 'expected': prepared[0]['expectedFuel'] = 359
            elif change == 'attempts': result['attempts'] = 1
            elif change == 'return': result['returnIds'] = []
            else: result['tailRead'] = receipts[0]['tailRead'] = False
            with self.subTest(change=change): self.assertTrue(self.verify(evidence)[0])
        self.selection['mode'] = 'native'
        evidence = self.exhausted_kindling()
        evidence[0].update(tailRead=False, tailProgress=False, status='failed', reason='native-independent-tail-not-preserved')
        evidence[2][0]['tailRead'] = False
        self.assertEqual(self.verify(evidence)[::2], ([], 'native-independent-tail-not-preserved'))

    def test_client_cannot_change_last_receipt_or_claim_a_false_status(self):
        for key, value in (('bookId', True), ('lit', False), ('tailRead', False), ('effectFuel', 999),
                           ('fuel', 999), ('nativeDuration', True), ('actionType', 'ISBBQToggle'),
                           ('expanded', 1), ('actionProgress', False), ('tokenCancelled', True), ('pickupProgress', False),
                           ('tailProgress', False), ('returnedBeforeTail', False), ('status', 'failed'),
                           ('reason', 'native-independent-tail-not-preserved')):
            evidence = self.evidence('literature');evidence[0][key] = value
            with self.subTest(key=key): self.assertTrue(self.verify(evidence)[0])
        evidence = self.evidence('kindle-retry');evidence[0]['retryBeforeReturns'] = False
        self.assertTrue(self.verify(evidence)[0])

    def test_world_profile_and_first_effect_are_authoritative(self):
        for key, value in (('crateIndex', 2), ('objectIndex', True), ('crateX', 21), ('book', 100),
                           ('nativeDuration', 1), ('initialFuel', -1), ('expectedFuel', float('nan'))):
            evidence = self.evidence('petrol');evidence[1][0][key] = value
            with self.subTest(key=key): self.assertTrue(self.verify(evidence)[0])
        for case in ('literature', 'bbq-fuel'):
            for key, value in (('lit', case == 'bbq-fuel'), ('effectFuel', 999), ('fuel', 0), ('fuel', 999)):
                evidence = self.evidence(case);evidence[2][0][key] = value
                with self.subTest(case=case, key=key): self.assertTrue(self.verify(evidence)[0])
        evidence = self.evidence('last-match');evidence[1][0]['resources'][0]['initialUses'] = 2
        self.assertTrue(self.verify(evidence)[0])

    def test_invalid_envelopes_fail_without_exceptions(self):
        result, prepared, receipts = self.evidence()
        for args in ((None, prepared, receipts), (result, None, receipts), (result, [None], receipts),
                     (result, prepared, [{}]), (dict(result, trial=True), prepared, receipts)):
            self.assertTrue(ignition.verify_case('literature', self.selection, *args)[0])
        self.assertTrue(ignition.verify_case('unknown', self.selection, result, prepared, receipts)[0])

    def test_malformed_trial_reaches_the_fire_report_as_issues(self):
        result, prepared, receipts = self.evidence()
        result['trial'] = True
        selection = dict(self.selection, cases=['literature'])
        context = dict(suite='fire', kind='sp', mode='toolkit', actor='client1')
        rows = [dict(context, event='setup', cases=['literature'], expected=1, queueEnabled=True, nativeDurations=True),
                dict(result, **context, event='case'),
                dict(context, event='complete', cases=['literature'], expected=1, performed=1, failed=0, skipped=0)]
        text = '\n'.join('[QUEUE_CHECK] ' + json.dumps(row) for row in rows)
        text += '\n' + '\n'.join(marker + json.dumps(row) for marker, values in
            (('[FIRE_TEST] PREPARED ', prepared), ('[FIRE_TEST] AUTHORITY ', receipts)) for row in values)
        with tempfile.TemporaryDirectory() as temporary:
            (Path(temporary) / 'client1-launch.log').write_text(text)
            report = fire.verify(temporary, selection, {})
        self.assertIn('Ignition final trial is invalid', report['issues'])
        self.assertEqual(report['outcomes'][0]['case'], 'literature')
        self.assertEqual(report['outcomes'][0]['status'], 'failed')


if __name__ == '__main__':
    unittest.main()
