local config=require 'QueueTestSelection'
if config.suite~='item-retention'then return end
local F=require 'ItemRetentionFixture'
local R=require 'PZSurvivorToolkit/ItemRetention'
local View=require 'PZSurvivorToolkit/InventoryRetention'
local JSON=require 'QueueHealthEvents'
local Ordering=require 'RetentionOrderChecks'
local Distribution=require 'DistributeDiagnostics'
local started,done,requested,packet,role,phase,state,actionAt,seen,shotMenu,pendingMenu,placed,vehicleReady
local markerAt
local setupAt,initialMode,orderStage,orderAt
local markDiagnosed
local function emit(event,data)print('[ITEM_RETENTION_TEST] '..event..' '..JSON.encode(data))end
local function find(menu,key)
 for _,option in ipairs(menu.options or {})do
  if option.pzstKey==key then return option end
  if option.subOption then local sub=menu:getSubMenu(option.subOption);local value=sub and find(sub,key);if value then return value end end
 end
end
local function selectedTransfer(items, callback)
 local carried=items[1]:isInPlayerInventory()
 local pane=(carried and getPlayerInventory(0)or getPlayerLoot(0)).inventoryPane
 local menu=assert(ISInventoryPaneContextMenu.createMenu(0,carried,items,150,150,pane),'Transfer menu missing')
 local function findCallback(context)
  for _,option in ipairs(context.options or {})do
   if option.onSelect==callback and not option.notAvailable then return option end
   if option.subOption then local sub=context:getSubMenu(option.subOption);local found=sub and findCallback(sub);if found then return found end end
  end
 end
 local option=assert(findCallback(menu),'Selected transfer menu callback missing')
 option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,option.param6)
 menu:hideAndChildren()
end
local function dispatch(item,release)
 local pane=getPlayerLoot(0).inventoryPane
 if item:isInPlayerInventory()then pane=getPlayerInventory(0).inventoryPane end
 local menu=assert(ISInventoryPaneContextMenu.createMenu(0,item:isInPlayerInventory(),{item},150,150,pane),'Native context menu missing')
 local option=assert(find(menu,release and 'releaseItem'or 'retainItem'),'Toolkit retain/release action missing')
 assert(option.onSelect and not option.notAvailable,'Retention action unavailable')
 pendingMenu={menu=menu,option=option,item=item,key=release and 'releaseItem'or 'retainItem',at=getTimestampMs()+1000}
end
local function observed()
 if seen==phase then return end
 sendClientCommand(F.module,'Observed',{phase=phase});seen=phase
end
local function markerRows()
 local pane=getPlayerLoot(0).inventoryPane
 assert(pane.inventory==state.container,'Retention marker source changed')
 local retained={[packet.ids[1]]=true,[packet.ids[3]]=true,[packet.ids[4]]=true}
 local marked={};for _,index in ipairs(View.marks(pane))do marked[index]=true end
 local count,found=0,{}
 for index,entry in ipairs(pane.items)do
  local expected=false
  if type(entry)=='table'and entry.items then
   local first=entry.cleanUILargeStackOptimized and 1 or entry.cleanUIFirstActualIndex or 2
   for j=first,#entry.items do
    local id=entry.items[j]:getID()
    if retained[id]then expected=true;found[id]=true end
   end
  elseif instanceof(entry,'InventoryItem')then expected=retained[entry:getID()]==true end
  assert((marked[index]==true)==expected,'Wrong physical retained-item marker at row '..index)
  if expected then count=count+1 end
 end
 assert(found[packet.ids[1]]and found[packet.ids[3]]and found[packet.ids[4]],'Retained items missing from visible inventory')
 assert(count>=3,'Retention markers missing')
 return count
end
Events.OnServerCommand.Add(function(module,command,args)
 if module==R.MODULE and command=='Result'then
  emit('RESULT',{role=role,request=args.request,accepted=args.accepted,rejected=args.rejected});return
 end
 if module~=F.module then return end
 if command=='Prepared'then packet=args.target;role=args.role;emit('PREPARED',{role=role,truckId=packet.truckId})
 else phase=command;actionAt=nil end
end)
Events.OnGameStart.Add(function()
 started=true;getPlayer():setGodMod(true);getPlayer():setGhostMode(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
 if getPlayerInfoPanel and getPlayerInfoPanel(0)then getPlayerInfoPanel(0):setVisible(false)end
end)
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,err=pcall(function()
  local player=getPlayer()
  if pendingMenu then
   if getTimestampMs()<pendingMenu.at then return end
   if not shotMenu then getCore():TakeFullScreenshot('item-retention-menu.png');shotMenu=true end
   local option=pendingMenu.option
   local exact=option.onSelect==R.toggle and option.target==0 and type(option.param1)=='table'
    and #option.param1==1 and option.param1[1]==pendingMenu.item and option.pzstKey==pendingMenu.key
   assert(exact,'Native retained-item callback or physical argument changed before dispatch')
   local request=option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,option.param6)
   emit('CALLBACK',{role=role,expectedId=pendingMenu.item:getID(),request=request or -1})
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
   if config.cases[1]=='trunk'then
    for index,page in ipairs({getPlayerInventory(0),getPlayerLoot(0)})do
     page:setVisible(true);page.isCollapsed=false;page:setPinned()
     page:setX(index==1 and 25 or 805);page:setY(50);page:setWidth(750);page:setHeight(500);page:setMaxDrawHeight(500)
     page.inventoryPane:setVisible(true)
    end
   end
   if config.cases[1]=='trunk'then
    initialMode=role=='client1'and 'clean'or 'vanilla'
    CleanUI_setCleanInventoryUIEnabled(initialMode=='clean');setupAt=getTimestampMs()+700
   else sendClientCommand(F.module,'Ready',{})end
   return
  end
  if setupAt then
   if getTimestampMs()<setupAt then return end
   assert(getTimestampMs()<setupAt+10000,'Native retention pane/trunk readiness timeout')
   if not Ordering.ready(state,initialMode)then return end
   Ordering.prepare(state);setupAt=nil;sendClientCommand(F.module,'Ready',{});return
  end
  if phase=='Mark'and not actionAt then
   dispatch(assert(F.item(state,role=='client1'and 1 or 4)),false);actionAt=getTimestampMs()
  elseif phase=='Mark'and not markDiagnosed and getTimestampMs()-actionAt>5000 then
   markDiagnosed=true
   local item=assert(F.item(state,role=='client1'and 1 or 4))
   local part=state.vehicle:getPartById('TruckBed')
   emit('MARK_WAIT',{role=role,lastResult=R.lastResult or {},locator=R.locate(item,player)or {},
    x=player:getX(),y=player:getY(),z=player:getZ(),containerAccess=player:canAccessContainer(state.container),
    vehicleAccess=state.vehicle:canAccessContainer(part:getIndex(),player)})
  elseif phase=='Marked'then
   if F.check(state,'marked')then
    if not orderStage then
     local receipt=Ordering.probe(state,initialMode,true);receipt.role=role;emit('ORDER',receipt)
     orderStage='switch';orderAt=getTimestampMs()+700
     CleanUI_setCleanInventoryUIEnabled(initialMode~='clean');return
    elseif orderStage=='switch'then
     if getTimestampMs()<orderAt then return end
     assert(getTimestampMs()<orderAt+10000,'Toggled retention pane/trunk readiness timeout')
     if not Ordering.ready(state,initialMode=='clean'and 'vanilla'or 'clean')then return end
     local receipt=Ordering.probe(state,initialMode=='clean'and 'vanilla'or 'clean',false)
     receipt.role=role;emit('ORDER',receipt);orderStage='done'
    end
    if not markerAt then
     local pane=getPlayerLoot(0).inventoryPane
     pane:refreshContainer();for _,row in ipairs(pane.itemslist)do if row.items then pane.collapsed[row.name]=false end end
     pane:refreshContainer();pane:setYScroll(0);pane:prerender();markerAt=getTimestampMs()+1000
    elseif getTimestampMs()>=markerAt then
     local count=markerRows()
     if seen~=phase then
      getCore():TakeFullScreenshot('item-retention-markers.png')
      emit('MARKERS',{role=role,markedRows=count,retainedIds=3})
     end
     observed()
    end
   end
  elseif phase=='ManualMultiple'and role=='client1'and not actionAt then
   selectedTransfer({assert(F.item(state,1)),assert(F.item(state,4))},ISInventoryPaneContextMenu.onGrabItems)
   actionAt=getTimestampMs()
  elseif phase=='MultipleMoved'then
   local valid=role=='client1'and F.check(state,'multiple')or role~='client1'
    and state.container:getItemById(packet.ids[1])==nil and state.container:getItemById(packet.ids[4])==nil
    and R.isRetained(state.container:getItemById(packet.ids[3]))
   if valid then
    if seen~=phase then emit('MULTIPLE',{role=role,ids={packet.ids[1],packet.ids[4]},retained=true})end
    observed()
   end
  elseif phase=='ManualReturn'and role=='client1'and not actionAt then
   getPlayerLoot(0):setForceSelectedContainer(state.container)
   selectedTransfer({assert(F.item(state,1)),assert(F.item(state,4))},ISInventoryPaneContextMenu.onPutItems)
   actionAt=getTimestampMs()
  elseif phase=='Distribute'and role=='client1'and not actionAt then
   getPlayerLoot(0):setForceSelectedContainer(state.container)
   -- Check the same native stand the sorter will select, after the crate has
   -- become a blocking object and with the actual cargo actor as its origin.
   local crateSquare=state.crate:getSquare()
   local stand=AdjacentFreeTileFinder.Find(crateSquare,player)
   local function position(square)
    return square and square:getX()..','..square:getY()..','..square:getZ()or 'nil'
   end
   assert(stand and stand:canStand()and not stand:isVehicleIntersecting(),
    'Fixture Distribute stand overlaps an obstacle: actor='..position(player:getCurrentSquare())
     ..' crate='..position(crateSquare)..' stand='..position(stand))
   local handler=ISLootWindowObjectControlHandler_LootSorterDistribute:new()
   handler.container=state.container;handler.playerNum=0;handler.lootWindow=getPlayerLoot(0)
   assert(handler:shouldBeVisible(),'Distribute toolbar unavailable')
   Distribution.start(state);handler:perform();actionAt=getTimestampMs()
   Distribution.sample(state,role,true)
  elseif phase=='Distribute'and role=='client1'and actionAt then
   Distribution.sample(state,role,false)
  elseif phase=='Distributed'then
   if role=='client1'then Distribution.sample(state,role,true)end
   Distribution.stop()
   if F.check(state,'distributed')then observed()end
  elseif phase=='Manual'and role=='client1'and not actionAt then
   -- Stage the actor at the native trunk access area; this case verifies
   -- deliberate transfer admission, not pathfinding around the spawned truck.
   player:teleportTo(math.floor(packet.x),math.floor(packet.y),0)
   player:setX(packet.x);player:setY(packet.y);player:setNextX(packet.x);player:setNextY(packet.y)
   player:setLastX(packet.x);player:setLastY(packet.y)
   selectedTransfer({assert(F.item(state,1))},ISInventoryPaneContextMenu.onGrabItems);actionAt=getTimestampMs()
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
 if not ok then
  done=true
  if state and phase=='Marked'then
   local captured,snapshot=pcall(Ordering.snapshot,state)
   emit('ORDER_DIAGNOSTIC',{role=role,before=Ordering.before or {},after=Ordering.after or {},
    current=captured and snapshot or {error=tostring(snapshot)}})
  end
  emit('FAIL',{role=role or 'unknown',error=tostring(err)})
 end
end)
