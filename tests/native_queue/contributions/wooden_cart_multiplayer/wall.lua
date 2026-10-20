local config=require 'QueueTestSelection'
assert(config.disposable==true,'Cart MP wall requires fresh owned disposable profiles')
local M={}
local owned={}
local spriteName='walls_exterior_wooden_01_0'
local function guard()
 assert(config.kind=='mp' and config.options and config.options.mp_host==true
  and (config.options.cart_wall_exit=='left' or config.options.cart_wall_exit=='right' or config.options.cart_wall_exit=='front')
  and isServer() and not isClient() and cartMPPadHost(),
  'Cart MP wall requires fresh disposable queue-smoke Host')
end
local function descriptor(area)
 assert(type(area)=='table' and area.bankVersion==4 and area.size==63 and area.z==7 and area.margin==2
  and area.elevated==true and area.floorSprite=='carpentry_02_57' and area.ownedWalls==49 and area.wallSprite==spriteName
  and (area.wallSide=='left' or area.wallSide=='right' or area.wallSide=='front'),'Invalid cart MP wall descriptor')
 local cx,cy=area.minX+31,area.minY+31
 assert(cx%1==0 and cy%1==0 and area.wallX==cx-3 and area.wallMinY==cy-24 and area.wallMaxY==cy+24
  and area.initialHeading==(area.wallSide=='front' and 1 or area.wallSide=='left' and .75 or -.75)*math.pi,'Invalid cart MP wall geometry')
end
local function flags(sprite)
 local properties=sprite and sprite:getProperties()
 return properties and properties:has(IsoFlagType.collideW)==true and properties:has(IsoFlagType.collideN)==false
end
local function floor(square,area)
 local value=square and square:getFloor()
 return value and value:getSpriteName()==area.floorSprite and square:TreatAsSolidFloor()
end
local function contains(square,object)
 local objects=square:getObjects()
 for i=0,objects:size()-1 do if objects:get(i)==object then return true end end
 return false
end
-- Placement calls this before creating even the first floor.
function M.preflight(area)
 guard();descriptor(area)
 assert(area.x==area.wallX+(area.wallSide=='front' and 1.8 or 2.8) and area.y==area.minY+31.5,'Invalid cart MP wall owner origin')
 assert(area.wallSide==config.options.cart_wall_exit,'Cart MP wall side disagrees with selection')
 for _ in pairs(owned) do error('Cart MP wall fixtures already owned',0) end
 assert(flags(getSprite(spriteName)),'Cart MP native wooden wall sprite collision flags disagree')
end
function M.create(area)
 M.preflight(area)
 local cell,plan=getCell(),{}
 local sprite=assert(getSprite(spriteName),'Cart MP wooden wall sprite missing')
 -- All targets and the opposite side must be native floors without existing objects.
 for y=area.wallMinY,area.wallMaxY do
  local square=cell:getGridSquare(area.wallX,y,area.z)
  local west=cell:getGridSquare(area.wallX-1,y,area.z)
  assert(floor(square,area) and floor(west,area) and square:getObjects():size()==1 and west:getObjects():size()==1
   and not square:testCollideAdjacent(nil,-1,0,0) and not west:testCollideAdjacent(nil,1,0,0),
   'Cart MP wall target is not an empty native floor')
  plan[#plan+1]={square=square,x=area.wallX,y=y,z=area.z}
 end
 for _,wall in ipairs(plan) do
  local object=assert(IsoObject.new(cell,wall.square,sprite),'Cart MP wall construction failed')
  owned[object]=wall
  -- This native method adds once, recalculates collision, and transmits to relevant clients.
  wall.square:transmitAddObjectToSquare(object,-1)
  assert(contains(wall.square,object),'Cart MP native wall insertion failed')
 end
 assert(M.receipt(area).ready,'Cart MP native wall geometry failed after creation')
 return area
end
function M.receipt(area)
 descriptor(area)
 local cell,floors,walls=getCell(),0,0
 for x=area.minX,area.minX+area.size-1 do for y=area.minY,area.minY+area.size-1 do
  if floor(cell:getGridSquare(x,y,area.z),area) then floors=floors+1 end
 end end
 for y=area.wallMinY,area.wallMaxY do
  local square=cell:getGridSquare(area.wallX,y,area.z)
  local west=cell:getGridSquare(area.wallX-1,y,area.z)
  if floor(square,area) and floor(west,area) then
   local matching=0;local objects=square:getObjects()
   for i=0,objects:size()-1 do
    local object=objects:get(i)
    if object:getSpriteName()==spriteName and flags(object:getSprite()) then matching=matching+1 end
   end
   if matching==1 and objects:size()==2 and square:testCollideAdjacent(nil,-1,0,0)
    and west:testCollideAdjacent(nil,1,0,0) and not square:testCollideAdjacent(nil,0,-1,0) then walls=walls+1 end
  end
 end
 return {floors=floors,walls=walls,ready=floors==area.size*area.size and walls==area.ownedWalls}
end
function M.cleanup()
 guard()
 local plan={}
 -- Preflight every owned identity before the first removal; never remove a replacement by sprite.
 for object,wall in pairs(owned) do
  assert(getCell():getGridSquare(wall.x,wall.y,wall.z)==wall.square and contains(wall.square,object)
   and object:getSpriteName()==spriteName,'Cart MP owned wall identity changed before cleanup')
  plan[#plan+1]={object=object,wall=wall}
 end
 for _,entry in ipairs(plan) do
  assert(entry.wall.square:transmitRemoveItemFromSquare(entry.object,false)>=0,'Cart MP native wall removal failed')
  assert(not contains(entry.wall.square,entry.object),'Cart MP native wall survived removal')
  owned[entry.object]=nil
 end
 return #plan
end
function M.cleanupReady(area)
 descriptor(area)
 local observed=M.receipt(area)
 if observed.floors~=area.size*area.size then return false end
 local cell=getCell()
 for y=area.wallMinY,area.wallMaxY do
  local square=cell:getGridSquare(area.wallX,y,area.z)
  local west=cell:getGridSquare(area.wallX-1,y,area.z)
  if not square or not west or square:getObjects():size()~=1 or west:getObjects():size()~=1
   or square:testCollideAdjacent(nil,-1,0,0) or west:testCollideAdjacent(nil,1,0,0) then return false end
 end
 return true
end
return M
