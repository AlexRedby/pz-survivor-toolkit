"""Strict offline evidence coverage and diagnostics; never asserts animation equivalence."""
from pathlib import Path
import argparse
import json
import math
import re
import statistics

ROLES = ('server', 'client1', 'client2')
WINDOWS = {'idle': (300, 1700), 'walk': (2500, 4500), 'turn': (5500, 7500),
           'stop': (8500, 9500), 'reverse': (10500, 11500), 'settled-stop': (13000, 14500)}
BOOLS = ('local', 'enabled', 'run', 'sprint', 'motion', 'pivot')
NUMBERS = ('wall', 'x', 'y', 'z', 'heading', 'stepX', 'stepY', 'pace', 'bank')
ITEM = 'SaucedWheelbarrow.WheelbarrowWood'


def require(ok, message):
    if not ok:
        raise ValueError(message)


def object_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'Duplicate JSON key: ' + key)
        result[key] = value
    return result


def parse(text):
    def invalid(value):
        raise ValueError('Nonfinite JSON constant: ' + value)
    result = json.loads(text, parse_constant=invalid, object_pairs_hook=object_pairs)
    def finite(value):
        if isinstance(value, float):
            require(math.isfinite(value), 'Nonfinite JSON number')
        elif isinstance(value, dict):
            for entry in value.values():
                finite(entry)
        elif isinstance(value, list):
            for entry in value:
                finite(entry)
    finite(result)
    return result


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def state(row):
    require(isinstance(row, dict), 'State row must be an object')
    require(all(type(row.get(key)) is bool for key in BOOLS), 'Missing/malformed state boolean')
    require(all(number(row.get(key)) for key in NUMBERS), 'Missing/malformed state number')
    require(all(type(row.get(key)) is int for key in ('id', 'primary', 'secondary')), 'Malformed state identity')
    require(isinstance(row.get('user'), str) and isinstance(row.get('item'), str), 'Missing state actor/item')
    require(isinstance(row.get('tracks'), str), 'Missing animation tracks')
    require(not re.search(r'(?:NaN|Infinity|(?<![A-Za-z])(?:nan|inf)(?![A-Za-z]))', row['tracks']), 'Nonfinite animation track')
    return row


def pose(row):
    require(isinstance(row, dict), 'Pose row must be an object')
    require(all(type(row.get(key)) is bool for key in ('local', 'enabled', 'female')), 'Missing/malformed pose boolean')
    require(number(row.get('wallTimeMillis')), 'Missing pose timestamp')
    require(all(type(row.get(key)) is int for key in ('id', 'primary', 'secondary')), 'Missing/malformed pose identity')
    def matrix(value):
        return isinstance(value, list) and len(value) == 16 and all(number(v) for v in value)
    require(matrix(row.get('cart')), 'Missing/malformed cart matrix')
    bones = row.get('bones')
    require(isinstance(bones, dict) and bones and all(matrix(v) for v in bones.values()), 'Missing/malformed bone matrices')
    require(all('Bip01_' + side + '_Hand' in bones for side in 'LR'), 'Missing hand bones')
    return row


def coverage(rows, key, epoch, window, label):
    a, b = (epoch + value for value in window)
    selected = [r for r in rows if a <= r[key] <= b]
    require(len(selected) >= 5, label + ': fewer than five samples')
    times = sorted({r[key] for r in selected})
    require(len(times) >= 5, label + ': fewer than five distinct timestamps')
    require(times[0] <= a + 350 and times[-1] >= b - 350, label + ': missing window edges')
    require(times[-1] - times[0] >= .55 * (b - a), label + ': insufficient time span')
    require(max(y - x for x, y in zip(times, times[1:])) <= 600, label + ': sampling gap exceeds 600ms')
    return selected


def transform(matrix, point):
    return [sum(matrix[col * 4 + row] * point[col] for col in range(4)) for row in range(3)]


def wheel(row):
    c = row['cart']
    return (c[1] * -6.642862e-6 + c[5] * -.0041269097 + c[9] * -.0010569958 + c[13]
            - .001062454 * math.hypot(c[5], c[9]) - .00024333253 * abs(c[1]))


def palm(row, side):
    actual = transform(row['bones']['Bip01_' + side + '_Hand'], [.055, 0, .024 if row['female'] else .020, 1])
    wanted = transform(row['cart'], [.00172237 if side == 'L' else -.00172238, .00541905, -.00342593, 1])
    return math.dist(actual, wanted)


def analyze(profile):
    profile = Path(profile)
    selection = parse((profile / 'selection.json').read_text())
    require(isinstance(selection, dict) and selection.get('suite') in ('cart_motion_mp', 'wooden_cart_multiplayer')
            and selection.get('kind') == 'mp' and selection.get('mode') == 'toolkit'
            and selection.get('cases') == ['owner_observer_motion'], 'Frozen selection does not match the Cart MP capture')
    logs = {role: (profile / (role + '-launch.log')).read_text() for role in ROLES}
    for role, text in logs.items():
        require('[CLEARANCE_PROBE] ERROR' not in text and '[GRIP_POSE_PROBE] ERROR' not in text, role + ': probe error')
        require('[QUEUE_TEST] FAIL' not in text, role + ': fixture failure')
    epochs = re.findall(r'\[CART_MP\] START epoch=(\d+)', logs['server'])
    require(len(epochs) == 1, 'Exactly one server scenario epoch required')
    epoch = int(epochs[0])
    for role in ('client1', 'client2'):
        require(re.findall(r'\[CART_MP\] START epoch=(\d+)', logs[role]) == epochs, role + ': mismatched epoch')
        events = [parse(line.split('[QUEUE_CHECK] ', 1)[1]) for line in logs[role].splitlines() if '[QUEUE_CHECK] ' in line]
        require(all(isinstance(e, dict) for e in events), role + ': malformed capture receipt')
        require([e.get('event') for e in events] == ['setup', 'case', 'complete'], role + ': incomplete/duplicate capture receipts')
        require(all(e.get('actor') == role and e.get('suite') == 'cart_motion_mp' and e.get('kind') == 'mp' and ('mode' not in e or e['mode'] == selection['mode']) for e in events), role + ': capture receipt identity mismatch')
        require(events[0].get('cases') == ['owner_observer_motion'] and type(events[0].get('expected')) is int and events[0]['expected'] == 1, role + ': setup selection mismatch')
        require(events[1].get('id') == 'owner_observer_motion' and events[1].get('status') == 'captured', role + ': missing capture receipt')
        require(all(type(events[2].get(key)) is int and events[2][key] == value for key, value in {'expected': 1, 'performed': 1, 'skipped': 0, 'failed': 0}.items()), role + ': unsuccessful capture completion')
        phases = re.findall(r'\[CART_MP\] PHASE ([a-z-]+) wall=(\d+) elapsed=(\d+)', logs[role])
        require([phase[0] for phase in phases] == ['idle', 'walk', 'turn', 'stop', 'reverse', 'stop-back'], role + ': missing/duplicate scenario phase')
        for (_, wall, elapsed), target in zip(phases, (0, 2000, 5000, 8000, 10000, 12000)):
            require(target <= int(elapsed) <= target + 600 and int(wall) - epoch == int(elapsed), role + ': scenario phase timing mismatch')
    require(parse((profile / 'execution.json').read_text()).get('status') == 'completed', 'Native runner did not complete')
    states = {role: [state(parse(line.split('[CART_MP_STATE] ', 1)[1])) for line in text.splitlines()
                     if '[CART_MP_STATE] ' in line] for role, text in logs.items()}
    ids = {r['id'] for r in states['client1'] if r['user'] == 'client1'}
    require(len(ids) == 1, 'Unique owner onlineID required')
    identity = next(iter(ids))
    require(identity >= 0, 'Owner onlineID must be assigned')
    for role in ROLES:
        require(all(r['user'] == 'client1' for r in states[role] if r['id'] == identity), role + ': owner ID reused')
        require(all(r['id'] == identity for r in states[role] if r['user'] == 'client1'), role + ': owner ID changed')
        states[role] = [r for r in states[role] if r['id'] == identity and r['user'] == 'client1']
    active = [r for r in states['client1'] if epoch <= r['wall'] <= epoch + 15000]
    cartids = {r['primary'] for r in active}
    require(len(cartids) == 1 and next(iter(cartids)) >= 0, 'Unique equipped owner cartID required')
    cartid = next(iter(cartids))
    poses = {}
    for role in ('client1', 'client2'):
        poses[role] = [pose(parse(line)) for line in (profile / role / 'body-clearance.jsonl').read_text().splitlines()]
        require(poses[role] and all(r['id'] == identity for r in poses[role]), role + ': missing/unexpected rendered owner')
    result = {'ownerOnlineID': identity, 'cartID': cartid, 'epoch': epoch, 'modeSource': 'selection.json', 'evidenceComplete': True,
              'scope': 'Capture coverage and raw diagnostics only; no animation equivalence PASS', 'phases': {}}
    for name, window in WINDOWS.items():
        phase = {}
        for role, rows in states.items():
            selected = coverage(rows, 'wall', epoch, window, name + '/' + role + '/state')
            require(all(r['primary'] == r['secondary'] == cartid and r['item'] == ITEM for r in selected), name + '/' + role + ': cart mismatch')
            require(all(r['local'] is (role == 'client1') for r in selected), name + '/' + role + ': local identity mismatch')
            if role == 'client1':
                require(all(r['enabled'] for r in selected), name + ': owner cart patch disabled')
            phase[role] = {'samples': len(selected), **{key: sorted({r[key] for r in selected}) for key in ('enabled', 'motion', 'pivot', 'run', 'sprint')},
                           'stepYRange': [min(r['stepY'] for r in selected), max(r['stepY'] for r in selected)],
                           'paceRange': [min(r['pace'] for r in selected), max(r['pace'] for r in selected)],
                           'bankMaxDegrees': max(abs(math.degrees(r['bank'])) for r in selected)}
        for role, rows in poses.items():
            selected = coverage(rows, 'wallTimeMillis', epoch, window, name + '/' + role + '/render')
            require(all(r['local'] is (role == 'client1') for r in selected), name + '/' + role + ': rendered local mismatch')
            require(all(r['primary'] == r['secondary'] == cartid for r in selected), name + '/' + role + ': rendered cart mismatch')
            if role == 'client1':
                require(all(r['enabled'] for r in selected), name + ': owner render patch disabled')
            phase[role]['render'] = {'frames': len(selected), 'enabled': sorted({r['enabled'] for r in selected}),
                                    'wheelFloorRange': [min(wheel(r) for r in selected), max(wheel(r) for r in selected)],
                                    'palmHandleErrorMax': {side: max(palm(r, side) for r in selected) for side in 'LR'},
                                    'palmHandleErrorMedian': {side: statistics.median(palm(r, side) for r in selected) for side in 'LR'}}
        result['phases'][name] = phase
    stop = {role: coverage(rows, 'wall', epoch, WINDOWS['settled-stop'], role + '/final') for role, rows in states.items()}
    owner = max(stop['client1'], key=lambda r: r['wall'])
    result['finalPositionDeltaFromOwner'] = {role: math.hypot(max(rows, key=lambda r: r['wall'])['x'] - owner['x'], max(rows, key=lambda r: r['wall'])['y'] - owner['y']) for role, rows in stop.items()}
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    report = analyze(args.profile)
    with args.output.open('x') as output:
        output.write(json.dumps(report, indent=2, allow_nan=False) + '\n')
    print('Evidence complete; animation equivalence is not asserted.')
