local Rack={}
local Checks=require 'QueueScenarioChecks'
function Rack.controls(state,helpers)
 local queue,api,policy,operations=helpers.queue(),helpers.api,helpers.policy,helpers.operations
 local pickup,equip,rack=state.pickupAction,state.rackEquipAction,state.rackAction
 local original={state.frontAction,pickup,equip,rack,state.tailAction}
 Checks.unchanged(queue,original)
 local current,native=queue.current,state.frontAction.action
 assert(current==state.frontAction and native,'rack controls require the unrelated active reading head')
 local token=pickup.toolkitQueueOperation
 assert(token and equip.toolkitQueueOperation==token and rack.toolkitQueueOperation==token
  and state.frontAction.toolkitQueueOperation~=token and state.tailAction.toolkitQueueOperation~=token,
  'rack preparation/operation must share one token separate from unrelated reading')
 local first,last=operations.bounds(queue,pickup)
 assert(first==2 and last==4,'rack operation must contain exactly pickup, equip and rack')
 local contract,kind=helpers.definitions.inspect(rack)
 assert(kind=='native.ISRackFirearm'and contract and contract.knownInputs~=false
  and contract.items[state.pickup:getID()]and contract.equipment==state.player
  and contract.outputTypes[state.pickup:getAmmoType():getItemKey()]and contract.cancelOperation==false,
  'native rack resource/cancellation contract missing')
 -- The exact gun and possible ammo output are tracked, so this unrelated book
 -- is movable. Cancellation of the rack operation still lacks permission.
 Checks.deniedCancel(queue,api,policy,pickup,'operation_dependent')
 state.rackCancellationProtected=true
 local decision=policy.evaluateMove(queue,pickup,state.tailAction,true)
 assert(decision.allowed,'independent book blocks whole rack operation: '..tostring(decision.reason))
 assert(api.move(queue,pickup,state.tailAction,true),'whole rack operation move failed')
 Checks.unchanged(queue,{state.frontAction,state.tailAction,pickup,equip,rack})
 first,last=operations.bounds(queue,rack)
 assert(first==3 and last==5,'whole rack operation split while crossing the independent tail')
 -- Select another member to prove the API restores the whole operation rather
 -- than moving only the originally selected pickup action.
 decision=policy.evaluateMove(queue,rack,state.tailAction,false)
 assert(decision.allowed,'whole rack operation cannot restore: '..tostring(decision.reason))
 assert(api.move(queue,rack,state.tailAction,false),'whole rack operation restore failed')
 Checks.unchanged(queue,original)
 assert(queue.current==current and state.frontAction.action==native
  and pickup.toolkitQueueOperation==token and equip.toolkitQueueOperation==token and rack.toolkitQueueOperation==token,
  'whole rack roundtrip changed active reading or native operation ownership')
 state.rackWholeOperationMoveVerified=true;state.independentMoveVerified=true
end
return Rack
