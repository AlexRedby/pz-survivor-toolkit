if not getActivatedMods():contains('EURY_CONTAINERS') then return end
require 'PZSurvivorToolkit'
if PZSurvivorToolkit.BCPinCompatibility then return end
local Classes = require 'PZSurvivorToolkit/InventoryClasses'
local Rows = require 'PZSurvivorToolkit/InventoryRows'
local Order = require 'PZSurvivorToolkit/InventoryOrder'
local Pins = require 'BetterContainers/Upgrades/PinnedItems'
if Pins._panePatched or Pins._paneVisualPatched then
    print('[PZSurvivorToolkit] Pin compatibility needs Toolkit before Better Containers')
    return
end
PZSurvivorToolkit.BCPinCompatibility = true
-- Toolkit owns row ordering; InventoryPresentation draws the markers.
-- BC keeps pin state and options. Its temporary comparator hides CleanUI's weight-sort identity.
Pins._panePatched, Pins._paneVisualPatched = true, true
local installed = {}

local function prioritize(pane)
    return Order.prioritize(pane, Pins)
end

local function finishRows(pane, selected, anchor)
    if not pane.itemslist then return end
    if prioritize(pane) then
        table.wipe(pane.selected)
        table.wipe(pane.items)
        pane:restoreSelection(selected)
    end
    Rows.restoreAnchor(pane, anchor)
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
        local anchor = Rows.captureAnchor(pane)
        local result = refresh(pane, ...)
        finishRows(pane, pane:saveSelection({}), anchor)
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
            if not pane then return split(pane, ...) end
            local selected = pane:saveSelection({})
            local anchor = Rows.captureAnchor(pane)
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
