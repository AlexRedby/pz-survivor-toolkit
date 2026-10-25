local Rows = {}

-- Refresh decorators reorder stacks before render rebuilds pane.items. Both
-- selection and its Shift anchor must use the rows the next render will expose.
local function visit(pane, accept)
    local row = 1
    local limit = pane.MAX_ITEMS_IN_STACK_TO_RENDER or ISInventoryPane.MAX_ITEMS_IN_STACK_TO_RENDER or 50
    for _, group in ipairs(pane.itemslist) do
        if not (pane.equippedCollapsed and group.equipped) then
            if accept(row, group, true) then return end
            row = row + 1
            if group.items and not pane.collapsed[group.name] then
                local first = group.cleanUIFirstActualIndex or 2
                local last = math.min(#group.items, first + limit - 1)
                for index = first, last do
                    if accept(row, group.items[index], false) then return end
                    row = row + 1
                end
            end
        end
    end
end

-- Priority/filter decorators can clear the rendered map before another packet
-- refresh. firstSelect already addresses the current projected view, so recover
-- its physical/group identity there until render publishes pane.items again.
function Rows.captureAnchor(pane)
    if not pane.firstSelect then return end
    if pane.items and #pane.items > 0 then return pane.items[pane.firstSelect] end
    if not pane.itemslist then return end
    local anchor
    visit(pane, function(index, value)
        if index == pane.firstSelect then anchor = value; return true end
    end)
    return anchor
end

function Rows.restoreAnchor(pane, anchor)
    if not anchor then return end
    pane.firstSelect = nil
    local itemAnchor = instanceof(anchor, "InventoryItem")
    visit(pane, function(index, value, group)
        if value == anchor or (group and not itemAnchor and value.items and anchor.items
            and ((anchor.name and value.name == anchor.name)
                or (anchor.items[1] and value.items[1] == anchor.items[1]))) then
            pane.firstSelect = index
            -- This index belongs to the refreshed projection. A later packet
            -- can refresh again before render rebuilds the old physical map.
            if pane.items and pane.items[index] ~= value then table.wipe(pane.items) end
            return true
        end
    end)
end

function Rows.restoreSelection(pane, saved)
    table.wipe(pane.selected)
    local groups = saved._cleanUISelectedGroups or {}
    visit(pane, function(index, value, group)
        if group then
            local display = value.cleanUIDisplayItem or value.firstItem or (value.items and value.items[1])
            if (value.name and groups[value.name]) or (display and saved[display] == "group") then
                pane.selected[index] = value
            end
        elseif saved[value] and saved[value] ~= "group" then
            pane.selected[index] = value
        end
    end)
end

return Rows
