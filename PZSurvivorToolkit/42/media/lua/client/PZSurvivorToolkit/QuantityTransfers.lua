require "PZSurvivorToolkit/BulkActions"
require "PZSurvivorToolkit/InventoryTransferProtection"
local Membership = require "PZSurvivorToolkit/InventoryMembership"
require "ISUI/ISTextBox"
if getActivatedMods():contains("TakeAnyAmount") then return end

local Toolkit = PZSurvivorToolkit
local Protection = Toolkit.InventoryTransferProtection
local Quantity = {}
Toolkit.QuantityTransfers = Quantity

function Quantity.parse(text, maximum)
    local value = tonumber(text)
    if type(value) == "number" and value >= 1 and value <= maximum and value == math.floor(value) then
        return value
    end
end

local function eligible(player, item, destination, containers, membership)
    local source = item:getContainer()
    if not source or source == destination or isForceDropHeavyItem(item) then return false end
    local acceptCallback = destination.getAcceptItemFunction and destination:getAcceptItemFunction()
    local allowed = destination:isItemAllowed(item)
    -- Admission may re-enter getContainers, rewrite its reused list and clear its own callback.
    -- Invalidate even when admission rejects this item; later items must see the rewrite.
    local reachableIndex = membership
    if acceptCallback or destination.getAcceptItemFunction and destination:getAcceptItemFunction() then
        if membership then membership.containerList = nil end
        reachableIndex = nil
    end
    if not allowed or item:isFavorite() or player:isEquipped(item) then return false end
    if source:isInCharacterInventory(player) or Membership.containsContainer(reachableIndex, containers, source) then return true end
    -- Proximity views can expose actual items through a virtual container.
    for i = 0, containers:size() - 1 do
        if Membership.contains(membership, containers:get(i), item) then return true end
    end
    return false
end

function Quantity.snapshot(playerNum, rows, destination, grab)
    local player = getSpecificPlayer(playerNum)
    if not player or player:isDead() or not destination then return end
    local containers = ISInventoryPaneContextMenu.getContainers(player)
    local membership = {}
    local selection = {player = player, playerNum = playerNum, destination = destination,
        grab = grab, items = {}, sources = {}, allowsStuck = Protection.selectionAllowsStuck(rows)}
    for _, item in ipairs(Toolkit.BulkActions.selectedItems(rows)) do
        if eligible(player, item, destination, containers, membership)
            and (selection.allowsStuck or Protection.allowsAutomatic(item))
            and (grab or item:getContainer():isInCharacterInventory(player)) then
            selection.items[#selection.items + 1] = item
            selection.sources[item] = item:getContainer()
        end
    end
    return selection
end

function Quantity.transfer(selection, text)
    if not Toolkit.Settings.quantityTransfers() or not selection then return end
    local player = getSpecificPlayer(selection.playerNum)
    local limit = Quantity.parse(text, #selection.items)
    if not limit or player ~= selection.player or player:isDead() then return end
    local containers = ISInventoryPaneContextMenu.getContainers(player)
    local membership = {}
    if not selection.destination:isInCharacterInventory(player)
        and not Membership.containsContainer(membership, containers, selection.destination) then return end
    local items = {}
    for _, item in ipairs(selection.items) do
        if #items >= limit then break end
        if item:getContainer() == selection.sources[item]
            and (selection.allowsStuck or Protection.allowsAutomatic(item))
            and eligible(player, item, selection.destination, containers, membership) then
            items[#items + 1] = item
        end
    end
    if #items == 0 then return 0 end
    if selection.grab and not luautils.walkToContainer(items[1]:getContainer(), selection.playerNum) then return 0 end
    -- A virtual row can span real containers. Once flattened, the owner's live
    -- callback would mistake that explicit row for a mass selection.
    local individual = selection.allowsStuck and not Protection.selectionAllowsStuck(items)
    if individual then
        individual = false
        for _, item in ipairs(items) do
            if not Protection.allowsAutomatic(item) then individual = true; break end
        end
    end
    local walk = luautils.walkToContainer
    local transfer = ISInventoryTransferUtil.newInventoryTransferAction
    -- A rejected pickup must not cancel another client's same-numbered transaction.
    ISInventoryTransferUtil.newInventoryTransferAction = function(...)
        return Toolkit.BulkActions.guardTransfer(transfer(...))
    end
    if individual then
        local checked, allowed = false, nil
        luautils.walkToContainer = function(container, playerNum, ...)
            if container ~= selection.destination or playerNum ~= selection.playerNum then
                return walk(container, playerNum, ...)
            end
            -- Native crate walking clears the queue: perform it once for this command.
            if not checked then
                checked = true
                allowed = walk(container, playerNum, ...)
            end
            return allowed
        end
    end
    local ok, err = pcall(function()
        if individual then
            for _, item in ipairs(items) do
                ISInventoryPaneContextMenu.onMoveItemsTo({item}, selection.destination, selection.playerNum)
            end
        else
            ISInventoryPaneContextMenu.onMoveItemsTo(items, selection.destination, selection.playerNum)
        end
    end)
    ISInventoryTransferUtil.newInventoryTransferAction = transfer
    if individual then luautils.walkToContainer = walk end
    if not ok then error(err) end
    return #items
end

local function accept(_, button, selection)
    if button.internal ~= "OK" then return end
    local modal, text = button.parent, button.parent.entry:getText()
    if not Quantity.parse(text, #selection.items) then
        modal:showErrorMessage(true, getText("UI_PZSurvivorToolkit_quantity_invalid", #selection.items))
        return
    end
    modal:showErrorMessage(false)
    Quantity.transfer(selection, text)
end

local function open(selection, title)
    if not Toolkit.Settings.quantityTransfers() then return end
    local modal = ISTextBox:new(0, 0, 360, 160,
        getText("UI_PZSurvivorToolkit_quantity_prompt", title, #selection.items), "", nil, accept, selection.playerNum, selection)
    modal:initialise()
    modal.player = selection.playerNum
    modal:setValidateFunction(nil, function(_, text) return Quantity.parse(text, #selection.items) ~= nil end)
    modal:setValidateTooltipText(getText("UI_PZSurvivorToolkit_quantity_invalid", #selection.items))
    modal.entry.onCommandEntered = function() modal:onClick(modal.yes) end
    modal:addToUIManager()
    modal.entry:focus()
    if JoypadState.players[selection.playerNum + 1] then
        modal.prevFocus = JoypadState.players[selection.playerNum + 1].focus
        setJoypadFocus(selection.playerNum, modal)
    end
    return modal
end

local nativeGrabMenu = ISInventoryPaneContextMenu.doGrabMenu
ISInventoryPaneContextMenu.doGrabMenu = function(context, rows, playerNum)
    local result = nativeGrabMenu(context, rows, playerNum)
    if not Toolkit.Settings.quantityTransfers() then return result end
    local page = getPlayerInventory(playerNum)
    local selection = Quantity.snapshot(playerNum, rows, page.inventory, true)
    if selection and #selection.items > 1 then
        local option = context:addOption(getText("UI_PZSurvivorToolkit_grab_amount"), selection, open, page.title)
        option.pzstCategory, option.pzstKey = "transfer", "grabAmount"
    end
    return result
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, rows)
    if not Toolkit.Settings.quantityTransfers() then return end
    local page = getPlayerLoot(playerNum)
    local selection = Quantity.snapshot(playerNum, rows, page.inventory, false)
    if selection and #selection.items > 1 then
        local option = context:addOption(getText("UI_PZSurvivorToolkit_put_amount", page.title), selection, open, page.title)
        option.pzstCategory, option.pzstKey = "transfer", "putAmount"
    end
end)
