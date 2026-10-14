-- Native queue and transfer contracts, with synchronous UI dispatch doubles.
if not NativeActionRoot then
    print('Action operation native-contract checks skipped (pass --native-action-root media/lua).')
    return
end
require = function() end
PZSurvivorToolkit = {}
local function derive(self, name)
    local t = {Type = name, derive = derive}
    t.__index = t
    return setmetatable(t, {__index = self})
end
ISBaseObject = {derive = derive}
Events = {OnTick = {Add = function() end}}
for _, name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState',
    'ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do
    _G[name] = {instance = function() return {} end}
end
instanceof = function(value, name) return value and value.class == name end
table.wipe = function(t) for k in pairs(t) do t[k] = nil end end
round = function(value) return value end
local function load(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
load('shared/TimedActions/ISBaseTimedAction.lua')
load('client/TimedActions/ISTimedActionQueue.lua')
load('client/TimedActions/ISQueueActionsAction.lua')
ISQueueActionsAction.begin = function(self) self.action = {forceComplete = function() end} end
ISInventoryPage = {}
load('client/TimedActions/ISInventoryTransferAction.lua')
load('client/ISUI/ISCraftingUI.lua')
local player = {class = 'IsoPlayer', getPlayerNum = function() return 0 end,
    isAsleep = function() return false end, isLocalPlayer = function() return true end,
    isDraggingCorpse = function() return false end, isFarming = function() return false end,
    hasTrait = function() return false end}
player.inventory = {}
function player:getInventory() return self.inventory end
getSpecificPlayer = function() return player end
CharacterTrait = {DISORGANIZED = 'disorganized'}
local function action(kind, item)
    return {character = player, Type = kind or 'TestAction', item = item,
        begin = function(self) assert(self.toolkitQueueOperation, 'stamp before native begin'); self.action = {} end,
        isValidStart = function() return true end,
        setAllowMissingItems = function(self, value) self.allowMissingItems = value end}
end
ISInventoryTransferUtil = {newInventoryTransferAction = function(p, item, source, destination)
    local a = action('ISInventoryTransferAction', item)
    a.srcContainer, a.destContainer = source, destination
    return a
end}
ISReadABook = {new = function(_, p, item) return action('ISReadABook', item) end}
ISInventoryPaneContextMenu = {transferIfNeeded = function(p, item)
    if item:getContainer() ~= p:getInventory() then
        ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(p, item, item:getContainer(), p:getInventory()))
    end
end}
-- Execute the actual native readItem function, including pickup and return.
local nativeContext = NativeInventoryContextMenuSource
if not nativeContext then
    local file = assert(io.open(NativeActionRoot .. '/client/ISUI/ISInventoryPaneContextMenu.lua'))
    nativeContext = file:read('*a'); file:close()
end
nativeContext = nativeContext:gsub('\r', '')
local readItem = assert(nativeContext:match('(ISInventoryPaneContextMenu.readItem = function%(item, player%).-\nend)'))
assert(loadstring(readItem))()
local function dispatch(_, callback, ...) return callback(...) end
ISContextMenu = {onMouseUp = dispatch, onJoypadDown = dispatch, onJoypadDirLeft = dispatch}
ISButton = {onMouseUp = dispatch, forceClick = dispatch}
ISInventoryPane = {onMouseUp = dispatch, onMouseDoubleClick = dispatch}
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueOperations.lua'))()
local operations = PZSurvivorToolkit.ActionQueueOperations
local q = ISTimedActionQueue.getTimedActionQueue(player)
local function reset() q.queue = {}; q.current = nil end
local function enqueue() local a = action(); ISTimedActionQueue.add(a); return a end
local first, second, nested
local one, hole, three, fourth = operations.run(function()
    first = enqueue()
    nested = operations.run(enqueue)
    second = enqueue()
    return 1, nil, 3, nil
end)
assert(one == 1 and hole == nil and three == 3 and fourth == nil)
assert(first.toolkitQueueOperation == second.toolkitQueueOperation and first.toolkitQueueOperation == nested.toolkitQueueOperation)
assert(operations.bounds(q, nested) == 1)
local start, finish = operations.bounds(q, second); assert(start == 1 and finish == 3)
local count = select('#', operations.run(function() return 1, nil, 3, nil end)); assert(count == 4)
local before, afterError
operations.run(function()
    before = enqueue()
    assert(not pcall(function() operations.run(function() error('nested failure') end) end))
    afterError = enqueue()
end)
assert(before.toolkitQueueOperation == afterError.toolkitQueueOperation)
assert(not pcall(function() operations.run(function() error('outer failure') end) end))
assert(enqueue().toolkitQueueOperation ~= before.toolkitQueueOperation, 'scope must restore after error')
local continuation = {}
operations.runWith(continuation, function()
    assert(enqueue().toolkitQueueOperation == continuation)
    local inner = {}
    operations.runWith(inner, function() assert(enqueue().toolkitQueueOperation == inner) end)
    assert(enqueue().toolkitQueueOperation == continuation)
    assert(not pcall(function() operations.runWith({}, function() error('continuation failure') end) end))
    assert(enqueue().toolkitQueueOperation == continuation)
end)
reset()
local linked, ignored = action(), action(); ignored.ignoreAction = true
local previous = enqueue()
local sameQueue, added = ISTimedActionQueue.addAfter(previous, linked)
assert(sameQueue == q and added == linked and previous.toolkitQueueLinked and linked.toolkitQueueLinked)
assert(previous.toolkitQueueOperation == linked.toolkitQueueOperation)
assert(ISTimedActionQueue.addAfter(previous, ignored) == nil and not ignored.toolkitQueueLinked)
assert(ISTimedActionQueue.addAfter(nil, action()) == nil)
-- Native deferred queueActions insertion inherits its current parent token.
previous._isAddingActions, previous._numAddedActions = true, 0
local expanded = enqueue()
assert(expanded.toolkitQueueOperation == previous.toolkitQueueOperation and q.queue[2] == expanded)
previous._isAddingActions, previous._numAddedActions = nil, nil
-- Every native UI dispatch encloses all synchronous additions.
for _, entry in ipairs({ISContextMenu.onMouseUp, ISContextMenu.onJoypadDown, ISContextMenu.onJoypadDirLeft,
    ISButton.onMouseUp, ISButton.forceClick, ISInventoryPane.onMouseUp, ISInventoryPane.onMouseDoubleClick}) do
    reset()
    local a, b
    entry({}, function() a = enqueue(); b = enqueue() end)
    assert(a.toolkitQueueOperation == b.toolkitQueueOperation)
end
reset()
local function book(container)
    return {class = 'InventoryItem', getContainer = function() return container end}
end
local b1, b2 = book({}), book({})
ISContextMenu.onMouseUp({}, function()
    ISInventoryPaneContextMenu.readItem(b1, 0)
    ISInventoryPaneContextMenu.readItem(b2, 0)
end)
assert(#q.queue == 6 and q.queue[1].Type == 'ISInventoryTransferAction' and q.queue[2].Type == 'ISReadABook')
start, finish = operations.bounds(q, q.queue[2]); assert(start == 1 and finish == 3)
start, finish = operations.bounds(q, q.queue[5]); assert(start == 4 and finish == 6)
assert(q.queue[1].toolkitQueueOperation ~= q.queue[4].toolkitQueueOperation)
local stale = q.queue[2]; q:removeFromQueue(stale); assert(operations.bounds(q, stale) == nil)
-- Repeated noncontiguous tokens cannot be moved as one block.
q.queue[5].toolkitQueueOperation = q.queue[1].toolkitQueueOperation
assert(operations.bounds(q, q.queue[1]) == nil)
reset()
local source, destination = {}, {}
local item = {getWeight = function() return 1 end, getFullType = function() return 'Base.Test' end}
local function transfer()
    local a = ISInventoryTransferUtil.newInventoryTransferAction(player, item, source, destination)
    a.queueList, a.maxTime = {}, 10
    setmetatable(a, {__index = ISInventoryTransferAction})
    return a
end
local t1, t2, t3 = transfer(), transfer(), transfer()
operations.run(function() ISTimedActionQueue.add(t1); ISTimedActionQueue.add(t2) end)
ISTimedActionQueue.add(t3)
assert(ISInventoryTransferAction.canMergeAction(t1, t2))
assert(not ISInventoryTransferAction.canMergeAction(t1, t3))
t2.destContainer = {}; assert(not ISInventoryTransferAction.canMergeAction(t1, t2)); t2.destContainer = destination
-- Execute native merge: it may wipe a same-operation transfer, never the next operation.
ISInventoryTransferAction.checkQueueList(t1)
for _ in pairs(t2) do error('merged action was not wiped') end
assert(#q.queue == 2 and q.queue[2] == t3 and t3.item == item)

-- Opted-in continuations are one-shot, preserve token ownership and become opaque until finished.
reset()
local asyncToken = {}
local handle = operations.attachContinuation(asyncToken, player)
assert(operations.isContinuationPending(asyncToken))
count = select('#', operations.runContinuation(handle, function()
    assert(enqueue().toolkitQueueOperation == asyncToken)
    operations.runContinuation(handle, function() error('reentrant callback') end)
    return 1, nil, 3, nil
end))
assert(count == 4 and not operations.isContinuationPending(asyncToken) and #q.queue == 1)
operations.runContinuation(handle, function() error('duplicate callback') end)
local failed = operations.attachContinuation(asyncToken, player)
assert(not pcall(function() operations.runContinuation(failed, function() error('async failure') end) end))
assert(not operations.isContinuationPending(asyncToken))
assert(enqueue().toolkitQueueOperation ~= asyncToken, 'async scope restores after failure')

local canceledToken = {}
handle = operations.attachContinuation(canceledToken, player)
operations.invalidate(canceledToken)
operations.runContinuation(handle, function() error('cancelled callback') end)
assert(not operations.isContinuationPending(canceledToken) and not operations.attachContinuation(canceledToken, player))
local cleaned = false
operations.runWith(canceledToken, function() cleaned = true end)
assert(cleaned, 'native cleanup must not be suppressed by token cancellation')

-- Explicit clear/reset invalidates old callbacks, including additions after a clear inside the callback.
for _, target in ipairs({q, player}) do
    local queued = enqueue()
    handle = operations.attachContinuation({}, player)
    operations.invalidateQueue(target)
    assert(queued.toolkitQueueOperation.toolkitCancelled, 'legacy queued producers inherit explicit invalidation')
    operations.runContinuation(handle, function() error('old queue generation') end)
end
handle = operations.attachContinuation({}, player)
local replacement = ISTimedActionQueue:new(player)
operations.runContinuation(handle, function() error('replaced queue') end)
ISTimedActionQueue.queues[player] = q
handle = operations.attachContinuation({}, player)
operations.runContinuation(handle, function()
    operations.invalidateQueue(q)
    reset()
    assert(enqueue() and #q.queue == 0)
    q:addToQueue(action())
    ISTimedActionQueue.addAfter(action(), action())
    assert(#q.queue == 0, 'a cleared continuation must not repopulate the queue')
end)
for _, state in ipairs({'disabled', 'dead'}) do
    handle = operations.attachContinuation({}, player)
    PZSurvivorToolkit.Settings = {actionQueue = function() return state ~= 'disabled' end}
    player.isDead = function() return state == 'dead' end
    operations.runContinuation(handle, function() error('disabled or dead continuation') end)
    assert(not operations.isContinuationPending(handle.token))
end
PZSurvivorToolkit.Settings, player.isDead = nil, nil
handle = operations.attachContinuation({}, player)
PZSurvivorToolkit.Settings = {actionQueue = function() return false end}
operations.invalidateQueue(q)
PZSurvivorToolkit.Settings.actionQueue = function() return true end
operations.runContinuation(handle, function() error('reactivating the option cannot revive old generation') end)
PZSurvivorToolkit.Settings = nil

-- Common deferred commands retain the native constructor args and its exact one-tick SP yield.
reset()
local target = {object = {}}
local calls = 0
local callback = function(character, snapshot)
    assert(character == player and snapshot == target)
    calls = calls + 1
    enqueue()
end
operations.enqueue(player, callback, target, {fields = {toolkitTest = true}, priority = 'urgent'})
local deferred = q.queue[1]
assert(operations.isCommand(deferred) and deferred.args[1] == target and deferred.toolkitTest
    and deferred.toolkitQueuePriority == 'urgent')
local borrowed = setmetatable({toolkitQueueCommand = deferred.toolkitQueueCommand, Type = deferred.Type}, ISQueueActionsAction)
assert(not operations.isCommand(borrowed), 'another action cannot borrow a trusted command record')
assert(deferred:waitToStart() == true and deferred:waitToStart() == false)
deferred.forceComplete = function() end
assert(not operations.isCommand(deferred), 'modified native completion cannot borrow command ownership')
deferred.forceComplete = ISQueueActionsAction.forceComplete
assert(operations.isCommand(deferred))
deferred.forceComplete = function() end
deferred:start()
assert(calls == 1 and q.queue[2].toolkitQueueOperation == deferred.toolkitQueueOperation)
for _, method in ipairs({'waitToStart', 'perform', 'complete', 'update', 'isValid', 'stop', 'forceCancel'}) do
    local original = deferred[method]
    deferred[method] = function() end
    assert(not operations.isCommand(deferred), 'foreign lifecycle ' .. method)
    deferred[method] = original
end
deferred.forceComplete = ISQueueActionsAction.forceComplete
deferred.addActionsFunction = function() end
assert(not operations.isCommand(deferred), 'foreign deferred callback')

-- A registered native perform producer can add audited children before its unrelated tail.
operations.registerProducer('fixture', function(a) return a.Type == 'AuditedProducer' end,
    function(parent, child) return child.Type == 'AuditedChild' end)
assert(not pcall(function() operations.registerProducer('fixture', function() end, function() end) end))
local nativeCompleted = q.onCompleted
q.onCompleted = function(queue, a)
    if not operations.deferCompletion(queue, a) then return nativeCompleted(queue, a) end
end
reset()
local producer, child, tail = action('AuditedProducer'), action('AuditedChild'), action('Tail')
ISTimedActionQueue.add(producer); ISTimedActionQueue.add(tail)
operations.perform(producer, function(a)
    q:onCompleted(a)
    assert(q.current == producer, 'native removal waits until producer callback has added children')
    ISTimedActionQueue.add(child)
    assert(q.queue[2] == child and q.queue[3] == tail)
end)
assert(q.current == child and q.queue[2] == tail and child.toolkitQueueOperation == producer.toolkitQueueOperation)
reset()
producer, child, tail = action('AuditedProducer'), action('ForeignChild'), action('Tail')
ISTimedActionQueue.add(producer); ISTimedActionQueue.add(tail)
operations.perform(producer, function(a) q:onCompleted(a); ISTimedActionQueue.add(child) end)
assert(q.current == tail and q.queue[2] == child, 'an unaudited producer child is never moved across unrelated work')
print('Action operation grouping native-contract checks passed.')
