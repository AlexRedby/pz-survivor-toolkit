require "PZSurvivorWishlist/Client"
require "PZSurvivorWishlist/Settings"

local W = PZSurvivorWishlist
local Inventory = {}
W.Inventory = Inventory

-- Presentation invalidates before refresh, including a refresh that fails.
-- Unmanaged panes retain live scanning rather than assuming a mutation owner.
function Inventory.invalidate(pane)
    pane.pzswRowTypes = {}
end

local function groupTypes(row, previous, current)
    local items = row.items
    local cached = previous[row]
    if not cached or cached.items ~= items or cached.count ~= #items then
        local types, seen = {}, {}
        for _, item in ipairs(items) do
            if instanceof(item, "InventoryItem") then
                local fullType = item:getFullType()
                if fullType and not seen[fullType] then
                    seen[fullType] = true
                    types[#types + 1] = fullType
                end
            end
        end
        cached = {items = items, count = #items, types = types}
    end
    current[row] = cached
    return cached.types
end

local function wanted(playerNum, row, previous, current)
    if instanceof(row, "InventoryItem") then return W.Client.isWanted(playerNum, row:getFullType()) end
    if type(row) == "table" and type(row.items) == "table" then
        if current then
            -- Keep the complete mixed stack, including children beyond the
            -- render cap. Only membership is cached; wanted state stays live.
            for _, fullType in ipairs(groupTypes(row, previous, current)) do
                if W.Client.isWanted(playerNum, fullType) then return true end
            end
            return false
        end
        for _, item in ipairs(row.items) do
            if instanceof(item, "InventoryItem") and W.Client.isWanted(playerNum, item:getFullType()) then return true end
        end
    end
    return false
end

function Inventory.marks(pane)
    local result = {}
    local previous = pane.pzswRowTypes
    local current = previous and {}
    -- Retain only this draw's visible, non-dragged groups, even on early exit.
    if current then pane.pzswRowTypes = current end
    if not W.Settings.rowsEnabled() or not pane.items or not pane.itemHgt or pane.itemHgt <= 0 then return result end
    local scroll = pane:getYScroll()
    local first = math.max(1, math.floor(-scroll / pane.itemHgt) + 1)
    local last = math.min(#pane.items, math.ceil((pane:getHeight() - scroll) / pane.itemHgt))
    for i = first, last do
        local dragging = pane.dragging and pane.dragStarted and pane.selected and pane.selected[i]
        if not dragging and wanted(pane.player, pane.items[i], previous, current) then result[#result + 1] = i end
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
return Inventory
