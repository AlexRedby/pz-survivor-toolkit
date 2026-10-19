if not getActivatedMods():contains('EURY_CONTAINERS') then return end
require 'PZSurvivorToolkit'
if PZSurvivorToolkit.BCPinCompatibility then return end
local Classes = require 'PZSurvivorToolkit/InventoryClasses'
local Pins = require 'BetterContainers/Upgrades/PinnedItems'
if Pins._panePatched then
    print('[PZSurvivorToolkit] Pin compatibility needs Toolkit before Better Containers')
    return
end
PZSurvivorToolkit.BCPinCompatibility = true
-- Apply pins to finished rows; a temporary comparator also hides CleanUI's weight-sort identity.
Pins._panePatched = true
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

local function visibleRows(pane)
    local rows = {}
    for _, group in ipairs(pane.itemslist) do
        if not (pane.equippedCollapsed and group.equipped) then
            rows[#rows + 1] = group
            if group.items and not pane.collapsed[group.name] then
                local first = group.cleanUIFirstActualIndex or 2
                local last = math.min(#group.items, first + (ISInventoryPane.MAX_ITEMS_IN_STACK_TO_RENDER or 50) - 1)
                for index = first, last do rows[#rows + 1] = group.items[index] end
            end
        end
    end
    return rows
end

local function finishRows(pane, selected, anchor)
    if not Pins.displayPinnedItem(pane.inventoryPage) or not pane.itemslist then return end
    if prioritize(pane) then
        table.wipe(pane.selected)
        table.wipe(pane.items)
        pane:restoreSelection(selected)
    end
    if anchor then
        pane.firstSelect = nil
        for index, row in ipairs(visibleRows(pane)) do
            if row == anchor or (not instanceof(anchor, 'InventoryItem') and row.items and anchor.items
                and (row.name == anchor.name or row.items[1] == anchor.items[1])) then
                pane.firstSelect = index; break
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
    -- BC's marker installer accepts only the global class and otherwise skips the alternate pane.
    local active, patched = ISInventoryPane, Pins._paneVisualPatched
    ISInventoryPane, Pins._paneVisualPatched = class, false
    local ok, err = pcall(Pins.installInventoryPaneVisualPatch)
    ISInventoryPane, Pins._paneVisualPatched = active, patched or ok
    if not ok then error(err) end
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
