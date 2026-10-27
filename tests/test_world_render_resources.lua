-- Offline guards for the disposable native resource fixture; no game launch.
local base=(ProjectRoot or '.')..'/tests/native_queue/world-render'
package.preload.QueueHealthEvents=function()return {encode=function()return '{}'end}end
local F=dofile(base..'/shared/WorldRenderFixture.lua')
local squares={}
local function square(x,name)
 local s={x=x}
 function s:getX()return self.x end
 function s:getY()return 0 end
 function s:getZ()return 0 end
 function s:TreatAsSolidFloor()return true end
 function s:canStand()return true end
 function s:isFree()return true end
 function s:isOutside()return true end
 function s:isVehicleIntersecting()return self.vehicle==true end
 function s:getRoom()return nil end
 function s:getFloor()return {getSprite=function()return {getName=function()return name end}end}end
 function s:isBlockedTo(next)return self.x==1 and next.x==2 end
 return s
end
function getCell()return {getGridSquare=function(_,x,y,z)if y==0 and z==0 then return squares[x]end end}end
for x=0,6 do squares[x]=square(x,'blends_street_01_'..(x%2))end
local player={getSquare=function()return squares[0]end}
local scene=assert(F.decalScene(player));assert(scene.x==2 and scene.dx==1 and scene.length==4,'Blocked edge or alternating paving mishandled')
for x=0,6 do squares[x]=square(x,'blends_natural_01_0')end
assert(F.decalScene(player)==nil,'Grass admitted')
for x=0,30 do squares[x]=square(x,'blends_street_01_0')end
scene=assert(F.decalScene(player));assert(scene.x+scene.length<=24,'Finder escaped bounded radius')
for x=0,6 do squares[x].vehicle=true end
scene=assert(F.decalScene(player));assert(scene.x>=8,'Vehicle or its one-tile margin admitted')

local config={suite='world-render',options={world_render_resources=true}}
package.preload.QueueTestSelection=function()return config end
local emitted,sent={},{}
local fakeF={module='WorldRenderTest',emit=function(e,v)emitted[#emitted+1]={e,v}end,prepare=function()return {getID=function()return 99 end}end}
package.loaded.WorldRenderFixture=fakeF
local handler
Events={OnClientCommand={Add=function(f)handler=f end}}
function isServer()return true end
local time=22.25
function getGameTime()return {getTimeOfDay=function()return time end,setTimeOfDay=function(_,v)time=v end}end
function sendServerCommand(player,module,command,value)sent[#sent+1]={command,value}end
local function actor(name,id)return {getUsername=function()return name end,getOnlineID=function()return id end}end
local a,b=actor('client1',1),actor('client2',2)
local function send(command,player)handler(fakeF.module,command,player,{})end
local function init()
 emitted={};sent={};dofile(base..'/server/ZZWorldRenderServer.lua')
 send('Prepare',a);send('Prepare',b);send('Ready',a);send('Ready',b)
end
init();send('ResourcesReady',a);assert(time==22.25,'Time changed before both clients were ready')
send('ResourcesReady',b);assert(time==12 and sent[#sent][1]=='ResourcesStart','Daylight phase did not start')
send('ResourcesDone',a);assert(time==12,'Time restored before both clients finished')
send('ResourcesDone',b);assert(time==22.25 and sent[#sent][1]=='ResourcesRestored','Original server time not restored')
assert(emitted[3][1]=='RESOURCE_TIME' and emitted[3][2].stage=='day','Missing day evidence')
assert(emitted[4][1]=='RESOURCE_TIME' and emitted[4][2].stage=='restored','Missing restored evidence')
send('ResourcesDone',a);assert(emitted[#emitted][1]=='FAIL','Duplicate completion admitted')
init();send('ResourcesReady',a);send('ResourcesReady',a);assert(emitted[#emitted][1]=='FAIL','Duplicate readiness admitted')
config.options.world_render_resources=false;init();send('ResourcesReady',a);assert(emitted[#emitted][1]=='FAIL' and time==22.25,'Disabled resource phase admitted')
print('WORLD_RENDER_RESOURCE_FIXTURE_CHECKS_PASS')
