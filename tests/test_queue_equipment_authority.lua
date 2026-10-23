isClient,isServer=function() return false end,function() return false end
local function load(name)
 return assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/shared/'..name..'.lua'))()
end
local modules={QueueEquipmentSlots=load('QueueEquipmentSlots'),QueueEquipmentFloor=load('QueueEquipmentFloor'),QueueEquipmentBulk=load('QueueEquipmentBulk'),QueueEquipmentClothing=load('QueueEquipmentClothing'),QueueEquipmentHotbar=load('QueueEquipmentHotbar')}
-- Generic consumers call these predicates for every equipment case; only
-- configuration consumers may assert that their state belongs to Clothing.
for _,id in ipairs({'hands-chain','hotbar-chain','tidy-hotbar','not-a-case'})do
 local clothing=modules.QueueEquipmentClothing
 assert(not clothing.isCase(id))
 for _,name in ipairs({'overlap','removes','headwear','desired'})do
  local ok,value=pcall(clothing[name],{id=id})
  assert(ok and value==false,'non-clothing predicate raised or matched '..id..' '..name)
 end
 assert(not pcall(clothing.spec,{id=id}),'unknown clothing configuration must remain strict')
end
for _,name in ipairs({'overlap','removes','headwear','desired'})do
 assert(modules.QueueEquipmentClothing[name]({})==false,'missing case ID must not match a clothing predicate')
end
require=function(name) return assert(modules[name],name) end
local Fixture=load('QueueEquipmentFixture')
local function book(pages)
 return {getAlreadyReadPages=function() return pages end,getNumberOfPages=function() return 10 end}
end
local attached,old={slot=1,kind='Back',model='Shovel Back with Bag'},{slot=-1}
for _,item in ipairs({attached,old}) do
 item.getAttachedSlot=function(self) return self.slot end
 item.getAttachedSlotType=function(self) return self.kind end
 item.getAttachedToModel=function(self) return self.model end
end
local hammer,screwdriver={},{}
local state={id='hotbar-chain',hammer=hammer,screwdriver=screwdriver,front=book(10),tail=book(10),
 hotbarReplacement=attached,hotbarInitial=old,hotbarLocation='Shovel Back with Bag',hotbarType='Back',hotbarIndex=1}
state.player={getPrimaryHandItem=function() return hammer end,getSecondaryHandItem=function() return screwdriver end,
 getAttachedItems=function() return {getItem=function(_,slot) assert(slot==state.hotbarLocation);return attached end} end}
assert(Fixture.settled(state,'toolkit'),'complete server attachment should settle')
for _,key in ipairs({'slot','kind','model'}) do
 local expected=attached[key];attached[key]=key=='slot' and -1 or nil
 assert(not Fixture.settled(state,'toolkit'),'attachment identity arrived before '..key)
 attached[key]=expected
end
for key,value in pairs({slot=1,kind='Back',model=state.hotbarLocation}) do
 local expected=old[key];old[key]=value
 assert(not Fixture.settled(state,'toolkit'),'old attachment cleanup fields have not converged '..key)
 old[key]=expected
end
old.kind='';old.model='';assert(Fixture.settled(state,'toolkit'),'native wire normalizes absent strings to empty');old.kind=nil;old.model=nil
state.tail=book(9);assert(not Fixture.settled(state,'toolkit'),'tail must finish on server')
assert(Fixture.settled(state,'toolkit',true),'checkpoint precedes tail completion')
state.front=book(9);assert(not Fixture.settled(state,'toolkit',true),'checkpoint still requires completed front')
state.front=book(10);state.tail=book(10)
-- Checkpoint hands use the same selector as the final clothing proof for
-- each overlap. The independent read tail can finish only after checkpoint.
for _,id in ipairs({'tidy-clothing-overlap','tidy-clothing-overlap-primary','tidy-clothing-overlap-both',
 'tidy-clothing-held-primary','tidy-clothing-held-secondary','tidy-clothing-held-both'})do
 local clothing=modules.QueueEquipmentClothing
 local socks={};local sample={id=id,hammer=hammer,screwdriver=screwdriver,clothingItem=socks,
  clothingLocation='base:socks',clothingHair='CrewCut',front=book(10),tail=book(9)}
 local primary,secondary=clothing.expectedHands(sample,false)
 sample.player={getPrimaryHandItem=function()return primary end,getSecondaryHandItem=function()return secondary end,
  getWornItem=function()return clothing.removes(sample)and socks or nil end,getHumanVisual=function()return {getHairModel=function()return 'CrewCut'end}end}
 assert(Fixture.settled(sample,'toolkit',true),'selected native overlap must satisfy checkpoint '..id)
 assert(not Fixture.settled(sample,'toolkit'),'overlap must preserve independent unfinished tail '..id)
 local expected=primary;primary=primary==socks and hammer or socks;assert(not Fixture.settled(sample,'toolkit',true));primary=expected
 expected=secondary;secondary=secondary==socks and screwdriver or socks;assert(not Fixture.settled(sample,'toolkit',true));secondary=expected
 sample.tail=book(10);assert(Fixture.settled(sample,'toolkit'))
 local finalPrimary,finalSecondary=clothing.expectedHands(sample,true)
 if not clothing.desired(sample)then assert(finalPrimary==hammer and finalSecondary==screwdriver,'P4 hand restore expectation differs '..id)
 else
  local slot=clothing.overlapHand(sample)
  assert(finalPrimary==((slot=='primary'or slot=='both')and socks or hammer)
   and finalSecondary==((slot=='secondary'or slot=='both')and socks or screwdriver),'P4 desired baseline differs '..id)
 end
end
local inventory={}
local item={getID=function() return 21 end}
local values={size=function() return #inventory end,get=function(_,i) return inventory[i+1] end}
state.player.getInventory=function() return {getItems=function() return values end} end
instanceof=function() return false end
local ids={items={hammer=21},originalWorn={}}
assert(not Fixture.available(state.player,ids),'delayed item replication must wait')
inventory[1]=item;assert(Fixture.available(state.player,ids),'exact replicated ID should become ready')
print('Equipment authority checks passed: delayed IDs, split attachment packets, detach metadata and reading tail.')

local original={getID=function() return 21 end,getFullType=function() return 'Base.Hammer' end}
item.getFullType=function() return 'Base.Hammer' end
local remote={player=state.player,id='hands-chain',items={hammer=original},owned={original}}
isClient=function() return true end
Fixture.refresh(remote)
assert(remote.hammer==item and remote.owned[1]==item,'native replicated object must resolve by exact ID')
inventory[1]={getID=function() return 21 end,getFullType=function() return 'Base.Plank' end}
assert(not pcall(Fixture.refresh,remote),'same ID with changed type must fail')

local position={}
local relocated={teleportTo=function(_,x,y,z) assert(x==10 and y==20 and z==0) end,
 setCurrentSquareFromPosition=function() position.refreshed=true end}
for _,key in ipairs({'X','Y','Z','LastX','LastY','LastZ'}) do relocated['set'..key]=function(_,value) position[key]=value end end
Fixture.relocate(relocated,{x=10.5,y=20.5,z=0})
assert(position.X==position.LastX and position.Y==position.LastY and position.Z==position.LastZ and position.refreshed,
 'fixture relocation must not manufacture a half-tile movement delta')

isClient,isServer=function() return false end,function() return false end
local source,root,floor={},{},{}
local owned,original,events={getItemContainer=function() return source end},{},{}
local releasePlayer={removeFromHands=function(_,value) assert(value==owned);events[#events+1]='hands' end,
 removeWornItem=function(_,value) assert(value==owned);events[#events+1]='worn' end,
 setWornItem=function(_,location,value) assert(location=='Back' and value==original) end,
 setPrimaryHandItem=function(_,value) assert(value==original) end,setSecondaryHandItem=function(_,value) assert(value==nil) end,
 getPlayerNum=function() return 0 end}
instanceof=function(item,kind) return item==owned and kind=='InventoryContainer' end
local function page(target)
 return {forceSelectedContainer=source,inventoryPane={inventory=source},
  setForceSelectedContainer=function(self,value) assert(value==nil);self.forceSelectedContainer=value end,
  setNewContainer=function(self,value) assert(value==target);self.inventoryPane.inventory=value end,
  refreshBackpacks=function(self) assert(not self.forceSelectedContainer and self.inventoryPane.inventory==target);events[#events+1]='ui' end}
end
getPlayerInventory=function() return page(root) end
getPlayerLoot=function() return page(floor) end
ISInventoryPage={GetFloorContainer=function() return floor end}
Fixture.release({id='hands-chain',player=releasePlayer,root=root,owned={owned},originalWorn={Back=original},originalPrimary=original})
assert(table.concat(events,',')=='hands,worn,ui,ui','release both equipment views before authoritative inventory deletion')
instanceof=function() return false end
inventory[1]=item
assert(not Fixture.removed({player=state.player,owned={item}}),'cleanup command must not mask pending removal packets')
inventory[1]=nil
assert(Fixture.removed({player=state.player,owned={item}}),'actual authoritative inventory deletion should settle')
local belt={getID=function() return 23 end,getBodyLocation=function() return 'BELT' end}
local replicatedBelt={getID=belt.getID}
state.player.getWornItem=function() return replicatedBelt end
assert(not Fixture.removed({player=state.player,owned={},belt=belt}),
 'inventory deletion must not mask a stale replicated worn belt with the same exact ID')
state.player.getWornItem=function() return nil end
assert(Fixture.removed({player=state.player,owned={},belt=belt}),'authoritative worn belt removal should settle')

local checked={}
isItemTransactionDone=function(id) checked[id]=true;return id~=-17 end
assert(not Fixture.transactionsSettled(),'a pending native transfer must block verification/deletion')
isItemTransactionDone=function(id) checked[id]=true;return true end
assert(Fixture.transactionsSettled(),'all native transfers should settle')
assert(not checked[0],'native zero is not a transaction ID')
for id=-128,127 do assert(id==0 or checked[id],'native signed byte ID missed') end
isServer=function() return true end
assert(not pcall(Fixture.transactionsSettled),'server must reject the client-only native query without its probe')
equipmentNativeTransferCount=function() return -1 end
assert(not pcall(Fixture.transactionsSettled),'unreadable native manager cannot be treated as idle')
equipmentNativeTransferCount=function() return 1 end
assert(not Fixture.transactionsSettled(),'real server pending transfer must hold its containers alive')
equipmentNativeTransferCount=function() return 0 end
assert(Fixture.transactionsSettled(),'idle server manager permits verification and cleanup')

local worldPresent=true
function getCell() return {getGridSquare=function()return {getWorldObjects=function()return {
 size=function()return worldPresent and 1 or 0 end,get=function()return {getItem=function()return item end}end
}end}end}end
for _,id in ipairs({'floor-pickup','tidy-floor'})do
 local floorState={id=id,player=state.player,owned={item},floor={id=item:getID(),x=1,y=2,z=0}}
 worldPresent=true
 assert(not Fixture.removed(floorState),'floor removal packet must arrive before next fixture')
 worldPresent=false;assert(Fixture.removed(floorState))
end

-- A Host unequip can reach client perform after its server effect; SP cannot.
local function exact(id)
 return {getID=function()return id end,getFullType=function()return 'Base.Pistol' end}
end
local gun,other=exact(31),exact(32)
for _,case in ipairs({{kind='sp',held=gun,ok=true},{kind='sp',ok=false},
 {kind='mp',held=gun,ok=true},{kind='mp',ok=true},{kind='mp',held=other,ok=false},
 {kind='mp',secondary=gun,ok=false}})do
 local player={getPrimaryHandItem=function()return case.held end,getSecondaryHandItem=function()return case.secondary end}
 local action={Type='ISUnequipAction',item=gun,character=player,action={},toolkitQueueOperation={}}
 local queue={current=action,queue={action}}
 ISTimedActionQueue={queues={[player]=queue}}
 local lifecycle={begin=function()return true end,current=function()return action end,
  finish=function()end,flush=function()end}
 local toolkit={ActionQueueLifecycle=lifecycle,ActionQueueOperations={perform=function()end,deferCompletion=function()end},
  ActionQueueDefinitions={inspect=function()return {},'compat.tidy-equipment' end},
  ActionQueuePolicy={evaluateCancel=function()return {allowed=false}end},
  -- This test exercises hand-state validation only; the shared effect/return
  -- observers have their own actual-source and settlement suites.
  ActionQueueSettlement={captureEffect=function()end,confirmEffect=function()return false end},
  ActionQueueAcknowledgements={},ActionQueueTidyIntent={status=function()return true end},
  ActionQueueCompat={isInstalled=function()return true end,verifySources=function()return true end}}
 ISInventoryPaneContextMenu,ISInventoryPane={},{}
 getFilenameOfClosure=function()return 'fixture' end
 local observer=load('QueueEquipmentCompletion').observe(toolkit,{kind=case.kind,mode='toolkit'})
 observer.watch({id='tidy-empty-hands',pickup=gun,hammer=exact(33),screwdriver=exact(34),baseline={[31]=gun}})
 local ok=pcall(lifecycle.begin,action,'perform')
 assert(ok==case.ok,'unequip observer accepted wrong hand state or rejected replicated Host completion')
end

-- Overlap primary cleanup must retain the inactive Torch baseline. Other
-- shared hand scenarios still restore their explicitly active Torch baseline.
for _,case in ipairs({{id='tidy-clothing-overlap-primary',activated=false,ok=true},
 {id='tidy-clothing-overlap-both',activated=false,ok=true},
 {id='tidy-clothing-overlap-primary',activated=true,ok=false},
 {id='tidy-clothing-overlap-both',activated=true,ok=false},
 {id='tidy-hands',activated=true,ok=true},{id='tidy-hands',activated=false,ok=false}})do
 local torch=exact(41);local player={}
 local action={Type='P4RestoreAction',activated=case.activated,item=torch,character=player,action={},toolkitQueueOperation={}}
 local queue={current=action,queue={action}}
 ISTimedActionQueue={queues={[player]=queue}}
 local lifecycle={begin=function()return true end,current=function()return action end,finish=function()end,flush=function()end}
 local toolkit={ActionQueueLifecycle=lifecycle,ActionQueueOperations={perform=function()end,deferCompletion=function()end},
  ActionQueueDefinitions={inspect=function()return {},'compat.tidy-equipment'end},
  ActionQueuePolicy={evaluateCancel=function()return {allowed=false}end},
  ActionQueueSettlement={captureEffect=function()end,confirmEffect=function()return false end},
  ActionQueueAcknowledgements={},ActionQueueTidyIntent={status=function()return true end},
  ActionQueueCompat={isInstalled=function()return true end,verifySources=function()return true end}}
 local observer=load('QueueEquipmentCompletion').observe(toolkit,{kind='sp',mode='toolkit'})
 observer.watch({id=case.id,hammer=torch,screwdriver=exact(42),baseline={[41]=torch}})
 assert(pcall(lifecycle.begin,action,'perform')==case.ok,'wrong primary baseline activation accepted/rejected '..case.id)
end

-- Desired held+worn cleanup counts its exact socks Equip/P4 pair as shared
-- hands; Wear remains the separate clothing completion boundary.
do
 ISEquipWeaponAction={Type='ISEquipWeaponAction'};P4RestoreAction={Type='P4RestoreAction'};ISWearClothing={Type='ISWearClothing'}
 for _,caseID in ipairs({'tidy-clothing-held-primary','tidy-clothing-held-secondary','tidy-clothing-held-both',
  'tidy-watch-held-primary','tidy-watch-held-secondary','tidy-watch-held-both'})do
  for _,bad in ipairs({'none','item','primary','twoHands','activation'})do
   local socks,torch,screw=exact(51),exact(52),exact(53)
   local location=modules.QueueEquipmentClothing.spec({id=caseID}).location
   socks.getBodyLocation=function()return location end
   local root={};socks.getContainer=function()return root end
   local player={};local state={id=caseID,clothingItem=socks,clothingLocation=location,clothingRestoreType='ISWearClothing',
    hammer=torch,screwdriver=screw,player=player,root=root,baseline={[51]=socks,[52]=torch,[53]=screw}}
   local spec=modules.QueueEquipmentClothing.cleanupSpec(state)
   local actions={}
   for _,value in ipairs(spec)do
    actions[#actions+1]=setmetatable({Type=value.class.Type,item=value.item,primary=value.primary,twoHands=value.twoHands,
     activated=value.activated,character=player,action={},toolkitQueueOperation={}},value.class)
   end
   if bad=='item'then actions[1].item=torch
   elseif bad=='primary'then actions[1].primary=not actions[1].primary
   elseif bad=='twoHands'then actions[1].twoHands=not actions[1].twoHands
   elseif bad=='activation'then actions[2].activated=true end
   local queue={queue={}};ISTimedActionQueue={queues={[player]=queue}}
   local lifecycle={begin=function()return true end,current=function()return queue.current end,finish=function()end,flush=function()end}
   local toolkit={ActionQueueLifecycle=lifecycle,ActionQueueOperations={perform=function()end,deferCompletion=function()end},
    ActionQueueDefinitions={inspect=function()return {},'compat.tidy-equipment'end},
    ActionQueuePolicy={evaluateCancel=function()return {allowed=false}end},
    ActionQueueSettlement={captureEffect=function()end,confirmEffect=function()return false end},ActionQueueAcknowledgements={},
    ActionQueueTidyIntent={status=function()return true end},ActionQueueCompat={isInstalled=function()return true end,verifySources=function()return true end}}
   local observer=load('QueueEquipmentCompletion').observe(toolkit,{kind='sp',mode='toolkit'});observer.watch(state)
   local ok=pcall(function()
    for _,action in ipairs(actions)do queue.current=action;queue.queue={action};lifecycle.begin(action,'perform')end
   end)
   assert(ok==(bad=='none'),'desired shared cleanup accepted/rejected '..caseID..' '..bad)
  end
 end
end

-- Host snapshots can install the authority's fixture clothing before Prepared.
-- Keep the pre-fixture belt as exact baseline data across that ordering.
do
 local locations={['base:belt']=true,['base:back']=true,['base:shirt']=true}
 ItemBodyLocation={get=function(location)return locations[location]and location or nil end}
 ResourceLocation={of=function(location)return location end}
 Perks={Woodwork='Woodwork',Doctor='Doctor'}
 local nextID=1000
 local function values(items)
  return {size=function()return #items end,get=function(_,index)return items[index+1]end}
 end
 local makeItem
 local function container()
  local source={items={}}
  function source:getItems()return values(self.items)end
  function source:getCapacity()return 100 end
  function source:getEffectiveCapacity()return 100 end
  function source:setCapacity(value)assert(value==100)end
  function source:setExplored()end
  function source:AddItem(kind)nextID=nextID+1;return makeItem(self,nextID,kind)end
  function source:Remove(item)
   for index,value in ipairs(self.items)do if value==item then table.remove(self.items,index);item.container=nil;return end end
  end
  return source
 end
 makeItem=function(source,id,kind)
  local value={id=id,kind=kind,container=source,pages=0,slot=-1}
  function value:getID()return self.id end
  function value:getFullType()return self.kind end
  function value:getContainer()return self.container end
  function value:getNumberOfPages()return 100 end
  function value:getAlreadyReadPages()return self.pages end
  function value:setAlreadyReadPages(pages)self.pages=pages end
  function value:setFavorite(favorite)self.favorite=favorite end
  function value:getBodyLocation()return self.kind=='Base.Belt2'and 'base:belt' or 'base:shirt'end
  function value:setAttachedSlot(slot)self.slot=slot end
  function value:setAttachedSlotType(kind)self.slotType=kind end
  function value:setAttachedToModel(model)self.model=model end
  if kind=='Base.Bag_ALICEpack_Army'then
   value.source=container()
   function value:getItemContainer()return self.source end
   function value:canBeEquipped()return 'base:back'end
  end
  source.items[#source.items+1]=value;return value
 end
 instanceof=function(item,kind)return kind=='InventoryContainer'and item.source~=nil end
 local function player(root)
  local result={root=root,worn={}}
  function result:getInventory()return self.root end
  function result:getPrimaryHandItem()return self.primary end
  function result:getSecondaryHandItem()return self.secondary end
  function result:setPrimaryHandItem(item)self.primary=item end
  function result:setSecondaryHandItem(item)self.secondary=item end
  function result:removeFromHands(item)
   if self.primary==item then self.primary=nil end;if self.secondary==item then self.secondary=nil end
  end
  function result:getWornItem(location)return self.worn[location]end
  function result:setWornItem(location,item)self.worn[location]=item end
  function result:removeWornItem(item)
   for location,value in pairs(self.worn)do if value==item then self.worn[location]=nil end end
  end
  function result:getWornItems()
   local list={};for _,item in pairs(self.worn)do list[#list+1]=item end
   return {size=function()return #list end,getItemByIndex=function(_,index)return list[index+1]end,
    getLocation=function(_,item)for location,value in pairs(self.worn)do if value==item then return location end end end}
  end
  function result:getBodyLocationGroup()return {getLocation=function(_,location)return locations[location]end}end
  function result:getAttachedItems()return {size=function()return 0 end}end
  function result:removeAttachedItem()end
  function result:getXp()return {setXPToLevel=function()end}end
  function result:setPerkLevelDebug()end
  function result:getPerkLevel()return 0 end
  function result:setAlreadyReadPages()end
  function result:getPlayerNum()return 0 end
  return result
 end
 local function scan(source,result)
  result=result or {};for _,item in ipairs(source.items)do
   result[item.id]=item;if item.source then scan(item.source,result)end
  end;return result
 end
 local function clone(source)
  local result=container()
  for _,item in ipairs(source.items)do
   local copy=makeItem(result,item.id,item.kind);copy.pages=item.pages
   if item.source then copy.source=clone(item.source)end
  end
  return result
 end
 local server=player(container())
 local baselineBelt=makeItem(server.root,1,'Base.Belt2')
 local baselineShirt=makeItem(server.root,2,'Base.Shirt_FormalWhite')
 local spareBelt=makeItem(server.root,3,'Base.Belt2')
 server.worn={['base:belt']=baselineBelt,['base:shirt']=baselineShirt}
 isClient,isServer=function()return false end,function()return true end
 sendClothing=function()end
 local authority=Fixture.prepare(server,'belt-knife')
 local descriptor=Fixture.descriptor(authority)
 assert(#descriptor.originalWorn==2 and descriptor.originalWorn[1].location=='base:belt'
  and descriptor.originalWorn[1].id==1 and descriptor.originalWorn[1].fullType=='Base.Belt2')
 local client=player(clone(server.root));local actual=scan(client.root)
 -- Model the full server clothing snapshot arriving before the Prepared command.
 for location,item in pairs(server.worn)do client.worn[location]=actual[item.id]end
 client.primary,client.secondary=actual[authority.hammer.id],actual[authority.screwdriver.id]
 assert(client:getWornItem('base:belt')==actual[authority.belt.id]and actual[1]~=baselineBelt)
 assert(Fixture.available(client,descriptor),'baseline and owned IDs should become ready independently of worn snapshot order')
 local function malformed(change)
  local bad={items=descriptor.items,originalWorn={}}
  for i,record in ipairs(descriptor.originalWorn)do bad.originalWorn[i]={location=record.location,id=record.id,fullType=record.fullType}end
  change(bad)
  assert(not pcall(Fixture.available,client,bad),'invalid authoritative worn descriptor accepted')
  assert(client:getWornItem('base:belt')==actual[authority.belt.id]and scan(client.root)[1]==actual[1],
   'invalid descriptor must fail before changing any client item or worn slot')
 end
 malformed(function(bad)bad.originalWorn=nil end)
 malformed(function(bad)bad.originalWorn[1].fullType='Base.Hammer'end)
 malformed(function(bad)bad.originalWorn[1].id=authority.belt.id end)
 malformed(function(bad)bad.originalWorn[2].location='base:belt'end)
 malformed(function(bad)bad.originalWorn[2].id=1 end)
 malformed(function(bad)bad.originalWorn[1].location='base:unknown'end)
 malformed(function(bad)bad.originalWorn[1].extra=true end)
 malformed(function(bad)bad.originalWorn[1]=nil end)
 client.root:Remove(actual[1])
 assert(not Fixture.available(client,descriptor),'missing baseline belt must wait even when fixture items are present')
 local before=#client.root.items
 assert(not pcall(Fixture.prepare,client,'belt-knife',descriptor),'prepare cannot proceed without the exact baseline belt')
 assert(#client.root.items==before and client:getWornItem('base:belt')==actual[authority.belt.id])
 actual[1].container=client.root;client.root.items[#client.root.items+1]=actual[1]
 -- Client UI is only a view of the source containers in this fixture.
 local function page()
  return {inventoryPane={},setNewContainer=function(self,target)self.inventoryPane.inventory=target end,
   refreshBackpacks=function()end}
 end
 getPlayerInventory,getPlayerLoot=function()return page()end,function()return page()end
 ISInventoryPage={GetFloorContainer=function()return {}end}
 ISInventoryPaneContextMenu={getContainers=function()return {contains=function()return true end}end}
 getPlayerHotbar=function()return {reloadIcons=function()end}end
 isClient,isServer=function()return true end,function()return false end
 local adopted=Fixture.prepare(client,'belt-knife',descriptor)
 assert(adopted.originalWorn['base:belt']==actual[1]and adopted.originalWorn['base:shirt']==actual[2],
  'client must reconstruct original slots from exact authoritative inventory IDs')
 assert(adopted.expectedWorn['base:belt']==adopted.belt and adopted.original[adopted.belt.id]==nil)
 Fixture.release(adopted)
 assert(client:getWornItem('base:belt')==actual[1],'client release must restore baseline belt before deletion')
 for _,owned in ipairs(adopted.owned)do if owned.container then owned.container:Remove(owned)end end
 assert(Fixture.removed(adopted),'owned removal must settle with the baseline belt still worn')
 Fixture.cleanup(adopted)
 assert(client:getWornItem('base:belt')==actual[1]and client:getWornItem('base:shirt')==actual[2])
 local remaining=scan(client.root)
 assert(remaining[1]==actual[1]and remaining[2]==actual[2]and remaining[3]==actual[3])
 local count=0;for _ in pairs(remaining)do count=count+1 end;assert(count==3,'cleanup removed baseline inventory or left an owned item')
 -- An authority baseline with no Belt slot must still reject an unrelated worn belt.
 client:setWornItem('base:belt',actual[3])
 local empty={id='hands-chain',player=client,root=client.root,owned={},original=remaining,
  originalWorn={['base:shirt']=actual[2]},capacity=100,originalEffectiveCapacity=100}
 local ok,problem=pcall(Fixture.cleanup,empty)
 assert(not ok and tostring(problem):find('unexpected worn item at base:belt',1,true),
  'baseline transport must not weaken unexpected worn identity conservation')
 assert(scan(client.root)[3]==actual[3],'failed conservation check must not delete an unrelated belt')
end
print('Equipment authority worn baseline checks passed: pre-Prepared clothing snapshots, exact restoration and invalid descriptors.')

-- Load the real scene helper. The Java double keeps removeWornItem(false)
-- inventory-neutral and models native exclusive-slot removal.
do
 local Scene=load('QueueEquipmentScene')
 ItemBodyLocation={HAT='base:hat',FULL_HAT='base:fullhat',get=function(value)return value end}
 ResourceLocation={of=function(value)return value end}
 local group={isExclusive=function(_,target,location)
  return target=='base:leftwrist'and location=='base:forearmleft'
   or target=='base:rightwrist'and location=='base:forearmright'
   or target=='base:fullhat'and(location=='base:eyes'or location=='base:hat')
   or location=='base:fullhat'and(target=='base:eyes'or target=='base:hat')
 end}
 local calls,sync={},{}
 local function actor()
  local root={items={}}
  function root:getItems()return {size=function()return #self.items end,get=function(_,i)return self.items[i+1]end}end
  function root:getItemById(id)for _,item in ipairs(self.items)do if item.id==id then return item end end end
  local player={root=root,worn={}}
  function player:getInventory()return self.root end
  function player:getWornItem(location)return self.worn[location]end
  function player:getWornItems()
   local entries={};for location,item in pairs(self.worn)do
    local loc,value=location,item
    entries[#entries+1]={getLocation=function()return loc end,getItem=function()return value end}
   end
   return {size=function()return #entries end,get=function(_,i)return entries[i+1]end,
    getBodyLocationGroup=function()return group end,
    contains=function(_,item)for _,value in pairs(self.worn)do if item==value then return true end end;return false end}
  end
  function player:removeWornItem(item,drop)
   assert(drop==false,'scene must explicitly disable the native capacity/drop branch')
   calls[#calls+1]={player=self,item=item}
   local target;for location,value in pairs(self.worn)do if value==item then target=location end end
   assert(target)
   for location in pairs(self.worn)do if target==location or group:isExclusive(target,location)then self.worn[location]=nil end end
  end
  local function item(id,kind,location)
   local value={id=id,kind=kind,getID=function(self)return self.id end,
    getFullType=function(self)return self.kind end,getContainer=function()return root end}
   root.items[#root.items+1]=value;if location then player.worn[location]=value end;return value
  end
  local glasses=item(1666075715,'Base.Glasses_Cosmetic_Normal','base:eyes')
  local shirt=item(12,'Base.Shirt_FormalWhite','base:shirt')
  return player,glasses,shirt,item
 end
 isClient,isServer=function()return false end,function()return true end
 sendClothing=function(player,location,item)assert(item==nil);sync[#sync+1]={player=player,location=location}end
 local player,glasses,shirt,add=actor()
 assert(not Scene.needed({'unknown','hands-chain','tidy-clothing'}))
 assert(Scene.prepare(player,{'unknown','hands-chain'})==nil and #calls==0)
 local proof=Scene.prepare(player,{'tidy-clothing','tidy-headwear-hat-remove','tidy-headwear-full-hat-remove'})
 assert(proof.prepared and proof.rootRetained and proof.authority=='server'and #proof.normalizedItems==1)
 local record=proof.normalizedItems[1]
 assert(record.id==glasses.id and record.fullType==glasses.kind and record.location=='base:eyes')
 assert(#calls==1 and calls[1].item==glasses and #sync==1 and sync[1].location=='base:eyes')
 assert(#player.root.items==2 and player.root:getItemById(glasses.id)==glasses
  and player:getWornItem('base:eyes')==nil and player:getWornItem('base:shirt')==shirt)
 assert(Scene.available(player,proof),'declared baseline should become ready with exact retained glasses')
 local temporary=add(34,'Base.Hat_BoxingRed','base:fullhat')
 temporary.getBodyLocation=function()return 'base:fullhat'end
 local restoreIds={case='tidy-headwear-full-hat-restore',items={clothingItem=temporary.id}}
 assert(Scene.needed({'tidy-headwear-hat-restore'})and Scene.needed({'tidy-headwear-full-hat-restore'}))
 assert(Scene.available(player,proof,restoreIds),'restore may adopt only its exact authority-seeded worn headwear')
 local foreign=add(35,'Base.Other','base:hat')
 assert(not Scene.available(player,proof,restoreIds),'exact seeded target must not allow another conflicting slot')
 player.worn['base:hat']=nil
 temporary.kind='Base.Hat_Beany'
 assert(not Scene.available(player,proof,restoreIds),'restore must reject same-ID wrong type')
 temporary.kind='Base.Hat_BoxingRed'
 assert(Scene.prepare(player,{'tidy-headwear-full-hat-remove'})==proof and #calls==1
  and player:getWornItem('base:fullhat')==temporary,'scene must not normalize between tested actions')
 assert(not Scene.available(player,proof),'readiness must quietly wait for native clothing replication')
 player.worn['base:fullhat']=nil
 assert(not Scene.available(player,proof,restoreIds),'restore readiness must wait for authoritative worn state')
 isClient,isServer=function()return true end,function()return false end
 local client,clientGlasses=actor()
 assert(not Scene.available(client,proof)and client:getWornItem('base:eyes')==clientGlasses and #calls==1)
 assert(not pcall(Scene.prepare,client,{'tidy-headwear-hat-remove'})and #calls==1,'client cannot own scene edits')
 assert(Scene.prepare(client,{'unknown','hands-chain'})==nil and #calls==1)
 client.worn['base:eyes']=nil
 assert(Scene.available(client,proof),'client should adopt the authoritative scene after SyncClothing')
 glasses.kind='Base.Hammer'
 assert(not Scene.available(player,proof)and not pcall(Scene.proof,player),'same-ID changed type must fail conservation')
 glasses.kind='Base.Glasses_Cosmetic_Normal';table.remove(player.root.items,1)
 assert(not Scene.available(player,proof)and not pcall(Scene.proof,player),'lost starter item must fail conservation')
 isClient,isServer=function()return false end,function()return false end
 local sp=actor();local spProof=Scene.prepare(sp,{'tidy-headwear-full-hat-remove'})
 assert(spProof.authority=='sp'and Scene.available(sp,spProof)and #sync==1,'SP scene must not send a server clothing packet')
 for _,side in ipairs({'left','right'})do
  local watchPlayer,starterGlasses,starterShirt,seed=actor()
  local wrist='base:'..side..'wrist';local forearm='base:forearm'..side
  local guard=seed(77,'Base.ForearmGuard',forearm)
  local case='tidy-watch-'..(side=='left'and 'digital'or 'classic')..'-remove'
  assert(Scene.needed({case}))
  local watchProof=Scene.prepare(watchPlayer,{case})
  assert(#watchProof.targetLocations==1 and watchProof.targetLocations[1]==wrist)
  assert(#watchProof.normalizedItems==1 and watchProof.normalizedItems[1].id==guard.id
   and watchPlayer:getWornItem(forearm)==nil and watchPlayer:getWornItem('base:eyes')==starterGlasses
   and watchPlayer:getWornItem('base:shirt')==starterShirt,'watch scene must normalize only its selected wrist/exclusive forearm')
  assert(Scene.available(watchPlayer,watchProof,{case=case,items={}}))
  watchPlayer.worn[forearm]=guard
  assert(not Scene.available(watchPlayer,watchProof,{case=case,items={}}),'watch scene must await authority forearm removal')
  watchPlayer.worn[forearm]=nil
  assert(Scene.prepare(watchPlayer,{case})==watchProof,'watch scene must not reseed between cases')
 end
end
print('Equipment scene checks passed: real helper, starter glasses, root identity, once-only preparation and authority-owned SyncClothing.')

-- Exercise the real Fixture.prepare prefix: adopting the client fixture must
-- reach clothing validation without overwriting either authority-owned hand.
do
 local clothing=modules.QueueEquipmentClothing
 local prepare=clothing.prepare
 local originalClient,originalServer=isClient,isServer
 local itemKinds={front='Base.BookCarpentry1',tail='Base.BookFirstAid1',hammer='Base.Torch',screwdriver='Base.Screwdriver',
  bag='Base.Bag_Schoolbag',clothingItem='Base.Socks_Ankle'}
 for _,caseID in ipairs({'tidy-clothing-held-primary','tidy-clothing-held-secondary','tidy-clothing-held-both',
  'tidy-watch-held-primary','tidy-watch-held-secondary','tidy-watch-held-both'})do
  itemKinds.clothingItem=clothing.spec({id=caseID}).fullType
  local root={items={}}
  function root:getItems()return {size=function()return #self.items end,get=function(_,i)return self.items[i+1]end}end
  function root:getCapacity()return 100 end;function root:getEffectiveCapacity()return 100 end
  local ids={case=caseID,originalWorn={},items={}}
  local byName={}
  for name,kind in pairs(itemKinds)do
   local item={id=#root.items+1,kind=kind}
   function item:getID()return self.id end;function item:getFullType()return self.kind end
   function item:getContainer()return root end
   function item:canBeEquipped()return 'base:back'end
   function item:getItemContainer()return {}end
   root.items[#root.items+1]=item;byName[name]=item;ids.items[name]=item.id
  end
  local desiredPrimary,desiredSecondary=clothing.expectedHands({id=caseID,hammer=byName.hammer,screwdriver=byName.screwdriver,clothingItem=byName.clothingItem},true)
  local player={}
  function player:getInventory()return root end
  function player:getPrimaryHandItem()return desiredPrimary end;function player:getSecondaryHandItem()return desiredSecondary end
  function player:setPrimaryHandItem()error('Fixture.prepare repaired desired primary')end
  function player:setSecondaryHandItem()error('Fixture.prepare repaired desired secondary')end
  function player:setWornItem(location,item)assert(location=='base:back'and item==byName.bag)end
  function player:getPlayerNum()return 0 end
  getPlayerInventory=function()return {refreshBackpacks=function()end}end
  ISInventoryPaneContextMenu={getContainers=function()return {contains=function()return true end}end}
  isClient,isServer=function()return true end,function()return false end
  local reached=false
  clothing.prepare=function(state)
   assert(state.player:getPrimaryHandItem()==desiredPrimary and state.player:getSecondaryHandItem()==desiredSecondary)
   reached=true;error('clothing-prefix-complete')
  end
  local ok,problem=pcall(Fixture.prepare,player,caseID,ids)
  clothing.prepare=prepare
  assert(not ok and reached and tostring(problem):find('clothing-prefix-complete',1,true),
   'client desired fixture hand adoption guard failed '..caseID..' '..tostring(problem))
 end
 isClient,isServer=originalClient,originalServer
end
print('Equipment desired client adoption checks passed: real fixture preparation preserves both authoritative hands.')

-- Server ProcessItems sweeps may lag Wear by more than five seconds. The
-- authority receipt waits for native membership; the fixture never repairs it.
do
 local clothing=modules.QueueEquipmentClothing
 local beforeClient,beforeServer,beforeCell=isClient,isServer,getCell
 local active,pendingRemoval=true,false
 getCell=function()return {getProcessItems=function()return {contains=function()return active end}end,
  getProcessItemsRemove=function()return {contains=function()return pendingRemoval end}end}end
 isClient,isServer=function()return false end,function()return true end
 for _,alarm in ipairs({false,true})do
  local sample={id=alarm and 'tidy-watch-digital-restore'or 'tidy-watch-classic-restore',clothingItem={},clothingWatch={alarmSet=alarm}}
  for _,worn in ipairs({false,true})do
   local expected=alarm and worn
   active=not expected
   for tick=1,3 do assert(not clothing.watchProcessingReady(sample,worn),'server must await its native processing sweep')end
   active=expected
   assert(clothing.watchProcessingReady(sample,worn),'settled native processing membership must release the authority gate')
   pendingRemoval=true
   assert(not clothing.watchProcessingReady(sample,worn),'server must await pending native removal even with matching active membership')
   pendingRemoval=false
  end
 end
 local sample={id='tidy-watch-classic-restore',clothingItem={},clothingWatch={alarmSet=false}}
 active=true
 isServer=function()return false end
 assert(clothing.watchProcessingReady(sample,true),'SP must retain its already verified processing timing behavior')
 isClient,isServer,getCell=beforeClient,beforeServer,beforeCell
end
print('Equipment watch processing readiness: server passively waits for disabled/worn and enabled/removed sweeps; SP unchanged.')

-- Arm only once after exact root/worn/hand replication. These Java doubles
-- model the audited native trigger; the fixture itself calls real item:update.
do
 local clothing=modules.QueueEquipmentClothing
 local oldClient,oldServer,oldTime,oldInstanceof=isClient,isServer,getGameTime,instanceof
 local age=100.0
 getGameTime=function()return {getHour=function()return 9 end,getMinutes=function()return 23 end,getWorldAgeHours=function()return age end}end
 instanceof=function(item,kind)return item.watch and(kind=='Clothing'or kind=='AlarmClockClothing')end
 isClient=function()return false end
 for _,server in ipairs({false,true})do
 isServer=function()return server end
 for _,id in ipairs({'tidy-watch-ringing-restore','tidy-watch-ringing-remove','tidy-watch-ringing-overlap-both','tidy-watch-ringing-held-both'})do
  age=100.0
  local spec=clothing.spec({id=id});local root={};local setters,updates,syncStops=0,0,0
  local watch={watch=true,hour=21,minute=40,alarm=true,ringing=false,force=-1}
  function watch:getID()return 701 end;function watch:getFullType()return spec.fullType end
  function watch:getBodyLocation()return spec.location end;function watch:getCategory()return 'AlarmClock'end
  function watch:getContainer()return root end
  function watch:getHour()return self.hour end;function watch:getMinute()return self.minute end
  function watch:isAlarmSet()return self.alarm end;function watch:isRinging()return self.ringing end
  function watch:setAlarmSet(value)setters=setters+1;self.alarm=value;self.ringing=false;self.force=20 end
  function watch:setHour(value)setters=setters+1;self.hour=value;self.force=-1 end
  function watch:setMinute(value)setters=setters+1;self.minute=value;self.force=-1 end
  function watch:setForceDontRing(value)setters=setters+1;self.force=value end
  function watch:update()
   updates=updates+1
   if self.alarm and self.hour==9 and self.minute==(server and 20 or 23)and self.force~=20 then self.ringing=true end
  end
  function watch:stopRinging()self.ringing=false end
  function watch:syncStopRinging()syncStops=syncStops+1 end
  local hammer={getID=function()return 702 end,getFullType=function()return 'Base.Torch'end,getContainer=function()return root end}
  local screw={getID=function()return 703 end,getFullType=function()return 'Base.Screwdriver'end,getContainer=function()return root end}
  function root:getItemById(value)return value==701 and watch or value==702 and hammer or value==703 and screw or nil end
  local sample={id=id,root=root,clothingItem=watch,clothingLocation=spec.location,clothingHair='CrewCut',clothingRingPending=true,
   clothingWatch={alarmHour=21,alarmMinute=40,alarmSet=true,ringing=false},hammer=hammer,screwdriver=screw}
  local primary,secondary=clothing.expectedHands(sample,true)
  local worn=not clothing.removes(sample)and watch or nil
  sample.player={getInventory=function()return root end,getPrimaryHandItem=function()return primary end,getSecondaryHandItem=function()return secondary end,
   getWornItem=function()return worn end,getHumanVisual=function()return {getHairModel=function()return 'CrewCut'end,getNonAttachedHair=function()end}end}
  assert(not pcall(clothing.armRing,sample,999)and setters==0,'wrong ring ID must fail before native setters')
  sample.clothingSetupPending=true
  assert(not pcall(clothing.armRing,sample,701)and setters==0,'ring must await root-before-worn setup')
  sample.clothingSetupPending=nil
  isClient=function()return true end
  assert(not pcall(clothing.armRing,sample,701)and setters==0,'client must never repair or arm a ring')
  isClient=function()return false end
  clothing.armRing(sample,701)
  assert(updates==1 and setters==4 and watch:isRinging()and sample.clothingWatch.ringing and not sample.clothingRingPending)
  assert(not pcall(clothing.armRing,sample,701)and updates==1 and setters==4,'duplicate or stale ring arm must not retrigger')
  local ids={case=id,items={clothingItem=701,hammer=702,screwdriver=703},clothingHair='CrewCut',clothingWatch=sample.clothingWatch,
   clothingWatchStartedAge=sample.clothingWatchStartedAge}
  watch.ringing=false
  assert(not clothing.available(sample.player,ids)and not clothing.watchMatches(sample)and setters==4,'ring convergence must quietly wait without repair')
  watch.ringing=true;age=100.1
  assert(clothing.available(sample.player,ids)and clothing.watchTiming(sample).observedAgeHours==age)
  age=100.5;assert(not pcall(clothing.watchTiming,sample),'half-hour lifetime boundary must not be claimed as persistent ring')
  age=100.1
  local cleanup=clothing.stopRing(sample)
  assert(cleanup.id==701 and not cleanup.watch.ringing and cleanup.watch.alarmSet and syncStops==(server and 1 or 0)and setters==4)
  assert(clothing.stopRing(sample)==nil and syncStops==(server and 1 or 0),'fixture cleanup must stop its exact watch once only')
 end
 end
 isClient,isServer,getGameTime,instanceof=oldClient,oldServer,oldTime,oldInstanceof
end
print('Equipment native ring protocol: root-ready once-only native trigger, quiet convergence, lifetime bound and logical cleanup stop passed.')

-- Exclusive cleanup prefixes are clothing boundaries, never synthetic hand
-- restores. Drive the real observer through native perform/complete/flush.
do
 local clothing=modules.QueueEquipmentClothing
 local oldMods=getActivatedMods
 getActivatedMods=function()return {contains=function(_,name)return name=='P4TidyUpMeister'end}end
 ISUnequipAction=ISUnequipAction or {Type='ISUnequipAction'}
 ISWearClothing=ISWearClothing or {Type='ISWearClothing'}
 for _,kind in ipairs({'sp','mp'})do
  for _,id in ipairs({'tidy-clothing-replace','tidy-headwear-hat-exclusive','tidy-headwear-full-hat-exclusive'})do
   local spec=clothing.spec({id=id});local root={};local player={getCharacterActions=function()return {contains=function()return false end}end}
   local function garment(number,fullType,location)
    return {getID=function()return number end,getFullType=function()return fullType end,getContainer=function()return root end,
     getBodyLocation=function()return location end}
   end
   local baseline=garment(901,spec.fullType,spec.location);local temp=garment(902,spec.temporaryType,spec.temporaryLocation)
   local sample={id=id,player=player,root=root,clothingItem=baseline,clothingTemporary=temp,clothingLocation=spec.location,
    baseline={[901]=baseline,[902]=temp}}
   local queue={character=player,queue={}}
   ISTimedActionQueue={queues={[player]=queue}}
   local lifecycle={begin=function()return true end,current=function()return queue.current end,finish=function()end,
    flush=function(value)return 'completed',value.current end}
   local toolkit={ActionQueueLifecycle=lifecycle,ActionQueueOperations={perform=function()end,deferCompletion=function()return false end},
    ActionQueueDefinitions={inspect=function()return {},'compat.tidy-equipment'end},
    ActionQueuePolicy={evaluateCancel=function()return {allowed=false}end},
    ActionQueueSettlement={captureEffect=function()end,confirmEffect=function()return false end},ActionQueueAcknowledgements={},
    ActionQueueTidyIntent={status=function()return true end},ActionQueueCompat={isInstalled=function()return true end,verifySources=function()return true end}}
   local observer=load('QueueEquipmentCompletion').observe(toolkit,{kind=kind,mode='toolkit'});observer.watch(sample)
   local specs=clothing.cleanupSpec(sample)
   for _,row in ipairs(specs)do
    local action=setmetatable({Type=row.class.Type,item=row.item,character=player,action={},toolkitQueueOperation={}},row.class)
    queue.current=action;queue.queue={action}
    lifecycle.begin(action,'perform');lifecycle.finish(action,'perform',true)
    if kind=='sp'then lifecycle.begin(action,'complete');lifecycle.finish(action,'complete',true)end
    lifecycle.flush(queue)
   end
   local observed=observer.clothing();local hands=observer.restores()
   assert(observed.perform==#specs and observed.flush==#specs and observed.complete==(kind=='sp'and #specs or 0))
   assert(hands.perform==0 and hands.unequip==0,'clothing prefix acquired false hand restoration evidence')
  end
 end
 getActivatedMods=oldMods
end
print('Equipment displacement completion: exact shared clothing boundaries and zero synthetic hand receipts passed in SP/Host modes.')

-- Ordinary hotbar setup waits for native visual replication without a client
-- repair, then checkpoint hands follow the real nonweapon equip branch.
do
 local Hotbar=modules.QueueEquipmentHotbar
 for _,id in ipairs({'tidy-hotbar-normal-left','tidy-hotbar-normal-right'})do
  local root={};local pickup={getContainer=function()return root end};local secondary={}
  local visual={hair='MohawkFan',getHairModel=function(self)return self.hair end,getNonAttachedHair=function(self)return self.attached end}
  local sample={id=id,root=root,pickup=pickup,screwdriver=secondary,front=book(10),tail=book(9)}
  local primary,held=Hotbar.expectedHands(sample,false)
  sample.player={getPrimaryHandItem=function()return primary end,getSecondaryHandItem=function()return held end,getHumanVisual=function()return visual end}
  local ids={case=id,hotbarHair='CrewCut'}
  assert(not Hotbar.available(sample.player,ids),'unreplicated plain hair must wait')
  visual.hair='CrewCut';visual.attached='Ponytail';assert(not Hotbar.available(sample.player,ids))
  visual.attached=nil;assert(Hotbar.available(sample.player,ids))
  assert(Fixture.settled(sample,'toolkit',true),'native selected ordinary checkpoint hands differ')
  assert(not Fixture.settled(sample,'toolkit'),'independent tail must still be incomplete')
  primary,held=held,primary;assert(not Fixture.settled(sample,'toolkit',true),'swapped native selected hands accepted')
 end
end
print('Equipment ordinary hotbar authority: passive visual setup and exact native checkpoint hands passed.')

-- Drive the actual client state machine with a first-case provider handshake.
-- Prepared state exists before enqueue creates receipt tracking; an expired
-- heartbeat must neither enumerate nil records nor capture setup actions.
do
 for _,id in ipairs({'tidy-hotbar-normal-left','tidy-hotbar-holster-left'})do
  local now,enabled,captures,enqueued,watches=0,false,0,0,0
  local tick,start,serverCommand
  local sent,events,lines={},{},{}
  local queue={queue={}}
  function queue:indexOf(action)for i,value in ipairs(self.queue)do if value==action then return i end end;return -1 end
  local player={}
  function player:getCurrentSquare()return {}end
  function player:isPlayerMoving()return false end
  function player:tooDarkToRead()return false end
  function player:hasTimedActions()return false end
  function player:isTimedActionInstant()return false end
  function player:getPlayerNum()return 0 end
  function player:getX()return 1 end;function player:getY()return 2 end;function player:getZ()return 0 end
  function player:setGhostMode()end;function player:setAutoDrink()end
  local function book(kind)return {getFullType=function()return kind end,getAlreadyReadPages=function()return 0 end}end
  local sample={id=id,player=player,front=book('Base.BookCarpentry1'),tail=book('Base.BookFirstAid1'),
   pickup={getID=function()return 1801 end},hotbarIndex=3}
  local selection={cases={id},kind='mp',mode='native',language='EN',options={}}
  local toolkit={Settings={actionQueue=function()return enabled end},ActionQueue={},ActionQueuePolicy={},ActionQueueOperations={},
   ActionQueueAcknowledgements={capture=function(action)
    captures=captures+1
    if action.Type=='ISEquipWeaponAction'then return {token='provider-token',kind=action.Type,transaction=1,state='completed'}end
   end}}
  local hotbar={isCase=function(value)return value==id end,provider=function()return {}end,install=function()end,
   observe=function()end,diagnoseWaiting=function()end,watch=function()watches=watches+1 end,
   enqueue=function(state)
    assert(state==sample);enqueued=enqueued+1
    queue.queue[#queue.queue+1]={Type='ISEquipWeaponAction',item=sample.pickup}
    queue.queue[#queue.queue+1]={Type='ISCutHair',item=sample.pickup}
   end}
  local required={QueueTestSelection=selection,QueueEquipmentSelection=selection,
   QueueEquipmentFixture={available=function()return true end,prepare=function()return sample end},
   QueueEquipmentScene={needed=function()return false end},QueueEquipmentSlots={isBelt=function()return false end},
   QueueEquipmentBulk={isCase=function()return false end},QueueEquipmentClothing={isCase=function()return false end,watch=function()end},
   QueueEquipmentHotbar=hotbar,QueueEquipmentCompletion={observe=function()return {watch=function()end}end},
   QueueHealthEvents={emit=function(event)events[#events+1]=event end}}
  local env=setmetatable({PZSurvivorToolkit=toolkit,require=function(name)return required[name]or {}end,
   Events={OnTick={Add=function(fn)tick=fn end},OnGameStart={Add=function(fn)start=fn end},
    OnPlayerUpdate={Add=function()end},OnServerCommand={Add=function(fn)serverCommand=fn end}},
   getPlayer=function()return player end,getTimestampMs=function()return now end,
   isClient=function()return true end,isServer=function()return false end,
   getActivatedMods=function()return {contains=function()return true end}end,
   getCore=function()return {setOptionAutoDrink=function()end}end,
   Translator={getLanguage=function()return {name=function()return 'EN'end}end},
   PZAPI={ModOptions={getOptions=function()return {getOption=function()return {setValue=function(_,value)enabled=value end}end}end}},
   ISTimedActionQueue={getTimedActionQueue=function()return queue end,add=function(action)queue.queue[#queue.queue+1]=action end},
   ISReadABook={getDuration=function()return 1 end},
   sendClientCommand=function(module,command,args)sent[#sent+1]={module=module,command=command,args=args}end,
   print=function(line)lines[#lines+1]=line end},{__index=_G})
  env.ISInventoryPaneContextMenu={onLiteratureItems=function(items)
   env.ISTimedActionQueue.add({Type='ISReadABook',item=items[1],getDuration=env.ISReadABook.getDuration,minutesPerPage=2.0})
  end}
  local chunk=assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/client/ZZEquipmentQueue.lua'))
  setfenv(chunk,env);chunk();start();tick()
  assert(sent[1].command=='Prepare'and enqueued==0)
  serverCommand('EquipmentQueueTest','Prepared',{case=id,items={pickup=1801},spawn={x=1,y=2,z=0}})
  tick();tick()
  assert(sent[2].command=='ConfigureHotbar'and not sample.records and enqueued==0 and watches==0)
  now=15000
  for i=1,3 do tick()end
  assert(captures==0 and enqueued==0 and #queue.queue==0,'partial provider setup captured receipts/actions')
  assert(#events==1 and events[1].event=='setup','delayed first provider acknowledgement failed with expired heartbeat')
  for _,line in ipairs(lines)do assert(not line:find('CAPTURE',1,true)and not line:find('WAIT',1,true),'setup leaked active receipt heartbeat')end
  serverCommand('EquipmentQueueTest','HotbarConfigured',{case=id,item=1801,slotIndex=3,ok=true})
  tick()
  assert(#events==1,'client failed after provider acknowledgement: '..tostring(events[#events].reason))
  assert(enqueued==1 and watches==1 and #queue.queue==4 and sample.expectedReceipts==1
   and type(sample.records)=='table'and type(sample.seen)=='table','provider ack did not enqueue and initialise strict receipt tracking')
  queue.current=queue.queue[2];tick();tick()
  assert(captures==2 and #sample.records==1 and sample.seen['provider-token']and sample.records[1].state=='completed',
   'after-enqueue exact receipt capture/dedup changed')
  local waits=0
  for _,line in ipairs(lines)do if line:find('[EQUIPMENT_TEST] WAIT',1,true)then waits=waits+1 end end
  assert(waits==1 and #events==1,'active heartbeat failed after delayed provider ack')
 end
end
print('Equipment first-provider client setup: expired heartbeat waits for enqueue tracking, then exact receipt capture proceeds once.')

-- Native equipment acknowledgements can precede RadioDeviceDataState0. Drive
-- the actual server request loop: no final verifier runs until the independently
-- owned device observes the arriving off state; retry never copies client data.
do
 local tick,command
 local now,on,reads,checks=0,true,0,0
 local sent,lines={},{}
 local player={getUsername=function()return 'client1'end,getCurrentSquare=function()return {}end,
  setGhostMode=function()end,getX=function()return 1 end,getY=function()return 2 end,getZ=function()return 0 end,
  getWornItem=function()end,getPrimaryHandItem=function()end,getSecondaryHandItem=function()end}
 local function item(id)return {getID=function()return id end,getAlreadyReadPages=function()return 0 end}end
 local sample={id='tidy-hotbar-radio-on',player=player,owned={},hammer=item(1),screwdriver=item(2),front=item(3),tail=item(4)}
 local fixture={position=function()end,prepare=function()return sample end,descriptor=function()return {}end,
  transactionsSettled=function()return true end,settled=function()return true end,verify=function()return {}end,refresh=function()end}
 local hotbar={isCase=function()return true end,provider=function()end,radio=function()return true end,
  radioReady=function(state,tidy)assert(state==sample and tidy);reads=reads+1;return not on end}
 local required={QueueTestSelection={cases={sample.id},mode='native',options={}},QueueEquipmentFixture=fixture,
  QueueEquipmentScene={prepare=function()end,proof=function()end},QueueEquipmentClothing={isCase=function()return false end,wristwatch=function()return false end},
  QueueEquipmentHotbar=hotbar,QueueEquipmentPostprocess={verify=function(state)assert(state==sample and not on);checks=checks+1;return {hotbar={}}end},
  QueueHealthEvents={encode=function()return '{}'end}}
 local env=setmetatable({require=function(name)return assert(required[name],name)end,isServer=function()return true end,
  Events={OnServerStarted={Add=function()end},OnClientCommand={Add=function(fn)command=fn end},OnTick={Add=function(fn)tick=fn end}},
  getTimestampMs=function()return now end,getActivatedMods=function()return {contains=function()return true end}end,
  sendClothing=function()end,sendEquip=function()end,equipmentNativeTransferCount=function()return 0 end,
  sendServerCommand=function(_,_,name,args)sent[#sent+1]={name=name,args=args}end,print=function(line)lines[#lines+1]=line end},{__index=_G})
 local chunk=assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/server/ZZEquipmentServer.lua'))
 setfenv(chunk,env);chunk()
 command('EquipmentQueueTest','Prepare',player,{case=sample.id})
 command('EquipmentQueueTest','Checkpoint',player,{case=sample.id});tick()
 assert(sent[1].name=='Prepared'and sent[2].name=='Checkpointed'and checks==0)
 command('EquipmentQueueTest','Verify',player,{case=sample.id});tick();now=1;tick()
 assert(#sent==2 and reads==2 and checks==0 and on,'radio state lag must remain pending without changing the device')
 on=false -- Independent native radio state packet arrival, after equip completion.
 now=2;tick();tick()
 assert(#sent==3 and sent[3].name=='Verified'and sent[3].args.passed and reads==3 and checks==1)
 for _,line in ipairs(lines)do assert(not line:find('FAIL',1,true),'radio state lag failed instead of retrying: '..line)end
end
print('Equipment authoritative radio final state: delayed native device packet retries without client-state normalization.')
