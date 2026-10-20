"""Opt-in Host manual wall-exit evidence; physical and visual claims stay separate."""
import importlib.util
import math
from pathlib import Path
import re
import statistics

DURATION = 29000
SETTLED = (28000, DURATION)
PHASES = [('idle', 0), ('walk', 1000), ('reverse', 9500), ('reverse-turn', 12000),
          ('reverse-stop', 15500), ('forward-turn', 16000), ('forward-out', 21000), ('settled', 26000)]
WINDOWS = {'idle': (100, 800), 'walk': (1500, 9300), 'reverse': (10500, 11800),
           'reverse-turn': (12300, 15300), 'reverse-stop': (15700, 15900),
           'forward-turn': (16300, 20800), 'forward-out': (21300, 25800), 'settled': SETTLED}
FRONT_DURATION = 18000
FRONT_SETTLED = (17300, FRONT_DURATION)
# Keep five native samples despite100..200ms cadence, after release blend and before manual reverse.
FRONT_RELEASE = (6750, 7400)
FRONT_PHASES = [('idle', 0), ('walk', 1000), ('release', 6500), ('reverse', 7500),
                ('reverse-stop', 10000), ('restart', 10800), ('settled', 15500)]
FRONT_WINDOWS = {'idle': (100, 800), 'contact': (5000, 6300), 'release': FRONT_RELEASE,
                 'reverse': (7800, 9800), 'restart': (11100, 12000),
                 'contact-again': (14500, 15300), 'settled': FRONT_SETTLED}
BRACE_TRACK = 'Toolkit_WoodCartBrace'
FEET = tuple(f'Bip01_{side}_{part}' for side in 'LR' for part in ('Foot', 'Toe0'))
PAD_KEYS = ('minX', 'minY', 'z', 'size', 'margin', 'bankVersion', 'elevated', 'vegetationFree',
            'floorSprite', 'wallSprite', 'wallSide', 'wallX', 'wallMinY', 'wallMaxY', 'ownedWalls', 'initialHeading')


def wrap(value):
    return math.atan2(math.sin(value), math.cos(value))


def draw_evidence(profile, role, frames, states, identity, cartid, epoch, duration, settled_window, footprint, common):
    require, parse, number = (common[k] for k in ('require', 'parse', 'number'))
    source = Path(profile)/role/'render-camera.jsonl'
    require(source.is_file(), role + ': missing independent native camera draw proof')
    raw = [parse(line) for line in source.read_text().splitlines()]
    draws = {}
    for row in raw:
        require(isinstance(row, dict) and row.get('renderProbeVersion') == 1
                and all(type(row.get(k)) is int for k in ('captureId', 'slotToken', 'id', 'primary', 'secondary'))
                and row['captureId'] > 0 and row.get('part') in ('body', 'cart'), role + ': malformed native draw identity')
        require(all(number(row.get(k)) for k in ('captureWallTimeMillis', 'cameraWallTimeMillis', 'wallTimeMillis',
                'cameraX', 'cameraY', 'cameraZ', 'cameraAngle', 'currentCameraX', 'currentCameraY', 'currentCameraZ', 'currentCameraAngle',
                'slotX', 'slotY', 'slotZ', 'slotAngle', 'squareDepth', 'depthBias'))
                and type(row.get('cameraWorldIso')) is bool and type(row.get('cameraInVehicle')) is bool,
                role + ': malformed consumed native camera')
        key = (row['captureId'], row['part'])
        require(key not in draws, role + ': duplicate native draw proof')
        draws[key] = row
    result, offsets = [], []
    times = [r['wall'] for r in states]
    unrendered = 0
    for frame in frames:
        at = frame['wallTimeMillis']
        if not epoch <= at <= epoch+duration:
            continue
        require(frame.get('renderProbeVersion') == 1 and all(type(frame.get(k)) is int for k in ('captureId', 'slotToken'))
                and frame['captureId'] > 0 and all(number(frame.get(k)) for k in ('nativeWallTimeMillis', 'nativeX', 'nativeY', 'nativeZ',
                    'nativeHeading', 'nativeRenderAngle', 'squareDepth', 'expectedSquareDepth')),
                role + ': missing original native pose/depth capture')
        pair = [draws.get((frame['captureId'], part)) for part in ('body', 'cart')]
        if all(row is None for row in pair):
            unrendered += 1
            continue
        require(all(row is not None for row in pair), role + ': body/cart draw proof incomplete')
        for row in pair:
            require(row['id'] == identity and row['primary'] == row['secondary'] == cartid
                    and (row['part'] != 'cart' or row.get('model') == 'WheelbarrowWood') and row['slotToken'] == frame['slotToken']
                    and row['captureWallTimeMillis'] == at
                    and frame['nativeWallTimeMillis'] <= at <= row['cameraWallTimeMillis'] <= row['wallTimeMillis'] <= at+1000,
                    role + ': stale/foreign native camera draw proof')
            require(row['cameraWorldIso'] and not row['cameraInVehicle'], role + ': draw did not consume native world camera')
            require(all(abs(row['camera'+axis]-row['currentCamera'+axis]) <= 1e-5
                        and abs(row['camera'+axis]-row['slot'+axis]) <= 1e-4
                        and abs(row['slot'+axis]-frame['slot'+axis]) <= 1e-4 for axis in 'XYZ')
                    and abs(wrap(row['cameraAngle']-row['currentCameraAngle'])) <= 1e-5
                    and abs(wrap(row['cameraAngle']-row['slotAngle'])) <= .002
                    and abs(wrap(row['slotAngle']-frame['slotAngle'])) <= .002,
                    role + ': consumed camera and final slot pose disagree')
            require(abs(row['squareDepth']-frame['squareDepth']) <= 1e-6
                    and abs(frame['squareDepth']-frame['expectedSquareDepth']) <= 1e-6,
                    role + ': final slot depth disagrees with corrected native depth inputs')
        native = dict(frame, wall=frame['nativeWallTimeMillis'], slotX=frame['nativeX'], slotY=frame['nativeY'],
                      slotAngle=frame['nativeHeading']+math.pi/2)
        require(abs(frame['nativeZ']-states[0]['z']) <= .25 and footprint.slot_matches(native, states, times), role + ': original native pose disagrees with actor state')
        dx,dy = frame['slotX']-frame['nativeX'],frame['slotY']-frame['nativeY']
        yaw = wrap(frame['slotAngle']-frame['nativeRenderAngle'])
        distance = math.hypot(dx,dy)
        require(distance <= .7501 and abs(frame['slotZ']-frame['nativeZ']) <= .002,
                role + ': observer cosmetic correction exceeds bounded native pose')
        if role == 'client1':
            require(distance <= .002 and abs(yaw) <= .02, 'Owner received observer cosmetic correction')
        if settled_window[0] <= at-epoch <= settled_window[1]:
            require(distance <= .01 and abs(yaw) <= .02, role + ': observer cosmetic correction remains after settled release')
        result.append(frame)
        offsets.append(dict(wall=at, x=dx, y=dy, yaw=yaw, distance=distance))
    require(result and all(b['wall']>a['wall'] for a,b in zip(offsets, offsets[1:])), role + ': missing/unordered proven draw frames')
    steps = [dict(wall=a['wall'], nextWall=b['wall'], elapsedMs=b['wall']-a['wall'],
                  distance=math.hypot(b['x']-a['x'], b['y']-a['y']), yaw=abs(wrap(b['yaw']-a['yaw']))) for a,b in zip(offsets, offsets[1:])]
    def percentile(values, q):
        return sorted(values)[min(len(values)-1, math.ceil(q*len(values))-1)] if values else 0
    return result, dict(provenFrames=len(result), unrenderedPreparedFrames=unrendered,
        maxCorrection=max(r['distance'] for r in offsets), maxYawCorrection=max(abs(r['yaw']) for r in offsets),
        correctionActiveFrames=sum(r['distance']>.001 or abs(r['yaw'])>.002 for r in offsets),
        maxCorrectionStep=max(steps,key=lambda r:r['distance']) if steps else None,
        maxYawCorrectionStep=max(steps,key=lambda r:r['yaw']) if steps else None,
        correctionStepP95=percentile([r['distance'] for r in steps],.95), yawCorrectionStepP95=percentile([r['yaw'] for r in steps],.95),
        scope='Independent native camera Begin values and actual body/cart DrawSolid proof; correction smoothness deltas are diagnostic, not natural-motion proof')


def front_evidence(states, inputs, poses, measured, cartid, wall_x, epoch, covered, require, number, gait, stopped_pose):
    def pick(rows, key, interval, label, minimum=5):
        return covered(rows, key, interval, label, minimum)
    def flags(row):
        fields = row.get('pose', '').split(',')
        require(len(fields) == 13 and fields[0] == '1' and fields[1] == str(cartid)
                and fields[2].isdigit() and int(fields[2]) > 0 and fields[3].isdigit(),
                'Front brace requires version 1 pose with exactly 13 fields')
        value = int(fields[3])
        require(0 <= value <= 15 and (value & 8 == 0 or value & 7 == 1), 'Invalid front brace flags')
        return value
    def tracks(row):
        values = row.get('trackProgress')
        require(isinstance(values, list) and all(isinstance(t, dict) and isinstance(t.get('name'), str)
                and all(number(t.get(k)) for k in ('time', 'duration', 'weight')) and t['duration'] > 0
                and 0 <= t['time'] <= t['duration'] + .01 and t['weight'] >= 0 for t in values),
                'Missing/malformed native front track progression')
        return values
    payloads = {}
    for role, rows in states.items():
        for row in rows:
            flags(row)
            serial = int(row['pose'].split(',')[2])
            require(serial not in payloads or payloads[serial] == row['pose'], 'Same pose serial changed across roles')
            payloads[serial] = row['pose']
            if role != 'server':
                require(type(row.get('brace')) is bool, role + ': missing actual ToolkitCartBrace boolean')
                tracks(row)
    for row in inputs:
        require(number(row.get('brace')) and 0 <= row['brace'] <= 1
                and type(row.get('nativeBlocked')) is bool and row['nativeBlocked']
                and type(row.get('wantsMove')) is bool, 'Missing/malformed front brace native diagnostics')
    summaries = []
    for role in ('client1', 'client2'):
        baseline = pick(poses[role], 'wallTimeMillis', (200, 800), role + '/standing')
        def feet(frame):
            require(all(name in frame['bones'] for name in FEET), role + ': missing rendered foot/toe bones')
            require(all(all(abs(frame['bones'][name][i] - expected) <= 1e-5 for i, expected in ((3, 0), (7, 0), (11, 0), (15, 1))) for name in FEET),
                    role + ': invalid rendered foot/toe matrix')
            return {name: frame['bones'][name][12:15] for name in FEET}
        standing = {name: [statistics.median(feet(f)[name][axis] for f in baseline) for axis in range(3)] for name in FEET}
        for interval in ((5000, 6300), (14500, 15300)):
            quiet = pick(states[role], 'wall', interval, role + '/front-contact')
            frames = pick(poses[role], 'wallTimeMillis', interval, role + '/front-contact/render')
            require(stopped_pose(quiet, .015), role + ': blocked brace moves root, heading or steps')
            require(all(r['brace'] and flags(r) & 8 for r in quiet), role + ': blocked contact lacks replicated brace')
            require(all(any(t.get('name') == BRACE_TRACK and number(t.get('weight')) and t['weight'] > .5
                            for t in tracks(r)) for r in quiet), role + ': native brace track missing')
            offset = max(abs(feet(f)[name][1] - standing[name][1]) for f in frames for name in FEET)
            jitter = max(math.sqrt(sum((max(feet(f)[name][a] for f in frames) - min(feet(f)[name][a] for f in frames)) ** 2 for a in range(3))) for name in FEET)
            require(offset <= .025 and jitter <= .012, role + ': blocked feet are raised or unplanted')
            summaries.append(dict(role=role, window=list(interval), samples=len(quiet), renderFrames=len(frames), footOffsetFromStanding=offset, footPositionRangeXYZ=jitter))
        for interval in (FRONT_RELEASE, (8000, 9800), FRONT_SETTLED):
            quiet = pick(states[role], 'wall', interval, role + '/brace-release')
            require(all(not r['brace'] and flags(r) & 8 == 0 for r in quiet), role + ': brace remains latched after release/reverse')
            require(all(not any(t.get('name') == BRACE_TRACK and number(t.get('weight')) and t['weight'] > .1
                                for t in tracks(r)) for r in quiet), role + ': brace track remains after release/reverse')
    for interval in (FRONT_RELEASE, (8000, 9800), FRONT_SETTLED):
        arrivals = pick(states['server'], 'wall', interval, 'server/brace-release')
        require(all(flags(r) & 8 == 0 for r in arrivals), 'Server brace flag remains after release/reverse')
    for interval in ((5000, 6300), (14500, 15300)):
        arrivals = pick(states['server'], 'wall', interval, 'server/front-contact')
        require(all(flags(r) & 8 for r in arrivals), 'Server brace flag missing')
        contact = pick(inputs, 'wall', interval, 'owner/front-native-contact')
        # ToolkitCartBrace is the live intended-step collision result; cartBlocked can reset at zero root budget.
        require(all(r['drive'] == 1 and r['wantsMove'] and r['brace'] >= .95 for r in contact), 'Owner lacks sustained blocked forward intent')
        require(any(f['minX'] <= wall_x + .65 for f in measured['client1'] if interval[0] <= f['elapsed'] <= interval[1]), 'Frontal stance never reaches wall contact')
    for interval in (FRONT_RELEASE, FRONT_SETTLED):
        release = pick(inputs, 'wall', interval, 'owner/front-release')
        require(all(r['drive'] == 0 and not r['wantsMove'] and r['brace'] < .05 for r in release), 'Owner release leaves brace intent latched')
    require(all(r['stepY'] >= 0 for r in states['client1'] if r['wall'] < epoch + 7500), 'Automatic reverse occurred before manual front reverse')
    reverse = pick(states['client1'], 'wall', (7800, 9800), 'owner/front-reverse')
    gait(reverse, 'Bob_WalkBwdNoAim1Hand', True)
    require(reverse[-1]['x'] - reverse[0]['x'] > .3, 'Manual reverse fails to leave front wall')
    restart = pick(states['client1'], 'wall', (11100, 12000), 'owner/front-restart')
    gait(restart, 'Bob_Walk')
    require(restart[0]['x'] - restart[-1]['x'] > .1, 'Forward restart fails to return toward wall')
    stop = pick(states['client1'], 'wall', (10300, 10600), 'owner/front-reverse-stop', minimum=2)
    require(stopped_pose(stop, .05), 'Front manual reverse did not stop before restart')
    return dict(verified=True, contact=summaries, payloadVersion=1, payloadFields=13, flagBit=8,
                scope='Actual native brace track and rendered foot/toe stability on both clients; authoritative native wall/forward intent on owner')


def analyze(profile, selection, common):
    require, parse, number = (common[k] for k in ('require', 'parse', 'number'))
    profile = Path(profile)
    options = selection.get('options', {})
    side = options.get('cart_wall_exit')
    require(side in ('left', 'right', 'front') and type(side) is str, 'cart_wall_exit must be left, right or front')
    front = side == 'front'
    duration, settled_window = (FRONT_DURATION, FRONT_SETTLED) if front else (DURATION, SETTLED)
    phases_plan, windows = (FRONT_PHASES, FRONT_WINDOWS) if front else (PHASES, WINDOWS)
    require(options.get('mp_host') is True, 'Wall bank requires native Host')
    require(options.get('cart_variant', 'wooden-wheelbarrow') == 'wooden-wheelbarrow', 'Wall bank requires wooden-wheelbarrow')
    require(all(options.get(k, False) is False for k in ('cart_fast_motion', 'cart_actions', 'cart_hotkey_setdown'))
            and 'cart_hotkey_key' not in options, 'Wall bank is mutually exclusive with fast/action/hotkey banks')
    logs = {role: (profile / (role + '-launch.log')).read_text() for role in common['ROLES']}
    def records(role, marker):
        values = [parse(line.split(marker, 1)[1]) for line in logs[role].splitlines() if marker in line]
        require(all(isinstance(row, dict) for row in values), role + ': malformed ' + marker)
        return values
    def one(role, marker):
        rows = records(role, marker)
        require(len(rows) == 1, role + ': exactly one ' + marker + ' required')
        return rows[0]
    for role, text in logs.items():
        require(not any(s in text for s in ('[QUEUE_TEST] FAIL', '[CLEARANCE_PROBE] ERROR', '[GRIP_POSE_PROBE] ERROR')), role + ': native fixture/probe failure')
    epochs = re.findall(r'\[CART_MP\] START epoch=(\d+)', logs['server'])
    require(len(epochs) == 1, 'Exactly one server scenario epoch required')
    epoch = int(epochs[0])
    require(parse((profile/'execution.json').read_text()).get('status') == 'completed', 'Native runner did not complete')
    sign = 1 if side == 'left' else -1
    pad = one('server', '[CART_MP] CART_PAD ')
    require(all(number(pad.get(k)) for k in ('minX', 'minY', 'wallX', 'wallMinY', 'wallMaxY', 'initialHeading'))
            and pad.get('bankVersion') == 4 and pad.get('size') == 63 and pad.get('margin') == 2
            and pad.get('z') == 7 and pad.get('elevated') is True and pad.get('vegetationFree') is True
            and pad.get('floorSprite') == 'carpentry_02_57' and pad.get('wallSprite') == 'walls_exterior_wooden_01_0'
            and pad.get('wallSide') == side and pad.get('ownedWalls') == 49
            and abs(pad['initialHeading']-(math.pi if front else sign*3*math.pi/4)) < 1e-6
            and pad['wallX'] == pad['minX']+31-3 and pad['wallMinY'] == pad['minY']+31-24
            and pad['wallMaxY'] == pad['minY']+31+24, 'Invalid authoritative native wall/pad geometry')
    for role in ('client1', 'client2'):
        require(re.findall(r'\[CART_MP\] START epoch=(\d+)', logs[role]) == epochs, role + ': mismatched epoch')
        setup = records(role, '[CART_MP] SETUP ')
        require(setup and all(all(row.get(k) == pad[k] for k in PAD_KEYS) for row in setup), role + ': authoritative wall geometry not shared')
        ready = one(role, '[CART_MP] PAD_READY ')
        require(ready.get('floors') == 3969 and ready.get('walls') == 49 and number(ready.get('wall')) and ready['wall'] < epoch
                and all(ready.get(k) == pad[k] for k in PAD_KEYS), role + ': complete replicated native pad/wall not observed')
        events = records(role, '[QUEUE_CHECK] ')
        require([r.get('event') for r in events] == ['setup', 'case', 'complete'], role + ': incomplete capture receipts')
        require(all(r.get('actor') == role and r.get('suite') == 'cart_motion_mp' and r.get('kind') == 'mp'
                    and r.get('mode', 'toolkit') == 'toolkit' for r in events), role + ': receipt identity differs')
        require(events[0].get('cases') == ['owner_observer_motion'] and events[0].get('expected') == 1
                and events[1].get('id') == 'owner_observer_motion' and events[1].get('status') == 'captured'
                and events[1].get('cartActions', False) is False
                and all(type(events[2].get(k)) is int and events[2][k] == v for k,v in {'expected':1,'performed':1,'failed':0,'skipped':0}.items()), role + ': unsuccessful capture receipt')
        phases = re.findall(r'\[CART_MP\] PHASE ([a-z-]+) wall=(\d+) elapsed=(\d+)', logs[role])
        require([p[0] for p in phases] == [p[0] for p in phases_plan], role + ': phase sequence differs')
        require(all(t <= int(p[2]) <= t+600 and int(p[1])-epoch == int(p[2]) for p,(_,t) in zip(phases, phases_plan)), role + ': phase timing differs')
    armed = records('server', '[CART_MP_WALL] ARMED ')
    require(len(armed) == 2 and {r.get('actor') for r in armed} == {'client1', 'client2'}
            and all(r.get('floors') == 3969 and r.get('walls') == 49 and r.get('bankVersion') == 4
                    and number(r.get('wall')) and r['wall'] < epoch for r in armed), 'Missing authoritative pre-epoch wall acknowledgements')
    cleanup = one('server', '[CART_MP_WALL] CLEANUP ')
    require(cleanup.get('walls') == 49 and number(cleanup.get('wall')) and epoch+duration <= cleanup['wall'] <= epoch+duration+5000,
            'Missing bounded server wall cleanup')
    for role in ('client1', 'client2'):
        row = one(role, '[CART_MP_WALL] CLEANUP_READY ')
        require(row.get('walls') == 0 and number(row.get('wall')) and cleanup['wall'] <= row['wall'] <= cleanup['wall']+5000,
                role + ': replicated wall cleanup not confirmed')
    raw = {role: [common['state'](r) for r in records(role, '[CART_MP_STATE] ')] for role in common['ROLES']}
    identities = {r['id'] for r in raw['client1'] if r['user'] == 'client1'}
    require(len(identities) == 1 and next(iter(identities)) >= 0, 'Unique owner onlineID required')
    identity = next(iter(identities))
    states = {}
    def covered(rows, key, window, label, minimum=5):
        a,b = (epoch+t for t in window)
        selected = [r for r in rows if a <= r[key] <= b]
        require(len(selected) >= minimum, label + ': insufficient samples')
        require(all(number(r.get(key)) for r in selected), label + ': invalid sample time')
        times = [r[key] for r in selected]
        require(all(0 < y-x <= 500 for x,y in zip(times,times[1:])), label + ': unordered samples or gap exceeds 500ms')
        edge=min(350,(b-a)/(2 if minimum==2 else 3))
        require(times[0] <= a+edge and times[-1] >= b-edge, label + ': missing window edges')
        return selected
    spec = one('server', '[CART_MP] CART_SPEC ')
    cartid = spec.get('id')
    require(type(cartid) is int and cartid >= 0 and spec.get('variant') == 'wooden-wheelbarrow'
            and spec.get('cartType') == common['VARIANTS']['wooden-wheelbarrow'] and spec.get('cargoCount') == 1
            and spec.get('cargoType') == 'Base.Log' and type(spec.get('cargoID')) is int and spec['cargoID'] >= 0 and spec['cargoID'] != cartid
            and number(spec.get('cargoWeight')) and spec['cargoWeight'] > 0 and number(spec.get('capacity'))
            and abs(spec['capacity']-spec['cargoWeight']) < .001, 'Authoritative full native Log cargo descriptor differs')
    sexes = set()
    for role, rows in raw.items():
        require(all(r['user'] == 'client1' for r in rows if r['id'] == identity)
                and all(r['id'] == identity for r in rows if r['user'] == 'client1'), role + ': owner identity changed')
        states[role] = covered([r for r in rows if r['id'] == identity], 'wall', (0,duration), role+'/active')
        for r in states[role]:
            require(r['primary'] == r['secondary'] == cartid and r['item'] == spec['cartType']
                    and r.get('cargoCount') == 1 and r.get('cargoID') == spec['cargoID']
                    and number(r.get('cargoWeight')) and abs(r['cargoWeight']-spec['cargoWeight']) < .001
                    and r.get('worldID') == -1 and type(r.get('inventoryCount')) is int
                    and (r.get('inventoryCount') == 1 if role != 'client2' else r.get('inventoryScope') == 'remote-hand-snapshot'), role + ': cart/cargo/ownership changed during active window')
            require(r.get('hasPath') is False and r.get('characterActions') == 0 and r.get('performing') is False,
                    role + ': native action/path interfered')
            require(type(r.get('female')) is bool and r['local'] is (role == 'client1'), role + ': sex/local identity missing')
            require(not r['run'] and not r['sprint'], role + ': walk-only wall bank changed gait')
            require(pad['minX']+2 <= r['x'] <= pad['minX']+61 and pad['minY']+2 <= r['y'] <= pad['minY']+61 and abs(r['z']-7)<.25,
                    role + ': owner left validated pad')
            sexes.add(r['female'])
            if role == 'client1': require(r['enabled'], 'Owner patch disabled')
    require(len(sexes) == 1, 'Owner sex changed across roles/window')
    initial=covered(states['client1'],'wall',(0,800),'owner/initial')
    require(all(abs(r['x']-(pad['wallX']+(1.8 if front else 2.8)))<.05 and abs(r['y']-(pad['minY']+31.5))<.05
                and abs(wrap(r['heading']-pad['initialHeading']))<.04 for r in initial), 'Owner initial wall pose differs')
    inputs = records('client1', '[CART_MP_WALL] INPUT ')
    inputs = covered(inputs, 'wall', (0,duration), 'owner/manual-input')
    for r in inputs:
        require(number(r.get('elapsed')) and r['elapsed'] == r['wall']-epoch and number(r.get('acceptedHeading'))
                and type(r.get('drive')) is int and r.get('gait') == 0 and r.get('id') == cartid
                and r.get('primary') == r.get('secondary') == cartid and r.get('inventoryCount') == 1 and r.get('worldID') == -1
                and r.get('cargoID') == spec['cargoID'] and number(r.get('cargoWeight')) and abs(r['cargoWeight']-spec['cargoWeight']) < .001
                and r.get('queue') == r.get('actions') == 0 and r.get('path') is False
                and r.get('front') == 1.26 and all(type(r.get(k)) is bool for k in ('blocked','recovering','clear')),
                'Malformed manual input/footprint/identity evidence')
        native=min(states['client1'],key=lambda s:abs(s['wall']-r['wall']))
        require(abs(wrap(native['heading']-r['acceptedHeading']))<=.08+3*abs(native['wall']-r['wall'])/1000, 'Manual accepted heading disagrees with owner native state')
    turns=[]
    drives=[0,1,0,4,0,1,0] if front else [0,1,4,6 if sign==1 else 7,0,5 if sign==1 else 8,5 if sign==1 else 8,0]
    for i, ((name,start),(_,end)) in enumerate(zip(phases_plan, phases_plan[1:]+[('end',duration)])):
        rows=[r for r in inputs if start+min(100,(end-start)/4) <= r['elapsed'] < end-min(100,(end-start)/4)]
        require(rows and all(r.get('stage') == name for r in rows), name + ': missing/wrong input stage')
        if front or i not in (3,5,6):
            require(all(r['drive'] == drives[i] for r in rows), name + ': unexpected physical drive (automatic reverse or steering)')
            continue
        straight=4 if i==3 else 1
        commands=[r['drive'] for r in rows]
        require(drives[i] in commands and straight in commands, name + ': steering never pressed/released')
        release=commands.index(straight)
        require(all(d==drives[i] for d in commands[:release]) and all(d==straight for d in commands[release:]), name + ': steering did not release once')
        target=sign*(3*math.pi/4 if i==3 else math.pi/4 if i==5 else 0)
        direction=sign*(1 if i==3 else -1)
        yaw=[wrap(b['acceptedHeading']-a['acceptedHeading'])*direction for a,b in zip(rows,rows[1:])]
        released=rows[release:]
        require(sum(yaw)>math.radians(15) and sum(-v for v in yaw if v<0)<=.02, name + ': reverse/wrong/oscillating accepted yaw')
        require(all(abs(wrap(r['acceptedHeading']-target))<=.04 for r in released), name + ': release missed accepted target')
        require(max(abs(wrap(r['acceptedHeading']-released[0]['acceptedHeading'])) for r in released)<=.025, name + ': heading drifts after steering release')
        turns.append(dict(stage=name,target=target,acceptedYaw=sum(yaw)))
    poses={role: [common['pose'](parse(line)) for line in (profile/role/'body-clearance.jsonl').read_text().splitlines()] for role in ('client1','client2')}
    module=importlib.util.spec_from_file_location('cart_mp_wall_footprint', Path(__file__).parent.parent/'wooden_cart_motion/analyze-footprint.py')
    footprint=importlib.util.module_from_spec(module);module.loader.exec_module(footprint)
    measured={}; meshsha={}; render_proof={}
    for role, rows in poses.items():
        poses[role],render_proof[role]=draw_evidence(profile,role,rows,states[role],identity,cartid,epoch,duration,settled_window,footprint,common)
        rows=poses[role]
        frames=covered(rows, 'wallTimeMillis', (0,duration), role+'/render')
        require(not (profile/role/'wood-wheel-mesh-error.json').exists(), role+': native mesh probe failed')
        vertices,sha=footprint.mesh(profile/role);meshsha[role]=sha
        later=profile/role/'wood-wheel-mesh-phase-proof.json'
        if later.exists():
            proof=parse(later.read_text())
            require(proof.get('proofAfterPhaseChanged') is True and proof.get('matchesInitial') is True and proof.get('initialSha256') == proof.get('sha256') == sha, role+': native GPU mesh changed after wheel phase')
        measured[role]=[]
        for f in frames:
            require(f['id']==identity and f['primary']==f['secondary']==cartid and f['local'] is (role=='client1') and f['female'] in sexes
                    and f.get('model')=='WheelbarrowWood' and all(number(f.get(k)) for k in ('slotX','slotY','slotZ','slotAngle')),
                    role + ': raw render identity/model/slot changed')
            if role=='client1':require(f['enabled'], 'Owner render patch disabled')
            bounds=footprint.world_bounds(f,vertices)
            require(pad['minX']+2 <= bounds['minX'] and bounds['maxX'] <= pad['minX']+61
                    and pad['minY']+2 <= bounds['minY'] and bounds['maxY'] <= pad['minY']+61, role + ': sampled full mesh left pad')
            raw_bounds=footprint.world_bounds(dict(f,slotX=f['nativeX'],slotY=f['nativeY'],slotZ=f['nativeZ'],slotAngle=f['nativeRenderAngle']),vertices)
            measured[role].append(dict(bounds,rawMinX=raw_bounds['minX'],rawMinY=raw_bounds['minY'],rawMaxY=raw_bounds['maxY'],wall=f['wallTimeMillis'],elapsed=f['wallTimeMillis']-epoch))
        require(all(f['minY']>=pad['wallMinY'] and f['maxY']<=pad['wallMaxY']+1 for f in measured[role]), role + ': cart escaped around finite wall end')
        require(all(f['minX']>=pad['wallX']-.005 for f in measured[role]
                    if f['maxY']>=pad['wallMinY'] and f['minY']<=pad['wallMaxY']+1), role + ': wooden mesh/wheel enters native W wall')
    require(len(set(meshsha.values()))==1, 'Client native mesh differs')
    def window(a,b):return covered(states['client1'],'wall',(a,b),'owner/motion')
    def travel(rows):return sum(math.dist((a['x'],a['y']),(b['x'],b['y'])) for a,b in zip(rows,rows[1:]))
    def gait(rows,name,backward=False):
        pattern=re.compile(r'(?:^|;)'+re.escape(name)+r'=([-+\d.eE]+)@([-+\d.eE]+)(?:;|$)')
        active=[r for r in rows if (m:=pattern.search(r['tracks'])) and float(m[1])>0 and float(m[2])>.1 and r['stepY']*(-1 if backward else 1)>.01]
        require(len(active)>=2 and active[0]['wall']<=rows[0]['wall']+500 and active[-1]['wall']>=rows[-1]['wall']-500
                and all(b['wall']-a['wall']<=500 for a,b in zip(active,active[1:])) and travel(rows)>.1,
                'Native '+name+' gait/movement missing')
        clips=[]
        for r in active:
            entries=r.get('trackProgress')
            require(isinstance(entries,list) and all(isinstance(c,dict) and isinstance(c.get('name'),str) and all(number(c.get(k)) for k in ('time','duration','weight')) and c['duration']>0 and 0<=c['time']<=c['duration']+.01 and c['weight']>=0 for c in entries), 'Missing/malformed native track progression')
            clips.extend((r['wall'],c) for c in entries if c['name']==name and c['weight']>.1)
        require(any(t1>t0 and abs(b['time']-a['time'])>.001 for (t0,a),(t1,b) in zip(clips,clips[1:])), 'Native '+name+' animation time never advances')
    def stopped_pose(rows,distance):
        yaw=[wrap(r['heading']-rows[0]['heading']) for r in rows]
        return (travel(rows)<distance and max(yaw)-min(yaw)<=.025
                and all(abs(r['stepX'])<.01 and abs(r['stepY'])<.01 for r in rows))
    brace_evidence = None
    if front:
        brace_evidence = front_evidence(states, inputs, poses, measured, cartid, pad['wallX'], epoch, covered, require, number, gait, stopped_pose)
        settled=window(*settled_window)
    else:
        contact=window(8000,9300)
        require(sign*(contact[-1]['y']-contact[0]['y'])>.15 and max(r['x'] for r in contact)-min(r['x'] for r in contact)<.15
                and any(r['blocked'] for r in inputs if 8000<=r['elapsed']<=9300)
                and any(f['minX']<=pad['wallX']+.65 for f in measured['client1'] if 8000<=f['elapsed']<=9300), 'Accepted wall contact/slide not demonstrated')
        require(all(r['stepY']>=0 for r in states['client1'] if r['wall']<epoch+9500), 'Automatic reverse occurred before explicit reverse input')
        gait(contact,'Bob_Walk')
        for a,b in ((10500,11800),(12300,15300)):
            reverse=window(a,b);gait(reverse,'Bob_WalkBwdNoAim1Hand',True)
            backward=-sum((b['x']-a['x'])*math.cos(a['heading'])+(b['y']-a['y'])*math.sin(a['heading']) for a,b in zip(reverse,reverse[1:]))
            require(backward>.1, 'Reverse stage has no measured backward travel')
        arc=window(12000,15300)
        require(arc[-1]['x']-arc[0]['x']>.15, 'Manual reverse arc creates no outward clearance')
        stopped=covered(states['client1'],'wall',(15700,15900),'reverse stop',minimum=2)
        require(stopped_pose(stopped,.05), 'Manual reverse did not stop before forward input')
        out=window(23000,25800);gait(out,'Bob_Walk')
        require(out[-1]['x']-out[0]['x']>.3 and all(r['stepY']>0 for r in out), 'Final forward departure missing')
        clear=[f for f in measured['client1'] if 24500<=f['elapsed']<=25800]
        require(clear and min(f['minX'] for f in clear)>=pad['wallX']+.35, 'Full mesh/wheel never clears wall')
        settled=window(*settled_window)
        require(stopped_pose(settled,.1), 'Final release did not settle')
    final_delta={}
    for role in common['ROLES']:
        quiet=covered(states[role],'wall',settled_window,role+'/final settle')
        require(stopped_pose(quiet,.1) and all(not r['run'] and not r['sprint'] for r in quiet), role+': final native position did not settle')
        final_delta[role]=math.dist((quiet[-1]['x'],quiet[-1]['y']),(settled[-1]['x'],settled[-1]['y']))
    phases={}
    for name,interval in windows.items():
        if name=='reverse-stop':continue # 500 ms stop is checked from input; 200 ms cannot contain five 100 ms state samples.
        phases[name]={}
        for role in ('client1','client2'):
            rows=covered(states[role],'wall',interval,role+'/'+name)
            frames=covered(poses[role],'wallTimeMillis',interval,role+'/'+name+'/render')
            phases[name][role]=dict(samples=len(rows),renderFrames=len(frames),bankMaxDegrees=max(abs(math.degrees(r['bank'])) for r in rows),
                wheelFloorRange=[min(common['wheel'](r) for r in frames),max(common['wheel'](r) for r in frames)],
                palmHandleErrorMax={s:max(common['palm'](r,s) for r in frames) for s in 'LR'},
                palmHandleErrorMedian={s:statistics.median(common['palm'](r,s) for r in frames) for s in 'LR'})
    # first-seen serial times are sampled observations, with explicit uncertainty, not synchronized send timestamps.
    serials={}
    for role in common['ROLES']:
        serials[role]={};previous=0
        for r in states[role]:
            fields=str(r.get('pose','')).split(',')
            require(len(fields)==13 and fields[0]=='1' and fields[1]==str(cartid) and fields[2].isdigit(), role+': missing/malformed ToolkitCartPose')
            serial=int(fields[2]);require(serial>=previous and serial>0, role+': pose serial regressed');previous=serial
            require(all(number(float(v)) for v in fields[3:]), role+': invalid pose payload')
            serials[role].setdefault(serial,r['wall'])
    source=Path(__file__).resolve().parents[4]/'JavaPatches/src/net/alexredby/pztoolkitjavapatches/CartMotionSync.java'
    match=re.search(r'CHANGE_NANOS\s*=\s*([\d_]+)L',source.read_text())
    require(match is not None, 'Missing sender CHANGE_NANOS budget')
    interval=int(match[1].replace('_',''))/1_000_000
    require(interval>0,'Invalid sender budget')
    state_gap={role:max(b['wall']-a['wall'] for a,b in zip(rows,rows[1:])) for role,rows in states.items()}
    firstseen=sorted(serials['client1'].items())
    require(all((b[0]-a[0])*interval<=b[1]-a[1]+state_gap['client1'] for a,b in zip(firstseen,firstseen[1:])), 'Pose serial rate exceeds sender budget plus sampling uncertainty')
    lags={}
    for role in ('server','client2'):
        values=[t-serials['client1'][s] for s,t in serials[role].items() if s in serials['client1']]
        require(len(values)>=5, role+': insufficient matched pose serial arrivals')
        lags[role]=dict(matchedSerials=len(values),firstSeenDelayMsRange=[min(values),max(values)],firstSeenDelayMsMedian=statistics.median(values),samplingUncertaintyMs=dict(owner=state_gap['client1'],remote=state_gap[role]),arrivalDelayBoundsMs=[min(values)-state_gap[role],max(values)+state_gap['client1']])
    traffic={}
    for role in common['ROLES']:
        rawtraffic=records(role,'[CART_MP_TRAFFIC] ')
        allrows=[]
        for row in rawtraffic:
            if not allrows or row!=allrows[-1]:allrows.append(row)
        require(all(number(r.get('wall')) and all(type(r.get(k)) is int and r[k]>=0 for k in ('packets','serializedBytes')) for r in allrows), role+': invalid traffic counter')
        require(all(b['wall']>a['wall'] and b['packets']>=a['packets'] and b['serializedBytes']>=a['serializedBytes'] for a,b in zip(allrows,allrows[1:])), role+': traffic counter reset/regression')
        rows=[r for r in allrows if epoch<=r['wall']<=epoch+duration]
        require(len(rows)>=2 and rows[0]['wall']<=epoch+1500 and rows[-1]['wall']>=epoch+duration-1500, role+': traffic window incomplete')
        a,b=rows[0],rows[-1];packets=b['packets']-a['packets'];bytecount=b['serializedBytes']-a['serializedBytes']
        require((packets==0) == (bytecount==0), role+': packet/serialized-byte counters disagree')
        if role=='client1':require(packets>0, 'Owner emitted no measured pose traffic')
        if role=='client1':require(packets<=math.floor((b['wall']-a['wall'])/interval)+1, 'Owner pose packets exceed CHANGE_NANOS sender budget')
        traffic[role]=dict(fromWall=a['wall'],toWall=b['wall'],packets=packets,serializedBytes=bytecount,identicalSnapshotsCoalesced=len(rawtraffic)-len(allrows))
    delayed=[]
    delay=lags['client2']['firstSeenDelayMsMedian']
    owner_frame_gap=max(b['wallTimeMillis']-a['wallTimeMillis'] for a,b in zip(poses['client1'],poses['client1'][1:]))
    for remote in poses['client2']:
        if not epoch+1000<=remote['wallTimeMillis']<=epoch+duration-1000:continue
        local=min(poses['client1'],key=lambda r:abs(r['wallTimeMillis']-(remote['wallTimeMillis']-delay)))
        if abs(local['wallTimeMillis']-(remote['wallTimeMillis']-delay))>owner_frame_gap:continue
        rs=min(states['client2'],key=lambda r:abs(r['wall']-remote['wallTimeMillis']))
        ls=min(states['client1'],key=lambda r:abs(r['wall']-local['wallTimeMillis']))
        delayed.append(dict(bank=abs(rs['bank']-ls['bank']),wheel=abs(common['wheel'](remote)-common['wheel'](local)),
                            **{s:abs(common['palm'](remote,s)-common['palm'](local,s)) for s in 'LR'}))
    require(len(delayed)>=5, 'Delayed render diagnostics lack matched owner frames')
    raw_observer_penetrations=sum(f['rawMinX']<pad['wallX']-.005 and f['rawMaxY']>=pad['wallMinY'] and f['rawMinY']<=pad['wallMaxY']+1 for f in measured['client2'])
    correction_active=render_proof['client2']['correctionActiveFrames']
    result = dict(evidenceComplete=True,ownerOnlineID=identity,cartID=cartid,epoch=epoch,cartVariant='wooden-wheelbarrow',
        actualSex='female' if next(iter(sexes)) else 'male',wallSide=side,checkedPad=pad,cargo=spec,phases=phases,manualTurns=turns,
        sampledOwnerFootprint=dict(sampledPass=True,tolerance=.005,meshSha256=meshsha['client1'],minClearance=min(f['minX']-pad['wallX'] for f in measured['client1'])),
        observerFootprint=dict(sampledPass=True,tolerance=.005,minClearance=min(f['minX']-pad['wallX'] for f in measured['client2']),
            rawMinClearance=min(f['rawMinX']-pad['wallX'] for f in measured['client2']),rawPenetratingFrames=raw_observer_penetrations,
            correctionActiveFrames=correction_active,
            counterexampleCoverage='raw-penetration-corrected' if raw_observer_penetrations and correction_active else 'clear-with-correction' if correction_active else 'clear-without-correction',
            scope='Independent camera/slot-proven remote rendered mesh; raw placement is a counterfactual using original native slot pose and the captured mesh, not authoritative physical collision'),
        renderProof=render_proof,
        poseReplication=lags,finalPositionDeltaFromOwner=final_delta,traffic=dict(roles=traffic,senderIntervalMs=interval,scope='ToolkitCartPose/ToolkitCartActionPose serialized VariableSyncPacket counters; setup excluded; not UDP or total network traffic'),
        delayedRenderDiagnostics=dict(pairs=len(delayed),measuredDelayMs=delay,maxDifference={k:max(r[k] for r in delayed) for k in delayed[0]},scope='Descriptive sampled delay alignment; no animation equivalence threshold'),
        scope='Bounded full-load Walk-first Host manual reverse exit, actual reported sex only. Sampled native mesh plus continuous wheel support against finite W wall; between-frame collision and visual animation equivalence remain unsupported. Native gait time progression is checked independently of descriptive remote render diagnostics.')

    if front:
        result.update(brace=brace_evidence, scope='Bounded full-load frontal Host brace, release, manual reverse and restart with owner/observer planted-foot and native-track gates. Both-role sampled native mesh/wheel wall clearance is required; no whole-animation or between-frame collision equivalence is asserted.')
    return result
