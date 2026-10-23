-- Owned disposable Host fixture. The guest follows native death, Coop respawn and menu reconnect.
local C=require 'QueueTestSelection'
local selected=false
for _,id in ipairs(C.cases or {}) do if id=='lease_lifecycle' then selected=true end end
if not selected then return {} end
assert(C.disposable==true and C.kind=='mp' and C.options and C.options.mp_host==true,'Lifecycle requires disposable menu Host')
local P=require 'CartLeaseProtocol'
local J=require 'CartMPJSON'
local MODULE='CartLeaseLifecycle'
local CART='SaucedWheelbarrow.WheelbarrowWood'
local REJOIN='cart-lease-lifecycle-rejoin.txt'
local SETUP='cart-lease-lifecycle-setup.txt'
local LIMIT,DEADLINE=12,240000
local M={}
local failed,role,phase=false,isServer() and 'server' or nil,0
local function now() return getTimestampMs() end
local function emit(event,row)
 row=row or {};row.actor=role;row.event=event;row.phase=row.phase or phase;row.wall=now()
 print('[CART_LIFECYCLE] '..J.encode(row))
end
local function standard(event,row)
 row=row or {};row.event=event;row.actor=role;row.suite=C.suite;row.kind=C.kind;row.mode=C.mode
 print('[QUEUE_CHECK] '..J.encode(row))
end
local function fail(reason)
 if failed then return end;failed=true
 emit('error',{reason=tostring(reason)})
 print('[CART_LIFECYCLE] ERROR '..tostring(reason));print('[QUEUE_TEST] FAIL CART_LIFECYCLE '..tostring(role)..' '..tostring(reason))
end
local function guarded(fn)
 if failed then return end
 local ok,err=pcall(fn);if not ok then fail(err) end
end
local function read(name)
 local f=getFileReader(name,false);if not f then return nil end
 local value=f:readLine();f:close();return value
end
local function write(name,value)
 local f=assert(getFileWriter(name,true,false),'Cannot write owned lifecycle scalar');f:write(value);f:close()
end
local function token(value)
 if type(value)~='string' then return nil end
 local version,process,actor,connection,revision=value:match('^(%d+)|([^|]+)|(%d+)|(%d+)|(%d+)$')
 assert(version=='1' and process and actor and connection and revision,'Malformed native lifetime token')
 return {process=process,actor=actor,connection=connection,revision=revision}
end
local function held(p,cart)
 if not p or p:isDead() or not p:getCurrentSquare() then return nil end
 local item=p:getPrimaryHandItem()
 if not item or item~=p:getSecondaryHandItem() or item:getWorldItem() or item:getFullType()~=CART or cart and item:getID()~=cart then return nil end
 local lifetime=cartLeaseLifetime(p);if not lifetime then return nil end
 token(lifetime)
 local inv=item:getInventory();local items=inv and inv:getItems()
 if not items or items:size()~=1 then return nil end
 local cargo=items:get(0)
 if cargo:getFullType()~='Base.Log' or cargo:getActualWeight()~=30 then return nil end
 return {mode='motion',item=item,cart=item:getID(),lifetime=lifetime,cargoID=cargo:getID(),cargoWeight=cargo:getActualWeight()}
end
local protected={'session','grant','lease','seq','open','visible','body','received','terminal','rebind','acceptedAt'}
local function unchanged(a,b)
 for _,k in ipairs(protected) do assert(a[k]==b[k],'Rejected stale state changed '..k) end
end
local function tuple(row,b)
 if b then for _,k in ipairs({'session','grant','lease','seq','cart','nonce'}) do if b[k]~=nil then row[k]=b[k] end end end
 return row
end
local function playerNamed(name)
 local players=getOnlinePlayers()
 for i=0,players:size()-1 do local p=players:get(i);if p:getUsername()==name and not p:isDead() then return p end end
 return nil
end
local function containsActor(p)
 local players=getOnlinePlayers()
 for i=0,players:size()-1 do if players:get(i)==p then return true end end
 return false
end
local function bodiesAt(x,y,z,id,previous)
 local found={}
 for dx=-2,2 do for dy=-2,2 do
  local sq=getCell():getGridSquare(math.floor(x)+dx,math.floor(y)+dy,z)
  if sq then
   local bodies=sq:getDeadBodys()
   for i=0,bodies:size()-1 do
    local body=bodies:get(i)
    if body:getCharacterOnlineID()==id and not (previous and previous[body]) then found[#found+1]=body end
   end
  end
 end end
 return found
end
local function corpseBaseline(p)
 local known={};for _,body in ipairs(bodiesAt(p:getX(),p:getY(),p:getZ(),p:getOnlineID())) do known[body]=true end
 return known
end
local function bodiesFor(cached)
 local found,seen={},{}
 for _,position in ipairs({{x=cached.x,y=cached.y,z=cached.z},{x=cached.actor:getX(),y=cached.actor:getY(),z=cached.actor:getZ()}}) do
  for _,body in ipairs(bodiesAt(position.x,position.y,position.z,cached.id,cached.corpses)) do
   if not seen[body] then seen[body]=true;found[#found+1]=body end
  end
 end
 return found
end
local function disposition(old)
 local item=old.binding.item;local inv=item:getInventory();local cargo=inv and inv:getItemById(old.binding.cargoID)
 local location=item:getWorldItem() and 'world-item' or item:getContainer() and 'native-container' or 'unattached'
 local corpses=bodiesFor(old)
 for _,body in ipairs(corpses) do
  local container=body:getContainer()
  if container and container:getItemById(old.binding.cart) then location='corpse-container' end
 end
 return {ownerID=old.id,cart=old.binding.cart,lifetime=old.binding.lifetime,cargoID=old.binding.cargoID,cargoWeight=cargo and cargo:getActualWeight() or -1,
  cargoStillInside=cargo~=nil,cartLocation=location,corpseCount=#corpses,oldActorDead=old.actor:isDead(),oldActorHasSquare=old.actor:getCurrentSquare()~=nil,
  oldActorInOnlineList=containsActor(old.actor),sameCartPreservationClaim=false,
  cachedX=old.x,cachedY=old.y,cachedZ=old.z,currentX=old.actor:getX(),currentY=old.actor:getY(),currentZ=old.actor:getZ(),
  corpseX=corpses[1] and corpses[1]:getX() or nil,corpseY=corpses[1] and corpses[1]:getY() or nil,corpseZ=corpses[1] and corpses[1]:getZ() or nil}
end
-- Optional native getters are diagnostic only; unavailable getters omit a field.
local function nativeRead(object,name,arg)
 if not object then return nil end
 local ok,value=pcall(function()
  local getter=object[name];if type(getter)~='function' then return nil end
  if arg~=nil then return getter(object,arg) end
  return getter(object)
 end)
 if ok then return value end
 return nil
end
local function deathProgress(cached)
 if not cached or not cached.deathStarted then return end
 local elapsed=now()-cached.deathStarted
 cached.deathSamples=cached.deathSamples or {}
 for _,seconds in ipairs({1,2,5}) do
  if elapsed>=seconds*1000 and not cached.deathSamples[seconds] then
   cached.deathSamples[seconds]=true
   local corpses=bodiesFor(cached)
   local nativeState=nativeRead(cached.actor,'getCurrentState')
   emit('native-death-progress',{ownerID=cached.id,lifetime=cached.binding.lifetime,elapsedMs=elapsed,sampleSeconds=seconds,
    nativeState=nativeState and tostring(nativeState) or nil,
    bDead=nativeRead(cached.actor,'getVariableBoolean','bDead'),onFloor=nativeRead(cached.actor,'isOnFloor'),
    onDeathDone=nativeRead(cached.actor,'isOnDeathDone'),animationUpdating=nativeRead(cached.actor,'isAnimationUpdatingThisFrame'),
    nativeLifetimeAbsent=cartLeaseLifetime(cached.actor)==nil,hasSquare=cached.actor:getCurrentSquare()~=nil,onlineList=containsActor(cached.actor),
    cachedX=cached.x,cachedY=cached.y,cachedZ=cached.z,currentX=cached.actor:getX(),currentY=cached.actor:getY(),currentZ=cached.actor:getZ(),
    corpseCount=#corpses,corpseX=corpses[1] and corpses[1]:getX() or nil,corpseY=corpses[1] and corpses[1]:getY() or nil,corpseZ=corpses[1] and corpses[1]:getZ() or nil})
  end
 end
end
local function transitionEvidence(before,after,which,row)
 local a,b=assert(token(before)),assert(token(after));assert(a.process==b.process,'Process changed within native client/server')
 assert(a.actor~=b.actor,'Lifecycle reused retired native actor epoch')
 local sameTransport=which==2 or role=='client1'
 assert((a.connection==b.connection)==sameTransport,'Native transport epoch did not match lifecycle transition')
 row=row or {};row.before=before;row.after=after;row.actorChanged=true;row.sameTransport=sameTransport;row.transportScope=role=='server' and 'owner-transport' or 'local-client-ingress'
 return row
end
if isServer() then
 local controller=P.server(assert(cartLeaseChallengeSeed())..':lifecycle',{limit=8})
 local players,hello,acks,prepared,finished,done={}, {}, {}, {}, {}, {}
 local attempts={client1=0,client2=0}
 local target,binding,spec,origin,old,stage,since,stageAt=nil,nil,nil,nil,nil,'hello',nil,nil
 local absenceSent,serverRemoved,hostRemoved,respawnOffered=false,false,false,false
 local finalOffered=false
 local function send(p,command,args) if p then sendServerCommand(p,MODULE,command,args) end end
 local function broadcast(command,args) for _,p in pairs(players) do send(p,command,args) end end
 local function all(t) return t.client1 and t.client2 end
 local function cache()
  return {actor=target,connection=assert(cartLeaseOwnerConnection(target),'Exact native owner transport missing'),id=target:getOnlineID(),binding=binding,
   x=target:getX(),y=target:getY(),z=target:getZ(),corpses=corpseBaseline(target),prepared=prepared}
 end
 local function observe()
  local conn=assert(cartLeaseOwnerConnection(target),'Current native owner connection missing')
  local next=held(target,spec.cart);if not next then return nil end
  assert(controller:observe(target:getOnlineID(),conn,target,next),'Native server observation refused')
  if not binding and old then emit('transition',transitionEvidence(old.binding.lifetime,next.lifetime,phase,{ownerID=target:getOnlineID(),oldOwnerID=old.id,cart=next.cart,newNativeActor=target~=old.actor})) end
  binding=next;return next
 end
 local function setup(nextPhase,p)
  assert(nextPhase==phase+1,'Nonsequential lifecycle phase')
  local previous=old;phase=nextPhase;target=p;players.client2=p
  if phase>1 then
   assert(previous and target~=previous.actor,'Native new actor aliases retired actor')
   local conn=assert(cartLeaseOwnerConnection(target),'New native owner connection missing')
   local active=cartLeaseConnectionActive(previous.connection)
   assert(type(active)=='boolean' and active==(phase==2),'Original native transport active state differs')
   assert((conn==previous.connection)==(phase==2),'Native transport object did not change as required')
   emit('native-connection',{ownerID=target:getOnlineID(),oldOwnerID=previous.id,oldConnectionActive=active,sameTransport=conn==previous.connection,guarded=true})
   emit('cart-disposition',disposition(previous))
  end
  local inv=target:getInventory()
  local cart=previous and inv:getItemById(previous.binding.cart) or nil
  local reused=cart~=nil
  if cart then assert(cart:getFullType()==CART,'Existing fixture cart changed type') end
  if not cart then
   cart=assert(inv:AddItem(CART),'Cannot add native fixture cart')
   local cargo=assert(cart:getInventory():AddItem('Base.Log'),'Cannot add native fixture cargo');cargo:setActualWeight(30);cargo:setCustomWeight(true)
   sendAddItemToContainer(inv,cart)
  end
  local cargo=assert(cart:getInventory():getItems():get(0),'Fixture cargo missing')
  assert(cart:getInventory():getItems():size()==1 and cargo:getFullType()=='Base.Log' and cargo:getActualWeight()==30,'Native fixture cargo differs')
  spec={phase=phase,ownerID=target:getOnlineID(),cart=cart:getID(),cargoID=cargo:getID(),cargoWeight=30,x=origin.x,y=origin.y,z=origin.z,reusedNativeCart=reused}
  emit('cart-setup',{ownerID=spec.ownerID,cart=spec.cart,cargoID=spec.cargoID,cargoWeight=30,reusedNativeCart=reused,
   previousCart=previous and previous.binding.cart or nil,newFixtureCart=not reused,sameCartPreservationClaim=false})
  acks={};prepared={};attempts={client1=0,client2=0};binding=nil;stage='binding';stageAt=now()
  for name,recipient in pairs(players) do
   recipient:teleportTo(math.floor(origin.x)+(name=='client1' and 2 or 0),math.floor(origin.y)+(name=='client1' and 2 or 0),origin.z)
   local descriptor={};for key,value in pairs(spec) do descriptor[key]=value end
   descriptor.previousLifetime=previous and previous.prepared[name].clientLifetime or nil
   send(recipient,'Setup',descriptor)
  end
 end
 local function staleServer(event)
  local e=old.prepared.client2.payload
  local before=controller:snapshot(old.id)
  assert(not controller:accept(old.id,old.connection,old.actor,e,now()),'Retired cached native source payload accepted')
  unchanged(before,controller:snapshot(old.id))
  emit(event,tuple({ownerID=old.id,lifetime=old.binding.lifetime,stalePayloadAccepted=false,cachedActor=true,cachedConnection=true,guarded=true},e))
 end
 local function progress()
  if not old or stage~='await-death' and stage~='await-reconnect' then return end
  deathProgress(old)
  if cartLeaseLifetime(old.actor)==nil then
   controller:unavailable(old.id,old.connection,old.actor)
   if not absenceSent then
    absenceSent=true;staleServer('unavailable-replay')
    emit('unavailable',{ownerID=old.id,lifetime=old.binding.lifetime,nativeLifetimeAbsent=true,oldActorDead=old.actor:isDead()})
    for name,recipient in pairs(players) do
     if name=='client1' or cartLeaseConnectionActive(old.connection)==true then send(recipient,'ProbeAbsent',{phase=phase,ownerID=old.id,reason=stage,stale=old.prepared[name].reply,payload=old.prepared[name].payload}) end
    end
   end
  end
  local corpses=bodiesFor(old)
  local removed=old.actor:getCurrentSquare()==nil or not containsActor(old.actor) or #corpses>0
  if removed and not serverRemoved then
   if stage=='await-death' then
    local corpses=bodiesFor(old)
    if #corpses==0 then return end
    serverRemoved=true;emit('native-removed',{ownerID=old.id,lifetime=old.binding.lifetime,oldActorDead=old.actor:isDead(),hasSquare=old.actor:getCurrentSquare()~=nil,
     onlineList=containsActor(old.actor),corpseCount=#corpses,corpseOnlineID=corpses[1]:getCharacterOnlineID(),nativeCorpse=true,
     nativeRemovalWitness='new-native-corpse',corpseX=corpses[1]:getX(),corpseY=corpses[1]:getY(),corpseZ=corpses[1]:getZ(),cachedX=old.x,cachedY=old.y,cachedZ=old.z})
   else
    serverRemoved=true;emit('native-removed',{ownerID=old.id,lifetime=old.binding.lifetime,hasSquare=old.actor:getCurrentSquare()~=nil,onlineList=containsActor(old.actor),reason='reconnect'})
   end
  end
  if stage=='await-death' and absenceSent and serverRemoved and hostRemoved and not respawnOffered then
   respawnOffered=true;emit('respawn-offer',{ownerID=old.id,lifetime=old.binding.lifetime,nativeCorpse=true})
   send(players.client2,'Respawn',{phase=phase,ownerID=old.id})
  end
 end
 local function startTransition()
  old=cache();stage=phase==1 and 'await-death' or 'await-reconnect';stageAt=now()
  absenceSent,serverRemoved,hostRemoved,respawnOffered=false,false,false,false
  emit('transition-start',{ownerID=old.id,cart=old.binding.cart,lifetime=old.binding.lifetime,reason=phase==1 and 'programmatic-native-kill' or 'native-menu-exit'})
  if phase==1 then
   old.deathStarted=now()
   emit('native-kill',{ownerID=old.id,cart=old.binding.cart,lifetime=old.binding.lifetime,programmaticNativeKill=true,authority='native-server',guarded=true,invoked=true})
   old.actor:setGodMod(false);old.actor:setGhostMode(false);old.actor:Kill(nil)
   assert(old.actor:isDead() and cartLeaseLifetime(old.actor)==nil,'Authoritative native Kill did not retire actor')
  end
  for name,p in pairs(players) do
   send(p,'Transition',{phase=phase,ownerID=old.id,reason=phase==1 and 'death' or 'reconnect',stale=prepared[name].reply,payload=prepared[name].payload})
  end
 end
 Events.OnServerStarted.Add(function()
  guarded(function() assert(cartMPPadHost(),'Lifecycle must use owned new Host');standard('setup',{cases={'lease_lifecycle'},expected=1});emit('setup',{nativeMenuHost=true});print('[QUEUE_TEST] SERVER_READY') end)
 end)
 Events.OnCharacterDeath.Add(function(p)
  if target and p==target then guarded(function() emit('native-death',{ownerID=p:getOnlineID(),lifetime=binding and binding.lifetime,nativeLifetimeAbsent=cartLeaseLifetime(p)==nil,eventSource='OnCharacterDeath',programmaticNativeKill=true}) end) end
 end)
 Events.OnClientCommand.Add(function(module,command,p,args)
  if module~=MODULE then return end
  guarded(function()
   local source=assert(cartLeaseSource(p),'Exact native lifecycle source missing')
   local name=p:getUsername();assert(name=='client1' or name=='client2','Foreign lifecycle source')
   assert(type(args)=='table','Lifecycle args missing')
   if not since then since=now();stageAt=since end
   assert(now()-since<DEADLINE,'Server lifecycle deadline')
   if command=='Hello' then
    if not p:getCurrentSquare() or p:isDead() then return end
    if name=='client1' then
     assert(not players.client1 or players.client1==p,'Host actor changed during guest lifecycle')
     players.client1=p;hello.client1=true
     if not origin then origin=require('CartMPPlacement')(p) end
    elseif phase==0 then players.client2=p;hello.client2=true
    elseif stage=='await-death' then
     progress();if not respawnOffered then return end
     assert(p~=old.actor,'Respawn Hello still names retired guest actor');setup(2,p);return
    elseif stage=='await-reconnect' then
     progress();assert(absenceSent and serverRemoved,'Reconnect arrived before native old actor absence')
     assert(p~=old.actor,'Reconnect Hello still names old guest actor');setup(3,p);return
    else
     assert(players.client2==p,'Unexpected guest actor during active phase');send(p,'Setup',spec);return
    end
    if phase==0 and all(hello) then setup(1,players.client2) end
    return
   end
   assert(players[name]==p,'Unknown native lifecycle requester')
   if command=='Pulse' then progress();return end
   assert(args.phase==phase,'Foreign lifecycle phase')
   if command=='Absent' then
    assert(name=='client1' and old and args.ownerID==old.id and stage=='await-death' or name=='client1' and old and args.ownerID==old.id and stage=='await-reconnect','Unexpected host absence evidence')
    assert(args.nativeLifetimeAbsent==true and args.removed==true and (phase==2 or args.corpseCount>=1),'Host native absence evidence incomplete')
    hostRemoved=true;emit('observer-absent',{ownerID=old.id,lifetime=old.binding.lifetime,requester=name,nativeLifetimeAbsent=true,removed=true,corpseCount=args.corpseCount,guarded=true});progress();return
   end
   if command=='FinalAck' then
    assert(stage=='final' and finalOffered and not finished[name],'Unexpected final ack');finished[name]=true
    emit('final-ack',{ownerID=target:getOnlineID(),requester=name,lifetime=args.lifetime,guarded=true})
    if all(finished) then
     stage='complete';emit('complete',{ownerID=target:getOnlineID(),cart=spec.cart,ok=true})
     standard('case',{id='lease_lifecycle',status='captured'});standard('complete',{expected=1,performed=1,passed=1,failed=0,skipped=0});print('[CART_LIFECYCLE] COMPLETE actor=server');broadcast('Complete',{phase=3,ownerID=target:getOnlineID()})
    end
    return
   end
   assert(stage=='binding','Lifecycle admission outside binding phase')
   assert(args.ownerID==target:getOnlineID() and cartLeaseTarget(args.ownerID)==target,'Wrong native current guest target')
   if command=='Bind' then
    assert(args.attempt==attempts[name]+1 and args.attempt<=LIMIT,'Unbounded or reordered lifecycle challenge');attempts[name]=args.attempt
   end
   local current=observe()
   if not current and command=='Bind' then send(p,'Wait',{phase=phase,ownerID=target:getOnlineID(),attempt=args.attempt});return end
   assert(current,'Authoritative native cart/equipment lost during accepted exchange')
   if command=='Bind' then
    local reply=assert(controller:reply(args.request,source),'Fresh lifecycle challenge missing')
    assert(reply.open and reply.actor==target:getOnlineID(),'Authoritative native lease closed')
    if old then
     staleServer('fresh-replay')
     local before=controller:snapshot(target:getOnlineID())
     assert(not controller:accept(target:getOnlineID(),source,p,old.prepared[name].payload,now()),'Old scalar payload accepted by new native incarnation')
     unchanged(before,controller:snapshot(target:getOnlineID()))
    end
    emit('bind',tuple({ownerID=target:getOnlineID(),requester=name,lifetime=current.lifetime,attempt=args.attempt,guarded=true},reply))
    send(p,'Bound',{phase=phase,ownerID=target:getOnlineID(),attempt=args.attempt,reply=reply,
     stale=old and old.prepared[name].reply or nil,payload=old and old.prepared[name].payload or nil})
   elseif command=='Echo' then
    assert(args.attempt==attempts[name],'Echo attempt differs')
    local accepted=controller:accept(target:getOnlineID(),source,p,args.payload,now())
    assert(accepted==(name=='client2'),'Native owner/observer source authority differs')
    token(args.lifetime);acks[name]={attempt=args.attempt,payload=args.payload,lifetime=current.lifetime,clientLifetime=args.lifetime}
    emit('echo',tuple({ownerID=target:getOnlineID(),requester=name,lifetime=current.lifetime,attempt=args.attempt,nonce=args.nonce,accepted=accepted,guarded=true},args.payload))
    send(p,'Receipt',{phase=phase,ownerID=target:getOnlineID(),attempt=args.attempt,nonce=args.nonce,accepted=accepted,payload=args.payload})
   elseif command=='Prepare' then
    assert(phase<3 and acks[name] and args.attempt==acks[name].attempt and not prepared[name],'Unbound/repeated pending lifecycle preparation')
    local reply=assert(controller:reply(args.request,source));assert(reply.open,'Pending native lease unavailable')
    local oldPayload={};for k,v in pairs(acks[name].payload) do oldPayload[k]=v end;oldPayload.seq=oldPayload.seq+100;oldPayload.body='retired-lifecycle-'..phase
    prepared[name]={reply=reply,payload=oldPayload,clientLifetime=acks[name].clientLifetime}
    emit('prepared',tuple({ownerID=target:getOnlineID(),requester=name,lifetime=current.lifetime,attempt=args.attempt,guarded=true},reply))
    if all(prepared) then startTransition() end
   elseif command=='Done' then
    assert(phase==3 and acks[name] and args.attempt==acks[name].attempt and not done[name],'Unexpected final lifecycle proof');done[name]=true
    if all(done) then stage='final';finalOffered=true;emit('complete-offer',{ownerID=target:getOnlineID(),cart=spec.cart});broadcast('Final',{phase=3,ownerID=target:getOnlineID()}) end
   else error('Unknown lifecycle request '..tostring(command)) end
  end)
 end)
 Events.OnTick.Add(function()
  if since and stage~='complete' then guarded(function() assert(now()-since<DEADLINE and now()-stageAt<120000,'Lifecycle server stage deadline: '..stage) end) end
 end)
 return M
end
local account=assert(read('smoke-user.txt'),'Owned native user scalar missing')
assert(account=='client1' or account=='client2','Foreign lifecycle profile');role=account
local resuming=read(REJOIN)=='pending'
assert(not resuming or role=='client2','Host cannot rejoin')
local started,done,since=false,false,nil
local spec,owner,receiver,current,old,inflight=nil,nil,nil,nil,nil,nil
local ready,ack,preparing,transition,respawnAllowed=false,false,false,nil,false
local attempts,lastHello,lastPulse,lastEquip=0,0,0,0
local nextBindAt,rejoinCreationAdvanced=0,false
local corpseKnown,absentSent,deathLogged=false,false,false
local exitAt,exitStage,rejoining=nil,nil,false
local phaseBeforeReset=resuming and 2 or nil
local function send(command,args)
 args=args or {};args.phase=phase;args.ownerID=spec and spec.ownerID or old and old.id or -1
 sendClientCommand(getPlayer(),MODULE,command,args)
end
local function invalidate(reason)
 if receiver then receiver:unavailable() end
 emit('unavailable',{ownerID=old and old.id or spec and spec.ownerID,lifetime=old and old.binding.lifetime or current and current.lifetime,
  nativeLifetimeAbsent=old and cartLeaseLifetime(old.actor)==nil or false,reason=reason})
end
local function replay(event,reply,payload,ingress,extra)
 assert(receiver and type(reply)=='table' and type(payload)=='table','Retired lifecycle replay missing')
 local before=receiver:snapshot()
 assert(not receiver:reply(reply,ingress),'Retired prepared reply accepted');unchanged(before,receiver:snapshot())
 assert(not receiver:receive(payload,now()),'Retired lifecycle payload accepted');unchanged(before,receiver:snapshot())
 local row=extra or {};row.ownerID=spec and spec.ownerID or old and old.id;row.lifetime=current and current.lifetime or old and old.binding.lifetime
 row.staleReplyAccepted=false;row.stalePayloadAccepted=false;row.staleNonce=reply.nonce;row.guarded=ingress~=nil
 emit(event,tuple(row,payload))
end
local function cache()
 return {actor=owner,connection=assert(cartLeaseCurrent()),id=spec.ownerID,binding=current,x=owner:getX(),y=owner:getY(),z=owner:getZ(),corpses=corpseBaseline(owner)}
end
local function refresh()
 if not spec then return nil end
 local p=playerNamed('client2');if not p or p:getOnlineID()~=spec.ownerID then return nil end
 local b=held(p,spec.cart);if not b or b.cargoID~=spec.cargoID then return nil end
 if not receiver then
  owner=p;receiver=P.receiver(spec.ownerID,assert(cartLeaseChallengeSeed())..':lc');current=b
  assert(receiver:native(assert(cartLeaseCurrent()),p,b),'First native binding did not invalidate')
  local previous=old and old.binding.lifetime or spec.previousLifetime
  if previous then emit('transition',transitionEvidence(previous,b.lifetime,phase,{ownerID=spec.ownerID,oldOwnerID=old and old.id,cart=b.cart,newNativeActor=old and p~=old.actor or nil,checkpointRestored=old==nil})) end
  emit('native-binding',{ownerID=spec.ownerID,cart=b.cart,lifetime=b.lifetime,cargoID=b.cargoID,cargoWeight=b.cargoWeight,localOwner=role=='client2'})
 elseif b.lifetime~=current.lifetime then
  assert(p==owner and b.cart==current.cart and b.item~=current.item and cartLeaseResnapshot(p,current.lifetime)==true,'Uncertified equipment transition in live lifecycle phase')
  b.resnapshotOf=current.lifetime
  assert(receiver:native(assert(cartLeaseCurrent()),p,b),'Certified remote equipment resnapshot refused')
  emit('resnapshot',{ownerID=spec.ownerID,cart=b.cart,before=current.lifetime,after=b.lifetime,nativeCertified=true})
  current=b;ack=false
 else
  assert(p==owner and b.item==current.item,'Native actor/item changed without lifetime transition')
  receiver:native(assert(cartLeaseCurrent()),p,b)
 end
 return b
end
local function fresh()
 attempts=attempts+1;assert(attempts<=LIMIT,'Lifecycle native challenge attempt bound exceeded')
 local request=assert(receiver:challenge(),'Native lifecycle challenge missing');inflight={request=request,attempt=attempts,lifetime=current.lifetime}
 emit('request',{ownerID=spec.ownerID,cart=current.cart,lifetime=current.lifetime,attempt=attempts,nonce=request.nonce})
 send('Bind',{request=request,attempt=attempts})
end
local function bindTick()
 if not spec or transition or done then return end
 local b=refresh();if not b then return end
 if not inflight and not ack and now()>=nextBindAt then fresh() end
 if not ack or inflight or preparing or now()-ack.wall<500 then return end
 if phase<3 then
  preparing=true;old=cache();local request=assert(receiver:challenge());send('Prepare',{request=request,attempt=ack.attempt})
  emit('prepare',{ownerID=spec.ownerID,cart=current.cart,lifetime=current.lifetime,attempt=ack.attempt,nonce=request.nonce})
 elseif not ready then ready=true;send('Done',{attempt=ack.attempt});emit('done',{ownerID=spec.ownerID,cart=current.cart,lifetime=current.lifetime}) end
end
local function initialized()
 local p=getPlayer();if not p or p:isDead() or not p:getCurrentSquare() or p:getUsername()~=role or p:getOnlineID()<0 or not cartLeaseCurrent() then return false end
 if not since then since=now() end
 if read(SETUP)~='logged' then
  write(SETUP,'logged');standard('setup',{cases={'lease_lifecycle'},expected=1});emit('setup',{ownerID=p:getOnlineID(),nativeMenuHost=true})
 end
 p:setGodMod(true);p:setGhostMode(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
 return true
end
local function absentTick()
 if not old or not transition then return end
 deathProgress(old)
 if cartLeaseLifetime(old.actor)~=nil then return end
 if receiver then receiver:unavailable() end
 local corpses=bodiesFor(old)
 local removed=old.actor:getCurrentSquare()==nil or not containsActor(old.actor) or #corpses>0
 if removed and not corpseKnown and (transition=='reconnect' or #corpses>=1) then
  corpseKnown=true
  local row=disposition(old);row.reason=transition;row.nativeCorpse=#corpses>=1;row.nativeRemovalWitness=#corpses>=1 and 'new-native-corpse' or 'native-square-or-list-absence'
  emit('native-removed',row);emit('cart-disposition',row)
 end
 if role=='client1' and corpseKnown and not absentSent then
  absentSent=true;send('Absent',{nativeLifetimeAbsent=true,removed=true,corpseCount=#corpses})
 end
end
Events.OnCharacterDeath.Add(function(p)
 if p and (p==owner or old and p==old.actor) then
  guarded(function()
   local row={ownerID=p:getOnlineID(),lifetime=old and old.binding.lifetime or current and current.lifetime,nativeLifetimeAbsent=cartLeaseLifetime(p)==nil,eventSource='OnCharacterDeath',programmaticNativeKill=true}
   emit('native-death',row);deathLogged=true
   if receiver then receiver:unavailable() end
  end)
 end
end)
Events.OnPlayerDeath.Add(function(p)
 if p and p:getUsername()==role then guarded(function() emit('native-player-death',{ownerID=p:getOnlineID(),nativeLifetimeAbsent=cartLeaseLifetime(p)==nil,eventSource='OnPlayerDeath'}) end) end
end)
Events.OnCreatePlayer.Add(function(index,p)
 if p and p:getUsername()==role then
  guarded(function()
   emit('native-create',{ownerID=p:getOnlineID(),index=index,eventSource='OnCreatePlayer',newNativeActor=old and p~=old.actor or nil,rejoinPending=resuming})
   started=true;lastHello=0
  end)
 end
end)
Events.OnGameStart.Add(function()
 started=true;since=now();lastHello=0
 if resuming then emit('native-rejoin',{ownerID=getPlayer() and getPlayer():getOnlineID(),nativeConnected=true,checkpoint='pending',phase=3}) end
end)
Events.OnServerCommand.Add(function(module,command,args)
 if module~=MODULE then return end
 guarded(function()
  local ingress=assert(cartLeaseIngress(),'Exact native lifecycle ingress missing')
  assert(type(args)=='table','Missing native lifecycle response')
  if command=='Setup' then
   if spec and args.phase==phase and spec.ownerID==args.ownerID then return end
   assert(args.phase==phase+1 or resuming and args.phase==3 and phase==0,'Unexpected native lifecycle setup phase')
   if phase>0 then assert(transition,'New native phase without lifecycle transition') end
   if old then assert(args.ownerID~=nil,'Native replacement ID missing') end
   phase=args.phase;spec=args;owner=nil;receiver=nil;current=nil;inflight=nil;ack=false;preparing=false;transition=nil;ready=false;attempts=0
   corpseKnown,absentSent=false,false;respawnAllowed=false;lastEquip=0
   emit('phase-setup',{ownerID=spec.ownerID,cart=spec.cart,cargoID=spec.cargoID,reusedNativeCart=spec.reusedNativeCart})
   return
  end
  if command=='ProbeAbsent' and (not spec or args.phase<phase) then
   emit('stale-control',{response=command,responsePhase=args.phase,accepted=false,guarded=true});return
  end
  assert(spec and args.phase==phase and args.ownerID==spec.ownerID,'Unexpected native lifecycle response incarnation')
  if command=='Wait' then
   assert(inflight and args.attempt==inflight.attempt,'Unrequested native lifecycle wait');inflight=nil;nextBindAt=now()+500
   emit('bind-wait',{ownerID=spec.ownerID,attempt=args.attempt,serverEquipmentPending=true});return
  elseif command=='Bound' then
   local b=refresh();assert(b and inflight and args.attempt==inflight.attempt and args.reply.nonce==inflight.request.nonce,'Unrequested native lifecycle grant')
   if args.stale then replay('fresh-nonce-replay',args.stale,args.payload,ingress,{freshNonce=inflight.request.nonce}) end
   local accepted=receiver:reply(args.reply,ingress)
   if not accepted then
    assert(inflight.lifetime~=current.lifetime,'Fresh exact native lifecycle grant refused')
    emit('reply-refused',{ownerID=spec.ownerID,before=inflight.lifetime,after=current.lifetime,attempt=inflight.attempt,accepted=false});inflight=nil;return
   end
   assert(inflight.lifetime==current.lifetime,'Grant admitted after native request incarnation changed')
   local e={session=args.reply.session,grant=args.reply.grant,lease=args.reply.lease,seq=receiver:snapshot().seq+1,op='UPDATE',mode='motion',cart=current.cart,body='lifecycle-'..phase..'-'..attempts}
   assert(receiver:receive(e,now()),'Fresh native receiver payload refused');inflight.payload=e
   emit('bound',tuple({ownerID=spec.ownerID,lifetime=current.lifetime,nonce=args.reply.nonce,attempt=inflight.attempt,guarded=true},e))
   send('Echo',{attempt=inflight.attempt,nonce=inflight.request.nonce,payload=e,lifetime=current.lifetime})
  elseif command=='Receipt' then
   assert(inflight and inflight.payload and args.attempt==inflight.attempt and args.nonce==inflight.request.nonce and args.accepted==(role=='client2'),'Lifecycle exact echo receipt differs')
   for _,k in ipairs({'session','grant','lease','seq','cart','body'}) do assert(args.payload[k]==inflight.payload[k],'Native echo receipt changed '..k) end
   refresh()
   if current.lifetime~=inflight.lifetime then
    assert(owner and cartLeaseResnapshot(owner,inflight.lifetime)==true,'Uncertified native lifetime changed before exact echo settled')
    emit('receipt-resnapshot',tuple({ownerID=spec.ownerID,nonce=args.nonce,attempt=inflight.attempt,accepted=args.accepted,
     before=inflight.lifetime,after=current.lifetime,nativeCertified=true,guarded=true,freshNativeProof=false},args.payload))
    inflight=nil;ack=false;nextBindAt=now()+500;return
   end
   ack={wall=now(),attempt=inflight.attempt};emit('receipt',tuple({ownerID=spec.ownerID,lifetime=current.lifetime,nonce=args.nonce,attempt=inflight.attempt,accepted=args.accepted,guarded=true},args.payload));inflight=nil
   if args.phase>1 and old and old.reply then replay('fresh-replay',old.reply,old.payload,ingress,{freshBound=true}) end
  elseif command=='Transition' then
   assert(phase<3 and preparing and ack and not transition,'Unexpected lifecycle transition request')
   assert(old and old.id==spec.ownerID and old.actor==owner,'Prepared original native actor cache missing');old.reply=args.stale;old.payload=args.payload
   transition=args.reason;assert(transition==(phase==1 and 'death' or 'reconnect'),'Unexpected lifecycle transition kind')
   emit('transition-start',{ownerID=old.id,cart=old.binding.cart,lifetime=old.binding.lifetime,reason=transition})
   if transition=='death' then old.deathStarted=now() end
   if role=='client2' then
    if transition=='death' then
     local alreadyDead=old.actor:isDead()
     emit('native-kill',{ownerID=old.id,cart=old.binding.cart,lifetime=old.binding.lifetime,programmaticNativeKill=true,authority='native-client',alreadyDead=alreadyDead,invoked=not alreadyDead})
     old.actor:setGodMod(false);old.actor:setGhostMode(false)
     if not alreadyDead then old.actor:Kill(nil) end
     assert(old.actor:isDead() and cartLeaseLifetime(old.actor)==nil,'Native Kill did not retire actor immediately')
     receiver:unavailable();replay('unavailable-replay',old.reply,old.payload,ingress,{nativeLifetimeAbsent=true,nativeDeath=true})
    else
     exitAt=now();exitStage='pause'
    end
   end
  elseif command=='ProbeAbsent' then
   assert(old and transition,'Authoritative absence arrived outside cached native transition')
   local nativeAbsent=cartLeaseLifetime(old.actor)==nil
   receiver:unavailable();replay('unavailable-replay',args.stale,args.payload,ingress,{nativeLifetimeAbsent=nativeAbsent,authoritativeAbsence=true,cachedActor=true})
  elseif command=='Respawn' then
   assert(role=='client2' and phase==1 and transition=='death','Unexpected native respawn offer');respawnAllowed=true
   emit('respawn-offer',{ownerID=old.id,lifetime=old.binding.lifetime})
  elseif command=='Final' then
   assert(phase==3 and ready and ack and refresh(),'Unsettled lifecycle final native state')
   emit('final-ack',{ownerID=spec.ownerID,cart=current.cart,lifetime=current.lifetime,guarded=true});send('FinalAck',{lifetime=current.lifetime})
  elseif command=='Complete' then
   assert(phase==3 and ready and ack,'Early native lifecycle completion');done=true
   if role=='client2' then write(REJOIN,'verified') end
   emit('complete',{ownerID=spec.ownerID,cart=current.cart,lifetime=current.lifetime,ok=true})
   standard('case',{id='lease_lifecycle',status='captured'});standard('complete',{expected=1,performed=1,passed=1,failed=0,skipped=0});print('[CART_LIFECYCLE] COMPLETE actor='..role)
  else error('Unknown lifecycle response '..tostring(command)) end
 end)
end)
local function respawnTick()
 if role~='client2' or not respawnAllowed or transition~='death' then return end
 local creation=CoopCharacterCreation and CoopCharacterCreation.instance
 if creation then
  local spawn=creation.mapSpawnSelect
  if spawn and spawn:isVisible() then assert(type(spawn.clickNext)=='function','Native Coop spawn Next missing');spawn:clickNext();emit('respawn-ui',{panel='spawn',nativeCallback=true});return end
  local profession=creation.charCreationProfession
  if profession and profession:isVisible() then
   assert(profession.playButton and profession.playButton.internal=='NEXT','Native profession Next missing')
   profession:onOptionMouseDown(profession.playButton,0,0);emit('respawn-ui',{panel='profession',nativeCallback=true});return
  end
  local main=creation.charCreationMain
  if main and main:isVisible() then
   assert(main.playButton and main.playButton.internal=='NEXT','Native character Next missing')
   main:onOptionMouseDown(main.playButton,0,0);emit('respawn-ui',{panel='character',nativeCallback=true});return
  end
  return
 end
 local p=getPlayer()
 if p and p~=old.actor and not p:isDead() then return end
 local panel=ISPostDeathUI and ISPostDeathUI.instance and ISPostDeathUI.instance[0]
 if not panel or not panel:isVisible() or panel.waitOver~=true or not panel.buttonRespawn or not panel.buttonRespawn:isVisible() then return end
 if not corpseKnown or not deathLogged then return end
 panel:onRespawn();emit('respawn-ui',{panel='post-death',nativeCallback=true,ownerID=old.id})
end
local function exitTick()
 if not exitAt or done then return end
 assert(now()-exitAt<30000,'Native pause Exit lifecycle timeout')
 local menu=assert(MainScreen and MainScreen.instance,'Native pause menu missing')
 assert(isIngameState() and menu.inGame==true,'Lifecycle pause Exit outside game')
 if exitStage=='pause' then
  if not menu:isVisible() then
   local key=getCore():getKey(KeybindId.MAIN_MENU);if key==0 then key=Keyboard.KEY_ESCAPE end
   ToggleEscapeMenu(key)
  end
  exitStage='exit';return
 end
 if not menu:isVisible() or isQuitCooldown and isQuitCooldown() then return end
 local option=assert(menu.exitOption,'Native pause Exit option missing')
 assert(option.internal=='EXIT' and type(option.onMouseDown)=='function','Native pause Exit callback missing')
 write(REJOIN,'pending');emit('native-exit',{ownerID=old.id,lifetime=old.binding.lifetime,nativeExitToMenu=true})
 started=false;resuming=true;rejoining=false;exitAt=nil;exitStage=nil
 option.onMouseDown(option,0,0)
end
local function connectAgain()
 if not resuming or rejoining or done or isIngameState() then return end
 local menu=MainScreen and MainScreen.instance
 if not menu or menu.inGame~=false or not menu:isVisible() or not ConnectToServer or not ConnectToServer.instance then return end
 if read(REJOIN)~='pending' then return end
 if old and receiver then
  assert(cartLeaseCurrent()==nil,'Native main menu retained owned current transport')
  receiver:unavailable();replay('unavailable-replay',old.reply,old.payload,nil,{nativeLifetimeAbsent=cartLeaseLifetime(old.actor)==nil,nativeMenu=true,nilIngress=true})
 end
 rejoining=true;started=false;spec=nil;owner=nil;receiver=nil;current=nil;inflight=nil;phase=0;ack=false;preparing=false;transition=nil;lastHello=0;lastPulse=0
 emit('native-reconnect',{phase=3,nativeConnectToServer=true,checkpoint='pending'})
 ConnectToServer.instance:connect(menu,'Cart lifecycle rejoin','client2','smoke-local-only','127.0.0.1','',tostring(C.port),'',false,true,1)
end
local function rejoinCreationTick()
 if not resuming or not rejoining or rejoinCreationAdvanced or isIngameState() then return end
 local menu=MainScreen and MainScreen.instance
 if not menu or not menu.charCreationProfession or not MapSpawnSelect then return end
 if menu.charCreationProfession:isVisible() or MapSpawnSelect.instance and MapSpawnSelect.instance:isVisible() then
  rejoinCreationAdvanced=true
  if MapSpawnSelect.instance then MapSpawnSelect.instance:useDefaultSpawnRegion();MapSpawnSelect.instance:setVisible(false) end
  menu.charCreationProfession:onOptionMouseDown({internal='NEXT'})
  menu.charCreationMain:onOptionMouseDown({internal='NEXT'})
  emit('rejoin-ui',{phase=3,nativeCallback=true})
 end
end
Events.OnMainMenuEnter.Add(function() guarded(connectAgain) end)
Events.OnPreUIDraw.Add(function() guarded(function() connectAgain();rejoinCreationTick();if isIngameState() then respawnTick() end end) end)
Events.OnTickEvenPaused.Add(function() guarded(function() exitTick();if isIngameState() then respawnTick() end end) end)
Events.OnTick.Add(function()
 if done or failed then return end
 guarded(function()
  if since then assert(now()-since<DEADLINE,'Lifecycle client deadline phase='..tostring(phase)..' transition='..tostring(transition)) end
  if not isIngameState() then return end
  absentTick()
  if not initialized() then return end
  local p=getPlayer()
  if spec and (role=='client1' or not transition or p==owner) and now()-lastPulse>250 then lastPulse=now();send('Pulse',{}) end
  if not spec or transition=='death' and p~=old.actor then
   if now()-lastHello>1000 then lastHello=now();send('Hello',{rejoin=resuming,afterDeath=transition=='death'}) end
   return
  end
  if role=='client2' and not transition and not ack and now()-lastEquip>1000 then
   lastEquip=now();local cart=p:getInventory():getItemById(spec.cart)
   if cart then
    assert(cart:getFullType()==CART,'Replicated exact native cart changed type')
    if p:getPrimaryHandItem()~=cart or p:getSecondaryHandItem()~=cart then p:setPrimaryHandItem(cart);p:setSecondaryHandItem(cart) end
    if SaucedCarts then SaucedCarts.applyCartPose(p);SaucedCarts.updateCartVisual(cart,p,true) end
    p:updateHandEquips()
   end
  end
  bindTick()
 end)
end)
return M
