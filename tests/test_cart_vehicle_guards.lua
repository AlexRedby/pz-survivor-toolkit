-- PZ's Kahlua environment does not expose next(). Keep this runnable in stock Lua too.
next=nil
CartMotionConfig={disposable=true,vehicles=true,area={x=20,y=20,z=7,minX=0,minY=0,size=48,margin=2,floorSprite='floor'}}
local area=dofile(ProjectRoot..'/tests/native_queue/contributions/wooden_cart_motion/test-area.lua');area.ready=true
local function list(items)return {size=function()return #items end,get=function(_,i)return items[i+1] end}end
local floor={getSpriteName=function()return 'floor'end};local objects={floor};local moving={}
local present=true
local square={getFloor=function()return floor end,TreatAsSolidFloor=function()return true end,
 getObjects=function()return list(objects)end,getWorldObjects=function()return list({})end,
 getSpecialObjects=function()return list({})end,getStaticMovingObjects=function()return list({})end,
 getMovingObjects=function()return list(moving)end,isVehicleIntersecting=function()return present end,isFree=function()return not present end,
 testCollideAdjacent=function()return false end}
getCell=function()return {getGridSquare=function()return square end}end
getWorld=function()return {getWorld=function()return 'CartTestArea'end}end
isClient=function()return false end;isServer=function()return false end
local player={getX=function()return 20 end,getY=function()return 20 end,getZ=function()return 7 end}
local owned={};local allowed=true;cartLabVehicleSquareAllowed=function()return allowed end
local function rejects()local ok,why=pcall(area.checkPosition,player);assert(not ok,tostring(why))end
rejects();area.vehicles[owned]=true;allowed=false;rejects();allowed=true;assert(area.checkPosition(player))
moving[1]={};rejects();moving[1]=nil;objects[2]={};rejects();objects[2]=nil
assert(area.checkPosition(player))
area.vehicles={}
local removed=0
cartLabVehicleCreate=function()error('Unexpected native creation')end
cartLabVehicleCheck=function()return true end;cartLabVehicleState=function()return ''end
cartLabVehicleRemove=function()removed=removed+1;present=false end
dofile(ProjectRoot..'/tests/native_queue/contributions/wooden_cart_motion/vehicles.lua')
area.clearVehicles(player);assert(removed==0 and not area.hasVehicles())
area.vehicles[owned]=true;assert(area.hasVehicles())
area.clearVehicles(player);assert(removed==1 and not area.hasVehicles())
print('PASS cart vehicle guards: exact ownership, foreign rejection and empty/owned cleanup without next')
