require "ISUI/ISInventoryPane"
local Categories = require "PZSurvivorToolkit/ItemCategories"
local Classes = require "PZSurvivorToolkit/InventoryClasses"
local Legacy = require "PZSurvivorToolkit/LegacyItemCategories"
local Groups = require "PZSurvivorToolkit/InventoryCategoryGroups"
local Rows = require "PZSurvivorToolkit/InventoryRows"
local Order = require "PZSurvivorToolkit/InventoryOrder"
local installed = {}

local function install(class)
    if not class or installed[class] or not class.refreshContainer then return end
    installed[class] = true
    local restore = class.restoreSelection
    if restore then
        class.restoreSelection = function(pane, saved)
            local changed = Groups.split(pane, saved)
            changed = Order.prioritize(pane) or changed
            local result = restore(pane, saved)
            if changed and pane.mode == "details" then Rows.restoreSelection(pane, saved) end
            return result
        end
    end
    local refresh = class.refreshContainer
    class.refreshContainer = function(pane, ...)
        -- Classify before native grouping, filtering and sorting read the items.
        -- Repeating this on refresh also restores instance categories after load
        -- and observes changes to fluid contents and recorded-media bindings.
        local anchor = Rows.captureAnchor(pane)
        Categories.prepareContainer(pane.inventory)
        local result = refresh(pane, ...)
        Rows.restoreAnchor(pane, anchor)
        return result
    end
end

local function installClasses()
    Classes.panes(install)
end

local booted = false
Events.OnGameBoot.Add(function()
    booted = true
    installClasses()
end)
Events.OnGameStart.Add(function() Legacy.reset();installClasses() end)
Events.OnCreatePlayer.Add(installClasses)
-- CleanUI calls subscribers immediately. BC still replaces restoreSelection
-- during top-level load, so capture class methods only after all mods load.
Classes.onToggle(function() if booted then installClasses() end end)
