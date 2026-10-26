"""Native fitness menu requests and clinical effects, with a real Host peer."""
import copy
import json
import math
import os
import subprocess
import zipfile
from pathlib import Path
import re
import shutil

from ..mod_selection import metadata, mod_ids

CASES = ['empty', 'queued', 'sequential', 'pending-cancel', 'pending-reorder', 'active-cancel',
         'missing-dumbbell', 'exhaustion', 'closed-ui-restore', 'burpees-30', 'squats-30', 'late-exhaustion', 'active-cancel-restore', 'pickup-cancel-restore', 'placement-cancel-restore', 'empty-restore', 'multi-storage', 'multi-storage-closed', 'storage-walk-away', 'storage-peer-pickup']
PROJECT = Path(__file__).resolve().parents[3]
MODS = mod_ids(metadata(PROJECT / 'SurvivorQoL-selected.ini')['Mods'])
SCENARIO_ACTIONS = {'fitness-ui': {
    'scope': 'Actual ISFitnessUI OK; native menu-duration squats/pushups/biceps curl and burpees (including natural exhaustion), long native reader, exact held/worn IDs, and authoritative real repetitions/clinical changes. Host uses a second actual independent reader.',
    'checks': {
        'success-empty': {'empty': {'effectsVerified': True, 'emptyStartVerified': True}},
        'success-queued': {'queued': {'effectsVerified': True, 'queuedStartVerified': True},
                           'sequential': {'effectsVerified': True, 'sequentialVerified': True}},
        'cancel-waiting': {'pending-cancel': {'effectsVerified': True, 'waitingCancelVerified': True}},
        'move-independent': {'pending-reorder': {'effectsVerified': True, 'independentMoveVerified': True}},
        'cancel-active': {'active-cancel': {'effectsVerified': True, 'activeCancelVerified': True}},
        'lost-before-start': {'missing-dumbbell': {'effectsVerified': True, 'missingItemVerified': True}},
        'restore-hands': {case: {'effectsVerified': True, 'restoreVerified': True}
                          for case in ('closed-ui-restore', 'multi-storage', 'multi-storage-closed')},
        'server-authority': {'sequential': {'effectsVerified': True, 'serverAuthorityVerified': True}},
    },
    'toolkit_only': ['cancel-waiting', 'move-independent', 'lost-before-start'],
}}


def definitions():
    return {'fitness': {'status': 'ready', 'clients': 2, 'default_mods': list(MODS),
        'scenario_actions': SCENARIO_ACTIONS,
        'cases': [dict(id=case, producer='fitness-ui', capability='effect', kinds=['mp'] if case=='storage-peer-pickup' else ['sp', 'mp'],
                       languages=['EN', 'RU'], modes=['native', 'toolkit']) for case in CASES]}}


def validate(selection):
    delay = selection.get('options', {}).get('fitness_receipt_delay_ms')
    if delay is not None and (type(delay) is not int or not 50 <= delay <= 1000
            or selection.get('kind') != 'mp' or selection.get('options', {}).get('fitness_diagnostics') is not True):
        raise ValueError('Fitness receipt delay requires diagnostic Host and 50..1000 integer milliseconds')
    cases = selection.get('cases')
    toggles = selection.get('options', {}).get('fitness_editor_toggles')
    if toggles is not None and (type(toggles) is not dict or not toggles
            or any(case not in RESTORATION_CASES or type(cases) is not list or case not in cases
                   or variant not in ('off-after-cancel', 'reenable-during-cleanup') for case, variant in toggles.items())):
        raise ValueError('Fitness editor toggles require selected restoration case IDs and an explicit supported variant')
    kind = selection.get('kind')
    clients = selection.get('clients', 2 if kind == 'mp' else 1)
    languages = selection.get('languages')
    if (type(cases) is not list or not cases or cases != [case for case in CASES if case in cases]
            or kind not in ('sp', 'mp') or kind=='sp'and 'storage-peer-pickup'in cases or selection.get('mode') not in ('native', 'toolkit')
            or type(clients) is not int or clients != (2 if kind == 'mp' else 1)
            or (languages not in (['EN'], ['RU']) if kind == 'sp' else languages != ['EN', 'RU'])
            or selection.get('mods') != MODS or selection.get('options', {}).get('world_template')
            or kind == 'mp' and selection.get('options', {}).get('mp_host') is not True):
        raise ValueError('Fitness requires ordered cases, fresh full selected pack, SP one EN/RU client or real two-client EN/RU Host, native/toolkit mode')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted(path for path in (root / 'fitness').rglob('*') if path.suffix in ('.lua', '.java')), root / 'health/shared/QueueHealthEvents.lua',
            root / 'startup/client/ZZStartup.lua', root / 'startup/server/ZZStartupServer.lua',
            Path(project) / 'tools/queue_checks/adapters/fitness_storage.py',
            Path(project) / 'tools/queue_checks/adapters/fitness_negative.py']


def _validity_probe(project, output, game, jdk, locations):
    classes = Path(output) / 'fitness-probe/classes'
    classes.mkdir(parents=True)
    classpath = os.pathsep.join(map(str, [Path(game) / 'projectzomboid.jar', Path(game) / 'ZombieBuddy.jar',
                                        Path(locations['PZToolkitJavaPatches']) / '42/media/java/PZToolkitJavaPatches.jar']))
    subprocess.run([str(Path(jdk) / 'bin/javac'), '--release', '25', '-cp', classpath, '-d', str(classes),
                    str(Path(project) / 'tests/native_queue/fitness/java/Main.java')],
                   check=True, capture_output=True, text=True, timeout=60)
    compiled = sorted(classes.rglob('*.class'))
    if not compiled:
        raise ValueError('Fitness validity probe compilation produced no classes')
    jar = classes.parent / 'FitnessValidityProbe.jar'
    with zipfile.ZipFile(jar, 'x', zipfile.ZIP_DEFLATED) as archive:
        for path in compiled:
            archive.write(path, path.relative_to(classes).as_posix())
    return jar


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    probe = _validity_probe(project, output, game, jdk, locations) if selection.get('options', {}).get('fitness_diagnostics') is True else None
    if probe:
        runtime.setdefault('fixture', {})['mods'] = ['FitnessValidityProbe']
    for role in runtime['roles'].values():
        if probe:
            layer = Path(role['cache']) / 'mods/FitnessValidityProbe/42'
            (layer / 'media/java').mkdir(parents=True, exist_ok=True)
            (layer / 'mod.info').write_text('name=Isolated Fitness validity probe\nid=FitnessValidityProbe\nversionMin=42.21\n'
                                          'require=\\ZombieBuddy\njavaPkgName=net.alexredby.fitnessprobe\n'
                                          'javaJarFile=media/java/FitnessValidityProbe.jar\n')
            shutil.copy2(probe, layer / 'media/java/FitnessValidityProbe.jar')
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


RESTORATION_CASES = ('active-cancel-restore', 'pickup-cancel-restore', 'placement-cancel-restore')
ACTIVE_CANCEL_CASES = ('active-cancel', 'active-cancel-restore')
EARLY_CANCEL_CASES = ('pickup-cancel-restore', 'placement-cancel-restore')
IMMEDIATE_CASES = ('empty', 'empty-restore', 'active-cancel', 'burpees-30', 'squats-30', 'late-exhaustion', 'multi-storage', 'multi-storage-closed', *RESTORATION_CASES)
BORROWED_CASES = ('closed-ui-restore', 'empty-restore', *RESTORATION_CASES)


def _expected_exercises(case, mode):
    if case == 'exhaustion' or mode == 'toolkit' and case in ('pending-cancel', 'missing-dumbbell', *EARLY_CANCEL_CASES):
        return []
    if case in ('multi-storage', 'multi-storage-closed'):
        return ['bicepscurl']
    if case in ('burpees-30', 'squats-30', 'late-exhaustion'):
        return ['squats' if case == 'squats-30' else 'burpees']
    return ['squats', 'pushups'] if case == 'sequential' else ['bicepscurl' if case in ('missing-dumbbell', *BORROWED_CASES) else 'squats']


def _storage(value, prep, endpoint, fetched):
    items = prep['items']
    contents = [row for row in prep['inventory']['items'] if row['container'] == items['bag']
                and (not fetched or row['id'] != items['dumbbell'])]
    if (not _matches(value, dict(id=items['bag'], kind='Base.Bag_Schoolbag', favorite=prep['case'] in RESTORATION_CASES,
                                 endpoint=endpoint, occurrences=1, contents=contents))):
        return False
    world = value.get('world')
    return (world is False if endpoint == 'root' else isinstance(world, dict)
            and set(world) == {'x', 'y', 'z', 'linked'} and world['linked'] is True
            and all(type(world[key]) is int for key in ('x', 'y', 'z')))


def _ground_conservation(value, prep):
    inventory = value.get('inventory', {})
    bag, prop = prep['items']['bag'], prep['items']['dumbbell']
    expected = [dict(row, container='root') if row['id'] == prop else row
                for row in prep['inventory']['items'] if row['id'] != bag and (row['container'] != bag or row['id'] == prop)]
    return (_storage(value.get('storage'), prep, 'world', True) and _inventory(inventory)
            and _same(inventory['items'], expected))


def _empty_restore_clock(record, command, minutes, native, mp):
    local, observed = command.get('nativeWorkoutClock', {}), record.get('nativeClock', {})
    if (not all(_number(local.get(key)) for key in ('constructorStartMS', 'deadlineMS', 'observedBodyStartMS', 'observedRemovalMS'))
            or not _matches(local, dict(source='actual started ISFitnessAction',
                constructorStartAtRemovalMS=local['constructorStartMS'], deadlineAtRemovalMS=local['deadlineMS']))
            or not _matches(observed, dict(source='ISFitnessAction.serverStart' if mp else 'SP first started sample'))
            or not _number(observed.get('observedBodyStartMS')) or observed['observedBodyStartMS'] != record.get('startMS')):
        return False
    # The active client deadline begins at actual/confirmed body start.
    # Constructor telemetry remains a separate request-time observation.
    if (local['deadlineMS'] - local['constructorStartMS'] != minutes * 60000
            or not local['constructorStartMS'] <= local['observedBodyStartMS'] < local['deadlineMS']
            or local['observedRemovalMS'] < local['deadlineMS']):
        return False
    if native:
        request = command.get('requestNativeClock', {})
        if (not isinstance(request, dict)
                or not all(_number(request.get(key)) for key in ('constructorStartMS', 'deadlineMS'))
                or request['deadlineMS'] - request['constructorStartMS'] != minutes * 60000
                or request['constructorStartMS'] > local['constructorStartMS']):
            return False
    # Host constructor fields are telemetry when the native server supplies
    # them. Missing replication cannot redefine the client's deadline contract.
    fields = ('constructorStartMS', 'deadlineMS', 'constructorStartAtStopMS', 'deadlineAtStopMS')
    if all(_number(observed.get(key)) for key in fields):
        if (observed['deadlineMS'] - observed['constructorStartMS'] != minutes * 60000
                or observed['constructorStartMS'] != observed['constructorStartAtStopMS']
                or observed['deadlineMS'] != observed['deadlineAtStopMS']):
            return False
    elif not mp:
        return False
    if not mp and (observed['constructorStartMS'] != local['constructorStartMS']
            or observed['deadlineMS'] != local['deadlineMS'] or record['stopMS'] < local['deadlineMS']):
        return False
    return True


def _post_stop_xp(record, receipt, mp):
    """Account native-passive-compatible AddXP events; the event has no caller identity."""
    ledger = record.get('postStopXP', {})
    entry = record.get('stopEntry', {})
    if (not isinstance(ledger, dict) or ledger.get('error') is not None
            or not _clinical(ledger.get('baseline')) or not _same(ledger['baseline'], entry.get('clinical'))
            or not isinstance(ledger.get('events'), list) or type(record.get('afterXPEventCount')) is not int
            or not 0 <= record['afterXPEventCount'] <= len(ledger['events'])
            or not all(_number(receipt.get(key)) for key in ('receiptCalendarMS', 'receiptDurationMS'))):
        return False
    if (not _number(record.get('stopMS')) or not _number(record.get('durationStopMS'))
            or receipt['receiptCalendarMS'] < record['stopMS']
            or receipt['receiptDurationMS'] < record['durationStopMS']):
        return False
    # Server Lua has netAction, not the client's BaseAction pointer. Native
    # ActionManager removes its network action before serverStop and retires
    # its animation emulator after return; require the post-return boundary.
    if mp and (record['afterXPEventCount'] != 0 or record.get('stopMethod') != 'serverStop'
            or record.get('serverStopReturned') is not True
            or not _matches(record.get('stopCallbacks'), dict(serverStop=1))
            or record.get('stopCallbacks', {}).get('complete', 0) != 0):
        return False
    baseline = ledger['baseline']
    if any(baseline[key] != record.get('lastRep', {}).get(key) for key in ('fitnessXP', 'strengthXP')):
        return False
    running = {key: baseline[key] for key in ('fitnessXP', 'strengthXP')}
    after_xp = dict(running) if record['afterXPEventCount'] == 0 else None
    calendar, duration = entry.get('calendarMS'), entry.get('durationMS')
    if not _number(calendar) or not _number(duration):
        return False
    for index, event in enumerate(ledger['events'], 1):
        if (not _matches(event, dict(perk='Fitness', amount=1, currentExerciseCleared=True,
                                    reps=record.get('reps'), enduranceWarning=.25))
                or type(event.get('observerActive')) is not bool
                or (event['observerActive'] if mp else event.get('nativeAbsent') is not True)
                or not _clinical(event.get('clinical'))
                or not all(_number(event.get(key)) for key in ('calendarMS', 'durationMS'))
                or not calendar <= event['calendarMS'] <= receipt['receiptCalendarMS']
                or not duration <= event['durationMS'] <= receipt['receiptDurationMS']
                or event['clinical']['endurance'] >= event['enduranceWarning']
                or any(event['clinical'][group][key] > value for group in ('regularity', 'stiffness')
                       for key, value in baseline[group].items())):
            return False
        running['fitnessXP'] += event['amount']
        if any(event['clinical'][key] != running[key] for key in running):
            return False
        calendar, duration = event['calendarMS'], event['durationMS']
        if index <= record['afterXPEventCount']:
            if calendar > record.get('stopMS', -1) or duration > record.get('durationStopMS', -1):
                return False
        elif calendar < record.get('stopMS', float('inf')) or duration < record.get('durationStopMS', float('inf')):
            return False
        if index == record['afterXPEventCount']:
            after_xp = dict(running)
    return (after_xp is not None and _clinical(record.get('after')) and _clinical(receipt.get('clinical'))
            and all(record['after'][key] == after_xp[key] and receipt['clinical'][key] == running[key] for key in running)
            and all(snapshot[group][key] <= value for snapshot in (record['after'], receipt['clinical'])
                    for group in ('regularity', 'stiffness') for key, value in baseline[group].items()))


def _late_exhaustion(command, receipt, mp, native, tail_id, minutes):
    """A partial earned workout is distinct from the strict full-duration control."""
    issues = []
    records = receipt.get('records')
    local = command.get('exhaustionStop', {})
    if not isinstance(local, dict):
        return ['Fitness late exhaustion missing local stop witness: late-exhaustion']
    state, timing = local.get('state', {}), local.get('timing', {})
    if not isinstance(state, dict) or not isinstance(timing, dict):
        return ['Fitness late exhaustion malformed local stop witness: late-exhaustion']
    stops = command.get('durationStops')
    stop = stops[0] if isinstance(stops, list) and len(stops) == 1 else {}
    record = records[0] if isinstance(records, list) and len(records) == 1 else {}

    def exhausted(value, authority=False):
        return (isinstance(value, dict)
                and _matches(value, dict(type='ISFitnessAction', exercise='burpees', minutes=minutes,
                    pressedMovement=False, moving=False, aiming=False, climbing=False, sittingFurniture=False,
                    vehicle=False, dead=False, asleep=False, pressedCancel=False))
                and (value.get('threshold') is False if authority and mp else value.get('threshold') == 2)
                # serverStop does not refresh or evaluate this cached UI value.
                and type(value.get('enduranceMoodle')) is int
                and (0 <= value['enduranceMoodle'] <= 4 if authority and mp else 2 < value['enduranceMoodle'] <= 4)
                and _clinical(value.get('clinical')) and value['clinical']['endurance'] < .25
                and _number(value.get('calendarMS')) and _number(value.get('durationMS')))

    if (not exhausted(state) or not _matches(state, dict(exerciseStarted=False, exerciseEnded=True, started=True))
            or not _number(local.get('timestampMilliseconds'))
            or not _matches(timing, dict(confirmed=True, stopping=mp and not native, total=minutes))
            or not all(_number(timing.get(key)) for key in ('startMS', 'endMS', 'stopMS', 'stopTimestampMS', 'worldSampleMS'))
            or not _matches(stop, dict(startMS=timing.get('startMS'), endMS=timing.get('endMS'),
                                      stopMS=timing.get('stopMS'), confirmed=True))
            or timing.get('endMS', 0) - timing.get('startMS', 0) != minutes * 60000
            or not 600000 < timing.get('stopMS', 0) - timing.get('startMS', 0) < minutes * 60000
            or not _number(state.get('durationMS')) or not _number(timing.get('stopMS'))
            or state['durationMS'] != timing['worldSampleMS']
            or command.get('cancelCallback') is not None or command.get('mutationObserved', False) is not False
            or command.get('activeCancelled') is not False
            or type(command.get('nativeStopCalls')) is not int or command['nativeStopCalls'] != 1
            or type(command.get('nativeStopReturns')) is not int or command['nativeStopReturns'] != 1
            or not _number(command.get('durationStopDelayMilliseconds'))
            or not 0 <= command['durationStopDelayMilliseconds'] < 5000):
        issues.append('Fitness late exhaustion lacks confirmed local endurance-only stop: late-exhaustion')

    entry = record.get('stopEntry', {})
    if (not exhausted(entry, authority=True)
            or not _number(record.get('stopMS')) or not _number(record.get('durationStopMS'))
            or not _number(record.get('lastRepMS')) or not _number(record.get('lastRepDurationMS'))
            or not _clinical(record.get('lastRepBefore')) or not _clinical(record.get('lastRep'))
            or not _number(entry.get('calendarMS')) or not _number(entry.get('durationMS'))
            or not record.get('lastRepMS', float('inf')) <= entry.get('calendarMS', -1) <= record.get('stopMS', -1)
            or not record.get('lastRepDurationMS', float('inf')) <= entry.get('durationMS', -1) <= record.get('durationStopMS', -1)
            or not record.get('lastRepBefore', {}).get('endurance', 0) > record.get('lastRep', {}).get('endurance', 0)
            or not 0 <= record.get('lastRep', {}).get('endurance', 1) < .25
            or any(record.get('lastRep', {}).get(key, 0) < record.get('lastRepBefore', {}).get(key, float('inf'))
                   for key in ('fitnessXP', 'strengthXP'))
            or not sum(record.get('lastRep', {}).get(key, 0) for key in ('fitnessXP', 'strengthXP'))
                > sum(record.get('lastRepBefore', {}).get(key, 0) for key in ('fitnessXP', 'strengthXP'))
            or record.get('repObservationSource') != ('server exeLooped' if mp else 'SP adjacent native samples')
            or type(record.get('repSampleDelta')) is not int or record['repSampleDelta'] != 1
            or type(record.get('lastRepEnduranceMoodle')) is not int or not 0 <= record['lastRepEnduranceMoodle'] <= 4
            or not _number(record.get('durationStartMS')) or not _number(timing.get('startMS'))
            or abs(record['durationStartMS'] - timing['startMS']) >= 60000
            or not _number(record.get('durationStopMS')) or not _number(timing.get('worldSampleMS'))
            or abs(record['durationStopMS'] - timing['worldSampleMS']) >= 60000
            or record.get('stopMethod') != ('serverStop' if mp else 'observed-native-removal')
            or mp and not _matches(record.get('stopCallbacks'), dict(serverStop=1))
            or mp and record.get('stopCallbacks', {}).get('complete', 0) != 0):
        issues.append('Fitness late exhaustion lacks authoritative paid repetitions/stop boundary: late-exhaustion')

    if not _post_stop_xp(record, receipt, mp):
        issues.append('Fitness exhaustion has unexplained post-stop XP/effects: late-exhaustion')

    pages, total = command.get('tailPagesAtRequest'), command.get('tailTotalPages')
    if (command.get('tailInitiallyQueued') is not True or type(pages) is not int or type(total) is not int
            or total - pages != 1 or command.get('tailPagesAtFinish') != (pages if native else total)):
        issues.append('Fitness exhaustion lost native/managed tail cancellation distinction: late-exhaustion')
    if not native:
        continuation = command.get('durationContinuation', {})
        if (not _matches(continuation, dict(callback='ISBaseTimedAction.begin', nativeAbsent=True, tailId=tail_id,
                workoutStartMS=timing.get('startMS'), workoutEndMS=timing.get('endMS'),
                stopNativeClock=timing.get('stopMS'), reachedNativeClock=timing.get('stopMS')))
                or not _number(continuation.get('continuationNativeClock'))
                or not _number(continuation.get('reachedTimestampMilliseconds'))
                or not _number(continuation.get('continuationTimestampMilliseconds'))
                or not _number(continuation.get('delayMilliseconds'))
                or not 0 <= continuation['delayMilliseconds'] < 5000
                or continuation['delayMilliseconds'] != continuation['continuationTimestampMilliseconds'] - continuation['reachedTimestampMilliseconds']
                or continuation['reachedTimestampMilliseconds'] != timing.get('stopTimestampMS')
                or continuation.get('continuationNativeClock', -1) < timing.get('stopMS', 0)
                or (command.get('activeAcks') != [continuation.get('token')]
                    or command.get('terminalAcks') != [dict(token=continuation.get('token'), state='canceled')]
                    or continuation.get('terminalState') != 'canceled'
                    or not isinstance(continuation.get('token'), str)) and mp):
            issues.append('Fitness exhaustion continuation preceded native removal/terminal: late-exhaustion')
        if not mp and not _matches(continuation, dict(terminalState='singleplayer', token=False)):
            issues.append('Fitness exhaustion single-player terminal identity differs: late-exhaustion')
    elif command.get('durationContinuation') is not None:
        issues.append('Fitness native exhaustion unexpectedly continued the canceled tail: late-exhaustion')
    return issues


def _editor_case(case, command, prep, selection):
    variant = selection.get('options', {}).get('fitness_editor_toggles', {}).get(case)
    if variant is None:
        return [] if all(key not in command for key in ('editorTransitions', 'editorEnabled', 'editorCancelBoundary', 'editorCleanupBoundary')) else ['Fitness unexpected editor evidence: ' + case]
    native = selection['mode'] == 'native'
    transitions = command.get('editorTransitions')
    expected_count = 0 if native else 2 if variant == 'reenable-during-cleanup' else 1
    error = ['Fitness editor transition boundary/identity/order differs: ' + case]
    if (type(transitions) is not list or len(transitions) != expected_count
            or any(type(entry) is not dict for entry in transitions)
            or command.get('editorEnabled') is not (not native and expected_count == 2)):
        return error
    if native:
        return [] if 'editorCancelBoundary' not in command and 'editorCleanupBoundary' not in command else error
    cancel = command.get('editorCancelBoundary')
    cleanup = command.get('editorCleanupBoundary')
    fields = {'case', 'boundary', 'at', 'nativeClock', 'actionRef', 'currentRef', 'nativeRef', 'kind', 'itemId', 'itemType',
              'token', 'generation', 'tailRef', 'tailId', 'tailRetained', 'requestRetained', 'drainingAction', 'requiredStep'}
    items = prep['items']
    def witness(value, boundary):
        return (type(value) is dict and set(value) == fields
                and _matches(value, dict(case=case, boundary=boundary, tailId=items['tail'], tailRetained=True))
                and all(isinstance(value.get(key), str) and value[key] for key in ('actionRef', 'currentRef', 'nativeRef', 'token', 'tailRef'))
                and value['currentRef'] == value['actionRef'] and value['tailRef'] != value['actionRef']
                and all(_number(value.get(key)) and value[key] >= 0 for key in ('at', 'nativeClock'))
                and type(value.get('generation')) is int and value['generation'] >= 0
                and type(value.get('requestRetained')) is bool)
    cancel_kind = {'active-cancel-restore': ('ISFitnessAction', False, False),
                   'pickup-cancel-restore': ('ISInventoryTransferAction', items['dumbbell'], 'Base.DumbBell'),
                   'placement-cancel-restore': ('ISDropWorldItemAction', items['bag'], 'Base.Bag_Schoolbag')}[case]
    if (not witness(cancel, 'accepted-cancel') or not _matches(cancel, dict(requestRetained=True, drainingAction=True, requiredStep=False,
            **dict(zip(('kind', 'itemId', 'itemType'), cancel_kind))))):
        return error
    witnesses = [cancel]
    if expected_count == 2:
        allowed_items = {items['dumbbell']: 'Base.DumbBell', items['bag']: 'Base.Bag_Schoolbag',
                         items['hammer']: 'Base.Torch', items['screwdriver']: 'Base.Screwdriver'}
        if (not witness(cleanup, 'cleanup-current') or not _matches(cleanup, dict(drainingAction=True, requiredStep=True, requestRetained=False))
                or cleanup['actionRef'] == cancel['actionRef'] or cleanup['token'] == cancel['token']
                or cleanup['tailRef'] != cancel['tailRef'] or cleanup['generation'] != cancel['generation'] + 1
                or cleanup['at'] <= transitions[0].get('at', float('inf'))
                or cleanup['nativeClock'] < cancel['nativeClock']
                or cleanup['kind'] not in ('ISInventoryTransferAction', 'ISUnequipAction', 'ISEquipWeaponAction', 'ISWearClothing', 'ISActivateItem')
                or type(cleanup['itemId']) is not int or allowed_items.get(cleanup['itemId']) != cleanup['itemType']):
            return error
        witnesses.append(cleanup)
    elif cleanup is not None:
        return error
    for i, (transition, boundary) in enumerate(zip(transitions, witnesses)):
        if (type(transition) is not dict or set(transition) != fields | {'enabled', 'generationBefore', 'generationAfter'}
                or not _matches(transition, {key: value for key, value in boundary.items() if key not in ('at', 'nativeClock')})
                or transition.get('enabled') is not bool(i)
                or not _number(transition.get('at')) or not boundary['at'] <= transition['at'] <= boundary['at'] + 50
                or not _number(transition.get('nativeClock')) or transition['nativeClock'] != boundary['nativeClock']
                or any(type(transition.get(key)) is not int for key in ('generationBefore', 'generationAfter'))
                or transition.get('generationBefore') != boundary['generation']
                # ModOption:setValue may only publish the value here. Native
                # begin/tick applies the one editor invalidation before cleanup.
                or transition.get('generationAfter') not in ((boundary['generation'], boundary['generation'] + 1)
                                                            if i == 0 else (boundary['generation'],))):
            return error
    return []


def _settled_case(case, command, prep, selection):
    requested = selection.get('options', {}).get('fitness_editor_toggles', {}).get(case)
    rows = command.get('settledLedgers')
    error = ['Fitness immutable settled cleanup ledger differs: ' + case]
    if not requested:
        return error if rows is not None else []
    if selection['mode'] == 'native':
        return [] if rows == [] else error
    roles = ['borrowed-return'] if case == 'pickup-cancel-restore' else ['carrier-recovery', 'borrowed-return']
    if not isinstance(rows, list) or len(rows) != len(roles) or any(type(row) is not dict for row in rows):
        return error
    fields = {'case', 'ordinal', 'boundary', 'source', 'at', 'nativeClock', 'role', 'kind', 'itemId', 'itemType',
              'actionRef', 'currentRef', 'nativeRef', 'token', 'generation', 'requiredStep', 'drainingAction',
              'completionState', 'originalState', 'actionState'}
    items = prep['items']
    cancel = command.get('editorCancelBoundary', {})
    tail = command.get('beforeTail', {})
    previous_at, previous_clock = cancel.get('at'), cancel.get('nativeClock')
    for ordinal, (row, role) in enumerate(zip(rows, roles), 1):
        item_id, item_type = (items['bag'], 'Base.Bag_Schoolbag') if role == 'carrier-recovery' else (items['dumbbell'], 'Base.DumbBell')
        original, action = row.get('originalState'), row.get('actionState')
        if (set(row) != fields or not _matches(row, dict(case=case, ordinal=ordinal, boundary='Lifecycle.settled',
                source='Settlement.operationState', role=role, kind='ISInventoryTransferAction', itemId=item_id, itemType=item_type,
                requiredStep=True, drainingAction=True, completionState='ready'))
                or not all(isinstance(row.get(key), str) and row[key] for key in ('actionRef', 'currentRef', 'nativeRef', 'token'))
                or row['actionRef'] != row['currentRef'] or row['actionRef'] == cancel.get('tailRef')
                or type(row.get('generation')) is not int or row['generation'] != cancel.get('generation', -2) + 1
                or not all(_number(row.get(key)) for key in ('at', 'nativeClock'))
                or not _number(previous_at) or row['at'] < previous_at
                or not _number(previous_clock) or row['nativeClock'] < previous_clock
                or not _number(tail.get('nativeClock')) or row['nativeClock'] > tail['nativeClock']
                or not isinstance(original, dict) or not isinstance(action, dict)
                or original.get('generation') != cancel.get('generation')
                or action.get('generation') not in (row['generation'] - 1, row['generation'])):
            return error
        expected_loan = [dict(id=items['dumbbell'], fullType='Base.DumbBell', state='active' if role == 'carrier-recovery' else 'completed')]
        if original.get('borrowings') != expected_loan:
            return error
        steps = action.get('steps')
        if not isinstance(steps, list):
            return error
        matched = [step for step in steps if isinstance(step, dict) and _matches(step,
            dict(kind='ISInventoryTransferAction', itemId=item_id, itemType=item_type, state='earned', started=True,
                 phase='cleanup', plannedTransfer=True)) and (step.get('transferDirection') == 'pickup' if role == 'carrier-recovery'
                                                            else step.get('transferDirection') is None)]
        if len(matched) != 1:
            return error
        if role == 'carrier-recovery':
            recovery = command.get('recoverySettlements')
            if not isinstance(recovery, list) or len(recovery) != 1 or not _same(recovery[0], action):
                return error
            starts = command.get('recoveryStarts', [])
        else:
            if not _same(command.get('settlement'), original) or command.get('confirmedReturn') is not True:
                return error
            starts = command.get('returnStarts', [])
        if (not isinstance(starts, list) or len(starts) != 1 or not _number(starts[0].get('nativeClock'))
                or row['nativeClock'] < starts[0]['nativeClock']):
            return error
        boundary = command.get('editorCleanupBoundary', {})
        if boundary.get('kind') == row['kind'] and boundary.get('itemId') == item_id and boundary.get('nativeRef') != row['nativeRef']:
            return error
        previous_at, previous_clock = row['at'], row['nativeClock']
    if len({row['actionRef'] for row in rows}) != len(rows) or len({row['nativeRef'] for row in rows}) != len(rows):
        return error
    return []


def _settled_logs(text, results, selection):
    ledgers = [row.get('command', {}).get('settledLedgers', []) for row in results]
    if any(not isinstance(entries, list) for entries in ledgers):
        return ['Fitness raw settled ledger evidence differs']
    expected = [entry for entries in ledgers for entry in entries]
    found = [json.loads(match[1]) for match in re.finditer(r'\[FITNESS_TEST\] SETTLED_LEDGER\s+([^\n]*)', text)]
    if found != expected:
        return ['Fitness raw settled ledger evidence differs']
    active, emitted = None, set()
    for line in text.splitlines():
        if '[FITNESS_TEST] EDITOR_CANCEL ' in line:
            value = json.loads(line.split('[FITNESS_TEST] EDITOR_CANCEL ', 1)[1])
            active = value.get('case')
        elif '[FITNESS_TEST] SETTLED_LEDGER ' in line:
            value = json.loads(line.split('[FITNESS_TEST] SETTLED_LEDGER ', 1)[1])
            if value.get('case') != active or active in emitted:
                return ['Fitness raw settled ledger boundary/publication order differs']
        elif '[QUEUE_CHECK] ' in line:
            value = json.loads(line.split('[QUEUE_CHECK] ', 1)[1])
            if value.get('event') == 'case':
                emitted.add(value.get('id'));active = None
    return []


def _editor_logs(text, results, selection):
    # Compare the independent marker stream as well as the final command. Each
    # transition must follow its own live boundary and precede its published row.
    expected = []
    for row in results:
        command = row.get('command', {})
        if selection.get('options', {}).get('fitness_editor_toggles', {}).get(row.get('id')) and selection['mode'] == 'toolkit':
            transitions = command.get('editorTransitions', [])
            if type(transitions) is not list:
                return ['Fitness raw editor transition evidence differs']
            expected.append(('EDITOR_CANCEL', command.get('editorCancelBoundary')))
            if transitions:
                expected.append(('EDITOR_TRANSITION', transitions[0]))
            if len(transitions) > 1:
                expected.extend([('EDITOR_CLEANUP', command.get('editorCleanupBoundary')), ('EDITOR_TRANSITION', transitions[1])])
    actual = [(match[1], json.loads(match[2])) for match in re.finditer(
        r'\[FITNESS_TEST\] (EDITOR_CANCEL|EDITOR_CLEANUP|EDITOR_TRANSITION)\s+([^\n]*)', text)]
    if actual != expected:
        return ['Fitness raw editor transition evidence differs']
    context = None
    pending = list(actual)
    for line in text.splitlines():
        if '[FITNESS_TEST] EDITOR_' in line:
            marker, value = pending.pop(0)
            if context is not None and context != value.get('case'):
                return ['Fitness raw editor transition case order differs']
            context = value.get('case')
        if '[QUEUE_CHECK] ' in line:
            row = json.loads(line.split('[QUEUE_CHECK] ', 1)[1])
            if row.get('event') == 'case':
                requested = selection.get('options', {}).get('fitness_editor_toggles', {}).get(row.get('id'))
                if context != (row.get('id') if requested and selection['mode'] == 'toolkit' else None):
                    return ['Fitness raw editor transition publication order differs']
                context = None
    return [] if context is None else ['Fitness raw editor transition follows final evidence']


def _case(case, row, prep, receipt, selection, mutation=None):
    if case in ('storage-walk-away','storage-peer-pickup'):
        from .fitness_negative import verify_negative
        return verify_negative(case,row,prep,receipt,selection)
    issues = []
    native, mp = selection['mode'] == 'native', selection['kind'] == 'mp'
    minutes = (60 if mp else 30) if case == 'late-exhaustion' else 30 if case in ('burpees-30', 'squats-30') else 10
    command = row.get('command', {})
    native_active_cancel = native and case in ACTIVE_CANCEL_CASES
    items = prep.get('items', {})
    if (not _matches(prep, {'case': case}) or not isinstance(items, dict)
            or set(items) != {'front', 'tail', 'bag', 'hammer', 'screwdriver', 'dumbbell'}
            or any(type(value) is not int for value in items.values()) or len(set(items.values())) != 6
            or not _inventory(prep.get('inventory')) or not _clinical(prep.get('before'))):
        return ['Fitness exact preparation differs: ' + case]
    issues.extend(_editor_case(case, command, prep, selection))
    issues.extend(_settled_case(case, command, prep, selection))
    expected = copy.deepcopy(prep['inventory'])
    if case == 'missing-dumbbell':
        expected['items'] = [item for item in expected['items'] if item['id'] != items['dumbbell']]
    if (not _inventory(receipt.get('inventory')) or not _same(receipt['inventory'], expected)
            or not _same(command.get('clientInventory'), expected)):
        issues.append('Fitness exact inventory/container/hand/worn identities differ: ' + case)
    if (not _matches(receipt, {'case': case, 'tailRead': not (native and (case == 'late-exhaustion' or case in ACTIVE_CANCEL_CASES)), 'frontRead': case not in IMMEDIATE_CASES,
                               'currentExerciseCleared': True, 'serverStopSettled': True, 'peerConnected': True,
                               'removed': items['dumbbell'] if case == 'missing-dumbbell' else False})
            or not _same(receipt.get('before'), prep['before']) or not _clinical(receipt.get('clinical'))
            or not _matches(row, {'status': 'passed', 'reason': None, 'receipt': receipt})
            or not _number(receipt.get('serverSettleMilliseconds')) or receipt['serverSettleMilliseconds'] < 2000):
        issues.append('Fitness authoritative settled effects/independent tail differ: ' + case)
    expected_fields = dict(menuDispatched=True, nativeDurations=True, minutes=minutes, frontMinutes=0 if case in IMMEDIATE_CASES else 12,
        activeObserved=bool(_expected_exercises(case, selection['mode'])), queueDrained=True, clientCurrentExerciseCleared=True,
        pendingCancelled=not native and case == 'pending-cancel', reordered=not native and case == 'pending-reorder',
        activeCancelled=case in ('active-cancel', 'active-cancel-restore'), closedUI=case in ('closed-ui-restore', 'multi-storage-closed'))
    if case in ('burpees-30', 'squats-30'):
        delay = command.get('durationStopDelayMilliseconds')
        if not _number(delay) or not 0 <= delay < 5000:
            issues.append('Fitness native stop remained active after selected duration: ' + case)
        continuation = command.get('durationContinuation')
        continuation = continuation if isinstance(continuation, dict) else {}
        clocks = ('workoutStartMS', 'workoutEndMS', 'reachedNativeClock', 'stopNativeClock', 'reachedTimestampMilliseconds',
                  'continuationNativeClock', 'continuationTimestampMilliseconds', 'delayMilliseconds')
        local_stops = command.get('durationStops')
        first_stop = local_stops[0] if isinstance(local_stops, list) and local_stops and isinstance(local_stops[0], dict) else {}
        if (not _matches(continuation, dict(callback='ISBaseTimedAction.begin', tailId=items['tail'], nativeAbsent=True))
                or not all(_number(continuation.get(key)) for key in clocks)
                or not _number(first_stop.get('startMS'))
                or continuation.get('workoutStartMS') != first_stop['startMS']
                or continuation['workoutEndMS'] - continuation['workoutStartMS'] != minutes * 60000
                or continuation['reachedNativeClock'] < continuation['workoutEndMS']
                or continuation['stopNativeClock'] != continuation['reachedNativeClock']
                or continuation['stopNativeClock'] != first_stop.get('stopMS')
                or continuation['continuationNativeClock'] < continuation['reachedNativeClock']
                or continuation['reachedTimestampMilliseconds'] < 0
                or continuation['delayMilliseconds'] != continuation['continuationTimestampMilliseconds'] - continuation['reachedTimestampMilliseconds']
                or not 0 <= continuation['delayMilliseconds'] < 5000
                or not _number(delay) or delay > continuation['delayMilliseconds']):
            issues.append('Fitness queue continuation missing or delayed after selected duration: ' + case)
        if mp:
            token, terminal = continuation.get('token'), continuation.get('terminalState')
            if (not isinstance(token, str) or terminal not in ('canceled', 'completed')
                    or command.get('activeAcks') != [token]
                    or command.get('terminalAcks') != [dict(token=token, state=terminal)]):
                issues.append('Fitness continuation preceded exact authoritative terminal receipt: ' + case)
        elif not _matches(continuation, dict(terminalState='singleplayer', token=False)):
            issues.append('Fitness single-player continuation identity differs: ' + case)
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
    if native_active_cancel:
        witness = command.get('nativeActiveCancel', {})
        if (not _matches(command, dict(cancelCallback='ISFitnessUI:CANCEL', nativeStopCalls=1, nativeStopReturns=1))
                or any(type(command.get(key)) is not int for key in ('nativeStopCalls', 'nativeStopReturns'))
                or not _matches(witness, dict(callback='ISFitnessUI:CANCEL', kind='ISFitnessAction', started=True,
                                             tailId=items['tail'], tailRetained=True))
                or not all(isinstance(witness.get(key), str) and witness[key] for key in ('actionRef', 'nativeRef'))
                or not all(_number(witness.get(key)) and witness[key] >= 0 for key in ('at', 'nativeClock'))
                or type(witness.get('tailPages')) is not int or type(witness.get('tailTotalPages')) is not int
                or witness['tailTotalPages'] - witness['tailPages'] != 1
                or command.get('nativeTailPagesAtFinish') != witness['tailPages']
                or command.get('beforeTail') is not None or receipt.get('tailStart') is not None
                or command.get('durationStops') != []):
            issues.append('Fitness native explicit UI cancellation/tail discard evidence differs: ' + case)
        # SP shares this clock with its receipt. Host client and authority
        # clocks are independent; each authoritative partial interval is checked below.
        if (len(records) != 1 or not _number(witness.get('nativeClock'))
                or not _number(records[0].get('durationStartMS')) or not _number(records[0].get('durationStopMS'))
                or not mp and not records[0]['durationStartMS'] <= witness['nativeClock'] <= records[0]['durationStopMS']):
            issues.append('Fitness native UI cancel was outside its actual partial workout: ' + case)
    elif 'nativeActiveCancel' in command or 'nativeTailPagesAtFinish' in command:
        issues.append('Fitness unexpected native active cancellation witness: ' + case)
    stops = command.get('durationStops')
    if (not isinstance(stops, list) or len(stops) != (0 if native_active_cancel else len(exercises))
            or not native and (not isinstance(progress, list) or len(progress) != len(exercises))
            or isinstance(stops, list) and any(not isinstance(stop, dict)
                   or not all(_number(stop.get(key)) for key in ('startMS', 'endMS', 'stopMS'))
                   or type(stop.get('confirmed')) is not bool or stop['startMS'] < 0
                   or not native and (not isinstance(progress[index], dict) or stop['startMS'] != progress[index].get('startMS'))
                   or stop['endMS'] - stop['startMS'] != minutes * 60000
                   or stop['stopMS'] < stop['startMS']
                   or case not in ('active-cancel', 'active-cancel-restore', 'late-exhaustion')
                      and (stop['confirmed'] is not True or stop['stopMS'] < stop['endMS'])
                   for index, stop in enumerate(stops))):
        issues.append('Fitness actual local stop lacks a full confirmed selected interval: ' + case)
    if case == 'empty-restore':
        if (type(command.get('nativeStopCalls')) is not int or command['nativeStopCalls'] != 1
                or type(command.get('nativeStopReturns')) is not int or command['nativeStopReturns'] != 1):
            issues.append('Fitness natural terminal did not run native stop exactly once: ' + case)
        if mp and any(not isinstance(record.get('stopCallbacks'), dict)
                      or type(record['stopCallbacks'].get('serverStop')) is not int
                      or record['stopCallbacks']['serverStop'] != 1
                      or type(record['stopCallbacks'].get('complete', 0)) is not int
                      or record['stopCallbacks'].get('complete', 0) != 0 for record in records):
            issues.append('Fitness natural terminal replayed authoritative stop/completion effects: ' + case)
    if case == 'empty-restore' and (command.get('cancelCallback') is not None
            or command.get('pickupCancelled', False) is not False or command.get('placementCancelled', False) is not False):
        issues.append('Fitness empty restoration did not finish naturally without cancellation: ' + case)
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
    if case in (*RESTORATION_CASES, 'empty-restore'):
        for record in records:
            if not _ground_conservation(dict(storage=record.get('startStorage'), inventory=record.get('startEquipment')), prep):
                issues.append('Fitness authoritative workout lacked exact world bag/content conservation: ' + case)
    if case in BORROWED_CASES:
        # Natural empty-queue restoration owes the exact gear before the reader
        # in both modes; explicit native cancellation controls retain their evidence.
        expected_types = dict(front='Base.BookCarpentry1', tail='Base.BookFirstAid1', bag='Base.Bag_Schoolbag',
                              hammer='Base.Torch' if case in RESTORATION_CASES else 'Base.Hammer', screwdriver='Base.Screwdriver', dumbbell='Base.DumbBell')
        if (any(next((item for item in prep['inventory']['items'] if item['id'] == identity), {}).get('kind') != expected_types[name]
                for name, identity in items.items())
                or case in RESTORATION_CASES and not _same(prep.get('activation'), {str(items['hammer']): True})
                or not _storage(prep.get('storage'), prep, 'root', False)
                or case in RESTORATION_CASES and next((item for item in prep['inventory']['items'] if item['id'] == items['front']), {}).get('container') != items['bag']):
            issues.append('Fitness borrowed exact gear/type/activation setup differs: ' + case)
        before_tail = command.get('beforeTail', {})
        if not native_active_cancel and (before_tail.get('callback') != 'ISBaseTimedAction.begin' or not _inventory(before_tail.get('inventory')) or not _number(before_tail.get('nativeClock'))
                or not (isinstance(before_tail.get('activation'), dict) or before_tail.get('activation') == [])
                or case in RESTORATION_CASES and not _matches(command, dict(cancelCallback='ISFitnessUI:CANCEL' if native else 'ActionQueue.cancelOperation'))):
            issues.append('Fitness independent tail boundary/native cancel callback missing: ' + case)
        if (not _storage(receipt.get('storage'), prep, 'root', False)
                or not _storage(command.get('clientStorage'), prep, 'root', False)
                or not _same(command.get('clientActivation'), prep['activation'])
                or not _same(receipt.get('activation'), prep['activation'])):
            issues.append('Fitness exact settled equipment activation differs: ' + case)
        if not native or case == 'empty-restore':
            if (not _same(before_tail.get('inventory'), expected)
                    or not _same(before_tail.get('activation'), prep['activation'])
                    or not _storage(before_tail.get('storage'), prep, 'root', False)):
                issues.append('Fitness exact equipment was not restored before independent reader: ' + case)
        if not native:
            starts = command.get('returnStarts')
            if (not isinstance(starts, list) or len(starts) != 1
                    or not _matches(starts[0], dict(ordinal=1, id=items['dumbbell'], kind='Base.DumbBell',
                        source='root', destination=items['bag'], callback='ISBaseTimedAction.begin'))
                    or not _number(starts[0].get('nativeClock'))
                    or not _number(before_tail.get('nativeClock')) or starts[0]['nativeClock'] > before_tail['nativeClock']):
                issues.append('Fitness exact native return start/count before reader differs: ' + case)
            settlement = command.get('settlement', {})
            if (command.get('confirmedPickup') is not True or command.get('confirmedReturn') is not True or not _matches(command, dict(returnCount=1))
                    or settlement.get('borrowings') != [dict(id=items['dumbbell'], fullType='Base.DumbBell', state='completed')]
                    or not _same(before_tail.get('inventory'), expected)
                    or not _same(before_tail.get('activation'), prep['activation'])
                    or not _storage(before_tail.get('storage'), prep, 'root', False)):
                issues.append('Fitness borrowed equipment lacked confirmed pickup/return or exact restoration before reader: ' + case)
            if case == 'active-cancel-restore':
                steps = command.get('preparationAtCancel', {}).get('steps', [])
                observed = [step for step in steps if step.get('observedPreparation') is True]
                expected_preparation = [('ISInventoryTransferAction', items['dumbbell'], 'Base.DumbBell'),
                                        ('ISUnequipAction', items['hammer'], 'Base.Torch'),
                                        ('ISUnequipAction', items['screwdriver'], 'Base.Screwdriver'),
                                        ('ISUnequipAction', items['bag'], 'Base.Bag_Schoolbag'),
                                        ('ISDropWorldItemAction', items['bag'], 'Base.Bag_Schoolbag'),
                                        ('ISEquipWeaponAction', items['dumbbell'], 'Base.DumbBell')]
                if (command.get('confirmedPreparation') is not True or len(observed) != 6
                        or [(step.get('kind'), step.get('itemId'), step.get('itemType')) for step in observed] != expected_preparation
                        or any(not _matches(step, dict(state='earned', started=True)) for step in observed)):
                    issues.append('Fitness active cancellation preceded confirmed preparation: ' + case)
            if case in EARLY_CANCEL_CASES and command.get('propEquipObserved') is not False:
                issues.append('Fitness canceled pickup still equipped workout prop: ' + case)
        if case in EARLY_CANCEL_CASES and not native:
            if not _exhaustion_without_training(prep['before'], receipt.get('clinical')):
                issues.append('Fitness canceled pickup changed native training effects: ' + case)
        if case == 'pickup-cancel-restore':
            pickup = command.get('pickupCancel', {})
            if (not _matches(command, dict(pickupCancelled=True))
                    or not _matches(pickup, dict(id=items['dumbbell'], kind='Base.DumbBell', source=items['bag'], destination='root', started=True))
                    or not _number(pickup.get('progress')) or not 0 < pickup['progress'] < 1
                    or type(pickup.get('transaction')) is not int or pickup['transaction'] < (1 if mp else 0)):
                issues.append('Fitness cancellation did not target exact in-flight native pickup: ' + case)
        if mp and not native_active_cancel:
            tail_start = receipt.get('tailStart', {})
            if (not _matches(tail_start, dict(id=items['tail'], kind='Base.BookFirstAid1', callback='ISReadABook.serverStart',
                                             workouts=len(exercises), observerActive=False))
                    or not _inventory(tail_start.get('inventory'))
                    or not (isinstance(tail_start.get('activation'), dict) or tail_start.get('activation') == [])
                    or (not native or case == 'empty-restore') and (not _same(tail_start['inventory'], expected)
                                       or not _same(tail_start['activation'], prep['activation'])
                                       or not _storage(tail_start.get('storage'), prep, 'root', False))):
                issues.append('Fitness authoritative reader callback lacked restored live Host replicas: ' + case)
        placements = receipt.get('placements')
        placement_expected = native or case != 'pickup-cancel-restore'
        if (not isinstance(placements, list) or len(placements) != int(placement_expected)
                or any(not _matches(value, dict(callback='ISDropWorldItemAction.complete', succeeded=True))
                       or not _number(value.get('nativeClock')) or not _ground_conservation(value, prep) for value in placements)):
            issues.append('Fitness native bag placement callback/world contents differ: ' + case)
        if not native:
            recovery = command.get('recoveryStarts')
            recovered = case != 'pickup-cancel-restore'
            settlements = command.get('recoverySettlements')
            if (not isinstance(recovery, list) or len(recovery) != int(recovered)
                    or not isinstance(settlements, list) or len(settlements) != int(recovered)):
                issues.append('Fitness native bag recovery start/count differs: ' + case)
            else:
                for start, settled in zip(recovery, settlements):
                    steps = settled.get('steps', []) if isinstance(settled, dict) else []
                    pickups = [step for step in steps if step.get('plannedTransfer') is True and step.get('transferDirection') == 'pickup']
                    if (not _matches(start, dict(ordinal=1, id=items['bag'], kind='Base.Bag_Schoolbag', source='world',
                                               destination='root', callback='ISBaseTimedAction.begin'))
                            or not _number(start.get('nativeClock')) or start['nativeClock'] > before_tail.get('nativeClock', -1)
                            or not _ground_conservation(start, prep) or len(pickups) != 1
                            or not isinstance(placements, list) or len(placements) != 1
                            or not _number(placements[0].get('nativeClock')) or placements[0]['nativeClock'] > start['nativeClock']
                            or not _matches(pickups[0], dict(kind='ISInventoryTransferAction', itemId=items['bag'],
                                itemType='Base.Bag_Schoolbag', state='earned', started=True, phase='cleanup'))):
                        issues.append('Fitness bag recovery lacks exact completed native pickup receipt: ' + case)
            if case == 'pickup-cancel-restore':
                initial = command.get('pickupCancelInventory', {})
                if (not _inventory(initial) or initial['primary'] != prep['inventory']['primary']
                        or initial['secondary'] != prep['inventory']['secondary'] or not _same(initial['worn'], prep['inventory']['worn'])
                        or not any(_storage(command.get('pickupCancelStorage'), prep, 'root', fetched) for fetched in (False, True))):
                    issues.append('Fitness pickup cancellation removed hands/bag before pickup settled: ' + case)
            elif not any(_matches(step, dict(kind='ISDropWorldItemAction', itemId=items['bag'], itemType='Base.Bag_Schoolbag',
                                             state='earned', started=True, observedPreparation=True)) for step in command.get('settlement', {}).get('steps', [])):
                issues.append('Fitness cancellation lacks confirmed native bag placement: ' + case)
        if case == 'placement-cancel-restore':
            placement = command.get('placementCancel', {})
            square = placement.get('square', {})
            if (command.get('placementCancelled') is not True or not _matches(placement, dict(id=items['bag'], kind='Base.Bag_Schoolbag', started=True, isPlaceItem=True))
                    or not _number(placement.get('progress')) or not 0 < placement['progress'] < 1
                    or not _storage(placement.get('storage'), prep, 'root', True)
                    or not isinstance(square, dict) or set(square) != {'x','y','z'}
                    or not all(type(square[key]) is int for key in square)
                    or isinstance(placements, list) and placements and not _matches(placements[0].get('storage', {}).get('world'), square)):
                issues.append('Fitness cancellation did not target exact active native bag placement: ' + case)
    if case in ('multi-storage', 'multi-storage-closed'):
        from .fitness_storage import verify_storage
        issues.extend(verify_storage(case, command, prep, receipt, mp))
    last_stop, last_duration_stop = None, None
    for record in records:
        before, after, rep = record.get('before'), record.get('after'), record.get('lastRep')
        valid = (_matches(record, dict(minutes=minutes, maxTime=5000000, previousStopSettled=True,
                                        currentExerciseCleared=True, serverStopReturned=True))
                 and type(record.get('reps')) is int and record['reps'] > 0
                 and all(_clinical(value) for value in (before, after, rep))
                 and all(record.get('exercise') in value['regularity'] for value in (before, after, rep))
                 and all(_number(record.get(key)) for key in ('startMS', 'stopMS', 'lastRepMS', 'minEndurance')))
        if valid:
            valid = (all(_number(record.get(key)) for key in ('durationStartMS', 'durationStopMS'))
                     and all(_number(record.get(key)) and record[key] > 0 for key in
                             ('durationStartFrameGameMS', 'durationStartFrameRealMS', 'durationStopFrameGameMS', 'durationStopFrameRealMS'))
                     and record['durationStartFrameGameMS'] < 60000 and record['durationStopFrameGameMS'] < 60000
                     and record['durationStartMS'] >= 0
                     and record['durationStopMS'] > record['durationStartMS']
                     and (last_duration_stop is None or record['durationStartMS'] >= last_duration_stop)
                     and (record['durationStopMS'] - record['durationStartMS'] < 600000
                          if case in ('active-cancel', 'active-cancel-restore')
                          else 600000 < record['durationStopMS'] - record['durationStartMS'] < minutes * 60000
                          if case == 'late-exhaustion'
                          else record['durationStopMS'] - record['durationStartMS'] + record['durationStopFrameGameMS'] >= minutes * 60000))
            if valid:
                last_duration_stop = record['durationStopMS']
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
                     and (_empty_restore_clock(record, command, minutes, native, mp) if case == 'empty-restore'
                          else not native or (duration < 600000 if case in ('active-cancel', 'active-cancel-restore')
                                              else 600000 < duration < minutes * 60000 if case == 'late-exhaustion'
                                              else duration >= minutes * 60000)))
            last_stop = record['stopMS']
        if not valid:
            issues.append('Fitness lacks real native repetitions/XP/endurance/stiffness or full duration: ' + case)
    if case == 'late-exhaustion':
        issues.extend(_late_exhaustion(command, receipt, mp, native, items['tail'], minutes))
    if records and case != 'late-exhaustion' and _clinical(receipt.get('clinical')) and _clinical(records[-1].get('after')):
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


def _conserved_storage(inventory, storage, prep, carried):
    if (not isinstance(prep, dict) or not isinstance(prep.get('items'), dict) or not isinstance(prep.get('storage'), dict)
            or not _inventory(prep.get('inventory')) or not _inventory(inventory) or not isinstance(storage, dict)
            or not _matches(storage, dict(id=prep['items']['bag'], kind='Base.Bag_Schoolbag',
                occurrences=1, favorite=prep['storage']['favorite']))
            or carried and storage.get('endpoint') != 'root'):
        return False
    actual = copy.deepcopy(inventory['items'])
    if storage.get('endpoint') == 'world':
        world = storage.get('world')
        if (not isinstance(world, dict) or not _matches(world, dict(linked=True))
                or any(type(world.get(key)) is not int for key in ('x', 'y', 'z'))
                or not isinstance(storage.get('contents'), list)):
            return False
        actual += [dict(id=storage['id'], kind=storage['kind'], container='root'), *storage['contents']]
    elif (storage.get('endpoint') != 'root' or storage.get('world') is not False
            or not _same(storage.get('contents'), [row for row in inventory['items'] if row['container'] == storage['id']])):
        return False
    expected = {row['id']: row['kind'] for row in prep['inventory']['items']}
    return (len(actual) == len(expected) and len({row.get('id') for row in actual}) == len(actual)
            and all(set(row) == {'id', 'kind', 'container'} and expected.get(row['id']) == row['kind'] for row in actual))


def _no_training(before, after):
    return (_clinical(before) and _clinical(after) and all(after[key] == before[key] for key in ('fitnessXP', 'strengthXP'))
            and all(after[group][key] <= value for group in ('regularity', 'stiffness') for key, value in before[group].items()))


def _isolations(text, authority_text, selection, results, raw):
    markers = [(match.start(), match[1], json.loads(match[2])) for match in re.finditer(
        r'\[FITNESS_TEST\] (ISOLATION_STARTED|ISOLATION_SETTLED|ISOLATION_FAILED)\s+([^\n]*)', text)]
    ready = [(match.start(), json.loads(match[1])) for match in re.finditer(
        r'\[FITNESS_TEST\] ISOLATION_READY\s+([^\n]*)', authority_text)]
    expected = [row['id'] for row in results if selection['mode'] == 'native' and selection['kind'] == 'mp'
                and row.get('id') in BORROWED_CASES and row.get('status') == 'failed'
                and row.get('receipt', {}).get('currentExerciseCleared') is True
                and row.get('receipt', {}).get('records') == []
                and row.get('command', {}).get('clientCurrentExerciseCleared') is False]
    issues = []
    if ([(marker, row.get('case')) for _, marker, row in markers]
            != [(marker, case) for case in expected for marker in ('ISOLATION_STARTED', 'ISOLATION_SETTLED')]
            or [(row.get('case'), row.get('phase')) for _, row in ready]
            != [(case, phase) for case in expected for phase in ('before', 'after')]):
        issues.append('Fitness native isolation case/phase/order differs')
    for case in expected:
        row = next(entry for entry in results if entry['id'] == case)
        prep = next((value for marker, value in raw if marker == 'PREPARED' and value.get('case') == case), {})
        if not isinstance(prep.get('items'), dict) or not isinstance(prep.get('storage'), dict):
            issues.append('Fitness native isolation preparation missing: ' + case)
            continue
        found = [(position, marker, value) for position, marker, value in markers if value.get('case') == case]
        if len(found) != 2 or [marker for _, marker, _ in found] != ['ISOLATION_STARTED', 'ISOLATION_SETTLED']:
            continue
        start_pos, _, start = found[0]; end_pos, _, end = found[1]
        prefix = text[:start_pos]
        published = [json.loads(line.split('[QUEUE_CHECK] ', 1)[1]) for line in prefix.splitlines() if '[QUEUE_CHECK] ' in line]
        following = [json.loads(line.split('[QUEUE_CHECK] ', 1)[1]) for line in text[start_pos:end_pos].splitlines() if '[QUEUE_CHECK] ' in line]
        if not any(_same(value, row) for value in published) or following or '[FITNESS_TEST] MENU_READY ' in text[start_pos:end_pos]:
            issues.append('Fitness native isolation preceded failure or overlapped next case: ' + case)
        context = dict(case=case, actor='client1', mode='native', kind='mp', failedCaseRecorded=True, failedRowUnchanged=True,
                       queueEmpty=True, nativeActions=0, observerActive=False, localRecords=0)
        if (not _matches(row.get('command'), dict(queueDrained=True, activeObserved=False, startedOrder=[], clientCurrentExerciseCleared=False))
                or not _matches(row.get('receipt'), dict(currentExerciseCleared=True, serverStopSettled=True, records=[], violations=[]))
                or not _matches(start, dict(context, phase='started', exactObjectMatched=True, cleared=True))
                or not _matches(end, dict(context, phase='settled', currentExerciseCleared=True))):
            issues.append('Fitness native isolation exact idle/zero-workout gates differ: ' + case)
        if (not _clinical(start.get('before')) or not _same(start.get('before'), start.get('after'))
                or not _same(start.get('inventoryBefore'), start.get('inventoryAfter'))
                or not _same(start.get('activationBefore'), start.get('activationAfter'))
                or not _conserved_storage(start.get('inventoryBefore'), start.get('storageBefore'), prep, False)
                or not _conserved_storage(end.get('inventory'), end.get('storage'), prep, True)
                or not _no_training(start.get('before'), end.get('clinical'))):
            issues.append('Fitness native isolation changed/lost exact items or clinical effects: ' + case)
        snapshots = [value for _, value in ready if value.get('case') == case]
        for phase, witness in (('before', start.get('authority')), ('after', end.get('authority'))):
            if (not isinstance(witness, dict) or not _matches(witness, dict(case=case, phase=phase, items=prep.get('items'), serverIdle=True,
                    currentExerciseCleared=True, records=0, observerActive=False, nativeActions=0, failedCaseRecorded=True))
                    or sum(_same(witness, value) for value in snapshots) != 1
                    or not _conserved_storage(witness.get('inventory'), witness.get('storage'), prep, phase == 'after')):
                issues.append('Fitness native isolation authority identity/replication witness differs: ' + case)
        if len(snapshots) == 2 and not _no_training(snapshots[0].get('clinical'), snapshots[1].get('clinical')):
            issues.append('Fitness native isolation authority gained workout effects: ' + case)
        for position, value in ready:
            if value.get('case') == case:
                preceding = [json.loads(line.split('[FITNESS_TEST] VERIFIED ', 1)[1]) for line in authority_text[:position].splitlines()
                             if '[FITNESS_TEST] VERIFIED ' in line]
                if not any(_same(receipt, row['receipt']) for receipt in preceding):
                    issues.append('Fitness native isolation authority preceded original receipt: ' + case)
        begins = end.get('nativeBegins')
        if (not isinstance(begins, list) or not begins or any(not isinstance(value, dict) or value.get('kind') == 'ISFitnessAction'
                or not isinstance(value.get('kind'), str) or value.get('callback') != 'ISBaseTimedAction.begin' for value in begins)):
            issues.append('Fitness native isolation lacked genuine cleanup starts: ' + case)
        recovery = start.get('storageBefore', {}).get('endpoint') == 'world'
        if type(start.get('recoveryRequired')) is not bool or start['recoveryRequired'] != recovery or end.get('recoveryRequired') != recovery:
            issues.append('Fitness native isolation recovery requirement differs: ' + case)
        if recovery:
            witness = end.get('recoveryStart', {})
            transaction = end.get('recoveryTransaction')
            if (not _matches(end, dict(recoveryCallbacks=1, recoveryCallbackSucceeded=True, recoveryAuthorityCompleted=True))
                    or type(transaction) is not int or transaction <= 0
                    or not _matches(witness, dict(id=prep['items']['bag'], kind='Base.Bag_Schoolbag', source='world', destination='root', callback='ISBaseTimedAction.begin'))
                    or not _conserved_storage(witness.get('inventory'), witness.get('storage'), prep, False)
                    or witness.get('storage', {}).get('endpoint') != 'world'
                    or not isinstance(begins, list) or sum(isinstance(value, dict) and value.get('kind') == 'ISInventoryTransferAction' and value.get('id') == prep['items']['bag'] for value in begins) != 1):
                issues.append('Fitness native isolation recovery lacks exact native transaction/callback: ' + case)
    return issues, [dict(marker=marker, **row) for _, marker, row in markers]


def verify(root, selection, catalog):
    from ..report import events
    root = Path(root)
    text = (root / 'client1-launch.log').read_text(errors='replace')
    authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
    rows = events(text)
    cases = selection['cases']
    results = [row for row in rows if row['event'] == 'case']
    raw = [(match[1], json.loads(match[2])) for match in re.finditer(r'\[FITNESS_TEST\] (PREPARED|MUTATED|VERIFIED)\s+([^\n]*)', authority)]
    issues, outcomes = [*_editor_logs(text, results, selection), *_settled_logs(text, results, selection)], []
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
    isolation_issues, isolation_proofs = _isolations(text, authority, selection, results, raw)
    issues.extend(isolation_issues)
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
            if case=='storage-peer-pickup' and (len(found)!=1 or not _same(found[0].get('peerPickup'),(receipt.get('peerPickup',{}).get('proof') if isinstance(receipt.get('peerPickup'),dict) else None))):
                problems.append('Fitness independent peer pickup witness differs: ' + case)
        used_ids.extend(prep.get('items', {}).values())
        issues.extend(problems)
        outcome = dict(effectsVerified=not problems, serverAuthorityVerified=not problems and selection['kind']=='mp',
            emptyStartVerified=not problems and case=='empty', queuedStartVerified=not problems and case=='queued',
            sequentialVerified=not problems and case=='sequential', waitingCancelVerified=not problems and case=='pending-cancel' and selection['mode']=='toolkit',
            independentMoveVerified=not problems and case=='pending-reorder' and selection['mode']=='toolkit',
            activeCancelVerified=not problems and case in ('active-cancel', 'active-cancel-restore'), missingItemVerified=not problems and case=='missing-dumbbell',
            nativeTailCancelledVerified=not problems and selection['mode']=='native' and case in ACTIVE_CANCEL_CASES,
            independentTailPreservedVerified=not problems and not (selection['mode']=='native' and case in (*ACTIVE_CANCEL_CASES, 'late-exhaustion')),
            restoreVerified=not problems and case in (*BORROWED_CASES, 'multi-storage', 'multi-storage-closed'), receipt=receipt, command=row.get('command'))
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
            peer_result['outcome'].update(participantRole='competing-picker' if result['case']=='storage-peer-pickup' else 'independent-reader', workoutActor='client1')
            peers.append(peer_result)
        outcomes.extend(peers)
    shared = [issue for issue in issues if not any(issue.endswith(': ' + case) for case in cases)]
    if shared:
        for outcome in outcomes:
            outcome.update(status='failed', reason='; '.join([*shared, outcome['reason']]).strip('; '))
            outcome['outcome'].update(effectsVerified=False, serverAuthorityVerified=False)
    return dict(issues=issues, outcomes=outcomes, evidence={'recoveries': recovery_proofs, 'isolations': isolation_proofs, 'limits': [
        'Programmatic native Fitness OK callbacks; physical mouse/controller input is not covered.',
        'Native menu durations and real native repetitions/XP; no time or action acceleration.',
        'Host uses two actual clients; the peer reads an independent exact-ID native book.',
        'Full selected pack only; native controls can fail and those failures remain visible.']})
