local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true,'CartMotionConfig.disposable must be true')
local area=assert(CartTestArea,'CartTestArea required')
local sprites={N='walls_exterior_wooden_01_1',W='walls_exterior_wooden_01_0'}
local doorSprites={N={'fixtures_doors_01_1','fixtures_doors_01_3'},W={'fixtures_doors_01_0','fixtures_doors_01_2'}}

local function guard(player)
 assert(config.disposable==true,'CartMotionConfig.disposable must be true')
 assert(getWorld():getWorld()=='CartTestArea','[CART_OBSTACLES] refusing to modify a non-test save')
 assert(not isClient() and not isServer(),'[CART_OBSTACLES] single-player test save required')
 assert(area.ready,'[CART_OBSTACLES] call prepare() before testing')
 area.check(player)
end

local function contains(square,object)
 local objects=square:getObjects()
 for i=0,objects:size()-1 do if objects:get(i)==object then return true end end
 return false
end

local function edge(edges,x,y,dx,dy)
 edges[x..','..y..','..dx..','..dy]=true
 edges[(x+dx)..','..(y+dy)..','..(dx==0 and 0 or -dx)..','..(dy==0 and 0 or -dy)]=true
end

local function obstacleEdges()
 local edges={}
 for _,wall in pairs(area.obstacles) do
  if not wall.open then edge(edges,wall.x,wall.y,wall.axis=='W' and -1 or 0,wall.axis=='N' and -1 or 0) end
 end
 return edges
end

local function toggleDoor(player,object,wall,open)
 if object:isOpen()~=open then object:ToggleDoor(player) end
 assert(object:isOpen()==open,'[CART_OBSTACLES] native door refused state change')
 local sprite=doorSprites[wall.axis][open and 2 or 1]
 assert(object:getSpriteName()==sprite,'[CART_OBSTACLES] native door sprite disagrees')
 wall.open=open;wall.sprite=sprite
end

function area.setObstacles(player,segments)
 guard(player)
 for _ in pairs(area.obstacles or {}) do error('[CART_OBSTACLES] clear existing obstacles first',0) end
 assert(type(segments)=='table' and #segments>0,'[CART_OBSTACLES] segments required')
 local plan,seen={},{}
 local count=0
 for index in pairs(segments) do
  assert(type(index)=='number' and index%1==0 and index>=1 and index<=#segments,'[CART_OBSTACLES] segments must be an array')
  count=count+1
 end
 assert(count==#segments,'[CART_OBSTACLES] segments must be an array')
 -- Validate the entire layout and loaded footprint before the first native edit.
 for _,segment in ipairs(segments) do
  assert(type(segment)=='table' and sprites[segment.axis],'[CART_OBSTACLES] unknown wall axis')
  local kind=segment.kind or 'wall'
  assert(kind=='wall' or kind=='door','[CART_OBSTACLES] unknown obstacle kind')
  assert(segment.open==nil or kind=='door' and type(segment.open)=='boolean','[CART_OBSTACLES] door open must be boolean')
  local x,y,axis=segment.x,segment.y,segment.axis
  assert(type(x)=='number' and x%1==0 and type(y)=='number' and y%1==0,'[CART_OBSTACLES] integer wall coordinates required')
  assert(segment.z==nil or segment.z==area.z,'[CART_OBSTACLES] wrong wall level')
  local dx,dy=axis=='W' and -1 or 0,axis=='N' and -1 or 0
  assert(area.contains(x,y,area.z) and area.contains(x+dx,y+dy,area.z),'[CART_OBSTACLES] wall outside safe pad bounds')
  local key=x..','..y..','..axis
  assert(not seen[key],'[CART_OBSTACLES] duplicate wall segment');seen[key]=true
  local square=assert(getCell():getGridSquare(x,y,area.z),'[CART_OBSTACLES] wall square not loaded')
  local name=kind=='door' and doorSprites[axis][1] or sprites[axis]
  local sprite=assert(getSprite(name),'[CART_OBSTACLES] wall sprite missing')
  local properties=sprite:getProperties()
  if kind=='door' then
   assert(properties:has(IsoFlagType.doorN)==(axis=='N') and properties:has(IsoFlagType.doorW)==(axis=='W'),
    '[CART_OBSTACLES] native door sprite collision flags disagree')
   assert(getSprite(doorSprites[axis][2]),'[CART_OBSTACLES] open door sprite missing')
  else
   assert(properties:has(IsoFlagType.collideN)==(axis=='N') and properties:has(IsoFlagType.collideW)==(axis=='W'),
    '[CART_OBSTACLES] native wall sprite collision flags disagree')
  end
  plan[#plan+1]={square=square,spriteObject=sprite,x=x,y=y,z=area.z,sprite=name,axis=axis,kind=kind,open=segment.open==true}
 end
 area.obstacles={};area.obstacleEdges={}
 local ok,why=pcall(function()
  for _,wall in ipairs(plan) do
   local object
   if wall.kind=='door' then object=IsoDoor.new(getCell(),wall.square,wall.spriteObject,wall.axis=='N')
   else object=IsoObject.new(getCell(),wall.square,wall.spriteObject) end
   assert(object,'[CART_OBSTACLES] wall construction failed')
   wall.object=object
   local owned={x=wall.x,y=wall.y,z=wall.z,sprite=wall.sprite,axis=wall.axis,kind=wall.kind}
   area.obstacles[object]=owned
   if wall.kind=='door' then
    -- The native constructor randomly locks even disposable doors.
    object:setLocked(false);object:setLockedByKey(false)
    wall.square:AddSpecialObject(object)
    toggleDoor(player,object,owned,wall.open)
   else wall.square:AddTileObject(object) end
  end
  area.obstacleEdges=obstacleEdges()
  area.check(player)
 end)
 if not ok then
  local cleaned,cleanupWhy=pcall(function()
   for i=#plan,1,-1 do
    local wall=plan[i]
    if wall.object and contains(wall.square,wall.object) then wall.square:RemoveTileObject(wall.object) end
   end
   area.obstacles={};area.obstacleEdges={}
   area.check(player)
  end)
  if not cleaned then error('[CART_OBSTACLES] setup failed: '..tostring(why)..'; cleanup failed: '..tostring(cleanupWhy),0) end
  error(why,0)
 end
 return area.obstacles
end

function area.setDoorOpen(player,object,open)
 guard(player)
 assert(type(open)=='boolean','[CART_OBSTACLES] door open must be boolean')
 local wall=area.obstacles[object]
 assert(wall and wall.kind=='door','[CART_OBSTACLES] door is not a registered fixture')
 local oldOpen,oldSprite,oldEdges=wall.open,wall.sprite,area.obstacleEdges
 local ok,why=pcall(function()
  toggleDoor(player,object,wall,open)
  area.obstacleEdges=obstacleEdges()
  area.check(player)
 end)
 if not ok then
  local restored,restoreWhy=pcall(function()
   toggleDoor(player,object,wall,oldOpen)
   wall.sprite=oldSprite;area.obstacleEdges=oldEdges
   area.check(player)
  end)
  if not restored then error('[CART_OBSTACLES] door change failed: '..tostring(why)..'; rollback failed: '..tostring(restoreWhy),0) end
  error(why,0)
 end
 return object
end

function area.clearObstacles(player)
 guard(player)
 local plan={}
 for object,wall in pairs(area.obstacles or {}) do
  local square=assert(getCell():getGridSquare(wall.x,wall.y,wall.z),'[CART_OBSTACLES] wall square not loaded')
  assert(contains(square,object),'[CART_OBSTACLES] registered wall missing')
  plan[#plan+1]={square=square,object=object}
 end
 for _,wall in ipairs(plan) do wall.square:RemoveTileObject(wall.object) end
 area.obstacles={};area.obstacleEdges={}
 area.check(player)
end

return area
