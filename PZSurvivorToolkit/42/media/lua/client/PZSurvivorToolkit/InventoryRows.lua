local Rows = {}

-- Refresh decorators reorder stacks before render rebuilds pane.items. Resolve the
-- old physical item/group against the rows that the next render will expose.
function Rows.restoreAnchor(pane, anchor)
    if not anchor then return end
    pane.firstSelect = nil
    local itemAnchor = instanceof(anchor, "InventoryItem")
    local row = 1
    local limit = pane.MAX_ITEMS_IN_STACK_TO_RENDER or ISInventoryPane.MAX_ITEMS_IN_STACK_TO_RENDER or 50
    for _, group in ipairs(pane.itemslist) do
        if not (pane.equippedCollapsed and group.equipped) then
            if group == anchor or (not itemAnchor and group.items and anchor.items
                and ((anchor.name and group.name == anchor.name)
                    or (anchor.items[1] and group.items[1] == anchor.items[1]))) then
                pane.firstSelect = row
                return
            end
            row = row + 1
            if group.items and not pane.collapsed[group.name] then
                local first = group.cleanUIFirstActualIndex or 2
                local last = math.min(#group.items, first + limit - 1)
                for index = first, last do
                    if itemAnchor and group.items[index] == anchor then
                        pane.firstSelect = row
                        return
                    end
                    row = row + 1
                end
            end
        end
    end
end

return Rows
