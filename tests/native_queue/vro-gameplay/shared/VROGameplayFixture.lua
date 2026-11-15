-- Disposable qualification state. Product callbacks remain the only effect producers.
local JSON=require 'QueueHealthEvents'
local F={phases={'repair-cancel','repair-complete','salvage-cancel','salvage-complete'},vehicles={},items={}}
local key='VROGameplayFixtureV1'
function F.emit(event,row)print('[VRO_GAMEPLAY] '..event..' '..JSON.encode(row))end
function F.same(a,b)
 if type(a)~=type(b)then return false end
 if type(a)=='number'then return a==b or math.abs(a-b)<.0001 end
 if type(a)~='table'then return a==b end
 for k,v in pairs(a)do if not F.same(v,b[k])then return false end end
 for k in pairs(b)do if a[k]==nil then return false end end
 return true
end
function F.family(phase)return require(phase:find('repair',1,true)and'VRORepairChecks'or'VROSalvageChecks')end
function F.mode(phase)return phase:find('cancel',1,true)and'cancel'or'complete'end
local function id(item)return item and item:getID()or false end
function F.actor(player)
 local state={primary=id(player:getPrimaryHandItem()),secondary=id(player:getSecondaryHandItem()),
  x=player:getX(),y=player:getY(),z=player:getZ(),xp={},worn={},items={},total=player:getXp():getTotalXp()}
 for _,name in ipairs({'Mechanics','MetalWelding'})do state.xp[name]={xp=player:getXp():getXP(Perks[name]),level=player:getPerkLevel(Perks[name])}end
 local inventory=player:getInventory():getItems()
 for i=0,inventory:size()-1 do local item=inventory:get(i);state.items[#state.items+1]={id=item:getID(),fullType=item:getFullType()}end
 local worn=player:getWornItems();for i=0,worn:size()-1 do local entry=worn:get(i)
  state.worn[#state.worn+1]={id=entry:getItem():getID(),location=tostring(entry:getLocation())}
 end
 return state
end
function F.skills(player)
 for _,name in ipairs({'Mechanics','MetalWelding'})do
  player:setPerkLevelDebug(Perks[name],4);player:getXp():setXPToLevel(Perks[name],4)
  assert(player:getPerkLevel(Perks[name])==4,'fixture skill setup failed')
 end
end
local function seed(player,kind)
 local item=assert(player:getInventory():AddItem(kind),'fixture input unavailable: '..kind)
 F.items[#F.items+1]=item
 if isServer()then sendAddItemToContainer(player:getInventory(),item)end
 return item
end
function F.clear(x,y)
 local squares={}
 for dx=-4,4 do for dy=-5,5 do
  local square=getCell():getGridSquare(x+dx,y+dy,0)
  if not square or not square:isOutside()or not square:isFree(false)then return false end
  for i=0,square:getMovingObjects():size()-1 do if instanceof(square:getMovingObjects():get(i),'BaseVehicle')then return false end end
  squares[dx..':'..dy]=square
 end end
 -- Free tiles can still be separated by a wall, door, window or fence edge.
 -- Keep the complete walking margin connected before spawning its obstacle.
 for dx=-4,4 do for dy=-5,5 do local square=squares[dx..':'..dy]
  for _,step in ipairs({{1,0},{0,1}})do local adjacent=squares[(dx+step[1])..':'..(dy+step[2])]
   if adjacent and(square:isBlockedTo(adjacent)or adjacent:isBlockedTo(square)
    or square:isHoppableTo(adjacent)or adjacent:isHoppableTo(square))then return false end
  end
 end end
 for _,vehicle in pairs(F.vehicles)do if math.abs(vehicle:getX()-x)<10 and math.abs(vehicle:getY()-y)<12 then return false end end
 return true
end
local function position(player)
 local px,py=math.floor(player:getX()),math.floor(player:getY())
 for radius=6,35 do for dx=-radius,radius do for dy=-radius,radius do
  if(math.abs(dx)==radius or math.abs(dy)==radius)and F.clear(px+dx,py+dy)then return getCell():getGridSquare(px+dx,py+dy,0)end
 end end end
 error('No clear loaded exterior VRO fixture area')
end
function F.safeVehicle(vehicle)
 assert(vehicle and not vehicle:getVehicleTowing()and not vehicle:getVehicleTowedBy(),'fixture vehicle towing changed')
 for i=0,vehicle:getMaxPassengers()-1 do assert(not vehicle:getCharacter(i),'fixture vehicle occupied')end
 assert(vehicle:getAnimals():size()==0,'fixture vehicle contains an animal')
 for i=0,vehicle:getPartCount()-1 do local container=vehicle:getPartByIndex(i):getItemContainer()
  assert(not container or container:getItems():size()==0,'fixture vehicle contains unowned contents')
 end
end
local function spawn(player,name)
 local square=position(player);local vehicle=assert(addVehicleDebug('Base.CarNormal',IsoDirections.N,nil,square))
 assert(vehicle:getSquare(),'fixture vehicle spawn rejected')
 vehicle:setAlarmed(false);vehicle:setAngles(0,2,0);vehicle:setAngles(0,0,0)
 -- The freshly generated contents are owned at this boundary; later guards only observe emptiness.
 local generated={}
 local function visit(container)
  for i=0,container:getItems():size()-1 do local item=container:getItems():get(i)
   if instanceof(item,'InventoryContainer')then visit(item:getInventory())end
   generated[#generated+1]={container=container,item=item}
  end
 end
 for i=0,vehicle:getPartCount()-1 do local container=vehicle:getPartByIndex(i):getItemContainer()
  if container then container:setExplored(true);visit(container)end
 end
 for _,entry in ipairs(generated)do
  assert(entry.item:getContainer()==entry.container,'generated vehicle contents moved')
  entry.container:Remove(entry.item);if isServer()then sendRemoveItemFromContainer(entry.container,entry.item)end
 end
 F.safeVehicle(vehicle)
 local part=assert(vehicle:getPartById('EngineDoor'));local installed=assert(part:getInventoryItem())
 part:getModData()[key]=name
 if name=='repair'then part:setCondition(40);installed:setCondition(40);installed:setHaveBeenRepaired(0)end
 if isServer()then vehicle:transmitPartCondition(part);vehicle:transmitPartItem(part);vehicle:transmitPartModData(part)end
 F.vehicles[name]=vehicle
 return {vehicleID=vehicle:getId(),vehicleKey=name,x=vehicle:getSquare():getX(),y=vehicle:getSquare():getY(),z=0,
  installedID=installed:getID()}
end
function F.prepare(player)
 assert(not F.packet,'fixture preparation repeated')
 local checkpoint=ModData.getOrCreate(key);for _ in pairs(checkpoint)do error('preexisting VRO fixture checkpoint')end
 F.original=F.actor(player);F.skills(player)
 local mask=seed(player,'Base.WeldingMask');local torch=seed(player,'Base.BlowTorch')
 assert(torch:getCurrentUses()>=3,'repair torch is not charged')
 local metal={seed(player,'Base.SheetMetal'):getID(),seed(player,'Base.SheetMetal'):getID()}
 F.packet={repair=spawn(player,'repair'),salvage=spawn(player,'salvage'),maskID=mask:getID(),repairTorchID=torch:getID(),metalIDs=metal}
 if isServer()then assert(F.packet.repair.vehicleID>=0 and F.packet.salvage.vehicleID>=0 and F.packet.repair.vehicleID~=F.packet.salvage.vehicleID,'fixture network identities missing')end
 F.emit('PREPARED',F.packet);return F.packet
end
function F.resolve(ids)
 if ids.vehicle then return not ids.vehicle:isRemovedFromWorld()and ids.vehicle or nil end
 local vehicle=getVehicleById(ids.vehicleID)
 return vehicle and not vehicle:isRemovedFromWorld()and vehicle or nil
end
function F.ids(packet,phase)
 local name=phase:find('repair',1,true)and'repair'or'salvage';local source=packet[name]
 local value={};for k,v in pairs(source)do value[k]=v end
 value.maskID=packet.maskID;value.metalIDs=packet.metalIDs
 value.torchID=name=='repair'and packet.repairTorchID or packet.salvageTorchID
 if not isServer()and not isClient()then value.vehicle=F.vehicles[name]end
 return value
end
function F.begin(player,index)
 local phase=assert(F.phases[index]);assert(not F.active,'previous VRO phase still active')
 if index==3 then
  local torch=seed(player,'Base.BlowTorch');assert(torch:getCurrentUses()>=10,'salvage needs a full native torch')
  F.packet.salvageTorchID=torch:getID()
 end
 local ids=F.ids(F.packet,phase);F.safeVehicle(assert(F.resolve(ids)))
 F.active={phase=phase,index=index,ids=ids,before=F.family(phase).observe(player,ids)}
 F.emit('AUTHORITY_BEFORE',{phase=phase,index=index,observed=F.active.before})
 return F.packet
end
function F.world(ids)
 -- Absence is meaningful only while the full target neighborhood remains loaded.
 for dx=-3,3 do for dy=-3,3 do if not getCell():getGridSquare(ids.x+dx,ids.y+dy,ids.z)then return nil end end end
 local square=getCell():getGridSquare(ids.x,ids.y,ids.z);local vehicle=F.resolve(ids)
 local row={vehicleKey=ids.vehicleKey,vehicleID=ids.vehicleID,removed=vehicle==nil,ground={}}
 if vehicle then
  local part=vehicle:getPartById('EngineDoor');local item=part and part:getInventoryItem()
  if not item then return nil end
  assert(part:getModData()[key]==ids.vehicleKey and item:getID()==ids.installedID,'VRO world vehicle ownership changed')
  row.itemID=item:getID();row.condition=part:getCondition();row.itemCondition=item:getCondition();row.hbr=item:getHaveBeenRepaired()
 end
 for i=0,square:getWorldObjects():size()-1 do local item=square:getWorldObjects():get(i):getItem()
  if item then row.ground[#row.ground+1]={id=item:getID(),fullType=item:getFullType()}end
 end
 table.sort(row.ground,function(a,b)return a.id<b.id end);return row
end
function F.ready(player,ids)
 if not F.world(ids)then return false end
 local inventory=player:getInventory()
 if not inventory:getItemById(ids.maskID)or not inventory:getItemById(ids.torchID)then return false end
 if ids.vehicleKey=='repair'then
  local vehicle=F.resolve(ids);if not vehicle then return false end
  for _,id in ipairs(ids.metalIDs)do if not inventory:getItemById(id)then return false end end
 end
 return true
end
function F.after(player,receipt)
 local state=assert(F.active);assert(receipt.vehicleID==state.ids.vehicleID and receipt.mode==F.mode(state.phase)
  and receipt.started and receipt.menuCallback and receipt.nativeDuration>1,'native VRO action receipt differs')
 assert(F.same(state.before,receipt.before),'actor and authority VRO baselines differ')
 local family=F.family(state.phase);local after=family.observe(player,state.ids)
 if not F.same(after,receipt.after)then return nil end
 family.validate(state.before,after,F.mode(state.phase))
 local world=assert(F.world(state.ids),'authoritative target neighborhood unloaded')
 F.emit('AUTHORITY_AFTER',{phase=state.phase,index=state.index,before=state.before,after=after,world=world,action=receipt})
 return world
end
function F.finishPhase()
 assert(F.active);F.active=nil
end
function F.checkpoint(player,receipts)
 local checkpoint=ModData.getOrCreate(key)
 checkpoint.version=1;checkpoint.packet=F.packet;checkpoint.original=F.original;checkpoint.receipts=receipts
 checkpoint.clientOriginals=F.clientOriginals or{client1=F.original}
 checkpoint.finalActor=F.actor(player);checkpoint.owned={}
 for _,item in ipairs(F.items)do checkpoint.owned[#checkpoint.owned+1]={id=item:getID(),fullType=item:getFullType()}end
 checkpoint.worlds={repair=F.world(F.ids(F.packet,'repair-complete')),salvage=F.world(F.ids(F.packet,'salvage-complete'))}
 assert(checkpoint.worlds.repair and checkpoint.worlds.salvage,'checkpoint area unloaded')
 F.emit('CHECKPOINT',{retainedForReload=true,original=checkpoint.original,actor=checkpoint.finalActor,worlds=checkpoint.worlds,
  owned=checkpoint.owned,clientOriginals=checkpoint.clientOriginals})
 return checkpoint
end
F.key=key
return F
