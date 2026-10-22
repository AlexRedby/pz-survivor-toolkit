"""Temporal regressions use final draws, independent clocks and actual spacing."""
import copy
import csv
import gzip
import importlib.util
import io
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'tools/cart_trajectory_check.py'
spec = importlib.util.spec_from_file_location('cart_trajectory_check', SCRIPT)
analyzer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)
WINDOWS = [dict(name='walk-switch', start=1000, end=1300)]


def evidence():
    native, matrices = [], []
    for i, seconds in enumerate((0, .1, .3)):
        actor = 10 + seconds
        fore_aft = 1 + seconds ** 2
        native.append(dict(sequence=i + 1, time=20 + seconds, event='draw', wallTimeMillis=1000 + seconds * 1000,
                           type='SaucedWheelbarrow.WheelbarrowWood', playerX=actor, playerY=2,
                           slotX=actor, slotY=2, slotAngle=math.pi / 2, actorHeading=0,
                           wheelX=actor + fore_aft, wheelY=2))
        matrix = [1., 0, 0, 0, 0, 1., 0, 0, 0, 0, 1., 0, 0, 0, -fore_aft / 1.5, 1.]
        matrices.append(dict(source='held', wall=1000 + seconds * 1000, nanoTime=int((9000 + seconds) * 1e9),
                             x=actor, y=2, angle=math.pi / 2, cart=matrix))
    return native, matrices


def write_capture(root, native, matrices, zipped=False):
    if native is not None:
        stream = io.StringIO()
        writer = csv.DictWriter(stream, fieldnames=list(native[0]))
        writer.writeheader()
        writer.writerows(native)
        path = root / ('wood-wheel-native.csv' + ('.gz' if zipped else ''))
        if zipped:
            with gzip.open(path, 'wt') as output:
                output.write(stream.getvalue())
        else:
            path.write_text(stream.getvalue())
    if matrices is not None:
        (root / 'wheel-roll-draws.jsonl').write_text(''.join(json.dumps(row) + '\n' for row in matrices))


class CartTrajectoryTests(unittest.TestCase):
    def analyze(self, native=None, matrices=None, windows=WINDOWS, gap=.25):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write_capture(root, native, matrices)
            return analyzer.analyze_capture(root, windows, gap)

    def test_irregular_spacing_and_distinct_world_actor_and_local_motion(self):
        report = self.analyze(*evidence())
        self.assertTrue(report['coverageComplete'])
        self.assertEqual(report['status'], 'partial')
        self.assertIsNone(report['aestheticPass'])
        self.assertFalse(report['completionVerified'])
        scene = report['scenes']['walk-switch']
        for stream, key in (('nativeDraw', 'wheelActorForeAft'), ('finalMatrix', 'cartOriginRenderForeAft')):
            metric = scene[stream]['metrics'][key]
            self.assertAlmostEqual(metric['peakStepTiles'], .08)
            self.assertAlmostEqual(metric['peakVelocityTilesPerSecond'], .4)
            self.assertAlmostEqual(metric['peakAccelerationTilesPerSecondSquared'], 2)
        self.assertAlmostEqual(scene['nativeDraw']['metrics']['actorWorld']['peakStepTiles'], .2)
        self.assertAlmostEqual(scene['nativeDraw']['metrics']['wheelWorld']['peakStepTiles'], .28)
        self.assertAlmostEqual(scene['finalMatrix']['metrics']['handleRenderForeAft']['peakStepTiles'], .08)

    def test_intermediate_updates_do_not_create_render_jumps(self):
        native, matrices = evidence()
        spike = dict(native[1], event='grounding', wheelX=100000, time=20.000001, sequence=77)
        native.insert(1, spike)
        native.insert(2, dict(spike, event='snapshot'))
        native.insert(4, dict(native[3]))
        matrices.insert(1, dict(matrices[0], source='world', x=999999))
        scene = self.analyze(native, matrices)['scenes']['walk-switch']
        self.assertEqual(scene['nativeDraw']['samples'], 3)
        self.assertEqual(scene['nativeDraw']['ignoredUpdatesOrWorldDraws'], 2)
        self.assertEqual(scene['nativeDraw']['duplicateRecords'], 1)
        self.assertEqual(scene['finalMatrix']['ignoredUpdatesOrWorldDraws'], 1)
        self.assertAlmostEqual(scene['nativeDraw']['metrics']['wheelActorForeAft']['peakStepTiles'], .08)

    def test_repeated_position_at_a_new_draw_time_is_a_real_hold(self):
        native, matrices = evidence()
        native[1].update({key: native[0][key] for key in ('playerX', 'wheelX', 'slotX')})
        scene = self.analyze(native, matrices)['scenes']['walk-switch']['nativeDraw']
        self.assertEqual(scene['samples'], 3)
        self.assertEqual(scene['duplicateRecords'], 0)
        self.assertGreater(scene['metrics']['wheelWorld']['peakAccelerationTilesPerSecondSquared'], 0)

    def test_missing_sources_wall_only_matrices_and_sparse_samples_are_not_passes(self):
        native, matrices = evidence()
        for row in matrices:
            del row['nanoTime']
        for n, m, reason in ((native, None, 'missing_final_draw_samples'),
                             (native, matrices, 'missing_monotonic_clock'),
                             (native[:2], matrices[:2], 'fewer_than_three_final_draw_samples')):
            report = self.analyze(n, m)
            self.assertFalse(report['coverageComplete'])
            self.assertIn(reason, report['scenes']['walk-switch']['finalMatrix']['reasons'])
            self.assertEqual(report['scenes']['walk-switch']['finalMatrix']['metrics'], {})
        report = self.analyze(None, evidence()[1])
        self.assertFalse(report['scenes']['walk-switch']['nativeDraw']['coverage'])
        native, matrices = evidence()
        report = self.analyze(native[:2], matrices[:2])
        self.assertFalse(report['coverageComplete'])
        metric = report['scenes']['walk-switch']['finalMatrix']['metrics']['cartOriginRenderForeAft']
        self.assertAlmostEqual(metric['peakStepTiles'], .01)
        self.assertIsNone(metric['peakAccelerationTilesPerSecondSquared'])

    def test_clock_and_sequence_corruption_fail_closed(self):
        for stream, field, value in (('native', 'time', 20), ('native', 'time', 19),
                                     ('native', 'sequence', 1), ('native', 'wallTimeMillis', 999),
                                     ('matrix', 'nanoTime', 9000 * 10 ** 9), ('matrix', 'nanoTime', 8999 * 10 ** 9)):
            with self.subTest(stream=stream, field=field, value=value):
                native, matrices = evidence()
                # Keep a regressing wall record inside the selected window.
                if field == 'wallTimeMillis':
                    native[2][field] = 1050
                else:
                    (native if stream == 'native' else matrices)[1][field] = value
                with self.assertRaises(ValueError):
                    self.analyze(native, matrices)
        native, matrices = evidence()
        del matrices[1]['nanoTime']
        with self.assertRaisesRegex(ValueError, 'Mixed clock'):
            self.analyze(native, matrices)

    def test_nonfinite_and_malformed_measurements_fail_closed(self):
        for mutate in (lambda n, m: n[1].update(wheelX='nan'),
                       lambda n, m: n[1].update(time='inf'),
                       lambda n, m: n[1].update(sequence=1.5),
                       lambda n, m: m[1]['cart'].__setitem__(14, float('nan')),
                       lambda n, m: m[1]['cart'].pop(),
                       lambda n, m: m[1].update(result=False),
                       lambda n, m: m[1].update(source='grip-before-IK')):
            native, matrices = evidence()
            mutate(native, matrices)
            with self.assertRaises((ValueError, KeyError)):
                self.analyze(native, matrices)
        with self.assertRaises(ValueError):
            analyzer.load_json('{"wall":1,"wall":2}')
        with self.assertRaises(ValueError):
            analyzer.load_json('{"wall":NaN}')

    def test_missing_edges_and_large_gaps_are_explicit(self):
        native, matrices = evidence()
        report = self.analyze(native, matrices, gap=.15)
        self.assertIn('sampling_gap', report['scenes']['walk-switch']['nativeDraw']['reasons'])
        report = self.analyze(native, matrices, windows=[dict(name='walk-switch', start=0, end=2300)])
        self.assertIn('missing_window_edges', report['scenes']['walk-switch']['nativeDraw']['reasons'])

    def test_clock_reset_between_named_windows_is_invalid(self):
        native, matrices = evidence()
        later = copy.deepcopy(native)
        for row in later:
            row['wallTimeMillis'] += 1000
            row['time'] -= 10
            row['sequence'] += 3
        windows = WINDOWS + [dict(name='stop', start=2000, end=2300)]
        with self.assertRaisesRegex(ValueError, 'monotonic'):
            self.analyze(native + later, matrices, windows=windows)

    def test_named_baseline_uses_independent_epochs_and_rejects_missing_coverage(self):
        baseline = self.analyze(*evidence())
        native, matrices = evidence()
        for row in native:
            row['time'] += 100000
            row['wallTimeMillis'] += 10000
            row['wheelX'] = row['playerX'] + 1 + (row['wheelX'] - row['playerX'] - 1) / 2
        for row in matrices:
            row['nanoTime'] += 987654321000000
            row['wall'] += 10000
            row['cart'][14] /= 2
        candidate = self.analyze(native, matrices, windows=[dict(name='walk-switch', start=11000, end=11300)])
        comparison = analyzer.compare(candidate, baseline)
        self.assertTrue(comparison['coverageComplete'])
        metric = comparison['scenes']['walk-switch']['streams']['nativeDraw']['wheelActorForeAft']['peakStepTiles']
        self.assertAlmostEqual(metric['delta'], -.04)
        partial = copy.deepcopy(candidate)
        partial['scenes']['other-scene'] = partial['scenes'].pop('walk-switch')
        self.assertFalse(analyzer.compare(partial, baseline)['coverageComplete'])
        partial = copy.deepcopy(candidate)
        partial['scenes']['walk-switch']['window']['end'] += 1
        self.assertFalse(analyzer.compare(partial, baseline)['scenes']['walk-switch']['comparable'])

    def test_gzip_archived_windows_and_cli_preserve_existing_output(self):
        native, matrices = evidence()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            write_capture(root, native, matrices, zipped=True)
            windows = root / 'windows.json'
            windows.write_text(json.dumps(dict(windows=[dict(name='walk-switch', lo=1000, hi=1300, start=900)])))
            output = root / 'report.json'
            command = [sys.executable, str(SCRIPT), '--candidate', str(root), '--windows', str(windows), '--output', str(output), '--max-gap-seconds', '.25']
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            report = json.loads(output.read_text())
            self.assertEqual(report['candidate']['status'], 'partial')
            self.assertTrue(report['candidate']['coverageComplete'])
            before = output.read_bytes()
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(output.read_bytes(), before)
            (root / 'wheel-roll-draws.jsonl').unlink()
            output.unlink()
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2, result.stderr)


if __name__ == '__main__':
    unittest.main()
