local root=assert(arg[1]);local folder=root..'/tests/native_queue/contributions/wooden_cart_multiplayer/'
local P=dofile(folder..'lease-protocol.lua');local queue,roles,logs={}, {}, {}
local now=1000
local function item(id)
 local cargo={getID=function() return 99 end,getActualWeight=function() return 30 end}
 local items={size=function() return 1 end,get=function() return cargo end}
 local v={id=id}
 function v:getID() return self.id end
 function v:setID(id) self.id=id end
 function v:getFullType() return 'SaucedWheelbarrow.WheelbarrowWood' end
 function v:getWorldItem() return nil end
 function v:getInventory() return {getItems=function() return items end} end
 return v
end
local function actor(role)
 local v={cart=item(42),revision=1}
 function v:getUsername() return 'client1' end
 function v:getOnlineID() return 7 end
 function v:getPrimaryHandItem() return self.primary end
 function v:getSecondaryHandItem() return self.secondary end
 function v:setPrimaryHandItem(i) if self.primary~=i then self.revision=self.revision+1 end;self.primary=i end
 function v:setSecondaryHandItem(i) if self.secondary~=i then self.revision=self.revision+1 end;self.secondary=i end
 v.primary=v.cart;v.secondary=v.cart;return v
end
for _,role in ipairs({'server','client1','client2'}) do
 local r={actor=actor(role),connection={},role=role};roles[role]=r
 function r:getUsername() return role end
 local callbacks={};local events={}
 for _,kind in ipairs({'OnClientCommand','OnServerCommand'}) do events[kind]={Add=function(fn) callbacks[kind]=fn end} end
 local env=setmetatable({},{__index=_G});r.env=env;r.callbacks=callbacks
 env.Events=events
 env.require=function(name)
  if name=='QueueTestSelection' then return {disposable=true,options={cart_lease_control=true,cart_lease_lifetimes=true}} end
  if name=='CartLeaseProtocol' then return P end
  if name=='CartMPJSON' then return {encode=function(row) logs[#logs+1]={role=role,row=row};return row.event end} end
  error('Unknown module '..name)
 end
 env.print=function(s) assert(not s:find(' ERROR ',1,true),s) end
 env.getTimestampMs=function() now=now+1;return now end
 env.isServer=function() return role=='server' end
 env.cartLeaseSeed=function() return role end
 env.cartLeaseLifetime=function(p) return p.primary and p.primary==p.secondary and role..':'..p.revision or nil end
 env.cartLeaseCurrent=function() return r.connection end
 env.cartLeaseIngress=function() return r.connection end
 env.cartLeaseSource=function(p) return p.connection end
 env.cartLeaseOwnerConnection=function() return roles.client1.connection end
 env.cartLeaseTarget=function(id) assert(id==7);return roles.server.actor end
 env.instanceItem=function() return item(-1) end
 env.getPlayer=function() return r end
 env.getOnlinePlayers=function() return {size=function() return 1 end,get=function() return r.actor end} end
 env.getFileReader=function() return {readLine=function() return role end,close=function() end} end
 env.sendClientCommand=function(p,mod,cmd,args) assert(p==r);queue[#queue+1]={role='server',kind='OnClientCommand',args={mod,cmd,roles.server.sources[role],args}} end
 env.sendServerCommand=function(p,mod,cmd,args) queue[#queue+1]={role=p.role,kind='OnServerCommand',args={mod,cmd,args}} end
 r.api=assert(setfenv(assert(loadfile(folder..'lease-lifetimes.lua')),env))()
end
roles.server.sources={client1=roles.server.actor,client2={role='client2',connection=roles.client2.connection,getUsername=function() return 'client2' end}}
roles.server.actor.role='client1';roles.server.actor.connection=roles.client1.connection
assert(not roles.client1.api.finish(roles.client1.actor,now))
assert(not roles.client2.api.finish(roles.client2.actor,now))
local count=0
while #queue>0 do
 count=count+1;assert(count<100,'Unbounded fixture messages')
 local message=table.remove(queue,1);roles[message.role].callbacks[message.kind](unpack(message.args))
end
assert(roles.client1.api.finish(roles.client1.actor,now) and roles.client2.api.finish(roles.client2.actor,now),'Fixture did not finish')
local cycles,stale=0,0
for _,v in ipairs(logs) do if v.row.event=='cycle' then cycles=cycles+1 end;if v.row.event=='stale' then stale=stale+1 end end
assert(cycles==6 and stale==4,'Native bank matrix mismatch')
print('LEASE_LIFETIME_BANK_CHECK_PASS messages='..count..' cycles='..cycles..' staleSourceRefusals='..stale)
