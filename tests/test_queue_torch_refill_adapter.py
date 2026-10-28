"""Shared torch sessions keep ordered per-case evidence and exact authority cleanup."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks.adapters import torch_refill as adapter


class TorchRefillAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = dict(suite=adapter.SUITE, cases=list(adapter.CASES), kind='mp',
                              mode='toolkit', clients=1, languages=['EN'],
                              mods=['PZSurvivorToolkit'], options={'mp_host': True})
        self.client, self.server = [], []
        for epoch, case in enumerate(adapter.CASES, 1):
            source, tank, output = epoch * 10 + 1, epoch * 10 + 2, epoch * 10 + 3
            effect = dict(case=case, epoch=epoch, sourceID=source, outputID=output, tankID=tank,
                          retained=case != 'trunk-unmarked', sourceRemoved=True, returned=True,
                          tankReturned=True, fuelExact=True, conserved=True,
                          torchUses=10, tankUses=91, torchBefore=1, tankBefore=100)
            native = dict(case=case, epoch=epoch, selectedID=source, recipe='Base.RefillBlowTorch',
                          nativeDuration=True, queueDrained=True, craftObserved=True, duration=250)
            self.client += [('LOCAL', effect), ('NATIVE', native),
                            ('CLEANUP', dict(case=case, epoch=epoch, role='client1', ownedRemoved=True,
                                             baselineRestored=True)),
                            ('COMPLETE', dict(case=case, epoch=epoch, role='client1'))]
            self.server += [('AUTHORITY', copy.deepcopy(effect)),
                            ('REMOVED', dict(case=case, epoch=epoch, items=[source, tank, output],
                                             vehicle=epoch if case != 'root-retained' else -1,
                                             hasVehicle=case != 'root-retained', baselineRestored=True))]

    def verify(self):
        def records(rows):
            return ''.join(adapter.MARKER + event + ' ' + json.dumps(row) + '\n' for event, row in rows)
        count = len(self.selection['cases'])
        suffix = f'case={self.selection["cases"][-1]} epoch={count}'
        client = records(self.client) + f'[QUEUE_SESSION] COMPLETE {suffix} actor=client1 cases={count}\n'
        server = records(self.server) + f'[QUEUE_SESSION] COMPLETE {suffix} actor=server cases={count}\n'
        if self.selection['kind'] == 'sp':
            client = server + client
        (self.root / 'client1-launch.log').write_text(client)
        (self.root / 'server-launch.log').write_text(server)
        return adapter.verify(self.root, self.selection, {})

    def test_all_cases_have_independent_evidence(self):
        adapter.validate(self.selection)
        result = self.verify()
        self.assertEqual(result['issues'], [])
        self.assertEqual(list(result['evidence']), list(adapter.CASES))
        self.assertEqual([row['status'] for row in result['outcomes']], ['passed'] * 3)
        self.assertTrue(adapter.definitions()[adapter.SUITE]['shared_session'])

    def test_sp_uses_same_case_receipts(self):
        self.selection['kind'] = 'sp'
        self.assertEqual(self.verify()['issues'], [])

    def test_subset_and_order_supported(self):
        for cases in ([adapter.CASES[1]], list(reversed(adapter.CASES))):
            selection = dict(self.selection, cases=cases)
            adapter.validate(selection)
        for cases in ([], [adapter.CASES[0]] * 2, ['unknown']):
            with self.assertRaises(ValueError):
                adapter.validate(dict(self.selection, cases=cases))

    def test_changed_server_item_or_fuel_rejected_per_case(self):
        for field, value in [('outputID', 14), ('tankID', 14), ('tankUses', 90),
                             ('retained', False), ('sourceRemoved', False), ('fuelExact', False)]:
            original = self.server[0][1].copy()
            self.server[0][1][field] = value
            with self.subTest(field=field):
                result = self.verify()
                self.assertTrue(result['issues'])
                self.assertEqual([row['status'] for row in result['outcomes']], ['failed', 'passed', 'passed'])
            self.server[0] = ('AUTHORITY', original)

    def test_native_execution_observation_required(self):
        native = self.client[1][1]
        for field, value in [('nativeDuration', False), ('queueDrained', False),
                             ('craftObserved', False), ('selectedID', 14), ('duration', 1)]:
            original = native[field]
            native[field] = value
            with self.subTest(field=field):
                self.assertTrue(self.verify()['issues'])
            native[field] = original

    def test_missing_authority_or_cleanup_rejects_session(self):
        self.server.pop(2)
        self.assertTrue(self.verify()['issues'])

    def test_out_of_order_and_duplicate_phases_rejected(self):
        self.client[0], self.client[4] = self.client[4], self.client[0]
        self.assertTrue(self.verify()['issues'])
        self.client[0], self.client[4] = self.client[4], self.client[0]
        self.client.append(self.client[0])
        self.assertTrue(self.verify()['issues'])

    def test_epoch_and_cleanup_baseline_required(self):
        self.client[1][1]['epoch'] = 0
        self.assertTrue(self.verify()['issues'])
        self.client[1][1]['epoch'] = 1
        self.client[2][1]['baselineRestored'] = False
        self.assertTrue(self.verify()['issues'])

    def test_runner_waits_for_joint_session_completion(self):
        self.verify()
        text = (self.root / 'client1-launch.log').read_text()
        self.assertTrue(adapter.complete(self.selection, 'client1', text))
        self.assertFalse(adapter.complete(self.selection, 'client1', text.rsplit('[QUEUE_SESSION] COMPLETE', 1)[0]))

    def test_menu_host_required(self):
        selection = copy.deepcopy(self.selection)
        selection['options'] = {}
        with self.assertRaises(ValueError):
            adapter.validate(selection)


if __name__ == '__main__':
    unittest.main()
