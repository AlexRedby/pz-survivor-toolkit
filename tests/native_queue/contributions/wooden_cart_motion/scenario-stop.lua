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
assert(CartLabKey and CartLabHUD and cartLabDrive and cartLabGait and cartLabBank and cartLabRamp and cartLabTracks and cartLabReversal and cartLabBrake and cartLabNative and cartLabClipInfo and cartLabPoseHeading and toolkitVideoStart and toolkitVideoStatus and toolkitVideoStop,'CartLab/video bridge missing')
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
-- At this side heading A/Left is straight; W/Forward and S/Backward request opposite 90-degree turns.
local cases={}
for _,female in ipairs(config.stopTiming and {false} or {false,true}) do
 for _,full in ipairs({false,true}) do
  for _,spec in ipairs(config.stopTiming and {'run-stop','sprint-stop'} or {'run-stop','sprint-stop','short-release','run-resume-reverse','sprint-resume-turn','arc-stop'}) do
   local steps
   if spec=='run-stop' or spec=='sprint-stop' then
    local gait=spec=='run-stop' and 1 or 2
    if config.stopTiming then
     -- Leave enough time for the full Sprint stop and its final hand-clearance return.
     steps={{1000,gait,2},{2500,0,0},{6000,gait,2},{7500,0,2},{7600,0,0},
      {11000,gait,2},{12500,0,2},{12800,0,0}}
    else
     -- The fourth field delays this event until the next game tick, even after a slow frame.
     steps={{1000,gait,2},{2500,0,0},{4000,gait,2},{5500,0,2},{5500,0,0,true},
      {7000,gait,2},{8500,gait,0},{8500,0,0,true}}
    end
   elseif spec=='short-release' then steps={{1000,2,2},{1250,0,0},{4000,1,2},{4250,0,0},{6500,2,2},{7000,0,0}}
   elseif spec=='run-resume-reverse' then steps={{1000,1,2},{4000,0,0},{4150,1,2},{7000,0,0},{7150,0,3},{10000,0,0}}
   elseif spec=='sprint-resume-turn' then steps={{1000,2,2},{4000,0,0},{4150,2,1},{8500,0,0}}
   else steps={{1000,1,2},{2500,1,1},{3000,0,0},{5500,2,2},{6500,2,4},{7000,0,0}} end
   cases[#cases+1]={female=female,full=full,startYaw=0,spec=spec,steps=steps,
    name=(female and 'female-' or 'male-')..(full and 'full-' or 'empty-')..spec}
  end
 end
end
assert(#cases==(config.stopTiming and 4 or 24))
cases=CartLabSelectScenes(cases)
local phase,since,stage,taken=0,0,0,{}
local tickFrame,stageFrame=0,0
local mode,attempt,videoSince='settle',0,0
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
 cartLabPoseHeading(math.pi*.75+cases[phase].startYaw)
 CartTestArea.checkPosition(p)
end
local function photo(name)
 if taken[name] then return end
 taken[name]=true;getCore():TakeFullScreenshot('wood-'..cases[phase].name..'-'..name..'.png')
end

local function sprinting(level)
 p:setPerkLevelDebug(Perks.Sprinting,level);p:getXp():setXPToLevel(Perks.Sprinting,level)
 assert(p:getPerkLevel(Perks.Sprinting)==level,'Wrong Sprinting skill')
end
local function held(action)
 return isKeyDown(getCore():getKey(action))
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
 sprinting(10)
 if p:isFemale()~=c.female then p:setFemale(c.female);p:getDescriptor():setFemale(c.female);p:resetModel() end
 wood(c.full or false);if c.bare then CartLabKey(Keyboard.KEY_F7);assert(not p:getPrimaryHandItem() and not p:getSecondaryHandItem(),'Bare reference must have empty hands') end;pose();p:getStats():reset(CharacterStat.ENDURANCE)
 mode='settle';since=getTimestampMs()+1800
end
CartLabHUD.prerender=function(self)
 self:drawRect(0,0,self.width,self.height,.85,0,0,0)
 local c=cases[phase]
 self:drawText(c and c.name or 'Complete',10,5,1,1,1,1,UIFont.Medium)
 self:drawText('wall elapsed='..tostring(mode=='record' and getTimestampMs()-videoSince or 0)..'ms stage='..stage,10,30,1,1,1,1,UIFont.Small)
end
local function tick()
 tickFrame=tickFrame+1
 local data=getPlayerData(0)
 if data and data.characterInfo then data.characterInfo:setVisible(false) end
 if ISChat and ISChat.instance then ISChat.instance:setVisible(false) end
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
  if c.bare then assert(not p:getPrimaryHandItem() and not p:getSecondaryHandItem() and not p:getVariableBoolean('ToolkitCartMotion'),'Bare reference contaminated by cart pose') end
  local dir=videoRoot..'/'..c.name..'-'..attempt
  assert(toolkitVideoStart(dir,ffmpeg),'Video start rejected')
  videoSince=now;since=now;stage=0;taken={};mode='record'
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
 local elapsed=now-since
 if now-sampleSince>=25 then
  sampleSince=now
  print('[WOOD_BANK_SAMPLE] case='..c.name..' wall='..now..' elapsed='..elapsed..' x='..p:getX()..' y='..p:getY()
   ..' run='..tostring(p:isRunning())..' sprint='..tostring(p:isSprinting())..' skill='..p:getPerkLevel(Perks.Sprinting)..' speed='..p:getVariableFloat('WalkSpeed',0)
   ..' brakeArmed='..tostring(p:getVariableBoolean('ToolkitCartWoodBrake'))..' bare='..tostring(c.bare==true)..' item='..(p:getPrimaryHandItem() and p:getPrimaryHandItem():getFullType() or 'none')..' cartMotion='..tostring(p:getVariableBoolean('ToolkitCartMotion'))..' native='..cartLabNative()..' requestedGait='..tostring(c.steps[stage] and c.steps[stage][2] or 0)..' stepX='..p:getVariableFloat('ToolkitCartStepX',0)..' stepY='..p:getVariableFloat('ToolkitCartStepY',0)..' pace='..p:getVariableFloat('ToolkitCartLegPace',0)..' bank='..cartLabBank()..' reversal='..cartLabReversal()..' brake='..cartLabBrake()..' ramp='..cartLabRamp()..' tracks='..cartLabTracks())
 end
 while stage<#c.steps and elapsed>=c.steps[stage+1][1]
  and (not c.steps[stage+1][4] or stageFrame<tickFrame) do
  stage=stage+1;local step=c.steps[stage]
  stageFrame=tickFrame
  if step[2]~=nil then cartLabGait(step[2]) end
  cartLabDrive(step[3])
  print('[WOOD_RAMP_EVENT] case='..c.name..' elapsed='..elapsed..' gait='..tostring(step[2])..' drive='..step[3]..' frame='..tickFrame
   ..' keyRun='..tostring(held('Run'))..' keySprint='..tostring(held('Sprint'))
   ..' keyMove='..tostring(held('Forward') or held('Left') or held('Right') or held('Backward')))
 end

 if elapsed>=(config.stopTiming and 16000 or 12000) then assert(toolkitVideoStop(),'Video stop rejected');mode='finish' end
end
WoodPrototypeTick=function()
 local ok,err=pcall(tick)
 if not ok then
  sprinting(0)
  Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil;cartLabDrive(-1);toolkitVideoStop()
  print('[WOOD_BANK] FAIL '..tostring(err))
 end
end
for _,name in ipairs({'Bob_RunToStop','Bob_SprintToStop','Bob_RunToStop2H_Heavy','Bob_SprintToStop_2h_Heavy','Bob_SprintToStop2h_Heavy'}) do print('[BARE_CLIP_LOOKUP] name='..name..' result='..cartLabClipInfo(name)) end
print('[WOOD_BANK] RUN_STARTED')
getCore():setAutoZoom(0,false)
for i=1,16 do getCore():doZoomScroll(0,-1) end
nextCase();Events.OnTick.Add(WoodPrototypeTick)
