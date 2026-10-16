"""Stationary gates reject fixed-heading spins, moving axles and fake native gait."""
import csv
import importlib.util
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).parent / 'native_queue/contributions/wooden_cart_motion/analyze-stationary.py'
spec = importlib.util.spec_from_file_location('cart_stationary_analyzer', SCRIPT)
analyzer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)


def evidence():
    lines, wheel = ['[WOOD_BANK] RUN_STARTED'], []
    for index, (sex, cargo, scenario) in enumerate((sex, cargo, scenario) for sex in ('male', 'female')
            for cargo in ('empty', 'full') for scenario in analyzer.SPECS):
        name, start = f'{sex}-{cargo}-{scenario}', 100000 + index * 15000
        events = analyzer.STEPS[scenario]
        lines.append(f'[WOOD_BANK] CASE {name} attempt=0 wall={start}')
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start}')
        for t, g, d in events:
            lines.append(f'[WOOD_RAMP_EVENT] case={name} elapsed={t} gait={g} drive={d}')
        for t in range(0, 12000, 100):
            heading = math.pi / 2 * min(1, max(0, (t - 1000) / 1000))
            pivot = 1000 <= t < 2000
            if scenario == 'cancel-restart':
                heading = math.pi / 8 if 1250 <= t < 2200 else heading
                if t >= 2200:
                    heading = math.pi / 8 + 3 * math.pi / 8 * min(1, (t - 2200) / 1000)
                pivot = 1000 <= t < 1250 or 2200 <= t < 3200
            if scenario == 'right':
                heading = -heading
            target = -math.pi / 2 if scenario == 'right' else math.pi / 2
            if scenario == 'sprint-sequence' and t >= 3800:
                heading += math.pi / 2 * min(1, (t - 3800) / 1000)
                target = math.pi
            command = [event for event in events if event[0] < t]
            _, gait, drive = command[-1] if command else (0, 0, 0)
            fast = 2100 <= t < events[-1][0] and scenario in ('run-exit', 'sprint-sequence')
            run, sprint = fast and scenario == 'run-exit', fast and scenario == 'sprint-sequence'
            x, y = 1 - math.cos(heading), -math.sin(heading)
            clip = 'Bob_StrafeNoAim_Right' if scenario == 'right' else 'Bob_StrafeNoAim_Left'
            tracks = f'{clip}@1/{t / 1000}/1;' if pivot else ''
            step = (1 if scenario == 'right' else -1) if pivot else 0
            state = f'heading:{heading},target:{target},stationary:{str(pivot).lower()},stationaryRoot:{str(pivot).lower()},actualDistance:{.01 if fast or pivot else 0},axle:1,rootTracks:{tracks}'
            lines.append(f'[WOOD_BANK_SAMPLE] case={name} wall={start+t} elapsed={t} x={x} y={y} '
                f'run={str(run).lower()} sprint={str(sprint).lower()} skill=10 speed=.8 drive={drive} requestedGait={gait} '
                f'stepX={step} stepY=0 pace=1 bank=0 reversal=direction:1, ramp=speed:1, stationary={state} tracks={clip}=1@1;')
            wheel.append(dict(event='grounding', wallTimeMillis=start+t, wheelX=1, wheelY=0, phase=0))
    return '\n'.join(lines + ['[WOOD_BANK] ALL_COMPLETE cases=20']), wheel


class StationaryAnalyzerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.log, cls.wheel = evidence()

    def test_complete_protocol(self):
        report = analyzer.analyze(self.log, self.wheel)
        self.assertTrue(report['motionPass'], report['failures'])
        self.assertEqual(report['caseCount'], 20)
        self.assertTrue(all(row['nativeWheelSamples'] >= 3 for row in report['cases']))

    def test_diagnostic_suffix_cannot_replace_header_coordinates(self):
        log = self.log.replace('tracks=Bob_', 'tracks=Bob_SprintToStop2h_Heavy=1@.5;y=999 heading=nan Bob_')
        self.assertTrue(analyzer.analyze(log, self.wheel)['motionPass'])
        for bad in (self.log.replace('x=0.0 ', 'x=nan ', 1),
                    self.log.replace(',axle:1,', ',axle:1,x:999,', 1),
                    self.log.replace('heading:0.0,', 'heading:nan,', 1),
                    self.log.replace('run=false ', 'run=false run=true ', 1)):
            with self.assertRaises((AssertionError, ValueError)):
                analyzer.analyze(bad, self.wheel)

    def test_missing_duplicate_wrong_cases_and_completion(self):
        first = next(line for line in self.log.splitlines() if ' COMPLETE ' in line)
        for bad in (self.log.replace(first, ''), self.log + '\n' + first,
                    self.log.replace('male-empty-left', 'unexpected'),
                    self.log.replace('ALL_COMPLETE cases=20', 'ALL_COMPLETE cases=200')):
            with self.assertRaises(AssertionError):
                analyzer.analyze(bad, self.wheel)

    def test_each_case_requires_finite_ordered_edges_and_input_events(self):
        for bad in (self.log.replace('stationary:false', 'stationary:unknown', 1),
                    self.log.replace('elapsed=100 ', 'elapsed=0 ', 1),
                    '\n'.join(line for line in self.log.splitlines() if not ('SAMPLE]' in line and int(re.search(r'elapsed=(\d+)', line)[1]) >= 11500)),
                    '\n'.join(line for line in self.log.splitlines() if '[WOOD_RAMP_EVENT]' not in line),
                    self.log.replace('gait=0 drive=1', 'gait=0 drive=3', 1)):
            with self.assertRaises(AssertionError):
                analyzer.analyze(bad, self.wheel)

    def test_motion_failures_preserve_measurements(self):
        variants = {
            'stationary turn never engaged': self.log.replace('stationary:true', 'stationary:false'),
            'fast gait during stationary turn': self.log.replace('run=false', 'run=true'),
            'stationary gait has forward/backward input': self.log.replace('stepY=0 ', 'stepY=.1 '),
            'stationary gait steps in opposite direction': self.log.replace('stepX=-1 ', 'stepX=1 '),
            'native lateral gait does not progress': re.sub(r'rootTracks:[^ ]+', 'rootTracks:', self.log),
            'native lateral gait uses opposite side': self.log.replace('rootTracks:Bob_StrafeNoAim_Left@', 'rootTracks:Bob_StrafeNoAim_Right@'),
            'front axle translates during stationary turn': self.log.replace('axle:1,', 'axle:2,'),
            'stationary heading did not converge and exit': re.sub(r'heading:([^,]+),', 'heading:0,', self.log),
            'held modifier did not resume after stationary turn': self.log.replace('run=true', 'run=false').replace('sprint=true', 'sprint=false'),
        }
        for gate, log in variants.items():
            with self.subTest(gate=gate):
                report = analyzer.analyze(log, self.wheel)
                self.assertFalse(report['motionPass'])
                self.assertIn(gate, [failure[1] for failure in report['failures']])
        report = analyzer.analyze(self.log, [])
        self.assertIn('missing native stationary wheel coverage', [failure[1] for failure in report['failures']])
        wheel = [dict(row, wheelX=row['wallTimeMillis'] / 1000) for row in self.wheel]
        report = analyzer.analyze(self.log, wheel)
        self.assertIn('native wheel translates during stationary turn', [failure[1] for failure in report['failures']])
        wheel = [dict(row, phase=row['wallTimeMillis'] / 100) for row in self.wheel]
        report = analyzer.analyze(self.log, wheel)
        self.assertIn('native wheel rolls during stationary turn', [failure[1] for failure in report['failures']])

    def test_cancel_release_and_restart_are_gated(self):
        lines = self.log.splitlines()
        for gate, change in (
            ('release did not cancel stationary turn', lambda line: line.replace('stationary:false', 'stationary:true') if 'elapsed=1700 ' in line else line),
            ('stationary turn did not restart', lambda line: line.replace('stationary:true', 'stationary:false') if 2200 <= int(re.search(r'elapsed=(\d+)', line)[1]) < 3200 else line),
            ('stationary latch survives release', lambda line: line.replace('stationary:false', 'stationary:true') if 'elapsed=9000 ' in line else line)):
            log = '\n'.join(change(line) if 'SAMPLE]' in line and 'cancel-restart ' in line else line for line in lines)
            with self.subTest(gate=gate):
                report = analyzer.analyze(log, self.wheel)
                self.assertIn(gate, [failure[1] for failure in report['failures']])

    def test_failed_attempt_samples_and_events_cannot_contaminate_selected_window(self):
        name = 'male-empty-left'
        boundary = f'[WOOD_BANK] CASE {name} attempt=0 wall=100000'
        prefix = (f'[WOOD_BANK] CASE {name} attempt=0 wall=85000\n'
                  f'[WOOD_RAMP_EVENT] case={name} elapsed=1000 gait=2 drive=3\n')
        sample = next(line for line in self.log.splitlines() if f'case={name} wall=100000 ' in line)
        prefix += sample.replace('wall=100000 ', 'wall=85000 ') + '\n'
        log = self.log.replace(boundary, prefix + boundary)
        self.assertTrue(analyzer.analyze(log, self.wheel)['motionPass'])
        wheel = [row for row in self.wheel for _ in range(2)]
        self.assertTrue(analyzer.analyze(self.log, wheel)['motionPass'])
        with self.assertRaisesRegex(AssertionError, 'selected stationary attempt'):
            analyzer.analyze(self.log.replace(boundary, boundary + '\n' + boundary), self.wheel)

    def test_wheel_values_are_validated_only_after_selected_pivot_filter(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'wheel.csv'
            def read(rows):
                with path.open('w') as stream:
                    writer = csv.DictWriter(stream, fieldnames=rows[0]); writer.writeheader(); writer.writerows(rows)
                return analyzer.read_wheel(path)
            bootstrap = dict(self.wheel[0], wallTimeMillis=1, wheelX='NaN', wheelY='unprepared', phase='NaN')
            # A previous recording attempt and settled pre-input Idle are outside the pivot.
            previous_attempt = dict(bootstrap, wallTimeMillis=85000)
            idle = dict(bootstrap, wallTimeMillis=100500)
            rows = [bootstrap, previous_attempt, idle, *self.wheel]
            self.assertTrue(analyzer.analyze(self.log, read(rows))['motionPass'])
            for key in ('wheelX', 'wheelY', 'phase'):
                for value in ('NaN', 'Infinity', '-Infinity'):
                    with self.subTest(key=key, value=value):
                        bad = [dict(row, **{key: value}) if row['wallTimeMillis'] == 101100 else row for row in self.wheel]
                        with self.assertRaisesRegex(AssertionError, 'selected pivot: male-empty-left'):
                            analyzer.analyze(self.log, read(bad))
            for time in ('NaN', 'Infinity'):
                with self.assertRaisesRegex(AssertionError, 'timestamp'):
                    read([dict(bootstrap, wallTimeMillis=time)])
            # Invalid pivot values must fail, not be discarded to create a coverage gap.
            with self.assertRaises((ValueError, TypeError)):
                analyzer.analyze(self.log, read([dict(row, phase='unprepared') for row in self.wheel]))
            with self.assertRaises(FileNotFoundError):
                analyzer.read_wheel(path.with_name('missing.csv'))

    def test_cli_uses_explicit_stdout_and_refuses_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log, output = root / 'client1-launch.log', root / 'stationary-motion.json'
            log.write_text(self.log)
            (root / 'native-launch.log').write_text('wrong legacy log')
            with (root / 'wood-wheel-native.csv').open('w') as stream:
                writer = csv.DictWriter(stream, fieldnames=self.wheel[0]); writer.writeheader(); writer.writerows(self.wheel)
            command = [sys.executable, str(SCRIPT), '--profile', str(root), '--log', str(log), '--output', str(output)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json.loads(output.read_text())['motionPass'])
            original = output.read_bytes()
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertEqual(output.read_bytes(), original)
            (root / 'wood-wheel-native.csv').unlink()
            output.unlink()
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
