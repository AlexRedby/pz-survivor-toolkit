-- Native obstacles; all actor resets and fixture edits finish before capture.
local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true and getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable SP CartTestArea required')
require 'TimedActions/ISTimedActionQueue'
local p,area=assert(getPlayer()),assert(CartTestArea)
assert(area.ready and CartLabSelectScenes and CartLabKey and cartLabDrive and cartLabGait and cartLabHeading and cartLabSteeringHeading and cartLabFrame and cartLabStationary and cartLabReversal and cartLabFootprint and cartLabBrace and cartLabPoseHeading and toolkitVideoStart and toolkitVideoStatus and toolkitVideoStop,'Obstacle matrix bridges missing')
for _,key in ipairs({'videoRoot','ffmpeg'}) do
 local value=config[key]
 assert(type(value)=='string' and (value:sub(1,1)=='/' or value:match('^%a:[/\\]') or value:sub(1,2)=='\\\\'),'Absolute '..key..' required')
end
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
local specs={'frontal','slide-left','slide-right','corner','door-closed','door-open'}
local cases={}
for _,sex in ipairs({'male','female'}) do for _,load in ipairs({'empty','full'}) do for gait=0,2 do for _,spec in ipairs(specs) do
 cases[#cases+1]={female=sex=='female',full=load=='full',gait=gait,spec=spec,name=sex..'-'..load..'-'..({'walk','run','sprint'})[gait+1]..'-'..spec}
end end end end
assert(#cases==72);cases=CartLabSelectScenes(cases)
local wx,gy,sy=math.floor(area.x)-4,math.floor(area.y),math.floor(area.y)+6
local lo,hi=area.minY+area.margin+2,area.minY+area.size-area.margin-3
assert(hi-lo>=50 and area.contains(wx-15,gy,area.z) and area.contains(wx+15,gy,area.z),'Obstacle bank requires safe runway')
local function encode(row)
 local out={}
 for key,value in pairs(row) do
  if type(value)=='string' then value='"'..value:gsub('[%z\1-\31\\"]',function(ch)return string.format('\\u%04x',string.byte(ch))end)..'"'
  elseif type(value)=='number' then assert(value==value and math.abs(value)<math.huge,'Nonfinite obstacle evidence');value=tostring(value)
  else assert(type(value)=='boolean','Invalid obstacle evidence');value=tostring(value) end
  out[#out+1]='"'..key..'":'..value
 end
 return '{'..table.concat(out,',')..'}'
end
local function emit(kind,row) print('[CART_OBSTACLE_MATRIX] '..kind..' '..encode(row)) end
local item,itemID,cargoIDs,cargoWeight,c,index,controlIndex,stage,attempt,mode,since,recordStart,lastSample
index=0;controlIndex=0;attempt=0
local phases
local function cargo(cart)
 local ids={};local items=cart:getInventory():getItems()
 for i=0,items:size()-1 do ids[#ids+1]=tostring(items:get(i):getID()) end
 table.sort(ids);return #ids==0 and 'empty' or table.concat(ids,',')
end
local function owned()
 if mode=='control' or mode=='control-settle' then
  assert(not p:getPrimaryHandItem() and not p:getSecondaryHandItem(),'Native control must be bare')
 else
  assert(item and p:getPrimaryHandItem()==item and p:getSecondaryHandItem()==item and item:getID()==itemID and item:getContainer()==p:getInventory() and not item:getWorldItem(),'Obstacle motion changed exact cart ownership')
  local count=0;local all=p:getInventory():getItems()
  for i=0,all:size()-1 do if all:get(i):getID()==itemID then count=count+1 end end
  assert(count==1 and cargo(item)==cargoIDs and math.abs(item:getInventory():getCapacityWeight()-cargoWeight)<.001,'Obstacle motion changed exact cargo or inventory count')
 end
 assert(#ISTimedActionQueue.getTimedActionQueue(p).queue==0 and p:getCharacterActions():isEmpty() and not p:hasPath(),'Obstacle inputs created actions/path')
end
local function layout(spec)
 area.check(p);area.clearObstacles(p)
 local walls={}
 for y=lo,hi do
  if not spec:find('door',1,true) or y~=gy then walls[#walls+1]={x=wx,y=y,axis='W'} end
 end
 if spec=='corner' then for x=wx,wx+15 do walls[#walls+1]={x=x,y=sy,axis='N'} end end
 if spec:find('door',1,true) then walls[#walls+1]={x=wx,y=gy,axis='W',kind='door',open=spec=='door-open'} end
 area.setObstacles(p,walls);area.check(p)
 local count,doors=0,0
 for object,wall in pairs(area.obstacles) do
  count=count+1
  if wall.kind=='door' then doors=doors+1;assert(object:isOpen()==(spec=='door-open'),'Wrong native door state') end
 end
 assert(count==#walls and doors==(spec:find('door',1,true) and 1 or 0),'Incomplete owned layout')
 for object,wall in pairs(area.obstacles) do if wall.kind=='door' then
  local square=object:getSquare();local opposite=assert(getCell():getGridSquare(wall.x-1,wall.y,area.z))
  emit('DOOR',{spec=spec,x=wall.x,y=wall.y,axis=wall.axis,open=object:isOpen(),blocked=object:isBlocked(),blockedForward=square:isDoorBlockedTo(opposite),blockedBackward=opposite:isDoorBlockedTo(square),sprite=object:getSpriteName()})
 end end
 return count
end
local function pose(spec)
 local x,y,heading=wx+(spec=='door-open' and 1.8 or 3.8),gy+.5,math.pi
 if spec=='slide-left' then y=gy-12+.5;heading=math.pi*.75
 elseif spec=='slide-right' then y=gy+12+.5;heading=-math.pi*.75
 elseif spec=='corner' then y=sy-3.8;heading=math.pi*.75 end
 p:setX(x);p:setY(y);p:setZ(area.z);p:setNextX(x);p:setNextY(y);p:setLastX(x);p:setLastY(y)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow();cartLabPoseHeading(heading)
 area.checkPosition(p)
 return x,y,heading
end
local function equip()
 if p:isFemale()~=c.female then p:setFemale(c.female);p:getDescriptor():setFemale(c.female);p:resetModel() end
 for _=1,3 do
  if p:getPrimaryHandItem() and p:getPrimaryHandItem():getFullType()=='SaucedWheelbarrow.WheelbarrowWood' then break end
  CartLabKey(Keyboard.KEY_F5)
 end
 CartLabKey(Keyboard.KEY_F7);CartLabKey(Keyboard.KEY_F7)
 item=assert(p:getPrimaryHandItem(),'Cart missing')
 if (item:getInventory():getCapacityWeight()>0)~=c.full then CartLabKey(Keyboard.KEY_F6) end
 item=p:getPrimaryHandItem();assert(item:getFullType()=='SaucedWheelbarrow.WheelbarrowWood','Wrong cart')
 itemID=item:getID();cargoIDs=cargo(item);cargoWeight=item:getInventory():getCapacityWeight()
 assert(c.full and math.abs(cargoWeight-item:getInventory():getEffectiveCapacity(p))<.01 or not c.full and cargoWeight==0,'Wrong cart load')
 p:setPerkLevelDebug(Perks.Sprinting,10);p:getXp():setXPToLevel(Perks.Sprinting,10)
 assert(p:getPerkLevel(Perks.Sprinting)==10,'Sprint eligibility missing');p:getStats():reset(CharacterStat.ENDURANCE)
end
local function setup()
 c.fastDoor=c.spec=='door-open' and c.gait>0
 phases={{0,0,0},{800,nil,1},{c.fastDoor and 3000 or 6800,0,0},{c.fastDoor and 4000 or 8000,0,4},{13000,0,0}}
 c.quietSince=nil;c.quietX=nil;c.quietY=nil;c.quietHeading=nil
 -- Change this disposable process only; never persist the user's mod settings.
 if PZAPI and PZAPI.ModOptions then
  local options=PZAPI.ModOptions:getOptions('MiniHealthPlus')
  local option=options and options:getOption('DisableMod')
  if option and option:getValue()~=true then
   option:setValue(true)
   if TwisTonFire_MHP_RefreshModOptions then TwisTonFire_MHP_RefreshModOptions() end
  end
 end
 cartLabDrive(0);cartLabGait(0);equip();local count=layout(c.spec);local x,y,h=pose(c.spec)
 c.layout={case=c.name,wallX=wx,gapY=gy,southY=sy,minY=lo,maxY=hi,owned=count,doors=c.spec:find('door',1,true) and 1 or 0,startX=x,startY=y,heading=h}
 mode='settle';since=getTimestampMs()+1800;owned()
end
local function nextCase()
 index=index+1;attempt=0
 if index>#cases then
  cartLabDrive(0);cartLabGait(0);area.clearObstacles(p);area.check(p)
  print('[CART_OBSTACLE_MATRIX] CLEANUP_COMPLETE');print('[WOOD_BANK] ALL_COMPLETE cases='..#cases)
  cartLabDrive(-1);Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil;return
 end
 c=cases[index];setup()
end
local function controlDrive(spec) return (spec=='slide-left' or spec=='corner') and 2 or spec=='slide-right' and 1 or 5 end
local function nextControl()
 cartLabDrive(0);cartLabGait(0);controlIndex=controlIndex+1
 if controlIndex>#specs then nextCase();return end
 local spec=specs[controlIndex];local count=layout(spec);local x,y,h=pose(spec)
 emit('CONTROL_LAYOUT',{spec=spec,wallX=wx,gapY=gy,southY=sy,minY=lo,maxY=hi,owned=count,doors=spec:find('door',1,true) and 1 or 0,startX=x,startY=y,heading=h})
 mode='control-settle';since=getTimestampMs()+1800
end
local function sample(now)
 if now==lastSample then return end
 lastSample=now;owned()
 emit('SAMPLE',{case=c.name,wall=now,elapsed=now-recordStart,frame=cartLabFrame(),x=p:getX(),y=p:getY(),heading=cartLabHeading(),acceptedHeading=cartLabSteeringHeading(),
  drive=phases[stage][3],gait=phases[stage][2] or c.gait,run=p:isRunning(),sprint=p:isSprinting(),skill=p:getPerkLevel(Perks.Sprinting),
  forward=isKeyDown(getCore():getKey('Forward')),backward=isKeyDown(getCore():getKey('Backward')),
  left=isKeyDown(getCore():getKey('Left')),right=isKeyDown(getCore():getKey('Right')),
  runKey=isKeyDown(getCore():getKey('Run')),sprintKey=isKeyDown(getCore():getKey('Sprint')),
  root=cartLabStationary(),reversal=cartLabReversal(),footprint=cartLabFootprint(),brace=cartLabBrace(wx,p:getY()),id=itemID,cargoIDs=cargoIDs,cargoWeight=cargoWeight})
end
local function tick()
 local now=getTimestampMs()
 local data=getPlayerData(0)
 if data and data.characterInfo then data.characterInfo:setVisible(false) end
 if ISChat and ISChat.instance then ISChat.instance:setVisible(false) end
 area.checkPosition(p);owned()
 if mode=='control-settle' then
  if now<since then return end
  area.check(p);since=getTimestampMs();lastSample=-1;mode='control';cartLabDrive(controlDrive(specs[controlIndex]));return
 end
 if mode=='control' then
  local spec=specs[controlIndex]
  if now-lastSample>=100 then
   lastSample=now;emit('CONTROL_SAMPLE',{spec=spec,wall=now,elapsed=now-since,x=p:getX(),y=p:getY(),heading=cartLabHeading(),bare=true,drive=controlDrive(spec),run=p:isRunning(),sprint=p:isSprinting(),tracks=cartLabTracks()})
  end
  if now-since>=6000 then emit('CONTROL_END',{spec=spec,wall=now,elapsed=now-since,x=p:getX(),y=p:getY()});nextControl() end
  return
 end
 if mode=='settle' then
  if now<since then return end
  local ready,why=pcall(area.check,p)
  if not ready then assert(now-since<6000,'Pad did not reload: '..tostring(why));return end
  assert(toolkitVideoStart(config.videoRoot..'/'..c.name..'-'..attempt,config.ffmpeg),'Video start rejected')
  recordStart=getTimestampMs();lastSample=-1;stage=1;c.openReleased=false;mode='record'
  print('[WOOD_BANK] CASE '..c.name..' attempt='..attempt..' wall='..recordStart);emit('LAYOUT',c.layout)
  emit('PHASE',{case=c.name,wall=recordStart,elapsed=0,gait=0,drive=0});print('[WOOD_RAMP_EVENT] case='..c.name..' elapsed=0 gait=0 drive=0');sample(recordStart);return
 end
 local video=toolkitVideoStatus()
 if video.state=='failed' then
  cartLabDrive(0);cartLabGait(0);attempt=attempt+1;assert(attempt<=2,'Repeated video failure: '..tostring(video.error))
  print('[WOOD_BANK] RETRY '..c.name..' reason='..tostring(video.error));setup();return
 end
 if mode=='finish' then
  assert(now-since<15000,'Video completion timed out')
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE '..c.name..' wall='..recordStart..' file='..tostring(video.file)..' frames='..tostring(video.frames)..' seconds='..tostring(video.seconds));nextCase()
  end
  return
 end
 local elapsed=now-recordStart
 -- A short measured crossing leaves runway for manual loaded backward Walk.
 if c.spec=='door-open' and stage==2 and p:getX()<=wx-1 then
  stage=3;c.openReleased=true;cartLabGait(0);cartLabDrive(0)
  emit('PHASE',{case=c.name,wall=now,elapsed=elapsed,gait=0,drive=0})
  print('[WOOD_RAMP_EVENT] case='..c.name..' elapsed='..elapsed..' gait=0 drive=0');sample(now)
 end
 -- Observe actual stopped pose while neutral, before requesting manual backward input.
 if c.fastDoor and stage==3 then
  local x,y,h=p:getX(),p:getY(),cartLabSteeringHeading()
  if not c.quietSince or math.abs(x-c.quietX)>1e-6 or math.abs(y-c.quietY)>1e-6 or math.abs(h-c.quietHeading)>1e-6 or p:isRunning() or p:isSprinting() then c.quietSince=now end
  c.quietX=x;c.quietY=y;c.quietHeading=h
 end
 while stage<#phases and elapsed>=phases[stage+1][1] do
  assert(c.spec~='door-open' or stage~=2,'Open door crossing did not reach bounded release plane')
  stage=stage+1;local command=phases[stage];local gait=command[2] or c.gait
  local neutralMs=c.fastDoor and stage==4 and c.quietSince and now-c.quietSince or 0
  assert(not c.fastDoor or stage~=4 or neutralMs>=500,'Fast open-door reverse requires 500ms measured stopped neutral pose')
  cartLabGait(gait);cartLabDrive(command[3]);emit('PHASE',{case=c.name,wall=now,elapsed=elapsed,gait=gait,drive=command[3],neutralMs=neutralMs})
  print('[WOOD_RAMP_EVENT] case='..c.name..' elapsed='..elapsed..' gait='..gait..' drive='..command[3])
 end
 if elapsed<16000 and now-lastSample>=100 then sample(now) end
 if elapsed>=16000 then cartLabDrive(0);cartLabGait(0);assert(toolkitVideoStop(),'Video stop rejected');mode='finish';since=now end
end
WoodPrototypeTick=function()
 local ok,why=pcall(tick)
 if not ok then
  cartLabDrive(0);cartLabGait(0);toolkitVideoStop();Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  local cleaned,cleanupWhy=pcall(area.clearObstacles,p)
  print('[WOOD_BANK] FAIL '..tostring(why)..(cleaned and '' or '; cleanup: '..tostring(cleanupWhy)));cartLabDrive(-1)
 end
end
print('[WOOD_BANK] RUN_STARTED')
print('[CART_OBSTACLE_MATRIX] SCOPE relative-keyboard-v1; native motion and mesh gates; body/grip/feet/video are independent')
if p:getPrimaryHandItem() then CartLabKey(Keyboard.KEY_F7) end
assert(not p:getPrimaryHandItem() and not p:getSecondaryHandItem(),'Bare controls require empty hands')
mode='control-settle';nextControl();Events.OnTick.Add(WoodPrototypeTick)
