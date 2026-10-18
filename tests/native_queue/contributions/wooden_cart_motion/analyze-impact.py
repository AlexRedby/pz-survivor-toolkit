"""Strict native collision-event recovery proof; physical contact and visual quality are separate."""
import bisect
import csv
import json
import math
from pathlib import Path
import re

CASES = [f'{sex}-{load}-{spec}' for sex in ('male', 'female')
         for load in ('empty', 'full') for spec in ('sprint-wall', 'native-impact')]
PROTECTED = {'CollideWithWallState', 'PlayerGetUpState'}
BOOLS = ('run', 'sprint', 'enabled', 'steering', 'hit', 'knocked', 'getup', 'ragdoll', 'ignore', 'pivot', 'brake')
NUMBERS = ('wall', 'elapsed', 'x', 'y', 'stepX', 'stepY', 'pace', 'brace', 'id', 'secondary', 'cargo', 'itemPhase')
BONEMAP = {'Bip01_Spine','Bip01_L_Hand','Bip01_R_Hand','Bip01_L_Foot','Bip01_R_Foot'}


def fields(text):
    return dict(token.split('=', 1) for token in text.split() if '=' in token)


def read_rows(path):
    assert path.is_file(), 'Missing render evidence: ' + str(path)
    rows = [json.loads(line) for line in path.read_text().splitlines() if line.strip()]
    assert rows, 'Empty render evidence: ' + str(path)
    return rows


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
    with (profile / 'wood-wheel-native.csv').open() as stream:
        wheel = list(csv.DictReader(stream))
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
            if not start <= float(row['wall']) < start + 12500: continue
            for key in BOOLS:
                assert row.get(key) in ('true', 'false'), 'Missing/invalid boolean ' + key
                row[key] = row[key] == 'true'
            for key in NUMBERS:
                row[key] = float(row[key])
                assert math.isfinite(row[key]), 'Nonfinite ' + key
            assert abs(row['wall'] - start - row['elapsed']) < 5, 'Misaligned sample clock'
            assert row.get('state') and row.get('action'), 'Missing native state'
            rows.append(row)
        assert len(rows) >= 250 and rows[0]['elapsed'] < 300 and rows[-1]['elapsed'] >= 11700, 'Incomplete native state window'
        assert all(0 < b['wall']-a['wall'] <= 150 for a,b in zip(rows, rows[1:])), 'Native state coverage gap'
        item = rows[0]['id']
        assert item >= 0 and all(r['id'] == r['secondary'] == item for r in rows), 'Cart ownership changed'
        cargo = rows[0]['cargo']
        assert (cargo > 0) == ('-full-' in name) and all(abs(r['cargo']-cargo) < .001 for r in rows), 'Cargo changed'
        assert any(r['sprint'] and r['action'] == 'sprint' for r in rows if 1100 <= r['elapsed'] < 2000), 'No actual Sprint approach'
        guarded = name.endswith('sprint-wall')
        protected = [r for r in rows if r['state'] in PROTECTED]
        events = [fields(line.split('[CART_IMPACT_EVENT] ',1)[1]) for line in log.splitlines()
                  if '[CART_IMPACT_EVENT] ' in line and fields(line.split('[CART_IMPACT_EVENT] ',1)[1]).get('case') == name]
        if guarded:
            assert not events and not protected, 'Guarded wall unexpectedly entered native impact'
            assert all(r['enabled'] for r in rows), 'Guarded wall lost steering'
            quiet = [r for r in rows if 5000 <= r['elapsed'] < 5800]
            assert len(quiet) >= 15 and max(math.hypot(r['x']-quiet[0]['x'],r['y']-quiet[0]['y']) for r in quiet) < .002, 'Sprint wall does not settle'
            assert all(abs(r['stepX'])+abs(r['stepY'])+abs(r['pace']) < 1e-6 and r['brace'] > .99 for r in quiet), 'Missing hard-contact stance'
            layouts = [fields(line.split('[CART_COLLISION_LAYOUT] ',1)[1]) for line in log.splitlines() if '[CART_COLLISION_LAYOUT] ' in line]
            layout = [r for r in layouts if r.get('case') == name][-1]
            assert rows[0]['x']-quiet[-1]['x'] > 2 and 1 < quiet[-1]['x']-float(layout['wallX']) < 1.85, 'No measured approach to wall envelope'
            assert max(abs(math.remainder(r['itemPhase']-quiet[0]['itemPhase'],2*math.pi)) for r in quiet) < 1e-4, 'Blocked wheel phase moves'
        else:
            assert len(events) == 1 and events[0].get('source') == 'native-action-event', 'Missing explicit collision-event provenance'
            event = float(events[0]['wall'])
            assert any(r['state'] == 'CollideWithWallState' for r in protected), 'Collision animation not observed'
            assert any(r['state'] == 'PlayerGetUpState' and r['getup'] for r in protected), 'Native getup not observed'
            phases = [r['state'] for i,r in enumerate(protected) if i == 0 or r['state'] != protected[i-1]['state']]
            assert phases == ['CollideWithWallState','PlayerGetUpState'], 'Wrong native collision/getup order'
            assert all(r['state'] in PROTECTED for r in rows if protected[0]['wall'] <= r['wall'] <= protected[-1]['wall']), 'Discontinuous protected episode'
            assert event <= protected[0]['wall'] <= event + 500 and protected[-1]['wall'] <= event + 4000, 'Unbounded native recovery'
            for r in protected:
                assert not any(r[k] for k in ('enabled', 'steering', 'pivot', 'brake')), 'Cart controller retained ownership in protected state'
                assert max(abs(r[k]) for k in ('stepX', 'stepY', 'pace')) < 1e-6, 'Cart variables not reset'
            recovered = [r for r in rows if protected[-1]['wall'] < r['wall'] <= protected[-1]['wall'] + 500]
            assert any(r['enabled'] and r['steering'] and r['pivot'] for r in recovered), 'Cart control did not recover within500ms'
        scene_tail = [r for r in tail if start <= r['wallTimeMillis'] < start + 12000]
        times = [r['wallTimeMillis'] for r in scene_tail]
        assert times == sorted(times) and times, 'Missing ordered render poses'
        for r in rows:
            i = bisect.bisect_left(times, r['wall'])
            assert min(abs(t-r['wall']) for t in times[max(0,i-1):i+1]) <= 150, 'Missing rendered native phase'
        for r in scene_tail:
            assert BONEMAP <= r['bones'].keys(), 'Missing required native bones'
            assert all(len(m) == 16 and all(isinstance(v,(int,float)) and math.isfinite(v) for v in m) for m in r['bones'].values()), 'Invalid native pose matrix'
            assert r['tracks'] and all(isinstance(t.get('name'),str) and isinstance(t.get('weight'),(float,int)) and math.isfinite(t['weight']) for t in r['tracks']), 'Invalid native tracks'
        if not guarded:
            impact_poses = [r for r in scene_tail if event <= r['wallTimeMillis'] < event + 2000]
            assert any(t['name'] == 'Bob_SprintIntoWall' and t['weight'] > .2 for r in impact_poses for t in r['tracks']), 'Missing native impact clip'
        reverse = [r for r in rows if 7500 <= r['elapsed'] <= 9400]
        assert reverse[-1]['x']-reverse[0]['x'] > .2, 'Reverse control did not restore movement'
        active = [r for r in rows if 1000 <= r['elapsed'] < 1900 or 7800 <= r['elapsed'] < 9200]
        scene_grip = [r for r in grip if start <= r['wallTimeMillis'] < start + 12000]
        active_grip = [r for r in scene_grip if 1000 <= r['wallTimeMillis']-start < 1900 or 7800 <= r['wallTimeMillis']-start < 9200]
        assert active_grip and all(r.get('result') is True and r.get('threw') is False for r in active_grip), 'Grip fails during active movement'
        good_times = sorted(r['wallTimeMillis'] for r in scene_grip if r.get('result') is True and r.get('threw') is False)
        assert good_times, 'No successful grip samples'
        for r in active:
            assert r['enabled'] and r['pivot'], 'Expected active control missing'
            i = bisect.bisect_left(good_times, r['wall'])
            assert min(abs(t-r['wall']) for t in good_times[max(0,i-1):i+1]) <= 150, 'Grip did not cover approach/recovery'
        assert not any(r.get('threw') is not False for r in scene_grip), 'Grip probe exception'
        wheel_frames = [r for r in wheel if r['event'] == 'draw' and start <= float(r['wallTimeMillis']) < start+12000]
        active_wheel = [r for r in wheel_frames if 1000 <= float(r['wallTimeMillis'])-start < 1900 or 7800 <= float(r['wallTimeMillis'])-start < 9200]
        assert active_wheel and all(math.isfinite(float(r[k])) for r in active_wheel for k in ('phase','wheelX','wheelY','wheelZ','contactZ')), 'Invalid active wheel pose'
        wheel_times = sorted(float(r['wallTimeMillis']) for r in active_wheel)
        for r in active:
            i = bisect.bisect_left(wheel_times,r['wall'])
            assert min(abs(t-r['wall']) for t in wheel_times[max(0,i-1):i+1]) <= 150, 'Missing restored wheel render coverage'
        summaries.append(dict(case=name, samples=len(rows), protectedSamples=len(protected),
                              protectedStates=sorted({r['state'] for r in protected}), renderSamples=len(scene_tail),
                              gripSamples=len(scene_grip), reverseTravel=reverse[-1]['x']-reverse[0]['x'],
                              eventSource='none' if guarded else 'native-action-event'))
    return dict(functionalPass=True, failures=[], cases=summaries,
                limits=['Native event scenes inject collideWithWall while actually Sprinting; they do not prove a natural impact trigger.',
                        'Body/cloth clearance and visual animation quality remain separate diagnostics.'])
