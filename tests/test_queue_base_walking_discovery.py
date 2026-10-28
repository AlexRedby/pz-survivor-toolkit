import csv
import json
from pathlib import Path
import tempfile
import unittest

from tools.queue_checks.adapters import base_walking_profile as profile


class DiscoveryEvidenceChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        (self.root / 'client1/Lua').mkdir(parents=True)
        self.records, self.floor = [], []
        for phase in (1, 2, 3):
            self.records.append(dict(kind='begin', phase=phase, settings={'nestedLoot': False}))
            self.records.append(dict(kind='timing', phase=phase, name='page.refreshBackpacks.loot',
                                     calls=2, inclusive_ms=4.5, exclusive_ms=1.5, max_ms=3, errors=0))
            self.records.append(dict(kind='end', phase=phase, settings={'nestedLoot': False},
                                     aborted=False, restore_conflicts=0,
                                     samples={'observer_errors': 0, 'loot': {'refreshes': 2,
                                         'floor_items_min': 1, 'floor_items_last': 1, 'floor_items_max': 1}}))
            for method in ('AddItem(InventoryItem)', 'clear()', 'removeItemsFromProcessItems()'):
                self.floor.append(dict(phase=phase, method=method, calls=2,
                                       inclusive_ns=3000, max_inclusive_ns=2000))

    def receipts(self):
        serialized = [json.dumps(record) for record in self.records]
        (self.root / 'client1/Lua/base-walking-inventory-discovery.jsonl.txt').write_text('\n'.join(serialized))
        path = self.root / 'client1/base-walking-inventory-floor.csv'
        with path.open('w') as stream:
            writer = csv.DictWriter(stream, fieldnames=['phase', 'method', 'calls', 'inclusive_ns', 'max_inclusive_ns'])
            writer.writeheader()
            writer.writerows(self.floor)
        return '\n'.join(profile.PREFIX + 'INVENTORY_DISCOVERY ' + line for line in serialized) + (
            '\n[BASE_WALKING_PROFILE] INVENTORY_FLOOR csv=' + str(path) + ' unclosed_scopes=0\n')

    def test_complete_method_evidence(self):
        self.records.insert(2, dict(kind='timing', phase=1, name='pane.refreshContainer.loot',
                                   calls=0, inclusive_ms=0, exclusive_ms=0, max_ms=0, errors=0))
        result = profile._discovery(self.root, self.receipts())
        self.assertEqual(len(result['floor']), 9)
        self.assertEqual(result['timings'][1]['calls'], 0)

    def test_missing_phase_or_changed_settings_fails(self):
        self.records[-1]['settings']['nestedLoot'] = True
        with self.assertRaisesRegex(ValueError, 'settings changed'):
            profile._discovery(self.root, self.receipts())
        self.records.pop()
        with self.assertRaisesRegex(ValueError, 'ordered'):
            profile._discovery(self.root, self.receipts())

    def test_failed_observer_or_scope_cannot_prove_cost(self):
        self.records[-1]['samples']['observer_errors'] = 1
        with self.assertRaisesRegex(ValueError, 'observer failed'):
            profile._discovery(self.root, self.receipts())
        self.records[-1]['samples']['observer_errors'] = 0
        with self.assertRaisesRegex(ValueError, 'scope did not close'):
            profile._discovery(self.root, self.receipts().replace('unclosed_scopes=0', 'unclosed_scopes=1'))

    def test_counter_or_duration_corruption_fails(self):
        self.floor[4]['calls'] = 1
        with self.assertRaisesRegex(ValueError, 'reset counts differ'):
            profile._discovery(self.root, self.receipts())
        self.floor[4]['calls'] = 2
        self.records[4]['inclusive_ms'] = float('nan')
        with self.assertRaises(ValueError):
            profile._discovery(self.root, self.receipts())

    def test_log_and_file_must_match(self):
        text = self.receipts()
        (self.root / 'client1/Lua/base-walking-inventory-discovery.jsonl.txt').write_text('{}')
        with self.assertRaisesRegex(ValueError, 'receipts differ'):
            profile._discovery(self.root, text)

    def test_nonempty_floor_requires_additem_hook(self):
        self.floor[3].update(calls=0, inclusive_ns=0, max_inclusive_ns=0)
        with self.assertRaisesRegex(ValueError, 'lacks native AddItem'):
            profile._discovery(self.root, self.receipts())
        self.records[5]['samples']['loot'].update(floor_items_min=0, floor_items_last=0, floor_items_max=0)
        profile._discovery(self.root, self.receipts())

    def test_floor_cardinality_must_be_observed_and_consistent(self):
        self.records[5]['samples']['loot']['floor_items_last'] = 2
        with self.assertRaisesRegex(ValueError, 'floor cardinalities'):
            profile._discovery(self.root, self.receipts())
        del self.records[5]['samples']['loot']['floor_items_last']
        with self.assertRaisesRegex(ValueError, 'floor cardinalities'):
            profile._discovery(self.root, self.receipts())


if __name__ == '__main__':
    unittest.main()
