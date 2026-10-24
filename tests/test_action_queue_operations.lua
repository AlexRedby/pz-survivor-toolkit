-- Native queue and transfer contracts, with synchronous UI dispatch doubles.
if not NativeActionRoot then
    print('Action operation native-contract checks skipped (pass --native-action-root media/lua).')
    return
end
require = function(name)
    if name == 'PZSurvivorToolkit/SourceProof' then
        return dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/' .. name .. '.lua')
    end
    if name == 'PZSurvivorToolkit/InventoryClasses' then
        return dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/' .. name .. '.lua')
    end
end
local queueEnabled = true
PZSurvivorToolkit = {Settings = {actionQueue = function() return queueEnabled end}}
local function derive(self, name)
    local t = {Type = name, derive = derive}
    t.__index = t
    return setmetatable(t, {__index = self})
end
ISBaseObject = {derive = derive}
Events = {OnTick = {Add = function() end}, OnGameStart = {Add = function() end}}
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

-- Disabling the feature restores native coalescing without changing action tokens.
-- Exercise the native removal/wipe path, then re-enable around the same executor.
for _, barrier in ipairs({'none', 'source', 'destination', 'callback', 'allowMissing', 'type'}) do
    reset()
    local a, b, tail = transfer(), transfer(), action('IndependentTail')
    a.item = {getWeight=function() return .01 end, getFullType=function() return 'Base.Nails' end}
    b.item = {getWeight=function() return .01 end, getFullType=function() return 'Base.Nails' end}
    a.queueList = {{items={a.item},time=10,type='Base.Nails'}}
    ISTimedActionQueue.add(a); ISTimedActionQueue.add(b); ISTimedActionQueue.add(tail)
    local aToken,bToken = a.toolkitQueueOperation,b.toolkitQueueOperation
    assert(aToken~=bToken)
    if barrier=='source' then b.srcContainer={}
    elseif barrier=='destination' then b.destContainer={}
    elseif barrier=='callback' then b.onCompleteFunc=function() end
    elseif barrier=='allowMissing' then b.allowMissingItems=true
    elseif barrier=='type' then b.Type='OtherAction' end
    queueEnabled=false
    assert(a.toolkitQueueOperation==aToken and b.toolkitQueueOperation==bToken)
    ISInventoryTransferAction.checkQueueList(a)
    if barrier=='none' then
        assert(#q.queue==2 and q.queue[2]==tail and #a.queueList==1 and #a.queueList[1].items==2,
            'off-mode did not preserve native lightweight grouping or independent tail')
        for _ in pairs(b) do error('off-mode native merge did not wipe accepted child') end
        queueEnabled=true
        local c=transfer(); ISTimedActionQueue.add(c)
        assert(not a:canMergeAction(c),'re-enabling allowed another operation into the existing executor')
        assert(#a.queueList[1].items==2 and a.toolkitQueueOperation==aToken,
            're-enabling must not rewrite already merged native groups or executor token')
    else
        assert(#q.queue==3 and q.queue[2]==b and b.toolkitQueueOperation==bToken,
            'off-mode bypassed upstream '..barrier..' barrier')
    end
    queueEnabled=true
end

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
queueEnabled=false
operations.runContinuation(handle, function() error('cancelled callback') end)
assert(not operations.isContinuationPending(canceledToken) and not operations.attachContinuation(canceledToken, player))
local cleaned = false
operations.runWith(canceledToken, function() cleaned = true end)
assert(cleaned, 'native cleanup must not be suppressed by token cancellation')
queueEnabled=true
operations.runContinuation(handle, function() error('toggle revived cancelled callback') end)

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
-- A verified retry keeps borrowed tools until it finishes; unknown return callbacks keep native order.
operations.registerProducer('retry', function(a) return a.Type == 'RetryProducer' end,
    function(parent, child) return child.Type == 'RetryChild', 'before-returns' end)
local function retryBeforeReturn(changed, expectedBefore)
    reset()
    local parent, retry, unrelated = action('RetryProducer'), action('RetryChild'), action('Tail')
    ISTimedActionQueue.add(parent)
    local restore = setmetatable(action('ISInventoryTransferAction'), ISInventoryTransferAction)
    restore.isValidStart = nil
    restore.allowMissingItems, restore.srcContainer, restore.destContainer = true, player.inventory, {}
    if changed then restore.onCompleteFunc = function() end end
    operations.runWith(parent.toolkitQueueOperation, ISTimedActionQueue.add, restore)
    ISTimedActionQueue.add(unrelated)
    operations.perform(parent, function(a)
        ISTimedActionQueue.add(retry)
        assert(q.queue[2] == (expectedBefore and retry or restore))
        assert(q.queue[3] == (expectedBefore and restore or retry) and q.queue[4] == unrelated)
        q:onCompleted(a)
    end)
    assert(q.current == (expectedBefore and retry or restore))
end
retryBeforeReturn(false, true)
retryBeforeReturn(true, false)
local original, replacement, helpersSafe = {}, {}, true
for _, name in ipairs({'isValid', 'start', 'perform', 'stop'}) do
    original[name] = ISInventoryTransferAction[name]
    local callback = original[name]
    replacement[name] = function(...) return callback(...) end
end
local function unchangedHelpers() return helpersSafe end
assert(not operations.adoptReturnMethods(original, replacement, unchangedHelpers))
for name, method in pairs(replacement) do ISInventoryTransferAction[name] = method end
assert(not operations.adoptReturnMethods({}, replacement, unchangedHelpers))
assert(operations.adoptReturnMethods(original, replacement, unchangedHelpers))
retryBeforeReturn(false, true)
helpersSafe = false; retryBeforeReturn(false, false)
helpersSafe = true; retryBeforeReturn(false, true)
-- Migrated producers use the native boundary, while child contracts still register retries.
local client=false
isClient=function()return client end
PZSurvivorToolkit.Settings={actionQueue=function()return true end}
local previousFilename = getFilenameOfClosure
getFilenameOfClosure = function() return 'ISQueueActionsAction.lua' end
local Lifecycle=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua'))()
getFilenameOfClosure = previousFilename
local legacyCompleted=q.onCompleted
q.onCompleted=function(queue,a)
    if Lifecycle.deferCompletion(queue,a) then return end
    return legacyCompleted(queue,a)
end
local present={}
player.getCharacterActions=function()return {contains=function(_,a)return present[a]==true end}end
local childChecks=0
operations.registerProducer('shared-retry',function(a)return a.Type=='SharedRetryProducer'end,function(parent,child)
    childChecks=childChecks+1
    if child.Type~='SharedRetryChild' then return false end
    child.registeredParent=parent
    return true,'before-returns'
end,true)
assert(not pcall(operations.registerProducer,'invalid-shared',function()end,function()end,'true'))
for _,mp in ipairs({false,true})do
    client=mp;reset()
    local parent,retry,unrelated,unknown=action('SharedRetryProducer'),action('SharedRetryChild'),action('Tail'),action('ForeignChild')
    ISTimedActionQueue.add(parent)
    present[parent.action]=true
    local restore=setmetatable(action('ISInventoryTransferAction'),ISInventoryTransferAction)
    restore.isValidStart=nil
    restore.allowMissingItems,restore.srcContainer,restore.destContainer=true,player.inventory,{}
    operations.runWith(parent.toolkitQueueOperation,ISTimedActionQueue.add,restore)
    ISTimedActionQueue.add(unrelated)
    assert(Lifecycle.begin(parent,'perform'))
    local count=select('#',operations.perform(parent,function(a)
        assert(not operations.deferCompletion(q,a),'migrated producer acquired the legacy completion interceptor')
        q:onCompleted(a)
        assert(q.current==parent,'native producer lost its parent during perform')
        ISTimedActionQueue.add(retry)
        ISTimedActionQueue.add(unknown)
        assert(retry.registeredParent==parent and unknown.registeredParent==nil,'producer child contract was bypassed')
        assert(retry.toolkitQueueOperation==parent.toolkitQueueOperation)
        assert(q.queue[2]==retry and q.queue[3]==restore and q.queue[4]==unrelated and q.queue[5]==unknown,
            'audited retry must precede returns; unknown child must preserve native order')
        return 1,nil,3
    end))
    assert(count==3)
    Lifecycle.finish(parent,'perform',true)
    if not mp then
        assert(Lifecycle.begin(parent,'complete')and q.current==parent,'SP complete lost its native parent')
        Lifecycle.finish(parent,'complete',true)
    end
    assert(Lifecycle.flush(q)=='waiting','producer advanced before native removal')
    present[parent.action]=nil
    assert(Lifecycle.flush(q)=='completed'and q.current==retry)
    assert(Lifecycle.flush(q)==nil,'producer completion replayed')
end
assert(childChecks==4,'each native child must pass the opted producer contract once')
-- Unsupported/absent native hooks retain the same family completion fallback.
reset()
local parent,retry,unrelated=action('SharedRetryProducer'),action('SharedRetryChild'),action('Tail')
ISTimedActionQueue.add(parent);ISTimedActionQueue.add(unrelated)
operations.perform(parent,function(a)
    q:onCompleted(a)
    assert(q.current==parent,'unsupported engine lost producer completion protection')
    ISTimedActionQueue.add(retry)
end)
assert(q.current==retry and q.queue[2]==unrelated and retry.registeredParent==parent)
-- Other registered families are not migrated just because a common boundary exists.
reset();parent=action('AuditedProducer');ISTimedActionQueue.add(parent)
assert(Lifecycle.begin(parent,'perform'))
operations.perform(parent,function(a)
    assert(operations.deferCompletion(q,a),'unmigrated producer lost its family fallback')
end)
Lifecycle.finish(parent,'perform',true);Lifecycle.reset(q)

-- Presentation enqueue must stay linear for separate shelf reads and large native
-- operations. These counts include the real native add -> addToQueue delegation.
local previousGetText = getText
getText = function(key) return key end
local definitions = assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueDefinitions.lua'))()
local describe, bounds = definitions.describe, operations.bounds
local descriptions, searches = 0, 0
definitions.describe = function(...) descriptions = descriptions + 1; return describe(...) end
operations.bounds = function(...) searches = searches + 1; return bounds(...) end
for _, n in ipairs({10, 30, 60, 120}) do
    for _, batch in ipairs({false, true}) do
        reset(); descriptions, searches = 0, 0
        local function readSelected()
            for i = 1, n do ISInventoryPaneContextMenu.readItem(book({}), 0) end
        end
        if batch then ISContextMenu.onMouseUp({}, readSelected) else readSelected() end
        assert(#q.queue == 3 * n and descriptions == 3 * n and searches == 0,
            'ordinary shelf reading rebuilt prior titles or searched the queue')
        for i = 1, #q.queue, 3 do
            assert(q.queue[i].toolkitQueueOperation.presentation.title == 'ContextMenu_Read')
            assert(q.queue[i].toolkitQueueOperation ~= (q.queue[i + 3] or {}).toolkitQueueOperation,
                'reading optimization merged independent book operations')
        end
    end
    reset(); descriptions, searches = 0, 0
    operations.run(function() for i = 1, n do ISTimedActionQueue.add(action('ISReadABook')) end end)
    assert(descriptions == n and searches == 0, 'one large operation must also contribute each title once')
    reset(); descriptions, searches = 0, 0
    operations.run(function()
        for i = 1, n do
            ISTimedActionQueue.add(action('ISInventoryTransferAction'))
            ISTimedActionQueue.add(action('ISWalkToTimedAction'))
        end
    end)
    assert(descriptions == 2 * n and searches == 0,
        'fixed transfer headings must retain the incremental summary for preparation additions')
end

-- Native deferred expansion inserts before unrelated work rather than appending.
-- Only its first child needs a range rebuild; later children contribute once.
reset()
local command = operations.command(player, function()
    for i = 1, 60 do ISTimedActionQueue.add(action('ISReadABook')) end
end, {})
command.forceComplete = function() end
local following = action('UnrelatedPresentation')
ISTimedActionQueue.add(command); ISTimedActionQueue.add(following)
descriptions, searches = 0, 0
command:start()
assert(q.queue[62] == following and searches == 1 and descriptions == 61,
    'deferred expansion rebuilt the growing operation on every insertion')
assert(command.toolkitQueueOperation.presentation.title == 'ContextMenu_Read')
reset()
command = ISQueueActionsAction:new(player, function()
    for i = 1, 60 do ISTimedActionQueue.add(action('ISReadABook')) end
end)
command.forceComplete = function() end
ISTimedActionQueue.add(command); ISTimedActionQueue.add(following)
descriptions, searches = 0, 0
command:start()
assert(q.queue[62] == following and searches == 1 and descriptions == 61,
    'native deferred start lost its shared presentation scope')

-- Higher priority work replaces preparation/transfer titles; returns cannot
-- replace it, and distinct primary signatures remain mixed after more additions.
reset()
local presentationToken = {}
operations.runWith(presentationToken, function()
    ISTimedActionQueue.add(action('ISWalkToTimedAction'))
    ISTimedActionQueue.add(action('ISInventoryTransferAction'))
    ISTimedActionQueue.add(action('ISReadABook'))
    local returning = action('ISInventoryTransferAction'); returning.allowMissingItems = true
    ISTimedActionQueue.add(returning)
end)
assert(presentationToken.presentation.title == 'ContextMenu_Read')
operations.runWith(presentationToken, function()
    ISTimedActionQueue.add(action('OtherPresentation'))
    ISTimedActionQueue.add(action('ISReadABook'))
end)
assert(presentationToken.presentation.title == 'UI_PZSurvivorToolkit_queue_mixed')
q:removeFromQueue(q.queue[5])
operations.runWith(presentationToken, function() ISTimedActionQueue.add(action('ISReadABook')) end)
assert(presentationToken.presentation.title == 'ContextMenu_Read',
    'a later command reused the removed mixed-title member')
local inserted = action('InsertedPresentation')
ISTimedActionQueue.addAfter(q.queue[2], inserted)
assert(presentationToken.presentation.title == 'UI_PZSurvivorToolkit_queue_mixed',
    'addAfter failed to refresh the actual operation range')

-- Deferred continuations retain ownership but rebuild presentation membership
-- after intervening removal/reordering, rather than retaining a dispatch cache.
handle = operations.attachContinuation(presentationToken, player)
q:removeFromQueue(inserted)
local firstRead = table.remove(q.queue, 3); table.insert(q.queue, 2, firstRead)
operations.runContinuation(handle, function() ISTimedActionQueue.add(action('ISReadABook')) end)
assert(presentationToken.presentation.title == 'ContextMenu_Read')
reset()
local completedPrimaryToken, completedRead = {}, action('ISReadABook')
operations.runWith(completedPrimaryToken, function()
    ISTimedActionQueue.add(completedRead)
    ISTimedActionQueue.add(action('ISInventoryTransferAction'))
end)
q:removeFromQueue(completedRead)
operations.runWith(completedPrimaryToken, function() ISTimedActionQueue.add(action('ISInventoryTransferAction')) end)
assert(completedPrimaryToken.presentation.title == 'ContextMenu_Read',
    'completed primary title must survive its remaining lower-rank transfers')
definitions.describe, operations.bounds, getText = describe, bounds, previousGetText

-- Native volume-bar direct and deferred callbacks must group their approach
-- and radio control when no ISButton callback is still on the stack.
do
    getText=function(key)return key end
    reset()
    ISPanel,ISPanelJoypad=ISBaseObject,ISBaseObject
    load('client/RadioCom/RadioWindowModules/RWMPanel.lua')
    UIFont={Small='Small'};getTextManager=function()return {getFontHeight=function()return 12 end}end
    load('client/RadioCom/RadioWindowModules/RWMVolume.lua')
    load('client/RadioCom/ISUIRadio/ISVolumeBar.lua')
    load('shared/RadioCom/ISRadioAction.lua')
    getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
    getGameFilesInput=function(path)
        local file=assert(io.open(NativeActionRoot..'/'..path:gsub('^media/lua/','')))
        return {readLine=function()local line=file:read('*l');return line and line:gsub('\r$','')end,
            close=function()file:close()end}
    end
    local nativeVolume=RWMVolume.onVolumeChange
    assert(operations.installVolumeProducer())
    local scopedVolume=RWMVolume.onVolumeChange
    assert(scopedVolume~=nativeVolume and operations.installVolumeProducer() and RWMVolume.onVolumeChange==scopedVolume,
        'repeated installation cannot stack native producer wrappers')
    local data={canPlayerRemoteInteract=function()return false end}
    local square={};local device={getSquare=function()return square end,getDeviceData=function()return data end}
    local panel=setmetatable({player=player,device=device,deviceData=data,deviceType='IsoObject',
        volumeBar={getVolumeSteps=function()return 10 end}},RWMVolume)
    luautils={walkAdj=function(p,s)
        assert(p==player and s==square)
        ISTimedActionQueue.add(action('ISWalkToTimedAction'));return true
    end}
    local lastToken
    local function check(commit)
        reset();enqueue();commit()
        local walk,setter=q.queue[2],q.queue[3]
        assert(#q.queue==3 and walk.Type=='ISWalkToTimedAction' and setter.Type=='ISRadioAction'and setter.mode=='SetVolume')
        assert(walk.toolkitQueueOperation==setter.toolkitQueueOperation and walk.toolkitQueueOperation~=lastToken,
            'each native commit groups only its own walk and setter')
        lastToken=walk.toolkitQueueOperation
    end
    check(function()panel:onVolumeChange(4)end)
    local slider=setmetatable({volumeSteps=10,dragInside=true,getWidth=function()return 100 end,
        getIsVisible=function()return true end,onVolumeChange=RWMVolume.onVolumeChange,
        onVolumeChangeTarget=panel},ISVolumeBar)
    check(function()slider:onMouseUp(35,0)end)
    ISPanel.update=function()end
    UIManager={getMillisSinceLastUpdate=function()return 600 end}
    local bar=setmetatable({joyMeter=500,hoverVolume=6,onVolumeChange=RWMVolume.onVolumeChange,
        onVolumeChangeTarget=panel},ISVolumeBar)
    check(function()bar:update()end)
    local walked=panel.doWalkTo
    panel.doWalkTo=function()ISTimedActionQueue.add(action('ForeignWalk'));return true end
    reset();enqueue();panel:onVolumeChange(5)
    assert(q.queue[2].toolkitQueueOperation~=q.queue[3].toolkitQueueOperation,
        'changed upstream walk helper cannot acquire a native producer scope')
    panel.doWalkTo=walked
    RWMVolume.onVolumeChange=function()error('foreign replacement')end
    assert(not operations.installVolumeProducer(),'foreign replacement cannot be adopted or wrapped again')
end

-- An unexpected producer error must stay visible without leaving subsequent
-- independent enqueues inside the failed command's insertion boundary.
reset()
local broken = operations.command(player, function() error('producer failure sentinel') end, {})
local untouched = action()
q.queue, q.current = {broken, untouched}, broken
local succeeded, failure = pcall(broken.start, broken)
assert(not succeeded and tostring(failure):find('producer failure sentinel', 1, true))
assert(not q:isCurrentActionAddingOtherActions(), 'failed expansion retained the native insertion boundary')
local following = enqueue()
assert(q.queue[2] == untouched and q.queue[3] == following,
    'independent enqueue was inserted into the failed producer instead of after the existing tail')
assert(following.toolkitQueueOperation ~= broken.toolkitQueueOperation)
reset()

print('Action operation grouping: native contracts, volume slider/deferred commits and foreign helper guards passed.')
