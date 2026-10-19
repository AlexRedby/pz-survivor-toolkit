require 'PZSurvivorToolkit/ActionQueuePanel'
require 'ISUI/ISFitnessUI'
require 'Definitions/FitnessExercises'
require 'TimedActions/ISFitnessAction'
local F=require 'QueueFitnessFixture'
local O=require 'QueueFitnessObservation'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local native=config.mode=='native'
local T=PZSurvivorToolkit
local API,Ops=T.ActionQueue,T.ActionQueueOperations
local state,authority,previous,ids,receipt,mutation,command,ui,front,tail,requests,seen,ack,progressSeen,menuGate
local started,done,phase,index,failed,since,quiet,idle=false,false,'prepare',1,0,0,nil,0
local peerCase,peerBook,peerComplete,actor
local ready,setupSince=false,0
local peersReady,peersReceipt=false,nil
local function case()return config.cases[index]end
local function exerciseForCase(id)return (id=='missing-dumbbell'or id=='closed-ui-restore')and 'bicepscurl'or 'squats'end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function emit(row)
 row.suite,row.kind,row.mode,row.actor='fitness',config.kind,config.mode,actor;JSON.emit(row)
end
local function raw(marker,row)print('[FITNESS_TEST] '..marker..' '..JSON.encode(row))end
local function run(fn,...)
 if native then return fn(...)end
 return Ops.run(fn,...)
end
local function read(book)
 local before=#queue().queue;run(ISInventoryPaneContextMenu.onLiteratureItems,{book},getPlayer():getPlayerNum())
 local action=assert(queue().queue[before+1],'native fitness reader not queued')
 assert(action.Type=='ISReadABook'and action.item==book and action.minutesPerPage==2,'reader native duration differs')
 return action
end
local function finish()
 emit({event='complete',cases=config.cases,expected=#config.cases,performed=index-1,failed=failed,skipped=0})
 print('[FITNESS_TEST] COMPLETE');done=true
end
local function request(name)
 if isClient()then sendClientCommand('FitnessQueueTest',name,{case=case(),clientQuiescent=empty(),failedCaseRecorded=state and state.failedCaseRecorded==true});return end
 if name=='Prepare'then
  authority=F.prepare(getPlayer(),case(),previous);previous=nil;ids=authority.ids;raw('PREPARED',ids)
 elseif name=='Mutate'then mutation=F.mutate(authority);raw('MUTATED',mutation)
 elseif name=='Verify'then receipt=F.receipt(authority);receipt.serverSettleMilliseconds=getTimestampMs()-quiet;raw('VERIFIED',receipt);authority.verified=true
 elseif name=='Next'then F.releaseEquipment(authority);previous=authority;authority=nil;phase='released'end
end
Events.OnServerCommand.Add(function(module,name,value)
 if module~='FitnessQueueTest'then return end
 if name=='Failed'then
  print('[QUEUE_TEST] FAIL fitness authority '..tostring(value and value.error))
  emit({event='error',id=case(),reason=tostring(value and value.error)});done=true;return
 end
 if name=='Prepared'then ids=value elseif name=='Verified'then receipt=value elseif name=='Mutated'then mutation=value
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
 for _,kind in ipairs({'ISFitnessAction','ISQueueActionsAction','ISUnequipAction','ISEquipWeaponAction','ISInventoryTransferAction','ISWearClothing'})do
  local class=_G[kind];local methods={}
  for _,name in ipairs({'new','start','perform','complete'})do methods[name]=closure(class and class[name])end
  callbacks[kind]=methods
 end
 raw('REQUEST_REJECTED',{case=case(),exercise=exercise,children=children,callbacks=callbacks})
end
local function enqueue(exercise)
 ui.selectedExe=exercise;ui:selectedNewExercise();ui:updateButtons(queue().queue[1])
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
 if not native then
  local managed=T.ActionQueueFitness.isManaged(requestAction)and requestAction.toolkitFitnessExercise==exercise
   and requestAction.toolkitFitnessMinutes==10
  if not managed then rejectedRequest(exercise,before+1,#queue().queue);error('fitness command did not snapshot menu parameters')end
 end
 return first,requestAction
end
local function dispatch()
 local id=case();requests,seen,ack,progressSeen={},{},{},{}
 command={menuDispatched=true,nativeDurations=true,minutes=10,frontMinutes=(id=='empty'or id=='active-cancel')and 0 or 12,
  waitingNoExercise=true,waitingNoClinicalEffects=true,activeObserved=false,activeCancelled=false,pendingCancelled=false,
  reordered=false,closedUI=false,startedOrder={},activeAcks={},terminalAcks={},progressSamples={},queueDrained=false}
 if id~='empty'and id~='active-cancel'then front=read(state.items.front)end
 local first=enqueue(exerciseForCase(id))
 if id=='sequential'then enqueue('pushups')end
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
 if case()=='closed-ui-restore'and current and current.Type=='ISInventoryTransferAction'and current.item
  and current.item:getID()==state.ids.items.dumbbell and current.srcContainer==state.items.bag:getItemContainer()
  and current.destContainer==player:getInventory()and current:isStarted()and current:getJobDelta()>0 then
  command.borrowedTransferProgress=true;command.borrowedTool=state.ids.items.dumbbell
  command.borrowedSourceBag=state.ids.items.bag
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
   assert(current.timeToExe==10 and current.getDuration==ISFitnessAction.getDuration and current:getDuration()==5000000,'native fitness duration modified')
  end
  if not native and not progressSeen[current]then
   local progress=T.ActionQueueFitness.progress(current)
   if progress and progress.fraction>0 then
    local sampleMS=O.clock();local expected=math.max(0,math.min(10,(sampleMS-current.startMS)/60000))
    assert(progress.total==10 and progress.elapsed>0 and progress.elapsed<=10 and progress.fraction<=1
     and math.abs(progress.elapsed-expected)<.000001 and math.abs(progress.fraction-progress.elapsed/10)<.000001,
     'fitness displayed progress differs from selected native time')
    local description=T.ActionQueueFitness.describe(current)
    assert(description and type(description.target)=='string'and description.target~='','fitness progress label missing')
    command.progressSamples[#command.progressSamples+1]={exercise=current.exeDataType,total=progress.total,
     elapsed=progress.elapsed,fraction=progress.fraction,startMS=current.startMS,sampleMS=sampleMS,label=description.target}
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
  if case()=='active-cancel'and not command.activeCancelled then
   command.activeSince=command.activeSince or getTimestampMs()
   local repObserved=isClient()and (command.authoritativeReps or 0)>0 or not isClient()and current.repnb>0
   if repObserved and getTimestampMs()-command.activeSince>=3500 and (not isClient()or native or ack[current])then
    if native then ui:onClick(ui.cancel)else assert(API.cancelOperation(queue(),current),'active fitness cancellation rejected')end
    command.activeCancelled=true
   end
  end
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
 command.clientCurrentExerciseCleared=not getPlayer():getFitness():getCurrentExe()
 local problem
 if not receipt.tailRead then problem='independent-tail-not-preserved'
 elseif not receipt.serverStopSettled or not receipt.currentExerciseCleared then problem='native-fitness-stop-not-settled'end
 emit({event='case',id=case(),status=problem and 'failed'or 'passed',reason=problem,command=command,receipt=receipt})
 if problem then failed=failed+1 end
 if ui then ui:onClick(ui.close);ui=nil end
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
  idle=empty()and idle+1 or 0
  if phase=='prepare'then
   if idle<10 or getPlayer():tooDarkToRead()then return end
   phase='prepared';request('Prepare')
  elseif phase=='prepared'and ids then
   if not state then
    state=F.resolve(getPlayer(),ids);if not state then return end
    -- Initial fixture state is applied once. Cached native Moodles catch up on
    -- later ticks; never force-enable OK or repeatedly reset clinical values.
    for name,pages in pairs({front=6,tail=1})do local book=state.items[name]
     book:setAlreadyReadPages(book:getNumberOfPages()-pages);getPlayer():setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-pages)
    end
    getPlayer():getStats():set(CharacterStat.ENDURANCE,1);getPlayer():getStats():set(CharacterStat.FATIGUE,0)
   end
   if case()=='closed-ui-restore'and (getPlayer():getPrimaryHandItem()~=state.items.hammer
    or getPlayer():getSecondaryHandItem()~=state.items.screwdriver or getPlayer():getWornItem(state.items.bag:canBeEquipped())~=state.items.bag)then return end
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
  elseif phase=='released'then
   index=index+1
   if not case()then finish();return end
   ids,receipt,mutation,state,command,front,tail,requests,seen,ack,progressSeen,menuGate=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
   phase='prepare';since=getTimestampMs();idle=0
  end
 end)
 if not ok then
  print('[QUEUE_TEST] FAIL fitness client '..tostring(problem));emit({event='error',id=case(),reason=tostring(problem)});done=true
 end
end)
