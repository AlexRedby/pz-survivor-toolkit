-- Actual UI and timed actions; no lifecycle or effect callback is replaced here.
require 'Project_Cook/PJCK_Window'
require 'Project_Cook/PJCK_CookingUI'
require 'Project_Cook/PJCK_Config'
local BaseFixture=require 'QueueCookEvolvedFixture'
local Evolved={}
local methods={'new','isValidStart','start','perform','complete','getDuration'}
local function queue(player)return ISTimedActionQueue.getTimedActionQueue(player)end
local function values(list)
 local result={};for _,value in ipairs(list)do result[#result+1]=value end;return result
end
local function waterCase(case)return case=='cook-water-soup'or case=='cook-water-stew'or case=='cook-water-soup-world'or case=='cook-water-stew-beans'or case=='cook-water-stew-floor-plus'end
local function dishType(case)
 return (case=='cook-water-soup'or case=='cook-water-soup-world')and 'Base.PotOfSoupRecipe'or (case=='cook-water-stew'or case=='cook-water-stew-beans'or case=='cook-water-stew-floor-plus')and 'Base.PotOfStew'or 'Base.Salad'
end
local function sourceCount(container,id)
 local total=0
 for i=0,container:getItems():size()-1 do
  local item=container:getItems():get(i)
  if item:getID()==id then total=total+1 end
  if instanceof(item,'InventoryContainer')then total=total+sourceCount(item:getItemContainer(),id)end
 end
 return total
end
local function visibleSource(run)
 if run.floor then
  local item=BaseFixture.resolveWorldBase(run.ids.base.world)
  local source=item and item:getContainer()or ISInventoryPage.GetFloorContainer(run.player:getPlayerNum())
  local containers=assert(ISInventoryPaneContextMenu.getContainers(run.player))
  local seen=false;for i=0,containers:size()-1 do if containers:get(i)==source then seen=true end end
  assert(source,'native floor cache and actual world-item container are both missing')
  return source,containers
 end
 local source=BaseFixture.resolveBaseSource(run.ids.base.source)
 assert(source and source==run.state.baseSource,'declared native base source changed')
 local containers=assert(ISInventoryPaneContextMenu.getContainers(run.player),'native source containers missing')
 local seen=false
 for i=0,containers:size()-1 do if containers:get(i)==source then seen=true end end
 assert(seen,'actual native getContainers does not expose the exact adjacent base source')
 return source,containers
end
local function itemSnapshot(run,item)
 if not item then return {missing=true}end
 local root=run.state.root;local container=item:getContainer()
 local owner=container and container:getContainingItem()or nil
 local value={id=item:getID(),kind=item:getFullType(),containerType=container and container:getType()or 'nil',
  containerItemId=owner and owner:getID()or -1,root=container==root,group=run.panel:getItemGroupKey(item)}
 if run.world then value.declaredSource=container==run.state.baseSource end
 if run.floor then
  local world=item:getWorldItem()
  value.hasWorldItem=world~=nil;value.worldItemMatches=world and world:getItem()==item or false
  value.worldPresent=world and world:getSquare()and world:getSquare():getWorldObjects():contains(world)or false
  local fluid=item:getFluidContainerFromSelfOrWorldItem()
  value.fluidOwner=fluid and (item:getFluidContainer()==fluid and 'item'or 'world')or 'nil'
  value.waterAmount=fluid and fluid:getAmount()or -1
 end
 if instanceof(item,'Food')then
  value.hunger=item:getHungChange();value.frozen=item:isFrozen();value.cooked=item:isCooked()
  value.rotten=item:isRotten();value.fresh=item:isFresh()
 end
 return value
end
local function observeFloor(run,event)
 if not run.floor or #run.floorObservations>=32 then return end
 local item,world,index=BaseFixture.resolveWorldBase(run.ids.base.world)
 local rootItem=run.state.root:getItemById(run.ids.base.id);local selected=run.panel:getBaseItem()
 local canonical=ISInventoryPage.GetFloorContainer(run.player:getPlayerNum())
 local actual=item and item:getContainer()
 local containers=assert(ISInventoryPaneContextMenu.getContainers(run.player));local exposed={}
 for i=0,containers:size()-1 do
  local source=containers:get(i)
  exposed[#exposed+1]={index=i,kind=source:getType(),canonicalFloor=source==canonical,actualItemContainer=source==actual,
   originalIdCount=sourceCount(source,run.ids.base.id),containsExactWorldReference=item and source:contains(item)or false}
 end
 run.floorObservations[#run.floorObservations+1]={event=event,timestampMs=getTimestampMs(),
  worldCount=BaseFixture.worldCount(run.ids.base.world,run.ids.base.id),worldObjectIndex=index or -1,
  worldItem=itemSnapshot(run,item),rootItem=itemSnapshot(run,rootItem),selectedBase=itemSnapshot(run,selected),
  worldObjectIsOriginal=world and world==run.originalBaseWorld or false,
  selectedIsWorldReference=item and selected==item or false,selectedIsRootReference=rootItem and selected==rootItem or false,
  canonicalFloorContainsId=canonical and sourceCount(canonical,run.ids.base.id)or -1,
  actualContainerIsCanonical=actual and actual==canonical or false,exposedContainers=exposed,
  baseItemHandling=PJCK_Config.get().baseItemHandling}
end
local function observeBaseTransfer(run,event)
 if not run.baseTransferTrace then return end
 local trace=run.baseTransferTrace;local now=getTimestampMs();local action=run.basePickup
 local root=run.state.root;local source=run.floor and visibleSource(run)or assert(BaseFixture.resolveBaseSource(run.ids.base.source))
 local live=root:getItemById(run.ids.base.id);local selected=run.panel:getBaseItem()
 local ingredient=BaseFixture.resolveIngredient(root,run.ids.ingredient)
 local started=action and action:isStarted()==true or false
 local delta=started and action:getJobDelta()or 0
 if started and not trace.startedTimestampMs then trace.startedTimestampMs=now end
 if delta>0 then trace.progress=true end
 if action and action:getDuration()>1 then trace.nativeDuration=action:getDuration()end
 if isClient()and action and action.transactionId and action.transactionId~=0 then
  local paid=getItemTransactionDuration(action.transactionId)
  if paid>1 then trace.transactionDuration=paid end
 end
 if live and live:getContainer()==root and not trace.rootArrivalTimestampMs then
  trace.rootArrivalTimestampMs=now;trace.baseRootObservedAt=now;trace.selectionToRootMs=now-trace.selectionTimestampMs
 end
 if ingredient and ingredient:getContainer()==root and not trace.ingredientRootObservedAt then
  trace.ingredientRootObservedAt=now;trace.selectionToIngredientRootMs=now-trace.selectionTimestampMs
  trace.ingredientRootState={selectedBase=itemSnapshot(run,selected),liveBase=itemSnapshot(run,live),
   pendingBaseItemTransferId=run.panel.pendingBaseItemTransferId or -1,
   pendingBaseItemTransferUntil=run.panel.pendingBaseItemTransferUntil or -1}
  event=event or 'ingredient-root-arrival'
 end
 if not selected and trace.initialPendingUntil and now>trace.initialPendingUntil and not trace.expiryEventObservedAt then
  trace.expiryEventObservedAt=now;trace.selectionToExpiryEventMs=now-trace.selectionTimestampMs
  event=event or 'selected-base-missing-after-deadline'
 end
 if not trace.ingredientOrExpiryObservedAt then
  local critical=trace.ingredientRootObservedAt or trace.expiryEventObservedAt
  if critical then
   trace.ingredientOrExpiryObservedAt=critical;trace.selectionToIngredientOrExpiryMs=critical-trace.selectionTimestampMs
   trace.overPendingDeadline=trace.selectionToIngredientOrExpiryMs>6000
  end
 end
 local key=tostring(started)..':'..tostring(delta>0)..':'..tostring(live and live:getContainer()==root)
  ..':'..tostring(selected and selected:getID())..':'..tostring(selected and selected:getContainer()==root)
  ..':'..tostring(run.panel.pendingBaseItemTransferId)..':'..tostring(run.panel.pendingBaseItemTransferUntil)
  ..':'..tostring(ingredient and ingredient:getContainer()==root)
 if (event or key~=trace.lastStateKey)and #trace.events<32 then
  trace.events[#trace.events+1]={event=event or 'base-state',timestampMs=now,actionStarted=started,jobDelta=delta,
   pendingBaseItemTransferId=run.panel.pendingBaseItemTransferId or -1,
   pendingBaseItemTransferUntil=run.panel.pendingBaseItemTransferUntil or -1,
   selectedBase=itemSnapshot(run,selected),liveBase=itemSnapshot(run,live),sourceBase=itemSnapshot(run,source:getItemById(run.ids.base.id)),
   liveIngredient=itemSnapshot(run,ingredient),
   rootBaseCount=sourceCount(root,run.ids.base.id),sourceBaseCount=sourceCount(source,run.ids.base.id)}
 end
 trace.lastStateKey=key
 if run.floor and (event or key~=trace.lastFloorKey)then observeFloor(run,event or 'base-state');trace.lastFloorKey=key end
end
local function observeInputs(run,event)
 if not run.water or #run.inputObservations>=24 then return end
 local root=run.state.root
 observeFloor(run,event)
 local base=root:getItemById(run.ids.base.id);local ingredient=BaseFixture.resolveIngredient(root,run.ids.ingredient)
 local row={event=event,
  originalBaseIsLive=run.originalBase==base,selectedBaseIsLive=run.panel:getBaseItem()==base,
  originalIngredientIsLive=run.originalIngredient==ingredient,
  originalBase=itemSnapshot(run,run.originalBase),selectedBase=itemSnapshot(run,run.panel:getBaseItem()),
  liveBase=itemSnapshot(run,base),originalIngredient=itemSnapshot(run,run.originalIngredient),liveIngredient=itemSnapshot(run,ingredient)}
 if run.baseTransferTrace then
  row.timestampMs=getTimestampMs();row.pendingBaseItemTransferId=run.panel.pendingBaseItemTransferId or -1
  row.pendingBaseItemTransferUntil=run.panel.pendingBaseItemTransferUntil or -1
 end
 if run.beans then
  local sequence,entry=run.ingredientSequence,run.ingredientEntry
  row.sequence=entry and {groupKey=entry.groupKey,itemId=entry.itemId or -1,
   expectedFullType=entry.expectedFullType or 'nil',preferredItemId=entry.preferredItemId or -1,
   awaitingTransfer=entry.awaitingTransfer==true,retryCount=entry.retryCount or 0,retryUntil=entry.retryUntil or -1,
   originalContainerType=entry.originalContainer and entry.originalContainer:getType()or 'nil',
   transferFailureNotified=sequence.transferFailureNotified==true}or {missing=true}
  if run.buttons then
   row.baseItemHandling=PJCK_Config.get().baseItemHandling
   row.sequence.returnBaseItemToSource=sequence and sequence.returnBaseItemToSource==true or false
   row.sequence.baseReturnTargetType=sequence and sequence.baseReturnTarget and sequence.baseReturnTarget:getType()or 'nil'
  end
  local source,containers=visibleSource(run)
  local recipeBase=base or run.panel:getBaseItem()
  local baseContainer=recipeBase and recipeBase:getContainer()
  local recipeBaseLive=recipeBase and (baseContainer==root and root:getItemById(recipeBase:getID())==recipeBase
   or baseContainer==source and source:getItemById(recipeBase:getID())==recipeBase)
  row.nativeRecipeBase=itemSnapshot(run,recipeBase);row.nativeRecipeBaseIsLive=recipeBaseLive==true
  if recipeBaseLive and ingredient then
   local available=run.recipe:getItemsCanBeUse(run.player,recipeBase,containers)
   row.nativeRecipeUsable=available and available:contains(ingredient)==true or false
   local profile=run.panel:getItemNextPortionProfile(ingredient,run.recipe,run.recipeUse)
   row.nextPortionProfile={nextKind=profile.nextKind,willConsumeNext=profile.willConsumeNext,
    fullUses=profile.fullUses,partialUses=profile.partialUses,
    hasFullUses=profile.fullUses~=nil,hasPartialUses=profile.partialUses~=nil}
  end
 end
 if run.world then
  local source=run.floor and visibleSource(run)or BaseFixture.resolveBaseSource(run.ids.base.source)
  row.sourceLive=source~=nil
  row.sourceBaseCount=source and sourceCount(source,run.ids.base.id)or -1
  row.rootBaseCount=sourceCount(root,run.ids.base.id)
  row.sourceItemCount=source and source:getItems():size()or -1
  row.sourceBase=itemSnapshot(run,source and source:getItemById(run.ids.base.id))
  row.source=run.ids.base.source
  if run.beans then
   row.sourceIngredientCount=source and sourceCount(source,run.ids.ingredient.id)or -1
   row.rootIngredientCount=sourceCount(root,run.ids.ingredient.id)
   row.sourceIngredient=itemSnapshot(run,source and source:getItemById(run.ids.ingredient.id))
  end
 end
 run.inputObservations[#run.inputObservations+1]=row
end
function Evolved.dispatchWaterSlot(input,info)
 local scroll=assert(input.scrollView,'real ingredient slot scroll view missing')
 assert(input.slotWidth>0 and input.slotHeight>=input.slotWidth,'real ingredient slot dimensions unavailable')
 -- Follow NIGridVirtualScrollView.initializePool: create, initialise and attach to
 -- the real scroll view. An unattached top-level slot clamps to the screen edge.
 local slot=input:onCreateSlot(1);slot:initialise();scroll:addChild(slot)
 input:onUpdateSlot(slot,info,1,1);slot:setVisible(true)
 assert(getmetatable(slot)==PJCK_ItemSlot and slot.javaObject and slot:getParent()==scroll,
  'real ingredient slot was not instantiated and bound to its scroll view')
 local center=slot:getWidth()/2
 slot:setX(slot:getX()+slot:getMouseX()-center)
 slot:setY(slot:getY()+slot:getMouseY()-center)
 local geometry={width=slot:getWidth(),height=slot:getHeight(),x=slot:getX(),y=slot:getY(),
  absoluteX=slot:getAbsoluteX(),absoluteY=slot:getAbsoluteY(),mouseX=slot:getMouseX(),mouseY=slot:getMouseY()}
 local inside=geometry.width>0 and geometry.height>=geometry.width and geometry.mouseX>=0
  and geometry.mouseX<geometry.width and geometry.mouseY>=0 and geometry.mouseY<geometry.width
 if not inside then
  scroll:removeChild(slot)
  error('native slot geometry unavailable: width='..tostring(geometry.width)..' height='..tostring(geometry.height)
   ..' mouseX='..tostring(geometry.mouseX)..' mouseY='..tostring(geometry.mouseY))
 end
 -- Native geometry satisfies the source guard; the actual callback and pointer
 -- getters remain untouched. Only this fixture-owned child is removed afterwards.
 local ok,result=pcall(slot.onMouseDoubleClick,slot)
 scroll:removeChild(slot)
 assert(ok,result)
 assert(result,'real Tomato slot double-click did not queue cooking')
 return geometry
end
function Evolved.dispatchPlusCook(input,info,panel,run)
 local scroll=assert(input.scrollView,'real ingredient slot scroll view missing')
 local slot=input:onCreateSlot(1);slot:initialise();scroll:addChild(slot)
 input:onUpdateSlot(slot,info,1,1);slot:setVisible(true)
 assert(getmetatable(slot)==PJCK_ItemSlot and slot.javaObject and slot:getParent()==scroll,'real plus slot was not attached')
 local basePanel=assert(panel.baseItemPanel,'real base item panel missing')
 assert(getmetatable(basePanel)==PJCK_BaseItem and basePanel.EvoPanel==panel,'real base item panel differs')
 local add,cook=slot.onAddButton,basePanel.onCook
 assert(add==PJCK_ItemSlot.onAddButton and cook==PJCK_BaseItem.onCook,'real plus/Cook callback identity differs')
 assert(basePanel.cookButton.onclick==cook and basePanel.cookButton.target==basePanel,'real Cook button callback differs')
 assert(#panel:getPreCookItems()==0,'plus fixture inherited selected ingredients')
 local before=#queue(run.player).queue
 local geometry={width=slot:getWidth(),height=slot:getHeight(),x=slot:getX(),y=slot:getY(),
  absoluteX=slot:getAbsoluteX(),absoluteY=slot:getAbsoluteY()}
 local ok,problem=pcall(add,slot)
 scroll:removeChild(slot)
 assert(ok,problem)
 local selected=panel:getPreCookItems();assert(#selected==1,'real plus did not select exactly one logical use')
 local request=selected[1]
 assert(request.groupKey==info.groupKey and request.panelType=='Ingredient'and request.recipeCompatible==true
  and request.recipeUse==10 and request.displayItem and request.displayItem:getID()==run.ids.ingredient.id,
  'real plus changed its selected ingredient request contract')
 assert(#queue(run.player).queue==before,'real plus unexpectedly queued physical cooking work')
 assert(basePanel.updateButtonsVisibility==PJCK_BaseItem.updateButtonsVisibility,'real Cook visibility callback differs')
 basePanel:updateButtonsVisibility()
 assert(basePanel.cookButton:getIsVisible()and basePanel.cookButton.enable,'real Cook button is unavailable after plus')
 run.plusCook={addCallback=tostring(add),cookCallback=tostring(cook),selectedCount=#selected,
  groupKey=request.groupKey,displayItemId=request.displayItem:getID(),recipeUse=request.recipeUse,
  baseItemHandling=PJCK_Config.get().baseItemHandling,cookButtonVisible=basePanel.cookButton:getIsVisible(),
  cookButtonEnabled=basePanel.cookButton.enable,plusTimestampMs=getTimestampMs()}
 run.plusCallback=add;run.cookCallback=cook;run.baseCookPanel=basePanel
 run.plusCook.cookTimestampMs=getTimestampMs()
 cook(basePanel)
 assert(slot.onAddButton==add and basePanel.onCook==cook and basePanel.cookButton.onclick==cook,
  'real plus/Cook callbacks changed during dispatch')
 assert(#panel:getPreCookItems()==0,'real Cook did not consume its logical selection')
 return geometry
end
function Evolved.start(player,state,ids,enabled)
 local run={player=player,state=state,ids=ids,enabled=enabled,actions={},seen={},progress={},durations={},snapshots={}}
 run.floor=ids.case=='cook-water-stew-floor-plus'
 run.buttons=run.floor
 run.water=waterCase(ids.case);run.beans=ids.case=='cook-water-stew-beans'or run.buttons
 run.world=ids.case=='cook-water-soup-world'or run.beans
 if run.beans then run.ingredientTransfers={};run.observedIngredientTransfers={}end
 run.outputType=dishType(ids.case);run.inputObservations={};run.observedWaits={}
 if run.buttons then
  assert(ids.inputDispatch=='plus-cook','plus/Cook authority descriptor differs')
  run.baseTransferTrace={events={},actions={},progress=false};run.baseTransferActions={};run.baseTransferMethods={}
  if run.floor then
   run.floorObservations={};local _,world=BaseFixture.resolveWorldBase(ids.base.world)
   run.originalBaseWorld=assert(world,'actual original floor Pot world object missing')
  end
 end
 run.previousSetting=PJCK_Config.get().baseItemHandling
 PJCK_Config.get().baseItemHandling=run.water and 'keep_inventory'or 'return_source'
 assert(PJCK_Config.shouldReturnBaseItemToSource()==not run.water,'evolved in-memory base handling setting did not apply')
 assert(not PJCK_CookingUI.IsWindowOpen(player:getPlayerNum()),'evolved fixture inherited a registered cooking window')
 PJCK_CookingUI.OnOpenPanel(player)
 run.window=assert(PJCK_CookingUI.GetWindowInstance(player:getPlayerNum()),'native cooking window registration missing')
 run.window:switchToPanel('evolved')
 local panel=assert(run.window.EvoPanel,'Project Cook real EvoPanel missing');run.panel=panel
 assert(getmetatable(panel)==PJCK_EvoPanel,'evolved panel replaced')
 assert(PZSurvivorToolkit.ActionQueueCompat.isInstalled('Project_Cook'),'evolved source adapter is not verified')
 panel:setContainers(state.containers)
 local base=assert(state.base or state.root:getItemById(ids.base.id));run.originalBase=base
 if run.world then
  local source=visibleSource(run)
  assert(base:getContainer()==source and source:getItemById(ids.base.id)==base
   and sourceCount(source,ids.base.id)==1 and sourceCount(state.root,ids.base.id)==0,'world base must start once in its native stove')
 end
 if run.baseTransferTrace then run.baseTransferTrace.selectionTimestampMs=getTimestampMs()end
 panel:setBaseItem(base)
 run.sourceDeferred=base:getContainer()==(run.water and state.root or state.root:getItemById(ids.bags[1]):getItemContainer())and #queue(player).queue==0
 if run.world then
  run.sourceDeferred=false
  for _,action in ipairs(queue(player).queue)do
   if action.Type=='ISInventoryTransferAction'and action.item and action.item:getID()==ids.base.id then
    assert(not run.basePickup and action.srcContainer==state.baseSource and action.destContainer==state.root,
     'world base pickup identity or endpoints differ')
    run.basePickup=action
   end
  end
  assert(run.basePickup,'real panel:setBaseItem did not queue native world base pickup')
  if run.baseTransferTrace then
   run.baseTransferTrace.queuedTimestampMs=getTimestampMs()
   run.baseTransferTrace.initialPendingUntil=panel.pendingBaseItemTransferUntil
   observeBaseTransfer(run,'base-pickup-queued')
  end
 else assert(run.sourceDeferred,'evolved selection unexpectedly moved the base before cooking')end
 local recipes=assert(panel:getRecipes(base));local recipe
 for i=0,recipes:size()-1 do
  local candidate=recipes:get(i);local result=candidate:getResultItem()
  if result==run.outputType or 'Base.'..result==run.outputType then assert(not recipe,'ambiguous real evolved recipe');recipe=candidate end
 end
 assert(recipe,'real evolved recipe unavailable: '..run.outputType);run.recipe=recipe
 panel:setRecipe(recipe)
 if run.world then
  run.originalIngredient=assert(BaseFixture.resolveIngredient(state.root,ids.ingredient))
  run.waitingForBase=true;run.basePickupDeadline=getTimestampMs()+30000
  observeInputs(run,'base-pickup-queued')
  return run
 end
 return Evolved.continueStart(run)
end
function Evolved.continueStart(run)
 if run.dispatched then return run end
 local player,state,ids,enabled=run.player,run.state,run.ids,run.enabled
 local panel,recipe=run.panel,run.recipe
 if run.waitingForBase then
  if run.floor then Evolved.observe(run)end
  assert(getTimestampMs()<=run.basePickupDeadline,'native world base pickup did not become idle')
  if #queue(player).queue>0 or player:hasTimedActions()then return run end
  local source=visibleSource(run)
  local live=state.root:getItemById(ids.base.id)
  if not live or live:getContainer()~=state.root or sourceCount(state.root,ids.base.id)~=1 or sourceCount(source,ids.base.id)~=0 then
   if not run.waitingReplicationObserved then
    run.waitingReplicationObserved=true;observeInputs(run,'base-pickup-awaiting-root')
   end
   return run
  end
  assert(live:getFullType()==ids.base.kind,'native world base pickup changed pot type')
  run.waitingForBase=false
  observeInputs(run,'base-pickup-idle')
 end
 -- Keep the panel's original selected reference. The native source is responsible
 -- for resolving a post-transfer replica; this fixture never rebinds panel.baseItem.
 local base=assert(panel:getBaseItem(),'native panel lost selected base after pickup')
 panel:getInputList('Ingredient');panel:getInputList('Seasoning')
 local ingredient,ingredientSource=BaseFixture.resolveIngredient(state.root,ids.ingredient)
 assert(ingredient,'declared evolved ingredient is missing or ambiguous');run.originalIngredient=ingredient
 if run.beans then
  local source=run.floor and state.root:getItemById(ids.bags[2]):getItemContainer()or visibleSource(run)
  assert((run.floor or ingredientSource==source)and ingredient:getFullType()=='Base.DriedWhiteBeans'
   and ingredient:getContainer()==source and sourceCount(source,ids.ingredient.id)==1
   and (run.floor or sourceCount(state.root,ids.ingredient.id)==0),'dry beans must remain in their declared source before the slot callback')
 end
 local spice=assert(state.root:getItemById(ids.spice.id))
 assert(not ingredient:isCooked()and not ingredient:isRotten(),'fixture ingredient is not raw usable food')
 run.recipeUse=recipe:getItemRecipe(ingredient):getUse()
 assert(run.recipeUse==(run.beans and 10 or run.water and 12 or 6)and recipe:getItemRecipe(spice):getUse()==1,
  'native evolved portion definitions differ')
 if run.water then
  local fluid=assert(base:getFluidContainerFromSelfOrWorldItem(),'water pot lost native fluid component')
  assert(not instanceof(base,'Food')and fluid:isPureFluid(Fluid.Water)
   and math.abs(fluid:getCapacity()-ids.base.fluidCapacity)<0.00001
   and math.abs(fluid:getAmount()-ids.base.waterAmount)<0.00001,'water pot changed before native recipe dispatch')
  local containers=run.world and select(2,visibleSource(run))or state.containers
  local liveBase=run.world and assert(state.root:getItemById(ids.base.id))or base
  local available=recipe:getItemsCanBeUse(player,liveBase,containers)
  assert(available and available:contains(ingredient),'native water recipe rejected the exact raw ingredient')
  local input=assert(panel.ingredientsPanel,'real evolved ingredient input panel missing')
  local info
  for _,entry in ipairs(panel:getInputList('Ingredient'))do
   if entry.item and entry.item:getID()==ingredient:getID()then assert(not info,'ambiguous real ingredient slot');info=entry end
  end
  if not info or info.isPossible==true then
   observeInputs(run,'missing-ingredient-slot')
   print('[CRAFT_UI_TEST] INPUT_UNAVAILABLE '..require('QueueHealthEvents').encode(run.inputObservations[#run.inputObservations]))
  end
  assert(info and info.isPossible~=true,'real usable ingredient slot missing')
  if run.beans then observeInputs(run,'world-ingredient-before-slot')end
  local beforeCommands
  if run.buttons then
   beforeCommands={};for _,action in ipairs(queue(player).queue)do beforeCommands[action]=true end
   assert(run.basePickup and run.basePickup.destContainer==state.root and not run.waitingForBase,
    'real plus/Cook dispatch must follow completed native Pot pickup')
   run.baseTransferTrace.slotTimestampMs=getTimestampMs();observeBaseTransfer(run,'real-slot-dispatch')
  end
  if run.buttons then run.slotGeometry=Evolved.dispatchPlusCook(input,info,panel,run)
  else run.slotGeometry=Evolved.dispatchWaterSlot(input,info)end
  if run.buttons then
   for _,action in ipairs(queue(player).queue)do
    local args=action.Type=='ISQueueActionsAction'and action.args
    if not beforeCommands[action]and args and args[1]and args[1].panel==panel and args[2]and args[2].groupKey then
     if run.command then
      assert(run.command.args[1]==args[1]and run.command.args[2]==args[2],
       'unrelated newly queued cooking source commands')
     else run.command=action end
    end
   end
   assert(run.command,'real slot did not create a new source sequence')
  end
  assert(panel:getRecipe()==recipe and info.item:getID()==ingredient:getID(),'native slot changed selected recipe or ingredient')
  run.dispatchMethod=run.buttons and 'PJCK_ItemSlot.onAddButton+PJCK_BaseItem.onCook'or 'PJCK_ItemSlot.onMouseDoubleClick'
 else
  panel:addIngredients({ingredient,spice},recipe,base)
 end
 observeInputs(run,'queued')
 run.command=run.command or assert(queue(player).queue[1],'real EvoPanel did not queue cooking')
 run.tail=ISReadABook:new(player,state.book)
 assert(run.tail.minutesPerPage==2.0 and run.tail.maxTime>1,'evolved reader duration changed')
 ISTimedActionQueue.add(run.tail)
 if enabled then assert(run.command.toolkitQueueOperation and run.tail.toolkitQueueOperation~=run.command.toolkitQueueOperation,
  'evolved reader operation not independent')end
 run.dispatched=true
 return run
end
function Evolved.observe(run)
 local q=queue(run.player)
 observeBaseTransfer(run)
 if run.buttons then
  for _,action in ipairs(q.queue)do
   local item=action.item
   if action.Type=='ISInventoryTransferAction'and item and (item:getID()==run.ids.base.id or item:getFullType()==run.outputType)then
    local record=run.baseTransferActions[action]
    if not record then
     local function callback(value)
      if type(value)~='function'then return {missing=true}end
      local ok,source=pcall(getFilenameOfClosure,value)
      return {identity=tostring(value),source=ok and source or 'unavailable'}
     end
     local _,behavior=PZSurvivorToolkit.ActionQueueDefinitions.inspect(action)
     record={id=item:getID(),kind=item:getFullType(),firstObservedTimestampMs=getTimestampMs(),
      sourceType=action.srcContainer and action.srcContainer:getType()or 'nil',
      destinationType=action.destContainer and action.destContainer:getType()or 'nil',
      sourceIsRoot=action.srcContainer==run.state.root,destinationIsRoot=action.destContainer==run.state.root,
      callbackAtFirstObservation=callback(action.onCompleteFunc),behaviorId=behavior or 'unclassified',
      progress=false,duration=action:getDuration()}
     run.baseTransferActions[action]=record;run.baseTransferTrace.actions[#run.baseTransferTrace.actions+1]=record
     local snapshot={onCompleteFunc=action.onCompleteFunc}
     for _,name in ipairs(methods)do snapshot[name]=action[name]end
     run.baseTransferMethods[action]=snapshot
    end
    if q.current==action and action:isStarted()then
     record.started=true;record.duration=action:getDuration()
     if action:getJobDelta()>0 then record.progress=true end
     if isClient()and action.transactionId and action.transactionId~=0 then
      local paid=getItemTransactionDuration(action.transactionId)
      if paid>1 then record.transactionDuration=paid end
     end
    end
   end
  end
 end
 if run.beans then
  -- Original native constructor arguments expose the source sequence and entry;
  -- retaining them for diagnostics does not replace or invoke their callbacks.
  for _,action in ipairs(q.queue)do
   local args=action.Type=='ISQueueActionsAction'and action.args
   if args and args[1]and args[1].panel==run.panel and args[2]then
    assert(not run.ingredientEntry or run.ingredientEntry==args[2],'dry beans source entry identity changed')
    run.ingredientSequence=args[1];run.ingredientEntry=args[2]
   end
  end
 end
 for _,action in ipairs(q.queue)do
  if run.beans and action.Type=='ISInventoryTransferAction'and action.item and action.item:getID()==run.ids.ingredient.id then
   local record=run.observedIngredientTransfers[action]
   if not record then
    local source=run.floor and run.state.root:getItemById(run.ids.bags[2]):getItemContainer()
     or assert(BaseFixture.resolveBaseSource(run.ids.ingredient.source),'dry beans native source changed')
    record={id=action.item:getID(),pickup=action.srcContainer==source and action.destContainer==run.state.root,
     returned=action.srcContainer==run.state.root and action.destContainer==source,duration=action:getDuration(),progress=false}
    assert(record.pickup or record.returned,'dry beans native transfer endpoints differ')
    run.observedIngredientTransfers[action]=record;run.ingredientTransfers[#run.ingredientTransfers+1]=record
    observeInputs(run,record.pickup and 'world-ingredient-pickup'or 'world-ingredient-return')
   end
   if q.current==action and action:isStarted()and action:getJobDelta()>0 then
    record.progress=true;record.duration=action:getDuration()
    if isClient()and action.transactionId and action.transactionId~=0 then
     local paid=getItemTransactionDuration(action.transactionId)
     if paid>1 then record.transactionDuration=paid end
    end
   end
  end
  if run.water and action.Type=='PJCK_SequenceWaitAction'and not run.observedWaits[action]then
   run.observedWaits[action]=true;observeInputs(run,'sequence-wait')
  end
  if action.Type=='ISAddItemInRecipe'and action.recipe==run.recipe and not run.seen[action]then
   local id=action.usedItem:getID()
   assert(id==run.ids.ingredient.id or not run.water and id==run.ids.spice.id,'evolved selected an unrelated ingredient')
   observeInputs(run,'add-ingredient')
   run.seen[action]=true;run.actions[#run.actions+1]=action
   local duration=action:getDuration()
   assert(duration==100-run.player:getPerkLevel(Perks.Cooking)*2.5 and not run.player:isTimedActionInstant(),
    'evolved action duration changed')
   run.durations[#run.durations+1]=duration
   local snapshot={};for _,name in ipairs(methods)do snapshot[name]=action[name]end
   run.snapshots[action]=snapshot
   if run.enabled then
    assert(action.toolkitQueueOperation==run.command.toolkitQueueOperation and PZSurvivorToolkit.ActionQueueDefinitions.inspect(action),
     'expanded native recipe action lost source grouping or contract')
   end
  end
 end
 local current=q.current
 for i,action in ipairs(run.actions)do
  if current==action and action:isStarted()and action:getJobDelta()>0 then run.progress[i]=true end
 end
 if run.tail and current==run.tail and run.tail:isStarted()and run.tail:getJobDelta()>0 then
  run.tailProgress=true
  if run.returnsBeforeRead==nil then
   local base=run.panel:resolveCurrentBaseItem(true)
   local source=run.state.root:getItemById(run.ids.bags[1]):getItemContainer()
   local ingredient,declaredIngredientSource=BaseFixture.resolveIngredient(run.state.root,run.ids.ingredient)
   local spiceSource=run.state.root:getItemById(run.ids.bags[2]):getItemContainer()
   local ingredientSource=declaredIngredientSource or spiceSource
   local spice=run.state.root:getItemById(run.ids.spice.id)
   local consumed=run.water and run.ids.ingredient.hunger+run.recipeUse/100*(1-0.03*run.ids.cookingLevel)>=-0.0200001
   local resultSource=run.water and run.state.root or source
   run.returnsBeforeRead=base and base:getFullType()==run.outputType and base:getContainer()==resultSource
    and (consumed and not ingredient or not consumed and ingredient and ingredient:getContainer()==ingredientSource)
    and (run.water and spice and spice:getContainer()==spiceSource or not run.water and not spice)or false
   observeInputs(run,'independent-tail')
  end
 end
end
function Evolved.finish(run,authority)
 observeBaseTransfer(run,'finish')
 local unchanged=true;local inputs,progress={},{}
 for i,action in ipairs(run.actions)do
  inputs[i]=action.usedItem:getID()
  if run.progress[i]then progress[#progress+1]=i end
  for _,name in ipairs(methods)do if action[name]~=run.snapshots[action][name]then unchanged=false end end
 end
 local selected=run.panel:resolveCurrentBaseItem(true)
 local dish=authority.dishes[1]
 local expectedHunger=run.ids.ingredient.hunger+run.recipeUse/100*(1-0.03*run.ids.cookingLevel)
 local consumed=run.water and expectedHunger>=-0.0200001
 local expected=authority.outputs==1 and authority.base.totalCount==0 and authority.spice.totalCount==(run.water and 1 or 0)
  and authority.ingredient.totalCount==(consumed and 0 or 1)and authority.ingredient.sourceCount==(consumed and 0 or 1)
  and math.abs(authority.ingredient.hunger-(consumed and 0 or expectedHunger))<0.00001
  and dish and dish.kind==run.outputType and dish.sourceCount==(run.water and 0 or 1)and dish.totalCount==1
  and #dish.extras==1 and dish.extras[1]==run.ids.ingredient.kind
  and (run.water and dish.rootCount==1 and #dish.spices==0 and authority.spice.sourceCount==1
   and math.abs(authority.spice.hunger-run.ids.spice.hunger)<0.00001
   or not run.water and #dish.spices==1 and dish.spices[1]=='Base.Pepper')
 if run.floor then expected=expected and authority.base.rootCount==0 and authority.base.worldCount==0
 elseif run.world then expected=expected and authority.base.rootCount==0 and authority.base.sourceCount==0
  and authority.base.sourceItemCount==(run.beans and 1 or 0)end
 if run.beans then expected=expected and #run.actions==1 and run.progress[1]==true
  and authority.ingredient.rootCount==0 and authority.ingredient.kind=='Base.DriedWhiteBeans'
  and #run.ingredientTransfers==2 and run.ingredientTransfers[1].pickup and run.ingredientTransfers[2].returned end
 local reason=not expected and 'native-evolved-effect-differs'or not authority.tailRead and 'native-independent-tail-not-preserved'
  or not run.returnsBeforeRead and 'native-returns-not-before-tail'or nil
 local value={event='case',id=run.ids.case,status=reason and 'failed'or 'passed',reason=reason,
  requested=run.water and 1 or 2,actions=#run.actions,actionInputIds=inputs,progressIds=progress,nativeDurations=values(run.durations),
  cookingLevel=run.player:getPerkLevel(Perks.Cooking),sourceMethodsUnchanged=unchanged,
  callbackClass='PJCK_EvoPanel',sourceDeferred=run.sourceDeferred,sourceVerified=true,tokensGrouped=run.enabled,
  tailIndependent=not run.enabled or run.tail.toolkitQueueOperation~=run.command.toolkitQueueOperation,
  tailProgress=run.tailProgress==true,returnsBeforeRead=run.returnsBeforeRead==true,selectedDishId=selected and selected:getID()or -1}
 if run.water then
  value.dispatchMethod=run.dispatchMethod;value.inputObservations=run.inputObservations
  value.slotGeometry=run.slotGeometry
  value.recipeUse=run.recipeUse;value.waterAmount=run.ids.base.waterAmount;value.fluidCapacity=run.ids.base.fluidCapacity
 end
 if run.world then value.basePickupNative=true;value.originalBaseSource=run.ids.base.source end
 if run.beans then value.ingredientTransfers=run.ingredientTransfers;value.originalIngredientSource=run.ids.ingredient.source end
 if run.buttons then
  value.plusButtonNative=run.plusCallback==PJCK_ItemSlot.onAddButton
  value.cookButtonNative=run.cookCallback==PJCK_BaseItem.onCook and run.baseCookPanel.cookButton.onclick==run.cookCallback
  value.preCookRequests=run.plusCook.selectedCount;value.plusCook=run.plusCook;value.baseTransferTrace=run.baseTransferTrace
  for action,record in pairs(run.baseTransferActions)do
   local snapshot=run.baseTransferMethods[action];record.sourceMethodsUnchanged=true
   for _,name in ipairs(methods)do if snapshot[name]~=action[name]then record.sourceMethodsUnchanged=false end end
   record.onCompleteUnchanged=snapshot.onCompleteFunc==action.onCompleteFunc
  end
 end
 if run.floor then
  value.originalBaseWorld=run.ids.base.world;value.floorObservations=run.floorObservations
 end
 for key,entry in pairs(authority)do if key~='case'then value[key]=entry end end
 PJCK_Config.get().baseItemHandling=run.previousSetting
 run.window:onCloseClick()
 assert(not PJCK_CookingUI.IsWindowOpen(run.player:getPlayerNum()),'evolved cooking window registration leaked')
 return value,reason
end
return Evolved
