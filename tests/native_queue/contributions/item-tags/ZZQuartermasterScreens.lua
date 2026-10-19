local entered,starting,started,done=false,false,false,false
local step,since=1,0
local picker,box
local steps={}
local function add(fn) steps[#steps+1]=fn end
local function shot(name) getCore():TakeFullScreenshot('tags-'..name..'.png');print('[QM_SCREEN] SHOT '..name) end
add(function()
 assert(not isClient() and not isServer(),'SP required')
 -- VISUAL_TEXTURE_GATE
 local visuals=require 'PZSurvivorToolkit/TagVisuals'
 for _,tag in ipairs({'food','electrical','tool','medical','material','perishable','fruit','preserved'}) do assert(visuals.get(tag).texture,'Missing tag icon '..tag) end
 for _,id in ipairs({'BravoItemDetails','organizedCategories_core','CleanUI','EURY_CONTAINERS','PZSurvivorToolkit'}) do assert(getActivatedMods():contains(id),'missing '..id) end
 assert(not getActivatedMods():contains('Quartermaster'),'external Quartermaster conflicts with the owned picker')
 local p=getPlayer();p:setGodMod(true);p:setGhostMode(true);p:setAutoDrink(false)
 getCore():setOptionAutoDrink(false)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
 if getPlayerInfoPanel and getPlayerInfoPanel(0) then getPlayerInfoPanel(0):setVisible(false) end
 local best,bestDist
 for dx=-28,28 do for dy=-28,28 do
  local sq=getCell():getGridSquare(math.floor(p:getX())+dx,math.floor(p:getY())+dy,0)
  if sq then
   local objs=sq:getObjects()
   for i=0,objs:size()-1 do local o=objs:get(i)
    if o:getContainerCount()>0 and o:getContainerByIndex(0) then
     local d=dx*dx+dy*dy
     if not bestDist or d<bestDist then best,bestDist=o,d end
    end
   end
  end
 end end
 box=assert(best,'no loaded native container nearby')
 local c=box:getContainerByIndex(0);assert(c)
 c:AddItem('Base.Apple');c:AddItem('Base.Nails');c:AddItem('Base.Battery')
 local sq=box:getSquare();print('[QM_SCREEN] BOX '..sq:getX()..','..sq:getY()..','..sq:getZ())
 LootSorter.openPicker(box,0,0);picker=assert(LootSorter._picker)
 assert(picker.toolkitTagSwitch and picker.toolkitTagView,'tag picker not installed')
 picker:setX(390);picker:setY(70)
 picker.filter:setText(PZSurvivorToolkit.ItemTags.label('electrical'));picker:rebuild()
 assert(#picker.listbox.items==1,'electrical tag missing or duplicate')
 picker.listbox.onmousedown(picker,picker.listbox.items[1].item)
 assert(picker.selectedCats.toolElectrical and picker.selectedCats.craftingElectrical_material,'electrical families not combined')
 assert(not picker.selectedCats.foodPerishable_fruit,'tag leaked into food')
end)
add(function()
 local l=picker.listbox;local v=l.vscroll
 print('[QM_SCREEN] GEOM list width='..tostring(l.width)..' height='..tostring(l.height)..' vscrollX='..tostring(v:getX())..' vscrollH='..tostring(v:getHeight())..' scrollH='..tostring(l:getScrollHeight())..' YScroll='..tostring(l:getYScroll()))
 shot('01-quartermaster-tags')
end)
add(function()
 picker.toolkitTagSwitch.onclick(picker)
 picker.filter:setText('Electrical');picker:rebuild()
 assert(not picker.toolkitTagView,'exact category toggle failed')
 picker.selectedCats.toolElectrical=nil
 picker.needRebuild=true
end)
add(function() shot('02-exact-refinement') end)
add(function()
 picker.toolkitTagSwitch.onclick(picker)
 picker.filter:setText(PZSurvivorToolkit.ItemTags.label('electrical'));picker:rebuild()
 assert(picker.toolkitTagView and #picker.listbox.items==1)
 local row=picker.listbox.items[1].item
 local n=0;for _,key in ipairs(row.categories) do if picker.selectedCats[key] then n=n+1 end end
 assert(n>0 and n<#row.categories,'partial selection missing')
end)
add(function() shot('03-partial-tags') end)
local pane
local function inventory(mode)
 LootSorter.closeAllWindows()
 CleanUI_setCleanInventoryUIEnabled(mode=='clean')
 local p=getPlayer();p:getInventory():getItems():clear()
 for _,id in ipairs({'Base.Apple','Base.TinnedBeans','Base.Screwdriver','Base.Nails','Base.ElectronicsScrap','Base.CarBattery1','Base.Bandage'}) do assert(p:getInventory():AddItem(id)) end
 p:getWornItems():clear();p:setPrimaryHandItem(nil);p:setSecondaryHandItem(nil)
 getPlayerLoot(0):setVisible(false)
 local page=getPlayerInventory(0);pane=page.inventoryPane
 page:setVisible(true);page:setX(100);page:setY(100);page:setWidth(1100);page:setHeight(650)
 page.isCollapsed=false;page:setPinned();page:setMaxDrawHeight(650);pane:setVisible(true)
end
local function reflowInventory()
 local page=getPlayerInventory(0)
 pane:setWidth(1090);pane:setHeight(590);pane.smoothScrollY=nil;pane.smoothScrollTargetY=nil;pane:setYScroll(0)
 pane:setMode('details');pane:refreshContainer()
 if page.cleanUIApplyScaleSettings then page:cleanUIApplyScaleSettings(true) end
 pane:onResize()
 pane:refreshContainer()
end
add(function()
 picker:onSave()
 local saved=assert(LootSorter.getBoxCats(box,0))
 assert(saved.craftingElectrical_material and not saved.toolElectrical and not saved.electrical,'saved tags instead of legacy categories')
 LootSorter.openPicker(box,0,0);picker=LootSorter._picker
 assert(picker.selectedCats.craftingElectrical_material and not picker.selectedCats.toolElectrical,'reopen lost refinement')
 print('[QM_SCREEN] SAVE exact IDs and reopen passed')
 inventory('clean')
end)
add(reflowInventory)
add(function()
 assert(pane.toolkitTagRows and #pane.toolkitTagRows>0,'CleanUI chips not drawn')
 for _,group in ipairs(pane.itemslist) do if group.items and group.items[1] then
  local key=group.items[1]:getDisplayCategory()
  assert(PZSurvivorToolkit.ItemTags.category(PZSurvivorToolkit.ItemTags.forCategory(key))==key,'legacy projection changed')
 end end
 assert(pane.width<=getPlayerInventory(0).width,'test child escaped parent geometry')
 local r=pane.toolkitTagRows[1]
 assert(r.drawnChips>0,'no visible chips')
 print('[QM_SCREEN] GEOM clean row='..tostring(r and r.left)..','..tostring(r and r.right)..' chips='..tostring(r and r.drawnChips)..' columns='..tostring(pane.column2)..','..tostring(pane.column3)..','..tostring(pane.column4)..' width='..tostring(pane.width)..' padding='..tostring(pane.padding)..' icon='..tostring(pane.cleanUIItemIconSize))
 for _,field in ipairs({'_cleanUIColumnBoundaryCache','_cleanUIRarityMetricsCache','_cleanUIWeightMetricsCache','_cleanUIHeaderMetricsCache'}) do
  local c=pane[field];local value=c and (c.state or c.value)
  if value then print('[QM_SCREEN] GEOM '..field..' right='..tostring(value.contentRight)..' boundary1='..tostring(value.boundary1)..' boundary2='..tostring(value.boundary2)..' categoryRight='..tostring(value.categoryRight)) end
 end
 shot('04-cleanui-inventory')
end)
add(function() inventory('vanilla') end)
add(reflowInventory)
add(function()
 assert(pane.toolkitTagRows and #pane.toolkitTagRows>0,'vanilla chips not drawn')
 shot('05-vanilla-inventory')
end)
add(function()
 pane.toolkitTag='food';pane:refreshContainer()
 local count=0
 for _,group in ipairs(pane.itemslist) do if group.items and group.items[1] then
  for _,item in ipairs(group.items) do
   assert(PZSurvivorToolkit.ItemTags.matches(PZSurvivorToolkit.ItemTags.forItem(item),{'food'}),
    'native tag filter leaked '..item:getFullType()..' category='..tostring(item:getDisplayCategory())..
    ' row='..tostring(group.cat)..' enabled='..tostring(PZSurvivorToolkit.Settings.inventoryFilters()))
  end
  count=count+1
 end end
 assert(count==2,'native tag filter missing food')
 local options=PZAPI.ModOptions:getOptions('PZSurvivorToolkit')
 options:getOption('ItemTags'):setValue(false)
end)
add(function()
 assert(not PZSurvivorToolkit.ItemTags.enabled(),'live disable failed')
 assert(not pane.toolkitTagRows or #pane.toolkitTagRows==0,'disabled tag rows remain')
 local count=0;for _,group in ipairs(pane.itemslist) do if group.items and group.items[1] then count=count+1 end end
 assert(count==7,'live disable kept tag-filtered rows')
 LootSorter.openPicker(box,0,0);picker=LootSorter._picker
 assert(picker.toolkitTagSwitch and not picker.toolkitTagSwitch:isVisible(),'off-start picker switched UI')
 PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ItemTags'):setValue(true)
end)
add(function()
 assert(picker.toolkitTagSwitch:isVisible(),'same picker failed live enable')
 picker.filter:setText(PZSurvivorToolkit.ItemTags.label('electrical'));picker:rebuild()
 assert(#picker.listbox.items==1 and picker.listbox.items[1].item.tag=='electrical','live enable needs reopen')
 print('[QM_SCREEN] COMPLETE 5 screenshots; native tag picker/save/refinement/chips/filter/live-toggle; no MP test')
 done=true
end)
Events.OnMainMenuEnter.Add(function() entered=true end)
Events.OnPreUIDraw.Add(function()
 if started and isIngameState() then setGameSpeed(1) end
 if not entered or starting or isIngameState() then return end
 starting=true;getCore():setOptionPauseOnFocusloss(false)
 getWorld():setGameMode('Sandbox');getWorld():setWorld('QuartermasterScreens');getWorld():setMap('Muldraugh, KY')
 MainScreen.instance:setDefaultSandboxVars()
 for name,value in pairs({Zombies=6,EnableVehicles=false,StartMonth=7,StartDay=9,StartTime=2}) do getSandboxOptions():getOptionByName(name):setValue(value) end
 getSandboxOptions():toLua();MainScreen.instance.createWorld=true
 MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=10835,posY=10144,posZ=0}}}}
 MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
 MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
end)
Events.OnGameStart.Add(function() started=true;since=getTimestampMs();getCore():setOptionPauseOnFocusloss(false) end)
Events.OnTick.Add(function()
 if not started then return end
 if done then if getTimestampMs()-since>4000 then getCore():quitToDesktop() end;return end
 if getTimestampMs()-since<1800 then return end
 local ok,err=pcall(steps[step])
 if not ok then print('[QM_SCREEN] FAIL '..step..' '..tostring(err));getCore():TakeFullScreenshot('qm-failed.png');done=true;since=getTimestampMs();return end
 step=step+1;since=getTimestampMs()
end)
