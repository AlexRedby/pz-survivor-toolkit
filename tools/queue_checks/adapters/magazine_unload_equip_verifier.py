"""Exact pending Equip edit evidence, independent of the unload receipt contract."""
import json
import math
from pathlib import Path
import re

from .. import report
from ..placement import validate as validate_placement

SEGMENTS = ('reorder-two', 'reorder-three', 'cancel', 'dependent', 'capacity', 'component-guard')
PREPARED_SEGMENTS = ('prepared-move', 'prepared-cancel-fetch', 'prepared-cancel-body', 'prepared-dependent')
PREFIX = '[EQUIP_EDIT] '


def require(value, reason):
    if not value: raise ValueError(reason)


def selected_segments(selection):
    enabled = selection.get('options', {}).get('equip_prepared', False)
    require(type(enabled) is bool, 'boolean prepared Equip selection')
    return SEGMENTS + (PREPARED_SEGMENTS if enabled else ())


def prepared_rows(selection):
    return (['prepared-approach'] if selection['mode'] == 'toolkit' else []) + ['prepared-fetch', 'prepared-equip']


def source_order(segment, selection):
    if segment in PREPARED_SEGMENTS:
        group = prepared_rows(selection)
        return ['front'] + (group + ['equip-dependent'] if segment == 'prepared-dependent' else ['equip-b'] + group) + ['tail']
    if segment == 'dependent': return ['front', 'transfer', 'equip-nested', 'tail']
    if segment == 'capacity': return ['front', 'equip-bag', 'transfer', 'tail']
    return ['front', 'equip-a', 'equip-b'] + (['equip-c'] if segment in ('reorder-three', 'cancel') else []) + ['tail']


def raw(text, marker):
    return [json.loads(match.group(1)) for match in re.finditer(re.escape(PREFIX + marker + ' ') + r'([^\n]+)', text)]



def check_hand_point(segments, selection, authority):
    """Correlate the optional native server read, never credit it as edit authority."""
    enabled = selection.get('options', {}).get('equip_host_observation', False)
    require(type(enabled) is bool, 'Host hand observation selection')
    receipts = raw(authority, 'HAND_POINT')
    if not enabled:
        require(not receipts and not any(row.get('handPoint') for row in segments), 'unselected Host hand observation')
        return None
    require(selection['kind'] == 'mp' and len(receipts) == 1, 'one selected Host hand observation')
    require(not any(row.get('handPoint') for row in segments[1:]), 'unexpected later Host hand observation')
    evidence = segments[0]['handPoint']
    require(type(evidence) is dict and set(evidence) == {'query', 'server', 'clientHands', 'active', 'authority'}, 'Host hand observation fields')
    query, point = evidence['query'], evidence['server']
    require(type(query) is dict and set(query) == {'segment', 'player', 'transaction', 'token', 'kind'}
            and query['segment'] == segments[0]['segment'] == 'reorder-two' and query['kind'] == 'ISReadABook', 'Host point query identity')
    require(type(query['player']) is int and query['player'] >= 0
            and type(query['transaction']) is int and -128 <= query['transaction'] <= 127 and query['transaction'] != 0
            and type(query['token']) is str and re.fullmatch(r'[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}', query['token']), 'native action token identity')
    fields = {'schema', 'scope', 'player', 'transaction', 'token', 'kind', 'state', 'primaryPresent', 'secondaryPresent',
              'primaryId', 'secondaryId', 'primaryType', 'secondaryType', 'primaryContainerIsRoot', 'secondaryContainerIsRoot',
              'sameItem', 'rootMembershipVerified', 'packetCorrelated', 'effectsVerified', 'editAuthority'}
    require(type(point) is dict and set(point) == fields and type(point['schema']) is int and point['schema'] == 1
            and point['scope'] == 'server-native-active-action-point' and point['state'] == 'accepted', 'server point schema')
    require(all(type(point[key]) is type(query[key]) and point[key] == query[key] for key in ('player', 'transaction', 'token', 'kind')), 'server/client action point identity')
    require(all(point[key] is False for key in ('rootMembershipVerified', 'packetCorrelated', 'effectsVerified', 'editAuthority'))
            and evidence['active'] is True and evidence['authority'] is False, 'observation acquired edit authority')
    require(type(evidence['clientHands']) is dict and set(evidence['clientHands']) == {'primary', 'secondary'}, 'client hand point fields')
    for hand in ('primary', 'secondary'):
        present, item, item_type = (point[hand + key] for key in ('Present', 'Id', 'Type'))
        require(type(present) is bool and type(point[hand + 'ContainerIsRoot']) is bool, 'hand presence metadata')
        require((present and type(item) is int and item >= 0 and type(item_type) is str and bool(item_type))
                or (present is False and item is False and item_type is False and point[hand + 'ContainerIsRoot'] is False), 'canonical hand point metadata')
        require(type(evidence['clientHands'][hand]) is type(item) and evidence['clientHands'][hand] == item, 'server/client point hands differ')
    require(type(point['sameItem']) is bool and (point['sameItem'] is False or point['primaryPresent'] and point['secondaryPresent']
            and point['primaryId'] == point['secondaryId'] and point['primaryType'] == point['secondaryType']), 'hand alias metadata')
    require(receipts == [dict(segment='reorder-two', query=query, point=point)], 'raw server point differs from client receipt')
    return evidence


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
    if segment == 'capacity': return dict(primary=item['heldBag']['id'], secondary=False)
    if segment in PREPARED_SEGMENTS:
        cancelled = editing and segment in ('prepared-cancel-fetch', 'prepared-cancel-body')
        return dict(primary=item['b' if cancelled else 'nested']['id'], secondary=item['b']['id'] if segment == 'prepared-move' else False)
    return dict(primary=False, secondary=False)


def check_callback_observation(value, allow_stop=False):
    require(type(value) is dict and set(value) == {'schema', 'sourceVerified', 'bindingsCurrent', 'classUnchanged',
            'customCallbacksAbsent', 'differences', 'verified'} and type(value['schema']) is int and value['schema'] == 1
            and all(value[name] is True for name in ('sourceVerified', 'bindingsCurrent', 'classUnchanged', 'customCallbacksAbsent', 'verified')),
            'fresh source callback observation')
    differences = value['differences']
    require(type(differences) is list and len(differences) <= 1, 'bounded callback differences')
    if differences:
        change = differences[0]
        require(allow_stop and type(change) is dict and set(change) == {'scope', 'method', 'source', 'line',
                'originalBaseline', 'guardedTransfer', 'exactStopCapture', 'nativeBindingAtAdmission'}
                and change['scope'] == 'action' and change['method'] == 'stop' and change['source'] == 'BulkActions.lua'
                and type(change['line']) is int and change['line'] > 0
                and all(change[name] is True for name in ('originalBaseline', 'guardedTransfer', 'exactStopCapture', 'nativeBindingAtAdmission')),
                'exact source-owned Host transfer stop guard')
    return bool(differences)


def check_owned_observation(value):
    require(type(value) is dict and set(value) == {'schema', 'kind', 'sourceVerified', 'bindingsCurrent',
            'constructorUnchanged', 'verified', 'nativeActionCallbacks', 'paidProgress', 'constructorSource', 'startSource', 'requestSource'}
            and type(value['schema']) is int and value['schema'] == 1 and value['kind'] == 'owned-deferred-carried-container'
            and all(value[key] is True for key in ('sourceVerified', 'bindingsCurrent', 'constructorUnchanged', 'verified'))
            and value['nativeActionCallbacks'] is False and value['paidProgress'] is False
            and value['constructorSource'] == 'ISQueueActionsAction.lua' and value['startSource'] == 'ActionQueueOperations.lua'
            and value['requestSource'] == 'ActionQueueApproach.lua', 'source-owned deferred approach provenance; no paid/native-callback claim')


WORK_HOOKS = ('modSource', 'gameSource', 'captureMatch', 'fingerprintTree', 'registryMatches',
              'dispatchEnter', 'dispatchExit', 'eventTrigger')
WORK_PHASES = ('before-first-equip-command', 'first-drag', 'idle-visible', 'steady-move',
               'steady-cancel', 'changing-drag')
WORK_NATIVE_PHASES = ('queue-disabled-before-commands', 'queue-disabled')


def finite(value):
    return type(value) in (int, float) and math.isfinite(value) and value >= 0


def count(value):
    return finite(value) and value == int(value)


def summary(value, number, total, maximum, positive=False):
    require(type(value) is dict and count(value.get(number)) and (not positive or value[number] > 0)
            and finite(value.get(total)) and finite(value.get(maximum)), 'finite native work summary')
    bound = value[maximum] * value[number]
    require(value[maximum] <= value[total] and (value[total] <= bound or math.isclose(value[total], bound)),
            'consistent native work summary')


def check_work_metrics(value, stage):
    require(type(value) is dict and all(type(item) in (str, bool, int, float) for item in value.values())
            and all(math.isfinite(item) for item in value.values() if type(item) in (int, float)),
            'flat finite native work metrics')
    require(type(value.get('schema')) is int and value['schema'] == 1 and value.get('stage') == stage
            and value.get('active') is True and finite(value.get('elapsedMs'))
            and value.get('source') == 'disposable-jvm-probe' and value.get('timer') == 'relative-System.nanoTime',
            'native work phase/clock scope')
    require(value.get('threadScope') == 'mark-caller-Java-thread; controls-bind-originating-Kahlua-thread'
            and value.get('timingScope') == 'completed-advice-intervals; inclusive-is-nonadditive; self-excludes-nested-instrumented-intervals'
            and value.get('sourceScope') == 'media/lua-relative-source-open-attempts; no-reader-wrapping-or-byte-count'
            and value.get('overheadCorrected') is False and value.get('perCallScopeAllocation') is False
            and type(value.get('overhead')) is str and value['overhead']
            and type(value.get('inactiveHookOverhead')) is str and value['inactiveHookOverhead']
            and value.get('adviceOrderLimit') == 'Event-trigger-interval-may-exclude-sibling-advice; dispatch-helper-intervals-reported-separately'
            and value.get('retention') == 'primitive-stats-and-immutable-source-strings; no-Event-closure-action-arguments',
            'explicit native work overhead/observation limits')
    require(type(value.get('allocatedBytesAvailable')) is bool
            and (finite(value.get('allocatedBytes')) if value['allocatedBytesAvailable'] else value.get('allocatedBytes') == -1),
            'optional current-thread allocation sample')
    require(value.get('diagnostic') == '' and count(value.get('droppedCalls')) and value['droppedCalls'] == 0
            and count(value.get('droppedPaths')) and value['droppedPaths'] == 0,
            'native work instrumentation incomplete')
    require(count(value.get('depthCapacity')) and value['depthCapacity'] > 0
            and all(count(value.get(field)) and value[field] <= value['depthCapacity'] for field in ('openDepth', 'discardedOpen')),
            'bounded native open/omitted intervals')
    observed = set()
    for hook in WORK_HOOKS:
        calls, completed = value.get(hook + 'Calls'), value.get(hook + 'Completed')
        total, own, maximum = (value.get(hook + suffix) for suffix in ('InclusiveNs', 'SelfNs', 'MaxNs'))
        require(count(calls) and count(completed) and completed <= calls
                and all(finite(item) for item in (total, own, maximum)) and own <= total
                and maximum <= total and (total <= maximum * completed or math.isclose(total, maximum * completed)),
                'finite consistent native hook counters/timings: ' + hook)
        require(type(value.get(hook + 'Observed')) is bool and value[hook + 'Observed'] is (calls > 0)
                and type(value.get(hook + 'SignatureAvailable')) is bool
                and type(value.get(hook + 'Signature')) is str and value[hook + 'Signature']
                and (calls == 0 or value[hook + 'SignatureAvailable'] is True),
                'actual native hook observation differs from signature availability: ' + hook)
        if calls > 0: observed.add(hook)
    require(count(value.get('pathCapacity')) and value['pathCapacity'] > 0
            and count(value.get('sourcePathCount')) and value['sourcePathCount'] <= value['pathCapacity'],
            'bounded source-open paths')
    paths = set()
    for index in range(1, int(value['sourcePathCount']) + 1):
        prefix = 'source' + str(index)
        mod, path, attempts = value.get(prefix + 'Mod'), value.get(prefix + 'Path'), value.get(prefix + 'Count')
        require(type(mod) is str and mod and len(mod) <= 128 and type(path) is str
                and path.startswith('media/lua/') and len(path) <= 512 and '\\' not in path
                and all(part not in ('', '.', '..') for part in path.split('/'))
                and count(attempts) and attempts > 0 and (mod, path) not in paths, 'relative native source-open attempt')
        paths.add((mod, path))
    return observed


def check_workload(value, selection):
    require(selection['kind'] == 'sp', 'optional Equip work profile supports SP only; Host functional controls remain separate')
    toolkit = selection['mode'] == 'toolkit'
    require(type(value) is dict and set(value) == {'schema', 'input', 'osEventRouting', 'pointerGettersReplaced',
            'requestsFocus', 'renderer', 'phases', 'observerReleased'} | ({'cold', 'cancel'} if toolkit else set())
            and type(value.get('schema')) is int and value['schema'] == 1
            and value.get('observerReleased') is True
            and value.get('input') == 'programmatic-native-widget-handlers' and value.get('renderer') == 'native-UIManager'
            and all(value.get(field) is False for field in ('osEventRouting', 'pointerGettersReplaced', 'requestsFocus')),
            'supported native-widget work scope; no OS routing/focus/pointer replacement')
    phases = value['phases']; names = WORK_PHASES if toolkit else WORK_NATIVE_PHASES
    require(type(phases) is list and all(type(phase) is dict for phase in phases)
            and [phase.get('name') for phase in phases] == list(names), 'ordered complete native work phases')
    observed = set(); open_spans = omitted = 0
    for phase in phases:
        name = phase['name']; metrics = phase.get('metrics')
        require(set(phase) <= {'name', 'metrics', 'panel', 'ticks'}, 'supported native work phase fields')
        observed |= check_work_metrics(metrics, name)
        open_spans += metrics['openDepth']; omitted += metrics['discardedOpen']
        sustained = name in ('idle-visible', 'steady-move', 'steady-cancel', 'changing-drag', 'queue-disabled')
        if sustained or 'ticks' in phase:
            ticks = phase.get('ticks'); summary(ticks, 'count', 'totalMs', 'maxMs', sustained)
            require(set(ticks) == {'count', 'totalMs', 'maxMs'}, 'native tick cadence fields')
        if toolkit and (sustained or name == 'first-drag') or 'panel' in phase:
            panel = phase.get('panel'); summary(panel, 'draws', 'drawMs', 'maxDrawMs', toolkit and sustained)
            require(set(panel) == {'draws', 'drawMs', 'maxDrawMs', 'previewRebuilds'}
                    and count(panel.get('previewRebuilds')) and panel['previewRebuilds'] <= panel['draws'], 'actual native UIManager row draw statistics')
            if not toolkit:
                require(panel['draws'] == panel['drawMs'] == panel['maxDrawMs'] == panel['previewRebuilds'] == 0,
                        'queue-disabled control cannot claim a queue panel')
            elif name == 'idle-visible': require(panel['previewRebuilds'] == 0, 'idle-visible panel rebuilt policy preview')
            elif name in ('steady-move', 'steady-cancel', 'changing-drag'):
                require(panel['previewRebuilds'] > 0, 'hover/drag phase lacks rendered preview rebuilds')
    if toolkit:
        committed = selection['kind'] == 'sp'
        cold = value['cold']
        require(type(cold) is dict and set(cold) == {'pressMs', 'releaseMs', 'committed', 'scope', 'sourceScope', 'nativeHitTesting'}
                and cold.get('scope') == 'first-timed-widget-gesture-not-OS-routing'
                and cold.get('sourceScope') == 'first-family-enqueue-and-gesture-not-filesystem-cold', 'bounded first-family widget scope')
        cancel = value['cancel']
        require(type(cancel) is dict and set(cancel) == {'pressMs', 'releaseMs', 'committed', 'nativeHitTesting', 'metrics'},
                'explicit native-widget cancel result')
        for gesture in (cold, cancel):
            require(finite(gesture.get('pressMs')) and finite(gesture.get('releaseMs'))
                    and gesture.get('committed') is committed and gesture.get('nativeHitTesting') is True,
                    'live native-widget timings/SP commit/Host denial')
        observed |= check_work_metrics(cancel['metrics'], 'cancel-click')
        open_spans += cancel['metrics']['openDepth']; omitted += cancel['metrics']['discardedOpen']
        if committed:
            require({'captureMatch', 'fingerprintTree', 'registryMatches'} <= observed,
                    'positive SP Equip work lacks actual capture/fingerprint/registry observations')
    require({'dispatchEnter', 'dispatchExit', 'eventTrigger'} <= observed,
            'native work lacks actual event/dispatch observations')
    return dict(scope='programmatic native widget handlers and actual UIManager row draws; no physical OS routing',
                observedHooks=sorted(observed), openIntervalsAtSnapshots=open_spans, discardedAtPhaseBoundaries=omitted,
                timing='completed advice intervals only; omitted/open spans are not complete Event costs',
                performanceVerdict=False)


def check_segment(row, selection, prepared, verified):
    try:
        ids = row['ids']; segment = row['segment']; editing = selection['mode'] == 'toolkit'
        prepared_scene = segment in PREPARED_SEGMENTS
        require(segment in selected_segments(selection) and ids == prepared and row['server'] == verified and ids['segment'] == segment
                and ids['case'] == 'equip-edit' and ids['kind'] == selection['kind'] and ids['mode'] == selection['mode'], 'authority/selection segment identity')
        validate_placement(row['clientPlacement'], ids['origin'], 'local', centered=True)
        validate_placement(ids['placementProof'], ids['origin'], 'replica' if selection['kind'] == 'mp' else 'local', centered=True)
        workload = selection.get('options', {}).get('equip_workload', False)
        require(type(workload) is bool and (not workload or selection['kind'] == 'sp'), 'boolean optional Equip work selection; SP only')
        specs = ids['items']; names = {'front', 'tail', 'a', 'b', 'c', 'bag', 'marker'}
        if segment in ('dependent', 'capacity') or prepared_scene: names.add('nested')
        if segment == 'capacity': names.add('heldBag')
        require(set(specs) == names and len({spec['id'] for spec in specs.values()}) == len(specs), 'exact fixture item identities')
        expected_types = dict(front='Base.BookCarpentry1', tail='Base.BookFirstAid1', a='Base.Hammer' if segment == 'component-guard' else 'Base.Nails', b='Base.Screwdriver', c='Base.Screwdriver',
                              bag='Base.Bag_Schoolbag', marker='Base.Nails', nested='Base.Plank' if segment == 'capacity' else 'Base.Pencil', heldBag='Base.Bag_Schoolbag')
        for name, spec in specs.items():
            fields = {'id', 'type', 'class'} | ({'pages'} if name in ('front', 'tail') else set())
            extended = workload and segment == 'reorder-two' and name == 'front'
            if extended: fields.add('initialPages')
            require(set(spec) == fields, 'exact optional native reader seed fields')
            if name in ('front', 'tail'):
                require(type(spec['pages']) is int and spec['pages'] > 1
                        and (not extended or type(spec['initialPages']) is int and spec['initialPages'] == spec['pages'] - 2),
                        'native reader initial pages')
            require(type(spec['id']) is int and spec['id'] >= 0 and spec['type'] == expected_types[name], 'native seed identities/types')
        baseline = rows(ids['inventory']); require(all(spec['id'] in baseline for spec in specs.values()), 'seeded input lost from inventory baseline')
        for name, spec in specs.items():
            expected_class = 'Literature' if name in ('front', 'tail') else 'InventoryContainer' if name in ('bag', 'heldBag') else 'HandWeapon' if name in ('b', 'c', 'nested') or name == 'a' and segment == 'component-guard' else 'ComboItem'
            expected_path = [specs['bag']['id']] if name == 'marker' or name == 'nested' and (segment == 'dependent' or prepared_scene) else [specs['heldBag']['id']] if name == 'nested' else []
            actual = baseline[spec['id']]
            require(spec['class'] == expected_class and actual['type'] == spec['type'] and actual['class'] == expected_class
                    and actual['path'] == expected_path, 'native canonical root/nested factory source')
        require(row['input']['inventory'] == ids['inventory'] and row['input']['hands'] == dict(primary=False, secondary=False), 'native empty hand/input baseline')
        for name in ('front', 'tail'):
            spec = specs[name]; initial = spec.get('initialPages', spec['pages'] - 1)
            require(row['input']['books'][name] == dict(id=spec['id'], present=True, root=True,
                    pages=initial, characterPages=initial, total=spec['pages']), 'exact initial native reader progress')
        if workload and segment == 'reorder-two': check_workload(row.get('workload'), selection)
        else: require(row.get('workload') is None or row.get('workload') is False, 'unexpected native work receipt outside selected first segment')
        for role in ('client', 'server'):
            value = row[role]
            require(value['case'] == 'equip-edit' and value['segment'] == segment and value['backpack'] is True
                    and value['hands'] == expected_hands(ids, editing), 'final native hand identities/backpack')
            current = rows(value['inventory']); require(set(current) == set(baseline), 'exact inventory multiset/count conservation')
            for identifier, before in baseline.items():
                expected = dict(before)
                if prepared_scene and identifier == specs['nested']['id'] and not(editing and segment in ('prepared-cancel-fetch', 'prepared-cancel-body')):
                    expected['path'] = []
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
        if prepared_scene and not native:
            expected_edits = ['prepared-reorder'] if segment == 'prepared-move' else ['dependent-prepared-cancel', 'dependent-prepared-move'] if segment == 'prepared-dependent' else ['prepared-cancel']
        require([value['name'] for value in edits] == expected_edits, 'complete pending edit/negative control sequence')
        for edit in edits:
            allowed = editing and segment in ('reorder-two', 'reorder-three', 'cancel', 'prepared-move', 'prepared-cancel-fetch', 'prepared-cancel-body')
            require(edit['allowed'] is allowed, 'native scheduling edit permission boundary')
            if allowed: require(edit['reason'] is False, 'successful edit carries denial reason')
            if not allowed:
                require(type(edit['reason']) is str and edit['reason'] and edit['queueBefore'] == edit['queueAfter'], 'denied edit must preserve queue')
            require(edit.get('nativeSchedule', False) is (allowed and (selection['kind'] == 'mp' or prepared_scene)), 'native scheduling route evidence')
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
        source = source_order(segment, selection)
        require([value['name'] for value in commands] == source, 'unchanged native source producer order')
        expected_order = list(source)
        if editing and segment == 'reorder-two': expected_order = ['front', 'equip-b', 'equip-a', 'tail']
        elif editing and segment == 'reorder-three': expected_order = ['front', 'equip-c', 'equip-a', 'equip-b', 'tail']
        elif editing and segment == 'cancel': expected_order.remove('equip-c')
        elif editing and segment == 'prepared-move': expected_order = ['front'] + prepared_rows(selection) + ['equip-b', 'tail']
        elif editing and segment in ('prepared-cancel-fetch', 'prepared-cancel-body'):
            expected_order = [name for name in source if name not in prepared_rows(selection)]
        if prepared_scene:
            group = row['preparedGroup']
            require(type(group) is dict and set(group) == {'schema', 'producer', 'scope', 'operationGrouping', 'sourceVerified',
                    'intentRouteVerified', 'tokenShared', 'item', 'sourceOwner', 'destination', 'rows'}
                    and type(group['schema']) is int and group['schema'] == 1
                    and group['producer'] == 'ISInventoryPaneContextMenu.OnPrimaryWeapon'
                    and group['scope'] == 'source-bound-menu-route-and-final-retained-effect'
                    and group['operationGrouping'] == 'ActionQueueOperations.run'
                    and all(group[key] is True for key in ('sourceVerified', 'intentRouteVerified', 'tokenShared'))
                    and group['item'] == specs['nested']['id'] and group['sourceOwner'] == specs['bag']['id']
                    and group['destination'] == 'actor-root' and group['rows'] == prepared_rows(selection), 'genuine source-bound explicit menu group')
        else: require(row.get('preparedGroup') is None or row.get('preparedGroup') is False, 'unselected prepared group receipt')
        require(row['pendingOrder'] == expected_order, 'committed native queue edit/source-order control')
        sequences = []; performed = []
        for command in commands:
            name = command['name']; owned = name == 'prepared-approach'
            cancelled = editing and (segment == 'cancel' and name == 'equip-c' or segment in ('prepared-cancel-fetch', 'prepared-cancel-body') and name in prepared_rows(selection))
            duration = command['duration']
            client_transfer = selection['kind'] == 'mp' and name in ('transfer', 'prepared-fetch')
            require(type(command['callbacksUntouched']) is bool and type(duration) in (int, float) and math.isfinite(duration)
                    and (duration == -1 if client_transfer or owned else duration > 0), 'native callbacks/duration')
            wanted_item = name.removeprefix('equip-')
            if name == 'equip-bag': wanted_item = 'heldBag'
            if name == 'transfer': wanted_item = 'nested'
            if name in ('prepared-fetch', 'prepared-equip', 'equip-dependent'): wanted_item = 'nested'
            if owned:
                require(command['item'] is False and command['type'] == 'ISQueueActionsAction'
                        and command.get('ownedApproach') is True and command.get('paidProgress') is False
                        and command['progress'] is False, 'owned itemless approach is not paid native work')
            else:
                require(command['item'] == specs[wanted_item]['id'] and command.get('ownedApproach', False) is False, 'native action exact input')
            if name in prepared_rows(selection) and prepared_scene:
                require(type(command.get('operation')) is int and command['operation'] == 1, 'prepared shared opaque operation identity')
            if name.startswith('equip-') or name == 'prepared-equip':
                primary = name == 'prepared-equip' or name == 'equip-b' and segment != 'prepared-move'
                require(command['type'] == 'ISEquipWeaponAction' and command['duration'] == 50 and command['maxTimeInit'] == 50
                        and command['twoHands'] is False and type(command['primary']) is bool
                        and (command['primary'] is primary if prepared_scene else command['primary'] is not (segment == 'reorder-three' and name in ('equip-a', 'equip-c') or segment == 'cancel' and name == 'equip-b')), 'explicit unchanged native equip controls')
            elif not owned: require(command['type'] == ('ISInventoryTransferAction' if name in ('transfer', 'prepared-fetch') else 'ISReadABook'), 'native action class')
            untouched = command['callbacksUntouched']
            guarded_stop = not untouched and selection['kind'] == 'mp' and selection['mode'] == 'toolkit' and name in ('transfer', 'prepared-fetch')
            constructor = command.get('callbackConstructor')
            if owned:
                require(untouched is True, 'owned approach callbacks changed')
                check_owned_observation(constructor)
            elif constructor is not None or not untouched or prepared_scene:
                require(not check_callback_observation(constructor), 'native constructor callbacks changed')
            events = command['lifecycle']; require(type(events) is list, 'native lifecycle list')
            changes = []
            for event in events:
                if owned: check_owned_observation(event.get('callbackObservation'))
                elif 'callbackObservation' in event or not untouched or prepared_scene:
                    changed = check_callback_observation(event.get('callbackObservation'), guarded_stop)
                    if changed: changes.append(event)
                require(type(event['sequence']) is int and event['sequence'] > 0, 'native lifecycle sequence'); sequences.append(event['sequence'])
                location = event['itemLocation']
                if owned:
                    require(location is False and event.get('itemIdentity') in (None, False), 'itemless approach claimed native item effect')
                    continue
                require(type(location) is dict and set(location) == {'root', 'containerPresent', 'owner'}
                        and type(location['root']) is bool and type(location['containerPresent']) is bool
                        and (location['owner'] is False or type(location['owner']) is int and location['owner'] in {spec['id'] for spec in specs.values()})
                        and (not location['root'] or location['containerPresent'] and location['owner'] is False), 'observed native item location')
                if prepared_scene:
                    identity = event.get('itemIdentity')
                    require(type(identity) is dict and set(identity) == {'id', 'type', 'class', 'canonicalRoot'}
                            and identity['id'] == command['item'] and identity['type'] == specs[wanted_item]['type']
                            and identity['class'] == specs[wanted_item]['class'] and type(identity['canonicalRoot']) is bool,
                            'actual native action item identity')
                    if command['type'] == 'ISEquipWeaponAction' and event['event'] == 'finish' and event['phase'] == ('perform' if selection['kind'] == 'mp' else 'complete'):
                        require(identity['canonicalRoot'] is True and location == dict(root=True, containerPresent=True, owner=False),
                                'Equip did not resolve canonical post-fetch root item')
            if not untouched:
                require(guarded_stop and changes and changes[0]['event'] == 'admission'
                        and len(changes) == len(events), 'unproven native callback change')
            if cancelled:
                require(command.get('cancelled') is True and command['started'] is False and command['progress'] is False
                        and not any(value['event'] == 'begin' for value in events), 'cancelled Equip ran or lost evidence')
                if prepared_scene: require(events == [], 'unsubmitted whole-group cancellation reached native lifecycle')
                continue
            require(command.get('cancelled') is not True, 'native control unexpectedly cancelled')
            finishes = [value for value in events if value['event'] == 'finish' and value['phase'] == 'perform']
            require(len(finishes) == 1 and finishes[0]['succeeded'] is True and type(finishes[0]['nativeEpisode']) is int
                    and finishes[0]['nativeEpisode'] > 0 and finishes[0]['nativeClass'] == 'LuaTimedActionNew', 'actual native perform episode')
            if selection['kind'] == 'sp' and not owned:
                complete = [value for value in events if value['event'] == 'finish' and value['phase'] == 'complete']
                require(len(complete) == 1 and complete[0]['succeeded'] is True, 'SP native complete boundary')
                if segment in ('dependent', 'capacity') and name == 'transfer' or prepared_scene and name == 'prepared-fetch':
                    require(complete[0]['itemLocation'] == dict(root=True, containerPresent=True, owner=False), 'SP native transfer effect before P4 restoration')
                if segment in ('dependent', 'capacity') and name.startswith('equip-'):
                    require(complete[0]['hands'] == dict(primary=command['item'], secondary=False)
                            and complete[0]['itemLocation'] == dict(root=True, containerPresent=True, owner=False), 'SP native equip effect before P4 restoration')
                if prepared_scene and command['type'] == 'ISEquipWeaponAction':
                    require(complete[0]['hands']['primary' if command['primary'] else 'secondary'] == command['item'],
                            'actual prepared native equip hand effect')
            if name in ('front', 'tail'): require(command['started'] is True and command['progress'] is True, 'paid native reader progress')
            performed.append((finishes[0]['sequence'], name))
        require(len(set(sequences)) == len(sequences), 'duplicate native callback receipts')
        require([name for _, name in sorted(performed)] == expected_order, 'actual native execution order differs from edited/source order')
        return []
    except (ValueError, KeyError, TypeError) as error:
        return ['Equip edit evidence differs: ' + str(error)]


def verify(root, selection, catalog):
    root = Path(root); issues = []; outcomes = []; work_evidence = None; hand_point = None
    try:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        events = [value for value in report.events(text) if value.get('suite') == 'magazine-unload']
        setups = [value for value in events if value.get('event') == 'setup']; ends = [value for value in events if value.get('event') == 'complete']
        cases = [value for value in events if value.get('event') == 'case']
        require(len(setups) == len(ends) == len(cases) == 1 and cases[0]['id'] == 'equip-edit' and cases[0]['status'] == 'passed', 'single complete equip-edit group')
        selected = selected_segments(selection)
        require(setups[0]['cases'] == selection['cases'] == ['equip-edit'] and setups[0]['segments'] == list(selected)
                and setups[0]['queueEnabled'] is (selection['mode'] == 'toolkit') and setups[0]['nativeDurations'] is True, 'equip selection/setup')
        require(ends[0]['cases'] == ['equip-edit'] and ends[0]['performed'] == 1 and ends[0]['failed'] == ends[0]['skipped'] == 0, 'complete equip group')
        row = cases[0]; segments = row['segments']; prepared = raw(authority, 'PREPARED'); verified = raw(authority, 'VERIFIED'); placements = raw(text, 'CLIENT_PLACEMENT')
        require(row['actor'] == 'client1' and row['kind'] == selection['kind'] and row['mode'] == selection['mode']
                and row['queueIdle'] is True and row['tidyQuiescent'] is True, 'equip actor/final quiescence')
        require(all([value['segment'] for value in group] == list(selected) for group in (segments, prepared, verified, placements)), 'ordered complete equip segment receipts')
        order = [(match.group(1), json.loads(match.group(2))['segment']) for match in re.finditer(re.escape(PREFIX) + r'(PREPARED|VERIFIED) ([^\n]+)', authority)]
        require(order == [(marker, segment) for segment in selected for marker in ('PREPARED', 'VERIFIED')], 'authority native segment order')
        for index, segment in enumerate(segments):
            require(placements[index] == dict(case='equip-edit', segment=segment['segment'], proof=segment['clientPlacement']), 'client centered placement evidence')
            issues += check_segment(segment, selection, prepared[index], verified[index])
        hand_point = check_hand_point(segments, selection, authority)
        if selection.get('options', {}).get('equip_workload'):
            work_evidence = check_workload(segments[0].get('workload'), selection)
        from .magazine_unload import complete
        require(complete(selection, 'client1', text), 'equip completion marker')
        for marker in ('VOICE_DISABLED', 'DISPLAY_READY', 'PREFLIGHT_COMPLETE', 'NATIVE_CONNECTED' if selection['kind'] == 'mp' else 'TRUE_SP'):
            require('[QUEUE_TEST] ' + marker in text, 'missing client readiness ' + marker)
        if selection['kind'] == 'mp': require('[STARTUP_TEST] SERVER_READY' in authority, 'native menu Host readiness')
    except (OSError, ValueError, KeyError, TypeError) as error: issues.append(str(error))
    outcomes.append(dict(actor='client1', case='equip-edit', status='failed' if issues else 'passed', reason='; '.join(issues),
        outcome=dict(effectsVerified=not issues, serverAuthorityVerified=not issues, tailCompleted=not issues,
                     pendingEditsVerified=not issues and selection['mode'] == 'toolkit',
                     pendingProtectionVerified=not issues and selection['mode'] == 'toolkit', tidyQuiescent=not issues)))
    return dict(issues=issues, outcomes=outcomes, evidence=dict(workload=work_evidence, handPoint=hand_point,
        preparedSelected=selection.get('options', {}).get('equip_prepared', False), failedPickupQualified=False, limits=[
        'Programmatic native constructors/durations and original delegates; only the exact source-proven local transfer stop guard may differ. No physical-input or active-edit claim.',
        'Original Host positives qualify unsubmitted singleton root-input order. Optional prepared positives qualify only complete untouched carried-bag fetch/Equip menu operations. Native effects/validity remain authoritative; no deterministic hand forecast, active/earned/return edit, replay or future capacity credit.',
        'P4 returns borrowed Pencil/Plank to the original nested source. Native transfer removes only the transferred item from hands: dependent clears held Pencil, capacity preserves the held source bag. No explicit menu-intent claim or future capacity grant.',
        'P4 quiescence uses real idle callbacks and shared retained-loan diagnostics; its private state tables are not observed.',
        'Prepared menu scenes preserve the explicit native menu intent and canonical post-fetch Equip item; itemless owned approach evidence does not claim paid progress or unchanged native callbacks. Authoritative failed-pickup isolation is not qualified by this bank.',
        'Optional work receipts measure programmatic widget handlers and actual UIManager row draws with native pointer getters. No physical OS routing, focus request, filesystem-cold claim, inactive-span cost or whole-project performance verdict. Instrumentation overhead is uncorrected; completed hook intervals omit open/boundary-discarded spans.']))
