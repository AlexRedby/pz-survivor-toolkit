local config=require 'QueueTestSelection'
assert(config.disposable==true,'Cart MP requires fresh owned disposable profiles')
return function(player)
 local current=assert(player:getCurrentSquare(),'actor square missing')
 for radius=8,24,2 do
  for dx=-radius,radius,2 do for dy=-radius,radius,2 do
   if math.abs(dx)==radius or math.abs(dy)==radius then
    local x,y,z=current:getX()+dx,current:getY()+dy,current:getZ();local clear=true
    for a=-6,6 do
     if not clear then break end
     for b=-6,6 do
      local sq=getCell():getGridSquare(x+a,y+b,z)
      if not sq or not sq:getFloor() or not sq:TreatAsSolidFloor() or not sq:isFree(false) or sq:getRoom() or sq:isVehicleIntersecting() then clear=false;break end
      for ax=-1,1 do for ay=-1,1 do
       if (ax~=0 or ay~=0) and a+ax>=-6 and a+ax<=6 and b+ay>=-6 and b+ay<=6 and sq:testCollideAdjacent(nil,ax,ay,0) then clear=false end
      end end
      if not clear then break end
     end
    end
    if clear then print('[CART_MP] OPEN_PAD '..x..','..y..','..z);return {x=x+.5,y=y+.5,z=z,minX=x-6,minY=y-6,size=13} end
   end
  end end
 end
 error('No loaded clear13x13 native cart capture area')
end
