-- Test-only interventions use the public queue commands and real container
-- capacity. No native validity/callback/outcome is substituted.
local F=require 'QueueWringClothing'
local C={}
local function generated(state,queue)
 local found
 for _,action in ipairs(queue.queue)do
  if action.Type=='ISInventoryTransferAction'and action.srcContainer==state.player:getInventory()and action.destContainer==state.source then
   local members=F.returnMembers(action,{})
   if #members==1 and members[1].id==state.ids.items.target.id then assert(not found,'duplicate generated return');found=action end
  end
 end
 return found
end
-- Captured DTO labels are immutable; actual objects remain the liveness proof.
function C.returnRef(profile,action)
 local pending=profile.pendingReturn
 if pending and pending.action==action then return pending.ref end
 return tostring(action)
end
function C.begin(profile,state,queue,body,native,request,bodyRef)
 if not state.ids.returnControl or profile.controlEvidence then return end
 assert(queue.current==body and body.action and body:isStarted()and body:getJobDelta()>0,'control requires actual native body progress')
 local returned=generated(state,queue);assert(native and not returned or not native and returned and not returned.action,'control generated return ownership differs')
 local pending=profile.pendingReturn
 assert(type(bodyRef)=='string'and bodyRef~='','control requires captured body reference')
 assert(native and not pending or not native and pending and pending.body==body and pending.action==returned
  and type(pending.ref)=='string'and pending.ref~='','control pending return capture differs')
 local nativeAction,token=body.action,body.toolkitQueueOperation
 local evidence={kind=state.ids.returnControl,enabled=not native,bodyRef=bodyRef,bodyNative=tostring(nativeAction),
  generatedRef=returned and pending.ref or false,before=F.snapshot(state),accepted=false,policyMode=false}
 profile.controlEvidence=evidence
 if evidence.kind=='keep'and not native then
  local toolkit=PZSurvivorToolkit;local decision=toolkit.ActionQueuePolicy.evaluateCancel(queue,returned)
  assert(decision.allowed and decision.mode=='pending-return','pending Keep policy denied '..tostring(decision.reason))
  evidence.policyMode=decision.mode;evidence.accepted=toolkit.ActionQueue.cancel(queue,returned)==true
  assert(evidence.accepted and queue:indexOf(returned)==-1,'pending Keep did not remove exact return')
 elseif evidence.kind=='full'then request('CapacityLost')end
 evidence.after=F.snapshot(state)
 evidence.bodyUnchanged=queue.current==body and body.action==nativeAction and body.toolkitQueueOperation==token
 assert(evidence.bodyUnchanged,'return control interrupted or replaced its native wring body')
end
function C.capacityAccepted(profile,state,receipt)
 local evidence=assert(profile.controlEvidence,'capacity receipt without active control')
 local spec=state.ids.items.target
 assert(evidence.kind=='full'and not evidence.authority and receipt.case==state.ids.case and receipt.itemId==spec.id
  and receipt.itemType==spec.type and receipt.authority==true and receipt.root==true
  and receipt.beforeCapacity>0 and receipt.afterCapacity==0 and receipt.roomBefore==true and receipt.roomAfter==false,'capacity receipt differs')
 if isClient()then
  assert(state.source:getCapacity()>0 and state.player:getInventory():getItemById(spec.id),'capacity replica missed earned root item')
  state.controlCapacityBefore=state.source:getCapacity();state.source:setCapacity(0)
 end
 assert(state.source:getCapacity()==0,'capacity replica did not converge')
 evidence.authority=receipt;evidence.accepted=true
end
function C.ready(profile,state,queue,native)
 if not state.ids.returnControl then return true end
 local evidence=profile.controlEvidence
 if not evidence or evidence.kind=='full'and not evidence.authority then return false end
 if #queue.queue>0 or state.player:hasTimedActions()then return false end
 if evidence.kind=='full'and evidence.kept==nil then
  evidence.blocked=false;evidence.kept=false
  if not native then
   local matches={};for _,failure in ipairs(PZSurvivorToolkit.ActionQueueExecution.blockedReturns(state.player))do
    if failure.itemId==state.ids.items.target.id then matches[#matches+1]=failure end
   end
   assert(#matches==1 and matches[1].state=='blocked','native source denial lost exact visible return debt')
   evidence.blocked=matches[1]
   evidence.kept=PZSurvivorToolkit.ActionQueueExecution.keepReturn(state.player,matches[1].id)==true
   assert(evidence.kept,'explicit Keep could not retire the rejected return')
  end
 end
 return true
end
return C
