"""Compare recorded fast stops with modifier-first Walk stops; no visual quality oracle."""
from pathlib import Path
import argparse
import csv
import json
import math
import re
import statistics

CASES = {f'male-{cargo}-{gait}-stop' for cargo in ('empty', 'full') for gait in ('run', 'sprint')}
GAP_MS = 200
POSITION_TOLERANCE = 1e-5
POSE_TOLERANCE = .002
POSE_QUIET_MS = 300


def require(condition, message):
    if not condition:
        raise ValueError(message)


def cadence(rows):
    intervals = [b['wall']-a['wall'] for a, b in zip(rows, rows[1:])]
    return dict(min=min(intervals), median=statistics.median(intervals), max=max(intervals))


def coverage(rows, start, end, label):
    selected = [row for row in rows if start <= row['wall'] < end]
    require(len(selected) >= 4, f'{label}: insufficient samples')
    require(selected[0]['wall']-start <= GAP_MS and end-selected[-1]['wall'] <= GAP_MS,
            f'{label}: missing sample edges')
    require(all(0 < b['wall']-a['wall'] <= GAP_MS for a, b in zip(selected, selected[1:])),
            f'{label}: collapsed clock or sample gap')
    return selected


def movement(rows, release, end):
    anchor = min(rows, key=lambda row: abs(row['wall']-release))
    selected = [row for row in rows if anchor['wall'] <= row['wall'] < end]
    distances = [math.hypot(b['playerX']-a['playerX'], b['playerY']-a['playerY'])
                 for a, b in zip(selected, selected[1:])]
    changing = [i for i, distance in enumerate(distances) if distance > POSITION_TOLERANCE]
    last = changing[-1]+1 if changing else 0
    rest = selected[last]
    return dict(referenceWallMs=release, nearestSampleWallMs=anchor['wall'],
                nearestSampleOffsetMs=anchor['wall']-release,
                sampledPathTiles=sum(distances),
                lastObservedMovementAfterReleaseMs=rest['wall']-release if changing else None,
                lastChangingIntervalAfterReleaseMs=[selected[last-1]['wall']-release, rest['wall']-release] if changing else None,
                observedStationaryTailMs=selected[-1]['wall']-rest['wall'],
                noObservedMovement=not changing), rest['wall']


def pose_settling(rows, rest, modifier, direction):
    selected = [row for row in rows if row['wall'] >= rest]
    final = selected[-1]
    offsets = [(row['wheelX']-row['playerX'], row['wheelY']-row['playerY']) for row in selected]
    last = offsets[-1]
    error = [math.hypot(x-last[0], y-last[1]) for x, y in offsets]
    outside = [i for i, value in enumerate(error) if value > POSE_TOLERANCE]
    first = outside[-1]+1 if outside else 0
    stable = selected[first]
    observed = final['wall']-stable['wall'] >= POSE_QUIET_MS
    return dict(observed=observed, toleranceTiles=POSE_TOLERANCE, requiredQuietMs=POSE_QUIET_MS,
                stableSuffixMs=final['wall']-stable['wall'],
                afterModifierReleaseMs=stable['wall']-modifier if observed else None,
                afterDirectionReleaseMs=stable['wall']-direction if observed else None,
                sampledOnsetBracketWallMs=[selected[max(0, first-1)]['wall'], stable['wall']] if observed else None,
                relativeOffsetExcursionTiles=max(error), cadenceMs=cadence(rows),
                limit='Wheel XY relative to player only, compared with final observed sample; sampled tolerance bound, not calibrated aesthetic PASS. A short suffix is right-censored by the next input.')


def analyze(profile, text, selected_cases=None):
    profile = Path(profile)
    selected = sorted(CASES) if selected_cases is None else list(selected_cases)
    require(selected and len(selected) == len(set(selected)) and set(selected) <= CASES,
            'Case selection must be a unique nonempty subset of known cases')
    require('[WOOD_BANK] RUN_STARTED' in text, 'Missing run start receipt')
    text = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    require('[WOOD_BANK] FAIL' not in text, 'Native scenario failed')
    require(re.findall(r'\[WOOD_BANK\] ALL_COMPLETE cases=(\d+)(?:\s|$)', text) == ['4'], 'Require one four-case completion')
    starts = re.findall(r'\[WOOD_BANK\] CASE (\S+) attempt=(\d+) wall=(\d+)', text)
    completed = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', text)
    require(len(starts) == len(completed) == 4, 'Require exactly four CASE/COMPLETE receipts')
    require({name for name, _, _ in starts} == CASES and {name for name, _ in completed} == CASES,
            'Missing, duplicate or unexpected cases')
    require({name: int(wall) for name, _, wall in starts} == {name: int(wall) for name, wall in completed},
            'CASE/COMPLETE attempts do not match')
    require('[WOOD_BANK] RETRY' not in text, 'Ambiguous retried attempt')
    require(all(int(b[2])-int(a[2]) >= 16000 for a, b in zip(starts, starts[1:])), 'Overlapping or reordered scene clocks')
    events = {name: [] for name in CASES}
    samples = {name: [] for name in CASES}
    for line in text.splitlines():
        if '[WOOD_RAMP_EVENT]' in line:
            row = dict(re.findall(r'(\w+)=([^ ]+)', line))
            require(row.get('case') in CASES, 'Unknown event case')
            for key in ('elapsed', 'gait', 'drive', 'frame'):
                row[key] = int(row[key])
            require(all(row.get(key) in ('true', 'false') for key in ('keyRun', 'keySprint', 'keyMove')),
                    'Missing independent key receipts')
            require(tuple(row[key] == 'true' for key in ('keyRun', 'keySprint', 'keyMove')) ==
                    (row['gait'] == 1, row['gait'] == 2, row['drive'] != 0), 'Native keys differ from requested input')
            events[row['case']].append(row)
        if '[WOOD_BANK_SAMPLE]' in line:
            row = dict(re.findall(r'(\w+)=([^ ]+)', line))
            require(row.get('case') in CASES, 'Unknown sample case')
            row['wall'], row['elapsed'] = int(row['wall']), int(row['elapsed'])
            for key in ('x', 'y', 'pace', 'speed'):
                row[key] = float(row[key])
                require(math.isfinite(row[key]), 'Nonfinite native sample')
            require(all(row.get(key) in ('true', 'false') for key in ('run', 'sprint')), 'Missing native gait flags')
            require(row.get('item') == 'SaucedWheelbarrow.WheelbarrowWood' and row.get('cartMotion') == 'true', 'Wrong cart or motion gate')
            tracks = re.search(r'tracks:(.*?),bones:', row.get('native', ''))
            require(tracks is not None, 'Missing native track telemetry')
            row['heavy'] = []
            for entry in filter(None, tracks[1].split(';')):
                track = re.fullmatch(r'([^;@]+)@([^/]+)/([^/]+)/([^/]+)/([^;]+)', entry)
                require(track is not None, 'Malformed native track telemetry')
                name, weight, time, rate, playing = track.groups()
                weight, time, rate = float(weight), float(time), float(rate)
                require(all(math.isfinite(v) for v in (weight, time, rate)), 'Nonfinite native track')
                require(0 <= weight <= 1.001 and rate >= 0 and playing in ('true', 'false'), 'Invalid native track')
                if name in ('Bob_RunToStop2H_Heavy', 'Bob_SprintToStop2h_Heavy') and weight > .001:
                    row['heavy'].append(dict(name=name, weight=weight, time=time, rate=rate))
            samples[row['case']].append(row)
    windows = [(int(wall), int(wall)+16000) for _, _, wall in starts]
    wheel = []
    with (profile/'wood-wheel-native.csv').open() as stream:
        for row in csv.DictReader(stream):
            if row.get('event') != 'grounding':
                continue
            wall = float(row['wallTimeMillis'])
            require(math.isfinite(wall), 'Nonfinite grounding wall clock')
            if not any(start <= wall < end for start, end in windows):
                continue
            point = {key: float(row[key]) for key in ('time', 'playerX', 'playerY', 'wheelX', 'wheelY')}
            for key in ('phase', 'lean'):
                if row.get(key):
                    point[key] = float(row[key])
            require(all(math.isfinite(value) for value in point.values()), 'Nonfinite grounding sample')
            point['wall'] = wall
            wheel.append(point)
    results = []
    for name, _, wall in starts:
        if name not in selected:
            continue
        start = int(wall)
        gait = 2 if 'sprint' in name else 1
        planned = [(1000, gait, 2), (2500, 0, 0), (6000, gait, 2), (7500, 0, 2),
                   (7600, 0, 0), (11000, gait, 2), (12500, 0, 2), (12800, 0, 0)]
        steps = events[name]
        require([(r['gait'], r['drive']) for r in steps] == [(g, d) for _, g, d in planned], f'{name}: missing or reordered events')
        require(all(target <= event['elapsed'] <= target+GAP_MS for event, (target, _, _) in zip(steps, planned)), f'{name}: late/mistimed event')
        require(all(b['frame'] > a['frame'] and b['elapsed'] > a['elapsed'] for a, b in zip(steps, steps[1:])), f'{name}: collapsed/reordered event frames')
        for first, second, delay in ((steps[3], steps[4], 100), (steps[6], steps[7], 300)):
            require(abs(second['elapsed']-first['elapsed']-delay) <= 75, f'{name}: modifier lead differs from requested delay')
        bank = samples[name]
        require(all(abs(row['wall']-start-row['elapsed']) <= 5 for row in bank), f'{name}: sample clocks disagree')
        bank = coverage(bank, start+800, start+16000, name+' native tracks')
        # Multiple render observations can share a millisecond; retain the last real observation.
        scene = list({row['wall']: row for row in wheel if start <= row['wall'] < start+16000}.values())
        scene = coverage(scene, start+800, start+16000, name+' grounding')
        require(all(b['time'] > a['time'] for a, b in zip(scene, scene[1:])), f'{name}: non-increasing native clock')
        expected = 'Bob_SprintToStop2h_Heavy' if gait == 2 else 'Bob_RunToStop2H_Heavy'
        stops = []
        for route, m, d, end in (('direct', 1, 1, steps[2]['elapsed']), ('walk-100ms', 3, 4, steps[5]['elapsed']), ('walk-300ms', 6, 7, 15800)):
            modifier, direction = start+steps[m]['elapsed'], start+steps[d]['elapsed']
            end += start
            require(end-direction >= 500, f'{name}: insufficient recorded stop tail')
            recorded = coverage(scene, modifier, end, name+' '+route)
            tracks = coverage(bank, modifier, end, name+' '+route+' tracks')
            from_modifier, _ = movement(scene, modifier, end)
            from_direction, rest = movement(scene, direction, end)
            require(from_direction['observedStationaryTailMs'] >= 500, f'{name} {route}: insufficient observed stationary tail')
            before_modifier = max((row for row in bank if row['wall'] < modifier), key=lambda row: row['wall'])
            before_direction = max((row for row in bank if row['wall'] < direction), key=lambda row: row['wall'])
            lead = [row for row in bank if modifier < row['wall'] < direction]
            walk = [row for row in lead if row['wall'] > modifier+50 and row['run'] == row['sprint'] == 'false']
            require(route == 'direct' or walk, f'{name} {route}: no observed native Walk after 50ms before WASD release')
            require((before_modifier['run'] == 'true', before_modifier['sprint'] == 'true') == (gait == 1, gait == 2), f'{name}: fast gait was not active before modifier release')
            def gait_receipt(row):
                return dict(afterModifierReleaseMs=row['wall']-modifier, afterDirectionReleaseMs=row['wall']-direction,
                            run=row['run'] == 'true', sprint=row['sprint'] == 'true',
                            nativeWalkSpeed=row['speed'], legPace=row['pace'])
            heavy = [(row, track) for row in tracks for track in row['heavy']]
            names = sorted({track['name'] for _, track in heavy})
            heavy_report = dict(expectedName=expected if route == 'direct' else None, observedNames=names,
                                firstAfterDirectionReleaseMs=heavy[0][0]['wall']-direction if heavy else None,
                                lastAfterDirectionReleaseMs=heavy[-1][0]['wall']-direction if heavy else None,
                                maxWeight=max((track['weight'] for _, track in heavy), default=0),
                                rates=sorted({track['rate'] for _, track in heavy}),
                                behaviorMatchesExpectation=names == [expected] if route == 'direct' else not names)
            stops.append(dict(route=route, modifierLeadMs=direction-modifier, fromModifierRelease=from_modifier,
                              fromDirectionRelease=from_direction, heavyTrack=heavy_report,
                              wheelRelativeSettling=pose_settling(recorded, rest, modifier, direction),
                              nativeBeforeModifier=gait_receipt(before_modifier), nativeBeforeDirection=gait_receipt(before_direction),
                              nativeLeadSamples=[gait_receipt(row) for row in lead], observedWalkBeforeDirection=bool(walk)))
        results.append(dict(case=name, samples=len(scene), cadenceMs=cadence(scene), stops=stops))
    return dict(timingVerified=True, timingVerificationScope='selectedCases only', captureValid=True,
                selectedCases=selected, partialCoverage=len(selected) < len(CASES), cases=results,
                evidenceInputs=dict(groundingCsv=str((profile/'wood-wheel-native.csv').resolve()), groundingCompression='none'),
                measurementStartAfterCaseMs=800,
                unmeasuredStartup='First 800ms after CASE are video startup; raw in-scene values remain validated.',
                positionToleranceTiles=POSITION_TOLERANCE,
                maximumAllowedSampleGapMs=GAP_MS,
                limit='Movement/path use nearest native grounding positions without interpolation; last movement is an observed interval, not an exact physics timestamp. Pose metrics are descriptive and may be censored by the next input. No animation-quality PASS is inferred.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--log', type=Path)
    parser.add_argument('--case', action='append', dest='selected_cases', help='Repeat to analyze only selected scenes; all four completion receipts remain required')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    require(not args.output.exists(), 'Refuse to overwrite an existing report')
    log = args.log or args.profile/'native-launch.log'
    report = analyze(args.profile, log.read_text(), args.selected_cases)
    report['evidenceInputs']['log'] = str(log.resolve())
    with args.output.open('x') as stream:
        stream.write(json.dumps(report, indent=2)+'\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
