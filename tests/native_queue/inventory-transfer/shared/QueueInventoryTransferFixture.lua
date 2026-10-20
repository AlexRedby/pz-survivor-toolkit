local F={count=15,kind='Base.EngineParts',script='Base.CarNormal'}
local config=require 'QueueTestSelection'
function F.inventory(state)
 local root,player=state.player:getInventory(),state.player
 return {rootItems=root:getItems():size(),trunkItems=state.trunk:getItems():size(),
  rootWeight=root:getCapacityWeight(),trunkWeight=state.trunk:getCapacityWeight(),
  rootCapacity=root:getEffectiveCapacity(player),trunkCapacity=state.trunk:getEffectiveCapacity(player)}
end
local function fillerReady(root,trunk,filler)
 if not filler then return true end
 for _,endpoint in ipairs({'root','trunk'})do
  local container=endpoint=='root'and root or trunk
  for _,id in ipairs(filler[endpoint])do
   local item=container:getItemById(id)
   if not item or item:getContainer()~=container or item:getFullType()~=filler.kind then return false,id end
  end
 end
 return true
end
local function count(container,id)
 local n=0;local items=container:getItems()
 for i=0,items:size()-1 do local item=items:get(i)
  if item:getID()==id then n=n+1 end
  if instanceof(item,'InventoryContainer')then n=n+count(item:getItemContainer(),id)end
 end
 return n
end
function F.prepare(player)
 local px,py=math.floor(player:getX()),math.floor(player:getY());local square
 for radius=4,24 do
  for dx=-radius,radius do for dy=-radius,radius do
   if not square and (math.abs(dx)==radius or math.abs(dy)==radius)then
    local clear=true
    for x=-3,3 do for y=-4,4 do
     local q=getCell():getGridSquare(px+dx+x,py+dy+y,0)
     if not q or not q:isOutside()or not q:isFree(false)or q:getVehicleContainer()then clear=false end
    end end
    if clear then square=getCell():getGridSquare(px+dx,py+dy,0)end
   end
  end end
  if square then break end
 end
 assert(square,'no clear car square')
 local vehicle=assert(addVehicleDebug(F.script,IsoDirections.N,nil,square))
 assert(vehicle:getSquare(),'native car placement rejected');vehicle:repair();vehicle:setAlarmed(false)
 local part=assert(vehicle:getPartById('TruckBed'));local trunk=assert(part:getItemContainer())
 trunk:clear();trunk:setExplored(true)
 local door=vehicle:getPartById('TrunkDoor')
 if door and door:getDoor()then door:getDoor():setLocked(false);door:getDoor():setOpen(true)
  if isServer()then vehicle:transmitPartDoor(door)end
 end
 local root=player:getInventory();local items,descriptors={},{}
 for i=1,F.count do local item=assert(root:AddItem(F.kind));items[i]=item
  descriptors[i]={id=item:getID(),kind=item:getFullType()}
  if isServer()then sendAddItemToContainer(root,item)end
 end
 local filler
 if config.options and config.options.inventory_transfer_density==true then
  filler={kind='Base.Paperclip',root={},trunk={}}
  for _,endpoint in ipairs({'root','trunk'})do
   local container=endpoint=='root'and root or trunk
   local amount=endpoint=='root'and 500 or 1000
   for i=1,amount do
    local item=assert(container:AddItem(filler.kind));filler[endpoint][i]=item:getID()
    if isServer()and endpoint=='root'then sendAddItemToContainer(root,item)end
   end
  end
 end
 if isServer()then sendItemsInContainer(vehicle,trunk)end
 local area=assert(vehicle:getAreaCenter(part:getArea()))
 local ids={case='trunk-15',vehicleId=vehicle:getId(),script=vehicle:getScriptName(),part='TruckBed',
  destinationType=trunk:getType(),items=descriptors,x=area:getX(),y=area:getY(),z=0,count=F.count}
 local state={player=player,vehicle=vehicle,trunk=trunk,items=items,ids=ids,filler=filler}
 ids.inventory=F.inventory(state)
 assert(ids.inventory.rootWeight<=ids.inventory.rootCapacity,'fixture root exceeds native capacity')
 local incoming=0;for _,item in ipairs(items)do incoming=incoming+item:getUnequippedWeight()end
 assert(ids.inventory.trunkWeight+incoming<=ids.inventory.trunkCapacity,'fixture final trunk exceeds native capacity')
 if filler then ids.density=true;ids.filler={kind=filler.kind,root=#filler.root,trunk=#filler.trunk}end
 return state
end
function F.resolve(player,ids)
 local vehicle=getVehicleById(ids.vehicleId)
 if not vehicle or not vehicle:getSquare()then return nil,{reason='client-vehicle-not-loaded',vehicleId=ids.vehicleId}end
 if vehicle:getScriptName()~=ids.script then return nil,{reason='client-vehicle-script',script=vehicle:getScriptName(),expected=ids.script}end
 local trunk=vehicle:getPartById(ids.part):getItemContainer();local items={}
 for i,entry in ipairs(ids.items)do
  local item=player:getInventory():getItemById(entry.id)
  if not item or item:getFullType()~=F.kind or item:getContainer()~=player:getInventory()then
   return nil,{reason='client-root-item-not-ready',itemId=entry.id,index=i}
  end
  items[i]=item
 end
 local filler
 if ids.filler then
  filler={kind=ids.filler.kind,root={},trunk={}}
  for _,endpoint in ipairs({'root','trunk'})do
   local container=endpoint=='root'and player:getInventory()or trunk;local values=container:getItems()
   for i=0,values:size()-1 do local item=values:get(i)
    if item:getFullType()==filler.kind then filler[endpoint][#filler[endpoint]+1]=item:getID()end
   end
   if #filler[endpoint]~=ids.filler[endpoint]then return nil,{reason='client-filler-not-ready',endpoint=endpoint,count=#filler[endpoint]}end
  end
 end
 return {player=player,vehicle=vehicle,trunk=trunk,items=items,ids=ids,filler=filler}
end
function F.access(state)
 local player,vehicle=state.player,state.vehicle
 local part=vehicle:getPartById(state.ids.part)
 local area=vehicle:getAreaCenter(part:getArea())
 if not area then return {reason='client-trunk-area-missing'}end
 local nearby=false
 local px,py,pz=math.floor(player:getX()),math.floor(player:getY()),math.floor(player:getZ())
 -- Native inventory pages discover outdoor vehicle containers in this 3x3 scan.
 for dx=-1,1 do for dy=-1,1 do
  local square=getCell():getGridSquare(px+dx,py+dy,pz)
  if square and square:getVehicleContainer()==vehicle then nearby=true end
 end end
 local door=vehicle:getPartById('TrunkDoor')or vehicle:getPartById('DoorRear')or vehicle:getPartById('TrunkDoorOpened')
 local inArea=vehicle:isInArea(part:getArea(),player)
 local accessible=vehicle:canAccessContainer(part:getIndex(),player)
 return {x=area:getX(),y=area:getY(),z=vehicle:getSquare():getZ(),playerX=player:getX(),playerY=player:getY(),
  serverX=state.ids.x,serverY=state.ids.y,vehicleX=vehicle:getX(),vehicleY=vehicle:getY(),
  inArea=inArea,accessible=accessible,nearby=nearby,insideVehicle=player:getVehicle()~=nil,
  door=door and door:getId()or 'none',doorOpen=door and door:getDoor()and door:getDoor():isOpen()or false,
  doorItem=door and door:getInventoryItem()~=nil or false}
end
function F.place(state)
 local area=F.access(state)
 if not area.x then return area end
 local player=state.player
 -- The client's physics transform can differ from the server's spawn-time transform.
 -- Use the same current area center as native vehicle interaction/pathfinding.
 player:teleportTo(math.floor(area.x),math.floor(area.y),area.z)
 player:setX(area.x);player:setY(area.y);player:setZ(area.z)
 player:setNextX(area.x);player:setNextY(area.y);player:setLastX(area.x);player:setLastY(area.y)
 return F.access(state)
end
function F.receipt(state)
 local root=state.player:getInventory();local rows={}
 for i,entry in ipairs(state.ids.items)do
  local total=count(root,entry.id)
  for p=0,state.vehicle:getPartCount()-1 do
   local container=state.vehicle:getPartByIndex(p):getItemContainer()
   if container then total=total+count(container,entry.id)end
  end
  local item=state.trunk:getItemById(entry.id)
  if not item or item:getContainer()~=state.trunk then return nil,'trunk endpoint pending '..entry.id end
  assert(total==1 and item:getFullType()==F.kind,'item duplicated or changed '..entry.id)
  rows[i]={id=entry.id,kind=item:getFullType(),count=total,endpoint='trunk'}
 end
 local receipt={case=state.ids.case,vehicleId=state.vehicle:getId(),script=state.vehicle:getScriptName(),
  part=state.ids.part,destinationType=state.trunk:getType(),items=rows,count=#rows,inventory=F.inventory(state)}
 assert(receipt.inventory.rootWeight<=receipt.inventory.rootCapacity and receipt.inventory.trunkWeight<=receipt.inventory.trunkCapacity,
  'settled inventory exceeds native capacity')
 if state.filler then
  local ready,missing=fillerReady(root,state.trunk,state.filler)
  assert(ready,'filler endpoint/type changed '..tostring(missing))
  local wanted,counts={},{}
  for _,endpoint in ipairs({'root','trunk'})do for _,id in ipairs(state.filler[endpoint])do wanted[id]=true end end
  local function scan(container)
   local values=container:getItems()
   for i=0,values:size()-1 do local item=values:get(i);local id=item:getID()
    if wanted[id]then counts[id]=(counts[id]or 0)+1 end
    if instanceof(item,'InventoryContainer')then scan(item:getItemContainer())end
   end
  end
  scan(root)
  for p=0,state.vehicle:getPartCount()-1 do
   local container=state.vehicle:getPartByIndex(p):getItemContainer();if container then scan(container)end
  end
  for id in pairs(wanted)do assert(counts[id]==1,'filler identity duplicated '..id)end
  assert(receipt.inventory.rootItems==state.ids.inventory.rootItems-15 and receipt.inventory.trunkItems==state.ids.inventory.trunkItems+15,
   'dense fixture physical counts changed')
  receipt.density=true;receipt.filler={kind=state.filler.kind,root=#state.filler.root,trunk=#state.filler.trunk,identitiesVerified=true}
 end
 return receipt
end
return F
