local Completion={}
function Completion.observe(toolkit,selection)
 local lifecycle,operations=toolkit.ActionQueueLifecycle,toolkit.ActionQueueOperations
 local begin,finish,flush,perform,defer=lifecycle.begin,lifecycle.finish,lifecycle.flush,operations.perform,operations.deferCompletion
 local state,records,counts,restores
 local enabled=selection.mode=='toolkit'
 local function observed(action)
  if not state or not action then return end
  local kind=select(2,toolkit.ActionQueueDefinitions.inspect(action))
  if kind=='compat.tidy-transfers' then return counts end
  if kind=='compat.tidy-equipment' then return restores end
 end
 local function retained(action,record)
  local queue=ISTimedActionQueue.queues[action.character]
  assert(queue and queue.current==action and queue.queue[1]==action
   and action.action==record.native and action.toolkitQueueOperation==record.token,
   'Tidy transfer lost its native parent or operation')
  assert(action.item:getID()==record.id and action.item:getFullType()==record.kind
   and (record.counts~=counts or action.srcContainer==state.root and action.destContainer==state.source),
   'Tidy transfer changed its exact item or endpoints')
 end
 lifecycle.begin=function(action,phase)
  local active=begin(action,phase)
  local counter=observed(action)
  if not counter then return active end
  assert(active==enabled,'wrong native Tidy completion boundary mode')
  if not active then return active end
  assert(lifecycle.current(action.character)==action and action.action,'Tidy transfer has no active native scope')
  local record=records[action]
  if phase=='perform' then
   assert(not record,'duplicate native Tidy perform')
   local id=action.item:getID()
   assert(state.baseline[id] and state.baseline[id]:getFullType()==action.item:getFullType(),
    'Tidy transfer returned an unexpected exact item')
   record={id=id,kind=action.item:getFullType(),native=action.action,token=action.toolkitQueueOperation,counts=counter}
   if counter==restores then
    local primary=action.item:getID()==state.hammer:getID() and action.item:getFullType()==state.hammer:getFullType()
    assert(action.Type=='ISUnequipAction' and state.id=='tidy-empty-hands' and action.item:getID()==state.pickup:getID()
     or primary or action.item:getID()==state.screwdriver:getID() and action.item:getFullType()==state.screwdriver:getFullType(),
     'P4 restored unexpected equipment')
    local queue=ISTimedActionQueue.queues[action.character]
    local decision=toolkit.ActionQueuePolicy.evaluateCancel(queue,action,true)
    assert(not decision.allowed,'shared equipment cleanup must remain protected')
    if action.Type=='ISEquipWeaponAction' then
     assert(action.primary==primary and not action.twoHands,'P4 restored wrong hand slots')
     restores.equip=restores.equip+1
    elseif action.Type=='ISUnequipAction' then
     local held=action.character:getPrimaryHandItem()
     -- Host may replicate the authoritative unequip before the client performs its UI cleanup.
     assert(not action.character:getSecondaryHandItem() and (held==action.item or selection.kind=='mp' and not held),
      'P4 removed wrong temporary equipment')
     restores.unequip=restores.unequip+1
    else
     assert(action.Type=='P4RestoreAction' and action.activated==primary,'P4 restored wrong activation')
     restores.activation=restores.activation+1
    end
   end
   records[action]=record
  else
   assert(phase=='complete' and selection.kind=='sp' and record and record.perform=='finished',
    'Tidy complete preceded perform or ran on the Host client')
  end
  retained(action,record)
  assert(not record[phase],'duplicate native Tidy completion phase');record[phase]='begun'
  return active
 end
 lifecycle.finish=function(action,phase,succeeded)
  local record=records and records[action]
  if record then
   retained(action,record)
   assert(record[phase]=='begun' and succeeded,'Tidy completion phase did not finish once')
  end
  finish(action,phase,succeeded)
  if record then record[phase]='finished';record.counts[phase]=record.counts[phase]+1 end
 end
 lifecycle.flush=function(queue)
  local action=queue.current
  local record=records and records[action]
  local absent=record and not queue.character:getCharacterActions():contains(record.native)
  local outcome,finished=flush(queue)
  if record and outcome=='completed' then
   assert(finished==action and absent and not record.flushed and record.perform=='finished'
    and (selection.kind=='mp' or record.complete=='finished'),
    'Tidy transfer flushed before native completion/removal or twice')
   record.flushed=true;record.counts.flush=record.counts.flush+1
  end
  return outcome,finished
 end
 operations.perform=function(action,callback,...)
  return perform(action,function(parent,...)
   if observed(parent) and lifecycle.current(parent.character)==parent then
    local queue=ISTimedActionQueue.queues[parent.character]
    if defer(queue,parent) then
     local counter=observed(parent);counter.legacy=counter.legacy+1
     error('Tidy transfer used legacy completion inside its native scope')
    end
   end
   return callback(parent,...)
  end,...)
 end
 function Completion.watch(value)
  state,records,counts=value,{},{perform=0,complete=0,flush=0,legacy=0}
  restores={perform=0,complete=0,flush=0,legacy=0,equip=0,activation=0,unequip=0}
 end
 function Completion.settled()
  assert(counts.perform==counts.flush and counts.complete==(selection.kind=='sp' and counts.perform or 0)
   and counts.legacy==0,'Tidy native completion counts did not settle')
  for _,record in pairs(records) do assert(record.flushed,'Tidy transfer never flushed') end
  return counts
 end
 function Completion.restores()
  assert(restores.flush==restores.perform and restores.complete==(selection.kind=='sp' and restores.perform or 0)
   and restores.legacy==0,'P4 equipment completion did not settle')
  return restores
 end
 return Completion
end
return Completion
