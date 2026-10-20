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
assert(CartLabKey and CartLabHUD and cartLabDrive and cartLabGait and cartLabBank and cartLabRamp and cartLabHeading and cartLabSteeringHeading and cartLabTracks and cartLabReversal and cartLabStationary and cartLabPoseHeading and toolkitVideoStart and toolkitVideoStatus and toolkitVideoStop,'CartLab/video bridge missing')
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
p:setFemale(false);p:getDescriptor():setFemale(false)
p:clearWornItems();p:getHumanVisual():setHairModel('CrewCut');p:getHumanVisual():setBeardModel('')
for _,name in ipairs({'Base.Tshirt_DefaultTEXTURE_TINT','Base.Trousers_JeanBaggy','Base.Shoes_TrainerTINT'}) do
 local item=assert(p:getInventory():AddItem(name),name)
 p:setWornItem(item:getBodyLocation(),item)
end
p:resetModel()
-- Change this disposable process only; never persist the user's mod settings.
if PZAPI and PZAPI.ModOptions then
 local options=PZAPI.ModOptions:getOptions('MiniHealthPlus')
 local option=options and options:getOption('DisableMod')
 if option and option:getValue()~=true then
  option:setValue(true)
  if TwisTonFire_MHP_RefreshModOptions then TwisTonFire_MHP_RefreshModOptions() end
 end
end

CartTestArea.check(p)
local climate=getClimateManager()
for _,index in ipairs({ClimateManager.FLOAT_FOG_INTENSITY,ClimateManager.FLOAT_PRECIPITATION_INTENSITY,ClimateManager.FLOAT_CLOUD_INTENSITY}) do
 local value=climate:getClimateFloat(index);value:setEnableAdmin(true);value:setAdminValue(0)
end
local kind='SaucedWheelbarrow.WheelbarrowWood'
-- Eight current cart-relative control scenes; each includes a moving entry control.
local cases={}
for _,female in ipairs({false,true}) do
 for _,full in ipairs({false,true}) do
  for _,side in ipairs({'left','right'}) do
   cases[#cases+1]={female=female,full=full,side=side,
    name=(female and 'female-' or 'male-')..(full and 'full-' or 'empty-')..'pivot-'..side}
  end
 end
end
cases=CartLabSelectScenes(cases)
local phase,since,videoSince,sampleSince,stageSince=0,0,0,0,0
local mode,stage,drive='settle','rest',0
local lastHeading,accumulated,pivotStart,attempt=0,0,0,0
local function wrap(a) return math.atan2(math.sin(a),math.cos(a)) end
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
 cartLabPoseHeading(.4)
 CartTestArea.checkPosition(p)
end

local function event(label,now)
 print('[CART_PIVOT_EVENT] case='..cases[phase].name..' wall='..now..' elapsed='..(now-videoSince)
  ..' event='..label..' drive='..drive..' accumulated='..accumulated..' heading='..cartLabSteeringHeading())
 print('[WOOD_RAMP_EVENT] case='..cases[phase].name..' elapsed='..(now-videoSince)..' gait=0 drive='..drive)
end
local function enter(label,input,now)
 stage=label;stageSince=now;drive=input;cartLabDrive(input);event(label,now)
end
local function nextCase()
 cartLabDrive(0);cartLabGait(0);phase=phase+1;attempt=0
 if phase>#cases then
  print('[WOOD_BANK] ALL_COMPLETE cases='..#cases)
  cartLabDrive(-1);Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil;return
 end
 local c=cases[phase]
 if p:isFemale()~=c.female then p:setFemale(c.female);p:getDescriptor():setFemale(c.female);p:resetModel() end
 wood(c.full);pose();p:getStats():reset(CharacterStat.ENDURANCE)
 mode='settle';since=getTimestampMs()+1800
end
CartLabHUD.prerender=function(self)
 self:drawRect(0,0,self.width,self.height,.85,0,0,0)
 local c=cases[phase]
 self:drawText(c and c.name..' '..stage..' yaw='..string.format('%.1f',math.deg(accumulated)) or 'Complete',10,5,1,1,1,1,UIFont.Medium)
end
local function tick()
 local now=getTimestampMs();local c=cases[phase]
 local data=getPlayerData(0)
 if data and data.characterInfo then data.characterInfo:setVisible(false) end
 if ISChat and ISChat.instance then ISChat.instance:setVisible(false) end
 getCore():setAutoZoom(0,false)
 if getCore():getZoom(0)>.251 then getCore():doZoomScroll(0,-1) end
 CartTestArea.checkPosition(p)
 if mode=='settle' then
  if now<since then return end
  local ready,why=pcall(CartTestArea.check,p)
  if not ready then assert(now-since<6000,'Pad did not reload: '..tostring(why));return end
  assert(toolkitVideoStart(videoRoot..'/'..c.name..'-'..attempt,ffmpeg),'Video start rejected')
  videoSince=now;sampleSince=0;accumulated=0;mode='record'
  print('[WOOD_BANK] CASE '..c.name..' attempt='..attempt..' wall='..videoSince)
  enter('rest',0,now);return
 end
 local video=toolkitVideoStatus()
 assert(video.state~='failed','Pivot video failed: '..tostring(video.error))
 if mode=='finish' then
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE '..c.name..' wall='..videoSince..' file='..tostring(video.file)..' frames='..tostring(video.frames)..' seconds='..tostring(video.seconds))
   nextCase()
  end
  return
 end
 assert(now-videoSince<20000,'Pivot phase timed out: '..stage)
 local heading=cartLabSteeringHeading()
 if stage=='pivot' then
  accumulated=accumulated+wrap(heading-lastHeading);lastHeading=heading
 end
 if now-sampleSince>=25 then
  sampleSince=now
  print('[WOOD_BANK_SAMPLE] case='..c.name..' wall='..now..' elapsed='..(now-videoSince)..' x='..p:getX()..' y='..p:getY()
   ..' run='..tostring(p:isRunning())..' sprint='..tostring(p:isSprinting())..' drive='..drive..' requestedGait=0'
   ..' stepX='..p:getVariableFloat('ToolkitCartStepX',0)..' stepY='..p:getVariableFloat('ToolkitCartStepY',0)
   ..' visualHeading='..cartLabHeading()..' acceptedHeading='..heading..' stage='..stage..' accumulated='..accumulated
   ..' bank='..cartLabBank()..' stationary='..cartLabStationary()..' tracks='..cartLabTracks())
 end
 local age=now-stageSince
 if stage=='rest' and age>=700 then
  lastHeading=heading;pivotStart=now;enter('pivot',c.side=='left' and 2 or 3,now)
 elseif stage=='pivot' then
  local sign=c.side=='left' and -1 or 1
  if sign*accumulated>=math.pi then
   -- The marker proves measured accumulated yaw; a timeout never completes this phase.
   event('pivot-complete',now);enter('released',0,now)
  end
 elseif stage=='released' and age>=1400 then enter('forward-exit',1,now)
 elseif stage=='forward-exit' and age>=1100 then enter('moving-entry',c.side=='left' and 5 or 8,now)
 elseif stage=='moving-entry' and age>=1000 then enter('final-rest',0,now)
 elseif stage=='final-rest' and age>=1000 then
  event('clip-complete',now);assert(toolkitVideoStop(),'Video stop rejected');mode='finish'
 end
end
WoodPrototypeTick=function()
 local ok,err=pcall(tick)
 if not ok then
  Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil;cartLabDrive(-1);cartLabGait(0);toolkitVideoStop()
  print('[WOOD_BANK] FAIL '..tostring(err))
 end
end
print('[WOOD_BANK] RUN_STARTED')
getCore():setAutoZoom(0,false)
for i=1,16 do getCore():doZoomScroll(0,-1) end
nextCase();Events.OnTick.Add(WoodPrototypeTick)
