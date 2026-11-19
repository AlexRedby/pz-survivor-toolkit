"""Verify real razor UI producer effects from separate native process receipts."""
import copy
from pathlib import Path
import re

from .. import placement
from .claimed_return_verifier import number, operation_key, records

PREFIX = '[RAZOR_RESTORATION] '
TYPES = {'razor': 'Base.Razor', 'previous': 'Base.Hammer', 'replacement': 'Base.Screwdriver', 'tail': 'Base.BookCarpentry1'}
ACTION_TYPES = {'heavyPickup': 'ISInventoryTransferAction', 'pickup': 'ISInventoryTransferAction', 'preparationEquip': 'ISEquipWeaponAction', 'trim': 'ISTrimBeard',
                'restore': 'ISEquipWeaponAction', 'returned': 'ISInventoryTransferAction', 'tail': 'ISReadABook',
                'explicitEquip': 'ISEquipWeaponAction', 'command': 'ISQueueActionsAction', 'approach': 'ISQueueActionsAction'}
BELT_CASES = {'belt-scissors', 'belt-scissors-cancel', 'belt-scissors-replace'}
CANCEL_CASES = {'cancel-active', 'belt-scissors-cancel'}
ACTION_FIELDS = ('fromHotbar', 'role', 'type', 'actionRef', 'itemId', 'constructorDuration', 'hairStyle', 'equipPrimary', 'equipTwoHands')
RETURNED_CASES = {'heavy-stone-anvil', 'restore-success', 'empty-primary', 'cancel-active', 'trim-scissors', 'cut-hair-scissors', 'two-handed-axe', 'one-handed-axe', 'mandatory-both-stone-wheel'}
TWO_HANDED_AXE_CASES = {'two-handed-axe', 'two-handed-axe-new-primary-intent'}
ONE_HANDED_AXE_CASES = {'one-handed-axe', 'one-handed-axe-new-primary-intent'}
AXE_CASES = TWO_HANDED_AXE_CASES | ONE_HANDED_AXE_CASES
MANDATORY_BOTH_TYPES = {'mandatory-both-stone-wheel': 'Base.StoneWheelSmall',
                        'mandatory-both-wood-axe-new-primary-intent': 'Base.WoodAxe'}
MANDATORY_BOTH_CASES = set(MANDATORY_BOTH_TYPES)
HEAVY_CASES = {'heavy-stone-anvil', 'heavy-stone-anvil-new-primary-intent', 'heavy-stone-anvil-unavailable'}
UNAVAILABLE_HEAVY = 'heavy-stone-anvil-unavailable'
SHARED_HAND_CASES = TWO_HANDED_AXE_CASES | MANDATORY_BOTH_CASES | HEAVY_CASES
EQUIPMENT_CASES = AXE_CASES | MANDATORY_BOTH_CASES | HEAVY_CASES
PREPARATION_BOUNDARY_CASES = ONE_HANDED_AXE_CASES | MANDATORY_BOTH_CASES | HEAVY_CASES
INTENT_CASES = {'heavy-stone-anvil-new-primary-intent', 'new-primary-intent', 'two-handed-axe-new-primary-intent', 'one-handed-axe-new-primary-intent', 'mandatory-both-wood-axe-new-primary-intent'}
RESTORE_BOUNDARY_CASES = {'empty-primary'} | (EQUIPMENT_CASES - INTENT_CASES - {UNAVAILABLE_HEAVY})
SCISSORS_CASES = {'trim-scissors', 'cut-hair-scissors'}


def item_types(case):
    values = dict(TYPES)
    if case in SCISSORS_CASES | BELT_CASES: values['razor'] = 'Base.Scissors'
    if case in HEAVY_CASES: values['previous'] = 'Base.StoneAnvil'
    if case in AXE_CASES: values['previous'] = 'Base.Axe'
    if case in MANDATORY_BOTH_CASES: values['previous'] = MANDATORY_BOTH_TYPES[case]
    if case in ONE_HANDED_AXE_CASES: values['secondary'] = 'Base.Pen'
    if case in BELT_CASES: values['belt'] = 'Base.Belt2'
    return values


def grooming(case):
    return ('ISCharacterScreen.onCutHair', 'ISCutHair', 'Bald') if case == 'cut-hair-scissors' else ('ISCharacterScreen.onTrimBeard', 'ISTrimBeard', 'Moustache')
ORIGIN_CASES = {'full-origin', 'unavailable-origin', 'keep-return'}


def heavy_physical(ids, state):
    at = ids['placement']; spec = ids['items']['previous']
    return dict(id=spec['id'], type=spec['type'], x=at['x'], y=at['y'], z=at['z'],
                state=state, rootPresent=state == 'root', worldPresent=state == 'world', canonical=True)


def heavy_errors(ev, authority, ids, kind):
    values = authority.get('heavyTransitions', [])
    if ids['case'] not in HEAVY_CASES:
        return [] if values == [] and 'heavyRemoval' not in ev else ['Unrequested heavy world observations']
    try:
        phases = ['dropped', 'recovered'] if ids['case'] == 'heavy-stone-anvil' else ['dropped', 'removed'] if ids['case'] == UNAVAILABLE_HEAVY else ['dropped']
        if type(values) is not list or [value.get('phase') for value in values] != phases:
            raise ValueError('exact authority drop/recovery/removal sequence differs')
        for value, phase in zip(values, phases):
            state = {'dropped': 'world', 'recovered': 'root', 'removed': 'unavailable'}[phase]
            if (value.get('case') != ids['case'] or value.get('authority') is not True or value.get('itemSame') is not True
                    or type(value.get('player')) is not int or value['player'] != ids['heavyActor'] or not number(value.get('at'))
                    or value.get('physical') != heavy_physical(ids, state)
                    or value.get('snapshot', {}).get('heavy') != value['physical']):
                raise ValueError('authority exact actor/seeded item/world identity differs')
        if [value['at'] for value in values] != sorted(value['at'] for value in values):
            raise ValueError('heavy authority transitions reordered')
        if values[0]['snapshot'] != borrowed_snapshot(ids):
            raise ValueError('authority native preparation failed to drop exact shared prior item')
        if ids['case'] == UNAVAILABLE_HEAVY:
            receipt = ev['heavyRemoval']; before = borrowed_snapshot(ids); after = copy.deepcopy(before)
            after['heavy'] = heavy_physical(ids, 'unavailable')
            for item in after['items']:
                if item['id'] == ids['items']['previous']['id']: item['container'] = 'unavailable'
            if (receipt.get('case') != ids['case'] or receipt.get('authority') is not True
                    or not number(receipt.get('at')) or not number(receipt.get('requestedAt'))
                    # The server can first observe the drop while handling the client's request.
                    or not ev['preparationBoundary']['at'] <= receipt['requestedAt'] <= receipt['at']
                    or not values[0]['at'] <= receipt['at'] <= values[1]['at']
                    or receipt.get('before') != before or receipt.get('after') != after):
                raise ValueError('exact authority removal during active trim differs')
        elif 'heavyRemoval' in ev:
            raise ValueError('unexpected heavy removal')
        return []
    except (KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
        return ['Heavy native world evidence differs: ' + str(error)]


def action_key(value):
    """Kahlua action identity excludes its mutable diagnostic field dump."""
    if isinstance(value, str):
        match = re.fullmatch(r'([A-Za-z][A-Za-z0-9_]*) 0x(0|[1-9][0-9]*)(?:\{[^\r\n]*\})?', value)
        if match and int(match[2]) <= 2147483647:
            return ('native-action', match[1], match[2])
    return ('literal', value)


def expected(ids, authority, authority_wire=False):
    row = copy.deepcopy(ids['baseline'])
    if ids['case'] == 'cut-hair-scissors':
        row['appearance'].update(hair=ids['targetHair'], nonAttached=False)
    else:
        row['appearance']['beard'] = ids['initialBeard'] if ids['case'] in CANCEL_CASES else ids['targetBeard']
    row['primary'] = ids['items']['razor']['id'] if ids.get('handAckDelay') else False if ids['case'] == 'empty-primary' else ids['items']['replacement' if ids['case'] in INTENT_CASES else 'previous']['id']
    if ids['case'] in SHARED_HAND_CASES and (ids['case'] in INTENT_CASES or ids['case'] == UNAVAILABLE_HEAVY): row['secondary'] = False
    if ids['case'] == UNAVAILABLE_HEAVY: row['primary'] = ids['items']['razor']['id']
    if ids['case'] in HEAVY_CASES and ids['case'] != 'heavy-stone-anvil':
        state = 'unavailable' if ids['case'] == UNAVAILABLE_HEAVY else 'world'
        row['heavy'].update(state=state, rootPresent=False, worldPresent=state == 'world')
        for item in row['items']:
            if item['id'] == ids['items']['previous']['id']: item['container'] = state
    row['tail']['pages'] = row['tail']['characterPages'] = ids['items']['tail']['total']
    if ids['case'] in BELT_CASES:
        if ids['case'] == 'belt-scissors-replace':
            row['belt']['tool'].update(slot=-1, slotType='' if authority_wire else False, model='' if authority_wire else False)
            row['belt']['replacement'].update(slot=ids['beltIndex'], slotType='SmallBeltLeft', model='Belt Left Screwdriver')
            row['belt']['occupant'] = ids['items']['replacement']['id']
    elif ids.get('handAckDelay') or ids['case'] not in RETURNED_CASES:
        row['origin']['sourceCount'] = 0
        for item in row['items']:
            if item['id'] == ids['items']['razor']['id']:
                item['container'] = 'root'
    if ids['case'] == 'unavailable-origin':
        row['origin'].update(container='unavailable', worn=False)
        for item in row['items']:
            if item['id'] == ids['bag']['id']: item['container'] = 'unavailable'
        row['worn'] = [item for item in row['worn'] if item['id'] != ids['bag']['id']]
    row['authority'] = authority
    return row


def seed_hands(ids):
    owned = ids['items']; case = ids['case']
    return dict(primary=False if case == 'empty-primary' else owned['previous']['id'],
                secondary=owned['secondary']['id'] if case in ONE_HANDED_AXE_CASES else
                owned['previous']['id'] if case in SHARED_HAND_CASES or case == 'empty-primary' else False)


def equip_mode_errors(action, ids):
    if ids['case'] not in EQUIPMENT_CASES or action.get('type') != 'ISEquipWeaponAction': return []
    two = action.get('role') == 'restore' and ids['case'] in SHARED_HAND_CASES
    flag = action.get('equipTwoHands', False) if ids['case'] in TWO_HANDED_AXE_CASES else action.get('equipTwoHands')
    if action.get('equipPrimary') is not True or flag is not two:
        return ['Native preparation/restoration/explicit hand mode differs: ' + str(action.get('role'))]
    return []


def hand_seed_errors(seed, ids):
    case = ids['case']; previous_type = item_types(case)['previous']
    wanted = dict(type=previous_type, requiresBoth=case in MANDATORY_BOTH_CASES | HEAVY_CASES,
                  handWeapon=previous_type not in ('Base.StoneWheelSmall', 'Base.StoneAnvil'),
                  supportsTwo=previous_type in ('Base.Axe', 'Base.WoodAxe'), ordinary=case not in HEAVY_CASES)
    wanted.update(dict(primary=False, secondary=ids['items']['previous']['id']) if case == 'empty-primary'
                  else dict(id=ids['items']['previous']['id']))
    if case in EQUIPMENT_CASES: wanted['secondary'] = seed_hands(ids)['secondary']
    if case in MANDATORY_BOTH_CASES | HEAVY_CASES: wanted['forceDropHeavy'] = case in HEAVY_CASES
    if case in HEAVY_CASES:
        at = ids['placement']
        wanted.update(ordinaryUnavailable=True, heavy=dict(captured=True, actorSame=True, rootSame=True, itemSame=True,
            id=ids['items']['previous']['id'], type=previous_type, squareSame=True, primarySame=True, secondarySame=True,
            position=dict(x=at['x'] + .5, y=at['y'] + .5, z=at['z']), square=dict(at)))
    valid = type(seed) is dict and seed == wanted and all(type(seed[key]) is type(value) for key, value in wanted.items())
    if valid and case in HEAVY_CASES:
        valid = all(type(seed['heavy'][key]) is type(value) for key, value in wanted['heavy'].items())
    return [] if valid else ['Initial hands lack exact ordinary restoration proof']


def validate_prepared(ids, selection):
    if (ids.get('case') not in selection['cases'] or ids.get('initialBeard') != 'LongScruffy'
            or ids.get('targetBeard') != 'Moustache' or set(ids.get('items', {})) != set(item_types(ids.get('case')))):
        raise ValueError('prepared native beard/item topology differs')
    if ids.get('handAckDelay', False) is not (selection.get('options', {}).get('razor_hand_ack_delay_ms') is not None):
        raise ValueError('hand authority prepared flag differs from explicit selection')
    owned = ids['items']; baseline = ids['baseline']; bag = ids['bag']
    if ids['case'] in HEAVY_CASES and (type(ids.get('heavyActor')) is not int or selection['kind'] == 'mp' and ids['heavyActor'] < 0):
        raise ValueError('prepared exact heavy actor identity differs')
    if baseline.get('heavy') != (heavy_physical(ids, 'root') if ids['case'] in HEAVY_CASES else None):
        raise ValueError('prepared exact heavy inventory/world topology differs')
    if ids['case'] == 'cut-hair-scissors' and (ids.get('initialHair') != 'Fabian' or ids.get('targetHair') != 'Bald'
            or baseline['appearance'].get('hair') != ids['initialHair'] or baseline['appearance'].get('nonAttached') is not False):
        raise ValueError('prepared plain haircut differs')
    specs = [bag, *owned.values()]
    if (bag.get('type') != 'Base.Bag_Military' or len({item.get('id') for item in specs}) != len(specs)
            or any(type(item.get('id')) is not int or item['id'] < 0 for item in specs)
            or any(owned[name].get('type') != kind for name, kind in item_types(ids['case']).items())):
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
                or item['container'] != (bag['id'] if name == 'razor' and ids['case'] not in BELT_CASES else 'root')):
            raise ValueError('owned initial inventory location differs')
    if (by_id[bag['id']]['container'] != 'root' or by_id[bag['id']]['type'] != bag['type']
            or len([item for item in baseline['worn'] if item.get('id') == bag['id']]) != 1
            or baseline.get('case') != ids['case'] or baseline.get('male') is not True
            or any(type(baseline.get(slot)) is not type(value) or baseline[slot] != value for slot, value in seed_hands(ids).items())
            or baseline['appearance'].get('beard') != ids['initialBeard']):
        raise ValueError('authority seed equipment/appearance differs')
    if baseline.get('origin') != dict(id=bag['id'], type=bag['type'], container='root', worn=True, sourceCount=0 if ids['case'] in BELT_CASES else 1):
        raise ValueError('origin baseline exact carried/worn inventory differs')
    tail = owned['tail']; checkpoint = baseline['tail']
    if (type(tail.get('total')) is not int or type(tail.get('initial')) is not int
            or tail['total'] - tail['initial'] != 2 or tail['initial'] <= 0
            or checkpoint != dict(id=tail['id'], type=tail['type'], total=tail['total'], pages=tail['initial'], characterPages=tail['initial'])):
        raise ValueError('independent reader initial checkpoint differs')
    placement.validate(ids['placementProof'], ids['placement'], 'replica' if selection['kind'] == 'mp' else 'local', centered=True)


def physical_transfer_errors(sample, ids, role, authority):
    if role == 'heavyPickup':
        if not isinstance(sample, dict): return ['Malformed heavy world transaction']
        state = sample.get('heavy', {}) if isinstance(sample, dict) else {}
        if (sample.get('case') != ids['case'] or sample.get('role') != role or sample.get('authority') is not authority
                or not number(sample.get('at')) or sample.get('itemId') != ids['items']['previous']['id']
                or sample.get('itemType') != 'Base.StoneAnvil' or sample.get('source') != 'world' or sample.get('destination') != 'root'
                or sample.get('canonical') is not True or sample.get('bagCanonical') is not True
                or type(sample.get('sourceCount')) is not int or type(sample.get('destinationCount')) is not int
                or (sample.get('sourceCount'), sample.get('destinationCount')) not in ((1, 0), (0, 1))
                or state != heavy_physical(ids, 'world' if sample.get('sourceCount') == 1 else 'root')):
            return ['Exact heavy world transaction identity/ancestry differs']
        return []
    pickup = role == 'pickup'
    if (not isinstance(sample, dict) or sample.get('case') != ids['case'] or sample.get('role') != role
            or sample.get('authority') is not authority or not number(sample.get('at'))
            or sample.get('itemId') != ids['items']['razor']['id'] or sample.get('itemType') != ids['items']['razor']['type']
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
    values = receipt.get('transfers'); expected_roles = ['pickup', 'returned'] if ids['case'] in RETURNED_CASES and not ids.get('handAckDelay') else ['pickup']
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
    names = prefix + ([] if ids.get('case') in BELT_CASES else ['pickup']) + ['preparationEquip', 'trim', 'command']
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
                or operation_key(action.get('originalOperationRef', action.get('operationRef'))) != token):
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


def borrowed_snapshot(ids):
    row = copy.deepcopy(ids['baseline']); row['primary'] = ids['items']['razor']['id']
    if ids['case'] in BELT_CASES: row['belt']['occupant'] = False
    if ids['case'] in SHARED_HAND_CASES: row['secondary'] = False
    if ids['case'] in HEAVY_CASES:
        row['heavy'] = heavy_physical(ids, 'world')
        for item in row['items']:
            if item['id'] == ids['items']['previous']['id']: item['container'] = 'world'
    row['origin']['sourceCount'] = 0
    for item in row['items']:
        if item['id'] == ids['items']['razor']['id']: item['container'] = 'root'
    return row


def blocked_debt_errors(debts, ids):
    if (type(debts) is not list or len(debts) != 1 or type(debts[0].get('id')) is not int
            or debts[0]['id'] <= 0 or debts[0].get('itemId') != ids['items']['razor']['id']
            or debts[0].get('itemType') != 'Base.Razor' or debts[0].get('state') != 'blocked'
            or debts[0].get('reason') not in (('cleanup-return',) if ids['case'] == 'unavailable-origin' else ('admission', 'server', 'unmoved'))):
        return ['Exact unpaid razor debt missing or changed']
    return []


def reader_snapshot_errors(snapshot, ids):
    wanted = expected(ids, False); wanted.pop('authority')
    pages = snapshot.get('tail', {}).get('pages')
    if not number(pages) or not ids['items']['tail']['initial'] <= pages <= ids['items']['tail']['total']:
        return ['Reader checkpoint escapes exact native range']
    wanted['tail']['pages'] = wanted['tail']['characterPages'] = pages
    return [] if snapshot == wanted else ['Exact blocked/Keep inventory, hands, appearance or reader state differs']


def control_errors(ev, roles, ids, kind='sp'):
    case = ids['case']; control = ev.get('control'); errors = []
    if case not in ORIGIN_CASES and case not in CANCEL_CASES:
        return [] if all(key not in ev for key in ('control', 'origin', 'originReplica', 'blocked', 'keep')) else ['Unrequested live control evidence']
    trim, tail = roles['trim'][0], roles['tail'][0]
    if (type(control) is not dict or not number(control.get('at'))
            or not trim['startedAt'] <= control['at'] <= tail['startedAt']
            or control.get('trimRef') != trim['actionRef'] or control.get('trimNative') != trim['nativeRef']
            or not number(control.get('trimDelta')) or not 0 < control['trimDelta'] < 1
            or control.get('before') != borrowed_snapshot(ids) or control.get('accepted') is not True):
        return ['Control lacks exact genuinely progressing native trim identity/state']
    if case in CANCEL_CASES:
        members = control.get('members')
        if (control.get('source') != 'ActionQueuePanel.List' or control.get('input') != 'programmatic-press-release'
                or control.get('after') != control['before'] or control.get('reason') is not False
                or action_key(control.get('targetRef')) != action_key(trim['actionRef'])
                or operation_key(control.get('operationRef')) != operation_key(trim['operationRef'])
                or any(control.get(key) is not True for key in ('header', 'hitTested', 'pressCaptured', 'tailQueued'))
                or type(members) is not list or [action_key(member) for member in members] != [action_key(trim['actionRef']), action_key(roles['command'][0]['actionRef'])]
                or any(key in ev for key in ('origin', 'originReplica', 'blocked', 'keep'))):
            errors.append('Real active operation header cancel identity/hit/press/unchanged physical state differs')
        errors.extend(cancellation_errors(control, trim, roles['restore'][0], ids))
        return errors
    origin = ev.get('origin', {}); unavailable = case == 'unavailable-origin'
    after = borrowed_snapshot(ids)
    if unavailable:
        after['origin'].update(container='unavailable', worn=False)
        for item in after['items']:
            if item['id'] == ids['bag']['id']: item['container'] = 'unavailable'
        after['worn'] = [item for item in after['worn'] if item['id'] != ids['bag']['id']]
    if (control.get('source') != 'authority.ChangeOrigin' or control.get('input') != 'authority-command'
            or control.get('requestedAt') != control['at'] or control.get('acceptedAt') != origin.get('at') or origin.get('authority') is not True
            or origin.get('case') != case or origin.get('kind') != ('unavailable' if unavailable else 'full')
            or origin.get('requestedAt') != control['requestedAt'] or not number(origin.get('at'))
            or origin.get('bagId') != ids['bag']['id'] or origin.get('itemId') != ids['items']['razor']['id']
            or origin.get('itemType') != 'Base.Razor' or origin.get('before') != control['before'] or origin.get('after') != after
            or not number(origin.get('capacityBefore')) or origin['capacityBefore'] <= 0
            or origin.get('roomBefore') is not True or type(origin.get('roomAfter')) is not bool
            or origin.get('capacityAfter') != (origin['capacityBefore'] if unavailable else 0)
            or not unavailable and origin.get('roomAfter') is not False):
        errors.append('Independent authority origin intervention identity/capacity/availability differs')
    replica = ev.get('originReplica')
    if kind == 'mp' and not unavailable:
        if (type(replica) is not dict or replica.get('source') != 'authority-confirmed-capacity'
                or replica.get('case') != case or not number(replica.get('at')) or not control['at'] <= replica['at'] <= tail['startedAt']
                or replica.get('authorityAt') != origin['at'] or replica.get('requestedAt') != control['requestedAt']
                or replica.get('bagId') != ids['bag']['id'] or replica.get('itemId') != ids['items']['razor']['id']
                or not number(replica.get('capacityBefore')) or replica['capacityBefore'] <= 0 or replica.get('roomBefore') is not True
                or replica.get('capacityAfter') != 0 or replica.get('roomAfter') is not False
                or action_key(replica.get('trimRef')) != action_key(trim['actionRef']) or replica.get('trimNative') != trim['nativeRef']
                or not number(replica.get('trimDelta')) or not 0 < replica['trimDelta'] < 1
                or replica.get('before') != control['before'] or replica.get('after') != control['before'] or replica.get('unchanged') is not True):
            errors.append('Host origin capacity replica lacks exact authority-confirmed active trim/unchanged physical state')
    elif replica is not None:
        errors.append('Unrequested origin capacity replica intervention')
    blocked = ev.get('blocked', {}); debts = blocked.get('debts')
    debt_errors = blocked_debt_errors(debts, ids)
    if debt_errors: return errors + debt_errors
    if (not number(blocked.get('at')) or not control['at'] <= blocked['at']
            or blocked.get('tailRef') != tail['actionRef'] or type(blocked.get('tailStarted')) is not bool
            or type(blocked.get('tailProgress')) is not bool):
        errors.append('Exact blocked debt observation/independent tail identity missing')
    ui = blocked.get('ui', {})
    if (ui.get('source') != 'ActionQueuePanel.KeepReturn' or ui.get('visible') is not True
            or ui.get('id') != debts[0]['id'] or ui.get('itemId') != ids['items']['razor']['id']):
        errors.append('Real footer does not display the exact blocked razor debt')
    if unavailable and 'returnAttempt' in blocked:
        errors.append('Unavailable origin unexpectedly constructed a native return')
    errors.extend(reader_snapshot_errors(blocked.get('snapshot', {}), ids))
    if case != 'keep-return':
        if ev.get('debts') != debts or 'keep' in ev:
            errors.append('Unpaid origin failure debt was silently retired')
    else:
        keep = ev.get('keep', {})
        if (keep.get('source') != 'ActionQueuePanel.KeepReturn' or keep.get('input') != 'programmatic-press-callback'
                or not number(keep.get('at')) or not blocked['at'] <= keep['at']
                or keep.get('id') != debts[0]['id'] or keep.get('itemId') != ids['items']['razor']['id']
                or keep.get('tailRef') != tail['actionRef'] or ev.get('debts') != []
                or keep.get('before') != keep.get('after')
                or any(keep.get(key) is not True for key in ('visible', 'tailStarted', 'tailProgress', 'queueActive',
                                                           'pressCaptured', 'cleared', 'sameSnapshot', 'accepted'))):
            errors.append('Real footer Keep lacks exact debt/active reader or changed physical state')
        errors.extend(reader_snapshot_errors(keep.get('before', {}), ids))
    return errors


def cancellation_errors(control, trim, restore, ids):
    stop = control.get('nativeStop', {}); before, after = stop.get('before', {}), stop.get('after', {})
    errors = []
    for member, present in ((before, True), (after, False)):
        if (not number(member.get('at')) or action_key(member.get('actionRef')) != action_key(trim['actionRef'])
                or member.get('nativeRef') != trim['nativeRef'] or member.get('member') is not present
                or member.get('current') is not present or member.get('beard') != ids['initialBeard']
                or any(member.get(key) is not True for key in ('actionSame', 'nativeSame', 'actorSame', 'queueSame', 'rootSame'))):
            errors.append('Canceled trim lacks exact native episode membership transition')
    if (not number(before.get('at')) or not number(after.get('at'))
            or not trim['startedAt'] <= before['at'] <= control['at'] <= after['at'] <= restore['admittedAt']
            or after.get('boundary') not in ('after-release', 'poll', 'before-next-admission')
            or after.get('snapshot') != control['before']):
        errors.append('Canceled native trim disappeared outside exact UI stop/cleanup boundary or changed appearance')
    return errors


def denied_duration(value, reason, kind):
    # A zero-capacity SP native constructor computes NaN before admission.
    # Preserve the JSON diagnostic; it grants neither progress nor completion.
    if kind == 'sp' and reason == 'admission' and value == {'__queueNonfiniteNumber': 'nan'}:
        return True
    return number(value) and (value == -1 if kind == 'mp' else value > 1)


def denied_return_errors(action, ev, ids, kind):
    attempt = ev.get('blocked', {}).get('returnAttempt', {}); errors = []
    physical = attempt.get('physical', {}); reason = attempt.get('reason')
    allowed = ('admission', 'server') if kind == 'mp' else ('admission', 'unmoved')
    if (action.get('itemId') != ids['items']['razor']['id'] or attempt.get('itemId') != ids['items']['razor']['id']
            or attempt.get('actionRef') != action['actionRef'] or not number(attempt.get('at'))
            or attempt.get('allocated') is not True or type(attempt.get('nativeRef')) is not str
            or attempt.get('nativeRef') in ('', 'nil') or attempt.get('queued') is not False
            or reason not in allowed or reason != ev['blocked']['debts'][0]['reason']
            or action.get('ack') != [] or not isinstance(action.get('operationRef'), str)
            or 'nativeRef' in action and action['nativeRef'] != attempt.get('nativeRef')):
        errors.append('Native return denial lacks exact allocated attempt/debt')
    errors.extend(physical_transfer_errors(physical, ids, 'returned', kind == 'sp'))
    if physical.get('sourceCount') != 1 or physical.get('destinationCount') != 0:
        errors.append('Denied native return changed physical inventory')
    if reason == 'admission':
        if (attempt.get('started') is not False or attempt.get('progress') is not False
                or action.get('started') is not False or action.get('progress') is not False
                or action.get('events') != [] or any(key in action for key in ('startedAt',))
                or 'effectiveDuration' in action and not number(action['effectiveDuration'])):
            errors.append('Unstarted admission denial invented native progress/completion')
        samples = action.get('transfers')
        if type(samples) is not list:
            return errors + ['Unstarted native admission observations malformed']
        for sample in samples:
            current = sample.get('physical', {})
            errors.extend(physical_transfer_errors(current, ids, 'returned', kind == 'sp'))
            if (sample.get('boundary') != 'poll' or sample.get('transaction') != 0
                    or sample.get('done') is not False or sample.get('rejected') is not False or sample.get('duration') is not False
                    or sample.get('nativeRef') != attempt.get('nativeRef') or not number(sample.get('at'))
                    or sample['at'] > attempt['at'] or current.get('sourceCount') != 1 or current.get('destinationCount') != 0
                    or sample.get('itemState') not in ('original', 'canonical-replica')
                    or operation_key(sample.get('operationRef')) != operation_key(action.get('operationRef'))
                    or any(sample.get(key) is not True for key in ('itemExact', 'nativeSame', 'actorSame', 'operationSame',
                                                                 'sourceSame', 'destinationSame', 'queueSame', 'rootSame'))):
                errors.append('Unstarted native return observation invented transaction/progress or changed identity')
        return errors
    events = action.get('events', [])
    phases = ('stop',) if reason == 'server' else ('perform', 'complete')
    if ([(event.get('boundary'), event.get('phase')) for event in events]
            != [(boundary, phase) for phase in phases for boundary in ('begin', 'finish')]
            or any(not number(event.get('at')) or event.get('nativeRef') != attempt.get('nativeRef')
                   or event.get('boundary') == 'finish' and event.get('succeeded') is not True for event in events)):
        errors.append('Denied return exact native terminal lifecycle differs')
    samples = action.get('transfers', []); transactions = set(); rejected = False
    if type(samples) is not list or not samples:
        return errors + ['Denied started return lacks exact native inventory observations']
    for sample in samples:
        current = sample.get('physical', {}); tx = sample.get('transaction')
        errors.extend(physical_transfer_errors(current, ids, 'returned', kind == 'sp'))
        if (current.get('sourceCount') != 1 or current.get('destinationCount') != 0
                or sample.get('nativeRef') != attempt.get('nativeRef')
                or operation_key(sample.get('operationRef')) != operation_key(action.get('operationRef'))
                or sample.get('boundary') not in ('poll', *('begin-' + phase for phase in phases), *('finish-' + phase for phase in phases))
                or not number(sample.get('at')) or sample.get('itemExact') is not True
                or sample.get('itemState') not in ('original', 'canonical-replica')
                or any(sample.get(key) is not True for key in ('nativeSame', 'actorSame', 'operationSame', 'sourceSame', 'destinationSame', 'queueSame', 'rootSame'))
                or type(tx) is not int or reason == 'server' and sample.get('done') is True):
            errors.append('Denied native inventory transaction identity/effect differs')
        if type(tx) is int and tx != 0: transactions.add(tx)
        rejected = rejected or type(tx) is int and tx != 0 and sample.get('rejected') is True
    if reason == 'server' and (len(transactions) != 1 or not rejected):
        errors.append('Host return lacks single exact rejected inventory transaction')
    return errors


def lifecycle_errors(action, kind, canceled=False):
    role = action['role']; events = action.get('events', []); errors = []
    # Grooming uses its unchanged native stop directly, outside runStop observers.
    phases = () if canceled else ('perform', 'complete') if kind == 'sp' else ('perform',)
    expected_events = [(boundary, phase) for phase in phases for boundary in ('begin', 'finish')]
    if ([(event.get('boundary'), event.get('phase')) for event in events] != expected_events
            or any(not number(event.get('at')) or event.get('nativeRef') != action['nativeRef']
                   or event['boundary'] == 'finish' and event.get('succeeded') is not True for event in events)
            or [event['at'] for event in events] != sorted(event['at'] for event in events)):
        errors.append('Unchanged native completion lifecycle differs: ' + role)
    if kind == 'mp' and role not in ('pickup', 'returned', 'heavyPickup'):
        terminal = [ack for ack in action.get('ack', []) if ack.get('state') in ('completed', 'canceled', 'rejected')]
        if (len(terminal) != 1 or terminal[0]['state'] != ('canceled' if canceled else 'completed')
                or terminal[0].get('kind') != action['type'] or type(terminal[0].get('transaction')) is not int
                or not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', str(terminal[0].get('token')))
                or any(terminal[0].get(key) is not True for key in ('nativeSame', 'actorSame', 'queueSame', 'rootSame', 'itemSame', 'operationSame'))
                or terminal[0].get('nativeRef') != action['nativeRef']
                or operation_key(terminal[0].get('operationRef')) != operation_key(action['operationRef'])):
            errors.append('Host exact native terminal ACK differs: ' + role)
    return errors



def preparation_boundary_errors(ev, roles, ids, kind):
    boundary = ev.get('preparationBoundary')
    if ids['case'] not in PREPARATION_BOUNDARY_CASES:
        return [] if boundary is None else ['Unexpected native preparation boundary']
    try:
        prepared, trim = roles['preparationEquip'][0], roles['trim'][0]
        wanted = borrowed_snapshot(ids)
        if (type(boundary) is not dict or boundary.get('actionRef') != prepared['actionRef']
                or boundary.get('nativeRef') != prepared['nativeRef'] or boundary.get('groomingRef') != trim['actionRef']
                or boundary.get('groomingNative') != trim['nativeRef'] or boundary.get('snapshot') != wanted
                or not number(boundary.get('at')) or not prepared['startedAt'] <= trim['startedAt'] <= boundary['at']
                or not number(boundary.get('groomingDelta')) or not 0 < boundary['groomingDelta'] < 1):
            return ['Native preparation physical hands during grooming differ']
        # Host terminal identity/result is required, but packet arrival may trail grooming admission.
        return equip_mode_errors(prepared, ids) + lifecycle_errors(prepared, kind)
    except (KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
        return ['Native preparation hand boundary differs: ' + str(error)]


def restore_boundary_errors(ev, roles, ids, kind):
    boundary = ev.get('restoreBoundary')
    if ids['case'] not in RESTORE_BOUNDARY_CASES:
        return [] if boundary is None else ['Unexpected native restore boundary']
    try:
        restore, returned = roles['restore'][0], roles['returned'][0]
        wanted = expected(ids, kind == 'sp'); wanted.pop('authority')
        wanted['origin']['sourceCount'] = 0
        for item in wanted['items']:
            if item['id'] == ids['items']['razor']['id']: item['container'] = 'root'
        wanted['tail']['pages'] = wanted['tail']['characterPages'] = ids['items']['tail']['initial']
        terminals = ([event for event in restore['events'] if event.get('boundary') == 'finish' and event.get('phase') == 'complete']
                     if kind == 'sp' else [ack for ack in restore['ack'] if ack.get('state') == 'completed'])
        if (type(boundary) is not dict or boundary.get('actionRef') != restore['actionRef']
                or boundary.get('nativeRef') != restore['nativeRef'] or boundary.get('returnRef') != returned['actionRef']
                or boundary.get('snapshot') != wanted or not number(boundary.get('at'))
                or any(type(boundary['snapshot'].get(slot)) is not type(wanted[slot]) for slot in ('primary', 'secondary'))
                or not number(returned.get('admittedAt')) or not number(restore.get('startedAt'))
                or not restore['startedAt'] <= returned['admittedAt'] <= boundary['at'] <= returned['startedAt']
                or len(terminals) != 1 or not number(terminals[0].get('at'))
                or not restore['startedAt'] <= terminals[0]['at'] <= returned['admittedAt']):
            raise ValueError('native completion and exact hand effect must precede return admission')
        return equip_mode_errors(restore, ids)
    except (KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
        return ['Native hand restore boundary differs: ' + str(error)]


def editor_errors(ev, selection):
    """Additional editor-off receipts; all existing native/physical gates still apply."""
    samples = ev.get('editor')
    if selection.get('options', {}).get('queue_editor_enabled', True):
        return [] if samples is None else ['Unexpected editor-off observations in enabled baseline']
    try:
        actions = ev['actions']
        admitted = {action_key(action['actionRef']): action for action in actions if 'admittedAt' in action}
        if len(admitted) != sum('admittedAt' in action for action in actions):
            raise ValueError('duplicate native action identity')
        if any(action_key(action['actionRef']) not in admitted for action in actions if action['role'] not in ('command', 'approach')):
            raise ValueError('native action admission missing')
        if type(samples) is not list or len(samples) != len(admitted) + 2:
            raise ValueError('editor boundaries missing/duplicated')
        before, after = samples[0], samples[-1]
        if (before.get('boundary') != 'before-producer' or after.get('boundary') != 'after-completion'
                or before.get('actionRef') is not False or after.get('actionRef') is not False
                or before.get('ticks') != 0 or type(after.get('ticks')) is not int or after['ticks'] <= 0):
            raise ValueError('editor producer/completion boundaries differ')
        observed = samples[1:-1]
        if (any(sample.get('boundary') != 'native-admission' for sample in observed)
                or {action_key(sample.get('actionRef')) for sample in observed} != set(admitted)):
            raise ValueError('editor native action identities differ')
        for sample in samples:
            if (sample.get('option') is not False or sample.get('setting') is not False
                    or not number(sample.get('at')) or type(sample.get('ticks')) is not int or sample['ticks'] < 0):
                raise ValueError('editor option/setting observation differs')
        if (list(sample['at'] for sample in samples) != sorted(sample['at'] for sample in samples)
                or list(sample['ticks'] for sample in samples) != sorted(sample['ticks'] for sample in samples)):
            raise ValueError('editor observation order differs')
        for sample in observed:
            action = admitted[action_key(sample['actionRef'])]
            if (not number(action['admittedAt']) or not before['at'] <= action['admittedAt'] <= sample['at']
                    or action['role'] not in ('command', 'approach') and not sample['at'] <= action['startedAt'] <= after['at']):
                raise ValueError('editor observation escaped native admission/completion')
        if any(event['at'] > after['at'] for action in actions for event in action.get('events', [])):
            raise ValueError('editor completion preceded native lifecycle completion')
    except (KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
        return ['Editor-off native evidence differs: ' + str(error)]
    return []


def hand_restore_lifecycle_errors(action):
    errors = lifecycle_errors(dict(action, events=[]), 'mp', True)
    events = action.get('events', [])
    if ([(event.get('boundary'), event.get('phase')) for event in events] not in ([], [('begin', 'stop'), ('finish', 'stop')])
            or any(event.get('nativeRef') != action['nativeRef'] or not number(event.get('at'))
                   or event.get('boundary') == 'finish' and event.get('succeeded') is not True for event in events)):
        errors.append('Stopped hand restoration replayed native effects or changed callback identity')
    return errors


def hand_authority_errors(ev, roles, ids):
    try:
        samples = ev['handAuthority']; stop = ev['handStop']; restore = roles['restore'][0]; tail = roles['tail'][0]
        if [row['phase'] for row in samples] != ['pending', 'kept', 'held', 'released', 'duplicate', 'finished']:
            raise ValueError('pending/Keep/late receipt/duplicate sequence differs')
        pending, kept, held, released, duplicate, finished = samples
        started = [ack for ack in restore['ack'] if ack['state'] == 'started']
        terminal = [ack for ack in restore['ack'] if ack['state'] == 'canceled']
        if len(started) != 1 or len(terminal) != 1:
            raise ValueError('exact stopped native Started/terminal missing')
        ack = started[0]
        # The online actor is carried in the intercepted packet fingerprint; all
        # other fields bind back to the sealed Started captured before forceStop.
        parts = pending['signature'].split('|')
        if (len(parts) != 6 or parts[0] != '1' or not re.fullmatch(r'-?\d+', parts[1])
                or int(parts[1]) != stop['player'] or parts[2:] != list(map(str, (stop['transaction'], 'ISEquipWeaponAction', stop['token'], 'canceled')))
                or stop['transaction'] != ack['transaction'] or stop['kind'] != ack['kind'] or stop['token'] != ack['token']
                or stop['actionRef'] != restore['actionRef'] or stop['nativeRef'] != restore['nativeRef']
                or not ack['at'] <= stop['at'] <= pending['at'] <= kept['at'] <= held['at'] <= released['at'] <= duplicate['at'] <= finished['at']
                or not 1000 <= released['at'] - kept['at'] < 30000):
            raise ValueError('native stop or late exact packet identity/deadline differs')
        if (any(row['actionRef'] != restore['actionRef'] or row['nativeRef'] != restore['nativeRef']
                or row['signature'] != pending['signature'] or row['packetRef'] != pending['packetRef']
                or row['nativeAbsent'] is not True for row in samples)
                or not pending['packetRef'] or not restore['startedAt'] <= stop['at'] <= tail['startedAt']):
            raise ValueError('retained genuine packet/native episode changed')
        before = expected(ids, False); before.pop('authority')
        before['tail']['pages'] = before['tail']['characterPages'] = ids['items']['tail']['initial']
        for row in (pending, kept, held):
            if (any(row.get(key) is not True for key in ('current', 'head', 'waiting', 'tailUnallocated'))
                    or row.get('tailStarted') is not False or row.get('tailProgress') is not False
                    or row['ack'] != 'started' or row['snapshot'] != before or row['tailPages'] != ids['items']['tail']['initial']):
                raise ValueError('Keep or elapsed time waived hand authority/advanced independent reader')
        debts = pending['debts']; final = expected(ids, False); final.pop('authority')
        keep = kept.get('keep', {})
        if (keep.get('source') != 'ActionQueuePanel.KeepReturn' or keep.get('id') != debts[0]['id']
                or any(keep.get(key) is not True for key in ('visible', 'pressCaptured', 'accepted'))):
            raise ValueError('actual Keep footer did not retire exact location debt')
        if (len(debts) != 1 or debts[0].get('itemId') != ids['items']['razor']['id'] or debts[0].get('state') != 'blocked'
                or any(row['debts'] != [] for row in samples[1:]) or ev['debts'] != []
                or any(row['ack'] != 'canceled' for row in samples[3:])
                or not released['at'] <= tail['admittedAt'] <= tail['startedAt'] <= finished['at']
                or finished['current'] or finished['waiting'] or finished['snapshot'] != final):
            raise ValueError('late receipt/duplicate did not resume independent tail exactly once')
    except (KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
        return ['Delayed hand authority evidence differs: ' + str(error)]
    return []


def intent_errors(ev, roles, ids):
    errors = []
    try:
        intent = ev.get('intent', {}); explicit = roles['explicitEquip'][0]
        trim, tail = roles['trim'][0], roles['tail'][0]
        token = operation_key(trim['operationRef']); debts = ev.get('debts')
        snapshot = intent.get('snapshot', {})
        during = borrowed_snapshot(ids)
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
    except (KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
        errors.append('Malformed newer native intent: ' + str(error))
    return errors


def check_case(row, selection, prepared, verified):
    if row.get('id') in BELT_CASES:
        return check_belt_case(row, selection, prepared, verified)
    errors = []
    try:
        case = row['id']; ids = row['ids']; ev = row['evidence']; delayed = ids.get('handAckDelay') is True
        returned_case = case in RETURNED_CASES and not delayed
        intent_case = case in INTENT_CASES; canceled = case == 'cancel-active'
        if (ids != prepared or ids['case'] != case or row.get('status') != 'passed' or row.get('actor') != 'client1'
                or row.get('kind') != selection['kind'] or row.get('mode') != 'toolkit'):
            raise ValueError('exact native case/process identity differs')
        validate_prepared(ids, selection)
        placement.validate(row['clientPlacement'], ids['placement'], 'local', centered=True)
        authority_snapshot = dict(verified); authority_snapshot.pop('transfers', None); authority_snapshot.pop('heavyTransitions', None)
        errors.extend(authority_transfer_errors(verified, ids))
        if (row.get('server') != verified or authority_snapshot != expected(ids, True)
                or row.get('client') != expected(ids, selection['kind'] == 'sp') or ev.get('after') != row['client']
                or ev.get('before') != ids['baseline']):
            errors.append('Independent authority/client exact inventory, hands, appearance or reader effects differ')
        if any(ev.get(key) != value for key, value in {'producer': grooming(case)[0], 'target': grooming(case)[2],
                'installed': True, 'explicitRequested': intent_case, 'nativeCallbacksUntouched': True, 'queueIdle': True}.items()):
            errors.append('Real install/menu producer or native callback integrity differs')
        errors.extend(editor_errors(ev, selection))
        errors.extend(heavy_errors(ev, verified, ids, selection['kind']))
        actions = ev['actions']; roles = {}
        for action in actions:
            roles.setdefault(action['role'], []).append(action)
        required = {'pickup', 'preparationEquip', 'trim', 'tail', 'command'}
        required.update({'explicitEquip'} if intent_case else set() if case == UNAVAILABLE_HEAVY else {'restore'})
        if case == 'heavy-stone-anvil': required.add('heavyPickup')
        if not delayed and (case in RETURNED_CASES or case in ('full-origin', 'keep-return')): required.add('returned')
        if 'approach' in roles: required.add('approach')
        command_count = len(roles.get('command', []))
        if (set(roles) != required or command_count != (1 if intent_case or case == UNAVAILABLE_HEAVY else 2)
                or any(len(values) != 1 for role, values in roles.items() if role != 'command')):
            raise ValueError('Native producer/cleanup action topology differs')
        refs = [action['actionRef'] for action in actions]
        if any(type(ref) is not str or not ref for ref in refs) or len(set(refs)) != len(refs):
            raise ValueError('Action identity duplicated/missing')
        errors.extend(producer_errors(ev, roles, ids))
        errors.extend(hand_seed_errors(ev.get('handSeed'), ids))
        for role, values in roles.items():
            for action in values:
                if action.get('type') != (grooming(case)[1] if role == 'trim' else 'ISUnequipAction' if case == 'empty-primary' and role == 'restore' else ACTION_TYPES[role]):
                    raise ValueError('Action native class differs: ' + role)
                if role in ('command', 'approach'):
                    continue
                errors.extend(equip_mode_errors(action, ids))
                if role == 'returned' and case in ('full-origin', 'keep-return'):
                    errors.extend(denied_return_errors(action, ev, ids, selection['kind']))
                    duration = action.get('constructorDuration')
                    if not denied_duration(duration, ev['blocked']['returnAttempt']['reason'], selection['kind']):
                        errors.append('Denied return original native constructor duration differs')
                    continue
                if role == 'trim' and case == 'cut-hair-scissors' and (action.get('hairStyle') != ids['targetHair'] or action.get('constructorDuration') != 300):
                    errors.append('Native haircut hairStyle/ordinary duration differs')
                item = 'previous' if role == 'heavyPickup' or role == 'restore' and case != 'empty-primary' else 'replacement' if role == 'explicitEquip' else 'tail' if role == 'tail' else 'razor'
                if (action.get('itemId') != ids['items'][item]['id'] or any(action.get(key) is not True for key in ('allocated', 'started', 'progress'))
                        or not number(action.get('startedAt')) or not number(action.get('effectiveDuration')) or action['effectiveDuration'] <= 1
                        or not isinstance(action.get('nativeRef'), str) or not isinstance(action.get('operationRef'), str)):
                    errors.append('Native duration/allocation/progress missing: ' + role)
                duration = action.get('constructorDuration')
                if case == 'empty-primary' and role == 'restore' and duration != 50:
                    errors.append('Empty-primary restore does not use ordinary native unequip duration')
                if not number(duration) or (duration != -1 if selection['kind'] == 'mp' and role in ('pickup', 'returned', 'heavyPickup') else duration <= 1):
                    errors.append('Original native constructor duration differs: ' + role)
                if delayed and role == 'restore':
                    errors.extend(hand_restore_lifecycle_errors(action))
                else:
                    errors.extend(lifecycle_errors(action, selection['kind'], case == 'cancel-active' and role == 'trim'))
                if role in ('pickup', 'returned', 'heavyPickup'):
                    errors.extend(transfer_errors(action, ids, selection['kind']))
        get = lambda name: roles[name][0]
        pickup, equip, trim, tail = (get(name) for name in ('pickup', 'preparationEquip', 'trim', 'tail'))
        if not pickup['startedAt'] <= equip['startedAt'] <= trim['startedAt'] <= tail['startedAt']:
            errors.append('Native borrow/equip/trim/independent reader ordering differs')
        token = operation_key(trim['operationRef'])
        if (any(operation_key(get(name)['operationRef']) != token for name in ('pickup', 'preparationEquip'))
                or operation_key(tail['operationRef']) == token):
            errors.append('Native borrowing chain or independent operation ownership differs')
        transitions = [action for action in actions if 'operationTransition' in action or 'originalOperationRef' in action]
        if canceled:
            command = get('command'); transition = command.get('operationTransition', {})
            cleanup = operation_key(get('restore')['operationRef'])
            if (transitions != [command] or operation_key(command.get('originalOperationRef')) != token
                    or operation_key(command['operationRef']) != cleanup or cleanup in (token, operation_key(tail['operationRef']))
                    or not number(transition.get('at')) or not ev['control']['at'] <= transition['at'] <= get('restore')['startedAt']
                    or operation_key(transition.get('from')) != token or operation_key(transition.get('to')) != operation_key(command['operationRef'])
                    or transition.get('preallocation') is not True or transition.get('sameAction') is not True
                    or any(operation_key(action['operationRef']) != cleanup for action in roles['command'])):
                errors.append('Canceled producer cleanup lacks exact single preallocation transition to fresh cleanup token')
        elif transitions:
            errors.append('Unrequested action operation ownership transition')
        debts = ev.get('debts')
        errors.extend(control_errors(ev, roles, ids, selection['kind']))
        if selection['kind'] == 'mp' and (canceled or case in ORIGIN_CASES or case == UNAVAILABLE_HEAVY):
            start = [ack for ack in trim['ack'] if ack['state'] == 'started']
            if len(start) != 1 or start[0]['at'] > (ev['heavyRemoval']['requestedAt'] if case == UNAVAILABLE_HEAVY else ev['control']['at']):
                errors.append('Host control preceded native grooming admission')
        if returned_case:
            if case == 'heavy-stone-anvil':
                heavy = get('heavyPickup')
                if (not trim['startedAt'] <= heavy['startedAt'] <= get('restore')['startedAt']
                        or operation_key(heavy['operationRef']) != token):
                    errors.append('Heavy pickup escaped native cleanup order/operation')
            restore, returned = get('restore'), get('returned')
            if (not trim['startedAt'] <= restore['startedAt'] <= returned['startedAt'] <= tail['startedAt']
                    or canceled and (operation_key(restore['operationRef']) == token or operation_key(returned['operationRef']) != operation_key(restore['operationRef']))
                    or not canceled and any(operation_key(action['operationRef']) != token for action in (restore, returned))
                    or debts != [] or 'intent' in ev):
                errors.append('Ordinary native restore/return effects or debt differ')
        elif delayed:
            errors.extend(hand_authority_errors(ev, roles, ids))
        elif case == UNAVAILABLE_HEAVY:
            if (type(debts) is not list or len(debts) != 1 or debts[0].get('itemId') != ids['items']['razor']['id']
                    or debts[0].get('itemType') != 'Base.Razor' or type(debts[0].get('id')) is not int or debts[0]['id'] <= 0
                    or debts[0].get('state') != 'blocked' or debts[0].get('reason') != 'cleanup-unresolved'):
                errors.append('Unavailable heavy lost exact unresolved borrowed-tool debt')
        elif intent_case:
            errors.extend(intent_errors(ev, roles, ids))
        elif case in ORIGIN_CASES:
            restore = get('restore')
            if (not trim['startedAt'] <= restore['startedAt'] <= tail['startedAt']
                    or operation_key(restore['operationRef']) != token
                    or case != 'unavailable-origin' and operation_key(get('returned')['operationRef']) != token or 'intent' in ev):
                errors.append('Origin failure hand restoration operation/order differs')
        errors.extend(preparation_boundary_errors(ev, roles, ids, selection['kind']))
        errors.extend(restore_boundary_errors(ev, roles, ids, selection['kind']))
        boundary = ev.get('tailBoundary', {})
        at_tail = expected(ids, selection['kind'] == 'sp'); at_tail.pop('authority')
        at_tail['tail']['pages'] = at_tail['tail']['characterPages'] = ids['items']['tail']['initial']
        if intent_case: at_tail['primary'] = ids['items']['razor']['id']
        if (not number(boundary.get('at')) or boundary['at'] > tail['startedAt']
                or boundary.get('snapshot') != at_tail or boundary.get('debts') != (ev['blocked']['debts'] if case == 'keep-return' else debts)):
            errors.append('Independent native reader admission inventory, hands or debt differ')
    except (KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
        errors.append('Malformed razor native evidence: ' + str(error))
    return errors


def belt_seed(ids):
    return dict(tool=dict(id=ids['items']['razor']['id'], slot=ids['beltIndex'], slotType='SmallBeltLeft', model='Belt Left Screwdriver', root=True),
                replacement=dict(id=ids['items']['replacement']['id'], slot=-1, slotType=False, model=False, root=True),
                occupant=ids['items']['razor']['id'], provider=ids['items']['belt']['id'])


def replacement_errors(ev, roles, ids, kind):
    value = ev.get('replacement'); errors = []
    if ids['case'] != 'belt-scissors-replace':
        return [] if value is None else ['Unrequested native belt replacement']
    try:
        trim, tail, detach, attach = (roles[name][0] for name in ('trim', 'tail', 'slotDetach', 'slotAttach'))
        during = borrowed_snapshot(ids)
        if (value.get('source') != 'ISHotbar.attachItem' or value.get('trimRef') != trim['actionRef']
                or value.get('trimNative') != trim['nativeRef'] or value.get('detachRef') != detach['actionRef']
                or value.get('attachRef') != attach['actionRef'] or value.get('before') != during or value.get('after') != during
                or not number(value.get('at')) or not trim['startedAt'] <= value['at'] <= tail['startedAt']
                or not number(value.get('trimDelta')) or not 0 < value['trimDelta'] < 1
                or not tail['startedAt'] <= attach['startedAt']
                or operation_key(attach['operationRef']) == operation_key(trim['operationRef'])):
            errors.append('Newer native slot request lacks exact active trim and queued detach/attach identity')
        if kind == 'mp' and not any(ack.get('state') == 'started' and ack['at'] <= value['at'] for ack in trim['ack']):
            errors.append('Belt replacement preceded genuine Host grooming admission')
    except (KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
        errors.append('Malformed native slot replacement: ' + str(error))
    return errors


def belt_endpoint_errors(value, ids, authority, kind):
    # Preserve the raw observed strings; only the Host authority detached tool
    # has the exact native nil -> zero-length UTF wire transform.
    wanted = expected(ids, authority, authority_wire=authority and kind == 'mp')
    return [] if value == wanted else ['Exact authority/client belt slot, hands, root tool or native effects differ']


def check_belt_case(row, selection, prepared, verified):
    errors = []
    try:
        ids=row['ids']; ev=row['evidence']; case=row['id']; kind=selection['kind']; canceled=case in CANCEL_CASES
        if (ids != prepared or ids['case'] != case or row.get('status') != 'passed' or row.get('actor') != 'client1'
                or row.get('kind') != kind or row.get('mode') != 'toolkit'):
            raise ValueError('belt case identity differs')
        validate_prepared(ids, selection)
        if ids.get('beltConfigured') is not True or type(ids.get('beltIndex')) is not int or not 1 < ids['beltIndex'] < 100: raise ValueError('actual native belt ordering unconfirmed')
        if ids['baseline'].get('belt') != belt_seed(ids): raise ValueError('exact root belt seed differs')
        placement.validate(row['clientPlacement'], ids['placement'], 'local', centered=True)
        authoritative=dict(verified); authoritative.pop('transfers', None); authoritative.pop('heavyTransitions', None)
        if (verified.get('transfers') != [] or verified.get('heavyTransitions') != [] or row.get('server') != verified
                or belt_endpoint_errors(authoritative, ids, True, kind) or belt_endpoint_errors(row.get('client'), ids, kind == 'sp', kind)
                or ev.get('after') != row['client'] or ev.get('before') != ids['baseline']):
            errors.append('Exact authority/client belt slot, hands, root tool or native effects differ')
        if any(ev.get(key) != value for key,value in dict(producer=grooming(case)[0], target='Moustache', installed=True,
                explicitRequested=False, nativeCallbacksUntouched=True, queueIdle=True, debts=[]).items()):
            errors.append('Belt producer, callback integrity, idle or debt differs')
        roles={}
        for action in ev['actions']: roles.setdefault(action['role'], []).append(action)
        required={'preparationEquip','trim','tail','command','restore'}
        if case == 'belt-scissors-replace': required.update(('slotDetach','slotAttach'))
        if set(roles) != required or any(len(value) != 1 for name,value in roles.items()):
            raise ValueError('belt native producer/cleanup topology differs')
        refs=[a['actionRef'] for a in ev['actions']]
        if len(set(refs)) != len(refs): raise ValueError('duplicate native belt action')
        errors.extend(producer_errors(ev, roles, ids)); errors.extend(hand_seed_errors(ev.get('handSeed'), ids))
        get=lambda name: roles[name][0]
        equip,trim,tail,restore=(get(name) for name in ('preparationEquip','trim','tail','restore'))
        for name,kind_name,item in (('preparationEquip','ISEquipWeaponAction','razor'),('trim','ISTrimBeard','razor'),
                ('tail','ISReadABook','tail'),('restore','ISEquipWeaponAction','previous')):
            action=get(name)
            if (action['type'] != kind_name or action.get('itemId') != ids['items'][item]['id']
                    or any(action.get(key) is not True for key in ('allocated','started','progress'))
                    or not number(action.get('effectiveDuration')) or action['effectiveDuration'] <= 1):
                errors.append('Belt native allocation/progress/item differs: '+name)
            errors.extend(lifecycle_errors(action,kind,canceled and name=='trim'))
        if equip.get('fromHotbar') is not True or restore.get('fromHotbar') is not False:
            errors.append('Belt native equip hotbar origin or plain hand restoration differs')
        if not equip['startedAt'] <= trim['startedAt'] <= restore['startedAt'] <= tail['startedAt']:
            errors.append('Belt native grooming/restore/reader ordering differs')
        token=operation_key(trim['operationRef'])
        if operation_key(equip['operationRef']) != token or operation_key(tail['operationRef']) == token:
            errors.append('Belt producer ownership or independent reader token differs')
        if canceled:
            errors.extend(control_errors(ev,roles,ids,kind))
            command=get('command');transition=command.get('operationTransition',{})
            if (operation_key(command.get('originalOperationRef')) != token or not transition.get('sameAction')
                    or not transition.get('preallocation') or operation_key(restore['operationRef']) == token):
                errors.append('Canceled belt cleanup lacks fresh exact preallocation operation')
        elif operation_key(restore['operationRef']) != token:
            errors.append('Belt hand restore escaped producer operation')
        if case=='belt-scissors-replace':
            for name,type_name,item in (('slotDetach','ISDetachItemHotbar','razor'),('slotAttach','ISAttachItemHotbar','replacement')):
                action=get(name)
                if action.get('type') != type_name or action.get('itemId') != ids['items'][item]['id'] or action.get('fromHotbar') is not True:
                    errors.append('Newer belt action exact native item/type differs: '+name)
                if not action.get('events') or not number(action.get('admittedAt')):
                    errors.append('Newer belt action native admission/lifecycle absent: '+name)
            errors.extend(lifecycle_errors(get('slotAttach'),kind))
        errors.extend(replacement_errors(ev,roles,ids,kind))
        boundary=ev.get('tailBoundary',{}); at_tail=expected(ids,kind=='sp');at_tail.pop('authority')
        at_tail['tail']['pages']=at_tail['tail']['characterPages']=ids['items']['tail']['initial']
        at_tail['belt']=belt_seed(ids); at_tail['belt']['occupant']=False
        if boundary.get('snapshot') != at_tail or boundary.get('debts') != []:
            errors.append('Belt independent tail admission state differs')
    except (KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
        errors.append('Malformed native belt evidence: '+str(error))
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
        seed_rows = records(client, PREFIX + 'HAND_SEED ')
        if [value for _, value in seed_rows] != [dict(case=row['id'], observation=row['evidence']['handSeed'])
                                                for _, row in rows if row['id'] in HEAVY_CASES]:
            issues.append('Raw exact heavy capture seed differs from published evidence')
        for position, value in seed_rows:
            index = cases.index(value['case'])
            if not placements[index][0] < position < rows[index][0]:
                issues.append('Heavy capture seed escaped exact case boundaries')
        if selection['kind'] == 'mp' and records(authority, PREFIX + 'HAND_SEED '):
            issues.append('Actor-local heavy capture seed emitted by authority process')
        heavy_rows = records(authority, PREFIX + 'HEAVY_AUTHORITY ')
        if [value for _, value in heavy_rows] != [sample for _, value in verified for sample in value.get('heavyTransitions', [])]:
            issues.append('Raw independent heavy authority transitions differ from published receipt')
        for position, value in heavy_rows:
            index = cases.index(value['case'])
            if not prepared[index][0] < position < verified[index][0]:
                issues.append('Heavy authority transition escaped exact case boundaries')
        removed = records(authority, PREFIX + 'HEAVY_REMOVED ')
        removed_client = records(client, PREFIX + 'HEAVY_REMOVAL_CLIENT ')
        wanted_removed = [row['evidence']['heavyRemoval'] for _, row in rows if 'heavyRemoval' in row['evidence']]
        if [value for _, value in removed] != wanted_removed or [value for _, value in removed_client] != wanted_removed:
            issues.append('Raw authority/client heavy removal differs from exact published case')
        if selection['kind'] == 'mp' and (records(client, PREFIX + 'HEAVY_AUTHORITY ') or records(client, PREFIX + 'HEAVY_REMOVED ')
                or records(authority, PREFIX + 'HEAVY_REMOVAL_CLIENT ')):
            issues.append('Heavy authority evidence emitted by wrong process')
        transfers = records(client, PREFIX + 'TRANSFER '); authority_transfers = records(authority, PREFIX + 'TRANSFER_AUTHORITY ')
        if [value for _, value in authority_transfers] != [sample for _, value in verified for sample in value.get('transfers', [])]:
            issues.append('Independent raw authority transfer transitions differ from published receipt')
        expected_actions = [dict(case=row['id'], action={key: action[key] for key in ACTION_FIELDS if key in action})
                            for _, row in rows for action in row['evidence']['actions']]
        if [value for _, value in action_rows] != expected_actions:
            issues.append('Raw exact native action records differ from published case actions')
        if [value for _, value in intent_rows] != [dict(case=row['id'], observation=row['evidence']['intent']) for _, row in rows if 'intent' in row['evidence']]:
            issues.append('Raw accepted primary intent records differ')
        for marker, field in (('CONTROL', 'control'), ('BLOCKED', 'blocked'), ('KEEP', 'keep'), ('ORIGIN_REPLICA', 'originReplica'), ('RESTORE_BOUNDARY', 'restoreBoundary'), ('PREPARATION_BOUNDARY', 'preparationBoundary'), ('REPLACEMENT', 'replacement')):
            values = records(client, PREFIX + marker + ' ')
            observations = [(row['id'], row['evidence'][field]) for _, row in rows if field in row['evidence']]
            if marker == 'ORIGIN_REPLICA':
                wanted = [observation for _, observation in observations]
            else:
                wanted = [dict(case=case, observation=observation) for case, observation in observations]
            if [value for _, value in values] != wanted:
                issues.append('Raw exact live ' + field + ' observations differ from published case evidence')
            for position, value in values:
                index = cases.index(value['case'])
                if not placements[index][0] < position < rows[index][0]:
                    issues.append('Raw live control escaped its exact case publication boundaries')
        hand_rows = records(client, PREFIX + 'HAND_AUTHORITY ')
        wanted_hand = [dict(case=row['id'], observation=sample) for _, row in rows
                       for sample in row['evidence'].get('handAuthority', [])]
        if [value for _, value in hand_rows] != wanted_hand:
            issues.append('Raw hand authority packet/Keep observations differ from published case')
        for position, value in hand_rows:
            index = cases.index(value['case'])
            if not placements[index][0] < position < rows[index][0]:
                issues.append('Hand authority observation escaped exact case boundaries')
        editor_rows = records(client, PREFIX + 'EDITOR ')
        expected_editor = [dict(case=row['id'], observation=sample)
                           for _, row in rows for sample in row['evidence'].get('editor', [])]
        if [value for _, value in editor_rows] != expected_editor:
            issues.append('Raw editor option/setting observations differ from published exact native boundaries')
        for position, value in editor_rows:
            index = cases.index(value['case'])
            if not placements[index][0] < position < rows[index][0]:
                issues.append('Editor observation escaped exact case boundaries')
        native_cancels = records(client, PREFIX + 'CANCEL_NATIVE ')
        wanted_cancels = [dict(case=row['id'], observation=row['evidence']['control']['nativeStop'])
                          for _, row in rows if row['id'] in CANCEL_CASES]
        if [value for _, value in native_cancels] != wanted_cancels:
            issues.append('Raw exact native canceled trim observation differs from published evidence')
        retokens = records(client, PREFIX + 'RETOKEN ')
        wanted_retokens = [dict(case=row['id'], actionRef=action['actionRef'], observation=action['operationTransition'])
                           for _, row in rows for action in row['evidence']['actions'] if 'operationTransition' in action]
        if [value for _, value in retokens] != wanted_retokens:
            issues.append('Raw exact canceled cleanup retoken differs from published action transition')
        for position, value in retokens:
            index = cases.index(value['case'])
            if not placements[index][0] < position < rows[index][0]:
                issues.append('Canceled cleanup transition escaped exact case boundaries')
        origins = records(authority, PREFIX + 'ORIGIN ')
        client_origins = records(client, PREFIX + 'ORIGIN_CLIENT ')
        wanted_origins = [row['evidence']['origin'] for _, row in rows if 'origin' in row['evidence']]
        if [value for _, value in origins] != wanted_origins or [value for _, value in client_origins] != wanted_origins:
            issues.append('Independent raw authority/client origin intervention observations differ')
        if selection['kind'] == 'mp' and (records(client, PREFIX + 'ORIGIN ') or records(authority, PREFIX + 'ORIGIN_CLIENT ')
                or any(records(authority, PREFIX + marker + ' ') for marker in ('CONTROL', 'BLOCKED', 'KEEP', 'RETOKEN', 'CANCEL_NATIVE', 'ORIGIN_REPLICA', 'EDITOR', 'RESTORE_BOUNDARY', 'PREPARATION_BOUNDARY', 'HAND_AUTHORITY'))):
            issues.append('Live razor control/origin evidence emitted by wrong process')
        for position, value in origins:
            index = cases.index(value['case'])
            if not prepared[index][0] < position < verified[index][0]:
                issues.append('Authority origin intervention escaped prepared/verified boundaries')
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
