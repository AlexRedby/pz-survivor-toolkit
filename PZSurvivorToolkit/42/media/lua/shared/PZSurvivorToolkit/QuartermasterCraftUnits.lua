-- Convert native item inputs to the units used by CraftRecipeData.consumeInputFromItems.
-- Item validity and the final craft count remain native responsibilities.
local Units = {}

local function positive(value)
    return type(value) == "number" and value == value and value > 0 and value < math.huge
end

function Units.input(input)
    local per = input:getIntAmount()
    if not positive(per) then return nil end
    local types, seen = {}, {}
    local scripts = input:getPossibleInputItems()
    for i = 0, scripts:size() - 1 do
        local fullType = scripts:get(i):getFullName()
        if not seen[fullType] then
            seen[fullType] = true
            types[#types + 1] = fullType
        end
    end
    return { input = input, per = per, exclusive = input:isExclusive(), types = types }
end

function Units.item(entry, index, item)
    local ok, candidate = pcall(function()
        local input, fullType = entry.input, item:getFullType()
        local counted = input:isItemCount()
        local uses = counted and 1 or item:getCurrentUses()
        local scale = input:getRelativeScale(fullType)
        if not positive(uses) or not positive(scale) then return nil end
        -- Match CraftRecipeManager.consumesEntireItem. isUsesPartialItem only identifies
        -- drainable/food UI inputs; generic multi-use items may retain uses as well.
        local entire = counted or input:isDestroy()
        if not entire and input:hasFlag(InputFlag.DontReplace) then
            entire = item:getReplaceOnUse() ~= nil or item:getScriptItem():getReplaceOnDeplete() ~= nil
        end
        return { input = index, fullType = fullType, uses = uses, scale = scale,
            partial = not entire }
    end)
    if ok then return candidate end
    return nil
end

return Units
