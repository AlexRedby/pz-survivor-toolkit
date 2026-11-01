-- Actual observer/commit module with a source-tagged request seam. Receipt
-- doubles cannot establish Java provenance; the two-client native bank does.
local function tagged(source,file,state)
 return assert(loadstring('return function(state) '..source..' end','@/fixture/'..file))()(state)
end
local function setup()
 local s={enabled=true,client=true,untouched=true,allowed=true,done=false,rejected=true,paired=true,
  ambiguous=false,stack=false,cancels=0,guards=0,clears=0,sourceExact=true}
 getFilenameOfClosure=NativeFilenameOfClosure or function(fn)return debug.getinfo(fn,'S').source end
 instanceof=function(value,name)return type(value)=='table'and value.class==name end
 isClient=function()return s.client end
 isItemTransactionDone=function()return s.done end;isItemTransactionRejected=function()return s.rejected end
 createItemTransaction=function()error('observer replayed a request')end
 PZSurvivorToolkit={Settings={actionQueue=function()return s.enabled end}}
 local proof=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
 local function container()
  return {class='ItemContainer',getType=function()return 'shelf'end,getAcceptItemFunction=function()end,
   getOnlyAcceptCategory=function()end,getItemById=function()end}
 end
 local root,source=container(),container()
 local actor={class='IsoPlayer',getInventory=function()return root end,isLocalPlayer=function()return true end,
  getPlayerNum=function()return 0 end,isDead=function()return false end,isAsleep=function()return false end,
  isPlayerMoving=function()return false end,pressedMovement=function()return false end,pressedCancelAction=function()return false end,
  getCharacterActions=function()return {contains=function()return s.stack end}end}
 getSpecificPlayer=function()return actor end
 local item={class='InventoryItem',getID=function()return 15 end,getFullType=function()return 'Base.BookCarpentry1'end,
  getContainer=function()return source end,getIsCraftingConsumed=function()return false end}
 source.getItemById=function()return s.sourceExact and item or nil end
 ISInventoryTransferAction={Type='ISInventoryTransferAction'};ISInventoryTransferAction.__index=ISInventoryTransferAction
 local action=setmetatable({Type='ISInventoryTransferAction',character=actor,item=item,srcContainer=source,destContainer=root,
  toolkitQueueOperation={},queueList={{items={item}}},transactionId=0},ISInventoryTransferAction)
 local reader={character=actor,toolkitQueueOperation=action.toolkitQueueOperation}
 local returning={character=actor,toolkitQueueOperation=action.toolkitQueueOperation}
 local tail={character=actor,toolkitQueueOperation={}}
 local q={character=actor,queue={action,reader,returning,tail},current=action}
 ISTimedActionQueue={queues={[actor]=q}}
 local policy=tagged([[return {
  matchesNative=function(action)return not action.foreign end,isOrdinaryTransfer=function()return true end,
  rejectedPickupPlan=function(q,action)
   state.plans=(state.plans or 0)+1
   if not state.allowed then return end
   return {members={state.reader,state.returning},retained={state.tail},snapshot={}}
  end,editUnchanged=function()return not state.stale end,
 }]],'ActionQueuePolicy.lua',s)
 local settlement=tagged([[return {track=function()state.tracked=true end,rejectedPickupUntouched=function()return state.untouched and state.tracked==true end}]],'ActionQueueSettlement.lua',s)
 local bulk=tagged([[return {guardTransfer=function(action,allowNativeMerge)
  state.guards=state.guards+1;action.stop=function()end
  action.toolkitTransferGuard={}
  if not allowNativeMerge then action.onCompleteFunc=function()end;action.toolkitQueueSafeOnComplete=action.onCompleteFunc end
 end,isGuardedTransfer=function()return true end}]],'BulkActions.lua',s)
 local lifecycle=tagged([[return {hasNativeStopBridge=function()return true end}]],'ActionQueueLifecycle.lua',s)
 ISBaseTimedAction=tagged([[return {forceCancel=function()state.cancels=state.cancels+1 end}]],'ISBaseTimedAction.lua',s)
 local requests=tagged([[return {prepare=function(action,guard,before,after)
  state.callbacks={guard=guard,before=before,after=after};return function()return true end
 end,clear=function()state.clears=state.clears+1 end}]],'ActionQueueTransferRequests.lua',s)
 PZSurvivorToolkit.ActionQueuePolicy=policy;PZSurvivorToolkit.ActionQueueSettlement=settlement
 PZSurvivorToolkit.BulkActions=bulk;PZSurvivorToolkit.ActionQueueLifecycle=lifecycle
 PZSurvivorToolkit.ActionQueueTransferRequests=requests
 local outcome=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ActionQueueTransferOutcome.lua'))()
 require=function(name)
  if name=='PZSurvivorToolkit/SourceProof'then return proof end
  if name=='PZSurvivorToolkit/ActionQueueTransferRequests'then return requests end
  if name=='PZSurvivorToolkit/ActionQueueTransferOutcome'then return outcome end
  error(name)
 end
 Events={OnGameStart={Add=function()end},OnPlayerDeath={Add=function()end}}
 local failure=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueuePickupFailure.lua'))()
 s.action,s.q,s.actor,s.reader,s.returning,s.tail,s.failure=action,q,actor,reader,returning,tail,failure
 function s.prepare()
  assert(failure.begin(action),'supported singleton did not stage observation')
  action.action={};action.transactionId=17
  local receipt={getItems=function()return action.queueList[1].items end,getSource=function()return source end,
   getDestination=function()return root end,getPhase=function()return 'submitted'end,getTransaction=function()return 17 end,
   matchesTransaction=function()return s.paired end,isWireAmbiguous=function()return s.ambiguous end,
   hasNativeHandle=function()return s.paired end}
  assert(s.callbacks.guard(action));local request=assert(s.callbacks.before(action,receipt))
  s.callbacks.after(action,request,receipt,false);s.receipt=receipt
 end
 return s
end
local s=setup();s.prepare()
assert(s.failure.beforeStop(s.action));assert(#s.q.queue==4 and s.cancels==0,'observation mutated queue')
s.action.transactionId=0;assert(s.failure.preserveStop(s.action),'guarded native removal lost refusal')
-- Dynamic replacement after planning must not be dispatched by the commit.
s.reader.forceCancel=function()error('mutable child dispatch')end
assert(s.failure.finish(s.q,s.action))
assert(#s.q.queue==2 and s.q.queue[1]==s.action and s.q.queue[2]==s.tail and s.cancels==2 and s.clears==1)
assert(s.failure.finish(s.q,s.action)==nil,'terminal episode committed twice')
for _,mutation in ipairs({'unknown','absent','done','unpaired','reuse','source','group','items','extra-key','meta',
 'transaction','native','generation','head','token','owner-effect','dependent-tail','callback','stop','movement','helper','sequential'})do
 s=setup();s.prepare()
 if mutation=='unknown'then s.rejected=false
 elseif mutation=='absent'then s.done=true
 elseif mutation=='done'then s.done=true;s.rejected=false
 elseif mutation=='unpaired'then s.paired=false
 elseif mutation=='reuse'then s.ambiguous=true
 elseif mutation=='source'then s.sourceExact=false -- before-call evidence is already captured: mutate the captured result instead below
  s=setup();s.sourceExact=false;s.prepare()
 elseif mutation=='group'then s.action.queueList[1]={items={s.action.item}}
 elseif mutation=='items'then s.action.queueList[1].items={s.action.item}
 elseif mutation=='extra-key'then s.action.queueList.extra=s.action.queueList[1]
 elseif mutation=='meta'then setmetatable(s.action.queueList,{})
 elseif mutation=='transaction'then s.action.transactionId=18
 elseif mutation=='native'then s.action.action={}
 elseif mutation=='generation'then s.q.toolkitOperationGeneration=1
 elseif mutation=='head'then s.q.queue[1]=s.tail
 elseif mutation=='token'then s.action.toolkitQueueOperation={}
 elseif mutation=='owner-effect'then s.untouched=false
 elseif mutation=='dependent-tail'then s.allowed=false
 elseif mutation=='callback'then s.action.onCompleteFunc=function()end;s.action.toolkitQueueSafeOnComplete=s.action.onCompleteFunc
 elseif mutation=='stop'then s.action.stop=function()end
 elseif mutation=='movement'then s.actor.pressedMovement=function()return true end
 elseif mutation=='helper'then isItemTransactionRejected=function()error('foreign helper queried')end
 elseif mutation=='sequential'then s.callbacks.before(s.action,s.receipt)end
 assert(not s.failure.beforeStop(s.action),'unsupported authority acquired isolation: '..mutation)
 assert(not s.failure.preserveStop(s.action)and #s.q.queue==4 and s.cancels==0,mutation..': fallback changed queue')
end
for _,mutation in ipairs({'disabled','sp','multi','unknown-tail','prior-effects'})do
 s=setup()
 if mutation=='disabled'then s.enabled=false elseif mutation=='sp'then s.client=false
 elseif mutation=='multi'then s.action.queueList[1].items[2]=s.action.item
 elseif mutation=='unknown-tail'then s.allowed=false else s.untouched=false end
 assert(not s.failure.begin(s.action)and s.guards==0,mutation..': unsupported native merge/start was modified')
end
s=setup();s.prepare();assert(s.failure.beforeStop(s.action));s.action.transactionId=0;s.stale=true
assert(s.failure.finish(s.q,s.action)==false and #s.q.queue==4 and s.cancels==0,'stale commit pruned dependent work')
s=setup();s.prepare();s.q.queue=nil
assert(s.failure.beforeStop(s.action)==false,'observer exception escaped native stop')
print('Rejected pickup observer: fresh singleton refusal only, exact request/native/group/callback identity, no replay, no return debt, dependency-only pruning and closed unknown/stale/error paths passed.')
