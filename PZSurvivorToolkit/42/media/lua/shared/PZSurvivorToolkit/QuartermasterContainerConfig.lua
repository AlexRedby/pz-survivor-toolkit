local Appearance = require "PZSurvivorToolkit/ContainerAppearance"
local Config = {}
PZSurvivorToolkit.QuartermasterContainerConfig = Config

local function hasAny(value)
    for _ in pairs(value) do return true end
    return false
end

local function copySet(value)
    if value == nil then return {} end
    if type(value) ~= "table" then return nil end
    local out, count = {}, 0
    for key, on in pairs(value) do
        if type(key) ~= "string" or #key > 512 then return nil end
        if on then
            if type(on) ~= "boolean" and type(on) ~= "string" and type(on) ~= "number" then return nil end
            if type(on) == "number" and (on ~= on or math.abs(on) == math.huge) then return nil end
            out[key] = on
            count = count + 1
            if count > 10000 then return nil end
        end
    end
    return out
end

-- Complete designation, with appearance deliberately optional for existing callers.
function Config.normalize(value)
    if type(value) ~= "table" then return nil end
    local out = {cats = copySet(value.cats), items = copySet(value.items), presets = copySet(value.presets)}
    if not out.cats or not out.items or not out.presets then return nil end
    local priority = value.priority == nil and 0 or tonumber(value.priority)
    if not priority or priority ~= priority or math.abs(priority) == math.huge then return nil end
    out.priority = priority
    if value.noDuplicates ~= nil and type(value.noDuplicates) ~= "boolean" then return nil end
    out.noDuplicates = value.noDuplicates == true
    if value.appearance ~= nil then
        out.appearance = Appearance.normalize(value.appearance)
        if not out.appearance then return nil end
    end
    if value.groupOperation ~= nil then
        local op = value.groupOperation
        if type(op) ~= "table" or (op.mode ~= "create" and op.mode ~= "join"
            and op.mode ~= "update" and op.mode ~= "detach") then return nil end
        local clean = {mode = op.mode}
        if op.mode == "join" or op.mode == "update" then
            if type(op.id) ~= "string" or #op.id == 0 or #op.id > 128 then return nil end
            clean.id = op.id
        end
        if op.mode == "update" then
            if type(op.baseRevision) ~= "number" or op.baseRevision < 0
                or op.baseRevision % 1 ~= 0 or op.baseRevision == math.huge then return nil end
            clean.baseRevision = op.baseRevision
        end
        out.groupOperation = clean
    end
    return out
end

function Config.read(obj, ci, player)
    local group = require("PZSurvivorToolkit/ContainerGroups").resolve(obj, ci)
    if group then return group.configuration end
    local md, key = obj:getModData(), tostring(ci)
    local out = Config.normalize({cats = md.LSBox and md.LSBox[key], items = md.LSBoxItems and md.LSBoxItems[key],
        presets = md.LSBoxPresets and md.LSBoxPresets[key], priority = md.LSBoxPriority and md.LSBoxPriority[key],
        noDuplicates = md.LSBoxNoDuplicates and md.LSBoxNoDuplicates[key]})
    if out then out.appearance = Appearance.read(obj, ci, player) end
    return out
end

-- Mutate only the selected compartment's fields in the current ModData.
function Config.apply(obj, ci, player, value)
    local md, key = obj:getModData(), tostring(ci)
    for field, set in pairs({LSBox = value.cats, LSBoxItems = value.items, LSBoxPresets = value.presets}) do
        if type(md[field]) ~= "table" then md[field] = {} end
        md[field][key] = hasAny(set) and copySet(set) or nil
    end
    if value.priority ~= 0 then
        if type(md.LSBoxPriority) ~= "table" then md.LSBoxPriority = {} end
        md.LSBoxPriority[key] = value.priority
    elseif type(md.LSBoxPriority) == "table" then md.LSBoxPriority[key] = nil end
    if value.noDuplicates then
        if type(md.LSBoxNoDuplicates) ~= "table" then md.LSBoxNoDuplicates = {} end
        md.LSBoxNoDuplicates[key] = true
    elseif type(md.LSBoxNoDuplicates) == "table" then md.LSBoxNoDuplicates[key] = nil end
    if value.appearance ~= nil then Appearance.apply(obj, ci, player, value.appearance) end
end

return Config
