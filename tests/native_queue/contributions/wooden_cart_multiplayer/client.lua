local config=require 'QueueTestSelection'
assert(config.disposable==true,'Cart MP requires fresh owned disposable profiles')
assert(type(config.ffmpeg)=='string' and config.ffmpeg:match('^/'),'Absolute config.ffmpeg required')
assert(type(config.videoRoot)=='table','Per-role config.videoRoot required')
require 'SaucedCarts/Core'
require 'SaucedCarts/CartVisuals'
local J=require 'CartMPJSON'
local wallSide=config.options and config.options.cart_wall_exit
local wallBank=wallSide and require 'CartMPWall'
local wallInput=wallSide and require 'CartMPWallInput'
local wallCleanup,wallDone,wallDoneAt,wallReleased,heldDrive=nil,false,nil,{},0
local wallPositioned,wallCleanupSeen,lastTraffic=false,false,0
local variants={['shopping-cart']='SaucedCarts.ShoppingCart',['wooden-wheelbarrow']='SaucedWheelbarrow.WheelbarrowWood',['metal-wheelbarrow']='SaucedWheelbarrow.WheelbarrowMetal'}
local variant=config.options and config.options.cart_variant or 'wooden-wheelbarrow'
local cartType=assert(variants[variant],'Unknown MP cart_variant')
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
 elseif wallSide and command=='WallCleanup' then wallCleanup=args.wall
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
local extended=wallSide or config.options and config.options.cart_fast_motion
local duration=wallSide=='front' and 18000 or wallSide and 29000 or extended and 26000 or 15000
local steps={{0,0,0,'idle'},{2000,1,0,'walk'},{5000,8,0,'turn'},{8000,0,0,'stop'},{10000,4,2,'reverse'},{12000,0,0,'stop-back'}}
if extended and not wallSide then
 steps[#steps+1]={15000,1,1,'run'};steps[#steps+1]={16500,5,2,'sprint-turn'}
 steps[#steps+1]={18500,0,0,'fast-stop'}
end
if wallSide then steps=wallInput.steps(wallSide) end
local function wallSample(p,now,elapsed)
 local item=assert(p:getPrimaryHandItem(),'Wall cart missing');local inventory=p:getInventory():getItems();local count=0
 for i=0,inventory:size()-1 do if inventory:get(i):getID()==item:getID() then count=count+1 end end
 local contents=item:getInventory():getItems();assert(contents:size()==1,'Wall cargo missing/duplicated')
 local cargo=contents:get(0);local footprint=cartLabFootprint();local fields={}
 for key,value in footprint:gmatch('(%w+)=([^ ]+)') do fields[key]=value end
 local row={wall=now,elapsed=elapsed,stage=steps[stage][4],drive=heldDrive,gait=0,acceptedHeading=cartLabSteeringHeading(),
  id=item:getID(),primary=item:getID(),secondary=p:getSecondaryHandItem() and p:getSecondaryHandItem():getID() or -1,
  inventoryCount=count,worldID=item:getWorldItem() and item:getWorldItem():getItem():getID() or -1,
  cargoID=cargo:getID(),cargoWeight=cargo:getActualWeight(),queue=#ISTimedActionQueue.getTimedActionQueue(p).queue,
  actions=p:getCharacterActions():size(),path=p:hasPath(),front=tonumber(fields.front)}
 for _,key in ipairs({'blocked','recovering','clear'}) do
  assert(fields[key]=='true' or fields[key]=='false','Invalid native footprint '..key);row[key]=fields[key]=='true'
 end
 if wallSide=='front' then
  local brace=cartMPBrace(p,setup.cartId,setup.wallX,setup.y)
  assert(type(brace)=='string','Native brace diagnostics missing for exact fixture owner/cart')
  for key,value in brace:gmatch('(%w+)=([^ ]+)') do
   if key=='brace' then row.brace=tonumber(value)
   else assert(value=='true' or value=='false','Invalid native brace '..key);row[key]=value=='true' end
  end
 end
 assert(item:getContainer()==p:getInventory() and count==1 and row.secondary==row.id and row.worldID==-1,'Wall cart ownership changed')
 assert(row.queue==0 and row.actions==0 and not row.path,'Wall route enqueued an action/path')
 print('[CART_MP_WALL] INPUT '..J.encode(row))
end
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,e=pcall(function()
  local now=getTimestampMs();local p=getPlayer()
  if now-readyAt>240000 and not epoch then error('MP setup deadline') end
  if not setup then if now-lastReady>1000 then lastReady=now;sendClientCommand('CartMP','Ready',{}) end;return end
  if not prepared then
   assert(setup.variant==variant and setup.cartType==cartType,'Server cart variant differs from selection')
   if wallSide then
    if not padSince then padSince=now end
    local receipt=wallBank.receipt(setup)
    assert(now-padSince<30000,'Native wall/floor replication deadline')
    if not receipt.ready then return end
    if not padReady then
     local row={};for key,value in pairs(setup) do row[key]=value end
     row.floors=receipt.floors;row.walls=receipt.walls;row.wall=now
     print('[CART_MP] PAD_READY '..J.encode(row));padReady=true
    end
   elseif extended then
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
    cartLabPoseHeading(wallSide and setup.initialHeading or math.pi*.75)
   else cartLabPoseHeading(wallSide and setup.initialHeading or math.pi*.75) end
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
   sendClientCommand('CartMP','Armed',{sprintLevel=p:getPerkLevel(Perks.Sprinting),padFloors=padReady and setup.size*setup.size or 0,padWalls=wallSide and 49 or 0,padVersion=setup.bankVersion});armed=true;lastArm=now
   print('[CART_MP] ARMED '..user..' sprintLevel='..p:getPerkLevel(Perks.Sprinting))
  end
  if user=='client2' and owner then
   if epoch and now>=epoch and (p:getX()-owner:getX())^2+(p:getY()-owner:getY())^2>25 then
    local moved=false
    for _,offset in ipairs(wallSide and {{3,3},{3,-3},{4,0}} or {{2,3},{-2,-3},{3,2},{-3,-2}}) do
     local x,y,z=owner:getX()+offset[1],owner:getY()+offset[2],owner:getZ()
     local square=getCell():getGridSquare(math.floor(x),math.floor(y),z)
     if (not wallSide or x>setup.wallX+1.5 and x>=setup.minX+setup.margin and x<=setup.minX+setup.size-setup.margin and y>=setup.minY+setup.margin and y<=setup.minY+setup.size-setup.margin) and square and square:getFloor() and square:TreatAsSolidFloor() and square:isFree(false) and not square:isVehicleIntersecting() then
      position(p,x,y,z);moved=true;print('[CART_MP] OBSERVER_FOLLOW wall='..now);break
     end
    end
    assert(moved,'No safe observer camera position near owner')
   end
   cartMPCamera(owner)
  end
  if not epoch then return end
  local elapsed=now-epoch
  if wallSide and not wallPositioned and elapsed>=-8000 then
   assert(elapsed<0,'Wall pose setup missed pre-epoch window')
   position(p,setup.x,setup.y,setup.z);cartLabPoseHeading(setup.initialHeading)
   wallPositioned=true;print('[CART_MP_WALL] POSE_READY '..J.encode({actor=user,wall=now,x=p:getX(),y=p:getY(),heading=cartLabSteeringHeading()}))
  end
  if not video and elapsed>=-2000 then
   assert(toolkitVideoStart(videoDirectory,config.ffmpeg));video=true
   print('[CART_MP] VIDEO '..tostring(toolkitVideoStatus().file))
  end
  if video and extended and user=='client1' then
   assert(setup.bankVersion==(wallSide and 4 or 3) and setup.size==(wallSide and 63 or 31) and setup.margin==2 and setup.vegetationFree==true,'Validated extended pad descriptor missing')
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
    cartLabGait(steps[stage][3]);if not wallSide then cartLabDrive(steps[stage][2]) end
   end
   print('[CART_MP] PHASE '..steps[stage][4]..' wall='..now..' elapsed='..elapsed..' zoom='..getCore():getZoom(0))
   if not wallSide then print('[CART_MP_TRAFFIC] '..cartMPTraffic()) end
  end
  if wallSide and user=='client1' then
   local drive=wallInput.drive(wallSide,steps[stage],wallReleased,cartLabSteeringHeading())
   if drive~=heldDrive then heldDrive=drive;cartLabDrive(drive) end
  end
  if wallSide and now-lastTraffic>=1000 then lastTraffic=now;print('[CART_MP_TRAFFIC] '..cartMPTraffic()) end
  if now-lastSample>=100 then
   lastSample=now
   for i=0,online:size()-1 do print('[CART_MP_STATE] '..cartMPState(online:get(i))) end
   if wallSide and user=='client1' then wallSample(p,now,elapsed) end
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
   if wallSide then
    if not wallDone then wallDone=true;wallDoneAt=now;sendClientCommand('CartMP','WallDone',{}) end
    if not wallCleanupSeen then
     assert(now-wallDoneAt<10000,'Native wall cleanup acknowledgement deadline')
     if wallCleanup and wallBank.cleanupReady(setup) then
      wallCleanupSeen=true;print('[CART_MP_WALL] CLEANUP_READY '..J.encode({wall=now,walls=0}))
     end
    end
   end
   local status=toolkitVideoStatus();assert(status.state~='failed',status.error)
   if status.state~='completed' then assert(now-finishedAt<10000,'encoder deadline');return end
   if wallSide and not wallCleanupSeen then return end
   print('[CART_MP] VIDEO_FINAL '..J.encode({file=status.file,frames=status.frames,captured=status.captured,dropped=status.dropped,seconds=status.seconds}))
   if not wallSide then print('[CART_MP_TRAFFIC] '..cartMPTraffic()) end
   emit({event='case',id='owner_observer_motion',status='captured',cartActions=actions~=nil})
   emit({event='complete',expected=1,performed=1,skipped=0,failed=0});done=true
  end
 end)
 if not ok then fail(e) end
end)
