require 'PZSurvivorToolkit/ActionQueuePanel'
require 'TimedActions/ISDrinkFluidAction'
require 'TimedActions/ISWearClothing'
require 'TimedActions/ISUnequipAction'
local Fixture=require 'QueueFluidFixture'
local Checks=require 'QueueScenarioChecks'
local Queue=require 'PZSurvivorToolkit/ActionQueue'
local Policy=require 'PZSurvivorToolkit/ActionQueuePolicy'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local started,done=false,false
local step,failed,phase,since,idle=1,0,'prepare',0,0
local ids,state,authorityState,receipt,spec
local previousAuthority,previousBag,lastCurrent
local commands,observations={},{}
local waitingCancelVerified=false
local independentMoveVerified=false
local function case()return config.cases[step]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function emit(row)
 row.suite,row.kind,row.mode,row.actor='fluid',config.kind,config.mode,'client1';JSON.emit(row)
end
local function trace(event,value)
 local row={}
 for key,item in pairs(value or {})do row[key]=item end
 row.case=case();row.event=event
 print('[FLUID_TEST] TRACE '..JSON.encode(row))
end
local function request(command)
 if isClient()then sendClientCommand('FluidTest',command,{case=case()});return end
 if command=='Prepare'then
  authorityState=Fixture.prepare(getPlayer(),case(),previousAuthority);previousAuthority=nil;ids=authorityState.ids
  print('[FLUID_TEST] PREPARED '..JSON.encode(ids))
 else
  receipt=assert(Fixture.verify(authorityState))
  print('[FLUID_TEST] VERIFIED '..JSON.encode(receipt))
 end
end
Events.OnServerCommand.Add(function(module,command,value)
 if module=='PZSurvivorToolkitActions'and command=='State'and phase=='running'then
  trace('native-state',{kind=value.kind,state=value.state,transaction=value.transaction,player=value.player,token=value.token})
  return
 end
 if module~='FluidTest'then return end
 assert(command~='Failed',value.error)
 if command=='Prepared'then ids=value elseif command=='Verified'then receipt=value end
end)
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs()
 getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false)
 getPlayer():setAutoDrink(false);getPlayer():setGhostMode(true)
end)
local function enqueue(player,target)
 local bottle=assert(player:getInventory():getItemById(ids.bottles[target].id))
 assert(bottle:getContainer()==state.bag:getItemContainer()or bottle:getContainer()==player:getInventory(),'unexpected dispatch container')
 local previous=observations[#observations]
 assert(PZSurvivorToolkit.Settings.actionQueue()==(config.mode=='toolkit'),'fluid queue switch differs')
 local command={queueEmptyBefore=#queue().queue==0 and not player:hasTimedActions(),
  previousDrinkPending=previous~=nil and queue():indexOf(previous.drink)~=-1,
  backpackWorn=player:getClothingItem_Back()==state.bag,
  dispatchAmount=bottle:getFluidContainer():getAmount(),
  dispatchSource=bottle:getContainer()==state.bag:getItemContainer()and 'bag'or 'root',cancelled=false,
  id=bottle:getID(),menu=spec.menu,pickupObserved=false,drinkProgress=false,menuDispatched=false,
  dispatchThirst=player:getStats():get(CharacterStat.THIRST),foodLevel=player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN)}
 local observed={actions={}};local add=ISTimedActionQueue.add
 ISTimedActionQueue.add=function(action)
  observed.actions[#observed.actions+1]=action
  if action.Type=='ISInventoryTransferAction'and action.item:getID()==command.id
   and action.destContainer==player:getInventory()then assert(not observed.pickup,'duplicate bottle pickup');observed.pickup=action end
  if action.Type=='ISDrinkFluidAction'then
   assert(not observed.drink,'duplicate drink');observed.drink=action;command.nativeDuration=action.maxTime
  end
  return add(action)
 end
 local ok,problem=pcall(function()
  SandboxVars.DrinkSmart=SandboxVars.DrinkSmart or {}
  SandboxVars.DrinkSmart.AddSipOption=spec.menu=='sip'
  SandboxVars.DrinkSmart.AllowWaterDrinkLowThirst=spec.menu=='smart'
  local menu=assert(ISInventoryPaneContextMenu.createMenu(player:getPlayerNum(),true,{bottle},20,20),'inventory menu missing')
  local label=spec.menu=='smart'and ('0% '..getText('Tooltip_food_Thirst'))
   or spec.menu=='sip'and getText('ContextMenu_DrinkSmart_Sip')
   or getText('ContextMenu_Eat_'..(spec.menu=='all'and 'All'or spec.menu=='quarter'and 'Quarter'or 'Half'))
  for _,option in ipairs(menu.options)do
   if option.subOption then
    local submenu=menu:getSubMenu(option.subOption)
    menu:displaySubMenu(submenu,option)
    for index,portion in ipairs(submenu.options)do
     local matches=spec.menu=='smart'and portion.name:sub(1,#label)==label or portion.name==label
     if matches and portion.onSelect==ISInventoryPaneContextMenu.onDrinkFluid and portion.target==bottle then
      command.portion=portion.param1;command.menuDispatched=true
      submenu.mouseOver=index;submenu:onJoypadDown(Joypad.AButton)
      return
     end
    end
   end
  end
  error('drink menu option missing: '..label)
 end)
 ISTimedActionQueue.add=add
 assert(ok,problem);assert(observed.drink and observed.drink.item:getID()==command.id,'native drink action missing')
 assert((observed.pickup~=nil)==(command.dispatchSource=='bag'),'native pickup presence differs')
 commands[#commands+1]=command;observations[#observations+1]=observed
 trace('dispatch',command)
end
local function cancelWaiting()
 if not spec.cancel or config.mode~='toolkit'then return end
 local removed,retained=observations[2].actions,{}
 assert(queue().queue[1]~=observations[2].drink and not observations[2].drink:isStarted(),'cancel target already active')
 if spec.source=='root'then
  assert(#removed==1 and #observations[3].actions==1,'root drink must be a single-action operation')
  Checks.moveRoundtrip(queue(),Queue,Policy,observations[2].drink,observations[3].drink,true,observations[3].drink,false)
  independentMoveVerified=true
 end
 for _,index in ipairs({1,3})do for _,action in ipairs(observations[index].actions)do retained[#retained+1]=action end end
 Checks.waitingCancel(queue(),Queue,Policy,observations[2].drink,removed,retained)
 commands[2].cancelled=true;waitingCancelVerified=true
 trace('waiting-cancel',{id=commands[2].id,removed=#removed,retained=#retained})
end
local function finish()
 local reason
 for index,bottle in ipairs(receipt.bottles)do
  local expected=ids.bottles[index].amount
  local tolerance=0
  for _,command in ipairs(commands)do if command.id==bottle.id then
   if command.cancelled then
    if command.drinkProgress or command.pickupObserved then reason='cancelled-action-started'end
   else
    local base=config.kind=='mp'and not spec.serial and expected or command.dispatchAmount
    expected=base*(1-command.portion);tolerance=tolerance*(1-command.portion)+.01
    if not command.drinkProgress then reason='drink-not-started'end
    if command.dispatchSource=='bag'and not command.pickupObserved then reason='pickup-not-observed'end
   end
  end end
  if bottle.amount<math.max(0,expected-tolerance)or bottle.amount>expected+.0001 then
   reason='portion-consumption-differs'
  end
 end
 if receipt.thirst>=ids.thirst-.00001 then reason='thirst-not-reduced'end
 local row={event='case',id=case(),status=reason and 'failed'or 'passed',reason=reason,commands=commands,
  waitingCancelVerified=waitingCancelVerified,independentMoveVerified=independentMoveVerified}
 for key,value in pairs(receipt)do row[key]=value end
 emit(row);if reason then failed=failed+1 end
 step=step+1
 if not case()then
  emit({event='complete',cases=config.cases,expected=#config.cases,performed=step-1,failed=failed,skipped=0})
  print('[FLUID_TEST] COMPLETE');done=true;return
 end
 previousAuthority=authorityState;previousBag=state.bag
 ids,state,authorityState,receipt,lastCurrent=nil,nil,nil,nil,nil
 commands,observations={},{};waitingCancelVerified=false;independentMoveVerified=false
 ISTimedActionQueue.add(ISUnequipAction:new(getPlayer(),previousBag,50))
 phase='unequipped';since=getTimestampMs()
end
Events.OnTick.Add(function()
 if not started or done or not isIngameState()or not getPlayer()or not getPlayer():getSquare()then return end
 local ok,problem=pcall(function()
  local player=getPlayer();getCore():setOptionAutoDrink(false);player:setAutoDrink(false)
  if getTimestampMs()-since>90000 then error('fluid phase timeout '..phase)end
  idle=(not player:hasTimedActions()and #queue().queue==0)and idle+1 or 0
  if phase=='unequipped'then
   if idle<10 then return end
   assert(not player:isEquipped(previousBag),'previous fluid bag still equipped');phase='prepare'
  end
  if phase=='prepare'then
   if step==1 then emit({event='setup',cases=config.cases,expected=#config.cases,queueEnabled=PZSurvivorToolkit.Settings.actionQueue(),nativeDurations=true})end
   spec=Fixture.scenario(case());phase='prepared';request('Prepare');return
  elseif phase=='prepared'and ids then
   state=Fixture.resolve(player,ids);if not state then return end
   player:getStats():set(CharacterStat.THIRST,ids.thirst)
   player:getBodyDamage():setHealthFromFoodTimer(ids.foodTimer);player:getMoodles():Update()
   if isClient()then syncPlayerStats(player,SyncPlayerStatsPacket.getBitMaskForStat(CharacterStat.THIRST))end
   ISTimedActionQueue.add(ISWearClothing:new(player,state.bag,50))
   phase='equipped';return
  elseif phase=='equipped'then
   if idle<10 then return end
   assert(player:getClothingItem_Back()==state.bag,'fixture military backpack not on back')
   assert(player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN)==ids.foodLevel,'fixture fullness differs')
   enqueue(player,spec.targets[1])
   if not spec.serial then for index=2,#spec.targets do enqueue(player,spec.targets[index])end end
   cancelWaiting()
   phase='running';since=getTimestampMs();return
  elseif phase=='running'then
   local current=queue().queue[1]
   if current~=lastCurrent then
    trace('queue-current',{actionType=current and current.Type or 'idle',itemId=current and current.item and current.item:getID()})
    lastCurrent=current
   end
   for index,observed in ipairs(observations)do
    local command=commands[index]
    if observed.pickup and current==observed.pickup and current:isStarted()and current:getJobDelta()>0 then
     if not command.pickupObserved then trace('pickup-progress',{id=command.id})end
     command.pickupObserved=true
    end
    if current==observed.drink and current:isStarted()and current:getJobDelta()>0 then
     if not command.drinkProgress then trace('drink-progress',{id=command.id,amount=current.item:getFluidContainer():getAmount()})end
     command.drinkProgress=true
     local bottle=assert(player:getInventory():getItemById(command.id))
     assert(bottle:getContainer()==player:getInventory(),'drink started outside root')
     assert(bottle:isFavorite()==spec.favorite,'drink bottle lost favorite flag')
    end
   end
   if idle>=10 then
    if spec.serial and #commands<#spec.targets then enqueue(player,spec.targets[#commands+1]);idle=0
    else phase='receipt';request('Verify')end
   end
  elseif phase=='receipt'and receipt then finish()end
 end)
 if not ok then print('[QUEUE_TEST] FAIL fluid client '..tostring(problem));done=true end
end)
