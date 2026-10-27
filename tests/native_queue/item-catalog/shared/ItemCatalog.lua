-- Test-only planning; no world or inventory writes in this module.
local Catalog = {world = 'PZSTItemCatalog', version = 1, perCrate = 80}

function Catalog.list(scripts)
    local result, seen, skipped = {}, {}, 0
    for i = 0, scripts:size() - 1 do
        local script = scripts:get(i)
        local fullType = script:getFullName()
        if script:isHidden() or script:getObsolete() then
            skipped = skipped + 1
        elseif not seen[fullType] then
            seen[fullType] = true
            result[#result + 1] = {fullType = fullType, name = script:getDisplayName()}
        end
    end
    table.sort(result, function(a, b)
        return a.name == b.name and a.fullType < b.fullType or a.name < b.name
    end)
    return result, skipped
end

function Catalog.pack(groups, label)
    local categories, crates = {}, {}
    for category in pairs(groups) do categories[#categories + 1] = category end
    table.sort(categories, function(a, b)
        local left, right = label(a), label(b)
        return left == right and a < b or left < right
    end)
    for _, category in ipairs(categories) do
        local items = groups[category]
        local pages = math.ceil(#items / Catalog.perCrate)
        for page = 1, pages do
            local crate = {category = category, label = label(category), items = {}}
            if pages > 1 then crate.label = crate.label .. ' (' .. page .. '/' .. pages .. ')' end
            for i = (page - 1) * Catalog.perCrate + 1, math.min(page * Catalog.perCrate, #items) do
                crate.items[#crate.items + 1] = items[i]
            end
            crates[#crates + 1] = crate
        end
    end
    assert(#crates > 0, 'No playable items in the loaded scripts')
    local columns = math.ceil(math.sqrt(#crates))
    local rows = math.ceil(#crates / columns)
    assert(columns <= 40 and rows <= 40, 'Catalogue exceeds the loaded test platform')
    for index, crate in ipairs(crates) do
        crate.dx, crate.dy = 2 + ((index - 1) % columns) * 2, 2 + math.floor((index - 1) / columns) * 2
    end
    return crates, columns * 2 + 3, rows * 2 + 3
end

function Catalog.tsv(value)
    return tostring(value or ''):gsub('[\t\r\n]', ' ')
end

return Catalog
