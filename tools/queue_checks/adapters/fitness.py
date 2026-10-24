"""Native fitness menu requests and clinical effects, with a real Host peer."""
import copy
import json
import math
from pathlib import Path
import re
import shutil

from ..mod_selection import metadata, mod_ids

CASES = ['empty', 'queued', 'sequential', 'pending-cancel', 'pending-reorder', 'active-cancel',
         'missing-dumbbell', 'exhaustion', 'closed-ui-restore', 'burpees-30', 'active-cancel-restore', 'pickup-cancel-restore']
PROJECT = Path(__file__).resolve().parents[3]
MODS = mod_ids(metadata(PROJECT / 'SurvivorQoL-selected.ini')['Mods'])
SCENARIO_ACTIONS = {'fitness-ui': {
    'scope': 'Actual ISFitnessUI OK; native ten-minute squats/pushups/biceps curl and thirty-minute burpees, long native reader, exact held/worn IDs, and authoritative real repetitions/clinical changes. Host uses a second actual independent reader.',
    'checks': {
        'success-empty': {'empty': {'effectsVerified': True, 'emptyStartVerified': True}},
        'success-queued': {'queued': {'effectsVerified': True, 'queuedStartVerified': True},
                           'sequential': {'effectsVerified': True, 'sequentialVerified': True}},
        'cancel-waiting': {'pending-cancel': {'effectsVerified': True, 'waitingCancelVerified': True}},
        'move-independent': {'pending-reorder': {'effectsVerified': True, 'independentMoveVerified': True}},
        'cancel-active': {'active-cancel': {'effectsVerified': True, 'activeCancelVerified': True}},
        'lost-before-start': {'missing-dumbbell': {'effectsVerified': True, 'missingItemVerified': True}},
        'restore-hands': {'closed-ui-restore': {'effectsVerified': True, 'restoreVerified': True}},
        'server-authority': {'sequential': {'effectsVerified': True, 'serverAuthorityVerified': True}},
    },
    'toolkit_only': ['cancel-waiting', 'move-independent', 'lost-before-start'],
}}


def definitions():
    return {'fitness': {'status': 'ready', 'clients': 2, 'default_mods': list(MODS),
        'scenario_actions': SCENARIO_ACTIONS,
        'cases': [dict(id=case, producer='fitness-ui', capability='effect', kinds=['sp', 'mp'],
                       languages=['EN', 'RU'], modes=['native', 'toolkit']) for case in CASES]}}


def validate(selection):
    cases = selection.get('cases')
    kind = selection.get('kind')
    clients = selection.get('clients', 2 if kind == 'mp' else 1)
    languages = selection.get('languages')
    if (type(cases) is not list or not cases or cases != [case for case in CASES if case in cases]
            or kind not in ('sp', 'mp') or selection.get('mode') not in ('native', 'toolkit')
            or type(clients) is not int or clients != (2 if kind == 'mp' else 1)
            or (languages not in (['EN'], ['RU']) if kind == 'sp' else languages != ['EN', 'RU'])
            or selection.get('mods') != MODS or selection.get('options', {}).get('world_template')
            or kind == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Fitness requires ordered cases, fresh full selected pack, SP one EN/RU client or real two-client EN/RU Host, native/toolkit mode')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / 'fitness').rglob('*.lua')), root / 'health/shared/QueueHealthEvents.lua',
            root / 'startup/client/ZZStartup.lua', root / 'startup/server/ZZStartupServer.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for side, source in [('shared', root / 'health/shared/QueueHealthEvents.lua'),
                             ('client', root / 'startup/client/ZZStartup.lua')]:
            (lua / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, lua / side)
    runtime.setdefault('fixture', {}).update(server_ready='[FITNESS_TEST] SERVER_READY',
                                             sandbox={'Zombies': 6, 'MinutesPerPage': 2.0})


def complete(selection, role, text):
    return role in ('client1', 'client2') and len(re.findall(r'\[FITNESS_TEST\] COMPLETE(?:\s|$)', text)) == 1


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def _same(left, right):
    if type(left) is not type(right):
        return False
    if isinstance(right, dict):
        return left.keys() == right.keys() and all(_same(left[key], value) for key, value in right.items())
    if isinstance(right, list):
        return len(left) == len(right) and all(_same(a, b) for a, b in zip(left, right))
    return left == right


def _matches(row, expected):
    return isinstance(row, dict) and all(_same(row.get(key), value) for key, value in expected.items())


def _inventory(value):
    if not isinstance(value, dict) or set(value) != {'items', 'primary', 'secondary', 'worn'}:
        return False
    items, worn = value['items'], value['worn']
    if not isinstance(items, list) or not items or not isinstance(worn, list):
        return False
    ids = [row.get('id') for row in items if isinstance(row, dict)]
    if (len(ids) != len(items) or any(type(identity) is not int for identity in ids)
            or len(ids) != len(set(ids)) or ids != sorted(ids)):
        return False
    if any(set(row) != {'id', 'kind', 'container'} or not isinstance(row['kind'], str)
           or row['container'] != 'root' and (type(row['container']) is not int or row['container'] not in ids) for row in items):
        return False
    if any(type(value[key]) is not bool and (type(value[key]) is not int or value[key] not in ids)
           or value[key] is True for key in ('primary', 'secondary')):
        return False
    return (all(isinstance(row, dict) and set(row) == {'id', 'location'} and type(row['id']) is int
                and row['id'] in ids and isinstance(row['location'], str) for row in worn)
            and len({row['location'] for row in worn}) == len(worn))


def _clinical(value):
    return (isinstance(value, dict) and all(_number(value.get(key)) for key in ('fitnessXP', 'strengthXP', 'endurance'))
            and 0 <= value['endurance'] <= 1
            and all(isinstance(value.get(group), dict)
                    and (set(value[group]) == set(keys) or group == 'regularity' and set(value[group]) == set(keys) | {'burpees'})
                    and all(_number(number) for number in value[group].values()) for group, keys in (
                        ('regularity', ('squats', 'pushups', 'bicepscurl')),
                        ('stiffness', ('legs', 'arms', 'chest', 'abs')),
                        ('timers', ('legs', 'arms', 'chest', 'abs')))))


def _exhaustion_without_training(before, after):
    # Native B42.21 IsoPlayer.updateInternal2 (bytecode727-796) awards Fitness+1
    # without a workout when !GameClient.client, endurance<0.25, and
    # Rand.Next(int(300 * GameTime.getInvMultiplier()))==0. exerciseRepeat()
    # calls incRegularity/incFutureStiffness before XP; these retain the replay gate.
    return (_clinical(before) and _clinical(after) and after['fitnessXP'] >= before['fitnessXP']
            and after['strengthXP'] == before['strengthXP']
            and all(after[group][key] <= value for group in ('regularity', 'stiffness')
                    for key, value in before[group].items()))


RESTORATION_CASES = ('active-cancel-restore', 'pickup-cancel-restore')
IMMEDIATE_CASES = ('empty', 'active-cancel', 'burpees-30', *RESTORATION_CASES)
BORROWED_CASES = ('closed-ui-restore', *RESTORATION_CASES)


def _expected_exercises(case, mode):
    if case == 'exhaustion' or mode == 'toolkit' and case in ('pending-cancel', 'missing-dumbbell', 'pickup-cancel-restore'):
        return []
    if case == 'burpees-30':
        return ['burpees']
    return ['squats', 'pushups'] if case == 'sequential' else ['bicepscurl' if case in ('missing-dumbbell', *BORROWED_CASES) else 'squats']


def _case(case, row, prep, receipt, selection, mutation=None):
    issues = []
    native, mp = selection['mode'] == 'native', selection['kind'] == 'mp'
    minutes = 30 if case == 'burpees-30' else 10
    command = row.get('command', {})
    items = prep.get('items', {})
    if (not _matches(prep, {'case': case}) or not isinstance(items, dict)
            or set(items) != {'front', 'tail', 'bag', 'hammer', 'screwdriver', 'dumbbell'}
            or any(type(value) is not int for value in items.values()) or len(set(items.values())) != 6
            or not _inventory(prep.get('inventory')) or not _clinical(prep.get('before'))):
        return ['Fitness exact preparation differs: ' + case]
    expected = copy.deepcopy(prep['inventory'])
    if native and case in RESTORATION_CASES:
        for item in expected['items']:
            if item['id'] == items['dumbbell']:item['container'] = 'root'
    if case == 'missing-dumbbell':
        expected['items'] = [item for item in expected['items'] if item['id'] != items['dumbbell']]
    if (not _inventory(receipt.get('inventory')) or not _same(receipt['inventory'], expected)
            or not _same(command.get('clientInventory'), expected)):
        issues.append('Fitness exact inventory/container/hand/worn identities differ: ' + case)
    if (not _matches(receipt, {'case': case, 'tailRead': True, 'frontRead': case not in IMMEDIATE_CASES,
                               'currentExerciseCleared': True, 'serverStopSettled': True, 'peerConnected': True,
                               'removed': items['dumbbell'] if case == 'missing-dumbbell' else False})
            or not _same(receipt.get('before'), prep['before']) or not _clinical(receipt.get('clinical'))
            or not _matches(row, {'status': 'passed', 'reason': None, 'receipt': receipt})
            or not _number(receipt.get('serverSettleMilliseconds')) or receipt['serverSettleMilliseconds'] < 2000):
        issues.append('Fitness authoritative settled effects/independent tail differ: ' + case)
    expected_fields = dict(menuDispatched=True, nativeDurations=True, minutes=minutes, frontMinutes=0 if case in IMMEDIATE_CASES else 12,
        activeObserved=bool(_expected_exercises(case, selection['mode'])), queueDrained=True, clientCurrentExerciseCleared=True,
        pendingCancelled=not native and case == 'pending-cancel', reordered=not native and case == 'pending-reorder',
        activeCancelled=case in ('active-cancel', 'active-cancel-restore'), closedUI=case == 'closed-ui-restore')
    if case == 'burpees-30' and not native:
        delay = command.get('durationStopDelayMilliseconds')
        if not _number(delay) or not 0 <= delay < 5000:
            issues.append('Fitness native stop remained active after selected duration: ' + case)
    if case in BORROWED_CASES and not native:
        expected_fields.update(borrowedTransferProgress=True, borrowedTool=items['dumbbell'], borrowedSourceBag=items['bag'])
    if case == 'pending-reorder' and not native:
        expected_fields['reorderedTailBeforeStart'] = True
    if case not in IMMEDIATE_CASES:
        expected_fields['waitingNoExercise'] = True
        if case != 'exhaustion':
            expected_fields['waitingNoClinicalEffects'] = True
        if not _number(command.get('waitMS')) or command['waitMS'] < 600000:
            issues.append('Fitness did not wait longer than native workout duration: ' + case)
    if case == 'exhaustion':
        # The sealed fixture flag only observed XP equality. Recompute training
        # effects from both original snapshots instead of trusting its true/false value.
        if (type(command.get('waitingNoClinicalEffects')) is not bool
                or not _exhaustion_without_training(command.get('initialClinical'), receipt.get('clinical'))
                or not _exhaustion_without_training(prep['before'], receipt.get('clinical'))):
            issues.append('Fitness exhaustion changed training effects or decreased XP: ' + case)
    if not _matches(command, expected_fields):
        issues.append('Fitness menu/timing/control observations differ: ' + case)
    if case in ('missing-dumbbell', 'exhaustion'):
        if (not _matches(command, {'mutationObserved': True, 'mutation': mutation}) or not isinstance(mutation, dict)
                or not _matches(mutation, dict(case=case, removed=items['dumbbell'] if case == 'missing-dumbbell' else False))
                or not _number(mutation.get('endurance')) or case == 'exhaustion' and mutation['endurance'] > .05):
            issues.append('Fitness exact input loss/exhaustion mutation differs: ' + case)
    records = receipt.get('records', [])
    exercises = _expected_exercises(case, selection['mode'])
    if case == 'missing-dumbbell':
        exercises = []  # Native execution with the lost exact dumbbell is an observed failure.
    if (not isinstance(records, list) or [record.get('exercise') for record in records] != exercises
            or command.get('startedOrder') != exercises or receipt.get('violations') != []):
        issues.append('Fitness native workout order/count or stop barrier differs: ' + case)
    if not native:
        progress = command.get('progressSamples')
        if (not isinstance(progress, list) or [sample.get('exercise') for sample in progress] != exercises
                or any(not all(_number(sample.get(key)) for key in ('total', 'elapsed', 'fraction', 'startMS', 'sampleMS'))
                       or sample.get('total') != minutes or not 0 < sample.get('elapsed', 0) <= minutes
                       or not 0 < sample.get('fraction', 0) <= 1
                       or abs(sample['fraction'] - sample['elapsed']/minutes) > 1e-6
                       or abs(sample['elapsed'] - max(0, min(minutes, (sample['sampleMS']-sample['startMS'])/60000))) > 1e-6
                       or not isinstance(sample.get('label'), str) or not sample['label'] for sample in progress)):
            issues.append('Fitness visible progress does not match selected native elapsed time: ' + case)
    if case in BORROWED_CASES:
        initial_tool = next((item for item in prep['inventory']['items'] if item['id'] == items['dumbbell']), {})
        if initial_tool.get('container') != items['bag']:
            issues.append('Fitness restoration did not borrow exact dumbbell from worn bag: ' + case)
        for record in records:
            start_inventory = record.get('startEquipment', {})
            start_tool = next((item for item in start_inventory.get('items', []) if item.get('id') == items['dumbbell']), {})
            if (not _inventory(start_inventory) or start_tool.get('container') != 'root'
                    or start_inventory.get('primary') != items['dumbbell'] or start_inventory.get('secondary') is not False
                    or any(item['id'] == items['bag'] for item in start_inventory.get('worn', []))):
                issues.append('Fitness authoritative start lacked borrowed dumbbell/unequipped bag: ' + case)
    if case in RESTORATION_CASES:
        # Vanilla keeps its native UI restoration and never returns its prop to the
        # source bag. Its baseline records this difference without claiming Toolkit cleanup.
        expected_types = dict(front='Base.BookCarpentry1', tail='Base.BookFirstAid1', bag='Base.Bag_Schoolbag',
                              hammer='Base.Torch', screwdriver='Base.Screwdriver', dumbbell='Base.DumbBell')
        if (any(next((item for item in prep['inventory']['items'] if item['id'] == identity), {}).get('kind') != expected_types[name]
                for name, identity in items.items())
                or not _same(prep.get('activation'), {str(items['hammer']): True})):
            issues.append('Fitness borrowed cancellation exact gear/type/activation setup differs: ' + case)
        before_tail = command.get('beforeTail', {})
        if (before_tail.get('callback') != 'ISBaseTimedAction.begin' or not _inventory(before_tail.get('inventory')) or not _number(before_tail.get('nativeClock'))
                or not isinstance(before_tail.get('activation'), dict)
                or not _matches(command, dict(cancelCallback='ISFitnessUI:CANCEL' if native else 'ActionQueue.cancelOperation'))):
            issues.append('Fitness independent tail boundary/native cancel callback missing: ' + case)
        if not native:
            settlement = command.get('settlement', {})
            if (command.get('confirmedPickup') is not True or command.get('confirmedReturn') is not True or not _matches(command, dict(returnCount=1))
                    or settlement.get('borrowings') != [dict(id=items['dumbbell'], fullType='Base.DumbBell', state='completed')]
                    or not _same(before_tail.get('inventory'), expected)
                    or not _same(before_tail.get('activation'), prep['activation'])
                    or not _same(command.get('clientActivation'), prep['activation'])
                    or not _same(receipt.get('activation'), prep['activation'])):
                issues.append('Fitness cancellation lacked confirmed pickup/return or exact restoration before reader: ' + case)
            if case == 'active-cancel-restore':
                steps = command.get('preparationAtCancel', {}).get('steps', [])
                observed = [step for step in steps if step.get('observedPreparation') is True]
                expected_preparation = [('ISUnequipAction', items['hammer'], 'Base.Torch'),
                                        ('ISUnequipAction', items['screwdriver'], 'Base.Screwdriver'),
                                        ('ISUnequipAction', items['bag'], 'Base.Bag_Schoolbag'),
                                        ('ISInventoryTransferAction', items['dumbbell'], 'Base.DumbBell'),
                                        ('ISEquipWeaponAction', items['dumbbell'], 'Base.DumbBell')]
                if (command.get('confirmedPreparation') is not True or len(observed) != 5
                        or [(step.get('kind'), step.get('itemId'), step.get('itemType')) for step in observed] != expected_preparation
                        or any(not _matches(step, dict(state='earned', started=True)) for step in observed)):
                    issues.append('Fitness active cancellation preceded confirmed preparation: ' + case)
            if case == 'pickup-cancel-restore' and command.get('propEquipObserved') is not False:
                issues.append('Fitness canceled pickup still equipped workout prop: ' + case)
        if case == 'pickup-cancel-restore' and not native:
            if not _exhaustion_without_training(prep['before'], receipt.get('clinical')):
                issues.append('Fitness canceled pickup changed native training effects: ' + case)
        if case == 'pickup-cancel-restore':
            pickup = command.get('pickupCancel', {})
            if (not _matches(command, dict(pickupCancelled=True))
                    or not _matches(pickup, dict(id=items['dumbbell'], kind='Base.DumbBell', source=items['bag'], destination='root', started=True))
                    or not _number(pickup.get('progress')) or not 0 < pickup['progress'] < 1
                    or type(pickup.get('transaction')) is not int or pickup['transaction'] < (1 if mp else 0)):
                issues.append('Fitness cancellation did not target exact in-flight native pickup: ' + case)
        if mp:
            tail_start = receipt.get('tailStart', {})
            if (not _matches(tail_start, dict(id=items['tail'], kind='Base.BookFirstAid1', callback='ISReadABook.serverStart',
                                             workouts=len(exercises), observerActive=False))
                    or not _inventory(tail_start.get('inventory'))
                    or not isinstance(tail_start.get('activation'), dict)
                    or not native and (not _same(tail_start['inventory'], expected)
                                       or not _same(tail_start['activation'], prep['activation']))):
                issues.append('Fitness authoritative reader callback lacked restored live Host replicas: ' + case)
    last_stop = None
    for record in records:
        before, after, rep = record.get('before'), record.get('after'), record.get('lastRep')
        valid = (_matches(record, dict(minutes=minutes, maxTime=5000000, previousStopSettled=True,
                                        currentExerciseCleared=True, serverStopReturned=True))
                 and type(record.get('reps')) is int and record['reps'] > 0
                 and all(_clinical(value) for value in (before, after, rep))
                 and all(record.get('exercise') in value['regularity'] for value in (before, after, rep))
                 and all(_number(record.get(key)) for key in ('startMS', 'stopMS', 'lastRepMS', 'minEndurance')))
        if valid:
            duration = record['stopMS'] - record['startMS']
            valid = (duration > 0 and record['startMS'] <= record['lastRepMS'] <= record['stopMS']
                     and record['minEndurance'] < before['endurance']
                     and rep['fitnessXP'] + rep['strengthXP'] > before['fitnessXP'] + before['strengthXP']
                     and rep['regularity'][record['exercise']] > before['regularity'][record['exercise']]
                     and any(rep['stiffness'][key] > before['stiffness'][key] for key in
                             (('legs',) if record['exercise'] == 'squats' else ('arms',)))
                     and all(after[key] >= rep[key] for key in ('fitnessXP', 'strengthXP'))
                     and (last_stop is None or record['startMS'] >= last_stop)
                     and (duration < 600000 if case in ('active-cancel', 'active-cancel-restore') else duration >= minutes * 60000))
            last_stop = record['stopMS']
        if not valid:
            issues.append('Fitness lacks real native repetitions/XP/endurance/stiffness or full duration: ' + case)
    if records and _clinical(receipt.get('clinical')) and _clinical(records[-1].get('after')):
        if any(receipt['clinical'][key] != records[-1]['after'][key] for key in ('fitnessXP', 'strengthXP')):
            issues.append('Fitness clinical XP changed after native stop settled: ' + case)
    if not records and case != 'exhaustion' and _clinical(receipt.get('clinical')):
        if any(receipt['clinical'][key] != prep['before'][key] for key in ('fitnessXP', 'strengthXP')):
            issues.append('Fitness rejected workout changed XP: ' + case)
    if mp:
        if (not _matches(receipt, {'peerRead': True, 'peerBook': prep.get('peerBook'), 'peerOnlineID': prep.get('peerOnlineID')})
                or type(prep.get('peerBook')) is not int or type(prep.get('peerOnlineID')) is not int or prep['peerOnlineID'] < 0):
            issues.append('Fitness actual Host peer/independent reader differs: ' + case)
        if not native:
            starts, ends = command.get('activeAcks'), command.get('terminalAcks')
            if (not isinstance(starts, list) or len(starts) != len(exercises) or len(set(starts)) != len(starts)
                    or not isinstance(ends, list) or [entry.get('token') for entry in ends] != starts
                    or any(entry.get('state') not in ('completed', 'canceled') for entry in ends)):
                issues.append('Fitness native started/terminal acknowledgement evidence differs: ' + case)
    return issues


def _recoveries(text, actor, selection, results):
    raw = [(match.start(), json.loads(match[1])) for match in re.finditer(r'\[FITNESS_TEST\] RECOVERY\s+([^\n]*)', text)]
    expected = [row['id'] for row in results if selection['mode'] == 'native'
                and row.get('id') in ('missing-dumbbell', 'exhaustion') and row.get('status') == 'failed'
                and row.get('receipt', {}).get('currentExerciseCleared') is False
                and row.get('receipt', {}).get('records') == []
                and (actor == 'server' or row.get('command', {}).get('clientCurrentExerciseCleared') is False)]
    issues = []
    if [row.get('case') for _, row in raw] != expected:
        issues.append('Fitness recovery case/order differs for ' + actor)
    for position, row in raw:
        case = row.get('case')
        observed = next((entry for entry in results if entry.get('id') == case), {})
        if (case not in expected or not _matches(row, dict(mode='native', actor=actor, failedCaseRecorded=True,
                queueEmpty=True, nativeActions=0, observerRecords=0, observerActive=False, exactObjectMatched=True, cleared=True))
                or not _clinical(row.get('before')) or not _same(row.get('before'), row.get('after'))
                or not _inventory(row.get('inventoryBefore')) or not _same(row.get('inventoryBefore'), row.get('inventoryAfter'))):
            issues.append('Fitness recovery idle/identity/clinical witness differs: ' + str(case))
        # Server VERIFIED is its durable failed state; the client must publish its
        # actual failed case before making the fixture-only mutation.
        prefix = '[FITNESS_TEST] VERIFIED ' if actor == 'server' else '[QUEUE_CHECK] '
        preceding = text[:position].splitlines()
        prior = [json.loads(line.split(prefix, 1)[1]) for line in preceding if prefix in line]
        if actor == 'server':
            published = any(entry.get('case') == case and entry.get('currentExerciseCleared') is False
                            and entry.get('records') == [] for entry in prior)
        else:
            published = any(entry.get('event') == 'case' and entry.get('id') == case and entry.get('status') == 'failed'
                            and entry.get('receipt', {}).get('currentExerciseCleared') is False for entry in prior)
        if not published or not observed:
            issues.append('Fitness recovery preceded recorded failure: ' + str(case))
    return issues, [row for _, row in raw]


def verify(root, selection, catalog):
    from ..report import events
    root = Path(root)
    text = (root / 'client1-launch.log').read_text(errors='replace')
    authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
    rows = events(text)
    cases = selection['cases']
    results = [row for row in rows if row['event'] == 'case']
    raw = [(match[1], json.loads(match[2])) for match in re.finditer(r'\[FITNESS_TEST\] (PREPARED|MUTATED|VERIFIED)\s+([^\n]*)', authority)]
    issues, outcomes = [], []
    if ([row.get('event') for row in rows] != ['setup'] + ['case'] * len(cases) + ['complete']
            or [row.get('id') for row in results] != cases
            or any(not _matches(row, dict(suite='fitness', actor='client1', kind=selection['kind'], mode=selection['mode'])) for row in rows)):
        issues.append('Fitness structured event order/context differs')
    for event, expected in [('setup', dict(cases=cases, expected=len(cases), nativeDurations=True, queueEnabled=selection['mode']=='toolkit')),
                            ('complete', dict(cases=cases, expected=len(cases), performed=len(cases), skipped=0, failed=sum(row.get('status') == 'failed' for row in results)))]:
        found = [row for row in rows if row.get('event') == event]
        if len(found) != 1 or not _matches(found[0], expected):
            issues.append('Fitness ' + event + ' differs')
    expected_order = [(marker, case) for case in cases for marker in (
        ('PREPARED', 'MUTATED', 'VERIFIED') if case in ('missing-dumbbell', 'exhaustion') else ('PREPARED', 'VERIFIED'))]
    if [(marker, row.get('case')) for marker, row in raw] != expected_order:
        issues.append('Fitness authority receipt order differs')
    if not complete(selection, 'client1', text):
        issues.append('Fitness completion missing or duplicated')
    peer_rows = []
    if selection['kind'] == 'mp':
        peer = (root / 'client2-launch.log').read_text(errors='replace')
        peer_rows = events(peer)
        if (not complete(selection, 'client2', peer) or [row.get('id') for row in peer_rows] != cases
                or any(not _matches(row, dict(event='case', suite='fitness', kind='mp', mode=selection['mode'], actor='client2',
                                             read=True, queueDrained=True)) for row in peer_rows)):
            issues.append('Fitness second actual Host client evidence differs')
        if '[QUEUE_TEST] FAIL ' in peer:
            issues.append('Fitness peer fixture failed')
    recovery_issues, recovery_proofs = _recoveries(text, 'client1', selection, results)
    issues.extend(recovery_issues)
    if selection['kind'] == 'mp':
        server_issues, server_recoveries = _recoveries(authority, 'server', selection, results)
        issues.extend(server_issues);recovery_proofs.extend(server_recoveries)
    used_ids = []
    for case in cases:
        row = next((row for row in results if row.get('id') == case), {})
        values = {marker: value for marker, value in raw if value.get('case') == case}
        prep, receipt = values.get('PREPARED', {}), values.get('VERIFIED', {})
        problems = _case(case, row, prep, receipt, selection, values.get('MUTATED'))
        if selection['kind'] == 'mp':
            found = [row for row in peer_rows if row.get('id') == case]
            if len(found) != 1 or found[0].get('book') != prep.get('peerBook'):
                problems.append('Fitness peer exact book identity differs: ' + case)
        used_ids.extend(prep.get('items', {}).values())
        issues.extend(problems)
        outcome = dict(effectsVerified=not problems, serverAuthorityVerified=not problems and selection['kind']=='mp',
            emptyStartVerified=not problems and case=='empty', queuedStartVerified=not problems and case=='queued',
            sequentialVerified=not problems and case=='sequential', waitingCancelVerified=not problems and case=='pending-cancel' and selection['mode']=='toolkit',
            independentMoveVerified=not problems and case=='pending-reorder' and selection['mode']=='toolkit',
            activeCancelVerified=not problems and case in ('active-cancel', 'active-cancel-restore'), missingItemVerified=not problems and case=='missing-dumbbell',
            restoreVerified=not problems and case in BORROWED_CASES, receipt=receipt, command=row.get('command'))
        outcomes.append(dict(actor='client1', case=case, status='failed' if problems else 'passed', reason='; '.join(problems), outcome=outcome))
    if len(set(used_ids)) != len(used_ids):
        issues.append('Fitness fixture IDs overlap between cases')
    if '[QUEUE_TEST] FAIL ' in text or '[QUEUE_TEST] FAIL ' in authority:
        issues.append('Native fitness fixture failed')
    if selection['kind'] == 'mp':
        # The second participant proves its independent reader inside the same joint
        # scenario. It is never represented as a second workout actor.
        peers = []
        for result in outcomes:
            peer_result = copy.deepcopy(result)
            peer_result['actor'] = 'client2'
            peer_result['outcome'].update(participantRole='independent-reader', workoutActor='client1')
            peers.append(peer_result)
        outcomes.extend(peers)
    shared = [issue for issue in issues if not any(issue.endswith(': ' + case) for case in cases)]
    if shared:
        for outcome in outcomes:
            outcome.update(status='failed', reason='; '.join([*shared, outcome['reason']]).strip('; '))
            outcome['outcome'].update(effectsVerified=False, serverAuthorityVerified=False)
    return dict(issues=issues, outcomes=outcomes, evidence={'recoveries': recovery_proofs, 'limits': [
        'Programmatic native Fitness OK callbacks; physical mouse/controller input is not covered.',
        'Native ten-minute workouts and real native repetitions/XP; no time or action acceleration.',
        'Host uses two actual clients; the peer reads an independent exact-ID native book.',
        'Full selected pack only; native controls can fail and those failures remain visible.']})
