"""Measured relative-key movement only; grip, wheel, mesh and runtime gates stay separate."""
import argparse
import importlib.util
import json
import math
from pathlib import Path
import re

_clip_spec = importlib.util.spec_from_file_location('cart_native_clip_names', Path(__file__).with_name('clip_names.py'))
_clip_names = importlib.util.module_from_spec(_clip_spec)
_clip_spec.loader.exec_module(_clip_names)
native_clip = _clip_names.native_clip

SPECS = ('arcs', 'slalom-up', 'slalom-down')
SCENES = tuple(f'{sex}-{load}-{gait}-{spec}' for sex in ('male', 'female')
               for load in ('empty', 'full') for gait in ('walk', 'run', 'sprint') for spec in SPECS)
DURATIONS = {'arcs': 90000, 'slalom-up': 20000, 'slalom-down': 20000}

def wrap(value):
    return math.atan2(math.sin(value), math.cos(value))

def schedule(name):
    sex, load, gait, spec = name.split('-', 3)
    level = ('walk', 'run', 'sprint').index(gait)
    result = []
    def add(phase, drive, requested, duration=0, target=0):
        result.append(dict(phase=phase, drive=drive, gait=requested, duration=duration,
                           target=target, deadline=2000 + abs(math.degrees(target))*50 if target else duration+500))
    add('idle', 0, 0, 800)
    add('straight', 1, level, 2200)
    if spec == 'arcs':
        for side, drive, sign in (('left', 5, -1), ('right', 8, 1)):
            for degrees in (45, 90, 135, 180):
                add(f'arc-{side}{degrees}', drive, level, target=math.radians(degrees)*sign)
                add(f'release-{side}{degrees}', 1, level, 800)
        add('stop-arc', 5, level, target=-math.pi/4)
    else:
        for interval in (300, 600, 900):
            for switch in range(1, 5):
                add(f'slalom-{interval}-{switch}', 5 if switch % 2 else 8, level, interval)
        add('release', 1, level, 800)
    add('stop', 0, 0, 3500)
    add('tail', 0, 0)
    return result

def selection(expected_scenes):
    if expected_scenes is None:
        return SCENES
    assert isinstance(expected_scenes, (list, tuple)) and expected_scenes, 'Empty scene selection'
    assert all(isinstance(n, str) and n in SCENES for n in expected_scenes), 'Unknown scene selection'
    assert len(set(expected_scenes)) == len(expected_scenes), 'Duplicate scene selection'
    return tuple(n for n in SCENES if n in expected_scenes)

def finite(row, keys):
    for key in keys:
        assert type(row.get(key)) in (int, float) and math.isfinite(row[key]), 'Missing/nonfinite field: '+key

def tracks(root):
    assert isinstance(root, str) and ',rootTracks:' in root, 'Missing native root tracks'
    result = {}
    for entry in root.split(',rootTracks:', 1)[1].split(';'):
        if not entry:
            continue
        name, values = entry.rsplit('@', 1)
        weight, time, speed = map(float, values.split('/'))
        assert all(map(math.isfinite, (weight, time, speed))), 'Nonfinite root track'
        if weight > .15 and speed > 0:
            result.setdefault(name, []).append(time)
    return result

def moving_clock_stall(state, row, clip, clocks):
    """Sampled moving-time stall, preserving continuity through same-gait phases.

    A changed native clock includes ordinary loop wrap. Half a second permits
    several ordinary samples or the maximum allowed capture gap; it is not a
    claim that every rendered frame advanced. Nonmoving/gait-transition gaps
    reset the moving-time budget. Same-tick phase-edge copies do not reset it.
    """
    previous = state.get('previous')
    if previous is not None and row['wall'] == previous['wall'] and clip == state.get('clip'):
        return state.get('frozenMs', 0.)
    frozen = state.get('frozenMs', 0.)
    if (previous is None or clip != state.get('clip') or not clocks or not state.get('clocks')
            or math.hypot(row['x']-previous['x'], row['y']-previous['y']) <= 1e-6):
        frozen = 0.
    else:
        before, after = state['clocks'], tuple(sorted(clocks))
        # A field crossfade can add/remove an instance of the same clip. It is
        # not itself clock progress; the next sample can compare the new set.
        changed = len(before) == len(after) and any(abs(a-b) > 1e-6 for a,b in zip(before,after))
        frozen = 0. if changed else frozen + row['wall']-previous['wall']
    state.update(previous=row, clip=clip, clocks=tuple(sorted(clocks)) if clocks else (), frozenMs=frozen)
    return frozen



def slalom_response(rows, load, sign, direct_opposite):
    """Bracket sampled response; never infer an exact sub-sample zero crossing.

    woodenStep keeps old yaw on opposite input, braking at 6 rad/s². Its
    integration step is capped at .1s; allow one such update for input delivery
    and discrete integration. Sampling adds uncertainty to the crossing bracket,
    not to the permitted old-direction angular excursion.
    """
    cap, acceleration, update_uncertainty, angle_noise = 1.6-.3*(load=='full'), 6., .1, .003
    intervals = [(a['phaseElapsed']/1000, b['phaseElapsed']/1000,
                  sign*wrap(b['acceptedHeading']-a['acceptedHeading'])) for a,b in zip(rows,rows[1:])]
    deadline = update_uncertainty+cap/acceleration
    # Integral of the maximum residual old-direction rate, including one
    # delayed native update. This bounds each interval and the whole excursion.
    def old_yaw(t):
        delayed = min(t,update_uncertainty)*cap
        braking = min(max(0.,t-update_uncertainty),cap/acceleration)
        return delayed+cap*braking-.5*acceleration*braking*braking
    opposite = sum(max(0.,-delta) for _,_,delta in intervals)
    net = sum(delta for _,_,delta in intervals)
    terminal = intervals[-1][2]/(intervals[-1][1]-intervals[-1][0])
    first_requested = next((i for i,(_,_,d) in enumerate(intervals) if d>angle_noise),None)
    bracket = None
    if first_requested is not None:
        preceding_old = [a for a,_,d in intervals[:first_requested] if d < -angle_noise]
        bracket = [1000*(preceding_old[-1] if preceding_old else 0.),1000*intervals[first_requested][1]]
    achieved = net >= .015 and terminal > .03
    failures = []
    if direct_opposite:
        if opposite > old_yaw(intervals[-1][1])+angle_noise:
            failures.append('Opposite slalom excursion exceeded bounded braking response')
        if any(-d > old_yaw(b)-old_yaw(a)+angle_noise for a,b,d in intervals):
            failures.append('Opposite slalom yaw persisted beyond bounded braking response')
        if first_requested is not None and any(d < -angle_noise for _,_,d in intervals[first_requested+1:]):
            failures.append('Slalom returned to the old direction after sampled response')
        if rows[-1]['phaseElapsed'] >= 600:
            settled = [(a,b,d) for a,b,d in intervals if a>=deadline]
            if not settled:
                failures.append('Insufficient samples after slalom braking deadline')
            if not achieved or first_requested is None or any(d < -angle_noise for _,_,d in settled):
                failures.append('Long slalom hold did not settle in the requested direction')
    return dict(directOppositeInput=direct_opposite, sampledOppositeExcursion=opposite,
                responseCrossingBracketMs=bracket, terminalSignedRate=terminal, netRequestedYaw=net,
                requestedDirectionAchieved=achieved, oldYawDeadlineMs=1000*deadline,
                oppositeExcursionBudget=old_yaw(intervals[-1][1])+angle_noise,
                inputUpdateUncertaintyMs=1000*update_uncertainty,
                maxSampleIntervalMs=1000*max(b-a for a,b,_ in intervals)), failures


def selected_capture(text, expected_scenes=None):
    expected = selection(expected_scenes)
    assert '[WOOD_BANK] RUN_STARTED' in text, 'Missing run boundary'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[1]
    assert '[WOOD_BANK] FAIL' not in log, 'Scenario failed'
    complete = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    assert tuple(n for n, _ in complete) == expected, 'Missing, duplicate or reordered scene completion'
    assert re.findall(r'\[WOOD_BANK\] ALL_COMPLETE cases=(\d+)', log) == [str(len(expected))], 'Missing or duplicate final completion'
    starts = {name: int(start) for name, start in complete}
    attempts = re.findall(r'\[WOOD_BANK\] CASE (\S+) attempt=\d+ wall=(\d+)', log)
    assert all(attempts.count((n, str(s))) == 1 for n, s in starts.items()), 'Missing selected attempt'
    records = {name: [] for name in expected}
    active = None
    for line in log.splitlines():
        boundary = re.search(r'\[WOOD_BANK\] CASE (\S+) attempt=\d+ wall=(\d+)', line)
        if boundary:
            active = boundary[1] if starts.get(boundary[1]) == int(boundary[2]) else None
        marker = re.search(r'\[CART_MATRIX\] (PHASE|SAMPLE|END) (\{.*\})$', line)
        if marker and active is not None:
            row = json.loads(marker[2])
            assert isinstance(row, dict) and row.get('case') == active, 'Mismatched scene telemetry'
            records[active].append((marker[1], row))
        if re.search(r'\[WOOD_BANK\] COMPLETE ', line):
            active = None
    return records, starts

def baggy_outfit(row, female):
    assert type(row.get('female')) is bool and row['female'] is female, 'Wrong/missing outfit body model'
    assert row.get('wornCount') == 3, 'Non-deterministic fixture outfit'
    assert row.get('pantsType') == 'Base.Trousers_JeanBaggy', 'Missing worn baggy jeans'
    assert type(row.get('pantsID')) is int and row['pantsID'] > 0, 'Missing worn jeans identity'
    model = row.get('pantsModel')
    assert isinstance(model, str), 'Missing native trousers model'
    model = model.lower().replace('\\', '/').removesuffix('.x')
    assert model == 'skinned/clothes/' + ('kate' if female else 'bob') + '_trousers', 'Wrong native trousers model'
    return row['pantsID'], model


def analyze(text, expected_scenes=None, *, require_baggy_jeans=False):
    captures, starts = selected_capture(text, expected_scenes)
    failures, results, rapid_limitations = [], [], []
    for name, events in captures.items():
        expected = schedule(name)
        sex, load, gait, spec = name.split('-', 3)
        start = starts[name]
        position, phase_results, identity = 0, [], None
        previous_end = start
        initial_heading = None
        previous_sample = None
        clock_state = {}
        outfit_identity, outfit_samples, sample_count = None, 0, 0
        def fail(phase, reason, value=None):
            failures.append(dict(case=name, phase=phase, reason=reason, value=value))
        for index, contract in enumerate(expected, 1):
            phase = contract['phase']
            direct_opposite = (phase.startswith('slalom-') and index > 1
                               and expected[index-2]['phase'].startswith('slalom-')
                               and {contract['drive'],expected[index-2]['drive']} == {5,8})
            assert position < len(events) and events[position][0] == 'PHASE', 'Missing/reordered phase: '+phase
            begin = events[position][1]
            position += 1
            finite(begin, ('index', 'wall', 'drive', 'gait', 'duration', 'target', 'deadline'))
            assert begin['index'] == index and begin.get('phase') == phase, 'Missing/reordered phase: '+phase
            assert begin['wall'] == previous_end, 'Gap between command phases'
            for key in ('drive', 'gait', 'target'):
                assert abs(begin[key]-contract[key]) < 1e-8, 'Wrong phase control/target: '+phase
            if phase == 'tail':
                duration = start+DURATIONS[spec]-begin['wall']
                assert duration >= 1000, 'Insufficient final quiet window'
                deadline = duration+500
            else:
                duration, deadline = contract['duration'], contract['deadline']
            assert abs(begin['duration']-duration) < 1e-8 and abs(begin['deadline']-deadline) < 1e-8, 'Changed phase duration/deadline'
            rows = []
            while position < len(events) and events[position][0] == 'SAMPLE':
                row = events[position][1]
                position += 1
                assert row.get('phase') == phase and row.get('index') == index, 'Sample in wrong phase'
                finite(row, ('wall', 'elapsed', 'phaseElapsed', 'frame', 'x', 'y', 'heading', 'acceptedHeading', 'yaw', 'drive', 'gait', 'skill', 'stepX', 'stepY', 'id', 'cargoWeight'))
                for key in ('run', 'sprint', 'forward', 'backward', 'left', 'right', 'runKey', 'sprintKey'):
                    assert type(row.get(key)) is bool, 'Missing/invalid actual input/gait flag'
                assert row['wall']-start == row['elapsed'] and row['wall']-begin['wall'] == row['phaseElapsed'], 'Mismatched sample clock'
                assert (row['drive'], row['gait']) == (contract['drive'], contract['gait']), 'Wrong sampled command'
                drive, requested = contract['drive'], contract['gait']
                expected_keys = (drive in (1, 5, 8), False, drive == 5, drive == 8, requested == 1, requested == 2)
                assert tuple(row[k] for k in ('forward','backward','left','right','runKey','sprintKey')) == expected_keys, 'Actual native keys disagree with phase'
                assert row['skill'] == 10, 'Missing controlled Sprint eligibility'
                sample_count += 1
                if require_baggy_jeans or any(key in row for key in ('female','wornCount','pantsType','pantsID','pantsModel')):
                    current_outfit = baggy_outfit(row, sex == 'female')
                    outfit_identity = current_outfit if outfit_identity is None else outfit_identity
                    assert current_outfit == outfit_identity, 'Worn jeans identity changed'
                    outfit_samples += 1
                assert type(row.get('cargoIDs')) is str and row['id'] > 0, 'Missing exact cart/cargo identity'
                current = row['id'], row['cargoIDs'], row['cargoWeight']
                identity = current if identity is None else identity
                assert identity == current, 'Cart/cargo changed during movement'
                assert (load == 'empty' and row['cargoIDs'] == 'empty' and row['cargoWeight'] == 0
                        or load == 'full' and row['cargoIDs'] != 'empty' and row['cargoWeight'] > 0), 'Wrong scene load'
                row['tracks'] = tracks(row['root'])
                gait_ok = ((not row['run'] and not row['sprint']) if requested == 0
                           else row['run'] and not row['sprint'] if requested == 1 else row['sprint'])
                clip = 'Bob_'+('Walk','Run','Sprint')[requested] if drive else None
                clocks = [time for name, times in row['tracks'].items() if native_clip(name) == clip for time in times] if gait_ok else ()
                if moving_clock_stall(clock_state, row, clip, clocks) > 500:
                    fail(phase, 'Matching native gait clock froze through more than 500ms of measured movement')
                rows.append(row)
            assert position < len(events) and events[position][0] == 'END', 'Missing phase completion: '+phase
            end = events[position][1]
            position += 1
            finite(end, ('index', 'wall', 'elapsed', 'yaw'))
            assert end.get('phase') == phase and end['index'] == index, 'Reordered phase completion'
            assert end['wall']-begin['wall'] == end['elapsed'], 'Mismatched end clock'
            assert 0 < end['elapsed'] <= deadline, 'Phase deadline exceeded'
            if not contract['target']:
                assert duration <= end['elapsed'] <= duration+500, 'Truncated/late timed phase'
            assert len(rows) >= 3 and rows[0]['wall'] == begin['wall'] and rows[-1]['wall'] == end['wall'], 'Incomplete phase sample edges'
            intervals = [b['wall']-a['wall'] for a,b in zip(rows, rows[1:])]
            assert min(intervals) > 0 and max(intervals) <= 500, 'Sample cadence exceeds 500ms'
            assert all(b['frame'] > a['frame'] for a,b in zip(rows,rows[1:])), 'Native frame progression missing'
            assert abs(rows[0]['yaw']) < .000001, 'Phase yaw origin missing'
            if previous_sample is not None:
                assert math.hypot(rows[0]['x']-previous_sample['x'], rows[0]['y']-previous_sample['y']) < .0001 and abs(wrap(rows[0]['acceptedHeading']-previous_sample['acceptedHeading'])) < .0001, 'Pose reset/discontinuity inside recording'
            previous_sample = rows[-1]
            previous_end = end['wall']
            if initial_heading is None:
                initial_heading = rows[0]['acceptedHeading']
                target = math.pi/4 if spec == 'slalom-down' else -math.pi*3/4
                if abs(wrap(initial_heading-target)) > .025:
                    fail(phase, 'Wrong initial screen heading', initial_heading)
            travel, distance, signed_yaw, motionless_yaw = 0., 0., 0., 0.
            for a,b in zip(rows,rows[1:]):
                delta = wrap(b['acceptedHeading']-a['acceptedHeading'])
                signed_yaw += delta
                if abs(b['yaw']-signed_yaw) > .002:
                    fail(phase, 'Yaw telemetry disagrees with measured heading')
                dx,dy = b['x']-a['x'], b['y']-a['y']
                norm = math.hypot(dx,dy)
                signed = dx*math.cos(a['acceptedHeading']+delta/2)+dy*math.sin(a['acceptedHeading']+delta/2)
                travel += signed
                distance += norm
                if norm > 10*(b['wall']-a['wall'])/1000+.02:
                    fail(phase, 'Implausible native displacement', norm)
                if contract['drive']:
                    turn_sign = (1 if contract['target']>0 else -1) if contract['target'] else (-1 if contract['drive']==5 else 1 if contract['drive']==8 else 0)
                    if turn_sign and not direct_opposite and delta*turn_sign < -.003:
                        fail(phase, 'Steering reversed inside a held arc', delta)
                    if abs(delta) > 3*(b['wall']-a['wall'])/1000+.03:
                        fail(phase, 'Native heading changed discontinuously', delta)
                    if signed < -.004:
                        fail(phase, 'Forward input moved backward', signed)
                    motionless_yaw = motionless_yaw+abs(delta) if norm <= .002 else 0
                    if motionless_yaw > math.radians(2):
                        fail(phase, 'Arc rotated without measured forward motion', motionless_yaw)
            if abs(end['yaw']-signed_yaw) > .002:
                fail(phase, 'End yaw disagrees with native heading')
            if contract['drive']:
                if travel <= .01 or distance <= .01 or travel < .7*distance:
                    fail(phase, 'Missing measured forward motion', travel)
                if contract['target']:
                    target=contract['target']
                    if not abs(target)-.002 <= signed_yaw*(1 if target>0 else -1) <= abs(target)+.18:
                        fail(phase, 'Arc missed measured target or overshot', signed_yaw)
                elif phase.startswith('slalom-'):
                    expected_sign = -1 if contract['drive']==5 else 1
                    if not direct_opposite and signed_yaw*expected_sign < .015:
                        fail(phase, 'Slalom steering missing/wrong sign', signed_yaw)
                elif phase.startswith('release') or phase == 'straight':
                    if abs(signed_yaw) > .025 or sum(abs(wrap(b['acceptedHeading']-a['acceptedHeading'])) for a,b in zip(rows,rows[1:])) > .04:
                        fail(phase, 'Steering continued after release', signed_yaw)
                # Require sustained actual gait flags plus advancing matching native root clips.
                # The initial straight allows native acceleration/eligibility to settle first.
                eligible = [r for r in rows if r['phaseElapsed'] >= (1000 if phase=='straight' else 150)]
                clip_word = ('Walk','Run','Sprint')[contract['gait']]
                matched=[]
                for row in eligible:
                    gait_ok = ((not row['run'] and not row['sprint']) if contract['gait']==0
                               else row['run'] and not row['sprint'] if contract['gait']==1 else row['sprint'])
                    active = {clip: times for clip,times in row['tracks'].items() if native_clip(clip) == 'Bob_'+clip_word}
                    if gait_ok and active and row['stepY'] > .05:
                        matched.append((row,active))
                if len(matched) < 2 or len(matched) < .6*len(eligible):
                    fail(phase, 'Requested gait was not sustained in native flags/root clips', len(matched))
                progressing = any(set(a) & set(b) and any(a[k] != b[k] for k in set(a)&set(b))
                                  for (_,a),(_,b) in zip(matched,matched[1:]))
                if not progressing:
                    fail(phase, 'Native gait root clip did not progress')
            else:
                quiet = [r for r in rows if r['wall'] >= end['wall']-500]
                drift = sum(math.hypot(b['x']-a['x'],b['y']-a['y']) for a,b in zip(quiet,quiet[1:]))
                quiet_yaw = sum(abs(wrap(b['acceptedHeading']-a['acceptedHeading'])) for a,b in zip(quiet,quiet[1:]))
                if len(quiet)<3 or drift > .025 or quiet_yaw > .025 or any(r['run'] or r['sprint'] for r in quiet):
                    fail(phase, 'Neutral state did not settle', dict(drift=drift,yaw=quiet_yaw))
            result = dict(phase=phase, elapsed=end['elapsed'], samples=len(rows), signedYaw=signed_yaw, forwardTravel=travel, distance=distance)
            if phase.startswith('slalom-'):
                response, response_failures = slalom_response(rows,load,-1 if contract['drive']==5 else 1,direct_opposite)
                result.update(response)
                for reason in response_failures:
                    fail(phase,reason,response)
                if contract['duration']==300 and not response['requestedDirectionAchieved']:
                    rapid_limitations.append(dict(case=name,phase=phase,netRequestedYaw=response['netRequestedYaw'],
                                                  terminalSignedRate=response['terminalSignedRate'],
                                                  reason='300ms hold did not achieve net yaw in the requested direction'))
            phase_results.append(result)
        assert position == len(events), 'Unexpected telemetry after final phase'
        assert DURATIONS[spec] <= previous_end-start <= DURATIONS[spec]+500, 'Truncated fixed recording window'
        results.append(dict(case=name, duration=previous_end-start, phases=phase_results,
                            baggyJeansVerified=outfit_samples == sample_count and sample_count > 0))
    return dict(complete=True, caseCount=len(results), fullSceneCount=len(SCENES), matrixComplete=tuple(captures)==SCENES,
                scope='full-matrix' if expected_scenes is None else 'selected-scenes', expectedScenes=list(captures),
                inputScheme='relative-keyboard-v1', motionPass=not failures, motionFailures=failures, cases=results,
                baggyJeansVerified=all(row['baggyJeansVerified'] for row in results),
                rapidResponsePass=not rapid_limitations, rapidResponseLimitations=rapid_limitations,
                limit='Measured SP relative keyboard movement with bounded existing steering inertia. Rapid 300ms requested-direction response is reported independently by rapidResponsePass/rapidResponseLimitations. Sampled heading, positions, native gait and controls do not establish grip, wheel support, body/clothing clearance, visual quality, runtime cleanliness or multiplayer correctness.')

def parse_scenes(value):
    return json.loads(value) if value.lstrip().startswith('[') else [v.strip() for v in value.split(',')]

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile',type=Path,required=True)
    parser.add_argument('--log',type=Path)
    parser.add_argument('--scenes',type=parse_scenes)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--require-baggy-jeans',action='store_true',help='Require stable live worn-jeans identity and the calibrated native model in every sample')
    args=parser.parse_args()
    assert args.profile.is_dir(), 'Missing capture profile'
    assert not args.output.exists(), 'Refuse to overwrite existing report'
    result=analyze((args.log or args.profile/'console.txt').read_text(errors='replace'),args.scenes,require_baggy_jeans=args.require_baggy_jeans)
    with args.output.open('x') as target:
        json.dump(result,target,indent=2,allow_nan=False);target.write('\n')
    print(json.dumps(result,indent=2,allow_nan=False))
    return 0 if result['motionPass'] else 1

if __name__=='__main__':
    raise SystemExit(main())
