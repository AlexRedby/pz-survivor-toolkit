require 'TimedActions/WalkToTimedAction'
require 'TimedActions/ISTimedActionQueue'
local U=require 'WarehouseWorkloadUI'
local Profile=require 'WarehouseWalkingProfile'
local Proximity=require 'BetterContainers/Proximity'
local N={}
local methods={'new','start','update','perform','complete','stop','getDuration','isValid','isValidStart'}
local lockFields={'isForceSelected','forceSelectedType','_ForceSwitchIntent','_BrowseElapsedMs','_HasNearbyCorpses'}
local lockMethods={}
local function slot(value)return {present=value~=nil,value=value}end
local function lockGlobals(player,saved)
 local num=player:getPlayerNum()
 for _,field in ipairs(lockFields)do assert(type(Proximity[field])=='table','native BC lock state missing: '..field);Proximity[field][num]=saved.values[field]end
end
function N.saveLock(player)
 local saved={values={},pages={},cleanMode=CleanUI_isCleanInventoryUIEnabled(),method=assert(Proximity.updateForceSelected,'native BC manual lock setter missing')}
 local num=player:getPlayerNum();lockMethods[num]=saved.method
 for _,field in ipairs(lockFields)do assert(type(Proximity[field])=='table','native BC lock state missing: '..field);saved.values[field]=Proximity[field][num]end
 for i,page in ipairs(U.pages(player))do saved.pages[i]={tempForceSelectUnlock=page.tempForceSelectUnlock}end
 return saved
end
function N.restoreLockGlobals(player,saved)
 if not saved then return end
 lockGlobals(player,saved)
 for i,page in ipairs(U.pages(player))do page.tempForceSelectUnlock=saved.pages[i].tempForceSelectUnlock end
end
function N.restoreLock(player,saved)
 assert(Proximity.updateForceSelected==saved.method,'native BC manual lock setter changed before restore')
 -- Recreate the original mode first so its new live pages receive their saved
 -- unlock flags before U.restore runs any owner refresh with original options.
 local num=player:getPlayerNum();Proximity.isForceSelected[num]=nil;Proximity._ForceSwitchIntent[num]=nil
 if CleanUI_isCleanInventoryUIEnabled()~=saved.cleanMode then CleanUI_setCleanInventoryUIEnabled(saved.cleanMode)end
 N.restoreLockGlobals(player,saved)
end
function N.finishLockRestoration(player,saved)
 -- Native restoration refreshes update scalar presence caches; restore those
 -- exact original slots after the final owner refresh, keeping live UI caches.
 N.restoreLockGlobals(player,saved)
 local proof={restored=true,methodUnchanged=Proximity.updateForceSelected==saved.method,globals={},pages={}}
 assert(proof.methodUnchanged,'native BC manual lock setter changed during restore')
 local num=player:getPlayerNum()
 for _,field in ipairs(lockFields)do local actual=Proximity[field][num];local expected=saved.values[field]
  assert(actual==expected,'native BC lock slot not restored: '..field);proof.globals[field]={expected=slot(expected),actual=slot(actual)}
 end
 for i,page in ipairs(U.pages(player))do local actual=page.tempForceSelectUnlock;local expected=saved.pages[i].tempForceSelectUnlock
  assert(actual==expected,'native BC page unlock not restored');proof.pages[i]={tempForceSelectUnlock={expected=slot(expected),actual=slot(actual)}}
 end
 return proof
end
local function assertLock(player,method,aggregate)
 local num=player:getPlayerNum()
 assert(Proximity.updateForceSelected==method,'native BC manual lock setter identity changed')
 assert(Proximity.isForceSelected[num]==true,'native BC manual aggregate lock disabled')
 assert(Proximity.forceSelectedType[num]==Proximity.invName,'native BC manual aggregate lock type changed')
 assert(aggregate and Proximity.itemContainer[num]==aggregate,'native BC manual aggregate lock target changed')
end

function N.idle(player)return #ISTimedActionQueue.getTimedActionQueue(player).queue==0 and not player:hasTimedActions()end
function N.state(player)
 local pages=U.pages(player);local row={}
 for i,page in ipairs(pages)do row[i]={visible=page:getIsVisible(),collapsed=page.isCollapsed==true,pin=page.pin==true,x=page:getX(),y=page:getY(),w=page:getWidth(),h=page:getHeight(),paneVisible=page.inventoryPane:getIsVisible()}end
 return row
end
local function mismatch(field,expected,actual)
 return false,field..' expected='..tostring(expected)..' actual='..tostring(actual)
end
local function binding(value,root,aggregate)
 if value==root then return 'actor-root'elseif value==aggregate then return 'native-aggregate'elseif value==nil then return 'nil'end
 return 'other-container'
end
function N.matches(player,state)
 local pages=U.pages(player);local root=player:getInventory();local aggregate=Proximity.itemContainer[player:getPlayerNum()]
 for i=1,2 do
  local page=pages[i];local label=i==1 and'own'or'loot'
  if not page then return mismatch(label..'.owner','present','nil')end
  local pane=page.inventoryPane;if not pane then return mismatch(label..'.pane','present','nil')end
  local x=page:getX();local expectedX=i==1 and 30 or 640
  if x~=expectedX then return mismatch(label..'.x',expectedX,x)end
  local y=page:getY();if y~=50 then return mismatch(label..'.y',50,y)end
  local width=page:getWidth();if width~=590 then return mismatch(label..'.width',590,width)end
  local height=page:getHeight();if height~=740 then return mismatch(label..'.height',740,height)end
  if pane.mode~='details'then return mismatch(label..'.mode','details',pane.mode)end
  local expectedInventory=i==1 and root or aggregate
  if pane.inventory~=expectedInventory then return mismatch(label..'.pane.inventory',binding(expectedInventory,root,aggregate),binding(pane.inventory,root,aggregate))end
  local expectedVisible=i==1 and state~='both-hidden'or i==2 and(state=='both-open'or state=='loot-collapsed')
  local visible=page:getIsVisible();if visible~=expectedVisible then return mismatch(label..'.visible',expectedVisible,visible)end
  local expectedCollapsed=i==2 and state=='loot-collapsed';local collapsed=page.isCollapsed==true
  if collapsed~=expectedCollapsed then return mismatch(label..'.collapsed',expectedCollapsed,collapsed)end
  local paneVisible=pane:getIsVisible();if not paneVisible then return mismatch(label..'.pane.visible',true,paneVisible)end
 end
 return true
end
local function assertMatches(player,state,message)
 local matches,detail=N.matches(player,state)
 if not matches then error(message..': '..detail)end
end
function N.configure(player,phase)
 U.configure(player,phase.paneMode)
 local pages=U.pages(player);local own,loot=pages[1],pages[2]
 for i,page in ipairs(pages)do page:setWidth(590);page:setHeight(740);page:setX(i==1 and 30 or 640);page:setY(50)end
 own:setNewContainer(player:getInventory());own:refreshBackpacks();loot:refreshBackpacks()
 local aggregate=Proximity.GetItemContainer(player:getPlayerNum());local selected=false
 for _,button in ipairs(loot.backpacks or {})do if button.inventory==aggregate then loot:onBackpackClick(button);selected=true;break end end
 assert(selected and loot.inventoryPane.inventory==aggregate,'walking native aggregate not selected')
 local setter=assert(lockMethods[player:getPlayerNum()],'native BC lock baseline missing')
 assert(Proximity.updateForceSelected==setter,'native BC manual lock setter identity changed')
 setter(player:getPlayerNum(),true);assertLock(player,setter,aggregate)
 if phase.paneState=='loot-collapsed'then loot:collapse();loot:collapseNow()end
 if phase.paneState=='own-only'or phase.paneState=='both-hidden'then loot:setVisible(false)end
 if phase.paneState=='both-hidden'then own:setVisible(false)end
 assertMatches(player,phase.paneState,'walking requested pane state unavailable')
end
function N.environment(player,origin,phase)
 local core=getCore();local row={width=core:getScreenWidth(),height=core:getScreenHeight(),gameSpeed=getGameSpeed(),
  language=Translator.getLanguage():name(),originX=origin.x,originY=origin.y,originZ=origin.z,actorRootItems=player:getInventory():getItems():size(),
  aggregateItems=Proximity.itemContainer[player:getPlayerNum()]:getItems():size(),actorRootWeight=player:getInventory():getCapacityWeight(),
  actorWornItems=player:getWornItems():size(),actorPrimaryEmpty=player:getPrimaryHandItem()==nil,actorSecondaryEmpty=player:getSecondaryHandItem()==nil}
 assert(row.actorRootItems==8 and row.actorWornItems==0 and row.actorPrimaryEmpty and row.actorSecondaryEmpty,'walking deterministic actor load differs')
 assert(row.aggregateItems==3*phase.itemsPerCrate,'walking endpoint nearby aggregate load differs: expected='..tostring(3*phase.itemsPerCrate)..' actual='..tostring(row.aggregateItems))
 assert(row.width==1280 and row.height==900 and row.gameSpeed==1,'walking viewport/game speed differs')
 return row
end
local function walk(run)
 run.motion.nativeActions=run.motion.nativeActions+1
 local x=run.motion.nativeActions%2==1 and run.origin.x+2 or run.origin.x-2
 local goal=assert(getCell():getGridSquare(x,run.origin.y,run.origin.z),'walking target unloaded')
 assert(goal:canStand()and goal:isFree(false),'walking aisle blocked')
 local action=ISWalkToTimedAction:new(run.player,goal);assert(action.Type=='ISWalkToTimedAction','native walk action required')
 local source={};for _,key in ipairs(methods)do source[key]=action[key]end
 run.actions[#run.actions+1]={action=action,source=source};run.action=action;run.goal=goal;ISTimedActionQueue.add(action)
end
local function owners(player,mode)
 local expectedPage=mode=='clean'and CleanUI_Clean_ISInventoryPage or CleanUI_Vanilla_ISInventoryPage
 local expectedPane=mode=='clean'and CleanUI_Clean_ISInventoryPane or CleanUI_Vanilla_ISInventoryPane
 assert(expectedPage and expectedPane,'walking actual UI classes unavailable')
 local saved={}
 for i,page in ipairs(U.pages(player))do
  local pane=page.inventoryPane;local pageClass,paneClass=getmetatable(page),getmetatable(pane)
  assert(pageClass==expectedPage and paneClass==expectedPane,'walking actual page/pane class differs')
  saved[i]={page=page,pane=pane,pageClass=pageClass,paneClass=paneClass}
 end
 return saved
end
local function assertOwners(run)
 local actual=CleanUI_isCleanInventoryUIEnabled();local expected=run.phase.paneMode=='clean'
 if actual~=expected then error('walking actual UI mode changed: expected='..tostring(expected)..' actual='..tostring(actual))end
 for i,page in ipairs(U.pages(run.player))do local saved=run.uiOwners[i]
  local label=i==1 and'own'or'loot'
  local field
  if page~=saved.page then field='page'elseif page.inventoryPane~=saved.pane then field='pane'
  elseif getmetatable(page)~=saved.pageClass then field='pageClass'elseif getmetatable(page.inventoryPane)~=saved.paneClass then field='paneClass'end
  if field then error('walking page/pane owner identity changed: '..label..'.'..field..' expected=same actual=replaced')end
 end
end
function N.begin(player,phase,origin)
 assert(N.idle(player)and not player:isPlayerMoving(),'walking interval start is not quiescent')
 assertMatches(player,phase.paneState,'walking interval start pane state differs')
 assert(not player:isTimedActionInstant(),'native walking timing is instant')
 local run={player=player,phase=phase,origin=origin,actions={},lockSetter=lockMethods[player:getPlayerNum()],aggregate=Proximity.itemContainer[player:getPlayerNum()],uiOwners=owners(player,phase.paneMode),x=player:getX(),y=player:getY(),z=player:getZ(),
  ticks={},tickCount=0,maxTickMs=0,motion={legs=0,distance=0,tileChanges=0,movementTicks=0,nativeActions=0,teleports=0},beforeState=N.state(player)}
 -- These calls occur on the fixture's tick, outside all measured native UI callbacks.
 assertOwners(run);assertLock(player,run.lockSetter,run.aggregate);run.environmentInitial=N.environment(player,origin,phase)
 Profile.begin(phase.index,player:getPlayerNum());run.profileActive=true
 run.began=getTimestampMs();run.lastTick=run.began
 local ok,problem=pcall(walk,run)
 if not ok then Profile.finish();run.profileActive=false;error(problem)end
 return run
end
-- Bounded scalar reads only. Never enumerate crates, items, rows or ID sets here.
function N.sample(run)
 local player=run.player;local m=run.motion;local timestamp=getTimestampMs();local elapsed=timestamp-run.began
 local tickMs=math.max(0,timestamp-run.lastTick);run.lastTick=timestamp;run.tickCount=run.tickCount+1
 run.ticks[(run.tickCount-1)%4096+1]=tickMs;run.maxTickMs=math.max(run.maxTickMs,tickMs)
 assert(elapsed<60000,'native walking interval deadline exceeded')
 assertOwners(run);assertLock(player,run.lockSetter,run.aggregate)
 assertMatches(player,run.phase.paneState,'walking pane state drifted')
 assert(getGameSpeed()==1 and getCore():getScreenWidth()==1280 and getCore():getScreenHeight()==900,'walking viewport/game speed drifted')
 local x,y,z=player:getX(),player:getY(),player:getZ();local distance=math.sqrt((x-run.x)^2+(y-run.y)^2)
 assert(distance<1.5 and z==run.z,'position jumped during walking interval')
 m.distance=m.distance+distance
 if math.floor(x)~=math.floor(run.x)or math.floor(y)~=math.floor(run.y)then m.tileChanges=m.tileChanges+1 end
 if player:isPlayerMoving()then m.movementTicks=m.movementTicks+1 end
 run.x=x;run.y=y
 if run.action.result==BehaviorResult.Failed then
  error('native walking action failed: action='..tostring(m.nativeActions)..' actor=('..tostring(x)..','..tostring(y)..','..tostring(z)..') goal=('..tostring(run.goal:getX())..','..tostring(run.goal:getY())..','..tostring(run.goal:getZ())..')')
 end
 if not N.idle(player)then return end
 assert(run.action.result==BehaviorResult.Succeeded,'native walk drained without success')
 assert(math.floor(x)==run.goal:getX()and math.floor(y)==run.goal:getY(),'native walk missed target')
 m.legs=m.legs+1
 if m.legs>=4 and m.legs%2==0 and elapsed>=12000 then
  assert(m.distance>=14 and m.tileChanges>=12 and m.movementTicks>=30,'insufficient native walking movement')
  m.elapsedMs=elapsed;return true
 end
 walk(run)
end
function N.finish(run)
 assert(N.idle(run.player),'walking profile finish before native drain')
 local ok,profile=pcall(Profile.finish);run.profileActive=false;assert(ok,profile)
 assertOwners(run);assertLock(run.player,run.lockSetter,run.aggregate)
 assert(type(profile)=='table','walking profile returned no metrics')
 for _,entry in ipairs(run.actions)do for _,key in ipairs(methods)do assert(entry.action[key]==entry.source[key],'native walking source method changed')end end
 table.sort(run.ticks);local n=#run.ticks;assert(n>=60,'insufficient measured tick samples')
 run.motion.tickIntervalsMs={samples=n,totalSamples=run.tickCount,p50=run.ticks[math.ceil(n*.50)],p95=run.ticks[math.ceil(n*.95)],max=run.maxTickMs,retainedWindow='most-recent-4096'}
 run.motion.sourceMethodsUnchanged=true;run.motion.uiIdentityUnchanged=true
 run.motion.manualAggregateLock=true;run.motion.lockMethodUnchanged=true
 run.motion.actualPaneMode=CleanUI_isCleanInventoryUIEnabled()and'clean'or'vanilla'
 return {motion=run.motion,profile=profile,beforeState=run.beforeState,afterState=N.state(run.player),environmentInitial=run.environmentInitial,environmentFinal=N.environment(run.player,run.origin,run.phase),warmupMs=2000}
end
function N.abortProfile(run)
 if run and run.profileActive then
  local ok,result=pcall(Profile.finish);run.profileActive=false
  return {stopped=ok,result=ok and result or nil,error=not ok and tostring(result)or nil}
 end
end
return N
