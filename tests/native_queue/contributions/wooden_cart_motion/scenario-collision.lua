local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true,'CartMotionConfig.disposable must be true')
local function absolutePath(name)
 local value=config[name]
 assert(type(value)=='string' and value~='' and (value:sub(1,1)=='/' or value:match('^%a:[/\\]') or value:sub(1,2)=='\\\\'), 'CartMotionConfig.'..name..' must be an absolute path')
 return value
end
local videoRoot,ffmpeg=absolutePath('videoRoot'),absolutePath('ffmpeg')
local footprint=config.footprint==true
assert(getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable single-player CartTestArea save required')
local p=assert(getPlayer(),'Live actor required')
assert(not p:isDead() and CartTestArea and CartTestArea.ready,'Wait for BOOTSTRAP_READY')
assert(CartLabKey and CartLabHUD and cartLabDrive and cartLabGait and cartLabBank and cartLabRamp and cartLabTracks and cartLabReversal and cartLabStationary and cartLabPoseHeading and cartLabHeading and cartLabWheelPhase and CartTestArea.setObstacles and toolkitVideoStart and toolkitVideoStatus and toolkitVideoStop,'CartLab/video bridge missing')
assert(not footprint or cartLabFootprint,'Footprint diagnostics missing')
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
p:setFemale(false);p:getDescriptor():setFemale(false)
p:clearWornItems();p:getHumanVisual():setHairModel('CrewCut');p:getHumanVisual():setBeardModel('')
for _,name in ipairs({'Base.Tshirt_DefaultTEXTURE_TINT','Base.Trousers_JeanBaggy','Base.Shoes_TrainerTINT'}) do
 local item=assert(p:getInventory():AddItem(name),name)
 p:setWornItem(item:getBodyLocation(),item)
end
p:resetModel()

CartTestArea.check(p)
local climate=getClimateManager()
for _,index in ipairs({ClimateManager.FLOAT_FOG_INTENSITY,ClimateManager.FLOAT_PRECIPITATION_INTENSITY,ClimateManager.FLOAT_CLOUD_INTENSITY}) do
 local value=climate:getClimateFloat(index);value:setEnableAdmin(true);value:setAdminValue(0)
end
local kind='SaucedWheelbarrow.WheelbarrowWood'
local cases={}
for _,female in ipairs({false,true}) do
 for _,full in ipairs({false,true}) do
  for _,spec in ipairs({'wall-block','wall-slide','corner-pivot','passage'}) do
   local steps,yaw
   if spec=='wall-block' then
    steps={{1000,1,5},{6000,0,0},{7000,0,7},{9500,0,0}};yaw=math.pi/4
   elseif spec=='wall-slide' then
    steps={{1000,1,2},{6000,0,0},{7000,0,7},{9500,0,0}};yaw=0
   elseif spec=='corner-pivot' then
    steps={{1000,2,3},{4000,0,0},{5000,0,1},{8500,0,0}};yaw=-math.pi/2
   else
    steps={{1000,0,5},{4500,0,0},{5000,0,7},{9500,0,0}};yaw=math.pi/4
    if footprint then steps=full and {{1000,0,5},{4200,0,0},{4600,0,7},{9500,0,0}}
     or {{1000,0,5},{3000,0,0},{3500,0,7},{9500,0,0}} end
   end
   cases[#cases+1]={female=female,full=full,spec=spec,steps=steps,startYaw=yaw,
    name=(female and 'female-' or 'male-')..(full and 'full-' or 'empty-')..spec}
  end
 end
end
if footprint then
 for _,spec in ipairs({'door-closed','door-open','overlap','gait-contact'}) do
  local steps=spec=='door-closed' and {{1000,1,5},{6000,0,0},{7000,0,7},{9500,0,0}}
   or spec=='door-open' and {{1000,0,5},{3000,0,0},{3500,0,7},{9500,0,0}}
   or spec=='overlap' and {{1000,0,5},{3000,0,0},{4000,0,7},{9000,0,0}}
   or {{1000,0,5},{3500,1,5},{6500,0,0},{7500,0,7},{10000,0,0}}
  cases[#cases+1]={female=false,full=false,spec=spec,steps=steps,startYaw=math.pi/4,name='male-empty-'..spec}
 end
end
assert(#cases==(footprint and 20 or 16))
local phase,since,stage,taken=0,0,0,{}
local mode,attempt,videoSince='layout',0,0
local wallX,southY,gapY=math.floor(CartTestArea.x)-(footprint and 3 or 1),math.floor(CartTestArea.y)+2,math.floor(CartTestArea.y)
local controls,controlIndex,controlResults={'wall','corner','passage'},0,{}
local controlStart,controlSample=0,0
local sampleSince=0
local function wood(full)
 for i=1,3 do
  local item=p:getPrimaryHandItem()
  if item and item:getFullType()==kind then break end
  CartLabKey(Keyboard.KEY_F5)
 end
 assert(p:getPrimaryHandItem() and p:getPrimaryHandItem():getFullType()==kind,'Wrong cart')
 CartLabKey(Keyboard.KEY_F7);CartLabKey(Keyboard.KEY_F7)
 local item=p:getPrimaryHandItem()
 if (item:getInventory():getCapacityWeight()>0)~=full then CartLabKey(Keyboard.KEY_F6) end
 item=p:getPrimaryHandItem()
 assert(item:getFullType()==kind,'Wrong cart after reset')
 local weight=item:getInventory():getCapacityWeight()
 assert(full and math.abs(weight-item:getInventory():getEffectiveCapacity(p))<.01 or not full and weight==0,'Wrong cargo')
end
local function pose(x,y,heading)
 x=x or CartTestArea.x;y=y or CartTestArea.y;local z=CartTestArea.z
 p:setX(x);p:setY(y);p:setZ(z);p:setNextX(x);p:setNextY(y);p:setLastX(x);p:setLastY(y)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow()
 cartLabPoseHeading(heading or math.pi*.75+cases[phase].startYaw)
 CartTestArea.checkPosition(p)
end
local function sprinting(level)
 p:setPerkLevelDebug(Perks.Sprinting,level);p:getXp():setXPToLevel(Perks.Sprinting,level)
 assert(p:getPerkLevel(Perks.Sprinting)==level,'Wrong Sprinting skill')
end
local function poseCase()
 local c=cases[phase]
 if footprint then
  if c.spec=='corner-pivot' then pose(wallX+1.3,southY-1.18)
  elseif c.spec=='passage' or c.spec=='door-open' then pose(wallX+1.8,CartTestArea.y)
  elseif c.spec=='overlap' then pose(wallX+.65,CartTestArea.y)
  elseif c.spec=='gait-contact' then pose(wallX+1.4,CartTestArea.y)
  else pose() end
 elseif c.spec=='corner-pivot' then pose(controlResults.corner.x,controlResults.corner.y)
 else pose() end
end
local function reverseDrive()
 local heading=cartLabHeading();local best,score=1,2
 for index,degrees in ipairs({225,135,315,45,180,90,0,270}) do
  local dot=math.cos(heading-math.rad(degrees))
  if dot<score then best=index;score=dot end
 end
 return best
end
local function nextCase()
 sprinting(0)
 cartLabDrive(0);cartLabGait(0);phase=phase+1;stage=0;taken={};attempt=0
 if phase>#cases then
  CartTestArea.clearObstacles(p)
  print('[CART_COLLISION] CLEANUP_COMPLETE')
  print('[WOOD_BANK] ALL_COMPLETE cases='..#cases)
  cartLabDrive(-1);Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  return
 end
 local c=cases[phase]
 -- Use native Sprint eligibility with the same controlled skill per variant.
 sprinting(10)
 if p:isFemale()~=c.female then p:setFemale(c.female);p:getDescriptor():setFemale(c.female);p:resetModel() end
 wood(c.full or false);if c.bare then CartLabKey(Keyboard.KEY_F7) end;pose();p:getStats():reset(CharacterStat.ENDURANCE)
 mode='layout';since=getTimestampMs()+1800
end
local function layout(kind)
 local walls={}
 for y=gapY-24,gapY+24 do
  if (kind~='passage' and kind~='door-closed' and kind~='door-open') or y~=gapY then walls[#walls+1]={x=wallX,y=y,axis='W'} end
 end
 if kind=='corner' then
  for x=wallX,wallX+20 do walls[#walls+1]={x=x,y=southY,axis='N'} end
 end
 if kind=='door-closed' or kind=='door-open' then
  walls[#walls+1]={x=wallX,y=gapY,axis='W',kind='door',open=kind=='door-open'}
 end
 CartTestArea.clearObstacles(p);CartTestArea.setObstacles(p,walls)
end
local function nextControl()
 cartLabDrive(0);cartLabGait(0);controlIndex=controlIndex+1
 if controlIndex>#controls then nextCase();return end
 pose(CartTestArea.x,CartTestArea.y,controls[controlIndex]=='corner' and math.pi*.75 or math.pi)
 mode='control-layout';since=getTimestampMs()+1800
end
CartLabHUD.prerender=function(self)
 self:drawRect(0,0,self.width,self.height,.85,0,0,0)
 local c=cases[phase]
 self:drawText(c and c.name..' stage='..stage..' wallMs='..math.max(0,getTimestampMs()-since) or 'Complete',10,5,1,1,1,1,UIFont.Medium)
end
local function tick()
 local data=getPlayerData(0)
 if data and data.characterInfo then data.characterInfo:setVisible(false) end
 if ISChat and ISChat.instance then ISChat.instance:setVisible(false) end
 getCore():setAutoZoom(0,false)
 if getCore():getZoom(0)>.251 then getCore():doZoomScroll(0,-1) end
 CartTestArea.checkPosition(p)
 local now=getTimestampMs();local c=cases[phase]
 if mode=='control-layout' or mode=='layout' then
  if now<since then return end
  local ready,why=pcall(CartTestArea.check,p)
  if not ready then assert(now-since<6000,'Pad did not reload: '..tostring(why));return end
  local kind=mode=='control-layout' and controls[controlIndex] or c.spec=='corner-pivot' and 'corner'
   or (c.spec=='passage' or c.spec=='door-closed' or c.spec=='door-open') and c.spec or 'wall'
  layout(kind)
  if mode=='control-layout' then
   pose(CartTestArea.x,CartTestArea.y,kind=='corner' and math.pi*.75 or math.pi)
   mode='control-settle'
  else
   poseCase()
   print('[CART_COLLISION_LAYOUT] case='..c.name..' wallX='..wallX..' southY='..southY..' gapY='..gapY..' startX='..p:getX()..' startY='..p:getY()..' baselineX='..controlResults.corner.x..' baselineY='..controlResults.corner.y)
   mode='settle'
  end
  since=getTimestampMs()+800;return
 end
 if mode=='control-settle' then
  if now<since then return end
  CartTestArea.check(p);now=getTimestampMs();controlStart=now;controlSample=0;mode='control-drive'
  local spec=controls[controlIndex]
  print('[CART_COLLISION_CONTROL] START spec='..spec..' wall='..now..' x='..p:getX()..' y='..p:getY()..' wallX='..wallX..' southY='..southY..' gapY='..gapY)
  cartLabDrive(spec=='corner' and 2 or 5);return
 end
 if mode=='control-drive' then
  local spec=controls[controlIndex]
  if now-controlSample>=25 then
   controlSample=now
   print('[CART_COLLISION_CONTROL_SAMPLE] spec='..spec..' wall='..now..' elapsed='..(now-controlStart)..' x='..p:getX()..' y='..p:getY()..' heading='..cartLabHeading()..' drive='..(spec=='corner' and 2 or 5))
  end
  if now-controlStart>=4000 then
   local x,y=p:getX(),p:getY()
   assert(not p:getVariableBoolean('ToolkitCartPivot'),'Bare control retained cart steering')
   if spec=='passage' then
    assert(x<wallX-.2 and math.abs(y-CartTestArea.y)<.03,'Native passage control did not cross the gap')
   else
    assert(x>=wallX+.1 and x<=wallX+.5,'Native wall control did not reach its collision boundary')
    if spec=='corner' then
     assert(y>=southY-.5 and y<=southY-.1,'Native corner control did not reach both walls')
    else assert(math.abs(y-CartTestArea.y)<.03,'Native wall control drifted along the wall') end
   end
   controlResults[spec]={x=x,y=y}
   print('[CART_COLLISION_CONTROL] COMPLETE spec='..spec..' wall='..now..' x='..p:getX()..' y='..p:getY())
   nextControl()
  end
  return
 end
 if mode=='settle' then
  if now<since then return end
  local ready,why=pcall(CartTestArea.check,p)
  if not ready then
   assert(now-since<6000,'Pad did not reload: '..tostring(why))
   return
  end
  local dir=videoRoot..'/'..c.name..'-'..attempt
  assert(toolkitVideoStart(dir,ffmpeg),'Video start rejected')
  -- Pad validation and encoder startup must finish before the measured window starts.
  now=getTimestampMs()
  videoSince=now;since=now;stage=0;taken={};mode='record'
  print('[WOOD_BANK] CASE '..c.name..' attempt='..attempt..' wall='..since)
  return
 end
 local video=toolkitVideoStatus()
 if video.state=='failed' then
  cartLabDrive(0);cartLabGait(0);attempt=attempt+1;assert(attempt<=3,'Repeated video failure '..tostring(video.error))
  poseCase()
  mode='layout';since=getTimestampMs()+2000
  print('[WOOD_BANK] RETRY '..c.name..' reason='..tostring(video.error));return
 end
 if mode=='finish' then
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE '..c.name..' wall='..videoSince..' file='..tostring(video.file)..' frames='..tostring(video.frames)..' seconds='..tostring(video.seconds))
   nextCase()
  end
  return
 end
 local elapsed=now-since
 if now-sampleSince>=25 then
  sampleSince=now
  print('[WOOD_BANK_SAMPLE] case='..c.name..' wall='..now..' elapsed='..elapsed..' x='..p:getX()..' y='..p:getY()
   ..' run='..tostring(p:isRunning())..' sprint='..tostring(p:isSprinting())..' skill='..p:getPerkLevel(Perks.Sprinting)..' speed='..p:getVariableFloat('WalkSpeed',0)
   ..' drive='..tostring(c.steps[stage] and c.steps[stage][3] or 0)..' requestedGait='..tostring(c.steps[stage] and c.steps[stage][2] or 0)..' stepX='..p:getVariableFloat('ToolkitCartStepX',0)..' stepY='..p:getVariableFloat('ToolkitCartStepY',0)..' pace='..p:getVariableFloat('ToolkitCartLegPace',0)..' wheelPhase='..cartLabWheelPhase()..' bank='..cartLabBank()..' reversal='..cartLabReversal()..' ramp='..cartLabRamp()..' stationary='..cartLabStationary()..' tracks='..cartLabTracks())
  if footprint then print('[CART_FOOTPRINT_STATE] case='..c.name..' wall='..now..' elapsed='..elapsed..' '..cartLabFootprint()) end
 end
 while stage<#c.steps and elapsed>=c.steps[stage+1][1] do
  stage=stage+1;local step=c.steps[stage]
  if footprint and stage==#c.steps-1 then step[3]=reverseDrive() end
  if step[2]~=nil then cartLabGait(step[2]) end
  cartLabDrive(step[3])
  print('[WOOD_RAMP_EVENT] case='..c.name..' elapsed='..elapsed..' gait='..tostring(step[2])..' drive='..step[3])
 end

 if elapsed>=12000 then assert(toolkitVideoStop(),'Video stop rejected');mode='finish' end
end
WoodPrototypeTick=function()
 local ok,err=pcall(tick)
 if not ok then
  sprinting(0)
  Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil;cartLabDrive(-1);toolkitVideoStop()
  print('[WOOD_BANK] FAIL '..tostring(err))
 end
end
print('[WOOD_BANK] RUN_STARTED')
getCore():setAutoZoom(0,false)
for i=1,16 do getCore():doZoomScroll(0,-1) end
if p:getPrimaryHandItem() then CartLabKey(Keyboard.KEY_F7) end
assert(not p:getPrimaryHandItem(),'Bare native controls must not hold a cart')
nextControl();Events.OnTick.Add(WoodPrototypeTick)
