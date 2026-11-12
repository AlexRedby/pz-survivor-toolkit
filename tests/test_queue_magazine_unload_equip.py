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
    selection = dict(kind=kind, mode=mode)
    editing = kind == 'sp' and mode == 'toolkit'
    types = dict(front='Base.BookCarpentry1', tail='Base.BookFirstAid1', a='Base.Hammer' if segment == 'component-guard' else 'Base.Nails', b='Base.Screwdriver', c='Base.Screwdriver', bag='Base.Bag_Schoolbag', marker='Base.Nails')
    if segment in ('dependent', 'capacity'): types['nested'] = 'Base.Plank' if segment == 'capacity' else 'Base.Pencil'
    if segment == 'capacity': types['heldBag'] = 'Base.Bag_Schoolbag'
    items = {}
    for index, (name, full_type) in enumerate(types.items(), 10):
        class_name = 'Literature' if name in ('front', 'tail') else 'InventoryContainer' if name in ('bag', 'heldBag') else 'HandWeapon' if name in ('b', 'c', 'nested') or name == 'a' and segment == 'component-guard' else 'ComboItem'
        items[name] = dict(id=index, type=full_type, **{'class': class_name})
        if name in ('front', 'tail'): items[name]['pages'] = 100
    inventory = []
    for name, spec in items.items():
        path = [items['bag']['id']] if name == 'marker' or name == 'nested' and segment == 'dependent' else [items['heldBag']['id']] if name == 'nested' else []
        inventory.append(dict(id=spec['id'], type=spec['type'], path=path, condition=10, count=5 if spec['type'] == 'Base.Nails' else 1, uses=1, **{'class': spec['class']}))
    origin = dict(x=11, y=20, z=0)
    ids = dict(case='equip-edit', segment=segment, mode=mode, kind=kind, origin=origin, items=items,
               placementProof=placement_proof(origin, 'replica' if kind == 'mp' else 'local'), inventory=inventory)
    def snapshot(final=False):
        rows = copy.deepcopy(inventory)
        books = {name: dict(id=items[name]['id'], present=True, root=True, total=100, pages=100 if final else 99, characterPages=100 if final else 99) for name in ('front', 'tail')}
        return dict(case='equip-edit', segment=segment, inventory=rows, books=books, backpack=True,
                    hands=verifier.expected_hands(ids, editing) if final else dict(primary=False, secondary=False))
    source = ['front', 'equip-a', 'equip-b'] + (['equip-c'] if segment in ('reorder-three', 'cancel') else []) + ['tail']
    if segment == 'dependent': source = ['front', 'transfer', 'equip-nested', 'tail']
    if segment == 'capacity': source = ['front', 'equip-bag', 'transfer', 'tail']
    order = list(source)
    if editing and segment == 'reorder-two': order = ['front', 'equip-b', 'equip-a', 'tail']
    elif editing and segment == 'reorder-three': order = ['front', 'equip-c', 'equip-a', 'equip-b', 'tail']
    elif editing and segment == 'cancel': order.remove('equip-c')
    commands = []
    for name in source:
        item_name = name.removeprefix('equip-')
        if name == 'transfer': item_name = 'nested'
        if name == 'equip-bag': item_name = 'heldBag'
        row = dict(name=name, type='ISEquipWeaponAction' if name.startswith('equip-') else 'ISInventoryTransferAction' if name == 'transfer' else 'ISReadABook',
                   item=items[item_name]['id'], duration=50 if name.startswith('equip-') else -1 if name == 'transfer' and kind == 'mp' else 100, callbacksUntouched=True,
                   lifecycle=[], started=name in order, progress=name in order)
        if name.startswith('equip-'):
            row.update(primary=not (segment == 'reorder-three' and name in ('equip-a', 'equip-c') or segment == 'cancel' and name == 'equip-b'), twoHands=False, maxTimeInit=50)
        if name not in order: row.update(cancelled=True, started=False, progress=False)
        commands.append(row)
    serial = 0; hands = dict(primary=False, secondary=False); transferred = False
    for episode, name in enumerate(order, 1):
        command = next(value for value in commands if value['name'] == name)
        events = [('admission', False), ('begin', 'perform'), ('finish', 'perform')]
        if kind == 'sp': events += [('begin', 'complete'), ('finish', 'complete')]
        for event, phase in events:
            serial += 1
            if command['type'] == 'ISInventoryTransferAction' and event == 'finish' and phase == 'complete': transferred = True
            if command['type'] == 'ISEquipWeaponAction' and event == 'finish' and phase == 'complete': hands['primary' if command['primary'] else 'secondary'] = command['item']
            item_name = name.removeprefix('equip-')
            if name == 'transfer': item_name = 'nested'
            if name == 'equip-bag': item_name = 'heldBag'
            nested = item_name == 'nested' and not transferred
            location = dict(root=not nested, containerPresent=True, owner=items['bag' if segment == 'dependent' else 'heldBag']['id'] if nested else False)
            command['lifecycle'].append(dict(sequence=serial, event=event, phase=phase, succeeded=event == 'finish',
                nativeEpisode=episode, nativeClass='LuaTimedActionNew', hands=copy.deepcopy(hands), itemLocation=location))
    edits = []
    if mode == 'toolkit':
        names = ['reorder'] if segment.startswith('reorder-') else ['cancel'] if segment == 'cancel' else ['unavailable-input', 'dependent-transfer'] if segment == 'dependent' else ['component-reorder', 'component-cancel'] if segment == 'component-guard' else ['capacity-transfer', 'capacity-cancel']
        for name in names:
            allowed = editing and segment in ('reorder-two', 'reorder-three', 'cancel')
            edits.append(dict(name=name, allowed=allowed, reason=False if allowed else 'unavailable', queueBefore=source, queueAfter=order if allowed else source))
    final = snapshot(True)
    row = dict(segment=segment, ids=copy.deepcopy(ids), input=snapshot(), clientPlacement=placement_proof(origin),
               client=copy.deepcopy(final), server=copy.deepcopy(final), commands=commands, edits=edits,
               componentGuard=dict(item=items['a']['id'], size=2, quiet=False, components=[dict(index=0, type='Attributes', **{'class': 'Attributes'}), dict(index=1, type='Script', **{'class': 'EntityScriptInfo'})]) if segment == 'component-guard' else False,
               pendingBefore=snapshot(), pendingAfter=snapshot(), pendingOrder=order, queueIdle=True, tidyQuiescent=True,
               tidyObservation=dict(sourceVerified=True, integrationInstalled=True, idlePlayerUpdates=6, observer='ActionQueueSettlement.operationState', retainedOperations=0, observedBorrowings=0, outstandingBorrowings=0, activeBlockedReturn=False, privateTablesObserved=False), settleMilliseconds=1000, frameCadence=dict(count=2, totalMilliseconds=33, maxMilliseconds=17))
    return row, selection, ids, final


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
package.preload.QueueMagazineUnload=function()return{equal=equal,hands=function()return{primary=false,secondary=false}end}end
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
 function p:getPrimaryHandItem()end
 function p:getSecondaryHandItem()end
 function p:getWornItem(slot)return self.worn[slot]end
 function p:setWornItem(slot,item)self.worn[slot]=item end
 function p:setAlreadyReadPages(kind,pages)self.read[kind]=pages end
 function p:getAlreadyReadPages(kind)return self.read[kind]end
 function p:setPerkLevelDebug()end;return p
end
local fixture=assert(loadfile(fixture_path))()
for _,segment in ipairs(fixture.segments)do
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

    def test_host_cannot_inherit_sp_rights_and_denials_cannot_reorder(self):
        values = evidence(kind='mp'); values[0]['edits'][0]['allowed'] = True
        self.assertTrue(verifier.check_segment(*values))
        values = evidence(kind='mp'); values[0]['edits'][0]['reason'] = 'bogus-denial'
        self.assertTrue(verifier.check_segment(*values))
        for segment, reason in (('reorder-two', 'move_dependent'), ('cancel', 'operation_dependent')):
            values = evidence(segment, kind='mp'); values[0]['edits'][0]['reason'] = reason
            self.assertEqual([], verifier.check_segment(*values))
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
        track = source[source.index('local function track(name,action)'):source.index('local function book(name)')]
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
        for kind in ('sp', 'mp'):
            selection = dict(kind=kind, mode='toolkit', cases=['equip-edit'])
            client = ['[QUEUE_TEST] ' + marker for marker in ('VOICE_DISABLED', 'DISPLAY_READY', 'PREFLIGHT_COMPLETE', 'NATIVE_CONNECTED' if kind == 'mp' else 'TRUE_SP')]
            authority = ['[STARTUP_TEST] SERVER_READY']
            group = []
            for segment in verifier.SEGMENTS:
                row, _, ids, final = evidence(segment, kind)
                group.append(row)
                client.append(verifier.PREFIX + 'CLIENT_PLACEMENT ' + json.dumps(dict(case='equip-edit', segment=segment, proof=row['clientPlacement'])))
                authority.extend([verifier.PREFIX + 'PREPARED ' + json.dumps(ids), verifier.PREFIX + 'VERIFIED ' + json.dumps(final)])
            client.extend(['[QUEUE_CHECK] ' + json.dumps(dict(suite='magazine-unload', event='setup', cases=['equip-edit'], segments=verifier.SEGMENTS, queueEnabled=True, nativeDurations=True)),
                           '[QUEUE_CHECK] ' + json.dumps(dict(suite='magazine-unload', event='case', id='equip-edit', status='passed', actor='client1', kind=kind, mode='toolkit', segments=group, queueIdle=True, tidyQuiescent=True)),
                           '[QUEUE_CHECK] ' + json.dumps(dict(suite='magazine-unload', event='complete', cases=['equip-edit'], performed=1, failed=0, skipped=0)),
                           adapter.PREFIX + 'COMPLETE ' + json.dumps(dict(cases=['equip-edit']))])
            if kind == 'sp': client += authority
            with tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary); (root / 'client1-launch.log').write_text('\n'.join(client)); (root / 'server-launch.log').write_text('\n'.join(authority))
                result = adapter.verify(root, selection, {})
                self.assertEqual([], result['issues'])
                outcome = result['outcomes'][0]['outcome']
                self.assertIs(outcome['pendingEditsVerified'], kind == 'sp')
                self.assertIs(outcome['pendingProtectionVerified'], True)
                # Drive the real scenario matrix using the verifier's current
                # outcome fields. A clean Host denial cannot become positive
                # cancellation/reorder coverage.
                from queue_checks import scenarios
                suite = adapter.definitions()['magazine-unload']
                coverage = dict(result['outcomes'][0], suite='magazine-unload', kind=kind, mode='toolkit')
                reports = [dict(status='passed', selection=dict(mods=adapter.MODS), coverage=[coverage])]
                def case_matrix(catalog, matching):
                    return dict(rows=[dict(suite='magazine-unload', case='equip-edit', kind=kind, mode='toolkit', status='passed', evidence=[coverage])])
                matrix = scenarios.matrix(dict(suites={'magazine-unload': suite}), reports, case_matrix)
                mapped = {value['scenario']: value for value in matrix if value['action'] == 'native-equip-edit' and value['kind'] == kind and value['mode'] == 'toolkit'}
                for positive in ('cancel-waiting', 'move-independent'):
                    self.assertEqual('passed' if kind == 'sp' else 'missing-evidence', mapped[positive]['status'])
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


if __name__ == '__main__': unittest.main()
