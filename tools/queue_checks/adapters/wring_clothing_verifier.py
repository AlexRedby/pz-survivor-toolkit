"""Read-only report checks over sealed native wring observation receipts."""
import json
import math
from pathlib import Path
import re

from .. import report
from ..placement import validate as validate_placement
from .wring_clothing import CASES, NAMES, PREFIX, PRODUCER, _raw, complete


def _number(value):
    return type(value) in (int, float) and math.isfinite(value)


def _counts(case, name, final):
    # Selected Tidy Up Meister restores the borrowed exact item after the operation.
    return dict(actor=0 if name == 'target' and case == 'world' else 1,
                root=0 if (name == 'target' and case in ('worn-bag', 'world') or name == 'cancelled' and case == 'worn-bag') else 1,
                source=1 if case in ('root', 'worn') or name == 'target' or name == 'cancelled' and case == 'worn-bag' else 0)


def _positive(value):
    return type(value) is int and value > 0


def _prepared(row, selection):
    value = row['prepared']; ids = row['ids']; editing = selection['mode'] == 'toolkit'
    if type(value) is not dict or value['sourceBag'] != ids['source']['bag'] or value['before'] != value['after']:
        raise ValueError('carried pending edits changed physical source/wetness/weight')
    commands = row['commands']; refs = [item['actionRef'] for item in commands]
    if any(type(ref) is not str or not ref for ref in refs) or len(set(refs)) != len(refs):
        raise ValueError('exact native action references')
    count = 3 if editing else 2
    if len(commands) != count * 2 + 2: raise ValueError('mode-specific native preparation topology')
    cancel_indexes = list(range(1, 1 + count)); target_indexes = list(range(1 + count, 1 + count * 2)); tail_index = len(commands) - 1
    tokens = [command['operation'] for command in commands]
    if (not all(_positive(token) for token in tokens)
        or len({tokens[index] for index in cancel_indexes}) != 1 or len({tokens[index] for index in target_indexes}) != 1
        or len({tokens[0], tokens[cancel_indexes[0]], tokens[target_indexes[0]], tokens[tail_index]}) != 4
        or value['front'] != refs[0] or type(value['frontNative']) is not str or not value['frontNative']
        or value['initialOrder'] != refs):
        raise ValueError('genuine native preparation operation ownership/order')
    for name, indexes in [('cancelled', cancel_indexes), ('target', target_indexes)]:
        group = value[name]; first, last = indexes[0], indexes[-1]
        if (group['token'] != tokens[first] or group['fetch'] != refs[last - 1] or group['body'] != refs[last]
            or group['item'] != ids['items'][name]['id'] or group['unallocated'] is not True
            or group['bounds'] != dict(first=first + 1, last=last + 1)
            or (group.get('prep') != refs[first] if editing else group.get('prep', False) is not False)):
            raise ValueError('native preparation/fetch/body group bounds/identity')
        if editing:
            if group['descriptor'] != dict(fetchSource='native.ISInventoryTransferAction', bodySource='native.ISWringClothing',
                item=group['item'], actual='bag', requires='root', fetchSets='root', sourceBag=value['sourceBag'],
                canonical=True, prepSource='toolkit.approach', prepOwned=True,
                prepLease=dict(capacity='unchanged', owner=value['sourceBag'], ownerRoot=True, effectsEmpty=True, fresh=True), bodyCapacity='external', fetchCapacity='external', projection='allowed'):
                raise ValueError('current source facts/root precondition/fetch projection')
            descriptor=group['descriptor']
            if descriptor['canonical'] is not True or descriptor['prepOwned'] is not True or any(descriptor['prepLease'][key] is not True for key in ('ownerRoot','effectsEmpty','fresh')):
                raise ValueError('typed source-bound preparation lease facts')
        elif 'descriptor' in group:
            raise ValueError('disabled control claimed shared descriptor authority')
    retained = [refs[0]] + [refs[index] for index in target_indexes] + [refs[tail_index]]
    if editing:
        group = value['cancelled']
        if group['selected'] != refs[cancel_indexes[-1]] or group['accepted'] is not True or group['afterOrder'] != retained:
            raise ValueError('pending whole carried group cancellation')
        expected_moves = [dict(selected=refs[target_indexes[-2]], after=True, accepted=True,
                               order=[refs[0], refs[tail_index]] + [refs[index] for index in target_indexes], bounds=dict(first=3, last=count + 2)),
                          dict(selected=refs[target_indexes[-1]], after=False, accepted=True, order=retained, bounds=dict(first=2, last=count + 1))]
        if value['moves'] != expected_moves or value['finalOrder'] != retained:
            raise ValueError('fetch-selected/body-selected whole native group move')
    elif value['moves'] != [] or value['finalOrder'] != refs or any(key in value['cancelled'] for key in ('selected', 'accepted', 'afterOrder')):
        raise ValueError('disabled control changed native groups')
    for command in commands:
        if command['type'] == 'ISQueueActionsAction':
            if command['preparation'] != dict(container=value['sourceBag'], owned=True, callbacksUntouched=True) or command['preparation']['owned'] is not True or command['preparation']['callbacksUntouched'] is not True:
                raise ValueError('source-owned carried-container preparation identity')
            if command.get('cancelled'):
                if command['admitted'] is not False or command.get('resolver') or 'rootAtStart' in command:
                    raise ValueError('cancelled deferred resolver was admitted')
            else:
                if command['admitted'] is not True: raise ValueError('real deferred container resolver never admitted')
                events = command['resolver']; phases = {}; native = None
                for event in events:
                    if (event['phase'] not in ('perform', 'complete') or event['boundary'] not in ('begin', 'finish')
                        or event['succeeded'] is not (event['boundary'] == 'finish')
                        or type(event['nativeRef']) is not str or not event['nativeRef'] or event['nativeClass'] != 'LuaTimedActionNew'
                        or event['ownedContainer'] is not True or event['expansionClosed'] is not True or event['unexpectedChildren'] != []
                        or type(event['position']) is not dict or set(event['position']) != {'x','y','z'}
                        or not all(_number(value) for value in event['position'].values())
                        or event['position'] != {key: row['clientPlacement']['actual'][key] for key in ('x','y','z')}):
                        raise ValueError('real native resolver/no-movement/closed empty expansion')
                    if native is not None and event['nativeRef'] != native: raise ValueError('resolver episode changed')
                    native = event['nativeRef']; phases.setdefault(event['phase'], []).append(event['boundary'])
                if phases.get('perform') != ['begin','finish'] or (phases.get('complete') != ['begin','finish'] if selection['kind'] == 'sp' else phases.get('complete', []) not in ([], ['begin','finish'])):
                    raise ValueError('deferred resolver native completion boundaries')
        elif command.get('cancelled'):
            if 'rootAtStart' in command: raise ValueError('cancelled garment was admitted')
        elif command['type'] == 'ISInventoryTransferAction':
            if command['started'] is not True: raise ValueError('native fetch never admitted')
        else:
            start = command['rootAtStart']; spec = ids['items'][command['name']]
            if (start['id'] != spec['id'] or start['type'] != spec['type'] or start['counts'] != dict(actor=1, root=1, source=0)
                or start['native'] != {key: spec[key] for key in ('bodyLocation','bodyLocationClass','nativeShoe','cap')}
                or start['weight'] != spec['weight'] or start['capacityWeight'] != spec['capacityWeight']
                or not _number(start['wetWeight']) or not spec['weight'] <= start['wetWeight'] <= spec['wetWeight'] + .01
                or start['worn'] is not False or not _number(start['wetness']) or not 10 < start['wetness'] <= 100):
                raise ValueError('real body start lacked exact root item after native fetch')
    wanted = {ids['items'][name]['id']: ids['items'][name]['type'] for name in (('target',) if editing else ('target', 'cancelled'))}
    returned = set(); returns = value['returns']
    if type(returns) is not list or not returns: raise ValueError('native P4 return observation missing')
    for receipt in returns:
        if (type(receipt['actionRef']) is not str or not receipt['actionRef'] or receipt['type'] != 'ISInventoryTransferAction'
            or receipt['from'] != 'root' or receipt['toBag'] != value['sourceBag'] or receipt['allowMissing'] is not False
            or not _number(receipt['duration']) or (receipt['duration'] != -1 if selection['kind'] == 'mp' else receipt['duration'] <= 0)):
            raise ValueError('native P4 return endpoint/duration/source flags')
        members = receipt['items']
        if (type(members) is not list or not members or len({item['id'] for item in members}) != len(members)
            or any(type(item['id']) is not int or wanted.get(item['id']) != item['type'] for item in members)):
            raise ValueError('P4 return retargeted an unearned/wrong item')
        returned.update(item['id'] for item in members)
        events = receipt['events']
        if type(events) is not list or not events: raise ValueError('native P4 return callbacks missing')
        opened = {}; finished = False
        for event in events:
            key = (event['phase'], event['nativeRef'])
            if event['phase'] not in ('perform', 'complete') or type(event['nativeRef']) is not str or not event['nativeRef']:
                raise ValueError('native P4 return allocation/phase missing')
            if event['boundary'] == 'begin':
                if key in opened: raise ValueError('duplicate native return callback begin')
                opened[key] = True
            elif event['boundary'] == 'finish' and event.get('succeeded') is True and opened.pop(key, False):
                finished = finished or event['phase'] == 'perform'
            else: raise ValueError('unsuccessful/unpaired native P4 return callback')
        if opened or not finished: raise ValueError('native P4 return perform did not finish')
    if returned != set(wanted): raise ValueError('native P4 return omitted exact borrowed identity')


def check_case(row, selection, prepared, verified, wear_baseline=None):
    issues = []
    try:
        ids = row['ids']; case = ids['case']; editing = selection['mode'] == 'toolkit' and case == 'root'; carried = case == 'worn-bag'; group_editing = carried and selection['mode'] == 'toolkit'
        native_wear = selection['kind'] == 'mp' and case in ('worn', 'worn-bag')
        if ids != prepared or case not in CASES or ids['mode'] != selection['mode'] or row['server'] != verified:
            raise ValueError('authority or selected identity')
        if ids.get('preparedGroups', False) is not carried:
            raise ValueError('carried group fixture declaration')
        if ids.get('nativeWearSetup', False) is not native_wear:
            raise ValueError('native owner wear setup declaration')
        if native_wear:
            wear = row['wearSetup']
            item = ids['items']['target']['id'] if case == 'worn' else ids['source']['bag']
            if (wear['type'] != 'ISWearClothing' or wear['producer'] != 'native ISWearClothing constructor'
                or wear['item'] != item or wear['duration'] != 50 or wear['started'] is not True
                or wear['progress'] is not True or not _number(wear['startedAt'])):
                raise ValueError('real native owner wear setup')
            if wear_baseline is not None and row['authorityBaseline'] != wear_baseline:
                raise ValueError('native wear authority baseline receipt')
        elif row.get('wearSetup', False) is not False or row.get('authorityBaseline', False) is not False:
            raise ValueError('unexpected native wear setup')
        validate_placement(row['clientPlacement'], ids['origin'], 'local', centered=True)
        validate_placement(ids['placementProof'], ids['origin'], 'replica' if selection['kind'] == 'mp' else 'local', centered=True)
        source = ids['source']
        if set(source) != {'kind', 'bag', 'world'} or source['kind'] != case:
            raise ValueError('source identity')
        if (type(source['bag']) is not int if case == 'worn-bag' else source['bag'] is not False):
            raise ValueError('worn bag identity')
        if case == 'world':
            world = source['world']; origin = ids['origin']
            if (set(world) != {'x', 'y', 'z', 'index'} or any(type(v) is not int for v in world.values())
                or world['index'] < 0 or world['x'] != origin['x'] or world['y'] != origin['y'] - 1 or world['z'] != origin['z']):
                raise ValueError('furniture identity')
        elif source['world'] is not False:
            raise ValueError('unexpected world source')
        specs = ids['items']
        if set(specs) != set(NAMES) or len({v['id'] for v in specs.values()}) != len(NAMES):
            raise ValueError('fixture clothing identities')
        for name, spec in specs.items():
            shoes = name == 'tail' or name == 'target' and case in ('worn', 'world')
            if (type(spec['id']) is not int or spec['type'] != ('Base.Shoes_FlipFlop' if shoes else 'Base.Socks_Ankle')
                or spec['cap'] != 10 or spec['nativeShoe'] is not False or spec['bodyLocationClass'] != 'ItemBodyLocation'
                or spec['bodyLocation'] != ('base:shoes' if shoes else 'base:socks') or spec['initial'] != 100
                or not _number(spec['weight']) or spec['weight'] <= 0):
                raise ValueError('native clothing type/cap/initial state')
        phases = [(phase, row[phase]) for phase in (('input', 'authorityBaseline', 'client', 'server') if native_wear else ('input', 'client', 'server'))]
        if carried: phases += [('pending', row['prepared']['before']), ('pending', row['prepared']['after'])]
        for phase, snapshot in phases:
            final = phase in ('client', 'server')
            if snapshot['case'] != case or snapshot['source'] != source or set(snapshot['items']) != set(NAMES):
                raise ValueError('snapshot identity')
            for name, item in snapshot['items'].items():
                spec = specs[name]
                expected_native = {key: spec[key] for key in ('bodyLocation', 'bodyLocationClass', 'nativeShoe', 'cap')}
                if (item['id'] != spec['id'] or item['type'] != spec['type'] or item['counts'] != _counts(case, name, final)
                    or item['native'] != expected_native
                    or item['worn'] is not (not final and case == 'worn' and name == 'target')
                    or not _number(item['weight']) or not 0 < item['weight'] <= spec['weight'] + .01
                    or not _number(item['wetness'])):
                    raise ValueError('clothing identity/source/weight/worn state')
                if carried:
                    if (not _number(spec['wetWeight']) or not _number(spec['capacityWeight']) or spec['capacityWeight'] <= 0
                        or not _number(item['wetWeight']) or not spec['weight'] <= item['wetWeight'] <= spec['wetWeight'] + .01
                        or type(item['capacityWeight']) not in (int, float) or item['capacityWeight'] != spec['capacityWeight']):
                        raise ValueError('current wet/native capacity weight bounds')
                untouched = name == 'cancelled' and not(carried and selection['mode'] == 'native')
                low, high = (80, 100) if not final or untouched else (spec['cap'] - 5, spec['cap'] + .01)
                if not low < item['wetness'] <= high:
                    raise ValueError('wetness effect or untouched cancelled garment')
        if (row['status'] != 'passed' or row['queueIdle'] is not True or not _number(row['settleMilliseconds'])
            or row['settleMilliseconds'] < 1000 or row['edit'] != dict(cancelled=editing or group_editing, reordered=editing or group_editing, repeatDenied=editing, untouched=True)):
            raise ValueError('pending edit/idle evidence')
        commands = row['commands']
        prelude = [('target', 'ISUnequipAction')] if case == 'worn' else [('target', 'ISInventoryTransferAction')] if case in ('worn-bag', 'world') else []
        expected = [('front', 'ISWringClothing')]
        if carried:
            expected += ([('cancelled', 'ISQueueActionsAction')] if group_editing else []) + [('cancelled', 'ISInventoryTransferAction'), ('cancelled', 'ISWringClothing')]
            if group_editing: prelude = [('target', 'ISQueueActionsAction')] + prelude
        elif editing: expected += [('cancelled', 'ISWringClothing')]
        expected += prelude + [('target', 'ISWringClothing')]
        if editing: expected += [('repeat', 'ISWringClothing')]
        expected += [('tail', 'ISWringClothing')]
        if [(c['name'], c['type']) for c in commands] != expected:
            raise ValueError('complete native producer sequence')
        starts = []
        for command in commands:
            name = command['name']; cancelled = editing and name in ('cancelled', 'repeat') or group_editing and name == 'cancelled'
            key = 'target' if name == 'repeat' else name
            # The native MP transfer wrapper waits for ItemTransactionPacket;
            # its constructor deliberately sets maxTime=-1, not a paid duration.
            transaction_wait = command['type'] == 'ISInventoryTransferAction' and selection['kind'] == 'mp' or command['type'] == 'ISQueueActionsAction' and group_editing
            duration_valid = _number(command['duration']) and (command['duration'] == -1 if transaction_wait else command['duration'] > 0)
            if (command['producer'] != PRODUCER or command['item'] != specs[key]['id']
                or not duration_valid
                or bool(command.get('cancelled')) != cancelled):
                raise ValueError('native producer or cancellation identity')
            if cancelled:
                if command['started'] is not False or command['progress'] is not False or 'startedAt' in command:
                    raise ValueError('cancelled action started')
            elif command['type'] == 'ISWringClothing':
                if command['started'] is not True or command['progress'] is not True or not _number(command.get('startedAt')):
                    raise ValueError('native wring progress')
                starts.append(command['startedAt'])
            if command['type'] == 'ISWringClothing':
                wetness = command['constructorWetness']
                if (command['callbacksUntouched'] is not True or not _number(wetness) or not 80 < wetness <= 100
                    or command['duration'] != math.ceil(wetness * 5)):
                    raise ValueError('native wring callbacks/duration')
        if carried: _prepared(row, selection)
        elif row.get('prepared', False) is not False: raise ValueError('unexpected carried group evidence')
        if starts != sorted(starts):
            raise ValueError('native completion order')
        if native_wear and starts[0] <= row['wearSetup']['startedAt']:
            raise ValueError('wring started before native wear setup')
    except (KeyError, TypeError, ValueError, IndexError) as error:
        issues.append('Wring clothing evidence differs: ' + str(error))
    return issues


def verify(root, selection, catalog):
    issues = []; outcomes = []; setups = []; root = Path(root)
    try:
        text = (root / 'client1-launch.log').read_text(errors='replace')
        authority = (root / 'server-launch.log').read_text(errors='replace') if selection['kind'] == 'mp' else text
        events = [e for e in report.events(text) if e.get('suite') == 'wring-clothing']
        rows = [e for e in events if e.get('event') == 'case']
        setups = [e for e in events if e.get('event') == 'setup']; ends = [e for e in events if e.get('event') == 'complete']
        prepared, verified = (_raw(authority, marker) for marker in ('PREPARED', 'VERIFIED'))
        wear_baselines = _raw(authority, 'WEAR_BASELINE')
        placements = _raw(text, 'CLIENT_PLACEMENT'); cases = selection['cases']
        if (len(setups) != 1 or len(ends) != 1 or [r.get('id') for r in rows] != cases
            or any([r.get('case') for r in values] != cases for values in (prepared, verified, placements))):
            raise ValueError('missing, duplicate or out-of-order authority/case evidence')
        wear_cases = [case for case in cases if case in ('worn', 'worn-bag')] if selection['kind'] == 'mp' else []
        if [baseline.get('case') for baseline in wear_baselines] != wear_cases:
            raise ValueError('missing, duplicate or out-of-order native wear baseline')
        ordered_authority = [(match.group(1), json.loads(match.group(2)).get('case')) for match in re.finditer(
            re.escape(PREFIX) + r'(PREPARED|WEAR_BASELINE|VERIFIED) ([^\n]+)', authority)]
        expected_authority = [(marker, case) for case in cases for marker in
                              (('PREPARED', 'WEAR_BASELINE', 'VERIFIED') if case in wear_cases else ('PREPARED', 'VERIFIED'))]
        if ordered_authority != expected_authority:
            raise ValueError('native preparation/baseline/effect authority order')
        if (setups[0].get('cases') != cases or setups[0].get('queueEnabled') is not (selection['mode'] == 'toolkit')
            or setups[0].get('nativeDurations') is not True or ends[0].get('cases') != cases
            or type(setups[0].get('adapterInstalled')) is not bool
            or selection['mode'] == 'toolkit' and setups[0].get('adapterInstalled') is not True
            or ends[0].get('performed') != len(cases) or ends[0].get('failed') != 0 or ends[0].get('skipped') != 0):
            raise ValueError('setup or completion evidence')
        for index, case in enumerate(cases):
            row = rows[index]
            if (row.get('actor') != 'client1' or row.get('kind') != selection['kind'] or row.get('mode') != selection['mode']
                or placements[index] != dict(case=case, proof=row.get('clientPlacement'))):
                raise ValueError('actor or placement receipt')
            baseline = next((value for value in wear_baselines if value['case'] == case), None)
            errors = check_case(row, selection, prepared[index], verified[index], baseline); issues += errors
            outcomes.append(dict(actor='client1', case=case, status='failed' if errors else 'passed', reason='; '.join(errors),
                outcome=dict(effectsVerified=not errors, serverAuthorityVerified=not errors, tailCompleted=not errors,
                             pendingEditsVerified=not errors and selection['mode'] == 'toolkit' and case in ('root', 'worn-bag'))))
        if not complete(selection, 'client1', text): issues.append('Missing completion marker')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return dict(issues=issues, outcomes=outcomes, evidence={'adapterInstalled': setups[0].get('adapterInstalled') if len(setups) == 1 else None, 'limits': [
        'Programmatic native inventory UI callbacks and genuine carried producer groups; no physical input, active edits, missing/full storage recovery or future drying/capacity credit.',
        'Wetness caps allow bounded natural drying after native completion; rain disabled only in the disposable fixture world.']})
