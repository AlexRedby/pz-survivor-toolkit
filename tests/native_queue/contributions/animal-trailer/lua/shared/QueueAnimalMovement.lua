-- Use native pathfinding and a server position receipt; never write player coordinates.
local M={}
function M.at(player,origin)
 return math.abs(player:getX()-origin.x)<=0.15 and math.abs(player:getY()-origin.y)<=0.15 and player:getZ()==origin.z
end
function M.restore(context,player,origin)
 assert(type(origin)=='table' and type(origin.x)=='number' and type(origin.y)=='number' and type(origin.z)=='number','missing authoritative fixture origin')
 require 'Vehicles/TimedActions/ISPathFindAction'
 local state={origin=origin,arrived=false,confirmed=false}
 local action=ISPathFindAction:pathToLocationF(player,origin.x,origin.y,origin.z)
 action:setOnComplete(function()
  if not M.at(player,origin) then context.quarantine('native reset path ended away from origin');return end
  state.arrived=true;context.send('VerifyPosition',{})
 end)
 action:setOnFail(function() context.quarantine('native reset path failed') end)
 ISTimedActionQueue.add(action)
 return state
end
function M.confirm(state,receipt)
 if not state or not state.arrived or type(receipt)~='table' then return false end
 for _,key in ipairs({'x','y','z'}) do
  if type(receipt[key])~='number' or not (math.abs(receipt[key]-state.origin[key])<=(key=='z' and 0 or 0.15)) then return false end
 end
 state.confirmed=true;return true
end
return M
