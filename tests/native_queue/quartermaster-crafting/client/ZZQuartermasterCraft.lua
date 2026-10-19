require 'PZSurvivorToolkit/ActionQueuePanel'
require 'ISUI/Crafting/ISHandcraftWindow'
require 'Neat_Crafting/NC_CraftActionPanel'
local Fixture=require 'QueueQuartermasterCraftFixture'
local config=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local step,phase,since,idle=1,'prepare',0,0
local started,done=false,false
local ids,state,authorityState,previous,receipt,position,window,owner,logic,craft,designatedAt,cleanupRetry
local walked,picked,crafted,notNearby,injected=false,false,false,false,false
local toolPickup,toolReturn={},{}
local function case()return config.cases[step]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function sorted(set)local out={};for id in pairs(set)do out[#out+1]=id end;table.sort(out);return out end
local function emit(value)
 value.suite='quartermaster-crafting';value.kind=config.kind;value.mode=config.mode;value.actor='client1';JSON.emit(value)
end
local function request(command)
 if isClient()then sendClientCommand('QuartermasterCraftTest',command,{case=case(),position=position})
 elseif command=='Prepare'then
  authorityState=Fixture.prepare(getPlayer(),case(),position,previous);previous=nil;ids=Fixture.descriptor(authorityState)
  print('[QM_CRAFT] PREPARED '..JSON.encode(ids))
 else
  receipt=assert(Fixture.verify(authorityState));print('[QM_CRAFT] VERIFIED '..JSON.encode(receipt));Fixture.cleanup(authorityState)
 end
end
Events.OnServerCommand.Add(function(module,command,value)
 if module~='QuartermasterCraftTest'then return end
 assert(command~='Failed',value.error)
 if command=='Prepared'then ids=value elseif command=='Verified'then receipt=value end
end)
local function sourceIn(containers)
 for i=0,containers:size()-1 do if containers:get(i)==state.source then return true end end
 return false
end
local function open(player)
 local recipe=assert(getScriptManager():getCraftRecipe('QueueBorrowedTools'))
 if case()=='vanilla'then
  window=ISXuiSkin.build(XuiManager.GetDefaultSkin(),'HandcraftWindow',ISHandcraftWindow,20,20,900,600,player,nil,'InHandCraft')
  window:initialise();window:instantiate();window:addToUIManager()
  local panel=assert(window.handCraftPanel);logic=panel.logic;owner=assert(panel.recipePanel.craftControl)
  assert(getmetatable(owner)==ISWidgetHandCraftControl,'vanilla craft owner replaced')
 else
  ISEntityUI.OpenHandcraftWindow(player,nil,'InHandCraft',true,recipe)
  window=assert(ISEntityUI.GetWindowInstance(player:getPlayerNum(),'HandcraftWindow'))
  local panel=assert(window.HandCraftPanel or window.handCraftPanel);logic=panel.logic;owner=assert(panel.craftActionPanel)
  assert(getmetatable(owner)==NC_CraftActionPanel,'Neat craft owner replaced')
 end
 assert(LootSorter._craftHooksAdded and LootSorter._getContainersWrapped,'owned Quartermaster craft hooks missing')
 -- Start with the actual ordinary craft container set, proving the remote ingredient is unavailable.
 LootSorter.craftFromBoxes=false
 local ordinary=ISInventoryPaneContextMenu.getContainers(player)
 notNearby=not sourceIn(ordinary)
 assert(notNearby,'designated source is already in ordinary crafting reach')
 logic:setContainers(ordinary);logic:setRecipe(recipe);logic:setManualSelectInputs(false);logic:clearManualInputs();logic:autoPopulateInputs()
 assert(logic:getPossibleCraftCount(true)==0,'fixture recipe can craft without fetching its exact Plank')
 local tick=assert(case()=='vanilla'and owner.qmTick or window.qmTick,'Quartermaster Storage tick missing')
 tick:setSelected(1,false);tick.joypadIndex=1;tick:forceClick()
 assert(LootSorter.craftFromBoxes,'Storage tick did not enable owned craft-from-boxes option')
end
local function click(player)
 local boxes,synced=LootSorter.gatherBoxes(player)
 if not synced then return false end
 local found=false
 for _,box in ipairs(boxes)do if box.container==state.source then found=true end end
 if not found then return false end
 local containers=ISInventoryPaneContextMenu.getContainers(player)
 if not sourceIn(containers)then return false end
 injected=true
 logic:setContainers(containers);logic:setRecipe(assert(getScriptManager():getCraftRecipe('QueueBorrowedTools')))
 logic:setManualSelectInputs(false);logic:clearManualInputs();logic:autoPopulateInputs()
 if not logic:canPerformCurrentRecipe()then return false end
 assert(logic:getPossibleCraftCount(true)==1,'Storage injection does not expose exactly one craft')
 if case()=='vanilla'then owner:setCraftQuantity(1);owner.buttonCraft:forceClick()
 else owner.quantityInput:setText('1');owner.craftButton:forceClick()end
 local walk,transfer,trigger=0,0,0
 for _,action in ipairs(queue().queue)do
  if action.Type=='LootSorterWalkAction'then walk=walk+1 end
  if action.Type=='ISInventoryTransferAction'and action.item and action.item:getID()==ids.materials[1]then transfer=transfer+1 end
  if action.Type=='LootSorterCraftTriggerAction'then trigger=trigger+1 end
 end
 assert(walk==1 and transfer==1 and trigger==1,'UI did not queue owned walking, exact ingredient retrieval and craft trigger')
 return true
end
local function observe(player)
 for _,action in ipairs(queue().queue)do
  if action.Type=='ISHandcraftAction'and action.craftRecipe==getScriptManager():getCraftRecipe('QueueBorrowedTools')then
   assert(not craft or craft==action,'more than one native craft action created');craft=action
   assert(action:getDuration()==150 and not player:isTimedActionInstant(),'native craft duration changed')
   assert(action.onCompleteTarget==owner and action.onStartTarget==owner,'native UI craft callbacks changed owner')
  end
 end
 local current=queue().current
 if current and current.Type=='LootSorterWalkAction'and
  (math.abs(player:getX()-(position.x+0.5))>0.5 or math.abs(player:getY()-(position.y+0.5))>0.5)then walked=true end
 if current and current.Type=='ISInventoryTransferAction'and current:isStarted()and current:getJobDelta()>0 then
  local items=current.queueList and current.queueList[1]and current.queueList[1].items or {current.item}
  for _,item in ipairs(items)do
   if item and item:getID()==ids.materials[1]then
    assert(current.srcContainer==state.source and current.destContainer==state.root,'exact material fetched through wrong endpoint');picked=true
   end
   for _,meta in ipairs(ids.toolMeta)do if item and item:getID()==meta.id then
    if current.destContainer==state.root then toolPickup[meta.id]=true end
    if current.srcContainer==state.root then toolReturn[meta.id]=true end
   end end
  end
 end
 if craft and current==craft and craft:isStarted()and craft:getJobDelta()>0 and not crafted then
  assert(walked and picked,'native craft started without observed physical haul')
  assert(state.source:getItems():size()==0 and state.root:getItemById(ids.materials[1]),'native craft did not start with exact hauled input at inventory root')
  crafted=true
 end
end
local function finish()
 assert(walked and picked and crafted and craft,'native haul/craft progress missing')
 assert(not logic:isCraftActionInProgress()and(not owner.craftTimes or owner.craftTimes==0),'native craft owner did not settle')
 local tools={};for _,meta in ipairs(ids.toolMeta)do tools[#tools+1]=meta.id end;table.sort(tools)
 if case()=='vanilla'then
  local a,b=sorted(toolPickup),sorted(toolReturn)
  assert(#a==2 and #b==2 and a[1]==tools[1]and a[2]==tools[2]and b[1]==tools[1]and b[2]==tools[2],'vanilla exact borrowed tool pickup/return did not execute')
 else assert(#sorted(toolPickup)==0 and #sorted(toolReturn)==0,'Neat unexpectedly transferred its bag tools')end
 local value={event='case',id=case(),status='passed',recipe='QueueBorrowedTools',callbackClass=case()=='vanilla'and 'ISWidgetHandCraftControl'or 'NC_CraftActionPanel',
  ordinarySourceExcluded=notNearby,storageSourceInjected=injected,walkProgress=walked,materialPickupProgress=picked,craftProgress=crafted,
  nativeDuration=150,toolPickupIds=sorted(toolPickup),toolReturnIds=sorted(toolReturn),ownerIdle=true}
 for key,entry in pairs(receipt)do if key~='case'then value[key]=entry end end;emit(value)
 LootSorter.craftFromBoxes=false;window:setVisible(false);window:removeFromUIManager()
 if step==#config.cases then
  emit({event='complete',cases=config.cases,expected=#config.cases,performed=#config.cases,failed=0,skipped=0})
  print('[QM_CRAFT] COMPLETE');done=true;return
 end
 local bags={};for _,id in ipairs(ids.bags)do bags[#bags+1]=assert(state.root:getItemById(id))end
 ISInventoryPaneContextMenu.onUnEquip(bags,getPlayer():getPlayerNum())
 previous=authorityState;step=step+1;phase='unequip';since=getTimestampMs()
 ids,state,authorityState,receipt,window,owner,logic,craft=nil,nil,nil,nil,nil,nil,nil,nil
 walked,picked,crafted,notNearby,injected=false,false,false,false,false;toolPickup,toolReturn={},{}
end
Events.OnPlayerUpdate.Add(function(player)
 if started and player==getPlayer()then idle=#queue().queue==0 and not player:hasTimedActions()and idle+1 or 0 end
end)
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs();getCore():setOptionPauseOnFocusloss(false)
 if not isClient()then getPlayer():setGhostMode(true)end
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
Events.OnTick.Add(function()
 if not started or done or not isIngameState()then return end
 local ok,problem=pcall(function()
  assert(getTimestampMs()-since<180000,'Quartermaster craft deadline: '..phase)
  local player=getPlayer();if not player or player:isDead()or not player:getSquare()then return end
  if config.kind=='mp'and(not isClient()or player:getOnlineID()<0)then return end
  if phase=='unequip'then
   if #queue().queue>0 or player:hasTimedActions()or idle<10 then return end
   phase='prepare';return
  end
  if phase=='prepare'then
   assert(PZSurvivorToolkit.Settings.actionQueue()==true,'Quartermaster craft smoke requires enabled Toolkit queue')
   if step==1 then emit({event='setup',cases=config.cases,expected=#config.cases,nativeDurations=true})end
   position=Fixture.placement(player);player:teleportTo(position.x+0.5,position.y+0.5,position.z)
   request('Prepare');phase='ready';return
  end
  if phase=='ready'then
   if not ids then return end;state=state or Fixture.resolve(player,ids);if not state then return end
   ISInventoryPaneContextMenu.onWearItems({state.root:getItemById(ids.bags[1])},player:getPlayerNum())
   ISInventoryPaneContextMenu.OnSecondWeapon({state.root:getItemById(ids.bags[2])},player:getPlayerNum())
   phase='equip';return
  end
  if phase=='equip'then
   if #queue().queue>0 or player:hasTimedActions()or idle<10 then return end
   getPlayerInventory(player:getPlayerNum()):refreshBackpacks();getPlayerLoot(player:getPlayerNum()):refreshBackpacks()
   LootSorter.setBoxItems(state.object,LootSorter.containerIndex(state.object,state.source),{[state.source:getItems():get(0):getDisplayName()]=true})
   designatedAt=getTimestampMs()
   open(player);phase='ui';return
  end
  if phase=='ui'then if click(player)then phase='running';since=getTimestampMs()end;return end
  if phase=='running'then
   observe(player)
   if idle<10 or #queue().queue>0 or player:hasTimedActions()then return end
   assert(crafted,'native queue drained without craft progress')
   local key=ids.source.x..','..ids.source.y..','..ids.source.z
   if getTimestampMs()-designatedAt<LootSorter.ADD_GRACE_MS+1000 then return end
   LootSorter.setBoxItems(state.object,LootSorter.containerIndex(state.object,state.source),{})
   cleanupRetry=getTimestampMs()
   phase='undesignate';return
  end
  if phase=='undesignate'then
   local key=ids.source.x..','..ids.source.y..','..ids.source.z
   if LootSorter.getRegistry()[key]then
    -- Object ModData and the coord registry use separate channels; retry a refused early removal.
    if getTimestampMs()-cleanupRetry>1000 then LootSorter.removeCoords({keys={key}});cleanupRetry=getTimestampMs()end
    return
   end
   request('Verify');phase='receipt';return
  end
  if phase=='receipt'and receipt then finish()end
 end)
 if not ok then print('[QM_CRAFT] FAIL '..tostring(problem));done=true end
end)
