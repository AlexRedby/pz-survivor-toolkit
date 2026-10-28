require 'TimedActions/ISInventoryTransferAction'
require 'Vehicles/TimedActions/ISEnterVehicle'
require 'Vehicles/TimedActions/ISExitVehicle'
local C=require 'QueueTestSelection'
local M='VehicleInventoryTest'
local function read(name)local f=getFileReader(name,false);if not f then return nil end;local x=f:readLine();f:close();return x end
local function write(name,x)local f=assert(getFileWriter(name,true,false));f:write(x);f:close()end
local role=assert(read('smoke-user.txt'))
local CHECKPOINT='vehicle-inventory-rejoin.txt'
local rejoined=read(CHECKPOINT)=='connecting' or read(CHECKPOINT)=='rejoined'
local pending,action,actionStage,untilAt,old,exitStage
local ready,done,failed,connecting,advanced=false,false,false,false,false
local function now()return getTimestampMs()end
local function send(kind,args)sendClientCommand(M,kind,args or {})end
local function guard(fn)local ok,err=pcall(fn);if not ok then failed=true;print('[VEHICLE_INVENTORY] FAIL '..role..' '..tostring(err))end end
Events.OnServerCommand.Add(function(module,command,args)
 if module~=M then return end
 guard(function()
  if command=='check'then pending=args;untilAt=now()+45000
  elseif command=='act'then assert(role=='client1');action=args;actionStage='start';untilAt=now()+45000
  elseif command=='reconnect'then assert(role=='client2');exitStage='pause';untilAt=now()+45000
  elseif command=='complete'then done=true;print('[VEHICLE_INVENTORY] COMPLETE '..role)
  else error('Unknown server command '..tostring(command))end
 end)
end)
local function gameTick()
 local p=getPlayer();if not isIngameState() or not p or not p:getSquare() or failed or done then return end
 p:setGodMod(true)
 if not ready then
  if rejoined then write(CHECKPOINT,'rejoined')end
  ready=true;send('ready',{rejoined=rejoined});print('[VEHICLE_INVENTORY] READY '..role..' rejoined='..tostring(rejoined))
 end
 if untilAt then assert(now()<untilAt,'Client timeout')end
 if pending then
  local v=getVehicleById(pending.id)
  if not v then return end
  local contents=vehicleInventoryContents(v)
  if contents~=pending.contents then return end
  if role=='client1' and (p:getInventory():getItemWithID(pending.item)~=nil)~=pending.held then return end
  if role=='client2' then assert(not p:getInventory():getItemWithID(pending.item),'Observer has duplicate')end
  if pending.phase=='replacement'then assert(not old or old~=v,'Replacement kept old vehicle object')end
  old=v
  print('[VEHICLE_INVENTORY] PASS '..role..' '..pending.phase..' contents='..contents)
  send('checked',{phase=pending.phase,contents=contents});pending=nil;untilAt=nil
 end
 if action then
  local v=assert(getVehicleById(action.id));local q=ISTimedActionQueue.getTimedActionQueue(p).queue
  if actionStage=='start'then
   if action.action=='leave'then ISTimedActionQueue.add(ISExitVehicle:new(p));actionStage='finish'
   elseif not p:getVehicle()then
    local pos=Vector3f.new();v:getWorldPos(v:getPassengerPosition(0,'outside'):getOffset(),pos)
    p:setX(pos:x());p:setY(pos:y());p:setNextX(pos:x());p:setNextY(pos:y());p:setLastX(pos:x());p:setLastY(pos:y());p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow()
    ISTimedActionQueue.add(ISEnterVehicle:new(p,v,0));actionStage='enter'
   else actionStage='transfer'end
  elseif actionStage=='enter' and #q==0 and p:getVehicle()==v then actionStage='transfer'
  elseif actionStage=='transfer'then
   local car=assert(v:getPartById('GloveBox'):getItemContainer())
   local source=action.action=='take' and car or p:getInventory();local dest=action.action=='take' and p:getInventory() or car
   ISTimedActionQueue.add(ISInventoryTransferAction:new(p,assert(source:getItemWithID(action.item)),source,dest));actionStage='finish'
  elseif actionStage=='finish' and #q==0 then
   local settled=action.action=='leave' and p:getVehicle()==nil or action.action=='take' and p:getInventory():getItemWithID(action.item)~=nil or action.action=='return' and p:getInventory():getItemWithID(action.item)==nil
   if settled then print('[VEHICLE_INVENTORY] ACTED '..action.action);send('acted',{action=action.action});action=nil;untilAt=nil end
  end
 end
end
Events.OnTick.Add(function()guard(gameTick)end)
local function menuTick()
 if done or failed then return end
 if exitStage then
  assert(now()<untilAt,'Native menu exit timeout')
  local menu=assert(MainScreen.instance)
  if exitStage=='pause'then
   if not menu:isVisible()then local key=getCore():getKey(KeybindId.MAIN_MENU);if key==0 then key=Keyboard.KEY_ESCAPE end;ToggleEscapeMenu(key)end
   exitStage='exit';return
  end
  if not menu:isVisible() or isQuitCooldown and isQuitCooldown()then return end
  write(CHECKPOINT,'pending');ready=false;rejoined=true;exitStage=nil;untilAt=nil
  print('[VEHICLE_INVENTORY] NATIVE_EXIT '..role);menu.exitOption.onMouseDown(menu.exitOption,0,0)
 end
 if not isIngameState() and role=='client2' and read(CHECKPOINT)=='pending' and not connecting then
  local menu=MainScreen and MainScreen.instance
  if menu and menu.inGame==false and menu:isVisible() and ConnectToServer and ConnectToServer.instance then
   write(CHECKPOINT,'connecting');connecting=true;print('[VEHICLE_INVENTORY] NATIVE_RECONNECT '..role)
   ConnectToServer.instance:connect(menu,'Vehicle inventory rejoin',role,'smoke-local-only','127.0.0.1','',tostring(C.port),'',false,true,1)
  end
 end
 if not isIngameState() and rejoined and not advanced then
  local menu=MainScreen and MainScreen.instance
  if menu and menu.charCreationProfession and MapSpawnSelect and (menu.charCreationProfession:isVisible() or MapSpawnSelect.instance and MapSpawnSelect.instance:isVisible())then
   advanced=true;if MapSpawnSelect.instance then MapSpawnSelect.instance:useDefaultSpawnRegion();MapSpawnSelect.instance:setVisible(false)end
   menu.charCreationProfession:onOptionMouseDown({internal='NEXT'});menu.charCreationMain:onOptionMouseDown({internal='NEXT'})
  end
 end
end
Events.OnMainMenuEnter.Add(function()guard(menuTick)end)
Events.OnPreUIDraw.Add(function()guard(menuTick)end)
Events.OnTickEvenPaused.Add(function()guard(menuTick)end)
