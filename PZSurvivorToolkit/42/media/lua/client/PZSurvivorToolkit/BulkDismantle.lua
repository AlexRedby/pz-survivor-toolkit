require "PZSurvivorToolkit/Settings"
require "ISUI/ISInventoryPaneContextMenu"
require "Entity/TimedActions/ISHandcraftAction"

local Toolkit = PZSurvivorToolkit
local Bulk = {}
Toolkit.BulkDismantle = Bulk

-- Only native single-item dismantling recipes; arbitrary crafts need their own selection rules.
local recipes = {
    DismantleElectronics = true,
    DismantleMiscElectronics = true,
    DismantleElectronicsDevice = true,
    DismantlePowerBar = true,
    DismantleImprovisedLighter = true,
}

local function safeItem(player, item)
    return item and item:getContainer() and not item:isFavorite()
        and not player:isEquippedClothing(item)
        and player:getPrimaryHandItem() ~= item and player:getSecondaryHandItem() ~= item
end

local function selectedItems(rows)
    local items, seen = {}, {}
    local function add(item)
        if not instanceof(item, "InventoryItem") then return end
        local id = item:getID()
        if not seen[id] then
            seen[id] = true
            items[#items + 1] = item
        end
    end
    for _, row in ipairs(rows) do
        if instanceof(row, "InventoryItem") then add(row)
        elseif row.items then
            -- Native groups duplicate the first item; CleanUI virtual groups do not.
            for _, item in ipairs(row.items) do add(item) end
        end
    end
    return items
end

local function inputFor(recipe, item)
    local found
    local inputs = recipe:getInputs()
    for i = 0, inputs:size() - 1 do
        local input = inputs:get(i)
        if input:getResourceType() ~= ResourceType.Item then return end
        if not input:isKeep() then
            if found or not input:isDestroy() or input:getIntAmount() ~= 1
                or not input:containsItem(item:getScriptItem()) then return end
            found = input
        end
    end
    return found
end

local function prepare(player, item, recipe, containers)
    if not safeItem(player, item) then return end
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

function Bulk.entries(player, rows)
    local entries = {}
    local containers = ISInventoryPaneContextMenu.getContainers(player)
    for _, item in ipairs(selectedItems(rows)) do
        if safeItem(player, item) then
            local available = CraftRecipeManager.getUniqueRecipeItems(item, player, containers)
            for i = 0, (available and available:size() or 0) - 1 do
                local recipe = available:get(i)
                if recipe and recipes[recipe:getName()] and prepare(player, item, recipe, containers) then
                    entries[#entries + 1] = {item = item, recipe = recipe}
                    break
                end
            end
        end
    end
    return entries
end

function Bulk.queue(player, entries)
    if not Toolkit.Settings.bulkDismantle() or not player or player:isDead() then return end
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
                return safeItem(self.character, item) and self:isValid()
            end
            local inputs = logic:getRecipeData():getAllInputItems()
            local kept = logic:getRecipeData():getAllPutBackInputItems()
            for i = 0, inputs:size() - 1 do
                local item = inputs:get(i)
                if item:getContainer() ~= player:getInventory() and not moved[item:getID()] then
                    moved[item:getID()] = true
                    ISInventoryPaneContextMenu.transferIfNeeded(player, item)
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

local function fillMenu(playerIndex, context, rows)
    if not Toolkit.Settings.bulkDismantle() then return end
    local player = getSpecificPlayer(playerIndex)
    if not player or player:isDead() then return end
    local entries = Bulk.entries(player, rows)
    if #entries < 2 then return end
    local option = context:addOption(getText("UI_PZSurvivorToolkit_dismantle_selected", #entries),
        player, Bulk.queue, entries)
    option.iconTexture = getTexture("Item_Screwdriver")
end

Events.OnFillInventoryObjectContextMenu.Add(fillMenu)
