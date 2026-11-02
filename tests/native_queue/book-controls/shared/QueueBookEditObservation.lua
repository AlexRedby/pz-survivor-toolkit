-- Test-only opt-in observation at the genuine progressed native reader boundary.
-- No producer, source guard, cart classification or action binding is substituted.
local O={}
local equal,kind,meta,each,pairsOf=rawequal,type,getmetatable,ipairs,pairs
local function ref(value)
 if value==nil then return false end
 local text=tostring(value)
 -- Kahlua dumps mutable table fields after this stable class/address prefix.
 return text:match('^([%a_][%w_]* 0x%x+)')or text
end
local function plain(value)return kind(value)=='table'and meta(value)==nil end
local function source(callback)
 if kind(callback)~='function'or kind(getFilenameOfClosure)~='function'then return false end
 local ok,path=pcall(getFilenameOfClosure,callback)
 return ok and kind(path)=='string'and(path:gsub('\\','/'):match('([^/]+)$')or false)or false
end
local function capture(queue)
 local result={queue=queue,list=queue.queue,current=queue.current,records={},seen={},native=queue.current.action,
  started=queue.current.started,finished=queue.current.action:finished(),forced=queue.current.action:isForceComplete(),ui=UIManager.getUI(),windows={}}
 local function tableRecord(owner)
  if kind(owner)~='table'or result.seen[owner]then return end
  local record={owner=owner,meta=meta(owner),values={},count=0};result.seen[owner]=true
  for key,value in pairsOf(owner)do record.count=record.count+1;assert(record.count<=128,'observation fixture table bound');record.values[key]=value end
  result.records[#result.records+1]=record
 end
 tableRecord(queue);tableRecord(queue.queue)
 for _,action in each(queue.queue)do
  tableRecord(action);tableRecord(action.toolkitQueueOperation);tableRecord(action.toolkitTransferGuard)
  if kind(action.toolkitQueueOperation)=='table'then tableRecord(action.toolkitQueueOperation.toolkitPickups)end
  tableRecord(action.onCompleteArgs);tableRecord(action.queueList)
  for _,group in each(action.queueList or{})do tableRecord(group);tableRecord(group.items)end
 end
 for index=0,result.ui:size()-1 do result.windows[index+1]=result.ui:get(index)end
 return result
end
local function unchanged(before)
 for _,record in each(before.records)do
  if not equal(meta(record.owner),record.meta)then return false end
  local count=0
  for key,value in pairsOf(record.owner)do count=count+1;if count>record.count or not equal(record.values[key],value)then return false end end
  if count~=record.count then return false end
 end
 local queue=before.queue
 if not equal(queue.queue,before.list)or not equal(queue.current,before.current)
  or not equal(queue.current.action,before.native)or queue.current.started~=before.started
  or queue.current.action:finished()~=before.finished or queue.current.action:isForceComplete()~=before.forced then return false end
 local windows=UIManager.getUI()
 if not equal(windows,before.ui)or windows:size()~=#before.windows then return false end
 for index,value in each(before.windows)do if not equal(windows:get(index-1),value)then return false end end
 return true
end
local function ledgerSummary(ledger)
 local result={status=ledger.status,reason=ledger.reason or false,borrowings={},earnedPreparations=0}
 if ledger.status~='observed'then return result end
 result.generation=ledger.generation;result.legacyHints=ledger.legacyHints;result.providersPresent=ledger.providersPresent
 for _,step in each(ledger.steps or{})do
  if step.phase=='prepare'and step.state=='earned'then result.earnedPreparations=result.earnedPreparations+1 end
 end
 for _,loan in each(ledger.borrowings or{})do
  result.borrowings[#result.borrowings+1]={id=loan.id,fullType=loan.fullType,state=loan.state,ambiguous=loan.ambiguous,
   source=ref(loan.source),destination=ref(loan.destination),returning=loan.returning,plannedReturn=ref(loan.plannedReturn),
   sourceOwner=loan.sourceOwner and{id=loan.sourceOwner.id,fullType=loan.sourceOwner.fullType}or false}
 end
 return result
end
local function observedSummary(result)
 local value={status=result.status,reason=result.reason or false,allowedAbsent=result.allowed==nil,
  projection=result.projection and{status=result.projection.status,reason=result.projection.reason or false,
   externalCapacity=result.projection.externalCapacity==true,allowedAbsent=result.projection.allowed==nil}or false,
  returns=0,unresolved=result.unresolved and #result.unresolved or 0}
 for _,node in each(result.nodes or{})do if node.kind=='return'then value.returns=value.returns+1 end end
 return value
end
local function failureDiagnostics(result)
 local value={contractGaps={},nodes={},projectionBlockerType=false,gapsTruncated=false,nodesTruncated=false}
 for index,gap in each(plain(result.contractGaps)and result.contractGaps or{})do
  if index>32 then value.gapsTruncated=true;break end
  if plain(gap)then value.contractGaps[#value.contractGaps+1]={index=gap.index,actionType=gap.actionType or false,reason=gap.reason or false}end
 end
 for index,node in each(plain(result.nodes)and result.nodes or{})do
  if index>32 then value.nodesTruncated=true;break end
  if plain(node)then value.nodes[#value.nodes+1]={kind=node.kind or false,action=ref(node.action),complete=plain(node.edit)and node.edit.complete==true or false}end
 end
 local projection=plain(result.projection)and result.projection
 local blocker=projection and projection.blocker
 if kind(blocker)=='table'then
  value.projectionBlockerType=kind(blocker.Type)=='string'and blocker.Type
   or kind(blocker.action)=='table'and kind(blocker.action.Type)=='string'and blocker.action.Type or false
 end
 return value
end
local function planSummary(result,prototype,item,root,destination,id,fullType,approach)
 local value={kind=result.kind,nodes={}}
 local retained,incomplete=0,0
 for _,node in each(result.nodes or{})do
  local complete=plain(node.edit)and node.edit.complete==true
  if approach and equal(node.action,approach)then
   incomplete=incomplete+1
   assert(node.kind=='pending'and node.edit==nil,'owned deferred approach unexpectedly acquired an effect contract')
  else assert(complete,'device-only plan contains another incomplete effect')end
  local summary={kind=node.kind,action=ref(node.action),complete=complete,capacity=node.edit and node.edit.capacity or false}
  if prototype and equal(node.action,prototype)then
   retained=retained+1
   local edit=node.edit;local resource=plain(edit.resources)and edit.resources[1]
   assert(node.kind=='pending'and edit.version==1 and edit.capacity=='external'and #edit.resources==1
    and plain(resource)and resource.domain=='item'and resource.key==id and plain(resource.facts)
    and equal(resource.facts.item,item)and equal(resource.facts.location,root),'retained native return item/location resource differs')
   assert(plain(resource.requires)and #resource.requires==1 and plain(resource.requires[1])and resource.requires[1].field=='location'
    and equal(resource.requires[1].equal,root),'retained native return root precondition differs')
   assert(plain(resource.effects)and #resource.effects==1 and plain(resource.effects[1])and resource.effects[1].field=='location'
    and equal(resource.effects[1].set,destination),'retained native return destination effect differs')
   summary.returnEffect={version=1,complete=true,capacity='external',domain='item',id=id,fullType=fullType,
    item=ref(item),source=ref(root),destination=ref(destination),action=ref(prototype),synthetic=false,
    resources=1,requirements=1,effects=1,field='location'}
  end
  value.nodes[#value.nodes+1]=summary
 end
 assert(retained==(prototype and 1 or 0),'retained native return absent or duplicated in preempt plan')
 assert(incomplete==(approach and 1 or 0),'owned deferred approach missing or duplicated in preempt plan')
 return value
end
local function descriptor(result,item,root,destination,id,fullType)
 assert(result.status=='observed'and result.allowed==nil,'active observer did not reach its typed transition')
 local found
 for _,node in each(result.nodes or{})do if node.kind=='return'then assert(not found,'ambiguous virtual return');found=node end end
 assert(found,'earned private loan has no virtual return')
 assert(found.action==nil and found.synthetic==true and equal(found.item,item)and found.id==id
  and found.fullType==fullType and equal(found.source,root)and equal(found.destination,destination),'virtual return changed its exact physical owner/endpoints')
 local edit=found.edit
 -- A detached same-ID native member can make the exact effect unsupported.
 -- Preserve the observed outcome and continue the read-only checks.
 if edit==nil then return nil,'virtual-return-effect-unavailable' end
 assert(plain(edit)and edit.version==1 and edit.complete==true and edit.capacity=='external'
  and plain(edit.resources)and #edit.resources==1,'virtual return has no complete external-capacity effect descriptor')
 local resource=edit.resources[1]
 assert(plain(resource)and resource.domain=='item'and resource.key==id and plain(resource.facts)
  and equal(resource.facts.item,item)and equal(resource.facts.location,root),'virtual return item/location facts differ')
 assert(plain(resource.requires)and #resource.requires==1 and plain(resource.requires[1])and resource.requires[1].field=='location'
  and equal(resource.requires[1].equal,root),'virtual return precondition differs')
 assert(plain(resource.effects)and #resource.effects==1 and plain(resource.effects[1])and resource.effects[1].field=='location'
  and equal(resource.effects[1].set,destination),'virtual return is not one exact source-to-destination location effect')
 assert(not result.projection or result.projection.allowed==nil,'resource projection acquired edit permission')
 return{version=edit.version,complete=true,capacity='external',domain='item',id=id,fullType=fullType,item=ref(item),source=ref(root),destination=ref(destination),
  actionAbsent=true,synthetic=true,resources=1,requirements=1,effects=1,field='location'}
end
local function distribution(values)
 local sorted,total={},0
 for index,value in each(values)do sorted[index]=value;total=total+value end
 table.sort(sorted)
 return{samplesMs=values,samples=#values,minMs=sorted[1],medianMs=sorted[math.floor(#sorted/2)+1],maxMs=sorted[#sorted],meanMs=total/#sorted}
end
function O.run(context)
 local T,queue,front,state=context.toolkit,context.queue,context.front,context.state
 local fixture,clock=context.fixture,context.clock
 local deviceOnly=context.deviceOnly==true
 local demote=context.control=='demote-reader'
 local movingAction=demote and front or context.volume
 local movingTarget=demote and context.volume or front
 local receipt={schema=deviceOnly and not context.native and 2 or 1,case=context.case,kind=context.kind,mode=context.mode,queueEnabled=not context.native,
  scope=deviceOnly and(not context.native and'active-edit-device-only-approach-observation'or'active-edit-device-only-preempt-observation')or'active-edit-native-return-effect-observation',mutationAuthorized=false,permissionsMeasured=false,
  current=ref(front),currentNative=ref(front.action),currentLuaStartedPresent=front.started~=nil,currentLuaStarted=front.started==true,
  liveItem=ref(state.front),source=context.ids.source,
  observer=false,existingDecision=false,ledgerBefore=false,ledgerAfter=false,nativeFacts=false,aliasFacts=false,prototype=false,
  effect=false,qualifiedReturn=false,readOnly=false,uiUnchanged=false,performance=false,passed=false}
 local before,worldBefore
 local ok,problem=pcall(function()
  assert(context.control=='header-cancel'and not deviceOnly or deviceOnly and(context.control=='move-volume'or demote)and context.volume,'active edit observation requires its declared genuine control boundary')
  assert(kind(clock)=='function'and context.precise==true,'active edit observation requires the source-bound native monotonic clock')
  assert(equal(queue.current,front)and equal(queue.queue[1],front)and front.action,'genuine active native reader missing')
  assert(front.item:getID()==context.ids.front.id and front.item:getFullType()==context.ids.front.type,'current reader identity changed')
  receipt.nativeStarted=front.action:isStarted();receipt.nativeFinished=front.action:finished();receipt.nativeForceComplete=front.action:isForceComplete()
  assert(receipt.nativeStarted==true and receipt.nativeFinished==false and receipt.nativeForceComplete==false,'current native reader checkpoint unavailable')
  local policy,settlement=T.ActionQueuePolicy,T.ActionQueueSettlement
  local observe,evaluate,ledger=policy.observeActiveEdit,deviceOnly and policy.evaluateMove or policy.evaluateCancel,settlement.editLedger
  local primitive,aliasPrimitive=toolkitLeafTransferFacts,toolkitLeafTransferAliasFacts
  assert(kind(observe)=='function'and source(observe)=='ActionQueuePolicy.lua'and kind(ledger)=='function'
   and source(ledger)=='ActionQueueSettlement.lua','source-owned observation/ledger API missing')
  local root=state.player:getInventory()
  worldBefore=fixture.snapshot(state);before=capture(queue)
  local initialLedger=ledger(queue,front);receipt.ledgerBefore=ledgerSummary(initialLedger)
  local prototype,member,approach,approachIndex
  for index=2,#queue.queue do
   local action=queue.queue[index]
   if action.toolkitQueueOperation==front.toolkitQueueOperation and action.Type=='ISInventoryTransferAction'
    and action.item and action.item:getID()==context.ids.front.id and action.allowMissingItems==true then
    assert(not prototype,'duplicate native optional-return prototype');prototype=action
   end
  end
  if prototype then
   member=prototype.queueList and prototype.queueList[1]and prototype.queueList[1].items and prototype.queueList[1].items[1]
   receipt.prototype={action=ref(prototype),item=ref(prototype.item),member=ref(member),liveItem=ref(state.front),
    sameItemReference=equal(prototype.item,state.front),sameMemberReference=equal(member,state.front),
    itemId=prototype.item:getID(),itemType=prototype.item:getFullType(),source=ref(prototype.srcContainer),destination=ref(prototype.destContainer),
    stopSource=source(prototype.stop),performSource=source(prototype.perform),constructorSource=source(ISInventoryTransferAction.new),
    allowMissingItems=prototype.allowMissingItems==true,pending=prototype.action==nil and not prototype.started}
  end
  if deviceOnly and not context.native then
   for index,action in each(queue.queue)do
    if action.Type=='ISQueueActionsAction'and action.toolkitQueueOperation==context.volume.toolkitQueueOperation then
     assert(not approach,'duplicate deferred approach in native volume operation');approach,approachIndex=action,index
    end
   end
   assert(approach and approach.toolkitQueueApproach==true and T.ActionQueueApproach
    and source(T.ActionQueueApproach.isAction)=='ActionQueueApproach.lua'and T.ActionQueueApproach.isAction(approach)==true,
    'genuine owned deferred native volume approach missing')
  end
  receipt.sources={observer=source(observe),cleanup=source(settlement.observeEditCleanup),
   bulk=T.BulkActions and source(T.BulkActions.transferBinding)or false,
   compat=T.ActionQueueCompat and source(T.ActionQueueCompat.transferBinding)or false,
   carts=T.ActionQueueCarts and source(T.ActionQueueCarts.transferBinding)or false,
   transferConstructor=source(ISInventoryTransferAction.new),transferPerform=source(ISInventoryTransferAction.perform),
   nativeAlias=kind(aliasPrimitive)=='function'}
  if not deviceOnly and not context.native and context.ids.source~='root'then
   assert(initialLedger.status=='observed'and #initialLedger.borrowings==1,'genuine native-earned private borrowing ledger missing')
   local loan=initialLedger.borrowings[1]
   assert(loan.id==context.ids.front.id and loan.fullType==context.ids.front.type and loan.state=='active'
    and loan.ambiguous==false and loan.returning==false and loan.plannedReturn==nil
    and equal(loan.source,state.source)and equal(loan.destination,root),'borrowed book private ownership is not the original active loan')
   assert(receipt.ledgerBefore.earnedPreparations>0 and context.pickupEarned==true,'pickup has no genuine native earned preparation evidence')
   assert(prototype and prototype.action==nil and not prototype.started,'real native optional return is not pending')
   assert(equal(prototype.item,state.front),'native return prototype item changed')
   assert(kind(primitive)=='function','native leaf facts primitive missing')
   local facts=primitive(state.player,state.front,root,state.source,context.ids.front.id,context.ids.front.type)
   receipt.nativeFacts=plain(facts)and{scope='independent-native-value-probe',schema=facts.schema,item=ref(facts.item),source=ref(facts.source),destination=ref(facts.destination),
    destinationOwner=ref(facts.destinationOwner),destinationOwnerFullType=facts.destinationOwnerFullType or false,
    primaryKnown=facts.primaryItemContainerKnown,primaryFullType=facts.primaryFullType or false}or false
   assert(plain(facts)and facts.schema==2 and equal(facts.item,state.front)and equal(facts.source,root)
    and equal(facts.destination,state.source),'direct native physical facts unavailable (no action/replica rebinding is permitted)')
   if not equal(member,state.front)then
    local alias
    if kind(aliasPrimitive)=='function'then alias=aliasPrimitive(state.player,state.front,root,state.source,context.ids.front.id,context.ids.front.type,member)end
    if alias==nil then receipt.unsupported='native-alias-facts-unavailable'
    else
     assert(plain(alias)and alias.schema==2 and equal(alias.item,state.front)and equal(alias.source,root)
      and equal(alias.destination,state.source)and equal(alias.aliasMember,member)and alias.aliasResolution=='native-root-id',
      'native detached member alias facts malformed')
     receipt.aliasFacts={scope='independent-native-alias-probe',schema=alias.schema,item=ref(alias.item),source=ref(alias.source),
      destination=ref(alias.destination),aliasMember=ref(alias.aliasMember),aliasResolution=alias.aliasResolution}
    end
   end
  end
  local intent=deviceOnly and{kind='move',action=movingAction,target=movingTarget,after=demote}or{kind='cancel',action=front,whole=true}
  if deviceOnly then receipt.intent={kind='move',action=ref(movingAction),target=ref(movingTarget),after=demote}end
  local function existing()
   local result
   if deviceOnly then result=evaluate(queue,movingAction,movingTarget,demote)else result=evaluate(queue,front,true)end
   assert(plain(result)and kind(result.allowed)=='boolean','existing whole-operation decision missing')
   return result
  end
  local function observation()
   local result=observe(queue,intent)
   assert(plain(result)and result.allowed==nil and(not result.projection or result.projection.allowed==nil),'observation granted an edit permission')
   return result
  end
  local started=clock();local baseline=existing();local baselineFirst=clock()-started
  started=clock();local result=observation();local observerFirst=clock()-started
  receipt.existingDecision={entrypoint=deviceOnly and'Policy.evaluateMove'or'Policy.evaluateCancel',allowed=baseline.allowed,reason=baseline.reason or false,whole=not deviceOnly}
  if deviceOnly then receipt.existingDecision.commonActiveEdit=baseline.commonActiveEdit==true end
  receipt.observer=observedSummary(result)
  if deviceOnly then receipt.diagnostics=failureDiagnostics(result)end
  if deviceOnly then
   receipt.plan=false
   if context.native then
    assert(result.status=='unhandled'and not result.projection,'queue-off move observer acquired a plan');receipt.control='queue-disabled'
   else
    assert(result.status=='observed'and result.kind=='preempt'and result.projection and result.projection.status=='unhandled'
     and result.projection.reason=='edit_unknown'and #result.unresolved==0,'deferred native approach must keep common projection unknown')
    assert(baseline.allowed and not baseline.commonActiveEdit,'device-only move must use existing legacy authority')
    local gaps=receipt.diagnostics.contractGaps
    assert(#gaps==1 and gaps[1].index==approachIndex and gaps[1].actionType=='ISQueueActionsAction'and gaps[1].reason=='effects_unproven'
     and receipt.diagnostics.projectionBlockerType=='ISQueueActionsAction'and not receipt.diagnostics.gapsTruncated and not receipt.diagnostics.nodesTruncated,
     'common projection has an unexpected effect gap')
    receipt.plan=planSummary(result,prototype,state.front,root,state.source,context.ids.front.id,context.ids.front.type,approach)
   end
  elseif context.native then
   assert(result.status=='unhandled'and receipt.observer.returns==0,'queue-off observer acquired a virtual operation')
   receipt.control='queue-disabled'
  elseif context.ids.source=='root'then
   assert(initialLedger.status=='observed'and #initialLedger.borrowings==0,'root control acquired a borrowing debt')
   assert(result.status=='observed'and receipt.observer.returns==0,'root control acquired a synthetic return')
   receipt.control='no-loan'
  else
   local effect,unsupported=descriptor(result,state.front,root,state.source,context.ids.front.id,context.ids.front.type)
   receipt.effect=effect or false;receipt.descriptorUnsupported=unsupported or false
   receipt.unsupported=receipt.unsupported or unsupported or false
   receipt.qualifiedReturn=effect~=nil and not receipt.unsupported
  end
  -- Same actual declared intent and unchanged live producer state. Outputs
  -- differ: legacy authority versus declarative effect observation. These are
  -- paired entrypoint diagnostics, never a complete edit/frame performance gate.
  existing();observation() -- one warm-up pair, no replayed edit or input handler
  local baselineTimes,observerTimes={},{}
  for index=1,3 do
   local a,b
   if index%2==1 then
    started=clock();a=existing();baselineTimes[index]=clock()-started
    started=clock();b=observation();observerTimes[index]=clock()-started
   else
    started=clock();b=observation();observerTimes[index]=clock()-started
    started=clock();a=existing();baselineTimes[index]=clock()-started
   end
   assert(a.allowed==baseline.allowed and a.reason==baseline.reason,'existing cancellation decision changed in paired bank')
   if deviceOnly and not context.native then
    assert(not a.commonActiveEdit and fixture.same(failureDiagnostics(b),receipt.diagnostics)and fixture.same(planSummary(b,prototype,state.front,root,state.source,context.ids.front.id,context.ids.front.type,approach),receipt.plan),'device-only legacy authority or exact approach gap changed in paired bank')
   end
   local summary=observedSummary(b)
   assert(fixture.same(summary,receipt.observer),'active observation result changed in paired bank')
   if not deviceOnly and not context.native and context.ids.source~='root'then
    local effect,unsupported=descriptor(b,state.front,root,state.source,context.ids.front.id,context.ids.front.type)
    assert((effect~=nil)==(receipt.effect~=false) and (unsupported or false)==receipt.descriptorUnsupported,'virtual return qualification changed in paired bank')
   end
   assert(unchanged(before),'paired observations changed queue/UI or action/native bindings')
  end
  local comparable=not deviceOnly and receipt.qualifiedReturn and baseline.allowed and result.status=='observed'
  receipt.performance={scope=deviceOnly and'paired-live-device-preempt-entrypoints'or'paired-live-header-return-entrypoints',timer='System.nanoTime',units='ms',warmupPairs=1,pairs=3,
   sameLiveIntent=true,whole=not deviceOnly,firstUseScope='first-call-after-untimed-identity-ledger-and-native-facts-diagnostics',
   baseline=distribution(baselineTimes),observer=distribution(observerTimes),baselineFirstMs=baselineFirst,observerFirstMs=observerFirst,
   comparable=comparable,comparisonReason=comparable and(deviceOnly and'complete-device-projection-and-existing-move-success'or'useful-return-effect-layer-and-existing-cancel-success')
    or receipt.control or deviceOnly and'approach-effects-unproven'or'existing-cancel-denied-or-observer-unknown',
   observerProjectionStatus=receipt.observer.projection and receipt.observer.projection.status or false,
   observerProjectionReason=receipt.observer.projection and receipt.observer.projection.reason or false,
   timerOverhead='included-not-subtracted',sameOutputContract=false,completeEditMeasured=false,frameLoadMeasured=false,
   positiveTimingClaim=false,assessment='not-assessed'}
  receipt.ledgerAfter=ledgerSummary(ledger(queue,front))
  assert(fixture.same(receipt.ledgerBefore,receipt.ledgerAfter),'observation changed private debt/earned-step disposition')
  assert(equal(policy.observeActiveEdit,observe)and equal(deviceOnly and policy.evaluateMove or policy.evaluateCancel,evaluate)and equal(settlement.editLedger,ledger)
   and equal(toolkitLeafTransferFacts,primitive)and equal(toolkitLeafTransferAliasFacts,aliasPrimitive),'observation replaced a production entrypoint')
 end)
 if before then
  local checked,stable=pcall(function()return unchanged(before)and fixture.same(worldBefore,fixture.snapshot(state))end)
  receipt.readOnly=checked and stable or false;receipt.uiUnchanged=receipt.readOnly
  if not receipt.readOnly then ok=false;problem='active edit observation changed queue/UI/item/hands/worn/page state'end
 end
 receipt.passed=ok and not receipt.unsupported
 if not ok then receipt.failure=tostring(problem)elseif receipt.unsupported then receipt.failure=receipt.unsupported else receipt.failure=false end
 return receipt
end
return O
