local Completion={}
function Completion.observe(toolkit,selection)
 local lifecycle,operations=toolkit.ActionQueueLifecycle,toolkit.ActionQueueOperations
 local begin,finish,flush,perform,defer=lifecycle.begin,lifecycle.finish,lifecycle.flush,operations.perform,operations.deferCompletion
 local state,records,counts,restores,proofs
 local settlement,acks=toolkit.ActionQueueSettlement,toolkit.ActionQueueAcknowledgements
 local captureEffect,confirmEffect=settlement.captureEffect,settlement.confirmEffect
 local beginReturn,finishReturn,returnState=settlement.beginReturn,settlement.finishReturn,settlement.returnState
 local returns={}
 local groupNative,groupItems,groupObligations,groupAttempts={}, {},0,{}
 local groupFailure
 local function grouped() return state and (state.id=='tidy-group' or state.id=='tidy-multigroup') end
 local function members()
  return {state.groupOne,state.groupTwo,state.groupHeavyOne,state.groupHeavyTwo}
 end
 local function expectedMembers()
  local result={};for _,item in ipairs(members()) do result[item:getID()]=item:getFullType() end;return result
 end
 local enabled=selection.mode=='toolkit'
 local returnItems=settlement.returnItems
 local tidyIntent=toolkit.ActionQueueTidyIntent
 local groupObserver=tidyIntent and tidyIntent.observeTransfers
 local groupObserverBound=false
 if groupObserver then
  -- Subscribe after compatibility preload; protected native helper identity stays intact.
  groupObserver(function(action)
   if not grouped() or action.srcContainer~=state.root or action.destContainer~=state.source or groupFailure then return end
   -- Never assert or throw across native merge: Kahlua logs even caught assertions.
   local function observe()
    local groups=action.queueList
    local prior=groupNative[action]
    if type(groups)~='table' or #groups>4 or #groups==0 and not prior then return 'unexpected bounded native group shape' end
    local expected,ids,seen=expectedMembers(),{},{}
    for _,group in ipairs(groups) do
     if type(group.items)~='table' or #group.items<1 or #group.items>2 then return 'unexpected native group size' end
     local values={}
     for _,item in ipairs(group.items) do
      local id=item:getID()
      if seen[id] or expected[id]~=item:getFullType() then return 'unexpected native group member' end
      if #group.items>1 and item:getWeight()>0.1 then return 'native merged heavy item' end
      seen[id]=true;values[#values+1]=id
     end
     table.sort(values);ids[#ids+1]=values
    end
    if not prior then
     local total=0;for _ in pairs(seen) do total=total+1 end
     local multi=state.id=='tidy-multigroup'
     local expectedCount=multi and 4 or 2
     if total~=(enabled and expectedCount or 1) then return 'native group omitted borrowed item' end
     groupNative[action]=ids
    else
     local original={};for _,values in ipairs(prior) do for _,id in ipairs(values) do original[id]=true end end
     for id in pairs(seen) do if not original[id] then return 'native continuation changed group membership' end end
    end
   end
   local ok,problem=pcall(observe)
   if not ok or problem then groupFailure='P4 return group observation failed: '..tostring(problem) end
   print('[EQUIPMENT_TEST] GROUP_OBSERVED case='..state.id..' mode='..selection.mode..' groups='..tostring(action.queueList and #action.queueList)..' valid='..tostring(ok and not problem))
  end)
  groupObserverBound=true
 end
 settlement.captureEffect=function(action)
  local proof=captureEffect(action)
  if state then
   local required=isClient() and (action.toolkitNativeTransaction~=nil or action.toolkitNativeKind~=nil)
   proofs[proof]={action=action,receipt=acks.capture(action),required=required}
   print('[EQUIPMENT_TEST] EFFECT_CAPTURE case='..state.id..' type='..action.Type..' required='..tostring(required)
    ..' receipt='..tostring(proofs[proof].receipt and proofs[proof].receipt.state))
  end
  return proof
 end
 settlement.confirmEffect=function(proof,observedEffect)
  local confirmed=confirmEffect(proof,observedEffect)
  local record=proofs and proofs[proof]
  if confirmed and record then
   assert(observedEffect==true and not record.confirmed,'explicit native effect confirmed twice or without effect')
   print('[EQUIPMENT_TEST] EFFECT_CONFIRMED case='..state.id..' type='..record.action.Type..' required='..tostring(record.required))
   record.confirmed=true;counts.explicitConfirmed=counts.explicitConfirmed+1
   if record.required then
    assert(record.receipt and acks.observe(record.action,record.receipt)=='completed',
     'explicit network intent confirmed without its captured authoritative completion')
    counts.authoritativeIntent=counts.authoritativeIntent+1
   end
  end
  return confirmed
 end
 if beginReturn and finishReturn and returnState then
  settlement.beginReturn=function(action,obligation,guard)
   local accepted,reason=beginReturn(action,obligation,guard)
   if state then
    local groups=action.queueList
    print('[EQUIPMENT_TEST] RETURN_CAPTURE accepted='..tostring(accepted)..' reason='..tostring(reason)
     ..' groups='..tostring(groups and #groups)..' items='..tostring(groups and groups[1] and #groups[1].items)
     ..' native='..tostring(action.action~=nil)..' current='..tostring(ISTimedActionQueue.queues[action.character].current==action))
   end
   if state and accepted then
    assert(obligation~=nil and (state.id=='tidy-multigroup' or not returns[obligation]),'duplicate or missing native return obligation')
    local transaction=action.transactionId
    local authoritative=isClient() and type(transaction)=='number' and transaction~=0
     and isItemTransactionDone(transaction)==true and isItemTransactionRejected(transaction)==false
    local record=returns[obligation]
    if record then assert(record.action==action,'P4 obligation changed executor')
    else record={action=action,authoritative=authoritative,observed=false,accepted=0};returns[obligation]=record end
    record.accepted=record.accepted+1
    record.authoritative=record.authoritative and authoritative
   end
   return accepted
  end
  settlement.finishReturn=function(obligation,succeeded)
   local finished=finishReturn(obligation,succeeded)
   return finished
  end
 end
 local function observed(action)
  if not state or not action then return end
  if grouped() and records and records[action] then return records[action].counts end
  local kind=select(2,toolkit.ActionQueueDefinitions.inspect(action))
  if kind=='compat.tidy-transfers' then return counts end
  if kind=='compat.tidy-equipment' then return restores end
 end
 local function retained(action,record)
  local queue=ISTimedActionQueue.queues[action.character]
  assert(queue and queue.current==action and queue.queue[1]==action
   and action.action==record.native and action.toolkitQueueOperation==record.token,
   'Tidy transfer lost its native parent or operation')
  local id=action.item:getID()
  local exact=grouped() and record.counts==counts
   and expectedMembers()[id]==action.item:getFullType()
   or id==record.id and action.item:getFullType()==record.kind
  assert(exact
   and (record.counts~=counts or action.srcContainer==state.root and action.destContainer==state.source),
   'Tidy transfer changed its exact item or endpoints')
 end
 lifecycle.begin=function(action,phase)
  local active=begin(action,phase)
  local counter=observed(action)
  if not counter then return active end
  assert(active==enabled,'wrong native Tidy completion boundary mode')
  if not active then return active end
  assert(lifecycle.current(action.character)==action and action.action,'Tidy transfer has no active native scope')
  local record=records[action]
  if phase=='perform' then
   assert(not record or state.id=='tidy-multigroup' and record.counts==counts and not record.flushed
    and record.perform=='finished' and (selection.kind=='mp' or record.complete=='finished'),'duplicate native Tidy perform')
   local id=action.item:getID()
   assert(state.baseline[id] and state.baseline[id]:getFullType()==action.item:getFullType(),
    'Tidy transfer returned an unexpected exact item')
   if record then
    retained(action,record);record.perform=nil;record.complete=nil
   else record={id=id,kind=action.item:getFullType(),native=action.action,token=action.toolkitQueueOperation,counts=counter,cycles=0} end
   record.cycles=record.cycles+1
   if counter==restores then
    local primary=action.item:getID()==state.hammer:getID() and action.item:getFullType()==state.hammer:getFullType()
    assert(action.Type=='ISUnequipAction' and state.id=='tidy-empty-hands' and action.item:getID()==state.pickup:getID()
     or primary or action.item:getID()==state.screwdriver:getID() and action.item:getFullType()==state.screwdriver:getFullType(),
     'P4 restored unexpected equipment')
    local queue=ISTimedActionQueue.queues[action.character]
    local decision=toolkit.ActionQueuePolicy.evaluateCancel(queue,action,true)
    assert(not decision.allowed,'shared equipment cleanup must remain protected')
    if action.Type=='ISEquipWeaponAction' then
     assert(action.primary==primary and not action.twoHands,'P4 restored wrong hand slots')
     restores.equip=restores.equip+1
    elseif action.Type=='ISUnequipAction' then
     local held=action.character:getPrimaryHandItem()
     -- Host may replicate the authoritative unequip before the client performs its UI cleanup.
     assert(not action.character:getSecondaryHandItem() and (held==action.item or selection.kind=='mp' and not held),
      'P4 removed wrong temporary equipment')
     restores.unequip=restores.unequip+1
    else
     assert(action.Type=='P4RestoreAction' and action.activated==primary,'P4 restored wrong activation')
     restores.activation=restores.activation+1
    end
   end
   records[action]=record
  else
   assert(phase=='complete' and selection.kind=='sp' and record and record.perform=='finished',
    'Tidy complete preceded perform or ran on the Host client')
  end
  retained(action,record)
  assert(not record[phase],'duplicate native Tidy completion phase');record[phase]='begun'
  return active
 end
 lifecycle.finish=function(action,phase,succeeded)
  local record=records and records[action]
  if record then
   retained(action,record)
   assert(record[phase]=='begun' and succeeded,'Tidy completion phase did not finish once')
  end
  finish(action,phase,succeeded)
  if record then record[phase]='finished';record.counts[phase]=record.counts[phase]+1 end
 end
 lifecycle.flush=function(queue)
  local action=queue.current
  local record=records and records[action]
  local absent=record and not queue.character:getCharacterActions():contains(record.native)
  local outcome,finished=flush(queue)
  if record and outcome=='completed' then
   assert(finished==action and absent and not record.flushed and record.perform=='finished'
    and (selection.kind=='mp' or record.complete=='finished'),
    'Tidy transfer flushed before native completion/removal or twice')
   record.flushed=true;record.counts.flush=record.counts.flush+1
  end
  return outcome,finished
 end
 operations.perform=function(action,callback,...)
  return perform(action,function(parent,...)
   if observed(parent) and lifecycle.current(parent.character)==parent then
    local queue=ISTimedActionQueue.queues[parent.character]
    if defer(queue,parent) then
     local counter=observed(parent);counter.legacy=counter.legacy+1
     error('Tidy transfer used legacy completion inside its native scope')
    end
   end
   return callback(parent,...)
  end,...)
 end
 function Completion.watch(value)
  local available,reason,subject=toolkit.ActionQueueTidyIntent.status()
  print('[EQUIPMENT_TEST] INTENT_STATUS available='..tostring(available)..' reason='..tostring(reason)..' subject='..tostring(subject))
  local carts=toolkit.ActionQueueCarts
  if carts then
   local valid,problem=carts.status()
   print('[EQUIPMENT_TEST] INTENT_CART_STATUS available='..tostring(valid)..' reason='..tostring(problem))
  end
  print('[EQUIPMENT_TEST] INTENT_CART installed='..tostring(toolkit.ActionQueueCompat.isInstalled('SaucedCartsTransfers'))
   ..' transfer='..tostring(carts and carts.isTransferConstructor(ISInventoryTransferAction.new))
   ..' unequip='..tostring(carts and carts.isUnequipConstructor(ISUnequipAction.new)))
  if (value.id=='tidy-group' or value.id=='tidy-multigroup') and getActivatedMods():contains('P4TidyUpMeister') then
   assert(groupObserverBound,'P4 group native merge observer subscription unavailable')
  end
  if value.id=='hands-chain' then assert(available,'explicit hand intent integration unavailable: '..tostring(reason)..':'..tostring(subject)) end
  print('[EQUIPMENT_TEST] INTENT_ADAPTER installed='..tostring(toolkit.ActionQueueCompat.isInstalled('P4TidyUpMeister'))..' sources='..tostring(toolkit.ActionQueueCompat.verifySources('P4TidyUpMeister')))
  for _,entry in ipairs({{ISInventoryPaneContextMenu,'OnTwoHandsEquip'},{ISInventoryPaneContextMenu,'OnPrimaryWeapon'},
   {ISInventoryPaneContextMenu,'equipWeapon'},{ISInventoryPane,'getActualItems'}}) do
   print('[EQUIPMENT_TEST] INTENT_CALLBACK '..entry[2]..' source='..tostring(getFilenameOfClosure(entry[1][entry[2]])))
  end
  state,records,proofs,counts=value,{},{},{perform=0,complete=0,flush=0,legacy=0,explicitConfirmed=0,authoritativeIntent=0,
   cleanupConfirmed=0,authoritativeCleanup=0}
  returns={}
  groupNative,groupItems,groupObligations,groupAttempts={},{},0,{}
  groupFailure=nil
  restores={perform=0,complete=0,flush=0,legacy=0,equip=0,activation=0,unequip=0}
 end
 function Completion.settled()
  assert(not groupFailure,groupFailure)
  for obligation,record in pairs(returns) do
   assert(not record.observed and returnState(obligation)=='completed','native return obligation did not complete exactly once')
   record.observed=true
   local items=assert(returnItems and returnItems(obligation),'native return item snapshot unavailable')
   assert(type(items)=='table' and #items>=1,'native return item snapshot empty')
   local seen={}
   for _,item in ipairs(items) do
    assert(type(item.id)=='number' and not seen[item.id] and item.state=='completed'
     and state.baseline[item.id] and state.baseline[item.id]:getFullType()==item.fullType,
     'native return item did not complete exact identity once')
    seen[item.id]=true;counts.cleanupConfirmed=counts.cleanupConfirmed+1
    if record.authoritative then counts.authoritativeCleanup=counts.authoritativeCleanup+1 end
    if grouped() then groupItems[#groupItems+1]={id=item.id,fullType=item.fullType,state=item.state} end
   end
   if grouped() then
    local multi=state.id=='tidy-multigroup'
    assert(#items==(multi and 4 or 2),'bounded P4 obligation lost group members');groupObligations=groupObligations+1
    if multi then
     local attempts=assert(settlement.returnAttempts and settlement.returnAttempts(obligation),'P4 attempt history unavailable')
     assert(record.accepted==3 and #attempts==3,'P4 multi-group attempt history did not cover every perform')
     local seen={}
     for ordinal,attempt in ipairs(attempts) do
      assert(attempt.ordinal==ordinal and attempt.phase=='perform' and attempt.state=='completed'
       and attempt.authority==(selection.kind=='mp' and 'completed' or 'native'),'P4 attempt completion or ordinal differs')
      if selection.kind=='mp' then
       assert(type(attempt.transaction)=='number' and attempt.transaction~=0,
        'P4 Host attempt lost its captured native transaction')
      else assert(attempt.transaction==0,'P4 SP attempt acquired a Host transaction') end
      for _,item in ipairs(attempt.items) do
       assert(not seen[item.id] and expectedMembers()[item.id]==item.fullType and item.state=='completed','P4 attempt repeated or lost an exact member')
       seen[item.id]=true
      end
      groupAttempts[#groupAttempts+1]=attempt
     end
     for id in pairs(expectedMembers()) do assert(seen[id],'P4 attempt ledger omitted exact item') end
    end
   end
  end
  if state.id=='hands-chain' then
   assert(counts.explicitConfirmed==3 and counts.authoritativeIntent==(selection.kind=='mp' and 3 or 0),
    'manual hand chain did not confirm all exact explicit native effects: explicit='..counts.explicitConfirmed..' authoritative='..counts.authoritativeIntent)
  end
  assert(counts.perform==counts.flush+(state.id=='tidy-multigroup' and enabled and getActivatedMods():contains('P4TidyUpMeister') and 2 or 0) and counts.complete==(selection.kind=='sp' and counts.perform or 0)
   and counts.legacy==0,'Tidy native completion counts did not settle')
  for _,record in pairs(records) do assert(record.flushed,'Tidy transfer never flushed') end
  return counts
 end
 function Completion.group()
  local tidy=getActivatedMods():contains('P4TidyUpMeister')
  assert(not groupFailure,groupFailure)
  local groups,nativeItems,seen,sizes,executors=0,0,{},{},0
  for _,nativeGroups in pairs(groupNative) do
   executors=executors+1
   for _,ids in ipairs(nativeGroups) do
    groups=groups+1;sizes[#sizes+1]=#ids
    for _,id in ipairs(ids) do assert(not seen[id],'P4 native groups repeated exact item');seen[id]=true;nativeItems=nativeItems+1 end
   end
  end
  local multi=state.id=='tidy-multigroup'
  local total=multi and 4 or 2
  assert(groups==(tidy and (enabled and (multi and 3 or 1) or total) or 0),'P4 native return group count differs')
  assert(nativeItems==(tidy and total or 0),'P4 native groups omitted exact item')
  table.sort(sizes)
  assert(groupObligations==(tidy and enabled and 1 or 0),'P4 return obligation group count differs')
  assert(#groupItems==(tidy and enabled and total or 0),'P4 per-item completion snapshot incomplete')
  table.sort(groupItems,function(a,b)return a.id<b.id end)
  local expected={};for id in pairs(expectedMembers()) do expected[#expected+1]=id end;table.sort(expected)
  for i,item in ipairs(groupItems) do assert(item.id==expected[i],'P4 completed wrong grouped return ID') end
  local items={}
  for _,id in ipairs(expected) do items[#items+1]={id=id,fullType=expectedMembers()[id],container=tidy and 'worn-bag' or 'root'} end
  local result={nativeGroups=groups,nativeItems=nativeItems,groupSizes=sizes,obligationGroups=groupObligations,completedItems=groupItems,items=items,unrelatedTailPreserved=true}
  if multi then
   assert(executors==(tidy and (enabled and 1 or 4) or 0),'P4 multi-group changed native executor')
   result.executorCount=executors;result.attempts=groupAttempts
   result.sameNativeExecutor=true
  end
  return result
 end
 function Completion.restores()
  assert(restores.flush==restores.perform and restores.complete==(selection.kind=='sp' and restores.perform or 0)
   and restores.legacy==0,'P4 equipment completion did not settle')
  return restores
 end
 return Completion
end
return Completion
