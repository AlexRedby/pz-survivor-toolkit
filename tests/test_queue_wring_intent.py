"""Only a paid exact native equip can retire an earlier optional return."""
import copy
import unittest

from tests.test_queue_wring_return_controls import a, capture, control_sample
from tests.test_queue_wring_unavailable import verify_capture


def intent_sample(kind='sp', mode='toolkit', late_ack=False, complete=False):
    result = control_sample(kind, mode, 'intent')
    row, selection, ids, final = result; enabled = mode == 'toolkit'; spec = ids['items']['target']
    baseline = dict(worn=[dict(slot='base:back', id=ids['source']['bag'], type='Base.Bag_Military')],
                    primary=dict(id=200, type='Base.Hammer'), secondary=dict(id=201, type='Base.HandTorch'))
    for snapshot in (row['input'], row['prepared']['before'], row['prepared']['after'],
                     row['returnControl']['before'], row['returnControl']['after']):
        snapshot['equipment'] = copy.deepcopy(baseline)
    if kind == 'mp': row['authorityBaseline']['equipment'] = copy.deepcopy(baseline)
    target = dict(id=spec['id'], type=spec['type'])
    for snapshot in (row['client'], row['server'], final):
        snapshot['equipment'] = dict(copy.deepcopy(baseline), primary=copy.deepcopy(target))
    phases = [('perform', 'begin'), ('perform', 'finish')]
    if kind == 'sp' or complete: phases += [('complete', 'begin'), ('complete', 'finish')]
    native = 'native-equip-episode'
    events = []
    for phase, boundary in phases:
        effect = (phase, boundary) == ('complete', 'finish') if kind == 'sp' else not late_ack and boundary == 'finish'
        events.append(dict(phase=phase, boundary=boundary, succeeded=boundary == 'finish', nativeRef=native,
                           primary=copy.deepcopy(target if effect else baseline['primary'])))
    row['returnControl'].update(accepted=True, policyMode=False, blocked=False, kept=False, finalPrimarySame=True,
                               intent=dict(producer='native ISInventoryPaneContextMenu.OnPrimaryWeapon', actionRef='native-equip-action',
                                           duration=50, itemId=spec['id'], itemType=spec['type'], primary=True, twoHands=False,
                                           callbacksUntouched=True, started=True, progress=True,
                                           startedAt=row['commands'][-1]['startedAt'] + 1000, nativeRef=native, events=events,
                                           beforeEffect=dict(loanState='active' if enabled else False,
                                                             debt=dict(id=7, itemId=spec['id'], itemType=spec['type'], state='blocked', reason='admission') if enabled else False,
                                                             canonicalRoot=True, primary=copy.deepcopy(baseline['primary']))))
    return result


class WringExplicitIntentTests(unittest.TestCase):
    def test_exact_paid_equip_modes_and_transports_including_host_late_ack(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for late_ack, complete in ((False, False), (True, False), (True, True)) if kind == 'mp' else ((False, False),):
                    with self.subTest(kind=kind, mode=mode, late_ack=late_ack, complete=complete):
                        result = intent_sample(kind, mode, late_ack, complete)
                        self.assertEqual([], a.check_case(*result))
                        self.assertEqual([], verify_capture(*capture(result)))

    def test_independent_native_phase_order_preserves_exact_sp_effect(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                result = intent_sample(kind, mode, complete=True)
                events = result[0]['returnControl']['intent']['events']
                # Complete applies the SP hand effect; subsequent perform only
                # advances the queue and observes that same exact held target.
                events[:] = events[2:] + events[:2]
                if kind == 'sp':
                    target = result[0]['client']['equipment']['primary']
                    for event in events[2:]: event['primary'] = copy.deepcopy(target)
                self.assertEqual([], a.check_case(*result), (kind, mode))
                self.assertEqual([], verify_capture(*capture(result)), (kind, mode))
        result = intent_sample(complete=True)
        events = result[0]['returnControl']['intent']['events']
        events[:] = events[2:] + events[:2]
        self.assertTrue(a.check_case(*result), 'SP cannot lose hand effect after complete')
        result = intent_sample()
        events = result[0]['returnControl']['intent']['events']
        events[1], events[2] = events[2], events[1]
        self.assertTrue(a.check_case(*result), 'native phase pairs cannot overlap')

    def test_native_equip_identity_paid_progress_and_distinct_episode(self):
        for field, value in [('producer', 'foreign'), ('actionRef', False), ('duration', 0), ('duration', True),
                             ('itemId', -1), ('itemType', 'other'), ('primary', False), ('twoHands', True),
                             ('callbacksUntouched', False), ('started', False), ('progress', False),
                             ('startedAt', float('nan')), ('startedAt', 0), ('nativeRef', False),
                             ('nativeRef', 'native-body-episode')]:
            result = intent_sample(); result[0]['returnControl']['intent'][field] = value
            self.assertTrue(a.check_case(*result), field)
        for copied in ('command', 'generated'):
            result = intent_sample(); value = result[0]['returnControl']
            value['intent']['actionRef'] = result[0]['commands'][-1]['actionRef'] if copied == 'command' else value['generatedRef']
            self.assertTrue(a.check_case(*result), copied)

    def test_live_native_pre_effect_retains_exact_loan_and_failure(self):
        for field, value in [('loanState', 'waived'), ('loanState', False), ('canonicalRoot', False),
                             ('primary', dict(id=999, type='other')), ('primary', 0)]:
            result = intent_sample(); result[0]['returnControl']['intent']['beforeEffect'][field] = value
            self.assertTrue(a.check_case(*result), field)
        for field, value in [('id', 0), ('id', True), ('itemId', -1), ('itemType', 'other'), ('state', 'kept'), ('reason', '')]:
            result = intent_sample(); result[0]['returnControl']['intent']['beforeEffect']['debt'][field] = value
            self.assertTrue(a.check_case(*result), field)
        for field in ('beforeEffect', 'debt'):
            result = intent_sample(); intent = result[0]['returnControl']['intent']
            if field == 'beforeEffect': del intent[field]
            else: del intent['beforeEffect'][field]
            self.assertTrue(a.check_case(*result), field)
        for field, value in [('loanState', 'active'), ('debt', dict(id=7))]:
            result = intent_sample(mode='native'); result[0]['returnControl']['intent']['beforeEffect'][field] = value
            self.assertTrue(a.check_case(*result), field)

    def test_callback_copy_failure_omission_and_missing_native_effect_fail(self):
        for mutation in ('missing', 'duplicate', 'failed', 'episode', 'unpaired', 'reordered', 'foreign-primary', 'no-sp-effect', 'malformed', 'bad-hand-type'):
            result = intent_sample(); events = result[0]['returnControl']['intent']['events']
            if mutation == 'missing': events.clear()
            elif mutation == 'duplicate': events.extend(copy.deepcopy(events))
            elif mutation == 'failed': events[-1]['succeeded'] = False
            elif mutation == 'episode': events[-1]['nativeRef'] = 'copied-episode'
            elif mutation == 'unpaired': events.pop()
            elif mutation == 'reordered': events.reverse()
            elif mutation == 'foreign-primary': events[-1]['primary'] = dict(id=999, type='other')
            elif mutation == 'no-sp-effect': events[-1]['primary'] = result[0]['input']['equipment']['primary']
            elif mutation == 'bad-hand-type': events[0]['primary'] = 0
            else: events[-1] = None
            self.assertTrue(a.check_case(*result), mutation)
        result = intent_sample(); del result[0]['returnControl']['intent']
        self.assertTrue(a.check_case(*result))

    def test_final_canonical_hands_and_unchanged_baseline_equipment(self):
        for side in ('client', 'server'):
            for field, value in [('primary', False), ('primary', dict(id=999, type='other')), ('secondary', False), ('worn', [])]:
                result = intent_sample('mp'); result[0][side]['equipment'][field] = value
                if side == 'server': result[3]['equipment'][field] = copy.deepcopy(value)
                self.assertTrue(a.check_case(*result), (side, field))
        for side in ('input', 'authorityBaseline'):
            result = intent_sample('mp'); result[0][side]['equipment']['secondary'] = False
            self.assertTrue(a.check_case(*result), side)
        for snapshot in ('before', 'after'):
            result = intent_sample(); result[0]['prepared'][snapshot]['equipment']['primary'] = False
            self.assertTrue(a.check_case(*result), snapshot)
        result = intent_sample(); result[0]['returnControl']['after']['equipment']['primary'] = False
        self.assertTrue(a.check_case(*result))
        result = intent_sample(); result[0]['client']['sourceDetached'] = False
        self.assertTrue(a.check_case(*result))

    def test_intent_does_not_manual_keep_or_execute_old_return(self):
        for field, value in [('kept', True), ('blocked', dict(id=7)), ('finalPrimarySame', False), ('authority', dict(case='worn-bag-intent')),
                             ('policyMode', 'pending-return'), ('accepted', False), ('bodyUnchanged', False)]:
            result = intent_sample(); result[0]['returnControl'][field] = value
            self.assertTrue(a.check_case(*result), field)
        result = intent_sample(); result[0]['prepared']['returns'] = [dict(actionRef='native-return')]
        self.assertTrue(a.check_case(*result))
        for field, value in [('state', 'completed'), ('plannedTransfers', 1)]:
            result = intent_sample(); result[0]['restoration']['samples'][-1][field] = value
            self.assertTrue(a.check_case(*result), field)
        result = intent_sample(); result[0]['restoration']['samples'][1]['returnRef'] = 'foreign'
        self.assertTrue(a.check_case(*result))

    def test_failures_aggregate_without_mutating_evidence(self):
        result = intent_sample(); result[0]['commands'][-1]['progress'] = False
        result[0]['client']['items']['target']['wetness'] = 60
        result[0]['returnControl']['intent']['beforeEffect']['loanState'] = 'waived'
        before = copy.deepcopy(result)
        domains = [issue.split('[', 1)[1].split(']', 1)[0] for issue in a.check_case(*result)]
        self.assertIn('native execution', domains); self.assertIn('physical state', domains); self.assertIn('return control', domains)
        self.assertEqual(before, result)


if __name__ == '__main__':
    unittest.main()
