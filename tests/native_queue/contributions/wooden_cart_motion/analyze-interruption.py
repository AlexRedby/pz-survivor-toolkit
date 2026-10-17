"""Check ordinary SP cancellation, native lifecycle and exact-item retry receipts."""
import argparse
import json
import math
import numpy as np
from pathlib import Path
import re
import runpy

shared = runpy.run_path(str(Path(__file__).with_name('analyze-interaction.py')))
decode, finite = shared['_decode'], shared['_finite']
rolling = runpy.run_path(str(Path(__file__).with_name('analyze-wheel-cycle.py')))['rolling']
CASES = tuple(f'{action}-{phase}-{route}' for action in ('pickup', 'drop')
              for phase in ('early', 'contact', 'late') for route in ('cancel', 'walk'))
MATRIX_CASES = tuple(f'{sex}-{load}-{case}' for sex in ('male', 'female') for load in ('empty', 'full') for case in CASES)
TYPES = {'pickup': 'ToolkitWoodCartPickup', 'drop': 'ToolkitWoodCartSetdown'}
THRESHOLDS = {'early': .15, 'contact': .55, 'late': .88}


def moving_knee_angles(frame):
    angles = []
    for side in 'LR':
        thigh, calf = [np.asarray(frame['bones']['Bip01_'+side+'_'+part], dtype=float).reshape(4,4).T[:3,:3]
                       for part in ('Thigh', 'Calf')]
        assert np.isfinite(thigh).all() and np.isfinite(calf).all(), 'Nonfinite moving knee rotation'
        assert np.linalg.det(thigh) > 1e-8 and np.linalg.det(calf) > 1e-8, 'Degenerate moving knee rotation'
        relative = np.linalg.solve(thigh, calf)
        relative /= np.linalg.norm(relative, axis=0)
        # Native calf flexion is around local +Y; a toe pointing down cannot define forward on the ground.
        angle = math.atan2(relative[0,2]-relative[2,0], relative[0,0]+relative[2,2])
        assert math.isfinite(angle), 'Nonfinite moving knee angle'
        angles.append(angle)
    return angles


def analyze(text, lifecycle, body, grip, world, draws, pose_tail, matrix=False):
    assert '[WOOD_BANK] RUN_STARTED' in text, 'Missing cancellation run boundary'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    completed = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    cases = MATRIX_CASES if matrix else CASES
    assert len(completed) == len(cases) and {name for name, _ in completed} == set(cases), 'Missing/duplicate cancellation cases'
    assert re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases=' + str(len(cases)) + r'(?:\s|$)', log), 'Cancellation run incomplete'
    assert '[WOOD_BANK] FAIL' not in log, 'Cancellation scenario failed'
    samples, events, record_order = [], [], {}
    for index, line in enumerate(log.splitlines()):
        match = re.search(r'\[WOOD_INTERACTION_(SAMPLE|EVENT)\] (\{.*\})', line)
        if match:
            record = decode(match[2])
            record_order[id(record)] = index
            (samples if match[1] == 'SAMPLE' else events).append(record)
    failures, summaries = [], []
    for name, stamp in completed:
        start = int(stamp)
        rows = [r for r in samples if r['case'] == name and r['start'] == start]
        receipts = [r for r in events if r['case'] == name and r['start'] == start]
        assert len(rows) >= 100 and rows[0]['elapsed'] < 500 and rows[-1]['elapsed'] >= 19500, 'Missing sample window: ' + name
        assert all(0 < b['wall']-a['wall'] <= 500 for a,b in zip(rows,rows[1:])), 'Cancellation sampling gap: ' + name
        action, phase, route = name.rsplit('-', 3)[-3:]
        expected = ['prepared', 'pickupQueued']
        if action == 'drop': expected += ['pickedUp', 'dropQueued']
        expected += ['cancelRequested', 'cancelled']
        if matrix and route == 'walk': expected += ['movementReleased']
        expected += ['retryQueued']
        expected += ['pickedUp', 'dropQueued', 'dropped'] if action == 'pickup' else ['dropped']
        assert [r['event'] for r in receipts] == expected, 'Missing/reordered cancellation events: ' + name
        lookup = {r['event']: r for r in receipts}
        request, cancelled, retry = [lookup[key] for key in ('cancelRequested','cancelled','retryQueued')]
        assert TYPES[action] == request['actionType'] and THRESHOLDS[phase] <= request['progress'] < THRESHOLDS[phase]+.1, 'Wrong cancellation phase: ' + name
        assert 0 <= cancelled['wall']-request['wall'] < 1000 and retry['wall']-cancelled['wall'] >= 850, 'Missing cancellation/retry tail'
        first = receipts[0]
        if matrix:
            sex, load = name.split('-')[:2]
            assert all(r['female'] is (sex == 'female') for r in rows + receipts), 'Wrong actor sex: ' + name
            assert (first['cargo'] > 0 and first['cargoCount'] > 0 if load == 'full'
                    else first['cargo'] == 0 and first['cargoCount'] == 0), 'Wrong cargo variant: ' + name
        for row in rows + receipts:
            finite(row)
            assert row['wall']-row['start'] == row['elapsed'], 'Cancellation clocks disagree'
            if (row['id'], row['cargoIDs'], row['cargoCount']) != (first['id'],first['cargoIDs'],first['cargoCount']) or abs(row['cargo']-first['cargo']) > .001:
                failures.append((name, 'item identity/cargo changed')); break
        for row in rows + receipts:
            if (row['worldCount'] not in (0,1) or row['inventoryCount'] not in (0,1)
                or row['worldCount']+row['inventoryCount'] != 1 or row['woodWorldCount'] != row['worldCount']
                or row['worldID'] != (row['id'] if row['worldCount'] else -1)
                or row['worldCount'] and (row['heldID'] != -1 or row['secondaryID'] != -1)
                or row['inventoryCount'] and row['heldID'] != row['id']
                or row['inventoryCount'] and row['secondaryID'] != row['id'] or row['worldAlpha'] < .99):
                failures.append((name, 'ownership/visibility invariant failed')); break
        tail = [r for r in rows if cancelled['wall'] <= r['wall'] < retry['wall']]
        assert len(tail) >= 10, 'Missing settled cancellation samples'
        for row in tail + [cancelled, retry]:
            if row['nativeActions'] or row['luaActions'] or row['actionType'] or row['active'] or row['rendered'] and not row.get('recovering') or row['ToolkitWoodCartAction'] or row['PerformingAction'] or row['IsPerformingAnAction']:
                failures.append((name, 'native/Lua cleanup incomplete')); break
        owned = action == 'drop'
        if any(r['inventoryCount'] != int(owned) or r['worldCount'] != int(not owned) for r in tail):
            failures.append((name, 'cancellation transferred ownership'))
        if any(r['condition'] != request['condition'] for r in tail):
            failures.append((name, 'cancellation changed cart condition'))
        if not owned and any(abs(r[key]-request[key]) > .0001 for r in tail for key in ('worldX','worldY','worldZ','worldRotation','worldObjectAlpha')):
            failures.append((name, 'pickup cancellation moved/mutated the ground cart'))
        native = [r for r in lifecycle if start <= r['wallTimeMillis'] < retry['wall'] and r['metaType'] == TYPES[action]]
        assert [r['event'] for r in native] == ['start','stop'], 'Cancelled native action completed or lifecycle evidence missing: ' + name
        assert native[0]['nativeActionId'] == native[1]['nativeActionId'] and not native[1]['finished'] and not native[1]['threw'], 'Invalid native stop: ' + name
        stop = native[1]['wallTimeMillis']
        assert request['wall'] <= stop <= cancelled['wall'], 'Native stop outside cancellation window'
        movement = {}
        if matrix and route == 'walk':
            released = lookup['movementReleased']
            assert released['wall'] - cancelled['wall'] >= 900 and retry['wall'] - released['wall'] >= 450, 'Missing sustained movement/settled window'
            # A tick samples the pressed key before emitting its release event at the same timestamp.
            released_order = record_order[id(released)]
            driven = [r for r in tail if record_order[id(r)] < released_order]
            assert driven and all(r['driveCommand'] == 1 for r in driven), 'Movement released during recovery: ' + name
            assert released['driveCommand'] == 0 and all(r['driveCommand'] == 0 for r in tail if record_order[id(r)] > released_order), 'Movement did not release: ' + name
            for label, lower, upper in [('recovery', stop, stop+400), ('restored', stop+650, released['wall'])]:
                window = [r for r in driven if lower <= r['wall'] <= upper]
                assert len(window) >= 3, 'Missing movement samples: ' + name
                distance = math.dist([window[0]['x'], window[0]['y']], [window[-1]['x'], window[-1]['y']])
                movement[label] = distance
                if distance <= .005: failures.append((name, 'actor did not move during ' + label))
        resumed = [r for r in lifecycle if retry['wall'] <= r['wallTimeMillis'] <= start+20000 and r['metaType'] == TYPES[action]]
        assert [r['event'] for r in resumed] == ['start','perform','complete'], 'Retry did not complete exactly once: ' + name
        assert len({r['nativeActionId'] for r in resumed}) == 1 and resumed[0]['nativeActionId'] != native[0]['nativeActionId'] and all(not r['threw'] for r in resumed), 'Retry reused stopped native action'
        summary = dict(case=name, id=first['id'], nativeStopId=native[0]['nativeActionId'],
                       retryId=resumed[0]['nativeActionId'], cancelledProgress=request['progress'],
                       cancellationLatencyMs=cancelled['wall']-request['wall'], tailSamples=len(tail), movement=movement)
        recovery = [r for r in tail if r.get('recovering')]
        settled = [r for r in tail if r['wall'] >= stop+650]
        assert len(recovery) >= 3 and len(settled) >= 5, 'Missing bounded recovery and settled tail: '+name
        assert recovery[0]['wall']-stop <= 100 and recovery[-1]['wall']-stop <= 650, 'Recovery exceeded bounded window'
        progress = [r['presentationProgress'] for r in recovery]
        if any(b>a+.00001 for a,b in zip(progress,progress[1:])) or max(progress)-min(progress)<min(.05,request['progress']*.5):
            failures.append((name,'recovery did not reverse the interrupted timeline'))
        if any(r.get('recovering') or r['rendered'] for r in settled): failures.append((name,'recovery presentation leaked after deadline'))
        first_frames = [r for r in body if r.get('afterStopActionId') == native[0]['nativeActionId']]
        assert len(first_frames) == 1, 'Missing unique first post-stop render receipt'
        first_frame = first_frames[0]
        before = [r for r in body if stop-100 <= r['wallTimeMillis'] < stop]
        assert before and 0 <= first_frame['wallTimeMillis']-stop <= 100, 'Missing first stop-boundary poses'
        before = max(before,key=lambda r:r['wallTimeMillis'])
        first_cart_step = math.dist(before['cart'][12:15],first_frame['cart'][12:15])
        if first_cart_step>.035: failures.append((name,'cart jumped on the first recovery frame'))
        frames = [r for r in pose_tail if stop-100 <= r['wallTimeMillis'] <= stop+700]
        assert len(frames)>=10 and frames[0]['wallTimeMillis']<=stop and frames[-1]['wallTimeMillis']>=stop+650, 'Incomplete recovery body window'
        assert all(0 < b['wallTimeMillis']-a['wallTimeMillis'] <= 100 for a,b in zip(frames,frames[1:])), 'Recovery pose sampling gap'
        if any(r['cartModelCount'] not in (0,1) for r in frames):
            failures.append((name,'duplicate cart visual model during recovery'))
        motion = {}
        for bone in ('Bip01_Spine','Bip01_L_Hand','Bip01_R_Hand'):
            positions=[]
            for frame in frames:
                finite(frame)
                bone_matrix=frame['bones'][bone]
                assert len(bone_matrix)==16, 'Missing recovery bone matrix'
                positions.append(bone_matrix[12:15])
            motion[bone]=max(math.dist(a,b) for a,b in zip(positions,positions[1:]))
        if motion['Bip01_Spine']>.05 or max(motion[b] for b in ('Bip01_L_Hand','Bip01_R_Hand'))>.07:
            failures.append((name,'abrupt body/hand pose step during recovery'))
        arm_drift = 0
        for side in 'LR':
            for a,b in [('UpperArm','Forearm'),('Forearm','Hand')]:
                lengths = [math.dist(frame['bones']['Bip01_'+side+'_'+a][12:15], frame['bones']['Bip01_'+side+'_'+b][12:15]) for frame in frames]
                assert all(math.isfinite(value) and value > .01 for value in lengths), 'Missing/nonfinite arm segment'
                arm_drift = max(arm_drift, max(abs(value-lengths[0]) for value in lengths))
        if arm_drift > .005: failures.append((name,'arm segment stretched during recovery'))
        wheel_rows=sorted((r for r in draws if stop-100 <= r['wall'] < retry['wall']),key=lambda r:r['wall'])
        assert len(wheel_rows)>=10 and wheel_rows[0]['wall']<=stop and wheel_rows[-1]['wall']>=stop+650, 'Incomplete actual wheel draw window'
        assert all(r['source']!='world' or r['itemId']==first['id'] for r in wheel_rows), 'Foreign cart wheel draw'
        wheel=rolling(wheel_rows)
        if wheel['maxResidual']>.004: failures.append((name,'wheel phase did not follow cancelled cart movement/pitch'))
        knee_frames=[r for r in body if stop<=r['wallTimeMillis']<=stop+600]
        assert len(knee_frames)>=3, 'Missing recovery knee coverage'
        knee_measure = moving_knee_angles if route == 'walk' else shared['knee_direction']
        knees=[v for r in knee_frames for v in knee_measure(r)]
        if min(knees)<-.0001: failures.append((name,'recovery knee bent backwards'))
        summary.update(recoverySamples=len(recovery),lastRecoveryMs=recovery[-1]['wall']-stop,
                       firstRenderDelayMs=first_frame['wallTimeMillis']-stop,firstCartStep=first_cart_step,
                       maxBoneSteps=motion,maxArmLengthDrift=arm_drift,wheel=wheel,kneeSamples=len(knee_frames),
                       kneeMeasure='local-flexion-radians' if route == 'walk' else 'foot-plane-offset',minKneeMeasure=min(knees))
        if owned:
            restored=[r for r in body if stop+650 <= r['wallTimeMillis'] < retry['wall']]
            assert len(restored)>=5, 'Missing restored held endpoint'
            ys=[r['cart'][13] for r in restored]
            summary['cartYRange']=[min(ys),max(ys)]
            if any(abs(y-.097179376)>.005 for y in ys): failures.append((name,'held cart endpoint not restored'))
            grips=[r for r in grip if stop <= r['wallTimeMillis'] < retry['wall']]
            assert len(grips)>=10, 'Missing recovery/restored grip coverage'
            if any(r['result'] is not True or r['threw'] is not False for r in grips): failures.append((name,'recovery/restored held grip failed'))
            if any(not r['ToolkitCartMotion'] for r in tail if r['wall']>=stop+100): failures.append((name,'held visual gate not restored'))
        else:
            renders=[r for r in world if r['itemId']==first['id'] and stop+650 <= r['wallTimeMillis'] < retry['wall']]
            assert renders and any(r.get('renderStatus')=='Ready' and r.get('alpha',0)>.99 for r in renders), 'Missing restored world draw'
            if any(r.get('transitionHidden') is True for r in renders): failures.append((name,'world cart remained hidden after recovery'))
        dropped = lookup['dropped']
        assert dropped['worldCount']==1 and dropped['inventoryCount']==0 and rows[-1]['wall']-dropped['wall']>=1000, 'Missing successful retry/end state'
        summaries.append(summary)
    return dict(functionalPass=not failures, recoveryVerified=not failures, wheelCoverageVerified=not failures, failures=failures, cases=summaries,
        limit='SP ordinary cancellation through CancelAction and injected movement keys, before transfer. Bounded presentation/body/wheel checks accompany native stop and exact-item retry. Videos and full geometry require separate review; MP and exceptional interruptions remain separate.')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile',type=Path,required=True)
    parser.add_argument('--log',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--matrix',action='store_true')
    args=parser.parse_args()
    assert not args.output.exists(), 'Refuse to overwrite report'
    def read(name): return [decode(line) for line in (args.profile/name).read_text().splitlines()]
    try:
        result=analyze(args.log.read_text(errors='replace'), read('action-lifecycle.jsonl'),
                       read('body-clearance.jsonl'),read('wood-grip-poses.jsonl'),read('world-cart-poses.jsonl'),
                       read('wheel-roll-draws.jsonl'),read('action-tail-poses.jsonl'),matrix=args.matrix)
    except (AssertionError, ValueError, KeyError, OSError) as error:
        result=dict(functionalPass=False,recoveryVerified=False,wheelCoverageVerified=False,
                    failures=[str(error)],cases=[])
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    print(json.dumps(result,indent=2,allow_nan=False))
    return 0 if result['functionalPass'] else 1


if __name__=='__main__': raise SystemExit(main())
