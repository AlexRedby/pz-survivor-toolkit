require "PZSurvivorToolkit/BulkActions"
require "PZSurvivorToolkit/ActionQueue"
require "TimedActions/ISEatFoodAction"
require "TimedActions/ISWearClothing"

local Toolkit = PZSurvivorToolkit
local Actions, Operations = Toolkit.BulkActions, Toolkit.ActionQueueOperations
local Bulk = {}
Toolkit.BulkFood = Bulk
local commands, meals, cleanup, removals = {}, {}, {}, {}
local registries = {commands, meals, cleanup, removals}
local function portion(value) return value == 1 or value == 0.5 or value == 0.25 end

function Bulk.prune()
    local pending = false
    for _, registry in ipairs(registries) do
        for _ in pairs(registry) do pending = true; break end
        if pending then break end
    end
    if not pending then return end
    local queued = {}
    for _, queue in pairs(ISTimedActionQueue.queues) do
        for _, action in ipairs(queue.queue or {}) do queued[action] = true end
    end
    for _, registry in ipairs(registries) do
        for action in pairs(registry) do if not queued[action] then registry[action] = nil end end
    end
end
Events.OnTick.Add(Bulk.prune)

local function edible(item)
    if not item or item:getCategory() ~= "Food" or item:getHungChange() >= 0 or item:isFavorite() then return false end
    local script, custom, required = item:getScriptItem(), item:getCustomMenuOption(), item:getRequireInHandOrInventory()
    -- Opening, smoking and tool-dependent foods keep their native single-item commands.
    return not script:isCantEat() and not script:getOpeningRecipe()
        and (not custom or custom == "" or custom == getText("ContextMenu_Eat"))
        and (not required or required:isEmpty())
end

local function available(player, item, containers)
    local source = item and item:getContainer()
    return source and source:getItemById(item:getID()) ~= nil
        and (source == player:getInventory() or containers:contains(source))
end

function Bulk.isCommand(action)
    local entry = commands[action]
    return entry ~= nil and Operations.isCommand(action) and action.item == entry.item
        and action.item:getID() == entry.id
end

function Bulk.isEat(action)
    local entry = meals[action]
    return entry ~= nil and action.Type == "ISEatFoodAction" and action.item
        and action.item:getID() == entry.id and action.percentage == entry.percentage
end

function Bulk.isCleanup(action)
    local entry = cleanup[action]
    return entry ~= nil and action.Type == "ISWearClothing" and action.character == entry.player
        and action.item and action.item:getID() == entry.maskId
end

function Bulk.isMaskRemoval(action)
    local entry = removals[action]
    return entry ~= nil and action.Type == "ISUnequipAction"
        and action.character == entry.player and action.item and action.item:getID() == entry.maskId
end

function Bulk.retainCleanup(action, current, queue)
    local entry = cleanup[action]
    if not Bulk.isCleanup(action) or not Toolkit.ActionQueuePolicy.inspect(action) then return false end
    -- Keep restoration only when removal has already run or is the step being finished.
    if entry.unequip ~= current and queue:indexOf(entry.unequip) ~= -1 then return false end
    entry.retained = true
    return true
end

local function installCleanupContract()
    if not Toolkit.ActionQueuePolicy then return end
    Toolkit.ActionQueuePolicy.registerNative("ISWearClothing", function(action)
        if not Bulk.isCleanup(action) then return end
        return {items = {[action.item:getID()] = true}, itemTypes = {[action.item:getFullType()] = true},
            targets = {}, hands = action.character, preparationFinish = true, cancelWaiting = true,
            cancelOperation = not cleanup[action].retained, interrupt = "finish-step"}
    end)
end
installCleanupContract()
Events.OnGameStart.Add(installCleanupContract)

function Bulk.missing(action)
    if not (Bulk.isEat(action) or Bulk.isCleanup(action)) or not Toolkit.ActionQueuePolicy.inspect(action) then return false end
    local inventory = action.character:getInventory()
    if isClient() then return not inventory:containsID(action.item:getID()) end
    return not inventory:contains(action.item)
end

function Bulk.skipUnavailable(queue)
    local action = queue.queue[2]
    -- Preparation may outlive the item or change satiety; preserve its native cleanup actions.
    while action and not action.action and (Bulk.isEat(action) or Bulk.isCleanup(action)) and Toolkit.ActionQueuePolicy.inspect(action)
        and ((Bulk.isEat(action) and (Bulk.missing(action) or action.character:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN) >= 3))
            or (Bulk.isCleanup(action) and (Bulk.missing(action) or action.item:isBroken()))) do
        table.remove(queue.queue, 2)
        action:forceCancel()
        if Bulk.isEat(action) then Toolkit.ActionQueueBatch.discard(action) end
        action = queue.queue[2]
    end
end

local function reserved(player)
    local used = {}
    local queue = ISTimedActionQueue.queues[player]
    for _, action in ipairs(queue and queue.queue or {}) do
        if action.item and (action.Type == "ISEatFoodAction" or Bulk.isCommand(action)) then
            used[action.item:getID()] = true
        end
    end
    return used
end

function Bulk.entries(player, rows)
    local result, used = {}, reserved(player)
    local containers = ISInventoryPaneContextMenu.getContainers(player)
    for _, item in ipairs(Actions.selectedItems(rows)) do
        if not used[item:getID()] and edible(item) and available(player, item, containers) then
            result[#result + 1] = item
        end
    end
    return result
end

local function dispatch(player, entry)
    local item = player:getInventory():getItemById(entry.id) or entry.source:getItemById(entry.id)
    local container = item and item:getContainer()
    if player:isDead() or not edible(item)
        or (container ~= entry.source and container ~= player:getInventory())
        or not available(player, item, ISInventoryPaneContextMenu.getContainers(player))
        or player:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN) >= 3 then
        Toolkit.ActionQueueBatch.discard(entry.command)
        return
    end
    local add = ISTimedActionQueue.add
    ISTimedActionQueue.add = function(action)
        if action.character == player and action.Type == "ISEatFoodAction"
            and action.item == item and action.percentage == entry.percentage then meals[action] = entry end
        if action.character == player and action.Type == "ISUnequipAction" then
            entry.unequip, entry.maskId = action, action.item:getID()
            removals[action] = {player = player, maskId = entry.maskId}
        elseif action.character == player and action.Type == "ISWearClothing" and entry.unequip
            and action.item == entry.unequip.item then cleanup[action] = entry end
        if action.character == player and action.Type == "ISInventoryTransferAction"
            and not action.toolkitTransferGuard and not action.onCompleteFunc then Actions.guardTransfer(action) end
        return add(action)
    end
    -- Keep the game's mask, utensil, transfer and return handling, including mod integrations.
    local ok, err = pcall(ISInventoryPaneContextMenu.eatItem, item, entry.percentage, player:getPlayerNum())
    ISTimedActionQueue.add = add
    if not ok then error(err, 0) end
end

function Bulk.queue(player, selected, percentage)
    percentage = percentage or 1
    if not portion(percentage) then return 0 end
    if not Toolkit.Settings.actionQueue() or not player or player:isDead() then return 0 end
    local items = Bulk.entries(player, selected)
    return Operations.run(function()
        for _, item in ipairs(items) do
            local entry = {item = item, id = item:getID(), source = item:getContainer(), player = player, percentage = percentage}
            local command = Operations.command(player, dispatch, entry, {fields = {item = item}})
            entry.command, commands[command] = command, entry
            ISTimedActionQueue.add(command)
        end
        return #items
    end)
end

function Bulk.queueOne(rows, percentage, playerIndex, openingRecipe, eatPercentage)
    if not Toolkit.Settings.actionQueue() or not portion(percentage) or openingRecipe then
        return ISInventoryPaneContextMenu.onEatItems(rows, percentage, playerIndex, openingRecipe, eatPercentage)
    end
    local player = getSpecificPlayer(playerIndex)
    if not player or player:isDead() then return 0 end
    local selected = Bulk.entries(player, rows)
    return selected[1] and Bulk.queue(player, {selected[1]}, percentage) or 0
end

local function eatMenu(context)
    for _, option in ipairs(context.options) do
        if option.toolkitBulkFood then return context, option end
        if option.onSelect == ISInventoryPaneContextMenu.onEatItems
            and option.param1 == 1 and not option.param3 and not option.ES_EatSmart then return context, option end
        local submenu = context:getSubMenu(option.subOption)
        if submenu then
            local menu, found = eatMenu(submenu)
            if found then return menu, found end
        end
    end
end

local function fillMenu(playerIndex, context, rows)
    if not Toolkit.Settings.actionQueue() then return end
    local player = getSpecificPlayer(playerIndex)
    if not player or player:isDead() then return end
    local menu, option = eatMenu(context)
    if not option or option.toolkitBulkFood then return end
    if not edible(Actions.selectedItems(rows)[1]) then return end
    local selected = Bulk.entries(player, rows)
    local labels = {[1] = "eat_selected", [0.5] = "eat_selected_half", [0.25] = "eat_selected_quarter"}
    local count = #menu.options
    for i = 1, count do
        local native = menu.options[i]
        local percentage = native.param1
        -- Eat Smart computes its own first-item portion; its public callback remains untouched.
        if native.onSelect == ISInventoryPaneContextMenu.onEatItems and portion(percentage)
            and not native.param3 and not native.ES_EatSmart then
            native.toolkitBulkFood, native.toolkitOriginalOnSelect = true, native.onSelect
            native.onSelect = Bulk.queueOne
            if #selected == 0 then native.notAvailable = true end
            if #selected >= 2 then
                local bulk = menu:addOption(getText("UI_PZSurvivorToolkit_" .. labels[percentage], #selected), player, Bulk.queue, selected, percentage)
                bulk.itemForTexture = selected[1]
                bulk.toolTip = ISInventoryPaneContextMenu.addToolTip()
                bulk.toolTip.description = getText("UI_PZSurvivorToolkit_eat_selected_tooltip")
            end
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(fillMenu)

return Bulk
