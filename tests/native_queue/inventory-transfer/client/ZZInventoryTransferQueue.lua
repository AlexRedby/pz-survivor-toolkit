require 'PZSurvivorToolkit/ActionQueuePanel'
local F=require 'QueueInventoryTransferFixture'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local Classes=require 'PZSurvivorToolkit/InventoryClasses'
local started,done,phase,since=false,false,'prepare',0
local ids,state,authority,receipt,command,idleAt,quietAt,previousFrame,idleInventory
local positionedAt,lastWait,lastPlace
local profiles,frames={},{}
local originalAdd
local function restoreAdd()if originalAdd then ISTimedActionQueue.add=originalAdd;originalAdd=nil end end
local function now()return getTimestampMs()end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function emit(row)
 row.suite,row.kind,row.mode,row.actor='inventory-transfer',config.kind,config.mode,'client1';JSON.emit(row)
end
local function trace(name,value)
 value=value or {};value.phase=phase
 print('[INVENTORY_TRANSFER_TEST] '..name..' '..JSON.encode(value))
end
local function bucket()return phase=='idle'and 'idle'or phase=='running'and 'running'or nil end
local function pack(...)return {n=select('#',...),...}end
local function measure(label,callback,...)
 local stage=bucket();if not stage then return callback(...)end
 local before=now();local result=pack(callback(...));local elapsed=now()-before
 profiles[stage]=profiles[stage]or {};local entry=profiles[stage][label]or {calls=0,totalMs=0,maxMs=0}
 profiles[stage][label]=entry;entry.calls=entry.calls+1;entry.totalMs=entry.totalMs+elapsed;entry.maxMs=math.max(entry.maxMs,elapsed)
 return unpack(result,1,result.n)
end
local wrapped={}
local function wrap(owner,name,label)
 if not owner or type(owner[name])~='function'then return end
 wrapped[owner]=wrapped[owner]or {};if wrapped[owner][name]then return end;wrapped[owner][name]=true
 for _,stage in ipairs({'idle','running'})do
  profiles[stage]=profiles[stage]or {};profiles[stage][label]=profiles[stage][label]or {calls=0,totalMs=0,maxMs=0}
 end
 local original=owner[name];owner[name]=function(...)return measure(label,original,...)end
end
local function installProfiles()
 Classes.panes(function(class)
  if not class then return end
  for _,name in ipairs({'refreshContainer','restoreSelection','renderdetails','prerender','render'})do wrap(class,name,'pane.'..name)end
 end)
 for _,page in ipairs({getPlayerInventory(0),getPlayerLoot(0)})do
  wrap(page,'prerender','page.prerender');wrap(page,'render','page.render');wrap(page,'refreshBackpacks','page.refreshBackpacks')
 end
 local panel=PZSurvivorToolkit.ActionQueuePanel
 wrap(panel,'drawRow','actions.drawRow');wrap(panel,'update','actions.update')
 for _,stage in ipairs({'idle','running'})do profiles[stage]['actions.refresh']={calls=0,totalMs=0,maxMs=0}end
 local refresh=panel.refresh
 Events.OnTickEvenPaused.Remove(refresh)
 panel.refresh=function(...)return measure('actions.refresh',refresh,...)end
 Events.OnTickEvenPaused.Add(panel.refresh)
 local policy=PZSurvivorToolkit.ActionQueuePolicy
 wrap(policy,'evaluateMove','policy.evaluateMove');wrap(policy,'evaluateCancel','policy.evaluateCancel')
 local proof=require 'PZSurvivorToolkit/SourceProof';wrap(proof,'matches','sourceProof.matches')
 wrap(PZSurvivorToolkit.ActionQueueDefinitions,'inspect','definitions.inspect')
end
local function request(name)
 if isClient()then sendClientCommand('InventoryTransferTest',name,{case='trunk-15'});return end
 if name=='Prepare'then authority=F.prepare(getPlayer());ids=authority.ids
  print('[INVENTORY_TRANSFER_TEST] PREPARED '..JSON.encode(ids))
 else receipt=assert(F.receipt(authority));print('[INVENTORY_TRANSFER_TEST] VERIFIED '..JSON.encode(receipt))end
end
Events.OnServerCommand.Add(function(module,name,value)
 if module~='InventoryTransferTest'then return end
 if name=='Failed'then print('[QUEUE_TEST] FAIL inventory transfer '..tostring(value.error));done=true
 elseif name=='Prepared'then ids=value;trace('PREPARED_CLIENT',{vehicleId=ids.vehicleId,count=#ids.items})
 elseif name=='Verified'then receipt=value end
end)
Events.OnGameStart.Add(function()
 started=true;since=now();getCore():setOptionPauseOnFocusloss(false)
 getCore():setOptionAutoDrink(false);getPlayer():setAutoDrink(false);getPlayer():setGhostMode(true)
 installProfiles()
end)
Events.OnPreUIDraw.Add(function()
 if not started or done or not isIngameState()then return end
 local stamp=now();local stage=bucket()
 if stage and previousFrame and previousFrame.stage==stage then
  frames[stage]=frames[stage]or {};local values=frames[stage]
  if #values<20000 then values[#values+1]=stamp-previousFrame.stamp end
 end
 previousFrame={stamp=stamp,stage=stage}
end)
local function panes()
 local inventory,loot=getPlayerInventory(0),getPlayerLoot(0)
 inventory:setVisible(true);inventory.isCollapsed=false;inventory:clearMaxDrawHeight();inventory:setPinned();inventory:setNewContainer(getPlayer():getInventory())
 loot:setVisible(true);loot.isCollapsed=false;loot:clearMaxDrawHeight();loot:setPinned();loot:refreshBackpacks()
 loot:selectButtonForContainer(state.trunk);loot:setForceSelectedContainer(state.trunk,60000)
 if loot.inventoryPane.inventory~=state.trunk then return end
 inventory.inventoryPane:refreshContainer();loot.inventoryPane:refreshContainer()
 return inventory.inventoryPane,loot.inventoryPane
end
local function waitForTrunk()
 local access=F.access(state)
 if not access.inArea and (not lastPlace or now()-lastPlace>=500)then
  access=F.place(state);lastPlace=now()
 end
 if access.accessible and access.nearby and panes()then return true end
 if not lastWait or now()-lastWait>=2000 then
  local loot=getPlayerLoot(0);local buttons={}
  for _,button in ipairs(loot.backpacks)do buttons[#buttons+1]=button.inventory:getType()end
  access.buttons=buttons;access.selected=loot.inventoryPane.inventory:getType()
  trace('WAIT_TRUNK',access);lastWait=now()
 end
 assert(now()-positionedAt<30000,'native trunk access/discovery did not settle; see WAIT_TRUNK')
 return false
end
local function dispatch()
 local player=getPlayer();local source,destination=panes();assert(source and destination,'native trunk pane missing')
 assert(state.vehicle:isInArea(state.vehicle:getPartById('TruckBed'):getArea(),player),'player outside native trunk area')
 assert(#queue().queue==0 and not player:hasTimedActions(),'transfer queue not empty')
 command={dropDispatched=false,count=0,transferProgress=false,nativeDurations=true,source='root',destination='trunk',
  queueEmptyBefore=true,selectedItems=#state.items,enqueuedIds={},activeSamples=0}
 local expected={};for _,item in ipairs(state.items)do
  assert(item:getContainer()==player:getInventory()and state.trunk:hasRoomFor(player,item),'source or capacity differs')
  expected[item:getID()]=true
 end
 originalAdd=ISTimedActionQueue.add
 local add=originalAdd;local enqueued={};local tokens={}
 command.uniqueOperationTokens=0;command.unstampedActions=0
 ISTimedActionQueue.add=function(action)
  if action.Type=='ISInventoryTransferAction'then
   assert(not enqueued[action.item:getID()]and expected[action.item:getID()]and action.srcContainer==player:getInventory()and action.destContainer==state.trunk,'native transfer endpoints differ')
   enqueued[action.item:getID()]=true;command.count=command.count+1;command.enqueuedIds[#command.enqueuedIds+1]=action.item:getID()
   command.nativeDuration=action.maxTime
  end
  local result=pack(add(action))
  if action.Type=='ISInventoryTransferAction'then
   local token=action.toolkitQueueOperation
   if not token then command.unstampedActions=command.unstampedActions+1
   elseif not tokens[token]then tokens[token]=true;command.uniqueOperationTokens=command.uniqueOperationTokens+1 end
  end
  return unpack(result,1,result.n)
 end
 local ok,problem=pcall(function()
  -- Invoke the actual destination pane drop callback with the exact physical selection.
  -- Native onMouseUp performs walkToContainer, admission and transferItemsByWeight.
  ISMouseDrag.dragging=state.items;ISMouseDrag.draggingFocus=source
  destination:onMouseUp(5,5);command.dropDispatched=true
 end)
 if not ok then restoreAdd();error(problem)end
 -- CleanUI schedules transferItemsByWeight on the following OnTick. Keep the
 -- observer installed until the entire deferred native batch has been admitted.
end
local function frameSummary(values)
 values=values or {};table.sort(values);local total=0;for _,value in ipairs(values)do total=total+value end
 return {samples=#values,totalMs=total,meanMs=#values>0 and total/#values or 0,
  p50Ms=values[math.max(1,math.ceil(#values*.5))]or 0,p95Ms=values[math.max(1,math.ceil(#values*.95))]or 0,maxMs=values[#values]or 0}
end
local function finish()
 restoreAdd()
 local localReceipt=assert(F.receipt(state),'client exact endpoints differ')
 for i,row in ipairs(receipt.items)do local item=localReceipt.items[i]
  assert(item.id==row.id and item.count==row.count and item.endpoint==row.endpoint,'client authority differs')
 end
 if receipt.filler then
  assert(localReceipt.density and localReceipt.inventory.rootItems==receipt.inventory.rootItems
   and localReceipt.inventory.trunkItems==receipt.inventory.trunkItems,'client dense counts differ from authority')
  for _,endpoint in ipairs({'root','trunk'})do
   assert(localReceipt.filler[endpoint]==receipt.filler[endpoint]and localReceipt.filler.identitiesVerified,'client filler evidence differs')
  end
 end
 assert(command.transferProgress and command.activeSamples>0,'native active transfer was not observed')
 local performance={clock='getTimestampMs',inclusive=true,frames={idle=frameSummary(frames.idle),running=frameSummary(frames.running)},calls=profiles,
  nativeUpdateUnmodified=true,inventory={idle=idleInventory,settled=F.inventory(state)},
  limit='UI frame intervals and inclusive Lua wall time; no GPU or native update timing'}
 print('[INVENTORY_TRANSFER_TEST] PROFILE '..JSON.encode(performance))
 local row={event='case',id='trunk-15',status='passed',command=command,performance=performance,queueIdle=true,
  clientIdentityVerified=true,settleMilliseconds=now()-quietAt}
 for key,value in pairs(receipt)do row[key]=value end;emit(row)
 emit({event='complete',cases=config.cases,expected=1,performed=1,failed=0,skipped=0})
 print('[INVENTORY_TRANSFER_TEST] COMPLETE');done=true
end
Events.OnTick.Add(function()
 if not started or done or not isIngameState()or not getPlayer()or not getPlayer():getSquare()then return end
 local ok,problem=pcall(function()
  if now()-since>180000 then error('inventory transfer timeout '..phase)end
  if phase=='prepare'then
   emit({event='setup',cases=config.cases,expected=1,queueEnabled=PZSurvivorToolkit.Settings.actionQueue(),nativeDurations=true})
   phase='prepared';request('Prepare')
  elseif phase=='prepared'and ids then
   local reason
   state,reason=F.resolve(getPlayer(),ids)
   if not state then
    if not lastWait or now()-lastWait>=2000 then trace('WAIT_RESOLVE',reason);lastWait=now()end
    assert(now()-since<60000,'client fixture did not resolve; see WAIT_RESOLVE');return
   end
   phase='positioned';positionedAt=now();trace('PLACED',F.place(state));lastPlace=now()
  elseif phase=='positioned'then
   if not waitForTrunk()then return end
   phase='idle';idleAt=now();idleInventory=F.inventory(state);trace('IDLE',F.access(state))
  elseif phase=='idle'then
   if now()-idleAt<5000 then return end
   phase='dispatch';dispatch();phase='enqueuing';since=now()
  elseif phase=='enqueuing'then
   if command.count<15 then return end
   assert(command.count==15,'drop did not enqueue exactly fifteen transfers');restoreAdd()
   print('[INVENTORY_TRANSFER_TEST] DISPATCH '..JSON.encode(command))
   phase='running';since=now()
  elseif phase=='running'then
   local current=queue().queue[1]
   if current and current.Type=='ISInventoryTransferAction'and current:isStarted()and current:getJobDelta()>0 then
    command.transferProgress=true;command.activeSamples=command.activeSamples+1
    command.progressDuration=current.maxTime
   end
   if #queue().queue==0 and not getPlayer():hasTimedActions()then
    quietAt=quietAt or now()
    phase='settling'
   else quietAt=nil end
  elseif phase=='settling'then
   if #queue().queue>0 or getPlayer():hasTimedActions()then phase='running';quietAt=nil
   elseif now()-quietAt>=3000 then phase='receipt';request('Verify')end
  elseif phase=='receipt'and receipt then finish()end
 end)
 if not ok then restoreAdd();print('[QUEUE_TEST] FAIL inventory transfer client '..tostring(problem));done=true end
end)
