"""Strict source-scoped menu-Host equip capture receipts; no animation-equivalence claim."""
import json
import math
from pathlib import Path
import runpy

COMMON = runpy.run_path(str(Path(__file__).with_name('analyze.py')))
parse, require, number = (COMMON[key] for key in ('parse', 'require', 'number'))
PRODUCER = 'cart-mp-inventory-equip-v1'
NATIVE = 'cart-mp-inventory-equip-native-v1'
MARKER = '[CART_MP_INVENTORY_EQUIP] '
VARIANTS = {'female-empty': (True, 'empty'), 'female-full': (True, 'full'),
            'male-empty': (False, 'empty'), 'male-full': (False, 'full')}


def records(text, role):
    rows = [parse(line.split(MARKER, 1)[1]) for line in text.splitlines() if MARKER in line]
    require(rows, role + ': no dedicated inventory-equip receipts')
    for row in rows:
        require(row.get('producer') == PRODUCER and row.get('actor') == role,
                role + ': wrong receipt producer/actor')
        require(number(row.get('wall')), role + ': missing receipt timestamp')
        require(row.get('event') != 'error', role + ': fixture failed')
    return rows


def one(rows, event, role):
    matches = [row for row in rows if row.get('event') == event]
    require(len(matches) == 1, role + ': expected one ' + event)
    return matches[0]


def identity(row, spec, role, held=True):
    require(all(row.get(key) == spec[key] for key in ('id', 'ownerID', 'variant', 'female', 'cartType', 'cargoIDs', 'cargoCount')),
            role + ': wrong authoritative cart/owner/cargo identity')
    require(number(row.get('cargoWeight')) and abs(row['cargoWeight'] - spec['cargoWeight']) < .001,
            role + ': wrong authoritative cargo weight')
    require(row.get('worldAttached') is False and row.get('worldCount') == 0, role + ': cart entered world')
    if role == 'client2':
        require('inventoryCount' not in row and row.get('inventoryScope') == 'remote-hand-snapshot',
                'Observer claimed owner inventory instead of its hand representation')
    else:
        require(row.get('inventoryCount') == 1 and row.get('inventoryScope') == 'owner-inventory',
                role + ': exact cart missing/duplicated in owner inventory')
    if held:
        require(row.get('primaryID') == row.get('secondaryID') == spec['id'] and row.get('handSameItem') is True,
                role + ': missing exact two-hand endpoint')
        require(row.get('nativeActions') == 0 and row.get('hasPath') is False,
                role + ': endpoint queues/path not terminal')
        require(('luaActions' not in row and row.get('queueScope') == 'native-server-only') if role == 'server'
                else row.get('luaActions') == 0, role + ': wrong native/Lua queue scope')
        require(row.get('pantsType') == 'Base.Trousers_JeanBaggy' and row.get('wornCount') == 3
                and row.get('pantsModel') == 'skinned/clothes/' + ('kate' if spec['female'] else 'bob') + '_trousers',
                role + ': wrong native worn outfit/model')


def covered(rows, start, end, role, minimum=5):
    selected = [row for row in rows if start <= row['wall'] <= end]
    times = sorted({row['wall'] for row in selected})
    require(len(times) >= minimum, role + ': insufficient distinct temporal samples')
    require(times[0] <= start + 350 and times[-1] >= end - 350
            and times[-1] - times[0] >= .5 * (end - start), role + ': incomplete phase span')
    require(max((b - a for a, b in zip(times, times[1:])), default=0) <= 350,
            role + ': native phase sampling gap')
    return selected


def native_rows(rows, role, spec):
    require(rows, role + ': missing native lifecycle/body file')
    for row in rows:
        require(row.get('producer') == NATIVE and row.get('actor') == role
                and row.get('ownerID') == spec['ownerID'] and row.get('female') == spec['female']
                and row.get('local') is (role == 'client1') and number(row.get('wall')),
                role + ': wrong native producer/owner/sex/source scope')
        require(row.get('event') in ('body', 'lifecycle', 'grounding-pair'), role + ': unknown native event')
    bodies = [row for row in rows if row['event'] == 'body']
    seen = set()
    trousers = ('kate' if spec['female'] else 'bob') + '_trousers'
    for row in bodies:
        require(type(row.get('captureId')) is int and row['captureId'] > 0 and row['captureId'] not in seen,
                role + ': missing/duplicate native capture ID')
        seen.add(row['captureId'])
        models = row.get('models')
        require(isinstance(models, list) and any(isinstance(model, str)
                and trousers in model.lower().replace('\\', '/') for model in models),
                role + ': native prepared slot lacks actual trousers model')
        bones = row.get('bones', {})
        require(all(name in bones for name in ('Bip01_L_Hand', 'Bip01_R_Hand', 'Bip01_L_Foot', 'Bip01_R_Foot', 'Bip01_Spine')),
                role + ': missing native hand/foot/spine bones')
        require(all(isinstance(matrix, list) and len(matrix) == 16 and all(number(v) for v in matrix)
                    for matrix in bones.values()), role + ': malformed native body matrix')
        require(isinstance(row.get('tracks'), list) and row['tracks']
                and all(isinstance(track.get('name'), str) and number(track.get('time')) and number(track.get('weight'))
                        for track in row['tracks']), role + ': missing native animation tracks')
    return bodies


def native_lifecycle(rows, spec, queued_wall):
    """Require one exact native inventory action through canonical ActionManager Done."""
    lifecycle = [row for row in rows if row.get('event') == 'lifecycle']
    require(lifecycle, 'Owner native lifecycle missing')
    ids = {row.get('actionId') for row in lifecycle}
    require(len(ids) == 1 and all(type(i) is int and i > 0 for i in ids), 'Missing/multiple native action lifecycle IDs')
    action_id = next(iter(ids))
    for row in lifecycle:
        require(row.get('id') == spec['id'] and row.get('actionType') == 'ISCartEquipAction'
                and row.get('sourceType') == 'inventory' and row.get('maxTime') == 30
                and number(row.get('luaMaxTime')) and row.get('luaCharacterExact') is True
                and row.get('threw') is False and row.get('forceStop') is False and row.get('networkRejected') is False,
                'Native lifecycle does not bind exact non-rejected inventory action')
        require(row.get('method') not in ('stop', 'interruptWaitToStart'), 'Native menu equip cancelled')
    began = [row for row in lifecycle if row.get('method') == 'start' and row.get('stage') == 'enter']
    ended = [row for row in lifecycle if row.get('method') == 'perform' and row.get('stage') == 'exit']
    require(len(began) == len(ended) == 1 and began[0]['wall'] >= queued_wall - 100
            and ended[0].get('waitForFinished') is True and ended[0].get('forceComplete') is True
            and ended[0].get('progress') == 1 and number(ended[0].get('time')) and ended[0]['time'] >= 30
            and 200 <= ended[0]['wall'] - began[0]['wall'] <= 4000,
            'Native start/perform/finished boundaries missing')
    registered = [row for row in lifecycle if row.get('method') == 'start' and row.get('stage') == 'exit']
    require(len(registered) == 1 and registered[0].get('waitForFinished') is True
            and registered[0].get('networkActionPresent') is True and registered[0].get('networkActionExact') is True
            and registered[0].get('networkActionType') == 'ISCartEquipAction'
            and registered[0].get('networkOwnerID') == spec['ownerID']
            and type(registered[0].get('transactionId')) is int, 'Native exact MP transaction registration missing')
    transaction = registered[0]['transactionId']
    for row in lifecycle:
        if row.get('method') == 'start' and row.get('stage') == 'enter': continue
        require(row.get('transactionId') == transaction and row.get('networkOwnerID') == spec['ownerID'],
                'Native lifecycle changed exact MP owner/transaction identity')
    canonical = [row for row in lifecycle if row.get('method') == 'update' and row.get('stage') == 'exit'
                 and row.get('networkActionPresent') is True and row.get('networkActionExact') is True
                 and row.get('networkActionType') == 'ISCartEquipAction' and row.get('networkDone') is True
                 and row.get('waitForFinished') is True and row.get('forceComplete') is True
                 and row.get('progress') == 1 and number(row.get('time')) and row['time'] >= 30]
    require(canonical and registered[0]['wall'] < canonical[0]['wall'] <= ended[0]['wall'],
            'Missing exact ActionManager server-done receipt before native perform')
    require(all(row.get('forceComplete') is False for row in lifecycle if row['wall'] < canonical[0]['wall']),
            'Native action forced before canonical server-done receipt')
    progress = [row.get('progress') for row in lifecycle if row.get('method') == 'update']
    require(len(progress) >= 2 and all(number(v) and 0 <= v <= 1 for v in progress)
            and max(progress) - min(progress) >= .3, 'Native action made no measured progress')
    return dict(nativeActionID=action_id, nativeTransactionID=transaction,
                nativeStartWall=began[0]['wall'], nativePerformWall=ended[0]['wall'],
                canonicalServerDoneWall=canonical[0]['wall'])


def analyze_data(logs, native, poses, cameras, variant='female-empty'):
    require(variant in VARIANTS, 'Unknown inventory-equip variant')
    rows = {role: records(logs[role], role) for role in ('server', 'client1', 'client2')}
    spec = one(rows['server'], 'spec', 'server')
    female, load = VARIANTS[variant]
    require(spec.get('variant') == variant and spec.get('female') is female and spec.get('load') == load
            and spec.get('cartType') == 'SaucedWheelbarrow.WheelbarrowWood'
            and type(spec.get('id')) is int and spec['id'] > 0 and type(spec.get('ownerID')) is int and spec['ownerID'] >= 0,
            'Server spec does not bind selected exact variant/cart/owner')
    require(type(spec.get('cargoCount')) is int and spec['cargoCount'] == (0 if load == 'empty' else 1)
            and isinstance(spec.get('cargoIDs'), str) and number(spec.get('cargoWeight'))
            and (load != 'empty' or spec['cargoIDs'] == '' and spec['cargoWeight'] == 0), 'Invalid authoritative load')
    if load == 'full':
        require(':Base.Log:' in spec['cargoIDs'] and spec['cargoWeight'] > 0, 'Missing exact full-load cargo identity')
    start = one(rows['server'], 'start', 'server');epoch = start.get('epoch')
    require(number(epoch), 'Missing authoritative epoch')
    for role in ('client1', 'client2'):
        received = one(rows[role], 'start', role)
        require(received.get('epoch') == epoch and received.get('id') == spec['id'] and received.get('ownerID') == spec['ownerID'],
                role + ': wrong authoritative start identity')
        require(all(row.get('producer') == NATIVE and row.get('actor') == role and number(row.get('wall')) for row in native[role]),
                role + ': malformed/unscoped native source file')
    # Attachment begins before setup reaches the client. Those pre-setup native
    # rows may still show its randomly created sex/outfit and are outside this run.
    native = {role: [row for row in native[role] if number(row.get('wall')) and row['wall'] >= epoch]
              for role in ('client1', 'client2')}
    queued = one(rows['client1'], 'queued', 'client1')
    require(queued.get('id') == spec['id'] and queued.get('ownerID') == spec['ownerID']
            and queued.get('actionType') == 'ISCartEquipAction' and queued.get('sourceType') == 'inventory'
            and queued.get('menuSource') == 'OnFillInventoryObjectContextMenu'
            and queued.get('duration') == queued.get('maxTime') == queued.get('nativeMaxTime') == 30
            and queued.get('maxTimeScope') == 'native-action' and number(queued.get('luaMaxTime'))
            and queued.get('cartId') == spec['id'] and queued.get('characterExact') is True
            and number(queued.get('walkDistance')) and queued['walkDistance'] >= .25
            and epoch + 2000 <= queued['wall'] <= epoch + 4000, 'Missing real inventory menu equip after native Walk')
    owner_check = one(rows['server'], 'owner-check', 'server')
    require(owner_check.get('receivedActor') == 'client1' and owner_check.get('actionType') == 'ISCartEquipAction'
            and owner_check.get('duration') == 30 and type(owner_check.get('nativeFinished')) is bool
            and type(owner_check.get('nativeForceComplete')) is bool and owner_check.get('nativeProgress') == 1
            and owner_check.get('nativeMaxTime') == 30
            and number(owner_check.get('nativeTime')) and owner_check['nativeTime'] >= 30,
            'Server did not receive owner native completion')
    identity(owner_check, spec, 'client1')
    terminal_probe = one(rows['client1'], 'terminal-probe', 'client1')
    identity(terminal_probe, spec, 'client1')
    require(terminal_probe.get('nativeActionPresent') is True
            and number(terminal_probe.get('elapsed')) and terminal_probe['elapsed'] >= 200
            and terminal_probe['wall'] <= owner_check['wall']
            and all(terminal_probe.get(key) == owner_check.get(key) for key in
                    ('nativeFinished', 'nativeForceComplete', 'nativeTime', 'nativeProgress', 'nativeMaxTime')),
            'Owner terminal diagnostic does not match server completion receipt')
    observer = one(rows['server'], 'observer', 'server')
    require(observer.get('receivedActor') == 'client2', 'Server lacks observer receipt')
    identity(observer, spec, 'client2')
    acknowledgement = one(rows['server'], 'ack', 'server');identity(acknowledgement, spec, 'server')
    require(acknowledgement.get('ok') is True and acknowledgement.get('holdMs', 0) >= 200,
            'Missing stable authoritative server ACK')
    tail = owner_check['wall']
    require(queued['wall'] < tail <= acknowledgement['wall'], 'Invalid native equip/tail ordering')
    authoritative = [row for row in rows['server'] if row['event'] == 'sample']
    for row in authoritative:
        identity(row, spec, 'server', held=False)
    covered(authoritative, epoch + 300, epoch + 1700, 'server pre-Walk')
    covered(authoritative, queued['wall'], tail, 'server menu-equip', minimum=3)
    for role in rows:
        complete = one(rows[role], 'complete', role)
        require(complete.get('ok') is True and complete.get('id') == spec['id']
                and complete['wall'] >= acknowledgement['wall'], role + ': incomplete authoritative session')
    lifecycle = native_lifecycle(native['client1'], spec, queued['wall'])
    action_id = lifecycle['nativeActionID'];transaction = lifecycle['nativeTransactionID']
    phase_counts = {}
    for role in ('client1', 'client2'):
        bodies = native_rows(native[role], role, spec)
        received_ack = one(rows[role], 'ack', role)
        require(received_ack.get('id') == spec['id'] and received_ack.get('ownerID') == spec['ownerID']
                and received_ack.get('serverWall') == acknowledgement['wall'] and received_ack.get('holdMs') == acknowledgement['holdMs'],
                role + ': did not consume exact authoritative ACK')
        pairs = [row for row in native[role] if row.get('event') == 'grounding-pair']
        require(len(pairs) >= 3, role + ': missing first-attachment grounding gate pairs')
        for pair in pairs:
            before, after = pair.get('before', {}), pair.get('after', {})
            require(all(before.get(key) == after.get(key) and type(before.get(key)) is int
                        for key in ('slotToken', 'cartDataToken'))
                    and before.get('id') == before.get('primaryID') == before.get('secondaryID')
                    == after.get('id') == after.get('primaryID') == after.get('secondaryID') == spec['id'],
                    role + ': grounding diagnostic changed source slot/cart identity')
            for stage in (before, after):
                gate = stage.get('readiness', {})
                require(all(type(gate.get(key)) is bool for key in ('visualEnabled', 'steeringEnabled', 'supportedHeldCart', 'IsPerformingAnAction', 'ToolkitCartMotion'))
                        and 'PerformingAction' in gate and 'Weapon' in gate, role + ': missing native readiness gates')
                require(isinstance(stage.get('cart'), list) and len(stage['cart']) == 16 and all(number(v) for v in stage['cart'])
                        and isinstance(stage.get('bones'), dict) and 'Bip01_L_Hand' in stage['bones'] and 'Bip01_R_Hand' in stage['bones'],
                        role + ': missing same-slot attachment cart/body matrices')
        pair_times = sorted(pair['wall'] for pair in pairs)
        require(pair_times[0] <= lifecycle['nativePerformWall'] + 800 and pair_times[-1] - pair_times[0] >= 80,
                role + ': first-attachment diagnostic window missing')
        before = covered(bodies, epoch + 300, epoch + 1700, role + ' pre-Walk')
        require(any(row.get('moving') is True for row in before)
                and all(row.get('primaryID') == row.get('secondaryID') == -1 for row in before), role + ': missing bare native pre-Walk')
        during = covered(bodies, lifecycle['nativeStartWall'], lifecycle['nativePerformWall'], role + ' equip', minimum=3)
        if role == 'client1':
            require(any(any(action.get('actionId') == action_id and action.get('id') == spec['id']
                    and action.get('type') == 'ISCartEquipAction' for action in row.get('actions', [])) for row in during),
                    'Native body/equip lifecycle IDs not joined')
        after = covered(bodies, tail + 400, tail + 2000, role + ' settled tail')
        require(all(row.get('primaryID') == row.get('secondaryID') == spec['id'] and row.get('nativeActions') == 0 for row in after),
                role + ': native settled tail lost exact cart/actions')
        samples = [row for row in rows[role] if row['event'] == 'sample' and row.get('phase') == 'settled-tail']
        for row in covered(samples, tail + 400, tail + 2000, role + ' endpoint'):
            identity(row, spec, role)
        bound_poses = [row for row in poses[role] if row.get('id') == spec['ownerID'] and tail + 400 <= row.get('wallTimeMillis', -1) <= tail + 2000]
        require(len(bound_poses) >= 5, role + ': missing actual held-cart/body render poses')
        draws = {(row.get('captureId'), row.get('part')): row for row in cameras[role] if row.get('id') == spec['ownerID']}
        for row in bound_poses:
            COMMON['pose'](row)
            require(row.get('female') is female and row.get('cartItemId') == row.get('primary') == row.get('secondary') == spec['id']
                    and row.get('cartItemSource') == 'hands' and row.get('model') == 'WheelbarrowWood'
                    and row.get('cartModelCount') == 1 and row.get('local') is (role == 'client1'), role + ': wrong native rendered cart/model identity')
            for part in ('body', 'cart'):
                draw = draws.get((row.get('captureId'), part))
                require(draw and draw.get('slotToken') == row.get('slotToken')
                        and draw.get('preparedPrimary') == draw.get('preparedSecondary') == spec['id'], role + ': missing consumed body/cart draw identity')
        final = one(rows[role], 'video-final', role)
        video_start = one(rows[role], 'video-start', role)
        require(final.get('id') == spec['id'] and final.get('state') == 'completed'
                and number(final.get('frames')) and final['frames'] > 0 and number(final.get('seconds')) and final['seconds'] > 0
                and isinstance(final.get('file'), str) and final['file'] == video_start.get('file')
                and video_start['wall'] <= epoch and final['wall'] >= tail + 2000, role + ': video does not span native action and tail')
        phase_counts[role] = dict(preWalk=len(before), equip=len(during), settledTail=len(after), renderedTail=len(bound_poses),
                                 firstAttachmentGroundingPairs=len(pairs))
    return dict(evidenceComplete=True, animationEquivalencePass=False, cartInventoryEquip=True, selectedVariant=variant,
                authoritativeCartID=spec['id'], ownerOnlineID=spec['ownerID'], nativeActionID=action_id,
                nativeClientCompleteRequired=False, nativeClientFinishedFlagRequired=False, nativeTransactionID=transaction,
                canonicalServerDoneWall=lifecycle['canonicalServerDoneWall'], phases=phase_counts, cargo=dict(ids=spec['cargoIDs'], weight=spec['cargoWeight']),
                scope='One selected disposable menu-Host inventory equip, native start/progress/exact ActionManager server-done/perform plus authoritative server and observer endpoints; body matrices, native outfit/model and rendered held-cart tail captured. Visual fit, wheel/feet/grip quality and animation equivalence still require independent review.')


def analyze(profile, selection, common=None):
    profile = Path(profile)
    logs = {}
    for role in ('server', 'client1', 'client2'):
        console = profile / role / 'console.txt'
        path = console if console.is_file() else profile / (role + '-launch.log')
        logs[role] = path.read_text(errors='replace')
        require(not any(marker in logs[role] for marker in ('[QUEUE_TEST] FAIL', '[CLEARANCE_PROBE] ERROR')), role + ': fixture/probe error')
    def load(role, name):
        return [parse(line) for line in (profile / role / name).read_text().splitlines() if line.strip()]
    roles = ('client1', 'client2')
    return analyze_data(logs, {role: load(role, 'inventory-equip-native.jsonl') for role in roles},
                        {role: load(role, 'body-clearance.jsonl') for role in roles},
                        {role: load(role, 'render-camera.jsonl') for role in roles},
                        selection.get('options', {}).get('cart_inventory_equip_variant', 'female-empty'))
