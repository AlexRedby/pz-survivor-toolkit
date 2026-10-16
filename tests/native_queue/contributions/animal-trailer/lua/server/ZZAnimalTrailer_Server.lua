local cfg=assert(AnimalTrailerFixtureConfig, "missing generated fixture configuration")

local function whereabouts(p,ids)
 local items=p:getInventory():getItems();local inv={}
 for i=0,items:size()-1 do local item=items:get(i);if instanceof(item,'AnimalInventoryItem') then local a=item:getAnimal();inv[#inv+1]=item:getID()..'/'..tostring(a and a:getAnimalID()) end end
 local live,world={},{};local sq=p:getSquare()
 for x=sq:getX()-5,sq:getX()+5 do for y=sq:getY()-5,sq:getY()+5 do local square=getSquare(x,y,0);if square then
  local animals=square:getAnimals();for i=0,animals:size()-1 do local a=animals:get(i);live[#live+1]=a:getAnimalID() end
  local objects=square:getWorldObjects();for i=0,objects:size()-1 do local item=objects:get(i):getItem();if item and instanceof(item,'AnimalInventoryItem') then local a=item:getAnimal();world[#world+1]=item:getID()..'/'..tostring(a and a:getAnimalID()) end end
 end end end
 return 'inventory='..table.concat(inv,',')..' groundAlive='..table.concat(live,',')..' groundItems='..table.concat(world,',')
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
local function reply(command,args)
 if Session then Session.reply(fixtureState.player,command,args or {}) else sendServerCommand(fixtureState.player,'AnimalTrailerBaseline',command,args or {}) end
end
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='AnimalTrailerBaseline' then return end
 if command=='Ready' then
  if fixtureState then if fixtureState.sent then reply('Fixture',fixtureState.args) end;return end
  local v,x,y=spawn();if not v then return end;fixtureState={vehicle=v,player=player,args={ids={}},animals={},items={}}
  for i,kind in ipairs({'hen','hen','chick'}) do
   local breed=AnimalDefinitions.getDef(kind):getBreedByName('rhodeisland')
   local a=assert(addAnimal(getCell(),x+3,y,0,kind,breed))
   assert(a:getData(),'animal data missing');a:setWild(false);a:addToWorld();v:addAnimalInTrailer(a)
   fixtureState.args.ids[i]=a:getAnimalID();fixtureState.animals[#fixtureState.animals+1]={id=a:getAnimalID(),online=a:getOnlineID()}
   log('SEEDED kind='..kind..' animal='..a:getAnimalID()..' online='..a:getOnlineID())
  end
  fixtureState.observationStart=getTimestampMs();if timer and animalTimerObserve then log('TIMER '..animalTimerObserve(v)) end
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
  log('DROP index='..args.index..' found='..tostring(found)..' handsEmpty='..tostring(empty))
  reply('DropVerified',{index=args.index,found=found,handsEmpty=empty})
 elseif command=='ClearHand' then
  local item=player:getPrimaryHandItem()
  if item then player:removeFromHands(item);player:getInventory():Remove(item);sendRemoveItemFromContainer(player:getInventory(),item) end
  reply('Cleared',{})
 elseif command=='Done' then log('COMPLETE')
 end
end)
Events.OnTick.Add(function()
 if fixtureState and not fixtureState.sent and fixtureState.vehicle:getId()>=0 and getTimestampMs()-fixtureState.observationStart>(timer and animalTimerObserve and cfg.timerObservationMs or 0) then
  if timer and animalTimerResult then log('TIMER '..animalTimerResult()) end
  fixtureState.sent=true;fixtureState.args.vehicleId=fixtureState.vehicle:getId();reply('Fixture',fixtureState.args)
  log('FIXTURE trailer='..fixtureState.args.vehicleId..' count='..fixtureState.vehicle:getAnimals():size())
 end
end)

if Session then
 local ownership=require 'QueueAnimalOwnership'
 Session.cleanup=function()
  assert(fixtureState and fixtureState.sent,'fixture never owned a seeded world')
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
