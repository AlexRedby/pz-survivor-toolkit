require "PZSurvivorToolkit/Settings"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISReadABook"
require "PZSurvivorToolkit/ActionQueueOperations"

local Toolkit = PZSurvivorToolkit
local Queue = {}
Toolkit.ActionQueue = Queue

local Operations = Toolkit.ActionQueueOperations

local function live(queue)
    local player = queue.character
    return player and getSpecificPlayer(player:getPlayerNum()) == player
        and not player:isDead() and not player:isAsleep()
end

local function stoppable(action)
    return action.Type == "ISReadABook" or (action.Type == "ISMoveablesAction" and action.mode == "scrap")
end

function Queue.cancelReason(queue, action)
    if not Toolkit.Settings.actionQueue() or not queue or not live(queue)
        or queue:indexOf(action) == -1 then return "unavailable" end
    if queue.toolkitCancel then return "stopping" end
    if action._isAddingActions or action.onCompleteFunc or action.onStartFunc or action.onCancelFunc
        or action.retriggerLastAction or action.toolkitQueueLinked then return "dependent" end
    if not stoppable(action) and not action.toolkitIndependentBulk and not action.toolkitWorldDismantle then
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
    if preempt and (not queue.current or queue.current.Type ~= "ISReadABook"
        or Queue.cancelReason(queue, queue.current)) then return "move_active" end
    if preempt then
        for i = first, last do
            local member = queue.queue[i]
            -- Native reading progress is shared by book type, including different copies.
            if member.Type == "ISReadABook" and member.item:getFullType() == queue.current.item:getFullType() then
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
                    -- A fresh native read obtains saved pages and MP duration through its constructor.
                    local resumed = ISReadABook:new(queue.character, action.item)
                    resumed.toolkitQueueOperation = action.toolkitQueueOperation
                    table.insert(queue.queue, index + 1, resumed)
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

function Queue.label(action)
    local title
    if action.toolkitWorldDismantle or (action.Type == "ISMoveablesAction" and action.mode == "scrap") then
        title = getText("ContextMenu_Disassemble")
        local name = action.toolkitWorldName or (action.moveProps and action.moveProps.name)
        if name then title = title .. ": " .. Translator.getMoveableDisplayName(name) end
    end
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

require "PZSurvivorToolkit/ActionQueueWorld"
return Queue
