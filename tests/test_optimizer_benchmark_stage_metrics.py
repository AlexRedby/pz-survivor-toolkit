"""Bounded stage diagnostic evidence and optional benchmark-report integration; no game process."""
import copy
import csv
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks.adapters import optimizer_benchmark as benchmark


class StageMetricsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='stage-metrics-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.cache = self.root / 'client1'
        self.cache.mkdir()
        self.rows = []
        for phase in (1, 2, 3):
            row = {column: 0 for column in benchmark.STAGE_COLUMNS}
            row.update(frame_id=phase, phase=phase, contacts=phase - 1, speed_kmh=12.5,
                       nano_start=phase * 110, nano_end=phase * 110 + 100, wall_ns=100, cpu_ns=80,
                       render_inclusive_ns=100, render_exclusive_ns=100, render_calls=1,
                       fog_inclusive_ns=20, fog_exclusive_ns=20, fog_calls=1,
                       translucent_total_inclusive_ns=50, translucent_total_exclusive_ns=20, translucent_total_calls=2,
                       translucent_merge_inclusive_ns=20, translucent_merge_exclusive_ns=20, translucent_merge_calls=1,
                       translucent_sort_inclusive_ns=10, translucent_sort_exclusive_ns=10, translucent_sort_calls=1)
            self.rows.append(row)
        self.status = ('complete_frames=3 omitted_incomplete_frames=1 cpu_supported_and_enabled=true diagnostic=none '
            'phase_contacts_speed=snapshot-at-frame-begin exclusive_plus_other=wall inclusive=category-union-nonadditive '
            'detail=independent-nonadditive fog=renderFog-whole translucent_total=whole-method '
            'translucent_merge=after-tempSquares-clear-to-doSort-including-profiler-and-sort-arguments '
            'translucent_sort=TimSort.doSort-call partial-details-on-throwable=included\n')
        # Structural JFR fixture only: the validator deliberately does not decode events.
        self.jfr = bytearray(69)
        self.jfr[:4] = b'FLR\0'
        self.jfr[4:6] = (2).to_bytes(2, 'big')
        self.jfr[8:16] = len(self.jfr).to_bytes(8, 'big')
        self.write()

    def write(self, columns=None):
        with (self.cache / 'driving-stages.csv').open('w', newline='') as target:
            writer = csv.DictWriter(target, fieldnames=columns or benchmark.STAGE_COLUMNS, extrasaction='ignore')
            writer.writeheader()
            writer.writerows(self.rows)
        (self.cache / 'driving-stages-status.txt').write_text(self.status)
        (self.cache / 'driving-stages.jfr').write_bytes(self.jfr)

    def test_reports_actual_nonadditive_wall_cost_by_phase_and_overall(self):
        report = benchmark.stage_metrics(self.cache)
        self.assertEqual(report['complete_frames'], 3)
        self.assertEqual(report['omitted_incomplete_frames'], 1)
        self.assertIn('nonadditive', report['attribution'])
        total = report['groups']['overall']
        self.assertAlmostEqual(total['frame_wall_ms'], 300 / 1e6)
        for stage, nanoseconds in [('fog', 20), ('translucent_merge', 20), ('translucent_sort', 10)]:
            self.assertAlmostEqual(total['detail_wall'][stage]['inclusive_ms'], 3 * nanoseconds / 1e6)
            self.assertEqual(total['detail_wall'][stage]['calls'], 3)
            self.assertAlmostEqual(report['groups']['phase2']['detail_wall'][stage]['inclusive_ms'], nanoseconds / 1e6)

    def test_zero_fog_and_early_return_only_translucent_are_valid(self):
        for row in self.rows:
            for stage in ('fog', 'translucent_merge', 'translucent_sort'):
                for suffix in ('_inclusive_ns', '_exclusive_ns', '_calls'):
                    row[stage + suffix] = 0
            row['translucent_total_exclusive_ns'] = row['translucent_total_inclusive_ns']
        self.write()
        self.assertEqual(benchmark.stage_metrics(self.cache)['groups']['overall']['detail_wall']['fog']['calls'], 0)

    def test_rejects_corrupt_rows(self):
        changes = {
            'NaN speed': {'speed_kmh': 'nan'}, 'infinite speed': {'speed_kmh': 'inf'},
            'negative speed': {'speed_kmh': -1}, 'float integer': {'wall_ns': '100.0'},
            'wall mismatch': {'nano_end': 211}, 'zero wall': {'wall_ns': 0},
            'invalid CPU sentinel': {'cpu_ns': -2}, 'integer overflow': {'nano_start': 1 << 64},
            'negative exclusive': {'fog_exclusive_ns': -1}, 'inclusive below exclusive': {'fog_inclusive_ns': 1},
            'timing outside frame': {'fog_inclusive_ns': 101}, 'timing without call': {'fog_calls': 0},
            'negative calls': {'fog_calls': -1}, 'exclusive partition': {'other_exclusive_ns': 1},
            'nested detail mismatch': {'translucent_total_exclusive_ns': 21},
            'sort child mismatch': {'translucent_sort_exclusive_ns': 9},
            'more sorts than merges': {'translucent_sort_calls': 2},
            'more merges than totals': {'translucent_merge_calls': 3},
            'invalid phase': {'phase': 4}, 'negative contacts': {'contacts': -1}, 'zero frame ID': {'frame_id': 0}, 'frame ID overflow': {'frame_id': 120001},
        }
        original = copy.deepcopy(self.rows)
        for label, change in changes.items():
            with self.subTest(label=label):
                self.rows = copy.deepcopy(original)
                self.rows[0].update(change)
                self.write()
                with self.assertRaises(ValueError):
                    benchmark.stage_metrics(self.cache)

    def test_rejects_unordered_frames_and_wrong_counts(self):
        original = copy.deepcopy(self.rows)
        for change in ({'frame_id': 1}, {'nano_start': 209, 'nano_end': 309}, {'phase': 1, 'contacts': 0}):
            self.rows = copy.deepcopy(original)
            self.rows[1].update(change)
            if change.get('phase') == 1:
                self.rows[0]['phase'] = 2
            self.write()
            with self.assertRaises(ValueError):
                benchmark.stage_metrics(self.cache)
        self.rows = original[:2]
        self.write()
        with self.assertRaisesRegex(ValueError, 'count mismatch'):
            benchmark.stage_metrics(self.cache)

    def test_rejects_missing_duplicate_extra_or_old_csv_columns(self):
        for columns in (benchmark.STAGE_COLUMNS[:-1], (*benchmark.STAGE_COLUMNS, 'unexpected'),
                        (*benchmark.STAGE_COLUMNS[:-1], benchmark.STAGE_COLUMNS[0])):
            self.write(columns)
            with self.assertRaisesRegex(ValueError, 'columns/order'):
                benchmark.stage_metrics(self.cache)
        self.write()
        with (self.cache / 'driving-stages.csv').open('a') as target:
            target.write('1,2\n')
        with self.assertRaisesRegex(ValueError, 'row shape'):
            benchmark.stage_metrics(self.cache)

    def test_rejects_failed_stale_or_inconsistent_status(self):
        original = self.status
        for old, new in (('diagnostic=none', 'diagnostic=overflow'), ('detail=independent-nonadditive', 'detail=unknown'),
                         ('complete_frames=3', 'complete_frames=0'), ('complete_frames=3', 'complete_frames=120001'),
                         ('omitted_incomplete_frames=1', 'omitted_incomplete_frames=-1'),
                         ('cpu_supported_and_enabled=true', 'cpu_supported_and_enabled=false'),
                         ('cpu_supported_and_enabled=true', 'cpu_supported_and_enabled=unknown')):
            self.status = original.replace(old, new)
            self.write()
            with self.assertRaises(ValueError):
                benchmark.stage_metrics(self.cache)
        self.status = original.rstrip() + ' diagnostic=none\n'
        self.write()
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            benchmark.stage_metrics(self.cache)

    def test_requires_complete_jfr_chunks_and_all_artifacts(self):
        original = bytes(self.jfr)
        for data in (b'', b'bad-jfr', original[:-1], original + b'trailing'):
            self.jfr = data
            self.write()
            with self.assertRaises(ValueError):
                benchmark.stage_metrics(self.cache)
        self.jfr = original
        for name in ('driving-stages.csv', 'driving-stages.jfr', 'driving-stages-status.txt'):
            self.write()
            (self.cache / name).unlink()
            with self.assertRaisesRegex(ValueError, 'Missing stage profile artifact'):
                benchmark.stage_metrics(self.cache)

    def test_verify_only_requires_stage_artifacts_when_explicitly_enabled(self):
        (self.root / 'client1-launch.log').write_text('\n'.join([
            '[DRIVING_PERF] LUA_COMPLETE', '[PZToolkitJavaPatches] Experimental B42.21 patch:',
            '[DRIVING_PERF] BEGIN ', '[DRIVING_PERF] MEASURE ', '[DRIVING_PERF] END ', '[DRIVING_PERF] COMPLETE ']))
        selection = {'cases': ['drive'], 'options': {'optimizer_enabled': False}}
        with patch.object(benchmark, 'metrics', return_value={'fixture': True}):
            old = benchmark.verify(self.root, selection, None)
            self.assertEqual(old['issues'], [])
            self.assertNotIn('stage_timings', old['evidence'])
            selection['options']['stage_profile'] = False
            self.assertEqual(benchmark.verify(self.root, selection, None), old)
            selection['options']['stage_profile'] = True
            actual = benchmark.verify(self.root, selection, None)
            self.assertEqual(actual['issues'], [])
            self.assertIn('stage_timings', actual['evidence'])
            (self.cache / 'driving-stages.csv').unlink()
            failed = benchmark.verify(self.root, selection, None)
            self.assertEqual(failed['outcomes'][0]['status'], 'failed')
            self.assertTrue(any(issue.startswith('Stage profile: Missing') for issue in failed['issues']))
            selection['options']['stage_profile'] = False
            self.assertEqual(benchmark.verify(self.root, selection, None), old)


if __name__ == '__main__':
    unittest.main()
