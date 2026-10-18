local InventoryClasses = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/InventoryClasses.lua')
local clean, vanilla, active = {}, {}, {}
ISInventoryPane, CleanUI_Clean_ISInventoryPane, CleanUI_Vanilla_ISInventoryPane = active, clean, vanilla
local function visits(cleanFirst)
    local result = {}
    InventoryClasses.panes(function(class, enhanced)
        result[#result + 1] = {class, enhanced}
    end, cleanFirst)
    return result
end
local rows = visits()
assert(rows[1][1] == active and rows[2][1] == clean and rows[3][1] == vanilla)
assert(rows[1][2] and rows[2][2] and rows[3][2] == false)
rows = visits(true)
assert(rows[1][1] == clean and rows[2][1] == vanilla and rows[3][1] == active)
assert(rows[1][2] and rows[2][2] == false and rows[3][2])

-- Feature installers own their idempotence; discovery must retain alias order.
ISInventoryPane = vanilla
rows = visits(true)
assert(rows[2][1] == vanilla and rows[3][1] == vanilla and rows[3][2] == false)
CleanUI_Vanilla_ISInventoryPane = nil
rows = visits(true)
assert(rows[2][1] == nil and rows[3][1] == vanilla and rows[3][2])

local calls, callback = 0
callback = function() calls = calls + 1 end
for _, unavailable in ipairs({false, true, {}}) do
    CleanUI_RegisterInventoryUiToggleCallback = unavailable
    InventoryClasses.onToggle(callback)
end
CleanUI_RegisterInventoryUiToggleCallback = nil
InventoryClasses.onToggle(callback)
assert(calls == 0)
local registered
CleanUI_RegisterInventoryUiToggleCallback = function(fn)
    registered = fn
    fn()
end
InventoryClasses.onToggle(callback)
assert(registered == callback and calls == 1)
registered()
assert(calls == 2)
print('inventory class discovery and live toggle contracts passed')
