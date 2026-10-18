require 'PZSurvivorToolkit/ActionQueuePanel'
require 'Camping/ISCampingMenu'
require 'Camping/TimedActions/ISAddFuelAction'
require 'TimedActions/ISReadABook'
local config=require 'QueueTestSelection'
local Authority=require 'QueueFireAuthority'
local Ignition=require 'QueueFireIgnition'
local IgnitionClient=require 'QueueFireIgnitionClient'
local JSON=require 'QueueHealthEvents'
local enabled=config.mode=='toolkit'
local nativeMP=config.kind=='mp' and not enabled
local failedCases=0
local started,done,step,phase,since=false,false,1,'prepare',0
local setupSent=false
local ids,source,log,book,target,fuel,pickup,tail,receipt,invalidated
local pickupProgress,fuelProgress,tailProgress,returnProgress,expanded,removalRequested,removedBeforeFuel
local removalTime,pickupDuration
local progressDiagnosed,pickupRootObserved=false,false
local returnDiagnosed=false
local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()) end
local function emit(value)
 value.suite='fire';value.kind=config.kind;value.mode=config.mode;value.actor='client1';JSON.emit(value)
end
local function finish(result)
 emit(result)
 if result.status=='failed' then failedCases=failedCases+1 end
 if step==#config.cases then
  emit({event='complete',cases=config.cases,expected=#config.cases,performed=#config.cases,failed=failedCases,skipped=0})
  done=true;print('[FIRE_TEST] COMPLETE');return
 end
 step=step+1;phase='prepare';since=getTimestampMs()
 ids,source,log,book,target,fuel,pickup,tail,receipt,invalidated=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
 pickupProgress,fuelProgress,tailProgress,returnProgress,expanded,removalRequested,removedBeforeFuel=false,false,false,false,false,false,false
 progressDiagnosed,pickupRootObserved=false,false
 returnDiagnosed=false
end
local function send(command)
 local case=config.cases[step]
 if config.kind=='mp' then sendClientCommand('FireQueueTest',command,{case=case})
 elseif command=='Prepare' then ids=Authority.prepare(getPlayer(),case)
 elseif command=='Invalidate' then invalidated=Authority.invalidate(getPlayer(),case)
 else receipt=Authority.verify(getPlayer(),case) end
end
local function crate()
 local square=getCell():getGridSquare(ids.crateX,ids.crateY,ids.crateZ)
 if not square then return end
 for i=0,square:getSpecialObjects():size()-1 do
  local object=square:getSpecialObjects():get(i)
  if object:getObjectIndex()==ids.crateIndex and object:getSprite():getName()=='carpentry_01_16' then return object:getContainer() end
 end
end
Events.OnServerCommand.Add(function(module,command,value)
 if module~='FireQueueTest' then return end
 IgnitionClient.response(command,value)
 assert(value.ok~=false,value.error)
 if command=='Prepared' then ids=value elseif command=='Invalidated' then invalidated=value elseif command=='Verified' then receipt=value end
end)
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs();getCore():setOptionPauseOnFocusloss(false)
 if not isClient() then getPlayer():setGhostMode(true) end
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
end)
Events.OnTick.Add(function()
 if not started or done or not isIngameState() then return end
 local ok,problem=pcall(function()
  local player=getPlayer()
  if not player or player:isDead() or not player:getSquare() then return end
  if config.kind=='mp' and (not isClient() or player:getOnlineID()<0) then return end
  local case=config.cases[step]
  if not setupSent then
   setupSent=true;emit({event='setup',cases=config.cases,expected=#config.cases,queueEnabled=enabled,nativeDurations=true})
  end
  if Ignition.cases[case] then
   assert(PZSurvivorToolkit.Settings.actionQueue()==enabled,'wrong ignition queue option')
   local result=IgnitionClient.tick(player,case)
   if result then finish(result) end
   return
  end
  assert(getTimestampMs()-since<180000,'fire stage deadline '..phase)
  local missing=case=='missing-target-after-expansion'
  if phase=='prepare' then
   assert(PZSurvivorToolkit.Settings.actionQueue()==enabled,'wrong fire queue option')
   send('Prepare');phase='ready';return
  end
  if phase=='ready' then
   if not ids then return end
   assert(ids.case==case,'wrong prepared fire case')
   source=crate();if not source then return end
   log=source:getItemById(ids.log);book=player:getInventory():getItemById(ids.book)
   target=CCampfireSystem.instance:getLuaObjectAt(ids.x,ids.y,ids.z)
   if not log or not book or not target or not target:getIsoObject() then return end
   target:updateFromIsoObject()
   assert(target:getIsoObject():getObjectIndex()==ids.objectIndex,'replicated campfire index differs')
   assert(log:getContainer()==source and target.fuelAmt==0 and not target.isLit,'wrong client fire fixture')
   assert(ISCampingMenu.getFuelDurationForItem(log)==ids.fuelAmount and log:getCondition()==ids.condition,'replicated Log differs')
   player:teleportTo(ids.spawn.x,ids.spawn.y,ids.spawn.z)
   phase='positioned';return
  end
  if phase=='positioned' then
   local square=player:getCurrentSquare()
   if not square or square:getX()~=math.floor(ids.spawn.x) or square:getY()~=math.floor(ids.spawn.y)
     or square:getZ()~=ids.spawn.z then return end
   getPlayerInventory(player:getPlayerNum()):refreshBackpacks();getPlayerLoot(player:getPlayerNum()):refreshBackpacks()
   local found=false;local containers=ISInventoryPaneContextMenu.getContainers(player)
   for i=0,containers:size()-1 do if containers:get(i)==source then found=true end end
   if not found then return end
   book:setAlreadyReadPages(book:getNumberOfPages()-1);player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
   assert(not player:isTimedActionInstant(),'native durations required')
   ISTimedActionQueue.queueActions(player,ISCampingMenu.onAddFuel,target,'Base.Log',ISAddFuelAction,0)
   tail=ISReadABook:new(player,book)
   assert(tail.minutesPerPage==2.0 and tail.maxTime>1,'native reading duration changed')
   ISTimedActionQueue.add(tail)
   phase='running';since=getTimestampMs();return
  end
  if phase=='running' then
   local q=queue()
   if player:getInventory():getItemById(ids.log) then pickupRootObserved=true end
   for index,action in ipairs(q.queue) do
    if action.Type=='ISAddFuelAction' and action.item and action.item:getID()==ids.log then
     assert(not fuel or fuel==action,'duplicate expanded native fuel action');fuel=action
     assert(fuel:getDuration()==100 and fuel.fuelAmt==ids.fuelAmount,'native fuel duration/amount changed')
     local tailIndex
     for n,pending in ipairs(q.queue) do if pending==tail then tailIndex=n end end
     assert(tailIndex and index<tailIndex,'expanded fuel must precede independent reader')
     if enabled then assert(PZSurvivorToolkit.ActionQueueFire.supports(fuel) and fuel.toolkitQueueOperation~=tail.toolkitQueueOperation,'fuel not audited or reader linked') end
     expanded=true
    elseif action.Type=='ISInventoryTransferAction' and action.item and action.item:getID()==ids.log then
     if action.srcContainer==source and action.destContainer==player:getInventory() then
      assert(not pickup or pickup==action,'duplicate borrowed pickup');pickup=action;pickupDuration=action.maxTime
     end
    end
   end
   if pickup and q.current==pickup and pickup:isStarted() and pickup:getJobDelta()>0 then
    pickupProgress=true;assert(pickupDuration>1,'native pickup duration missing')
    if missing and expanded and not removalRequested then
     assert(not fuel.action,'fuel allocated before missing-target request')
     removalRequested=true;removalTime=getTimestampMs();send('Invalidate')
    end
   end
   if removalRequested and invalidated and not removedBeforeFuel then
    local vanished=not CCampfireSystem.instance:getLuaObjectAt(ids.x,ids.y,ids.z) and not target:getIsoObject()
    if vanished then
     assert(q.current==pickup and pickup:isStarted() and not fuel.action,'campfire removal missed native pickup window')
     removedBeforeFuel=true
    end
   end
   if fuel and q.current==fuel and fuel:isStarted() and fuel:getJobDelta()>0 then fuelProgress=true end
   local current=q.current
   if current and current.Type=='ISInventoryTransferAction' and current.item and current.item:getID()==ids.log
     and current.srcContainer==player:getInventory() and current.destContainer==source and current:isStarted() and current:getJobDelta()>0 then returnProgress=true end
   if q.current==tail and tail:isStarted() and tail:getJobDelta()>0 then
    tailProgress=true
    if missing then
     if not returnDiagnosed then
      returnDiagnosed=true
      local sourceItem,rootItem=source:getItemById(ids.log),player:getInventory():getItemById(ids.log)
      local token=fuel and fuel.toolkitQueueOperation
      local pickupIds,pickupSource,types={},false,{}
      for item,borrowedSource in pairs(type(token)=='table' and token.toolkitPickups or {}) do
       pickupIds[#pickupIds+1]=item:getID()
       if item:getID()==ids.log and borrowedSource==source then pickupSource=true end
      end
      for _,action in ipairs(q.queue) do types[#types+1]=action.Type or 'unknown' end
      local containers=ISInventoryPaneContextMenu.getContainers(player)
      print('[FIRE_TEST] RETURN_DIAG '..JSON.encode({logId=ids.log,sourceHasId=sourceItem~=nil,rootHasId=rootItem~=nil,
       sourceExact=sourceItem~=nil and sourceItem:getContainer()==source,rootExact=rootItem~=nil and rootItem:getContainer()==player:getInventory(),
       returnProgress=returnProgress,tokenPresent=type(token)=='table',tokenPickupIds=pickupIds,tokenPickupSource=pickupSource,
       currentType=q.current and q.current.Type or 'none',queueTypes=types,sourceExists=source:isExistYet(),sourceVisible=containers:contains(source)}))
     end
     assert(enabled and source:getItemById(ids.log) and returnProgress,'reading preceded exact borrowed return')
    end
   end
   -- A native missing-target control deliberately leaves the stock exception/queue observable.
   local baseline=missing and not enabled
   if baseline then
    if not removedBeforeFuel or getTimestampMs()-removalTime<3000 then return end
    assert(not tailProgress and not fuelProgress,'native missing-target baseline unexpectedly advanced')
    local item=player:getInventory():getItemById(ids.log)
    if not item or item:getContainer()~=player:getInventory() then return end
   elseif #q.queue>0 or player:hasTimedActions() then return end
   if not progressDiagnosed then
    progressDiagnosed=true
    local liveTarget=CCampfireSystem.instance:getLuaObjectAt(ids.x,ids.y,ids.z)
    print('[FIRE_TEST] PROGRESS_DIAG '..JSON.encode({case=case,fuelProgress=fuelProgress,tailProgress=tailProgress,
     returnProgress=returnProgress,pickupRootObserved=pickupRootObserved,sourceHasId=source:getItemById(ids.log)~=nil,
     rootHasId=player:getInventory():getItemById(ids.log)~=nil,fuel=liveTarget and liveTarget.fuelAmt or 0,
     tailRead=book:getAlreadyReadPages()==book:getNumberOfPages()}))
   end
   assert(expanded and pickupProgress and (not missing or removedBeforeFuel),'native expansion/pickup/removal evidence absent')
   if not nativeMP then assert(fuelProgress==not missing and tailProgress==not baseline,'native action progress differs') end
   assert(returnProgress==(missing and enabled),'native return progress differs')
   send('Verify');phase='receipt';return
  end
  if phase=='receipt' then
   if not receipt then
    if config.kind=='sp' then send('Verify') end
    return
   end
   assert(receipt.case==case and receipt.logId==ids.log and receipt.bookId==ids.book,'authority identity differs')
   local failed=not enabled and (missing or not receipt.tailRead)
   finish({event='case',id=case,status=failed and 'failed' or 'passed',
    reason=failed and (missing and 'native-missing-target' or 'native-independent-tail-not-preserved') or nil,
    logId=ids.log,bookId=ids.book,condition=receipt.condition,fuelAmount=ids.fuelAmount,
    consumed=receipt.consumed,sourceCount=receipt.sourceCount,rootCount=receipt.rootCount,fuel=receipt.fuel,
    removed=receipt.removed,unspent=receipt.unspent,tailRead=receipt.tailRead,expanded=true,pickupProgress=true,
    fuelProgress=fuelProgress,tailProgress=tailProgress,returnProgress=returnProgress,
    removedDuringPickup=missing and removedBeforeFuel or false,pickupDuration=pickupDuration,nativeDuration=100,authorityVerified=true})
  end
 end)
 if not ok then done=true;emit({event='error',message=tostring(problem)});print('[QUEUE_TEST] FAIL fire '..tostring(problem)) end
end)
pickupProgress,fuelProgress,tailProgress,returnProgress,expanded,removalRequested,removedBeforeFuel=false,false,false,false,false,false,false
