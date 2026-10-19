local Checks={}

function Checks.snapshot(queue)
 local result={};for i,action in ipairs(queue.queue) do result[i]=action end;return result
end

function Checks.unchanged(queue,expected)
 assert(#expected==#queue.queue,'denied control changed queue size')
 for i,action in ipairs(expected) do assert(queue.queue[i]==action,'denied control changed queue order') end
end

function Checks.deniedMove(queue,api,policy,action,target,after,reason)
 local before=Checks.snapshot(queue);local decision=policy.evaluateMove(queue,action,target,after)
 assert(not decision.allowed and decision.reason==reason,'unexpected policy barrier '..tostring(decision.reason))
 local ok,actual=api.move(queue,action,target,after)
 assert(not ok and actual==reason,'queue API did not preserve policy barrier');Checks.unchanged(queue,before)
end

function Checks.waitingCancel(queue,api,policy,action,removed,retained)
 local before=Checks.snapshot(queue);local excluded,expected={},{}
 for _,member in ipairs(removed) do excluded[member]=true end
 for _,member in ipairs(before) do if not excluded[member] then expected[#expected+1]=member end end
 local decision=policy.evaluateCancel(queue,action,true)
 assert(decision.allowed,'waiting operation cannot be cancelled '..tostring(decision.reason))
 assert(api.cancelOperation(queue,action),'waiting operation cancellation failed')
 for _,member in ipairs(removed) do assert(queue:indexOf(member)==-1,'whole operation was not removed') end
 for _,member in ipairs(retained) do assert(queue:indexOf(member)~=-1,'cancellation removed unrelated actions') end
 Checks.unchanged(queue,expected)
end

function Checks.deniedCancel(queue,api,policy,action,reason)
 local before=Checks.snapshot(queue);local decision=policy.evaluateCancel(queue,action,true)
 assert(not decision.allowed and decision.reason==reason,'active operation must remain protected')
 local allowed,actual=api.cancelOperation(queue,action)
 assert(not allowed and actual==reason,'active cancellation bypassed policy');Checks.unchanged(queue,before)
end

local function moved(queue,before,action,target,after)
 local index,targetIndex=queue:indexOf(action),queue:indexOf(target)
 assert(index>0 and targetIndex>0,'move action or target missing')
 assert(after and index>targetIndex or not after and index<targetIndex,'move did not reach requested side of target')
 local expected={}
 for _,member in ipairs(before) do if member~=action then expected[#expected+1]=member end end
 for i,member in ipairs(expected) do
  if member==target then table.insert(expected,i+(after and 1 or 0),action);break end
 end
 Checks.unchanged(queue,expected)
end

-- A single-action operation; composite moves need their own exact member list.
function Checks.moveRoundtrip(queue,api,policy,action,target,after,restoreTarget,restoreAfter)
 local before=Checks.snapshot(queue)
 assert(policy.evaluateMove(queue,action,target,after).allowed,'independent action move should be allowed')
 assert(api.move(queue,action,target,after),'independent action move failed')
 moved(queue,before,action,target,after)
 local intermediate=Checks.snapshot(queue)
 assert(api.move(queue,action,restoreTarget,restoreAfter),'independent action restore failed')
 moved(queue,intermediate,action,restoreTarget,restoreAfter);Checks.unchanged(queue,before)
end

return Checks
