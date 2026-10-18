require 'PZSurvivorToolkit/ActionQueuePanel'
require 'TimedActions/ISInventoryTransferAction'
require 'TimedActions/ISReadABook'
local config = require 'QueueTestSelection'
local Toolkit = PZSurvivorToolkit
local started, done, phase, step, since = false, false, 'prepare', 1, 0
local names = {'success', 'partial', 'rejected', 'withdraw'}
local boxes, items, tail, blocker, custom, target, expected, observed, read, window, itemName

local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()) end
local function key(object)
 local square = object:getSquare()
 return square:getX()..','..square:getY()..','..square:getZ()
end
local function snapshot(object)
 local stores = ModData.getOrCreate('LootSorter_Manifest').boxes or {}
 local record = stores[key(object)]
 return record and record[itemName] and record[itemName].n or 0
end
local function uiCount()
 local count = 0
 for _, row in ipairs(window.listBox.items) do
  if row.item.ft == 'Base.Nails' then count = count + row.item.n end
 end
 return count
end
local function empty(container)
 local values = container:getItems()
 for index = values:size()-1, 0, -1 do container:Remove(values:get(index)) end
end
local function book()
 local player = getPlayer()
 local item = assert(player:getInventory():AddItem('Base.BookCarpentry1'))
 item:setAlreadyReadPages(item:getNumberOfPages()-1)
 player:setAlreadyReadPages(item:getFullType(),item:getNumberOfPages()-1)
 return ISReadABook:new(player,item)
end
local function setup()
 assert(not isClient() and not isServer(), 'real SP required')
 local player = getPlayer()
 assert(Toolkit.Settings.actionQueue() == (config.mode == 'toolkit'), 'wrong queue mode')
 player:setGodMod(true); player:setGhostMode(true)
 assert(LootSorter._manifestXferHooked and LootSorter.toggleManifest, 'SP Manifest hook missing')
 local origin = require('QueueEnergyPlacement')(player)
 boxes = {}
 for _, offset in ipairs({{1,0},{0,1}}) do
  local square = assert(getCell():getGridSquare(origin:getX()+offset[1],origin:getY()+offset[2],origin:getZ()))
  local object = IsoThumpable.new(getCell(),square,'carpentry_01_16',false,{})
  object:setCanPassThrough(true); object:setIsContainer(true)
  local container = assert(object:getContainer())
  container:setType('crate'); container:setCapacity(100); container:setExplored(true)
  square:AddSpecialObject(object)
  boxes[#boxes+1] = object
 end
 assert(key(boxes[1]) ~= key(boxes[2]), 'source/destination snapshots must be independent')
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false) end
end
local function prepare()
 assert(#queue().queue == 0 and not getPlayer():hasTimedActions(), 'previous phase did not drain')
 local source, dest = boxes[1]:getContainer(), boxes[2]:getContainer()
 empty(source); empty(dest); dest:setCapacity(100)
 items = {assert(source:AddItem('Base.Nails')),assert(source:AddItem('Base.Nails'))}
 itemName = items[1]:getDisplayName()
 assert(items[1]:getID() ~= items[2]:getID(), 'fixture item IDs alias')
 if step == 1 then
  for _, object in ipairs(boxes) do
   LootSorter.setBoxItems(object,LootSorter.containerIndex(object,object:getContainer()),{[itemName]=true})
   assert(LootSorter.getRegistry()[key(object)], 'designation did not register its square')
  end
 end
 if names[step] == 'partial' then
  local filler = assert(instanceItem('Base.LargeStone'))
  local weight = items[1]:getActualWeight()
  assert(weight > 0 and weight <= 0.1, 'native lightweight batch input changed')
  filler:setActualWeight(dest:getEffectiveCapacity(getPlayer())-weight*1.5)
  filler:setCustomWeight(true)
  dest:AddItem(filler)
 elseif names[step] == 'rejected' then dest:setCapacity(0) end
 LootSorter.manifestReconcile()
 if not LootSorter._manifestWin then LootSorter.toggleManifest() end
 window = assert(LootSorter._manifestWin)
 window.filterText = string.lower(itemName); window:rebuild()
 assert(snapshot(boxes[1]) == 2 and snapshot(boxes[2]) == 0 and uiCount() == 2, 'initial Manifest differs from containers')
 assert(not LootSorter._manifestDirty[key(boxes[1])] and not LootSorter._manifestDirty[key(boxes[2])], 'previous dirty state leaked')
 observed, read = false, false
 expected = names[step] == 'success' and 2 or names[step] == 'rejected' and 0 or 1
 if names[step] == 'withdraw' then dest = getPlayer():getInventory() end
 local action = ISInventoryTransferAction:new(getPlayer(),items[1],source,dest)
 assert(action:isValid() == (expected > 0), 'native capacity precondition differs')
 if config.mode == 'toolkit' then assert(Toolkit.ActionQueuePolicy.inspect(action), 'Manifest native transfer lost its audited contract') end
 Toolkit.ActionQueueOperations.run(function()
  ISTimedActionQueue.add(action)
  if names[step] ~= 'withdraw' then ISTimedActionQueue.add(ISInventoryTransferAction:new(getPlayer(),items[2],source,dest)) end
 end)
 tail = book(); ISTimedActionQueue.add(tail)
 phase, since = 'transferring', getTimestampMs()
end
local function finishTransfer()
 local withdrawing = names[step] == 'withdraw'
 local source = boxes[1]:getContainer()
 local dest = withdrawing and getPlayer():getInventory() or boxes[2]:getContainer()
 local moved = 0
 for _, item in ipairs(items) do
  local inSource = source:getItemById(item:getID()) == item
  local inDest = dest:getItemById(item:getID()) == item
  assert(inSource ~= inDest and item:getContainer() == (inDest and dest or source), 'item lost, duplicated or source identity changed')
  if not withdrawing then assert(not getPlayer():getInventory():getItemById(item:getID()), 'world transfer leaked through player inventory') end
  if inDest then moved = moved + 1 end
 end
 assert(moved == expected, 'wrong native transfer amount')
 assert(dest:getCapacityWeight() <= dest:getEffectiveCapacity(getPlayer())+0.0001, 'native partial batch overfilled destination')
 assert(snapshot(boxes[1]) == 2-moved and snapshot(boxes[2]) == (withdrawing and 0 or moved) and uiCount() == (withdrawing and 1 or 2), 'drained Manifest/UI snapshot differs from actual item IDs')
 assert(read == (expected > 0) and observed == (expected > 0), 'native rejection/dirty/tail outcome changed')
 print('[QM_TRANSFER] PHASE '..names[step]..' moved='..moved..' remaining='..(2-moved)..' tailRead='..tostring(read)..' dirty='..tostring(observed))
 step = step + 1
 if names[step] then phase = 'prepare'
 else
  boxes[2]:getContainer():setCapacity(100)
  blocker = book(); ISTimedActionQueue.add(blocker)
  phase = 'custom'; since = getTimestampMs()
 end
end
local function customBoundaries()
 local player, q = getPlayer(), queue()
 if q.current ~= blocker or not blocker:isStarted() or blocker:getJobDelta() <= 0 then return end
 custom = {
  LootSorter.WalkAction:new(player,boxes[1]:getSquare()),
  LootSorter.DepositAction:new(player,items[2],boxes[1]:getContainer(),boxes[2]:getContainer()),
  LootSorter.CraftTriggerAction:new(player,nil,nil,1,function() error('opaque craft callback executed') end,nil),
 }
 for _, action in ipairs(custom) do ISTimedActionQueue.add(action) end
 target = book(); ISTimedActionQueue.add(target)
 local before = {}; for index, action in ipairs(q.queue) do before[index] = action end
 for _, action in ipairs(custom) do
  assert(not Toolkit.ActionQueuePolicy.inspect(action), 'unknown custom action gained a native contract')
  local ok, reason = Toolkit.ActionQueue.cancel(q,action)
  assert(not ok and reason == (config.mode == 'native' and 'unavailable' or 'dependent'), 'wrong custom cancellation denial: '..tostring(reason))
  ok, reason = Toolkit.ActionQueue.cancelOperation(q,action)
  assert(not ok and reason == (config.mode == 'native' and 'unavailable' or 'operation_dependent'), 'wrong custom operation denial: '..tostring(reason))
  ok, reason = Toolkit.ActionQueue.move(q,action,target,true)
  assert(not ok and reason == (config.mode == 'native' and 'unavailable' or 'move_dependent'), 'wrong custom reorder denial: '..tostring(reason))
 end
 assert(q.current == blocker and #q.queue == #before, 'denied editing mutated active queue')
 for index, action in ipairs(before) do assert(q.queue[index] == action, 'denied editing reordered identities') end
 assert(items[1]:getContainer() == player:getInventory() and items[2]:getContainer() == boxes[1]:getContainer(), 'denied editing mutated containers')
 print('[QM_TRANSFER] CUSTOM protected=3 queueUnchanged=true')
 ISTimedActionQueue.clear(player)
 phase = 'cleanup'
end
Events.OnGameStart.Add(function() started = true; since = getTimestampMs() end)
Events.OnTick.Add(function()
 if not started or done or not isIngameState() or not getPlayer() or not getPlayer():getSquare() then return end
 local ok, err = pcall(function()
  assert(getTimestampMs()-since < 120000, 'native transfer phase deadline '..phase)
  if not boxes then setup() end
  if phase == 'prepare' then prepare()
  elseif phase == 'transferring' then
   local q = queue()
   if q.current == tail and tail:isStarted() and tail:getJobDelta() > 0 then
    read = true
    assert(LootSorter._manifestDirty[key(boxes[1])] and (names[step] == 'withdraw' or LootSorter._manifestDirty[key(boxes[2])]), 'native perform failed to dirty designated squares')
    assert(snapshot(boxes[1]) == 2 and snapshot(boxes[2]) == 0, 'Manifest flushed before native queue drained')
    observed = true
   end
   if #q.queue == 0 and not getPlayer():hasTimedActions()
    and not LootSorter._manifestDirty[key(boxes[1])] and not LootSorter._manifestDirty[key(boxes[2])] then finishTransfer() end
  elseif phase == 'custom' then customBoundaries()
  elseif phase == 'cleanup' and #queue().queue == 0 and not getPlayer():hasTimedActions() then
   for _, object in ipairs(boxes) do
    local added = LootSorter._coordAddedAt and LootSorter._coordAddedAt[key(object)]
    if added and getTimestampMs()-added < LootSorter.ADD_GRACE_MS then return end
   end
   window:close()
   for _, object in ipairs(boxes) do
    local coordinate = key(object)
    LootSorter.setBoxItems(object,LootSorter.containerIndex(object,object:getContainer()),{})
    assert(not LootSorter.getRegistry()[coordinate], 'owned designation survived cleanup')
    object:getSquare():RemoveTileObject(object)
   end
   LootSorter.manifestReconcile()
   done = true
   print('[QM_TRANSFER] COMPLETE case=manifest')
  end
 end)
 if not ok then done = true; print('[QM_TRANSFER] FAIL '..tostring(err)) end
end)
