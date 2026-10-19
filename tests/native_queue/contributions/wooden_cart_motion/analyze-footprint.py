"""Independent sampled wooden mesh/world obstacle proof; pose and runtime gates are separate."""
import argparse
import bisect
import csv
import hashlib
import importlib.util
import json
import math
from pathlib import Path
import re
import numpy as np

_spec = importlib.util.spec_from_file_location('cart_footprint_collision', Path(__file__).with_name('analyze-collision.py'))
collision = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(collision)
wrap, fields = collision.wrap, collision.fields
MESH_SHA = '0f99448cda120bad9f324f38bdbf994f8788ab6731473533475fb6eaf3f4c948'
CENTER = np.array([-6.642862e-6, -.0041269097, -.0010569958])
RADIUS, HALF_AXLE = .001062454, .00024333253
SPECIAL = ('door-closed', 'door-open', 'overlap', 'gait-contact')
EXPECTED = {f'{sex}-{cargo}-{spec}' for sex in ('male', 'female') for cargo in ('empty', 'full') for spec in (*collision.SPECS, 'wall-slide-right')}
EXPECTED.update('male-empty-' + spec for spec in SPECIAL)
FAST_SLIDE_EXPECTED = {f'{sex}-{cargo}-{gait}-{spec}' for sex in ('male', 'female') for cargo in ('empty', 'full')
                       for gait in ('run', 'sprint') for spec in ('wall-slide', 'wall-slide-right')}
WALL_EXIT_EXPECTED = {f'male-{cargo}-{gait}-{spec}-out{angle}' for cargo in ('empty', 'full')
                      for gait in ('walk', 'run', 'sprint') for spec in ('wall-slide', 'wall-slide-right') for angle in (45, 90)}
WALL_MANUAL_EXIT_EXPECTED = {f'{sex}-{cargo}-walk-{spec}-manual-out{angle}' for sex in ('male','female') for cargo in ('empty','full')
                             for spec in ('wall-slide','wall-slide-right') for angle in (45,90)}
WALL_FAST_MANUAL_EXIT_EXPECTED = {f'{sex}-{cargo}-{gait}-{spec}-manual-out{angle}' for sex in ('male','female') for cargo in ('empty','full')
                                  for gait in ('run','sprint') for spec in ('wall-slide','wall-slide-right') for angle in (45,90)}
ANGLES = {1: -3*math.pi/4, 2: 3*math.pi/4, 3: -math.pi/4, 4: math.pi/4,
          5: math.pi, 6: math.pi/2, 7: 0., 8: -math.pi/2}


def steps(name, fast_slide=False, wall_exit=False, wall_manual_exit=False, wall_fast_manual_exit=False, relative=False):
    spec = name.split('-', 2)[2]
    if wall_manual_exit or wall_fast_manual_exit:
        gait, spec = spec.split('-',1)
        spec, angle = spec.rsplit('-manual-out',1)
        right=spec.endswith('right')
        if relative:
            return [(1000,('walk','run','sprint').index(gait),1),(9500,0,4),(12000,0,7 if right else 6),(15500,0,0),(16000,0,8 if right else 5)]+([(21000,0,8 if right else 5)] if angle=='90' else [])+[(26000,0,0)]
        return [(1000,('walk','run','sprint').index(gait),1 if right else 2),(9500,0,6 if right else 8),(12000,0,4 if right else 3),
                (15500,0,0),(16000,0,3 if right else 4)]+([(21000,0,7)] if angle=='90' else [])+[(26000,0,0)]
    if wall_exit:
        gait, spec = spec.split('-', 1)
        spec, angle = spec.rsplit('-out', 1)
        level = ('walk', 'run', 'sprint').index(gait)
        return [(1000, level, 1 if spec.endswith('right') else 2),
                (5500, level, 7 if angle == '90' else 3 if spec.endswith('right') else 4), (10000, 0, 0)]
    if fast_slide:
        gait, spec = spec.split('-', 1)
        return [(1000, 1 if gait == 'run' else 2, 1 if spec.endswith('right') else 2),
                (6000, 0, 0), (7000, 0, None), (9500, 0, 0)]
    if spec in ('passage', 'door-open'):
        return [(1000, 0, 5), (4200 if '-full-' in name else 3000, 0, 0),
                (4600 if '-full-' in name else 3500, 0, None), (9500, 0, 0)]
    if spec == 'overlap':
        return [(1000, 0, 5), (3000, 0, 0), (4000, 0, None), (9000, 0, 0)]
    if spec == 'gait-contact':
        return [(1000, 0, 5), (3500, 1, 5), (6500, 0, 0), (7500, 0, None), (10000, 0, 0)]
    result = list(collision.STEPS['wall-slide' if spec == 'wall-slide-right' else 'wall-block' if spec == 'door-closed' else spec])
    if spec == 'wall-slide-right': result[0] = (1000, 1, 1)
    result[2] = (result[2][0], 0, None)
    return result


def scene_scope(expected_scenes=None, fast_slide=False, wall_exit=False, wall_manual_exit=False, wall_fast_manual_exit=False):
    assert sum((fast_slide,wall_exit,wall_manual_exit,wall_fast_manual_exit)) <= 1, 'Footprint banks are mutually exclusive'
    full = WALL_FAST_MANUAL_EXIT_EXPECTED if wall_fast_manual_exit else WALL_MANUAL_EXIT_EXPECTED if wall_manual_exit else WALL_EXIT_EXPECTED if wall_exit else FAST_SLIDE_EXPECTED if fast_slide else EXPECTED
    if expected_scenes is None:
        return full,full
    assert isinstance(expected_scenes,(list,tuple)) and expected_scenes, 'Selected footprint scenes must be a nonempty list'
    assert all(isinstance(name,str) for name in expected_scenes), 'Selected footprint scenes must be names'
    assert len(set(expected_scenes))==len(expected_scenes), 'Duplicate selected footprint scenes'
    expected=set(expected_scenes)
    assert expected<=full, 'Unknown selected footprint scenes or wrong footprint bank'
    return expected,full


def selected(log, fast_slide=False, wall_exit=False, wall_manual_exit=False, wall_fast_manual_exit=False, expected_scenes=None):
    expected,_=scene_scope(expected_scenes,fast_slide,wall_exit,wall_manual_exit,wall_fast_manual_exit)
    duration=29000 if wall_manual_exit or wall_fast_manual_exit else 12000
    assert re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases='+str(len(expected))+r'(?:\s|$)', log), 'Capture incomplete'
    assert '[WOOD_BANK] FAIL' not in log, 'Scenario failed'
    complete = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    assert len(complete) == len(expected) and {n for n, _ in complete} == expected, 'Missing, duplicate or unexpected footprint cases'
    starts = {n: int(t) for n, t in complete}
    attempts = re.findall(r'\[WOOD_BANK\] CASE (\S+) attempt=\d+ wall=(\d+)', log)
    if expected_scenes is not None:
        assert {n for n,_ in attempts}==expected, 'Missing or unexpected selected footprint attempts'
    assert all(attempts.count((n, str(t))) == 1 for n, t in starts.items()), 'Missing or duplicate selected footprint attempt'
    versions=re.findall(r'\[CART_RELATIVE_MANUAL\] VERSION (\S+)',log)
    relative=bool(versions)
    assert not relative or versions==['1'] and (wall_manual_exit or wall_fast_manual_exit), 'Unknown or misplaced relative manual input version'
    assert relative or '[CART_RELATIVE_MANUAL]' not in log, 'Missing relative manual input version'
    cases = {n: dict(rows=[], events=[], states=[], relative=relative, manual=[]) for n in starts}
    available, active = {}, None
    layout_keys=('wallX','southY','gapY','startX','startY','baselineX','baselineY')
    if wall_fast_manual_exit:layout_keys+=('ownedWalls','wallMinY','wallMaxY')
    for line in log.splitlines():
        if '[CART_COLLISION_LAYOUT] ' in line:
            raw = fields(line.split('[CART_COLLISION_LAYOUT] ', 1)[1])
            available[raw.pop('case', None)] = raw
        attempt = re.search(r'\[WOOD_BANK\] CASE (\S+) attempt=\d+ wall=(\d+)', line)
        if attempt:
            active = attempt[1] if starts.get(attempt[1]) == int(attempt[2]) else None
            if active:
                assert active in available, 'Missing footprint layout'
                cases[active]['layout'] = collision.numeric_fields(' '.join(f'{k}={v}' for k, v in available[active].items()),
                    layout_keys, 'footprint layout')
                if wall_fast_manual_exit:
                    layout=cases[active]['layout']
                    assert (layout['ownedWalls'],layout['wallMinY'],layout['wallMaxY'])==(81,layout['gapY']-40,layout['gapY']+40), 'Incomplete fast manual wall layout'
        if active is None:
            continue
        event = re.search(r'\[WOOD_RAMP_EVENT\] case=(\S+) elapsed=(\d+) gait=(\d+) drive=(\d+)', line)
        if event:
            assert event[1] == active, 'Footprint event outside selected attempt'
            cases[active]['events'].append(tuple(map(int, event.groups()[1:])))
        if '[WOOD_BANK_SAMPLE]' in line:
            row = collision.sample(line)
            assert row['case'] == active and row['wall'] >= starts[active], 'Footprint sample outside selected attempt'
            if row['wall'] < starts[active] + duration:
                cases[active]['rows'].append(row)
        if '[CART_RELATIVE_MANUAL] SAMPLE ' in line:
            raw=fields(line.split('[CART_RELATIVE_MANUAL] SAMPLE ',1)[1])
            assert relative and raw.pop('case',None)==active, 'Relative manual sample outside selected attempt'
            assert set(raw)=={'wall','elapsed','acceptedHeading','id','primary','secondary','inventoryCount','worldID','cargoIds','cargoWeight','queue','actions','path'}, 'Missing or unexpected relative manual diagnostics'
            for key in set(raw)-{'cargoIds','path'}:
                raw[key]=float(raw[key]);assert math.isfinite(raw[key]), 'Nonfinite relative manual diagnostics'
            assert raw['path'] in ('true','false'), 'Invalid relative manual path state'
            if starts[active] <= raw['wall'] < starts[active]+duration: cases[active]['manual'].append(raw)
        if '[CART_FOOTPRINT_STATE] ' in line:
            raw = fields(line.split('[CART_FOOTPRINT_STATE] ', 1)[1])
            assert set(raw) == {'case', 'wall', 'elapsed', 'front', 'blocked', 'recovering', 'clear'}, 'Missing or unexpected footprint diagnostics'
            assert raw.pop('case') == active, 'Footprint diagnostics outside selected attempt'
            for key in ('wall', 'elapsed', 'front'):
                raw[key] = float(raw[key]);assert math.isfinite(raw[key]), 'Nonfinite footprint diagnostics'
            for key in ('blocked', 'recovering', 'clear'):
                assert raw[key] in ('true', 'false'), 'Invalid footprint boolean'
                raw[key] = raw[key] == 'true'
            assert raw['front'] in (1.26, 1.62), 'Invalid footprint envelope'
            if starts[active] <= raw['wall'] < starts[active] + duration:
                cases[active]['states'].append(raw)
    return starts, cases


def relative_manual_inputs(name, rows, probes, events):
    assert [(r['wall'],r['elapsed']) for r in probes]==[(r['wall'],r['elapsed']) for r in rows], 'Missing or misaligned relative manual diagnostics'
    first=probes[0]
    ids=first['cargoIds']
    load_ok=(ids=='empty' and first['cargoWeight']==0) if '-empty-' in name else (re.fullmatch(r'-?\d+(?:,-?\d+)*',ids) and first['cargoWeight']>0)
    assert load_ok, 'Wrong relative manual cargo load'
    assert ids=='empty' or len(set(ids.split(',')))==len(ids.split(',')), 'Duplicate relative manual cargo identity'
    assert ids=='empty' or first['id'] not in map(int,ids.split(',')), 'Cart identity appears in relative manual cargo'
    for r in probes:
        assert r['id']==first['id'] and r['id']==int(r['id']) and r['primary']==r['secondary']==r['id'] and r['inventoryCount']==1 and r['worldID']==-1, 'Relative manual cart identity/ownership changed'
        assert r['cargoIds']==ids and abs(r['cargoWeight']-first['cargoWeight'])<.001, 'Relative manual cargo changed'
        assert r['queue']==r['actions']==0 and r['path']=='false', 'Relative manual action/path ownership changed'
    sign=-1 if '-right-' in name else 1
    stages=[(0,0,0),*events,(29000,0,0)]
    turns=[]
    for index,(a,b) in enumerate(zip(stages,stages[1:])):
        margin=min(200,(b[0]-a[0])/4)
        samples=[(r,p) for r,p in zip(rows,probes) if a[0]+margin<=r['elapsed']<b[0]-margin]
        assert samples and all(r['requestedGait']==a[1] for r,_ in samples), 'Missing relative manual input stage'
        turning=index in (3,5) or index==6 and len(events)==7
        if not turning:
            assert all(r['drive']==a[2] for r,_ in samples), 'Wrong relative manual physical input'
            continue
        straight=4 if index==3 else 1
        commands=[r['drive'] for r,_ in samples]
        assert a[2] in commands and straight in commands and all(d==a[2] for d in commands[:commands.index(straight)]) and all(d==straight for d in commands[commands.index(straight):]), 'Relative manual steering did not release once at target'
        target=sign*(3*math.pi/4 if index==3 else math.pi/4 if index==5 else 0)
        yaw=[wrap(q['acceptedHeading']-p['acceptedHeading'])*sign*(1 if index==3 else -1) for (_,p),(_,q) in zip(samples,samples[1:])]
        assert sum(yaw)>math.radians(15) and sum(-v for v in yaw if v<0)<=.02, 'Relative manual steering oscillates or turns in wrong direction'
        released=[p for r,p in samples if r['drive']==straight]
        assert all(abs(wrap(p['acceptedHeading']-target))<=.04 for p in released), 'Relative manual steering missed target heading'
        assert collision.angle_drift(released,'acceptedHeading')<=.025, 'Relative manual steering continues after release'
        turns.append(dict(target=target,acceptedYaw=sum(yaw)))
    return dict(inputScheme='relative-keyboard-v1',cartID=first['id'],cargoIds=ids,cargoWeight=first['cargoWeight'],turns=turns)


def mesh(profile):
    path = profile / 'WheelbarrowWood.bin'
    data = path.read_bytes()
    proof = json.loads((profile / 'wood-wheel-mesh-proof.json').read_text())
    sha = hashlib.sha256(data).hexdigest()
    assert sha == MESH_SHA and proof['sha256'] == sha and proof['matchesOriginal'] is True, 'Unverified native wooden mesh'
    assert len(data) == 8116*32 and proof['bytes'] == len(data) and proof['indices'] == 16914, 'Wrong native mesh layout'
    vertices = np.frombuffer(data, dtype='<f4').reshape(-1, 8)[:, :3].astype(float)
    assert np.isfinite(vertices).all(), 'Nonfinite native mesh'
    return np.c_[vertices[1114:], np.ones(len(vertices)-1114)], sha


def world_bounds(frame, vertices):
    matrix = np.asarray(frame['cart'], dtype=float)
    assert matrix.shape == (16,) and np.isfinite(matrix).all(), 'Invalid footprint matrix'
    matrix = matrix.reshape(4, 4).T
    assert np.allclose(matrix[3], [0, 0, 0, 1], atol=1e-6), 'Non-affine footprint matrix'
    assert all(.9*76.5 <= np.linalg.norm(matrix[:3, i]) <= 1.1*76.5 for i in range(3)), 'Wrong footprint model scale'
    x, y, angle = (float(frame[k]) for k in ('slotX', 'slotY', 'slotAngle'))
    assert all(math.isfinite(v) for v in (x, y, angle)), 'Nonfinite same-frame footprint slot'
    c, s = math.cos(angle), math.sin(angle)
    world = np.array([[-1.5*c, 0, -1.5*s], [-1.5*s, 0, 1.5*c]])
    linear, offset = world @ matrix[:3, :3], world @ matrix[:3, 3] + [x, y]
    points = vertices[:, :3] @ linear.T + offset
    center = linear @ CENTER + offset
    # Support function of the continuously rotating tire, including axle half-width.
    support = HALF_AXLE*np.abs(linear[:, 0]) + RADIUS*np.hypot(linear[:, 1], linear[:, 2])
    low = np.minimum(points.min(0), center-support)
    high = np.maximum(points.max(0), center+support)
    return dict(minX=float(low[0]), maxX=float(high[0]), minY=float(low[1]), maxY=float(high[1]))


def progressing(rows, names):
    tracks = [(r['elapsed'], c) for r in rows for c in r['clips'] if c['name'] in names and c['weight'] > .1 and c['speed'] > 0]
    return any(t1 > t0 and a['name'] == b['name'] and abs(a['time']-b['time']) > .001
               for (t0, a), (t1, b) in zip(tracks, tracks[1:]))


def brackets(rows, times, at):
    before, after = bisect.bisect_right(times, at)-1, bisect.bisect_left(times, at)
    return [rows[i] for i in {before, after} if 0 <= i < len(rows)]


def slot_matches(frame, rows, times):
    return any(math.dist((frame['slotX'], frame['slotY']), (r['x'], r['y'])) <= 8*abs(r['wall']-frame['wall'])/1000+.04
               and abs(wrap(frame['slotAngle']-r['heading']-math.pi/2)) <= 3*abs(r['wall']-frame['wall'])/1000+.08
               for r in brackets(rows, times, frame['wall']))


def native_updates(profile, starts, durations=None):
    durations = {name: 12000 for name in starts} if durations is None else durations
    assert durations.keys() == starts.keys() and all(type(v) is int and v >= 12000 for v in durations.values()), 'Invalid native grounding durations'
    cases = {name: [] for name in starts}
    required = {'event', 'type', 'sequence', 'time', 'wallTimeMillis', 'dt', 'playerX', 'playerY', 'actorHeading'}
    with (profile/'wood-wheel-native.csv').open() as source:
        reader = csv.DictReader(source)
        assert required <= set(reader.fieldnames or ()), 'Missing native grounding budget columns'
        for raw in reader:
            if raw['event'] != 'grounding':
                continue
            row = {k: float(raw[k]) for k in required-{'event', 'type'}}
            assert all(math.isfinite(v) for v in row.values()), 'Nonfinite native grounding budget'
            assert 0 <= row['dt'] <= .1 and row['sequence'] > 0 and row['sequence'] % 1 == 0, 'Invalid native grounding budget'
            for name, start in starts.items():
                if start <= row['wallTimeMillis'] < start+durations[name]:
                    assert raw['type'] == 'SaucedWheelbarrow.WheelbarrowWood', 'Wrong native grounding cart'
                    cases[name].append(dict(wall=row['wallTimeMillis'], elapsed=row['wallTimeMillis']-start,
                        x=row['playerX'], y=row['playerY'], heading=row['actorHeading'], dt=row['dt'],
                        sequence=row['sequence'], time=row['time']))
                    break
    failures = []
    for name, rows in cases.items():
        # Millisecond clocks may tie; the native sequence and monotonic high-resolution clock may not.
        assert len(rows) >= 80, 'Insufficient native grounding samples: '+name
        assert rows[0]['elapsed'] <= 200 and rows[-1]['elapsed'] >= durations[name]-200, 'Incomplete native grounding sample edges: '+name
        assert all(b['sequence'] > a['sequence'] and b['time'] > a['time'] and 0 <= b['wall']-a['wall'] <= 500
                   for a, b in zip(rows, rows[1:])), 'Incomplete or non-monotonic native grounding window: '+name
        for a, b in zip(rows, rows[1:]):
            # Movement consumes deferred animation deltas before the next animator/render update.
            # Adjacent native timesteps bracket that phase; wall-clock sample spacing does not.
            budget = a['dt']+b['dt']
            if math.dist((a['x'], a['y']), (b['x'], b['y'])) > 8*budget+.02:
                if (name, 'position jumps outside native update budget') not in failures:
                    failures.append((name, 'position jumps outside native update budget'))
            if abs(wrap(b['heading']-a['heading'])) > 3*budget+.05:
                if (name, 'heading snaps outside native update budget') not in failures:
                    failures.append((name, 'heading snaps outside native update budget'))
    return cases, failures


def analyze(text, profile, fast_slide=False, wall_exit=False, wall_manual_exit=False, wall_fast_manual_exit=False, expected_scenes=None):
    assert '[WOOD_BANK] RUN_STARTED' in text, 'Missing footprint run boundary'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[1]
    native, control_failures = collision.controls(log, wall_offset=3)
    starts, cases = selected(log, fast_slide, wall_exit, wall_manual_exit, wall_fast_manual_exit, expected_scenes)
    _,full=scene_scope(expected_scenes,fast_slide,wall_exit,wall_manual_exit,wall_fast_manual_exit)
    duration=29000 if wall_manual_exit or wall_fast_manual_exit else 12000
    wall_manual_exit=wall_manual_exit or wall_fast_manual_exit
    wall_exit=wall_exit or wall_manual_exit
    assert max(c['end']['wall'] for c in native.values()) < min(starts.values()), 'Native controls must precede footprint scenes'
    vertices, sha = mesh(profile)
    updates, native_failures = native_updates(profile, starts, {name:duration for name in starts})
    frames = {name: [] for name in starts}
    windows = sorted((t, n) for n, t in starts.items())
    assert all(b-a >= duration for (a, _), (b, _) in zip(windows, windows[1:])), 'Overlapping footprint case windows'
    for line in (profile / 'body-clearance.jsonl').read_text().splitlines():
        frame = json.loads(line)
        at = frame['wallTimeMillis']
        assert type(at) in (int, float) and math.isfinite(at), 'Invalid footprint frame time'
        for start, name in windows:
            if start <= at < start+duration:
                assert type(frame.get('female')) is bool and frame['female'] == name.startswith('female-'), 'Wrong footprint frame sex'
                bounds = world_bounds(frame, vertices)
                frames[name].append(dict(wall=at, elapsed=at-start, **bounds, slotX=frame['slotX'], slotY=frame['slotY'], slotAngle=frame['slotAngle']))
                break
    motion_failures, footprint_failures, summaries = [*control_failures, *native_failures], [], []
    geometry = native['wall']['start']
    for name, case in cases.items():
        rows, events, states, layout = (case[k] for k in ('rows', 'events', 'states', 'layout'))
        row_times = [r['wall'] for r in rows]
        native_rows = updates[name]
        spec, measured = name.split('-', 2)[2], frames[name]
        desired_gait = 'Run'
        if fast_slide or wall_exit:
            gait, spec = spec.split('-', 1)
            desired_gait = gait.title()
            if wall_exit: spec, _ = spec.rsplit('-out', 1)
            if wall_manual_exit: spec=spec.removesuffix('-manual')
        collision.coverage(rows, starts[name], duration, 'footprint motion '+name, 80)
        collision.coverage(measured, starts[name], duration, 'footprint mesh '+name, 80)
        assert [(r['wall'], r['elapsed']) for r in states] == [(r['wall'], r['elapsed']) for r in rows], 'Missing, duplicate or misaligned footprint diagnostics'
        assert all(layout[k] == geometry[k] for k in ('wallX', 'southY', 'gapY')), 'Footprint layout disagrees with native controls'
        assert math.dist((layout['baselineX'], layout['baselineY']), (native['corner']['end']['x'], native['corner']['end']['y'])) <= .025, 'Wrong footprint control baseline'
        origin = (layout['startX'], layout['startY'])
        assert math.dist((rows[0]['x'], rows[0]['y']), origin) <= .025, 'Footprint scene starts after movement'
        wx, sy, gy = (layout[k] for k in ('wallX', 'southY', 'gapY'))
        relative=case['relative']
        start_offset=(20 if spec=='wall-slide-right' else -20) if wall_fast_manual_exit and relative else 0
        expected_origin = ((wx+2.8, gy+.5+start_offset) if wall_exit else (wx+1.3, sy-1.18) if spec == 'corner-pivot' else
                           (wx+1.8, gy+.5) if spec in ('passage', 'door-open') else
                           (wx+.65, gy+.5) if spec == 'overlap' else
                           (wx+1.4, gy+.5) if spec == 'gait-contact' else (geometry['x'], geometry['y']))
        assert math.dist(origin, expected_origin) <= .025, 'Wrong footprint fixture start'
        planned = steps(name, fast_slide, wall_exit, wall_manual_exit, wall_fast_manual_exit,relative=relative)
        assert len(events) == len(planned), 'Missing footprint input events'
        for actual, expected in zip(events, planned):
            at, gait, drive = actual
            assert abs(at-expected[0]) <= 500 and gait == expected[1] and (drive == expected[2] if expected[2] is not None else drive in ANGLES), 'Wrong footprint input event'
        assert all(b[0] > a[0] for a, b in zip(events, events[1:])), 'Non-monotonic footprint events'
        relative_comparison=relative_manual_inputs(name,rows,case['manual'],events) if relative else None
        assert relative or not case['manual'], 'Unexpected relative manual diagnostics'
        stages = [(0, 0, 0), *events, (duration, 0, 0)]
        for a, b in zip(stages, stages[1:]):
            margin = min(200, (b[0]-a[0])/4)
            stage = [r for r in rows if a[0]+margin <= r['elapsed'] < b[0]-margin]
            if not relative:
                assert stage and all((r['requestedGait'], r['drive']) == a[1:] for r in stage), 'Missing or wrong footprint input stage'
        def fail(reason, body=False):
            collection = footprint_failures if body else motion_failures
            if (name, reason) not in collection:
                collection.append((name, reason))
        if wall_fast_manual_exit:
            if any(not layout['wallMinY'] <= r['y'] <= layout['wallMaxY']+1 for r in rows):
                fail('actor leaves finite wall span')
            if any(f['minY'] < layout['wallMinY'] or f['maxY'] > layout['wallMaxY']+1 for f in measured):
                fail('wooden mesh and wheel leave finite wall span',True)
        def window(a, b):
            return [r for r in rows if a <= r['elapsed'] < b]
        def quiet(selected, reason):
            assert len(selected) >= 2, 'Insufficient '+reason+' samples'
            if collision.spread(selected) > .015 or collision.angle_drift(selected, 'heading') > math.radians(1) or collision.wheel_roll_error(selected) > .01:
                fail(reason)
        initial_heading = -3*math.pi/4 if spec == 'wall-slide-right' else collision.HEADINGS.get(spec, math.pi)
        if abs(wrap(rows[0]['heading']-initial_heading)) > math.radians(4):
            fail('wrong initial footprint heading')
        quiet_run, yaw = [], 0.
        for a, b in zip(rows, rows[1:]):
            distance = math.dist((a['x'], a['y']), (b['x'], b['y']))
            turn = wrap(b['heading']-a['heading'])
            yaw = yaw+turn if distance <= .002 else 0.
            if abs(yaw) > math.radians(2): fail('heading changes without measured movement')
            quiet_run = (quiet_run+[b] if quiet_run else [a, b]) if distance <= .002 else []
            if quiet_run and collision.spread(quiet_run) <= .005 and collision.wheel_roll_error(quiet_run) > .02:
                fail('wheel spins without wheel-center movement')
        reverse_event = events[-2]
        reverse = window(reverse_event[0]+300, events[-1][0])
        before = min(rows, key=lambda r: abs(r['elapsed']-reverse_event[0]))
        if not wall_exit and abs(wrap(ANGLES[reverse_event[2]]-before['heading']-math.pi)) > math.pi/8+.05:
            fail('reverse key is not opposite accepted heading')
        if not wall_exit and not any(r['direction'] < 0 and r['actualDistance'] > 1e-6 for r in reverse): fail('reverse escape never engages')
        if not wall_exit and not progressing(reverse, {'Bob_WalkBwdNoAim1Hand'}): fail('native reverse gait does not progress')
        if any((r['stationaryRoot'] or r['requested'] < 0 or r['direction'] < 0) and (r['run'] or r['sprint']) for r in rows):
            fail('fast gait during stationary or reverse motion')
        if spec in ('wall-block', 'wall-slide', 'wall-slide-right', 'door-closed'):
            approach = window(1100, events[1][0])
            if fast_slide or wall_exit:
                frame_times = [f['wall'] for f in measured]
                approach = [r for r in approach if all(f['minX'] > wx+.65
                    for f in brackets(measured, frame_times, r['wall']))]
                actual_fast = [r for r in approach if r['run'] == (desired_gait == 'Run')
                               and r['sprint'] == (desired_gait == 'Sprint') and r['actualDistance'] > 1e-6]
                fast_progress = progressing(actual_fast, {'Bob_'+desired_gait})
            else:
                fast_progress = any(r['run'] and r['actualDistance'] > 1e-6 for r in approach) and progressing(approach, {'Bob_Run'})
            if not fast_progress:
                fail('native requested fast gait does not progress')
        if spec in ('passage', 'door-open'):
            if min(r['x'] for r in window(1200, events[1][0])) >= wx-.2: fail('opening never crossed west')
            if max(r['x'] for r in reverse) <= wx+.2: fail('opening never crossed east')
        else:
            if spec not in ('corner-pivot', 'gait-contact') and not any(s['blocked'] for s in states): fail('obstacle guard never reports rejection')
            reverse_travel = sum((b['x']-a['x'])*math.cos(before['heading']+math.pi)+(b['y']-a['y'])*math.sin(before['heading']+math.pi) for a, b in zip(reverse, reverse[1:]))
            if not wall_exit and reverse_travel < .2: fail('reverse does not escape obstacle')
        if spec in ('wall-block', 'door-closed'):
            quiet(window(4500, 5800), 'wall contact does not remain quiet')
            if min(f['minX'] for f in measured if 4500 <= f['elapsed'] < 5800) > wx+.65:
                fail('wooden mesh never approaches obstacle contact', True)
        if spec == 'corner-pivot':
            contact = window(3000, 3800)
            quiet(contact, 'blocked corner changes pose or position')
            unresolved = any(r['stationaryRoot'] and r['drive'] == events[0][2]
                and abs(wrap(r['target']-ANGLES[r['drive']])) <= .05
                and abs(wrap(r['target']-r['heading'])) >= math.radians(20) for r in contact)
            if not unresolved and not any(s['blocked'] for s in states if 3000 <= s['elapsed'] < 3800):
                fail('corner contact not demonstrated under held input')
        slide_comparison = None
        if spec in ('wall-slide', 'wall-slide-right'):
            direction = -1 if spec.endswith('right') else 1
            contact_start, contact_end = (events[1][0]-1000, events[1][0]-200) if wall_exit else (4500,5800)
            approach = window(1000, contact_end)
            if approach[0]['x']-min(r['x'] for r in approach) < .15 or direction*(approach[-1]['y']-approach[0]['y']) < .15:
                fail('wall slide has no accepted diagonal approach')
            # Compare measured motion after mesh contact, with the bare Walk control in the same direction.
            frame_times = [f['wall'] for f in measured]
            contact = [r for r in window(contact_start, contact_end) if any(f['minX'] <= wx+.65
                for f in brackets(measured, frame_times, r['wall']))]
            metrics = collision.slide_metrics(contact, direction)
            if (fast_slide or wall_exit) and collision.angle_drift(contact, 'heading') > math.radians(1.5):
                fail('wall slide heading oscillates at steady contact')
            if wall_exit and any(abs(wrap(r['heading']-direction*math.pi/2)) > math.radians(1.5) for r in contact):
                fail('wall exit does not start from tangent wall slide')
            bare = native['wall-slide-right' if direction < 0 else 'wall-slide-left']['slide']
            slide_comparison = dict(cart=metrics, bareWalk=bare, requestedGait=desired_gait)
            if metrics['durationMs'] < 500 or metrics['tangent'] < .15 or metrics['normal'] > .15 or any(b['wall']-a['wall'] > 500 for a,b in zip(contact,contact[1:])):
                fail('wall slide has no accepted tangential movement at contact')
            if not any(s['blocked'] for s in states if contact and contact[0]['wall'] <= s['wall'] <= contact[-1]['wall']):
                fail('wall slide contact never reports normal rejection')
            actual_contact = ([r for r in contact if r['run'] == (desired_gait == 'Run')
                               and r['sprint'] == (desired_gait == 'Sprint') and r['actualDistance'] > 1e-6
                               and any(c['name'] == 'Bob_'+desired_gait and c['weight'] > .1 and c['speed'] > 0 for c in r['clips'])]
                              if fast_slide or wall_exit else contact)
            if (not progressing(actual_contact, {'Bob_'+desired_gait}) or (fast_slide or wall_exit) and
                (collision.slide_metrics(actual_contact, direction)['durationMs'] < 500
                 or any(b['wall']-a['wall'] > 500 for a,b in zip(actual_contact,actual_contact[1:])))):
                fail('native requested fast gait does not progress at wall contact')
        exit_comparison = None
        if wall_exit:
            departure_gait='Walk' if wall_manual_exit else desired_gait
            forward_event=events[4] if wall_manual_exit else events[1]
            before=min(rows,key=lambda r:abs(r['elapsed']-forward_event[0]))
            departure = window(forward_event[0]+(3500 if wall_manual_exit else 700), events[-1][0]-200)
            outward = (0 if name.endswith('out90') else (-1 if '-right-' in name else 1)*math.pi/4) if relative else ANGLES[events[-2][2] if wall_manual_exit else forward_event[2]]
            held_exit = window(forward_event[0], events[-1][0])
            if not wall_manual_exit and any(r['requested'] <= 0 or r['direction'] <= 0 or r['active'] or r['stationaryRoot'] or r['braking'] for r in held_exit):
                fail('wall exit interrupts held forward motion')
            if (abs(wrap(before['heading']-outward)) < math.radians(30)
                or abs(wrap(departure[-1]['heading']-outward)) >= abs(wrap(before['heading']-outward))-math.radians(30)):
                fail('wall exit does not turn toward outward target')
            aligned = [r for r in departure if abs(wrap(r['heading']-outward)) <= math.radians(4)]
            if not aligned or departure[-1]['wall']-aligned[-1]['wall'] > 500 or collision.angle_drift(window(events[-1][0]-1500, events[-1][0]-200), 'heading') > math.radians(1.5):
                fail('wall exit never holds outward heading')
            if departure[-1]['x']-before['x'] < .3:
                fail('wall exit has no outward displacement')
            for at in range(math.ceil(departure[0]['elapsed']), int(departure[-1]['elapsed'])-500, 500):
                moving_window = window(at, at+600)
                if len(moving_window) < 2 or moving_window[-1]['x']-moving_window[0]['x'] <= .005:
                    fail('wall exit freezes instead of continuing outward')
            actual_exit = [r for r in departure if r['direction'] > 0 and r['actualDistance'] > 1e-6
                           and r['run'] == (departure_gait == 'Run') and r['sprint'] == (departure_gait == 'Sprint')
                           and any(c['name'] == 'Bob_'+departure_gait and c['weight'] > .1 and c['speed'] > 0 for c in r['clips'])]
            if (not progressing(actual_exit, {'Bob_'+departure_gait}) or len(actual_exit) < 2
                or actual_exit[0]['wall']-departure[0]['wall'] > 500 or departure[-1]['wall']-actual_exit[-1]['wall'] > 500
                or any(b['wall']-a['wall'] > 500 for a,b in zip(actual_exit,actual_exit[1:]))):
                fail('native requested gait does not continue during wall exit')
            contact_mesh = [f for f in measured if contact_start <= f['elapsed'] < contact_end]
            escaped_mesh = [f for f in measured if events[-1][0]-1500 <= f['elapsed'] < events[-1][0]]
            clearance = min(f['minX'] for f in escaped_mesh)
            if clearance < wx+.35 or clearance-min(f['minX'] for f in contact_mesh) < .3:
                fail('wall exit does not clear all wooden mesh and wheel', True)
            exit_comparison = dict(outwardHeading=outward, outwardDisplacement=departure[-1]['x']-before['x'], minClearance=clearance-wx,
                                   precontactRootWallGapMin=min((r['x']-wx for r in contact), default=None),
                                   precontactRootWallGapMax=max((r['x']-wx for r in contact), default=None))
        manual_comparison = None
        if wall_manual_exit:
            if name.endswith('out90'):
                gentle=window(events[5][0]-700,events[5][0]-200)
                gentle_heading=(-1 if '-right-' in name else 1)*math.pi/4 if relative else ANGLES[events[4][2]]
                if not gentle or any(abs(wrap(r['heading']-gentle_heading)) > math.radians(4) for r in gentle):
                    fail('manual exit never holds gentle forward heading before perpendicular turn')
            straight=window(events[1][0]+1100,events[2][0]-100)
            arc=window(events[2][0]+300,events[3][0]-100)
            for selected_reverse in (straight,arc):
                actual_reverse=[r for r in selected_reverse if r['direction'] < 0 and r['requested'] < 0 and r['actualDistance'] > 1e-6
                                and not r['run'] and not r['sprint'] and not r['stationaryRoot']
                                and any(c['name']=='Bob_WalkBwdNoAim1Hand' and c['weight']>.1 and c['speed']>0 for c in r['clips'])]
                if (not progressing(actual_reverse,{'Bob_WalkBwdNoAim1Hand'}) or len(actual_reverse)<2
                    or actual_reverse[0]['wall']-selected_reverse[0]['wall']>500 or selected_reverse[-1]['wall']-actual_reverse[-1]['wall']>500
                    or any(b['wall']-a['wall']>500 for a,b in zip(actual_reverse,actual_reverse[1:]))):
                    fail('manual reverse gait does not progress through straight and arc stages')
                backward_travel=-sum((b['x']-a['x'])*math.cos(a['heading'])+(b['y']-a['y'])*math.sin(a['heading']) for a,b in zip(selected_reverse,selected_reverse[1:]))
                if backward_travel < .1:fail('manual reverse has no measured backward travel')
            arc_start=min(rows,key=lambda r:abs(r['elapsed']-events[2][0]))
            if arc[-1]['x']-arc_start['x'] < .15:fail('manual reverse arc does not create wall clearance')
            if abs(wrap(arc[-1]['heading']-arc_start['heading'])) < math.radians(15):fail('manual reverse arc never turns')
            quiet(window(events[3][0]+250,events[4][0]),'manual reverse does not stop before forward exit')
            if any(r['requested'] < 0 or r['direction'] < 0 or r['active'] or r['braking'] or r['stationaryRoot'] for r in departure):
                fail('manual forward exit retains reverse or stationary motion')
            manual_comparison=dict(reverseArcOutwardDisplacement=arc[-1]['x']-arc_start['x'],inputProof=relative_comparison)
        if spec == 'overlap':
            quiet(window(1200, 2800), 'initial overlap accepts forward movement')
            if collision.angle_drift(window(0, events[-1][0]), 'heading') > math.radians(1): fail('overlap escape adds yaw')
            if not any(s['blocked'] for s in states if 1200 <= s['elapsed'] < 2800): fail('overlap forward request never reports rejection')
            if not any(s['recovering'] for s in states if reverse_event[0] <= s['elapsed'] < events[-1][0]): fail('overlap recovery never engages')
        if spec == 'gait-contact':
            promotion = window(3700, 6300)
            quiet(promotion, 'gait promotion at contact moves actor or wheel')
            if (not any(r['requestedGait'] == 1 for r in promotion)
                or any(r['run'] or r['sprint'] or r['drive'] != 5 or r['requested'] < 0 or r['direction'] < 0
                       or r['stationary'] or r['stationaryRoot'] for r in promotion)
                or progressing(promotion, {'Bob_Run', 'Bob_Sprint'})
                or any(s['front'] != 1.26 or not s['clear'] or s['recovering'] for s in states if 3700 <= s['elapsed'] < 6300)):
                fail('gait promotion at contact was not denied')
        settle_start=28300 if wall_manual_exit else 11500
        quiet(window(max(settle_start, events[-1][0]+1250), duration), 'final release does not settle')
        if any(r['stationary'] or r['braking'] or r['run'] or r['sprint'] for r in window(settle_start, duration)): fail('final release does not settle')
        for frame in measured:
            assert slot_matches(frame, rows, row_times), 'Same-frame slot disagrees with both actor position/heading brackets'
            if spec == 'overlap':
                if frame['elapsed'] >= events[-1][0] and frame['minX'] < wx+.01: fail('overlap never clears wooden mesh', True)
                continue
            if spec in ('passage', 'door-open'):
                if frame['minX'] <= wx+.005 and frame['maxX'] >= wx-.005 and (frame['minY'] < gy-.005 or frame['maxY'] > gy+1+.005):
                    fail('wooden mesh crosses outside open gap', True)
            elif frame['minX'] < wx-.005: fail('wooden mesh enters closed wall', True)
            if spec == 'corner-pivot' and frame['maxY'] > sy+.005: fail('wooden mesh enters corner wall', True)
        if spec == 'overlap':
            if measured[0]['minX'] >= wx-.01: fail('initial overlap not demonstrated', True)
            if any(f['minX'] < measured[0]['minX']-.01 for f in measured if f['elapsed'] < reverse_event[0]): fail('initial overlap penetration worsens', True)
            escape = [f for f in measured if reverse_event[0] <= f['elapsed'] < events[-1][0]]
            if any(b['minX'] < a['minX']-.01 for a, b in zip(escape, escape[1:])): fail('overlap recovery increases penetration', True)
        summaries.append(dict(case=name, samples=len(rows), frames=len(measured), nativeUpdates=len(native_rows), minX=min(f['minX'] for f in measured), maxY=max(f['maxY'] for f in measured),
                              initialOverlap=spec=='overlap', slideComparison=slide_comparison, exitComparison=exit_comparison, manualComparison=manual_comparison))
    return dict(complete=True, caseCount=len(cases), controlCount=len(native), meshSha256=sha, cases=summaries,
                scope='full-matrix' if expected_scenes is None else 'selected-scenes', matrixComplete=set(cases)==full,
                fullSceneCount=len(full), expectedScenes=sorted(cases),
                inputScheme='relative-keyboard-v1' if any(c['relative'] for c in cases.values()) else 'legacy-absolute-v0',
                motionPass=not motion_failures, footprintPass=not footprint_failures, motionFailures=motion_failures, footprintFailures=footprint_failures,
                limit='Sampled held wooden mesh and continuous wheel-cylinder support against tile wall/door fixture planes; no separate collision body or vehicle-hull clearance claim. Initial overlap is an explicit recovery case, not an initial-clearance PASS. Motion between captured frames, body/grip/clothing, visual review, runtime errors and multiplayer authority remain separate gates.')


def parse_scenes(value):
    return json.loads(value) if value.lstrip().startswith('[') else [name.strip() for name in value.split(',')]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    bank = parser.add_mutually_exclusive_group()
    bank.add_argument('--fast-slide', action='store_true', help='Require the separate 16-case native Run/Sprint slide bank')
    bank.add_argument('--wall-exit', action='store_true', help='Require 24 male Walk/Run/Sprint outward wall exits')
    bank.add_argument('--wall-manual-exit', action='store_true', help='Require 16 male/female Walk manual reverse-arc wall exits')
    bank.add_argument('--wall-fast-manual-exit', action='store_true', help='Require 32 male/female Run/Sprint approaches followed by manual Walk reverse-arc exits')
    parser.add_argument('--log', type=Path)
    parser.add_argument('--scenes', type=parse_scenes, help='Exact selected scene names as a JSON list or comma-separated list; requires every listed scene and rejects other scenes')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    assert args.profile.is_dir(), 'Capture profile is missing'
    assert not args.output.exists(), 'Refuse to overwrite an existing report'
    result = analyze((args.log or args.profile/'native-launch.log').read_text(errors='replace'), args.profile, args.fast_slide, args.wall_exit, args.wall_manual_exit, args.wall_fast_manual_exit, args.scenes)
    with args.output.open('x') as target:
        json.dump(result, target, indent=2, allow_nan=False);target.write('\n')
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0 if result['motionPass'] and result['footprintPass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
