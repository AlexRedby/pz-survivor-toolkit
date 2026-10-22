local cartSelection=require 'QueueTestSelection'
if cartSelection.cases[1]=='cart-pickup' then return end
require 'PZSurvivorToolkit/ActionQueuePanel'
local Selection=require 'QueueEquipmentSelection'
local Fixture=require 'QueueEquipmentFixture'
local Slots=require 'QueueEquipmentSlots'
local Floor=require 'QueueEquipmentFloor'
local Postprocess=require 'QueueEquipmentPostprocess'
local Bulk=require 'QueueEquipmentBulk'
local Clothing=require 'QueueEquipmentClothing'
local Hotbar=require 'QueueEquipmentHotbar'
local Rack=require 'QueueEquipmentRack'
local Checks=require 'QueueScenarioChecks'
local JSON=require 'QueueHealthEvents'
local Toolkit=PZSurvivorToolkit
local Completion=require('QueueEquipmentCompletion').observe(Toolkit,Selection)
local API,Policy,Ops=Toolkit.ActionQueue,Toolkit.ActionQueuePolicy,Toolkit.ActionQueueOperations
local native=Selection.mode=='native'
local option=assert(PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'))
option:setValue(not native)
local started,done=false,false
local ids,receipt,checkpoint,cleaned,outcome=nil,nil,nil,false,nil
local hotbarConfigured=nil
local idleUpdates=0
local tidy=getActivatedMods():contains('P4TidyUpMeister')
local index,performed,failures,since,heartbeat=1,0,0,0,0
local state,phase=nil,'prepare'
local function emit(event)
 event.suite='equipment';event.kind=Selection.kind;event.mode=Selection.mode;event.actor='client1';JSON.emit(event)
end
local function complete()
 if done then return end;done=true
 emit({event='complete',cases=Selection.cases,expected=#Selection.cases,performed=performed,skipped=0,failed=failures})
 if failures>0 then print('[QUEUE_TEST] FAIL equipment selected cases='..failures) end
 print('[EQUIPMENT_TEST] COMPLETE')
end
local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()) end
local function empty() return #queue().queue==0 and not getPlayer():hasTimedActions() end
-- P4 starts its deferred restore after two empty player updates.
Events.OnPlayerUpdate.Add(function(player)
 if player==getPlayer() then idleUpdates=empty() and idleUpdates+1 or 0 end
end)
local function run(fn,...) if native then return fn(...) end;return Ops.run(fn,...) end
local function read(book)
 local before=#queue().queue
 run(ISInventoryPaneContextMenu.onLiteratureItems,{book},getPlayer():getPlayerNum())
 local action=assert(queue().queue[before+1],'native book callback did not enqueue')
 assert(action.Type=='ISReadABook' and action.item==book,'native book callback added unexpected preparation')
 assert(action.getDuration==ISReadABook.getDuration and action.minutesPerPage==2.0,'native reading duration changed')
 return action
end
local function equip(item,primary,both)
 local before=#queue().queue
 run(both and ISInventoryPaneContextMenu.OnTwoHandsEquip or primary and ISInventoryPaneContextMenu.OnPrimaryWeapon or ISInventoryPaneContextMenu.OnSecondWeapon,{item},getPlayer():getPlayerNum())
 local first,last=queue().queue[before+1],queue().queue[#queue().queue]
 assert(first and last.Type=='ISEquipWeaponAction' and last.item==item,'native equip callback missing')
 return first,last
end
local function beltTrace(stage,action,value)
 local item=state.slotLast and state.slotLast.item or state.hotbarReplacement;local types={}
 for _,entry in ipairs(queue().queue) do types[#types+1]=entry.Type end
 print('[EQUIPMENT_TEST] BELT case='..state.id..' stage='..stage..' action='..tostring(action and action.Type)
  ..' result='..tostring(value)..' id='..item:getID()..' item='..tostring(item)..' root='..tostring(item:getContainer()==state.root)
  ..' container='..tostring(item:getContainer())..' attachAnim='..tostring(state.player:getVariableString('AttachAnim'))
  ..' moving='..tostring(state.player:isPlayerMoving())..' pressed='..tostring(state.player:pressedMovement(false))
  ..' x='..state.player:getX()..' y='..state.player:getY()..' slot='..item:getAttachedSlot()..' model='..tostring(item:getAttachedToModel())..' queue='..table.concat(types,','))
end
local function watch()
 Completion.watch(state)
 Clothing.watch(Clothing.isCase(state.id)and state or nil)
 Hotbar.watch(Hotbar.isCase(state.id)and state or nil)
end
local function enqueue()
 if Slots.isBelt(state.id) then
  Slots.enqueue(state,{run=run,queue=queue})
  beltTrace('enqueued',state.slotLast)
  if Selection.options.belt_walk then
   assert(type(equipmentTestWalk)=='function','native equipment keyboard probe missing')
   state.walkX,state.walkY=state.player:getX(),state.player:getY()
   state.walkSince=getTimestampMs()
   state.expectedReceipts=1;state.records={};state.seen={};state.policyChecked=false
   equipmentTestWalk(true)
   return
  end
 end
 state.frontAction=read(state.front)
 if Slots.isBelt(state.id) then
  state.policyChecked=false
 elseif state.id=='bag-capacity' then
  local before=#queue().queue
  run(ISInventoryPaneContextMenu.onGrabItems,{state.pickup},getPlayer():getPlayerNum())
  for i=before+1,#queue().queue do local action=queue().queue[i]
   if action.Type=='ISInventoryTransferAction' and action.item==state.pickup then state.pickupAction=action end
  end
  assert(state.pickupAction and state.pickupAction.srcContainer==state.pickupSource and state.pickupAction.destContainer==state.root,'native carried pickup missing')
  before=#queue().queue
  equip(state.hammer,true,false)
  state.replacementAction=assert(queue().queue[before+1],'native hand replacement callback missing')
  assert(state.replacementAction.Type=='ISEquipWeaponAction' and state.replacementAction.item==state.hammer,'native hand replacement differs')
 elseif state.id=='hands-chain' or state.id=='waiting-cancel' then
  state.pickupAction,state.equipAction=equip(state.bat,true,true)
  assert(state.pickupAction.Type=='ISInventoryTransferAction' and state.pickupAction.item==state.bat
   and state.pickupAction.srcContainer==state.source and state.pickupAction.destContainer==state.root,'native bag pickup/equip chain missing')
  assert(state.equipAction.twoHands,'native bat must occupy both hands')
  if not native then
   local first,last=Ops.bounds(queue(),state.pickupAction)
   assert(first and last==first+1 and queue().queue[last]==state.equipAction,'pickup and equip are not one actual operation')
  end
  if state.id=='hands-chain' then
   local first
   first,state.hammerAction=equip(state.hammer,true,false)
   first,state.screwdriverAction=equip(state.screwdriver,false,false)
  end
 elseif Hotbar.isCase(state.id)then Hotbar.enqueue(state,{run=run,queue=queue})
 elseif Clothing.isCase(state.id)then Clothing.enqueue(state,{run=run,queue=queue})
 elseif (state.id=='tidy-group' or state.id=='tidy-multigroup') then
  state.groupPickups={}
  -- Same native borrowing utility as bulk-mixed; P4 owns the actual deferred returns.
  Ops.run(function()
   for _,item in ipairs({state.groupOne,state.groupTwo,state.groupHeavyOne,state.groupHeavyTwo}) do
    local action=ISInventoryTransferUtil.newInventoryTransferAction(state.player,item,state.source,state.root)
    ISTimedActionQueue.add(action);state.groupPickups[#state.groupPickups+1]=action
   end
  end)
  -- Root-origin pistol needs no return: native rack creates real hand restoration ahead of the group.
  local before=#queue().queue
  run(ISInventoryPaneContextMenu.onRackGun,getPlayer(),state.pickup)
  for i=before+1,#queue().queue do local action=queue().queue[i]
   assert(action.Type~='ISInventoryTransferAction','root-origin rack unexpectedly borrowed pistol')
   if action.Type=='ISRackFirearm' then state.rackAction=action end
  end
  assert(state.rackAction and state.rackAction.gun==state.pickup,'native group rack callback missing')
  if not native then
   for _,name in ipairs({'instanceItem','syncHandWeaponFields','sendAddItemToContainer','emulateAnimEventOnce','getClassSimpleName'}) do
    print('[EQUIPMENT_TEST] RACK_GLOBAL '..name..' class='..tostring(getClassSimpleName(_G[name])))
   end
   local inspected,proof,reason=pcall(Toolkit.ActionQueueFirearms.rack,state.rackAction)
   print('[EQUIPMENT_TEST] RACK_PROOF ok='..tostring(inspected)..' contract='..tostring(proof~=nil)..' reason='..tostring(reason or (not inspected and proof)))
   local contract,id=Toolkit.ActionQueueDefinitions.inspect(state.rackAction)
   assert(contract and id=='native.ISRackFirearm' and contract.knownInputs~=false
    and contract.items[state.pickup:getID()] and contract.equipment==state.player
    and contract.outputTypes[state.pickup:getAmmoType():getItemKey()] and contract.cancelOperation==false,
    'native rack resource contract missing, incomplete or permits active cancellation')
  end
 elseif Bulk.isCase(state.id) then Bulk.enqueue(state,{run=run,queue=queue})
 elseif state.id=='tidy-hands' or state.id=='tidy-floor' or state.id=='tidy-empty-hands' then
  local before=#queue().queue
  run(ISInventoryPaneContextMenu.onRackGun,getPlayer(),state.pickup)
  for i=before+1,#queue().queue do local action=queue().queue[i]
   if action.Type=='ISInventoryTransferAction' then state.pickupAction=action end
   if action.Type=='ISRackFirearm' then state.rackAction=action end
  end
  for i=before+1,#queue().queue do local action=queue().queue[i]
   if action.Type=='ISEquipWeaponAction'and action.item==state.pickup then state.rackEquipAction=action end
  end
  assert(state.pickupAction and state.pickupAction.item==state.pickup and state.rackEquipAction
   and state.rackAction and state.rackAction.gun==state.pickup,'native rack callback did not borrow/equip/rack exact gun')
 elseif state.id=='floor-pickup' then Floor.enqueue(state,{run=run,queue=queue})
 else Slots.enqueue(state,{run=run,queue=queue}) end
 state.tailAction=read(state.tail)
 state.expectedReceipts=0;state.records={};state.seen={}
 for _,action in ipairs(queue().queue) do
  if action.Type=='ISEquipWeaponAction' or action.Type=='ISWearClothing' or action.Type=='ISAttachItemHotbar' then
   state.expectedReceipts=state.expectedReceipts+1
  end
 end
end
local function denied(action,target,after,reason)
 Checks.deniedMove(queue(),API,Policy,action,target,after,reason)
 state.dependentMoveRejected=true
end
local function controls()
 if Bulk.isCase(state.id) then
  Bulk.controls(state,{native=native,queue=queue,policy=Policy,api=API})
  state.policyChecked=not native;return
 end
 if native then return end
 if state.id=='hands-chain' then
  denied(state.pickupAction,state.hammerAction,true,'container_capacity')
  denied(state.hammerAction,state.pickupAction,false,'container_capacity')
  denied(state.hammerAction,state.screwdriverAction,true,'move_dependent')
  denied(state.screwdriverAction,state.hammerAction,false,'move_dependent')
  Checks.moveRoundtrip(queue(),API,Policy,state.tailAction,state.pickupAction,false,state.screwdriverAction,true)
  state.independentMoveVerified=true
 elseif Hotbar.isCase(state.id)then
  assert(queue():indexOf(state.tailAction)~=-1,'native rack lost unrelated reading tail')
 elseif Clothing.isCase(state.id)then
  assert(queue():indexOf(state.tailAction)~=-1,'clothing constructor fixture lost unrelated tail')
 elseif (state.id=='tidy-group' or state.id=='tidy-multigroup') then
  assert(queue():indexOf(state.tailAction)~=-1 and state.tailAction.toolkitQueueOperation~=state.groupPickups[1].toolkitQueueOperation,
   'borrowed group lost independent native reading tail')
 elseif state.id=='waiting-cancel' then
  Checks.waitingCancel(queue(),API,Policy,state.pickupAction,{state.pickupAction,state.equipAction},{state.frontAction,state.tailAction})
 elseif state.id=='bag-capacity' then
  denied(state.pickupAction,state.replacementAction,true,'container_capacity')
  denied(state.replacementAction,state.pickupAction,false,'container_capacity')
 elseif state.id=='tidy-hands' or state.id=='tidy-empty-hands' then
  Rack.controls(state,{queue=queue,api=API,policy=Policy,operations=Ops,definitions=Toolkit.ActionQueueDefinitions})
 elseif state.id=='floor-pickup' or state.id=='tidy-floor' then Floor.controls(state,{denied=denied,queue=queue,native=native})
 else Slots.controls(state,{denied=denied,queue=queue,native=native}) end
 if state.id=='waiting-cancel' then state.expectedReceipts=0 end
 state.policyChecked=true
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~='EquipmentQueueTest' then return end
 assert(args.ok~=false,args.error)
 if command=='Prepared' then ids=args elseif command=='Checkpointed' then checkpoint=args elseif command=='Verified' then receipt=args elseif command=='Cleaned' then cleaned=true elseif command=='HotbarConfigured'then hotbarConfigured=args end
end)
Events.OnGameStart.Add(function()
 local ok,problem=pcall(function()
  local player=assert(getPlayer());assert(isClient()==(Selection.kind=='mp') and not isServer(),'equipment connection kind differs')
  assert(Translator.getLanguage():name()==Selection.language,'equipment language differs')
  assert(Toolkit.Settings.actionQueue()==(not native),'equipment queue mode differs')
  assert(not player:isTimedActionInstant(),'native equipment duration required')
  player:setGhostMode(true);getCore():setOptionAutoDrink(false);player:setAutoDrink(false)
  if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
  if Selection.kind=='sp' then Fixture.position(player) end
  for _,id in ipairs(Selection.cases)do
   if Clothing.isCase(id)then Clothing.install(tidy)end
   if Hotbar.isCase(id)then Hotbar.install(tidy)end
  end
  emit({event='setup',cases=Selection.cases,expected=#Selection.cases,language=Selection.language,nativeDurations=true,queueEnabled=not native})
  started=true;since=getTimestampMs()
 end)
 if not ok then failures=failures+1;emit({event='error',reason=tostring(problem)});complete() end
end)
Events.OnTick.Add(function()
 if not started or done then return end
 local now=getTimestampMs()
 local ok,problem=pcall(function()
  if state and phase=='beltWalk' then
   assert(now-state.walkSince<15000,'walking belt action did not settle within bounded input hold')
   local player=state.player
   local dx,dy=player:getX()-state.walkX,player:getY()-state.walkY
   state.walkDistance=math.max(state.walkDistance or 0,math.sqrt(dx*dx+dy*dy))
   if player:isPlayerMoving() then
    if queue().current==state.slotFirst then state.walkedDuringTransfer=true end
    if queue().current==state.slotLast then state.walkedDuringAttach=true end
   end
  end
  if state and Slots.isBelt(state.id) and state.beltCurrent~=queue().current then
   state.beltCurrent=queue().current;beltTrace('current',queue().current)
   if queue().current==state.slotLast then beltTrace('valid',state.slotLast,state.slotLast:isValid()) end
  end
  if state and Bulk.isCase(state.id) then Bulk.observe(state,queue()) end
  if state and Clothing.isCase(state.id)then Clothing.observe(state,queue(),Toolkit,tidy)end
  if state and Hotbar.isCase(state.id)then Hotbar.observe(state,queue(),Toolkit,tidy)end
  if state and Selection.kind=='mp' then
   local action=queue().current
   local record=action and Toolkit.ActionQueueAcknowledgements.capture(action)
   if phase~='drain' and phase~='checkpointReceipt' and record and (action.Type=='ISEquipWeaponAction' or action.Type=='ISWearClothing' or action.Type=='ISAttachItemHotbar') and not state.seen[record.token] then
    state.seen[record.token]=true;state.records[#state.records+1]=record
    print('[EQUIPMENT_TEST] CAPTURE case='..state.id..' kind='..action.Type..' token='..record.token)
   end
   if now-heartbeat>=10000 then
    heartbeat=now
    local records={}
    for _,entry in ipairs(state.records) do records[#records+1]=entry.kind..':'..entry.transaction..':'..entry.state..':'..entry.token end
    print('[EQUIPMENT_TEST] WAIT case='..state.id..' phase='..phase..' current='..tostring(action and action.Type)
     ..' size='..#queue().queue..' front='..state.front:getAlreadyReadPages()..' tail='..state.tail:getAlreadyReadPages()..' records='..table.concat(records,','))
   end
  end
  if state and state.id=='hands-chain' and not state.activeProgress then
   local action=queue().current
   if action and action.Type=='ISEquipWeaponAction' and action:isStarted() and action:getJobDelta()>0 then
    state.activeProgress=true
    if not native then
     Checks.deniedCancel(queue(),API,Policy,action,'operation_dependent')
     state.activeProtected=true
    end
   end
  end
  assert(now-since<180000,'native equipment case deadline '..Selection.cases[index])
  assert(Toolkit.Settings.actionQueue()==(not native),'equipment queue mode changed')
  if phase=='prepare' then
   if not empty() or getPlayer():isPlayerMoving() or (Selection.kind=='sp' and getPlayer():tooDarkToRead()) then return end
   if Selection.kind=='mp' then
    sendClientCommand('EquipmentQueueTest','Prepare',{case=Selection.cases[index]});phase='ready'
   else state=Fixture.prepare(getPlayer(),Selection.cases[index],nil,Selection.options);watch();enqueue();phase=Slots.isBelt(state.id) and (Selection.options.belt_walk and 'beltWalk' or 'checkpoint') or 'controls' end
  elseif phase=='ready' then
   if not ids or not Fixture.available(getPlayer(),ids) then return end
   assert(ids.case==Selection.cases[index],'wrong authoritative fixture case')
   local player=getPlayer()
   if math.abs(player:getX()-ids.spawn.x)>0.1 or math.abs(player:getY()-ids.spawn.y)>0.1 or player:getZ()~=ids.spawn.z then
    Fixture.relocate(player,ids.spawn)
   end
   phase='positioned';return
  elseif phase=='positioned' then
   local player=getPlayer()
   if not player:getCurrentSquare() or player:isPlayerMoving() or player:tooDarkToRead() then return end
   state=Fixture.prepare(player,Selection.cases[index],ids,Selection.options)
   if state.holster then
    sendClientCommand('EquipmentQueueTest','ConfigureHotbar',{case=state.id,item=state.pickup:getID(),slotIndex=state.hotbarIndex})
    phase='configureHotbar';return
   end
   watch();enqueue();phase=Slots.isBelt(state.id) and (Selection.options.belt_walk and 'beltWalk' or 'checkpoint') or 'controls'
  elseif phase=='configureHotbar'then
   if not hotbarConfigured then return end
   assert(hotbarConfigured.case==state.id and hotbarConfigured.item==state.pickup:getID()
    and hotbarConfigured.slotIndex==state.hotbarIndex,'authoritative native hotbar setup differs')
   watch();enqueue();phase='controls'
  elseif phase=='beltWalk' then
   if queue():indexOf(state.slotLast)~=-1 then return end
   equipmentTestWalk(false);state.walkReleased=true;beltTrace('released',state.slotLast)
   assert(state.walkedDuringTransfer and state.walkedDuringAttach and (state.walkDistance or 0)>0.1,
    'belt regression did not walk through native transfer and attach')
   phase='beltWalkStop'
  elseif phase=='beltWalkStop' then
   if not empty() or getPlayer():isPlayerMoving() or getPlayer():pressedMovement(false) then return end
   state.frontAction=read(state.front);state.tailAction=read(state.tail);phase='checkpoint'
  elseif phase=='controls' then
   if queue():indexOf(state.frontAction)==-1 then
    print('[EQUIPMENT_TEST] FRONT_MISSING case='..state.id..' moving='..tostring(getPlayer():isPlayerMoving())..' dark='..tostring(getPlayer():tooDarkToRead())
     ..' pages='..state.front:getAlreadyReadPages()..' characterPages='..getPlayer():getAlreadyReadPages(state.front:getFullType())..' startPage='..tostring(state.frontAction.startPage)..' queueSize='..#queue().queue)
    error('front action removed before waiting controls')
   end
   if queue().current~=state.frontAction or not state.frontAction.action or not state.frontAction.action:isStarted() then return end
   controls();phase='checkpoint'
  elseif phase=='checkpoint' and queue().current==state.tailAction and state.tailAction:isStarted() then
   assert(native or state.policyChecked or Slots.isBelt(state.id),'toolkit policy evidence missing')
   local receiptStates={}
   if Selection.kind=='mp' then
    if not Fixture.transactionsSettled() then return end
    if #state.records~=state.expectedReceipts then return end
    for _,record in ipairs(state.records) do
     if record.state=='started' then return end
     -- Attach mutates through client field packets; its server complete() has no effects.
     assert(record.state=='completed' or (state.id=='hotbar-chain' or Slots.isBelt(state.id)) and record.kind=='ISAttachItemHotbar' and record.state=='canceled',
      'unexpected native equipment outcome '..record.kind..':'..record.state)
     receiptStates[#receiptStates+1]=record.state
    end
   end
   if state.id=='hands-chain' then assert(state.activeProgress,'equipment never made native active progress') end
   outcome=Fixture.verify(state,Selection.mode,true)
   if Selection.options.belt_walk then
    outcome.walkingVerified=true;outcome.walkedDuringTransfer=state.walkedDuringTransfer==true
    outcome.walkedDuringAttach=state.walkedDuringAttach==true;outcome.walkReleased=state.walkReleased==true;outcome.walkDistance=state.walkDistance
   end
   if Bulk.isCase(state.id) then for key,value in pairs(Bulk.evidence(state)) do outcome[key]=value end end
   if state.id=='hands-chain' then outcome.activeProgress=true;outcome.activeProtected=not native end
   outcome.receipts=Selection.kind=='mp' and #state.records or 0
   if Selection.kind=='mp' then outcome.receiptStates=receiptStates end
   if Selection.kind=='mp' then
    sendClientCommand('EquipmentQueueTest','Checkpoint',{case=state.id});phase='checkpointReceipt';return
   end
   phase='drain'
  elseif phase=='checkpointReceipt' then
   if not checkpoint then return end
   assert(checkpoint.case==state.id,'wrong authoritative equipment checkpoint')
   for _,key in ipairs({'primary','secondary','bag','front','tail','clothingItem','hotbarItem'}) do
    assert(checkpoint.outcome[key]==outcome[key],'checkpoint exact equipment identity differs '..key)
   end
   phase='drain'
  elseif phase=='drain' and empty() and idleUpdates>=6 then
   if Selection.kind=='mp' and not Fixture.transactionsSettled() then return end
   Fixture.refresh(state)
   if Clothing.isCase(state.id)and not Clothing.settled(state,Toolkit,tidy)then return end
   if Hotbar.isCase(state.id)and not Hotbar.settled(state,Toolkit,tidy)then return end
   local passed,problem=pcall(Postprocess.verify,state,Selection.mode,tidy)
   outcome.checkpointEquipmentMatches=outcome.equipmentMatches
   outcome.equipmentMatches=passed
   outcome.tailCompleted=state.tail:getAlreadyReadPages()==state.tail:getNumberOfPages()
    and getPlayer():getAlreadyReadPages(state.tail:getFullType())==state.tail:getNumberOfPages()
   outcome.postprocessingVerified=passed
   outcome.tidyCompletion=Completion.settled()
   if Hotbar.isCase(state.id)then outcome.tidyHotbar=Hotbar.evidence(state,Toolkit,tidy,Completion.hotbar())end
   if Clothing.isCase(state.id)then outcome.tidyClothing=Clothing.evidence(state,Toolkit,tidy,Completion.clothing())end
   if (state.id=='tidy-group' or state.id=='tidy-multigroup') then outcome.tidyGroup=Completion.group() end
   if state.id=='tidy-hands' or state.id=='tidy-floor' or state.id=='tidy-empty-hands' or (state.id=='tidy-group' or state.id=='tidy-multigroup') then
    outcome.restoreVerified=passed;outcome.floorRestoreVerified=state.id=='tidy-floor' and passed and tidy
    outcome.restoreCompletion=Completion.restores()
   end
   if Bulk.isCase(state.id) then outcome.borrowedReturned=state.id=='bulk-mixed' and passed and tidy or false end
   outcome.finalPrimary=getPlayer():getPrimaryHandItem() and getPlayer():getPrimaryHandItem():getID() or false
   outcome.finalSecondary=getPlayer():getSecondaryHandItem() and getPlayer():getSecondaryHandItem():getID() or false
   if not passed then state.postproblem=tostring(problem) end
   if Selection.kind=='mp' then
    sendClientCommand('EquipmentQueueTest','Verify',{case=state.id});phase='receipt';return
   end
   phase='cleanup'
  elseif phase=='receipt' then
   if not receipt then return end
   assert(receipt.ok and receipt.case==state.id,'wrong authoritative equipment receipt')
   outcome.authoritative=receipt.passed==true
   if not receipt.passed then state.postproblem=state.postproblem or receipt.error or 'server postprocessing failed' end
   assert(receipt.passed==outcome.postprocessingVerified,'server/client postprocessing decision differs')
   Fixture.release(state)
   sendClientCommand('EquipmentQueueTest','Cleanup',{case=state.id});phase='cleaned';return
  elseif phase=='cleaned' then
   if not cleaned or not Fixture.removed(state) then return end;Fixture.cleanup(state);phase='finish'
  end
  if phase=='cleanup' then Fixture.cleanup(state);phase='finish' end
  if phase=='finish' then
   performed=performed+1
   if state.postproblem then failures=failures+1;print('[EQUIPMENT_TEST] CASE_FAILED case='..state.id..' '..state.postproblem) end
   outcome.rackWholeOperationMoveVerified=state.rackWholeOperationMoveVerified==true
   outcome.rackCancellationProtected=state.rackCancellationProtected==true
   outcome.independentMoveVerified=state.independentMoveVerified==true
   outcome.dependentMoveRejected=state.dependentMoveRejected==true
   emit({event='case',id=state.id,status=state.postproblem and 'failed' or 'passed',reason=state.postproblem,outcome=outcome})
   print('[EQUIPMENT_TEST] RECEIPT case='..state.id)
   index=index+1;since=now;phase='prepare';state=nil;ids=nil;receipt=nil;checkpoint=nil;hotbarConfigured=nil;cleaned=false;outcome=nil;idleUpdates=0
   if index>#Selection.cases then complete() end
  end
 end)
 if not ok then
  if Selection.options.belt_walk and type(equipmentTestWalk)=='function' then equipmentTestWalk(false) end
  failures=failures+1;performed=performed+1
  emit({event='case',id=Selection.cases[index],status='failed',reason=tostring(problem)})
  print('[QUEUE_TEST] FAIL equipment '..tostring(problem));complete()
 end
end)
