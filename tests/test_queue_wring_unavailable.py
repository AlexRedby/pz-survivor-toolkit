"""Detached retained sources waive only their exact optional return debt."""
import copy
import json
from pathlib import Path
import tempfile
import unittest

from tests.test_queue_wring_return_controls import a, capture, control_sample
from queue_checks.adapters import wring_clothing_verifier as verifier


def unavailable_sample(kind='sp', mode='toolkit', detached_after=None):
    result = control_sample(kind, mode, 'unavailable')
    row, selection, ids, final = result
    enabled = mode == 'toolkit'; spec = ids['items']['target']; cancelled = ids['items']['cancelled']
    for snapshot in (row['input'], row['prepared']['before'], row['prepared']['after']):
        snapshot['sourceDetached'] = False
    if kind == 'mp': row['authorityBaseline']['sourceDetached'] = False
    for snapshot in (row['client'], row['server'], final):
        snapshot['sourceDetached'] = True
        if enabled: snapshot['items']['cancelled']['counts'] = dict(actor=0, root=0, source=1)
    contents = [dict(id=cancelled['id'], type=cancelled['type'])] if enabled else []
    value = row['returnControl']; value['before']['sourceDetached'] = False
    value['after'] = copy.deepcopy(value['before'])
    value['after']['sourceDetached'] = kind == 'sp' if detached_after is None else detached_after
    if enabled and value['after']['sourceDetached']:
        value['after']['items']['cancelled']['counts'] = dict(actor=0, root=0, source=1)
    value.update(accepted=True, policyMode=False, detachedConfirmed=True,
                 replica=dict(bagAbsentRoot=True, bagAbsentWorn=True, rootTarget=True, sourceRetained=True),
                 authority=dict(case=ids['case'], itemId=spec['id'], itemType=spec['type'],
                                bagId=ids['source']['bag'], bagType='Base.Bag_Military',
                                bagRootBefore=True, bagWornBefore=True, bagRootAfter=False, bagWornAfter=False,
                                contentsBefore=contents, contentsAfter=copy.deepcopy(contents),
                                root=True, authority=True, at=150, scope='detached-retained-fixture-bag'),
                 blocked=dict(id=7, itemId=spec['id'], itemType=spec['type'], state='blocked', reason='admission') if enabled else False,
                 kept=enabled)
    return result


def unavailable_capture(result):
    selection, client, authority = capture(result)
    receipt = a.PREFIX + 'SOURCE_LOST ' + json.dumps(result[0]['returnControl']['authority'])
    index = next(i for i, line in enumerate(authority) if line.startswith(a.PREFIX + 'VERIFIED '))
    authority.insert(index, receipt)
    if selection['kind'] == 'sp':
        index = next(i for i, line in enumerate(client) if line.startswith(a.PREFIX + 'VERIFIED '))
    else:
        index = next(i for i, line in enumerate(client) if line.startswith(a.PREFIX + 'RESTORATION '))
    client.insert(index, receipt)
    return selection, client, authority


def verify_capture(selection, client, authority):
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        (root / 'client1-launch.log').write_text('\n'.join(client))
        (root / 'server-launch.log').write_text('\n'.join(authority))
        return verifier.verify(root, selection, {})['issues']


class WringUnavailableSourceTests(unittest.TestCase):
    def test_exact_retained_source_modes_and_transports(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for detached in ((True,) if kind == 'sp' else (False, True)):
                    with self.subTest(kind=kind, mode=mode, detached=detached):
                        result = unavailable_sample(kind, mode, detached)
                        self.assertEqual([], a.check_case(*result))
                        self.assertEqual([], verify_capture(*unavailable_capture(result)))

    def test_authority_requires_detachment_and_exact_retained_contents(self):
        mutations = [('bagId', -1), ('bagType', 'Base.Bag_Schoolbag'), ('bagRootBefore', False),
                     ('bagWornBefore', False), ('bagRootAfter', True), ('bagWornAfter', True),
                     ('contentsBefore', []), ('contentsAfter', []), ('root', False), ('authority', False),
                     ('at', float('nan')), ('scope', 'destroyed'), ('itemId', -1), ('itemType', 'other')]
        for field, value in mutations:
            result = unavailable_sample(); result[0]['returnControl']['authority'][field] = value
            self.assertTrue(a.check_case(*result), field)
        result = unavailable_sample(); result[0]['returnControl']['authority']['contentsAfter'].append(dict(id=999, type='other'))
        self.assertTrue(a.check_case(*result))
        result = unavailable_sample(mode='native'); result[0]['returnControl']['authority']['contentsAfter'] = [dict(id=999, type='other')]
        self.assertTrue(a.check_case(*result))

    def test_replica_and_snapshot_detachment_are_required(self):
        for field in ('bagAbsentRoot', 'bagAbsentWorn', 'rootTarget', 'sourceRetained'):
            result = unavailable_sample(); result[0]['returnControl']['replica'][field] = False
            self.assertTrue(a.check_case(*result), field)
        result = unavailable_sample(); result[0]['returnControl']['detachedConfirmed'] = False
        self.assertTrue(a.check_case(*result))
        for section in ('input', 'client', 'server'):
            result = unavailable_sample(); result[0][section]['sourceDetached'] = section == 'input'
            self.assertTrue(a.check_case(*result), section)
        for section in ('before', 'after'):
            result = unavailable_sample(); result[0]['prepared'][section]['sourceDetached'] = True
            self.assertTrue(a.check_case(*result), section)
        result = unavailable_sample(detached_after=False)
        self.assertTrue(a.check_case(*result), 'SP must detach synchronously')
        result = unavailable_sample(); result[0]['returnControl']['after']['items']['target']['wetness'] = 10
        self.assertTrue(a.check_case(*result), 'intervention cannot wring body')
        result = unavailable_sample(); result[0]['client']['items']['cancelled']['counts'] = dict(actor=1, root=0, source=1)
        self.assertTrue(a.check_case(*result), 'retained garment left actor ancestry')
        result = unavailable_sample(); del result[0]['client']['sourceDetached']
        self.assertTrue(a.check_case(*result), 'missing witness fails closed')

    def test_only_blocked_own_debt_is_kept_and_unallocated_return_never_runs(self):
        for mode in ('native', 'toolkit'):
            for field, value in [('accepted', False), ('bodyUnchanged', False), ('policyMode', 'pending-return'),
                                 ('bodyRef', 'foreign'), ('bodyNative', False), ('enabled', mode != 'toolkit'),
                                 ('generatedRef', False if mode == 'toolkit' else 'fake')]:
                result = unavailable_sample(mode=mode); result[0]['returnControl'][field] = value
                self.assertTrue(a.check_case(*result), (mode, field))
            result = unavailable_sample(mode=mode); result[0]['prepared']['returns'] = [dict(actionRef='fake')]
            self.assertTrue(a.check_case(*result), (mode, 'return allocated'))
        for field, value in [('id', 0), ('itemId', -1), ('itemType', 'other'), ('state', 'revoked'), ('reason', '')]:
            result = unavailable_sample(); result[0]['returnControl']['blocked'][field] = value
            self.assertTrue(a.check_case(*result), field)
        result = unavailable_sample(); result[0]['returnControl']['kept'] = False
        self.assertTrue(a.check_case(*result))
        for field, value in [('kept', True), ('blocked', dict(id=7))]:
            result = unavailable_sample(mode='native'); result[0]['returnControl'][field] = value
            self.assertTrue(a.check_case(*result), field)
        for field, value in [('plannedTransfers', 1), ('state', 'completed')]:
            result = unavailable_sample(); result[0]['restoration']['samples'][-1][field] = value
            self.assertTrue(a.check_case(*result), field)
        result = unavailable_sample(); result[0]['restoration']['samples'][1]['returnRef'] = 'foreign'
        self.assertTrue(a.check_case(*result))
        result = unavailable_sample(); result[0]['restoration']['samples'][1]['returnIndex'] = result[0]['restoration']['samples'][1]['tailIndex']
        self.assertTrue(a.check_case(*result))

    def test_source_receipts_are_independent_ordered_and_bound(self):
        for kind in ('sp', 'mp'):
            original = unavailable_capture(unavailable_sample(kind))
            for mutation in ('missing', 'duplicate', 'wrong-case', 'changed', 'late', 'client-missing', 'malformed'):
                selection, client, authority = copy.deepcopy(original)
                stream = client if kind == 'sp' else authority
                index = next(i for i, line in enumerate(stream) if line.startswith(a.PREFIX + 'SOURCE_LOST '))
                if mutation == 'missing': stream.pop(index)
                elif mutation == 'client-missing': client = [line for line in client if not line.startswith(a.PREFIX + 'SOURCE_LOST ')]
                elif mutation == 'duplicate': stream.insert(index, stream[index])
                elif mutation == 'late': stream.append(stream.pop(index))
                elif mutation == 'malformed': stream[index] = a.PREFIX + 'SOURCE_LOST null'
                else:
                    payload = json.loads(stream[index].split('SOURCE_LOST ', 1)[1])
                    payload['case' if mutation == 'wrong-case' else 'at'] = 'worn-bag-full' if mutation == 'wrong-case' else 999
                    stream[index] = a.PREFIX + 'SOURCE_LOST ' + json.dumps(payload)
                self.assertTrue(verify_capture(selection, client, authority), (kind, mutation))

    def test_failures_aggregate_without_mutating_evidence(self):
        result = unavailable_sample(); result[0]['commands'][-1]['progress'] = False
        result[0]['client']['items']['target']['wetness'] = 60
        result[0]['returnControl']['kept'] = False
        before = copy.deepcopy(result)
        domains = [issue.split('[', 1)[1].split(']', 1)[0] for issue in a.check_case(*result)]
        self.assertIn('native execution', domains); self.assertIn('physical state', domains); self.assertIn('return control', domains)
        self.assertEqual(before, result)


if __name__ == '__main__':
    unittest.main()
