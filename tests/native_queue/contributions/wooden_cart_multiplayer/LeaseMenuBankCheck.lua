-- Exercise the actual three-role lifetime adapter; the native menu boundary is doubled.
local root=assert(arg[1]);local defect=arg[2] or 'none'
local folder=root..'/tests/native_queue/contributions/wooden_cart_multiplayer/'
local Protocol=dofile(folder..'lease-protocol.lua')
local messages,roles,logs,updates,drivers={},{},{},{},{}
local now,tick,messageCount,menuCount=1000,0,0,0
local runtime=false
local commandCounts={};local firstDefect=false
local function copy(value)
 if type(value)~='table' then return value end
 local result={};for key,v in pairs(value) do result[key]=copy(v) end;return result
end
local function item()
 local cargo={getID=function() return 99 end,getActualWeight=function() return 30 end}
 local items={size=function() return 1 end,get=function() return cargo end}
 local v={id=42}
 function v:getID() return self.id end
 function v:getFullType() return 'SaucedWheelbarrow.WheelbarrowWood' end
 function v:getWorldItem() return self.world end
 function v:getInventory() return {getItems=function() return items end} end
 function v:setID() error('Menu bank attempted synthetic item mutation') end
 return v
end
local function actor()
 local v={cart=item(),revision=1}
 function v:getUsername() return 'client1' end
 function v:getOnlineID() return 7 end
 function v:getPrimaryHandItem() return self.primary end
 function v:getSecondaryHandItem() return self.secondary end
 function v:getX() return 10 end
 function v:getY() return 10 end
 function v:getZ() return 0 end
 function v:setPrimaryHandItem() error('Menu bank attempted native primary setter') end
 function v:setSecondaryHandItem() error('Menu bank attempted native secondary setter') end
 v.primary=v.cart;v.secondary=v.cart
 return v
end
local function records(role,event,phase)
 local result={}
 for _,entry in ipairs(logs) do
  if entry.role==role and entry.row.event==event and (not phase or entry.row.phase==phase) then result[#result+1]=entry.row end
 end
 return result
end
local function replicated(role,pickup)
 local p=roles[role].actor
 p.primary=pickup and p.cart or nil;p.secondary=p.primary;p.revision=p.revision+1
 p.cart.world=not pickup and {getItem=function() return p.cart end} or nil
end
local function schedule(pickup)
 replicated('client1',pickup)
 for _,role in ipairs({'server','client2'}) do
  if not (not pickup and defect==role..'-no-absence') then
   updates[#updates+1]={role=role,pickup=pickup,at=tick+(role=='server' and 2 or 5)}
  end
 end
end
local function enqueueMessage(role,kind,args)
 local command=args[2]
 commandCounts[command]=(commandCounts[command] or 0)+1
 messages[#messages+1]={role=role,kind=kind,args=args}
end
for _,role in ipairs({'server','client1','client2'}) do
 local r={actor=actor(),connection={},role=role};roles[role]=r
 r.localPlayer=role=='client1' and r.actor or {getUsername=function() return role end}
 local callbacks,events={},{}
 for _,kind in ipairs({'OnClientCommand','OnServerCommand','OnTick'}) do
  events[kind]={Add=function(fn) assert(not callbacks[kind]);callbacks[kind]=fn end}
 end
 r.callbacks=callbacks
 local env=setmetatable({},{__index=_G});r.env=env
 env.Events=events
 env.require=function(name)
  if name=='QueueTestSelection' then return {disposable=true,options={cart_lease_control=true,cart_lease_lifetimes=true,cart_lease_menu=true}} end
  if name=='CartLeaseProtocol' then
   local p={server=function(...)
    local server=Protocol.server(...);local accept=server.accept;r.sourceRefusals=0
    server.accept=function(self,id,connection,actor,envelope,at)
     local result=accept(self,id,connection,actor,envelope,at)
     if envelope and envelope.body=='retired-equipment' and not result then r.sourceRefusals=r.sourceRefusals+1 end
     return result
    end
    return server
   end,receiver=function(...)
    r.receiver=Protocol.receiver(...)
    local reply,receive=r.receiver.reply,r.receiver.receive;r.replyRefusals=0;r.payloadRefusals=0
    r.receiver.reply=function(self,...)
     local result=reply(self,...);if not result then r.replyRefusals=r.replyRefusals+1 end;return result
    end
    r.receiver.receive=function(self,envelope,at)
     local result=receive(self,envelope,at)
     if envelope.body=='retired-equipment' and not result then r.payloadRefusals=r.payloadRefusals+1 end
     return result
    end
    return r.receiver
   end};return p
  end
  if name=='CartMPJSON' then return {encode=function(row) logs[#logs+1]={role=role,row=row};return row.event end} end
  if name=='CartLeaseMenuActions' then
   assert(runtime and role=='client1','Menu helper must load only for runtime owner input')
   r.menuRequires=(r.menuRequires or 0)+1
   if defect=='missing-menu-driver' then return nil end
   if defect=='non-table-menu-driver' then return true end
   if defect=='incomplete-menu-driver' then return {enqueue=function() error('Incomplete menu driver invoked') end} end
   return {
   enqueue=function(player,cart,pickup,phase,emit)
    assert(role=='client1' and player==r.actor and cart==r.actor.cart,'Foreign menu enqueue')
    assert(phase==2 or phase==3,'Unexpected native menu phase')
    assert((pickup and not player.primary and cart.world) or (not pickup and player.primary==cart and not cart.world),'Menu native precondition differs')
    if pickup then
     for _,who in ipairs({'server','client1','client2'}) do
      assert(#records(who,'absence',phase)==1 and roles[who].actor.primary==nil,'Pickup bypassed three-role empty-hands barrier')
     end
     assert(#records('server','menu-resume',phase)==1,'Pickup bypassed authoritative resume')
    end
    menuCount=menuCount+1
    local s={player=player,item=cart,pickup=pickup,phase=phase,emit=emit,polls=0}
    drivers[#drivers+1]=s;emit('queued',{kind=pickup and 'pickup' or 'release',cart=42,actionType=pickup and 'ToolkitWoodCartPickup' or 'ToolkitWoodCartSetdown'})
    return s
   end,
   poll=function(s)
    assert(role=='client1' and s.player==r.actor,'Foreign menu poll')
    s.polls=s.polls+1
    local row={kind=s.pickup and 'pickup' or 'release',cart=42,actionType=s.pickup and 'ToolkitWoodCartPickup' or 'ToolkitWoodCartSetdown'}
    if s.polls==1 then s.emit('start',row);return false end
    if s.polls==2 then schedule(s.pickup);return false end
    if not s.terminal then s.terminal=true;s.emit('terminal',row) end
    return true
   end,
  } end
  error('Unknown module '..name)
 end
 env.print=function(s) assert(not s:find(' ERROR ',1,true),s) end
 env.getTimestampMs=function() now=now+1;return now end
 env.isServer=function() return role=='server' end
 env.cartLeaseChallengeSeed=function() return role..':menu-bank:fresh' end
 env.cartLeaseLifetime=function(p) return p.primary and p.primary==p.secondary and '1|mock-'..role..'|101|201|'..p.revision or nil end
 env.cartLeaseResnapshot=function() return false end
 env.cartLeaseCurrent=function() return r.connection end
 env.cartLeaseIngress=function() return r.foreignIngress or r.connection end
 env.cartLeaseSource=function(p) return p.connection end
 env.cartLeaseOwnerConnection=function() return roles.client1.connection end
 env.cartLeaseTarget=function(id) assert(id==7);return roles.server.actor end
 env.instanceItem=function() error('Menu bank attempted synthetic replacement') end
 env.getPlayer=function() return r.localPlayer end
 env.getOnlinePlayers=function() return {size=function() return 1 end,get=function() return r.actor end} end
 env.getFileReader=function() return {readLine=function() return role end,close=function() end} end
 env.getCell=function() return {getGridSquare=function(_,x,y)
  if x~=10 or y~=10 then return nil end
  return {getWorldObjects=function() return {size=function() return r.actor.cart.world and 1 or 0 end,
   get=function() return r.actor.cart.world end} end}
 end} end
 env.sendClientCommand=function(player,mod,cmd,args)
  assert(player==r.localPlayer and role~='server')
  if cmd=='MenuAbsent' and not firstDefect then
   if defect=='omitted-absence' then firstDefect=true;return end
   if defect=='malformed-absence' then firstDefect=true;args.old.body='foreign-prepared-payload' end
   if defect=='wrong-absence-nonce' then firstDefect=true;args.nonce='foreign-nonce' end
  end
  enqueueMessage('server','OnClientCommand',{mod,cmd,roles.server.sources[role],copy(args)})
 end
 env.sendServerCommand=function(player,mod,cmd,args)
  enqueueMessage(player.role,'OnServerCommand',{mod,cmd,copy(args)})
 end
 r.api=assert(setfenv(assert(loadfile(folder..'lease-lifetimes.lua')),env))()
end
roles.server.sources={client1=roles.server.actor,client2={role='client2',connection=roles.client2.connection,getUsername=function() return 'client2' end}}
roles.server.actor.role='client1';roles.server.actor.connection=roles.client1.connection
runtime=true
for tickIndex=1,2500 do
 tick=tickIndex;now=now+20
 for index=#updates,1,-1 do
  local update=updates[index]
  if tick>=update.at then replicated(update.role,update.pickup);table.remove(updates,index) end
 end
 if #messages>0 then
  messageCount=messageCount+1;assert(messageCount<=60,'Unbounded menu fixture commands')
  local message=table.remove(messages,1)
  if message.kind=='OnServerCommand' and message.args[2]=='Cycle' and not firstDefect then
   if defect=='early-resume' then
    firstDefect=true
    roles[message.role].callbacks.OnServerCommand(message.args[1],'MenuResume',{phase=message.args[3].phase,owner=7})
   elseif defect=='foreign-ingress' then firstDefect=true;roles[message.role].foreignIngress={} end
  end
  if message.kind=='OnServerCommand' and message.args[2]=='MenuResume' and defect=='malformed-resume' and not firstDefect then
   firstDefect=true;message.args[3].phase=99
  end
  roles[message.role].callbacks[message.kind](unpack(message.args))
 end
 if roles.server.callbacks.OnTick then roles.server.callbacks.OnTick() end
 local first=roles.client1.api.finish(roles.client1.actor,now)
 local second=roles.client2.api.finish(roles.client2.actor,now)
 if first and second and #messages==0 and #updates==0 then break end
 assert(tick<2500,'Menu bank fixture did not finish')
end
assert(defect=='none','Injected menu bank defect unexpectedly completed: '..defect)
assert(messageCount==50 and menuCount==4,'Menu command/action matrix mismatch')
assert(roles.client1.menuRequires==1 and not roles.client2.menuRequires and not roles.server.menuRequires,'Native menu helper load scope differs')
assert(commandCounts.MenuAbsent==4 and commandCounts.MenuResume==4,'Menu barrier command count differs')
for _,role in ipairs({'server','client1','client2'}) do
 assert(#records(role,'cycle')==2 and #records(role,'absence')==2,'Missing role transition/absence observations')
 assert(roles[role].actor.primary==roles[role].actor.cart and roles[role].actor.secondary==roles[role].actor.cart,'Native final equipment differs')
 if role~='server' then
  assert(#records(role,'post-bind-stale')==2,'Missing client stale refusal after fresh bind')
  assert(roles[role].replyRefusals==4 and roles[role].payloadRefusals==4,'Actual receiver stale refusal calls missing')
  assert(#records(role,'complete')==1,'Client did not complete')
 end
 for phase=2,3 do
  local absence=records(role,'absence',phase)[1]
  assert(absence.nativeLifetimeAbsent==true,'Unproved native equipment absence')
  if role~='server' then assert(absence.staleReplyAccepted==false and absence.stalePayloadAccepted==false,'Missing absent client stale refusals') end
  local cycle=records(role,'cycle',phase)[1]
  assert(cycle.before~=cycle.after and cycle.cart==42 and cycle.cargoID==99 and cycle.cargoWeight==30,'Native cart/cargo or lifetime changed incorrectly')
 end
end
assert(#records('server','absent-source')==4 and #records('server','stale')==4,'Missing server stale refusals')
assert(roles.server.sourceRefusals==8,'Actual server source refusal calls missing')
assert(#records('server','menu-resume')==2 and #records('server','complete')==1,'Authoritative menu barrier/completion missing')
for _,s in ipairs(drivers) do assert(s.terminal and s.polls>=3,'Incomplete native menu boundary') end
print('LEASE_MENU_BANK_CHECK_PASS messages='..messageCount..' ownerActions='..menuCount..' absenceObservations=6 absentSourceRefusals=4 postBindClientRefusals=4')
