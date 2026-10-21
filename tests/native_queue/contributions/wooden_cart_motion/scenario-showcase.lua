local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true and getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable SP CartTestArea required')
require 'SaucedCarts/ContextMenu'
require 'ISUI/ISContextMenu'
require 'ISUI/ISInventoryPaneContextMenu'
require 'TimedActions/ISTimedActionQueue'
local area,p=assert(CartTestArea),assert(getPlayer())
assert(area.ready and CartLabKey and CartLabSelectScenes and cartLabDrive and cartLabGait and cartLabPoseHeading and cartLabSteeringHeading and toolkitVideoStart and toolkitVideoStatus and toolkitVideoStop,'Cart showcase bootstrap required')
assert(not p:isTimedActionInstant(),'Native action durations required')
assert(type(config.videoRoot)=='string' and config.videoRoot:sub(1,1)=='/' and type(config.ffmpeg)=='string' and config.ffmpeg:sub(1,1)=='/','Absolute video paths required')
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
-- Keep the longer metal wheelbarrow fully visible during camera follow at Sprint.
getCore():doZoomScroll(0,1)
p:setPerkLevelDebug(Perks.Sprinting,10);p:getXp():setXPToLevel(Perks.Sprinting,10)
local cases={
 {name='wooden-wheelbarrow',kind='SaucedWheelbarrow.WheelbarrowWood'},
 {name='metal-wheelbarrow',kind='SaucedWheelbarrow.WheelbarrowMetal'},
 {name='shopping-cart',kind='SaucedCarts.ShoppingCart'},
}
cases=CartLabSelectScenes(cases)
local phases={
 {name='walk-straight',drive=1,gait=0,duration=5500,minimum=.25},
 {name='walk-left',drive=5,gait=0,duration=2200,minimum=.15,turn=.08},
 {name='walk-right',drive=8,gait=0,duration=3800,minimum=.15,turn=.08},
 {name='run-turn',drive=5,gait=1,duration=4000,minimum=.25,turn=.08},
 {name='run-brake',drive=0,gait=0,duration=1100,minimum=0},
 {name='sprint-turn',drive=8,gait=2,duration=3700,minimum=.25,turn=.08},
 {name='sprint-brake',drive=0,gait=0,duration=1100,minimum=0},
}
local index,step,mode,since,videoStart=0,0,'setup',0,0
local item,id,cargoIDs,cargoWeight,startX,startY,lastX,lastY,distance,gaitSeen,turnStart,lastHeading,turnAccum,pickupType
local function queue() return ISTimedActionQueue.getTimedActionQueue(p).queue end
local function terminal() return #queue()==0 and p:getCharacterActions():isEmpty() and not p:hasPath() end
local function encode(row)
 local out={}
 for key,value in pairs(row) do
  if type(value)=='string' then value='"'..value:gsub('[%z\1-\31\\"]',function(c)return string.format('\\u%04x',string.byte(c))end)..'"'
  elseif type(value)=='number' then assert(value==value and math.abs(value)<math.huge,'Nonfinite showcase evidence');value=tostring(value)
  else assert(type(value)=='boolean','Invalid showcase evidence');value=tostring(value) end
  out[#out+1]='"'..key..'":'..value
 end
 return '{'..table.concat(out,',')..'}'
end
local function cargo()
 local contents=item:getInventory():getItems();local entries={}
 for i=0,contents:size()-1 do
  local child=contents:get(i)
  entries[#entries+1]=tostring(child:getID())..':'..child:getFullType()..':'..tostring(child:getActualWeight())
 end
 table.sort(entries);return table.concat(entries,'|'),item:getInventory():getCapacityWeight()
end
local function inventoryCount()
 local count,contents=0,p:getInventory():getItems()
 for i=0,contents:size()-1 do if contents:get(i):getID()==id then count=count+1 end end
 return count
end
local function worldCount()
 local world=item and item:getWorldItem()
 if not world then return 0 end
 assert(world:getItem()==item and world:getSquare(),'Cart world identity lost')
 local objects=world:getSquare():getWorldObjects();local count=0
 for i=0,objects:size()-1 do if objects:get(i)==world then count=count+1 end end
 return count
end
local function ownership(ground)
 assert(item:getID()==id and item:getFullType()==cases[index].kind,'Cart identity changed')
 local ids,weight=cargo()
 assert(ids==cargoIDs and math.abs(weight-cargoWeight)<.001,'Cart cargo identity/weight changed')
 local inv,world=inventoryCount(),worldCount()
 local primary,secondary=p:getPrimaryHandItem(),p:getSecondaryHandItem()
 if ground then
  assert(item:getWorldItem() and world==1 and inv==0 and primary~=item and secondary~=item,'Putdown did not transfer exact cart to world')
  assert(primary==nil and secondary==nil,'Putdown left occupied hands')
 else
  assert(primary==item and secondary==item and inv==1 and world==0 and not item:getWorldItem() and item:getContainer()==p:getInventory(),'Pickup did not retain exact cart in both hands')
 end
 assert(terminal(),'Showcase phase left native actions/path')
 area.checkPosition(p,ground and item or nil)
 return inv,world
end
local function findPush(context)
 for _,option in ipairs(context.options) do
  if option.name==getText('UI_SaucedCarts_PushCart') or option.name=='Push Cart' then return option end
  if option.subOption then local found=findPush(context:getSubMenu(option.subOption));if found then return found end end
 end
end
local function pushWorld()
 local world=assert(item:getWorldItem(),'World pickup target missing')
 local context=ISContextMenu.get(p:getPlayerNum(),50,50)
 triggerEvent('OnFillWorldObjectContextMenu',p:getPlayerNum(),context,{world},false)
 local option=assert(findPush(context),'Actual SaucedCarts Push Cart menu option missing')
 assert(option.onSelect and not option.notAvailable,'World Push Cart unavailable')
 context:hideAndChildren()
 option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,option.param6,option.param7,option.param8,option.param9,option.param10)
 local action=assert(queue()[1],'World Push Cart queued no native action')
 assert(action.Type=='ISWalkToTimedActionF' or action.Type=='ISCartPickupAction' or action.Type=='ToolkitWoodCartPickup',
  'Unexpected native world pickup route: '..tostring(action.Type))
 pickupType=action.Type
 mode='pickup';since=getTimestampMs()
end
local function beginPhase(now)
 step=step+1
 if step>#phases then
  mode='putdown';since=now
  ISInventoryPaneContextMenu.onUnEquip({item},p:getPlayerNum())
  local action=assert(queue()[1],'Native putdown queued no action')
  assert(action.Type=='ToolkitWoodCartSetdown','Putdown was not dispatched to native cart action: '..tostring(action.Type))
  return
 end
 local phase=phases[step]
 since=now;startX,startY=p:getX(),p:getY();lastX,lastY=startX,startY;distance=0;gaitSeen=false
 turnStart=cartLabSteeringHeading();lastHeading=turnStart;turnAccum=0
 p:getStats():reset(CharacterStat.ENDURANCE)
 cartLabGait(phase.gait);cartLabDrive(phase.drive);mode='move'
 print('[CART_SHOWCASE] BEGIN '..encode({case=cases[index].name,phase=phase.name,wall=now,drive=phase.drive,gait=phase.gait}))
end
local function angleDelta(a,b) return math.atan2(math.sin(a-b),math.cos(a-b)) end
local function receipt(phaseName,now,ground,elapsed,phaseGait,phaseDrive,phaseDistance,seen,turn)
 local inv,world=ownership(ground)
 local row={case=cases[index].name,kind=item:getFullType(),phase=phaseName,id=id,cargoIDs=cargoIDs,cargoWeight=cargoWeight,
  primaryID=p:getPrimaryHandItem() and p:getPrimaryHandItem():getID() or -1,
  secondaryID=p:getSecondaryHandItem() and p:getSecondaryHandItem():getID() or -1,
  inventoryCount=inv,worldCount=world,luaActions=#queue(),nativeActions=p:getCharacterActions():size(),hasPath=p:hasPath(),
  elapsed=elapsed,distance=phaseDistance,gaitSeen=seen==true,drive=phaseDrive,gait=phaseGait,
  heading=cartLabSteeringHeading(),turnRadians=turn or 0,wall=now,nativeRoute=pickupType or ''}
 print('[CART_SHOWCASE] PHASE '..encode(row))
end
local function clearWorld()
 local world=item and item:getWorldItem()
 if world then
  local square=world:getSquare();square:transmitRemoveItemFromSquare(world);square:removeWorldObject(world);item:setWorldItem(nil)
 end
 if item then local container=item:getContainer();if container then container:Remove(item) end end
 item=nil
end
local function setup(now)
 assert(terminal(),'Previous showcase left native work')
 cartLabDrive(0);cartLabGait(0);clearWorld()
 for _=1,3 do
  local held=p:getPrimaryHandItem()
  if held and held:getFullType()==cases[index].kind then break end
  CartLabKey(Keyboard.KEY_F5)
 end
 item=assert(p:getPrimaryHandItem(),'Showcase fixture cart missing')
 assert(item:getFullType()==cases[index].kind,'Wrong fixture cart for '..cases[index].name..': '..item:getFullType())
 if item:getInventory():getCapacityWeight()>0 then CartLabKey(Keyboard.KEY_F6) end
 item=assert(p:getPrimaryHandItem(),'Showcase cart missing after emptying fixture')
 assert(item:getFullType()==cases[index].kind and item:getInventory():getCapacityWeight()==0,'Expected empty fixture cart')
 local child=assert(item:getInventory():AddItem('Base.Log'),'Fixture cargo missing')
 child:setActualWeight(1);child:setCustomWeight(true)
 id=item:getID();cargoIDs,cargoWeight=cargo()
 assert(cargoIDs~='' and cargoWeight>0,'Fixture cargo evidence missing')
 p:setX(area.x);p:setY(area.y);p:setZ(area.z);p:setNextX(area.x);p:setNextY(area.y);p:setLastX(area.x);p:setLastY(area.y)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow();cartLabPoseHeading(math.pi)
 area.check(p)
 -- Fixture staging uses the real native unequip route before recording begins.
 ISInventoryPaneContextMenu.onUnEquip({item},p:getPlayerNum())
 local action=assert(queue()[1],'Fixture native unequip queued no action')
 assert(action.Type=='ToolkitWoodCartSetdown','Fixture cart did not use native unequip/setdown')
 mode='fixture-drop';since=now
end
local function startRecording(now)
 local world=assert(item:getWorldItem(),'Initial native setdown did not produce a world cart')
 assert(world:getItem()==item and inventoryCount()==0,'Initial cart is not in the world')
 -- Place the sole actor near the handles before capture; every later movement is native.
 local x,y=world:getWorldPosX(),world:getWorldPosY()
 p:setX(x-.65);p:setY(y);p:setZ(area.z);p:setNextX(x-.65);p:setNextY(y);p:setLastX(x-.65);p:setLastY(y)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow();cartLabPoseHeading(0)
 area.checkPosition(p,item)
 assert(toolkitVideoStart(config.videoRoot..'/showcase-'..cases[index].name..'-'..now,config.ffmpeg),'Showcase video start rejected')
 videoStart=getTimestampMs();print('[WOOD_BANK] CASE '..cases[index].name..' wall='..videoStart)
 print('[CART_SHOWCASE] START '..encode({case=cases[index].name,kind=item:getFullType(),id=id,cargoIDs=cargoIDs,cargoWeight=cargoWeight,wall=videoStart}))
 pushWorld()
end
local function nextCase(now)
 cartLabDrive(0);cartLabGait(0);index=index+1;step=0
 if index>#cases then
  cartLabDrive(-1);Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  print('[WOOD_BANK] ALL_COMPLETE cases='..#cases);return
 end
 mode='setup'
end
local function tick()
 local now=getTimestampMs();local video=toolkitVideoStatus()
 assert(video.state~='failed','Showcase video failed: '..tostring(video.error))
 if mode~='setup' and mode~='fixture-drop' and mode~='recording-finish' then area.checkPosition(p,item and item:getWorldItem() and item or nil) end
 if mode=='setup' then setup(now)
 elseif mode=='fixture-drop' then
  assert(now-since<12000,'Native fixture unequip timed out')
  if terminal() and item:getWorldItem() then
   assert(item:getWorldItem():getItem()==item and inventoryCount()==0,'Native fixture unequip lost cart')
   startRecording(now)
  end
 elseif mode=='pickup' then
  assert(now-since<12000,'Native world pickup timed out')
  if terminal() and p:getPrimaryHandItem()==item then
   ownership(false);receipt('pickup',now,false,now-since,0,0,0,true,0);beginPhase(now)
  end
 elseif mode=='move' then
  local phase=phases[step]
  local x,y=p:getX(),p:getY();distance=distance+math.sqrt((x-lastX)^2+(y-lastY)^2);lastX,lastY=x,y
  local heading=cartLabSteeringHeading();turnAccum=turnAccum+angleDelta(heading,lastHeading);lastHeading=heading
  local gaitOK=phase.gait==0 and not p:isRunning() and not p:isSprinting() or phase.gait==1 and p:isRunning() or phase.gait==2 and p:isSprinting()
  if gaitOK then gaitSeen=true end
  local elapsed=now-since
  if elapsed>=phase.duration then
   local turn=math.abs(turnAccum)
   assert(distance>=phase.minimum,'Native '..phase.name..' distance too short: '..distance)
   assert(gaitSeen,'Native gait evidence missing for '..phase.name)
   if phase.turn then assert(turn>=phase.turn,'Native steering turn missing for '..phase.name..': '..turn) end
   receipt(phase.name,now,false,elapsed,phase.gait,phase.drive,distance,gaitSeen,turn)
   beginPhase(now)
  end
 elseif mode=='putdown' then
  assert(now-since<15000,'Native putdown timed out')
  if terminal() and item:getWorldItem() then
   receipt('putdown',now,true,now-since,0,0,0,true,0)
   mode='putdown-tail';since=now
  end
 elseif mode=='putdown-tail' then
  if now-since>=500 then
   assert(toolkitVideoStop(),'Showcase video stop rejected');mode='recording-finish';since=now
  end
 elseif mode=='recording-finish' then
  assert(now-since<15000,'Showcase video completion timed out')
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE '..cases[index].name..' wall='..videoStart..' file='..tostring(video.file)..' frames='..tostring(video.frames)..' seconds='..tostring(video.seconds))
   nextCase(now)
  end
 end
end
WoodPrototypeTick=function()
 local ok,why=pcall(tick)
 if not ok then
  cartLabDrive(0);cartLabGait(0);pcall(toolkitVideoStop);Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  print('[CART_SHOWCASE] FAIL case='..tostring(cases[index] and cases[index].name)..' phase='..tostring(mode)..' '..tostring(why))
  print('[WOOD_BANK] FAIL '..tostring(why))
 end
end
print('[WOOD_BANK] RUN_STARTED')
print('[CART_SHOWCASE] SCOPE SP continuous native world pickup, cart motion and native putdown; single actor')
index=1
Events.OnTick.Add(WoodPrototypeTick)
