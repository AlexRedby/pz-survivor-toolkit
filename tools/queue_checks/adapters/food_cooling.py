"""Live appliance power, food cooling and native transfer evidence in SP/menu Host."""
import math
from pathlib import Path
import shutil

from .. import receipts

SUITE = 'food-cooling'
MARKER = '[FOOD_COOLING_TEST] '
PHASES = ('powered-cooling', 'cold-to-ambient', 'ambient-to-cold', 'power-off-thaw')
FOODS = ('chilled', 'frozen', 'control')
ENHANCED_SOURCE_SHA256 = 'f5992aaebc4f629fd6ebb7b049be86a3e0995ea82276b23f22cf921a18bb7cc0'
STACK_COUNTS = {'chilled': 199, 'frozen': 200, 'control': 1}


def definitions():
    return {SUITE: {'status': 'ready', 'clients': 1,
                   'default_mods': ['ZombieBuddy', 'PZToolkitJavaPatches', 'CleanUI', 'PZSurvivorToolkit'],
                   'cases': [{'id': case, 'producer': 'fixture', 'capability': 'effect',
                              'kinds': ['sp', 'mp'], 'languages': ['EN'], 'modes': ['native', 'toolkit']}
                             for case in ('appliances', 'collapsed-stacks')],
                   'limits': ['One owned appliance lifecycle with accelerated world time and ordinary native action durations.',
                              'Generator power transitions; no manual unplug, physical-input, hidden-row or WAN claim.']}}


def validate(selection):
    options = selection.get('options', {})
    if (selection.get('cases') not in (['appliances'], ['collapsed-stacks']) or selection.get('kind') not in ('sp', 'mp')
            or selection.get('mode') not in ('native', 'toolkit') or selection.get('clients', 1) != 1
            or selection.get('languages') != ['EN'] or options.get('world_template') or options.get('seed_run')
            or (selection['kind'] == 'mp' and options.get('mp_host') is not True)):
        raise ValueError('Food cooling requires one appliances/collapsed-stacks case with one EN client in fresh SP/menu Host')


def sources(project, selection):
    root = Path(project) / 'tests/native_queue'
    return [*sorted((root / SUITE).rglob('*.lua')), *sorted((root / 'startup').rglob('*.lua')),
            root / 'health/shared/QueueHealthEvents.lua']


def stage(project, output, game, jdk, selection, locations, runtime):
    validate(selection)
    root = Path(project) / 'tests/native_queue'
    for role in runtime['roles'].values():
        lua = Path(role['cache']) / 'mods/ActionQueueTest/42/media/lua'
        for source, side in [(root / 'startup/client/ZZStartup.lua', 'client'),
                             (root / 'startup/server/ZZStartupServer.lua', 'server'),
                             (root / 'health/shared/QueueHealthEvents.lua', 'shared')]:
            (lua / side).mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, lua / side / source.name)
    runtime['fixture'] = {'server_ready': '[STARTUP_TEST] SERVER_READY',
                          'failure_markers': [MARKER + 'FAIL '], 'sandbox': {'Zombies': 6}}


def _role(selection, role):
    return 'sp' if selection['kind'] == 'sp' else 'server' if role == 'server' else 'client'


def complete(selection, role, text):
    return receipts.records(text, MARKER, 'COMPLETE') == [
        {'suite': SUITE, 'case': selection['cases'][0], 'kind': selection['kind'], 'mode': selection['mode'],
         'role': _role(selection, role), 'phases': len(PHASES), 'restored': True}]


def _require(value, reason):
    if not value:
        raise ValueError(reason)


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def _envelope(row, selection, role):
    _require(all(row.get(key) == value for key, value in dict(suite=SUITE, case=selection['cases'][0],
             kind=selection['kind'], mode=selection['mode'], role=role).items()), 'Receipt ownership differs')


def _settled(row, origin):
    _require(row['origin'] == origin and row['ready'] is True
             and _number(row['stableMs']) and row['stableMs'] >= 1000, 'Native observation position did not settle')
    actor = row['actor']
    _require(all(actor['square' + axis.upper()] == origin[axis] for axis in ('x', 'y', 'z'))
             and all(actor[key] is False for key in ('moving', 'hasPath', 'timedActions')),
             'Actor is moving or outside the shared native observation tile')


def _snapshot(row, ids, endpoint, powered):
    _require(_number(row['world']) and row['minutesPerDay'] == 5, 'Missing measured world clock/rate')
    _require(row['sandbox']['DaysForRottenFoodRemoval'] == -1,
             'Extra rotten-food processing cannot qualify ordinary visible food ageing')
    generator = row['generator']
    _require(generator['active'] is powered and generator['connected'] is True
             and _number(generator['fuel']) and generator['fuel'] > 0
             and _number(generator['condition']) and generator['condition'] > 0,
             'Native generator state differs')
    appliance = row['appliance']
    _require(type(appliance['nickLoaded']) is bool and appliance['unplugged'] is False
             and appliance['auto'] is False, 'Unexpected appliance unplug/automatic state')
    for name, kind in (('fridge', 'fridge'), ('freezer', 'freezer'), ('ambient', 'crate')):
        container = row['containers'][name]
        _require(container['type'] == kind and type(container['powered']) is bool
                 and (name == 'ambient' or container['powered'] is powered),
                 'Native container power/type differs: ' + name)
        _require(all(_number(container[field]) for field in ('temperature', 'customTemperature', 'x', 'y', 'z')),
                 'Incomplete native container state: ' + name)
        _require(container['customTemperature'] <= 0, 'Custom temperature cannot prove real appliance cooling')
        if name == 'ambient':
            _require(container['temperature'] == 1, 'Ambient control container is not at native room temperature')
        elif powered:
            _require(0 < container['temperature'] < 1, 'Powered appliance does not have a native cold temperature')
        else:
            _require(container['temperature'] == 1, 'Unpowered appliance retained a cold temperature')
    expected = {'chilled': endpoint, 'frozen': 'freezer', 'control': 'ambient'}
    for name in FOODS:
        food = row['foods'][name]
        _require(type(food['id']) is int and food['id'] == ids[name] and food['type'] == 'Base.Cabbage'
                 and food['count'] == 1 and food['endpoint'] == expected[name], 'Food identity/endpoint differs: ' + name)
        _require(all(_number(food[key]) for key in ('age', 'lastAged', 'heat', 'freezingTime'))
                 and food['age'] >= 0 and 0 <= food['heat'] <= 3 and food['lastAged'] <= row['world'] + 0.02
                 and 0 <= food['freezingTime'] <= 100
                 and all(type(food[key]) is bool for key in ('frozen', 'isFreezing', 'isThawing')),
                 'Invalid raw thermal/age state: ' + name)


def _phase(row, ids, transition):
    index = row['index']
    before, after = row['before'], row['after']
    endpoint = 'root' if index == 2 else 'fridge'
    powered = index != 4
    _snapshot(before, ids, endpoint, powered)
    _snapshot(after, ids, endpoint, powered)
    elapsed = after['world'] - before['world']
    _require(_number(row['elapsedWorldHours']) and elapsed > 0
             and abs(elapsed - row['elapsedWorldHours']) < 0.001, 'Unmeasured or inconsistent phase time')
    _require(elapsed >= (1.6 if index == 4 else 0.45), 'Insufficient live observation interval')
    for name in FOODS:
        a, b = before['foods'][name], after['foods'][name]
        _require(b['age'] >= a['age'] and b['lastAged'] >= a['lastAged'], 'Native food age moved backwards')
    chilled0, chilled1 = before['foods']['chilled'], after['foods']['chilled']
    frozen0, frozen1 = before['foods']['frozen'], after['foods']['frozen']
    # Transfers, native walking and Host settlement consume time before BEGIN.
    # Thermal changes start at the action, while ageing rates below use only
    # the measured observation interval and each food's actual lastAged clock.
    start_chilled, start_frozen = transition['foods']['chilled'], transition['foods']['frozen']
    _require(transition['world'] <= before['world'] and all(
             transition['foods'][name]['id'] == ids[name] for name in FOODS),
             'Thermal transition baseline is late or belongs to another food')
    control0, control1 = before['foods']['control'], after['foods']['control']
    control_age = control1['age'] - control0['age']
    _require(control_age > 0 and not control1['frozen'], 'Ambient ageing control did not advance')
    control_time = control1['lastAged'] - control0['lastAged']
    chilled_time = chilled1['lastAged'] - chilled0['lastAged']
    _require(control_time > 0 and chilled_time > 0, 'Native ageing clock did not advance')
    control_rate = control_age / control_time
    chilled_rate = (chilled1['age'] - chilled0['age']) / chilled_time
    if index == 1:
        _require(chilled1['heat'] < start_chilled['heat'] and chilled1['heat'] < 0.6,
                 'Powered fridge did not cool food')
        _require(0 < chilled_rate < control_rate * 0.65,
                 'Powered fridge did not slow ageing relative to ambient food')
        _require(start_frozen['freezingTime'] < 100 and frozen1['freezingTime'] == 100 and frozen1['frozen'],
                 'Powered freezer did not freeze food naturally')
    elif index == 2:
        _require(start_chilled['heat'] < 0.6 and chilled1['heat'] > start_chilled['heat'] + 0.05,
                 'Native cold-to-ambient transfer did not warm food')
        _require(chilled1['age'] > chilled0['age'], 'Transferred food did not age in ambient inventory')
        _require(frozen1['frozen'] and frozen1['freezingTime'] == 100, 'Powered freezer lost frozen state')
    elif index == 3:
        _require(chilled1['heat'] < start_chilled['heat'] - 0.05 and chilled1['heat'] < 0.6,
                 'Native ambient-to-cold transfer did not recool food')
        _require(0 < chilled_rate < control_rate * 0.65,
                 'Returned fridge food did not regain slower ageing')
    else:
        _require(start_frozen['frozen'] and start_frozen['freezingTime'] == 100
                 and not frozen1['frozen'] and frozen1['freezingTime'] == 0,
                 'Real generator power loss did not thaw freezer food')
        _require(chilled1['heat'] > start_chilled['heat'] and chilled1['age'] > chilled0['age'],
                 'Unpowered fridge food did not warm and age')
    return {'elapsedWorldHours': elapsed, 'ambientAgeDelta': control_age,
            'chilledAgeDelta': chilled1['age'] - chilled0['age'],
            'chilledAgePerHour': chilled_rate, 'ambientAgePerHour': control_rate,
            'chilledHeatBefore': chilled0['heat'], 'chilledHeatAfter': chilled1['heat'],
            'freezingBefore': frozen0['freezingTime'], 'freezingAfter': frozen1['freezingTime'],
            'transitionHeatBefore': start_chilled['heat'], 'transitionFreezingBefore': start_frozen['freezingTime']}


def verify(root, selection, catalog):
    issues, evidence = [], {}
    try:
        roles = ['sp'] if selection['kind'] == 'sp' else ['client', 'server']
        texts = {role: (Path(root) / ('server-launch.log' if role == 'server' else 'client1-launch.log')).read_text(errors='replace')
                 for role in roles}
        identities = None
        for role, text in texts.items():
            rows = {event: receipts.records(text, MARKER, event) for event in ('SETUP', 'BEGIN', 'PHASE', 'COMMAND', 'RENDERED', 'SETTLED', 'WALK', 'CLEANUP', 'UI_BASELINE', 'UI_RESTORED', 'POSITION_RESTORED')}
            # Keep captured observations on a failed/incomplete run without promoting
            # them to a passed phase or losing the original failure reason.
            evidence[role] = {'rows': rows, 'calculations': []}
            _require(MARKER + 'FAIL ' not in text, 'Native fixture failed: ' + role)
            _require(len(rows['SETUP']) == len(rows['CLEANUP']) == 1, 'Missing/duplicate setup or cleanup')
            _require([(x.get('index'), x.get('name')) for x in rows['PHASE']] == list(enumerate(PHASES, 1)),
                     'Missing/duplicate/out-of-order cooling phases')
            _require([(x.get('index'), x.get('name')) for x in rows['BEGIN']] == list(enumerate(PHASES, 1))
                     and all(begin['snapshot'] == phase['before'] for begin, phase in zip(rows['BEGIN'], rows['PHASE'])),
                     'Phase baseline differs from its native BEGIN receipt')
            for event in rows.values():
                for row in event:
                    _envelope(row, selection, role)
            _require(complete(selection, 'server' if role == 'server' else 'client1', text), 'Incomplete native lifecycle')
            setup, cleanup = rows['SETUP'][0], rows['CLEANUP'][0]
            _require(setup['original']['sandbox']['DaysForRottenFoodRemoval'] == -1
                     and 'DaysForRottenFoodRemoval' not in setup.get('controls', {}),
                     'The ordinary rotten-food-removal setting must be preserved')
            ids = setup['ids']['foods']
            _require(set(ids) == set(FOODS) and all(type(x) is int for x in ids.values())
                     and len(set(ids.values())) == len(FOODS), 'Invalid seeded food identities')
            if identities is None:
                identities = ids
            _require(ids == identities, 'Client/server food identities differ')
            if selection['cases'] == ['collapsed-stacks']:
                members = setup['ids']['stackMembers']
                _require(set(members) == set(FOODS), 'Missing owned collapsed stack membership')
                flat = []
                for name, count in STACK_COUNTS.items():
                    group = members[name]
                    _require(type(group) is list and len(group) == count and group[-1] == ids[name]
                             and all(type(item_id) is int for item_id in group), 'Seeded collapsed tail cardinality/identity differs')
                    flat.extend(group)
                _require(len(set(flat)) == 400 and cleanup['ownedItemCount'] == 400,
                         'Owned collapsed filler identities or cleanup count differ')
                if role == roles[0]:
                    stack_identities = members
                _require(members == stack_identities, 'Client/server owned stack membership differs')
                capacities = setup['ids']['capacities']
                if role == roles[0]: capacity_identities = capacities
                _require(capacities == capacity_identities, 'Client/server native capacity setup differs')
                _require(set(capacities) == {'fridge', 'freezer'}, 'Missing appliance capacity admission')
                for capacity in capacities.values():
                    _require(all(_number(capacity[key]) for key in ('original', 'configured', 'fullWeight'))
                             and 0 < capacity['original'] <= capacity['configured'] <= 100
                             and capacity['configured'] >= capacity['fullWeight'] > 0
                             and capacity['configured'] == max(capacity['original'], math.ceil(capacity['fullWeight'])),
                             'Owned stack bypassed native appliance capacity')
                for phase in rows['PHASE']:
                    for sample in (phase['before'], phase['after']):
                        for name, capacity in capacities.items():
                            container = sample['containers'][name]
                            _require(container['capacity'] == capacity['configured']
                                     and _number(container['contentsWeight']) and 0 < container['contentsWeight'] <= container['capacity'],
                                     'Owned stack exceeds its recorded native capacity')
                if role != 'server':
                    _require(len(rows['UI_BASELINE']) == len(rows['UI_RESTORED']) == len(rows['POSITION_RESTORED']) == 1, 'Missing settled/restored live UI proof')
                    baseline, restored = rows['UI_BASELINE'][0], rows['UI_RESTORED'][0]
                    _require(text.index(MARKER+'UI_BASELINE ') < text.index(MARKER+'SETUP ')
                             and text.rindex(MARKER+'PHASE ') < text.index(MARKER+'POSITION_RESTORED ') < text.index(MARKER+'UI_RESTORED ') < text.index(MARKER+'CLEANUP '),
                             'Original UI capture/restoration order differs')
                    returned = rows['POSITION_RESTORED'][0]
                    original_position, actual_position = returned['original'], returned['actual']
                    _require(returned['deadlineMs'] == 10000 and returned['minimumWaitMs'] == 100
                             and _number(returned['elapsedMs']) and 100 <= returned['elapsedMs'] < 10000
                             and all(_number(original_position[key]) for key in ('x','y','z','squareX','squareY','squareZ'))
                             and all(_number(actual_position[key]) for key in ('x','y','z','squareX','squareY','squareZ','currentSquareX','currentSquareY','currentSquareZ'))
                             and all(abs(actual_position[axis]-original_position[axis]) <= .01 for axis in ('x','y','z'))
                             and all(actual_position[prefix+axis] == original_position['square'+axis]
                                     for prefix in ('square','currentSquare') for axis in ('X','Y','Z'))
                             and actual_position['moving'] is actual_position['hasPath'] is False,
                             'Original actor position did not settle before native container rediscovery')
                    times = baseline['sampleTimesMs']
                    _require(type(baseline['cleanMode']) is bool and baseline['samples'] == len(times) == 3
                             and all(_number(value) for value in times) and all(b-a >= 120 for a,b in zip(times,times[1:]))
                             and baseline['stableSpanMs'] == times[-1]-times[0] >= 240,
                             'Original UI baseline did not settle across three native samples')
                    _require(len(baseline['pages']) == 2, 'Missing original native page baseline')
                    for page in baseline['pages']:
                        _require(page['inventoryBound'] is True and all(_number(page[key]) for key in
                                 ('x','y','width','height','paneX','paneY','paneWidth','paneHeight'))
                                 and page['width'] > 0 and page['height'] > 0 and page['paneWidth'] > 0 and page['paneHeight'] > 0
                                 and page['paneX'] >= 0 and page['paneY'] >= 0
                                 and page['paneX']+page['paneWidth'] <= page['width']+.01
                                 and page['paneY']+page['paneHeight'] <= page['height']+.01,
                                 'Original native pane exceeded its settled owner')
                    _require(restored['cleanMode'] is baseline['cleanMode'] and all(restored[key] is True for key in
                             ('activePages','geometry','bindings','states','selection','anchors','equipped')), 'Original active UI was not restored')


            settled = [x for x in rows['SETTLED'] if x.get('purpose') == 'before-begin']
            _require([x['index'] for x in settled] == list(range(1, 5)), 'Missing settled observation admission for each phase')
            origin = setup['ids']['origin']
            for row in rows['SETTLED']:
                _settled(row, origin)
                if role != 'server':
                    _require(row['queue']['size'] == 0 and row['queue']['idle'] is True,
                             'Native observation admitted pending movement')
                    _settled(row['authority'], origin)
                    _require(row['authority']['index'] == row['index']
                             and row['authority']['sequence'] == row['sequence'], 'Authority settled another observation')
            limits = setup['limits']
            if selection['cases'] == ['collapsed-stacks']:
                _require(limits['stackFoodProcessing'] == 'active-cookable' and limits['rootTransfer'] == 'singleton',
                         'Collapsed cooling coverage limits differ')
            _require(limits['observationAgeWrites'] == 0 and limits['forcedAgeUpdates'] == 0
                     and limits['nativeDurations'] is True and limits['physicalInput'] is False,
                     'Fixture cannot establish native ageing/action behavior')
            transitions = [setup['snapshot']] + [row['after'] for row in rows['PHASE'][:-1]]
            if role != 'server':
                for position, (index, action) in enumerate(((0, 'ISActivateGenerator'), (2, 'ISInventoryTransferAction'),
                                                          (3, 'ISInventoryTransferAction'), (4, 'ISActivateGenerator'))):
                    matches = [row for row in rows['COMMAND'] if row['index'] == index and row['type'] == action]
                    _require(len(matches) == 1, 'Missing/duplicate thermal transition command')
                    transitions[position] = matches[0]['before']
            calculations = [_phase(row, ids, transition) for row, transition in zip(rows['PHASE'], transitions)]
            for previous, current in zip(rows['PHASE'], rows['PHASE'][1:]):
                _require(current['before']['world'] >= previous['after']['world'], 'Phase world clock moved backwards')
                for name in FOODS:
                    _require(current['before']['foods'][name]['age'] >= previous['after']['foods'][name]['age'],
                             'Food age was reset between phases')
            _require(all(cleanup[key] is True for key in ('objectsRemoved', 'ownedIdsAbsent',
                     'originalItemsPreserved', 'queueIdle')), 'Missing owned cleanup or original inventory conservation')
            _require(cleanup['originalItemCount'] == cleanup['remainingOriginalCount']
                     and cleanup['minutesPerDayAfter'] == setup['original']['minutesPerDay']
                     and cleanup['sandboxBefore'] == cleanup['sandboxAfter'] == setup['original']['sandbox'],
                     'Original time/sandbox/inventory state not restored')
            if role != 'server':
                _require([x.get('index') for x in rows['RENDERED']] == list(range(1, 5)),
                         'Missing native visible-row observations for each phase')
                for rendered in rows['RENDERED']:
                    phase = rows['PHASE'][rendered['index'] - 1]
                    expected = {'chilled': 'root' if rendered['index'] == 2 else 'fridge',
                                'frozen': 'freezer', 'control': 'ambient'}
                    _require(set(rendered['foods']) == set(FOODS), 'Missing native rendered food identity')
                    for name, row in rendered['foods'].items():
                        _require(row['id'] == ids[name] and row['endpoint'] == expected[name]
                                 and type(row['passes']) is int and row['passes'] > 0
                                 and all(row[key] is True for key in ('pageVisible', 'paneVisible', 'primary', 'pinned', 'unclipped', 'selected', 'screenBounds'))
                                 and _number(row['world']) and phase['before']['world'] <= row['world'] <= phase['after']['world']
                                 and all(_number(row[key]) for key in ('rowTop', 'rowBottom', 'header', 'height'))
                                 and row['rowBottom'] > row['rowTop'] and row['rowBottom'] > row['header']
                                 and row['rowTop'] < row['height'], 'Food row was not rendered in the native viewport')
                if selection['cases'] == ['collapsed-stacks']:
                    for rendered in rows['RENDERED']:
                        phase = rows['PHASE'][rendered['index'] - 1]
                        expected_helpers = {'frozen'} if rendered['index'] == 2 else {'chilled', 'frozen'}
                        _require(set(rendered['helper']) == expected_helpers, 'Missing admitted collapsed helper delegation')
                        for name, proof in rendered['foods'].items():
                            stack = proof['stack']
                            count = 1 if name == 'chilled' and rendered['index'] == 2 else STACK_COUNTS[name]
                            _require(stack['vanilla'] is True and stack['collapsed'] is True
                                     and stack['actualCount'] == stack['actualIndex'] == count
                                     and stack['tailId'] == ids[name]
                                     and stack['headerId'] == (members[name][0] if count > 1 else ids[name]),
                                     'Native vanilla collapsed tail row/cardinality differs')
                        for name, proof in rendered['helper'].items():
                            count = STACK_COUNTS[name]
                            _require(proof['id'] == proof['tailId'] == ids[name] and proof['headerId'] == members[name][0]
                                     and proof['actualCount'] == proof['actualIndex'] == count
                                     and proof['endpoint'] == ('fridge' if name == 'chilled' else 'freezer')
                                     and proof['admitted'] is proof['delegated'] is True and proof['protocol'] == 1
                                     and proof['enhancedSourceSha256'] == ENHANCED_SOURCE_SHA256,
                                     'Public helper group/protocol/source delegation differs')
                            _require(all(_number(proof[key]) for key in ('intervalBefore', 'intervalAfter',
                                     'beforeLastAged', 'afterLastAged', 'world'))
                                     and proof['intervalAfter'] > 0 and proof['intervalAfter'] != proof['intervalBefore']
                                     and proof['afterLastAged'] >= proof['beforeLastAged']
                                     and proof['afterLastAged'] <= proof['world'] + .02
                                     and phase['before']['world'] <= proof['world'] <= phase['after']['world'],
                                     'Missing actual full-pass admission or invalid passive age observation')
                commands = rows['COMMAND']
                _require(commands and all(x['nativeDuration'] is True and _number(x['duration']) and x['duration'] > 1
                         and x['started'] is True and x['completed'] is True for x in commands),
                         'Native action duration/start/completion missing')
                transfers = [x for x in commands if x['type'] == 'ISInventoryTransferAction']
                _require([(x['index'], x['itemId'], x['source'], x['destination']) for x in transfers] ==
                         [(2, ids['chilled'], 'fridge', 'root'), (3, ids['chilled'], 'root', 'fridge')],
                         'Native transfer identities/endpoints differ')
                _require(any(x['index'] == 0 and x['type'] == 'ISActivateGenerator' for x in commands)
                         and any(x['index'] == 4 and x['type'] == 'ISActivateGenerator' for x in commands),
                         'Missing native generator on/off actions')
                for command in commands:
                    a, b = command['before'], command['after']
                    _require(a['sandbox']['DaysForRottenFoodRemoval'] == b['sandbox']['DaysForRottenFoodRemoval'] == -1,
                             'Native action changed rotten-food processing')
                    _require(b['world'] > a['world'], 'Native action did not consume measured world time')
                    if command['type'] == 'ISInventoryTransferAction':
                        food0, food1 = a['foods']['chilled'], b['foods']['chilled']
                        _require(food0['id'] == food1['id'] == ids['chilled']
                                 and food0['endpoint'] == command['source']
                                 and food1['endpoint'] == command['destination'], 'Native transfer raw effect differs')
                    elif command['type'] == 'ISActivateGenerator':
                        active = command['index'] == 0
                        _require(a['generator']['active'] is not active and b['generator']['active'] is active,
                                 'Native generator raw transition differs')
                        if not active:
                            _require(a['foods']['frozen']['frozen'] and a['foods']['frozen']['freezingTime'] == 100,
                                     'Power-loss command did not start with naturally frozen food')
                    else:
                        _require(command['type'] == 'ISPlugGenerator' and command['index'] == 0
                                 and a['generator']['connected'] is False and b['generator']['connected'] is True,
                                 'Unknown or ineffective native appliance action')
            lifecycle = []
            for line in text.splitlines():
                for event in ('SETUP', 'COMMAND', 'SETTLED', 'BEGIN', 'RENDERED', 'PHASE', 'CLEANUP', 'COMPLETE'):
                    prefix = MARKER + event + ' '
                    if prefix in line:
                        row = receipts.decode_object(line.split(prefix, 1)[1])
                        if event != 'SETTLED' or row['purpose'] == 'before-begin':
                            lifecycle.append((event, row.get('index')))
            expected = [('SETUP', None)]
            if role != 'server':
                expected += [('COMMAND', 0)] * sum(x['index'] == 0 for x in commands)
            for index in range(1, 5):
                if role != 'server' and index > 1:
                    expected.append(('COMMAND', index))
                expected.extend([('SETTLED', index), ('BEGIN', index)])
                if role != 'server':
                    expected.append(('RENDERED', index))
                expected.append(('PHASE', index))
            expected.extend([('CLEANUP', None), ('COMPLETE', None)])
            _require(lifecycle == expected, 'Native admission/render/command lifecycle order differs')
            evidence[role]['calculations'] = calculations
    except (OSError, KeyError, ValueError, TypeError, IndexError) as error:
        issues.append(str(error))
    return {'issues': issues, 'evidence': evidence,
            'coverage': {'case': selection['cases'][0], 'foodProcessing': 'active-cookable',
                         'rootTransfer': 'singleton', 'inertFood': False, 'load': 'fixture-injected'},
            'outcomes': [{'actor': 'client1', 'case': selection['cases'][0], 'status': 'failed' if issues else 'passed',
                          'reason': '; '.join(issues)}]}
