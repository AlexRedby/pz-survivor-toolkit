"""Optional return controls retain native authority and independent receipts."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from tests import test_queue_wring_clothing as fixtures
from queue_checks.adapters import wring_clothing_verifier as verifier

a = fixtures.a


def control_sample(kind='sp', mode='toolkit', control='keep'):
    reference = fixtures.WringClothingRestorationProfileTests().sample(mode)
    if kind == 'sp':
        result = reference
    else:
        result = list(fixtures.evidence(kind, mode, 'worn-bag'))
        row, selection, ids, final = result
        selection.update(reference[1]); selection['kind'] = kind
        selection['options'] = dict(selection['options'], mp_host=True)
        ids['restoration'] = row['ids']['restoration'] = True
        row['restoration'] = copy.deepcopy(reference[0]['restoration'])
        if mode == 'toolkit':
            row['prepared']['returns'][0].update(bodySettled=True, allowMissing=True)
        else:
            row['prepared']['returns'] = []
            for snapshot in (row['client'], row['server'], final):
                for name in ('target', 'cancelled'):
                    snapshot['items'][name]['counts'] = dict(actor=1, root=1, source=0)
    row, selection, ids, final = result
    case = 'worn-bag-' + control; enabled = mode == 'toolkit'
    selection['cases'] = [case]
    ids.update(case=case, returnControl=control)
    row['ids'].update(case=case, returnControl=control)
    for snapshot in (row['input'], row['client'], row['server'], final,
                     row['prepared']['before'], row['prepared']['after']):
        snapshot['case'] = case
    if kind == 'mp': row['authorityBaseline']['case'] = case
    for snapshot in (row['client'], row['server'], final):
        snapshot['items']['target']['counts'] = dict(actor=1, root=1, source=0)
    samples = row['restoration']['samples']
    for sample in samples: sample['case'] = case
    samples[-1].update(state='waived' if enabled else False, plannedTransfers=0)
    row['prepared']['returns'] = []
    before = copy.deepcopy(row['input'])
    before['items']['target']['counts'] = dict(actor=1, root=1, source=0)
    before['items']['front'].update(wetness=10, wetWeight=.1025)
    if not enabled:
        before['items']['cancelled'].update(wetness=10, wetWeight=.1025, counts=dict(actor=1, root=1, source=0))
    value = dict(kind=control, enabled=enabled, bodyRef=row['prepared']['target']['body'],
                 bodyNative='native-body-episode', generatedRef='native-return' if enabled else False,
                 before=before, after=copy.deepcopy(before), accepted=enabled or control == 'full',
                 policyMode='pending-return' if enabled and control == 'keep' else False, bodyUnchanged=True)
    if control == 'full':
        spec = ids['items']['target']
        value.update(authority=dict(case=case, itemId=spec['id'], itemType=spec['type'], beforeCapacity=28,
                                    afterCapacity=0, roomBefore=True, roomAfter=False, root=True, authority=True, at=150),
                     blocked=dict(id=7, itemId=spec['id'], itemType=spec['type'], state='blocked', reason='admission') if enabled else False,
                     kept=enabled)
    row['returnControl'] = value
    return result


def capture(result):
    """Build separate client and authority streams, preserving grouped order."""
    row, selection, ids, verified = copy.deepcopy(result)
    case = ids['case']; kind = selection['kind']; enabled = selection['mode'] == 'toolkit'
    row.update(suite='wring-clothing', event='case', id=case, actor='client1', kind=kind, mode=selection['mode'])
    setup = dict(suite='wring-clothing', event='setup', cases=[case], queueEnabled=enabled, nativeDurations=True, adapterInstalled=True)
    ending = dict(suite='wring-clothing', event='complete', cases=[case], performed=1, failed=0, skipped=0)
    raw = lambda marker, payload: a.PREFIX + marker + ' ' + json.dumps(payload)
    authority = [raw('PREPARED', ids)]
    if kind == 'mp': authority.append(raw('WEAR_BASELINE', row['authorityBaseline']))
    if case == 'worn-bag-full': authority.append(raw('CAPACITY_LOST', row['returnControl']['authority']))
    authority.append(raw('VERIFIED', verified))
    client = ['[QUEUE_CHECK] ' + json.dumps(setup), raw('CLIENT_PLACEMENT', dict(case=case, proof=row['clientPlacement']))]
    if kind == 'sp': client += authority
    elif case == 'worn-bag-full': client.append(raw('CAPACITY_LOST', row['returnControl']['authority']))
    client += [raw('RESTORATION', sample) for sample in row['restoration']['samples']]
    client += ['[QUEUE_CHECK] ' + json.dumps(row), '[QUEUE_CHECK] ' + json.dumps(ending), raw('COMPLETE', dict(cases=[case]))]
    return selection, client, authority


class WringReturnControlTests(unittest.TestCase):
    def test_exact_native_controls_for_both_modes_and_transports(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for control in ('keep', 'full'):
                    with self.subTest(kind=kind, mode=mode, control=control):
                        result = control_sample(kind, mode, control)
                        self.assertEqual([], a.check_case(*result))
                        selection, client, authority = capture(result)
                        with tempfile.TemporaryDirectory() as temporary:
                            root = Path(temporary)
                            (root / 'client1-launch.log').write_text('\n'.join(client))
                            (root / 'server-launch.log').write_text('\n'.join(authority))
                            self.assertEqual([], verifier.verify(root, selection, {})['issues'])

    def test_keep_needs_exact_body_generated_request_and_unchanged_physical_state(self):
        for field, value in (('bodyRef', 'foreign'), ('bodyNative', False), ('generatedRef', False),
                             ('enabled', False), ('accepted', False), ('policyMode', False), ('bodyUnchanged', False)):
            result = control_sample(); result[0]['returnControl'][field] = value
            self.assertTrue(a.check_case(*result), field)
        result = control_sample(); result[0]['returnControl']['after']['items']['target']['wetness'] = 10
        self.assertTrue(a.check_case(*result))
        result = control_sample(); result[0]['restoration']['samples'][1]['returnRef'] = 'foreign'
        self.assertTrue(a.check_case(*result))
        result = control_sample(); result[0]['restoration']['samples'][-1]['state'] = 'completed'
        self.assertTrue(a.check_case(*result))

    def test_native_control_cannot_publish_keep_or_blocked_debt(self):
        for control in ('keep', 'full'):
            for field, value in (('generatedRef', 'fake'), ('policyMode', 'pending-return'), ('enabled', True), ('kept', True)):
                result = control_sample(mode='native', control=control); result[0]['returnControl'][field] = value
                self.assertTrue(a.check_case(*result), (control, field))
        result = control_sample(mode='native', control='full'); result[0]['returnControl']['blocked'] = dict(id=7)
        self.assertTrue(a.check_case(*result))

    def test_full_source_requires_real_authority_exact_debt_and_footer_keep(self):
        for section, field, value in (('authority', 'beforeCapacity', 0), ('authority', 'beforeCapacity', True),
                                      ('authority', 'afterCapacity', False), ('authority', 'roomBefore', False),
                                      ('authority', 'roomAfter', True), ('authority', 'root', False),
                                      ('authority', 'authority', False), ('authority', 'itemId', -1),
                                      ('authority', 'at', float('nan')), ('blocked', 'id', 0),
                                      ('blocked', 'itemId', -1), ('blocked', 'itemType', 'other'),
                                      ('blocked', 'state', 'revoked'), ('blocked', 'reason', '')):
            result = control_sample(control='full'); result[0]['returnControl'][section][field] = value
            self.assertTrue(a.check_case(*result), (section, field))
        result = control_sample(control='full'); result[0]['returnControl']['kept'] = False
        self.assertTrue(a.check_case(*result))
        result = control_sample(control='full'); result[0]['client']['items']['target']['counts'] = dict(actor=1, root=0, source=1)
        self.assertTrue(a.check_case(*result), 'full source cannot silently accept successful physical restoration')

    def test_full_refusal_preserves_any_real_native_callback_evidence(self):
        result = control_sample(control='full')
        receipt = copy.deepcopy(fixtures.WringClothingRestorationProfileTests().sample('toolkit')[0]['prepared']['returns'][0])
        receipt['events'][-1]['succeeded'] = False
        result[0]['prepared']['returns'] = [receipt]
        result[0]['restoration']['samples'][-1]['plannedTransfers'] = 1
        self.assertEqual([], a.check_case(*result))
        for field, value in (('toBag', -1), ('items', []), ('allowMissing', False), ('bodySettled', False), ('actionRef', 'foreign')):
            changed = copy.deepcopy(result); changed[0]['prepared']['returns'][0][field] = value
            self.assertTrue(a.check_case(*changed), field)
        for change in ('unpaired', 'duplicate', 'episode'):
            changed = copy.deepcopy(result); events = changed[0]['prepared']['returns'][0]['events']
            if change == 'unpaired': events.pop()
            elif change == 'duplicate': events += copy.deepcopy(events)
            else: events[-1]['nativeRef'] = 'other'
            self.assertTrue(a.check_case(*changed), change)

    def test_control_domain_aggregates_without_repairing_other_failures(self):
        result = control_sample(control='full')
        result[0]['commands'][-1]['progress'] = False
        result[0]['client']['items']['target']['wetness'] = 60
        result[0]['returnControl']['kept'] = False
        before = copy.deepcopy(result)
        domains = [issue.split('[', 1)[1].split(']', 1)[0] for issue in a.check_case(*result)]
        self.assertIn('native execution', domains); self.assertIn('physical state', domains); self.assertIn('return control', domains)
        self.assertEqual(before, result)

    def test_alias_and_provider_must_agree_and_unrequested_controls_fail(self):
        result = control_sample(); result[1]['options']['wring_restoration_provider'] = 'selected'
        self.assertTrue(a.check_case(*result))
        result = control_sample(); result[0]['ids']['returnControl'] = result[2]['returnControl'] = 'full'
        self.assertTrue(a.check_case(*result))
        result = fixtures.WringClothingRestorationProfileTests().sample('toolkit')
        result[0]['returnControl'] = dict(kind='keep')
        self.assertTrue(a.check_case(*result))

    def test_grouped_aliases_keep_authority_and_restoration_case_order(self):
        for mode in ('native', 'toolkit'):
            results = [fixtures.WringClothingRestorationProfileTests().sample(mode),
                       control_sample(mode=mode), control_sample(mode=mode, control='full')]
            captures = [capture(result) for result in results]
            cases = [result[2]['case'] for result in results]
            selection = dict(captures[0][0], cases=cases)
            setup = dict(suite='wring-clothing', event='setup', cases=cases, queueEnabled=mode == 'toolkit',
                         nativeDurations=True, adapterInstalled=True)
            ending = dict(suite='wring-clothing', event='complete', cases=cases, performed=len(cases), failed=0, skipped=0)
            client = ['[QUEUE_CHECK] ' + json.dumps(setup)]
            for _, lines, _ in captures:
                for line in lines:
                    if line.startswith('[QUEUE_CHECK] ') and json.loads(line.split(' ', 1)[1]).get('event') != 'case':
                        continue
                    if not line.startswith(a.PREFIX + 'COMPLETE '): client.append(line)
            client += ['[QUEUE_CHECK] ' + json.dumps(ending), a.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=cases))]
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); path = root / 'client1-launch.log'
                path.write_text('\n'.join(client))
                self.assertEqual([], verifier.verify(root, selection, {})['issues'])
                # A matching receipt from a different position in the batch is
                # still insufficient authority for this case's intervention.
                lost = next(line for line in client if line.startswith(a.PREFIX + 'CAPACITY_LOST '))
                client.remove(lost); client.insert(1, lost); path.write_text('\n'.join(client))
                self.assertTrue(verifier.verify(root, selection, {})['issues'])

    def test_independent_full_authority_receipts_are_required_ordered_and_bound(self):
        for kind in ('sp', 'mp'):
            selection, original_client, original_authority = capture(control_sample(kind=kind, control='full'))
            for mutation in ('missing', 'duplicate', 'wrong-case', 'changed', 'late', 'client-missing'):
                client, authority = original_client[:], original_authority[:]
                stream = client if kind == 'sp' else authority
                index = next(i for i, line in enumerate(stream) if line.startswith(a.PREFIX + 'CAPACITY_LOST '))
                if mutation in ('missing', 'client-missing'):
                    if mutation == 'client-missing': client = [line for line in client if not line.startswith(a.PREFIX + 'CAPACITY_LOST ')]
                    else: stream.pop(index)
                elif mutation == 'duplicate': stream.insert(index, stream[index])
                elif mutation in ('wrong-case', 'changed'):
                    payload = json.loads(stream[index].split('CAPACITY_LOST ', 1)[1])
                    payload['case' if mutation == 'wrong-case' else 'at'] = 'worn-bag-keep' if mutation == 'wrong-case' else 999
                    stream[index] = a.PREFIX + 'CAPACITY_LOST ' + json.dumps(payload)
                else: stream.append(stream.pop(index))
                with tempfile.TemporaryDirectory() as temporary:
                    root = Path(temporary)
                    (root / 'client1-launch.log').write_text('\n'.join(client))
                    (root / 'server-launch.log').write_text('\n'.join(authority))
                    self.assertTrue(verifier.verify(root, selection, {})['issues'], (kind, mutation))


if __name__ == '__main__':
    unittest.main()
