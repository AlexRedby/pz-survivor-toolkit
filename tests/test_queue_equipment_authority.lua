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
 for _,name in ipairs({'overlap','removes','headwear'})do
  local ok,value=pcall(clothing[name],{id=id})
  assert(ok and value==false,'non-clothing predicate raised or matched '..id..' '..name)
 end
 assert(not pcall(clothing.spec,{id=id}),'unknown clothing configuration must remain strict')
end
for _,name in ipairs({'overlap','removes','headwear'})do
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
for _,id in ipairs({'tidy-clothing-overlap','tidy-clothing-overlap-primary','tidy-clothing-overlap-both'})do
 local clothing=modules.QueueEquipmentClothing
 local socks={};local sample={id=id,hammer=hammer,screwdriver=screwdriver,clothingItem=socks,
  clothingLocation='base:socks',clothingHair='CrewCut',front=book(10),tail=book(9)}
 local primary,secondary=clothing.expectedHands(sample,false)
 sample.player={getPrimaryHandItem=function()return primary end,getSecondaryHandItem=function()return secondary end,
  getWornItem=function()return socks end,getHumanVisual=function()return {getHairModel=function()return 'CrewCut'end}end}
 assert(Fixture.settled(sample,'toolkit',true),'selected native overlap must satisfy checkpoint '..id)
 assert(not Fixture.settled(sample,'toolkit'),'overlap must preserve independent unfinished tail '..id)
 local expected=primary;primary=nil;assert(not Fixture.settled(sample,'toolkit',true));primary=expected
 expected=secondary;secondary=nil;assert(not Fixture.settled(sample,'toolkit',true));secondary=expected
 sample.tail=book(10);assert(Fixture.settled(sample,'toolkit'))
 local finalPrimary,finalSecondary=clothing.expectedHands(sample,true)
 assert(finalPrimary==hammer and finalSecondary==screwdriver,'P4 hand restore expectation differs '..id)
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
 ItemBodyLocation={HAT='base:hat',FULL_HAT='base:fullhat'}
 local group={isExclusive=function(_,target,location)
  return target=='base:fullhat'and(location=='base:eyes'or location=='base:hat')
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
end
print('Equipment scene checks passed: real helper, starter glasses, root identity, once-only preparation and authority-owned SyncClothing.')
