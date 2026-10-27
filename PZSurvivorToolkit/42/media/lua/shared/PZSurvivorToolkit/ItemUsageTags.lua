-- Native medical and fuel capabilities, read without constructing game items.
local fluids = require "PZSurvivorToolkit/ItemFluidTags"
local Usage = {}
local fields = {"bandage", "disinfectant", "dirty", "fuel"}

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
        return nil, true
    end
    if isDrainable == false or tagged(source, "IS_FIRE_FUEL_SINGLE_USE") == true then return true end
    if isDrainable then
        -- Camping drains whole uses except for explicitly single-use fuels.
        if item and item.getCurrentUses then return item:getCurrentUses() > 0 end
        return nil, true
    end
    return nil
end

-- Current roles, coherent preview states, and whether this has a fluid component.
-- nil fields mean missing metadata or no physical contents to observe. Declared
-- initial contents are returned only in the second result, never as current data.
function Usage.read(script, item)
    script = script or item and item.getScriptItem and item:getScriptItem()
    local roles, possible, isFluid = fluids.usage(script, item)
    local source, isDrainable = item or script, drainable(script, item)
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
    local fuel, fuelCanVary = solidFuel(script, item, isDrainable)
    if isFluid == false then
        roles.fuel = fuel
        local alcohol = power(script, item, "getAlcoholPower", toolkitScriptAlcoholPower)
        if isDrainable == false then roles.disinfectant = false
        elseif isDrainable and type(alcohol) == "number" then roles.disinfectant = alcohol == 4 end
    end
    if not item then
        if isFluid then
            for _, state in ipairs(possible) do
                state.bandage, state.dirty = roles.bandage, roles.dirty
            end
        elseif isFluid == false and fuelCanVary then
            possible = {}
            for _, remaining in ipairs({false, true}) do
                possible[#possible + 1] = {bandage = roles.bandage, dirty = roles.dirty,
                    disinfectant = roles.disinfectant, fuel = remaining}
            end
        end
    end
    return roles, possible, isFluid
end

-- Compact snapshots preserve false separately from unknown. No factory-state
-- reconstruction is needed when a manifest is read without an InventoryItem.
function Usage.encode(roles)
    local result, known = {}, false
    for i, field in ipairs(fields) do
        local value = roles and roles[field]
        result[i] = value == true and "1" or value == false and "0" or "?"
        if type(value) == "boolean" then known = true end
    end
    return known and table.concat(result) or nil
end

function Usage.decode(value)
    if type(value) ~= "string" or #value ~= #fields or value:find("[^10?]") then return {} end
    local result = {}
    for i, field in ipairs(fields) do
        local character = value:sub(i, i)
        if character ~= "?" then result[field] = character == "1" end
    end
    return result
end

return Usage
