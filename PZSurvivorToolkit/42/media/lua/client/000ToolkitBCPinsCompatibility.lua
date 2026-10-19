if not getActivatedMods():contains('EURY_CONTAINERS') then return end
require 'PZSurvivorToolkit'
if PZSurvivorToolkit.BCPinCompatibility then return end
local Classes = require 'PZSurvivorToolkit/InventoryClasses'
local Rows = require 'PZSurvivorToolkit/InventoryRows'
local Pins = require 'BetterContainers/Upgrades/PinnedItems'
if Pins._panePatched or Pins._paneVisualPatched then
    print('[PZSurvivorToolkit] Pin compatibility needs Toolkit before Better Containers')
    return
end
PZSurvivorToolkit.BCPinCompatibility = true
-- Toolkit owns row ordering and marker placement; BC keeps pin state and options.
-- A temporary comparator also hides CleanUI's weight-sort identity.
Pins._panePatched, Pins._paneVisualPatched = true, true
local installed = {}

local function itemRow(row)
    return row.type ~= 'separator' and not row._bcEquippedAttachedSeparator and not row._ocPinned
        and row.items and row.items[1] and row.items[1].getFullType
end

local function prioritize(pane)
    if not Pins.displayPinnedItem(pane.inventoryPage) or not pane.itemslist then return false end
    local rows, ordered, first = pane.itemslist, {}, 1
    while first <= #rows do
        local head, last = rows[first], first
        if itemRow(head) then
            while last < #rows do
                local row = rows[last + 1]
                if not itemRow(row) or (row.equipped == true) ~= (head.equipped == true)
                    or (row.matchesSearch == true) ~= (head.matchesSearch == true) then break end
                last = last + 1
            end
            -- Stable partition retains the chosen column order and search/equipment sections.
            for _, pinned in ipairs({true, false}) do
                for index = first, last do
                    local row = rows[index]
                    if Pins.isFavourite(row.items[1]:getFullType()) == pinned then ordered[#ordered + 1] = row end
                end
            end
        else
            ordered[#ordered + 1] = head
        end
        first = last + 1
    end
    local changed = false
    for index, row in ipairs(ordered) do
        changed = changed or rows[index] ~= row
        rows[index] = row
    end
    return changed
end

local function finishRows(pane, selected, anchor)
    if not Pins.displayPinnedItem(pane.inventoryPage) or not pane.itemslist then return end
    if prioritize(pane) then
        table.wipe(pane.selected)
        table.wipe(pane.items)
        pane:restoreSelection(selected)
    end
    Rows.restoreAnchor(pane, anchor)
end

local function drawPins(pane, doDragged)
    if doDragged or not Pins.displayPinnedItem(pane.inventoryPage) or not pane.items then return end
    local texture = getTexture('media/ui/BetterContainers/PinnedItemMarker.png')
    if not texture then return end
    local size = math.min(11, pane.itemHgt)
    if size < 8 then return end
    local itemSize = math.min(pane.itemHgt - 2, 32)
    local x = pane.column2 - itemSize - (pane.itemHgt - itemSize) / 2 + 1
    -- The renderer owns visible rows, including hidden equipment and stack limits.
    for index, row in ipairs(pane.items) do
        if type(row) == 'table' and row.type ~= 'separator' and not row._bcEquippedAttachedSeparator then
            local item = row.items and row.items[1]
            if item and item.getFullType and Pins.isFavourite(item:getFullType())
                and not (pane.dragging ~= nil and pane.dragStarted and pane.selected and pane.selected[index] ~= nil) then
                pane:drawTextureScaled(texture, x, (index - 1) * pane.itemHgt + pane.headerHgt, size, size, 1, 1, 1, 1)
            end
        end
    end
end

local function install(class)
    if not class or installed[class] then return end
    installed[class] = true
    local restore, refresh = class.restoreSelection, class.refreshContainer
    class.restoreSelection = function(pane, selected)
        prioritize(pane)
        return restore(pane, selected)
    end
    class.refreshContainer = function(pane, ...)
        local anchor = pane.firstSelect and pane.items and pane.items[pane.firstSelect]
        local result = refresh(pane, ...)
        finishRows(pane, pane:saveSelection({}), anchor)
        return result
    end
    local render = class.renderdetails
    class.renderdetails = function(pane, doDragged, ...)
        local result = render(pane, doDragged, ...)
        drawPins(pane, doDragged)
        return result
    end
end

local splitInstalled
local function installClasses()
    Classes.panes(install)
    -- OC splits can sort again outside our refresh hook, after BC's comparator was restored.
    if OrganizedCategories and OrganizedCategories.splitStacksByDisplayCategory and not splitInstalled then
        splitInstalled = true
        local split = OrganizedCategories.splitStacksByDisplayCategory
        OrganizedCategories.splitStacksByDisplayCategory = function(pane, ...)
            if not pane or not Pins.displayPinnedItem(pane.inventoryPage) then return split(pane, ...) end
            local selected = pane:saveSelection({})
            local anchor = pane.firstSelect and pane.items and pane.items[pane.firstSelect]
            local result = split(pane, ...)
            finishRows(pane, selected, anchor)
            return result
        end
    end
end
local booted = false
Events.OnGameBoot.Add(function()
    booted = true
    installClasses()
end)
Events.OnGameStart.Add(installClasses)
-- Wait for BC's top-level class replacements before capturing methods.
Classes.onToggle(function() if booted then installClasses() end end)
