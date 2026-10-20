require 'PZSurvivorToolkit/ActionQueuePanel'
require 'TimedActions/ISEatFoodAction'
require 'TimedActions/ISDrinkFluidAction'
require 'TimedActions/ISWearClothing'
require 'TimedActions/ISUnequipAction'
require 'TimedActions/ISInventoryTransferAction'
local Fixture=require 'QueueFoodFixture'
local Checks=require 'QueueScenarioChecks'
local Progress=require 'QueueFoodProgress'
local Queue=require 'PZSurvivorToolkit/ActionQueue'
local Policy=require 'PZSurvivorToolkit/ActionQueuePolicy'
local Operations=require 'PZSurvivorToolkit/ActionQueueOperations'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local started,done=false,false
local step,failed,phase,since,idle=1,0,'prepare',0,0
local ids,state,authority,receipt,previous,previousBag,spec,anchor
local commands,observed,evidence,observer={},{},nil,nil
local function case()return config.cases[step]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function emit(row)
 row.suite,row.kind,row.mode,row.actor='food',config.kind,config.mode,'client1';JSON.emit(row)
end
local function request(command)
 if isClient()then sendClientCommand('FoodTest',command,{case=case()});return end
 if command=='Prepare'then
  authority=Fixture.prepare(getPlayer(),case(),previous);previous=nil;ids=authority.ids
  print('[FOOD_TEST] PREPARED '..JSON.encode(ids))
 else receipt=assert(Fixture.verify(authority));print('[FOOD_TEST] VERIFIED '..JSON.encode(receipt))end
end
Events.OnServerCommand.Add(function(module,command,value)
 if module~='FoodTest'then return end
 assert(command~='Failed',value.error)
 if command=='Prepared'then ids=value elseif command=='Verified'then receipt=value end
end)
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs();getCore():setOptionPauseOnFocusloss(false)
 getCore():setOptionAutoDrink(false);getPlayer():setAutoDrink(false);getPlayer():setGhostMode(true)
end)
local function items()return assert(Fixture.items(getPlayer(),ids),'current exact food identities missing')end
local function capture(callback)
 local actions={};local add=ISTimedActionQueue.add
 ISTimedActionQueue.add=function(action)actions[#actions+1]=action;return add(action)end
 local ok,problem=pcall(callback);ISTimedActionQueue.add=add;assert(ok,problem);return actions
end
local function smartOption(player,food,goal)
 local options=assert(PZAPI.ModOptions:getOptions('EatSmart'))
 local enabled,target=options:getOption('2'),options:getOption('3')
 local oldEnabled,oldTarget=enabled:getValue(),target:getValue()
 enabled:setValue(true);target:setValue(goal)
 local menu=ISContextMenu.get(player:getPlayerNum(),0,0)
 local ok,problem=pcall(ES_subMenuEat,menu,{food},{food},player:getPlayerNum(),player)
 enabled:setValue(oldEnabled);target:setValue(oldTarget);menu:setVisible(false)
 assert(ok,problem)
 local hunger=player:getStats():get(CharacterStat.HUNGER)
 local fraction=(hunger-goal/100)/-food:getBaseHunger()
 local found
 for _,option in ipairs(menu.options)do
  if option.ES_EatSmart and option.onSelect and not option.notAvailable and not option.param5
   and type(option.param1)=='number'and math.abs(option.param1-fraction)<.000001 then
   assert(not found,'ambiguous EatSmart hunger option');found=option
  end
 end
 assert(found and found.target[1]==food and found.param2==player:getPlayerNum(),'EatSmart goal unavailable')
 return found,hunger
end
local function eat(portion,menu,smartGoal)
 local player=getPlayer();local food=items().food
 local option,dispatchHunger
 if smartGoal then option,dispatchHunger=smartOption(player,food,smartGoal);portion=option.param1 end
 local command={id=food:getID(),portion=portion,baseHunger=food:getBaseHunger(),dispatchRemaining=food:getHungChange(),
  dispatchSource=food:getContainer()==player:getInventory()and 'root'or 'bag',menuDispatched=menu,
  nativeDuration=0,progress=false,cancelled=false,pickupObserved=false}
 if smartGoal then command.smartGoal=smartGoal;command.dispatchHunger=dispatchHunger end
 if spec.cookable then command.cooked,command.dispatchHeat=food:isCooked(),food:getHeat()end
 local actions=capture(function()
  if option then
   Operations.run(option.onSelect,option.target,option.param1,option.param2,option.param3,option.param4,option.param5)
  elseif menu then Operations.run(ISInventoryPaneContextMenu.eatItem,food,portion,player:getPlayerNum())
  else ISTimedActionQueue.add(ISEatFoodAction:new(player,food,portion))end
 end)
 assert(#actions==1 and actions[1].Type=='ISEatFoodAction'and actions[1].item:getID()==ids.foodId,
  'ordinary native eat must be exactly one action')
 local action=actions[1];assert(action.useUtensil==spec.utensil and action.percentage==portion,'unexpected utensil/portion')
 if spec.utensil then
  local current=items();local selected=spec.cancel and current.spoon or current.fork
  local second=action:getSecondItem()
  assert(second and second:getID()==selected:getID(),'native selected utensil differs')
  command.useUtensil,command.utensilId=true,second:getID()
  command.forkId,command.spoonId=action.fork and action.fork:getID()or -1,action.spoon and action.spoon:getID()or -1
 end
 command.nativeDuration=action.maxTime;assert(action.maxTime==action:getDuration()and action.maxTime==(portion==1 and 464 or 232),'native eat duration differs')
 commands[#commands+1]=command;observed[#observed+1]={eat=action,actions=actions}
 return action
end
local function observeReturn(returning)
 local q=queue();local previousCallback,previousRaw=q.onCompleted,rawget(q,'onCompleted')
 local record=evidence.returning;local pendingBefore
 local function endpoint()
  local current=Fixture.items(getPlayer(),ids)
  if not current then error('return identity unresolved')end
  local source=current.food:getContainer()
  return source==getPlayer():getInventory()and 'root'or source==current.bag:getItemContainer()and 'bag'or 'unknown'
 end
 local function recordSafely(fn)
  local ok=pcall(fn);if not ok then record.observationFailed=true end
 end
 local callback
 callback=function(self,action)
  local imminent=action~=nil and returning~=nil and self.current==action and self.queue[1]==action and self.queue[2]==returning
  local completing=action~=nil and returning~=nil and action==returning and self.current==returning and self.queue[1]==returning
  local after
  recordSafely(function()if imminent then pendingBefore=endpoint()end;if completing then after=endpoint()end end)
  -- The observer never asserts or prevents the native completion delegate from running.
  local result=previousCallback(self,action)
  recordSafely(function()
   if imminent and(self.current==returning or self:indexOf(returning)==-1)and not record.boundary then
    record.before=pendingBefore;record.boundary=true
   end
   if completing and self:indexOf(returning)==-1 then
    record.before=pendingBefore or 'unknown';record.after=after;record.boundary=pendingBefore~=nil;record.completed=true
   end
  end)
  return result
 end
 q.onCompleted=callback;observer={queue=q,callback=callback,previous=previousRaw,returning=returning}
end
local function dispatch()
 local player=getPlayer();local current=items();local food,bag=current.food,current.bag:getItemContainer()
 assert(Progress.running(queue().current,anchor),'food needs running native anchor')
 evidence.anchorRunning=true;evidence.untouchedBefore=false
 if spec.bag then
  local actions=capture(function()Operations.run(ISInventoryPaneContextMenu.onGrabItems,{food},player:getPlayerNum())end)
  assert(#actions==1,'manual food pickup count differs')
  local pickup=actions[1];assert(pickup.Type=='ISInventoryTransferAction'and pickup.item:getID()==ids.foodId
   and pickup.srcContainer==bag and pickup.destContainer==player:getInventory(),'manual food grab differs')
  local eating=eat(.5,false);observed[1].pickup=pickup
  local returning=ISInventoryTransferAction:new(player,food,player:getInventory(),bag);ISTimedActionQueue.add(returning)
  for _,action in ipairs({pickup,eating,returning})do
   local first,last=Operations.bounds(queue(),action);assert(first==last and first==queue():indexOf(action),'explicit action not standalone')
  end
  evidence.pickupDuration=pickup.maxTime;evidence.returnDuration=returning.maxTime;evidence.manualPickup=true
  evidence.returning={boundary=false,completed=false,observationFailed=false}
  if config.mode=='toolkit'then
   for _,action in ipairs({pickup,eating,returning})do local contract=Policy.inspect(action);assert(contract and contract.edit,'food edit contract missing')end
   evidence.contractsVerified=true
   assert(Policy.evaluateMove(queue(),returning,pickup,false).allowed,'return-before-pickup denied')
   assert(Queue.move(queue(),returning,pickup,false),'return-before-pickup move failed');evidence.reordered=true
   Checks.unchanged(queue(),{anchor,returning,pickup,eating})
   Checks.deniedMove(queue(),Queue,Policy,pickup,eating,true,'edit_required_state');evidence.moveRejected=true
   Checks.deniedCancel(queue(),Queue,Policy,pickup,'edit_required_state');evidence.cancelRejected=true
  else Checks.unchanged(queue(),{anchor,pickup,eating,returning})end
  assert(pickup.maxTime==evidence.pickupDuration and returning.maxTime==evidence.returnDuration,'transfer duration changed')
  observeReturn(returning)
 else
  local half=eat(spec.utensil and .625 or spec.depletion and .25 or .5,true,spec.smart and 15 or nil)
  local quarter=eat(spec.utensil and .125 or spec.depletion and 1 or .25,true,spec.smart and 5 or nil)
  if config.mode=='toolkit'then
   for _,action in ipairs({half,quarter})do local contract=Policy.inspect(action);assert(contract and contract.edit,'ordinary food contract missing')end
   evidence.contractsVerified=true
   if spec.depletion then
    Checks.deniedMove(queue(),Queue,Policy,quarter,half,false,'edit_resource_amount')
    Checks.unchanged(queue(),{anchor,half,quarter});evidence.moveRejected=true;evidence.denialReason='edit_resource_amount'
   elseif spec.cancel then
    Checks.waitingCancel(queue(),Queue,Policy,half,{half},{anchor,quarter})
    commands[1].cancelled=true;evidence.waitingCancel=true
   else
    assert(Policy.evaluateMove(queue(),quarter,half,false).allowed,'same-food original portions move denied')
    assert(Queue.move(queue(),quarter,half,false),'same-food move failed')
    Checks.unchanged(queue(),{anchor,quarter,half});evidence.reordered=true
   end
  else Checks.unchanged(queue(),{anchor,half,quarter})end
 end
 local fresh=items();assert(fresh.food:getHungChange()==ids.remaining and fresh.food:getBaseHunger()==ids.baseHunger
  and fresh.food:getContainer()==(spec.bag and fresh.bag:getItemContainer()or player:getInventory()),'edit touched pending food')
 for index,value in ipairs(observed)do
  local action,command=value.eat,commands[index]
  assert(action.maxTime==command.nativeDuration and action.percentage==command.portion
   and action.useUtensil==spec.utensil,'edit changed native eating duration, portion or utensil flag')
  if spec.utensil then
   local selected=action:getSecondItem()
   assert(selected and selected:getID()==command.utensilId
    and (action.fork and action.fork:getID()or -1)==command.forkId
    and (action.spoon and action.spoon:getID()or -1)==command.spoonId,'edit changed captured native cutlery')
  end
  if spec.cookable then
   assert(action.item:isCooked()==command.cooked and action.item:getHeat()>=0 and action.item:getHeat()<=1.6,
    'edit changed stable cooking state')
  end
 end
 evidence.untouchedBefore=true;evidence.nativeDurationsUnchanged=true
end
local function clientReady()
 local current=Fixture.snapshot(getPlayer(),ids);if not current then return end
 for field,value in pairs(receipt)do
  if type(value)=='number'then
   local tolerance=(field=='hunger'or field=='thirst')and .01 or .0001
   if type(current[field])~='number'or math.abs(current[field]-value)>tolerance then return end
  elseif current[field]~=value then return end
 end
 return current
end
local function finish(localReceipt)
 -- Resolve Host Java proxies afresh, compare the authoritative item endpoints and counts.
 for _,field in ipairs({'bagId','bagType','bagCount','foodId','foodType','source','foodCount','foodTypeCount','deleted','anchorId','anchorType','anchorCount'})do
  assert(localReceipt[field]==receipt[field],'client authority differs: '..field)
 end
 for _,field in ipairs({'baseHunger','remaining','anchorAmount','hunger','thirst'})do
  assert(math.abs(localReceipt[field]-receipt[field])<=((field=='hunger'or field=='thirst')and .01 or .0001),'client authority numerical mismatch: '..field)
 end
 if observer then
  local returning=observer.returning;evidence.returning.started=returning.started;evidence.returning.transactionId=returning.transactionId
  evidence.returning.dontAdd=returning.dontAdd
  assert(observer.queue.onCompleted==observer.callback,'food return observer replaced')
  observer.queue.onCompleted=observer.previous;observer=nil
 end
 local row={event='case',id=case(),status='passed',commands=commands,editEvidence=evidence,client=localReceipt}
 for key,value in pairs(receipt)do row[key]=value end;emit(row)
 step=step+1
 if not case()then
  emit({event='complete',cases=config.cases,expected=#config.cases,performed=step-1,failed=failed,skipped=0});print('[FOOD_TEST] COMPLETE');done=true;return
 end
 previous=authority;previousBag=assert(Fixture.items(getPlayer(),ids,true)).bag
 ids,state,authority,receipt,anchor=nil,nil,nil,nil,nil;commands,observed,evidence={},{},nil
 ISTimedActionQueue.add(ISUnequipAction:new(getPlayer(),previousBag,50));phase='unequipped';since=getTimestampMs()
end
Events.OnTick.Add(function()
 if not started or done or not isIngameState()or not getPlayer()or not getPlayer():getSquare()then return end
 local ok,problem=pcall(function()
  local player=getPlayer();getCore():setOptionAutoDrink(false);player:setAutoDrink(false)
  if getTimestampMs()-since>120000 then error('food phase timeout '..phase)end
  idle=not player:hasTimedActions()and #queue().queue==0 and idle+1 or 0
  if phase=='unequipped'then if idle<10 then return end;assert(not player:isEquipped(previousBag),'food bag still worn');phase='prepare'end
  if phase=='prepare'then
   if step==1 then emit({event='setup',cases=config.cases,expected=#config.cases,queueEnabled=PZSurvivorToolkit.Settings.actionQueue(),nativeDurations=true})end
   spec=Fixture.scenario(case());phase='prepared';request('Prepare');return
  elseif phase=='prepared'and ids then
   state=Fixture.resolve(player,ids);if not state then return end
   player:getStats():set(CharacterStat.HUNGER,ids.hunger);player:getStats():set(CharacterStat.THIRST,ids.thirst)
   player:getBodyDamage():setHealthFromFoodTimer(0);player:getMoodles():Update()
   if isClient()then syncPlayerStats(player,SyncPlayerStatsPacket.getBitMaskForStat(CharacterStat.HUNGER)+SyncPlayerStatsPacket.getBitMaskForStat(CharacterStat.THIRST))end
   ISTimedActionQueue.add(ISWearClothing:new(player,state.bag,50));phase='equipped';return
  elseif phase=='equipped'then
   if idle<10 then return end
   assert(player:getClothingItem_Back()==items().bag,'food bag not worn')
   assert(PZSurvivorToolkit.Settings.actionQueue()==(config.mode=='toolkit'),'food queue mode differs')
   evidence={emptyStart=true,anchorRunning=false,anchorProgress=false,anchorDuration=460,contractsVerified=false,
    reordered=false,waitingCancel=false,moveRejected=false,cancelRejected=false,manualPickup=false,
    untouchedBefore=false,nativeDurationsUnchanged=false,order={}}
   if spec.depletion then evidence.denialReason='not-requested'end
   anchor=ISDrinkFluidAction:new(player,items().anchor,.5);assert(anchor.maxTime==460,'anchor duration differs')
   ISTimedActionQueue.add(anchor);phase='running';since=getTimestampMs();return
  elseif phase=='running'then
   local current=queue().queue[1]
   if Progress.running(current,anchor) then
    evidence.anchorProgress=true;if not evidence.anchorRunning then dispatch()end
   end
   for index,value in ipairs(observed)do
    if Progress.running(current,value.pickup) then commands[index].pickupObserved=true end
    if Progress.running(current,value.eat) and not commands[index].progress then
     local fresh=items();assert(fresh.food:getContainer()==player:getInventory(),'food started outside root')
     commands[index].progress=true;evidence.order[#evidence.order+1]=index
    end
   end
   if idle>=10 then assert(evidence.anchorRunning,'anchor ended before dispatch');phase='receipt';request('Verify')end
  elseif phase=='receipt'and receipt then
   -- Host inventory/stat replication may trail the command receipt; resolve fresh IDs until aligned.
   local current=clientReady();if current then finish(current)end
  end
 end)
 if not ok then print('[QUEUE_TEST] FAIL food client '..tostring(problem));done=true end
end)
