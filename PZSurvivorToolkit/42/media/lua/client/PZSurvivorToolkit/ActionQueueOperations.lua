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

local function stamp(action, token)
    if not action.toolkitQueueOperation then
        local queue = ISTimedActionQueue.queues[action.character]
        local current = queue and queue.queue[1]
        if current and current._isAddingActions then
            token = current.toolkitQueueOperation
        end
        action.toolkitQueueOperation = token or scope or {}
    end
end

local add = ISTimedActionQueue.add
ISTimedActionQueue.add = function(action)
    stamp(action)
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
    if added then previous.toolkitQueueLinked, added.toolkitQueueLinked = true, true end
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
