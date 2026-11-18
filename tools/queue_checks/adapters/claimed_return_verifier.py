"""Bind claimed-return causality to native actions and physical authority."""
import math
from pathlib import Path
import re

from .. import placement
from ..receipts import decode_object

PREFIX = '[CLAIMED_RETURN] '
TYPES = {'borrowed': 'Base.BookCarpentry1', 'previous': 'Base.BookCooking1', 'tail': 'Base.BookFarming1'}
ACTION_TYPES = {'pickup': 'ISInventoryTransferAction', 'preparationEquip': 'ISEquipWeaponAction',
                'body': 'ISReadABook', 'expansion': 'ISQueueActionsAction', 'restore': 'ISEquipWeaponAction',
                'continuation': 'ISQueueActionsAction', 'returned': 'ISInventoryTransferAction', 'tail': 'ISReadABook'}


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def operation_key(value):
    """Kahlua table identity precedes its mutable diagnostic field rendering."""
    if isinstance(value, str):
        match = re.fullmatch(r'table 0x(0|[1-9][0-9]*)(?:\{[^\r\n]*\})?', value)
        if match and int(match[1]) <= 2147483647:
            return ('native-table', match[1])
    return ('literal', value)


def authenticated_operation_same(left, right, observed):
    # A printed table identity supplements the direct live object comparison;
    # it cannot manufacture that comparison or replace native ACK identity.
    return observed is True and operation_key(left) == operation_key(right)


def records(text, marker):
    result = []
    for match in re.finditer(re.escape(marker) + r'([^\r\n]*)', text):
        result.append((match.start(), decode_object(match[1])))
    return result


def snapshot(row, ids, *, phase, authority=None):
    if not isinstance(row, dict) or row.get('case') != ids['case']:
        return False
    if authority is not None and row.get('authority') is not authority:
        return False
    items = row.get('items')
    if type(items) is not dict or set(items) != set(TYPES) or row.get('secondary') is not False:
        return False
    if row.get('bag') != dict(ids['bag'], canonicalRoot=True, worn=True, sourceSame=True):
        return False
    success = ids['case'] in ('claimed-success', 'claimed-cancel-success')
    initial = phase == 'before'
    returned = phase in ('final', 'tail') and success
    root_borrowed = not initial and not returned
    expected_primary = ids['items']['previous' if initial or phase == 'continuation' or returned else 'borrowed']['id']
    if row.get('primary') != expected_primary:
        return False
    for name, spec in ids['items'].items():
        item = items[name]
        in_root = name != 'borrowed' or root_borrowed
        if (type(item) is not dict or set(item) != {'id', 'type', 'root', 'source', 'pages', 'total'}
                or item['id'] != spec['id'] or item['type'] != spec['type'] or item['total'] != spec['pages']
                or type(item['root']) is not int or item['root'] != int(in_root)
                or type(item['source']) is not int or item['source'] != int(not in_root)
                or type(item['pages']) is not int or not spec['initial'] <= item['pages'] <= spec['pages']):
            return False
        expected_pages = spec['initial'] if initial or name == 'previous' or phase != 'final' and name == 'tail' else spec['pages']
        if name == 'borrowed' and ids['case'].startswith('claimed-cancel') and not initial:
            if item['pages'] >= spec['pages']:
                return False
        else:
            if item['pages'] != expected_pages:
                return False
    return True


def native_events(row, kind, *, completed):
    events = row.get('events')
    if type(events) is not list:
        return False
    if not completed:
        return events == []
    phases = ['perform', 'complete'] if kind == 'sp' else ['perform']
    expected = [(boundary, phase) for phase in phases for boundary in ('begin', 'finish')]
    if [(event.get('boundary'), event.get('phase')) for event in events] != expected:
        return False
    if any(not number(event.get('at')) or event.get('nativeRef') != row.get('nativeRef')
           or event['boundary'] == 'finish' and event.get('succeeded') is not True for event in events):
        return False
    times = [event['at'] for event in events]
    return times == sorted(times) and row['startedAt'] <= times[0]


def check_case(row, selection, prepared, verified):
    errors = []
    case = row.get('id'); success = case in ('claimed-success', 'claimed-cancel-success'); cancelled = str(case).startswith('claimed-cancel')
    ids, evidence = row.get('ids', {}), row.get('evidence', {})
    try:
        if (row.get('status') != 'passed' or row.get('actor') != 'client1' or row.get('kind') != selection['kind']
                or row.get('mode') != 'toolkit' or ids != prepared or ids.get('case') != case):
            errors.append('Exact case identity or prepared authority differs')
        specs = ids['items']
        if type(specs) is not dict or set(specs) != set(TYPES):
            raise ValueError('prepared item names')
        for name, spec in specs.items():
            if (set(spec) != {'id', 'type', 'pages', 'initial'} or spec['type'] != TYPES[name]
                    or any(type(spec[key]) is not int for key in ('id', 'pages', 'initial'))
                    or spec['id'] < 0 or spec['initial'] <= 0 or spec['pages'] - spec['initial'] != 4):
                raise ValueError('prepared exact item ' + name)
        if len({spec['id'] for spec in specs.values()}) != len(specs):
            raise ValueError('prepared item identity collision')
        origin = ids['placement']
        placement.validate(row['clientPlacement'], origin, 'local', centered=True)
        placement.validate(ids['placementProof'], origin, 'replica' if selection['kind'] == 'mp' else 'local', centered=True)
        bag = ids['bag']
        if (set(bag) != {'id', 'type'} or type(bag['id']) is not int or bag['id'] < 0
                or bag['id'] in {spec['id'] for spec in specs.values()} or bag['type'] != 'Base.Bag_Military'):
            errors.append('Borrowed source is not the exact prepared carried bag')
        if not snapshot(evidence.get('before'), ids, phase='before'):
            errors.append('Initial native producer snapshot differs')
        if (row.get('server') != verified or evidence.get('after') != row.get('client')
                or not snapshot(verified, ids, phase='final', authority=True)
                or not snapshot(row.get('client'), ids, phase='final', authority=selection['kind'] == 'sp')):
            errors.append('Exact authority/client inventory, hands or paid pages differ')
        if any(evidence.get(key) is not value for key, value in {
                'claimAccepted': True, 'originalReturnAllocated': False, 'returnAllocated': success,
                'cancelAccepted': cancelled, 'freshOperation': cancelled, 'stopRequested': not success,
                'queueIdle': True, 'nativeCallbacksUntouched': True,
                'loanEarnedAtExpansion': True}.items()) or evidence.get('returnCalls') != int(success):
            errors.append('Claimed expansion, fresh cancellation ownership or dependent return outcome differs')
        if not number(evidence.get('expandedAt')):
            errors.append('Genuine cleanup expansion boundary missing')
        if not snapshot(evidence.get('expansionSnapshot'), ids, phase='expanded'):
            errors.append('Claimed expansion did not preserve the exact paid carried loan')
        debts = evidence.get('debts')
        if success:
            if debts != []:
                errors.append('Successful native restore left a blocked debt')
        elif (type(debts) is not list or len(debts) != 1 or debts[0].get('itemId') != specs['borrowed']['id']
              or debts[0].get('itemType') != specs['borrowed']['type'] or debts[0].get('reason') != 'cleanup-outcome'
              or debts[0].get('state') != 'blocked'):
            errors.append('Stopped native restore did not preserve the exact blocked loan')
        names = set(ACTION_TYPES) - (set() if success else {'returned'})
        if {name for name in ACTION_TYPES if name in evidence} != names:
            errors.append('Missing or unexpected native continuation/return action')
        native_names = ('pickup', 'preparationEquip', 'body', 'restore', 'tail') + (('returned',) if success else ())
        refs = []
        for name in names:
            action = evidence[name]
            if action.get('type') != ACTION_TYPES[name] or not isinstance(action.get('actionRef'), str) or not action['actionRef']:
                raise ValueError('exact action identity ' + name)
            refs.append(action['actionRef'])
        if len(set(refs)) != len(refs) or evidence.get('originalReturnRef') in refs:
            errors.append('Native original, cleanup and independent action identities overlap')
        for name in native_names:
            action = evidence[name]
            if (any(action.get(key) is not True for key in ('started', 'progress', 'nativeStarted'))
                    or not number(action.get('startedAt')) or not isinstance(action.get('nativeRef'), str)
                    or not isinstance(action.get('operationRef'), str)):
                errors.append('Native allocation/progress evidence missing: ' + name)
                continue
            item_name = 'previous' if name == 'restore' else 'tail' if name == 'tail' else 'borrowed'
            transfer = action['type'] == 'ISInventoryTransferAction' and selection['kind'] == 'mp'
            if (action.get('allocated') is not True or action.get('itemId') != specs[item_name]['id']
                    or not number(action.get('duration')) or (action['duration'] != -1 if transfer else action['duration'] <= 1)
                    or not number(action.get('effectiveDuration')) or action['effectiveDuration'] <= 1):
                errors.append('Native exact item/duration allocation differs: ' + name)
            completed = not (name == 'restore' and not success or name == 'body' and cancelled)
            if not native_events(action, selection['kind'], completed=completed):
                errors.append('Untouched native lifecycle evidence differs: ' + name)
        pickup, equip, body, restore, tail = (evidence[name] for name in ('pickup', 'preparationEquip', 'body', 'restore', 'tail'))
        if (not pickup['startedAt'] <= equip['startedAt'] <= body['startedAt'] <= evidence['expandedAt'] <= restore['startedAt'] <= tail['startedAt']
                or operation_key(pickup['operationRef']) != operation_key(body['operationRef']) or operation_key(equip['operationRef']) != operation_key(body['operationRef'])
                or (operation_key(restore['operationRef']) != operation_key(body['operationRef'])) is not cancelled
                or operation_key(tail['operationRef']) in (operation_key(body['operationRef']), operation_key(restore['operationRef']))):
            errors.append('Borrowing, cleanup and independent-tail causal ownership differs')
        continuation = evidence['continuation']
        if success:
            returned = evidence['returned']
            if (not snapshot(evidence.get('continuationSnapshot'), ids, phase='continuation')
                    or evidence.get('restoreEffectEarned') is not True
                    or not number(evidence.get('continuationAt'))
                    or not restore['startedAt'] <= evidence['continuationAt'] <= returned['startedAt'] <= tail['startedAt']
                    or operation_key(returned['operationRef']) != operation_key(restore['operationRef'])):
                errors.append('Return was not enrolled after the exact successful native hand effect')
        else:
            if (not snapshot(evidence.get('beforeStop'), ids, phase='expanded')
                    or not number(evidence.get('stopRequestedAt'))
                    or not restore['startedAt'] <= evidence['stopRequestedAt'] <= tail['startedAt']
                    or continuation.get('started') is not False or continuation.get('events') != []
                    or continuation.get('progress') is not False or continuation.get('allocated') is not False
                    or any(key in evidence for key in ('continuationAt', 'continuationSnapshot'))):
                errors.append('Real progressed native stop failed to fence the unissued continuation')
        if cancelled and (not number(evidence.get('cancelRequestedAt'))
                          or not body['startedAt'] <= evidence['cancelRequestedAt'] <= evidence['expandedAt']):
            errors.append('Public cancellation did not precede fresh cleanup expansion')
        boundary = evidence.get('tailBoundary', {})
        if (not number(boundary.get('at')) or boundary['at'] > tail['startedAt']
                or boundary.get('restoreNativeRemoved') is not True
                or boundary.get('restoreRef') != restore['nativeRef'] or boundary.get('tailActionRef') != tail['actionRef']
                or boundary.get('tailRef') != tail['nativeRef'] or boundary.get('tailAllocated') is not True
                or not number(boundary.get('tailAllocatedAt'))
                or not boundary['at'] <= boundary['tailAllocatedAt'] <= tail['startedAt']
                or selection['kind'] == 'mp' and boundary.get('restoreAck') != ('completed' if success else 'canceled')
                or not snapshot(boundary.get('snapshot'), ids, phase='tail')):
            errors.append('Independent native tail preceded the exact restore terminal/removal boundary')
        pending = evidence.get('pendingAuthority')
        if pending is not None and (selection['kind'] != 'mp' or success or pending.get('ack') != 'started'
                or pending.get('currentRestore') is not True or pending.get('nativeContained') is not True
                or pending.get('continuationAllocated') is not False or pending.get('tailAllocated') is not False
                or pending.get('returnCalls') != 0 or not number(pending.get('at'))
                or not evidence['stopRequestedAt'] <= pending['at'] <= boundary['at']
                or not snapshot(pending.get('snapshot'), ids, phase='expanded')):
            errors.append('Observed pending Host authority released dependent native work')
        ack = restore.get('ack')
        if type(ack) is not list or any(not number(item.get('at')) for item in ack):
            errors.append('Missing exact native restore ACK observations')
        elif selection['kind'] == 'mp':
            terminal = 'completed' if success else 'canceled'
            completed_acks = [item for item in ack if item.get('state') == terminal]
            if (len(completed_acks) != 1 or completed_acks[0].get('captured') is not True
                    or completed_acks[0].get('kind') != 'ISEquipWeaponAction'
                    or type(completed_acks[0].get('transaction')) is not int
                    or not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', str(completed_acks[0].get('token')))
                    or any(completed_acks[0].get(key) is not True for key in
                           ('nativeSame', 'itemSame', 'actorSame', 'queueSame', 'rootSame', 'operationSame'))
                    or completed_acks[0].get('nativeRef') != restore['nativeRef']
                    or not authenticated_operation_same(completed_acks[0].get('operationRef'), restore['operationRef'],
                                                        completed_acks[0].get('operationSame'))):
                errors.append('Host restore lacks its exact authenticated terminal native ACK')
            if any(item.get('state') in ('completed', 'canceled', 'rejected') and item.get('state') != terminal for item in ack):
                errors.append('Host restore acquired a conflicting terminal native ACK')
        removed_pending = evidence.get('pendingAfterRemoval')
        if removed_pending is not None:
            terminal_acks = [item for item in ack if item.get('state') == 'canceled'] if type(ack) is list else []
            terminal_ack = terminal_acks[0] if len(terminal_acks) == 1 else {}
            if (selection['kind'] != 'mp' or success or removed_pending.get('ack') != 'started'
                    or removed_pending.get('currentRestore') is not True or removed_pending.get('nativeContained') is not False
                    or removed_pending.get('continuationAllocated') is not False or removed_pending.get('tailAllocated') is not False
                    or type(removed_pending.get('returnCalls')) is not int or removed_pending['returnCalls'] != 0
                    or removed_pending.get('nativeRef') != restore['nativeRef']
                    or type(removed_pending.get('transaction')) is not int
                    or removed_pending.get('transaction') != terminal_ack.get('transaction')
                    or removed_pending.get('token') != terminal_ack.get('token')
                    or not number(removed_pending.get('at')) or not number(terminal_ack.get('at'))
                    or not evidence['stopRequestedAt'] <= removed_pending['at'] <= terminal_ack['at'] <= boundary['at']
                    or not snapshot(removed_pending.get('snapshot'), ids, phase='expanded')):
                errors.append('Post-removal pending Host authority lost its exact current restore or released dependent native work')
    except (KeyError, TypeError, ValueError, IndexError, AttributeError) as error:
        errors.append('Malformed claimed-return evidence: ' + str(error))
    return errors


def verify(root, selection, catalog):
    root = Path(root); issues = []; outcomes = []
    cases = selection['cases']
    try:
        client = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else client
        events = [(position, row) for position, row in records(client, '[QUEUE_CHECK] ') if row.get('suite') == 'claimed-return']
        setups = [(position, row) for position, row in events if row.get('event') == 'setup']
        rows = [(position, row) for position, row in events if row.get('event') == 'case']
        completions = [(position, row) for position, row in events if row.get('event') == 'complete']
        prepared = records(authority, PREFIX + 'PREPARED ')
        verified = records(authority, PREFIX + 'VERIFIED ')
        placements = records(client, PREFIX + 'CLIENT_PLACEMENT ')
        complete = records(client, PREFIX + 'COMPLETE ')
        raw_ack_rows = records(client, PREFIX + 'ACK ')
        pending_rows = records(client, PREFIX + 'PENDING_AUTHORITY ')
        removed_pending_rows = records(client, PREFIX + 'PENDING_AFTER_REMOVAL ')
        if (len(setups) != 1 or setups[0][1].get('cases') != cases or setups[0][1].get('nativeDurations') is not True
                or setups[0][1].get('provider') != 'native-returns'
                or len(completions) != 1 or any(completions[0][1].get(key) != value for key, value in
                    {'cases': cases, 'performed': len(cases), 'failed': 0, 'skipped': 0}.items())
                or len(complete) != 1 or complete[0][1] != {'cases': cases}
                or [row.get('id') for _, row in rows] != cases
                or any([row.get('case') for _, row in stream] != cases for stream in (prepared, verified, placements))):
            raise ValueError('Missing, duplicate, foreign or reordered setup/case/authority/completion receipts')
        if ([value for _, value in raw_ack_rows] != [dict(case=row['id'], actionRef=row['evidence']['restore']['actionRef'], observation=ack)
                for _, row in rows for ack in row['evidence']['restore'].get('ack', [])]
                or [value for _, value in pending_rows] != [dict(case=row['id'], observation=row['evidence']['pendingAuthority'])
                    for _, row in rows if 'pendingAuthority' in row['evidence']]
                or [value for _, value in removed_pending_rows] != [dict(case=row['id'], observation=row['evidence']['pendingAfterRemoval'])
                    for _, row in rows if 'pendingAfterRemoval' in row['evidence']]):
            issues.append('Raw native authority/ACK observations are missing, duplicate, foreign or reordered')
        if (selection['kind'] == 'mp' and any(case in ('claimed-failure', 'claimed-cancel') for case in cases)
                and not removed_pending_rows):
            issues.append('Host stopped-case group lacks an observed post-removal pending authority window')
        if selection['kind'] == 'mp' and (records(client, PREFIX + 'PREPARED ') or records(client, PREFIX + 'VERIFIED ')
                or records(authority, PREFIX + 'CLIENT_PLACEMENT ') or records(authority, '[QUEUE_CHECK] ')
                or records(authority, PREFIX + 'PENDING_AFTER_REMOVAL ') or records(authority, PREFIX + 'PENDING_AUTHORITY ')):
            raise ValueError('Claimed-return evidence emitted by wrong native process')
        if not setups[0][0] < placements[0][0] or not rows[-1][0] < completions[0][0] < complete[0][0]:
            issues.append('Native case receipts escape setup/completion boundaries')
        for index, case in enumerate(cases):
            position, row = rows[index]
            errors = check_case(row, selection, prepared[index][1], verified[index][1])
            if (placements[index][1] != {'case': case, 'proof': row.get('clientPlacement')}
                    or not placements[index][0] < position or not prepared[index][0] < verified[index][0]
                    or selection['kind'] == 'sp' and not placements[index][0] < prepared[index][0] < verified[index][0] < position
                    or index and (rows[index - 1][0] >= placements[index][0] or verified[index - 1][0] >= prepared[index][0])):
                errors.append('Native placement/setup/authority publication order differs')
            raw_acks = [value for _, value in raw_ack_rows if value.get('case') == case]
            if raw_acks != [dict(case=case, actionRef=row['evidence']['restore']['actionRef'], observation=ack)
                           for ack in row['evidence']['restore'].get('ack', [])]:
                errors.append('Raw native restore ACK observations differ from the case evidence')
            for pending_position, pending_row in removed_pending_rows:
                if pending_row.get('case') != case:
                    continue
                observed = pending_row.get('observation', {})
                terminal_positions = [ack_position for ack_position, ack_row in raw_ack_rows
                    if ack_row.get('case') == case and ack_row.get('observation', {}).get('state') == 'canceled'
                    and ack_row['observation'].get('transaction') == observed.get('transaction')
                    and ack_row['observation'].get('token') == observed.get('token')]
                if (len(terminal_positions) != 1
                        or not placements[index][0] < pending_position < terminal_positions[0] < position):
                    errors.append('Post-removal pending receipt did not precede its exact native terminal ACK')
            issues.extend(case + ': ' + error for error in errors)
            outcomes.append(dict(actor='client1', case=case, status='failed' if errors else 'passed',
                                 reason='; '.join(errors), outcome={'effectsVerified': not errors,
                                                                  'serverAuthorityVerified': not errors,
                                                                  'tailCompleted': not errors}))
        if '[QUEUE_TEST] FAIL ' in client or '[QUEUE_TEST] FAIL ' in authority:
            issues.append('Claimed-return native fixture failed')
    except (OSError, KeyError, ValueError, TypeError, AttributeError) as error:
        issues.append('Claimed-return verifier: ' + str(error))
    if issues:
        outcomes = [dict(actor='client1', case=case, status='failed', reason='; '.join(issues)) for case in cases]
    return dict(issues=issues, outcomes=outcomes)
