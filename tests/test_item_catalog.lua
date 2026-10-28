local Catalog = dofile(ProjectRoot .. '/tests/native_queue/item-catalog/shared/ItemCatalog.lua')
local function script(id, name, hidden, obsolete)
    return {getFullName = function() return id end, getDisplayName = function() return name end,
        isHidden = function() return hidden end, getObsolete = function() return obsolete end}
end
local source = {script('Base.A', 'Same'), script('Mod.B', 'Same'), script('Base.A', 'Same'),
    script('Base.Hidden', 'Hidden', true), script('Base.Old', 'Old', false, true)}
local rows, skipped = Catalog.list({size = function() return #source end, get = function(_, i) return source[i + 1] end})
assert(#rows == 2 and skipped == 2 and rows[1].fullType == 'Base.A' and rows[2].fullType == 'Mod.B',
    'Catalogue lost same-name variants, duplicated a full type or included hidden/obsolete scripts')
local groups = {A = {}, B = {{id = 'last'}}}
for i = 1, 161 do groups.A[i] = {id = i} end
local crates, width, height = Catalog.pack(groups, function(id) return id end)
assert(#crates == 4 and #crates[1].items == 80 and #crates[2].items == 80 and #crates[3].items == 1)
local seen, squares = {}, {}
for _, crate in ipairs(crates) do
    local tile = crate.dx .. ',' .. crate.dy
    assert(not squares[tile] and crate.dx > 1 and crate.dy > 1 and crate.dx < width - 1 and crate.dy < height - 1)
    squares[tile] = true
    for _, item in ipairs(crate.items) do assert(not seen[item.id]); seen[item.id] = true end
end
for i = 1, 161 do assert(seen[i]) end
assert(seen.last and crates[3].label == 'A (3/3)' and crates[4].label == 'B')
assert(Catalog.tsv('a\tb\nc\r') == 'a b c ')
print('Item catalogue planning passed: full-type identity, playable filters, lossless crate pages and aisle bounds.')
