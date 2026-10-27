"""Focused evidence contract for the manually browsed item catalogue."""
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tools'))
from queue_checks.adapters import item_catalog


class ItemCatalogAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.selection = {'suite': 'item-catalog', 'cases': ['browse'], 'kind': 'sp',
                          'mode': 'toolkit', 'clients': 1, 'languages': ['EN'],
                          'mods': ['PZSurvivorToolkit'], 'options': {}}
        self.output = self.root / 'run'
        self.output.mkdir()

    def test_validate_allows_same_suite_world_template_and_selected_mods(self):
        self.selection['options']['world_template'] = str(self.root / 'sealed-world')
        self.selection['mods'] += ['CleanUI', 'organizedCategories_core']
        item_catalog.validate(self.selection)
        with self.assertRaisesRegex(ValueError, 'PZSurvivorToolkit'):
            item_catalog.validate(dict(self.selection, mods=['CleanUI', 'organizedCategories_core']))

    def test_stage_uses_manual_lifetime_and_failure_marker(self):
        cache = self.output / 'client1'
        cache.mkdir()
        runtime = {'roles': {'client1': {'cache': str(cache)}}}
        item_catalog.stage(ROOT, self.output, self.root / 'game', self.root / 'jdk',
                           self.selection, {}, runtime)
        self.assertTrue(runtime['fixture']['manual'])
        self.assertEqual(runtime['fixture']['failure_markers'], ['[ITEM_CATALOG] FAIL '])
        self.assertFalse(item_catalog.complete(self.selection, 'client1', '[ITEM_CATALOG] READY items=1 crates=1 skipped=0'))

    def test_verify_requires_one_positive_ready_receipt_and_no_failure(self):
        log = self.output / 'client1-launch.log'
        log.write_text('LOG : Lua      f:0, t:1, st:0> [ITEM_CATALOG] READY items=420 crates=18 skipped=2\n')
        result = item_catalog.verify(self.output, self.selection, {})
        self.assertFalse(result['issues'])
        row = result['outcomes'][0]
        self.assertEqual(row['status'], 'captured')
        self.assertTrue(row['outcome']['manualReview'])
        self.assertFalse(row['outcome']['evidenceComplete'])
        self.assertEqual((row['outcome']['items'], row['outcome']['crates'], row['outcome']['skipped']), (420, 18, 2))

        for text in ('',
                     '[ITEM_CATALOG] READY items=1 crates=1 skipped=0\n'
                     '[ITEM_CATALOG] READY items=2 crates=1 skipped=0\n',
                     'LOG : Lua f:0, t:1> [ITEM_CATALOG] READY items=x crates=1 skipped=0\n',
                     '[ITEM_CATALOG] READY items=0 crates=1 skipped=0\n',
                     '[ITEM_CATALOG] READY items=1 crates=0 skipped=0\n',
                     '[ITEM_CATALOG] READY items=1 crates=1 skipped=0\n[ITEM_CATALOG] FAIL broken\n'):
            log.write_text(text)
            result = item_catalog.verify(self.output, self.selection, {})
            self.assertTrue(result['issues'], text)
            self.assertEqual(result['outcomes'][0]['status'], 'failed')


if __name__ == '__main__':
    unittest.main()
