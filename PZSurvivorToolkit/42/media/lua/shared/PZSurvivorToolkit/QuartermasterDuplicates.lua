-- Duplicate identity is the full script type: skill books retain separate volumes.
-- Only direct contents count, matching the compartment configured by the player.
local Duplicates = {}

function Duplicates.enabled(obj, ci)
    if not obj or ci == nil then return false end
    local values = obj:getModData().LSBoxNoDuplicates
    return type(values) == "table" and values[tostring(ci)] == true
end

function Duplicates.contents(container)
    local types, items = {}, container:getItems()
    for index = 0, items:size() - 1 do
        local item = items:get(index)
        local fullType = item:getFullType()
        if types[fullType] == nil then types[fullType] = item end
    end
    return types
end

function Duplicates.accepts(container, item)
    local fullType, items = item:getFullType(), container:getItems()
    for index = 0, items:size() - 1 do
        local existing = items:get(index)
        if existing ~= item and existing:getFullType() == fullType then return false end
    end
    return true
end

return Duplicates
