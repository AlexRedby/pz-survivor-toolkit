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
local phase,since='prepare',0
local ids,state,current,tail,receipt
local returns,returnOrder,boundaries={},{},{}
local injected,progress,tailProgress=false,false,false
local localDeferrals=0
local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()) end
local function emit(value)
 value.suite='craft';value.kind=config.kind;value.mode=config.mode;value.actor='client1';JSON.emit(value)
end
local begin=Lifecycle.begin
Lifecycle.begin=function(action,nativePhase)
 local active=begin(action,nativePhase)
 if action==current and active and Lifecycle.current(action.character)==action then boundaries[nativePhase]=true end
 if nativePhase=='perform' then
  for i,expected in ipairs(returns) do if action==expected then returnOrder[#returnOrder+1]=ids.tools[i] end end
 end
 return active
end
local defer=Ops.deferCompletion
Ops.deferCompletion=function(q,action)
 local result=defer(q,action)
 if action==current and result then localDeferrals=localDeferrals+1 end
 return result
end
-- Emulate a late client craft callback with real native returns; leave action methods untouched.
local basePerform=ISBaseTimedAction.perform
ISBaseTimedAction.perform=function(action,...)
 local result=basePerform(action,...)
 if action==current then
  assert(not injected,'craft performed twice');injected=true
  assert((Lifecycle.current(action.character)==action)==enabled,'wrong native completion owner')
  for i=1,2 do
   local tool=assert(state.root:getItemById(ids.tools[i]),'borrowed tool missing during completion')
   assert(tool:getContainer()==state.root,'craft tool was not actually borrowed')
   ISCraftingUI.ReturnItemToContainer(action.character,tool,state.bags[i]:getItemContainer())
   for _,pending in ipairs(queue().queue) do
    if pending.Type=='ISInventoryTransferAction' and pending.item==tool and pending.allowMissingItems then returns[i]=pending end
   end
   assert(returns[i],'native return helper did not enqueue tool')
  end
  local q=queue()
  assert(q.queue[2]==returns[1] and q.queue[3]==returns[2],'late native return order differs')
  assert(q.current==(enabled and current or tail),'reading started before shared completion finished')
  if enabled then assert(q.queue[4]==tail,'late returns did not precede independent reader') end
 end
 return result
end
local function request(command)
 if config.kind=='mp' then sendClientCommand('CraftQueueTest',command,{})
 elseif command=='Prepare' then state=Fixture.prepare(getPlayer());ids=Fixture.descriptor(state)
 else
  receipt=assert(Fixture.verify(state))
  print('[CRAFT_QUEUE_TEST] AUTHORITY consumed=1 outputs=1 toolsReturned=2 tailRead=true')
 end
end
Events.OnServerCommand.Add(function(module,command,value)
 if module~='CraftQueueTest' then return end
 assert(value.ok~=false,value.error)
 if command=='Prepared' then ids=value elseif command=='Verified' then receipt=value end
end)
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs();getCore():setOptionPauseOnFocusloss(false)
 if not isClient() then getPlayer():setGhostMode(true) end
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
end)
Events.OnTick.Add(function()
 if not started or done or not isIngameState() then return end
 local ok,problem=pcall(function()
  assert(getTimestampMs()-since<180000,'craft stage deadline '..phase)
  local player=getPlayer()
  if not player or player:isDead() or not player:getSquare() then return end
  if config.kind=='mp' and (not isClient() or player:getOnlineID()<0) then return end
  if phase=='prepare' then
   assert(Toolkit.Settings.actionQueue()==enabled,'wrong queue option')
   emit({event='setup',cases=config.cases,expected=1,queueEnabled=enabled,nativeDurations=true})
   request('Prepare');phase='ready';return
  end
  if phase=='ready' then
   if not ids then return end
   state=state or Fixture.resolve(player,ids);if not state then return end
   state.book:setAlreadyReadPages(state.book:getNumberOfPages()-1)
   player:setAlreadyReadPages(state.book:getFullType(),state.book:getNumberOfPages()-1)
   local containers=ArrayList.new();containers:add(state.root)
   local function craft()
    for i=1,2 do
     local source=state.bags[i]:getItemContainer();containers:add(source)
     ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(player,state.tools[i],source,state.root))
    end
    local recipe=assert(getScriptManager():getCraftRecipe('QueueBorrowedTools'),'fixture recipe missing')
    local logic=HandcraftLogic.new(player,nil,nil);logic:setContainers(containers);logic:setRecipe(recipe)
    current=ISHandcraftAction.FromLogic(logic)
    assert(current:getDuration()==150 and not player:isTimedActionInstant(),'native craft duration changed')
    assert(Toolkit.ActionQueueCraft.supports(current),'fixture craft is not audited')
    ISTimedActionQueue.add(current)
   end
   if enabled then Ops.run(craft) else craft() end
   tail=ISReadABook:new(player,state.book)
   assert(tail.minutesPerPage==2.0 and tail.maxTime>1,'native reading duration changed')
   ISTimedActionQueue.add(tail)
   if enabled then assert(tail.toolkitQueueOperation~=current.toolkitQueueOperation,'reader is not independent') end
   phase='running';since=getTimestampMs();return
  end
  if phase=='running' then
   local q=queue()
   if q.current==current and current:isStarted() and current:getJobDelta()>0 then progress=true end
   if q.current==tail and tail:isStarted() and tail:getJobDelta()>0 then
    tailProgress=true
    assert((#returnOrder==2)==enabled,'reading has wrong position relative to tool returns')
   end
   if #q.queue>0 or player:hasTimedActions() then return end
   assert(injected and progress and tailProgress,'real craft/reader did not progress')
   assert(#returnOrder==2 and returnOrder[1]==ids.tools[1] and returnOrder[2]==ids.tools[2],'native tool returns lost or reordered')
   assert(localDeferrals==0,'shared craft still used local completion deferral')
   assert((boundaries.perform==true)==enabled and (boundaries.complete==true)==(enabled and config.kind=='sp'),'native craft phases differ')
   request('Verify');phase='receipt';return
  end
  if phase=='receipt' and receipt then
   assert(receipt.consumed==1 and receipt.outputs==1 and receipt.toolsReturned==2 and receipt.tailRead,'wrong authority receipt')
   emit({event='case',id='borrowed-tools',status='passed',consumed=1,outputs=1,toolsReturned=2,
    toolIds=ids.tools,returnOrder=returnOrder,tailRead=true,returnsBeforeRead=enabled,sharedPerform=enabled,
    sharedComplete=enabled and config.kind=='sp',localDeferrals=localDeferrals,nativeDuration=150,authorityVerified=true})
   emit({event='complete',cases=config.cases,expected=1,performed=1,failed=0,skipped=0})
   done=true;print('[CRAFT_QUEUE_TEST] COMPLETE')
  end
 end)
 if not ok then done=true;emit({event='error',message=tostring(problem)});print('[QUEUE_TEST] FAIL craft '..tostring(problem)) end
end)
