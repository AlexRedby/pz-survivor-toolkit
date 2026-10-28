"""One initial public inventory entry followed by the verified menu lifetime bank."""
import argparse
import json
import math
from pathlib import Path
import re
import runpy
import uuid

HERE = Path(__file__).parent
LIFE = runpy.run_path(str(HERE/'analyze-lease-lifetimes.py'))
EQUIP = runpy.run_path(str(HERE/'analyze-inventory-equip.py'))
parse, require, integer, text = (LIFE[name] for name in ('parse', 'require', 'integer', 'text'))
ROLES = LIFE['ROLES']
MARKER = '[CART_LEASE_INVENTORY] '
MAX = LIFE['MAX']


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def endpoint(row, role, owner, cart, cargo, held):
    require(row.get('owner') == owner and type(row.get('owner')) is int
            and row.get('cart') == cart and type(row.get('cart')) is int,
            role+': inventory entry owner/cart changed')
    require(integer(row, 'cargoID', -2147483648, 2147483647) == cargo[0]
            and number(row.get('cargoWeight')) and row['cargoWeight'] == cargo[1],
            role+': inventory entry cargo changed')
    require(row.get('primaryID') == row.get('secondaryID') == (cart if held else -1)
            and type(row.get('primaryID')) is int and type(row.get('secondaryID')) is int
            and row.get('handSameItem') is held, role+': inventory entry hands differ')
    require(row.get('worldAttached') is False and integer(row, 'worldCount', 0, 0) == 0,
            role+': initial inventory cart entered world')
    require(integer(row, 'nativeActions', 0, 0) == 0 and row.get('hasPath') is False,
            role+': inventory entry native queue/path unfinished')
    if role == 'client2':
        require(row.get('inventoryScope') == 'remote-hand-snapshot' and 'inventoryCount' not in row
                and 'luaActions' not in row and row.get('queueScope') == 'remote-native-only',
                'Observer claimed owner inventory or Lua queue authority')
    else:
        require(row.get('inventoryScope') == 'owner-inventory' and integer(row, 'inventoryCount', 1, 1) == 1,
                role+': initial cart missing/duplicated in owner inventory')
        if role == 'server':
            require(row.get('guarded') is True and 'luaActions' not in row
                    and row.get('queueScope') == 'native-server-only',
                    'Server inventory endpoint lacks original callback guard/native scope')
        else:
            require(integer(row, 'luaActions', 0, 0) == 0 and row.get('queueScope') == 'owner-local',
                    'Owner inventory entry Lua queue unfinished')


def analyze(profile, life=None):
    profile = Path(profile)
    selection = parse((profile/'selection.json').read_text())
    require(isinstance(selection, dict) and selection.get('suite') == 'wooden_cart_multiplayer'
            and selection.get('kind') == 'mp' and selection.get('mode') == 'toolkit'
            and selection.get('cases') == ['owner_observer_motion'], 'Wrong inventory entry selection')
    options = selection.get('options')
    require(isinstance(options, dict) and all(options.get(flag) is True for flag in
            ('cart_lease_inventory', 'cart_lease_menu', 'cart_lease_lifetimes', 'cart_lease_control',
             'cart_timeline', 'cart_fast_motion', 'mp_host')),
            'Explicit initial inventory entry and menu lifetime Host bank required')
    require(options.get('cart_variant', 'wooden-wheelbarrow') == 'wooden-wheelbarrow'
            and 'cart_wall_exit' not in options and all(options.get(flag, False) is False for flag in
            ('cart_inventory_equip', 'cart_actions', 'cart_hotkey_setdown', 'cart_action_admission',
             'cart_observer_association', 'cart_time_alignment')),
            'Inventory entry cannot combine independent experiment banks')
    if life is None:
        life = LIFE['analyze'](profile)
    require(isinstance(life, dict) and life.get('evidenceComplete') is True and life.get('menu') is True
            and life.get('completedNativeCycles') == 6 and life.get('phases') == list(LIFE['MENU_PHASES']),
            'Verified later native menu lifetime bank required')
    owner = integer(life, 'ownerID', 0, 32767)
    cart = integer(life, 'cartID', -2147483648, 2147483647)
    cycles = life.get('cycles')
    require(isinstance(cycles, list) and len(cycles) == 6, 'Missing later native cart/cargo cycles')
    cargo = None
    for cycle in cycles:
        # Current lifetime reports keep cargo in the original cycle rows below;
        # do not infer it from an item ID or the native action's nearest timestamp.
        require(isinstance(cycle, dict) and cycle.get('actor') in ROLES, 'Foreign later native cycle')
    logs = {role: (profile/(role+'-launch.log')).read_text() for role in ROLES}
    require(all(len(log) <= 32*1024*1024 for log in logs.values()), 'Inventory entry log limit exceeded')
    rows, held, starts, initial = {}, {}, {}, {}
    for role, log in logs.items():
        values = LIFE['records'](log, MARKER, 8)
        expected = ['unheld', 'held'] if role == 'server' else ['held'] if role == 'client2' else [
            'unheld', 'queued', 'start', 'terminal', 'held']
        require([row.get('event') for _, row in values] == expected,
                role+': missing/duplicate/reordered initial inventory entry stages')
        wall = -1
        for _, row in values:
            require(row.get('actor') == role and integer(row, 'phase', 0, 0) == 0,
                    role+': foreign inventory entry actor/phase')
            require(integer(row, 'owner', 0, 32767) == owner, role+': foreign inventory entry owner')
            now = integer(row, 'wall', 0, MAX)
            require(now >= wall, role+': inventory entry clock regressed'); wall = now
        rows[role] = {row['event']: (line, row) for line, row in values}
        held[role] = rows[role]['held']
        epoch = [(line, re.search(r'\[CART_MP\] START epoch=([0-9]+)', value))
                 for line, value in enumerate(log.splitlines()) if '[CART_MP] START epoch=' in value]
        require(len(epoch) == 1 and epoch[0][1] is not None and held[role][0] < epoch[0][0],
                role+': inventory entry did not precede ordinary motion START')
        if role != 'server':
            armed = [(line, re.search(r'\[CART_MP\] ARMED (\S+)(?:\s|$)', value))
                     for line, value in enumerate(log.splitlines()) if '[CART_MP] ARMED ' in value]
            require(armed and all(match is not None and match.group(1) == role for _, match in armed)
                    and held[role][0] < armed[0][0] < epoch[0][0],
                    role+': inventory held endpoint must precede first exact local ARMED')
        starts[role] = epoch[0][1].group(1)
        ready = LIFE['records'](log, LIFE['MARKER'], 256)
        ready = [(line, row) for line, row in ready if row.get('event') == 'ready']
        require(ready and all(row.get('lifetime') == ready[0][1].get('lifetime') for _, row in ready),
                role+': missing/changed initial ready lifetime')
        initial[role] = LIFE['token'](ready[0][1]['lifetime'])
        process, actor, connection, revision = initial[role]
        native = [(line, row) for line, row in LIFE['records'](log, LIFE['NATIVE'], 8192)
                  if row.get('process') == process and row.get('actorEpoch') == actor]
        baselines = [(line, row) for line, row in native if row.get('event') == 'baseline']
        require(len(baselines) == 1 and native[0] == baselines[0]
                and held[role][0] < baselines[0][0] < ready[0][0],
                role+': native baseline must first be created after actual inventory equip')
        baseline = baselines[0][1]
        require(revision == 1 and baseline.get('ownerID') == owner and baseline.get('connectionEpoch') == connection
                and baseline.get('revision') == baseline.get('hardRevision') == 1
                and baseline.get('primaryEpoch') == baseline.get('secondaryEpoch')
                and integer(baseline, 'primaryEpoch', 1, MAX) > 0
                and baseline.get('primaryID') == baseline.get('secondaryID') == cart
                and baseline.get('success') is True and baseline.get('poisoned') is False and baseline.get('retired') is False
                and all(integer(baseline, key, 0, 0) == 0 for key in
                        ('depth', 'mutationSerial', 'parseSerial', 'ingressGeneration')),
                role+': initial native baseline is not exact fresh held equipment')
        cycle_rows = [row for _, row in LIFE['records'](log, LIFE['MARKER'], 256) if row.get('event') == 'cycle']
        require(len(cycle_rows) == 2, role+': missing later menu release cycles')
        for cycle in cycle_rows:
            value = (integer(cycle, 'cargoID', -2147483648, 2147483647), cycle.get('cargoWeight'))
            require(number(value[1]) and 0 < value[1] <= 100000, 'Invalid later native cargo weight')
            require(cargo is None or value == cargo, 'Later native menu cycles changed inventory entry cargo')
            cargo = value
    require(len(set(starts.values())) == 1, 'Inventory entry roles changed ordinary motion epoch')
    for role in ROLES:
        endpoint(held[role][1], role, owner, cart, cargo, True)
        if role != 'client2': endpoint(rows[role]['unheld'][1], role, owner, cart, cargo, False)
    driver = [rows['client1'][stage][1] for stage in ('queued', 'start', 'terminal')]
    queued, started, terminal = driver
    for row in driver:
        require(row.get('kind') == 'inventory' and row.get('actionType') == row.get('queuedSource') == 'ISCartEquipAction'
                and row.get('cart') == cart and type(row.get('cart')) is int
                and row.get('sourceType') == 'inventory' and integer(row, 'duration', 30, 30) == 30
                and number(row.get('luaMaxTime')),
                'Inventory menu driver changed native source/action/duration')
        if row is not queued:
            integer(row, 'nativeMaxTime', 30, 30)
        for key in ('localActionEpoch', 'localSourceEpoch', 'operation'):
            integer(row, key, 1, MAX)
        integer(row, 'generation', 0, MAX); text(row, 'source', 240)
        require(all(row.get(key) == queued.get(key) for key in
                ('localActionEpoch', 'localSourceEpoch', 'operation', 'source', 'generation')),
                'Inventory menu driver source/action/operation changed')
    require(started['luaMaxTime'] == terminal['luaMaxTime'], 'Inventory started/completed adjusted Lua duration changed')
    require(started.get('sealed') is True and terminal.get('sealed') is True
            and started.get('state') == 'started' and terminal.get('state') == 'completed',
            'Inventory entry lacks sealed start/completed receipt')
    token = text(started, 'token', 36)
    try: canonical = str(uuid.UUID(token)) == token
    except ValueError: canonical = False
    require(canonical, 'Invalid inventory entry acknowledgement UUID')
    transaction = integer(started, 'transaction', -128, 127)
    require(transaction != 0 and integer(started, 'localNativeEpoch', 1, MAX) > 0,
            'Invalid native inventory transaction/action identity')
    require(all(terminal.get(key) == started.get(key) for key in ('token', 'transaction', 'localNativeEpoch')),
            'Inventory completed receipt changed exact native token/transaction')
    integer(terminal, 'transaction', -128, 127); integer(terminal, 'localNativeEpoch', 1, MAX)
    require(('localNativeEpoch' in queued) == ('nativeMaxTime' in queued),
            'Inventory queued native identity/time must be observed together')
    if 'nativeMaxTime' in queued:
        integer(queued, 'nativeMaxTime', 30, 30)
        require(integer(queued, 'localNativeEpoch', 1, MAX) == started['localNativeEpoch'],
                'Inventory queued native action was replaced before start')
    native_path = profile/'client1/inventory-equip-native.jsonl'
    require(native_path.stat().st_size <= 64*1024*1024, 'Inventory native source file limit exceeded')
    native = [parse(line) for line in native_path.read_text().splitlines() if line.strip()]
    require(native and all(isinstance(row, dict) and row.get('producer') == EQUIP['NATIVE']
            and row.get('actor') == 'client1' and number(row.get('wall'))
            and row.get('event') in ('body', 'lifecycle', 'grounding-pair') for row in native),
            'Inventory native file has foreign/malformed producer')
    lifecycle = [row for row in native if row.get('event') == 'lifecycle']
    require(lifecycle and all(row.get('ownerID') == owner and row.get('local') is True for row in lifecycle),
            'Inventory native lifecycle changed exact local owner')
    require(all(row.get('luaMaxTime') == started['luaMaxTime'] for row in lifecycle),
            'Inventory native lifecycle changed adjusted Lua duration')
    for row in lifecycle:
        require(integer(row, 'ownerID', 0, 32767) == owner
                and integer(row, 'id', -2147483648, 2147483647) == cart
                and row.get('method') in ('start', 'update', 'perform', 'complete', 'stop', 'interruptWaitToStart')
                and row.get('stage') in ('enter', 'exit'), 'Malformed inventory native lifecycle boundary')
        if (row['method'], row['stage']) != ('start', 'enter'):
            require(integer(row, 'transactionId', -128, 127) == transaction
                    and integer(row, 'networkOwnerID', 0, 32767) == owner,
                    'Inventory native lifecycle changed exact transaction/owner')
    require([row['wall'] for row in lifecycle] == sorted(row['wall'] for row in lifecycle),
            'Inventory native lifecycle clock regressed')
    native_result = EQUIP['native_lifecycle'](native, dict(id=cart, ownerID=owner), queued['wall'])
    require(native_result['nativeTransactionID'] == transaction
            and native_result['nativeStartWall'] <= started['wall'] <= native_result['nativePerformWall']
            <= terminal['wall'] <= held['client1'][1]['wall'],
            'Inventory driver receipt is not the exact canonical native action')
    return dict(schema=1, diagnosticOnly=True, evidenceComplete=True, inventoryEntry=True,
                ownerID=owner, cartID=cart, cargoID=cargo[0], cargoWeight=cargo[1], nativeActionID=native_result['nativeActionID'],
                nativeTransactionID=transaction, token=token, canonicalServerDoneWall=native_result['canonicalServerDoneWall'],
                ownerMenuActions=1, completedNativeCycles=6, heldEndpointRoles=list(ROLES),
                sourceFiles={role: role+'-launch.log' for role in ROLES},
                nativeSourceFile='client1/inventory-equip-native.jsonl',
                qualification='One initial owner inventory Push Cart entry via ISCartEquipAction with canonical ActionManager Done, followed by the verified world release/pickup lifetime fences. No repeated inventory return, ground Grab path, Toolkit native action-admission classifier coverage, production migration, animation equivalence or wire budget is established.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    print(json.dumps(analyze(parser.parse_args().profile), indent=2))
