-- Explicit native setter boundary bank. No production admission or playback is enabled.
local config=require 'QueueTestSelection'
assert(config.disposable==true and config.options.cart_lease_control==true and config.options.cart_lease_lifetimes==true,'Owned equipment lifetime bank required')
local P=require 'CartLeaseProtocol'
local J=require 'CartMPJSON'
local M={}
local module='CartLeaseLifetimes'
local phases={'baseline','release-reacquire','same-id-replacement'}
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
  assert(replacement~=before.item,'Replacement aliases original item')
  replacement:setID(before.cart)
  p:setPrimaryHandItem(replacement);p:setSecondaryHandItem(replacement)
  assert(p:getPrimaryHandItem()==replacement and p:getSecondaryHandItem()==replacement and replacement:getID()==before.cart,'Same-ID native replacement failed')
 end
 p:setPrimaryHandItem(before.item);p:setSecondaryHandItem(before.item)
 local after=held(p);local final,finalID,finalWeight=cargo(after.item)
 assert(after.item==before.item and after.cart==before.cart and final==c and finalID==cid and finalWeight==weight,'Fixture cart/cargo restoration failed')
 assert(after.lifetime~=before.lifetime,'Native mutation cycle was missed')
 row.after=after.lifetime;row.sameItem=true;return row
end
local protected={'session','grant','lease','seq','open','visible','body','received'}
local function unchanged(before,after)
 for _,k in ipairs(protected) do assert(before[k]==after[k],'Rejection changed '..k) end
end
local function tuple(row,b)
 row.session=b.session;row.grant=b.grant;row.lease=b.lease;row.cart=b.cart;return row
end
if isServer() then
 local controller=P.server(assert(cartLeaseSeed())..':equipment',{limit=4})
 local clients,ready,completed,prepared={},{},{},{}
 local target,phase=nil,0
 local function observe()
  local connection=assert(cartLeaseOwnerConnection(target),'Current native owner connection missing')
  local binding=held(target)
  assert(controller:observe(target:getOnlineID(),connection,target,binding),'Authoritative lifetime observation refused')
  return binding
 end
 local function send(p,command,args) sendServerCommand(p,module,command,args) end
 local function all(rows) return rows.client1 and rows.client2 end
 local function advance()
  phase=phase+1;completed={}
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
    log({actor='server',event='ready',requester=role,phase=0,owner=id,guarded=true})
    if all(ready) then advance() end
    return
   end
   assert(clients[role]==p and args.phase==phase and phase>=1 and phase<=3,'Unknown requester or phase')
   local binding=observe()
   if command=='Bind' then
    if phase>1 then
     local before=controller:snapshot(id)
     assert(not controller:accept(id,source,p,args.old,getTimestampMs()),'Retired source payload accepted')
     unchanged(before,controller:snapshot(id))
     log(tuple({actor='server',event='stale',requester=role,phase=phase,owner=id,accepted=false,guarded=true},args.old))
    end
    local reply=assert(controller:reply(args.request,source),'Fresh challenge reply missing')
    assert(reply.open and reply.actor==id,'Fresh native lease closed')
    log(tuple({actor='server',event='bind',requester=role,phase=phase,owner=id,nonce=reply.nonce,lifetime=binding.lifetime,guarded=true},reply))
    send(p,'Bound',{phase=phase,owner=id,reply=reply})
   elseif command=='Echo' then
    local accepted=controller:accept(id,source,p,args.envelope,getTimestampMs())
    assert(accepted==(role=='client1'),'Exact native source authority differs')
    log(tuple({actor='server',event='echo',requester=role,phase=phase,owner=id,nonce=args.nonce,accepted=accepted,seq=args.envelope.seq,guarded=true},args.envelope))
    send(p,'Receipt',{phase=phase,owner=id,nonce=args.nonce,accepted=accepted,envelope=args.envelope})
   elseif command=='Prepare' then
    assert(phase<3 and not prepared[role],'Repeated/late preparation')
    local reply=assert(controller:reply(args.request,source),'Pending challenge reply missing')
    assert(reply.actor==id and reply.open,'Pre-mutation source lease missing')
    prepared[role]={reply=reply}
    log(tuple({actor='server',event='prepare',requester=role,phase=phase,owner=id,nonce=reply.nonce,lifetime=binding.lifetime,guarded=true},reply))
    if all(prepared) then advance() end
   elseif command=='Done' then
    assert(phase==3 and not completed[role],'Repeated/early completion')
    completed[role]=true
    log({actor='server',event='done',requester=role,phase=phase,owner=id,guarded=true})
    if all(completed) then
     log({actor='server',event='complete',phase=3,owner=id})
     for _,v in pairs(clients) do send(v,'Complete',{phase=3,owner=id}) end
    end
   else error('Unexpected lifetime request') end
  end)
  if not ok then log({actor='server',event='error',reason=tostring(err)}) end
 end)
 return M
end
local reader=assert(getFileReader('smoke-user.txt',false));local user=reader:readLine();reader:close()
local receiver,ownerID,phase,request,oldEnvelope,since=nil,nil,0,nil,nil,nil
local ready,done=false,false
local function owner()
 local players=getOnlinePlayers()
 for i=0,players:size()-1 do local p=players:get(i);if p:getUsername()=='client1' then return p end end
 error('Native owner missing')
end
local function send(command,args) args.owner=ownerID;args.phase=phase;sendClientCommand(getPlayer(),module,command,args) end
local function fresh(native)
 receiver:native(assert(cartLeaseCurrent(),'Current local connection missing'),native,held(native))
 request=assert(receiver:challenge(),'Bounded fresh challenge missing')
 log({actor=user,event='request',phase=phase,owner=ownerID,nonce=request.nonce,lifetime=held(native).lifetime})
 send('Bind',{request=request,old=oldEnvelope})
end
Events.OnServerCommand.Add(function(mod,command,args)
 if mod~=module then return end
 local ok,err=pcall(function()
  local ingress=assert(cartLeaseIngress(),'Exact native reply ingress missing')
  local native=owner();assert(receiver and native:getOnlineID()==ownerID and args.owner==ownerID,'Unexpected owner incarnation')
  if command=='Begin' then
   assert(phase==0 and args.phase==1,'Unexpected baseline begin');phase=1
   log({actor=user,event='begin',phase=phase,owner=ownerID});fresh(native)
  elseif command=='Cycle' then
   assert(args.phase==phase+1 and phase>=1 and phase<=2,'Unexpected mutation stage')
   assert(request and args.stale.nonce==request.nonce,'Pending challenge replaced')
   phase=args.phase;local row=cycle(native,phase,user)
   receiver:native(assert(cartLeaseCurrent()),native,held(native))
   local before=receiver:snapshot()
   assert(not receiver:reply(args.stale,ingress),'Retired pending challenge reply accepted')
   unchanged(before,receiver:snapshot())
   assert(not receiver:receive(oldEnvelope,getTimestampMs()),'Retired receiver payload accepted')
   unchanged(before,receiver:snapshot())
   row.staleReplyAccepted=false;row.stalePayloadAccepted=false;row.staleNonce=args.stale.nonce
   log(row);fresh(native)
  elseif command=='Bound' then
   assert(args.phase==phase and request and args.reply.nonce==request.nonce,'Unrequested grant')
   local binding=held(native);receiver:native(assert(cartLeaseCurrent()),native,binding)
   assert(receiver:reply(args.reply,ingress),'Fresh exact lifetime bind rejected')
   local e={session=args.reply.session,grant=args.reply.grant,lease=args.reply.lease,seq=1,op='UPDATE',mode='motion',cart=binding.cart,body='fixture-lifetime-'..phase}
   assert(receiver:receive(e,getTimestampMs()),'Fresh receiver state refused')
   log(tuple({actor=user,event='bound',phase=phase,owner=ownerID,nonce=request.nonce,lifetime=binding.lifetime,guarded=true},e))
   send('Echo',{nonce=request.nonce,envelope=e})
  elseif command=='Receipt' then
   assert(args.phase==phase and request and args.nonce==request.nonce and args.accepted==(user=='client1'),'Exact echo receipt differs')
   local s=receiver:snapshot();local e=args.envelope
   assert(e.session==s.session and e.grant==s.grant and e.lease==s.lease and e.cart==held(native).cart and e.seq==1,'Echo receipt changed native lease')
   log(tuple({actor=user,event='receipt',phase=phase,owner=ownerID,nonce=args.nonce,accepted=args.accepted,seq=e.seq,guarded=true},e))
   oldEnvelope={session=e.session,grant=e.grant,lease=e.lease,seq=2,op='UPDATE',mode='motion',cart=e.cart,body='retired-equipment'}
   if phase<3 then
    request=assert(receiver:challenge(),'Pending pre-mutation challenge missing')
    log({actor=user,event='prepare',phase=phase,owner=ownerID,nonce=request.nonce,lifetime=held(native).lifetime})
    send('Prepare',{request=request})
   else log({actor=user,event='done',phase=phase,owner=ownerID});send('Done',{}) end
  elseif command=='Complete' then
   assert(phase==3 and args.phase==3,'Early completion');done=true
   log({actor=user,event='complete',phase=phase,owner=ownerID})
  else error('Unexpected lifetime response') end
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
  receiver:native(assert(cartLeaseCurrent()),native,held(native));ready=true
  log({actor=user,event='ready',phase=0,owner=ownerID});send('Ready',{})
 end
 return false
end
return M
