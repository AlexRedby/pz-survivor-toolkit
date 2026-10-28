local config=require 'QueueTestSelection'
if type(config.options)~='table' or config.options.cart_inventory_equip~=true then return end
assert(config.disposable==true and config.kind=='mp' and config.options.mp_host==true,'Fresh disposable menu Host required')
local J=require 'CartMPJSON'
local P=require 'CartMPInventoryEquipProtocol'
local c=P.variant(config.options.cart_inventory_equip_variant or 'female-empty')
local players,armed,finished={},{},{}
local visualResent=false
local spec,origin,epoch,phase,pending,observed,ack,last,since,pendingSince=nil,nil,nil,'setup',false,false,false,0,nil,nil
local function emit(event,row)
 row=row or {};if row.actor and row.actor~='server' then row.receivedActor=row.actor end
 row.producer=P.producer;row.actor='server';row.event=event;row.wall=getTimestampMs()
 print('[CART_MP_INVENTORY_EQUIP] '..J.encode(row))
end
local function broadcast(command,row) for _,p in pairs(players) do sendServerCommand(p,'CartMPInventoryEquip',command,row) end end
local function state(p)
 local cart=p:getInventory():getItemById(spec.id);assert(cart and cart:getFullType()==P.cartType,'Authoritative exact cart missing')
 local count=0;local inv=p:getInventory():getItems()
 for i=0,inv:size()-1 do if inv:get(i):getID()==spec.id then count=count+1 end end
 local contents=cart:getInventory():getItems();local ids={}
 for i=0,contents:size()-1 do local child=contents:get(i);ids[#ids+1]=tostring(child:getID())..':'..child:getFullType()..':'..tostring(child:getActualWeight()) end
 table.sort(ids)
 local a,b=p:getPrimaryHandItem(),p:getSecondaryHandItem();local pants=p:getWornItem(ItemBodyLocation.PANTS)
 -- Resolve the native worn clothing visual, not a declared fixture string.
 local model=pants and pants:getVisual() and pants:getVisual():getClothingItem():getModel(p:isFemale())
 local worlds=0
 for x=math.floor(p:getX())-4,math.floor(p:getX())+4 do for y=math.floor(p:getY())-4,math.floor(p:getY())+4 do
  local sq=assert(getCell():getGridSquare(x,y,p:getZ()),'Authoritative equip area unloaded')
  local objects=sq:getWorldObjects();for i=0,objects:size()-1 do local item=objects:get(i):getItem();if item and item:getID()==spec.id then worlds=worlds+1 end end
 end end
 return {producer=P.producer,actor='server',phase=phase,wall=getTimestampMs(),variant=c.name,female=p:isFemale(),id=spec.id,ownerID=p:getOnlineID(),cartType=cart:getFullType(),
  cargoIDs=table.concat(ids,'|'),cargoCount=contents:size(),cargoWeight=cart:getInventory():getCapacityWeight(),inventoryScope='owner-inventory',inventoryCount=count,
  primaryID=a and a:getID() or -1,secondaryID=b and b:getID() or -1,handSameItem=a~=nil and a==b,worldAttached=cart:getWorldItem()~=nil,worldCount=worlds,
  nativeActions=p:getCharacterActions():size(),queueScope='native-server-only',hasPath=p:hasPath(),
  pantsType=pants and pants:getFullType() or '',pantsModel=model and model:lower():gsub('\\','/'):gsub('%.x$','') or '',wornCount=p:getWornItems():size()}
end
local function fail(error)
 emit('error',{reason=tostring(error)});print('[QUEUE_TEST] FAIL CART_MP inventory-equip server '..tostring(error));broadcast('Failed',{reason=tostring(error)});phase='failed'
end
Events.OnServerStarted.Add(function()
 assert(cartMPPadHost(),'Inventory-equip must run in new owned menu Host')
 print('[QUEUE_TEST] SERVER_READY')
end)
Events.OnClientCommand.Add(function(module,command,p,args)
 if module~='CartMPInventoryEquip' or phase=='failed' then return end
 local ok,error=pcall(function()
  local user=p:getUsername();assert(user=='client1' or user=='client2','Foreign inventory-equip actor');local now=getTimestampMs()
  if command=='Ready' then
   if not p:getCurrentSquare() then return end
   if not since then since=now end
   if not origin then origin=require('CartMPPlacement')(p);emit('pad',origin) end
   players[user]=p
   if user=='client1' and not spec then
    assert(not p:getPrimaryHandItem() and not p:getSecondaryHandItem(),'Owner setup hands must be empty')
    p:setFemale(c.female);p:getDescriptor():setFemale(c.female);p:clearWornItems()
    p:getHumanVisual():setHairModel('CrewCut');p:getHumanVisual():setBeardModel('')
    local clothes={}
    for _,name in ipairs({'Base.Tshirt_DefaultTEXTURE_TINT','Base.Trousers_JeanBaggy','Base.Shoes_TrainerTINT'}) do
     local item=assert(p:getInventory():AddItem(name));p:setWornItem(item:getBodyLocation(),item);clothes[#clothes+1]=item:getID();sendAddItemToContainer(p:getInventory(),item)
    end
    syncVisuals(p);sendHumanVisual(p)
    local cart=assert(p:getInventory():AddItem(P.cartType));local ids={}
    if c.load=='full' then local cargo=assert(cart:getInventory():AddItem('Base.Log'));cargo:setActualWeight(cart:getInventory():getEffectiveCapacity(p));cargo:setCustomWeight(true)
     ids[1]=tostring(cargo:getID())..':'..cargo:getFullType()..':'..tostring(cargo:getActualWeight()) end
    spec={producer=P.producer,actor='server',id=cart:getID(),ownerID=p:getOnlineID(),variant=c.name,female=c.female,load=c.load,cartType=P.cartType,
     cargoIDs=table.concat(ids,'|'),cargoCount=#ids,cargoWeight=cart:getInventory():getCapacityWeight(),clothes=clothes}
    sendAddItemToContainer(p:getInventory(),cart);emit('spec',spec)
   end
   if not spec then return end
   local row={};for key,value in pairs(spec) do row[key]=value end
   row.x=origin.x+(user=='client2' and 2 or 0);row.y=origin.y+(user=='client2' and 3 or 0);row.z=origin.z
   row.minX=origin.minX;row.minY=origin.minY;row.size=origin.size;row.margin=origin.margin
   p:teleportTo(math.floor(row.x),math.floor(row.y),row.z)
   sendServerCommand(p,module,'Setup',row)
   if not visualResent and players.client1 and players.client2 then
    -- The first native clothing broadcast can precede the observer's connection.
    -- Resend the exact authoritative setup once both owned recipients exist.
    syncVisuals(players.client1);sendHumanVisual(players.client1);visualResent=true
   end
  elseif command=='Armed' then
   assert(spec and args.id==spec.id and args.ownerID==spec.ownerID,'Arming wrong cart/owner')
   armed[user]=true
   if armed.client1 and armed.client2 and not epoch then
    local row=state(players.client1);P.match(row,spec,'server');assert(row.primaryID==-1 and row.secondaryID==-1 and row.nativeActions==0,'Pre-equip state already held/busy')
    epoch=now+10000;phase='pre-walk';broadcast('Start',{epoch=epoch,id=spec.id,ownerID=spec.ownerID});emit('start',{epoch=epoch,id=spec.id,ownerID=spec.ownerID})
   end
  elseif command=='Begin' then
   assert(user=='client1' and epoch and now>=epoch+2000 and phase=='pre-walk' and args.id==spec.id,'Unexpected menu equip begin')
   phase='menu-equip';emit('begin',{id=spec.id,ownerID=spec.ownerID});broadcast('Phase',{phase=phase,wall=now,id=spec.id})
  elseif command=='Check' then
   assert(user=='client1' and phase=='menu-equip' and args.id==spec.id,'Unexpected equip completion')
   P.match(args,spec,'client1');P.nativeTerminal(args)
   phase='settled-tail';pending=true;broadcast('Phase',{phase=phase,wall=now,id=spec.id});emit('owner-check',args)
  elseif command=='Observation' then
   assert(user=='client2' and phase=='settled-tail' and not observed,'Unexpected observer endpoint')
   P.settled(args,spec,'client2');observed=true;emit('observer',args)
  elseif command=='Finished' then
   assert(ack and args.id==spec.id and not finished[user] and args.frames>0 and args.seconds>0,'Invalid role video finish')
   finished[user]=true;emit('role-finished',{role=user,id=spec.id,frames=args.frames,seconds=args.seconds,file=args.file})
   if finished.client1 and finished.client2 then emit('complete',{id=spec.id,ownerID=spec.ownerID,ok=true}) end
  else error('Unknown inventory-equip command') end
 end)
 if not ok then fail(error) end
end)
Events.OnTick.Add(function()
 if phase=='failed' or not since then return end
 local now=getTimestampMs();local ok,error=pcall(function()
  assert(now-since<180000 or finished.client1 and finished.client2,'Inventory-equip Host deadline')
  if not epoch or now<epoch or now-last<100 or ack then return end;last=now
  local row=state(players.client1);P.match(row,spec,'server');emit('sample',row)
  if pending and observed then
   local valid=P.settledReady(row,spec,'server')
   if not valid then pendingSince=nil;return end
   pendingSince=pendingSince or now
   if now-pendingSince>=200 then
    P.settled(row,spec,'server')
    ack=true;row.ok=true;row.holdMs=now-pendingSince;emit('ack',row);broadcast('Ack',row)
   end
  end
 end)
 if not ok then fail(error) end
end)
return true
