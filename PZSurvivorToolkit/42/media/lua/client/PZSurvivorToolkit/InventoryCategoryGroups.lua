-- Project mixed-category stacks into homogeneous rows before selection restore.
-- Native/CleanUI continue to own grouping, sorting and rendering.
local Groups = {}

local function firstActual(group)
    if group.cleanUIFirstActualIndex then return group.cleanUIFirstActualIndex end
    if group.cleanUILargeStackOptimized then return 1 end
    return #group.items > 1 and group.items[1] == group.items[2] and 2 or 1
end

local function project(source, items, category, first)
    local row = {}
    for key, value in pairs(source) do row[key] = value end
    row.items, row.cat = {}, category
    row.toolkitCategoryBaseName = source.toolkitCategoryBaseName or source.name
    row.name = (source.name or '')..string.char(31)..category
    row.firstItem, row.cleanUIDisplayItem = items[1], items[1]
    row.realCount, row.count, row.weight, row.equippedWeight = #items, #items + 1, 0, 0
    row.cleanUIFirstActualIndex, row.cleanUILargeStackOptimized = first, false
    row.cleanUIStackCountSuffix = ' ('..#items..')'
    row.cleanUIWeightText, row.cleanUITooltipWeight, row._cleanUICategoryTextCache = nil, nil, nil
    row.cleanUIWeightKnown, row.cleanUITooltipWeightKnown = false, false
    if first == 2 then row.items[1] = items[1] end
    for _, item in ipairs(items) do
        row.items[#row.items + 1] = item
        row.weight = row.weight + item:getUnequippedWeight()
        if source.equipped then row.equippedWeight = row.equippedWeight + item:getEquippedWeight() end
    end
    return row
end

function Groups.split(pane, saved)
    local source = pane.itemslist
    if not source or source == pane.toolkitCategoryGroupRows then return false end
    local result, changed = {}, false
    local selectedGroups = saved and saved._cleanUISelectedGroups
    local priorSplit = {}
    -- Vanilla saves only a physical header marker. Recover the previous split
    -- row's name so that marker cannot become selection of the whole raw stack.
    for _, previous in ipairs(pane.toolkitCategoryGroupRows or {}) do
        if previous.toolkitCategoryBaseName then
            priorSplit[previous.toolkitCategoryBaseName] = true
            if saved and saved[previous.items[1]] == 'group' then
                selectedGroups = selectedGroups or {}
                saved._cleanUISelectedGroups = selectedGroups
                selectedGroups[previous.name] = true
            end
        end
    end
    for _, group in ipairs(source) do
        if group.type == 'separator' or not group.items then result[#result + 1] = group
        else
            local first, buckets, order = firstActual(group), {}, {}
            for index = first, #group.items do
                local item = group.items[index]
                local category = tostring(item:getDisplayCategory() or item:getCategory() or '')
                if not buckets[category] then buckets[category]={};order[#order + 1]=category end
                buckets[category][#buckets[category] + 1] = item
            end
            if #order <= 1 then result[#result + 1] = group
            else
                changed = true
                local selectedSplit = priorSplit[group.name]
                for _, category in ipairs(order) do
                    if selectedGroups and selectedGroups[(group.name or '')..string.char(31)..category] then
                        selectedSplit = true
                    end
                end
                local selected = saved and (selectedGroups and selectedGroups[group.name]
                    or not selectedSplit and saved[group.items[1]] == 'group')
                for _, category in ipairs(order) do
                    local row = project(group, buckets[category], category, first)
                    if pane.collapsed and pane.collapsed[row.name] == nil then
                        local collapsed = pane.collapsed[group.name]
                        pane.collapsed[row.name] = collapsed ~= false
                    end
                    if selected or selectedGroups and selectedGroups[row.name] then
                        saved[row.items[1]] = 'group'
                        if selectedGroups then selectedGroups[row.name] = true end
                    end
                    result[#result + 1] = row
                end
            end
        end
    end
    if changed then
        pane.itemslist = result
        if pane.itemSortFunc then table.sort(result, pane.itemSortFunc) end
    end
    pane.toolkitCategoryGroupRows = pane.itemslist
    return changed
end

return Groups
