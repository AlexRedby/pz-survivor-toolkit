local gate = ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/000ToolkitBCCompatibility.lua"

local function setup(active)
    local w = {calls = {}, loads = {}, base = {}, categories = {"AdvancedFood", "AdvancedTool"}}
    PZSurvivorToolkit = {}
    getActivatedMods = function() return {contains = function(_, id) return active and id == "EURY_CONTAINERS" end} end
    getCore = function() return {getDebug = function() return false end} end
    getTextOrNull = function() return "BC tooltip" end
    getSpecificPlayer = function() return {isAsleep = function() return false end} end
    ISInventoryPane = {
        refreshContainer = function(self) self.itemslist = {{cat = "AdvancedFood"}, {cat = "AdvancedTool"}} end,
        onFilterMenu = function() return "base menu" end,
        createChildren = function(self) self.filterMenu = {tooltip = "base tooltip"} end,
    }
    for _, name in ipairs({"refreshContainer", "onFilterMenu", "createChildren"}) do w.base[name] = ISInventoryPane[name] end
    local loaded = {}
    require = function(name)
        w.calls[#w.calls + 1] = name
        if loaded[name] then return loaded[name] end
        w.loads[name] = (w.loads[name] or 0) + 1
        local value = true
        if name == "PZSurvivorToolkit" or name == "ISUI/ISInventoryPane" then
        elseif name == "BetterContainers/Categorize/ui/FiltersUI" then
            value = {}
            local children = ISInventoryPane.createChildren
            ISInventoryPane.createChildren = function(self) children(self); self.dependencyUI = true end
        elseif name == "BetterContainers/Categorize" then
            value = {getAllDisplayCategories = function() return w.categories end}
            w.categorize = value
            local refresh = ISInventoryPane.refreshContainer
            ISInventoryPane.refreshContainer = function(self, ...) refresh(self, ...); self.categorized = true end
            w.dependencyRefresh, w.dependencyChildren = ISInventoryPane.refreshContainer, ISInventoryPane.createChildren
        elseif name == "BetterContainers/Categorize/CategoryFilters" then
            value = assert(loadstring(assert(NativeBCFilterSource, "native BC filters missing")))()
            if w.fail then
                value.install()
                error("fixture filters failed after installing patches")
            end
        else error("unexpected require: " .. name) end
        loaded[name] = value
        return value
    end
    return w
end

local w = setup(false)
dofile(gate)
assert(#w.calls == 0 and ISInventoryPane.refreshContainer == w.base.refreshContainer and not PZSurvivorToolkit.BCFilterCompatibility)
print("PASS BC inactive mod leaves pane and dependencies untouched")
if not NativeBCFilterSource then
    print("SKIP BC duplicate filtering checks require actual upstream CategoryFilters source")
    return
end

w = setup(true); dofile(gate)
local filters = PZSurvivorToolkit.BCFilterCompatibility
assert(type(filters) == "table" and filters._installedFilterBtn and filters._installedFilterRefresh)
assert(ISInventoryPane.refreshContainer == w.dependencyRefresh and ISInventoryPane.createChildren == w.dependencyChildren)
assert(ISInventoryPane.onFilterMenu == w.base.onFilterMenu and w.categorize.getAllDisplayCategories()[1] == "AdvancedFood")
local pane = setmetatable({_bcCategoryFilterApplied = {map = {AdvancedFood = true}, count = 1}}, {__index = ISInventoryPane})
pane:refreshContainer(); pane:createChildren()
assert(#pane.itemslist == 2 and not pane._bcItemslistUnfiltered and pane.categorized and pane.dependencyUI)
assert(pane.filterMenu.tooltip == "base tooltip" and pane:onFilterMenu() == "base menu")
assert(w.loads["BetterContainers/Categorize"] == 1 and w.loads["BetterContainers/Categorize/ui/FiltersUI"] == 1)
assert(w.calls[4] == "BetterContainers/Categorize" and w.calls[5] == "BetterContainers/Categorize/CategoryFilters", "dependencies must load before capturing pane methods")
local methods = {}
for _, name in ipairs({"refreshContainer", "onFilterMenu", "createChildren"}) do
    local before = ISInventoryPane[name]
    methods[name] = function(self, ...) self.later = true; return before(self, ...) end
    ISInventoryPane[name] = methods[name]
end
filters.install(); dofile(gate)
for name, method in pairs(methods) do assert(ISInventoryPane[name] == method, "later wrapper was unwrapped: " .. name) end
assert(w.loads["BetterContainers/Categorize/CategoryFilters"] == 1)
pane:refreshContainer(); assert(pane.later and #pane.itemslist == 2)
print("PASS BC actual duplicate patches suppressed; categorization/UI dependencies, idempotence and later wrappers preserved")

w = setup(true); w.fail = true
local ok, err = pcall(dofile, gate)
assert(not ok and tostring(err):find("fixture filters failed"))
assert(not PZSurvivorToolkit.BCFilterCompatibility)
assert(ISInventoryPane.refreshContainer == w.dependencyRefresh and ISInventoryPane.createChildren == w.dependencyChildren)
assert(ISInventoryPane.onFilterMenu == w.base.onFilterMenu, "partial filter patches must roll back on error")
w.fail = false; dofile(gate)
assert(type(PZSurvivorToolkit.BCFilterCompatibility) == "table" and w.loads["BetterContainers/Categorize/CategoryFilters"] == 2)
assert(w.loads["BetterContainers/Categorize"] == 1, "retry must preserve loaded categorization dependency")
print("PASS BC partial load error restores only duplicate patches, rethrows and permits retry")

w = setup(true)
local cached = require("BetterContainers/Categorize/CategoryFilters")
if not cached._installedFilterRefresh then
    dofile(gate)
    assert(PZSurvivorToolkit.BCFilterCompatibility == cached)
    assert(ISInventoryPane.refreshContainer == w.dependencyRefresh and ISInventoryPane.createChildren == w.dependencyChildren)
    assert(w.loads["BetterContainers/Categorize/CategoryFilters"] == 1)
    print("PASS BC cached module without auto-install is explicitly installed and suppressed")
end

w = setup(true)
local upstream = require("BetterContainers/Categorize/CategoryFilters")
upstream.install()
local lateRefresh = function() return "later refresh" end
ISInventoryPane.refreshContainer = lateRefresh
local menu, children = ISInventoryPane.onFilterMenu, ISInventoryPane.createChildren
dofile(gate)
assert(not PZSurvivorToolkit.BCFilterCompatibility and ISInventoryPane.refreshContainer == lateRefresh)
assert(ISInventoryPane.onFilterMenu == menu and ISInventoryPane.createChildren == children)
assert(require("BetterContainers/Categorize/CategoryFilters") == upstream and w.loads["BetterContainers/Categorize/CategoryFilters"] == 1)
print("PASS BC wrong load order preserves installed/later methods and avoids claiming success")
