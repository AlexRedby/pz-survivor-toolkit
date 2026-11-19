return function()
require 'PZSurvivorToolkit/CraftChainRecipes'
local config=require 'QueueTestSelection'
local F=require 'QueueCraftFixture'
local JSON=require 'QueueHealthEvents'
local T=PZSurvivorToolkit
local editorEnabled=config.mode=='toolkit'
local step,phase,since,started,done=1,'prepare',0,false,false
local state,ids,current,tail,receipt,walk,readySince,settledSince,interrupted,pickupEvidence
local picked,returned,starts,seenReturns={},{},{},{}
local progress,tailProgress,stopped,idle=false,false,false,0
local bodyEvidence,originalRows,stopEvidence
local eventTrace,keepEvidence={},nil
local diagnose
local originalPickupWatch,pickupWatchForwarder
local function case()return config.cases[step]end
local function running()return case()=='run-editor-pickup-drill'end
local function restorePickupWatch()
 if pickupWatchForwarder and pzWatchInterruptedPickup==pickupWatchForwarder then
  pzWatchInterruptedPickup=originalPickupWatch
 end
 originalPickupWatch,pickupWatchForwarder=nil,nil
end
local function observePickupWatch(action)
 if config.kind~='mp'then return end
 pickupEvidence.watchEnrolled=false
 local watch=pzWatchInterruptedPickup
 if type(watch)~='function'then return end
 originalPickupWatch=watch
 pickupWatchForwarder=function(candidate)
  local result=watch(candidate)
  if candidate==action then pickupEvidence.watchEnrolled=result~=nil end
  return result
 end
 pzWatchInterruptedPickup=pickupWatchForwarder
end
local function keeping()return case()=='walk-editor-keep-saw'end
local function trace(event)if editorEnabled then eventTrace[#eventTrace+1]=event end end
local function walking()return case()~='complete-pinned-tools'end
local function q()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function sorted(set)local a={};for id in pairs(set)do a[#a+1]=id end;table.sort(a);return a end
local function emit(row)
 row.suite='craft';row.kind=config.kind;row.mode=config.mode;row.actor='client1';JSON.emit(row)
end
local function request(command)
 if config.kind=='mp'then sendClientCommand('CraftQueueTest',command,{case=case()})
 elseif command=='Prepare'then
  state=F.prepare(getPlayer(),case());ids=F.descriptor(state)
  print('[CRAFT_QUEUE_TEST] PREPARED '..JSON.encode(ids))
 else receipt=assert(F.verify(state,false));print('[CRAFT_QUEUE_TEST] WALK_AUTHORITY '..JSON.encode(receipt))end
end
Events.OnServerCommand.Add(function(module,command,value)
 if module~='CraftQueueTest'then return end
 if value.ok==false then pcall(diagnose,value.error)end
 assert(value.ok~=false,value.error)
 if command=='Prepared'then ids=value elseif command=='Verified'then receipt=value end
end)
Events.OnPlayerUpdate.Add(function(player)
 if started and player==getPlayer()then idle=#q().queue==0 and not player:hasTimedActions()and not player:isPlayerMoving()and idle+1 or 0 end
end)
local function rows()
 local result={}
 for _,action in ipairs(q().queue)do
  local source=action.srcContainer and action.srcContainer:getContainingItem()
  local dest=action.destContainer and action.destContainer:getContainingItem()
  result[#result+1]={row=string.match(tostring(action),'^%S+ %S+'),kind=action.Type,itemId=action.item and action.item:getID(),
   sourceId=source and source:getID(),destId=dest and dest:getID(),started=action:isStarted(),
   native=tostring(action.action),allowMissing=action.allowMissingItems==true}
 end
 return result
end
diagnose=function(problem)
 if not ids or not state then return end
 local endpoints={}
 for i,id in ipairs(ids.tools)do
  local item=state.root:getItemById(id);local container=item and item:getContainer()
  endpoints[i]={id=id,sourceId=ids.bags[i],present=item~=nil,root=container==state.root,
   source=container==state.bags[i]:getItemContainer(),capacity=state.bags[i]:getItemContainer():getCapacity(),
   room=item and state.bags[i]:getItemContainer():hasRoomFor(getPlayer(),item),
   picked=picked[id]==true,returned=returned[id]==true}
 end
 print('[CRAFT_QUEUE_TEST] FAILURE_DIAGNOSTICS '..JSON.encode({case=case(),problem=tostring(problem),phase=phase,
  body=bodyEvidence,originalRows=originalRows,stop=stopEvidence,queue=rows(),endpoints=endpoints,
  authority=config.kind=='sp'and require('QueueCraftWalkFixture').inspect(state)or false,
  returnStarts=starts,pickupIds=sorted(picked),returnIds=sorted(returned),
  walk=walk,pickup=pickupEvidence,nativeStop=stopped,tailProgress=tailProgress,idle=idle}))
end
-- Read-only transaction state before the actual native stop removes its cursor.
craftWalkStopEntering=function(action)
 if not running()or action~=interrupted then return end
 assert(not pickupEvidence.stopEntry,'repeated interrupted pickup stop entry')
 local tx=action.transactionId or 0
 pickupEvidence.stopEntry={transaction=tx,done=isItemTransactionDone(tx)==true,
  rejected=isItemTransactionRejected(tx)==true,current=q().current==action,
  sourcePresent=action.srcContainer:getItemById(ids.tools[2])~=nil,
  rootPresent=state.root:getItemById(ids.tools[2])~=nil and state.root:getItemById(ids.tools[2]):getContainer()==state.root}
end
-- Read-only receipt from the actual engine stop after the original Lua delegate.
craftWalkStopped=function(action,ok)
 if action~=(running()and interrupted or current)then return end
 assert(ok and walking()and walk and not stopped,'unexpected or repeated native craft/pickup stop')
 trace('native-stop');stopped=true;walk.stoppedAt=getTimestampMs()
 if running()then
  restorePickupWatch()
  pickupEvidence.stopTransaction=action.transactionId or 0
  pickupEvidence.stopDone=isItemTransactionDone(action.transactionId or 0)==true
  pickupEvidence.stopRejected=isItemTransactionRejected(action.transactionId or 0)==true
 end
 stopEvidence={x=getPlayer():getX(),y=getPlayer():getY(),queue=rows(),native=tostring(action.action),ok=ok}
end
require('QueuePreflight').onGameStart(Events,function()
 started=true;since=getTimestampMs();getCore():setOptionPauseOnFocusloss(false)
 craftWalkInput(getPlayer(),0)
 if not isClient()then getPlayer():setGhostMode(true)end
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
local function enqueue(player)
 local worn=player:getWornItem(state.bags[1]:canBeEquipped())==state.bags[1]
 local held=player:getSecondaryHandItem()==state.bags[2]
 if worn and held and not state.menuRefreshed then
  getPlayerInventory(player:getPlayerNum()):refreshBackpacks();getPlayerLoot(player:getPlayerNum()):refreshBackpacks()
  state.menuRefreshed=true;return false
 end
 local containers=ISInventoryPaneContextMenu.getContainers(player)
 if not worn or not held or not containers:contains(state.bags[1]:getItemContainer())
  or not containers:contains(state.bags[2]:getItemContainer())then return false end
 local recipe=assert(getScriptManager():getCraftRecipe('QueueKeepCraftTools'))
 local logic=HandcraftLogic.new(player,nil,nil);logic:setContainers(containers);logic:setRecipe(recipe)
 logic:setManualSelectInputs(true);logic:clearManualInputs()
 local items={state.material,state.tools[1],state.tools[2]};local inputs,choices,initial={},{},{}
 for i=0,2 do
  local native=recipe:getInputs():get(i);local index=recipe:getIndexForIO(native)
  local item=items[i+1];local selected=ArrayList.new();selected:add(item)
  assert(logic:setManualInputsFor(native,selected),'native manual input refused')
  inputs[#inputs+1]={index=index,native=native,keep=native:isKeep()}
  choices[index]={amount=1,resourceIds={item:getID()},generated=0,fullType=item:getFullType()};initial[item:getID()]=true
 end
 logic:canPerformCurrentRecipe();if not logic:canPerformCurrentRecipe()then return false end
 assert(T.Settings.craftChains(),'craft chains disabled')
 assert(T.CraftChainRecipes.enqueue(player,{steps={{recipe={native=recipe,inputs=inputs},inputs=choices}},initialIds=initial},{player=player}),
  'real pinned producer refused')
 state.book:setAlreadyReadPages(state.book:getNumberOfPages()-1)
 player:setAlreadyReadPages(state.book:getFullType(),state.book:getNumberOfPages()-1)
 tail=ISReadABook:new(player,state.book);ISTimedActionQueue.add(tail)
 return true
end
local function discover()
 for _,a in ipairs(q().queue)do
  if a.Type=='ISHandcraftAction'and a.craftRecipe==getScriptManager():getCraftRecipe('QueueKeepCraftTools')then
   assert(not current or current==a,'multiple native crafts');current=a
  end
 end
end
local function transfers(action)
 if not action or action.Type~='ISInventoryTransferAction'or not action:isStarted()or action:getJobDelta()<=0 then return end
 local items=action.queueList and action.queueList[1]and action.queueList[1].items or {action.item}
 for _,item in ipairs(items)do for i,id in ipairs(ids.tools)do
  if item:getID()==id then
   local source=state.bags[i]:getItemContainer()
   if action.srcContainer==source and action.destContainer==state.root then
    if not picked[id]then trace(i==1 and 'pickup-saw'or 'pickup-drill')end
    picked[id]=true
   end
   if action.srcContainer==state.root and action.destContainer==source then
    seenReturns[action]=seenReturns[action]or {}
    if not seenReturns[action][id]then
     trace(i==1 and 'return-saw'or 'return-drill');starts[#starts+1]=id;seenReturns[action][id]=true
    end
    returned[id]=true
   end
  end
 end end
end
local function returnsFinished()
 local seen={}
 for _,id in ipairs(starts)do
  assert(not seen[id],'native return started more than once for exact tool');seen[id]=true
  assert(id~=ids.tools[1]or(case()~='walk-pinned-full'and case()~='walk-editor-keep-saw'),'retained saw received forbidden return')
 end
 for i,id in ipairs(ids.tools)do
  local blocked=(case()=='walk-pinned-full'or case()=='walk-editor-keep-saw')and i==1
  local item=state.root:getItemById(id)
  if blocked then
   assert(not returned[id],'blocked source received forbidden transfer progress')
   if not item or item:getContainer()~=state.root then return false end
  elseif running()and i==2 and not returned[id]then
   if not item or item:getContainer()~=state.bags[i]:getItemContainer()then return false end
  elseif not returned[id]or not seen[id]or not item
   or item:getContainer()~=state.bags[i]:getItemContainer()then return false end
 end
 return true
end
local function keepSaw()
 local pending={}
 for _,action in ipairs(q().queue)do
  if action.Type=='ISInventoryTransferAction'and action.allowMissingItems and action.srcContainer==state.root then
   for i,id in ipairs(ids.tools)do
    if action.item:getID()==id then
     assert(not pending[i]and action.destContainer==state.bags[i]:getItemContainer(),'pending return identity/source changed')
     pending[i]=action
    end
   end
  end
 end
 local saw,drill=assert(pending[1],'pending saw row missing'),assert(pending[2],'pending drill row missing')
 assert(not saw.action and not drill.action and not saw.started and not drill.started,'return already issued')
 local native,token=current.action,current.toolkitQueueOperation
 assert(native and token and tail.toolkitQueueOperation~=token,'current craft/independent reader scope differs')
 local delta=current:getJobDelta()
 local allowed,reason=T.ActionQueue.cancel(q(),saw);assert(allowed,reason)
 assert(q():indexOf(saw)==-1 and q():indexOf(drill)>1 and q().current==current and q().queue[1]==current
  and current.action==native and current.toolkitQueueOperation==token and not token.toolkitCancelled,
  'Keep altered active craft or sibling pending return')
 assert(state.root:getItemById(ids.tools[1]):getContainer()==state.root,'Keep moved exact saw')
 keepEvidence={keptId=ids.tools[1],keptSourceId=ids.bags[1],siblingId=ids.tools[2],siblingSourceId=ids.bags[2],
  keepSucceeded=true,keptRowPending=true,keptRowRemoved=true,siblingPreserved=true,craftPreservedAfterKeep=true,keepProgress=delta}
 trace('keep-saw')
end
local function chooseDirection(player)
 -- Screen-forward and its rotations follow the cart native keyboard fixture.
 local offsets={{-1,-1},{-1,1},{1,1},{1,-1}}
 for direction,offset in ipairs(offsets)do
  local square=getCell():getGridSquare(math.floor(player:getX())+offset[1],math.floor(player:getY())+offset[2],math.floor(player:getZ()))
  if square and square:canStand()and square:isFree(false)then return direction end
 end
 error('no free neighbouring square for genuine walk interruption')
end
local function finish()
 restorePickupWatch()
 if running()then
  pickupEvidence.finalTransaction=interrupted.transactionId or 0
  pickupEvidence.finalDone=isItemTransactionDone(interrupted.transactionId or 0)==true
  pickupEvidence.finalRejected=isItemTransactionRejected(interrupted.transactionId or 0)==true
 end
 local value={event='case',id=case(),status='passed',producer='CraftChainRecipes.enqueue',queueEnabled=editorEnabled,
  toolIds=ids.tools,pickupIds=sorted(picked),returnIds=sorted(returned),returnStarts=starts,
  craftProgress=progress,tailProgress=tailProgress,tailDiscarded=walking()and q():indexOf(tail)==-1 and not tailProgress,
  nativeStop=stopped,nativeDuration=150,authorityVerified=true,
  walkDistance=walk and walk.distance or 0,walkProgress=walk and walk.progress or 0,
  inputReleased=not walk or walk.released==true,blockedToolId=case()=='walk-pinned-full'and ids.tools[1]or false}
 if editorEnabled then
  value.eventTrace=eventTrace;value.instantActions=getPlayer():isTimedActionInstant()
  value.pauseOnFocusLoss=getCore():getOptionPauseOnFocusloss();value.craftChainsEnabled=T.Settings.craftChains()
  value.foreignReturnProvider=false
  if pickupEvidence then value.pickup=pickupEvidence;value.runObserved=walk.running==true end
  if keepEvidence then for key,result in pairs(keepEvidence)do value[key]=result end end
 end
 for key,result in pairs(receipt)do if key~='case'then value[key]=result end end
 emit(value)
 if step==#config.cases then
  craftWalkInput(getPlayer(),-1);done=true
  emit({event='complete',cases=config.cases,expected=step,performed=step,failed=0,skipped=0});print('[CRAFT_QUEUE_TEST] COMPLETE')
 else
  step=step+1;phase='prepare';since=getTimestampMs();state,ids,current,tail,receipt,walk,readySince,settledSince=nil,nil,nil,nil,nil,nil,nil,nil
  picked,returned,starts,seenReturns={},{},{},{};progress,tailProgress,stopped,idle=false,false,false,0
  interrupted,pickupEvidence=nil,nil;bodyEvidence,originalRows,stopEvidence=nil,nil,nil;eventTrace,keepEvidence={},nil
 end
end
require('QueuePreflight').onTick(Events,function()
 if not started or done or not isIngameState()then return end
 local ok,problem=pcall(function()
  assert(getTimestampMs()-since<180000,'walking craft deadline '..phase)
  local player=getPlayer();if not player or player:isDead()or not player:getSquare()then return end
  if config.kind=='mp'and(not isClient()or player:getOnlineID()<0)then return end
  assert(T.Settings.actionQueue()==editorEnabled,'craft editor setting differs')
  assert(not player:isTimedActionInstant()and not getCore():getOptionPauseOnFocusloss(),'native controls differ')
  if phase=='prepare'then
   assert(P4TidyUpMeister==nil and not getActivatedMods():contains('P4TidyUpMeister'),'foreign returns provider selected')
   if step==1 then emit({event='setup',cases=config.cases,expected=#config.cases,queueEnabled=editorEnabled,nativeDurations=true})end
   request('Prepare');phase='ready';return
  end
  if phase=='ready'then
   if not ids then return end
   state=state or F.resolve(player,ids);if not state then return end
   readySince=readySince or getTimestampMs();assert(getTimestampMs()-readySince<25000,'native container/recipe readiness timeout')
   if not enqueue(player)then return end
   phase='running';since=getTimestampMs();return
  end
  if phase=='running'then
   discover();transfers(q().current);F.fillFirstOrigin(state)
   if running()and not walk then
    local action=q().current
    if action and action.Type=='ISInventoryTransferAction'and action.item and action.item:getID()==ids.tools[2]
     and action.srcContainer==state.bags[2]:getItemContainer()and action.destContainer==state.root
     and action:isStarted()and action:getJobDelta()>0 then
     local tx=action.transactionId or 0
     if config.kind=='mp'and(tx==0 or isItemTransactionDone(tx)or isItemTransactionRejected(tx))then return end
     local saw=state.root:getItemById(ids.tools[1])
     assert(picked[ids.tools[1]]and saw and saw:getContainer()==state.root,'first saw pickup not confirmed before run')
     assert(state.tools[2]:getContainer()==state.bags[2]:getItemContainer(),'interrupted drill already moved')
     assert(current and not current.craftStarted and not current.action,'craft started before interrupted drill pickup')
     assert(action:getJobDelta()<=.5 and action.stopOnRun==true,'missed native pickup run window')
     interrupted=action
     pickupEvidence={itemId=ids.tools[2],sourceId=ids.bags[2],firstId=ids.tools[1],firstConfirmed=true,
      sourcePresent=true,rootPresent=false,progress=action:getJobDelta(),duration=action:getDuration(),
      started=true,transaction=tx,done=isItemTransactionDone(tx)==true,rejected=isItemTransactionRejected(tx)==true,
      craftStarted=false,stopOnRun=true}
     bodyEvidence=T.ActionQueueSettlement.operationState(action)or {unavailable=true};originalRows=rows()
     walk={x=player:getX(),y=player:getY(),progress=action:getJobDelta(),since=getTimestampMs(),distance=0,running=false}
     observePickupWatch(action)
     trace('drill-progress');trace('run-input');craftWalkInput(player,chooseDirection(player)+4)
    end
   end
   if current and q().current==current and current.craftStarted==true and current:isStarted()and current:getJobDelta()>0 then
    if not progress then trace('craft-progress')end
    progress=true;assert(current:getDuration()==150 and current.stopOnWalk==true and not player:isTimedActionInstant())
    if walking()and not walk then
     local ack=editorEnabled and config.kind=='mp'and T.ActionQueueAcknowledgements.capture(current)
     if editorEnabled and config.kind=='mp'and(not ack or T.ActionQueueAcknowledgements.state(current,ack)~='started')then return end
     assert(picked[ids.tools[1]]and picked[ids.tools[2]],'actual pickups missing before walk')
     assert(current:getJobDelta()<=.25,'missed early native craft progress')
     assert(case()~='walk-pinned-full'or state.fullOrigin,'source not blocked before walk')
     if keeping()then keepSaw()end
     bodyEvidence=T.ActionQueueSettlement.operationState(current)or {unavailable=true}
     originalRows=rows()
     walk={x=player:getX(),y=player:getY(),progress=current:getJobDelta(),since=getTimestampMs(),distance=0}
     trace('walk-input');craftWalkInput(player,chooseDirection(player))
    end
   end
   if walk and not walk.released then
    if running()and player:isRunning()then walk.running=true end
    walk.distance=math.sqrt((player:getX()-walk.x)^2+(player:getY()-walk.y)^2)
    assert(getTimestampMs()-walk.since<7000,'genuine native walk/stop timed out')
    if stopped and walk.distance>=.25 and(not running()or walk.running)then
     craftWalkInput(player,0);walk.released=true;walk.releasedAt=getTimestampMs();idle=0;settledSince=nil
    end
   end
   if q().current==tail and tail:isStarted()and tail:getJobDelta()>0 then tailProgress=true end
   if walk and walk.released then
    assert(getTimestampMs()-walk.releasedAt<20000,'native earned return settlement timed out')
   end
   if #q().queue>0 or player:hasTimedActions()or player:isPlayerMoving()or idle<3
    or walk and not walk.released or not running()and not returnsFinished()then settledSince=nil;return end
   -- Native movement clears the queue before its deferred restoration can start.
   -- Only settle after actual expected transfers, stationary native idle and a
   -- quiet interval; idle accumulated while walking cannot pay this gate.
   settledSince=settledSince or getTimestampMs()
   if getTimestampMs()-settledSince<(running()and 1000 or 250)then return end
   assert(current and(progress or running()and pickupEvidence)and picked[ids.tools[1]]and picked[ids.tools[2]],'native craft/pickup progress missing')
   assert(walking()and stopped and not tailProgress or not walking()and not stopped and tailProgress,'native stop/tail differs')
   request('Verify');phase='receipt';return
  end
  if phase=='receipt'and receipt then finish()end
 end)
 if not ok then
  restorePickupWatch()
  pcall(diagnose,problem)
  craftWalkInput(getPlayer(),-1);done=true;emit({event='error',message=tostring(problem)});print('[QUEUE_TEST] FAIL walking craft '..tostring(problem))
 end
end)
end
