-- Project mixed category/tag/retention stacks into homogeneous rows before selection restore.
-- Native/CleanUI continue to own grouping, sorting and rendering.
local Groups = {}
local Tags = require "PZSurvivorToolkit/ItemTags"
local Retention = require "PZSurvivorToolkit/ItemRetention"

local function firstActual(group)
    if group.cleanUIFirstActualIndex then return group.cleanUIFirstActualIndex end
    if group.cleanUILargeStackOptimized then return 1 end
    return #group.items > 1 and group.items[1] == group.items[2] and 2 or 1
end

local function project(source, items, category, first, key)
    local row = {}
    for key, value in pairs(source) do row[key] = value end
    row.items, row.cat = {}, category
    row.toolkitCategoryBaseName = source.toolkitCategoryBaseName or source.name
    row.name = (source.name or '')..string.char(31)..(key or category)
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
    local priorSplit, selectedPrevious = {}, {}
    -- Vanilla saves only a physical header marker. Recover the previous split
    -- row's name so that marker cannot become selection of the whole raw stack.
    for _, previous in ipairs(pane.toolkitCategoryGroupRows or {}) do
        if previous.toolkitCategoryBaseName then
            priorSplit[previous.toolkitCategoryBaseName] = true
            if saved and (saved[previous.items[1]] == 'group' or selectedGroups and selectedGroups[previous.name]) then
                selectedGroups = selectedGroups or {}
                saved._cleanUISelectedGroups = selectedGroups
                selectedGroups[previous.name] = true
                selectedPrevious[#selectedPrevious + 1] = previous
            end
        end
    end
    for _, group in ipairs(source) do
        if group.type == 'separator' or not group.items then result[#result + 1] = group
        else
            local first, buckets, order, categories, counts = firstActual(group), {}, {}, {}, {}
            for index = first, #group.items do
                local item = group.items[index]
                local category = tostring(item:getDisplayCategory() or item:getCategory() or '')
                local key = category
                if Tags.enabled() then key = key..string.char(30)..Tags.signature(Tags.forItem(item)) end
                if Retention.isRetained(item) then key = key..string.char(29).."retained" end
                if not buckets[key] then
                    buckets[key]={};order[#order + 1]=key;categories[key]=category
                    counts[category]=(counts[category] or 0)+1
                end
                buckets[key][#buckets[key] + 1] = item
            end
            if #order <= 1 then result[#result + 1] = group
            else
                changed = true
                local selectedSplit = priorSplit[group.name]
                local function rowKey(key) return counts[categories[key]] > 1 and key or categories[key] end
                for _, key in ipairs(order) do
                    if selectedGroups and selectedGroups[(group.name or '')..string.char(31)..rowKey(key)] then
                        selectedSplit = true
                    end
                end
                local selected = saved and (selectedGroups and selectedGroups[group.name]
                    or not selectedSplit and saved[group.items[1]] == 'group')
                for _, key in ipairs(order) do
                    local row = project(group, buckets[key], categories[key], first, rowKey(key))
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
    local rowsByName, recovered, needsRecovery = {}, {}, false
    for _, row in ipairs(result) do if row.name then rowsByName[row.name] = row end end
    for _, previous in ipairs(selectedPrevious) do
        local current = rowsByName[previous.name]
        local same = current and current.items ~= nil
        if same then
            local members, count = {}, 0
            for index = firstActual(previous), #previous.items do
                members[previous.items[index]], count = true, count + 1
            end
            local currentCount = 0
            for index = firstActual(current), #current.items do
                currentCount = currentCount + 1
                if not members[current.items[index]] then same = false end
            end
            same = same and currentCount == count
        end
        if not same then
            needsRecovery = true
            selectedGroups[previous.name] = nil
            -- Projection may have inferred a group marker on a new display item
            -- solely because this name survived. That item need not be selected.
            local display = current and (current.cleanUIDisplayItem or current.firstItem
                or current.items and current.items[1])
            if display and saved[display] == 'group' then saved[display] = nil end
            for index = firstActual(previous), #previous.items do
                local item = previous.items[index]
                saved[item], recovered[item] = true, true
            end
        end
    end
    -- Exact item markers cannot restore through a collapsed row's hidden
    -- children. Keep a whole-row marker when it is exact; expose only partial
    -- rows whose recovered physical copies need individual selection.
    if needsRecovery then
        for _, row in ipairs(result) do
            if row.items then
                local count, total, affected = 0, 0, false
                for index = firstActual(row), #row.items do
                    local item = row.items[index]
                    total = total + 1
                    affected = affected or recovered[item] == true
                    if saved and saved[item] and saved[item] ~= 'group' then count = count + 1 end
                end
                if affected then
                    local display = row.cleanUIDisplayItem or row.firstItem or row.items[1]
                    if count == total then
                        selectedGroups[row.name] = true
                        for index = firstActual(row), #row.items do saved[row.items[index]] = nil end
                        saved[display] = 'group'
                    else
                        selectedGroups[row.name] = nil
                        if saved[display] == 'group' then saved[display] = nil end
                        if pane.collapsed then pane.collapsed[row.name] = false end
                    end
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
