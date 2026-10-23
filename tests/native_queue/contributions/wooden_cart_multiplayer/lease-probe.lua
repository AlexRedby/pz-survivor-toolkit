-- Explicit disposable held-only control-path experiment. Never writes native pose/equipment.
local config=require 'QueueTestSelection'
assert(config.disposable==true and config.options.cart_lease_control==true,'Explicit owned lease experiment required')
local P=require 'CartLeaseProtocol'
local J=require 'CartMPJSON'
local M={}
local module='CartLeaseProbe'
local function log(row)
 row.wall=getTimestampMs();print('[CART_LEASE] '..J.encode(row))
 if row.event=='error' then print('[CART_LEASE] ERROR '..tostring(row.reason)) end
end
local function held(player)
 local item=player and player:getPrimaryHandItem()
 assert(item and player:getSecondaryHandItem()==item and not item:getWorldItem(),'Exact held native cart required')
 local kind=item:getFullType()
 assert(kind=='SaucedCarts.ShoppingCart' or kind=='SaucedWheelbarrow.WheelbarrowWood' or kind=='SaucedWheelbarrow.WheelbarrowMetal','Native cart type required')
 return {mode='motion',cart=item:getID(),item=item}
end
if isServer() then
 local server=P.server(assert(cartLeaseSeed()),{limit=4})
 Events.OnClientCommand.Add(function(mod,command,player,args)
  if mod~=module then return end
  local ok,err=pcall(function()
   local source=assert(cartLeaseSource(player),'Missing exact native command source')
   local role=player:getUsername();assert(role=='client1' or role=='client2','Owned fixture source required')
   local target=assert(cartLeaseTarget(args.actor),'Registered target missing')
   assert(target:getUsername()=='client1','Exact fixture owner required')
   local ownerConnection=assert(cartLeaseOwnerConnection(target),'Native owner connection missing')
   assert(server:observe(target:getOnlineID(),ownerConnection,target,held(target)),'Authoritative observation refused')
   if command=='Bind' then
    local reply=assert(server:reply(args,source),'Fresh bind refused')
    assert(reply.open==true,'Fixture native lease closed')
    log({actor='server',event='bind',requester=role,nonce=reply.nonce,owner=args.actor,cart=reply.cart,session=reply.session,grant=reply.grant,lease=reply.lease,guarded=true})
    sendServerCommand(player,module,'Bound',reply)
   elseif command=='Echo' then
    local accepted=server:accept(args.actor,source,player,args.envelope,getTimestampMs())
    assert(accepted==(role=='client1'),'Source authority acceptance differs')
    log({actor='server',event='echo',requester=role,nonce=args.nonce,owner=args.actor,accepted=accepted,session=args.envelope.session,grant=args.envelope.grant,lease=args.envelope.lease,seq=args.envelope.seq,cart=args.envelope.cart,guarded=true})
    sendServerCommand(player,module,'Receipt',{nonce=args.nonce,actor=args.actor,accepted=accepted,session=args.envelope.session,grant=args.envelope.grant,lease=args.envelope.lease,seq=args.envelope.seq,cart=args.envelope.cart})
   else error('Unexpected lease probe command') end
  end)
  if not ok then log({actor='server',event='error',reason=tostring(err)}) end
 end)
 return M
end
local reader=assert(getFileReader('smoke-user.txt',false));local user=reader:readLine();reader:close()
local receiver,round,pending,ownerID=nil,0,{},nil
local function owner()
 local players=getOnlinePlayers()
 for i=0,players:size()-1 do local p=players:get(i);if p:getUsername()=='client1' then return p end end
 error('Exact native owner missing')
end
Events.OnServerCommand.Add(function(mod,command,args)
 if mod~=module then return end
 local ok,err=pcall(function()
  local ingress=assert(cartLeaseIngress(),'Missing exact transport/dispatch ingress')
  local native=owner();assert(native:getOnlineID()==ownerID,'Native owner changed')
  receiver:native(assert(cartLeaseCurrent()),native,held(native))
  if command=='Bound' then
   local request=assert(pending[args.nonce],'Unrequested bind reply')
   assert(request.stage=='bind' and receiver:reply(args,ingress),'Fresh exact bind refused')
   request.stage='echo';request.session=args.session;request.grant=args.grant;request.lease=args.lease;request.cart=args.cart
   log({actor=user,event='bound',nonce=args.nonce,owner=args.actor,cart=args.cart,session=args.session,grant=args.grant,lease=args.lease,guarded=true})
   local envelope={session=args.session,grant=args.grant,lease=args.lease,seq=request.round,op='UPDATE',mode='motion',cart=args.cart,body='probe-only'}
   sendClientCommand(getPlayer(),module,'Echo',{actor=args.actor,nonce=args.nonce,envelope=envelope})
  elseif command=='Receipt' then
   local request=assert(pending[args.nonce],'Unrequested echo receipt')
   assert(request.stage=='echo' and args.actor==ownerID and args.accepted==(user=='client1') and args.session==request.session and args.grant==request.grant
    and args.lease==request.lease and args.cart==request.cart and args.seq==request.round,'Exact native source proof failed')
   pending[args.nonce]=nil
   log({actor=user,event='receipt',nonce=args.nonce,owner=args.actor,accepted=args.accepted,session=args.session,grant=args.grant,lease=args.lease,seq=args.seq,cart=args.cart,guarded=true})
  else error('Unexpected lease control response') end
 end)
 if not ok then log({actor=user,event='error',reason=tostring(err)}) end
end)
function M.sample(native,elapsed)
 if elapsed<0 or elapsed>26000 or round>=3 or elapsed<round*8000 then return end
 assert(native and native:getUsername()=='client1','Native probe owner missing')
 local connection=assert(cartLeaseCurrent(),'Owned local connection unavailable')
 if not receiver then ownerID=native:getOnlineID();receiver=P.receiver(ownerID,assert(cartLeaseSeed())..':'..user) end
 assert(native:getOnlineID()==ownerID,'Fixture actor ID replaced')
 receiver:native(connection,native,held(native))
 local request=assert(receiver:challenge(),'Bounded fresh challenge unavailable')
 round=round+1;pending[request.nonce]={stage='bind',round=round}
 log({actor=user,event='request',nonce=request.nonce,owner=ownerID,round=round,elapsed=elapsed})
 sendClientCommand(getPlayer(),module,'Bind',request)
end
return M
