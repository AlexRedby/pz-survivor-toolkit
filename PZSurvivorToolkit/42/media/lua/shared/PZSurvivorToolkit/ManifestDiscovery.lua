require "LootSorter_Presets"
local Presets = require "PZSurvivorToolkit/QuartermasterPresets"
local Rules = require "PZSurvivorToolkit/QuartermasterTagRules"
local Groups = require "PZSurvivorToolkit/ContainerGroups"
local Discovery = {}
local function any(set)
    for _, on in pairs(set or {}) do if on then return true end end
    return false
end
function Discovery.designated(object, ci)
    if not object or not object.hasModData or not object:hasModData() then return false end
    local md, key = object:getModData(), tostring(ci)
    local group = Groups.resolve(object, ci)
    local config = group and group.configuration
    local links = config and config.presets or (md.LSBoxPresets and md.LSBoxPresets[key])
    local presets = Presets.native()
    local cats, items = LootSorter.resolveEffective(config and config.cats or (md.LSBox and md.LSBox[key]),
        config and config.items or (md.LSBoxItems and md.LSBoxItems[key]), links, presets)
    return any(cats) or any(items)
        or #Rules.forBox(object, ci, links, presets) > 0
end
return Discovery
