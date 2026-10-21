PZSurvivorToolkit = PZSurvivorToolkit or {}
require "TimedActions/ISQueueActionsAction"
local Toolkit = PZSurvivorToolkit
local Lifecycle = {}
Toolkit.ActionQueueLifecycle = Lifecycle

local pending = setmetatable({}, {__mode = "k"})
local function enabled(action)
    local media=Toolkit.ActionQueueMedia
    return Toolkit.Settings and Toolkit.Settings.actionQueue() or media and media.tracks(action)
end

local function owned(queue, action)
    return queue and action and queue.character == action.character
        and ISTimedActionQueue.queues[action.character] == queue
        and queue.current == action and queue.queue[1] == action
end

-- Policy grants permission before reaching this shared native stop boundary.
function Lifecycle.requestStop(queue, action, reason, scope, buildReceipt)
    if not owned(queue, action) or not action.action then return false end
    local acknowledgements = Toolkit.ActionQueueAcknowledgements
    local receipt = acknowledgements and acknowledgements.capture(action)
    queue.toolkitCancel = action
    queue.toolkitStopIntent = {reason = reason, scope = scope}
    if receipt or buildReceipt then
        queue.toolkitOutcomeWait = {acknowledgement = receipt or buildReceipt, generic = receipt ~= nil,
            deadline = getTimestampMs() + 30000}
    end
    action:forceStop()
    return true
end

-- Called by the supported native LuaTimedActionNew boundary, never by individual action adapters.
function Lifecycle.begin(action, phase)
    if phase ~= "perform" and phase ~= "complete" then return false end
    local intent=Toolkit.ActionQueueTidyIntent
    local observing=intent and intent.begin(action,phase)
    if not enabled(action) then return observing==true end
    local queue = action and ISTimedActionQueue.queues[action.character]
    if not owned(queue, action) or not action.action then return observing==true end
    local state = pending[queue]
    if state and state.action ~= action then pending[queue] = nil; state = nil end
    if not state then
        if phase ~= "perform" then return observing==true end
        state = {action = action, native = action.action, depth = 0, needsComplete = not isClient()}
        pending[queue] = state
    end
    state.depth = state.depth + 1
    return true
end

function Lifecycle.finish(action, phase, succeeded)
    local intent=Toolkit.ActionQueueTidyIntent
    if intent then intent.finish(action,phase,succeeded) end
    local queue = action and ISTimedActionQueue.queues[action.character]
    local state = queue and pending[queue]
    if not state or state.action ~= action then return end
    state.depth = math.max(0, state.depth - 1)
    state[phase] = true
    if not succeeded then state.failed = true end
end

function Lifecycle.deferCompletion(queue, action)
    local state = pending[queue]
    if state and state.action == action and owned(queue, action) then
        state.requested = true
        return true
    end
    return false
end

function Lifecycle.reset(queue)
    pending[queue] = nil
    if Toolkit.ActionQueueMedia then Toolkit.ActionQueueMedia.reset(queue) end
end

function Lifecycle.current(character)
    local queue = ISTimedActionQueue.queues[character]
    local state = queue and pending[queue]
    if state and state.depth > 0 and owned(queue, state.action) then return state.action end
end

-- A native callback has finished, but its owned Lua continuation has not advanced.
-- UI cancellation may still revoke this work after Java removes its action.
function Lifecycle.deferredAction(queue)
    local state = queue and pending[queue]
    if state and owned(queue, state.action) and enabled(state.action)
        and not state.failed and state.requested and state.depth == 0 and state.perform
        and (not state.needsComplete or state.complete)
        and not queue.character:getCharacterActions():contains(state.native) then return state.action end
end

-- Existing queue tick calls this before native tick; native removal is the final completion gate.
function Lifecycle.flush(queue)
    local state = pending[queue]
    if not state then return end
    local action = state.action
    if not owned(queue, action) or not enabled(action) then
        pending[queue] = nil
        return
    end
    if state.depth > 0 or not state.perform or state.needsComplete and not state.complete
        or queue.character:getCharacterActions():contains(state.native) then return "waiting", action end
    if state.failed or not state.requested then
        pending[queue] = nil
        return "failed", action
    end
    local reading = Toolkit.ActionQueueReading
    local media=Toolkit.ActionQueueMedia
    local mediaState
    if media and media.tracks(action) then mediaState=media.continuationState(action)
    else mediaState=reading and reading.mediaCompletionState and reading.mediaCompletionState(queue, action) end
    if mediaState == "waiting" then return "waiting", action end
    pending[queue] = nil
    if mediaState == "failed" then return "failed", action end
    if reading and reading.completedPickup then reading.completedPickup(queue, action) end
    queue:onCompleted(action)
    return "completed", action
end

-- An empty successful expansion is a no-op; errors still reach native update()/stop().
local commandStart = ISQueueActionsAction.start
local nativeCommand = false
if getFilenameOfClosure then
    local ok, filename = pcall(getFilenameOfClosure, commandStart)
    nativeCommand = ok and type(filename) == "string" and filename:match("([^/\\]+)$") == "ISQueueActionsAction.lua"
end
local operations = Toolkit.ActionQueueOperations
ISQueueActionsAction.start = function(action)
    if not nativeCommand or not Toolkit.Settings.actionQueue() then return commandStart(action) end
    action:beginAddingActions()
    if operations then
        operations.runWith(action.toolkitQueueOperation, action.addActionsFunction, action.character, unpack(action.args))
    else
        action.addActionsFunction(action.character, unpack(action.args))
    end
    action:endAddingActions()
    action:forceComplete()
end
if operations then operations.adoptCommandLifecycle("start", commandStart, ISQueueActionsAction.start) end

return Lifecycle
