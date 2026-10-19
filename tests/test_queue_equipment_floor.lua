local Floor=assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/shared/QueueEquipmentFloor.lua'))()
local function list(values)
 return {values=values,size=function(s) return #s.values end,get=function(s,i) return s.values[i+1] end,
  contains=function(s,value) for _,entry in ipairs(s.values) do if entry==value then return true end end return false end}
end
local objects=list({})
local square={getWorldObjects=function() return objects end,getX=function() return 10 end,getY=function() return 20 end,getZ=function() return 0 end}
local root={hasRoomFor=function() return true end,getItemById=function(s,id) return s.item and s.item.id==id and s.item end,
 getType=function() return 'inventorymale' end}
local item={id=731,getID=function(s) return s.id end,getContainer=function(s) return s.container end,
 getWorldItem=function(s) return s.world end,setWorldItem=function(s,world) s.world=world end}
local world={getSquare=function() return square end,getItem=function() return item end}
local floor={getType=function() return 'floor' end,contains=function(s,value) return value==item and item.world~=nil end}
local removals=0
square.AddWorldInventoryItem=function() item.world=world;objects.values={world};return item end
square.transmitRemoveItemFromSquare=function(s,value) assert(value==world);removals=removals+1 end
square.removeWorldObject=function(s,value) assert(value==world);objects.values={} end
local player={getCurrentSquare=function() return square end,getPlayerNum=function() return 0 end}
getCell=function() return {getGridSquare=function(s,x,y,z) assert(x==10 and y==20 and z==0);return square end} end
local client,server=false,true
isClient=function() return client end;isServer=function() return server end
local state={player=player,root=root,items={},owned={}}

-- Server preparation owns exactly one real world item and needs no client UI.
Floor.prepare(state)
assert(state.pickup==item and state.floor.id==item.id and state.items.pickup==item and #state.owned==1)
assert(Floor.resolve(state.floor)==item)
objects.values={world,world};assert(not pcall(Floor.resolve,state.floor));objects.values={world}

-- Client setup waits for the exact authoritative world ID, then uses the real loot refresh.
client,server=true,false
local metadata=state.floor
state={player=player,root=root,items={},owned={},ids={floor=metadata}}
objects.values={};assert(Floor.resolve(metadata)==nil);assert(not pcall(Floor.prepare,state))
objects.values={world}
getPlayerLoot=function() return {refreshBackpacks=function() end} end
ISInventoryPage={GetFloorContainer=function() return floor end}
assert(not pcall(Floor.prepare,state),'an unassociated world item must not gain a synthetic source')
getPlayerLoot=function() return {refreshBackpacks=function() item.container=floor end} end
state={player=player,root=root,items={},owned={},ids={floor=metadata}}
Floor.prepare(state)

local queue={queue={}}
ISInventoryPaneContextMenu={onGrabItems=function(items,number)
 assert(items[1]==item and number==0)
 queue.queue[1]={Type='ISInventoryTransferAction',item=item,srcContainer=floor,destContainer=root}
end}
local helpers={queue=function() return queue end,run=function(fn,...) return fn(...) end,native=true}
assert(Floor.enqueue(state,helpers)==queue.queue[1])

-- Empty native queues must not pass while the exact fixture is still on the floor.
assert(not pcall(Floor.verify,state,'native'))
item.container=root;root.item={id=item.id};item.world=nil;objects.values={}
assert(not pcall(Floor.verify,state,'native'),'a replacement with the same ID must fail identity verification')
root.item=item
local result=Floor.verify(state,'native')
assert(result.floorPickup and result.pickupWorldRemoved and result.pickupID==metadata.id)
assert(not pcall(Floor.verify,state,'toolkit'),'toolkit verification requires protected-control evidence')

-- Cleanup leaves completed pickups alone and refuses world objects it did not create.
Floor.cleanup(state);assert(removals==0)
item.world={};assert(not pcall(Floor.cleanup,state));assert(removals==0)
item.world=world;objects.values={};Floor.cleanup(state)
assert(removals==0 and not item.world,'already replicated removal must not send a duplicate world removal')
item.world=world;objects.values={world};Floor.cleanup(state)
assert(removals==1 and not item.world and objects:size()==0)
-- The authoritative placement must broadcast the final rotation, not an earlier random value.
client,server=false,true
instanceItem=function(kind) assert(kind=='Base.Pistol');return item end
item.setWorldZRotation=function(s,value) s.rotation=value end
item.getWorldXRotation=function()return 0 end;item.getWorldYRotation=function()return 0 end
item.getWorldZRotation=function(s)return s.rotation end
world.getOffX=function()return .5 end;world.getOffY=function()return .5 end;world.getOffZ=function()return 0 end
square.AddWorldInventoryItem=function(s,value,x,y,z,transmit)
 assert(value==item and item.rotation==37 and transmit,'floor pose changed after its initial broadcast')
 item.world=world;objects.values={world}
end
state={id='tidy-floor',player=player,root=root,items={},owned={}}
Floor.prepare(state,nil,'Base.Pistol')
assert(state.floor.pose[6]==37)
print('Equipment floor fixture identity/source/cleanup checks passed.')
