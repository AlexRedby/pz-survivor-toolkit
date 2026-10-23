local config=require 'QueueTestSelection'
if config.suite~='item-retention'then return end
local F=require 'ItemRetentionFixture'
local R=require 'PZSurvivorToolkit/ItemRetention'
local JSON=require 'QueueHealthEvents'
local started,done,requested,packet,role,phase,state,actionAt,seen,shotMenu,pendingMenu,placed,vehicleReady
local function emit(event,data)print('[ITEM_RETENTION_TEST] '..event..' '..JSON.encode(data))end
local function find(menu,key)
 for _,option in ipairs(menu.options or {})do
  if option.pzstKey==key then return option end
  if option.subOption then local sub=menu:getSubMenu(option.subOption);local value=sub and find(sub,key);if value then return value end end
 end
end
local function dispatch(item,release)
 local pane=getPlayerLoot(0).inventoryPane
 if item:isInPlayerInventory()then pane=getPlayerInventory(0).inventoryPane end
 local menu=assert(ISInventoryPaneContextMenu.createMenu(0,item:isInPlayerInventory(),{item},150,150,pane),'Native context menu missing')
 local option=assert(find(menu,release and 'releaseItem'or 'retainItem'),'Toolkit retain/release action missing')
 assert(option.onSelect and not option.notAvailable,'Retention action unavailable')
 pendingMenu={menu=menu,option=option,at=getTimestampMs()+1000}
end
local function observed()
 if seen==phase then return end
 sendClientCommand(F.module,'Observed',{phase=phase});seen=phase
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~=F.module then return end
 if command=='Prepared'then packet=args.target;role=args.role;emit('PREPARED',{role=role,truckId=packet.truckId})
 else phase=command;actionAt=nil end
end)
Events.OnGameStart.Add(function()
 started=true;getPlayer():setGodMod(true);getPlayer():setGhostMode(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,err=pcall(function()
  local player=getPlayer()
  if pendingMenu then
   if getTimestampMs()<pendingMenu.at then return end
   if not shotMenu then getCore():TakeFullScreenshot('item-retention-menu.png');shotMenu=true end
   local option=pendingMenu.option
   option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,option.param6)
   pendingMenu.menu:hideAndChildren();pendingMenu=nil
   return
  end
  if not requested then requested=true;sendClientCommand(F.module,'Prepare',{});return end
  if not packet then return end
  if not state then
   if not placed then
    player:teleportTo(math.floor(packet.x),math.floor(packet.y),0)
    player:setX(packet.x);player:setY(packet.y);player:setNextX(packet.x);player:setNextY(packet.y)
    player:setLastX(packet.x);player:setLastY(packet.y);placed=true
   end
   local vehicle,container,crate=F.resolve(packet);if not vehicle then return end
   if not vehicleReady then vehicleReady=true;sendClientCommand(F.module,'VehicleReady',{})end
   if container:getItems():size()~=(config.cases[1]=='reload'and 2 or 4)then return end
   state={vehicle=vehicle,container=container,crate=crate,packet=packet,player=player}
   assert(not getActivatedMods():contains('organizedCategories_core'),'OC active on client')
   getPlayerLoot(0):refreshBackpacks();getPlayerLoot(0):setForceSelectedContainer(container)
   sendClientCommand(F.module,'Ready',{});return
  end
  if phase=='Mark'and not actionAt then
   dispatch(assert(F.item(state,role=='client1'and 1 or 4)),false);actionAt=getTimestampMs()
  elseif phase=='Marked'then
   if F.check(state,'marked')then observed()end
  elseif phase=='Distribute'and role=='client1'and not actionAt then
   getPlayerLoot(0):setForceSelectedContainer(state.container)
   local handler=ISLootWindowObjectControlHandler_LootSorterDistribute:new()
   handler.container=state.container;handler.playerNum=0;handler.lootWindow=getPlayerLoot(0)
   assert(handler:shouldBeVisible(),'Distribute toolbar unavailable')
   handler:perform();actionAt=getTimestampMs()
  elseif phase=='Distributed'then
   if F.check(state,'distributed')then observed()end
  elseif phase=='Manual'and role=='client1'and not actionAt then
   -- Stage the actor at the native trunk access area; this case verifies
   -- deliberate transfer admission, not pathfinding around the spawned truck.
   player:teleportTo(math.floor(packet.x),math.floor(packet.y),0)
   player:setX(packet.x);player:setY(packet.y);player:setNextX(packet.x);player:setNextY(packet.y)
   player:setLastX(packet.x);player:setLastY(packet.y)
   ISInventoryPaneContextMenu.onGrabItems({assert(F.item(state,1))},0);actionAt=getTimestampMs()
  elseif phase=='Moved'then
   if role=='client1' then if F.check(state,'manual')then observed()end
   elseif state.container:getItemById(packet.ids[1])==nil
    and R.isRetained(assert(state.container:getItemById(packet.ids[3])))
    and R.isRetained(assert(state.container:getItemById(packet.ids[4])))then observed()end
  elseif phase=='Release'and role=='client1'and not actionAt then
   dispatch(assert(F.item(state,1)),true);actionAt=getTimestampMs()
  elseif phase=='Done'then
   if role=='client1'and not F.check(state,'released')then return end
   assert(R.isRetained(assert(state.container:getItemById(packet.ids[3]))),'Legacy flag lost')
   assert(R.isRetained(assert(state.container:getItemById(packet.ids[4]))),'Observer mark lost')
   emit('VERIFIED',F.receipt(role,state));emit('COMPLETE',{case='trunk',role=role});done=true
  elseif phase=='Reloaded'then
   if role=='client1'and not F.check(state,'released')then return end
   assert(state.crate:getContainer():getItemById(packet.ids[2]),'Saved distributed item missing')
   assert(R.isRetained(assert(state.container:getItemById(packet.ids[3]))),'Saved legacy mark missing')
   assert(R.isRetained(assert(state.container:getItemById(packet.ids[4]))),'Saved Toolkit mark missing')
   emit('PERSISTED',F.persisted(role,state));emit('COMPLETE',{case='reload',role=role});done=true
  end
 end)
 if not ok then done=true;emit('FAIL',{role=role or 'unknown',error=tostring(err)})end
end)
