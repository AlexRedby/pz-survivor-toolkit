-- Native cooking state is mutable InventoryItem data. Script previews describe
-- possible states without creating items or running OnCreate/OnCooked callbacks.
local CookingStates = {}

local function scriptFood(script)
    if script and script.isItemType and ItemType and ItemType.FOOD then
        return script:isItemType(ItemType.FOOD)
    end
end

local function alreadyCooked(script)
    -- B42.21 Food.update applies this declaration with setCooked(true), even
    -- outside a heated container. Names, icons and recipe results do not prove it.
    return script and script.hasTag and ItemTag and ItemTag.ALREADY_COOKED
        and script:hasTag(ItemTag.ALREADY_COOKED) or false
end

local function possibilities(script)
    local food = scriptFood(script)
    if food == false then return {} end
    if food == nil then return nil end
    local inherent = alreadyCooked(script)
    if script.isIsCookable then
        if script:isIsCookable() then
            -- ReplaceOnCooked does not rule out cooked/burnt on this type:
            -- B42.21 Food.update bypasses replacement when the source is rotten.
            return inherent and {"cooked", "burnt"} or {"raw", "cooked", "burnt"}
        end
        return inherent and {"cooked"} or {}
    end
    if inherent then return {"cooked"} end
end

-- Returns raw/cooked/burnt, false for known inapplicable food/nonfood, or nil
-- when current state is unknown. The second return is an array of script states
-- for type previews; nil means unavailable metadata. It is never current state.
function CookingStates.read(script, item)
    script = script or item and item.getScriptItem and item:getScriptItem()
    local possible = possibilities(script)
    if item then
        local food
        if item.IsFood then food = item:IsFood()
        elseif item.isFood then food = item:isFood()
        else food = scriptFood(script) end
        if food == false then return false, possible end
        if food == nil then return nil, possible end
        if not item.isBurnt then return nil, possible end
        if item:isBurnt() then return "burnt", possible end
        if not item.isCooked then return nil, possible end
        if item:isCooked() then return "cooked", possible end
        -- Cooked food can stop being cookable; test its flags first. Conversely,
        -- ordinary uncookable fruit is not raw just because both flags are false.
        local cookable
        if item.isCookable then cookable = item:isCookable()
        elseif item.isIsCookable then cookable = item:isIsCookable() end
        if cookable == nil then return nil, possible end
        return cookable and "raw" or false, possible
    end
    local food = scriptFood(script)
    if food == false then return false, possible end
    if food == nil then return nil, possible end
    if alreadyCooked(script) then return "cooked", possible end
    if script.isIsCookable and not script:isIsCookable() then return false, possible end
    return nil, possible
end

return CookingStates
