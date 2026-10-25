"""Strict offline evidence coverage and diagnostics; never asserts animation equivalence."""
from pathlib import Path
import argparse
import json
import math
import re
import statistics
import runpy

ROLES = ('server', 'client1', 'client2')
WINDOWS = {'idle': (300, 1700), 'walk': (2500, 4500), 'turn': (5500, 7500),
           'stop': (8500, 9500), 'reverse': (10500, 11500), 'settled-stop': (13000, 14500)}
BOOLS = ('local', 'enabled', 'run', 'sprint', 'motion', 'pivot')
NUMBERS = ('wall', 'x', 'y', 'z', 'heading', 'stepX', 'stepY', 'pace', 'bank')
VARIANTS = {'shopping-cart': 'SaucedCarts.ShoppingCart', 'wooden-wheelbarrow': 'SaucedWheelbarrow.WheelbarrowWood',
            'metal-wheelbarrow': 'SaucedWheelbarrow.WheelbarrowMetal'}
MODELS = {'shopping-cart': {'ShoppingCartModel', 'ShoppingCartPartialModel', 'ShoppingCartFullModel',
                           'ShoppingCartFlashlightModel', 'ShoppingCartFlashlightPartialModel', 'ShoppingCartFlashlightFullModel'},
          'wooden-wheelbarrow': {'WheelbarrowWood'}, 'metal-wheelbarrow': {'WheelbarrowMetal'}}
# The fixture creates an unupgraded cart and fills it to effective capacity.
FILLED_MODELS = {'shopping-cart': 'ShoppingCartFullModel', 'wooden-wheelbarrow': 'WheelbarrowWood',
                 'metal-wheelbarrow': 'WheelbarrowMetal'}
HELD_MODELS = {variant: {model, 'Base.'+model} for variant,model in FILLED_MODELS.items()}
ACTION_PHASES = ('drop-complete', 'pickup-complete', 'drop-cancel', 'drop-repeat', 'pickup-cancel', 'pickup-repeat')
ACTION_GROUND = (True, False, False, True, True, False)


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


def model_diagnostics(row):
    keys=('heldModel','overridePrimary','overrideSecondary')
    if 'modelProbeVersion' in row or any(key in row for key in keys):
        require(type(row.get('modelProbeVersion')) is int and row['modelProbeVersion']==1,
                'Missing or unknown model probe version')
        require(all(key in row and (row[key] is None or isinstance(row[key],str)) for key in keys),
                'Missing or malformed held/override model diagnostics')


def state(row):
    require(isinstance(row, dict), 'State row must be an object')
    require(all(type(row.get(key)) is bool for key in BOOLS), 'Missing/malformed state boolean')
    require(all(number(row.get(key)) for key in NUMBERS), 'Missing/malformed state number')
    require(all(type(row.get(key)) is int for key in ('id', 'primary', 'secondary')), 'Malformed state identity')
    require(isinstance(row.get('user'), str) and isinstance(row.get('item'), str), 'Missing state actor/item')
    require(isinstance(row.get('tracks'), str), 'Missing animation tracks')
    require(not re.search(r'(?:NaN|Infinity|(?<![A-Za-z])(?:nan|inf)(?![A-Za-z]))', row['tracks']), 'Nonfinite animation track')
    model_diagnostics(row)
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
    model_diagnostics(row)
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


def action_draws(profile, role):
    """Actual DrawSolid callbacks, kept separate from the prepared pose snapshots."""
    source = Path(profile) / role / 'render-camera.jsonl'
    require(source.is_file(), role + ': missing actual action body/cart draw proof')
    result = {}
    for line in source.read_text().splitlines():
        row = parse(line)
        require(isinstance(row, dict) and row.get('renderProbeVersion') == 1
                and type(row.get('captureId')) is int and row['captureId'] > 0
                and row.get('part') in ('body', 'cart'), role + ': malformed action draw proof')
        key = (row['captureId'], row['part'])
        require(key not in result, role + ': duplicate action draw proof')
        result[key] = row
    return result


def drawn_action_frames(frames, draws, role, cartid, variant):
    result = []
    for frame in frames:
        require(frame.get('renderProbeVersion') == 1 and type(frame.get('captureId')) is int
                and type(frame.get('slotToken')) is int and number(frame.get('nativeWallTimeMillis')),
                role + ': missing original action render identity')
        pair = [draws.get((frame['captureId'], part)) for part in ('body', 'cart')]
        if all(row is None for row in pair):
            continue  # Prepared off-screen poses do not establish an actual draw.
        require(all(row is not None for row in pair), role + ': incomplete actual action body/cart draw')
        for row in pair:
            # Inventory can advance between preparation and the render thread's
            # draw. Bind identity to the exact frozen slot; retain live hands as
            # separately validated diagnostics, never as prepared-model evidence.
            require(row.get('id') == frame['id'] and row.get('preparedPrimary') == frame['primary']
                    and row.get('preparedSecondary') == frame['secondary']
                    and all(type(row.get(k)) is int for k in ('preparedPrimary', 'preparedSecondary', 'primary', 'secondary'))
                    and row.get('slotToken') == frame['slotToken'] and row.get('captureWallTimeMillis') == frame['wallTimeMillis']
                    and all(number(row.get(k)) for k in ('cameraWallTimeMillis', 'wallTimeMillis', 'cameraX', 'cameraY', 'cameraZ', 'cameraAngle'))
                    and frame['nativeWallTimeMillis'] <= frame['wallTimeMillis'] <= row['cameraWallTimeMillis'] <= row['wallTimeMillis'] <= frame['wallTimeMillis']+1000
                    and row.get('cameraWorldIso') is True and row.get('cameraInVehicle') is False,
                    role + ': stale/foreign actual action draw')
            if row['part'] == 'cart':
                require(row.get('model') == frame['model'] == FILLED_MODELS[variant], role + ': action draw fill/model mismatch')
        require(frame.get('cartItemId') == cartid and frame.get('cartItemSource') == ('transition' if frame['primary'] == -1 else 'hands')
                and frame.get('cartItemModel') in HELD_MODELS[variant] and frame.get('modelProbeVersion') == 1
                and (frame.get('heldModel') is None if frame['primary'] == -1 else frame.get('heldModel') in HELD_MODELS[variant])
                and all(frame.get(key) in (None, '') or frame.get(key) in HELD_MODELS[variant] for key in ('overridePrimary', 'overrideSecondary')),
                role + ': action rendered model lacks exact native cart identity/fill')
        result.append(frame)
    return result


def action_coverage(logs, poses, cartid, epoch, duration, variant='wooden-wheelbarrow', profile=None):
    def rows(role, kind):
        marker = '[CART_MP_ACTION] ' + kind + ' '
        values = [parse(line.split(marker, 1)[1]) for line in logs[role].splitlines() if marker in line]
        require(all(isinstance(row, dict) for row in values), role + '/' + kind + ': malformed action object')
        return values
    def ordered(values, label):
        require([(r.get('index'), r.get('phase')) for r in values] == list(enumerate(ACTION_PHASES, 1)), label + ': missing/duplicate/reordered action phases')
        require(all(r.get('id') == cartid and number(r.get('wall')) for r in values), label + ': wrong action identity/time')
        require(all(a['wall'] < b['wall'] for a, b in zip(values, values[1:])), label + ': reordered action timestamps')
        return values
    begins = ordered(rows('client1', 'BEGIN'), 'owner begin')
    owner = ordered(rows('client1', 'RECEIPT'), 'owner receipt')
    server_begin = ordered(rows('server', 'SERVER_BEGIN'), 'server begin')
    server = ordered(rows('server', 'SERVER_RECEIPT'), 'server receipt')
    require(begins[0]['wall'] >= epoch+duration and server[-1]['wall'] <= epoch+duration+35000, 'Action bank outside bounded post-motion window')
    done = rows('server', 'ALL_COMPLETE')
    require(len(done) == 1 and done[0].get('id') == cartid and done[0].get('phases') == 6
            and number(done[0].get('wall')) and done[0]['wall'] >= server[-1]['wall'], 'Missing authoritative ActionsDone')
    cargo = (server[0].get('cargoID'), server[0].get('cargoWeight'))
    require(type(cargo[0]) is int and cargo[0] >= 0 and number(cargo[1]) and cargo[1] > 0, 'Missing authoritative cargo identity')
    cancels = rows('client1', 'CANCEL')
    require([(r.get('index'), r.get('phase')) for r in cancels] == [(3, 'drop-cancel'), (5, 'pickup-cancel')], 'Missing/duplicate/reordered native cancellations')
    require(all(r.get('id') == cartid and number(r.get('progress')) and .35 <= r['progress'] < .55 for r in cancels), 'Native cancellation outside progress window')
    for index, (begin, receipt, check, ground) in enumerate(zip(begins, owner, server, ACTION_GROUND)):
        label = ACTION_PHASES[index]
        require(begin['wall'] <= server_begin[index]['wall'] < check['wall'] and begin['wall'] < receipt['wall'] <= check['wall']
                and check['wall']-receipt['wall'] < 3500, label + ': action/authority window reordered or expired')
        require(index == 0 or begin['wall'] >= server[index-1]['wall'], label + ': next action preceded server acknowledgement')
        for role, row in (('client1', receipt), ('server', check)):
            require(row.get('actor') == role and (row.get('cargoID'), row.get('cargoWeight')) == cargo
                    and row.get('cargoPreserved') is True and row.get('inventoryCount') == int(not ground)
                    and row.get('worldCount') == int(ground) and row.get('primaryID') == (-1 if ground else cartid)
                    and row.get('secondaryID') == (-1 if ground else cartid) and row.get('nativeActions') == 0
                    and row.get('hasPath') is False, label + '/' + role + ': cargo/ownership/queue mismatch')
        cancelled = index in (2, 4)
        require(begin.get('cancel') is cancelled and receipt.get('luaActions') == 0 and receipt.get('cancelled') is cancelled
                and receipt.get('nativeProgress') is True and receipt.get('presentationProgress') is True
                and receipt.get('recoveryEnded') is True and receipt.get('recoveryObserved') is cancelled
                and number(receipt.get('elapsed')) and 0 < receipt['elapsed'] < 10000
                and abs(receipt['elapsed']-(receipt['wall']-begin['wall'])) <= 100, label + ': native progress/cancellation/recovery missing')
        if cancelled:
            cancellation = cancels[0 if index == 2 else 1]
            require(number(cancellation.get('wall')) and begin['wall'] <= cancellation['wall'] < receipt['wall'], label + ': cancellation outside native action window')
        require(check.get('ok') is True and check.get('ground') is ground and check.get('held') is (not ground)
                and number(check.get('holdMs')) and 100 <= check['holdMs'] < 3000, label + ': independent server endpoint missing')
    result = {}
    for role in ('client1', 'client2'):
        draws = action_draws(profile, role) if variant != 'wooden-wheelbarrow' else None
        windows = ordered(rows(role, 'WINDOW'), role + '/window')
        acknowledgements = ordered(rows(role, 'SERVER_ACK'), role + '/ack')
        finished = rows(role, 'SERVER_DONE')
        require(len(finished) == 1 and finished[0].get('ok') is True and finished[0].get('id') == cartid
                and finished[0].get('phases') == 6 and finished[0].get('serverWall') == done[0]['wall']
                and number(finished[0].get('wall')), role + ': final server broadcast missing')
        for index, (window, ack, source) in enumerate(zip(windows, acknowledgements, server)):
            require(window.get('serverWall') == server_begin[index]['wall'] and ack.get('serverWall') == source['wall']
                    and 0 <= ack['wall']-source['wall'] < 3500 and ack.get('ok') is True
                    and all(ack.get(key) == source.get(key) for key in ('cargoID', 'cargoWeight', 'cargoPreserved', 'inventoryCount', 'worldCount', 'primaryID', 'secondaryID', 'nativeActions', 'hasPath', 'held', 'ground')),
                    role + ': authoritative acknowledgement differs')
        samples = rows(role, 'PRESENTATION')
        require(all(r.get('actor') == role and type(r.get('index')) is int and 1 <= r['index'] <= 6
                    and r.get('phase') == ACTION_PHASES[r['index']-1] and r.get('id') == cartid
                    and number(r.get('wall')) and number(r.get('progress')) and 0 <= r['progress'] <= 1
                    and all(type(r.get(key)) is bool for key in ('active', 'recovering', 'pickup', 'rendered', 'ik'))
                    and all(type(r.get(key)) is int for key in ('primaryID', 'secondaryID')) for r in samples), role + ': malformed presentation sample')
        require(all(a['wall'] < b['wall'] and a['index'] <= b['index'] for a, b in zip(samples, samples[1:])), role + ': reordered presentation samples')
        phases = []
        for index, name in enumerate(ACTION_PHASES):
            selected = [r for r in samples if r['index'] == index+1 and r['wall'] <= acknowledgements[index]['wall']]
            require(selected and all(windows[index]['wall'] <= r['wall'] for r in selected), role + '/' + name + ': missing phase samples')
            active = [r for r in selected if r['active'] and r['progress'] > .05]
            presented = [r for r in active if r['rendered'] and r['ik']]
            require(len(active) >= 2 and active[-1]['wall']-active[0]['wall'] >= 50
                    and max(r['progress'] for r in active)-min(r['progress'] for r in active) > .05
                    and all(b['progress'] >= a['progress']-.02 for a, b in zip(active, active[1:]))
                    and len(presented) >= 2 and presented[-1]['wall']-presented[0]['wall'] >= 50
                    and max(r['progress'] for r in presented)-min(r['progress'] for r in presented) > .05,
                    role + '/' + name + ': native active/progress/render/IK coverage missing')
            require(all(r['pickup'] is name.startswith('pickup') for r in selected if r['active'] or r['recovering']), role + '/' + name + ': presentation direction differs')
            require(index not in (2, 4) or any(r['recovering'] and r['progress'] > 0 for r in selected), role + '/' + name + ': cancellation recovery sample missing')
            frames = [r for r in poses[role] if begins[index]['wall'] <= r['wallTimeMillis'] <= owner[index]['wall']
                      and r['primary'] == r['secondary'] == (-1 if name.startswith('pickup') else cartid)]
            if draws is not None:
                frames = drawn_action_frames(frames, draws, role, cartid, variant)
            frames = coverage(frames, 'wallTimeMillis', 0, (presented[0]['wall'], presented[-1]['wall']), role + '/' + name + '/action render')
            require(all(r['local'] is (role == 'client1') for r in frames), role + '/' + name + ': raw action render identity mismatch')
            phase = {'phase': name, 'activeSamples': len(active), 'renderFrames': len(frames),
                     'recoverySamples': sum(r['recovering'] for r in selected)}
            if variant == 'wooden-wheelbarrow':
                phase.update(wheelFloorRange=[min(wheel(r) for r in frames), max(wheel(r) for r in frames)],
                             palmHandleErrorMax={side: max(palm(r, side) for r in frames) for side in 'LR'})
            else:
                require(all(r.get('model') == FILLED_MODELS[variant] for r in frames), role + '/' + name + ': action rendered another cart fill/model')
                phase.update(models=sorted({r['model'] for r in frames}), rawTransformCoverage=True, nativeDrawCoverage=True,
                             scope='Exact cart action matrices, actual body/cart draws and lifecycle; geometry and animation equivalence require separate review')
            phases.append(phase)
        quiet = [r for r in samples if r['index'] == 6 and r['wall'] >= finished[0]['wall']]
        require(len(quiet) >= 2 and quiet[-1]['wall']-quiet[0]['wall'] >= 100
                and quiet[-1]['wall'] >= finished[0]['wall']+200
                and all(not r['active'] and not r['recovering'] for r in quiet), role + ': final presentation quiescence missing')
        result[role] = phases
    return {'evidenceComplete': True, 'cargoID': cargo[0], 'cargoWeight': cargo[1], 'phases': result}



def hotkey_coverage(logs, cartid, configured_key=None):
    """Require real input dispatch, started constructor data and three native endpoints."""
    def rows(role, kind, indices):
        marker = '[CART_MP_ACTION] ' + kind + ' '
        values = [parse(line.split(marker, 1)[1]) for line in logs[role].splitlines() if marker in line]
        require(all(isinstance(row, dict) for row in values), role + '/' + kind + ': malformed object')
        require([(r.get('index'), r.get('phase')) for r in values] == [(i, ACTION_PHASES[i-1]) for i in indices],
                role + '/' + kind + ': missing/duplicate/reordered hotkey evidence')
        require(all(r.get('id') == cartid and number(r.get('wall')) for r in values), role + '/' + kind + ': wrong identity/time')
        return {r['index']: r for r in values}
    def placement(actual, expected, label, epsilon=.002):
        require(isinstance(actual, dict) and isinstance(expected, dict)
                and all(number(row.get(k)) for row in (actual, expected) for k in ('x', 'y', 'z', 'rotation')),
                label + ': missing/nonfinite world pose')
        require(all(abs(actual[k]-expected[k]) <= epsilon for k in ('x', 'y', 'z'))
                and abs((actual['rotation']-expected['rotation']+180) % 360-180) <= .01,
                label + ': exact world placement differs from started native drop')
    begins = rows('client1', 'BEGIN', range(1, 7))
    inputs = rows('client1', 'INPUT', (1, 3, 4))
    queued = rows('client1', 'QUEUED', (1, 3, 4))
    released = rows('client1', 'RELEASED', (1, 3, 4))
    serialized = rows('client1', 'SERIALIZED', (1, 3, 4))
    owner = rows('client1', 'RECEIPT', range(1, 7))
    server = rows('server', 'SERVER_RECEIPT', range(1, 7))
    observer = rows('client2', 'OBSERVER_RECEIPT', range(1, 7))
    forwarded = rows('server', 'SERVER_OBSERVATION', range(1, 7))
    for index, begin in begins.items():
        require(begin.get('inputRoute') == ('hotkey' if index in inputs else 'menu'), 'Frozen hotkey input route differs')
    for index, row in inputs.items():
        created, started = queued[index], serialized[index]
        require(row.get('actor') == 'client1' and row.get('inputRoute') == 'hotkey'
                and row.get('event') == 'OnKeyStartPressed' and row.get('events') == ['OnKeyStartPressed', 'OnCustomUIKeyPressed']
                and type(row.get('key')) is int and 0 < row['key'] < 256
                and row.get('rebound') is (configured_key is not None)
                and (configured_key is None or row['key'] == configured_key),
                'Installed PushCart key event missing')
        # ISBaseTimedAction.create applies physiological modifiers to Lua maxTime.
        # LuaTimedActionNew constructs native maxTime via KahluaNumberConverter$2:
        # Double.intValue truncates positive fractions to the actual native tick count.
        require(number(created.get('maxTime')) and number(started.get('maxTime'))
                and created['maxTime'] == started['maxTime'] and int(created['maxTime']) == 88,
                'Hotkey queued/started native duration differs from 88 ticks')
        require(created.get('actor') == started.get('actor') == 'client1' and created.get('inputRoute') == 'hotkey'
                and created.get('actionType') == started.get('actionType') == 'ToolkitWoodCartDrop'
                and started.get('started') is True,
                'Hotkey did not retain native wooden drop lifecycle')
        require(begins[index]['wall'] <= row['wall'] <= created['wall'] <= started['wall'] < owner[index]['wall'],
                'Input/queued/started native evidence reordered')
        require(all(type(started.get(k)) is int for k in ('sqX', 'sqY', 'sqZ'))
                and all(number(started.get(k)) for k in ('xoffset', 'yoffset', 'zoffset', 'rotation'))
                and 0 < started['xoffset'] < 1 and 0 < started['yoffset'] < 1
                and started['zoffset'] == 0 and 0 <= started['rotation'] < 360 and started.get('isMultiple') is False,
                'Native serialized drop constructor fields missing/unsafe')
        release = released[index]
        require(release.get('actor') == 'client1' and release.get('key') == row['key']
                and release.get('events') == ['OnKeyPressed', 'OnCustomUIKey', 'OnCustomUIKeyReleased']
                and release.get('actionType') == 'ToolkitWoodCartDrop' and release.get('queuedCount') == 1
                and release.get('sameAction') is True and created['wall'] <= release['wall'] < owner[index]['wall'],
                'Native hotkey release is missing, uncorrelated or duplicated the queued action')
        if row['key'] == 18:
            require(release.get('nativeE') is True and release.get('nativeDownSeen') is True
                    and number(release.get('heldMs')) and release['heldMs'] >= 150
                    and owner[index].get('nativeE') is True and owner[index].get('ignoreRestored') is True,
                    'Host native E hold/release/context restoration was not observed')
        actual = dict(x=started['sqX']+started['xoffset'], y=started['sqY']+started['yoffset'],
                      z=started['sqZ']+started['zoffset'], rotation=started['rotation'])
        placement(started.get('expectedWorld'), actual, 'serialized constructor', 1e-7)
        placement(actual, started.get('plannedWorld'), 'refreshed drop pose', .000011)
    cargo = (owner[1].get('cargoID'), owner[1].get('cargoWeight'))
    for index, ground in enumerate(ACTION_GROUND, 1):
        observed = observer[index]
        require(observed.get('actor') == 'client2' and (observed.get('cargoID'), observed.get('cargoWeight')) == cargo
                and observed.get('cargoPreserved') is True and observed.get('inventoryCount') is None
                and observed.get('inventoryScope') == 'remote-hand-snapshot'
                and observed.get('itemSource') == ('world' if ground else 'hands') and observed.get('handSameItem') is (not ground)
                and observed.get('worldCount') == int(ground) and observed.get('primaryID') == (-1 if ground else cartid)
                and observed.get('secondaryID') == (-1 if ground else cartid) and observed.get('worldAttached') is ground
                and observed.get('luaActions') == 0 and observed.get('nativeActions') == 0 and observed.get('hasPath') is False,
                ACTION_PHASES[index-1] + ': observer native cargo/ownership/queue differs')
        require(owner[index]['wall'] <= observed['wall'] <= server[index]['wall']
                and server[index]['wall']-owner[index]['wall'] < 3500,
                'Observer replication did not settle within authoritative audit window')
        require(forwarded[index] == observed, 'Server observer receipt differs from native observation')
        if ground:
            expected = serialized[1 if index == 1 else 4]['expectedWorld']
            for role, row in (('client1', owner[index]), ('server', server[index]), ('client2', observed)):
                placement(row.get('expectedWorld'), expected, role + '/expected')
                placement(row.get('worldPose'), expected, role + '/native world')
        else:
            require(all(row.get('worldPose') is None for row in (owner[index], server[index], observed)),
                    'Held endpoint retained native world object')
    return {'evidenceComplete': True, 'inputEvent': 'OnKeyStartPressed', 'dropPhases': 3,
            'configuredKey': configured_key, 'completeTap': True, 'nativeDurationTicks': 88,
            'durationConversion': 'LuaTimedActionNew / KahluaNumberConverter$2 / Double.intValue',
            'worldEndpointRoles': ['client1', 'server', 'client2'], 'positionTolerance': .002, 'rotationToleranceDegrees': .01}

def analyze(profile):
    profile = Path(profile)
    selection = parse((profile / 'selection.json').read_text())
    require(isinstance(selection, dict) and selection.get('suite') in ('cart_motion_mp', 'wooden_cart_multiplayer')
            and selection.get('kind') == 'mp' and selection.get('mode') == 'toolkit'
            and selection.get('cases') == ['owner_observer_motion'], 'Frozen selection does not match the Cart MP capture')
    injury_module=runpy.run_path(str(Path(__file__).with_name('analyze-injury.py')))
    injury=injury_module['validate_options'](selection.get('options', {}), require)
    if 'cart_wall_exit' in selection.get('options', {}):
        return runpy.run_path(str(Path(__file__).with_name('analyze-wall.py')))['analyze'](profile, selection, globals())
    extended = selection.get('options', {}).get('cart_fast_motion', False)
    require(type(extended) is bool, 'cart_fast_motion must be boolean')
    actions = selection.get('options', {}).get('cart_actions', False)
    require(type(actions) is bool, 'cart_actions must be boolean')
    hotkey = selection.get('options', {}).get('cart_hotkey_setdown', False)
    require(type(hotkey) is bool, 'cart_hotkey_setdown must be boolean')
    require(not hotkey or actions, 'cart_hotkey_setdown requires cart_actions')
    hotkey_key = selection.get('options', {}).get('cart_hotkey_key')
    require('cart_hotkey_key' not in selection.get('options', {})
            or type(hotkey_key) is int and 0 < hotkey_key < 256 and hotkey,
            'cart_hotkey_key requires hotkey setdown and an integer keyboard code in 1..255')
    variant = selection.get('options', {}).get('cart_variant', 'wooden-wheelbarrow')
    require(isinstance(variant, str) and variant in VARIANTS, 'cart_variant must be an exact supported MP variant')
    item = VARIANTS[variant]
    expected_phases = [('idle', 0), ('walk', 2000), ('turn', 5000), ('stop', 8000), ('reverse', 10000), ('stop-back', 12000)]
    if extended:
        expected_phases += [('run', 15000), ('sprint-turn', 16500), ('fast-stop', 18500)]
    if injury:
        expected_phases += [(name,target) for name,target,_,_ in injury_module['PHASES']]
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
        require(events[1].get('cartActions', False) is actions, role + ': action capture differs from selection')
        require(events[1].get('cartInjury', False) is injury, role + ': injury capture differs from selection')
        require(all(type(events[2].get(key)) is int and events[2][key] == value for key, value in {'expected': 1, 'performed': 1, 'skipped': 0, 'failed': 0}.items()), role + ': unsuccessful capture completion')
        phases = re.findall(r'\[CART_MP\] PHASE ([a-z-]+) wall=(\d+) elapsed=(\d+)', logs[role])
        require([phase[0] for phase in phases] == [p[0] for p in expected_phases], role + ': missing/duplicate scenario phase')
        for (_, wall, elapsed), (_, target) in zip(phases, expected_phases):
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
    windows = dict(WINDOWS)
    if extended:
        windows.update({'run': (15300, 16200), 'sprint-turn': (17000, 18200),
                        'fast-stop': (18600, 20000), 'fast-settled': (24500, 25500)})
        pads=[parse(line.split('[CART_MP] CART_PAD ',1)[1]) for line in logs['server'].splitlines() if '[CART_MP] CART_PAD ' in line]
        require(len(pads)==1, 'Unique authoritative extended pad descriptor required')
        pad=pads[0]
        pad_size,pad_version=(63,5) if injury else (31,3)
        require(all(number(pad.get(k)) for k in ('minX','minY','z')) and pad.get('bankVersion')==pad_version
                and pad.get('size')==pad_size and pad.get('margin')==2 and pad.get('vegetationFree') is True
                and pad.get('elevated') is True and pad['z']==7 and pad.get('floorSprite')=='carpentry_02_57',
                'Extended bank requires native elevated vegetation-free'+str(pad_size)+'x'+str(pad_size)+' pad with two tile cart margin')
        for role in ('client1','client2'):
            setups=[parse(line.split('[CART_MP] SETUP ',1)[1]) for line in logs[role].splitlines() if '[CART_MP] SETUP ' in line]
            require(setups and all(all(row.get(k)==pad[k] for k in ('minX','minY','z','bankVersion','size','margin','vegetationFree','elevated','floorSprite')) for row in setups),
                    role+': authoritative pad bounds were not shared')
            ready=[parse(line.split('[CART_MP] PAD_READY ',1)[1]) for line in logs[role].splitlines() if '[CART_MP] PAD_READY ' in line]
            require(len(ready)==1 and ready[0].get('floors')==pad_size*pad_size and number(ready[0].get('wall')) and ready[0]['wall']<epoch
                    and all(ready[0].get(k)==pad[k] for k in ('minX','minY','z','bankVersion','size')),
                    role+': every native replicated floor was not observed')
        for role,rows in states.items():
            require(all(pad['minX']+pad['margin']<=r['x']<=pad['minX']+pad['size']-pad['margin']
                        and pad['minY']+pad['margin']<=r['y']<=pad['minY']+pad['size']-pad['margin']
                        and abs(r['z']-pad['z'])<.25 for r in rows if r['wall']>=epoch-2000),
                    role+': owner/cart left validated pad interior during video')
    active = [r for r in states['client1'] if epoch <= r['wall'] <= epoch + (injury_module['DURATION'] if injury else 26000 if extended else 15000)]
    cartids = {r['primary'] for r in active}
    require(len(cartids) == 1 and next(iter(cartids)) >= 0, 'Unique equipped owner cartID required')
    cartid = next(iter(cartids))
    specs = [parse(line.split('[CART_MP] CART_SPEC ', 1)[1]) for line in logs['server'].splitlines() if '[CART_MP] CART_SPEC ' in line]
    require(not ('cart_variant' in selection.get('options', {})) or specs, 'Selected cart variant lacks authoritative cargo descriptor')
    require(len(specs) <= 1, 'Duplicate authoritative cart descriptor')
    spec = specs[0] if specs else None
    if spec is not None:
        require(spec.get('variant') == variant and spec.get('cartType') == item and spec.get('id') == cartid
                and spec.get('cargoCount') == 1 and type(spec.get('cargoID')) is int and spec['cargoID'] >= 0
                and number(spec.get('cargoWeight')) and spec['cargoWeight'] > 0, 'Authoritative cart variant/cargo descriptor mismatch')
    poses = {}
    for role in ('client1', 'client2'):
        poses[role] = [pose(parse(line)) for line in (profile / role / 'body-clearance.jsonl').read_text().splitlines()]
        require(poses[role] and all(r['id'] == identity for r in poses[role]), role + ': missing/unexpected rendered owner')
        if spec is not None:
            require(all(r.get('model') in MODELS[variant] for r in poses[role]), role + ': raw render model differs from selected cart')
    result = {'ownerOnlineID': identity, 'cartID': cartid, 'epoch': epoch, 'modeSource': 'selection.json', 'evidenceComplete': True,
              'scope': 'Capture coverage and raw diagnostics only; no animation equivalence PASS',
              'cartVariant': variant, 'cartType': item, 'phases': {}}
    if spec is not None:
        result['cargo'] = {'id': spec['cargoID'], 'weight': spec['cargoWeight'], 'count': 1}
    if extended:
        result['checkedPad']=pad
    for name, window in windows.items():
        phase = {}
        for role, rows in states.items():
            selected = coverage(rows, 'wall', epoch, window, name + '/' + role + '/state')
            require(all(r['primary'] == r['secondary'] == cartid and r['item'] == item for r in selected), name + '/' + role + ': cart mismatch')
            if spec is not None:
                require(all(r.get('cargoCount') == 1 and r.get('cargoID') == spec['cargoID']
                            and number(r.get('cargoWeight')) and abs(r['cargoWeight']-spec['cargoWeight']) < .001 for r in selected),
                        name + '/' + role + ': actual cart cargo differs from authoritative descriptor')
            require(all(r['local'] is (role == 'client1') for r in selected), name + '/' + role + ': local identity mismatch')
            if role == 'client1':
                require(all(r['enabled'] for r in selected), name + ': owner cart patch disabled')
            if role != 'server' and any('modelProbeVersion' in r for r in selected):
                require(all(r.get('modelProbeVersion')==1 and r.get('heldModel') in HELD_MODELS[variant] for r in selected),
                        name+'/'+role+': held static model differs from selected full cart')
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
            render = {'frames': len(selected), 'enabled': sorted({r['enabled'] for r in selected})}
            if spec is not None or any('modelProbeVersion' in r for r in selected):
                actual=sorted({r.get('model','missing') for r in selected})
                require(all(r.get('model')==FILLED_MODELS[variant] for r in selected),
                        name+'/'+role+': rendered fill model mismatch; expected '+FILLED_MODELS[variant]+', actual '+','.join(actual))
                if variant!='wooden-wheelbarrow' or any('modelProbeVersion' in r for r in selected):
                    require(all(r.get('modelProbeVersion')==1 and r.get('heldModel') in HELD_MODELS[variant] for r in selected),
                            name+'/'+role+': rendered held model differs from selected full cart')
                render.update(expectedModel=FILLED_MODELS[variant],models=actual,
                              modelDiagnostics=all(r.get('modelProbeVersion')==1 for r in selected))
            if variant == 'wooden-wheelbarrow':
                render.update(wheelFloorRange=[min(wheel(r) for r in selected), max(wheel(r) for r in selected)],
                              palmHandleErrorMax={side: max(palm(r, side) for r in selected) for side in 'LR'},
                              palmHandleErrorMedian={side: statistics.median(palm(r, side) for r in selected) for side in 'LR'})
            else:
                render.update(models=sorted({r['model'] for r in selected}), rawTransformCoverage=True,
                              scope='Actual cart/bone transforms; wooden wheel and handle calibration is not applicable')
            phase[role]['render'] = render
        result['phases'][name] = phase
    stop = {role: coverage(rows, 'wall', epoch, WINDOWS['settled-stop'], role + '/final') for role, rows in states.items()}
    owner = max(stop['client1'], key=lambda r: r['wall'])
    result['finalPositionDeltaFromOwner'] = {role: math.hypot(max(rows, key=lambda r: r['wall'])['x'] - owner['x'], max(rows, key=lambda r: r['wall'])['y'] - owner['y']) for role, rows in stop.items()}
    if extended:
        moving = {}
        for name, flag in (('run', 'run'), ('sprint-turn', 'sprint')):
            rows = coverage(states['client1'], 'wall', epoch, windows[name], name + '/native progress')
            distance = sum(math.hypot(b['x']-a['x'], b['y']-a['y']) for a, b in zip(rows, rows[1:]))
            yaw = sum(math.atan2(math.sin(b['heading']-a['heading']), math.cos(b['heading']-a['heading'])) for a, b in zip(rows, rows[1:]))
            require(sum(r[flag] for r in rows) >= len(rows)/2 and distance > .25, name + ': native gait/movement progress missing')
            require(name != 'sprint-turn' or yaw < -.2, name + ': held left steering progress missing')
            moving[name] = {'distance': distance, 'yaw': yaw}
        settled = coverage(states['client1'], 'wall', epoch, windows['fast-settled'], 'fast final stop')
        require(all(not r['run'] and not r['sprint'] for r in settled)
                and max(math.hypot(r['x']-settled[0]['x'], r['y']-settled[0]['y']) for r in settled) < .1,
                'Fast gait did not settle to a native stop')
        result['fastMotion'] = moving
    if actions:
        result['actions'] = action_coverage(logs, poses, cartid, epoch, 26000 if extended else 15000, variant, profile)
        if hotkey:
            result['actions']['hotkeySetdown'] = hotkey_coverage(logs, cartid, hotkey_key)
        require(spec is None or result['actions']['cargoID'] == spec['cargoID']
                and abs(result['actions']['cargoWeight']-spec['cargoWeight']) < .001, 'Action sequence changed initial motion cargo')
    if injury:
        result['injury']=injury_module['analyze'](profile, selection, result)
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
