PZSurvivorToolkit = PZSurvivorToolkit or {}
local Retention = {}
PZSurvivorToolkit.ItemRetention = Retention
Retention.FIELD = "pzstRetained"
Retention.MODULE = "PZSurvivorToolkitRetention"
Retention.MAX_ITEMS = 128

function Retention.isEnabled() return true end

function Retention.isRetained(item)
    if not item or not item:hasModData() then return false end
    local data = item:getModData()
    return data[Retention.FIELD] == true or data.ocStuck == true
end

-- Saved OC flags are read in place; the first authoritative edit migrates them.
function Retention.apply(item, value)
    local data = item:getModData()
    data[Retention.FIELD] = value and true or nil
    data.ocStuck = nil
end

local Access = require "PZSurvivorToolkit/ItemAccess"
Retention.locate, Retention.resolve = Access.locate, Access.resolve

return Retention
