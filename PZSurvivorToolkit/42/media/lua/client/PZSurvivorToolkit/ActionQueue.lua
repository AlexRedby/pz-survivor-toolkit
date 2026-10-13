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
local nativeForceCancel = ISBaseTimedAction.forceCancel
local returnMarker = {}

local function craft(action)
    return Toolkit.ActionQueueCraft and Toolkit.ActionQueueCraft.supports(action)
end

Queue.isCraftAction = craft

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
        or resumableWorld(action) or craft(action)
end

local function deferredWorld(action)
    return action.Type == "ISQueueActionsAction" and Toolkit.ActionQueueWorld
        and type(Toolkit.ActionQueueWorld.isDeferredAction) == "function"
        and Toolkit.ActionQueueWorld.isDeferredAction(action)
end
Queue.isDeferredWorldAction = deferredWorld

local function appliance(action)
    local world = Toolkit.ActionQueueWorld
    return world and world.isApplianceAction and world.isApplianceAction(action)
end

function Queue.cancelReason(queue, action)
    if not Toolkit.Settings.actionQueue() or not queue or not live(queue)
        or queue:indexOf(action) == -1 then return "unavailable" end
    if queue.toolkitCancel or queue.toolkitGroupCancel then return "stopping" end
    if craft(action) then return Queue.cancelOperationReason(queue, action) end
    if appliance(action) then return Queue.cancelOperationReason(queue, action) end
    if action.Type == "ISQueueActionsAction" then
        if not deferredWorld(action) then return "dependent" end
        return Queue.cancelOperationReason(queue, action)
    end
    if action._isAddingActions or (action.onStartFunc and not craft(action))
        or ((action.onCompleteFunc or action.onCancelFunc) and not resumableWorld(action) and not craft(action))
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
    if craft(action) then return Queue.cancelOperation(queue, action) end
    if appliance(action) then return Queue.cancelOperation(queue, action) end
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

local itemFields = {"item", "gun", "magazine", "weapon", "primary", "secondary"}
local function itemKey(item)
    return instanceof(item, "InventoryItem") and item:getID() or item
end
local operationItems
local function sharedItem(a, b)
    local left, right = operationItems(a), operationItems(b)
    for item in pairs(left) do if right[item] then return true end end
end

local function knownCraftInputs(action)
    if craft(action) then return Toolkit.ActionQueueCraft.collectItems(action, {}) end
    return action.Type ~= "ISHandcraftAction" and action.Type ~= "ISCraftAction" and action.Type ~= "ISFixAction"
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

local preparationMethods = {"start", "stop", "perform", "complete", "isValid", "update", "forceStop", "forceCancel"}
local nativePreparation = {}
for kind in pairs(groupPreparation) do
    local class = _G[kind]
    if class then
        local methods = {}
        for _, name in ipairs(preparationMethods) do methods[name] = class[name] end
        nativePreparation[class] = methods
    end
end
local transferMethods = {}
for _, name in ipairs(preparationMethods) do transferMethods[name] = ISInventoryTransferAction[name] end
nativePreparation[ISInventoryTransferAction] = transferMethods

local function preparationCanFinish(action)
    if appliance(action) then return true end
    if Toolkit.BulkActions.canFinish and Toolkit.BulkActions.canFinish(action) then return true end
    local methods = nativePreparation[getmetatable(action)]
    if not methods then return false end
    for _, name in ipairs(preparationMethods) do
        if action[name] ~= methods[name] and not (name == "stop" and action.Type == "ISInventoryTransferAction"
            and Toolkit.BulkActions.isGuardedTransfer(action, methods.stop)) then return false end
    end
    return true
end

operationItems = function(action)
    local items = {}
    for _, key in ipairs(itemFields) do
        local item = action[key]
        if item and instanceof(item, "InventoryItem") then items[item] = true end
    end
    if action.recipeItem and instanceof(action.recipeItem, "InventoryItem") then items[action.recipeItem] = true end
    if Toolkit.ActionQueueCraft then Toolkit.ActionQueueCraft.collectItems(action, items) end
    local keys = {}
    for item in pairs(items) do keys[itemKey(item)] = true end
    return keys
end

local repairIndependent = {}
for _, class in ipairs({ISReadABook, ISRadioAction}) do
    local methods = {}
    for _, name in ipairs(preparationMethods) do methods[name] = class[name] end
    repairIndependent[class] = methods
end
local radioModes = {ToggleOnOff = true, SetChannel = true, MuteVolume = true, UnMuteVolume = true,
    SetVolume = true, MuteMicrophone = true, TogglePlayMedia = true}
local radioMethods = {}
if ISRadioAction then
    for mode in pairs(radioModes) do
        for _, prefix in ipairs({"isValid", "start", "perform"}) do
            local name = prefix .. mode
            radioMethods[name] = ISRadioAction[name] or false
        end
    end
end

local function repairInputs(action)
    local helper = Toolkit.ActionQueueCraft
    return helper and helper.repairInputs and helper.repairInputs(action)
end

local function repairCanCross(repair, other)
    local types = repairInputs(repair)
    if not types then return true end
    if other.onStartFunc or other.onCompleteFunc or other.onCancelFunc or other.retriggerLastAction then return false end
    local methods = repairIndependent[getmetatable(other)]
    if methods then
        for _, name in ipairs(preparationMethods) do
            if other[name] ~= methods[name] then return false end
        end
        if getmetatable(other) == ISRadioAction then
            if not radioModes[other.mode] then return false end
            for name, method in pairs(radioMethods) do
                if (other[name] or false) ~= method then return false end
            end
        end
    elseif (other.Type ~= "ISInventoryTransferAction" and other.Type ~= "ISWalkToTimedAction"
        and other.Type ~= "ISWalkToTimedActionF" and other.Type ~= "ISPathFindAction") or not preparationCanFinish(other) then
        -- shortcut: craft/world outputs and other repairs can supply new donors; audit their outputs before allowing a crossing.
        return false
    end
    local function independent(item)
        if not item or not instanceof(item, "InventoryItem") then return true end
        return not instanceof(item, "InventoryContainer") and not types[item:getFullType()]
            and item:getID() ~= repair.item:getID()
    end
    for _, name in ipairs(itemFields) do if not independent(other[name]) then return false end end
    if not independent(other.device) or not independent(other.secondaryItem) then return false end
    for _, batch in ipairs(other.queueList or {}) do
        for _, item in ipairs(batch.items) do if not independent(item) then return false end end
    end
    return true
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
    if queue.toolkitCancel or queue.toolkitGroupCancel then return "stopping" end
    local first, last = Operations.bounds(queue, action)
    if not first then return "operation_dependent" end
    local token = action.toolkitQueueOperation
    local active = first == 1 and queue.current == queue.queue[1]
    if type(token) == "table" and token.toolkitStarted and not active then return "operation_active" end
    local main, output, inputs, scrapOnly = false, false, {}, true
    for i = first, last do
        local member = queue.queue[i]
        if (member.action or member == queue.current or i == 1) and not (active and i == first) then
            return "operation_active"
        end
        local auditedCraft = craft(member)
        if member._isAddingActions or ((member.onStartFunc or member.onCancelFunc) and not auditedCraft and not resumableWorld(member)) or member.retriggerLastAction
            or (member.onCompleteFunc and member.onCompleteFunc ~= member.toolkitQueueSafeOnComplete
                and not auditedCraft and not resumableWorld(member))
            or member.forceCancel ~= nativeForceCancel then return "operation_dependent" end
        local plannedCraft, world = craftPlan(member), deferredWorld(member)
        if member.Type == "ISQueueActionsAction" and not plannedCraft and not world then
            return "operation_dependent"
        end
        local supported = stoppable(member) or member.toolkitIndependentBulk or world or plannedCraft or appliance(member)
        if not supported and not groupPreparation[member.Type]
            and member.Type ~= "ISInventoryTransferAction" then return "operation_dependent" end
        main = main or supported
        if supported then
            scrapOnly = scrapOnly and ((world and member.toolkitWorldDismantle)
                or (member.Type == "ISMoveablesAction" and member.mode == "scrap"))
        end
        output = output or member.toolkitIndependentBulk or auditedCraft or (world and member.toolkitWorldDismantle) or plannedCraft
            or (member.Type == "ISMoveablesAction" and member.mode == "scrap")
        for item in pairs(operationItems(member)) do inputs[item] = true end
    end
    if not main then return "operation_dependent" end
    if active then
        local current = queue.current
        if current.action and (current.action:finished() or current.action:isForceComplete()) then return "starting" end
        if stoppable(current) then
            if not current.action or not current.action:isStarted() then return "starting" end
        elseif not preparationCanFinish(current) then
            return "operation_active"
        end
    end
    for item in pairs(type(token) == "table" and token.toolkitPickups or {}) do inputs[itemKey(item)] = true end
    for i, other in ipairs(queue.queue) do
        if i < first or i > last then
            if other._isAddingActions or not knownCraftInputs(other) then return "operation_dependent" end
            for item in pairs(operationItems(other)) do
                if inputs[item] then return "operation_shared_item" end
            end
            for j = first, last do
                if sharedWorldTarget(queue.queue[j], other) then return "operation_dependent" end
            end
            -- shortcut: output requirements of arbitrary later actions are unknown; add verified adapters to allow them.
            if output and i > last then
                local independentCraft = craft(other) and knownCraftInputs(other)
                if ((other.onStartFunc or other.onCancelFunc) and not independentCraft) or other.retriggerLastAction
                    or (other.onCompleteFunc and other.onCompleteFunc ~= other.toolkitQueueSafeOnComplete and not independentCraft)
                    or (not independentCraft and not other.toolkitIndependentBulk and not other.toolkitBulkPreparation
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
    return completed(queue, action)
end

function Queue.moveReason(queue, action, target, after)
    if not Toolkit.Settings.actionQueue() or not queue or not live(queue)
        or queue:indexOf(action) == -1 or queue:indexOf(target or action) == -1 then return "unavailable" end
    if queue.toolkitCancel or queue.toolkitGroupCancel then return "stopping" end
    local first, last = Operations.bounds(queue, action)
    local targetFirst, targetLast = Operations.bounds(queue, target or action)
    if not first or not targetFirst then return "move_dependent" end
    for i = first, last do
        local member = queue.queue[i]
        if member.action or member == queue.current or i == 1 then return "move_active" end
        if member._isAddingActions then return "move_dependent" end
        if not knownCraftInputs(member) and not repairInputs(member) then
            return craft(member) and "move_craft_inputs" or "move_dependent"
        end
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
            if not knownCraftInputs(crossed) and not repairInputs(crossed) then
                return craft(crossed) and "move_craft_inputs" or "move_dependent"
            end
            for j = first, last do
                if sharedItem(queue.queue[j], crossed) then return "move_shared_item" end
                if not repairCanCross(queue.queue[j], crossed) or not repairCanCross(crossed, queue.queue[j]) then
                    return "move_craft_inputs"
                end
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

local completeAfterStop = ISTimedActionQueue.onCompleted
ISTimedActionQueue.onCompleted = function(queue, action)
    if queue.toolkitBuildWait and queue.toolkitCancel == action and queue.current == action and queue.queue[1] == action then
        -- Native perform can precede Java removal; the server's matching terminal still owns the outcome.
        queue.toolkitBuildWait.localCompleted = true
        return
    end
    return completeAfterStop(queue, action)
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
        and world and world.targetGone and world.targetGone(action) then
        local reason = Queue.cancelReason(queue, action)
        -- MP object removal can arrive before completion; native stop must not discard unrelated work.
        if not reason or reason == "starting" then queue.toolkitCancel = action end
    end
    if queue and queue.toolkitCancel == action and live(queue)
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
for _, methods in pairs(nativePreparation) do
    if methods.stop == stop then methods.stop = ISBaseTimedAction.stop end
end
for _, methods in pairs(repairIndependent) do
    if methods.stop == stop then methods.stop = ISBaseTimedAction.stop end
end

local reset = ISTimedActionQueue.resetQueue
ISTimedActionQueue.resetQueue = function(queue)
    if Toolkit.ActionQueueCraft and Toolkit.ActionQueueCraft.cancelQueue then Toolkit.ActionQueueCraft.cancelQueue(queue) end
    clearStop(queue)
    queue.toolkitGroupCancel = nil
    return reset(queue)
end

local clear = ISTimedActionQueue.clearQueue
ISTimedActionQueue.clearQueue = function(queue)
    if not queue:isCurrentActionAddingOtherActions() then
        if Toolkit.ActionQueueCraft and Toolkit.ActionQueueCraft.cancelQueue then Toolkit.ActionQueueCraft.cancelQueue(queue) end
        clearStop(queue)
        queue.toolkitGroupCancel = nil
    end
    return clear(queue)
end

local tick = ISTimedActionQueue.tick
ISTimedActionQueue.tick = function(queue)
    local action = queue.toolkitCancel
    if action then
        if not live(queue) or queue.current ~= action or queue.queue[1] ~= action then
            clearStop(queue)
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
