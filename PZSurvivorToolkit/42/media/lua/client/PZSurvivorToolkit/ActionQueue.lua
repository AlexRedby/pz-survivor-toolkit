require "PZSurvivorToolkit/Settings"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISReadABook"
require "PZSurvivorToolkit/ActionQueueOperations"
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
local returnMarker = {}
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

local begin = ISBaseTimedAction.begin
ISBaseTimedAction.begin = function(action)
    local token = action.toolkitQueueOperation
    if type(token) == "table" then token.toolkitStarted = true end
    return begin(action)
end

function Queue.cancel(queue, action)
    local decision = Policy.evaluateCancel(queue, action)
    Policy.record("cancel", action, decision)
    if not decision.allowed then return false, decision.reason end
    if craft(action) then return Queue.cancelOperation(queue, action) end
    if appliance(action) then return Queue.cancelOperation(queue, action) end
    local contract = Policy.inspect(action)
    if contract and contract.cancelWaiting and not stoppable(action) then return Queue.cancelOperation(queue, action) end
    local first, last = Operations.bounds(queue, action)
    if first == last and Operations.invalidate then Operations.invalidate(action.toolkitQueueOperation) end
    if action == queue.current then
        queue.toolkitCancel = action
        action:forceStop()
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
    if Operations.invalidate then Operations.invalidate(action.toolkitQueueOperation) end
    if Batch then Batch.cancel(action) end
    if first == 1 and queue.current == queue.queue[1] then
        local current = queue.current
        queue.toolkitGroupCancel = {action = current, token = current.toolkitQueueOperation}
        if stoppable(current) then
            queue.toolkitCancel = current
            current:forceStop()
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
    local current, token = request.action, request.token
    local last = 1
    while token and queue.queue[last + 1] and queue.queue[last + 1].toolkitQueueOperation == token do last = last + 1 end
    local returns = {}
    local inventory = queue.character:getInventory()
    for i = last, 2, -1 do
        local member = table.remove(queue.queue, i)
        if member.Type == "ISInventoryTransferAction" and member.allowMissingItems
            and member.srcContainer == inventory and member.destContainer ~= inventory then
            returns[member.item:getID()] = member.destContainer
        end
        member:forceCancel()
        if craft(member) then Toolkit.ActionQueueCraft.cancelWaiting(member) end
    end
    if craft(current) then Toolkit.ActionQueueCraft.cancelWaiting(current) end
    for item, source in pairs(type(token) == "table" and token.toolkitPickups or {}) do returns[item:getID()] = source end
    local containers = ISInventoryPaneContextMenu.getContainers(queue.character)
    local index = 2
    for id, destination in pairs(returns) do
        -- Native MP replication can replace the item object while retaining its ID.
        local item = inventory:getItemById(id)
        if item and item:getContainer() == inventory and not item:getIsCraftingConsumed()
            and destination:isExistYet() and containers:contains(destination) then
            local action = ISInventoryTransferUtil.newInventoryTransferAction(queue.character, item, inventory, destination)
            if action.Type == "ISInventoryTransferAction" then
                Toolkit.BulkActions.guardTransfer(action)
                action:setAllowMissingItems(true)
                action.toolkitQueueOperation, action.toolkitQueueReturn = {}, returnMarker
                table.insert(queue.queue, index, action)
                index = index + 1
            end
        end
    end
end

local completed = ISTimedActionQueue.onCompleted
ISTimedActionQueue.onCompleted = function(queue, action)
    if Operations.deferCompletion and Operations.deferCompletion(queue, action) then return end
    if queue.toolkitBuildWait and queue.toolkitCancel == action and queue.current == action and queue.queue[1] == action then
        queue.toolkitBuildWait.localCompleted = true
        return
    end
    if Batch and queue.current == action and queue.queue[1] == action and not queue.toolkitCancelStopped
        and not (action.toolkitQueueOperation and action.toolkitQueueOperation.toolkitCancelled)
        and not (action.action and action.action.hasStalled and action.action:hasStalled()) then Batch.completed(action) end
    local request = queue.toolkitGroupCancel
    if request and request.action == action then
        queue.toolkitGroupCancel = nil
        if live(queue) and queue.current == action and queue.queue[1] == action
            and not queue.character:isPlayerMoving() and not queue.character:pressedMovement(false) then
            finishGroup(queue, request)
        end
    end
    if processPriority then processPriority(queue, false) end
    return completed(queue, action)
end

function Queue.move(queue, action, target, after)
    local decision = Policy.evaluateMove(queue, action, target, after)
    Policy.record("move", action, decision)
    if not decision.allowed then return false, decision.reason end
    local to, first, last, preempt = decision.to, decision.first, decision.last, decision.preempt
    if to == first then return true end
    local world = Toolkit.ActionQueueWorld
    local acknowledgement = preempt and world and world.buildAcknowledgement and world.buildAcknowledgement(queue.current)
    local moved = {}
    for i = first, last do moved[#moved + 1] = table.remove(queue.queue, first) end
    if preempt then to = 2 end
    for i, member in ipairs(moved) do table.insert(queue.queue, to + i - 1, member) end
    if preempt then
        queue.toolkitResume = moved[#moved]
        queue.toolkitCancel = queue.current
        if acknowledgement then
            queue.toolkitBuildWait = {acknowledgement = acknowledgement, deadline = getTimestampMs() + 30000}
        end
        queue.current:forceStop()
    end
    return true
end

local function clearStop(queue)
    queue.toolkitCancel, queue.toolkitCancelStopped, queue.toolkitResume, queue.toolkitBuildWait = nil, nil, nil, nil
end

processPriority = function(queue, preempt)
    if not Toolkit.Settings.actionQueue() or not live(queue) or queue.toolkitCancel or queue.toolkitGroupCancel
        or not queue.current or queue.character:isPlayerMoving() or queue.character:pressedMovement(false) then return end
    local currentToken = queue.current.toolkitQueueOperation
    for _, action in ipairs(queue.queue) do
        local token = action.toolkitQueueOperation
        if token ~= currentToken and not (token and token.toolkitCancelled)
            and (action.toolkitQueuePriority == "urgent" or (token and token.toolkitPriority == "urgent")) then
            local decision = Policy.evaluatePriority(queue, action, preempt)
            local reason = decision.reason or (decision.after and "move_active" or nil)
            if type(token) == "table" and token.toolkitPriorityReason ~= reason then
                Policy.record("priority", action, decision)
            end
            if type(token) == "table" then token.toolkitPriorityReason = reason end
            if decision.allowed and decision.to ~= decision.first then Queue.move(queue, action, decision.target, decision.after) end
            return
        end
    end
end

local stop = ISBaseTimedAction.stop
ISBaseTimedAction.stop = function(action)
    local queue = ISTimedActionQueue.queues[action.character]
    local world = Toolkit.ActionQueueWorld
    if queue and not queue.toolkitCancel and queue.current == action and queue.queue[1] == action
        and ((queue.toolkitGroupCancel and queue.toolkitGroupCancel.action == action)
            or action.toolkitQueueReturn == returnMarker) then
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
        local generators, fire = Toolkit.ActionQueueGenerators, Toolkit.ActionQueueFire
        if (generators and generators.canSkip and generators.canSkip(action))
            or (fire and fire.canSkip and fire.canSkip(action)) then
            Operations.invalidate(action.toolkitQueueOperation)
            queue.toolkitGroupCancel = {action = action, token = action.toolkitQueueOperation}
            queue.toolkitCancel = action
        end
    end
    if queue and queue.toolkitCancel == action and live(queue)
        and (not queue.toolkitResume or (Toolkit.Settings.actionQueue()
            and not (action.toolkitQueueOperation and action.toolkitQueueOperation.toolkitCancelled)))
        and not action.character:isPlayerMoving() and not action.character:pressedMovement(false) then
        if Batch and not queue.toolkitGroupCancel and not queue.toolkitResume then Batch.discard(action) end
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
if Operations.adoptCommandLifecycle then Operations.adoptCommandLifecycle("stop", stop, ISBaseTimedAction.stop) end

local reset = ISTimedActionQueue.resetQueue
ISTimedActionQueue.resetQueue = function(queue)
    if Operations.invalidateQueue then Operations.invalidateQueue(queue) end
    if Toolkit.ActionQueueCraft and Toolkit.ActionQueueCraft.cancelQueue then Toolkit.ActionQueueCraft.cancelQueue(queue) end
    clearStop(queue)
    queue.toolkitGroupCancel = nil
    return reset(queue)
end

local clear = ISTimedActionQueue.clearQueue
ISTimedActionQueue.clearQueue = function(queue)
    if not queue:isCurrentActionAddingOtherActions() then
        if Operations.invalidateQueue then Operations.invalidateQueue(queue) end
        if Toolkit.ActionQueueCraft and Toolkit.ActionQueueCraft.cancelQueue then Toolkit.ActionQueueCraft.cancelQueue(queue) end
        clearStop(queue)
        queue.toolkitGroupCancel = nil
    end
    return clear(queue)
end

local tick = ISTimedActionQueue.tick
ISTimedActionQueue.tick = function(queue)
    if (not Toolkit.Settings.actionQueue() or not live(queue)) and Operations.invalidateQueue then
        if not queue.toolkitOperationsInvalid then Operations.invalidateQueue(queue); queue.toolkitOperationsInvalid = true end
    else queue.toolkitOperationsInvalid = nil end
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
        elseif queue.toolkitBuildWait then
            local wait = queue.toolkitBuildWait
            local state = Toolkit.ActionQueueWorld.buildState(action, wait.acknowledgement)
            if queue.character:isPlayerMoving() or queue.character:pressedMovement(false)
                or getTimestampMs() >= wait.deadline or not state then
                if getTimestampMs() >= wait.deadline then
                    print("[PZSurvivorToolkit] Build interruption timed out; cleared queue without replay.")
                end
                queue:resetQueue()
                queue.character:setIsFarming(false)
                return
            end
            if queue.character:getCharacterActions():contains(action.action)
                or state == "started" or not (queue.toolkitCancelStopped or wait.localCompleted) then return end
            local resumeAfter = queue.toolkitResume
            clearStop(queue)
            local index = resumeAfter and queue:indexOf(resumeAfter)
            if state == "canceled" and index and index > 1 then
                local resumed = Toolkit.ActionQueueWorld.resume(action, wait.acknowledgement)
                if resumed then
                    resumed.toolkitQueueOperation = action.toolkitQueueOperation
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
    return tick(queue)
end

Queue.label = Toolkit.ActionQueueLabels.label

require "PZSurvivorToolkit/ActionQueueGenerators"
require "PZSurvivorToolkit/ActionQueueFire"
require "PZSurvivorToolkit/ActionQueueWorld"
require "PZSurvivorToolkit/ActionQueueHealth"
require "PZSurvivorToolkit/ActionQueueCompat"
return Queue
