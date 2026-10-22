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


def verify_vehicle(first, selected):
    prefix='Native parked vehicle: '
    assert first['collisionKind']=='vehicle', prefix+'wrong collision fixture'
    state=first['vehicleState']
    match=re.fullmatch(r'id=(\d+) z=([-+\d.Ee]+) static=true active=false bodyBlocked=true crossBlocked=true hull=([-+\d.Ee,]+)',state)
    assert match and float(match[2])==first['z'], prefix+'missing native static vehicle/map proof'
    hull=[float(v) for v in match[3].split(',')]
    assert len(hull)==8 and all(math.isfinite(v) for v in hull), prefix+'invalid native vehicle hull'
    assert abs(max(hull[::2])-first['collisionX'])<=.002, prefix+'vehicle collision edge differs from hull'
    assert abs(max(hull[1::2])+min(hull[1::2])-2*first['y'])<=.002, prefix+'approach did not target vehicle side center'
    assert abs(first['goalX']-first['collisionX']-.10)<.002 and abs(first['goalY']-first['y'])<.002, prefix+'wrong blocked handle target'
    assert all(r['vehicleState']==state and r['collisionKind']=='vehicle' and r['collisionX']==first['collisionX'] and r['x']>=first['collisionX']-.002 for r in selected), prefix+'collision/pose changed'


def analyze(text, lifecycle, scenes=None,entry_contact=False):
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
    records = []
    for index, line in enumerate(log.splitlines()):
        match = re.search(r'\[CART_APPROACH_(SAMPLE|EVENT)\] (\{.*\})', line)
        if match:
            row = json.loads(match[2])
            assert all(math.isfinite(v) for v in row.values() if type(v) in (int, float)), 'Nonfinite approach evidence'
            row['_order'], row['_sample'] = index, match[1] == 'SAMPLE'
            records.append(row)
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
        if entry_contact:
            assert name in ('container-equip','wrong-side'), 'Unsupported entry-contact scene'
            assert all(r.get('entryContactRepro') is True and r.get('female') is False
                       and r.get('pantsType')=='Base.Trousers_JeanBaggy'
                       and str(r.get('pantsModel','')).lower().replace('\\','/').removesuffix('.x')=='skinned/clothes/bob_trousers'
                       and r.get('pantsID')==first.get('pantsID') for r in selected), 'Missing actual entry-contact outfit proof'
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
        if entry_contact and name=='container-equip':
            begin,end=queued['preWalkStartedAt'],queued['preWalkReleasedAt']
            assert start+300<=begin and 350<=end-begin<=550 and 0<queued['wall']-end<=150, 'Missing bounded native pre-menu Walk/release'
            before=[r for r in rows if r['wall']<=queued['wall']]
            assert queued.get('preWalkSeen') is True and .05<=queued['preWalkDistance']<1.5, 'Native pre-menu Walk did not move'
            assert any(r.get('preWalkDrive')==1 for r in before) and queued['preWalkDrive']==0, 'Missing native Walk input/release'
            assert .05<=math.dist((queued['x'],queued['y']),(first['x'],first['y']))<1.5, 'Missing measured pre-menu displacement'
            assert all(r['nativeActions']==r['luaActions']==0 and r['primaryID']==-1 for r in before), 'Pre-menu Walk changed native queue/cart ownership'
        else:
            assert all(math.dist((r['x'],r['y']),(first['x'],first['y'])) <= .002 for r in rows if r['wall'] <= queued['wall']), 'Actor moved before native menu request'
        # CancelAction can empty both queues synchronously while the bare walking animation blends out.
        # Same-ms samples printed before the terminal event still describe the pre-cancel native state.
        post_terminal=[r for r in rows if r['_order']>terminal['_order']]
        cancel_metrics={}
        native_terminal_wall=terminal['wall']
        if name=='approach-cancel':
            stops=[r for r in lifecycle if queued['wall']<=r['wallTimeMillis']<=settled['wall']
                   and r['metaType']=='ISWalkToTimedActionF' and r['event']=='stop']
            assert len(stops)==1 and post_terminal, 'Missing exact native cancellation stop receipt'
            native_terminal_wall=max(native_terminal_wall,stops[0]['wallTimeMillis'])
            assert native_terminal_wall<=post_terminal[0]['wall'], 'Native stop occurred after post-terminal sample'
            peak=max(math.dist((r['x'],r['y']),(terminal['x'],terminal['y'])) for r in post_terminal)
            assert peak<=.06, 'Cancelled native walking drift exceeded .06'
            before_deadline=[r for r in post_terminal if r['wall']<=native_terminal_wall+500]
            assert before_deadline, 'Missing native cancellation settlement deadline'
            stable_start=before_deadline[-1]
            assert native_terminal_wall+250<=stable_start['wall'] and settled['wall']-stable_start['wall']>=500, 'Missing final 500ms cancellation settlement window'
            assert all(math.dist((r['x'],r['y']),(settled['x'],settled['y']))<=.002
                       for r in post_terminal if r['_order']>=stable_start['_order']), 'Cancelled native walking did not settle by 500ms'
            cancel_metrics=dict(nativeCancelPeakDrift=peak,nativeCancelSettledByMillis=stable_start['wall']-native_terminal_wall,
                                nativeCancelStopWall=stops[0]['wallTimeMillis'])
        else:
            assert all(math.dist((r['x'],r['y']),(terminal['x'],terminal['y'])) <= .002 for r in post_terminal), 'Actor moved after native terminal state'
        for a, b in zip(rows, rows[1:]):
            assert math.dist((a['x'], a['y']), (b['x'], b['y'])) <= 8*(b['wall']-a['wall'])/1000+.03, 'Actor teleported during native approach'
        success = name in SUCCESS
        for row in [terminal, settled] + post_terminal:
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
            stopped = i == 0 and name == 'approach-cancel'
            assert [r['event'] for r in group] == (['start', 'stop'] if stopped else ['start', 'perform', 'complete']), 'Native lifecycle did not stop/complete exactly once'
            assert all(r['metaType'] == group[0]['metaType'] for r in group), 'Native action identity reused'
            assert queued['wall'] <= group[0]['wallTimeMillis'] < group[-1]['wallTimeMillis'] <= native_terminal_wall, 'Native action outside queue boundaries'
        approach_rows = [r for r in rows if queued['wall'] < r['wall'] < terminal['wall'] and r['actionType'] == 'ISWalkToTimedActionF']
        if name != 'container-equip':
            assert len(approach_rows) >= 3 and any(r['hasPath'] for r in approach_rows), 'Native approach never became active'
        if name == 'precise-blocked':
            verify_vehicle(first,selected)
            original=(first['goalX'],first['goalY'])
            clipped=(terminal['nativeTargetX'],terminal['nativeTargetY'])
            assert terminal['approachResult']=='Succeeded' and .02 < math.dist(original,clipped) < .10, 'Missing native planner clipped target'
            assert math.dist((terminal['x'],terminal['y']),original)>.002 and math.dist((terminal['x'],terminal['y']),clipped)<=.06, 'Invalid clipped native arrival'
            assert any(r['hasPath'] and math.dist((r['nativeTargetX'],r['nativeTargetY']),original)>.002 for r in approach_rows), 'Missing live native target clipping'
            assert all((r['nativeTargetX'],r['nativeTargetY'])==clipped for r in approach_rows if r['hasPath']), 'Native clipped target changed'
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
                              approachResult=terminal['approachResult'], tailResult=terminal['tailResult'],entryContactRepro=entry_contact,**cancel_metrics))
    return dict(functionalPass=True, approachVerified=True, preciseStallExercised=False, failures=[], cases=summaries,
                limit='Selected SP public-menu scenes only; exact item/cargo and native lifecycle verified. Unselected approach routes, rendered mesh/grip and Host replication remain separate gates.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('profile', 'log', 'output'):
        parser.add_argument('--'+name, type=Path, required=True)
    parser.add_argument('--scene',action='append')
    parser.add_argument('--entry-contact',action='store_true')
    args = parser.parse_args()
    assert not args.output.exists(), 'Refuse to overwrite approach report'
    try:
        lifecycle = [json.loads(line) for line in (args.profile/'action-lifecycle.jsonl').read_text().splitlines()]
        result = analyze(args.log.read_text(errors='replace'), lifecycle,scenes=args.scene,entry_contact=args.entry_contact)
    except (AssertionError, KeyError, TypeError, ValueError, OSError) as error:
        result = dict(functionalPass=False, approachVerified=False, failures=[str(error)], cases=[])
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False)+'\n')
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0 if result['functionalPass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
