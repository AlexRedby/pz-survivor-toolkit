"""Chunk invocation joins, overlap accounting and corrupt evidence; no game/JVM."""
import copy
import csv
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import chunk_metrics as chunks
from queue_checks.adapters import optimizer_benchmark as benchmark


class ChunkMetricsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='chunk-metrics-')
        self.addCleanup(self.temporary.cleanup)
        self.cache = Path(self.temporary.name)
        self.stages = []
        for phase in (1, 2, 3):
            stage = dict.fromkeys(benchmark.STAGE_COLUMNS, 0)
            stage.update(frame_id=phase, phase=phase, nano_start=phase * 110,
                nano_end=phase * 110 + 100, wall_ns=100, cpu_ns=-1, other_exclusive_ns=100)
            self.stages.append(stage)
        self.stages[1].update(chunk_calls=5, chunk_inclusive_ns=70, chunk_exclusive_ns=45,
            loot_exclusive_ns=10, lua_exclusive_ns=15, logic_exclusive_ns=30, other_exclusive_ns=0)
        self.stages[2].update(chunk_calls=1, chunk_inclusive_ns=50, chunk_exclusive_ns=30,
            lua_exclusive_ns=40, logic_exclusive_ns=30, other_exclusive_ns=0)
        self.rows = []
        for frame, token, depth, start, end, chunk, loot, lua in (
                (2, 1, 1, 230, 280, 30, 10, 10),
                (2, 2, 2, 240, 250, 5, 5, 0),
                (2, 3, 3, 242, 246, 2, 2, 0),
                (2, 4, 2, 260, 270, 5, 0, 5),
                (2, 5, 1, 290, 310, 15, 0, 5),
                (3, 1, 1, 340, 390, 30, 0, 20)):
            row = dict.fromkeys(chunks.CHUNK_COLUMNS, 0)
            row.update(frame_id=frame, chunk_index=len(self.rows) + 1, token=token, depth=depth,
                wx=-1, wy=42, queue_depth_before=3, queue_depth_after=2,
                nano_start=start, nano_end=end, wall_ns=end-start,
                chunk_exclusive_ns=chunk, loot_exclusive_ns=loot, lua_exclusive_ns=lua)
            self.rows.append(row)
        self.status = dict(version=1, complete_chunks=6, omitted_chunks=1, capacity=120000,
            max_depth=256, diagnostic='none',
            semantics='per_chunk_inclusive_wall_exclusive_stage_partition',
            nested_rows='overlap', queue_depth='O1_observed_after_dequeue_not_wait')
        self.write()

    def csv(self, name, columns, rows):
        with (self.cache / name).open('w', newline='', encoding='utf-8') as target:
            writer = csv.DictWriter(target, fieldnames=columns, extrasaction='ignore')
            writer.writeheader()
            writer.writerows(rows)

    def write(self, columns=None):
        self.csv('driving-stages.csv', benchmark.STAGE_COLUMNS, self.stages)
        self.csv('driving-chunks.csv', columns or chunks.CHUNK_COLUMNS, self.rows)
        (self.cache / 'driving-chunks-status.txt').write_text(
            ' '.join(key + '=' + str(value) for key, value in self.status.items()) + '\n')

    def report(self, frames=3):
        return chunks.chunk_metrics(self.cache, {'complete_frames': frames})

    def test_nested_wall_union_counters_phases_and_zero_chunk_frame(self):
        report = self.report()
        self.assertEqual((report['complete_frames'], report['complete_chunks'], report['omitted_chunks']), (3, 6, 1))
        overall = report['groups']['overall']
        self.assertEqual((overall['frames'], overall['chunks'], overall['top_level_chunks']), (3, 6, 3))
        self.assertEqual(overall['max_frame_chunks'], 5)
        self.assertAlmostEqual(overall['wall_ms'], 120 / 1e6)
        self.assertAlmostEqual(overall['stage_exclusive_ms']['chunk'], 75 / 1e6)
        self.assertAlmostEqual(overall['stage_exclusive_ms']['loot'], 10 / 1e6)
        self.assertAlmostEqual(overall['stage_exclusive_ms']['lua'], 35 / 1e6)
        self.assertEqual(overall['max_single_chunk']['chunk_index'], 1)
        self.assertAlmostEqual(overall['max_single_chunk_ms'], 50 / 1e6)
        self.assertEqual(overall['mean_chunks_per_frame'], 2)
        self.assertEqual([row['chunks'] for row in report['per_frame']], [0, 5, 1])
        self.assertEqual(report['groups']['phase1']['wall_ms'], 0)
        self.assertIsNone(report['groups']['phase1']['max_queue_depth'])
        self.assertEqual(report['groups']['phase2']['chunks'], 5)
        self.assertIn('wall', report['attribution'])
        self.assertIn('not queue wait', ' '.join(report['limits']))

    def test_queue_snapshots_and_coordinates_are_signed_ints(self):
        self.rows[2].update(queue_depth_before=-1, queue_depth_after=17, wx=-(1 << 31), wy=(1 << 31)-1)
        self.write()
        overall = self.report()['groups']['overall']
        self.assertEqual((overall['min_queue_depth'], overall['max_queue_depth']), (-1, 17))
        for key in ('wx', 'wy', 'queue_depth_before', 'queue_depth_after'):
            with self.subTest(key=key):
                previous = self.rows[2][key]
                self.rows[2][key] = 1 << 31
                self.write()
                with self.assertRaises(ValueError):
                    self.report()
                self.rows[2][key] = previous

    def test_complete_zero_chunk_profile_and_empty_phase(self):
        self.rows = []
        self.status.update(complete_chunks=0, omitted_chunks=0)
        for stage in self.stages:
            stage.update(chunk_calls=0, chunk_inclusive_ns=0, chunk_exclusive_ns=0)
        self.stages[2]['phase'] = 2
        self.write()
        report = self.report()
        self.assertEqual(report['complete_chunks'], 0)
        self.assertEqual(report['groups']['overall']['wall_ms'], 0)
        self.assertIsNone(report['groups']['overall']['max_single_chunk'])
        self.assertEqual(report['groups']['phase3']['frames'], 0)
        self.assertIsNone(report['groups']['phase3']['mean_chunks_per_frame'])

    def test_invalid_integer_and_row_fields(self):
        original = copy.deepcopy(self.rows)
        changes = ({'token': 0}, {'token': 1 << 31}, {'depth': 0}, {'depth': 257},
            {'chunk_index': 0}, {'chunk_index': 2}, {'frame_id': 0}, {'frame_id': 120001},
            {'wall_ns': -1}, {'chunk_exclusive_ns': -1}, {'wx': '+1'}, {'wx': '01'},
            {'wy': '1.0'}, {'token': ' 1'}, {'nano_start': -(1 << 63)-1}, {'nano_end': 1 << 63})
        for change in changes:
            with self.subTest(change=change):
                self.rows = copy.deepcopy(original)
                self.rows[0].update(change)
                self.write()
                with self.assertRaises(ValueError):
                    self.report()

    def test_duplicate_token_and_missing_or_out_of_order_frame(self):
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
        changes = ((0, {'nano_start': 219}), (0, {'nano_end': 321}), (0, {'wall_ns': 49}),
            (0, {'chunk_exclusive_ns': 29}), (0, {'logic_exclusive_ns': 31, 'chunk_exclusive_ns': 0,
                'loot_exclusive_ns': 9, 'lua_exclusive_ns': 10}))
        for index, change in changes:
            with self.subTest(change=change):
                self.rows = copy.deepcopy(original_rows)
                self.rows[index].update(change)
                self.write()
                with self.assertRaises(ValueError):
                    self.report()
        self.rows = original_rows
        for change in ({'chunk_calls': 4}, {'chunk_calls': 6}, {'chunk_inclusive_ns': 69},
                {'chunk_exclusive_ns': 46}, {'lua_exclusive_ns': 14}):
            with self.subTest(stage=change):
                self.stages = copy.deepcopy(original_stages)
                self.stages[1].update(change)
                self.write()
                with self.assertRaises(ValueError):
                    self.report()

    def test_nesting_requires_contained_ordered_siblings_and_complete_parent(self):
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

    def test_sibling_counter_sum_cannot_exceed_parent(self):
        # Each child individually fits the parent and frame. Together their loot
        # deltas exceed the parent, so a simple per-row bound would miss this.
        self.rows[1].update(chunk_exclusive_ns=2, loot_exclusive_ns=8)
        self.rows[3].update(chunk_exclusive_ns=2, loot_exclusive_ns=8, lua_exclusive_ns=0)
        self.write()
        with self.assertRaisesRegex(ValueError, 'sibling counters'):
            self.report()

    def test_truncated_extra_and_mismatched_status_rows(self):
        original = copy.deepcopy(self.rows)
        for rows in (original[:-1], original[1:], original + [dict(original[-1], chunk_index=7)]):
            with self.subTest(rows=len(rows)):
                self.rows = rows
                self.write()
                with self.assertRaises(ValueError):
                    self.report()
        self.rows = original
        for count in (5, 7):
            self.status['complete_chunks'] = count
            self.write()
            with self.assertRaises(ValueError):
                self.report()
        self.status['complete_chunks'] = 6
        self.write()
        with self.assertRaisesRegex(ValueError, 'completed frame count'):
            self.report(frames=4)

    def test_exact_status_contract_and_capacity_limits(self):
        original = dict(self.status)
        changes = ({'version': 2}, {'capacity': 119999}, {'max_depth': 255},
            {'diagnostic': 'overflow'}, {'complete_chunks': 120001}, {'omitted_chunks': -1},
            {'semantics': 'cpu'}, {'nested_rows': 'disjoint'}, {'queue_depth': 'wait'}, {'extra': 1})
        for change in changes:
            with self.subTest(change=change):
                self.status = dict(original, **change)
                self.write()
                with self.assertRaises(ValueError):
                    self.report()
        self.status = original
        self.write()
        with patch.object(chunks, 'MAX_CHUNKS', 5):
            with self.assertRaises(ValueError):
                list(chunks._rows(self.cache / 'driving-chunks.csv'))
        status_path = self.cache / 'driving-chunks-status.txt'
        for suffix in (' version=1', '\nextra=1', ' '):
            self.write()
            status_path.write_text(status_path.read_text().rstrip('\n') + suffix)
            with self.assertRaises(ValueError):
                self.report()

    def test_exact_csv_shape_missing_files_and_malformed_quotes(self):
        for columns in (chunks.CHUNK_COLUMNS[:-1], chunks.CHUNK_COLUMNS[::-1],
                chunks.CHUNK_COLUMNS + ('extra',)):
            self.write(columns=columns)
            with self.assertRaises(ValueError):
                self.report()
        self.write()
        path = self.cache / 'driving-chunks.csv'
        with path.open('a') as target:
            target.write('"unterminated')
        with self.assertRaises(ValueError):
            self.report()
        for name in ('driving-chunks.csv', 'driving-chunks-status.txt'):
            self.write()
            (self.cache / name).unlink()
            with self.assertRaisesRegex(ValueError, 'Missing chunk'):
                self.report()


if __name__ == '__main__':
    unittest.main()
