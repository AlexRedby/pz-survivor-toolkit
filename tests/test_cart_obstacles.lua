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
local missingOpenSprite,refuseToggle,failToggleAfter=false,false,false
local failToggleCollision,wrongDoorCollision=false,nil
local toggles,specialAdds,recalcs=0,0,0
local forcedEdges={}
local function key(x,y,z) return x..','..y..','..z end
local function edgeKey(x,y,dx,dy) return x..','..y..','..dx..','..dy end
IsoFlagType={collideN='N',collideW='W',doorN='doorN',doorW='doorW'}
local function sprite(name)
 local axis=name=='walls_exterior_wooden_01_1' and 'N' or name=='walls_exterior_wooden_01_0' and 'W' or nil
 local door=name=='fixtures_doors_01_1' and 'doorN' or name=='fixtures_doors_01_0' and 'doorW' or nil
 return {getName=function() return name end,getProperties=function()
  return {has=function(_,flag) return (axis==flag or door==flag) and not wrongSpriteFlags end}
 end}
end
getSprite=function(name)
 if missingSprite or missingOpenSprite and (name=='fixtures_doors_01_2' or name=='fixtures_doors_01_3') then return nil end
 return sprite(name)
end
local function nativeWall(x,y,axis)
 local sq=squares[key(x,y,7)]
 if not sq then return false end
 for _,object in ipairs(sq.objects) do
  if object:getSprite():getProperties():has(axis) then return true end
 end
 return false
end
local function nativeDoor(x,y,axis,objects)
 local sq=squares[key(x,y,7)]
 if not sq then return nil end
 for _,object in ipairs(objects and sq.objects or sq.special) do
  if object.doorAxis==axis then
   local blocked=objects and object:isBlocked() or (object==wrongDoorCollision and object:isOpen() or object~=wrongDoorCollision and object:isBlocked())
   if blocked then return object end
  end
 end
 return nil
end
local function specialEdge(x,y,dx,dy,objects)
 if dx==-1 then return nativeDoor(x,y,'W',objects) end
 if dx==1 then return nativeDoor(x+1,y,'W',objects) end
 if dy==-1 then return nativeDoor(x,y,'N',objects) end
 return nativeDoor(x,y+1,'N',objects)
end
local function nativeEdge(x,y,dx,dy,wallsOnly)
 local override=forcedEdges[edgeKey(x,y,dx,dy)]
 if override~=nil then return override end
 if not wallsOnly and specialEdge(x,y,dx,dy) then return true end
 if dx==-1 then return nativeWall(x,y,'W') end
 if dx==1 then return nativeWall(x+1,y,'W') end
 if dy==-1 then return nativeWall(x,y,'N') end
 return nativeWall(x,y+1,'N')
end
local function square(x,y,z)
local sq={objects={},moving={},special={}}
 function sq:getX() return x end
 function sq:getY() return y end
 function sq:getZ() return z end
 function sq:getFloor() return self.floor end
 function sq:getObjects() return list(self.objects) end
 function sq:getSpecialObjects() return list(self.special) end
 function sq:getWorldObjects() return list({}) end
 function sq:getStaticMovingObjects() return list({}) end
 function sq:getMovingObjects() return list(self.moving) end
 function sq:TreatAsSolidFloor() return self.floor~=nil end
 function sq:isVehicleIntersecting() return false end
 function sq:isFree() return true end
 function sq:testCollideAdjacent(_,dx,dy,dz)
  assert(dz==0)
  if dx~=0 and dy~=0 then
   return nativeEdge(x,y,dx,0,true) or nativeEdge(x,y,0,dy,true)
    or nativeEdge(x+dx,y,0,dy,true) or nativeEdge(x,y+dy,dx,0,true)
  end
  -- Native B42's nil-actor path only reads its static wall collision matrix.
  return nativeEdge(x,y,dx,dy,true)
 end
 function sq:testCollideSpecialObjects(other)
  local dx,dy=other:getX()-x,other:getY()-y
  if dx~=0 and dy~=0 then
   return specialEdge(x,y,dx,0) or specialEdge(x,y,0,dy)
    or specialEdge(x+dx,y,0,dy) or specialEdge(x,y+dy,dx,0)
  end
  return specialEdge(x,y,dx,dy)
 end
 function sq:isDoorBlockedTo(other)
  return specialEdge(x,y,other:getX()-x,other:getY()-y,true)~=nil
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
 function sq:AddSpecialObject(object)
  specialAdds=specialAdds+1
  self:AddTileObject(object)
  self.special[#self.special+1]=object
 end
 function sq:RemoveTileObject(object)
  for i,value in ipairs(self.objects) do
   if value==object then
    for j,special in ipairs(self.special) do if special==object then table.remove(self.special,j);break end end
    table.remove(self.objects,i);removals=removals+1;return i-1
   end
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
IsoDoor={new=function(_,sq,sp,north)
 local object={doorAxis=north and 'N' or 'W',open=false,locked=true,lockedByKey=true}
 assert(sp:getName()==(north and 'fixtures_doors_01_1' or 'fixtures_doors_01_0'),'wrong native door orientation')
 function object:getSquare() return sq end
 function object:getSpriteName()
  return 'fixtures_doors_01_'..(self.open and (north and 3 or 2) or (north and 1 or 0))
 end
 function object:getSprite() return sprite(self:getSpriteName()) end
 function object:isOpen() return self.open end
 function object:isBlocked() return not self.open or self.barricaded==true end
 function object:setLocked(value) self.locked=value end
 function object:setLockedByKey(value) self.lockedByKey=value end
 function object:ToggleDoor(actor)
  assert(actor and not self.locked and not self.lockedByKey,'door fixture must be unlocked')
  toggles=toggles+1
  if refuseToggle then return end
  self.open=not self.open;recalcs=recalcs+1
  wrongDoorCollision=failToggleCollision and self or nil;failToggleCollision=false
  if failToggleAfter then failToggleAfter=false;error('injected native toggle failure') end
 end
 return object
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
rejects(function() area.setObstacles(player,{{x=4,y=4,axis='N',kind='other'}}) end,'kind')
rejects(function() area.setObstacles(player,{{x=4,y=4,axis='N',open=true}}) end,'boolean')
rejects(function() area.setObstacles(player,{{x=4,y=4,axis='N',kind='door',open=1}}) end,'boolean')
local doors={{x=4,y=4,axis='W',kind='door'},{x=5,y=4,axis='N',kind='door',open=true}}
missingOpenSprite=true;rejects(function() area.setObstacles(player,doors) end,'sprite missing');missingOpenSprite=false
wrongSpriteFlags=true;rejects(function() area.setObstacles(player,doors) end,'flags');wrongSpriteFlags=false
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
local distantKey=key(area.minX+area.size-1,area.minY,area.z)
local distant=squares[distantKey];squares[distantKey]=nil
local registry,edges=area.obstacles,area.obstacleEdges
rejects(function() area.clearObstacles(player) end,'square not loaded')
assert(removals==before and area.obstacles==registry and area.obstacleEdges==edges,
 'missing distant square allowed partial cleanup')
squares[distantKey]=distant
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

local specialBefore=specialAdds
area.setObstacles(player,doors)
assert(specialAdds-specialBefore==2,'native doors must use AddSpecialObject')
local west,north
for object,owned in pairs(area.obstacles) do
 if owned.axis=='W' then west=object else north=object end
 assert(owned.kind=='door' and owned.sprite==object:getSpriteName())
end
local westSquare=cell:getGridSquare(4,4,7)
assert(west and north and not west:isOpen() and north:isOpen() and area.check(player))
assert(westSquare:getSpecialObjects():size()==1 and westSquare:getSpecialObjects():get(0)==west)
local westOpposite=cell:getGridSquare(3,4,7)
-- Reproduce B42: the nil-actor matrix is clear while the live closed door blocks.
assert(not westSquare:testCollideAdjacent(nil,-1,0,0) and not westOpposite:testCollideAdjacent(nil,1,0,0))
assert(westSquare:testCollideSpecialObjects(westOpposite)==west and westOpposite:testCollideSpecialObjects(westSquare)==west)
assert(westSquare:isDoorBlockedTo(westOpposite) and westOpposite:isDoorBlockedTo(westSquare))
assert(cell:getGridSquare(3,3,7):testCollideSpecialObjects(westSquare)==west,'door diagonal lost an orthogonal edge')
assert(westSquare:isFree(false),'closed door must not make its floor tile solid')
assert(nativeEdge(4,4,-1,0) and nativeEdge(3,4,1,0))
assert(not nativeEdge(5,4,0,-1) and not nativeEdge(5,3,0,1))
local toggleBefore=toggles
area.setDoorOpen(player,west,false)
assert(toggles==toggleBefore,'idempotent state setting toggled native door')
area.setDoorOpen(player,west,true);area.setDoorOpen(player,north,false)
assert(westSquare:testCollideSpecialObjects(westOpposite)==nil and westOpposite:testCollideSpecialObjects(westSquare)==nil)
assert(not westSquare:isDoorBlockedTo(westOpposite) and not westOpposite:isDoorBlockedTo(westSquare))
assert(not nativeEdge(4,4,0,-1) and not nativeEdge(4,3,0,1),'open leaf invented a perpendicular collision edge')
table.remove(westSquare.special)
rejects(function() area.check(player) end,'missing fixture door')
westSquare.special[1]=west
west.barricaded=true
rejects(function() area.check(player) end,'fixture door state disagrees')
west.barricaded=false
assert(not nativeEdge(4,4,-1,0) and not nativeEdge(3,4,1,0))
assert(nativeEdge(5,4,0,-1) and nativeEdge(5,3,0,1) and area.check(player))
local oldEdges=area.obstacleEdges
world='RealSave';toggleBefore=toggles
rejects(function() area.setDoorOpen(player,west,false) end,'non-test save');world='CartTestArea'
assert(toggles==toggleBefore and west:isOpen() and area.obstacleEdges==oldEdges)
rejects(function() area.setDoorOpen(player,west,1) end,'boolean')
local foreignDoor=IsoDoor.new(cell,westSquare,getSprite('fixtures_doors_01_0'),false)
rejects(function() area.setDoorOpen(player,foreignDoor,true) end,'not a registered')
foreignDoor.open=true
westSquare.objects[#westSquare.objects+1]=foreignDoor
rejects(function() area.setDoorOpen(player,west,false) end,'unexpected tile object')
before=removals;rejects(function() area.clearObstacles(player) end,'unexpected tile object')
assert(removals==before and toggles==toggleBefore and west:isOpen())
table.remove(westSquare.objects)
refuseToggle=true
rejects(function() area.setDoorOpen(player,west,false) end,'refused')
refuseToggle=false
assert(west:isOpen() and area.obstacleEdges==oldEdges and area.check(player),'refusal changed fixture registry')
failToggleAfter=true
rejects(function() area.setDoorOpen(player,west,false) end,'injected native toggle failure')
assert(west:isOpen() and area.obstacles[west].sprite=='fixtures_doors_01_2' and area.obstacleEdges==oldEdges and area.check(player),
 'failed native toggle was not rolled back')
failToggleCollision=true
rejects(function() area.setDoorOpen(player,west,false) end,'missing fixture collision edge')
assert(west:isOpen() and area.obstacles[west].sprite=='fixtures_doors_01_2' and area.obstacleEdges==oldEdges and area.check(player),
 'failed collision verification was not rolled back')
area.clearObstacles(player)
assert(westSquare:getSpecialObjects():size()==0 and westSquare:getObjects():size()==1 and area.check(player))
for _,after in ipairs({false,true}) do
 failAddAt=additions+2;failAfterAdd=after
 rejects(function() area.setObstacles(player,doors) end,'injected native add failure')
 failAddAt=nil
 assert(empty(area.obstacles) and empty(area.obstacleEdges) and westSquare:getSpecialObjects():size()==0 and area.check(player))
end
failToggleAfter=true
rejects(function() area.setObstacles(player,doors) end,'injected native toggle failure')
assert(empty(area.obstacles) and empty(area.obstacleEdges) and area.check(player))
assert(recalcs>0,'native door changes never updated collision state')
print('PASS cart obstacles: strict guards, native nil-actor wall matrix and live door edges, identity cleanup, setup and door rollback')

next=originalNext
