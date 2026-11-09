local config=require 'QueueTestSelection';if config.suite~='queue-transfer-peers'then return end
require 'PZSurvivorToolkit/ActionQueuePanel'
require 'TimedActions/ISReadABook'
require 'TimedActions/ISInventoryTransferUtil'
local F=require 'QueueTransferPeers';local T=PZSurvivorToolkit
local Proof=require 'PZSurvivorToolkit/SourceProof'
local R={index=1,phase='hello',records={},tracks={},tokens={},serial=0,tokenSerial=0}
local entered,done=false,false
local producer,readProducer,requestState,grabProducer,grabOriginal,grabResolver,grabOriginState,scopeOperations,scopeRunner
local pickupFailure=T.ActionQueuePickupFailure
local pickupState=pickupFailure and pickupFailure.nativeRequestState
local function now()return getTimestampMs()end
local function ref(value)return value and tostring(value)or false end
local function queue()return ISTimedActionQueue.getTimedActionQueue(R.player)end
local function empty()return #queue().queue==0 and not R.player:hasTimedActions()and R.player:getCharacterActions():isEmpty()end
local function request(command,extra)
 local row=extra or {};row.case=R.seed and R.seed.case or config.cases[R.index];row.index=R.index;row.token=R.seed and R.seed.token
 sendClientCommand(F.module,command,row)
end
local function fail(problem)
 if done then return end;done=true
 F.emit('FAIL',{case=config.cases[R.index],role=R.role,error=tostring(problem),phase=R.phase})
 print('[QUEUE_TEST] FAIL queue-transfer-peers '..tostring(problem))
end
local function intact()
 assert(ISInventoryPaneContextMenu.onLiteratureItems==producer and ISInventoryPaneContextMenu.readItem==readProducer,'literature producer changed')
 assert(Proof.closure(producer,'ISInventoryPaneContextMenu.lua')and Proof.closure(readProducer,'ActionQueueOperations.lua'),'literature source mismatch')
 assert(pickupFailure==T.ActionQueuePickupFailure and pickupFailure.nativeRequestState==pickupState
  and Proof.closure(pickupState,'ActionQueuePickupFailure.lua'),'pickup observer changed')
 assert(T.ActionQueueSettlement.nativeRequestState==requestState and Proof.closure(requestState,'ActionQueueSettlement.lua'),'request observer changed')
 if R.seed and R.seed.case=='partial-accepted'then
  assert(T.ActionQueueOperations==scopeOperations and scopeOperations.run==scopeRunner and Proof.closure(scopeRunner,'ActionQueueOperations.lua'),'bulk-grab UI operation scope changed')
  assert(ISInventoryPaneContextMenu.onGrabItems==grabProducer and queuePeersGrabOriginal==grabResolver and queuePeersGrabOriginState==grabOriginState
   and grabResolver(grabProducer,ISInventoryPaneContextMenu)==grabOriginal
   and Proof.closure(grabOriginal,'ISInventoryPaneContextMenu.lua'),'native bulk-grab producer chain changed')
 end
end
local function sample(action,row,point)
 local tx=action.transactionId or 0
 if tx~=0 then row.transaction=tx end
 local value={point=point,at=now(),transaction=tx,done=false,rejected=false,observation=false,refusal=false}
 if row.role=='pickup'or row.role=='return'then
  value.done=isItemTransactionDone(tx)==true;value.rejected=isItemTransactionRejected(tx)==true
  value.observation=requestState(action)or false
  if row.role=='pickup'then value.refusal=pickupState(action)or false end
 end
 if row.samples[#row.samples]then
  local prior=row.samples[#row.samples];local a,b={},{}
  for k,v in pairs(value)do if k~='at'then a[k]=v end end
  for k,v in pairs(prior)do if k~='at'then b[k]=v end end
  if F.same(a,b)then return end
 end
 assert(#row.samples<32,'unbounded native observation history');row.samples[#row.samples+1]=value
end
local function register(action)
 if not R.active or not R.state or action.character~=R.player or not action.item then return end
 if R.tracks[action]then return R.tracks[action]end
 local id=action.item:getID();local role
 if action.Type=='ISReadABook'then
  role=id==R.state.ids.front.id and'front'or id==R.state.ids.tail.id and'tail'or nil
 elseif action.Type=='ISInventoryTransferAction'and id==R.state.ids.front.id then role=action.destContainer==R.player:getInventory()and'pickup'or'return'end
 if not role then return end
 R.serial=R.serial+1;local token=action.toolkitQueueOperation
 if token and not R.tokens[token]then R.tokenSerial=R.tokenSerial+1;R.tokens[token]=R.tokenSerial end
 local duration=action.maxTime
 if action.queueList and action.queueList[1]then duration=action.queueList[1].time end
 assert(type(duration)=='number'and duration==duration and math.abs(duration)<math.huge,'nonfinite constructor duration')
 local row={sequence=R.serial,role=role,item=id,actionRef=ref(action),nativeRef=false,token=token and R.tokens[token]or false,
  started=false,progress=false,duration=duration,transaction=0,finishes={},samples={}}
 assert(T.ActionQueuePolicy.matchesNative(action),'unreviewed native action binding')
 R.tracks[action]=row;R.records[#R.records+1]=row;sample(action,row,'pending');return row
end
-- Disposable entry diagnostics: inspect the same pre-Java stage as the real
-- begin gate, without changing production bindings or retrying that begin.
local function pickupEntry(action)
 local row=register(action)
 if not row or row.role~='pickup'then return end
 local q=queue();local allowed,reason=T.ActionQueuePolicy.rejectedPickupPlan(q,action)
 local ownership=T.ActionQueueSettlement.rejectedPickupUntouched(action,{})
 local metadata={}
 for key,entry in pairs({native={T.ActionQueuePolicy.matchesNative,'ActionQueuePolicy.lua'},
  ordinary={T.ActionQueuePolicy.isOrdinaryTransfer,'ActionQueuePolicy.lua'},
  partition={T.ActionQueuePolicy.rejectedPickupPlan,'ActionQueuePolicy.lua'},
  untouched={T.ActionQueueSettlement.rejectedPickupUntouched,'ActionQueueSettlement.lua'},
  guard={T.BulkActions.guardTransfer,'BulkActions.lua'},cancel={ISBaseTimedAction.forceCancel,'ISBaseTimedAction.lua'},
  requests={T.ActionQueueTransferRequests.prepare,'ActionQueueTransferRequests.lua'}})do
  metadata[key]=Proof.closure(entry[1],entry[2])==true
 end
 row.entry={plan=allowed~=nil,reason=reason or false,ownership=ownership,operation=T.ActionQueueSettlement.operationState(action)or false,
  native=T.ActionQueuePolicy.matchesNative(action),ordinary=T.ActionQueuePolicy.isOrdinaryTransfer(action),
  bridge=T.ActionQueueLifecycle.hasNativeStopBridge(),metadata=metadata,queueSize=#q.queue,
  nativeAllocated=action.action~=nil,adding=action._isAddingActions==true,activeWatch=pickupState(action)or false,
  pendingHint=T.ActionQueueTransferRequests.pending[R.player]==action,
  completeSource=action.onCompleteFunc and getFilenameOfClosure(action.onCompleteFunc)or false}
 F.emit('ENTRY',{case=R.seed.case,index=R.index,role=R.role,entry=row.entry})
end
local function nativeIdentity(action,row)
 if action.action then
  local value=ref(action.action);assert(not row.nativeRef or row.nativeRef==value,'native episode changed')
  row.nativeRef=value
 end
end
local function begin(action,phase)
 local row=register(action);if not row then return false end
 nativeIdentity(action,row)
 -- A real callback may arrive before the next tick. Observe the native flag
 -- here too; allocation alone never implies a start or progress.
 if action.action and action:isStarted()then row.started=true end
 if phase=='perform'then sample(action,row,'perform-begin')end
 return true
end
local function finish(action,phase,succeeded)
 local row=register(action);if not row then return end
 if phase=='perform'then sample(action,row,'perform-finish')end
 row.finishes[#row.finishes+1]={phase=phase,at=now(),succeeded=succeeded}
end
-- The existing disposable Java stop observer calls before guarded cleanup can
-- remove the native transaction. This is independent of private request pairing.
function bookControlsNativeTransferStop(action,episode,phase,returned)
 if not R.active then return end
 local row=register(action);if not row or(row.role~='pickup'and row.role~='return')then return end
 intact();nativeIdentity(action,row);assert(row.nativeRef==ref(episode),'native stop episode mismatch')
 if episode:isStarted()then row.started=true end
 local tx=action.transactionId or 0
 if phase=='entry'then
  if tx==0 then return end
  assert(not row.nativeStopEntry,'duplicate native stop entry')
  row.transaction=tx
  row.nativeStopEntry={actor=R.player:getOnlineID(),item=row.item,transaction=tx,nativeRef=ref(episode),at=now(),
   done=isItemTransactionDone(tx)==true,rejected=isItemTransactionRejected(tx)==true,
   current=queue().current==action and queue().queue[1]==action,
   endpointsExact=action.srcContainer==(row.role=='return'and R.player:getInventory()or R.state.frontSource)
    and action.destContainer==(row.role=='pickup'and R.player:getInventory()or R.state.frontSource),
   observation=requestState(action)or false,refusal=row.role=='pickup'and(pickupState(action)or false)or false}
 elseif phase=='returned'and row.nativeStopEntry then
  row.nativeStopReturned={transaction=tx,at=now(),sameNative=action.action==episode,returned=returned}
 end
end
local function observe()
 local q=queue()
 for _,action in ipairs(q.queue)do register(action)end
 -- Retired Java objects can keep isStarted()==true. Only the current owned
 -- queue member can publish an in-flight observation or progress update.
 local action=q.current;local row=action and R.tracks[action]
 if row and q.queue[1]==action then
  nativeIdentity(action,row)
  if action.action and action:isStarted()then
   row.started=true
   local delta=action:getJobDelta();if type(delta)=='number'and delta>0 and delta<1 then row.progress=true end
   sample(action,row,'started')
  end
 end
end
local function start()
 assert(empty(),'fresh phase queue not empty');intact()
 R.records,R.tracks,R.tokens,R.serial,R.tokenSerial={}, {}, {},0,0
 R.active=true;R.bodyReady=false;R.unknown=nil;R.lossSent=false;R.quiet=nil;R.sent=false;R.partial=nil
 local s=R.state
 if R.seed.case=='partial-accepted'then
  if R.role=='client1'then
   local first=assert(F.find(s,R.seed.actors[1].front.id));local second=assert(F.find(s,R.seed.actors[2].front.id))
   assert(queuePeersArmPartialClient(R.player,first:getID(),second:getID(),R.seed.token),'partial client probe could not arm')
   -- One real adjacent step keeps both ordinary transfer actions pending until
   -- native checkQueueList can group the two light items. No fabricated batch,
   -- shortened action or overridden native start/update is used.
   local origin=R.seed.origin
   local square=assert(getCell():getGridSquare(origin.x+1,origin.y,origin.z))
   ISTimedActionQueue.add(ISWalkToTimedAction:new(R.player,square))
   -- The real context-menu click scopes its synchronous producer through
   -- Operations.run. Directly calling only the leaf would invent two intents,
   -- correctly preventing native merging when the queue is enabled.
   scopeRunner(grabProducer,{first,second},R.player:getPlayerNum())
   local firstAction,secondAction
   for _,action in ipairs(queue().queue)do
    if action.Type=='ISInventoryTransferAction'and action.item then
     if action.item:getID()==first:getID()then firstAction=action end
     if action.item:getID()==second:getID()then secondAction=action end
    end
   end
   assert(firstAction and secondAction and firstAction:canMergeAction(secondAction),'UI command did not prepare a native mergeable pair')
   if config.mode=='toolkit'then assert(firstAction.toolkitQueueOperation~=nil and firstAction.toolkitQueueOperation==secondAction.toolkitQueueOperation,'one UI command acquired different operation owners')end
  end
  R.phase='run';R.since=now();return
 end
 producer({s.front},R.player:getPlayerNum());producer({s.tail},R.player:getPlayerNum())
 for _,action in ipairs(queue().queue)do register(action)end
 assert(#R.records>=3,'native pickup/read/return admission missing')
 R.phase='run';R.since=now()
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~=F.module or done then return end
 local ok,problem=pcall(function()
  if command=='Seeded'then
   assert(not R.active,'new phase before old release');R.seed=args;R.index=args.index;R.state=nil;R.phase='resolve';R.since=now()
   local p=args.origin;R.player:teleportTo(p.x+(R.role=='client1'and .5 or 1.5),p.y+.5,p.z)
  elseif command=='Go'then assert(R.seed.token==args.token and R.phase=='ready');start()
  elseif command=='Capacity'then R.capacity=args
  elseif command=='Partial'then assert(R.seed.case=='partial-accepted'and args.token==R.seed.token and not R.partial,'foreign partial result');R.partial=args
  elseif command=='AbortUnknown'then
   assert(R.seed.case=='lost-done'and R.role=='client1'and R.lossSent and not R.unknown,'unexpected unknown abort')
   local current=queue().current;local row=assert(R.tracks[current]);local tx=current.transactionId
   assert(row.role=='return'and tx~=0 and not isItemTransactionDone(tx)and not isItemTransactionRejected(tx),'lost reply was not unresolved')
   R.unknown={probe=queuePeersReplyLossState(),done=false,rejected=false,privateState=requestState(current)or false,cleared=false,recovery=false}
   assert(R.unknown.probe.droppedDone>=1 and R.unknown.probe.pendingExact,'no bound lost native Done')
   ISTimedActionQueue.clear(R.player);R.unknown.cleared=true;R.phase='run'
  elseif command=='Released'then
   assert(R.sent and args.token==R.seed.token);R.active=false;R.phase='release';R.since=now()
  elseif command=='Done'then
   assert(args.restored and args.performed==#config.cases);F.emit('COMPLETE',args);done=true
  elseif command=='Failed'then error(args.error)
  else error('unknown server command')end
 end)
 if not ok then fail(problem)end
end)
local function partialResult()
 intact();assert(empty()and R.partial,'partial result before native drain/authority')
 local blocked=T.ActionQueueExecution.blockedReturns(R.player)
 assert(#blocked==0,'partial native batch invented singleton cleanup authority')
 local probe=R.role=='client1'and queuePeersPartialState()or false
 local row={case=R.seed.case,token=R.seed.token,index=R.index,role=R.role,onlineId=R.player:getOnlineID(),mode=config.mode,
  queueEnabled=config.mode=='toolkit',sourceBound=true,queueIdle=true,producer='selected-pack-walk-then-native-bulk-grab',operationScoped=true,
  replica=F.replica(R.state),probe=probe,producerProof=grabOriginState(),serverPartial=R.partial,blocked=blocked,keptIds={},records=R.records}
 R.sent=true;F.emit('CASE',row);request('Result',{result=row});R.phase='result'
end
local function result()
 intact();for action,row in pairs(R.tracks)do sample(action,row,'terminal')end
 local blocked,kept={},{}
 local entries=T.ActionQueueExecution.blockedReturns(R.player)
 for _,entry in ipairs(entries)do if entry.itemId==R.state.ids.front.id and entry.state=='blocked'then
  blocked[#blocked+1]=entry;assert(T.ActionQueueExecution.keepReturn(R.player,entry.id),'exact failed return Keep rejected');kept[#kept+1]=entry.itemId
 end end
 if R.unknown then
  assert(#kept==0,'unknown outcome acquired Keep')
  R.unknown.recovery=T.ActionQueueRecovery.preview(R.player)or false
  R.unknown.afterProbe=queuePeersReplyLossState()
 end
 local row={case=R.seed.case,token=R.seed.token,index=R.index,role=R.role,onlineId=R.player:getOnlineID(),mode=config.mode,
  queueEnabled=config.mode=='toolkit',sourceBound=true,records=R.records,tailPages=R.player:getAlreadyReadPages(R.state.ids.tail.ft),
  tailInitial=R.state.ids.tail.initial,tailTotal=R.state.ids.tail.total,frontPages=R.player:getAlreadyReadPages(R.state.ids.front.ft),
  blocked=blocked,keptIds=kept,queueIdle=empty(),unknown=R.unknown or false}
 R.sent=true;F.emit('CASE',row);request('Result',{result=row});R.phase='result'
end
require('QueuePreflight').onGameStart(Events,function()entered=true end)
require('QueuePreflight').onTick(Events,function()
 if not entered or done then return end
 local ok,problem=pcall(function()
  if not isIngameState()or not getPlayer()or not getPlayer():getSquare()then return end
  if not R.player then
   R.player=getPlayer();R.role=R.player:getUsername();assert(R.role=='client1'or R.role=='client2')
   assert(isClient(),'two-peer fixture requires client VM')
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(config.mode=='toolkit')
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);R.player:setAutoDrink(false)
   producer=ISInventoryPaneContextMenu.onLiteratureItems;readProducer=ISInventoryPaneContextMenu.readItem
   requestState=T.ActionQueueSettlement.nativeRequestState
   for _,selected in ipairs(config.cases)do if selected=='partial-accepted'then
    grabProducer=ISInventoryPaneContextMenu.onGrabItems;grabResolver=queuePeersGrabOriginal;grabOriginState=queuePeersGrabOriginState
    scopeOperations=T.ActionQueueOperations;scopeRunner=scopeOperations and scopeOperations.run
    assert(Proof.closure(scopeRunner,'ActionQueueOperations.lua'),'native UI operation scope unavailable')
    assert(type(grabResolver)=='function'and type(grabOriginState)=='function','bulk-grab source resolver unavailable')
    grabOriginal=grabResolver(grabProducer,ISInventoryPaneContextMenu)
    assert(Proof.closure(grabOriginal,'ISInventoryPaneContextMenu.lua'),'native bulk-grab callback unavailable')
   end end
   intact()
   assert(T.ActionQueueLifecycle.registerObserver('fixture.queue-transfer-peers',{started=pickupEntry,begin=begin,finish=finish}),'native observer unavailable')
   if type(queuePeersReplyLossState)=='function'then
    local probe=queuePeersReplyLossState();F.emit('PROBE',{role=R.role,state=probe})
    for _,selected in ipairs(config.cases)do if selected=='lost-done'then assert(probe.sourceExact and probe.historyFromConnectionStart,'reply-loss source/lifecycle unsupported: '..tostring(probe.failure))end end
   end
   R.since=now();request('Hello');R.phase='seed';return
  end
  assert(now()-R.since<180000,'peer client phase timeout '..R.phase)
  if R.phase=='resolve'then
   local state=F.resolve(R.player,R.seed,R.role);if not state then return end
   if R.player:isPlayerMoving()or R.player:tooDarkToRead()then return end
   R.state=state
   local _,source,count=F.find(state,state.ids.front.id);assert(count==1 and(source=='source1'or source=='source2'))
   state.frontSource=state.stores[source]
   for _,spec in ipairs({state.ids.front,state.ids.tail})do
    local item=spec==state.ids.front and state.front or state.tail
    if instanceof(item,'Literature')then R.player:setAlreadyReadPages(spec.ft,spec.initial);item:setAlreadyReadPages(spec.initial)end
   end
   R.player:setPerkLevelDebug(Perks.Woodwork,0);R.player:setPerkLevelDebug(Perks.Cooking,0)
   assert(not R.player:hasTrait(CharacterTrait.DISORGANIZED)and not R.player:hasTrait(CharacterTrait.ILLITERATE),'unsupported actor trait')
   R.phase='ready';request('Ready')
  elseif R.phase=='run'then
   observe()
   if R.seed.case=='partial-accepted'then
    if R.role=='client1'then local probe=queuePeersPartialState();assert(probe.failure==''and probe.closed=='','partial client probe rejected native request: '..tostring(probe.closed))end
    if not R.partial or not empty()then R.quiet=nil;return end
    if R.role=='client1'and not queuePeersPartialState().expired then return end
    R.quiet=R.quiet or now();if now()-R.quiet<1500 then return end
    partialResult();return
   end
   local current=queue().current;local row=current and R.tracks[current]
   if not R.bodyReady and row and row.role=='front'and row.started and row.progress and R.player:getAlreadyReadPages(R.state.ids.front.ft)>R.state.ids.front.initial then
    R.bodyReady=true
    if R.seed.case=='lost-done'and R.role=='client1'then assert(queuePeersArmReplyLoss(R.player,R.state.ids.front.id),'reply-loss probe could not arm')end
    request('BodyReady')
   end
   if R.seed.case=='lost-done'and R.role=='client1'and R.bodyReady and not R.lossSent then
    local probe=queuePeersReplyLossState()
    if probe.droppedDone>0 then R.lossSent=true;request('LostDone')end
   end
   if not empty()then R.quiet=nil;return end
   R.quiet=R.quiet or now();if now()-R.quiet<1500 then return end
   if R.seed.case=='shared-capacity'and not R.capacity then return end
   if R.seed.case=='lost-done'and R.role=='client1'and not R.unknown then error('lost-Done action completed without explicit unknown cancellation')end
   result()
  elseif R.phase=='release'then
   assert(empty(),'phase release with native work');local missing=true
   for _,spec in ipairs(R.seed.items)do local _,_,count=F.find(R.state,spec.id);if count~=0 then missing=false end end
   if missing then R.state=nil;R.phase='seed';request('Released')end
  end
 end)
 if not ok then fail(problem)end
end)
