local config = require 'QueueTestSelection'
if config.cases[1] ~= 'deposit' then return end
require 'TimedActions/ISQueueActionsAction'
require 'LootSorter_DepositAction'
local Placement = require 'QuartermasterDistributionFixture'
local F = require 'QuartermasterDepositFixture'
local JSON = require 'QueueHealthEvents'
local started, done, since, phase, updates = false, false, 0, 'prepare', 0
local point, state, packet, boxes, authority, cleaned, first, second
local merged, confirmedRejection, rejectionId, startCapacity = false, false, 0, 0
local function emit(event,value) print('[QM_DEPOSIT] '..event..' '..JSON.encode(value)) end
local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()) end
Events.OnPlayerUpdate.Add(function(player) if started and player == getPlayer() then updates=updates+1 end end)
Events.OnGameStart.Add(function()
 started, since = true, getTimestampMs()
 getPlayer():setGodMod(true); getPlayer():setGhostMode(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
end)
Events.OnServerCommand.Add(function(module,command,value)
 if module ~= F.module then return end
 if command == 'Prepared' then packet=value
 elseif command == 'Verified' then authority=value
 elseif command == 'Cleaned' then cleaned=true end
end)
local function enqueue()
 local player, source, limited, tail = getPlayer(), boxes[1]:getContainer(), boxes[2]:getContainer(), boxes[3]:getContainer()
 if isClient() then limited:setCapacity(100) end -- deliberate local admission; actual server capacity remains zero
 startCapacity = limited:getCapacity()
 assert(startCapacity == (isClient() and 100 or 2), 'deposit initial capacity differs')
 local items = {}
 for i, id in ipairs(packet.ids) do
  items[i]=assert(source:getItemById(id))
  assert(items[i]:getActualWeight()==F.nailWeight and items[i]:getWeight()==F.nailWeight, 'replicated nail weight differs')
 end
 assert(limited:hasRoomFor(player,items[1]) and limited:hasRoomFor(player,items[2]), 'first batch cannot enter native start')
 first=LootSorter.DepositAction:new(player,items[1],source,limited)
 second=LootSorter.DepositAction:new(player,items[2],source,limited)
 local last=LootSorter.DepositAction:new(player,items[3],source,tail)
 local start, perform, complete = first.start, first.perform, first.forceComplete
 first.start=function(self)
  start(self)
  assert(self.started and not self._lsSkip, 'first deposit did not start naturally')
  if isClient() then
   assert(self.transactionId~=0 and #self.queueList==1 and #self.queueList[1].items==2,
    'Host did not merge two nails before native Request')
   assert(self.queueList[1].items[1]==items[1] and self.queueList[1].items[2]==items[2], 'Host merged wrong IDs')
   merged=true
  else
   limited:setCapacity(1) -- change after production start, before the native merged perform
   assert(limited:getEffectiveCapacity(player)==1 and limited:getCapacityWeight()==F.ballastWeight
    and limited:hasRoomFor(player,items[1]), 'SP one-item capacity precondition differs')
   -- Native rounds the current load before adding the incoming item's weight.
   assert(ItemContainer.floatingPointCorrection(F.ballastWeight+F.nailWeight)+F.nailWeight
    >limited:getEffectiveCapacity(player), 'SP second nail still fits')
  end
 end
 first.perform=function(self)
  perform(self)
  if not isClient() then
   local empty=true; for _ in pairs(second) do empty=false end
   assert(empty, 'SP native transfer did not merge the second action')
   merged=true
  end
 end
 first.forceComplete=function(self)
  local id=self.transactionId
  if isClient() and id and id~=0 and isItemTransactionRejected(id) and not isItemTransactionDone(id) then
   confirmedRejection, rejectionId=true,id
  end
  return complete(self)
 end
 -- Native add-actions barrier keeps all three actions queued before first:start() can run.
 ISTimedActionQueue.add(ISQueueActionsAction:new(player,function()
  ISTimedActionQueue.add(first); ISTimedActionQueue.add(second); ISTimedActionQueue.add(last)
 end))
end
local function tick()
 local player=getPlayer()
 if phase=='prepare' then
  if updates<30 then return end
  assert(#queue().queue==0 and not player:hasTimedActions(), 'deposit fixture inherited timed actions')
  point=Placement.place(player)
  if isClient() then sendClientCommand(F.module,'Prepare',point)
  else state=F.prepare(player,point,'sp'); packet=F.descriptor(state) end
  phase='resolve'
 elseif phase=='resolve' then
  if not packet then return end
  boxes=F.resolve(packet); if not boxes then return end
  emit('PREPARED',packet)
  enqueue(); phase='running'
 elseif phase=='running' then
  if #queue().queue>0 or player:hasTimedActions() then return end
  assert(merged, 'deposit merged batch never executed')
  assert(confirmedRejection==isClient() and (not isClient() or rejectionId~=0), 'native Host Request rejection was not proved')
  if isClient() then boxes[2]:getContainer():setCapacity(0) end -- restore actual server capacity for final matching receipts
  local result=F.receipt(player,boxes,packet); if not result then return end
  result.merged, result.confirmedRejectionMP, result.rejectionId, result.startCapacity=merged,confirmedRejection,rejectionId,startCapacity
  emit('LOCAL',result)
  if isClient() then sendClientCommand(F.module,'Verify',{})
  else authority=assert(F.receipt(player,boxes,packet)); emit('AUTHORITY',authority) end
  phase='verified'
 elseif phase=='verified' then
  if not authority then return end
  if isClient() then sendClientCommand(F.module,'Cleanup',{})
  else F.cleanup(state); cleaned=true end
  phase='cleanup'
 elseif phase=='cleanup' and cleaned then
  emit('CLEANUP',{objects=3})
  emit('COMPLETE',{case='deposit',kind=config.kind,merged=merged,confirmedRejectionMP=confirmedRejection})
  done=true
 end
end
Events.OnTick.Add(function()
 if not started or done or not isIngameState() or not getPlayer() or not getPlayer():getSquare() then return end
 local ok,problem=pcall(function()
  assert(getTimestampMs()-since<120000,'deposit timeout phase='..phase)
  tick()
 end)
 if not ok then done=true; print('[QUEUE_TEST] FAIL deposit '..tostring(problem)) end
end)
