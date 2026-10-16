require 'PZSurvivorToolkit/CraftChains'
-- Intake fixture: disposable two-client MP caches only.
local reader=assert(getFileReader('craft-fixture.txt',false),'Missing craft fixture configuration')
local config={}
for _,key in ipairs({'user','scenario','host','port','password'}) do config[key]=assert(reader:readLine(),'Missing '..key) end
reader:close()
local user,scenario=config.user,config.scenario
assert(user=='client1' or user=='client2','Expected a fixed fixture client')
assert(scenario=='crafting' or scenario=='ui' or scenario=='alternatives','Unknown craft scenario')
local connecting,advanced,started,lastReady=false,false,nil,0
local ids,fixtureSurface,fixtureCrate,craftPanel,planWindow
local replies,stages,step,previous,lastDiagnostic={}, {},1,0,0
local function send(command,args) sendClientCommand('CraftChainTest',command,args or {}) end
local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()) end
local function empty() return #queue().queue==0 and not getPlayer():hasTimedActions() end
local function stage(name,fn,ready,delay) stages[#stages+1]={name,fn,ready,delay} end
local function observeRender(window)
 window.fixtureOriginalPrerender=window.fixtureOriginalPrerender or window.prerender
 local original=window.fixtureOriginalPrerender
 window.fixtureRenderFrames,window.fixtureOpenedAt=0,getTimestampMs()
 window.prerender=function(self,...)
  self.fixtureRenderFrames=self.fixtureRenderFrames+1
  return original(self,...)
 end
end
local function rendered(window)
 return window and window.fixtureRenderFrames>=2 and getTimestampMs()-window.fixtureOpenedAt>=800
end
local function findObject(data,owner)
 if not data then return end
 local square=getCell():getGridSquare(data.x,data.y,0)
 if not square then return end
 local objects=square:getObjects()
 for i=0,objects:size()-1 do local object=objects:get(i)
  if object:getModData().CraftChainTestOwner==owner then return object,object:getContainer() end
 end
end
local function refreshInventories()
 local player=getPlayer();local num=player:getPlayerNum()
 getPlayerInventory(num):refreshBackpacks();getPlayerLoot(num):refreshBackpacks()
end
local function fixtureReady()
 fixtureSurface,fixtureCrate=findObject(ids,user)
 if not fixtureSurface or not fixtureCrate:getItemById(ids.log) then return false end
 local p=getPlayer();local inv=p:getInventory()
 return fixtureCrate:getItemById(ids.saw) and inv:getItemById(ids.knife)
  and inv:getItemById(ids.cancelCurrent) and inv:getItemById(ids.cancelTail) and p:getPerkLevel(Perks.Carving)>=1
end
local function rows(view,kind)
 local result={}
 for _,row in ipairs(view.preview.items) do if row.item.kind==kind then result[#result+1]=row.item end end
 return result
end
local function openNative(recipe,object)
 ISEntityUI.OpenHandcraftWindow(getPlayer(),object,nil,true,recipe)
 local window=assert(ISEntityUI.GetWindowInstance(getPlayer():getPlayerNum(),'HandcraftWindow'),'native handcraft window missing')
 local panel=assert(window.HandCraftPanel or window.handCraftPanel,'native/NC panel missing')
 panel.logic:setIsoObject(object);panel.logic:setRecipe(recipe);refreshInventories()
 panel.logic:setContainers(ISInventoryPaneContextMenu.getContainers(getPlayer()))
 return panel
end
Events.OnConnected.Add(function() connecting=true end)
Events.OnMainMenuEnter.Add(function()
 if connecting or isClient() then return end;connecting=true
 ConnectToServer.instance:connect(MainScreen.instance,'Native crafting chains isolated test',user,config.password,config.host,'',config.port,'',false,true,1)
end)
Events.OnPreUIDraw.Add(function()
 if (not connecting and not isClient()) or advanced or isIngameState() then return end
 if not MainScreen.instance or not MainScreen.instance.charCreationProfession or not MapSpawnSelect.instance then return end
 if MainScreen.instance.charCreationProfession:getIsVisible() or MapSpawnSelect.instance:getIsVisible() then
  advanced=true;MapSpawnSelect.instance:useDefaultSpawnRegion();MapSpawnSelect.instance:setVisible(false)
  MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
  MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
 end
end)
Events.OnConnectFailed.Add(function(a,b) print('[CRAFT_TEST] FAIL connect '..tostring(a)..' '..tostring(b)) end)
Events.OnGameStart.Add(function()
 started=getTimestampMs();getCore():setOptionAutoDrink(false);getPlayer():setAutoDrink(false)
 if user=='client2' then local p=getPlayer();p:teleportTo(math.floor(p:getX())+8,math.floor(p:getY())+8,0) end
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
 print('[CRAFT_TEST] CONNECTED '..user..' language='..tostring(getCore():getOptionLanguageName()))
end)
local Planner=PZSurvivorToolkit.CraftPlanner
local Recipes=PZSurvivorToolkit.CraftChainRecipes
local function itemById(name)
 return getPlayer():getInventory():getItemById(ids[name]) or fixtureCrate:getItemById(ids[name])
end
local function allReady()
 if not fixtureReady() then return false end
 for _,name in ipairs({'log2','branch1','branch2','stick','longstick','sapling','handle','firewood','cleaver','unusable'}) do
  if not itemById(name) then return false end
 end
 return true
end
local function selectRecipe(name,auto)
 if planWindow and not planWindow.closed then planWindow:close() end
 craftPanel=openNative(assert(getScriptManager():getCraftRecipe(name)),fixtureSurface)
 if auto then craftPanel.logic:setManualSelectInputs(false) end
 return craftPanel.logic:getRecipe()
end
local function inputAccepting(recipe,fullType)
 local inputs=recipe:getInputs()
 for i=0,inputs:size()-1 do
  local input=inputs:get(i);local types=input:getPossibleInputItems()
  for j=0,types:size()-1 do if types:get(j):getFullName()==fullType then return input,recipe:getIndexForIO(input) end end
 end
 error('No input accepting '..fullType)
end
local function snapshot()
 local model,target,context=Recipes.collect(craftPanel)
 assert(model,'Collect failed: '..tostring(target));return model,target,context
end
local function makePlan(count)
 local model,target,context=snapshot()
 local plan,why,missing=Planner.plan(model,target,count or 1)
 print('[CRAFT_TEST] PLAN '..user..' recipe='..target..' count='..tostring(count or 1)..' ok='..tostring(plan~=nil)..' reason='..tostring(why)..' missing='..tostring(missing))
 if plan then
  for i,step in ipairs(plan.steps) do
   local choices={}
   for _,slot in ipairs(step.recipe.inputs) do
    local choice=step.inputs[slot.index]
    choices[#choices+1]=(slot.keep and 'keep:' or 'consume:')..choice.fullType..'x'..choice.amount
   end
   print('[CRAFT_TEST] STEP '..user..' '..i..' '..step.recipe.id..' '..table.concat(choices,','))
  end
 end
 return plan,why,missing,model,target,context
end
local function manualPick(recipe,fullType,key)
 local input,index=inputAccepting(recipe,fullType)
 craftPanel.logic:setManualSelectInputs(true)
 craftPanel.logic:setManualSelectInputScriptFilter(input)
 craftPanel.logic:setShowManualSelectInputs(true)
 local picker=assert(craftPanel.InputSwitchPanel,'native picker missing')
 local chosen=assert(itemById(key))
 for group,info in ipairs(picker.InputscriptItems) do
  for _,candidate in ipairs(info.AvailableItems or {}) do
   if candidate==chosen then
    assert(picker:onItemGroupDoubleClick(group,chosen),'native picker rejected selection')
    local selected=craftPanel.logic:getManualInputsFor(input,ArrayList.new())
    assert(selected:size()==1 and selected:get(0)==chosen,'picker did not pin exact item')
    return index,picker
   end
  end
 end
 error('Native picker has no selected candidate '..fullType)
end
local function view()
 planWindow=assert(PZSurvivorToolkit.CraftChains.open(craftPanel));observeRender(planWindow)
 assert(planWindow.plan,'preview failed');return planWindow
end
local function inputRow(recipeId,fullType)
 for _,row in ipairs(rows(planWindow,'input')) do
  if row.recipeId==recipeId and row.fullType==fullType then return row end
 end
 error('No ingredient row '..recipeId..' '..fullType)
end
local function choose(row,fullType)
 planWindow:openChoices(row)
 local menu=assert(planWindow.choiceMenu,'material menu missing')
 for _,option in ipairs(menu.options) do
  if option.param1 and option.param1.fullType==fullType then
   option.onSelect(option.target,option.param1)
   return
  end
 end
 error('No material option '..tostring(fullType))
end
local function start()
 planWindow:startPlan()
 assert(planWindow.closed and #queue().queue>0,'native crafting was not enqueued')
end
stage('server supplied alternative real materials and tools',function()
 assert(itemById('branch1'):getFullType()=='Base.TreeBranch2')
 assert(itemById('cleaver'):getSharpness()>0)
end,allReady)
stage('NC auto-filled manual inputs no longer become explicit constraints',function()
 local recipe=selectRecipe('Carve4SmallHandles')
 assert(craftPanel.logic:isManualSelectInputs(),'NC no longer defaults to manual')
 local input,index=inputAccepting(recipe,'Base.TreeBranch2')
 local selected=craftPanel.logic:getManualInputsFor(input,ArrayList.new())
 assert(selected:size()==1,'expected one automatically populated raw input')
 local model,target=snapshot()
 for _,slot in ipairs(model.recipes[target].inputs) do
  assert(not slot.preference and not slot.selectedIds and not slot.preferredIds,'auto-fill became a constraint')
 end
 local plan=assert(makePlan(2))
 assert(#plan.steps==2 and plan.consumed['Base.TreeBranch2']==2,'spare branches were blocked')
 view();planWindow.quantity:setText('2');planWindow:refresh();observeRender(planWindow)
end)
stage('automatic quantities and material icons render in native NC',function()
 assert(#rows(planWindow,'input')==4)
 getCore():TakeFullScreenshot('alternatives-automatic-'..user..'.png')
end,function() return rendered(planWindow) end,800)
stage('native picker imports deliberate type and prefers selected instance across repeats',function()
 planWindow:close()
 local recipe=craftPanel.logic:getRecipe()
 local index=manualPick(recipe,'Base.TreeBranch2','branch2')
 local plan=assert(makePlan(2));assert(plan.consumed['Base.TreeBranch2']==2)
 assert(plan.steps[1].inputs[index].resourceIds[1]==ids.branch2,'explicit branch was not preferred first')
 assert(plan.steps[2].inputs[index].resourceIds[1]==ids.branch1,'remaining branch was not usable for repetition')
end)
stage('native picker imports another final material and exact reusable tool',function()
 local recipe=craftPanel.logic:getRecipe()
 manualPick(recipe,'Base.WoodenStick2','stick')
 local index=manualPick(recipe,'Base.MeatCleaver','cleaver')
 local plan=assert(makePlan(1))
 assert(plan.consumed['Base.WoodenStick2']==1 and not plan.consumed['Base.TreeBranch2'])
 assert(plan.steps[1].inputs[index].resourceIds[1]==ids.cleaver)
 view()
end)
stage('native choice appears as selected ingredient row with stock allocation',function()
 local row=inputRow('Carve4SmallHandles','Base.WoodenStick2')
 assert(row.mode==getText('UI_PZST_CraftChainSelected'))
 planWindow:openChoices(row)
 planWindow.choiceMenu:setX(planWindow:getAbsoluteX()+10)
 planWindow.choiceMenu:setY(planWindow:getAbsoluteY()+80)
end,function() return rendered(planWindow) end,800)
stage('material popup renders before screenshot',function()
 getCore():TakeFullScreenshot('alternatives-material-menu-'..user..'.png')
end,nil,800)
stage('inline Auto overrides imported material and recalculates the whole plan',function()
 choose(inputRow('Carve4SmallHandles','Base.WoodenStick2'),false)
 assert(planWindow.plan.consumed['Base.TreeBranch2']==1)
 choose(inputRow('Carve4SmallHandles','Base.TreeBranch2'),'Base.TableLeg_Broken')
 assert(not planWindow.plan and #rows(planWindow,'input')>0,'impossible material cannot be corrected')
 choose(inputRow('Carve4SmallHandles','Base.TableLeg_Broken'),false)
 assert(planWindow.plan and planWindow.plan.consumed['Base.TreeBranch2']==1,'Auto failed to recover')
end)
stage('native manual off on without preview clears old picker intent',function()
 planWindow:close()
 craftPanel.logic:setManualSelectInputs(false)
 craftPanel.logic:setManualSelectInputs(true)
 local model,target=snapshot()
 for _,slot in ipairs(model.recipes[target].inputs) do assert(not slot.preference,'old native intent survived mode toggle') end
end)
stage('second recipe respects native sapling choice',function()
 local recipe=selectRecipe('Carve8SmallHandles')
 local plan=assert(makePlan(1));assert(plan.consumed['Base.LongStick']==1)
 manualPick(recipe,'Base.Sapling','sapling')
 plan=assert(makePlan(1));assert(plan.consumed['Base.Sapling']==1 and not plan.consumed['Base.LongStick'])
end)
stage('untouched SawLogs plans two native runs with spare log',function()
 selectRecipe('SawLogs')
 assert(craftPanel.logic:isManualSelectInputs())
 local plan=assert(makePlan(2));assert(#plan.steps==2 and plan.consumed['Base.Log']==2)
end)
stage('partially stocked spoon input allows making a missing handle under default NC settings',function()
 selectRecipe('CarveWoodenSpoon')
 local plan=assert(makePlan(2))
 assert(#plan.steps==3 and plan.steps[1].recipe.id=='CarveWoodenSpoon')
 assert(plan.steps[2].recipe.id=='Carve2SmallHandles' and plan.steps[3].recipe.id=='CarveWoodenSpoon')
 assert(plan.consumed['Base.SmallHandle']==1 and plan.consumed['Base.Firewood']==1)
 view();planWindow.quantity:setText('2');planWindow:refresh()
end)
stage('intermediate ingredient can choose a different real source and tool',function()
 choose(inputRow('Carve2SmallHandles','Base.Firewood'),'Base.UnusableWood')
 choose(inputRow('Carve2SmallHandles','Base.HuntingKnife'),'Base.MeatCleaver')
 assert(planWindow.plan.consumed['Base.UnusableWood']==1 and not planWindow.plan.consumed['Base.Firewood'])
 local middle=planWindow.plan.steps[2]
 local source=inputRow('Carve2SmallHandles','Base.UnusableWood')
 assert(source.detail==getText('UI_PZST_CraftChainAllocation',1,1,0),'stock allocation differs')
 local generated=rows(planWindow,'input')[6]
 assert(generated.fullType=='Base.SmallHandle' and generated.detail==getText('UI_PZST_CraftChainAllocation',1,0,1),'generated handle allocation differs')
 for _,input in ipairs(middle.recipe.inputs) do
  if input.keep then assert(middle.inputs[input.index].resourceIds[1]==ids.cleaver) end
 end
 -- Scroll intermediate rows into the real native viewport.
 planWindow.preview:setYScroll(-350);observeRender(planWindow)
end)
stage('intermediate choices and counts render EN RU',function()
 getCore():TakeFullScreenshot('alternatives-prerequisite-'..user..'.png')
end,function() return rendered(planWindow) end,800)
stage('UI starts actual selected-material prerequisite crafting',start,empty)
stage('native chain finishes and requests server conservation checks',function()
 send('VerifyAlternatives',{phase='chain'})
end,empty)
stage('server confirms selected intermediate source consumption and exact outputs',function()
 assert(replies.AlternativesVerified.ok,replies.AlternativesVerified.error)
 assert(replies.AlternativesVerified.phase=='chain')
 replies.AlternativesVerified=nil
end,function() return replies.AlternativesVerified~=nil end)
stage('explicit branch material repeats execute under default native selection',function()
 local recipe=selectRecipe('Carve4SmallHandles')
 manualPick(recipe,'Base.TreeBranch2','branch2')
 view();planWindow.quantity:setText('2');planWindow:refresh()
 assert(planWindow.plan.consumed['Base.TreeBranch2']==2)
 start()
end,empty)
stage('native repeated crafts finish and request authoritative totals',function()
 send('VerifyAlternatives',{phase='repeat'})
end,empty)
stage('server confirms both selected branches consumed with no tool loss',function()
 assert(replies.AlternativesVerified.ok,replies.AlternativesVerified.error)
 assert(replies.AlternativesVerified.phase=='repeat')
 replies.AlternativesVerified=nil
end,function() return replies.AlternativesVerified~=nil end)
stage('two native log crafts enqueue with auto-filled NC inputs',function()
 selectRecipe('SawLogs');view();planWindow.quantity:setText('2');planWindow:refresh()
 assert(planWindow.plan.consumed['Base.Log']==2);start()
end,empty)
stage('native saw crafts finish and request server stock verification',function()
 send('VerifyAlternatives',{phase='logs'})
end,empty)
stage('server verifies two logs six planks and retained shelf saw',function()
 assert(replies.AlternativesVerified.ok,replies.AlternativesVerified.error)
 assert(replies.AlternativesVerified.phase=='logs')
 print('[CRAFT_TEST] ALTERNATIVES_COMPLETE '..user)
end,function() return replies.AlternativesVerified~=nil end)

CraftIntakeFixture={stageCount=#stages}
print('[CRAFT_TEST] EXPECTED checks='..#stages..' scenario='..scenario)
Events.OnServerCommand.Add(function(module,command,args)
 if module~='CraftChainTest' then return end
 if command=='Setup' then
  if not ids then ids=args;previous=getTimestampMs() end
 else replies[command]=args end
end)
Events.OnTick.Add(function()
 local now=getTimestampMs()
 if not ids then
  if started and now-started>2000 and now-lastReady>1000 then lastReady=now;send('Ready') end
  return
 end
 local spec=stages[step];if not spec or now-previous<(spec[4] or 0) then return end
 if spec[3] then
  local ok,ready=pcall(spec[3])
  if ok and not ready and now-previous<240000 then
   if now-previous>5000 and now-lastDiagnostic>10000 then
    lastDiagnostic=now
    local actions={};for i,action in ipairs(queue().queue) do actions[#actions+1]=i..':'..tostring(action.Type)..':'..tostring(action.craftRecipe and action.craftRecipe:getName()) end
    print('[CRAFT_TEST] WAIT stage='..step..' '..spec[1]..' queue='..table.concat(actions,','))
   end
   return
  end
  if not ok or not ready then
   print('[CRAFT_TEST] FAIL deadline '..spec[1]..' '..tostring(ready))
   print('[CRAFT_TEST] COMPLETE checks='..(step-1)..' failures=1');step=#stages+1;return
  end
 end
 local ok,error=pcall(spec[2]);print('[CRAFT_TEST] '..(ok and 'PASS ' or 'FAIL ')..spec[1]..' '..tostring(error))
 if not ok then print('[CRAFT_TEST] COMPLETE checks='..(step-1)..' failures=1');step=#stages+1;return end
 step=step+1;previous=getTimestampMs()
 if step>#stages then print('[CRAFT_TEST] COMPLETE checks='..#stages..' failures=0') end
end)
