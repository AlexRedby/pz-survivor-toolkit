local config=require 'QueueTestSelection'
assert(config.disposable==true,'Cart MP requires fresh owned disposable profiles')
local J=require 'CartMPJSON'
local wallSide=config.options and config.options.cart_wall_exit
local wallBank=wallSide and require 'CartMPWall'
local wallDone,wallCleaned,originSince={},false,nil
local players,ready,armed={}, {}, {}
local epoch,last,origin,lastTraffic= nil,0,nil,0
local actions=config.options and config.options.cart_actions
local hotkey=config.options and config.options.cart_hotkey_setdown==true
assert(not hotkey or actions,'cart_hotkey_setdown requires cart_actions')
local variants={['shopping-cart']='SaucedCarts.ShoppingCart',['wooden-wheelbarrow']='SaucedWheelbarrow.WheelbarrowWood',['metal-wheelbarrow']='SaucedWheelbarrow.WheelbarrowMetal'}
local variant=config.options and config.options.cart_variant or 'wooden-wheelbarrow'
local cartType=assert(variants[variant],'Unknown MP cart_variant')
assert(not actions or (variant=='wooden-wheelbarrow' or variant=='metal-wheelbarrow'),'cart_actions requires a calibrated wheelbarrow')
local actionPhases={'drop-complete','pickup-complete','drop-cancel','drop-repeat','pickup-cancel','pickup-repeat'}
local actionGround={true,false,false,true,true,false}
local cartSession,actionIndex,pendingAction,actionStarted,actionsDone=nil,1,nil,false,false
local function broadcast(command,args) for _,p in pairs(players) do sendServerCommand(p,'CartMP',command,args) end end
local function samePose(actual,expected)
 if type(actual)~='table' or type(expected)~='table' then return false end
 for _,key in ipairs({'x','y','z','rotation'}) do
  if type(actual[key])~='number' or type(expected[key])~='number' or actual[key]~=actual[key] or expected[key]~=expected[key] then return false end
 end
 return math.abs(actual.x-expected.x)<=.002 and math.abs(actual.y-expected.y)<=.002 and math.abs(actual.z-expected.z)<=.002
  and math.abs((actual.rotation-expected.rotation+180)%360-180)<=.01
end
local function actionState(p)
 local found,count,worldCount=nil,0,0
 local contents=p:getInventory():getItems()
 for i=0,contents:size()-1 do local item=contents:get(i);if item:getID()==cartSession.id then found=item;count=count+1 end end
 local seen={}
 for _,point in ipairs({cartSession,{x=p:getX(),y=p:getY(),z=p:getZ()}}) do
  for x=math.floor(point.x)-4,math.floor(point.x)+4 do for y=math.floor(point.y)-4,math.floor(point.y)+4 do
   local square=getCell():getGridSquare(x,y,point.z)
   if square and not seen[square] then seen[square]=true;local objects=square:getWorldObjects()
    for i=0,objects:size()-1 do local item=objects:get(i):getItem()
     if item and item:getID()==cartSession.id then found=item;worldCount=worldCount+1 end
    end
   end
  end end
 end
 local cargoID,cargoWeight,cargoOK=-1,-1,false
 if found then
  assert(found:getFullType()==cartType,'Authoritative cart ID changed type')
  local contents=found:getInventory():getItems()
  if contents:size()==1 then local cargo=contents:get(0);cargoID=cargo:getID();cargoWeight=cargo:getActualWeight()
   cargoOK=cargoID==cartSession.cargoID and cargo:getFullType()=='Base.Log' and math.abs(cargoWeight-cartSession.cargoWeight)<.001
  end
 end
 local a,b=p:getPrimaryHandItem(),p:getSecondaryHandItem()
 local held=found and count==1 and worldCount==0 and not found:getWorldItem() and found:getContainer()==p:getInventory() and a==found and b==found
 local ground=found and count==0 and worldCount==1 and found:getWorldItem()~=nil and not a and not b
 local world=found and found:getWorldItem()
 local placement=world and {x=world:getWorldPosX(),y=world:getWorldPosY(),z=world:getWorldPosZ(),rotation=found:getWorldZRotation()} or nil
 return {worldPose=placement,actor='server',index=actionIndex,phase=actionPhases[actionIndex],id=cartSession.id,cargoID=cargoID,cargoWeight=cargoWeight,
  cargoPreserved=cargoOK,inventoryCount=count,worldCount=worldCount,primaryID=a and a:getID() or -1,secondaryID=b and b:getID() or -1,
  nativeActions=p:getCharacterActions():size(),hasPath=p:hasPath(),held=held==true,ground=ground==true,wall=getTimestampMs()}
end
local function pollAction(now)
 if not pendingAction then return end
 local row=actionState(pendingAction.player)
 if hotkey then row.expectedWorld=pendingAction.expectedWorld end
 assert(now-pendingAction.since<3000,'Authoritative cart action state deadline '..row.phase)
 if not pendingAction.logged or now-pendingAction.logged>=250 then
  pendingAction.logged=now;print('[CART_MP_ACTION] SERVER_STATE '..J.encode(row))
 end
 if not row.cargoPreserved or row.nativeActions~=0 or row.hasPath or not (actionGround[actionIndex] and row.ground or not actionGround[actionIndex] and row.held) then pendingAction.hold=nil;return end
 if hotkey and (not pendingAction.observed or actionGround[actionIndex] and not samePose(row.worldPose,pendingAction.expectedWorld)) then pendingAction.hold=nil;return end
 if not pendingAction.hold then pendingAction.hold=now;return end
 if now-pendingAction.hold<100 then return end
 row.ok=true;row.holdMs=now-pendingAction.hold
 print('[CART_MP_ACTION] SERVER_RECEIPT '..J.encode(row));broadcast('ActionAck',row)
 pendingAction=nil;actionStarted=false;actionIndex=actionIndex+1
 if actionIndex>#actionPhases then
  actionsDone=true;broadcast('ActionsDone',{ok=true,phases=#actionPhases,id=cartSession.id,wall=row.wall})
  print('[CART_MP_ACTION] ALL_COMPLETE '..J.encode({phases=#actionPhases,id=cartSession.id,wall=row.wall}))
 end
end
Events.OnServerStarted.Add(function()
 local climate=getClimateManager()
 for _,index in ipairs({ClimateManager.FLOAT_FOG_INTENSITY,ClimateManager.FLOAT_PRECIPITATION_INTENSITY,ClimateManager.FLOAT_CLOUD_INTENSITY}) do
  local value=climate:getClimateFloat(index);value:setEnableAdmin(true);value:setAdminValue(0)
 end
 print('[CART_MP] CLEAR_WEATHER_ADMIN configured=true')
 print('[QUEUE_TEST] SERVER_READY')
end)
Events.OnClientCommand.Add(function(module,command,p,args)
 if module~='CartMP' then return end
 local ok,e=pcall(function()
  local user=p:getUsername();assert(user=='client1' or user=='client2','unknown test actor')
  if command=='Ready' then
   if not players[user] then
    if not p:getCurrentSquare() then return end
    if not origin then
     if not originSince then originSince=getTimestampMs() end
     origin=require('CartMPPlacement')(p)
     if not origin then
      assert(wallSide and getTimestampMs()-originSince<30000,'Native wall pad chunk readiness deadline')
      return
     end
     print('[CART_MP] CART_PAD '..J.encode(origin))
    end
    local state={x=origin.x+(user=='client2' and 2 or 0),y=origin.y+(user=='client2' and 3 or 0),z=origin.z,variant=variant,cartType=cartType,
     minX=origin.minX,minY=origin.minY,size=origin.size,margin=origin.margin,vegetationFree=origin.vegetationFree,bankVersion=origin.bankVersion,
     elevated=origin.elevated,floorSprite=origin.floorSprite}
    if wallSide then
     for _,key in ipairs({'wallSide','wallSprite','wallX','wallMinY','wallMaxY','ownedWalls','initialHeading'}) do state[key]=origin[key] end
    end
    if user=='client1' then
     local cart=assert(p:getInventory():AddItem(cartType));state.cartId=cart:getID()
     local cargo=cart:getInventory():AddItem('Base.Log');cargo:setActualWeight(cart:getInventory():getEffectiveCapacity(p));cargo:setCustomWeight(true)
     cartSession={id=cart:getID(),cargoID=cargo:getID(),cargoWeight=cargo:getActualWeight(),x=state.x,y=state.y,z=state.z}
     print('[CART_MP] CART_SPEC '..J.encode({variant=variant,cartType=cartType,id=cart:getID(),cargoCount=1,cargoID=cargo:getID(),cargoWeight=cargo:getActualWeight(),cargoType=cargo:getFullType(),capacity=cart:getInventory():getEffectiveCapacity(p)}))
     sendAddItemToContainer(p:getInventory(),cart)
    end
    if not origin.elevated then p:teleportTo(math.floor(state.x),math.floor(state.y),state.z) end
    players[user]=p;ready[user]=state
   end
   if user=='client1' then
    assert(cartMPSeedSprinting(p)==10 and p:getPerkLevel(Perks.Sprinting)==10,'Authoritative Sprinting setup failed')
    print('[CART_MP] SPRINTING_SEED level='..p:getPerkLevel(Perks.Sprinting)..' wall='..getTimestampMs())
   end
   sendServerCommand(p,module,'Setup',ready[user])
  elseif command=='Armed' then
   if origin and origin.elevated and not armed[user] then
    assert(type(args)=='table' and args.padFloors==origin.size*origin.size and args.padVersion==origin.bankVersion and (not wallSide or args.padWalls==49),'Client did not observe every native elevated floor')
    if wallSide then print('[CART_MP_WALL] ARMED '..J.encode({actor=user,wall=getTimestampMs(),floors=args.padFloors,walls=args.padWalls,bankVersion=args.padVersion})) end
    local target=ready[user]
    p:teleportTo(math.floor(target.x),math.floor(target.y),target.z)
   end
   if user=='client1' and (type(args)~='table' or args.sprintLevel~=10 or p:getPerkLevel(Perks.Sprinting)~=10) then
    cartMPSeedSprinting(p);return
   end
   armed[user]=true
   if armed.client1 and armed.client2 and not epoch then
    epoch=getTimestampMs()+25000
    for _,v in pairs(players) do sendServerCommand(v,module,'Start',{epoch=epoch}) end
    print('[CART_MP] START epoch='..epoch)
   end
  elseif wallSide and command=='WallDone' then
   assert(epoch and getTimestampMs()-epoch>=(wallSide=='front' and 18000 or 29000) and armed[user] and not wallDone[user],'Unexpected wall completion')
   wallDone[user]=true
   if wallDone.client1 and wallDone.client2 then
    assert(not wallCleaned,'Duplicate wall cleanup');local count=wallBank.cleanup();assert(count==49,'Native wall ownership cleanup mismatch')
    wallCleaned=true;local receipt={wall=getTimestampMs(),walls=count}
    print('[CART_MP_WALL] CLEANUP '..J.encode(receipt));broadcast('WallCleanup',receipt)
   end
  elseif command=='ActionObservation' then
   assert(hotkey and actions and user=='client2' and pendingAction and args.index==actionIndex
    and args.phase==actionPhases[actionIndex] and args.id==cartSession.id,'Unexpected observer receipt')
   assert(not pendingAction.observed and args.actor=='client2' and args.cargoID==cartSession.cargoID
    and args.cargoPreserved==true and type(args.cargoWeight)=='number' and math.abs(args.cargoWeight-cartSession.cargoWeight)<.001
    and args.inventoryCount==nil and args.inventoryScope=='remote-hand-snapshot'
    and args.itemSource==(actionGround[actionIndex] and 'world' or 'hands') and args.handSameItem==not actionGround[actionIndex]
    and args.luaActions==0 and args.nativeActions==0 and args.hasPath==false and args.worldAttached==actionGround[actionIndex]
    and args.worldCount==(actionGround[actionIndex] and 1 or 0)
    and args.primaryID==(actionGround[actionIndex] and -1 or cartSession.id)
    and args.secondaryID==(actionGround[actionIndex] and -1 or cartSession.id)
    and (not actionGround[actionIndex] or samePose(args.worldPose,pendingAction.expectedWorld)), 'Observer native endpoint differs')
   pendingAction.observed=true
   print('[CART_MP_ACTION] SERVER_OBSERVATION '..J.encode(args))
  elseif command=='ActionBegin' or command=='ActionCheck' then
   assert(actions and epoch and user=='client1' and not actionsDone and cartSession,'Unexpected cart action request')
   assert(type(args)=='table' and args.index==actionIndex and args.phase==actionPhases[actionIndex] and args.id==cartSession.id,'Out-of-order exact cart action request')
   local duration=config.options and config.options.cart_fast_motion and 26000 or 15000
   assert(getTimestampMs()-epoch>=duration,'Cart actions started before motion bank completed')
   if command=='ActionBegin' then
    assert(not actionStarted and not pendingAction,'Duplicate action begin');actionStarted=true
    if actionIndex==1 then cartSession.x=p:getX();cartSession.y=p:getY();cartSession.z=p:getZ() end
    local row={index=actionIndex,phase=actionPhases[actionIndex],id=cartSession.id,wall=getTimestampMs()}
    print('[CART_MP_ACTION] SERVER_BEGIN '..J.encode(row));broadcast('ActionPhase',row)
   else
    assert(actionStarted and not pendingAction,'Action check without native phase begin')
    pendingAction={player=p,since=getTimestampMs(),expectedWorld=args.expectedWorld}
    if hotkey then
     assert(not actionGround[actionIndex] or samePose(args.expectedWorld,args.expectedWorld),'Missing exact expected world pose')
     broadcast('ActionAudit',{index=actionIndex,phase=actionPhases[actionIndex],id=cartSession.id,
      cargoID=cartSession.cargoID,cargoWeight=cartSession.cargoWeight,expectedWorld=args.expectedWorld})
    end
   end
  else error('unknown test command') end
 end)
 if not ok then print('[QUEUE_TEST] FAIL CART_MP server '..tostring(e));if actions then broadcast('ActionFailed',{error=tostring(e)}) end end
end)
Events.OnTick.Add(function()
 local now=getTimestampMs()
 if pendingAction then local ok,e=pcall(pollAction,now);if not ok then pendingAction=nil;print('[QUEUE_TEST] FAIL CART_MP server '..tostring(e));broadcast('ActionFailed',{error=tostring(e)}) end end
 if (epoch and now-epoch>(wallSide and 30000 or config.options and config.options.cart_fast_motion and 27000 or 16000)+(actions and 35000 or 0)) or now-last<(epoch and 100 or 500) then return end;last=now
 for user,p in pairs(players) do
  if epoch and now>=epoch-2000 and (wallSide or config.options and config.options.cart_fast_motion) and user=='client1'
   and not (p:getX()>=origin.minX+origin.margin and p:getX()<=origin.minX+origin.size-origin.margin
    and p:getY()>=origin.minY+origin.margin and p:getY()<=origin.minY+origin.size-origin.margin and math.abs(p:getZ()-origin.z)<.25) then
   print('[QUEUE_TEST] FAIL CART_MP owner left validated pad interior');return
  end
  print('[CART_MP_STATE] '..cartMPState(p))
 end
 if now-lastTraffic>=1000 then lastTraffic=now;print('[CART_MP_TRAFFIC] '..cartMPTraffic()) end
end)
