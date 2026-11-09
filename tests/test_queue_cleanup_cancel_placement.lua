-- Run the real setup scripts with delayed native placement and authority replicas.
local root=ProjectRoot..'/tests/native_queue/'
local function fixture(kind)
 local server=kind=='server';local client=kind=='mp'
 local f={now=0,teleports=0,prepared=0,messages={},logs={},rows={},events={},x=100.5,y=100.5,z=0}
 local function square(x,y,z)
  return {getX=function()return x end,getY=function()return y end,getZ=function()return z end,
   isFree=function()return true end,getRoom=function()end,getObjects=function()return {size=function()return 1 end}end}
 end
 f.square=square(100,100,0);f.current=f.square
 local p={};f.player=p;f.dark=true
 for _,key in ipairs({'X','Y','Z'})do p['get'..key]=function()return f[key:lower()]end end
 function p:getSquare()return f.square end
 function p:getCurrentSquare()return f.current end
 function p:getUsername()return 'client1'end
 function p:getOnlineID()return 1 end
 function p:isLocalPlayer()return not server end
 function p:hasTimedActions()return false end
 function p:isPlayerMoving()return false end
 function p:isTimedActionInstant()return false end
 function p:tooDarkToRead()return f.dark end
 function p:getPath2()end
 function p:getDeferredMovement(out)return out end
 function p:setAutoDrink()end
 function p:teleportTo(x,y,z)f.teleports=f.teleports+1;f.target={x=x,y=y,z=z}end
 function f:arrive(target)
  self.x,self.y,self.z=target.x,target.y,target.z
  self.square=square(target.x,target.y,target.z);self.current=self.square
 end
 local function event(name)return {Add=function(fn)f[name]=fn end}end
 local env={Events={OnClientCommand=event('command'),OnServerCommand=event('serverCommand'),
  OnServerStarted=event('started'),OnTick=event('tick'),OnPreUIDraw=event('draw')}}
 env.isServer=function()return server end;env.isClient=function()return client end
 env.isIngameState=function()return true end;env.getPlayer=function()return p end
 env.getTimestampMs=function()return f.now end;env.getDebug=function()return false end
 env.getCell=function()return {getGridSquare=function(_,x,y,z)return square(x,y,z)end}end
 env.Vector2={new=function()return {getX=function()return 0 end,getY=function()return 0 end}end}
 env.ISTimedActionQueue={getTimedActionQueue=function()return {queue={}}end,add=function()error('unexpected action admission')end}
 env.getCore=function()return {setOptionPauseOnFocusloss=function()end,setOptionAutoDrink=function()end}end
 env.PZSurvivorToolkit={ActionQueueLifecycle={registerObserver=function()return true end},
  Settings={actionQueue=function()return true end}}
 env.PZAPI={ModOptions={getOptions=function()return {getOption=function()return {setValue=function()end}end}end}}
 env.print=function(value)
  f.logs[#f.logs+1]=value
  local event=value:match('^%[QUEUE_CLEANUP%] (%S+) ')
  if event then f.events[#f.events+1]={event=event,value=f.rows[#f.rows]}end
 end
 env.sendServerCommand=function(_,_,command,value)f.messages[#f.messages+1]={command=command,value=value}end
 env.sendClientCommand=function(_,command,value)f.messages[#f.messages+1]={command=command,value=value}end
 setmetatable(env,{__index=_G});f.env=env
 local function load(path)local chunk=assert(loadfile(root..path));setfenv(chunk,env);return chunk()end
 f.P=load('support/QueueEnergyPlacement.lua')
 env.require=function(name)if name=='QueueEnergyPlacement'then return f.P end;return {}end
 local real=load('cleanup-cancel/shared/QueueCleanupCancel.lua')
 local function same(a,b)return a.x==b.x and a.y==b.y and a.z==b.z end
 local F={same=same,baseCase=real.baseCase};f.F=F
 function F.prepare(actor,case,target,proof)
  assert(actor==p and f.P.at(actor,target),'scene must follow actual arrival')
  assert(proof.mode==(server and'replica'or'local'))
  f.prepared=f.prepared+1
  local ids={case=case,placement=f.P.target(target),baseline={}}
  f.state={player=p,ids=ids};return f.state
 end
 function F.resolve()return f.resolve and f.state or nil end
 function F.snapshot()return {case=f.state and f.state.ids.case}end
 function F.refresh()return true end
 function F.baselineDifference()end
 env.require=function(name)
  local modules={QueueEnergyPlacement=f.P,QueueCleanupCancel=F,
   QueueHealthEvents={encode=function(value)f.rows[#f.rows+1]=value;return '{}'end,emit=function(value)f.emitted=value end},
   QueueTestSelection={cases={'mask-after-removal','p4-after-pickup'},mode='toolkit',kind=client and'mp'or'sp'},
   QueuePreflight={onGameStart=function(_,fn)f.start=fn end,onTick=function(_,fn)f.tick=fn end}}
  return modules[name]or{}
 end
 -- Shared prepare requires these modules at load time; reload it after routing.
 f.real=load('cleanup-cancel/shared/QueueCleanupCancel.lua')
 load(server and'cleanup-cancel/server/ZZQueueCleanupCancelServer.lua'or'cleanup-cancel/client/ZZQueueCleanupCancel.lua')
 return f
end

local function exactKeys(value,names)
 local expected={};for _,name in ipairs(names)do expected[name]=true end
 local count=0;for name in pairs(value)do assert(expected[name],'foreign record field '..tostring(name));count=count+1 end
 assert(count==#names,'record fields missing')
end
local function placementEvent(f,name)
 local found
 for _,entry in ipairs(f.events)do
  if entry.event==name then assert(not found,'duplicate '..name);found=entry.value end
 end
 return assert(found,name..' missing')
end

-- Local setup waits for quiet, sends exactly one teleport, and needs both squares.
for _,kind in ipairs({'sp','mp'})do
for _,missing in ipairs({'square','current'})do
 local f=fixture(kind);f.start();f.tick();f.tick();assert(f.prepared==0 and f.teleports==0)
 f.now=500;f.tick();assert(f.prepared==0 and f.teleports==1 and #f.messages==0)
 f.now=1000;f.tick();assert(f.prepared==0 and f.teleports==1)
 f:arrive(f.target);f[missing]=nil;f.now=1001;f.tick();assert(f.prepared==0)
 f:arrive(f.target);f.now=1002;f.tick();assert(f.prepared==0)
 f.now=1502;f.tick()
 if kind=='sp'then assert(f.prepared==1 and #f.messages==0)
 else
  assert(f.prepared==0 and #f.messages==1 and f.messages[1].command=='Prepare')
  local args=f.messages[1].value
  exactKeys(args,{'case','target','clientPlacement'})
  assert(args.case=='mask-after-removal'and f.F.same(args.target,f.target))
  assert(args.clientPlacement.mode=='local'and args.clientPlacement.teleports==1)
 end
 local evidence=placementEvent(f,'CLIENT_PLACEMENT')
 exactKeys(evidence,{'case','actor','target','proof'})
 assert(evidence.case=='mask-after-removal'and evidence.actor=='client1'and f.F.same(evidence.target,f.target))
 assert(evidence.proof.mode=='local'and evidence.proof.teleports==1 and f.F.same(evidence.proof.target,f.target))
 f.now=2002;f.tick();assert(f.teleports==1)
end
end

local target={x=98,y=98,z=0}
local function request(f,proof)
 local args={case='mask-after-removal',target=target}
 if proof~=false then args.clientPlacement=proof or{mode='local',teleports=1,target=target}end
 f.command('QueueCleanupCancelTest','Prepare',f.player,args)
end
-- Authority cannot seed equipment until its own replica has settled.
local f
for _,missing in ipairs({'square','current'})do
f=fixture('server');request(f)
f.tick();f.now=1000;f.tick();assert(f.prepared==0 and f.teleports==0 and #f.messages==0)
f:arrive(target);f[missing]=nil;f.now=1001;f.tick();assert(f.prepared==0)
f:arrive(target);f.now=1002;f.tick();f.now=1501;f.tick();assert(f.prepared==0)
f.now=1502;f.tick();assert(f.prepared==1 and f.teleports==0 and #f.messages==1)
assert(f.messages[1].command=='Prepared'and f.F.same(f.messages[1].value.placement,target))
f.now=2002;f.tick();assert(f.prepared==1 and f.teleports==0)
end

-- Missing, foreign-role and target-mismatched receipts never start scene work.
for _,proof in ipairs({false,{}, {mode='replica',teleports=0,target=target},
 {mode='local',teleports=0,target=target}, {mode='local',teleports=2,target=target},
 {mode='local',teleports=1,target={x=99,y=98,z=0}}})do
 f=fixture('server');request(f,proof);f.tick()
 assert(f.prepared==0 and f.teleports==0 and #f.messages==1 and f.messages[1].command=='Failed')
end
for _,command in ipairs({'Prepare','Baseline','Checkpoint','Verify','Unknown'})do
 f=fixture('server');request(f)
 f.command('QueueCleanupCancelTest',command,f.player,{case='mask-after-removal',target=target,clientPlacement={mode='local',teleports=1,target=target}})
 assert(f.prepared==0 and f.teleports==0 and f.messages[1].command=='Failed','pending prepare must reject overlapping requests')
 f:arrive(target);f.tick();f.now=1000;f.tick()
 assert(f.prepared==0 and f.teleports==0 and #f.messages==1,'failed overlap retained pending scene work')
end
for _,bad in ipairs({'actor','case'})do
 f=fixture('server')
 if bad=='actor'then function f.player:getUsername()return 'client2'end end
 f.command('QueueCleanupCancelTest','Prepare',f.player,{case=bad=='case'and'p4-after-pickup'or'mask-after-removal',
  target=target,clientPlacement={mode='local',teleports=1,target=target}})
 f.tick();assert(f.prepared==0 and f.teleports==0 and f.messages[1].command=='Failed')
end
for _,args in ipairs({false,{}, {case='mask-after-removal'},
 {case='mask-after-removal',target={x=98.5,y=98,z=0},clientPlacement={mode='local',teleports=1,target=target}},
 {case='mask-after-removal',target={x=98,y=98,z=0,extra=true},clientPlacement={mode='local',teleports=1,target=target}}})do
 f=fixture('server');f.command('QueueCleanupCancelTest','Prepare',f.player,args)
 f.tick();assert(f.prepared==0 and f.teleports==0 and #f.messages==1 and f.messages[1].command=='Failed')
end
f=fixture('server');request(f);f.tick();f.now=30000;f.tick()
assert(f.prepared==0 and f.teleports==0 and f.messages[1].command=='Failed')
f=fixture('sp');f.start();f.tick();f.tick();f.now=500;f.tick();f.now=30000;f.tick()
assert(f.prepared==0 and f.teleports==1 and f.emitted.status=='failed'and f.emitted.reason:find('placement timed out',1,true))

-- Shared entry rejects stale/mismatched proofs before headwear cleanup or seeding.
for _,server in ipairs({false,true})do
 f=fixture(server and'server'or'sp')
 local mutations=0
 function f.player:setGodMod()mutations=mutations+1;error('unexpected scene mutation')end
 function f.player:getWornItems()mutations=mutations+1;error('unexpected headwear cleanup')end
 function f.player:getInventory()mutations=mutations+1;error('unexpected item seeding')end
 local proof={mode=server and'replica'or'local',teleports=server and 0 or 1,target=target}
 local ok,problem=pcall(f.real.prepare,f.player,'mask-after-removal',target,proof)
 assert(not ok and tostring(problem):find('arrival target differs',1,true)and mutations==0,tostring(problem))
 f:arrive(target)
 for _,bad in ipairs({false,{}, {mode=proof.mode,teleports=proof.teleports,target={x=99,y=98,z=0}},
  {mode=proof.mode,teleports=server and 1 or 0,target=target},
  {mode=server and'local'or'replica',teleports=proof.teleports,target=target}})do
  ok=pcall(f.real.prepare,f.player,'mask-after-removal',target,bad)
  assert(not ok and mutations==0)
 end
 -- Even valid setup records authority evidence before touching the scene.
 ok,problem=pcall(f.real.prepare,f.player,'mask-after-removal',target,proof)
 assert(not ok and tostring(problem):find('unexpected scene mutation',1,true)and mutations==1)
 assert(f.logs[#f.logs]:find('AUTHORITY_PLACEMENT',1,true))
 local evidence=placementEvent(f,'AUTHORITY_PLACEMENT')
 exactKeys(evidence,{'case','actor','target','proof'})
 assert(evidence.case=='mask-after-removal'and evidence.actor=='client1'and f.F.same(evidence.target,target))
 assert(evidence.proof==proof)
end

-- Fresh client admission checks reject drift and Prepared records for another target.
for _,kind in ipairs({'sp','mp'})do
for _,bad in ipairs({'drift','binding'})do
 f=fixture(kind);f.start();f.tick();f.tick();f.now=500;f.tick();f:arrive(f.target)
 f.now=501;f.tick();f.now=1001;f.tick()
 if kind=='mp'then
  assert(f.prepared==0 and f.messages[1].command=='Prepare')
  f.state={player=f.player,ids={case='mask-after-removal',placement=f.P.target(f.target),baseline={}}}
  f.serverCommand('QueueCleanupCancelTest','Prepared',f.state.ids)
 else assert(f.prepared==1)end
 f.resolve=true;f.now=1002;f.tick();f.dark=false
 if kind=='mp'then
  assert(f.messages[2].command=='Baseline')
  f.serverCommand('QueueCleanupCancelTest','Baselined',f.F.snapshot())
 end
 if bad=='drift'then f:arrive({x=100,y=100,z=0})else f.state.ids.placement={x=99,y=98,z=0}end
 f.now=1003;f.tick()
 assert(f.emitted.status=='failed'and f.emitted.reason:find('left prepared placement before admission',1,true))
 for _,log in ipairs(f.logs)do assert(not log:find(' ADMITTED ',1,true),'stale placement admitted native work')end
end
end
print('QUEUE_CLEANUP_CANCEL_PLACEMENT_PASS')
