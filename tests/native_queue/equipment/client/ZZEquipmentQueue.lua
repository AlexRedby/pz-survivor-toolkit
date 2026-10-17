require 'PZSurvivorToolkit/ActionQueuePanel'
local Selection=require 'QueueEquipmentSelection'
local Fixture=require 'QueueEquipmentFixture'
local JSON=require 'QueueHealthEvents'
local Toolkit=PZSurvivorToolkit
local API,Policy,Ops=Toolkit.ActionQueue,Toolkit.ActionQueuePolicy,Toolkit.ActionQueueOperations
local native=Selection.mode=='native'
local option=assert(PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'))
option:setValue(not native)
local entered,starting,started,done=false,false,false,false
local index,performed,failures,since=1,0,0,0
local state,phase=nil,'prepare'
local function emit(event)
 event.suite='equipment';event.kind='sp';event.mode=Selection.mode;event.actor='client1';JSON.emit(event)
end
local function complete()
 if done then return end;done=true
 emit({event='complete',cases=Selection.cases,expected=#Selection.cases,performed=performed,skipped=0,failed=failures})
 print('[EQUIPMENT_TEST] COMPLETE')
end
local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()) end
local function empty() return #queue().queue==0 and not getPlayer():hasTimedActions() end
local function run(fn,...) if native then return fn(...) end;return Ops.run(fn,...) end
local function snapshot()
 local result={};for i,action in ipairs(queue().queue) do result[i]=action end;return result
end
local function unchanged(expected)
 assert(#expected==#queue().queue,'denied control changed queue size')
 for i,action in ipairs(expected) do assert(queue().queue[i]==action,'denied control changed queue order') end
end
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
 run(ISInventoryPaneContextMenu.equipWeapon,item,primary,both,getPlayer():getPlayerNum())
 local first,last=queue().queue[before+1],queue().queue[#queue().queue]
 assert(first and last.Type=='ISEquipWeaponAction' and last.item==item,'native equip callback missing')
 return first,last
end
local function enqueue()
 state.frontAction=read(state.front)
 if state.id=='bag-capacity' then
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
 else
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
 end
 state.tailAction=read(state.tail)
end
local function denied(action,target,after,reason)
 local before=snapshot();local decision=Policy.evaluateMove(queue(),action,target,after)
 assert(not decision.allowed and decision.reason==reason,'unexpected policy barrier '..tostring(decision.reason))
 local ok,actual=API.move(queue(),action,target,after)
 assert(not ok and actual==reason,'queue API did not preserve policy barrier');unchanged(before)
end
local function controls()
 if native then return end
 if state.id=='hands-chain' then
  denied(state.pickupAction,state.hammerAction,true,'container_capacity')
  denied(state.hammerAction,state.pickupAction,false,'container_capacity')
  denied(state.hammerAction,state.screwdriverAction,true,'move_dependent')
  denied(state.screwdriverAction,state.hammerAction,false,'move_dependent')
  local before=snapshot()
  assert(Policy.evaluateMove(queue(),state.tailAction,state.pickupAction,false).allowed,'independent book move should be allowed')
  assert(API.move(queue(),state.tailAction,state.pickupAction,false),'independent book move failed')
  assert(API.move(queue(),state.tailAction,state.screwdriverAction,true),'independent book restore failed');unchanged(before)
 elseif state.id=='waiting-cancel' then
  local decision=Policy.evaluateCancel(queue(),state.pickupAction,true)
  assert(decision.allowed,'actual waiting pickup/equip operation cannot be cancelled '..tostring(decision.reason))
  assert(API.cancelOperation(queue(),state.pickupAction),'waiting pickup/equip cancellation failed')
  assert(queue():indexOf(state.pickupAction)==-1 and queue():indexOf(state.equipAction)==-1,'whole equipment operation was not removed')
  assert(queue():indexOf(state.frontAction)~=-1 and queue():indexOf(state.tailAction)~=-1,'cancellation removed unrelated books')
 else
  denied(state.pickupAction,state.replacementAction,true,'container_capacity')
  denied(state.replacementAction,state.pickupAction,false,'container_capacity')
 end
 state.policyChecked=true
end
Events.OnMainMenuEnter.Add(function() entered=true end)
Events.OnPreUIDraw.Add(function()
 if done then return end
 if started and isIngameState() and isGamePaused() then setGameSpeed(1) end
 if not entered or starting or isIngameState() then return end;starting=true
 local ok,problem=pcall(function()
 getCore():setOptionPauseOnFocusloss(false)
 getWorld():setGameMode('Sandbox');getWorld():setWorld('QueueEquipmentSP');getWorld():setMap('Muldraugh, KY')
 MainScreen.instance:setDefaultSandboxVars()
 for name,value in pairs({Zombies=6,StartMonth=7,StartDay=9,StartTime=2,MinutesPerPage=2.0}) do
  getSandboxOptions():getOptionByName(name):setValue(value)
 end
 getSandboxOptions():toLua()
 local current,active=ActiveMods.getById('currentGame'),getActivatedMods();current:getMods():clear()
 for i=0,active:size()-1 do current:getMods():add(active:get(i)) end
 MainScreen.instance.createWorld=true
 MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=10835,posY=10144,posZ=0}}}}
 MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
 MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
 end)
 if not ok then failures=failures+1;emit({event='error',reason=tostring(problem)});complete() end
end)
Events.OnGameStart.Add(function()
 local ok,problem=pcall(function()
  local player=assert(getPlayer());assert(not isClient() and not isServer(),'equipment is true SP only')
  assert(Translator.getLanguage():name()==Selection.language,'equipment language differs')
  assert(Toolkit.Settings.actionQueue()==(not native),'equipment queue mode differs')
  assert(not player:isTimedActionInstant(),'native equipment duration required')
  player:setGhostMode(true);getCore():setOptionAutoDrink(false);player:setAutoDrink(false)
  if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
  Fixture.position(player)
  emit({event='setup',cases=Selection.cases,expected=#Selection.cases,language=Selection.language,nativeDurations=true,queueEnabled=not native})
  started=true;since=getTimestampMs()
 end)
 if not ok then failures=failures+1;emit({event='error',reason=tostring(problem)});complete() end
end)
Events.OnTick.Add(function()
 if not started or done then return end
 local now=getTimestampMs()
 local ok,problem=pcall(function()
  assert(now-since<600000,'native equipment case deadline '..Selection.cases[index])
  assert(Toolkit.Settings.actionQueue()==(not native),'equipment queue mode changed')
  if phase=='prepare' then
   if not empty() or getPlayer():isPlayerMoving() or getPlayer():tooDarkToRead() then return end
   state=Fixture.prepare(getPlayer(),Selection.cases[index]);enqueue();phase='controls'
  elseif phase=='controls' then
   assert(queue():indexOf(state.frontAction)~=-1,'front finished before waiting controls')
   if queue().current~=state.frontAction or not state.frontAction.action or not state.frontAction.action:isStarted() then return end
   controls();phase='verify'
  elseif empty() then
   assert(native or state.policyChecked,'toolkit policy evidence missing')
   local outcome=Fixture.verify(state,Selection.mode)
   Fixture.cleanup(state)
   performed=performed+1
   emit({event='case',id=state.id,status='passed',outcome=outcome})
   print('[EQUIPMENT_TEST] RECEIPT case='..state.id)
   index=index+1;since=now;phase='prepare';state=nil
   if index>#Selection.cases then complete() end
  end
 end)
 if not ok then
  failures=failures+1;performed=performed+1
  emit({event='case',id=Selection.cases[index],status='failed',reason=tostring(problem)})
  print('[QUEUE_TEST] FAIL equipment '..tostring(problem));complete()
 end
end)
