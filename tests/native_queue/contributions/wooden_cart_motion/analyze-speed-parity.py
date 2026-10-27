"""Independent native bare/cart cruise comparison; acceleration and braking stay separate."""
import argparse
import json
import math
from pathlib import Path
import re

TYPES = {'wooden-wheelbarrow': 'SaucedWheelbarrow.WheelbarrowWood',
         'metal-wheelbarrow': 'SaucedWheelbarrow.WheelbarrowMetal', 'shopping-cart': 'SaucedCarts.ShoppingCart'}
TOLERANCE = .03  # Fixed before native execution; never infer tolerance from observed results.
PHASES = (('idle', 1200, 0), ('acceleration', 3000, 1), ('cruise', 5000, 1), ('braking', 2000, 0))
STATS = ('endurance', 'fatigue', 'pain', 'panic', 'hunger', 'thirst', 'stress')
MATCH = ('inventoryWeight', 'capacityWeight', 'maxWeight', 'walkSpeed', 'runSpeed', 'injury',
         'slowFactor', 'thermalMovement', 'heavyLoad', 'enduranceMoodle', 'painMoodle', *STATS)
NUMBERS = ('mono', 'wall', 'elapsed', 'phaseElapsed', 'frame', 'x', 'y', 'z', 'heading', 'gait', 'drive',
           'cartID', 'cargoID', 'cargoWeight', 'primaryID', 'secondaryID', 'cartCount', 'ballastID',
           'ballastWeight', 'targetWeight', 'targetMax', 'wornCount', 'skill', 'cartRunSpeedModifier', 'nativeRunSpeedModifier', 'leftScratch',
           'rightScratch', 'leftFracture', 'rightFracture', *MATCH)
BOOLS = ('run', 'sprint', 'runKey', 'sprintKey', 'female', 'full', 'motion', 'steering')
INTS = ('wall', 'frame', 'gait', 'drive', 'cartID', 'cargoID', 'primaryID', 'secondaryID',
        'cartCount', 'ballastID', 'maxWeight', 'targetMax', 'wornCount', 'skill',
        'heavyLoad', 'enduranceMoodle', 'painMoodle')


def scene_names():
    return [f'{sex}-{load}-{injury}' for sex in ('male', 'female') for load in ('empty', 'full')
            for injury in ('healthy', 'left-mild', 'left-heavy', 'right-mild', 'right-heavy')]


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def fail(message):
    raise ValueError(message)


def span(rows, begin, end, label):
    times = [r['mono'] for r in rows]
    if (len(times) < 5 or times[0] > begin + 150 or times[-1] < end - 150
            or any(not 0 < b-a <= 250 for a, b in zip(times, times[1:]))):
        fail('Incomplete speed temporal coverage: ' + label)


def speed(rows, heading):
    elapsed = (rows[-1]['mono'] - rows[0]['mono']) / 1000
    dx, dy = rows[-1]['x']-rows[0]['x'], rows[-1]['y']-rows[0]['y']
    forward = dx*math.cos(heading) + dy*math.sin(heading)
    lateral = -dx*math.sin(heading) + dy*math.cos(heading)
    distance = sum(math.hypot(b['x']-a['x'], b['y']-a['y']) for a, b in zip(rows, rows[1:]))
    return dict(seconds=elapsed, projectedDistanceTiles=forward, pathDistanceTiles=distance,
                lateralDistanceTiles=lateral, speedTilesPerSecond=forward/elapsed)


def track_valid(text, bare=False):
    if not isinstance(text, str) or not text:
        return False
    active = False
    for entry in text.split(';'):
        if not entry:
            continue
        match = re.fullmatch(r'([^=;]+)=([^@]+)@([^@;]+)', entry)
        if match is None:
            return False
        try:
            rate, weight = map(float, match.groups()[1:])
        except ValueError:
            return False
        if not math.isfinite(rate) or not math.isfinite(weight) or not 0 <= weight <= 1.001:
            return False
        name = match.group(1)
        cart_track = name.startswith(('ToolkitCart', 'Bob_Cart_')) or name.startswith('Toolkit_') and 'Cart' in name
        if bare and cart_track and weight > 0:
            return False
        active |= abs(rate) > .001 and weight > .01
    return active


def ordered_scene(events):
    expected = ['SCENE']
    for _ in range(6):
        expected += ['TRIAL', *[tag for _ in PHASES for tag in ('PHASE', 'PHASE_END')], 'TRIAL_END']
    expected += ['SCENE_END']
    if [tag for tag, _ in events if tag != 'SAMPLE'] != expected:
        fail('Missing, duplicated or reordered speed event phases')
    active_trial, active_phase = None, None
    for tag, row in events:
        if tag == 'TRIAL':
            active_trial = row.get('trial')
        elif tag == 'PHASE':
            active_phase = row.get('phase')
        elif tag == 'SAMPLE':
            if (row.get('trial') != active_trial or row.get('phase') != active_phase
                    or active_phase not in {p[0] for p in PHASES}):
                fail('Out-of-order speed phase sample')
        elif tag == 'PHASE_END':
            if row.get('trial') != active_trial or row.get('phase') != active_phase:
                fail('Out-of-order speed phase end')
            active_phase = None
        elif tag == 'TRIAL_END':
            if row.get('trial') != active_trial:
                fail('Out-of-order speed trial end')
            active_trial = None


def analyze(text, names=None, variant='wooden-wheelbarrow'):
    names = scene_names() if names is None else names
    if (variant not in TYPES or not names or len(set(names)) != len(names)
            or any(n not in scene_names() for n in names)):
        fail('Invalid speed scene/variant selection')
    if '[WOOD_BANK] RUN_STARTED' not in text:
        fail('Missing speed run boundary')
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[1]
    if '[WOOD_BANK] FAIL' in log or re.findall(r'\[WOOD_BANK\] ALL_COMPLETE cases=(\d+)(?:\s|$)', log) != [str(len(names))]:
        fail('Speed fixture failed or did not complete')
    starts = re.findall(r'\[WOOD_BANK\] CASE (\S+) attempt=(\d+) wall=(\d+)', log)
    completes = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    if ([r[0] for r in starts] != names or [r[0] for r in completes] != names
            or any(r[1] != '0' for r in starts) or [r[2] for r in starts] != [r[1] for r in completes]):
        fail('Missing, duplicated or reordered speed scene receipts')
    events = []
    for line in log.splitlines():
        if '[CART_SPEED] ' in line:
            tag, value = line.split('[CART_SPEED] ', 1)[1].split(' ', 1)
            if tag not in ('SCENE', 'TRIAL', 'PHASE', 'SAMPLE', 'PHASE_END', 'TRIAL_END', 'SCENE_END'):
                fail('Unknown speed event')
            row = json.loads(value)
            if not isinstance(row, dict) or row.get('case') not in names:
                fail('Unexpected speed scene telemetry')
            events.append((tag, row))
    summaries, failures = [], []
    previous_end = -1
    for name, _, scene_wall in starts:
        own = [(tag, row) for tag, row in events if row['case'] == name]
        ordered_scene(own)
        scenes = [r for t, r in own if t == 'SCENE']
        ends = [r for t, r in own if t == 'SCENE_END']
        if (len(scenes) != 1 or len(ends) != 1 or scenes[0].get('wall') != int(scene_wall)
                or scenes[0].get('cartType') != TYPES[variant] or scenes[0].get('fullBankCount') != 20
                or scenes[0].get('statsControl') != 'neutral-each-tick'):
            fail('Invalid speed scene contract: ' + name)
        scene = scenes[0]
        if (not finite(scene.get('targetWeight')) or scene['targetWeight'] < 0
                or type(scene.get('targetMax')) is not int or scene['targetMax'] <= 0):
            fail('Invalid speed target encumbrance')
        trials = [r for t, r in own if t == 'TRIAL']
        terminals = [r for t, r in own if t == 'TRIAL_END']
        if [r.get('trial') for r in trials] != list(range(1, 7)) or [r.get('trial') for r in terminals] != list(range(1, 7)):
            fail('Missing, duplicate or reordered speed trial receipts')
        sex, load, injury_name = name.split('-', 2)
        all_samples, measured, cruise_rows = [], [], []
        for i, (trial, terminal) in enumerate(zip(trials, terminals), 1):
            mode, gait = ('bare' if i % 2 else 'cart'), (i-1)//2
            if (trial.get('mode') != mode or trial.get('gait') != gait
                    or not finite(trial.get('mono')) or not finite(terminal.get('mono'))
                    or terminal['mono'] <= trial['mono'] or trial['mono'] < previous_end
                    or not finite(trial.get('heading')) or abs(trial['heading'] + 3*math.pi/4) > 1e-5):
                fail('Invalid speed trial contract')
            previous_end = terminal['mono']
            phase_events = [r for t, r in own if t == 'PHASE' and r.get('trial') == i]
            phase_ends = [r for t, r in own if t == 'PHASE_END' and r.get('trial') == i]
            rows = [r for t, r in own if t == 'SAMPLE' and r.get('trial') == i]
            all_samples += rows
            if [r.get('phase') for r in phase_events] != [p[0] for p in PHASES] or [r.get('phase') for r in phase_ends] != [p[0] for p in PHASES]:
                fail('Missing, duplicate or reordered speed phases')
            for row in rows:
                required = (*NUMBERS, *BOOLS, 'mode', 'cartType', 'statsControl', 'outfitIDs', 'nativeWeapon', 'heldModels', 'tracks')
                missing = sorted({key for key in required if key not in row})
                if missing:
                    fail('Missing speed telemetry fields: ' + ', '.join(missing))
                invalid = sorted({key for key in NUMBERS if not finite(row[key])})
                if invalid:
                    fail('Nonfinite/nonnumeric speed telemetry fields: ' + ', '.join(invalid))
                if (any(not finite(row.get(k)) for k in NUMBERS) or any(type(row.get(k)) is not bool for k in BOOLS)
                        or any(type(row.get(k)) is not int for k in INTS)
                        or row.get('mode') != mode or row.get('gait') != gait or row.get('cartType') != TYPES[variant]
                        or row.get('statsControl') != 'neutral-each-tick' or not isinstance(row.get('outfitIDs'), str)
                        or any(not isinstance(row.get(k), str) for k in ('nativeWeapon', 'heldModels'))
                        or row['female'] is not (sex == 'female') or row['full'] is not (load == 'full')
                        or row['wornCount'] != 3 or row['skill'] != 10 or row['cartID'] < 0
                        or abs(row['targetWeight']-scene['targetWeight']) > 1e-6 or row['targetMax'] != scene['targetMax']
                        or any(abs(row[k]-scene['targetWeight']) > .001 for k in ('inventoryWeight', 'capacityWeight'))
                        or row['maxWeight'] != scene['targetMax']
                        or abs(row['mono']-trial['mono']-row['elapsed']) > .01
                        or not trial['mono'] <= row['mono'] <= terminal['mono']):
                    fail('Invalid speed ownership/weight/state telemetry')
                if mode == 'bare':
                    if row['primaryID'] != -1 or row['secondaryID'] != -1 or row['cartCount'] != 0 or row['ballastID'] < 0 or row['ballastWeight'] < 0:
                        fail('Bare speed trial retained cart or lost ballast')
                elif row['primaryID'] != row['cartID'] or row['secondaryID'] != row['cartID'] or row['cartCount'] != 1 or row['ballastID'] != -1 or row['ballastWeight'] != 0:
                    fail('Cart speed trial lost exact hands or retained ballast')
                if abs(row['endurance']-1) > 1e-6 or any(abs(row[k]) > 1e-6 for k in STATS if k != 'endurance'):
                    fail('Speed controlled stats mismatch')
                if load == 'empty' and (row['cargoID'] != -1 or row['cargoWeight'] != 0) or load == 'full' and (row['cargoID'] < 0 or row['cargoWeight'] <= 0):
                    fail('Invalid speed cargo')
            span(rows, trial['mono'], terminal['mono'], name)
            if len({(r['ballastID'], r['ballastWeight']) for r in rows}) != 1:
                fail('Speed trial changed exact ballast identity/weight')
            if any(b['frame'] <= a['frame'] for a, b in zip(rows, rows[1:])):
                fail('Speed samples did not advance native frames')
            selected = None
            for j, ((phase, duration, drive), event, end) in enumerate(zip(PHASES, phase_events, phase_ends)):
                if (not finite(event.get('mono')) or not finite(end.get('mono'))
                        or event.get('drive') != drive or event.get('gait') != (gait if drive else 0)
                        or abs(event['mono']-(trial['mono'] if j == 0 else phase_ends[j-1]['mono'])) > .01
                        or not duration <= end['mono']-event['mono'] <= duration+250
                        or abs(end.get('elapsed', -1)-(end['mono']-event['mono'])) > .01):
                    fail('Invalid speed phase timing/input')
                section = [r for r in rows if r.get('phase') == phase]
                span(section, event['mono'], end['mono'], name + ':' + phase)
                if any(r['drive'] != drive or abs(r['phaseElapsed']-(r['mono']-event['mono'])) > .01
                       or not event['mono'] <= r['mono'] <= end['mono']
                       or r['runKey'] is not (drive == 1 and gait == 1)
                       or r['sprintKey'] is not (drive == 1 and gait == 2) for r in section):
                    fail('Speed phase sample/input mismatch')
                if phase == 'cruise':
                    selected = section
                if phase in ('idle', 'braking'):
                    tail = [r for r in section if r['mono'] >= end['mono']-400]
                    if len(tail) < 3 or any(r['run'] or r['sprint'] for r in tail) or math.dist((tail[0]['x'], tail[0]['y']), (tail[-1]['x'], tail[-1]['y'])) > .015:
                        failures.append([name, i, phase + ' did not settle'])
            if abs(phase_ends[-1]['mono']-terminal['mono']) > .01:
                fail('Speed terminal not at final phase boundary')
            native_gaits = {(r['run'], r['sprint']) for r in selected}
            if len(native_gaits) != 1:
                failures.append([name, i, 'native gait changed during cruise'])
            actual = 'sprint' if any(r['sprint'] for r in selected) else 'run' if any(r['run'] for r in selected) else 'walk'
            if gait == 0 and actual != 'walk' or injury_name == 'healthy' and actual != ('walk', 'run', 'sprint')[gait]:
                failures.append([name, i, 'native requested gait not achieved'])
            if ('walk', 'run', 'sprint').index(actual) > gait:
                failures.append([name, i, 'native gait exceeds requested gait'])
            for r in selected:
                if r['motion'] is not (mode == 'cart') or r['steering'] is not (mode == 'cart'):
                    fail('Speed cruise controller isolation mismatch')
                if mode == 'bare' and (r['nativeWeapon'] == 'cart' or r['heldModels'] != 'none|none'):
                    fail('Bare speed retained native held-cart state')
                if not track_valid(r.get('tracks'), bare=mode == 'bare'):
                    fail('Missing/invalid native speed tracks')
                if abs(math.atan2(math.sin(r['heading']-trial['heading']), math.cos(r['heading']-trial['heading']))) > .03:
                    failures.append([name, i, 'cruise heading changed'])
                wounds = {k: r[k] for k in ('leftScratch', 'rightScratch', 'leftFracture', 'rightFracture')}
                if injury_name == 'healthy':
                    valid = abs(r['injury']) <= .01 and max(wounds.values()) <= .01
                else:
                    side, severity = injury_name.split('-')
                    active = side + ('Scratch' if severity == 'mild' else 'Fracture')
                    valid = (wounds[active] > (5 if severity == 'mild' else 20)
                             and all(v <= .01 for k, v in wounds.items() if k != active)
                             and (r['injury'] > .15 if side == 'left' else r['injury'] < -.15))
                if not valid:
                    fail('Wrong native speed injury/severity/side')
            result = speed(selected, trial['heading'])
            if (result['speedTilesPerSecond'] <= .02 or abs(result['lateralDistanceTiles']) > .02
                    or result['pathDistanceTiles']-result['projectedDistanceTiles'] > .025):
                failures.append([name, i, 'cruise blocked, curved, reversed or stationary'])
            halves = [selected[:len(selected)//2+1], selected[len(selected)//2:]]
            half_speeds = [speed(part, trial['heading'])['speedTilesPerSecond'] for part in halves]
            if abs(half_speeds[0]-half_speeds[1])/max(result['speedTilesPerSecond'], .02) > .03:
                failures.append([name, i, 'cruise speed not settled'])
            accel = [r for r in rows if r['phase'] == 'acceleration']
            brake = [r for r in rows if r['phase'] == 'braking']
            result.update(trial=i, mode=mode, requestedGait=('walk', 'run', 'sprint')[gait], actualGait=actual,
                          demoted=actual != ('walk', 'run', 'sprint')[gait], samples=len(selected),
                          acceleration=speed(accel, trial['heading']), braking=speed(brake, trial['heading']))
            measured.append(result);cruise_rows.append(selected)
        if len({(r['cartID'], r['cargoID'], r['cargoWeight'], r['cartRunSpeedModifier'], r['outfitIDs']) for r in all_samples}) != 1:
            fail('Speed changed cart/cargo/outfit identity')
        pairs = []
        for i in range(0, 6, 2):
            bare, cart_result = measured[i:i+2]
            baseline, candidate = cruise_rows[i:i+2]
            mismatches = []
            for key in MATCH:
                tolerance = .001 if key in ('inventoryWeight', 'capacityWeight') else .002 if key in ('walkSpeed', 'runSpeed', 'injury', 'slowFactor') else 1e-6
                if max(abs(a[key]-b[key]) for a in baseline for b in candidate) > tolerance:
                    mismatches.append(key)
            for key in ('leftScratch', 'rightScratch', 'leftFracture', 'rightFracture'):
                if abs(baseline[0][key]-candidate[0][key]) > .15:
                    mismatches.append(key)
            if mismatches:
                failures.append([name, bare['requestedGait'], 'paired native state mismatch', mismatches])
            if bare['actualGait'] != cart_result['actualGait']:
                failures.append([name, bare['requestedGait'], 'paired native gait eligibility mismatch'])
            ratio = cart_result['speedTilesPerSecond']/bare['speedTilesPerSecond'] if bare['speedTilesPerSecond'] > .02 else None
            passed = ratio is not None and abs(ratio-1) <= TOLERANCE and not mismatches and bare['actualGait'] == cart_result['actualGait']
            if ratio is None or abs(ratio-1) > TOLERANCE:
                failures.append([name, bare['requestedGait'], 'cruise speed differs by more than fixed 3%', ratio])
            pairs.append(dict(requestedGait=bare['requestedGait'], actualGait=bare['actualGait'], demoted=bare['demoted'],
                              bareSpeedTilesPerSecond=bare['speedTilesPerSecond'], cartSpeedTilesPerSecond=cart_result['speedTilesPerSecond'],
                              cartToBareRatio=ratio, absoluteDifferenceTilesPerSecond=cart_result['speedTilesPerSecond']-bare['speedTilesPerSecond'],
                              pass_=passed))
        if not finite(ends[0].get('mono')) or abs(ends[0]['mono']-previous_end) > 250:
            fail('Invalid speed scene end')
        summaries.append(dict(scene=name, trials=measured, pairs=pairs))
    return dict(speedParityVerified=not failures, evidenceComplete=True, failures=failures, tolerance=TOLERANCE,
                fullBankCount=20, selectedScenes=names, partialCoverage=names != scene_names(), cartVariant=variant,
                scenes=summaries, geometryVerified=False, animationEquivalencePass=False,
                statsControl='Neutral endurance/fatigue/hunger/thirst/panic/stress/pain clamped each fixture tick; native moodles verified',
                scope='Native keyboard bare/cart straight cruise at equal effective carried weight, outfit, real foot injury and controlled stats; acceleration/braking reported separately; injury gait demotions are explicit.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--variant', choices=TYPES, default='wooden-wheelbarrow')
    parser.add_argument('--scene', action='append')
    args = parser.parse_args()
    report = analyze(args.log.read_text(errors='replace'), args.scene, args.variant)
    args.output.write_text(json.dumps(report, indent=2, allow_nan=False)+'\n')
    return 0 if report['speedParityVerified'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
