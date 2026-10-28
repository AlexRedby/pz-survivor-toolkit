local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true and getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable SP CartTestArea required')
require 'TimedActions/ISTimedActionQueue'
local area,p=assert(CartTestArea),assert(getPlayer())
assert(area.ready and CartLabKey and CartLabSelectScenes and cartLabDrive and cartLabGait and cartLabHeading and cartLabSteeringHeading and cartLabFrame and cartLabPoseHeading,'CartLab bootstrap required')
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
p:setPerkLevelDebug(Perks.Sprinting,10);p:getXp():setXPToLevel(Perks.Sprinting,10)
local cases={
 {name='shopping-cart',kind='SaucedCarts.ShoppingCart'},
 {name='wooden-wheelbarrow',kind='SaucedWheelbarrow.WheelbarrowWood'},
 {name='metal-wheelbarrow',kind='SaucedWheelbarrow.WheelbarrowMetal'},
}
cases=CartLabSelectScenes(cases)
if config.controlsExtended then
 assert(config.controlsExtended==true and #cases==1 and cases[1].name=='shopping-cart','Extended controls require only shopping-cart')
 assert(not p:isTimedActionInstant(),'Native action durations required')
 require 'SaucedCarts/ContextMenu'
 require 'ISUI/ISContextMenu'
 require 'ISUI/ISInventoryPaneContextMenu'
 require 'ISUI/ISWorldObjectContextMenu'
end
local phases={
 {name='forward-0',drive=1,gait=0,duration=1000,pose=0},
 {name='forward-angle',drive=1,gait=0,duration=1000,pose=2.1},
 {name='left-held',drive=5,gait=1,duration=4000,pose=0},
 {name='left-release',drive=1,gait=0,duration=600},
 {name='right-held',drive=8,gait=1,duration=4000,pose=0},
 {name='right-release',drive=1,gait=0,duration=600},
 {name='pivot-left',drive=2,gait=0,duration=1300,pose=0},
 {name='pivot-right',drive=3,gait=0,duration=1300,pose=0},
 {name='pivot-release',drive=0,gait=0,duration=700},
 {name='reverse',drive=4,gait=0,duration=1200,pose=.8},
 {name='reverse-left',drive=6,gait=0,duration=1500,pose=.8},
 {name='reverse-right',drive=7,gait=0,duration=1500,pose=.8},
 {name='moving-forward',drive=1,gait=0,duration=1000,pose=1.3},
 {name='moving-reverse',drive=4,gait=0,duration=1800},
 {name='run',drive=1,gait=1,duration=1000,pose=1.3},
 {name='run-stop',drive=0,gait=0,duration=1200},
 {name='sprint',drive=1,gait=2,duration=1000,pose=1.3},
 {name='sprint-stop',drive=0,gait=0,duration=1500},
}
if config.controlsExtended then
 for _,phase in ipairs({
  {name='correction-left',drive=5,gait=0,duration=180,pose=0,cadence=25},
  {name='correction-left-release',drive=1,gait=0,duration=600},
  {name='correction-right',drive=8,gait=0,duration=180,pose=0,cadence=25},
  {name='correction-right-release',drive=1,gait=0,duration=600},
  {name='correction-stop',drive=0,gait=0,duration=900},
 }) do phases[#phases+1]=phase end
end
local index,step,since,videoStart,sample,lastSample=0,0,0,0,0,0
local item,id,cargoItem,cargoID,cargoWeight,mode,gaitSeen
local actionPhase,actionSince,actionProgressed,actionTypeSeen,tailSince
local actionProgressSamples,boundAction,boundNative,boundDuration,boundLuaDuration
local beginAction
local function queue() return ISTimedActionQueue.getTimedActionQueue(p).queue end
local function terminal() return #queue()==0 and p:getCharacterActions():isEmpty() and not p:hasPath() end
local function encode(row)
 local out={}
 for key,value in pairs(row) do
  if type(value)=='string' then value='"'..value:gsub('[%z\1-\31\\"]',function(c) return string.format('\\u%04x',string.byte(c)) end)..'"'
  elseif type(value)=='number' then assert(value==value and math.abs(value)<math.huge,'Nonfinite controls evidence');value=tostring(value)
  else assert(type(value)=='boolean','Invalid controls evidence');value=tostring(value) end
  out[#out+1]='"'..key..'":'..value
 end
 return '{'..table.concat(out,',')..'}'
end
local function ownership()
 local queue=ISTimedActionQueue.getTimedActionQueue(p).queue
 assert(#queue==0 and p:getCharacterActions():isEmpty() and not p:hasPath(),'Controls must not enqueue actions/path')
 assert(item:getID()==id and item:getFullType()==cases[index].kind and item:getContainer()==p:getInventory() and not item:getWorldItem(),'Controls changed cart owner/identity')
 assert(p:getPrimaryHandItem()==item and p:getSecondaryHandItem()==item,'Controls lost exact cart hands')
 local contents=item:getInventory():getItems()
 assert(contents:size()==1 and contents:get(0)==cargoItem and contents:get(0):getID()==cargoID and math.abs(item:getInventory():getCapacityWeight()-cargoWeight)<.001,'Controls changed cargo identity/weight')
 local count=0;local inventory=p:getInventory():getItems()
 for i=0,inventory:size()-1 do if inventory:get(i):getID()==id then count=count+1 end end
 assert(count==1,'Controls duplicated cart inventory identity')
 area.checkPosition(p)
 return count
end
local function position(heading)
 p:setX(area.x);p:setY(area.y);p:setZ(area.z);p:setNextX(area.x);p:setNextY(area.y);p:setLastX(area.x);p:setLastY(area.y)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow();cartLabPoseHeading(heading)
end
local function record(now)
 print('[CART_CONTROLS] SAMPLE '..encode({case=cases[index].name,phase=phases[step].name,sample=sample,
  elapsed=now-since,frame=cartLabFrame(),x=p:getX(),y=p:getY(),heading=cartLabHeading(),acceptedHeading=cartLabSteeringHeading()}))
 sample=sample+1;lastSample=now
end
local function startPhase(now)
 local phase=phases[step]
 if phase.pose~=nil then position(phase.pose) end
 p:getStats():reset(CharacterStat.ENDURANCE)
 since=now;sample=0;gaitSeen=false;mode='drive'
 cartLabGait(phase.gait);cartLabDrive(phase.drive);record(now)
end
local function nextPhase(now)
 step=step+1
 if step>#phases then
  cartLabDrive(0);cartLabGait(0)
  if config.controlsExtended then beginAction('drop',now)
  else assert(toolkitVideoStop(),'Video stop rejected');mode='finish';since=now end
  return
 end
 if phases[step].pose~=nil then cartLabDrive(0);cartLabGait(0);mode='settle';since=now
 else startPhase(now) end
end
local function actionSnapshot(now)
 assert(item:getID()==id and item:getFullType()==cases[index].kind,'Action changed cart identity')
 local contents=item:getInventory():getItems()
 assert(contents:size()==1 and contents:get(0)==cargoItem and contents:get(0):getID()==cargoID and math.abs(item:getInventory():getCapacityWeight()-cargoWeight)<.001,'Action changed cargo identity/weight')
 local inv,worldCount,worldID=0,0,-1
 local inventory=p:getInventory():getItems()
 for i=0,inventory:size()-1 do if inventory:get(i):getID()==id then assert(inventory:get(i)==item,'Duplicate inventory cart object');inv=inv+1 end end
 for x=math.floor(area.x)-24,math.floor(area.x)+24 do for y=math.floor(area.y)-24,math.floor(area.y)+24 do
  local objects=assert(getCell():getGridSquare(x,y,area.z),'Controls action pad unloaded'):getWorldObjects()
  for i=0,objects:size()-1 do
   local world=objects:get(i);local found=world:getItem()
   if found and found:getID()==id then
    assert(found==item and item:getWorldItem()==world,'Duplicate world cart object');worldCount=worldCount+1;worldID=found:getID()
   end
  end
 end end
 assert(inv<=1 and worldCount<=1 and inv+worldCount==1,'Action lost/duplicated cart ownership')
 local action=queue()[1]
 local started=action and action:isStarted() or false
 local nativeStarted=started and action.action~=nil
 local progress=action and action:getJobDelta() or 0
 local expected=actionPhase=='drop' and 'ToolkitWoodCartSetdown' or 'ToolkitWoodCartPickup'
 local duration=action and action.Type==expected and action:getDuration() or 0
 local nativeTime=action and action.action and action.action:getTime() or 0
 assert(#queue()<=2 and p:getCharacterActions():size()<=1,'Controls action queue bounds exceeded')
 for _,queued in ipairs(queue()) do
  assert(queued.character==p,'Controls action actor changed')
  if queued.Type==expected then
   assert(actionPhase=='drop' and queued.item==item or actionPhase=='pickup' and queued.itemId==id,'Controls action cart binding changed')
   boundAction=boundAction or queued
   assert(queued==boundAction,'Controls native action identity changed')
  else
   assert(actionPhase=='pickup' and queued.Type=='ISWalkToTimedActionF' and queued.toolkitWoodCartItem==item,'Unexpected controls native action')
  end
 end
 if action then
  assert(action.Type==expected or actionPhase=='pickup' and action.Type=='ISWalkToTimedActionF','Unexpected controls native action')
  if action.Type==expected then
   assert(action.character==p and (actionPhase=='drop' and action.item==item or actionPhase=='pickup' and action.itemId==id),'Controls action cart binding changed')
   assert(type(duration)=='number' and duration==duration and duration>1 and duration<math.huge
    and type(action.maxTime)=='number' and action.maxTime==action.maxTime and action.maxTime>=duration and action.maxTime<math.huge,
    'Controls native action duration changed')
   boundDuration=boundDuration or duration;assert(duration==boundDuration,'Controls gameplay duration changed')
   if nativeStarted then
    boundNative=boundNative or action.action;assert(action.action==boundNative,'Controls native action identity changed')
    boundLuaDuration=boundLuaDuration or action.maxTime;assert(action.maxTime==boundLuaDuration,'Controls started Lua duration changed')
    -- Stock create() applies physiological modifiers to Lua maxTime. The native
    -- LuaTimedActionNew bridge uses Double.intValue, truncating positive fractions.
    assert(nativeTime>1 and nativeTime==math.floor(action.maxTime),'Controls native duration differs from gameplay duration')
   end
   if nativeStarted and progress>0 and progress<1 then actionProgressed=true;actionTypeSeen=action.Type end
  end
 end
 area.checkPosition(p,item:getWorldItem() and item or nil)
 return {case=cases[index].name,phase=actionPhase,kind=item:getFullType(),wall=now,frame=cartLabFrame(),elapsed=now-actionSince,
  id=id,cargoID=cargoID,cargoWeight=cargoWeight,primaryID=p:getPrimaryHandItem() and p:getPrimaryHandItem():getID() or -1,
  secondaryID=p:getSecondaryHandItem() and p:getSecondaryHandItem():getID() or -1,inventoryCount=inv,worldCount=worldCount,worldID=worldID,
  containerOwned=item:getContainer()==p:getInventory(),hasWorldItem=item:getWorldItem()~=nil,luaActions=#queue(),nativeActions=p:getCharacterActions():size(),hasPath=p:hasPath(),
  x=p:getX(),y=p:getY(),z=p:getZ(),actionType=action and action.Type or '',started=started,nativeStarted=nativeStarted,
  progress=progress,nativeMaxTime=nativeTime,luaMaxTime=action and action.maxTime or 0,duration=duration,
  progressed=actionProgressed==true,actionTypeSeen=actionTypeSeen or '',settledElapsed=tailSince and now-tailSince or 0}
end
local function actionEvent(name,now,row)
 row=row or actionSnapshot(now)
 if name=='SAMPLE' and row.actionType==(actionPhase=='drop' and 'ToolkitWoodCartSetdown' or 'ToolkitWoodCartPickup')
  and row.nativeStarted and row.progress>0 and row.progress<1 then actionProgressSamples=actionProgressSamples+1 end
 print('[CART_CONTROLS_ACTION] '..name..' '..encode(row));lastSample=now
end
local function actionEndpoint(now,row)
 row=row or actionSnapshot(now)
 assert(terminal(),'Controls action left queues/path')
 if actionPhase=='drop' then
  assert(row.worldCount==1 and row.inventoryCount==0 and row.hasWorldItem and row.worldID==id and row.primaryID==-1 and row.secondaryID==-1 and not row.containerOwned,'Drop did not transfer exact cart to world')
 else
  assert(row.worldCount==0 and row.inventoryCount==1 and not row.hasWorldItem and row.primaryID==id and row.secondaryID==id and row.containerOwned,'Pickup did not retain exact cart in both hands')
 end
end
local function findOption(context,predicate)
 local selected
 for _,option in ipairs(context.options) do
  local found=predicate(option) and option or nil
  if option.subOption then found=findOption(context:getSubMenu(option.subOption),predicate) or found end
  if found then assert(not selected,'Ambiguous controls menu option');selected=found end
 end
 return selected
end
beginAction=function(phase,now)
 assert(terminal(),'Cannot begin controls action with queued work')
 actionPhase=phase;actionSince=now;since=now;actionProgressed=false;actionTypeSeen=nil;tailSince=nil
 actionProgressSamples=0;boundAction=nil;boundNative=nil;boundDuration=nil;boundLuaDuration=nil
 actionEvent('BEGIN',now)
 local context,option
 if phase=='drop' then
  -- Sauced removes inventory Unequip; vanilla's world DropNamedItem retains this callback.
  local square=assert(p:getCurrentSquare(),'Native drop menu square missing')
  local floor=assert(square:getFloor(),'Native drop menu floor missing')
  assert(floor:getSquare()==square,'Native drop menu floor changed')
  context=assert(ISWorldObjectContextMenu.createMenu(p:getPlayerNum(),{floor},50,50,false),'Native drop menu missing')
  option=findOption(context,function(o) return o.onSelect==ISInventoryPaneContextMenu.onUnEquip
   and type(o.target)=='table' and #o.target==1 and o.target[1]==item and o.param1==p:getPlayerNum() end)
 else
  local world=assert(item:getWorldItem(),'Pickup target missing')
  local objects={world};context=ISContextMenu.get(p:getPlayerNum(),50,50)
  triggerEvent('OnFillWorldObjectContextMenu',p:getPlayerNum(),context,objects,false)
  option=findOption(context,function(o) return (o.name==getText('UI_SaucedCarts_PushCart') or o.name=='Push Cart')
   and o.target==objects and o.param1==p:getPlayerNum() and o.param2==world end)
 end
 assert(option and option.onSelect and not option.notAvailable,'Actual controls menu option unavailable')
 context:hideAndChildren()
 option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,option.param6,option.param7,option.param8,option.param9,option.param10)
 assert(not terminal() and queue()[1],'Actual menu callback queued no action')
 mode='action';actionEvent('QUEUED',now)
end
local function nextCase()
 index=index+1;step=0
 if index>#cases then
  cartLabDrive(-1);cartLabGait(0);Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  print('[CART_CONTROLS] ALL_COMPLETE cases='..#cases);print('[WOOD_BANK] ALL_COMPLETE cases='..#cases);return
 end
 if p:getPrimaryHandItem() and p:getPrimaryHandItem():getFullType()==cases[index].kind and p:getPrimaryHandItem():getInventory():getCapacityWeight()>0 then CartLabKey(Keyboard.KEY_F5) end
 for _=1,3 do
  if p:getPrimaryHandItem() and p:getPrimaryHandItem():getFullType()==cases[index].kind then break end
  CartLabKey(Keyboard.KEY_F5)
 end
 item=assert(p:getPrimaryHandItem(),'Fixture cart missing');assert(item:getFullType()==cases[index].kind,'Fixture cart type mismatch')
 assert(item:getInventory():getCapacityWeight()==0,'Expected new empty fixture cart')
 local cargo=assert(item:getInventory():AddItem('Base.Log'));cargo:setActualWeight(1);cargo:setCustomWeight(true)
 id=item:getID();cargoItem=cargo;cargoID=cargo:getID();cargoWeight=item:getInventory():getCapacityWeight();ownership()
 videoStart=getTimestampMs()
 assert(toolkitVideoStart(config.videoRoot..'/controls-'..cases[index].name..'-'..videoStart,config.ffmpeg),'Video start rejected')
 print('[WOOD_BANK] CASE '..cases[index].name..' wall='..videoStart);nextPhase(videoStart)
end
local function tick()
 local now=getTimestampMs();local video=toolkitVideoStatus()
 assert(video.state~='failed','Controls video failed: '..tostring(video.error))
 if mode~='action' and mode~='action-tail' then ownership() end
 assert(now-since<(mode=='action' and 15000 or 10000),'Controls phase timed out: '..tostring(actionPhase or phases[step] and phases[step].name))
 if mode=='finish' then
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE '..cases[index].name..' wall='..videoStart..' file='..video.file..' frames='..video.frames..' seconds='..video.seconds)
   nextCase()
  end
 elseif mode=='action' then
  local row=actionSnapshot(now)
  if terminal() then
   assert(actionProgressed and actionProgressSamples>=2,'Controls action completed without started native progress samples')
   actionEndpoint(now,row);tailSince=now;mode='action-tail';actionEvent('SAMPLE',now,row)
  elseif now-lastSample>=50 then actionEvent('SAMPLE',now,row) end
 elseif mode=='action-tail' then
  local row=actionSnapshot(now);actionEndpoint(now,row)
  if now-lastSample>=50 then actionEvent('SAMPLE',now,row) end
  if now-tailSince>=700 then
   actionEvent('COMPLETE',now,row)
   if actionPhase=='drop' then beginAction('pickup',now)
   else assert(toolkitVideoStop(),'Video stop rejected');mode='finish';since=now end
  end
 elseif mode=='settle' then if now-since>=600 then startPhase(now) end
 elseif mode=='drive' then
  local phase=phases[step]
  if phase.gait==0 and not p:isRunning() and not p:isSprinting() or phase.gait==1 and p:isRunning() or phase.gait==2 and p:isSprinting() then gaitSeen=true end
  if now-lastSample>=(phase.cadence or 100) or now-since>=phase.duration then record(now) end
  if now-since>=phase.duration then
   print('[CART_CONTROLS] PHASE '..encode({case=cases[index].name,kind=item:getFullType(),phase=phase.name,
    id=id,cargoID=cargoID,cargoWeight=cargoWeight,primaryID=p:getPrimaryHandItem():getID(),secondaryID=p:getSecondaryHandItem():getID(),
    inventoryCount=ownership(),worldCount=0,luaActions=0,nativeActions=p:getCharacterActions():size(),hasPath=p:hasPath(),
    drive=phase.drive,gait=phase.gait,gaitSeen=gaitSeen,elapsed=now-since,samples=sample}))
   nextPhase(now)
  end
 end
end
WoodPrototypeTick=function()
 local ok,why=pcall(tick)
 if not ok then
  cartLabDrive(-1);cartLabGait(0);toolkitVideoStop();Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  print('[CART_CONTROLS] FAIL '..tostring(why));print('[WOOD_BANK] FAIL '..tostring(why))
 end
end
print('[WOOD_BANK] RUN_STARTED')
print('[CART_CONTROLS] SCOPE SP physical keyboard controls with light cargo; animation/mesh equivalence not assessed')
nextCase();Events.OnTick.Add(WoodPrototypeTick)
