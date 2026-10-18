local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true and config.vehicles==true,'Disposable vehicle bank required')
local function absolute(name)
 local value=config[name]
 assert(type(value)=='string' and (value:sub(1,1)=='/' or value:match('^%a:[/\\]') or value:sub(1,2)=='\\\\'),'Absolute '..name..' required')
 return value
end
local videoRoot,ffmpeg=absolute('videoRoot'),absolute('ffmpeg')
assert(getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable single-player CartTestArea required')
local p=assert(getPlayer(),'Live actor required');local area=assert(CartTestArea)
assert(not p:isDead() and area.ready and area.setVehicle and CartLabSelectScenes and cartLabFootprint,'Vehicle fixture/bootstrap missing')
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
p:setFemale(false);p:getDescriptor():setFemale(false)
p:clearWornItems();p:getHumanVisual():setHairModel('CrewCut');p:getHumanVisual():setBeardModel('')
for _,name in ipairs({'Base.Tshirt_DefaultTEXTURE_TINT','Base.Trousers_JeanBaggy','Base.Shoes_TrainerTINT'}) do
 local item=assert(p:getInventory():AddItem(name),name);p:setWornItem(item:getBodyLocation(),item)
end
p:resetModel();p:setPerkLevelDebug(Perks.Sprinting,10);p:getXp():setXPToLevel(Perks.Sprinting,10)
local cases={}
local controls={}
for _,yaw in ipairs({0,45}) do
 for _,side in ipairs({'left','right'}) do controls[#controls+1]={yaw=yaw,spec='slide-'..side,name='yaw'..yaw..'-slide-'..side,bare=true} end
end
for _,full in ipairs({false,true}) do for _,yaw in ipairs({0,45}) do for _,spec in ipairs({'front','slide-left','slide-right'}) do
 cases[#cases+1]={full=full,yaw=yaw,spec=spec,name='male-'..(full and 'full-' or 'empty-')..'vehicle-yaw'..yaw..'-'..spec}
end end end
cases=CartLabSelectScenes(cases)
local index,phase,mode,since,stage,lastSample,videoSince=0,'control','next',0,0,0,0
local current,layout
local angles={225,135,315,45,180,90,0,270}
local function key(angle)
 local best,score=1,-2
 for i,degrees in ipairs(angles) do local dot=math.cos(angle-math.rad(degrees));if dot>score then best=i;score=dot end end
 return best
end
local function pose(x,y,heading)
 p:setX(x);p:setY(y);p:setZ(area.z);p:setNextX(x);p:setNextY(y);p:setLastX(x);p:setLastY(y)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow();cartLabPoseHeading(heading);area.checkPosition(p)
end
local function equip(full,bare)
 for i=1,3 do
  local item=p:getPrimaryHandItem();if item and item:getFullType()=='SaucedWheelbarrow.WheelbarrowWood' then break end
  CartLabKey(Keyboard.KEY_F5)
 end
 assert(p:getPrimaryHandItem() and p:getPrimaryHandItem():getFullType()=='SaucedWheelbarrow.WheelbarrowWood','Wrong wooden cart')
 CartLabKey(Keyboard.KEY_F7);CartLabKey(Keyboard.KEY_F7)
 local item=p:getPrimaryHandItem()
 if (item:getInventory():getCapacityWeight()>0)~=full then CartLabKey(Keyboard.KEY_F6) end
 item=p:getPrimaryHandItem()
 local weight=item:getInventory():getCapacityWeight()
 assert(full and math.abs(weight-item:getInventory():getEffectiveCapacity(p))<.01 or not full and weight==0,'Wrong cargo')
 if bare then CartLabKey(Keyboard.KEY_F7);assert(not p:getPrimaryHandItem() and not p:getSecondaryHandItem(),'Control must be bare') end
end
local function setup()
 cartLabDrive(0);cartLabGait(0);area.clearVehicles(p)
 index=index+1
 if phase=='control' and index>#controls then phase='case';index=1 end
 current=(phase=='control' and controls or cases)[index]
 if not current then
  print('[CART_VEHICLE] CLEANUP_COMPLETE');print('[WOOD_BANK] ALL_COMPLETE cases='..#cases)
  cartLabDrive(-1);Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil;return
 end
 equip(current.full==true,current.bare==true)
 -- Spawn actors away from the body before each exact owned vehicle is constructed.
 pose(area.x,area.y,math.pi)
 layout=area.setVehicle(p,current.yaw)
 local direction=current.spec=='slide-right' and -1 or 1
 local slide=current.spec~='front'
 local tangent=slide and -direction*.5 or 0
 local normal=layout.width+(current.bare and .9 or 2.15)
 -- Full cargo needs held input after the rear cap clears and the wooden arc turns inward.
 current.extra=current.full and slide and 3000 or 0
 current.heading=math.atan2(-layout.ny+(slide and direction*layout.ty or 0),-layout.nx+(slide and direction*layout.tx or 0))
 current.drive=key(current.heading)
 pose(layout.x+layout.nx*normal+layout.tx*tangent,layout.y+layout.ny*normal+layout.ty*tangent,current.heading)
 current.startX=p:getX();current.startY=p:getY()
 stage=0;mode='settle';since=getTimestampMs()+1000
end
local function sample(now,elapsed)
 local prefix=current.bare and '[CART_VEHICLE_CONTROL_SAMPLE]' or '[CART_VEHICLE_SAMPLE]'
 print(prefix..' case='..current.name..' wall='..now..' elapsed='..elapsed..' x='..p:getX()..' y='..p:getY()..' heading='..cartLabHeading()
  ..' drive='..(stage==1 and current.drive or stage==3 and current.reverse or 0)..' bare='..tostring(current.bare==true)
  ..' run='..tostring(p:isRunning())..' sprint='..tostring(p:isSprinting())..' tracks='..cartLabTracks()..' '..cartLabVehicleState())
 if not current.bare then
  print('[WOOD_BANK_SAMPLE] case='..current.name..' wall='..now..' elapsed='..elapsed..' x='..p:getX()..' y='..p:getY()
   ..' run='..tostring(p:isRunning())..' sprint='..tostring(p:isSprinting())..' skill='..p:getPerkLevel(Perks.Sprinting)..' speed='..p:getVariableFloat('WalkSpeed',0)
   ..' drive='..(stage==1 and current.drive or stage==3 and current.reverse or 0)..' requestedGait=0 stepX='..p:getVariableFloat('ToolkitCartStepX',0)
   ..' stepY='..p:getVariableFloat('ToolkitCartStepY',0)..' pace='..p:getVariableFloat('ToolkitCartLegPace',0)..' wheelPhase='..cartLabWheelPhase()
   ..' bank='..cartLabBank()..' reversal='..cartLabReversal()..' ramp='..cartLabRamp()..' stationary='..cartLabStationary()..' tracks='..cartLabTracks())
  print('[CART_FOOTPRINT_STATE] case='..current.name..' wall='..now..' elapsed='..elapsed..' '..cartLabFootprint())
 end
end
local function tick()
 area.checkPosition(p);if mode=='next' then setup();return end
 cartLabVehicleCheck()
 local now=getTimestampMs()
 if mode=='settle' then
  if now<since then return end
  area.check(p)
  current.startX=p:getX();current.startY=p:getY()
  if not current.bare then assert(toolkitVideoStart(videoRoot..'/'..current.name..'-0',ffmpeg),'Video start rejected') end
  since=getTimestampMs();videoSince=since;lastSample=0;mode='record'
  print((current.bare and '[CART_VEHICLE_CONTROL] START ' or '[WOOD_BANK] CASE ')..current.name..(current.bare and '' or ' attempt=0')..' wall='..since)
  print('[CART_VEHICLE_LAYOUT] case='..current.name..' yaw='..current.yaw..' x='..layout.x..' y='..layout.y..' z='..layout.z
   ..' nx='..layout.nx..' ny='..layout.ny..' tx='..layout.tx..' ty='..layout.ty..' width='..layout.width..' length='..layout.length
   ..' startX='..current.startX..' startY='..current.startY..' '..cartLabVehicleState())
  return
 end
 if mode=='finish' then
  local video=toolkitVideoStatus();assert(video.state~='failed','Video failed: '..tostring(video.error))
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE '..current.name..' wall='..videoSince..' file='..tostring(video.file)..' frames='..tostring(video.frames)..' seconds='..tostring(video.seconds));mode='next'
  end
  return
 end
 local elapsed=now-since
 if elapsed>=(current.bare and 7000 or 12000+current.extra) then
  cartLabDrive(0)
  if current.bare then print('[CART_VEHICLE_CONTROL] COMPLETE '..current.name..' wall='..now);mode='next'
  else assert(toolkitVideoStop(),'Video stop rejected');mode='finish' end
  return
 end
 local nextStage=elapsed>=11000+current.extra and 4 or elapsed>=9300+current.extra and 3 or elapsed>=8500+current.extra and 2 or elapsed>=1000 and 1 or 0
 if current.bare then nextStage=elapsed>=1000 and 1 or 0 end
 if nextStage~=stage then
  stage=nextStage
  if stage==3 then current.reverse=key(cartLabHeading()+math.pi) end
  local drive=stage==1 and current.drive or stage==3 and current.reverse or 0
  cartLabDrive(drive);cartLabGait(0)
  if not current.bare then print('[WOOD_RAMP_EVENT] case='..current.name..' elapsed='..elapsed..' gait=0 drive='..drive) end
 end
 if now-lastSample>=25 then lastSample=now;sample(now,elapsed) end
end
WoodPrototypeTick=function()
 local ok,why=pcall(tick)
 if not ok then
  cartLabDrive(-1);cartLabGait(0);pcall(toolkitVideoStop)
  Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  local cleaned,cleanupWhy=pcall(area.clearVehicles,p)
  print('[WOOD_BANK] FAIL '..tostring(why)..(cleaned and '' or '; vehicle cleanup failed: '..tostring(cleanupWhy)))
 end
end
print('[WOOD_BANK] RUN_STARTED')
getCore():setAutoZoom(0,false);for i=1,16 do getCore():doZoomScroll(0,-1) end
Events.OnTick.Add(WoodPrototypeTick)
