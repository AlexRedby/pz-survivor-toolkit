-- The real common placement helper, including Kahlua's absent global next.
local path=ProjectRoot..'/tests/native_queue/support/QueueEnergyPlacement.lua'
local function fixture(server)
 local f={now=0,server=server or false,teleports=0,logs={},queue={},x=100.5,y=100.5,z=0,
  localPlayer=true,moving=false,timed=false,deferredX=0,deferredY=0}
 local function square(x,y,z)
  return {getX=function()return x end,getY=function()return y end,getZ=function()return z end,
   isFree=function()return true end,getRoom=function()end,getObjects=function()return {size=function()return 1 end}end}
 end
 f.square=square(100,100,0);f.current=f.square
 f.player={}
 for _,key in ipairs({'X','Y','Z'})do f.player['get'..key]=function()return f[key:lower()]end end
 function f.player:getSquare()return f.square end
 function f.player:getCurrentSquare()return f.current end
 function f.player:isLocalPlayer()return f.localPlayer end
 function f.player:isPlayerMoving()return f.moving end
 function f.player:hasTimedActions()return f.timed end
 function f.player:getPath2()return f.path end
 function f.player:getDeferredMovement(out)
  out.x,out.y=f.deferredX,f.deferredY;return out
 end
 function f.player:teleportTo(x,y,z)f.teleports=f.teleports+1;f.command={x=x,y=y,z=z}end
 function f:arrive(target,offset)
  self.x,self.y,self.z=target.x+(offset or 0),target.y+(offset or 0),target.z
  self.square=square(target.x,target.y,target.z);self.current=self.square
 end
 local env={isServer=function()return f.server end,getTimestampMs=function()return f.now end,
  getCell=function()return {getGridSquare=function(_,x,y,z)return square(x,y,z)end}end,
  Vector2={new=function()return {getX=function(v)return v.x end,getY=function(v)return v.y end}end},
  ISTimedActionQueue={getTimedActionQueue=function()return {queue=f.queue}end},
  print=function(text)f.logs[#f.logs+1]=text end}
 setmetatable(env,{__index=function(_,key)if key~='next'then return _G[key]end end})
 assert(env.next==nil)
 local chunk=assert(loadfile(path));setfenv(chunk,env);f.P=chunk()
 return f
end
local function fails(fn,text)
 local ok,problem=pcall(fn);assert(not ok and tostring(problem):find(text,1,true),tostring(problem))
end
for _,offset in ipairs({0,.5})do
 local f=fixture();local target=f.P.choose(f.player)
 assert(f.teleports==0,'selection must not move actor')
 local state=f.P.begin(f.player,target)
 assert(not f.P.poll(state)and f.teleports==0,'first quiet sample is not settled')
 f.now=499;assert(not f.P.poll(state)and f.teleports==0)
 f.now=500;assert(not f.P.poll(state)and f.teleports==1)
 assert(f.command.x==target.x and f.command.y==target.y,'issue native integer placement once')
 f.now=1000;assert(not f.P.poll(state)and f.teleports==1,'coordinates and squares still refer to old tile')
 f:arrive(target,offset)
 f.now=1001;assert(not f.P.poll(state))
 f.now=1500;assert(not f.P.poll(state))
 f.now=1501;local proof=assert(f.P.poll(state))
 assert(proof.mode=='local'and proof.teleports==1 and proof.quietMs==500 and proof.stableMs==500)
 assert(proof.actual.square.x==target.x and proof.actual.currentSquare.x==target.x and f.P.at(f.player,target))
 assert(f.P.poll(state)==proof and f.teleports==1,'completed polling must not repeat movement')
end
-- Neither stale square nor stale coordinates can prove arrival.
for _,missing in ipairs({'square','current','coordinates','z'})do
 local f=fixture(true);local target={x=98,y=98,z=0};local state=f.P.observe(f.player,target)
 f:arrive(target,.5)
 if missing=='square'then f.square=nil elseif missing=='current'then f.current=nil
 elseif missing=='coordinates'then f.x=100.5 else f.z=.5 end
 assert(not f.P.at(f.player,target)and not f.P.poll(state))
 f.now=1000;assert(not f.P.poll(state)and f.teleports==0)
 f:arrive(target,0);f.now=1001;assert(not f.P.poll(state))
 f.now=1501;local proof=assert(f.P.poll(state))
 assert(proof.mode=='replica'and proof.teleports==0 and f.teleports==0)
end
-- Residual native animation and unsettled work delay the one teleport.
for _,busy in ipairs({'deferredX','deferredY','moving','timed','path','queue'})do
 local f=fixture();local state=f.P.begin(f.player)
 if busy=='queue'then f.queue[1]={}elseif busy=='path'then f.path={}elseif busy=='moving'or busy=='timed'then f[busy]=true else f[busy]=.01 end
 assert(not f.P.poll(state));f.now=1000;assert(not f.P.poll(state)and f.teleports==0)
 f.deferredX,f.deferredY,f.moving,f.timed,f.path,f.queue=0,0,false,false,nil,{}
 f.now=1001;assert(not f.P.poll(state));f.now=1500;assert(not f.P.poll(state))
 f.now=1501;assert(not f.P.poll(state)and f.teleports==1)
end
local f=fixture();local state=f.P.begin(f.player)
assert(not f.P.poll(state));f.now=500;assert(not f.P.poll(state))
f:arrive(state.target,.5);f.now=501;assert(not f.P.poll(state))
f.now=1000;f.x=f.x+.01171875;assert(not f.P.poll(state),'sub-tile residual motion resets settlement interval')
f.now=1499;assert(not f.P.poll(state));f.now=1500;assert(f.P.poll(state)and f.teleports==1)
-- Ownership, target identity and original deadline are hard boundaries.
f=fixture(true);fails(function()f.P.begin(f.player)end,'owning local client')
f=fixture();f.localPlayer=false;fails(function()f.P.begin(f.player)end,'owning local client')
f=fixture();state=f.P.begin(f.player);f.localPlayer=false;fails(function()f.P.poll(state)end,'ownership changed')
f=fixture();state=f.P.begin(f.player);state.target.x=state.target.x+1;fails(function()f.P.poll(state)end,'target changed')
f=fixture();state=f.P.begin(f.player);assert(not f.P.poll(state));f.now=30000
fails(function()f.P.poll(state)end,'placement timed out mode=local phase=quiet target=')
assert(f.teleports==0 and #f.logs==1,'bounded timeout must not pin actor or flood logs')
for _,target in ipairs({{}, {x=1,y=2,z=.5}, {x=1/0,y=2,z=0}, {x=0/0,y=2,z=0}, {x=1,y=2,z=0,foreign=true}})do
 fails(function()f.P.target(target)end,'placement target');assert(not f.P.at(f.player,target))
end
-- Keep the explicit migration boundary compatible, without treating it as a proof.
f=fixture(true);local legacySquare=f.P(f.player)
assert(f.teleports==1 and legacySquare:getX()==f.command.x-.5 and legacySquare:getY()==f.command.y-.5)
assert(not f.P.at(f.player,{x=legacySquare:getX(),y=legacySquare:getY(),z=legacySquare:getZ()}),
 'legacy synchronous return still requires migration; it is not an arrival receipt')
print('QUEUE_FIXTURE_PLACEMENT_PASS')
