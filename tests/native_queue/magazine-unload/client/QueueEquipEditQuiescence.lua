-- Test-only observation of the existing P4 idle boundary and shared loan
-- diagnostics. P4 exports registration functions, not its private state maps.
local M={}
function M.new(toolkit,player,empty,proof,events)
 local compat,settlement=toolkit.ActionQueueCompat,toolkit.ActionQueueSettlement
 local owner=P4TidyUpMeister
 assert(type(owner)=='table'and type(compat)=='table'and type(settlement)=='table','P4/Settlement observation unavailable')
 local installed,verify,operation,blocked=compat.isInstalled,compat.verifySources,settlement.operationState,settlement.hasActiveBlockedReturn
 assert(proof.closure(installed,'ActionQueueCompat.lua')and proof.closure(verify,'ActionQueueCompat.lua')
  and proof.closure(operation,'ActionQueueSettlement.lua')and proof.closure(blocked,'ActionQueueSettlement.lua')
  and proof.closure(owner.registerActionPolicy,'P4TidyUpMeister.lua')
  and proof.closure(owner.registerWornItemReplacement,'P4TidyUpMeister.lua'),'P4/Settlement source bindings unavailable')
 assert(installed('P4TidyUpMeister')==true and verify('P4TidyUpMeister')==true,'selected P4 source integration unavailable')
 local guard=assert(proof.captureBindings({{owner=_G,keys={'P4TidyUpMeister'}},
  {owner=toolkit,keys={'ActionQueueCompat','ActionQueueSettlement'}},
  {owner=compat,keys={'isInstalled','verifySources'}},{owner=settlement,keys={'operationState','hasActiveBlockedReturn'}},
  {owner=owner,keys={'registerActionPolicy','registerWornItemReplacement'}}}))
 local idleUpdates=0
 events.OnPlayerUpdate.Add(function(character)
  if character==player then idleUpdates=guard()and empty()and idleUpdates+1 or 0 end
 end)
 local observer={}
 function observer.reset()idleUpdates=0 end
 function observer.diagnose(tracks)
  local value={bindingsCurrent=guard()==true,idlePlayerUpdates=idleUpdates,queueEmpty=empty(),privateTablesObserved=false,operations={}}
  if not value.bindingsCurrent then return value end
  value.integrationInstalled=installed('P4TidyUpMeister')==true;value.activeBlockedReturn=blocked(player)
  local count=0
  for action in pairs(tracks)do
   count=count+1;if count>8 then value.truncated=true;break end
   value.operations[#value.operations+1]={type=action.Type,item=action.item and action.item:getID()or false,state=operation(action)or false}
  end
  return value
 end
 function observer.read(tracks)
  if not guard()or installed('P4TidyUpMeister')~=true or idleUpdates<6 or not empty()or blocked(player)~=false then return end
  local retained,borrowings,seen=0,0,0
  for action in pairs(tracks)do
   seen=seen+1;assert(seen<=8,'fixture action observation bound exceeded')
   local state=operation(action)
   if state then
    if type(state)~='table'or type(state.borrowings)~='table'or #state.borrowings>32 then return end
    retained=retained+1
    for _,loan in ipairs(state.borrowings)do
     borrowings=borrowings+1
     if type(loan)~='table'or loan.state~='completed'and loan.state~='waived'then return end
    end
   end
  end
  if not guard()or not empty()or blocked(player)~=false then return end
  return{sourceVerified=true,integrationInstalled=true,idlePlayerUpdates=idleUpdates,
   observer='ActionQueueSettlement.operationState',retainedOperations=retained,observedBorrowings=borrowings,
   outstandingBorrowings=0,activeBlockedReturn=false,privateTablesObserved=false}
 end
 return observer
end
return M
