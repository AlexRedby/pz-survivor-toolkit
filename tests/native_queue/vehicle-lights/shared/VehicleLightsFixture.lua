local F={}
local function road(x,y)
 local sq=getCell():getGridSquare(x,y,0)
 if not sq or not sq:isOutside() or not sq:isFree(false) then return false end
 local floor=sq:getFloor();local sprite=floor and floor:getSprite();local name=sprite and sprite:getName() or ''
 return name:find('street')~=nil
end
function F.position(player)
 local px,py=math.floor(player:getX()),math.floor(player:getY())
 for radius=0,60,4 do
  for dx=-radius,radius,2 do for dy=-radius,radius,2 do
   if radius==0 or math.abs(dx)==radius or math.abs(dy)==radius then
    local x,y=px+dx,py+dy
    for _,dir in ipairs({{0,-1,'N'},{0,1,'S'},{1,0,'E'},{-1,0,'W'}}) do
     local clear=true
     for offset=-66,66 do
      if not road(x+dir[1]*offset,y+dir[2]*offset) then clear=false;break end
     end
     if clear then
      print('[VEHICLE_LIGHTS] ROAD x='..x..' y='..y..' direction='..dir[3]..' clearAhead=66 clearBehind=66')
      return x,y,dir[3]
     end
    end
   end
  end end
 end
 error('No loaded unobstructed 133-tile road segment')
end
function F.prepare(player,x,y,dir,script)
 getGameTime():setTimeOfDay(2)
 local c=getClimateManager()
 for _,index in ipairs({ClimateManager.FLOAT_FOG_INTENSITY,ClimateManager.FLOAT_PRECIPITATION_INTENSITY,ClimateManager.FLOAT_CLOUD_INTENSITY}) do
  local value=c:getClimateFloat(index);value:setEnableAdmin(true);value:setAdminValue(index==ClimateManager.FLOAT_CLOUD_INTENSITY and 1 or 0)
 end
 local square=assert(getCell():getGridSquare(x,y,0),'road unloaded')
 local vehicle=assert(addVehicleDebug(script or 'Base.CarNormal',IsoDirections[dir],nil,square))
 assert(vehicle:getSquare(),'native vehicle placement rejected')
 -- addVehicleDebug randomizes yaw; the native setter uses degrees and truncates for its early-out.
 local yaw=assert(({N=180,S=0,E=90,W=-90})[dir])
 vehicle:setAngles(0,yaw+2,0);vehicle:setAngles(0,yaw,0)
 vehicle:repair();vehicle:setHotwired(true);vehicle:setAlarmed(false)
 local tank=assert(vehicle:getPartById('GasTank'));tank:setContainerContentAmount(tank:getContainerCapacity())
 for _,id in ipairs({'HeadlightLeft','HeadlightRight','HeadlightRearLeft','HeadlightRearRight'}) do
  local part=assert(vehicle:getPartById(id));assert(part:getInventoryItem(),'missing lamp '..id)
  part:getInventoryItem():setCondition(part:getInventoryItem():getConditionMax());part:setCondition(100)
 end
 F.vehicle=vehicle
 print('[VEHICLE_LIGHTS] SPAWN id='..vehicle:getId()..' x='..vehicle:getX()..' y='..vehicle:getY())
 return vehicle
end
return F
