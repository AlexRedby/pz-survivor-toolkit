require 'PZSurvivorToolkit/ActionQueuePanel'
require 'TimedActions/ISInventoryTransferAction'
require 'TimedActions/ISReadABook'
local config = require 'QueueTestSelection'
local P = require 'QueueEnergyPlacement'
local JSON = require 'QueueHealthEvents'
local Toolkit = PZSurvivorToolkit
local started, done, phase, step, since = false, false, 'prepare', 1, 0
local names = {'success', 'partial', 'rejected', 'withdraw'}
local boxes, items, tail, blocker, custom, target, expected, observed, read, window, itemName
local actor, origin, placement, layout

local function emit(event, row) print('[QM_TRANSFER_PLACEMENT] '..event..' '..JSON.encode(row)) end
local function envelope()
 return {case='manifest',phase=layout.phase,index=layout.index,token=layout.token,target=P.target(origin)}
end
local function fresh()
 local player = getPlayer()
 assert(player == actor and P.atCentered(player,origin), 'Quartermaster actor left reserved centered placement')
 local motion = P.snapshot(player,true,Vector2.new())
 assert(motion.queued == 0 and not motion.timed and not motion.moving and not motion.hasPath
  and motion.deferredX == 0 and motion.deferredY == 0, 'Quartermaster placement still has native work or motion')
 if boxes then
  for index, object in ipairs(boxes) do
   local square, reserved = object:getSquare(), layout.boxes[index]
   assert(square and square:getX() == reserved.x and square:getY() == reserved.y and square:getZ() == reserved.z
    and object:getObjectIndex() >= 0 and square:getObjects():get(object:getObjectIndex()) == object,
    'Quartermaster crate left reserved placement')
  end
 end
end
local function beginPlacement()
 assert(not isClient() and not isServer(), 'real SP required')
 actor = actor or assert(getPlayer())
 assert(getPlayer() == actor, 'Quartermaster placement actor replaced')
 origin = origin or P.choose(actor)
 -- Reserve the layout without creating or changing fixtures.
 layout = {case='manifest',phase=names[step] or 'custom',index=step,
  token='quartermaster:'..getTimestampMs()..':'..step,target=P.target(origin),
  boxes={{x=origin.x+1,y=origin.y,z=origin.z},{x=origin.x,y=origin.y+1,z=origin.z}}}
 emit('LAYOUT',layout)
 placement = P.beginCentered(actor,origin)
 phase, since = 'placement', getTimestampMs()
end
local function prepared()
 fresh()
 local row = envelope(); row.boxes = {}
 for _, object in ipairs(boxes) do
  local square = object:getSquare()
  row.boxes[#row.boxes+1] = {x=square:getX(),y=square:getY(),z=square:getZ()}
 end
 for i, point in ipairs(row.boxes) do
  local reserved = layout.boxes[i]
  assert(point.x == reserved.x and point.y == reserved.y and point.z == reserved.z, 'Quartermaster crate left reserved layout')
 end
 emit('PREPARED',row)
end
local function admitted()
 fresh(); emit('ADMITTED',envelope())
end

local function queue() return ISTimedActionQueue.getTimedActionQueue(getPlayer()) end
local function key(object)
 local square = object:getSquare()
 return square:getX()..','..square:getY()..','..square:getZ()
end
local function snapshot(object)
 local total = 0
 for _, record in pairs(Toolkit.ManifestAuthority.getStore().containers) do
  if record.key == key(object) then
   for _, entry in pairs(record.entries) do if entry.ft == 'Base.Nails' then total = total + entry.n end end
  end
 end
 return total
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
local function itemBoundary(point)
 local inventory = getPlayer():getInventory()
 local source, dest = boxes[1]:getContainer(), boxes[2]:getContainer()
 local rows = {}
 for _, item in ipairs(items) do
  local current = item:getContainer()
  rows[#rows+1] = {id=item:getID(),root=inventory:getItemById(item:getID()) == item,
   source=source:getItemById(item:getID()) == item,dest=dest:getItemById(item:getID()) == item,
   container=current == inventory and 'root' or current == source and 'source' or current == dest and 'dest' or tostring(current)}
 end
 print('[QM_TRANSFER_ITEMS] '..JSON.encode({point=point,items=rows}))
end
local function customItemsPresent()
 local inventory, source, dest = getPlayer():getInventory(), boxes[1]:getContainer(), boxes[2]:getContainer()
 return items[1]:getContainer() == inventory and inventory:getItemById(items[1]:getID()) == items[1]
  and not source:getItemById(items[1]:getID()) and not dest:getItemById(items[1]:getID())
  and items[2]:getContainer() == source and source:getItemById(items[2]:getID()) == items[2]
  and not inventory:getItemById(items[2]:getID()) and not dest:getItemById(items[2]:getID())
end
local function prepareCustom()
 fresh()
 local inventory, source, dest = getPlayer():getInventory(), boxes[1]:getContainer(), boxes[2]:getContainer()
 -- Idle restoration from the preceding withdrawal may legitimately return its
 -- item before this round settles. Retire only those exact owned identities,
 -- then give this independent denial scenario its own root/world inputs.
 local retired = {}
 for _, item in ipairs(items) do
  local container = item:getContainer(); local id = item:getID()
  retired[id] = true
  assert((container == inventory or container == source or container == dest)
   and container:getItemById(id) == item, 'previous owned transfer item missing before custom preparation')
  container:Remove(item)
  assert(not inventory:getItemById(id) and not source:getItemById(id) and not dest:getItemById(id), 'previous owned transfer item survived retirement')
 end
 empty(source); empty(dest); dest:setCapacity(100)
 items = {assert(inventory:AddItem('Base.Nails')),assert(source:AddItem('Base.Nails'))}
 assert(items[1]:getID() ~= items[2]:getID() and not retired[items[1]:getID()]
  and not retired[items[2]:getID()] and customItemsPresent(), 'custom root/world inputs differ')
 itemBoundary('custom-prepared')
end
local function setup()
 fresh()
 assert(not isClient() and not isServer(), 'real SP required')
 local player = getPlayer()
 assert(Toolkit.Settings.actionQueue() == (config.mode == 'toolkit'), 'wrong queue mode')
 player:setGodMod(true); player:setGhostMode(true)
 assert(Toolkit.ManifestAuthority and LootSorter.toggleManifest, 'shared Manifest service missing')
 boxes = {}
 for _, offset in ipairs({{1,0},{0,1}}) do
  local square = assert(getCell():getGridSquare(origin.x+offset[1],origin.y+offset[2],origin.z))
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
 fresh()
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
 if not LootSorter._manifestWin then LootSorter.toggleManifest() end
 window = assert(LootSorter._manifestWin)
 window.filterText = string.lower(itemName); window:rebuild()
 phase, since = 'prime', getTimestampMs()
end
local function startTransfer()
 admitted()
 local source, dest = boxes[1]:getContainer(), boxes[2]:getContainer()
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
 if withdrawing then
  assert(items[1]:getContainer() == getPlayer():getInventory() and items[2]:getContainer() == source,
   'withdrawal did not move the exact requested item')
 end
 assert(dest:getCapacityWeight() <= dest:getEffectiveCapacity(getPlayer())+0.0001, 'native partial batch overfilled destination')
 assert(snapshot(boxes[1]) == 2-moved and snapshot(boxes[2]) == (withdrawing and 0 or moved) and uiCount() == (withdrawing and 1 or 2), 'drained Manifest/UI snapshot differs from actual item IDs')
 assert(read == (expected > 0) and observed == (expected > 0), 'native rejection/queue/tail outcome changed')
 print('[QM_TRANSFER] PHASE '..names[step]..' moved='..moved..' remaining='..(2-moved)..' tailRead='..tostring(read)..' queueObserved='..tostring(observed))
 if withdrawing then itemBoundary('withdraw-finished') end
 step = step + 1
 phase = 'prepare'
end
local function customBoundaries()
 local player, q = getPlayer(), queue()
 if q.current ~= blocker or not blocker:isStarted() or blocker:getJobDelta() <= 0 then return end
 assert(player == actor and P.atCentered(player,origin), 'Quartermaster custom actor left reserved placement')
 assert(customItemsPresent(), 'custom root/world inputs changed before denied edits')
 itemBoundary('custom-entry')
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
  assert(not ok and reason == (config.mode == 'native' and 'unavailable' or 'edit_unknown'), 'wrong custom cancellation denial: '..tostring(reason))
  ok, reason = Toolkit.ActionQueue.cancelOperation(q,action)
  assert(not ok and reason == (config.mode == 'native' and 'unavailable' or 'edit_unknown'), 'wrong custom operation denial: '..tostring(reason))
  ok, reason = Toolkit.ActionQueue.move(q,action,target,true)
  assert(not ok and reason == (config.mode == 'native' and 'unavailable' or 'edit_unknown'), 'wrong custom reorder denial: '..tostring(reason))
 end
 assert(q.current == blocker and #q.queue == #before, 'denied editing mutated active queue')
 for index, action in ipairs(before) do assert(q.queue[index] == action, 'denied editing reordered identities') end
 assert(customItemsPresent(), 'denied editing mutated containers')
 itemBoundary('custom-after-edits')
 print('[QM_TRANSFER] CUSTOM protected=3 queueUnchanged=true')
 ISTimedActionQueue.clear(player)
 phase = 'cleanup'
end
require('QueuePreflight').onGameStart(Events,function() started = true; since = getTimestampMs() end)
require('QueuePreflight').onTick(Events,function()
 if not started or done or not isIngameState() or not getPlayer() or not getPlayer():getSquare() then return end
 local ok, err = pcall(function()
  assert(getTimestampMs()-since < 120000, 'native transfer phase deadline '..phase)
  if phase == 'prepare' then beginPlacement()
  elseif phase == 'placement' then
   local proof = P.poll(placement); if not proof then return end
   fresh(); local row = envelope(); row.proof = proof; emit('LOCAL',row)
   if not boxes then setup() end
   if names[step] then prepare(); prepared()
   else
    prepareCustom()
    prepared(); admitted()
    blocker = book(); ISTimedActionQueue.add(blocker)
    phase, since = 'custom', getTimestampMs()
   end
  elseif phase == 'prime' then
   fresh()
   if snapshot(boxes[1]) == 2 and snapshot(boxes[2]) == 0 and uiCount() == 2 then startTransfer() end
  elseif phase == 'transferring' then
   local q = queue()
   if q.current == tail and tail:isStarted() and tail:getJobDelta() > 0 then
    read = true
    observed = true
   end
   local wanted = names[step] == 'withdraw' and 1 or 2
   if #q.queue == 0 and not getPlayer():hasTimedActions()
    and snapshot(boxes[1]) == 2-expected and snapshot(boxes[2]) == (names[step] == 'withdraw' and 0 or expected)
    and uiCount() == wanted then finishTransfer() end
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
     phase = 'cleanupSnapshot'
  elseif phase == 'cleanupSnapshot' and snapshot(boxes[1]) == 0 and snapshot(boxes[2]) == 0 then
   done = true
   print('[QM_TRANSFER] COMPLETE case=manifest')
  end
 end)
 if not ok then done = true; print('[QM_TRANSFER] FAIL '..tostring(err)) end
end)
