"""Collision reports require native controls, measured contact, escape and complete inputs."""
import importlib.util
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).parent / 'native_queue/contributions/wooden_cart_motion/analyze-collision.py'
spec = importlib.util.spec_from_file_location('cart_collision_analyzer', SCRIPT)
analyzer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analyzer)


def interpolate(t, knots):
    for (start, value), (end, target) in zip(knots, knots[1:]):
        if t <= end:
            return value + (target - value) * max(0, (t - start) / (end - start))
    return knots[-1][1]


def evidence():
    lines = ['[WOOD_BANK] RUN_STARTED']
    for index, name in enumerate(('wall', 'corner', 'passage')):
        start = 10000 + index * 10000
        lines.append(f'[CART_COLLISION_CONTROL] START spec={name} wall={start} x=10825.5 y=10142.5 wallX=10824 southY=10144 gapY=10142')
        for t in range(0, 4000, 100):
            x = interpolate(t, [(0, 10825.5), (2500 if name != 'passage' else 3900, 10824.3 if name != 'passage' else 10822.8)])
            y = interpolate(t, [(0, 10142.5), (2500, 10143.7)]) if name == 'corner' else 10142.5
            lines.append(f'[CART_COLLISION_CONTROL_SAMPLE] spec={name} wall={start+t} elapsed={t} x={x} y={y} heading={math.pi} drive={2 if name == "corner" else 5}')
        lines.append(f'[CART_COLLISION_CONTROL] COMPLETE spec={name} wall={start+4000} x={x} y={y}')
    for index, (sex, cargo, scenario) in enumerate((sex, cargo, scene) for sex in ('male', 'female')
            for cargo in ('empty', 'full') for scene in analyzer.SPECS):
        name, start = f'{sex}-{cargo}-{scenario}', 100000 + index * 15000
        start_x, start_y = (10824.3, 10143.7) if scenario == 'corner-pivot' else (10825.5, 10142.5)
        lines.append(f'[CART_COLLISION_LAYOUT] case={name} wallX=10824 southY=10144 gapY=10142 startX={start_x} startY={start_y} baselineX=10824.3 baselineY=10143.7')
        lines.append(f'[WOOD_BANK] CASE {name} attempt=0 wall={start}')
        events, heading, phase = analyzer.STEPS[scenario], analyzer.HEADINGS[scenario], 0.
        previous = start_x, start_y
        for t in range(0, 12000, 100):
            command = [event for event in events if event[0] < t]
            _, gait, drive = command[-1] if command else (0, 0, 0)
            if scenario == 'wall-block':
                x = interpolate(t, [(0, 10825.5), (1000, 10825.5), (3000, 10824.3), (7000, 10824.3), (9000, 10825.5)])
                y = 10142.5
            elif scenario == 'wall-slide':
                x = interpolate(t, [(0, 10825.5), (1000, 10825.5), (2500, 10824.05), (7000, 10824.05), (9000, 10824.95)])
                y = interpolate(t, [(0, 10142.5), (1000, 10142.5), (5800, 10144.5)])
                heading = interpolate(t, [(0, analyzer.HEADINGS[scenario]), (1000, analyzer.HEADINGS[scenario]), (4000, math.pi)])
            elif scenario == 'corner-pivot':
                x = 10824.3
                y = interpolate(t, [(0, 10143.7), (5000, 10143.7), (8000, 10142.7)])
            else:
                x = interpolate(t, [(0, 10825.5), (1000, 10825.5), (4000, 10822.8), (5000, 10822.8), (9000, 10825.5)])
                y = 10142.5
            distance = math.dist(previous, (x, y))
            phase = analyzer.wrap(phase - ((x - previous[0]) * math.cos(heading) + (y - previous[1]) * math.sin(heading)) / analyzer.WHEEL_RADIUS)
            previous = x, y
            moving = distance > 1e-8
            reverse = t > events[2][0]
            direction, requested = (-1 if reverse else 1), (-1 if reverse and drive else 1 if drive else 0)
            stationary = scenario == 'corner-pivot' and 1000 < t < 4000
            run = scenario in ('wall-block', 'wall-slide') and gait == 1 and moving
            clip = ('Bob_StrafeNoAim_Right' if stationary else 'Bob_WalkBwdNoAim1Hand' if reverse
                    else 'Bob_Run' if run else 'Bob_Walk')
            actual = .002 if moving else 0
            tracks = f'{clip}@1/{t/1000}/1;'
            root_heading = analyzer.wrap(heading)
            state = f'heading:{root_heading},target:{root_heading},stationary:{str(stationary).lower()},stationaryRoot:{str(stationary).lower()},actualDistance:{actual},axle:1,rootTracks:{tracks}'
            lines.append(f'[WOOD_BANK_SAMPLE] case={name} wall={start+t} elapsed={t} x={x} y={y} '
                f'run={str(run).lower()} sprint=false skill=10 speed=.8 drive={drive} requestedGait={gait} '
                f'stepX={1 if stationary else 0} stepY={direction if moving else 0} pace=1 wheelPhase={phase} bank=0 '
                f'reversal=direction:{direction},requested:{requested},active:false,braking:false,neutral:0,actualDistance:{actual},brakeTarget:{root_heading}, '
                f'ramp=speed:{.2 if moving else 0},velocity:0,sprintMomentum:0,load:{1 if cargo == "full" else 0},heading:{root_heading},target:0, '
                f'stationary={state} tracks={clip}=1@1;')
            for at, g, d in events:
                if at == t:
                    lines.append(f'[WOOD_RAMP_EVENT] case={name} elapsed={at} gait={g} drive={d}')
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start}')
    return '\n'.join(lines + ['[WOOD_BANK] ALL_COMPLETE cases=16'])


def change_case(log, case, callback):
    return '\n'.join(callback(line, int(re.search(r'elapsed=(\d+)', line)[1]))
                     if '[WOOD_BANK_SAMPLE]' in line and f'case={case} ' in line else line for line in log.splitlines())


class CollisionAnalyzerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.log = evidence()

    def failures(self, log):
        report = analyzer.analyze(log)
        self.assertFalse(report['motionPass'])
        return [failure[1] for failure in report['failures']]

    def test_complete_native_controls_and_matrix(self):
        report = analyzer.analyze(self.log)
        self.assertTrue(report['motionPass'], report['failures'])
        self.assertEqual((report['caseCount'], report['controlCount']), (16, 3))
        self.assertIn('no separate collision body', report['limit'])

    def test_control_tick_can_sample_at_completion_after_four_seconds(self):
        lines = []
        for line in self.log.splitlines():
            if '[CART_COLLISION_CONTROL] COMPLETE ' in line:
                raw = analyzer.fields(line.split(' COMPLETE ', 1)[1])
                wall = int(raw['wall']) + 10
                lines.append(f'[CART_COLLISION_CONTROL_SAMPLE] spec={raw["spec"]} wall={wall} elapsed=4010 x={raw["x"]} y={raw["y"]} heading=3.14 drive={2 if raw["spec"] == "corner" else 5}')
                line = re.sub(r'wall=\d+', f'wall={wall}', line)
            lines.append(line)
        self.assertTrue(analyzer.analyze('\n'.join(lines))['motionPass'])

    def test_strict_finite_header_and_diagnostic_boundaries(self):
        for bad in (self.log.replace('wheelPhase=0.0 ', 'wheelPhase=nan ', 1),
                    self.log.replace('wheelPhase=0.0 ', '', 1),
                    self.log.replace('wheelPhase=0.0 ', 'wheelPhase=0 wheelPhase=1 ', 1),
                    self.log.replace('skill=10 ', 'skill=nan ', 1),
                    self.log.replace('drive=0 ', 'drive=9 ', 1),
                    self.log.replace('baselineX=10824.3 ', 'baselineX=nan ', 1)):
            with self.subTest(bad=bad[:100]), self.assertRaises((AssertionError, ValueError)):
                analyzer.analyze(bad)
        modified = self.log.replace('tracks=Bob_', 'tracks=x=nan wheelPhase=nan heading=nan Bob_')
        self.assertTrue(analyzer.analyze(modified)['motionPass'])

    def test_missing_duplicate_cases_layouts_and_completion_fail(self):
        complete = next(line for line in self.log.splitlines() if '[WOOD_BANK] COMPLETE ' in line)
        layout = next(line for line in self.log.splitlines() if '[CART_COLLISION_LAYOUT]' in line)
        for bad in (self.log.replace(complete, ''), self.log + '\n' + complete,
                    self.log.replace(layout, ''), self.log.replace('ALL_COMPLETE cases=16', 'ALL_COMPLETE cases=160')):
            with self.assertRaises(AssertionError):
                analyzer.analyze(bad)

    def test_native_controls_require_real_complete_ordered_sample_coverage(self):
        variants = (
            '\n'.join(line for line in self.log.splitlines() if not ('CONTROL_SAMPLE]' in line and 'spec=wall ' in line)),
            self.log.replace('COMPLETE spec=corner', 'COMPLETE spec=wall'),
            self.log.replace('CONTROL_SAMPLE] spec=wall wall=10100 elapsed=100', 'CONTROL_SAMPLE] spec=wall wall=10000 elapsed=0'),
            self.log.replace('START spec=wall wall=10000 x=10825.5', 'START spec=wall wall=10000 x=nan'),
            self.log.replace('COMPLETE spec=wall wall=14000 x=10824.3', 'COMPLETE spec=wall wall=14000 x=10825.5'),
        )
        for bad in variants:
            with self.assertRaises((AssertionError, ValueError)):
                analyzer.analyze(bad)
        log = '\n'.join(re.sub(r' x=[^ ]+', ' x=10825.5', line)
                        if 'spec=wall ' in line and ('CONTROL_SAMPLE]' in line or 'COMPLETE' in line) else line
                        for line in self.log.splitlines())
        self.assertIn('native control does not reach wall contact', self.failures(log))

    def test_missing_input_stages_native_gaits_and_quiet_tail_fail(self):
        for bad in ('\n'.join(line for line in self.log.splitlines() if '[WOOD_RAMP_EVENT]' not in line),
                    change_case(self.log, 'male-empty-wall-block', lambda line, t: line.replace('drive=5 ', 'drive=0 ') if t == 2000 else line),
                    change_case(self.log, 'male-empty-passage', lambda line, t: '' if t >= 11900 else line)):
            with self.assertRaises(AssertionError):
                analyzer.analyze(bad)
        for case, old, new, reason in (
                ('male-empty-wall-block', 'run=true', 'run=false', 'native requested fast gait does not progress'),
                ('male-empty-wall-slide', 'Bob_Run@', 'Bob_Idle@', 'native requested fast gait does not progress'),
                ('male-empty-passage', 'Bob_WalkBwdNoAim1Hand@', 'Bob_Idle@', 'native reverse gait does not progress'),
                ('male-empty-corner-pivot', 'stationary:true', 'stationary:false', 'blocked corner pivot never engages stationary steering')):
            with self.subTest(case=case):
                self.assertIn(reason, self.failures(change_case(self.log, case, lambda line, t: line.replace(old, new))))

    def test_fully_blocked_pivot_can_keep_feet_planted(self):
        log = change_case(self.log, 'male-empty-corner-pivot',
                          lambda line, t: line.replace('Bob_StrafeNoAim_Right@', 'Bob_Idle@'))
        self.assertTrue(analyzer.analyze(log)['motionPass'])

    def test_wall_corner_and_passage_constraints(self):
        variants = {
            'character crosses a closed wall': change_case(self.log, 'male-empty-wall-block',
                lambda line, t: re.sub(r' x=[^ ]+', ' x=10823.9', line) if t == 4000 else line),
            'character crosses the corner wall': change_case(self.log, 'male-empty-corner-pivot',
                lambda line, t: re.sub(r' y=[^ ]+', ' y=10144.2', line) if t == 2000 else line),
            'passage never crosses west through the opening': change_case(self.log, 'male-empty-passage',
                lambda line, t: re.sub(r' x=[^ ]+', ' x=10825.5', line)),
            'passage never crosses east through the opening': change_case(self.log, 'male-empty-passage',
                lambda line, t: re.sub(r' x=[^ ]+', ' x=10822.8', line) if t > 5000 else line),
            'passage movement leaves the open gap': change_case(self.log, 'male-empty-passage',
                lambda line, t: re.sub(r' y=[^ ]+', ' y=10143.2', line) if t == 3000 else line),
            'wall slide has no accepted tangential movement': change_case(self.log, 'male-empty-wall-slide',
                lambda line, t: re.sub(r' y=[^ ]+', ' y=10142.5', line) if t <= 6000 else line),
        }
        for reason, log in variants.items():
            with self.subTest(reason=reason):
                self.assertIn(reason, self.failures(log))

    def test_wall_and_corner_reverse_must_actually_escape(self):
        for case, anchor, reason in (
                ('male-empty-wall-block', 'x=10824.3 y=10142.5', 'wall reverse does not escape'),
                ('male-empty-corner-pivot', 'x=10824.3 y=10143.7', 'corner reverse does not escape'),
                ('male-empty-wall-slide', 'x=10824.3 y=10144.5', 'wall slide reverse does not escape')):
            log = change_case(self.log, case, lambda line, t: re.sub(r'x=[^ ]+ y=[^ ]+', anchor, line) if t > 7000 or case.endswith('pivot') and t > 5000 else line)
            with self.subTest(case=case):
                self.assertIn(reason, self.failures(log))
        log = change_case(self.log, 'male-empty-passage', lambda line, t: line.replace('run=false ', 'run=true ') if t == 7000 else line)
        self.assertIn('fast gait during stationary or reverse motion', self.failures(log))

    def test_slide_uses_wall_plane_and_eastward_escape(self):
        case = 'male-empty-wall-slide'
        # A legitimate slide can approach the wall plane more closely than the frontal bare control.
        report = analyzer.analyze(self.log)
        scene = next(row for row in report['cases'] if row['case'] == case)
        self.assertAlmostEqual(scene['minX'], 10824.05)
        rounded = change_case(self.log, case,
                              lambda line, t: re.sub(r' x=[^ ]+', ' x=10823.999', line) if t == 4000 else line)
        self.assertTrue(analyzer.analyze(rounded)['motionPass'])
        crossed = change_case(self.log, case,
                              lambda line, t: re.sub(r' x=[^ ]+', ' x=10823.997', line) if t == 4000 else line)
        self.assertIn('character crosses a closed wall', self.failures(crossed))
        north_only = change_case(self.log, case,
                                 lambda line, t: re.sub(r' x=[^ ]+', ' x=10824.05', line) if t > 7000 else line)
        self.assertIn('wall slide reverse does not escape', self.failures(north_only))

    def test_basic_suite_does_not_accept_protected_impact_missing_state(self):
        def protected(line, t):
            if t == 2800:
                line = re.sub(r'wheelPhase=[^ ]+', 'wheelPhase=nan', line)
                line = re.sub(r' reversal=.*? tracks=', ' reversal=none ramp=none stationary=none tracks=', line)
            return line
        with self.assertRaises((AssertionError, ValueError)):
            analyzer.analyze(change_case(self.log, 'male-empty-wall-block', protected))

    def test_phantom_turn_spin_and_teleports_are_measured(self):
        for reason, log in {
            'heading changes without measured movement': change_case(self.log, 'male-empty-wall-block',
                lambda line, t: re.sub(r'heading:[^,]+,', f'heading:{math.pi + max(0, min(t - 3500, 1500)) / 10000},', line)),
            'wheel spins without measured movement': change_case(self.log, 'male-empty-wall-block',
                lambda line, t: re.sub(r'wheelPhase=([^ ]+)', lambda m: f'wheelPhase={float(m[1]) + max(0, min(t - 3500, 1500)) / 1000}', line)),
            'position jumps between samples': change_case(self.log, 'male-empty-passage',
                lambda line, t: re.sub(r' x=[^ ]+', ' x=10900', line) if t == 3000 else line),
            'final release does not settle': change_case(self.log, 'male-empty-wall-block',
                lambda line, t: re.sub(r' x=[^ ]+', ' x=10825.6', line) if t == 11900 else line),
        }.items():
            with self.subTest(reason=reason):
                self.assertIn(reason, self.failures(log))

    def test_rejected_attempt_diagnostics_cannot_contaminate_selected_capture(self):
        first = next(line for line in self.log.splitlines() if '[WOOD_BANK] CASE ' in line)
        name = 'male-empty-wall-block'
        rejected = f'[WOOD_BANK] CASE {name} attempt=0 wall=99999\n[WOOD_BANK_SAMPLE] case={name} x=nan\n'
        log = self.log.replace(first, rejected + first.replace('attempt=0', 'attempt=1'), 1)
        self.assertTrue(analyzer.analyze(log)['motionPass'])

    def test_positive_actual_distance_cannot_hide_heading_only_rotation(self):
        def fake_motion(line, t):
            if t < 1000:
                heading = math.pi + (.0002 * t if t < 900 else 0)
                line = re.sub(r'heading:[^,]+,', f'heading:{heading},', line)
                line = line.replace('actualDistance:0,', 'actualDistance:.002,')
            return line
        log = change_case(self.log, 'male-empty-wall-block', fake_motion)
        self.assertIn('heading changes without measured movement', self.failures(log))

    def test_gait_axle_translation_requires_matching_wheel_roll_even_when_actor_is_still(self):
        def gait_shift(multiplier):
            def change(line, t):
                shift = .031456377 if t >= 1100 else 0.
                x = float(re.search(r' x=([^ ]+)', line)[1])
                actual_x = 10825.5 if t == 1100 else x
                phase = float(re.search(r' wheelPhase=([^ ]+)', line)[1])
                phase -= ((actual_x - x) * math.cos(math.pi) + multiplier * shift) / analyzer.WHEEL_RADIUS
                line = re.sub(r' x=[^ ]+', f' x={actual_x}', line)
                line = re.sub(r' wheelPhase=[^ ]+', f' wheelPhase={analyzer.wrap(phase)}', line)
                return line.replace('axle:1,', f'axle:{1 + shift},')
            return change_case(self.log, 'male-empty-wall-block', change)
        valid = gait_shift(1)
        self.assertTrue(analyzer.analyze(valid)['motionPass'])
        for multiplier in (0, 2):
            with self.subTest(multiplier=multiplier):
                self.assertIn('wheel spins without measured movement', self.failures(gait_shift(multiplier)))

    def test_cli_explicit_log_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            log, output = root / 'client1-launch.log', root / 'collision.json'
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
            log.write_text(change_case(self.log, 'male-empty-wall-block', lambda line, t: re.sub(r' x=[^ ]+', ' x=10823', line) if t == 4000 else line))
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 1)
            self.assertFalse(json.loads(output.read_text())['motionPass'])


if __name__ == '__main__':
    unittest.main()
