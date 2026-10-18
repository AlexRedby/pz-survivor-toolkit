local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true,'CartMotionConfig.disposable must be true')
local function absolutePath(name)
 local value=config[name]
 assert(type(value)=='string' and value~='' and (value:sub(1,1)=='/' or value:match('^%a:[/\\]') or value:sub(1,2)=='\\\\'), 'CartMotionConfig.'..name..' must be an absolute path')
 return value
end
local videoRoot,ffmpeg=absolutePath('videoRoot'),absolutePath('ffmpeg')
local footprint=config.footprint==true
local brace=config.brace==true
local fastSlide=config.fastSlide==true
local wallExit=config.wallExit==true
local wallManualExit=config.wallManualExit==true
local wallFastManualExit=config.wallFastManualExit==true
assert(not wallFastManualExit or wallManualExit,'Fast manual wall exit requires manual wall exit mode')
assert(not wallManualExit or wallExit,'Manual wall exit requires wall exit mode')
assert(not wallExit or footprint and not fastSlide and not brace and not config.impact,'Wall exit bank requires footprint without fast slide, brace or impact')
assert(not fastSlide or footprint and not brace and not config.impact,'Fast slide bank requires footprint without brace or impact')
assert(not brace or footprint and not config.impact,'Brace bank requires footprint without impact')
assert(getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable single-player CartTestArea save required')
local p=assert(getPlayer(),'Live actor required')
assert(not p:isDead() and CartTestArea and CartTestArea.ready,'Wait for BOOTSTRAP_READY')
assert(CartLabKey and CartLabHUD and cartLabDrive and cartLabGait and cartLabBank and cartLabRamp and cartLabTracks and cartLabReversal and cartLabStationary and cartLabPoseHeading and cartLabHeading and cartLabWheelPhase and CartTestArea.setObstacles and toolkitVideoStart and toolkitVideoStatus and toolkitVideoStop,'CartLab/video bridge missing')
assert(not footprint or cartLabFootprint,'Footprint diagnostics missing')
assert(not brace or cartLabBrace,'Brace/native wall diagnostics missing')
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
  for _,spec in ipairs(footprint and {'wall-block','wall-slide','wall-slide-right','corner-pivot','passage'} or {'wall-block','wall-slide','corner-pivot','passage'}) do
   local steps,yaw
   if spec=='wall-block' then
    steps={{1000,1,5},{6000,0,0},{7000,0,7},{9500,0,0}};yaw=math.pi/4
   elseif spec=='wall-slide' or spec=='wall-slide-right' then
    local right=spec=='wall-slide-right'
    steps={{1000,1,right and 1 or 2},{6000,0,0},{7000,0,7},{9500,0,0}};yaw=right and math.pi/2 or 0
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
assert(#cases==(footprint and 24 or 16))
if fastSlide then
 cases={}
 for _,female in ipairs({false,true}) do for _,full in ipairs({false,true}) do
  for _,gait in ipairs({'run','sprint'}) do for _,right in ipairs({false,true}) do
   local spec=right and 'wall-slide-right' or 'wall-slide'
   cases[#cases+1]={female=female,full=full,spec=spec,startYaw=right and math.pi/2 or 0,
    steps={{1000,gait=='run' and 1 or 2,right and 1 or 2},{6000,0,0},{7000,0,7},{9500,0,0}},
    name=(female and 'female-' or 'male-')..(full and 'full-' or 'empty-')..gait..'-'..spec}
  end end
 end end
 assert(#cases==16)
end
if wallExit then
 cases={}
 for _,full in ipairs({false,true}) do for gaitIndex,gait in ipairs(wallFastManualExit and {'run','sprint'} or wallManualExit and {'walk'} or {'walk','run','sprint'}) do
  for _,right in ipairs({false,true}) do for _,angle in ipairs({45,90}) do
   local spec=right and 'wall-slide-right' or 'wall-slide'
   cases[#cases+1]={female=false,full=full,spec=spec,startYaw=right and math.pi/2 or 0,
    steps=wallManualExit and {{1000,wallFastManualExit and (gait=='run' and 1 or 2) or 0,right and 1 or 2},{9500,0,right and 6 or 8},{12000,0,right and 4 or 3},{15500,0,0},{16000,0,right and 3 or 4},{26000,0,0}}
     or {{1000,gaitIndex-1,right and 1 or 2},{5500,gaitIndex-1,angle==90 and 7 or right and 3 or 4},{10000,0,0}},
    name='male-'..(full and 'full-' or 'empty-')..gait..'-'..spec..(wallManualExit and '-manual' or '')..'-out'..angle}
   if wallManualExit and angle==90 then table.insert(cases[#cases].steps,6,{21000,0,7}) end
  end end
 end end
 assert(#cases==(wallFastManualExit and 16 or wallManualExit and 8 or 24))
end
if config.impact then
 cases={}
 for _,female in ipairs({false,true}) do for _,full in ipairs({false,true}) do
  for _,spec in ipairs({'sprint-wall','native-impact'}) do
   cases[#cases+1]={female=female,full=full,spec=spec,startYaw=math.pi/4,
    steps={{1000,2,5},{6000,0,0},{7000,0,7},{spec=='native-impact' and 8000 or 9500,0,0}},
    name=(female and 'female-' or 'male-')..(full and 'full-' or 'empty-')..spec}
  end
 end end
end
if brace then
 cases={}
 for _,female in ipairs({false,true}) do for _,full in ipairs({false,true}) do
  for _,spec in ipairs({'wall-release','wall-restart'}) do
   cases[#cases+1]={female=female,full=full,spec=spec,startYaw=math.pi/4,
    steps=spec=='wall-release' and {{1000,0,5},{14000,0,0}}
     or {{1000,0,5},{6500,0,0},{7500,0,7},{10000,0,0},{10800,0,5},{15500,0,0}},
    name=(female and 'female-' or 'male-')..(full and 'full-' or 'empty-')..spec}
  end
 end end
end
cases=CartLabSelectScenes(cases)
local phase,since,stage,taken=0,0,0,{}
local mode,attempt,videoSince='layout',0,0
local wallX,southY,gapY=math.floor(CartTestArea.x)-(config.impact and 6 or footprint and 3 or 1),math.floor(CartTestArea.y)+2,math.floor(CartTestArea.y)
local controls,controlIndex,controlResults={'wall','corner','passage'},0,{}
if footprint and not config.impact then controls[#controls+1]='wall-slide-left';controls[#controls+1]='wall-slide-right' end
local function controlDrive(spec) return (spec=='corner' or spec=='wall-slide-left') and 2 or spec=='wall-slide-right' and 1 or 5 end
local function controlHeading(spec) return spec=='wall-slide-right' and -math.pi*.75 or (spec=='corner' or spec=='wall-slide-left') and math.pi*.75 or math.pi end
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
 if wallExit then pose(wallX+2.8,CartTestArea.y)
 elseif brace then pose(wallX+1.8,CartTestArea.y,math.pi)
 elseif footprint then
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
 local previous=cases[phase]
 if config.impact and previous and previous.item then
  local item=previous.item;local world=item:getWorldItem()
  if world then
   assert(world:getItem()==item and not p:getInventory():contains(item),'Invalid owned impact cart cleanup')
   local square=world:getSquare()
   square:transmitRemoveItemFromSquare(world);square:removeWorldObject(world);item:setWorldItem(nil)
   p:getInventory():AddItem(item);p:setPrimaryHandItem(item);p:setSecondaryHandItem(item);SaucedCarts.applyCartPose(p)
  end
 end
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
 wood(c.full or false);if c.bare then CartLabKey(Keyboard.KEY_F7) end
 if config.impact then c.item=p:getPrimaryHandItem() end
 pose();p:getStats():reset(CharacterStat.ENDURANCE)
 mode='layout';since=getTimestampMs()+1800
end
local function layout(kind,shortWall)
 local walls={}
 local reach=shortWall and 1 or wallFastManualExit and mode=='layout' and 40 or 24
 for y=gapY-reach,gapY+reach do
  if (kind~='passage' and kind~='door-closed' and kind~='door-open') or y~=gapY then walls[#walls+1]={x=wallX,y=y,axis='W'} end
 end
 if kind=='corner' then
  for x=wallX,wallX+20 do walls[#walls+1]={x=x,y=southY,axis='N'} end
 end
 if kind=='door-closed' or kind=='door-open' then
  walls[#walls+1]={x=wallX,y=gapY,axis='W',kind='door',open=kind=='door-open'}
 end
 CartTestArea.clearObstacles(p);CartTestArea.setObstacles(p,walls)
 if wallFastManualExit and mode=='layout' then
  local count,minY,maxY=0,math.huge,-math.huge
  for _,wall in pairs(CartTestArea.obstacles) do
   assert(wall.x==wallX and wall.axis=='W' and wall.kind=='wall' and wall.z==CartTestArea.z,'Fast manual wall layout changed')
   count=count+1;minY=math.min(minY,wall.y);maxY=math.max(maxY,wall.y)
  end
  assert(count==81 and minY==gapY-40 and maxY==gapY+40,'Incomplete fast manual wall')
  return count,minY,maxY
 end
end
local function nextControl()
 cartLabDrive(0);cartLabGait(0);controlIndex=controlIndex+1
 if controlIndex>#controls then nextCase();return end
 pose(CartTestArea.x,CartTestArea.y,controlHeading(controls[controlIndex]))
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
 local now=getTimestampMs();local c=cases[phase]
 CartTestArea.checkPosition(p,config.impact and c and c.item or nil)
 if mode=='control-layout' or mode=='layout' then
  if now<since then return end
  local ready,why=pcall(CartTestArea.check,p)
  if not ready then assert(now-since<6000,'Pad did not reload: '..tostring(why));return end
  local kind=mode=='control-layout' and controls[controlIndex] or c.spec=='corner-pivot' and 'corner'
   or (c.spec=='passage' or c.spec=='door-closed' or c.spec=='door-open') and c.spec or 'wall'
  local ownedWalls,wallMinY,wallMaxY=layout(kind,brace and mode~='control-layout' and c.spec=='wall-release')
  if mode=='control-layout' then
   pose(config.impact and wallX+3.5 or CartTestArea.x,CartTestArea.y,controlHeading(kind))
   mode='control-settle'
  else
   poseCase()
   print('[CART_COLLISION_LAYOUT] case='..c.name..' wallX='..wallX..' southY='..southY..' gapY='..gapY..' startX='..p:getX()..' startY='..p:getY()..' baselineX='..controlResults.corner.x..' baselineY='..controlResults.corner.y
    ..(brace and (' ownedWalls='..(c.spec=='wall-release' and 3 or 49)) or '')
    ..(wallFastManualExit and (' ownedWalls='..ownedWalls..' wallMinY='..wallMinY..' wallMaxY='..wallMaxY) or ''))
   mode='settle'
  end
  since=getTimestampMs()+800;return
 end
 if mode=='control-settle' then
  if now<since then return end
  CartTestArea.check(p);now=getTimestampMs();controlStart=now;controlSample=0;mode='control-drive'
  local spec=controls[controlIndex]
  print('[CART_COLLISION_CONTROL] START spec='..spec..' wall='..now..' x='..p:getX()..' y='..p:getY()..' wallX='..wallX..' southY='..southY..' gapY='..gapY)
  cartLabDrive(controlDrive(spec));return
 end
 if mode=='control-drive' then
  local spec=controls[controlIndex]
  if now-controlSample>=25 then
   controlSample=now
   print('[CART_COLLISION_CONTROL_SAMPLE] spec='..spec..' wall='..now..' elapsed='..(now-controlStart)..' x='..p:getX()..' y='..p:getY()..' heading='..cartLabHeading()..' drive='..controlDrive(spec)
    ..(spec:find('wall-slide',1,true) and (' run='..tostring(p:isRunning())..' sprint='..tostring(p:isSprinting())..' bare='..tostring(not p:getPrimaryHandItem() and not p:getSecondaryHandItem())..' tracks='..cartLabTracks()) or ''))
  end
  if now-controlStart>=(spec:find('wall-slide',1,true) and 6000 or 4000) then
   local x,y=p:getX(),p:getY()
   assert(not p:getVariableBoolean('ToolkitCartPivot'),'Bare control retained cart steering')
   if spec=='passage' then
    assert(x<wallX-.2 and math.abs(y-CartTestArea.y)<.03,'Native passage control did not cross the gap')
   else
    assert(x>=wallX+(spec:find('wall-slide',1,true) and -.002 or .1) and x<=wallX+.5,'Native wall control did not reach its collision boundary')
    if spec=='corner' then
     assert(y>=southY-.5 and y<=southY-.1,'Native corner control did not reach both walls')
    elseif spec:find('wall-slide',1,true) then
     assert((spec=='wall-slide-right' and -1 or 1)*(y-CartTestArea.y)>.15,'Native Walk did not slide along the wall')
     assert(not p:isRunning() and not p:isSprinting(),'Bare slide must use native Walk')
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
  local checkStarted=brace and getTimestampMs()
  local ready,why=pcall(CartTestArea.check,p)
  if brace then print('[CART_BRACE_GUARD_COST] case='..c.name..' phase=settle millis='..(getTimestampMs()-checkStarted)) end
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
  if config.impact then
   print('[CART_IMPACT_SAMPLE] case='..c.name..' wall='..now..' elapsed='..elapsed
    ..' x='..p:getX()..' y='..p:getY()..' run='..tostring(p:isRunning())..' sprint='..tostring(p:isSprinting())..' '..cartLabSafety(c.item,CartTestArea.x,CartTestArea.y))
  else
   print('[WOOD_BANK_SAMPLE] case='..c.name..' wall='..now..' elapsed='..elapsed..' x='..p:getX()..' y='..p:getY()
   ..' run='..tostring(p:isRunning())..' sprint='..tostring(p:isSprinting())..' skill='..p:getPerkLevel(Perks.Sprinting)..' speed='..p:getVariableFloat('WalkSpeed',0)
    ..' drive='..tostring(c.steps[stage] and c.steps[stage][3] or 0)..' requestedGait='..tostring(c.steps[stage] and c.steps[stage][2] or 0)..' stepX='..p:getVariableFloat('ToolkitCartStepX',0)..' stepY='..p:getVariableFloat('ToolkitCartStepY',0)..' pace='..p:getVariableFloat('ToolkitCartLegPace',0)..' wheelPhase='..cartLabWheelPhase()..' bank='..cartLabBank()..' reversal='..cartLabReversal()..' ramp='..cartLabRamp()..' stationary='..cartLabStationary()..' tracks='..cartLabTracks())
  end
  if footprint then print('[CART_FOOTPRINT_STATE] case='..c.name..' wall='..now..' elapsed='..elapsed..' '..cartLabFootprint()) end
  if brace then print('[CART_BRACE_SAMPLE] case='..c.name..' wall='..now..' elapsed='..elapsed..' '..cartLabBrace(wallX,CartTestArea.y)) end
 end
 if brace and c.spec=='wall-release' and elapsed>=8000 then
  if not taken.remove then
   assert(stage==1 and c.steps[stage][3]==5,'Wall removal must retain forward input')
   local count=0;for _ in pairs(CartTestArea.obstacles) do count=count+1 end
   assert(count==3,'Unexpected owned wall count before removal')
   local state=cartLabBrace(wallX,CartTestArea.y)
   assert(state:match('nativeBlocked=true'),'Native wall missing before guarded removal')
   print('[CART_BRACE_REMOVE] case='..c.name..' phase=before wall='..now..' elapsed='..elapsed..' owned='..count..' drive=5 '..state)
   CartTestArea.clearObstacles(p)
   for _ in pairs(CartTestArea.obstacles) do error('Owned wall survived removal') end
   taken.remove=now
  end
  if not taken.clear then
   local state=cartLabBrace(wallX,CartTestArea.y)
   if state:match('nativeBlocked=false') then
    local observed=getTimestampMs()
    print('[CART_BRACE_REMOVE] case='..c.name..' phase=after wall='..observed..' elapsed='..(observed-since)..' owned=0 drive=5 '..state)
    taken.clear=true
   else assert(now-taken.remove<=1000,'Native wall removal did not become query-clear') end
  end
 end
 if config.impact and c.spec=='native-impact' and elapsed>=2000 and not taken.impact then
  assert(elapsed<2500,'Native Sprint did not become ready for wall event')
  if p:isSprinting() and p:getActionStateName()=='sprint' then
   taken.impact=true
   print('[CART_IMPACT_EVENT] case='..c.name..' wall='..now..' elapsed='..elapsed..' source=native-action-event')
   cartLabWallEvent()
   cartLabDrive(0);cartLabGait(0)
   print('[WOOD_RAMP_EVENT] case='..c.name..' elapsed='..elapsed..' gait=0 drive=0')
  end
 end
 while stage<#c.steps and elapsed>=c.steps[stage+1][1] do
  stage=stage+1;local step=c.steps[stage]
  if footprint and not wallExit and (not brace and stage==#c.steps-1 or brace and c.spec=='wall-restart' and stage==3) then step[3]=reverseDrive() end
  if step[2]~=nil then cartLabGait(step[2]) end
  cartLabDrive(step[3])
  print('[WOOD_RAMP_EVENT] case='..c.name..' elapsed='..elapsed..' gait='..tostring(step[2])..' drive='..step[3])
 end

 if elapsed>=(wallManualExit and 29000 or brace and 18000 or 12000) then
  assert(not brace or c.spec~='wall-release' or taken.clear,'Missing guarded native wall removal')
  assert(not config.impact or c.spec~='native-impact' or taken.impact,'Missing native wall event')
  assert(toolkitVideoStop(),'Video stop rejected');mode='finish'
 end
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
