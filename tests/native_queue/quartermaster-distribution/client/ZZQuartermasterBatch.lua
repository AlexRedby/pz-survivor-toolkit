local config = require 'QueueTestSelection'
if config.cases[1] ~= 'batch' then return end
require 'TimedActions/ISQueueActionsAction'
require 'LootSorter_DepositAction'
local Placement = require 'QuartermasterDistributionFixture'
local F = require 'QuartermasterDepositFixture'
local JSON = require 'QueueHealthEvents'
local MODULE = 'QuartermasterBatchTest'
local started, done, since, updates, phase = false, false, 0, 0, 'prepare'
local point, packet, boxes, stage, merged, observed, transactionId
local authority, cleaned = {}, false
local function emit(event,value) print('[QM_BATCH] '..event..' '..JSON.encode(value)) end
local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()) end
Events.OnGameStart.Add(function()
 started, since = true, getTimestampMs()
 assert(isClient(), 'batch fixture requires menu Host')
 getPlayer():setGodMod(true); getPlayer():setGhostMode(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
end)
Events.OnPlayerUpdate.Add(function(player) if started and player == getPlayer() then updates=updates+1 end end)
Events.OnServerCommand.Add(function(module,command,value)
 if module ~= MODULE then return end
 if command == 'Prepared' then packet=value
 elseif command == 'Verified' then authority[value.stage]=value
 elseif command == 'Cleaned' then cleaned=true end
end)
local function enqueue(nextStage)
 stage, merged, observed, transactionId = nextStage, false, false, 0
 local player, source, limited = getPlayer(), boxes[1]:getContainer(), boxes[2]:getContainer()
 assert(limited:getCapacity()==1 and limited:getCapacityWeight()==F.ballastWeight, 'batch capacity precondition')
 local actions, count = {}, stage == 'rejected' and 3 or 2
 for i=1,count do
  local item=assert(source:getItemById(packet.ids[i]))
  assert(limited:hasRoomFor(player,item), 'individual batch item must fit')
  actions[i]=(stage=='rejected' and LootSorter.DepositAction or ISInventoryTransferAction):new(player,item,source,limited)
 end
 local first=actions[1]
 local start, complete=first.start,first.forceComplete
 first.start=function(self)
  start(self)
  assert(self.started and self.transactionId~=0 and #self.queueList==1 and #self.queueList[1].items==count,
   'native batch was not submitted intact')
  for i,item in ipairs(self.queueList[1].items)do assert(item:getID()==packet.ids[i], 'wrong native batch identity')end
  merged=true
 end
 first.forceComplete=function(self)
  local id=self.transactionId
  if id and id~=0 then
   local rejected,finished=isItemTransactionRejected(id),isItemTransactionDone(id)
   if stage=='rejected' and rejected and not finished or stage=='accepted' and finished and not rejected then
    observed,transactionId=true,id
   end
  end
  return complete(self)
 end
 ISTimedActionQueue.add(ISQueueActionsAction:new(player,function()
  for _,action in ipairs(actions)do ISTimedActionQueue.add(action)end
  if stage=='rejected' then
   ISTimedActionQueue.add(LootSorter.DepositAction:new(player,assert(source:getItemById(packet.ids[4])),source,boxes[3]:getContainer()))
  end
 end))
 phase='running'
end
local function tick()
 local player=getPlayer()
 if phase=='prepare' then
  if updates<30 then return end
  assert(#queue().queue==0 and not player:hasTimedActions(), 'batch fixture inherited actions')
  point=Placement.place(player);sendClientCommand(MODULE,'Prepare',point);phase='resolve'
 elseif phase=='resolve' then
  if not packet then return end
  boxes=F.resolve(packet);if not boxes then return end
  emit('PREPARED',packet);enqueue('rejected')
 elseif phase=='running' then
  if #queue().queue>0 or player:hasTimedActions()then return end
  assert(merged and observed and transactionId~=0, 'missing native batch outcome: '..stage)
  local result=F.receipt(player,boxes,packet,stage);if not result then return end
  emit(stage=='rejected' and 'REJECTED' or 'ACCEPTED',{result=result,merged=true,transactionId=transactionId})
  sendClientCommand(MODULE,'Verify',{stage=stage});phase='authority'
 elseif phase=='authority' then
  if not authority[stage]then return end
  if stage=='rejected' then enqueue('accepted')
  else sendClientCommand(MODULE,'Cleanup',{});phase='cleanup'end
 elseif phase=='cleanup' and cleaned then
  emit('CLEANUP',{objects=3});emit('COMPLETE',{case='batch',rejected=true,accepted=true,manual=true,continued=true})
  done=true
 end
end
Events.OnTick.Add(function()
 if not started or done or not isIngameState() or not getPlayer() or not getPlayer():getSquare()then return end
 local ok,problem=pcall(function()assert(getTimestampMs()-since<120000,'batch timeout phase='..phase);tick()end)
 if not ok then done=true;print('[QUEUE_TEST] FAIL batch '..tostring(problem))end
end)
