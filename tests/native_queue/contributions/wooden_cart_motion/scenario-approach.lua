-- Public-menu pickup edges. Fixture setup alone relocates actors/items; every measured move is native.
local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true and getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable SP CartTestArea required')
require 'SaucedCarts/ContextMenu'
require 'ISUI/ISContextMenu'
require 'TimedActions/ISTimedActionQueue'
require 'TimedActions/WalkToTimedActionF'
local area,p=assert(CartTestArea),assert(getPlayer())
assert(area.ready and area.setObstacles and CartLabSelectScenes and cartLabDrive and cartLabGait and cartLabPoseHeading,'CartLab/obstacles required')
assert(not p:isTimedActionInstant(),'Native durations required')
assert(type(config.videoRoot)=='string' and config.videoRoot:sub(1,1)=='/' and type(config.ffmpeg)=='string' and config.ffmpeg:sub(1,1)=='/','Absolute video paths required')
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
local cases={{name='container-equip'},{name='wrong-side'},{name='wall-detour'},
 {name='precise-blocked'},{name='approach-cancel'},{name='approach-target-loss'},{name='approach-tail-success'}}
cases=CartLabSelectScenes(cases)
local index,since,sampled,mode=0,0,0,'prepare'
local item,bag,cargoID,cargoWeight,approach,tail,stance,queuedAt,terminalAt,changed,calibration,calibrationAt
local wallX,wallY=math.floor(area.x),math.floor(area.y)
local cartX,cartY=area.x,area.y
local tailX,tailY,startX,startY,removed=nil,nil,0,0,false
local function queue() return ISTimedActionQueue.getTimedActionQueue(p).queue end
local function empty() return #queue()==0 and p:getCharacterActions():isEmpty() and not p:hasPath() end
local function encode(row)
 local out={}
 for key,value in pairs(row) do
  if type(value)=='string' then value='"'..value:gsub('[%z\1-\31\\"]',function(c) return string.format('\\u%04x',string.byte(c)) end)..'"'
  elseif type(value)=='number' then assert(value==value and math.abs(value)<math.huge,'Nonfinite approach evidence');value=tostring(value)
  else assert(type(value)=='boolean','Invalid approach evidence');value=tostring(value) end
  out[#out+1]='"'..key..'":'..value
 end
 return '{'..table.concat(out,',')..'}'
end
local function relocate(x,y)
 assert(empty(),'Cannot relocate during native action')
 p:setX(x);p:setY(y);p:setZ(area.z);p:setNextX(x);p:setNextY(y);p:setLastX(x);p:setLastY(y)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow();cartLabPoseHeading(math.pi)
end
-- Use the same native movement primitive and timed-action update phase as the precise
-- arrival hook. Keyboard walking stops earlier because its predictive collision differs.
local WallCalibration=ISBaseTimedAction:derive('CartApproachWallCalibration')
function WallCalibration:isValid() return self.character==p and not p:getVehicle() end
function WallCalibration:update()
 local now,x,y=getTimestampMs(),p:getX(),p:getY()
 local rows=self.rows;local previous=rows[#rows]
 if previous and math.abs(x-previous.x)<=.001 and math.abs(y-previous.y)<=.001 then
  self.blocked=self.blocked+1;self.blockedAt=self.blockedAt or previous.wall
 else self.blocked=0;self.blockedAt=nil end
 local done=self.blocked>=45 and now-self.blockedAt>=500 and self.startX-x>=.2
 rows[#rows+1]={wall=now,x=x,y=y,dx=done and 0 or -.005,dy=0}
 if done then self.done=true;self:forceStop();return end
 self.character:moveUnmodded(-.005,0)
end
function WallCalibration:new()
 local o=ISBaseTimedAction.new(self,p)
 o.stopOnWalk=false;o.stopOnRun=false;o.maxTime=-1;o.rows={};o.blocked=0;o.startX=p:getX()
 return o
end
local function removeWorld(value)
 local world=value and value:getWorldItem()
 if world then local sq=assert(world:getSquare());sq:transmitRemoveItemFromSquare(world);sq:removeWorldObject(world);value:setWorldItem(nil) end
end
local function ground(x,y)
 cartX,cartY=x,y
 removeWorld(item)
 local container=item:getContainer();if container then container:Remove(item) end
 local sq=assert(getCell():getGridSquare(math.floor(x),math.floor(y),area.z))
 sq:AddWorldInventoryItem(item,x-math.floor(x),y-math.floor(y),0,true);item:setWorldZRotation(135)
 assert(SaucedCarts.markDropPersistent(item));SaucedCarts.updateCartVisual(item,p,true)
 stance=assert(toolkitWoodCartStance(p,assert(item:getWorldItem())),'Missing wooden handle stance')
end
local function snapshot(now)
 local contents=item:getInventory():getItems()
 assert(contents:size()==1 and contents:get(0):getID()==cargoID and contents:get(0):getFullType()=='Base.Log'
  and math.abs(contents:get(0):getActualWeight()-cargoWeight)<.001,'Exact cargo changed')
 local inv,worlds=0,0
 local items=p:getInventory():getItems();for i=0,items:size()-1 do if items:get(i):getID()==item:getID() then assert(items:get(i)==item);inv=inv+1 end end
 for x=wallX-8,wallX+8 do for y=wallY-8,wallY+8 do
  local sq=assert(getCell():getGridSquare(x,y,area.z));local values=sq:getWorldObjects()
  for i=0,values:size()-1 do local value=values:get(i):getItem();if value and value:getID()==item:getID() then assert(value==item);worlds=worlds+1 end end
 end end
 local nested=bag and item:getContainer()==bag:getInventory() and 1 or 0
 assert(inv+worlds+nested+(removed and 1 or 0)==1,'Cart ownership duplicated/lost')
 local a,b=p:getPrimaryHandItem(),p:getSecondaryHandItem();local status=toolkitWoodCartStatus(p)
 local current=queue()[1]
 local row={case=cases[index].name,start=since,wall=now,elapsed=now-since,id=item:getID(),cargoID=cargoID,cargoWeight=cargoWeight,
  inventoryCount=inv,worldCount=worlds,containerCount=nested,removed=removed,primaryID=a and a:getID() or -1,secondaryID=b and b:getID() or -1,
  x=p:getX(),y=p:getY(),z=p:getZ(),startX=startX,startY=startY,goalX=stance and stance.x or startX,goalY=stance and stance.y or startY,
  tailX=tailX or startX,tailY=tailY or startY,wallX=wallX,wallY=wallY,cartX=cartX,cartY=cartY,
  luaActions=#queue(),nativeActions=p:getCharacterActions():size(),hasPath=p:hasPath(),actionType=current and current.Type or '',
  approachResult=approach and approach.result==BehaviorResult.Failed and 'Failed' or approach and approach.result==BehaviorResult.Succeeded and 'Succeeded' or '',
  tailResult=tail and tail.result==BehaviorResult.Succeeded and 'Succeeded' or '',
  active=status.active==true,recovering=status.recovering==true,rendered=status.rendered==true,
  ToolkitWoodCartAction=p:getVariableBoolean('ToolkitWoodCartAction'),route=bag and 'inventory-menu' or 'world-menu'}
 return row
end
local function emit(event,now)
 local row=snapshot(now);row.event=event;print('[CART_APPROACH_EVENT] '..encode(row));return row
end
local function push()
 local function find(context)
  for _,option in ipairs(context.options) do
   if option.name==getText('UI_SaucedCarts_PushCart') or option.name=='Push Cart' then return option end
   if option.subOption then local found=find(context:getSubMenu(option.subOption));if found then return found end end
  end
 end
 local context=ISContextMenu.get(p:getPlayerNum(),50,50)
 if bag then triggerEvent('OnFillInventoryObjectContextMenu',p:getPlayerNum(),context,{item})
 else triggerEvent('OnFillWorldObjectContextMenu',p:getPlayerNum(),context,{assert(item:getWorldItem())},false) end
 local option=assert(find(context),'Public Push Cart option missing');assert(option.onSelect and not option.notAvailable,'Public Push Cart unavailable')
 context:hideAndChildren()
 option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,option.param6,option.param7,option.param8,option.param9,option.param10)
 approach=assert(queue()[1],'Public menu queued nothing')
 assert(approach.Type==(bag and 'ISCartEquipAction' or 'ISWalkToTimedActionF'),'Unexpected public pickup route')
 if not bag then assert(approach.toolkitWoodCartItem==item,'Approach lost exact target') end
end
local function cleanup()
 assert(empty(),'Cleanup requires native terminal state')
 cartLabDrive(0);cartLabGait(0);p:removeFromHands(item);SaucedCarts.clearCartPose(p)
 removeWorld(item);local c=item and item:getContainer();if c then c:Remove(item) end
 if bag then removeWorld(bag);bag=nil end
 item=nil;area.clearObstacles(p);area.check(p)
end
local function ready(now)
 startX,startY=p:getX(),p:getY();mode='settle';since=now+1200
end
local function prepare()
 assert(empty(),'Previous approach left native work');area.clearObstacles(p);area.check(p)
 cartLabDrive(0);cartLabGait(0);p:getStats():reset(CharacterStat.ENDURANCE)
 local held=p:getPrimaryHandItem();if held then p:removeFromHands(held);SaucedCarts.clearCartPose(p);p:getInventory():Remove(held) end
 item=assert(instanceItem('SaucedWheelbarrow.WheelbarrowWood'));local child=assert(item:getInventory():AddItem('Base.Log'))
 child:setActualWeight(1);child:setCustomWeight(true);cargoID,cargoWeight=child:getID(),child:getActualWeight()
 bag=nil;approach=nil;tail=nil;terminalAt=nil;queuedAt=nil;changed=false;removed=false;sampled=0;stance=nil;tailX=nil;tailY=nil;calibration=nil
 local name=cases[index].name
 relocate(wallX+2.5,wallY+.5)
 if name=='container-equip' then
  bag=assert(instanceItem('Base.Bag_DuffelBagTINT'));bag:getInventory():AddItem(item)
  p:getCurrentSquare():AddWorldInventoryItem(bag,.6,.6,0,true)
 elseif name=='precise-blocked' then
  local walls={};for y=wallY-3,wallY+3 do walls[#walls+1]={x=wallX,y=y,axis='W'} end
  area.setObstacles(p,walls);relocate(wallX+1,wallY+.5)
  calibrationAt=getTimestampMs();calibration=WallCalibration:new();ISTimedActionQueue.add(calibration);mode='calibrate';return
 else
  if name=='wall-detour' then
   local walls={};for y=wallY-1,wallY+1 do walls[#walls+1]={x=wallX+1,y=y,axis='W'} end
   area.setObstacles(p,walls)
  end
  ground(wallX+2.5,wallY+.5)
  if name=='wrong-side' then
   local world=item:getWorldItem();relocate(2*world:getWorldPosX()-stance.x,2*world:getWorldPosY()-stance.y)
  elseif name=='wall-detour' then
   -- Fix the handles relative to the wall; the cart's native authored offset is not the path goal.
   ground(cartX+wallX+2.5-stance.x,cartY+wallY+.5-stance.y)
   relocate(wallX-1,wallY+.5)
  else relocate(stance.x-3,stance.y) end
 end
 ready(getTimestampMs())
end
local function nextCase()
 index=index+1
 if index>#cases then
  print('[CART_APPROACH] CLEANUP_COMPLETE');print('[WOOD_BANK] ALL_COMPLETE cases='..#cases)
  cartLabDrive(-1);Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil;return
 end
 prepare()
end
local function tick()
 local now=getTimestampMs();local name=cases[index].name
 if mode=='calibrate' then
  assert(now-calibrationAt<7000,'Native bare wall calibration timed out')
  if not calibration.done then return end
  if not empty() then return end
  assert(p:getX()>wallX and p:getX()<wallX+.5,'Bare actor did not reach native wall')
  mode='calibrate-stop';calibrationAt=now;return
 elseif mode=='calibrate-stop' then
  assert(now-calibrationAt<2000,'Wall calibration did not settle')
  if p:isPlayerMoving() or now-calibrationAt<300 then return end
  local last=calibration.rows[#calibration.rows];local x,y=p:getX(),p:getY()
  assert(math.abs(x-last.x)<.002 and math.abs(y-last.y)<.002,'Actor drifted after physical wall calibration')
  ground(wallX+2,wallY+.5)
  ground(item:getWorldItem():getWorldPosX()+x-.03-stance.x,item:getWorldItem():getWorldPosY()+y-stance.y)
  assert(math.abs(stance.x-(x-.03))<.002 and math.abs(stance.y-y)<.002,'Blocked stance calibration failed')
  ready(now);return
 elseif mode=='settle' then
  if now<since then return end
  assert(toolkitVideoStart(config.videoRoot..'/'..name..'-0',config.ffmpeg),'Video start rejected')
  since=getTimestampMs();mode='record';print('[WOOD_BANK] CASE '..name..' attempt=0 wall='..since)
  if calibration then
   for _,row in ipairs(calibration.rows) do
    row.case=name;row.start=since;print('[CART_APPROACH_CALIBRATION] '..encode(row))
   end
  end
  emit('prepared',since);return
 end
 local video=toolkitVideoStatus();assert(video.state~='failed','Approach video failed: '..tostring(video.error))
 assert(now-since<23000,'Approach/video deadline')
 if mode=='finish' then
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE '..name..' wall='..since..' file='..video.file..' frames='..video.frames..' seconds='..video.seconds)
   cleanup();nextCase()
  end
  return
 end
 area.checkPosition(p,bag or item:getWorldItem() and item or nil)
 local row=snapshot(now)
 if now-sampled>=25 then sampled=now;print('[CART_APPROACH_SAMPLE] '..encode(row)) end
 if not queuedAt and now-since>=700 then
  push();queuedAt=now
  if name=='approach-cancel' or name=='approach-target-loss' or name=='approach-tail-success' then
   tailX,tailY=startX,startY+1
   tail=ISWalkToTimedActionF:new(p,Vector3f.new(tailX,tailY,area.z));ISTimedActionQueue.add(tail)
  end
  emit('queued',now)
 elseif queuedAt and not terminalAt then
  assert(now-queuedAt<14000,'Native approach did not terminate')
  if not changed and (name=='approach-cancel' or name=='approach-target-loss') and approach:isStarted() and p:hasPath() and now-queuedAt>=250 then
   assert(queue()[1]==approach and tail and not tail:isStarted(),'Interruption missed approach window')
   changed=true;emit(name=='approach-cancel' and 'cancelRequested' or 'targetRemoved',now)
   if name=='approach-cancel' then CancelAction(p:getPlayerNum())
   else removeWorld(item);removed=true end
  end
  if empty() then
   local success=name=='container-equip' or name=='wrong-side' or name=='wall-detour' or name=='approach-tail-success'
   assert(not (name=='approach-cancel' or name=='approach-target-loss') or changed,'Interruption never occurred')
   local state=snapshot(now)
   if success then assert(state.inventoryCount==1 and state.worldCount==0 and state.primaryID==item:getID() and state.secondaryID==item:getID(),'Pickup failed exact ownership')
   else assert(state.inventoryCount==0 and state.primaryID==-1 and state.secondaryID==-1,'Failed/cancelled approach equipped cart') end
   if name=='precise-blocked' then assert(approach.result==BehaviorResult.Failed,'Native collision did not reject final alignment') end
   if tail and name~='approach-cancel' then assert(tail.result==BehaviorResult.Succeeded,'Independent tail did not complete') end
   if name=='approach-cancel' then assert(not tail:isStarted() and not tail.result,'Native full-queue cancellation consumed tail') end
   terminalAt=now;emit('terminal',now)
  end
 elseif terminalAt and now-terminalAt>=1000 then
  local state=snapshot(now)
  assert(empty() and not state.active and not state.recovering and not state.rendered and not state.ToolkitWoodCartAction,'Approach leaked presentation/queue')
  emit('settled',now);assert(toolkitVideoStop(),'Video stop rejected');mode='finish'
 end
end
WoodPrototypeTick=function()
 local ok,why=pcall(tick)
 if not ok then
  cartLabDrive(-1);cartLabGait(0);ISTimedActionQueue.clear(p);toolkitVideoStop()
  Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil;print('[WOOD_BANK] FAIL '..tostring(why))
 end
end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
print('[WOOD_BANK] RUN_STARTED');nextCase();Events.OnTick.Add(WoodPrototypeTick)
