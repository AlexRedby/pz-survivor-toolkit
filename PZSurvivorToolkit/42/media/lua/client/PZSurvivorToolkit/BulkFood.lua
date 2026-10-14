require "PZSurvivorToolkit/BulkActions"
require "PZSurvivorToolkit/ActionQueue"
require "TimedActions/ISEatFoodAction"

local Toolkit = PZSurvivorToolkit
local Actions, Operations = Toolkit.BulkActions, Toolkit.ActionQueueOperations
local Bulk = {}
Toolkit.BulkFood = Bulk
local commands, meals = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})

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
        and action.item:getID() == entry.id and action.percentage == 1
end

function Bulk.missing(action)
    if not Bulk.isEat(action) or not Toolkit.ActionQueuePolicy.inspect(action) then return false end
    local inventory = action.character:getInventory()
    if isClient() then return not inventory:containsID(action.item:getID()) end
    return not inventory:contains(action.item)
end

function Bulk.skipUnavailable(queue)
    local action = queue.queue[2]
    -- Preparation may outlive the item or change satiety; preserve its native cleanup actions.
    while action and not action.action and Bulk.isEat(action) and Toolkit.ActionQueuePolicy.inspect(action)
        and (Bulk.missing(action) or action.character:getMoodles():getMoodleLevel(MoodleType.FOOD_EATEN) >= 3) do
        table.remove(queue.queue, 2)
        action:forceCancel()
        Toolkit.ActionQueueBatch.discard(action)
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
            and action.item == item and action.percentage == 1 then meals[action] = entry end
        if action.character == player and action.Type == "ISInventoryTransferAction"
            and not action.toolkitTransferGuard and not action.onCompleteFunc then Actions.guardTransfer(action) end
        return add(action)
    end
    -- Keep the game's mask, utensil, transfer and return handling, including mod integrations.
    local ok, err = pcall(ISInventoryPaneContextMenu.eatItem, item, 1, player:getPlayerNum())
    ISTimedActionQueue.add = add
    if not ok then error(err, 0) end
end

function Bulk.queue(player, selected)
    if not Toolkit.Settings.actionQueue() or not player or player:isDead() then return 0 end
    local items = Bulk.entries(player, selected)
    return Operations.run(function()
        for _, item in ipairs(items) do
            local entry = {item = item, id = item:getID(), source = item:getContainer()}
            local command = Operations.command(player, dispatch, entry, {fields = {item = item}})
            entry.command, commands[command] = command, entry
            ISTimedActionQueue.add(command)
        end
        return #items
    end)
end

function Bulk.queueOne(rows, percentage, playerIndex, openingRecipe, eatPercentage)
    if not Toolkit.Settings.actionQueue() then
        return ISInventoryPaneContextMenu.onEatItems(rows, percentage, playerIndex, openingRecipe, eatPercentage)
    end
    local player = getSpecificPlayer(playerIndex)
    if not player or player:isDead() then return 0 end
    local selected = Bulk.entries(player, rows)
    return selected[1] and Bulk.queue(player, {selected[1]}) or 0
end

local function eatMenu(context)
    for _, option in ipairs(context.options) do
        if option.toolkitBulkFood then return context, option end
        if option.onSelect == ISInventoryPaneContextMenu.onEatItems
            and option.param1 == 1 and not option.param3 then return context, option end
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
    -- Only the native full-portion option: Eat Smart computes its own first-item portion.
    option.toolkitBulkFood, option.toolkitOriginalOnSelect = true, option.onSelect
    option.onSelect = Bulk.queueOne
    if #selected == 0 then option.notAvailable = true end
    if #selected < 2 then return end
    local bulk = menu:addOption(getText("UI_PZSurvivorToolkit_eat_selected", #selected), player, Bulk.queue, selected)
    bulk.itemForTexture = selected[1]
    bulk.toolTip = ISInventoryPaneContextMenu.addToolTip()
    bulk.toolTip.description = getText("UI_PZSurvivorToolkit_eat_selected_tooltip")
end

Events.OnFillInventoryObjectContextMenu.Add(fillMenu)

return Bulk
