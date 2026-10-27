-- Joining actor: real Project Cook plus/Cook, native oven and native SliceBread.
require 'Project_Cook/PJCK_CookingUI'
require 'Project_Cook/PJCK_Window'
require 'Project_Cook/PJCK_Config'
require 'TimedActions/ISInventoryTransferUtil'
require 'TimedActions/ISToggleStoveAction'
require 'TimedActions/ISReadABook'
local F=require 'QueueCookSandwichFixture'
local M={};local active
local methodNames={'new','start','perform','complete','getDuration','isValidStart','isValid','onStartFunc','onCompleteFunc','onCancelFunc'}
local function q(run)return ISTimedActionQueue.getTimedActionQueue(run.player)end
local function idle(run)return #q(run).queue==0 and not run.player:hasTimedActions()end
local function exact(run,id)
 local root=run.player:getInventory();local item=root:getItemById(id)or run.state.sourceContainer:getItemById(id)
  or run.state.ovenContainer and run.state.ovenContainer:getItemById(id)
 return item
end
local function nativeSources(run)
 local source=assert(F.resolveSource(run.ids.source),'declared joining crate changed')
 assert(source==run.state.sourceContainer,'joining crate proxy changed')
 getPlayerInventory(run.player:getPlayerNum()):refreshBackpacks();getPlayerLoot(run.player:getPlayerNum()):refreshBackpacks()
 local containers=ISInventoryPaneContextMenu.getContainers(run.player);local seen={}
 for i=0,containers:size()-1 do seen[containers:get(i)]=true end
 assert(seen[source],'actual native getContainers lost the declared shared crate')
 if run.ids.oven then assert(seen[run.state.ovenContainer],'actual native getContainers lost the declared oven')end
 run.state.containers=containers;return containers
end
local function rootFoods(run,kind)
 local out={};local root=run.state.root
 for i=0,root:getItems():size()-1 do local item=root:getItems():get(i)
  if item:getFullType()==kind and not run.baseline[item:getID()]then out[#out+1]=item end
 end
 table.sort(out,function(a,b)return a:getID()<b:getID()end);return out
end
local function remember(run,action,kind)
 if run.seen[action]then return end
 local row={kind=kind,type=action.Type,duration=action:getDuration(),progress=false,stage=run.stage,dispatch=run.currentDispatch}
 if action.item then row.itemId=action.item:getID();row.itemType=action.item:getFullType()end
 if action.usedItem then
  row.itemId=action.usedItem:getID();row.itemType=action.usedItem:getFullType();row.baseId=action.baseItem:getID()
  row.baseRoot=action.baseItem:getContainer()==run.state.root;row.inputRoot=action.usedItem:getContainer()==run.state.root
  row.basePresent=run.state.root:contains(action.baseItem);row.inputPresent=run.state.root:contains(action.usedItem)
  row.cookingLevel=run.player:getPerkLevel(Perks.Cooking)
  row.inputBefore=F.snapshot(action.usedItem)
 end
 if kind=='transfer'then row.pickup=action.destContainer==run.state.root;row.returned=action.srcContainer==run.state.root
  row.sourceType=action.srcContainer:getType();row.destinationType=action.destContainer:getType()end
 local callbacks={};for _,name in ipairs(methodNames)do callbacks[name]=action[name]end
 callbacks.onStartFunc=action.onStartFunc;callbacks.onCompleteFunc=action.onCompleteFunc;callbacks.onCancelFunc=action.onCancelFunc
 run.seen[action]={row=row,methods=callbacks};run.records[#run.records+1]=row
end
function M.observe(run)
 for _,action in ipairs(q(run).queue)do
  if action.Type=='ISAddItemInRecipe'then
   assert(run.allowed[action.usedItem:getID()],'native cooking selected a foreign physical ingredient')
   remember(run,action,'evolved')
  elseif action.Type=='ISInventoryTransferAction'and action.item and run.owned[action.item:getID()]then remember(run,action,'transfer')
  elseif action.Type=='ISHandcraftAction'and action.craftRecipe==run.sliceRecipe then remember(run,action,'slice')
  elseif action==run.tail then remember(run,action,'tail')end
 end
 local current=q(run).current
 for action,record in pairs(run.seen)do
  if current==action and action:isStarted()and action:getJobDelta()>0 then
   record.row.progress=true;record.row.duration=action:getDuration()
   if record.row.kind=='transfer'and isClient()and action.transactionId and action.transactionId~=0 then
    local duration=getItemTransactionDuration(action.transactionId);if duration>1 then record.row.transactionDuration=duration end
   end
  end
 end
 if current==run.tail and run.tail and run.tail:isStarted()and run.tail:getJobDelta()>0 and not run.tailObserved then
  run.tailObserved=true;run.sourceAtTail=F.observerSnapshot(run.player,run.ids)
  run.returnsBeforeRead=true
  for _,meta in ipairs(run.ids.sandwichInputs)do local item=exact(run,meta.id)
   if not item or item:getContainer()~=run.state.sourceContainer then run.returnsBeforeRead=false end
  end
 end
end
local function recipeFor(panel,base,target)
 local recipes=assert(panel:getRecipes(base));local selected
 for i=0,recipes:size()-1 do local recipe=recipes:get(i);local result=recipe:getResultItem()
  if result==target or 'Base.'..result==target then assert(not selected,'ambiguous real evolved recipe');selected=recipe end
 end
 return assert(selected,'real evolved recipe unavailable: '..target)
end
local function dispatch(run,base,target,metas,stage)
 local panel=run.panel;run.window:switchToPanel('evolved');local containers=nativeSources(run)
 panel:setContainers(containers);panel:setBaseItem(base);local recipe=recipeFor(panel,base,target);panel:setRecipe(recipe)
 -- Use the same live state computation as CookingInfo:render before testing any plus.
 panel.cookingInfoPanel:updateContentType()
 local cookStatus=panel:getCookStatus();assert(cookStatus=='addOneFirst'or cookStatus=='showNutrition','real cooking content state differs')
 assert(base:getContainer()==run.state.root and panel:getBaseItem()==base,'real selected base is not canonical root')
 assert(#panel:getPreCookItems()==0,'real plus/Cook inherited pending requests')
 local record={stage=stage,baseBefore=F.snapshot(base),cookStatus=cookStatus,requests={}}
 run.currentDispatch=#run.dispatches+1
 for _,meta in ipairs(metas)do
  local item=assert(exact(run,meta.id),'declared source ingredient missing')
  assert(item:getContainer()==run.state.sourceContainer and item:getFullType()==meta.kind,'ingredient left exact shared crate before plus')
  local available=recipe:getItemsCanBeUse(run.player,base,containers)
  assert(available and available:contains(item),'actual native recipe rejected the exact shared ingredient')
  local info
  for _,entry in ipairs(panel:getInputList('Ingredient'))do
   if entry.item and entry.item:getID()==meta.id and entry.isPossible~=true then assert(not info,'duplicate usable native ingredient row');info=entry end
  end
  assert(info and info.usableIds[meta.id],'real usable ingredient slot missing for '..meta.kind)
  local input=assert(panel.ingredientsPanel);local scroll=assert(input.scrollView)
  local slot=input:onCreateSlot(1);slot:initialise();scroll:addChild(slot);input:onUpdateSlot(slot,info,1,1);slot:setVisible(true)
  assert(slot:getParent()==scroll and slot.onAddButton==PJCK_ItemSlot.onAddButton,'native plus slot binding changed')
  local displayed=slot:isDisplayedItemUsable();local plusAllowed=input:canAddItem(item)
  assert(displayed and plusAllowed,'real rendered plus control rejected a native-eligible ingredient: '..stage..':'..cookStatus)
  local before=#panel:getPreCookItems();local callback=slot.onAddButton;local ok,problem=pcall(callback,slot);scroll:removeChild(slot);assert(ok,problem)
  local requests=panel:getPreCookItems();local request=requests[#requests]
  assert(#requests==before+1 and request.displayItem and request.displayItem:getID()==meta.id
   and request.recipeCompatible==true and request.panelType=='Ingredient','real plus chose another ingredient/use')
  local use=assert(recipe:getItemRecipe(item)):getUse()
  assert(request.recipeUse==use,'source request/native portion mismatch')
  record.requests[#record.requests+1]={id=meta.id,kind=meta.kind,recipeUse=use,groupKey=request.groupKey,before=F.snapshot(item),displayedUsable=displayed,plusAllowed=plusAllowed}
  if cookStatus=='addOneFirst'then
   assert(#metas==1 and #requests==1 and not input:canAddItem(item),'first conversion allowed another pending ingredient')
   record.firstOnly=true
  end
 end
 local basePanel=assert(panel.baseItemPanel);assert(basePanel.onCook==PJCK_BaseItem.onCook,'native Cook callback changed')
 basePanel:updateButtonsVisibility()
 assert(basePanel.cookButton.onclick==basePanel.onCook and basePanel.cookButton.target==basePanel
  and basePanel.cookButton:getIsVisible()and basePanel.cookButton.enable,'real Cook control unavailable after plus')
 assert(#panel:getPreCookItems()==#metas,'real plus selected another logical request count')
 record.plusCallback=tostring(PJCK_ItemSlot.onAddButton);record.cookCallback=tostring(basePanel.onCook)
 basePanel.cookButton:forceClick()
 assert(#panel:getPreCookItems()==0,'real Cook did not consume logical requests')
 run.dispatches[#run.dispatches+1]=record;run.currentRecipe=recipe
 M.observe(run)
end
local function requestCheckpoint(run,stage,nextStage)
 assert(not run.waitingCheckpoint,'overlapping authoritative cooking checkpoints')
 run.waitingCheckpoint=stage;run.afterCheckpoint=nextStage;run.stage='checkpoint'
 sendClientCommand('CraftUITest','ActorCheckpoint',{case=run.ids.case,stage=stage})
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~='CraftUITest'or command~='ActorCheckpoint'or not active then return end
 local run=active
 assert(args.case==run.ids.case and args.stage==run.waitingCheckpoint,'authoritative cooking checkpoint identity differs')
 run.checkpoints[args.stage]=assert(args.snapshot,'authoritative cooking checkpoint missing')
 run.waitingCheckpoint=nil;run.stage=assert(run.afterCheckpoint);run.afterCheckpoint=nil
end)
local function transfer(run,item,from,to)
 assert(item:getContainer()==from,'native transfer source differs')
 local action=assert(ISInventoryTransferUtil.newInventoryTransferAction(run.player,item,from,to,nil))
 action:setAllowMissingItems(false);ISTimedActionQueue.add(action);remember(run,action,'transfer');return action
end
local function finalCook(run,base)
 -- The real UI requires one addition to create a new recipe result before selecting more.
 run.stage='sandwich-first';dispatch(run,base,'Base.Sandwich',{run.ids.sandwichInputs[1]},'Sandwich')
 run.stage='sandwich-first-working'
end
local function finishSandwich(run,base)
 run.stage='sandwich-rest';dispatch(run,base,'Base.Sandwich',{run.ids.sandwichInputs[2]},'Sandwich')
 run.tail=ISReadABook:new(run.player,run.state.book)
 assert(run.tail.minutesPerPage==2.0 and run.tail.maxTime>1 and not run.player:isTimedActionInstant(),'native reader cost changed')
 ISTimedActionQueue.add(run.tail);remember(run,run.tail,'tail');run.dispatched=true
end
local function slice(run,bread)
 run.window:switchToPanel('craft')
 local panel=assert(run.window.HandCraftPanel);local logic=panel.logic;local owner=panel.craftActionPanel
 local recipe=assert(getScriptManager():getCraftRecipe('SliceBread'));run.sliceRecipe=recipe
 assert(recipe:getInputs():size()==2,'native SliceBread input contract changed')
 logic:setContainers(nativeSources(run));logic:setRecipe(recipe);logic:setManualSelectInputs(true);logic:clearManualInputs()
 for index,item in ipairs({run.state.root:getItemById(run.ids.knife.id),bread})do
  local selected=ArrayList.new();selected:add(assert(item));assert(logic:setManualInputsFor(recipe:getInputs():get(index-1),selected),'native SliceBread manual input rejected')
 end
 assert(logic:canPerformCurrentRecipe(),'native SliceBread eligibility failed')
 owner.quantityInput:setText('1');owner:updateCraftAction()
 assert(owner.craftButton.onclick==PJCK_CraftActionPanel.onCraftButtonClick and owner.craftButton.target==owner
  and owner.craftButton.enable,'real SliceBread craft control unavailable')
 run.stage='slicing';owner.craftButton:forceClick()
 local found
 for _,action in ipairs(q(run).queue)do if action.Type=='ISHandcraftAction'and action.craftRecipe==recipe then
  assert(not found,'native SliceBread queued twice');found=action
  assert(action:getDuration()==200 and action.onStartTarget==owner and action.onCompleteTarget==owner,'SliceBread native cost/callback owner changed')
  remember(run,action,'slice')
 end end
 assert(found,'native SliceBread action was not queued')
end
function M.start(player,state,ids,enabled)
 assert(isClient()and player:getUsername()=='client2'and player:getOnlineID()==ids.actorId,'sandwich actor must be joining client2')
 assert(not active and not PJCK_CookingUI.IsWindowOpen(player:getPlayerNum()),'joining cooking window already active')
 local run={player=player,state=state,ids=ids,enabled=enabled,seen={},records={},dispatches={},checkpoints={},allowed={},owned={},baseline={},
  stage=ids.oven and 'bread'or 'plain',deadline=getTimestampMs()+300000}
 for _,id in ipairs(ids.baselineOutputIds)do run.baseline[id]=true end
 for _,set in ipairs({ids.breadInputs,ids.sandwichInputs})do for _,meta in ipairs(set)do run.allowed[meta.id]=true;run.owned[meta.id]=true end end
 run.owned[ids.base.id]=true
 run.previousSetting=PJCK_Config.get().baseItemHandling;PJCK_Config.get().baseItemHandling='keep_inventory'
 PJCK_CookingUI.OnOpenPanel(player);run.window=assert(PJCK_CookingUI.GetWindowInstance(player:getPlayerNum()));run.panel=assert(run.window.EvoPanel)
 assert(PZSurvivorToolkit.ActionQueueCompat.isInstalled('Project_Cook'),'Project Cook source adapter unverified')
 active=run;return M.continueStart(run)
end
function M.continueStart(run)
 M.observe(run);if run.dispatched then return run end
 assert(getTimestampMs()<=run.deadline,'native joining bread chain exceeded bounded fixture deadline')
 if run.stage=='checkpoint'then return run end
 if run.stage=='plain'then finalCook(run,assert(exact(run,run.ids.base.id)))
 elseif run.stage=='bread'then
  dispatch(run,assert(exact(run,run.ids.base.id)),'Base.BreadDough',run.ids.breadInputs,'Bread');run.stage='bread-working'
 elseif run.stage=='bread-working'and idle(run)then
  local bread=exact(run,run.ids.base.id)
  if bread and bread:getExtraItems()and bread:getExtraItems():size()==2 and bread:getContainer()==run.state.root then requestCheckpoint(run,'BreadAdded','place-bread')end
 elseif run.stage=='place-bread'then
  local bread=assert(exact(run,run.ids.base.id));local oven=assert(run.state.ovenObject)
  oven:setMaxTemperature(200);oven:setTimer(0);oven:sync();oven:syncSpriteGridObjects(false,true)
  transfer(run,bread,run.state.root,run.state.ovenContainer)
  assert(not oven:Activated(),'owned oven unexpectedly active before native toggle')
  ISTimedActionQueue.add(ISToggleStoveAction:new(run.player,oven));run.bakingStarted=getTimestampMs();run.stage='baking'
 elseif run.stage=='baking'and idle(run)then
  local bread=exact(run,run.ids.base.id)
  if bread then assert(not bread:isBurnt(),'native enriched bread burned');if bread:isCooked()then requestCheckpoint(run,'Baked','retrieve-bread')end end
 elseif run.stage=='retrieve-bread'then
  local bread=assert(exact(run,run.ids.base.id));local oven=run.state.ovenObject
  assert(oven:Activated(),'native oven was not active while baking')
  ISTimedActionQueue.add(ISToggleStoveAction:new(run.player,oven));transfer(run,bread,run.state.ovenContainer,run.state.root);run.stage='retrieving'
 elseif run.stage=='retrieving'and idle(run)then
  local bread=run.state.root:getItemById(run.ids.base.id)
  if bread and bread:getContainer()==run.state.root and bread:isCooked()then slice(run,bread)end
 elseif run.stage=='slicing'and idle(run)then
  local slices=rootFoods(run,'Base.BreadSlices')
  if #slices==3 and not exact(run,run.ids.base.id)then
   run.sliceIds={};for _,item in ipairs(slices)do run.sliceIds[#run.sliceIds+1]=item:getID()end
   requestCheckpoint(run,'Sliced','sandwich-ready')
  end
 elseif run.stage=='sandwich-ready'then finalCook(run,assert(run.state.root:getItemById(run.sliceIds[1])))
 elseif run.stage=='sandwich-first-working'and idle(run)then
  local sandwiches=rootFoods(run,'Base.Sandwich')
  if #sandwiches==1 then
   run.firstSandwich=F.snapshot(sandwiches[1]);requestCheckpoint(run,'FirstSandwich','sandwich-rest-ready')
  end
 elseif run.stage=='sandwich-rest-ready'then
  finishSandwich(run,assert(run.state.root:getItemById(run.firstSandwich.id)))
 end
 return run
end
function M.finish(run,authority)
 M.observe(run);local unchanged=true;local evolved,progress=0,0
 local grouped,tailIndependent=true,true;local groups={}
 for action,record in pairs(run.seen)do
  record.row.sourceMethodsUnchanged=true
  for _,name in ipairs(methodNames)do if action[name]~=record.methods[name]then unchanged=false;record.row.sourceMethodsUnchanged=false end end
  if record.row.kind=='evolved'then
   evolved=evolved+1;if record.row.progress then progress=progress+1 end
   if run.enabled then
    local token=action.toolkitQueueOperation;local dispatch=record.row.dispatch
    if not token or not dispatch or groups[dispatch]and groups[dispatch]~=token then grouped=false end
    groups[dispatch]=token
    if not run.tail.toolkitQueueOperation or run.tail.toolkitQueueOperation==token then tailIndependent=false end
   end
  end
 end
 local expected=run.ids.oven and 4 or 2
 local reason=evolved~=expected and 'native-evolved-count-differs'or progress~=expected and 'native-evolved-progress-missing'
  or not unchanged and 'native-callback-changed'or not run.tailObserved and 'native-independent-tail-missing'
  or not run.returnsBeforeRead and 'native-leftovers-not-before-tail'or not grouped and 'native-evolved-grouping-differs'
  or not tailIndependent and 'native-tail-operation-not-independent'or nil
 local actualSandwiches,actualSlices={},{}
 for _,item in ipairs(rootFoods(run,'Base.Sandwich'))do actualSandwiches[#actualSandwiches+1]=F.snapshot(item)end
 for _,item in ipairs(rootFoods(run,'Base.BreadSlices'))do actualSlices[#actualSlices+1]=F.snapshot(item)end
 local value={event='case',id=run.ids.case,status=reason and 'failed'or 'passed',reason=reason,requested=expected,actions=evolved,
  sourceVerified=true,sourceMethodsUnchanged=unchanged,callbackClass='PJCK_EvoPanel',dispatchMethod='PJCK_ItemSlot.onAddButton+PJCK_BaseItem.onCook',
  cookingLevel=run.player:getPerkLevel(Perks.Cooking),actorId=run.player:getOnlineID(),records=run.records,dispatches=run.dispatches,
  actorCheckpoints=run.checkpoints,firstSandwich=run.firstSandwich,tailProgress=run.tailObserved==true,returnsBeforeRead=run.returnsBeforeRead==true,
  actualSandwiches=actualSandwiches,actualSlices=actualSlices,finalSourceSnapshot=F.observerSnapshot(run.player,run.ids),sourceAtTail=run.sourceAtTail,sliceIds=run.sliceIds,
  tailIndependent=tailIndependent,tokensGrouped=run.enabled and grouped,bakingElapsedMs=run.bakingStarted and getTimestampMs()-run.bakingStarted or nil}
 for key,entry in pairs(authority)do if key~='case'then value[key]=entry end end
 PJCK_Config.get().baseItemHandling=run.previousSetting;run.window:onCloseClick();active=nil
 return value,reason
end
return M
