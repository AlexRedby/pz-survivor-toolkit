-- State-machine-only check. These fake actors do not qualify as native evidence.
local base=assert(arg[1],'Supply contribution directory')
local function readSource(name) local f=assert(io.open(base..'/'..name));local s=f:read('*a');f:close();return s end
local source=readSource('lease-lifecycle.lua')
local protocol=readSource('lease-protocol.lua')
mockRace=arg[2]=='resnapshot';mockRaceCertified=arg[3]~='uncertified'
local time,serial=10000,10
local queue,envs,logs,files={},{},{},{}
local guestGeneration=1
local activeEnvironment,raceInjected=nil,false
local function list(items)
 items=items or {};return {size=function() return #items end,get=function(_,i) return items[i+1] end}
end
local function inventory()
 local v={items={}}
 function v:getItems() return list(self.items) end
 function v:getItemById(id) for _,item in ipairs(self.items) do if item.id==id then return item end end end
 function v:AddItem(kind)
  serial=serial+1
  local item={id=serial,kind=kind,weight=1,container=self}
  function item:getID() return self.id end
  function item:getFullType() return self.kind end
  function item:getActualWeight() return self.weight end
  function item:setActualWeight(v) self.weight=v end
  function item:setCustomWeight(v) end
  function item:getWorldItem() return self.world end
  function item:getContainer() return self.container end
  function item:getInventory() return self.inventory end
  if kind~='Base.Log' then item.inventory=inventory() end
  self.items[#self.items+1]=item;return item
 end
 return v
end
local bodies={}
local square={getDeadBodys=function() return list(bodies) end}
local conn1,conn2={active=true},{active=true}
local function actor(name,epoch,inv)
 local p={name=name,epoch=epoch,id=name=='client1' and 1 or 2,inventory=inv or inventory(),square=square,x=100,y=100,z=0,dead=false}
 function p:getUsername() return self.name end
 function p:getOnlineID() return self.id end
 function p:getCurrentSquare() return self.square end
 function p:isDead() return self.dead end
 function p:getPrimaryHandItem() return activeEnvironment and activeEnvironment.remoteItem and self.name=='client2' and activeEnvironment.remoteItem or self.primary end
 function p:getSecondaryHandItem() return activeEnvironment and activeEnvironment.remoteItem and self.name=='client2' and activeEnvironment.remoteItem or self.secondary end
 function p:setPrimaryHandItem(v) self.primary=v end
 function p:setSecondaryHandItem(v) self.secondary=v end
 function p:getInventory() return self.inventory end
 function p:getX() return self.x end
 function p:getY() return self.y end
 function p:getZ() return self.z end
 function p:teleportTo(x,y,z) self.x=x;self.y=y;self.z=z end
 function p:setGodMod(v) end
 function p:setGhostMode(v) end
 function p:updateHandEquips() end
 function p:Kill(v)
  self.dead=true
  for _,e in pairs(envs) do for _,f in ipairs(e.Events.OnCharacterDeath.listeners) do f(self) end end
  for _,f in ipairs(envs.client2.Events.OnPlayerDeath.listeners) do f(self) end
 end
 return p
end
local host,guest=actor('client1',1),actor('client2',2)
local function current(name) return name=='client1' and host or guest end
local function fire(e,event,...)
 activeEnvironment=e
 for _,f in ipairs(e.Events[event].listeners) do f(...) end
end
local function clone(t)
 if type(t)~='table' then return t end
 local n={};for k,v in pairs(t) do n[k]=clone(v) end;return n
end
local function makeEnv(name)
 local e=setmetatable({},{__index=_G});e.Events=setmetatable({},{__index=function(t,k) local ev={listeners={}};ev.Add=function(fn) table.insert(ev.listeners,fn) end;t[k]=ev;return ev end})
 e._G=e;e.files=files[name] or {};files[name]=e.files
 e.isServer=function() return name=='server' end
 e.isClient=function() return name~='server' end
 e.getTimestampMs=function() return time end
 e.getOnlinePlayers=function() local ps={host};if guest.square then ps[#ps+1]=guest end;return list(ps) end
 e.getPlayer=function() return current(name) end
 e.getCell=function() return {getGridSquare=function() return square end} end
 e.getFileReader=function(path) local value=path=='smoke-user.txt' and name or e.files[path];if value==nil then return nil end;return {readLine=function() return value end,close=function() end} end
 e.getFileWriter=function(path) return {write=function(_,value) e.files[path]=value end,close=function() end} end
 e.cartLeaseChallengeSeed=function() serial=serial+1;return 'uuid-'..name..'-'..serial end
 e.cartMPPadHost=function() return true end
 e.cartLeaseSource=function(p) assert(e.inCommand,'no native scope');return p==host and conn1 or conn2 end
 e.cartLeaseOwnerConnection=function(p) assert(e.inCommand,'no native scope');return p==host and conn1 or conn2 end
 e.cartLeaseConnectionActive=function(c) assert(e.inCommand,'no native scope');return c.active end
 e.cartLeaseTarget=function(id) return guest.id==id and guest or host.id==id and host end
 e.cartLeaseCurrent=function() return e.inGame and (name=='client1' and conn1 or conn2) or nil end
 e.cartLeaseIngress=function() return e.inCommand and (name=='client1' and conn1 or conn2) or nil end
 e.cartLeaseLifetime=function(p)
  if p.dead or not p.square or not p.primary or p.primary~=p.secondary then return nil end
  local c=name=='client1' and conn1 or p==host and conn1 or conn2
  if not c.active then return nil end
  return '1|process-'..name..'|'..p.epoch..'|'..(c==conn1 and '1' or tostring(guestGeneration+1))..'|'..tostring(e.remoteRevision or 1)
 end
 e.cartLeaseResnapshot=function(p,previous) return name=='client1' and e.remoteRevision==2 and previous:match('|1$')~=nil and mockRaceCertified~=false end
 e.sendAddItemToContainer=function() end
 e.sendServerCommand=function(p,module,command,args) queue[#queue+1]={target=p.name,module=module,command=command,args=clone(args)} end
 e.sendClientCommand=function(p,module,command,args) queue[#queue+1]={target='server',p=p,module=module,command=command,args=clone(args)} end
 e.print=function(s) logs[#logs+1]={role=name,text=s};if s:find('ERROR',1,true) then for i=math.max(1,#logs-12),#logs do _G.print(logs[i].role..' '..logs[i].text) end;error(s) end end
 e.require=function(mod)
  if mod=='QueueTestSelection' then return {suite='wooden_cart_multiplayer',disposable=true,kind='mp',cases={'lease_lifecycle'},options={mp_host=true},port=1} end
  if mod=='CartMPJSON' then return {encode=function(row) local s='';for k,v in pairs(row) do s=s..k..'='..tostring(v)..',' end;return s end} end
  if mod=='CartLeaseProtocol' then return assert(load(protocol,'protocol','t',e))() end
  if mod=='CartMPPlacement' then return function() return {x=100,y=100,z=0} end end
  error(mod)
 end
 e.inGame=name~='server';e.isIngameState=function() return e.inGame end
 e.ISPostDeathUI={instance={}}
 e.CoopCharacterCreation={}
 e.MainScreen={instance={inGame=true,isVisible=function() return e.menuVisible end}}
 e.KeybindId={MAIN_MENU=1};e.Keyboard={KEY_ESCAPE=1}
 e.getCore=function() return {getKey=function() return 1 end} end
 e.ToggleEscapeMenu=function() e.menuVisible=true end
 e.MainScreen.instance.exitOption={internal='EXIT',onMouseDown=function()
  guest.square=nil;conn2.active=false;e.inGame=false;e.MainScreen.instance.inGame=false;e.menuVisible=true
 end}
 e.ConnectToServer={instance={connect=function()
  guestGeneration=guestGeneration+1
  local inv=guest.inventory;guest=actor('client2',4,inv);conn2={active=true};envs.client1.remoteItem=nil;envs.client1.remoteRevision=nil
  e.inGame=true;e.MainScreen.instance.inGame=true;e.menuVisible=false
  fire(e,'OnCreatePlayer',0,guest);fire(e,'OnGameStart')
 end}}
 return e
end
for _,name in ipairs({'server','client1','client2'}) do envs[name]=makeEnv(name) end
for _,e in pairs(envs) do assert(load(source,'fixture','t',e))() end
fire(envs.server,'OnServerStarted')
for _,name in ipairs({'client1','client2'}) do fire(envs[name],'OnCreatePlayer',0,current(name));fire(envs[name],'OnGameStart') end
local removed=false
for tick=1,1000 do
 time=time+100
 for _,name in ipairs({'server','client1','client2'}) do local e=envs[name];fire(e,'OnTick');fire(e,'OnPreUIDraw');fire(e,'OnTickEvenPaused') end
 local count=0
 while #queue>0 do
  count=count+1;assert(count<100,'message storm')
  local message=table.remove(queue,1);local e=envs[message.target];e.inCommand=true
  if mockRace and not raceInjected and message.target=='client1' and message.command=='Receipt' and message.args.phase==1 then
   raceInjected=true;e.remoteRevision=2;e.remoteItem={}
   for k,v in pairs(guest.primary) do e.remoteItem[k]=v end
  end
  if message.target=='server' then fire(e,'OnClientCommand',message.module,message.command,message.p,message.args) else fire(e,'OnServerCommand',message.module,message.command,message.args) end
  e.inCommand=false
 end
 local authoritativeAbsence=false
 for _,log in ipairs(logs) do if log.role=='server' and log.text:find('event=native-death-progress,',1,true) then authoritativeAbsence=true end end
 if guest.dead and not removed and authoritativeAbsence then
  removed=true;guest.square=nil
  bodies[#bodies+1]={isPlayer=function() return true end,getCharacterOnlineID=function() return 2 end,getContainer=function() return inventory() end}
  envs.client2.ISPostDeathUI.instance[0]={waitOver=true,buttonRespawn={isVisible=function() return true end},isVisible=function() return true end,onRespawn=function()
   guest=actor('client2',3);envs.client1.remoteItem=nil;envs.client1.remoteRevision=nil;envs.client2.ISPostDeathUI.instance[0]=nil
   fire(envs.client2,'OnCreatePlayer',0,guest)
  end}
 end
 local complete={}
 for _,log in ipairs(logs) do if log.text:find('COMPLETE actor=',1,true) then complete[log.role]=true end end
 if complete.server and complete.client1 and complete.client2 then
  for _,kind in ipairs({'bound','echo','receipt'}) do
   local seen=false
   for _,log in ipairs(logs) do if log.text:find('event='..kind..',',1,true) then assert(log.text:find('nonce=',1,true),'Missing nonce on '..kind);seen=true end end
   assert(seen,'Missing exchange event '..kind)
  end
  if mockRace then
   local receiptRace,freshAfter=false,false
   for _,log in ipairs(logs) do
    if log.role=='client1' and log.text:find('event=receipt-resnapshot,',1,true) then assert(log.text:find('freshNativeProof=false,',1,true));receiptRace=true end
    if receiptRace and log.role=='client1' and log.text:find('event=receipt,',1,true) then freshAfter=true end
   end
   assert(raceInjected and receiptRace and freshAfter,'Remote receipt race did not settle through a normal fresh receipt')
  end
  print('LIFECYCLE_STATE_MACHINE_MOCK_PASS ticks='..tick..' roles=3 phases=3 hostPulseAfterDeathOneSecond=true noncePreserved=true receiptRace='..tostring(mockRace==true));return
 end
end
for _,log in ipairs(logs) do print(log.role..' '..log.text) end
error('mock did not complete')
