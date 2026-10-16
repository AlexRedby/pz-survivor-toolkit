require 'PZSurvivorToolkit/CraftChains'
require 'PZSurvivorToolkit/ActionQueuePanel'
require 'TimedActions/ISReadABook'
-- Intake fixture: disposable two-client MP caches only.
local reader=assert(getFileReader('craft-fixture.txt',false),'Missing craft fixture configuration')
local config={}
for _,key in ipairs({'user','scenario','host','port','password'}) do config[key]=assert(reader:readLine(),'Missing '..key) end
reader:close()
local user,scenario=config.user,config.scenario
assert(user=='client1' or user=='client2','Expected a fixed fixture client')
assert(scenario=='crafting' or scenario=='ui' or scenario=='alternatives','Unknown craft scenario')
local connecting,advanced,started,lastReady=false,false,nil,0
local ids,raceIds,fixtureSurface,fixtureCrate,raceSurface,raceCrate,craftPanel,planWindow,racePlan,raceContext
local currentRead,tailRead,waitingPlan,classic
local uiStages,classicUIStages={},{}
local ncChildren,disabledView,removedView
local replies,stages,step,previous,lastDiagnostic={}, {},1,0,0
local function send(command,args) sendClientCommand('CraftChainTest',command,args or {}) end
local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()) end
local function empty() return #queue().queue==0 and not getPlayer():hasTimedActions() end
local function stage(name,fn,ready,delay) stages[#stages+1]={name,fn,ready,delay} end
local function uiStage(name,fn,ready,delay) uiStages[#uiStages+1]={name,fn,ready,delay} end
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
local function separateButtons(panel)
 local plan,wishlist=assert(panel.pzstPlanButton,'plan button missing'),assert(panel.pzswButton,'Wishlist button missing')
 assert(plan:getIsVisible() and wishlist:getIsVisible(),'craft buttons hidden')
 local px,py,wx,wy=plan:getAbsoluteX(),plan:getAbsoluteY(),wishlist:getAbsoluteX(),wishlist:getAbsoluteY()
 assert(px+plan.width<=wx or wx+wishlist.width<=px or py+plan.height<=wy or wy+wishlist.height<=py,'plan and Wishlist buttons overlap')
 assert(plan.width>0 and wishlist.width>0 and plan.height>0 and wishlist.height>0,'craft button size empty')
 print('[CRAFT_TEST] BUTTON_LAYOUT '..user..' type='..tostring(panel.Type)..' plan='..px..','..py..','..plan.width..','..plan.height..' wishlist='..wx..','..wy..','..wishlist.width..','..wishlist.height)
end
local function containsContainer(containers,needed)
 for i=0,containers:size()-1 do if containers:get(i)==needed then return true end end
 return false
end
local function childCount(panel)
 local count=0;for _,child in pairs(panel.children or {}) do count=count+1 end;return count
end
local function hasChild(panel,needed)
 for _,child in pairs(panel.children or {}) do if child==needed then return true end end
 return false
end
local function originalPanelsVisible(cell,visible)
 for _,panel in ipairs({cell.craftInputPanel,cell.recipeInfoPanel,cell.craftResultPanel}) do
  assert(panel:getIsVisible()==visible,'native recipe panel visibility differs')
 end
end
local function embeddedFits(view)
 local cell=assert(view.cell,'plan is not embedded in NC cell')
 assert(cell.pzstPlanView==view and hasChild(cell,view),'cell does not own embedded plan')
 assert(not view.window,'embedded plan opened a floating window')
 assert(view:getIsVisible() and view.preview.width>0 and view.preview.height>0,'embedded preview size empty')
 assert(view.x>=0 and view.y>=0 and view.x+view.width<=cell.width+1 and view.y+view.height<=cell.height+1,'embedded plan exceeds native cell')
 local wishlist=assert(cell.pzswButton,'embedded Wishlist missing')
 assert(wishlist:getIsVisible(),'embedded plan hid Wishlist')
 assert(view:getAbsoluteY()+view.height<=wishlist:getAbsoluteY()+1,'embedded plan overlaps Wishlist footer')
 assert(not cell.pzstPlanButton:getIsVisible(),'plan entry remains over embedded plan')
 originalPanelsVisible(cell,false)
end
local function scrollbarBounds(view,label)
 local preview,scroll=view.preview,assert(view.preview.vscroll,'native list scrollbar missing')
 local py,ph,sy,sh=preview:getAbsoluteY(),preview:getHeight(),scroll:getAbsoluteY(),scroll:getHeight()
 local footer=view.start:getAbsoluteY()
 local wishlist=view.cell and view.cell.pzswButton:getAbsoluteY() or footer
 print('[CRAFT_TEST] SCROLLBAR_BOUNDS '..user..' label='..label..' previewActual='..ph..' previewLua='..preview.height..' previewY='..py..' scrollbarActual='..sh..' scrollbarLua='..scroll.height..' scrollbarYActual='..scroll:getY()..' scrollbarYLua='..scroll.y..' scrollbarAbsoluteY='..sy..' previewBottom='..(py+ph)..' scrollbarBottom='..(sy+sh)..' startY='..footer..' wishlistY='..wishlist)
 assert(math.abs(ph-preview.height)<=1,'native preview actual/Lua height differ')
 assert(sh>0 and sh<=ph+1 and sy>=py-1 and sy+sh<=py+ph+1,'native scrollbar exceeds actual preview viewport')
 assert(py+ph<=footer+1 and sy+sh<=footer+1,'native preview/scrollbar overlaps Start footer')
 assert(py+ph<=wishlist+1,'native preview overlaps Wishlist footer')
end
local function restored(cell,view)
 assert(view.closed,'closed embedded view did not mark itself closed')
 assert(not cell.pzstPlanView and not hasChild(cell,view),'closed embedded plan remained in cell')
 assert(childCount(cell)==ncChildren,'closed plan changed cell child count')
 originalPanelsVisible(cell,true)
 if PZSurvivorToolkit.Settings.craftChains() then separateButtons(cell) end
end
local function rows(view,kind)
 local result={}
 for _,row in ipairs(view.preview.items) do if row.item.kind==kind then result[#result+1]=row.item end end
 return result
end
local function icon(row)
 local script=row.script or (row.fullType and getScriptManager():getItem(row.fullType))
 assert(script,'preview row has no script item: '..tostring(row.kind))
 assert(script:getNormalTexture(),'preview item icon unavailable: '..tostring(row.fullType or row.name))
end
local function summaryRows(view)
 local materials,tools,steps=rows(view,'material'),rows(view,'tool'),rows(view,'step')
 assert(#materials==1 and materials[1].fullType=='Base.Log' and materials[1].amount==1,'material rows count intermediates as owned stock')
 icon(materials[1]);assert(#tools>=2,'native saw/knife tools omitted')
 for _,row in ipairs(tools) do assert(row.amount==1,'reused tool multiplied between steps');icon(row) end
 assert(#steps==3,'native recipe step preview differs')
 for i,row in ipairs(steps) do assert(row.step==i,'step order absent');icon(row) end
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
stage('server created real ingredients skill and native surface',function()
 assert(PZSurvivorToolkit.Settings.craftChains(),'fresh profile crafting chains disabled')
 assert(getActivatedMods():contains('Neat_Crafting'),'selected Neat Crafting mod missing')
 assert(fixtureSurface:isGenericCraftingSurface() and getPlayer():canUseAsGenericCraftingSurface(fixtureSurface),'native generic surface unavailable')
 assert(getPlayer():getInventory():getItemById(ids.knife):getSharpness()>0,'native knife has no sharpness')
end,fixtureReady)
stage('native/NC window exposes adjacent crafting commands',function()
 local recipe=assert(getScriptManager():getCraftRecipe('CarveWoodenSpoon'))
 assert(recipe:getLoadedScriptBodies():size()>=2,'public callback source unavailable')
 craftPanel=openNative(recipe,fixtureSurface)
 assert(containsContainer(craftPanel.logic:getContainers(),fixtureCrate),'native nearby sources omitted fixture crate')
end)
stage('native NC plan and Wishlist buttons are visible separated and rendered',function()
 separateButtons(assert(craftPanel.cellBaseCraft))
 ncChildren=childCount(craftPanel.cellBaseCraft)
 getCore():TakeFullScreenshot('craft-chain-nc-buttons-'..user..'.png')
 planWindow=assert(PZSurvivorToolkit.CraftChains.open(craftPanel))
 observeRender(planWindow)
 assert(planWindow.plan and planWindow.context,'native toolkit plan not produced')
 assert(getText('UI_PZST_CraftChainOption')~='UI_PZST_CraftChainOption','localized crafting option missing')
end,nil,500)
stage('embedded plan preview renders before capture',function()
 embeddedFits(planWindow);summaryRows(planWindow)
 scrollbarBounds(planWindow,'initial')
 print('[CRAFT_TEST] PREVIEW_RENDERED '..user..' frames='..planWindow.fixtureRenderFrames..' age='..(getTimestampMs()-planWindow.fixtureOpenedAt))
 getCore():TakeFullScreenshot('craft-chain-preview-'..user..'.png')
end,function() return rendered(planWindow) end,800)
stage('planner resolves exact real log plank handle spoon chain',function()
 local plan=planWindow.plan
 assert(#plan.steps==3,'expected three real native crafts; got '..#plan.steps)
 for i,name in ipairs({'SawLogs','CarveSmallHandlesFromPlank','CarveWoodenSpoon'}) do assert(plan.steps[i].recipe.id==name,'wrong prerequisite '..i) end
 assert(plan.consumed['Base.Log']==1,'preview did not account one raw log')
 assert(plan.resources and plan.target=='CarveWoodenSpoon','planner did not retain target')
end)
uiStage('embedded plan constrains scroll viewport through its layout',function()
 embeddedFits(planWindow)
 -- NC's minimum window height may otherwise fit every row; use the real plan layout.
 planWindow:layout(planWindow.width,260);observeRender(planWindow)
end)
uiStage('rendered constrained preview scrolls resource and recipe icon rows',function()
 scrollbarBounds(planWindow,'constrained')
 assert(planWindow.preview:getScrollHeight()>planWindow.preview.height,'preview does not provide scrollable content')
 planWindow.preview:onMouseWheel(6);observeRender(planWindow)
end,function() return rendered(planWindow) end,800)
uiStage('embedded plan actually renders scrolled rows',function()
 assert(planWindow.preview:getYScroll()<0,'preview wheel did not scroll')
 scrollbarBounds(planWindow,'scrolled')
 getCore():TakeFullScreenshot('craft-chain-scroll-'..user..'.png')
 planWindow.preview:setYScroll(0)
 local main=craftPanel.MainPanel
 main:setWidth(760);main:setHeight(460);main:calculateLayout(760,460)
 observeRender(planWindow)
end,function() return rendered(planWindow) end,800)
uiStage('short native resize preserves embedded plan and Wishlist footer',function()
 embeddedFits(planWindow)
 scrollbarBounds(planWindow,'short')
 getCore():TakeFullScreenshot('craft-chain-resize-short-'..user..'.png')
 local main=craftPanel.MainPanel
 local width=math.min(1200,getCore():getScreenWidth()-24)
 local height=math.min(850,getCore():getScreenHeight()-24)
 main:setWidth(width);main:setHeight(height);main:calculateLayout(width,height)
 observeRender(planWindow)
end,function() return rendered(planWindow) end,800)
uiStage('wide native resize preserves embedded plan and Wishlist footer',function()
 embeddedFits(planWindow)
 scrollbarBounds(planWindow,'wide')
 getCore():TakeFullScreenshot('craft-chain-resize-wide-'..user..'.png')
 planWindow.quantity:setText('2');observeRender(planWindow)
end,function() return rendered(planWindow) end,800)
uiStage('changed quantity disables Start before explicit recalculation',function()
 assert(planWindow.start.enable==false,'changed quantity can start stale reviewed plan')
 assert(planWindow.plan.count==1,'quantity change recalculated implicitly')
 assert(empty(),'quantity change enqueued native actions')
 planWindow:refresh();observeRender(planWindow)
end,function() return rendered(planWindow) end,800)
uiStage('explicit quantity refresh shows two final spoon outputs',function()
 assert(planWindow.plan.count==2 and planWindow.start.enable~=false,'explicit refresh did not review quantity two')
 local outputs=rows(planWindow,'output');local spoon
 for _,row in ipairs(outputs) do if row.fullType=='Base.WoodenSpoon' then spoon=row end end
 assert(spoon and spoon.amount==2,'final output preview differs from selected quantity');icon(spoon)
 assert(empty(),'preview refresh enqueued actions')
 getCore():TakeFullScreenshot('craft-chain-quantity-two-'..user..'.png')
 removedView=planWindow;planWindow.back:forceClick()
end,function() return rendered(planWindow) end,800)
uiStage('Back removes embedded child and restores native recipe controls',function()
 restored(craftPanel.cellBaseCraft,removedView)
 getCore():TakeFullScreenshot('craft-chain-back-'..user..'.png')
 planWindow=assert(PZSurvivorToolkit.CraftChains.open(craftPanel.cellBaseCraft));observeRender(planWindow)
end,nil,500)
uiStage('recipe change closes embedded plan without stale execution',function()
 embeddedFits(planWindow);removedView=planWindow
 craftPanel.logic:setRecipe(assert(getScriptManager():getCraftRecipe('SawLogs')))
end,function() return rendered(planWindow) end,800)
uiStage('changed recipe restored native panels and removed stale plan',function()
 restored(craftPanel.cellBaseCraft,removedView);assert(empty(),'recipe switch queued stale plan')
 craftPanel.logic:setRecipe(assert(getScriptManager():getCraftRecipe('CarveWoodenSpoon')))
 planWindow=assert(PZSurvivorToolkit.CraftChains.open(craftPanel));observeRender(planWindow)
end,nil,800)
uiStage('disabling crafting chains closes embedded plan',function()
 embeddedFits(planWindow);disabledView=planWindow
 PZAPI.ModOptions.Dict.PZSurvivorToolkit:getOption('CraftChains'):setValue(false)
end,function() return rendered(planWindow) end,800)
uiStage('disabled option removes plan and its entry while retaining Wishlist',function()
 restored(craftPanel.cellBaseCraft,disabledView)
 assert(not craftPanel.cellBaseCraft.pzstPlanButton:getIsVisible(),'disabled plan entry visible')
 assert(craftPanel.cellBaseCraft.pzswButton:getIsVisible(),'disabled plan hid Wishlist')
 getCore():TakeFullScreenshot('craft-chain-disabled-'..user..'.png')
 PZAPI.ModOptions.Dict.PZSurvivorToolkit:getOption('CraftChains'):setValue(true)
end,nil,800)
uiStage('repeated embedded open close does not accumulate children',function()
 separateButtons(craftPanel.cellBaseCraft)
 for i=1,4 do
  local view=assert(PZSurvivorToolkit.CraftChains.open(craftPanel))
  embeddedFits(view);assert(childCount(craftPanel.cellBaseCraft)==ncChildren+1,'open accumulated embedded children')
  view:close();restored(craftPanel.cellBaseCraft,view)
 end
 planWindow=assert(PZSurvivorToolkit.CraftChains.open(craftPanel));observeRender(planWindow)
end,nil,800)
uiStage('native handcraft and entity owner guards protect hidden slots and close plans',function()
 embeddedFits(planWindow);planWindow:close()
 assert(NC_EntityWindow,'native entity class missing')
 for _,class in ipairs({NC_HandcraftWindow,NC_EntityWindow}) do
  -- Keep the real crafting window open while exercising the copied entity methods.
  local owner=setmetatable({HandCraftPanel=craftPanel,hasClosedWindowInstance=true},{__index=class})
  local view=assert(PZSurvivorToolkit.CraftChains.open(craftPanel))
  assert(#owner:getJoypadInputEntries()==0 and #owner:getJoypadOutputEntries()==0,'native owner exposes hidden slots')
  assert(#owner:getJoypadActionEntries()==0,'native owner exposes hidden craft controls')
  owner:onJoypadDown(Joypad.BButton,nil);restored(craftPanel.cellBaseCraft,view)
  assert(#owner:getJoypadInputEntries()==#craftPanel.craftInputPanel.inputItems,'native Back did not restore input navigation')
  view=assert(PZSurvivorToolkit.CraftChains.open(craftPanel));owner:close()
  restored(craftPanel.cellBaseCraft,view)
 end
 print('[CRAFT_TEST] WINDOW_GUARDS '..user..' handcraft=true entity=true')
 planWindow=assert(PZSurvivorToolkit.CraftChains.open(craftPanel));observeRender(planWindow)
end,function() return rendered(planWindow) end,800)
uiStage('native read holds queue before actual embedded Start callback',function()
 currentRead=ISReadABook:new(getPlayer(),assert(getPlayer():getInventory():getItemById(ids.cancelCurrent)))
 currentRead.minutesPerPage=0.5;currentRead.maxTime=currentRead:getDuration()
 ISTimedActionQueue.add(currentRead)
end,empty)
uiStage('actual embedded Start closes plan and queues one cancellable waiting operation',function()
 embeddedFits(planWindow);removedView=planWindow
 assert(planWindow.start.enable~=false,'reviewed native plan Start is disabled')
 planWindow.start:forceClick();restored(craftPanel.cellBaseCraft,removedView)
 local waiting={}
 for _,action in ipairs(queue().queue) do if action.toolkitCraftPlanCancellation then waiting[#waiting+1]=action end end
 assert(#waiting==3,'embedded Start did not enqueue exactly three native generators')
 local token=assert(waiting[1].toolkitQueueOperation,'embedded Start operation token absent')
 for _,action in ipairs(waiting) do
  assert(action.toolkitQueueOperation==token and not action.action,'waiting embedded craft operation fragmented or started')
 end
 assert(queue().current==currentRead,'embedded Start displaced native current read')
 local Queue=PZSurvivorToolkit.ActionQueue
 assert(Queue.cancelOperationReason(queue(),waiting[1])==nil,'waiting embedded operation cannot be canceled')
 assert(Queue.cancelOperation(queue(),waiting[1],waiting),'waiting embedded operation cancellation refused')
 for _,action in ipairs(waiting) do assert(queue():indexOf(action)==-1 and not action.action,'canceled embedded generator survived or started') end
 assert(queue().current==currentRead,'embedded waiting cancellation stopped native current read')
 assert(fixtureCrate:getItemById(ids.log) and fixtureCrate:getItemById(ids.saw),'blocked Start consumed fixture stock/tools')
 print('[CRAFT_TEST] START_CALLBACK '..user..' pending=3 sharedOperation=true canceled=true')
 ISTimedActionQueue.clear(getPlayer())
end,function() return currentRead and currentRead:isStarted() end)
uiStage('native read stop leaves empty queue and another usable embedded preview',function()
 assert(not getPlayer():getCharacterActions():contains(currentRead.action),'native read survived UI Start test clear')
 assert(fixtureCrate:getItemById(ids.log) and fixtureCrate:getItemById(ids.saw),'UI Start test changed fixture raw/tool IDs')
 assert(getPlayer():getInventory():getItemById(ids.knife),'UI Start test removed kept knife')
 planWindow=assert(PZSurvivorToolkit.CraftChains.open(craftPanel));observeRender(planWindow)
end,empty)
uiStage('closing native owner removes embedded plan',function()
 embeddedFits(planWindow);removedView=planWindow
 craftPanel.MainPanel:close()
end,function() return rendered(planWindow) end,800)
uiStage('closed native owner leaves no embedded plan child',function()
 restored(craftPanel.cellBaseCraft,removedView)
 assert(empty(),'UI lifecycle test enqueued native actions')
end,nil,800)
stage('native current read holds a waiting crafting plan',function()
 currentRead=ISReadABook:new(getPlayer(),assert(getPlayer():getInventory():getItemById(ids.cancelCurrent)))
 currentRead.minutesPerPage=0.5;currentRead.maxTime=currentRead:getDuration()
 ISTimedActionQueue.add(currentRead)
end,empty)
stage('whole waiting craft operation cancellation preserves current and unrelated tail',function()
 assert(PZSurvivorToolkit.CraftChainRecipes.enqueue(getPlayer(),planWindow.plan,planWindow.context))
 waitingPlan={}
 for _,action in ipairs(queue().queue) do if action.toolkitCraftPlanCancellation then waitingPlan[#waitingPlan+1]=action end end
 assert(#waitingPlan==3 and not waitingPlan[1].action,'craft plan expanded before cancellation')
 tailRead=ISReadABook:new(getPlayer(),assert(getPlayer():getInventory():getItemById(ids.cancelTail)))
 ISTimedActionQueue.add(tailRead)
 local Queue=PZSurvivorToolkit.ActionQueue
 local why=Queue.cancelOperationReason(queue(),waitingPlan[1]);assert(why==nil,tostring(why))
 assert(Queue.cancelOperation(queue(),waitingPlan[1],waitingPlan),'waiting craft cancellation refused')
 for _,action in ipairs(waitingPlan) do assert(queue():indexOf(action)==-1 and not action.action,'canceled craft step survived or started') end
 assert(queue().current==currentRead and queue():indexOf(tailRead)==2,'unrelated native reads were removed or reordered')
 assert(fixtureCrate:getItemById(ids.log) and fixtureCrate:getItemById(ids.saw),'canceled plan changed shelf raw/tool')
 send('VerifyCancel')
end,function() return currentRead and currentRead:isStarted() end)
stage('server confirms canceled plan had no inventory or output mutation',function()
 assert(replies.CancelVerified.ok,replies.CancelVerified.error)
 ISTimedActionQueue.clear(getPlayer())
end,function() return replies.CancelVerified~=nil end)
stage('native current read stop completes before real crafting starts',function()
 assert(not getPlayer():getCharacterActions():contains(currentRead.action),'native test read survived stock clear')
 assert(getPlayer():getInventory():getItemById(ids.cancelCurrent) and getPlayer():getInventory():getItemById(ids.cancelTail),'stock clear removed books')
end,empty)
stage('UI starts real native generators and one shared operation',function()
 planWindow:startPlan()
 assert(#queue().queue>0,'plan UI did not enqueue native crafting')
 local token=queue().queue[1].toolkitQueueOperation
 for _,action in ipairs(queue().queue) do assert(action.toolkitQueueOperation==token,'craft chain operation fragmented') end
end,empty)
stage('native queued crafting renders before capture',function()
 getCore():TakeFullScreenshot('craft-chain-queued-'..user..'.png')
end,nil,500)
stage('native deferred actions finish and request authoritative outputs',function()
 send('VerifyChain')
end,empty)
stage('server confirms exact output quantities consumption and tool IDs',function()
 assert(replies.ChainVerified.ok,replies.ChainVerified.error)
 send('PrepareRace')
end,function() return replies.ChainVerified~=nil end)
stage('both clients approach the same shared raw native item',function()
 local p=getPlayer();p:teleportTo(raceIds.x+0.5,raceIds.y-0.5,0)
 p:setForceX(raceIds.x+0.5);p:setForceY(raceIds.y-0.5)
 refreshInventories()
end,function() return raceIds~=nil end)
stage('both clients preview native SawLogs against identical raw ID',function()
 craftPanel=openNative(assert(getScriptManager():getCraftRecipe('SawLogs')),raceSurface)
 local model,target,context=PZSurvivorToolkit.CraftChainRecipes.collect(craftPanel)
 assert(model,target)
 -- This race intentionally chooses only the newly supplied shared log, with native keep tools.
 local filtered={}
 for _,resource in ipairs(model.resources) do
  if resource.fullType~='Base.Log' or resource.item:getID()==raceIds.log then filtered[#filtered+1]=resource end
 end
 model.resources=filtered
 racePlan=assert(PZSurvivorToolkit.CraftPlanner.plan(model,target,1))
 raceContext=context
 assert(#racePlan.steps==1 and racePlan.steps[1].recipe.id=='SawLogs')
 send('RaceReady',{log=raceIds.log})
end,function()
 raceSurface,raceCrate=findObject(raceIds,'shared')
 if not raceCrate or not raceCrate:getItemById(raceIds.log) then return false end
 refreshInventories()
 return containsContainer(ISInventoryPaneContextMenu.getContainers(getPlayer()),raceCrate)
end)
stage('coordinated shared-log contenders use native execution',function()
 assert(replies.RaceStart.log==raceIds.log)
 assert(PZSurvivorToolkit.CraftChainRecipes.enqueue(getPlayer(),racePlan,raceContext))
end,function() return replies.RaceStart~=nil end)
stage('both native contender queues end without client-created items',function()
 send('RaceDone')
end,empty)
stage('server permits exactly one shared log conversion',function()
 assert(replies.RaceVerified.ok,replies.RaceVerified.error)
 assert(replies.RaceVerified.completed==1,'native shared race completed twice')
 getCore():TakeFullScreenshot('craft-chain-result-'..user..'.png')
end,function() return replies.RaceVerified~=nil end)
stage('classic native recipe panel builds with toolkit and Wishlist XUI hooks',function()
 if planWindow and planWindow:getIsVisible() then planWindow:close() end
 ISEntityUI.CloseWindows()
 local logic=HandcraftLogic.new(getPlayer(),nil,raceSurface or fixtureSurface)
 logic:setContainers(ISInventoryPaneContextMenu.getContainers(getPlayer()))
 logic:setRecipe(assert(getScriptManager():getCraftRecipe('SawLogs')))
 classic=ISXuiSkin.build(XuiManager.GetDefaultSkin(),'S_NeedsAStyle',ISCraftRecipePanel,100,80,400,560,getPlayer(),logic)
 classic:initialise();classic:instantiate();classic:calculateLayout(400,560);classic:addToUIManager();classic:bringToTop()
 observeRender(classic)
end,empty)
stage('classic native recipe panel commands have separate visible rows',function()
 separateButtons(classic)
 getCore():TakeFullScreenshot('craft-chain-classic-buttons-'..user..'.png')
 if scenario~='ui' then classic:removeFromUIManager() end
end,function() return rendered(classic) end,800)
classicUIStages[#classicUIStages+1]={'classic native fallback opens an icon plan in its opaque window',function()
 planWindow=assert(PZSurvivorToolkit.CraftChains.open(classic));observeRender(planWindow)
 assert(planWindow.window and planWindow.window.backgroundColor.a==1,'classic fallback has no opaque host window')
 assert(not planWindow.cell and planWindow.plan,'classic fallback did not produce a plan')
 assert(hasChild(planWindow.window,planWindow),'classic window does not own plan view')
end}
classicUIStages[#classicUIStages+1]={'classic fallback resource tool recipe and result rows render before capture',function()
 assert(planWindow:getIsVisible() and planWindow.window:getIsVisible(),'classic fallback hidden')
 for _,kind in ipairs({'material','tool','step','output'}) do
  local list=rows(planWindow,kind);assert(#list>0,'classic fallback omitted '..kind..' rows')
  for _,row in ipairs(list) do icon(row) end
 end
 print('[CRAFT_TEST] FALLBACK_RENDERED '..user..' frames='..planWindow.fixtureRenderFrames)
 getCore():TakeFullScreenshot('craft-chain-classic-preview-'..user..'.png')
 planWindow.back:forceClick();assert(planWindow.closed,'classic Back did not close plan')
 separateButtons(classic);classic:removeFromUIManager()
end,function() return rendered(planWindow) end,800}
if scenario=='ui' then
 local selected={}
 for i=1,5 do selected[#selected+1]=stages[i] end
 for _,spec in ipairs(uiStages) do selected[#selected+1]=spec end
 selected[#selected+1]=stages[#stages-1];selected[#selected+1]=stages[#stages]
 for _,spec in ipairs(classicUIStages) do selected[#selected+1]=spec end
 stages=selected
end
CraftIntakeFixture={stageCount=#stages}
print('[CRAFT_TEST] EXPECTED checks='..#stages..' scenario='..scenario)
Events.OnServerCommand.Add(function(module,command,args)
 if module~='CraftChainTest' then return end
 if command=='Setup' then
  if not ids then ids=args;previous=getTimestampMs() end
 elseif command=='RaceSetup' then raceIds=args
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
