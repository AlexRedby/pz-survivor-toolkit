local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true and getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable SP CartTestArea required')
require 'TimedActions/ISTimedActionQueue'
local area,p=assert(CartTestArea),assert(getPlayer())
local cases={{name='native-e'}}
cases=CartLabSelectScenes(cases)
assert(#cases==1,'One native E case required')
assert(area.ready and cartLabKeyState and cartLabContextSeconds,'Native E fixture bridge required')
assert(not p:isTimedActionInstant(),'Native cart durations required')
local binding=assert(PZAPI.ModOptions:getOptions('SaucedCarts'):getOption('PushCart'))
assert(binding:getValue()==Keyboard.KEY_E and getCore():isKey(KeybindId.INTERACT,Keyboard.KEY_E),'Actual E/Interact bindings required')
assert(not p:isIgnoreContextKey(),'Initial native context must be enabled')
if WoodPrototypeTick then Events.OnTick.Remove(WoodPrototypeTick) end
cartLabDrive(0);cartLabGait(0);setGameSpeed(1)
local item=assert(p:getPrimaryHandItem(),'Bootstrap cart missing')
assert(item:getFullType()=='SaucedWheelbarrow.WheelbarrowWood' and p:getSecondaryHandItem()==item,'Exact wooden cart required')
local cargo=assert(item:getInventory():AddItem('Base.Log'));cargo:setActualWeight(1);cargo:setCustomWeight(true)
local id,cargoID=item:getID(),cargo:getID()
local x,y=math.floor(area.x),math.floor(area.y)
local walls={{x=x+1,y=y,axis='W',kind='door',open=false}}
for yy=y-4,y+4 do if yy~=y then walls[#walls+1]={x=x+1,y=yy,axis='W'} end end
area.setObstacles(p,walls)
local door
for object,owned in pairs(area.obstacles) do if owned.kind=='door' then door=object end end
assert(door and instanceof(door,'IsoDoor'),'Native test door missing')
local function queue() return ISTimedActionQueue.getTimedActionQueue(p).queue end
local function quiet()
 local status=toolkitWoodCartStatus(p)
 return #queue()==0 and p:getCharacterActions():isEmpty() and not p:hasPath() and not status.active and not status.recovering
end
local function placeActor()
 assert(quiet(),'Positioning while actions pending')
 p:setX(x+.5);p:setY(y+.5);p:setZ(area.z);p:setNextX(x+.5);p:setNextY(y+.5);p:setLastX(x+.5);p:setLastY(y+.5)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow();cartLabPoseHeading(0)
end
local function relocateCart(far)
 assert(quiet(),'Cart fixture placement while actions pending')
 local world=item:getWorldItem()
 if world then
  local square=world:getSquare();square:transmitRemoveItemFromSquare(world);square:removeWorldObject(world);item:setWorldItem(nil)
 end
 p:removeFromHands(item);SaucedCarts.clearCartPose(p)
 if p:getInventory():contains(item) then p:getInventory():Remove(item) end
 local square=assert(getCell():getGridSquare(x+(far and 8 or -1),y+(far and 0 or 1),area.z))
 square:AddWorldInventoryItem(item,.65,.5,0,true);item:setWorldZRotation(90)
 assert(item:getWorldItem(),'Fixture world cart missing')
end
local function doorState(open)
 assert(open==false and area.obstacles[door],'Only the owned closed-door fixture reset is allowed')
 -- A native E control changes the door without changing the fixture's closed
 -- edge map. Restore native state before the next input gesture.
 if door:isOpen() then door:ToggleDoor(p) end
 assert(not door:isOpen(),'Native fixture door reset refused')
 local owned=area.obstacles[door];owned.open=false;owned.sprite=door:getSpriteName()
 assert(door:getSquare()==getCell():getGridSquare(x+1,y,area.z) and door:isBlocked(),'Owned closed-door state differs')
end
local phases={
 {name='native-before',native=true,far=true,hold=150,ground=true},
 {name='pickup',hold=150,ground=false},
 {name='drop-long',hold=900,ground=true},
 {name='pickup-cancel',hold=150,ground=true,cancel=true},
 {name='pickup-repeat',hold=150,ground=false},
 {name='drop-repeat',hold=150,ground=true},
 {name='native-after',native=true,far=true,hold=150,ground=true},
}
local index,mode,since,phaseSince,videoStart=0,'setup',getTimestampMs(),0,0
local held,capturedSeen,nativeDownSeen,longSeen,cancelled,settled
local function encode(row)
 local fields={}
 for key,value in pairs(row) do
  assert(type(value)=='string' or type(value)=='boolean' or type(value)=='number','Invalid E receipt')
  fields[#fields+1]='"'..key..'":'..(type(value)=='string' and '"'..value..'"' or tostring(value))
 end
 return '{'..table.concat(fields,',')..'}'
end
local function ownership(ground)
 assert(item:getID()==id and item:getInventory():getItems():size()==1 and item:getInventory():getItems():get(0):getID()==cargoID
  and cargo:getFullType()=='Base.Log' and math.abs(cargo:getActualWeight()-1)<.001,'Exact cart/cargo changed')
 local inv=0;local contents=p:getInventory():getItems()
 for i=0,contents:size()-1 do if contents:get(i):getID()==id then inv=inv+1 end end
 local worlds=0
 for xx=x-3,x+10 do for yy=y-3,y+3 do
  local objects=assert(getCell():getGridSquare(xx,yy,area.z)):getWorldObjects()
  for i=0,objects:size()-1 do if objects:get(i):getItem():getID()==id then worlds=worlds+1 end end
 end end
 assert(inv==(ground and 0 or 1) and worlds==(ground and 1 or 0),'Exact cart ownership count mismatch')
 assert((p:getPrimaryHandItem()==item)==not ground and (p:getSecondaryHandItem()==item)==not ground,'Exact cart hand ownership mismatch')
 return inv,worlds
end
local function nextPhase(now)
 index=index+1
 if not phases[index] then
  assert(not p:isIgnoreContextKey(),'Native context remained blocked after all phases')
  assert(toolkitVideoStop(),'E regression video stop rejected');mode='finish';since=now;return
 end
 local phase=phases[index]
 assert(quiet() and not p:isIgnoreContextKey(),'Previous E phase did not drain')
 if phase.far then relocateCart(true) elseif index==2 then relocateCart(false) end
 placeActor();doorState(false)
 capturedSeen,nativeDownSeen,longSeen,cancelled,settled=false,false,false,false,nil
 phaseSince=now;mode='press';held=true
 print('[CART_NATIVE_E] BEGIN phase='..phase.name..' wall='..now)
 cartLabKeyState(Keyboard.KEY_E,true)
 if phase.native then assert(not p:isIgnoreContextKey(),'No-cart E unexpectedly captured')
 else assert(p:isIgnoreContextKey() and #queue()>0,'Accepted cart E did not capture native context') end
end
local function tick()
 local now=getTimestampMs()
 if mode=='setup' then
  if now-since<1000 then return end
  relocateCart(true);placeActor()
  assert(toolkitVideoStart(config.videoRoot..'/native-e-'..now,config.ffmpeg),'E regression video start rejected')
  videoStart=now;print('[WOOD_BANK] CASE native-e wall='..now);nextPhase(now);return
 end
 if mode=='finish' then
  local video=toolkitVideoStatus();assert(video.state~='failed','E regression video failed')
  assert(now-since<15000,'E video finish deadline')
  if video.state=='completed' then
   print('[WOOD_BANK] COMPLETE native-e wall='..videoStart..' file='..video.file..' frames='..video.frames..' seconds='..video.seconds)
   print('[WOOD_BANK] ALL_COMPLETE cases=1');Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil;cartLabDrive(-1)
  end
  return
 end
 local phase=phases[index]
 assert(now-phaseSince<15000,'E regression timeout '..phase.name)
 capturedSeen=capturedSeen or p:isIgnoreContextKey()
 nativeDownSeen=nativeDownSeen or p:isInteractButtonDown()
 longSeen=longSeen or held and cartLabContextSeconds()>=.5
 if not phase.native then assert(not door:isOpen(),'Cart E triggered the native door: '..phase.name) end
 local action=queue()[1]
 if phase.cancel and not cancelled and action and (action.Type=='ToolkitWoodCartPickup' or action.Type=='ISCartPickupAction')
  and action.action and action:isStarted() and action:getJobDelta()>=.25 then
  assert(action:getJobDelta()<.75,'Missed native cancellation interval')
  action.action:forceStop();cancelled=true
 end
 if held and now-phaseSince>=phase.hold then cartLabKeyState(Keyboard.KEY_E,false);held=false end
 if held or not quiet() or p:isIgnoreContextKey() then settled=nil;return end
 if phase.native and not door:isOpen() then return end
 if not settled then settled=now;return end
 if now-settled<200 then return end
 assert(nativeDownSeen,'Held E never reached native interact input')
 assert(phase.native or capturedSeen,'Accepted cart E was never captured')
 assert(phase.name~='drop-long' or longSeen,'Long E never crossed native 0.5 second threshold')
 assert(not phase.cancel or cancelled,'Cancellation was not executed')
 local inv,world=ownership(phase.ground)
 print('[CART_NATIVE_E] RECEIPT '..encode({phase=phase.name,id=id,cargoID=cargoID,cargoWeight=cargo:getActualWeight(),cargoType=cargo:getFullType(),key=Keyboard.KEY_E,doorOpen=door:isOpen(),
  inventoryCount=inv,worldCount=world,primaryID=p:getPrimaryHandItem() and p:getPrimaryHandItem():getID() or -1,
  secondaryID=p:getSecondaryHandItem() and p:getSecondaryHandItem():getID() or -1,ignoreRestored=not p:isIgnoreContextKey(),
  nativeDownSeen=nativeDownSeen,capturedSeen=capturedSeen,longSeen=longSeen,cancelled=cancelled,
  luaActions=#queue(),nativeActions=p:getCharacterActions():size(),hasPath=p:hasPath(),elapsed=now-phaseSince}))
 nextPhase(now)
end
WoodPrototypeTick=function()
 local ok,why=pcall(tick)
 if not ok then
  if held then pcall(function() cartLabKeyState(Keyboard.KEY_E,false) end) end
  toolkitVideoStop();cartLabDrive(-1);Events.OnTick.Remove(WoodPrototypeTick);WoodPrototypeTick=nil
  print('[CART_NATIVE_E] FAIL phase='..tostring(phases[index] and phases[index].name)..' '..tostring(why));print('[WOOD_BANK] FAIL '..tostring(why))
 end
end
print('[WOOD_BANK] RUN_STARTED');Events.OnTick.Add(WoodPrototypeTick)
