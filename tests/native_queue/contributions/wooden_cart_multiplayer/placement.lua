local config=require 'QueueTestSelection'
assert(config.disposable==true,'Cart MP requires fresh owned disposable profiles')
return function(player)
 local current=assert(player:getCurrentSquare(),'actor square missing')
 local wallSide=config.options and config.options.cart_wall_exit
 local injury=config.options and config.options.cart_injury==true
 local extended=config.options and (config.options.cart_fast_motion or wallSide)
 if extended then
  assert(config.kind=='mp' and config.options.mp_host==true and isServer() and not isClient() and cartMPPadHost(),
   'Elevated cart pad requires fresh disposable queue-smoke Host')
  local cell,chunks=getCell(),{}
  local x,y,z=current:getX(),current:getY(),7
  local half=(wallSide or injury) and 31 or 15
  local area={x=x+4.5,y=y+.5,z=z,minX=x-half,minY=y-half,size=half*2+1,margin=2,vegetationFree=true,bankVersion=wallSide and 4 or injury and 5 or 3,floorSprite='carpentry_02_57',elevated=true}
  local wall
  if wallSide then
   area.wallSide=wallSide;area.wallSprite='walls_exterior_wooden_01_0';area.wallX=x-3;area.wallMinY=y-24;area.wallMaxY=y+24;area.ownedWalls=49
   area.initialHeading=(wallSide=='front' and 1 or wallSide=='left' and .75 or -.75)*math.pi
   area.x=area.wallX+(wallSide=='front' and 1.8 or 2.8)
   wall=require 'CartMPWall';wall.preflight(area)
  end
  -- addFloor creates neighbouring empty squares too; validate that halo before the first write.
  for a=x-half-1,x+half+1 do for b=y-half-1,y+half+1 do
   local chunk=cell:getChunkForGridSquare(a,b,0)
   local ground=cell:getGridSquare(a,b,0)
   if (wallSide or injury) and (not chunk or not ground) then return nil end
   assert(chunk and ground,'Elevated cart pad ground chunk not loaded')
   chunks[chunk]=true
   local sq=cell:getGridSquare(a,b,z)
   assert(not sq or not sq:getFloor() and sq:getObjects():size()==0 and sq:getSpecialObjects():size()==0
    and sq:getWorldObjects():size()==0 and sq:getStaticMovingObjects():size()==0 and sq:getMovingObjects():size()==0
    and not sq:getRoom() and not sq:isVehicleIntersecting(),'Elevated cart pad footprint is not empty')
  end end
  for a=area.minX,area.minX+area.size-1 do for b=area.minY,area.minY+area.size-1 do
   local sq=cell:getGridSquare(a,b,z) or cell:createNewGridSquare(a,b,z,true)
   assert(sq,'Elevated cart pad cannot create native square')
   cell:setCacheGridSquare(a,b,z,sq)
   -- Native addFloor transmits its AddItemToMap packet to relevant clients.
   assert(sq:addFloor(area.floorSprite),'Elevated cart pad native floor creation failed')
  end end
  for chunk in pairs(chunks) do cell:setCacheChunk(chunk) end
  if wall then wall.create(area) end
  print('[CART_MP] OPEN_PAD '..x..','..y..','..z)
  return area
 end
 local half=6
 for radius=8,24,2 do
  for dx=-radius,radius,2 do for dy=-radius,radius,2 do
   if math.abs(dx)==radius or math.abs(dy)==radius then
    local x,y,z=current:getX()+dx,current:getY()+dy,current:getZ();local clear=true
    for a=-half,half do
     if not clear then break end
     for b=-half,half do
      local sq=getCell():getGridSquare(x+a,y+b,z)
      if not sq or not sq:getFloor() or not sq:TreatAsSolidFloor() or not sq:isFree(false) or sq:getRoom() or sq:isVehicleIntersecting() then clear=false;break end
      for ax=-1,1 do for ay=-1,1 do
       if (ax~=0 or ay~=0) and a+ax>=-half and a+ax<=half and b+ay>=-half and b+ay<=half and sq:testCollideAdjacent(nil,ax,ay,0) then clear=false end
      end end
      if not clear then break end
     end
    end
    if clear then print('[CART_MP] OPEN_PAD '..x..','..y..','..z);return {x=x+.5,y=y+.5,z=z,minX=x-half,minY=y-half,size=half*2+1,margin=2,vegetationFree=extended==true,bankVersion=extended and 2 or 1} end
   end
  end end
 end
 error('No loaded clear'..(half*2+1)..'x'..(half*2+1)..' native cart capture area')
end
