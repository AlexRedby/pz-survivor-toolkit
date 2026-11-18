require 'PZSurvivorToolkit/ActionQueuePanel'
require 'ISUI/ISInventoryPaneContextMenu'
require 'TimedActions/ISEquipWeaponAction'
require 'TimedActions/ISWearClothing'
local F=require 'QueueClaimedReturn'
local P=require 'QueueEnergyPlacement'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local T=PZSurvivorToolkit
local Ops=require 'PZSurvivorToolkit/ActionQueueOperations'
local Settlement=require 'PZSurvivorToolkit/ActionQueueSettlement'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local phase,index,since='prepare',1,getTimestampMs()
local started,ready,done=false,false,false
local state,authority,previous,ids,receipt,placement,placing,placementProof,quiet
local evidence,actions,tracks,owned,observations={},{},{},{},{}
local nativeWatch,setupActions,tailBoundaryAction,tailBoundaryNative
local function cancelsBody()return ids.case=='claimed-cancel'or ids.case=='claimed-cancel-success'end
local function succeeds()return ids.case=='claimed-success'or ids.case=='claimed-cancel-success'end
local function q()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #q().queue==0 and not getPlayer():hasTimedActions()end
local function raw(event,row)print('[CLAIMED_RETURN] '..event..' '..JSON.encode(row))end
local function emit(row)row.suite='claimed-return';row.actor='client1';row.kind=config.kind;row.mode=config.mode;JSON.emit(row)end
local function fail(reason)if done then return end;done=true;raw('FAILED',{phase=phase,error=tostring(reason)});print('[QUEUE_TEST] FAIL claimed-return '..tostring(reason));emit({event='failure',id=config.cases[index],error=tostring(reason)})end
local function request(command)
 local args={case=config.cases[index],placement=placement,clientPlacement=placementProof}
 if isClient()then sendClientCommand('ClaimedReturnTest',command,args)
 elseif command=='Prepare'then authority=F.prepare(getPlayer(),args.case,placement,placementProof,previous);previous=nil;ids=authority.ids;raw('PREPARED',ids)
 else receipt=assert(F.verify(authority),'SP physical authority differs');raw('VERIFIED',receipt)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~='ClaimedReturnTest'or done then return end
 if command=='Failed'then fail(args.error)
 elseif args and args.case==config.cases[index]then
  if command=='Prepared'then ids=args elseif command=='Verified'then receipt=args end
 end
end)
assert(T.ActionQueueDefinitions.registerBehavior('fixture.claimed-return',{
 types={'ISQueueActionsAction'},
 matches=function(action)return owned[action]~=nil and Ops.isCommand(action)end,
 inspect=function(action)
  assert(owned[action]and action.addActionsFunction==owned[action])
  return{knownInputs=true,items={},targets={[getPlayer()]=true},hands=getPlayer(),equipment=getPlayer(),deferred=true,cancelWaiting=true}
 end,
}))
local function command(callback)
 local action=Ops.command(getPlayer(),callback,{})
 owned[action]=callback;return action
end
local function track(name,action)
 actions[name]=action;local row={actionRef=tostring(action),type=action.Type,itemId=action.item and action.item:getID()or false,
  duration=action.maxTime,allocated=action.action~=nil,started=false,progress=false,events={}}
 evidence[name]=row;tracks[action]=row;return action
end
-- Independent immutable native callback/ancestry watch. Physical predicates are
-- deliberately separate: losing the native hand effect is a failed obligation.
local function equipSource()
 local class,base=ISEquipWeaponAction,ISBaseTimedAction
 local parent,root=getmetatable(class),getmetatable(base)
 local methods,baseMethods={},{}
 for name,callback in pairs(class)do if type(callback)=='function'then methods[name]=callback end end
 for name,callback in pairs(base)do if type(callback)=='function'then baseMethods[name]=callback end end
 local heavy,drop=isForceDropHeavyItem,forceDropHeavyItems
 assert(Proof.closure(class.new,'ISEquipWeaponAction.lua')and Proof.closure(class.stop,'ISEquipWeaponAction.lua'),'native equip source differs')
 return function(action)
  if ISEquipWeaponAction~=class or ISBaseTimedAction~=base or getmetatable(action)~=class
   or getmetatable(class)~=parent or getmetatable(base)~=root or isForceDropHeavyItem~=heavy or forceDropHeavyItems~=drop then return false end
  for name,callback in pairs(methods)do if class[name]~=callback or action[name]~=callback then return false end end
  for name,callback in pairs(class)do if type(callback)=='function'and methods[name]~=callback then return false end end
  for name,callback in pairs(baseMethods)do if base[name]~=callback or action[name]~=(methods[name]or callback)then return false end end
  return true
 end
end
local function ack(action,row)
 if not action then return end
 local A=T.ActionQueueAcknowledgements
 local saved=observations[action]
 if not saved and action.action then saved={native=action.action,actor=action.character,item=action.item,queue=q(),root=action.character:getInventory(),operation=action.toolkitQueueOperation};observations[action]=saved end
 if saved and not saved.receipt then saved.receipt=A.capture(action)end
 local status=saved and saved.receipt and A.observe(action,saved.receipt)or false
 local out={at=getTimestampMs(),state=status or false,captured=saved~=nil and saved.receipt~=nil,
  transaction=action.toolkitNativeTransaction or false,kind=action.toolkitNativeKind or false,
  token=saved and saved.receipt and saved.receipt.token or false,
  nativeSame=saved~=nil and action.action==saved.native,itemSame=saved~=nil and action.item==saved.item,
  actorSame=saved~=nil and action.character==saved.actor,queueSame=saved~=nil and q()==saved.queue,
  rootSame=saved~=nil and action.character:getInventory()==saved.root,
  operationSame=saved~=nil and action.toolkitQueueOperation==saved.operation,
  nativeRef=saved and tostring(saved.native)or false,operationRef=saved and tostring(saved.operation)or false}
 local last=row.ack[#row.ack]
 if not last or last.state~=out.state or last.captured~=out.captured then row.ack[#row.ack+1]=out;raw('ACK',{case=ids.case,actionRef=row.actionRef,observation=out})end
 return status
end
assert(T.ActionQueueLifecycle.registerObserver('fixture-claimed-return',{
 started=function(action)
  local row=tracks[action];if row then row.nativeStarted=true end
  if action==actions.tail and actions.restore then
   local restore=actions.restore;local status=ack(restore,evidence.restore)
   assert(not tailBoundaryAction,'duplicate native tail admission boundary')
   tailBoundaryAction=action
   evidence.tailBoundary={at=getTimestampMs(),restoreNativeRemoved=not getPlayer():getCharacterActions():contains(restore.action),
    restoreAck=status or false,restoreRef=tostring(restore.action),tailActionRef=tostring(action),tailRef=false,tailAllocated=false,snapshot=F.snapshot(state)}
  end
 end,
 begin=function(action,boundary)
  local row=tracks[action];if not row then return end
  row.events[#row.events+1]={boundary='begin',phase=boundary,at=getTimestampMs(),nativeRef=action.action and tostring(action.action)or false};return true
 end,
 finish=function(action,boundary,succeeded)
  local row=tracks[action];if not row then return end
  row.events[#row.events+1]={boundary='finish',phase=boundary,succeeded=succeeded==true,at=getTimestampMs(),nativeRef=action.action and tostring(action.action)or false}
 end,
 settled=function(action)
  local row=tracks[action];if row then row.settled=true;row.settledAt=getTimestampMs()end
 end,
}))
local function produce()
 local player=getPlayer();local queue=q();local nativeSource=equipSource();nativeWatch=nativeSource
 evidence={claimAccepted=false,freshOperation=false,cancelAccepted=false,stopRequested=false,
  originalReturnAllocated=false,returnCalls=0,returnAllocated=false,pendingObserved=false,timeline={}}
 actions,tracks,owned,observations={},{},{},{}
 tailBoundaryAction,tailBoundaryNative=nil,nil
 assert(empty(),'read producer requires fresh idle queue')
 ISInventoryPaneContextMenu.readItem(state.items.borrowed,player:getPlayerNum())
 local produced={};for _,action in ipairs(queue.queue)do produced[#produced+1]=action end
 local pickup,body,original
 for _,action in ipairs(produced)do
  if action.Type=='ISReadABook'then assert(not body);body=action
  elseif action.Type=='ISInventoryTransferAction'then
   if action.destContainer==player:getInventory()then assert(not pickup);pickup=action
   elseif action.srcContainer==player:getInventory()then assert(not original);original=action end
  end
 end
 assert(pickup and body and original and not original.action and queue:indexOf(original)>1,'native carried read producer differs')
 assert(T.ActionQueuePolicy.isCarriedContainer(pickup.srcContainer,player),'pickup lacks actual carried ancestry')
 track('pickup',pickup);track('body',body)
 evidence.originalReturnRef=tostring(original);actions.original=original
 local loan=assert(Settlement.track(pickup,'prepare'))
 -- Disclosed composition seam: replace only a never-issued optional native
 -- return. All borrowing, hand effects, stop/removal and replication stay native.
 queue:removeFromQueue(original)
 local equip=ISEquipWeaponAction:new(player,state.items.borrowed,50,true,false)
 Ops.adopt(equip,body.toolkitQueueOperation);track('preparationEquip',equip);ISTimedActionQueue.addAfter(pickup,equip)
 local originalToken=body.toolkitQueueOperation;local expansion
 expansion=command(function()
  assert(q().current==expansion and expansion._isAddingActions,'missing genuine cleanup expansion')
  evidence.expandedAt=getTimestampMs();evidence.expansionSnapshot=F.snapshot(state);evidence.freshOperation=expansion.toolkitQueueOperation~=originalToken
  evidence.loanEarnedAtExpansion=Settlement.earned(loan)
  local item=assert(player:getInventory():getItemById(ids.items.previous.id))
  local restore=ISEquipWeaponAction:new(player,item,50,true,false)
  Ops.adopt(restore,expansion.toolkitQueueOperation);assert(Settlement.inheritCleanup(restore,expansion))
  track('restore',restore);evidence.restore.ack={}
  local effect=assert(Settlement.observeCleanupEffect(restore,{
   sourceGuard=nativeSource,
   guard=function(action)return action==restore and action.item==item and action.character==player end,
   capture=function()return{primary=player:getPrimaryHandItem(),secondary=player:getSecondaryHandItem()}end,
   observed=function(_,before)return before.primary~=item and player:getPrimaryHandItem()==item and player:getSecondaryHandItem()==before.secondary end,
  }))
  local continuation=command(function()
   evidence.returnCalls=evidence.returnCalls+1
   evidence.continuationAt=getTimestampMs();evidence.continuationSnapshot=F.snapshot(state)
   evidence.restoreEffectEarned=Settlement.earned(effect)
   assert(evidence.restoreEffectEarned,'unearned native restore released dependent return')
   local returned,why=Settlement.enqueueBorrowedReturn(loan)
   evidence.returnReason=why or false
   if returned then track('returned',returned);evidence.returnAllocated=true end
  end)
  Ops.adopt(continuation,expansion.toolkitQueueOperation);assert(Settlement.inheritCleanup(continuation,expansion));track('continuation',continuation)
  assert(Settlement.requireBorrowedReturnSuccess(loan,{effect},continuation),'cleanup prerequisite enrollment denied')
  ISTimedActionQueue.add(restore);ISTimedActionQueue.add(continuation)
 end)
 Ops.adopt(expansion,originalToken);assert(Settlement.cleanup(expansion,loan))
 evidence.claimAccepted=Settlement.claimBorrowedReturn(expansion,loan)==true;assert(evidence.claimAccepted,'pending exact return claim refused')
 track('expansion',expansion);Ops.runWith(originalToken,function()ISTimedActionQueue.add(expansion)end)
 local beforeTail=#queue.queue
 ISInventoryPaneContextMenu.readItem(state.items.tail,player:getPlayerNum())
 assert(#queue.queue==beforeTail+1,'root read tail producer topology differs')
 local tail=queue.queue[#queue.queue];assert(tail.Type=='ISReadABook'and tail.toolkitQueueOperation~=originalToken,'independent native read tail differs');track('tail',tail)
 evidence.before=F.snapshot(state);phase='running'
end
local function observe()
 for action,row in pairs(tracks)do
  row.allocated=row.allocated or action.action~=nil or action.started==true
  if action.action then
   row.nativeRef=tostring(action.action);row.operationRef=tostring(action.toolkitQueueOperation);row.effectiveDuration=math.max(row.effectiveDuration or -1,action.action:getTime())
   if action==tailBoundaryAction then
    assert(action==actions.tail and evidence.tailBoundary.tailActionRef==row.actionRef,'native tail allocation lost exact admission owner')
    if not tailBoundaryNative then
     tailBoundaryNative=action.action
     evidence.tailBoundary.tailRef=tostring(tailBoundaryNative);evidence.tailBoundary.tailAllocated=true;evidence.tailBoundary.tailAllocatedAt=getTimestampMs()
    end
    assert(action.action==tailBoundaryNative,'native tail allocation identity changed')
   end
  end
  if q().current==action and action:isStarted()then
   if not row.started then row.started=true;row.startedAt=getTimestampMs();row.nativeRef=tostring(assert(action.action));row.operationRef=tostring(action.toolkitQueueOperation)end
   if action:getJobDelta()>0 then row.progress=true end
  end
 end
 if actions.original then evidence.originalReturnAllocated=actions.original.action~=nil or actions.original.started==true;assert(not evidence.originalReturnAllocated,'replaced optional return allocated')end
 if actions.restore then
  local status=ack(actions.restore,evidence.restore)
  if isClient()and status=='started'then evidence.pendingObserved=true end
 end
 if cancelsBody()and evidence.body.progress and not evidence.cancelAccepted then
  assert(q().current==actions.body and getPlayer():getPrimaryHandItem():getID()==ids.items.borrowed.id,'cancel missed borrowed native body')
  evidence.cancelAccepted=T.ActionQueue.cancelOperation(q(),actions.body)==true
  assert(evidence.cancelAccepted,'public claimed body cancellation refused');evidence.cancelRequestedAt=getTimestampMs()
 end
 if not succeeds()and evidence.restore and evidence.restore.progress and not evidence.stopRequested then
  assert(q().current==actions.restore and actions.restore.action,'restore stop missed allocated native progress')
  if cancelsBody()then assert(evidence.freshOperation,'cancellation reused old operation')end
  evidence.stopRequested=true;evidence.stopRequestedAt=getTimestampMs();evidence.beforeStop=F.snapshot(state)
  actions.restore:forceStop()
 end
 if actions.restore then
  evidence.nativeCallbacksUntouched=nativeWatch(actions.restore);assert(evidence.nativeCallbacksUntouched,'native equip callback/ancestry changed')
  local status=ack(actions.restore,evidence.restore)
  if isClient() and evidence.stopRequested and status=='started' and q().current==actions.restore then
   assert(q().queue[1]==actions.restore,'pending restore no longer heads the native queue')
   local contained=getPlayer():getCharacterActions():contains(actions.restore.action)
   local key=contained and 'pendingAuthority' or 'pendingAfterRemoval'
   if not evidence[key] then
    local latest=evidence.restore.ack[#evidence.restore.ack]
    local sample={at=getTimestampMs(),ack=status,currentRestore=true,nativeContained=contained,
     continuationAllocated=actions.continuation.action~=nil,tailAllocated=actions.tail.action~=nil,
     returnCalls=evidence.returnCalls,snapshot=F.snapshot(state)}
    if not contained then
     assert(latest.nativeSame and latest.captured and latest.transaction and latest.token,'pending removal lost native transaction')
     sample.nativeRef=tostring(actions.restore.action);sample.transaction=latest.transaction;sample.token=latest.token
    end
    assert(not sample.continuationAllocated and not sample.tailAllocated and sample.returnCalls==0,'pending Host authority released dependent native work')
    evidence[key]=sample
    raw(contained and 'PENDING_AUTHORITY' or 'PENDING_AFTER_REMOVAL',{case=ids.case,observation=sample})
   end
  end
 end
end
require('QueuePreflight').onGameStart(Events,function()started=true;since=getTimestampMs()end)
require('QueuePreflight').onTick(Events,function()
 if not started or done then return end
 local ok,reason=pcall(function()
  local player=getPlayer();if not isIngameState()or not player or not player:getSquare()then return end
  if not ready then
   if isClient()~=(config.kind=='mp')or isClient()and(player:getOnlineID()<0 or player:getUsername()~='client1')then return end
   assert(config.mode=='toolkit'and not player:isTimedActionInstant(),'claimed bank requires ordinary Toolkit native durations')
   assert(not P4TidyUpMeister and not getActivatedMods():contains('P4TidyUpMeister'),'claimed bank requires native return provider')
   assert(T.ActionQueueAcknowledgements and type(T.ActionQueueAcknowledgements.capture)=='function','native lifecycle ACK bridge unavailable')
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(true)
   player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false);getCore():setOptionAutoDrink(false);getCore():setOptionPauseOnFocusloss(false)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
   ready=true;emit({event='setup',cases=config.cases,nativeDurations=true,provider='native-returns'});since=getTimestampMs()
  end
  assert(getTimestampMs()-since<120000,'claimed return timeout '..phase)
  if phase=='prepare'then
   assert(empty());placement=placement or P.choose(player);placing=placing or P.beginCentered(player,placement);placementProof=P.poll(placing);if not placementProof then return end
   raw('CLIENT_PLACEMENT',{case=config.cases[index],proof=placementProof});phase='prepared';request('Prepare')
  elseif phase=='prepared'and ids then
   state=F.resolve(player,ids);if not state then return end
   setupActions={wear=ISWearClothing:new(player,state.bag),equip=ISEquipWeaponAction:new(player,state.items.previous,50,true,false)}
   ISTimedActionQueue.add(setupActions.wear);ISTimedActionQueue.add(setupActions.equip);phase='setup'
  elseif phase=='setup'and empty()then
   if player:getPrimaryHandItem()~=state.items.previous or not player:getWornItems():contains(state.bag)then return end
   local pane=assert(getPlayerInventory(player:getPlayerNum()));pane:refreshBackpacks();local available=false
   for _,entry in ipairs(pane.backpacks)do if entry.inventory==state.source then available=true end end
   if not available then return end;produce()
  elseif phase=='running'then
   observe();if not empty()then return end
   assert(evidence.tail.started and evidence.tail.progress,'cleanup lost independent real native tail')
   assert(evidence.restore.started and evidence.restore.progress,'required native restore never progressed')
   assert(evidence.tailBoundary and evidence.tailBoundary.restoreNativeRemoved and evidence.tailBoundary.tailAllocated,'tail allocation/admission lost original restore native removal')
   if isClient()then assert(evidence.tailBoundary.restoreAck==(succeeds()and'completed'or'canceled'),'tail preceded exact Host restore terminal')end
   local debts=Settlement.blockedReturns(player);evidence.debts=debts
   if succeeds()then assert(evidence.returnCalls==1 and evidence.returnAllocated and not evidence.stopRequested and #debts==0,'successful cleanup return/debt differs')
   else
    assert(evidence.stopRequested and evidence.returnCalls==0 and not evidence.returnAllocated and not actions.continuation.action,'stopped cleanup executed dependent return')
    assert(#debts==1 and debts[1].itemId==ids.items.borrowed.id and debts[1].reason=='cleanup-outcome','confirmed native cleanup failure debt differs: '..JSON.encode(debts))
   end
   if not F.verify(state)then return end
   quiet=quiet or getTimestampMs();if getTimestampMs()-quiet<500 then return end
   phase='verified';request('Verify')
  elseif phase=='verified'and receipt then
   local client=assert(F.verify(state));ack(actions.restore,evidence.restore)
   evidence.after=client;evidence.queueIdle=true
   emit({event='case',id=ids.case,status='passed',ids=ids,clientPlacement=placementProof,client=client,server=receipt,evidence=evidence})
   if not isClient()then previous=authority end
   index=index+1
   if not config.cases[index]then emit({event='complete',cases=config.cases,performed=index-1,failed=0,skipped=0});raw('COMPLETE',{cases=config.cases});done=true;return end
   -- Retire the visible failure by the existing explicit Keep command before
   -- the next disposable episode. It cannot acquire return/retry authority.
   for _,debt in ipairs(Settlement.blockedReturns(player))do assert(T.ActionQueueExecution.keepReturn(player,debt.id),'fixture debt retirement refused')end
   state,authority,ids,receipt,placement,placing,placementProof,quiet=nil,nil,nil,nil,nil,nil,nil,nil
   actions,tracks,owned,evidence={},{},{},{};phase='prepare';since=getTimestampMs()
  end
 end)
 if not ok then fail(reason)end
end)
