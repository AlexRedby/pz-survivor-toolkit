local config=require 'QueueTestSelection'
assert(config.disposable==true and config.kind=='mp' and config.options.mp_host==true,'Fresh disposable menu Host required')
assert(type(config.ffmpeg)=='string' and config.ffmpeg:match('^/'),'Absolute FFmpeg required')
require 'SaucedCarts/ContextMenu'
require 'ISUI/ISContextMenu'
require 'TimedActions/ISTimedActionQueue'
local P=require 'CartMPInventoryEquipProtocol'
local J=require 'CartMPJSON'
local c=P.variant(config.options.cart_inventory_equip_variant or 'female-empty')
local reader=assert(getFileReader('smoke-user.txt',false));local user=reader:readLine();reader:close()
assert(user=='client1' or user=='client2','Unknown inventory-equip role')
local directory=assert(config.videoRoot[user]);assert(directory:match('^/'),'Absolute role video root required')
local spec,epoch,action,video,ack,tailAt=nil,nil,nil,false,false,nil
local started,prepared,armed,done,observed=false,false,false,false,false
local phase,lastReady,lastSample,since,menuAt,walkX,walkY='setup',0,0,nil,nil,nil,nil
local function emit(event,row)
 row=row or {};row.producer=P.producer;row.actor=user;row.event=event;row.wall=getTimestampMs()
 print('[CART_MP_INVENTORY_EQUIP] '..J.encode(row))
end
local function send(command,row) sendClientCommand('CartMPInventoryEquip',command,row or {}) end
local function queue(p) return ISTimedActionQueue.getTimedActionQueue(p).queue end
local function terminal(p) return #queue(p)==0 and p:getCharacterActions():isEmpty() and not p:hasPath() end
local function fail(error)
 cartLabDrive(0);cartLabGait(0);if video then toolkitVideoStop() end;done=true
 emit('error',{reason=tostring(error)});print('[QUEUE_TEST] FAIL CART_MP inventory-equip '..tostring(error))
end
local function position(p,x,y,z)
 p:teleportTo(math.floor(x),math.floor(y),z);p:setX(x);p:setY(y);p:setZ(z);p:setNextX(x);p:setNextY(y);p:setLastX(x);p:setLastY(y);p:setLastZ(z)
 p:ensureOnTile();p:setCurrentSquareFromPosition();p:setMovingSquareNow()
end
local function owner()
 local online=getOnlinePlayers();for i=0,online:size()-1 do local p=online:get(i);if p:getUsername()=='client1' and p:getOnlineID()==spec.ownerID then return p end end
end
local function inspect(p)
 local a,b=p:getPrimaryHandItem(),p:getSecondaryHandItem();local cart,count=nil,0
 if user=='client1' then
  local inv=p:getInventory():getItems();for i=0,inv:size()-1 do local item=inv:get(i);if item:getID()==spec.id then cart=item;count=count+1 end end
 elseif a and a:getID()==spec.id and a==b then cart=a end
 local ids,weight,cargoCount={},-1,-1
 if cart then
  assert(cart:getFullType()==P.cartType,'Exact cart changed type')
  local items=cart:getInventory():getItems();cargoCount=items:size();weight=cart:getInventory():getCapacityWeight()
  for i=0,items:size()-1 do local child=items:get(i);ids[#ids+1]=tostring(child:getID())..':'..child:getFullType()..':'..tostring(child:getActualWeight()) end;table.sort(ids)
 end
 local worlds=0
 for x=math.floor(p:getX())-4,math.floor(p:getX())+4 do for y=math.floor(p:getY())-4,math.floor(p:getY())+4 do
  local sq=assert(getCell():getGridSquare(x,y,p:getZ()),'Inventory-equip capture pad unloaded')
  local objects=sq:getWorldObjects();for i=0,objects:size()-1 do local item=objects:get(i):getItem();if item and item:getID()==spec.id then worlds=worlds+1 end end
 end end
 local pants=p:getWornItem(ItemBodyLocation.PANTS);local model=pants and pants:getVisual() and pants:getVisual():getClothingItem():getModel(p:isFemale())
 return {producer=P.producer,actor=user,phase=phase,wall=getTimestampMs(),id=spec.id,ownerID=p:getOnlineID(),variant=c.name,female=p:isFemale(),cartType=cart and cart:getFullType() or '',
  itemAvailable=cart~=nil,cargoIDs=table.concat(ids,'|'),cargoCount=cargoCount,cargoWeight=weight,
  inventoryScope=user=='client2' and 'remote-hand-snapshot' or 'owner-inventory',inventoryCount=user=='client1' and count or nil,
  primaryID=a and a:getID() or -1,secondaryID=b and b:getID() or -1,handSameItem=a~=nil and a==b,
  worldCount=worlds,worldAttached=cart and cart:getWorldItem()~=nil or false,luaActions=#queue(p),nativeActions=p:getCharacterActions():size(),hasPath=p:hasPath(),
  pantsType=pants and pants:getFullType() or '',pantsModel=model and model:lower():gsub('\\','/'):gsub('%.x$','') or '',wornCount=p:getWornItems():size(),
  x=p:getX(),y=p:getY(),z=p:getZ(),moving=p:isPlayerMoving(),running=p:isRunning(),sprinting=p:isSprinting(),nativeState=cartMPState(p)}
end
local function findPush(context)
 for _,option in ipairs(context.options) do
  if option.name==getText('UI_SaucedCarts_PushCart') or option.name=='Push Cart' then return option end
  if option.subOption then local found=findPush(context:getSubMenu(option.subOption));if found then return found end end
 end
end
local function menu(p,now)
 assert(terminal(p) and not p:isTimedActionInstant(),'Native public equip needs idle queues and native duration')
 local cart=assert(p:getInventory():getItemById(spec.id));local row=inspect(p);P.match(row,spec,user)
 assert(row.primaryID==-1 and row.secondaryID==-1,'Menu equip must begin with empty hands')
 local context=ISContextMenu.get(p:getPlayerNum(),50,50)
 triggerEvent('OnFillInventoryObjectContextMenu',p:getPlayerNum(),context,{cart})
 local option=assert(findPush(context),'Actual inventory Push Cart menu option missing')
 assert(option.onSelect and not option.notAvailable,'Actual inventory Push Cart unavailable');context:hideAndChildren()
 send('Begin',{id=spec.id});phase='menu-equip';menuAt=now
 option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,option.param6,option.param7,option.param8,option.param9,option.param10)
 assert(#queue(p)==1,'Inventory menu must queue exactly one action');action=queue(p)[1]
 assert(action.Type=='ISCartEquipAction' and action.cartId==spec.id and action.character==p and action.sourceType=='inventory'
  and action.maxTime==30 and action:getDuration()==30,'Menu did not create exact native-duration ISCartEquipAction')
 emit('queued',{id=spec.id,ownerID=spec.ownerID,phase=phase,actionType=action.Type,sourceType=action.sourceType,duration=action:getDuration(),maxTime=action.maxTime,
  menuSource='OnFillInventoryObjectContextMenu',walkDistance=math.sqrt((p:getX()-walkX)^2+(p:getY()-walkY)^2)})
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~='CartMPInventoryEquip' then return end
 local ok,error=pcall(function()
  if command=='Setup' then
   assert(args.producer==P.producer and args.variant==c.name and args.female==c.female and args.cartType==P.cartType,'Host inventory-equip spec differs');spec=args
   emit('setup',args)
  elseif command=='Start' then assert(args.id==spec.id and args.ownerID==spec.ownerID,'Wrong start identity');epoch=args.epoch;phase='pre-walk';emit('start',args)
  elseif command=='Phase' then
   assert(args.id==spec.id,'Wrong phase cart');phase=args.phase
   if phase=='settled-tail' then tailAt=getTimestampMs() end
   emit('phase',{phase=phase,id=spec.id,ownerID=spec.ownerID,serverWall=args.wall})
  elseif command=='Ack' then
   assert(args.ok==true and args.holdMs>=200,'Unsettled server acknowledgement');P.settled(args,spec,'server');ack=true
   emit('ack',{id=spec.id,ownerID=spec.ownerID,serverWall=args.wall,holdMs=args.holdMs})
  elseif command=='Failed' then fail(args.reason)
  else error('Unknown inventory-equip server command') end
 end)
 if not ok then fail(error) end
end)
Events.OnConnectFailed.Add(function(a,b) fail('connect '..tostring(a)..' '..tostring(b)) end)
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs();cartLabDrive(0);cartLabGait(0)
 getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false)
 local p=getPlayer();p:setGodMod(true);p:setGhostMode(false);p:setAutoDrink(false)
 print('[CART_MP] CONNECTED '..user)
end)
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,error=pcall(function()
  local now=getTimestampMs();local p=getPlayer();assert(now-since<180000,'Inventory-equip client deadline')
  if not spec then if now-lastReady>1000 then lastReady=now;send('Ready') end;return end
  if not prepared then
   assert(terminal(p) and not p:getPrimaryHandItem() and not p:getSecondaryHandItem(),'Setup hands/queues occupied')
   if user=='client1' then
    if not p:getInventory():getItemById(spec.id) then return end
    for _,id in ipairs(spec.clothes) do if not p:getInventory():getItemById(id) then return end end
    p:setFemale(c.female);p:getDescriptor():setFemale(c.female);p:clearWornItems()
    p:getHumanVisual():setHairModel('CrewCut');p:getHumanVisual():setBeardModel('')
    for _,id in ipairs(spec.clothes) do local item=p:getInventory():getItemById(id);p:setWornItem(item:getBodyLocation(),item) end
    p:resetModel();sendVisual(p)
   end
   position(p,spec.x,spec.y,spec.z);cartLabPoseHeading(math.pi*.75)
   assert(cartMPZoom(user=='client2')==(user=='client2' and 1 or .25),'Wrong native fixture zoom');prepared=true
  end
  local target=owner();if not target then return end
  if user=='client2' then cartMPCamera(target) end
  if not epoch then
   if now-lastReady>1000 then lastReady=now;send('Armed',{id=spec.id,ownerID=spec.ownerID});armed=true end;return
  end
  cartMPHideUI()
  if not video and now>=epoch-2000 then
   assert(toolkitVideoStart(directory,config.ffmpeg),'Inventory-equip video start rejected');video=true;emit('video-start',{id=spec.id,ownerID=spec.ownerID,file=toolkitVideoStatus().file})
  end
  if now<epoch then return end
  assert(p:getX()>=spec.minX+spec.margin and p:getX()<=spec.minX+spec.size-spec.margin and p:getY()>=spec.minY+spec.margin
   and p:getY()<=spec.minY+spec.size-spec.margin and math.abs(p:getZ()-spec.z)<.25,'Actor left validated inventory-equip pad')
  if not walkX then walkX,walkY=target:getX(),target:getY();emit('phase',{phase='pre-walk',id=spec.id,ownerID=spec.ownerID}) end
  if user=='client1' and phase=='pre-walk' then
   if now<epoch+2000 then cartLabGait(0);cartLabDrive(1)
   else
    cartLabDrive(0);assert(now<epoch+4000,'Pre-walk did not settle before menu')
    if not p:isPlayerMoving() then
     assert(math.sqrt((p:getX()-walkX)^2+(p:getY()-walkY)^2)>=.25,'Pre-menu native Walk did not move');menu(p,now)
    end
   end
  end
  if now-lastSample>=50 then
   lastSample=now;local row=inspect(target)
   if user=='client1' or row.itemAvailable then P.match(row,spec,user) end
   emit('sample',row)
  end
  if user=='client1' and phase=='menu-equip' and action and terminal(p) then
   assert(now-menuAt>=200 and action.action,'Native menu equip had no native lifecycle')
   local row=inspect(p);row.phase='settled-tail';P.settled(row,spec,user)
   row.actionType=action.Type;row.duration=action:getDuration();row.nativeFinished=action.action:finished()
   row.nativeForceComplete=action.action:isForceComplete();row.nativeTime=action.action:getCurrentTime();row.nativeProgress=action.action:getJobDelta()
   P.nativeTerminal(row)
   send('Check',row);phase='await-tail';emit('native-finished',row)
  end
  if phase=='settled-tail' and tailAt then
   local row=inspect(target);local ready=pcall(P.settled,row,spec,user)
   if user=='client2' and ready and not observed then observed=true;send('Observation',row);emit('observer',row) end
   if ack and now-tailAt>=2200 then
    assert(ready,'Tail endpoint lost exact cart/outfit');assert(toolkitVideoStop(),'Inventory-equip video stop rejected');phase='video-flush'
   end
  elseif phase=='video-flush' then
   local status=toolkitVideoStatus();assert(status.state~='failed',status.error);if status.state~='completed' then return end
   assert(status.frames and status.frames>0 and status.seconds and status.seconds>0 and status.file,'Video did not finalize')
   emit('video-final',{id=spec.id,ownerID=spec.ownerID,file=status.file,frames=status.frames,seconds=status.seconds,state=status.state})
   send('Finished',{id=spec.id,file=status.file,frames=status.frames,seconds=status.seconds})
   print('[CART_MP] VIDEO_FINAL '..J.encode(status));emit('complete',{id=spec.id,ownerID=spec.ownerID,ok=true})
   J.emit({suite=config.suite,kind=config.kind,mode=config.mode,actor=user,event='case',id='owner_observer_motion',status='captured',inventoryEquip=true})
   J.emit({suite=config.suite,kind=config.kind,mode=config.mode,actor=user,event='complete',expected=1,performed=1,skipped=0,failed=0});done=true
  end
 end)
 if not ok then fail(error) end
end)
return true
