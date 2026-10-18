require 'PZSurvivorToolkit/ActionQueuePanel'
require 'TimedActions/ISDrinkFluidAction'
require 'TimedActions/ISReadABook'
require 'TimedActions/ISWearClothing'
require 'TimedActions/ISUnequipAction'
local Fixture=require 'QueueFluidFixture'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local started,done=false,false
local step,failed,phase,since,idle=1,0,'prepare',0,0
local ids,state,authorityState,receipt,drink,pickup,tail
local previousAuthority,previousBag
local pickupObserved,drinkProgress,tailProgress=false,false,false
local nativeDuration
local function case()return config.cases[step]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function emit(row)
 row.suite,row.kind,row.mode,row.actor='fluid',config.kind,config.mode,'client1';JSON.emit(row)
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
 if module~='FluidTest'then return end
 assert(command~='Failed',value.error)
 if command=='Prepared'then ids=value elseif command=='Verified'then receipt=value end
end)
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs()
 getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false)
 getPlayer():setAutoDrink(false);getPlayer():setGhostMode(true)
end)
local function enqueue(player)
 local add=ISTimedActionQueue.add
 ISTimedActionQueue.add=function(action)
  if action.Type=='ISInventoryTransferAction'and action.item:getID()==ids.bottleId
   and action.destContainer==player:getInventory()then assert(not pickup,'duplicate bottle pickup');pickup=action end
  if action.Type=='ISDrinkFluidAction'then
   assert(not drink,'duplicate drink');drink=action;nativeDuration=action.maxTime
  end
  return add(action)
 end
 local ok,problem=pcall(function()
  local menu=ISContextMenu.get(player:getPlayerNum(),20,20)
  ISInventoryPaneContextMenu.doDrinkFluidMenu(player,state.bottle,menu)
  for _,option in ipairs(menu.options)do
   if option.subOption then
    local submenu=menu:getSubMenu(option.subOption)
    menu:displaySubMenu(submenu,option)
    for index,portion in ipairs(submenu.options)do
     if portion.onSelect==ISInventoryPaneContextMenu.onDrinkFluid and portion.target==state.bottle and portion.param1==.5 then
      submenu.mouseOver=index;submenu:onJoypadDown(Joypad.AButton)
      return
     end
    end
   end
  end
  error('native half-portion menu missing')
 end)
 ISTimedActionQueue.add=add
 assert(ok,problem);assert(drink and drink.item:getID()==ids.bottleId,'native drink action missing')
 assert((pickup~=nil)==(ids.source=='bag'),'native pickup presence differs')
 state.book:setAlreadyReadPages(state.book:getNumberOfPages()-1)
 player:setAlreadyReadPages(state.book:getFullType(),state.book:getNumberOfPages()-1)
 tail=ISReadABook:new(player,state.book);add(tail)
 print('[FLUID_TEST] DISPATCH '..JSON.encode({case=case(),actionType=drink.Type,nativeDuration=nativeDuration,
  bottleId=drink.item:getID(),pickup=pickup~=nil}))
end
local function finish()
 local expected=ids.amount*.5
 local reason
 if receipt.amount<expected-.01 or receipt.amount>expected+.0001 then reason='portion-consumption-differs'
 elseif receipt.thirst>=ids.thirst-.00001 then reason='thirst-not-reduced'
 elseif not drinkProgress then reason='drink-not-started'
 elseif not receipt.tailRead or not tailProgress then reason='independent-reader-not-completed'
 elseif ids.source=='bag'and not pickupObserved then reason='pickup-not-observed'end
 local row={event='case',id=case(),status=reason and 'failed'or 'passed',reason=reason,
  pickupObserved=pickupObserved,drinkProgress=drinkProgress,tailRead=receipt.tailRead,
  actionType=drink.Type,nativeDuration=nativeDuration,menuDispatched=true,portion=.5}
 for key,value in pairs(receipt)do row[key]=value end
 emit(row);if reason then failed=failed+1 end
 step=step+1
 if not case()then
  emit({event='complete',cases=config.cases,expected=#config.cases,performed=step-1,failed=failed,skipped=0})
  print('[FLUID_TEST] COMPLETE');done=true;return
 end
 previousAuthority=authorityState;previousBag=state.bag
 ids,state,authorityState,receipt,drink,pickup,tail=nil,nil,nil,nil,nil,nil,nil
 pickupObserved,drinkProgress,tailProgress=false,false,false
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
   if step==1 then emit({event='setup',cases=config.cases,expected=#config.cases,queueEnabled=config.mode=='toolkit',nativeDurations=true})end
   phase='prepared';request('Prepare');return
  elseif phase=='prepared'and ids then
   state=Fixture.resolve(player,ids);if not state then return end
   player:getStats():set(CharacterStat.THIRST,ids.thirst)
   if isClient()then syncPlayerStats(player,SyncPlayerStatsPacket.getBitMaskForStat(CharacterStat.THIRST))end
   ISTimedActionQueue.add(ISWearClothing:new(player,state.bag,50))
   phase='equipped';return
  elseif phase=='equipped'then
   if idle<10 then return end
   assert(player:isEquipped(state.bag),'fixture backpack not equipped')
   enqueue(player);phase='running';since=getTimestampMs();return
  elseif phase=='running'then
   local current=queue().queue[1]
   if pickup and current==pickup and pickup:isStarted()and pickup:getJobDelta()>0 then pickupObserved=true end
   if current==drink and drink:isStarted()and drink:getJobDelta()>0 then
    drinkProgress=true
    local bottle=assert(player:getInventory():getItemById(ids.bottleId))
    assert(bottle:getContainer()==player:getInventory(),'drink started outside root')
    assert(bottle:isFavorite()==ids.favorite,'drink bottle lost favorite flag')
   end
   if current==tail and player:isReading()and tail:isStarted()and tail:getJobDelta()>0 then tailProgress=true end
   if idle>=10 then phase='receipt';request('Verify')end
  elseif phase=='receipt'and receipt then finish()end
 end)
 if not ok then print('[QUEUE_TEST] FAIL fluid client '..tostring(problem));done=true end
end)
