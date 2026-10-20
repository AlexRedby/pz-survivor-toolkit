local config=require 'QueueTestSelection'
if config.cases[1]~='backpack' then return end
require 'TimedActions/ISWearClothing'
local Fixture=require 'QuartermasterDistributionFixture'
require 'PZSurvivorToolkit/Settings'
local Tags=require 'PZSurvivorToolkit/ItemTags'
local Rules=require 'PZSurvivorToolkit/QuartermasterTagRuleClient'
local JSON=require 'QueueHealthEvents'
local started,done,since,phase=false,false,0,'prepare'
local point,box,rejectedBox,bag,items,ids,original,designatedAt,quietSince
local transferred,dispatched,sourceBag,rejectedDestinationSkipped=false,false,false,false
local updates=0
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function counts(container,result)
 result=result or {}
 for i=0,container:getItems():size()-1 do
  local item=container:getItems():get(i);local id=item:getID();result[id]=(result[id]or 0)+1
  if instanceof(item,'InventoryContainer')then counts(item:getInventory(),result)end
 end
 return result
end
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs();getCore():setOptionPauseOnFocusloss(false)
 getCore():setOptionAutoDrink(false);getPlayer():setAutoDrink(false)
 getPlayer():setGodMod(true);getPlayer():setGhostMode(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
Events.OnPlayerUpdate.Add(function(player)
 if started and player==getPlayer()then updates=updates+1 end
end)
local function showBag()
 local page=assert(getPlayerInventory(0));page:refreshBackpacks();page:setNewContainer(bag:getInventory())
 page:setVisible(true);page.isCollapsed=false;page:setMaxDrawHeight(page.height)
 local pane=page.inventoryPane;pane:refreshContainer();pane:prerender()
 return page,pane
end
local function checkDestinationQueue()
 local q=queue()
 local function check(action)
  assert(not action or action.destContainer~=rejectedBox:getContainer(),'native-rejected destination was queued')
 end
 check(q.current)
 for _,action in ipairs(q.queue)do check(action)end
end
local function dispatch(player)
 local page,pane=showBag()
 local row,index
 for i,value in ipairs(pane.items)do
  local item=instanceof(value,'InventoryItem')and value or value.items[1]
  if item:getFullType()==items[1]:getFullType()and item:getContainer()==bag:getInventory()then row,index=value,i;break end
 end
 assert(row and items[1]:isInPlayerInventory(),'worn bag Thread row missing')
 pane.selected={[index]=row}
 page.controlsUI:arrange()
 local handler=assert(page.controlsUI.handlers[ISInventoryWindowControlHandler_LootSorterDistribute])
 assert(page:getIsVisible()and page.controlsUI:getIsVisible()and handler.control:getIsVisible()
  and handler.container==bag:getInventory()and player:getJoypadBind()==-1,'visible bag toolbar precondition missing')
 assert(PZSurvivorToolkit.Settings.contextMenus(),'context organizer must be enabled for this regression')
 local inInventory=pane.inventory:isInCharacterInventory(player)
 assert(inInventory,'source bag is not carried')
 local menu=assert(ISInventoryPaneContextMenu.createMenu(0,inInventory,{row},20,20))
 assert(menu.toolkitContextKind=='inventory','right-click route is not the carried inventory context')
 menu:setVisible(true);menu:prerender()
 local option,optionIndex
 for i,value in ipairs(menu.options)do
  if value.name=='Distribute Loot'then option,optionIndex=value,i;break end
 end
 print('[QM_BACKPACK] MENU '..JSON.encode({visible=option~=nil,toolbarVisible=true,category=items[1]:getDisplayCategory()}))
 assert(option and option.onSelect and not option.notAvailable and not option.isDisabled,'Distribute Loot hidden from worn bag context menu')
 menu:prerender();assert(menu.options[optionIndex]==option,'distribution option moved during layout')
 menu.mouseOver=optionIndex;menu:ensureVisible()
 local scroll=menu:getScrollHeight()>menu:getScrollAreaHeight()
 local y=menu.padTopBottom+(scroll and menu.scrollIndicatorHgt or 0)+menu:getScrollAreaHeight()/2-menu:getYScroll()
 local before=LootSorter._sortRunSeq or 0
 menu:onMouseUp(5,y)
 assert((LootSorter._sortRunSeq or 0)>before and #queue().queue>0,'context option did not start distribution')
 checkDestinationQueue()
 dispatched=true
end
local function tick()
 local player=getPlayer();local root=player:getInventory()
 if phase=='prepare'then
  if updates<30 then return end
  -- Use the documented organizedCategories provider, not BetterContainers' alternative categories.
  local options=PZAPI.ModOptions:getOptions('BetterContainers')
  if options then
   options:getOption('showAdvancedDisplayCategories'):setValue(false);options:apply()
   assert(not require('BetterContainers/_Options').showAdvancedDisplayCategories,'category provider not configured')
  end
  original=counts(root);assert(not player:getClothingItem_Back(),'fresh fixture already has a worn bag')
  point=Fixture.place(player)
  for index,offset in ipairs({{1,0},{0,1}})do
   local square=assert(getCell():getGridSquare(point.x+offset[1],point.y+offset[2],point.z))
   local target=IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
   target:setBlockAllTheSquare(true);target:setIsContainer(true)
   target:getContainer():setType('crate');target:getContainer():setCapacity(100);target:getContainer():setExplored(true)
   target:getModData().PZSTDistributionFixture=true;square:AddSpecialObject(target)
   if index==1 then box=target else rejectedBox=target end
  end
  rejectedBox:getContainer():setOnlyAcceptCategory('Food')
  bag=assert(root:AddItem('Base.Bag_Schoolbag'))
  items={assert(bag:getInventory():AddItem('Base.Thread')),assert(bag:getInventory():AddItem('Base.Thread')),
   assert(bag:getInventory():AddItem('Base.LargeStone')),assert(root:AddItem('Base.Thread'))}
  local script=items[1]:getScriptItem();local lootCategory=script:getDisplayCategory()
  assert(lootCategory=='Material','Thread script no longer has its loot-safe category')
  assert(Tags.matches(Tags.forScriptItem(script),{'tailoring','material'}),'Thread catalog tags disagree with inventory category')
  assert(script:getDisplayCategory()==lootCategory,'catalog tags changed native loot category')
  items[2]:setFavorite(true);ids={}
  for _,item in ipairs(items)do ids[#ids+1]=item:getID()end
  ids[#ids+1]=bag:getID();print('[QM_BACKPACK] PREPARED '..JSON.encode({ids=ids}))
  ISTimedActionQueue.add(ISWearClothing:new(player,bag,50));phase='configure'
 elseif phase=='configure'then
  if #queue().queue>0 or player:hasTimedActions()then return end
  assert(player:getClothingItem_Back()==bag,'native wear did not equip backpack')
  -- organizedCategories applies inventory display categories when the bag is opened.
  showBag()
  assert(items[1]:getDisplayCategory()=='craftingTailoring_material','Thread has unexpected category '..tostring(items[1]:getDisplayCategory()))
  assert(Tags.matches(Tags.forItem(items[1]),{'tailoring'})and not Tags.matches(Tags.forItem(items[3]),{'tailoring'}),'invalid tailoring fixture items')
  for _,target in ipairs({box,rejectedBox})do
   local name=target==box and 'allowed' or 'native-rejected'
   local square,current=target:getSquare(),player:getCurrentSquare()
   local location=square:getX()..','..square:getY()..','..square:getZ()
   assert(current:getZ()==square:getZ()and math.abs(current:getX()-square:getX())<=1
    and math.abs(current:getY()-square:getY())<=1 and not current:isBlockedTo(square),
    name..' crate outside native designation access at '..location)
   LootSorter.openPicker(target,0,0);local picker=assert(LootSorter._picker)
   picker.toolkitTagRule={mode='all',include={'tailoring'},exclude={}};picker.toolkitTagRuleTouched=true
   picker.priority=target==rejectedBox and 5 or 0
   picker.btnSave.onclick(picker)
   local saved,revision=Rules.getBox(target,0),Rules.getBoxRevision(target,0)
   assert(not LootSorter._picker and saved and saved.include[1]=='tailoring',name..' tailoring designation did not save at '..location
    ..' revision='..tostring(revision)..' pickerOpen='..tostring(LootSorter._picker==picker))
   print('[QM_BACKPACK] DESIGNATED '..JSON.encode({target=name,location=location,revision=revision}))
  end
  designatedAt=getTimestampMs();phase='ready'
 elseif phase=='ready'then
  if not LootSorter.isRegistrySynced()or not LootSorter.arePresetsSynced()then return end
  local found,rejectedFound=false,false
  for _,entry in ipairs(LootSorter.gatherBoxes(player)or {})do
   if entry.obj==box then found=true end
   if entry.obj==rejectedBox then rejectedFound=true end
  end
  if not found or not rejectedFound then return end
  assert(LootSorter.getBoxPriority(rejectedBox,0)>LootSorter.getBoxPriority(box,0),'native-rejected crate must win priority before admission')
  assert(AdjacentFreeTileFinder.Find(rejectedBox:getSquare(),player),'native-rejected crate is unreachable')
  local rejected=rejectedBox:getContainer()
  assert(rejected:isItemAllowed(items[1])==false,'Food-only crate unexpectedly admits Thread')
  -- hasRoomFor also tests native admission; check weight room separately to isolate rejection.
  assert(rejected:getEffectiveCapacity(player)*LootSorter.BOX_FILL_FRACTION-rejected:getCapacityWeight()>items[1]:getActualWeight(),
   'native-rejected crate lacks positive weight room')
  assert(box:getContainer():isItemAllowed(items[1])and box:getContainer():hasRoomFor(player,items[1]),'allowed crate cannot receive Thread')
  dispatch(player);phase='sorting'
 elseif phase=='sorting'then
  checkDestinationQueue()
  local current=queue().current
  if current and current.Type=='LootSorterDeposit'and current:isStarted()and current:getJobDelta()>0 then
   assert(current.item==items[1]and current.srcContainer==bag:getInventory()and current.destContainer==box:getContainer(),'wrong transfer item/endpoints')
   sourceBag=true;transferred=true
  end
  if #queue().queue>0 or player:hasTimedActions()then quietSince=nil;return end
  quietSince=quietSince or getTimestampMs();if getTimestampMs()-quietSince<1000 then return end
  local carried,dest,rejected=counts(root),counts(box:getContainer()),counts(rejectedBox:getContainer())
  for i,item in ipairs(items)do
   local id=ids[i];assert((carried[id]or 0)+(dest[id]or 0)+(rejected[id]or 0)==1,'lost/duplicated fixture item')
   assert(item:getContainer()==(i==1 and box:getContainer()or i==4 and root or bag:getInventory()),'wrong final item container')
  end
  assert(items[2]:isFavorite()and bag:getContainer()==root and player:getClothingItem_Back()==bag,'favorite/equipment state lost')
  for id,count in pairs(original)do assert(carried[id]==count,'pre-existing inventory changed')end
  assert(transferred and sourceBag and dispatched,'missing native distribution progress')
  assert(rejectedBox:getContainer():getItems():size()==0,'native-rejected destination received items')
  rejectedDestinationSkipped=true
  print('[QM_BACKPACK] RESULT '..JSON.encode({ids=ids,moved=1,retained=3,backpackWorn=true,
   menuDispatched=dispatched,toolbarVisible=true,sourceBag=sourceBag,transfer=transferred,rejectedDestinationSkipped=rejectedDestinationSkipped}))
  phase='cleanup'
 elseif phase=='cleanup'then
  if getTimestampMs()-designatedAt<LootSorter.ADD_GRACE_MS+1000 then return end
  Fixture.cleanup({boxes={box,rejectedBox}})
  LootSorter.removeCoords({keys={(point.x+1)..','..point.y..','..point.z,point.x..','..(point.y+1)..','..point.z}})
  print('[QM_BACKPACK] COMPLETE');done=true
 end
end
Events.OnTick.Add(function()
 if not started or done or not isIngameState()or not getPlayer()or not getPlayer():getSquare()then return end
 local ok,problem=pcall(function()assert(getTimestampMs()-since<120000,'backpack timeout phase='..phase);tick()end)
 if not ok then done=true;print('[QUEUE_TEST] FAIL backpack '..tostring(problem))end
end)
