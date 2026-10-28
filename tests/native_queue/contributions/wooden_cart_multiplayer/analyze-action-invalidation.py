"""Exact accepted-action invalidation and fresh-action evidence; no gameplay authority."""
import argparse
import json
import math
from pathlib import Path
import runpy

HERE = Path(__file__).parent
ADMISSION = runpy.run_path(str(HERE/'analyze-action-admission.py'))
parse, require, integer, text, marked, native, identity_equal = (
    ADMISSION[key] for key in ('parse', 'require', 'integer', 'text', 'marked', 'native', 'identity_equal'))
MAX = ADMISSION['MAX']
ROLES = ADMISSION['ROLES']
IDENTITY = ADMISSION['IDENTITY']
BOOLEANS = ADMISSION['BOOLEANS']
MARKER = '[CART_ACTION_INVALIDATION] '
NATIVE = ADMISSION['NATIVE_MARKER']
KINDS = {1: 'ToolkitWoodCartSetdown', 2: 'ToolkitWoodCartPickup', 3: 'ToolkitWoodCartPickup'}


def records(log, marker):
    rows = [(line, parse(value.split(marker, 1)[1])) for line, value in enumerate(log.splitlines()) if marker in value]
    require(len(rows) <= 128 and all(isinstance(row, dict) for _, row in rows),
            'Malformed or excessive action invalidation records')
    return rows


def number(row, key):
    value = row.get(key)
    require(type(value) in (int, float) and math.isfinite(value), 'Invalid invalidation '+key)
    return value


def endpoint(row, role, owner, cart, cargo, held):
    require(row['owner'] == owner and row['cart'] == cart, 'Endpoint owner/cart changed')
    require(integer(row, 'cargoID', -2147483648, 2147483647) == cargo[0]
            and number(row, 'cargoWeight') == cargo[1], 'Endpoint cart cargo changed')
    for key in ('primaryID', 'secondaryID'):
        require(integer(row, key, -2147483648, 2147483647) == (cart if held else -1), 'Endpoint hands differ')
    require(row.get('handSameItem') is held and row.get('worldAttached') is (not held)
            and integer(row, 'worldCount', 0, 1) == (0 if held else 1), 'Endpoint world/hand identity differs')
    require(integer(row, 'nativeActions', 0, 0) == 0 and row.get('hasPath') is False,
            'Endpoint native queue/path unfinished')
    require(row.get('state') == ('held' if held else 'ground'), 'Endpoint cart state differs')
    if role == 'client2':
        require(row.get('inventoryScope') == 'remote-hand-snapshot'
                and row.get('queueScope') == 'remote-native-only'
                and 'inventoryCount' not in row and 'luaActions' not in row,
                'Observer claimed owner inventory or Lua queue authority')
    else:
        require(row.get('inventoryScope') == 'owner-inventory'
                and integer(row, 'inventoryCount', 0, 1) == (1 if held else 0), 'Owner inventory endpoint differs')
        if role == 'server':
            require(row.get('guarded') is True and row.get('queueScope') == 'native-server-only' and 'luaActions' not in row,
                    'Server claimed owner-local Lua queue authority')
        else:
            require(row.get('queueScope') == 'owner-local' and integer(row, 'luaActions', 0, 0) == 0,
                    'Owner Lua queue unfinished')


def snapshot(row, observed):
    require(row.get('guarded') is True, 'Native snapshot lacks exact original callback guard')
    native(row)
    identity_equal(observed, row, IDENTITY+BOOLEANS+('token', 'stage', 'reason', 'nativeState'),
                   'Fixture native snapshot differs from exact native lifetime')
    require(row['monoNs'] >= observed['monoNs'], 'Fixture snapshot predates native observation')


def lifetimes(rows, owner, cart):
    """Consume every native start event; retirement cannot create a new lifetime."""
    groups = {}
    for position, row in rows:
        event = row.get('event')
        require(event in ('pending', 'accepted', 'retired'), 'Unknown native invalidation admission event')
        native(row, 'terminal' if event == 'retired' else event)
        require(row['owner'] == owner and row['cart'] == cart,
                'Native invalidation admission differs from exact owner/cart')
        group = groups.setdefault((row['process'], row['startGeneration']), {})
        require(event not in group, 'Duplicate native invalidation lifecycle event')
        group[event], group[event+'Position'] = row, position
    require(len(groups) == 3, 'Exactly three native action lifetimes required')
    tokens = set()
    for group in groups.values():
        require(all(event in group for event in ('pending', 'accepted', 'retired')),
                'Incomplete native invalidation pending/accepted/retired lifecycle')
        pending, accepted, retired = (group[event] for event in ('pending', 'accepted', 'retired'))
        require(group['pendingPosition'] < group['acceptedPosition'] < group['retiredPosition'],
                'Native invalidation lifecycle reordered')
        require(pending['monoNs'] <= accepted['monoNs'] <= retired['monoNs'],
                'Native invalidation monotonic time regressed')
        identity_equal(pending, accepted, IDENTITY, 'Native pending/accepted identity changed')
        identity_equal(accepted, retired, IDENTITY+('token',), 'Native retirement changed admitted identity')
        require(not pending['tokenObserved'] or pending['token'] == accepted['token'],
                'Native pending token differs from accepted identity')
        require(accepted['token'] not in tokens, 'Native invalidation token reused')
        tokens.add(accepted['token'])
    require(len({key[0] for key in groups}) == 1, 'Native invalidation process changed')
    require(len({tuple(group['accepted'][key] for key in
                ('sourceSession', 'owner', 'actorEpoch', 'connectionEpoch', 'itemEpoch'))
                for group in groups.values()}) == 1,
            'Native invalidation owner/source/item incarnation changed')
    for key in ('actionEpoch', 'tableEpoch'):
        require(len({group['accepted'][key] for group in groups.values()}) == 3,
                'Native invalidation reused '+key)
    return {group['accepted']['token']: group for group in groups.values()}


def analyze(profile):
    profile = Path(profile)
    selection = parse((profile/'selection.json').read_text())
    require(isinstance(selection, dict) and selection.get('suite') == 'wooden_cart_multiplayer'
            and selection.get('kind') == 'mp' and selection.get('mode') == 'toolkit'
            and selection.get('cases') == ['owner_observer_motion'], 'Wrong action invalidation selection')
    options = selection.get('options')
    require(isinstance(options, dict) and all(options.get(key) is True for key in
            ('cart_action_invalidation', 'mp_host', 'cart_timeline', 'cart_fast_motion')),
            'Explicit isolated action invalidation Host selection required')
    require(options.get('cart_variant', 'wooden-wheelbarrow') == 'wooden-wheelbarrow'
            and 'cart_wall_exit' not in options and all(options.get(key, False) is False for key in
            ('cart_actions', 'cart_action_admission', 'cart_lease_control', 'cart_lease_lifetimes',
             'cart_lease_menu', 'cart_lease_inventory', 'cart_inventory_equip', 'cart_time_alignment',
             'cart_hotkey_setdown', 'cart_observer_association')),
            'Action invalidation cannot combine independent experiment banks')
    logs = {role: (profile/(role+'-launch.log')).read_text() for role in ROLES}
    require(all(len(log) <= 32*1024*1024 for log in logs.values()), 'Action invalidation log limit exceeded')
    specs = records(logs['server'], '[CART_MP] CART_SPEC ')
    require(len(specs) == 1, 'One authoritative cart descriptor required')
    spec = specs[0][1]
    cart = integer(spec, 'id', -2147483648, 2147483647)
    require(spec.get('variant') == 'wooden-wheelbarrow'
            and spec.get('cartType') == 'SaucedWheelbarrow.WheelbarrowWood'
            and integer(spec, 'cargoCount', 1, 1) == 1, 'Wrong authoritative cart variant/cargo count')
    cargo = integer(spec, 'cargoID', -2147483648, 2147483647), number(spec, 'cargoWeight')
    require(0 < cargo[1] <= 100000, 'Invalid authoritative cargo weight')
    canonical = marked(logs['client1'], '[CART_MP_STATE] ')
    require(all(isinstance(row, dict) for row in canonical), 'Malformed canonical owner states')
    owners = {integer(row, 'id', 0, 32767) for row in canonical if row.get('user') == 'client1'}
    require(len(owners) == 1, 'Unique canonical owner required')
    owner = next(iter(owners))
    require(all(row.get('user') == 'client1' for row in canonical if row.get('id') == owner), 'Canonical owner ID reused')
    require(not records(logs['client1'], NATIVE) and not records(logs['client2'], NATIVE),
            'Native admission evidence came from a foreign endpoint')
    native_groups = lifetimes(records(logs['server'], NATIVE), owner, cart)
    rows, indexes, epochs = {}, {}, {}
    endpoints = {'init': (0, True), 'ground': (1, False), 'invalid-ground': (2, False),
                 'recovered': (3, True), 'complete': (3, True)}
    role_events = {
        'server': set(endpoints) | {'accepted', 'mutation', 'retired', 'fresh-accepted'},
        'client1': set(endpoints) | {'menu-queued', 'menu-start', 'menu-terminal', 'native-terminal',
                                   'invalidated', 'stale-terminal-refused'},
        'client2': set(endpoints),
    }
    for role in ROLES:
        rows[role] = records(logs[role], MARKER)
        require(rows[role], role+': missing action invalidation records')
        epoch = [line.split('[CART_MP] START epoch=', 1)[1] for line in logs[role].splitlines()
                 if '[CART_MP] START epoch=' in line]
        require(len(epoch) == 1 and epoch[0].isascii() and epoch[0].isdigit(), 'Unique native scenario epoch required')
        epochs[role] = int(epoch[0])
        index = indexes[role] = {}
        previous = -1
        for line, row in rows[role]:
            event = row.get('event')
            require(row.get('actor') == role and event in role_events[role], role+': foreign/unknown invalidation actor/event')
            require(integer(row, 'owner', 0, 32767) == owner
                    and integer(row, 'cart', -2147483648, 2147483647) == cart, role+': invalidation owner/cart changed')
            now = integer(row, 'wall', 0, MAX)
            require(now >= previous and now >= epochs[role]+26000, role+': invalidation precedes motion or local clock regressed')
            previous = now
            phase = integer(row, 'phase', 0, 3)
            duplicate = integer(row, 'duplicate', 1, 2) if event == 'stale-terminal-refused' else 0
            key = event, phase, duplicate
            require(key not in index, role+': duplicate invalidation event')
            index[key] = line, row
        for event, (phase, held) in endpoints.items():
            key = event, phase, 0
            require(key in index, role+': missing exact '+event+' endpoint')
            endpoint(index[key][1], role, owner, cart, cargo, held)
        expected = {(event, phase, 0) for event, (phase, _) in endpoints.items()}
        if role == 'server':
            expected |= {(event, phase, 0) for event, phase in
                         (('accepted', 2), ('mutation', 2), ('retired', 2), ('fresh-accepted', 3))}
        elif role == 'client1':
            expected |= {(event, phase, 0) for phase in (1, 2, 3) for event in ('menu-queued', 'menu-start')}
            expected |= {('menu-terminal', phase, 0) for phase in (1, 3)}
            expected |= {('native-terminal', 2, 0), ('invalidated', 2, 0)}
            expected |= {('stale-terminal-refused', 3, duplicate) for duplicate in (1, 2)}
        require(set(index) == expected, role+': missing/extra invalidation stage')
        require([index[(event, phase, 0)][0] for event, (phase, _) in endpoints.items()]
                == sorted(index[(event, phase, 0)][0] for event, (phase, _) in endpoints.items()),
                role+': invalidation endpoints reordered')
    require(len(set(epochs.values())) == 1, 'Native motion epochs differ')

    def get(role, event, phase, duplicate=0):
        return indexes[role][event, phase, duplicate]

    active = [row for row in canonical if row.get('user') == 'client1'
              and epochs['client1'] <= integer(row, 'wall', 0, MAX) <= epochs['client1']+26000]
    require(active and all(integer(row, 'primary', -2147483648, 2147483647) == cart
                           and integer(row, 'secondary', -2147483648, 2147483647) == cart for row in active),
            'Invalidation cart differs from canonical motion held cart')
    associated, results = set(), []
    for phase in (1, 2, 3):
        queued_line, queued = get('client1', 'menu-queued', phase)
        started_line, started = get('client1', 'menu-start', phase)
        require(queued_line < started_line, 'Owner menu start precedes enqueue')
        expected_kind = 'release' if phase == 1 else 'pickup'
        require(started.get('sealed') is True and started.get('state') == 'started', 'Real sealed owner start required')
        ADMISSION['uuid_text'](started, 'token')
        ADMISSION['transaction'](started)
        integer(started, 'localNativeEpoch', 1, MAX)
        for row in (queued, started):
            require(row.get('kind') == expected_kind and row.get('actionType') == KINDS[phase],
                    'Menu phase native source/action differs')
            require(row.get('queuedSource') in ((KINDS[phase], 'ISWalkToTimedActionF') if phase > 1 else (KINDS[phase],)),
                    'Unexpected actual queued menu source')
            for key in ('localActionEpoch', 'localSourceEpoch', 'operation'):
                integer(row, key, 1, MAX)
            integer(row, 'generation', 0, MAX); text(row, 'source', 240)
        driver_identity = ('kind', 'actionType', 'queuedSource', 'localActionEpoch', 'localSourceEpoch',
                           'operation', 'generation', 'source')
        identity_equal(queued, started, driver_identity, 'Owner menu source/action/operation changed')
        if 'localNativeEpoch' in queued:
            integer(queued, 'localNativeEpoch', 1, MAX)
            identity_equal(queued, started, ('localNativeEpoch',), 'Owner queued native identity changed')
        require(started['token'] in native_groups and started['token'] not in associated,
                'Owner receipt lacks unique exact native admission')
        associated.add(started['token'])
        group = native_groups[started['token']]
        accepted, retired = group['accepted'], group['retired']
        require(accepted['kind'] == KINDS[phase] and accepted['transaction'] == started['transaction'],
                'Owner receipt differs from exact native action/transaction')
        if phase != 2:
            terminal_line, terminal = get('client1', 'menu-terminal', phase)
            identity_equal(started, terminal, driver_identity+('localNativeEpoch', 'token', 'transaction'),
                           'Owner completed menu receipt identity changed')
            require(terminal_line > started_line and terminal.get('sealed') is True and terminal.get('state') == 'completed',
                    'Real sealed owner completed receipt required')
            require(retired['reason'] == 'completed' and retired['nativeState'] == 'Done',
                    'Successful menu action lacks direct native Done')
            require(terminal_line < get('client1', 'ground' if phase == 1 else 'recovered', phase)[0],
                    'Owner endpoint preceded real menu completion')
        else:
            require(retired['reason'] == 'item-invalid' and retired['nativeState'] == 'Accept'
                    and retired['nativeBindingValid'] is False,
                    'Invalidated accepted action completed or retained its item binding')
        results.append(dict(phase=phase, token=started['token'], kind=accepted['kind'], transaction=accepted['transaction'],
                            startGeneration=accepted['startGeneration'], nativeTerminalState=retired['nativeState'],
                            nativeRetirementReason=retired['reason'],
                            ownerSealedOutcome='completed' if phase != 2 else None))
    require(associated == set(native_groups), 'Unassociated extra native action lifetime')
    starts = [get('client1', 'menu-start', phase)[1] for phase in (1, 2, 3)]
    for key in ('localActionEpoch', 'localNativeEpoch', 'operation'):
        require(len({row[key] for row in starts}) == 3, 'Owner fresh action reused '+key)
    for key in ('source', 'localSourceEpoch'):
        require(len({row[key] for row in starts}) == 1, 'Owner menu transport source changed')
    old, fresh = (native_groups[row['token']] for row in starts[1:])
    require(old['accepted']['worldEpoch'] != fresh['accepted']['worldEpoch'], 'Fresh pickup reused invalidated world object')
    ordered = [native_groups[row['token']] for row in starts]
    require(ordered[0]['retiredPosition'] < old['pendingPosition'] < old['retiredPosition'] < fresh['pendingPosition'],
            'Native action phases overlap or reorder')
    accepted_line, accepted = get('server', 'accepted', 2)
    mutation_line, mutation = get('server', 'mutation', 2)
    retired_line, retired = get('server', 'retired', 2)
    fresh_line, fresh_row = get('server', 'fresh-accepted', 3)
    snapshot(accepted, old['accepted']); snapshot(retired, old['retired']); snapshot(fresh_row, fresh['accepted'])
    require(old['acceptedPosition'] < accepted_line < mutation_line < old['retiredPosition'] <= retired_line
            < get('server', 'invalid-ground', 2)[0] < fresh['pendingPosition'] < fresh['acceptedPosition'] < fresh_line
            < fresh['retiredPosition'] < get('server', 'recovered', 3)[0], 'Native world invalidation barrier reordered')
    require(get('server', 'init', 0)[0] < ordered[0]['pendingPosition']
            and ordered[0]['retiredPosition'] < get('server', 'ground', 1)[0] < old['pendingPosition'],
            'Native initial release/ground barrier reordered')
    require(retired.get('currentAuthority') is False, 'Retired admission claimed current authority')
    require(mutation.get('worldReplaced') is True and mutation.get('oldWorldRemoved') is True
            and integer(mutation, 'oldWorldEpoch', 1, MAX) == old['accepted']['worldEpoch'],
            'Mutation did not remove exact accepted world object')
    require(integer(mutation, 'cargoID', -2147483648, 2147483647) == cargo[0]
            and number(mutation, 'cargoWeight') == cargo[1], 'World replacement changed cargo')
    before = number(mutation, 'oldX'), number(mutation, 'oldY')
    after = number(mutation, 'newX'), number(mutation, 'newY')
    require(before != after and all(abs(value) <= 1000000 for value in before+after), 'World replacement did not move the cart')
    terminal_line, terminal = get('client1', 'native-terminal', 2)
    invalidated_line, invalidated = get('client1', 'invalidated', 2)
    old_start, fresh_start = starts[1:]
    require(integer(terminal, 'protocol', 1, 1) == 1 and integer(terminal, 'player', 0, 32767) == owner
            and terminal.get('state') == 'canceled' and terminal.get('guarded') is True
            and terminal.get('sealed') is False and terminal.get('currentAuthority') is False,
            'Invalidation lacks genuine guarded negative owner terminal receipt')
    for row in (terminal, invalidated):
        identity_equal(old_start, row, ('token', 'transaction'), 'Invalidated owner receipt identity changed')
        require(row.get('kind') == KINDS[2], 'Invalidated owner receipt action kind changed')
    require(invalidated.get('observation') in ('unavailable', 'canceled', 'rejected')
            and invalidated.get('currentAuthority') is False and invalidated.get('captureUnavailable') is True
            and invalidated.get('stateUnavailable') is True, 'Invalidated action retained owner receipt authority')
    require(get('client1', 'menu-start', 2)[0] < terminal_line < get('client1', 'invalid-ground', 2)[0]
            < invalidated_line < get('client1', 'menu-queued', 3)[0],
            'Owner invalidation/absence/fresh-action barrier reordered')
    results[1]['ownerNativeReceiptOutcome'] = terminal['state']
    replay_lines = []
    for duplicate in (1, 2):
        line, replay = get('client1', 'stale-terminal-refused', 3, duplicate)
        replay_lines.append(line)
        identity_equal(fresh_start, replay, ('token', 'transaction'), 'Historical replay changed fresh receipt identity')
        require(replay.get('kind') == KINDS[3] and replay.get('oldToken') == old_start['token']
                and type(replay.get('oldTransaction')) is int and replay['oldTransaction'] == old_start['transaction'],
                'Historical replay lacks exact retired owner receipt')
        require(all(replay.get(key) is True for key in ('guarded', 'sealed', 'currentAuthority', 'queueUnchanged',
                                                       'oldCaptureUnavailable', 'oldStateUnavailable'))
                and replay.get('oldObservation') in ('unavailable', 'canceled', 'rejected'),
                'Historical terminal replay restored old authority or disturbed fresh action')
        require(get('client1', 'menu-start', 3)[0] < line < get('client1', 'menu-terminal', 3)[0],
                'Historical terminal replay did not occur during exact fresh action')
    require(replay_lines[0] < replay_lines[1], 'Historical terminal duplicate order differs')
    owner_order = [('init', 0), ('menu-queued', 1), ('menu-start', 1), ('menu-terminal', 1), ('ground', 1),
                   ('menu-queued', 2), ('menu-start', 2), ('native-terminal', 2), ('invalid-ground', 2),
                   ('invalidated', 2), ('menu-queued', 3), ('menu-start', 3)]
    positions = [get('client1', event, phase)[0] for event, phase in owner_order]+replay_lines+[
        get('client1', event, 3)[0] for event in ('menu-terminal', 'recovered', 'complete')]
    require(all(left < right for left, right in zip(positions, positions[1:])), 'Owner action/barrier stages reordered')
    for role in ROLES:
        require(get(role, 'recovered', 3)[0] < get(role, 'complete', 3)[0], role+': missing final recovered completion barrier')
    return dict(schema=1, diagnosticOnly=True, evidenceComplete=True, ownerID=owner, cartID=cart,
        cargoID=cargo[0], cargoWeight=cargo[1], nativeLifetimes=3, exactOwnerAssociations=3,
        invalidatedAcceptedActions=1, historicalTerminalReplaysRefused=2, completedNativeActions=2,
        phases=results, sourceFiles={role: role+'-launch.log' for role in ROLES},
        qualification='One accepted pickup lost its exact world object and was explicitly stopped, then a distinct fresh pickup completed. Native retirement, genuine historical owner terminal receipt and current sealed authority are separate facts. Historical replay cannot restore the old seal or alter the current receipt. Observer evidence is limited to remote hand/native queue snapshots. No spontaneous native Reject, pre-admission rejection, byte transaction wrap, observer proxy binding, production migration or runtime PASS is established.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(analyze(args.profile), indent=2))


if __name__ == '__main__':
    main()
