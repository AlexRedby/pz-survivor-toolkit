"""Verify real razor UI producer effects from separate native process receipts."""
import copy
from pathlib import Path
import re

from .. import placement
from .claimed_return_verifier import number, operation_key, records

PREFIX = '[RAZOR_RESTORATION] '
TYPES = {'razor': 'Base.Razor', 'previous': 'Base.Hammer', 'replacement': 'Base.Screwdriver', 'tail': 'Base.BookCarpentry1'}
ACTION_TYPES = {'pickup': 'ISInventoryTransferAction', 'preparationEquip': 'ISEquipWeaponAction', 'trim': 'ISTrimBeard',
                'restore': 'ISEquipWeaponAction', 'returned': 'ISInventoryTransferAction', 'tail': 'ISReadABook',
                'explicitEquip': 'ISEquipWeaponAction', 'command': 'ISQueueActionsAction', 'approach': 'ISQueueActionsAction'}
ACTION_FIELDS = ('role', 'type', 'actionRef', 'itemId', 'constructorDuration')


def expected(ids, authority):
    row = copy.deepcopy(ids['baseline'])
    row['appearance']['beard'] = ids['targetBeard']
    row['primary'] = ids['items']['previous' if ids['case'] == 'restore-success' else 'replacement']['id']
    row['tail']['pages'] = row['tail']['characterPages'] = ids['items']['tail']['total']
    if ids['case'] == 'new-primary-intent':
        for item in row['items']:
            if item['id'] == ids['items']['razor']['id']:
                item['container'] = 'root'
    row['authority'] = authority
    return row


def validate_prepared(ids, selection):
    if (ids.get('case') not in selection['cases'] or ids.get('initialBeard') != 'LongScruffy'
            or ids.get('targetBeard') != 'Moustache' or set(ids.get('items', {})) != set(TYPES)):
        raise ValueError('prepared native beard/item topology differs')
    owned = ids['items']; baseline = ids['baseline']; bag = ids['bag']
    specs = [bag, *owned.values()]
    if (bag.get('type') != 'Base.Bag_Military' or len({item.get('id') for item in specs}) != len(specs)
            or any(type(item.get('id')) is not int or item['id'] < 0 for item in specs)
            or any(owned[name].get('type') != kind for name, kind in TYPES.items())):
        raise ValueError('prepared item identity/type differs')
    rows = baseline['items']; by_id = {item['id']: item for item in rows}
    if (len(by_id) != len(rows) or [item['id'] for item in rows] != sorted(by_id)
            or any(item.get('canonical') is not True or type(item.get('id')) is not int
                   or type(item.get('type')) is not str or not item['type']
                   or type(item.get('condition')) is not int or item['condition'] < 0
                   or type(item.get('favorite')) is not bool or type(item.get('count')) is not int or item['count'] < 1
                   for item in rows)):
        raise ValueError('inventory snapshot is not exact/canonical')
    for item in rows:
        seen = {item['id']}; parent = item['container']
        while parent != 'root':
            if parent in seen or parent not in by_id:
                raise ValueError('inventory ancestry broken')
            seen.add(parent); parent = by_id[parent]['container']
    for name, spec in owned.items():
        item = by_id[spec['id']]
        if (item['type'] != spec['type'] or item['favorite'] is not True
                or item['container'] != (bag['id'] if name == 'razor' else 'root')):
            raise ValueError('owned initial inventory location differs')
    if (by_id[bag['id']]['container'] != 'root' or by_id[bag['id']]['type'] != bag['type']
            or len([item for item in baseline['worn'] if item.get('id') == bag['id']]) != 1
            or baseline.get('case') != ids['case'] or baseline.get('male') is not True
            or baseline.get('primary') != owned['previous']['id'] or baseline.get('secondary') is not False
            or baseline['appearance'].get('beard') != ids['initialBeard']):
        raise ValueError('authority seed equipment/appearance differs')
    tail = owned['tail']; checkpoint = baseline['tail']
    if (type(tail.get('total')) is not int or type(tail.get('initial')) is not int
            or tail['total'] - tail['initial'] != 2 or tail['initial'] <= 0
            or checkpoint != dict(id=tail['id'], type=tail['type'], total=tail['total'], pages=tail['initial'], characterPages=tail['initial'])):
        raise ValueError('independent reader initial checkpoint differs')
    placement.validate(ids['placementProof'], ids['placement'], 'replica' if selection['kind'] == 'mp' else 'local', centered=True)


def physical_transfer_errors(sample, ids, role, authority):
    pickup = role == 'pickup'
    if (not isinstance(sample, dict) or sample.get('case') != ids['case'] or sample.get('role') != role
            or sample.get('authority') is not authority or not number(sample.get('at'))
            or sample.get('itemId') != ids['items']['razor']['id'] or sample.get('itemType') != 'Base.Razor'
            or sample.get('source') != (ids['bag']['id'] if pickup else 'root')
            or sample.get('destination') != ('root' if pickup else ids['bag']['id'])
            or sample.get('canonical') is not True or sample.get('bagCanonical') is not True
            or type(sample.get('sourceCount')) is not int or type(sample.get('destinationCount')) is not int
            or (sample['sourceCount'], sample['destinationCount']) not in ((1, 0), (0, 1))):
        return ['Exact physical inventory transaction identity/ancestry differs: ' + role]
    return []


def transfer_errors(action, ids, kind):
    role = action['role']; samples = action.get('transfers'); errors = []
    if type(samples) is not list or not samples:
        return ['Native inventory transaction observations missing: ' + role]
    completed = False; transactions = set()
    for sample in samples:
        physical = sample.get('physical', {})
        errors.extend(physical_transfer_errors(physical, ids, role, kind == 'sp'))
        if (sample.get('boundary') not in ('poll', 'begin-perform', 'finish-perform', 'begin-complete', 'finish-complete')
                or not number(sample.get('at')) or sample.get('nativeRef') != action.get('nativeRef')
                or operation_key(sample.get('operationRef')) != operation_key(action.get('operationRef'))
                or any(sample.get(key) is not True for key in ('itemExact', 'nativeSame', 'actorSame', 'operationSame',
                                                             'sourceSame', 'destinationSame', 'queueSame', 'rootSame'))
                or sample.get('itemState') not in ('original', 'canonical-replica', 'nil')):
            errors.append('Native transfer episode/endpoints/item identity changed: ' + role + '/' + str(sample.get('boundary')))
        tx = sample.get('transaction')
        if type(tx) is not int or sample.get('rejected') is not False:
            errors.append('Rejected/malformed native inventory transaction: ' + role)
            continue
        if tx != 0: transactions.add(tx)
        if sample.get('done') is True:
            if tx == 0 or not number(sample.get('duration')) or sample['duration'] <= 1:
                errors.append('Completed native inventory transaction lacks ID/duration: ' + role)
            if physical.get('sourceCount') == 0 and physical.get('destinationCount') == 1:
                completed = True
        if sample.get('itemState') == 'nil' and not completed:
            errors.append('Nil transfer item preceded exact native transaction completion: ' + role)
    if kind == 'mp' and (len(transactions) != 1 or not completed):
        errors.append('Single native inventory transaction completion/physical destination missing: ' + role)
    if action.get('ack') != []:
        errors.append('Inventory transfer incorrectly uses timed-action UUID ACK: ' + role)
    return errors


def authority_transfer_errors(receipt, ids):
    values = receipt.get('transfers'); expected_roles = ['pickup', 'returned'] if ids['case'] == 'restore-success' else ['pickup']
    if type(values) is not list or [value.get('role') for value in values] != expected_roles:
        return ['Independent authority physical transfer transitions missing/reordered']
    errors = []
    for role, value in zip(expected_roles, values):
        errors.extend(physical_transfer_errors(value, ids, role, True))
        if value.get('sourceCount') != 0 or value.get('destinationCount') != 1:
            errors.append('Authority transfer did not reach exact destination: ' + role)
    if [value['at'] for value in values] != sorted(value['at'] for value in values):
        errors.append('Authority physical transfer transition times reordered')
    return errors


def producer_errors(ev, roles, ids):
    errors = []
    prefix = ['approach'] if 'approach' in roles else []
    names = prefix + ['pickup', 'preparationEquip', 'trim', 'command']
    expected = [roles[name][0]['actionRef'] for name in names]
    entries = ev.get('producerEntries')
    if ev.get('producerQueue') != expected or type(entries) is not list or len(entries) != len(names):
        return ['UI producer exact queue array/topology differs']
    token = operation_key(roles['trim'][0]['operationRef'])
    for index, (name, entry) in enumerate(zip(names, entries), 1):
        action = roles[name][0]
        if (entry.get('position') != index or entry.get('actionRef') != action['actionRef'] or entry.get('role') != name
                or any(entry.get(key) is not True for key in ('sameToken', 'actorSame', 'queueEntrySame'))
                or operation_key(entry.get('operationRef')) != token
                or operation_key(action.get('operationRef')) != token):
            errors.append('Producer queue array identity/position/actor/token differs: ' + name)
    approach = ev.get('approach')
    if not prefix:
        if approach is not False:
            errors.append('Unrequested/unauthenticated approach receipt')
        return errors
    action = roles['approach'][0]; pickup = roles['pickup'][0]
    if (type(approach) is not dict or approach.get('actionRef') != action['actionRef']
            or approach.get('position') != 1 or approach.get('type') != 'ISQueueActionsAction'
            or approach.get('bagId') != ids['bag']['id'] or not isinstance(approach.get('containerRef'), str)
            or approach.get('containerRef') != pickup.get('sourceRef')
            or operation_key(approach.get('operationRef')) != token or action.get('allocated') is not True
            or any(approach.get(key) is not True for key in ('sourceBound', 'pickupSourceSame', 'canonicalBag', 'actorSame',
                                                          'sameToken', 'queueSame', 'listSame', 'queueEntrySame'))):
        errors.append('Optional approach lacks exact live container predicate, canonical bag, array position or native identity')
    return errors


def check_case(row, selection, prepared, verified):
    errors = []
    try:
        case = row['id']; ids = row['ids']; ev = row['evidence']; success = case == 'restore-success'
        if (ids != prepared or ids['case'] != case or row.get('status') != 'passed' or row.get('actor') != 'client1'
                or row.get('kind') != selection['kind'] or row.get('mode') != 'toolkit'):
            raise ValueError('exact native case/process identity differs')
        validate_prepared(ids, selection)
        placement.validate(row['clientPlacement'], ids['placement'], 'local', centered=True)
        authority_snapshot = dict(verified); authority_snapshot.pop('transfers', None)
        errors.extend(authority_transfer_errors(verified, ids))
        if (row.get('server') != verified or authority_snapshot != expected(ids, True)
                or row.get('client') != expected(ids, selection['kind'] == 'sp') or ev.get('after') != row['client']
                or ev.get('before') != ids['baseline']):
            errors.append('Independent authority/client exact inventory, hands, appearance or reader effects differ')
        if any(ev.get(key) != value for key, value in {'producer': 'ISCharacterScreen.onTrimBeard', 'target': 'Moustache',
                'installed': True, 'explicitRequested': not success, 'nativeCallbacksUntouched': True, 'queueIdle': True}.items()):
            errors.append('Real install/menu producer or native callback integrity differs')
        actions = ev['actions']; roles = {}
        for action in actions:
            roles.setdefault(action['role'], []).append(action)
        required = {'pickup', 'preparationEquip', 'trim', 'tail', 'command', *({'restore', 'returned'} if success else {'explicitEquip'})}
        if 'approach' in roles: required.add('approach')
        if set(roles) != required or any(len(values) != (2 if success else 1) if role == 'command' else len(values) != 1
                                       for role, values in roles.items()):
            raise ValueError('Native producer/cleanup action topology differs')
        refs = [action['actionRef'] for action in actions]
        if any(type(ref) is not str or not ref for ref in refs) or len(set(refs)) != len(refs):
            raise ValueError('Action identity duplicated/missing')
        errors.extend(producer_errors(ev, roles, ids))
        seed = ev.get('handSeed')
        if seed != dict(id=ids['items']['previous']['id'], type='Base.Hammer', requiresBoth=False,
                        handWeapon=True, supportsTwo=False, ordinary=True):
            errors.append('Initial primary lacks exact ordinary one-hand restoration proof')
        for role, values in roles.items():
            for action in values:
                if action.get('type') != ACTION_TYPES[role]:
                    raise ValueError('Action native class differs: ' + role)
                if role in ('command', 'approach'):
                    continue
                item = 'previous' if role == 'restore' else 'replacement' if role == 'explicitEquip' else 'tail' if role == 'tail' else 'razor'
                if (action.get('itemId') != ids['items'][item]['id'] or any(action.get(key) is not True for key in ('allocated', 'started', 'progress'))
                        or not number(action.get('startedAt')) or not number(action.get('effectiveDuration')) or action['effectiveDuration'] <= 1
                        or not isinstance(action.get('nativeRef'), str) or not isinstance(action.get('operationRef'), str)):
                    errors.append('Native duration/allocation/progress missing: ' + role)
                duration = action.get('constructorDuration')
                if not number(duration) or (duration != -1 if selection['kind'] == 'mp' and role in ('pickup', 'returned') else duration <= 1):
                    errors.append('Original native constructor duration differs: ' + role)
                events = action.get('events', [])
                expected_events = [(boundary, phase) for phase in (('perform', 'complete') if selection['kind'] == 'sp' else ('perform',)) for boundary in ('begin', 'finish')]
                if ([(event.get('boundary'), event.get('phase')) for event in events] != expected_events
                        or any(not number(event.get('at')) or event.get('nativeRef') != action['nativeRef']
                               or event['boundary'] == 'finish' and event.get('succeeded') is not True for event in events)):
                    errors.append('Unchanged native completion lifecycle differs: ' + role)
                if role in ('pickup', 'returned'):
                    errors.extend(transfer_errors(action, ids, selection['kind']))
                elif selection['kind'] == 'mp':
                    terminal = [ack for ack in action.get('ack', []) if ack.get('state') in ('completed', 'canceled', 'rejected')]
                    if (len(terminal) != 1 or terminal[0]['state'] != 'completed' or terminal[0].get('kind') != action['type']
                            or type(terminal[0].get('transaction')) is not int
                            or not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', str(terminal[0].get('token')))
                            or any(terminal[0].get(key) is not True for key in ('nativeSame', 'actorSame', 'queueSame', 'rootSame', 'itemSame', 'operationSame'))
                            or terminal[0].get('nativeRef') != action['nativeRef']
                            or operation_key(terminal[0].get('operationRef')) != operation_key(action['operationRef'])):
                        errors.append('Host exact native completed ACK differs: ' + role)
        get = lambda name: roles[name][0]
        pickup, equip, trim, tail = (get(name) for name in ('pickup', 'preparationEquip', 'trim', 'tail'))
        if not pickup['startedAt'] <= equip['startedAt'] <= trim['startedAt'] <= tail['startedAt']:
            errors.append('Native borrow/equip/trim/independent reader ordering differs')
        token = operation_key(trim['operationRef'])
        if (any(operation_key(get(name)['operationRef']) != token for name in ('pickup', 'preparationEquip'))
                or operation_key(tail['operationRef']) == token):
            errors.append('Native borrowing chain or independent operation ownership differs')
        debts = ev.get('debts')
        if success:
            restore, returned = get('restore'), get('returned')
            if (not trim['startedAt'] <= restore['startedAt'] <= returned['startedAt'] <= tail['startedAt']
                    or any(operation_key(action['operationRef']) != token for action in (restore, returned))
                    or debts != [] or 'intent' in ev):
                errors.append('Ordinary native restore/return effects or debt differ')
        else:
            intent = ev.get('intent', {}); explicit = get('explicitEquip')
            snapshot = intent.get('snapshot', {})
            during = copy.deepcopy(ids['baseline']); during['primary'] = ids['items']['razor']['id']
            for item in during['items']:
                if item['id'] == ids['items']['razor']['id']: item['container'] = 'root'
            if (not number(intent.get('at')) or not trim['startedAt'] <= intent['at'] <= tail['startedAt'] <= explicit['startedAt']
                    or not number(intent.get('trimDelta')) or not 0 < intent['trimDelta'] < 1
                    or type(intent.get('before')) is not int or type(intent.get('after')) is not int or intent['after'] <= intent['before']
                    or intent.get('before') != ev.get('initialRevision') or intent.get('trimRef') != trim['actionRef']
                    or intent.get('trimNative') != trim['nativeRef'] or intent.get('explicitActionRef') != explicit['actionRef']
                    or intent.get('explicitUnallocated') is not True or snapshot.get('primary') != ids['items']['razor']['id']
                    or snapshot != during
                    or operation_key(explicit['operationRef']) in (token, operation_key(tail['operationRef']))):
                errors.append('Accepted newer native primary intent did not precede old cleanup while trim genuinely progressed')
            if (type(debts) is not list or len(debts) != 1 or debts[0].get('itemId') != ids['items']['razor']['id']
                    or debts[0].get('itemType') != 'Base.Razor' or debts[0].get('state') != 'blocked'
                    or debts[0].get('reason') != 'cleanup-unresolved'):
                errors.append('Superseded auto restore lost its exact unpaid razor debt')
        boundary = ev.get('tailBoundary', {})
        at_tail = expected(ids, selection['kind'] == 'sp'); at_tail.pop('authority')
        at_tail['tail']['pages'] = at_tail['tail']['characterPages'] = ids['items']['tail']['initial']
        if not success: at_tail['primary'] = ids['items']['razor']['id']
        if (not number(boundary.get('at')) or boundary['at'] > tail['startedAt']
                or boundary.get('snapshot') != at_tail or boundary.get('debts') != debts):
            errors.append('Independent native reader admission inventory, hands or debt differ')
    except (KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
        errors.append('Malformed razor native evidence: ' + str(error))
    return errors


def verify(root, selection, catalog):
    issues = []; outcomes = []; cases = selection['cases']; root = Path(root)
    try:
        client = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else client
        events = [(pos, row) for pos, row in records(client, '[QUEUE_CHECK] ') if row.get('suite') == 'razor-restoration']
        setups = [(pos, row) for pos, row in events if row.get('event') == 'setup']
        rows = [(pos, row) for pos, row in events if row.get('event') == 'case']
        completions = [(pos, row) for pos, row in events if row.get('event') == 'complete']
        prepared = records(authority, PREFIX + 'PREPARED '); verified = records(authority, PREFIX + 'VERIFIED ')
        placements = records(client, PREFIX + 'CLIENT_PLACEMENT '); complete = records(client, PREFIX + 'COMPLETE ')
        if (len(setups) != 1 or any(setups[0][1].get(key) != value for key, value in dict(cases=cases, nativeDurations=True, provider='native-returns', installed=True).items())
                or len(completions) != 1 or any(completions[0][1].get(key) != value for key, value in dict(cases=cases, performed=len(cases), failed=0, skipped=0).items())
                or [row.get('id') for _, row in rows] != cases or [row for _, row in complete] != [dict(cases=cases)]
                or any([row.get('case') for _, row in stream] != cases for stream in (prepared, verified, placements))):
            raise ValueError('Missing, duplicate, foreign or reordered native setup/case/authority/completion receipts')
        if selection['kind'] == 'mp' and (records(client, PREFIX + 'PREPARED ') or records(client, PREFIX + 'VERIFIED ')
                or records(authority, PREFIX + 'CLIENT_PLACEMENT ') or records(authority, '[QUEUE_CHECK] ')):
            raise ValueError('Native evidence emitted by wrong process')
        if not setups[0][0] < placements[0][0] or not rows[-1][0] < completions[0][0] < complete[0][0]:
            issues.append('Native receipts escape setup/completion boundaries')
        action_rows = records(client, PREFIX + 'ACTION '); ack_rows = records(client, PREFIX + 'ACK '); intent_rows = records(client, PREFIX + 'INTENT ')
        transfers = records(client, PREFIX + 'TRANSFER '); authority_transfers = records(authority, PREFIX + 'TRANSFER_AUTHORITY ')
        if [value for _, value in authority_transfers] != [sample for _, value in verified for sample in value.get('transfers', [])]:
            issues.append('Independent raw authority transfer transitions differ from published receipt')
        expected_actions = [dict(case=row['id'], action={key: action[key] for key in ACTION_FIELDS if key in action})
                            for _, row in rows for action in row['evidence']['actions']]
        if [value for _, value in action_rows] != expected_actions:
            issues.append('Raw exact native action records differ from published case actions')
        if [value for _, value in intent_rows] != [dict(case=row['id'], observation=row['evidence']['intent']) for _, row in rows if 'intent' in row['evidence']]:
            issues.append('Raw accepted primary intent records differ')
        expected_ack = {(row['id'], action['actionRef']): action.get('ack', []) for _, row in rows for action in row['evidence']['actions']}
        actual_ack = {key: [] for key in expected_ack}
        for _, value in ack_rows:
            key = (value.get('case'), value.get('actionRef'))
            if key not in actual_ack:
                raise ValueError('foreign native ACK owner')
            actual_ack[key].append(value['observation'])
        expected_transfers = {(row['id'], action['actionRef']): action.get('transfers', []) for _, row in rows for action in row['evidence']['actions']}
        actual_transfers = {key: [] for key in expected_transfers}
        for _, value in transfers:
            key = (value.get('case'), value.get('actionRef'))
            if key not in actual_transfers: raise ValueError('foreign native transfer observation owner')
            actual_transfers[key].append(value['observation'])
        if actual_transfers != expected_transfers:
            issues.append('Raw native inventory transaction observations differ from published exact actions')
        if actual_ack != expected_ack:
            issues.append('Raw native ACK records differ from published exact episode observations')
        for index, (position, row) in enumerate(rows):
            errors = check_case(row, selection, prepared[index][1], verified[index][1])
            if (placements[index][1] != dict(case=row['id'], proof=row.get('clientPlacement')) or not placements[index][0] < position
                    or not prepared[index][0] < verified[index][0]
                    or selection['kind'] == 'sp' and not placements[index][0] < prepared[index][0] < verified[index][0] < position
                    or index and rows[index - 1][0] >= placements[index][0]):
                errors.append('Native placement/authority/case publication order differs')
            issues.extend(row['id'] + ': ' + error for error in errors)
            outcomes.append(dict(actor='client1', case=row['id'], status='failed' if errors else 'passed', reason='; '.join(errors)))
        if '[QUEUE_TEST] FAIL ' in client or '[QUEUE_TEST] FAIL ' in authority:
            issues.append('Native razor fixture reported failure')
    except (OSError, KeyError, TypeError, ValueError, AttributeError) as error:
        issues.append('Razor restoration verifier: ' + str(error))
    if issues:
        outcomes = [dict(actor='client1', case=case, status='failed', reason='; '.join(issues)) for case in cases]
    return dict(issues=issues, outcomes=outcomes)
