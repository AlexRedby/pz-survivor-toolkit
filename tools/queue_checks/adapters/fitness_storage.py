"""Exact-resource gates for the mixed carried/worn Fitness fixture."""
import copy
from .fitness import _matches, _same, _number, _inventory

CASES = ('multi-storage', 'multi-storage-closed')


def _snapshot(value, before, spec, world=(), outside=False, hands=False):
    if not isinstance(value, dict):
        return False
    bags = {row['id']: row for row in spec['bags']}
    world = set(world)
    expected = copy.deepcopy(before['items'])
    for row in expected:
        if row['id'] in bags:
            row['container'] = 'world' if row['id'] in world else 'root'
        elif row['id'] == spec['prop']['id']:
            row['container'] = 'root' if outside else spec['prop']['bag']
    if not _same(value.get('items'), expected) or not isinstance(value.get('bags'), list) or len(value['bags']) != 3:
        return False
    for actual, ref in zip(value['bags'], spec['bags']):
        contents = [row for row in expected if row['container'] == ref['id']]
        if not _matches(actual, dict(id=ref['id'], kind=ref['kind'], favorite=True, occurrences=1,
                                    endpoint='world' if ref['id'] in world else 'root', contents=contents)):
            return False
        if ref['id'] in world:
            if not _matches(actual.get('world'), dict(**spec['origin'], linked=True)):
                return False
        elif actual.get('world') is not False:
            return False
    if not _matches(value.get('prop'), dict(id=spec['prop']['id'], kind='Base.DumbBell', favorite=True,
                       endpoint='root' if outside else spec['prop']['bag'], occurrences=1)):
        return False
    if hands:
        worn = [row for row in before['worn'] if row['id'] not in bags] if outside else before['worn']
        if not _matches(value, dict(primary=spec['prop']['id'] if outside else before['primary'],
                                    secondary=False if outside else before['secondary'], worn=worn)):
            return False
    return True


def verify_storage(case, command, prep, receipt, mp):
    issues = []
    def fail(message):issues.append('Fitness multi-storage ' + message + ': ' + case)
    spec, before = prep.get('multiStorage', {}), prep.get('multiBefore', {})
    ids = prep['items']
    bags, markers = spec.get('bags'), spec.get('markers')
    if (not isinstance(bags, list) or len(bags) != 3 or not isinstance(markers, list) or len(markers) != 3
            or not isinstance(before, dict) or not isinstance(before.get('items'), list)
            or not isinstance(spec.get('origin'), dict) or set(spec['origin']) != {'x','y','z'}
            or not all(type(v) is int for v in spec['origin'].values())):
        return ['Fitness multi-storage preparation schema differs: ' + case]
    kinds = dict(bag='Base.Bag_Schoolbag', hammer='Base.Bag_Satchel', fanny='Base.Bag_FannyPackFront')
    if ([row.get('name') for row in bags] != list(kinds)
            or any(not _matches(row, dict(kind=kinds[name], primary=name=='hammer', secondary=False, favorite=True))
                   or type(row.get('id')) is not int for row,name in zip(bags,kinds))
            or bags[0]['id'] != ids['bag'] or bags[1]['id'] != ids['hammer']
            or bags[0].get('slot') != 'base:back' or bags[2].get('slot') != 'base:fannypackfront' or bags[1].get('slot') is not False
            or not _matches(spec.get('prop'),dict(id=ids['dumbbell'],kind='Base.DumbBell',bag=ids['hammer'],favorite=True))
            or any(not _matches(row,dict(kind='Base.Pencil',bag=bag['id'])) or type(row.get('id')) is not int for row,bag in zip(markers,bags))):
        return ['Fitness multi-storage exact bag/prop/marker declaration differs: ' + case]
    resource_ids = [row['id'] for row in bags+markers] + [ids['dumbbell']]
    if len(set(resource_ids)) != 7 or len(set([*ids.values(), bags[2]['id'], *(row['id'] for row in markers)])) != 10:
        return ['Fitness multi-storage resource IDs overlap: ' + case]
    canonical = dict(items=[{key:row.get(key) for key in ('id','kind','container')} for row in before['items']],
                     primary=before.get('primary'),secondary=before.get('secondary'),worn=before.get('worn'))
    if (not _inventory(canonical) or not _same(canonical, prep['inventory'])
            or not _matches(before,dict(primary=ids['hammer'],secondary=ids['screwdriver']))
            or any(dict(id=row['id'],location=row['slot']) not in before.get('worn',[]) for row in (bags[0],bags[2]))
            or any(row['id']==ids['hammer'] for row in before.get('worn',[]))
            or any(not any(_matches(item,dict(id=ref['id'],kind=ref['kind'],container=ref['bag'],favorite=False)) for item in before['items']) for ref in markers)
            or not _snapshot(before,before,spec,hands=True)):
        fail('initial hands/worn/favorite contents differ')
    records = receipt.get('records', [])
    if len(records) != 1 or not _snapshot(records[0].get('multiStorage'),before,spec,world=resource_ids[:3],outside=True,hands=True):
        fail('workout lacks three exact world bags and held borrowed prop')
    else:
        expected = copy.deepcopy(prep['inventory'])
        expected['items'] = [dict(row,container='root') if row['id']==ids['dumbbell'] else row for row in expected['items']
                             if row['id'] not in resource_ids[:3] and (row['container'] not in resource_ids[:3] or row['id']==ids['dumbbell'])]
        expected.update(primary=ids['dumbbell'],secondary=False,worn=[row for row in expected['worn'] if row['id'] not in resource_ids[:3]])
        if not _same(records[0].get('startEquipment'),expected):fail('authority workout root inventory differs')
    boundary = command.get('multiBeforeTail', {})
    if (not _matches(boundary,dict(callback='ISBaseTimedAction.begin',inventory=prep['inventory']))
            or not _number(boundary.get('nativeClock')) or type(boundary.get('frameNo')) is not int or not _same(boundary.get('snapshot'),before)
            or not _same(command.get('multiFinal'),before) or not _same(receipt.get('multiStorage'),before)):
        fail('exact restoration before reader/final receipt differs')
    if mp and (not _matches(receipt.get('tailStart'),dict(id=ids['tail'],kind='Base.BookFirstAid1',
                      callback='ISReadABook.serverStart',workouts=1,observerActive=False,inventory=prep['inventory']))
               or not _same(receipt.get('tailStart',{}).get('multiStorage'),before)):
        fail('server reader precedes exact restoration')
    starts, placements = command.get('multiStarts'), receipt.get('multiPlacements')
    if not isinstance(starts,list) or not isinstance(placements,list):
        return issues + ['Fitness multi-storage native callback evidence missing: ' + case]
    expected_bags = {row['id']:row['kind'] for row in bags}
    def members(row):
        if row.get('phase')=='placement':
            return [{key:row.get(key) for key in ('id','kind','source','destination')}]
        value=row.get('members')
        return value if isinstance(value,list) else []
    for phase in ('placement','recovery'):
        covered=[ref for row in starts if row.get('phase')==phase for ref in members(row)]
        if len(covered)!=3 or {row.get('id'):row.get('kind') for row in covered}!=expected_bags:
            fail('native '+phase+' member identities/count differ')
    returned=[ref for row in starts if row.get('phase')=='return' for ref in members(row)]
    if len(returned)!=1 or not _matches(returned[0],dict(id=ids['dumbbell'],kind='Base.DumbBell',source='root',destination=ids['hammer'])):
        fail('exact prop return count/source/destination differs')
    if any(row.get('phase') not in ('placement','recovery','return') for row in starts):fail('unknown native callback phase')
    last_frame = -1
    stop_frame = command.get('multiStopFrame')
    if type(stop_frame) is not int:fail('actual local stop frame missing')
    for row in starts:
        phase=row.get('phase'); snapshot=row.get('snapshot',{})
        world={bag.get('id') for bag in snapshot.get('bags',[]) if bag.get('endpoint')=='world'}
        if (not _matches(row,dict(callback='ISBaseTimedAction.begin')) or not _number(row.get('nativeClock'))
                or row.get('clockError') is not None or type(row.get('frameNo')) is not int
                or row['frameNo']>boundary.get('frameNo',-1)
                or not _snapshot(snapshot,before,spec,world=world,outside=True)):
            fail('native start has missing or inconsistent conserved snapshot')
        if type(row.get('frameNo')) is not int or row['frameNo'] < last_frame:fail('callback start order differs')
        else:last_frame=row['frameNo']
        if phase in ('recovery','return'):
            captures=row.get('memberCaptures')
            if (not members(row) or row.get('membersError') is not None or not isinstance(captures,list) or not captures
                    or type(stop_frame) is not int or type(row.get('frameNo')) is not int or row['frameNo']<stop_frame
                    or not _matches(members(row)[0],{key:row.get(key) for key in ('id','kind','source','destination')})):
                fail('native batch membership lacks an exact observed merge boundary')
                continue
            covered=[];capture_frame=row['frameNo']
            declared={ref.get('id'):ref for ref in members(row)}
            for index,capture in enumerate(captures):
                snapshot=capture.get('snapshot',{});world={bag.get('id') for bag in snapshot.get('bags',[]) if bag.get('endpoint')=='world'}
                captured=capture.get('members')
                if (not isinstance(captured,list) or not captured or any(type(identity) is not int or identity not in declared for identity in captured)
                        or capture.get('callback') != ('ISBaseTimedAction.begin' if index==0 else 'ISInventoryTransferAction.checkQueueList')
                        or capture.get('clockError') is not None or not _number(capture.get('nativeClock'))
                        or type(capture.get('frameNo')) is not int
                        or not capture_frame<=capture['frameNo']<=boundary.get('frameNo',-1)
                        or not _snapshot(snapshot,before,spec,world=world,outside=True)):
                    fail('native member capture is missing or not source-bound')
                    continue
                capture_frame=capture['frameNo'];covered.extend(captured)
                for identity in captured:
                    ref=declared[identity]
                    if phase=='recovery' and (ref.get('source')!='world' or ref.get('destination')!='root' or identity not in world):
                        fail('recovery member does not start from its exact world source')
                    if phase=='return' and world:fail('prop returned before all carriers recovered')
            if len(covered)!=len(declared) or len(set(covered))!=len(covered) or set(covered)!=set(declared):
                fail('native member captures overlap or omit a transferred resource')
        elif phase=='placement' and (row.get('source')!='root' or row.get('destination')!='world' or row.get('id') in world):
            fail('placement does not start from exact carried bag')
    if len(placements)!=3 or {row.get('id'):row.get('kind') for row in placements}!=expected_bags:
        fail('original placement completion identities/count differ')
    for row in placements:
        snapshot=row.get('snapshot',{});world={bag.get('id') for bag in snapshot.get('bags',[]) if bag.get('endpoint')=='world'}
        begins=[begin for begin in starts if begin.get('phase')=='placement' and begin.get('id')==row.get('id')]
        recoveries=[begin for begin in starts if begin.get('phase')=='recovery' and any(ref.get('id')==row.get('id') for ref in members(begin))]
        if len(begins)!=1 or len(recoveries)!=1:fail('placement completion lacks native begin/recovery')
        if (not _matches(row,dict(phase='placement',callback='ISDropWorldItemAction.complete',succeeded=True))
                or row.get('id') not in world or not _number(row.get('nativeClock')) or row.get('clockError') is not None
                or not _snapshot(snapshot,before,spec,world=world,outside=True)
                or not mp and (type(row.get('frameNo')) is not int or not begins or not recoveries
                    or not begins[0].get('frameNo',float('inf'))<=row['frameNo']<=recoveries[0].get('frameNo',-1)
                    or not records or row['frameNo']>records[0].get('startFrameNo',-1))
                or mp and (not _number(row.get('serverTimeMS')) or not records
                    or not _number(records[0].get('serverTiming',{}).get('startMS'))
                    or row['serverTimeMS']>records[0]['serverTiming']['startMS'])):
            fail('placement is not an earned original world effect before workout')
    if mp:
        timing=records[0].get('serverTiming',{}) if len(records)==1 else {}
        if (timing.get('error') is not None or timing.get('source')!='GameTime.getServerTimeMills:System.nanoTime'
                or not all(_number(timing.get(key)) for key in ('startMS','stopMS','elapsedMS','minutesPerDay','worldMS','realMS','minScale','maxScale'))
                or timing.get('stopMS',0)<=timing.get('startMS',0)
                or timing.get('elapsedMS')!=timing.get('stopMS',0)-timing.get('startMS',0)
                or type(timing.get('samples')) is not int or timing['samples']<2):
            fail('independent server monotonic timing missing')
    return issues
