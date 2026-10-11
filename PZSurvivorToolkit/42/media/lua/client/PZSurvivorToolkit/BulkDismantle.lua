require "PZSurvivorToolkit/BulkActions"
require "ISUI/ISInventoryPaneContextMenu"
require "Entity/TimedActions/ISHandcraftAction"

local Toolkit = PZSurvivorToolkit
local Actions = Toolkit.BulkActions
local Bulk, Batteries = {}, {}
Toolkit.BulkDismantle = Bulk
Toolkit.BulkBatteries = Batteries

-- Only native single-item dismantling recipes; arbitrary crafts need their own selection rules.
local recipes = {
    DismantleElectronics = true,
    DismantleMiscElectronics = true,
    DismantleElectronicsDevice = true,
    DismantlePowerBar = true,
    DismantleImprovisedLighter = true,
}

local function inputFor(recipe, item)
    local found
    local battery = recipe:getName() == "RemoveBattery"
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if input:getResourceType() ~= ResourceType.Item then return end
        if battery or not input:isKeep() then
            if found or (battery and not input:isKeep())
                or (not battery and not input:isDestroy()) or input:getIntAmount() ~= 1
                or not input:containsItem(item:getScriptItem()) then return end
            found = input
        end
    end
    return found
end

local function prepare(player, item, recipe, containers)
    if not Actions.safeItem(player, item) then return end
    local input = inputFor(recipe, item)
    if not input then return end
    local logic = HandcraftLogic.new(player, nil, nil)
    logic:setContainers(containers)
    logic:setRecipeFromContextClick(recipe, item)
    local exact = ArrayList.new()
    exact:add(item)
    if not logic:setManualInputsFor(input, exact) then return end
    local bound = logic:getManualInputsFor(input, ArrayList.new())
    if bound:size() ~= 1 or bound:get(0) ~= item or not logic:canPerformCurrentRecipe() then return end
    return logic
end

local function entries(player, rows, allowed)
    local entries = {}
    local containers = ISInventoryPaneContextMenu.getContainers(player)
    for _, item in ipairs(Actions.selectedItems(rows)) do
        if Actions.safeItem(player, item) then
            local available = CraftRecipeManager.getUniqueRecipeItems(item, player, containers)
            for i = 0, (available and available:size() or 0) - 1 do
                local recipe = available:get(i)
                if recipe and allowed[recipe:getName()] and prepare(player, item, recipe, containers) then
                    entries[#entries + 1] = {item = item, recipe = recipe}
                    break
                end
            end
        end
    end
    return entries
end

local function queue(player, entries, enabled)
    if not enabled() or not player or player:isDead() then return end
    local containers = ISInventoryPaneContextMenu.getContainers(player)
    local moved, returnItems = {}, {}
    local count = 0
    for _, entry in ipairs(entries) do
        local logic = prepare(player, entry.item, entry.recipe, containers)
        if logic then
            local action = ISHandcraftAction.FromLogic(logic)
            local id = entry.item:getID()
            -- MP removes consumed inputs before client completion; check only before starting.
            action.isValidStart = function(self)
                local item = self.character:getInventory():getItemById(id)
                return Actions.safeItem(self.character, item) and self:isValid()
            end
            local inputs = logic:getRecipeData():getAllInputItems()
            local kept = logic:getRecipeData():getAllPutBackInputItems()
            for i = 0, inputs:size() - 1 do
                local item = inputs:get(i)
                if item:getContainer() ~= player:getInventory() and not moved[item:getID()] then
                    moved[item:getID()] = true
                    Actions.transfer(player, item)
                    if kept:contains(item) then returnItems[#returnItems + 1] = item end
                end
            end
            ISTimedActionQueue.add(action)
            count = count + 1
        end
    end
    ISCraftingUI.ReturnItemsToOriginalContainer(player, returnItems)
    return count
end

function Bulk.entries(player, rows)
    return entries(player, rows, recipes)
end

function Bulk.queue(player, selected)
    return queue(player, selected, Toolkit.Settings.bulkDismantle)
end

local batteryRecipes = {RemoveBattery = true}

function Batteries.entries(player, rows)
    return entries(player, rows, batteryRecipes)
end

function Batteries.queue(player, selected)
    return queue(player, selected, Toolkit.Settings.bulkRemoveBatteries)
end

local function recipeOptions(context, allowed, found)
    for _, option in ipairs(context.options) do
        if option.toolkitBulkRecipe and allowed[option.toolkitBulkRecipe]
            or (option.onSelect == ISInventoryPaneContextMenu.OnNewCraft
                and option.param1 and allowed[option.param1:getName()]) then
            found[#found + 1] = {context = context, option = option}
        else
            local submenu = context:getSubMenu(option.subOption)
            if submenu then recipeOptions(submenu, allowed, found) end
        end
    end
end

local function fillRecipeMenu(playerIndex, context, rows, allowed, api, enabled, oneKey, selectedKey)
    if not enabled() then return end
    local player = getSpecificPlayer(playerIndex)
    if not player or player:isDead() then return end
    local selected = api.entries(player, rows)
    if #selected < 2 then return end
    local found = {}
    recipeOptions(context, allowed, found)
    if #found == 0 then
        -- Vanilla omits recipe actions for mixed item types; build the native one-item anchor.
        local available = ArrayList.new()
        available:add(selected[1].recipe)
        ISInventoryPaneContextMenu.addNewCraftingDynamicalContextMenu(selected[1].item,
            context, available, playerIndex, ISInventoryPaneContextMenu.getContainers(player))
        recipeOptions(context, allowed, found)
    end
    for _, entry in ipairs(found) do
        local menu, option = entry.context, entry.option
        if not option.toolkitBulkRecipe then
            option.toolkitBulkRecipe = option.param1:getName()
            local submenu = Actions.submenu(menu, option, getText(oneKey))
            local bulk = submenu:addOption(getText(selectedKey, #selected), player, api.queue, selected)
            bulk.iconTexture = option.iconTexture
            bulk.itemForTexture = option.itemForTexture
            bulk.color = option.color
        end
    end
end

local function fillMenu(playerIndex, context, rows)
    fillRecipeMenu(playerIndex, context, rows, recipes, Bulk, Toolkit.Settings.bulkDismantle,
        "UI_PZSurvivorToolkit_dismantle_one", "UI_PZSurvivorToolkit_dismantle_selected")
    fillRecipeMenu(playerIndex, context, rows, batteryRecipes, Batteries, Toolkit.Settings.bulkRemoveBatteries,
        "UI_PZSurvivorToolkit_action_one", "UI_PZSurvivorToolkit_remove_batteries_selected")
end

Events.OnFillInventoryObjectContextMenu.Add(fillMenu)
