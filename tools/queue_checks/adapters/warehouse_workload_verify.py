"""Validate native peer effects from independent, visibility-scoped raw receipts."""
import math
from pathlib import Path

from .. import receipts

MARKER = '[WAREHOUSE_WORKLOAD] '
STEPS = ('initial', 'peer-transfer', 'peer-replace', 'peer-craft', 'hidden-loot')
EVENTS = {'BASELINE', 'SETUP', 'MODE', 'HIDDEN', 'ACTIONS', 'SNAPSHOT', 'RELEASE',
          'SEED', 'GO', 'SEEN', 'AUTHORITY', 'RESTORED', 'COMPLETE'}


def ensure(value, message):
    if not value:
        raise ValueError('Warehouse workload: ' + message)


def require(row, **values):
    ensure(type(row) is dict, 'receipt is not an object')
    for key, value in values.items():
        ensure(type(row.get(key)) is type(value) and row[key] == value, 'guard differs: ' + key)


def number(value, minimum=None):
    ensure(type(value) in (int, float) and math.isfinite(value), 'invalid numeric evidence')
    ensure(minimum is None or value >= minimum, 'numeric evidence below bound')
    return value


def ids(value, count=None):
    ensure(type(value) is list and (count is None or len(value) == count), 'wrong ID cohort size')
    ensure(all(type(item) is int for item in value) and len(value) == len(set(value)), 'invalid/duplicate IDs')
    return value


def one(rows, event):
    values = [row for name, row in rows if name == event]
    ensure(len(values) == 1, 'expected one ' + event)
    return values[0]


def records(text, role):
    result = []
    for line in text.splitlines():
        if MARKER not in line:
            continue
        event, separator, body = line.split(MARKER, 1)[1].partition(' ')
        ensure(event in EVENTS and separator and body and len(body) <= 262144, 'failed/unknown/malformed event')
        row = receipts.decode_object(body)
        require(row, suite='warehouse-workload', case='peer-edits', kind='mp', mode='toolkit', role=role)
        result.append((event, row))
    return result


def phase_meta(phase, token, index):
    require(phase, token=token, index=index, mode=('clean', 'vanilla')[index-1],
            phaseToken=token + ':' + str(index), recipe='OpenHotdogPack', outputType='Base.Hotdog_single', outputCount=4)
    rows = phase['items']
    ensure(type(rows) is list and len(rows) in (14, 18), 'wrong seeded/output metadata cohort')
    ids([row['id'] for row in rows])
    result = {row['id']: row for row in rows}
    for row in rows:
        ensure(type(row['ft']) is str and row['ft'].startswith('Base.'), 'invalid item type')
        ensure(type(row['key']) is str and bool(row['key']) and type(row['cat']) is str and bool(row['cat']), 'missing item identity/category')
        ensure(row['initialEndpoint'] in [*('crate'+str(i) for i in range(1, 13)), 'client1', 'client2'], 'invalid initial endpoint')
    for key, ft, endpoint in [('transferId', 'Base.Nails', 'crate1'),
                              ('replacementSourceId', 'Base.Bandage', 'crate3'),
                              ('replacementId', 'Base.Bandage', 'client2'),
                              ('craftInputId', 'Base.HotdogPack', 'crate4'),
                              ('quickId', 'Base.Nails', 'crate5'), ('quickMatchId', 'Base.Nails', 'client1')]:
        require(result[phase[key]], ft=ft, initialEndpoint=endpoint)
    require(result[phase['replacementSourceId']], name='Warehouse old bandage')
    require(result[phase['replacementId']], name='Warehouse new bandage')
    ensure(result[phase['replacementSourceId']]['key'] != result[phase['replacementId']]['key'], 'replacement has no distinct identity')
    outputs = ids(phase['outputIds'], 0 if len(rows) == 14 else 4)
    ensure(set(outputs) <= set(result), 'unknown recipe output IDs')
    for key in outputs:
        require(result[key], ft='Base.Hotdog_single', initialEndpoint='client2')
    for slot in range(1, 13):
        entries = [row for row in rows if row['initialEndpoint'] == 'crate'+str(slot)]
        ensure(len(entries) == 1, 'sparse fixture does not have one seed per crate')
        if slot not in (3, 4):
            require(entries[0], ft='Base.Nails')
    return result


def endpoints(phase, step):
    rank = STEPS.index(step)
    expected = {row['id']: row['initialEndpoint'] for row in phase['items']}
    if rank >= 1:
        expected[phase['transferId']] = 'crate2'
    if rank >= 2:
        expected[phase['replacementSourceId']] = 'client2'
        expected[phase['replacementId']] = 'crate3'
    if rank >= 3:
        expected.pop(phase['craftInputId'])
        ensure(len(ids(phase['outputIds'], 4)) == 4, 'missing recipe results')
    else:
        ensure(not phase['outputIds'], 'recipe output existed before crafting')
    if rank >= 4:
        expected[phase['quickId']] = 'client1'
    return expected


def snapshot(row, phase, step, descriptors, originals, role):
    require(row, token=descriptors['token'], visibility='both-roots' if role == 'server' else role)
    meta = {item['id']: item for item in phase['items']} if phase else {}
    expected = endpoints(phase, step) if phase else {}
    if phase:
        require(row, index=phase['index'], phaseToken=phase['phaseToken'])
    visible = {key: where for key, where in expected.items()
               if role == 'server' or where == role or where.startswith('crate')}
    item_rows = row['items']
    ensure(type(item_rows) is list and set(ids([item['id'] for item in item_rows])) == set(visible), 'visible item cohort differs')
    for item in item_rows:
        before = meta[item['id']]
        require(item, endpoint=visible[item['id']], count=1, ft=before['ft'], key=before['key'], cat=before['cat'])
    roots = ('client1', 'client2') if role == 'server' else (role,)
    ensure(type(row['rootIds']) is dict and set(row['rootIds']) == set(roots), 'root visibility differs')
    locations = {}
    for actor in roots:
        actual = ids(row['rootIds'][actor])
        ensure(set(actual) == set(originals[actor]) | {key for key, where in expected.items() if where == actor}, 'root has missing/foreign items')
        locations[actor] = actual
    crates = row['crates']
    ensure(type(crates) is list and len(crates) == 12, 'wrong world-container cohort')
    for slot, (crate, desc) in enumerate(zip(crates, descriptors['crates']), 1):
        require(crate, slot=slot, id=desc['id'], capacity=100)
        ensure(number(crate['weight'], 0) <= number(crate['effectiveCapacity'], 0) + .0001, 'crate overfilled')
        actual = ids(crate['itemIds'])
        ensure(set(actual) == {key for key, where in expected.items() if where == 'crate'+str(slot)}, 'crate IDs/endpoints differ')
        locations['crate'+str(slot)] = actual
    for key, where in visible.items():
        ensure(key in locations[where] and sum(items.count(key) for items in locations.values()) == 1, 'missing/duplicate physical item')


def restored_ui(proof):
    for key, fields in [('flags', ('god', 'ghost', 'autoDrink')), ('core', ('autoDrink', 'focusLoss'))]:
        for side in ('expected', 'actual'):
            ensure(set(proof[key][side]) == set(fields) and all(type(proof[key][side][field]) is bool for field in fields), 'missing original flags/core evidence')
    ensure(type(proof['cleanMode']['expected']) is bool, 'missing original inventory mode')
    for key in ('flags', 'core', 'cleanMode'):
        ensure(proof[key]['expected'] == proof[key]['actual'], 'original UI/core/player state changed')
    ensure(set(proof['options']) == {'enableProximity', 'enableCorpseOnly', 'enableDualMode', 'enableNestedContainers_Loot', 'enableAutoLock'}, 'missing original BC option')
    for row in proof['options'].values():
        ensure(row['expected'] == row['actual'], 'BC option changed')
    ensure(len(proof['pages']) == 2, 'missing restored inventory page')
    for page in proof['pages']:
        require(page, inventoryBound=True, selectionRestored=True)
        ensure(page['expected'] == page['actual'], 'original UI geometry/state changed')
        for key in ('owner', 'pane'):
            state = page['actual'][key]
            for field in ('x', 'y', 'width', 'height', 'maxDrawHeight'):
                number(state[field])
            ensure(state['width'] > 0 and state['height'] > 0 and type(state['visible']) is bool, 'missing original UI bounds/visibility')
        ensure(type(page['actual']['owner']['pin']) is bool and type(page['actual']['owner']['collapsed']) is bool, 'missing original owner state')
        ensure(type(page['actual']['pane']['mode']) is str and bool(page['actual']['pane']['mode']), 'missing original pane mode')
        number(page['actual']['pane']['scroll'])


def position(proof, expected=None):
    require(proof, singlePlacement=True)
    target, actual = proof['target'], proof['actual']
    if expected:
        ensure(all(target[key] == expected[key] for key in ('x', 'y', 'z', 'squareX', 'squareY', 'squareZ')), 'original position target differs')
    require(actual, moving=False, hasPath=False)
    ensure(number(actual['deferredX']) == number(actual['deferredY']) == 0, 'native animation motion still pending')
    ensure(100 <= number(proof['elapsedMs']) <= number(proof['lifecycleElapsedMs']) < 15000, 'position did not settle within bound')
    require(proof, deadlineMs=15000)
    quiet = proof['quiescence']
    require(quiet, minimumStableMs=500)
    number(quiet['stableMs'], 500); number(quiet['samples'], 2)
    for axis in ('x', 'y', 'z'):
        ensure(abs(number(target[axis]) - number(actual[axis])) <= .01, 'fractional native position changed')
        key = axis.upper()
        ensure(actual['square'+key] == actual['currentSquare'+key] == target['square'+key], 'native square changed')


def _server(rows):
    setup = one(rows, 'SETUP'); descriptors = setup['ids']; token = descriptors['token']
    ensure(type(token) is str and bool(token), 'missing session token')
    peers = setup['onlineIds']; ids([peers['client1'], peers['client2']], 2)
    originals = {role: ids(descriptors['originalRootIds'][role]) for role in ('client1', 'client2')}
    original_ids = set(ids(originals['client1'] + originals['client2']))
    ensure(len(descriptors['crates']) == 12, 'missing owned descriptors')
    locations = []
    for slot, desc in enumerate(descriptors['crates'], 1):
        require(desc, token=token+':'+str(slot), ci=0)
        ensure(all(type(desc[key]) is int for key in ('x', 'y', 'z', 'index', 'object')) and desc['index'] >= 0 and desc['index'] == desc['object'], 'invalid owned object location')
        ensure(desc['key'] == ','.join(str(desc[key]) for key in ('x', 'y', 'z')) and desc['id'] == desc['key']+'/'+str(desc['index'])+'/0', 'invalid owned object identity')
        locations.append(desc['id'])
    ensure(len(set(locations)) == 12, 'duplicate owned world object')
    expected_sequence = ['SETUP'] + (['SEED', 'SEEN', 'SEEN'] + ['GO', 'AUTHORITY', 'SEEN', 'SEEN']*4 + ['RELEASE'])*2 + ['RESTORED', 'COMPLETE']
    ensure([name for name, _ in rows] == expected_sequence, 'server lifecycle order/duplicates differ')
    ensure(len([1 for name, _ in rows if name == 'SEEN']) == 20, 'wrong server observation count')
    for _, row in rows:
        require(row, token=token)
    phases = {}
    for index, mode in enumerate(('clean', 'vanilla'), 1):
        selected = [(event, row) for event, row in rows if event in ('SEED', 'GO', 'SEEN', 'AUTHORITY', 'RELEASE') and row.get('index') == index]
        seed = one(selected, 'SEED'); base = seed['phase']; meta = phase_meta(base, token, index)
        readiness = seed['readiness']
        ensure(type(readiness) is dict and set(readiness) == {'client1', 'client2'}, 'missing server placement readiness')
        for role, placement in readiness.items():
            require(placement, deadlineMs=15000, onlineId=peers[role])
            waited = number(placement['waitMs'], 0)
            ensure(waited <= 15000 and number(placement['confirmedAt'], 0)-number(placement['requestedAt'], 0) == waited, 'server placement readiness deadline differs')
            origin = descriptors['actorOrigin']
            ensure(all(abs(number(placement[axis]) - origin[axis] - .5) <= 1 for axis in ('x', 'y')), 'server actor not at fixture origin')
            ensure(number(placement['z']) == placement['squareZ'] == origin['z'] and all(type(placement['square'+axis]) is int for axis in ('X', 'Y', 'Z')), 'server actor square differs')
        ensure(len(meta) == 14, 'initial recipe output/foreign metadata')
        ensure(not original_ids.intersection(meta), 'fixture item aliases an original item')
        snapshot(seed['snapshot'], base, 'initial', descriptors, originals, 'server')
        by_step = {'initial': (base, seed['snapshot'])}
        for event, row in selected:
            require(row, index=index, phaseToken=token+':'+str(index))
            if event != 'RELEASE':
                require(row, paneMode=mode)
        cursor = 1
        for step in STEPS:
            if step != 'initial':
                require(selected[cursor][1], step=step)
                require(selected[cursor+1][1], step=step)
                cursor += 2
            ensure({row['observer'] for _, row in selected[cursor:cursor+2]} == {'client1', 'client2'}, 'missing peer barrier')
            for _, row in selected[cursor:cursor+2]:
                require(row, step=step)
            cursor += 2
        for step in STEPS:
            seen = [row['observer'] for event, row in selected if event == 'SEEN' and row.get('step') == step]
            ensure(sorted(seen) == ['client1', 'client2'], 'both peers did not observe each step exactly once')
            if step == 'initial':
                continue
            gos = [row for event, row in selected if event == 'GO' and row.get('step') == step]
            authorities = [row for event, row in selected if event == 'AUTHORITY' and row.get('step') == step]
            ensure(len(gos) == len(authorities) == 1, 'missing/duplicate native action authority')
            require(gos[0], actor='client1' if step == 'hidden-loot' else 'client2')
            authority = authorities[0]; phase = authority['phase']; current = phase_meta(phase, token, index)
            ensure(all(current[key] == value for key, value in meta.items()), 'seeded metadata changed')
            ensure(not original_ids.intersection(current), 'recipe output aliases an original item')
            meta = current
            ensure(all(phase[key] == base[key] for key in ('transferId', 'replacementSourceId', 'replacementId', 'craftInputId', 'quickId', 'quickMatchId')), 'phase effect identities changed')
            snapshot(authority['snapshot'], phase, step, descriptors, originals, 'server')
            by_step[step] = (phase, authority['snapshot'])
        release = one(selected, 'RELEASE'); final = by_step['hidden-loot'][0]
        ensure(set(ids(release['removedIds'], 17)) == set(endpoints(final, 'hidden-loot')), 'owned release cohort differs')
        ensure(ids(release['consumedIds'], 1) == [base['craftInputId']], 'recipe input was not consumed exactly once')
        require(release, ownedRemaining=0)
        ensure(release['originalRootIds'] == originals, 'release originals differ')
        snapshot(release['snapshot'], None, None, descriptors, originals, 'server')
        phases[index] = dict(steps=by_step, release=release)
    restored = one(rows, 'RESTORED')
    require(restored, removedCrates=12, ownedAbsent=True, ownedRemaining=0)
    ensure(restored['originalRootIds'] == originals and len(restored['crates']) == 12, 'originals/world cleanup proof differs')
    for before, after in zip(descriptors['crates'], restored['crates']):
        ensure(all(after[key] == value for key, value in before.items()) and number(after['afterIndex']) < 0, 'foreign/surviving world object during cleanup')
    snapshot(restored['snapshot'], None, None, descriptors, originals, 'server')
    require(one(rows, 'COMPLETE'), phases=2, restored=True)
    return descriptors, originals, phases, restored


def verify(root):
    root = Path(root)
    rows = {role: records((root / (role+'-launch.log')).read_text(errors='replace'), role)
            for role in ('server', 'client1', 'client2')}
    descriptors, originals, phases, restored = _server(rows['server'])
    for role in ('client1', 'client2'):
        _client(rows[role], role, descriptors, originals, phases, restored)
    return {'phases': 2, 'peers': 2, 'steps': list(STEPS), 'authority': phases,
            'limits': ['Sparse functional native UI callbacks, not a performance or physical-input measurement.']}


def _client(rows, role, descriptors, originals, phases, restored):
    token = descriptors['token']
    baseline = one(rows, 'BASELINE')
    number(baseline['stableSamples'], 3)
    require(baseline['original'], identity=True, payload=True, equipment=True)
    ensure(set(originals[role]) <= set(ids(baseline['original']['ids'])), 'original client root cohort differs')
    ensure(one(rows, 'SETUP')['ids'] == descriptors, 'client setup differs from server world')
    expected_sequence = ['BASELINE', 'SETUP']
    for _ in range(2):
        expected_sequence += ['MODE']
        for step in STEPS:
            if (role == 'client1' and step == 'hidden-loot') or (role == 'client2' and step not in ('initial', 'hidden-loot')):
                expected_sequence += ['ACTIONS']
            expected_sequence += ['HIDDEN', 'SNAPSHOT']
        expected_sequence += ['RELEASE']
    expected_sequence += ['RESTORED', 'COMPLETE']
    ensure([name for name, _ in rows] == expected_sequence, 'client lifecycle order/duplicates differ')
    for event, row in rows:
        if event != 'BASELINE':
            require(row, token=token)
    for index, mode in enumerate(('clean', 'vanilla'), 1):
        selected = [(event, row) for event, row in rows if event in ('MODE', 'ACTIONS', 'HIDDEN', 'SNAPSHOT', 'RELEASE') and row.get('index') == index]
        mode_row = one(selected, 'MODE')
        position(mode_row['placement'])
        origin = descriptors['actorOrigin']; target = mode_row['placement']['target']
        ensure(all(target[key] == origin[key] + (0 if key == 'z' else .5) for key in ('x', 'y', 'z')), 'mode did not use the declared observer origin')
        for event, row in selected:
            require(row, index=index, paneMode=mode)
            if event != 'MODE':
                require(row, phaseToken=token+':'+str(index))
        for step in STEPS:
            phase, authority = phases[index]['steps'][step]
            step_rows = [(event, row) for event, row in selected if row.get('step') == step and event != 'RELEASE']
            hidden = one(step_rows, 'HIDDEN'); observed = one(step_rows, 'SNAPSHOT')
            require(hidden['before'], visible=False)
            require(hidden['after'], visible=False)
            number(hidden['samples'], 1); number(hidden['elapsedMs'], 0)
            if role == 'client1' and step != 'hidden-loot':
                require(hidden['before'], rowsPending=True)
                require(hidden['after'], rowsPending=True)
                ensure(hidden['before']['nativeBuilds'] == hidden['after']['nativeBuilds'], 'hidden idle observer rebuilt rows')
            if role == 'client1' and step == 'peer-transfer':
                walk = hidden['walker']; require(walk, progress=True, returned=True)
                ensure(walk['target'] == descriptors['walkTarget'], 'observer walked to another target')
                ensure(abs(number(walk['reached']['x']) - walk['from']['x']) > .25, 'observer never left its initial position')
            snapshot(observed['native'], phase, step, descriptors, originals, role)
            if step != 'initial':
                ensure(observed['authority'] == authority, 'client referenced another server result')
            _reopen(observed, phase, step, role)
            actor = 'client1' if step == 'hidden-loot' else 'client2'
            if step != 'initial' and role == actor:
                _actions(one(step_rows, 'ACTIONS'), phase, step, mode)
        release = one(selected, 'RELEASE')
        require(release, absent=True)
        ensure(release['receipt'] == phases[index]['release'], 'client released another owned cohort')
        ensure(release['original'] == baseline['original'], 'client original items/equipment changed after phase')
    restored_client = one(rows, 'RESTORED')
    require(restored_client, ownedAbsent=True)
    ensure(restored_client['original'] == restored_client['actual'] == baseline['original'], 'client original state not restored')
    ensure(restored_client['authority'] == restored, 'client cleanup differs from authority')
    position(restored_client['positionProof'], baseline['position'])
    restored_ui(restored_client['uiProof'])
    require(one(rows, 'COMPLETE'), phases=2, restored=True)


def _reopen(row, phase, step, role):
    aggregate = row['aggregateProof']
    require(aggregate, nativeAggregate=True)
    slots = ids(aggregate['discoveredSlots'])
    ensure(slots and set(slots) <= set(range(1, 13)), 'invalid discovered crate sources')
    if role == 'client1':
        ensure({1, 2, 3, 4, 5} <= set(slots), 'observer omitted an exercised shared crate')
    expected = endpoints(phase, step)
    source_names = {'crate'+str(slot) for slot in slots}
    expected_ids = {key for key, where in expected.items() if where in source_names}
    actual_ids = set(ids(aggregate['actualIds']))
    ensure(actual_ids == set(ids(aggregate['expectedIds'])) == expected_ids, 'native aggregate is stale or has foreign items')
    meta = {item['id']: item for item in phase['items']}
    ensure(set(ids([item['id'] for item in aggregate['identities']])) == actual_ids, 'aggregate payload cohort differs')
    for item in aggregate['identities']:
        require(item, key=meta[item['id']]['key'], cat=meta[item['id']]['cat'])
    ui = row['reopen']; require(ui, nativeRows=True, selectedBound=True,
                               selectedKind='crate5' if step == 'hidden-loot' else 'aggregate')
    displayed = {key for key, where in expected.items() if where == 'crate5'} if step == 'hidden-loot' else actual_ids
    ensure(set(ids(ui['rowIds'])) == set(ids(ui['containerIds'])) == displayed, 'reopened UI has stale/missing item identities')
    ensure(type(ui['totalItems']) is int and ui['totalItems'] == ui['expectedTotal'] == len(displayed), 'reopened title count differs')
    require(ui['before'], visible=False)
    require(ui['after'], visible=True, rowsPending=False, countPending=False, tooltipsPending=False)
    if ui['before']['rowsPending']:
        ensure(number(ui['after']['nativeBuilds'], 0) > number(ui['before']['nativeBuilds'], 0), 'reopening did not rebuild deferred rows')
    groups = ui['groups']; ensure(type(groups) is list, 'missing native groups')
    grouped = []
    for group in groups:
        members = ids(group['ids']); grouped += members
        ensure(type(group['count']) is int and group['count'] == len(members), 'native group count differs')
        require(group, nativeCount=len(members)+1)
        if 'realCount' in group:
            require(group, realCount=len(members))
        resolved = group['expectedGroupCategory']
        ensure(type(resolved) is str and bool(resolved), 'missing installed category resolution')
        require(group, groupCategory=resolved)
        categories = group['itemCategories']
        ensure(type(categories) is list and set(ids([item['id'] for item in categories])) == set(members), 'native category item cohort differs')
        for item in categories:
            require(item, rawCategory=meta[item['id']]['cat'], modelCategory=meta[item['id']]['cat'], resolvedCategory=resolved)
        for key in members:
            ensure(key in displayed and group['category'] == meta[key]['cat'], 'native group category differs')
    ensure(set(ids(grouped)) == displayed, 'native grouped rows duplicate or omit physical items')


def _actions(row, phase, step, mode):
    all_actions = row['records']
    ensure(type(all_actions) is list, 'missing native action observations')
    current = [action for action in all_actions if action.get('step') == step]
    for action in current:
        require(action, sourceMethodsUnchanged=True)
        ensure(action['type'] in ('ISInventoryTransferAction', 'ISWalkToTimedAction', 'ISHandcraftAction'), 'foreign native action')
        number(action['duration'])
        number(action['progressSamples'], 0)
        if 'transactionDuration' in action:
            number(action['transactionDuration'], .000001)
            ensure(type(action.get('transactionId')) is int and action['transactionId'] > 0, 'invalid native transaction')
    transfers = [action for action in current if action['type'] == 'ISInventoryTransferAction']
    crafts = [action for action in current if action['type'] == 'ISHandcraftAction']
    expected = {
        'peer-transfer': [(phase['transferId'], 'crate1', 'client2'), (phase['transferId'], 'client2', 'crate2')],
        'peer-replace': [(phase['replacementSourceId'], 'crate3', 'client2'), (phase['replacementId'], 'client2', 'crate3')],
        'peer-craft': [(phase['craftInputId'], 'crate4', 'client2')],
        'hidden-loot': [(phase['quickId'], 'crate5', 'client1')],
    }[step]
    ensure([(a['id'], a['source'], a['destination']) for a in transfers] == expected, 'native transfer batch changed item/order/endpoint')
    if step == 'peer-craft':
        ensure(len(crafts) == 1, 'native craft action count differs')
        dispatch = row['craftDispatch']
        require(dispatch, recipe='OpenHotdogPack', inputId=phase['craftInputId'], source='crate4', nativeMaterials=True,
                outputType='Base.Hotdog_single', outputCount=4)
        ensure(number(dispatch['recipeTime'], .000001)*5 == dispatch['nativeDuration'] == crafts[0]['duration'], 'native crafting duration differs')
        require(crafts[0], recipe='OpenHotdogPack', started=True)
        number(crafts[0]['progressSamples'], 1)
    else:
        ensure(not crafts, 'unexpected native craft action')
    if step == 'hidden-loot':
        require(row['quick'], installedButton=True, hiddenBefore=True, hiddenAfter=True, id=phase['quickId'],
                source='crate5', destination='client1', callback='ISInventoryPage.onTransferByNameClick' if mode == 'clean' else 'ISInventoryPage.lootAll')
