"""Native relative-key obstacle matrix: movement and sampled mesh gates, never visual approval."""
import argparse
import bisect
import importlib.util
import json
import math
from pathlib import Path
import re

_spec = importlib.util.spec_from_file_location('obstacle_footprint', Path(__file__).with_name('analyze-footprint.py'))
footprint = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(footprint)
collision = footprint.collision
wrap, fields = collision.wrap, collision.fields
_motion_spec = importlib.util.spec_from_file_location('obstacle_motion_clock', Path(__file__).with_name('analyze-motion-matrix.py'))
_motion = importlib.util.module_from_spec(_motion_spec)
_motion_spec.loader.exec_module(_motion)
DURATION = 16000
SPECS = ('frontal', 'slide-left', 'slide-right', 'corner', 'door-closed', 'door-open')
EXPECTED = tuple(f'{sex}-{load}-{gait}-{spec}' for sex in ('male', 'female') for load in ('empty', 'full')
                 for gait in ('walk', 'run', 'sprint') for spec in SPECS)
PREFIX = '[CART_OBSTACLE_MATRIX] '


def unique(pairs):
    value = dict(pairs)
    assert len(value) == len(pairs), 'Duplicate obstacle JSON fields'
    return value


def finite(row, keys):
    for key in keys:
        assert type(row.get(key)) in (int, float) and math.isfinite(row[key]), 'Missing/nonfinite obstacle field: ' + key


def flags(row, keys):
    assert all(type(row.get(k)) is bool for k in keys), 'Invalid obstacle boolean'


def coverage(rows, duration, label):
    assert len(rows) >= duration // 200, 'Insufficient ' + label + ' samples'
    assert rows[0]['elapsed'] <= 200 and rows[-1]['elapsed'] >= duration - 200, 'Incomplete ' + label + ' edges'
    assert all(0 <= r['elapsed'] < duration for r in rows), 'Invalid ' + label + ' interval'
    assert all(0 < b['wall'] - a['wall'] <= 500 for a, b in zip(rows, rows[1:])), 'Incomplete/nonmonotonic ' + label + ' coverage'
    starts = [r['wall'] - r['elapsed'] for r in rows]
    assert max(starts) - min(starts) <= 5, 'Disagreeing ' + label + ' clocks'


def spec_of(name):
    return name.split('-', 3)[3]


def planned(name):
    gait = ('walk', 'run', 'sprint').index(name.split('-', 3)[2])
    return [(0, 0, 0), (800, gait, 1), (6800, 0, 0), (8000, 0, 4), (13000, 0, 0)]


def root(row):
    numeric, tracks = row['root'].split(',rootTracks:', 1)
    values = fields(numeric, ':')
    assert set(values) == {'heading', 'target', 'stationary', 'stationaryRoot', 'actualDistance', 'axle'}, 'Invalid obstacle root diagnostics'
    clips = []
    for value in tracks.split(';'):
        if not value:
            continue
        name, values_ = value.split('@', 1)
        weight, time, speed = map(float, values_.split('/'))
        assert all(math.isfinite(v) for v in (weight, time, speed)) and 0 <= weight <= 1.001 and time >= 0 and speed >= 0, 'Invalid obstacle native track'
        clips.append(dict(name=name, weight=weight, time=time, speed=speed))
    for key in ('heading', 'target', 'actualDistance', 'axle'):
        values[key] = float(values[key])
        assert math.isfinite(values[key]), 'Nonfinite obstacle root'
    assert values['actualDistance'] >= 0 and values['axle'] > 0, 'Invalid obstacle root distance'
    for key in ('stationary', 'stationaryRoot'):
        assert values[key] in ('true', 'false'), 'Invalid obstacle root boolean'
        values[key] = values[key] == 'true'
    reversal = fields(row['reversal'], ':')
    assert reversal['direction'] in ('-1', '1') and reversal['requested'] in ('-1', '0', '1'), 'Invalid obstacle reverse state'
    values.update(direction=int(reversal['direction']), requested=int(reversal['requested']))
    wall = fields(row['brace'])
    shape = fields(row['footprint'])
    for raw, keys in ((wall, ('nativeBlocked', 'wantsMove')), (shape, ('blocked', 'recovering', 'clear'))):
        for key in keys:
            assert raw[key] in ('true', 'false'), 'Invalid obstacle contact flag'
            values[key] = raw[key] == 'true'
    values['front'] = float(shape['front'])
    assert values['front'] in (1.26, 1.62), 'Invalid shipped native obstacle envelope'
    values['brace'] = float(wall['brace'])
    assert math.isfinite(values['brace']) and 0 <= values['brace'] <= 1, 'Invalid obstacle brace blend'
    assert abs(wrap(values['heading'] - row['acceptedHeading'])) <= .002, 'Obstacle pose diagnostics disagree'
    return dict(row, **{key: value for key, value in values.items() if key != 'heading'}, clips=clips)


def parse(text, selected=None):
    assert '[WOOD_BANK] RUN_STARTED' in text, 'Missing obstacle run boundary'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[1]
    assert '[WOOD_BANK] FAIL' not in log and PREFIX + 'CLEANUP_COMPLETE' in log, 'Obstacle fixture failed or cleanup missing'
    names = tuple(EXPECTED if selected is None else selected)
    assert names and len(set(names)) == len(names) and set(names) <= set(EXPECTED), 'Invalid obstacle selection'
    complete = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)(?:\s|$)', log)
    assert len(complete) == len(names) and [n for n, _ in complete] == list(names), 'Missing/duplicate/unordered obstacle completion'
    assert re.findall(r'\[WOOD_BANK\] ALL_COMPLETE cases=(\d+)(?:\s|$)', log) == [str(len(names))], 'Incomplete obstacle matrix'
    starts = {name: int(at) for name, at in complete}
    assert all(b - a >= DURATION for a, b in zip(starts.values(), list(starts.values())[1:])), 'Overlapping obstacle windows'
    cases = {name: dict(rows=[], phases=[], layout=None) for name in names}
    controls, receipts, active, attempts = {}, {}, None, []
    for line in log.splitlines():
        match = re.search(r'\[WOOD_BANK\] CASE (\S+) attempt=(\d+) wall=(\d+)', line)
        if match:
            name, at = match[1], int(match[3])
            assert name in starts, 'Unexpected obstacle attempt'
            active = name if starts[name] == at else None
            if active:
                attempts.append(name)
        if '[WOOD_BANK] RETRY ' in line or '[WOOD_BANK] COMPLETE ' in line:
            active = None
        if PREFIX not in line:
            continue
        payload = line.split(PREFIX, 1)[1]
        if ' {' not in payload:
            continue
        event, raw = payload.split(' ', 1)
        row = json.loads(raw, object_pairs_hook=unique)
        assert event in ('DOOR', 'CONTROL_LAYOUT', 'CONTROL_SAMPLE', 'CONTROL_END', 'LAYOUT', 'PHASE', 'SAMPLE'), 'Unexpected obstacle event'
        if event == 'DOOR':
            flags(row, ('open', 'blocked', 'blockedForward', 'blockedBackward'))
            assert row['spec'] in ('door-closed', 'door-open') and row['axis'] == 'W', 'Invalid native obstacle door'
            assert row['open'] == (row['spec'] == 'door-open') and row['blocked'] == row['blockedForward'] == row['blockedBackward'] != row['open'], 'Native obstacle door state disagrees'
            assert row['sprite'] == ('fixtures_doors_01_2' if row['open'] else 'fixtures_doors_01_0'), 'Native obstacle door sprite disagrees'
            receipts[row['spec']] = row
        elif event.endswith('LAYOUT'):
            name = row.get('case', row.get('spec'))
            spec = spec_of(name) if event == 'LAYOUT' else name
            assert spec in SPECS, 'Unexpected obstacle layout'
            finite(row, ('wallX', 'gapY', 'southY', 'minY', 'maxY', 'owned', 'doors', 'startX', 'startY', 'heading'))
            assert row['maxY'] - row['minY'] >= 50 and row['owned'] == row['maxY'] - row['minY'] + 1 + (16 if spec == 'corner' else 0), 'Incomplete native obstacle wall'
            assert row['doors'] == (1 if spec.startswith('door-') else 0), 'Missing native obstacle door count'
            if spec.startswith('door-'):
                receipt = receipts.pop(spec, None)
                assert receipt and receipt['x'] == row['wallX'] and receipt['y'] == row['gapY'], 'Missing current native door receipt'
            if event == 'CONTROL_LAYOUT':
                assert name not in controls, 'Duplicate native obstacle control'
                controls[name] = dict(layout=row, rows=[], end=None)
            elif active:
                assert name == active and cases[name]['layout'] is None, 'Duplicate/misplaced obstacle layout'
                cases[name]['layout'] = row
        elif event.startswith('CONTROL_'):
            name = row['spec']
            assert name in controls, 'Native obstacle control without layout'
            finite(row, ('wall', 'elapsed', 'x', 'y'))
            if event == 'CONTROL_END':
                assert controls[name]['end'] is None and 6000 <= row['elapsed'] <= 6500, 'Invalid native control completion'
                controls[name]['end'] = row
            else:
                flags(row, ('bare', 'run', 'sprint'))
                assert row['bare'] and not row['run'] and not row['sprint'], 'Native obstacle control must be bare Walk'
                assert row['drive'] == (2 if name in ('slide-left', 'corner') else 1 if name == 'slide-right' else 5), 'Wrong bare native input'
                if row['elapsed'] < 6000:
                    controls[name]['rows'].append(row)
        elif active:
            assert row['case'] == active, 'Obstacle evidence outside selected attempt'
            finite(row, ('wall', 'elapsed', 'gait', 'drive'))
            assert abs(row['wall'] - starts[active] - row['elapsed']) <= 5, 'Obstacle clocks disagree'
            assert row['gait'] in range(3) and row['drive'] in (0, 1, 4), 'Wrong relative obstacle input'
            if event == 'PHASE':
                cases[active]['phases'].append(row)
            elif event == 'SAMPLE':
                finite(row, ('frame', 'x', 'y', 'heading', 'acceptedHeading', 'id', 'cargoWeight', 'skill'))
                flags(row, ('run', 'sprint', 'forward', 'backward', 'left', 'right', 'runKey', 'sprintKey'))
                assert (row['forward'], row['backward'], row['left'], row['right'], row['runKey'], row['sprintKey']) == (row['drive'] == 1, row['drive'] == 4, False, False, row['gait'] == 1, row['gait'] == 2), 'Actual native keys disagree with obstacle command'
                assert row['skill'] == 10 and row['id'] >= 0 and row['cargoWeight'] >= 0 and isinstance(row['cargoIDs'], str), 'Invalid obstacle identity/load'
                cases[active]['rows'].append(root(row))
    assert attempts == list(names) and all(c['layout'] is not None for c in cases.values()), 'Missing/repeated selected obstacle attempt/layout'
    assert set(controls) == set(SPECS) and all(c['end'] for c in controls.values()), 'Missing independent native obstacle controls'
    assert max(c['end']['wall'] for c in controls.values()) < min(starts.values()), 'Native controls must precede cart scenes'
    return starts, cases, controls


def native_support(row, axis):
    # Shipped tapered query rails, expanded by the native wall capsule radius.
    # This is an independent bound on its current support, not rendered mesh contact.
    c, s = math.cos(row['acceptedHeading']), math.sin(row['acceptedHeading'])
    length = row['front'] - .28
    if axis == 'west':
        points = (0, c*length, c*(length-.30)-abs(s)*.04, -abs(s)*.04)
        return .3-min(points)
    points = (0, s*length, s*(length-.30)+abs(c)*.04, abs(c)*.04)
    return .3+max(points)


def analyze_motion(text, selected=None):
    starts, cases, controls = parse(text, selected)
    failures, summaries = [], []
    def fail(name, reason):
        if (name, reason) not in failures:
            failures.append((name, reason))
    for spec, control in controls.items():
        rows, layout, end = control['rows'], control['layout'], control['end']
        coverage(rows, 6000, 'bare native ' + spec)
        # Layout pose precedes native settling; the first measured control row
        # is the movement origin. Deferred native deltas can move a bare actor
        # during settling, so do not call that setup pose a measured start.
        for left, right in zip(rows, rows[1:]):
            if math.dist((left['x'], left['y']), (right['x'], right['y'])) > 8*(right['wall']-left['wall'])/1000+.02:
                fail('control-' + spec, 'bare native control position jumps between samples')
        assert end['wall'] >= rows[-1]['wall'] and math.dist((end['x'], end['y']), (rows[-1]['x'], rows[-1]['y'])) <= 8 * (end['wall'] - rows[-1]['wall']) / 1000 + .02, 'Native obstacle control endpoint jumps'
        wx, sy = layout['wallX'], layout['southY']
        if spec == 'door-open':
            if end['x'] >= wx - .2:
                fail('control-' + spec, 'bare actor never crosses real open doorway')
        else:
            if not wx - .002 <= end['x'] <= wx + .5:
                fail('control-' + spec, 'bare actor never reaches native wall contact')
            if any(r['x'] < wx - .002 for r in rows):
                fail('control-' + spec, 'bare actor crosses closed native wall')
        if spec == 'corner' and any(r['y'] > sy+.002 for r in rows):
            fail('control-' + spec, 'bare actor crosses native corner wall')
        if spec == 'door-open' and any(abs(r['x']-wx)<.5 and not layout['gapY']+.1 <= r['y'] <= layout['gapY']+.9 for r in rows):
            fail('control-' + spec, 'bare actor crosses outside real open doorway')
        if spec == 'corner' and not sy - .5 <= end['y'] <= sy - .1:
            fail('control-' + spec, 'bare actor never reaches native corner contact')
        if spec.startswith('slide-'):
            sign = 1 if spec == 'slide-left' else -1
            contact = [r for r in rows if r['elapsed'] >= 4000 and r['x'] <= wx + .5]
            if len(contact) < 3 or sign * (contact[-1]['y'] - contact[0]['y']) < .15:
                fail('control-' + spec, 'bare Walk never slides along native wall')
    for name, case in cases.items():
        rows, events, layout = case['rows'], case['phases'], case['layout']
        spec = spec_of(name)
        control_layout = controls[spec]['layout']
        assert all(abs(layout[k]-control_layout[k])<=.002 for k in ('wallX','gapY','southY','minY','maxY','owned','doors','startX','startY','heading')), 'Obstacle layout disagrees with matching independent native control'
        coverage(rows, DURATION, 'obstacle ' + name)
        assert all(abs(r['wall'] - starts[name] - r['elapsed']) <= 5 for r in rows), 'Obstacle sample clocks disagree'
        plan = planned(name)
        assert len(events) == len(plan) and all((e['gait'], e['drive']) == (g, d) for e, (_, g, d) in zip(events, plan)), 'Wrong obstacle phase sequence'
        for i, (event, (at, _, _)) in enumerate(zip(events, plan)):
            assert (1200 <= event['elapsed'] <= 6800 if spec == 'door-open' and i == 2 else abs(event['elapsed'] - at) <= 500), 'Late obstacle input phase'
        assert all(b['elapsed'] > a['elapsed'] for a, b in zip(events, events[1:])), 'Nonmonotonic obstacle phases'
        for event, following in zip(events, [*events[1:], dict(elapsed=DURATION)]):
            stage = [r for r in rows if event['elapsed'] + 150 <= r['elapsed'] < following['elapsed'] - 150]
            assert stage and all((r['gait'], r['drive']) == (event['gait'], event['drive']) for r in stage), 'Sampled obstacle input disagrees with phase'
        first = rows[0]
        assert all((r['id'], r['cargoIDs'], r['cargoWeight']) == (first['id'], first['cargoIDs'], first['cargoWeight']) for r in rows), 'Obstacle cart/cargo identity changed'
        assert (first['cargoIDs'] == 'empty' and first['cargoWeight'] == 0 if '-empty-' in name else first['cargoIDs'] != 'empty' and first['cargoWeight'] > 0), 'Wrong obstacle load variant'
        assert math.dist((first['x'], first['y']), (layout['startX'], layout['startY'])) <= .025 and abs(wrap(first['acceptedHeading'] - layout['heading'])) <= .05, 'Obstacle capture starts after movement'
        clock_state = {}
        for row in rows:
            requested = row['gait']
            gait_ok = ((not row['run'] and not row['sprint']) if requested == 0
                       else row['run'] and not row['sprint'] if requested == 1 else row['sprint'])
            clip = ('Bob_WalkBwdNoAim1Hand' if row['drive'] == 4 else 'Bob_'+('Walk','Run','Sprint')[requested]) if row['drive'] else None
            clocks = [c['time'] for c in row['clips'] if c['name'] == clip and c['weight'] > .1 and c['speed'] > 0] if gait_ok else []
            if _motion.moving_clock_stall(clock_state, row, clip, clocks) > 500:
                fail(name, 'Matching native gait clock froze through more than 500ms of measured movement')
        for a, b in zip(rows, rows[1:]):
            dt = (b['wall'] - a['wall']) / 1000
            if math.dist((a['x'], a['y']), (b['x'], b['y'])) > 8 * dt + .02:
                fail(name, 'position jumps between obstacle samples')
            if abs(wrap(b['acceptedHeading'] - a['acceptedHeading'])) > 3 * dt + .05:
                fail(name, 'accepted heading snaps between obstacle samples')
        approach = [r for r in rows if 1000 <= r['elapsed'] < events[2]['elapsed']]
        moving = [r for a, r in zip(approach, approach[1:]) if math.dist((a['x'], a['y']), (r['x'], r['y'])) > .002]
        gait = name.split('-', 3)[2]
        clip = dict(walk='Bob_Walk', run='Bob_Run', sprint='Bob_Sprint')[gait]
        def matched_gait(selected):
            return [r for r in selected if ((not r['run'] and not r['sprint']) if gait == 'walk' else (r['run'] and not r['sprint']) if gait == 'run' else r['sprint'])
                    and any(c['name'] == clip and c['weight'] > .1 and c['speed'] > 0 for c in r['clips'])]
        matched = matched_gait(moving)
        if len(matched) < max(2, .6*len(moving)) or not footprint.progressing(matched, {clip}):
            fail(name, 'requested native approach gait never progresses')
        reverse = [r for r in rows if 8400 <= r['elapsed'] < 13000]
        if not footprint.progressing(reverse, {'Bob_WalkBwdNoAim1Hand'}) or not any(r['direction'] < 0 and r['actualDistance'] > 1e-6 for r in reverse):
            fail(name, 'manual native reverse gait never progresses')
        signed_reverse, reverse_distance = 0., 0.
        for left, right in zip(reverse, reverse[1:]):
            angle = left['acceptedHeading'] + wrap(right['acceptedHeading'] - left['acceptedHeading'])/2
            dx, dy = right['x']-left['x'], right['y']-left['y']
            signed = dx*math.cos(angle) + dy*math.sin(angle)
            signed_reverse += signed
            reverse_distance += math.hypot(dx, dy)
            if signed > .02:
                fail(name, 'manual backward input produces forward displacement')
        if signed_reverse > -.3 or -signed_reverse < .6*reverse_distance:
            fail(name, 'manual reverse lacks measured signed backward travel')
        if any(r['run'] or r['sprint'] for r in rows if 8400 <= r['elapsed']):
            fail(name, 'fast gait survives manual reverse or final release')
        if any(r['direction'] < 0 and r['actualDistance'] > 1e-6 for r in rows if 800 <= r['elapsed'] < events[3]['elapsed']):
            fail(name, 'automatic reverse occurs before manual reverse command')
        released = [r for r in rows if events[2]['elapsed'] <= r['elapsed'] < events[3]['elapsed']]
        progress = peak = 0.
        for a, b in zip(released, released[1:]):
            heading = a['acceptedHeading'] + wrap(b['acceptedHeading']-a['acceptedHeading'])/2
            progress += (b['x']-a['x'])*math.cos(heading)+(b['y']-a['y'])*math.sin(heading)
            peak = max(peak, progress)
            if peak-progress > .03:
                fail(name, 'automatic reverse occurs before manual reverse command')
        wx, sy = layout['wallX'], layout['southY']
        if spec != 'door-open' and any(r['x'] < wx - .002 for r in rows):
            fail(name, 'actor crosses a closed native obstacle')
        if spec == 'corner' and any(r['y'] > sy + .002 for r in rows):
            fail(name, 'actor crosses the native corner')
        late = [r for r in approach if r['elapsed'] >= events[2]['elapsed'] - 1400]
        if spec == 'door-open':
            if not any(r['x'] < wx - .8 for r in approach):
                fail(name, 'open-door forward crossing never reaches release plane')
        else:
            measured_contact = [r for r in late if r['nativeBlocked'] and r['wantsMove'] and (spec.startswith('slide-') or r['blocked'] or r['brace'] > .1)]
            if len(measured_contact) < max(3,.8*len(late)):
                fail(name, 'cart never reaches measured obstacle contact')
            normal_errors = [abs(r['x']-wx-native_support(r,'west')) for r in late]
            if not normal_errors or max(normal_errors) > .08:
                fail(name, 'cart contact disagrees with current native envelope support')
            if spec == 'corner' and any(abs(sy-r['y']-native_support(r,'south'))>.08 for r in late):
                fail(name, 'corner contact disagrees with current native envelope support')
        if spec.startswith('slide-'):
            sign = 1 if spec == 'slide-left' else -1
            contact = [r for r in approach if r['elapsed'] >= 3500 and r['x'] <= wx + 1.6]
            if len(contact) < 3 or sign * (contact[-1]['y'] - contact[0]['y']) < .15:
                fail(name, 'cart never sustains tangential wall slide at contact')
            matched_contact = matched_gait(contact)
            if len(matched_contact) < max(2, .6*len(contact)) or not footprint.progressing(matched_contact, {clip}):
                fail(name, 'requested native gait is not sustained at wall-slide contact')
        elif spec != 'door-open' and (len(late) < 3 or collision.spread(late) > .025):
            fail(name, 'frontal or corner brace never settles at contact')
        pre_reverse = [r for r in rows if 7500 <= r['elapsed'] < 8000]
        assert pre_reverse, 'Missing released contact window'
        baseline = pre_reverse[-1]
        if not spec.startswith('slide-') and reverse[-1]['x'] - baseline['x'] < .3:
            fail(name, 'manual reverse does not back away from wall')
        tail = [r for r in rows if r['elapsed'] >= 14500]
        if collision.spread(tail) > .025 or collision.angle_drift(tail, 'acceptedHeading') > .025:
            fail(name, 'final input release does not settle')
        summaries.append(dict(case=name,approachSamples=len(approach),reverseBackoff=reverse[-1]['x']-baseline['x'],signedReverseTravel=signed_reverse,reverseScope='tangent mobility at wall contact' if spec.startswith('slide-') else 'normal wall escape',maximumNativeContactError=max((abs(r['x']-wx-native_support(r,'west')) for r in late),default=0) if spec!='door-open' else None,minimumX=min(r['x'] for r in rows)))
    return starts, cases, controls, failures, summaries


def analyze(text, profile, selected=None):
    starts, cases, controls, failures, summaries = analyze_motion(text, selected)
    vertices, sha = footprint.mesh(profile)
    _, budget_failures = footprint.native_updates(profile, starts, {name: DURATION for name in starts})
    failures.extend(budget_failures)
    measured = {name: [] for name in starts}
    windows = sorted((start, name) for name, start in starts.items())
    with (profile / 'body-clearance.jsonl').open() as source:
        for line in source:
            frame = json.loads(line, object_pairs_hook=unique)
            finite(frame, ('wallTimeMillis',))
            at = frame['wallTimeMillis']
            i = bisect.bisect_right(windows, (at, chr(0x10ffff))) - 1
            if i < 0:
                continue
            start, name = windows[i]
            if at >= start + DURATION:
                continue
            assert type(frame['female']) is bool and frame['female'] == name.startswith('female-'), 'Wrong native obstacle body model'
            rows = [dict(r, heading=r['acceptedHeading']) for r in cases[name]['rows']]
            slot = dict(frame, wall=at)
            assert footprint.slot_matches(slot, rows, [r['wall'] for r in rows]), 'Obstacle render slot disagrees with measured actor pose'
            measured[name].append(dict(wall=at, elapsed=at-start, **footprint.world_bounds(frame, vertices)))
    geometry_failures = []
    def fail(name, reason):
        if (name, reason) not in geometry_failures:
            geometry_failures.append((name, reason))
    for summary in summaries:
        name = summary['case']
        frames, case = measured[name], cases[name]
        coverage(frames, DURATION, 'obstacle mesh ' + name)
        spec, layout = spec_of(name), case['layout']
        wx, gy, sy = layout['wallX'], layout['gapY'], layout['southY']
        for frame in frames:
            if frame['minY'] < layout['minY'] + .005 or frame['maxY'] > layout['maxY'] + .995:
                fail(name, 'wooden mesh or continuous wheel leaves finite wall span')
            if spec == 'door-open':
                if frame['minX'] < wx + .005 and frame['maxX'] > wx - .005 and (frame['minY'] < gy + .005 or frame['maxY'] > gy + .995):
                    fail(name, 'wooden mesh or continuous wheel crosses an open-door jamb')
            elif frame['minX'] < wx - .005:
                fail(name, 'wooden mesh or continuous wheel enters closed wall or door')
            if spec == 'corner' and frame['maxY'] > sy + .005:
                fail(name, 'wooden mesh or continuous wheel enters corner wall')
        approach_end = case['phases'][2]['elapsed']
        contact = [f for f in frames if approach_end - 1200 <= f['elapsed'] < approach_end]
        if spec == 'door-open':
            west = [f for f in frames if approach_end <= f['elapsed'] < 8000]
            if not west or max(f['maxX'] for f in west[-3:]) > wx - .1:
                fail(name, 'whole wooden mesh never clears open doorway westbound')
        # Native contact uses the independently checked conservative query envelope.
        # Rendered body/tire clearance is reported without an aesthetic contact claim.
        escaped = [f for f in frames if 14000 <= f['elapsed']]
        if not spec.startswith('slide-') and min(f['minX'] for f in escaped) < wx + .1:
            fail(name, 'manual reverse never clears whole wooden mesh and continuous wheel')
        summary.update(contactMeshWallGap=min((f['minX']-wx for f in contact),default=None),meshSamples=len(frames),minimumMeshX=min(f['minX'] for f in frames),finalMeshClearance=min(f['minX'] for f in escaped)-wx)
    return dict(complete=True,caseCount=len(cases),fullSceneCount=72,controlCount=len(controls),selectedScenes=list(cases),
                motionPass=not failures,footprintPass=not geometry_failures,motionFailures=failures,footprintFailures=geometry_failures,
                meshSha256=sha,cases=summaries,visualPass=None,
                limit='Sampled native progression and conservative native-envelope contact; manual normal backoff for frontal/corner/doors and backward tangent mobility for wall slides. Real wall/door mesh plus continuous wheel nonpenetration. Body/torso, grip, feet, clothing, manual video quality, runtime and multiplayer are independent gates; no visual approval or between-frame geometry claim.')


def parse_scenes(value):
    return json.loads(value) if value.startswith('[') else value.split(',')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--log', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--scenes', type=parse_scenes)
    args = parser.parse_args()
    assert not args.output.exists(), 'Refuse to overwrite existing obstacle report'
    report = analyze((args.log or args.profile/'native-launch.log').read_text(errors='replace'), args.profile, args.scenes)
    with args.output.open('x') as target:
        json.dump(report, target, indent=2, allow_nan=False)
        target.write('\n')
    print(json.dumps(report, indent=2, allow_nan=False))
    return 0 if report['motionPass'] and report['footprintPass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
