require "PZSurvivorToolkit/Settings"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISReadABook"
require "PZSurvivorToolkit/ActionQueueOperations"
require "PZSurvivorToolkit/ActionQueueLabels"

local Toolkit = PZSurvivorToolkit
local Queue = {}
Toolkit.ActionQueue = Queue

local Operations = Toolkit.ActionQueueOperations
local nativeForceCancel = ISBaseTimedAction.forceCancel

local begin = ISBaseTimedAction.begin
ISBaseTimedAction.begin = function(action)
    local token = action.toolkitQueueOperation
    if type(token) == "table" then token.toolkitStarted = true end
    return begin(action)
end

local function live(queue)
    local player = queue.character
    return player and getSpecificPlayer(player:getPlayerNum()) == player
        and not player:isDead() and not player:isAsleep()
end

local function resumableWorld(action)
    if action and Toolkit.ActionQueueWorld and Toolkit.ActionQueueWorld.canResume then
        return Toolkit.ActionQueueWorld.canResume(action)
    end
end

local function stoppable(action)
    return action.Type == "ISReadABook" or (action.Type == "ISMoveablesAction" and action.mode == "scrap")
        or resumableWorld(action)
end

local function deferredWorld(action)
    return action.Type == "ISQueueActionsAction" and Toolkit.ActionQueueWorld
        and type(Toolkit.ActionQueueWorld.isDeferredAction) == "function"
        and Toolkit.ActionQueueWorld.isDeferredAction(action)
end
Queue.isDeferredWorldAction = deferredWorld

function Queue.cancelReason(queue, action)
    if not Toolkit.Settings.actionQueue() or not queue or not live(queue)
        or queue:indexOf(action) == -1 then return "unavailable" end
    if queue.toolkitCancel then return "stopping" end
    if action.Type == "ISQueueActionsAction" then
        if not deferredWorld(action) then return "dependent" end
        return Queue.cancelOperationReason(queue, action)
    end
    if action._isAddingActions or action.onStartFunc
        or ((action.onCompleteFunc or action.onCancelFunc) and not resumableWorld(action))
        or action.retriggerLastAction or action.toolkitQueueLinked then return "dependent" end
    if not stoppable(action) and not action.toolkitIndependentBulk then
        return "dependent"
    end
    if action.toolkitIndependentBulk then
        -- A later arbitrary craft/generator may require this operation's output.
        for i = queue:indexOf(action) + 1, #queue.queue do
            local following = queue.queue[i]
            if not following.toolkitIndependentBulk and not following.toolkitBulkPreparation
                and following.Type ~= "ISReadABook"
                and following.Type ~= "ISInventoryTransferAction" then return "dependent" end
        end
    end
    if action == queue.current or queue.queue[1] == action then
        -- These native stop paths clean up visuals/sound; materials and outputs belong to completion.
        if not stoppable(action) then return "active" end
        if not action.action or not action.action:isStarted() or action.action:finished() or action.action:isForceComplete() then
            return "starting"
        end
    elseif action.action then
        return "active"
    end
end

function Queue.cancel(queue, action)
    local reason = Queue.cancelReason(queue, action)
    if reason then return false, reason end
    if action == queue.current then
        queue.toolkitCancel = action
        action:forceStop()
    else
        action:forceCancel()
        queue:removeFromQueue(action)
    end
    return true
end

local itemFields = {"item", "gun", "magazine", "weapon", "primary", "secondary"}
local function sharedItem(a, b)
    for _, key in ipairs(itemFields) do
        local item = a[key]
        if item and instanceof(item, "InventoryItem") then
            for _, other in ipairs(itemFields) do
                if item == b[other] then return true end
            end
        end
    end
end

local function sharedWorldTarget(a, b)
    local world = Toolkit.ActionQueueWorld
    if world and world.sharesTarget and world.sharesTarget(a, b) then return true end
    local objects = {a.generator, a.charger, a.object, a.moveProps and a.moveProps.object,
        a.toolkitWorldTarget, a.isoObject}
    for i = 1, 6 do
        local object = objects[i]
        if object and instanceof(object, "IsoObject") and (object == b.generator or object == b.charger
            or object == b.object or (b.moveProps and object == b.moveProps.object)
            or object == b.toolkitWorldTarget or object == b.isoObject) then return true end
    end
end

local groupPreparation = {
    ISWalkToTimedAction = true, ISWalkToTimedActionF = true, ISPathFindAction = true,
    ISEquipWeaponAction = true, ISEquipHeavyItem = true, ISUnequipAction = true,
}

local function operationItems(action)
    local items = {}
    for _, key in ipairs(itemFields) do
        local item = action[key]
        if item and instanceof(item, "InventoryItem") then items[item] = true end
    end
    if action.recipeItem and instanceof(action.recipeItem, "InventoryItem") then items[action.recipeItem] = true end
    if action.Type == "ISHandcraftAction" and action.items then
        for i = 0, action.items:size() - 1 do items[action.items:get(i)] = true end
    end
    if action.Type == "ISHandcraftAction" and action.manualInputs then
        for _, list in pairs(action.manualInputs) do
            for i = 0, list:size() - 1 do items[list:get(i)] = true end
        end
    end
    return items
end

local function craftPlan(action)
    return action.Type == "ISQueueActionsAction" and action.toolkitCraftPlanCancellation == true
        and Toolkit.CraftChainRecipes and type(Toolkit.CraftChainRecipes.addStep) == "function"
        and action.addActionsFunction == Toolkit.CraftChainRecipes.addStep
end
Queue.isCraftPlanAction = craftPlan

function Queue.cancelOperationReason(queue, action)
    if not Toolkit.Settings.actionQueue() or not queue or not live(queue)
        or queue:indexOf(action) == -1 then return "unavailable" end
    if queue.toolkitCancel then return "stopping" end
    local first, last = Operations.bounds(queue, action)
    if not first then return "operation_dependent" end
    local token = action.toolkitQueueOperation
    if type(token) == "table" and token.toolkitStarted then return "operation_active" end
    local main, output, inputs, scrapOnly = false, false, {}, true
    for i = first, last do
        local member = queue.queue[i]
        if member.action or member == queue.current or i == 1 then return "operation_active" end
        if member._isAddingActions or member.onStartFunc or member.onCancelFunc or member.retriggerLastAction
            or (member.onCompleteFunc and member.onCompleteFunc ~= member.toolkitQueueSafeOnComplete)
            or member.forceCancel ~= nativeForceCancel then return "operation_dependent" end
        local plannedCraft, world = craftPlan(member), deferredWorld(member)
        if member.Type == "ISQueueActionsAction" and not plannedCraft and not world then
            return "operation_dependent"
        end
        local supported = stoppable(member) or member.toolkitIndependentBulk or world or plannedCraft
        if not supported and not groupPreparation[member.Type]
            and member.Type ~= "ISInventoryTransferAction" then return "operation_dependent" end
        main = main or supported
        if supported then
            scrapOnly = scrapOnly and ((world and member.toolkitWorldDismantle)
                or (member.Type == "ISMoveablesAction" and member.mode == "scrap"))
        end
        output = output or member.toolkitIndependentBulk or (world and member.toolkitWorldOperation ~= "build") or plannedCraft
            or (member.Type == "ISMoveablesAction" and member.mode == "scrap")
        for item in pairs(operationItems(member)) do inputs[item] = true end
    end
    if not main then return "operation_dependent" end
    for i, other in ipairs(queue.queue) do
        if i < first or i > last then
            if other._isAddingActions then return "operation_dependent" end
            for item in pairs(operationItems(other)) do
                if inputs[item] then return "operation_shared_item" end
            end
            for j = first, last do
                if sharedWorldTarget(queue.queue[j], other) then return "operation_dependent" end
            end
            -- shortcut: output requirements of arbitrary later actions are unknown; add verified adapters to allow them.
            if output and i > last then
                if other.onStartFunc or other.onCancelFunc or other.retriggerLastAction
                    or (other.onCompleteFunc and other.onCompleteFunc ~= other.toolkitQueueSafeOnComplete)
                    or (not other.toolkitIndependentBulk and not other.toolkitBulkPreparation
                        and not (scrapOnly and deferredWorld(other) and other.toolkitWorldDismantle)
                        and not groupPreparation[other.Type] and other.Type ~= "ISReadABook"
                        and other.Type ~= "ISInventoryTransferAction") then return "operation_dependent" end
            end
        end
    end
    return nil, first, last
end

function Queue.cancelOperation(queue, action, expected)
    local reason, first, last = Queue.cancelOperationReason(queue, action)
    if reason then return false, reason end
    if expected then
        if #expected ~= last - first + 1 then return false, "unavailable" end
        for i, member in ipairs(expected) do
            if queue.queue[first + i - 1] ~= member then return false, "unavailable" end
        end
    end
    for i = last, first, -1 do
        queue.queue[i]:forceCancel()
        table.remove(queue.queue, i)
    end
    return true
end

function Queue.moveReason(queue, action, target, after)
    if not Toolkit.Settings.actionQueue() or not queue or not live(queue)
        or queue:indexOf(action) == -1 or queue:indexOf(target or action) == -1 then return "unavailable" end
    if queue.toolkitCancel then return "stopping" end
    local first, last = Operations.bounds(queue, action)
    local targetFirst, targetLast = Operations.bounds(queue, target or action)
    if not first or not targetFirst then return "move_dependent" end
    for i = first, last do
        local member = queue.queue[i]
        if member.action or member == queue.current or i == 1 then return "move_active" end
        if member._isAddingActions then return "move_dependent" end
    end
    if first == targetFirst then return nil, first, first, last end
    local to = after and targetLast + 1 or targetFirst
    local preempt = to == 1
    if preempt then
        local supported, reason = resumableWorld(queue.current)
        if not queue.current or (queue.current.Type ~= "ISReadABook" and not supported)
            or Queue.cancelReason(queue, queue.current) then return reason or "move_active" end
    end
    if preempt then
        for i = first, last do
            local member = queue.queue[i]
            -- Native reading progress is shared by book type, including different copies.
            if queue.current.Type == "ISReadABook" and member.Type == "ISReadABook"
                and member.item:getFullType() == queue.current.item:getFullType() then
                return "move_shared_book"
            end
        end
    end
    for i = math.min(first, to), math.min(#queue.queue, math.max(last, to - 1)) do
        if i < first or i > last then
            local crossed = queue.queue[i]
            if crossed._isAddingActions then return "move_dependent" end
            for j = first, last do
                if sharedItem(queue.queue[j], crossed) then return "move_shared_item" end
                if sharedWorldTarget(queue.queue[j], crossed) then return "move_dependent" end
            end
        end
    end
    if first < to then to = to - (last - first + 1) end
    return nil, to, first, last, preempt
end

function Queue.move(queue, action, target, after)
    local reason, to, first, last, preempt = Queue.moveReason(queue, action, target, after)
    if reason then return false, reason end
    if to == first then return true end
    local moved = {}
    for i = first, last do moved[#moved + 1] = table.remove(queue.queue, first) end
    if preempt then to = 2 end
    for i, member in ipairs(moved) do table.insert(queue.queue, to + i - 1, member) end
    if preempt then
        queue.toolkitResume = moved[#moved]
        queue.toolkitCancel = queue.current
        queue.current:forceStop()
    end
    return true
end

local function clearStop(queue)
    queue.toolkitCancel, queue.toolkitCancelStopped, queue.toolkitResume = nil, nil, nil
end

local stop = ISBaseTimedAction.stop
ISBaseTimedAction.stop = function(action)
    local queue = ISTimedActionQueue.queues[action.character]
    local world = Toolkit.ActionQueueWorld
    if queue and not queue.toolkitCancel and queue.current == action and queue.queue[1] == action
        and world and world.targetGone and world.targetGone(action) then
        local reason = Queue.cancelReason(queue, action)
        -- MP object removal can arrive before completion; native stop must not discard unrelated work.
        if not reason or reason == "starting" then queue.toolkitCancel = action end
    end
    if queue and queue.toolkitCancel == action and live(queue)
        and not action.character:isPlayerMoving() and not action.character:pressedMovement(false) then
        queue.toolkitCancelStopped = true
        action.character:setIsFarming(false)
        return
    end
    if queue then clearStop(queue) end
    return stop(action)
end

local tick = ISTimedActionQueue.tick
ISTimedActionQueue.tick = function(queue)
    local action = queue.toolkitCancel
    if action then
        if not live(queue) or queue.current ~= action or queue.queue[1] ~= action then
            clearStop(queue)
        elseif not queue.character:getCharacterActions():contains(action.action) then
            -- B42 sends the MP stop packet after Lua stop; resume only after Java removes the action.
            local stopped, resumeAfter = queue.toolkitCancelStopped, queue.toolkitResume
            clearStop(queue)
            if stopped then
                local index = resumeAfter and queue:indexOf(resumeAfter)
                if index and index > 1 then
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
    return tick(queue)
end

Queue.label = Toolkit.ActionQueueLabels.label

require "PZSurvivorToolkit/ActionQueueWorld"
return Queue
