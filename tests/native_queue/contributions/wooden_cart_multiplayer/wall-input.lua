-- Physical relative-key inputs; a released steering key stays released for its stage.
local M={}
function M.steps(side)
 assert(side=='left' or side=='right','Unknown wall side')
 local left=side=='left'
 return {{0,0,0,'idle'},{1000,1,0,'walk'},{9500,4,0,'reverse'},
  {12000,left and 6 or 7,0,'reverse-turn'},{15500,0,0,'reverse-stop'},
  {16000,left and 5 or 8,0,'forward-turn'},{21000,left and 5 or 8,0,'forward-out'},{26000,0,0,'settled'}}
end
function M.drive(side,step,released,heading)
 local name=step[4]
 if name~='reverse-turn' and name~='forward-turn' and name~='forward-out' then return step[2] end
 local sign=side=='left' and 1 or -1
 local reverse=name=='reverse-turn'
 local target=sign*(reverse and math.pi*.75 or name=='forward-turn' and math.pi*.25 or 0)
 local error=math.atan2(math.sin(target-heading),math.cos(target-heading))
 if released[name] or sign*error*(reverse and 1 or -1)<=.025 then
  released[name]=true;return reverse and 4 or 1
 end
 return step[2]
end
return M
