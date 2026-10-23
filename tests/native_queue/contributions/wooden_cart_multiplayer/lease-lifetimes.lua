-- Explicit native setter boundary bank. No production admission or playback is enabled.
local config=require 'QueueTestSelection'
assert(config.disposable==true and config.options.cart_lease_control==true and config.options.cart_lease_lifetimes==true,'Owned equipment lifetime bank required')
local P=require 'CartLeaseProtocol'
local J=require 'CartMPJSON'
local M={}
local module='CartLeaseLifetimes'
local phases={'baseline','release-reacquire','same-id-replacement'}
local MAX_ATTEMPTS,QUIET_MS=8,250
local function log(row)
 row.wall=getTimestampMs();print('[CART_LEASE_LIFETIME] '..J.encode(row))
 if row.event=='error' then print('[CART_LEASE_LIFETIME] ERROR '..tostring(row.reason)) end
end
local function held(p)
 local item=assert(p and p:getPrimaryHandItem(),'Native primary cart missing')
 assert(p:getSecondaryHandItem()==item and not item:getWorldItem(),'Exact native held cart required')
 local kind=item:getFullType()
 assert(kind=='SaucedWheelbarrow.WheelbarrowWood' or kind=='SaucedWheelbarrow.WheelbarrowMetal' or kind=='SaucedCarts.ShoppingCart','Supported native cart required')
 return {mode='motion',cart=item:getID(),item=item,lifetime=assert(cartLeaseLifetime(p),'Native equipment lifetime unavailable')}
end
local function cargo(item)
 local items=item:getInventory():getItems();assert(items:size()==1,'Fixture cargo count changed')
 local v=items:get(0);return v,v:getID(),v:getActualWeight()
end
local function cycle(p,index,actor)
 assert(index==2 or index==3,'Unexpected mutation phase')
 local before=held(p);local c,cid,weight=cargo(before.item)
 local row={actor=actor,event='cycle',phase=index,name=phases[index],owner=p:getOnlineID(),cart=before.cart,before=before.lifetime,cargoID=cid,cargoWeight=weight}
 if index==2 then
  p:setPrimaryHandItem(nil);p:setSecondaryHandItem(nil)
  assert(not cartLeaseLifetime(p),'Released native hands retained a lifetime')
 else
  local replacement=assert(instanceItem(before.item:getFullType()),'Native replacement construction failed')
  assert(replacement~=before.item,'Replacement aliases original item');replacement:setID(before.cart)
  p:setPrimaryHandItem(replacement);p:setSecondaryHandItem(replacement)
  assert(p:getPrimaryHandItem()==replacement and p:getSecondaryHandItem()==replacement and replacement:getID()==before.cart,'Same-ID native replacement failed')
 end
 p:setPrimaryHandItem(before.item);p:setSecondaryHandItem(before.item)
 local after=held(p);local final,finalID,finalWeight=cargo(after.item)
 assert(after.item==before.item and after.cart==before.cart and final==c and finalID==cid and finalWeight==weight,'Fixture cart/cargo restoration failed')
 assert(after.lifetime~=before.lifetime,'Native mutation cycle was missed')
 row.after=after.lifetime;row.sameItem=true;return row,after
end
local protected={'session','grant','lease','seq','open','visible','body','received','terminal','rebind','acceptedAt'}
local function unchanged(before,after)
 for _,k in ipairs(protected) do assert(before[k]==after[k],'Rejection changed '..k) end
end
local function tuple(row,b)
 row.session=b.session;row.grant=b.grant;row.lease=b.lease;row.cart=b.cart;return row
end
if isServer() then
 local controller=P.server(assert(cartLeaseSeed())..':equipment',{limit=4})
 local clients,ready,prepared,done,finished,firstBind,attempts,lastEcho={},{},{},{},{},{},{},{}
 local target,phase,offered=nil,0,false
 local function observe()
  local connection=assert(cartLeaseOwnerConnection(target),'Current native owner connection missing')
  local binding=held(target)
  assert(controller:observe(target:getOnlineID(),connection,target,binding),'Authoritative lifetime observation refused')
  return binding
 end
 local function send(p,command,args) sendServerCommand(p,module,command,args) end
 local function all(rows) return rows.client1 and rows.client2 end
 local function advance()
  phase=phase+1
  if phase==1 then
   log({actor='server',event='begin',phase=phase,owner=target:getOnlineID()})
   for _,p in pairs(clients) do send(p,'Begin',{phase=phase,owner=target:getOnlineID()}) end
  else
   local row=cycle(target,phase,'server');observe();log(row)
   for role,p in pairs(clients) do
    local pending=assert(prepared[role],'Missing pre-mutation pending challenge')
    send(p,'Cycle',{phase=phase,owner=target:getOnlineID(),stale=pending.reply})
   end
   prepared={}
  end
 end
 Events.OnClientCommand.Add(function(mod,command,p,args)
  if mod~=module then return end
  local ok,err=pcall(function()
   local source=assert(cartLeaseSource(p),'Exact native request source missing')
   local role=p:getUsername();assert(role=='client1' or role=='client2','Owned requester required')
   assert(type(args)=='table','Command arguments missing')
   local native=assert(cartLeaseTarget(args.owner),'Registered owner missing')
   assert(native:getUsername()=='client1' and (not target or target==native),'Native target replaced during setter bank')
   target=native;local id=target:getOnlineID()
   if command=='Ready' then
    assert(phase==0 and not ready[role],'Repeated/out-of-phase ready')
    clients[role]=p;ready[role]=true
    log({actor='server',event='ready',requester=role,phase=0,owner=id,lifetime=held(target).lifetime,guarded=true})
    if all(ready) then advance() end;return
   end
   assert(clients[role]==p and args.phase==phase and phase>=1 and phase<=3 and not finished[role],'Unknown requester or phase')
   local binding=observe()
   if command=='Bind' then
    assert(type(args.attempt)=='number' and args.attempt==math.floor(args.attempt) and args.attempt==(attempts[role] or 0)+1 and args.attempt<=MAX_ATTEMPTS,'Unbounded/reordered bind attempt')
    attempts[role]=args.attempt
    local key=phase..':'..role
    if not firstBind[key] then
     firstBind[key]=true
     if phase>1 then
      local before=controller:snapshot(id)
      assert(not controller:accept(id,source,p,args.old,getTimestampMs()),'Retired source payload accepted')
      unchanged(before,controller:snapshot(id))
      log(tuple({actor='server',event='stale',requester=role,phase=phase,owner=id,attempt=args.attempt,accepted=false,guarded=true},args.old))
     end
    else assert(args.old==nil,'Repeated stale probe') end
    local reply=assert(controller:reply(args.request,source),'Fresh challenge reply missing')
    assert(reply.open and reply.actor==id,'Fresh native lease closed')
    log(tuple({actor='server',event='bind',requester=role,phase=phase,owner=id,attempt=args.attempt,nonce=reply.nonce,lifetime=binding.lifetime,guarded=true},reply))
    send(p,'Bound',{phase=phase,owner=id,attempt=args.attempt,reply=reply})
   elseif command=='Echo' then
    assert(args.attempt==attempts[role] and (not lastEcho[role] or lastEcho[role].attempt<args.attempt),'Repeated/foreign echo attempt')
    local accepted=controller:accept(id,source,p,args.envelope,getTimestampMs())
    assert(accepted==(role=='client1'),'Exact native source authority differs')
    lastEcho[role]={attempt=args.attempt,nonce=args.nonce}
    log(tuple({actor='server',event='echo',requester=role,phase=phase,owner=id,attempt=args.attempt,nonce=args.nonce,accepted=accepted,seq=args.envelope.seq,guarded=true},args.envelope))
    send(p,'Receipt',{phase=phase,owner=id,attempt=args.attempt,nonce=args.nonce,accepted=accepted,envelope=args.envelope})
   elseif command=='Prepare' then
    assert(phase<3 and not prepared[role] and lastEcho[role] and args.afterAttempt==lastEcho[role].attempt,'Repeated/late/unbound preparation')
    local reply=assert(controller:reply(args.request,source),'Pending challenge reply missing')
    assert(reply.actor==id and reply.open,'Pre-mutation source lease missing');prepared[role]={reply=reply}
    log(tuple({actor='server',event='prepare',requester=role,phase=phase,owner=id,afterAttempt=args.afterAttempt,nonce=reply.nonce,lifetime=binding.lifetime,guarded=true},reply))
    if all(prepared) then advance() end
   elseif command=='Done' then
    assert(phase==3 and not done[role] and lastEcho[role] and args.afterAttempt==lastEcho[role].attempt,'Repeated/early completion')
    done[role]=true
    log({actor='server',event='done',requester=role,phase=phase,owner=id,afterAttempt=args.afterAttempt,guarded=true})
    if all(done) then
     offered=true;log({actor='server',event='complete-offer',phase=3,owner=id})
     for _,v in pairs(clients) do send(v,'Complete',{phase=3,owner=id}) end
    end
   elseif command=='Finished' then
    assert(phase==3 and offered and done[role] and not finished[role] and lastEcho[role] and args.afterAttempt==lastEcho[role].attempt,'Unsettled final native snapshot')
    finished[role]=true
    log({actor='server',event='finished',requester=role,phase=3,owner=id,afterAttempt=args.afterAttempt,lifetime=args.lifetime,guarded=true})
    if all(finished) then log({actor='server',event='complete',phase=3,owner=id}) end
   else error('Unexpected lifetime request') end
  end)
  if not ok then log({actor='server',event='error',reason=tostring(err)}) end
 end)
 return M
end
local reader=assert(getFileReader('smoke-user.txt',false));local user=reader:readLine();reader:close()
local receiver,ownerID,phase,since,current,lastChange=nil,nil,0,nil,nil,nil
local ready,done,preparing,doneSent,offered=false,false,false,false,false
local inflight,pendingPrepared,oldEnvelope,ackLifetime,ackAttempt=nil,nil,nil,nil,nil
local attempts,firstPhaseAttempt,snapshots=0,true,0
local function owner()
 local players=getOnlinePlayers()
 for i=0,players:size()-1 do local p=players:get(i);if p:getUsername()=='client1' then return p end end
 error('Native owner missing')
end
local function send(command,args) args.owner=ownerID;args.phase=phase;sendClientCommand(getPlayer(),module,command,args) end
local function refresh(native)
 local next=held(native)
 if current and next.lifetime~=current.lifetime then
  assert(next.cart==current.cart and next.item~=current.item and cartLeaseResnapshot(native,current.lifetime)==true,'Uncertified native equipment gap')
  local _,cid,weight=cargo(current.item);local _,nextID,nextWeight=cargo(next.item)
  assert(cid==nextID and weight==nextWeight,'Certified resnapshot changed fixture cargo')
  snapshots=snapshots+1;assert(snapshots<=16,'Equipment resnapshot observation limit')
  next.resnapshotOf=current.lifetime
  assert(receiver:native(assert(cartLeaseCurrent()),native,next),'Certified native resnapshot did not invalidate receiver')
  log({actor=user,event='resnapshot',phase=phase,owner=ownerID,before=current.lifetime,after=next.lifetime,cart=next.cart,cargoID=cid,cargoWeight=weight,nativeCertified=true})
  current=next;lastChange=getTimestampMs()
 elseif current then
  assert(next.item==current.item,'Unobserved exact native item replacement')
  receiver:native(assert(cartLeaseCurrent()),native,next)
 end
 return next
end
local function fresh(native)
 assert(not inflight and not preparing and phase>=1,'Overlapping lifetime bind')
 attempts=attempts+1;assert(attempts<=MAX_ATTEMPTS,'Equipment resync attempt limit')
 local request=assert(receiver:challenge(),'Bounded fresh challenge missing')
 inflight={request=request,attempt=attempts,lifetime=current.lifetime}
 log({actor=user,event='request',phase=phase,owner=ownerID,attempt=attempts,nonce=request.nonce,lifetime=current.lifetime})
 send('Bind',{request=request,attempt=attempts,old=firstPhaseAttempt and oldEnvelope or nil});firstPhaseAttempt=false
end
local function drive(native)
 if done or phase==0 or preparing or inflight then return end
 local snapshot=receiver:snapshot()
 if not snapshot.open or ackLifetime~=current.lifetime then fresh(native);return end
 if getTimestampMs()-lastChange<QUIET_MS then return end
 if phase<3 then
  pendingPrepared=assert(receiver:challenge(),'Pending pre-mutation challenge missing');preparing=true
  log({actor=user,event='prepare',phase=phase,owner=ownerID,afterAttempt=ackAttempt,nonce=pendingPrepared.nonce,lifetime=current.lifetime})
  send('Prepare',{request=pendingPrepared,afterAttempt=ackAttempt})
 elseif not doneSent then
  doneSent=true;log({actor=user,event='done',phase=3,owner=ownerID,afterAttempt=ackAttempt});send('Done',{afterAttempt=ackAttempt})
 elseif offered then
  done=true;log({actor=user,event='complete',phase=3,owner=ownerID,afterAttempt=ackAttempt,lifetime=current.lifetime})
  send('Finished',{afterAttempt=ackAttempt,lifetime=current.lifetime})
 end
end
Events.OnServerCommand.Add(function(mod,command,args)
 if mod~=module then return end
 local ok,err=pcall(function()
  local ingress=assert(cartLeaseIngress(),'Exact native reply ingress missing')
  local native=owner();assert(receiver and native:getOnlineID()==ownerID and args.owner==ownerID,'Unexpected owner incarnation')
  refresh(native)
  if command=='Begin' then
   assert(phase==0 and args.phase==1,'Unexpected baseline begin');phase=1
   log({actor=user,event='begin',phase=phase,owner=ownerID})
  elseif command=='Cycle' then
   assert(args.phase==phase+1 and phase>=1 and phase<=2 and preparing,'Unexpected mutation stage')
   assert(pendingPrepared and args.stale.nonce==pendingPrepared.nonce,'Pending challenge replaced')
   phase=args.phase;local row,after=cycle(native,phase,user)
   receiver:native(assert(cartLeaseCurrent()),native,after);current=after;lastChange=getTimestampMs();ackLifetime=nil
   local before=receiver:snapshot()
   assert(not receiver:reply(args.stale,ingress),'Retired pending challenge reply accepted');unchanged(before,receiver:snapshot())
   assert(not receiver:receive(oldEnvelope,getTimestampMs()),'Retired receiver payload accepted');unchanged(before,receiver:snapshot())
   row.staleReplyAccepted=false;row.stalePayloadAccepted=false;row.staleNonce=args.stale.nonce
   log(row);preparing=false;pendingPrepared=nil;firstPhaseAttempt=true
  elseif command=='Bound' then
   assert(args.phase==phase and inflight and args.attempt==inflight.attempt and args.reply.nonce==inflight.request.nonce,'Unrequested grant')
   local accepted=receiver:reply(args.reply,ingress)
   if not accepted then
    assert(inflight.lifetime~=current.lifetime,'Fresh exact lifetime bind rejected without certified race')
    log(tuple({actor=user,event='reply-refused',phase=phase,owner=ownerID,attempt=inflight.attempt,nonce=inflight.request.nonce,before=inflight.lifetime,after=current.lifetime,accepted=false,guarded=true},args.reply))
    inflight=nil
   else
    assert(inflight.lifetime==current.lifetime,'Stale native request admitted after resnapshot')
    local snapshot=receiver:snapshot()
    local e={session=args.reply.session,grant=args.reply.grant,lease=args.reply.lease,seq=snapshot.seq+1,op='UPDATE',mode='motion',cart=current.cart,body='fixture-lifetime-'..phase..'-'..inflight.attempt}
    assert(receiver:receive(e,getTimestampMs()),'Fresh receiver state refused');inflight.envelope=e
    log(tuple({actor=user,event='bound',phase=phase,owner=ownerID,attempt=inflight.attempt,nonce=inflight.request.nonce,lifetime=current.lifetime,seq=e.seq,guarded=true},e))
    send('Echo',{attempt=inflight.attempt,nonce=inflight.request.nonce,envelope=e})
   end
  elseif command=='Receipt' then
   assert(args.phase==phase and inflight and inflight.envelope and args.attempt==inflight.attempt and args.nonce==inflight.request.nonce and args.accepted==(user=='client1'),'Exact echo receipt differs')
   local e=inflight.envelope;local got=args.envelope
   assert(got.session==e.session and got.grant==e.grant and got.lease==e.lease and got.cart==e.cart and got.seq==e.seq,'Echo receipt changed exact lease')
   log(tuple({actor=user,event='receipt',phase=phase,owner=ownerID,attempt=inflight.attempt,nonce=args.nonce,lifetime=inflight.lifetime,currentLifetime=current.lifetime,accepted=args.accepted,seq=e.seq,guarded=true},e))
   ackLifetime=inflight.lifetime;ackAttempt=inflight.attempt
   oldEnvelope={session=e.session,grant=e.grant,lease=e.lease,seq=e.seq+1,op='UPDATE',mode='motion',cart=e.cart,body='retired-equipment'}
   inflight=nil
  elseif command=='Complete' then
   assert(phase==3 and args.phase==3 and doneSent and not offered,'Early/repeated completion offer');offered=true
   log({actor=user,event='complete-offer',phase=3,owner=ownerID})
  else error('Unexpected lifetime response') end
  drive(native)
 end)
 if not ok then log({actor=user,event='error',reason=tostring(err)}) end
end)
function M.finish(native,now)
 if done then return true end
 if not since then since=now end
 assert(now-since<20000,'Equipment lifetime bank deadline')
 if not ready then
  assert(native and native:getUsername()=='client1','Exact native fixture owner required')
  ownerID=native:getOnlineID();receiver=P.receiver(ownerID,assert(cartLeaseSeed())..':'..user..':equipment')
  current=held(native);receiver:native(assert(cartLeaseCurrent()),native,current);ready=true;lastChange=getTimestampMs()
  log({actor=user,event='ready',phase=0,owner=ownerID,lifetime=current.lifetime});send('Ready',{})
 else refresh(native);drive(native) end
 return done
end
return M
