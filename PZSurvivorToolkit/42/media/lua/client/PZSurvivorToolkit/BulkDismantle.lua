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
                    if luautils.haveToBeTransfered(player, item) then
                        local transfer = ISInventoryTransferUtil.newInventoryTransferAction(player,
                            item, item:getContainer(), player:getInventory())
                        -- Keep this guard when an ordinary pickup is already queued.
                        transfer:setOnComplete(function() end)
                        local stop = transfer.stop
                        transfer.stop = function(self)
                            -- B42 cancellation uses a client-local ID without an owner on the server.
                            if isClient() and self.transactionId ~= 0
                                and isItemTransactionRejected(self.transactionId)
                                and not isItemTransactionDone(self.transactionId) then
                                removeItemTransaction(self.transactionId, false)
                                self.transactionId = 0
                            end
                            return stop(self)
                        end
                        ISTimedActionQueue.add(transfer)
                    end
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

local function dismantleOptions(context, found)
    for _, option in ipairs(context.options) do
        if option.toolkitBulkDismantle or (option.onSelect == ISInventoryPaneContextMenu.OnNewCraft
            and option.param1 and recipes[option.param1:getName()]) then
            found[#found + 1] = {context = context, option = option}
        else
            local submenu = context:getSubMenu(option.subOption)
            if submenu then dismantleOptions(submenu, found) end
        end
    end
end

local function fillMenu(playerIndex, context, rows)
    if not Toolkit.Settings.bulkDismantle() then return end
    local player = getSpecificPlayer(playerIndex)
    if not player or player:isDead() then return end
    local entries = Bulk.entries(player, rows)
    if #entries < 2 then return end
    local found = {}
    dismantleOptions(context, found)
    if #found == 0 then
        -- Vanilla omits recipe actions for mixed item types; build the native one-item anchor.
        local available = ArrayList.new()
        available:add(entries[1].recipe)
        ISInventoryPaneContextMenu.addNewCraftingDynamicalContextMenu(entries[1].item,
            context, available, playerIndex, ISInventoryPaneContextMenu.getContainers(player))
        dismantleOptions(context, found)
    end
    for _, entry in ipairs(found) do
        local menu, option = entry.context, entry.option
        if not option.toolkitBulkDismantle then
            local submenu = menu:getSubMenu(option.subOption)
            if not submenu then
                submenu = menu:getNew(menu)
                local single = submenu:addOption(getText("UI_PZSurvivorToolkit_dismantle_one"),
                    option.target, option.onSelect, option.param1, option.param2, option.param3,
                    option.param4, option.param5, option.param6, option.param7, option.param8,
                    option.param9, option.param10)
                for _, key in ipairs({"iconTexture", "itemForTexture", "color", "toolTip", "notAvailable"}) do
                    single[key] = option[key]
                end
                option.onSelect = nil
                menu:addSubMenu(option, submenu)
            end
            option.toolkitBulkDismantle = true
            local bulk = submenu:addOption(getText("UI_PZSurvivorToolkit_dismantle_selected", #entries),
                player, Bulk.queue, entries)
            bulk.iconTexture = option.iconTexture
            bulk.itemForTexture = option.itemForTexture
            bulk.color = option.color
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(fillMenu)
