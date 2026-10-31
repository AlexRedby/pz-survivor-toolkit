-- Motion loop runs against engine/action doubles whose item reads are forbidden.
local root=ProjectRoot..'/tests/native_queue/warehouse-walking/'
local clock,measuring,profileBegins,profileEnds=0,false,0,0
function getTimestampMs()return clock end
function getGameSpeed()return 1 end
function getCore()return {getScreenWidth=function()return 1280 end,getScreenHeight=function()return 900 end}end
Translator={getLanguage=function()return {name=function()return 'EN'end}end}
BehaviorResult={Failed='failed',Succeeded='succeeded'}
local inventory={getItems=function()assert(not measuring,'item enumeration/read in measured loop');return {size=function()return 1 end}end}
local aggregate={getItems=function()assert(not measuring,'aggregate scan/read in measured loop');return {size=function()return 3 end}end}
local pages={}
CleanUI_Clean_ISInventoryPage={};CleanUI_Clean_ISInventoryPane={}
CleanUI_Vanilla_ISInventoryPage={};CleanUI_Vanilla_ISInventoryPane={}
local cleanMode=true
function CleanUI_isCleanInventoryUIEnabled()return cleanMode end
for i=1,2 do
 local page={visible=true,isCollapsed=false,pin=true,x=i==1 and 30 or 640,y=50,w=590,h=740,inventoryPane={mode='details'}}
 function page:getX()return self.x end
 function page:getY()return self.y end
 function page:getWidth()return self.w end
 function page:getHeight()return self.h end
 function page:getIsVisible()return self.visible end
 function page:setVisible(value)self.visible=value end
 function page:setWidth(value)self.w=value end
 function page:setHeight(value)self.h=value end
 function page:setX(value)self.x=value end
 function page:setY(value)self.y=value end
 function page:refreshBackpacks()end
 function page:setNewContainer(value)self.inventoryPane.inventory=value end
 function page:onBackpackClick(button)self.inventoryPane.inventory=button.inventory end
 function page:collapse()self.isCollapsed=true end
 function page:collapseNow()self.isCollapsed=true end
 function page.inventoryPane:getIsVisible()return self.visible~=false end
 page.inventoryPane.inventory=i==1 and inventory or aggregate
 setmetatable(page,CleanUI_Clean_ISInventoryPage);setmetatable(page.inventoryPane,CleanUI_Clean_ISInventoryPane);pages[i]=page
end
pages[2].backpacks={{inventory=aggregate}}
package.preload.WarehouseWorkloadUI=function()return {pages=function()return pages end,configure=function()
 for _,page in ipairs(pages)do page.visible=true;page.isCollapsed=false;page.inventoryPane.mode='details'end
end}end
package.preload.WarehouseWalkingProfile=function()return {
 begin=function(index,num)assert(index==1 and num==0 and not measuring);profileBegins=profileBegins+1 end,
 finish=function()profileEnds=profileEnds+1;return {phase=1,metrics={{name='pane.refreshContainer',calls=1}}}end}
end
local Proximity={invName='proximityInv',itemContainer={[0]=aggregate},isForceSelected={},forceSelectedType={},_ForceSwitchIntent={},_BrowseElapsedMs={},_HasNearbyCorpses={}}
function Proximity.GetItemContainer()return aggregate end
function Proximity.GetCurrentForceContainer()return aggregate end
function Proximity.updateForceSelected(num,value)Proximity.isForceSelected[num]=value;Proximity.forceSelectedType[num]=Proximity.invName end
package.preload['BetterContainers/Proximity']=function()return Proximity end
package.preload['TimedActions/WalkToTimedAction']=function()return true end
package.preload['TimedActions/ISTimedActionQueue']=function()return true end
local player={x=98.5,y=100.5,z=0}
function player:getPlayerNum()return 0 end
function player:getInventory()return inventory end
function player:getX()return self.x end
function player:getY()return self.y end
function player:getZ()return self.z end
function player:isPlayerMoving()return self.moving==true end
function player:isTimedActionInstant()return false end
local queue={queue={}}
function player:hasTimedActions()return #queue.queue>0 end
ISTimedActionQueue={getTimedActionQueue=function()return queue end,add=function(action)queue.queue={action};queue.current=action end}
ISWalkToTimedAction={new=function(_,actor,goal)
 return {Type='ISWalkToTimedAction',player=actor,goal=goal,update=function()end}
end}
local cell={}
function cell:getGridSquare(x,y,z)return {getX=function()return x end,getY=function()return y end,getZ=function()return z end,canStand=function()return true end,isFree=function()return true end}end
function getCell()return cell end
local N=dofile(root..'client/WarehouseWalkingNative.lua')
local savedLock=N.saveLock(player)
for _,state in ipairs({'own-only','both-hidden','loot-collapsed','both-open'})do
 N.configure(player,{paneMode='clean',paneState=state});assert(N.matches(player,state))
end
local phase={index=1,paneState='both-open',paneMode='clean',itemsPerCrate=1}
local function traverse(run)
 measuring=true
 for _=1,5000 do
  clock=clock+100;local action=queue.current
  local target=action.goal:getX()+.5;local diff=target-player.x
  if math.abs(diff)<=.05 then player.x=target;player.moving=false;action.result=BehaviorResult.Succeeded;queue.queue={}
  else player.x=player.x+(diff>0 and .05 or -.05);player.moving=true end
  if N.sample(run)then measuring=false;return end
 end;error('motion did not finish')
end
local run=N.begin(player,phase,{x=100,y=100,z=0});traverse(run)
local receipt=N.finish(run)
assert(receipt.environmentInitial.aggregateItems==3 and receipt.environmentFinal.aggregateItems==3)
assert(receipt.motion.elapsedMs>=12000 and receipt.motion.legs>=4 and receipt.motion.legs%2==0)
assert(receipt.motion.distance>=14 and receipt.motion.tileChanges>=12 and receipt.motion.movementTicks>=30)
assert(receipt.motion.manualAggregateLock and receipt.motion.lockMethodUnchanged)
assert(receipt.motion.uiIdentityUnchanged and receipt.motion.actualPaneMode=='clean')
assert(receipt.motion.teleports==0 and receipt.motion.nativeActions==receipt.motion.legs and receipt.motion.sourceMethodsUnchanged)
assert(profileBegins==1 and profileEnds==1 and receipt.profile.metrics[1].calls==1)
assert(receipt.motion.tickIntervalsMs.samples>=60 and receipt.motion.tickIntervalsMs.max==100 and receipt.motion.tickIntervalsMs.p95==100)
assert(math.floor(player.x)==98,'route did not finish at the fixed original endpoint')
-- A measured jump cannot masquerade as native tile travel.
run=N.begin(player,phase,{x=100,y=100,z=0});player.x=player.x+2;measuring=true
assert(not pcall(N.sample,run),'teleport admitted as native motion');measuring=false
queue.queue={};N.abortProfile(run);assert(profileEnds==2)
player.x=98.5;run=N.begin(player,phase,{x=100,y=100,z=0});pages[2].visible=false
local accepted,problem=pcall(N.sample,run)
assert(not accepted and tostring(problem):find('loot.visible expected=true actual=false',1,true),'hidden pane drift lacked exact diagnostic');pages[2].visible=true;queue.queue={};N.abortProfile(run)
run=N.begin(player,phase,{x=100,y=100,z=0});traverse(run)
run.actions[1].action.update=function()end
assert(not pcall(N.finish,run),'changed native method accepted')
-- Geometry/binding are part of the bounded live pane-state contract.
pages[1].x=31;assert(not N.matches(player,'both-open'));pages[1].x=30
pages[2].inventoryPane.inventory={};assert(not N.matches(player,'both-open'));pages[2].inventoryPane.inventory=aggregate
-- Every scalar gate identifies its field and actual/expected values without item reads.
local function diagnostic(object,key,value,expected)
 local old=object[key];object[key]=value;measuring=true
 local matches,detail=N.matches(player,'both-open');measuring=false;object[key]=old
 assert(not matches and detail==expected,'scalar diagnostic differs: '..tostring(detail))
end
diagnostic(pages[1],'x',31,'own.x expected=30 actual=31')
diagnostic(pages[2],'y',51,'loot.y expected=50 actual=51')
diagnostic(pages[1],'w',591,'own.width expected=590 actual=591')
diagnostic(pages[2],'h',741,'loot.height expected=740 actual=741')
diagnostic(pages[1].inventoryPane,'mode','icons','own.mode expected=details actual=icons')
diagnostic(pages[2].inventoryPane,'inventory',inventory,'loot.pane.inventory expected=native-aggregate actual=actor-root')
diagnostic(pages[1].inventoryPane,'inventory',{},'own.pane.inventory expected=actor-root actual=other-container')
diagnostic(pages[1],'visible',false,'own.visible expected=true actual=false')
diagnostic(pages[2],'visible',false,'loot.visible expected=true actual=false')
diagnostic(pages[1],'isCollapsed',true,'own.collapsed expected=false actual=true')
diagnostic(pages[2],'isCollapsed',true,'loot.collapsed expected=false actual=true')
diagnostic(pages[1].inventoryPane,'visible',false,'own.pane.visible expected=true actual=false')
diagnostic(pages[2].inventoryPane,'visible',false,'loot.pane.visible expected=true actual=false')
diagnostic(pages[1],'inventoryPane',nil,'own.pane expected=present actual=nil')
-- A replacement owner or actual CleanUI mode change fails even with identical geometry.
run=N.begin(player,phase,{x=100,y=100,z=0});cleanMode=false
accepted,problem=pcall(N.sample,run)
assert(not accepted and tostring(problem):find('walking actual UI mode changed: expected=true actual=false',1,true),'actual CleanUI mode drift diagnostic missing');cleanMode=true;queue.queue={};N.abortProfile(run)
run=N.begin(player,phase,{x=100,y=100,z=0});setmetatable(pages[1],CleanUI_Vanilla_ISInventoryPage)
accepted,problem=pcall(N.sample,run)
assert(not accepted and tostring(problem):find('own.pageClass expected=same actual=replaced',1,true),'page class drift diagnostic missing');setmetatable(pages[1],CleanUI_Clean_ISInventoryPage);queue.queue={};N.abortProfile(run)
run=N.begin(player,phase,{x=100,y=100,z=0});local previous=pages[2].inventoryPane;local replacement={}
for key,value in pairs(previous)do replacement[key]=value end;setmetatable(replacement,CleanUI_Clean_ISInventoryPane);pages[2].inventoryPane=replacement
accepted,problem=pcall(N.sample,run)
assert(not accepted and tostring(problem):find('loot.pane expected=same actual=replaced',1,true),'pane owner replacement diagnostic missing');pages[2].inventoryPane=previous;queue.queue={};N.abortProfile(run)
-- The manual lock is checked without repair on every native sample.
run=N.begin(player,phase,{x=100,y=100,z=0});Proximity.isForceSelected[0]=false
accepted,problem=pcall(N.sample,run);assert(not accepted and tostring(problem):find('manual aggregate lock disabled',1,true));Proximity.isForceSelected[0]=true;queue.queue={};N.abortProfile(run)
run=N.begin(player,phase,{x=100,y=100,z=0});local setter=Proximity.updateForceSelected;Proximity.updateForceSelected=function()end
accepted,problem=pcall(N.sample,run);assert(not accepted and tostring(problem):find('setter identity changed',1,true));Proximity.updateForceSelected=setter;queue.queue={};N.abortProfile(run)
run=N.begin(player,phase,{x=100,y=100,z=0});Proximity.forceSelectedType[0]='other'
accepted,problem=pcall(N.sample,run);assert(not accepted and tostring(problem):find('lock type changed',1,true));Proximity.forceSelectedType[0]=Proximity.invName;queue.queue={};N.abortProfile(run)
run=N.begin(player,phase,{x=100,y=100,z=0});Proximity.itemContainer[0]={}
accepted,problem=pcall(N.sample,run);assert(not accepted and tostring(problem):find('lock target changed',1,true));Proximity.itemContainer[0]=aggregate;queue.queue={};N.abortProfile(run)
N.restoreLock(player,savedLock);local proof=N.finishLockRestoration(player,savedLock)
assert(proof.restored and proof.methodUnchanged and not proof.globals.isForceSelected.expected.present and Proximity.isForceSelected[0]==nil)
-- Failure diagnostics identify the exact native leg and actor/goal coordinates.
N.configure(player,phase);run=N.begin(player,phase,{x=100,y=100,z=0});run.action.result=BehaviorResult.Failed
accepted,problem=pcall(N.sample,run)
assert(not accepted and tostring(problem):find('action=1 actor=(98.5,100.5,0) goal=(102,100,0)',1,true),'failed native action lacks route diagnostic');queue.queue={};N.abortProfile(run)
N.restoreLock(player,savedLock);N.finishLockRestoration(player,savedLock)
-- No source scanning may creep into the measured driver.
local source=assert(io.open(root..'client/ZZWarehouseWalking.lua')):read('*a')
local measure=assert(source:match("elseif R.stage=='measure'then(.-)elseif R.stage=='observed'then"))
local sampleAt=assert(measure:find('N.sample',1,true));local finishAt=assert(measure:find('N.finish',1,true));local snapshotAt=assert(measure:find('F.snapshot',1,true))
assert(sampleAt<finishAt and finishAt<snapshotAt,'full identity scans entered the profiled interval')
