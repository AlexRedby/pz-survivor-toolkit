"""Check actual split draws against axle travel and cart pitch, including both ownership handoffs."""
import argparse
import json
import math
from pathlib import Path
import re
import numpy as np

CENTER = np.array([-6.642862e-6, -.0041269097, -.0010569958, 1.])
RADIUS = .001062454

def wrap(value):
    return math.remainder(value, 2 * math.pi)

def pose(row):
    matrix = np.array(row['cart']).reshape((4, 4), order='F')
    assert np.isfinite(matrix).all() and all(math.isfinite(row[k]) for k in ('x', 'y', 'angle', 'phase'))
    center = matrix @ CENTER
    axle_length = np.linalg.norm(matrix[:3, 0])
    assert math.isfinite(axle_length) and axle_length > 1e-8, 'Invalid wheel axle'
    axle = matrix[:3, 0] / axle_length
    up = np.array([0., 1., 0.]) - axle[1] * axle
    up_length = np.linalg.norm(up)
    assert math.isfinite(up_length) and up_length > 1e-6, 'Invalid wheel up plane'
    up /= up_length
    radial = matrix[:3, 1]
    pitch = math.atan2(radial @ np.cross(axle, up), radial @ up)
    c, s = math.cos(row['angle']), math.sin(row['angle'])
    side = np.array([-c * axle[0] - s * axle[2], -s * axle[0] + c * axle[2]])
    side_length = np.linalg.norm(side)
    radius = np.linalg.norm(radial) * RADIUS * 1.5
    assert math.isfinite(side_length) and side_length > 1e-6 and math.isfinite(radius) and radius > 1e-6, 'Invalid rolling plane/radius'
    forward = np.array([-side[1], side[0]]) / side_length
    xy = np.array([row['x'] - 1.5 * (c * center[0] + s * center[2]),
                   row['y'] - 1.5 * s * center[0] + 1.5 * c * center[2]])
    assert np.isfinite(xy).all() and np.isfinite(forward).all() and math.isfinite(pitch), 'Nonfinite derived wheel pose'
    return xy, forward, pitch, radius

def rolling(rows):
    result = dict(samples=len(rows), worldDraws=0, heldDraws=0, handoffs=0, maxResidual=0.,
                  maxHandoffResidual=0., forwardTravel=0., reverseTravel=0.)
    previous = None
    for row in rows:
        result[row['source'] + 'Draws'] += 1
        current = pose(row)
        if previous:
            old, before = previous
            xy, forward, pitch, radius = current
            mean = forward + before[1]
            length = np.linalg.norm(mean)
            delta = xy - before[0]
            assert np.linalg.norm(delta) < 1, 'Unexpected teleport inside continuous wheel cycle'
            gap = row['wall'] - old['wall']
            assert gap >= 0 and (gap <= 500 or old['source'] == 'world'), 'Missing moving/transition draw coverage'
            if length > 1e-6:
                distance = float(delta @ mean / length)
                mean_radius = (radius + before[3]) / 2
                residual = abs(wrap(wrap(row['phase'] - old['phase']) + wrap(pitch - before[2]) + distance / mean_radius)) * mean_radius
                assert math.isfinite(residual), 'Nonfinite rolling residual'
                result['maxResidual'] = max(result['maxResidual'], residual)
                result['forwardTravel'] += max(0., distance)
                result['reverseTravel'] += max(0., -distance)
                if row['source'] != old['source']:
                    result['handoffs'] += 1
                    result['maxHandoffResidual'] = max(result['maxHandoffResidual'], residual)
        previous = row, current
    return result

def analyze(profile, log):
    events = [json.loads(line.split('[WOOD_INTERACTION_EVENT] ', 1)[1]) for line in log.splitlines() if '[WOOD_INTERACTION_EVENT] ' in line]
    assert re.search(r'\[WOOD_BANK\] ALL_COMPLETE cases=1(?:\s|$)', log), 'Cycle not completed'
    prepared = [r for r in events if r['event'] == 'prepared']
    assert len(prepared) == 1, 'Missing unique continuous cycle'
    start, item = prepared[0]['start'], prepared[0]['id']
    events = [r for r in events if r['start'] == start]
    assert [r['event'] for r in events if r['event'] != 'driveChanged'] == ['prepared', 'pickupQueued', 'pickedUp', 'dropQueued', 'dropped', 'pickupQueued', 'pickedUp', 'dropQueued', 'dropped'], 'Missing repeated exact-item cycle'
    assert {r['driveStage'] for r in events if r['event'] == 'driveChanged'} >= {1, 2, 4}, 'Missing forward/turn/reverse inputs'
    samples = [json.loads(line.split('[WOOD_INTERACTION_SAMPLE] ', 1)[1]) for line in log.splitlines() if '[WOOD_INTERACTION_SAMPLE] ' in line]
    samples = [r for r in samples if r['start'] == start]
    assert len(samples) >= 300 and samples[-1]['elapsed'] >= 29500, 'Incomplete state coverage'
    assert all(r['id'] == item and r['cargoIDs'] == prepared[0]['cargoIDs'] and r['condition'] == prepared[0]['condition']
               and abs(r['cargo'] - prepared[0]['cargo']) < .001 and r['worldCount'] + r['inventoryCount'] == 1
               and r['woodWorldCount'] == r['worldCount'] for r in events + samples), 'Identity/cargo/ownership changed'
    rows = [json.loads(line) for line in (profile / 'wheel-roll-draws.jsonl').read_text().splitlines()]
    before = [r for r in rows if start - 2500 <= r['wall'] < start and r['source'] == 'world' and r['itemId'] == item]
    assert before, 'Initial cached ground draw was not captured during fixture settle'
    rows = [max(before, key=lambda r: r['wall'])] + sorted((r for r in rows if start <= r['wall'] <= start + 30000), key=lambda r: r['wall'])
    assert all(r['source'] != 'world' or r['itemId'] == item for r in rows), 'Foreign world item draw'
    metrics = rolling(rows)
    assert metrics['worldDraws'] >= 3 and metrics['heldDraws'] >= 100 and metrics['handoffs'] >= 4, 'Missing actual split draw handoffs'
    assert metrics['forwardTravel'] > .1 and metrics['reverseTravel'] > .1, 'Missing actual wheel travel in both directions'
    proof = json.loads((profile / 'wood-wheel-mesh-proof.json').read_text())
    assert proof['matchesOriginal'] is True, 'Original mesh changed'
    failures = []
    if metrics['maxResidual'] > .004: failures.append('wheel motion differs from actual axle travel/pitch by over .004 tile')
    return dict(pass_=not failures, failures=failures, itemId=item, metrics=metrics,
                limit='Local cosmetic phase continuity in one SP process; no save/reload or multiplayer persistence claim.')

def self_check():
    matrix = np.diag([76.5, 76.5, 76.5, 1.]).flatten(order='F').tolist()
    radius = RADIUS * 76.5 * 1.5
    rows = [dict(source='world' if i == 0 else 'held', wall=i * 20, x=0., y=-i * radius / 10,
                 angle=0., phase=-i / 10, cart=matrix) for i in range(20)]
    assert rolling(rows)['maxResidual'] < 1e-12
    rows[1]['wall'] += 900
    for row in rows[2:]: row['wall'] += 900
    assert rolling(rows)['maxResidual'] < 1e-12, 'Cached stationary world gap was treated as missing motion'
    rows[5]['phase'] += .2
    assert rolling(rows)['maxResidual'] > .02, 'Phase reset/skid was not detected'
    for indices in ((0, 1, 2), (4, 5, 6), (0, 1, 2, 4, 5, 6)):
        invalid = [dict(r, cart=list(r['cart'])) for r in rows]
        for i in indices: invalid[5]['cart'][i] = 0
        try: rolling(invalid)
        except AssertionError: pass
        else: raise AssertionError('Degenerate wheel geometry hid a phase jump')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--profile', type=Path)
    parser.add_argument('--log', type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--self-check', action='store_true')
    args = parser.parse_args()
    self_check()
    if args.self_check: print('WHEEL_CYCLE_SELF_CHECK_PASS')
    else:
        result = analyze(args.profile, args.log.read_text(errors='replace'))
        result['pass'] = result.pop('pass_')
        args.output.write_text(json.dumps(result, indent=2, allow_nan=False) + '\n')
