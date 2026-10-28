local F={}
F.settleMilliseconds=750
F.settleSamples=15
function F.newPositionSettlement(target)
 return {target=target,samples=0,logs=0}
end
function F.observePositionSettlement(state,player,now,idle)
 local x,y,z=player:getX(),player:getY(),player:getZ()
 local target=state.target
 local matches=not target or math.abs(x-target.x)<.01 and math.abs(y-target.y)<.01 and z==target.z
 local same=x==state.x and y==state.y and z==state.z
 if not idle or not matches then state.since=nil;state.samples=0
 elseif not same or not state.since then state.since=now;state.samples=1
 else state.samples=state.samples+1 end
 state.x,state.y,state.z=x,y,z
 return state.since~=nil and now-state.since>=F.settleMilliseconds and state.samples>=F.settleSamples
end
function F.settlementText(state,now)
 return 'stableMs='..(state.since and now-state.since or 0)..' samples='..state.samples
  ..' observed='..state.x..','..state.y..','..state.z
end
function F.positionText(player,target)
 return 'target='..target.x..','..target.y..','..target.z
  ..' observed='..player:getX()..','..player:getY()..','..player:getZ()
end
function F.restorePosition(player,target)
 local before=F.positionText(player,target)
 -- B42 teleportTo(float,float,int) floors x/y before the integer teleport.
 -- Restore the original sub-tile coordinates and all horizontal integration
 -- positions afterward, so the following native update cannot reuse old motion.
 player:teleportTo(target.x,target.y,target.z)
 player:setX(target.x);player:setY(target.y);player:setZ(target.z)
 player:setNextX(target.x);player:setNextY(target.y)
 player:setLastX(target.x);player:setLastY(target.y)
 return before,F.positionText(player,target)
end
local function road(x,y)
 local sq=getCell():getGridSquare(x,y,0)
 if not sq or not sq:isOutside() or not sq:isFree(false) then return false end
 local floor=sq:getFloor();local sprite=floor and floor:getSprite();local name=sprite and sprite:getName() or ''
 return name:find('street')~=nil
end
function F.position(player)
 local px,py=math.floor(player:getX()),math.floor(player:getY())
 for radius=0,60,4 do
  for dx=-radius,radius,2 do for dy=-radius,radius,2 do
   if radius==0 or math.abs(dx)==radius or math.abs(dy)==radius then
    local x,y=px+dx,py+dy
    for _,dir in ipairs({{0,-1,'N'},{0,1,'S'},{1,0,'E'},{-1,0,'W'}}) do
     local clear=true
     for offset=-66,66 do
      if not road(x+dir[1]*offset,y+dir[2]*offset) then clear=false;break end
     end
     if clear then
      print('[VEHICLE_LIGHTS] ROAD x='..x..' y='..y..' direction='..dir[3]..' clearAhead=66 clearBehind=66')
      return x,y,dir[3]
     end
    end
   end
  end end
 end
 error('No loaded unobstructed 133-tile road segment')
end
function F.prepare(player,x,y,dir,script)
 assert(not F.vehicle,'previous owned vehicle must be removed before preparation')
 local square=assert(getCell():getGridSquare(x,y,0),'road unloaded')
 local vehicle=assert(addVehicleDebug(script or 'Base.CarNormal',IsoDirections[dir],nil,square))
 assert(vehicle:getSquare(),'native vehicle placement rejected')
 -- addVehicleDebug randomizes yaw; the native setter uses degrees and truncates for its early-out.
 local yaw=assert(({N=180,S=0,E=90,W=-90})[dir])
 vehicle:setAngles(0,yaw+2,0);vehicle:setAngles(0,yaw,0)
 vehicle:repair();vehicle:setHotwired(true);vehicle:setAlarmed(false)
 local tank=assert(vehicle:getPartById('GasTank'));tank:setContainerContentAmount(tank:getContainerCapacity())
 for _,id in ipairs({'HeadlightLeft','HeadlightRight','HeadlightRearLeft','HeadlightRearRight'}) do
  local part=assert(vehicle:getPartById(id));assert(part:getInventoryItem(),'missing lamp '..id)
  part:getInventoryItem():setCondition(part:getInventoryItem():getConditionMax());part:setCondition(100)
 end
 F.vehicle=vehicle
 -- A newly spawned fixture owns only its initial generated contents. Remove exact
 -- references now; later cleanup refuses every remaining item instead of deleting it.
 local generated={}
 local function visit(pool)
  for index=0,pool:getItems():size()-1 do
   local item=pool:getItems():get(index)
   if instanceof(item,'InventoryContainer') then visit(item:getInventory()) end
   generated[#generated+1]={item=item,pool=pool}
  end
 end
 for index=0,vehicle:getPartCount()-1 do
  local pool=vehicle:getPartByIndex(index):getItemContainer()
  if pool then pool:setExplored(true);visit(pool) end
 end
 for _,entry in ipairs(generated) do
  assert(entry.item:getContainer()==entry.pool and entry.pool:contains(entry.item),'generated ownership changed')
  entry.pool:Remove(entry.item)
  if isServer() then sendRemoveItemFromContainer(entry.pool,entry.item) end
  assert(not entry.pool:contains(entry.item),'generated item survived removal')
 end
 print('[VEHICLE_LIGHTS] SPAWN id='..vehicle:getId()..' x='..vehicle:getX()..' y='..vehicle:getY())
 return vehicle
end
function F.remove(vehicle)
 assert(vehicle and vehicle==F.vehicle,'unowned vehicle removal refused')
 assert(not vehicle:getVehicleTowing() and not vehicle:getVehicleTowedBy(),'foreign towing attachment')
 for index=0,vehicle:getMaxPassengers()-1 do assert(not vehicle:getCharacter(index),'occupied fixture vehicle') end
 assert(vehicle:getAnimals():size()==0,'animal in fixture vehicle')
 for index=0,vehicle:getPartCount()-1 do
  local pool=vehicle:getPartByIndex(index):getItemContainer()
  assert(not pool or pool:getItems():size()==0,'foreign contents in fixture vehicle')
 end
 local id=vehicle:getId();vehicle:setHeadlightsOn(false);vehicle:shutOff()
 vehicle:permanentlyRemove();assert(not getCell():getVehicles():contains(vehicle),'owned vehicle removal failed')
 F.vehicle=nil
 return id
end
return F
