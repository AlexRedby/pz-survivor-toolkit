require'PZSurvivorToolkit/ActionQueuePanel'
require'TimedActions/ISReadABook'
local F=require'QueueCleanupCancel';local JSON=require'QueueHealthEvents';local config=require'QueueTestSelection'
local T=PZSurvivorToolkit;local native=config.mode=='native'
local phase,index,since='prepare',1,0
local entered,ready,done=false,false,false
local state,ids,baseline,checkpoint,final,records,byAction,cancelEvidence,tailSnapshot,quiet,tail,body,prep
local bodyTerminal,idleEvidence
local resolveLast,resolveSeen=nil,{}
local authorityStart,baselineRequested
local serial=0;local tokenSerial=0;local tokenIds={};local classes={};local completedStates={}
local function case()return config.cases[index]end
local function now()return getTimestampMs()end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function raw(event,value)print('[QUEUE_CLEANUP] '..event..' '..JSON.encode(value))end
local function resolveWait(diagnostic)
 resolveLast=diagnostic or{case=case(),reason='resolve returned no detail'}
 local encoded=JSON.encode(resolveLast)
 if not resolveSeen[encoded]then resolveSeen[encoded]=true;raw('RESOLVE_WAIT',resolveLast)end
end
local function emit(value)value.suite,value.kind,value.mode,value.actor='cleanup-cancel',config.kind,config.mode,'client1';JSON.emit(value)end
local function itemID(action)return action.item and action.item:getID()or action.gun and action.gun:getID()or false end
local function classify(action)
 if not state or action.character~=state.player then return end
 if action==tail then return'tail'end
 if action.Type=='ISEatFoodAction'and F.itemMatches(state,'food',action.item)then body=action;return'body'end
 if action.Type=='ISReadABook'and F.itemMatches(state,'borrowed',action.item)then body=action;return'body'end
 if state.mask and F.itemMatches(state,'mask',action.item)then
  if action.Type=='ISUnequipAction'then prep=action;return'prepare'end
  if action.Type=='ISWearClothing'then return'cleanup'end
 end
 if state.borrowed and F.itemMatches(state,'borrowed',action.item)then
  if action.Type=='ISInventoryTransferAction'then
   if F.sourceMatches(state,action.srcContainer)and action.destContainer==state.player:getInventory()then prep=action;return'prepare'end
   if action.srcContainer==state.player:getInventory()and F.sourceMatches(state,action.destContainer) then return'cleanup'end
  end
 end
end
local function tokenId(token)
 if type(token)~='table'then return false end
 if not tokenIds[token]then tokenSerial=tokenSerial+1;tokenIds[token]=tokenSerial end
 return tokenIds[token]
end
local function register(action)
 if not action then return end
 local row=byAction[action]
 if row then
  assert(itemID(action)==row.item and action.item:getFullType()==row.itemType,'registered native action changed exact item identity')
  return row -- preserve the exact Lua action's paired callbacks across native item replica replacement
 end
 local role=classify(action);if not role then return end
 if not row then
  local duration=F.constructorDuration(action)
  serial=serial+1;row={sequence=serial,role=role,type=action.Type,item=itemID(action),itemType=action.item:getFullType(),actionRef=tostring(action),duration=duration,
   finishes={},started=false,progress=false,transaction=false,uuid=false,receipts={},nativeMethods=true,token=tokenId(action.toolkitQueueOperation),durationBefore=action:adjustMaxTime(duration)}
  records[#records+1]=row;byAction[action]=row
  local class=getmetatable(action);local saved=classes[class]
  if not saved then saved={};for _,name in ipairs({'new','start','stop','update','perform','complete','getDuration','isValid','waitToStart','animEvent'})do saved[name]=class[name]end;classes[class]=saved end
 end
 return row
end
local function intact()
 for class,saved in pairs(classes)do for name,callback in pairs(saved)do assert(class[name]==callback,'native lifecycle changed '..class.Type..'.'..name)end end
end
local function snapshot()return F.snapshot(state)end
local function recordBegin(action,step)
 local row=register(action);if not row then return end
 if step=='perform'and action.Type=='ISInventoryTransferAction'and action.transactionId then
  row.transaction=action.transactionId
  row.transactionDone=isClient()and isItemTransactionDone(action.transactionId)==true or not isClient()
  row.transactionRejected=isClient()and isItemTransactionRejected(action.transactionId)==true or false
 end
 return true -- pair this read-only begin observation with the real native finish
end
local function recordFinish(action,step,succeeded)
 local row=register(action);if not row then return end
 row.finishes[#row.finishes+1]={phase=step,succeeded=succeeded,at=now()}
 if step=='perform'and succeeded then row.performedAt=now()end
end
local function duration(action,row)
 if row.performedAt then return end -- stock transfers reset maxTime during their completed loop
 if row.type=='ISInventoryTransferAction'and isClient()then
  assert(row.duration==-1,'Host transfer constructor must retain native transaction duration')
  if action.transactionId and action.transactionId~=0 and action.maxTime>0 then
   local expected=getItemTransactionDuration(action.transactionId)
   assert(expected>0 and math.abs(action.maxTime-expected)<.001,'Host transfer changed native transaction duration')
   row.transactionDuration=expected;row.effectiveDuration=action.maxTime
  end
 elseif not action.action then row.durationBefore=action:adjustMaxTime(row.duration)
 elseif not row.effectiveDuration then
  local after=action:adjustMaxTime(row.duration);local before=row.durationBefore
  assert(before>1 and after>1 and math.abs(before-after)<=math.max(.001,row.duration*.00001),'native duration bracket changed')
  assert(action.maxTime>=math.min(before,after)-.001 and action.maxTime<=math.max(before,after)+.001,'native duration allocation differs')
  row.durationAfter=after;row.effectiveDuration=action.maxTime
 else assert(math.abs(action.maxTime-row.effectiveDuration)<.001,'allocated native duration changed')end
end
local function observe()
 local ready,detail=F.refresh(state);if not ready then resolveWait(detail);return false end
 for _,action in ipairs(queue().queue)do local row=register(action);if row then duration(action,row)end end
 local action=queue().current;local row=register(action)
 if row and action.action and action:isStarted()then
  if row.started then assert(tostring(action.action)==row.nativeRef,'native action instance changed while running')end
  if not row.started then
   row.started=true;row.startedAt=now();row.nativeRef=tostring(action.action)
   if action==tail then
    tailSnapshot=snapshot();raw('TAIL_STARTED',tailSnapshot)
    if not native then assert(F.ownedCleanupBeforeTail(state,tailSnapshot),'earned native cleanup did not precede the independent tail')end
   end
  end
  local progress=action:getJobDelta()
  if row.role=='body'and state.borrowed then
   row.readStartProgress=row.readStartProgress or progress
   row.readMaxProgress=math.max(row.readMaxProgress or progress,progress)
   row.progress=row.readMaxProgress>row.readStartProgress+.00000001
  elseif progress>0 then row.progress=true end
  local receipt=T.ActionQueueAcknowledgements.capture(action)
  if receipt then row.transaction=receipt.transaction;row.uuid=receipt.token;row.receiptState=receipt.state end
 end
 if state.borrowed and body and byAction[body]and byAction[body].started and not bodyTerminal and queue():indexOf(body)==-1 then
  bodyTerminal=snapshot();raw('BODY_SETTLED',bodyTerminal)
 end
 intact()
end
local function request(command)
 if isClient()then sendClientCommand('QueueCleanupCancelTest',command,{case=case()});return end
 if command=='Prepare'then state=F.prepare(getPlayer(),case());ids=state.ids;raw('PREPARED',ids);authorityStart=snapshot();raw('BASELINE_CONFIRMED',authorityStart)
 elseif command=='Checkpoint'then checkpoint=snapshot();raw('CHECKPOINT',checkpoint)
 elseif command=='Verify'then final=snapshot();raw('VERIFY',final)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if done then return end
 if module=='QueueCleanupCancelTest'then
  if command=='Prepared'then ids=args
  elseif command=='Baselined'then authorityStart=args
  elseif command=='BaselineWaiting'then resolveWait(args)
  elseif command=='Checkpointd'then checkpoint=args
  elseif command=='Verifyd'then final=args
  elseif command=='Failed'then error(args.error)end
 elseif module=='PZSurvivorToolkitActions'and command=='State'and state then
  for _,action in ipairs(queue().queue)do register(action)end
  local matched,matchedAction
  for action,row in pairs(byAction)do
   if action.toolkitNativeTransaction==args.transaction and action.toolkitNativeKind==args.kind and args.player==state.player:getOnlineID()
    and(action.toolkitNativeToken==nil or action.toolkitNativeToken==args.token)then
    assert(not matched,'ambiguous native cleanup receipt');matched,matchedAction=row,action
   end
  end
  if matched then
   matched.nativeRef=matched.nativeRef or(matchedAction.action and tostring(matchedAction.action)or false)
   local receipt={case=case(),state=args.state,transaction=args.transaction,kind=args.kind,token=args.token,player=args.player,at=now(),actionRef=matched.actionRef,nativeRef=matched.nativeRef}
   matched.receipts[#matched.receipts+1]=receipt;raw('NATIVE_STATE',receipt)
   if args.state=='completed'then completedStates[matched]=true end
  end
 end
end)
local function enqueue()
 records,byAction,cancelEvidence,tailSnapshot,completedStates={}, {},nil,nil,{}
 state.keepReturn=case()=='p4-keep-return'and not native
 baseline=snapshot();assert(authorityStart and not F.baselineDifference(state,baseline),'exact local/authority baseline required');raw('BASELINE',baseline)
 assert(not state.player:isTimedActionInstant(),'native actions must keep their duration')
 local run=T.ActionQueueOperations.run
 if state.mask then
  assert(ISInventoryPaneContextMenu.getEatingMask(state.player,false)==state.mask,'exact native mask selector changed')
  run(T.BulkFood.queueOne,{state.food},.25,state.player:getPlayerNum())
 else
  assert(getActivatedMods():contains('P4TidyUpMeister'),'P4 return integration missing')
  assert(state.borrowed:getContainer()==state.source and state.player:getPrimaryHandItem()==state.torch,'native borrow baseline differs')
  assert(not state.player:hasTrait(CharacterTrait.DISORGANIZED),'native borrowed read return requires an organized actor')
  -- Exact native signature: onLiteratureItems(items, playerIndex); its readItem
  -- owns pickup, ISReadABook and allowMissing native return.
  run(ISInventoryPaneContextMenu.onLiteratureItems,{state.borrowed},state.player:getPlayerNum())
 end
 tail=ISReadABook:new(state.player,state.book);ISTimedActionQueue.add(tail)
 for _,action in ipairs(queue().queue)do register(action)end
 assert(queue().queue[#queue().queue]==tail,'independent native tail missing')
 phase='running'
end
local function preparationPaid()
 local ready,detail=F.refresh(state);if not ready then resolveWait(detail);return false end
 local row=prep and byAction[prep]
 if not row or not row.performedAt or isClient()and not completedStates[row]and row.type~='ISInventoryTransferAction'then return false end
 if state.mask then return not state.player:isEquippedClothing(state.mask)end
 return row.transactionDone and not row.transactionRejected and state.borrowed:getContainer()==state.player:getInventory()
end
-- Exercise the real Panel projection, hit test and press/release handlers.
-- Coordinates belong to an isolated real widget; no physical input is issued.
local function panelCancel(action,whole)
 local panel=T.ActionQueuePanel:new(80,80,420,600)
 panel.queue,panel.playerNum=queue(),state.player:getPlayerNum();panel:initialise();panel:addToUIManager();panel:update()
 local list=panel.list;list:setYScroll(0)
 assert(not list:isVScrollBarVisible(),'fixture panel must fit its complete operation without a physical scrollbar hit')
 local function target(header)
  for _,row in ipairs(list.items)do
   if row.operation==action.toolkitQueueOperation and (row.header==true)==header and(header or row.item==action)then return row end
  end
 end
 local header=assert(target(true),'real operation header missing')
 if not whole then
  local y=list:topOfItem(header.index)+header.height/2
  assert(list:rowUnderMouse(10,y)==header,'real expand hit test differs')
  assert(list:onMouseDown(10,y)and list.pressedToggle==header.operation,'real expand press was not captured')
  assert(list:onMouseUp(10,y)and panel.expanded[header.operation],'real expand release did not expose children')
 end
 local row=assert(target(whole),'real cancel target missing');local x,y=list:cancelX()+12,list:topOfItem(row.index)+row.height/2
 assert(list:rowUnderMouse(x,y)==row,'real cancel hit test differs')
 local preview=T.ActionQueuePolicy.previewCancel(queue(),row.item,whole)
 assert(preview.allowed,'real cancel preview denied '..tostring(preview.reason))
 local beforeBody=queue().current;local beforeNative=beforeBody and beforeBody.action
 local evidence={source='ActionQueuePanel.List',input='programmatic-press-release',header=whole,target=byAction[row.item].sequence,
  actionRef=tostring(row.item),item=itemID(row.item),previewAllowed=preview.allowed,x=x,y=y,at=now()}
 evidence.pressed=list:onMouseDown(x,y)==true
 evidence.pressCaptured=whole and list.pressedOperation and list.pressedOperation.item==row.item or not whole and list.pressedCancel==row.item
 assert(evidence.pressed and evidence.pressCaptured,'real cancel press did not capture its exact target')
 evidence.released=list:onMouseUp(x,y)==true;evidence.feedback=list.cancelFeedback and list.cancelFeedback.text or false
 evidence.gestureCleared=not list.pressedOperation and not list.pressedCancel
 evidence.bodyCurrent=queue().current==beforeBody and queue().current.action==beforeNative
 evidence.returnAbsent=not whole and queue():indexOf(action)==-1 or false
 evidence.bodyRef=beforeBody and tostring(beforeBody)or false;evidence.nativeRef=beforeNative and tostring(beforeNative)or false
 assert(evidence.released and evidence.gestureCleared and not evidence.feedback,'real cancel release rejected')
 if not whole then assert(evidence.bodyCurrent and evidence.returnAbsent,'return click stopped reading or retained the native return')end
 panel:removeFromUIManager()
 return evidence
end
local function cancelAtBoundary()
 if cancelEvidence or not prep or not body or not preparationPaid()then return end
 local current=queue().current;local currentRow=byAction[current]
 if current~=body or not currentRow or not currentRow.progress then return end
 if state.borrowed then
  assert(state.borrowed:getAlreadyReadPages()==ids.borrowedInitial and state.player:getAlreadyReadPages(state.borrowed:getFullType())==ids.borrowedInitial,
   'borrowed native reader passed its first unpaid page before cancellation boundary')
 end
 local before=snapshot()
 assert(queue():indexOf(prep)==-1,'confirmed preparation must have left the Lua queue')
 assert(queue():indexOf(tail)~=-1 and tail.toolkitQueueOperation~=body.toolkitQueueOperation,'independent tail shares operation')
 cancelEvidence={requested=not native,at=now(),preparation=byAction[prep].sequence,body=byAction[body].sequence,
  current=currentRow.sequence,preparationAbsent=true,preparationPaid=true,currentProgress=true,tailRetained=true,before=before}
 if state.borrowed and not native then
  local operation=assert(T.ActionQueueSettlement.operationState(current),'borrowed read has no shared phase record')
  local active=0
  for _,entry in ipairs(operation.borrowings or{})do
   if entry.id==state.borrowed:getID()and entry.fullType==state.borrowed:getFullType()and entry.state=='active'then active=active+1 end
  end
  assert(active==1,'exact confirmed borrowed read episode missing from shared phase record')
  cancelEvidence.operationState=operation
 end
 if not native then
  if state.borrowed then
   local whole=not state.keepReturn;local target=current
   if not whole then
    for _,action in ipairs(queue().queue)do
     if classify(action)=='cleanup'and action.toolkitQueueOperation==body.toolkitQueueOperation then
      assert(target==current,'ambiguous pending borrowed return');target=action
     end
    end
    assert(target~=current,'pending borrowed return missing')
   end
   cancelEvidence.ui=panelCancel(target,whole);cancelEvidence.allowed=true;cancelEvidence.reason=false
  else
   local decision=T.ActionQueuePolicy.evaluateCancel(queue(),current,true)
   cancelEvidence.allowed=decision.allowed;cancelEvidence.reason=decision.reason or false
   assert(decision.allowed,'completed native preparation cancellation denied '..tostring(decision.reason))
   assert(T.ActionQueue.cancelOperation(queue(),current),'public operation cancellation rejected')
  end
  assert(queue():indexOf(tail)~=-1,'operation cancellation removed independent native tail')
 end
 raw('BOUNDARY',cancelEvidence);phase='checkpoint';request('Checkpoint')
end
local function finish()
 local actual=snapshot()
 assert(final.case==case()and F.sameFinalItems(state,baseline.items,actual.items)and F.sameFinalItems(state,ids.baseline.items,final.items),'cleanup inventory identity/container conservation failed')
 assert(F.restored(state,actual)and F.restored(state,final),'exact native cleanup was not restored on both roles')
 assert(actual.book==ids.pages and final.book==ids.pages,'independent native reader did not complete')
 assert(tailSnapshot and cancelEvidence,'native causal boundary/tail evidence missing')
 if state.mask then
  local expected=baseline.food.hunger-baseline.food.base*.25
  -- Active native Eat is finish-step: it may finish its sole paid portion before cleanup.
  assert(math.abs(actual.food.hunger-expected)<.0001 and math.abs(final.food.hunger-expected)<.0001,'native mask meal duplicated, omitted or changed its portion')
 else
  local expected=(native or state.keepReturn)and ids.borrowedPages or cancelEvidence.before.borrowed.pages
  assert(bodyTerminal and expected==((native or state.keepReturn)and ids.borrowedPages or ids.borrowedInitial),'borrowed native page boundary evidence missing')
  for _,value in ipairs({actual.borrowed,final.borrowed,bodyTerminal.borrowed})do
   assert(value.pages==expected and value.characterPages==expected and value.total==ids.borrowedPages,'borrowed paid pages rolled back or replayed')
  end
 end
 emit({event='case',id=case(),status='passed',ids=ids,baseline=baseline,authorityBaseline=authorityStart,checkpoint=checkpoint,
  boundary=cancelEvidence,records=records,bodyTerminal=bodyTerminal or false,tailSnapshot=tailSnapshot,idleEvidence=idleEvidence,client=actual,server=final,nativeMethodsUnchanged=true,
  outcome={cleanupRestored=true,tailCompleted=true,authoritative=true,cancelled=not native,normalNativeControl=native,cleanupBeforeTail=F.ownedCleanupBeforeTail(state,tailSnapshot),originalEquipmentBeforeTail=F.restored(state,tailSnapshot)}})
 index=index+1;state=nil;ids=nil;checkpoint=nil;final=nil;tail=nil;body=nil;prep=nil;quiet=nil;bodyTerminal=nil;idleEvidence=nil;resolveLast=nil;resolveSeen={};authorityStart=nil;baselineRequested=nil;since=now();phase='prepare'
 if not case()then emit({event='complete',cases=config.cases,performed=#config.cases,skipped=0,failed=0});raw('COMPLETE',{cases=config.cases});done=true end
end
Events.OnGameStart.Add(function()entered=true;since=now()end)
Events.OnTick.Add(function()
 if not entered or done then return end
 local ok,problem=pcall(function()
  local player=getPlayer();if not isIngameState()or not player or not player:getCurrentSquare()then return end
  if not ready then
   if isClient()~=(config.kind=='mp')or isClient()and player:getUsername()~='client1'then return end
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(not native)
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);player:setAutoDrink(false)
   assert(T.ActionQueueLifecycle.registerObserver('fixture.cleanup-cancel',{started=register,begin=recordBegin,finish=recordFinish}),'read-only native observer unavailable')
   ready=true;emit({event='setup',cases=config.cases,queueEnabled=not native,nativeDurations=true})
  end
  assert(now()-since<180000,'cleanup timeout '..tostring(case())..' phase='..phase)
  if state and records and observe()==false then return end
  if phase=='prepare'then assert(empty());phase='prepared';request('Prepare')
  elseif phase=='prepared'and ids then
   if not state then
    local diagnostic;state,diagnostic=F.resolve(player,ids)
    if not state then resolveWait(diagnostic);return end
   end
   if isClient()and not baselineRequested then baselineRequested=true;phase='baseline';request('Baseline');return end
   if player:isPlayerMoving()or player:tooDarkToRead()then return end
   enqueue()
  elseif phase=='baseline'and authorityStart then
   local difference=F.baselineDifference(state,snapshot());assert(not difference,JSON.encode(difference or{}))
   if player:isPlayerMoving()or player:tooDarkToRead()then return end
   enqueue()
  elseif phase=='running'then cancelAtBoundary()
  elseif phase=='checkpoint'and checkpoint then phase='drain'
  elseif phase=='drain'then
   if not empty()then quiet=nil;return end
   local actual=snapshot()
   if not F.restored(state,actual)or actual.book~=ids.pages then quiet=nil;return end
   quiet=quiet or now();if now()-quiet>=1500 then
    idleEvidence={case=case(),since=quiet,at=now(),empty=empty(),snapshot=actual};raw('P4_IDLE',idleEvidence)
    phase='verify';request('Verify')
   end
  elseif phase=='verify'and final then finish()end
 end)
 if not ok then
  local diagnostic=state and snapshot()or false
  emit({event='case',id=case(),status='failed',phase=phase,reason=tostring(problem),client=diagnostic,resolve=resolveLast or false,prepared=ids or false,records=records or{}})
  print('[QUEUE_TEST] FAIL cleanup-cancel '..tostring(problem));done=true
 end
end)
