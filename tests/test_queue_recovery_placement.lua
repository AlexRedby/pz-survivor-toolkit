-- Exercise the real setup protocols with delayed native placement snapshots.
local root=ProjectRoot..'/tests/native_queue/'
local function fixture(server)
 local f={now=0,teleports=0,prepared=0,messages={},logs={},x=100.5,y=100.5,z=0}
 local function square(x,y,z)
  return {getX=function()return x end,getY=function()return y end,getZ=function()return z end,
   isFree=function()return true end,getRoom=function()end,getObjects=function()return {size=function()return 1 end}end}
 end
 f.square=square(100,100,0);f.current=f.square
 local player={}
 f.player=player
 for _,key in ipairs({'X','Y','Z'})do player['get'..key]=function()return f[key:lower()]end end
 function player:getSquare()return f.square end
 function player:getCurrentSquare()return f.current end
 function player:getUsername()return 'client1'end
 function player:isLocalPlayer()return not server end
 function player:hasTimedActions()return false end
 function player:isPlayerMoving()return false end
 function player:isTimedActionInstant()return false end
 function player:getPath2()return nil end
 function player:getDeferredMovement(out)return out end
 function player:teleportTo(x,y,z)f.teleports=f.teleports+1;f.target={x=x,y=y,z=z}end
 function player:setGodMod()end
 function player:setGhostMode()end
 function player:setAutoDrink()end
 function f:arrive(target)
  self.x,self.y,self.z=target.x,target.y,target.z
  self.square=square(target.x,target.y,target.z);self.current=self.square
 end
 local env={}
 local function event(name)return {Add=function(fn)f[name]=fn end}end
 env.Events={OnClientCommand=event('command'),OnServerCommand=event('serverCommand'),
  OnTick=event('tick'),OnPostUIDraw=event('draw')}
 env.isServer=function()return server end;env.isClient=function()return false end
 env.isIngameState=function()return true end;env.getPlayer=function()return player end
 env.getTimestampMs=function()return f.now end
 env.getCell=function()return {getGridSquare=function(_,x,y,z)return square(x,y,z)end}end
 env.Vector2={new=function()return {getX=function()return 0 end,getY=function()return 0 end}end}
 env.ISTimedActionQueue={getTimedActionQueue=function()return {queue={}}end,add=function()error('unexpected action')end}
 env.getCore=function()return {setOptionPauseOnFocusloss=function()end,setOptionAutoDrink=function()end}end
 env.PZSurvivorToolkit={ActionQueueRecovery={},Settings={actionQueue=function()return true end}}
 env.PZAPI={ModOptions={getOptions=function()return {getOption=function()return {setValue=function()end}end}end}}
 env.print=function(value)f.logs[#f.logs+1]=value end
 env.sendServerCommand=function(_,_,command,value)f.messages[#f.messages+1]={command=command,value=value}end
 setmetatable(env,{__index=_G})
 local function load(path)local chunk=assert(loadfile(root..path));setfenv(chunk,env);return chunk()end
 f.P=load('support/QueueEnergyPlacement.lua')
 local F={}
 function F.prepare(actor,case,mode,target,proof)
  assert(actor==player and f.P.at(actor,target),'scene must follow actual arrival')
  assert(proof.mode==(server and'replica'or'local'))
  f.prepared=f.prepared+1
  return {player=player,ids={case=case,origin=target,placementProof=proof}}
 end
 function F.resolve()return nil end
 local modules={QueueEnergyPlacement=f.P,QueueRecovery=F,
  QueueHealthEvents={encode=function()return '{}'end,emit=function()end},
  QueueTestSelection={cases={'movement-cancel','clear-queue'},mode='toolkit',kind=server and'mp'or'sp'},
  QueuePreflight={onGameStart=function(_,fn)f.start=fn end,onTick=function(_,fn)f.tick=fn end}}
 env.require=function(name)return modules[name]or{}end
 load(server and'queue-recovery/server/ZZQueueRecoveryServer.lua'or'queue-recovery/client/ZZQueueRecovery.lua')
 return f
end

-- Client waits for quiet, sends one teleport, then waits for both squares.
local f=fixture(false)
f.start();f.tick();assert(f.prepared==0 and f.teleports==0)
f.now=500;f.tick();assert(f.prepared==0 and f.teleports==1)
f.now=1000;f.tick();assert(f.prepared==0 and f.teleports==1)
f:arrive(f.target);f.current=nil
f.now=1001;f.tick();assert(f.prepared==0)
f.current=f.square;f.now=1002;f.tick();assert(f.prepared==0)
f.now=1502;f.tick();assert(f.prepared==1 and f.teleports==1)
f.now=2002;f.tick();assert(f.prepared==1 and f.teleports==1)

-- Authority never moves a remote actor and waits its own full stable interval.
f=fixture(true)
local target={x=98,y=98,z=0}
f.command('QueueRecoveryTest','Prepare',f.player,{case='movement-cancel',placement=target,clientPlacement={mode='local',teleports=1,target=target}})
f.tick();f.now=1000;f.tick();assert(f.prepared==0 and f.teleports==0 and #f.messages==0)
f:arrive(target);f.current=nil
f.now=1001;f.tick();assert(f.prepared==0)
f.current=f.square;f.now=1002;f.tick();assert(f.prepared==0)
f.now=1501;f.tick();assert(f.prepared==0)
f.now=1502;f.tick();assert(f.prepared==1 and f.teleports==0 and #f.messages==1)
assert(f.messages[1].command=='Prepared'and f.messages[1].value.placementProof.mode=='replica')
f.now=2002;f.tick();assert(f.prepared==1)

-- A never-arriving replica fails at the original deadline without scene work.
f=fixture(true)
f.command('QueueRecoveryTest','Prepare',f.player,{case='movement-cancel',placement=target,clientPlacement={mode='local',teleports=1,target=target}})
f.tick();f.now=30000;f.tick()
assert(f.prepared==0 and f.teleports==0 and #f.messages==1 and f.messages[1].command=='Failed')

-- The shared scene entrypoint also rejects stale placement before any mutation.
local env={require=function(name)assert(name=='QueueEnergyPlacement');return {target=function(t)return t end,at=function()return false end}end}
setmetatable(env,{__index=_G})
local chunk=assert(loadfile(root..'queue-recovery/shared/QueueRecovery.lua'));setfenv(chunk,env)
local F=chunk()
local ok,problem=pcall(F.prepare,{},'clear-queue','toolkit',target,{mode='local'})
assert(not ok and tostring(problem):find('left settled placement',1,true))
print('QUEUE_RECOVERY_PLACEMENT_PASS')
