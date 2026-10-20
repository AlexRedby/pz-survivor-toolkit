-- Optional native action handles must never match an empty queue head through nil == nil.
local Progress={}
function Progress.running(current,target)
 return current~=nil and target~=nil and current==target and current:isStarted()and current:getJobDelta()>0
end
return Progress
