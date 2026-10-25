-- One cancelled remainder per local actor. Old objects are observation identities,
-- never executable capabilities: recovery builds fresh actions and operation tokens.
local Toolkit = PZSurvivorToolkit
local Adapters = require 'PZSurvivorToolkit/ActionQueueRecoveryAdapters'
local Recovery = {}
Toolkit.ActionQueueRecovery = Recovery
local histories = setmetatable({}, {__mode='k'})
local applying = setmetatable({}, {__mode='k'})
local serial = 0
local function localActor(player)
 return instanceof(player,'IsoPlayer') and getSpecificPlayer(player:getPlayerNum())==player
  and not player:isDead() and Toolkit.Settings.actionQueue()
end
local function completionEntered(queue, action)
 local lifecycle=Toolkit.ActionQueueLifecycle
 return lifecycle and lifecycle.completionEntered and lifecycle.completionEntered(queue,action)
end
local function activeReadable(queue, first, last, action)
 return first==1 and last==1 and action==queue.current and action.Type=='ISReadABook'
  and action.action and action.action:isStarted() and not action.action:finished()
  and not action.action:isForceComplete() and not completionEntered(queue,action)
end
function Recovery.capture(queue)
 local player=queue and queue.character
 if not localActor(player) or applying[player] or ISTimedActionQueue.queues[player]~=queue
  or not queue.queue or #queue.queue==0 then return end
 -- A reset can happen inside an unsuccessful completion callback; its current
 -- operation is not replayable, even if Java still retains the action.
 local saved={entries={},byAction={},natives={}}
 local i,meaningful=1,false
 while i<=#queue.queue do
  local action=queue.queue[i];local token=action.toolkitQueueOperation
  local last=i
  while token and queue.queue[last+1] and queue.queue[last+1].toolkitQueueOperation==token do last=last+1 end
  local entry={records={},steps=last-i+1}
  local firstBound,lastBound=Toolkit.ActionQueueOperations.bounds(queue,action)
  if not firstBound or firstBound~=i or lastBound~=last then entry.reason='split_operation' end
  local begun=type(token)=='table' and token.toolkitStarted
  local active=activeReadable(queue,i,last,action)
  if i==1 and completionEntered(queue,action) then entry.removed=true end
  for j=i,last do
   local member=queue.queue[j]
   saved.byAction[member]=entry
   if member.action then saved.natives[#saved.natives+1]=member.action end
   begun=begun or member.action~=nil or member.started==true or member._isAddingActions
  end
  if not entry.removed then
   meaningful=true
   if begun and not active then entry.reason=entry.reason or 'started_operation' end
   if not entry.reason then
    for j=i,last do
     local record,reason=Adapters.capture(queue.queue[j],active)
     if not record then entry.reason=reason or 'unsupported';break end
     entry.records[#entry.records+1]=record
    end
   end
   if entry.reason then entry.records=nil end
  end
  saved.entries[#saved.entries+1]=entry;i=last+1
 end
 -- A paid row retained for native settlement is not a new cancellation.
 if not meaningful then return end
 serial=serial+1;saved.id=serial;histories[player]=saved
end
-- cancelQueue is also a public native method. If it was called without wiping
-- the queue, original work may still run: do not later restore that work again.
function Recovery.started(action)
 local saved=action and histories[action.character]
 local entry=saved and saved.byAction[action]
 if entry then entry.removed=true end
end
Recovery.completed=Recovery.started
function Recovery.forget(player, expected)
 local saved=histories[player]
 if not saved or expected and saved.id~=expected then return false end
 histories[player]=nil;return true
end
function Recovery.info(player)
 if not player then return end
 if not localActor(player) then histories[player]=nil;return end
 local saved=histories[player]
 if not saved then return end
 local count,skipped,reason=0,0,nil
 for _,entry in ipairs(saved.entries)do
  if not entry.removed then
   if entry.records then count=count+1 else skipped=skipped+1;reason=reason or entry.reason end
  end
 end
 if count+skipped==0 then histories[player]=nil;return end
 return {id=saved.id,count=count,skipped=skipped,reason=reason}
end
local function candidate(player,expected)
 local info=Recovery.info(player)
 if not info or expected and info.id~=expected then return nil,'history_changed',info end
 local saved=histories[player]
 local queue=ISTimedActionQueue.queues[player]
 if player:isPlayerMoving() or player:pressedMovement(false) then return nil,'moving',info end
 if player:hasTimedActions() then return nil,'settling',info end
 local native=player:getCharacterActions()
 for _,action in ipairs(saved.natives)do
  if native:contains(action)then return nil,'settling',info end
 end
 if queue and (#queue.queue>0 or queue.toolkitCancel or queue.toolkitGroupCancel)then
  return nil,'busy',info
 end
 if player:isAsleep() then return nil,'busy',info end
 if info.count==0 then return nil,info.reason or 'unsupported',info end
 local records,groups={},{}
 for _,entry in ipairs(saved.entries)do
  if not entry.removed and entry.records then
   groups[#groups+1]=#entry.records
   for _,record in ipairs(entry.records)do records[#records+1]=record end
  end
 end
 local actions,reason=Adapters.plan(records,player)
 if not actions then return nil,reason or 'state_changed',info end
 if #actions~=#records then return nil,'unsupported',info end
 for _,action in ipairs(actions)do
  if action.character~=player or action.action or action.toolkitQueueOperation then return nil,'unsupported',info end
 end
 return {actions=actions,groups=groups,id=info.id},nil,info
end
function Recovery.preview(player)
 local plan,reason,info=candidate(player)
 if not info then return end
 info.available=plan~=nil;info.blocked=reason;return info
end
function Recovery.restore(player,expected)
 local plan,reason=candidate(player,expected)
 if not plan then return false,reason end
 -- No retry may replay an action if native allocation or a later add fails.
 -- Consume before invoking the existing executor, which retains all effects.
 histories[player]=nil;applying[player]=true
 local ok,result=pcall(function()
  local index=1
  for _,count in ipairs(plan.groups)do
   local token={}
   for _=1,count do
    local action=plan.actions[index];index=index+1
    action.toolkitQueueOperation=token
    local queue=ISTimedActionQueue.add(action)
    if not queue or queue:indexOf(action)==-1 then return false end
   end
  end
  return true
 end)
 applying[player]=nil
 if not ok or not result then return false,'enqueue_failed' end
 return true
end
Events.OnGameStart.Add(function()histories=setmetatable({}, {__mode='k'})end)
return Recovery
