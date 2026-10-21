require "LootSorter_Presets"
local Presets = require "PZSurvivorToolkit/QuartermasterPresets"
local Rules = require "PZSurvivorToolkit/QuartermasterTagRules"
local Discovery = {}
local function any(set)
    for _, on in pairs(set or {}) do if on then return true end end
    return false
end
function Discovery.designated(object, ci)
    if not object or not object.hasModData or not object:hasModData() then return false end
    local md, key = object:getModData(), tostring(ci)
    local presets = Presets.native()
    local cats, items = LootSorter.resolveEffective(md.LSBox and md.LSBox[key],
        md.LSBoxItems and md.LSBoxItems[key], md.LSBoxPresets and md.LSBoxPresets[key], presets)
    return any(cats) or any(items)
        or #Rules.forBox(object, ci, md.LSBoxPresets and md.LSBoxPresets[key], presets) > 0
end
return Discovery
