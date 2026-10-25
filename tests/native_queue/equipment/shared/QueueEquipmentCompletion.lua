local Completion={}
local Clothing=require 'QueueEquipmentClothing'
local Hotbar=require 'QueueEquipmentHotbar'
local function hotbarCase(id)return Hotbar.isCase(id)end
local function clothingAction(state,action)
 if Clothing.replaces(state)then return Clothing.cleanupMember(state,action)~=nil end
 return state.clothingItem and action.Type==(state.clothingRestoreType
  or (state.id=='tidy-clothing'and 'ISWearClothing'or 'ISUnequipAction'))
end
function Completion.observe(toolkit,selection)
 local lifecycle,operations=toolkit.ActionQueueLifecycle,toolkit.ActionQueueOperations
 local begin,finish,flush,perform,defer=lifecycle.begin,lifecycle.finish,lifecycle.flush,operations.perform,operations.deferCompletion
 local state,records,counts,restores,clothing,hotbar,proofs
 local settlement,acks=toolkit.ActionQueueSettlement,toolkit.ActionQueueAcknowledgements
 local captureEffect,confirmEffect=settlement.captureEffect,settlement.confirmEffect
 local beginReturn,finishReturn,returnState=settlement.beginReturn,settlement.finishReturn,settlement.returnState
 local returns={}
 local groupNative,groupItems,groupObligations,groupAttempts={}, {},0,{}
 local groupFailure
 local pickupOwners,pickupRecords,pickupItems,ownershipAtBegin,ownershipCompleted={},{},{},{},{}
 local pickupOperations=0
 local claimScopes,pickupScopes={},{}
 local function grouped() return state and (state.id=='tidy-group' or state.id=='tidy-multigroup') end
 local function members()
  return {state.groupOne,state.groupTwo,state.groupHeavyOne,state.groupHeavyTwo}
 end
 local function expectedMembers()
  local result={};for _,item in ipairs(members()) do result[item:getID()]=item:getFullType() end;return result
 end
 local enabled=selection.mode=='toolkit'
 local remember=settlement.remember
 if remember then
  settlement.remember=function(scope,action,contract)
   local accepted=remember(scope,action,contract)
   if accepted and enabled and grouped() then
    local captured=claimScopes[scope]
    if not captured then captured={tasks={},seen={},equipmentItems={}};claimScopes[scope]=captured end
    if not captured.seen[action] then
     captured.seen[action]=true
     local token=action.toolkitQueueOperation
     local task=captured.tasks[token]
     if not task then task={items={},unknown={}};captured.tasks[token]=task end
     local reason=not contract and 'missing-contract' or contract.knownInputs==false and 'unknown-inputs'
      or contract.dynamicInputs and 'dynamic-inputs' or contract.dynamicInputsByType and 'dynamic-types'
     if reason then task.unknown[#task.unknown+1]={kind=tostring(action.Type),reason=reason} end
     for id in pairs(contract and contract.items or {}) do
      task.items[id]=tostring(action.Type)
      if contract.hands==action.character then captured.equipmentItems[id]=true end
     end
     if contract and contract.equipment==action.character then task.readsEquipment=true end
     for id in pairs(contract and contract.containerOwners or {}) do task.items[id]=tostring(action.Type) end
     pickupScopes[action]=scope
    end
   end
   return accepted
  end
 end
 local function expectedShared(item)
  local captured=claimScopes[item.scope]
  if not captured or not captured.tasks[item.owner] then return nil,'native pickup omitted accepted task claims' end
  local shared=false
  for token,task in pairs(captured.tasks) do
   if token~=item.owner then
    if #task.unknown>0 or task.items[item.id] or task.readsEquipment and captured.equipmentItems[item.id] then
     shared=true
     local unknown=task.unknown[1]
     print('[EQUIPMENT_TEST] OWNERSHIP_SHARED id='..item.id..' competingType='..tostring(unknown and unknown.kind or task.items[item.id])
      ..' reason='..tostring(unknown and unknown.reason or 'exact-item-input'))
    end
   end
  end
  return shared
 end
 local function addPickupMembers(action,record)
  local groups=action.queueList
  local members=groups and groups[1] and groups[1].items
  if type(members)~='table' or #members<1 then return 'native pickup attempt has no members' end
  for _,item in ipairs(members) do
   local id=item:getID()
   if expectedMembers()[id]~=item:getFullType() or pickupItems[id] then return 'native pickup repeated or changed exact member' end
   if not record.seen[id] then
    record.seen[id]=true
    record.active[#record.active+1]={id=id,fullType=item:getFullType(),owner=record.owner,item=item,scope=record.scope,
     pickupAttempt=record.ordinal,pickupTransaction=record.transaction,pickupAuthority=isClient() and 'completed' or 'native'}
   end
  end
 end
 local function capturePickup(action,phase)
  if not enabled or not grouped() or phase~='perform' or not getActivatedMods():contains('P4TidyUpMeister') or action.srcContainer~=state.source or action.destContainer~=state.root then return end
  local owner=assert(action.toolkitQueueOperation,'native pickup has no original operation')
  if not pickupOwners[owner] then pickupOperations=pickupOperations+1;pickupOwners[owner]=pickupOperations end
  assert(pickupOperations==1,'bounded native pickups changed original operation')
  local record=pickupRecords[action] or {ordinal=0,owner=owner,scope=pickupScopes[action]}
  assert(record.owner==owner and not record.active,'native pickup changed operation or overlapped attempts')
  record.ordinal=record.ordinal+1;record.active={};record.seen={}
  local transaction=action.transactionId
  if isClient() then
   assert(type(transaction)=='number' and transaction~=0 and isItemTransactionDone(transaction)==true
    and isItemTransactionRejected(transaction)==false,'native pickup lacks authoritative inventory transaction')
  else transaction=0 end
  record.transaction=transaction
  local problem=addPickupMembers(action,record);assert(not problem,problem)
  pickupRecords[action]=record
 end
 local function finishPickup(action,phase,succeeded)
  local record=pickupRecords[action]
  if not record or phase~='perform' then return end
  assert(succeeded and record.active,'native pickup did not finish its captured attempt')
  for _,item in ipairs(record.active) do
   local live=state.root:getItemById(item.id)
   assert(live and live:getID()==item.id and live:getFullType()==item.fullType and live:getContainer()==state.root,
    'native pickup did not apply its exact root inventory effect')
   pickupItems[item.id]=item
  end
  record.active=nil
 end
 local function ownership(obligation,phase,partial)
  local values=settlement.returnOwnership and settlement.returnOwnership(obligation)
  if type(values)~='table' or #values<1 or not partial and #values~=(state.id=='tidy-multigroup' and 4 or 2) then
   return nil,'native return ownership omitted members'
  end
  local result,seen={},{}
  for _,value in ipairs(values) do
   local pickup=pickupItems[value.id]
   if pickup and pickup.shared==nil then
    local shared,problem=expectedShared(pickup)
    if shared==nil then return nil,problem end
    pickup.shared=shared
   end
   if not (pickup and not seen[value.id] and value.fullType==pickup.fullType and (value.state==phase or partial and value.state=='completed')
    and value.owner==pickup.owner and value.shared==pickup.shared and value.pickupAttempt==pickup.pickupAttempt
    and value.pickupTransaction==pickup.pickupTransaction and value.pickupAuthority==pickup.pickupAuthority) then
    return nil,'native return ownership differs id='..tostring(value.id)..' state='..tostring(value.state)..' owner='..tostring(pickup and value.owner==pickup.owner)..' shared='..tostring(value.shared)..'/'..tostring(pickup and pickup.shared)..' attempt='..tostring(value.pickupAttempt)..'/'..tostring(pickup and pickup.pickupAttempt)..' transaction='..tostring(value.pickupTransaction)..'/'..tostring(pickup and pickup.pickupTransaction)..' authority='..tostring(value.pickupAuthority)..'/'..tostring(pickup and pickup.pickupAuthority)
   end
   seen[value.id]=true
   result[#result+1]={id=value.id,fullType=value.fullType,state=value.state,owner=pickupOwners[value.owner],shared=value.shared,
    pickupAttempt=value.pickupAttempt,pickupTransaction=value.pickupTransaction,pickupAuthority=value.pickupAuthority}
  end
  if not partial then for id in pairs(expectedMembers()) do if not seen[id] then return nil,'native return ownership lost exact borrowed member' end end end
  table.sort(result,function(a,b)return a.id<b.id end)
  return result
 end
 local function rememberOwnership(obligation)
  local prior={};for _,item in ipairs(ownershipAtBegin) do prior[item.id]=true end
  local values,problem=ownership(obligation,'active',true)
  if not values then return problem end
  for _,item in ipairs(values) do
   if not prior[item.id] then
    if item.state~='active' then return 'native return ownership was first observed after its effect' end
    ownershipAtBegin[#ownershipAtBegin+1]=item
   end
  end
  table.sort(ownershipAtBegin,function(a,b)return a.id<b.id end)
 end
 local returnItems=settlement.returnItems
 local tidyIntent=toolkit.ActionQueueTidyIntent
 local groupObserver=tidyIntent and tidyIntent.observeTransfers
 local groupObserverBound=false
 if groupObserver then
  -- Subscribe after compatibility preload; protected native helper identity stays intact.
  groupObserver(function(action)
   if not grouped() or groupFailure then return end
   if action.srcContainer==state.source and action.destContainer==state.root then
    local record=pickupRecords[action]
    if record and record.active and not isClient() then
     local ok,problem=pcall(addPickupMembers,action,record)
     if not ok or problem then groupFailure='P4 pickup group observation failed: '..tostring(problem) end
    end
    return
   end
   if action.srcContainer~=state.root or action.destContainer~=state.source then return end
   -- Never assert or throw across native merge: Kahlua logs even caught assertions.
   local function observe()
    for obligation,record in pairs(returns) do if record.action==action then
     local problem=rememberOwnership(obligation);if problem then return problem end
    end end
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
     if total~=expectedCount then return 'native group omitted borrowed item' end
     groupNative[action]=ids
     local times={}
     for _,group in ipairs(groups) do
      if type(group.time)~='number' or not (group.time>0 or isClient() and group.time==-1) then
       return 'native group duration missing or shortened'
      end
      times[#times+1]=tostring(group.time)
     end
     print('[EQUIPMENT_TEST] GROUP_TIMING case='..state.id..' mode='..selection.mode..' times='..table.concat(times,','))
    else
     local original={};for _,values in ipairs(prior) do for _,id in ipairs(values) do original[id]=true end end
     for id in pairs(seen) do if not original[id] then return 'native continuation changed group membership' end end
    end
   end
   local ok,problem=pcall(observe)
   if not ok or problem then groupFailure='P4 return group observation failed: '..tostring(problem) end
   print('[EQUIPMENT_TEST] GROUP_OBSERVED case='..state.id..' mode='..selection.mode..' groups='..tostring(action.queueList and #action.queueList)..' valid='..tostring(ok and not problem))
  end,nil,{begin=function(action)
   if grouped() and isClient() and action.srcContainer==state.root and action.destContainer==state.source then
    -- MP queues use -1 until the server supplies a transaction duration. Observe
    -- it before native perform removes that transaction; do not retime the action.
    print('[EQUIPMENT_TEST] GROUP_TRANSACTION_TIMING case='..state.id..' mode='..selection.mode
     ..' transaction='..tostring(action.transactionId)..' duration='..tostring(getItemTransactionDuration(action.transactionId)))
   end
  end})
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
   local returning=state and action.srcContainer==state.root and action.destContainer==state.source
   if returning then
    local groups=action.queueList
    print('[EQUIPMENT_TEST] RETURN_CAPTURE accepted='..tostring(accepted)..' reason='..tostring(reason)
     ..' groups='..tostring(groups and #groups)..' items='..tostring(groups and groups[1] and #groups[1].items)
     ..' native='..tostring(action.action~=nil)..' current='..tostring(ISTimedActionQueue.queues[action.character].current==action))
   end
   if returning and accepted then
    assert(obligation~=nil and (state.id=='tidy-multigroup' or not returns[obligation]),'duplicate or missing native return obligation')
    local transaction=action.transactionId
    local authoritative=isClient() and type(transaction)=='number' and transaction~=0
     and isItemTransactionDone(transaction)==true and isItemTransactionRejected(transaction)==false
    local record=returns[obligation]
    if record then assert(record.action==action,'P4 obligation changed executor')
    else
     record={action=action,authoritative=authoritative,observed=false,accepted=0};returns[obligation]=record
     if grouped() then local problem=rememberOwnership(obligation);if problem then groupFailure=problem;print('[EQUIPMENT_TEST] OWNERSHIP_PROBLEM '..problem) end end
    end
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
  if kind=='compat.tidy-equipment' then
   if clothingAction(state,action)then return clothing end
   if hotbarCase(state.id)and action.Type=='ISUnequipAction'then return hotbar end
   return restores
  end
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
  if state and hotbarCase(state.id)and action==state.hotbarRestoreAction and phase=='perform'then
   -- Sample before native perform in both queue modes. After the detached
   -- checkpoint, only the real attachConnect event can have attached the model.
   assert(state.hotbarDetached and action.fromHotbar and action.item==state.pickup
    and action.character:getAttachedItems():getItem(state.hotbarLocation)==state.pickup,
    'native hotbar attachConnect effect missing before perform')
   state.hotbarAttachConnect=true
  end
  capturePickup(action,phase)
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
   if counter==hotbar then
    assert(action.Type=='ISUnequipAction'and action.item==state.pickup and action.fromHotbar and action.reason==nil
     and action.item:getContainer()==state.root and action.item:getAttachedSlot()==state.hotbarIndex
     and action.item:getAttachedSlotType()==state.hotbarType and action.item:getAttachedToModel()==state.hotbarLocation,
     'P4 hotbar cleanup changed exact ordinary item/slot/root')
    assert(state.hotbarDetached and action.character:getAttachedItems():getItem(state.hotbarLocation)==state.pickup,
     'native attachConnect effect missing before hotbar perform')
    state.hotbarAttachConnect=true
    local held=action.character:getPrimaryHandItem()
    local other=action.character:getSecondaryHandItem()
    local primary,secondary=Hotbar.expectedHands(state,false)
    local finalPrimary,finalSecondary=Hotbar.expectedHands(state,true)
    assert((held==primary and other==secondary or selection.kind=='mp'and held==finalPrimary and other==finalSecondary),
     'P4 hotbar cleanup removed wrong temporary hands')
    local queue=ISTimedActionQueue.queues[action.character]
    assert(not toolkit.ActionQueuePolicy.evaluateCancel(queue,action,true).allowed,'shared hotbar cleanup must remain protected')
   elseif counter==clothing then
    local expected=Clothing.replaces(state)and assert(Clothing.cleanupMember(state,action)).item or state.clothingItem
    assert(clothingAction(state,action)
     and action.item:getID()==expected:getID()and action.item:getFullType()==expected:getFullType()
     and action.item:getBodyLocation()==expected:getBodyLocation()and action.item:getContainer()==state.root,
     'P4 restored unexpected clothing identity/slot/container')
    local queue=ISTimedActionQueue.queues[action.character]
    assert(not toolkit.ActionQueuePolicy.evaluateCancel(queue,action,true).allowed,'shared clothing cleanup must remain protected')
    -- Host can replicate worn state before client perform; observe exact final
    -- authority after quiescence instead of requiring pre-effect slot absence.
   elseif counter==restores then
    local spec=Clothing.overlap(state)and Clothing.cleanupMember(state,action)
    local primary=action.item:getID()==state.hammer:getID() and action.item:getFullType()==state.hammer:getFullType()
    assert(spec or action.Type=='ISUnequipAction' and state.id=='tidy-empty-hands' and action.item:getID()==state.pickup:getID()
     or not Clothing.overlap(state)and (primary or action.item:getID()==state.screwdriver:getID()and action.item:getFullType()==state.screwdriver:getFullType()),
     'P4 restored unexpected equipment')
    local queue=ISTimedActionQueue.queues[action.character]
    local decision=toolkit.ActionQueuePolicy.evaluateCancel(queue,action,true)
    assert(not decision.allowed,'shared equipment cleanup must remain protected')
    if action.Type=='ISEquipWeaponAction' then
     assert(spec and action.primary==spec.primary and action.twoHands==spec.twoHands
      or not spec and action.primary==primary and not action.twoHands,'P4 restored wrong hand slots')
     restores.equip=restores.equip+1
    elseif action.Type=='ISUnequipAction' then
     local held=action.character:getPrimaryHandItem()
     -- Host may replicate the authoritative unequip before the client performs its UI cleanup.
     assert(not action.character:getSecondaryHandItem() and (held==action.item or selection.kind=='mp' and not held),
      'P4 removed wrong temporary equipment')
     restores.unequip=restores.unequip+1
    else
     assert(action.Type=='P4RestoreAction' and action.activated==(spec and spec.activated or not spec and primary and not Clothing.overlap(state)),
      'P4 restored wrong activation')
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
  finishPickup(action,phase,succeeded)
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
  pickupOwners,pickupRecords,pickupItems,ownershipAtBegin,ownershipCompleted={},{},{},{},{}
  pickupOperations=0
  claimScopes,pickupScopes={},{}
  restores={perform=0,complete=0,flush=0,legacy=0,equip=0,activation=0,unequip=0}
  clothing={perform=0,complete=0,flush=0,legacy=0}
  hotbar={perform=0,complete=0,flush=0,legacy=0}
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
    local problem;ownershipCompleted,problem=ownership(obligation,'completed');assert(ownershipCompleted,problem)
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
  assert(groups==(tidy and (multi and 3 or 1) or 0),'P4 native return group count differs')
  assert(nativeItems==(tidy and total or 0),'P4 native groups omitted exact item')
  table.sort(sizes)
  assert(groupObligations==(tidy and enabled and 1 or 0),'P4 return obligation group count differs')
  assert(#groupItems==(tidy and enabled and total or 0),'P4 per-item completion snapshot incomplete')
  table.sort(groupItems,function(a,b)return a.id<b.id end)
  local expected={};for id in pairs(expectedMembers()) do expected[#expected+1]=id end;table.sort(expected)
  for i,item in ipairs(groupItems) do assert(item.id==expected[i],'P4 completed wrong grouped return ID') end
  local items={}
  for _,id in ipairs(expected) do items[#items+1]={id=id,fullType=expectedMembers()[id],container=tidy and 'worn-bag' or 'root'} end
  local pickups={}
  for _,item in pairs(pickupItems) do pickups[#pickups+1]={id=item.id,fullType=item.fullType,owner=pickupOwners[item.owner],shared=item.shared,
   pickupAttempt=item.pickupAttempt,pickupTransaction=item.pickupTransaction,pickupAuthority=item.pickupAuthority} end
  table.sort(pickups,function(a,b)return a.id<b.id end)
  local count=tidy and enabled and total or 0
  assert(pickupOperations==(count>0 and 1 or 0) and #pickups==count and #ownershipAtBegin==count and #ownershipCompleted==count,
   'bounded native pickup/return ownership evidence incomplete or active with queue disabled')
  local result={pickupOperations=pickupOperations,pickupItems=pickups,ownershipAtBegin=ownershipAtBegin,ownershipCompleted=ownershipCompleted,nativeGroups=groups,nativeItems=nativeItems,groupSizes=sizes,obligationGroups=groupObligations,completedItems=groupItems,items=items,unrelatedTailPreserved=true}
  if multi then
   assert(executors==(tidy and 1 or 0),'P4 multi-group changed native executor')
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
 function Completion.hotbar()
  local expected=enabled and getActivatedMods():contains('P4TidyUpMeister')and 1 or 0
  assert(hotbar.perform==expected and hotbar.flush==expected
   and hotbar.complete==(selection.kind=='sp'and expected or 0)and hotbar.legacy==0,
   'P4 hotbar shared completion phases did not settle exactly once')
  return hotbar
 end
 function Completion.clothing()
  local expected=enabled and getActivatedMods():contains('P4TidyUpMeister')and (Clothing.replaces(state)and #Clothing.cleanupSpec(state)or 1)or 0
  assert(clothing.perform==expected and clothing.flush==expected
   and clothing.complete==(selection.kind=='sp'and expected or 0)and clothing.legacy==0,
   'P4 clothing shared completion phases did not settle exactly once')
  return clothing
 end
 return Completion
end
return Completion
