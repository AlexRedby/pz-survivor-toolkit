local events, opts = {}, {}
Events = setmetatable({}, {__index=function(t,k)
 local e={Add=function(fn) events[k]=fn end};rawset(t,k,e);return e
end})
local options={addTitle=function() end}
function options:addTickBox(id,_,value)
 local o={value=value,getValue=function(self) return self.value end};opts[id]=o;return o
end
function options:addComboBox(id)
 local o={value=1,items=0}
 function o:addItem(_,default) self.items=self.items+1;if default then self.value=self.items end end
 function o:getValue() return self.value end
 opts[id]=o;return o
end
PZSurvivorToolkit={}
PZAPI={ModOptions={getOptions=function() return options end}}
local originData=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleLampOrigins.lua')
require=function(name) if name=='PZSurvivorToolkit/VehicleLampOrigins' then return originData end end
getText=function(k) return k end
getActivatedMods=function() return {contains=function() return true end} end
ReverseDriveLights={REVERSE_DISTANCE=36,REVERSE_INTENSITY=1,Client={players={}}}
local function vec(x,y,z)
 return {x=function() return x end,y=function() return y end,z=function() return z end}
end
Vector3f={new=function() return {} end}
local lights, removed, count={}, {}, 0
IsoLightSource={new=function(x,y,z,r,g,b,radius)
 local s={x=x,y=y,z=z,r=r,g=g,b=b,radius=radius}
 for _,v in ipairs({'R','G','B'}) do s['set'..v]=function(self,value) self[v:lower()]=value end end
 return s
end}
local cell={getVehicles=function() return {iterator=function() local once=false;return {hasNext=function() return not once end,next=function() once=true;return Vehicle end} end} end}
function cell:getLamppostPositions() return {contains=function(_,s) return lights[s]==true end} end
function cell:addLamppost(s) assert(not lights[s]);lights[s]=true;count=count+1 end
function cell:removeLamppost(s) assert(lights[s],'must remove owned active source');lights[s]=nil;removed[s]=true;count=count-1 end
getCell=function() return cell end
getNumActivePlayers=function() return 1 end
local p={isDead=function() return false end,getZ=function() return 0 end,getX=function() return 0 end,getY=function() return 0 end}
getSpecificPlayer=function() return p end
local bulbs={}
for _,id in ipairs({'HeadlightLeft','HeadlightRight','HeadlightRearLeft','HeadlightRearRight'}) do
 local bulb={condition=100,getCondition=function(self) return self.condition end}
 local light={active=true,getActive=function(self) return self.active end}
 bulbs[id]={item=bulb,light=light,getInventoryItem=function(self) return self.item end,getLight=function(self) return self.light end}
end
Vehicle={x=0,y=0,power=1,on=true,removed=false,
 getSquare=function() return true end,isRemovedFromWorld=function(self) return self.removed end,
 getZ=function() return 0 end,getX=function(self) return self.x end,getY=function(self) return self.y end,
 getBatteryCharge=function(self) return self.power end,getHeadlightsOn=function(self) return self.on end,
 modelName='Vehicles_CarNormal',scale=1,modelOffset=vec(0,0,0),extents=vec(2,1,4),rotate=vec(0,0,0),
 getScript=function(self) return {
  getExtents=function() return self.extents end,getModelScale=function() return self.scale end,
  getModelOffset=function() return self.modelOffset end,
  getModel=function() return {getFile=function() return self.modelName end,getRotate=function() return self.rotate end} end,
 } end,
 getPartById=function(_,id) return bulbs[id] end,
 getWorldPos=function(self,x,_,z,out)
  out.x=function() return self.x+x end;out.y=function() return self.y+z end
 end}
getTimestampMs=function() return 0 end
dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleLighting.lua')
local L=PZSurvivorToolkit.VehicleLighting
L.update();assert(count==4 and ReverseDriveLights.REVERSE_DISTANCE==12 and ReverseDriveLights.REVERSE_INTENSITY==.3)
local state=L.states[Vehicle];local old=state.lights.frontLeft.source
L.update();assert(count==4 and state.lights.frontLeft.source==old,'stationary sources reused')
Vehicle.x=2;L.update();assert(removed[old] and count==4,'movement must remove registered JNI source')
local stale=state.lights.frontLeft.source
lights[stale]=nil;count=count-1
-- Native chunk unload removes a source independently; removal is idempotent.
local nativeRemove=cell.removeLamppost
function cell:removeLamppost(s) if lights[s] then nativeRemove(self,s) end end
L.update();assert(state.lights.frontLeft.source~=stale and count==4,'re-register native-removed parked light')
local weak=state.lights.frontLeft.source.r
opts.VehicleLightSpill.value=4;L.update();assert(state.lights.frontLeft.source.r>weak and count==4)
ReverseDriveLights.Client.players[0]={vehicle=Vehicle};L.update();assert(state.lights.rearLeft.radius==3 and state.lights.rearLeft.source.g>.04)
ReverseDriveLights.Client.players[0]=nil;L.update();assert(state.lights.rearLeft.radius==2 and state.lights.rearLeft.source.g<.01,'restore red tail spill')
bulbs.HeadlightLeft.item.condition=0;L.update();assert(count==3,'broken bulb must not emit')
bulbs.HeadlightLeft.item.condition=100
Vehicle.power=0;L.update();assert(count==0 and next(L.states)==nil,'battery shutdown cleanup')
Vehicle.power=1;L.update();assert(count==4)
Vehicle.on=false;L.update();assert(count==0,'off cleanup')
Vehicle.on=true;L.update();assert(count==4)
opts.VehicleLightSpill.value=1;L.update();assert(count==0,'disable cleanup')
opts.VehicleLightSpill.value=3;L.update();assert(count==4)
Vehicle.removed=true;L.update();assert(count==0,'removed vehicle cleanup')
Vehicle.removed=false;Vehicle.x=100;L.update();assert(count==0,'unloaded/distant cleanup')
Vehicle.x=0;L.update();assert(count==4);events.OnMainMenuEnter();assert(count==0,'world/menu cleanup')
opts.VehicleReverseLight.value=1;L.configureReverse();assert(ReverseDriveLights.REVERSE_DISTANCE==8)
opts.VehicleReverseLight.value=3;L.configureReverse();assert(ReverseDriveLights.REVERSE_DISTANCE==36 and ReverseDriveLights.REVERSE_INTENSITY==1,'original compatibility preset')
print('PASS vehicle lighting: movement, power, bulbs, removal, options and reverse-state cleanup')

-- Workload: unlit parking lots must not reread every local player's pose per car.
-- Lit cars share only this synchronous update's player/script/list reads; native
-- source membership stays checked, including native removal between updates.
do
 local originalVehicles, originalPositions = cell.getVehicles, cell.getLamppostPositions
 local originalCount, originalPlayer = getNumActivePlayers, getSpecificPlayer
 local vehicles, playerReads, scriptReads, listReads = {}, 0, 0, 0
 local players = {{x=0,y=0,z=0}, {x=200,y=0,z=1}}
 for _,player in ipairs(players) do
  function player:isDead() return self.dead == true end
  function player:getX() playerReads=playerReads+1;return self.x end
  function player:getY() playerReads=playerReads+1;return self.y end
  function player:getZ() playerReads=playerReads+1;return self.z end
 end
 getNumActivePlayers=function() return #players end
 getSpecificPlayer=function(i) return players[i+1] end
 cell.getVehicles=function() return {iterator=function()
  local index=0
  return {hasNext=function() return index<#vehicles end,next=function() index=index+1;return vehicles[index] end}
 end} end
 cell.getLamppostPositions=function(self) listReads=listReads+1;return originalPositions(self) end
 for i=1,512 do vehicles[i]=setmetatable({on=false,x=i,y=0}, {__index=Vehicle}) end
 L.update()
 assert(count==0 and playerReads==0 and listReads==0,'unlit lot must skip player and registered-light reads')
 local function car(x,z)
  return setmetatable({on=true,x=x,y=0,z=z,
   getZ=function(self) return self.z end,
   getScript=function(self) scriptReads=scriptReads+1;return Vehicle.getScript(self) end}, {__index=Vehicle})
 end
 local first,second,upper,distant=car(0,0),car(2,0),car(200,1),car(200,0)
 vehicles[#vehicles+1]=first;vehicles[#vehicles+1]=second
 vehicles[#vehicles+1]=upper;vehicles[#vehicles+1]=distant
 local foreign=IsoLightSource.new(0,0,0,1,1,1,10)
 cell:addLamppost(foreign)
 L.update()
 assert(count==13 and not L.states[distant],'split local players and floor/distance filtering')
 assert(playerReads==6 and scriptReads==3 and listReads==1,'share pose/script/list reads within one lighting update')
 local saved=L.states[first].lights.frontLeft.source
 playerReads,scriptReads,listReads=0,0,0
 L.update()
 assert(playerReads==6 and scriptReads==3 and listReads==1 and L.states[first].lights.frontLeft.source==saved,
  'stationary workload must reuse native sources without repeated snapshot reads')
 players[2].x=600;L.update()
 assert(not L.states[upper] and count==9,'next update reads fresh second-player movement')
 players[1].z=2;L.update()
 assert(count==1 and lights[foreign],'floor changes remove only owned sources on the next update')
 players[1].z=0;L.update();assert(count==9,'returning players rediscover lights')
 players[1].dead=true;L.update();assert(count==1,'dead players do not keep lights alive')
 players[1].dead=false;L.update();assert(count==9)
 opts.VehicleLightSpill.value=1;playerReads,listReads=0,0;L.update()
 assert(count==1 and lights[foreign] and playerReads==0 and listReads==0,'disabled spill skips native discovery and preserves foreign lights')
 opts.VehicleLightSpill.value=3;L.update();assert(count==9)
 L.clear();assert(count==1 and lights[foreign]);cell:removeLamppost(foreign)
 cell.getVehicles,cell.getLamppostPositions=originalVehicles,originalPositions
 getNumActivePlayers,getSpecificPlayer=originalCount,originalPlayer
 print('PASS vehicle lighting workload: 512 unlit cars skip pose reads; three lit cars share six coordinate reads and one native list read, with fresh movement/floor/death and foreign-light ownership')
end

-- The spill feature has no mandatory dependency on Reverse Drive Lights.
L.clear()
getActivatedMods=function() return {contains=function() return false end} end
require=function(name) if name=='PZSurvivorToolkit/VehicleLampOrigins' then return originData end;assert(name=='PZSurvivorToolkit/Settings','absent mod must not be required') end
dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/VehicleLighting.lua')
PZSurvivorToolkit.VehicleLighting.update();assert(count==4)
PZSurvivorToolkit.VehicleLighting.clear();assert(count==0)
print('PASS vehicle spill without Reverse Drive Lights')

-- Shape changes preserve raw power, colour/activation and condition scaling.
local current=PZSurvivorToolkit.VehicleLighting
local md={highBeamsOn=false}
NepHBO7={getModData=function() return md end,options={alwaysOn={getValue=function() return false end}}}
local originalCalls=0
function NepHBO7.UpdateLights(v)
 originalCalls=originalCalls+1
 for _,id in ipairs({'HeadlightLeft','HeadlightRight'}) do
  v:getPartById(id):createSpotLight(id=='HeadlightLeft' and .5 or -.5,2,36,.75,.96,100)
 end
end
for id,part in pairs(bulbs) do
 part.getId=function() return id end
 local l=part.light
 l.getDistanization=function() return l.rawDistance end
 l.getIntensity=function() return l.rawIntensity end
 l.getFocusing=function() return 100 end
 part.createSpotLight=function(self,x,y,range,power,dot)
  self.light.rawDistance=range;self.light.rawIntensity=power
  self.light.x=x;self.light.y=y;self.light.dot=dot
 end
end
current.refreshBeams()
local fl=bulbs.HeadlightLeft.light
assert(originalCalls==1 and fl.rawDistance==36 and fl.rawIntensity==.75 and math.abs(fl.y-1.2161299/2)<1e-7 and fl.dot==.94)
md.highBeamsOn=true;NepHBO7.UpdateLights(Vehicle);assert(fl.dot==.98 and fl.rawIntensity==.75)
opts.VehicleBeamShape.value=false;NepHBO7.UpdateLights(Vehicle);assert(fl.y==2 and fl.dot==.96,'disabled profile restores upstream geometry')
print('PASS vehicle beam shape: upstream switching/raw parameters and original restoration')

-- Native offsets are fractions of loaded half-extents, not model units.
local function close(a,b) assert(math.abs(a-b)<1e-6,tostring(a)..' ~= '..tostring(b)) end
Vehicle.scale=2.5;Vehicle.modelOffset=vec(.1,.2,-.3);Vehicle.extents=vec(3,2,8)
local x,y,z,nx,nz=current.lampOrigin(Vehicle,'HeadlightLeft')
close(x,.1+.3428599*2.5);close(y,.2-.0837760*2.5);close(z,-.3+1.2161299*2.5)
close(nx*3/2,x);close(nz*8/2,z)
opts.VehicleBeamShape.value=true;NepHBO7.UpdateLights(Vehicle)
close(fl.x,nx);close(fl.y,nz)
local firstX=fl.x;Vehicle.modelName='Vehicles_SportsCar';NepHBO7.UpdateLights(Vehicle)
assert(math.abs(fl.x-firstX)>.1,'different lamp geometry must change the actual origin')
Vehicle.modelName='UnknownModdedCar';NepHBO7.UpdateLights(Vehicle)
assert(fl.y==2,'unknown mesh must retain its upstream origin')
Vehicle.modelName='Vehicles_CarNormal';Vehicle.rotate=vec(0,90,0);NepHBO7.UpdateLights(Vehicle)
assert(fl.y==2,'unsupported mesh rotation retains upstream origin')
Vehicle.rotate=vec(0,0,0)
-- Reverse white origins are applied only while RDL owns the actual reverse state.
local rear=bulbs.HeadlightRearLeft
ReverseDriveLights.Client.onPlayerUpdate=function()
 if ReverseDriveLights.Client.players[0] then rear:createSpotLight(.5,-1.6,12,.3,.75)
 else rear:createSpotLight(.5,-1.6,3,.2,.75) end
end
Events.OnPlayerUpdate.Remove=function() end
L.installBeamHooks()
local driver={isLocalPlayer=function() return true end,getPlayerNum=function() return 0 end}
ReverseDriveLights.Client.players[0]={vehicle=Vehicle,parts={[rear]=true}}
ReverseDriveLights.Client.onPlayerUpdate(driver)
local _,_,_,rx,rz=L.lampOrigin(Vehicle,'HeadlightRearLeft')
close(rear.light.x,rx);close(rear.light.y,rz)
assert(rear.light.rawDistance==12 and rear.light.rawIntensity==.3)
ReverseDriveLights.Client.players[0]=nil;ReverseDriveLights.Client.onPlayerUpdate(driver)
assert(rear.light.y==-1.6 and rear.light.rawDistance==3,'native red tail restoration remains owned by RDL')
print('PASS mesh lamp origins: asymmetric geometry, loaded scale/offset, normalized coordinates, model changes and reverse restoration')
