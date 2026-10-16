local config=require 'QueueTestSelection'
assert(config.disposable==true,'Cart MP requires fresh owned disposable profiles')
assert(type(config.ffmpeg)=='string' and config.ffmpeg:match('^/'),'Absolute config.ffmpeg required')
assert(type(config.videoRoot)=='table','Per-role config.videoRoot required')
require 'SaucedCarts/Core'
require 'SaucedCarts/CartVisuals'
local J=require 'CartMPJSON'
local option=assert(PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'));option:setValue(true)
local r=assert(getFileReader('smoke-user.txt',false));local user=r:readLine();r:close()
local videoDirectory=assert(config.videoRoot[user],'Missing role videoRoot')
assert(type(videoDirectory)=='string' and videoDirectory:match('^/'),'Absolute role video directory required')
local entered,connecting,advanced,started,setup,epoch,done=false,false,false,false,nil,nil,false
local readyAt,lastReady,lastSample,lastEquip,video,stage=0,0,0,0,nil,-1
local function emit(e) e.suite='cart_motion_mp';e.kind='mp';e.mode=config.mode;e.actor=user;J.emit(e) end
local function fail(e) cartLabDrive(0);print('[QUEUE_TEST] FAIL CART_MP '..tostring(e));emit({event='error',reason=tostring(e)});emit({event='complete',failed=1});done=true end
Events.OnMainMenuEnter.Add(function()
 entered=true;if connecting or isClient() then return end;connecting=true
 ConnectToServer.instance:connect(MainScreen.instance,'Cart animation MP example',user,'smoke-local-only','127.0.0.1','',tostring(config.port),'',false,true,1)
end)
Events.OnPreUIDraw.Add(function()
 if (not connecting and not isClient()) or advanced or isIngameState() then return end
 if not MainScreen.instance or not MainScreen.instance.charCreationProfession or not MapSpawnSelect.instance then return end
 if MainScreen.instance.charCreationProfession:getIsVisible() or MapSpawnSelect.instance:getIsVisible() then
  advanced=true;MapSpawnSelect.instance:useDefaultSpawnRegion();MapSpawnSelect.instance:setVisible(false)
  MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'});MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
 end
end)
Events.OnConnectFailed.Add(function(a,b) fail('connect '..tostring(a)..' '..tostring(b)) end)
Events.OnServerCommand.Add(function(module,command,args)
 if module~='CartMP' then return end
 if command=='Setup' then setup=args;print('[CART_MP] SETUP '..J.encode(args))
 elseif command=='Start' then epoch=args.epoch;print('[CART_MP] START epoch='..epoch)
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
local prepared,armed,stopped=false,false,false
local steps={{0,0,0,'idle'},{2000,2,0,'walk'},{5000,1,0,'turn'},{8000,0,0,'stop'},{10000,4,2,'reverse'},{12000,0,0,'stop-back'}}
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,e=pcall(function()
  local now=getTimestampMs();local p=getPlayer()
  if now-readyAt>240000 and not epoch then error('MP setup deadline') end
  if not setup then if now-lastReady>1000 then lastReady=now;sendClientCommand('CartMP','Ready',{}) end;return end
  if not prepared then
   position(p,setup.x,setup.y,setup.z)
   if user=='client1' then
    local cart=p:getInventory():getItemById(setup.cartId);if not cart then return end
    p:setPrimaryHandItem(cart);p:setSecondaryHandItem(cart);SaucedCarts.applyCartPose(p);p:updateHandEquips();SaucedCarts.updateCartVisual(cart,p,true)
    cartLabPoseHeading(math.pi*.75);p:setPerkLevelDebug(Perks.Sprinting,10);p:getXp():setXPToLevel(Perks.Sprinting,10)
   else cartLabPoseHeading(math.pi*.75) end
   getCore():setAutoZoom(0,false);if user=='client1' then for i=1,8 do getCore():doZoomScroll(0,-1) end end
   prepared=true;print('[CART_MP] PREPARED '..user)
  end
  local online=getOnlinePlayers();local owner
  for i=0,online:size()-1 do local v=online:get(i);if v:getUsername()=='client1' then owner=v end end
  if user=='client1' and not epoch and now-lastEquip>1000 then lastEquip=now;p:updateHandEquips() end
  if not epoch and now-lastSample>500 then lastSample=now;for i=0,online:size()-1 do print('[CART_MP_STATE] '..cartMPState(online:get(i))) end end
  if not armed and owner and owner:getPrimaryHandItem() and owner:getSecondaryHandItem()==owner:getPrimaryHandItem() then
   sendClientCommand('CartMP','Armed',{});armed=true;print('[CART_MP] ARMED '..user)
  end
  if user=='client2' and owner then cartMPCamera(owner) end
  if not epoch then return end
  local elapsed=now-epoch
  if not video and elapsed>=-2000 then
   assert(toolkitVideoStart(videoDirectory,config.ffmpeg));video=true
   print('[CART_MP] VIDEO '..tostring(toolkitVideoStatus().file))
  end
  cartMPHideUI()
  if elapsed<0 then return end
  local nextStage=1;for i,s in ipairs(steps) do if elapsed>=s[1] then nextStage=i end end
  if nextStage~=stage then stage=nextStage;if user=='client1' then cartLabGait(steps[stage][3]);cartLabDrive(steps[stage][2]) end;print('[CART_MP] PHASE '..steps[stage][4]..' wall='..now..' elapsed='..elapsed) end
  if now-lastSample>=100 then
   lastSample=now
   for i=0,online:size()-1 do print('[CART_MP_STATE] '..cartMPState(online:get(i))) end
  end
  if elapsed>=15000 then
   cartLabDrive(0);cartLabGait(0)
   if not stopped then assert(toolkitVideoStop(),'video stop failed');stopped=true;getCore():TakeFullScreenshot('cart-mp-end.png') end
   local status=toolkitVideoStatus();assert(status.state~='failed',status.error)
   if status.state~='completed' then assert(elapsed<25000,'encoder deadline');return end
   print('[CART_MP] VIDEO_FINAL '..J.encode({file=status.file,frames=status.frames,captured=status.captured,dropped=status.dropped,seconds=status.seconds}))
   emit({event='case',id='owner_observer_motion',status='captured'})
   emit({event='complete',expected=1,performed=1,skipped=0,failed=0});done=true
  end
 end)
 if not ok then fail(e) end
end)
