"""Strict callback diagnostic artifacts; synthetic completed stages, no game process."""
import copy
import csv
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import callback_metrics as callbacks
from queue_checks.adapters import optimizer_benchmark as benchmark


class CallbackMetricsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='callback-metrics-')
        self.addCleanup(self.temporary.cleanup)
        self.cache = Path(self.temporary.name)
        self.stages = []
        for phase, speed in enumerate((0, 10, 30), 1):
            row = dict.fromkeys(benchmark.STAGE_COLUMNS, 0)
            row.update(frame_id=phase, phase=phase, contacts=0, speed_kmh=speed,
                       nano_start=phase * 110, nano_end=phase * 110 + 100,
                       wall_ns=100, cpu_ns=-1, other_exclusive_ns=100)
            self.stages.append(row)
        self.sources = [dict(callback_id=index, kind='lua', filename='client.lua', file='mods/client.lua',
                             name='onTick', line_first_instruction=12) for index in range(2)]
        # Discoveries in an omitted frame may leave unused identities.
        self.sources.append(dict(callback_id=2, kind='java', filename='', file='', name='Native.call',
                                 line_first_instruction=-1))
        self.rows = [dict(frame_id=2, callback_id=0, calls=2, inclusive_ns=100, exclusive_ns=40, max_call_ns=90),
                     dict(frame_id=2, callback_id=1, calls=1, inclusive_ns=100, exclusive_ns=50, max_call_ns=100),
                     dict(frame_id=3, callback_id=0, calls=2, inclusive_ns=70, exclusive_ns=60, max_call_ns=60)]
        self.frames = [dict(frame_id=index, nano_start=index * 110, nano_end=index * 110 + 100,
                            callbacks=calls, rows=rows, exclusive_ns=exclusive)
                       for index, calls, rows, exclusive in ((1, 0, 0, 0), (2, 3, 2, 90), (3, 2, 1, 60))]
        self.status = dict(version=1, complete_frames=3, rows=3, identities=3, omitted_incomplete_frames=1,
            max_frames=6000, max_rows=1000000, max_identities=2048, max_depth=64, stopped='finish',
            diagnostic='none', coverage='LuaCaller-native-terminal-overloads',
            inclusive='identity-union-nonadditive', exclusive='callback-stack-only')
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
            'translucent_sort=TimSort.doSort-call partial-details-on-throwable=included\n')
        jfr = bytearray(69)
        jfr[:4] = b'FLR\0'
        jfr[4:6] = (2).to_bytes(2, 'big')
        jfr[8:16] = len(jfr).to_bytes(8, 'big')
        (self.cache / 'driving-stages.jfr').write_bytes(jfr)
        self.csv('driving-callback-sources.csv', callbacks.SOURCE_COLUMNS, self.sources)
        self.csv('driving-callbacks.csv', callbacks.CALLBACK_COLUMNS, self.rows)
        self.csv('driving-callback-frames.csv', callbacks.FRAME_COLUMNS, self.frames)
        (self.cache / 'driving-callback-status.txt').write_text(
            ' '.join(str(key) + '=' + str(value) for key, value in self.status.items()) + '\n')

    def report(self):
        return callbacks.callback_metrics(self.cache)

    def test_nonadditive_nested_callbacks_empty_frame_and_distinct_same_source(self):
        report = self.report()
        self.assertEqual((report['complete_frames'], report['rows'], report['identities']), (3, 3, 3))
        total = report['groups']['overall']
        self.assertEqual((total['frames'], total['calls']), (3, 5))
        self.assertAlmostEqual(total['frame_wall_ms'], 300 / 1e6)
        self.assertAlmostEqual(total['callback_inclusive_ms_nonadditive'], 270 / 1e6)
        self.assertAlmostEqual(total['callback_exclusive_ms'], 150 / 1e6)
        phase2 = report['groups']['phase2']
        self.assertGreater(phase2['callback_inclusive_ms_nonadditive'], phase2['frame_wall_ms'])
        self.assertEqual([row['callback_id'] for row in total['top_by_exclusive']], [0, 1])
        self.assertEqual(total['top_by_exclusive'][0]['line_first_instruction'], 12)
        self.assertEqual(total['top_by_exclusive'][0]['file'], 'mods/client.lua')
        self.assertEqual(report['groups']['stationary']['frames'], 1)
        self.assertEqual(report['groups']['stationary']['calls'], 0)
        self.assertEqual(report['groups']['stationary']['top_by_inclusive'], [])
        self.assertEqual(report['groups']['moving10']['calls'], 5)
        self.assertEqual(report['groups']['moving30']['calls'], 2)
        self.assertIn('nonadditive', report['attribution'])
        self.assertIn('Synchronous Java', report['limits'][0])

    def test_accepts_shorter_and_empty_completed_stage_prefix(self):
        self.frames = self.frames[:2]
        self.rows = self.rows[:2]
        self.status.update(complete_frames=2, rows=2)
        self.write()
        self.assertEqual(self.report()['groups']['overall']['frames'], 2)
        self.frames, self.rows = [], []
        self.status.update(complete_frames=0, rows=0)
        self.write()
        self.assertEqual(self.report()['groups']['overall']['frames'], 0)

    def test_utf8_source_metadata_matches_native_writer(self):
        self.sources[0].update(filename='тест.lua', file='mods/日本語.lua', name='обработчик😀')
        self.write()
        opened_encodings = []
        original_open = Path.open

        def utf8_source_open(path, *args, **kwargs):
            if path.name == 'driving-callback-sources.csv':
                opened_encodings.append(kwargs.get('encoding'))
                # Simulate a host whose default text encoding cannot decode the metadata.
                if 'encoding' not in kwargs:
                    kwargs['encoding'] = 'ascii'
            return original_open(path, *args, **kwargs)

        with patch.object(Path, 'open', utf8_source_open):
            source = self.report()['groups']['overall']['top_by_exclusive'][0]
        self.assertEqual(opened_encodings, ['utf-8'])
        self.assertEqual((source['filename'], source['file'], source['name']),
                         ('тест.lua', 'mods/日本語.lua', 'обработчик😀'))

    def test_rejects_native_integer_bounds_for_calls_and_frame_totals(self):
        self.rows[0]['calls'] = callbacks.MAX_INTEGER
        self.frames[1]['callbacks'] = callbacks.MAX_INTEGER + 1
        self.write()
        with self.assertRaisesRegex(ValueError, 'Out-of-range callback integer: callbacks'):
            self.report()
        self.rows[0]['calls'] = callbacks.MAX_INTEGER + 1
        self.write()
        with self.assertRaises(ValueError):
            self.report()

    def test_stopping_reason_requires_frame_limit_at_exact_capacity(self):
        # Shrink only the frame cap to exercise a complete capture without 6000 fixtures.
        with patch.object(callbacks, 'MAX_FRAMES', 3):
            self.status['max_frames'] = 3
            self.write()
            with self.assertRaisesRegex(ValueError, 'stopping status'):
                self.report()
            self.status['stopped'] = 'frame-limit'
            self.write()
            self.assertEqual(self.report()['stopped'], 'frame-limit')

    def test_rejects_frame_prefix_join_or_summary_mismatches(self):
        original = copy.deepcopy(self.frames)
        for change in ({'frame_id': 4}, {'nano_start': 221}, {'nano_end': 321},
                       {'callbacks': 4}, {'rows': 1}, {'exclusive_ns': 91}, {'exclusive_ns': 101}):
            with self.subTest(change=change):
                self.frames = copy.deepcopy(original)
                self.frames[1].update(change)
                self.write()
                with self.assertRaises(ValueError):
                    self.report()
        self.frames = original[1:]
        self.status['complete_frames'] = 2
        self.write()
        with self.assertRaisesRegex(ValueError, 'stage prefix'):
            self.report()

    def test_rejects_bad_rows_and_aggregate_exclusive_over_frame(self):
        original = copy.deepcopy(self.rows)
        for change in ({'frame_id': 9}, {'callback_id': 3}, {'calls': 0}, {'calls': -1},
                       {'inclusive_ns': 101}, {'exclusive_ns': 101}, {'exclusive_ns': -1},
                       {'max_call_ns': 101}, {'max_call_ns': -1}, {'calls': '1.0'},
                       {'inclusive_ns': 'nan'}, {'calls': 1 << 63}):
            with self.subTest(change=change):
                self.rows = copy.deepcopy(original)
                self.rows[0].update(change)
                self.write()
                with self.assertRaises(ValueError):
                    self.report()
        self.rows = original
        self.rows[0]['exclusive_ns'] = 60
        self.frames[1]['exclusive_ns'] = 110
        self.write()
        with self.assertRaises(ValueError):
            self.report()

    def test_rejects_unordered_duplicate_or_count_mismatched_rows(self):
        original = copy.deepcopy(self.rows)
        for rows in (original[::-1], [original[0], original[0], original[2]], original[:-1]):
            self.rows = rows
            self.write()
            with self.assertRaises(ValueError):
                self.report()

    def test_source_identity_schema_and_bounds(self):
        original = copy.deepcopy(self.sources)
        for change in ({'callback_id': 1}, {'callback_id': 2048}, {'callback_id': -1}, {'kind': 'unknown'},
                       {'line_first_instruction': -2}, {'line_first_instruction': 1 << 31},
                       {'name': 'x' * 4097}, {'name': '\0'}, {'name': '\U0001f600' * 2049}, {'filename': 'x' * 4097},
                       {'file': 'x' * 4097}):
            with self.subTest(change=change):
                self.sources = copy.deepcopy(original)
                self.sources[0].update(change)
                self.write()
                with self.assertRaises(ValueError):
                    self.report()
        self.sources = original[1:]
        self.status['identities'] = 2
        self.write()
        with self.assertRaisesRegex(ValueError, 'IDs/count'):
            self.report()

    def test_rejects_missing_extra_duplicate_or_malformed_csv_columns(self):
        fixtures = [('driving-callback-sources.csv', callbacks.SOURCE_COLUMNS, self.sources),
                    ('driving-callbacks.csv', callbacks.CALLBACK_COLUMNS, self.rows),
                    ('driving-callback-frames.csv', callbacks.FRAME_COLUMNS, self.frames)]
        for filename, columns, rows in fixtures:
            for fields in (columns[:-1], (*columns, 'extra'), (*columns[:-1], columns[0])):
                with self.subTest(filename=filename, fields=fields):
                    self.write()
                    self.csv(filename, fields, rows)
                    with self.assertRaisesRegex(ValueError, 'columns/order'):
                        self.report()
            self.write()
            with (self.cache / filename).open('a') as target:
                target.write('1,2\n')
            with self.assertRaisesRegex(ValueError, 'row shape'):
                self.report()

    def test_status_schema_counts_caps_and_diagnostics(self):
        original = dict(self.status)
        changes = ({'version': 2}, {'diagnostic': 'depth-overflow'}, {'extra': 'field'},
                   {'complete_frames': 4}, {'complete_frames': 6001}, {'rows': 1000001},
                   {'identities': 2049}, {'omitted_incomplete_frames': -1}, {'max_depth': 65},
                   {'max_rows': 10}, {'max_frames': 5999}, {'max_identities': 2049},
                   {'stopped': 'unknown'}, {'stopped': 'frame-limit'}, {'coverage': 'other'},
                   {'inclusive': 'additive'}, {'exclusive': 'all-work'}, {'identities': 2})
        for change in changes:
            with self.subTest(change=change):
                self.status = dict(original, **change)
                self.write()
                with self.assertRaises(ValueError):
                    self.report()
        self.status = original
        self.write()
        path = self.cache / 'driving-callback-status.txt'
        text = path.read_text()
        for malformed in (text.replace(' rows=', '  rows='), text + '\n', text.rstrip() + ' version=1\n',
                          text.replace('max_depth=64 ', ''), text.replace(' rows=', '\trows=')):
            path.write_text(malformed)
            with self.assertRaises(ValueError):
                self.report()

    def test_explicit_inner_span_contract_preserves_legacy_capture(self):
        self.assertEqual(self.report()['detail_spans'], 'disabled')
        self.status.update(version=2, max_rows=1200000, detail_spans='enabled')
        self.write()
        report = self.report()
        self.assertEqual(report['detail_spans'], 'enabled')
        self.assertIn('explicitly selected inner Lua spans', report['attribution'])
        for value in ('unknown', '', 'true'):
            self.status['detail_spans'] = value
            self.write()
            with self.assertRaises(ValueError):
                self.report()
        self.status.update(version=1, max_rows=1000000, detail_spans='enabled')
        self.write()
        with self.assertRaises(ValueError):
            self.report()

    def test_enforces_actual_row_capacity_and_top_twenty(self):
        self.sources = [dict(self.sources[0], callback_id=index) for index in range(21)]
        self.rows = [dict(frame_id=2, callback_id=index, calls=1, inclusive_ns=1,
                          exclusive_ns=1, max_call_ns=1) for index in range(21)]
        self.frames[1].update(callbacks=21, rows=21, exclusive_ns=21)
        self.frames[2].update(callbacks=0, rows=0, exclusive_ns=0)
        self.status.update(rows=21, identities=21)
        self.write()
        top = self.report()['groups']['overall']['top_by_exclusive']
        self.assertEqual(len(top), 20)
        self.assertEqual([row['callback_id'] for row in top], list(range(20)))
        with patch.object(callbacks, 'MAX_ROWS', 20):
            self.status.update(version=2, detail_spans='disabled', rows=20, max_rows=20)
            self.write()
            with self.assertRaisesRegex(ValueError, 'capacity'):
                self.report()

    def test_stage_validation_runs_first_and_inherits_nonfinite_rejection(self):
        for speed in ('nan', 'inf'):
            self.stages[0]['speed_kmh'] = speed
            self.write()
            (self.cache / 'driving-callbacks.csv').unlink()
            with self.assertRaisesRegex(ValueError, 'Nonfinite'):
                self.report()

    def test_all_callback_artifacts_required(self):
        for filename in ('driving-callback-sources.csv', 'driving-callbacks.csv',
                         'driving-callback-frames.csv', 'driving-callback-status.txt'):
            self.write()
            (self.cache / filename).unlink()
            with self.assertRaisesRegex(ValueError, 'Missing callback profile artifact'):
                self.report()


if __name__ == '__main__':
    unittest.main()
