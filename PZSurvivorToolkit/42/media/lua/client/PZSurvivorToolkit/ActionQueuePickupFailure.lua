-- A definite, fresh singleton refusal has no earned item effect. Isolate only
-- its proven dependants; unknown/partial/custom outcomes retain native fallback.
local Toolkit=PZSurvivorToolkit
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Requests=require 'PZSurvivorToolkit/ActionQueueTransferRequests'
local Outcome=require 'PZSurvivorToolkit/ActionQueueTransferOutcome'
local Failure={}
Toolkit.ActionQueuePickupFailure=Failure
local active={}
local closure,own=Proof.closure,Proof.own
local done,rejected=isItemTransactionDone,isItemTransactionRejected
local bindings
local cancel=ISBaseTimedAction.forceCancel
local function owned(fn,file)return type(fn)=='function'and Proof.closure==closure and closure(fn,file)end
local function ready()
 local policy,settlement,bulk,lifecycle=Toolkit.ActionQueuePolicy,Toolkit.ActionQueueSettlement,Toolkit.BulkActions,Toolkit.ActionQueueLifecycle
 if Toolkit~=PZSurvivorToolkit or Toolkit.ActionQueuePickupFailure~=Failure or Toolkit.ActionQueueTransferRequests~=Requests or Proof.own~=own
  or not owned(Requests.prepare,'ActionQueueTransferRequests.lua')or not owned(Requests.clear,'ActionQueueTransferRequests.lua')
  or not owned(Outcome.atSource,'ActionQueueTransferOutcome.lua')or ISBaseTimedAction.forceCancel~=cancel
  or not owned(cancel,'ISBaseTimedAction.lua')then return false end
 if not bindings then
  local refs={}
  for _,entry in ipairs({{policy,'matchesNative','ActionQueuePolicy.lua'},{policy,'isOrdinaryTransfer','ActionQueuePolicy.lua'},
   {policy,'rejectedPickupPlan','ActionQueuePolicy.lua'},{policy,'editUnchanged','ActionQueuePolicy.lua'},
   {settlement,'rejectedPickupUntouched','ActionQueueSettlement.lua'},{settlement,'track','ActionQueueSettlement.lua'},{bulk,'guardTransfer','BulkActions.lua'},
   {bulk,'isGuardedTransfer','BulkActions.lua'},{lifecycle,'hasNativeStopBridge','ActionQueueLifecycle.lua'}})do
   if not entry[1]or not owned(entry[1][entry[2]],entry[3])then return false end
   refs[#refs+1]={entry[1],entry[2],entry[1][entry[2]]}
  end
  bindings={policy=policy,settlement=settlement,bulk=bulk,lifecycle=lifecycle,refs=refs,
   prepare=Requests.prepare,clear=Requests.clear,source=Outcome.atSource,settings=Toolkit.Settings,enabled=Toolkit.Settings.actionQueue}
 end
 if policy~=bindings.policy or settlement~=bindings.settlement or bulk~=bindings.bulk or lifecycle~=bindings.lifecycle
  or Requests.prepare~=bindings.prepare or Requests.clear~=bindings.clear or Outcome.atSource~=bindings.source
  or Toolkit.Settings~=bindings.settings or Toolkit.Settings.actionQueue~=bindings.enabled then return false end
 for _,ref in ipairs(bindings.refs)do if ref[1][ref[2]]~=ref[3]then return false end end
 return Toolkit.Settings.actionQueue()==true and isClient()and isItemTransactionDone==done and isItemTransactionRejected==rejected
  and lifecycle.hasNativeStopBridge()==true
end
local function retire(s)
 if s and active[s.actor]==s then active[s.actor]=nil;(bindings and bindings.clear or Requests.clear)(s.action)end
end
local function localActor(actor)
 return instanceof(actor,'IsoPlayer')and actor:isLocalPlayer()and getSpecificPlayer(actor:getPlayerNum())==actor
  and not actor:isDead()and not actor:isAsleep()
end
local function endpoint(container)
 return instanceof(container,'ItemContainer')and container:getType()~='floor'and container:getType()~='proximityInv'
  and container:getType()~='twistInv_corpses'and container:getAcceptItemFunction()==nil and container:getOnlyAcceptCategory()==nil
end
local function shape(action)
 return type(action)=='table'and getmetatable(action)==ISInventoryTransferAction and action.Type=='ISInventoryTransferAction'
  and localActor(action.character)and action.destContainer==action.character:getInventory()and action.srcContainer~=action.destContainer
  and endpoint(action.srcContainer)and endpoint(action.destContainer)
  and instanceof(action.item,'InventoryItem')and not instanceof(action.item,'InventoryContainer')and not instanceof(action.item,'AnimalInventoryItem')
  and not action.onStartFunc and not action.onCancelFunc and not action.onFailFunc and not action.additionalTest
  and not action.retriggerLastAction and not action._isAddingActions
  and(not action.onCompleteFunc or action.onCompleteFunc==action.toolkitQueueSafeOnComplete
   and owned(action.onCompleteFunc,'BulkActions.lua'))
  and bindings.policy.matchesNative(action)==true and bindings.policy.isOrdinaryTransfer(action)==true
end
local function single(values)
 if type(values)~='table'or getmetatable(values)~=nil or #values~=1 then return false end
 for key in pairs(values)do if key~=1 then return false end end
 return true
end
local function singleton(action)
 local groups=action.queueList;local group=type(groups)=='table'and groups[1]
 return single(groups)and type(group)=='table'and getmetatable(group)==nil and single(group.items)
end
local function current(s)
 local action,q=s.action,s.queue
 return not s.invalid and ready()and active[s.actor]==s and localActor(s.actor)and ISTimedActionQueue.queues[s.actor]==q and q.character==s.actor
  and q.queue==s.list and q.current==action and q.queue[1]==action and #q.queue<=32
  and (q.toolkitOperationGeneration or 0)==s.generation and action.toolkitQueueOperation==s.token
  and not s.token.toolkitCancelled and not q.toolkitGroupCancel and not q.toolkitResume and not q.toolkitOutcomeWait
  and not q.toolkitStopIntent and not q.toolkitOperationsInvalid and(not q.toolkitCancel or q.toolkitCancel==action and s.refused)
  and not s.actor:isPlayerMoving()and not s.actor:pressedMovement(false)and not s.actor:pressedCancelAction()
  and action.srcContainer==s.source and action.destContainer==s.destination and action.item==s.item
  and action.item:getID()==s.id and action.item:getFullType()==s.fullType and shape(action)
  and singleton(action)and action.queueList==s.groups and #s.groups==1 and s.groups[1]==s.group and s.group.items==s.items
  and #s.items==1 and s.items[1]==s.item
  and action.stop==s.stop and action.onCompleteFunc==s.complete and action.toolkitTransferGuard==s.transferGuard
  and (not s.native or action.action==s.native)
end
local function guard(action)
 local s=action and active[action.character]
 return s and s.action==action and current(s)and not s.refused
end
local function before(action,receipt)
 local s=active[action.character]
 local group=action.queueList and action.queueList[1]
 if s and s.request then s.invalid=true;return end
 if not s or s.action~=action or not guard(action)or not singleton(action)or not group or #action.queueList~=1
  or type(group.items)~='table'or #group.items~=1 or group.items[1]~=s.item
  or receipt:getItems()~=group.items or receipt:getSource()~=s.source or receipt:getDestination()~=s.destination then return end
 s.native=action.action
 local request={receipt=receipt,native=s.native,phase='before',dispatcher=createItemTransaction,group=group}
 request.sourceExact=bindings.source(action,s)==true;s.request=request;return request
end
local function after(action,request,receipt,ambiguous)
 local s=active[action.character]
 if not s or s.action~=action or s.request~=request or not request or request.native~=action.action then return end
 request.phase,request.transaction,request.ambiguous=receipt:getPhase(),receipt:getTransaction(),ambiguous==true
end
function Failure.begin(action)
 local prior=action and active[action.character]
 if prior then retire(prior)end
 -- No policy/ancestry work for non-pickups, SP or disabled queues.
 if not isClient()or not Toolkit.Settings.actionQueue()or not action or action.Type~='ISInventoryTransferAction'
  or action.destContainer~=action.character:getInventory()or action.srcContainer==action.destContainer or not ready()then return false end
 local q=ISTimedActionQueue.queues[action.character]
 if not q or q.current~=action or q.queue[1]~=action or #q.queue>32 or action.action or not shape(action)
  or type(action.toolkitQueueOperation)~='table'or q.toolkitCancel or q.toolkitGroupCancel or q.toolkitResume
  then return false end
 -- Native add can create the queue only after the first enqueue stamp. Track
 -- this real head now, before private history checks; preserve an existing role.
 bindings.settlement.track(action,'body')
 if not bindings.settlement.rejectedPickupUntouched(action,{})then return false end
 local candidate=bindings.policy.rejectedPickupPlan(q,action)
 if not candidate or not bindings.settlement.rejectedPickupUntouched(action,candidate.members)
  or not bindings.policy.editUnchanged(q,candidate.snapshot)then return false end
 local groups=action.queueList;local group=type(groups)=='table'and groups[1]
 if not singleton(action)or not group or #groups~=1 or type(group.items)~='table'or #group.items~=1 or group.items[1]~=action.item then return false end
 -- Observe the current singleton without changing native merge behavior. A
 -- later group/request invalidates this capability instead of disabling merge.
 bindings.bulk.guardTransfer(action,true)
 if not shape(action)then return false end
 local s={action=action,actor=action.character,queue=q,list=q.queue,token=action.toolkitQueueOperation,
  generation=q.toolkitOperationGeneration or 0,source=action.srcContainer,destination=action.destContainer,
  item=action.item,id=action.item:getID(),fullType=action.item:getFullType(),groups=groups,group=group,items=group.items,stop=action.stop,complete=action.onCompleteFunc,transferGuard=action.toolkitTransferGuard}
 active[s.actor]=s
 local commit=Requests.prepare(action,guard,before,after)
 if not commit or not current(s)then retire(s);return false end
 if commit()~=true then retire(s);return false end
 return true
end
local function plan(s)
 if not current(s)then return end
 local value=bindings.policy.rejectedPickupPlan(s.queue,s.action)
 if not value or not bindings.settlement.rejectedPickupUntouched(s.action,value.members)
  or not bindings.policy.editUnchanged(s.queue,value.snapshot)or not current(s)then return end
 return value
end
function Failure.beforeStop(action)
 local s=action and active[action.character]
 if not s or s.action~=action or s.refused or not current(s)or not s.native or s.native~=action.action then return false end
 local r=s.request;local tx=action.transactionId
 if not r or r.phase~='submitted'or not r.sourceExact or r.ambiguous or r.native~=s.native or r.transaction~=tx
  or r.dispatcher~=createItemTransaction or type(tx)~='number'or tx==0 or tx%1~=0
  or done(tx)~=false or rejected(tx)~=true or not r.receipt:matchesTransaction(action,tx)
  or r.receipt:isWireAmbiguous()~=false or not r.receipt:hasNativeHandle()
  or action.item:getContainer()==s.destination
  or s.destination:getItemById(s.id)~=nil or not plan(s)then return false end
 s.refused=true;s.transaction=tx
 return true
end
function Failure.preserveStop(action)
 local s=action and active[action.character]
 if not s or s.action~=action or not s.refused or not current(s)
  or(action.transactionId~=0 and action.transactionId~=s.transaction)or not plan(s)then return false end
 return true
end
-- Called after Java removal and before native onCompleted validates its next
-- action. Remove proven untouched dependants only; never synthesize cleanup.
function Failure.finish(queue,action)
 local s=action and active[action.character]
 if not s or s.action~=action or not s.refused then return nil end
 if queue~=s.queue or action.character:getCharacterActions():contains(s.native)then return false end
 local value=plan(s)
 if not value then retire(s);return false end
 if not bindings.policy.editUnchanged(queue,value.snapshot)then retire(s);return false end
 local removed={}
 for _,member in ipairs(value.members)do
  if member.action or member.started or member.toolkitQueueOperation~=s.token then retire(s);return false end
  removed[member]=true
 end
 for i=#queue.queue,2,-1 do if removed[queue.queue[i]]then table.remove(queue.queue,i)end end
 -- Native forceCancel has no effect/callback under the policy's exact binding.
 for _,member in ipairs(value.members)do cancel(member)end
 retire(s)
 return true
end
-- Value-only native verification; a diagnostic is never execution authority.
function Failure.nativeRequestState(action)
 local s=action and active[action.character];local r=s and s.action==action and s.request
 if not r then return end
 local receipt=r.receipt
 return {phase=r.phase,sourceExact=r.sourceExact,transaction=r.transaction,id=s.id,fullType=s.fullType,
  refused=s.refused==true,ambiguous=r.ambiguous==true or s.invalid==true,
  currentHandle=receipt:matchesTransaction(action,action.transactionId)==true,
  nativeHandle=receipt:hasNativeHandle()==true,wireAmbiguous=receipt:isWireAmbiguous()~=false}
end
function Failure.completed(action)
 local s=action and active[action.character]
 if s and s.action==action then retire(s)end
end
function Failure.reset(queue)
 local s=queue and active[queue.character]
 if s and s.queue==queue then retire(s)end
end
if Events and Events.OnGameStart then Events.OnGameStart.Add(function()for _,s in pairs(active)do retire(s)end;active={}end)end
if Events and Events.OnPlayerDeath then Events.OnPlayerDeath.Add(function(actor)retire(active[actor])end)end
-- Observation failures must not abort the original native start/stop callback.
for _,name in ipairs({'begin','beforeStop','preserveStop','finish','completed','reset'})do
 local callback=Failure[name]
 Failure[name]=function(...)
  local ok,value=pcall(callback,...)
  if ok then return value end
  return false
 end
end
return Failure
