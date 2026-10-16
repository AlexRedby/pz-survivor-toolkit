-- The server issues native teleport; both sides must observe the saved origin.
local M={}
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
function M.observe(state,context,player)
 if not state or not state.issued or state.arrived or not M.at(player,state.origin) then return false end
 state.arrived=true;context.send('VerifyPosition',{});return true
end
function M.confirm(state,receipt)
 if not state or not state.issued or not state.arrived or state.confirmed or not matches(state,receipt) then return false end
 state.confirmed=true;return true
end
function M.describe(player,origin)
 return 'actual='..player:getX()..','..player:getY()..','..player:getZ()..' expected='..origin.x..','..origin.y..','..origin.z
end
return M
