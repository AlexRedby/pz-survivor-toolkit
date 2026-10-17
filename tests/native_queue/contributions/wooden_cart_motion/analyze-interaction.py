"""Validate native wooden pickup/setdown receipts and phase-specific render coverage."""
import argparse
import bisect
import json
import math
from pathlib import Path
import re
import numpy as np

CASES = ('male-empty-yaw0', 'male-empty-yaw135', 'female-full-yaw90', 'male-full-yaw270')
EVENTS = ('prepared', 'pickupQueued', 'pickedUp', 'dropQueued', 'dropped')
ACTIONS = ('ToolkitWoodCartPickup', 'ToolkitWoodCartSetdown')
DURATION = 16000
SETTLE_MS = 500
ENTRY_MS = 200
ENTRY_GUARD_MS = 35
ENTRY_GAP_MS = 75
ENTRY_RISE = .035
ENTRY_STEP = .045
ARM_BONES = tuple('Bip01_'+side+'_'+part for side in 'LR' for part in ('UpperArm', 'Forearm', 'Hand'))


def entryMotion(text, tail, life):
    """Bound sampled pickup entry motion, independently of the final held-cart probes."""
    assert '[WOOD_BANK] RUN_STARTED' in text, 'Missing interaction run boundary'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    events = [_decode(line.split('[WOOD_INTERACTION_EVENT] ', 1)[1]) for line in log.splitlines()
              if '[WOOD_INTERACTION_EVENT] ' in line]
    cases, failures = [], []
    for name in CASES:
        entry = {'case': name}
        cases.append(entry)
        try:
            attempts = re.findall(r'\[WOOD_BANK\] COMPLETE '+re.escape(name)+r' wall=(\d+)(?:\s|$)', log)
            assert len(attempts) == 1, 'Missing unique selected entry case'
            selected = [r for r in events if r['case'] == name and r['start'] == int(attempts[0])]
            queued = [r for r in selected if r['event'] == 'pickupQueued']
            picked = [r for r in selected if r['event'] == 'pickedUp']
            assert len(queued) == len(picked) == 1, 'Missing unique pickup boundaries'
            starts = [r for r in life if r.get('metaType') == ACTIONS[0] and r.get('event') == 'start'
                      and queued[0]['wall'] <= r['wallTimeMillis'] < picked[0]['wall']]
            assert len(starts) == 1, 'Missing unique native pickup start'
            start = starts[0]
            assert start.get('phase') == 'exit' and start.get('started') is True and start.get('threw') is None \
                and start.get('playerNum') == 0 and type(start.get('nativeActionId')) is int \
                and start['nativeActionId'] > 0, 'Invalid native pickup start receipt'
            wall = start['wallTimeMillis']
            entry.update(nativeActionId=start['nativeActionId'], actorId=start.get('actorId'), startWall=wall)
            candidates = [r for r in tail if wall <= r['wallTimeMillis'] <= wall+ENTRY_MS+ENTRY_GUARD_MS]
            end = next((i for i, r in enumerate(candidates) if r['wallTimeMillis'] >= wall+ENTRY_MS), None)
            assert end is not None, 'Missing frame bracketing pickup entry end'
            frames = candidates[:end+1]
            before = [r for r in tail if wall-50 <= r['wallTimeMillis'] <= wall]
            assert len(frames) >= 4, 'Missing pickup entry render window'
            stamps = [r['wallTimeMillis'] for r in frames]
            assert all(b > a for a, b in zip(stamps, stamps[1:])), 'Nonmonotonic entry frames'
            baseline = max(before, key=lambda r: r['wallTimeMillis']) if before else frames[0]
            assert baseline['wallTimeMillis'] <= wall+35, 'Missing pre-start/immediate entry baseline'
            observed = ([baseline] if baseline['wallTimeMillis'] < stamps[0] else []) + frames
            gaps = [b['wallTimeMillis']-a['wallTimeMillis'] for a, b in zip(observed, observed[1:])]
            entry.update(samples=len(frames), baselineOffsetMs=baseline['wallTimeMillis']-wall,
                         firstOffsetMs=stamps[0]-wall, lastOffsetMs=stamps[-1]-wall, maxSampleGapMs=max(gaps),
                         metricsWindowOffsetMs=[baseline['wallTimeMillis']-wall, stamps[-1]-wall])
            assert stamps[0]-wall <= 35 and ENTRY_MS <= stamps[-1]-wall <= ENTRY_MS+ENTRY_GUARD_MS \
                and max(gaps) <= ENTRY_GAP_MS, 'Incomplete pickup entry render coverage'
            for frame in observed:
                _finite(frame)
                assert all(len(frame['bones'][bone]) == 16
                           and all(type(value) in (int, float) for value in frame['bones'][bone])
                           for bone in ARM_BONES), 'Missing/invalid entry arm matrices'
            assert all(r.get('PerformingAction') == 'ToolkitWoodCart' and r.get('cartModel') is True
                       for r in frames), 'Entry frames do not show the pickup presentation'
            assert all('RightHandMask' in r and isinstance(r['tracks'], list) and r['tracks']
                       for r in frames), 'Missing entry mask/track evidence'
            masked = [r['wallTimeMillis']-wall for r in frames if r['RightHandMask'] != '']
            stock = []
            for frame in frames:
                for track in frame['tracks']:
                    assert isinstance(track['name'], str) and type(track['priority']) is int \
                        and type(track['layer']) is int and 0 <= track['weight'] <= 1.001 \
                        and 0 <= track['field'] <= 1.001, 'Invalid entry animation track'
                    if track['name'] == 'Bob_Cart_Idle' and track['priority'] < 20 \
                            and track['weight']*track['field'] > .0001:
                        stock.append(dict(offsetMs=frame['wallTimeMillis']-wall, **track))
            entry.update(rightMaskOffsetsMs=masked, lowerPriorityCartTracks=stock, bones={})
            for bone in ARM_BONES:
                points = [np.asarray(r['bones'][bone][12:15], dtype=float) for r in observed]
                rise = max(float(point[1]-points[0][1]) for point in points)
                step = max(float(np.linalg.norm(b-a)) for a, b in zip(points, points[1:]))
                entry['bones'][bone] = dict(maxRiseActorUnits=rise, maxAdjacentDistanceActorUnits=step)
                if bone.endswith('_Hand') and (rise > ENTRY_RISE or step > ENTRY_STEP):
                    failures.append((name, bone+' pickup entry wrist motion exceeds limits'))
            if masked:
                failures.append((name, 'right hand mask active during pickup entry'))
            if stock:
                failures.append((name, 'lower-priority cart idle active during pickup entry'))
        except (AssertionError, KeyError, TypeError, ValueError) as error:
            entry['evidenceError'] = str(error)
            failures.append((name, str(error)))
    return dict(failures=failures, cases=cases,
                limits=dict(windowMs=ENTRY_MS, maxBaselineBeforeMs=50, maxFirstOffsetMs=35,
                            minLastOffsetMs=ENTRY_MS, endGuardMs=ENTRY_GUARD_MS, maxSampleGapMs=ENTRY_GAP_MS,
                            maxWristRiseActorUnits=ENTRY_RISE, maxAdjacentWristDistanceActorUnits=ENTRY_STEP),
                limit='Sampled first 200ms of each selected SP pickup, through its first bracketing frame (up to +35ms); '
                      'tail probe has no actor identifier. '
                      'Native player-0 start and the isolated scene bound the window. No full animation equivalence claim.') | {'pass': not failures}


def knee_direction(frame):
    """Signed knee offset in the foot's forward plane; an unsigned flex angle misses reversal."""
    offsets = []
    for side in 'LR':
        hip, knee, foot, toe = [np.asarray(frame['bones']['Bip01_'+side+'_'+name][12:15], dtype=float)
                               for name in ('Thigh', 'Calf', 'Foot', 'Toe0')]
        axis = foot - hip
        forward = toe - foot; forward[1] = 0
        assert np.linalg.norm(axis) > 1e-6, 'Degenerate leg axis'
        axis /= np.linalg.norm(axis)
        forward -= axis * np.dot(forward, axis)
        assert np.linalg.norm(forward) > 1e-6, 'Degenerate foot direction'
        offsets.append(float(np.dot(knee-hip, forward / np.linalg.norm(forward))))
    assert np.isfinite(offsets).all(), 'Nonfinite knee pole'
    return offsets


def world_points(frame, vertices, actor_z=None):
    """Use the actual renderer's camera convention, independently of the presentation helper."""
    if actor_z is not None:
        c, s = math.cos(frame['slotAngle']), math.sin(frame['slotAngle'])
        camera = np.array([[-1.5*c, 0, -1.5*s, frame['slotX']],
                           [-1.5*s, 0, 1.5*c, frame['slotY']],
                           [0, 1.5/2.44949, 0, actor_z], [0, 0, 0, 1]])
        transform = np.asarray(frame['cart']).reshape(4, 4).T
    else:
        camera = np.array([[1.5, 0, 0, frame['x']], [0, 0, -1.5, frame['y']],
                           [0, 1.5/2.44949, 0, frame['z']], [0, 0, 0, 1]])
        x, y, z = map(math.radians, frame['angle'])
        cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
        rx = np.array([[1,0,0,0],[0,cx,-sx,0],[0,sx,cx,0],[0,0,0,1]])
        ry = np.array([[cy,0,sy,0],[0,1,0,0],[-sy,0,cy,0],[0,0,0,1]])
        rz = np.array([[cz,-sz,0,0],[sz,cz,0,0],[0,0,1,0],[0,0,0,1]])
        transform = rx @ ry @ rz @ np.asarray(frame['transform']).reshape(4, 4).T
    points = vertices @ (camera @ transform).T
    assert np.isfinite(points).all(), 'Nonfinite actual world/held mesh coordinates'
    return points[:, :3]


def handoff(text, body, world, vertices):
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    samples = [_decode(line.split('[WOOD_INTERACTION_SAMPLE] ', 1)[1]) for line in log.splitlines() if '[WOOD_INTERACTION_SAMPLE] ' in line]
    events = [_decode(line.split('[WOOD_INTERACTION_EVENT] ', 1)[1]) for line in log.splitlines() if '[WOOD_INTERACTION_EVENT] ' in line]
    result, failures = [], []
    for name in CASES:
        completed = re.findall(r'\[WOOD_BANK\] COMPLETE ' + re.escape(name) + r' wall=(\d+)', log)
        assert len(completed) == 1, 'Missing unique handoff case'
        start = int(completed[0])
        rows = [r for r in samples if r['case'] == name and r['start'] == start]
        receipts = {r['event']: r for r in events if r['case'] == name and r['start'] == start}
        native = [r for r in world if r['itemId'] == rows[0]['id'] and start-4000 <= r['wallTimeMillis'] <= start+DURATION]
        for row in native:
            _finite(row)
        visible = [r for r in native if r.get('renderStatus') == 'Ready'
                   and r.get('transitionHidden') is not True and r['alpha'] > .01]
        before = [r for r in visible if r['wallTimeMillis'] <= receipts['pickupQueued']['wall']]
        after = [r for r in visible if r['wallTimeMillis'] >= receipts['dropped']['wall']-200]
        assert before and after, 'Missing actual visible world render endpoint: ' + name
        entry = {'case': name, 'endpoints': {}}
        matched = _matched([r for r in body if start <= r['wallTimeMillis'] <= start+DURATION], rows)
        for action, low, high, endpoint in [(ACTIONS[0], .15, .35, before[-1]), (ACTIONS[1], .75, .95, after[0])]:
            frames = [(p, r) for p, r in matched if r['actionType'] == action and low <= r['progress'] <= high and r['rendered']]
            assert len(frames) >= 3, 'Missing grounded handoff mesh window: ' + name + ' ' + action
            target = world_points(endpoint, vertices)
            errors = [float(np.linalg.norm(world_points(p, vertices, r['z'])-target, axis=1).max()) for p, r in frames]
            entry['endpoints'][action] = {'samples': len(frames), 'maxVertexDistanceTiles': max(errors)}
            if max(errors) > .01:
                failures.append((name, action + ' world/held mesh handoff exceeds .01 tiles'))
        # The world-object gate can skip the model renderer entirely; only its named exit probe proves that path.
        hidden = [r for r in native if receipts['pickupQueued']['wall']+500 < r['wallTimeMillis'] < receipts['pickedUp']['wall']-200
                  and r.get('transitionHidden') is True and (r.get('renderStatus') == 'NoModel'
                  or r.get('renderStatus') == 'Suppressed' and r.get('source') == 'IsoWorldInventoryObject.render-exit')]
        entry['suppressedWorldSamples'] = len(hidden)
        if not hidden:
            failures.append((name, 'missing exact-item world suppression evidence'))
        # Cached world rendering need not initialize every frame; every later observed init must stay visible.
        settled = [r for r in native if r['wallTimeMillis'] >= receipts['dropped']['wall']+SETTLE_MS]
        entry['settledWorldRenderSamples'] = len(settled)
        if any(r.get('renderStatus') != 'Ready' or r.get('transitionHidden') is True or r['alpha'] <= .01 for r in settled):
            failures.append((name, 'settled world renderer was suppressed after drop'))
        result.append(entry)
    return {'pass': not failures, 'failures': failures, 'cases': result,
            'limit': 'Sampled native world/held mesh handoff; video cadence and foot/grip geometry remain separate gates.'}


def _finite(value):
    if isinstance(value, dict):
        for entry in value.values():
            _finite(entry)
    elif isinstance(value, list):
        for entry in value:
            _finite(entry)
    elif isinstance(value, (int, float)):
        assert math.isfinite(value), 'Nonfinite interaction measurement'


def _object(pairs):
    result = dict(pairs)
    assert len(result) == len(pairs), 'Duplicate interaction JSON field'
    return result


def _decode(value):
    row = json.loads(value, object_pairs_hook=_object)
    _finite(row)
    return row


def _matched(probes, rows):
    stamps = [row['wall'] for row in rows]
    result = []
    for probe in probes:
        index = bisect.bisect_right(stamps, probe['wallTimeMillis']) - 1
        if index >= 0 and 0 <= probe['wallTimeMillis'] - stamps[index] <= 200:
            result.append((probe, rows[index]))
    return result


def analyze(text, body, grip):
    assert '[WOOD_BANK] RUN_STARTED' in text, 'Missing interaction run boundary'
    log = text.rsplit('[WOOD_BANK] RUN_STARTED', 1)[-1]
    assert re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases=4(?:\s|$)', log), 'Interaction capture incomplete'
    assert '[WOOD_BANK] FAIL' not in log, 'Interaction scenario failed'
    completed = re.findall(r'\[WOOD_BANK\] COMPLETE (\S+) wall=(\d+)', log)
    assert len(completed) == 4 and {name for name, _ in completed} == set(CASES), 'Missing/duplicate interaction cases'
    starts = {name: int(wall) for name, wall in completed}
    attempts = re.findall(r'\[WOOD_BANK\] CASE (\S+) attempt=\d+ wall=(\d+)', log)
    assert all(attempts.count((name, str(wall))) == 1 for name, wall in starts.items()), 'Missing/duplicate selected interaction attempt'
    samples, events = {name: [] for name in CASES}, {name: [] for name in CASES}
    for line in log.splitlines():
        match = re.search(r'\[WOOD_INTERACTION_(SAMPLE|EVENT)\] (\{.*\})', line)
        if not match:
            continue
        row = _decode(match[2])
        assert row['case'] in starts, 'Unexpected interaction case'
        if row['start'] != starts[row['case']]:
            continue
        assert abs(row['wall'] - row['start'] - row['elapsed']) <= 5, 'Interaction clocks disagree'
        assert 0 <= row['elapsed'] <= DURATION + 500, 'Interaction sample outside selected recording'
        for key in ('id', 'heldID', 'secondaryID', 'worldID', 'worldCount', 'woodWorldCount', 'inventoryCount', 'cargoCount'):
            assert type(row[key]) is int, 'Invalid interaction integer: ' + key
        for key in ('ToolkitCartMotion', 'statusAvailable', 'active', 'rendered', 'ik', 'pickup'):
            assert type(row[key]) is bool, 'Invalid interaction boolean: ' + key
        assert row['id'] >= 0 and 0 <= row['progress'] <= 1.001 and 0 <= row['presentationProgress'] <= 1.001, 'Invalid item/progress'
        assert row['cargo'] >= 0 and row['cargoCount'] >= 0 and isinstance(row['cargoIDs'], str), 'Invalid cargo'
        assert row['worldAlpha'] == -1 or 0 <= row['worldAlpha'] <= 1.001, 'Invalid world alpha'
        (samples if match[1] == 'SAMPLE' else events)[row['case']].append(row)
    failures, summaries = [], []
    for name in CASES:
        rows, receipts = samples[name], events[name]
        assert len(rows) >= 100, 'Insufficient interaction samples: ' + name
        gaps = [b['wall'] - a['wall'] for a, b in zip(rows, rows[1:])]
        assert min(gaps) > 0 and max(gaps) <= 500 and rows[0]['elapsed'] <= 500 and rows[-1]['elapsed'] >= DURATION - 500, 'Incomplete interaction sample window: ' + name
        assert tuple(dict.fromkeys(row['stage'] for row in rows)) == ('grounded', 'pickup', 'held', 'drop', 'dropped'), 'Missing/reordered interaction phases'
        assert tuple(row['event'] for row in receipts) == EVENTS, 'Missing/reordered interaction receipts: ' + name
        assert all(b['wall'] > a['wall'] for a, b in zip(receipts, receipts[1:])), 'Non-monotonic interaction receipts'
        initial = receipts[0]
        assert (initial['cargo'] > 0) == ('-full-' in name), 'Wrong initial cargo: ' + name
        assert initial['worldCount'] == 1 and initial['inventoryCount'] == 0 and initial['heldID'] == initial['secondaryID'] == -1, 'Pickup did not start with exact ground cart'
        picked, dropped = receipts[2], receipts[4]
        assert picked['heldID'] == picked['secondaryID'] == picked['id'] and picked['inventoryCount'] == 1 and picked['worldCount'] == 0, 'Missing exact held pickup receipt'
        assert dropped['heldID'] == dropped['secondaryID'] == -1 and dropped['inventoryCount'] == 0 and dropped['worldCount'] == 1 and dropped['worldID'] == dropped['id'], 'Missing exact world drop receipt'
        assert rows[-1]['wall'] - dropped['wall'] >= 700, 'Missing settled drop tail'
        for row in rows + receipts:
            if row['id'] != initial['id'] or abs(row['cargo'] - initial['cargo']) > .001 or row['cargoIDs'] != initial['cargoIDs'] or row['cargoCount'] != initial['cargoCount']:
                failures.append((name, 'item identity or cargo changed')); break
        if any(row['worldCount'] not in (0, 1) or row['inventoryCount'] not in (0, 1)
               or row['woodWorldCount'] != row['worldCount'] or row['worldCount'] + row['inventoryCount'] != 1
               or row['worldID'] != (row['id'] if row['worldCount'] else -1)
               or row['heldID'] not in (-1, row['id']) or row['secondaryID'] not in (-1, row['id'])
               or row['worldCount'] and (row['heldID'] != -1 or row['secondaryID'] != -1) for row in rows):
            failures.append((name, 'owned cart duplicated, disappeared or retained stale hands'))
        if any(row['worldAlpha'] < .99 for row in rows):
            failures.append((name, 'inventory item world alpha was mutated'))
        if any(row['ToolkitCartMotion'] for row in rows if row['actionType'] in ACTIONS):
            failures.append((name, 'steering motion enabled during custom interaction'))
        if any(row['heldID'] != row['id'] or row['secondaryID'] != row['id']
               or row['inventoryCount'] != 1 or row['worldCount'] != 0 for row in rows if row['stage'] == 'held'):
            failures.append((name, 'exact cart was not held in both hands throughout the held window'))
        tail = [row for row in rows if row['wall'] >= dropped['wall'] + SETTLE_MS]
        if any(row['worldCount'] != 1 or row['inventoryCount'] != 0 or row['heldID'] != -1 or row['secondaryID'] != -1 or row['worldAlpha'] < .99 for row in tail):
            failures.append((name, 'settled world state or visibility was not restored'))
        if any(row['active'] or row['rendered'] or row['actionType'] for row in tail):
            failures.append((name, 'presentation or action remained active after settled drop'))
        selected_body = [row for row in body if starts[name] <= row['wallTimeMillis'] <= starts[name] + DURATION]
        selected_grip = [row for row in grip if starts[name] <= row['wallTimeMillis'] <= starts[name] + DURATION]
        for row in selected_body + selected_grip:
            _finite(row)
        assert all(len(row['cart']) == 16 and isinstance(row['bones'], dict) for row in selected_body), 'Missing final render matrices'
        matched_body, matched_grip = _matched(selected_body, rows), _matched(selected_grip, rows)
        coverage = {}
        for action in ACTIONS:
            observed = [row for row in rows if row['actionType'] == action]
            assert len(observed) >= 3 and max(row['progress'] for row in observed) - min(row['progress'] for row in observed) >= .5, 'Missing progressing native action: ' + name + ' ' + action
            frames = [(probe, row) for probe, row in matched_body if row['actionType'] == action]
            assert len({probe['wallTimeMillis'] for probe, _ in frames}) >= 3, 'Missing final render action coverage: ' + name + ' ' + action
            phases = [row['progress'] for _, row in frames]
            stamps = sorted({probe['wallTimeMillis'] for probe, _ in frames})
            assert max(b-a for a, b in zip(stamps, stamps[1:])) <= 500, 'Final render action coverage has gaps'
            assert min(phases) <= .35 and max(phases) >= .65 and max(phases) - min(phases) >= .5, 'Final render action coverage is partial: ' + name + ' ' + action
            contact = [(probe, row) for probe, row in matched_grip if row['actionType'] == action
                       and (.48 <= row['progress'] <= .95 if action == ACTIONS[0] else .05 <= row['progress'] <= .52)]
            assert len({probe['wallTimeMillis'] for probe, _ in contact}) >= 3, 'Missing contact-phase native grip coverage: ' + name + ' ' + action
            if any(probe.get('threw') is not False or probe.get('result') is not True for probe, _ in contact):
                failures.append((name, action + ' native contact grip failed'))
            rendered = [row for _, row in frames if row['statusAvailable'] and row['active'] and row['rendered']]
            if any(not row['ik'] for row in rendered):
                failures.append((name, action + ' rendered IK failed'))
            knee_frames = [probe for probe, row in frames if .25 <= row['progress'] <= .75]
            assert len(knee_frames) >= 3, 'Missing knee transition coverage'
            knee_offsets = [value for probe in knee_frames for value in knee_direction(probe)]
            if min(knee_offsets) < -.0001:
                failures.append((name, action + ' knee bent behind the foot plane'))
            coverage[action] = dict(kneeDirectionSamples=len(knee_frames), minForwardKneeOffset=min(knee_offsets),
                                    finalRenderSamples=len(frames), gripContactSamples=len(contact), renderedStatusSamples=len(rendered),
                                    ikCoverageVerified=len(rendered) >= 3, progressRange=[min(phases), max(phases)],
                                    finalCartTranslation=frames[-1][0]['cart'][12:15])
        held = [(probe, row) for probe, row in matched_body if row['stage'] == 'held' and row['actionType'] == '']
        assert len(held) >= 3 and max(p['wallTimeMillis'] for p, _ in held) - min(p['wallTimeMillis'] for p, _ in held) >= 500, 'Missing held final-render window: ' + name
        summaries.append(dict(case=name, id=initial['id'], cargo=initial['cargo'], cargoIDs=initial['cargoIDs'], samples=len(rows),
            pickupElapsed=picked['elapsed'], droppedElapsed=dropped['elapsed'], maxSampleGapMs=max(gaps), coverage=coverage,
            heldRenderSamples=len(held), finalWorldAlpha=rows[-1]['worldAlpha'],
            finalWorldPosition=[rows[-1].get(key) for key in ('worldX', 'worldY', 'worldZ')]))
    return dict(complete=True, functionalPass=not failures, failures=failures, caseCount=len(summaries), cases=summaries,
        ikCoverageVerified=all(c['ikCoverageVerified'] for row in summaries for c in row['coverage'].values()),
        limit='Native actions, sampled identity/cargo/ownership and phase-specific render coverage only. Local owned-world scan is bounded to the checked pad. Geometry diagnostics and videos require separate review; no motion or animation equivalence claim.')


def fixture():
    """Small deterministic protocol specimen used by the assert-based self-check."""
    lines, body, grip = ['[WOOD_BANK] RUN_STARTED'], [], []
    for index, name in enumerate(CASES):
        start, identifier = 100000 + index * 20000, 1000 + index
        lines.append(f'[WOOD_BANK] CASE {name} attempt=0 wall={start}')
        for elapsed in range(0, DURATION + 1, 25):
            stage = 'grounded' if elapsed < 700 else 'pickup' if elapsed < 4500 else 'held' if elapsed < 5600 else 'drop' if elapsed < 9300 else 'dropped'
            held = stage in ('held', 'drop')
            action = ACTIONS[0] if 1200 <= elapsed < 4500 else ACTIONS[1] if stage == 'drop' else ''
            progress = (elapsed - 1200) / 3300 if action == ACTIONS[0] else (elapsed - 5600) / 3700 if action == ACTIONS[1] else 0
            row = dict(case=name, start=start, wall=start+elapsed, elapsed=elapsed, id=identifier, stage=stage,
                heldID=identifier if held else -1, secondaryID=identifier if held else -1,
                worldID=-1 if held else identifier, worldCount=0 if held else 1, woodWorldCount=0 if held else 1,
                inventoryCount=int(held), actionType=action, progress=progress, ToolkitCartMotion=False, worldAlpha=1,
                cargo=50 if '-full-' in name else 0, cargoIDs='55:Base.Log:50' if '-full-' in name else '', cargoCount=int('-full-' in name), x=0,y=0,z=0,
                statusAvailable=True, active=bool(action), rendered=bool(action), ik=bool(action), presentationProgress=progress, pickup=action==ACTIONS[0])
            lines.append('[WOOD_INTERACTION_SAMPLE] ' + json.dumps(row))
            event = {0:'prepared', 700:'pickupQueued', 4500:'pickedUp', 5600:'dropQueued', 9300:'dropped'}.get(elapsed)
            if event:
                lines.append('[WOOD_INTERACTION_EVENT] ' + json.dumps(dict(row, event=event)))
            if action or stage == 'held':
                body.append(dict(wallTimeMillis=start+elapsed, slotX=0,slotY=0,slotAngle=0,cart=[1,0,0,0,0,1,0,0,0,0,1,0,.1,.2,.3,1], bones={
                    'Bip01_'+side+'_'+name: [1,0,0,0,0,1,0,0,0,0,1,0,x,y,z,1]
                    for side,x in [('L',.05),('R',-.05)]
                    for name,y,z in [('Thigh',.9,0),('Calf',.45,-.1),('Foot',0,0),('Toe0',0,-.1)]}))
                grip.append(dict(wallTimeMillis=start+elapsed, result=True, threw=False))
        lines.append(f'[WOOD_BANK] COMPLETE {name} wall={start} file=/owned/{name}.mp4 frames=480 seconds=16.0')
    lines.append('[WOOD_BANK] ALL_COMPLETE cases=4')
    return '\n'.join(lines), body, grip


def world_fixture():
    return [dict(wallTimeMillis=100000+index*20000+elapsed,itemId=1000+index,
                 **(dict(renderStatus='NoModel',transitionHidden=True) if elapsed == 3000 else
                    dict(renderStatus='Ready',x=0,y=0,z=0,angle=[0,0,0],
                         transform=[-1,0,0,0,0,1,0,0,0,0,-1,0,-.1,.2,-.3,1],alpha=1)))
            for index in range(len(CASES)) for elapsed in (100,3000,9400)]


def entry_fixture():
    tail, life = [], []
    for index, _ in enumerate(CASES):
        wall = 101200+index*20000
        life.append(dict(wallTimeMillis=wall, event='start', phase='exit', metaType=ACTIONS[0],
                         nativeActionId=index+1, actorId=3, playerNum=0, started=True, threw=None))
        for offset in range(-25, 201, 25):
            tail.append(dict(wallTimeMillis=wall+offset, PerformingAction='ToolkitWoodCart' if offset >= 0 else '',
                             RightHandMask='', cartModel=offset >= 0,
                             bones={bone: [1,0,0,0,0,1,0,0,0,0,1,0,
                                           .15 if '_L_' in bone else -.15, .48-offset*.00002, .03-offset*.00002, 1]
                                    for bone in ARM_BONES},
                             tracks=[dict(name='Bob_Idle', weight=1, field=1, layer=1, priority=20)]))
    return tail, life


def self_check():
    held = dict(slotX=10, slotY=20, slotAngle=.3, cart=[1,0,0,0,0,1,0,0,0,0,1,0,.1,.2,.3,1])
    theta = .3 + math.pi
    rotation = np.array([[math.cos(theta),0,math.sin(theta),0],[0,1,0,0],[-math.sin(theta),0,math.cos(theta),0],[0,0,0,1]])
    final = rotation @ np.asarray(held['cart']).reshape(4,4).T
    world = dict(x=10,y=20,z=7,angle=[0,0,0],transform=final.T.reshape(-1).tolist())
    vertices = np.array([[0,0,0,1],[.01,.02,-.03,1]])
    assert np.max(abs(world_points(held,vertices,7)-world_points(world,vertices))) < 1e-10
    world['x'] += .03
    assert np.max(abs(world_points(held,vertices,7)-world_points(world,vertices))) > .01, 'Handoff jump accepted'
    text, body, grip = fixture()
    tail, life = entry_fixture()
    assert entryMotion(text, tail, life)['pass']
    bracketed = [dict(row, wallTimeMillis=101403) if row['wallTimeMillis'] == 101400 else row for row in tail]
    outside = json.loads(json.dumps(bracketed[2])); outside['wallTimeMillis'] = 101425
    outside['bones']['Bip01_R_Hand'][13] += .10
    bracketed.insert(10, outside)
    bracketed_result = entryMotion(text, bracketed, life)
    assert bracketed_result['pass'] and bracketed_result['cases'][0]['lastOffsetMs'] == 203, 'First end-bracketing frame was not used'
    no_bracket = [row for row in tail if row['wallTimeMillis'] != 101400]
    assert not entryMotion(text, no_bracket, life)['pass'], 'Unbracketed entry end accepted'
    late_bracket = [dict(row, wallTimeMillis=101436) if row['wallTimeMillis'] == 101400 else row for row in tail]
    assert not entryMotion(text, late_bracket, life)['pass'], 'Entry end guard exceeded'
    # Foreign cases/actions outside selected pickup boundaries cannot satisfy missing native evidence.
    unrelated = [dict(r, wallTimeMillis=r['wallTimeMillis']+10000) for r in life]
    for missing_tail, missing_life in [(tail, []), ([], life), (tail, unrelated),
                                       (tail, [dict(r, metaType='ToolkitWoodCartSetdown') for r in life]),
                                       (tail[4:], life)]:
        assert not entryMotion(text, missing_tail, missing_life)['pass'], 'Missing entry evidence accepted'
    assert entryMotion(text, tail+[dict(tail[2], wallTimeMillis=111200)], life+unrelated)['pass'], 'Unrelated scene evidence changed selected entry'
    for mutation in ('mask', 'stock', 'rise', 'step', 'missingbone', 'missingtracks', 'emptytracks', 'gap', 'duplicatestart'):
        changed = json.loads(json.dumps(tail)); changed_life = json.loads(json.dumps(life))
        row = changed[2]
        if mutation == 'mask': row['RightHandMask'] = 'holdingcartright'
        elif mutation == 'stock': row['tracks'].append(dict(name='Bob_Cart_Idle', weight=.5, field=1, layer=2, priority=10))
        elif mutation == 'rise': row['bones']['Bip01_R_Hand'][13] += .10
        elif mutation == 'step': row['bones']['Bip01_R_Hand'][12] += .16
        elif mutation == 'missingbone': del row['bones']['Bip01_R_Hand']
        elif mutation == 'missingtracks': del row['tracks']
        elif mutation == 'emptytracks': row['tracks'] = []
        elif mutation == 'gap': changed = [r for r in changed if not 101225 <= r['wallTimeMillis'] <= 101300]
        elif mutation == 'duplicatestart': changed_life.append(dict(life[0], nativeActionId=99))
        assert not entryMotion(text, changed, changed_life)['pass'], 'Bad entry evidence accepted: '+mutation
    result = analyze(text, body, grip)
    assert result['functionalPass'] and result['ikCoverageVerified']
    assert handoff(text,body,world_fixture(),vertices)['pass']
    assert handoff('\n'.join('LOG : Lua > '+line for line in text.splitlines()),body,world_fixture(),vertices)['pass']
    world_suppressed=[dict(row,renderStatus='Suppressed',source='IsoWorldInventoryObject.render-exit')
                      if row['renderStatus']=='NoModel' else row for row in world_fixture()]
    assert handoff(text,body,world_suppressed,vertices)['pass'], 'Explicit suppressed world pass was not recognized'
    for changes in ({'transitionHidden':False}, {'transitionHidden':1}, {'source':None},
                    {'source':'ItemModelRenderer.renderMain-exit'}, {'renderStatus':'Ready'}):
        fake_suppressed=[dict(row) for row in world_suppressed];fake_suppressed[1].update(changes)
        assert not handoff(text,body,fake_suppressed,vertices)['pass'], 'Unconfirmed world-pass suppression accepted'
    broken=world_fixture();broken[0]['x']+=.03
    assert not handoff(text,body,broken,vertices)['pass'], 'Actual endpoint jump accepted'
    for value in (False, None, 1, 'true'):
        fake_hidden=world_fixture();fake_hidden[1]['transitionHidden']=value
        assert not handoff(text,body,fake_hidden,vertices)['pass'], 'Unconfirmed NoModel became suppression evidence'
    fake_hidden=world_fixture();fake_hidden[1].update(renderStatus='Ready',alpha=0)
    assert not handoff(text,body,fake_hidden,vertices)['pass'], 'Alpha-zero draw became suppression evidence'
    late_hidden=world_fixture()
    late_hidden.append(dict(late_hidden[1],wallTimeMillis=112000))
    assert not handoff(text,body,late_hidden,vertices)['pass'], 'Late world suppression accepted'
    late_hidden[-1]['transitionHidden']=False
    assert not handoff(text,body,late_hidden,vertices)['pass'], 'Settled NoModel false became visible rendering'
    for index in (0,2):
        missing_endpoint=world_fixture();missing_endpoint[index].update(renderStatus='NoModel',transitionHidden=False)
        try:
            handoff(text,body,missing_endpoint,vertices)
        except AssertionError as error:
            assert 'Missing actual visible world render endpoint' in str(error)
        else:
            raise AssertionError('NoModel became a visible handoff endpoint')
    for stage, changes in [('held', {'heldID': -1, 'secondaryID': -1}),
                           ('held', {'secondaryID': -1}),
                           ('dropped', {'active': True}),
                           ('dropped', {'rendered': True})]:
        lines=[]
        for line in text.splitlines():
            if '[WOOD_INTERACTION_SAMPLE]' in line:
                row=json.loads(line.split('] ',1)[1])
                if row['stage']==stage: row.update(changes)
                line='[WOOD_INTERACTION_SAMPLE] '+json.dumps(row)
            lines.append(line)
        assert not analyze('\n'.join(lines),body,grip)['functionalPass'], 'Stable lifecycle failure accepted: '+str(changes)
    for field, value in [('cargo', 999), ('worldCount', 2), ('ToolkitCartMotion', True), ('ik', False)]:
        lines = text.splitlines()
        index = next(i for i, line in enumerate(lines) if '[WOOD_INTERACTION_SAMPLE]' in line and 'ToolkitWoodCartPickup' in line)
        row = json.loads(lines[index].split('] ', 1)[1]); row[field] = value
        lines[index] = '[WOOD_INTERACTION_SAMPLE] ' + json.dumps(row)
        assert not analyze('\n'.join(lines), body, grip)['functionalPass'], field
    for bad_text, bad_body, bad_grip in [
        (text.replace('"event": "dropped"', '"event": "missing"', 1), body, grip),
        ('\n'.join(line for line in text.splitlines() if not ('SAMPLE]' in line and '"elapsed": 1000' in line)), [], grip),
        (text, body, []),
        (text.replace('"cargo": 0', '"cargo": NaN', 1), body, grip),
        (text.replace('ALL_COMPLETE cases=4', 'ALL_COMPLETE cases=40'), body, grip),
    ]:
        try:
            analyze(bad_text, bad_body, bad_grip)
        except (AssertionError, ValueError):
            pass
        else:
            raise AssertionError('Invalid protocol accepted')
    reversed_body = json.loads(json.dumps(body))
    for probe in reversed_body:
        probe['bones']['Bip01_L_Calf'][14] *= -1
    assert not analyze(text, reversed_body, grip)['functionalPass'], 'Backward knee passed unsigned pose gates'
    missing_bones = json.loads(json.dumps(body))
    del missing_bones[0]['bones']['Bip01_L_Calf']
    try:
        knee_direction(missing_bones[0])
    except KeyError:
        pass
    else:
        raise AssertionError('Missing knee evidence accepted')
    absent = text.replace('"statusAvailable": true', '"statusAvailable": false')
    assert not analyze(absent, body, grip)['ikCoverageVerified'], 'Missing status became an IK pass'
    print('Interaction analyzer self-check passed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path)
    parser.add_argument('--log', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--self-check', action='store_true')
    args = parser.parse_args()
    if args.self_check:
        self_check(); return 0
    assert args.profile and args.output, '--profile and --output required'
    assert not args.output.exists(), 'Refuse to overwrite an existing report'
    body = [_decode(line) for line in (args.profile / 'body-clearance.jsonl').read_text().splitlines()]
    grip = [_decode(line) for line in (args.profile / 'wood-grip-poses.jsonl').read_text().splitlines()]
    result = analyze((args.log or args.profile / 'console.txt').read_text(errors='replace'), body, grip)
    vertices = np.frombuffer((args.profile / 'WheelbarrowWood.bin').read_bytes(), dtype='<f4').reshape(-1, 8)[:, :3]
    vertices = np.c_[vertices, np.ones(len(vertices))]
    world = [_decode(line) for line in (args.profile / 'world-cart-poses.jsonl').read_text().splitlines()]
    result['worldHandoff'] = handoff((args.log or args.profile / 'console.txt').read_text(errors='replace'), body, world, vertices)
    tail = [_decode(line) for line in (args.profile / 'action-tail-poses.jsonl').read_text().splitlines()]
    life = [_decode(line) for line in (args.profile / 'action-lifecycle.jsonl').read_text().splitlines()]
    result['entryMotion'] = entryMotion((args.log or args.profile / 'console.txt').read_text(errors='replace'), tail, life)
    args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n')
    print(json.dumps(result, indent=2, allow_nan=False))
    return 0 if result['functionalPass'] and result['worldHandoff']['pass'] and result['entryMotion']['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
