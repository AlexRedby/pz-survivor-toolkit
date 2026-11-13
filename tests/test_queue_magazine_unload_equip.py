"""Equip group selection, sealed lifecycle/identity evidence, and denial controls."""
import copy
import json
import tempfile
from pathlib import Path
import sys
import unittest

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / 'tools'))
from queue_checks.adapters import magazine_unload as adapter
from queue_checks.adapters import magazine_unload_equip_verifier as verifier
from tests.test_queue_wring_clothing import placement_proof


def evidence(segment='reorder-two', kind='sp', mode='toolkit'):
    prepared = segment in verifier.PREPARED_SEGMENTS
    selection = dict(kind=kind, mode=mode, **({'options': dict(equip_prepared=True)} if prepared else {}))
    editing = mode == 'toolkit'
    types = dict(front='Base.BookCarpentry1', tail='Base.BookFirstAid1', a='Base.Hammer' if segment == 'component-guard' else 'Base.Nails', b='Base.Screwdriver', c='Base.Screwdriver', bag='Base.Bag_Schoolbag', marker='Base.Nails')
    if segment in ('dependent', 'capacity') or prepared: types['nested'] = 'Base.Plank' if segment == 'capacity' else 'Base.Pencil'
    if segment == 'capacity': types['heldBag'] = 'Base.Bag_Schoolbag'
    items = {}
    for index, (name, full_type) in enumerate(types.items(), 10):
        class_name = 'Literature' if name in ('front', 'tail') else 'InventoryContainer' if name in ('bag', 'heldBag') else 'HandWeapon' if name in ('b', 'c', 'nested') or name == 'a' and segment == 'component-guard' else 'ComboItem'
        items[name] = dict(id=index, type=full_type, **{'class': class_name})
        if name in ('front', 'tail'): items[name]['pages'] = 100
    inventory = []
    for name, spec in items.items():
        path = [items['bag']['id']] if name == 'marker' or name == 'nested' and (segment == 'dependent' or prepared) else [items['heldBag']['id']] if name == 'nested' else []
        inventory.append(dict(id=spec['id'], type=spec['type'], path=path, condition=10, count=5 if spec['type'] == 'Base.Nails' else 1, uses=1, **{'class': spec['class']}))
    origin = dict(x=11, y=20, z=0)
    ids = dict(case='equip-edit', segment=segment, mode=mode, kind=kind, origin=origin, items=items,
               placementProof=placement_proof(origin, 'replica' if kind == 'mp' else 'local'), inventory=inventory)
    def snapshot(final=False):
        rows = copy.deepcopy(inventory)
        if final and prepared and not(editing and segment in ('prepared-cancel-fetch', 'prepared-cancel-body')):
            next(row for row in rows if row['id'] == items['nested']['id'])['path'] = []
        books = {name: dict(id=items[name]['id'], present=True, root=True, total=100, pages=100 if final else 99, characterPages=100 if final else 99) for name in ('front', 'tail')}
        return dict(case='equip-edit', segment=segment, inventory=rows, books=books, backpack=True,
                    hands=verifier.expected_hands(ids, editing) if final else dict(primary=False, secondary=False))
    source = ['front', 'equip-a', 'equip-b'] + (['equip-c'] if segment in ('reorder-three', 'cancel') else []) + ['tail']
    if segment == 'dependent': source = ['front', 'transfer', 'equip-nested', 'tail']
    if segment == 'capacity': source = ['front', 'equip-bag', 'transfer', 'tail']
    if prepared:
        group = (['prepared-approach'] if editing else []) + ['prepared-fetch', 'prepared-equip']
        source = ['front'] + (group + ['equip-dependent'] if segment == 'prepared-dependent' else ['equip-b'] + group) + ['tail']
    order = list(source)
    if editing and segment == 'reorder-two': order = ['front', 'equip-b', 'equip-a', 'tail']
    elif editing and segment == 'reorder-three': order = ['front', 'equip-c', 'equip-a', 'equip-b', 'tail']
    elif editing and segment == 'cancel': order.remove('equip-c')
    elif editing and segment == 'prepared-move': order = ['front'] + group + ['equip-b', 'tail']
    elif editing and segment in ('prepared-cancel-fetch', 'prepared-cancel-body'): order = [name for name in source if name not in group]
    commands = []
    for name in source:
        owned = name == 'prepared-approach'
        equip = name.startswith('equip-') or name == 'prepared-equip'
        transfer = name in ('transfer', 'prepared-fetch')
        item_name = name.removeprefix('equip-')
        if name == 'transfer': item_name = 'nested'
        if name == 'equip-bag': item_name = 'heldBag'
        if name in ('prepared-fetch', 'prepared-equip', 'equip-dependent'): item_name = 'nested'
        row = dict(name=name, type='ISQueueActionsAction' if owned else 'ISEquipWeaponAction' if equip else 'ISInventoryTransferAction' if transfer else 'ISReadABook',
                   item=False if owned else items[item_name]['id'], duration=-1 if owned else 50 if equip else -1 if transfer and kind == 'mp' else 100, callbacksUntouched=True,
                   lifecycle=[], started=name in order, progress=name in order and not owned)
        if owned: row.update(ownedApproach=True, paidProgress=False)
        if prepared and name in group: row['operation'] = 1
        if prepared: row['callbackConstructor'] = owned_observation() if owned else callback_observation()
        if equip:
            primary = name == 'prepared-equip' or name == 'equip-b' and segment != 'prepared-move' if prepared else not (segment == 'reorder-three' and name in ('equip-a', 'equip-c') or segment == 'cancel' and name == 'equip-b')
            row.update(primary=primary, twoHands=False, maxTimeInit=50)
        if name not in order: row.update(cancelled=True, started=False, progress=False)
        commands.append(row)
    serial = 0; hands = dict(primary=False, secondary=False); transferred = False
    for episode, name in enumerate(order, 1):
        command = next(value for value in commands if value['name'] == name)
        events = [('admission', False), ('begin', 'perform'), ('finish', 'perform')]
        if kind == 'sp' and name != 'prepared-approach': events += [('begin', 'complete'), ('finish', 'complete')]
        for event, phase in events:
            serial += 1
            if command['type'] == 'ISInventoryTransferAction' and event == 'finish' and phase == ('perform' if kind == 'mp' else 'complete'): transferred = True
            if command['type'] == 'ISEquipWeaponAction' and event == 'finish' and phase == ('perform' if kind == 'mp' else 'complete'): hands['primary' if command['primary'] else 'secondary'] = command['item']
            item_name = name.removeprefix('equip-')
            if name == 'transfer': item_name = 'nested'
            if name == 'equip-bag': item_name = 'heldBag'
            if name in ('prepared-fetch', 'prepared-equip', 'equip-dependent'): item_name = 'nested'
            nested = item_name == 'nested' and not transferred
            location = False if name == 'prepared-approach' else dict(root=not nested, containerPresent=True, owner=items['bag' if segment == 'dependent' or prepared else 'heldBag']['id'] if nested else False)
            receipt = dict(sequence=serial, event=event, phase=phase, succeeded=event == 'finish',
                nativeEpisode=episode, nativeClass='LuaTimedActionNew', hands=copy.deepcopy(hands), itemLocation=location)
            if prepared:
                receipt['callbackObservation'] = owned_observation() if name == 'prepared-approach' else callback_observation()
                if name != 'prepared-approach': receipt['itemIdentity'] = dict(id=command['item'], type=items[item_name]['type'], **{'class': items[item_name]['class']}, canonicalRoot=not nested)
            command['lifecycle'].append(receipt)
    edits = []
    if mode == 'toolkit':
        names = ['reorder'] if segment.startswith('reorder-') else ['cancel'] if segment == 'cancel' else ['unavailable-input', 'dependent-transfer'] if segment == 'dependent' else ['component-reorder', 'component-cancel'] if segment == 'component-guard' else ['capacity-transfer', 'capacity-cancel']
        if prepared: names = ['prepared-reorder'] if segment == 'prepared-move' else ['dependent-prepared-cancel', 'dependent-prepared-move'] if segment == 'prepared-dependent' else ['prepared-cancel']
        for name in names:
            allowed = editing and segment in ('reorder-two', 'reorder-three', 'cancel', 'prepared-move', 'prepared-cancel-fetch', 'prepared-cancel-body')
            edits.append(dict(name=name, nativeSchedule=allowed and (kind == 'mp' or prepared), allowed=allowed, reason=False if allowed else 'unavailable', queueBefore=source, queueAfter=order if allowed else source))
    final = snapshot(True)
    row = dict(segment=segment, ids=copy.deepcopy(ids), input=snapshot(), clientPlacement=placement_proof(origin),
               client=copy.deepcopy(final), server=copy.deepcopy(final), commands=commands, edits=edits,
               componentGuard=dict(item=items['a']['id'], size=2, quiet=False, components=[dict(index=0, type='Attributes', **{'class': 'Attributes'}), dict(index=1, type='Script', **{'class': 'EntityScriptInfo'})]) if segment == 'component-guard' else False,
               pendingBefore=snapshot(), pendingAfter=snapshot(), pendingOrder=order, queueIdle=True, tidyQuiescent=True,
               tidyObservation=dict(sourceVerified=True, integrationInstalled=True, idlePlayerUpdates=6, observer='ActionQueueSettlement.operationState', retainedOperations=0, observedBorrowings=0, outstandingBorrowings=0, activeBlockedReturn=False, privateTablesObserved=False), settleMilliseconds=1000, frameCadence=dict(count=2, totalMilliseconds=33, maxMilliseconds=17))
    if prepared:
        row['preparedGroup'] = dict(schema=1, producer='ISInventoryPaneContextMenu.OnPrimaryWeapon', scope='source-bound-menu-route-and-final-retained-effect',
            operationGrouping='ActionQueueOperations.run', sourceVerified=True, intentRouteVerified=True, tokenShared=True,
            item=items['nested']['id'], sourceOwner=items['bag']['id'], destination='actor-root', rows=group)
    return row, selection, ids, final


def callback_observation():
    return dict(schema=1, sourceVerified=True, bindingsCurrent=True, classUnchanged=True, customCallbacksAbsent=True, differences=[], verified=True)


def owned_observation():
    return dict(schema=1, kind='owned-deferred-carried-container', sourceVerified=True, bindingsCurrent=True,
        constructorUnchanged=True, verified=True, nativeActionCallbacks=False, paidProgress=False,
        constructorSource='ISQueueActionsAction.lua', startSource='ActionQueueOperations.lua', requestSource='ActionQueueApproach.lua')


class EquipEditTests(unittest.TestCase):
    def test_authority_seed_sync_serializes_nested_ids_once_before_canonical_worn_binding(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().fixture_path = str(PROJECT / 'tests/native_queue/magazine-unload/shared/QueueEquipEdit.lua')
        # Network doubles model the verified native boundary: InventoryContainer.save
        # includes children; SyncClothing resolves an inventory ID or creates an
        # unattached object. This does not exercise native packet transport.
        lua.execute('''
local function equal(a,b)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not equal(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end;return true
end
package.preload.QueueEnergyPlacement=function()return{atCentered=function()return true end}end
package.preload.QueueMagazineUnload=function()return{equal=equal,hands=function(player)
 local primary,secondary=player:getPrimaryHandItem(),player:getSecondaryHandItem()
 return{primary=primary and primary:getID()or false,secondary=secondary and secondary:getID()or false}
end}end
Perks={Woodwork={},Doctor={}}
local server,nextID=true,0
function isServer()return server end
function getClassSimpleName(item)return item.class end
function instanceof(item,class)return item.class==class end
local makeContainer,makeItem
makeItem=function(fullType,id)
 local item={fullType=fullType,id=id,pages=0}
 item.class=fullType:find('Book')and'Literature'or fullType:find('Bag_')and'InventoryContainer'or fullType=='Base.Nails'and'ComboItem'or'HandWeapon'
 function item:getID()return self.id end
 function item:getFullType()return self.fullType end
 function item:getContainer()return self.container end
 function item:getCondition()return 10 end
 function item:getCount()return self.fullType=='Base.Nails'and 5 or 1 end
 function item:getCurrentUses()return 1 end
 function item:getNumberOfPages()return 100 end
 function item:getAlreadyReadPages()return self.pages end
 function item:setAlreadyReadPages(pages)self.pages=pages end
 function item:canBeEquipped()return 'Back' end
 function item:getItemContainer()return self.child end
 if item.class=='InventoryContainer'then item.child=makeContainer()end;return item
end
makeContainer=function()
 local container={items={}}
 function container:getItems()
  local values=self.items;return{size=function()return #values end,get=function(_,index)return values[index+1]end}
 end
 function container:AddItem(fullType)
  nextID=nextID+1;local item=makeItem(fullType,nextID);item.container=self;self.items[#self.items+1]=item;return item
 end
 function container:getItemById(id)for _,item in ipairs(self.items)do if item.id==id then return item end end end
 function container:setExplored()end;return container
end
local function player()
 local p={root=makeContainer(),worn={},read={}}
 function p:getInventory()return self.root end
 function p:getPrimaryHandItem()return self.primary end
 function p:getSecondaryHandItem()return self.secondary end
 function p:getWornItem(slot)return self.worn[slot]end
 function p:setWornItem(slot,item)self.worn[slot]=item end
 function p:setAlreadyReadPages(kind,pages)self.read[kind]=pages end
 function p:getAlreadyReadPages(kind)return self.read[kind]end
 function p:setPerkLevelDebug()end;return p
end
local fixture=assert(loadfile(fixture_path))()
for _,segment in ipairs(fixture.selectedSegments(true))do
 local authority,replica=player(),player();local serialized={};local sends=0
 local function copy(item,destination)
  assert(not serialized[item.id],'duplicate serialized nested item ID');serialized[item.id]=true
  local value=makeItem(item.fullType,item.id);value.pages=item.pages;value.container=destination
  destination.items[#destination.items+1]=value
  if item.child then for _,child in ipairs(item.child.items)do copy(child,value.child)end end
  return value
 end
 function sendAddItemToContainer(container,item)
  assert(server and container==authority.root,'only complete actor roots may be transmitted')
  sends=sends+1;copy(item,replica.root)
 end
 function sendClothing(p,slot,item)
  assert(server and p==authority);sends=sends+1
  replica:setWornItem(slot,replica.root:getItemById(item.id)or makeItem(item.fullType,item.id))
 end
 server=true;local state=fixture.prepare(authority,segment,'native','mp',{},{});local ids=state.ids
 for _,spec in pairs(ids.items)do assert(serialized[spec.id],'authority seed was not serialized')end
 local resolved=assert(fixture.resolve(replica,ids),'replica did not resolve exact authoritative inventory/worn graph')
 assert(resolved.items.bag==replica:getWornItem('Back'),'worn bag is not the canonical inventory object')
 assert(resolved.items.marker:getContainer()==resolved.items.bag:getItemContainer(),'nested marker parent changed')
 if segment=='capacity'then assert(resolved.items.nested:getContainer()==resolved.items.heldBag:getItemContainer(),'held-source child parent changed')end
 if fixture.isPrepared(segment)then
  -- Model the observed final data only: this is not a native transfer/equip.
  local nested=state.items.nested;local child=nested:getContainer()
  for index,item in ipairs(child.items)do if item==nested then table.remove(child.items,index);break end end
  nested.container=authority.root;authority.root.items[#authority.root.items+1]=nested
  authority.primary=nested;authority.secondary=segment=='prepared-move'and state.items.b or nil
  for _,name in ipairs({'front','tail'})do local book=state.items[name];book.pages=100;authority.read[book.fullType]=100 end
  assert(fixture.verify(state),'prepared retained-root final snapshot rejected')
  local found=false
  for _,row in ipairs(ids.inventory)do if row.id==nested.id then found=true;assert(#row.path==1 and row.path[1]==state.items.bag.id,'verification mutated authority seed history')end end
  assert(found)
 end
 local previous=sends;server=false
 local localState=fixture.prepare(player(),segment,'native','sp',{},{});assert(localState.input.backpack and sends==previous,'SP preparation emitted authority packets')
end
''')

    def test_ordered_subset_and_independent_equip_group_selection(self):
        selection = dict(kind='sp', mode='toolkit', clients=1, languages=['EN'], mods=adapter.MODS, options={})
        for cases in (['direct'], ['bulk'], ['direct', 'bulk'], ['equip-edit']):
            adapter.validate(dict(selection, cases=cases))
        for cases in ([], ['bulk', 'direct'], ['direct', 'direct'], ['equip-edit', 'direct'], ['missing']):
            with self.assertRaises(ValueError): adapter.validate(dict(selection, cases=cases))
        self.assertIn('equip-edit', [row['id'] for row in adapter.definitions()['magazine-unload']['cases']])

    def test_matching_native_and_sp_toolkit_and_host_denial_evidence(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for segment in verifier.SEGMENTS:
                    self.assertEqual([], verifier.check_segment(*evidence(segment, kind, mode)), (segment, kind, mode))

    def test_prepared_profile_keeps_original_bank_and_requires_explicit_selection(self):
        selection = dict(kind='sp', mode='toolkit', clients=1, languages=['EN'], mods=adapter.MODS, cases=['equip-edit'], options=dict(equip_prepared=True))
        adapter.validate(selection)
        self.assertEqual(verifier.SEGMENTS + verifier.PREPARED_SEGMENTS, verifier.selected_segments(selection))
        for options, cases in ((dict(equip_prepared='true'), ['equip-edit']), (dict(equip_prepared=True), ['direct']),
                               (dict(equip_prepared=True, equip_workload=True), ['equip-edit'])):
            with self.assertRaises(ValueError): adapter.validate(dict(selection, options=options, cases=cases))
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                for segment in verifier.PREPARED_SEGMENTS:
                    values = evidence(segment, kind, mode)
                    self.assertEqual([], verifier.check_segment(*values), (kind, mode, segment))
                    values[1]['options'] = {}
                    self.assertTrue(verifier.check_segment(*values), 'unselected prepared evidence accepted')

    def test_prepared_move_changes_actual_whole_group_order_and_preserves_explicit_item(self):
        for kind in ('sp', 'mp'):
            values = evidence('prepared-move', kind); row, _, ids, _ = values
            self.assertEqual(['front', 'prepared-approach', 'prepared-fetch', 'prepared-equip', 'equip-b', 'tail'], row['pendingOrder'])
            self.assertEqual(dict(primary=ids['items']['nested']['id'], secondary=ids['items']['b']['id']), row['client']['hands'])
            nested = next(item for item in row['client']['inventory'] if item['id'] == ids['items']['nested']['id'])
            self.assertEqual([], nested['path'])
            for change in ('marker', 'producer', 'group-rows', 'token', 'partial-move', 'paid-approach', 'native-approach-claim', 'source-approach', 'canonical-host'):
                changed = copy.deepcopy(values); bad = changed[0]
                if change == 'marker': bad['edits'][0]['nativeSchedule'] = False
                elif change == 'producer': bad['preparedGroup']['producer'] = 'fixture.direct-constructor'
                elif change == 'group-rows': bad['preparedGroup']['rows'].remove('prepared-fetch')
                elif change == 'token': next(command for command in bad['commands'] if command['name'] == 'prepared-fetch')['operation'] = 2
                elif change == 'partial-move': bad['pendingOrder'] = ['front', 'prepared-equip', 'equip-b', 'prepared-approach', 'prepared-fetch', 'tail']
                elif change == 'canonical-host':
                    command = next(command for command in bad['commands'] if command['name'] == 'prepared-equip')
                    for event in command['lifecycle']: event['itemIdentity']['canonicalRoot'] = False
                else:
                    command = next(command for command in bad['commands'] if command['name'] == 'prepared-approach')
                    if change == 'paid-approach': command['progress'] = True
                    elif change == 'native-approach-claim': command['callbackConstructor']['nativeActionCallbacks'] = True
                    else: command['callbackConstructor']['requestSource'] = 'foreign.lua'
                self.assertTrue(verifier.check_segment(*changed), (kind, change))

    def test_prepared_fetch_or_body_cancel_removes_every_unsubmitted_member(self):
        for kind in ('sp', 'mp'):
            for segment in ('prepared-cancel-fetch', 'prepared-cancel-body'):
                values = evidence(segment, kind); row = values[0]
                self.assertEqual(['front', 'equip-b', 'tail'], row['pendingOrder'])
                cancelled = [command for command in row['commands'] if command.get('cancelled')]
                self.assertEqual(['prepared-approach', 'prepared-fetch', 'prepared-equip'], [command['name'] for command in cancelled])
                for change in ('partial', 'started-fetch', 'submitted-body', 'lost-nested'):
                    changed = copy.deepcopy(values); bad = changed[0]
                    commands = {command['name']: command for command in bad['commands']}
                    if change == 'partial': bad['pendingOrder'].insert(2, 'prepared-equip')
                    elif change == 'started-fetch': commands['prepared-fetch']['started'] = True
                    elif change == 'submitted-body':
                        commands['prepared-equip']['lifecycle'] = [dict(sequence=99, event='admission', phase=False, succeeded=False,
                            nativeEpisode=99, nativeClass='LuaTimedActionNew', hands=dict(primary=False, secondary=False),
                            itemLocation=dict(root=False, containerPresent=True, owner=bad['ids']['items']['bag']['id']),
                            itemIdentity=dict(id=bad['ids']['items']['nested']['id'], type='Base.Pencil', **{'class': 'HandWeapon'}, canonicalRoot=False),
                            callbackObservation=callback_observation())]
                    else: next(item for item in bad['client']['inventory'] if item['id'] == bad['ids']['items']['nested']['id'])['path'] = []
                    self.assertTrue(verifier.check_segment(*changed), (kind, segment, change))

    def test_prepared_same_item_survivor_denials_keep_native_commands_and_tail(self):
        for kind in ('sp', 'mp'):
            values = evidence('prepared-dependent', kind)
            self.assertEqual([], verifier.check_segment(*values))
            self.assertEqual([False, False], [edit['allowed'] for edit in values[0]['edits']])
            for edit in values[0]['edits']:
                self.assertEqual(edit['queueBefore'], edit['queueAfter'])
            changed = copy.deepcopy(values); changed[0]['edits'][0]['allowed'] = True
            self.assertTrue(verifier.check_segment(*changed))

    def test_actual_menu_fixture_registers_enqueued_rows_without_resubmitting(self):
        from lupa.lua51 import LuaRuntime
        source = (PROJECT / 'tests/native_queue/magazine-unload/client/QueueEquipEditClient.lua').read_text()
        helper = source[source.index('local function menuEquip(item)'):source.index('local function guardedComponentFacts(item)')]
        lua = LuaRuntime(unpack_returned_tuples=True); lua.globals().helper_source = helper
        # Explicit producer/source/queue doubles exercise this fixture's
        # grouping and registration only, not native producer qualification.
        lua.execute(r'''
for _,native in ipairs({false,true})do
 for _,change in ipairs({'none','split','extra','rebind','intent'})do
  local origins,scope,registered={},{},{}
  local root,source,bag={},{},{getID=function()return 42 end}
  local item={getID=function()return 41 end,getContainer=function()return source end}
  local player={getInventory=function()return root end,getPlayerNum=function()return 0 end}
  getPlayer=function()return player end
  local front={};local q={queue={front}}
  local function queue()return q end
  local intent={status=function()return change~='intent'end}
  local operations={run=function(callback,...)
   scope={};callback(...)
  end}
  ISInventoryPane={getActualItems=function(items)return items end}
  ISInventoryTransferUtil={newInventoryTransferAction=function()end}
  ISInventoryPaneContextMenu={equipWeapon=function()end,transferIfNeeded=function()end}
  local owner=ISInventoryPaneContextMenu
  owner.OnPrimaryWeapon=function(items,number)
   assert(items[1]==item and number==0,'menu producer arguments changed')
   if not native then q.queue[#q.queue+1]={Type='ISQueueActionsAction',toolkitQueueOperation=scope,target=source}end
   q.queue[#q.queue+1]={Type='ISInventoryTransferAction',toolkitQueueOperation=scope,item=item,srcContainer=source,destContainer=root}
   q.queue[#q.queue+1]={Type='ISEquipWeaponAction',toolkitQueueOperation=change=='split'and{}or scope,item=item,primary=true,twoHands=false}
   if change=='extra'then q.queue[#q.queue+1]={}end
   if change=='rebind'then owner.equipWeapon=function()end end
  end
  origins[owner.OnPrimaryWeapon]='ActionQueueTidyIntent.lua';origins[owner.equipWeapon]='ISInventoryPaneContextMenu.lua'
  origins[operations.run]='ActionQueueOperations.lua';origins[intent.status]='ActionQueueTidyIntent.lua'
  PZSurvivorToolkit={ActionQueueOperations=operations,ActionQueueTidyIntent=intent,
   ActionQueueApproach={isContainer=function(action,container,actor)return action.target==container and actor==player end}}
  local Proof={closure=function(callback,file)return origins[callback]==file end,captureBindings=function(entries)
   local snapshot={}
   for _,entry in ipairs(entries)do for _,key in ipairs(entry.keys)do snapshot[#snapshot+1]={entry.owner,key,entry.owner[key]}end end
   return function()for _,entry in ipairs(snapshot)do if entry[1][entry[2]]~=entry[3]then return false end end;return true end
  end}
  local tracks={}
  local function track(name,action,enqueued)
   assert(enqueued==true,'already-enqueued native row was resubmitted')
   registered[#registered+1]=name;tracks[action]={name=name}
  end
  local prefix='local native,Proof,queue,track,tracks,state=...;local preparedGroup\n'
  local produce,receipt=assert(loadstring(prefix..helper_source..'\nreturn menuEquip,function()return preparedGroup end'))(
   native,Proof,queue,track,tracks,{items={bag=bag}})
  local ok=pcall(produce,item)
  assert(ok==(change=='none'),'fixture admitted changed producer group '..change)
  if ok then
   assert(q.queue[1]==front and #q.queue==(native and 3 or 4),'registration changed native queue membership')
   assert(#registered==(native and 2 or 3)and receipt().tokenShared and receipt().intentRouteVerified)
  end
 end
end
''')

    def test_owned_approach_observation_is_distinct_and_revoked_by_callback_changes(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True); lua.globals().project_root = str(PROJECT)
        # Source/capture API doubles are explicit here. The actual fixture's
        # class/function identity rules are exercised; no native proof is claimed.
        lua.execute(r'''
local helper=assert(loadfile(project_root..'/tests/native_queue/magazine-unload/client/QueueEquipCallbackObservation.lua'))()
local function setup(rebind)
 local origins={}
 getFilenameOfClosure=function(callback)return origins[callback]end
 getFirstLineOfClosure=function()return 1 end
 local function source(callback,file)origins[callback]=file;return callback end
 local function native()error('observation executed native callback')end
 local class={Type='ISQueueActionsAction',new=source(function()end,'ISQueueActionsAction.lua'),start=native,waitToStart=native,perform=native,stop=native}
 class.__index=class;ISQueueActionsAction=class
 local start=source(function()error('owned start executed')end,'ActionQueueOperations.lua')
 local wait=source(function()error('owned wait executed')end,'ActionQueueOperations.lua')
 local request=source(function()error('owned request executed')end,'ActionQueueApproach.lua')
 local action=setmetatable({start=start,waitToStart=wait,addActionsFunction=request},class)
 local operations={}
 operations.isCommand=source(function(value)return value==action and value.start==start and value.waitToStart==wait and value.addActionsFunction==request end,'ActionQueueOperations.lua')
 operations.commandConstructionTrusted=source(function()return true end,'ActionQueueOperations.lua')
 local approach={isAction=source(function(value)return value==action end,'ActionQueueApproach.lua')}
 local toolkit={ActionQueueOperations=operations,ActionQueueApproach=approach,
  ActionQueuePolicy={matchesNative=source(function()error('native matcher executed for owned command')end,'ActionQueuePolicy.lua')},
  BulkActions={isGuardedTransfer=source(function()error('guard matcher executed for owned command')end,'BulkActions.lua')}}
 PZSurvivorToolkit=toolkit
 local proof={}
 proof.own=source(rawget,'SourceProof.lua')
 proof.closure=function(callback,file)return origins[callback]==file end
 proof.captureBindings=source(function(entries)
  local snapshot,owners={},{}
  for _,entry in ipairs(entries)do
   assert(not owners[entry.owner],'duplicate binding owner rejected by real SourceProof')
   owners[entry.owner]=true
   for _,key in ipairs(entry.keys)do snapshot[#snapshot+1]={entry.owner,key,entry.owner[key]}end
  end
  return function()for _,entry in ipairs(snapshot)do if entry[1][entry[2]]~=entry[3]then return false end end;return true end
 end,'SourceProof.lua')
 proof.matches=source(function(path)
  if rebind and path:find('ActionQueueApproach.lua',1,true)then operations.isCommand=function()return true end end
  return true
 end,'SourceProof.lua')
 toolkitLuaCaptureFactsMatch=function()error('owned command invoked native stop capture matching')end
 toolkitLuaCaptureFactsApiMatches=function(callback)return callback==toolkitLuaCaptureFactsMatch end
 local observer=helper.new(toolkit,{mode='toolkit',kind='sp',options={equip_prepared=true}},proof,{class})
 return {action=action,class=class,toolkit=toolkit,read=observer.track(action)}
end
for _,change in ipairs({'none','start','request','class','custom','api','global'})do
 local s=setup();local value=s.read('constructor')
 assert(value.verified and value.nativeActionCallbacks==false and value.paidProgress==false)
 if change=='start'then s.action.start=function()end
 elseif change=='request'then s.action.addActionsFunction=function()end
 elseif change=='class'then s.class.perform=function()end
 elseif change=='custom'then s.action.onCompleteFunc=function()end
 elseif change=='api'then s.toolkit.ActionQueueOperations.isCommand=function()return true end
 elseif change=='global'then ISQueueActionsAction={}
 end
 assert(s.read('admission').verified==(change=='none'),'owned callback mutation admitted '..change)
end
assert(not pcall(setup,true),'prepared source-reader rebound API accepted')
''')

    def test_same_type_screwdrivers_keep_distinct_native_item_and_hand_identities(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                values = evidence('reorder-three', kind, mode)
                b, c = values[2]['items']['b'], values[2]['items']['c']
                self.assertEqual('Base.Screwdriver', b['type'])
                self.assertEqual(b['type'], c['type'])
                self.assertNotEqual(b['id'], c['id'])
                self.assertEqual([], verifier.check_segment(*values))
                for change in ('aliased-seed', 'wrong-action-item', 'wrong-same-type-hand'):
                    changed = copy.deepcopy(values); row = changed[0]
                    if change == 'aliased-seed': row['ids']['items']['c']['id'] = b['id']
                    elif change == 'wrong-action-item': next(value for value in row['commands'] if value['name'] == 'equip-c')['item'] = b['id']
                    else: row['client']['hands']['primary'] = c['id']
                    self.assertTrue(verifier.check_segment(*changed), (kind, mode, change))

    def test_inventory_loss_alias_nested_drift_and_final_hands_are_rejected(self):
        for change in ('missing', 'duplicate', 'wrong-hands', 'backpack', 'contents', 'authority', 'pending-physical'):
            values = evidence('dependent'); row = values[0]
            if change == 'missing': row['client']['inventory'].pop()
            elif change == 'duplicate': row['client']['inventory'].append(copy.deepcopy(row['client']['inventory'][-1]))
            elif change == 'wrong-hands': row['client']['hands']['primary'] = row['ids']['items']['a']['id']
            elif change == 'backpack': row['client']['backpack'] = False
            elif change == 'contents': next(value for value in row['client']['inventory'] if value['id'] == row['ids']['items']['nested']['id'])['path'] = []
            elif change == 'authority': row['server']['books']['tail']['pages'] -= 1
            else: row['pendingAfter']['inventory'].pop()
            self.assertTrue(verifier.check_segment(*values), change)

    def test_host_requires_native_schedule_and_actual_edits_and_denials_cannot_reorder(self):
        values = evidence(kind='mp'); values[0]['edits'][0]['nativeSchedule'] = False
        self.assertTrue(verifier.check_segment(*values))
        values = evidence(kind='mp'); values[0]['edits'][0]['reason'] = 'bogus-denial'
        self.assertTrue(verifier.check_segment(*values))
        for segment, reason in (('reorder-two', 'move_dependent'), ('cancel', 'operation_dependent')):
            values = evidence(segment, kind='mp'); values[0]['edits'][0]['allowed'] = False
            values[0]['edits'][0]['reason'] = reason
            self.assertTrue(verifier.check_segment(*values), 'Host denial was promoted to positive edit evidence')
        values = evidence('capacity'); values[0]['edits'][0]['queueAfter'] = list(reversed(values[0]['edits'][0]['queueBefore']))
        self.assertTrue(verifier.check_segment(*values))

    def test_source_callback_observer_authenticates_actual_bulk_stop_and_rejects_forged_guards(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().project_root = str(PROJECT)
        # Real fixture helper, BulkActions guard and SourceProof byte/binding
        # checks. The native capture API is an explicit identity/capture double;
        # its bytecode fingerprint is independently derived with the game compiler.
        lua.execute(r'''
getFilenameOfClosure=function(callback)return debug.getinfo(callback,'S').source end
getFirstLineOfClosure=function(callback)return debug.getinfo(callback,'S').linedefined end
local helper=assert(loadfile(project_root..'/tests/native_queue/magazine-unload/client/QueueEquipCallbackObservation.lua'))()
local function setup(mode,kind,sourceChanged,readRebind)
 getFilenameOfClosure=function(callback)return debug.getinfo(callback,'S').source end
 getFirstLineOfClosure=function(callback)return debug.getinfo(callback,'S').linedefined end
 local s={nativeResult=true}
 toolkitLuaMetatableMatches=function(owner,parent)return getmetatable(owner)==parent end
 getModFileReader=function(mod,path)
  assert(mod=='PZSurvivorToolkit')
  if readRebind and not s.rebound then
   s.rebound=true
   if readRebind=='matcher'then PZSurvivorToolkit.ActionQueuePolicy.matchesNative=function()return true end
   elseif readRebind=='guarded'then PZSurvivorToolkit.BulkActions.isGuardedTransfer=function()return true end
   elseif readRebind=='proof'then s.proof.matches=function()return true end
   elseif readRebind=='facts'then toolkitLuaCaptureFactsMatch=function()return true end
   else getFilenameOfClosure=function()return 'BulkActions.lua'end end
  end
  local file=assert(io.open(project_root..'/PZSurvivorToolkit/42/'..path))
  local appended=false
  return{readLine=function()
   local line=file:read('*l');if line then return line end
   if sourceChanged and not appended then appended=true;return '-- changed source' end
  end,close=function()file:close()end}
 end
 local proof=assert(loadfile(project_root..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))();s.proof=proof
 PZSurvivorToolkit={}
 require=function(name)if name=='PZSurvivorToolkit/SourceProof'then return proof end;return{}end
 local bulk=assert(loadfile(project_root..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/BulkActions.lua'))()
 local matcher=assert(loadstring('return function(state)return function()return state.nativeResult end end','@fixture/ActionQueuePolicy.lua'))()(s)
 PZSurvivorToolkit.ActionQueuePolicy={matchesNative=matcher}
 local function native()error('observation executed native action callback')end
 ISInventoryTransferAction={Type='ISInventoryTransferAction',stop=native,update=native,perform=native}
 ISInventoryTransferAction.__index=ISInventoryTransferAction
 local item={};local action=setmetatable({Type='ISInventoryTransferAction',item=item},ISInventoryTransferAction)
 local facts=function(callback,recipe)
  s.factCalls=(s.factCalls or 0)+1
  assert(recipe.fingerprint=='d56b01558730b799ff5a022ed70b3a589bc1816f3f2d16ae82be9f79e490bf5a'
   and recipe.parameters==1 and recipe.upvalues==1 and #recipe.captures==1)
  assert(recipe.captures[1].slot==0 and recipe.captures[1].test=='identity'and recipe.captures[1].value==native)
  local _,captured=debug.getupvalue(callback,1)
  if s.unknown then return nil end
  return not s.falseFacts and callback==s.stop and captured==native
 end
 toolkitLuaCaptureFactsMatch=facts
 toolkitLuaCaptureFactsApiMatches=function(callback)return callback==facts end
 s.observer=helper.new(PZSurvivorToolkit,{mode=mode or'toolkit',kind=kind or'mp'},proof,{ISInventoryTransferAction})
 s.read=s.observer.track(action)
 local constructor=s.read('constructor');assert(constructor.verified and #constructor.differences==0)
 bulk.guardTransfer(action,true);s.stop=action.stop
 assert(action.onCompleteFunc==nil,'optional guard changed native merge behavior')
 s.action,s.bulk,s.proof,s.native,s.matcher=action,bulk,proof,native,matcher;return s
end
local s=setup();local value=s.read('admission')
assert(value.verified and #value.differences==1 and value.differences[1].exactStopCapture
 and value.differences[1].nativeBindingAtAdmission,'actual Bulk stop guard was not authenticated')
-- Native binding is captured at admission; later queue drainage cannot require
-- repeating its transient eligibility. The closure/captured delegate stays fresh.
s.nativeResult=false;assert(s.read('finish').verified and s.factCalls==2)
for _,change in ipairs({'action','class','custom','matcher-false','matcher-rebound','guard-api','facts-rebound',
 'unknown-facts','false-facts','unguarded','forged-public-guard','wrong-original','global-class','stop-removed','stop-replaced'})do
 s=setup()
 if change=='action'then s.action.update=function()end
 elseif change=='class'then ISInventoryTransferAction.stop=function()end
 elseif change=='custom'then s.action.onCompleteFunc=function()end
 elseif change=='matcher-false'then s.nativeResult=false
 elseif change=='matcher-rebound'then PZSurvivorToolkit.ActionQueuePolicy.matchesNative=function()return true end
 elseif change=='guard-api'then s.bulk.isGuardedTransfer=function()return true end
 elseif change=='facts-rebound'then toolkitLuaCaptureFactsMatch=function()return true end
 elseif change=='unknown-facts'then s.unknown=true
 elseif change=='false-facts'then s.falseFacts=true
 elseif change=='unguarded'then s.action.stop=function()end
 elseif change=='forged-public-guard'then
  local forged=assert(loadstring('return function()error("forged callback executed")end','@fixture/BulkActions.lua'))()
  s.action.stop=forged;s.action.toolkitTransferGuard.stop=forged
  assert(s.bulk.isGuardedTransfer(s.action,s.native)and s.matcher(),'structural matchers must exercise the forged-marker gap')
 elseif change=='wrong-original'then s.action.toolkitTransferGuard.original=function()end
 elseif change=='global-class'then ISInventoryTransferAction={}
 else
  assert(s.read('admission').verified)
  if change=='stop-removed'then s.action.stop=nil
  else local other=setmetatable({},getmetatable(s.action));s.bulk.guardTransfer(other,true)
   s.action.stop=other.stop;s.action.toolkitTransferGuard=other.toolkitTransferGuard;s.stop=other.stop end
 end
 assert(not s.read((change=='stop-removed'or change=='stop-replaced')and'finish'or'admission').verified,'callback mutation accepted: '..change)
end
for _,selection in ipairs({{'native','mp'},{'toolkit','sp'}})do
 s=setup(selection[1],selection[2]);assert(not s.read('admission').verified,'stop wrapper escaped mode/kind scope')
end
assert(not pcall(setup,'toolkit','mp',true),'changed source bytes were accepted')
for _,binding in ipairs({'matcher','guarded','proof','facts','metadata'})do
 assert(not pcall(setup,'toolkit','mp',false,binding),'source-read rebind was accepted: '..binding)
end
''')

    def test_verifier_requires_fresh_explicit_stop_proof_without_upgrading_old_false_receipts(self):
        def observation(changed=False):
            differences = [dict(scope='action', method='stop', source='BulkActions.lua', line=123,
                                originalBaseline=True, guardedTransfer=True, exactStopCapture=True,
                                nativeBindingAtAdmission=True)] if changed else []
            return dict(schema=1, sourceVerified=True, bindingsCurrent=True, classUnchanged=True,
                        customCallbacksAbsent=True, differences=differences, verified=True)
        def guarded(values):
            command = next(row for row in values[0]['commands'] if row['name'] == 'transfer')
            command['callbacksUntouched'] = False
            command['callbackConstructor'] = observation()
            for event in command['lifecycle']: event['callbackObservation'] = observation(True)
            return command
        values = evidence('capacity', 'mp'); guarded(values)
        self.assertEqual([], verifier.check_segment(*values))
        for change in ('old-false', 'constructor', 'event', 'capture', 'matcher', 'binding', 'class', 'method', 'scope', 'source', 'custom', 'raw-true', 'late-wrapper'):
            changed = copy.deepcopy(values); command = next(row for row in changed[0]['commands'] if row['name'] == 'transfer')
            proof = command['lifecycle'][0]['callbackObservation']
            if change == 'old-false':
                command.pop('callbackConstructor')
                for event in command['lifecycle']: event.pop('callbackObservation')
            elif change == 'constructor': command.pop('callbackConstructor')
            elif change == 'event': command['lifecycle'][-1].pop('callbackObservation')
            elif change == 'capture': proof['differences'][0]['exactStopCapture'] = False
            elif change == 'matcher': proof['differences'][0]['nativeBindingAtAdmission'] = False
            elif change == 'binding': proof['bindingsCurrent'] = False
            elif change == 'class': proof['classUnchanged'] = False
            elif change in ('method', 'scope', 'source'): proof['differences'][0][change] = 'unknown'
            elif change == 'custom': proof['customCallbacksAbsent'] = False
            elif change == 'raw-true': command['callbacksUntouched'] = True
            else: command['lifecycle'][0]['callbackObservation'] = observation()
            self.assertTrue(verifier.check_segment(*changed), change)
        for kind, mode in (('sp', 'toolkit'), ('mp', 'native')):
            changed = evidence('capacity', kind, mode); guarded(changed)
            self.assertTrue(verifier.check_segment(*changed), (kind, mode))

    def test_only_host_transfer_accepts_exact_native_transaction_duration_sentinel(self):
        for kind in ('sp', 'mp'):
            for segment in ('dependent', 'capacity'):
                values = evidence(segment, kind)
                self.assertEqual([], verifier.check_segment(*values))
                for name in ('front', 'tail', 'transfer'):
                    for duration in (-2, -1, 0, 100, True, float('inf')):
                        changed = copy.deepcopy(values)
                        command = next(row for row in changed[0]['commands'] if row['name'] == name)
                        command['duration'] = duration
                        allowed = duration == -1 if kind == 'mp' and name == 'transfer' else type(duration) in (int, float) and 0 < duration < float('inf')
                        self.assertEqual(not allowed, bool(verifier.check_segment(*changed)), (kind, segment, name, duration))
                changed = copy.deepcopy(values)
                next(row for row in changed[0]['commands'] if row['name'].startswith('equip-'))['duration'] = -1
                self.assertTrue(verifier.check_segment(*changed))

    def test_client_tracker_preserves_native_transfer_sentinel_and_queue_member(self):
        from lupa.lua51 import LuaRuntime
        source = (PROJECT / 'tests/native_queue/magazine-unload/client/QueueEquipEditClient.lua').read_text()
        track = source[source.index('local function track(name,action,enqueued)'):source.index('local function book(name)')]
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().track_source = track
        # Exercise the actual fixture guard with constructor-field doubles, not
        # synthetic transaction updates or fabricated progress observations.
        lua.execute(r'''
local client=false
function isClient()return client end
local config,tracks,commands={kind='sp'},{},{}
local callbacks={ISReadABook={},ISEquipWeaponAction={},ISInventoryTransferAction={}}
local added={}
ISTimedActionQueue={add=function(action)added[#added+1]=action end}
local callbackObserver={track=function()return function()return{verified=true,differences={}}end end};local callbackReaders={}
local prefix='local config,tracks,commands,callbacks,callbackObserver,callbackReaders=...\n'
local track=assert(loadstring(prefix..track_source..'\nreturn track'))(config,tracks,commands,callbacks,callbackObserver,callbackReaders)
local item={getID=function()return 17 end}
local function action(kind,duration)
 return{Type=kind,item=item,maxTime=duration,maxTimeInit=50,twoHands=false,fromHotbar=false,
  queueList={{time=duration,items={item}}},transactionId=0}
end
for _,kind in ipairs({'ISReadABook','ISEquipWeaponAction','ISInventoryTransferAction'})do
 for _,mp in ipairs({false,true})do
  client=mp;config.kind=mp and'mp'or'sp'
  for _,duration in ipairs({-2,-1,0,50,math.huge})do
   local expected=mp and kind=='ISInventoryTransferAction'and duration==-1
    or not(mp and kind=='ISInventoryTransferAction')and duration==50
   assert(pcall(track,'probe',action(kind,duration))==expected,'fixture duration boundary differs')
  end
 end
end
client=true;config.kind='mp'
for _,change in ipairs({'timer','item','extra','transaction'})do
 local value=action('ISInventoryTransferAction',-1)
 if change=='timer'then value.queueList[1].time=50
 elseif change=='item'then value.queueList[1].items[1]={}
 elseif change=='extra'then value.queueList[2]=value.queueList[1]
 else value.transactionId=1 end
 assert(not pcall(track,'probe',value),'changed native transaction constructor was accepted')
end
''')

    def test_native_callbacks_paid_lifecycle_and_independent_tail_required(self):
        for change in ('duration', 'callback', 'perform', 'episode', 'progress', 'tail', 'cancel-ran', 'p4-busy'):
            values = evidence('cancel'); row = values[0]; command = row['commands'][1]
            if change == 'duration': command['duration'] = 1
            elif change == 'callback': command['callbacksUntouched'] = False
            elif change == 'perform': command['lifecycle'] = [event for event in command['lifecycle'] if event['phase'] != 'perform']
            elif change == 'episode': command['lifecycle'][2]['nativeEpisode'] = False
            elif change == 'progress': row['commands'][0]['progress'] = False
            elif change == 'tail': row['commands'].pop()
            elif change == 'cancel-ran': row['commands'][3]['started'] = True
            else: row['tidyQuiescent'] = False
            self.assertTrue(verifier.check_segment(*values), change)

    def test_native_transfer_and_equip_effects_precede_original_p4_returns(self):
        for segment in ('dependent', 'capacity'):
            values = evidence(segment)
            primary = values[2]['items']['heldBag']['id'] if segment == 'capacity' else False
            self.assertEqual(dict(primary=primary, secondary=False), values[0]['client']['hands'])
            self.assertEqual(values[2]['inventory'], values[0]['client']['inventory'])
            for change in ('transfer-effect', 'equip-effect', 'invented-retention'):
                changed = copy.deepcopy(values); row = changed[0]
                if change == 'invented-retention': row['client']['hands']['primary'] = row['ids']['items']['nested']['id'] if segment == 'dependent' else False
                else:
                    command = next(value for value in row['commands'] if value['name'] == ('transfer' if change == 'transfer-effect' else 'equip-nested' if segment == 'dependent' else 'equip-bag'))
                    event = next(value for value in command['lifecycle'] if value['event'] == 'finish' and value['phase'] == 'complete')
                    if change == 'transfer-effect': event['itemLocation'] = dict(root=False, containerPresent=True, owner=row['ids']['items']['bag' if segment == 'dependent' else 'heldBag']['id'])
                    else: event['hands'] = dict(primary=False, secondary=False)
                self.assertTrue(verifier.check_segment(*changed), (segment, change))

    def test_capacity_preserves_exact_held_source_bag_while_dependent_clears_pencil(self):
        for kind in ('sp', 'mp'):
            for mode in ('native', 'toolkit'):
                values = evidence('capacity', kind, mode)
                self.assertEqual([], verifier.check_segment(*values))
                held = values[2]['items']['heldBag']['id']
                self.assertEqual(dict(primary=held, secondary=False), values[0]['client']['hands'])
                for role in ('client', 'server'):
                    for wrong in (False, values[2]['items']['a']['id'], values[2]['items']['bag']['id']):
                        changed = copy.deepcopy(values); changed[0][role]['hands']['primary'] = wrong
                        self.assertTrue(verifier.check_segment(*changed), (kind, mode, role, wrong))
                dependent = evidence('dependent', kind, mode)
                self.assertEqual(dict(primary=False, secondary=False), dependent[0]['client']['hands'])
                self.assertEqual([], verifier.check_segment(*dependent))

    def test_quiescence_observes_real_idle_updates_and_retained_loans_without_private_maps(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().helper_path = str(PROJECT / 'tests/native_queue/magazine-unload/client/QueueEquipEditQuiescence.lua')
        # Explicit source-metadata and private-loan observer doubles; no P4 map is exposed.
        lua.execute('''
local helper=assert(loadfile(helper_path))()
local idle,valid,blocked=true,true,false
local updates,states={},{}
P4TidyUpMeister={registerActionPolicy=function()end,registerWornItemReplacement=function()end}
local compat={isInstalled=function()return true end,verifySources=function()return true end}
local settlement={operationState=function(action)return states[action]end,hasActiveBlockedReturn=function()return blocked end}
local proof={closure=function(value)return type(value)=='function'end,captureBindings=function()return function()return valid end end}
local events={OnPlayerUpdate={Add=function(callback)updates[#updates+1]=callback end}}
local player,other,action={},{},{}
local tracks={[action]={}}
local observer=helper.new({ActionQueueCompat=compat,ActionQueueSettlement=settlement},player,function()return idle end,proof,events)
local function tick(who)for _,callback in ipairs(updates)do callback(who or player)end end
for i=1,8 do tick(other)end
assert(observer.read(tracks)==nil,'foreign player updates became quiescence')
for i=1,5 do tick()end
assert(observer.read(tracks)==nil,'P4 idle boundary completed too early')
tick();local receipt=assert(observer.read(tracks));assert(receipt.idlePlayerUpdates==6 and receipt.privateTablesObserved==false and receipt.retainedOperations==0)
states[action]={borrowings={{state='prepare'}}};assert(observer.read(tracks)==nil,'outstanding borrowing was ignored')
local diagnostic=observer.diagnose(tracks);assert(diagnostic.privateTablesObserved==false and diagnostic.operations[1].state.borrowings[1].state=='prepare','failure diagnosis lost original retained-loan state')
states[action].borrowings[1].state='completed';receipt=assert(observer.read(tracks));assert(receipt.retainedOperations==1 and receipt.observedBorrowings==1)
blocked=true;assert(observer.read(tracks)==nil,'blocked return was ignored');blocked=false
idle=false;tick();idle=true;assert(observer.read(tracks)==nil,'native work did not reset idle boundary')
for i=1,6 do tick()end
valid=false;assert(observer.read(tracks)==nil,'changed source bindings retained authority');valid=true
assert(observer.read(tracks));observer.reset();assert(observer.read(tracks)==nil,'segment reset retained idle history')
''')

    def test_quiescence_receipt_cannot_claim_private_maps_or_outstanding_loans(self):
        for field, value in (('idlePlayerUpdates', 5), ('outstandingBorrowings', 1), ('activeBlockedReturn', True),
                             ('privateTablesObserved', True), ('sourceVerified', False), ('integrationInstalled', False)):
            values = evidence(); values[0]['tidyObservation'][field] = value
            self.assertTrue(verifier.check_segment(*values), field)

    def test_frame_cadence_is_structural_evidence_without_arbitrary_performance_gate(self):
        for total, maximum in ((0, 0), (33, 17), (100000, 90000)):
            values = evidence(); values[0]['frameCadence'] = dict(count=2, totalMilliseconds=total, maxMilliseconds=maximum)
            self.assertEqual([], verifier.check_segment(*values))
        for cadence in (dict(count=0, totalMilliseconds=0, maxMilliseconds=0),
                        dict(count=2, totalMilliseconds=20, maxMilliseconds=21),
                        dict(count=2, totalMilliseconds=50, maxMilliseconds=20),
                        dict(count=2, totalMilliseconds=float('inf'), maxMilliseconds=20)):
            values = evidence(); values[0]['frameCadence'] = cadence
            self.assertTrue(verifier.check_segment(*values))

    def test_component_guard_requires_actual_hammer_components_and_denied_edits(self):
        for change in ('quiet', 'missing', 'wrong-type', 'index', 'allowed', 'reordered', 'substituted'):
            values = evidence('component-guard'); row = values[0]
            if change == 'quiet': row['componentGuard']['quiet'] = True
            elif change == 'missing': row['componentGuard']['components'].pop()
            elif change == 'wrong-type': row['componentGuard']['components'][1]['type'] = 'FluidContainer'
            elif change == 'index': row['componentGuard']['components'][1]['index'] = 8
            elif change == 'allowed': row['edits'][0]['allowed'] = True
            elif change == 'reordered': row['edits'][0]['queueAfter'] = list(reversed(row['edits'][0]['queueBefore']))
            else: row['ids']['items']['a']['type'] = 'Base.Pencil'
            self.assertTrue(verifier.check_segment(*values), change)

    def test_grouped_verifier_requires_all_ordered_authority_checkpoints(self):
        for kind, prepared_profile in ((kind, profile) for kind in ('sp', 'mp') for profile in (False, True)):
            selection = dict(kind=kind, mode='toolkit', cases=['equip-edit'], options=dict(equip_prepared=prepared_profile))
            selected = verifier.selected_segments(selection)
            client = ['[QUEUE_TEST] ' + marker for marker in ('VOICE_DISABLED', 'DISPLAY_READY', 'PREFLIGHT_COMPLETE', 'NATIVE_CONNECTED' if kind == 'mp' else 'TRUE_SP')]
            authority = ['[STARTUP_TEST] SERVER_READY']
            group = []
            for segment in selected:
                row, _, ids, final = evidence(segment, kind)
                group.append(row)
                client.append(verifier.PREFIX + 'CLIENT_PLACEMENT ' + json.dumps(dict(case='equip-edit', segment=segment, proof=row['clientPlacement'])))
                authority.extend([verifier.PREFIX + 'PREPARED ' + json.dumps(ids), verifier.PREFIX + 'VERIFIED ' + json.dumps(final)])
            client.extend(['[QUEUE_CHECK] ' + json.dumps(dict(suite='magazine-unload', event='setup', cases=['equip-edit'], segments=selected, queueEnabled=True, nativeDurations=True)),
                           '[QUEUE_CHECK] ' + json.dumps(dict(suite='magazine-unload', event='case', id='equip-edit', status='passed', actor='client1', kind=kind, mode='toolkit', segments=group, queueIdle=True, tidyQuiescent=True)),
                           '[QUEUE_CHECK] ' + json.dumps(dict(suite='magazine-unload', event='complete', cases=['equip-edit'], performed=1, failed=0, skipped=0)),
                           adapter.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=['equip-edit']))])
            if kind == 'sp': client += authority
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); (root / 'client1-launch.log').write_text('\n'.join(client)); (root / 'server-launch.log').write_text('\n'.join(authority))
                result = adapter.verify(root, selection, {})
                self.assertEqual([], result['issues'])
                self.assertIs(result['evidence']['preparedSelected'], prepared_profile)
                self.assertIs(result['evidence']['failedPickupQualified'], False)
                outcome = result['outcomes'][0]['outcome']
                self.assertIs(outcome['pendingEditsVerified'], True)
                self.assertIs(outcome['pendingProtectionVerified'], True)
                # Drive the real scenario matrix using the verifier's current
                # outcome fields. Host coverage requires actual changed native order/cancellation,
                # not only a clean denial or a capability flag.
                from queue_checks import scenarios
                suite = adapter.definitions()['magazine-unload']
                coverage = dict(result['outcomes'][0], suite='magazine-unload', kind=kind, mode='toolkit')
                reports = [dict(status='passed', selection=dict(mods=adapter.MODS), coverage=[coverage])]
                def case_matrix(catalog, matching):
                    return dict(rows=[dict(suite='magazine-unload', case='equip-edit', kind=kind, mode='toolkit', status='passed', evidence=[coverage])])
                matrix = scenarios.matrix(dict(suites={'magazine-unload': suite}), reports, case_matrix)
                mapped = {value['scenario']: value for value in matrix if value['action'] == 'native-equip-edit' and value['kind'] == kind and value['mode'] == 'toolkit'}
                for positive in ('cancel-waiting', 'move-independent'):
                    self.assertEqual('passed', mapped[positive]['status'])
                self.assertEqual('passed', mapped['move-dependent']['status'])

                if kind == 'sp': (root / 'client1-launch.log').write_text('\n'.join(client[:-1]))
                else: (root / 'server-launch.log').write_text('\n'.join(authority[:-1]))
                self.assertTrue(adapter.verify(root, selection, {})['issues'])

    def test_source_audit_adds_native_read_transfer_and_equip_without_weaker_unload_pins(self):
        self.assertEqual(3528902511, adapter.EQUIP_NATIVE_CRC['media/lua/shared/TimedActions/ISEquipWeaponAction.lua'])
        self.assertIn('media/lua/shared/TimedActions/ISUnloadBulletsFromMagazine.lua', adapter.NATIVE_CRC)
        declared = adapter.verifier_sources(PROJECT, dict(cases=['equip-edit']))
        self.assertIn(Path(verifier.__file__), declared)
        self.assertIn(Path(__file__), declared)

    def test_prepared_source_preflight_uses_closed_opt_in_literals(self):
        fixture = (PROJECT / 'tests/native_queue/magazine-unload/client/QueueEquipCallbackObservation.lua').read_text()
        normal = adapter._reviewed_equip_pins(fixture)
        prepared = adapter._reviewed_equip_pins(fixture, prepared=True)
        self.assertEqual(normal, {key: value for key, value in prepared.items() if key in normal})
        self.assertEqual({'client/PZSurvivorToolkit/ActionQueueOperations.lua', 'client/PZSurvivorToolkit/ActionQueueApproach.lua',
                          'client/PZSurvivorToolkit/ActionQueueTidyIntent.lua'}, set(prepared) - set(normal))
        for change in ('flag', 'guard', 'computed-pin', 'duplicate'):
            changed = fixture
            if change == 'flag': changed = changed.replace('local prepared=config.options and config.options.equip_prepared==true', 'local prepared=true')
            elif change == 'guard': changed = changed.replace('if prepared then\n  for _,entry in ipairs(preparedSources)do', 'if true then\n  for _,entry in ipairs(preparedSources)do')
            elif change == 'computed-pin': changed = changed.replace("'ActionQueueOperations.lua',2049664196", "'ActionQueueOperations.lua',actualChecksum()")
            else: changed = changed.replace("'ActionQueueApproach.lua'," + str(prepared['client/PZSurvivorToolkit/ActionQueueApproach.lua']), "'ActionQueueOperations.lua',3155442316")
            with self.assertRaises(ValueError, msg=change): adapter._reviewed_equip_pins(changed, prepared=True)


class HostHandPointTests(unittest.TestCase):
    def evidence(self):
        query = dict(segment='reorder-two', player=7, transaction=-126, token='12345678-1234-1234-1234-123456789abc', kind='ISReadABook')
        point = dict(schema=1, scope='server-native-active-action-point', state='accepted', **{k: query[k] for k in ('player', 'transaction', 'token', 'kind')},
                     primaryPresent=False, secondaryPresent=False, primaryId=False, secondaryId=False, primaryType=False, secondaryType=False,
                     primaryContainerIsRoot=False, secondaryContainerIsRoot=False, sameItem=False,
                     rootMembershipVerified=False, packetCorrelated=False, effectsVerified=False, editAuthority=False)
        value = dict(query=query, server=point, clientHands=dict(primary=False, secondary=False), active=True, authority=False)
        return [dict(segment='reorder-two', handPoint=value)], dict(kind='mp', options=dict(equip_host_observation=True)), value

    def check(self, segments, selection, value):
        authority = verifier.PREFIX + 'HAND_POINT ' + json.dumps(dict(segment='reorder-two', query=value['query'], point=value['server']))
        return verifier.check_hand_point(segments, selection, authority)

    def test_matches_raw_server_action_and_does_not_credit_edit_authority(self):
        segments, selection, value = self.evidence()
        self.assertEqual(value, self.check(segments, selection, value))
        for flag in ('rootMembershipVerified', 'packetCorrelated', 'effectsVerified', 'editAuthority'):
            with self.subTest(flag=flag):
                bad = copy.deepcopy(segments); bad[0]['handPoint']['server'][flag] = True
                with self.assertRaises(ValueError): self.check(bad, selection, bad[0]['handPoint'])
        for key in ('token', 'transaction', 'kind', 'player'):
            with self.subTest(identity=key):
                bad = copy.deepcopy(segments); bad[0]['handPoint']['server'][key] = 'wrong'
                with self.assertRaises(ValueError): self.check(bad, selection, bad[0]['handPoint'])
        stale = copy.deepcopy(value); stale['server']['token'] = '87654321-1234-1234-1234-123456789abc'
        with self.assertRaises(ValueError): self.check(segments, selection, stale)
        with self.assertRaises(ValueError): verifier.check_hand_point(segments, selection, '')
        with self.assertRaises(ValueError): self.check(segments, dict(kind='sp', options=selection['options']), value)
        with self.assertRaises(ValueError): self.check(segments, dict(kind='mp'), value)
        self.assertIsNone(verifier.check_hand_point([dict(segment='reorder-two')], dict(kind='mp'), ''))

    def test_observation_selection_is_host_only_and_strictly_opt_in(self):
        selection = dict(kind='mp', mode='toolkit', clients=1, languages=['EN'], cases=['equip-edit'], mods=adapter.MODS,
                         options=dict(mp_host=True, equip_host_observation=True))
        adapter.validate(selection)
        for change in (dict(kind='sp'), dict(cases=[adapter.CASES[0]]), dict(options=dict(mp_host=True, equip_host_observation=1))):
            with self.subTest(change=change), self.assertRaises(ValueError): adapter.validate(dict(selection, **change))

    def test_optional_fixture_waits_for_real_receipt_and_rejects_late_reply(self):
        from lupa.lua51 import LuaRuntime
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().path = str(PROJECT / 'tests/native_queue/magazine-unload/shared/QueueEquipHostPoint.lua')
        lua.execute(r"""
local function event() return {Add=function(fn) receive=fn end} end
Events={OnServerCommand=event()}
package.preload.QueueTestSelection=function()return{kind='mp',cases={'equip-edit'},options={equip_host_observation=true}}end
package.preload.QueueHealthEvents=function()return{}end
function isServer()return false end
function isClient()return true end
function sendClientCommand(module,command,args) sent={module=module,command=command,args=args};calls=(calls or 0)+1 end
local current={character={getOnlineID=function()return 7 end}}
local receipt={transaction=-126,token='12345678-1234-1234-1234-123456789abc',kind='ISReadABook'}
local available=false;local active=true
PZSurvivorToolkit={ActionQueueAcknowledgements={capture=function(a)assert(a==current);if available then return receipt end end,
 state=function(a,r)assert(a==current and r==receipt);if active then return 'started' end end}}
local H=dofile(path);local function hands()return{primary=false,secondary=false}end
assert(not H.poll(current,'reorder-two',hands)and not sent)
available=true;assert(not H.poll(current,'reorder-two',hands)and calls==1)
assert(not H.poll(current,'reorder-two',hands)and calls==1)
local point={schema=1,scope='server-native-active-action-point',player=7,transaction=-126,token=receipt.token,kind=receipt.kind,state='accepted',
 packetCorrelated=false,rootMembershipVerified=false,effectsVerified=false,editAuthority=false,primaryId=false,secondaryId=false}
receive('EquipEditPointTest','Observed',{segment='reorder-two',query=sent.args,point=point})
active=false;assert(not pcall(H.poll,current,'reorder-two',hands),'late receipt accepted after native episode changed')
active=true;assert(H.poll(current,'reorder-two',hands)and H.result().authority==false)
""")


if __name__ == '__main__': unittest.main()
