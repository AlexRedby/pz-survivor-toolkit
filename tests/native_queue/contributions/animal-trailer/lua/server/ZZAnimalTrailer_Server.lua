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
local state
local function log(s) print('[ANIMAL_TRAILER] SERVER '..s) end
local function reply(command,args) sendServerCommand(state.player,'AnimalTrailerBaseline',command,args or {}) end
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
Events.OnClientCommand.Add(function(module,command,player,args)
 if module~='AnimalTrailerBaseline' then return end
 if command=='Ready' then
  if state then if state.sent then reply('Fixture',state.args) end;return end
  local v,x,y=spawn();if not v then return end;state={vehicle=v,player=player,args={ids={}}}
  for i,kind in ipairs({'hen','hen','chick'}) do
   local breed=AnimalDefinitions.getDef(kind):getBreedByName('rhodeisland')
   local a=assert(addAnimal(getCell(),x+3,y,0,kind,breed))
   assert(a:getData(),'animal data missing');a:setWild(false);a:addToWorld();v:addAnimalInTrailer(a)
   state.args.ids[i]=a:getAnimalID()
   log('SEEDED kind='..kind..' animal='..a:getAnimalID()..' online='..a:getOnlineID())
  end
  state.observationStart=getTimestampMs();if animalTimerObserve then log('TIMER '..animalTimerObserve(v)) end
 elseif command=='EquipWeapon' then
  local weapon=player:getInventory():AddItem('Base.BaseballBat');sendAddItemToContainer(player:getInventory(),weapon)
  reply('WeaponReady',{id=weapon:getID()});log('WEAPON_CREATED id='..weapon:getID())
 elseif command=='Verify' then
  local p=player:getPrimaryHandItem();local a=p and p:getAnimal()
  log('WHERE index='..args.index..' '..whereabouts(player,state.args.ids))
  log('VERIFY index='..args.index..' count='..state.vehicle:getAnimals():size()..' hand='..tostring(p)..' animal='..tostring(a and a:getAnimalID()))
  reply('Verified',{index=args.index,count=state.vehicle:getAnimals():size(),animal=a and a:getAnimalID() or -1})
 elseif command=='VerifyDrop' then
  local found=false;local sq=player:getSquare()
  for x=sq:getX()-5,sq:getX()+5 do for y=sq:getY()-5,sq:getY()+5 do local square=getSquare(x,y,0);if square then local animals=square:getAnimals();for i=0,animals:size()-1 do if animals:get(i):getAnimalID()==state.args.ids[args.index] then found=true end end end end end
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
 if state and not state.sent and state.vehicle:getId()>=0 and getTimestampMs()-state.observationStart>(animalTimerObserve and cfg.timerObservationMs or 0) then
  if animalTimerResult then log('TIMER '..animalTimerResult()) end
  state.sent=true;state.args.vehicleId=state.vehicle:getId();reply('Fixture',state.args)
  log('FIXTURE trailer='..state.args.vehicleId..' count='..state.vehicle:getAnimals():size())
 end
end)
