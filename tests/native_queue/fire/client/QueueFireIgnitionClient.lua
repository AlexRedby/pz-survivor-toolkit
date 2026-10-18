local Test=require 'QueueFireIgnition'
local selection=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local Tidy=require 'QueueFireTidy'
require 'Camping/ISCampingMenu'
for _,name in ipairs({'ISLightFromLiterature','ISLightFromPetrol','ISLightFromKindle'}) do require('Camping/TimedActions/'..name) end
for _,name in ipairs({'ISBBQAddFuel','ISBBQLightFromLiterature','ISBBQLightFromPetrol','ISBBQLightFromKindle'}) do require('TimedActions/'..name) end
local Client,state={},nil
local priorTailFailure=false
local enabled=selection.mode=='toolkit'
local hasP4=false
for _,mod in ipairs(selection.mods) do if mod=='P4TidyUpMeister' then hasP4=true end end
function Client.response(command,value)
 if not state then return end
 assert(value.ok~=false,value.error)
 if command=='Prepared' then state.ids=value elseif command=='Verified' then state.receipt=value end
end
local function sorted(set)local result={};for id in pairs(set) do result[#result+1]=id end;table.sort(result);return result end
local function send(command)
 if selection.kind=='mp' then sendClientCommand('FireQueueTest',command,{case=state.case,tidyReturnIds=sorted(state.tidyReturns)})
 elseif command=='Prepare' then state.ids=Test.prepare(getPlayer(),state.case)
 else state.receipt=Test.verify(getPlayer(),state.case,sorted(state.tidyReturns)) end
end
local function change(phase)state.phase=phase;state.since=getTimestampMs()end
local function reset(case)
 state={case=case,since=getTimestampMs(),phase='prepare',pickup={},returns={},actions={},attempts=0,
  expanded=false,actionProgress=false,tailProgress=false,returnedBeforeTail=false,retryBeforeReturns=true,tidyReturns={},petrolBeforeTail=false}
end
local function locate(player)
 local ids=state.ids;local square=getCell():getGridSquare(ids.x,ids.y,ids.z)
 if not square then return end
 local source,target
 for i=0,square:getObjects():size()-1 do
  local object=square:getObjects():get(i)
  if object:getObjectIndex()==ids.crateIndex and object:getSprite():getName()=='carpentry_01_16' then source=object:getContainer() end
  if Test.cases[state.case].bbq and object:getObjectIndex()==ids.objectIndex and instanceof(object,Test.cases[state.case].fireplace and 'IsoFireplace' or 'IsoBarbecue') then target=object end
 end
 if not Test.cases[state.case].bbq then target=CCampfireSystem.instance:getLuaObjectAt(ids.x,ids.y,ids.z) end
 if not source or not target then return end
 local items={}
 for _,entry in ipairs(ids.resources) do
  local item=(entry.source=='crate' and source or player:getInventory()):getItemById(entry.id)
  if not item or item:getFullType()~=entry.kind then return end
  items[entry.role]=item
 end
 state.source,state.target,state.items=source,target,items
 return true
end
local function enqueue(player)
 local spec=Test.cases[state.case];local items=state.items
 local class=_G[spec.class];assert(class,'native ignition class missing')
 if spec.mode=='fuel' then ISTimedActionQueue.queueActions(player,ISCampingMenu.onAddFuel,state.target,'Base.Log',class,0)
 elseif spec.mode=='literature' then ISTimedActionQueue.queueActions(player,ISCampingMenu.onLightFromLiterature,'Base.SheetPaper2',items.starter,state.target,class)
 elseif spec.mode=='petrol' then ISTimedActionQueue.queueActions(player,ISCampingMenu.onLightFromPetrol,items.starter,items.petrol,state.target,class)
 else ISTimedActionQueue.queueActions(player,ISCampingMenu.onLightFromKindle,items.plank,items.stick,state.target,class) end
 local book=assert(player:getInventory():getItemById(state.ids.book))
 book:setAlreadyReadPages(book:getNumberOfPages()-1);player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
 state.tail=ISReadABook:new(player,book)
 assert(state.tail.minutesPerPage==2.0 and state.tail.maxTime>1,'native ignition reader duration changed')
 ISTimedActionQueue.add(state.tail)
 change('running')
end
local function recordTransfer(action,player)
 if action.Type~='ISInventoryTransferAction' or not action:isStarted() or action:getJobDelta()<=0 then return end
 local dest=action.srcContainer==state.source and action.destContainer==player:getInventory() and state.pickup
  or action.srcContainer==player:getInventory() and action.destContainer==state.source and state.returns
 if not dest then return end
 local items=action.queueList and action.queueList[1] and action.queueList[1].items or {action.item}
 for _,item in ipairs(items) do
  for _,entry in ipairs(state.ids.resources) do
   if item:getID()==entry.id then
    local restore=Tidy.restore(player,entry.id)
    if not (entry.role=='petrol' and dest==state.returns and restore) then dest[entry.id]=true end
    if entry.role=='petrol' and dest==state.returns and not state.petrolReturnDiagnosed then
     state.petrolReturnDiagnosed=true
     local book=player:getInventory():getItemById(state.ids.book)
     print('[FIRE_TEST] PETROL_RETURN '..JSON.encode({case=state.case,trial=state.ids.trial,id=entry.id,
      groupCleanup=action.toolkitQueueReturn~=nil,p4Planned=restore~=nil,p4Session=restore and tostring(restore.sessionId) or '',
      tokenCancelled=state.first and state.first.toolkitQueueOperation and state.first.toolkitQueueOperation.toolkitCancelled==true or false,
      tailProgress=state.tailProgress,readerFinished=book and book:getAlreadyReadPages()==book:getNumberOfPages() or false}))
    end
   end
  end
 end
end
local function observeTidy(player,q)
 local action=q.current
 if not action or getmetatable(action)~=ISInventoryTransferAction or not action:isStarted()
  or action:getJobDelta()<=0 or action.srcContainer~=player:getInventory() or action.destContainer~=state.source then return end
 local items=action.queueList and action.queueList[1] and action.queueList[1].items or {action.item}
 for _,item in ipairs(items) do for _,entry in ipairs(state.ids.resources) do
  if entry.role=='petrol' and item:getID()==entry.id then
   local restore=Tidy.restore(player,entry.id)
   assert(restore and not action.toolkitQueueReturn,'unproven petrol restore')
   local book=assert(player:getInventory():getItemById(state.ids.book))
   local read=book:getAlreadyReadPages()==book:getNumberOfPages()
   local cancelled=state.first.toolkitQueueOperation and state.first.toolkitQueueOperation.toolkitCancelled==true or false
   if enabled then assert(read and not cancelled and state.petrolBeforeTail,'petrol restored before completed reading') end
   local first=not state.tidyReturns[entry.id]
   state.tidyReturns[entry.id]={id=entry.id,sessionId=restore.sessionId,nativeTransfer=true,
    fromRoot=true,toSource=true,groupCleanup=false,progress=true,tailRead=read,tokenCancelled=cancelled}
   if first then print('[FIRE_TEST] TIDY_RETURN '..JSON.encode(state.tidyReturns[entry.id])) end
  end
 end end
end
function Client.tick(player,case)
 if not state then reset(case) end
 assert(state.case==case,'ignition client case changed')
 assert(getTimestampMs()-state.since<300000,'ignition deadline '..state.phase)
 local spec=Test.cases[case]
 local nativeSPKindle=spec.bbq and spec.mode=='kindle' and not isClient()
 if state.phase=='prepare' then Tidy.install(hasP4);Tidy.reset(player);send('Prepare');change('ready');return end
 if state.phase=='ready' then
  if not state.ids or not locate(player) then return end
  assert(state.ids.case==case and state.ids.actionType==spec.class and state.ids.nativeDuration==spec.duration
   and state.ids.targetKind==(spec.fireplace and 'fireplace' or spec.bbq and 'bbq' or 'campfire'),'ignition preparation differs')
  player:teleportTo(state.ids.spawn.x,state.ids.spawn.y,state.ids.spawn.z);change('positioned');return
 end
 if state.phase=='positioned' then
  local ids=state.ids;local square=player:getCurrentSquare()
  if not square or square:getX()~=math.floor(ids.spawn.x) or square:getY()~=math.floor(ids.spawn.y) or square:getZ()~=ids.spawn.z then return end
  getPlayerInventory(player:getPlayerNum()):refreshBackpacks();getPlayerLoot(player:getPlayerNum()):refreshBackpacks()
  if not ISInventoryPaneContextMenu.getContainers(player):contains(state.source) then return end
  assert(not player:isTimedActionInstant(),'native ignition durations required');enqueue(player);return
 end
 if state.phase=='running' then
  local q=ISTimedActionQueue.getTimedActionQueue(player)
  local tailIndex
  for i,action in ipairs(q.queue) do if action==state.tail then tailIndex=i end end
  for i,action in ipairs(q.queue) do
   if action.Type==spec.class then
    -- Campfire petrol getDuration reads maxTime, which native create adjusts for moodles.
    local duration=spec.class=='ISLightFromPetrol' and action.maxTimeInit or action:getDuration()
    assert(duration==spec.duration,'native ignition action duration changed')
    state.expanded=true
    if enabled then assert(PZSurvivorToolkit.ActionQueueFire.supports(action),'ignition action not audited') end
    if not state.first then state.first=action end
    if action~=state.first then
     local before=tailIndex and i<tailIndex
     for n,member in ipairs(q.queue) do
      if member.Type=='ISInventoryTransferAction' and member.destContainer==state.source and n<i then before=false end
     end
     for _ in pairs(state.returns) do before=false end
     state.retryBeforeReturns=state.retryBeforeReturns and before==true
     if enabled then
      assert(before and action.toolkitQueueOperation==state.first.toolkitQueueOperation and action.plank:getID()==state.ids.resources[1].id
       and action.campfire==state.target,'native Kindle retry escaped its operation/returns')
     end
    end
    if q.current==action and action:isStarted() and action:getJobDelta()>0 then
     state.actionProgress=true
     if not state.actions[action] then state.actions[action]=true;state.attempts=state.attempts+1 end
    end
   end
  end
  local current=q.current
  if current then recordTransfer(current,player) end
  observeTidy(player,q)
  if current==state.tail and state.tail:isStarted() and state.tail:getJobDelta()>0 then
   if not state.tailProgress then
    for _,entry in ipairs(state.ids.resources) do if entry.role=='petrol' then
     state.petrolBeforeTail=player:getInventory():getItemById(entry.id)~=nil
     print('[FIRE_TEST] TAIL_BOUNDARY '..JSON.encode({case=case,trial=state.ids.trial,id=entry.id,
      root=player:getInventory():getItemById(entry.id)~=nil,source=state.source:getItemById(entry.id)~=nil,
      tokenCancelled=state.first.toolkitQueueOperation and state.first.toolkitQueueOperation.toolkitCancelled==true or false}))
    end end
   end
   if enabled then
    if not nativeSPKindle then assert(not (state.first.toolkitQueueOperation and state.first.toolkitQueueOperation.toolkitCancelled),'completed ignition was cancelled before reader') end
    for _,entry in ipairs(state.ids.resources) do
     if entry.role=='petrol' then assert(player:getInventory():getItemById(entry.id),'completed ignition returned retained petrol before reader') end
    end
   end
   state.tailProgress=true;local returned=true
   for _,entry in ipairs(state.ids.resources) do
    if entry.returnToSource then
     local exists=player:getInventory():getItemById(entry.id) or state.source:getItemById(entry.id)
     if exists and (not state.source:getItemById(entry.id) or not state.returns[entry.id]) then returned=false end
    end
   end
   state.returnedBeforeTail=returned
   if enabled then assert(returned,'ignition reader preceded exact borrowed returns') end
  end
  if #q.queue>0 or player:hasTimedActions() then return end
  assert(state.expanded and state.actionProgress,'native ignition action progress absent')
  for _,entry in ipairs(state.ids.resources) do
   if entry.source=='crate' then assert(state.pickup[entry.id],'native ignition pickup evidence absent '..entry.role) end
  end
  if enabled and not nativeSPKindle then assert(not (state.first.toolkitQueueOperation and state.first.toolkitQueueOperation.toolkitCancelled),'completed ignition operation was cancelled') end
  local locations={}
  for _,entry in ipairs(state.ids.resources) do
   locations[#locations+1]={id=entry.id,role=entry.role,source=state.source:getItemById(entry.id)~=nil,
    root=player:getInventory():getItemById(entry.id)~=nil}
  end
  print('[FIRE_TEST] BEFORE_DRAIN '..JSON.encode({case=case,trial=state.ids.trial,locations=locations,
   tokenCancelled=state.first.toolkitQueueOperation and state.first.toolkitQueueOperation.toolkitCancelled==true or false,
   returnIds=sorted(state.returns),tailProgress=state.tailProgress,returnedBeforeTail=state.returnedBeforeTail}))
  change('settling');return
 end
 if state.phase=='settling' then
  local q=ISTimedActionQueue.getTimedActionQueue(player)
  observeTidy(player,q)
  if #q.queue>0 or player:hasTimedActions() or Tidy.idleUpdates(player)<3 then return end
  for id in pairs(state.tidyReturns) do
   if not Tidy.restore(player,id).completed then return end
   assert(state.source:getItemById(id) and not player:getInventory():getItemById(id),'P4 transfer did not commit')
  end
  print('[FIRE_TEST] TIDY_SETTLED '..JSON.encode({case=case,trial=state.ids.trial,tidyReturnIds=sorted(state.tidyReturns)}))
  send('Verify');change('receipt');return
 end
 if state.phase=='receipt' then
  if not state.receipt then
   if selection.kind=='sp' then state.receipt=Test.verify(player,case,sorted(state.tidyReturns)) end
   return
  end
  local receipt=state.receipt
  assert(receipt.case==case and receipt.trial==state.ids.trial and receipt.bookId==state.ids.book and receipt.targetKind==state.ids.targetKind,'ignition authority identity differs')
  print('[FIRE_TEST] IGNITION_DIAG '..JSON.encode({case=case,trial=receipt.trial,attempts=state.attempts,retryBeforeReturns=state.retryBeforeReturns,
   pickupIds=sorted(state.pickup),returnIds=sorted(state.returns),tailProgress=state.tailProgress,returnedBeforeTail=state.returnedBeforeTail}))
  priorTailFailure=priorTailFailure or not receipt.tailRead
  if spec.retry and state.attempts<2 then
   assert(receipt.trial<8,'natural Kindle retry evidence absent after eight valid trials')
   reset(case);return
  end
  local reason
  if not enabled then
   if priorTailFailure then reason='native-independent-tail-not-preserved'
   elseif not state.returnedBeforeTail then reason='native-returns-not-before-tail'
   elseif spec.retry and not state.retryBeforeReturns then reason='native-retry-not-before-returns' end
  end
  local result={event='case',id=case,status=reason and 'failed' or 'passed',reason=reason,trial=receipt.trial,
   actionType=spec.class,nativeDuration=spec.duration,attempts=state.attempts,expanded=state.expanded,actionProgress=state.actionProgress,
   pickupProgress=true,pickupIds=sorted(state.pickup),returnIds=sorted(state.returns),tailProgress=state.tailProgress,
   returnedBeforeTail=state.returnedBeforeTail,retryBeforeReturns=state.retryBeforeReturns,
   tokenCancelled=state.first.toolkitQueueOperation and state.first.toolkitQueueOperation.toolkitCancelled==true or false,
   tidyReturns={},petrolBeforeTail=state.petrolBeforeTail}
  for _,id in ipairs(sorted(state.tidyReturns)) do result.tidyReturns[#result.tidyReturns+1]=state.tidyReturns[id] end
  for key,value in pairs(receipt) do if key~='case' then result[key]=value end end
  state=nil;priorTailFailure=false;return result
 end
end
return Client
