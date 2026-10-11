if not getActivatedMods():contains("EURY_CONTAINERS") then return end
require "PZSurvivorToolkit"
if PZSurvivorToolkit.BCFilterCompatibility then return end
require "ISUI/ISInventoryPane"
require "BetterContainers/Categorize/ui/FiltersUI"
require "BetterContainers/Categorize"

-- Keep BC's container features; only Toolkit owns category filtering.
local pane = ISInventoryPane
local refresh, menu, children = pane.refreshContainer, pane.onFilterMenu, pane.createChildren
local ok, filters = pcall(function()
    local module = require "BetterContainers/Categorize/CategoryFilters"
    module.install()
    return module
end)
if not ok then
    pane.refreshContainer, pane.onFilterMenu, pane.createChildren = refresh, menu, children
    error(filters)
end
if pane.refreshContainer == refresh then
    print("[PZSurvivorToolkit] Filter compatibility needs Toolkit before Better Containers")
    return
end
pane.refreshContainer, pane.onFilterMenu, pane.createChildren = refresh, menu, children
PZSurvivorToolkit.BCFilterCompatibility = filters
