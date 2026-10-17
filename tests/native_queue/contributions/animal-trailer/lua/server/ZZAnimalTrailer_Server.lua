local cfg=assert(AnimalTrailerFixtureConfig, "missing generated fixture configuration")

local function whereabouts(p,ids)
 local items=p:getInventory():getItems();local inv={}
 for i=0,items:size()-1 do local item=items:get(i);if instanceof(item,'AnimalInventoryItem') then local a=item:getAnimal();inv[#inv+1]=item:getID()..'/'..tostring(a and a:getAnimalID()) end end
 local live,world={},{};local sq=p:getSquare();local scanned=0
 for x=sq:getX()-5,sq:getX()+5 do for y=sq:getY()-5,sq:getY()+5 do local square=getSquare(x,y,0);if square then scanned=scanned+1
  local animals=square:getAnimals();for i=0,animals:size()-1 do local a=animals:get(i);live[#live+1]=a:getAnimalID() end
  local objects=square:getWorldObjects();for i=0,objects:size()-1 do local item=objects:get(i):getItem();if item and instanceof(item,'AnimalInventoryItem') then local a=item:getAnimal();world[#world+1]=item:getID()..'/'..tostring(a and a:getAnimalID()) end end
 end end end
 return 'inventory='..table.concat(inv,',')..' groundAlive='..table.concat(live,',')..' groundItems='..table.concat(world,',')..' handsEmpty='..tostring(not p:getPrimaryHandItem() and not p:getSecondaryHandItem())..' scannedSquares='..scanned..' primaryID='..(p:getPrimaryHandItem() and p:getPrimaryHandItem():getID() or -1)..' secondaryID='..(p:getSecondaryHandItem() and p:getSecondaryHandItem():getID() or -1)
end
local function log(s) print('[ANIMAL_TRAILER] SERVER '..s) end
local function spawn()
 for x=10818,10845 do for y=10118,10145 do
  local sq=getSquare(x,y,0)
  if sq and sq:isOutside() and sq:getFloor() and sq:getFloor():getSprite():getName():find('street') then
   local v=addVehicleDebug('Base.Trailer_Livestock',IsoDirections.N,nil,sq)
   if v and v:getSquare() then return v,x,y end
  end
 end end
 return nil
end
Events.OnServerStarted.Add(function() log('READY') end)
local function createFixture(Session)
local Events=Session and Session.events or Events
local fixtureState
local timer=not Session or Session.case:find('timer') or Session.case:find('combined')
local movement=require 'QueueAnimalMovement'
local function reply(command,args)
 if Session then Session.reply(fixtureState.player,command,args or {}) else sendServerCommand(fixtureState.player,'AnimalTrailerBaseline',command,args or {}) end
end
local function fail(reason)
 fixtureState.failed=true
 if Session then Session.quarantine(reason) else error(reason) end
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='AnimalTrailerBaseline' then return end
 if command=='Ready' then
  if fixtureState then assert(fixtureState.player==player,'foreign fixture owner');if fixtureState.sent then reply('Fixture',fixtureState.args) end;return end
  local v,x,y=spawn();if not v then return end;fixtureState={vehicle=v,player=player,args={ids={},origin={x=player:getX(),y=player:getY(),z=player:getZ()}},animals={},items={}}
  for i,kind in ipairs({'hen','hen','chick'}) do
   local breed=AnimalDefinitions.getDef(kind):getBreedByName('rhodeisland')
   local a=assert(addAnimal(getCell(),x+3,y,0,kind,breed))
   assert(a:getData(),'animal data missing');a:setWild(false);a:addToWorld();v:addAnimalInTrailer(a)
   fixtureState.args.ids[i]=a:getAnimalID();fixtureState.animals[#fixtureState.animals+1]={id=a:getAnimalID(),online=a:getOnlineID()}
   log('SEEDED kind='..kind..' animal='..a:getAnimalID()..' online='..a:getOnlineID())
  end
  fixtureState.observationStart=getTimestampMs();if timer and animalTimerObserve then log('TIMER '..animalTimerObserve(v)) end
 elseif command=='VerifyStartPosition' then
  assert(fixtureState and fixtureState.player==player and fixtureState.startIssued
   and not fixtureState.startRequest and not fixtureState.startReady,'unexpected fixture start receipt')
  fixtureState.startRequest=true
 elseif command=='EquipWeapon' then
  local weapon=player:getInventory():AddItem('Base.BaseballBat');sendAddItemToContainer(player:getInventory(),weapon)
  fixtureState.items[weapon:getID()]=weapon;reply('WeaponReady',{id=weapon:getID()});log('WEAPON_CREATED id='..weapon:getID())
 elseif command=='Verify' then
  local p=player:getPrimaryHandItem();local a=p and p:getAnimal();if p then fixtureState.items[p:getID()]=p end
  log('WHERE index='..args.index..' '..whereabouts(player,fixtureState.args.ids))
  log('VERIFY index='..args.index..' count='..fixtureState.vehicle:getAnimals():size()..' hand='..tostring(p)..' animal='..tostring(a and a:getAnimalID()))
  reply('Verified',{index=args.index,count=fixtureState.vehicle:getAnimals():size(),animal=a and a:getAnimalID() or -1})
 elseif command=='VerifyDrop' then
  local found=false;local sq=player:getSquare()
  for x=sq:getX()-5,sq:getX()+5 do for y=sq:getY()-5,sq:getY()+5 do local square=getSquare(x,y,0);if square then local animals=square:getAnimals();for i=0,animals:size()-1 do if animals:get(i):getAnimalID()==fixtureState.args.ids[args.index] then found=true end end end end end
  local empty=not player:getPrimaryHandItem() and not player:getSecondaryHandItem()
  fixtureState.drops=fixtureState.drops or {}
  if found and empty then fixtureState.drops[args.index]=true end
  log('DROP index='..args.index..' found='..tostring(found)..' handsEmpty='..tostring(empty))
  reply('DropVerified',{index=args.index,found=found,handsEmpty=empty})
 elseif command=='ClearHand' then
  local item=player:getPrimaryHandItem()
  if item then player:removeFromHands(item);player:getInventory():Remove(item);sendRemoveItemFromContainer(player:getInventory(),item) end
  reply('Cleared',{})
 elseif command=='RestorePosition' and Session then
  assert(fixtureState and fixtureState.sent and fixtureState.player==player and not fixtureState.returnRequested,'unexpected native return request')
  assert(fixtureState.drops and fixtureState.drops[1] and fixtureState.drops[2] and fixtureState.drops[3]
   and not player:getPrimaryHandItem() and not player:getSecondaryHandItem(),'native return requires three verified live drops and empty hands')
  fixtureState.returnRequested=true
  local origin=fixtureState.args.origin
  local result=animalFixtureRestorePosition(player,origin.x,origin.y,origin.z)
  assert(result=='issued','native return failed: '..tostring(result)..' '..(require 'QueueAnimalMovement').describe(player,origin))
  fixtureState.returnIssued=true
  reply('ReturnIssued',{x=origin.x,y=origin.y,z=origin.z})
 elseif command=='VerifyPosition' and Session then
  assert(fixtureState and fixtureState.player==player and fixtureState.returnIssued and not fixtureState.positionRequest and not fixtureState.positionAcknowledged,'unexpected position reset request')
  fixtureState.positionRequest=true
 elseif command=='Done' then log('COMPLETE')
 end
end)
Events.OnTick.Add(function()
 if fixtureState and fixtureState.failed then return end
 if fixtureState and not fixtureState.startReady then
  local state=fixtureState
  if not state.startIssued and state.vehicle:getId()>=0 then
   state.failed=true
   local square=movement.startSquare(state.vehicle)
   if not square then fail('no free reachable square at trailer AnimalEntry');return end
   state.start={x=square:getX()+0.5,y=square:getY()+0.5,z=square:getZ()}
   local result=animalFixtureRestorePosition(state.player,state.start.x,state.start.y,state.start.z)
   if result~='issued' then fail('native fixture start failed: '..tostring(result));return end
   state.startIssued=getTimestampMs()
   state.failed=false
   reply('StartPositionIssued',{x=state.start.x,y=state.start.y,z=state.start.z,vehicleId=state.vehicle:getId()})
  end
  if state.startIssued then
   if getTimestampMs()-state.startIssued>30000 then fail('native fixture start/client receipt deadline');return end
   if state.startRequest and movement.stagedAt(state.player,state.start) and movement.nearEntry(state.player,state.vehicle) then
    state.startReady=true
    reply('StartPositionReady',state.start)
    log('START_POSITION nativeTeleport=true clientAck=true '..movement.describe(state.player,state.start))
   end
  end
 end
 if fixtureState and fixtureState.positionRequest and (require 'QueueAnimalMovement').at(fixtureState.player,fixtureState.args.origin) then
  fixtureState.positionRequest=false
  fixtureState.positionAcknowledged=true
  reply('PositionReset',{x=fixtureState.player:getX(),y=fixtureState.player:getY(),z=fixtureState.player:getZ()})
  log('POSITION_RESET nativeTeleport=true serverAck=true '..(require 'QueueAnimalMovement').describe(fixtureState.player,fixtureState.args.origin))
 end
 if fixtureState and fixtureState.startReady and not fixtureState.sent and getTimestampMs()-fixtureState.observationStart>(timer and animalTimerObserve and cfg.timerObservationMs or 0) then
  if timer and animalTimerResult then log('TIMER '..animalTimerResult()) end
  fixtureState.sent=true;fixtureState.args.vehicleId=fixtureState.vehicle:getId();reply('Fixture',fixtureState.args)
  log('FIXTURE trailer='..fixtureState.args.vehicleId..' count='..fixtureState.vehicle:getAnimals():size())
 end
end)

if Session then
 local ownership=require 'QueueAnimalOwnership'
 Session.cleanup=function()
  assert(fixtureState and fixtureState.sent,'fixture never owned a seeded world')
  assert(fixtureState.positionAcknowledged and (require 'QueueAnimalMovement').at(fixtureState.player,fixtureState.args.origin),
   'native return was not confirmed '..(require 'QueueAnimalMovement').describe(fixtureState.player,fixtureState.args.origin))
  log('COMPLETE')
  if animalHandsRaceReset then assert(animalHandsRaceReset()=='clean','packet-order reset failed') end
  if animalTimerReset then assert(animalTimerReset()=='clean','timer reset failed') end
  Session.receipt=ownership.remove(fixtureState)
  assert(ownership.verify(Session.receipt,fixtureState.player),'server owned world reset failed')
  log('PROBE_RESET clean=true')
  return true
 end
end
end
if cfg.cases then
 local session=require 'QueueAnimalLifecycle'
 session.start(cfg,createFixture,true)
else createFixture(nil) end
