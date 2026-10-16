"""Motion gates for forward/reverse transitions; geometry and video are separate evidence."""
import argparse
import json
import math
from pathlib import Path
import re

SPECS = ('walk-switch', 'run-switch', 'sprint-switch', 'cancel-switch', 'arc-switch')


def analyze(text):
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    assert re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases=20(?:\s|$)', log), 'Capture incomplete'
    assert '[WOOD_BANK] FAIL' not in log, 'Scenario failed'
    completed = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    expected = {f'{sex}-{cargo}-{spec}' for sex in ('male', 'female') for cargo in ('empty', 'full') for spec in SPECS}
    assert len(completed) == 20 and {name for name, _ in completed} == expected, 'Missing, duplicate or unexpected reversal cases'
    starts = {name: int(start) for name, start in completed}
    cases = {name: [] for name in starts}
    for line in log.splitlines():
        if '[WOOD_BANK_SAMPLE]' not in line:
            continue
        segments = re.search(r'\[WOOD_BANK_SAMPLE\] (.*?) reversal=(\S+) ramp=(\S+)', line)
        assert segments, 'Missing reversal/ramp diagnostics'
        header, reversal, ramp = segments.groups()
        row = dict(re.findall(r'(?:^| )(case|elapsed|wall|stepY|x|y|run|sprint)=([^ ]+)', header))
        name = row.get('case')
        assert name in starts, 'Unexpected sampled reversal case'
        row.update(re.findall(r'(?:^|,)(direction|requested|active|braking|actualDistance):([^,]+)', reversal))
        row.update(re.findall(r'(?:^|,)(speed|heading):([^,]+)', ramp))
        for key in ('x', 'y', 'stepY', 'speed', 'actualDistance', 'heading'):
            row[key] = float(row[key])
            assert math.isfinite(row[key]), 'Nonfinite reversal measurement: ' + key
        for key in ('run', 'sprint', 'active', 'braking'):
            assert row[key] in ('true', 'false'), 'Invalid reversal boolean: ' + key
            row[key] = row[key] == 'true'
        for key in ('direction', 'requested', 'wall', 'elapsed'):
            row[key] = int(row[key])
        assert row['direction'] in (-1, 1) and row['requested'] in (-1, 0, 1), 'Invalid reversal direction'
        if starts[name] <= row['wall'] < starts[name] + 12000:
            cases[name].append(row)
    summaries, failures = [], []
    for name, samples in cases.items():
        assert len(samples) >= 80, 'Insufficient reversal samples for ' + name
        intervals = [b['wall'] - a['wall'] for a, b in zip(samples, samples[1:])]
        assert all(b['elapsed'] > a['elapsed'] for a, b in zip(samples, samples[1:])), 'Non-monotonic reversal samples'
        assert min(intervals) > 0 and max(intervals) <= 1000, 'Incomplete reversal sample window'
        assert samples[0]['wall'] <= starts[name] + 500 and samples[-1]['wall'] >= starts[name] + 11500, 'Incomplete reversal sample edges'
        flips, opposite = [], []
        for last, row in zip(samples, samples[1:]):
            if row['direction'] != last['direction']:
                flip = {'elapsed': row['elapsed'], 'previousElapsed': last['elapsed'], 'previousSpeed': last['speed'],
                        'actualDistance': row['actualDistance'], 'previousActualDistance': last['actualDistance']}
                flips.append(flip)
                if last['speed'] > 1e-6 or last['actualDistance'] > 1e-6:
                    failures.append((name, 'flip before measured rest', flip))
            dt = (row['wall'] - last['wall']) / 1000
            signed = ((row['x'] - last['x']) * math.cos(last['heading']) + (row['y'] - last['y']) * math.sin(last['heading'])) / dt
            if row['braking'] and last['braking'] and signed * row['direction'] < -.02:
                opposite.append((row['elapsed'], signed))
        for row in samples:
            if row['braking'] and row['stepY'] * row['direction'] < -1e-6:
                failures.append((name, 'field reverses before stop', row))
            if row['requested'] == -1 and (row['run'] or row['sprint']):
                failures.append((name, 'fast reverse', row))
        if opposite:
            failures.append((name, 'opposite displacement while braking', opposite))
        if name.endswith(('walk-switch', 'run-switch', 'sprint-switch')) and len(flips) != 2:
            failures.append((name, 'expected two complete flips', flips))
        summaries.append({'case': name, 'samples': len(samples), 'flips': flips,
                          'oppositeDisplacementWhileBraking': len(opposite),
                          'zeroRootSamples': sum(row['speed'] == 0 for row in samples),
                          'brakingSamples': sum(row['braking'] for row in samples),
                          'intervalMs': {'min': min(intervals), 'max': max(intervals)}})
    return {'complete': True, 'caseCount': len(summaries), 'sampleCount': sum(len(rows) for rows in cases.values()),
            'cases': summaries, 'failures': failures, 'motionPass': not failures,
            'limit': 'Samples follow game updates; reported intervals are measured, not a guaranteed 25ms cadence. Native hook tests cover individual update ordering. Grip, geometry, wheel contact and visual quality require separate evidence.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--log', type=Path, help='Full native stdout; defaults to profile/native-launch.log')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert args.profile.is_dir(), 'Capture profile is missing'
    assert not args.output.exists(), 'Refuse to overwrite an existing report'
    result = analyze((args.log if args.log is not None else args.profile / 'native-launch.log').read_text(errors='replace'))
    with args.output.open('x') as output:
        json.dump(result, output, indent=2, allow_nan=False)
        output.write('\n')
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0 if result['motionPass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
