"""Public cart menu, exact ownership, native collision and independent queue-tail evidence."""
import argparse
import json
import math
from pathlib import Path
import re

CASES = ('container-equip', 'wrong-side', 'wall-detour', 'precise-blocked',
         'approach-cancel', 'approach-target-loss', 'approach-tail-success')
SUCCESS = {'container-equip', 'wrong-side', 'wall-detour', 'approach-tail-success'}
TYPES = {'ISWalkToTimedActionF', 'ToolkitWoodCartPickup', 'ISCartEquipAction'}


def verify_calibration(calibration, first, lifecycle):
    prefix='Native production-path calibration: '
    assert 6 <= len(calibration) <= 4096, prefix+'missing bounded evidence'
    assert 0 < calibration[-1]['wall']-calibration[0]['wall'] < 30000 and calibration[-1]['wall'] < first['wall'], prefix+'unbounded timing'
    assert calibration[0]['x']-calibration[-1]['x'] >= .2, prefix+'never moved toward wall'
    rounds={}
    for row in calibration:
        rounds.setdefault(row['round'],[]).append(row)
        assert row['actionType']=='ISWalkToTimedActionF', prefix+'wrong native action'
        if row['started']:
            assert row['nativeTargetX']==row['goalX'] and row['nativeTargetY']==row['goalY'], prefix+'planner clipped target'
    assert list(rounds)==list(range(1,len(rounds)+1)) and len(rounds)<=32, prefix+'missing/reordered rounds'
    previous=None
    for number,rows in rounds.items():
        queued,terminal=rows[0],rows[-1]
        assert [r['event'] for r in rows]==['queued']+['sample']*(len(rows)-2)+['terminal'], prefix+'missing round boundaries'
        assert all(0 < b['wall']-a['wall'] <= 250 for a,b in zip(rows,rows[1:])), prefix+'sampling gap'
        assert terminal['wall']-queued['wall']<4000, prefix+'round timeout'
        assert all(r['goalX']==queued['goalX'] and r['goalY']==queued['goalY'] for r in rows), prefix+'changed round goal'
        assert .002 < queued['x']-queued['goalX'] <= .032 and abs(queued['y']-queued['goalY'])<=.002, prefix+'step exceeded .03'
        if previous:
            assert math.dist((queued['x'],queued['y']),(previous['x'],previous['y']))<=.002 and queued['wall']>=previous['wall'], prefix+'actor relocated between rounds'
        for a,b in zip(rows,rows[1:]):
            assert math.dist((a['x'],a['y']),(b['x'],b['y']))<=8*(b['wall']-a['wall'])/1000+.003, prefix+'actor teleported'
        failed=number==len(rounds)
        distance=math.dist((terminal['x'],terminal['y']),(queued['goalX'],queued['goalY']))
        assert terminal['started'] and terminal['result']==('Failed' if failed else 'Succeeded'), prefix+'wrong native terminal result'
        native=[r for r in lifecycle if queued['wall']<=r['wallTimeMillis']<=terminal['wall'] and r['metaType'] in TYPES]
        assert native and len({r['nativeActionId'] for r in native})==1 and all(r['metaType']=='ISWalkToTimedActionF' and r['phase']=='exit' and r['playerNum']==0 and not r['threw'] for r in native), prefix+'missing/extra native action'
        assert [r['event'] for r in native]==(['start','stop'] if failed else ['start','perform','complete']), prefix+'native lifecycle mismatch'
        if failed:
            assert .002 < distance <= .06, prefix+'failed outside precise arrival'
            stable=[]
            for row in reversed([r for r in rows[1:-1] if r['result']=='Working']):
                if not row['hasPath'] or not .002 < math.dist((row['x'],row['y']),(row['goalX'],row['goalY'])) <= .06 or math.dist((row['x'],row['y']),(terminal['x'],terminal['y']))>.002: break
                stable.append(row)
            assert len(stable)>=3 and stable[0]['wall']-stable[-1]['wall']>=500, prefix+'planner-only/short failure'
        else:
            assert distance<=.002, prefix+'succeeded away from original target'
        previous=terminal
    assert math.dist((first['x'],first['y']),(previous['x'],previous['y']))<=.002, prefix+'actor drift after stop'
    assert first['goalX']==previous['goalX'] and first['goalY']==previous['goalY'], prefix+'measured target changed'


def analyze(text, lifecycle, scenes=None):
    cases=CASES
    if scenes is not None:
        assert scenes and len(set(scenes))==len(scenes) and set(scenes)<=set(CASES), 'Invalid selected approach scenes'
        cases=tuple(name for name in CASES if name in scenes)
    assert '[WOOD_BANK] RUN_STARTED' in text, 'Missing approach run boundary'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[1]
    completed = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    assert len(completed) == len(cases) and {n for n, _ in completed} == set(cases), 'Missing/duplicate approach scenes'
    assert '[WOOD_BANK] FAIL' not in log and re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases='+str(len(cases))+r'(?:\s|$)', log), 'Approach scenario incomplete/failed'
    assert '[CART_APPROACH] CLEANUP_COMPLETE' in log, 'Missing owned fixture cleanup'
    records, calibrations = [], []
    for index, line in enumerate(log.splitlines()):
        match = re.search(r'\[CART_APPROACH_(SAMPLE|EVENT|CALIBRATION)\] (\{.*\})', line)
        if match:
            row = json.loads(match[2])
            assert all(math.isfinite(v) for v in row.values() if type(v) in (int, float)), 'Nonfinite approach evidence'
            row['_order'], row['_sample'] = index, match[1] == 'SAMPLE'
            (calibrations if match[1] == 'CALIBRATION' else records).append(row)
    summaries = []
    for name, stamp in completed:
        start = int(stamp)
        selected = [r for r in records if r['case'] == name and r['start'] == start]
        rows = [r for r in selected if r['_sample']]
        events = [r for r in selected if not r['_sample']]
        expected = ['prepared', 'queued'] + (['cancelRequested'] if name == 'approach-cancel' else ['targetRemoved'] if name == 'approach-target-loss' else []) + ['terminal', 'settled']
        assert [r['event'] for r in events] == expected, 'Missing/reordered approach receipts: ' + name
        event = {r['event']: r for r in events}
        first, queued, terminal, settled = (event[k] for k in ('prepared', 'queued', 'terminal', 'settled'))
        assert len(rows) >= 30 and rows[0]['elapsed'] <= 100 and rows[-1]['wall'] >= settled['wall']-100, 'Missing approach sample window'
        assert all(0 < b['wall']-a['wall'] <= 250 for a, b in zip(rows, rows[1:])), 'Approach sampling gap'
        assert 650 <= queued['elapsed'] <= 1500 and 0 < terminal['wall']-queued['wall'] < 14000 and settled['wall']-terminal['wall'] >= 1000, 'Unbounded approach/cleanup window'
        assert first['cargoWeight'] > 0, 'Missing exact fixture cargo'
        for row in selected:
            assert row['wall']-start == row['elapsed'] and all(row[k] == first[k] for k in ('id', 'cargoID', 'cargoWeight', 'z', 'goalX', 'goalY')), 'Changed cart/cargo/target/level'
            assert all(row[k] in (0, 1) for k in ('inventoryCount', 'worldCount', 'containerCount')), 'Duplicate cart ownership'
            assert row['inventoryCount']+row['worldCount']+row['containerCount']+int(row['removed']) == 1, 'Cart ownership duplicated/lost'
            assert row['primaryID'] in (-1, first['id']) and row['secondaryID'] == row['primaryID'], 'Wrong exact cart hands'
            assert (row['primaryID'] == first['id']) == (row['inventoryCount'] == 1), 'Cart ownership/hand mismatch'
            assert row['route'] == ('inventory-menu' if name == 'container-equip' else 'world-menu'), 'Public pickup route changed'
        assert first['containerCount'] == int(name == 'container-equip') and first['worldCount'] == int(name != 'container-equip') and first['inventoryCount'] == 0, 'Wrong initial source container'
        assert all(math.dist((r['x'],r['y']),(first['x'],first['y'])) <= .002 for r in rows if r['wall'] <= queued['wall']), 'Actor moved before native menu request'
        assert all(math.dist((r['x'],r['y']),(terminal['x'],terminal['y'])) <= .002 for r in rows if r['wall'] >= terminal['wall']), 'Actor moved after native terminal state'
        for a, b in zip(rows, rows[1:]):
            assert math.dist((a['x'], a['y']), (b['x'], b['y'])) <= 8*(b['wall']-a['wall'])/1000+.03, 'Actor teleported during native approach'
        success = name in SUCCESS
        for row in [terminal, settled] + [r for r in rows if r['wall'] >= terminal['wall']]:
            assert row['nativeActions'] == row['luaActions'] == 0 and not row['hasPath'], 'Native queue/path leaked'
            assert row['inventoryCount'] == int(success) and row['primaryID'] == (first['id'] if success else -1), 'Terminal exact ownership differs'
            assert row['worldCount'] == int(not success and name != 'approach-target-loss') and row['containerCount'] == 0, 'Terminal source ownership differs'
        assert not any(settled[k] for k in ('active', 'recovering', 'rendered', 'ToolkitWoodCartAction')), 'Presentation cleanup leaked'
        native = [r for r in lifecycle if start <= r['wallTimeMillis'] <= settled['wall'] and r['metaType'] in TYPES]
        groups = {}
        for row in native:
            assert row['phase'] == 'exit' and row['playerNum'] == 0 and not row['threw'], 'Invalid native lifecycle receipt'
            groups.setdefault(row['nativeActionId'], []).append(row)
        groups = sorted(groups.values(), key=lambda group: (group[0]['wallTimeMillis'], native.index(group[0])))
        expected_types = ['ISCartEquipAction'] if name == 'container-equip' else ['ISWalkToTimedActionF'] + (['ToolkitWoodCartPickup'] if success else [])
        if name in ('approach-target-loss', 'approach-tail-success'):
            expected_types.append('ISWalkToTimedActionF')
        assert [g[0]['metaType'] for g in groups] == expected_types, 'Missing/extra native pickup or independent tail'
        for i, group in enumerate(groups):
            stopped = i == 0 and name in ('precise-blocked', 'approach-cancel')
            assert [r['event'] for r in group] == (['start', 'stop'] if stopped else ['start', 'perform', 'complete']), 'Native lifecycle did not stop/complete exactly once'
            assert all(r['metaType'] == group[0]['metaType'] for r in group), 'Native action identity reused'
            assert queued['wall'] <= group[0]['wallTimeMillis'] < group[-1]['wallTimeMillis'] <= terminal['wall'], 'Native action outside queue boundaries'
        approach_rows = [r for r in rows if queued['wall'] < r['wall'] < terminal['wall'] and r['actionType'] == 'ISWalkToTimedActionF']
        if name != 'container-equip':
            assert len(approach_rows) >= 3 and any(r['hasPath'] for r in approach_rows), 'Native approach never became active'
        if name == 'precise-blocked':
            calibration = [r for r in calibrations if r['case'] == name and r['start'] == start]
            verify_calibration(calibration,first,lifecycle)
            assert terminal['approachResult'] == 'Failed' and .002 < math.dist((terminal['x'], terminal['y']), (first['goalX'], first['goalY'])) <= .06, 'Blocked final alignment was not exercised'
            close = [r for r in approach_rows if .002 < math.dist((r['x'], r['y']), (first['goalX'], first['goalY'])) <= .06]
            assert len(close) >= 3 and close[-1]['wall']-close[0]['wall'] >= 300, 'Missing real blocked precise-arrival window'
            assert all(r['x'] >= first['wallX'] for r in selected), 'Native wall collision crossed wall'
        elif name == 'wall-detour':
            crossing = first['wallX']+1
            assert first['startX'] < crossing < first['goalX'], 'Detour wall did not divide start/target'
            assert any(r['y'] < first['wallY']-1 or r['y'] > first['wallY']+2 for r in approach_rows), 'Native path did not route around real wall'
        elif name == 'wrong-side':
            handle=(first['goalX']-first['cartX'], first['goalY']-first['cartY'])
            actor=(first['startX']-first['cartX'], first['startY']-first['cartY'])
            assert sum(a*b for a,b in zip(handle,actor)) < -.04, 'Wrong-side fixture did not start opposite the handles'
        if name in ('approach-target-loss', 'approach-cancel'):
            request = event['targetRemoved' if name.endswith('target-loss') else 'cancelRequested']
            assert request['actionType'] == 'ISWalkToTimedActionF' and request['hasPath'] and request['luaActions'] >= 2, 'Interruption missed approach/queued tail'
            assert request['worldCount'] == 1 and not request['removed'], 'Target missing before requested loss/cancel'
            assert groups[0][-1]['wallTimeMillis'] >= request['wall'], 'Native approach ended before interruption'
            if name == 'approach-target-loss':
                assert terminal['removed'] and terminal['tailResult'] == 'Succeeded', 'Lost target consumed independent tail'
            else:
                assert terminal['tailResult'] == '' and not terminal['removed'], 'Whole-queue cancellation executed tail or removed cart'
        if name in ('approach-target-loss', 'approach-tail-success'):
            assert math.dist((terminal['x'], terminal['y']), (queued['tailX'], queued['tailY'])) <= .06, 'Independent tail did not reach its own goal'
            assert groups[-1][0]['wallTimeMillis'] >= groups[-2][0]['wallTimeMillis'], 'Independent tail ran out of order'
        elif success and name != 'container-equip':
            assert math.dist((terminal['x'], terminal['y']), (first['goalX'], first['goalY'])) <= .002, 'Pickup started away from precise handle stance'
        summaries.append(dict(case=name, itemId=first['id'], nativeActionIds=[g[0]['nativeActionId'] for g in groups],
                              approachResult=terminal['approachResult'], tailResult=terminal['tailResult']))
    return dict(functionalPass=True, approachVerified=True, failures=[], cases=summaries,
                limit='Seven SP public-menu scenes; real native wall routing and calibrated blocked final alignment, exact item/cargo and native lifecycle. Rendered mesh/grip and Host replication remain separate gates.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('profile', 'log', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--scene',action='append')
    args = parser.parse_args()
    assert not args.output.exists(), 'Refuse to overwrite approach report'
    try:
        lifecycle = [json.loads(line) for line in (args.profile/'action-lifecycle.jsonl').read_text().splitlines()]
        result = analyze(args.log.read_text(errors='replace'), lifecycle,scenes=args.scene)
    except (AssertionError, KeyError, TypeError, ValueError, OSError) as error:
        result = dict(functionalPass=False, approachVerified=False, failures=[str(error)], cases=[])
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0 if result['functionalPass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
