"""Torch refill requires matching authority identities and native execution evidence."""
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
        self.selection = dict(suite=adapter.SUITE, cases=['trunk-retained'], kind='mp',
                              mode='toolkit', clients=1, languages=['EN'],
                              mods=['PZSurvivorToolkit'], options={'mp_host': True})
        self.effect = dict(case='trunk-retained', sourceID=11, outputID=13, tankID=12,
                           retained=True, sourceRemoved=True, returned=True,
                           tankReturned=True, fuelExact=True, conserved=True,
                           torchUses=10, tankUses=91, torchBefore=1, tankBefore=100)
        self.native = dict(selectedID=11, recipe='Base.RefillBlowTorch', nativeDuration=True,
                           queueDrained=True, craftObserved=True, duration=250)

    def verify(self, authority=None, native=None, complete=True):
        def record(event, value):
            return adapter.MARKER + event + ' ' + json.dumps(value) + '\n'
        client = record('LOCAL', self.effect) + record('NATIVE', native or self.native)
        if complete:
            client += record('COMPLETE', dict(case='trunk-retained', role='client1'))
        (self.root / 'client1-launch.log').write_text(client)
        (self.root / 'server-launch.log').write_text(record('AUTHORITY', authority or self.effect))
        return adapter.verify(self.root, self.selection, {})['issues']

    def test_authority_and_native_evidence_pass(self):
        adapter.validate(self.selection)
        self.assertEqual(self.verify(), [])

    def test_changed_server_item_or_fuel_rejected(self):
        for field, value in [('outputID', 14), ('tankID', 14), ('tankUses', 90),
                             ('retained', False), ('sourceRemoved', False), ('fuelExact', False)]:
            authority = dict(self.effect, **{field: value})
            with self.subTest(field=field):
                self.assertTrue(self.verify(authority=authority))

    def test_native_execution_observation_required(self):
        for field, value in [('nativeDuration', False), ('queueDrained', False),
                             ('craftObserved', False), ('selectedID', 14)]:
            with self.subTest(field=field):
                self.assertTrue(self.verify(native=dict(self.native, **{field: value})))
        self.assertTrue(self.verify(complete=False))

    def test_menu_host_required(self):
        selection = copy.deepcopy(self.selection)
        selection['options'] = {}
        with self.assertRaises(ValueError):
            adapter.validate(selection)


if __name__ == '__main__':
    unittest.main()
