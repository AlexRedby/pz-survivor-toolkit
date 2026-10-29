"""Independent tile-stack artifacts joined to validated stages; no game or JVM."""
import copy
import csv
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import tile_metrics as tiles
from queue_checks.adapters import optimizer_benchmark as benchmark


class TileMetricsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='tile-metrics-')
        self.addCleanup(self.temporary.cleanup)
        self.cache = Path(self.temporary.name)
        self.stages, self.rows = [], []
        for phase, speed in enumerate((0, 10, 30), 1):
            stage = dict.fromkeys(benchmark.STAGE_COLUMNS, 0)
            stage.update(frame_id=phase, phase=phase, speed_kmh=speed, nano_start=phase * 110,
                         nano_end=phase * 110 + 100, wall_ns=100, cpu_ns=-1, other_exclusive_ns=100)
            self.stages.append(stage)
            row = dict.fromkeys(tiles.TILE_COLUMNS, 0)
            row.update({key: stage[key] for key in ('frame_id', 'nano_start', 'nano_end', 'wall_ns')})
            row['other_exclusive_ns'] = 100
            self.rows.append(row)
        # Nested categories are nonadditive; repeated child calls can exceed root calls.
        self.rows[1].update(tiles_internal_inclusive_ns=80, tiles_internal_exclusive_ns=20,
            tiles_internal_calls=2, perform_inclusive_ns=60, perform_exclusive_ns=30, perform_calls=3,
            chunk_inclusive_ns=30, chunk_exclusive_ns=30, chunk_calls=2, other_exclusive_ns=20)
        self.rows[2].update(tiles_internal_inclusive_ns=90, tiles_internal_exclusive_ns=20,
            tiles_internal_calls=1, perform_inclusive_ns=70, perform_exclusive_ns=20, perform_calls=1,
            moving_inclusive_ns=30, moving_exclusive_ns=20, moving_calls=4,
            items_inclusive_ns=30, items_exclusive_ns=20, items_calls=2,
            preparation_inclusive_ns=10, preparation_exclusive_ns=10, preparation_calls=1, other_exclusive_ns=10)
        self.status = dict(version='1', complete_frames='3', max_frames='120000', diagnostic='none',
            coverage='renderTilesInternal-descendants', inclusive='category-union-nonadditive',
            exclusive='tile-stack-only', partition='exclusive-plus-other-equals-wall', profile='native')
        self.stage_profile = 'native'
        self.write()

    def csv(self, name, columns, rows):
        with (self.cache / name).open('w', newline='', encoding='utf-8') as target:
            writer = csv.DictWriter(target, fieldnames=columns, extrasaction='ignore')
            writer.writeheader()
            writer.writerows(rows)

    def write(self):
        self.csv('driving-stages.csv', benchmark.STAGE_COLUMNS, self.stages)
        (self.cache / 'driving-stages-status.txt').write_text(
            'complete_frames=3 omitted_incomplete_frames=1 cpu_supported_and_enabled=false diagnostic=none '
            'phase_contacts_speed=snapshot-at-frame-begin exclusive_plus_other=wall inclusive=category-union-nonadditive '
            'detail=independent-nonadditive fog=renderFog-whole translucent_total=whole-method '
            'translucent_merge=after-tempSquares-clear-to-doSort-including-profiler-and-sort-arguments '
            'translucent_sort=TimSort.doSort-call partial-details-on-throwable=included '
            'tile_details=method-boundaries-v1 tile_profile=' + self.stage_profile + '\n')
        jfr = bytearray(69)
        jfr[:4] = b'FLR\0'
        jfr[4:6] = (2).to_bytes(2, 'big')
        jfr[8:16] = len(jfr).to_bytes(8, 'big')
        (self.cache / 'driving-stages.jfr').write_bytes(jfr)
        self.csv('driving-tiles.csv', tiles.TILE_COLUMNS, self.rows)
        (self.cache / 'driving-tiles-status.txt').write_text(
            ' '.join(key + '=' + str(value) for key, value in self.status.items()) + '\n')

    def evidence(self):
        return benchmark.stage_metrics(self.cache)

    def report(self):
        return self.evidence()['tile_timings']

    def test_nested_union_reentry_empty_frame_and_phase_speed_summaries(self):
        report = self.report()
        self.assertEqual((report['complete_frames'], report['profile']), (3, 'native'))
        overall = report['groups']['overall']
        self.assertEqual(overall['frames'], 3)
        self.assertAlmostEqual(overall['frame_wall_ms'], 300 / 1e6)
        self.assertAlmostEqual(overall['other_exclusive_ms'], 130 / 1e6)
        root = overall['tile_wall']['tiles_internal']
        self.assertEqual(root['calls'], 3)
        self.assertAlmostEqual(root['inclusive_ms'], 170 / 1e6)
        self.assertAlmostEqual(root['exclusive_ms'], 40 / 1e6)
        self.assertAlmostEqual(root['max_frame_inclusive_ms'], 90 / 1e6)
        self.assertAlmostEqual(root['max_frame_exclusive_ms'], 20 / 1e6)
        self.assertAlmostEqual(root['mean_per_frame_inclusive_ms'], 170 / 3e6)
        self.assertAlmostEqual(root['mean_per_frame_exclusive_ms'], 40 / 3e6)
        self.assertAlmostEqual(root['mean_calls_per_frame'], 1)
        self.assertEqual(tiles.GROUPS[-1], 'preparation')
        self.assertEqual(overall['tile_wall']['preparation']['calls'], 1)
        self.assertAlmostEqual(overall['tile_wall']['preparation']['exclusive_ms'], 10 / 1e6)
        self.assertGreater(sum(value['inclusive_ms'] for value in overall['tile_wall'].values()), overall['frame_wall_ms'])
        for group, frames, calls in (('stationary', 1, 0), ('moving10', 2, 3), ('moving30', 1, 1),
                                     ('phase1', 1, 0), ('phase2', 1, 2), ('phase3', 1, 1)):
            self.assertEqual(report['groups'][group]['frames'], frames)
            self.assertEqual(report['groups'][group]['tile_wall']['tiles_internal']['calls'], calls)
        self.assertIn('nonadditive', report['attribution'])
        self.assertTrue(any('do not establish optimization gain' in limit for limit in report['limits']))

    def test_speed_boundaries_and_empty_summary_means(self):
        for stage, speed in zip(self.stages, (1, 9.999, 29.999)):
            stage['speed_kmh'] = speed
        self.write()
        groups = self.report()['groups']
        self.assertEqual(groups['stationary']['frames'], 0)
        self.assertEqual(groups['moving10']['frames'], 1)
        self.assertEqual(groups['moving30']['frames'], 0)
        self.assertIsNone(groups['moving30']['tile_wall']['tiles_internal']['mean_per_frame_inclusive_ms'])
        self.assertIsNone(groups['moving30']['tile_wall']['items']['mean_calls_per_frame'])

    def test_zero_duration_calls_and_large_reentry_counts_are_valid(self):
        self.rows[0].update(tiles_internal_calls=2, perform_calls=tiles.MAX_CALLS)
        self.write()
        self.assertEqual(self.report()['groups']['stationary']['tile_wall']['perform']['calls'], tiles.MAX_CALLS)

    def test_rejects_corrupt_timing_partition_call_and_integer_bounds(self):
        changes = {
            'float integer': {'wall_ns': '100.0'}, 'nonfinite integer': {'perform_calls': 'nan'},
            'overflow timestamp': {'nano_start': 1 << 63}, 'negative calls': {'perform_calls': -1},
            'overflow calls': {'perform_calls': tiles.MAX_CALLS + 1},
            'negative timing': {'perform_exclusive_ns': -1}, 'exclusive exceeds inclusive': {'perform_exclusive_ns': 61},
            'child exceeds root': {'chunk_inclusive_ns': 81}, 'root exceeds wall': {'tiles_internal_inclusive_ns': 101},
            'timing without call': {'chunk_calls': 0}, 'root timing without call': {'tiles_internal_calls': 0},
            'wall partition': {'other_exclusive_ns': 21},
            'root partition': {'tiles_internal_exclusive_ns': 19, 'other_exclusive_ns': 21},
            'negative other': {'other_exclusive_ns': -1},
        }
        original = copy.deepcopy(self.rows)
        for label, change in changes.items():
            with self.subTest(label=label):
                self.rows = copy.deepcopy(original)
                self.rows[1].update(change)
                self.write()
                with self.assertRaises(ValueError):
                    self.report()
        self.rows = copy.deepcopy(original)
        self.rows[0]['perform_calls'] = 1
        self.write()
        with self.assertRaisesRegex(ValueError, 'child call without root'):
            self.report()

    def test_native_forbids_optimizer_only_calls_and_official_allows_them(self):
        for category in tiles.OPTIMIZER_ONLY:
            with self.subTest(category=category):
                self.rows[0].update(tiles_internal_calls=1, **{category + '_calls': 1})
                self.write()
                with self.assertRaisesRegex(ValueError, 'Optimizer-only'):
                    self.report()
                self.rows[0][category + '_calls'] = 0
        self.rows[0]['schedule_calls'] = 1
        self.status['profile'] = self.stage_profile = 'official'
        self.write()
        self.assertEqual(self.report()['groups']['phase1']['tile_wall']['schedule']['calls'], 1)
        self.stage_profile = 'native'
        self.write()
        with self.assertRaisesRegex(ValueError, 'profile mismatch'):
            self.report()

    def test_native_and_official_allow_actual_composite_work(self):
        self.rows[0].update(tiles_internal_calls=1, tiles_internal_inclusive_ns=10,
            composite_calls=1, composite_inclusive_ns=10, composite_exclusive_ns=10, other_exclusive_ns=90)
        for profile in ('native', 'official'):
            with self.subTest(profile=profile):
                self.status['profile'] = self.stage_profile = profile
                self.write()
                composite = self.report()['groups']['phase1']['tile_wall']['composite']
                self.assertEqual(composite['calls'], 1)
                self.assertAlmostEqual(composite['exclusive_ms'], 10 / 1e6)

    def test_stage_integration_requires_declared_valid_tiles_and_accepts_old_capture(self):
        stage_status = self.cache / 'driving-stages-status.txt'
        declared = stage_status.read_text()
        stage_status.write_text(declared.replace(' tile_details=method-boundaries-v1 tile_profile=native', ''))
        for name in ('driving-tiles.csv', 'driving-tiles-status.txt'):
            (self.cache / name).unlink()
        old = benchmark.stage_metrics(self.cache)
        self.assertNotIn('tile_timings', old)
        self.assertNotIn('tile_profile', old)
        # A tile artifact cannot silently escape validation in an old-format capture.
        (self.cache / 'driving-tiles.csv').write_text('')
        with self.assertRaisesRegex(ValueError, 'Undeclared tile detail artifacts'):
            benchmark.stage_metrics(self.cache)
        for name in ('driving-tiles.csv', 'driving-tiles-status.txt'):
            self.write()
            (self.cache / name).unlink()
            with self.assertRaisesRegex(ValueError, 'Missing tile profile artifact'):
                benchmark.stage_metrics(self.cache)
        self.status['diagnostic'] = 'overflow'
        self.write()
        with self.assertRaisesRegex(ValueError, 'invalid tile profile status'):
            benchmark.stage_metrics(self.cache)
        self.status.update(diagnostic='none', profile='official')
        self.write()
        with self.assertRaisesRegex(ValueError, 'profile mismatch'):
            benchmark.stage_metrics(self.cache)

    def test_rejects_nonexact_frame_join_including_truncated_prefix(self):
        original = copy.deepcopy(self.rows)
        variants = [original[:2], original[1:], original + [dict(original[-1], frame_id=4)],
                    [original[0], original[2], original[1]], [original[0], original[1], original[1]]]
        for key in ('frame_id', 'nano_start', 'nano_end', 'wall_ns'):
            changed = copy.deepcopy(original)
            changed[1][key] += 1
            variants.append(changed)
        for rows in variants:
            with self.subTest(rows=rows):
                self.rows = rows
                self.write()
                with self.assertRaisesRegex(ValueError, 'completed stage frame'):
                    self.report()

    def test_rejects_missing_duplicate_extra_or_reordered_columns_and_bad_rows(self):
        columns = tiles.TILE_COLUMNS
        for invalid in (columns[:-1], (*columns, 'extra'), (*columns[:-1], columns[0]), tuple(reversed(columns))):
            self.csv('driving-tiles.csv', invalid, self.rows)
            with self.assertRaisesRegex(ValueError, 'columns/order'):
                self.report()
        for invalid in ('1,2\n', ','.join('0' for _ in range(len(columns) + 1)) + '\n'):
            self.write()
            with (self.cache / 'driving-tiles.csv').open('a') as target:
                target.write(invalid)
            with self.assertRaisesRegex(ValueError, 'row shape'):
                self.report()

    def test_malformed_csv_fails_as_validation_error(self):
        with (self.cache / 'driving-tiles.csv').open('a') as target:
            target.write('"unterminated\n')
        with self.assertRaisesRegex(ValueError, 'Malformed tile CSV'):
            self.report()

    def test_rejects_failed_stale_or_nonexact_status(self):
        original = dict(self.status)
        for key, value in (('version', '2'), ('complete_frames', '2'), ('complete_frames', '0'),
                           ('complete_frames', '120001'), ('diagnostic', 'overflow'), ('max_frames', '6000'),
                           ('coverage', 'unknown'), ('inclusive', 'additive'), ('exclusive', 'stage-stack'),
                           ('partition', 'unknown'), ('profile', 'unknown'), ('extra', '1')):
            with self.subTest(key=key, value=value):
                self.status = dict(original, **{key: value})
                self.write()
                with self.assertRaises(ValueError):
                    self.report()
        self.status = original
        self.write()
        path = self.cache / 'driving-tiles-status.txt'
        text = path.read_text()
        for invalid in (text.rstrip() + ' diagnostic=none\n', text + '\n', text.replace('version=1 ', ''),
                        text.replace('version=1 ', 'version=1\t'), text.replace('version=1 ', 'version=1  ')):
            path.write_text(invalid)
            with self.assertRaises(ValueError):
                self.report()

    def test_requires_artifacts_and_uses_passed_stage_validation_without_recursion(self):
        evidence = self.evidence()
        with patch.object(benchmark, 'stage_metrics', side_effect=AssertionError('recursive stage validation')):
            self.assertEqual(tiles.tile_metrics(self.cache, evidence)['complete_frames'], 3)
        with self.assertRaisesRegex(ValueError, 'profile mismatch'):
            tiles.tile_metrics(self.cache, dict(evidence, tile_profile=None))
        for name in ('driving-tiles.csv', 'driving-tiles-status.txt'):
            self.write()
            (self.cache / name).unlink()
            with self.assertRaisesRegex(ValueError, 'Missing tile profile artifact'):
                tiles.tile_metrics(self.cache, evidence)

    def test_capacity_and_status_count_are_bounded(self):
        self.status['max_frames'] = '3'
        self.write()
        with patch.object(tiles, 'MAX_FRAMES', 3):
            self.assertEqual(self.report()['complete_frames'], 3)
            self.rows.append(dict(self.rows[-1], frame_id=3))
            self.write()
            with self.assertRaisesRegex(ValueError, 'capacity'):
                self.report()
        self.rows = self.rows[:3]
        self.status['max_frames'] = '120000'
        self.write()
        evidence = self.evidence()
        evidence['complete_frames'] = 4
        with self.assertRaisesRegex(ValueError, 'frame count mismatch'):
            tiles.tile_metrics(self.cache, evidence)


if __name__ == '__main__':
    unittest.main()
