local config=assert(CartMotionConfig,'CartMotionConfig required')
require "TimedActions/WalkToTimedActionF"
assert(config.disposable==true and getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable SP CartTestArea required')
local area,p=assert(CartTestArea),assert(getPlayer())
assert(area.ready and cartLabDrive and cartLabGait and cartLabPoseHeading and cartLabHeading and cartLabFootprint,'Cart lab bridge missing')
assert(type(config.videoRoot)=='string' and config.videoRoot:sub(1,1)=='/' and type(config.ffmpeg)=='string' and config.ffmpeg:sub(1,1)=='/','Absolute video paths required')
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
p:clearWornItems()
for _,name in ipairs({'Base.Tshirt_DefaultTEXTURE_TINT','Base.Trousers_JeanBaggy','Base.Shoes_TrainerTINT'}) do
 local item=assert(p:getInventory():AddItem(name));p:setWornItem(item:getBodyLocation(),item)
end
local cases={}
for _,female in ipairs({false,true}) do for _,full in ipairs({false,true}) do
 for _,spec in ipairs({'straight','corner','door-open','door-closed','overlap','cancel'}) do
  cases[#cases+1]={female=female,full=full,spec=spec,name=(female and 'female-' or 'male-')..(full and 'full-' or 'empty-')..spec}
 end
end end
local phase,since,sampled,attempt=0,0,0,0
local mode,action,item,terminalAt,manualAt,manualDrive,queuedAt,cancelled
local goalX,goalY,startX,startY,cargo,door
local wx,gy=math.floor(area.x)-3,math.floor(area.y)
local function queue() return ISTimedActionQueue.getTimedActionQueue(p).queue end
local function encode(record)
 local out={}
 for key,value in pairs(record) do
  local t=type(value)
  if t=='string' then value='"'..value:gsub('[%z\1-\31\\"]',function(char) return string.format('\\u%04x',string.byte(char)) end)..'"'
  elseif t=='number' then assert(value==value and math.abs(value)<math.huge,'Nonfinite path sample');value=tostring(value)
  else assert(t=='boolean','Invalid path sample');value=tostring(value) end
  out[#out+1]='"'..key..'":'..value
 end
 return '{'..table.concat(out,',')..'}'
end
local function snapshot(now)
 assert(item==p:getPrimaryHandItem() and item==p:getSecondaryHandItem() and item:getContainer()==p:getInventory() and not item:getWorldItem(),'Path changed cart ownership')
 assert(math.abs(item:getInventory():getCapacityWeight()-cargo)<.001,'Path changed cargo')
 area.checkPosition(p)
 local result=action and action.result
 return {case=cases[phase].name,start=since,wall=now,elapsed=now-since,x=p:getX(),y=p:getY(),z=p:getZ(),
  female=p:isFemale(),id=item:getID(),cargo=cargo,hasPath=p:hasPath(),nativeActions=p:getCharacterActions():size(),
  luaActions=#queue(),motion=p:getVariableBoolean('ToolkitCartMotion'),pivot=p:getVariableBoolean('ToolkitCartPivot'),
  result=result==BehaviorResult.Succeeded and 'Succeeded' or result==BehaviorResult.Failed and 'Failed' or result==BehaviorResult.Working and 'Working' or '',
  heading=cartLabHeading(),drive=manualDrive or 0,goalX=goalX,goalY=goalY,startX=startX,startY=startY,
  wallX=wx,gapY=gy,doorOpen=door and door:isOpen() or false}
end
local function event(name,now)
 local record=snapshot(now);record.event=name;print('[CART_PATH_EVENT] '..encode(record))
end
local function reverseDrive()
 local best,score=1,2
 for index,degrees in ipairs({225,135,315,45,180,90,0,270}) do
  local dot=math.cos(cartLabHeading()-math.rad(degrees))
  if dot<score then best=index;score=dot end
 end
 return best
end
local function prepare()
 assert(#queue()==0 and p:getCharacterActions():isEmpty() and not p:hasPath(),'Previous native path/action not cleared')
 cartLabDrive(0);cartLabGait(0);manualDrive=0
 area.clearObstacles(p)
 local c=cases[phase]
 if p:isFemale()~=c.female then p:setFemale(c.female);p:getDescriptor():setFemale(c.female) end
 p:resetModel()
 for _=1,3 do
  if p:getPrimaryHandItem() and p:getPrimaryHandItem():getFullType()=='SaucedWheelbarrow.WheelbarrowWood' then break end
  CartLabKey(Keyboard.KEY_F5)
 end
 CartLabKey(Keyboard.KEY_F7);CartLabKey(Keyboard.KEY_F7)
 item=assert(p:getPrimaryHandItem());assert(item:getFullType()=='SaucedWheelbarrow.WheelbarrowWood','Wrong cart')
 if (item:getInventory():getCapacityWeight()>0)~=c.full then CartLabKey(Keyboard.KEY_F6) end
 item=assert(p:getPrimaryHandItem());assert(item:getFullType()=='SaucedWheelbarrow.WheelbarrowWood' and item==p:getSecondaryHandItem(),'Wrong loaded cart')
 cargo=item:getInventory():getCapacityWeight();assert(c.full and cargo>0 or not c.full and cargo==0,'Wrong load')
 startX,startY=wx+2.5,gy+.5;goalX,goalY=wx-2.5,gy+.5;door=nil
 local walls={}
 if c.spec=='straight' or c.spec=='cancel' then
  goalX=startX-4
 elseif c.spec=='corner' then
  for y=gy-2,gy+2 do walls[#walls+1]={x=wx,y=y,axis='W'} end
 elseif c.spec=='overlap' then
  startX=wx+.65;goalX=wx+3.5
  for y=gy-24,gy+24 do walls[#walls+1]={x=wx,y=y,axis='W'} end
 else
  for y=gy-4,gy+4 do
   if y~=gy then walls[#walls+1]={x=wx,y=y,axis='W'} end
   walls[#walls+1]={x=wx-5,y=y,axis='W'}
  end
  for x=wx-5,wx-1 do
   walls[#walls+1]={x=x,y=gy-4,axis='N'}
   walls[#walls+1]={x=x,y=gy+5,axis='N'}
  end
  walls[#walls+1]={x=wx,y=gy,axis='W',kind='door',open=c.spec=='door-open'}
 end
 if #walls>0 then
  for object,wall in pairs(area.setObstacles(p,walls)) do
   if wall.kind=='door' then
    door=object
    if c.spec=='door-closed' then door:setLocked(true);door:setLockedByKey(true) end
   end
  end
 end
 p:setX(startX);p:setY(startY);p:setZ(area.z);p:setNextX(startX);p:setNextY(startY);p:setLastX(startX);p:setLastY(startY)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow();cartLabPoseHeading(math.pi)
 p:getStats():reset(CharacterStat.ENDURANCE)
 action=nil;terminalAt=nil;manualAt=nil;queuedAt=nil;cancelled=false;sampled=0
 mode='settle';since=getTimestampMs()+1800
end
local function nextCase()
 phase=phase+1;attempt=0
 if phase>#cases then
  area.clearObstacles(p);cartLabDrive(-1)
  print('[CART_PATH] CLEANUP_COMPLETE');print('[WOOD_BANK] ALL_COMPLETE cases='..#cases)
  Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil;return
 end
 prepare()
end
CartLabHUD.prerender=function(self)
 self:drawRect(0,0,self.width,self.height,.85,0,0,0)
 local c=cases[phase];self:drawText(c and c.name..' wallMs='..math.max(0,getTimestampMs()-since) or 'Complete',10,5,1,1,1,1,UIFont.Medium)
end
local function tick()
 local data=getPlayerData(0)
 if data and data.characterInfo then data.characterInfo:setVisible(false) end
 if ISChat and ISChat.instance then ISChat.instance:setVisible(false) end
 getCore():setAutoZoom(0,false)
 if getCore():getZoom(0)>.251 then getCore():doZoomScroll(0,-1) end
 local now=getTimestampMs();local c=cases[phase]
 if mode=='settle' then
  if now<since then return end
  area.check(p);assert(toolkitVideoStart(config.videoRoot..'/'..c.name..'-'..attempt,config.ffmpeg),'Video start rejected')
  since=getTimestampMs();mode='record';print('[WOOD_BANK] CASE '..c.name..' attempt='..attempt..' wall='..since);event('prepared',since);return
 end
 local video=toolkitVideoStatus();assert(video.state~='failed','Path video failed: '..tostring(video.error))
 if mode=='finish' then
  assert(now-since<28000,'Video finalization timed out')
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE '..c.name..' wall='..since..' file='..video.file..' frames='..video.frames..' seconds='..video.seconds);nextCase()
  end
  return
 end
 local elapsed=now-since;local row=snapshot(now)
 if now-sampled>=25 then sampled=now;print('[CART_PATH_SAMPLE] '..encode(row)) end
 if not queuedAt and elapsed>=1000 then
  action=ISWalkToTimedActionF:new(p,Vector3f.new(goalX,goalY,area.z))
  ISTimedActionQueue.add(action);queuedAt=now;event('queued',now)
 elseif action and not terminalAt then
  assert(now-queuedAt<8500,'Native cart path did not terminate within bounded window')
  if c.spec=='cancel' and not cancelled and p:hasPath() and now-queuedAt>=500 then
   cancelled=true;event('cancelRequested',now);CancelAction(p:getPlayerNum())
  end
  if #queue()==0 and p:getCharacterActions():isEmpty() then
   assert(not p:hasPath(),'Completed action retained native path')
   assert(cancelled or action.result==BehaviorResult.Succeeded or action.result==BehaviorResult.Failed,'Path ended without native result')
   terminalAt=now;event('terminal',now)
  end
 elseif terminalAt and not manualAt and now-terminalAt>=250 then
  manualAt=now;manualDrive=reverseDrive();cartLabDrive(manualDrive);event('manual',now)
 elseif manualAt and manualDrive~=0 and now-manualAt>=(c.spec=='overlap' and 1800 or 900) then
  manualDrive=0;cartLabDrive(0);event('manualStopped',now)
 end
 if elapsed>=12000 then
  assert(terminalAt and manualAt and manualDrive==0 and #queue()==0 and p:getCharacterActions():isEmpty() and not p:hasPath(),'Path cleanup/manual control incomplete')
  event('settled',now);assert(toolkitVideoStop(),'Video stop rejected');mode='finish'
 end
end
WoodPrototypeTick=function()
 local ok,why=pcall(tick)
 if not ok then
  cartLabDrive(-1);toolkitVideoStop();Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  print('[WOOD_BANK] FAIL '..tostring(why))
 end
end
print('[WOOD_BANK] RUN_STARTED');nextCase();Events.OnTick.Add(WoodPrototypeTick)
