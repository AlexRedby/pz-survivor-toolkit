local events,logs,shots,walks={},{},{},{}
local clock,saves,ready=0,0,false
local config={disposable=true,world='QueueBasementHall',kind='sp',cases={fixtureCase or 'fresh'},options={},video={directory='/cache/videos',ffmpeg='/bin/ffmpeg'}}
function require(name) if name=='QueueTestSelection' then return config end end
Events=setmetatable({},{__index=function(t,name)
 local e={Add=function(fn)events[name]=fn end};rawset(t,name,e);return e
end})
function print(text) logs[#logs+1]=text end
function getTimestampMs() return clock end
function isIngameState() return true end
function isClient() return false end
function isServer() return false end
function getWorld() return {getWorld=function()return config.world end} end
local core={TakeFullScreenshot=function(_,name) shots[#shots+1]=name end}
function getCore()return core end
local owner={getX=function()return 10707 end,getX2=function()return 10712 end,
 getY=function()return 9484 end,getY2=function()return 9491 end,getIDString=function()return 'actual-owner' end}
local room={getBuilding=function()return owner end}
local foreign={getBuilding=function()return {} end}
local function square(x,y,z,kind)
 return {getX=function()return x end,getY=function()return y end,getZ=function()return z end,
  getObjects=function()return {size=function()return 0 end} end,
  getFloor=function()return kind~='stairs' and {} or nil end,
  TreatAsSolidFloor=function()return kind~='stairs' and (z==0 or ready) end,
  HasStairs=function()return kind=='stairs' end,HasStairsBelow=function()return false end,
  isFree=function()return kind~='stairs' end,getRoomDef=function()return kind=='foreign' and foreign or room end}
end
local landing=square(10707,9484,0,'floor')
local staircase=square(10707,9485,-1,'stairs')
local interior=square(10710,9489,-1,'floor')
local wrong=square(10707,9488,-1,'foreign')
local cell={getGridSquare=function(_,x,y,z)
 for _,sq in ipairs({landing,staircase,interior,wrong})do
  if sq:getX()==x and sq:getY()==y and sq:getZ()==z then return sq end
 end
end}
function getCell()return cell end
local current=landing
local uses,active,held=0,false,nil
local useDelta=0.007
local lantern={getFullType=function()return 'Base.Lantern_Propane' end,
 setCurrentUsesFloat=function(_,value)uses=math.floor(value/useDelta+0.5) end,
 setCurrentUses=function(_,value)uses=value end,getMaxUses=function()return math.floor(1/useDelta) end,
 getCurrentUsesFloat=function()return uses*useDelta end,
 isActivated=function()return active end,getLightDistance=function()return 15 end,
 getLightStrength=function()return 2 end,isTorchCone=function()return false end}
lantern:setCurrentUsesFloat(1)
assert(uses==143 and lantern:getCurrentUsesFloat()>1 and lantern:getMaxUses()==142,'must model native rounded float setter and floored full charge')
uses=0
local inventory={getFirstType=function()return config.cases[1]=='reload' and lantern or nil end,
 AddItem=function(_,name)assert(name=='Base.Lantern_Propane');return lantern end}
local player={getSquare=function()return current end,isDead=function()return false end,setGodMod=function()end,
 getInventory=function()return inventory end,setPrimaryHandItem=function(_,item)held=item end,
 getPrimaryHandItem=function()return held end,getSecondaryHandItem=function()return nil end,getPlayerNum=function()return 0 end,
 getX=function()return current:getX()+0.5 end,getY=function()return current:getY()+0.5 end,getZ=function()return current:getZ() end}
function getPlayer()return player end
ISInventoryPaneContextMenu={onActivateItem=function(item,index)assert(item==lantern and index==0);active=true end}
BehaviorResult={Failed='failed',Succeeded='succeeded'}
ISWalkToTimedAction={new=function(_,actor,target)assert(actor==player);return {location=target}end}
ISTimedActionQueue={getTimedActionQueue=function()return {queue={}}end,add=function(action)
 walks[#walks+1]=action.location;current=action.location;action.result=BehaviorResult.Succeeded
end}
function basementHallProbe(name,nativeControl)
 assert(nativeControl==(config.cases[1]=='native-control'))
 assert(held==lantern and active and uses==lantern:getMaxUses() and lantern:getCurrentUsesFloat()<=1,
  'each probe must have a charged active held native lantern without rounding above full')
 return name
end
function basementHallSave()saves=saves+1 end
local recording=false
function toolkitVideoStart(directory,encoder)assert(directory==config.video.directory and encoder==config.video.ffmpeg);recording=true;return true end
function toolkitVideoStop()assert(recording);recording=false;return true end
function toolkitVideoStatus()return {state=saves>0 and 'completed' or recording and 'recording' or 'idle',
 file='/cache/videos/test.mp4',frames=153,seconds=5.1,captured=153,dropped=0,width=1280,height=720,error=''} end
assert(loadstring(fixtureSource))()
events.OnGameStart()
events.OnTick();assert(#logs==0,'must settle before probing or walking')
clock=2101;events.OnTick();events.OnTick()
clock=3800;events.OnTick();events.OnTick()
assert(#walks==0,'must wait for the actual underground floor')
ready=true;clock=3900;events.OnTick()
assert(#walks==1 and walks[1]==interior,'must select actual same-owner floor rather than nearer foreign room or a fixed asset tile')
clock=5501;events.OnTick();events.OnTick()
assert(#walks==2 and walks[2]==landing,'native walk must return to the original hall landing')
clock=7202;events.OnTick();clock=8803;events.OnTick()
assert(saves==1 and #shots==3,'must retain all three images and save once')
assert(logs[#logs]=='[BASEMENT_HALL] COMPLETE case='..config.cases[1],'must finish only after actual floor traversal and save')
for _,line in ipairs(logs)do assert(not line:find('[BASEMENT_HALL] FAIL ',1,true),line)end
