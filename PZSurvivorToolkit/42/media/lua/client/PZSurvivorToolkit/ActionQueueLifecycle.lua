PZSurvivorToolkit = PZSurvivorToolkit or {}
require "TimedActions/ISQueueActionsAction"
require "PZSurvivorToolkit/ActionQueueOperations"
local Toolkit = PZSurvivorToolkit
local Lifecycle = {}
Toolkit.ActionQueueLifecycle = Lifecycle

local pending = setmetatable({}, {__mode = "k"})
local phaseEntries = {} -- Live native callback frames only; removed by their matching finish.
local finishStepCancellations = {} -- At most one current capability per queue; explicitly revoked below.
local observers, observerIds = {}, {}
local guardedStops, stopScope = {}, nil
local function pack(...) return {n = select("#", ...), ...} end
-- Observation at the common native boundary does not grant edit permissions.
-- Failed observers are quarantined: observation must never abort a paid native
-- callback and make it eligible for replay. An incomplete proof earns no effect.
function Lifecycle.registerObserver(id, observer)
    if type(id) ~= "string" or type(observer) ~= "table" or observerIds[id] then return false end
    for key, callback in pairs(observer) do
        if (key ~= "started" and key ~= "begin" and key ~= "finish" and key ~= "settled") or type(callback) ~= "function" then return false end
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
local function draining(action)
    local settlement = Toolkit.ActionQueueSettlement
    return settlement and settlement.drainingAction(action)
end
local function generationMatches(queue, action, generation)
    local settlement = Toolkit.ActionQueueSettlement
    return (queue.toolkitOperationGeneration or 0) == generation
        or settlement and settlement.cancellationGeneration(action, generation)
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
        and generationMatches(queue, action, seal.generation)
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
local function nativeCompletionState(action, nativeAction, waiting)
    local character=action and action.character
    local queue=character and ISTimedActionQueue.queues[character]
    if not isClient()then
        if queue then finishStepCancellations[queue] = nil end
        return false
    end
    local editing = Toolkit.Settings.actionQueue()
    local admitted = draining(action)
    if not editing and not admitted and queue then finishStepCancellations[queue] = nil end
    local finishing = (editing or admitted) and queue and finishingCanceledStep(queue, action, nativeAction)
    if not owned(queue,action)or action.action~=nativeAction or character:isDead()or character:isAsleep()
        or not character:isLocalPlayer()or getSpecificPlayer(character:getPlayerNum())~=character
        or queue.toolkitCancel or queue.toolkitStopIntent or queue.toolkitOutcomeWait
        or (queue.toolkitGroupCancel and not finishing) or queue.toolkitResume
        or (editing and queue.toolkitOperationsInvalid and not admitted)
        or (editing and action.toolkitQueueOperation and action.toolkitQueueOperation.toolkitCancelled and not admitted and not finishing)
        or character:pressedCancelAction()
        or (action.stopOnWalk and (character:isPlayerMoving()or character:pressedMovement(false)))
        or (action.stopOnRun and (character:isRunning()or character:isSprinting()))
        or (action.stopOnAim and character:isAiming())then
        if queue then finishStepCancellations[queue] = nil end
        return false
    end
    local acknowledgements=Toolkit.ActionQueueAcknowledgements
    local receipt=acknowledgements and acknowledgements.capture(action)
    local disabled = acknowledgements and (waiting and acknowledgements.allowsDisabledNativeCompletionWait
        or acknowledgements.allowsDisabledNativeCompletion)
    if not editing and not admitted and not (receipt and disabled and disabled(action,receipt)) then return end
    return receipt and acknowledgements.state(action,receipt)
end
function Lifecycle.allowNativeCompletion(action, nativeAction)
    return nativeCompletionState(action,nativeAction,false)=='completed'
end
-- Waiting is not completion. Java may hold an exact accepted standard transaction
-- until Done and its sealed receipt, with an absolute deadline and no stale update.
function Lifecycle.allowNativeCompletionWait(action, nativeAction)
    local state=nativeCompletionState(action,nativeAction,true)
    return state=='started'or state=='completed'
end

-- A terminal stop keeps native cleanup/networking and suppresses only Base.stop
-- reset. Its private proof grants no permission to edit the queue.
local function releaseStop(state)
    if state.released then return not state.releaseFailed, state.releaseError end
    state.released = true
    if state.release then
        local ok, problem = pcall(state.release, state.action)
        if not ok then
            state.failed, state.releaseFailed, state.releaseError = true, true, problem
            return false, problem
        end
    end
    return true
end
function Lifecycle.clearStop(queue)
    local state = guardedStops[queue]
    guardedStops[queue] = nil
    if state then return releaseStop(state) end
    return true
end
function Lifecycle.invalidateStop(queue, action)
    local state = guardedStops[queue]
    if not state or state.action ~= action then return false end
    -- Keep restoration held until the ensuing native reset has cleared the old
    -- queue. Releasing here could enqueue earned returns into that same reset.
    state.failed = true
    return true
end
local function guardedValid(queue, action, state)
    local actor, token = state.actor, state.token
    local cancelled
    if type(token) == "table" then cancelled = rawget(token, "toolkitCancelled") end
    local settings = Toolkit.Settings and Toolkit.Settings.actionQueue()
    if guardedStops[queue] ~= state or state.failed or state.action ~= action or state.queue ~= queue or actor ~= action.character
        or queue.character ~= actor or ISTimedActionQueue.queues[actor] ~= queue
        or queue.queue ~= state.list or queue.current ~= action or state.list[1] ~= action
        or action.action ~= state.native or action.toolkitQueueOperation ~= token
        or (queue.toolkitOperationGeneration or 0) ~= state.generation
        or rawget(queue, "toolkitOperationsInvalid") ~= state.invalid or settings ~= state.settings
        or cancelled ~= state.cancelled or queue.toolkitCancel ~= action
        or queue.toolkitStopIntent ~= state.intent or queue.toolkitOutcomeWait ~= state.wait
        or queue.toolkitGroupCancel or queue.toolkitResume
        or actor:isDead() or actor:isAsleep() or not actor:isLocalPlayer()
        or getSpecificPlayer(actor:getPlayerNum()) ~= actor or actor:pressedCancelAction()
        or actor:isPlayerMoving() or actor:pressedMovement(false)
        or (action.stopOnRun and (actor:isRunning() or actor:isSprinting()))
        or (action.stopOnAim and actor:isAiming()) then return false end
    if state.validate then
        local ok, result = pcall(state.validate, action)
        if not ok or result ~= true or guardedStops[queue] ~= state or state.failed then return false end
    end
    return true
end
function Lifecycle.stopValid(queue, action)
    local state = guardedStops[queue]
    if not state then return true end
    if guardedValid(queue, action, state) then return true end
    state.failed = true
    return false
end

-- Policy grants permission before reaching this shared native stop boundary.
function Lifecycle.prepareStop(queue, action, reason, scope, options)
    if not owned(queue, action) or not action.action then return false end
    if queue.toolkitCancel == action then return true end
    options = options or {}
    if options.guarded and (guardedStops[queue] or queue.toolkitCancel or queue.toolkitStopIntent
        or queue.toolkitOutcomeWait or queue.toolkitGroupCancel or queue.toolkitResume) then return false end
    finishStepCancellations[queue] = nil
    local acknowledgements = Toolkit.ActionQueueAcknowledgements
    local receipt = acknowledgements and acknowledgements.capture(action)
    if options.guarded and isClient() and not receipt and not options.pendingStart then return false end
    queue.toolkitCancel = action
    queue.toolkitStopIntent = {reason = reason, scope = scope}
    if receipt or options.buildReceipt or (options.pendingStart and isClient()) then
        queue.toolkitOutcomeWait = {acknowledgement = receipt or options.buildReceipt,
            generic = receipt ~= nil or options.pendingStart == true, deadline = getTimestampMs() + 30000}
        if not receipt and options.pendingStart and isClient() then
            queue.toolkitOutcomeWait.pendingStart = {native = action.action, transaction = action.toolkitNativeTransaction,
                kind = action.toolkitNativeKind, generation = queue.toolkitOperationGeneration or 0}
        end
    end
    if options.guarded then
        local token = action.toolkitQueueOperation
        local cancelled
        if type(token) == "table" then cancelled = rawget(token, "toolkitCancelled") end
        guardedStops[queue] = {queue = queue, action = action, actor = action.character, list = queue.queue,
            native = action.action, token = token, cancelled = cancelled,
            generation = queue.toolkitOperationGeneration or 0, invalid = rawget(queue, "toolkitOperationsInvalid"),
            settings = Toolkit.Settings and Toolkit.Settings.actionQueue(), intent = queue.toolkitStopIntent,
            wait = queue.toolkitOutcomeWait, validate = options.validate, cleanup = options.cleanup, release = options.release}
    end
    return true
end
function Lifecycle.requestStop(queue, action, reason, scope, buildReceipt)
    if not owned(queue, action) or not action.action then return false end
    local state = guardedStops[queue]
    if state and state.action == action then Lifecycle.clearStop(queue) end
    if not Lifecycle.prepareStop(queue, action, reason, scope, {buildReceipt = buildReceipt}) then return false end
    action:forceStop()
    return true
end

function Lifecycle.runStop(action, callback, ...)
    local queue = action and ISTimedActionQueue.queues[action.character]
    local state = queue and guardedStops[queue]
    local previous = stopScope
    if state then
        if state.entered or not Lifecycle.stopValid(queue, action) then state.failed = true end
        state.entered = true
    end
    stopScope = {action = action, state = state}
    observe("begin", action, "stop")
    local results = pack(pcall(callback, action, ...))
    observe("finish", action, "stop", results[1])
    stopScope = previous
    if state then
        if not results[1] then state.failed = true; releaseStop(state)
        elseif not state.failed and state.reachedBaseStop then state.stoppedReturn = true end
    end
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2, results.n)
end
function Lifecycle.deferStop(queue, action)
    local state = guardedStops[queue]
    if not state then return nil end
    if not Lifecycle.stopValid(queue, action) or not stopScope or stopScope.action ~= action
        or stopScope.state ~= state or state.stoppedReturn or state.reachedBaseStop then
        state.failed = true
        return false
    end
    state.reachedBaseStop = true
    return true
end
function Lifecycle.takeStopCleanup(queue, action)
    local state = guardedStops[queue]
    if not state then return true end
    if not Lifecycle.stopValid(queue, action) or not state.stoppedReturn or not state.reachedBaseStop
        or state.actor:getCharacterActions():contains(state.native) then return false end
    guardedStops[queue] = nil
    if not state.cleanup and not state.release then return true end
    local taken = false
    return true, function(candidate)
        if taken then return end
        taken = true
        if candidate ~= action then
            local ok, problem = releaseStop(state)
            if not ok then error(problem, 0) end
            return
        end
        local results = pack(pcall(function() if state.cleanup then return state.cleanup(action) end end))
        local released, problem = releaseStop(state)
        if not results[1] then error(results[2], 0) end
        if not released then error(problem, 0) end
        return unpack(results, 2, results.n)
    end
end

-- Settings authorize a new episode, not the completion of callbacks already
-- admitted. Reset, ownership, native identity and generation still revoke it.
local function episodeOwned(queue, state)
    local action = state.action
    return owned(queue, action) and action.action == state.native
        and generationMatches(queue, action, state.generation)
        and not (action.character.isDead and action.character:isDead())
end

-- Called by the supported native LuaTimedActionNew boundary, never by individual action adapters.
function Lifecycle.begin(action, phase)
    if phase ~= "perform" and phase ~= "complete" then return false end
    local observing = observe("begin", action, phase)
    local intent=Toolkit.ActionQueueTidyIntent
    if intent and intent.begin(action,phase) then observing = true end
    local queue = action and ISTimedActionQueue.queues[action.character]
    local state = queue and owned(queue, action) and pending[queue]
    if state and (state.action ~= action or not episodeOwned(queue, state)) then pending[queue] = nil; state = nil end
    if not state and phase == "perform" and (enabled(action) or draining(action)) and owned(queue, action) and action.action
        and not (action.character.isDead and action.character:isDead()) then
        state = {action = action, native = action.action, generation = queue.toolkitOperationGeneration or 0,
            depth = 0, needsComplete = not isClient()}
        pending[queue] = state
    end
    if state then state.depth = state.depth + 1 end
    if not state and not observing then return false end
    -- A reset/restart can nest another episode on the same Lua table. Its
    -- callback must never receive the older episode's finish or failure.
    local entries = phaseEntries[action] or {}
    entries[#entries + 1] = {phase = phase, queue = queue, state = state}
    phaseEntries[action] = entries
    return true
end

function Lifecycle.finish(action, phase, succeeded)
    local entries = action and phaseEntries[action]
    local entry = entries and entries[#entries]
    if entry and entry.phase == phase then
        table.remove(entries)
        if #entries == 0 then phaseEntries[action] = nil end
    else entry = nil end
    observe("finish", action, phase, succeeded)
    local intent=Toolkit.ActionQueueTidyIntent
    if intent then intent.finish(action,phase,succeeded) end
    local queue = action and ISTimedActionQueue.queues[action.character]
    local seal = queue and finishStepCancellations[queue]
    if seal and seal.action == action then finishStepCancellations[queue] = nil end
    local state = entry and entry.state
    queue = entry and entry.queue
    if not state or pending[queue] ~= state then return end
    if not episodeOwned(queue, state) then pending[queue] = nil; return end
    state.depth = state.depth - 1
    state[phase] = true
    if not succeeded then state.failed = true end
end

function Lifecycle.deferCompletion(queue, action)
    local state = pending[queue]
    if state and state.action == action and episodeOwned(queue, state) then
        state.requested = true
        return true
    end
    return false
end

-- Recovery must not infer unfinished work from a row awaiting native removal.
function Lifecycle.completionEntered(queue, action)
    local state = pending[queue]
    return state ~= nil and state.action == action and episodeOwned(queue, state)
end

function Lifecycle.reset(queue)
    Lifecycle.clearStop(queue)
    pending[queue], finishStepCancellations[queue] = nil, nil
    if Toolkit.ActionQueueMedia then Toolkit.ActionQueueMedia.reset(queue) end
end

function Lifecycle.current(character)
    local queue = ISTimedActionQueue.queues[character]
    local state = queue and pending[queue]
    if state and state.depth > 0 and episodeOwned(queue, state) then return state.action end
end

-- A native callback has finished, but its owned Lua continuation has not advanced.
-- UI cancellation may still revoke this work after Java removes its action.
function Lifecycle.deferredAction(queue)
    local state = queue and pending[queue]
    if state and episodeOwned(queue, state) and enabled(state.action)
        and not state.failed and state.requested and state.depth == 0 and state.perform
        and (not state.needsComplete or state.complete)
        and not queue.character:getCharacterActions():contains(state.native) then return state.action end
end

-- Existing queue tick calls this before native tick; native removal is the final completion gate.
function Lifecycle.flush(queue)
    local state = pending[queue]
    if not state then return end
    local action = state.action
    if not owned(queue, action) then
        pending[queue] = nil
        return
    end
    if not episodeOwned(queue, state) then
        pending[queue] = nil
        return "failed", action
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
    if mediaState == "waiting" then
        -- Legacy reading replication waits belong to the optional editor.
        -- Native phase draining does not authorize a disabled asynchronous wait;
        -- standalone tracked media retains its separate disabled-mode contract.
        if not enabled(action) then pending[queue] = nil; return end
        return "waiting", action
    end
    local settlement = Toolkit.ActionQueueSettlement
    local cancellation = settlement and settlement.completionState(queue, action)
    if cancellation == "waiting" then return "waiting", action end
    pending[queue] = nil
    if cancellation == "failed" or mediaState == "failed" then return "failed", action end
    -- Receipts/effects are settled and Java has removed this exact episode, but
    -- native advancement has not retired its required cleanup record yet.
    -- Observers receive no edit capability; failures remain quarantined.
    observe("settled", action)
    if not episodeOwned(queue, state) then return "completed", action end
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
local expandCommand = operations and operations.expandCommand
ISQueueActionsAction.start = function(action)
    if not nativeCommand or not (Toolkit.Settings.actionQueue() or draining(action)) then return commandStart(action) end
    return expandCommand(action, operations.runWith, action.toolkitQueueOperation,
        action.addActionsFunction, action.character, unpack(action.args))
end
if operations then operations.adoptCommandLifecycle("start", commandStart, ISQueueActionsAction.start) end

-- A replaced/removed queue is no longer ticked by the native registry. Sweep
-- only our bounded private seals, without allocating or advancing a new queue.
if Events and Events.OnTick then
    Events.OnTick.Add(function()
        local detached
        for queue, state in pairs(guardedStops) do
            if ISTimedActionQueue.queues[state.actor] ~= queue
                or getSpecificPlayer(state.actor:getPlayerNum()) ~= state.actor then
                detached = detached or {}
                detached[#detached + 1] = {queue = queue, state = state}
            end
        end
        for _, entry in ipairs(detached or {}) do
            if guardedStops[entry.queue] == entry.state then Lifecycle.clearStop(entry.queue) end
        end
    end)
end
if Events and Events.OnMainMenuEnter then
    Events.OnMainMenuEnter.Add(function()
        for queue in pairs(guardedStops) do Lifecycle.clearStop(queue) end
    end)
end
return Lifecycle
