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
local function hand(item)return item and{id=item:getID(),type=item:getFullType()}or false end
local function intentStatus(action)
 local api=PZSurvivorToolkit.ActionQueueTidyIntent
 if not api or type(api.status)~='function'then return{available=false}end
 local ok,allowed,reason,helper=pcall(api.status,action)
 return{available=true,ok=ok,allowed=allowed==true,reason=type(reason)=='string'and reason or false,helper=type(helper)=='string'and helper or false}
end
-- Passive setup receipts isolate source-role and class-binding refusals without
-- invoking an action callback or probing native validity.
local function installationFacts()
 local proof=PZSurvivorToolkit.SourceProof
 if not proof then local ok,value=pcall(require,'PZSurvivorToolkit/SourceProof');if ok then proof=value end end
 if type(proof)~='table'then return{available=false}end
 local pane,menu,api=ISInventoryPane,ISInventoryPaneContextMenu,PZSurvivorToolkit.ActionQueueTidyIntent
 local facts={available=true,roles={},paneMeta=type(pane)=='table'and type(getmetatable(pane))or false,paneFields=0}
 if type(pane)=='table'then
  for _ in pairs(pane)do facts.paneFields=facts.paneFields+1;if facts.paneFields>1000 then facts.paneTruncated=true;break end end
  local ok,watch=pcall(proof.captureBindings,{{owner=pane,keys={'getActualItems'}}})
  facts.paneBinding=ok and type(watch)=='function'and watch()==true
 end
 for _,entry in ipairs({{'selector',pane and pane.getActualItems},{'install',api and api.install},{'poll',api and api.pollOwn},
  {'primary',menu and menu.OnPrimaryWeapon},{'secondary',menu and menu.OnSecondWeapon},{'twoHands',menu and menu.OnTwoHandsEquip},
  {'equip',menu and menu.equipWeapon},{'transfer',menu and menu.transferIfNeeded},
  {'reset',menu and menu.cleanUIResetStaleTimedActionRetrigger},{'log',menu and menu.cleanUILogTimedActionFix}})do
  local role={name=entry[1],kind=type(entry[2])}
  if role.kind=='function'then
   local ok,value=pcall(getFirstLineOfClosure,entry[2]);role.line=ok and value or false
   ok,value=pcall(getFilenameOfClosure,entry[2]);role.filename=ok and type(value)=='string'and value:match('([^/\\]+)$')or false
  end
  facts.roles[#facts.roles+1]=role
 end
 local hashes={
  {'intent','media/lua/client/PZSurvivorToolkit/ActionQueueTidyIntent.lua',442162072,'PZSurvivorToolkit',true},
  {'nativePane','media/lua/client/ISUI/ISInventoryPane.lua',3400657123,false,true},
  {'cleanPane','media/lua/client/ISUI/ISInventoryPane.lua',3716736911,'CleanUI',true},
  {'nativeContext','media/lua/client/ISUI/ISInventoryPaneContextMenu.lua',4293448388},
  {'cleanContext','media/lua/client/ISUI/ISInventoryPaneContextMenu.lua',1953753890}}
 facts.sources={}
 for _,entry in ipairs(hashes)do local ok,value=pcall(proof.matches,entry[2],entry[3],entry[4]or nil,entry[5]);facts.sources[entry[1]]=ok and value==true end
 return facts
end
local function intentCallbacks(profile,action)
 for name,callback in pairs(profile.intentCallbacks or{})do
  assert(action[name]==callback and ISEquipWeaponAction[name]==callback,'explicit native equip callback changed '..name)
 end
end
function C.enqueueIntent(profile,state)
 require 'TimedActions/ISEquipWeaponAction'
 local Ops=require 'PZSurvivorToolkit/ActionQueueOperations'
 local spec=state.ids.items.target;local item=assert(state.player:getInventory():getItemById(spec.id))
 assert(item:getContainer()==state.player:getInventory()and item:getFullType()==spec.type,'explicit intent lost canonical root item')
 profile.intentCallbacks={};for _,name in ipairs({'new','isValid','start','update','perform','complete','getDuration','stop'})do profile.intentCallbacks[name]=ISEquipWeaponAction[name]end
 local action;local add=ISTimedActionQueue.add
 ISTimedActionQueue.add=function(value)
  assert(not action and value.Type=='ISEquipWeaponAction'and value.character==state.player and value.item==item
   and value.primary==true and value.twoHands==false and value.maxTime==50,'explicit native equip producer topology differs')
  intentCallbacks(profile,value);action=value
  profile.controlEvidence.intent={producer='native ISInventoryPaneContextMenu.OnPrimaryWeapon',actionRef=tostring(value),duration=value.maxTime,
   itemId=item:getID(),itemType=item:getFullType(),primary=true,twoHands=false,callbacksUntouched=true,started=false,progress=false,nativeRef=false,events={}}
  profile.intentAction=value
  return add(value)
 end
 local ok,error=pcall(Ops.run,ISInventoryPaneContextMenu.OnPrimaryWeapon,{item},state.player:getPlayerNum())
 ISTimedActionQueue.add=add;assert(ok,error);assert(action,'native explicit equip was not queued')
 profile.controlEvidence.intent.observer=intentStatus(action)
 profile.controlEvidence.intent.installation=installationFacts()
 profile.controlEvidence.accepted=true
end
function C.intentStarted(profile,state,queue,action)
 if action~=profile.intentAction then return end
 intentCallbacks(profile,action)
 local row=profile.controlEvidence.intent
 row.observerAtStart=intentStatus(action)
 local view=PZSurvivorToolkit.ActionQueueSettlement.operationState(profile.pendingReturn and profile.pendingReturn.body or profile.controlBody)
 local loan=false;for _,candidate in ipairs(view and view.borrowings or{})do if candidate.id==state.ids.items.target.id then assert(loan==false);loan=candidate.state end end
 local debt=false;for _,failure in ipairs(PZSurvivorToolkit.ActionQueueExecution.blockedReturns(state.player))do if failure.itemId==state.ids.items.target.id then assert(debt==false);debt=failure end end
 local root=state.player:getInventory();local item=root:getItemById(state.ids.items.target.id)
 row.beforeEffect={loanState=loan,debt=debt,canonicalRoot=item~=nil and action.item==item and item:getContainer()==root,primary=hand(state.player:getPrimaryHandItem())}
 assert(row.beforeEffect.canonicalRoot,'native equip began with a noncanonical root item')
end
function C.observeIntent(profile,state,queue)
 local action=profile.intentAction
 if not action or queue.current~=action or not action:isStarted()then return end
 intentCallbacks(profile,action)
 local row=profile.controlEvidence.intent
 if not row.started then row.started=true;row.startedAt=getTimestampMs();row.nativeRef=tostring(assert(action.action))end
 if action:getJobDelta()>0 then row.progress=true end
end
function C.intentBoundary(profile,state,action,boundary,phase,succeeded)
 if action~=profile.intentAction or(phase~='perform'and phase~='complete')then return end
 intentCallbacks(profile,action)
 local row=profile.controlEvidence.intent
 row.events[#row.events+1]={boundary=boundary,phase=phase,succeeded=succeeded==true,
  nativeRef=action.action and tostring(action.action)or false,primary=hand(state.player:getPrimaryHandItem()),observer=intentStatus(action)}
 return true -- Lifecycle sends matching finish notifications only for an enrolled observer.
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
 profile.controlBody=body
 if evidence.kind=='keep'and not native then
  local toolkit=PZSurvivorToolkit;local decision=toolkit.ActionQueuePolicy.evaluateCancel(queue,returned)
  assert(decision.allowed and decision.mode=='pending-return','pending Keep policy denied '..tostring(decision.reason))
  evidence.policyMode=decision.mode;evidence.accepted=toolkit.ActionQueue.cancel(queue,returned)==true
  assert(evidence.accepted and queue:indexOf(returned)==-1,'pending Keep did not remove exact return')
 elseif evidence.kind=='full'then request('CapacityLost')
 elseif evidence.kind=='unavailable'then request('SourceLost')
 elseif evidence.kind=='intent'then C.enqueueIntent(profile,state)end
 evidence.after=F.snapshot(state)
 evidence.bodyUnchanged=queue.current==body and body.action==nativeAction and body.toolkitQueueOperation==token
 assert(evidence.bodyUnchanged,'return control interrupted or replaced its native wring body')
end
function C.poll(profile,state)
 local evidence=profile.controlEvidence
 if not state or state.ids.returnControl~='unavailable'or not evidence then return true end
 if not evidence.authority then return false end
 if evidence.detachedConfirmed then return true end
 local root=state.player:getInventory();local bag=state.bag;local spec=state.ids.items.target
 local item=root:getItemById(spec.id)
 local proof={bagAbsentRoot=root:getItemById(state.ids.source.bag)==nil,
  bagAbsentWorn=state.player:getWornItems():getItemById(state.ids.source.bag)==nil,
  rootTarget=item~=nil and item:getFullType()==spec.type and item:getContainer()==root,
  sourceRetained=bag:getID()==state.ids.source.bag and bag:getFullType()=='Base.Bag_Military'and bag:getItemContainer()==state.source}
 if not(proof.bagAbsentRoot and proof.bagAbsentWorn and proof.rootTarget and proof.sourceRetained)then return false end
 state.detachedSource=true;evidence.detachedConfirmed=true;evidence.replica=proof;return true
end
function C.sourceAccepted(profile,state,receipt)
 local evidence=assert(profile.controlEvidence,'source receipt without active control');local spec=state.ids.items.target
 assert(evidence.kind=='unavailable'and not evidence.authority and receipt.case==state.ids.case and receipt.itemId==spec.id
  and receipt.itemType==spec.type and receipt.bagId==state.ids.source.bag and receipt.bagType=='Base.Bag_Military'
  and receipt.bagRootBefore==true and receipt.bagWornBefore==true and receipt.bagRootAfter==false and receipt.bagWornAfter==false
  and receipt.root==true and receipt.authority==true and receipt.scope=='detached-retained-fixture-bag','source loss receipt differs')
 evidence.authority=receipt;evidence.accepted=true;C.poll(profile,state)
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
 if not evidence or(evidence.kind=='full'or evidence.kind=='unavailable')and not evidence.authority then return false end
 if not C.poll(profile,state)then return false end
 if #queue.queue>0 or state.player:hasTimedActions()then return false end
 if evidence.kind=='intent'then
  local item=state.player:getInventory():getItemById(state.ids.items.target.id)
  if not item or state.player:getPrimaryHandItem()~=item then return false end
  evidence.finalPrimarySame=true;evidence.blocked=false;evidence.kept=false
  for _,failure in ipairs(PZSurvivorToolkit.ActionQueueExecution.blockedReturns(state.player))do
   if failure.itemId==state.ids.items.target.id then evidence.waitingDebt=failure;return false end
  end
  evidence.waitingDebt=false
 end
 if(evidence.kind=='full'or evidence.kind=='unavailable')and evidence.kept==nil then
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
