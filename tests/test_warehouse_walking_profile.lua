-- Boundary registration leaves the installed class and instance owners untouched.
local modules={}
local phase,active,bindings
local function callback()end
local pageClass={};for _,name in ipairs({'refreshBackpacks','addContainerButton','checkExplored','refreshWeight','updateItemCount'})do pageClass[name]=function()end end
pageClass.__index=pageClass
local paneClass={refreshContainer=function()end,restoreSelection=function()end,saveSelection=function()end};paneClass.__index=paneClass
local pages={}
for i=1,2 do pages[i]=setmetatable({inventoryPane=setmetatable({refreshContainer=function()end,itemSortFunc=function()end},paneClass)},pageClass)end
function getPlayerInventory()return pages[1]end
function getPlayerLoot()return pages[2]end
for _,name in ipairs({'BetterContainers/Nested','BetterContainers/Proximity','BetterContainers/_Options',
 'PZSurvivorToolkit/InventoryRows','PZSurvivorToolkit/InventoryRefresh',
 'PZSurvivorToolkit/InventorySearch','PZSurvivorToolkit/InventoryCategoryGroups','PZSurvivorToolkit/InventoryOrder',
 'PZSurvivorToolkit/InventoryDetailSort','PZSurvivorToolkit/ItemCategoryRules','PZSurvivorToolkit/ItemCategories',
 'PZSurvivorToolkit/ItemRetention','PZSurvivorToolkit/ItemTagProperties','PZSurvivorToolkit/PlantingTags',
 'PZSurvivorToolkit/ItemUsageTags','PZSurvivorToolkit/ItemFluidTags','PZSurvivorToolkit/ItemBaitTags',
 'PZSurvivorToolkit/ItemRepairTags','PZSurvivorToolkit/ItemLaundryTags','PZSurvivorToolkit/ItemSmeltingTags',
 'PZSurvivorToolkit/ItemSharpeningTags','PZSurvivorToolkit/ItemBrokenTags','PZSurvivorToolkit/ItemCookingTags',
 'PZSurvivorToolkit/ItemCookingStates','PZSurvivorToolkit/ItemDisassemblyTags','PZSurvivorToolkit/ItemMediaTags',
 'PZSurvivorToolkit/TagCustomization','PZSurvivorToolkit/ItemRecipeCatalog'})do
 local module={consume=function()end};modules[name]=module;package.preload[name]=function()return module end
end
-- Execute the real side-effect module: it publishes Toolkit.InventoryFilter,
-- registers its installer and returns nil; stock require then returns true.
PZSurvivorToolkit={}
Events={OnGameStart={Add=function()end}}
for _,name in ipairs({'InventoryClasses','InventoryMembership','Settings','UIStyle','TagVisuals','TagRulePicker','TagFilterPresetsMenu'})do
 package.preload['PZSurvivorToolkit/'..name]=function()return {}end
end
local tags={};for _,key in ipairs({'signature','automaticForItem','forItem','newProjectionContext'})do tags[key]=function()end end
package.preload['PZSurvivorToolkit/ItemTags']=function()return tags end
package.preload['PZSurvivorToolkit/InventoryFilter']=function()
 local value=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/InventoryFilter.lua')
 assert(value==nil and type(PZSurvivorToolkit.InventoryFilter.choices)=='function','actual side-effect contract changed')
 return value
end
function warehouseWalkingProfileReset()assert(not active);bindings={}end
function warehouseWalkingProfileBind(label,value)assert(not active and type(value)=='function');bindings[#bindings+1]={label,value}end
function warehouseWalkingProfileBegin(index)phase=index;active=true end
function warehouseWalkingProfileFinish()assert(active);active=false;return {phase=phase}end
local Profile=dofile(ProjectRoot..'/tests/native_queue/warehouse-walking/client/WarehouseWalkingProfile.lua')
local classRefresh,paneRefresh,instanceRefresh=pageClass.refreshBackpacks,paneClass.refreshContainer,pages[1].inventoryPane.refreshContainer
for index=1,16 do
 Profile.begin(index,0)
 assert(active and #bindings>20)
 local found={};for _,entry in ipairs(bindings)do found[entry[1]]=entry[2]end
 for key,value in pairs(tags)do assert(found['tags.'..key]==value,'missing public tag reader: '..key)end
 assert(found['tagProperties.consume']==modules['PZSurvivorToolkit/ItemTagProperties'].consume)
 assert(found['recipeCatalog.consume']==modules['PZSurvivorToolkit/ItemRecipeCatalog'].consume)
 assert(pageClass.refreshBackpacks==classRefresh and paneClass.refreshContainer==paneRefresh and pages[1].inventoryPane.refreshContainer==instanceRefresh)
 assert(not pcall(Profile.begin,index,0),'nested measurement admitted')
 local result=Profile.finish();assert(result.phase==index and result.identities_unchanged)
end
assert(package.loaded['PZSurvivorToolkit/InventoryFilter']==true,'real side-effect require did not return true')
-- Native Kahlua may return nil instead of the stock require true sentinel.
local normalRequire=require
require=function(name)if name=='PZSurvivorToolkit/InventoryFilter'then return nil end;return normalRequire(name)end
Profile.begin(1,0);Profile.finish();require=normalRequire
local filter=PZSurvivorToolkit.InventoryFilter;PZSurvivorToolkit.InventoryFilter=nil
assert(not pcall(Profile.begin,1,0),'missing known side-effect export admitted')
PZSurvivorToolkit.InventoryFilter=filter
local proximity=package.loaded['BetterContainers/Proximity'];package.loaded['BetterContainers/Proximity']=true
assert(not pcall(Profile.begin,1,0),'unrelated non-table module admitted by fallback')
package.loaded['BetterContainers/Proximity']=proximity
Profile.begin(1,0);pageClass.refreshBackpacks=callback
assert(not pcall(Profile.finish),'callback ownership change was accepted')
assert(not active and pageClass.refreshBackpacks==callback,'successor callback was overwritten')
pageClass.refreshBackpacks=classRefresh
local saved=warehouseWalkingProfileReset;warehouseWalkingProfileReset=nil
assert(not pcall(Profile.begin,1,0),'missing native observer was accepted');warehouseWalkingProfileReset=saved
paneClass.restoreSelection=nil
assert(not pcall(Profile.begin,1,0),'missing native row boundary was accepted')
print('WAREHOUSE_WALKING_PROFILE_LUA_PASS')
