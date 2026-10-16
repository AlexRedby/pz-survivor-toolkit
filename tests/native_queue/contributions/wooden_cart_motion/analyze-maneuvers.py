"""Measured motion gates for the wooden cart maneuver matrix; visual review is separate."""
import argparse
import importlib.util
import json
import math
from pathlib import Path
import re

_parser = importlib.util.spec_from_file_location('cart_stationary_samples', Path(__file__).with_name('analyze-stationary.py'))
_stationary = importlib.util.module_from_spec(_parser)
_parser.loader.exec_module(_stationary)
wrap = _stationary.wrap
H0 = 3 * math.pi / 4
STEPS = {
    'idle-swap-left': [(1000, 0, 1), (1350, 0, 4), (1700, 0, 0), (2500, 0, 4), (6200, 0, 0)],
    'idle-swap-right': [(1000, 0, 4), (1350, 0, 1), (1700, 0, 0), (2500, 0, 1), (6200, 0, 0)],
    'moving-swap-left': [(1000, 1, 2), (2200, 1, 1), (2550, 1, 4), (6200, 0, 0), (7000, 0, 4), (9000, 0, 0)],
    'moving-swap-right': [(1000, 1, 2), (2200, 1, 4), (2550, 1, 1), (6200, 0, 0), (7000, 0, 1), (9000, 0, 0)],
    'reverse-rest': [(1000, 2, 3), (3800, 1, 2), (8000, 0, 0)],
    'reverse-moving': [(1000, 2, 2), (3000, 2, 3), (3150, 2, 2), (4000, 2, 3), (6500, 2, 2), (9500, 0, 0)],
    'uturn-left': [(1000, 0, 2), (2200, 0, 1), (5200, 0, 3), (5550, 0, 0), (6500, 0, 3), (9500, 0, 0)],
    'uturn-right': [(1000, 0, 2), (2200, 0, 4), (5200, 0, 3), (5550, 0, 0), (6500, 0, 3), (9500, 0, 0)],
}
SPECS = tuple(STEPS)


def sample(line):
    row = _stationary.sample(line)
    prefix = line.split(' stationary=', 1)[0]
    reversal, ramp = prefix.split(' reversal=', 1)[1].split(' ramp=', 1)
    state = _stationary.fields(reversal, ':')
    assert set(state) == {'direction', 'requested', 'active', 'braking', 'neutral', 'actualDistance', 'brakeTarget'}, 'Missing or unexpected reversal diagnostics'
    ramp = _stationary.fields(ramp, ':')
    for key in ('speed', 'heading'):
        assert key in ramp, 'Missing maneuver ramp diagnostic: ' + key
        row['ramp' + key.title()] = float(ramp[key])
        assert math.isfinite(row['ramp' + key.title()]), 'Nonfinite maneuver ramp: ' + key
    for key in ('direction', 'requested'):
        row[key] = int(state[key])
    for key in ('active', 'braking'):
        assert state[key] in ('true', 'false'), 'Invalid maneuver boolean: ' + key
        row[key] = state[key] == 'true'
    for key in ('neutral', 'actualDistance', 'brakeTarget'):
        row['reversal' + key[0].upper() + key[1:]] = float(state[key])
        assert math.isfinite(row['reversal' + key[0].upper() + key[1:]]), 'Nonfinite maneuver reversal: ' + key
    assert row['direction'] in (-1, 1) and row['requested'] in (-1, 0, 1), 'Invalid maneuver reversal direction'
    assert row['rampSpeed'] >= 0 and row['reversalNeutral'] >= 0 and row['reversalActualDistance'] >= 0, 'Invalid maneuver motion measurement'
    assert abs(wrap(row['heading'] - row['rampHeading'])) < .001, 'Maneuver heading diagnostics disagree'
    return row


def selected_capture(text):
    assert '[WOOD_BANK] RUN_STARTED' in text, 'Missing maneuver run boundary'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[1]
    assert re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases=32(?:\s|$)', log), 'Capture incomplete'
    assert '[WOOD_BANK] FAIL' not in log, 'Scenario failed'
    expected = {f'{sex}-{cargo}-{spec}' for sex in ('male', 'female') for cargo in ('empty', 'full') for spec in SPECS}
    completed = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    assert len(completed) == 32 and {name for name, _ in completed} == expected, 'Missing, duplicate or unexpected maneuver cases'
    starts = {name: int(start) for name, start in completed}
    attempts = re.findall(r'\[WOOD_BANK\] CASE (\S+) attempt=\d+ wall=(\d+)', log)
    assert all(attempts.count((name, str(start))) == 1 for name, start in starts.items()), 'Missing or duplicate selected maneuver attempt'
    cases, events = {name: [] for name in starts}, {name: [] for name in starts}
    active = None
    for line in log.splitlines():
        attempt = re.search(r'\[WOOD_BANK\] CASE (\S+) attempt=\d+ wall=(\d+)', line)
        if attempt:
            active = attempt[1] if starts.get(attempt[1]) == int(attempt[2]) else None
        event = re.search(r'\[WOOD_RAMP_EVENT\] case=(\S+) elapsed=(\d+) gait=(\d+) drive=(\d+)', line)
        if event and active is not None:
            name, elapsed, gait, drive = event.groups()
            assert name == active, 'Maneuver event disagrees with selected attempt'
            events[name].append((int(elapsed), int(gait), int(drive)))
        if '[WOOD_BANK_SAMPLE]' in line and active is not None:
            row = sample(line)
            assert row['case'] == active, 'Maneuver sample disagrees with selected attempt'
            assert row['wall'] >= starts[active], 'Maneuver sample precedes selected window'
            if row['wall'] >= starts[active] + 12000:
                continue
            assert abs(row['wall'] - starts[active] - row['elapsed']) <= 5, 'Maneuver clocks disagree'
            cases[active].append(row)
    return cases, events


def analyze(text):
    cases, events = selected_capture(text)
    summaries, failures = [], []
    for name, rows in cases.items():
        spec = name.split('-', 2)[2]
        assert len(rows) >= 80, 'Insufficient maneuver samples for ' + name
        intervals = [b['wall'] - a['wall'] for a, b in zip(rows, rows[1:])]
        assert min(intervals) > 0 and max(intervals) <= 500, 'Incomplete maneuver sample window'
        assert rows[0]['elapsed'] <= 500 and rows[-1]['elapsed'] >= 11500, 'Incomplete maneuver sample edges'
        actual = events[name]
        assert [(g, d) for _, g, d in actual] == [(g, d) for _, g, d in STEPS[spec]], 'Missing or reordered maneuver input events'
        assert all(abs(a[0] - b[0]) <= 500 for a, b in zip(actual, STEPS[spec])), 'Late maneuver input events'
        assert all(b[0] > a[0] for a, b in zip(actual, actual[1:])), 'Non-monotonic maneuver input events'
        stages = [(0, 0, 0), *actual, (12000, 0, 0)]
        for index, (elapsed, gait, drive) in enumerate(stages[:-1]):
            end = stages[index + 1][0]
            # Lua prints the sample before applying that tick's event.
            margin = min(200, (end - elapsed) / 4)
            matching = [r for r in rows if elapsed + margin <= r['elapsed'] < end - margin
                        and (r['requestedGait'], r['drive']) == (gait, drive)]
            assert matching, 'Missing sampled maneuver input stage: ' + name
            assert all((r['requestedGait'], r['drive']) == (gait, drive) for r in rows
                       if elapsed + 200 < r['elapsed'] < end), 'Sampled maneuver input disagrees with events: ' + name
        def fail(reason, value=None):
            failures.append((name, reason) if value is None else (name, reason, value))
        def window(start, end):
            return [r for r in rows if start <= r['elapsed'] < end]
        yaw, travel, flips = [rows[0]['heading']], [], []
        motionless_yaw = 0
        for index, (previous, row) in enumerate(zip(rows, rows[1:])):
            dt = (row['wall'] - previous['wall']) / 1000
            turn = wrap(row['heading'] - previous['heading'])
            yaw.append(yaw[-1] + turn)
            row['unwrapped'] = yaw[-1]
            dx, dy = row['x'] - previous['x'], row['y'] - previous['y']
            distance = math.hypot(dx, dy)
            motionless_yaw = motionless_yaw + turn if distance <= .002 else 0
            if abs(motionless_yaw) > math.radians(2):
                fail('heading changes without measured movement', row['elapsed'])
            if distance > 8 * dt + .02:
                fail('position jumps between samples', row['elapsed'])
            if abs(turn) > 3 * dt + .05:
                fail('heading snaps between samples', row['elapsed'])
            signed = dx * math.cos(previous['heading'] + turn / 2) + dy * math.sin(previous['heading'] + turn / 2)
            if (previous['braking'] and row['braking'] and previous['direction'] == row['direction']
                    and signed * row['direction'] < -max(.002, .02 * dt)):
                fail('actual movement reverses while braking', row['elapsed'])
            if not row['stationaryRoot'] and not previous['stationaryRoot']:
                travel.append((row['elapsed'], signed))
            if row['direction'] != previous['direction']:
                flips.append(row['elapsed'])
                # An at-rest initial request may flip immediately; moving flips need a measured quiet sample.
                rest = previous['rampSpeed'] <= .001 and previous['reversalActualDistance'] <= .002
                if index > 0:
                    before = rows[index - 1]
                    rest &= math.hypot(previous['x'] - before['x'], previous['y'] - before['y']) <= .004
                if not rest:
                    fail('direction flips before measured rest', row['elapsed'])
            if row['braking'] and row['stepY'] * row['direction'] < -1e-6:
                fail('movement input reverses while braking', row['elapsed'])
        rows[0]['unwrapped'] = yaw[0]
        if abs(wrap(rows[0]['heading'] - H0)) > math.radians(4):
            fail('initial heading differs from fixture')
        if any((r['stationaryRoot'] or r['requested'] < 0 or r['direction'] < 0) and (r['run'] or r['sprint']) for r in rows):
            fail('fast gait during stationary or reverse motion')
        quiet = window(max(11500, actual[-1][0] + 2250), 12000)
        assert len(quiet) >= 2, 'Insufficient settled maneuver tail samples: ' + name
        if (any(r['stationary'] or r['braking'] or r['run'] or r['sprint'] for r in quiet)
                or max(math.dist((quiet[0]['x'], quiet[0]['y']), (r['x'], r['y'])) for r in quiet) > .01
                or max(abs(r['unwrapped'] - quiet[0]['unwrapped']) for r in quiet) > math.radians(1)):
            fail('final release does not settle')
        final_offset = 0
        if 'swap' in spec:
            sign = 1 if spec.endswith('left') else -1
            final_offset = -sign * math.pi / 2
            first, switched = (0, 1) if spec.startswith('idle') else (1, 2)
            early = window(actual[first][0], actual[switched][0] + 1)
            if not early or sign * (early[-1]['unwrapped'] - early[0]['unwrapped']) < math.radians(.5):
                fail('first steering side has no signed yaw')
            if spec.startswith('idle'):
                cancelled = window(actual[2][0] + 200, actual[3][0])
                if (not cancelled or any(r['stationary'] for r in cancelled)
                        or max(abs(r['unwrapped'] - cancelled[0]['unwrapped']) for r in cancelled) > math.radians(1)
                        or max(math.dist((cancelled[0]['x'], cancelled[0]['y']), (r['x'], r['y'])) for r in cancelled) > .01):
                    fail('idle release does not cancel quietly')
                if not any(r['stationary'] for r in window(actual[3][0] + 200, actual[4][0])):
                    fail('idle steering does not restart')
            else:
                if sum(max(0, d) for t, d in travel if actual[0][0] < t < actual[1][0]) < .02:
                    fail('moving steering has no initial forward travel')
                if sum(max(0, d) for t, d in travel if actual[4][0] + 200 < t < actual[5][0]) < .02:
                    fail('moving steering does not restart')
        elif spec.startswith('reverse'):
            forward = sum(d for _, d in travel if d > .002)
            backward = -sum(d for _, d in travel if d < -.002)
            if min(forward, backward) < .02:
                fail('reverse scenario lacks actual forward and backward travel', dict(forward=forward, backward=backward))
            if len(flips) != 2:
                fail('reverse scenario requires two direction flips', flips)
            if spec == 'reverse-moving' and any(r['direction'] < 0 for r in rows if r['elapsed'] < actual[3][0]):
                fail('cancelled early reverse changes direction')
        else:
            sign = 1 if spec.endswith('left') else -1
            final_offset = sign * math.pi
            opposite_yaw = sum(max(0, -sign * wrap(b['heading'] - a['heading'])) for a, b in zip(rows, rows[1:]))
            if opposite_yaw > math.radians(6):
                fail('U-turn yaws in the opposite direction', math.degrees(opposite_yaw))
            if any(r['direction'] < 0 for r in rows):
                fail('U-turn becomes reverse instead of completing its arc')
            if sum(max(0, d) for t, d in travel if actual[4][0] + 200 < t < actual[5][0]) < .02:
                fail('U-turn does not restart after release')
        final_error = max(abs(r['unwrapped'] - H0 - final_offset) for r in quiet)
        if final_error > math.radians(4):
            fail('actual final heading does not complete maneuver', math.degrees(final_error))
        summaries.append(dict(case=name, samples=len(rows), directionFlipsMs=flips,
                              signedYawDegrees=math.degrees(yaw[-1] - yaw[0]),
                              forwardTravelTiles=sum(max(0, d) for _, d in travel), backwardTravelTiles=-sum(min(0, d) for _, d in travel),
                              finalHeadingErrorDegrees=math.degrees(final_error), intervalMs=dict(min=min(intervals), max=max(intervals))))
    return dict(complete=True, caseCount=len(summaries), sampleCount=sum(len(rows) for rows in cases.values()),
                cases=summaries, failures=failures, motionPass=not failures,
                limit='Measured update samples only; motion between samples is unresolved. Input boundaries allow 200ms and settled position allows .01 tiles for native rounding. Broad continuity bounds are 8 tiles/s and 3 rad/s. Native geometry, wheel/grip contact and video review remain separate gates; this report makes no visual PASS claim.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--log', type=Path, help='Native stdout; defaults to profile/native-launch.log')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert args.profile.is_dir(), 'Capture profile is missing'
    assert not args.output.exists(), 'Refuse to overwrite an existing report'
    result = analyze((args.log or args.profile / 'native-launch.log').read_text(errors='replace'))
    with args.output.open('x') as output:
        json.dump(result, output, indent=2, allow_nan=False)
        output.write('\n')
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0 if result['motionPass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
