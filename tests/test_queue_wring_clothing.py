import copy
from functools import lru_cache
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from queue_checks import adapters
from queue_checks.adapters import wring_clothing as a
from tests.test_queue_tv_controls_adapter import placement_proof as tile_placement_proof

PROJECT = Path(__file__).resolve().parents[1]


@lru_cache(maxsize=2)
def carried_plan(mode):
    # The live fixture and source composition load this same pure Lua recipe.
    from lupa.lua51 import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    scenario = lua.execute((PROJECT / 'tests/native_queue/wring-clothing/shared/QueueWringScenario.lua').read_text())
    plan = scenario.plan(mode)
    return tuple((plan[index]['name'], plan[index]['type']) for index in range(1, len(plan) + 1))


def placement_proof(target, mode='local'):
    proof = tile_placement_proof(target, mode)
    proof.update(centered=True, centers=1 if mode == 'local' else 0)
    proof['actual'].update(x=target['x'] + .5, y=target['y'] + .5)
    return proof


def worn_alias_fixture():
    from lupa.lua51 import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().fixture = str(PROJECT / 'tests/native_queue/wring-clothing/shared/QueueWringClothing.lua')
    lua.execute(r'''
package.loaded.QueueEnergyPlacement={atCentered=function()return true end}
function instanceof(value,kind)return value.class==kind end
function getClassSimpleName(value)return value.class end
F=dofile(fixture)
local function location(name)return setmetatable({class='ItemBodyLocation'},{__tostring=function()return 'base:'..name end})end
local shoes,socks=location('shoes'),location('socks')
ItemBodyLocation=setmetatable({SHOES=shoes,SOCKS=socks},{__index=function(_,key)return key end})
root={};local values={};local slot
local function item(id,kind,body)
 return{class='Clothing',getID=function()return id end,getFullType=function()return kind end,
 getBodyLocation=function()return body end,getContainer=function()return root end,getWetness=function()return 99 end,
 getActualWeight=function()return .1 end,hasTag=function()return false end,getCategory=function()return 'Clothing'end,
 IsClothing=function()return true end,setJobType=function()end,setJobDelta=function()end,getName=function()return kind end}
end
function root:getItems()return{size=function()return #values end,get=function(_,i)return values[i+1]end}end
function root:getItemById(id)for _,value in ipairs(values)do if value:getID()==id then return value end end end
player={getInventory=function()return root end,getWornItem=function(_,body)return body==shoes and slot or nil end,
 setWornItem=function(_,body,value)assert(body==shoes);slot=value end,
 getWornItems=function()return{contains=function(_,value)return value==slot end,
 getItemById=function(_,id)return slot and slot:getID()==id and slot or nil end}end,
 reportEvent=function()end,playSound=function()return 0 end,
 getHumanVisual=function()return{getHairModel=function()return{contains=function()return false end}end}end}
ids={case='worn',nativeWearSetup=true,origin={},source={kind='worn',bag=false,world=false},items={}}
for i,name in ipairs(F.names)do
 local shoe=name=='target'or name=='tail';local body=shoe and shoes or socks
 local kind=shoe and 'Base.Shoes_FlipFlop'or 'Base.Socks_Ankle'
 local value=item(i,kind,body);values[i]=value
 local spec=F.nativeWetnessContract(value);spec.id=i;spec.type=kind;ids.items[name]=spec
end
canonical=values[2];proxy=item(2,'Base.Shoes_FlipFlop',shoes);slot=proxy
assert(F.resolve(player,ids)==nil,'same-ID worn alias was accepted as canonical')
state=assert(F.resolve(player,ids,true),'declared provisional native wear input could not resolve')
assert(F.wearBaseline(state)==nil,'same-ID worn alias became authority baseline')
local diagnostic=F.preparedDiagnostic(player,ids)
assert(diagnostic.items.target.present and diagnostic.items.target.exactOwner and diagnostic.items.target.wetness==99)
assert(diagnostic.items.target.wornId==2 and diagnostic.items.target.slotId==2 and not diagnostic.items.target.wornSame)
assert(not diagnostic.items.target.canonicalWorn and not diagnostic.items.target.slotSame,'prepared diagnostic hid worn alias')
''')
    return lua


def evidence(kind='mp', mode='toolkit', case='root'):
    if case == 'wear-swap': return wear_swap_evidence(kind,mode)
    if case == 'worn-prepared': return worn_prepared_evidence(kind, mode)
    origin = dict(x=11, y=20, z=0)
    source = dict(kind=case, bag=20 if case == 'worn-bag' else False,
                  world=dict(x=11, y=19, z=0, index=1) if case == 'world' else False)
    specs = {}
    for index, name in enumerate(a.NAMES):
        shoes = name == 'tail' or name == 'target' and case in ('worn', 'world')
        specs[name] = dict(id=10 + index, type='Base.Shoes_FlipFlop' if shoes else 'Base.Socks_Ankle',
                           cap=10, nativeShoe=False, bodyLocationClass='ItemBodyLocation',
                           bodyLocation='base:shoes' if shoes else 'base:socks', initial=100, weight=.1)
    ids = dict(case=case, mode=mode, restoration=False, source=source, origin=origin, items=specs,
               placementProof=placement_proof(origin, 'replica' if kind == 'mp' else 'local'))
    carried = case == 'worn-bag'
    if carried:
        ids['preparedGroups'] = True
        for spec in specs.values(): spec.update(wetWeight=.125, capacityWeight=.1)
    native_wear = kind == 'mp' and case in ('worn', 'worn-bag')
    if native_wear: ids['nativeWearSetup'] = True
    def snapshot(final):
        return dict(case=case, source=copy.deepcopy(source), items={
            name: dict(id=spec['id'], type=spec['type'], wetness=99 if not final or name == 'cancelled' and not(carried and mode == 'native') else spec['cap'],
                       native={key: spec[key] for key in ('bodyLocation', 'bodyLocationClass', 'nativeShoe', 'cap')},
                       weight=.1, worn=not final and case == 'worn' and name == 'target', counts=a._counts(case, name, final))
            for name, spec in specs.items()})
    editing = mode == 'toolkit' and case == 'root'
    if carried:
        plan = carried_plan(mode)
    else:
        plan = [('front', 'ISWringClothing')]
        if editing: plan += [('cancelled', 'ISWringClothing')]
        if case == 'worn': plan += [('target', 'ISUnequipAction')]
        if case == 'world': plan += [('target', 'ISInventoryTransferAction')]
        plan += [('target', 'ISWringClothing')]
        if editing: plan += [('repeat', 'ISWringClothing')]
        plan += [('tail', 'ISWringClothing')]
    commands = []
    for index, (name, type_) in enumerate(plan):
        cancelled = editing and name in ('cancelled', 'repeat') or carried and mode == 'toolkit' and name == 'cancelled'
        command = dict(name=name, type=type_, producer=a.PRODUCER, item=specs['target' if name == 'repeat' else name]['id'],
                       duration=495 if type_ == 'ISWringClothing' else -1 if type_ == 'ISInventoryTransferAction' and kind == 'mp' else 50,
                       started=not cancelled, progress=not cancelled)
        if cancelled: command['cancelled'] = True
        else: command['startedAt'] = 100 + index
        if type_ == 'ISWringClothing': command.update(constructorWetness=99, callbacksUntouched=True)
        commands.append(command)
    final = snapshot(True)
    row = dict(ids=copy.deepcopy(ids), clientPlacement=placement_proof(origin), input=snapshot(False),
               client=copy.deepcopy(final), server=copy.deepcopy(final), status='passed', queueIdle=True,
               settleMilliseconds=1000, commands=commands,
               edit=dict(cancelled=editing or carried and mode == 'toolkit', reordered=editing or carried and mode == 'toolkit', repeatDenied=editing, untouched=True))
    if native_wear:
        row.update(authorityBaseline=snapshot(False), wearSetup=dict(type='ISWearClothing', producer='native ISWearClothing constructor',
            item=specs['target']['id'] if case == 'worn' else source['bag'], duration=50, started=True, progress=True, startedAt=10))
    if carried:
        for phase in ('input', 'client', 'server', 'authorityBaseline'):
            if phase in row:
                for value in row[phase]['items'].values(): value.update(wetWeight=.1 + value['wetness'] / 100 * .025, capacityWeight=.1)
        final = copy.deepcopy(row['server'])
        editing_group = mode == 'toolkit'; count = 3 if editing_group else 2
        for index, command in enumerate(commands):
            command.update(actionRef='native-action-' + str(index), operation=dict(front=1, cancelled=2, target=3, tail=4)[command['name']])
            if command['type'] == 'ISWringClothing' and not command.get('cancelled'):
                start = copy.deepcopy(row['input']['items'][command['name']]);start['counts'] = dict(actor=1, root=1, source=0)
                command['rootAtStart'] = start
            elif command['type'] == 'ISQueueActionsAction':
                command.update(duration=-1, started=False, progress=False, admitted=not command.get('cancelled', False),
                    preparation=dict(container=source['bag'], owned=True, callbacksUntouched=True))
                command.pop('startedAt', None)
                if not command.get('cancelled'):
                    command['resolver'] = [dict(boundary=boundary, phase=phase, succeeded=boundary == 'finish',
                        nativeRef='native-resolver-episode', nativeClass='LuaTimedActionNew', ownedContainer=True,
                        position={key: row['clientPlacement']['actual'][key] for key in ('x','y','z')}, unexpectedChildren=[], expansionClosed=True)
                        for phase in (('perform','complete') if kind == 'sp' else ('perform',)) for boundary in ('begin','finish')]
        refs = [command['actionRef'] for command in commands]
        cancel_indexes = list(range(1, count + 1)); target_indexes = list(range(count + 1, count * 2 + 1)); tail_index = len(commands) - 1
        def group(name, indexes):
            first, last = indexes[0], indexes[-1]
            result = dict(token=commands[first]['operation'], fetch=refs[last - 1], body=refs[last], item=specs[name]['id'], bounds=dict(first=first + 1, last=last + 1), unallocated=True)
            if editing_group:
                result['prep'] = refs[first]
                result['descriptor'] = dict(fetchSource='native.ISInventoryTransferAction', bodySource='native.ISWringClothing', item=specs[name]['id'],
                    actual='bag', requires='root', fetchSets='root', sourceBag=source['bag'], canonical=True, prepSource='toolkit.approach', prepOwned=True,
                    prepLease=dict(capacity='unchanged', owner=source['bag'], ownerRoot=True, effectsEmpty=True, fresh=True), bodyCapacity='external', fetchCapacity='external', projection='allowed')
            return result
        discarded = group('cancelled', cancel_indexes); kept = group('target', target_indexes)
        retained = [refs[0]] + [refs[index] for index in target_indexes] + [refs[tail_index]]
        moves = []
        if editing_group:
            discarded.update(selected=refs[cancel_indexes[-1]], accepted=True, afterOrder=retained)
            moves = [dict(selected=refs[target_indexes[-2]], after=True, accepted=True,
                          order=[refs[0], refs[tail_index]] + [refs[index] for index in target_indexes], bounds=dict(first=3, last=count + 2)),
                     dict(selected=refs[target_indexes[-1]], after=False, accepted=True, order=retained, bounds=dict(first=2, last=count + 1))]
        members = [dict(id=specs[name]['id'], type=specs[name]['type']) for name in (('target',) if editing_group else ('target', 'cancelled'))]
        members.sort(key=lambda item: item['id'])
        returns = [dict(actionRef='native-return', type='ISInventoryTransferAction', **{'from': 'root'}, toBag=source['bag'], duration=-1 if kind == 'mp' else 50,
            allowMissing=False, items=members, events=[dict(boundary='begin', phase='perform', nativeRef='native-return-episode'),
                                                     dict(boundary='finish', phase='perform', succeeded=True, nativeRef='native-return-episode')])]
        row['prepared'] = dict(sourceBag=source['bag'], front=refs[0], frontNative='native-front-episode', initialOrder=refs,
            cancelled=discarded, target=kept, moves=moves, finalOrder=retained if editing_group else refs, returns=returns,
            before=copy.deepcopy(row['input']), after=copy.deepcopy(row['input']))
    return row, dict(kind=kind, mode=mode), ids, final


def worn_prepared_evidence(kind, mode):
    row, selection, ids, _ = evidence(kind, mode, 'root')
    ids = copy.deepcopy(ids); ids.update(case='worn-prepared', wornPrepared=True, nativeWearSetup=True)
    ids['source']['kind'] = 'worn-prepared'
    specs=ids['items'];specs['target'].update(type='Base.Scarf_White',bodyLocation='base:scarf',weight=.2);specs['cancelled'].update(type='Base.Gloves_LeatherGloves', bodyLocation='base:hands')
    for spec in specs.values(): spec.update(capacityWeight=spec['weight'], equippedWeight=spec['weight']*.3)
    base=dict(worn=[dict(slot='base:shoes',id=99,type='Base.Shoes_TrainerTINT'),dict(slot='base:socks',id=98,type='Base.Socks_Ankle')],primary=False,secondary=False)
    ids['initialEquipment']=copy.deepcopy(base)
    loaded=dict(base,worn=sorted(base['worn']+[dict(slot=specs[name]['bodyLocation'],id=specs[name]['id'],type=specs[name]['type'])for name in ('target','cancelled')],key=lambda item:(item['slot'],item['id'])))
    executed=('target',)if mode=='toolkit'else('cancelled','target')
    def snapshot(removed=(), final=False):
        out=dict(case='worn-prepared',source=copy.deepcopy(ids['source']),items={},equipment=dict(loaded,worn=[item for item in loaded['worn']if item['id']not in {specs[name]['id']for name in removed}]),inventoryWeight=1+sum(specs[name]['capacityWeight']-specs[name]['equippedWeight']for name in removed))
        for name,spec in specs.items():
            worn=name in ('target','cancelled')and name not in removed
            out['items'][name]=dict(id=spec['id'],type=spec['type'],native={key:spec[key]for key in ('bodyLocation','bodyLocationClass','nativeShoe','cap')},
                wetness=10 if final and(name!='cancelled'or mode=='native')else 99,weight=spec['weight'],worn=worn,counts=dict(actor=1,root=1,source=1),
                slot=spec['bodyLocation'],slotId=next((entry['id']for entry in out['equipment']['worn']if entry['slot']==spec['bodyLocation']),False),capacityWeight=spec['capacityWeight'],equippedWeight=spec['equippedWeight'])
        return out
    initial=snapshot();final=snapshot(executed,True);transitions=[];removed=[]
    for name in executed:
        removed.append(name);state=snapshot(removed)
        transitions.append(dict(name=name,item=state['items'][name],equipment=state['equipment'],inventoryWeight=state['inventoryWeight']))
    final['unequipTransitions']=transitions
    plan=[('front','ISWringClothing'),('cancelled','ISUnequipAction'),('cancelled','ISWringClothing'),('target','ISUnequipAction'),('target','ISWringClothing'),('tail','ISWringClothing')]
    commands=[];removed=[]
    for index,(name,type_)in enumerate(plan):
        cancelled=name=='cancelled'and mode=='toolkit'
        command=dict(name=name,type=type_,producer=a.PRODUCER,item=specs[name]['id'],duration=495 if type_=='ISWringClothing'else 50,
            started=not cancelled,progress=not cancelled,actionRef='worn-action-'+str(index),operation=dict(front=1,cancelled=2,target=3,tail=4)[name],callbacksUntouched=True)
        if type_=='ISWringClothing':command['constructorWetness']=99
        else:command['cartsGuard']=True
        if cancelled:command['cancelled']=True
        else:
            command['startedAt']=100+index;before=snapshot(removed);command['admission']=dict(item=before['items'][name],equipment=before['equipment'],inventoryWeight=before['inventoryWeight'])
            events=[]
            for phase in (('perform','complete')if kind=='sp'else('perform',)):
                for boundary in ('begin','finish'):
                    observed=snapshot(removed)
                    if type_=='ISUnequipAction'and boundary=='finish'and(phase=='complete'or kind=='mp'):
                        removed.append(name);observed=snapshot(removed)
                    events.append(dict(phase=phase,boundary=boundary,succeeded=boundary=='finish',nativeRef='worn-episode-'+str(index),nativeClass='LuaTimedActionNew',
                        state=dict(item=observed['items'][name],equipment=observed['equipment'],inventoryWeight=observed['inventoryWeight'])))
            command['events']=events
        commands.append(command)
    refs=[command['actionRef']for command in commands];retained=[refs[0],refs[3],refs[4],refs[5]]
    def group(name,first):
        result=dict(token=commands[first]['operation'],unequip=refs[first],body=refs[first+1],bounds=dict(first=first+1,last=first+2),item=specs[name]['id'],unallocated=True)
        if mode=='toolkit':result['descriptor']=dict(unequipSource='native.ISUnequipAction',bodySource='native.ISWringClothing',item=specs[name]['id'],actual='root',worn=True, slot=specs[name]['bodyLocation'],setsWorn=False,capacity='external',bodyCapacity='external',equipmentWriter=True,cancelWaiting=False,moveRequiresProjection=True,projection='allowed',canonical=True)
        return result
    cancelled=group('cancelled',1);moves=[]
    if mode=='toolkit':
        cancelled.update(selected=refs[2],accepted=True,afterOrder=retained)
        moves=[dict(selected=refs[3],after=True,accepted=True,order=[refs[0],refs[5],refs[3],refs[4]],bounds=dict(first=3,last=4)),dict(selected=refs[4],after=False,accepted=True,order=retained,bounds=dict(first=2,last=3))]
    row.update(ids=copy.deepcopy(ids),input=copy.deepcopy(initial),authorityBaseline=copy.deepcopy(initial),client=copy.deepcopy(final),server=copy.deepcopy(final),commands=commands,
        edit=dict(cancelled=mode=='toolkit',reordered=mode=='toolkit',repeatDenied=False,untouched=True),wearSetup=[dict(type='ISWearClothing',producer='native ISWearClothing constructor',item=specs[name]['id'],duration=50,started=True,progress=True,startedAt=10+index)for index,name in enumerate(('target','cancelled'))],
        wornPrepared=dict(capacityFresh=True,front=refs[0],frontNative='native-worn-front',initialOrder=refs,cancelled=cancelled,target=group('target',3),moves=moves,finalOrder=retained if mode=='toolkit'else refs,before=copy.deepcopy(initial),after=copy.deepcopy(initial)))
    for index,receipt in enumerate(row['wearSetup']):
        name=('target','cancelled')[index];remaining=('target','cancelled')if index==0 else('cancelled',)
        before=snapshot(remaining);receipt.update(name=name,callbacksUntouched=True)
        receipt['events']=[]
        for phase in (('perform','complete')if kind=='sp'else('perform',)):
            for boundary in ('begin','finish'):
                observed=snapshot(('cancelled',)if index==0 else())if phase=='complete'and boundary=='finish'else before
                receipt['events'].append(dict(phase=phase,boundary=boundary,succeeded=boundary=='finish',nativeRef='native-wear-'+str(index),nativeClass='LuaTimedActionNew',state=dict(item=observed['items'][name],equipment=observed['equipment'],inventoryWeight=observed['inventoryWeight'])))
    return row,selection,ids,final


def wear_swap_evidence(kind,mode):
    row,selection,ids,_=evidence(kind,mode,'root');ids=copy.deepcopy(ids);ids.update(case='wear-swap',wearSwap=True,nativeWearSetup=True)
    ids['source']['kind']='wear-swap';specs=ids['items'];specs.pop('cancelled')
    specs['target'].update(type='Base.Scarf_White',bodyLocation='base:scarf',weight=.2)
    for name,index,full_type,weight in [('incoming',31,'Base.Gloves_LeatherGloves',.1),('displaced',32,'Base.Gloves_BurlapWrap',.2)]:
        specs[name]=dict(specs['front'],id=index,type=full_type,bodyLocation='base:hands',weight=weight)
    for spec in specs.values():spec.update(capacityWeight=spec['weight'],equippedWeight=spec['weight']*.3)
    base=dict(worn=[dict(slot='base:socks',id=99,type='Base.Socks_Ankle')],primary=False,secondary=False);ids['initialEquipment']=copy.deepcopy(base)
    def snapshot(worn=('target','displaced'),final=False):
        equipment=dict(base,worn=sorted(base['worn']+[dict(slot=specs[name]['bodyLocation'],id=specs[name]['id'],type=specs[name]['type'])for name in worn],key=lambda item:(item['slot'],item['id'])))
        reduction=lambda name:specs[name]['capacityWeight']-specs[name]['equippedWeight']
        out=dict(case='wear-swap',source=copy.deepcopy(ids['source']),equipment=equipment,inventoryWeight=1+reduction('target')+reduction('displaced')-sum(reduction(name)for name in worn),items={})
        for name,spec in specs.items():
            out['items'][name]=dict(id=spec['id'],type=spec['type'],native={key:spec[key]for key in ('bodyLocation','bodyLocationClass','nativeShoe','cap')},weight=spec['weight'],
                wetness=10 if final and name in ('front','target','tail')else 99,worn=name in worn,counts=dict(actor=1,root=1,source=1),slot=spec['bodyLocation'],
                slotId=next((entry['id']for entry in equipment['worn']if entry['slot']==spec['bodyLocation']),False),capacityWeight=spec['capacityWeight'],equippedWeight=spec['equippedWeight'])
        return out
    def observed(snapshot,name):return dict(item=snapshot['items'][name],equipment=snapshot['equipment'],inventoryWeight=snapshot['inventoryWeight'])
    def events(name,episode,before,after):
        return[dict(phase=phase,boundary=boundary,succeeded=boundary=='finish',nativeRef=episode,nativeClass='LuaTimedActionNew',state=observed(snapshot(after if boundary=='finish'and(phase=='complete'or kind=='mp')else before),name))for phase in (('perform','complete')if kind=='sp'else('perform',))for boundary in ('begin','finish')]
    def ack(index):return dict(client=True,capturePresent=True,ackState='completed',generation=1,transaction=43+index,kind='ISWearClothing',nativeSame=True,itemSame=True,actorSame=True,rootSame=True,queueSame=True,canonicalRoot=True,rootOwned=True,worn=True,slotSame=True,slotId=specs[('target','displaced','incoming')[index]]['id'])if kind=='mp'else dict(client=False,capturePresent=False,ackState=False)
    initial=snapshot();swapped=snapshot(('target','incoming'));final=snapshot(('incoming',),True)
    transition=snapshot(('incoming',));final['unequipTransitions']=[dict(name='target',**observed(transition,'target'))];final['swapTransition']=copy.deepcopy(swapped)
    setup=[]
    for index,name in enumerate(('target','displaced')):
        before=()if index==0 else('target',);after=('target',)if index==0 else('target','displaced')
        setup.append(dict(name=name,type='ISWearClothing',producer='native ISWearClothing constructor',item=specs[name]['id'],duration=50,started=True,progress=True,callbacksUntouched=True,startedAt=10+index,events=events(name,'setup-'+name,before,after),settled=observed(snapshot(after),name),fresh=True,ack=ack(index)))
    swap=dict(name='incoming',type='ISWearClothing',producer='native ISInventoryPaneContextMenu.onWearItems',item=specs['incoming']['id'],duration=50,started=True,progress=True,callbacksUntouched=True,startedAt=20,actionRef='swap-action',events=events('incoming','swap-episode',('target','displaced'),('target','incoming')))
    commands=[]
    for index,(name,type_)in enumerate((('front','ISWringClothing'),('target','ISUnequipAction'),('target','ISWringClothing'),('tail','ISWringClothing'))):
        before=('target','incoming')if index<2 else('incoming',);after=('incoming',)if index==1 else before
        command=dict(name=name,type=type_,producer=a.PRODUCER,item=specs[name]['id'],duration=50 if type_=='ISUnequipAction'else 495,
            started=True,progress=True,startedAt=100+index,actionRef='swap-body-'+str(index),operation=1 if index==0 else 2 if index in (1,2)else 3,callbacksUntouched=True,
            admission=observed(snapshot(before),name),events=events(name,'swap-body-episode-'+str(index),before,after))
        if type_=='ISUnequipAction':command['cartsGuard']=True
        else:command['constructorWetness']=99
        if kind=='sp'and type_=='ISWringClothing':command['events'][-1]['state']['item']['wetness']=10
        commands.append(command)
    refs=[command['actionRef']for command in commands]
    target=dict(token=2,unequip=refs[1],body=refs[2],bounds=dict(first=2,last=3),item=specs['target']['id'],unallocated=True)
    if mode=='toolkit':target['descriptor']=dict(unequipSource='native.ISUnequipAction',bodySource='native.ISWringClothing',item=specs['target']['id'],actual='root',worn=True,slot='base:scarf',setsWorn=False,capacity='external',bodyCapacity='external',equipmentWriter=True,cancelWaiting=False,moveRequiresProjection=True,projection='allowed',canonical=True)
    moves=[dict(selected=refs[1],after=True,accepted=True,order=[refs[0],refs[3],refs[1],refs[2]],bounds=dict(first=3,last=4)),dict(selected=refs[2],after=False,accepted=True,order=refs,bounds=dict(first=2,last=3))]if mode=='toolkit'else[]
    swap_ack=ack(2)
    row.update(ids=copy.deepcopy(ids),input=copy.deepcopy(initial),authorityBaseline=copy.deepcopy(initial),client=copy.deepcopy(final),server=copy.deepcopy(final),commands=commands,wearSetup=setup,
        edit=dict(cancelled=False,reordered=mode=='toolkit',repeatDenied=False,untouched=True),wearSwap=dict(before=copy.deepcopy(initial),wear=swap,queuedOrder=['swap-action']+refs,attempts=[],moves=moves,permission=dict(fresh=True,reason=False,physical=True,before=copy.deepcopy(swapped),after=copy.deepcopy(swapped)),initialOrder=refs,finalOrder=refs,front=refs[0],frontNative='front-episode',target=target,capacityFresh=True,ack=swap_ack))
    return row,selection,ids,final


def capacity_profile_evidence(kind='mp',mode='toolkit'):
    row,selection,ids,final=evidence(kind,mode,'worn-bag');selection['options']=dict(profile_capacity=True)
    rows=[dict(id=1000+index,type='Base.Nails',class_='ComboItem',count=5,uses=1,actualWeight=.05,capacityWeight=.05,ownerBag=ids['source']['bag'])for index in range(128)]
    for item in rows:item['class']=item.pop('class_')
    spec=dict(instances=128,bag=ids['source']['bag'],items=rows)
    ids.update(capacityProfile=copy.deepcopy(spec),nativeWearSetup=True);row['ids']=copy.deepcopy(ids)
    payload=dict(bag=ids['source']['bag'],bagType='Base.Bag_Military',bagRoot=True,bagWorn=True,instances=128,uses=128,totalWeight=sum(item['actualWeight']for item in rows),items=copy.deepcopy(rows),
        sourceInstances=128,actorInstances=128,rootInstances=0,bagCapacity=18,effectiveCapacity=18,sourceWeight=6.6,rootWeight=4.0)
    if kind=='sp':
        row['authorityBaseline']=copy.deepcopy(row['input']);row['wearSetup']=dict(type='ISWearClothing',producer='native ISWearClothing constructor',item=ids['source']['bag'],duration=50,started=True,progress=True,startedAt=10)
    for snapshot in (row['input'],row['authorityBaseline'],row['client'],row['server'],row['prepared']['before'],row['prepared']['after'],final):snapshot['capacityPayload']=copy.deepcopy(payload)
    measurement=dict(case='worn-bag',point='before-wring-producers',clock='getTimestampMs',units='coarse wall-clock milliseconds',instances=128,callsPerPath=32,warmupPerPath=2,
        samples=[dict(path=path,calls=16,elapsedMilliseconds=2,minUpper=4.0 if path=='legacy'else 4.0001,maxUpper=4.0 if path=='legacy'else 4.0001,minLower=4.0 if path=='legacy'else 0,maxLower=4.0 if path=='legacy'else 0)for path in ('legacy','qualified','qualified','legacy')],
        startedAt=20,finishedAt=30,totalMilliseconds=10,nativeWeight=4.0,before=copy.deepcopy(row['input']),after=copy.deepcopy(row['input']),queueIdle=True,helperSource=True,helperUnchanged=True,callbacksUntouched=True,
        scope='actual Java-backed own-player root and carried bag; synchronous idle tick including Lua loop/validation overhead; no FPS or other inventory-size extrapolation')
    cleanup=dict(case='worn-bag',bag=ids['source']['bag'],ids=[item['id']for item in rows],actorInstances=0,bagReachable=False,bagWorn=False,bagWorld=False,scope='removed from actor inventory; no object-destruction claim')
    row['capacityProfile']=dict(measurement=measurement,cleanupClient=copy.deepcopy(cleanup),cleanupServer=copy.deepcopy(cleanup))
    return row,selection,ids,final


class WringClothingRestorationProfileTests(unittest.TestCase):
    def selection(self, mode='toolkit'):
        return dict(kind='sp', mode=mode, mods=[mod for mod in a.MODS if mod != 'P4TidyUpMeister'],
                    languages=['EN'], clients=1, cases=['worn-bag'],
                    options=dict(wring_restoration_provider='native-returns'))

    def sample(self, mode):
        result = list(evidence('sp', mode, 'worn-bag')); row, selection, ids, final = result
        selection.update(self.selection(mode)); spec = ids['items']['target']; enabled = mode == 'toolkit'
        ids['restoration'] = True; row['ids']['restoration'] = True
        samples = [dict(case='worn-bag', point=point, loaded=False, selected=False, itemId=spec['id'], itemType=spec['type'],
                        state=state if enabled else False, candidates=1 if enabled else 0,
                        observedPreparation=enabled, plannedTransfers=planned if enabled else 0)
                   for point, state, planned in (('queued', 'prepare', 0), ('body', 'active', 0), ('final', 'completed', 1))]
        samples[1].update(bodyIndex=1, returnIndex=2 if enabled else False, tailIndex=3 if enabled else 2,
                          returnRef='native-return' if enabled else False)
        row['restoration'] = dict(provider='native-returns', samples=samples)
        if enabled:
            row['prepared']['returns'][0]['bodySettled'] = True
            row['prepared']['returns'][0]['allowMissing'] = True
        else:
            row['prepared']['returns'] = []
            for snapshot in (row['client'], row['server'], final):
                for name in ('target', 'cancelled'): snapshot['items'][name]['counts'] = dict(actor=1, root=1, source=0)
        return result

    def test_profile_requires_exact_mods_and_case(self):
        selection = self.selection(); a.validate(selection)
        for changed in (dict(mods=a.MODS), dict(mods=list(reversed(selection['mods']))), dict(cases=['root']),
                        dict(options=dict(wring_restoration_provider='other')),
                        dict(options=dict(wring_restoration_provider=False))):
            with self.assertRaises(ValueError): a.validate(dict(selection, **changed))

    def test_real_loan_receipts_and_queue_off_root(self):
        for mode in ('toolkit', 'native'):
            result = self.sample(mode); self.assertEqual([], a.check_case(*result))
            for field, value in (('loaded', True), ('selected', True), ('itemId', -1), ('candidates', 9), ('plannedTransfers', 1)):
                changed = copy.deepcopy(result); changed[0]['restoration']['samples'][0][field] = value
                self.assertTrue(a.check_case(*changed), field)
            changed = copy.deepcopy(result); changed[0]['restoration']['samples'][1]['state'] = 'waived'
            self.assertTrue(a.check_case(*changed))
        result = self.sample('native'); result[0]['prepared']['returns'] = [dict()]
        self.assertTrue(a.check_case(*result))
        result = self.sample('native'); result[0]['client']['items']['target']['counts'] = dict(actor=1, root=0, source=1)
        self.assertTrue(a.check_case(*result))
        result = self.sample('toolkit'); result[0]['prepared']['returns'][0]['bodySettled'] = False
        self.assertTrue(a.check_case(*result))
        result = self.sample('toolkit'); result[0]['prepared']['returns'] = []
        self.assertTrue(a.check_case(*result))


class WringClothingEvidenceTests(unittest.TestCase):
    def test_wear_swap_rejects_unfresh_edits_wrong_identity_and_unpaid_effects(self):
        for kind in ('sp','mp'):
            for mode in ('native','toolkit'):
                with self.subTest(kind=kind,mode=mode):self.assertEqual([],a.check_case(*evidence(kind,mode,'wear-swap')))
        changes=[
            lambda r:r['wearSwap']['permission'].update(fresh=False),
            lambda r:r['wearSwap']['permission'].update(physical=False),
            lambda r:r['wearSwap'].update(capacityFresh=1),
            lambda r:r['wearSetup'][0].update(fresh=False),
            lambda r:r['wearSetup'][0]['ack'].update(ackState='started'),
            lambda r:r['wearSetup'][1]['ack'].update(transaction=r['wearSetup'][0]['ack']['transaction']),
            lambda r:r['wearSwap']['ack'].update(capturePresent=False),
            lambda r:r['wearSwap']['ack'].update(ackState='started'),
            lambda r:r['wearSwap']['ack'].update(itemSame=False),
            lambda r:r['wearSwap']['ack'].update(canonicalRoot=False),
            lambda r:r['wearSwap']['ack'].update(slotId=r['ids']['items']['displaced']['id']),
            lambda r:r['wearSwap']['wear'].update(duration=1),
            lambda r:r['wearSwap']['wear'].update(callbacksUntouched=False),
            lambda r:r['wearSwap']['wear'].update(progress=False),
            lambda r:r['wearSwap']['wear']['events'].pop(),
            lambda r:r['wearSwap']['wear']['events'][0]['state']['item']['counts'].update(root=0),
            lambda r:r['wearSwap']['wear']['events'][0]['state']['item'].update(id=r['ids']['items']['displaced']['id']),
            lambda r:r['client']['items']['displaced'].update(worn=True),
            lambda r:r['client']['items']['incoming'].update(worn=False),
            lambda r:r['client']['items']['target'].update(wetness=60),
            lambda r:r['client'].update(inventoryWeight=1),
            lambda r:r['client']['equipment']['worn'].append(dict(slot='base:hat',id=111,type='Base.Hat_BaseballCap')),
            lambda r:r['client'].update(swapTransition=copy.deepcopy(r['input'])),
            lambda r:r['client'].update(unequipTransitions=[]),
            lambda r:r['wearSwap']['target'].update(bounds=dict(first=1,last=3)),
            lambda r:r['wearSwap']['target']['descriptor'].update(worn=1),
            lambda r:r['wearSwap']['moves'][0].update(selected=r['commands'][2]['actionRef']),
            lambda r:r['commands'][1].update(cancelled=True),
            lambda r:r['commands'][1].update(cartsGuard=False),
            lambda r:r['commands'][2].update(duration=1),
            lambda r:r['commands'][2]['events'][0]['state']['item'].update(worn=True),
            lambda r:r['commands'][-1].update(progress=False),
        ]
        for change in changes:
            result=evidence('mp','toolkit','wear-swap');change(result[0])
            self.assertTrue(a.check_case(*result),change)
        result=evidence('mp','toolkit','wear-swap');result[0]['ids']['items']['displaced']['equippedWeight']=.2;result[2].update(copy.deepcopy(result[0]['ids']))
        self.assertTrue(a.check_case(*result),'swap must increase actual native load')
        result=evidence('sp','native','wear-swap');result[0]['wearSwap']['wear']['events'][0]['state']=copy.deepcopy(result[0]['wearSwap']['wear']['events'][-1]['state'])
        self.assertTrue(a.check_case(*result),'SP native Wear effect is complete, not perform')
        result=evidence('sp','native','wear-swap');result[0]['commands'][2]['events'][-1]['state']['item']['wetness']=60
        self.assertTrue(a.check_case(*result),'native paid Wring completion cap is mandatory')

    def test_wear_swap_signed_native_transactions_and_naturally_dry_nonexecuted_gloves(self):
        for transaction in (-128,-1,1,127):
            result=evidence('mp','toolkit','wear-swap');row=result[0]
            row['wearSwap']['ack']['transaction']=transaction
            self.assertEqual([],a.check_case(*result))
        for transaction in (-129,0,128,True,1.5):
            result=evidence('mp','toolkit','wear-swap');result[0]['wearSwap']['ack']['transaction']=transaction
            self.assertTrue(a.check_case(*result))
        for mode in ('native','toolkit'):
            result=evidence('mp',mode,'wear-swap');row=result[0]
            for snapshot in (row['input'],row['authorityBaseline'],row['wearSwap']['before']):
                snapshot['items']['incoming']['wetness']=0;snapshot['items']['displaced']['wetness']=0
            for snapshot in (row['wearSwap']['permission']['before'],row['wearSwap']['permission']['after']):
                snapshot['items']['incoming']['wetness']=0;snapshot['items']['displaced']['wetness']=0
            self.assertEqual([],a.check_case(*result))
            row['input']['items']['displaced']['wetness']=-1;self.assertTrue(a.check_case(*result))
        result=evidence('sp','native','wear-swap');row=result[0]
        row['commands'][2].update(constructorWetness=50,duration=250)
        self.assertEqual([],a.check_case(*result),'native duration must use actual captured wetness, no fixed high-wetness assumption')
        row['commands'][2].update(constructorWetness=10,duration=50);self.assertTrue(a.check_case(*result))
        result=evidence('sp','native','wear-swap');row=result[0]
        for event in row['commands'][2]['events']:
            if event['phase']=='complete':event['state']['item']['wetness']=3
        for value in (row['client'],row['server'],result[3]):value['items']['target']['wetness']=2
        self.assertEqual([],a.check_case(*result),'native complete preserves an already-drier item; final can passively dry further')
        row['commands'][2]['events'][-1]['state']['item']['wetness']=10
        self.assertTrue(a.check_case(*result),'native min(begin,cap) must be observed exactly in SP')


    def test_wear_swap_unfresh_refusal_and_host_packet_shapes_are_strict(self):
        for mode in ('native','toolkit'):
            result=evidence('mp',mode,'wear-swap');row=result[0];value=row['wearSwap'];refs=value['initialOrder']
            attempt=dict(fresh=False,reason='unresolved:receipt-started',physical=False,accepted=False,attempted=mode=='toolkit',beforeOrder=copy.deepcopy(refs),afterOrder=copy.deepcopy(refs),before=copy.deepcopy(row['input']),after=copy.deepcopy(row['input']))
            value['attempts']=[attempt];self.assertEqual([],a.check_case(*result))
            for field,new_value in (('accepted',True),('attempted',mode!='toolkit'),('fresh',True),('physical',True)):
                changed=copy.deepcopy(result);changed[0]['wearSwap']['attempts'][0][field]=new_value;self.assertTrue(a.check_case(*changed))
            changed=copy.deepcopy(result);changed[0]['wearSwap']['attempts'][0]['afterOrder'].reverse();self.assertTrue(a.check_case(*changed))
            changed=copy.deepcopy(result);changed[0]['wearSwap']['attempts'][0]['after']['items']['target']['wetness']=10;self.assertTrue(a.check_case(*changed))
            # Host sync may arrive after client perform, or aggregate swap+later removal.
            for event in value['wear']['events']:event['state']=copy.deepcopy(value['wear']['events'][0]['state'])
            observed=copy.deepcopy(row['client']['swapTransition'])
            row['client']['swapTransition']=copy.deepcopy(row['client']);row['client']['swapTransition'].pop('swapTransition');row['client']['swapTransition'].pop('unequipTransitions')
            self.assertTrue(a.check_case(*result),'client swap must be observed before the pending target is admitted')
            row['client']['swapTransition']=observed
            value['ack']['ackState']='completed';value['finalAck']=dict(client=True,capturePresent=True,ackState=False)
            self.assertEqual([],a.check_case(*result),'retired final Ack cannot replace or invalidate earlier real permission witness')

    def test_host_server_wear_observation_must_match_its_real_later_unequip_event(self):
        for mode in ('native','toolkit'):
            result=evidence('mp',mode,'wear-swap');row=result[0];server=row['server'];event=server['unequipTransitions'][0]
            # Native Wear.complete has no explicit server clothing event. The
            # next native Unequip.complete can supply both read-only observations.
            transition=server['swapTransition'];transition['items']['target']=copy.deepcopy(event['item'])
            transition['equipment']=copy.deepcopy(event['equipment']);transition['inventoryWeight']=event['inventoryWeight']
            transition['items']['front']['wetness']=10
            result[3].update(copy.deepcopy(server))
            self.assertEqual([],a.check_case(*result))
            changed=copy.deepcopy(result);changed[0]['client']['swapTransition']=copy.deepcopy(transition)
            self.assertTrue(a.check_case(*changed),'Host client final observation cannot borrow the server deferred-event allowance')
            for mutation in (
                lambda r:r['server']['swapTransition']['items']['target'].update(wetness=98),
                lambda r:r['server']['swapTransition'].update(inventoryWeight=r['server']['unequipTransitions'][0]['inventoryWeight']+.0001),
                lambda r:r['server'].update(swapTransition=copy.deepcopy(r['input'])),
                lambda r:r['wearSwap']['permission'].update(before=copy.deepcopy(r['client']),after=copy.deepcopy(r['client'])),
                lambda r:r['wearSwap']['ack'].update(ackState='started'),
                lambda r:r['wearSwap']['permission'].update(fresh=False),
            ):
                changed=copy.deepcopy(result);mutation(changed[0]);changed[3].update(copy.deepcopy(changed[0]['server']));self.assertTrue(a.check_case(*changed),mutation)
        result=evidence('sp','native','wear-swap');row=result[0];event=row['server']['unequipTransitions'][0]
        transition=row['server']['swapTransition'];transition['items']['target']=copy.deepcopy(event['item'])
        transition['equipment']=copy.deepcopy(event['equipment']);transition['inventoryWeight']=event['inventoryWeight']
        result[3].update(copy.deepcopy(row['server']))
        self.assertTrue(a.check_case(*result),'SP retains its observed immediate swap phase requirement')

    def test_installed_kahlua_wear_swap_uses_native_constructor_and_fixture_physical_observer(self):
        game,jdk=os.environ.get('PZ_GAME'),os.environ.get('PZ_JDK')
        if not game or not jdk:self.skipTest('PZ_GAME and PZ_JDK required for native Wear/fixture Kahlua regression')
        a.audit_native(game)
        clothing=(Path(game)/'media/scripts/generated/items/clothing.txt').read_text()
        import re
        for name,weight in (('Gloves_BurlapWrap','0.2'),('Gloves_LeatherGloves','0.1')):
            block=re.search(r'\bitem\s+'+name+r'\s*\{(.*?)\n\s*\}',clothing,re.S).group(1)
            self.assertRegex(block,r'BodyLocation\s*=\s*base:hands');self.assertRegex(block,r'Weight\s*=\s*'+re.escape(weight)+r'\s*,');self.assertIn('ItemType = base:clothing',block)
        scenario=r'''
ItemTag={WEARABLE='wearable',REPLACE_PRIMARY='primary'}
ItemBodyLocation=setmetatable({},{__index=function(_,name)return name end})
function isClient()return false end
function instanceof(value,name)return value.class==name end
function getClassSimpleName(value)return value.class end
local values,slots={},{};local root={};local actor={}
function root:getItems()return{size=function()return #values end,get=function(_,i)return values[i+1]end}end
function root:getItemById(id)for _,item in ipairs(values)do if item:getID()==id then return item end end end
function actor:getInventory()return root end
function actor:isTimedActionInstant()return false end
function actor:getHumanVisual()return{getHairModel=function()return{contains=function()return false end}end}end
function actor:getWornItem(slot)return slots[slot]end
function actor:setWornItem(slot,item)slots[slot]=item end
function actor:getPrimaryHandItem()end;actor.getSecondaryHandItem=actor.getPrimaryHandItem
function actor:getWornItems()
 local entries={};for slot,item in pairs(slots)do entries[#entries+1]={getItem=function()return item end,getLocation=function()return slot end}end
 return{size=function()return #entries end,get=function(_,i)return entries[i+1]end,contains=function(_,item)return slots[item:getBodyLocation()]==item end}
end
function actor:getInventoryWeight()local total=0;for _,item in ipairs(values)do total=total+(self:getWornItems():contains(item)and item:getEquippedWeight()or item:getUnequippedWeight())end;return total end
local bodies={}
local function item(id,name,slot,weight)
 if not bodies[slot]then bodies[slot]=setmetatable({class='ItemBodyLocation'},{__tostring=function()return slot end})end
 local body=bodies[slot]
 return{class='Clothing',getID=function()return id end,getFullType=function()return name end,getBodyLocation=function()return body end,
  getCategory=function()return 'Clothing'end,getContainer=function()return root end,getWetness=function()return 99 end,getActualWeight=function()return weight end,
  getUnequippedWeight=function()return weight end,getEquippedWeight=function()return weight*.3 end,hasTag=function()return false end,getClothingItem=function()return{}end,canBeEquipped=function()return nil end}
end
local ids={case='wear-swap',wearSwap=true,nativeWearSetup=true,source={kind='wear-swap',bag=false,world=false},items={}}
local state={player=actor,ids=ids,source=root,items={}}
for index,name in ipairs(Fixture.namesFor(ids))do
 local spec=Fixture.swapCatalog[name];local slot=spec and spec.slot or name=='tail'and'base:shoes'or'base:socks'
 local value=item(index,spec and spec.type or'Base.Socks_Ankle',slot,spec and spec.weight or .1)
 values[index]=value;state.items[name]=value;local entry=Fixture.nativeWetnessContract(value);entry.id=index;entry.type=value:getFullType();entry.initial=100;ids.items[name]=entry
end
local before=ISWearClothing.complete
for _,name in ipairs({'target','displaced'})do local action=ISWearClothing:new(actor,state.items[name]);assert(action.maxTime==50);assert(action:complete())end
state.wearBaseline=Fixture.snapshot(state)
assert(not Fixture.swapPhysical(state));local weight=actor:getInventoryWeight()
local action=ISWearClothing:new(actor,state.items.incoming)
assert(action.item==state.items.incoming and action.maxTime==50 and actor:getInventoryWeight()==weight,'constructor caused physical effect')
assert(action:complete()and ISWearClothing.complete==before)
Fixture.clothingTransition(state)
local settled,snapshot=Fixture.swapPhysical(state)
assert(settled and snapshot.items.incoming.worn and not snapshot.items.displaced.worn and snapshot.items.target.worn)
assert(snapshot.items.incoming.counts.root==1 and snapshot.items.displaced.counts.root==1)
assert(actor:getInventoryWeight()>weight and math.abs(actor:getInventoryWeight()-weight-.07)<.000001)
assert(state.swapTransition and #state.unequipTransitions==0,'Wear replacement invented retained Unequip transition')
actor:setWornItem(state.items.target:getBodyLocation(),nil);Fixture.clothingTransition(state)
assert(#state.unequipTransitions==1 and state.unequipTransitions[1].name=='target')
assert(Fixture.namesFor({})[4]=='cancelled','historical execution names changed')
assert(Fixture.readyWetness(ids,'incoming',0)and Fixture.readyWetness(ids,'displaced',0))
assert(not Fixture.readyWetness(ids,'incoming',-1)and not Fixture.readyWetness(ids,'displaced',101))
assert(Fixture.readyWetness(ids,'target',50)and not Fixture.readyWetness(ids,'target',10))
assert(not Fixture.readyWetness({},'target',80),'historical readiness changed')
'''
        java=r'''
import java.nio.file.*;
import se.krka.kahlua.j2se.J2SEPlatform;
import se.krka.kahlua.luaj.compiler.LuaCompiler;
import se.krka.kahlua.vm.*;
public class WearSwapFixtureChecks {
 static KahluaTable env;static KahluaThread thread;
 static Object run(String value,String name)throws Exception{return thread.call(LuaCompiler.loadstring(value,name,env),new Object[0]);}
 static Object load(Path file)throws Exception{return run(Files.readString(file),file.getFileName().toString());}
 public static void main(String[] args)throws Exception{
  Path game=Path.of(args[0]),project=Path.of(args[1]);var platform=J2SEPlatform.getInstance();env=platform.newTable();env.rawset("_G",env);
  se.krka.kahlua.stdlib.BaseLib.register(env);se.krka.kahlua.j2se.MathLib.register(platform,env);se.krka.kahlua.stdlib.RandomLib.register(platform,env);
  se.krka.kahlua.stdlib.StringLib.register(platform,env);se.krka.kahlua.stdlib.CoroutineLib.register(platform,env);se.krka.kahlua.stdlib.OsLib.register(platform,env);se.krka.kahlua.stdlib.TableLib.register(platform,env);LuaCompiler.register(env);
  thread=new KahluaThread(System.out,platform,env);thread.debugOwnerThread=Thread.currentThread();
  try(var stream=Files.newInputStream(game.resolve("stdlib.lbc"))){thread.call(Prototype.loadByteCode(stream,env),new Object[0]);}
  run("require=function()return{}end;ItemBodyLocation=setmetatable({},{__index=function(_,key)return key end})","bootstrap");
  load(game.resolve("media/lua/shared/ISBaseObject.lua"));load(game.resolve("media/lua/shared/TimedActions/ISBaseTimedAction.lua"));load(game.resolve("media/lua/shared/TimedActions/ISWearClothing.lua"));
  env.rawset("Fixture",load(project.resolve("tests/native_queue/wring-clothing/shared/QueueWringClothing.lua")));load(Path.of(args[2]));
  System.out.println("PASS installed Kahlua real native Wear ctor/complete + fixture exact replacement observation (headless doubles)");
 }
}'''
        from tools.queue_checks import preparation_process
        with tempfile.TemporaryDirectory(prefix='pz-wear-swap-kahlua-')as temporary:
            root=Path(temporary);source=root/'WearSwapFixtureChecks.java';source.write_text(java);script=root/'scenario.lua';script.write_text(scenario)
            environment={key:value for key,value in os.environ.items()if key not in ('JAVA_TOOL_OPTIONS','JDK_JAVA_OPTIONS','_JAVA_OPTIONS')}
            result=preparation_process.run([str(Path(jdk)/'bin/java'),'-cp',str(Path(game)/'projectzomboid.jar'),str(source),game,str(PROJECT),str(script)],capture_output=True,text=True,timeout=60,env=environment)
            self.assertEqual(0,result.returncode,result.stdout+result.stderr)
            self.assertIn('PASS installed Kahlua',result.stdout)

    def test_capacity_profile_is_explicit_optional_and_preserves_source_payload(self):
        base=dict(suite='wring-clothing',cases=['worn-bag'],kind='mp',mode='toolkit',languages=['EN'],clients=1,mods=a.MODS,options=dict(mp_host=True))
        a.validate(dict(base,options=dict(mp_host=True,profile_capacity=True)))
        a.validate(dict(base,options=dict(mp_host=True,profile_capacity=False)))
        for value in (None,0,1,'true'):
            with self.assertRaises(ValueError):a.validate(dict(base,options=dict(mp_host=True,profile_capacity=value)))
        with self.assertRaises(ValueError):a.validate(dict(base,cases=['worn-prepared'],options=dict(mp_host=True,profile_capacity=True)))
        for kind in ('sp','mp'):
            for mode in ('native','toolkit'):self.assertEqual([],a.check_case(*capacity_profile_evidence(kind,mode)))
        result=capacity_profile_evidence();result[1]['options']['profile_capacity']=False;self.assertTrue(a.check_case(*result))
        mutations=[
            lambda r:r['ids']['capacityProfile'].update(instances=127),
            lambda r:r['capacityProfile']['measurement']['before']['capacityPayload']['items'][0].update(count=1),
            lambda r:r['client']['capacityPayload']['items'][0].update(uses=0),
            lambda r:r['client']['capacityPayload']['items'][0].update(actualWeight=.001),
            lambda r:r['client']['capacityPayload']['items'][0].update(ownerBag=99),
            lambda r:r['client']['capacityPayload']['items'].pop(),
            lambda r:r['client']['capacityPayload'].update(rootInstances=1),
            lambda r:r['client']['capacityPayload'].update(actorInstances=127),
            lambda r:r['server']['capacityPayload'].update(bagRoot=False),
            lambda r:r['server']['capacityPayload'].update(bagWorn=False),
            lambda r:r['server']['capacityPayload'].update(totalWeight=.128),
            lambda r:r['server']['capacityPayload'].update(effectiveCapacity=1),
            lambda r:r['capacityProfile']['measurement'].update(queueIdle=False),
            lambda r:r['capacityProfile']['measurement'].update(helperUnchanged=False),
            lambda r:r['capacityProfile']['measurement'].update(callbacksUntouched=False),
            lambda r:r['capacityProfile']['measurement'].update(callsPerPath=16),
            lambda r:r['capacityProfile']['measurement']['samples'].pop(),
            lambda r:r['capacityProfile']['measurement']['samples'][1].update(path='legacy'),
            lambda r:r['capacityProfile']['measurement']['samples'][0].update(elapsedMilliseconds=-1),
            lambda r:r['capacityProfile']['measurement']['samples'][0].update(elapsedMilliseconds=True),
            lambda r:r['capacityProfile']['measurement']['samples'][1].update(minUpper=1),
            lambda r:r['capacityProfile']['measurement']['samples'][1].update(minUpper=3.9999999),
            lambda r:r['capacityProfile']['measurement']['samples'][1].update(maxUpper=float('nan')),
            lambda r:r['capacityProfile']['measurement']['samples'][1].update(maxLower=1),
            lambda r:r['capacityProfile']['measurement'].update(totalMilliseconds=1),
            lambda r:r['capacityProfile']['measurement'].update(finishedAt=101,totalMilliseconds=81),
            lambda r:r['capacityProfile']['cleanupClient'].update(actorInstances=1),
            lambda r:r['capacityProfile']['cleanupServer'].update(bagWorn=True),
            lambda r:r['capacityProfile']['cleanupServer']['ids'].pop(),
        ]
        for mutation in mutations:
            result=capacity_profile_evidence();mutation(result[0]);self.assertTrue(a.check_case(*result),mutation)
        # Zero-ms groups are legitimate coarse clock observations, never a speed pass.
        result=capacity_profile_evidence();measurement=result[0]['capacityProfile']['measurement']
        for sample in measurement['samples']:sample['elapsedMilliseconds']=0
        measurement.update(totalMilliseconds=0,finishedAt=measurement['startedAt'])
        self.assertEqual([],a.check_case(*result))

    def test_capacity_helper_preserves_real_instance_count_source_and_readonly_samples(self):
        from lupa.lua51 import LuaRuntime
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.globals().fixture=str(PROJECT/'tests/native_queue/wring-clothing/shared/QueueWringCapacityProfile.lua')
        lua.globals().jsonSource=str(PROJECT/'tests/native_queue/health/shared/QueueHealthEvents.lua')
        lua.execute(r'''
package.loaded.QueueHealthEvents=dofile(jsonSource)
package.loaded['PZSurvivorToolkit/SourceProof']={closure=function(_,file)assert(file=='ActionQueueWeights.lua');return true end}
function instanceof(value,name)return value.class==name end
function getClassSimpleName(value)return value.class end
local rootItems,sourceItems={},{};local root={class='ItemContainer'};local source={class='ItemContainer'};local player={};local worn=true
local bag={class='InventoryContainer',getID=function()return 20 end,getFullType=function()return 'Base.Bag_Military'end,getContainer=function()return root end,
 getItemContainer=function()return source end,getWorldItem=function()return nil end};rootItems[1]=bag
local function list(values)return{size=function()return #values end,get=function(_,index)return values[index+1]end}end
function root:getItems()return list(rootItems)end
function source:getItems()return list(sourceItems)end
function root:getItemById(id)for _,item in ipairs(rootItems)do if item:getID()==id then return item end end end
function source:getContainingItem()return bag end
function source:getCapacity()return 18 end;source.getEffectiveCapacity=source.getCapacity
function source:getCapacityWeight()return #sourceItems*.05 end
function root:getCapacityWeight()return 4 end
function player:getInventory()return root end
function player:getWornItems()return{contains=function(_,item)return worn and item==bag end,getItemById=function(_,id)return worn and id==20 and bag or nil end}end
function player:hasTimedActions()return false end
local created=0
function source:AddItem(kind)
 assert(kind=='Base.Nails');created=created+1;local id=1000+created
 local item={class='ComboItem',getID=function()return id end,getFullType=function()return kind end,getCount=function()return 5 end,
 getCurrentUses=function()return 1 end,getActualWeight=function()return .05 end,getUnequippedWeight=function()return .05 end,getContainer=function()return source end}
 sourceItems[#sourceItems+1]=item;return item
end
function getPlayer()return player end
local queue={character=player,queue={}}
local C=dofile(fixture);local state={ids={case='worn-bag'},player=player,source=source,bag=bag}
C.seed(state);assert(created==128 and #sourceItems==128 and #state.ids.capacityProfile.items==128,'script Count expanded physical instances')
local payload=C.snapshot(state);assert(payload.instances==128 and payload.uses==128 and math.abs(payload.totalWeight-6.4)<.000001)
assert(payload.items[1].count==5 and payload.items[1].uses==1 and payload.rootInstances==0)
local first=sourceItems[1];sourceItems[129]=first;assert(not pcall(C.snapshot,state),'duplicate exact-ID instance accepted');sourceItems[129]=nil
sourceItems[1]=nil;rootItems[2]=first;assert(not pcall(C.snapshot,state),'payload left source without rejection');sourceItems[1]=first;rootItems[2]=nil
local getCount=first.getCount;first.getCount=function()return 1 end;assert(not pcall(C.snapshot,state));first.getCount=getCount
local calls={legacy=0,qualified=0};local mode='normal';local clock=0
function getTimestampMs()clock=clock+1;return clock end
PZSurvivorToolkit={ActionQueueWeights={capacity=function(container,actor,discount)
 assert(container==root and actor==player and(discount==nil or discount==0));local key=discount==nil and'legacy'or'qualified';calls[key]=calls[key]+1
 if mode=='mutate'then first.getCurrentUses=function()return 2 end end
 if mode=='invalid'then return nil end
 return discount==nil and 4 or 4.0001,discount==nil and 4 or 0
end}}
local function snapshot()return{capacityPayload=C.snapshot(state),clothes={id=7,wetness=99}}end
local report=C.measure(state,queue,snapshot)
assert(calls.legacy==34 and calls.qualified==34 and report.callsPerPath==32 and report.warmupPerPath==2)
assert(report.before.capacityPayload.items[1].count==5 and #report.samples==4 and report.samples[1].path=='legacy'and report.samples[3].path=='qualified')
mode='invalid';assert(not pcall(C.measure,state,queue,snapshot),'missing bounds were reported as measurements')
mode='mutate';assert(not pcall(C.measure,state,queue,snapshot),'profiling physical mutation was accepted');first.getCurrentUses=function()return 1 end
mode='normal';queue.current={};assert(not pcall(C.measure,state,queue,snapshot),'active native timer entered measurement');queue.current=nil
rootItems[1]=nil;worn=false;local cleanup=C.cleanupProof(state)
assert(cleanup.actorInstances==0 and not cleanup.bagReachable and #cleanup.ids==128)
rootItems[2]=first;assert(not pcall(C.cleanupProof,state),'cleanup overlooked exact payload ID remaining in actor root')
''')
        source=(PROJECT/'tests/native_queue/wring-clothing/shared/QueueWringCapacityProfile.lua').read_text()
        for forbidden in ('setCount(','setActualWeight(','setWeight(','setCapacity(','sendAddItemToContainer(','forceComplete(','installObserver(','bindNative('):self.assertNotIn(forbidden,source)
        client=(PROJECT/'tests/native_queue/wring-clothing/client/ZZWringClothing.lua').read_text()
        self.assertIn("profile.run();state.frontAction=produce('front'",client)
        self.assertIn("profile.final=client;profile.cleanupRequested=true;request('ProfileCleanup')",client)

    def test_profile_measurement_and_cleanup_require_independent_ordered_raw_receipts(self):
        for kind in ('sp','mp'):
            for mode in ('native','toolkit'):
                row,selection,ids,verified=capacity_profile_evidence(kind,mode);selection['cases']=['worn-bag'];row.update(suite='wring-clothing',event='case',id='worn-bag',actor='client1',kind=kind,mode=mode)
                setup=dict(suite='wring-clothing',event='setup',cases=['worn-bag'],queueEnabled=mode=='toolkit',nativeDurations=True,adapterInstalled=True)
                ending=dict(suite='wring-clothing',event='complete',cases=['worn-bag'],performed=1,failed=0,skipped=0)
                authority=[a.PREFIX+'PREPARED '+json.dumps(ids),a.PREFIX+'WEAR_BASELINE '+json.dumps(row['authorityBaseline']),a.PREFIX+'VERIFIED '+json.dumps(verified),a.PREFIX+'PROFILE_CLEANED '+json.dumps(row['capacityProfile']['cleanupServer'])]
                client=['[QUEUE_CHECK] '+json.dumps(setup),a.PREFIX+'CLIENT_PLACEMENT '+json.dumps(dict(case='worn-bag',proof=row['clientPlacement'])),a.PREFIX+'CAPACITY_PROFILE '+json.dumps(row['capacityProfile']['measurement'])]
                if kind=='sp':client+=authority
                client+=['[QUEUE_CHECK] '+json.dumps(row),'[QUEUE_CHECK] '+json.dumps(ending),a.PREFIX+'COMPLETE '+json.dumps(dict(cases=['worn-bag']))]
                with tempfile.TemporaryDirectory()as temporary:
                    root=Path(temporary);path=root/('client1-launch.log'if kind=='sp'else'server-launch.log')
                    (root/'client1-launch.log').write_text('\n'.join(client));(root/'server-launch.log').write_text('\n'.join(authority))
                    self.assertEqual([],a.verify(root,selection,{})['issues'])
                    text=path.read_text();path.write_text('\n'.join(line for line in text.splitlines()if not line.startswith(a.PREFIX+'PROFILE_CLEANED ')))
                    self.assertTrue(a.verify(root,selection,{})['issues'],'unobserved cleanup cannot qualify')
                    path.write_text(text+'\n'+authority[-1]);self.assertTrue(a.verify(root,selection,{})['issues'],'duplicate cleanup cannot qualify')
                    path.write_text(text)
                    client_path=root/'client1-launch.log';text=client_path.read_text();client_path.write_text('\n'.join(line for line in text.splitlines()if not line.startswith(a.PREFIX+'CAPACITY_PROFILE ')))
                    self.assertTrue(a.verify(root,selection,{})['issues'],'missing real measurement marker cannot qualify')

    def test_profile_host_prepare_and_verified_cleanup_use_selected_option(self):
        from lupa.lua51 import LuaRuntime
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.globals().serverSource=str(PROJECT/'tests/native_queue/wring-clothing/server/ZZWringClothingServer.lua')
        lua.globals().diagnosticSource=str(PROJECT/'tests/native_queue/wring-clothing/shared/QueueWringDiagnostics.lua')
        lua.execute(r'''
function isServer()return true end
function getTimestampMs()return 0 end
function print()end -- Protocol doubles do not emit fake native-capture markers.
local command,tick;Events={OnClothingUpdated={Add=function()end},OnClientCommand={Add=function(callback)command=callback end},OnTick={Add=function(callback)tick=callback end}}
local actor={getUsername=function()return 'client1'end};local disposed=false;local receipt={case='worn-bag'};local sent={};local profile
function sendServerCommand(player,module,name,args)assert(player==actor and module=='WringClothingTest');sent[#sent+1]=name end
package.loaded.QueueTestSelection={cases={'worn-bag'},mode='toolkit',options={profile_capacity=true}}
package.loaded.QueueEnergyPlacement={target=function(value)return value end,observeCentered=function()return{}end,poll=function()return{}end,atCentered=function()return true end}
package.loaded.QueueHealthEvents={encode=function()return'{}'end}
package.loaded.QueueWringCapacityProfile={cleanupProof=function(state)assert(disposed and state.ids.capacityProfile);return receipt end}
package.loaded.QueueWringClothing={observesClothing=function()return false end,
 prepare=function(player,case,mode,placement,proof,previous,enabled)
  assert(player==actor and case=='worn-bag'and mode=='toolkit'and previous==nil and enabled==true,'Host option did not reach actual authority Prepare')
  profile={player=actor,ids={case=case,capacityProfile={},nativeWearSetup=true}};return profile
 end,wearBaseline=function()return receipt end,verify=function()return receipt end,dispose=function(state)assert(state==profile and state.profileVerified);disposed=true end}
package.loaded.QueueWringDiagnostics=dofile(diagnosticSource)
dofile(serverSource)
command('WringClothingTest','Prepare',actor,{case='worn-bag',placement={},clientPlacement={mode='local',centered=true,centers=1}});tick();assert(sent[#sent]=='Prepared')
command('WringClothingTest','WearBaseline',actor,{case='worn-bag'});tick();assert(sent[#sent]=='WearBaselined')
command('WringClothingTest','Verify',actor,{case='worn-bag'});tick();assert(sent[#sent]=='Verified'and profile.profileVerified and not disposed)
command('WringClothingTest','ProfileCleanup',actor,{case='worn-bag'});tick();assert(sent[#sent]=='ProfileCleaned'and disposed)
''')

    def test_capacity_profile_native_script_pins_are_optional(self):
        game=os.environ.get('PZ_GAME')
        if not game:self.skipTest('PZ_GAME required for native Nails/bag source audit')
        audit=a.audit_native(game,True)
        for path,value in a.PROFILE_CRC.items():self.assertEqual(value,audit[path])
        import re
        text=(Path(game)/'media/scripts/generated/items/normal.txt').read_text()
        block=re.search(r'\bitem\s+Nails\s*\{(.*?)\n\s*\}',text,re.S).group(1)
        self.assertRegex(block,r'Weight\s*=\s*0\.05\s*,');self.assertRegex(block,r'count\s*=\s*5\s*,')
        self.assertNotIn('media/scripts/generated/items/normal.txt',a.audit_native(game))

    def test_selected_pack_and_grouped_sp_host_modes(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                selection = dict(suite='wring-clothing', cases=list(a.CASES), kind=kind, mode=mode, languages=['EN'],
                                 clients=1, mods=a.MODS, options={'mp_host': True} if kind == 'mp' else {})
                a.validate(selection)
                self.assertIs(adapters.get('wring-clothing'), a)
                for case in a.CASES:
                    self.assertEqual([], a.check_case(*evidence(kind, mode, case)))
        selection['options'] = {}
        with self.assertRaises(ValueError): a.validate(selection)
        selection['options'] = {'mp_host': True, 'world_template': 'old-save'}
        with self.assertRaises(ValueError): a.validate(selection)

    def test_carried_only_selector_preserves_historical_cases(self):
        base = dict(suite='wring-clothing', kind='mp', mode='toolkit', languages=['EN'], clients=1, mods=a.MODS, options={'mp_host': True})
        for chosen in (['worn-bag'], ['root', 'worn-bag'], list(a.CASES)):
            a.validate(dict(base, cases=chosen))
        for chosen in ([], ['worn-bag', 'root'], ['worn-bag', 'worn-bag'], ['bag-magazine']):
            with self.assertRaises(ValueError): a.validate(dict(base, cases=chosen))
        self.assertTrue(a.complete(dict(base, cases=['worn-bag']), 'client1', a.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=['worn-bag']))))

    def test_prepared_groups_require_exact_tokens_bounds_moves_and_unadmitted_cancel(self):
        for change in ('split-token', 'front-token', 'split-order', 'wrong-bound', 'wrong-selection', 'missing-body-move',
                       'cancelled-admitted', 'cancelled-physical', 'fetch-not-started', 'wrong-start-owner', 'wrong-facts',
                       'root-not-required', 'missing-fetch-projection', 'physical-edit', 'future-drying-credit', 'allocated', 'forged-pending-source'):
            result = evidence(case='worn-bag'); row = result[0]; prepared = row['prepared']
            body = next(command for command in row['commands'] if command['name'] == 'target' and command['type'] == 'ISWringClothing')
            fetch = next(command for command in row['commands'] if command['name'] == 'target' and command['type'] == 'ISInventoryTransferAction')
            if change == 'split-token': body['operation'] = 100
            if change == 'front-token': fetch['operation'] = body['operation'] = row['commands'][0]['operation']
            if change == 'split-order': prepared['finalOrder'][1], prepared['finalOrder'][2] = prepared['finalOrder'][2], prepared['finalOrder'][1]
            if change == 'wrong-bound': prepared['target']['bounds']['first'] = 1
            if change == 'wrong-selection': prepared['moves'][0]['selected'] = prepared['target']['body']
            if change == 'missing-body-move': prepared['moves'].pop()
            if change == 'cancelled-admitted': row['commands'][2]['started'] = True
            if change == 'cancelled-physical': row['client']['items']['cancelled']['wetness'] = 10
            if change == 'fetch-not-started': fetch['started'] = False
            if change == 'wrong-start-owner': body['rootAtStart']['counts'] = dict(actor=1, root=0, source=1)
            if change == 'wrong-facts': prepared['target']['descriptor']['actual'] = 'root'
            if change == 'root-not-required': prepared['target']['descriptor']['requires'] = 'bag'
            if change == 'missing-fetch-projection': prepared['target']['descriptor']['projection'] = 'unhandled'
            if change == 'physical-edit': prepared['after']['items']['target']['wetness'] = 10
            if change == 'future-drying-credit': row['client']['items']['target']['capacityWeight'] = .01
            if change == 'allocated': prepared['cancelled']['unallocated'] = False
            if change == 'forged-pending-source':
                for phase in ('before','after'): prepared[phase]['items']['target']['counts'] = dict(actor=1, root=1, source=0)
            self.assertTrue(a.check_case(*result), change)

    def test_deferred_container_resolver_is_owned_real_closed_and_has_no_walk_expansion(self):
        for kind in ('sp','mp'):
            row = evidence(kind=kind, case='worn-bag')[0]
            self.assertEqual(['ISWringClothing','ISQueueActionsAction','ISInventoryTransferAction','ISWringClothing',
                              'ISQueueActionsAction','ISInventoryTransferAction','ISWringClothing','ISWringClothing'], [command['type'] for command in row['commands']])
            self.assertEqual([], a.check_case(*evidence(kind=kind, case='worn-bag')))
        for change in ('missing-prep', 'wrong-container', 'callbacks', 'cancel-admitted', 'cancel-resolved', 'no-real-perform', 'failed',
                       'missing-native', 'wrong-owner', 'open-expansion', 'walk-child', 'foreign-child', 'position', 'wrong-capacity', 'wrong-owner-key', 'stale-lease'):
            result = evidence(case='worn-bag'); row = result[0]
            prep = next(command for command in row['commands'] if command['name'] == 'target' and command['type'] == 'ISQueueActionsAction')
            cancelled = next(command for command in row['commands'] if command['name'] == 'cancelled' and command['type'] == 'ISQueueActionsAction')
            if change == 'missing-prep': row['commands'].remove(prep)
            if change == 'wrong-container': prep['preparation']['container'] = 999
            if change == 'callbacks': prep['preparation']['callbacksUntouched'] = False
            if change == 'cancel-admitted': cancelled['admitted'] = True
            if change == 'cancel-resolved': cancelled['resolver'] = copy.deepcopy(prep['resolver'])
            if change == 'no-real-perform': prep['resolver'] = []
            if change == 'failed': prep['resolver'][1]['succeeded'] = False
            if change == 'missing-native': prep['resolver'][0]['nativeRef'] = False
            if change == 'wrong-owner': prep['resolver'][0]['ownedContainer'] = False
            if change == 'open-expansion': prep['resolver'][0]['expansionClosed'] = False
            if change == 'walk-child': prep['resolver'][0]['unexpectedChildren'] = [dict(type='ISWalkToTimedAction', actionRef='native-walk')]
            if change == 'foreign-child': prep['resolver'][0]['unexpectedChildren'] = [dict(type='ISEquipWeaponAction', actionRef='foreign')]
            if change == 'position': prep['resolver'][0]['position']['x'] += 1
            if change == 'wrong-capacity': row['prepared']['target']['descriptor']['prepLease']['capacity'] = 'external'
            if change == 'wrong-owner-key': row['prepared']['target']['descriptor']['prepLease']['owner'] = 999
            if change == 'stale-lease': row['prepared']['target']['descriptor']['prepLease']['fresh'] = False
            self.assertTrue(a.check_case(*result), change)
        disabled = evidence(mode='native', case='worn-bag')
        self.assertNotIn('ISQueueActionsAction', [command['type'] for command in disabled[0]['commands']])
        disabled[0]['commands'][1]['type'] = 'ISQueueActionsAction'
        self.assertTrue(a.check_case(*disabled), 'disabled controls cannot adopt owned deferred preparation')

    def test_native_p4_return_requires_exact_earned_item_endpoint_episode_and_success(self):
        for mode in ('native', 'toolkit'):
            self.assertEqual([], a.check_case(*evidence(case='worn-bag', mode=mode)))
        for change in ('missing-return', 'wrong-id', 'cancelled-return', 'wrong-bag', 'missing-native', 'failed', 'missing-finish', 'wrong-duration'):
            result = evidence(case='worn-bag'); receipt = result[0]['prepared']['returns'][0]
            if change == 'missing-return': result[0]['prepared']['returns'] = []
            if change == 'wrong-id': receipt['items'][0]['id'] = 999
            if change == 'cancelled-return': receipt['items'].append(dict(id=result[2]['items']['cancelled']['id'], type='Base.Socks_Ankle'))
            if change == 'wrong-bag': receipt['toBag'] = 999
            if change == 'missing-native': receipt['events'][0]['nativeRef'] = False
            if change == 'failed': receipt['events'][1]['succeeded'] = False
            if change == 'missing-finish': receipt['events'].pop()
            if change == 'wrong-duration': receipt['duration'] = 50
            self.assertTrue(a.check_case(*result), change)

    def test_centered_placement_rejects_tile_edges_and_unproven_centering(self):
        for kind in ('sp', 'mp'):
            result = evidence(kind=kind)
            result[0]['clientPlacement']['actual']['x'] = result[2]['origin']['x']
            self.assertTrue(a.check_case(*result))
            result = evidence(kind=kind)
            result[2]['placementProof']['actual']['y'] = result[2]['origin']['y']
            result[0]['ids'] = copy.deepcopy(result[2])
            self.assertTrue(a.check_case(*result))
            result = evidence(kind=kind)
            del result[0]['clientPlacement']['centered']
            self.assertTrue(a.check_case(*result))
            result = evidence(kind=kind)
            result[0]['clientPlacement']['centers'] = 0
            self.assertTrue(a.check_case(*result))

    def test_drying_bounds_preserve_observed_native_caps(self):
        for case in a.CASES:
            result = evidence(case=case)
            for phase in ('client', 'server'):
                for name in ('front', 'target', 'tail'):
                    result[0][phase]['items'][name]['wetness'] -= 1
            result[3].update(copy.deepcopy(result[0]['server']))
            self.assertEqual([], a.check_case(*result))
        for case, name, wetness in [('root', 'target', 60), ('world', 'target', 60), ('root', 'cancelled', 10)]:
            result = evidence(case=case); result[0]['client']['items'][name]['wetness'] = wetness
            self.assertTrue(a.check_case(*result))

    def test_exact_input_source_debit_identity_and_equipment(self):
        for case in a.CASES:
            for phase in ('input', 'client', 'server'):
                result = evidence(case=case); result[0][phase]['items']['target']['counts']['source'] += 1
                self.assertTrue(a.check_case(*result))
                result = evidence(case=case); result[0][phase]['items']['target']['id'] += 1
                self.assertTrue(a.check_case(*result))
        result = evidence(case='worn'); result[0]['client']['items']['target']['worn'] = True
        self.assertTrue(a.check_case(*result))
        result = evidence(case='world'); result[2]['source']['world']['x'] += 1; result[0]['ids'] = copy.deepcopy(result[2])
        self.assertTrue(a.check_case(*result))
        for case in ('worn-bag', 'world'):
            result = evidence(case=case); result[0]['client']['items']['target']['counts']['root'] = 1
            self.assertTrue(a.check_case(*result))

    def test_native_preludes_durations_and_pending_only_edits(self):
        for case in ('worn', 'worn-bag', 'world'):
            result = evidence(case=case); result[0]['commands'].pop(1)
            self.assertTrue(a.check_case(*result))
        for change in ('callbacks', 'duration', 'progress', 'cancelled', 'dependency', 'untouched', 'tail'):
            result = evidence(); row = result[0]
            if change == 'callbacks': row['commands'][0]['callbacksUntouched'] = False
            if change == 'duration': row['commands'][0]['duration'] = 1
            if change == 'progress': row['commands'][0]['progress'] = False
            if change == 'cancelled': row['commands'][1]['started'] = True
            if change == 'dependency': row['edit']['repeatDenied'] = False
            if change == 'untouched': row['edit']['untouched'] = False
            if change == 'tail': row['commands'].pop()
            self.assertTrue(a.check_case(*result), change)

    def test_transfer_wait_sentinel_is_specific_to_native_mp_wrapper(self):
        for case in ('worn-bag', 'world'):
            for mode in ('native', 'toolkit'):
                result = evidence(mode=mode, case=case)
                self.assertEqual([], a.check_case(*result))
                for duration in (0, -2, 50, False):
                    result = evidence(mode=mode, case=case); next(command for command in result[0]['commands'] if command['type'] == 'ISInventoryTransferAction')['duration'] = duration
                    self.assertTrue(a.check_case(*result))
                result = evidence(kind='sp', mode=mode, case=case); next(command for command in result[0]['commands'] if command['type'] == 'ISInventoryTransferAction')['duration'] = -1
                self.assertTrue(a.check_case(*result))
        for case, index in (('root', 0), ('worn', 1)):
            result = evidence(case=case); result[0]['commands'][index]['duration'] = -1
            self.assertTrue(a.check_case(*result), 'wring/unequip must not inherit transfer sentinel')

    def test_captured_v6_host_command_rows_preserve_transfer_constructor_sentinel(self):
        # Emitted v6 Host receipts; IDs/clocks are normalized by evidence().
        captured = [('front', 'ISWringClothing', 500), ('target', 'ISInventoryTransferAction', -1),
                    ('target', 'ISWringClothing', 500), ('tail', 'ISWringClothing', 500)]
        for case in ('world',):
            result = evidence(mode='native', case=case)
            for command, (name, kind, duration) in zip(result[0]['commands'], captured):
                self.assertEqual((name, kind), (command['name'], command['type']))
                command['duration'] = duration
                if kind == 'ISWringClothing': command['constructorWetness'] = 100
            self.assertEqual([], a.check_case(*result))

    def test_worn_prepared_real_group_and_native_effect_profiles(self):
        for kind in ('sp','mp'):
            for mode in ('native','toolkit'):
                result=evidence(kind=kind,mode=mode,case='worn-prepared')
                self.assertEqual([],a.check_case(*result,copy.deepcopy(result[0]['authorityBaseline'])))
        base=dict(suite='wring-clothing',kind='mp',mode='toolkit',languages=['EN'],clients=1,mods=a.MODS,options=dict(mp_host=True))
        a.validate(dict(base,cases=['worn-prepared','wear-swap','worn-bag']))
        with self.assertRaises(ValueError):a.validate(dict(base,cases=['worn-bag','worn-prepared']))
        a.validate(dict(base,cases=['worn-prepared']))

    def test_cancelled_worn_clothing_can_naturally_dry_without_paid_action(self):
        for kind in ('sp','mp'):
            for wetness in (0, .1, 10, 80, 100):
                result=evidence(kind=kind,case='worn-prepared')
                for snapshot in (result[0]['client'],result[0]['server'],result[3]):snapshot['items']['cancelled']['wetness']=wetness
                self.assertEqual([],a.check_case(*result))
                for index in (1,2):
                    for proof in ('started','admission','events'):
                        forged=copy.deepcopy(result);command=forged[0]['commands'][index]
                        if proof=='started':command.update(started=True,startedAt=120)
                        elif proof=='admission':command['admission']=copy.deepcopy(forged[0]['input']['items']['cancelled'])
                        else:command['events']=[dict(phase='perform',boundary='begin')]
                        self.assertTrue(a.check_case(*forged),(kind,wetness,index,proof))
            for wetness in (-1,100.001,float('nan'),float('inf')):
                result=evidence(kind=kind,case='worn-prepared')
                for snapshot in (result[0]['client'],result[0]['server'],result[3]):snapshot['items']['cancelled']['wetness']=wetness
                self.assertTrue(a.check_case(*result))
            result=evidence(kind=kind,mode='native',case='worn-prepared')
            for snapshot in (result[0]['client'],result[0]['server'],result[3]):snapshot['items']['cancelled']['wetness']=0
            self.assertTrue(a.check_case(*result),'executed native-off glove must still satisfy native wring cap')
        result=evidence(case='worn-prepared')
        for key in ('before','after'):result[0]['wornPrepared'][key]['items']['cancelled']['wetness']=0
        self.assertTrue(a.check_case(*result),'pending wetness baseline bounds remain strict')

    def test_fixture_final_gate_accepts_clamped_natural_worn_drying_only(self):
        lua=worn_alias_fixture()
        lua.execute(r'''
ids.case='worn-prepared';ids.source.kind='worn-prepared';ids.wornPrepared=true;ids.mode='toolkit'
local wetness=0;local cancelled=state.items.cancelled;local worn=true
for name,item in pairs(state.items)do
 ids.items[name].initial=100
 item.getWetness=function()return 10 end
 item.getUnequippedWeight=function()return .1 end;item.getEquippedWeight=function()return .03 end
end
cancelled.getWetness=function()return wetness end
player.getWornItem=function(_,slot)return worn and slot==cancelled:getBodyLocation()and cancelled or nil end
player.getWornItems=function()return{contains=function(_,item)return worn and item==cancelled end,
 size=function()return worn and 1 or 0 end,get=function(_,index)assert(index==0);return{getItem=function()return cancelled end,getLocation=function()return cancelled:getBodyLocation()end}end}end
player.getPrimaryHandItem=function()return nil end;player.getSecondaryHandItem=player.getPrimaryHandItem
player.getInventoryWeight=function()return 1 end
state.wearBaseline=F.snapshot(state)
for _,value in ipairs({0,.1,10,80,100})do wetness=value;assert(F.verify(state),'natural worn drying failed fixture completion')end
for _,value in ipairs({-1,100.001,0/0,math.huge})do wetness=value;assert(not F.verify(state),'invalid native wetness clamp was accepted')end
wetness=0;worn=false;assert(not F.verify(state),'cancelled garment lost its worn identity')
ids.mode='native';assert(not F.verify(state),'executed glove escaped native wring cap')
wetness=10;assert(F.verify(state),'native-off executed glove cap rejected')
''')

    def test_worn_setup_uses_recorded_native_boundaries_without_admission(self):
        for kind in ('sp','mp'):
            for mode in ('native','toolkit'):
                result=evidence(kind=kind,mode=mode,case='worn-prepared')
                for receipt in result[0]['wearSetup']:self.assertNotIn('admission',receipt)
                self.assertEqual([],a.check_case(*result))
        result=evidence(kind='sp',mode='native',case='worn-prepared')
        for snapshot in (result[0]['client'],result[0]['server'],result[3]):
            for event in snapshot['unequipTransitions']:
                event['item']['wetness']=77.66146850585938 if event['name']=='target'else 88.51947021484375
        self.assertEqual([],a.check_case(*result),'native worn drying before actual removal is independent of paid Wring proof')

    def test_native_wear_boundary_and_physical_removal_proofs_stay_strict(self):
        mutations=[
            lambda r:r['wearSetup'][0].update(name='cancelled'),
            lambda r:r['wearSetup'][0].update(events=r['wearSetup'][0]['events'][2:]),
            lambda r:r['wearSetup'][0]['events'][0]['state']['item']['counts'].update(root=0),
            lambda r:r['wearSetup'][0]['events'][0]['state']['item'].update(slot='base:socks'),
            lambda r:r['wearSetup'][0]['events'][0]['state'].update(inventoryWeight=999),
            lambda r:r['wearSetup'][0]['events'][0]['state']['equipment']['worn'].pop(0),
            lambda r:r['client']['unequipTransitions'][0]['item'].update(id=999),
            lambda r:r['client']['unequipTransitions'][0]['item']['counts'].update(root=0),
            lambda r:r['client']['unequipTransitions'][0]['item'].update(slotId=999),
            lambda r:r['client']['unequipTransitions'][0]['item'].update(wetness=-1),
            lambda r:r['client']['unequipTransitions'][0].update(inventoryWeight=r['input']['inventoryWeight']),
            lambda r:r['client']['unequipTransitions'].reverse(),
        ]
        for mutation in mutations:
            result=evidence(kind='sp',mode='native',case='worn-prepared');mutation(result[0])
            self.assertTrue(a.check_case(*result),mutation)
        result=evidence(kind='sp',case='worn-prepared');row=result[0];event=row['wearSetup'][0]['events'][0]['state'];spec=row['ids']['items']['target']
        event['item'].update(worn=True,slotId=spec['id']);event['equipment']['worn'].append(dict(slot=spec['bodyLocation'],id=spec['id'],type=spec['type']))
        event['equipment']['worn'].sort(key=lambda entry:(entry['slot'],entry['id']));event['inventoryWeight']-=spec['capacityWeight']-spec['equippedWeight']
        self.assertTrue(a.check_case(*result),'SP Wear physical slot effect belongs to native complete-finish')

    def test_host_client_removal_observes_monotonic_physical_prefixes(self):
        # Source-shaped packet aggregation control, not a captured Host qualification.
        result=evidence(kind='mp',mode='native',case='worn-prepared');row=result[0]
        for event in row['client']['unequipTransitions']:
            event['equipment']=copy.deepcopy(row['client']['equipment']);event['inventoryWeight']=row['client']['inventoryWeight']
        row['client']['unequipTransitions'].reverse()
        self.assertEqual([],a.check_case(*result),'client clothing packets may expose both removals together')
        row['client']['unequipTransitions'][0]['inventoryWeight']-=.07
        self.assertTrue(a.check_case(*result),'observed physical aggregate still requires exact native load')

    def test_worn_prepared_scarf_preserves_occupied_starter_socks(self):
        for kind in ('sp','mp'):
            for mode in ('native','toolkit'):
                result=evidence(kind=kind,mode=mode,case='worn-prepared');row=result[0]
                self.assertEqual([],a.check_case(*result))
                self.assertEqual(('Base.Scarf_White','base:scarf',.2),tuple(row['ids']['items']['target'][key]for key in ('type','bodyLocation','weight')))
                for phase in ('input','authorityBaseline','client','server'):
                    self.assertIn(dict(slot='base:socks',id=98,type='Base.Socks_Ankle'),row[phase]['equipment']['worn'])
                    self.assertEqual(98,row[phase]['items']['front']['slotId'])

    def test_prepared_slot_catalog_reports_occupants_and_native_exclusions(self):
        from lupa.lua51 import LuaRuntime
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.globals().fixture=str(PROJECT/'tests/native_queue/wring-clothing/shared/QueueWringClothing.lua')
        lua.execute(r'''
package.loaded.QueueEnergyPlacement={}
function getClassSimpleName(item)return item.class end
local F=dofile(fixture)
local function item(id,fullType,slot)
 return{class='Clothing',getID=function()return id end,getFullType=function()return fullType end,
 getBodyLocation=function()return slot end,getBloodClothingType=function()return{size=function()return 1 end}end}
end
local scarf=item(10,'Base.Scarf_White','base:scarf');local gloves=item(11,'Base.Gloves_LeatherGloves','base:hands')
local starter=item(98,'Base.Socks_Ankle','base:socks');local occupied,exclusive
local player={getWornItem=function(_,slot)return occupied and occupied:getBodyLocation()==slot and occupied or nil end,
 getBodyLocationGroup=function()return{getLocation=function(_,slot)return slot=='base:scarf'or slot=='base:hands'end,
 isMultiItem=function()return false end,isExclusive=function()return exclusive==true end}end,
 getWornItems=function()return{size=function()return 1 end,get=function()return{getLocation=function()return starter:getBodyLocation()end,getItem=function()return starter end}end}end,
 setWornItem=function()error('slot check mutated starter gear')end}
local items={target=scarf,cancelled=gloves};F.assertPreparedSlots(player,items)
occupied=item(77,'Base.Scarf_StripeBlackWhite','base:scarf')
local ok,error=pcall(F.assertPreparedSlots,player,items)
assert(not ok and error:find('requested=Base.Scarf_White',1,true)and error:find('slot=base:scarf',1,true)and error:find('occupant=Base.Scarf_StripeBlackWhite#77',1,true),'occupied diagnostic lost exact identity')
occupied=nil;exclusive=true;ok,error=pcall(F.assertPreparedSlots,player,items)
assert(not ok and error:find('exclusive slot',1,true)and error:find('Base.Socks_Ankle#98',1,true),'exclusive occupant was hidden')
exclusive=false;scarf.getBloodClothingType=function()return nil end
assert(not pcall(F.assertPreparedSlots,player,items),'unwettable cosmetic item became a natural clothing fixture')
''')

    def test_host_witness_diagnostics_keep_exact_receipt_private_and_never_rearm(self):
        from lupa.lua51 import LuaRuntime
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.globals().fixture=str(PROJECT/'tests/native_queue/wring-clothing/shared/QueueWringWitnessDiagnostics.lua')
        lua.execute(r'''
local function encode(value)
 if type(value)~='table'then return tostring(value)end
 local keys={};for key in pairs(value)do keys[#keys+1]=key end;table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local rows={};for _,key in ipairs(keys)do rows[#rows+1]=tostring(key)..'='..encode(value[key])end;return '{'..table.concat(rows,',')..'}'
end
package.loaded.QueueHealthEvents={encode=encode}
local locations={};local function role(file,line,callback)locations[callback]={file=file,line=line};return callback end
function getFilenameOfClosure(callback)return locations[callback]and locations[callback].file or 'test.lua'end
function getFirstLineOfClosure(callback)return locations[callback]and locations[callback].line or 1 end
local Proof={closure=function(callback,file)return getFilenameOfClosure(callback)==file end,
 matches=function(path)return path:find('ActionQueueAcknowledgements.lua',1,true)~=nil end}
package.loaded['PZSurvivorToolkit/SourceProof']=Proof
function isClient()return true end
function instanceof(value,class)return type(value)=='table'and value.class==class end
function getClassSimpleName(value)return value.class end
local worn,invalid,bootstrap=true,false,false
local actor={class='IsoPlayer'};local item={class='Clothing'};local root={};local queue={character=actor,queue={},toolkitOperationGeneration=0}
function root:getItemWithID(id)return id==10 and item or nil end
function actor:getInventory()return root end
function actor:getPlayerNum()return 0 end;function actor:getOnlineID()return 17 end;function actor:isDead()return false end
function actor:getPrimaryHandItem()return nil end;actor.getSecondaryHandItem=actor.getPrimaryHandItem
function actor:getInventoryWeight()return worn and 1 or 1.14 end
function actor:getWornItem(slot)return worn and slot=='base:scarf'and item or nil end
function actor:getWornItems()return{contains=function(_,value)return worn and value==item end}end
function item:getID()return 10 end;function item:getFullType()return 'Base.Scarf_White'end;function item:getBodyLocation()return 'base:scarf'end
function item:getContainer()return root end;function item:getAttachedSlot()return -1 end;function item:getWetness()return 90 end
function item:getActualWeight()return .2 end;item.getUnequippedWeight=item.getActualWeight;function item:getEquippedWeight()return .06 end
function queue:indexOf(action)for index,value in ipairs(self.queue)do if value==action then return index end end;return -1 end
function getPlayer()return actor end;function getSpecificPlayer()return actor end
ISTimedActionQueue={queues={[actor]=queue},getTimedActionQueue=function()return queue end}
local action={Type='ISUnequipAction',character=actor,item=item};local receipt={state='started',generation=0,transaction=7,kind='ISUnequipAction',token='SEALED-TOKEN-DO-NOT-LOG',seal=function()error('seal read')end}
local captures,observations=0,0;local Acks={}
Acks.capture=role('ActionQueueAcknowledgements.lua',120,function(value)assert(value==action);captures=captures+1;return receipt end)
Acks.observe=role('ActionQueueAcknowledgements.lua',159,function(value,exact)assert(value==action and exact==receipt);observations=observations+1;return not invalid and receipt.state or nil end)
Acks.reset=function()error('diagnostics reset receipt epoch')end
local Clothing={capacityFresh=role('ActionQueueClothing.lua',489,function(value)assert(value==queue)
 if not bootstrap then return false,'bootstrap:source'end
 if invalid then return false,'unresolved:receipt-invalid'end
 return true,'clean'
end),lookupSafe=role('ActionQueueClothing.lua',23,function(value)return value==action end),
 inspect=role('ActionQueueClothing.lua',222,function(value)assert(value==action);return not value.action and{edit={complete=true,capacity='external'}}or nil end),
 bindNative=function()error('diagnostics rebound native owner')end,installObserver=function()error('diagnostics rearmed witness')end,bindingsTrusted=function()return true end}
local Policy={matchesNative=role('ActionQueuePolicy.lua',544,function(value)return value==action end)}
local Lifecycle={};for _,name in ipairs({'registerObserver','started','begin','finish','flush','reset'})do Lifecycle[name]=role('ActionQueueLifecycle.lua',37,function()error('diagnostics invoked lifecycle '..name)end)end
ISUnequipAction={};for _,name in ipairs({'new','isValid','start','update','perform','stop','complete'})do ISUnequipAction[name]=role('ISUnequipAction.lua',1,function()error('diagnostics invoked native callback '..name)end)end
ISWearClothing={};for _,name in ipairs({'new','isValid','start','update','perform','stop','complete'})do ISWearClothing[name]=role('ISWearClothing.lua',1,function()error('diagnostics invoked Wear callback '..name)end)end
PZSurvivorToolkit={ActionQueueClothing=Clothing,ActionQueuePolicy=Policy,ActionQueueAcknowledgements=Acks,ActionQueueLifecycle=Lifecycle}
local rows={};local forbidden={[receipt]=true,[action]=true,[actor]=true,[item]=true,[root]=true,[queue]=true}
local function scalarSummary(value)
 assert(not forbidden[value],'authority handle leaked')
 if type(value)=='table'then for key,child in pairs(value)do assert(type(key)=='string'or type(key)=='number');scalarSummary(child)end
 else assert(type(value)=='boolean'or type(value)=='number'or type(value)=='string','non-scalar diagnostic value')end
end
local D=dofile(fixture);D.configure(function(value)scalarSummary(value);assert(not encode(value):find('SEALED-TOKEN',1,true));rows[#rows+1]=value end,function()return 'worn-prepared','running'end)
D.setup();assert(rows[1].fresh==false and rows[1].reason=='bootstrap:source'and rows[1].sourceChecks[1].checksumMatch==false)
for _,entry in ipairs(rows[1].roles)do assert(not entry.file:find('/',1,true)and entry.ownerSame and entry.readerSame)end
bootstrap=true;D.freshness('before-producers');D.before(action)
assert(rows[#rows].classification.pendingEditEligible and rows[#rows].physical.nativeAllocated==false)
queue.current=action;queue.queue={action};D.started(action) -- deliberately no main-fixture track table
local sawStart=false;for _,row in ipairs(rows)do if row.point=='unequip-start'then sawStart=true;assert(row.tracked==false and row.classification.matchesNative and row.classification.lookupSafe)end end;assert(sawStart)
action.action={class='LuaTimedActionNew'};action.toolkitNativeTransaction=7;action.toolkitNativeKind='ISUnequipAction'
assert(D.begin(action,'perform')==nil,'diagnostics accepted a production Lifecycle phase');assert(captures==1 and rows[#rows].capturePresent and rows[#rows].ackState=='started')
D.finish(action,'perform',true);receipt.state='completed';queue.current=nil;queue.queue={};D.poll()
assert(rows[#rows].ackState=='completed'and rows[#rows].physical.worn)
worn=false;D.poll();assert(rows[#rows].ackState=='completed'and not rows[#rows].physical.worn)
invalid=true;D.poll();assert(rows[#rows].ackState==false and rows[#rows].recordState=='completed'and rows[#rows].nativeSame and rows[#rows].queueSame)
D.finalWait();local final=rows[#rows];assert(final.point=='final-receipt'and final.ackState==false)
local count=#rows;D.poll();D.finalWait();assert(#rows==count,'unchanged witness polling flooded logs')
local savedObserve=Acks.observe;Acks.observe=function()error('changed reader was invoked')end;D.poll();assert(rows[#rows].observeReaderSame==false)
assert(captures==1 and observations>1,'diagnostics recaptured a revoked receipt')
assert(D.receipt(action).ackState==false,'receipt summary trusted a replaced reader')
Acks.observe=savedObserve;invalid=false;worn=true;action.Type='ISWearClothing';action.toolkitNativeKind='ISWearClothing';receipt.kind='ISWearClothing'
D.started(action,false);assert(rows[#rows].point=='wear-start'and rows[#rows].tracked==false)
assert(D.begin(action,'perform')==nil,'Wear diagnostics accepted a production phase')
local summary=D.receipt(action);scalarSummary(summary)
assert(captures==2 and summary.capturePresent and summary.ackState=='completed'and summary.kind=='ISWearClothing')
assert(summary.nativeSame and summary.itemSame and summary.canonicalRoot and summary.rootOwned and summary.worn and summary.slotSame and summary.slotId==10)
''')
        source=(PROJECT/'tests/native_queue/wring-clothing/shared/QueueWringWitnessDiagnostics.lua').read_text()
        for call in ('.installObserver(','.bindNative(','.forceComplete(','.forceStop(','.reset('):self.assertNotIn(call,source)
        client=(PROJECT/'tests/native_queue/wring-clothing/client/ZZWringClothing.lua').read_text()
        front=client[client.index("elseif phase=='front'and tracks[state.frontAction].progress then"):]
        self.assertLess(front.index("Witness.freshness('before-producers')"),front.index("produce('cancelled'"))
        self.assertIn("raw('HOST_WITNESS',value)",client)

    def test_source_pinned_scarf_and_gloves_are_naturally_wet_clothing(self):
        game=os.environ.get('PZ_GAME')
        if not game:self.skipTest('PZ_GAME required for installed natural clothing catalog source')
        a.audit_native(game)
        source=(Path(game)/'media/scripts/generated/items/clothing.txt').read_text()
        for kind,slot,blood,fabric,weight in (('Scarf_White','scarf','Neck','Cotton','0.2'),('Gloves_LeatherGloves','hands','Hands','Leather','0.1')):
            block=source.split('    item '+kind+'\n',1)[1].split('}',1)[0]
            for field,value in (('ItemType','base:clothing'),('BodyLocation','base:'+slot),('BloodLocation',blood),('FabricType',fabric),('Weight',weight)):
                self.assertRegex(block,field+r'\s*=\s*'+value.replace('.',r'\.')+r'\s*,')
            self.assertNotIn('Cosmetic = true',block)
        client=(Path(game)/'media/lua/client/ISUI/ISInventoryPaneContextMenu.lua').read_text()
        self.assertIn('tests.clothing:getWetness() > 15',client)

    def test_worn_prepared_requires_final_native_capacity_freshness(self):
        for kind in ('sp','mp'):
            for mode in ('native','toolkit'):
                for value in (False, None, 1):
                    result=evidence(kind=kind,mode=mode,case='worn-prepared')
                    result[0]['wornPrepared']['capacityFresh']=value
                    self.assertTrue(a.check_case(*result))
                result=evidence(kind=kind,mode=mode,case='worn-prepared')
                del result[0]['wornPrepared']['capacityFresh']
                self.assertTrue(a.check_case(*result))
        client=(PROJECT/'tests/native_queue/wring-clothing/client/ZZWringClothing.lua').read_text()
        final=client[client.index("elseif phase=='verified'and receipt then"):]
        self.assertLess(final.index('F.verify(state)'),final.index('clothing.capacityFresh(queue())~=true'))
        self.assertIn("diagnostic('native clothing capacity freshness pending');return",final)
        self.assertNotIn('clothing.capacityFresh=',client)

    def test_worn_prepared_rejects_slot_effect_callback_or_group_forgery(self):
        mutations=[
            lambda r:r['client']['equipment']['worn'].clear(),
            lambda r:r['wornPrepared']['moves'][0].update(selected=r['commands'][4]['actionRef']),
            lambda r:r['wornPrepared']['target']['descriptor'].update(setsWorn=True),
            lambda r:r['commands'][1].update(admission={}),
            lambda r:r['commands'][3].update(callbacksUntouched=False),
            lambda r:r['commands'][3].update(operation=4),
            lambda r:r['wornPrepared']['target']['descriptor'].update(equipmentWriter=1),
            lambda r:r['wearSetup'][0].update(events=[]),
            lambda r:r['wearSetup'][0].update(callbacksUntouched=False),
            lambda r:r['commands'][3].update(cartsGuard=False),
            lambda r:r['commands'][3]['events'].clear(),
            lambda r:r['commands'][4]['events'][0]['state']['item'].update(worn=True),
            lambda r:r['client'].update(unequipTransitions=[]),
            lambda r:r['client']['unequipTransitions'][0]['item'].update(id=999),
            lambda r:r['client'].update(inventoryWeight=1),
            lambda r:r['client']['items']['cancelled'].update(worn=False),
            lambda r:r['wearSetup'][1].update(item=r['ids']['items']['target']['id']),
            lambda r:r['authorityBaseline']['equipment']['worn'].clear(),
        ]
        for mutation in mutations:
            result=evidence(case='worn-prepared');mutation(result[0]);self.assertTrue(a.check_case(*result),mutation)
        result=evidence(case='worn-prepared');result[0]['server']['unequipTransitions']=[];result[3]['unequipTransitions']=[]
        self.assertTrue(a.check_case(*result),'server physical transition must be observed independently')

    def test_authority_receipts_require_all_grouped_cases(self):
        selection = dict(kind='mp', mode='toolkit', cases=list(a.CASES)); cases = selection['cases']
        client = ['[QUEUE_CHECK] ' + json.dumps(dict(suite='wring-clothing', event='setup', cases=cases, queueEnabled=True, nativeDurations=True, adapterInstalled=True))]
        server = []
        for case in cases:
            row, _, ids, verified = evidence(case=case)
            row.update(suite='wring-clothing', event='case', id=case, actor='client1', kind='mp', mode='toolkit')
            client += [a.PREFIX + 'CLIENT_PLACEMENT ' + json.dumps(dict(case=case, proof=row['clientPlacement'])), '[QUEUE_CHECK] ' + json.dumps(row)]
            server.append(a.PREFIX + 'PREPARED ' + json.dumps(ids))
            if ids.get('nativeWearSetup'): server.append(a.PREFIX + 'WEAR_BASELINE ' + json.dumps(row['authorityBaseline']))
            server.append(a.PREFIX + 'VERIFIED ' + json.dumps(verified))
        client += ['[QUEUE_CHECK] ' + json.dumps(dict(suite='wring-clothing', event='complete', cases=cases, performed=len(cases), failed=0, skipped=0)),
                   a.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=cases))]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); (root / 'client1-launch.log').write_text('\n'.join(client)); (root / 'server-launch.log').write_text('\n'.join(server))
            self.assertEqual([], a.verify(root, selection, {})['issues'])
            false_setup = client.copy(); false_setup[0] = false_setup[0].replace('"adapterInstalled": true', '"adapterInstalled": false')
            (root / 'client1-launch.log').write_text('\n'.join(false_setup))
            self.assertTrue(a.verify(root, selection, {})['issues'])

            (root / 'client1-launch.log').write_text('\n'.join(client))
            (root / 'server-launch.log').write_text('\n'.join(server[:-1]))
            self.assertTrue(a.verify(root, selection, {})['issues'])

    def test_host_native_wear_setup_requires_exact_input_and_authority_baseline(self):
        for case in ('worn', 'worn-bag'):
            result = evidence(case=case)
            self.assertEqual([], a.check_case(*result, copy.deepcopy(result[0]['authorityBaseline'])))
            result = evidence(case=case); result[0]['wearSetup']['duration'] = 1
            self.assertTrue(a.check_case(*result))
            result = evidence(case=case); result[0]['wearSetup']['progress'] = False
            self.assertTrue(a.check_case(*result))
            result = evidence(case=case); result[0]['wearSetup']['item'] += 100
            self.assertTrue(a.check_case(*result))
            result = evidence(case=case); result[0]['authorityBaseline']['items']['target']['wetness'] = 10
            self.assertTrue(a.check_case(*result))
            result = evidence(case=case); baseline = copy.deepcopy(result[0]['authorityBaseline']); baseline['items']['target']['counts']['source'] = 0
            self.assertTrue(a.check_case(*result, baseline))
            result = evidence(case=case); del result[0]['authorityBaseline']
            self.assertTrue(a.check_case(*result))


    def test_prepared_wait_diagnoses_same_id_alias_without_accepting_it(self):
        lua = worn_alias_fixture()
        lua.execute("player:setWornItem(canonical:getBodyLocation(),canonical);assert(F.resolve(player,ids));assert(F.wearBaseline(state))")

    def test_host_bag_provisional_resolution_never_weakens_final_worn_identity(self):
        lua = worn_alias_fixture()
        lua.execute(r'''
local old=root:getItems();local front,tail,cancelled=old:get(0),old:get(2),old:get(3)
local function list(values)return{size=function()return #values end,get=function(_,i)return values[i+1]end}end
local source={getItems=function()return list({canonical,cancelled})end}
local bag={class='InventoryContainer',getID=function()return 10 end,getFullType=function()return 'Base.Bag_Military'end,
 getContainer=function()return root end,getItemContainer=function()return source end,canBeEquipped=function()return 'Back'end}
local worn
function root:getItems()return list({front,tail,bag})end
function root:getItemById(id)if id==10 then return bag end end
canonical.getContainer=function()return source end
cancelled.getContainer=function()return source end
player.getWornItems=function()return{contains=function(_,value)return value==worn end,
 getItemById=function(_,id)return worn and worn:getID()==id and worn or nil end}end
player.getWornItem=function(_,slot)return slot=='Back'and worn or nil end
ids.case='worn-bag';ids.source={kind='worn-bag',bag=10,world=false}
assert(not F.resolve(player,ids),'unworn bag became ready baseline')
local s=assert(F.resolve(player,ids,true));assert(not F.wearBaseline(s))
worn={getID=function()return 10 end};assert(not F.resolve(player,ids),'same-ID bag alias accepted')
local diagnostic=F.preparedDiagnostic(player,ids)
assert(diagnostic.bag.slotId==10 and not diagnostic.bag.slotSame and not diagnostic.bag.canonicalWorn)
worn=bag;assert(F.resolve(player,ids));assert(F.wearBaseline(s))
worn=nil;assert(not F.resolve(player,ids)and not F.wearBaseline(s))
assert(not pcall(F.verify,s),'nativeWearSetup permanently relaxed final canonical worn bag identity')
''')

    def test_native_wear_source_rebinds_and_completes_exact_root_item(self):
        game = os.environ.get('PZ_GAME')
        if not game: self.skipTest('PZ_GAME required for installed native wear source regression')
        native = Path(game) / 'media/lua/shared/TimedActions/ISWearClothing.lua'
        self.assertEqual(a.NATIVE_CRC['media/lua/shared/TimedActions/ISWearClothing.lua'], zlib.crc32(native.read_bytes()))
        lua = worn_alias_fixture(); lua.globals().nativeWearSource = str(native)
        lua.execute(r'''
require=function()end
ISBaseTimedAction={derive=function(_,name)local cls={Type=name};cls.__index=cls;return cls end}
ItemTag={WEARABLE='wearable',REPLACE_PRIMARY='primary'}
function isClient()return true end
function getText(value)return value end
dofile(nativeWearSource)
local action=setmetatable({item=proxy,character=player,setActionAnim=function()end,setAnimVariable=function()end,
 forceComplete=function()error('same-ID proxy must not force-complete canonical wear')end},ISWearClothing)
action:start();assert(action.item==canonical,'native wear start did not rebind exact root item')
assert(action:complete(),'native wear complete failed')
assert(player:getWornItem(canonical:getBodyLocation())==canonical and F.resolve(player,ids))
assert(F.wearBaseline(state),'native canonical wear did not satisfy strict baseline')
''')

    def test_native_unequip_complete_emits_exact_readonly_slot_transition(self):
        game = os.environ.get('PZ_GAME')
        if not game: self.skipTest('PZ_GAME required for installed native unequip regression')
        native = Path(game) / 'media/lua/shared/TimedActions/ISUnequipAction.lua'
        self.assertEqual(a.NATIVE_CRC['media/lua/shared/TimedActions/ISUnequipAction.lua'], zlib.crc32(native.read_bytes()))
        lua = worn_alias_fixture(); lua.globals().nativeUnequipSource = str(native)
        lua.execute(r'''
require=function()end
ISBaseTimedAction={derive=function(self,name)local cls={Type=name};cls.__index=cls;return setmetatable(cls,{__index=self})end,
 new=function(self,character)return setmetatable({character=character},self)end}
ISWearClothing={isStopOnWalk=function()return false end}
function isServer()return false end;function isClient()return false end
function getPlayerHotbar()return nil end
function isForceDropHeavyItem()return false end
function sendEquip()end
player.getPlayerNum=function()return 0 end;player.isTimedActionInstant=function()return false end
player.getPrimaryHandItem=function()return nil end;player.getSecondaryHandItem=player.getPrimaryHandItem
player.removeWornItem=function(self,item)assert(item==canonical);self:setWornItem(item:getBodyLocation(),nil)end
player.getInventoryWeight=function(self)return self:getWornItem(canonical:getBodyLocation())and .3 or 1 end
for _,item in pairs(state.items)do item.getUnequippedWeight=function()return .1 end;item.getEquippedWeight=function()return .03 end end
local oldWorn=player.getWornItems
player.getWornItems=function(self)
 local worn=oldWorn(self);worn.size=function()return self:getWornItem(canonical:getBodyLocation())and 1 or 0 end
 worn.get=function(_,index)assert(index==0);return{getItem=function()return canonical end,getLocation=function()return canonical:getBodyLocation()end}end
 return worn
end
ids.case='worn-prepared';ids.source.kind='worn-prepared';ids.wornPrepared=true
player:setWornItem(canonical:getBodyLocation(),canonical)
state.wearBaseline=F.snapshot(state)
local saved=F.snapshot(state);assert(saved.items.target.worn and saved.equipment.worn[1].id==canonical:getID())
function triggerEvent(event,actor)assert(event=='OnClothingUpdated'and actor==player);F.clothingTransition(state)end
dofile(nativeUnequipSource)
local complete=ISUnequipAction.complete;local action=ISUnequipAction:new(player,canonical,50)
assert(action.item==canonical and action.maxTime==50 and F.snapshot(state).items.target.worn,'constructor caused effect')
assert(action:complete()and ISUnequipAction.complete==complete,'native complete was replaced')
local final=F.snapshot(state);assert(not final.items.target.worn and final.items.target.slotId==false and #final.equipment.worn==0)
assert(#state.unequipTransitions==1,'physical transition must start from a genuinely worn baseline')
local target;for _,event in ipairs(state.unequipTransitions)do if event.name=='target'then target=event end end
assert(target and target.item.id==canonical:getID()and target.item.counts.root==1 and not target.item.worn and #target.equipment.worn==0)
triggerEvent('OnClothingUpdated',player);assert(#state.unequipTransitions==1,'duplicate native event created duplicate transitions')
''')

    def test_native_source_audit_fails_before_launch_on_drift(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp); data = b'native source fixture'
            paths = {name: zlib.crc32(data) for name in a.NATIVE_CRC}
            for relative in paths:
                path = root / relative; path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
            with patch.object(a, 'NATIVE_CRC', paths):
                self.assertEqual(paths, a.audit_native(root))
                (root / next(iter(paths))).write_bytes(b'changed native method')
                with self.assertRaises(ValueError): a.audit_native(root)

    def test_report_verifier_has_explicit_separate_source_roles(self):
        from queue_checks import provenance
        selection = {'suite': 'wring-clothing'}
        declared = {path.resolve() for path in provenance.verifier_sources(PROJECT, selection)}
        verifier = Path(a.__file__).with_name('wring_clothing_verifier.py').resolve()
        self.assertIn(verifier, declared)
        self.assertIn(Path(__file__).resolve(), declared)
        inputs = {path.resolve() for path in a.sources(PROJECT, selection)} | declared | {Path(a.__file__).resolve()}
        manifest = {str(path): provenance.digest(path) for path in inputs}
        roles = provenance.source_roles(PROJECT, selection, manifest)
        self.assertEqual({str(path) for path in declared}, set(roles['verifier']))
        self.assertIn(str(Path(a.__file__).resolve()), roles['runtime'])
        self.assertIn(str(PROJECT / 'tests/native_queue/wring-clothing/client/ZZWringClothing.lua'), roles['runtime'])
        self.assertNotIn(str(verifier), roles['runtime'])
        sentinel = object()
        with patch('queue_checks.provenance.run_verifier', return_value=sentinel) as run:
            self.assertIs(sentinel, a.verify(Path('unused-evidence'), selection, {}))
        self.assertEqual(verifier, Path(run.call_args.args[0]).resolve())
        self.assertEqual('queue_checks.adapters', run.call_args.args[1])

    def test_fixture_native_callbacks_and_dry_baseline(self):
        root = PROJECT / 'tests/native_queue/wring-clothing'
        shared = (root / 'shared/QueueWringClothing.lua').read_text()
        client = (root / 'client/ZZWringClothing.lua').read_text()
        self.assertIn('precipitation:setEnableAdmin(true)', shared)
        self.assertEqual(shared.count('item:setWetness('), 1)
        self.assertIn('item:setWetness(100)', shared)
        self.assertIn("nativeShoe=location=='Shoes'", shared)
        self.assertIn('player:getInventoryWeight()<player:getMaxWeight()', shared)
        self.assertIn('if item:getContainer()==root then sendAddItemToContainer(root,item)end', shared)
        self.assertIn('Ops.run(ISInventoryPaneContextMenu.onWringClothing', client)
        self.assertNotIn('toolkitQueueOperation=', client)
        for name in ('complete', 'perform', 'getDuration', 'isValid'):
            self.assertNotIn('ISWringClothing.' + name + '=', client)
        self.assertNotRegex(client, r'\.maxTime\s*=(?!=)')
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        compile_ = lua.eval('function(source) local f,e=loadstring(source); assert(f,e) end')
        for file in root.rglob('*.lua'):
            compile_(file.read_text())

    def test_unique_canonical_clothing_handle_replacement_preserves_identity(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        source = PROJECT / 'tests/native_queue/wring-clothing/shared/QueueWringClothing.lua'
        script = r'''
package.loaded.QueueEnergyPlacement={}
function instanceof(value,kind)return value.class==kind end
function getClassSimpleName(value)return value.class end
local F=dofile(arg[1])
local values={};local root={}
local socks=setmetatable({class='ItemBodyLocation'},{__tostring=function()return 'base:socks'end})
local function item(id,kind)
 return {class='Clothing',getID=function()return id end,getFullType=function()return kind end,
 getWetness=function()return 99 end,getActualWeight=function()return .1 end,getContainer=function()return root end,
 getBodyLocation=function()return socks end}
end
function root:getItems()return{size=function()return #values end,get=function(_,i)return values[i+1]end}end
local player={getInventory=function()return root end,getWornItems=function()return{contains=function()return false end}end}
local s={player=player,source=root,items={},ids={case='root',source={kind='root',bag=false,world=false},items={}}}
for i,name in ipairs(F.names)do
 s.ids.items[name]={id=i,type='Base.Socks_Ankle',bodyLocation='base:socks',bodyLocationClass='ItemBodyLocation',nativeShoe=false,cap=10}
 s.items[name]=item(i,'Base.Socks_Ankle');values[i]=item(i,'Base.Socks_Ankle')
end
local snapshot=F.snapshot(s)
for i,name in ipairs(F.names)do
 assert(s.items[name]==values[i]and snapshot.items[name].counts.root==1 and snapshot.items[name].counts.source==1)
end
values[5]=item(2,'Base.Socks_Ankle');assert(not pcall(F.snapshot,s),'duplicate ID accepted');values[5]=nil
values[2]=item(2,'Base.Shoes_FlipFlop');assert(not pcall(F.snapshot,s),'wrong-type replacement accepted')
values[2]=item(200,'Base.Socks_Ankle');assert(not pcall(F.snapshot,s),'unowned replacement accepted')
'''
        lua.globals().arg = lua.table_from([str(source)])
        lua.execute(script)

    def test_carried_fixture_keeps_cancelled_source_and_requires_exact_native_return(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().fixture = str(PROJECT / 'tests/native_queue/wring-clothing/shared/QueueWringClothing.lua')
        lua.execute(r'''
package.loaded.QueueEnergyPlacement={atCentered=function()return true end}
function instanceof(value,kind)return value.class==kind end
function getClassSimpleName(value)return value.class end
local F=dofile(fixture)
local values,contents={},{};local root,source={},{}
local function list(items)return{size=function()return #items end,get=function(_,i)return items[i+1]end}end
function root:getItems()return list(values)end
function source:getItems()return list(contents)end
local location=setmetatable({class='ItemBodyLocation'},{__tostring=function()return 'base:socks'end})
local bag={class='InventoryContainer',getID=function()return 20 end,getFullType=function()return 'Base.Bag_Military'end,
 getContainer=function()return root end,getItemContainer=function()return source end}
values[1]=bag
function root:getItemById(id)if id==20 then return bag end end
local player={getInventory=function()return root end,getWornItems=function()return{contains=function(_,item)return item==bag end}end}
local ids={case='worn-bag',mode='toolkit',preparedGroups=true,origin={},source={kind='worn-bag',bag=20,world=false},items={}}
local state={player=player,source=source,bag=bag,items={},ids=ids}
for index,name in ipairs(F.names)do
 local owner=(name=='target'or name=='cancelled')and source or root
 local item={class='Clothing',id=index,wet=99,owner=owner}
 function item:getID()return self.id end
 function item:getFullType()return 'Base.Socks_Ankle'end
 function item:getContainer()return self.owner end
 function item:getWetness()return self.wet end
 function item:getActualWeight()return .1 end
 function item:getWeight()return .1+self.wet/100*.025 end
 function item:getUnequippedWeight()return .1 end
 function item:getBodyLocation()return location end
 local spec=F.nativeWetnessContract(item);spec.id=index;spec.type=item:getFullType();spec.weight=.1;spec.wetWeight=.125;spec.capacityWeight=.1
 ids.items[name]=spec;state.items[name]=item
 local collection=owner==source and contents or values;collection[#collection+1]=item
end
assert(F.resolve(player,ids),'carried source canonical resolution failed')
local input=F.snapshot(state)
assert(input.items.target.counts.root==0 and input.items.cancelled.counts.source==1)
for _,name in ipairs({'front','target','tail'})do state.items[name].wet=10 end
local target=state.items.target
for index,item in ipairs(contents)do if item==target then table.remove(contents,index);break end end
values[#values+1]=target;target.owner=root
assert(not F.verify(state),'body root state incorrectly credited a future return')
assert(F.snapshot(state).items.target.counts.root==1 and state.items.cancelled.owner==source and state.items.cancelled.wet==99)
table.remove(values);contents[#contents+1]=target;target.owner=source
assert(F.verify(state),'exact native/P4 return source was not accepted')
ids.mode='native';assert(not F.verify(state),'disabled control omitted its uncancelled body effect')
state.items.cancelled.wet=10;assert(F.verify(state))
contents[#contents+1]=target;assert(not pcall(F.snapshot,state),'duplicate returned identity accepted')
''')

    def test_p4_return_observation_refreshes_native_members_merged_after_start(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().fixture = str(PROJECT / 'tests/native_queue/wring-clothing/shared/QueueWringClothing.lua')
        lua.execute(r'''
package.loaded.QueueEnergyPlacement={}
local F=dofile(fixture)
local function item(id,kind)return{getID=function()return id end,getFullType=function()return kind end}end
local first,second=item(10,'Base.Socks_Ankle'),item(11,'Base.Socks_Ankle')
local action={queueList={{items={first}}}};local original=action.queueList
local observed=F.returnMembers(action,{})
assert(#observed==1 and observed[1].id==10)
-- Native add/merge may extend a currently running transfer before its perform.
action.queueList[2]={items={second}};F.returnMembers(action,observed)
assert(#observed==2 and observed[2].id==11 and action.queueList==original and #action.queueList==2)
action.queueList[1]=nil;action.queueList={{items={second}}};F.returnMembers(action,observed)
assert(#observed==2,'completed native member evidence was lost')
action.queueList={{items={item(10,'Base.Shoes_FlipFlop')}}}
assert(not pcall(F.returnMembers,action,observed),'changed native return identity/type accepted')
''')

    def test_enum_valued_shoe_location_preserves_native_string_predicate(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().fixture = str(PROJECT / 'tests/native_queue/wring-clothing/shared/QueueWringClothing.lua')
        lua.execute(r'''
package.loaded.QueueEnergyPlacement={}
function getClassSimpleName(value)return type(value)=='string'and 'String'or value.class end
local F=dofile(fixture)
local location=setmetatable({class='ItemBodyLocation'},{__tostring=function()return 'base:shoes'end})
local actual=F.nativeWetnessContract({getBodyLocation=function()return location end})
assert(actual.bodyLocation=='base:shoes'and actual.bodyLocationClass=='ItemBodyLocation')
assert(actual.nativeShoe==false and actual.cap==10,'enum-valued shoes must retain the native false string branch')
local legacy=F.nativeWetnessContract({getBodyLocation=function()return 'Shoes'end})
assert(legacy.nativeShoe==true and legacy.cap==60,'fixture must report the native expression, not force a cap')
''')
        result = evidence(case='world')
        for spec in (result[0]['ids']['items']['target'], result[2]['items']['target']):
            spec.update(nativeShoe=True, cap=60)
        self.assertTrue(a.check_case(*result), 'unobserved string-valued shoe branch must not pass')


if __name__ == '__main__':
    unittest.main()
