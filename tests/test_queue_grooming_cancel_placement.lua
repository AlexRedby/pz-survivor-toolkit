-- Run the real setup scripts with delayed native placement and authority replicas.
local root=ProjectRoot..'/tests/native_queue/'
local function fixture(kind)
 local server=kind=='server';local client=kind=='mp'
 local f={now=0,teleports=0,prepared=0,messages={},logs={},rows={},x=100.5,y=100.5,z=0}
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
 function p:isFemale()return false end
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
 env.ISTrimBeard={};env.ISCutHair={};env.ISDyeHair={}
 env.ISCharacterScreen={onTrimBeard=function()error('unexpected beard admission')end,onCutHair=function()error('unexpected haircut admission')end}
 env.ISInventoryPaneContextMenu={onDyeHair=function()error('unexpected dye admission')end}
 for _,name in ipairs({'new','getDuration','isValid','start','stop','update','perform','complete'})do env.ISTrimBeard[name]=function()end end
 env.getCore=function()return {setOptionPauseOnFocusloss=function()end,setOptionAutoDrink=function()end}end
 env.PZSurvivorToolkit={ActionQueueLifecycle={registerObserver=function()return true end}}
 env.PZAPI={ModOptions={getOptions=function()return {getOption=function()return {setValue=function()end}end}end}}
 env.print=function(value)f.logs[#f.logs+1]=value end
 env.sendServerCommand=function(_,_,command,value)f.messages[#f.messages+1]={command=command,value=value}end
 env.sendClientCommand=function(_,command,value)f.messages[#f.messages+1]={command=command,value=value}end
 setmetatable(env,{__index=_G});f.env=env
 local function load(path)local chunk=assert(loadfile(root..path));setfenv(chunk,env);return chunk()end
 f.P=load('support/QueueEnergyPlacement.lua')
 env.require=function(name)if name=='QueueEnergyPlacement'then return f.P end;return {}end
 local real=load('grooming-cancel/shared/QueueGroomingCancel.lua')
 local F={same=real.same,sameSetup=real.sameSetup,held=real.held,baseCase=real.baseCase,active=real.active,moving=real.moving};f.F=F
 function F.prepare(actor,case,previous,target,proof)
  assert(actor==p and f.P.at(actor,target),'scene must follow actual arrival')
  assert(proof.mode==(server and'replica'or'local'))
  f.prepared=f.prepared+1
  local ids={case=case,placement=f.P.target(target),baseline={}}
  f.state={player=p,ids=ids};return f.state
 end
 function F.resolve()return f.resolve and f.state or nil end
 function F.snapshot()return {}end
 function F.refresh()return false end
 env.require=function(name)
  local modules={QueueEnergyPlacement=f.P,QueueGroomingCancel=F,
   QueueHealthEvents={encode=function(value)f.rows[#f.rows+1]=value;return '{}'end,emit=function(value)f.emitted=value end},
   QueueTestSelection={cases={'borrowed-scissors','style-no-tool'},mode='toolkit',kind=client and'mp'or'sp'},
   ['PZSurvivorToolkit/SourceProof']={closure=function()return true end},
   QueuePreflight={onGameStart=function(_,fn)f.start=fn end,onTick=function(_,fn)f.tick=fn end}}
  return modules[name]or{}
 end
 -- Shared prepare requires these modules at load time; reload it after routing.
 f.real=load('grooming-cancel/shared/QueueGroomingCancel.lua')
 load(server and'grooming-cancel/server/ZZGroomingCancelServer.lua'or'grooming-cancel/client/ZZGroomingCancel.lua')
 return f
end

-- Local setup waits for quiet, sends exactly one teleport, and needs both squares.
for _,kind in ipairs({'sp','mp'})do
 local f=fixture(kind);f.start();f.tick();f.tick();assert(f.prepared==0 and f.teleports==0)
 f.now=500;f.tick();assert(f.prepared==0 and f.teleports==1 and #f.messages==0)
 f.now=1000;f.tick();assert(f.prepared==0 and f.teleports==1)
 f:arrive(f.target);f.current=nil;f.now=1001;f.tick();assert(f.prepared==0)
 f.current=f.square;f.now=1002;f.tick();assert(f.prepared==0)
 f.now=1502;f.tick()
 if kind=='sp'then assert(f.prepared==1 and #f.messages==0)
 else
  assert(f.prepared==0 and #f.messages==1 and f.messages[1].command=='Prepare')
  local args=f.messages[1].value
  assert(args.case=='borrowed-scissors'and f.F.same(args.target,f.target))
  assert(args.clientPlacement.mode=='local'and args.clientPlacement.teleports==1)
 end
 f.now=2002;f.tick();assert(f.teleports==1)
end

local target={x=98,y=98,z=0}
local function request(f,proof)
 f.command('GroomingCancelTest','Prepare',f.player,{case='borrowed-scissors',target=target,
  clientPlacement=proof or{mode='local',teleports=1,target=target}})
end
-- Authority cannot seed equipment until its own replica has settled.
local f=fixture('server');request(f)
f.tick();f.now=1000;f.tick();assert(f.prepared==0 and f.teleports==0 and #f.messages==0)
f:arrive(target);f.current=nil;f.now=1001;f.tick();assert(f.prepared==0)
f.current=f.square;f.now=1002;f.tick();f.now=1501;f.tick();assert(f.prepared==0)
f.now=1502;f.tick();assert(f.prepared==1 and f.teleports==0 and #f.messages==1)
assert(f.messages[1].command=='Prepared'and f.F.same(f.messages[1].value.placement,target))
f.now=2002;f.tick();assert(f.prepared==1 and f.teleports==0)

-- Missing, foreign-role and target-mismatched receipts never start scene work.
for _,proof in ipairs({{}, {mode='replica',teleports=0,target=target},
 {mode='local',teleports=0,target=target},
 {mode='local',teleports=1,target={x=99,y=98,z=0}}})do
 f=fixture('server');request(f,proof);f.tick()
 assert(f.prepared==0 and f.teleports==0 and #f.messages==1 and f.messages[1].command=='Failed')
end
for _,command in ipairs({'Prepare','Baseline','Checkpoint','Verify'})do
 f=fixture('server');request(f)
 f.command('GroomingCancelTest',command,f.player,{case='borrowed-scissors',target=target,clientPlacement={mode='local',teleports=1,target=target}})
 assert(f.prepared==0 and f.teleports==0 and f.messages[1].command=='Failed','pending prepare must reject overlapping requests')
end
for _,bad in ipairs({'actor','case'})do
 f=fixture('server')
 if bad=='actor'then function f.player:getUsername()return 'client2'end end
 f.command('GroomingCancelTest','Prepare',f.player,{case=bad=='case'and'style-no-tool'or'borrowed-scissors',
  target=target,clientPlacement={mode='local',teleports=1,target=target}})
 f.tick();assert(f.prepared==0 and f.teleports==0 and f.messages[1].command=='Failed')
end
f=fixture('server');request(f);f.tick();f.now=30000;f.tick()
assert(f.prepared==0 and f.teleports==0 and f.messages[1].command=='Failed')

-- Shared entry rejects stale/mismatched proofs before previous-case cleanup or seeding.
for _,server in ipairs({false,true})do
 f=fixture(server and'server'or'sp')
 local mutations=0
 function f.player:getInventory()mutations=mutations+1;error('unexpected scene mutation')end
 local proof={mode=server and'replica'or'local',teleports=server and 0 or 1,target=target}
 local ok,problem=pcall(f.real.prepare,f.player,'borrowed-scissors',{items={one=1}},target,proof)
 assert(not ok and tostring(problem):find('arrival target differs',1,true)and mutations==0)
 f:arrive(target)
 for _,bad in ipairs({{}, {mode=proof.mode,teleports=proof.teleports,target={x=99,y=98,z=0}},
  {mode=proof.mode,teleports=server and 1 or 0,target=target},
  {mode=server and'local'or'replica',teleports=proof.teleports,target=target}})do
  ok=pcall(f.real.prepare,f.player,'borrowed-scissors',{items={one=1}},target,bad)
  assert(not ok and mutations==0)
 end
 -- Even valid setup records authority evidence before touching the previous scene.
 ok,problem=pcall(f.real.prepare,f.player,'borrowed-scissors',{items={one=1}},target,proof)
 assert(not ok and tostring(problem):find('unexpected scene mutation',1,true)and mutations==1)
 assert(f.logs[#f.logs]:find('AUTHORITY_PLACEMENT',1,true))
end

-- Fresh client admission checks reject drift and Prepared records for another target.
for _,bad in ipairs({'drift','binding'})do
 f=fixture('sp');f.start();f.tick();f.tick();f.now=500;f.tick();f:arrive(f.target)
 f.now=501;f.tick();f.now=1001;f.tick();assert(f.prepared==1)
 f.resolve=true;f.now=1002;f.tick();f.dark=false
 if bad=='drift'then f:arrive({x=100,y=100,z=0})else f.state.ids.placement={x=99,y=98,z=0}end
 f.now=1003;f.tick()
 assert(f.emitted.status=='failed'and f.emitted.reason:find('left prepared placement before admission',1,true))
 for _,log in ipairs(f.logs)do assert(not log:find(' ADMITTED ',1,true),'stale placement admitted native work')end
end
print('QUEUE_GROOMING_CANCEL_PLACEMENT_PASS')
