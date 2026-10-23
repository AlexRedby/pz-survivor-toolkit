-- Explicit owned world-loss/cancel/retry experiment. Never enables production admission.
local config=require 'QueueTestSelection'
assert(config.disposable==true and config.options.cart_action_invalidation==true,'Explicit owned action invalidation required')
local J=require 'CartMPJSON'
local M={};local module='CartActionInvalidation';local actor=isServer() and 'server' or nil
local spec,players,ready,ground,lost,recovered={},{},{},{},{},{}
local function encode(row)
 local parts={}
 for k,v in pairs(row) do
  local value
  if type(v)=='number' then
   assert(v==math.floor(v) and math.abs(v)<=9007199254740991,'Exact diagnostic integer required')
   local negative=v<0;if negative then v=-v end
   local digits={};repeat local q=math.floor(v/10);digits[#digits+1]=string.char(48+v-q*10);v=q until v==0
   value=negative and '-' or '';for i=#digits,1,-1 do value=value..digits[i] end
  else value=J.encode(v) end
  parts[#parts+1]=J.encode(k)..':'..value
 end
 return '{'..table.concat(parts,',')..'}'
end
local function emit(event,phase,fields)
 local row={actor=actor,event=event,phase=phase,owner=spec.owner,cart=spec.cart,wall=getTimestampMs()}
 for k,v in pairs(fields or {}) do row[k]=v end
 print('[CART_ACTION_INVALIDATION] '..encode(row));return row
end
local function cargo(item)
 local values=item:getInventory():getItems();assert(values:size()==1,'Invalidation cargo count differs')
 local value=values:get(0);return value:getID(),value:getActualWeight()
end
local function worldCart(p)
 local item,world,count=nil,nil,0
 for x=math.floor(p:getX())-4,math.floor(p:getX())+4 do for y=math.floor(p:getY())-4,math.floor(p:getY())+4 do
  local sq=getCell():getGridSquare(x,y,p:getZ());if not sq then return end
  local objects=sq:getWorldObjects()
  for i=0,objects:size()-1 do local w=objects:get(i);local v=w:getItem()
   if v and v:getID()==spec.cart then item,world,count=v,w,count+1 end
  end
 end end
 assert(count<=1,'Invalidation world cart duplicated');return item,world,count
end
local function endpoint(p,state,event,phase)
 local item,world,count=worldCart(p);if count==nil then return end
 local a,b=p:getPrimaryHandItem(),p:getSecondaryHandItem()
 local held=a and a==b and a:getID()==spec.cart and not a:getWorldItem()
 if state=='held' then if not held or count~=0 then return end;item=a
 else if a or b or count~=1 or not world or item:getWorldItem()~=world then return end end
 local actions=p:getCharacterActions():size();if actions~=0 or p:hasPath() then return end
 local row={state=state,cargoID=select(1,cargo(item)),cargoWeight=select(2,cargo(item)),
  primaryID=a and a:getID() or -1,secondaryID=b and b:getID() or -1,handSameItem=a~=nil and a==b,
  worldAttached=item:getWorldItem()~=nil,worldCount=count,nativeActions=actions,hasPath=false,
  inventoryScope=actor=='client2' and 'remote-hand-snapshot' or 'owner-inventory',
  queueScope=actor=='server' and 'native-server-only' or actor=='client1' and 'owner-local' or 'remote-native-only'}
 assert(row.cargoID==spec.cargoID and row.cargoWeight==spec.cargoWeight,'Invalidation cargo changed')
 if actor~='client2' then
  local items=p:getInventory():getItems();local n=0
  for i=0,items:size()-1 do if items:get(i):getID()==spec.cart then n=n+1;assert(items:get(i)==item,'Invalidation inventory alias') end end
  if n~=(state=='held' and 1 or 0) then return end;row.inventoryCount=n
 end
 if actor=='client1' then
  row.luaActions=#ISTimedActionQueue.getTimedActionQueue(p).queue;if row.luaActions~=0 then return end
 end
 row.guarded=actor=='server';emit(event,phase,row);return item
end
if isServer() then
 local old,receipt,acceptedFresh,mutation
 local function broadcast(command,args) for _,p in pairs(players) do sendServerCommand(p,module,command,args or spec) end end
 local function snapshot(p,args,stage)
  local row=assert(cartActionAdmission(p),'Native invalidation admission missing')
  assert(row.token==args.token and row.transaction==args.transaction and row.cart==spec.cart
   and row.owner==spec.owner and row.stage==stage and row.accepted==true and row.admittedBindingValid==true,
   'Exact accepted invalidation incarnation missing')
  row.guarded=true;return row
 end
 local function retry()
  if lost.client1 and lost.client2 and receipt then broadcast('Retry') end
 end
 Events.OnClientCommand.Add(function(mod,command,p,args)
  if mod~=module then return end
  local ok,err=pcall(function()
   assert(cartLeaseSource(p),'Invalidation original native source missing')
   local role=p:getUsername();assert(role=='client1' or role=='client2','Invalidation actor differs')
   local target=assert(cartLeaseTarget(args.owner or p:getOnlineID()),'Invalidation owner unregistered')
   assert(target:getUsername()=='client1' and cartLeaseOwnerConnection(target),'Invalidation owner transport missing')
   if command=='Begin' then
    assert(role=='client1' and not spec.owner,'Duplicate invalidation begin')
    local item=assert(target:getPrimaryHandItem());assert(item==target:getSecondaryHandItem())
    spec={owner=target:getOnlineID(),cart=item:getID()};spec.cargoID,spec.cargoWeight=cargo(item)
    for _,name in ipairs({'client1','client2'}) do
     local online=getOnlinePlayers()
     for i=0,online:size()-1 do local v=online:get(i);if v:getUsername()==name then players[name]=v end end
     assert(players[name] and cartLeaseTarget(players[name]:getOnlineID())==players[name],'Invalidation role missing')
    end
    assert(endpoint(target,'held','init',0),'Invalidation initial server hands unsettled');broadcast('Init')
    return
   end
   assert(args.owner==spec.owner and target==players.client1 and p==players[role],'Invalidation native actor changed')
   if command=='Ready' then
    assert(not ready[role]);ready[role]=true;if ready.client1 and ready.client2 then broadcast('Release') end
   elseif command=='Released' then
    assert(role=='client1');local native=snapshot(target,args,'terminal')
    assert(native.nativeState=='Done' and native.reason=='completed','Initial release did not complete')
    assert(endpoint(target,'ground','ground',1),'Server ground release unsettled');broadcast('Ground')
   elseif command=='GroundReady' then
    assert(not ground[role]);ground[role]=true;if ground.client1 and ground.client2 then broadcast('Pickup') end
   elseif command=='Inspect' then
    assert(role=='client1' and not old);old=snapshot(target,args,'accepted')
    assert(old.kind=='ToolkitWoodCartPickup' and old.nativeBindingValid==true and old.nativeState=='Accept')
    emit('accepted',2,old);sendServerCommand(p,module,'Accepted',old)
   elseif command=='Invalidate' then
    assert(role=='client1' and old and not mutation);local current=snapshot(target,args,'accepted')
    assert(current.actionEpoch==old.actionEpoch and current.tableEpoch==old.tableEpoch and current.nativeBindingValid==true)
    local item,world,count=worldCart(target);assert(count==1 and item and world,'Exact invalidation world cart missing')
    local sq=assert(world:getSquare());local x,y,z=sq:getX(),sq:getY(),sq:getZ()
    local nextSquare=assert(getCell():getGridSquare(x+2,y,z),'Invalidation destination unloaded')
    assert(nextSquare:TreatAsSolidFloor(),'Invalidation destination lacks native floor')
    local rotation=item:getWorldZRotation()
    sq:transmitRemoveItemFromSquare(world);item:setWorldItem(nil)
    local moved=assert(nextSquare:AddWorldInventoryItem(item,.5,.5,0,false),'World cart move failed')
    assert(moved==item,'World cart move replaced item');item:setWorldZRotation(rotation)
    local replacement=assert(item:getWorldItem());assert(replacement~=world and replacement:getSquare()==nextSquare)
    replacement:transmitCompleteItemToClients();mutation=true
    local removed=true
    for _,objects in ipairs({sq:getWorldObjects(),sq:getObjects()}) do
     for i=0,objects:size()-1 do if objects:get(i)==world then removed=false end end
    end
    assert(removed,'Old native world object remains in its square lists')
    emit('mutation',2,{oldWorldEpoch=old.worldEpoch,worldReplaced=true,oldWorldRemoved=removed,
     oldX=x,oldY=y,newX=x+2,newY=y,cargoID=spec.cargoID,cargoWeight=spec.cargoWeight})
    local retired=snapshot(target,args,'terminal')
    assert(retired.reason=='item-invalid' and retired.nativeBindingValid==false,'Lost world identity did not retire admission')
    retired.currentAuthority=false;emit('retired',2,retired)
    assert(cartActionInvalidationStop(target,old.token,old.actionEpoch),'Exact invalidated native stop failed')
    broadcast('Moved')
   elseif command=='Settled' then
    assert(role=='client1' and mutation and not receipt)
    assert(args.token==old.token and args.transaction==old.transaction and args.kind==old.kind
     and args.protocol==1 and args.player==spec.owner and args.state=='canceled','Canonical old cancellation differs')
    receipt={protocol=args.protocol,player=args.player,transaction=args.transaction,kind=args.kind,token=args.token,state=args.state}
    assert(endpoint(target,'ground','invalid-ground',2),'Invalidated native pickup had an effect');retry()
   elseif command=='LostReady' then
    assert(mutation and not lost[role]);lost[role]=true;retry()
   elseif command=='InspectFresh' then
    assert(role=='client1' and receipt and not acceptedFresh);acceptedFresh=snapshot(target,args,'accepted')
    assert(acceptedFresh.kind==old.kind and acceptedFresh.nativeBindingValid==true and acceptedFresh.nativeState=='Accept'
     and acceptedFresh.token~=old.token and acceptedFresh.actionEpoch~=old.actionEpoch
     and acceptedFresh.tableEpoch~=old.tableEpoch and acceptedFresh.worldEpoch~=old.worldEpoch
     and acceptedFresh.itemEpoch==old.itemEpoch,'Fresh pickup inherited invalidated incarnation')
    emit('fresh-accepted',3,acceptedFresh)
    -- Replay the exact historical cancellation returned from its genuine owner callback.
    sendServerCommand(p,'PZSurvivorToolkitActions','State',receipt)
    sendServerCommand(p,'PZSurvivorToolkitActions','State',receipt)
   elseif command=='Recovered' then
    assert(role=='client1' and acceptedFresh);local native=snapshot(target,args,'terminal')
    assert(native.token==acceptedFresh.token and native.nativeState=='Done' and native.reason=='completed')
    assert(endpoint(target,'held','recovered',3),'Fresh native pickup not settled');broadcast('Recovered')
   elseif command=='RecoveredReady' then
    assert(not recovered[role]);recovered[role]=true
    if recovered.client1 and recovered.client2 then assert(endpoint(target,'held','complete',3));broadcast('Done') end
   else error('Unknown invalidation command '..tostring(command)) end
  end)
  if not ok then emit('error',0,{reason=tostring(err)});print('[CART_ACTION_INVALIDATION] ERROR '..tostring(err)) end
 end)
 return M
end
local reader=assert(getFileReader('smoke-user.txt',false));actor=reader:readLine();reader:close()
local Ack
local phase,stage,action,driver,started,terminal,oldAction,oldReceipt,oldNative,oldSource,deadline,replays=0,nil,nil,nil,false,nil,nil,nil,nil,nil,nil,0
local initial,groundSeen,lostSeen,recoveredSeen,done=false,false,false,false,false
local function send(command,args)
 args=args or {};args.owner=spec.owner or getPlayer():getOnlineID();sendClientCommand(getPlayer(),module,command,args)
end
local function identify(s) return {token=s.receipt.token,transaction=s.receipt.transaction} end
local function input(p,item,pickup,index)
 driver=driver or assert(require 'CartLeaseMenuActions');phase=index;started=false
 action=driver.enqueue(p,item,pickup,index,function(event,row) emit('menu-'..event,index,row) end)
end
Events.OnServerCommand.Add(function(mod,command,args)
 local ok,err=pcall(function()
  if mod=='PZSurvivorToolkitActions' and actor=='client1' and command=='State' and oldReceipt and args.token==oldReceipt.token then
   assert(cartLeaseIngress()==oldSource and cartLeaseCurrent()==oldSource,'Historical receipt transport changed')
   assert(args.protocol==1 and args.player==spec.owner and args.transaction==oldReceipt.transaction
    and args.kind==oldReceipt.kind and args.state=='canceled','Historical invalidation receipt differs')
   if not terminal then
    assert(phase==2);terminal=args
    local row={};for k,v in pairs(args) do row[k]=v end
    row.guarded=true;row.sealed=false;row.currentAuthority=false;emit('native-terminal',2,row)
   else
    assert(phase==3 and action and action.receipt and replays<2,'Unexpected duplicate old terminal')
    local fresh=action.receipt;local q=ISTimedActionQueue.getTimedActionQueue(getPlayer())
    assert(q.current==action.action and action.action.action==action.native and Ack.capture(action.action)==fresh
     and Ack.observe(action.action,fresh)=='started','Historical cancellation affected fresh authority')
    local observed=Ack.observe(oldAction,oldReceipt)
    assert(Ack.capture(oldAction)==nil and Ack.state(oldAction,oldReceipt)==nil and observed~='started' and observed~='completed')
    replays=replays+1;emit('stale-terminal-refused',3,{oldToken=oldReceipt.token,oldTransaction=oldReceipt.transaction,
     token=fresh.token,transaction=fresh.transaction,kind=fresh.kind,duplicate=replays,guarded=true,sealed=true,currentAuthority=true,
     queueUnchanged=true,oldCaptureUnavailable=true,oldStateUnavailable=true,oldObservation=observed or 'unavailable'})
   end
   return
  end
  if mod~=module then return end
  assert(cartLeaseIngress() and cartLeaseIngress()==cartLeaseCurrent(),'Invalidation command original ingress missing')
  if command=='Init' then assert(not spec.owner);spec=args;stage='init'
  elseif command=='Release' then stage='release'
  elseif command=='Ground' then stage='ground'
  elseif command=='Pickup' then stage='pickup'
  elseif command=='Accepted' then
   assert(actor=='client1' and phase==2 and action.receipt and args.token==action.receipt.token
    and args.nativeBindingValid==true and args.stage=='accepted');send('Invalidate',identify(action));stage='invalidating'
  elseif command=='Moved' then stage='lost'
  elseif command=='Retry' then stage='retry'
  elseif command=='Recovered' then stage='recovered'
  elseif command=='Done' then
   local online=getOnlinePlayers();local owner
   for i=0,online:size()-1 do local p=online:get(i);if p:getOnlineID()==spec.owner then owner=p end end
   assert(endpoint(assert(owner),'held','complete',3),'Final invalidation endpoint unsettled');done=true
  else error('Unknown invalidation reply '..tostring(command)) end
 end)
 if not ok then emit('error',phase,{reason=tostring(err)});print('[CART_ACTION_INVALIDATION] ERROR '..tostring(err)) end
end)
function M.finish(owner,now)
 if actor=='client1' and not Ack then Ack=assert(PZSurvivorToolkit and PZSurvivorToolkit.ActionQueueAcknowledgements,'Runtime owner receipt API missing') end
 if done then return true end
 deadline=deadline or now;assert(now-deadline<45000,'Action invalidation bank deadline')
 if not stage then if actor=='client1' then stage='begin';send('Begin') end;return false end
 if stage=='init' and not initial then
  if not endpoint(owner,'held','init',0) then return false end
  initial=true;send('Ready')
 elseif stage=='release' and actor=='client1' then
  input(owner,assert(owner:getPrimaryHandItem()),false,1);stage='release-action'
 elseif stage=='release-action' then
  if driver.poll(action) then send('Released',identify(action));stage='release-wait' end
 elseif stage=='ground' and not groundSeen then
  if not endpoint(owner,'ground','ground',1) then return false end
  groundSeen=true;send('GroundReady')
 elseif stage=='pickup' and actor=='client1' then
  local item=worldCart(owner);input(owner,assert(item),true,2);stage='pickup-action'
 elseif stage=='pickup-action' then
  assert(not driver.poll(action),'Invalidation pickup completed before its accepted guard')
  if action.receipt and not started then
   started=true;oldAction=action.action;oldReceipt=action.receipt;oldNative=action.native;oldSource=action.source
   send('Inspect',identify(action))
  end
 elseif stage=='lost' and not lostSeen then
  if actor=='client1' then
   if not terminal then return false end
   local observed=Ack.observe(oldAction,oldReceipt)
   assert(Ack.capture(oldAction)==nil and Ack.state(oldAction,oldReceipt)==nil and observed~='started' and observed~='completed')
   if not endpoint(owner,'ground','invalid-ground',2) then return false end
   emit('invalidated',2,{token=oldReceipt.token,transaction=oldReceipt.transaction,kind=oldReceipt.kind,
    observation=observed or 'unavailable',currentAuthority=false,captureUnavailable=true,stateUnavailable=true})
   send('Settled',terminal)
  else if not endpoint(owner,'ground','invalid-ground',2) then return false end end
  lostSeen=true;send('LostReady')
 elseif stage=='retry' and actor=='client1' then
  local item=worldCart(owner);input(owner,assert(item),true,3);stage='retry-action'
 elseif stage=='retry-action' then
  local complete=driver.poll(action)
  if action.receipt and not started then started=true;send('InspectFresh',identify(action)) end
  if complete then assert(replays==2,'Historical terminal replay proof incomplete');send('Recovered',identify(action));stage='recovered-wait' end
 elseif stage=='recovered' and not recoveredSeen then
  if not endpoint(owner,'held','recovered',3) then return false end
  recoveredSeen=true;send('RecoveredReady')
 end
 return false
end
return M
