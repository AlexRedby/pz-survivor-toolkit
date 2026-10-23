"""Exact native admission/owner receipt joins; no observer action or gameplay authority."""
import re
import argparse
import json
from pathlib import Path
import runpy
import uuid

HELPERS = runpy.run_path(str(Path(__file__).with_name('analyze-lease.py')))
parse, require, integer, text, marked = (HELPERS[key] for key in ('parse', 'require', 'integer', 'text', 'marked'))
MAX = 9007199254740991
ROLES = ('server', 'client1', 'client2')
PHASES = ('drop-complete', 'pickup-complete', 'drop-cancel', 'drop-repeat', 'pickup-cancel', 'pickup-repeat')
IDENTITY = ('process', 'sourceSession', 'owner', 'actorEpoch', 'connectionEpoch', 'startGeneration',
            'actionEpoch', 'tableEpoch', 'transaction', 'kind', 'cart', 'itemEpoch', 'worldEpoch',
            'ingressGeneration', 'parseGeneration', 'packetType')
POSITIVE = ('actorEpoch', 'connectionEpoch', 'startGeneration', 'actionEpoch', 'tableEpoch', 'itemEpoch',
            'ingressGeneration', 'parseGeneration')
BOOLEANS = ('nativeBindingValid', 'admittedBindingValid', 'accepted', 'sourceValidated', 'tokenObserved')
OWNER_IDENTITY = ('ownerProcess', 'owner', 'index', 'phase', 'cart', 'localActionEpoch')
OWNER_RECEIPT = ('localNativeEpoch', 'token', 'transaction', 'kind', 'captureGeneration')
NATIVE_MARKER = '[CART_ADMISSION] '
OWNER_MARKER = '[CART_ADMISSION_OWNER] '
QUERY_MARKER = '[CART_ADMISSION_QUERY] '


def uuid_text(row, field):
    value = text(row, field, 36)
    try:
        valid = str(uuid.UUID(value)) == value
    except (ValueError, AttributeError):
        valid = False
    require(valid, 'Invalid admission UUID '+field)
    return value


def transaction(row):
    value = integer(row, 'transaction', -128, 127)
    require(value != 0, 'Zero native transaction is not an action identity')
    return value


def phase(row):
    index = integer(row, 'index', 1, 6)
    require(row.get('phase') == PHASES[index-1], 'Explicit action phase differs')
    return index


def identity_equal(left, right, fields, reason):
    require(all(left.get(field) == right.get(field) and type(left.get(field)) is type(right.get(field))
                for field in fields), reason)


def native(row, stage=None):
    require(isinstance(row, dict), 'Native admission row is not an object')
    require(type(row.get('protocol')) is int and row['protocol'] == 1, 'Unknown native admission protocol')
    uuid_text(row, 'process')
    session = text(row, 'sourceSession', 160).split(':')
    require(len(session) == 3 and session[0] == row['process'] and session[1] == str(row.get('connectionEpoch'))
            and session[2].isascii() and session[2].isdigit() and 0 <= int(session[2]) <= 18446744073709551615,
            'Native source session does not bind exact process/connection/GUID')
    integer(row, 'owner', 0, 32767)
    for field in POSITIVE:
        integer(row, field, 1, MAX)
    integer(row, 'worldEpoch', 0, MAX)
    integer(row, 'packetType', 1, 65535)
    integer(row, 'cart', -2147483648, 2147483647)
    transaction(row)
    require(row.get('kind') in ('ToolkitWoodCartPickup', 'ToolkitWoodCartSetdown', 'ToolkitWoodCartDrop'), 'Unsupported native action kind')
    if row['kind'] == 'ToolkitWoodCartPickup':
        integer(row, 'worldEpoch', 1, MAX)
    else:
        require(row['worldEpoch'] == 0, 'Native held action unexpectedly bound a world item')
    require(all(type(row.get(field)) is bool for field in BOOLEANS), 'Native admission guards must be actual booleans')
    require(row['sourceValidated'] is True, 'Native action source was not validated')
    require(row.get('stage') in ('pending', 'accepted', 'terminal') and (stage is None or row['stage'] == stage), 'Native admission stage differs')
    text(row, 'reason', 160)
    require(row.get('nativeState') in ('Create', 'Request', 'Accept', 'Done', 'Reject', 'unavailable'), 'Unknown native transaction state')
    if row['stage'] == 'pending':
        require(row['reason'] == 'native-request-start' and row['nativeState'] == 'Request', 'Pending native start state/reason differs')
    elif row['stage'] == 'accepted':
        require(row['reason'] == 'native-accepted', 'Accepted native admission reason differs')
    else:
        require(row['reason'] in ('completed', 'rejected', 'native-remove', 'native-absent', 'disconnect',
                'actor-invalid', 'item-invalid', 'native-restart', 'native-state-changed'), 'Unsupported admitted native retirement reason')
        if row['reason'] in ('completed', 'rejected'):
            require(row['nativeState'] == ('Done' if row['reason'] == 'completed' else 'Reject'), 'Native retirement outcome contradicts native state')
    integer(row, 'monoNs', -(1 << 63), (1 << 63)-1)
    integer(row, 'wallMs', 0, MAX)
    if row['tokenObserved']:
        uuid_text(row, 'token')
    else:
        require(row.get('token') is None, 'Unobserved token claims an identity')
    if row['stage'] == 'pending':
        require(not row['accepted'] and not row['admittedBindingValid'], 'Pending start claims native acceptance')
        require(row['nativeBindingValid'], 'Pending native item binding is invalid')
    else:
        require(row['accepted'] and row['admittedBindingValid'] and row['tokenObserved'], 'Native admission lacks frozen accepted binding/token proof')
        if row['stage'] == 'accepted':
            require(row['nativeBindingValid'] and row['nativeState'] == 'Accept', 'Active native admission is not current/accepted')
    return row


def analyze(root):
    root = Path(root)
    selection = parse((root/'selection.json').read_text())
    require(isinstance(selection, dict) and selection.get('suite') == 'wooden_cart_multiplayer'
            and selection.get('kind') == 'mp' and selection.get('mode') == 'toolkit'
            and selection.get('cases') == ['owner_observer_motion'], 'Frozen selection does not match native action admission')
    options = selection.get('options')
    require(isinstance(options, dict) and options.get('cart_action_admission') is True
            and options.get('cart_actions') is True and options.get('mp_host') is True,
            'Explicit menu Host native action admission bank required')
    require('cart_wall_exit' not in options and options.get('cart_inventory_equip', False) is False
            and options.get('cart_lease_control', False) is False,
            'Native action admission is separate from held/inventory/wall experiments')
    logs = {role: (root/(role+'-launch.log')).read_text() for role in ROLES}
    native_rows = {role: marked(log, NATIVE_MARKER) for role, log in logs.items()}
    owner_rows = {role: marked(log, OWNER_MARKER) for role, log in logs.items()}
    query_rows = {role: marked(log, QUERY_MARKER) for role, log in logs.items()}
    require(not native_rows['client1'] and not native_rows['client2'] and not owner_rows['server']
            and not owner_rows['client2'] and not query_rows['client1'] and not query_rows['client2'],
            'Admission evidence came from a foreign endpoint')
    require(native_rows['server'] and owner_rows['client1'] and query_rows['server'], 'Missing native admission/owner/query evidence')
    for rows in (*native_rows.values(), *owner_rows.values(), *query_rows.values()):
        require(all(isinstance(row, dict) and row.get('event') != 'error' for row in rows), 'Action admission probe error or malformed row')

    baseline = marked(logs['client1'], '[CART_MP_STATE] ')
    require(baseline and all(isinstance(row, dict) for row in baseline), 'Missing canonical native owner states')
    current_owners = {integer(row, 'id', 0, 32767) for row in baseline if row.get('user') == 'client1'}
    require(len(current_owners) == 1, 'Canonical native owner ID changed')
    owner_id = next(iter(current_owners))
    require(all(row.get('user') == 'client1' for row in baseline if row.get('id') == owner_id), 'Canonical native owner ID reused')
    begins = marked(logs['client1'], '[CART_MP_ACTION] BEGIN ')
    require(len(begins) == 6 and all(isinstance(row, dict) for row in begins)
            and [phase(row) for row in begins] == list(range(1, 7)),
            'Canonical native six-phase action bank missing/reordered')
    carts = {integer(row, 'id', -2147483648, 2147483647) for row in begins}
    require(len(carts) == 1, 'Canonical action bank cart changed')
    cart_id = next(iter(carts))
    require(all(row.get('actor') == 'client1' and type(row.get('cancel')) is bool
                and row['cancel'] is (row['index'] in (3, 5)) for row in begins), 'Canonical action phase owner/cancel request differs')

    # Native object/start revisions establish identity. Neither byte transaction IDs
    # nor the closest action/presentation timestamp can select a lifecycle.
    lifetimes = {}
    for position, row in enumerate(native_rows['server']):
        event = row.get('event')
        require(event in ('pending', 'accepted', 'retired'), 'Unknown native admission event')
        native(row, 'terminal' if event == 'retired' else event)
        require(row['owner'] == owner_id and row['cart'] == cart_id, 'Native admission differs from canonical owner/cart')
        key = row['process'], row['startGeneration']
        group = lifetimes.setdefault(key, {})
        require(event not in group, 'Duplicate native action lifecycle event')
        group[event] = row
        group[event+'Position'] = position
    require(len(lifetimes) == 6, 'Exactly six native start lifetimes required')
    tokens = {}
    for key, group in lifetimes.items():
        require(all(event in group for event in ('pending', 'accepted', 'retired')), 'Incomplete native pending/accepted/retired lifecycle')
        pending, accepted, retired = (group[event] for event in ('pending', 'accepted', 'retired'))
        require(group['pendingPosition'] < group['acceptedPosition'] < group['retiredPosition'], 'Native admission lifecycle reordered')
        require(pending['monoNs'] <= accepted['monoNs'] <= retired['monoNs'], 'Native admission monotonic time regressed')
        identity_equal(pending, accepted, IDENTITY, 'Native pending/accepted object identity changed')
        identity_equal(accepted, retired, IDENTITY+('token',), 'Native retirement changed admitted identity')
        if pending['tokenObserved']:
            require(pending['token'] == accepted['token'], 'Pending start token differs from admitted token')
        require(accepted['token'] not in tokens, 'Ack token reused across native starts')
        tokens[accepted['token']] = group
    require(len({key[0] for key in lifetimes}) == 1, 'Native process changed during selected bank')
    require(len({tuple(group['accepted'][field] for field in ('sourceSession', 'owner', 'actorEpoch', 'connectionEpoch'))
                 for group in lifetimes.values()}) == 1, 'Native owner/source incarnation changed during bank')

    owners, observed_processes = {}, set()
    for position, row in enumerate(owner_rows['client1']):
        require(row.get('actor') == 'client1', 'Foreign owner admission actor')
        event = row.get('event')
        require(event in ('track', 'capture', 'query', 'reply', 'terminal', 'native-terminal-receipt', 'seal-revoked'), 'Unknown owner admission event')
        index = phase(row)
        observed_processes.add(uuid_text(row, 'ownerProcess'))
        integer(row, 'owner', 0, 32767)
        integer(row, 'cart', -2147483648, 2147483647)
        integer(row, 'localActionEpoch', 1, MAX)
        integer(row, 'wallMs', 0, MAX)
        group = owners.setdefault(index, {})
        require(event not in group, 'Duplicate explicit owner action stage')
        group[event], group[event+'Position'] = row, position
        if event != 'track':
            integer(row, 'localNativeEpoch', 1, MAX)
            integer(row, 'captureGeneration', 0, MAX)
            uuid_text(row, 'token')
            transaction(row)
            require(row.get('kind') in ('ToolkitWoodCartPickup', 'ToolkitWoodCartSetdown', 'ToolkitWoodCartDrop'), 'Unknown sealed owner action kind')
        if event in ('capture', 'reply', 'terminal'):
            require(row.get('sealed') is True, 'Missing actual sealed owner receipt proof')
        if event in ('native-terminal-receipt', 'seal-revoked'):
            require(row.get('sealed') is False and row.get('currentAuthority') is False,
                    'Historical receipt or revoked seal claims current sealed authority')
        if event == 'native-terminal-receipt':
            require(row.get('guarded') is True and row.get('state') in ('completed', 'canceled', 'rejected'),
                    'Native terminal receipt lacks exact ingress guard/outcome')
        if event == 'seal-revoked':
            require(row.get('reason') == 'operation-generation-changed'
                    and integer(row, 'observedGeneration', 0, MAX) > row['captureGeneration'],
                    'Seal revocation lacks exact operation generation change proof: '+str(row.get('reason')))
        if event in ('query', 'reply'):
            require(row.get('guarded') is True, 'Missing actual fresh owner query/ingress guard')
            nonce=text(row,'nonce',120); suffix=':action:'+str(index)
            require(nonce.endswith(suffix),'Owner request nonce is not exact phase challenge')
            challenge=nonce[:-len(suffix)]
            require(challenge!=row['ownerProcess'] and re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}',challenge) is not None, 'Fresh action challenge namespace missing')
        if event == 'capture':
            require(row.get('state') == 'started', 'Owner captured an action after its start rights expired')
        if event == 'terminal':
            require(row.get('state') in ('completed', 'canceled', 'rejected'), 'Unknown sealed owner terminal outcome')
    require(set(owners) == set(range(1, 7)) and len(observed_processes) == 1, 'Missing six owner phases or owner process changed')
    require(all(all(event in group for event in ('track', 'capture', 'query', 'reply', 'native-terminal-receipt'))
                for group in owners.values()), 'Incomplete explicit owner action chain')
    require([row['index'] for row in owner_rows['client1'] if row['event'] == 'track'] == list(range(1, 7)), 'Explicit owner tracking reordered')
    require(next(iter(observed_processes)) != next(iter(lifetimes))[0], 'Owner and server reused native process epoch')
    require(len({group['track']['localActionEpoch'] for group in owners.values()}) == 6, 'Local action epoch reused across selected phases')

    queries = {}
    for row in query_rows['server']:
        require(row.get('actor') == 'server' and row.get('event') == 'query' and row.get('guarded') is True,
                'Server query lacks exact fresh command source guard')
        native(row)
        require(row['stage'] in ('accepted', 'terminal'), 'Server query exposed a pending transaction')
        phase(row)
        nonce = text(row, 'nonce', 120)
        require(nonce not in queries, 'Duplicate server action query')
        queries[nonce] = row
    require(len(queries) == 6, 'Exactly six fresh server query replies required')

    used, results = set(), []
    for index, group in sorted(owners.items()):
        require(all(event in group for event in ('track', 'capture', 'query', 'reply', 'native-terminal-receipt')), 'Incomplete explicit owner action chain')
        track, capture, query, reply, receipt = (group[event] for event in ('track', 'capture', 'query', 'reply', 'native-terminal-receipt'))
        expected_terminal = 'seal-revoked' if index in (3, 5) else 'terminal'
        other_terminal = 'terminal' if index in (3, 5) else 'seal-revoked'
        require(expected_terminal in group and other_terminal not in group, 'Selected owner phase lacks expected sealed outcome/revocation proof')
        terminal = group[expected_terminal]
        if expected_terminal == 'seal-revoked':
            require(group['replyPosition'] < group['seal-revokedPosition'], 'Sealed reply occurred after owner authority was revoked')
        require(group['trackPosition'] < group['capturePosition'] < group['queryPosition'] < group['replyPosition']
                and group['queryPosition'] < group['native-terminal-receiptPosition']
                and group['queryPosition'] < group[expected_terminal+'Position'], 'Owner action association reordered')
        for event in ('capture', 'query', 'reply', 'native-terminal-receipt', expected_terminal):
            identity_equal(track, group[event], OWNER_IDENTITY, 'Owner action/phase binding advanced')
            identity_equal(capture, group[event], OWNER_RECEIPT, 'Owner sealed action/native/token binding advanced')
        require(reply['token'] in tokens, 'Owner Ack token has no exact native admission')
        lifetime = tokens[reply['token']]
        accepted, retired = lifetime['accepted'], lifetime['retired']
        nonce = query['nonce']
        require(nonce in queries, 'Missing exact nonce-associated server query')
        server_query = queries[nonce]
        used.add(nonce)
        for row in (server_query, reply):
            native(row)
            identity_equal(accepted, row, IDENTITY+('token',), 'Fresh query/native admitted identity differs')
            observed = retired if row['stage'] == 'terminal' else accepted
            identity_equal(observed, row, BOOLEANS+('stage', 'reason', 'nativeState'), 'Query snapshot contradicts exact observed native lifecycle stage')
            require(row['monoNs'] >= observed['monoNs'] and (row['stage'] == 'terminal' or row['monoNs'] <= retired['monoNs']),
                    'Query snapshot time contradicts exact local native lifecycle')
            identity_equal(query, row, ('nonce', 'index', 'phase', 'owner', 'cart', 'transaction', 'kind', 'token'), 'Query challenge or sealed receipt differs')
        identity_equal(server_query, reply, IDENTITY+BOOLEANS+('token', 'stage', 'reason', 'nativeState'), 'Server query snapshot changed on owner reply')
        require(accepted['owner'] == capture['owner'] and accepted['cart'] == capture['cart']
                and accepted['transaction'] == capture['transaction'] and accepted['kind'] == capture['kind'],
                'Native admission differs from explicit sealed owner transaction')
        expected_kind = 'ToolkitWoodCartPickup' if PHASES[index-1].startswith('pickup') else None
        require(capture['kind'] == expected_kind if expected_kind else capture['kind'] in ('ToolkitWoodCartSetdown', 'ToolkitWoodCartDrop'),
                'Native kind differs from explicit phase operation')
        direct_outcome = {'Done': 'completed', 'Reject': 'rejected'}.get(retired['nativeState'])
        require(direct_outcome is None or receipt['state'] == direct_outcome,
                'Direct native terminal state contradicts exact owner native receipt outcome')
        expected_outcome = 'canceled' if index in (3, 5) else 'completed'
        require(receipt['state'] == expected_outcome, 'Selected owner phase native receipt outcome differs')
        if expected_terminal == 'terminal':
            require(terminal['state'] == receipt['state'], 'Owner sealed terminal and native receipt outcomes contradict')
        results.append(dict(index=index, phase=PHASES[index-1], ownerID=accepted['owner'], cartID=accepted['cart'],
            process=accepted['process'], sourceSession=accepted['sourceSession'], startGeneration=accepted['startGeneration'],
            token=accepted['token'], transaction=accepted['transaction'], kind=accepted['kind'],
            localActionEpoch=track['localActionEpoch'], localNativeEpoch=capture['localNativeEpoch'],
            ownerNativeReceiptOutcome=receipt['state'],
            ownerSealedOutcome=terminal['state'] if expected_terminal == 'terminal' else None,
            ownerSealRevocationReason=terminal['reason'] if expected_terminal == 'seal-revoked' else None,
            captureGeneration=capture['captureGeneration'],
            observedGeneration=terminal.get('observedGeneration') if expected_terminal == 'seal-revoked' else None,
            nativeTerminalState=retired['nativeState'],
            nativeRetirementReason=retired['reason'], queryObservedStage=server_query['stage']))
    require(used == set(queries), 'Unmatched extra native action query')
    require(len({row['startGeneration'] for row in results}) == 6, 'Native start associated to multiple owner phases')
    return dict(schema=1, diagnosticOnly=True, evidenceComplete=True, nativeLifetimes=6, exactOwnerAssociations=6,
        ownerSealedTerminalAssociations=4, ownerRevokedSealAssociations=2,
        logicalQueryMessages=dict(total=12, clientToServer=6, serverToClient=6), phases=results,
        sourceFiles={role: role+'-launch.log' for role in ROLES},
        qualification='Observed server native action admission plus exact initial sealed owner receipt association. Native retirement state/reason, historical native owner receipt outcome and current sealed authority are separate facts; native remove does not by itself prove cancellation or success. Cancel/reset revokes the seal; no authority survives that reset and no seal is renewed by this probe. No observer skeleton/proxy binding, reconnect/reject/ID-reuse matrix, production migration, runtime PASS or full-image timing is established. Logical queries are not wire bytes.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(analyze(args.profile), indent=2))


if __name__ == '__main__':
    main()
