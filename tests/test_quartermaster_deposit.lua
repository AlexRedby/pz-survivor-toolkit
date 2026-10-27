-- Run actual B42 transfer/merge/completion code; only Java objects, animation and audio are doubles.
if not NativeActionRoot then
    print('Quartermaster deposit checks skipped (pass --game or --native-action-root).')
    return
end
local duplicates = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/QuartermasterDuplicates.lua')
require = function(name)
    if name == 'PZSurvivorToolkit/QuartermasterDuplicates' then return duplicates end
end
next = nil -- native Kahlua has no next() global
local clientMode = false
isClient, isServer = function() return clientMode end, function() return false end
instanceof = function(value, class) return value and value.class == class end
getTimestampMs, getTimestamp = function() return 1000 end, function() return 1000 end
getCore = function() return {getGameMode = function() return 'Sandbox' end} end
round = function(value, digits) local p = 10 ^ digits; return math.floor(value * p + .5) / p end
table.wipe = function(value) for key in pairs(value) do value[key] = nil end end
CharacterTrait, Metabolics = {DEXTROUS = 1, ALL_THUMBS = 2}, {LightWork = 1}
Events = {OnTick = {Add = function() end}}
ISInventoryPage = {}
ISLogSystem = {logAction = function() end}
for _, name in ipairs({'ClimbThroughWindowState', 'ClimbOverFenceState', 'ClimbOverWallState',
    'ClimbSheetRopeState', 'ClimbDownSheetRopeState', 'CloseWindowState', 'OpenWindowState'}) do
    _G[name] = {instance = function() return {} end}
end
local function native(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
native('shared/ISBaseObject.lua')
native('shared/TimedActions/ISBaseTimedAction.lua')
native('client/TimedActions/ISTimedActionQueue.lua')
native('client/TimedActions/ISInventoryTransferAction.lua')
native('shared/TimedActions/ISTransferAction.lua')
LootSorter = {isDebug = function() return false end}
dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/LootSorter_DepositAction.lua')

-- Leave all native validation, construction, batching and transfer methods intact.
local noOp = function() end
for _, name in ipairs({'playSourceContainerOpenSound', 'playDestContainerOpenSound',
    'playSourceContainerCloseSound', 'playDestContainerCloseSound', 'stopLoopingSound',
    'playTransferCompleteSound', 'startActionAnim'}) do
    ISInventoryTransferAction[name] = noOp
end
ISInventoryTransferAction.getTransferStartSoundName = function() return nil end
local soundCalls = {}
ISInventoryTransferAction.playTransferCompleteSound = function(_, value)
    soundCalls[value] = (soundCalls[value] or 0) + 1
end
local removals = {}
removeItemTransaction = function(id, aborted) removals[#removals + 1] = {id = id, aborted = aborted} end
local transactions, created, serial = {}, {}, 0
ISTradingUI = {GetUIForPlayer = function() return nil end}
getServerOptions = function() return {getInteger = function() return 0 end} end
isItemTransactionConsistent = function() return true end
createItemTransaction = function(character, items, source, destination)
    serial = serial + 1
    local tx = {id = serial, items = items, source = source, destination = destination, done = false, rejected = false}
    transactions[serial], created[#created + 1] = tx, tx
    return serial
end
isItemTransactionDone = function(id) return transactions[id] and transactions[id].done or false end
isItemTransactionRejected = function(id) return transactions[id] and transactions[id].rejected or false end
getItemTransactionDuration = function() return 0 end
local square = {TreatAsSolidFloor = function() return false end}
getCell = function() return {getGridSquare = function() return nil end} end
local emitter = {playSound = function() return 1 end, isPlaying = function() return false end}
local actor = {getInventory = function(self) return self.inventory end, getPlayerNum = function() return 0 end,
    hasTrait = function() return false end, isWearingAwkwardGloves = function() return false end,
    isTimedActionInstant = function() return false end, isPlayerMoving = function() return false end,
    getEmitter = function() return emitter end, setIsFarming = noOp, removeAttachedItem = noOp,
    setMetabolicTarget = noOp, isEquipped = function() return false end,
    getCurrentSquare = function() return square end, getX = function() return 0 end,
    getY = function() return 0 end, getZ = function() return 0 end}
local function container(capacity)
    local c = {items = {}, capacity = capacity, denied = {}, roomReads = 0}
    function c:getType() return 'crate' end
    function c:getItems()
        return {size = function() return #self.items end, get = function(_, i) return self.items[i + 1] end}
    end
    function c:getParent() return nil end
    function c:isVehicleSeat() return false end
    function c:isExistYet() return true end
    function c:isInside() return false end
    function c:isItemAllowed(item) return not self.denied[item.id] end
    function c:isRemoveItemAllowed() return true end
    function c:isInCharacterInventory() return self == actor.inventory end
    function c:contains(item) return item.container == self end
    function c:getEffectiveCapacity() return self.capacity end
    function c:getCapacityWeight()
        local weight = 0
        for _, item in ipairs(self.items) do weight = weight + item.weight end
        return weight
    end
    function c:hasRoomFor(_, item)
        self.roomReads = self.roomReads + 1
        return self:isItemAllowed(item) and self:getCapacityWeight() + item.weight <= self.capacity + 1e-9
    end
    function c:DoRemoveItem(item)
        for i, value in ipairs(self.items) do if value == item then table.remove(self.items, i); break end end
        if item.container == self then item.container = nil end
    end
    -- Native ItemContainer.AddItem(InventoryItem) does not perform an admission/capacity check.
    function c:AddItem(item)
        if item.container then item.container:DoRemoveItem(item) end
        self.items[#self.items + 1], item.container = item, self
        return item
    end
    c.setDrawDirty, c.setHasBeenLooted = noOp, noOp
    return c
end
local function item(id, source)
    local value = {id = id, weight = .1}
    function value:getContainer() return self.container end
    function value:getWeight() return self.weight end
    value.getActualWeight, value.getUnequippedWeight = value.getWeight, value.getWeight
    function value:getFullType() return 'Base.Nails' end
    function value:getType() return 'Nails' end
    function value:getIsCraftingConsumed() return false end
    function value:isFavorite() return false end
    value.setJobDelta = noOp
    source:AddItem(value)
    return value
end
local function action(class, value, source, destination)
    local a = class:new(actor, value, source, destination)
    a.action = {setTime = noOp, resetJobDelta = noOp, stopTimedActionAnim = noOp,
        setLoopedAction = noOp, setWaitForFinished = noOp, reset = noOp, getJobDelta = function() return 0 end,
        isStarted = function() return a.started == true end,
        forceStop = function() a.forcedStop = true; a:stop() end,
        forceComplete = function() a.forcedComplete = true end}
    -- Native onCompleted still removes this action and starts the next; Java begin() is a marker.
    a.begin = function(self) self.begun = true end
    return a
end
local function scenario(class, mode)
    soundCalls = {}
    actor.inventory = container(10)
    local source, destination, other = container(10), container(.2), container(10)
    local one, two, last = item(1, source), item(2, source), item(3, source)
    local a, b, tail = action(class, one, source, destination), action(class, two, source, destination),
        action(class, last, source, other)
    local queue = ISTimedActionQueue.getTimedActionQueue(actor)
    queue.queue, queue.current = {a, b, tail}, a
    assert(destination:hasRoomFor(actor, one) and destination:hasRoomFor(actor, two), 'planning precondition')
    assert(a:canMergeAction(b) and not a:canMergeAction(tail), 'native subclass batching boundary changed')
    if mode == 'capacity-before-start' then destination.capacity = .1
    elseif mode == 'full-at-start' then destination.capacity = 0
    elseif mode == 'admission' then destination.denied[2] = true end
    if mode ~= 'full-at-start' then assert(ISInventoryTransferAction.isValid(a), 'first item must fit at start') end
    local loops, merged = 0, false
    while queue.current do
        local current = queue.current
        if not current.testStarted then
            current.testStarted = true
            current:start()
            if current == a then
                if mode == 'capacity-after-start' then destination.capacity = 0 end
                if not current._lsSkip then
                    local reads = destination.roomReads
                    for _ = 1, 5 do current:update() end
                    assert(destination.roomReads == reads, 'waiting updates repeated native capacity scans')
                end
            end
        end
        current:perform()
        if current == a then
            local empty = true; for _ in pairs(b) do empty = false end
            merged = merged or empty -- real native checkQueueList removes and wipes the merged action
        end
        loops = loops + 1; assert(loops < 10, 'deposit queue did not drain')
    end
    assert(other:contains(last) and not source:contains(last), 'local rejection erased independent destination tail')
    assert(not a.forcedStop, 'local rejection used native queue cancellation')
    assert(destination:getCapacityWeight() <= destination.capacity + 1e-9, 'merged deposit overfilled destination')
    assert(not destination.denied[2] or not destination:contains(two), 'merged deposit bypassed per-item admission')
    local expected = (mode == 'full-at-start' or mode == 'capacity-after-start') and 0 or 1
    assert(#destination.items == expected and #source.items == 2 - expected, 'wrong partial deposit counts')
    if mode == 'full-at-start' then
        assert(a._lsSkip and not merged, 'full-at-start action did not remain a local skip')
    else
        assert(merged, 'fix disabled native merging instead of validating the merged items')
    end
    for _, value in ipairs({one, two}) do
        if source:contains(value) then
            assert(not soundCalls[value], 'skipped deposit played native successful-transfer audio')
        else
            assert((soundCalls[value] or 0) > 0, 'moved deposit lost native successful-transfer audio')
        end
    end
    assert((soundCalls[last] or 0) > 0, 'independent moved item lost native successful-transfer audio')
    return {soundCalls[one] or 0, soundCalls[two] or 0, soundCalls[last] or 0}
end

for _, mode in ipairs({'capacity-before-start', 'admission', 'capacity-after-start'}) do
    local control = scenario(ISInventoryTransferAction, mode) -- unchanged native implementation is the control
    local actual = scenario(LootSorter.DepositAction, mode)
    for i, count in ipairs(control) do assert(actual[i] == count, 'moved-item audio differs from native control') end
end
scenario(LootSorter.DepositAction, 'full-at-start')

-- Explicit player/engine cancellation must retain ordinary native stop/resetQueue semantics.
do
    actor.inventory = container(10)
    local source, destination = container(10), container(10)
    local a = action(LootSorter.DepositAction, item(10, source), source, destination)
    local tail = action(LootSorter.DepositAction, item(11, source), source, destination)
    local queue = ISTimedActionQueue.getTimedActionQueue(actor)
    queue.queue, queue.current = {a, tail}, a
    a:start(); a:stop()
    assert(#queue.queue == 0 and queue.current == nil, 'explicit stop no longer resets the native queue')
    assert(#source.items == 2 and #destination.items == 0, 'cancel performed a transfer')
    assert(removals[#removals].aborted == true, 'explicit stop lost native transaction cancellation')
end

-- Client-side Host status/transaction APIs are doubles; native start/update/perform/cleanup remain real.
-- The server effect below is applied only for accepted transactions, never a rejected payload.
local function serverAccept(tx)
    for _, value in ipairs(tx.items) do
        assert(tx.source:contains(value), 'accepted transaction lost its source item')
        assert(tx.destination:hasRoomFor(actor, value), 'accepted transaction exceeds actual destination room')
        ISTransferAction:transferItem(actor, value, tx.source, tx.destination, nil)
    end
    tx.done = true
end
-- Duplicate protection rechecks actual contents and keeps Host transactions separate.
for _, host in ipairs({false, true}) do
    clientMode = host
    actor.inventory = container(10)
    local source, destination, other = container(10), container(10), container(10)
    local one, two, last = item(701, source), item(702, source), item(703, source)
    local md = {LSBoxNoDuplicates = {['0'] = true}}
    local box = {obj = {getModData = function() return md end}, ci = 0, noDuplicates = true}
    local first, second, tail = action(LootSorter.DepositAction, one, source, destination),
        action(LootSorter.DepositAction, two, source, destination), action(LootSorter.DepositAction, last, source, other)
    first.lsDestinationBox, second.lsDestinationBox = box, box
    local queue = ISTimedActionQueue.getTimedActionQueue(actor)
    queue.queue, queue.current = {first, second, tail}, first
    assert(not first:canMergeAction(second) and not second:canMergeAction(first),
        'constrained actions merged past fresh admission')
    first:start()
    if host then serverAccept(transactions[first.transactionId]) end
    first:perform()
    assert(destination:contains(one) and queue.current == second)
    local beforeTransactions = #created
    second:start(); second:perform()
    assert(second._lsSkip and source:contains(two) and queue.current == tail and #destination.items == 1,
        'late duplicate must be skipped without dropping the independent tail')
    assert(not host or #created == beforeTransactions, 'duplicate started a Host transaction')
    tail:start()
    if host then serverAccept(transactions[tail.transactionId]) end
    tail:perform()
    assert(other:contains(last) and #queue.queue == 0)
    if not host then
        -- A duplicate arriving after start is also rejected at the SP effect boundary.
        destination:DoRemoveItem(one)
        local late = action(LootSorter.DepositAction, two, source, destination)
        late.lsDestinationBox = box
        queue.queue, queue.current = {late}, late
        late:start(); destination:AddItem(one); late:perform()
        assert(source:contains(two) and #destination.items == 1 and #queue.queue == 0)
        md.LSBoxNoDuplicates['0'] = nil
        assert(late:lsCanDeposit(), 'disabling restriction did not restore ordinary transfer admission')
    end
end
local function hostSetup()
    clientMode, transactions, created, removals, serial = true, {}, {}, {}, 0
    actor.inventory = container(10)
    local source, destination, other = container(10), container(10), container(10)
    local one, two, third, last = item(1, source), item(2, source), item(3, source), item(4, source)
    third.getFullType = function() return 'Base.EngineParts' end
    third.weight = .2 -- a second native group, still merged into this same src/dest action
    local a, b, c, tail = action(LootSorter.DepositAction, one, source, destination),
        action(LootSorter.DepositAction, two, source, destination),
        action(LootSorter.DepositAction, third, source, destination),
        action(LootSorter.DepositAction, last, source, other)
    local queue = ISTimedActionQueue.getTimedActionQueue(actor)
    queue.queue, queue.current = {a, b, c, tail}, a
    a:start()
    assert(a.started and a.transactionId ~= 0 and #created == 1, 'Host did not start a native transaction')
    assert(#queue.queue == 2 and queue.queue[2] == tail and #a.queueList == 2,
        'Host merge did not preserve native group/other-destination boundaries')
    return {action = a, tail = tail, queue = queue, first = one, second = two, third = third, last = last,
        source = source, destination = destination, other = other, rejected = created[1]}
end
do
    local s = hostSetup()
    s.rejected.rejected = true
    local batch = s.action.queueList[1]
    s.action:update()
    assert(s.action.forcedComplete and not s.action.forcedStop, 'known Host rejection canceled the queue')
    assert(s.action.queueList[1] == batch and #batch.items == 2, 'rejection mutated the failed payload before completion')
    s.action:perform()
    assert(#batch.items == 2 and batch.items[1] == s.first and batch.items[2] == s.second
        and s.rejected.items == batch.items, 'completion rewrote the rejected transaction payload')
    assert(s.queue.current == s.action and #created == 2 and #s.action.queueList == 1,
        'rejected batch erased the next native batch')
    assert(removals[1].id == s.rejected.id and removals[1].aborted == false,
        'rejected transaction missed ordinary native completion cleanup')
    assert(s.source:contains(s.first) and s.source:contains(s.second) and #s.destination.items == 0,
        'rejected payload transferred items')
    for index = 2, #created do
        for _, value in ipairs(created[index].items) do
            assert(value ~= s.first and value ~= s.second, 'rejected payload was retried')
        end
    end
    serverAccept(created[2]); s.action:update(); s.action:perform()
    assert(s.queue.current == s.tail and s.destination:contains(s.third), 'remaining native batch did not complete')
    s.tail:start(); serverAccept(created[3]); s.tail:update(); s.tail:perform()
    assert(#s.queue.queue == 0 and s.other:contains(s.last), 'Host rejection lost independent destination tail')
    assert(not s.action.forcedStop and not s.tail.forcedStop, 'successful Host continuation reset the queue')
    assert(#removals == 3 and removals[2].aborted == false and removals[3].aborted == false,
        'Host continuation changed native transaction cleanup')
end
for _, failure in ipairs({'zero-id', 'done-and-rejected', 'changed-id', 'changed-batch', 'cancel'}) do
    local s = hostSetup()
    s.rejected.rejected = true
    if failure == 'zero-id' then
        s.action.transactionId = 0
    elseif failure == 'done-and-rejected' then
        s.rejected.done = true
    end
    s.action:update()
    if failure == 'changed-id' then
        s.action.transactionId = 999
        s.action:perform()
    elseif failure == 'changed-batch' then
        s.action.queueList[1] = {items = {s.first, s.second}}
        s.action:perform()
    elseif failure == 'cancel' then
        s.action:stop() -- actor cancellation stays native even after the rejected result was observed
    end
    assert(#s.queue.queue == 0 and s.queue.current == nil, 'unknown Host failure/cancel retained the queue: ' .. failure)
    assert(failure == 'cancel' or s.action.forcedStop, 'unknown Host failure was treated as local rejection: ' .. failure)
    assert(removals[#removals].aborted == true, 'Host failure/cancel lost native transaction abort: ' .. failure)
    assert(#s.source.items == 4 and #s.destination.items == 0 and #s.other.items == 0,
        'Host failure/cancel transferred or replayed an item: ' .. failure)
    assert(#created == 1, 'Host failure/cancel retried a transaction: ' .. failure)
end
print('Quartermaster deposits passed: native SP merged capacity/admission, post-start changes, local skip/tail, Host rejected-batch cleanup/continuation, identity failures and native cancellation.')
