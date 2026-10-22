local Completion={}
function Completion.observe(toolkit,selection)
 local lifecycle,operations=toolkit.ActionQueueLifecycle,toolkit.ActionQueueOperations
 local begin,finish,flush,perform,defer=lifecycle.begin,lifecycle.finish,lifecycle.flush,operations.perform,operations.deferCompletion
 local state,records,counts,restores,proofs
 local settlement,acks=toolkit.ActionQueueSettlement,toolkit.ActionQueueAcknowledgements
 local captureEffect,confirmEffect=settlement.captureEffect,settlement.confirmEffect
 local beginReturn,finishReturn,returnState=settlement.beginReturn,settlement.finishReturn,settlement.returnState
 local returns={}
 local groupNative,groupItems,groupObligations={}, {},0
 local groupFailure
 local enabled=selection.mode=='toolkit'
 local returnItems=settlement.returnItems
 local tidyIntent=toolkit.ActionQueueTidyIntent
 local groupObserver=tidyIntent and tidyIntent.observeTransfers
 local groupObserverBound=false
 if groupObserver then
  -- Subscribe after compatibility preload; protected native helper identity stays intact.
  groupObserver(function(action)
   if not state or state.id~='tidy-group' or action.srcContainer~=state.root or action.destContainer~=state.source or groupFailure then return end
   if groupNative[action] then return end
   local diagnostic='unreadable native group'
   local ok,problem=pcall(function()
    local groups=action.queueList
    local ids,detail={},{}
    for i=1,math.min(groups and #groups or 0,4) do
     local group=groups[i];local values={}
     for j=1,math.min(group.items and #group.items or 0,4) do values[#values+1]=tostring(group.items[j]:getID()) end
     detail[#detail+1]=tostring(group.items and #group.items)..':'..table.concat(values,',')
    end
    diagnostic='groups='..tostring(groups and #groups)..' members=['..table.concat(detail,';')..']'
    assert(groups and #groups==1 and #groups[1].items==(enabled and 2 or 1),'unexpected bounded native group shape')
    local expected={[state.groupOne:getID()]=true,[state.groupTwo:getID()]=true}
    for _,item in ipairs(groups[1].items) do
     local id=item:getID()
     assert(expected[id] and item:getFullType()=='Base.Nails' and item:getWeight()<=0.1,'unexpected native group member')
     expected[id]=nil;ids[#ids+1]=id
    end
    if enabled then for _ in pairs(expected) do error('native group omitted borrowed item') end end
    groupNative[action]=ids
   end)
   print('[EQUIPMENT_TEST] GROUP_OBSERVED case=tidy-group mode='..selection.mode..' '..diagnostic..' valid='..tostring(ok))
   if not ok then groupFailure='P4 return group observation failed: '..tostring(problem)..' '..diagnostic end
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
    assert(obligation~=nil and not returns[obligation],'duplicate or missing native return obligation')
    local transaction=action.transactionId
    local authoritative=isClient() and type(transaction)=='number' and transaction~=0
     and isItemTransactionDone(transaction)==true and isItemTransactionRejected(transaction)==false
    returns[obligation]={action=action,authoritative=authoritative,observed=false}
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
  if state.id=='tidy-group' and records and records[action] then return records[action].counts end
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
  local exact=state.id=='tidy-group' and record.counts==counts
   and (id==state.groupOne:getID() or id==state.groupTwo:getID()) and action.item:getFullType()=='Base.Nails'
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
   assert(not record,'duplicate native Tidy perform')
   local id=action.item:getID()
   assert(state.baseline[id] and state.baseline[id]:getFullType()==action.item:getFullType(),
    'Tidy transfer returned an unexpected exact item')
   record={id=id,kind=action.item:getFullType(),native=action.action,token=action.toolkitQueueOperation,counts=counter}
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
  if value.id=='tidy-group' and getActivatedMods():contains('P4TidyUpMeister') then
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
  groupNative,groupItems,groupObligations={},{},0
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
    if state.id=='tidy-group' then groupItems[#groupItems+1]={id=item.id,fullType=item.fullType,state=item.state} end
   end
   if state.id=='tidy-group' then
    assert(#items==2,'bounded P4 obligation lost group members');groupObligations=groupObligations+1
   end
  end
  if state.id=='hands-chain' then
   assert(counts.explicitConfirmed==3 and counts.authoritativeIntent==(selection.kind=='mp' and 3 or 0),
    'manual hand chain did not confirm all exact explicit native effects: explicit='..counts.explicitConfirmed..' authoritative='..counts.authoritativeIntent)
  end
  assert(counts.perform==counts.flush and counts.complete==(selection.kind=='sp' and counts.perform or 0)
   and counts.legacy==0,'Tidy native completion counts did not settle')
  for _,record in pairs(records) do assert(record.flushed,'Tidy transfer never flushed') end
  return counts
 end
 function Completion.group()
  local tidy=getActivatedMods():contains('P4TidyUpMeister')
  assert(not groupFailure,groupFailure)
  local groups,nativeItems,seen,sizes=0,0,{},{}
  for _,ids in pairs(groupNative) do
   groups=groups+1;sizes[#sizes+1]=#ids
   for _,id in ipairs(ids) do assert(not seen[id],'P4 native groups repeated exact item');seen[id]=true;nativeItems=nativeItems+1 end
  end
  assert(groups==(tidy and (enabled and 1 or 2) or 0),'P4 native return group count differs')
  assert(nativeItems==(tidy and 2 or 0),'P4 native groups omitted exact item')
  table.sort(sizes)
  assert(groupObligations==(tidy and enabled and 1 or 0),'P4 return obligation group count differs')
  assert(#groupItems==(tidy and enabled and 2 or 0),'P4 per-item completion snapshot incomplete')
  table.sort(groupItems,function(a,b)return a.id<b.id end)
  local expected={state.groupOne:getID(),state.groupTwo:getID()};table.sort(expected)
  for i,item in ipairs(groupItems) do assert(item.id==expected[i],'P4 completed wrong grouped return ID') end
  local items={}
  for _,id in ipairs(expected) do items[#items+1]={id=id,fullType='Base.Nails',container=tidy and 'worn-bag' or 'root'} end
  return {nativeGroups=groups,nativeItems=nativeItems,groupSizes=sizes,obligationGroups=groupObligations,completedItems=groupItems,items=items,unrelatedTailPreserved=true}
 end
 function Completion.restores()
  assert(restores.flush==restores.perform and restores.complete==(selection.kind=='sp' and restores.perform or 0)
   and restores.legacy==0,'P4 equipment completion did not settle')
  return restores
 end
 return Completion
end
return Completion
