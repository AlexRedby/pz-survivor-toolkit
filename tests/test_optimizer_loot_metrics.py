"""Loot fill joins, nested counters and malformed evidence; no game/JVM."""
import copy
import csv
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import loot_metrics as loot
from queue_checks.adapters import optimizer_benchmark as benchmark


class LootMetricsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='loot-metrics-')
        self.addCleanup(self.temporary.cleanup)
        self.cache = Path(self.temporary.name)
        self.stages = []
        for phase in (1, 2, 3):
            stage = dict.fromkeys(benchmark.STAGE_COLUMNS, 0)
            stage.update(frame_id=phase, phase=phase, nano_start=phase * 110,
                nano_end=phase * 110 + 100, wall_ns=100, cpu_ns=-1, other_exclusive_ns=100)
            self.stages.append(stage)
        self.stages[1].update(loot_calls=5, loot_inclusive_ns=70, loot_exclusive_ns=45,
            chunk_exclusive_ns=10, lua_exclusive_ns=15, logic_exclusive_ns=30, other_exclusive_ns=0)
        self.stages[2].update(loot_calls=1, loot_inclusive_ns=50, loot_exclusive_ns=30,
            lua_exclusive_ns=40, logic_exclusive_ns=30, other_exclusive_ns=0)
        self.rows = []
        for frame, token, depth, start, end, fill, chunk, lua, chance, factory, nonnull in (
                (2, 1, 1, 230, 280, 30, 10, 10, 20, 10, 9),
                (2, 2, 2, 240, 250, 5, 5, 0, 8, 3, 2),
                (2, 3, 3, 242, 246, 2, 2, 0, 2, 1, 1),
                (2, 4, 2, 260, 270, 5, 0, 5, 8, 3, 3),
                (2, 5, 1, 290, 310, 15, 0, 5, 4, 2, 1),
                (3, 1, 1, 340, 390, 30, 0, 20, 6, 4, 4)):
            row = dict.fromkeys(loot.LOOT_COLUMNS, 0)
            row.update(frame_id=frame, fill_index=len(self.rows) + 1, token=token, depth=depth,
                container_type='ящик, "quoted"\n二', nano_start=start, nano_end=end,
                wall_ns=end-start, loot_exclusive_ns=fill, chunk_exclusive_ns=chunk,
                lua_exclusive_ns=lua, chance_calls=chance, factory_calls=factory,
                factory_nonnull=nonnull, bag_roll_calls=chance, direct_roll_calls=factory,
                plain_translation_calls=chance * 10, other_translation_calls=nonnull)
            self.rows.append(row)
        self.rows[1]['container_type'] = ''
        self.status = dict(version=1, complete_fills=6, omitted_fills=1, capacity=120000,
            max_depth=256, diagnostic='none',
            semantics='per_fill_inclusive_wall_exclusive_stage_partition',
            nested_rows='overlap', counters='inclusive_calls_not_items')
        self.write()

    def csv(self, name, columns, rows):
        with (self.cache / name).open('w', newline='', encoding='utf-8') as target:
            writer = csv.DictWriter(target, fieldnames=columns, extrasaction='ignore')
            writer.writeheader()
            writer.writerows(rows)

    def write(self, columns=None):
        self.csv('driving-stages.csv', benchmark.STAGE_COLUMNS, self.stages)
        self.csv('driving-loot.csv', columns or loot.LOOT_COLUMNS, self.rows)
        (self.cache / 'driving-loot-status.txt').write_text(
            ' '.join(key + '=' + str(value) for key, value in self.status.items()) + '\n')

    def report(self, frames=3):
        return loot.loot_metrics(self.cache, {'complete_frames': frames})

    def test_nested_partition_union_counters_phases_and_raw_intervals(self):
        report = self.report()
        self.assertEqual((report['complete_frames'], report['complete_fills'], report['omitted_fills']), (3, 6, 1))
        overall = report['groups']['overall']
        self.assertEqual((overall['frames'], overall['fills'], overall['top_level_fills']), (3, 6, 3))
        self.assertEqual(overall['max_frame_fills'], 5)
        self.assertAlmostEqual(overall['wall_ms'], 120 / 1e6)
        self.assertAlmostEqual(overall['stage_exclusive_ms']['loot'], 75 / 1e6)
        self.assertAlmostEqual(overall['stage_exclusive_ms']['chunk'], 10 / 1e6)
        self.assertAlmostEqual(overall['stage_exclusive_ms']['lua'], 35 / 1e6)
        self.assertEqual(overall['counter_totals']['chance_calls'], 30)
        self.assertEqual(overall['counter_totals']['factory_calls'], 16)
        self.assertEqual(overall['counter_totals']['factory_nonnull'], 14)
        self.assertEqual(overall['counter_totals']['plain_translation_calls'], 300)
        maximum = overall['max_single_fill']
        self.assertEqual((maximum['frame_id'], maximum['fill_index'], maximum['chance_calls']), (2, 1, 20))
        self.assertEqual(maximum['container_type'], self.rows[0]['container_type'])
        self.assertAlmostEqual(overall['max_single_fill_ms'], 50 / 1e6)
        self.assertEqual(overall['mean_fills_per_frame'], 2)
        self.assertEqual([row['fills'] for row in report['per_frame']], [0, 5, 1])
        self.assertEqual(report['per_frame'][1]['invocations'], self.rows[:5])
        self.assertEqual(report['per_frame'][1]['invocations'][1]['container_type'], '')
        self.assertEqual(report['groups']['phase1']['counter_totals'], dict.fromkeys(loot.COUNTERS, 0))
        self.assertEqual(report['groups']['phase2']['counter_totals']['factory_calls'], 12)
        self.assertIn('not distinct items or RNG draws', ' '.join(report['limits']))

    def test_complete_zero_fill_profile_and_empty_phase(self):
        self.rows = []
        self.status.update(complete_fills=0, omitted_fills=0)
        for stage in self.stages:
            stage.update(loot_calls=0, loot_inclusive_ns=0, loot_exclusive_ns=0)
        self.stages[2]['phase'] = 2
        self.write()
        report = self.report()
        self.assertEqual(report['complete_fills'], 0)
        self.assertEqual(report['groups']['overall']['wall_ms'], 0)
        self.assertIsNone(report['groups']['overall']['max_single_fill'])
        self.assertEqual(report['groups']['phase3']['frames'], 0)
        self.assertIsNone(report['groups']['phase3']['mean_fills_per_frame'])

    def test_integer_fields_bounds_and_spellings(self):
        original = copy.deepcopy(self.rows)
        changes = ({'token': 0}, {'token': 1 << 31}, {'depth': 0}, {'depth': 257},
            {'fill_index': 0}, {'fill_index': 2}, {'frame_id': 0}, {'frame_id': 120001},
            {'wall_ns': -1}, {'loot_exclusive_ns': -1}, {'nano_start': -(1 << 63)-1},
            {'nano_end': 1 << 63}, {'factory_nonnull': 11})
        for change in changes:
            with self.subTest(change=change):
                self.rows = copy.deepcopy(original)
                self.rows[0].update(change)
                self.write()
                with self.assertRaises(ValueError):
                    self.report()
        for counter in loot.COUNTERS:
            for value in (-1, 1 << 63, '+1', '01', '1.0', ' 1', ''):
                with self.subTest(counter=counter, value=value):
                    self.rows = copy.deepcopy(original)
                    self.rows[0][counter] = value
                    self.write()
                    with self.assertRaises(ValueError):
                        self.report()

    def test_duplicate_token_missing_and_out_of_order_frames(self):
        original = copy.deepcopy(self.rows)
        for index, change in ((1, {'token': 1}), (0, {'frame_id': 1}),
                (5, {'frame_id': 4}), (4, {'frame_id': 3}), (5, {'frame_id': 2})):
            with self.subTest(index=index, change=change):
                self.rows = copy.deepcopy(original)
                self.rows[index].update(change)
                self.write()
                with self.assertRaises(ValueError):
                    self.report()

    def test_interval_partition_and_stage_join_corruption(self):
        original_rows, original_stages = copy.deepcopy(self.rows), copy.deepcopy(self.stages)
        changes = ({'nano_start': 219}, {'nano_end': 321}, {'wall_ns': 49},
            {'loot_exclusive_ns': 29}, {'logic_exclusive_ns': 31, 'loot_exclusive_ns': 0,
                'chunk_exclusive_ns': 9, 'lua_exclusive_ns': 10})
        for change in changes:
            with self.subTest(change=change):
                self.rows = copy.deepcopy(original_rows)
                self.rows[0].update(change)
                self.write()
                with self.assertRaises(ValueError):
                    self.report()
        self.rows = original_rows
        for change in ({'loot_calls': 4}, {'loot_calls': 6}, {'loot_inclusive_ns': 69},
                {'loot_exclusive_ns': 46}, {'lua_exclusive_ns': 14}, {'phase': 4}):
            with self.subTest(stage=change):
                self.stages = copy.deepcopy(original_stages)
                self.stages[1].update(change)
                self.write()
                with self.assertRaises(ValueError):
                    self.report()

    def test_nesting_requires_containment_order_and_complete_parent(self):
        original = copy.deepcopy(self.rows)
        changes = ((0, {'depth': 2}), (1, {'depth': 3}), (2, {'depth': 2}),
            (2, {'nano_start': 248, 'nano_end': 252}),
            (3, {'nano_start': 249, 'nano_end': 259}),
            (4, {'nano_start': 275, 'nano_end': 295}))
        for index, change in changes:
            with self.subTest(index=index, change=change):
                self.rows = copy.deepcopy(original)
                self.rows[index].update(change)
                self.write()
                with self.assertRaises(ValueError):
                    self.report()

    def test_sibling_exclusive_and_inclusive_counter_sums_must_fit_parent(self):
        original = copy.deepcopy(self.rows)
        # Individually each sibling fits; together the stage or call deltas do not.
        self.rows[1].update(loot_exclusive_ns=2, chunk_exclusive_ns=8)
        self.rows[3].update(loot_exclusive_ns=2, chunk_exclusive_ns=8, lua_exclusive_ns=0)
        self.write()
        with self.assertRaisesRegex(ValueError, 'sibling counters'):
            self.report()
        for counter in loot.COUNTERS:
            with self.subTest(counter=counter):
                self.rows = copy.deepcopy(original)
                value = self.rows[0][counter]
                self.rows[1][counter] = value
                self.rows[3][counter] = value
                if counter == 'factory_nonnull':
                    self.rows[1]['factory_calls'] = value
                    self.rows[3]['factory_calls'] = value
                self.write()
                with self.assertRaisesRegex(ValueError, 'sibling counters'):
                    self.report()

    def test_aggregate_counter_overflow_across_top_level_fills_and_frames(self):
        for index in (4, 5):
            with self.subTest(index=index):
                self.rows[0]['chance_calls'] = loot.MAX_LONG
                self.rows[index]['chance_calls'] = 1
                self.write()
                with self.assertRaisesRegex(ValueError, 'Overflowing loot total'):
                    self.report()
                self.rows[index]['chance_calls'] = 0
        # Child totals also use checked arithmetic rather than wrapping.
        self.rows[1]['chance_calls'] = loot.MAX_LONG
        self.rows[3]['chance_calls'] = 1
        self.write()
        with self.assertRaisesRegex(ValueError, 'Overflowing loot total'):
            self.report()

    def test_truncated_extra_and_mismatched_status_rows(self):
        original = copy.deepcopy(self.rows)
        for rows in (original[:-1], original[1:], original + [dict(original[-1], fill_index=7)]):
            with self.subTest(rows=len(rows)):
                self.rows = rows
                self.write()
                with self.assertRaises(ValueError):
                    self.report()
        self.rows = original
        for count in (5, 7):
            self.status['complete_fills'] = count
            self.write()
            with self.assertRaises(ValueError):
                self.report()
        self.status['complete_fills'] = 6
        self.write()
        with self.assertRaisesRegex(ValueError, 'completed frame count'):
            self.report(frames=4)

    def test_exact_status_contract_and_capacity(self):
        original = dict(self.status)
        for change in ({'version': 2}, {'capacity': 119999}, {'max_depth': 255},
                {'diagnostic': 'overflow'}, {'complete_fills': 120001}, {'omitted_fills': -1},
                {'omitted_fills': 1 << 31}, {'semantics': 'cpu'}, {'nested_rows': 'disjoint'},
                {'counters': 'items'}, {'extra': 1}):
            with self.subTest(change=change):
                self.status = dict(original, **change)
                self.write()
                with self.assertRaises(ValueError):
                    self.report()
        self.status = original
        self.write()
        with patch.object(loot, 'MAX_FILLS', 5):
            with self.assertRaises(ValueError):
                list(loot._rows(self.cache / 'driving-loot.csv'))
        status_path = self.cache / 'driving-loot-status.txt'
        for suffix in (' version=1', '\nextra=1', ' '):
            self.write()
            status_path.write_text(status_path.read_text().rstrip('\n') + suffix)
            with self.assertRaises(ValueError):
                self.report()

    def test_exact_csv_shape_partial_records_missing_artifacts_and_quotes(self):
        for columns in (loot.LOOT_COLUMNS[:-1], loot.LOOT_COLUMNS[::-1], loot.LOOT_COLUMNS + ('extra',)):
            self.write(columns=columns)
            with self.assertRaises(ValueError):
                self.report()
        for tail in ('"unterminated', '1,2,3\n', ','.join(['1'] * (len(loot.LOOT_COLUMNS) + 1)) + '\n'):
            self.write()
            with (self.cache / 'driving-loot.csv').open('a') as target:
                target.write(tail)
            with self.assertRaises(ValueError):
                self.report()
        for name in ('driving-loot.csv', 'driving-loot-status.txt', 'driving-stages.csv'):
            self.write()
            (self.cache / name).unlink()
            with self.assertRaisesRegex(ValueError, 'Missing loot'):
                self.report()


if __name__ == '__main__':
    unittest.main()
