"""Strict native collision release proof; natural impact and visual quality are separate."""
import bisect
import csv
import json
import math
from pathlib import Path
import re

CASES = [f'{sex}-{load}-{spec}' for sex in ('male', 'female')
         for load in ('empty', 'full') for spec in ('sprint-wall', 'native-impact')]
PROTECTED = {'CollideWithWallState', 'PlayerGetUpState'}
BOOLS = ('run', 'sprint', 'enabled', 'steering', 'hit', 'knocked', 'getup', 'ragdoll', 'ignore', 'pivot', 'brake',
         'inInventory', 'worldExact', 'worldPersistent')
NUMBERS = ('wall', 'elapsed', 'x', 'y', 'stepX', 'stepY', 'pace', 'brace', 'id', 'primary', 'secondary',
           'cargo', 'itemPhase', 'inventoryCount', 'worldCount', 'woodCount', 'worldId', 'worldX', 'worldY', 'worldZ', 'rotation')
BONEMAP = {'Bip01_Spine', 'Bip01_L_Hand', 'Bip01_R_Hand', 'Bip01_L_Foot', 'Bip01_R_Foot'}
SETTLE_MS = 240
# Mesh-local measurements shared with CartWheelSpin.CENTER and CartGrip.handle("WheelbarrowWood").
CART_POINTS = {'axle': (-6.642862e-6, -.0041269097, -.0010569958),
               'leftHandle': (.00172237, .00541905, -.00342593),
               'rightHandle': (-.00172238, .00541905, -.00342593)}


def fields(text):
    return dict(token.split('=', 1) for token in text.split() if '=' in token)


def read_rows(path):
    assert path.is_file(), 'Missing render evidence: ' + str(path)
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    assert rows, 'Empty render evidence: ' + str(path)
    for row in rows:
        assert type(row['wallTimeMillis']) in (int, float) and math.isfinite(row['wallTimeMillis']), 'Invalid render clock'
    return rows


def covered(times, wall, message):
    i = bisect.bisect_left(times, wall)
    assert times and min(abs(t-wall) for t in times[max(0, i-1):i+1]) <= 150, message


def world_wheel_floor(row):
    # shortcut: this wheel cylinder matches WoodenWheelNativeProbe; recalibrate after wooden mesh changes.
    x, y, z = map(math.radians, row['angle'])
    cx, sx, sy, cy, sz, cz = math.cos(x), math.sin(x), math.sin(y), math.cos(y), math.sin(z), math.cos(z)
    up = (cx*sz+sx*sy*cz, cx*cz-sx*sy*sz, -sx*cy)
    m = row['transform']
    vertical = [sum(up[j]*m[i*4+j] for j in range(3)) for i in range(4)]
    lowest = sum(a*b for a, b in zip(vertical, (-6.642862e-6, -.0041269097, -.0010569958, 1)))
    lowest -= .001062454*math.hypot(vertical[1], vertical[2]) + .00024333253*abs(vertical[0])
    return row['z'] + (1.5/2.44949)*lowest


def matrix_point(matrix, point):
    return [sum(matrix[j*4+i]*value for j, value in enumerate((*point, 1))) for i in range(3)]


def world_cart_points(row):
    # Native composition is Rx * Ry * Rz * transform, then the world camera's tile projection.
    ax, ay, az = map(math.radians, row['angle'])
    cx, sx, cy, sy, cz, sz = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay), math.cos(az), math.sin(az)
    result = {}
    for name, point in CART_POINTS.items():
        x, y, z = matrix_point(row['transform'], point)
        x, y = cz*x-sz*y, sz*x+cz*y
        x, z = cy*x+sy*z, -sy*x+cy*z
        y, z = cx*y-sx*z, sx*y+cx*z
        result[name] = [row['x']+1.5*x, row['y']-1.5*z, row['z']+(1.5/2.44949)*y]
    return result


def held_cart_points(row):
    c, s = math.cos(row['slotAngle']), math.sin(row['slotAngle'])
    result = {}
    for name, point in CART_POINTS.items():
        x, y, z = matrix_point(row['cart'], point)
        result[name] = [row['slotX']-1.5*(c*x+s*z), row['slotY']+1.5*(-s*x+c*z),
                        None if 'slotZ' not in row else row['slotZ']+(1.5/2.44949)*y]
    return result


def settle_diagnostics(profile, start, drop, scene_world):
    first = scene_world[0]
    trajectory = [r for r in scene_world if r['wallTimeMillis'] < drop+SETTLE_MS]
    settled = [r for r in scene_world if r['wallTimeMillis'] >= drop+SETTLE_MS]
    if settled:
        trajectory.append(settled[0])
    result = dict(evidenceKind='Prepared render matrices; actual GL draw is not proved.',
                  staticFromWallTimeMillis=drop+SETTLE_MS, lastHeld=None, handoffDelta=None,
                  firstWorld=dict(wallTimeMillis=first['wallTimeMillis'], points=world_cart_points(first)),
                  trajectory=[dict(wallTimeMillis=r['wallTimeMillis'], elapsedSinceDropMs=r['wallTimeMillis']-drop,
                                   points=world_cart_points(r)) for r in trajectory], missingEvidence=[])
    path = profile / 'body-clearance.jsonl'
    if not path.is_file() or not path.read_text().strip():
        result['missingEvidence'].append('body-clearance.jsonl: no held mesh preparation evidence')
        return result
    held = [r for r in read_rows(path) if start <= r['wallTimeMillis'] < min(drop, first['wallTimeMillis'])]
    if not held:
        result['missingEvidence'].append('body-clearance.jsonl: no held pose before sampled release/first world pose')
        return result
    before = max(held, key=lambda r: r['wallTimeMillis'])
    assert len(before['cart']) == 16 and all(type(v) in (int, float) and math.isfinite(v)
        for v in before['cart']+[before[k] for k in ('slotX', 'slotY', 'slotAngle')]), 'Invalid held diagnostic pose'
    if 'slotZ' in before:
        assert type(before['slotZ']) in (int, float) and math.isfinite(before['slotZ']), 'Invalid held diagnostic height'
    source = held_cart_points(before)
    result['lastHeld'] = dict(wallTimeMillis=before['wallTimeMillis'],
                             gapToFirstWorldMs=first['wallTimeMillis']-before['wallTimeMillis'], points=source)
    result['handoffDelta'] = {name: dict(xy=math.dist(source[name][:2], result['firstWorld']['points'][name][:2]),
        z=None if source[name][2] is None else result['firstWorld']['points'][name][2]-source[name][2]) for name in CART_POINTS}
    if 'slotZ' not in before:
        result['missingEvidence'].append('body-clearance.jsonl: slotZ absent; held vertical handoff cannot be measured')
    if 'itemId' not in before:
        result['missingEvidence'].append('body-clearance.jsonl: itemId absent; held pose association uses the isolated scene window')
    return result


def actual_settle(profile, start, item):
    path = profile / 'wheel-roll-draws.jsonl'
    assert path.is_file(), 'Missing actual split draw receipts: wheel-roll-draws.jsonl'
    receipts = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    rows = []
    for row in receipts:
        assert type(row.get('wall')) in (int, float) and math.isfinite(row['wall']), 'Invalid actual draw clock'
        if not start <= row['wall'] < start+12000:
            continue
        assert row.get('source') in ('held', 'world'), 'Unknown actual draw source'
        assert len(row['cart']) == 16 and all(type(v) in (int, float) and math.isfinite(v)
            for v in row['cart']+[row[k] for k in ('x', 'y', 'angle', 'phase')]), 'Invalid actual draw pose'
        if row['source'] == 'world':
            assert row.get('itemId') == item, 'Foreign actual world cart draw'
        points = held_cart_points(dict(cart=row['cart'], slotX=row['x'], slotY=row['y'], slotAngle=row['angle']))
        rows.append(dict(wall=row['wall'], source=row['source'], points=points))
    assert all(a['wall'] <= b['wall'] for a, b in zip(rows, rows[1:])), 'Unordered actual split draws'
    world = [r for r in rows if r['source'] == 'world']
    assert world, 'Missing actual released world draw'
    first = world[0]
    held = [r for r in rows if r['source'] == 'held' and r['wall'] < first['wall']]
    assert held and first['wall']-held[-1]['wall'] <= 150, 'Missing recent actual held draw before world handoff'
    before = held[-1]
    jumps = {name: math.dist(before['points'][name][:2], first['points'][name][:2]) for name in CART_POINTS}
    assert max(jumps.values()) <= .03, 'Actual held-to-world point jump exceeds .03 tile'
    # Millisecond clocks can repeat across render passes; use the last receipt for each distinct clock.
    distinct = list({r['wall']: r for r in world}.values())
    early = [r for r in distinct if r['wall'] < first['wall']+240]
    assert len(early) >= 5, 'Insufficient actual settle draw timestamps before 240ms'
    endpoint = next((r for r in distinct if r['wall'] > first['wall']+300), None)
    assert endpoint is not None, 'Missing actual settled endpoint after 300ms'
    transition = [r for r in distinct if r['wall'] <= first['wall']+300]+[endpoint]
    drift = max(math.dist(r['points']['axle'][:2], first['points']['axle'][:2]) for r in transition)
    assert drift <= .01, 'Actual settle axle drift exceeds .01 tile'
    speed = max((math.dist(b['points'][name][:2], a['points'][name][:2])*1000/(b['wall']-a['wall'])
                 for a, b in zip(transition, transition[1:]) for name in ('leftHandle', 'rightHandle')), default=0)
    assert speed <= 2, 'Actual settle handle step exceeds 2 tiles/s'
    middle = [r for r in distinct if 80 <= r['wall']-first['wall'] <= 120]
    assert middle, 'Missing actual settle draw at 80..120ms'
    remaining = max(math.dist(r['points'][name][:2], endpoint['points'][name][:2])
                    for r in middle for name in ('leftHandle', 'rightHandle'))
    assert remaining >= .02, 'Actual Sprint settle completed before 80..120ms'
    return dict(scope='Actual split-draw XY handoff and bounded cart settle; no body/pose visual pass.',
                heldWall=before['wall'], firstWorldWall=first['wall'], handoffGapMs=first['wall']-before['wall'],
                handoffJumpXY=jumps, earlyWorldTimestamps=len(early), axleDriftXY=drift,
                maxHandleStepTilesPerSecond=speed, middleHandleDistanceToEndpointXY=remaining,
                endpointWall=endpoint['wall'], trajectory=transition)


def emergency_recoil(rows, drop):
    # These injected scenes travel west: decreasing X advances into the released cart.
    # Stop at the transition to GetUp; later intentional recovery walking is a separate gate.
    first = next(i for i, row in enumerate(rows) if row['wall'] == drop)
    end = first
    while end < len(rows) and rows[end]['state'] == 'CollideWithWallState':
        end += 1
    episode = rows[first:end]
    assert len(episode) >= 2, 'Missing sampled collision episode after exact emergency drop'
    assert end < len(rows) and rows[end]['state'] == 'PlayerGetUpState', 'Emergency recoil lacks native getup boundary'
    minimum = min(row['x'] for row in episode)
    forward = max(0, episode[0]['x']-minimum)
    rebound = episode[-1]['x']-minimum
    result = dict(scope='Sampled actor X motion during westbound released collision episode; no body/pose visual pass.',
                  firstDroppedWall=drop, lastCollisionWall=episode[-1]['wall'], firstGetupWall=rows[end]['wall'],
                  collisionSamples=len(episode), firstDroppedX=episode[0]['x'], minimumX=minimum,
                  lastCollisionX=episode[-1]['x'], forwardIntrusionTiles=forward, backwardReboundTiles=rebound,
                  maxForwardIntrusionTiles=.02, minBackwardReboundTiles=.5)
    assert forward <= .02, f'Emergency actor forward intrusion {forward:.6f} exceeds .02 tile after exact drop'
    assert rebound >= .5, f'Emergency native backward rebound {rebound:.6f} is below .5 tile before getup'
    return result


def analyze(profile, text, selected=None, require_natural=False, require_settle=False, require_recoil=False):
    profile = Path(profile)
    expected = CASES if selected is None else selected
    assert expected and len(set(expected)) == len(expected) and set(expected) <= set(CASES), 'Invalid impact selection'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    assert '[WOOD_BANK] FAIL' not in log and '[QUEUE_TEST] FAIL' not in log, 'Fixture failed'
    complete = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    assert [name for name, _ in complete] == expected, 'Missing, repeated or reordered impact scenes'
    assert re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases=' + str(len(expected)) + r'(?:\s|$)', log), 'Capture incomplete'
    tail = read_rows(profile / 'action-tail-poses.jsonl')
    grip = read_rows(profile / 'wood-grip-poses.jsonl')
    world = read_rows(profile / 'world-cart-poses.jsonl') if any(n.endswith('native-impact') for n in expected) else []
    with (profile / 'wood-wheel-native.csv').open() as stream:
        wheel = list(csv.DictReader(stream))
    for row in wheel:
        row['wallTimeMillis'] = float(row['wallTimeMillis'])
        assert math.isfinite(row['wallTimeMillis']), 'Nonfinite wheel clock'
    summaries = []
    for name, start in complete:
        start = int(start)
        assert len(re.findall(r'\[WOOD_BANK\] CASE ' + re.escape(name) + r' attempt=\d+ wall=' + str(start) + r'(?:\s|$)', log)) == 1, 'Missing selected attempt'
        rows = []
        for line in log.splitlines():
            if '[CART_IMPACT_SAMPLE] ' not in line:
                continue
            row = fields(line.split('[CART_IMPACT_SAMPLE] ', 1)[1])
            if row.get('case') != name:
                continue
            assert math.isfinite(float(row['wall'])), 'Nonfinite native state clock'
            if not start <= float(row['wall']) < start + 12500:
                continue
            for key in BOOLS:
                assert row.get(key) in ('true', 'false'), 'Missing/invalid boolean ' + key
                row[key] = row[key] == 'true'
            for key in NUMBERS:
                row[key] = float(row[key])
                assert math.isfinite(row[key]), 'Nonfinite ' + key
            assert abs(row['wall'] - start - row['elapsed']) < 5, 'Misaligned sample clock'
            assert row.get('state') and row.get('action'), 'Missing native state'
            ids = [] if row.get('cargoIds') == 'empty' else row['cargoIds'].split(',')
            assert ids == sorted(set(ids)) and all(v == str(int(v)) and int(v) >= 0 for v in ids), 'Invalid cargo identities'
            rows.append(row)
        assert len(rows) >= 250 and rows[0]['elapsed'] < 300 and rows[-1]['elapsed'] >= 11700, 'Incomplete native state window'
        assert all(0 < b['wall']-a['wall'] <= 150 for a, b in zip(rows, rows[1:])), 'Native state coverage gap'
        item = rows[0]['id']
        assert item >= 0 and item.is_integer() and all(r['id'] == item for r in rows), 'Tracked cart identity changed'
        cargo = rows[0]['cargo']
        assert (cargo > 0) == ('-full-' in name) and all(abs(r['cargo']-cargo) < .001 for r in rows), 'Cargo changed'
        assert (rows[0]['cargoIds'] != 'empty') == ('-full-' in name) and all(r['cargoIds'] == rows[0]['cargoIds'] for r in rows), 'Cargo identities changed'
        assert any(r['sprint'] and r['action'] == 'sprint' for r in rows if 1100 <= r['elapsed'] < 2000), 'No actual Sprint approach'
        guarded = name.endswith('sprint-wall')
        protected = [r for r in rows if r['state'] in PROTECTED]
        events = [fields(line.split('[CART_IMPACT_EVENT] ', 1)[1]) for line in log.splitlines()
                  if '[CART_IMPACT_EVENT] ' in line and fields(line.split('[CART_IMPACT_EVENT] ', 1)[1]).get('case') == name]
        drop = None
        if guarded:
            assert not events and not protected, 'Guarded wall unexpectedly entered native impact'
            assert all(r['enabled'] for r in rows), 'Guarded wall lost steering'
            quiet = [r for r in rows if 5000 <= r['elapsed'] < 5800]
            assert len(quiet) >= 15 and max(math.hypot(r['x']-quiet[0]['x'], r['y']-quiet[0]['y']) for r in quiet) < .002, 'Sprint wall does not settle'
            assert all(abs(r['stepX'])+abs(r['stepY'])+abs(r['pace']) < 1e-6 and r['brace'] > .99 for r in quiet), 'Missing hard-contact stance'
            layouts = [fields(line.split('[CART_COLLISION_LAYOUT] ', 1)[1]) for line in log.splitlines() if '[CART_COLLISION_LAYOUT] ' in line]
            layout = [r for r in layouts if r.get('case') == name][-1]
            wall_x = float(layout['wallX'])
            assert math.isfinite(wall_x) and rows[0]['x']-quiet[-1]['x'] > 2 and 1 < quiet[-1]['x']-wall_x < 1.85, 'No measured approach to wall envelope'
            assert max(abs(math.remainder(r['itemPhase']-quiet[0]['itemPhase'], 2*math.pi)) for r in quiet) < 1e-4, 'Blocked wheel phase moves'
        else:
            assert len(events) == 1 and events[0].get('source') == 'native-action-event', 'Missing explicit collision-event provenance'
            event = float(events[0]['wall'])
            assert math.isfinite(event) and 2000 <= event-start < 2500, 'Invalid collision-event clock'
            event_elapsed = float(events[0]['elapsed'])
            assert math.isfinite(event_elapsed) and abs(event-start-event_elapsed) < 5, 'Misaligned collision-event clock'
            stops = [fields(line.split('[WOOD_RAMP_EVENT] ', 1)[1]) for line in log.splitlines()
                     if '[WOOD_RAMP_EVENT] ' in line and fields(line.split('[WOOD_RAMP_EVENT] ', 1)[1]).get('case') == name]
            assert any(r.get('gait') == r.get('drive') == '0' and math.isfinite(float(r['elapsed']))
                       and abs(float(r['elapsed'])-event_elapsed) < 5 for r in stops), 'Missing immediate native input stop'
            assert any(r['state'] == 'CollideWithWallState' for r in protected), 'Collision animation not observed'
            assert any(r['state'] == 'PlayerGetUpState' and r['getup'] for r in protected), 'Native getup not observed'
            phases = [r['state'] for i, r in enumerate(protected) if i == 0 or r['state'] != protected[i-1]['state']]
            assert phases == ['CollideWithWallState', 'PlayerGetUpState'], 'Wrong native collision/getup order'
            assert all(r['state'] in PROTECTED for r in rows if protected[0]['wall'] <= r['wall'] <= protected[-1]['wall']), 'Discontinuous protected episode'
            assert event <= protected[0]['wall'] <= event + 500 and protected[-1]['wall'] <= event + 4000, 'Unbounded native recovery'
            dropped = [r for r in rows if r['worldCount'] == 1 and r['worldExact']]
            assert dropped, 'Cart never released into world'
            drop = dropped[0]['wall']
            assert event <= drop <= min(event, protected[0]['wall']) + 100, 'Cart release exceeds 100ms'
            for r in rows:
                if r['wall'] >= drop or r['state'] in PROTECTED:
                    assert not any(r[k] for k in ('enabled', 'steering', 'pivot', 'brake')), 'Cart controller retained ownership after release'
                    assert max(abs(r[k]) for k in ('stepX', 'stepY', 'pace')) < 1e-6, 'Cart variables not reset'
                if r['wall'] >= protected[-1]['wall'] + 500:
                    assert not any(r[k] for k in ('ignore', 'hit', 'knocked', 'getup', 'ragdoll')), 'Native control did not recover within 500ms'
                if r['wall'] >= event + 100:
                    assert not r['run'] and not r['sprint'], 'Native input continued after collision event'
            idle = [r for r in rows if protected[-1]['wall']+500 <= r['wall'] and r['elapsed'] < 6900]
            assert len(idle) >= 15 and all(r['action'] == 'idle' for r in idle), 'Missing bare idle recovery'
            assert max(math.hypot(r['x']-idle[0]['x'], r['y']-idle[0]['y']) for r in idle) < .002, 'Actor moved before recovery walk'
        for r in rows:
            if drop is None or r['wall'] < drop:
                assert r['primary'] == r['secondary'] == item and r['inventoryCount'] == 1 and r['inInventory'], 'Exact held cart ownership changed'
                assert r['worldCount'] == r['woodCount'] == 0 and r['worldId'] == -1 and not r['worldExact'] and not r['worldPersistent'], 'Held cart has world ownership'
            else:
                assert r['primary'] == r['secondary'] == -1 and r['inventoryCount'] == 0 and not r['inInventory'], 'Released cart still held or in inventory'
                assert r['worldCount'] == r['woodCount'] == 1 and r['worldId'] == item and r['worldExact'] and r['worldPersistent'], 'Released cart lost exact persistent world ownership'
                assert max(abs(r[k]-dropped[0][k]) for k in ('worldX', 'worldY', 'worldZ', 'rotation')) < 1e-4, 'Dropped world cart moved'
        recoil = emergency_recoil(rows, drop) if require_recoil and not guarded else None
        scene_tail = [r for r in tail if start <= r['wallTimeMillis'] < start + 12000]
        times = [r['wallTimeMillis'] for r in scene_tail]
        assert times == sorted(times) and times, 'Missing ordered render poses'
        for r in rows:
            covered(times, r['wall'], 'Missing rendered native phase')
        for r in scene_tail:
            assert BONEMAP <= r['bones'].keys(), 'Missing required native bones'
            assert all(len(m) == 16 and all(type(v) in (int, float) and math.isfinite(v) for v in m) for m in r['bones'].values()), 'Invalid native pose matrix'
            assert r['tracks'] and all(isinstance(t.get('name'), str) and type(t.get('weight')) in (float, int) and math.isfinite(t['weight']) for t in r['tracks']), 'Invalid native tracks'
            if drop is not None and r['wallTimeMillis'] >= drop+100:
                assert r.get('cartModel') is False and r.get('cartModelCount') == 0, 'Held cart model survived release'
        scene_world = []
        settle = None
        measured_settle = None
        if not guarded:
            impact_poses = [r for r in scene_tail if event <= r['wallTimeMillis'] < event + 2000]
            assert any(t['name'] == 'Bob_SprintIntoWall' and t['weight'] > .2 for r in impact_poses for t in r['tracks']), 'Missing native impact clip'
            scene_world = [r for r in world if start <= r['wallTimeMillis'] < start + 12000]
            assert scene_world, 'Missing released world render'
            for r in scene_world:
                assert r['itemId'] == item and r['renderStatus'] == 'Ready' and r.get('transitionHidden') is not True, 'Wrong or hidden released world render'
                assert r['matrixOrder'] == 'column-major', 'Unknown world matrix order'
                assert len(r['transform']) == 16 and len(r['angle']) == 3, 'Invalid world render matrix/angle'
                assert all(type(v) in (int, float) and math.isfinite(v) for v in r['transform'] + r['angle'] + [r[k] for k in ('x', 'y', 'z', 'alpha')]), 'Nonfinite world render pose'
                assert r['alpha'] > 0 and r['wallTimeMillis'] >= drop-100, 'World render invisible or predates release'
                assert max(abs(r[k]-scene_world[0][k]) for k in ('x', 'y', 'z')) < .001, 'World render moved with actor'
                assert max(abs(r[k]-dropped[0]['world'+k.upper()]) for k in ('x', 'y', 'z')) < .05, 'World cart floats away from drop location'
            world_times = [r['wallTimeMillis'] for r in scene_world]
            assert world_times == sorted(world_times), 'Unordered world render poses'
            assert all(b-a <= 150 for a, b in zip(world_times, world_times[1:])), 'World render coverage gap'
            for r in dropped:
                covered(world_times, r['wall'], 'Missing rendered released phase')
            # World ownership and renderer anchors stay fixed during the short cart-only settle.
            # Euler folding changes representation, so compare composed axle/handle world points.
            settled = [r for r in scene_world if r['wallTimeMillis'] >= drop+SETTLE_MS]
            assert settled, 'Missing settled world mesh'
            reference = world_cart_points(settled[0])
            for r in settled:
                points = world_cart_points(r)
                assert max(abs(a-b) for name in CART_POINTS for a, b in zip(points[name], reference[name])) < .001, 'World cart mesh leapt during recovery'
            settle = settle_diagnostics(profile, start, drop, scene_world)
            if require_settle:
                measured_settle = actual_settle(profile, start, item)
        reverse = [r for r in rows if 7500 <= r['elapsed'] <= 9400]
        assert reverse[-1]['x']-reverse[0]['x'] > .2, 'Native walk/control did not restore movement'
        active = [r for r in rows if 1000 <= r['elapsed'] < 1900 or guarded and 7800 <= r['elapsed'] < 9200]
        scene_grip = [r for r in grip if start <= r['wallTimeMillis'] < start + 12000]
        active_grip = [r for r in scene_grip if 1000 <= r['wallTimeMillis']-start < 1900 or guarded and 7800 <= r['wallTimeMillis']-start < 9200]
        assert active_grip and all(r.get('result') is True and r.get('threw') is False for r in active_grip), 'Grip fails during active movement'
        assert all(r.get('threw') is False for r in scene_grip), 'Grip probe exception'
        if drop is not None:
            assert all(r.get('result') is False for r in scene_grip if r['wallTimeMillis'] >= drop+100), 'Grip modifier applied after release'
        good_times = sorted(r['wallTimeMillis'] for r in active_grip)
        for r in active:
            assert r['enabled'] and r['pivot'], 'Expected active control missing'
            covered(good_times, r['wall'], 'Grip did not cover approach/recovery')
        wheel_frames = [r for r in wheel if r['event'] == 'draw' and start <= r['wallTimeMillis'] < start+12000]
        active_wheel = [r for r in wheel_frames if 1000 <= r['wallTimeMillis']-start < 1900 or guarded and 7800 <= r['wallTimeMillis']-start < 9200]
        assert active_wheel and all(math.isfinite(float(r[k])) for r in active_wheel for k in ('phase', 'wheelX', 'wheelY', 'wheelZ', 'contactZ')), 'Invalid active wheel pose'
        if drop is not None:
            assert not any(r['wallTimeMillis'] >= drop+100 for r in wheel_frames), 'Held wheel rendered after release'
        wheel_times = sorted(r['wallTimeMillis'] for r in active_wheel)
        for r in active:
            covered(wheel_times, r['wall'], 'Missing split wheel render coverage')
        summaries.append(dict(case=name, samples=len(rows), protectedSamples=len(protected),
                              protectedStates=sorted({r['state'] for r in protected}), renderSamples=len(scene_tail),
                              gripSamples=len(scene_grip), worldRenderSamples=len(scene_world),
                              emergencySettle=settle,
                              actualDrawSettle=measured_settle,
                              emergencyRecoil=recoil,
                              worldWheelFloorMaxOffset=None if guarded else max(abs(world_wheel_floor(r)-dropped[0]['worldZ']) for r in scene_world),
                              releaseLatencyMs=None if guarded else drop-event,
                              reverseTravel=reverse[-1]['x']-reverse[0]['x'],
                              eventSource='none' if guarded else 'native-action-event'))
    natural = analyze_natural(profile, log, tail, complete) if require_natural else None
    return dict(functionalPass=True, failures=[], cases=summaries, naturalImpact=natural,
                limits=['Native event scenes inject collideWithWall while actually Sprinting; they do not prove a natural impact trigger.',
                        'World wheel-floor offset is diagnostic until calibrated against native stock world rendering and video.',
                        'Body/cloth clearance and visual animation quality remain separate diagnostics.'])

NATURAL_CONTROLS = ('natural-run-wall', 'natural-sprint-wall')
NATIVE_BOOLEANS = ('watch', 'actor', 'local', 'run', 'sprint', 'ignore', 'getup', 'hit',
                   'knocked', 'ragdoll', 'collidedN', 'collidedS', 'collidedE', 'collidedW', 'collidedDoor')
NATIVE_NUMBERS = ('timeMs', 'primary', 'secondary', 'wallType', 'naturalEvents', 'injectedEvents', 'otherEvents')
COUNTERS = ('naturalEvents', 'injectedEvents', 'otherEvents')


def natural_row(row, token=False):
    row = dict(row)
    for key in NATIVE_BOOLEANS:
        if token:
            assert row.get(key) in ('true', 'false'), 'Invalid native boolean ' + key
            row[key] = row[key] == 'true'
        else:
            assert type(row.get(key)) is bool, 'Invalid receipt boolean ' + key
    for key in NATIVE_NUMBERS:
        assert not isinstance(row.get(key), bool), 'Invalid native number ' + key
        row[key] = float(row[key])
        assert math.isfinite(row[key]) and row[key].is_integer(), 'Invalid native number ' + key
    assert all(row[k] >= 0 for k in COUNTERS), 'Negative event counter'
    assert row['watch'] and row['actor'] and row['local'], 'Wrong native observation actor/watch'
    assert row.get('state') and row.get('action') and row.get('dir') and row.get('origin'), 'Incomplete native observation'
    return row


def native_receipts(log):
    receipts = []
    for order, line in enumerate(log.splitlines()):
        if '[CART_NATURAL_HIT] ' in line:
            row = json.loads(line.split('[CART_NATURAL_HIT] ', 1)[1])
            assert row.get('kind') in ('watch', 'event'), 'Unknown native receipt'
            # A disabled watch is a boundary, not an observation of a live actor.
            if row.get('kind') == 'watch' and row.get('watch') is False:
                assert type(row.get('timeMs')) in (int, float) and math.isfinite(row['timeMs']), 'Invalid watch end'
            else:
                row = natural_row(row)
            row['_logOrder'] = order
            receipts.append(row)
    assert receipts and all(a['timeMs'] <= b['timeMs'] for a, b in zip(receipts, receipts[1:])), 'Missing/ordered provenance receipts'
    return receipts


def observation_window(receipts, rows, start, end):
    starts = [r for r in receipts if r['kind'] == 'watch' and r.get('watch') is True and r['timeMs'] <= start]
    assert starts and 0 <= start-starts[-1]['timeMs'] <= 5000, 'Missing bounded active watch'
    watch = starts[-1]
    assert all(watch[k] == 0 for k in COUNTERS) and watch['origin'] == 'watch-control', 'Watch counters not reset'
    for key in ('movingObjectSha256', 'actionContextSha256'):
        assert re.fullmatch('[a-f0-9]{64}', watch.get(key, '')), 'Missing watched class fingerprint'
    boundaries = [r for r in receipts if r['kind'] == 'watch' and r['_logOrder'] > watch['_logOrder']]
    boundary = boundaries[0] if boundaries else None
    assert boundary is None or boundary['timeMs'] >= end, 'Native watch ended during observation'
    events = [r for r in receipts if r['kind'] == 'event' and watch['_logOrder'] < r['_logOrder']
              and (boundary is None or r['_logOrder'] < boundary['_logOrder'])]
    # A watch spans setup as well as the bounded capture. An event in setup cannot be hidden.
    assert all(start <= e['timeMs'] <= end for e in events), 'Impact outside captured observation'
    counts = dict.fromkeys(COUNTERS, 0)
    origins = {'native-checkHitWall': 'naturalEvents', 'injected-cartLabWallEvent': 'injectedEvents', 'other': 'otherEvents'}
    for event in events:
        assert event.get('event') == 'collideWithWall' and event.get('origin') in origins, 'Invalid wall event provenance'
        stack = event.get('stack', '').split(';')
        native = 'zombie.iso.IsoMovingObject.checkHitWall' in stack
        injected = any(s.endswith('.Main.wallEvent') or s == 'Main.wallEvent' for s in stack)
        origin = event['origin']
        assert (origin == 'injected-cartLabWallEvent') == injected, 'Injected stack provenance mismatch'
        assert (origin == 'native-checkHitWall') == (native and not injected), 'Natural stack provenance mismatch'
        counts[origins[origin]] += 1
        assert all(event[k] == counts[k] for k in COUNTERS), 'Event receipt counter mismatch'
    for row in rows:
        # Clock equality is resolved by emitted log order, never by relaxing counters.
        elapsed_events = [e for e in events if (e['timeMs'], e['_logOrder']) < (row['timeMs'], row['_logOrder'])]
        for origin, key in origins.items():
            assert row[key] == sum(e['origin'] == origin for e in elapsed_events), 'Sample/receipt provenance mismatch'
        expected_origin = elapsed_events[-1]['origin'] if elapsed_events else 'none'
        assert row['origin'] == expected_origin, 'Sample origin mismatch'
    return events, {k: watch[k] for k in ('movingObjectSha256', 'actionContextSha256')}


def observation_samples(log, marker, key, name, start, duration):
    rows = []
    for order, line in enumerate(log.splitlines()):
        if marker not in line:
            continue
        raw = fields(line.split(marker, 1)[1])
        if raw.get(key) != name:
            continue
        row = natural_row(raw, token=True)
        row['_logOrder'] = order
        for number in ('wall', 'elapsed'):
            row[number] = float(row[number])
            assert math.isfinite(row[number]), 'Nonfinite natural sample clock'
        assert start <= row['wall'] <= start+duration+250, 'Natural sample outside bounded window'
        assert abs(row['wall']-start-row['elapsed']) < 5 and abs(row['timeMs']-row['wall']) <= 100, 'Misaligned natural clock'
        rows.append(row)
    assert len(rows) >= duration/60 and rows[0]['elapsed'] <= 150 and duration-200 <= rows[-1]['elapsed'] <= duration+250, 'Incomplete natural observation window'
    assert all(0 < b['wall']-a['wall'] <= 150 and 0 < b['timeMs']-a['timeMs'] <= 150 for a, b in zip(rows, rows[1:])), 'Natural sample coverage gap'
    return rows


def natural_render(tail, rows, start, end):
    poses = [r for r in tail if start <= r['wallTimeMillis'] <= end]
    times = [r['wallTimeMillis'] for r in poses]
    assert times and times == sorted(times) and all(0 < b-a <= 150 for a, b in zip(times, times[1:])), 'Natural render coverage gap'
    for row in rows:
        covered(times, row['wall'], 'Missing natural rendered phase')
    for pose in poses:
        assert BONEMAP <= pose.get('bones', {}).keys(), 'Missing natural render bones'
        assert all(len(m) == 16 and all(type(v) in (int, float) and math.isfinite(v) for v in m) for m in pose['bones'].values()), 'Invalid natural render bones'
        assert pose.get('tracks') and all(isinstance(t.get('name'), str) and type(t.get('weight')) in (int, float) and math.isfinite(t['weight']) for t in pose['tracks']), 'Invalid natural rendered tracks'
        assert pose.get('cartModel') is False and pose.get('cartModelCount') == 0, 'Bare control renders a held cart'
    return poses


def analyze_natural(profile, log, tail, complete):
    receipts = native_receipts(log)
    starts = [fields(line.split('[CART_NATURAL_CONTROL] START ', 1)[1]) for line in log.splitlines() if '[CART_NATURAL_CONTROL] START ' in line]
    finishes = [fields(line.split('[CART_NATURAL_CONTROL] COMPLETE ', 1)[1]) for line in log.splitlines() if '[CART_NATURAL_CONTROL] COMPLETE ' in line]
    assert [r.get('spec') for r in starts] == list(NATURAL_CONTROLS) == [r.get('spec') for r in finishes], 'Missing/reordered natural controls'
    controls = []
    for begin, finish in zip(starts, finishes):
        name, start = begin['spec'], float(begin['wall'])
        assert math.isfinite(start) and finish['wall'] == begin['wall'], 'Wrong completed natural attempt'
        assert finish.get('file') not in (None, 'nil', 'none', '') and float(finish['frames']) > 0 and math.isfinite(float(finish['seconds'])) and float(finish['seconds']) >= 7.5, 'Incomplete natural control video'
        rows = observation_samples(log, '[CART_NATURAL_SAMPLE] ', 'spec', name, start, 8000)
        for row in rows:
            for coord in ('x', 'y'):
                row[coord] = float(row[coord])
                assert math.isfinite(row[coord]), 'Nonfinite natural control position'
        events, fingerprints = observation_window(receipts, rows, start, rows[-1]['timeMs'])
        assert all(r['primary'] == r['secondary'] == -1 for r in rows), 'Natural control is not bare hands'
        wall_x, initial_x = float(begin['wallX']), float(begin['x'])
        assert all(math.isfinite(v) for v in (wall_x, initial_x)) and initial_x-wall_x > 2 and initial_x-rows[-1]['x'] > 1, 'No measured bare approach to wall'
        sprint = name == 'natural-sprint-wall'
        gait = 'sprint' if sprint else 'run'
        approach = [r for r in rows if r[gait] and r['action'] == gait and r['dir'] == 'W']
        assert len(approach) >= 2, 'No actual bare '+gait+' approach'
        stops = [fields(line.split('[CART_NATURAL_CONTROL] INPUT_STOP ', 1)[1]) for line in log.splitlines() if '[CART_NATURAL_CONTROL] INPUT_STOP ' in line]
        stops = [r for r in stops if r.get('spec') == name]
        assert len(stops) == 1, 'Missing/repeated natural input stop'
        stop = float(stops[0]['wall'])
        assert math.isfinite(stop) and abs(stop-start-float(stops[0]['elapsed'])) < 5, 'Invalid natural input stop clock'
        protected = [r for r in rows if r['state'] in PROTECTED]
        poses = natural_render(tail, rows, start, rows[-1]['wall'])
        if sprint:
            assert len(events) == 1 and events[0]['origin'] == 'native-checkHitWall', 'Missing exact natural sprint event'
            event = events[0]
            assert event['sprint'] and event['dir'] == 'W' and event['collidedW'] and int(event['wallType']) & 4, 'Natural event lacks native sprint/W wall collision'
            assert event['primary'] == event['secondary'] == -1, 'Natural event actor held an item'
            assert approach[0]['timeMs'] < event['timeMs'] and event['timeMs'] <= stop <= event['timeMs']+150, 'Natural event/input stop order'
            phases = [r['state'] for i, r in enumerate(protected) if i == 0 or r['state'] != protected[i-1]['state']]
            assert phases == ['CollideWithWallState', 'PlayerGetUpState'], 'Missing/incorrect natural collision/getup episode'
            assert all(r['state'] in PROTECTED for r in rows if protected[0]['wall'] <= r['wall'] <= protected[-1]['wall']), 'Discontinuous natural recovery'
            assert event['timeMs']-100 <= protected[0]['wall'] <= event['timeMs']+500 and protected[-1]['wall'] <= event['timeMs']+5000, 'Unbounded natural recovery'
            for state, clip in (('CollideWithWallState', 'Bob_SprintIntoWall'), ('PlayerGetUpState', 'Bob_GetUp_Back')):
                phase = [r for r in protected if r['state'] == state]
                rendered = [p for p in poses if phase[0]['wall']-150 <= p['wallTimeMillis'] <= phase[-1]['wall']+150]
                assert any(t['name'] == clip and t['weight'] > .2 for p in rendered for t in p['tracks']), 'Missing natural rendered '+clip
        else:
            assert not events and not protected and not any(r['sprint'] for r in rows), 'Bare Run unexpectedly fell/impacted'
            assert any(r['collidedW'] and r['dir'] == 'W' and int(r['wallType']) & 4 for r in rows), 'Bare Run never reached directional wall collision'
            assert 4000 <= stop-start <= 4150, 'Bare Run input stop is not bounded'
        quiet = [r for r in rows if r['elapsed'] >= 7000]
        assert quiet and all(r['action'] == 'idle' and r['state'] not in PROTECTED and not any(r[k] for k in ('run', 'sprint', 'ignore', 'getup', 'ragdoll', 'hit', 'knocked')) for r in quiet), 'Natural control failed final idle recovery'
        assert max(math.hypot(r['x']-quiet[0]['x'], r['y']-quiet[0]['y']) for r in quiet) < .02, 'Natural idle control moved'
        controls.append(dict(control=name, samples=len(rows), renderSamples=len(poses), eventSource=events[0]['origin'] if events else 'none', protectedStates=sorted({r['state'] for r in protected}), fingerprints=fingerprints))
    cart = []
    for name, start in complete:
        start = int(start)
        rows = observation_samples(log, '[CART_NATURAL_CART] ', 'case', name, start, 12000)
        events, fingerprints = observation_window(receipts, rows, start, rows[-1]['timeMs'])
        ownership_samples = [fields(line.split('[CART_IMPACT_SAMPLE] ', 1)[1]) for line in log.splitlines()
                             if '[CART_IMPACT_SAMPLE] ' in line]
        ownership_samples = {float(r['wall']): r for r in ownership_samples if r.get('case') == name}
        shared = ('state', 'action', 'run', 'sprint', 'ignore', 'getup', 'hit', 'knocked', 'ragdoll', 'primary', 'secondary')
        for row in rows:
            owner = ownership_samples.get(row['wall'])
            assert owner is not None, 'Natural cart observation lacks matched ownership sample'
            for key in shared:
                expected = owner[key] == 'true' if key in NATIVE_BOOLEANS else float(owner[key]) if key in ('primary', 'secondary') else owner[key]
                assert row[key] == expected, 'Natural cart/ownership state mismatch: '+key
        guarded = name.endswith('sprint-wall')
        if guarded:
            assert not events and all(r['state'] not in PROTECTED for r in rows), 'Guarded cart unexpectedly received native wall event'
            quiet = [r for r in rows if 5000 <= r['elapsed'] < 5800]
            # cartBlocked resets on zero root displacement; Sprint may remain requested.
            # Stationary brace/pace/wheel and exact ownership gates above prove the stop.
            assert quiet and all(r.get('clear') == 'true' and r.get('recovering') == 'false' and not any(r[k] for k in ('collidedN', 'collidedS', 'collidedE', 'collidedW', 'collidedDoor')) for r in quiet), 'Cart frontal guard did not stop before body contact'
            assert all(r.get('footprint', '').startswith('front=') and math.isfinite(float(r['footprint'].split('=', 1)[1])) and float(r['footprint'].split('=', 1)[1]) > 0 for r in quiet), 'Missing front footprint evidence'
            assert any(r.get('drive') == '1' and r['sprint'] and r['action'] == 'sprint' for r in rows if 1000 <= r['elapsed'] < 2000), 'Missing actual cart forward sprint'
            assert any(r.get('drive') == '4' and r['state'] == 'PlayerMovementState' and r['action'] == 'movement' and not r['run'] and not r['sprint'] for r in rows if 7500 <= r['elapsed'] <= 9400), 'Missing cart reverse recovery'
        else:
            assert len(events) == 1 and events[0]['origin'] == 'injected-cartLabWallEvent', 'Cart release was not explicitly injected'
            injected = [fields(line.split('[CART_IMPACT_EVENT] ', 1)[1]) for line in log.splitlines() if '[CART_IMPACT_EVENT] ' in line]
            injected = [r for r in injected if r.get('case') == name]
            assert len(injected) == 1 and abs(events[0]['timeMs']-float(injected[0]['wall'])) <= 100, 'Injected release receipt does not match action event'
        cart.append(dict(case=name, samples=len(rows), eventSource='none' if guarded else 'injected-cartLabWallEvent', fingerprints=fingerprints))
    return dict(functionalPass=True, controls=controls, cases=cart,
                scope='Bare vanilla Run/Sprint wall controls, cart frontal guard, and explicitly injected cart release; selected cases only.')
