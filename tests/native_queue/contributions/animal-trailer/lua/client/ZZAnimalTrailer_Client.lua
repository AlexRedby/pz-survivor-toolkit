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
require 'TimedActions/Animals/ISRemoveAnimalFromTrailer'
require 'ISUI/ISVehicleAnimalUI'
local connecting,advanced,ingame=false,false,false
local function log(s) print('[ANIMAL_TRAILER] CLIENT '..s) end
Events.OnMainMenuEnter.Add(function()
 if connecting or isClient() or not cfg.connect then return end;connecting=true
 local c=cfg.connect
 assert(c.username and c.password and c.port, 'runner must provide fixture login and port')
 ConnectToServer.instance:connect(MainScreen.instance,'Animal trailer test',c.username,c.password,c.host or '127.0.0.1','',tostring(c.port),'',false,true,1)
end)
Events.OnConnected.Add(function() connecting=true;log('CONNECTED') end)
Events.OnPreUIDraw.Add(function()
 if not connecting or advanced or isIngameState() then return end
 if MainScreen.instance.charCreationProfession:getIsVisible() or MapSpawnSelect.instance:getIsVisible() then
  advanced=true;MapSpawnSelect.instance:useDefaultSpawnRegion();MapSpawnSelect.instance:setVisible(false)
  MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'});MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
 end
end)
Events.OnGameStart.Add(function() ingame=true;log('INGAME '..getCore():getVersion());if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end end)
local function createFixture(Session)
local Events=Session and Session.events or Events
local sendClientCommand=Session and function(module,command,args) Session.send(command,args) end or sendClientCommand
local fixture,index,phase,at,lastReady=nil,1,'waiting',0,0
local equipment=not Session or Session.case:find('equipment') or Session.case:find('combined')
local ghost=not Session or Session.case=='ghost'
local movement=Session and require 'QueueAnimalMovement'
local reset
if Session then
 assert(not getPlayer():getPrimaryHandItem() and not getPlayer():getSecondaryHandItem(),'session requires initially empty hands')
 log('INGAME '..getCore():getVersion())
end
local function done()
 if Session then
  phase='returning';at=getTimestampMs();reset=movement.restore(Session,getPlayer(),fixture.origin)
 else log('COMPLETE');phase='done';sendClientCommand('AnimalTrailerBaseline','Done',{}) end
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~='AnimalTrailerBaseline' then return end
 if command=='Fixture' and not fixture then fixture=args;at=getTimestampMs();log('FIXTURE '..args.vehicleId)
 elseif command=='Verified' then
  log('SERVER_RESULT index='..args.index..' count='..args.count..' animal='..args.animal)
  if index<=3 then local item=getPlayer():getPrimaryHandItem();if item then ISInventoryPaneContextMenu.onDropItems({item},0) end;phase='dropping';at=getTimestampMs()
  else done() end
 elseif command=='DropVerified' then local v=getVehicleById(fixture.vehicleId);log('DROP_VERIFIED index='..args.index..' found='..tostring(args.found)..' handsEmpty='..tostring(args.handsEmpty)..' clientTrailer='..v:getAnimals():size());if index==3 then done() else index=index+1;if index==2 then sendClientCommand('AnimalTrailerBaseline','EquipWeapon',{});phase='weaponrequest' else phase='waiting' end;at=getTimestampMs() end
 elseif command=='WeaponReady' then fixture.weapon=args.id;phase='weaponwaiting';at=getTimestampMs()
 elseif command=='Cleared' then index=index+1;phase='waiting';at=getTimestampMs() end
 if command=='PositionReset' and Session then
  if phase~='returning' or not movement.confirm(reset,args) then Session.quarantine('server position reset receipt mismatch');return end
  log('POSITION_RESET nativeWalk=true serverAck=true');log('COMPLETE');phase='done';Session.finish(true)
 end
end)
Events.OnTick.Add(function()
 if not ingame then return end
 local now=getTimestampMs()
 local p=getPlayer()
 local function label(item) return item and (item:getFullType()..'#'..item:getID()..'/'..tostring(instanceof(item,'AnimalInventoryItem') and item:getAnimal() and item:getAnimal():getAnimalID())) or 'nil' end
 local inv={};local items=p:getInventory():getItems();for i=0,items:size()-1 do local it=items:get(i);if instanceof(it,'AnimalInventoryItem') then inv[#inv+1]=label(it) end end
 local q=ISTimedActionQueue.getTimedActionQueue(p)
 local signature=label(p:getPrimaryHandItem())..'|'..label(p:getSecondaryHandItem())..'|inv='..table.concat(inv,',')..'|action='..tostring(q.queue[1] and q.queue[1].Type)
 if signature~=_G.AnimalTraceLast then _G.AnimalTraceLast=signature;log('HANDS index='..index..' phase='..phase..' '..signature) end

 if not fixture then if now-lastReady>2000 then lastReady=now;sendClientCommand('AnimalTrailerBaseline','Ready',{}) end;return end
 local v=getVehicleById(fixture.vehicleId);if not v then return end
 if phase=='weaponwaiting' then
  local bat=p:getInventory():getItemWithID(fixture.weapon)
  if bat then ISTimedActionQueue.add(ISEquipWeaponAction:new(p,bat,50,true,true));phase='waiting';at=now;log('WEAPON_NATIVE_EQUIP id='..bat:getID()) end
 elseif phase=='waiting' and now-at>cfg.waitBeforeGrabMs then
  local a;local ids={}
  for i=0,v:getAnimals():size()-1 do local x=v:getAnimals():get(i);ids[#ids+1]=x:getAnimalID()..'/'..x:getOnlineID();if x:getAnimalID()==fixture.ids[index] then a=x end end
  if not a then if now-at>15000 then log('MISSING index='..index..' ids='..table.concat(ids,','));phase='done' end;return end
  log('QUEUE index='..index..' target='..a:getAnimalID()..' ids='..table.concat(ids,','))
  if equipment and animalHandsRaceArm then log('ORDER_ARM '..animalHandsRaceArm(p)) end;ISVehicleAnimalUI.onGrabAnimal({character=p,vehicle=v},a);phase='acting';at=now
 elseif phase=='dropping' and now-at>cfg.waitAfterDropMs then sendClientCommand('AnimalTrailerBaseline','VerifyDrop',{index=index});phase='dropverifying'
 elseif phase=='acting' and now-at>cfg.waitAfterGrabMs and #q.queue==0 then
  log('WHERE index='..index..' '..whereabouts(getPlayer(),fixture.ids));if equipment and animalHandsRaceStatus then log('ORDER_STATUS '..animalHandsRaceStatus());log('ORDER_RELEASE '..animalHandsRaceRelease()) end;local p=getPlayer();local item=p:getPrimaryHandItem();local a=item and item:getAnimal()
  if ghost and index==1 and animalTrailerReplayProbe then log('REPLAY '..animalTrailerReplayProbe(p,v)) end
  local remaining={};for i=0,v:getAnimals():size()-1 do local x=v:getAnimals():get(i);remaining[#remaining+1]=x:getAnimalID()..'/'..x:getOnlineID() end;log('REMAINING '..table.concat(remaining,','))
  log('AFTER index='..index..' count='..v:getAnimals():size()..' hand='..tostring(item)..' animal='..tostring(a and a:getAnimalID())..' queue='..#ISTimedActionQueue.getTimedActionQueue(p).queue)
  sendClientCommand('AnimalTrailerBaseline','Verify',{index=index});phase='verifying'
 elseif phase=='returning' and now-at>30000 then
  Session.quarantine('native position reset or server ACK deadline')
 end
end)

if Session then
 local lifecycle=require 'QueueAnimalOwnership'
 Session.readyToClean=function()
  if not reset or not reset.confirmed or not movement.at(getPlayer(),reset.origin) then return false end
  if #ISTimedActionQueue.getTimedActionQueue(getPlayer()).queue~=0 then return false end
  if equipment and animalHandsRaceStatus then
   local status=animalHandsRaceStatus()
   if not status:find('armed=false pending=-1',1,true) then return false end
  end
  return true
 end
 Session.cleanup=function()
  if animalHandsRaceReset then assert(animalHandsRaceReset()=='clean','packet-order reset failed') end
  if animalTimerReset then assert(animalTimerReset()=='clean','timer reset failed') end
  local p=getPlayer();assert(not p:getPrimaryHandItem() and not p:getSecondaryHandItem(),'fixture hands retained items')
  assert(reset and reset.arrived and reset.confirmed and movement.at(p,reset.origin),'fixture position reset failed')
  _G.AnimalTraceLast=nil
  log('PROBE_RESET clean=true')
  return true
 end
 Session.clean=function(receipt)
  local clean,reason=lifecycle.verify(receipt,getPlayer())
  if clean then log('OWNED_RESET animals=3 items=4 trailer=1') end
  return clean,reason
 end
end
end
if cfg.cases then
 local session=require 'QueueAnimalLifecycle'
 session.start(cfg,createFixture,false)
else createFixture(nil) end
