require 'XpSystem/ISUI/ISHealthPanel'
require 'TimedActions/ISReadABook'
local Selection=require 'QueueHealthSelection'
local Cases=Selection.cases
local Authority=require 'QueueHealthAuthority'
return function(stage,queue,empty,remote)
 local Toolkit=PZSurvivorToolkit
 local API,Policy,Ops=Toolkit.ActionQueue,Toolkit.ActionQueuePolicy,Toolkit.ActionQueueOperations
 local native=Selection.mode=='native'
 local function run(fn,...) if native then return fn(...) end;return Ops.run(fn,...) end
 local function assertMode() assert(Toolkit.Settings.actionQueue()==(not native),'medical queue setting differs from selected mode') end
 local player,observer,restoreHelper
 local function item(id)
  local function scan(container)
   local values=container:getItems();for i=0,values:size()-1 do local value=values:get(i)
    if value:getID()==id then return value end
    if instanceof(value,'InventoryContainer') then local found=scan(value:getItemContainer());if found then return found end end
   end
  end
  return scan(player:getInventory())
 end
 local function patient(name)
  if remote.kind=='sp' then return player end
  local values=getOnlinePlayers();for i=0,values:size()-1 do local value=values:get(i);if value:getUsername()==name then return value end end
 end
 local function readyPosition(character,expected)
  local square=character:getCurrentSquare()
  return square and square:getX()==math.floor(expected.x) and square:getY()==math.floor(expected.y) and square:getZ()==expected.z
   and math.abs(character:getX()-expected.x)<0.25 and math.abs(character:getY()-expected.y)<0.25 and character:getZ()==expected.z
   and not character:isPlayerMoving()
 end
 local function read(id,pages)
  local book=assert(item(id),'book not synchronized');book:setAlreadyReadPages(book:getNumberOfPages()-pages)
  player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-pages)
  run(ISInventoryPaneContextMenu.onLiteratureItems,{book},player:getPlayerNum())
  for _,action in ipairs(queue().queue) do if action.Type=='ISReadABook' and action.item==book then
   assert(action.getDuration==ISReadABook.getDuration and action.minutesPerPage==2.0,'native reading timing changed');return action
  end end
  error('native literature menu did not enqueue book')
 end
 local function menuOption(context,spec,ids)
  for _,option in ipairs(context.options) do
   if option.target and option.target.Type==spec.handler then
    local match=not spec.hands or option.param1=='Hands'
    if not spec.hands and spec.supply and spec.supply[1] then
     local expected=assert(item(ids[spec.supply[1][1]])):getFullType()
     if spec.id=='readySplint' then match=option.param1==nil and option.param2==expected
     else match=option.param1==expected end
    end
    if match and option.onSelect then return option end
   end
   if option.subOption then local found=menuOption(context:getSubMenu(option.subOption),spec,ids);if found then return found end end
  end
 end
 local function enqueue(panel,body,spec,ids)
  assertMode()
  local before=#queue().queue
  run(function()
   if spec.drop then
    local values={};for _,entry in ipairs(spec.supply or {}) do values[#values+1]=assert(item(ids[entry[1]])) end
    panel:dropItemsOnBodyPart(body,values)
   else
    panel:doBodyPartContextMenu(body,0,0)
    local context=getPlayerContextMenu(player:getPlayerNum())
    local option=assert(menuOption(context,spec,ids),'native medical menu missing '..spec.handler)
    option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,option.param6,option.param7,option.param8)
    context:hideAndChildren()
   end
  end)
  local parent=assert(queue().queue[before+1],'native medical producer did not enqueue')
  assert(parent.Type=='HealthPanelAction','native medical parent contract missing')
  if not native then
   assert(Policy.inspect(parent),'medical parent permission missing')
   local description=Toolkit.ActionQueueDefinitions.describe(parent)
   assert(description.title and description.target,'native medical presentation lacks operation/patient/body part')
  end
  return parent
 end
 local function closeObserver()
  if observer then Events.OnPlayerUpdate.Remove(observer);observer=nil end
  if restoreHelper then ISHealthPanel.DidPatientMove=restoreHelper;restoreHelper=nil end
 end
 stage('medical native setup',function()
  player=getPlayer();assert(remote.ids())
  assertMode();assert(not player:isTimedActionInstant(),'native medical timing required')
  assert(Translator.getLanguage():name()==remote.language,'fixture language differs')
  if not native then Policy.setDiagnostics(true) end
 end,empty)
 for _,spec in ipairs(Cases) do
   local skipSent=false
   local prep,phase,front,tail,parent,panel,body,activePatient,requested=false,'prepare'
   local controlSent,observed,doneTick,observerProblem=false,false,nil,nil
   local positioned,subscribed,stableSince,baselineRequested=false,false,nil,false
   local bag,previousSecondary,bagVisible,bagHidden
   local removedAt,nativeObservation
   local function notReady() stableSince=nil;return false end
   local function mutation(mode)
    if not controlSent then remote.send('Mutate',{phase=spec.id,mode=mode});controlSent=true end
    local receipt=remote.mutations[spec.id]
    if not receipt then return false end
    assert(receipt.ok,receipt.error)
    if mode=='missing' then return not item(assert(prep.items.bandage)) end
    return true
   end
   stage('medical native '..spec.id,function()
    local skipReason=Selection.skipReason(spec,assert(remote.ids()).username)
    if skipReason then
     if not skipSent then remote.send('Skip',{phase=spec.id,reason=skipReason});skipSent=true end
     local receipt=remote.skips[spec.id];if not receipt then return false end;assert(receipt.ok,receipt.error)
     return {status='skipped',reason=skipReason}
    end
    assertMode()
    assert(not observerProblem,observerProblem)
    if phase=='prepare' then
     if not requested then remote.send('Prepare',{phase=spec.id});requested=true;return false end
     prep=remote.preparations[spec.id];if not prep then return notReady() end;assert(prep.ok,prep.error)
     activePatient=patient(prep.patient);if not activePatient then return notReady() end
     for _,id in pairs(prep.items) do if not item(id) then return notReady() end end
     if not positioned then Authority.position(player,prep.spawn.x,prep.spawn.y,prep.spawn.z);positioned=true;return notReady() end
     if player:pressedMovement(false) or player:tooDarkToRead() then return notReady() end
     if remote.kind=='sp' then body=player:getBodyDamage():getBodyPart(BodyPartType.FromIndex(prep.body))
     else
      if not subscribed then player:startReceivingBodyDamageUpdates(activePatient);subscribed=true;return notReady() end
      body=activePatient:getBodyDamageRemote():getBodyPart(BodyPartType.FromIndex(prep.body))
     end
     if not Authority.clinicalReady(body,assert(prep.readiness,'authority categorical readiness missing'))
      or not readyPosition(player,prep.spawn) or not readyPosition(activePatient,prep.patientSpawn) then return notReady() end
     local now=getTimestampMs();stableSince=stableSince or now
     if now-stableSince<500 then return false end
     if not baselineRequested then remote.send('Baseline',{phase=spec.id});baselineRequested=true;return false end
     local baseline=remote.baselines[spec.id];if not baseline then return false end;assert(baseline.ok,baseline.error)
     print('[QUEUE_TEST] HEALTH_READY phase='..spec.id..' stableMs='..(now-stableSince)..' actualPatient='..prep.patient..' categoricalState=true adjacentCentered=true')
     panel=ISHealthPanel:new(activePatient,0,0,400,400);panel:initialise()
     if activePatient~=player then panel:setOtherPlayer(player) end
     if spec.bag then
      bag=assert(item(prep.bag));previousSecondary=player:getSecondaryHandItem()
      assert(previousSecondary~=bag,'fixture schoolbag already equipped')
      Authority.setBagHand(player,bag,bag);bagVisible=true
     end
     front=read(prep.front,prep.frontPages);parent=enqueue(panel,body,spec,prep.items);tail=read(prep.tail,1)
     assert(queue():indexOf(front)<queue():indexOf(parent) and queue():indexOf(parent)<queue():indexOf(tail),'native queue order differs')
     if spec.cancel then local ok,why=API.cancelOperation(queue(),parent);assert(ok,'waiting medical cancel rejected '..tostring(why))
     elseif spec.move then
      local ok,why=API.move(queue(),parent,tail,true);assert(ok,'waiting medical reorder rejected '..tostring(why))
      ok,why=API.move(queue(),parent,tail,false);assert(ok,'waiting medical reorder restore rejected '..tostring(why))
     elseif spec.guard=='closed' then
      if activePatient==player then panel.character=nil else panel:tryStopReceivingBodyDamageUpdates() end
      assert(not Policy.inspect(parent),'closed panel kept permission')
     elseif spec.guard=='reassigned' then
      panel.character=activePatient==player and {} or player
      assert(not Policy.inspect(parent),'reassigned panel kept permission')
     elseif spec.guard=='helper' then
      restoreHelper=ISHealthPanel.DidPatientMove;ISHealthPanel.DidPatientMove=function(...) return restoreHelper(...) end
      assert(not Policy.inspect(parent),'changed native helper kept permission')
     end
     local observe=function(character)
      if character~=player or not parent then return end
      for _,child in ipairs(queue().queue) do
       if child~=parent and child.Type~='HealthPanelAction' and
        (native and child.Type=='ISDisinfect' and child.bodyPart==body or not native and child.toolkitQueueOperation==parent.toolkitQueueOperation) then
        local contract=not native and Policy.inspect(child)
        if spec.guard=='helper' then assert(not contract,'changed helper granted expanded-child permission');return end
        if not native then assert(contract,'expanded native medical child contract missing '..child.Type) end
        if not native and child.Type~='ISInventoryTransferAction' then assert(contract.targets and contract.targets[body],'expanded child lost body dependency') end
        if not native and child.Type=='ISStitch' then assert(contract.dynamicInputsByType and contract.dynamicInputsByType.SutureNeedleHolder,'expanded stitch lost late holder dependency') end
        local startedPrep=child.Type=='ISInventoryTransferAction' and child.action and child.action:isStarted() and not child.action:finished()
        if spec.bag and bagVisible and startedPrep then
         Authority.setBagHand(player,bag,previousSecondary);bagVisible=false;bagHidden=true
        end
        if spec.expanded and not observed then
         if spec.expanded=='cancel' and startedPrep and bagHidden then
          local ok,why=API.cancelOperation(queue(),child);assert(ok,'expanded chain cancel rejected '..tostring(why));observed=true
         elseif spec.expanded=='missing' and bagHidden and child.Type=='ISApplyBandage' and not child.action and item(prep.items.bandage) then
          remote.send('Mutate',{phase=spec.id,mode='missing'});controlSent=true;observed=true
         elseif spec.expanded=='stop' and child.action and child.action:isStarted() and not child.action:finished() then
          assert(child.stop==getmetatable(child).stop and child.complete==getmetatable(child).complete,'native stop/complete replaced')
          if native then child:forceStop()
          else local ok,why=API.cancelOperation(queue(),child);assert(ok,'active native medical stop rejected '..tostring(why)) end
          observed=true
         end
        end
       end
      end
     end
     observer=function(character) local ok,problem=pcall(observe,character);if not ok then observerProblem=tostring(problem) end end
     Events.OnPlayerUpdate.Add(observer);phase='control';return false
    elseif phase=='control' then
     if spec.guard=='missing' then if not mutation('missing') then return false end
     elseif spec.remote=='move' or spec.remote=='range' then
      if not mutation(spec.remote) then return false end
     elseif spec.remote=='removed' then
      if not controlSent then print('[QUEUE_TEST] PATIENT_DISCONNECT_REQUEST patient=client1 doctor=client2');controlSent=true end
      if patient(prep.patient) then return false end
      print('[QUEUE_TEST] PATIENT_DISCONNECTED actualOnlinePeerAbsent=true')
      removedAt=getTimestampMs()
     end
     phase='wait';return false
    elseif phase=='wait' then
     if native and spec.id=='remoteRemoved' and not nativeObservation then
      if empty() then nativeObservation={nativeStallObserved=false,queueDrained=true}
      elseif getTimestampMs()-assert(removedAt)<60000 then return false
      else
       assert(not patient(prep.patient),'native stall observation requires actual peer absence')
       local q=queue();local child=q.current
       assert(child and q.queue[1]==child and #q.queue==2 and q.queue[2]==tail,
        'native stall queue differs from exact clinical action and original tail')
       assert(child.Type=='ISApplyBandage' and child.character==player and child.otherPlayer==activePatient
        and child.bodyPart==body and child.item==item(prep.items.bandage) and child.doIt==true
        and child.action and child.action:isStarted() and not child.action:finished(),
        'native stall is not the exact started unfinished fixture bandage action')
       assert(front.item==item(prep.front) and front.item:getAlreadyReadPages()==front.item:getNumberOfPages(),
        'native stall front book did not finish')
       assert(tail.Type=='ISReadABook' and tail.item==item(prep.tail)
        and tail.item:getAlreadyReadPages()==tail.item:getNumberOfPages()-1,'native stall original tail already changed')
       assert(child.stop==getmetatable(child).stop and child.complete==getmetatable(child).complete,'native stall stop/complete replaced')
       nativeObservation={nativeStallObserved=true,nativeCurrentType=child.Type,queueDrained=false,
        nativeObservationMs=getTimestampMs()-removedAt,nativeObservationSince='actual peer disappearance',nativeTailCompletedBeforeCleanup=false,
        nativeCleanup='forceStop owned clinical action after bounded observation'}
       print('[QUEUE_TEST] HEALTH_NATIVE_STALL phase='..spec.id..' current='..child.Type..' queueDrained=false observationMs='..nativeObservation.nativeObservationMs..' cleanup=forceStopOwnedClinicalAction')
       child:forceStop();return false
      end
     end
     if not empty() then return false end
     if nativeObservation and nativeObservation.nativeStallObserved then nativeObservation.cleanupQueueDrained=true end
     if spec.expanded then assert(observed,'expanded child interception did not execute') end
     if spec.bag then
      assert(bagHidden and not ISInventoryPaneContextMenu.getContainers(player):contains(bag:getItemContainer()),'return destination was exposed through native getter')
      assert(Policy.isCarriedContainer(bag:getItemContainer(),player),'return destination stopped being carried')
     end
     if spec.expanded=='missing' then
      local result=remote.mutations[spec.id];if not result then return false end;assert(result.ok and not item(prep.items.bandage),'missing child supply mutation missing')
     end
     closeObserver()
     if not doneTick then doneTick=getTimestampMs();return false end
     if getTimestampMs()-doneTick<1000 then return false end
     remote.send('Verify',{phase=spec.id});phase='receipt';return false
    else
     local result=remote.receipts[spec.id];if not result then return false end
     if nativeObservation then result.outcome=result.outcome or {};for key,value in pairs(nativeObservation) do result.outcome[key]=value end end
     assert(result.ok,result.error)
     assert(result.front==prep.front and result.tail==prep.tail,'authority receipt changed book identities')
     print('[QUEUE_TEST] HEALTH_RECEIPT phase='..spec.id..' authority='..(isClient() and 'server' or 'sp')..' actualPatient='..prep.patient)
     return {status='passed',outcome=result.outcome}
    end
   end,nil,spec.id)
 end
 stage('medical native cleanup',function()
  closeObserver()
  print('[QUEUE_TEST] HEALTH_NATIVE_COMPLETE nativeDurations=true selectedCases='..#Cases..' mode='..Selection.mode)
 end,empty)
end
