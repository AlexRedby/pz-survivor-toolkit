-- Observe native row-build counters and timed actions without replacing any
-- class methods, instance methods or InventoryRefresh's pane gate.
require 'TimedActions/ISInventoryTransferUtil'
require 'TimedActions/WalkToTimedAction'
local Proximity=require 'BetterContainers/Proximity'
local Model=require 'PZSurvivorToolkit/ManifestModel'
local InventoryCategory=require 'BetterContainers/Categorize/InventoryCategory'
local N={}
local methodNames={'new','start','update','perform','complete','stop','getDuration','isValid','isValidStart','onStartFunc','onCompleteFunc','onCancelFunc','onStartTarget','onCompleteTarget','onCancelTarget'}
local function sortedKeys(values)local out={};for id in pairs(values)do out[#out+1]=id end;table.sort(out);return out end
local function sameIds(a,b)if #a~=#b then return false end;for i,id in ipairs(a)do if id~=b[i]then return false end end;return true end
function N.queue(player)return ISTimedActionQueue.getTimedActionQueue(player)end
function N.idle(player)return #N.queue(player).queue==0 and not player:hasTimedActions()end
function N.ids(container)local out={};for i=0,container:getItems():size()-1 do out[#out+1]=container:getItems():get(i):getID()end;table.sort(out);return out end
local function nativeBuilds(pane)
 -- Both installed native pane implementations increment this only after an
 -- actual details rebuild (and reset above 10000). Sparse functional phases
 -- must remain below that reset boundary; a reset cannot pass a reopen gate.
 local value=pane.refreshContainerCount
 assert(type(value)=='number'and value>=0 and value<=10000,'native pane row-build counter unavailable')
 return value
end
function N.startObservation(player,phase)
 local run={player=player,phase=phase,records={},actions={},owned={}}
 for _,entry in ipairs(phase.items)do run.owned[entry.id]=true end
 nativeBuilds(getPlayerLoot(player:getPlayerNum()).inventoryPane)
 return run
end
local function endpoint(run,container)
 if container==run.player:getInventory()then return run.player:getUsername()end
 for i,c in ipairs(run.state.stores)do if c==container then return 'crate'..i end end
 return container and container:getType()or 'none'
end
function N.remember(run,action)
 if run.actions[action]then return end
 local record={type=action.Type,step=run.step,progressSamples=0,duration=action:getDuration(),methods={}}
 for _,key in ipairs(methodNames)do record.methods[key]=action[key]end
 if action.item then
  record.id=action.item:getID();record.ft=action.item:getFullType();record.source=endpoint(run,action.srcContainer);record.destination=endpoint(run,action.destContainer)
 end
 if action.craftRecipe then record.recipe=action.craftRecipe:getName()end
 run.actions[action]=record;run.records[#run.records+1]=record
end
function N.observe(run)
 local q=N.queue(run.player)
 for _,action in ipairs(q.queue)do
  if action.Type=='ISInventoryTransferAction'then
   assert(action.item and run.owned[action.item:getID()],'native warehouse action selected an unowned item');N.remember(run,action)
  elseif action.Type=='ISHandcraftAction'then
   assert(action.craftRecipe==run.recipe,'native warehouse action selected another recipe');N.remember(run,action)
  elseif action.Type=='ISWalkToTimedAction'then N.remember(run,action)
  else error('unexpected native warehouse timed action: '..tostring(action.Type))end
 end
 for action,record in pairs(run.actions)do
  for _,key in ipairs(methodNames)do assert(action[key]==record.methods[key],'native warehouse action callback changed: '..key)end
  if q.current==action and action:isStarted()then
   record.started=true;if action:getJobDelta()>0 then record.progressSamples=record.progressSamples+1 end
   if action.transactionId and action.transactionId~=0 then
    record.transactionId=action.transactionId;local duration=getItemTransactionDuration(action.transactionId)
    if duration>0 then record.transactionDuration=duration end
   end
  end
 end
end
function N.actionProof(run)
 N.observe(run);local out={};for _,record in ipairs(run.records)do
  local value={};for key,v in pairs(record)do if key~='methods'then value[key]=v end end
  value.sourceMethodsUnchanged=true;out[#out+1]=value
 end;return out
end
function N.walk(run,x,y,z)
 local square=assert(getCell():getGridSquare(x,y,z),'native walk square unavailable')
 assert(square:canStand()and square:isFree(false),'native warehouse aisle blocked')
 local action=ISWalkToTimedAction:new(run.player,square);ISTimedActionQueue.add(action);N.remember(run,action);return action
end
function N.transfer(run,id,from,to)
 local item=assert(from:getItemById(id),'native source identity missing')
 assert(run.owned[id]and item:getContainer()==from,'native transfer selected a foreign identity')
 local physical=from==run.player:getInventory()and to or from;local object=physical:getParent()
 assert(object and luautils.walkAdj(run.player,object:getSquare()),'native transfer approach failed')
 local action=assert(ISInventoryTransferUtil.newInventoryTransferAction(run.player,item,from,to,nil))
 action:setAllowMissingItems(false);ISTimedActionQueue.add(action);N.remember(run,action);return action
end
function N.craft(run)
 local player=run.player;local num=player:getPlayerNum();local input=assert(run.state.stores[4]:getItemById(run.phase.craftInputId))
 assert(input:getFullType()=='Base.HotdogPack','native crafting input changed')
 local old=ISEntityUI.GetWindowInstance(num,'HandcraftWindow')
 assert(not old,'unrelated native craft window already exists')
 local recipe=assert(getScriptManager():getCraftRecipe('OpenHotdogPack'));run.recipe=recipe
 assert(recipe:getInputs():size()==1,'native OpenHotdogPack input contract changed')
 ISEntityUI.OpenHandcraftWindow(player,nil,nil,true,recipe)
 local window=assert(ISEntityUI.GetWindowInstance(num,'HandcraftWindow'));run.craftWindow=window
 local panel=assert(window.HandCraftPanel or window.handCraftPanel);local logic=panel.logic
 local containers=ISInventoryPaneContextMenu.getContainers(player);local found=false
 for i=0,containers:size()-1 do if containers:get(i)==run.state.stores[4]then found=true end end
 assert(found,'native material collection omitted the exact shared craft crate')
 logic:setContainers(containers);logic:setRecipe(recipe);logic:setManualSelectInputs(true);logic:clearManualInputs()
 local selected=ArrayList.new();selected:add(input)
 assert(logic:setManualInputsFor(recipe:getInputs():get(0),selected),'native material selection rejected the exact HotdogPack')
 assert(logic:canPerformCurrentRecipe(),'native OpenHotdogPack eligibility failed')
 local materials=logic:getRecipeData():getAllInputItems();local selectedId=false
 for i=0,materials:size()-1 do if materials:get(i):getID()==run.phase.craftInputId then selectedId=true end end
 assert(selectedId,'native recipe data omitted the declared input ID')
 local owner=panel.craftActionPanel or panel.recipePanel and panel.recipePanel.craftControl
 assert(owner,'installed native craft control absent')
 local button=owner.craftButton or owner.buttonCraft;assert(button and button.target==owner and type(button.onclick)=='function','installed craft button binding differs')
 if owner.quantityInput then owner.quantityInput:setText('1');owner:updateCraftAction()
 else owner:setCraftQuantity(1);owner:prerender()end
 assert(not player:isTimedActionInstant(),'native action timing is instant')
 run.craftDispatch={inputId=input:getID(),source='crate4',nativeMaterials=true,recipe='OpenHotdogPack',outputType='Base.Hotdog_single',outputCount=4,recipeTime=recipe:getTime(player),nativeDuration=recipe:getTime(player)*5,callback=tostring(button.onclick)}
 button:forceClick();N.observe(run)
 local count=0;for action,record in pairs(run.actions)do if record.step==run.step and action.Type=='ISHandcraftAction'then
  count=count+1;assert(action.craftRecipe==recipe and action:getDuration()==recipe:getTime(player)*5,'native OpenHotdogPack duration/recipe changed')
  assert(action.onStartTarget==owner and action.onCompleteTarget==owner,'native craft callback owner changed')
 end end
 assert(count==1,'native craft button did not queue exactly one handcraft action')
end
function N.closeCraft(run)
 if not run.craftWindow then return end
 assert(N.idle(run.player),'native craft actions still running')
 local window=run.craftWindow
 if window.close then window:close()elseif window.onClose then window:onClose()else error('native craft window has no close callback')end
 run.craftWindow=nil
end
function N.aggregate(player)
 return Proximity.GetItemContainer(player:getPlayerNum())
end
function N.selectAggregate(player)
 local loot=getPlayerLoot(player:getPlayerNum());local target=N.aggregate(player)
 for _,button in ipairs(loot.backpacks or {})do if button.inventory==target then loot:onBackpackClick(button);return loot end end
 return nil
end
function N.hidden(run)
 local loot=getPlayerLoot(run.player:getPlayerNum());local pane=loot.inventoryPane;local state=loot.toolkitRefreshState or {}
 return {visible=loot:getIsVisible(),rowsPending=state.rowsPending==true,countPending=state.countPending==true,tooltipsPending=state.tooltipsPending==true,
  nativeBuilds=nativeBuilds(pane),nativeRefreshCount=nativeBuilds(pane),rawAggregateIds=N.ids(N.aggregate(run.player)),selectedContainerIds=N.ids(pane.inventory)}
end
function N.hide(run)
 local loot=getPlayerLoot(run.player:getPlayerNum());local pane=loot.inventoryPane
 pane.selected={};pane.firstSelect=nil;pane.doController=nil;pane.joyfocus=nil;loot.joyfocus=nil;loot.mouseOverButton=nil
 loot:setVisible(false);loot:refreshBackpacks()
 local snapshot=N.hidden(run)
 assert(not snapshot.visible and snapshot.rowsPending,'hidden native details did not enter deferred state');return snapshot
end
function N.reopen(run,preOpen)
 -- Selection is deliberately after the pre-open membership proof. Opening or
 -- selecting a button may perform native discovery and cannot prove propagation.
 assert(preOpen and preOpen.nativeAggregate and sameIds(preOpen.actualIds,preOpen.expectedIds)
  and sameIds(preOpen.actualIds,N.ids(N.aggregate(run.player))),'pre-open native aggregate proof missing or changed')
 local loot=getPlayerLoot(run.player:getPlayerNum());local before=N.hidden(run);loot:setVisible(true)
 local selectedKind=run.step=='hidden-loot'and'crate5'or'aggregate'
 local target=selectedKind=='crate5'and run.state.stores[5]or N.aggregate(run.player);local button
 for _,entry in ipairs(loot.backpacks or {})do if entry.inventory==target then assert(not button,'duplicate native reopen target button');button=entry end end
 assert(button and button.target==loot and type(button.onclick)=='function','intended native reopen target button unavailable')
 local callback=button.onclick;callback(button.target,button)
 assert(button.onclick==callback and button.inventory==target,'native reopen target callback/binding changed')
 assert(loot.inventory==target and loot.inventoryPane.inventory==target,'native reopen selected another container')
 local pane=loot.inventoryPane;local pending=loot.toolkitRefreshState
 assert(not pending or not pending.rowsPending and not pending.countPending and not pending.tooltipsPending,'native reopen left pending presentation')
 local physical={};for i=0,pane.inventory:getItems():size()-1 do local item=pane.inventory:getItems():get(i);physical[item:getID()]=item end
 local rows={};local groups={}
 for _,group in ipairs(pane.itemslist or {})do local groupIds,itemCategories={},{};local seen={};local rawCategory,expectedGroupCategory
  for _,item in ipairs(group.items or {})do
   local id=item:getID();assert(physical[id]and item==physical[id],'reopened native row contains a stale/foreign physical item')
   if not seen[id]then
    seen[id]=true;assert(not rows[id],'reopened native row duplicates an item across groups');rows[id]=true;groupIds[#groupIds+1]=id
    local meta=assert(Model.item(item));local raw=item:getDisplayCategory()or item:getCategory();local resolved=InventoryCategory.get(item)
    local detail=' id='..tostring(id)..' type='..tostring(item:getFullType())..' group='..tostring(group.name)
     ..' observedGroup='..tostring(group.cat)..' displayCategory='..tostring(item:getDisplayCategory())..' nativeCategory='..tostring(item:getCategory())
     ..' modelCategory='..tostring(meta.cat)..' resolvedCategory='..tostring(resolved)
    -- BC's row decorator owns its sorting/compatibility category independently
    -- of the physical item's raw display-category identity.
    assert(meta.cat==raw,'reopened model/native category differs'..detail)
    assert(group.cat==resolved,'reopened native group category differs'..detail)
    assert(rawCategory==nil or rawCategory==raw,'reopened native group mixes raw categories'..detail)
    assert(expectedGroupCategory==nil or expectedGroupCategory==resolved,'reopened native group mixes resolved categories'..detail)
    rawCategory=raw;expectedGroupCategory=resolved
    itemCategories[#itemCategories+1]={id=id,rawCategory=raw,modelCategory=meta.cat,resolvedCategory=resolved}
   end
  end
  assert(group.count==#groupIds+1,'reopened native stack count differs')
  if group.realCount~=nil then assert(group.realCount==#groupIds,'reopened CleanUI physical stack count differs')end
  table.sort(groupIds);table.sort(itemCategories,function(a,b)return a.id<b.id end)
  groups[#groups+1]={name=group.name,category=rawCategory,groupCategory=group.cat,expectedGroupCategory=expectedGroupCategory,
   rawLocalizedCategory=rawCategory and getText('IGUI_ItemCat_'..rawCategory),itemCategories=itemCategories,ids=groupIds,count=#groupIds,nativeCount=group.count,realCount=group.realCount}
 end
 local expected=N.ids(pane.inventory);local actual=sortedKeys(rows)
 assert(sameIds(actual,expected),'native reopened row IDs/count differ from live selected inventory')
 local count=luautils.countItemsRecursive({luautils.findRootInventory(pane.inventory)})
 assert(loot.totalItems==count,'native reopened title count differs')
 if before.rowsPending then assert(nativeBuilds(pane)>before.nativeBuilds,'native reopen did not run the installed class row builder')end
 return {nativeRows=true,selectedBound=true,selectedKind=selectedKind,rowIds=actual,containerIds=expected,totalItems=loot.totalItems,expectedTotal=count,groups=groups,before=before,after=N.hidden(run)}
end
function N.diagnostics(run)
 local loot=getPlayerLoot(run.player:getPlayerNum());local pane=loot.inventoryPane;local refresh=loot.toolkitRefreshState or {}
 local row={nativeRefreshCount=nativeBuilds(pane),visible=loot:getIsVisible(),rowsPending=refresh.rowsPending==true,
  countPending=refresh.countPending==true,tooltipsPending=refresh.tooltipsPending==true,
  selectedType=pane.inventory and pane.inventory:getType(),selectedIds=pane.inventory and N.ids(pane.inventory)or {},
  aggregateIds=N.ids(N.aggregate(run.player)),paneClass=tostring(getmetatable(pane).Type),
  classRefresh=tostring(getmetatable(pane).refreshContainer),paneRefresh=tostring(pane.refreshContainer),buttons={}}
 for i,button in ipairs(loot.backpacks or {})do local container=button.inventory;local slot
  for j,owned in ipairs(run.state.stores)do if container==owned then slot=j end end
  row.buttons[#row.buttons+1]={index=i,type=container and container:getType(),ownedSlot=slot,itemIds=container and N.ids(container)or {}}
 end
 return row
end
function N.aggregateProof(run)
 local loot=getPlayerLoot(run.player:getPlayerNum());local physical={};local slots={};local expected={}
 for _,button in ipairs(loot.backpacks or {})do
  for i,container in ipairs(run.state.stores)do if button.inventory==container and not physical[container]then
   physical[container]=true;slots[#slots+1]=i
   for j=0,container:getItems():size()-1 do expected[container:getItems():get(j):getID()]=true end
  end end
 end
 local aggregate=N.aggregate(run.player);local actual=N.ids(aggregate);local expectedIds=sortedKeys(expected)
 if not sameIds(actual,expectedIds)then return nil end
 local identities={}
 for i=0,aggregate:getItems():size()-1 do local item=aggregate:getItems():get(i);local id=item:getID()
  assert(physical[item:getContainer()],'native aggregate item lost its physical discovered source')
  local meta=assert(Model.item(item));identities[#identities+1]={id=id,key=meta.key,cat=meta.cat}
 end
 table.sort(slots);table.sort(identities,function(a,b)return a.id<b.id end)
 return {nativeAggregate=true,actualIds=actual,expectedIds=expectedIds,discoveredSlots=slots,identities=identities}
end
function N.quick(run)
 local loot=getPlayerLoot(run.player:getPlayerNum());assert(not loot:getIsVisible(),'quick transfer requires the observer loot page hidden')
 assert(loot.inventoryPane.inventory==run.state.stores[5],'hidden quick transfer lost its physical crate binding')
 local button,callback
 if run.phase.mode=='clean'then
  button=assert(loot.transferByNameButton,'installed CleanUI quick-transfer button missing');callback='ISInventoryPage.onTransferByNameClick'
  assert(button.target==loot and button.onclick==loot.onTransferByNameClick,'installed CleanUI quick-transfer callback differs')
 else
  button=assert(loot.lootAll,'installed vanilla Loot All button missing');callback='ISInventoryPage.lootAll'
  assert(button.target==loot and button.onclick==getmetatable(loot).lootAll,'installed vanilla Loot All callback differs')
 end
 local before=N.hidden(run);button.onclick(button.target,button);assert(not loot:getIsVisible(),'quick transfer exposed loot page')
 N.observe(run);local count=0
 for action,record in pairs(run.actions)do if record.step=='hidden-loot'and action.Type=='ISInventoryTransferAction'then
  assert(action.item:getID()==run.phase.quickId and action.srcContainer==run.state.stores[5]and action.destContainer==run.player:getInventory(),'hidden quick transfer selected wrong identity/endpoint');count=count+1
 end end
 assert(count==1,'installed hidden quick callback did not queue one exact item')
 return {callback=callback,installedButton=true,hiddenBefore=not before.visible,hiddenAfter=not loot:getIsVisible(),id=run.phase.quickId,source='crate5',destination='client1'}
end
N.sameIds=sameIds
return N
