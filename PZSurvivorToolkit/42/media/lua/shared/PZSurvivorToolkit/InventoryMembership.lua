-- Only synchronous enumeration owners retain an index. A later command or
-- dialog confirmation must start with a new one; native action checks stay live.
local Membership = {}

function Membership.contains(index, container, item)
    local items = container:getItems()
    if not index then return items:contains(item) end
    local entry, count = index[container], items:size()
    if not entry or entry.items ~= items or entry.count ~= count then
        entry = {items = items, count = count, members = {}}
        -- Filtered UI rows omit hidden items and cannot define raw membership.
        for offset = 0, count - 1 do entry.members[items:get(offset)] = true end
        index[container] = entry
    end
    return entry.members[item] == true
end

return Membership
