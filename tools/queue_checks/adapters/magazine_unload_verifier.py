"""Read-only identity, native progress and ammo conservation gates for sealed receipts."""
import json
import math
from pathlib import Path
import re

from .. import report
from ..placement import validate as validate_placement
from .magazine_unload import AMMO, OTHER, CASES, NAMES, LOADS, PREFIX, PRODUCERS, _raw, complete


def require(value, reason):
    if not value: raise ValueError(reason)


def integer(value, minimum=0):
    return type(value) is int and value >= minimum


def number(value):
    try: return type(value) in (int, float) and math.isfinite(value) and value >= 0
    except OverflowError: return False


def ammo_rows(rows, magazine_ids):
    require(type(rows) is list, 'ammo rows')
    result = {}
    for item in rows:
        require(type(item) is dict and set(item) == {'id', 'type', 'class', 'uses', 'factoryCount', 'root', 'path'}, 'ammo record fields')
        identifier = item['id']; kind = item['type']; path = item['path']
        require(integer(identifier) and identifier not in result and identifier not in magazine_ids, 'duplicate/aliased ammo identity')
        require(kind in (AMMO, OTHER) and item['class'] == 'ComboItem', 'plain ammo output type')
        require(integer(item['uses'], 1) and item['uses'] <= 1000000 and type(item['factoryCount']) is int
                and item['factoryCount'] == (5 if kind == AMMO else 6), 'actionable uses/factory count')
        require(type(item['root']) is bool and type(path) is list and all(integer(value) for value in path)
                and len(set(path)) == len(path) and identifier not in path and item['root'] is (not path), 'ammo source ancestry')
        result[identifier] = item
    require(list(result) == sorted(result), 'ammo receipt order')
    return result


def snapshot(value, ids, phase, editing):
    require(type(value) is dict and set(value) == {'case', 'magazines', 'ammo', 'looseUnits', 'loadedUnits', 'totalUnits'}
            and value['case'] == ids['case'] and set(value['magazines']) == set(NAMES), 'snapshot fields/case')
    loads = {}
    for name in NAMES:
        item = value['magazines'][name]; spec = ids['magazines'][name]
        require(type(item) is dict and set(item) == set(spec) | {'present', 'actorCount', 'rootCount', 'equipped', 'favorite'}, 'magazine receipt fields')
        require(all(type(item[key]) is type(spec[key]) and item[key] == spec[key] for key in spec if key != 'loaded'), 'exact magazine identity/type/condition')
        require(item['present'] is True and type(item['actorCount']) is int and item['actorCount'] == 1
                and type(item['rootCount']) is int and item['rootCount'] == 1
                and item['equipped'] is False and item['favorite'] is False, 'exact unique root magazine source')
        loaded = item['loaded']; require(integer(loaded) and loaded <= spec['maxAmmo'], 'loaded count type/bounds')
        if phase == 'input': wanted = LOADS[name]
        elif phase == 'pending': wanted = None if name == 'front' else LOADS[name]
        else: wanted = LOADS[name] if name == 'unrelated' or editing and name == 'cancelled' else 0
        require(0 < loaded < LOADS['front'] if wanted is None else loaded == wanted, 'native magazine count effect ' + name)
        loads[name] = loaded
    ammo = ammo_rows(value['ammo'], {spec['id'] for spec in ids['magazines'].values()})
    loose = sum(item['uses'] for item in ammo.values() if item['type'] == AMMO); loaded = sum(loads.values())
    require(all(type(value[key]) is int for key in ('looseUnits', 'loadedUnits', 'totalUnits'))
            and value['looseUnits'] == loose and value['loadedUnits'] == loaded and value['totalUnits'] == loose + loaded,
            'physical loose-plus-loaded units')
    return ammo, loads


def preserved_and_outputs(current, baseline):
    require(all(current.get(identifier) == value for identifier, value in baseline.items()), 'baseline loose/unrelated ammo changed or lost')
    outputs = {identifier: value for identifier, value in current.items() if identifier not in baseline}
    require(all(value['type'] == AMMO and value['class'] == 'ComboItem' and value['uses'] == 1
                and value['factoryCount'] == 5 and value['root'] is True and value['path'] == [] for value in outputs.values()),
            'new output ID/type/actionable units/root source')
    return outputs


def check_case(row, selection, prepared, verified):
    try:
        ids = row['ids']; case = ids['case']; editing = selection['mode'] == 'toolkit'
        require(ids == prepared and case in CASES and ids['mode'] == selection['mode'] and row['server'] == verified, 'prepared/authority identity receipt')
        require(set(ids) == {'case', 'mode', 'origin', 'placementProof', 'magazines', 'seedAmmo', 'otherAmmo', 'initialAmmo', 'ammoUnit'}
                and ids['ammoUnit'] == 'currentUses' and set(ids['magazines']) == set(NAMES), 'seed contract')
        validate_placement(row['clientPlacement'], ids['origin'], 'local', centered=True)
        validate_placement(ids['placementProof'], ids['origin'], 'replica' if selection['kind'] == 'mp' else 'local', centered=True)
        magazine_ids = []
        for name, spec in ids['magazines'].items():
            require(type(spec) is dict and set(spec) == {'id', 'type', 'class', 'loaded', 'maxAmmo', 'ammoType', 'factoryCount', 'condition'}, 'magazine seed fields')
            require(integer(spec['id']) and spec['type'] == 'Base.9mmClip' and spec['class'] == 'ComboItem'
                    and type(spec['loaded']) is int and spec['loaded'] == LOADS[name] and type(spec['maxAmmo']) is int and spec['maxAmmo'] == 15
                    and spec['ammoType'] == AMMO and type(spec['factoryCount']) is int and spec['factoryCount'] == 1
                    and type(spec['condition']) is int and spec['condition'] == 10, 'plain magazine factory/loaded input')
            magazine_ids.append(spec['id'])
        require(len(set(magazine_ids)) == len(NAMES), 'aliased magazine IDs')
        baseline = ammo_rows(ids['initialAmmo'], set(magazine_ids))
        require(type(ids['seedAmmo']) is list and len(ids['seedAmmo']) == 2 and all(integer(value) for value in ids['seedAmmo'])
                and len(set(ids['seedAmmo'])) == 2 and integer(ids['otherAmmo']) and ids['otherAmmo'] not in ids['seedAmmo'], 'baseline ammo identities')
        for identifier, kind in [(value, AMMO) for value in ids['seedAmmo']] + [(ids['otherAmmo'], OTHER)]:
            require(identifier in baseline and baseline[identifier]['type'] == kind and baseline[identifier]['uses'] == 1
                    and baseline[identifier]['root'] is True and baseline[identifier]['path'] == [], 'seeded round/root identity')
        initial, _ = snapshot(row['input'], ids, 'input', editing)
        require(initial == baseline and row['input']['ammo'] == ids['initialAmmo'], 'client initial baseline differs from authority')
        final_outputs = None
        for role in ('client', 'server'):
            ammo, loads = snapshot(row[role], ids, 'final', editing); outputs = preserved_and_outputs(ammo, baseline)
            decrement = sum(LOADS[name] - loaded for name, loaded in loads.items())
            require(len(outputs) == decrement and sum(value['uses'] for value in outputs.values()) == decrement
                    and row[role]['totalUnits'] == row['input']['totalUnits'], 'one actionable new round per native magazine decrement')
            if final_outputs is not None: require(outputs == final_outputs, 'client/server output IDs differ')
            final_outputs = outputs
        require(row['client'] == row['server'], 'canonical client/server final state differs')
        require(row['pendingBefore'] == row['pendingAfter'], 'pending edit mutated physical effects')
        pending, _ = snapshot(row['pendingBefore'], ids, 'pending', editing)
        pending_outputs = preserved_and_outputs(pending, baseline)
        require(len(pending_outputs) <= LOADS['front'] and all(final_outputs.get(identifier) == value for identifier, value in pending_outputs.items()), 'pending output was invented, replayed or lost')
        require(row['status'] == 'passed' and row['queueIdle'] is True and number(row['settleMilliseconds']) and row['settleMilliseconds'] >= 1000,
                'native completion/settle')
        require(row['edit'] == dict(cancelled=editing, reordered=editing, untouched=True)
                and all(type(value) is bool for value in row['edit'].values()), 'real pending edit effects')
        names = ['front', 'repeat-first', 'repeat-second', 'target', 'cancelled', 'tail']
        commands = row['commands']; require(type(commands) is list and [command['name'] for command in commands] == names, 'complete native producer sequence')
        executed = []; sequences = []; episodes = set(); repeat_ammo = None
        for command in commands:
            name = command['name']; repeat = name in ('repeat-first', 'repeat-second'); source = 'front' if repeat else name
            cancelled = editing and name == 'cancelled'
            constructor_ammo = row['pendingBefore']['magazines']['front']['loaded'] if repeat else LOADS[source]
            require(command['type'] == 'ISUnloadBulletsFromMagazine' and integer(command['item']) and command['item'] == ids['magazines'][source]['id']
                    and command['producer'] == PRODUCERS[case] and type(command['duration']) is int and command['duration'] == -1
                    and type(command['constructorAmmo']) is int and command['constructorAmmo'] == constructor_ammo
                    and command['constructorStartUnset'] is True and command['callbacksUntouched'] is True and command['ownedBulkGuard'] is (case == 'bulk')
                    and command.get('cancelled', False) is cancelled, 'native duration/callback/guard/input identity')
            partial = command['partialCounts']; events = command['lifecycle']
            require(type(partial) is list and type(events) is list, 'native partial/lifecycle samples')
            if cancelled:
                require(command['started'] is False and command['progress'] is False and not partial and not events and 'startedAt' not in command, 'cancelled magazine action started')
                continue
            if repeat:
                require(type(command['started']) is bool and command['progress'] is False and not partial
                        and (number(command.get('startedAt')) if command['started'] else 'startedAt' not in command), 'empty repeats cannot claim partial progress')
            else:
                require(command['started'] is True and command['progress'] is True and number(command['startedAt'])
                        and partial and all(integer(value, 1) and value < LOADS[source] for value in partial)
                        and all(a > b for a, b in zip(partial, partial[1:])), 'real native start/partial loaded-count progress')
            require(events and all(type(event) is dict and set(event) == {'sequence', 'event', 'phase', 'succeeded', 'nativeEpisode', 'nativeClass', 'loaded', 'startAmmo', 'ammo'} for event in events), 'typed Lifecycle boundary receipt')
            require(all(integer(event['sequence'], 1) and type(event['succeeded']) is bool and integer(event['loaded'])
                        and event['loaded'] <= constructor_ammo for event in events)
                    and all(a['sequence'] < b['sequence'] for a, b in zip(events, events[1:])), 'monotonic native observer sequence')
            sequences.extend(event['sequence'] for event in events)
            admissions = [event for event in events if event['event'] == 'admission']
            require(len(admissions) == 1 and admissions[0] == events[0] and admissions[0]['phase'] is False
                    and admissions[0]['succeeded'] is False and admissions[0]['nativeEpisode'] is False and admissions[0]['nativeClass'] is False
                    and admissions[0]['startAmmo'] is False and admissions[0]['loaded'] == (0 if repeat else LOADS[source]), 'actual admission count before native allocation')
            boundaries = events[1:]; native_ids = set()
            for event in boundaries:
                require(event['event'] in ('begin', 'finish') and event['phase'] in ('perform', 'complete')
                        and event['succeeded'] is (event['event'] == 'finish')
                        and integer(event['nativeEpisode'], 1) and event['nativeClass'] == 'LuaTimedActionNew'
                        and type(event['startAmmo']) is int and event['startAmmo'] == (0 if repeat else LOADS[source])
                        and event['loaded'] == 0, 'successful native episode/start/finish boundary')
                native_ids.add(event['nativeEpisode'])
            require(len(native_ids) == 1 and not native_ids & episodes, 'native allocation episode reused or absent')
            episodes.update(native_ids)
            for phase in ('perform', 'complete'):
                pair = [event['event'] for event in boundaries if event['phase'] == phase]
                require(pair == ['begin', 'finish'] or phase == 'complete' and selection['kind'] == 'mp' and not pair, 'native perform/SP complete finish missing')
            for event in events:
                if repeat:
                    observed = ammo_rows(event['ammo'], set(magazine_ids)); outputs = preserved_and_outputs(observed, baseline)
                    require(len(outputs) == LOADS['front'] and all(final_outputs.get(identifier) == value for identifier, value in outputs.items()), 'empty-start output receipt differs from completed front')
                    if repeat_ammo is not None: require(observed == repeat_ammo, 'repeat native callback changed loose ammo')
                    repeat_ammo = observed
                else: require(event['ammo'] is False, 'unexpected ordinary callback ammo witness')
            executed.append((admissions[0]['sequence'], name))
        require(len(set(sequences)) == len(sequences) and sorted(sequences) == list(range(min(sequences), max(sequences) + 1)), 'duplicated/missing observer boundary serial')
        expected_order = ['front', 'repeat-first', 'repeat-second', 'tail', 'target'] if editing else ['front', 'repeat-first', 'repeat-second', 'target', 'cancelled', 'tail']
        require([name for _, name in sorted(executed)] == expected_order, 'committed native admission execution order')
        calls = ([dict(names=[name], entries=1, queued=1) for name in names] if case == 'direct' else
                 [dict(names=[name], entries=1, queued=1) for name in names[:3]] + [dict(names=['target', 'cancelled', 'tail'], entries=3, queued=3)])
        require(type(row['producerCalls']) is list and row['producerCalls'] == calls
                and all(type(call['entries']) is int and type(call['queued']) is int for call in row['producerCalls']), 'public native/bulk producer call receipts')
        return []
    except (KeyError, TypeError, ValueError, IndexError, OverflowError) as error:
        return ['Magazine unload evidence differs: ' + str(error)]


def verify(root, selection, catalog):
    root = Path(root); issues = []; outcomes = []; setups = []
    try:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        events = [value for value in report.events(text) if value.get('suite') == 'magazine-unload']
        setups = [value for value in events if value.get('event') == 'setup']; ends = [value for value in events if value.get('event') == 'complete']
        rows = [value for value in events if value.get('event') == 'case']; cases = list(CASES)
        prepared, verified = (_raw(authority, marker) for marker in ('PREPARED', 'VERIFIED')); placements = _raw(text, 'CLIENT_PLACEMENT')
        require(len(setups) == 1 and len(ends) == 1 and [value.get('id') for value in rows] == cases
                and all([value.get('case') for value in group] == cases for group in (prepared, verified, placements)), 'missing/duplicate/ordered grouped case receipts')
        setup = setups[0]; end = ends[0]
        require(setup.get('cases') == cases and setup.get('queueEnabled') is (selection['mode'] == 'toolkit')
                and setup.get('nativeDurations') is True and type(setup.get('adapterInstalled')) is bool
                and (selection['mode'] != 'toolkit' or setup.get('adapterInstalled') is True)
                and end.get('cases') == cases and type(end.get('performed')) is int and end['performed'] == len(cases)
                and type(end.get('failed')) is int and end['failed'] == 0 and type(end.get('skipped')) is int and end['skipped'] == 0, 'setup or grouped completion')
        order = [(match.group(1), json.loads(match.group(2)).get('case')) for match in re.finditer(re.escape(PREFIX) + r'(PREPARED|VERIFIED) ([^\n]+)', authority)]
        require(order == [(marker, case) for case in cases for marker in ('PREPARED', 'VERIFIED')], 'authority preparation/effect order')
        for index, case in enumerate(cases):
            row = rows[index]
            require(row.get('actor') == 'client1' and row.get('kind') == selection['kind'] and row.get('mode') == selection['mode']
                    and placements[index] == dict(case=case, proof=row.get('clientPlacement')), 'actor/selection/local placement evidence')
            errors = check_case(row, selection, prepared[index], verified[index]); issues += errors
            outcomes.append(dict(actor='client1', case=case, status='failed' if errors else 'passed', reason='; '.join(errors),
                outcome=dict(effectsVerified=not errors, serverAuthorityVerified=not errors, tailCompleted=not errors,
                             pendingEditsVerified=not errors and selection['mode'] == 'toolkit')))
        require(complete(selection, 'client1', text), 'completion marker')
        for marker in ('VOICE_DISABLED', 'DISPLAY_READY', 'PREFLIGHT_COMPLETE', 'NATIVE_CONNECTED' if selection['kind'] == 'mp' else 'TRUE_SP'):
            require('[QUEUE_TEST] ' + marker in text, 'missing client readiness ' + marker)
        if selection['kind'] == 'mp': require('[STARTUP_TEST] SERVER_READY' in authority, 'missing native Host server readiness')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return dict(issues=issues, outcomes=outcomes, evidence=dict(adapterInstalled=setups[0].get('adapterInstalled') if len(setups) == 1 else None,
        limits=['Programmatic native inventory/public bulk producers; no physical input, active edits, recovery or group-fetch authority.',
                'Ammo conservation counts actionable getCurrentUses, not the unrelated factory getCount metadata; no future capacity credit.']))
