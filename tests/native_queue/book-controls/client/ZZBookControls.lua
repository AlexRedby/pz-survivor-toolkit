require 'PZSurvivorToolkit/ActionQueuePanel'
require 'RadioCom/RadioWindowModules/RWMMergedTV'
require 'TimedActions/ISReadABook'
local F=require 'QueueBookControls';local JSON=require 'QueueHealthEvents';local config=require 'QueueTestSelection'
local T=PZSurvivorToolkit;local Proof=require 'PZSurvivorToolkit/SourceProof';local native=config.mode=='native'
local phase,index,since='prepare',1,0;local entered,ready,done=false,false,false
local state,previous,ids,authorityBaseline,authorityFinal,baseline,tracks,records,starts,boundary,front,tail,volume,equip,window
local oldNative,resume,quiet,failure,draining,tailSnapshot,volumeSnapshot,equipSnapshot
local capacityReceipt,capacityRequestedAt,blockedEvidence,failureUI,nativeDebtAbsent
local performance,tickSpacing,lastTick,transferEpisode,replicaGaps
local failures=0;local serial,tokenSerial=0,0;local tokens={};local classes={}
local producer,readProducer,volumeProducer,equipProducer
local function now()return getTimestampMs()end
local function case()return config.cases[index]end
local function control()return ids and F.parseControl(ids.control)end
local function capacityLost()if not ids then return false end;local _,lost=F.parseControl(ids.control);return lost end
local function favoriteWorld()if not ids then return false end;local _,_,favorite=F.parseControl(ids.control);return favorite end
local function favoriteUnmoved()return favoriteWorld()and not isClient()end
local function failedReturnExpected()return capacityLost()or favoriteUnmoved()end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()and getPlayer():getCharacterActions():isEmpty()end
local function raw(marker,value)print('[BOOK_CONTROLS] '..marker..' '..JSON.encode(value))end
local function emit(value)value.suite,value.kind,value.mode,value.actor='book-controls',config.kind,config.mode,'client1';JSON.emit(value)end
local function tokenID(token)
 if type(token)~='table'then return false end
 if not tokens[token]then tokenSerial=tokenSerial+1;tokens[token]=tokenSerial end;return tokens[token]
end
local function ref(value)return value and tostring(value)or false end
local function role(action)
 if not state or action.character~=state.player then return end
 local item=action.item
 if action.Type=='ISReadABook'and item then
  if item:getID()==ids.front.id then return 'front'elseif item:getID()==ids.tail.id then return 'tail'end
 elseif action.Type=='ISInventoryTransferAction'and item and item:getID()==ids.front.id then
  return action.destContainer==state.player:getInventory()and 'pickup'or 'return'
 elseif action.Type=='ISEquipWeaponAction'and item and item:getID()==ids.pen.id then return 'equip'
 elseif action.Type=='ISRadioAction'and action.device==state.tv and action.mode=='SetVolume'then return 'volume'end
 return 'preparation'
end
local function register(action)
 if not tracks or not state then return end
 if tracks[action]then return tracks[action]end
 if action.character~=state.player then return end
 local name=role(action);if not name then return end
 serial=serial+1
 local duration=action.maxTime
 if action.Type=='ISInventoryTransferAction'and action.queueList and action.queueList[1]then duration=action.queueList[1].time end
 local row={sequence=serial,role=name,type=action.Type,mode=action.mode or false,item=action.item and action.item:getID()or false,
  actionRef=ref(action),token=tokenID(action.toolkitQueueOperation),duration=duration,started=false,progress=false,finishes={},receipts={},
  nativeSource=true}
 -- Source checks are applied independently rather than relying on Lua's and/or value propagation.
 if name=='front'or name=='tail'then row.nativeSource=Proof.closure(ISReadABook.new,'ISReadABook.lua')end
 if name=='volume'then row.nativeSource=Proof.closure(ISRadioAction.new,'ISRadioAction.lua')end
 if name=='equip'then row.nativeSource=Proof.closure(ISEquipWeaponAction.new,'ISEquipWeaponAction.lua')end
 if type(duration)=='number'and duration>0 then row.durationBefore=action:adjustMaxTime(duration)end
 tracks[action]=row;records[#records+1]=row
 local class=getmetatable(action)
 if not classes[class]then local saved={};for _,method in ipairs({'new','getDuration','isValid','start','stop','update','perform','complete','animEvent'})do saved[method]=class[method]end;classes[class]=saved end
 return row
end
local function intact()
 assert(ISInventoryPaneContextMenu.onLiteratureItems==producer and ISInventoryPaneContextMenu.readItem==readProducer and RWMVolume.onVolumeChange==volumeProducer and ISInventoryPaneContextMenu.equipWeapon==equipProducer,'native producer callback changed after setup')
 assert(Proof.closure(producer,'ISInventoryPaneContextMenu.lua')and Proof.closure(readProducer,'ActionQueueOperations.lua')and Proof.closure(equipProducer,'ISInventoryPaneContextMenu.lua'),'native literature/equip producer source changed')
 assert(Proof.closure(ISReadABook.new,'ISReadABook.lua')and Proof.closure(ISReadABook.getDuration,'ISReadABook.lua')and Proof.closure(ISRadioAction.new,'ISRadioAction.lua'),'native constructors/timers replaced')
 for class,saved in pairs(classes)do for method,callback in pairs(saved)do assert(class[method]==callback,'native lifecycle changed '..tostring(class.Type)..'.'..method)end end
end
local function updateTransferEpisode(action,row)
 if not isClient()or row.type~='ISInventoryTransferAction'or(row.role~='pickup'and row.role~='return')then return end
 if transferEpisode and transferEpisode.action==action then transferEpisode.live=false end
 local tx=action.transactionId
 local root=state.player:getInventory();local from=row.role=='pickup'and state.source or root;local to=row.role=='pickup'and root or state.source
 if type(tx)=='number'and tx>0 and row.started and row.nativeRef and action.character==state.player and action.item
  and action.item:getID()==ids.front.id and action.item:getFullType()==ids.front.type and action.srcContainer==from and action.destContainer==to
  and action.action and ref(action.action)==row.nativeRef and queue().current==action then
  if transferEpisode and transferEpisode.action==action then assert(transferEpisode.transaction==tx,'live exact transfer transaction changed')else
   transferEpisode={case=case(),actor=ids.actor,itemId=ids.front.id,itemType=ids.front.type,source=ids.source,role=row.role,
    from=row.role=='pickup'and ids.source or'root',to=row.role=='pickup'and'root'or ids.source,
    sequence=row.sequence,transaction=tx,actionRef=row.actionRef,nativeRef=row.nativeRef,action=action,positive=true}
  end
  transferEpisode.live=true;transferEpisode.observedAt=now();transferEpisode.done=isItemTransactionDone(tx)==true;transferEpisode.rejected=isItemTransactionRejected(tx)==true
 end
end
-- The disposable Java probe calls this after the unchanged native stop returns,
-- while the Base.stop bridge flag still exists. OnTick would race its cleanup.
function bookControlsNativeStopped(action,episode,returned)
 if native or not state or not boundary or action~=front or episode~=oldNative then return end
 local row=assert(tracks[action]);assert(not row.stopReturned,'duplicate exact reader stop')
 intact()
 local q=queue()
 row.stopReturned={case=case(),actionRef=ref(action),nativeRef=ref(episode),item=action.item:getID(),at=now(),returned=returned,
  queueOwned=q.current==action and q.queue[1]==action and action.action==episode,
  nativePresent=state.player:getCharacterActions():contains(episode),bridgeStopped=q.toolkitCancel==action and q.toolkitCancelStopped==true,
  nativeSource=Proof.closure(ISReadABook.stop,'ISReadABook.lua')and T.ActionQueueLifecycle.hasNativeStopBridge()==true,
  finished=episode:finished(),forceComplete=episode:isForceComplete(),pages=action.item:getAlreadyReadPages()}
 raw('STOP_RETURNED',row.stopReturned)
end
local function observeStoppedRemoval()
 if native or not boundary or not oldNative or control()=='return-child-cancel'then return end
 local row=tracks[front];local q=queue()
 if not row.stoppedRemoval and q:indexOf(front)==-1 and not state.player:getCharacterActions():contains(oldNative)then
  row.stoppedRemoval={at=now(),actionRef=ref(front),nativeRef=ref(oldNative),sameNative=front.action==oldNative,item=front.item:getID(),pages=front.item:getAlreadyReadPages(),
   queueAbsent=true,nativeAbsent=true,finished=oldNative:finished(),forceComplete=oldNative:isForceComplete()}
 end
end
local function observe()
 local refreshed,diagnostic=F.refresh(state)
 if transferEpisode then
  local ep=transferEpisode;local row=tracks[ep.action]
  if row then updateTransferEpisode(ep.action,row)end
 end
 local status,gap=F.replicaBarrier(state,refreshed and nil or diagnostic,transferEpisode,now())
 if not status then raw('IDENTITY_FAILURE',{case=case(),diagnostic=diagnostic or false,reason=gap});error(gap)end
 if status=='wait'then
  for action,row in pairs(tracks)do if row.role~='pickup'and row.role~='return'and not row.started and(action.action or row.performedAt)then error('native start crossed replica gap without observed timing')end end
  if not gap.emitted then gap.emitted=true;raw('REPLICA_GAP',gap)end;return false end
 if status=='resolved'then gap.emitted=nil;replicaGaps[#replicaGaps+1]=gap;raw('REPLICA_CONVERGED',gap)end
 for _,action in ipairs(queue().queue)do register(action)end
 for action,row in pairs(tracks)do
  if not row.started and not action.action and row.duration and row.duration>0 then row.durationBefore=action:adjustMaxTime(row.duration)end
  if action.action and not row.effectiveDuration and queue():indexOf(action)~=-1 then
   row.nativeRef=ref(action.action);row.allocatedAt=now()
   if action.Type=='ISInventoryTransferAction'and isClient()then
    if action.transactionId and action.maxTime>0 then row.transactionDuration=getItemTransactionDuration(action.transactionId);row.effectiveDuration=action.maxTime end
   else row.durationAfter=action:adjustMaxTime(row.duration);row.effectiveDuration=action.maxTime end
  end
  if queue().current==action and action.action and action:isStarted()then
   if not row.started then
    row.started=true;row.startedAt=now();row.nativeRef=ref(action.action);starts[#starts+1]=row.sequence
    if row.role=='tail'then tailSnapshot=F.snapshot(state);raw('TAIL_STARTED',tailSnapshot)end
    if row.role=='equip'then equipSnapshot=F.snapshot(state);raw('EQUIP_STARTED',equipSnapshot)end
    if row.role=='volume'then volumeSnapshot=F.snapshot(state);raw('VOLUME_STARTED',volumeSnapshot)end
    if boundary and row.role=='front'and action~=front then
     assert(not resume,'duplicate resumed reader')
     resume={oldAction=ref(front),newAction=ref(action),oldNative=ref(oldNative),newNative=ref(action.action),
      item=action.item:getID(),token=tokenID(action.toolkitQueueOperation),startPage=action.startPage,
      pages=action.item:getAlreadyReadPages(),oldNativeAbsent=not state.player:getCharacterActions():contains(oldNative),at=now()}
     raw('RESUME',resume)
    end
   end
   local delta=action:getJobDelta();row.firstDelta=row.firstDelta or delta;row.maxDelta=math.max(row.maxDelta or delta,delta)
   row.progress=row.maxDelta>row.firstDelta+.00000001
  end
  if row.type=='ISInventoryTransferAction'and action.transactionId and action.transactionId~=0 then
   row.transaction=action.transactionId;row.transactionDone=isClient()and isItemTransactionDone(action.transactionId)==true or not isClient()
   row.transactionRejected=isClient()and isItemTransactionRejected(action.transactionId)==true or false
  end
 end
 for action,row in pairs(tracks)do updateTransferEpisode(action,row)end
 if boundary and oldNative and not state.player:getCharacterActions():contains(oldNative)then if not boundary.drained then boundary.drained=true;boundary.drainedAt=now();raw('DRAIN',{case=case(),reader=boundary.reader,native=boundary.native,at=boundary.drainedAt,oldNativeAbsent=true})end end
 observeStoppedRemoval();intact();return true
end
local function lifecycleBegin(action,step)
 local row=register(action)
 if row and step=='perform'and row.type=='ISInventoryTransferAction'and action.transactionId then
  row.transaction=action.transactionId;row.transactionDone=isClient()and isItemTransactionDone(action.transactionId)==true or not isClient()
  row.transactionRejected=isClient()and isItemTransactionRejected(action.transactionId)==true or false
 end
 return row~=nil
end
local function lifecycleFinish(action,step,succeeded)
 if transferEpisode and transferEpisode.action==action and(step=='perform'or step=='stop')then transferEpisode.live=false;transferEpisode.terminalAt=now();transferEpisode.observedAt=now();transferEpisode.done=isItemTransactionDone(transferEpisode.transaction)==true;transferEpisode.rejected=isItemTransactionRejected(transferEpisode.transaction)==true end
 local row=register(action);if row then row.finishes[#row.finishes+1]={phase=step,succeeded=succeeded,at=now()};if step=='perform'and succeeded then row.performedAt=now()end end
end
local function request(command)
 if isClient()then sendClientCommand('BookControlsTest',command,{case=case(),expected=command=='Verify'and F.snapshot(state)or false,requestedAt=capacityRequestedAt,acceptedAt=boundary and boundary.ui and boundary.ui.acceptedAt or false});return end
 if command=='Prepare'then state=F.prepare(getPlayer(),case(),previous);previous=nil;ids=state.ids;raw('PREPARED',ids)
 elseif command=='CapacityLost'then capacityReceipt=F.capacityLost(state,capacityRequestedAt,boundary.ui and boundary.ui.acceptedAt or false);raw('CAPACITY_LOST',capacityReceipt)
 elseif command=='Baseline'then authorityBaseline=F.snapshot(state);raw('BASELINE',authorityBaseline)
 elseif command=='Verify'then authorityFinal=F.snapshot(state);raw('VERIFIED',authorityFinal);F.restoreCapacity(state)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if done then return end
 if module=='BookControlsTest'then
  if command=='Prepared'then ids=args
  elseif command=='Baselined'then authorityBaseline=args
  elseif command=='CapacityLost'then capacityReceipt=args
  elseif command=='Verified'then authorityFinal=args
  elseif command=='Failed'then error(args.error)end
 elseif module=='PZSurvivorToolkitActions'and command=='State'and state and tracks then
  local found
  for action,row in pairs(tracks)do
   if action.toolkitNativeTransaction==args.transaction and action.toolkitNativeKind==args.kind and args.player==state.player:getOnlineID()
    and(action.toolkitNativeToken==nil or action.toolkitNativeToken==args.token)then
    assert(not found,'ambiguous book-controls native outcome');found=row
   end
  end
  if found then
   local receipt={case=case(),sequence=found.sequence,kind=args.kind,transaction=args.transaction,token=args.token,state=args.state,player=args.player,at=now()}
   found.receipts[#found.receipts+1]=receipt;raw('ACK',receipt)
  end
 end
end)
local function queueEvidence()
 local rows={}
 for _,action in ipairs(queue().queue)do local r=register(action);rows[#rows+1]={sequence=r.sequence,type=r.type,role=r.role,token=tokenID(action.toolkitQueueOperation),actionRef=ref(action),nativeRef=ref(action.action),current=queue().current==action}end
 return rows
end
local function enqueue()
 tracks,records,starts={},{},{};boundary,resume,quiet,failure,draining,tailSnapshot,volumeSnapshot,equipSnapshot=nil,nil,nil,nil,nil,nil,nil,nil
 capacityReceipt,capacityRequestedAt,blockedEvidence,failureUI,nativeDebtAbsent=nil,nil,nil,nil,nil
 performance,tickSpacing,lastTick,transferEpisode,replicaGaps=nil,{},now(),nil,{}
 baseline=F.snapshot(state);assert(F.same(baseline,ids.baseline)and F.same(authorityBaseline,baseline),'exact native baseline differs')
 assert(not state.player:hasTrait(CharacterTrait.DISORGANIZED),'native producer requires its normal return contract')
 assert(not state.player:isTimedActionInstant()and not state.player:hasTrait(CharacterTrait.ILLITERATE),'native reading actor unavailable')
 producer({state.front},state.player:getPlayerNum())
 for _,action in ipairs(queue().queue)do register(action);if role(action)=='front'then assert(not front,'duplicate original reader');front=action end end
 assert(front and front.item:getID()==ids.front.id,'native literature producer omitted exact reader')
 equipProducer(state.pen,true,false,state.player:getPlayerNum())
 for _,action in ipairs(queue().queue)do register(action);if role(action)=='equip'then assert(not equip,'duplicate equip setter');equip=action end end
 assert(equip and equip.item==state.pen and equip.primary and not equip.twoHands and equip.item:getContainer()==state.player:getInventory(),'native Pen equip admission differs')
 window=RWMMergedTV:new(-1000,-1000,300,100);window:initialise();window:instantiate();assert(window:readFromObject(state.player,state.tv,state.data,'IsoObject'))
 window.volumeBar.onVolumeChange(window,ids.targetVolume*window.volumeBar:getVolumeSteps())
 for _,action in ipairs(queue().queue)do register(action);if role(action)=='volume'then assert(not volume,'duplicate volume setter');volume=action end end
 assert(volume and volume.secondaryItem==ids.targetVolume and volume.deviceData==state.data and volume.maxTime==30,'native RWM volume admission differs')
 producer({state.tail},state.player:getPlayerNum())
 for _,action in ipairs(queue().queue)do register(action);if role(action)=='tail'then assert(not tail,'duplicate tail reader');tail=action end end
 assert(tail and queue().queue[#queue().queue]==tail,'native independent tail missing')
 raw('ADMISSION',{case=case(),producer='ISInventoryPaneContextMenu.onLiteratureItems/readItem',volumeProducer='RWMVolume.onVolumeChange',equipProducer='ISInventoryPaneContextMenu.equipWeapon',sourceBound=true,queue=queueEvidence()})
 phase='boundary'
end
local function diagnostic(decision,action)
 local contract,adapter=T.ActionQueuePolicy.inspect(action);local blocker=decision.blocker
 return {case=case(),source=ids.source,operation=tokenID(action.toolkitQueueOperation),action=ref(action),type=action.Type,
  reason=decision.reason or false,blocker=blocker and{action=ref(blocker),type=blocker.Type,operation=tokenID(blocker.toolkitQueueOperation),item=blocker.item and blocker.item:getID()or false}or false,
  adapter=adapter or false,resource=decision.resource and tostring(decision.resource)or false,first=decision.first or false,last=decision.last or false,
  contract={knownInputs=contract and contract.knownInputs==true or false,cancelOperation=contract and contract.cancelOperation or false,cancelWaiting=contract and contract.cancelWaiting or false},at=now()}
end
local function realGesture()
 local panel=T.ActionQueuePanel:new(80,80,460,640);panel.queue,panel.playerNum=queue(),state.player:getPlayerNum();panel:initialise();panel:addToUIManager();panel:update()
 local list=panel.list;list:setYScroll(0);assert(not list:isVScrollBarVisible(),'owned real queue panel must fit all rows')
 local function rowFor(action,header)
  for _,row in ipairs(list.items)do if row.item==action and(row.header==true)==header then return row end end
 end
 local grouped=rowFor(front,true)~=nil
 local keep=control()=='return-child-cancel'
 if (control()=='reader-child-cancel'or keep)and grouped then
  local row=assert(rowFor(front,true));local y=list:topOfItem(row.index)+row.height/2
  assert(list:rowUnderMouse(10,y)==row,'real expand hit target differs');list:onMouseDown(10,y);assert(list.pressedToggle==row.operation,'expand press failed');list:onMouseUp(10,y)
  assert(panel.expanded[row.operation],'expand release failed')
 end
 local targetAction=front
 if keep then
  targetAction=nil
  for _,action in ipairs(queue().queue)do
   if role(action)=='return'and action.toolkitQueueOperation==front.toolkitQueueOperation then assert(not targetAction,'ambiguous native pending return');targetAction=action end
  end
  assert(targetAction,'exact native pending return missing')
 end
 local target=assert(rowFor(targetAction,grouped and control()~='reader-child-cancel'and not keep),'real reader/header/return target missing')
 local whole=target.header==true;local moving=control()=='move-volume'or control()=='move-equip';local movingAction=control()=='move-equip'and equip or volume
 local decision=moving and T.ActionQueuePolicy.evaluateMove(queue(),movingAction,front,false)or T.ActionQueuePolicy.evaluateCancel(queue(),target.item,whole)
 local ui={source='ActionQueuePanel.List',input=moving and'programmatic-drag'or'programmatic-press-release',header=whole,singleton=not grouped,
  target=ref(target.item),operation=tokenID(target.operation),hitTested=true,decision=diagnostic(decision,moving and movingAction or target.item),at=now()}
 if moving then
  local from=rowFor(movingAction,false)or rowFor(movingAction,true)
  if not from then for _,row in ipairs(list.items)do if row.operation==movingAction.toolkitQueueOperation and row.header then from=row;break end end end
  assert(from,'real pending operation row missing');ui.movingAction=ref(movingAction);ui.movingAnchor=ref(from.item);ui.movingToken=tokenID(from.operation)
  local x,fromY=35,list:topOfItem(from.index)+from.height/2;local toY=list:topOfItem(target.index)+2
  assert(list:rowUnderMouse(x,fromY)==from and list:rowUnderMouse(x,toY)==target,'real drag hit targets differ')
  list:onMouseDown(x,fromY);ui.pressCaptured=list.dragAction==from.item
  -- The actual list onMouseMove reads native pointer coordinates. Use release's
  -- real hit testing with a captured programmatic drag; no pointer getter override.
  list.dragging=ui.pressCaptured and math.abs(fromY-toY)>5;ui.dragging=list.dragging==true
  list:onMouseUp(x,toY);ui.x,ui.fromY,ui.toY=x,fromY,toY
 else
  local x,y=list:cancelX()+12,list:topOfItem(target.index)+target.height/2
  assert(list:rowUnderMouse(x,y)==target,'real cancel hit target differs')
  list:onMouseDown(x,y);ui.pressCaptured=whole and list.pressedOperation~=nil or not whole and list.pressedCancel==target.item
  list:onMouseUp(x,y);ui.x,ui.y=x,y
 end
 ui.feedback=list.cancelFeedback and list.cancelFeedback.text or false;ui.gestureCleared=not list.pressedOperation and not list.pressedCancel and not list.dragAction
 if keep then
  ui.bodyContinues=queue().current==front and front.action==oldNative and queue().toolkitCancel==nil
  ui.returnAbsent=queue():indexOf(targetAction)==-1
  ui.bookRoot=F.snapshot(state).books.front.container=='root'
  ui.operationCancelled=front.toolkitQueueOperation.toolkitCancelled==true
  ui.accepted=ui.bodyContinues and ui.returnAbsent and ui.bookRoot and not ui.operationCancelled and ui.pressCaptured==true and not ui.feedback
 else ui.accepted=queue().toolkitCancel==front and front.action==oldNative and ui.pressCaptured==true and not ui.feedback end
 if ui.accepted then ui.acceptedAt=now()else raw('DENIED',ui.decision)end
 panel:removeFromUIManager();return ui
end
local function resetFailure(reason)
 failure=reason;draining={at=now(),natives={}}
 for _,action in ipairs(queue().queue)do if action.action then draining.natives[#draining.natives+1]=action.action end end
 ISTimedActionQueue.clear(state.player);raw('RESET',{case=case(),entrypoint='ISTimedActionQueue.clear',reason=reason,at=now()});phase='reset-drain'
end
-- Test-only observations of real read-only production entrypoints. The
-- millisecond clock is deliberately reported as coarse; no render/Host-contention
-- or full-queue regression claim follows from these tiny scenario timings.
local function performanceAtBoundary()
 local profileRequested=type(config.options)=='table'and config.options.profileCounts==true
 local liveProfile=profileRequested and PZSurvivorToolkitBookProfile or nil
 if profileRequested then
  assert(type(liveProfile)=='table','diagnostic source profiler not loaded')
  PZSurvivorToolkitBookProfileEnabled=true
 end
 local q=queue();local list=q.queue;local before=F.snapshot(state);local actions,originalSet={},{}
 local radioClass,radioConstructor=ISRadioAction,ISRadioAction.new
 for i,action in ipairs(list)do actions[i]={action=action,native=action.action,token=action.toolkitQueueOperation};originalSet[action]=true end
 local current,generation,cancel,groupCancel=q.current,q.toolkitOperationGeneration,q.toolkitCancel,q.toolkitGroupCancel
 local resumeIntent,outcomeWait,stopIntent=q.toolkitResume,q.toolkitOutcomeWait,q.toolkitStopIntent
 local panel=T.ActionQueuePanel:new(-1000,-1000,460,640)
 panel.queue,panel.playerNum=q,state.player:getPlayerNum();panel:initialise();panel:addToUIManager()
 local keep=control()=='return-child-cancel';local target=front
 if keep then for _,action in ipairs(list)do if role(action)=='return'and action.toolkitQueueOperation==front.toolkitQueueOperation then target=action;break end end end
 local whole=not keep and control()~='reader-child-cancel'and ids.source~='root'
 local moving=control()=='move-equip'and equip or volume
 local entries={
  {name='evaluateMove',kind='authoritative',call=function()return T.ActionQueuePolicy.evaluateMove(q,moving,front,false)end},
  {name='evaluateCancel',kind='authoritative',call=function()return T.ActionQueuePolicy.evaluateCancel(q,target,whole)end},
  {name='previewMove',kind='advisory',call=function()return T.ActionQueuePolicy.previewMove(q,moving,front,false)end},
  {name='previewCancel',kind='advisory',call=function()return T.ActionQueuePolicy.previewCancel(q,target,whole)end},
  {name='panelUpdate',kind='advisory',call=function()panel:update()end},
 }
 local function input(count,limits)
  return{case=case(),timer='getTimestampMs',units='ms',coarse=true,queueEnabled=not native,queueCount=count,warmup=3,samples=20,limits=limits,metrics={}}
 end
 local function measure(result)
  for _,entry in ipairs(entries)do
   if liveProfile then assert(liveProfile.start(tostring(result.queueCount)..'/'..entry.name),'diagnostic profiler opt-in rejected')end
   local decisionSamples,firstAllowed,firstReason,firstMode,lastAllowed,lastReason,lastMode=0,nil,nil,nil,nil,nil,nil
   local stable=true;local isDecision=entry.name~='panelUpdate'
   local function observe(decision)
    if not isDecision then return end
    assert(type(decision)=='table','read-only decision missing')
    local reason,mode=decision.reason,decision.mode
    assert(reason==nil or type(reason)=='string','nonscalar decision reason')
    assert(mode==nil or type(mode)=='string','nonscalar decision mode')
    local allowed
    if entry.kind=='authoritative'then allowed=decision.allowed;assert(type(allowed)=='boolean','authoritative allowed missing')
    else allowed=reason==nil end
    assert(allowed==(reason==nil),'decision permission/reason inconsistent')
    reason,mode=reason or false,mode or false
    if decisionSamples==0 then firstAllowed,firstReason,firstMode=allowed,reason,mode
    elseif firstAllowed~=allowed or firstReason~=reason or firstMode~=mode then stable=false end
    decisionSamples=decisionSamples+1;lastAllowed,lastReason,lastMode=allowed,reason,mode
   end
   local function sample()
    local started=now();local decision=entry.call();local elapsed=now()-started
    assert(elapsed>=0,'benchmark wall clock moved backwards')
    -- Scalar comparison is outside the timed call; authority snapshots and
    -- execution descriptors never survive this local observation.
    observe(decision);return elapsed
   end
   local row={name=entry.name,kind=entry.kind,firstUseMs=sample(),rawMs={}}
   for i=1,result.warmup do observe(entry.call())end
   for i=1,result.samples do row.rawMs[i]=sample()end
   if liveProfile then
    row.sourceProfile=liveProfile.stop();row.sourceProfile.entrypointCalls=1+result.warmup+result.samples
    row.sourceProfile.scope=result.queueCount==32 and'probe32'or'natural'
   end
   row.decisionSamples=decisionSamples;row.decisionStable=stable
   if isDecision then
    row.firstDecision={allowed=firstAllowed,reason=firstReason,mode=firstMode}
    row.lastDecision={allowed=lastAllowed,reason=lastReason,mode=lastMode}
    row.decisionClass=not stable and'unstable'or firstAllowed and'allowed'or'denied'
   else row.firstDecision=false;row.lastDecision=false;row.decisionClass='not-decision'end
   local sorted={};for i,value in ipairs(row.rawMs)do sorted[i]=value end;table.sort(sorted)
   row.p95Ms=sorted[math.ceil(#sorted*.95)];row.p99Ms=sorted[math.ceil(#sorted*.99)]
   row.p95BudgetMs=entry.kind=='authoritative'and 2 or 1;row.p99BudgetMs=entry.kind=='authoritative'and 4 or 2
   row.passed=row.p95Ms<=row.p95BudgetMs and row.p99Ms<=row.p99BudgetMs
   result.metrics[#result.metrics+1]=row
  end
  result.pathClass=native and'nativeoff-denial-baseline'or'toolkit-observed-decisions'
  result.authorityAllowed=true;local timingPassed=true
  for index,metric in ipairs(result.metrics)do
   if index<=2 and(metric.decisionClass~='allowed'or not metric.decisionStable)then result.authorityAllowed=false end
   if not metric.passed or not metric.decisionStable then timingPassed=false end
  end
  result.diagnosticProfile=liveProfile~=nil
  result.positiveTimingClaim=not liveProfile and not native and result.authorityAllowed and timingPassed
 end
 local private,privateSet={},{}
 local ok,problem=pcall(function()
  assert(#actions<=32,'fixture exceeds the supported32-member probe')
  performance=input(#actions,'First-use is first fixture call, not process-cold. Tiny real producer queue only; preview excludes hover cache/rendering; no baseline regression, weaker-client or Host contention qualification.')
  measure(performance)
  local probe=input(32,'Synchronous temporary constructor-input probe only, not32-step gameplay. No native enqueue, validity/start/effects or retention-intent publication; not128-borrowing or Host-contention qualification.')
  probe.source='fixture-temporary-native-constructors';probe.originalQueueCount=#actions
  probe.constructor='ISRadioAction.new';probe.nativeDuration=30;probe.nativeConstructorProof=Proof.closure(radioConstructor,'ISRadioAction.lua');probe.temporary={}
  assert(probe.nativeConstructorProof,'temporary constructor source changed')
  for index=#actions+1,32 do
   assert(ISRadioAction==radioClass and radioClass.new==radioConstructor,'native constructor binding changed')
   local action=radioConstructor(radioClass,'SetVolume',state.player,state.tv,.25)
   assert(not originalSet[action]and not privateSet[action],'constructor reused an existing action table');privateSet[action]=true
   assert(action.Type=='ISRadioAction'and action.character==state.player and action.device==state.tv and action.deviceData==state.data
    and action.mode=='SetVolume'and action.secondaryItem==.25 and action.maxTime==30 and not action.action and not action.started,'temporary native constructor changed')
   -- These private grouping tokens are diagnostic metadata only. Do not call
   -- Operations.run/add/enqueued or publish an execution/retention capability.
   action.toolkitQueueOperation={};private[#private+1]=action;list[index]=action
   probe.temporary[#probe.temporary+1]={actionRef=ref(action),type=action.Type,mode=action.mode,duration=action.maxTime,
    nativeRef=false,started=false,unexecuted=true,intentPublished=false}
  end
  measure(probe);performance.probe32=probe
 end)
 if liveProfile and liveProfile.active then liveProfile.stop()end
 -- This suffix is never handed to a native queue tick: restore synchronously,
 -- even if construction/inspection/projection failed, without replacing tables.
 local unexecuted=true
 for _,action in ipairs(private)do if action.action or action.started then unexecuted=false end end
 for index=#actions+1,32 do list[index]=nil end
 panel:removeFromUIManager()
 assert(q.queue==list and q.current==current and q.toolkitOperationGeneration==generation and q.toolkitCancel==cancel and q.toolkitGroupCancel==groupCancel
  and q.toolkitResume==resumeIntent and q.toolkitOutcomeWait==outcomeWait and q.toolkitStopIntent==stopIntent and #list==#actions,'profiling changed queue ownership/intent')
 for i,entry in ipairs(actions)do assert(list[i]==entry.action and entry.action.action==entry.native and entry.action.toolkitQueueOperation==entry.token,'profiling changed an original action/native/operation')end
 assert(unexecuted,'temporary constructor acquired a native execution')
 assert(ISRadioAction==radioClass and radioClass.new==radioConstructor,'profiling changed native constructor identity')
 assert(F.same(before,F.snapshot(state)),'profiling changed item/equipment/page effects')
 assert(ok,tostring(problem))
 performance.readOnly=true;performance.probe32.readOnly=true
 performance.probe32.restored=true;performance.probe32.queueIdentityUnchanged=true;performance.probe32.originalStateUnchanged=true
 raw('PERFORMANCE',performance)
end
local function atBoundary()
 local record=tracks[front]
 if queue().current~=front or not record.started or not record.progress then return end
 local actual=F.snapshot(state)
 if actual.books.front.pages<=ids.front.initial or actual.books.front.pages>=ids.front.total then return end
 performanceAtBoundary()
 -- A paid native page leaves one unread page: a precise stop/resume checkpoint.
 oldNative=front.action
 boundary={case=case(),at=now(),before=actual,reader=ref(front),native=ref(oldNative),token=tokenID(front.toolkitQueueOperation),
  nativeCheckpoint={finished=oldNative:finished(),forceComplete=oldNative:isForceComplete()},
  delta=front:getJobDelta(),tailRetained=queue():indexOf(tail)~=-1,volumePending=not volume.action,equipPending=not equip.action,requested=not native,drained=false,queue=queueEvidence()}
 assert(boundary.tailRetained and boundary.volumePending and boundary.equipPending,'independent work started before reader edit boundary')
 if native then
  boundary.ui=false;raw('BOUNDARY',boundary)
  if capacityLost()then capacityRequestedAt=now();request('CapacityLost')end
  phase='drain';return
 end
 boundary.ui=realGesture();raw('BOUNDARY',boundary)
 if not boundary.ui.accepted then resetFailure('real panel control denied: '..tostring(boundary.ui.decision.reason));return end
 assert(queue():indexOf(tail)~=-1,'real UI edit discarded independent tail')
 if capacityLost()then capacityRequestedAt=now();request('CapacityLost')end
 phase='drain'
end
local function keepBlocked()
 local execution=assert(T.ActionQueueExecution,'execution failure API missing')
 local info=execution.blockedReturnInfo(state.player);if not info or info.count==0 then return false end
 local entries=execution.blockedReturns(state.player);local entry
 for _,value in ipairs(entries)do if value.itemId==ids.front.id and value.itemType==ids.front.type then assert(not entry,'duplicate exact failed return');entry=value end end
 if not entry then return false end
 blockedEvidence=entry
 if favoriteUnmoved()then assert(entry.reason=='unmoved','favorite refusal must be actual native no-effect, not an unrelated admission failure')end
 assert(entry.state=='blocked'and(entry.reason=='admission'or entry.reason=='server'or entry.reason=='unmoved'),'failed return has no live blocked state')
 T.ActionQueuePanel.refresh()
 local windows=UIManager.getUI();local panel
 for i=0,windows:size()-1 do local element=windows:get(i);local view=element and element.getTable and element:getTable()
  if type(view)=='table'and getmetatable(view)==T.ActionQueuePanel and view.queue==queue()and view:getIsVisible()then panel=view;break end
 end
 local function rejectedFooter(reason)
  failureUI={case=case(),id=entry.id,itemId=entry.itemId,visible=false,reason=reason,at=now()}
  raw('BLOCKED_RETURN',{case=case(),entry=entry});raw('FAILURE_UI',failureUI)
  assert(execution.keepReturn(state.player,entry.id),'failed fixture footer could not safely clean its owned debt')
  resetFailure(reason);return false
 end
 if not panel then return rejectedFooter('idle failed return did not retain its actual queue window')end
 panel:update()
 if not panel.keepReturnButton or not panel.keepReturnButton:getIsVisible()then return rejectedFooter('actual failed-return footer missing')end
 for i=1,info.count do
  local selected=panel.returnEntries and panel.returnEntries[panel.returnIndex or 1]
  if selected and selected.id==entry.id then break end
  panel:nextFailedReturn()
 end
 local selected=assert(panel.returnEntries[panel.returnIndex or 1]);assert(selected.id==entry.id,'footer selected the wrong obligation')
 local button=panel.keepReturnButton
 failureUI={case=case(),source='ActionQueuePanel.KeepReturn',input='programmatic-press-callback',id=entry.id,itemId=entry.itemId,revision=info.revision,count=info.count,
  visible=panel:getIsVisible()and button:getIsVisible(),idle=empty(),bookRoot=F.snapshot(state).books.front.container=='root',at=now()}
 button:onMouseDown(1,1);failureUI.pressCaptured=button.returnId==entry.id
 panel:keepFailedReturn(button)
 local after=execution.blockedReturnInfo(state.player)
 failureUI.cleared=not after or after.count==0;failureUI.bookRetained=F.snapshot(state).books.front.container=='root'
 if not(failureUI.pressCaptured and failureUI.cleared and failureUI.bookRetained)then return rejectedFooter('actual Keep footer did not waive only the exact optional return')end
 raw('BLOCKED_RETURN',{case=case(),entry=blockedEvidence});raw('FAILURE_UI',failureUI);return true
end
local function finish()
 local actual=F.snapshot(state)
 assert(not state.replicaGap,'unresolved exact transfer replica gap at final verification')
 if not failure and performance then
  for _,result in ipairs({performance,performance.probe32})do for _,metric in ipairs(result.metrics)do if not metric.passed then failure='frozen timing budget exceeded: '..result.queueCount..'/'..metric.name;break end
   if not metric.decisionStable then failure='unstable read-only decision: '..result.queueCount..'/'..metric.name;break end end end
 end
 if not failure then
  local expected=F.expected(state,boundary,native)
  if not F.same(actual,expected)or not F.same(authorityFinal,expected)then failure='native final effect/inventory/Pen intent differs from exact requested result' end
 end
 if not failure and not native and performance and not performance.probe32.authorityAllowed then failure='Toolkit32 intended edit denied; no positive performance claim'end
 local passed=not failure
 local row={event='case',id=case(),status=passed and'passed'or'failed',reason=failure or false,ids=ids,baseline=baseline,authorityBaseline=authorityBaseline,
  boundary=boundary,records=records,starts=starts,resume=resume or false,tailSnapshot=tailSnapshot or false,volumeSnapshot=volumeSnapshot or false,equipSnapshot=equipSnapshot or false,
  client=actual,server=authorityFinal,performance=performance or false,replicaGaps=replicaGaps or{},finishedAt=now(),tickSpacingMs=tickSpacing or {},capacity=capacityReceipt or false,nativeDebtAbsent=nativeDebtAbsent,blockedReturn=blockedEvidence or false,failureUI=failureUI or false,nativeMethodsUnchanged=true,reset=draining and{entrypoint='ISTimedActionQueue.clear',drained=true,at=draining.at}or false}
 if failedReturnExpected()then row.returnSucceeded=false end
 emit(row);if not passed then failures=failures+1 end
 if not isClient()then previous=state end
 local completedPlayer,completedPen=state.player,state.pen
 state,ids,front,tail,volume,equip,window,oldNative,authorityBaseline,authorityFinal=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
 index=index+1;phase='between-cases';since=now()
 if case()then
  -- Clear the completed explicit equip through the real native producer before
  -- authority seeds the next empty-hands baseline. No replica hand repair.
  raw('BETWEEN_CASE_UNEQUIP',{item=completedPen:getID(),producer='ISInventoryPaneContextMenu.onUnEquip',at=now()})
  ISInventoryPaneContextMenu.onUnEquip({completedPen},completedPlayer:getPlayerNum())
 end
 if not case()then
  emit({event='complete',cases=config.cases,performed=#config.cases,skipped=0,failed=failures});raw('COMPLETE',{cases=config.cases,failed=failures});done=true
  if failures>0 then print('[QUEUE_TEST] FAIL book-controls '..failures..' failed cases across complete bank')end
 end
end
Events.OnGameStart.Add(function()entered=true;since=now()end)
Events.OnTick.Add(function()
 if not entered or done then return end
 local ok,problem=pcall(function()
  local player=getPlayer();if not isIngameState()or not player or not player:getCurrentSquare()then return end
  if not ready then
   if isClient()~=(config.kind=='mp')or isClient()and player:getUsername()~='client1'then return end
   assert(T.ActionQueueOperations.installVolumeProducer(),'source-bound native RWM producer unavailable');producer,readProducer,volumeProducer,equipProducer=ISInventoryPaneContextMenu.onLiteratureItems,ISInventoryPaneContextMenu.readItem,RWMVolume.onVolumeChange,ISInventoryPaneContextMenu.equipWeapon
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(not native)
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);player:setAutoDrink(false)
   assert(T.ActionQueueLifecycle.registerObserver('fixture.book-controls',{started=register,begin=lifecycleBegin,finish=lifecycleFinish}),'read-only native observer missing')
   ready=true;emit({event='setup',cases=config.cases,queueEnabled=not native,nativeDurations=true,sourceBound=true,authorityEquipment=true})
  end
  local elapsed=now()-since
  if elapsed>180000 and(phase=='boundary'or phase=='drain')then resetFailure('native functional timeout '..phase);since=now()
  else assert(elapsed<200000,'book controls setup/identity/drain timeout '..tostring(case())..' '..phase)end
  if state and tracks then
   local tick=now();if lastTick and #tickSpacing<60 then assert(tick>=lastTick,"fixture tick clock moved backwards");tickSpacing[#tickSpacing+1]=tick-lastTick end;lastTick=tick
   if not observe()then return end
  end
  if phase=='between-cases'then if empty()then phase='prepare'end
  elseif phase=='prepare'then assert(empty(),'fresh case requires drained native queue');tracks=nil;phase='prepared';request('Prepare')
  elseif phase=='prepared'and ids then
   if not state then state=F.resolve(player,ids);if not state then return end end
   if player:isPlayerMoving()or player:tooDarkToRead()then return end
   phase='baseline';request('Baseline')
  elseif phase=='baseline'and authorityBaseline then enqueue()
  elseif phase=='boundary'then atBoundary()
  elseif phase=='reset-drain'then
   if not empty()then return end
   for _,value in ipairs(draining.natives)do assert(not player:getCharacterActions():contains(value),'failed-case native allocation escaped reset')end
   phase='verify';request('Verify')
  elseif phase=='drain'then
   if not empty()then quiet=nil;return end
   quiet=quiet or now();if now()-quiet<1500 then return end
   if failedReturnExpected()then
    if capacityLost()and not capacityReceipt then return end
    if not native and not failureUI and not keepBlocked()then return end
    if native then
     local execution=T.ActionQueueExecution;local info=execution and execution.blockedReturnInfo(state.player)
     nativeDebtAbsent=not info or info.count==0
     assert(nativeDebtAbsent,'queue-off control acquired an execution return obligation')
    end
   end
   phase='verify';request('Verify')
  elseif phase=='verify'and authorityFinal then finish()end
 end)
 if not ok then
  emit({event='fatal',id=case(),status='failed',reason=tostring(problem),phase=phase,ids=ids or false,records=records or{}})
  print('[QUEUE_TEST] FAIL book-controls setup/identity '..tostring(problem));done=true
 end
end)
