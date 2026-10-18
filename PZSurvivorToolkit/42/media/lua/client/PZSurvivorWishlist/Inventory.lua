require "PZSurvivorWishlist/Client"
require "PZSurvivorWishlist/Settings"
require "ISUI/ISInventoryPane"

local W = PZSurvivorWishlist
local Inventory = {}
W.Inventory = Inventory
local wrapped = {}

local function wanted(playerNum, row)
    if instanceof(row, "InventoryItem") then return W.Client.isWanted(playerNum, row:getFullType()) end
    if type(row) == "table" and type(row.items) == "table" then
        for _, item in ipairs(row.items) do
            if instanceof(item, "InventoryItem") and W.Client.isWanted(playerNum, item:getFullType()) then return true end
        end
    end
    return false
end

function Inventory.marks(pane)
    local result = {}
    if not W.Settings.rowsEnabled() or not pane.items or not pane.itemHgt or pane.itemHgt <= 0 then return result end
    local scroll = pane:getYScroll()
    local first = math.max(1, math.floor(-scroll / pane.itemHgt) + 1)
    local last = math.min(#pane.items, math.ceil((pane:getHeight() - scroll) / pane.itemHgt))
    for i = first, last do
        local dragging = pane.dragging and pane.dragStarted and pane.selected and pane.selected[i]
        if not dragging and wanted(pane.player, pane.items[i]) then result[#result + 1] = i end
    end
    return result
end

function Inventory.draw(pane)
    local colour, scroll = W.Settings.color(), pane:getYScroll()
    local width = pane:getWidth() - 2
    if pane.vscroll and pane.vscroll:getHeight() < pane:getScrollHeight() then width = width - pane.vscroll:getWidth() end
    for _, index in ipairs(Inventory.marks(pane)) do
        local y = (index - 1) * pane.itemHgt + pane.headerHgt
        local top = math.max(y, pane.headerHgt - scroll)
        local bottom = math.min(y + pane.itemHgt, pane:getHeight() - scroll)
        if bottom > top then
            pane:drawRect(1, top, width, bottom - top, 0.1, colour.r, colour.g, colour.b)
            pane:drawRectBorder(1, top, width, bottom - top, 0.7, colour.r, colour.g, colour.b)
        end
    end
end

local function install(class)
    if not class or not class.renderdetails or wrapped[class] then return end
    local original = class.renderdetails
    wrapped[class] = true
    class.renderdetails = function(self, doDragged, ...)
        local result = original(self, doDragged, ...)
        if not doDragged then Inventory.draw(self) end
        return result
    end
end

function Inventory.install()
    install(ISInventoryPane)
    install(CleanUI_Clean_ISInventoryPane)
    install(CleanUI_Vanilla_ISInventoryPane)
end

local function context(playerNum, menu, items)
    local types = {}
    for _, selection in ipairs(items) do
        local group = instanceof(selection, "InventoryItem") and { selection } or selection.items
        for _, item in ipairs(group or {}) do
            if instanceof(item, "InventoryItem") then types[item:getFullType()] = true end
        end
    end
    local entries = {}
    for fullType in pairs(types) do entries[#entries + 1] = { fullType = fullType, amount = 1 } end
    if #entries == 0 then return end
    local list = W.Client.selected(playerNum)
    if #entries == 1 and list then
        local fullType, listId = entries[1].fullType, list.id
        local keys = W.Client.entryKeys(list, fullType)
        if #keys == 0 then
            menu:addOption(getText("UI_PZSW_AddWanted"), playerNum, function(number)
                W.Client.edit(number, "addMany", {listId = listId, entries = entries})
            end)
        end
        for _, key in ipairs(keys) do
            local entry = list.entries[key]
            local name = getText(entry.vehicleTypes and "UI_PZSW_RemoveVehicleWanted" or "UI_PZSW_RemoveWanted")
            if entry.vehicleTypes and #keys > 1 then name = name .. ": " .. getItemNameFromFullType(entry.vehicleTypes[1]) end
            menu:addOption(name, playerNum, function(number)
                W.Client.edit(number, "remove", {listId = listId, fullType = key})
            end)
        end
        return
    end
    menu:addOption(getText("UI_PZSW_AddWanted"), playerNum, function(number)
        W.Client.addItems(number, entries)
    end)
end

Events.OnFillInventoryObjectContextMenu.Add(context)
Events.OnGameStart.Add(function()
    Inventory.install()
    if CleanUI_RegisterInventoryUiToggleCallback then CleanUI_RegisterInventoryUiToggleCallback(Inventory.install) end
end)
return Inventory
