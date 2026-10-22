local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true,'CartMotionConfig.disposable must be true')
local function absolutePath(name)
 local value=config[name]
 assert(type(value)=='string' and value~='' and (value:sub(1,1)=='/' or value:match('^%a:[/\\]') or value:sub(1,2)=='\\\\'), 'CartMotionConfig.'..name..' must be an absolute path')
 return value
end
local videoRoot,ffmpeg=absolutePath('videoRoot'),absolutePath('ffmpeg')
assert(getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable single-player CartTestArea save required')
local p=assert(getPlayer(),'Live actor required')
assert(not p:isDead() and CartTestArea and CartTestArea.ready,'Wait for BOOTSTRAP_READY')
assert(CartLabKey and CartLabHUD and cartLabDrive and cartLabGait and cartLabBank and cartLabRamp and cartLabTracks and toolkitVideoStart and toolkitVideoStatus and toolkitVideoStop and cartLabMillis,'CartLab/video bridge missing')
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
local kind=config.cartType or 'SaucedWheelbarrow.WheelbarrowWood'
assert(kind=='SaucedWheelbarrow.WheelbarrowWood' or kind=='SaucedWheelbarrow.WheelbarrowMetal','Unsupported calibrated cart type')
-- Relative cart controls: Forward rolls along the current heading; Left/Right steer while held.
local cases={}
for _,female in ipairs({false,true}) do
 for _,full in ipairs({false,true}) do
  for _,spec in ipairs({'comparison','direct','gait','runstop'}) do
   local turn=full and 4 or 1
   local steer=full and 8 or 5
   local steps
   if spec=='comparison' or spec=='runstop' then
    steps={{700,0,1},{1800,spec=='comparison' and 2 or 1,1},{3000,nil,steer},{5000,nil,1},{7000,nil,steer},{9000,nil,0},{10000,0,1},{11500,nil,0}}
   elseif spec=='direct' then
    steps={{1000,2,1},{4000,nil,steer},{6000,nil,0},{8000,0,1},{9500,2,1},{11000,nil,0}}
   else
    steps={{700,0,1},{1800,1,1},{3200,2,1},{4500,nil,steer},{6300,config.directFastWalk and 0 or 1,1},{8500,config.directFastWalk and 1 or 0,1},{10000,nil,0}}
   end
   cases[#cases+1]={female=female,full=full,spec=spec,steps=steps,
    name=(female and 'female-' or 'male-')..(full and 'full-' or 'empty-')..spec..(turn==1 and '-left' or '-right')}
  end
 end
end
assert(#cases==16)
cases=CartLabSelectScenes(cases)
local phase,since,stage,taken=0,0,0,{}
local mode,attempt,videoSince,recordSince='settle',0,0,0
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
local function pose()
 local x,y,z=CartTestArea.x,CartTestArea.y,CartTestArea.z
 p:setX(x);p:setY(y);p:setZ(z);p:setNextX(x);p:setNextY(y);p:setLastX(x);p:setLastY(y)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow()
 p:setTargetAndCurrentDirection(-.70710678,.70710678)
 CartTestArea.checkPosition(p)
end
local function photo(name)
 if taken[name] then return end
 taken[name]=true;getCore():TakeFullScreenshot((config.cartVariant=='metal-wheelbarrow' and 'metal-' or 'wood-')..cases[phase].name..'-'..name..'.png')
end

local function sprinting(level)
 p:setPerkLevelDebug(Perks.Sprinting,level);p:getXp():setXPToLevel(Perks.Sprinting,level)
 assert(p:getPerkLevel(Perks.Sprinting)==level,'Wrong Sprinting skill')
end
local function nextCase()
 sprinting(0)
 cartLabDrive(0);cartLabGait(0);phase=phase+1;stage=0;taken={};attempt=0
 if phase>#cases then
  print('[WOOD_BANK] ALL_COMPLETE cases='..#cases)
  cartLabDrive(-1);Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  return
 end
 local c=cases[phase]
 -- Use native Sprint eligibility with the same controlled skill per variant.
 if not c.bare and c.spec~='runstop' then sprinting(10) end
 if p:isFemale()~=c.female then p:setFemale(c.female);p:getDescriptor():setFemale(c.female);p:resetModel() end
 wood(c.full or false);if c.bare then CartLabKey(Keyboard.KEY_F7) end;pose();p:getStats():reset(CharacterStat.ENDURANCE)
 mode='settle';since=getTimestampMs()+1800
end
CartLabHUD.prerender=function(self)
 self:drawRect(0,0,self.width,self.height,.85,0,0,0)
 local c=cases[phase]
 self:drawText(c and c.name or 'Complete',10,5,1,1,1,1,UIFont.Medium)
end
local gaitSeen,lastSampleX,lastSampleY
local function tick()
 getCore():setAutoZoom(0,false)
 if getCore():getZoom(0)>.251 then getCore():doZoomScroll(0,-1) end
 CartTestArea.checkPosition(p)
 local now=getTimestampMs();local c=cases[phase]
 if mode=='settle' then
  if now<since then return end
  local ready,why=pcall(CartTestArea.check,p)
  if not ready then
   assert(now-since<6000,'Pad did not reload: '..tostring(why))
   return
  end
  gaitSeen={};lastSampleX,lastSampleY=p:getX(),p:getY()
  local dir=videoRoot..'/'..c.name..'-'..attempt
  assert(toolkitVideoStart(dir,ffmpeg),'Video start rejected')
  videoSince=now;since=now;recordSince=cartLabMillis();stage=0;taken={};mode='record'
  print('[WOOD_BANK] CASE '..c.name..' attempt='..attempt..' wall='..since)
  return
 end
 local video=toolkitVideoStatus()
 if video.state=='failed' then
  cartLabDrive(0);attempt=attempt+1;assert(attempt<=3,'Repeated video failure '..tostring(video.error))
  pose();mode='settle';since=now+2000
  print('[WOOD_BANK] RETRY '..c.name..' reason='..tostring(video.error));return
 end
 if mode=='finish' then
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE '..c.name..' wall='..videoSince..' file='..tostring(video.file)..' frames='..tostring(video.frames)..' seconds='..tostring(video.seconds))
   nextCase()
  end
  return
 end
 local elapsed=math.floor(cartLabMillis()-recordSince)
 if now-sampleSince>=100 then
  sampleSince=now
  if math.sqrt((p:getX()-lastSampleX)^2+(p:getY()-lastSampleY)^2)>.01 then
   gaitSeen[p:isSprinting() and 'sprint' or p:isRunning() and 'run' or 'walk']=true
  end
  lastSampleX,lastSampleY=p:getX(),p:getY()
  print('[WOOD_BANK_SAMPLE] case='..c.name..' wall='..now..' elapsed='..elapsed..' x='..p:getX()..' y='..p:getY()
   ..' cartType='..(p:getPrimaryHandItem() and p:getPrimaryHandItem():getFullType() or 'none')..' run='..tostring(p:isRunning())..' sprint='..tostring(p:isSprinting())..' skill='..p:getPerkLevel(Perks.Sprinting)..' speed='..p:getVariableFloat('WalkSpeed',0)
   ..' pace='..p:getVariableFloat('ToolkitCartLegPace',0)..' bank='..cartLabBank()..' ramp='..cartLabRamp()..' tracks='..cartLabTracks())
 end
 while stage<#c.steps and elapsed>=c.steps[stage+1][1] do
  stage=stage+1;local step=c.steps[stage]
  if step[2]~=nil then cartLabGait(step[2]) end
  cartLabDrive(step[3])
  print('[WOOD_RAMP_EVENT] case='..c.name..' elapsed='..elapsed..' gait='..tostring(step[2])..' drive='..step[3])
 end

 if elapsed>=12000 then
  if c.spec=='gait' then assert(gaitSeen.walk and gaitSeen.run and gaitSeen.sprint,'Requested Walk/Run/Sprint did not all move natively') end
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
nextCase();Events.OnTick.Add(WoodPrototypeTick)
