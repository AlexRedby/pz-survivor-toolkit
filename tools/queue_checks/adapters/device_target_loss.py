"""Capture actual world-target loss, with a separate explicit safe-outcome gate."""
import json
import math
from pathlib import Path
import re
import shutil

from .. import report
from ..placement import validate as validate_placement
from ..mod_selection import metadata, mod_ids

MODS = mod_ids(metadata(Path(__file__).resolve().parents[3] / 'SurvivorQoL-selected.ini')['Mods'])
CASES = ('tv-remove', 'tv-move', 'radio-remove', 'radio-move')
WALK_CASES = ('radio-walk-remove', 'tv-walk-move')
ALL_CASES = CASES + WALK_CASES
OPERATIONS = {'tv-remove': 'remove', 'tv-move': 'move', 'radio-remove': 'remove', 'radio-move': 'move',
              'radio-walk-remove': 'remove', 'tv-walk-move': 'move'}
PREFIX = '[DEVICE_TARGET_LOSS] '
LIMITS = [
    'Capture mode records current behavior, including stale detached DeviceData effects and lost tails; it is not fix qualification.',
    'Moved authority objects retain Java object/Data identity. Native replication may allocate a new client proxy; held and live data are separate receipts.',
    'Native authority removal/addition reproduces topology loss; player pickup/move UI, arbitrary device modes, WAN latency and additional peers are not covered.',
    'Ordinary native RWM SetVolume and book durations are retained; fixture observers do not invoke validity/effect callbacks or change timers.',
    'Queue-disabled capture observes perform entry without enabling lifecycle phase tracking; absent finish evidence never implies perform success.',
]


def definitions():
    return {'device-target-loss': dict(status='ready', clients=1, default_mods=MODS,
        scenario_actions={'world-device-target-loss': dict(mods=MODS, checks={
            'cancel-waiting': {c: {'effectsVerified': True, 'pendingRequestsVerified': True} for c in ALL_CASES}},
            scope='; '.join(LIMITS))}, cases=[dict(id=c, producer='fixture', capability='capture',
                kinds=['sp', 'mp'], modes=['native', 'toolkit'], languages=['EN']) for c in ALL_CASES])}


def validate(selection):
    cases = selection.get('cases')
    options = selection.get('options', {})
    expectation = options.get('device_target_loss_expect', 'capture')
    walk_bank = options.get('device_target_loss_walk', False)
    if (not isinstance(cases, list) or not cases or cases != [c for c in ALL_CASES if c in cases]
            or type(walk_bank) is not bool or walk_bank and cases != list(ALL_CASES)
            or not walk_bank and any(c in WALK_CASES for c in cases)
            or selection.get('kind') not in ('sp', 'mp') or selection.get('mode') not in ('native', 'toolkit')
            or selection.get('languages') != ['EN'] or type(selection.get('clients')) is not int
            or selection['clients'] != 1 or selection.get('mods') != MODS or options.get('world_template')
            or expectation not in ('capture', 'safe') or expectation == 'safe' and selection['mode'] != 'toolkit'
            or selection['kind'] == 'mp' and options.get('mp_host') is not True):
        raise ValueError('Device loss requires ordered fresh full-pack SP/menu Host, one EN client, capture or toolkit safe expectation; paid walking requires the explicit six-case bank and device_target_loss_walk=true')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'device-target-loss').rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua', root / 'support/QueueEnergyPlacement.lua',
            Path(__file__).resolve().parents[1] / 'placement.py']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, name in [('client', 'ZZStartup.lua'), ('server', 'ZZStartupServer.lua')]:
            shutil.copy2(root / 'startup' / side / name, lua / side / name)
        shutil.copy2(root / 'health/shared/QueueHealthEvents.lua', lua / 'shared')
    runtime.setdefault('fixture', {}).update(server_ready='[STARTUP_TEST] SERVER_READY',
        failure_markers=['[QUEUE_TEST] FAIL device-target-loss'], sandbox={'Zombies': 6})


def complete(selection, role, text):
    return role == 'client1' and len(re.findall(re.escape(PREFIX) + r'COMPLETE(?:\s|$)', text)) == 1


def number(value):
    return type(value) in (int, float) and math.isfinite(value)


def close(value, wanted):
    return number(value) and number(wanted) and abs(value - wanted) < .0001


def point(value):
    return isinstance(value, dict) and set(value) == {'x', 'y', 'z'} and all(type(v) is int for v in value.values())


def data(value, initial=False):
    return (isinstance(value, dict) and set(value) == {'volume', 'channel', 'on', 'battery', 'media', 'power', 'powered'}
            and number(value['volume']) and 0 <= value['volume'] <= 1 and type(value['channel']) is int
            and value['channel'] == 90000 and value['on'] is True and value['battery'] is False
            and value['media'] is False and number(value['power']) and 0 < value['power'] <= 1
            and type(value['powered']) is bool and (not initial or close(value['volume'], .5) and value['powered']))


def snapshot(value, ids, initial=False, changed=False, authority=False):
    moved = OPERATIONS[ids['case']] == 'move'
    booleans = ('generatorPresent', 'oldPresent', 'destinationPresent', 'heldMemberOld', 'heldMemberDestination',
                'heldDataSame', 'heldDataParentSame', 'liveSameObject', 'liveSameData')
    if (not isinstance(value, dict) or set(value) != {'case', 'key', *booleans, 'heldSquare', 'heldIndex', 'held', 'live', 'books'}
            or value['case'] != ids['case'] or value['key'] != ids['key']
            or any(type(value[k]) is not bool for k in booleans) or not value['generatorPresent']
            or not value['heldDataSame'] or not value['heldDataParentSame']
            or type(value['heldIndex']) is not int or value['heldSquare'] is not False and not point(value['heldSquare'])
            or not data(value['held'], initial) or value['oldPresent'] and value['destinationPresent']):
        return False
    if initial and (not value['oldPresent'] or value['destinationPresent'] or not value['heldMemberOld']
            or value['heldMemberDestination'] or not value['liveSameObject'] or not value['liveSameData']
            or value['heldIndex'] != ids['index'] or value['heldSquare'] != ids['old']):
        return False
    if changed and (value['oldPresent'] or value['destinationPresent'] is not moved or value['heldMemberOld']):
        return False
    if changed and authority and (value['heldMemberDestination'] is not moved
            or value['liveSameObject'] is not moved or value['liveSameData'] is not moved
            or moved and value['heldSquare'] != ids['destination']):
        return False
    present = value['oldPresent'] or value['destinationPresent']
    if (present and not data(value['live'], initial) or not present and value['live'] is not False
            or not present and (value['liveSameObject'] or value['liveSameData'])
            or value['liveSameObject'] != value['liveSameData']
            or value['liveSameData'] and value['live'] != value['held']):
        return False
    if not isinstance(value['books'], dict) or set(value['books']) != {'hold', 'tail'}:
        return False
    for name, row in value['books'].items():
        spec = ids[name]
        if (not isinstance(row, dict) or set(row) != {'id', 'type', 'root', 'count', 'pages', 'characterPages'}
                or type(row['id']) is not int or row['id'] != spec['id'] or row['type'] != spec['type']
                or row['root'] is not True or type(row['count']) is not int or row['count'] != 1
                or any(type(row[k]) is not int or not spec['initial'] <= row[k] <= spec['pages'] for k in ('pages', 'characterPages'))
                or initial and any(row[k] != spec['initial'] for k in ('pages', 'characterPages'))):
            return False
    return True


def check_case(row, case, selection, prepared, mutated, verified, cleaned):
    errors = []
    walking = case in WALK_CASES
    expectation = selection.get('options', {}).get('device_target_loss_expect', 'capture')
    if row.get('status') != ('captured' if expectation == 'capture' else 'passed') or row.get('expectation') != expectation:
        errors.append('Wrong capture/safe verdict')
    ids = row.get('ids', {})
    id_keys = {'case', 'mode', 'key', 'class', 'old', 'destination', 'index', 'origin', 'generator', 'placementProof', 'hold', 'tail'}
    if (not isinstance(ids, dict) or set(ids) != id_keys | ({'walkLayout'} if walking else set()) or ids != prepared
            or ids.get('case') != case or ids.get('mode') != selection['mode']
            or ids.get('class') != ('IsoTelevision' if case.startswith('tv-') else 'IsoRadio')
            or not isinstance(ids.get('key'), str) or not ids['key'].startswith('device-target-loss:' + case + ':')
            or type(ids.get('index')) is not int or ids['index'] < 0
            or any(not point(ids.get(k)) for k in ('old', 'destination', 'origin', 'generator'))):
        return errors + ['Exact prepared world/device identity differs']
    origin = ids['origin']
    if (ids['old'] != dict(origin, x=origin['x'] - (8 if walking else 1))
            or ids['destination'] != dict(origin, x=origin['x'] + (-9 if walking else 1))
            or ids['generator'] != dict(origin, x=origin['x'] - (5 if walking else 0), y=origin['y'] + 1)
            or walking and ids.get('walkLayout') != dict(distance=8, minX=-10, maxX=1, minY=-1, maxY=1, chosenBeforePlacement=True)):
        errors.append('Device/destination/generator placement differs')
    for name, kind, remaining in [('hold', 'Base.BookForaging1', 4), ('tail', 'Base.BookTrapping1', 2)]:
        book = ids.get(name)
        if (not isinstance(book, dict) or set(book) != {'id', 'type', 'pages', 'initial'} or book.get('type') != kind
                or any(type(book.get(k)) is not int for k in ('id', 'pages', 'initial'))
                or book['id'] < 0 or book['initial'] <= 0 or book['pages'] - book['initial'] != remaining):
            return errors + ['Invalid exact independent book identity']
    if ids['hold']['id'] == ids['tail']['id']:
        errors.append('Hold/tail book identities collide')
    try:
        validate_placement(row.get('clientPlacement'), origin, 'local')
        validate_placement(ids['placementProof'], origin, 'replica' if selection['kind'] == 'mp' else 'local')
    except (ValueError, TypeError, KeyError) as error:
        errors.append('Invalid settled placement: ' + str(error))
    if not snapshot(row.get('before'), ids, initial=True):
        errors.append('Missing untouched initial held/live data and book snapshot')
    mutation_ok = (isinstance(mutated, dict) and row.get('mutation') == mutated
        and set(mutated) == {'case', 'key', 'operation', 'sameAuthorityObject', 'sameAuthorityData', 'before', 'after', 'at'}
        and mutated.get('case') == case and mutated.get('key') == ids['key']
        and mutated.get('operation') == OPERATIONS[case]
        and mutated.get('sameAuthorityObject') is True and mutated.get('sameAuthorityData') is True
        and number(mutated.get('at')) and snapshot(mutated.get('before'), ids, authority=True)
        and snapshot(mutated.get('after'), ids, changed=True, authority=True)
        and close(mutated['before']['held']['volume'], .5) and close(mutated['after']['held']['volume'], .5))
    if not mutation_ok:
        errors.append('Exact same authority object/data mutation receipt differs')
    if not snapshot(row.get('observed'), ids, changed=True):
        errors.append('Missing replicated client target loss before hold completion')
    if not snapshot(row.get('client'), ids, changed=True) or not snapshot(verified, ids, changed=True, authority=True) or row.get('server') != verified:
        errors.append('Final held vs live device and independent-tail snapshots differ')
    names = ['hold', *(['setter:approach'] if selection['mode'] == 'toolkit' else []), 'setter', 'tail']
    initial_names = ['hold', 'setter:walk', 'setter', 'tail'] if walking and selection['mode'] == 'native' else names
    commands = row.get('commands')
    by_name = {}
    if row.get('initialQueue') != initial_names or not isinstance(commands, list) or [r.get('name') for r in commands if isinstance(r, dict)] != names:
        errors.append('Native RWM pending operation and independent tail queue differs')
    else:
        by_name = {command['name']: command for command in commands}
        for name, command in by_name.items():
            wanted = 'ISReadABook' if name in ('hold', 'tail') else 'ISRadioAction' if name == 'setter' else 'ISQueueActionsAction'
            if (command.get('type') != wanted or not number(command.get('duration'))
                    or (command['duration'] != -1 if name == 'setter:approach' else command['duration'] <= 0)
                    or any(type(command.get(k)) is not bool for k in ('started', 'progress', 'performed', 'stopped', 'allocated'))
                    or type(command.get('starts')) is not int or command['starts'] != int(command.get('started') is True)
                    or command.get('progress') and not command.get('started') or command.get('performed') and not command.get('started')
                    or command.get('progress') and (not number(command.get('progressAt'))
                        or not number(command.get('startedAt')) or command['progressAt'] < command['startedAt'])
                    or command.get('started') and not number(command.get('startedAt'))
                    or command.get('performed') and (not number(command.get('finishedAt')) or not number(command.get('performAt'))
                        or command['finishedAt'] < command['performAt'])
                    or command.get('allocated') and (not number(command.get('effectiveDuration'))
                        or not close(command['effectiveDuration'], command.get('nativeDurationExpected')))):
                errors.append('Native lifecycle/ordinary duration evidence differs: ' + name)
            if name == 'setter' and not close(command.get('duration'), 30):
                errors.append('RWM SetVolume constructor duration differs')
        setter = by_name['setter']
        if (setter.get('mode') != 'SetVolume' or not close(setter.get('value'), .75)
                or setter.get('targetKey') != ids['key'] or setter.get('originalDevice') is not True
                or setter.get('originalData') is not True or setter.get('pendingAtMutate') is not True
                or not number(setter.get('mutationRequestedAt'))):
            errors.append('Pending original native RWM mode/value/device/data binding differs')
        hold = by_name['hold']; observed_at = row.get('observedAt')
        if (not hold.get('started') or not hold.get('progress') or selection['mode'] == 'toolkit' and not hold.get('performed')
                or not number(observed_at) or not number(hold.get('startedAt')) or not number(hold.get('performAt'))
                or not hold['startedAt'] <= observed_at
                or walking and observed_at < hold['performAt']
                or not walking and observed_at >= hold['performAt']
                or not number(hold.get('progressAt')) or not number(setter.get('mutationRequestedAt'))
                or not hold['startedAt'] <= hold['progressAt'] <= setter['mutationRequestedAt'] <= observed_at
                or not mutation_ok or not setter['mutationRequestedAt'] <= mutated['at'] <= observed_at):
            errors.append('Mutation/replication was not observed in the selected progressed hold/paid-walk window')
        if by_name['setter'].get('started') and (not number(observed_at) or by_name['setter']['startedAt'] < observed_at):
            errors.append('Setter started before replicated target loss')
        client_hold = row.get('client', {}).get('books', {}).get('hold', {}) if isinstance(row.get('client'), dict) else {}
        if client_hold.get('pages') != ids['hold']['pages'] or client_hold.get('characterPages') != ids['hold']['pages']:
            errors.append('Native hold reading effect did not complete')
    walk_safe = True
    if walking:
        walk_errors, walk_safe = paid_approach(row.get('paidApproach'), ids, row, by_name, selection)
        errors += walk_errors
    elif 'paidApproach' in row:
        errors.append('Unexpected paid walk receipt in the unchanged pending bank')
    if (type(row.get('queueIdle')) is not bool or type(row.get('queueTimedOut')) is not bool
            or row.get('queueIdle') == row.get('queueTimedOut')
            or row.get('recovery') != ('none' if row.get('queueIdle') else 'native-stop-all')
            or not number(row.get('settleMilliseconds')) or row['settleMilliseconds'] < (1000 if row.get('queueIdle') else 0)
            or row.get('nativeCallbacksUnchanged') is not True or row.get('originalSetterBinding') is not True):
        errors.append('Missing native callback/binding, drain and late-packet settling evidence')
    expected_cleanup = dict(case=case, key=ids['key'], objectsRemoved=True, generatorRemoved=True, booksRemoved=True)
    if (cleaned != expected_cleanup or row.get('cleanup') != cleaned or row.get('cleanupObserved') is not True
            or not number(row.get('cleanupSettleMilliseconds')) or row['cleanupSettleMilliseconds'] < 1000):
        errors.append('Exact owned authority/client cleanup and settling missing')
    acks = row.get('acks')
    if not isinstance(acks, list):
        errors.append('Missing native transaction ACK observation')
    elif acks:
        if (selection['kind'] != 'mp' or len(acks) > 2 or any(not isinstance(a, dict) for a in acks)
                or [a.get('state') for a in acks] not in (['started'], ['started', 'completed'], ['started', 'canceled'], ['started', 'rejected'])):
            errors.append('Native setter ACK state sequence differs')
        elif any(a.get('kind') != 'ISRadioAction' or a.get('token') != acks[0].get('token')
                 or not isinstance(a.get('token'), str) or not re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', a['token'])
                 or a.get('transaction') != acks[0].get('transaction') or not number(a.get('transaction'))
                 or by_name.get('setter', {}).get('ackToken') != a.get('token')
                 or not number(a.get('at')) for a in acks):
            errors.append('Native setter ACK identity differs')
    if not errors:
        client = row['client']; tail = client['books']['tail']
        setter = by_name['setter']
        safe = (selection['mode'] == 'toolkit' and row['queueIdle'] and row['recovery'] == 'none'
            and setter['started'] is False and setter['starts'] == 0 and setter['allocated'] is False
            and setter['performed'] is False and setter.get('performAt') is None and not acks
            and close(client['held']['volume'], .5) and close(verified['held']['volume'], .5)
            and (client['live'] is False or close(client['live']['volume'], .5))
            and (verified['live'] is False or close(verified['live']['volume'], .5))
            and tail['pages'] == ids['tail']['pages'] and tail['characterPages'] == ids['tail']['pages']
            and all(by_name['tail'][k] for k in ('started', 'progress', 'performed')))
        safe = safe and walk_safe
        if row.get('safeOutcome') is not safe or expectation == 'safe' and not safe:
            errors.append('Safe target-loss outcome/independent native tail did not pass')
    return errors


def paid_approach(value, ids, row, commands, selection):
    error = ['Missing exact progressed native paid-walk mutation/lifetime evidence']
    if (not isinstance(value, dict) or set(value) != {'schema', 'producer', 'mode', 'children', 'child', 'initialPending', 'tailIndependent', 'mutation', 'observed'}
            or value.get('schema') != 1 or value.get('producer') != 'native RWM walkAdj'
            or value.get('mode') != selection['mode'] or value.get('children') != 1
            or value.get('initialPending') is not True or value.get('tailIndependent') is not True):
        return error, False
    child = value.get('child')
    if (not isinstance(child, dict) or child.get('name') != 'setter:walk' or child.get('type') != 'ISWalkToTimedAction'
            or child.get('duration') != -1 or child.get('starts') != 1
            or any(child.get(k) is not True for k in ('started', 'progress', 'allocated', 'sameOperation', 'nativeCallbacks', 'nativeHandleStable'))
            or any(type(child.get(k)) is not bool for k in ('performed', 'stopped', 'retired'))
            or not close(child.get('effectiveDuration'), -1) or not close(child.get('nativeDurationExpected'), -1)
            or not point(child.get('destination')) or not finite_position(child.get('startPosition'))
            or any(not number(child.get(k)) for k in ('startedAt', 'nativeAllocatedAt', 'progressAt'))
            or not child['startedAt'] <= child['nativeAllocatedAt'] <= child['progressAt']):
        return error, False
    old = ids['old']; destination = child['destination']
    if (destination['z'] != old['z'] or abs(destination['x'] - old['x']) > 1 or abs(destination['y'] - old['y']) > 1
            or destination == old or max(abs(child['startPosition'][k] - destination[k]) for k in ('x', 'y')) < 5):
        return error, False
    setter = commands.get('setter', {}); hold = commands.get('hold', {})
    if selection['mode'] == 'toolkit':
        preparation = commands.get('setter:approach', {})
        if (not all(preparation.get(k) is True for k in ('started', 'allocated', 'performed'))
                or not number(preparation.get('performAt')) or preparation['performAt'] > child['startedAt']):
            return error, False
    mutation, observed = value.get('mutation'), value.get('observed')
    for event in (mutation, observed):
        if (not isinstance(event, dict) or set(event) != {'at', 'position', 'currentNativeSame', 'bodyUnallocated', 'bodyUnstarted', 'sameOperation'}
                or not number(event.get('at')) or not finite_position(event.get('position'))
                or any(event.get(k) is not True for k in ('currentNativeSame', 'bodyUnallocated', 'bodyUnstarted', 'sameOperation'))):
            return error, False
    if (not number(hold.get('performAt')) or not number(setter.get('mutationRequestedAt'))
            or not hold['performAt'] <= child['startedAt'] <= child['progressAt'] <= mutation['at'] <= setter['mutationRequestedAt']
            or not setter['mutationRequestedAt'] <= row['mutation']['at'] <= observed['at'] <= row['observedAt']
            or abs(mutation['position']['x'] - child['startPosition']['x']) + abs(mutation['position']['y'] - child['startPosition']['y']) <= .05
            or child.get('performAt') is not None and (not number(child['performAt']) or child['performAt'] <= observed['at'])):
        return error, False
    safe = (child.get('performed') is True and child.get('resultSucceeded') is True and child.get('atDestination') is True
            and child.get('retired') is True and child.get('stopped') is False
            and finite_position(child.get('arrival')) and number(child.get('performAt')) and number(child.get('finishedAt'))
            and number(child.get('retiredAt')) and observed['at'] < child['performAt'] <= child['finishedAt'] <= child['retiredAt']
            and all(math.floor(child['arrival'][k]) == destination[k] for k in ('x', 'y')) and close(child['arrival']['z'], destination['z']))
    return [], safe


def finite_position(value):
    return isinstance(value, dict) and set(value) == {'x', 'y', 'z'} and all(number(v) for v in value.values())


def raw(text, marker):
    rows = [json.loads(m.group(1)) for m in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\n]+)', text)]
    if any(not isinstance(row, dict) for row in rows):
        raise ValueError('Malformed device-loss authority marker: ' + marker)
    return rows


def verify(root, selection, catalog):
    issues, outcomes = [], []
    try:
        root = Path(root)
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        rows = [r for r in report.events(text) if r.get('suite') == 'device-target-loss' and r.get('event') == 'case']
        markers = {name: raw(authority, name) for name in ('PREPARED', 'MUTATED', 'VERIFIED', 'CLEANED')}
        placements = raw(text, 'CLIENT_PLACEMENT')
        if [r.get('id') for r in rows] != selection['cases'] or any([r.get('case') for r in values] != selection['cases'] for values in [*markers.values(), placements]):
            issues.append('Device loss case/authority markers missing, duplicated or out of order')
        for i, case in enumerate(selection['cases']):
            row = rows[i] if i < len(rows) else {}
            values = [markers[name][i] if i < len(markers[name]) else None for name in ('PREPARED', 'MUTATED', 'VERIFIED', 'CLEANED')]
            errors = check_case(row, case, selection, *values)
            if (row.get('actor') != 'client1' or row.get('kind') != selection['kind'] or row.get('mode') != selection['mode']
                    or i >= len(placements) or placements[i] != dict(case=case, proof=row.get('clientPlacement'))):
                errors.append('Owning client/kind/mode/raw placement differs')
            issues += [case + ': ' + error for error in errors]
            status = 'failed' if errors else row['status']; qualified = not errors and status == 'passed'
            outcomes.append(dict(actor='client1', case=case, status=status, reason='; '.join(errors),
                outcome=dict(effectsVerified=qualified, pendingRequestsVerified=qualified,
                             serverAuthorityVerified=qualified, baselineCaptured=not errors and status == 'captured')))
        if not complete(selection, 'client1', text):
            issues.append('Missing unique device-target-loss completion')
    except (OSError, ValueError, TypeError, KeyError, AttributeError) as error:
        issues.append(str(error))
    return dict(issues=issues, outcomes=outcomes, evidence=dict(limits=LIMITS))
