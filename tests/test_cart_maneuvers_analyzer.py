"""Maneuver gates need measured motion and every actual requested input stage."""
import importlib.util
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).parent / 'native_queue/contributions/wooden_cart_motion/analyze-maneuvers.py'
spec = importlib.util.spec_from_file_location('cart_maneuvers_analyzer', SCRIPT)
analyzer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)


def interpolate(t, knots):
    for (start, value), (end, target) in zip(knots, knots[1:]):
        if t <= end:
            return value + (target - value) * max(0, (t - start) / (end - start))
    return knots[-1][1]


def evidence():
    lines = ['[WOOD_BANK] RUN_STARTED']
    for index, (sex, cargo, scenario) in enumerate((sex, cargo, scenario) for sex in ('male', 'female')
            for cargo in ('empty', 'full') for scenario in analyzer.SPECS):
        name, start = f'{sex}-{cargo}-{scenario}', 100000 + index * 15000
        events = analyzer.STEPS[scenario]
        lines.append(f'[WOOD_BANK] CASE {name} attempt=0 wall={start}')
        x, y, last_heading = 100., 100., analyzer.H0
        for t in range(0, 12000, 100):
            command = [event for event in events if event[0] < t]
            _, gait, drive = command[-1] if command else (0, 0, 0)
            sign = 1 if scenario.endswith('left') else -1
            offset, stationary, direction, braking, moving = 0., False, 1, False, False
            if scenario.startswith('idle'):
                offset = sign * interpolate(t, [(0, 0), (1000, 0), (1350, .16), (1700, .08), (2500, .08), (4200, -math.pi / 2)])
                stationary = 1000 < t < 1700 or 2500 < t < 4200
            elif scenario.startswith('moving'):
                offset = sign * interpolate(t, [(0, 0), (2200, 0), (2550, .1), (5000, -math.pi / 2)])
                moving = 1000 < t < 6200 or 7000 < t < 9000
            elif scenario == 'reverse-rest':
                direction = -1 if 1100 <= t < 4500 else 1
                braking = 3900 <= t < 4500
                moving = 1200 <= t < 4300 or 4700 <= t < 8000
            elif scenario == 'reverse-moving':
                direction = -1 if 4800 <= t < 7300 else 1
                braking = 3100 <= t < 3200 or 4100 <= t < 4800 or 6600 <= t < 7300
                moving = 1100 <= t < 4600 or 5000 <= t < 7100 or 7500 <= t < 9500
            else:
                offset = sign * interpolate(t, [(0, 0), (2200, 0), (5200, math.pi / 2), (5500, math.pi / 2 + .1),
                                               (6500, math.pi / 2 + .1), (8800, math.pi)])
                moving = 1000 < t < 5550 or 6500 < t < 9500
            heading = analyzer.H0 + offset
            if scenario.startswith('idle'):
                x += math.cos(last_heading) - math.cos(heading)
                y += math.sin(last_heading) - math.sin(heading)
            elif moving:
                x += direction * .02 * math.cos((heading + last_heading) / 2)
                y += direction * .02 * math.sin((heading + last_heading) / 2)
            last_heading = heading
            requested = 0 if drive == 0 else (-1 if drive == 3 and scenario.startswith('reverse') else 1)
            run = gait == 1 and moving and direction > 0 and requested > 0
            sprint = gait == 2 and moving and direction > 0 and requested > 0
            clip = 'Bob_StrafeNoAim_Left' if sign > 0 else 'Bob_StrafeNoAim_Right'
            tracks = f'{clip}@1/{t / 1000}/1;' if stationary else 'Bob_Walk@1/0.5/1;'
            root_speed, actual_distance = (.2, .002) if moving else (0, 0)
            root_heading = analyzer.wrap(heading)
            state = f'heading:{root_heading},target:{root_heading},stationary:{str(stationary).lower()},stationaryRoot:{str(stationary).lower()},actualDistance:{actual_distance},axle:1,rootTracks:{tracks}'
            lines.append(f'[WOOD_BANK_SAMPLE] case={name} wall={start+t} elapsed={t} x={x} y={y} '
                f'run={str(run).lower()} sprint={str(sprint).lower()} skill=10 speed=.8 drive={drive} requestedGait={gait} '
                f'stepX={-sign if stationary else 0} stepY={direction if moving else 0} pace=1 bank=0 '
                f'reversal=direction:{direction},requested:{requested},active:{str(braking).lower()},braking:{str(braking).lower()},neutral:{.04 if braking and not moving else 0},actualDistance:{actual_distance},brakeTarget:{root_heading}, '
                f'ramp=speed:{root_speed},velocity:0,sprintMomentum:0,load:0,heading:{root_heading},target:0, '
                f'stationary={state} tracks={clip}=1@1;')
            # The native fixture logs a due sample before applying its new input.
            for at, g, d in events:
                if t < at <= t + 99 or at == t:
                    lines.append(f'[WOOD_RAMP_EVENT] case={name} elapsed={at} gait={g} drive={d}')
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start}')
    return '\n'.join(lines + ['[WOOD_BANK] ALL_COMPLETE cases=32'])


def change_case(log, case, callback):
    return '\n'.join(callback(line, int(re.search(r'elapsed=(\d+)', line)[1]))
                     if 'SAMPLE]' in line and f'case={case} ' in line else line for line in log.splitlines())


class ManeuverAnalyzerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.log = evidence()

    def failures(self, log):
        report = analyzer.analyze(log)
        self.assertFalse(report['motionPass'])
        return [failure[1] for failure in report['failures']]

    def test_complete_matrix_and_wrapped_native_headings(self):
        report = analyzer.analyze(self.log)
        self.assertTrue(report['motionPass'], report['failures'])
        self.assertEqual(report['caseCount'], 32)
        turns = {r['case']: r['signedYawDegrees'] for r in report['cases']}
        self.assertAlmostEqual(turns['male-empty-uturn-left'], 180)
        self.assertAlmostEqual(turns['male-empty-uturn-right'], -180)
        self.assertNotIn('visualPass', report)

    def test_fixture_stop_tick_may_sample_after_12_second_window(self):
        lines = []
        for line in self.log.splitlines():
            lines.append(line)
            if 'SAMPLE]' in line and 'elapsed=11900 ' in line:
                wall = int(re.search(r'wall=(\d+)', line)[1])
                lines.append(line.replace(f'wall={wall} ', f'wall={wall + 100} ').replace('elapsed=11900 ', 'elapsed=12000 '))
        self.assertTrue(analyzer.analyze('\n'.join(lines))['motionPass'])

    def test_boundaries_and_exact_case_matrix_are_required(self):
        first = next(line for line in self.log.splitlines() if ' COMPLETE ' in line)
        for bad in (self.log.replace('[WOOD_BANK] RUN_STARTED', ''), self.log.replace(first, ''),
                    self.log + '\n' + first, self.log.replace('male-empty-idle-swap-left', 'unexpected'),
                    self.log.replace('ALL_COMPLETE cases=32', 'ALL_COMPLETE cases=320'),
                    self.log + '\n[WOOD_BANK] FAIL blocked'):
            with self.subTest(tail=bad[-80:]), self.assertRaises(AssertionError):
                analyzer.analyze(bad)

    def test_selected_attempt_ignores_rejected_samples_and_events(self):
        boundary = '[WOOD_BANK] CASE male-empty-idle-swap-left attempt=0 wall=100000'
        rejected = ('[WOOD_BANK] CASE male-empty-idle-swap-left attempt=0 wall=85000\n'
                    '[WOOD_RAMP_EVENT] case=male-empty-idle-swap-left elapsed=1 gait=2 drive=3\n'
                    '[WOOD_BANK_SAMPLE] case=male-empty-idle-swap-left wall=85000 stationary=none\n')
        self.assertTrue(analyzer.analyze(self.log.replace(boundary, rejected + boundary))['motionPass'])
        with self.assertRaisesRegex(AssertionError, 'selected maneuver attempt'):
            analyzer.analyze(self.log.replace(boundary, boundary + '\n' + boundary))

    def test_stages_require_actual_samples_including_150ms_cancel(self):
        variants = [self.log.replace('elapsed=3150 gait=2 drive=2', 'elapsed=3150 gait=2 drive=3', 1),
                    re.sub(r'^\[WOOD_RAMP_EVENT\].*\n', '', self.log, count=1, flags=re.MULTILINE),
                    change_case(self.log, 'male-empty-reverse-moving', lambda line, t: line.replace('drive=3 ', 'drive=2 ') if t == 3100 else line),
                    change_case(self.log, 'male-empty-idle-swap-left', lambda line, t: line.replace('drive=4 ', 'drive=1 ') if 1500 <= t < 1700 else line)]
        for bad in variants:
            with self.assertRaisesRegex(AssertionError, 'input'):
                analyzer.analyze(bad)

    def test_full_ordered_finite_actual_measurements_are_required(self):
        case = 'male-empty-idle-swap-left'
        for bad in (self.log.replace('x=100.0 ', 'x=nan ', 1),
                    self.log.replace('heading:2.356194490192345,', 'heading:nan,', 1),
                    self.log.replace('neutral:0,', 'neutral:inf,', 1),
                    self.log.replace('run=false ', 'run=false run=true ', 1),
                    change_case(self.log, case, lambda line, t: line.replace('elapsed=100 ', 'elapsed=0 ') if t == 100 else line),
                    change_case(self.log, case, lambda line, t: '' if t >= 11500 else line),
                    change_case(self.log, case, lambda line, t: '' if 4000 <= t < 4800 else line)):
            with self.assertRaises((AssertionError, ValueError)):
                analyzer.analyze(bad)

    def test_native_track_suffix_cannot_replace_real_coordinates(self):
        log = self.log.replace(' tracks=', ' tracks=x=nan heading=nan ')
        self.assertTrue(analyzer.analyze(log)['motionPass'])

    def test_teleport_snap_and_animation_without_motion_fail(self):
        cases = {
            'position jumps between samples': change_case(self.log, 'male-empty-moving-swap-left',
                lambda line, t: re.sub(r' x=[^ ]+', ' x=999', line) if t == 4000 else line),
            'heading snaps between samples': change_case(self.log, 'male-empty-uturn-left',
                lambda line, t: re.sub(r'heading:[^,]+,', 'heading:0,', line) if t == 4000 else line),
            'reverse scenario lacks actual forward and backward travel': change_case(self.log, 'male-empty-reverse-rest',
                lambda line, t: re.sub(r' x=[^ ]+ y=[^ ]+', ' x=100 y=100', line)),
            'actual final heading does not complete maneuver': change_case(self.log, 'male-empty-uturn-left',
                lambda line, t: re.sub(r'heading:[^,]+,', f'heading:{analyzer.H0},', line)),
        }
        for gate, log in cases.items():
            with self.subTest(gate=gate):
                self.assertIn(gate, self.failures(log))

    def test_idle_heading_only_rotation_requires_actual_handle_motion(self):
        log = change_case(self.log, 'male-empty-idle-swap-left',
                          lambda line, t: re.sub(r' x=[^ ]+ y=[^ ]+', ' x=100 y=100', line))
        self.assertIn('heading changes without measured movement', self.failures(log))

    def test_uturn_requires_motion_during_yaw_not_only_on_straight_segments(self):
        case = 'male-empty-uturn-left'
        rows = analyzer.selected_capture(self.log)[0][case]
        positions = {r['elapsed']: (r['x'], r['y']) for r in rows}
        for start, end in ((2200, 5500), (6500, 8800)):
            anchor = positions[start]
            dx, dy = positions[end][0] - anchor[0], positions[end][1] - anchor[1]
            for t, (x, y) in list(positions.items()):
                if start <= t <= end:
                    positions[t] = anchor
                elif t > end:
                    positions[t] = x - dx, y - dy
        log = change_case(self.log, case, lambda line, t:
                          re.sub(r' x=[^ ]+ y=[^ ]+', f' x={positions[t][0]} y={positions[t][1]}', line))
        self.assertIn('heading changes without measured movement', self.failures(log))

    def test_actual_opposite_travel_while_braking_is_rejected(self):
        def opposite(line, t):
            if t != 4300:
                return line
            x = float(re.search(r' x=([^ ]+)', line)[1])
            y = float(re.search(r' y=([^ ]+)', line)[1])
            return re.sub(r' x=[^ ]+ y=[^ ]+', f' x={x + .1} y={y - .1}', line)
        log = change_case(self.log, 'male-empty-reverse-moving', opposite)
        self.assertIn('actual movement reverses while braking', self.failures(log))

    def test_reversal_needs_measured_rest_and_early_cancel(self):
        rest = change_case(self.log, 'male-empty-reverse-moving',
                           lambda line, t: line.replace('ramp=speed:0,', 'ramp=speed:.2,') if t == 4700 else line)
        self.assertIn('direction flips before measured rest', self.failures(rest))
        early = change_case(self.log, 'male-empty-reverse-moving',
                            lambda line, t: line.replace('direction:1,', 'direction:-1,') if t == 3100 else line)
        self.assertIn('cancelled early reverse changes direction', self.failures(early))
        fast = change_case(self.log, 'male-empty-reverse-rest',
                           lambda line, t: line.replace('run=false ', 'run=true ') if t == 2000 else line)
        self.assertIn('fast gait during stationary or reverse motion', self.failures(fast))

    def test_cancel_quiet_restart_and_final_settling(self):
        case = 'male-empty-idle-swap-left'
        for gate, log in {
            'idle release does not cancel quietly': change_case(self.log, case,
                lambda line, t: line.replace('stationary:false', 'stationary:true') if t == 2100 else line),
            'idle steering does not restart': change_case(self.log, case,
                lambda line, t: line.replace('stationary:true', 'stationary:false') if t >= 2500 else line),
            'final release does not settle': change_case(self.log, case,
                lambda line, t: re.sub(r' x=[^ ]+', ' x=101', line) if t == 11800 else line),
        }.items():
            with self.subTest(gate=gate):
                self.assertIn(gate, self.failures(log))

    def test_native_stop_can_coast_for_2_2_seconds_before_quiet_tail(self):
        case = 'male-empty-reverse-moving'
        def coast(line, t):
            distance = .1 * min(2200, max(0, t - 9500)) / 2200
            x = float(re.search(r' x=([^ ]+)', line)[1])
            return re.sub(r' x=[^ ]+', f' x={x + distance}', line)
        log = change_case(self.log, case, coast)
        self.assertTrue(analyzer.analyze(log)['motionPass'])
        log = change_case(log, case, lambda line, t: '' if t >= 11900 else line)
        with self.assertRaisesRegex(AssertionError, 'settled maneuver tail'):
            analyzer.analyze(log)

    def test_uturn_wrong_signed_path_cannot_pass_same_wrapped_destination(self):
        # Both +/-180 end on the same wrapped heading; only the requested path is valid.
        def reverse_yaw(line, t):
            current = float(re.search(r'heading:([^,]+)', line)[1])
            other = analyzer.wrap(2 * analyzer.H0 - current)
            return re.sub(r'heading:[^,]+,', f'heading:{other},', line)
        log = change_case(self.log, 'male-empty-uturn-left', reverse_yaw)
        failures = self.failures(log)
        self.assertIn('U-turn yaws in the opposite direction', failures)
        self.assertIn('actual final heading does not complete maneuver', failures)

    def test_cli_explicit_log_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log, output = root / 'client1-launch.log', root / 'maneuvers.json'
            log.write_text(self.log)
            (root / 'native-launch.log').write_text('wrong legacy log')
            command = [sys.executable, str(SCRIPT), '--profile', str(root), '--log', str(log), '--output', str(output)]
            result = subprocess.run(command, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(json.loads(output.read_text())['motionPass'])
            original = output.read_bytes()
            self.assertNotEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertEqual(output.read_bytes(), original)
            output.unlink()
            log.write_text(change_case(self.log, 'male-empty-reverse-rest', lambda line, t: re.sub(r' x=[^ ]+ y=[^ ]+', ' x=0 y=0', line)))
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 1)
            self.assertFalse(json.loads(output.read_text())['motionPass'])


if __name__ == '__main__':
    unittest.main()
