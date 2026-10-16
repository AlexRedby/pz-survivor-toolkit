local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true,'CartMotionConfig.disposable must be true')
local area=assert(CartTestArea,'CartTestArea required')
local sprites={N='walls_exterior_wooden_01_1',W='walls_exterior_wooden_01_0'}

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

function area.setObstacles(player,segments)
 guard(player)
 for _ in pairs(area.obstacles or {}) do error('[CART_OBSTACLES] clear existing obstacles first',0) end
 assert(type(segments)=='table' and #segments>0,'[CART_OBSTACLES] segments required')
 local plan,edges,seen={},{},{}
 local count=0
 for index in pairs(segments) do
  assert(type(index)=='number' and index%1==0 and index>=1 and index<=#segments,'[CART_OBSTACLES] segments must be an array')
  count=count+1
 end
 assert(count==#segments,'[CART_OBSTACLES] segments must be an array')
 -- Validate the entire layout and loaded footprint before the first native edit.
 for _,segment in ipairs(segments) do
  assert(type(segment)=='table' and sprites[segment.axis],'[CART_OBSTACLES] unknown wall axis')
  local x,y,axis=segment.x,segment.y,segment.axis
  assert(type(x)=='number' and x%1==0 and type(y)=='number' and y%1==0,'[CART_OBSTACLES] integer wall coordinates required')
  assert(segment.z==nil or segment.z==area.z,'[CART_OBSTACLES] wrong wall level')
  local dx,dy=axis=='W' and -1 or 0,axis=='N' and -1 or 0
  assert(area.contains(x,y,area.z) and area.contains(x+dx,y+dy,area.z),'[CART_OBSTACLES] wall outside safe pad bounds')
  local key=x..','..y..','..axis
  assert(not seen[key],'[CART_OBSTACLES] duplicate wall segment');seen[key]=true
  local square=assert(getCell():getGridSquare(x,y,area.z),'[CART_OBSTACLES] wall square not loaded')
  local sprite=assert(getSprite(sprites[axis]),'[CART_OBSTACLES] wall sprite missing')
  local properties=sprite:getProperties()
  assert(properties:has(IsoFlagType.collideN)==(axis=='N') and properties:has(IsoFlagType.collideW)==(axis=='W'),
   '[CART_OBSTACLES] native wall sprite collision flags disagree')
  plan[#plan+1]={square=square,spriteObject=sprite,x=x,y=y,z=area.z,sprite=sprites[axis],axis=axis}
  edge(edges,x,y,dx,dy)
 end
 area.obstacles={};area.obstacleEdges=edges
 local ok,why=pcall(function()
  for _,wall in ipairs(plan) do
   local object=assert(IsoObject.new(getCell(),wall.square,wall.spriteObject),'[CART_OBSTACLES] wall construction failed')
   wall.object=object
   area.obstacles[object]={x=wall.x,y=wall.y,z=wall.z,sprite=wall.sprite,axis=wall.axis}
   wall.square:AddTileObject(object)
  end
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
