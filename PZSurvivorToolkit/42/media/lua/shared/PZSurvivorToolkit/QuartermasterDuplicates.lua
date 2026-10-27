-- Duplicate identity is the full script type: skill books retain separate volumes.
-- Only direct contents count, matching the compartment configured by the player.
local Duplicates = {}
local Groups = require "PZSurvivorToolkit/ContainerGroups"

function Duplicates.enabled(obj, ci)
    if not obj or ci == nil then return false end
    local group = Groups.resolve(obj, ci)
    if group then return group.configuration.noDuplicates == true end
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

local function acceptsContainer(container, item)
    local fullType, items = item:getFullType(), container:getItems()
    for index = 0, items:size() - 1 do
        local existing = items:get(index)
        if existing ~= item and existing:getFullType() == fullType then return false end
    end
    return true
end

function Duplicates.accepts(container, item, box)
    if not acceptsContainer(container, item) then return false end
    local id = box and Groups.link(box.obj, box.ci)
    if id and box.groupPeers then
        for _, peer in ipairs(box.groupPeers) do
            if peer.container ~= container and Groups.link(peer.obj, peer.ci) == id
                and not acceptsContainer(peer.container, item) then return false end
        end
    end
    return true
end

return Duplicates
