-- Native capabilities, read without constructing items or executing actions.
local fluids = require "PZSurvivorToolkit/ItemFluidTags"
local bait = require "PZSurvivorToolkit/ItemBaitTags"
local repair = require "PZSurvivorToolkit/ItemRepairTags"
local Usage = {}
-- The first four positions are the original snapshot format.
local fields = {"bandage", "disinfectant", "dirty", "fuel", "ignite", "treatment",
    "spentBattery", "fishBait", "trapBait", "repair"}

local function tagged(source, id)
    if not source or not source.hasTag or not ItemTag or not ItemTag[id] then return nil end
    return source:hasTag(ItemTag[id])
end

local function drainable(script, item)
    if item then
        if item.IsDrainable then return item:IsDrainable() end
    elseif script and script.isItemType and ItemType and ItemType.DRAINABLE then
        return script:isItemType(ItemType.DRAINABLE)
    end
end

local function power(script, item, method, helper)
    if item then return item[method] and item[method](item) end
    if script and helper then return helper(script) end
end

local function solidFuel(script, item, isDrainable)
    local source = item or script
    if not source then return nil end
    local fullType
    if item and item.getFullType then fullType = item:getFullType()
    elseif not item and script.getFullName then fullType = script:getFullName() end
    local propane = fullType == "Base.PropaneTank"
    local tag = tagged(source, "IS_FIRE_FUEL")
    local ratio = source.getFireFuelRatio and source:getFireFuelRatio()
    local candidate = propane or tag == true or type(ratio) == "number" and ratio > 0
    if not candidate then
        if tag == false and type(ratio) == "number" then return false end
        return nil
    end
    if propane then
        -- BBQ checks fractional remaining uses; a partly used tank still fuels it.
        if item and item.getCurrentUsesFloat then return item:getCurrentUsesFloat() > 0 end
        return nil, "fractional"
    end
    if isDrainable == false or tagged(source, "IS_FIRE_FUEL_SINGLE_USE") == true then return true end
    if isDrainable then
        -- Camping drains whole uses except for explicitly single-use fuels.
        if item and item.getCurrentUses then return item:getCurrentUses() > 0 end
        return nil, "whole"
    end
    return nil
end

local plantTreatments = { ["Base.GardeningSprayMilk"] = true,
    ["Base.GardeningSprayCigarettes"] = true, ["Base.GardeningSprayAphids"] = true,
    ["Base.SlugRepellent"] = true }

local function copy(value)
    local out = {}
    for key, field in pairs(value) do out[key] = field end
    return out
end

local function merge(target, source)
    for key, value in pairs(source) do target[key] = value end
end

local function stateKey(state)
    local key = {}
    for _, field in ipairs(fields) do key[#key + 1] = tostring(state[field]) end
    for _, field in ipairs({"beverage", "alcoholic", "cooked"}) do key[#key + 1] = tostring(state[field]) end
    return table.concat(key, ":")
end

local function previews(roles, fluidStates, baitStates, varying)
    local hasVarying = false
    for _ in pairs(varying) do hasVarying = true; break end
    if #fluidStates == 0 and #baitStates == 0 and not hasVarying then return {} end
    local result, seen = {}, {}
    -- Native fractional getters normalize the same integer remaining uses.
    -- A small positive fraction still has a use; do not invent half a use.
    local levels = hasVarying and {0, 1} or {0}
    for _, fluidState in ipairs(#fluidStates > 0 and fluidStates or {{}}) do
        for _, baitState in ipairs(#baitStates > 0 and baitStates or {{}}) do
            for _, level in ipairs(levels) do
                local state = copy(roles)
                merge(state, fluidState); merge(state, baitState)
                for id, mode in pairs(varying) do
                    if mode == "empty" then state[id] = level == 0
                    elseif mode == "fractional" then state[id] = level > 0
                    else state[id] = level >= 1 end
                end
                local key = stateKey(state)
                if not seen[key] then result[#result + 1], seen[key] = state, true end
            end
        end
    end
    return result
end

-- Current roles, coherent preview states, and whether this has a fluid component.
-- nil fields mean missing metadata or no physical contents to observe. Declared
-- initial contents are returned only in the second result, never as current data.
function Usage.read(script, item)
    script = script or item and item.getScriptItem and item:getScriptItem()
    local roles, possible, isFluid = fluids.usage(script, item)
    local source, isDrainable = item or script, drainable(script, item)
    local fullType = item and item.getFullType and item:getFullType()
        or script and script.getFullName and script:getFullName()
    local varying = {}
    local bandage = power(script, item, "getBandagePower", toolkitScriptBandagePower)
    if type(bandage) == "number" then roles.bandage = bandage > 0 end
    if roles.bandage == false then roles.dirty = false
    elseif roles.bandage then
        local washable = tagged(source, "CAN_BE_WASHED")
        local cleaning = source.getItemAfterCleaning and source:getItemAfterCleaning()
        if washable == false or source.getItemAfterCleaning and (not cleaning or tostring(cleaning) == "") then
            roles.dirty = false
        elseif washable and cleaning and tostring(cleaning) ~= "" then roles.dirty = true end
    end
    local fuel, fuelMode = solidFuel(script, item, isDrainable)
    if isFluid == false then
        roles.fuel = fuel
        if fuelMode then varying.fuel = fuelMode end
        local alcohol = power(script, item, "getAlcoholPower", toolkitScriptAlcoholPower)
        if isDrainable == false then roles.disinfectant = false
        elseif isDrainable and type(alcohol) == "number" then roles.disinfectant = alcohol == 4 end
    end
    local starter = tagged(source, "START_FIRE")
    if fullType == "Base.Lighter" or fullType == "Base.Matches" then starter = true end
    if starter == false then roles.ignite = false
    elseif starter then
        if item then roles.ignite = item.getCurrentUses and item:getCurrentUses() > 0
        else varying.ignite = "whole" end
    end
    if fullType == "Base.GardeningSprayEmpty" then roles.treatment = false
    elseif plantTreatments[fullType] then
        if item then roles.treatment = item.getCurrentUses and item:getCurrentUses() >= 1
        else varying.treatment = "whole" end
    end
    if fullType == "Base.Battery" then
        if item then roles.spentBattery = item.getCurrentUsesFloat and item:getCurrentUsesFloat() <= 0
        else varying.spentBattery = "empty" end
    end
    local repairRole, repairStates = repair.read(script, item)
    roles.repair = repairRole
    if not item and repairStates and #repairStates > 0 then varying.repair = "whole" end
    local baitRoles, baitStates = bait.read(script, item)
    merge(roles, baitRoles)
    possible = not item and previews(roles, possible, baitStates or {}, varying) or {}
    return roles, possible, isFluid
end

-- Compact snapshots preserve false separately from unknown. No factory-state
-- reconstruction is needed when a manifest is read without an InventoryItem.
function Usage.encode(roles)
    local result, known, extended = {}, false, false
    for i, field in ipairs(fields) do
        local value = roles and roles[field]
        result[i] = value == true and "1" or value == false and "0" or "?"
        if type(value) == "boolean" then known = true end
        if i > 4 and type(value) == "boolean" then extended = true end
    end
    return known and table.concat(result):sub(1, extended and #fields or 4) or nil
end

function Usage.decode(value)
    if type(value) ~= "string" or (#value ~= 4 and #value ~= #fields) or value:find("[^10?]") then return {} end
    local result = {}
    for i, field in ipairs(fields) do
        local character = value:sub(i, i)
        if character ~= "?" and character ~= "" then result[field] = character == "1" end
    end
    return result
end

return Usage
