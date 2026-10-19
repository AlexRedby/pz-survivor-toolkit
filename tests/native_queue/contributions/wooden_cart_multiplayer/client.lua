local config=require 'QueueTestSelection'
assert(config.disposable==true,'Cart MP requires fresh owned disposable profiles')
assert(type(config.ffmpeg)=='string' and config.ffmpeg:match('^/'),'Absolute config.ffmpeg required')
assert(type(config.videoRoot)=='table','Per-role config.videoRoot required')
require 'SaucedCarts/Core'
require 'SaucedCarts/CartVisuals'
local J=require 'CartMPJSON'
local variants={['shopping-cart']='SaucedCarts.ShoppingCart',['wooden-wheelbarrow']='SaucedWheelbarrow.WheelbarrowWood',['metal-wheelbarrow']='SaucedWheelbarrow.WheelbarrowMetal'}
local variant=config.options and config.options.cart_variant or 'wooden-wheelbarrow'
local cartType=assert(variants[variant],'Unknown MP cart_variant')
assert(not (config.options and config.options.cart_actions) or variant=='wooden-wheelbarrow','cart_actions requires wooden-wheelbarrow')
local actions=config.options and config.options.cart_actions and require 'CartMPActions' or nil
local option=assert(PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'));option:setValue(true)
local r=assert(getFileReader('smoke-user.txt',false));local user=r:readLine();r:close()
local videoDirectory=assert(config.videoRoot[user],'Missing role videoRoot')
assert(type(videoDirectory)=='string' and videoDirectory:match('^/'),'Absolute role video directory required')
local started,setup,epoch,done=false,nil,nil,false
local readyAt,lastReady,lastSample,lastEquip,video,stage,lastArm,skillSince=0,0,0,0,nil,-1,0,nil
local function emit(e) e.suite='cart_motion_mp';e.kind='mp';e.mode=config.mode;e.actor=user;J.emit(e) end
local function fail(e) cartLabDrive(0);cartLabGait(0);if video then toolkitVideoStop() end;print('[QUEUE_TEST] FAIL CART_MP '..tostring(e));emit({event='error',reason=tostring(e)});emit({event='complete',failed=1});done=true end
Events.OnConnectFailed.Add(function(a,b) fail('connect '..tostring(a)..' '..tostring(b)) end)
Events.OnServerCommand.Add(function(module,command,args)
 if module~='CartMP' then return end
 if command=='Setup' then setup=args;print('[CART_MP] SETUP '..J.encode(args))
 elseif command=='Start' then epoch=args.epoch;print('[CART_MP] START epoch='..epoch)
 elseif actions and command:sub(1,6)=='Action' then local ok,e=pcall(actions.command,command,args);if not ok then fail(e) end
 end
end)
Events.OnGameStart.Add(function()
 started=true;readyAt=getTimestampMs();cartLabDrive(0);cartLabGait(0)
 getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false)
 getPlayer():setGodMod(true);getPlayer():setGhostMode(false);getPlayer():setAutoDrink(false)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
 emit({event='setup',cases=config.cases,expected=#config.cases})
 print('[CART_MP] CONNECTED '..user)
end)
local function position(p,x,y,z)
 p:teleportTo(math.floor(x),math.floor(y),z);p:setX(x);p:setY(y);p:setZ(z);p:setNextX(x);p:setNextY(y);p:setLastX(x);p:setLastY(y);p:setLastZ(z)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow()
end
local prepared,armed,stopped,finishedAt,actionsFinished,padSince,padReady=false,false,false,nil,false,nil,false
local extended=config.options and config.options.cart_fast_motion
local duration=extended and 26000 or 15000
local steps={{0,0,0,'idle'},{2000,1,0,'walk'},{5000,8,0,'turn'},{8000,0,0,'stop'},{10000,4,2,'reverse'},{12000,0,0,'stop-back'}}
if extended then
 steps[#steps+1]={15000,1,1,'run'};steps[#steps+1]={16500,5,2,'sprint-turn'}
 steps[#steps+1]={18500,0,0,'fast-stop'}
end
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,e=pcall(function()
  local now=getTimestampMs();local p=getPlayer()
  if now-readyAt>240000 and not epoch then error('MP setup deadline') end
  if not setup then if now-lastReady>1000 then lastReady=now;sendClientCommand('CartMP','Ready',{}) end;return end
  if not prepared then
   assert(setup.variant==variant and setup.cartType==cartType,'Server cart variant differs from selection')
   if extended then
    assert(setup.bankVersion==3 and setup.elevated==true and setup.z==7 and setup.size==31 and setup.floorSprite=='carpentry_02_57','Native elevated pad descriptor missing')
    if not padSince then padSince=now end
    local count=0
    for x=setup.minX,setup.minX+setup.size-1 do for y=setup.minY,setup.minY+setup.size-1 do
     local sq=getCell():getGridSquare(x,y,setup.z);local floor=sq and sq:getFloor()
     if floor and floor:getSpriteName()==setup.floorSprite and sq:TreatAsSolidFloor() then count=count+1 end
    end end
    assert(now-padSince<30000,'Native elevated floor replication deadline')
    if count~=961 then return end
    if not padReady then
     print('[CART_MP] PAD_READY '..J.encode({bankVersion=3,floors=count,z=setup.z,minX=setup.minX,minY=setup.minY,size=setup.size,wall=now}))
     padReady=true
    end
   end
   position(p,setup.x,setup.y,setup.z)
   if user=='client1' then
    local cart=p:getInventory():getItemById(setup.cartId);if not cart then return end
    assert(cart:getFullType()==cartType,'Exact fixture cart type differs')
    p:setPrimaryHandItem(cart);p:setSecondaryHandItem(cart);SaucedCarts.applyCartPose(p);p:updateHandEquips();SaucedCarts.updateCartVisual(cart,p,true)
    cartLabPoseHeading(math.pi*.75)
   else cartLabPoseHeading(math.pi*.75) end
   local expectedZoom=user=='client2' and 1 or .25
   assert(cartMPZoom(user=='client2')==expectedZoom,'Native fixture zoom differs from role framing')
   prepared=true;print('[CART_MP] PREPARED '..user..' zoom='..getCore():getZoom(0)..' expectedZoom='..expectedZoom)
  end
  local online=getOnlinePlayers();local owner
  for i=0,online:size()-1 do local v=online:get(i);if v:getUsername()=='client1' then owner=v end end
  if user=='client1' and not epoch and now-lastEquip>1000 then lastEquip=now;p:updateHandEquips() end
  if not epoch and now-lastSample>500 then lastSample=now;for i=0,online:size()-1 do print('[CART_MP_STATE] '..cartMPState(online:get(i))) end end
  local skillReady=user~='client1' or p:getPerkLevel(Perks.Sprinting)==10
  if user=='client1' and not skillReady then
   if not skillSince then skillSince=now end
   assert(now-skillSince<10000,'Authoritative Sprinting snapshot deadline')
   if now-lastReady>1000 then lastReady=now;sendClientCommand('CartMP','Ready',{}) end
  else skillSince=nil end
  if skillReady and (not armed or not epoch and now-lastArm>1000) and owner and owner:getPrimaryHandItem() and owner:getPrimaryHandItem():getFullType()==cartType and owner:getSecondaryHandItem()==owner:getPrimaryHandItem() then
   sendClientCommand('CartMP','Armed',{sprintLevel=p:getPerkLevel(Perks.Sprinting),padFloors=padReady and 961 or 0,padVersion=setup.bankVersion});armed=true;lastArm=now
   print('[CART_MP] ARMED '..user..' sprintLevel='..p:getPerkLevel(Perks.Sprinting))
  end
  if user=='client2' and owner then
   if epoch and now>=epoch and (p:getX()-owner:getX())^2+(p:getY()-owner:getY())^2>25 then
    local moved=false
    for _,offset in ipairs({{2,3},{-2,-3},{3,2},{-3,-2}}) do
     local x,y,z=owner:getX()+offset[1],owner:getY()+offset[2],owner:getZ()
     local square=getCell():getGridSquare(math.floor(x),math.floor(y),z)
     if square and square:getFloor() and square:TreatAsSolidFloor() and square:isFree(false) and not square:isVehicleIntersecting() then
      position(p,x,y,z);moved=true;print('[CART_MP] OBSERVER_FOLLOW wall='..now);break
     end
    end
    assert(moved,'No safe observer camera position near owner')
   end
   cartMPCamera(owner)
  end
  if not epoch then return end
  local elapsed=now-epoch
  if not video and elapsed>=-2000 then
   assert(toolkitVideoStart(videoDirectory,config.ffmpeg));video=true
   print('[CART_MP] VIDEO '..tostring(toolkitVideoStatus().file))
  end
  if video and extended and user=='client1' then
   assert(setup.bankVersion==3 and setup.size==31 and setup.margin==2 and setup.vegetationFree==true,'Validated extended pad descriptor missing')
   assert(p:getX()>=setup.minX+setup.margin and p:getX()<=setup.minX+setup.size-setup.margin
    and p:getY()>=setup.minY+setup.margin and p:getY()<=setup.minY+setup.size-setup.margin and math.abs(p:getZ()-setup.z)<.25,
    'Owner/cart margin left validated pad interior')
  end
  cartMPHideUI()
  if elapsed<0 then return end
  local nextStage=1;for i,s in ipairs(steps) do if elapsed>=s[1] then nextStage=i end end
  if nextStage~=stage then
   stage=nextStage
   if user=='client1' then
    assert(p:getPerkLevel(Perks.Sprinting)==10,'Authoritative Sprinting level changed during motion')
    p:getStats():reset(CharacterStat.ENDURANCE)
    cartLabGait(steps[stage][3]);cartLabDrive(steps[stage][2])
   end
   print('[CART_MP] PHASE '..steps[stage][4]..' wall='..now..' elapsed='..elapsed..' zoom='..getCore():getZoom(0))
   print('[CART_MP_TRAFFIC] '..cartMPTraffic())
  end
  if now-lastSample>=100 then
   lastSample=now
   for i=0,online:size()-1 do print('[CART_MP_STATE] '..cartMPState(online:get(i))) end
   if actions and elapsed>=duration then actions.sample(owner,user) end
  end
  if elapsed>=duration then
   cartLabDrive(0);cartLabGait(0)
   if actions and not actionsFinished then
    assert(elapsed<duration+35000,'MP action bank deadline')
    if user=='client1' then actions.tick(p,setup,now) end
    if not actions.done(owner,now,user) then return end
    actionsFinished=true
   end
   if not finishedAt then finishedAt=now end
   if not stopped then assert(toolkitVideoStop(),'video stop failed');stopped=true;getCore():TakeFullScreenshot('cart-mp-end.png') end
   local status=toolkitVideoStatus();assert(status.state~='failed',status.error)
   if status.state~='completed' then assert(now-finishedAt<10000,'encoder deadline');return end
   print('[CART_MP] VIDEO_FINAL '..J.encode({file=status.file,frames=status.frames,captured=status.captured,dropped=status.dropped,seconds=status.seconds}))
   print('[CART_MP_TRAFFIC] '..cartMPTraffic())
   emit({event='case',id='owner_observer_motion',status='captured',cartActions=actions~=nil})
   emit({event='complete',expected=1,performed=1,skipped=0,failed=0});done=true
  end
 end)
 if not ok then fail(e) end
end)
