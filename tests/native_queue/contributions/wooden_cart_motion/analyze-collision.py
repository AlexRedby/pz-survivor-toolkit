"""Native character wall, corner and passage gates for the held wooden cart."""
import argparse
import importlib.util
import json
import math
from pathlib import Path
import re

_spec = importlib.util.spec_from_file_location('cart_collision_maneuvers', Path(__file__).with_name('analyze-maneuvers.py'))
_motion = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_motion)
wrap, fields = _motion.wrap, _motion._stationary.fields
native_clip = _motion._stationary.native_clip
STEPS = {
    'wall-block': [(1000, 1, 5), (6000, 0, 0), (7000, 0, 7), (9500, 0, 0)],
    'wall-slide': [(1000, 1, 2), (6000, 0, 0), (7000, 0, 7), (9500, 0, 0)],
    'corner-pivot': [(1000, 2, 3), (4000, 0, 0), (5000, 0, 1), (8500, 0, 0)],
    'passage': [(1000, 0, 5), (4500, 0, 0), (5000, 0, 7), (9500, 0, 0)],
}
SPECS = tuple(STEPS)
HEADINGS = dict(zip(SPECS, (math.pi, 3 * math.pi / 4, math.pi / 4, math.pi)))
WHEEL_RADIUS = .001062454 * 76.5 * 1.5
HEADER = {'case', 'wall', 'elapsed', 'x', 'y', 'run', 'sprint', 'skill', 'speed', 'drive', 'requestedGait', 'stepX', 'stepY', 'pace', 'wheelPhase'}


def numeric_fields(text, expected, label):
    row = fields(text)
    assert set(row) == set(expected), 'Missing or unexpected ' + label + ' fields'
    for key in expected:
        row[key] = float(row[key])
        assert math.isfinite(row[key]), 'Nonfinite ' + label + ': ' + key
    return row


def sample(line):
    header = fields(line.split('[WOOD_BANK_SAMPLE] ', 1)[1].split(' bank=', 1)[0])
    assert set(header) == HEADER, 'Missing or unexpected collision sample header'
    row = _motion.sample(line)
    for key in ('wheelPhase', 'skill', 'speed', 'pace'):
        row[key] = float(header[key])
        assert math.isfinite(row[key]), 'Nonfinite collision measurement: ' + key
    assert row['skill'] == 10 and row['speed'] >= 0 and row['pace'] >= 0, 'Invalid collision skill/speed/pace'
    assert row['drive'] in range(9), 'Invalid collision input'
    return row


def spread(rows):
    return max(math.dist((rows[0]['x'], rows[0]['y']), (r['x'], r['y'])) for r in rows)


def angle_drift(rows, key):
    value, maximum = 0., 0.
    for a, b in zip(rows, rows[1:]):
        value += wrap(b[key] - a[key])
        maximum = max(maximum, abs(value))
    return maximum


def wheel_roll_error(rows):
    error, maximum = 0., 0.
    for a, b in zip(rows, rows[1:]):
        turn = wrap(b['heading'] - a['heading'])
        mid = a['heading'] + turn / 2
        # Project the wheel center's world displacement, including native gait/lean axle clearance.
        travel = ((b['x'] - a['x']) * math.cos(mid) + (b['y'] - a['y']) * math.sin(mid)
                  + (b['axle'] - a['axle']) * math.cos(turn / 2) - 2 * .00984276836 * math.sin(turn / 2))
        error += wrap(b['wheelPhase'] - a['wheelPhase']) * WHEEL_RADIUS + travel
        maximum = max(maximum, abs(error))
    return maximum


def coverage(rows, start, duration, label, minimum):
    assert len(rows) >= minimum, 'Insufficient ' + label + ' samples'
    gaps = [b['wall'] - a['wall'] for a, b in zip(rows, rows[1:])]
    assert min(gaps) > 0 and max(gaps) <= 500, 'Incomplete ' + label + ' sample window'
    assert rows[0]['elapsed'] <= 200 and rows[-1]['elapsed'] >= duration - 200, 'Incomplete ' + label + ' sample edges'
    assert all(0 <= r['elapsed'] < duration and abs(r['wall'] - start - r['elapsed']) <= 5 for r in rows), label + ' clocks disagree'
    return gaps


def slide_metrics(rows, direction):
    if len(rows) < 2:
        return dict(samples=len(rows), durationMs=0, tangent=0, normal=0, tangentPerSecond=0)
    duration = rows[-1]['wall']-rows[0]['wall']
    tangent = direction*(rows[-1]['y']-rows[0]['y'])
    return dict(samples=len(rows), durationMs=duration, tangent=tangent,
                normal=max(r['x'] for r in rows)-min(r['x'] for r in rows),
                tangentPerSecond=tangent/(duration/1000) if duration else 0)


def controls(log, wall_offset=1):
    result, active = {}, None
    expected = {'wall', 'corner', 'passage'}
    if wall_offset == 3: expected.update(('wall-slide-left', 'wall-slide-right'))
    for line in log.splitlines():
        if '[CART_COLLISION_CONTROL] START ' in line:
            raw = fields(line.split('[CART_COLLISION_CONTROL] START ', 1)[1])
            name = raw.pop('spec', None)
            assert name in expected and name not in result and active is None, 'Unexpected or duplicate native control'
            row = numeric_fields(' '.join(f'{k}={v}' for k, v in raw.items()), ('wall', 'x', 'y', 'wallX', 'southY', 'gapY'), 'control start')
            result[name] = dict(start=row, rows=[])
            active = name
        elif '[CART_COLLISION_CONTROL_SAMPLE] ' in line:
            raw = fields(line.split('[CART_COLLISION_CONTROL_SAMPLE] ', 1)[1])
            name = raw.pop('spec', None)
            assert name == active and active is not None, 'Control sample outside its attempt'
            slide = name.startswith('wall-slide-')
            if slide:
                assert raw.pop('run', None) == 'false' and raw.pop('sprint', None) == 'false' and raw.pop('bare', None) == 'true', 'Native slide must be bare Walk'
                tracks = raw.pop('tracks', '')
                assert tracks and all(re.fullmatch(r'[^=;]+=[^@;]+@[^;]+', t) for t in tracks.split(';') if t), 'Invalid native Walk tracks'
                parsed = [(n, float(speed), float(weight)) for n, speed, weight in re.findall(r'([^=;]+)=([^@;]+)@([^;]+);', tracks)]
                assert parsed and all(math.isfinite(speed+weight) for _, speed, weight in parsed), 'Nonfinite native Walk tracks'
                walking = any(native_clip(n) == 'Bob_Walk' and speed > 0 and weight > .1 for n, speed, weight in parsed)
            row = numeric_fields(' '.join(f'{k}={v}' for k, v in raw.items()), ('wall', 'elapsed', 'x', 'y', 'heading', 'drive'), 'control sample')
            assert row['drive'] == (2 if name in ('corner', 'wall-slide-left') else 1 if name == 'wall-slide-right' else 5), 'Wrong native control input'
            if slide: row['walking'] = walking
            result[name]['rows'].append(row)
        elif '[CART_COLLISION_CONTROL] COMPLETE ' in line:
            raw = fields(line.split('[CART_COLLISION_CONTROL] COMPLETE ', 1)[1])
            name = raw.pop('spec', None)
            assert name == active and active is not None, 'Native control completion without start'
            result[name]['end'] = numeric_fields(' '.join(f'{k}={v}' for k, v in raw.items()), ('wall', 'x', 'y'), 'control completion')
            active = None
    assert set(result) == expected and active is None and all('end' in c for c in result.values()), 'Missing native collision controls'
    failures = []
    geometry = result['wall']['start']
    for name, control in result.items():
        start, rows, end = control['start'], control['rows'], control['end']
        slide = name.startswith('wall-slide-')
        duration = 6000 if slide else 4000
        coverage([r for r in rows if r['elapsed'] < duration], start['wall'], duration, 'native control ' + name, 40)
        assert duration <= end['wall'] - start['wall'] <= duration+500 and end['wall'] >= rows[-1]['wall'], 'Invalid native control completion time'
        assert all(0 <= r['elapsed'] <= end['wall'] - start['wall'] and abs(r['wall'] - start['wall'] - r['elapsed']) <= 5 for r in rows), 'Native control clocks disagree'
        assert all(b['wall'] > a['wall'] for a, b in zip(rows, rows[1:])), 'Non-monotonic native control samples'
        assert all(start[k] == geometry[k] for k in ('x', 'y', 'wallX', 'southY', 'gapY')), 'Native controls disagree on geometry'
        assert start['wallX'] == math.floor(start['x']) - wall_offset and start['southY'] == math.floor(start['y']) + 2 and start['gapY'] == math.floor(start['y']), 'Invalid native control geometry'
        assert math.dist((start['x'], start['y']), (rows[0]['x'], rows[0]['y'])) <= 8 * rows[0]['elapsed'] / 1000 + .02, 'Native control starts after movement'
        assert math.dist((end['x'], end['y']), (rows[-1]['x'], rows[-1]['y'])) <= 8*(end['wall']-rows[-1]['wall'])/1000+.002, 'Native control endpoint disagrees with samples'
        def fail(reason):
            failures.append(('control-' + name, reason))
        if any(math.dist((a['x'], a['y']), (b['x'], b['y'])) > 8 * (b['wall'] - a['wall']) / 1000 + .02 for a, b in zip(rows, rows[1:])):
            fail('native control position jumps between samples')
        if name != 'passage' and any(r['x'] < start['wallX'] - .002 for r in rows):
            fail('native control crosses a closed wall')
        if name == 'corner' and any(r['y'] > start['southY'] + .002 for r in rows):
            fail('native control crosses the corner wall')
        if name in ('wall', 'corner'):
            if not start['wallX'] + .1 <= end['x'] <= start['wallX'] + .5:
                fail('native control does not reach wall contact')
            quiet = [r for r in rows if r['elapsed'] >= 3500]
            if len(quiet) < 2 or spread(quiet) > .01:
                fail('native control does not settle at contact')
        if name == 'corner':
            if not start['southY'] - .5 <= end['y'] <= start['southY'] - .1:
                fail('native control does not reach corner contact')
        elif slide:
            # Diagonal contact can sit closer to the wall than the frontal control.
            contact = [r for r in rows if duration-1300 <= r['elapsed'] < duration
                       and r['x'] <= min(start['wallX']+.5, end['x']+.05)]
            metrics = slide_metrics(contact, -1 if name.endswith('right') else 1)
            control['slide'] = metrics
            if metrics['durationMs'] < 500 or metrics['tangent'] < .15 or metrics['normal'] > .15 or any(b['wall']-a['wall'] > 500 for a,b in zip(contact,contact[1:])):
                fail('native Walk has no sustained wall slide at contact')
            if not contact or sum(r['walking'] for r in contact) < .8*len(contact): fail('native Walk animation absent at wall contact')
            if not start['wallX']-.002 <= end['x'] <= start['wallX']+.5: fail('native slide does not reach wall contact')
        else:
            if any(abs(r['y'] - start['y']) > .025 for r in rows):
                fail('straight native control leaves its lane')
            if name == 'passage' and end['x'] >= start['wallX'] - .2:
                fail('native passage control never crosses the opening')
    return result, failures


def selected_capture(log):
    assert re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases=16(?:\s|$)', log), 'Capture incomplete'
    assert '[WOOD_BANK] FAIL' not in log, 'Scenario failed'
    expected = {f'{sex}-{cargo}-{spec}' for sex in ('male', 'female') for cargo in ('empty', 'full') for spec in SPECS}
    completed = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    assert len(completed) == 16 and {name for name, _ in completed} == expected, 'Missing, duplicate or unexpected collision cases'
    starts = {name: int(start) for name, start in completed}
    attempts = re.findall(r'\[WOOD_BANK\] CASE (\S+) attempt=\d+ wall=(\d+)', log)
    assert all(attempts.count((name, str(start))) == 1 for name, start in starts.items()), 'Missing or duplicate selected collision attempt'
    cases, events, layouts = {name: [] for name in starts}, {name: [] for name in starts}, {}
    active, available_layouts = None, {}
    for line in log.splitlines():
        if '[CART_COLLISION_LAYOUT] ' in line:
            layout = fields(line.split('[CART_COLLISION_LAYOUT] ', 1)[1])
            available_layouts[layout.pop('case', None)] = layout
        attempt = re.search(r'\[WOOD_BANK\] CASE (\S+) attempt=\d+ wall=(\d+)', line)
        if attempt:
            active = attempt[1] if starts.get(attempt[1]) == int(attempt[2]) else None
            if active is not None:
                assert active in available_layouts, 'Missing collision layout for selected attempt'
                layouts[active] = numeric_fields(' '.join(f'{k}={v}' for k, v in available_layouts[active].items()), ('wallX', 'southY', 'gapY', 'startX', 'startY', 'baselineX', 'baselineY'), 'layout')
        event = re.search(r'\[WOOD_RAMP_EVENT\] case=(\S+) elapsed=(\d+) gait=(\d+) drive=(\d+)', line)
        if event and active is not None:
            assert event[1] == active, 'Collision event disagrees with selected attempt'
            events[active].append(tuple(map(int, event.groups()[1:])))
        if '[WOOD_BANK_SAMPLE]' in line and active is not None:
            row = sample(line)
            assert row['case'] == active, 'Collision sample disagrees with selected attempt'
            assert row['wall'] >= starts[active], 'Collision sample precedes selected window'
            if row['wall'] < starts[active] + 12000:
                cases[active].append(row)
    return starts, cases, events, layouts


def analyze(text):
    assert '[WOOD_BANK] RUN_STARTED' in text, 'Missing collision run boundary'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[1]
    native, failures = controls(log)
    starts, cases, events, layouts = selected_capture(log)
    assert max(c['end']['wall'] for c in native.values()) < min(starts.values()), 'Native controls must precede collision scenes'
    geometry, summaries = native['wall']['start'], []
    for name, rows in cases.items():
        spec, layout = name.split('-', 2)[2], layouts[name]
        gaps = coverage(rows, starts[name], 12000, 'collision ' + name, 80)
        assert all(layout[k] == geometry[k] for k in ('wallX', 'southY', 'gapY')), 'Scene layout disagrees with native controls'
        assert math.dist((layout['baselineX'], layout['baselineY']), (native['corner']['end']['x'], native['corner']['end']['y'])) <= .025, 'Corner baseline disagrees with native control'
        origin = (layout['baselineX'], layout['baselineY']) if spec == 'corner-pivot' else (geometry['x'], geometry['y'])
        assert math.dist((layout['startX'], layout['startY']), origin) <= .025, 'Wrong collision scene start'
        assert math.dist((rows[0]['x'], rows[0]['y']), origin) <= .025, 'Collision scene starts after movement'
        actual = events[name]
        assert [(g, d) for _, g, d in actual] == [(g, d) for _, g, d in STEPS[spec]], 'Missing or reordered collision input events'
        assert all(abs(a[0] - b[0]) <= 500 for a, b in zip(actual, STEPS[spec])) and all(b[0] > a[0] for a, b in zip(actual, actual[1:])), 'Late or non-monotonic collision input events'
        stages = [(0, 0, 0), *actual, (12000, 0, 0)]
        for index, (at, gait, drive) in enumerate(stages[:-1]):
            end = stages[index + 1][0]
            margin = min(200, (end - at) / 4)
            stage = [r for r in rows if at + margin <= r['elapsed'] < end - margin]
            assert stage and all((r['requestedGait'], r['drive']) == (gait, drive) for r in stage), 'Missing or wrong sampled collision input stage'
        seen = set()
        def fail(reason):
            if reason not in seen:
                failures.append((name, reason));seen.add(reason)
        def window(start, end):
            return [r for r in rows if start <= r['elapsed'] < end]
        def quiet(rows, reason):
            assert len(rows) >= 2, 'Insufficient ' + reason + ' samples'
            if spread(rows) > .015 or angle_drift(rows, 'heading') > math.radians(1) or wheel_roll_error(rows) > .01:
                fail(reason)
        if abs(wrap(rows[0]['heading'] - HEADINGS[spec])) > math.radians(4):
            fail('initial collision heading differs from fixture')
        if spec != 'passage' and any(r['x'] < layout['wallX'] - .002 for r in rows):
            fail('character crosses a closed wall')
        if spec == 'corner-pivot' and any(r['y'] > layout['southY'] + .002 for r in rows):
            fail('character crosses the corner wall')
        quiet_run, motionless_yaw = [], 0.
        for a, b in zip(rows, rows[1:]):
            dt = (b['wall'] - a['wall']) / 1000
            distance = math.dist((a['x'], a['y']), (b['x'], b['y']))
            if distance > 8 * dt + .02:
                fail('position jumps between samples')
            if abs(wrap(b['heading'] - a['heading'])) > 3 * dt + .05:
                fail('heading snaps between samples')
            motionless_yaw = motionless_yaw + wrap(b['heading'] - a['heading']) if distance <= .002 else 0.
            if abs(motionless_yaw) > math.radians(2):
                fail('heading changes without measured movement')
            if distance <= .002:
                quiet_run = quiet_run + [b] if quiet_run else [a, b]
                if spread(quiet_run) <= .005 and wheel_roll_error(quiet_run) > .02:
                    fail('wheel spins without measured movement')
            else:
                quiet_run = []
        reverse_start = actual[2][0]
        reverse = window(reverse_start + 300, actual[3][0])
        if any((r['stationaryRoot'] or r['requested'] < 0 or r['direction'] < 0) and (r['run'] or r['sprint']) for r in rows):
            fail('fast gait during stationary or reverse motion')
        if not any(r['direction'] < 0 and r['actualDistance'] > 1e-6 for r in reverse):
            fail('reverse escape never engages')
        clip = 'Bob_WalkBwdNoAim1Hand'
        def progressing(selected, names):
            tracks = [(r['elapsed'], c) for r in selected for c in r['clips'] if native_clip(c['name']) in names and c['weight'] > .1 and c['speed'] > 0]
            return any(t1 > t0 and a['name'] == b['name'] and abs(a['time'] - b['time']) > .001 for (t0, a), (t1, b) in zip(tracks, tracks[1:]))
        if not progressing(reverse, {clip}):
            fail('native reverse gait does not progress')
        if spec in ('wall-block', 'wall-slide'):
            approach = window(1100, actual[1][0])
            if not any(r['run'] and r['actualDistance'] > 1e-6 for r in approach) or not progressing(approach, {'Bob_Run'}):
                fail('native requested fast gait does not progress')
        if spec == 'wall-block':
            contact = window(3500, 5500)
            quiet(contact, 'wall contact does not remain quiet')
            if any(abs(r['x'] - native['wall']['end']['x']) > .05 for r in contact):
                fail('cart actor does not reach native wall contact')
            if not reverse or max(r['x'] for r in reverse) - contact[-1]['x'] < .2:
                fail('wall reverse does not escape')
        elif spec == 'wall-slide':
            contact = [r for r in window(1500, 5800) if r['x'] <= layout['wallX'] + .6]
            if len(contact) < 3 or contact[-1]['y'] - contact[0]['y'] < .15:
                fail('wall slide has no accepted tangential movement')
            if not reverse or reverse[-1]['x'] - reverse[0]['x'] < .2:
                fail('wall slide reverse does not escape')
        elif spec == 'corner-pivot':
            blocked = window(1200, 3800)
            quiet(blocked, 'blocked corner pivot changes pose or position')
            if not any(r['stationary'] and r['stationaryRoot'] for r in blocked):
                fail('blocked corner pivot never engages stationary steering')
            if not reverse or min(r['y'] for r in reverse) > layout['baselineY'] - .1:
                fail('corner reverse does not escape')
        else:
            if any(not layout['gapY'] + .1 <= r['y'] <= layout['gapY'] + .9 for r in rows):
                fail('passage movement leaves the open gap')
            outbound = window(1200, actual[1][0])
            if not outbound or min(r['x'] for r in outbound) >= layout['wallX'] - .2:
                fail('passage never crosses west through the opening')
            if not reverse or max(r['x'] for r in reverse) <= layout['wallX'] + .2:
                fail('passage never crosses east through the opening')
        tail = window(max(11500, actual[-1][0] + 2250), 12000)
        quiet(tail, 'final release does not settle')
        if any(r['stationary'] or r['braking'] or r['run'] or r['sprint'] for r in tail):
            fail('final release does not settle')
        summaries.append(dict(case=name, samples=len(rows), minX=min(r['x'] for r in rows), maxY=max(r['y'] for r in rows),
                              intervalMs=dict(min=min(gaps), max=max(gaps))))
    return dict(complete=True, caseCount=len(summaries), cases=summaries, controlCount=len(native),
                controls={name: dict(samples=len(c['rows']), x=c['end']['x'], y=c['end']['y']) for name, c in native.items()},
                failures=failures, motionPass=not failures,
                limit='Native character collision measured in update samples; motion between samples is unresolved. Wall approaches use Run; protected Sprint-impact recovery is not covered. The cart is a held render model with no separate collision body. Mesh/wheel-wall intersection and video review remain separate; this report makes no visual PASS claim.')


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
