return function()
-- This case observes the real chain producer without replacing lifecycle,
-- native completion, transfer helpers or the source proof collaborators.
require 'PZSurvivorToolkit/CraftChainRecipes'
local config=require 'QueueTestSelection'
local Fixture=require 'QueueCraftFixture'
local JSON=require 'QueueHealthEvents'
local T=PZSurvivorToolkit
assert(#config.cases==1 and config.cases[1]=='keep-craft-tool'and config.mode=='toolkit','isolated toolkit case required')
local started,done,phase,since=false,false,'prepare',0
local state,ids,current,tail,receipt,keptRow,siblingRow,craftNative
local kept,progress,afterKeep,tailProgress,returnsBeforeRead=false,false,false,false,false
local picked,returned,outcomeTrace={},{},{}
local keepProgress,idle,readySince
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function emit(value)
 value.suite='craft';value.kind=config.kind;value.mode=config.mode;value.actor='client1';JSON.emit(value)
end
local function sorted(set)local values={};for id in pairs(set)do values[#values+1]=id end;table.sort(values);return values end
local function request(command)
 if config.kind=='mp'then sendClientCommand('CraftQueueTest',command,{case='keep-craft-tool'})
 elseif command=='Prepare'then
  state=Fixture.prepare(getPlayer(),'keep-craft-tool');ids=Fixture.descriptor(state)
  print('[CRAFT_QUEUE_TEST] PREPARED '..JSON.encode(ids))
 else
  receipt=assert(Fixture.verify(state,true))
  print('[CRAFT_QUEUE_TEST] KEEP_AUTHORITY '..JSON.encode(receipt))
 end
end
local function discover()
 for _,action in ipairs(queue().queue)do
  if action.Type=='ISHandcraftAction'and action.craftRecipe
   and action.craftRecipe==getScriptManager():getCraftRecipe('QueueKeepCraftTools')then
   assert(not current or current==action,'chain produced multiple crafts');current=action
  end
 end
end
Events.OnServerCommand.Add(function(module,command,value)
 if module=='PZSurvivorToolkitActions'and command=='State'and ids then
  if not current then discover()end
  if current and value.player==ids.playerId and value.transaction==current.toolkitNativeTransaction
   and value.kind==current.toolkitNativeKind then
   local row={protocol=value.protocol,player=value.player,transaction=value.transaction,kind=value.kind,token=value.token,state=value.state}
   outcomeTrace[#outcomeTrace+1]=row;print('[CRAFT_QUEUE_TEST] OUTCOME '..JSON.encode(row))
  end
  return
 end
 if module~='CraftQueueTest'then return end
 assert(value.ok~=false,value.error)
 if command=='Prepared'then ids=value elseif command=='Verified'then receipt=value end
end)
Events.OnPlayerUpdate.Add(function(player)
 if started and player==getPlayer()then idle=#queue().queue==0 and not player:hasTimedActions()and(idle or 0)+1 or 0 end
end)
require('QueuePreflight').onGameStart(Events,function()
 started=true;since=getTimestampMs();getCore():setOptionPauseOnFocusloss(false)
 if not isClient()then getPlayer():setGhostMode(true)end
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
local function prepareWait(player,reason,worn,held,containers,recipeReady)
 state.prepareWaitReason=reason
 local now=getTimestampMs()
 if state.prepareDiagnosticAt and now-state.prepareDiagnosticAt<5000 then return end
 state.prepareDiagnosticAt=now
 print('[CRAFT_QUEUE_TEST] PREPARE_WAIT '..JSON.encode({case='keep-craft-tool',reason=reason,
  elapsed=now-since,actorMatches=state.player==player,rootMatches=state.root==player:getInventory(),
  worn=worn,held=held,refreshed=state.menuRefreshed==true,
  firstContainer=containers and containers:contains(state.bags[1]:getItemContainer())or false,
  secondContainer=containers and containers:contains(state.bags[2]:getItemContainer())or false,
  recipeReady=recipeReady==true,recipeValue=tostring(recipeReady),recipeValueType=type(recipeReady),
  tooDark=player:tooDarkToRead(),timeOfDay=getGameTime():getTimeOfDay(),
  indoors=player:getSquare():getRoom()~=nil}))
end
local function enqueue(player)
 local worn=player:getWornItem(state.bags[1]:canBeEquipped())==state.bags[1]
 local held=player:getSecondaryHandItem()==state.bags[2]
 if worn and held and not state.menuRefreshed then
  -- Native getContainers reads the inventory pages' cached backpack buttons.
  -- Wait for exact equipment replication before refreshing that native cache.
  assert(getPlayerInventory(player:getPlayerNum()),'inventory UI missing'):refreshBackpacks()
  assert(getPlayerLoot(player:getPlayerNum()),'loot UI missing'):refreshBackpacks()
  state.menuRefreshed=true
  return false
 end
 local containers=ISInventoryPaneContextMenu.getContainers(player)
 if not worn or not held or not containers:contains(state.bags[1]:getItemContainer())
  or not containers:contains(state.bags[2]:getItemContainer())then
  prepareWait(player,'native-container-cache',worn,held,containers);return false
 end
 local recipe=assert(getScriptManager():getCraftRecipe('QueueKeepCraftTools'))
 local logic=HandcraftLogic.new(player,nil,nil);logic:setContainers(containers);logic:setRecipe(recipe)
 logic:setManualSelectInputs(true);logic:clearManualInputs()
 local items={state.material,state.tools[1],state.tools[2]}
 local inputs,choices,initial={},{},{}
 assert(recipe:getInputs():size()==3,'native recipe inputs differ')
 for i=0,2 do
  local native=recipe:getInputs():get(i);local index=recipe:getIndexForIO(native)
  local item=items[i+1];local selected=ArrayList.new();selected:add(item)
  assert(logic:setManualInputsFor(native,selected),'native recipe manual input refused')
  inputs[#inputs+1]={index=index,native=native,keep=native:isKeep()}
  choices[index]={amount=1,resourceIds={item:getID()},generated=0,fullType=item:getFullType()}
  initial[item:getID()]=true
 end
 logic:canPerformCurrentRecipe()
 local recipeReady=logic:canPerformCurrentRecipe()
 if not recipeReady then prepareWait(player,'native-recipe',worn,held,containers,recipeReady);return false end
 assert(T.Settings.craftChains(),'craft chains disabled')
 local plan={steps={{recipe={native=recipe,inputs=inputs},inputs=choices}},initialIds=initial}
 assert(T.CraftChainRecipes.enqueue(player,plan,{player=player}),'real craft chain producer refused')
 state.book:setAlreadyReadPages(state.book:getNumberOfPages()-1)
 player:setAlreadyReadPages(state.book:getFullType(),state.book:getNumberOfPages()-1)
 tail=ISReadABook:new(player,state.book);assert(tail.minutesPerPage==2.0 and tail.maxTime>1)
 ISTimedActionQueue.add(tail);discover()
 return true
end
local function transfers(action)
 if not action or action.Type~='ISInventoryTransferAction'or not action:isStarted()or action:getJobDelta()<=0 then return end
 local items=action.queueList and action.queueList[1]and action.queueList[1].items or {action.item}
 for _,item in ipairs(items)do for i,id in ipairs(ids.tools)do
  if item:getID()==id then
   local source=state.bags[i]:getItemContainer()
   if action.srcContainer==source and action.destContainer==state.root then picked[id]=true end
   if action.srcContainer==state.root and action.destContainer==source then returned[id]=true end
  end
 end end
end
local function keep(player,q)
 local rows={}
 for _,action in ipairs(q.queue)do
  if action.Type=='ISInventoryTransferAction'and action.allowMissingItems and action.srcContainer==state.root then
   for i,id in ipairs(ids.tools)do
    if action.item:getID()==id then
     assert(not rows[i]and action.destContainer==state.bags[i]:getItemContainer(),'native return origin changed')
     rows[i]=action
    end
   end
  end
 end
 local keptIndex=ids.keptIndex;local returnedIndex=3-keptIndex
 keptRow,siblingRow=assert(rows[keptIndex],'kept native return missing'),assert(rows[returnedIndex],'sibling native return missing')
 assert(not keptRow.action and not siblingRow.action and not keptRow.started and not siblingRow.started,'return already issued')
 assert(picked[ids.tools[1]]and picked[ids.tools[2]],'craft tools did not actually progress through pickups')
 assert(tail.toolkitQueueOperation~=current.toolkitQueueOperation,'independent reader joined craft')
 local token=current.toolkitQueueOperation;craftNative=current.action;keepProgress=current:getJobDelta()
 local allowed,reason,decision=T.ActionQueue.cancel(q,keptRow)
 if not allowed then
  local status=T.ActionQueueSettlement.operationState(current)
  local loans={};for _,loan in ipairs(status and status.borrowings or {})do loans[#loans+1]={id=loan.id,state=loan.state}end
  local pending={}
  for _,action in ipairs(q.queue)do
   local origin=action.destContainer and action.destContainer:getContainingItem()
   pending[#pending+1]={kind=action.Type,itemId=action.item and action.item:getID(),originId=origin and origin:getID()}
  end
  print('[CRAFT_QUEUE_TEST] KEEP_REFUSED '..JSON.encode({reason=reason,blocker=decision and decision.blocker and decision.blocker.Type,siblingEligible=T.ActionQueueExecution.inspect(siblingRow)~=nil,currentKind=q.current and q.current.Type,loans=loans,queue=pending}))
 end
 assert(allowed,reason)
 assert(q:indexOf(keptRow)==-1 and q:indexOf(siblingRow)>1 and q.current==current and q.queue[1]==current
  and current.action==craftNative and current.toolkitQueueOperation==token and not token.toolkitCancelled,
  'Keep altered current craft or its independent return')
 assert(state.root:getItemById(ids.tools[keptIndex]):getContainer()==state.root,'Keep moved the retained tool')
 assert(not T.ActionQueueSettlement.canWaivePendingReturn(keptRow,function()return true end),'retired row replayed Keep')
 kept=true
 print('[CRAFT_QUEUE_TEST] KEPT '..JSON.encode({case='keep-craft-tool',itemId=ids.tools[keptIndex],sourceId=ids.bags[keptIndex],progress=keepProgress}))
end
local function finish()
 local keptIndex=ids.keptIndex;local returnedIndex=3-keptIndex
 local value={event='case',id='keep-craft-tool',status='passed',reason=nil,toolIds=ids.tools,
  pickupIds=sorted(picked),returnIds=sorted(returned),keptId=ids.tools[keptIndex],keptSourceId=ids.bags[keptIndex],
  siblingId=ids.tools[returnedIndex],siblingSourceId=ids.bags[returnedIndex],keepSucceeded=true,keptRowRemoved=true,siblingPreserved=true,
  craftProgress=progress,craftProgressAfterKeep=afterKeep,keepProgress=keepProgress,tailProgress=tailProgress,
  returnsBeforeRead=returnsBeforeRead,tokenCancelled=current.toolkitQueueOperation.toolkitCancelled==true,
  producer='CraftChainRecipes.enqueue',nativeDuration=150,authorityVerified=true,playerId=ids.playerId,outcomeTrace=outcomeTrace}
 for key,result in pairs(receipt)do if key~='case'then value[key]=result end end
 emit(value)
 emit({event='complete',cases=config.cases,expected=1,performed=1,failed=0,skipped=0})
 done=true;print('[CRAFT_QUEUE_TEST] COMPLETE')
end
require('QueuePreflight').onTick(Events,function()
 if not started or done or not isIngameState()then return end
 local ok,problem=pcall(function()
  assert(getTimestampMs()-since<180000,'keep craft deadline '..phase)
  local player=getPlayer();if not player or player:isDead()or not player:getSquare()then return end
  if config.kind=='mp'and(not isClient()or player:getOnlineID()<0)then return end
  if phase=='prepare'then
   assert(T.Settings.actionQueue()and P4TidyUpMeister==nil and not getActivatedMods():contains('P4TidyUpMeister'),'wrong keep craft providers')
   emit({event='setup',cases=config.cases,expected=1,queueEnabled=true,nativeDurations=true})
   request('Prepare');phase='ready';return
  end
  if phase=='ready'then
   if not ids then return end
   assert(ids.case=='keep-craft-tool')
   state=state or Fixture.resolve(player,ids);if not state then return end
   readySince=readySince or getTimestampMs()
   assert(getTimestampMs()-readySince<25000,'keep craft readiness deadline '..tostring(state.prepareWaitReason))
   if not enqueue(player)then return end
   phase='running';since=getTimestampMs();return
  end
  if phase=='running'then
   local q=queue();discover();transfers(q.current)
   if current and q.current==current and current.craftStarted==true and current:isStarted()and current:getJobDelta()>0 then
    progress=true;assert(current:getDuration()==150 and not player:isTimedActionInstant(),'native craft duration changed')
    if not kept then
     local ack=config.kind=='mp'and T.ActionQueueAcknowledgements.capture(current)
     if config.kind=='sp'or ack and T.ActionQueueAcknowledgements.state(current,ack)=='started'then
      assert(current:getJobDelta()<=.25,'Keep missed early active craft');keep(player,q)
     end
    elseif current.action==craftNative and current:getJobDelta()>keepProgress then afterKeep=true end
   end
   if q.current==tail and tail:isStarted()and tail:getJobDelta()>0 then
    tailProgress=true
    local ki=ids.keptIndex;local ri=3-ki
    returnsBeforeRead=kept and not returned[ids.tools[ki]]and returned[ids.tools[ri]]==true
     and state.root:getItemById(ids.tools[ki]):getContainer()==state.root
     and state.bags[ri]:getItemContainer():getItemById(ids.tools[ri])~=nil
    assert(returnsBeforeRead,'independent return did not precede reader')
   end
   if #q.queue>0 or player:hasTimedActions()or(idle or 0)<3 then return end
   assert(kept and progress and afterKeep and tailProgress and returnsBeforeRead,'native Keep craft did not finish required progress')
   if config.kind=='mp'then
    if #outcomeTrace<2 then return end
    assert(#outcomeTrace==2 and outcomeTrace[1].state=='started'and outcomeTrace[2].state=='completed','native craft receipt differs')
   end
   request('Verify');phase='receipt';return
  end
  if phase=='receipt'and receipt then finish()end
 end)
 if not ok then done=true;print('[QUEUE_TEST] FAIL keep craft '..tostring(problem));emit({event='error',message=tostring(problem)})end
end)

end
