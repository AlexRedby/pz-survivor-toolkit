-- Native relative-key motion. Pose resets belong exclusively to pre-capture setup.
local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true and getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable SP CartTestArea required')
require 'TimedActions/ISTimedActionQueue'
local p,area=assert(getPlayer()),assert(CartTestArea)
assert(area.ready and CartLabKey and CartLabSelectScenes and cartLabDrive and cartLabGait and cartLabHeading and cartLabSteeringHeading and cartLabFrame and cartLabStationary and cartLabPoseHeading and toolkitVideoStart and toolkitVideoStatus and toolkitVideoStop,'Motion matrix bridges missing')
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
local cases={}
for _,sex in ipairs({'male','female'}) do for _,load in ipairs({'empty','full'}) do
 for gait=0,2 do for _,spec in ipairs({'arcs','slalom-up','slalom-down'}) do
  cases[#cases+1]={female=sex=='female',full=load=='full',gait=gait,spec=spec,name=sex..'-'..load..'-'..({'walk','run','sprint'})[gait+1]..'-'..spec}
 end end
end end
assert(#cases==36);cases=CartLabSelectScenes(cases)
local function encode(row)
 local out={}
 for key,value in pairs(row) do
  if type(value)=='string' then value='"'..value:gsub('[%z\1-\31\\"]',function(c)return string.format('\\u%04x',string.byte(c))end)..'"'
  elseif type(value)=='number' then assert(value==value and math.abs(value)<math.huge,'Nonfinite motion evidence');value=tostring(value)
  else assert(type(value)=='boolean','Invalid motion evidence');value=tostring(value) end
  out[#out+1]='"'..key..'":'..value
 end
 return '{'..table.concat(out,',')..'}'
end
local function emit(kind,row)print('[CART_MATRIX] '..kind..' '..encode(row))end
local function wrap(a)return math.atan2(math.sin(a),math.cos(a))end
local index,phaseIndex,attempt=0,0,0
local c,item,itemID,cargoIDs,cargoWeight,phases,phase,mode,since,recordStart,phaseStart,lastSample,lastHeading,yaw
local function cargo(cart)
 local ids={};local items=cart:getInventory():getItems()
 for i=0,items:size()-1 do ids[#ids+1]=tostring(items:get(i):getID()) end
 table.sort(ids);return #ids==0 and 'empty' or table.concat(ids,',')
end
local function owned()
 assert(p:getPrimaryHandItem()==item and p:getSecondaryHandItem()==item and item:getID()==itemID and item:getContainer()==p:getInventory() and not item:getWorldItem(),'Motion changed exact cart ownership')
 assert(cargo(item)==cargoIDs and math.abs(item:getInventory():getCapacityWeight()-cargoWeight)<.001,'Motion changed exact cargo')
 assert(#ISTimedActionQueue.getTimedActionQueue(p).queue==0 and p:getCharacterActions():isEmpty() and not p:hasPath(),'Motion created native actions/path')
end
local function schedule()
 local out={}
 local function add(name,drive,gait,duration,target)
  out[#out+1]={name=name,drive=drive,gait=gait,duration=duration,target=target,deadline=target and 2000+math.abs(math.deg(target))*50 or duration+500}
 end
 add('idle',0,0,800);add('straight',1,c.gait,2200)
 if c.spec=='arcs' then
  for _,side in ipairs({'left','right'}) do for _,degrees in ipairs({45,90,135,180}) do
   add('arc-'..side..degrees,side=='left' and 5 or 8,c.gait,nil,math.rad(degrees)*(side=='left' and -1 or 1))
   add('release-'..side..degrees,1,c.gait,800)
  end end
  add('stop-arc',5,c.gait,nil,-math.rad(45))
 else
  for _,interval in ipairs({300,600,900}) do for switch=1,4 do
   add('slalom-'..interval..'-'..switch,switch%2==1 and 5 or 8,c.gait,interval)
  end end
  add('release',1,c.gait,800)
 end
 add('stop',0,0,3500)
 out[#out+1]={name='tail',drive=0,gait=0}
 return out
end
local function disableOverlay()
 if PZAPI and PZAPI.ModOptions then
  local options=PZAPI.ModOptions:getOptions('MiniHealthPlus')
  local option=options and options:getOption('DisableMod')
  if option and option:getValue()~=true then
   option:setValue(true)
   if TwisTonFire_MHP_RefreshModOptions then TwisTonFire_MHP_RefreshModOptions() end
  end
 end
end
local function setup()
 disableOverlay()
 cartLabDrive(0);cartLabGait(0)
 if p:isFemale()~=c.female then p:setFemale(c.female);p:getDescriptor():setFemale(c.female);p:resetModel() end
 for _=1,3 do
  if p:getPrimaryHandItem() and p:getPrimaryHandItem():getFullType()=='SaucedWheelbarrow.WheelbarrowWood' then break end
  CartLabKey(Keyboard.KEY_F5)
 end
 CartLabKey(Keyboard.KEY_F7);CartLabKey(Keyboard.KEY_F7)
 item=assert(p:getPrimaryHandItem(),'Cart missing')
 assert(item:getFullType()=='SaucedWheelbarrow.WheelbarrowWood','Wrong cart')
 if (item:getInventory():getCapacityWeight()>0)~=c.full then CartLabKey(Keyboard.KEY_F6) end
 item=p:getPrimaryHandItem();itemID=item:getID();cargoIDs=cargo(item);cargoWeight=item:getInventory():getCapacityWeight()
 assert(c.full and math.abs(cargoWeight-item:getInventory():getEffectiveCapacity(p))<.01 or not c.full and cargoWeight==0,'Wrong cart load')
 p:setPerkLevelDebug(Perks.Sprinting,10);p:getXp():setXPToLevel(Perks.Sprinting,10)
 assert(p:getPerkLevel(Perks.Sprinting)==10,'Sprint eligibility missing')
 p:getStats():reset(CharacterStat.ENDURANCE)
 local heading=c.spec=='slalom-down' and math.pi/4 or -math.pi*3/4
 -- Give fast slaloms a runway across the owned pad; never reposition during recording.
 local runway=c.spec=='arcs' and 0 or 20
 local x,y=area.x-math.cos(heading)*runway,area.y-math.sin(heading)*runway
 p:setX(x);p:setY(y);p:setZ(area.z);p:setNextX(x);p:setNextY(y);p:setLastX(x);p:setLastY(y)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow()
 cartLabPoseHeading(heading)
 area.checkPosition(p);owned();mode='settle';since=getTimestampMs()+1800
end
local function sample(now)
 if now==lastSample then return end
 lastSample=now;owned()
 emit('SAMPLE',{case=c.name,phase=phase.name,index=phaseIndex,wall=now,elapsed=now-recordStart,phaseElapsed=now-phaseStart,
  frame=cartLabFrame(),x=p:getX(),y=p:getY(),heading=cartLabHeading(),acceptedHeading=cartLabSteeringHeading(),yaw=yaw,
  drive=phase.drive,gait=phase.gait,run=p:isRunning(),sprint=p:isSprinting(),skill=p:getPerkLevel(Perks.Sprinting),
  stepX=p:getVariableFloat('ToolkitCartStepX',0),stepY=p:getVariableFloat('ToolkitCartStepY',0),
  forward=isKeyDown(getCore():getKey('Forward')),backward=isKeyDown(getCore():getKey('Backward')),
  left=isKeyDown(getCore():getKey('Left')),right=isKeyDown(getCore():getKey('Right')),
  runKey=isKeyDown(getCore():getKey('Run')),sprintKey=isKeyDown(getCore():getKey('Sprint')),
  root=cartLabStationary(),id=itemID,cargoIDs=cargoIDs,cargoWeight=cargoWeight})
end
local function nextPhase(now)
 phaseIndex=phaseIndex+1
 if phaseIndex>#phases then
  cartLabDrive(0);cartLabGait(0);assert(toolkitVideoStop(),'Video stop rejected');mode='finish';since=now;return
 end
 phase=phases[phaseIndex]
 if phase.name=='tail' then
  phase.duration=recordStart+(c.spec=='arcs' and 90000 or 20000)-now
  assert(phase.duration>=1000,'Motion phases exceeded fixed capture budget');phase.deadline=phase.duration+500
 end
 phaseStart=now;lastSample=-1;lastHeading=cartLabSteeringHeading();yaw=0
 cartLabGait(phase.gait);cartLabDrive(phase.drive)
 print('[WOOD_RAMP_EVENT] case='..c.name..' elapsed='..(now-recordStart)..' gait='..phase.gait..' drive='..phase.drive)
 emit('PHASE',{case=c.name,phase=phase.name,index=phaseIndex,wall=now,drive=phase.drive,gait=phase.gait,target=phase.target or 0,duration=phase.duration or 0,deadline=phase.deadline})
 sample(now)
end
local function nextCase()
 index=index+1
 if index>#cases then
  cartLabDrive(-1);cartLabGait(0);Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  print('[WOOD_BANK] ALL_COMPLETE cases='..#cases);return
 end
 c=cases[index];phases=schedule();phaseIndex=0;attempt=0;setup()
end
local function tick()
 disableOverlay()
 local now=getTimestampMs()
 local data=getPlayerData(0)
 if data and data.characterInfo then data.characterInfo:setVisible(false) end
 if ISChat and ISChat.instance then ISChat.instance:setVisible(false) end
 area.checkPosition(p);owned()
 if mode=='settle' then
  if now<since then return end
  local ready,why=pcall(area.check,p)
  if not ready then assert(now-since<6000,'Pad did not reload: '..tostring(why));return end
  assert(toolkitVideoStart(config.videoRoot..'/'..c.name..'-'..attempt,config.ffmpeg),'Video start rejected')
  now=getTimestampMs();recordStart=now;phaseIndex=0;mode='record'
  print('[WOOD_BANK] CASE '..c.name..' attempt='..attempt..' wall='..recordStart)
  nextPhase(now);return
 end
 local video=toolkitVideoStatus()
 if video.state=='failed' then
  cartLabDrive(0);cartLabGait(0);attempt=attempt+1;assert(attempt<=2,'Repeated video failure: '..tostring(video.error))
  print('[WOOD_BANK] RETRY '..c.name..' reason='..tostring(video.error));setup();return
 end
 if mode=='finish' then
  assert(now-since<15000,'Video completion timed out')
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE '..c.name..' wall='..recordStart..' file='..tostring(video.file)..' frames='..tostring(video.frames)..' seconds='..tostring(video.seconds))
   nextCase()
  end
  return
 end
 local heading=cartLabSteeringHeading();yaw=yaw+wrap(heading-lastHeading);lastHeading=heading
 local elapsed=now-phaseStart
 assert(elapsed<=phase.deadline,'Motion phase deadline: '..phase.name)
 if now-lastSample>=100 then sample(now) end
 local done=phase.target and yaw*(phase.target<0 and -1 or 1)>=math.abs(phase.target) or not phase.target and elapsed>=phase.duration
 if done then
  sample(now);emit('END',{case=c.name,phase=phase.name,index=phaseIndex,wall=now,elapsed=elapsed,yaw=yaw})
  nextPhase(now)
 end
end
WoodPrototypeTick=function()
 local ok,why=pcall(tick)
 if not ok then
  cartLabDrive(-1);cartLabGait(0);toolkitVideoStop();Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  print('[WOOD_BANK] FAIL '..tostring(why))
 end
end
print('[WOOD_BANK] RUN_STARTED')
print('[CART_MATRIX] SCOPE relative-keyboard-v1 movement only; geometry and visual quality are separate')
nextCase();Events.OnTick.Add(WoodPrototypeTick)
