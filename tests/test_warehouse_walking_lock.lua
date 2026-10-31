-- Opt-in source-backed contract for the installed BC controller and CleanUI's
-- native look-square/force-hold selection. External sources stay external.
local bcPath=os.getenv('PZ_WALKING_BC_PROXIMITY_SOURCE')
local pagePath=os.getenv('PZ_WALKING_CLEANUI_PAGE_SOURCE')
if not bcPath or not pagePath then print('SKIP warehouse walking installed BC/CleanUI lock sources');return end
local function read(path)local f=assert(io.open(path));local source=f:read('*a');f:close();return(source:gsub('\r\n','\n'))end
local bcSource,pageSource=read(bcPath),read(pagePath)
local lookStart=assert(pageSource:find('if (numButtons < #self.backpacks) and (gs == lookSquare) then',1,true))
local lookEnd=assert(pageSource:find('\n\t\t\t\tend',lookStart,true))
local nativeLook=assert(loadstring('return function(self,numButtons,gs,lookSquare)\n'..pageSource:sub(lookStart,lookEnd+8)..'\nend'))()
local forceStart=assert(pageSource:find('\n\tif self.forceSelectedContainer then',lookEnd,true))
local forceEnd=assert(pageSource:find('\n\tself.inventoryPane:bringToTop()',forceStart,true))
local nativeForce=assert(loadstring('return function(self)\n'..pageSource:sub(forceStart,forceEnd-1)..'\nend'))()
local clock,clean=0,false
function getTimestampMs()return clock end
function CleanUI_isCleanInventoryUIEnabled()return clean end
function getTexture()return {}end
function instanceof()return false end
local eff={proximityActive=true,autoLock=false,corpseOnly=false,dualMode=false}
local Options={getEffectivePermissions=function()return eff end}
package.preload['BetterContainers/_Options']=function()return Options end
package.preload['BetterContainers/Helpers']=function()return {}end
local P=assert(loadstring(bcSource,'@installed/BetterContainers/Proximity.lua'))()
package.preload['BetterContainers/Proximity']=function()return P end
local function inventory(kind,count)
 local items={n=count}
 function items:clear()self.n=0 end
 function items:addAll(other)self.n=self.n+other.n end
 return {getType=function()return kind end,getItems=function()return items end,getParent=function()end}
end
local root,physical,aggregate=inventory('inventorymale',1),inventory('crate',12),inventory('proximityInv',0)
P.itemContainer[0]=aggregate
local pages={}
local Page={};Page.__index=Page
ISInventoryPage=Page
local hold=assert(pageSource:match('(function ISInventoryPage:setForceSelectedContainer%b().-)\nend'))..'\nend'
assert(loadstring(hold,'@installed/CleanUI/setForceSelectedContainer.lua'))()
function Page:getX()return self.x end
function Page:getY()return 50 end
function Page:getWidth()return 590 end
function Page:getHeight()return 740 end
function Page:getIsVisible()return self.visible end
function Page:setWidth()end
function Page:setHeight()end
function Page:setX(x)self.x=x end
function Page:setY()end
function Page:setVisible(v)self.visible=v end
function Page:collapse()self.isCollapsed=true end
function Page:collapseNow()self.isCollapsed=true end
function Page:setNewContainer(inv)self.inventoryPane.inventory=inv end
function Page:onBackpackClick(button)self.inventoryPane.inventory=button.inventory end
function Page:refreshBackpacks()end
local function createPages()
 for i=1,2 do
  local pane={mode='details',inventory=i==1 and root or aggregate,getIsVisible=function()return true end}
  pages[i]=setmetatable({player=0,x=i==1 and 30 or 640,visible=true,isCollapsed=false,inventoryPane=pane,
   backpacks={{inventory=physical,capacity=100},{inventory=aggregate,capacity=0}},bcProximityRefreshGeneration=1},Page)
 end
 P.inventoryButtonRef[0]=pages[2].backpacks[2]
end
function CleanUI_setCleanInventoryUIEnabled(value)clean=value;createPages()end
createPages();pages[2].tempForceSelectUnlock=true
local player={getPlayerNum=function()return 0 end,getInventory=function()return root end}
function getSpecificPlayer()return player end
function getPlayerLoot()return pages[2]end
local U={pages=function()return pages end}
function U.configure(_,mode)
 if clean~=(mode=='clean')then CleanUI_setCleanInventoryUIEnabled(mode=='clean')end
 for _,page in ipairs(pages)do page.visible=true;page.isCollapsed=false;page.inventoryPane.mode='details'end
end
package.preload.WarehouseWorkloadUI=function()return U end
package.preload.WarehouseWalkingProfile=function()return {}end
package.preload['TimedActions/WalkToTimedAction']=function()return true end
package.preload['TimedActions/ISTimedActionQueue']=function()return true end
function Page.dirtyUI()
 local loot=pages[2];local square={}
 nativeLook(loot,0,square,square)
 assert(loot.inventoryPane.inventory==physical,'installed native look direction no longer selects physical stock')
 P.OnButtonsAdded(loot)
 nativeForce(loot);loot.inventory=loot.inventoryPane.inventory
end
-- With auto-lock off and no manual lock, real native look selection survives.
Page.dirtyUI();assert(pages[2].inventoryPane.inventory==physical)
local N=dofile(ProjectRoot..'/tests/native_queue/warehouse-walking/client/WarehouseWalkingNative.lua')
P.isForceSelected[0]=false;P.forceSelectedType[0]='original-mode';P._BrowseElapsedMs[0]=17.25;P._HasNearbyCorpses[0]=nil
local saved=N.saveLock(player);local setter=P.updateForceSelected
N.configure(player,{paneMode='clean',paneState='both-open'})
assert(P.isForceSelected[0]and P.forceSelectedType[0]==P.invName and P.updateForceSelected==setter)
-- Every discovery renews the real native hold before its final selection stage.
-- Two-second gaps exceed its one-second default, so an old hold cannot pass.
for _=1,12 do clock=clock+2000;Page.dirtyUI();assert(pages[2].inventoryPane.inventory==aggregate,'public manual lock lost aggregate during direction change')end
N.restoreLock(player,saved)
assert(not clean and pages[2].tempForceSelectUnlock==true,'restoration did not establish original live page before unlock flags')
Page.dirtyUI() -- final native owner refresh may rewrite scalar presence caches
local proof=N.finishLockRestoration(player,saved)
assert(proof.restored and proof.methodUnchanged and P.isForceSelected[0]==false and P.forceSelectedType[0]=='original-mode'
 and P._BrowseElapsedMs[0]==17.25 and P._ForceSwitchIntent[0]==nil and P._HasNearbyCorpses[0]==nil)
assert(proof.globals.isForceSelected.expected.present and not proof.globals.isForceSelected.actual.value)
assert(not proof.globals._HasNearbyCorpses.expected.present and not proof.globals._HasNearbyCorpses.actual.present)
print('WAREHOUSE_WALKING_INSTALLED_LOCK_PASS native_look_selection=true public_manual_lock=true exact_restore=true')
