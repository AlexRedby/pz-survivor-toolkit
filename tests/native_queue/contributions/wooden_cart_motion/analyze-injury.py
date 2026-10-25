"""Verify real BodyDamage and native cart injury motion; preserve visual review separately."""
import argparse
import json
import math
from pathlib import Path
import re
import xml.etree.ElementTree as ET

# Current cart directional clip and the native clip used by historical captures.
BACKWARD_CLIPS = {'Toolkit_CartPivot_Backward', 'Bob_WalkBwdNoAim1Hand'}

PHASES = (
    ('forward', 0, 1, 0), ('left', 1800, 5, 0), ('right', 3000, 8, 0),
    ('reverse', 4200, 4, 0), ('run-request', 5600, 1, 1),
    ('sprint-request', 6800, 1, 2), ('stop', 8000, 0, 0),
    ('healed-forward', 9000, 1, 0), ('healed-stop', 11000, 0, 0))
TYPES = {'wooden-wheelbarrow': 'SaucedWheelbarrow.WheelbarrowWood',
         'metal-wheelbarrow': 'SaucedWheelbarrow.WheelbarrowMetal',
         'shopping-cart': 'SaucedCarts.ShoppingCart'}
MODELS = {'wooden-wheelbarrow': {'WheelbarrowWood'}, 'metal-wheelbarrow': {'WheelbarrowMetal'},
          'shopping-cart': {'ShoppingCartModel', 'ShoppingCartPartialModel', 'ShoppingCartFullModel',
                            'ShoppingCartFlashlightModel', 'ShoppingCartFlashlightPartialModel', 'ShoppingCartFlashlightFullModel'}}


def scene_names():
    return [f'{sex}-{load}-{side}-{severity}' for sex in ('male', 'female')
            for load in ('empty', 'full') for side in ('left', 'right') for severity in ('mild', 'heavy')]


def finite(value):
    return type(value) in (int, float) and math.isfinite(value)


def tracks(text):
    result = []
    for value in text.split(';'):
        if not value:
            continue
        match = re.fullmatch(r'([^=;]+)=([^@]+)@([^@;]+)', value)
        if match is None:
            raise ValueError('Malformed injury animation track')
        name, speed, weight = match.groups()
        speed, weight = float(speed), float(weight)
        if not finite(speed) or not finite(weight) or not 0 <= weight <= 1.001:
            raise ValueError('Invalid injury animation track')
        result.append(dict(name=name, speed=speed, weight=weight))
    return result


def _walk_source(game):
    """Verify the independent native field behind the B42.21 analytical oracle."""
    if game is None:
        return 'B42.21 defaultWalk baseline (no native source supplied)'
    path = Path(game) / 'media/AnimSets/player/movement/defaultWalk.xml'
    node = ET.parse(path).getroot()
    expected = {'Bob_WalkLightLimpR': (.5, 1), 'Bob_WalkLightLimpL': (-.5, 1),
                'Bob_WalkHeavyLimpR': (1, 1), 'Bob_WalkHeavyLimpL': (-1, 1),
                'Bob_Walk': (0, 1), 'Bob_WalkSlow': (0, 0)}
    points = {r.findtext('m_AnimName'): (float(r.findtext('m_XPos')), float(r.findtext('m_YPos')))
              for r in node.findall('m_2DBlends')}
    references = {int(r.attrib['referenceID']): r.findtext('m_AnimName') for r in node.findall('m_2DBlends')}
    triangles = [tuple(int(t.findtext('node' + str(i))) for i in (1, 2, 3)) for t in node.findall('m_2DBlendTri')]
    if (node.findtext('m_Name') != 'defaultWalk' or node.findtext('m_Scalar') != 'WalkInjury'
            or node.findtext('m_Scalar2') != 'WalkSpeed' or points != expected
            or references != dict(enumerate(expected, 1))
            or triangles != [(2, 4, 6), (5, 2, 6), (6, 1, 5), (6, 3, 1)]):
        raise ValueError('Native defaultWalk topology differs from the injury oracle')
    return str(path)


def walk_components(injury, speed):
    """Native defaultWalk triangles; out-of-hull Pick inflates coordinates by 1.1."""
    x, y = abs(injury), speed
    # Host can retain its native negative injury-adjusted RunSpeed briefly
    # after returning to Walk. Pick projects that point onto the same hull.
    if not finite(y) or y > 1 or x > 1.001:
        raise ValueError('Unsupported native injury walk coordinates')
    if x > y:
        light, heavy = 0, max(0, min(1, 1.1 * (x + y) / 2))
    else:
        light, heavy = max(0, 2 * min(x, y - x)), max(0, 2 * x - y)
    suffix = 'R' if injury > 0 else 'L'
    return {'Bob_WalkLightLimp' + suffix: light, 'Bob_WalkHeavyLimp' + suffix: heavy}


def _walk_mix(row):
    expected = walk_components(row['injury'], row['walkSpeed'])
    active = {c['name']: c['weight'] for c in row['clips'] if abs(c['speed']) > .001}
    mass = sum(active.get(name, 0) for name in expected)
    total = sum(expected.values())
    if mass <= 1e-4 or total <= 1e-4:
        return False
    if any('Walk' in name and 'Limp' in name and name not in expected and weight > .01 for name, weight in active.items()):
        return False
    # Directional blending scales the entire native forward component. Compare
    # its conditional Light/Heavy ratio, not an absolute arc weight or wound name.
    return all(abs(active.get(name, 0) / mass - weight / total) <= .02 for name, weight in expected.items())


def _reverse(rows, since, require_rest=True):
    first = next((i for i, r in enumerate(rows) if r['stepY'] < -.001), None)
    if first is None:
        return dict(pass_=False, reason='backward input never engaged')
    before, backward = rows[:first], rows[first:]
    resting = any(abs(a['stepY']) <= .01 and abs(b['stepY']) <= .01
                  and 0 < b['wall'] - a['wall'] <= 500
                  and math.hypot(b['x'] - a['x'], b['y'] - a['y']) <= .002
                  for a, b in zip(before, before[1:]))
    travel = [(b['x'] - a['x']) * math.cos(a['heading']) + (b['y'] - a['y']) * math.sin(a['heading'])
              for a, b in zip(backward, backward[1:])]
    passed = ((resting or not require_rest) and len(backward) >= 5 and backward[-1]['elapsed'] - backward[0]['elapsed'] >= 200
              and all(r['stepY'] < 0 for r in backward) and sum(travel) < -.03
              and sum(max(0, d) for d in travel) <= .002)
    return dict(pass_=passed, restBeforeReverse=resting, restRequired=require_rest,
                reverseStartDelayMs=backward[0]['elapsed'] - since,
                backwardSamples=len(backward), forwardTravelTiles=sum(travel),
                positiveTravelAfterReverseTiles=sum(max(0, d) for d in travel))


def _span(rows, key, start, end, label):
    times = sorted({r[key] for r in rows})
    if (len(times) < 5 or times[0] > start + 500 or times[-1] < end - 500
            or any(not 0 < b - a <= 500 for a, b in zip(times, times[1:]))):
        raise ValueError('Incomplete injury ' + label + ' temporal coverage')


def _probes(profile, start, end, female, variant):
    result = {}
    for kind, filename in (('body', 'body-clearance.jsonl'), ('grip', 'wood-grip-poses.jsonl')):
        records = [json.loads(line) for line in (Path(profile) / filename).read_text().splitlines()]
        rows = [r for r in records if start <= r.get('wallTimeMillis', -1) < end]
        _span(rows, 'wallTimeMillis', start, end, kind)
        for row in rows:
            matrices = [row.get('cart'), *row.get('bones', {}).values()]
            if (row.get('model') not in MODELS[variant] or row.get('female') is not female
                    or not row.get('bones') or any(not isinstance(m, list) or len(m) != 16
                    or not all(finite(v) for v in m) for m in matrices)):
                raise ValueError('Mismatched injury ' + kind + ' render matrices')
            if kind == 'grip' and (row.get('result') is not True or row.get('threw') is not False):
                raise ValueError('Injury cart grip solve failed')
        result[kind + 'Samples'] = len(rows)
    return result


def analyze(text, names=None, variant='wooden-wheelbarrow', profile=None, game=None):
    if game is None and profile is not None and (Path(profile).parent / 'runtime.json').is_file():
        game = json.loads((Path(profile).parent / 'runtime.json').read_text())['game']
    native_source = _walk_source(game)
    names = scene_names() if names is None else names
    if (not names or len(set(names)) != len(names) or any(n not in scene_names() for n in names)
            or variant not in TYPES):
        raise ValueError('Invalid injury scene/variant selection')
    if '[WOOD_BANK] RUN_STARTED' not in text:
        raise ValueError('Missing injury run boundary')
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[1]
    if '[WOOD_BANK] FAIL' in log or re.findall(r'\[WOOD_BANK\] ALL_COMPLETE cases=(\d+)(?:\s|$)', log) != [str(len(names))]:
        raise ValueError('Injury fixture failed or did not complete')
    receipts = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+) file=.+? frames=(\d+) seconds=([\d.]+)', log)
    attempts = re.findall(r'\[WOOD_BANK\] CASE (\S+) attempt=(\d+) wall=(\d+)', log)
    if ([r[0] for r in receipts] != names or [r[0] for r in attempts] != names
            or any(a != '0' for _, a, _ in attempts)
            or [r[1] for r in receipts] != [r[2] for r in attempts]):
        raise ValueError('Missing, duplicated or reordered injury scene receipts')
    samples = [json.loads(line.split('[CART_INJURY] SAMPLE ', 1)[1]) for line in log.splitlines() if '[CART_INJURY] SAMPLE ' in line]
    events = [json.loads(line.split('[CART_INJURY] PHASE ', 1)[1]) for line in log.splitlines() if '[CART_INJURY] PHASE ' in line]
    ends = [json.loads(line.split('[CART_INJURY] END ', 1)[1]) for line in log.splitlines() if '[CART_INJURY] END ' in line]
    if [r.get('case') for r in ends] != names:
        raise ValueError('Missing, duplicated or reordered injury recording ends')
    if any(r.get('case') not in names for r in samples + events):
        raise ValueError('Unexpected injury scene telemetry')
    summaries, failures = [], []
    previous_end = -1
    for name, start, frames, seconds in receipts:
        start = int(start)
        terminal = next(r for r in ends if r['case'] == name)
        if (any(type(terminal.get(k)) is not int for k in ('start', 'wall', 'elapsed'))
                or terminal['start'] != start or terminal['wall'] - start != terminal['elapsed']
                or not 12000 <= terminal['elapsed'] <= 30000):
            raise ValueError('Invalid injury recording end')
        duration = terminal['elapsed']
        if start < previous_end or int(frames) <= 0 or abs(float(seconds) * 1000 - duration) > 500:
            raise ValueError('Invalid injury recording window')
        previous_end = terminal['wall']
        sex, cargo, side, severity = name.split('-')
        rows = [r for r in samples if r['case'] == name]
        phase_events = [r for r in events if r['case'] == name]
        if [r.get('phase') for r in phase_events] != [p[0] for p in PHASES]:
            raise ValueError('Missing or reordered injury phase events: ' + name)
        for i, (event, (phase, planned, drive, gait)) in enumerate(zip(phase_events, PHASES)):
            preceding = phase_events[i - 1]['elapsed'] if i else 0
            requested = planned - PHASES[i - 1][1] if i else 0
            interval = event['elapsed'] - preceding if type(event.get('elapsed')) is int else -1
            if (any(type(event.get(k)) is not int for k in ('start', 'wall', 'elapsed', 'drive', 'gait'))
                    or event['start'] != start or event['wall'] - start != event['elapsed']
                    or (not 0 <= event['elapsed'] <= 500 if i == 0 else not requested <= interval <= requested + 500)
                    or event['drive'] != drive or event['gait'] != gait
                    or event.get('heal') is not (phase == 'healed-forward')):
                raise ValueError('Invalid injury phase receipt: ' + name)
        final_interval = duration - phase_events[-1]['elapsed']
        if not 12000 - PHASES[-1][1] <= final_interval <= 12500 - PHASES[-1][1]:
            raise ValueError('Short or delayed injury final phase: ' + name)
        _span(rows, 'elapsed', 0, duration, 'samples: ' + name)
        if any(b['wall'] <= a['wall'] for a, b in zip(rows, rows[1:])):
            raise ValueError('Unordered injury samples: ' + name)
        for row in rows:
            if (any(type(row.get(k)) is not int for k in ('start', 'wall', 'elapsed', 'id', 'primaryID', 'secondaryID', 'cargoID', 'drive', 'requestedGait'))
                    or row['start'] != start or row['wall'] - start != row['elapsed'] or not 0 <= row['elapsed'] <= duration
                    or any(not finite(row.get(k)) for k in ('x', 'y', 'heading', 'acceptedHeading', 'injury', 'walkSpeed', 'legPace', 'stepX', 'stepY', 'cargoWeight', 'leftScratch', 'rightScratch', 'leftFracture', 'rightFracture'))
                    or any(type(row.get(k)) is not bool for k in ('female', 'full', 'run', 'sprint', 'motion', 'pivot', 'brake'))
                    or row['female'] is not (sex == 'female') or row['full'] is not (cargo == 'full')
                    or row.get('cartType') != TYPES[variant] or not row['motion'] or row['id'] < 0
                    or row['primaryID'] != row['id'] or row['secondaryID'] != row['id']):
                raise ValueError('Invalid injury ownership/telemetry: ' + name)
            row['clips'] = tracks(row['tracks'])
        wrong_cargo = (rows[0]['cargoID'] != -1 or rows[0]['cargoWeight'] != 0) if cargo == 'empty' else (rows[0]['cargoID'] < 0 or rows[0]['cargoWeight'] <= 0)
        if len({(r['id'], r['cargoID'], r['cargoWeight']) for r in rows}) != 1 or wrong_cargo:
            raise ValueError('Injury changed cart/cargo identity: ' + name)
        phases = []
        for i, (phase, planned, drive, gait) in enumerate(PHASES):
            event_start = phase_events[i]['elapsed']
            end = phase_events[i + 1]['elapsed'] if i + 1 < len(PHASES) else duration
            selected = [r for r in rows if event_start + 350 <= r['elapsed'] < end]
            _span(selected, 'elapsed', event_start + 350, end, phase + ': ' + name)
            if any(r['phase'] != phase or r['drive'] != drive or r['requestedGait'] != gait for r in selected):
                raise ValueError('Injury phase and samples disagree: ' + name)
            healed = phase.startswith('healed-')
            if healed:
                if any(abs(r['injury']) > .01 or any(r[k] > .01 for k in ('leftScratch', 'rightScratch', 'leftFracture', 'rightFracture')) for r in selected):
                    failures.append([name, phase, 'injury remained after BodyDamage healing'])
                if any('Limp' in c['name'] and c['weight'] > .1 for r in selected for c in r['clips']):
                    failures.append([name, phase, 'limp track remained after healing'])
            else:
                active_key = side + ('Scratch' if severity == 'mild' else 'Fracture')
                other = 'right' if side == 'left' else 'left'
                if any(r[active_key] <= (5 if severity == 'mild' else 20)
                       or r[other + 'Scratch'] > 0 or r[other + 'Fracture'] > 0
                       or (r['injury'] <= .15 if side == 'left' else r['injury'] >= -.15) for r in selected):
                    failures.append([name, phase, 'wrong real injury severity/side or engine WalkInjury'])
            if phase in ('forward', 'left', 'right'):
                if not all(_walk_mix(r) for r in selected):
                    failures.append([name, phase, 'native injury components do not match WalkInjury/WalkSpeed field'])
                if any(r['run'] or r['sprint'] for r in selected):
                    failures.append([name, phase, 'fast gait active without request'])
            if phase == 'reverse' and not any(c['name'] in BACKWARD_CLIPS and c['weight'] > .15 and abs(c['speed']) > .001
                                              for r in selected for c in r['clips']):
                failures.append([name, phase, 'native backward clip missing or paused'])
            if phase in ('run-request', 'sprint-request'):
                suffix = 'R' if side == 'left' else 'L'
                # defaultRun blends both walking and running limp clips at native WalkSpeed;
                # heavy injuries can still use heavy Walk even while the final Run flag is true.
                expected_clips = {'Bob_WalkLightLimp' + suffix, 'Bob_WalkHeavyLimp' + suffix, 'Bob_RunLightLimp' + suffix}
                grounded = [r for r in selected if not r['sprint'] and r['stepY'] > .01]
                if (not grounded and not any(r['sprint'] for r in selected)
                        or any(not _walk_mix(r) if not r['run'] else not any(c['name'] in expected_clips
                               and c['weight'] > 1e-4 and abs(c['speed']) > .001 for c in r['clips']) for r in grounded)):
                    failures.append([name, phase, 'native final gait did not retain its injury blend'])
            distance = sum(math.hypot(b['x'] - a['x'], b['y'] - a['y']) for a, b in zip(selected, selected[1:]))
            forward_travel = sum((b['x'] - a['x']) * math.cos(a['heading']) + (b['y'] - a['y']) * math.sin(a['heading'])
                                 for a, b in zip(selected, selected[1:]))
            heading_delta = math.atan2(math.sin(selected[-1]['heading'] - selected[0]['heading']), math.cos(selected[-1]['heading'] - selected[0]['heading']))
            if drive and distance < .03:
                failures.append([name, phase, 'cart did not move'])
            reversal = None
            if phase == 'reverse':
                reversal = _reverse([r for r in rows if event_start <= r['elapsed'] < end], event_start,
                                    require_rest=variant != 'shopping-cart')
                if not reversal['pass_']:
                    failures.append([name, phase, 'cart did not complete its variant reversal contract and move backward in its facing direction', reversal])
            if phase in ('left', 'right') and abs(heading_delta) < .015:
                failures.append([name, phase, 'steering did not turn injured cart'])
            if phase in ('stop', 'healed-stop'):
                tail = [r for r in selected if r['elapsed'] >= end - 400]
                if len(tail) < 2:
                    raise ValueError('Incomplete injury stop tail: ' + name)
                if any(r['run'] or r['sprint'] for r in tail) or math.dist((tail[0]['x'], tail[0]['y']), (tail[-1]['x'], tail[-1]['y'])) > .025:
                    failures.append([name, phase, 'cart did not settle after release'])
            phases.append(dict(phase=phase, samples=len(selected), distanceTiles=distance,
                               forwardTravelTiles=forward_travel,
                               meanTravelSpeedTilesPerSecond=distance * 1000 / (selected[-1]['elapsed'] - selected[0]['elapsed']),
                               headingChange=heading_delta, actualRun=any(r['run'] for r in selected),
                               actualSprint=any(r['sprint'] for r in selected),
                               requestedGait=gait, minWalkSpeed=min(r['walkSpeed'] for r in selected),
                               maxWalkSpeed=max(r['walkSpeed'] for r in selected),
                               tracks=sorted({c['name'] for r in selected for c in r['clips'] if c['weight'] > .1})))
            if reversal is not None:
                phases[-1]['reversal'] = reversal
        summary = dict(scene=name, phases=phases, samples=len(rows), startWall=start,
                       endWall=terminal['wall'], recordElapsedMs=duration)
        if profile is not None:
            summary['probes'] = _probes(profile, start, terminal['wall'], sex == 'female', variant)
        summaries.append(summary)
    return dict(injuryVerified=not failures, motionPass=not failures, failures=failures,
                cartVariant=variant, scenes=summaries, probeCoverageVerified=profile is not None,
                nativeWalkFieldSource=native_source,
                geometryVerified=False, animationEquivalencePass=False,
                scope='Real SP leg injury, native limp tracks, steering, ownership, stopping and healing; gait requests record engine eligibility. Grip render coverage is measured separately from visual/geometry equivalence.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--variant', choices=TYPES, default='wooden-wheelbarrow')
    parser.add_argument('--scene', action='append')
    parser.add_argument('--game-java-dir', type=Path)
    args = parser.parse_args()
    report = analyze(args.log.read_text(errors='replace'), args.scene, args.variant, args.profile, args.game_java_dir)
    args.output.write_text(json.dumps(report, indent=2, allow_nan=False) + '\n')
    return 0 if report['injuryVerified'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
