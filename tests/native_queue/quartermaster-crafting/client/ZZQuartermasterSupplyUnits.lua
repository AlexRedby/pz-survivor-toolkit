local config=require 'QueueTestSelection'
if config.cases[1]~='uses'then return end
require 'PZSurvivorToolkit/ActionQueuePanel'
require 'ISUI/Crafting/ISHandcraftWindow'
require 'Neat_Crafting/NC_CraftActionPanel'
local Placement=require 'QueueQuartermasterCraftFixture'
local F=require 'QueueSupplyUnitsFixture'
local JSON=require 'QueueHealthEvents'
local index,phase,idle,since=1,'prepare',0,0
local started,done=false,false
local packet,object,authority,previous,receipt,point,window,panel,owner,logic,native,designatedAt,retry
local walked,picked,crafted=false,false,false
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function emit(event,value)print('[QM_USES] '..event..' '..JSON.encode(value))end
local function request(command)
 if isClient()then sendClientCommand('QuartermasterSupplyTest',command,{index=index,position=point})
 elseif command=='Prepare'then
  authority=F.prepare(getPlayer(),index,point,previous);previous=nil;packet=F.descriptor(authority);emit('PREPARED',packet)
 elseif command=='Verify'then receipt=assert(F.verify(authority));emit('VERIFIED',receipt);previous=authority
 else F.cleanup(previous,true);previous=nil;print('[QM_USES] CLEANUP');phase='cleaned'end
end
Events.OnServerCommand.Add(function(module,command,value)
 if module~='QuartermasterSupplyTest'then return end
 assert(command~='Failed',value.error)
 if command=='Prepared'then packet=value elseif command=='Verified'then receipt=value elseif command=='Cleaned'then phase='cleaned'end
end)
local function contains(containers,source)
 for i=0,containers:size()-1 do if containers:get(i)==source then return true end end
 return false
end
local function open(player)
 local recipe=assert(getScriptManager():getCraftRecipe('QueueSupplyUnits'))
 LootSorter.craftFromBoxes=false
 if index==1 then
  window=ISXuiSkin.build(XuiManager.GetDefaultSkin(),'HandcraftWindow',ISHandcraftWindow,20,20,900,600,player,nil,'InHandCraft')
  window:initialise();window:instantiate();window:addToUIManager()
  panel=assert(window.handCraftPanel);owner=assert(panel.recipePanel.craftControl)
 else
  ISEntityUI.OpenHandcraftWindow(player,nil,'InHandCraft',true,recipe)
  window=assert(ISEntityUI.GetWindowInstance(player:getPlayerNum(),'HandcraftWindow'))
  panel=assert(window.HandCraftPanel or window.handCraftPanel);owner=assert(panel.craftActionPanel)
 end
 logic=panel.logic
 local ordinary=ISInventoryPaneContextMenu.getContainers(player)
 assert(not contains(ordinary,object:getContainer()),'supply crate is already nearby')
 logic:setContainers(ordinary);logic:setRecipe(recipe);logic:setManualSelectInputs(false);logic:clearManualInputs();logic:autoPopulateInputs()
 assert(logic:getPossibleCraftCount(true)==(index==2 and 2 or 0),'native ordinary-use availability differs')
 local tick=assert(index==1 and owner.qmTick or window.qmTick)
 tick:setSelected(1,false);tick.joypadIndex=1;tick:forceClick()
 assert(LootSorter.craftFromBoxes,'Storage toggle failed')
end
local function click(player)
 local boxes,synced=LootSorter.gatherBoxes(player);if not synced then return end
 local found=false;for _,box in ipairs(boxes)do if box.container==object:getContainer()then found=true end end
 if not found then return end
 panel:updateContainers(true)
 if not contains(logic:getContainers(),object:getContainer())then return end
 logic:setRecipe(assert(getScriptManager():getCraftRecipe('QueueSupplyUnits')))
 logic:setManualSelectInputs(false);logic:clearManualInputs();logic:autoPopulateInputs()
 if not logic:canPerformCurrentRecipe()then return end
 if index==1 then owner:setCraftQuantity(1);owner.buttonCraft:forceClick()
 else owner.quantityInput:setText('1');owner.craftButton:forceClick()end
 local transfers,walks=0,0;local expected=index==1 and packet.ids[1]or packet.ids[2]
 for _,action in ipairs(queue().queue)do
  if action.Type=='LootSorterWalkAction'then walks=walks+1 end
  if action.Type=='ISInventoryTransferAction'then
   assert(index~=2 and action.item and action.item:getID()==expected,'unnecessary or wrong supply fetched');transfers=transfers+1
  end
 end
 assert(transfers==(index==2 and 0 or 1)and walks==(index==2 and 0 or 1),'supply haul count differs')
 return true
end
local function observe(player)
 for _,action in ipairs(queue().queue)do
  if action.Type=='ISHandcraftAction'and action.craftRecipe==getScriptManager():getCraftRecipe('QueueSupplyUnits')then
   assert(not native or native==action,'duplicate supply craft');native=action
   assert(action:getDuration()==100 and action.onCompleteTarget==owner and action.onStartTarget==owner,'native supply craft owner/duration differs')
  end
 end
 local current=queue().current
 if current and current.Type=='LootSorterWalkAction'and(math.abs(player:getX()-point.x-.5)>.5 or math.abs(player:getY()-point.y-.5)>.5)then walked=true end
 if current and current.Type=='ISInventoryTransferAction'and current:isStarted()and current:getJobDelta()>0 then
  assert(current.srcContainer==object:getContainer()and current.destContainer==player:getInventory(),'wrong supply endpoints');picked=true
 end
 if native and current==native and native:isStarted()and native:getJobDelta()>0 then crafted=true end
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
  assert(getTimestampMs()-since<180000,'supply deadline: '..phase)
  local player=getPlayer();if not player or player:isDead()or not player:getSquare()then return end
  if config.kind=='mp'and(not isClient()or player:getOnlineID()<0)then return end
  if phase=='prepare'then
   if index==1 then point=Placement.placement(player)end
   player:teleportTo(point.x+.5,point.y+.5,point.z);request('Prepare');phase='ready';return
  end
  if phase=='ready'then
   if not packet then return end;object=object or F.resolve(player,packet);if not object then return end
   local tape=object:getContainer():getItems():get(0)
   LootSorter.setBoxItems(object,LootSorter.containerIndex(object,object:getContainer()),{[tape:getDisplayName()]=true})
   designatedAt=designatedAt or getTimestampMs();open(player);phase='ui';return
  end
  if phase=='ui'then if click(player)then phase='running';since=getTimestampMs()end;return end
  if phase=='running'then
   observe(player)
   if idle<10 or #queue().queue>0 or player:hasTimedActions()then return end
   assert(crafted and native and not logic:isCraftActionInProgress(),'supply craft did not settle')
   assert(walked==(index~=2)and picked==(index~=2),'physical supply haul progress differs')
   request('Verify');phase='receipt';return
  end
  if phase=='receipt'and receipt then
   emit('RESULT',{index=index,case=F.cases[index],walked=walked,picked=picked,crafted=crafted,receipt=receipt})
   LootSorter.craftFromBoxes=false;window:setVisible(false);window:removeFromUIManager()
   if index==3 then phase='undesignate';return end
   index=index+1;packet,object,authority,receipt,native=nil,nil,nil,nil,nil
   walked,picked,crafted=false,false,false;phase='prepare';return
  end
  if phase=='undesignate'then
   if getTimestampMs()-designatedAt<LootSorter.ADD_GRACE_MS+1000 then return end
   LootSorter.setBoxItems(object,LootSorter.containerIndex(object,object:getContainer()),{});retry=getTimestampMs();phase='registry';return
  end
  if phase=='registry'then
   local key=packet.source.x..','..packet.source.y..','..packet.source.z
   if LootSorter.getRegistry()[key]then
    if getTimestampMs()-retry>1000 then LootSorter.removeCoords({keys={key}});retry=getTimestampMs()end;return
   end
   index=4;phase='cleanup';request('Cleanup');return
  end
  if phase=='cleaned'then print('[QM_USES] COMPLETE');done=true end
 end)
 if not ok then print('[QM_USES] FAIL '..tostring(problem));done=true end
end)
