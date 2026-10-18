require 'PZSurvivorToolkit/ActionQueuePanel'
require 'Entity/TimedActions/ISHandcraftAction'
require 'ISUI/ISCraftingUI'
local config=require 'QueueTestSelection'
local Fixture=require 'QueueCraftFixture'
local JSON=require 'QueueHealthEvents'
local Toolkit=PZSurvivorToolkit
local Ops,Lifecycle=Toolkit.ActionQueueOperations,Toolkit.ActionQueueLifecycle
local enabled=config.mode=='toolkit'
local started,done=false,false
local phase,since,step,failed='prepare',0,1,0
local ids,state,current,tail,receipt,blocker
local returns,returnOrder,boundaries,pickups,picked,returned={},{},{},{},{},{}
local injected,progress,tailProgress,returnsBeforeRead=false,false,false,false
local localDeferrals,idle=0,0
local interrupted,removal,missingObserved=false,nil,false
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function case()return config.cases[step]end
local function sorted(set)local result={};for id in pairs(set)do result[#result+1]=id end;table.sort(result);return result end
local function emit(value)
 value.suite='craft';value.kind=config.kind;value.mode=config.mode;value.actor='client1';JSON.emit(value)
end
local begin=Lifecycle.begin
Lifecycle.begin=function(action,nativePhase)
 local active=begin(action,nativePhase)
 if action==current and active and Lifecycle.current(action.character)==action then boundaries[nativePhase]=true end
 if nativePhase=='perform' then
  for i,expected in ipairs(returns)do if action==expected then returnOrder[#returnOrder+1]=ids.tools[i]end end
 end
 return active
end
local defer=Ops.deferCompletion
Ops.deferCompletion=function(q,action)
 local result=defer(q,action)
 if action==current and result then localDeferrals=localDeferrals+1 end
 return result
end
-- Synthetic late-callback stress case; abort cases use untouched native craft methods.
local basePerform=ISBaseTimedAction.perform
ISBaseTimedAction.perform=function(action,...)
 local result=basePerform(action,...)
 if action==current and case()=='borrowed-tools' then
  assert(not injected,'craft performed twice');injected=true
  assert((Lifecycle.current(action.character)==action)==enabled,'wrong native completion owner')
  for i=1,2 do
   local tool=assert(state.root:getItemById(ids.tools[i]),'borrowed tool missing during completion')
   assert(tool:getContainer()==state.root,'craft tool was not actually borrowed')
   ISCraftingUI.ReturnItemToContainer(action.character,tool,state.bags[i]:getItemContainer())
   for _,pending in ipairs(queue().queue)do
    if pending.Type=='ISInventoryTransferAction' and pending.item==tool and pending.allowMissingItems then returns[i]=pending end
   end
   assert(returns[i],'native return helper did not enqueue tool')
  end
  local q=queue()
  assert(q.queue[2]==returns[1] and q.queue[3]==returns[2],'late native return order differs')
  assert(q.current==(enabled and current or tail),'reading started before shared completion finished')
  if enabled then assert(q.queue[4]==tail,'late returns did not precede independent reader')end
 end
 return result
end
local function request(command)
 if config.kind=='mp' then sendClientCommand('CraftQueueTest',command,{case=case()})
 elseif command=='Prepare' then
  state=Fixture.prepare(getPlayer(),case());ids=Fixture.descriptor(state)
  print('[CRAFT_QUEUE_TEST] PREPARED '..JSON.encode(ids))
 elseif command=='RemoveInput' then
  removal=Fixture.removeInput(state);print('[CRAFT_QUEUE_TEST] REMOVED '..JSON.encode(removal))
 else
  receipt=assert(Fixture.verify(state,enabled))
  if case()=='borrowed-tools' then print('[CRAFT_QUEUE_TEST] AUTHORITY consumed=1 outputs=1 toolsReturned=2 tailRead=true')
  else print('[CRAFT_QUEUE_TEST] ABORT_AUTHORITY '..JSON.encode(receipt))end
 end
end
Events.OnServerCommand.Add(function(module,command,value)
 if module~='CraftQueueTest' then return end
 assert(value.ok~=false,value.error)
 if command=='Prepared' then ids=value elseif command=='Verified' then receipt=value elseif command=='Removed' then removal=value end
end)
Events.OnPlayerUpdate.Add(function(player)
 if started and player==getPlayer() then idle=#queue().queue==0 and not player:hasTimedActions() and idle+1 or 0 end
end)
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs();getCore():setOptionPauseOnFocusloss(false)
 if not isClient() then getPlayer():setGhostMode(true)end
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
local function nearEnd(player,book)
 book:setAlreadyReadPages(book:getNumberOfPages()-1)
 player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
end
local function enqueue(player)
 local containers=ArrayList.new();containers:add(state.root)
 for i=1,2 do containers:add(state.bags[i]:getItemContainer())end
 local recipe=assert(getScriptManager():getCraftRecipe('QueueBorrowedTools'),'fixture recipe missing')
 local logic=HandcraftLogic.new(player,nil,nil);logic:setContainers(containers);logic:setRecipe(recipe)
 if case()~='borrowed-tools' then
  logic:setManualSelectInputs(true);logic:clearManualInputs()
  local items={state.material,state.tools[1],state.tools[2]}
  assert(recipe:getInputs():size()==3,'manual recipe inputs differ')
  for i=0,2 do
   local input=recipe:getInputs():get(i);local selected=ArrayList.new();selected:add(items[i+1])
   assert(logic:setManualInputsFor(input,selected),'manual craft input rejected')
  end
 end
 -- Native start warms AppliedData before checking manual recipe availability.
 logic:canPerformCurrentRecipe()
 if not logic:canPerformCurrentRecipe() then
  if not state.readinessWaited then
   state.readinessWaited=true
   print('[CRAFT_QUEUE_TEST] PREPARE_WAIT '..JSON.encode({case=case(),tooDark=player:tooDarkToRead()}))
  end
  return false
 end
 local function craft()
  for i=1,2 do
   local source=state.bags[i]:getItemContainer()
   pickups[i]=ISInventoryTransferUtil.newInventoryTransferAction(player,state.tools[i],source,state.root)
   ISTimedActionQueue.add(pickups[i])
  end
  if state.blocker then
   nearEnd(player,state.blocker);blocker=ISReadABook:new(player,state.blocker);ISTimedActionQueue.add(blocker)
  end
  current=ISHandcraftAction.FromLogic(logic)
  assert(current:getDuration()==150 and not player:isTimedActionInstant(),'native craft duration changed')
  assert(Toolkit.ActionQueueCraft.supports(current),'fixture craft is not audited')
  ISTimedActionQueue.add(current)
  if case()~='borrowed-tools' then
   for i=1,2 do ISCraftingUI.ReturnItemToContainer(player,state.tools[i],state.bags[i]:getItemContainer())end
  end
 end
 if enabled then Ops.run(craft)else craft()end
 nearEnd(player,state.book);tail=ISReadABook:new(player,state.book)
 assert(tail.minutesPerPage==2.0 and tail.maxTime>1,'native reading duration changed')
 ISTimedActionQueue.add(tail)
 if enabled then assert(tail.toolkitQueueOperation~=current.toolkitQueueOperation,'reader is not independent')end
 return true
end
local function transfers(action)
 if not action or action.Type~='ISInventoryTransferAction' or not action:isStarted() or action:getJobDelta()<=0 then return end
 local items=action.queueList and action.queueList[1] and action.queueList[1].items or {action.item}
 for _,item in ipairs(items)do for i,id in ipairs(ids.tools)do
  if item:getID()==id then
   local source=state.bags[i]:getItemContainer()
   if action.srcContainer==source and action.destContainer==state.root then picked[id]=true end
   if action.srcContainer==state.root and action.destContainer==source then returned[id]=true end
  end
 end end
end
local function finishCase()
 if case()=='borrowed-tools' then
  assert(receipt.consumed==1 and receipt.outputs==1 and receipt.toolsReturned==2 and receipt.tailRead,'wrong authority receipt')
  emit({event='case',id=case(),status='passed',consumed=1,outputs=1,toolsReturned=2,
   toolIds=ids.tools,returnOrder=returnOrder,tailRead=true,returnsBeforeRead=enabled,sharedPerform=enabled,
   sharedComplete=enabled and config.kind=='sp',localDeferrals=localDeferrals,nativeDuration=150,authorityVerified=true})
 else
  local reason=not receipt.tailRead and 'native-independent-tail-not-preserved'
   or not returnsBeforeRead and 'native-returns-not-before-tail' or nil
  local value={event='case',id=case(),status=reason and 'failed' or 'passed',reason=reason,
   toolIds=ids.tools,pickupIds=sorted(picked),returnIds=sorted(returned),pickupProgress=true,craftProgress=progress,
   tailProgress=tailProgress,returnsBeforeRead=returnsBeforeRead,interrupted=interrupted,
   missingObserved=missingObserved,tokenCancelled=current.toolkitQueueOperation and current.toolkitQueueOperation.toolkitCancelled==true or false,
   nativeDuration=150,authorityVerified=true,manualInputs=true,localDeferrals=localDeferrals}
  for key,result in pairs(receipt)do if key~='case' then value[key]=result end end
  if reason then failed=failed+1 end;emit(value)
 end
 if step==#config.cases then
  emit({event='complete',cases=config.cases,expected=#config.cases,performed=#config.cases,failed=failed,skipped=0})
  done=true;print('[CRAFT_QUEUE_TEST] COMPLETE');return
 end
 step=step+1;phase='prepare';since=getTimestampMs()
 ids,state,current,tail,receipt,blocker=nil,nil,nil,nil,nil,nil
 returns,returnOrder,boundaries,pickups,picked,returned={},{},{},{},{},{}
 injected,progress,tailProgress,returnsBeforeRead,interrupted,removal,missingObserved=false,false,false,false,false,nil,false
 localDeferrals,idle=0,0
end
Events.OnTick.Add(function()
 if not started or done or not isIngameState() then return end
 local ok,problem=pcall(function()
  assert(getTimestampMs()-since<180000,'craft stage deadline '..phase)
  local player=getPlayer()
  if not player or player:isDead() or not player:getSquare()then return end
  if config.kind=='mp' and (not isClient()or player:getOnlineID()<0)then return end
  if phase=='prepare' then
   assert(Toolkit.Settings.actionQueue()==enabled,'wrong queue option')
   if step==1 then emit({event='setup',cases=config.cases,expected=#config.cases,queueEnabled=enabled,nativeDurations=true})end
   request('Prepare');phase='ready';return
  end
  if phase=='ready' then
   if not ids then return end
   assert(ids.case==case(),'prepared craft case differs')
   state=state or Fixture.resolve(player,ids);if not state then return end
   if not enqueue(player)then return end
   phase='running';since=getTimestampMs();return
  end
  if phase=='running' then
   local q=queue();transfers(q.current)
   if q.current==current and current:isStarted()and current:getJobDelta()>0 then progress=true end
   if case()=='cancel-pickup' and not interrupted and q.current==pickups[2] and picked[ids.tools[2]] then
    local first=state.root:getItemById(ids.tools[1])
    assert(first and first:getContainer()==state.root and not current:isStarted(),'cancel stage differs')
    if enabled then local allowed,reason=Toolkit.ActionQueue.cancelOperation(q,current);assert(allowed,reason)
    else q.current:forceStop()end
    interrupted=true;print('[CRAFT_QUEUE_TEST] INTERRUPTED '..JSON.encode({case=case(),duringPickup=true,craftStarted=false}))
   elseif case()=='missing-input' and q.current==blocker and blocker:isStarted()and blocker:getJobDelta()>0 then
    if not interrupted then interrupted=true;request('RemoveInput')end
    if removal and not state.root:getItemById(ids.material)then
     assert(not current:isStarted(),'input removal arrived after craft start')
     missingObserved=true
    end
   end
   if q.current==tail and tail:isStarted()and tail:getJobDelta()>0 then
    tailProgress=true
    if case()=='borrowed-tools' then assert((#returnOrder==2)==enabled,'reading has wrong position relative to tool returns')
    else
     returnsBeforeRead=true
     for i,id in ipairs(ids.tools)do
      if not state.bags[i]:getItemContainer():getItemById(id)or not returned[id]then returnsBeforeRead=false end
     end
     if enabled then assert(returnsBeforeRead,'aborted craft returned tools after reader')end
    end
   end
   if #q.queue>0 or player:hasTimedActions()then return end
   phase='settling'
  end
  if phase=='settling' then
   local q=queue();transfers(q.current)
   if #q.queue>0 or player:hasTimedActions()or idle<3 then return end
   if case()=='borrowed-tools' then
    assert(injected and progress and tailProgress,'real craft/reader did not progress')
    assert(#returnOrder==2 and returnOrder[1]==ids.tools[1]and returnOrder[2]==ids.tools[2],'native tool returns lost or reordered')
    assert((boundaries.perform==true)==enabled and(boundaries.complete==true)==(enabled and config.kind=='sp'),'native craft phases differ')
   else
    assert(interrupted and not progress and picked[ids.tools[1]]and picked[ids.tools[2]],'abort pickup/progress evidence differs')
    if case()=='missing-input'then assert(missingObserved and removal.materialId==ids.material,'missing exact input was not observed')end
    if enabled then assert(tailProgress and returnsBeforeRead,'abort lost independent reader')end
   end
   assert(localDeferrals==0,'shared craft still used local completion deferral')
   request('Verify');phase='receipt';return
  end
  if phase=='receipt' and receipt then finishCase()end
 end)
 if not ok then done=true;emit({event='error',message=tostring(problem)});print('[QUEUE_TEST] FAIL craft '..tostring(problem))end
end)
