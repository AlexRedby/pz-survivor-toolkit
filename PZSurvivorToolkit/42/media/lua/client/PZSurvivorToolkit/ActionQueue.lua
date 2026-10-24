require "PZSurvivorToolkit/Settings"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISReadABook"
require "PZSurvivorToolkit/ActionQueueOperations"
require "PZSurvivorToolkit/ActionQueueSettlement"
require "PZSurvivorToolkit/ActionQueueLifecycle"
require "PZSurvivorToolkit/ActionQueueAcknowledgements"
require "PZSurvivorToolkit/ActionQueueLabels"
require "PZSurvivorToolkit/ActionQueueCraft"
require "PZSurvivorToolkit/ActionQueueBatch"
require "TimedActions/ISInventoryTransferUtil"
require "TimedActions/ISEquipWeaponAction"
require "TimedActions/ISEquipHeavyItem"
require "TimedActions/ISUnequipAction"
require "Vehicles/TimedActions/ISPathFindAction"
require "PZSurvivorToolkit/BulkActions"
require "RadioCom/ISRadioAction"

local Toolkit = PZSurvivorToolkit
local Queue = {}
Toolkit.ActionQueue = Queue

local Operations = Toolkit.ActionQueueOperations
local Batch = Toolkit.ActionQueueBatch
local Settlement = Toolkit.ActionQueueSettlement
local processPriority
require "PZSurvivorToolkit/ActionQueuePolicy"
local Policy = Toolkit.ActionQueuePolicy
local craft, live, stoppable = Policy.isCraftAction, Policy.live, Policy.stoppable
local resumableWorld = Policy.resumableWorld
Queue.isCraftAction, Queue.isCraftPlanAction = craft, Policy.isCraftPlanAction
Queue.isDeferredWorldAction = Policy.isDeferredWorldAction
Queue.cancelReason, Queue.cancelOperationReason, Queue.moveReason = Policy.cancelReason, Policy.cancelOperationReason, Policy.moveReason
local function appliance(action)
    local world = Toolkit.ActionQueueWorld
    return world and world.isApplianceAction and world.isApplianceAction(action)
end

local function updateOperationState(queue)
    if not queue then return end
    if (not Toolkit.Settings.actionQueue() or not live(queue)) and Operations.invalidateQueue then
        if not queue.toolkitOperationsInvalid then Operations.invalidateQueue(queue); queue.toolkitOperationsInvalid = true end
    else queue.toolkitOperationsInvalid = nil end
end
-- Producers that capture receipts before enqueueing must share the same boundary
-- as begin/tick, so the first native begin cannot invalidate their own receipt.
Queue.updateOperationState = updateOperationState

local begin = ISBaseTimedAction.begin
ISBaseTimedAction.begin = function(action)
    if Toolkit.ActionQueueRecovery then Toolkit.ActionQueueRecovery.started(action) end
    -- Initialize disabled-mode bookkeeping before native allocation/receipts.
    -- Its first tick must not revoke a freshly captured media transaction.
    updateOperationState(ISTimedActionQueue.queues[action.character])
    local media = Toolkit.ActionQueueMedia
    if media then media.start(action) end
    local intent=Toolkit.ActionQueueTidyIntent
    if intent and isClient() then intent.start(action) end
    Toolkit.ActionQueueLifecycle.started(action)
    local token = action.toolkitQueueOperation
    if type(token) == "table" then token.toolkitStarted = true end
    local result = begin(action)
    if media then media.bind(action) end
    return result
end
Policy.adoptBegin(begin, ISBaseTimedAction.begin)

function Queue.cancel(queue, action)
    local decision = Policy.evaluateCancel(queue, action)
    Policy.record("cancel", action, decision)
    if not decision.allowed then return false, decision.reason end
    if craft(action) then return Queue.cancelOperation(queue, action) end
    -- Policy validates deferred commands as complete operations. Execute that
    -- same edit, so required preparation cannot be detached from its body.
    if action.Type == "ISQueueActionsAction" then return Queue.cancelOperation(queue, action) end
    if appliance(action) then return Queue.cancelOperation(queue, action) end
    local contract = Policy.inspect(action)
    if contract and contract.cancelWaiting and not stoppable(action) then return Queue.cancelOperation(queue, action) end
    local first, last = Operations.bounds(queue, action)
    if not Policy.editUnchanged(queue, decision.snapshot) then return false, "unavailable" end
    decision = Policy.evaluateCancel(queue, action)
    if not decision.allowed then return false, decision.reason end
    if first == last and Operations.invalidate then Operations.invalidate(action.toolkitQueueOperation) end
    if action == queue.current then
        return Toolkit.ActionQueueLifecycle.requestStop(queue, action, "cancel", "action")
    else
        if Batch then Batch.discard(action) end
        action:forceCancel()
        queue:removeFromQueue(action)
    end
    return true
end

function Queue.cancelOperation(queue, action, expected)
    local decision = Policy.evaluateCancel(queue, action, true)
    Policy.record("cancel-operation", action, decision)
    if not decision.allowed then return false, decision.reason end
    local first, last = decision.first, decision.last
    if expected then
        if #expected ~= last - first + 1 then return false, "unavailable" end
        for i, member in ipairs(expected) do
            if queue.queue[first + i - 1] ~= member then return false, "unavailable" end
        end
    end
    if not Policy.editUnchanged(queue, decision.snapshot) then return false, "unavailable" end
    decision = Policy.evaluateCancel(queue, action, true)
    if not decision.allowed then return false, decision.reason end
    if decision.first ~= first or decision.last ~= last then return false, "unavailable" end
    local request
    if first == 1 and queue.current == queue.queue[1] then
        local current = queue.current
        request = {action = current, token = current.toolkitQueueOperation}
        if not stoppable(current) then
            Toolkit.ActionQueueLifecycle.acceptFinishStepCancellation(queue, current, request, decision)
        end
    end
    if Operations.invalidate then Operations.invalidate(action.toolkitQueueOperation) end
    if Batch then Batch.cancel(action) end
    if request then
        local current = queue.current
        queue.toolkitGroupCancel = request
        if stoppable(current) then
            Toolkit.ActionQueueLifecycle.requestStop(queue, current, "cancel", "operation")
        end
        -- In-flight pickups/equipment finish natively before dropping the remaining work.
        return true
    end
    local removed = {}
    for i = last, first, -1 do
        removed[#removed + 1] = table.remove(queue.queue, i)
    end
    for _, member in ipairs(removed) do
        member:forceCancel()
        if craft(member) then Toolkit.ActionQueueCraft.cancelWaiting(member) end
    end
    return true
end

local function finishGroup(queue, request)
    return Settlement.finish(queue, request, function(member, completed)
        if not completed then member:forceCancel() end
        if craft(member) then Toolkit.ActionQueueCraft.cancelWaiting(member) end
    end)
end

local completed = ISTimedActionQueue.onCompleted
ISTimedActionQueue.onCompleted = function(queue, action)
    if Toolkit.ActionQueueApproach then Toolkit.ActionQueueApproach.completed(action) end
    if Toolkit.ActionQueueRecovery then Toolkit.ActionQueueRecovery.completed(action) end
    if Toolkit.ActionQueueLifecycle.deferCompletion(queue, action) then return end
    if Operations.deferCompletion and Operations.deferCompletion(queue, action) then return end
    if queue.toolkitOutcomeWait and queue.toolkitCancel == action and queue.current == action and queue.queue[1] == action then
        queue.toolkitOutcomeWait.localCompleted = true
        return
    end
    if Batch and queue.current == action and queue.queue[1] == action and not queue.toolkitCancelStopped
        and not (action.toolkitQueueOperation and action.toolkitQueueOperation.toolkitCancelled)
        and not (action.action and action.action.hasStalled and action.action:hasStalled()) then Batch.completed(action) end
    local request = queue.toolkitGroupCancel
    if request and request.action == action then
        if live(queue) and queue.current == action and queue.queue[1] == action
            and not queue.character:isPlayerMoving() and not queue.character:pressedMovement(false) then
            if not finishGroup(queue, request) then queue:resetQueue(); return end
        end
        queue.toolkitGroupCancel = nil
    end
    if processPriority then processPriority(queue, false) end
    if Toolkit.Settings.actionQueue() and Toolkit.BulkFood and queue.current == action and queue.queue[1] == action then
        Toolkit.BulkFood.skipUnavailable(queue)
    end
    if Toolkit.Settings.actionQueue() and queue.current == action and queue.queue[1] == action then
        if Toolkit.ActionQueueFire and Toolkit.ActionQueueFire.skipUnavailableReturns then
            Toolkit.ActionQueueFire.skipUnavailableReturns(queue, action)
        end
        if Toolkit.ActionQueueFitness then Toolkit.ActionQueueFitness.skipUnavailable(queue) end
        Policy.skipUnavailableHygiene(queue)
        if Toolkit.ActionQueueReading then Toolkit.ActionQueueReading.skipUnavailable(queue) end
    end
    local generators = Toolkit.ActionQueueGenerators
    local fire = Toolkit.ActionQueueFire
    local Craft = Toolkit.ActionQueueCraft
    if Toolkit.Settings.actionQueue() and live(queue) and queue.current == action and queue.queue[1] == action
        and not queue.character:isPlayerMoving() and not queue.character:pressedMovement(false) then
        local pending = queue.queue[2]
        -- Skip audited unavailable targets before native validation/start can discard the independent tail.
        while pending and not pending.action and ((generators and generators.canSkip and generators.canSkip(pending))
            or (fire and fire.canSkip and fire.canSkip(pending))
            or (Craft and Craft.canSkip and Craft.canSkip(pending))) do
            local token = pending.toolkitQueueOperation
            if token and token == action.toolkitQueueOperation then
                local reason = Policy.cancelOperationReason(queue, pending)
                if reason and reason ~= "starting" then break end
                Operations.invalidate(token)
                if Batch then Batch.cancel(pending) end
                finishGroup(queue, {action = action, token = token})
            elseif not Queue.cancelOperation(queue, pending) then break end
            if queue.queue[2] == pending then break end
            pending = queue.queue[2]
        end
    end
    return completed(queue, action)
end

function Queue.move(queue, action, target, after)
    local decision = Policy.evaluateMove(queue, action, target, after)
    Policy.record("move", action, decision)
    if not decision.allowed then return false, decision.reason end
    if not Policy.editUnchanged(queue, decision.snapshot) then return false, "unavailable" end
    decision = Policy.evaluateMove(queue, action, target, after)
    if not decision.allowed then return false, decision.reason end
    local to, first, last, preempt = decision.to, decision.first, decision.last, decision.preempt
    if to == first then return true end
    if decision.demote then Toolkit.ActionQueueReading.capture(queue, first, last) end
    local world = Toolkit.ActionQueueWorld
    local acknowledgement = preempt and world and world.buildAcknowledgement and world.buildAcknowledgement(queue.current)
    if not Policy.editUnchanged(queue, decision.snapshot) then return false, "unavailable" end
    local moved = {}
    for i = first, last do moved[#moved + 1] = table.remove(queue.queue, first) end
    if preempt then to = 2 end
    for i, member in ipairs(moved) do table.insert(queue.queue, to + i - 1, member) end
    if preempt then
        queue.toolkitResume = moved[#moved]
        Toolkit.ActionQueueLifecycle.requestStop(queue, queue.current, "preempt", "action", acknowledgement)
    end
    return true
end

local function clearStop(queue)
    queue.toolkitCancel, queue.toolkitCancelStopped, queue.toolkitResume, queue.toolkitOutcomeWait, queue.toolkitStopIntent = nil, nil, nil, nil, nil
end

processPriority = function(queue, preempt)
    if not Toolkit.Settings.actionQueue() or not live(queue) or queue.toolkitCancel or queue.toolkitGroupCancel
        or not queue.current or queue.character:isPlayerMoving() or queue.character:pressedMovement(false) then return end
    local currentToken = queue.current.toolkitQueueOperation
    local activeLast = 1
    while currentToken and queue.queue[activeLast + 1]
        and queue.queue[activeLast + 1].toolkitQueueOperation == currentToken do activeLast = activeLast + 1 end
    for index, action in ipairs(queue.queue) do
        local token = action.toolkitQueueOperation
        if token ~= currentToken and not (token and token.toolkitCancelled)
            and (action.toolkitQueuePriority == "urgent" or (token and token.toolkitPriority == "urgent")) then
            local decision
            if index == activeLast + 1 and (not preempt or activeLast > 1
                or (currentToken and currentToken.toolkitPriority == "urgent")
                or (queue.current.Type ~= "ISReadABook" and not resumableWorld(queue.current))) then
                -- Already at the earliest boundary and the active operation
                -- cannot be interrupted. Resource checks cannot improve its place.
                decision = {after = true}
            else
                decision = Policy.priorityIntent(queue, action, preempt)
            end
            local reason = decision.reason or (decision.after and "move_active" or nil)
            if type(token) == "table" and token.toolkitPriorityReason ~= reason then
                Policy.record("priority", action, decision)
            end
            if type(token) == "table" then token.toolkitPriorityReason = reason end
            if decision.candidate then Queue.move(queue, action, decision.target, decision.after) end
            return
        end
    end
end

local stop = ISBaseTimedAction.stop
ISBaseTimedAction.stop = function(action)
    local approach = Toolkit.ActionQueueApproach
    if approach then approach.onStop(action) end
    if Toolkit.ActionQueueMedia then Toolkit.ActionQueueMedia.stop(action) end
    local queue = ISTimedActionQueue.queues[action.character]
    local world = Toolkit.ActionQueueWorld
    if queue and not queue.toolkitCancel and queue.current == action and queue.queue[1] == action
        and ((queue.toolkitGroupCancel and queue.toolkitGroupCancel.action == action)
            or Settlement.isCleanup(action)) then
        queue.toolkitCancel = action
    end
    if queue and not queue.toolkitCancel and queue.current == action and queue.queue[1] == action
        and world and world.wreckTargetGone and world.wreckTargetGone(action) then
        queue.toolkitCancel = action
    end
    if queue and not queue.toolkitCancel and queue.current == action and queue.queue[1] == action
        and world and world.targetGone and world.targetGone(action) then
        local reason = Queue.cancelReason(queue, action)
        -- MP object removal can arrive before completion; native stop must not discard unrelated work.
        if not reason or reason == "starting" then queue.toolkitCancel = action end
    end
    if Toolkit.Settings.actionQueue() and queue and not queue.toolkitCancel and queue.current == action and queue.queue[1] == action then
        if Toolkit.BulkFood and Toolkit.BulkFood.missing(action) then queue.toolkitCancel = action end
        if Policy.hygieneUnavailable(action) then queue.toolkitCancel = action end
        if Toolkit.ActionQueueFitness then Toolkit.ActionQueueFitness.canPreserveStop(action) end
        local generators, fire, health = Toolkit.ActionQueueGenerators, Toolkit.ActionQueueFire, Toolkit.ActionQueueHealth
        local fireUnavailable = fire and fire.canSkip and fire.canSkip(action)
        if (generators and generators.canSkip and generators.canSkip(action))
            or fireUnavailable
            or (health and health.canPreserveStop and health.canPreserveStop(action))
            or (Toolkit.ActionQueueMedia and Toolkit.ActionQueueMedia.canSkipUnavailable
                and Toolkit.ActionQueueMedia.canSkipUnavailable(action)) then
            local request = {action = action, token = action.toolkitQueueOperation}
            local receipt = fireUnavailable and Toolkit.ActionQueueAcknowledgements.capture(action)
            if receipt then
                -- Replicated ignition/consumption can invalidate native BBQ before its completed receipt arrives.
                queue.toolkitOutcomeWait = {acknowledgement = receipt, generic = true,
                    deadline = getTimestampMs() + 30000, operation = request}
            else
                Operations.invalidate(request.token)
                queue.toolkitGroupCancel = request
            end
            queue.toolkitCancel = action
        end
    end
    if queue and queue.toolkitCancel == action and live(queue)
        and (not queue.toolkitResume or (Toolkit.Settings.actionQueue()
            and not (action.toolkitQueueOperation and action.toolkitQueueOperation.toolkitCancelled)))
        and not action.character:isPlayerMoving() and not action.character:pressedMovement(false) then
        if Batch and not queue.toolkitGroupCancel and not queue.toolkitResume
            and not (queue.toolkitOutcomeWait and queue.toolkitOutcomeWait.operation) then Batch.discard(action) end
        if queue.toolkitGroupCancel and craft(action) then Toolkit.ActionQueueCraft.nativeStopped(action) end
        queue.toolkitCancelStopped = true
        action.character:setIsFarming(false)
        return
    end
    if queue then
        if craft(action) then Toolkit.ActionQueueCraft.nativeStopped(action) end
        clearStop(queue); queue.toolkitGroupCancel = nil
    end
    return stop(action)
end
Policy.replaceStop(stop, ISBaseTimedAction.stop)
if Toolkit.ActionQueueCompat then Toolkit.ActionQueueCompat.adoptStop(stop, ISBaseTimedAction.stop) end
if Operations.adoptCommandLifecycle then Operations.adoptCommandLifecycle("stop", stop, ISBaseTimedAction.stop) end

-- Native reset/clear delegate here even when another mod retains an earlier reset wrapper.
local cancelQueue = ISTimedActionQueue.cancelQueue
ISTimedActionQueue.cancelQueue = function(queue)
    if Toolkit.ActionQueueApproach then Toolkit.ActionQueueApproach.reset(queue) end
    if Toolkit.ActionQueueRecovery then Toolkit.ActionQueueRecovery.capture(queue) end
    Toolkit.ActionQueueLifecycle.reset(queue)
    Toolkit.ActionQueueAcknowledgements.reset(queue)
    if Operations.invalidateQueue then Operations.invalidateQueue(queue) end
    if Toolkit.ActionQueueCraft and Toolkit.ActionQueueCraft.cancelQueue then Toolkit.ActionQueueCraft.cancelQueue(queue) end
    clearStop(queue)
    queue.toolkitGroupCancel = nil
    return cancelQueue(queue)
end

local tick = ISTimedActionQueue.tick
ISTimedActionQueue.tick = function(queue)
    -- Walking may continue native inventory actions. Keep their completed callback
    -- until Java removes the action; native stop/reset still revokes completion.
    if not live(queue) then
        Toolkit.ActionQueueLifecycle.reset(queue)
    end
    local completion = Toolkit.ActionQueueLifecycle.flush(queue)
    if completion == "waiting" or completion == "completed" then return end
    if completion == "failed" then queue:resetQueue(); return end
    updateOperationState(queue)
    if queue.toolkitResume and (not Toolkit.Settings.actionQueue()
        or (queue.toolkitCancel and queue.toolkitCancel.toolkitQueueOperation
            and queue.toolkitCancel.toolkitQueueOperation.toolkitCancelled)) then clearStop(queue) end
    processPriority(queue, true)
    local action = queue.toolkitCancel
    if action then
        if not live(queue) or queue.current ~= action or queue.queue[1] ~= action then
            clearStop(queue)
        elseif queue.character:isPlayerMoving() or queue.character:pressedMovement(false) then
            queue:resetQueue()
            queue.character:setIsFarming(false)
            return
        elseif queue.toolkitOutcomeWait then
            local wait = queue.toolkitOutcomeWait
            if wait.pendingStart then
                local binding = wait.pendingStart
                if action.action ~= binding.native or action.toolkitNativeTransaction ~= binding.transaction
                    or action.toolkitNativeKind ~= binding.kind
                    or (queue.toolkitOperationGeneration or 0) ~= binding.generation then
                    queue:resetQueue()
                    queue.character:setIsFarming(false)
                    return
                end
                wait.acknowledgement = Toolkit.ActionQueueAcknowledgements.capture(action)
                if wait.acknowledgement then wait.pendingStart = nil end
            end
            local state = wait.generic and Toolkit.ActionQueueAcknowledgements.state(action, wait.acknowledgement)
                or not wait.generic and Toolkit.ActionQueueWorld.buildState(action, wait.acknowledgement)
            if queue.character:isPlayerMoving() or queue.character:pressedMovement(false)
                or getTimestampMs() >= wait.deadline or (not state and not wait.pendingStart)
                or (wait.operation and (wait.operation.action ~= action or wait.operation.token ~= action.toolkitQueueOperation
                    or (type(wait.operation.token) == "table" and wait.operation.token.toolkitCancelled))) then
                if getTimestampMs() >= wait.deadline then
                    print("[PZSurvivorToolkit] Action interruption timed out; cleared queue without replay.")
                end
                queue:resetQueue()
                queue.character:setIsFarming(false)
                return
            end
            if wait.pendingStart or queue.character:getCharacterActions():contains(action.action)
                or state == "started" or not (queue.toolkitCancelStopped or wait.localCompleted) then return end
            if wait.operation and state ~= "completed" then
                Operations.invalidate(wait.operation.token)
                queue.toolkitGroupCancel = wait.operation
            end
            local resumeAfter = queue.toolkitResume
            clearStop(queue)
            local index = resumeAfter and queue:indexOf(resumeAfter)
            if state == "canceled" and index and index > 1
                and (action.Type ~= "ISReadABook" or stoppable(action)) then
                local resumed = action.Type == "ISReadABook" and ISReadABook:new(queue.character, action.item)
                    or Toolkit.ActionQueueWorld.resume(action, wait.acknowledgement)
                if resumed then
                    resumed.toolkitQueueOperation = action.toolkitQueueOperation
                    if Toolkit.ActionQueueReading then Toolkit.ActionQueueReading.resumed(action, resumed) end
                    table.insert(queue.queue, index + 1, resumed)
                end
            end
            queue:onCompleted(action)
            return
        elseif not queue.character:getCharacterActions():contains(action.action) then
            -- B42 sends the MP stop packet after Lua stop; resume only after Java removes the action.
            local stopped, resumeAfter = queue.toolkitCancelStopped, queue.toolkitResume
            clearStop(queue)
            if stopped then
                local index = resumeAfter and queue:indexOf(resumeAfter)
                if index and index > 1 and stoppable(action) then
                    -- Native constructors restore saved pages; world work prepares tools and validates again.
                    local resumed = action.Type == "ISReadABook" and ISReadABook:new(queue.character, action.item)
                        or Toolkit.ActionQueueWorld.resume(action)
                    if resumed then
                        resumed.toolkitQueueOperation = action.toolkitQueueOperation
                        if Toolkit.ActionQueueReading then Toolkit.ActionQueueReading.resumed(action, resumed) end
                        table.insert(queue.queue, index + 1, resumed)
                    end
                end
                queue:onCompleted(action)
                return
            end
        else
            return
        end
    end
    -- Native idle clear is housekeeping; explicit clear still revokes late continuations.
    if not queue.queue[1] then return end
    local current, health = queue.queue[1], Toolkit.ActionQueueHealth
    -- Java removes invalid, never-started actions without stop(); native tick would clear unrelated work.
    if Toolkit.Settings.actionQueue() and live(queue) and queue.current == current and current.action
        and not current:isStarted() and not queue.character:getCharacterActions():contains(current.action)
        and not queue.character:isPlayerMoving() and not queue.character:pressedMovement(false)
        and ((health and health.canSkip(current) and health.canPreserveStop(current))
            or (Toolkit.ActionQueueFitness and Toolkit.ActionQueueFitness.canSkip(current)
                and not Toolkit.ActionQueueAcknowledgements.capture(current))
            or (Toolkit.ActionQueueMedia and Toolkit.ActionQueueMedia.canSkipUnavailable
                and Toolkit.ActionQueueMedia.canSkipUnavailable(current)
                and not Toolkit.ActionQueueAcknowledgements.capture(current))) then
        Operations.invalidate(current.toolkitQueueOperation)
        queue.toolkitGroupCancel = {action = current, token = current.toolkitQueueOperation}
        current:forceCancel()
        queue:onCompleted(current)
        return
    end
    return tick(queue)
end

Queue.label = Toolkit.ActionQueueLabels.label

require "PZSurvivorToolkit/ActionQueueCompat"
require "PZSurvivorToolkit/ActionQueueGenerators"
require "PZSurvivorToolkit/ActionQueueFire"
require "PZSurvivorToolkit/ActionQueueWorld"
require "PZSurvivorToolkit/ActionQueueHealth"
require "PZSurvivorToolkit/ActionQueueFitness"
require "PZSurvivorToolkit/ActionQueueReading"
require "PZSurvivorToolkit/ActionQueueMedia"
if Toolkit.ActionQueueMedia then Toolkit.ActionQueueMedia.install() end
require "PZSurvivorToolkit/ActionQueueRecovery"
return Queue
