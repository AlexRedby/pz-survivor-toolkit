"""Require exact-item rapid actions, native retirement and independent fading clip clocks."""
import argparse
import json
import math
from pathlib import Path
import re
import runpy

shared = runpy.run_path(str(Path(__file__).with_name('analyze-interaction.py')))
decode, finite = shared['_decode'], shared['_finite']
rolling = runpy.run_path(str(Path(__file__).with_name('analyze-wheel-cycle.py')))['rolling']
CASES = tuple(f'{sex}-{load}-{spec}' for sex in ('male', 'female') for load in ('empty', 'full')
              for spec in ('complete-chain', 'pickup-restart', 'drop-restart'))
TYPES = {'pickup': 'ToolkitWoodCartPickup', 'drop': 'ToolkitWoodCartSetdown'}
ARM_BONES = tuple('Bip01_'+side+'_'+part for side in 'LR' for part in ('UpperArm','Forearm','Hand'))
CLIPS = {'SaucedWheelbarrow.WheelbarrowWood': 'Toolkit_WoodCart_Pickup',
         'SaucedWheelbarrow.WheelbarrowMetal': 'Toolkit_MetalCart_Pickup'}
CLIP = CLIPS['SaucedWheelbarrow.WheelbarrowWood']
CLOCK = 'ToolkitWoodCartClipTime'


def matrix(value):
    assert len(value) == 16 and all(type(v) in (int, float) and math.isfinite(v) for v in value), 'Invalid pose matrix'


def tracks(frame, cart_type='SaucedWheelbarrow.WheelbarrowWood'):
    """Select only the authored clip belonging to an exact captured item type."""
    assert cart_type in CLIPS, 'Unsupported captured repeat cart type'
    clip = CLIPS[cart_type]
    finite(frame)
    found = {}
    for track in frame['tracks']:
        if track['name'] != clip:
            assert track['name'] not in CLIPS.values() and track.get('clockBinding') != CLOCK, 'Wrong cart clip for captured cart type'
            continue
        identity = track['trackId']
        assert type(identity) is int and identity >= 0 and identity not in found, 'Invalid/duplicate clip track identity'
        assert type(track['reverse']) is bool and track['clockBinding'] in (None, CLOCK), 'Missing native clip direction/clock binding'
        assert 0 <= track['weight'] <= 1.001 and 0 <= track['field'] <= 1.001 and track['duration'] > 0, 'Invalid clip weight/duration'
        assert -.001 <= track['time'] <= track['duration']+.001, 'Invalid clip clock'
        found[identity] = track
    return found


def analyze(text, lifecycle, body, grip, world, draws, pose_tail, *, hotkey=False):
    types = dict(TYPES, drop='ToolkitWoodCartDrop') if hotkey else TYPES
    assert '[WOOD_BANK] RUN_STARTED' in text, 'Missing repeat run boundary'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    completed = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    assert len(completed) == 12 and {name for name, _ in completed} == set(CASES), 'Missing/duplicate repeat scenes'
    assert re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases=12(?:\s|$)', log) and '[WOOD_BANK] FAIL' not in log, 'Repeat run incomplete/failed'
    samples, events = [], []
    for line in log.splitlines():
        match = re.search(r'\[WOOD_INTERACTION_(SAMPLE|EVENT)\] (\{.*\})', line)
        if match:
            (samples if match[1] == 'SAMPLE' else events).append(decode(match[2]))
    hotkeys = [decode(m[1]) for m in re.finditer(r'\[WOOD_HOTKEY\] (\{.*\})', log)]
    releases = [decode(m[1]) for m in re.finditer(r'\[WOOD_HOTKEY_RELEASE\] (\{.*\})', log)]
    summaries = []
    for name, stamp in completed:
        start = int(stamp)
        assert len(re.findall(r'\[WOOD_BANK\] CASE '+re.escape(name)+r' attempt=\d+ wall='+stamp+r'(?:\s|$)', log)) == 1, 'Missing unique selected repeat attempt'
        rows = [r for r in samples if r['case'] == name and r['start'] == start]
        receipts = [r for r in events if r['case'] == name and r['start'] == start]
        assert len(rows) >= 100 and rows[0]['elapsed'] <= 100 and rows[-1]['elapsed'] >= 19500, 'Incomplete repeat sample window'
        assert all(0 < b['wall']-a['wall'] <= 100 for a,b in zip(rows,rows[1:])), 'Repeat sampling gap'
        sex, load, spec = name.split('-', 2)
        plan = [('pickup',False),('drop',False),('pickup',False),('drop',False)] if spec == 'complete-chain' else \
               [('pickup',True),('pickup',True),('pickup',False),('drop',False)] if spec == 'pickup-restart' else \
               [('pickup',False),('drop',True),('drop',True),('drop',False)]
        expected = ['prepared']
        for _, cancelled in plan:
            expected += ['actionQueued'] + (['cancelRequested','cancelCleared'] if cancelled else ['actionCompleted'])
        expected += ['dropped','finalCleanup']
        assert [r['event'] for r in receipts] == expected, 'Missing/reordered rapid action receipts'
        first = receipts[0]
        cart_type = first['cartType']
        assert cart_type in CLIPS, 'Unsupported captured repeat cart type'
        clip = CLIPS[cart_type]
        assert cart_type == 'SaucedWheelbarrow.WheelbarrowWood', 'Full repeat analysis requires wooden wheel calibration; use tracks() for metal clip evidence'
        assert first['cargoCount'] > 0 and first['cargo'] > 0 if load == 'full' else first['cargoCount'] == first['cargo'] == 0, 'Wrong repeat cargo variant'
        for row in rows + receipts:
            finite(row)
            assert row['female'] is (sex == 'female'), 'Wrong repeat body model'
            assert row['cartType'] == cart_type, 'Repeat cart type changed'
            assert row['wall']-row['start'] == row['elapsed'] and 0 <= row['elapsed'] <= 20500, 'Repeat clocks disagree'
            assert (row['id'],row['cargoIDs'],row['cargoCount'],row['condition']) == (first['id'],first['cargoIDs'],first['cargoCount'],first['condition']) and abs(row['cargo']-first['cargo']) < .001, 'Repeat item/cargo/condition changed'
            assert row['worldCount'] in (0,1) and row['inventoryCount'] in (0,1) and row['worldCount']+row['inventoryCount'] == 1 and row['woodWorldCount'] == row['worldCount'], 'Repeat item lost or duplicated'
            owned = bool(row['inventoryCount'])
            assert row['worldID'] == (-1 if owned else row['id']) and row['heldID'] == row['secondaryID'] == (row['id'] if owned else -1) and row['worldAlpha'] >= .99, 'Repeat ownership/visibility changed'
        final = receipts[-1]
        assert final['event'] == 'finalCleanup' and 19000 <= final['elapsed'] <= 20000, 'Missing final cleanup receipt'
        dropped = receipts[-2]
        settled = [r for r in rows if r['wall'] >= final['wall']]
        assert len(settled) >= 10 and rows[-1]['wall']-dropped['wall'] >= 1000, 'Missing final settled tail'
        for row in settled + [final]:
            assert row['worldCount'] == 1 and row['inventoryCount'] == 0 and row['nativeActions'] == row['luaActions'] == 0 \
                and row['actionType'] == '' and not any(row[k] for k in ('active','recovering','rendered','ToolkitWoodCartAction','IsPerformingAnAction')) \
                and row['PerformingAction'] == '', 'Incomplete final native/Lua/presentation cleanup'
        frames = [r for r in pose_tail if start <= r['wallTimeMillis'] <= start+20000]
        assert len(frames) >= 100 and frames[0]['wallTimeMillis'] <= start+100 and frames[-1]['wallTimeMillis'] >= start+19500, 'Incomplete repeat track/body window'
        assert all(0 < b['wallTimeMillis']-a['wallTimeMillis'] <= 100 for a,b in zip(frames,frames[1:])), 'Repeat track/body sampling gap'
        for frame in frames:
            assert frame['cartModelCount'] in (0,1), 'Duplicate repeat cart model'
            tracks(frame, cart_type)
            for bone in ('Bip01_Spine',)+ARM_BONES:
                matrix(frame['bones'][bone])
        assert all(f['cartModelCount'] == 0 and not any(t['weight']*t['field'] > .0001 for t in tracks(f, cart_type).values()) for f in frames if f['wallTimeMillis'] >= final['wall']), 'Final native cart model/clip cleanup incomplete'
        native = [r for r in lifecycle if start <= r['wallTimeMillis'] <= start+20000 and r['metaType'] in types.values()]
        queued = [r for r in receipts if r['event'] == 'actionQueued']
        terminals = [r for r in receipts if r['event'] in ('actionCompleted','cancelCleared')]
        native_groups = []
        cursor = 0
        for serial, ((action,cancelled),queue,terminal) in enumerate(zip(plan,queued,terminals),1):
            assert queue['actionSerial'] == terminal['actionSerial'] == serial, 'Wrong rapid action serial'
            names = ['start','stop'] if cancelled else ['start','perform','complete']
            group = native[cursor:cursor+len(names)];cursor += len(names)
            assert [r['event'] for r in group] == names and all(r['metaType'] == types[action] for r in group), 'Missing/duplicate/reordered native action lifecycle'
            assert len({r['nativeActionId'] for r in group}) == 1 and all(r['phase'] == 'exit' and r['playerNum'] == 0 and not r['threw'] for r in group), 'Invalid repeat native receipt'
            assert queue['wall'] <= group[0]['wallTimeMillis'] < group[-1]['wallTimeMillis'] <= terminal['wall'], 'Native action outside rapid boundaries'
            if cancelled:
                request = next(r for r in receipts if r['event'] == 'cancelRequested' and r['actionSerial'] == serial)
                threshold = .55 if serial == (1 if spec == 'pickup-restart' else 2) else .88
                assert request['actionType'] == types[action] and threshold <= request['progress'] < threshold+.1, 'Wrong repeat cancellation phase'
                assert request['wall'] <= group[-1]['wallTimeMillis'] <= terminal['wall'] and not group[-1]['finished'], 'Cancelled repeat performed/transferred'
                assert terminal['nativeActions'] == terminal['luaActions'] == 0, 'Restart queued before native/Lua clear'
                assert terminal['inventoryCount'] == queue['inventoryCount'] and terminal['worldCount'] == queue['worldCount'], 'Cancellation transferred cart ownership'
            else:
                assert group[-1]['finished'], 'Native repeat did not finish'
                assert terminal['inventoryCount'] == int(action == 'pickup'), 'Successful repeat did not transfer exact item'
            stable = [r for r in rows if group[0]['wallTimeMillis']+100 < r['wall'] < group[-1]['wallTimeMillis'] and r['progress'] < .98]
            assert len(stable) >= 3, 'Missing stable authored repeat action samples'
            assert all(r['actionSerial'] == serial and r['actionType'] == types[action]
                       and all(r[key] is True for key in ('active','authored','rendered','ik')) for r in stable), 'Stable authored repeat presentation/IK failed'
            native_groups.append(group)
            active_body = [r for r in body if group[0]['wallTimeMillis'] <= r['wallTimeMillis'] <= group[-1]['wallTimeMillis']]
            assert len(active_body) >= 3, 'Missing repeat actual cart/body poses'
            for frame in active_body:
                finite(frame);matrix(frame['cart'])
                for bone in ('Bip01_Spine','Bip01_L_Hand','Bip01_R_Hand'):
                    matrix(frame['bones'][bone])
            active_grip = [r for r in grip if group[0]['wallTimeMillis'] <= r['wallTimeMillis'] <= group[-1]['wallTimeMillis']]
            for frame in active_grip: finite(frame)
            assert len(active_grip) >= 3 and all(r['result'] is True and r['threw'] is False for r in active_grip), 'Missing/failed repeat grip coverage'
        assert cursor == len(native) and len({g[0]['nativeActionId'] for g in native_groups}) == 4, 'Duplicate/reused native repeat action'
        if hotkey:
            keys = [r for r in hotkeys if r['case'] == name and r['start'] == start]
            drops = [i for i,(action,_) in enumerate(plan) if action == 'drop']
            assert [(r['actionSerial'],r['event']) for r in keys] == [(i+1,e) for i in drops for e in ('queued','started')], 'Missing/duplicate hotkey entry and start receipts'
            released = [r for r in releases if r['case'] == name and r['start'] == start]
            assert [r['actionSerial'] for r in released] == [i+1 for i in drops], 'Missing/duplicate hotkey release receipts'
            for i in drops:
                request, placement = [r for r in keys if r['actionSerial'] == i+1]
                for r in (request,placement):
                    finite(r)
                    assert r['route'] == 'OnKeyStartPressed' and r['actionType'] == types['drop'] and r['id'] == first['id'] and type(r['key']) is int and r['key'] > 0, 'Wrong hotkey producer or exact item'
                release = next(r for r in released if r['actionSerial'] == i+1)
                finite(release)
                assert release['id'] == first['id'] and release['key'] == request['key'] and request['wall'] < release['wall'] <= request['wall']+100, 'Hotkey tap was not released on a subsequent frame'
                assert request['key'] == placement['key'] and request['wall'] == queued[i]['wall'], 'Hotkey input not correlated with queue'
                assert native_groups[i][0]['wallTimeMillis'] <= placement['wall'] < native_groups[i][-1]['wallTimeMillis'], 'Hotkey placement not sampled after native start'
                distance = max(abs(math.floor(placement['x'])-math.floor(placement['actorX'])),abs(math.floor(placement['y'])-math.floor(placement['actorY'])))
                assert distance == 1 and math.floor(placement['z']) == math.floor(placement['actorZ']), 'Hotkey adjacent-square placement not exercised'
                if not plan[i][1]:
                    result = terminals[i]
                    assert max(abs(result['world'+axis.upper()]-placement[axis]) for axis in 'xyz') <= .002, 'Hotkey world placement differs from native start fields'
                    yaw = (result['worldRotation']-placement['rotation']+180)%360-180
                    assert abs(yaw) <= .01, 'Hotkey world rotation differs from native start fields'
        transitions = []
        for index in range(3):
            retired = native_groups[index][-1]['wallTimeMillis'];fresh = native_groups[index+1][0]['wallTimeMillis']
            assert queued[index+1]['wall'] == terminals[index]['wall'], 'Repeat not queued on first observed empty tick'
            assert 0 <= fresh-retired <= 200, 'Native restart delayed beyond 200ms'
            seam_samples = 0
            if plan[index][1]:
                seam = [f for f in frames if retired-50 <= f['wallTimeMillis'] <= fresh+150]
                assert len(seam) >= 3 and seam[0]['wallTimeMillis'] <= retired and seam[-1]['wallTimeMillis'] >= fresh+100, 'Missing cancelled-retry cart presentation window: '+name
                assert all(0 < b['wallTimeMillis']-a['wallTimeMillis'] <= 50 for a,b in zip(seam,seam[1:])), 'Cancelled-retry presentation sampling gap: '+name
                assert all(f['cartModelCount'] == 1 for f in seam), 'Cancelled-retry cart presentation disappeared: '+name
                seam_draws = [r for r in draws if retired-50 <= r['wall'] <= fresh+150]
                assert len(seam_draws) >= 3 and seam_draws[0]['wall'] <= retired and seam_draws[-1]['wall'] >= fresh+100, 'Missing cancelled-retry actual held draws: '+name
                assert all(0 <= b['wall']-a['wall'] <= 50 for a,b in zip(seam_draws,seam_draws[1:])), 'Cancelled-retry actual draw sampling gap: '+name
                assert all(r['source'] == 'held' for r in seam_draws), 'Cancelled-retry exposed actual world cart draw: '+name
                seam_samples = len(seam)
            before = [r for r in frames if retired-100 <= r['wallTimeMillis'] < retired]
            assert before, 'Missing pre-retirement clip pose'
            old_candidates = tracks(before[-1], cart_type)
            old = {i:t for i,t in old_candidates.items() if t['clockBinding'] == CLOCK and t['reverse'] is (plan[index][0] == 'drop')}
            assert len(old) == 1, 'Missing unique retiring clock-bound clip'
            old_id = next(iter(old))
            overlap = []
            for frame in frames:
                if not fresh <= frame['wallTimeMillis'] <= retired+200:
                    continue
                current = tracks(frame, cart_type)
                newer = [(i,t) for i,t in current.items() if i != old_id and t['clockBinding'] == CLOCK and t['reverse'] is (plan[index+1][0] == 'drop')]
                if old_id in current and current[old_id]['weight']*current[old_id]['field'] > .0001 and newer:
                    assert len(newer) == 1 and current[old_id]['clockBinding'] is None, 'Retired clip still bound to fresh clock'
                    overlap.append((frame,current[old_id],newer[0]))
            assert overlap, 'Missing actual fading-old/fresh-track overlap'
            new_id,new_track = overlap[0][2]
            fresh_progress = new_track['time']/new_track['duration']
            if new_track['reverse']: fresh_progress = 1-fresh_progress
            assert 0 <= fresh_progress <= .2, 'Fresh clip clock did not reset'
            old_times = [tracks(f, cart_type)[old_id]['time'] for f in frames if f['wallTimeMillis'] >= overlap[0][0]['wallTimeMillis'] and old_id in tracks(f, cart_type)]
            assert max(old_times)-min(old_times) <= .005, 'Retired clip clock reset/advanced with replacement'
            new_times = [tracks(f, cart_type)[new_id]['time'] for f in frames if fresh <= f['wallTimeMillis'] <= native_groups[index+1][-1]['wallTimeMillis'] and new_id in tracks(f, cart_type)]
            assert new_times and max(new_times)-min(new_times) > .1*new_track['duration'], 'Fresh clock did not progress independently'
            window = [f for f in frames if retired-100 <= f['wallTimeMillis'] <= fresh+300]
            motion = {bone:max(math.dist(a['bones'][bone][12:15],b['bones'][bone][12:15]) for a,b in zip(window,window[1:])) for bone in ('Bip01_Spine','Bip01_L_Hand','Bip01_R_Hand')}
            assert motion['Bip01_Spine'] <= .05 and max(motion[b] for b in ('Bip01_L_Hand','Bip01_R_Hand')) <= .07, 'Abrupt repeat body/hand recovery step'
            arm_drift = 0
            for side in 'LR':
                for a,b in [('UpperArm','Forearm'),('Forearm','Hand')]:
                    lengths = [math.dist(f['bones']['Bip01_'+side+'_'+a][12:15],f['bones']['Bip01_'+side+'_'+b][12:15]) for f in window]
                    assert all(v > .01 for v in lengths), 'Missing repeat arm segment'
                    arm_drift = max(arm_drift,max(lengths)-min(lengths))
            assert arm_drift <= .005, 'Repeat arm segment stretched'
            cart_window = [f for f in body if retired-100 <= f['wallTimeMillis'] <= fresh+300]
            assert len(cart_window) >= 5 and cart_window[0]['wallTimeMillis'] < retired and cart_window[-1]['wallTimeMillis'] >= fresh+200, 'Missing first restart cart render window'
            assert all(0 < b['wallTimeMillis']-a['wallTimeMillis'] <= 100 for a,b in zip(cart_window,cart_window[1:])), 'Restart cart render sampling gap'
            cart_step = max(math.dist(a['cart'][12:15],b['cart'][12:15]) for a,b in zip(cart_window,cart_window[1:]))
            assert cart_step <= .035, 'Cart jumped through immediate restart handoff'
            transitions.append(dict(retiredTrackId=old_id,freshTrackId=new_id,nativeGapMs=fresh-retired,overlapSamples=len(overlap),cancelledSeamSamples=seam_samples,maxBoneSteps=motion,maxArmLengthDrift=arm_drift,maxCartStep=cart_step))
        wheel_rows = sorted((r for r in draws if start <= r['wall'] <= start+20000),key=lambda r:r['wall'])
        assert len(wheel_rows) >= 50 and all(r['source'] != 'world' or r['itemId'] == first['id'] for r in wheel_rows), 'Missing/foreign repeat wheel draws'
        for group in native_groups:
            assert len([r for r in wheel_rows if group[0]['wallTimeMillis'] <= r['wall'] <= group[-1]['wallTimeMillis']]) >= 3, 'Missing repeat action wheel coverage'
        wheel = rolling(wheel_rows)
        assert wheel['maxResidual'] <= .004 and wheel['worldDraws'] > 0 and wheel['heldDraws'] > 0, 'Repeat wheel phase/ownership handoff failed'
        renders = [r for r in world if final['wall'] <= r['wallTimeMillis'] <= start+20000 and r['itemId'] == first['id']]
        assert renders and all(r.get('renderStatus') == 'Ready' and r.get('alpha',0) >= .99 and not r.get('transitionHidden') for r in renders), 'Missing final visible world cart'
        summaries.append(dict(case=name,cartType=cart_type,clip=clip,itemId=first['id'],nativeActionIds=[g[0]['nativeActionId'] for g in native_groups],transitions=transitions,wheel=wheel))
    return dict(functionalPass=True,clockVerified=True,recoveryVerified=True,wheelCoverageVerified=True,failures=[],cases=summaries,
                limit='Twelve isolated SP scenes with two contact/late same-action cancellations or a four-action immediate chain. Sampled native clock overlap, pose steps and rolling are bounded gates; full mesh clearance and visual review remain separate.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('profile','log','output'):
        parser.add_argument('--'+name,type=Path,required=True)
    parser.add_argument('--hotkey', action='store_true', help='Require native hotkey drop and serialized adjacent-square placement evidence')
    args = parser.parse_args()
    assert not args.output.exists(), 'Refuse to overwrite report'
    def read(name): return [decode(line) for line in (args.profile/name).read_text().splitlines()]
    try:
        result = analyze(args.log.read_text(errors='replace'),read('action-lifecycle.jsonl'),read('body-clearance.jsonl'),
                         read('wood-grip-poses.jsonl'),read('world-cart-poses.jsonl'),read('wheel-roll-draws.jsonl'),read('action-tail-poses.jsonl'),hotkey=args.hotkey)
    except (AssertionError,KeyError,TypeError,ValueError,OSError) as error:
        result = dict(functionalPass=False,clockVerified=False,recoveryVerified=False,wheelCoverageVerified=False,failures=[str(error)],cases=[])
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    print(json.dumps(result,indent=2,allow_nan=False))
    return 0 if result['functionalPass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
