require 'PZSurvivorToolkit/ActionQueuePanel'
require 'ISUI/ISFitnessUI'
require 'Definitions/FitnessExercises'
require 'TimedActions/ISFitnessAction'
local F=require 'QueueFitnessFixture'
local Settlement=require 'PZSurvivorToolkit/ActionQueueSettlement'
local O=require 'QueueFitnessObservation'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local native=config.mode=='native'
local T=PZSurvivorToolkit
local API,Ops=T.ActionQueue,T.ActionQueueOperations
local state,authority,previous,ids,receipt,mutation,command,ui,front,tail,requests,seen,ack,progressSeen,menuGate
local started,done,phase,index,failed,since,quiet,idle=false,false,'prepare',1,0,0,nil,0
local peerCase,peerBook,peerComplete,actor,stopReached,returnSeen,recoverySeen,recoveryActions
local ready,setupSince,preparedInitialized,prepareLogged=false,0,false,nil
local peersReady,peersReceipt,isolationAuthority,isolationFinalAuthority=false,nil,nil,nil
local function case()return config.cases[index]end
local function minutes()return case()=='burpees-30'and 30 or 10 end
local function exerciseForCase(id)return id=='burpees-30'and 'burpees'or (id=='missing-dumbbell'or F.borrowedCase(id))and 'bicepscurl'or 'squats'end
local function immediate(id)return id=='empty'or id=='empty-restore'or id=='active-cancel'or id=='burpees-30'or F.restorationCase(id)end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()end
-- Retain the exact workout after it stops being the head. Native removal and
-- queue continuation are independent gates and share this first deadline sample.
local function sampleDurationStop(action)
 if native or not command or not action or not seen[action]
  or action.Type~='ISFitnessAction'then return end
 local sample=stopReached[action]
 if not sample then
  local progress=T.ActionQueueFitness.progress(action)
  if not progress or not progress.stopMS then return end
  sample={workoutStartMS=progress.startMS,workoutEndMS=progress.endMS,
   stopNativeClock=progress.stopMS,reachedNativeClock=progress.stopMS,reachedTimestampMilliseconds=progress.stopTimestampMS}
  stopReached[action]=sample
  command.durationStops=command.durationStops or {}
  command.durationStops[#command.durationStops+1]={startMS=progress.startMS,endMS=progress.endMS,
   stopMS=progress.stopMS,confirmed=progress.confirmed}
 end
 if case()=='burpees-30'and command.durationStopDelayMilliseconds==nil and not action.character:getCharacterActions():contains(action.action)then
  command.durationStopDelayMilliseconds=getTimestampMs()-sample.reachedTimestampMilliseconds
 end
 return sample
end
local function observeDurationContinuation(nextAction)
 for action in pairs(seen or {})do sampleDurationStop(action)end
 if native or case()~='burpees-30'or not command or not state or command.durationContinuation
  or not nextAction or nextAction.Type~='ISReadABook'or getmetatable(nextAction)~=ISReadABook
  or nextAction.character~=state.player or not nextAction.item
  or nextAction.item:getID()~=state.ids.items.tail or nextAction.item:getFullType()~='Base.BookFirstAid1'then return end
 for action in pairs(seen)do
  local sample=sampleDurationStop(action)
  if sample then
   local record=ack[action]
   local terminal=isClient()and record and T.ActionQueueAcknowledgements.observe(action,record)or not isClient()and 'singleplayer'
   command.durationContinuation={workoutStartMS=sample.workoutStartMS,workoutEndMS=sample.workoutEndMS,
    reachedNativeClock=sample.reachedNativeClock,stopNativeClock=sample.stopNativeClock,reachedTimestampMilliseconds=sample.reachedTimestampMilliseconds,
    continuationNativeClock=O.durationClock(),continuationTimestampMilliseconds=getTimestampMs(),
    delayMilliseconds=getTimestampMs()-sample.reachedTimestampMilliseconds,tailId=nextAction.item:getID(),
    callback='ISBaseTimedAction.begin',nativeAbsent=not action.character:getCharacterActions():contains(action.action),
    terminalState=terminal or false,token=record and record.token or false}
  end
 end
end
-- The shared native begin boundary runs before native actions allocate/start,
-- including queue-disabled mode. Observation changes no callback or queue work.
assert(T.ActionQueueLifecycle.registerObserver('fitness-independent-tail',{started=function(action)
 observeDurationContinuation(action)
 if state and state.isolation and state.isolation.status=='started'then F.isolationStarted(state,action);return end
 if not command or not state or not F.borrowedCase(case())then return end
 if action.Type=='ISEquipWeaponAction'and getmetatable(action)==ISEquipWeaponAction and action.character==state.player
  and action.item and action.item:getID()==state.ids.items.dumbbell and action.item:getFullType()=='Base.DumbBell'then
  command.propEquipObserved=true
 end
 local returned=F.observeReturnStart(state,action,returnSeen)
 if returned then
  command.returnCount=command.returnCount+1;returned.ordinal=command.returnCount
  command.returnStarts[#command.returnStarts+1]=returned
 end
 local recovered=F.observeRecoveryStart(state,action,recoverySeen)
 if recovered then
  recovered.ordinal=#command.recoveryStarts+1;command.recoveryStarts[#command.recoveryStarts+1]=recovered
  recoveryActions[#recoveryActions+1]=action
 end
 if action.Type=='ISReadABook'and action.item==state.items.tail and action.character==getPlayer()then
  command.beforeTail={inventory=F.inventory(action.character),activation=F.activation(action.character),nativeClock=O.clock(),
   callback='ISBaseTimedAction.begin',storage=F.storage(action.character,state.ids.items.bag)}
 end
end,begin=function(action,phase)
 if state and state.isolation and state.isolation.status=='started'then return F.isolationBegin(state,action,phase)end
 -- Queue-disabled ActionCompletion dispatches finish only for an accepted observer.
 return command~=nil and state~=nil and F.borrowedCase(case())and action~=nil
  and (phase=='perform'or phase=='complete')and action.character==state.player
  and action.Type=='ISDropWorldItemAction'and getmetatable(action)==ISDropWorldItemAction and action.item~=nil
  and action.item:getID()==state.ids.items.bag and action.item:getFullType()=='Base.Bag_Schoolbag'
end,finish=function(action,phase,succeeded)
 if state and state.isolation and state.isolation.status=='started'then F.isolationFinish(state,action,phase,succeeded);return end
 if not isClient()and not isServer()and command and state and F.borrowedCase(case())
  and action.character==state.player and action.Type=='ISDropWorldItemAction'and getmetatable(action)==ISDropWorldItemAction
  and action.item and action.item:getID()==state.ids.items.bag and action.item:getFullType()=='Base.Bag_Schoolbag'and phase=='complete'then
  O.placements[#O.placements+1]=F.placement(action.character,state.ids.items.bag,'ISDropWorldItemAction.complete',succeeded==true)
 end
end}),'fitness native reader boundary observer unavailable')
local function emit(row)
 row.suite,row.kind,row.mode,row.actor='fitness',config.kind,config.mode,actor;JSON.emit(row)
end
local function raw(marker,row)print('[FITNESS_TEST] '..marker..' '..JSON.encode(row))end
local diagnostics=require('QueueFitnessDiagnostics').install(config,{case=case,player=getPlayer,emit=raw,
 active=function()return actor=='client1'and state~=nil end})
local function cancel(action,message)
 local accepted,reason=API.cancelOperation(queue(),action)
 if not accepted then
  local policy=T.ActionQueuePolicy;local decision=policy.evaluateCancel(queue(),action,true);local members={}
  for _,member in ipairs(queue().queue)do
   local contract,adapter=policy.inspect(member)
   members[#members+1]={kind=member.Type,stage=member.toolkitFitnessStage or false,adapter=adapter or false,
    managed=T.ActionQueueFitness.isManaged(member),cancelWaiting=contract and contract.cancelWaiting or false,
    cancelOperation=contract and contract.cancelOperation~=false or false,preparation=contract and contract.preparation or false,
    preparationFinish=contract and contract.preparationFinish or false,deferred=contract and contract.deferred or false,
    adding=member._isAddingActions==true,completeCallback=member.onCompleteFunc~=nil,
    completeCallbackSafe=member.onCompleteFunc==member.toolkitQueueSafeOnComplete}
  end
  raw('CANCEL_REJECTED',{case=case(),reason=reason or false,decisionReason=decision.reason or false,
   blocker=decision.blocker and decision.blocker.Type or false,first=decision.first or false,last=decision.last or false,
   current=action.Type,preparationCanFinish=policy.preparationCanFinish(action),members=members})
 end
 assert(accepted,message..' ('..tostring(reason)..')')
end
local function run(fn,...)
 if native then return fn(...)end
 return Ops.run(fn,...)
end
local function read(book)
 local before={};for _,action in ipairs(queue().queue)do before[action]=true end
 run(ISInventoryPaneContextMenu.onLiteratureItems,{book},getPlayer():getPlayerNum())
 local action
 for _,candidate in ipairs(queue().queue)do
  if not before[candidate]and candidate.Type=='ISReadABook'and candidate.item==book then
   assert(not action,'duplicate native fitness reader');action=candidate
  end
 end
 assert(action,'native fitness reader not queued')
 assert(action.Type=='ISReadABook'and action.item==book and action.minutesPerPage==2,'reader native duration differs')
 return action
end
local function finish()
 emit({event='complete',cases=config.cases,expected=#config.cases,performed=index-1,failed=failed,skipped=0})
 print('[FITNESS_TEST] COMPLETE');done=true
end
local function request(name)
 if isClient()then sendClientCommand('FitnessQueueTest',name,{case=case(),clientQuiescent=empty(),failedCaseRecorded=state and state.failedCaseRecorded==true,items=state and state.ids.items or nil,isolationPhase=state and state.isolation and 'after'or 'before'});return end
 if name=='Prepare'then
  authority=F.prepare(getPlayer(),case(),previous);previous=nil;ids=authority.ids;raw('PREPARED',ids)
 elseif name=='Mutate'then mutation=F.mutate(authority);raw('MUTATED',mutation)
 elseif name=='Verify'then receipt=F.receipt(authority);receipt.serverSettleMilliseconds=getTimestampMs()-quiet;raw('VERIFIED',receipt);authority.verified=true
 elseif name=='Next'then F.releaseEquipment(authority);previous=authority;authority=nil;phase='released'end
end
Events.OnServerCommand.Add(function(module,name,value)
 -- Sample before the next queue tick can prune a settled workout's private record.
 for action in pairs(seen or {})do sampleDurationStop(action)end
 if module~='FitnessQueueTest'then return end
 if name=='Failed'then
  if phase=='isolation-ready'or phase=='isolating'or phase=='isolation-verifying'then
   raw('ISOLATION_FAILED',{case=case(),actor='client1',mode='native',kind='mp',phase='failed',reason=tostring(value and value.error),failedCaseRecorded=true})
  end
  print('[QUEUE_TEST] FAIL fitness authority '..tostring(value and value.error))
  emit({event='error',id=case(),reason=tostring(value and value.error)});done=true;return
 end
 if name=='IsolationReady'then
  assert(value.case==case(),'native isolation authority case differs')
  if value.phase=='before'then isolationAuthority=value elseif value.phase=='after'then isolationFinalAuthority=value else error('native isolation authority phase differs')end
 elseif name=='Prepared'then ids=value elseif name=='Verified'then receipt=value elseif name=='Mutated'then mutation=value
 elseif name=='NativeRep'then
  if command and value.case==case()then command.authoritativeReps=value.reps end
 elseif name=='Released'then phase='released'elseif name=='Peer'then peerCase,peerBook=value.case,value.book
 elseif name=='PeerComplete'then peerComplete=true elseif name=='PeersReady'then peersReceipt=value end
end)
Events.OnGameStart.Add(function()
 -- Host identity and the local player can still be incomplete in this callback.
 -- The role file is written by the common runner; validate the live peer on ticks.
 started=true;setupSince=getTimestampMs();since=setupSince
end)
local function initialize()
 if not actor then
  local reader=assert(getFileReader('smoke-user.txt',false),'fitness runner role missing')
  actor=reader:readLine();reader:close()
  assert(actor=='client1'or config.kind=='mp'and actor=='client2','unexpected fitness runner actor')
 end
 local player=getPlayer()
 if not isIngameState()or not player or not player:getSquare()or player:isDead()then return false end
 if isClient()~=(config.kind=='mp')then return false end
 if config.kind=='mp'and (player:getOnlineID()<0 or player:getUsername()~=actor)then return false end
 local option=assert(PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'));option:setValue(not native)
 assert(not player:isTimedActionInstant(),'fitness requires native SP/Host timing')
 getCore():setOptionPauseOnFocusloss(false);player:setGhostMode(true);player:setAutoDrink(false)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
 ready=true;since=getTimestampMs()
 raw('IDENTITY_READY',{actor=actor,kind=config.kind,onlineID=config.kind=='mp'and player:getOnlineID()or -1})
 if actor=='client1'then emit({event='setup',cases=config.cases,expected=#config.cases,nativeDurations=true,queueEnabled=not native})end
 if config.kind=='mp'then sendClientCommand('FitnessQueueTest','Ready',{actor=actor,onlineID=player:getOnlineID()})end
 return true
end
local function open()
 ui=ISFitnessUI:new(20,20,700,450,getPlayer(),getPlayer():getSquare());ui:initialise();ui:addToUIManager();ui:setVisible(true)
 assert(tonumber(ui.exeTime:getInternalText())==10,'native fitness menu default duration changed')
end
local function rejectedRequest(exercise,first,last)
 local children={}
 for i=first,last do local action=queue().queue[i]
  children[#children+1]={kind=action.Type,stage=action.toolkitFitnessStage or false,
   deferred=action.onCompleteArgs and action.onCompleteArgs.p1 and action.onCompleteArgs.p1.Type or false}
 end
 local function closure(fn)
  return type(fn)=='function'and getFilenameOfClosure and getFilenameOfClosure(fn)or 'unavailable'
 end
 local callbacks={uiClick=closure(ISFitnessUI.onClick)}
 for _,kind in ipairs({'ISFitnessAction','ISQueueActionsAction','ISUnequipAction','ISEquipWeaponAction','ISInventoryTransferAction','ISWearClothing','ISDropWorldItemAction'})do
  local class=_G[kind];local methods={}
  for _,name in ipairs({'new','isValid','start','perform','complete'})do methods[name]=closure(class and class[name])end
  callbacks[kind]=methods
 end
 raw('REQUEST_REJECTED',{case=case(),exercise=exercise,children=children,callbacks=callbacks})
end
local function enqueue(exercise)
 ui.selectedExe=exercise;ui:selectedNewExercise();ui.exeTime:setText(tostring(minutes()));ui:updateButtons(queue().queue[1])
 if not ui.ok.enable then
  raw('MENU_NOT_READY',F.menuDiagnostic(ui,case(),menuGate and getTimestampMs()-menuGate.since or 0,'dispatch-disabled'))
  error('native fitness OK not enabled')
 end
 local before=#queue().queue;ui:onClick(ui.ok)
 local first=assert(queue().queue[before+1],'native fitness menu produced no request')
 local requestAction
 for i=before+1,#queue().queue do
  local action=queue().queue[i]
  local candidate,deferred=F.requestedAction(action,ui,native,exercise)
  if candidate then requestAction=candidate;if deferred then command.nativeGetUpDeferred=true end end
 end
 if not requestAction then rejectedRequest(exercise,before+1,#queue().queue);error('native fitness/request action missing')end
 requests[#requests+1]=requestAction
 if native and case()=='empty-restore'then command.requestNativeClock={constructorStartMS=requestAction.startMS,deadlineMS=requestAction.endMS}end
 if native and F.borrowedCase(case())then state.requestedCurrent=requestAction.fitness:getCurrentExe()end
 if not native then
  local managed=T.ActionQueueFitness.isManaged(requestAction)and requestAction.toolkitFitnessExercise==exercise
   and requestAction.toolkitFitnessMinutes==minutes()
  if not managed then rejectedRequest(exercise,before+1,#queue().queue);error('fitness command did not snapshot menu parameters')end
 end
 return first,requestAction
end
local function dispatch()
 local id=case();requests,seen,ack,progressSeen,stopReached,returnSeen,recoverySeen,recoveryActions={},{},{},{},{},{},{},{}
 command={menuDispatched=true,nativeDurations=true,minutes=minutes(),frontMinutes=immediate(id)and 0 or 12,
  waitingNoExercise=true,waitingNoClinicalEffects=true,activeObserved=false,activeCancelled=false,pendingCancelled=false,
  reordered=false,closedUI=false,startedOrder={},activeAcks={},terminalAcks={},progressSamples={},durationStops={},queueDrained=false}
 if not immediate(id)then front=read(state.items.front)end
 local first=enqueue(exerciseForCase(id))
 if id=='sequential'then enqueue('pushups')end
 if F.borrowedCase(id)then command.propEquipObserved=false;command.returnCount=0;command.returnStarts={};command.recoveryStarts={} end
 tail=read(state.items.tail)
 command.waitStartMS=O.clock();command.initialClinical=O.clinical(getPlayer())
 if front then command.waitingNoExercise=not getPlayer():getFitness():getCurrentExe()end
 if id=='pending-cancel'and not native then
  assert(API.cancelOperation(queue(),first),'pending fitness cancellation rejected')
  command.pendingCancelled=true
  assert(queue():indexOf(front)~=-1 and queue():indexOf(tail)~=-1,'fitness cancellation removed independent readers')
 elseif id=='pending-reorder'and not native then
  assert(API.move(queue(),first,tail,true),'pending fitness reorder rejected')
  command.reordered=true
  assert(queue():indexOf(front)<queue():indexOf(tail)and queue():indexOf(tail)<queue():indexOf(first),'whole workout order differs')
 elseif id=='closed-ui-restore'then ui:onClick(ui.close);command.closedUI=true end
 if id=='missing-dumbbell'or id=='exhaustion'then request('Mutate')end
 phase='running';since=getTimestampMs();quiet=nil
end
local function observe()
 local player=getPlayer();local current=queue().queue[1]
 if case()=='exhaustion'and command.mutationObserved then player:getStats():set(CharacterStat.ENDURANCE,.01)end
 O.sample(current)
 if F.borrowedCase(case())and current and current.Type=='ISInventoryTransferAction'and current.item
  and current.item:getID()==state.ids.items.dumbbell and current.srcContainer==state.items.bag:getItemContainer()
  and current.destContainer==player:getInventory()and current:isStarted()and current:getJobDelta()>0 then
  command.borrowedTransferProgress=true;command.borrowedTool=state.ids.items.dumbbell
  command.borrowedSourceBag=state.ids.items.bag
  if case()=='pickup-cancel-restore'and not command.pickupCancelled then
   command.pickupCancelInventory=F.inventory(player);command.pickupCancelStorage=F.storage(player,state.ids.items.bag)
   command.pickupCancel={id=current.item:getID(),kind=current.item:getFullType(),source=state.ids.items.bag,
    destination='root',progress=current:getJobDelta(),started=current:isStarted(),transaction=current.transactionId or 0}
   if native then ui:onClick(ui.cancel);command.cancelCallback='ISFitnessUI:CANCEL'
   else cancel(current,'in-flight fitness pickup cancellation rejected');command.cancelCallback='ActionQueue.cancelOperation'end
   command.pickupCancelled=true
   assert(queue():indexOf(tail)~=-1,'pickup cancellation removed independent tail')
  end
 end
 if case()=='placement-cancel-restore'and current and current.Type=='ISDropWorldItemAction'and current.item
  and current.item:getID()==state.ids.items.bag and current:isStarted()and current:getJobDelta()>0 and not command.placementCancelled then
  command.placementCancel={id=current.item:getID(),kind=current.item:getFullType(),progress=current:getJobDelta(),started=true,
   isPlaceItem=current.isPlaceItem==true,square={x=current.sq:getX(),y=current.sq:getY(),z=current.sq:getZ()},storage=F.storage(player,state.ids.items.bag),inventory=F.inventory(player)}
  if native then ui:onClick(ui.cancel);command.cancelCallback='ISFitnessUI:CANCEL'
  else cancel(current,'in-flight fitness placement cancellation rejected');command.cancelCallback='ActionQueue.cancelOperation'end
  command.placementCancelled=true
  assert(queue():indexOf(tail)~=-1,'placement cancellation removed independent tail')
 end
 if not native and F.borrowedCase(case())then
  command.recoverySettlements={}
  for _,action in ipairs(recoveryActions)do command.recoverySettlements[#command.recoverySettlements+1]=Settlement.operationState(action)or false end
  local status=Settlement.operationState(requests[1])
  if status then
   command.settlement=status
   for _,binding in ipairs(status.borrowings)do
    if binding.id==state.ids.items.dumbbell and binding.fullType=='Base.DumbBell'then
     if binding.state=='active'then command.confirmedPickup=true end
     if binding.state=='completed'then command.confirmedReturn=true end
    end
   end
   if current and current.Type=='ISFitnessAction'then
    local earned,count=true,0
    for _,step in ipairs(status.steps)do
     if step.observedPreparation then count=count+1;if step.state~='earned'then earned=false end end
    end
    if earned and count==6 then command.confirmedPreparation=true;command.preparationAtCancel=status end
   end
  end
 end
 if front and queue():indexOf(front)~=-1 then
  command.waitMS=O.clock()-command.waitStartMS
  if player:getFitness():getCurrentExe()then command.waitingNoExercise=false end
  local now=O.clinical(player);local before=command.initialClinical
  if now.fitnessXP~=before.fitnessXP or now.strengthXP~=before.strengthXP then command.waitingNoClinicalEffects=false end
 end
 if current and current.Type=='ISFitnessAction'and current:isStarted()then
  command.activeObserved=true
  if not seen[current]then
   seen[current]=true;command.startedOrder[#command.startedOrder+1]=current.exeDataType
   if case()=='pending-reorder'and not native then
    command.reorderedTailBeforeStart=getPlayer():getAlreadyReadPages(state.items.tail:getFullType())==state.items.tail:getNumberOfPages()
   end
   assert(current.timeToExe==minutes() and current.getDuration==ISFitnessAction.getDuration and current:getDuration()==5000000,'native fitness duration modified')
  end
  local progress=not native and T.ActionQueueFitness.progress(current)
  if case()=='empty-restore'and not command.nativeWorkoutClock and (native or progress and progress.confirmed)then
   command.nativeWorkoutClock={constructorStartMS=current.startMS,deadlineMS=current.endMS,
    observedBodyStartMS=O.clock(),source='actual started ISFitnessAction'}
  end
  if not native and not progressSeen[current]then
   if progress and progress.fraction>0 then
    local sampleMS=O.durationClock();local expected=math.max(0,math.min(minutes(),(sampleMS-progress.startMS)/60000))
    assert(progress.total==minutes() and progress.elapsed>0 and progress.elapsed<=minutes() and progress.fraction<=1
     and math.abs(progress.elapsed-expected)<.000001 and math.abs(progress.fraction-progress.elapsed/minutes())<.000001,
     'fitness displayed progress differs from selected native time')
    local description=T.ActionQueueFitness.describe(current)
    assert(description and type(description.target)=='string'and description.target~='','fitness progress label missing')
    command.progressSamples[#command.progressSamples+1]={exercise=current.exeDataType,total=progress.total,
     elapsed=progress.elapsed,fraction=progress.fraction,startMS=progress.startMS,sampleMS=sampleMS,label=description.target}
    progressSeen[current]=true
   end
  end
  if isClient()and not native then
   local record=T.ActionQueueAcknowledgements.capture(current)
   if record and not ack[current]then ack[current]=record;command.activeAcks[#command.activeAcks+1]=record.token end
  end
  local clinical=O.clinical(player)
  -- In Host the authoritative rep witness is server-side. Native animation progress plus
  -- at least three real seconds and a started acknowledgement precede cancellation.
  if (case()=='active-cancel'or case()=='active-cancel-restore')and not command.activeCancelled then
   command.activeSince=command.activeSince or getTimestampMs()
   local repObserved=isClient()and (command.authoritativeReps or 0)>0 or not isClient()and current.repnb>0
   if repObserved and getTimestampMs()-command.activeSince>=3500 and (not isClient()or native or ack[current])and (case()~='active-cancel-restore'or native or command.confirmedPreparation)then
    if native then ui:onClick(ui.cancel)else cancel(current,'active fitness cancellation rejected')end
    command.activeCancelled=true
    if F.restorationCase(case())then command.cancelCallback=native and 'ISFitnessUI:CANCEL'or 'ActionQueue.cancelOperation' end
   end
  end
 end
 if case()=='empty-restore'and command.nativeWorkoutClock and not command.nativeWorkoutClock.observedRemovalMS then
  for action in pairs(seen)do
   if action.Type=='ISFitnessAction'and not player:getCharacterActions():contains(action.action)then
    local clock=command.nativeWorkoutClock;clock.observedRemovalMS=O.clock()
    clock.constructorStartAtRemovalMS=action.startMS;clock.deadlineAtRemovalMS=action.endMS
   end
  end
 end
 if not native then
  for action in pairs(seen)do sampleDurationStop(action)end
 end
 for action,record in pairs(ack or {})do
  if record.state~='started'and not seen[record] then
   seen[record]=true;command.terminalAcks[#command.terminalAcks+1]={token=record.token,state=record.state}
  end
 end
end
local function finishCase()
 local localInventory=F.inventory(getPlayer())
 command.queueDrained=empty();command.clientInventory=localInventory
 if F.borrowedCase(case())then command.clientActivation=F.activation(getPlayer());command.clientStorage=F.storage(getPlayer(),state.ids.items.bag)end
 command.clientCurrentExerciseCleared=not getPlayer():getFitness():getCurrentExe()
 local problem
 if not receipt.tailRead then problem='independent-tail-not-preserved'
 elseif not receipt.serverStopSettled or not receipt.currentExerciseCleared then problem='native-fitness-stop-not-settled'end
 local published={event='case',id=case(),status=problem and 'failed'or 'passed',reason=problem,command=command,receipt=receipt}
 emit(published)
 if problem then failed=failed+1 end
 if ui then ui:onClick(ui.close);ui=nil end
 if native and isClient()and F.borrowedCase(case())and problem and #receipt.records==0
  and receipt.currentExerciseCleared and not command.clientCurrentExerciseCleared then
  state.failedCaseRecorded,state.lastReceipt,state.failedRow=true,receipt,published
  state.failedRowEncoding=JSON.encode(published);state.strandedCurrent=getPlayer():getFitness():getCurrentExe()
  phase='isolation-ready';since=getTimestampMs();quiet=nil;isolationAuthority=nil;request('IsolationReady');return
 end
 -- Preserve the failed row and original receipt before fixture-only recovery.
 if native and problem and not receipt.currentExerciseCleared and #receipt.records==0
  and (case()=='missing-dumbbell'or case()=='exhaustion')then
  state.verified,state.failedCaseRecorded,state.lastReceipt=true,true,receipt
  state.strandedCurrent=getPlayer():getFitness():getCurrentExe()
  if state.strandedCurrent then raw('RECOVERY',F.recoverStranded(state))end
 end
 phase='release';request('Next')
end
local function peerTick()
 if peerCase and peerBook then
  local book=getPlayer():getInventory():getItemById(peerBook);if not book then return end
  if not seen then
   book:setAlreadyReadPages(book:getNumberOfPages()-1);getPlayer():setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
   read(book);seen=true
  elseif empty()and getPlayer():getAlreadyReadPages(book:getFullType())==book:getNumberOfPages()then
   emit({event='case',id=peerCase,book=peerBook,read=true,queueDrained=true})
   peerCase,peerBook,seen=nil,nil,nil
  end
 end
 if peerComplete and not peerCase then print('[FITNESS_TEST] COMPLETE');done=true end
end
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,problem=pcall(function()
  if not ready then
   assert(getTimestampMs()-setupSince<90000,'fitness network-ready identity deadline')
   if not initialize()then return end
  end
  if not isIngameState()or not getPlayer()or not getPlayer():getSquare()then return end
  if config.kind=='mp'and not peersReady then
   assert(getTimestampMs()-since<90000,'fitness peer readiness deadline')
   if not peersReceipt then return end
   assert(type(peersReceipt.client1)=='number'and type(peersReceipt.client2)=='number'
    and peersReceipt.client1>=0 and peersReceipt.client2>=0 and peersReceipt.client1~=peersReceipt.client2
    and peersReceipt[actor]==getPlayer():getOnlineID(),'fitness peer readiness identity differs')
   peersReady=true;raw('PEERS_READY',{actor=actor,client1=peersReceipt.client1,client2=peersReceipt.client2})
  end
  if actor=='client2'then peerTick();return end
  assert(getTimestampMs()-since<210000,'native fitness deadline '..phase..' '..tostring(case()))
  assert(T.Settings.actionQueue()==not native,'fitness queue mode changed')
  if diagnostics then diagnostics.poll()end
  idle=empty()and idle+1 or 0
  if phase=='prepare'then
   if idle<10 or getPlayer():tooDarkToRead()then return end
   phase='prepared';request('Prepare')
  elseif phase=='prepared'then
   local cached=state
   state=ids and F.resolve(getPlayer(),ids)or nil
   if state and not preparedInitialized then
    -- Initialize once even when later packets replace the exact-ID item replicas.
    for name,pages in pairs({front=6,tail=1})do local book=state.items[name]
     book:setAlreadyReadPages(book:getNumberOfPages()-pages);getPlayer():setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-pages)
    end
    getPlayer():getStats():set(CharacterStat.ENDURANCE,1);getPlayer():getStats():set(CharacterStat.FATIGUE,0)
    preparedInitialized=true
   end
   if not F.prepareReady(state)then
    local now=getTimestampMs()
    if not prepareLogged or now-prepareLogged>=5000 then
     prepareLogged=now;raw('PREPARE_WAIT',F.prepareDiagnostic(getPlayer(),ids,cached,case(),now-since))
    end
    return
   end
   open();ui.selectedExe=exerciseForCase(case())
   ui:selectedNewExercise();menuGate={since=getTimestampMs(),ticks=0};phase='menuReady'
  elseif phase=='menuReady'then
   local now=getTimestampMs();local readiness=F.menuReady(ui,queue().queue[1],menuGate,now)
   if readiness=='ready'then
    raw('MENU_READY',F.menuDiagnostic(ui,case(),now-menuGate.since,'ready'));dispatch()
   elseif readiness=='expired'then
    raw('MENU_NOT_READY',F.menuDiagnostic(ui,case(),now-menuGate.since,'expired'))
    error('native fitness menu did not become ready')
   elseif not ui.ok.enable and (not menuGate.logged or now-menuGate.logged>=5000)then
    menuGate.logged=now;raw('MENU_WAIT',F.menuDiagnostic(ui,case(),now-menuGate.since,'waiting'))
   end
  elseif phase=='running'then
   if mutation then
    assert(mutation.case==case(),'fitness mutation case differs')
    if case()=='exhaustion'then getPlayer():getStats():set(CharacterStat.ENDURANCE,mutation.endurance)end
    if case()=='missing-dumbbell'and getPlayer():getInventory():getItemById(mutation.removed)then return end
    command.mutationObserved=true;command.mutation=mutation;mutation=nil
   end
   observe()
   if idle>=10 then
    quiet=quiet or getTimestampMs()
    if getTimestampMs()-quiet>=2000 then phase='receipt';request('Verify')end
   else quiet=nil end
  elseif phase=='receipt'and receipt then finishCase()
  elseif phase=='isolation-ready'then
   assert(getTimestampMs()-since<45000,'native isolation server-ready deadline')
   if isolationAuthority then
    raw('ISOLATION_STARTED',F.beginNativeIsolation(state,isolationAuthority));phase='isolating';since=getTimestampMs();quiet=nil
   end
  elseif phase=='isolating'then
   if getTimestampMs()-since>=45000 then
    error('native isolation cleanup deadline; original failure retained')
   end
   assert(not O.active and #O.records==0 and not getPlayer():getFitness():getCurrentExe(),'native isolation started a workout')
   if empty()then
    quiet=quiet or getTimestampMs()
    if getTimestampMs()-quiet>=2000 then
     phase='isolation-verifying';since=getTimestampMs();isolationFinalAuthority=nil;request('IsolationReady')
    end
   else quiet=nil end
  elseif phase=='isolation-verifying'then
   assert(getTimestampMs()-since<45000,'native isolation final authority deadline')
   assert(not O.active and #O.records==0 and empty()and not getPlayer():getFitness():getCurrentExe(),'native isolation final boundary not idle')
   if isolationFinalAuthority then
    raw('ISOLATION_SETTLED',F.finishNativeIsolation(state,isolationFinalAuthority));phase='release';request('Next')
   end
  elseif phase=='released'then
   index=index+1
   if not case()then finish();return end
   ids,receipt,mutation,state,command,front,tail,requests,seen,ack,progressSeen,menuGate=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
   phase='prepare';since=getTimestampMs();idle=0;preparedInitialized=false;prepareLogged=nil
  end
 end)
 if not ok then
  if phase=='isolation-ready'or phase=='isolating'or phase=='isolation-verifying'then
   raw('ISOLATION_FAILED',{case=case(),actor='client1',mode='native',kind='mp',phase='failed',reason=tostring(problem),failedCaseRecorded=true})
  end
  print('[QUEUE_TEST] FAIL fitness client '..tostring(problem));emit({event='error',id=case(),reason=tostring(problem)});done=true
 end
end)
