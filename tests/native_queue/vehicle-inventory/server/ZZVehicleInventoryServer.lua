local F=require 'VehicleDoorsFixture'
local M='VehicleInventoryTest'
local peers,acks={},{}
local stage,phase,deadline='waiting',nil,nil
local vehicle,item,late,nested,oldVehicle,oldConnection,oldActor
local function now()return getTimestampMs()end
local function fail(err)stage='failed';print('[VEHICLE_INVENTORY] FAIL server '..tostring(err))end
local function send(p,kind,args)sendServerCommand(p,M,kind,args or {})end
local function all()return peers.client1 and peers.client2 end
local function phaseStart(name)
 phase=name;stage='phase';acks={};deadline=now()+45000
 vehicleInventoryTracePhase(name)
 local state=vehicleInventoryContents(vehicle)
 print('[VEHICLE_INVENTORY] STATE '..name..' vehicle='..vehicle:getId()..' contents='..state)
 for _,p in pairs(peers)do send(p,'check',{phase=name,id=vehicle:getId(),contents=state,item=item:getID(),held=name=='native-take',old=oldVehicle and oldVehicle:getId() or -1})end
end
local function music(v)
 local r=assert(NMLootPlaceholderResolver);local c=assert(v:getPartById('GloveBox'):getItemContainer())
 local placeholder=assert(c:AddItem(assert(r.getMediaPlaceholderFullType('cassettes','standard'))))
 assert(r.replacePlaceholdersInContainer(c,{routeClass='vehicle_glovebox',containerType=c:getType(),shape='vehicle'})>=1)
 assert(not c:getItemWithID(placeholder:getID()))
 print('[VEHICLE_INVENTORY] MUSIC vehicle='..v:getId()..' placeholder='..placeholder:getID())
end
local function act(name)
 vehicleInventoryTracePhase('native-'..name);stage='act-'..name;deadline=now()+45000;send(peers.client1,'act',{action=name,id=vehicle:getId(),item=item:getID()})
end
local function nextPhase()
 local c=vehicle:getPartById('GloveBox'):getItemContainer()
 if phase=='initial' then
  vehicleInventoryTracePhase('late-add');late=assert(c:AddItem('Base.Screwdriver'));sendAddItemToContainer(c,late);phaseStart('late-add')
 elseif phase=='late-add' then
  vehicleInventoryTracePhase('late-remove');c:Remove(late);sendRemoveItemFromContainer(c,late);phaseStart('late-remove')
 elseif phase=='late-remove' then
  vehicleInventoryTracePhase('nested-add');late=assert(nested:AddItem('Base.Screwdriver'));vehicleInventorySendBag(vehicle,nested,late,true);phaseStart('nested-add')
 elseif phase=='nested-add' then
  vehicleInventoryTracePhase('nested-remove');nested:Remove(late);vehicleInventorySendBag(vehicle,nested,late,false);phaseStart('nested-remove')
 elseif phase=='nested-remove' then act('take')
 elseif phase=='native-take' then act('return')
 elseif phase=='native-return' then act('leave')
 elseif phase=='replacement' then
  oldActor=peers.client2;oldConnection=vehicleInventoryConnection(oldActor)
  stage='reconnect';deadline=now()+120000;send(oldActor,'reconnect');print('[VEHICLE_INVENTORY] EXIT_GUEST connection='..oldConnection)
 elseif phase=='rejoined' then
  vehicleInventoryTracePhase('post-rejoin-add');late=assert(c:AddItem('Base.Pen'));sendAddItemToContainer(c,late);phaseStart('post-rejoin-add')
 elseif phase=='post-rejoin-add' then
  vehicleInventoryTracePhase('post-rejoin-remove');c:Remove(late);sendRemoveItemFromContainer(c,late);phaseStart('post-rejoin-remove')
 elseif phase=='post-rejoin-remove' then
  stage='done';for _,p in pairs(peers)do send(p,'complete')end;print('[VEHICLE_INVENTORY] COMPLETE server')
 end
end
Events.OnClientCommand.Add(function(module,command,p,args)
 if module~=M or stage=='failed' then return end
 local ok,err=pcall(function()
  local role=p:getUsername();assert(role=='client1' or role=='client2')
  if command=='ready' then
   if stage=='reconnect' and role=='client2' and args.rejoined then
    assert(p~=oldActor,'Guest actor was not replaced')
    assert(vehicleInventoryConnection(p)~=oldConnection,'Guest connection was not replaced')
    peers.client2=p;print('[VEHICLE_INVENTORY] REJOIN connection='..vehicleInventoryConnection(p));phaseStart('rejoined')
   elseif not peers[role] then
    peers[role]=p;print('[VEHICLE_INVENTORY] PEER '..role..' connection='..vehicleInventoryConnection(p))
   end
  elseif command=='checked' then
   assert(stage=='phase' and args.phase==phase and peers[role]==p and not acks[role],'Stale phase ack')
   assert(args.contents==vehicleInventoryContents(vehicle),'Server contents changed during check')
   assert((peers.client1:getInventory():getItemWithID(item:getID())~=nil)==(phase=='native-take'),'Server actor item differs')
   assert(not peers.client2:getInventory():getItemWithID(item:getID()),'Observer acquired a duplicate')
   acks[role]=true;print('[VEHICLE_INVENTORY] ACK '..role..' '..phase)
  elseif command=='acted' then
   assert(role=='client1' and stage=='act-'..args.action,'Unexpected native action receipt');stage='settle-'..args.action
  else error('Unknown client command '..tostring(command))end
 end)
 if not ok then fail(err)end
end)
Events.OnTick.Add(function()
 if stage=='done' or stage=='failed' then return end
 local ok,err=pcall(function()
  if deadline then assert(now()<deadline,'Server timeout '..stage..'/'..tostring(phase))end
  if stage=='waiting' and all() then
   vehicleInventoryTracePhase('initial');F.prepare(peers.client1);vehicle=F.vehicle
   music(vehicle)
   local c=vehicle:getPartById('GloveBox'):getItemContainer();item=assert(c:AddItem('Base.Wrench'));sendAddItemToContainer(c,item)
   local bed=assert(vehicle:getPartById('TruckBed'):getItemContainer())
   local bag=assert(bed:AddItem('Base.Tote_Bags'));sendAddItemToContainer(bed,bag)
   nested=assert(bag:getItemContainer());local child=assert(nested:AddItem('Base.Pen'));vehicleInventorySendBag(vehicle,nested,child,true)
   phaseStart('initial')
  elseif stage=='phase' and acks.client1 and acks.client2 then
   print('[VEHICLE_INVENTORY] PASS server '..phase);nextPhase()
  elseif stage=='settle-take' and peers.client1:getInventory():getItemWithID(item:getID()) and not vehicle:getPartById('GloveBox'):getItemContainer():getItemWithID(item:getID())then phaseStart('native-take')
  elseif stage=='settle-return' and not peers.client1:getInventory():getItemWithID(item:getID()) and vehicle:getPartById('GloveBox'):getItemContainer():getItemWithID(item:getID())then phaseStart('native-return')
  elseif stage=='settle-leave' and not peers.client1:getVehicle()then
   oldVehicle=vehicle;oldVehicle:permanentlyRemove();vehicleInventoryTracePhase('replacement')
   F.prepare(peers.client1);vehicle=F.vehicle;music(vehicle)
   item=assert(vehicle:getPartById('GloveBox'):getItemContainer():AddItem('Base.Wrench'));sendAddItemToContainer(vehicle:getPartById('GloveBox'):getItemContainer(),item)
   print('[VEHICLE_INVENTORY] REPLACEMENT old='..oldVehicle:getId()..' new='..vehicle:getId());phaseStart('replacement')
  end
 end)
 if not ok then fail(err)end
end)
