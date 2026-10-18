local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true and getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable SP CartTestArea required')
require 'SaucedCarts/ContextMenu'
require 'ISUI/ISContextMenu'
require 'ISUI/ISInventoryPaneContextMenu'
require 'TimedActions/ISTimedActionQueue'
local area,p=assert(CartTestArea),assert(getPlayer())
assert(area.ready and CartLabKey and CartLabSelectScenes and cartLabDrive and cartLabGait and cartLabPoseHeading,'CartLab bootstrap required')
assert(not p:isTimedActionInstant(),'Native action durations required')
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
p:setPerkLevelDebug(Perks.Sprinting,10);p:getXp():setXPToLevel(Perks.Sprinting,10)
local cases={
 {name='shopping-cart',kind='SaucedCarts.ShoppingCart'},
 {name='wooden-wheelbarrow',kind='SaucedWheelbarrow.WheelbarrowWood'},
 {name='metal-wheelbarrow',kind='SaucedWheelbarrow.WheelbarrowMetal'},
}
cases=CartLabSelectScenes(cases)
local phases={'inventory-equip','walk','run','sprint','drop-near','pickup-near','drop-far','pickup-far','drop-repeat','pickup-repeat'}
local index,step,since,phaseSince=0,0,0,0
local item,id,cargoIDs,cargoWeight,mode,startX,startY,approachDistance,gaitSeen,videoStart
local function queue() return ISTimedActionQueue.getTimedActionQueue(p).queue end
local function terminal() return #queue()==0 and p:getCharacterActions():isEmpty() and not p:hasPath() end
local function encode(row)
 local out={}
 for key,value in pairs(row) do
  if type(value)=='string' then value='"'..value:gsub('[%z\1-\31\\"]',function(c) return string.format('\\u%04x',string.byte(c)) end)..'"'
  elseif type(value)=='number' then assert(value==value and math.abs(value)<math.huge,'Nonfinite variant evidence');value=tostring(value)
  else assert(type(value)=='boolean','Invalid variant evidence');value=tostring(value) end
  out[#out+1]='"'..key..'":'..value
 end
 return '{'..table.concat(out,',')..'}'
end
local function cargo()
 local contents=item:getInventory():getItems();local ids={}
 for i=0,contents:size()-1 do
  local child=contents:get(i)
  ids[#ids+1]=tostring(child:getID())..':'..child:getFullType()..':'..tostring(child:getActualWeight())
 end
 table.sort(ids)
 return table.concat(ids,'|'),item:getInventory():getCapacityWeight()
end
local function ownership(ground)
 assert(item:getID()==id and item:getFullType()==cases[index].kind,'Cart identity changed')
 local ids,weight=cargo()
 assert(ids==cargoIDs and math.abs(weight-cargoWeight)<.001,'Cart cargo identity/weight changed')
 local count=0;local inventory=p:getInventory():getItems()
 for i=0,inventory:size()-1 do if inventory:get(i):getID()==id then count=count+1 end end
 local worldCount=0
 for x=math.floor(area.x)-24,math.floor(area.x)+24 do for y=math.floor(area.y)-24,math.floor(area.y)+24 do
  local square=assert(getCell():getGridSquare(x,y,area.z),'Variant pad unloaded')
  local objects=square:getWorldObjects()
  for i=0,objects:size()-1 do
   local found=objects:get(i):getItem()
   if found and found:getID()==id then assert(found==item,'Duplicate cart object identity');worldCount=worldCount+1 end
  end
 end end
 local primary,secondary=p:getPrimaryHandItem(),p:getSecondaryHandItem()
 if ground then
  local world=assert(item:getWorldItem(),'Dropped cart has no world object')
  assert(world:getItem()==item and worldCount==1 and count==0 and primary~=item and secondary~=item,'Drop did not transfer exact cart to world')
  assert(primary==nil and secondary==nil,'Drop left occupied hands')
 else
  assert(primary==item and secondary==item and count==1 and worldCount==0 and not item:getWorldItem() and item:getContainer()==p:getInventory(),'Pickup/equip did not retain exact cart in both hands')
 end
 area.checkPosition(p,ground and item or nil)
 assert(terminal(),'Variant phase did not terminate both queues/path')
 return count,worldCount
end
local function place(x,y)
 assert(terminal(),'Cannot position fixture during action')
 p:setX(x);p:setY(y);p:setZ(area.z);p:setNextX(x);p:setNextY(y);p:setLastX(x);p:setLastY(y)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow()
 cartLabPoseHeading(math.pi*1.25)
end
local function findPush(context)
 for _,option in ipairs(context.options) do
  if option.name==getText('UI_SaucedCarts_PushCart') or option.name=='Push Cart' then return option end
  if option.subOption then local found=findPush(context:getSubMenu(option.subOption));if found then return found end end
 end
end
local function push(world)
 local context=ISContextMenu.get(p:getPlayerNum(),50,50)
 if world then triggerEvent('OnFillWorldObjectContextMenu',p:getPlayerNum(),context,{world},false)
 else triggerEvent('OnFillInventoryObjectContextMenu',p:getPlayerNum(),context,{item}) end
 local option=assert(findPush(context),'Actual SaucedCarts Push Cart menu option missing')
 assert(option.onSelect and not option.notAvailable,'Push Cart menu option unavailable')
 context:hideAndChildren()
 option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,option.param6,option.param7,option.param8,option.param9,option.param10)
 assert(not terminal(),'Actual menu callback queued no action')
 local first=queue()[1]
 print('[CART_VARIANT] QUEUED phase='..phases[step]..' type='..tostring(first and first.Type)..' player='..p:getX()..','..p:getY()..' world='..tostring(world and world:getWorldPosX())..','..tostring(world and world:getWorldPosY())..' reachable='..tostring(world and p:getSquare():canReachTo(world:getSquare()))..' hands='..tostring(p:getPrimaryHandItem() and p:getPrimaryHandItem():getID()))
end
local function receipt(now)
 local phase=phases[step];local inventoryCount,worldCount=ownership(phase:sub(1,5)=='drop-')
 local row={case=cases[index].name,kind=item:getFullType(),phase=phase,id=id,cargoIDs=cargoIDs,cargoWeight=cargoWeight,
  primaryID=p:getPrimaryHandItem() and p:getPrimaryHandItem():getID() or -1,
  secondaryID=p:getSecondaryHandItem() and p:getSecondaryHandItem():getID() or -1,
  inventoryCount=inventoryCount,worldCount=worldCount,luaActions=#queue(),nativeActions=p:getCharacterActions():size(),hasPath=p:hasPath(),
  elapsed=now-phaseSince,distance=math.sqrt((p:getX()-startX)^2+(p:getY()-startY)^2),gaitSeen=gaitSeen==true,approachDistance=approachDistance or 0}
 if phase=='walk' or phase=='run' or phase=='sprint' then
  assert(row.distance>=.25 and row.gaitSeen,'Native '..phase..' did not move with requested gait')
 end
 print('[CART_VARIANT] PHASE '..encode(row))
end
local function beginPhase(now)
 step=step+1
 if step>#phases then assert(toolkitVideoStop(),'Video stop rejected');mode='finish';phaseSince=now;return end
 phaseSince=now;startX,startY=p:getX(),p:getY();gaitSeen=false;approachDistance=0
 local phase=phases[step]
 print('[CART_VARIANT] BEGIN case='..cases[index].name..' phase='..phase..' id='..id)
 if phase=='inventory-equip' then push(nil);mode='action'
 elseif phase=='walk' or phase=='run' or phase=='sprint' then
  p:getStats():reset(CharacterStat.ENDURANCE)
  cartLabGait(phase=='sprint' and 2 or phase=='run' and 1 or 0);cartLabDrive(1);mode='move'
 elseif phase:sub(1,5)=='drop-' then
  ISInventoryPaneContextMenu.onUnEquip({item},p:getPlayerNum())
  assert(not terminal(),'Native onUnEquip queued no drop action');mode='action'
 else
  local world=assert(item:getWorldItem(),'Pickup target missing')
  local x,y=world:getWorldPosX(),world:getWorldPosY()
  if phase=='pickup-near' then place(x-.5,y)
  elseif phase=='pickup-far' then place(x-2.25,y) end
  startX,startY=p:getX(),p:getY();approachDistance=math.sqrt((x-startX)^2+(y-startY)^2)
  push(world);mode='action'
 end
end
local function nextCase()
 index=index+1;step=0
 if index>#cases then
  cartLabDrive(-1);cartLabGait(0);Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  print('[CART_VARIANT] ALL_COMPLETE cases='..#cases)
  print('[WOOD_BANK] ALL_COMPLETE cases='..#cases);return
 end
 assert(terminal(),'Previous variant left an action/path')
 for _=1,3 do
  if p:getPrimaryHandItem() and p:getPrimaryHandItem():getFullType()==cases[index].kind then break end
  CartLabKey(Keyboard.KEY_F5)
 end
 item=assert(p:getPrimaryHandItem(),'Fixture cart missing');assert(item:getFullType()==cases[index].kind,'Fixture cart type mismatch')
 assert(item:getInventory():getCapacityWeight()==0,'Expected empty newly created fixture cart')
 local child=assert(item:getInventory():AddItem('Base.Log'),'Fixture cargo missing')
 child:setActualWeight(1);child:setCustomWeight(true)
 id=item:getID();cargoIDs,cargoWeight=cargo()
 -- Only initial fixture setup bypasses gameplay actions; all subsequent transitions use real menu callbacks.
 p:removeFromHands(item);SaucedCarts.clearCartPose(p)
 place(area.x,area.y)
 since=getTimestampMs();mode='settle'
end
local function tick()
 local now=getTimestampMs()
 if mode=='settle' then
  if now-since<1000 then return end
  area.check(p)
  assert(toolkitVideoStart(config.videoRoot..'/variants-'..cases[index].name..'-'..now,config.ffmpeg),'Video start rejected')
  videoStart=now;print('[WOOD_BANK] CASE '..cases[index].name..' wall='..now);beginPhase(now);return
 end
 local video=toolkitVideoStatus();assert(video.state~='failed','Variant video failed: '..tostring(video.error))
 assert(now-phaseSince<15000,'Variant phase timed out: '..tostring(phases[step])..' mode='..tostring(mode))
 if mode=='finish' then
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE '..cases[index].name..' wall='..videoStart..' file='..video.file..' frames='..video.frames..' seconds='..video.seconds)
   nextCase()
  end
 elseif mode=='action' then
  if terminal() and now-phaseSince>50 then receipt(now);beginPhase(now) end
 elseif mode=='move' then
  local phase=phases[step]
  if phase=='walk' and not p:isRunning() and not p:isSprinting() or phase=='run' and p:isRunning() or phase=='sprint' and p:isSprinting() then gaitSeen=true end
  if now-phaseSince>=1800 then cartLabDrive(0);cartLabGait(0);mode='stop';since=now end
 elseif mode=='stop' and now-since>=700 then receipt(now);beginPhase(now) end
end
WoodPrototypeTick=function()
 local ok,why=pcall(tick)
 if not ok then
  cartLabDrive(-1);cartLabGait(0);toolkitVideoStop();Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  print('[CART_VARIANT] FAIL case='..tostring(cases[index] and cases[index].name)..' phase='..tostring(phases[step])..' '..tostring(why))
  print('[WOOD_BANK] FAIL '..tostring(why))
 end
end
print('[WOOD_BANK] RUN_STARTED')
print('[CART_VARIANT] SCOPE SP native usability; wooden mesh/IK and cosmetic equivalence not assessed')
nextCase();Events.OnTick.Add(WoodPrototypeTick)
