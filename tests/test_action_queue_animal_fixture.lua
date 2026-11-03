-- Exercise the saved fixture with the real shared asynchronous placement helper.
local now, actorX, actorY, teleports, spawned, waits, staleSquare
local function square(x,y,z)
 return {getX=function()return x end,getY=function()return y end,getZ=function()return z end,
  isFree=function()return true end,getRoom=function()end,getFloor=function()return {}end,
  getObjects=function()return {size=function()return 1 end}end,canReachTo=function(_,other)return math.abs(other:getX()-x)+math.abs(other:getY()-y)<=1 end}
end
local p={setGodMod=function()end,setGhostMode=function()end,setAutoDrink=function()end,
 isLocalPlayer=function()return true end,hasTimedActions=function()return false end,
 isPlayerMoving=function()return false end,getPath2=function()end}
function p:getSquare()return square(math.floor(actorX),math.floor(actorY),0)end
function p:getCurrentSquare()return staleSquare or self:getSquare()end
function p:getX()return actorX end;function p:getY()return actorY end;function p:getZ()return 0 end
function p:getDeferredMovement(probe)return probe end
Vector2={new=function()return {getX=function()return 0 end,getY=function()return 0 end}end}
ISTimedActionQueue={getTimedActionQueue=function()return {queue={}}end}
local target
function p:teleportTo(x,y,z)teleports=teleports+1;target={x=x,y=y,z=z}end
getCell=function()return {getGridSquare=function(_,x,y,z)return square(x,y,z)end}end
getSquare=square
getTimestampMs=function()return now end
isClient=function()return false end
isServer=function()return false end
Events={AddXP={Add=function()end}}
AnimalDefinitions={getDef=function()return {getBreedByName=function()return {}end}end}
addAnimal=function()spawned=spawned+1;error('fixture reached native spawn')end
local output=print
print=function(text)if text:find('PLACEMENT_WAIT',1,true)then waits=waits+1 end end
require=function(name)
 if name=='QueueEnergyPlacement'then return assert(loadfile(ProjectRoot..'/tests/native_queue/support/QueueEnergyPlacement.lua'))()end
 if name=='QueueHealthEvents'then return {encode=function()return '{}'end}end
end
for _,case in ipairs({'pet-success','pet-invalid'})do
for _,offset in ipairs({0,.5})do
 now,actorX,actorY,teleports,spawned,waits,staleSquare=100,100.5,100.5,0,0,0,nil
 local released=0;local previous={animal={getBehavior=function()return {setBlockMovement=function(_,value)assert(value==false);released=released+1 end}end}}
 local f=assert(loadfile(ProjectRoot..'/tests/native_queue/animal-terminal/shared/QueueAnimalTerminal.lua'))()
 assert(not f.prepare(p,case,previous)and teleports==0 and spawned==0 and released==0,'fixture must earn a quiet pre-teleport window')
 now=599;assert(not f.prepare(p,case,previous)and teleports==0)
 now=600;assert(not f.prepare(p,case,previous)and teleports==1 and spawned==0)
 assert(not f.prepare(p,case,previous)and teleports==1 and spawned==0 and waits==1)
 now=5100;assert(not f.prepare(p,case,previous)and waits==2,'waiting diagnostics must be bounded')
 assert(not f.at(p,target),'old tile must not satisfy asynchronous arrival')
 actorX,actorY=target.x+offset,target.y+offset;staleSquare=square(100,100,0)
 assert(not f.at(p,target),'stale currentSquare cannot prove arrival')
 now=5600;assert(not f.prepare(p,case,previous)and spawned==0)
 staleSquare=nil;assert(f.at(p,target),'native corner and centre positions belong to the requested tile')
 assert(not f.prepare(p,case,previous)and spawned==0 and released==0,'arrival requires its own stable window')
 now=6099;assert(not f.prepare(p,case,previous)and spawned==0)
 now=6100;local ok,problem=pcall(f.prepare,p,case,previous)
 assert(not ok and tostring(problem):find('fixture reached native spawn',1,true)
  and spawned==1 and teleports==1 and released==1,'settled arrival must advance once without another teleport')
end
end
-- A Host server observes ordinary replication and never teleports the remote actor.
isServer=function()return true end
now,actorX,actorY,teleports,spawned,waits,staleSquare=100,100.5,100.5,0,0,0,nil
local remote={x=98,y=98,z=0}
local serverFixture=assert(loadfile(ProjectRoot..'/tests/native_queue/animal-terminal/shared/QueueAnimalTerminal.lua'))()
assert(not serverFixture.prepare(p,'pet-success',nil,remote)and teleports==0 and spawned==0)
assert(not pcall(serverFixture.prepare,p,'pet-success',nil,{x=99,y=98,z=0}),'server target cannot change while waiting')
actorX,actorY=98,98
assert(not serverFixture.prepare(p,'pet-success',nil,remote),'server must earn a stable replication window')
now=600;local arrived,problem=pcall(serverFixture.prepare,p,'pet-success',nil,remote)
assert(not arrived and tostring(problem):find('fixture reached native spawn',1,true)and teleports==0 and spawned==1,
 'server must wait for exact replicated arrival without moving the remote actor')
now,actorX,actorY,spawned=100,100.5,100.5,0
local stalled=assert(loadfile(ProjectRoot..'/tests/native_queue/animal-terminal/shared/QueueAnimalTerminal.lua'))()
assert(not stalled.prepare(p,'pet-success',nil,remote));now=30100
local ok,diagnostic=pcall(stalled.prepare,p,'pet-success',nil,remote)
assert(not ok and tostring(diagnostic):find('placement timed out',1,true)and tostring(diagnostic):find('currentSquare=',1,true)
 and spawned==0 and teleports==0,'stalled authority arrival must fail with bounded actual-square diagnostics')
isServer=function()return false end
print=output
print('PASS saved animal fixture: quiet window, one local teleport, delayed dual-square arrival, stable replica arrival and bounded diagnostics')

local function read(path)local file=assert(io.open(path));local text=file:read('*a');file:close();return text:gsub('\r','')end
local source=read(ProjectRoot..'/tests/native_queue/animal-terminal/client/ZZAnimalTerminal.lua')
-- Run the saved fixture's own registration against the actual disabled lifecycle.
PZSurvivorToolkit={Settings={actionQueue=function()return false end}}
ISTimedActionQueue={queues={}};ISQueueActionsAction={start=function()end}
require=function()end
isClient=function()return false end
local lifecycle=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua'))()
local tracked,other={character={}},{character={}}
local observed=0
local registration=assert(source:match("(T.ActionQueueLifecycle.registerObserver%('fixture%.animal%-terminal'.-finish=finish%}%))"))
assert(assert(loadstring('local T,tracks,started,finish=...;return '..registration))(
 PZSurvivorToolkit,{[tracked]={}},function()end,function(_,_,ok)assert(ok);observed=observed+1 end))
for _,phase in ipairs({'perform','complete'})do
 assert(lifecycle.begin(tracked,phase))
 lifecycle.finish(tracked,phase,true)
end
assert(observed==2 and not lifecycle.begin(other,'perform'),
 'saved fixture must observe disabled-mode callbacks without acquiring authority over untracked actions')
print('PASS saved animal fixture opts tracked native callbacks into observation with the queue disabled')

if NativeActionRoot then
 local baseSource=read(NativeActionRoot..'/shared/TimedActions/ISBaseTimedAction.lua')
 local adjustSource=assert(baseSource:match('(function ISBaseTimedAction:adjustMaxTime%(.-\nend)'))
 local base={}
 assert(loadstring('local ISBaseTimedAction=...;\n'..adjustSource,'@media/lua/shared/TimedActions/ISBaseTimedAction.lua'))(base)
 MoodleType={UNHAPPY=1,DRUNK=2}
 BodyPartType={Hand_L=0,ForeArm_R=0,ToIndex=function()return 0 end,FromIndex=function()return 0 end}
 local actor={getMoodles=function()return {getMoodleLevel=function()return 0 end}end,
  getBodyDamage=function()return {getBodyPart=function()return {getPain=function()return 0 end}end}end,
  getTimedActionTimeModifier=function()return 1.25 end}
 getFilenameOfClosure=function(callback)return debug.getinfo(callback,'S').source end
 local proof=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
 local first=assert(source:find('local function started(',1,true))
 local last=assert(source:find('local function finish(',first,true))
 local action={maxTime=400,character=actor,adjustMaxTime=base.adjustMaxTime,getJobDelta=function()return .2 end}
 local row={duration=400,name='body'}
 local started,sample=assert(loadstring('local tracks,nativeAdjust,Proof,now,snap,raw,case=...\n'
  ..source:sub(first,last-1)..'\nreturn started,sampleNative'))(
   {[action]=row},base.adjustMaxTime,proof,function()return 100 end,function()return {}end,function()end,function()return 'pet-success'end)
 started(action)
 action.maxTime=base.adjustMaxTime(action,action.maxTime)
 action.action={getCurrentTime=function()return 10 end}
 sample(action,row,'allocated')
 assert(row.timing.constructor==400 and row.timing.expectedAdjusted==500 and row.timing.allocated==500)
 action.maxTime=510;sample(action,row,'started')
 assert(row.timing.allocated==500 and row.timing.samples[2].luaMaxTime==510,
  'fixture must distinguish immutable native construction, create adjustment and later native samples')
 print('PASS saved animal fixture records actual native maxTime adjustment and later timing samples separately')
end
