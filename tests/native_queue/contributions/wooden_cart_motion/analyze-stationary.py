"""Stationary wheelbarrow gates; native mesh/grip and visual review remain separate."""
import argparse
import csv
import json
import math
from pathlib import Path
import re

STEPS = {
    'left': [(1000, 0, 1), (3500, 0, 0)],
    'right': [(1000, 0, 4), (3500, 0, 0)],
    'cancel-restart': [(1000, 2, 1), (1250, 0, 0), (2200, 0, 1), (4800, 0, 0)],
    'run-exit': [(1000, 1, 1), (6200, 0, 0)],
    'sprint-sequence': [(1000, 2, 1), (3800, 2, 3), (6500, 0, 0)],
}
SPECS = tuple(STEPS)


def wrap(value):
    return math.atan2(math.sin(value), math.cos(value))


def fields(text, separator='='):
    pairs = [part.split(separator, 1) for part in text.rstrip(',').split(' ' if separator == '=' else ',') if part]
    assert all(len(pair) == 2 for pair in pairs), 'Malformed stationary fields'
    result = dict(pairs)
    assert len(result) == len(pairs), 'Duplicate stationary fields'
    return result


def sample(line):
    # Stop at diagnostic boundaries: native tracks contain repeated names and punctuation.
    prefix, diagnostic = line.split(' stationary=', 1)
    diagnostic, _ = diagnostic.split(' tracks=', 1)
    numeric, tracks = diagnostic.split(',rootTracks:', 1)
    header = prefix.split('[WOOD_BANK_SAMPLE] ', 1)[1].split(' bank=', 1)[0]
    row = fields(header)
    state = fields(numeric, ':')
    assert set(state) == {'heading', 'target', 'stationary', 'stationaryRoot', 'actualDistance', 'axle'}, 'Missing or unexpected stationary diagnostics'
    row.update(state)
    for key in ('x', 'y', 'stepX', 'stepY', 'heading', 'target', 'actualDistance', 'axle'):
        row[key] = float(row[key])
        assert math.isfinite(row[key]), 'Nonfinite stationary measurement: ' + key
    for key in ('run', 'sprint', 'stationary', 'stationaryRoot'):
        assert row[key] in ('true', 'false'), 'Invalid stationary boolean: ' + key
        row[key] = row[key] == 'true'
    for key in ('wall', 'elapsed', 'drive', 'requestedGait'):
        row[key] = int(row[key])
    assert row['actualDistance'] >= 0 and row['axle'] > 0, 'Invalid stationary distance/axle'
    assert row['drive'] in range(5) and row['requestedGait'] in range(3), 'Invalid stationary input'
    row['clips'] = []
    for value in tracks.split(';'):
        if not value:
            continue
        name, value = value.split('@', 1)
        weight, time, speed = map(float, value.split('/'))
        assert all(math.isfinite(x) for x in (weight, time, speed)), 'Nonfinite native track'
        assert 0 <= weight <= 1.001 and time >= 0 and speed >= 0, 'Invalid native track'
        row['clips'].append(dict(name=name, weight=weight, time=time, speed=speed))
    return row


def analyze(text, wheel):
    assert '[WOOD_BANK] RUN_STARTED' in text, 'Missing stationary run boundary'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    assert re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases=20(?:\s|$)', log), 'Capture incomplete'
    assert '[WOOD_BANK] FAIL' not in log, 'Scenario failed'
    expected = {f'{sex}-{cargo}-{spec}' for sex in ('male', 'female') for cargo in ('empty', 'full') for spec in SPECS}
    completed = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    assert len(completed) == 20 and {name for name, _ in completed} == expected, 'Missing, duplicate or unexpected stationary cases'
    starts = {name: int(start) for name, start in completed}
    attempts = re.findall(r'\[WOOD_BANK\] CASE (\S+) attempt=\d+ wall=(\d+)', log)
    assert all(attempts.count((name, str(start))) == 1 for name, start in starts.items()), 'Missing or duplicate selected stationary attempt'
    cases, events = {name: [] for name in starts}, {name: [] for name in starts}
    active = None
    for line in log.splitlines():
        attempt = re.search(r'\[WOOD_BANK\] CASE (\S+) attempt=\d+ wall=(\d+)', line)
        if attempt:
            active = attempt[1] if starts.get(attempt[1]) == int(attempt[2]) else None
        event = re.search(r'\[WOOD_RAMP_EVENT\] case=(\S+) elapsed=(\d+) gait=(\d+) drive=(\d+)', line)
        if event and active is not None:
            name, elapsed, gait, drive = event.groups()
            assert name == active, 'Stationary event disagrees with selected attempt'
            events[name].append((int(elapsed), int(gait), int(drive)))
    for line in log.splitlines():
        if '[WOOD_BANK_SAMPLE]' not in line:
            continue
        row = sample(line)
        name = row['case']
        assert name in cases, 'Unexpected stationary sample'
        if not starts[name] <= row['wall'] < starts[name] + 12000:
            continue
        assert abs(row['wall'] - starts[name] - row['elapsed']) <= 5, 'Stationary clocks disagree'
        cases[name].append(row)
    failures, summaries = [], []
    for name, rows in cases.items():
        spec, start = name.split('-', 2)[2], starts[name]
        assert len(rows) >= 80, 'Insufficient stationary samples for ' + name
        gaps = [b['wall'] - a['wall'] for a, b in zip(rows, rows[1:])]
        assert min(gaps) > 0 and max(gaps) <= 500, 'Incomplete stationary sample window'
        assert rows[0]['elapsed'] <= 500 and rows[-1]['elapsed'] >= 11500, 'Incomplete stationary sample edges'
        actual = events[name]
        assert [(g, d) for _, g, d in actual] == [(g, d) for _, g, d in STEPS[spec]], 'Missing or reordered stationary input events'
        assert all(abs(a[0] - b[0]) <= 500 for a, b in zip(actual, STEPS[spec])), 'Late stationary input events'
        assert all(b[0] > a[0] for a, b in zip(actual, actual[1:])), 'Non-monotonic stationary input events'
        pivot = [r for r in rows if r['stationary']]
        if len(pivot) < 3:
            failures.append((name, 'stationary turn never engaged'))
        if any(r['run'] or r['sprint'] or any(c['name'] in ('Bob_Run', 'Bob_Sprint') and c['weight'] > .1 for c in r['clips']) for r in pivot):
            failures.append((name, 'fast gait during stationary turn'))
        if any(abs(r['stepY']) > .015 for r in pivot if abs(r['stepX']) > .05):
            failures.append((name, 'stationary gait has forward/backward input'))
        wrong_side = [r for r in pivot if abs(wrap(r['target'] - r['heading'])) > .03
                      and r['stepX'] * wrap(r['target'] - r['heading']) > .001]
        if wrong_side:
            failures.append((name, 'stationary gait steps in opposite direction'))
        clips = [(r['elapsed'], c) for r in pivot for c in r['clips']
                 if c['name'] in ('Bob_StrafeNoAim_Left', 'Bob_StrafeNoAim_Right') and c['weight'] > .1 and c['speed'] > 0]
        progressing = any(a['name'] == b['name'] and t1 > t0 and abs(b['time'] - a['time']) > .001
                          for (t0, a), (t1, b) in zip(clips, clips[1:]))
        if not progressing:
            failures.append((name, 'native lateral gait does not progress'))
        wrong_clip = False
        for row in pivot:
            active_clips = [c for c in row['clips'] if c['name'] in ('Bob_StrafeNoAim_Left', 'Bob_StrafeNoAim_Right') and c['weight'] > .1]
            if not active_clips or abs(wrap(row['target'] - row['heading'])) < .03:
                continue
            expected_clip = 'Bob_StrafeNoAim_Left' if wrap(row['target'] - row['heading']) > 0 else 'Bob_StrafeNoAim_Right'
            wrong_clip |= max(active_clips, key=lambda c: c['weight'])['name'] != expected_clip
        if wrong_clip:
            failures.append((name, 'native lateral gait uses opposite side'))
        # Each contiguous pivot keeps its axle fixed; gaps delimit cancellation/restart.
        runs, previous_pivot = [], False
        for row in rows:
            if row['stationary']:
                if not runs or not previous_pivot:
                    runs.append([])
                runs[-1].append(row)
            previous_pivot = row['stationary']
        axle_drift = 0
        for run in runs:
            anchors = [(r['x'] + r['axle'] * math.cos(r['heading']), r['y'] + r['axle'] * math.sin(r['heading'])) for r in run]
            axle_drift = max(axle_drift, max(math.dist(anchors[0], p) for p in anchors))
        if axle_drift > .025:
            failures.append((name, 'front axle translates during stationary turn', axle_drift))
        initial = rows[0]['heading']
        sign = -1 if spec == 'right' else 1
        final_target = initial + sign * (math.pi if spec == 'sprint-sequence' else math.pi / 2)
        release = actual[-1][0]
        settled = [r for r in rows if release - 400 <= r['elapsed'] < release]
        final_error = min((abs(wrap(r['heading'] - final_target)) for r in settled), default=math.pi)
        if final_error > math.radians(4) or not settled or all(r['stationary'] for r in settled):
            failures.append((name, 'stationary heading did not converge and exit', final_error))
        if any(r['stationary'] for r in rows if release + 150 <= r['elapsed']):
            failures.append((name, 'stationary latch survives release'))
        if spec == 'cancel-restart':
            quiet = [r for r in rows if actual[1][0] + 200 <= r['elapsed'] < actual[2][0]]
            if not quiet or any(r['stationary'] for r in quiet) or max(abs(wrap(r['heading'] - quiet[0]['heading'])) for r in quiet) > math.radians(1) or max(math.hypot(r['x'] - quiet[0]['x'], r['y'] - quiet[0]['y']) for r in quiet) > .01:
                failures.append((name, 'release did not cancel stationary turn'))
            if not any(r['stationary'] and r['elapsed'] >= actual[2][0] for r in rows):
                failures.append((name, 'stationary turn did not restart'))
        if spec in ('run-exit', 'sprint-sequence'):
            flag = 'run' if spec == 'run-exit' else 'sprint'
            if not any(r[flag] and not r['stationary'] and r['actualDistance'] > 1e-5 for r in rows if actual[0][0] < r['elapsed'] < release):
                failures.append((name, 'held modifier did not resume after stationary turn'))
        wheel_drift, wheel_roll, wheel_count = 0, 0, 0
        for run in runs:
            # Existing render probe observes the actual transformed wheel center.
            frames = [{key: float(r[key]) for key in ('wallTimeMillis', 'wheelX', 'wheelY', 'phase')}
                      for r in wheel if start + run[0]['elapsed'] <= r['wallTimeMillis'] <= start + run[-1]['elapsed']]
            assert all(math.isfinite(value) for row in frames for value in row.values()), 'Nonfinite native stationary wheel measurement in selected pivot: ' + name
            stamps = sorted({r['wallTimeMillis'] for r in frames})
            if len(stamps) < 3 or frames[0]['wallTimeMillis'] > start + run[0]['elapsed'] + 200 or frames[-1]['wallTimeMillis'] < start + run[-1]['elapsed'] - 200:
                failures.append((name, 'missing native stationary wheel coverage'))
                continue
            times = [b - a for a, b in zip(stamps, stamps[1:])]
            if min(times) <= 0 or max(times) > 500:
                failures.append((name, 'incomplete native stationary wheel coverage'))
            wheel_count += len(frames)
            wheel_drift = max(wheel_drift, max(math.hypot(r['wheelX'] - frames[0]['wheelX'], r['wheelY'] - frames[0]['wheelY']) for r in frames))
            phase = 0
            for a, b in zip(frames, frames[1:]):
                phase += wrap(b['phase'] - a['phase'])
                wheel_roll = max(wheel_roll, abs(phase) * .001062454 * 76.5 * 1.5)
        # The calibrated wheel center has a ~.01 tile lateral offset from the steering axis.
        if wheel_drift > .05:
            failures.append((name, 'native wheel translates during stationary turn', wheel_drift))
        if wheel_roll > .05:
            failures.append((name, 'native wheel rolls during stationary turn', wheel_roll))
        summaries.append(dict(case=name, samples=len(rows), stationarySamples=len(pivot), nativeStrafeSamples=len(clips),
                              axleDriftTiles=axle_drift, nativeWheelSamples=wheel_count, nativeWheelDriftTiles=wheel_drift, nativeWheelRollTiles=wheel_roll,
                              finalHeadingErrorDegrees=math.degrees(final_error), intervalMs=dict(min=min(gaps), max=max(gaps))))
    return dict(complete=True, caseCount=len(summaries), cases=summaries, failures=failures, motionPass=not failures,
                limit='Measured update/render samples; unresolved inter-sample motion is not checked. Axle drift tolerance .025 tiles; actual wheel center tolerance .05 includes its calibrated lateral offset. Native grip, mesh, floor and video review remain separate gates.')


def read_wheel(path):
    with path.open() as stream:
        rows = []
        for row in csv.DictReader(stream):
            if row['event'] != 'grounding':
                continue
            # Bootstrap and rejected attempts can have no prepared wheel phase.
            point = {key: row[key] for key in ('wallTimeMillis', 'wheelX', 'wheelY', 'phase')}
            point['wallTimeMillis'] = float(point['wallTimeMillis'])
            assert math.isfinite(point['wallTimeMillis']), 'Nonfinite native wheel timestamp'
            rows.append(point)
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--log', type=Path, help='Full native stdout; defaults to profile/native-launch.log')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert args.profile.is_dir(), 'Capture profile is missing'
    assert not args.output.exists(), 'Refuse to overwrite an existing report'
    result = analyze((args.log or args.profile / 'native-launch.log').read_text(errors='replace'),
                     read_wheel(args.profile / 'wood-wheel-native.csv'))
    with args.output.open('x') as output:
        json.dump(result, output, indent=2, allow_nan=False)
        output.write('\n')
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0 if result['motionPass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
