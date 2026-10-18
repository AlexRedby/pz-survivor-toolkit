local config=assert(CartMotionConfig,'CartMotionConfig required')
assert(config.disposable==true and config.vehicles==true,'Disposable vehicle bank required')
local area=assert(CartTestArea,'CartTestArea required')
assert(cartLabVehicleCreate and cartLabVehicleCheck and cartLabVehicleState and cartLabVehicleRemove and cartLabVehicleSquareAllowed,'Native vehicle fixture bridge missing')
local function guard(player)
 assert(getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable single-player CartTestArea required')
 assert(area.ready,'Prepare disposable pad first');area.check(player)
end
function area.clearVehicles(player)
 assert(getWorld():getWorld()=='CartTestArea' and not isClient() and not isServer(),'Disposable single-player CartTestArea required')
 assert(area.ready,'Prepare disposable pad first')
 if area.hasVehicles() then
  -- Removal accepts only the bridge's exact object, even when a failed stability guard needs cleanup.
  cartLabVehicleRemove();area.vehicles={}
  area.check(player)
 end
end
function area.setVehicle(player,yaw)
 guard(player)
 assert(not area.hasVehicles(),'Clear the owned fixture vehicle first')
 assert(yaw==0 or yaw==45,'Vehicle yaw must be 0 or 45 degrees')
 local x,y=area.x-4,area.y
 -- Preflight the complete native CarNormal footprint before creating any world object.
 for dx=-8,8 do for dy=-8,8 do
  assert(area.contains(x+dx,y+dy,area.z),'Vehicle fixture outside safe pad bounds')
  local square=getCell():getGridSquare(math.floor(x+dx),math.floor(y+dy),area.z)
  assert(square and square:TreatAsSolidFloor(),'Vehicle fixture floor not loaded')
 end end
 local vehicle=cartLabVehicleCreate(x,y,area.z,math.rad(yaw))
 assert(vehicle,'Native fixture vehicle creation failed');area.vehicles[vehicle]=true
 local ok,result=pcall(function()
  local state=cartLabVehicleState();local hull={}
  for value in assert(state:match(' hull=([^ ]+)'),'Missing native hull'):gmatch('[^,]+') do hull[#hull+1]=assert(tonumber(value)) end
  assert(#hull==8,'Invalid native hull')
  local a=math.rad(yaw);local nx,ny,tx,ty=math.cos(a),-math.sin(a),math.sin(a),math.cos(a)
  local width,length=0,0
  for i=1,8,2 do
   width=math.max(width,math.abs((hull[i]-x)*nx+(hull[i+1]-y)*ny))
   length=math.max(length,math.abs((hull[i]-x)*tx+(hull[i+1]-y)*ty))
  end
  assert(width>.5 and width<2 and length>1.5 and length<4,'Unexpected CarNormal hull')
  area.check(player)
  return {x=x,y=y,z=area.z,yaw=yaw,nx=nx,ny=ny,tx=tx,ty=ty,width=width,length=length}
 end)
 if not ok then
  local cleaned,why=pcall(cartLabVehicleRemove);if cleaned then area.vehicles={} end
  error('[CART_VEHICLE] setup failed: '..tostring(result)..(cleaned and '' or '; cleanup failed: '..tostring(why)),0)
 end
 return result
end
return area
