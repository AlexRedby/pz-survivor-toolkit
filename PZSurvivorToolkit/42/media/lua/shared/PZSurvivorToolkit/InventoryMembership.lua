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

-- getItemById searches by ID recursively, unlike getItems():contains(object).
-- Keep that distinction for callers that allow a replicated same-ID replacement.
function Membership.containsId(index, container, id)
    if not index then return container:getItemById(id) ~= nil end
    local roots = index.recursiveIds
    if not roots then roots = {}; index.recursiveIds = roots end
    local entry = roots[container]
    if not entry then
        entry = {ids = {}, pending = {{container = container, offset = 0}}, seen = {[container] = true}}
        roots[container] = entry
    end
    if entry.ids[id] then return true end
    -- Resume the native depth-first order from the last lookup. A single item
    -- near the head must not force an eager scan of a huge unrelated tail.
    while #entry.pending > 0 do
        local frame = entry.pending[#entry.pending]
        if frame.child then
            local child = frame.child:getItemContainer()
            frame.child = nil
            if child and not entry.seen[child] then
                entry.seen[child] = true
                entry.pending[#entry.pending + 1] = {container = child, offset = 0}
            end
        else
            frame.items = frame.items or frame.container:getItems()
            if frame.offset >= frame.items:size() then
                table.remove(entry.pending)
            else
                local item = frame.items:get(frame.offset)
                frame.offset = frame.offset + 1
                local currentId = item:getID()
                entry.ids[currentId] = true
                if instanceof(item, "InventoryContainer") then frame.child = item end
                if currentId == id then return true end
            end
        end
    end
    return false
end

return Membership
