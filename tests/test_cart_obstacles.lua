local originalNext=next
next=nil -- Stock Kahlua exposes pairs but not Lua 5.1's next.
local function empty(items)
 for _ in pairs(items) do return false end
 return true
end
local function list(items)
 return {size=function() return #items end,get=function(_,i) return items[i+1] end}
end
local squares,loaded,world={},true,'CartTestArea'
local additions,removals,failAddAt,failAfterAdd=0,0,nil,false
local client,server,missingSprite,wrongSpriteFlags=false,false,false,false
local forcedEdges={}
local function key(x,y,z) return x..','..y..','..z end
local function edgeKey(x,y,dx,dy) return x..','..y..','..dx..','..dy end
IsoFlagType={collideN='N',collideW='W'}
local function sprite(name)
 local axis=name=='walls_exterior_wooden_01_1' and 'N' or name=='walls_exterior_wooden_01_0' and 'W' or nil
 return {getName=function() return name end,getProperties=function()
  return {has=function(_,flag) return axis==flag and not wrongSpriteFlags end}
 end}
end
getSprite=function(name) return not missingSprite and sprite(name) or nil end
local function nativeWall(x,y,axis)
 local sq=squares[key(x,y,7)]
 if not sq then return false end
 for _,object in ipairs(sq.objects) do
  if object:getSprite():getProperties():has(axis) then return true end
 end
 return false
end
local function nativeEdge(x,y,dx,dy)
 local override=forcedEdges[edgeKey(x,y,dx,dy)]
 if override~=nil then return override end
 if dx==-1 then return nativeWall(x,y,'W') end
 if dx==1 then return nativeWall(x+1,y,'W') end
 if dy==-1 then return nativeWall(x,y,'N') end
 return nativeWall(x,y+1,'N')
end
local function square(x,y,z)
 local sq={objects={},moving={}}
 function sq:getX() return x end
 function sq:getY() return y end
 function sq:getZ() return z end
 function sq:getFloor() return self.floor end
 function sq:getObjects() return list(self.objects) end
 function sq:getWorldObjects() return list({}) end
 function sq:getStaticMovingObjects() return list({}) end
 function sq:getMovingObjects() return list(self.moving) end
 function sq:TreatAsSolidFloor() return self.floor~=nil end
 function sq:isVehicleIntersecting() return false end
 function sq:isFree() return true end
 function sq:testCollideAdjacent(_,dx,dy,dz)
  assert(dz==0)
  if dx~=0 and dy~=0 then
   return nativeEdge(x,y,dx,0) or nativeEdge(x,y,0,dy)
    or nativeEdge(x+dx,y,0,dy) or nativeEdge(x,y+dy,dx,0)
  end
  return nativeEdge(x,y,dx,dy)
 end
 function sq:addFloor(name)
  local sp=sprite(name)
  self.floor={getSpriteName=function() return name end,getSprite=function() return sp end}
  self.objects={self.floor};return self.floor
 end
 function sq:AddTileObject(object)
  additions=additions+1
  if additions==failAddAt and not failAfterAdd then error('injected native add failure') end
  self.objects[#self.objects+1]=object
  if additions==failAddAt then error('injected native add failure') end
 end
 function sq:RemoveTileObject(object)
  for i,value in ipairs(self.objects) do
   if value==object then table.remove(self.objects,i);removals=removals+1;return i-1 end
  end
  error('cleanup attempted to remove an absent object')
 end
 return sq
end
local chunk,cell={},{}
function cell:getGridSquare(x,y,z)
 if z==0 then return loaded and {} or nil end
 return squares[key(x,y,z)]
end
function cell:getChunkForGridSquare() return loaded and chunk or nil end
function cell:createNewGridSquare(x,y,z)
 local sq=square(x,y,z);squares[key(x,y,z)]=sq;return sq
end
function cell:setCacheGridSquare() end
function cell:setCacheChunk() end
getCell=function() return cell end
getWorld=function() return {getWorld=function() return world end} end
isClient=function() return client end
isServer=function() return server end
IsoObject={new=function(_,sq,sp)
 return {getSquare=function() return sq end,getSpriteName=function() return sp:getName() end,getSprite=function() return sp end}
end}
CartMotionConfig={disposable=true,area={x=3.5,y=3.5,z=7,minX=0,minY=0,size=8,margin=1,floorSprite='carpentry_02_57'}}
local area=dofile(ProjectRoot..'/tests/native_queue/contributions/wooden_cart_motion/test-area.lua')
area.prepare()
local player={getX=function() return 3.5 end,getY=function() return 3.5 end,getZ=function() return 7 end}
dofile(ProjectRoot..'/tests/native_queue/contributions/wooden_cart_motion/obstacles.lua')
assert(additions==0 and removals==0,'loading helper installed an obstacle')
local function rejects(fn,reason)
 local ok,why=pcall(fn)
 assert(not ok and tostring(why):find(reason,1,true),tostring(why))
end
local wall={{x=4,y=4,axis='N'}}
world='RealSave';rejects(function() area.setObstacles(player,wall) end,'non-test save');world='CartTestArea'
client=true;rejects(function() area.setObstacles(player,wall) end,'single-player');client=false
server=true;rejects(function() area.setObstacles(player,wall) end,'single-player');server=false
CartMotionConfig.disposable=false;rejects(function() area.setObstacles(player,wall) end,'disposable');CartMotionConfig.disposable=true
area.ready=false;rejects(function() area.setObstacles(player,wall) end,'prepare()');area.ready=true
rejects(function() area.setObstacles(player,{{x=4,y=4,axis='N'},{x=5,y=4,axis='bad'}}) end,'axis')
rejects(function() area.setObstacles(player,{{x=4,y=4,axis='N'},{x=4,y=4,axis='N'}}) end,'duplicate')
rejects(function() area.setObstacles(player,{{x=4,y=4,axis='N'},{x=1,y=1,axis='W'}}) end,'bounds')
rejects(function() area.setObstacles(player,{{x=4,y=4,axis='N'},{x=5.5,y=4,axis='N'}}) end,'integer')
rejects(function() area.setObstacles(player,{{x=4,y=4,axis='N',z=0}}) end,'level')
missingSprite=true;rejects(function() area.setObstacles(player,wall) end,'sprite missing');missingSprite=false
wrongSpriteFlags=true;rejects(function() area.setObstacles(player,wall) end,'flags');wrongSpriteFlags=false
assert(additions==0 and removals==0,'invalid preflight edited the pad')

-- Corner and one missing N segment form a one-tile passage through a native wall.
local layout={{x=3,y=4,axis='N'},{x=3,y=4,axis='W'},{x=5,y=4,axis='N'}}
area.setObstacles(player,layout)
assert(additions==3 and area.check(player))
assert(area.obstacleEdges[edgeKey(3,4,0,-1)] and area.obstacleEdges[edgeKey(3,3,0,1)])
assert(area.obstacleEdges[edgeKey(3,4,-1,0)] and area.obstacleEdges[edgeKey(2,4,1,0)])
assert(not cell:getGridSquare(4,4,7):testCollideAdjacent(nil,0,-1,0))
assert(not cell:getGridSquare(4,3,7):testCollideAdjacent(nil,0,1,0))
rejects(function() area.setObstacles(player,wall) end,'clear existing')
local here=cell:getGridSquare(3,4,7)
local foreign=IsoObject.new(cell,here,getSprite('walls_exterior_wooden_01_1'))
here.objects[#here.objects+1]=foreign
rejects(function() area.check(player) end,'unexpected tile object')
local before=removals
rejects(function() area.clearObstacles(player) end,'unexpected tile object')
assert(removals==before and here.objects[#here.objects]==foreign,'cleanup removed a foreign object')
table.remove(here.objects)
forcedEdges[edgeKey(3,4,0,-1)]=false
rejects(function() area.check(player) end,'edge')
forcedEdges={}
forcedEdges[edgeKey(6,6,1,0)]=true
rejects(function() area.check(player) end,'edge')
forcedEdges={}
area.clearObstacles(player)
assert(removals==3 and empty(area.obstacles) and empty(area.obstacleEdges) and area.check(player))
assert(here:getObjects():size()==1 and here:getFloor()==here:getObjects():get(0),'cleanup removed the floor')
area.clearObstacles(player)
assert(removals==3,'empty cleanup edited the pad')

for _,after in ipairs({false,true}) do
 failAddAt=additions+2;failAfterAdd=after
 local removedBefore=removals
 rejects(function() area.setObstacles(player,layout) end,'injected native add failure')
 assert(removals-removedBefore==(after and 2 or 1),'partial setup did not clean exactly its created objects')
 assert(empty(area.obstacles) and empty(area.obstacleEdges) and area.check(player),'failed setup left native obstacles')
 failAddAt=nil
end
area.setObstacles(player,wall)
world='RealSave';before=removals
rejects(function() area.clearObstacles(player) end,'non-test save')
assert(removals==before,'wrong-world cleanup edited the pad')
world='CartTestArea';area.clearObstacles(player)
print('PASS cart obstacles: strict guards, complete preflight, native edges, identity cleanup, partial failure rollback')

next=originalNext
