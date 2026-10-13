require "PZSurvivorToolkit/Settings"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISInventoryTransferAction"
require "ISUI/ISContextMenu"
require "ISUI/ISButton"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISInventoryPane"

local Operations = {}
PZSurvivorToolkit.ActionQueueOperations = Operations
local scope
local completionScope
local returnClass = ISInventoryTransferAction
local returnMethods = {}
for _, name in ipairs({"new", "isValid", "isValidStart", "start", "update", "stop", "perform", "complete", "forceStop", "forceCancel"}) do
    returnMethods[name] = returnClass[name]
end

local function nativeReturn(action)
    if getmetatable(action) ~= returnClass or action.Type ~= returnClass.Type or not action.allowMissingItems
        or action.srcContainer ~= action.character:getInventory() or action.destContainer == action.srcContainer
        or action.onStartFunc or action.onCancelFunc or action.onCompleteFunc then return false end
    for name, method in pairs(returnMethods) do if action[name] ~= method then return false end end
    return true
end

local function pack(...)
    return {n = select("#", ...), ...}
end

local function run(token, callback, ...)
    local previous = scope
    scope = token
    local results = pack(pcall(callback, ...))
    scope = previous
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2, results.n)
end

function Operations.run(callback, ...)
    return run(scope or {}, callback, ...)
end

function Operations.runWith(token, callback, ...)
    return run(token or scope or {}, callback, ...)
end

function Operations.deferCompletion(queue, action)
    if completionScope and completionScope.action == action and queue.queue[1] == action then
        completionScope.queue = queue
        return true
    end
end

function Operations.perform(action, callback, ...)
    local Craft = PZSurvivorToolkit.ActionQueueCraft
    local Settings = PZSurvivorToolkit.Settings
    if (Settings and not Settings.actionQueue()) or not Craft or not Craft.supports(action) then
        return callback(action, ...)
    end
    local previous = completionScope
    local pending = {action = action}
    completionScope = pending
    local results = pack(pcall(Operations.runWith, action.toolkitQueueOperation, callback, action, ...))
    completionScope = previous
    if not results[1] then error(results[2], 0) end
    -- Native MP handcraft callbacks add returns after base.perform; finish that same task before advancing.
    if pending.queue and pending.queue.current == action and pending.queue.queue[1] == action then
        pending.queue:onCompleted(action)
    end
    return unpack(results, 2, results.n)
end

local function stamp(action, token)
    if not action.toolkitQueueOperation then
        local queue = ISTimedActionQueue.queues[action.character]
        local current = queue and queue.queue[1]
        if current and current._isAddingActions then
            token = current.toolkitQueueOperation
            action.toolkitBatchIteration = current.toolkitBatchIteration
        end
        action.toolkitQueueOperation = token or scope or {}
    end
    if not action.ignoreAction and PZSurvivorToolkit.ActionQueueBatch then
        PZSurvivorToolkit.ActionQueueBatch.attach(action)
    end
    -- Keep original pickup locations after native transfers merge or leave the queue.
    local operation = action.toolkitQueueOperation
    if type(operation) == "table" and action.Type == "ISInventoryTransferAction"
        and action.item and action.srcContainer and action.destContainer
        and action.destContainer == action.character:getInventory()
        and action.srcContainer ~= action.destContainer
        and action.item:getContainer() == action.srcContainer then
        operation.toolkitPickups = operation.toolkitPickups or {}
        if not operation.toolkitPickups[action.item] then
            operation.toolkitPickups[action.item] = action.srcContainer
        end
    end
end

local add = ISTimedActionQueue.add
ISTimedActionQueue.add = function(action)
    stamp(action)
    local current = completionScope and completionScope.action
    local queue = current and ISTimedActionQueue.queues[current.character]
    if queue and queue.queue[1] == current and action.character == current.character
        and action.toolkitQueueOperation == current.toolkitQueueOperation
        and not current._isAddingActions and nativeReturn(action) then
        local last = 1
        while queue.queue[last + 1] and queue.queue[last + 1].toolkitQueueOperation == current.toolkitQueueOperation do
            last = last + 1
        end
        local result = add(action)
        local index = queue:indexOf(action)
        if index > last then
            table.remove(queue.queue, index)
            table.insert(queue.queue, last + 1, action)
        end
        return result
    end
    return add(action)
end

local addToQueue = ISTimedActionQueue.addToQueue
ISTimedActionQueue.addToQueue = function(queue, action)
    stamp(action)
    return addToQueue(queue, action)
end

local addAfter = ISTimedActionQueue.addAfter
ISTimedActionQueue.addAfter = function(previous, action)
    if not previous then return addAfter(previous, action) end
    stamp(previous)
    action.toolkitQueueOperation = previous.toolkitQueueOperation
    local queue, added = addAfter(previous, action)
    if added then
        stamp(added)
        previous.toolkitQueueLinked, added.toolkitQueueLinked = true, true
    end
    return queue, added
end

function Operations.bounds(queue, action)
    local index = queue:indexOf(action)
    if index == -1 then return end
    local token = action.toolkitQueueOperation
    if not token then return index, index end
    local first, last = index, index
    while first > 1 and queue.queue[first - 1].toolkitQueueOperation == token do first = first - 1 end
    while last < #queue.queue and queue.queue[last + 1].toolkitQueueOperation == token do last = last + 1 end
    for i, queued in ipairs(queue.queue) do
        if (i < first or i > last) and queued.toolkitQueueOperation == token then return end
    end
    return first, last
end

local canMerge = ISInventoryTransferAction.canMergeAction
ISInventoryTransferAction.canMergeAction = function(action, following)
    if following and action.toolkitQueueOperation ~= following.toolkitQueueOperation then return false end
    return canMerge(action, following)
end

local function wrap(class, method, fresh)
    local callback = class and class[method]
    if not callback then return end
    class[method] = function(...)
        if fresh then return run({}, callback, ...) end
        return Operations.run(callback, ...)
    end
end

-- UI callbacks enqueue preparation, the operation and native returns synchronously.
-- shortcut: plain add in async mod callbacks is ungrouped; add an adapter when supporting that callback.
wrap(ISContextMenu, "onMouseUp")
wrap(ISContextMenu, "onJoypadDown")
wrap(ISContextMenu, "onJoypadDirLeft")
wrap(ISContextMenu, "onKeyPress")
wrap(ISButton, "onMouseUp")
wrap(ISButton, "forceClick")
wrap(ISButton, "onJoypadDown")
wrap(ISInventoryPane, "onMouseUp")
wrap(ISInventoryPane, "onMouseDoubleClick")
wrap(ISInventoryPaneContextMenu, "readItem", true)

return Operations
