"""Exact pending Equip edit evidence, independent of the unload receipt contract."""
import json
import math
from pathlib import Path
import re

from .. import report
from ..placement import validate as validate_placement

SEGMENTS = ('reorder-two', 'reorder-three', 'cancel', 'dependent', 'capacity', 'component-guard')
PREFIX = '[EQUIP_EDIT] '


def require(value, reason):
    if not value: raise ValueError(reason)


def raw(text, marker):
    return [json.loads(match.group(1)) for match in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\n]+)', text)]


def rows(values):
    require(type(values) is list, 'inventory list')
    result = {}
    for row in values:
        require(type(row) is dict and set(row) == {'id', 'type', 'class', 'path', 'condition', 'count', 'uses'}, 'inventory fields')
        require(type(row['id']) is int and row['id'] >= 0 and row['id'] not in result, 'unique canonical inventory ID')
        require(type(row['path']) is list and all(type(value) is int and value >= 0 for value in row['path'])
                and len(set(row['path'])) == len(row['path']) and row['id'] not in row['path'], 'inventory ancestry')
        require(all(type(row[key]) is int and row[key] >= 0 for key in ('condition', 'count', 'uses')), 'inventory counts/condition')
        require(type(row['type']) is str and type(row['class']) is str, 'inventory source type')
        result[row['id']] = row
    require(list(result) == sorted(result), 'canonical inventory receipt order')
    return result


def expected_hands(ids, editing):
    item = ids['items']; segment = ids['segment']
    if segment == 'reorder-two': return dict(primary=item['a' if editing else 'b']['id'], secondary=False)
    if segment == 'reorder-three': return dict(primary=item['b']['id'], secondary=item['a' if editing else 'c']['id'])
    if segment == 'cancel': return dict(primary=item['a' if editing else 'c']['id'], secondary=item['b']['id'])
    if segment == 'component-guard': return dict(primary=item['b']['id'], secondary=False)
    return dict(primary=False, secondary=False)


def check_segment(row, selection, prepared, verified):
    try:
        ids = row['ids']; segment = row['segment']; editing = selection['mode'] == 'toolkit' and selection['kind'] == 'sp'
        require(segment in SEGMENTS and ids == prepared and row['server'] == verified and ids['segment'] == segment
                and ids['case'] == 'equip-edit' and ids['kind'] == selection['kind'] and ids['mode'] == selection['mode'], 'authority/selection segment identity')
        validate_placement(row['clientPlacement'], ids['origin'], 'local', centered=True)
        validate_placement(ids['placementProof'], ids['origin'], 'replica' if selection['kind'] == 'mp' else 'local', centered=True)
        specs = ids['items']; names = {'front', 'tail', 'a', 'b', 'c', 'bag', 'marker'}
        if segment in ('dependent', 'capacity'): names.add('nested')
        if segment == 'capacity': names.add('heldBag')
        require(set(specs) == names and len({spec['id'] for spec in specs.values()}) == len(specs), 'exact fixture item identities')
        expected_types = dict(front='Base.BookCarpentry1', tail='Base.BookFirstAid1', a='Base.Hammer' if segment == 'component-guard' else 'Base.Nails', b='Base.Screwdriver', c='Base.Scissors',
                              bag='Base.Bag_Schoolbag', marker='Base.Nails', nested='Base.Plank' if segment == 'capacity' else 'Base.Pencil', heldBag='Base.Bag_Schoolbag')
        for name, spec in specs.items():
            require(type(spec['id']) is int and spec['id'] >= 0 and spec['type'] == expected_types[name]
                    and set(spec) == ({'id', 'type', 'class', 'pages'} if name in ('front', 'tail') else {'id', 'type', 'class'}), 'native seed identities/types')
        baseline = rows(ids['inventory']); require(all(spec['id'] in baseline for spec in specs.values()), 'seeded input lost from inventory baseline')
        for name, spec in specs.items():
            expected_class = 'Literature' if name in ('front', 'tail') else 'InventoryContainer' if name in ('bag', 'heldBag') else 'HandWeapon' if name in ('b', 'c', 'nested') or name == 'a' and segment == 'component-guard' else 'ComboItem'
            expected_path = [specs['bag']['id']] if name == 'marker' or name == 'nested' and segment == 'dependent' else [specs['heldBag']['id']] if name == 'nested' else []
            actual = baseline[spec['id']]
            require(spec['class'] == expected_class and actual['type'] == spec['type'] and actual['class'] == expected_class
                    and actual['path'] == expected_path, 'native canonical root/nested factory source')
        require(row['input']['inventory'] == ids['inventory'] and row['input']['hands'] == dict(primary=False, secondary=False), 'native empty hand/input baseline')
        for role in ('client', 'server'):
            value = row[role]
            require(value['case'] == 'equip-edit' and value['segment'] == segment and value['backpack'] is True
                    and value['hands'] == expected_hands(ids, editing), 'final native hand identities/backpack')
            current = rows(value['inventory']); require(set(current) == set(baseline), 'exact inventory multiset/count conservation')
            for identifier, before in baseline.items():
                expected = dict(before)
                require(current[identifier] == expected, 'inventory source/contents/condition changed')
            for name in ('front', 'tail'):
                book = value['books'][name]; spec = specs[name]
                require(book == dict(id=spec['id'], present=True, root=True, pages=spec['pages'], characterPages=spec['pages'], total=spec['pages']), 'native front/tail completion')
        require(row['client'] == row['server'] and row['pendingBefore'] == row['pendingAfter'], 'authority parity/pending edit physical mutation')
        require(row['queueIdle'] is True and row['tidyQuiescent'] is True and type(row['settleMilliseconds']) in (int, float)
                and row['settleMilliseconds'] >= 1000, 'quiescent native/P4 idle boundary')
        tidy = row['tidyObservation']
        require(type(tidy) is dict and set(tidy) == {'sourceVerified', 'integrationInstalled', 'idlePlayerUpdates', 'observer',
                'retainedOperations', 'observedBorrowings', 'outstandingBorrowings', 'activeBlockedReturn', 'privateTablesObserved'}
                and tidy['sourceVerified'] is True and tidy['integrationInstalled'] is True
                and type(tidy['idlePlayerUpdates']) is int and tidy['idlePlayerUpdates'] >= 6
                and tidy['observer'] == 'ActionQueueSettlement.operationState'
                and type(tidy['retainedOperations']) is int and 0 <= tidy['retainedOperations'] <= len(row['commands'])
                and type(tidy['observedBorrowings']) is int and 0 <= tidy['observedBorrowings'] <= 32 * tidy['retainedOperations']
                and type(tidy['outstandingBorrowings']) is int and tidy['outstandingBorrowings'] == 0
                and tidy['activeBlockedReturn'] is False and tidy['privateTablesObserved'] is False,
                'truthful source-backed P4 idle boundary/shared retained-loan observation')
        cadence = row['frameCadence']
        require(type(cadence) is dict and set(cadence) == {'count', 'totalMilliseconds', 'maxMilliseconds'}
                and type(cadence['count']) is int and cadence['count'] > 0
                and all(type(cadence[key]) in (int, float) and math.isfinite(cadence[key]) and cadence[key] >= 0
                        for key in ('totalMilliseconds', 'maxMilliseconds'))
                and cadence['maxMilliseconds'] <= cadence['totalMilliseconds']
                and cadence['totalMilliseconds'] <= cadence['maxMilliseconds'] * cadence['count'],
                'bounded actual OnTick gap summary')
        native = selection['mode'] == 'native'
        edits = row['edits']; expected_edits = [] if native else ['reorder'] if segment.startswith('reorder-') else ['cancel'] if segment == 'cancel' else ['unavailable-input', 'dependent-transfer'] if segment == 'dependent' else ['component-reorder', 'component-cancel'] if segment == 'component-guard' else ['capacity-transfer', 'capacity-cancel']
        require([value['name'] for value in edits] == expected_edits, 'complete pending edit/negative control sequence')
        for edit in edits:
            allowed = editing and segment in ('reorder-two', 'reorder-three', 'cancel')
            require(edit['allowed'] is allowed, 'SP/Host edit permission boundary')
            if not allowed:
                require(type(edit['reason']) is str and edit['reason'] and edit['queueBefore'] == edit['queueAfter'], 'denied edit must preserve queue')
                if selection['kind'] == 'mp' and segment in ('reorder-two', 'reorder-three', 'cancel'):
                    recognized = {'unavailable', 'move_dependent', 'container_capacity', 'move_shared_item'} if edit['name'] == 'reorder' else {'unavailable', 'operation_dependent', 'operation_shared_item', 'container_capacity'}
                    require(edit['reason'] in recognized, 'Host new Equip rights remain protected by source-backed denials')
        if segment == 'component-guard':
            guard = row['componentGuard']
            require(type(guard) is dict and set(guard) == {'item', 'size', 'components', 'quiet'} and guard['item'] == specs['a']['id']
                    and type(guard['size']) is int and guard['size'] == 2 and guard['quiet'] is False, 'actual protected Hammer component eligibility')
            components = guard['components']
            require(type(components) is list and len(components) == guard['size']
                    and [value['index'] for value in components] == list(range(guard['size']))
                    and {value['type'] for value in components} == {'Script', 'Attributes'}
                    and all(set(value) == {'index', 'type', 'class'} and type(value['class']) is str and value['class'] for value in components),
                    'bounded native Script+Attributes component metadata')
        else: require(row.get('componentGuard', False) is False, 'component guard evidence attached to unrelated segment')
        commands = row['commands']
        source = ['front', 'equip-a', 'equip-b'] + (['equip-c'] if segment in ('reorder-three', 'cancel') else []) + ['tail']
        if segment == 'dependent': source = ['front', 'transfer', 'equip-nested', 'tail']
        if segment == 'capacity': source = ['front', 'equip-bag', 'transfer', 'tail']
        require([value['name'] for value in commands] == source, 'unchanged native source producer order')
        expected_order = list(source)
        if editing and segment == 'reorder-two': expected_order = ['front', 'equip-b', 'equip-a', 'tail']
        elif editing and segment == 'reorder-three': expected_order = ['front', 'equip-c', 'equip-a', 'equip-b', 'tail']
        elif editing and segment == 'cancel': expected_order.remove('equip-c')
        require(row['pendingOrder'] == expected_order, 'committed native queue edit/source-order control')
        sequences = []; performed = []
        for command in commands:
            name = command['name']; cancelled = editing and segment == 'cancel' and name == 'equip-c'
            require(command['callbacksUntouched'] is True and type(command['duration']) in (int, float) and command['duration'] > 0, 'native callbacks/duration')
            wanted_item = name.removeprefix('equip-')
            if name == 'equip-bag': wanted_item = 'heldBag'
            if name == 'transfer': wanted_item = 'nested'
            require(command['item'] == specs[wanted_item]['id'], 'native action exact input')
            if name.startswith('equip-'):
                require(command['type'] == 'ISEquipWeaponAction' and command['duration'] == 50 and command['maxTimeInit'] == 50
                        and command['twoHands'] is False and type(command['primary']) is bool and command['primary'] is not (segment == 'reorder-three' and name in ('equip-a', 'equip-c') or segment == 'cancel' and name == 'equip-b'), 'explicit unchanged native equip controls')
            else: require(command['type'] == ('ISInventoryTransferAction' if name == 'transfer' else 'ISReadABook'), 'native action class')
            events = command['lifecycle']; require(type(events) is list, 'native lifecycle list')
            for event in events:
                require(type(event['sequence']) is int and event['sequence'] > 0, 'native lifecycle sequence'); sequences.append(event['sequence'])
                location = event['itemLocation']
                require(type(location) is dict and set(location) == {'root', 'containerPresent', 'owner'}
                        and type(location['root']) is bool and type(location['containerPresent']) is bool
                        and (location['owner'] is False or type(location['owner']) is int and location['owner'] in {spec['id'] for spec in specs.values()})
                        and (not location['root'] or location['containerPresent'] and location['owner'] is False), 'observed native item location')
            if cancelled:
                require(command.get('cancelled') is True and command['started'] is False and command['progress'] is False
                        and not any(value['event'] == 'begin' for value in events), 'cancelled Equip ran or lost evidence')
                continue
            require(command.get('cancelled') is not True, 'native control unexpectedly cancelled')
            finishes = [value for value in events if value['event'] == 'finish' and value['phase'] == 'perform']
            require(len(finishes) == 1 and finishes[0]['succeeded'] is True and type(finishes[0]['nativeEpisode']) is int
                    and finishes[0]['nativeEpisode'] > 0 and finishes[0]['nativeClass'] == 'LuaTimedActionNew', 'actual native perform episode')
            if selection['kind'] == 'sp':
                complete = [value for value in events if value['event'] == 'finish' and value['phase'] == 'complete']
                require(len(complete) == 1 and complete[0]['succeeded'] is True, 'SP native complete boundary')
                if segment in ('dependent', 'capacity') and name == 'transfer':
                    require(complete[0]['itemLocation'] == dict(root=True, containerPresent=True, owner=False), 'SP native transfer effect before P4 restoration')
                if segment in ('dependent', 'capacity') and name.startswith('equip-'):
                    require(complete[0]['hands'] == dict(primary=command['item'], secondary=False)
                            and complete[0]['itemLocation'] == dict(root=True, containerPresent=True, owner=False), 'SP native equip effect before P4 restoration')
            if name in ('front', 'tail'): require(command['started'] is True and command['progress'] is True, 'paid native reader progress')
            performed.append((finishes[0]['sequence'], name))
        require(len(set(sequences)) == len(sequences), 'duplicate native callback receipts')
        require([name for _, name in sorted(performed)] == expected_order, 'actual native execution order differs from edited/source order')
        return []
    except (ValueError, KeyError, TypeError) as error:
        return ['Equip edit evidence differs: ' + str(error)]


def verify(root, selection, catalog):
    root = Path(root); issues = []; outcomes = []
    try:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        events = [value for value in report.events(text) if value.get('suite') == 'magazine-unload']
        setups = [value for value in events if value.get('event') == 'setup']; ends = [value for value in events if value.get('event') == 'complete']
        cases = [value for value in events if value.get('event') == 'case']
        require(len(setups) == len(ends) == len(cases) == 1 and cases[0]['id'] == 'equip-edit' and cases[0]['status'] == 'passed', 'single complete equip-edit group')
        require(setups[0]['cases'] == selection['cases'] == ['equip-edit'] and setups[0]['segments'] == list(SEGMENTS)
                and setups[0]['queueEnabled'] is (selection['mode'] == 'toolkit') and setups[0]['nativeDurations'] is True, 'equip selection/setup')
        require(ends[0]['cases'] == ['equip-edit'] and ends[0]['performed'] == 1 and ends[0]['failed'] == ends[0]['skipped'] == 0, 'complete equip group')
        row = cases[0]; segments = row['segments']; prepared = raw(authority, 'PREPARED'); verified = raw(authority, 'VERIFIED'); placements = raw(text, 'CLIENT_PLACEMENT')
        require(row['actor'] == 'client1' and row['kind'] == selection['kind'] and row['mode'] == selection['mode']
                and row['queueIdle'] is True and row['tidyQuiescent'] is True, 'equip actor/final quiescence')
        require(all([value['segment'] for value in group] == list(SEGMENTS) for group in (segments, prepared, verified, placements)), 'ordered complete equip segment receipts')
        order = [(match.group(1), json.loads(match.group(2))['segment']) for match in re.finditer(re.escape(PREFIX) + r'(PREPARED|VERIFIED) ([^\n]+)', authority)]
        require(order == [(marker, segment) for segment in SEGMENTS for marker in ('PREPARED', 'VERIFIED')], 'authority native segment order')
        for index, segment in enumerate(segments):
            require(placements[index] == dict(case='equip-edit', segment=segment['segment'], proof=segment['clientPlacement']), 'client centered placement evidence')
            issues += check_segment(segment, selection, prepared[index], verified[index])
        from .magazine_unload import complete
        require(complete(selection, 'client1', text), 'equip completion marker')
        for marker in ('VOICE_DISABLED', 'DISPLAY_READY', 'PREFLIGHT_COMPLETE', 'NATIVE_CONNECTED' if selection['kind'] == 'mp' else 'TRUE_SP'):
            require('[QUEUE_TEST] ' + marker in text, 'missing client readiness ' + marker)
        if selection['kind'] == 'mp': require('[STARTUP_TEST] SERVER_READY' in authority, 'native menu Host readiness')
    except (OSError, ValueError, KeyError, TypeError) as error: issues.append(str(error))
    outcomes.append(dict(actor='client1', case='equip-edit', status='failed' if issues else 'passed', reason='; '.join(issues),
        outcome=dict(effectsVerified=not issues, serverAuthorityVerified=not issues, tailCompleted=not issues,
                     pendingEditsVerified=not issues and selection['mode'] == 'toolkit' and selection['kind'] == 'sp',
                     pendingProtectionVerified=not issues and selection['mode'] == 'toolkit', tidyQuiescent=not issues)))
    return dict(issues=issues, outcomes=outcomes, evidence=dict(limits=[
        'Programmatic native constructors with unchanged callbacks/durations; no physical-input or active-edit claim.',
        'New positive Equip rights are SP only; menu Host is a denial control with exact authority inventory/hands.',
        'Low-level dependent/capacity constructors preserve P4 native restoration to the original empty hands and nested source; they make no explicit menu-intent claim or future capacity grant.',
        'P4 quiescence uses real idle callbacks and shared retained-loan diagnostics; its private state tables are not observed.']))
