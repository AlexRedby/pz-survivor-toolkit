-- The server issues native teleport; both sides must observe the saved origin.
local M={}
function M.entry(vehicle)
 local point=vehicle:getAreaCenter('AnimalEntry')
 if not point then return nil end
 return point,getSquare(math.floor(point:getX()),math.floor(point:getY()),math.floor(vehicle:getZ()))
end
function M.startSquare(vehicle)
 local point,entry=M.entry(vehicle)
 if not entry then return nil end
 for radius=0,1 do for dx=-radius,radius do for dy=-radius,radius do
  if math.max(math.abs(dx),math.abs(dy))==radius then
   local square=getSquare(entry:getX()+dx,entry:getY()+dy,entry:getZ())
   if square and square:getFloor() and square:isOutside() and square:isFree(true)
    and not square:isVehicleIntersecting() and square:canReachTo(entry)
    and (radius==0 or not square:testCollideAdjacent(nil,-dx,-dy,0)) then return square end
  end
 end end end
end
function M.nearEntry(player,vehicle)
 local point,entry=M.entry(vehicle)
 local square=player:getSquare()
 if not entry or not square or player:getZ()~=entry:getZ() then return false end
 local corrected=luautils.getCorrectSquareForWall(player,entry)
 return corrected and math.abs(player:getX()-point:getX())<=1.6 and math.abs(player:getY()-point:getY())<=1.6
  and square:canReachTo(corrected)
end
function M.stagedAt(player,target)
 local square=player:getSquare()
 return M.at(player,target) and square and square:getX()==math.floor(target.x)
  and square:getY()==math.floor(target.y) and square:getZ()==target.z
end
function M.at(player,origin)
 return math.abs(player:getX()-origin.x)<=0.15 and math.abs(player:getY()-origin.y)<=0.15 and player:getZ()==origin.z
end
function M.restore(context,player,origin)
 assert(type(origin)=='table' and type(origin.x)=='number' and type(origin.y)=='number' and type(origin.z)=='number','missing authoritative fixture origin')
 local state={origin=origin,issued=false,arrived=false,confirmed=false}
 context.send('RestorePosition',{})
 return state
end
local function matches(state,receipt)
 if not state or type(receipt)~='table' then return false end
 for _,key in ipairs({'x','y','z'}) do
  if type(receipt[key])~='number' or not (math.abs(receipt[key]-state.origin[key])<=(key=='z' and 0 or 0.15)) then return false end
 end
 return true
end
function M.issued(state,receipt)
 if not state or state.issued or not matches(state,receipt) then return false end
 state.issued=true;return true
end
function M.observe(state,context,player,command)
 if not state or not state.issued or state.arrived or not M.at(player,state.origin) then return false end
 state.arrived=true;context.send(command or 'VerifyPosition',{});return true
end
function M.confirm(state,receipt)
 if not state or not state.issued or not state.arrived or state.confirmed or not matches(state,receipt) then return false end
 state.confirmed=true;return true
end
function M.describe(player,origin)
 return 'actual='..player:getX()..','..player:getY()..','..player:getZ()..' expected='..origin.x..','..origin.y..','..origin.z
end
return M
