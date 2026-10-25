local Refill = require "PZSurvivorToolkit/TorchRefill"
local Operations = require "PZSurvivorToolkit/ActionQueueOperations"
require "Entity/TimedActions/ISHandcraftAction"
require "ISUI/ISCraftingUI"
local Return = {}
local pending = {}

local function active(entry)
    return not entry.player:isDead() and ISTimedActionQueue.queues[entry.player] == entry.queue
        and entry.queue:indexOf(entry.wait) ~= -1
        and not (entry.wait.toolkitQueueOperation and entry.wait.toolkitQueueOperation.toolkitCancelled)
end

local function ready(player, entry)
    if not active(entry) then return true end
    entry.deadline = entry.deadline or getTimestampMs() + 30000
    if entry.outputID and player:getInventory():getItemById(entry.outputID) then return true end
    return not isClient() or getTimestampMs() >= entry.deadline
end

local function putBack(player, entry)
    pending[entry] = nil
    local item = entry.outputID and player:getInventory():getItemById(entry.outputID)
    if not active(entry) or not item or item:getFullType() ~= "Base.BlowTorch"
        or item:getContainer() ~= player:getInventory() then return end
    ISCraftingUI.ReturnItemToContainer(player, item, entry.source)
end

Refill.onRefilled = function(player, args)
    for entry in pairs(pending) do
        if active(entry) and entry.player == player and args.sourceID == entry.id
            and type(args.outputID) == "number" and args.outputID == math.floor(args.outputID)
            and args.outputID ~= entry.id and not entry.outputID then
            entry.outputID = args.outputID
            return
        end
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= Refill.MODULE or command ~= "Refilled" or type(args) ~= "table"
        or type(args.onlineID) ~= "number" then return end
    local player = getPlayerByOnlineID(args.onlineID)
    if player and getSpecificPlayer(player:getPlayerNum()) == player then Refill.onRefilled(player, args) end
end)
Events.OnTick.Add(function()
    for entry in pairs(pending) do if not active(entry) then pending[entry] = nil end end
end)

local function usesSelected(action, entry)
    if action.Type ~= "ISHandcraftAction" or action.character ~= entry.player or action.craftRecipe ~= entry.recipe
        or type(action.manualInputs) ~= "table" then return false end
    local found = 0
    for _, items in pairs(action.manualInputs) do
        for i = 0, items:size() - 1 do
            if items:get(i):getID() == entry.id then found = found + 1 end
        end
    end
    return found == 1
end

-- Native crafting queues a return for the destroyed input too. In Host its
-- crafting-consumed flag makes that transfer invalid even with allowMissingItems,
-- cancelling the tank return behind it. Replace only this exact pending return.
local function sourceReturn(action, entry, token)
    if action.Type ~= "ISInventoryTransferAction" or action.character ~= entry.player
        or action.toolkitQueueOperation ~= token
        or not action.item or action.item:getID() ~= entry.id or not action.allowMissingItems
        or action.srcContainer ~= entry.player:getInventory() or action.destContainer ~= entry.source
        or action.onStartFunc or action.onCompleteFunc or action.onCancelFunc then return false end
    local list = action.queueList
    return type(list) == "table" and #list == 1 and type(list[1].items) == "table"
        and #list[1].items == 1 and list[1].items[1] == action.item
end

function Return.install()
    if Return.wrapper then return ISInventoryPaneContextMenu.OnNewCraft == Return.wrapper end
    local native = ISInventoryPaneContextMenu.OnNewCraft
    Return.wrapper = function(selectedItem, recipe, playerNum, all, ...)
        local player = getSpecificPlayer(playerNum)
        local source = selectedItem and selectedItem:getContainer()
        if all or not player or not source or source == player:getInventory()
            or selectedItem:getFullType() ~= "Base.BlowTorch" or not Refill.supports(recipe)
            or player:hasTrait(CharacterTrait.DISORGANIZED) then
            return native(selectedItem, recipe, playerNum, all, ...)
        end
        return Operations.run(function(...)
            local queue = ISTimedActionQueue.getTimedActionQueue(player)
            -- Initialize native/disabled-mode bookkeeping before the first pickup
            -- can begin and invalidate a newly captured operation token.
            local owner = PZSurvivorToolkit.ActionQueue
            if owner and owner.updateOperationState then owner.updateOperationState(queue) end
            local existing = {}
            for _, action in ipairs(queue.queue) do existing[action] = true end
            local result = native(selectedItem, recipe, playerNum, all, ...)
            local entry = {player = player, source = source, id = selectedItem:getID(), recipe = recipe, queue = queue}
            local craft
            for _, action in ipairs(queue.queue) do
                if not existing[action] and usesSelected(action, entry) then
                    if craft then return result end
                    craft = action
                end
            end
            if not craft then return result end
            entry.wait = Operations.command(player, putBack, entry, {ready = ready, fields = {item = selectedItem}})
            -- Share the native operation's cancellation boundary, including with queue UI disabled.
            entry.wait.toolkitQueueOperation = craft.toolkitQueueOperation
            local returnIndex
            for index = queue:indexOf(craft) + 1, #queue.queue do
                local action = queue.queue[index]
                if not existing[action] and sourceReturn(action, entry, craft.toolkitQueueOperation) then
                    if returnIndex then return result end
                    returnIndex = index
                end
            end
            pending[entry] = true
            if returnIndex then
                -- One-for-one substitution preserves native deferred insertion counts.
                Operations.adopt(entry.wait, craft.toolkitQueueOperation)
                queue.queue[returnIndex] = entry.wait
                Operations.invalidateTitle(craft)
            else
                ISTimedActionQueue.add(entry.wait)
            end
            return result
        end, ...)
    end
    ISInventoryPaneContextMenu.OnNewCraft = Return.wrapper
    return true
end
Events.OnGameStart.Add(Return.install)
return Return
