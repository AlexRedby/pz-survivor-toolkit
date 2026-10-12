require "PZSurvivorToolkit/Settings"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISBaseTimedAction"

local Toolkit = PZSurvivorToolkit
local Queue = {}
Toolkit.ActionQueue = Queue

local addAfter = ISTimedActionQueue.addAfter
ISTimedActionQueue.addAfter = function(previous, action)
    local queue, added = addAfter(previous, action)
    if added then
        -- Kahlua ignores weak-table modes; mark linked steps without retaining completed actions.
        previous.toolkitQueueLinked, added.toolkitQueueLinked = true, true
    end
    return queue, added
end

local function live(queue)
    local player = queue.character
    return player and getSpecificPlayer(player:getPlayerNum()) == player
        and not player:isDead() and not player:isAsleep()
end

function Queue.cancelReason(queue, action)
    if not Toolkit.Settings.actionQueue() or not queue or not live(queue)
        or queue:indexOf(action) == -1 then return "unavailable" end
    if queue.toolkitCancel then return "stopping" end
    if action._isAddingActions or action.onCompleteFunc or action.onStartFunc or action.onCancelFunc
        or action.retriggerLastAction or action.toolkitQueueLinked then return "dependent" end
    if action.Type ~= "ISReadABook" and not action.toolkitIndependentBulk then
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
        -- Only reading has an audited stop path without item transactions or craft callbacks.
        if action.Type ~= "ISReadABook" then return "active" end
        if not action:isStarted() or action.action:finished() or action.action:isForceComplete() then
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

local stop = ISBaseTimedAction.stop
ISBaseTimedAction.stop = function(action)
    local queue = ISTimedActionQueue.queues[action.character]
    if queue and queue.toolkitCancel == action and live(queue)
        and not action.character:isPlayerMoving() and not action.character:pressedMovement(false) then
        queue.toolkitCancelStopped = true
        action.character:setIsFarming(false)
        return
    end
    if queue then queue.toolkitCancel, queue.toolkitCancelStopped = nil, nil end
    return stop(action)
end

local tick = ISTimedActionQueue.tick
ISTimedActionQueue.tick = function(queue)
    local action = queue.toolkitCancel
    if action then
        if not live(queue) or queue.current ~= action or queue.queue[1] ~= action then
            queue.toolkitCancel, queue.toolkitCancelStopped = nil, nil
        elseif not queue.character:getCharacterActions():contains(action.action) then
            -- B42 sends the MP stop packet after Lua stop; resume only after Java removes the action.
            local stopped = queue.toolkitCancelStopped
            queue.toolkitCancel, queue.toolkitCancelStopped = nil, nil
            if stopped then queue:onCompleted(action); return end
        else
            return
        end
    end
    return tick(queue)
end

function Queue.label(action)
    local title
    if action.Type == "ISReadABook" then title = getText("ContextMenu_Read") end
    if action.craftRecipe and instanceof(action.craftRecipe, "CraftRecipe") then
        title = action.craftRecipe:getTranslationName()
    end
    if action.Type == "ISInventoryTransferAction" then title = getText("IGUI_MovingToContainer") end
    title = title or tostring(action.Type or "?"):gsub("^IS", ""):gsub("(%l)(%u)", "%1 %2")
    local item = action.item or action.gun or action.magazine or action.weapon
    if item and instanceof(item, "InventoryItem") then title = title .. ": " .. item:getDisplayName() end
    return title
end

return Queue
