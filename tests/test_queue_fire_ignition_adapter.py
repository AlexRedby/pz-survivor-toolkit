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
        self.selection = {'kind': 'sp', 'mode': 'toolkit', 'mods': ['P4TidyUpMeister']}

    def evidence(self, case='literature', trials=1):
        classes = {'literature': ('ISLightFromLiterature', 100), 'petrol': ('ISLightFromPetrol', 20),
                   'last-match': ('ISLightFromPetrol', 20), 'kindle-retry': ('ISLightFromKindle', 1500),
                   'bbq-fuel': ('ISBBQAddFuel', 100), 'bbq-literature': ('ISBBQLightFromLiterature', 100),
                   'bbq-petrol': ('ISBBQLightFromPetrol', 20), 'bbq-kindle': ('ISBBQLightFromKindle', 1500),
                   'fireplace-fuel': ('ISBBQAddFuel', 100), 'fireplace-literature': ('ISBBQLightFromLiterature', 100),
                   'fireplace-petrol': ('ISBBQLightFromPetrol', 20), 'fireplace-kindle': ('ISBBQLightFromKindle', 1500)}
        action, duration = classes[case]
        def resource(role, kind, uses=0, amount=0, debit=0, fluid=0, consumed=False, optional=False,
                     returned=False, source='crate'):
            return dict(role=role, kind=kind, condition=100, initialUses=uses, initialAmount=amount,
                        expectedUse=debit, expectedAmountDelta=fluid, consumed=consumed,
                        optionalConsume=optional, returnToSource=returned, source=source)
        if case in ('bbq-fuel', 'fireplace-fuel'):
            resources = [resource('fuel', 'Base.Log', consumed=True)]
        elif case in ('kindle-retry', 'bbq-kindle', 'fireplace-kindle'):
            resources = [resource('plank', 'Base.PercedWood', returned=True),
                         resource('stick', 'Base.WoodenStick2', optional=True, returned=True)]
            if case == 'kindle-retry':
                resources.append(resource('reserve1', 'Base.WoodenStick2', optional=True, source='root'))
        elif case in ('literature', 'bbq-literature', 'fireplace-literature'):
            resources = [resource('tinder', 'Base.SheetPaper2', consumed=True),
                         resource('starter', 'Base.Matches', uses=2, debit=1, returned=True)]
        else:
            last = case in ('last-match', 'bbq-petrol', 'fireplace-petrol')
            resources = [resource('starter', 'Base.Matches', uses=1 if last else 2, debit=1,
                                  consumed=last, returned=True),
                         resource('petrol', 'Base.PetrolCan', amount=2, fluid=0.1)]
        prepared, receipts = [], []
        lit = case not in ('bbq-fuel', 'fireplace-fuel')
        target = 'fireplace' if case.startswith('fireplace-') else 'bbq' if case.startswith('bbq-') else 'campfire'
        for trial in range(1, trials + 1):
            specs = copy.deepcopy(resources)
            for n, row in enumerate(specs): row['id'] = trial * 100 + n
            initial = 360 if lit else 0
            effect = initial + (1.5 if case == 'literature' else 1 if case in ('bbq-literature', 'fireplace-literature') else 360 if not lit else 0)
            prep = dict(case=case, trial=trial, targetKind=target, book=trial * 100 + 90, actionType=action, nativeDuration=duration,
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
            receipt = dict(case=case, trial=trial, targetKind=target, bookId=prep['book'], resources=actual,
                           lit=lit, effectFuel=effect, fuel=effect - 1 if lit else effect, tailRead=True, tidyReturnIds=[])
            prepared.append(prep); receipts.append(receipt)
        result = dict(receipts[-1], id=case, actionType=action, nativeDuration=duration,
                      attempts=2 if case == 'kindle-retry' else 1, expanded=True, actionProgress=True, tokenCancelled=False,
                      pickupProgress=True, tailProgress=True, returnedBeforeTail=True,
                      petrolBeforeTail=True, tidyReturns=[],
                      retryBeforeReturns=case == 'kindle-retry', status='passed', reason=None,
                      pickupIds=[row['id'] for row in prepared[-1]['resources'] if row['source'] == 'crate'],
                      returnIds=[row['id'] for row in receipts[-1]['resources'] if row['sourceCount']])
        del result['case']
        if case == 'kindle-retry':
            count = result['attempts'] if self.selection['mode'] == 'toolkit' else 0
            result['nativeCompletion'] = dict(perform=count, complete=count if self.selection['kind'] == 'sp' else 0, flush=count)
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
                        self.assertEqual(outcome['outcome']['targetKind'], self.evidence(case)[0]['targetKind'])
                        self.assertEqual(outcome['outcome']['nativeDuration'], 1500 if case in
                                         ('kindle-retry', 'bbq-kindle', 'fireplace-kindle') else 20 if case in
                                         ('petrol', 'last-match', 'bbq-petrol', 'fireplace-petrol') else 100)

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

    def test_kindle_completion_requires_exact_typed_phase_counts_in_sp_and_host(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                evidence = self.evidence('kindle-retry', 2)
                expected = evidence[0]['nativeCompletion']
                self.assertEqual(self.verify(evidence)[1]['outcome']['nativeCompletion'], expected)
                for phase in ('perform', 'complete', 'flush'):
                    for value in (True, 2.0, '2', None, -1, expected[phase] + 1):
                        mutated = copy.deepcopy(evidence)
                        mutated[0]['nativeCompletion'][phase] = value
                        with self.subTest(kind=kind, mode=mode, phase=phase, value=value):
                            self.assertIn('Ignition native Kindle completion phases differ', self.verify(mutated)[0])
                    mutated = copy.deepcopy(evidence)
                    del mutated[0]['nativeCompletion'][phase]
                    self.assertTrue(self.verify(mutated)[0])
                for value in (None, [], True, dict(expected, stop=0)):
                    mutated = copy.deepcopy(evidence)
                    mutated[0]['nativeCompletion'] = value
                    self.assertTrue(self.verify(mutated)[0])
                mutated = copy.deepcopy(evidence)
                del mutated[0]['nativeCompletion']
                self.assertTrue(self.verify(mutated)[0])

    def test_kindle_completion_cannot_swap_sp_and_client_phases_or_claim_an_unflushed_attempt(self):
        for kind, phases in (('sp', dict(perform=2, complete=0, flush=2)),
                             ('mp', dict(perform=2, complete=2, flush=2)),
                             ('sp', dict(perform=2, complete=2, flush=1)),
                             ('mp', dict(perform=1, complete=0, flush=2))):
            self.selection['kind'] = kind
            evidence = self.evidence('kindle-retry')
            evidence[0]['nativeCompletion'] = phases
            with self.subTest(kind=kind, phases=phases): self.assertTrue(self.verify(evidence)[0])

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

    def test_native_unfinished_unlit_retry_preserves_failed_control_and_exact_fuel(self):
        self.selection.update(mode='native', kind='mp')
        evidence = self.exhausted_kindling()
        result, _, receipts = evidence
        for rows in (result['resources'], receipts[0]['resources']):
            rows[-1].update(consumed=False, rootCount=1)
        result.update(tokenCancelled=True, retryBeforeReturns=False,
                      status='failed', reason='native-retry-not-before-returns')
        issues, outcome, reason = self.verify(evidence)
        self.assertEqual(issues, [])
        self.assertEqual(reason, 'native-retry-not-before-returns')
        self.assertFalse(outcome['outcome']['lit'])
        self.assertFalse(outcome['outcome']['resources'][-1]['consumed'])
        self.assertTrue(outcome['outcome']['tokenCancelled'])
        for key in ('effectFuel', 'fuel'):
            mutated = copy.deepcopy(evidence)
            mutated[0][key] = mutated[2][0][key] = 359
            with self.subTest(key=key): self.assertTrue(self.verify(mutated)[0])
        mutated = copy.deepcopy(evidence)
        mutated[0].update(retryBeforeReturns=True, status='passed', reason=None)
        self.assertIn('Unfinished native Kindle trial lacks a functional failure', self.verify(mutated)[0])
        mutated = copy.deepcopy(evidence)
        mutated[2][0]['resources'][-1]['rootCount'] = 0
        self.assertTrue(self.verify(mutated)[0])
        self.selection['mode'] = 'toolkit'
        evidence[0].update(nativeCompletion=dict(perform=2, complete=0, flush=2),
                           tokenCancelled=False, retryBeforeReturns=True, status='passed', reason=None)
        self.assertIn('Unlit Kindle trial did not consume every optional stick', self.verify(evidence)[0])

    def single_kindling(self, case, lit=False, broken=False, cancelled=False):
        evidence = self.evidence(case)
        result, prepared, receipts = evidence
        if broken:
            receipts[0]['resources'][1].update(sourceCount=0, rootCount=0, consumed=True)
        initial = prepared[0]['initialFuel']
        receipts[0].update(lit=lit, effectFuel=initial, fuel=initial - 1 if lit else initial)
        result.update(receipts[0], tokenCancelled=cancelled,
                      returnIds=[row['id'] for row in receipts[0]['resources'] if row['sourceCount']])
        result['resources'] = copy.deepcopy(receipts[0]['resources'])
        result.pop('case')
        return evidence

    def test_single_kindle_accepts_native_terminal_outcomes_without_claiming_ignition(self):
        for case in ('bbq-kindle', 'fireplace-kindle'):
            for kind in ('sp', 'mp'):
                for mode in ('native', 'toolkit'):
                    self.selection.update(kind=kind, mode=mode)
                    for lit, broken in ((True, False), (False, True), (False, False)):
                        with self.subTest(case=case, kind=kind, mode=mode, lit=lit, broken=broken):
                            issues, outcome, reason = self.verify(self.single_kindling(case, lit, broken))
                            self.assertEqual(issues, [])
                            self.assertIsNone(reason)
                            self.assertIs(outcome['outcome']['lit'], lit)
                            self.assertEqual(outcome['outcome']['attempts'], 1)
                            self.assertEqual(outcome['outcome']['targetKind'], case.split('-')[0])

    def test_single_kindle_native_sp_stop_is_allowed_only_after_lighting_or_breakage(self):
        for case in ('bbq-kindle', 'fireplace-kindle'):
            for kind in ('sp', 'mp'):
                self.selection['kind'] = kind
                for lit, broken in ((True, False), (False, True), (False, False)):
                    evidence = self.single_kindling(case, lit, broken, cancelled=True)
                    with self.subTest(case=case, kind=kind, lit=lit, broken=broken):
                        self.assertEqual(not self.verify(evidence)[0], kind == 'sp' and (lit or broken))
            self.selection['kind'] = 'sp'
            for value in (1, 'true', None):
                evidence = self.single_kindling(case, lit=True)
                evidence[0]['tokenCancelled'] = value
                with self.subTest(case=case, cancelled=value): self.assertTrue(self.verify(evidence)[0])
        for case in ('literature', 'petrol', 'kindle-retry', 'fireplace-literature', 'fireplace-petrol'):
            evidence = self.evidence(case);evidence[0]['tokenCancelled'] = True
            with self.subTest(case=case): self.assertTrue(self.verify(evidence)[0])

    def test_single_kindle_keeps_exact_fuel_resources_returns_and_tail_requirements(self):
        for case in ('bbq-kindle', 'fireplace-kindle'):
            for change in ('effect', 'fuel', 'expected', 'plank', 'stick', 'return', 'tail', 'trial', 'attempts', 'reserve'):
                evidence = self.single_kindling(case)
                result, prepared, receipts = evidence
                if change in ('effect', 'fuel'):
                    key = 'effectFuel' if change == 'effect' else 'fuel'
                    result[key] = receipts[0][key] = 359
                elif change == 'expected': prepared[0]['expectedFuel'] = 359
                elif change in ('plank', 'stick'):
                    for rows in (result['resources'], receipts[0]['resources']):
                        rows[0 if change == 'plank' else 1]['condition'] = 99
                elif change == 'return': result['returnIds'] = []
                elif change == 'tail': result['tailRead'] = receipts[0]['tailRead'] = False
                elif change == 'trial': result['trial'] = 2
                elif change == 'attempts': result['attempts'] = 0
                else:
                    reserve = copy.deepcopy(prepared[0]['resources'][1])
                    reserve.update(role='reserve1', id=102, source='root', returnToSource=False)
                    prepared[0]['resources'].append(reserve)
                with self.subTest(case=case, change=change): self.assertTrue(self.verify(evidence)[0])

    def test_target_kind_is_checked_against_case_in_all_envelopes(self):
        for case in ignition.CASES:
            for envelope in range(3):
                for value in (None, 'oven', 'bbq' if not case.startswith('bbq-') else 'fireplace'):
                    evidence = self.evidence(case)
                    row = evidence[0] if envelope == 0 else evidence[envelope][0]
                    if value is None: row.pop('targetKind')
                    else: row['targetKind'] = value
                    with self.subTest(case=case, envelope=envelope, value=value): self.assertTrue(self.verify(evidence)[0])
            evidence = self.evidence(case)
            for row in (evidence[0], evidence[1][0], evidence[2][0]): row['targetKind'] = 'oven'
            with self.subTest(case=case, consistent_forgery=True): self.assertTrue(self.verify(evidence)[0])

    def tidy_petrol(self, case='fireplace-petrol'):
        result, prepared, receipts = self.evidence(case)
        petrol = next(row for row in receipts[0]['resources'] if row['role'] == 'petrol')
        petrol.update(sourceCount=1, rootCount=0)
        receipts[0]['tidyReturnIds'] = [petrol['id']]
        result.update(resources=copy.deepcopy(receipts[0]['resources']), tidyReturnIds=[petrol['id']],
                      tidyReturns=[dict(id=petrol['id'], sessionId=7, nativeTransfer=True, fromRoot=True,
                                        toSource=True, groupCleanup=False, progress=True, tailRead=True, tokenCancelled=False)])
        return result, prepared, receipts

    def test_post_reader_p4_restore_keeps_exact_effects_in_both_modes_and_transports(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                self.selection.update(kind=kind, mode=mode)
                for case in ('petrol', 'last-match', 'bbq-petrol', 'fireplace-petrol'):
                    with self.subTest(kind=kind, mode=mode, case=case):
                        evidence = self.tidy_petrol(case)
                        issues, outcome, reason = self.verify(evidence)
                        self.assertEqual(issues, [])
                        self.assertIsNone(reason)
                        self.assertEqual(outcome['outcome']['tidyReturnIds'], evidence[0]['tidyReturnIds'])
                        self.assertEqual(outcome['outcome']['tidyReturns'], evidence[0]['tidyReturns'])
                        self.assertNotIn(evidence[0]['tidyReturnIds'][0], outcome['outcome']['returnIds'])

    def test_p4_restore_cannot_replace_native_return_or_resource_delta_evidence(self):
        for change in ('native-return', 'debit', 'condition', 'root', 'authority-root', 'duplicate-location', 'consumed'):
            evidence = self.tidy_petrol()
            result, _, receipts = evidence
            if change == 'native-return': result['returnIds'].append(result['tidyReturnIds'][0])
            else:
                rows = [result['resources'][1], receipts[0]['resources'][1]]
                if change == 'authority-root': rows = [receipts[0]['resources'][1]]
                for row in rows:
                    if change == 'debit': row['amount'] = 1.8
                    elif change == 'condition': row['condition'] = 99
                    elif change in ('root', 'authority-root'): row.update(sourceCount=0, rootCount=1)
                    elif change == 'duplicate-location': row['rootCount'] = 1
                    else: row.update(sourceCount=0, consumed=True)
            with self.subTest(change=change): self.assertTrue(self.verify(evidence)[0])

    def test_p4_restore_provenance_types_session_timing_and_selected_mod_are_strict(self):
        for key, value in (('id', True), ('id', [101]), ('id', 999), ('sessionId', True), ('sessionId', 0),
                           ('sessionId', -1), ('sessionId', 7.0), ('nativeTransfer', 1), ('nativeTransfer', False),
                           ('fromRoot', False), ('toSource', False), ('groupCleanup', True), ('groupCleanup', 0),
                           ('progress', False), ('tailRead', False), ('tailRead', 1),
                           ('tokenCancelled', True), ('tokenCancelled', 0)):
            evidence = self.tidy_petrol();evidence[0]['tidyReturns'][0][key] = value
            with self.subTest(key=key, value=value): self.assertTrue(self.verify(evidence)[0])
        for change in ('missing-proof', 'proof-type', 'proof-row', 'duplicate-proof', 'extra-field', 'missing-field', 'no-mod', 'early-tail'):
            evidence = self.tidy_petrol()
            if change == 'missing-proof': evidence[0].pop('tidyReturns')
            elif change == 'proof-type': evidence[0]['tidyReturns'] = {}
            elif change == 'proof-row': evidence[0]['tidyReturns'] = [None]
            elif change == 'duplicate-proof': evidence[0]['tidyReturns'] *= 2
            elif change == 'extra-field': evidence[0]['tidyReturns'][0]['extra'] = True
            elif change == 'missing-field': evidence[0]['tidyReturns'][0].pop('progress')
            elif change == 'early-tail': evidence[0]['petrolBeforeTail'] = False
            else: self.selection['mods'] = []
            with self.subTest(change=change): self.assertTrue(self.verify(evidence)[0])
            self.selection['mods'] = ['P4TidyUpMeister']

    def test_p4_return_ids_are_required_unique_and_limited_to_that_trials_petrol(self):
        for envelope in (0, 2):
            for value in (None, {}, [True], [101, 101], [999], [100], []):
                evidence = self.tidy_petrol()
                row = evidence[0] if envelope == 0 else evidence[2][0]
                if value is None: row.pop('tidyReturnIds')
                else: row['tidyReturnIds'] = value
                with self.subTest(envelope=envelope, value=value): self.assertTrue(self.verify(evidence)[0])
        for case in ('literature', 'bbq-fuel', 'fireplace-literature', 'fireplace-kindle', 'kindle-retry'):
            evidence = self.evidence(case)
            item_id = evidence[1][0]['resources'][0]['id']
            evidence[0]['tidyReturnIds'] = evidence[2][0]['tidyReturnIds'] = [item_id]
            with self.subTest(case=case): self.assertTrue(self.verify(evidence)[0])
        evidence = self.evidence('fireplace-petrol')
        for row in (evidence[0]['resources'][1], evidence[2][0]['resources'][1]): row.update(sourceCount=1, rootCount=0)
        self.assertTrue(self.verify(evidence)[0])
        for case in ('literature', 'fireplace-petrol'):
            for value in (None, 1, 'true'):
                evidence = self.evidence(case)
                if value is None: evidence[0].pop('petrolBeforeTail')
                else: evidence[0]['petrolBeforeTail'] = value
                with self.subTest(case=case, petrol_before_tail=value): self.assertTrue(self.verify(evidence)[0])

    def test_native_failed_tail_can_still_prove_p4_settlement_without_becoming_a_pass(self):
        self.selection.update(kind='mp', mode='native')
        evidence = self.tidy_petrol()
        result, _, receipts = evidence
        result.update(tailRead=False, tailProgress=False, petrolBeforeTail=False, tokenCancelled=True,
                      status='failed', reason='native-independent-tail-not-preserved')
        receipts[0]['tailRead'] = False
        result['tidyReturns'][0].update(tailRead=False, tokenCancelled=True)
        issues, outcome, reason = self.verify(evidence)
        self.assertEqual(issues, [])
        self.assertEqual(reason, 'native-independent-tail-not-preserved')
        self.assertFalse(outcome['outcome']['tailRead'])
        for row in (result['resources'][1], receipts[0]['resources'][1]): row.update(sourceCount=0, rootCount=1)
        self.assertTrue(self.verify(evidence)[0])

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
