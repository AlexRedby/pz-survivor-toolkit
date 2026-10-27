require 'Entity/ISEntityUI'
local config=require 'QueueTestSelection'
if config.suite~='plastic-battery' then return end
local JSON=require 'QueueHealthEvents'
local gunType='damnCraft.PlasticWeldingGun'
local plans={}
for _,provider in ipairs({'base','damn'})do
 for _,operation in ipairs({'insert','remove'})do
  for _,charge in ipairs({0,0.37,1})do
   plans[#plans+1]={provider=provider,operation=operation,requestedCharge=charge}
  end
 end
end
local started,done,index,phase=false,false,1,'prepare'
local inventory,original,stash={}, {}, {}
local row,gun,battery,recipe,action,since,settleAt,seen
local nativePerform=ISHandcraftAction.performRecipe
local function observePerform(value,...)
 if value==action then row.performCalls=(row.performCalls or 0)+1 end
 return nativePerform(value,...)
end
local function emit(event,data)print('[PLASTIC_BATTERY] '..event..' '..JSON.encode(data))end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function relevant(item)return item:getFullType()==gunType or item:getFullType()=='Base.Battery'end
local function snapshot()
 local rows={}
 for i=0,inventory:getItems():size()-1 do
  local item=inventory:getItems():get(i)
  if relevant(item)then rows[#rows+1]={id=item:getID(),type=item:getFullType(),
   uses=item:getCurrentUses(),maxUses=item:getMaxUses(),charge=item:getCurrentUsesFloat(),condition=item:getCondition()}end
 end
 table.sort(rows,function(a,b)return a.id<b.id end)
 return rows
end
local function cleanup()
 for i=inventory:getItems():size()-1,0,-1 do
  local item=inventory:getItems():get(i)
  if relevant(item)and not original[item:getID()]then getPlayer():removeFromHands(item);inventory:Remove(item)end
 end
end
local function finishPhase()
 row.after=snapshot();row.queueDrained=#queue().queue==0 and not getPlayer():hasTimedActions()
 row.actionObserved=seen==true
 row.nativeDuration=action~=nil and action:getDuration()==recipe:getTime(getPlayer())*5 and action:getDuration()>1
 row.elapsedMs=getTimestampMs()-since
 emit('PHASE',row)
 cleanup();index=index+1;phase='prepare';action=nil;seen=false
 if index>#plans then
  for _,item in ipairs(stash)do inventory:AddItem(item)end
  for id in pairs(original)do assert(inventory:getItemById(id),'original inventory item lost')end
  assert(ISHandcraftAction.performRecipe==observePerform,'craft observer replaced')
  ISHandcraftAction.performRecipe=nativePerform
  done=true;emit('COMPLETE',{phases=#plans,restored=true})
 end
end
local function menuRecipes(item)
 local context=assert(ISInventoryPaneContextMenu.createMenu(0,true,{item},150,150,getPlayerInventory(0).inventoryPane))
 local found={}
 local function scan(menu)
  for _,option in ipairs(menu.options or {})do
   if option.onSelect==ISInventoryPaneContextMenu.OnNewCraft and option.param1 then
    found[#found+1]={recipe=option.param1:getScriptObjectFullType(),enabled=not option.notAvailable}
   end
   if option.subOption then local child=menu:getSubMenu(option.subOption);if child then scan(child)end end
  end
 end
 scan(context);context:hideAndChildren();return found
end
Events.OnGameStart.Add(function()
 started=true;inventory=getPlayer():getInventory()
 getPlayer():setGodMod(true);getPlayer():setGhostMode(true)
 assert(not getPlayer():isTimedActionInstant(),'native duration requires ordinary timed actions')
 ISHandcraftAction.performRecipe=observePerform
 for i=inventory:getItems():size()-1,0,-1 do
  local item=inventory:getItems():get(i);original[item:getID()]=true
  if relevant(item)then stash[#stash+1]=item;getPlayer():removeFromHands(item);inventory:Remove(item)end
 end
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
 emit('SETUP',{phases=#plans,native=true,physicalInput=false,network=false,
  entrypoint='ISInventoryPaneContextMenu.OnNewCraft',
  damnInsert=type(DAMN and DAMN.OnCreate and DAMN.OnCreate.PlasticWeldingGunBatteryInsert),
  damnRemove=type(DAMN and DAMN.OnCreate and DAMN.OnCreate.PlasticWeldingGunBatteryRemoval)})
end)
Events.OnTick.Add(function()
 if not started or done or not getPlayer()or not getPlayer():getSquare()then return end
 local ok,problem=pcall(function()
  if phase=='prepare'then
   assert(#queue().queue==0 and not getPlayer():hasTimedActions(),'queue not idle at phase start')
   row={index=index,performCalls=0};for key,value in pairs(plans[index])do row[key]=value end
   assert(getPlayer():getInventoryWeight()+3<getPlayer():getMaxWeight(),'insufficient carry headroom for native output')
   local name=row.operation=='insert'and 'InsertBattery'or 'RemoveBattery'
   if row.provider=='damn'then name='damnCraft'..name..(row.operation=='insert'and 'Into'or 'From')..'PlasticWeldingGun'end
   recipe=assert(getScriptManager():getCraftRecipe(name),'recipe absent '..name)
   row.recipe=recipe:getScriptObjectFullType();row.obsolete=recipe:getObsolete();row.learnRequired=recipe:needToBeLearn()
   -- Float setters can round above getMaxUses (Battery: 143 versus 142).
   -- Seed bounded native use counts instead of manufacturing an overfull item.
   gun=assert(inventory:AddItem(gunType))
   gun:setCurrentUses(row.operation=='insert'and 0 or math.floor(gun:getMaxUses()*row.requestedCharge+0.5))
   battery=nil
   if row.operation=='insert'then
    battery=assert(inventory:AddItem('Base.Battery'))
    battery:setCurrentUses(math.floor(battery:getMaxUses()*row.requestedCharge+0.5))
   end
   row.gunID=gun:getID();row.batteryID=battery and battery:getID()or -1
   row.before=snapshot();getPlayerInventory(0).inventoryPane:refreshContainer()
   since=getTimestampMs();settleAt=since+500;phase='ready'
  elseif phase=='ready'then
   if getTimestampMs()<settleAt then return end
   local logic=HandcraftLogic.new(getPlayer(),nil,nil)
   logic:setIsoObject(logic:findCraftSurface(getPlayer(),2))
   logic:setContainers(ISInventoryPaneContextMenu.getContainers(getPlayer()))
   logic:setRecipeFromContextClick(recipe,gun)
   row.available=logic:canPerformCurrentRecipe();row.menu=menuRecipes(gun);row.ready=snapshot()
   emit('ADMITTED',{index=index,recipe=row.recipe,available=row.available,menu=row.menu})
   if not row.available then finishPhase();return end
   ISInventoryPaneContextMenu.OnNewCraft(gun,recipe,0,false)
   for _,value in ipairs(queue().queue)do
    if value.Type=='ISHandcraftAction'and value.craftRecipe==recipe then assert(not action,'duplicate craft');action=value end
   end
   assert(action,'native callback did not queue craft')
   phase='running';since=getTimestampMs()
  elseif phase=='running'then
   if action:isStarted()and not seen then
    local inputs=assert(action.logic):getRecipeData():getAllInputItems()
    row.inputIDs={};local found={}
    for i=0,inputs:size()-1 do
     local id=inputs:get(i):getID();row.inputIDs[#row.inputIDs+1]=id;found[id]=true
     assert(id==row.gunID or id==row.batteryID,'native craft selected a non-fixture input')
    end
    assert(found[row.gunID] and (row.operation=='remove'or found[row.batteryID]),'native craft did not select exact fixture inputs')
    seen=true
   end
   assert(getTimestampMs()-since<45000,'native battery action did not finish')
   if #queue().queue==0 and not getPlayer():hasTimedActions()then finishPhase()end
  end
 end)
 if not ok then
  if ISHandcraftAction.performRecipe==observePerform then ISHandcraftAction.performRecipe=nativePerform end
  done=true;emit('FAIL',{index=index,phase=phase,error=tostring(problem)})
 end
end)
