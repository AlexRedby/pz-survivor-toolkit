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


def analyze(profile, text, selected=None):
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
                assert max(abs(a-b) for a, b in zip(r['transform']+r['angle'], scene_world[0]['transform']+scene_world[0]['angle'])) < .001, 'World cart mesh leapt during recovery'
                assert max(abs(r[k]-dropped[0]['world'+k.upper()]) for k in ('x', 'y', 'z')) < .05, 'World cart floats away from drop location'
            world_times = [r['wallTimeMillis'] for r in scene_world]
            assert world_times == sorted(world_times), 'Unordered world render poses'
            assert all(b-a <= 150 for a, b in zip(world_times, world_times[1:])), 'World render coverage gap'
            for r in dropped:
                covered(world_times, r['wall'], 'Missing rendered released phase')
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
                              worldWheelFloorMaxOffset=None if guarded else max(abs(world_wheel_floor(r)-dropped[0]['worldZ']) for r in scene_world),
                              releaseLatencyMs=None if guarded else drop-event,
                              reverseTravel=reverse[-1]['x']-reverse[0]['x'],
                              eventSource='none' if guarded else 'native-action-event'))
    return dict(functionalPass=True, failures=[], cases=summaries,
                limits=['Native event scenes inject collideWithWall while actually Sprinting; they do not prove a natural impact trigger.',
                        'World wheel-floor offset is diagnostic until calibrated against native stock world rendering and video.',
                        'Body/cloth clearance and visual animation quality remain separate diagnostics.'])
