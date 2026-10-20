local Protection = {}
PZSurvivorToolkit = PZSurvivorToolkit or {}
PZSurvivorToolkit.InventoryTransferProtection = Protection

-- Ask the optional owner at use time: its options and hooks can change after load.
function Protection.allowsAutomatic(item)
    local oc = OrganizedCategories
    return not (oc and type(oc.isItemStickingEnabled) == "function"
        and type(oc.isItemStuck) == "function" and oc.isItemStickingEnabled()
        and oc.isItemStuck(item))
end

-- Preserve the user's original pick before a quantity budget flattens its rows.
-- One row with its own children is deliberate. Loose items are one pick when
-- they share both their source container and their displayed stack name.
function Protection.selectionAllowsStuck(rows)
    local selectedRow, loose = nil, {}
    for _, entry in ipairs(rows) do
        if instanceof(entry, "InventoryItem") then
            loose[#loose + 1] = entry
        elseif entry.type ~= "separator" then
            if selectedRow and selectedRow ~= entry then return false end
            selectedRow = entry
        end
    end
    if selectedRow then
        local members = {}
        local first = selectedRow.cleanUILargeStackOptimized and 1 or selectedRow.cleanUIFirstActualIndex or 2
        for i = first, #(selectedRow.items or {}) do members[selectedRow.items[i]] = true end
        for _, item in ipairs(loose) do if not members[item] then return false end end
        return true
    end
    local first = loose[1]
    if not first then return false end
    local source, name = first:getContainer(), first:getName()
    for i = 2, #loose do
        if loose[i]:getContainer() ~= source or loose[i]:getName() ~= name then return false end
    end
    return true
end

return Protection
