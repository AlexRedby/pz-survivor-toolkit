require 'Entity/ISEntityUI'
local config=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local started,done=false,false
local step,phase,since=1,'prepare',0
local ids,shifted,receipt,window,logic,owner,action,forge
local peak,atFull,requested=0,nil,false
local clientIndex,openLogged
local function case()return config.cases[step]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function emit(value)
 value.suite='forge';value.kind='mp';value.mode=config.mode;value.actor='client1';JSON.emit(value)
end
local function request(command)sendClientCommand('ForgeTest',command,{case=case()})end
Events.OnServerCommand.Add(function(module,command,value)
 if module~='ForgeTest'then return end
 if command=='Failed'then print('[QUEUE_TEST] FAIL forge authority '..tostring(value.error));done=true
 elseif command=='Prepared'then ids=value elseif command=='Shifted'then shifted=value elseif command=='Verified'then receipt=value end
end)
local function finish()
 local q=queue();local drained=#q.queue==0 and not getPlayer():hasTimedActions()
 local ownerIdle=not logic:isCraftActionInProgress()
 local passed=receipt.exactEffects and drained and ownerIdle
 local reason
 if not passed then reason=not drained and 'action-stalled'or 'authoritative-recipe-effects-differ'end
 emit({event='case',id=case(),status=passed and 'passed'or 'failed',
  reason=reason,
  authorityVerified=true,authority=receipt,peak=peak,queueDrained=drained,ownerIdle=ownerIdle,
  recipe=case()=='handcraft'and 'Base.SawLogs'or 'Base.Forge_Crude_Blade',
  nativeDuration=action and action:getDuration()or 0})
 if not drained then ISTimedActionQueue.clear(getPlayer())end -- fixture cleanup only, after recording the failure
 if window then
  if window.close then window:close()else window:setVisible(false);window:removeFromUIManager()end
 end
 if step==#config.cases then
  emit({event='complete',cases=config.cases,performed=step});print('[FORGE_TEST] COMPLETE');done=true;return
 end
 step=step+1;phase='prepare';since=getTimestampMs()
 ids,shifted,receipt,window,logic,owner,action,forge=nil,nil,nil,nil,nil,nil,nil,nil
 peak,atFull,requested=0,nil,false
 clientIndex,openLogged=nil,nil
end
local function open(player)
 local recipe=assert(getScriptManager():getCraftRecipe(case()=='handcraft'and 'SawLogs'or 'Forge_Crude_Blade'))
 if forge then
  if not openLogged then
   print('[FORGE_TEST] WORKSTATION sprite='..tostring(forge:getSprite():getName())..' serverIndex='..ids.index
    ..' clientIndex='..forge:getObjectIndex()..' style='..tostring(ISEntityUI.GetWindowStyleName(forge))
    ..' canOpen='..tostring(ISEntityUI.CanOpenWindowFor(player,forge)))
   openLogged=true
  end
  ISEntityUI.OpenWindow(player,forge)
  local playerUI=ISEntityUI.players[player:getPlayerNum()]
  for _,entry in pairs(playerUI and playerUI.windows or {})do
   if entry.instance and entry.entityObj==forge then window=entry.instance end
  end
  if not window then return false end
 else
  ISEntityUI.OpenHandcraftWindow(player,nil,'InHandCraft',true,recipe)
  window=assert(ISEntityUI.GetWindowInstance(player:getPlayerNum(),'HandcraftWindow'))
 end
 local panel=assert(window.HandCraftPanel or window.handCraftPanel)
 logic=assert(panel.logic);owner=panel.craftActionPanel or panel.recipePanel.craftControl
 logic:setContainers(ISInventoryPaneContextMenu.getContainers(player));logic:setRecipe(recipe)
 logic:setManualSelectInputs(false)
 if forge then assert(logic:getCraftBench()==forge:getComponent(ComponentType.CraftBench),'UI lost native forge component')end
 print('[FORGE_TEST] UI_OPEN case='..case()..' recipe='..recipe:getName()..' bench='..tostring(logic:getCraftBench()))
 return true
end
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs();getCore():setOptionPauseOnFocusloss(false)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
 emit({event='setup',cases=config.cases,nativeDurations=true,queueEnabled=PZSurvivorToolkit.Settings.actionQueue()})
end)
Events.OnTick.Add(function()
 if not started or done or not isIngameState()then return end
 local ok,problem=pcall(function()
  local player=getPlayer();if not player or player:isDead()or not player:getSquare()then return end
  assert(getTimestampMs()-since<210000,'forge phase deadline '..phase)
  if phase=='prepare'then request('Prepare');phase='ready';return end
  if phase=='ready'then
   if not ids then return end
   for _,id in ipairs(ids.materials)do if not player:getInventory():getItemById(id)then return end end
   for _,id in ipairs(ids.tools)do if not player:getInventory():getItemById(id)then return end end
   if case()~='handcraft'then
    local square=getCell():getGridSquare(ids.x,ids.y,ids.z);if not square then return end
    for i=0,square:getObjects():size()-1 do local value=square:getObjects():get(i)
     if value:getModData().ForgeTestCase==case()then forge=value end
    end
    if not forge or not forge:getComponent(ComponentType.CraftBench)then return end
    if case()=='forge-shift'then clientIndex=forge:getObjectIndex();request('Shift');phase='shift';return end
   end
   if open(player)then phase='ui'end;return
  end
  if phase=='shift'then
   if not shifted or forge:getObjectIndex()~=clientIndex-1 then return end
   print('[FORGE_TEST] SHIFT_OBSERVED before='..ids.index..' after='..forge:getObjectIndex())
   if open(player)then phase='ui'end;return
  end
  if phase=='ui'then
   logic:canPerformCurrentRecipe()
   if not logic:canPerformCurrentRecipe()then return end
   local button=owner.craftButton or owner.buttonCraft
   if not button.enable then return end
   if owner.quantityInput then owner.quantityInput:setText('1')else owner:setCraftQuantity(1)end
   button:forceClick();phase='running';since=getTimestampMs();return
  end
  if phase=='running'then
   for _,value in ipairs(queue().queue)do
    if value.Type=='ISHandcraftAction'and value.craftRecipe==logic:getRecipe()then action=value end
   end
   if action and action:isStarted()then
    peak=math.max(peak,action:getJobDelta())
    if peak>=0.999 and not atFull then atFull=getTimestampMs();print('[FORGE_TEST] REACHED_100 case='..case())end
   end
   local idle=#queue().queue==0 and not player:hasTimedActions()
   if (action and idle)or (atFull and getTimestampMs()-atFull>15000)or getTimestampMs()-since>150000 then
    request('Verify');phase='receipt';return
   end
  end
  if phase=='receipt'and receipt then finish()end
 end)
 if not ok then print('[QUEUE_TEST] FAIL forge client '..tostring(problem));done=true end
end)
