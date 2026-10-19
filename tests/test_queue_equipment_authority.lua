isClient,isServer=function() return false end,function() return false end
local function load(name)
 return assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/shared/'..name..'.lua'))()
end
local modules={QueueEquipmentSlots=load('QueueEquipmentSlots'),QueueEquipmentFloor=load('QueueEquipmentFloor'),QueueEquipmentBulk=load('QueueEquipmentBulk')}
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
local inventory={}
local item={getID=function() return 21 end}
local values={size=function() return #inventory end,get=function(_,i) return inventory[i+1] end}
state.player.getInventory=function() return {getItems=function() return values end} end
instanceof=function() return false end
local ids={items={hammer=21}}
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
  ActionQueuePolicy={evaluateCancel=function()return {allowed=false}end}}
 local observer=load('QueueEquipmentCompletion').observe(toolkit,{kind=case.kind,mode='toolkit'})
 observer.watch({id='tidy-empty-hands',pickup=gun,hammer=exact(33),screwdriver=exact(34),baseline={[31]=gun}})
 local ok=pcall(lifecycle.begin,action,'perform')
 assert(ok==case.ok,'unequip observer accepted wrong hand state or rejected replicated Host completion')
end
