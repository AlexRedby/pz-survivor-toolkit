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
                source=1 if case in ('root', 'worn', 'worn-prepared') or name == 'target' or name == 'cancelled' and case == 'worn-bag' else 0)


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
    native_returns = selection.get('options', {}).get('wring_restoration_provider') == 'native-returns'
    if native_returns and not editing:
        if returns != []: raise ValueError('queue-off P4-free control unexpectedly returned clothing')
        return
    if type(returns) is not list or not returns: raise ValueError('native return observation missing')
    if native_returns and len(returns) != 1: raise ValueError('native restoration requires exactly one generated return')
    for receipt in returns:
        if native_returns and receipt.get('bodySettled') is not True:
            raise ValueError('generated return started before exact wring body settled')
        if (type(receipt['actionRef']) is not str or not receipt['actionRef'] or receipt['type'] != 'ISInventoryTransferAction'
            or receipt['from'] != 'root' or receipt['toBag'] != value['sourceBag'] or receipt['allowMissing'] is not native_returns
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


def _restoration(row, selection):
    enabled = selection.get('options', {}).get('wring_restoration_provider') == 'native-returns'
    if not enabled:
        if 'restoration' in row: raise ValueError('unrequested restoration receipt')
        return
    spec = row['ids']['items']['target']; toolkit = selection['mode'] == 'toolkit'
    samples = row.get('restoration', {}).get('samples', [])
    if len(samples) != 3: raise ValueError('missing P4-free loan transitions')
    returned = row['prepared']['returns']
    for sample, (point, state, planned) in zip(samples, (('queued', 'prepare', 0), ('body', 'active', 0), ('final', 'completed', 1))):
        wanted = dict(case='worn-bag', point=point, loaded=False, selected=False, itemId=spec['id'], itemType=spec['type'],
                      state=state if toolkit else False, candidates=1 if toolkit else 0,
                      observedPreparation=toolkit, plannedTransfers=planned if toolkit else 0)
        if point == 'body':
            if toolkit:
                body_index, return_index, tail_index = (sample.get(k) for k in ('bodyIndex', 'returnIndex', 'tailIndex'))
                if (not all(_positive(v) for v in (body_index, return_index, tail_index))
                        or not body_index < return_index < tail_index or len(returned) != 1):
                    raise ValueError('generated return missing between exact body and tail')
                wanted.update(bodyIndex=body_index, returnIndex=return_index, tailIndex=tail_index,
                              returnRef=returned[0]['actionRef'])
            else:
                wanted.update(bodyIndex=sample.get('bodyIndex'), tailIndex=sample.get('tailIndex'), returnIndex=False, returnRef=False)
                if not _positive(wanted['bodyIndex']) or not _positive(wanted['tailIndex']) or wanted['bodyIndex'] >= wanted['tailIndex']:
                    raise ValueError('queue-off native body/tail order differs')
        if sample != wanted: raise ValueError('P4-free provider or exact loan transitions differ')
    if row.get('restoration', {}).get('provider') != 'native-returns':
        raise ValueError('P4-free restoration provider differs')


def _equipment(value):
    if type(value) is not dict or set(value) != {'worn','primary','secondary'} or type(value['worn']) is not list:
        raise ValueError('exact equipment snapshot')
    rows = value['worn']
    if (rows != sorted(rows, key=lambda item: (item['slot'], item['id']))
        or len({item['slot'] for item in rows}) != len(rows) or len({item['id'] for item in rows}) != len(rows)
        or any(set(item) != {'slot','id','type'} or type(item['slot']) is not str or not item['slot']
               or type(item['id']) is not int or type(item['type']) is not str or not item['type'] for item in rows)):
        raise ValueError('single canonical worn slots')
    for key in ('primary','secondary'):
        hand = value[key]
        if hand is not False and (type(hand) is not dict or set(hand) != {'id','type'} or type(hand['id']) is not int or type(hand['type']) is not str):
            raise ValueError('exact native hand identity')
    return value


def _worn_prepared(row, selection, authority_baseline):
    ids = row['ids']; editing = selection['mode'] == 'toolkit'; specs = ids['items']; value = row['wornPrepared']
    if value['capacityFresh'] is not True: raise ValueError('final native clothing freshness witness unavailable')
    base = _equipment(ids['initialEquipment']); original = row['input']; baseline = row['authorityBaseline']
    if authority_baseline is not None and baseline != authority_baseline: raise ValueError('worn authority baseline differs')
    wanted = [dict(slot=specs[name]['bodyLocation'], id=specs[name]['id'], type=specs[name]['type']) for name in ('target','cancelled')]
    if any(item['slot'] in {entry['slot'] for entry in base['worn']} for item in wanted): raise ValueError('fixture displaced unrelated clothing')
    loaded = dict(base, worn=sorted(base['worn'] + wanted, key=lambda item: (item['slot'],item['id'])))
    executed = ('target',) if editing else ('cancelled','target'); removed = {specs[name]['id'] for name in executed}
    final = dict(base, worn=[item for item in loaded['worn'] if item['id'] not in removed])
    for snapshot in (original, baseline, value['before'], value['after']):
        if _equipment(snapshot['equipment']) != loaded: raise ValueError('worn authoritative baseline/other slots')
    if value['before'] != value['after']: raise ValueError('worn pending edit changed physical state')
    for snapshot in (row['client'], row['server']):
        if _equipment(snapshot['equipment']) != final: raise ValueError('native unequip final/other equipment')
    for snapshot in (original, baseline, value['before'], value['after'], row['client'],row['server']):
        if not _number(snapshot['inventoryWeight']) or snapshot['inventoryWeight'] <= 0: raise ValueError('native inventory weight missing')
        for name,item in snapshot['items'].items():
            spec = specs[name]
            if (item['slot'] != spec['bodyLocation'] or item['slotId'] != next((entry['id'] for entry in snapshot['equipment']['worn'] if entry['slot'] == spec['bodyLocation']),False)
                or not _number(spec['capacityWeight']) or spec['capacityWeight'] <= 0 or not _number(spec['equippedWeight']) or spec['equippedWeight'] <= 0
                or item['capacityWeight'] != spec['capacityWeight'] or item['equippedWeight'] != spec['equippedWeight']):
                raise ValueError('native slot/weight identity')
    delta = sum(specs[name]['capacityWeight'] - specs[name]['equippedWeight'] for name in executed)
    for side,snapshot,initial in (('client',row['client'],original),('server',row['server'],baseline)):
        if abs(snapshot['inventoryWeight'] - initial['inventoryWeight'] - delta) > .001: raise ValueError('native unequip load delta')
        transitions = snapshot['unequipTransitions']
        if type(transitions) is not list or sorted(entry['name'] for entry in transitions) != sorted(executed): raise ValueError('native clothing-update physical transition missing/duplicate')
        source_local = selection['kind']=='sp' or side=='server'
        if source_local and [event['name'] for event in transitions] != list(executed):
            raise ValueError('native producer removal order')
        previous_removed = set()
        for event_index,event in enumerate(transitions):
            item = event['item'];spec = specs[event['name']]
            if (item['id'] != spec['id'] or item['type'] != spec['type'] or item['counts'] != dict(actor=1,root=1,source=1)
                or item['worn'] is not False or item['slotId'] is not False or item['slot'] != spec['bodyLocation']
                or not _number(item['wetness']) or not 0 <= item['wetness'] <= spec['initial'] or item['capacityWeight'] != spec['capacityWeight']
                or item['equippedWeight'] != spec['equippedWeight'] or not _number(event['inventoryWeight'])):
                raise ValueError('native clothing-update exact source transition')
            equipment = _equipment(event['equipment'])
            if item['native'] != {key:spec[key] for key in ('bodyLocation','bodyLocationClass','nativeShoe','cap')} or item['weight'] != spec['weight']:
                raise ValueError('native clothing transition predicate/weight drift')
            if editing and next(entry for entry in wanted if entry['id']==specs['cancelled']['id']) not in equipment['worn']:
                raise ValueError('cancelled worn slot changed during native execution')
            if equipment['primary'] != base['primary'] or equipment['secondary'] != base['secondary'] or any(entry not in loaded['worn'] for entry in equipment['worn']) or any(entry not in equipment['worn'] for entry in base['worn']):
                raise ValueError('native transition changed unrelated equipment')
            physical_removed = {key for key in ('target','cancelled') if next(entry for entry in wanted if entry['id']==specs[key]['id']) not in equipment['worn']}
            prefixes = [set(executed[:count]) for count in range(1,len(executed)+1)]
            if (physical_removed not in prefixes or event['name'] not in physical_removed or not previous_removed <= physical_removed
                or source_local and physical_removed != set(executed[:event_index+1])):
                raise ValueError('native physical removal prefix/monotonicity')
            previous_removed = physical_removed
            native_delta = sum(specs[key]['capacityWeight'] - specs[key]['equippedWeight'] for key in physical_removed)
            if abs(event['inventoryWeight'] - initial['inventoryWeight'] - native_delta) > .001:
                raise ValueError('native physical removal cumulative load')
    wear = row['wearSetup']
    if type(wear) is not list or len(wear) != 2: raise ValueError('two genuine native wear setups missing')
    wear_seen = set()
    for wear_index, (name, receipt) in enumerate(zip(('target','cancelled'), wear)):
        if (receipt['type'] != 'ISWearClothing' or receipt['producer'] != 'native ISWearClothing constructor' or receipt['item'] != specs[name]['id']
            or receipt['duration'] != 50 or receipt['started'] is not True or receipt['progress'] is not True or not _number(receipt['startedAt'])):
            raise ValueError('real distinct native wear setup')
        if receipt['callbacksUntouched'] is not True or receipt['name'] != name:
            raise ValueError('native owner wear source/identity')
        phases = {}; episode = None
        for event in receipt['events']:
            if (event['phase'] not in ('perform','complete') or event['boundary'] not in ('begin','finish') or event['succeeded'] is not (event['boundary']=='finish')
                or type(event['nativeRef']) is not str or not event['nativeRef'] or event['nativeClass'] != 'LuaTimedActionNew'
                or event['state']['item']['id'] != specs[name]['id'] or event['state']['item']['type'] != specs[name]['type']
                or event['state']['item']['counts'] != dict(actor=1,root=1,source=1)):
                raise ValueError('native owner wear callback/identity')
            state = event['state']; item = state['item']; equipment = _equipment(state['equipment']); spec = specs[name]
            available = wanted[:wear_index + 1]
            fixture_rows = [entry for entry in equipment['worn'] if entry not in base['worn']]
            present = {entry['id'] for entry in fixture_rows}
            if (equipment['primary'] != base['primary'] or equipment['secondary'] != base['secondary']
                or any(entry not in equipment['worn'] for entry in base['worn']) or any(entry not in available for entry in fixture_rows)
                or not wear_seen <= present):
                raise ValueError('native Wear changed unrelated or previously worn equipment')
            wear_seen.update(present)
            if (type(item['worn']) is not bool or item['worn'] is not (spec['id'] in present)
                or item['slot'] != spec['bodyLocation'] or item['slotId'] != (spec['id'] if item['worn'] else False)
                or item['native'] != {key:spec[key] for key in ('bodyLocation','bodyLocationClass','nativeShoe','cap')}
                or item['weight'] != spec['weight'] or item['capacityWeight'] != spec['capacityWeight'] or item['equippedWeight'] != spec['equippedWeight']
                or not _number(item['wetness']) or not 0 <= item['wetness'] <= spec['initial']):
                raise ValueError('native Wear boundary root/slot/weight identity')
            missing_delta = sum(specs[key]['capacityWeight'] - specs[key]['equippedWeight'] for key in ('target','cancelled') if specs[key]['id'] not in present)
            if not _number(state['inventoryWeight']) or abs(state['inventoryWeight'] - original['inventoryWeight'] - missing_delta) > .001:
                raise ValueError('native Wear boundary load')
            if selection['kind']=='sp':
                count = wear_index + (1 if event['phase']=='complete' and event['boundary']=='finish' else 0)
                expected = dict(base,worn=sorted(base['worn']+wanted[:count],key=lambda entry:(entry['slot'],entry['id'])))
                if equipment != expected: raise ValueError('SP native Wear effect precedes complete or changed another slot')
            if episode is not None and episode != event['nativeRef']: raise ValueError('wear setup episode changed')
            episode = event['nativeRef']; phases.setdefault(event['phase'],[]).append(event['boundary'])
            if event['phase']=='complete' and event['boundary']=='finish' and event['state']['item']['worn'] is not True:
                raise ValueError('native wear complete failed slot')
        if phases.get('perform') != ['begin','finish'] or (phases.get('complete') != ['begin','finish'] if selection['kind']=='sp' else phases.get('complete',[]) not in ([],['begin','finish'])):
            raise ValueError('native wear setup lifecycle missing')
        expected_phases = [('perform','begin'),('perform','finish')] + ([('complete','begin'),('complete','finish')] if 'complete' in phases else [])
        if [(event['phase'],event['boundary']) for event in receipt['events']] != expected_phases: raise ValueError('native Wear setup callback order')
    commands = row['commands']; refs = [command['actionRef'] for command in commands]
    if len(set(refs)) != len(refs) or any(type(ref) is not str or not ref for ref in refs): raise ValueError('worn action identity')
    if value['front'] != refs[0] or not isinstance(value['frontNative'], str) or not value['frontNative'] or value['initialOrder'] != refs:
        raise ValueError('worn front/order identity')
    tokens = [command['operation'] for command in commands]
    if not all(_positive(token) for token in tokens) or tokens[1] != tokens[2] or tokens[3] != tokens[4] or len({tokens[0],tokens[1],tokens[3],tokens[5]}) != 4:
        raise ValueError('native worn operation token identity')
    for name, first in (('cancelled',1),('target',3)):
        group = value[name]
        if (group['token'] != tokens[first] or group['unequip'] != refs[first] or group['body'] != refs[first+1] or group['item'] != specs[name]['id']
            or group['bounds'] != dict(first=first+1,last=first+2) or group['unallocated'] is not True):
            raise ValueError('worn native group bounds')
        if editing:
            if group['descriptor'] != dict(unequipSource='native.ISUnequipAction', bodySource='native.ISWringClothing', item=specs[name]['id'], actual='root',
                worn=True, slot=specs[name]['bodyLocation'], setsWorn=False, capacity='external', bodyCapacity='external', equipmentWriter=True, cancelWaiting=False, moveRequiresProjection=True, projection='allowed', canonical=True):
                raise ValueError('generic native unequip root/slot descriptor')
            if any(group['descriptor'][key] is not True for key in ('worn','equipmentWriter','moveRequiresProjection','canonical')) or any(group['descriptor'][key] is not False for key in ('setsWorn','cancelWaiting')):
                raise ValueError('typed generic unequip facts')
        elif 'descriptor' in group: raise ValueError('disabled control claimed generic unequip descriptor')
    retained = [refs[0],refs[3],refs[4],refs[5]]
    if editing:
        if (value['cancelled']['selected'] != refs[2] or value['cancelled']['accepted'] is not True or value['cancelled']['afterOrder'] != retained
            or value['moves'] != [dict(selected=refs[3],after=True,accepted=True,order=[refs[0],refs[5],refs[3],refs[4]],bounds=dict(first=3,last=4)),
                                 dict(selected=refs[4],after=False,accepted=True,order=retained,bounds=dict(first=2,last=3))] or value['finalOrder'] != retained):
            raise ValueError('native worn whole group cancel/unequip-selected/body-selected moves')
    elif value['finalOrder'] != refs or value['moves'] or any(key in value['cancelled'] for key in ('selected','accepted','afterOrder')): raise ValueError('disabled worn group changed')
    for command in commands:
        name = command['name']; spec = specs[name]
        if command.get('cancelled'):
            if command.get('events') or 'admission' in command: raise ValueError('cancelled worn action admitted')
            continue
        if command['type'] == 'ISUnequipAction' and (command['callbacksUntouched'] is not True or command['cartsGuard'] is not True or command['duration'] != 50):
            raise ValueError('native/Carts unequip callbacks/duration')
        events = command['events']; phases = {}; episode = None; unworn = False
        for event in events:
            if (event['boundary'] not in ('begin','finish') or event['phase'] not in ('perform','complete') or event['succeeded'] is not (event['boundary']=='finish')
                or type(event['nativeRef']) is not str or not event['nativeRef'] or event['nativeClass'] != 'LuaTimedActionNew'):
                raise ValueError('native worn callback allocation/phase')
            if episode is not None and episode != event['nativeRef']: raise ValueError('native worn callback episode changed')
            episode = event['nativeRef']; phases.setdefault(event['phase'],[]).append(event['boundary'])
            observed = event['state']; item = observed['item']; equipment = _equipment(observed['equipment'])
            if type(item['worn']) is not bool: raise ValueError('typed native worn state')
            if item['id'] != spec['id'] or item['type'] != spec['type'] or item['counts'] != dict(actor=1,root=1,source=1) or item['slotId'] != next((entry['id'] for entry in equipment['worn'] if entry['slot'] == spec['bodyLocation']),False):
                raise ValueError('native worn boundary exact identity')
            if equipment['primary'] != base['primary'] or equipment['secondary'] != base['secondary'] or any(entry not in loaded['worn'] for entry in equipment['worn']) or any(entry not in equipment['worn'] for entry in base['worn']):
                raise ValueError('native boundary changed other equipment')
            if editing and next(entry for entry in wanted if entry['id']==specs['cancelled']['id']) not in equipment['worn']:
                raise ValueError('cancelled clothing lost worn slot at native boundary')
            if unworn and item['worn']: raise ValueError('native clothing silently reworn')
            unworn = unworn or not item['worn']
            if command['type'] == 'ISWringClothing' and item['worn']: raise ValueError('native wring ran before real unequip')
            if command['type'] == 'ISUnequipAction' and selection['kind']=='sp' and event['phase']=='complete' and event['boundary']=='finish' and item['worn']:
                raise ValueError('native SP unequip complete retained slot')
        if phases.get('perform') != ['begin','finish'] or (phases.get('complete') != ['begin','finish'] if selection['kind']=='sp' else phases.get('complete',[]) not in ([],['begin','finish'])):
            raise ValueError('native worn callback did not naturally finish')
        expected_phases = [('perform','begin'),('perform','finish')] + ([('complete','begin'),('complete','finish')] if 'complete' in phases else [])
        if [(event['phase'],event['boundary']) for event in events] != expected_phases: raise ValueError('native callback phase order')
        if command['type']=='ISUnequipAction' and command['admission']['item']['worn'] is not True: raise ValueError('unequip admitted wrong source slot')
    if commands[0]['startedAt'] <= wear[-1]['startedAt']: raise ValueError('wring preceded native wear baseline')


def _wear_swap(row, selection, prepared, verified, wear_baseline):
    ids=row['ids']; specs=ids['items']; value=row['wearSwap']; editing=selection['mode']=='toolkit'; host=selection['kind']=='mp'
    names=('front','target','tail','incoming','displaced')
    if (ids!=prepared or row['server']!=verified or ids['case']!='wear-swap' or ids['mode']!=selection['mode']
        or ids.get('wearSwap') is not True or ids.get('nativeWearSetup') is not True or ids.get('wornPrepared',False) is not False
        or ids.get('preparedGroups',False) is not False or set(specs)!=set(names) or len({spec['id'] for spec in specs.values()})!=len(names)):
        raise ValueError('Wear swap exact fixture declaration/authority')
    if ids['source']!=dict(kind='wear-swap',bag=False,world=False): raise ValueError('Wear swap root source')
    validate_placement(row['clientPlacement'],ids['origin'],'local',centered=True)
    validate_placement(ids['placementProof'],ids['origin'],'replica'if host else'local',centered=True)
    catalog={'front':('Base.Socks_Ankle','base:socks',None),'target':('Base.Scarf_White','base:scarf',.2),'tail':('Base.Shoes_FlipFlop','base:shoes',None),
             'incoming':('Base.Gloves_LeatherGloves','base:hands',.1),'displaced':('Base.Gloves_BurlapWrap','base:hands',.2)}
    for name,spec in specs.items():
        full_type,slot,weight=catalog[name]
        if (not _positive(spec['id']) or spec['type']!=full_type or spec['bodyLocation']!=slot or spec['bodyLocationClass']!='ItemBodyLocation'
            or spec['nativeShoe'] is not False or spec['cap']!=10 or spec['initial']!=100
            or not all(_number(spec[key]) and spec[key]>0 for key in ('weight','capacityWeight','equippedWeight'))
            or spec['capacityWeight']!=spec['weight'] or spec['equippedWeight']>spec['capacityWeight'] or weight is not None and abs(spec['weight']-weight)>.000001):
            raise ValueError('Wear swap native catalog/weights')
    base=_equipment(ids['initialEquipment']); rows={name:dict(slot=spec['bodyLocation'],id=spec['id'],type=spec['type'])for name,spec in specs.items()}
    if any(entry['slot'] in ('base:hands','base:scarf')for entry in base['worn']): raise ValueError('Wear swap displaced starter gear')
    baseline=row['authorityBaseline']; initial=row['input']
    if wear_baseline is not None and baseline!=wear_baseline: raise ValueError('Wear swap independent authority baseline')
    def reduction(name):return specs[name]['capacityWeight']-specs[name]['equippedWeight']
    swap_delta=reduction('displaced')-reduction('incoming')
    if swap_delta<=0: raise ValueError('Wear swap lacks positive native load delta')
    def physical(equipment,weight,initial_weight):
        equipment=_equipment(equipment)
        present={name for name in ('target','incoming','displaced')if rows[name]in equipment['worn']}
        wanted=dict(base,worn=sorted(base['worn']+[rows[name]for name in present],key=lambda item:(item['slot'],item['id'])))
        if equipment!=wanted or {'incoming','displaced'}<=present: raise ValueError('Wear swap changed unrelated/aliased equipment')
        expected=initial_weight+reduction('target')+reduction('displaced')-sum(reduction(name)for name in present)
        if not _number(weight)or not _number(initial_weight)or abs(weight-expected)>.001: raise ValueError('Wear swap exact native cumulative load')
        return present
    def item_state(item,name,equipment):
        spec=specs[name];present={entry['id']for entry in equipment['worn']}
        if (item['id']!=spec['id']or item['type']!=spec['type']or item['counts']!=dict(actor=1,root=1,source=1)
            or item['native']!={key:spec[key]for key in ('bodyLocation','bodyLocationClass','nativeShoe','cap')}
            or item['weight']!=spec['weight']or item['capacityWeight']!=spec['capacityWeight']or item['equippedWeight']!=spec['equippedWeight']
            or item['slot']!=spec['bodyLocation']or type(item['worn'])is not bool or item['worn']is not(spec['id']in present)
            or item['slotId']!=next((entry['id']for entry in equipment['worn']if entry['slot']==spec['bodyLocation']),False)
            or not _number(item['wetness'])or not 0<=item['wetness']<=spec['initial']):
            raise ValueError('Wear swap exact native item/root/slot/weight')
    def snapshot(snapshot,initial_weight,allowed):
        if snapshot['case']!='wear-swap'or snapshot['source']!=ids['source']or set(snapshot['items'])!=set(names):raise ValueError('Wear swap snapshot identity')
        present=physical(snapshot['equipment'],snapshot['inventoryWeight'],initial_weight)
        if present not in allowed:raise ValueError('Wear swap physical phase')
        for name,item in snapshot['items'].items():item_state(item,name,snapshot['equipment'])
        return present
    loaded={'target','displaced'};swapped={'target','incoming'};final={'incoming'}
    for snapshot_value in (initial,baseline,value['before']):
        snapshot(snapshot_value,snapshot_value['inventoryWeight'],[loaded])
        if any(not 10<snapshot_value['items'][name]['wetness']<=100 for name in ('front','target','tail')):raise ValueError('Wear prelude native wet setup differs')
    permission=value['permission']
    if permission['fresh']is not True or permission['physical']is not True or permission['before']!=permission['after']:raise ValueError('Wear freshness permission/pending mutation')
    for snapshot_value in (permission['before'],permission['after']):snapshot(snapshot_value,initial['inventoryWeight'],[swapped])
    if value['capacityFresh']is not True:raise ValueError('Wear final freshness missing')
    for side,final_value,start in (('client',row['client'],initial),('server',row['server'],baseline)):
        snapshot(final_value,start['inventoryWeight'],[final])
        for name in ('front','target','tail'):
            if not 0<=final_value['items'][name]['wetness']<=specs[name]['cap']+.01:raise ValueError('Wear bank native wring cap')
        # Host Wear.complete emits no clothing event. The first server event can
        # be Unequip.complete after removal; correlate that deferred observation below.
        transition=final_value['swapTransition'];present=snapshot(transition,start['inventoryWeight'],[swapped,final]if host and side=='server'else[swapped])
        transitions=final_value['unequipTransitions']
        if len(transitions)!=1 or transitions[0]['name']!='target':raise ValueError('Wear retained native removal transition')
        event=transitions[0];physical(event['equipment'],event['inventoryWeight'],start['inventoryWeight'])
        if {entry['id']for entry in event['equipment']['worn']}!={entry['id']for entry in base['worn']}|{specs['incoming']['id']}:raise ValueError('Wear retained removal changed other slots')
        item_state(event['item'],'target',event['equipment'])
        if host and side=='server'and present==final:
            if (transition['items']['target']!=event['item']or transition['equipment']!=event['equipment']
                or transition['inventoryWeight']!=event['inventoryWeight']):
                raise ValueError('Host deferred Wear observation differs from exact native Unequip transition')
    def lifecycle(receipt,name,allowed,initial_weight,sp_effect=None):
        if receipt['callbacksUntouched']is not True or receipt['started']is not True or receipt['progress']is not True or not _number(receipt['startedAt']):raise ValueError('Wear/native action progress/source')
        events=receipt['events'];phases=[];episode=None;seen=None
        for event in events:
            key=(event['phase'],event['boundary']);phases.append(key)
            if (event['phase']not in ('perform','complete')or event['boundary']not in ('begin','finish')or event['succeeded']is not(event['boundary']=='finish')
                or not isinstance(event['nativeRef'],str)or not event['nativeRef']or event['nativeClass']!='LuaTimedActionNew'
                or episode is not None and episode!=event['nativeRef']):raise ValueError('Wear native phase/allocation')
            episode=event['nativeRef'];observed=event['state'];present=physical(observed['equipment'],observed['inventoryWeight'],initial_weight)
            if present not in allowed:raise ValueError('Wear native callback physical phase')
            item_state(observed['item'],name,observed['equipment'])
            if seen is not None and seen!=present and allowed.index(present)<allowed.index(seen):raise ValueError('Wear packet physical state reversed')
            seen=present
            if not host and sp_effect is not None:
                expected=sp_effect[1]if key==('complete','finish')else sp_effect[0]
                if present!=expected:raise ValueError('Wear SP native effect phase')
        expected=[('perform','begin'),('perform','finish')]
        if not host or('complete','begin')in phases:expected+=[('complete','begin'),('complete','finish')]
        if phases!=expected:raise ValueError('Wear native callbacks did not finish naturally')
        return events
    seen_transactions=set()
    def terminal_ack(ack,name):
        if host:
            if (ack['client']is not True or ack['capturePresent']is not True or ack['ackState']!='completed'or type(ack['transaction'])is not int or not -128<=ack['transaction']<=127 or ack['transaction']==0 or ack['kind']!='ISWearClothing'
                or type(ack['generation'])is not int or ack['generation']<0 or any(ack[key]is not True for key in ('nativeSame','itemSame','actorSame','rootSame','queueSame','canonicalRoot','rootOwned','worn','slotSame'))or ack['slotId']!=specs[name]['id']
                or ack['transaction']in seen_transactions):raise ValueError('Wear exact saved native terminal Ack')
            seen_transactions.add(ack['transaction'])
        elif ack!=dict(client=False,capturePresent=False,ackState=False):raise ValueError('SP fabricated Host Wear Ack')
    wear=row['wearSetup']
    if len(wear)!=2:raise ValueError('Wear swap native setup missing')
    for index,name in enumerate(('target','displaced')):
        receipt=wear[index];before=set()if index==0 else{'target'};after={'target'}if index==0 else loaded
        if (receipt['name']!=name or receipt['type']!='ISWearClothing'or receipt['producer']!='native ISWearClothing constructor'or receipt['duration']!=50 or receipt['item']!=specs[name]['id']):raise ValueError('Wear swap genuine setup identity/duration')
        lifecycle(receipt,name,[before,after],initial['inventoryWeight'],(before,after))
        settled=receipt['settled'];present=physical(settled['equipment'],settled['inventoryWeight'],initial['inventoryWeight']);item_state(settled['item'],name,settled['equipment'])
        if receipt['fresh']is not True or present!=after or settled['item']['worn']is not True:raise ValueError('Wear setup lacked settled canonical/fresh stage')
        terminal_ack(receipt['ack'],name)
    swap=value['wear']
    if (swap['name']!='incoming'or swap['type']!='ISWearClothing'or swap['producer']!='native ISInventoryPaneContextMenu.onWearItems'
        or swap['duration']!=50 or swap['item']!=specs['incoming']['id']):raise ValueError('Wear swap genuine UI producer')
    lifecycle(swap,'incoming',[loaded,swapped],initial['inventoryWeight'],(loaded,swapped))
    if swap['startedAt']<=wear[-1]['startedAt']:raise ValueError('Wear swap preceded authority setup')
    commands=row['commands'];expected=[('front','ISWringClothing'),('target','ISUnequipAction'),('target','ISWringClothing'),('tail','ISWringClothing')]
    if [(command['name'],command['type'])for command in commands]!=expected:raise ValueError('Wear exact native execution names/topology')
    refs=[command['actionRef']for command in commands];tokens=[command['operation']for command in commands]
    if (any(type(ref)is not str or not ref for ref in refs+[swap['actionRef']])or len(set(refs+[swap['actionRef']]))!=5
        or not all(_positive(token)for token in tokens)or tokens[1]!=tokens[2]or len({tokens[0],tokens[1],tokens[3]})!=3
        or value['queuedOrder']!=[swap['actionRef']]+refs or value['initialOrder']!=refs or value['finalOrder']!=refs or value['front']!=refs[0]
        or type(value['frontNative'])is not str or not value['frontNative']):raise ValueError('Wear native queue ownership/order')
    group=value['target'];expected_group=dict(token=tokens[1],unequip=refs[1],body=refs[2],bounds=dict(first=2,last=3),item=specs['target']['id'],unallocated=True)
    if editing:expected_group['descriptor']=dict(unequipSource='native.ISUnequipAction',bodySource='native.ISWringClothing',item=specs['target']['id'],actual='root',worn=True,slot='base:scarf',setsWorn=False,capacity='external',bodyCapacity='external',equipmentWriter=True,cancelWaiting=False,moveRequiresProjection=True,projection='allowed',canonical=True)
    if editing and (any(group['descriptor'][key]is not True for key in ('worn','equipmentWriter','moveRequiresProjection','canonical'))or any(group['descriptor'][key]is not False for key in ('setsWorn','cancelWaiting'))):raise ValueError('Wear typed retained descriptor')
    if group!=expected_group or group['unallocated']is not True:raise ValueError('Wear retained exact whole operation descriptor')
    moves=[dict(selected=refs[1],after=True,accepted=True,order=[refs[0],refs[3],refs[1],refs[2]],bounds=dict(first=3,last=4)),dict(selected=refs[2],after=False,accepted=True,order=refs,bounds=dict(first=2,last=3))]if editing else[]
    if value['moves']!=moves or any(move['accepted']is not True for move in value['moves']):raise ValueError('Wear retained child-selected full-group moves')
    for attempt in value['attempts']:
        if (attempt['fresh']is not False or attempt['accepted']is not False or attempt['attempted']is not editing or type(attempt['physical'])is not bool
            or attempt['beforeOrder']!=refs or attempt['afterOrder']!=refs or attempt['before']!=attempt['after']):raise ValueError('Wear unfresh refusal mutated queue/physical state')
        present=snapshot(attempt['before'],initial['inventoryWeight'],[loaded,swapped])
        if attempt['physical']is not(present==swapped):raise ValueError('Wear refusal physical readiness')
    starts=[]
    for command in commands:
        name=command['name'];spec=specs[name]
        if command['producer']!=PRODUCER or command['item']!=spec['id']or command.get('cancelled',False)is not False:raise ValueError('Wear wring native producer identity')
        if command['type']=='ISWringClothing':
            wet=command['constructorWetness']
            if not _number(wet)or not 10<wet<=100 or command['duration']!=math.ceil(wet*5):raise ValueError('Wear native wring duration/wetness')
            starts.append(command['startedAt'])
        elif command['duration']!=50 or command['cartsGuard']is not True:raise ValueError('Wear retained native/Carts Unequip')
        admission=command['admission'];item_state(admission['item'],name,admission['equipment'])
        physical(admission['equipment'],admission['inventoryWeight'],initial['inventoryWeight'])
        allowed=[loaded,swapped]if name=='front'else[swapped,final]if command['type']=='ISUnequipAction'else[final]
        if command['type']=='ISUnequipAction'and admission['item']['worn']is not True:raise ValueError('Wear retained source slot missing on admission')
        events=lifecycle(command,name,allowed,initial['inventoryWeight'])
        if not host and command['type']=='ISWringClothing':
            begin=next(event for event in events if(event['phase'],event['boundary'])==('complete','begin'))['state']['item']['wetness']
            finish=next(event for event in events if(event['phase'],event['boundary'])==('complete','finish'))['state']['item']['wetness']
            if abs(finish-min(begin,spec['cap']))>.01:raise ValueError('Wear SP exact native min-wetness completion')
            if any(row[side]['items'][name]['wetness']>finish+.01 for side in ('client','server')):raise ValueError('Wear SP final wetness increased after paid completion')
        for event in events:
            if command['type']=='ISWringClothing'and event['state']['item']['worn']:raise ValueError('Wear wring preceded real native Unequip')
            if not host and command['type']=='ISWringClothing'and(event['phase'],event['boundary'])==('complete','finish')and not 0<=event['state']['item']['wetness']<=spec['cap']+.01:raise ValueError('Wear SP native wring completion cap')
            if not host and command['type']=='ISUnequipAction'and(event['phase'],event['boundary'])==('complete','finish')and event['state']['item']['worn']:raise ValueError('Wear native Unequip complete retained scarf')
    if starts!=sorted(starts)or starts[0]<=swap['startedAt']:raise ValueError('Wear independent tail/native execution order')
    terminal_ack(value['ack'],'incoming')
    if (row['status']!='passed'or row['queueIdle']is not True or not _number(row['settleMilliseconds'])or row['settleMilliseconds']<1000
        or row['edit']!=dict(cancelled=False,reordered=editing,repeatDenied=False,untouched=True)
        or any(row.get(key,False)is not False for key in ('prepared','wornPrepared'))):raise ValueError('Wear idle/exact edits/no invented cancellation')


def _capacity_profile(row, selection):
    enabled=selection.get('options',{}).get('profile_capacity',False) is True and row['ids']['case']=='worn-bag'
    if not enabled:
        if (row.get('capacityProfile',False)is not False or row['ids'].get('capacityProfile',False)is not False
            or any(type(row.get(key))is dict and row[key].get('capacityPayload',False)is not False for key in ('input','client','server','authorityBaseline'))):
            raise ValueError('unexpected optional capacity profile')
        return
    ids=row['ids'];spec=ids['capacityProfile'];value=row['capacityProfile'];measurement=value['measurement'];bag=ids['source']['bag']
    if type(spec)is not dict or spec['instances']!=128 or type(spec['instances'])is not int or spec['bag']!=bag or type(spec['items'])is not list or len(spec['items'])!=128:
        raise ValueError('capacity payload manifest size/bag')
    items=spec['items'];keys={'id','type','class','count','uses','actualWeight','capacityWeight','ownerBag'}
    if (items!=sorted(items,key=lambda item:item['id'])or len({item['id']for item in items})!=128
        or {item['id']for item in items}&({bag}|{item['id']for item in ids['items'].values()})):
        raise ValueError('capacity payload IDs collide/alias')
    for item in items:
        if (set(item)!=keys or type(item['id'])is not int or not -2147483648<=item['id']<=2147483647 or item['type']!='Base.Nails'or item['class']!='ComboItem'
            or type(item['count'])is not int or item['count']!=5 or type(item['uses'])is not int or item['uses']<=0 or item['ownerBag']!=bag
            or not _number(item['actualWeight'])or abs(item['actualWeight']-.05)>.000001 or item['capacityWeight']!=item['actualWeight']):
            raise ValueError('capacity payload native physical instance/count/uses/weight')
    total=sum(item['actualWeight']for item in items);uses=sum(item['uses']for item in items)
    def payload(snapshot):
        actual=snapshot['capacityPayload']
        if (actual['bag']!=bag or actual['bagType']!='Base.Bag_Military'or actual['bagRoot']is not True or actual['bagWorn']is not True
            or actual['items']!=items or any(type(actual[key])is not int or actual[key]!=expected for key,expected in (('instances',128),('sourceInstances',128),('actorInstances',128),('rootInstances',0),('uses',uses)))
            or not _number(actual['totalWeight'])or abs(actual['totalWeight']-total)>.000001
            or any(not _number(actual[key])or actual[key]<0 for key in ('bagCapacity','effectiveCapacity','sourceWeight','rootWeight'))
            or actual['sourceWeight']+.000001<total or actual['sourceWeight']>actual['effectiveCapacity']+.000001):
            raise ValueError('capacity payload exact canonical source/amount/native capacity')
        return actual
    for snapshot in (row['input'],row['authorityBaseline'],row['client'],row['server'],row['prepared']['before'],row['prepared']['after'],measurement['before'],measurement['after']):payload(snapshot)
    if (measurement['case']!='worn-bag'or measurement['point']!='before-wring-producers'or measurement['clock']!='getTimestampMs'
        or measurement['units']!='coarse wall-clock milliseconds'or measurement['instances']!=128 or measurement['callsPerPath']!=32 or measurement['warmupPerPath']!=2
        or any(type(measurement[key])is not int for key in ('instances','callsPerPath','warmupPerPath'))
        or any(measurement[key]is not True for key in ('queueIdle','helperSource','helperUnchanged','callbacksUntouched'))
        or measurement['before']!=row['input']or measurement['before']!=measurement['after']):
        raise ValueError('capacity profile real idle context/source/no-mutation')
    native=measurement['nativeWeight']
    if not _number(native)or native<0 or native!=measurement['before']['capacityPayload']['rootWeight']:raise ValueError('capacity profile native root weight')
    if measurement['scope']!='actual Java-backed own-player root and carried bag; synchronous idle tick including Lua loop/validation overhead; no FPS or other inventory-size extrapolation':raise ValueError('capacity profile measurement scope')
    samples=measurement['samples']
    if type(samples)is not list or [sample['path']for sample in samples]!=['legacy','qualified','qualified','legacy']:raise ValueError('capacity alternating grouped samples missing')
    for sample in samples:
        if (type(sample['calls'])is not int or sample['calls']!=16 or type(sample['elapsedMilliseconds'])is not int or sample['elapsedMilliseconds']<0
            or any(not _number(sample[key])or sample[key]<0 for key in ('minUpper','maxUpper','minLower','maxLower'))
            or not sample['minUpper']<=sample['maxUpper']or not sample['minLower']<=sample['maxLower']
            or sample['minUpper']<native or sample['maxLower']>native
            or sample['path']=='qualified'and(sample['minLower']!=0 or sample['maxLower']!=0)):
            raise ValueError('capacity profile calls/coarse clock/conservative bound')
    if (any(type(measurement[key])is not int or measurement[key]<0 for key in ('startedAt','finishedAt','totalMilliseconds'))
        or measurement['totalMilliseconds']!=measurement['finishedAt']-measurement['startedAt']
        or measurement['totalMilliseconds']<sum(sample['elapsedMilliseconds']for sample in samples)
        or measurement['startedAt']<row['wearSetup']['startedAt']or measurement['finishedAt']>row['commands'][0]['startedAt']):
        raise ValueError('capacity profile real ready-baseline/before-producers timing')
    expected=dict(case='worn-bag',bag=bag,ids=[item['id']for item in items],actorInstances=0,bagReachable=False,bagWorn=False,bagWorld=False,
                  scope='removed from actor inventory; no object-destruction claim')
    for cleanup in (value['cleanupClient'],value['cleanupServer']):
        if cleanup!=expected or type(cleanup['actorInstances'])is not int or any(cleanup[key]is not False for key in ('bagReachable','bagWorn','bagWorld')):
            raise ValueError('capacity payload explicit cleanup identity/actor absence')


def check_case(row, selection, prepared, verified, wear_baseline=None):
    issues = []
    try:
        _capacity_profile(row,selection)
        if row['ids']['case']=='wear-swap':
            _wear_swap(row,selection,prepared,verified,wear_baseline);return issues
        ids = row['ids']; case = ids['case']; editing = selection['mode'] == 'toolkit' and case == 'root'; carried = case == 'worn-bag'; worn_prepared = case == 'worn-prepared'; group_editing = (carried or worn_prepared) and selection['mode'] == 'toolkit'
        native_wear = worn_prepared or case=='worn-bag'and selection.get('options',{}).get('profile_capacity',False)is True or selection['kind'] == 'mp' and case in ('worn', 'worn-bag')
        if ids != prepared or case not in CASES or ids['mode'] != selection['mode'] or row['server'] != verified:
            raise ValueError('authority or selected identity')
        if ids.get('wornPrepared', False) is not worn_prepared: raise ValueError('worn group fixture declaration')
        if ids.get('preparedGroups', False) is not carried:
            raise ValueError('carried group fixture declaration')
        if ids.get('nativeWearSetup', False) is not native_wear:
            raise ValueError('native owner wear setup declaration')
        if native_wear and not worn_prepared:
            wear = row['wearSetup']
            item = ids['items']['target']['id'] if case == 'worn' else ids['source']['bag']
            if (wear['type'] != 'ISWearClothing' or wear['producer'] != 'native ISWearClothing constructor'
                or wear['item'] != item or wear['duration'] != 50 or wear['started'] is not True
                or wear['progress'] is not True or not _number(wear['startedAt'])):
                raise ValueError('real native owner wear setup')
            if wear_baseline is not None and row['authorityBaseline'] != wear_baseline:
                raise ValueError('native wear authority baseline receipt')
        elif not worn_prepared and (row.get('wearSetup', False) is not False or row.get('authorityBaseline', False) is not False):
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
            gloves = worn_prepared and name == 'cancelled'; scarf = worn_prepared and name == 'target'
            if (type(spec['id']) is not int or spec['type'] != ('Base.Scarf_White' if scarf else 'Base.Gloves_LeatherGloves' if gloves else 'Base.Shoes_FlipFlop' if shoes else 'Base.Socks_Ankle')
                or spec['cap'] != 10 or spec['nativeShoe'] is not False or spec['bodyLocationClass'] != 'ItemBodyLocation'
                or spec['bodyLocation'] != ('base:scarf' if scarf else 'base:hands' if gloves else 'base:shoes' if shoes else 'base:socks') or spec['initial'] != 100
                or not _number(spec['weight']) or spec['weight'] <= 0):
                raise ValueError('native clothing type/cap/initial state')
            if worn_prepared and name in ('target','cancelled') and abs(spec['weight']-(.2 if scarf else .1)) > .000001:
                raise ValueError('source-audited natural clothing weight')
        phases = [(phase, row[phase]) for phase in (('input', 'authorityBaseline', 'client', 'server') if native_wear else ('input', 'client', 'server'))]
        if worn_prepared: phases += [('pending', row['wornPrepared']['before']), ('pending', row['wornPrepared']['after'])]
        if carried: phases += [('pending', row['prepared']['before']), ('pending', row['prepared']['after'])]
        for phase, snapshot in phases:
            final = phase in ('client', 'server')
            if snapshot['case'] != case or snapshot['source'] != source or set(snapshot['items']) != set(NAMES):
                raise ValueError('snapshot identity')
            for name, item in snapshot['items'].items():
                spec = specs[name]
                expected_native = {key: spec[key] for key in ('bodyLocation', 'bodyLocationClass', 'nativeShoe', 'cap')}
                expected_counts = _counts(case, name, final)
                if (final and case == 'worn-bag' and name in ('target', 'cancelled') and selection['mode'] == 'native'
                        and selection.get('options', {}).get('wring_restoration_provider') == 'native-returns'):
                    expected_counts = dict(actor=1, root=1, source=0)
                if (item['id'] != spec['id'] or item['type'] != spec['type'] or item['counts'] != expected_counts
                    or item['native'] != expected_native
                    or item['worn'] is not ((not final and case == 'worn' and name == 'target') or (worn_prepared and name in ('target','cancelled') and (not final or name == 'cancelled' and group_editing)))
                    or not _number(item['weight']) or not 0 < item['weight'] <= spec['weight'] + .01
                    or not _number(item['wetness'])):
                    raise ValueError('clothing identity/source/weight/worn state')
                if carried:
                    if (not _number(spec['wetWeight']) or not _number(spec['capacityWeight']) or spec['capacityWeight'] <= 0
                        or not _number(item['wetWeight']) or not spec['weight'] <= item['wetWeight'] <= spec['wetWeight'] + .01
                        or type(item['capacityWeight']) not in (int, float) or item['capacityWeight'] != spec['capacityWeight']):
                        raise ValueError('current wet/native capacity weight bounds')
                untouched = name == 'cancelled' and not((carried or worn_prepared) and selection['mode'] == 'native')
                if final and worn_prepared and group_editing and name == 'cancelled':
                    # Native worn wetness remains live even when no queued child is admitted.
                    if not 0 <= item['wetness'] <= spec['initial']:
                        raise ValueError('cancelled worn garment exceeded native wetness clamp')
                else:
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
        elif worn_prepared: expected += [('cancelled','ISUnequipAction'), ('cancelled','ISWringClothing')]; prelude = [('target','ISUnequipAction')]
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
        _restoration(row, selection)
        if starts != sorted(starts):
            raise ValueError('native completion order')
        if worn_prepared: _worn_prepared(row, selection, wear_baseline)
        elif row.get('wornPrepared', False) is not False: raise ValueError('unexpected worn group evidence')
        if native_wear and not worn_prepared and starts[0] <= row['wearSetup']['startedAt']:
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
        wear_cases = [case for case in cases if case in ('worn-prepared','wear-swap') or case=='worn-bag'and selection.get('options',{}).get('profile_capacity',False)is True or selection['kind'] == 'mp' and case in ('worn', 'worn-bag')]
        if [baseline.get('case') for baseline in wear_baselines] != wear_cases:
            raise ValueError('missing, duplicate or out-of-order native wear baseline')
        profile_cases=['worn-bag']if selection.get('options',{}).get('profile_capacity',False)is True else[]
        if any(case not in cases for case in profile_cases):raise ValueError('capacity profiling requires selected worn-bag')
        measurements=_raw(text,'CAPACITY_PROFILE');cleanups=_raw(authority,'PROFILE_CLEANED')
        if [value.get('case')for value in measurements]!=profile_cases or [value.get('case')for value in cleanups]!=profile_cases:
            raise ValueError('missing/duplicate/unselected capacity profile or cleanup authority')
        for case in profile_cases:
            row=next(value for value in rows if value['id']==case)
            if row['capacityProfile']['measurement']!=measurements[0]or row['capacityProfile']['cleanupServer']!=cleanups[0]:
                raise ValueError('capacity profile/cleanup differs from independent raw receipts')
            relevant=[(match.group(1),json.loads(match.group(2)).get('case'))for match in re.finditer(re.escape(PREFIX)+r'(VERIFIED|PROFILE_CLEANED) ([^\n]+)',authority)if json.loads(match.group(2)).get('case')==case]
            if relevant!=[('VERIFIED',case),('PROFILE_CLEANED',case)]:raise ValueError('capacity cleanup preceded exact native Verify')
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
        restoration_raw = _raw(text, 'RESTORATION')
        restoration_rows = [sample for row in rows for sample in row.get('restoration', {}).get('samples', [])]
        if restoration_raw != restoration_rows:
            raise ValueError('restoration event and raw loan receipts differ')
        for index, case in enumerate(cases):
            row = rows[index]
            if (row.get('actor') != 'client1' or row.get('kind') != selection['kind'] or row.get('mode') != selection['mode']
                or placements[index] != dict(case=case, proof=row.get('clientPlacement'))):
                raise ValueError('actor or placement receipt')
            baseline = next((value for value in wear_baselines if value['case'] == case), None)
            errors = check_case(row, selection, prepared[index], verified[index], baseline); issues += errors
            outcomes.append(dict(actor='client1', case=case, status='failed' if errors else 'passed', reason='; '.join(errors),
                outcome=dict(effectsVerified=not errors, serverAuthorityVerified=not errors, tailCompleted=not errors,
                             pendingEditsVerified=not errors and selection['mode'] == 'toolkit' and case in ('root', 'worn-bag', 'worn-prepared', 'wear-swap'))))
        if not complete(selection, 'client1', text): issues.append('Missing completion marker')
    except (OSError, ValueError, KeyError, TypeError) as error:
        issues.append(str(error))
    return dict(issues=issues, outcomes=outcomes, evidence={'adapterInstalled': setups[0].get('adapterInstalled') if len(setups) == 1 else None, 'limits': [
        'Programmatic native inventory UI callbacks and genuine carried producer groups; no physical input, active edits, missing/full storage recovery or future drying/capacity credit.',
        'Optional capacity samples are coarse synchronous idle wall-clock measurements including Lua loop/validation overhead; no timing threshold, FPS qualification or inventory-size extrapolation.',
        'Wetness caps allow bounded natural drying after native completion; rain disabled only in the disposable fixture world.']})
