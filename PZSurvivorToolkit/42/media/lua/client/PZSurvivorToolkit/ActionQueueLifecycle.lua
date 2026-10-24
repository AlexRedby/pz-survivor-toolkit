PZSurvivorToolkit = PZSurvivorToolkit or {}
require "TimedActions/ISQueueActionsAction"
local Toolkit = PZSurvivorToolkit
local Lifecycle = {}
Toolkit.ActionQueueLifecycle = Lifecycle

local pending = setmetatable({}, {__mode = "k"})
local finishStepCancellations = {} -- At most one current capability per queue; explicitly revoked below.
local observers, observerIds = {}, {}
-- Observation at the common native boundary does not grant edit permissions.
-- Failed observers are quarantined: observation must never abort a paid native
-- callback and make it eligible for replay. An incomplete proof earns no effect.
function Lifecycle.registerObserver(id, observer)
    if type(id) ~= "string" or type(observer) ~= "table" or observerIds[id] then return false end
    for key, callback in pairs(observer) do
        if (key ~= "started" and key ~= "begin" and key ~= "finish") or type(callback) ~= "function" then return false end
    end
    local entry = {}
    for key, callback in pairs(observer) do entry[key] = callback end
    observers[#observers + 1], observerIds[id] = entry, true
    return true
end
local function observe(phase, ...)
    local accepted = false
    for _, observer in ipairs(observers) do
        if not observer.failed and observer[phase] then
            local ok, result = pcall(observer[phase], ...)
            if not ok then observer.failed = true
            elseif result == true then accepted = true end
        end
    end
    return accepted
end
function Lifecycle.started(action)
    local queue = action and ISTimedActionQueue.queues[action.character]
    local seal = queue and finishStepCancellations[queue]
    if seal and (seal.action ~= action or seal.native ~= action.action) then finishStepCancellations[queue] = nil end
    if Toolkit.ActionQueueSettlement then Toolkit.ActionQueueSettlement.started(action) end
    observe("started", action)
end
local function enabled(action)
    local media=Toolkit.ActionQueueMedia
    return Toolkit.Settings and Toolkit.Settings.actionQueue() or media and media.tracks(action)
end

local function owned(queue, action)
    return queue and action and queue.character == action.character
        and ISTimedActionQueue.queues[action.character] == queue
        and queue.current == action and queue.queue[1] == action
end

-- Seal only the current preparation accepted by the actual cancellation decision,
-- before its token is invalidated. Public group/cancel flags alone grant nothing.
function Lifecycle.acceptFinishStepCancellation(queue, action, request, decision)
    local policy = Toolkit.ActionQueuePolicy
    if not isClient() or not Toolkit.Settings.actionQueue() or not owned(queue, action) or not action.action
        or type(request) ~= "table" or request.action ~= action or request.token ~= action.toolkitQueueOperation
        or type(request.token) ~= "table" or request.token.toolkitCancelled
        or not decision or decision.allowed ~= true or decision.first ~= 1
        or not policy or not policy.editUnchanged(queue, decision.snapshot)
        or policy.stoppable(action) or not policy.preparationCanFinish(action) then return false end
    local contract, adapter, behavior = policy.inspect(action)
    if not contract or contract.interrupt ~= "finish-step" or not behavior then return false end
    finishStepCancellations[queue] = {action = action, native = action.action, request = request, token = request.token,
        generation = queue.toolkitOperationGeneration or 0, policy = policy, inspect = policy.inspect,
        preparationCanFinish = policy.preparationCanFinish, stoppable = policy.stoppable, adapter = adapter, behavior = behavior}
    return true
end
local function finishingCanceledStep(queue, action, nativeAction)
    local seal = finishStepCancellations[queue]
    if not seal then return false end
    local policy = Toolkit.ActionQueuePolicy
    local valid = owned(queue, action) and seal.action == action and seal.native == nativeAction
        and action.action == nativeAction and queue.toolkitGroupCancel == seal.request
        and seal.request.action == action and seal.request.token == seal.token
        and action.toolkitQueueOperation == seal.token and seal.token.toolkitCancelled == true
        and (queue.toolkitOperationGeneration or 0) == seal.generation
        and policy == seal.policy and policy.inspect == seal.inspect
        and policy.preparationCanFinish == seal.preparationCanFinish and policy.stoppable == seal.stoppable
    if valid then
        local contract, adapter, behavior = policy.inspect(action)
        valid = contract and contract.interrupt == "finish-step" and adapter == seal.adapter and behavior == seal.behavior
            and not policy.stoppable(action) and policy.preparationCanFinish(action)
    end
    if not valid then finishStepCancellations[queue] = nil end
    return valid == true
end

-- A server-completed transaction can remove its target before native valid()
-- reaches update()/Done. Java verifies its exact standard transaction and stop
-- flags; this gate verifies current queue ownership and the sealed server receipt.
-- It never executes callbacks, effects or queue advancement.
function Lifecycle.allowNativeCompletion(action, nativeAction)
    local character=action and action.character
    local queue=character and ISTimedActionQueue.queues[character]
    if not isClient()then
        if queue then finishStepCancellations[queue] = nil end
        return false
    end
    local editing = Toolkit.Settings.actionQueue()
    if not editing and queue then finishStepCancellations[queue] = nil end
    local finishing = editing and queue and finishingCanceledStep(queue, action, nativeAction)
    if not owned(queue,action)or action.action~=nativeAction or character:isDead()or character:isAsleep()
        or not character:isLocalPlayer()or getSpecificPlayer(character:getPlayerNum())~=character
        or queue.toolkitCancel or queue.toolkitStopIntent or queue.toolkitOutcomeWait
        or (queue.toolkitGroupCancel and not finishing) or queue.toolkitResume
        or (editing and queue.toolkitOperationsInvalid)
        or (editing and action.toolkitQueueOperation and action.toolkitQueueOperation.toolkitCancelled and not finishing)
        or character:pressedCancelAction()
        or (action.stopOnWalk and (character:isPlayerMoving()or character:pressedMovement(false)))
        or (action.stopOnRun and (character:isRunning()or character:isSprinting()))
        or (action.stopOnAim and character:isAiming())then
        if queue then finishStepCancellations[queue] = nil end
        return false
    end
    local acknowledgements=Toolkit.ActionQueueAcknowledgements
    local receipt=acknowledgements and acknowledgements.capture(action)
    if not editing and not (receipt and acknowledgements.allowsDisabledNativeCompletion
        and acknowledgements.allowsDisabledNativeCompletion(action,receipt)) then return false end
    return receipt~=nil and acknowledgements.state(action,receipt)=='completed'
end

-- Policy grants permission before reaching this shared native stop boundary.
function Lifecycle.requestStop(queue, action, reason, scope, buildReceipt)
    if not owned(queue, action) or not action.action then return false end
    finishStepCancellations[queue] = nil
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
    local observing = observe("begin", action, phase)
    local intent=Toolkit.ActionQueueTidyIntent
    if intent and intent.begin(action,phase) then observing = true end
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
    observe("finish", action, phase, succeeded)
    local intent=Toolkit.ActionQueueTidyIntent
    if intent then intent.finish(action,phase,succeeded) end
    local queue = action and ISTimedActionQueue.queues[action.character]
    local seal = queue and finishStepCancellations[queue]
    if seal and seal.action == action then finishStepCancellations[queue] = nil end
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

-- Recovery must not infer unfinished work from a row awaiting native removal.
function Lifecycle.completionEntered(queue, action)
    local state = pending[queue]
    return state ~= nil and state.action == action
end

function Lifecycle.reset(queue)
    pending[queue], finishStepCancellations[queue] = nil, nil
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
    local settlement = Toolkit.ActionQueueSettlement
    local cancellation = settlement and settlement.completionState(queue, action)
    if cancellation == "waiting" then return "waiting", action end
    pending[queue] = nil
    if cancellation == "failed" or mediaState == "failed" then return "failed", action end
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
