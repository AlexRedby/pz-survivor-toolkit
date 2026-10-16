"""Motion-only gates for scenario-reverse.lua; geometry/video require separate evidence."""
from pathlib import Path
import argparse
import json
import math
import re

SPECS = ('back-modifiers', 'back-arc-left', 'back-arc-right', 'u-turn-control', 'start-turn-control')


def wrap(angle):
    return math.atan2(math.sin(angle), math.cos(angle))


def read_samples(log, starts):
    rows = {name: [] for name in starts}
    for line in log.splitlines():
        if '[WOOD_BANK_SAMPLE]' not in line:
            continue
        data = dict(re.findall(r'(case|wall|elapsed|run|sprint|requestedGait|speed|pace|stepY|x|y|ramp)=([^ ]+)', line))
        name = data['case']
        if name not in starts or not starts[name] <= int(data['wall']) <= starts[name] + 12000:
            continue
        row = {key: float(data[key]) for key in ('elapsed', 'speed', 'pace', 'stepY', 'x', 'y')}
        row['heading'] = float(dict(re.findall(r'(heading):([^,]+)', data['ramp']))['heading'])
        assert all(math.isfinite(value) for value in row.values()), 'Non-finite motion sample'
        assert data['run'] in ('true', 'false') and data['sprint'] in ('true', 'false'), 'Invalid native gait boolean'
        assert data['requestedGait'] in ('0', '1', '2'), 'Invalid requested gait'
        row['requestedGait'] = int(data['requestedGait'])
        row['run'], row['sprint'] = data['run'] == 'true', data['sprint'] == 'true'
        rows[name].append(row)
    return rows


def analyze(text):
    assert '[WOOD_BANK] RUN_STARTED' in text, 'No scenario run'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    complete = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    starts = {name: int(time) for name, time in complete}
    expected = {sex+'-'+cargo+'-'+spec for sex in ('male', 'female') for cargo in ('empty', 'full') for spec in SPECS}
    assert len(complete) == 20 and set(starts) == expected, 'Require 20 unique completed cases'
    assert '[WOOD_BANK] ALL_COMPLETE cases=20' in log and '[WOOD_BANK] FAIL' not in log, 'Incomplete or failed run'
    rows = read_samples(log, starts)
    result = {'scope': 'motion-only; grip, geometry, floor and visual sequence require separate evidence', 'cases': []}
    for name, samples in rows.items():
        assert len(samples) >= 80, 'Insufficient samples for '+name
        assert all(b['elapsed'] > a['elapsed'] for a, b in zip(samples, samples[1:])), 'Non-monotonic samples'
        first, last = samples[0]['heading'], samples[-1]['heading']
        moving = [row for row in samples if 1800 < row['elapsed'] < (9500 if 'back-' in name else 10500)]
        checks = {'nativeWalk': bool(moving) and all(not row['run'] and not row['sprint'] for row in moving)}
        row = {'case': name, 'checks': checks, 'samples': len(samples), 'yawDegrees': math.degrees(wrap(last-first))}
        if 'back-' in name:
            stages = [(1800, 3300, 0), (3800, 5300, 1), (5800, 7300, 2), (7800, 9300, 0)] if 'back-modifiers' in name else [(1800, 3300, 0), (3800, 6300, 2), (6800, 9300, 0)]
            checks['requestedGaitStages'] = all(
                len(observed := [sample for sample in samples if begin < sample['elapsed'] < end]) >= 5
                and all(sample['requestedGait'] == gait for sample in observed)
                for begin, end, gait in stages)
            checks['backwardStep'] = all(sample['stepY'] < 0 for sample in moving)
            settled = [sample for sample in moving if sample['elapsed'] > 4500]
            checks['authoredPace'] = bool(settled) and all(abs(sample['pace']-1.04) < .002 for sample in settled)
            if 'back-modifiers' in name:
                checks['fixedHeading'] = all(abs(wrap(sample['heading']-first)) < math.radians(1) for sample in samples)
                a, b = moving[0], moving[-1]
                forward = (b['x']-a['x'])*math.cos(first)+(b['y']-a['y'])*math.sin(first)
                side = -(b['x']-a['x'])*math.sin(first)+(b['y']-a['y'])*math.cos(first)
                checks['reverseTravel'] = forward < -.1 and abs(side) < .05
                row['reverseDistance'], row['lateralDrift'] = -forward, side
            else:
                checks['reverseArcSettles'] = abs(wrap(last-math.pi*.75)) < math.radians(2)
                travel = [(b['x']-a['x'])*math.cos(a['heading'])+(b['y']-a['y'])*math.sin(a['heading'])
                          for a, b in zip(moving, moving[1:])]
                checks['reverseArcTravel'] = sum(travel) < -.1 and sum(max(0, value) for value in travel) < .01
            row['meanWalkSpeed'] = sum(sample['speed'] for sample in settled)/len(settled)
        else:
            wanted = 180 if 'u-turn' in name else 90
            checks['requestedYaw'] = abs(abs(row['yawDegrees'])-wanted) < 5
        stop = 6000 if 'start-turn' in name else 10500 if 'u-turn' in name else 9500
        idle = [sample for sample in samples if sample['elapsed'] > stop+500]
        checks['stops'] = len(idle) >= 5 and max(math.hypot(sample['x']-idle[0]['x'], sample['y']-idle[0]['y']) for sample in idle) < .005
        result['cases'].append(row)
    result['cargoSlowsReverse'] = all(
        next(row['meanWalkSpeed'] for row in result['cases'] if row['case'] == sex+'-full-back-modifiers')
        < next(row['meanWalkSpeed'] for row in result['cases'] if row['case'] == sex+'-empty-back-modifiers')
        for sex in ('male', 'female'))
    result['motionPass'] = result['cargoSlowsReverse'] and all(all(row['checks'].values()) for row in result['cases'])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True, help='New JSON report; existing files are refused')
    args = parser.parse_args()
    result = analyze((args.profile/'console.txt').read_text(errors='replace'))
    with args.output.open('x') as file:
        json.dump(result, file, indent=2)
        file.write('\n')
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result['motionPass'] else 1)


if __name__ == '__main__':
    main()
