-- Test-only native stop/editor interventions. No validity, duration, executor,
-- physical item mutation or outcome is substituted.
local F=require 'QueueWringClothing'
local A={}
function A.applies(state)
 local kind=state and state.ids.returnControl
 return kind=='cancel'or kind=='cancel-toggle'or kind=='toggle-off'or kind=='toggle'
end
local function setting(profile,state,q,native,label,requested)
 local T=PZSurvivorToolkit;local active=assert(profile.activeControl)
 local before=T.Settings.actionQueue();local generation=q.toolkitOperationGeneration or 0
 PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(requested)
 T.ActionQueue.updateOperationState(q)
 local row={label=label,requested=requested,before=before,after=T.Settings.actionQueue(),
  generationBefore=generation,generationAfter=q.toolkitOperationGeneration or 0,
  bodySame=q.current==active.body,nativeSame=active.body.action==active.native,
  tailRetained=q:indexOf(state.tailAction)~=-1,requestRetained=q.toolkitGroupCancel~=nil}
 assert(row.after==requested,'editor transition did not apply')
 profile.controlEvidence.settings[#profile.controlEvidence.settings+1]=row
 return row
end
function A.begin(profile,state,q,body,native,bodyRef)
 if profile.controlEvidence then return end
 assert(q.current==body and body.action and body:isStarted()and body:getJobDelta()>0,'active intervention missed native body progress')
 local pending=profile.pendingReturn
 assert(native and not pending or not native and pending and pending.body==body and not pending.action.action,'active original optional return ownership differs')
 local token,nativeAction=body.toolkitQueueOperation,body.action
 profile.activeControl={body=body,native=nativeAction,token=token,original=pending and pending.action,
  requestAt=getTimestampMs()}
 local e={kind=state.ids.returnControl,enabled=not native,bodyRef=bodyRef,bodyNative=tostring(nativeAction),
  generatedRef=pending and pending.ref or false,before=F.snapshot(state),accepted=false,policyMode=false,
  stopped=false,stopEvents={},lifecycleEvents={},originalReturn=pending and{actionRef=pending.ref,allocated=false,events={}}or false,
  requiredRef=false,reenabledDuringBody=false,tailPreserved=false,tailRef=assert(profile.controlTailRef),settings={},blocked=false,kept=false}
 profile.controlEvidence=e;profile.controlBody=body
 assert(profile.activeBodyRow,'active native command row missing').lifecycleEvents=e.lifecycleEvents
 if e.kind=='toggle'or e.kind=='toggle-off'then
  setting(profile,state,q,native,'disable',false)
  profile.activeControl.reenable=e.kind=='toggle'and 3 or nil
  e.accepted=true
 elseif native then
  body:forceStop();e.accepted=true
 else
  local decision=PZSurvivorToolkit.ActionQueuePolicy.evaluateCancel(q,body,true)
  e.policyMode=decision.mode or false
  assert(decision.allowed,'active source-proven wring cancel denied '..tostring(decision.reason))
  e.accepted=PZSurvivorToolkit.ActionQueue.cancelOperation(q,body)==true
  assert(e.accepted,'public active operation cancel rejected')
 end
 if e.kind=='cancel-toggle'then setting(profile,state,q,native,'disable',false)end
 e.after=F.snapshot(state)
 e.bodyUnchanged=body.action==nativeAction and body.toolkitQueueOperation==token
 assert(e.bodyUnchanged,'active request replaced its original native body')
end
function A.tick(profile,state,q,native)
 local active,e=profile.activeControl,profile.controlEvidence
 if not active or not active.reenable or getTimestampMs()<=active.requestAt then return end
 assert(q.current==active.body and active.body.action==active.native and active.body:isStarted(),'editor cycle lost active native body')
 local enabling=active.reenable%2==1
 setting(profile,state,q,native,enabling and(native and're-enable-control'or're-enable')or'disable',enabling and not native)
 active.reenable=active.reenable>1 and active.reenable-1 or nil;active.requestAt=getTimestampMs()
 if enabling then e.reenabledDuringBody=true end
end
function A.started(profile,state,q,action)
 local active,e=profile.activeControl,profile.controlEvidence
 if not active then return end
 if action==active.original then e.originalReturn.allocated=true end
 if action.Type=='ISInventoryTransferAction'and action.srcContainer==state.player:getInventory()and action.destContainer==state.source then
  local members=F.returnMembers(action,{})
  if #members==1 and members[1].id==state.ids.items.target.id then
   assert(e.enabled and e.kind~='toggle'and e.kind~='toggle-off'and action~=active.original and not profile.activeRequired,'unexpected original/duplicate active return')
   assert(e.stopped,'required return started before exact native stop finished')
   profile.activeRequired={action=action,ref=tostring(action)};e.requiredRef=profile.activeRequired.ref
  end
 end
end
function A.returnRef(profile,action)
 local row=profile.activeRequired
 if row and row.action==action then return row.ref end
end
function A.lifecycle(profile,state,action,boundary,phase,succeeded)
 local active,e=profile.activeControl,profile.controlEvidence
 if not active then return end
 if action==active.original then
  e.originalReturn.events[#e.originalReturn.events+1]={boundary=boundary,phase=phase,succeeded=succeeded==true}
  return true
 end
 if action~=active.body or(phase~='stop'and phase~='perform'and phase~='complete')then return end
 assert(action.action==active.native,'active callback native episode changed')
 local event={boundary=boundary,phase=phase,succeeded=succeeded==true,nativeRef=tostring(active.native)}
 e.lifecycleEvents[#e.lifecycleEvents+1]=event
 return true
end
-- JVM probe observes the untouched native callback; Lifecycle.runStop is not
-- part of ordinary wring execution. Keep the two evidence channels distinct.
function A.nativeStop(profile,state,action,nativeAction,boundary,succeeded,details)
 local active,e=profile.activeControl,profile.controlEvidence
 if not active or action~=active.body then return end
 assert(e.kind=='cancel'or e.kind=='cancel-toggle','editor toggle stopped native body')
 assert(nativeAction==active.native and action.action==active.native,'native stop episode changed')
 assert(type(details)=='table'and details.source=='disposable-jvm-stop'
  and details.probeClass=='net.alexredby.wringstopprobe.Main'
  and details.nativeClass=='zombie.characters.CharacterTimedActions.LuaTimedActionNew','native stop observer source differs')
 assert(details.callbackUnchanged==true,'native stop callback changed')
 if boundary=='entry'then
  assert(#e.stopEvents==0 and succeeded==false and details.callbackObserved==false and details.callbackSucceeded==false,'duplicate/invalid native stop entry')
 else
  assert(boundary=='returned'and #e.stopEvents==1 and succeeded==true
   and details.callbackObserved==true and details.callbackSucceeded==true,'native stop callback did not return successfully')
  e.stopped=true
 end
 local event={boundary=boundary,phase='stop',succeeded=succeeded==true,nativeRef=tostring(nativeAction)}
 for key,value in pairs(details)do event[key]=value end
 e.stopEvents[#e.stopEvents+1]=event
end
function A.ready(profile,state,q,native)
 local active,e=profile.activeControl,profile.controlEvidence
 if not active or active.reenable or #q.queue>0 or state.player:hasTimedActions()then return false end
 if active.original then
  e.originalReturn.allocated=e.originalReturn.allocated or active.original.action~=nil or active.original.started==true
  assert(not e.originalReturn.allocated and #e.originalReturn.events==0,'revoked original optional return was executed')
 end
 if e.kind=='toggle'or e.kind=='toggle-off'then
  assert((e.kind=='toggle-off'or e.reenabledDuringBody)and not e.stopped,'editor toggle stopped native body')
 else
  assert(e.stopped,'active cancellation did not deliver native stop')
  assert(native and not e.requiredRef or not native and e.requiredRef,'earned cancellation return observation differs')
 end
 local tail=assert(profile.activeTailRow,'active tail observation missing')
 e.tailPreserved=tail.started==true and tail.progress==true
 local expectedNotice=not native and(e.kind=='toggle'or e.kind=='toggle-off')
 local notice
 for _,failure in ipairs(PZSurvivorToolkit.ActionQueueExecution.blockedReturns(state.player))do
  if failure.itemId==state.ids.items.target.id then
   e.blocked=failure
   assert(expectedNotice and not notice and failure.itemType==state.ids.items.target.type
    and failure.reason=='producer'and failure.state=='revoked','active cancellation/editor cycle return debt differs')
   notice=failure
  end
 end
 assert(not expectedNotice or notice,'revoked unpaid optional return notice disappeared')
 e.blocked=notice or false
 return true
end
return A
