-- Search/sort must never rebuild the warehouse projection or access world inventories.
local View = assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ManifestView.lua'))()
local described, sorts = 0, 0
local originalSort = table.sort
local tags = {label = function(id) return id end,
    matches = function(actual, selected)
        for _, tag in ipairs(actual) do if tag == selected[1] then return true end end
        return false
    end}
local view = View.new(function(entry)
    described = described + 1
    return entry.name or entry.ft, entry.cat or '', {entry.cat or 'other'}
end, tags)
local payload = {revision = 1, containers = {}}
for c = 1, 100 do
    local entries = {}
    for i = 1, 100 do
        local key = 'type' .. i
        entries[key] = {ft = key, cat = i % 2 == 0 and 'material' or 'food', n = c}
    end
    payload.containers['box' .. c] = {name = 'Crate ' .. c, loaded = c % 2 == 0, entries = entries}
end
assert(view:setPayload(payload))
assert(described == 100, 'presentation is resolved once per distinct identity, not per source record')
table.sort = function(...) sorts = sorts + 1; return originalSort(...) end
local rows, count = view:select('', nil, 'count', false)
assert(#rows == 100 and count == 505000 and #rows[1].locations == 100)
assert(sorts == 1)
for _, query in ipairs({'t', 'ty', 'type', 'type1', 'type100', ''}) do view:select(query, nil, 'count', false) end
assert(sorts == 1 and described == 100, 'typing must reuse aggregation and sort')
assert(view:setPayload(payload) == false)
assert(#view:select('', 'food', 'count', false) == 50)
assert(#view:select('type100', 'food', 'count', false) == 0)
assert(#view:select('TYPE100', 'material', 'count', false) == 1)
view:select('', nil, 'name', true); view:select('1', nil, 'name', true)
assert(sorts == 2, 'sort cached separately for each order')
local custom = {containers = {a = {entries = {
    default = {ft = 'Base.Thread', n = 2, cat = 'material'},
    custom = {ft = 'Base.Thread', name = 'My thread', n = 3, cat = 'material'},
    sameLabel = {ft = 'Other.Thread', name = 'Base.Thread', n = 4, cat = 'material'},
}}}}
assert(view:setPayload(custom))
local nextRows, total = view:select('', nil, 'name', true)
assert(#nextRows == 3 and total == 9, 'custom names and homonymous types remain distinct')
assert(#view:select('my thread', nil, 'name', true) == 1)
assert(view:setPayload({containers = {}}))
assert(#view:select('', nil, 'name', true) == 0 and #view.tagOptions == 0, 'removed sources must disappear')
table.sort = originalSort
print('Manifest view: 10,000 source records, cached query/order, tag filtering, locations and distinct identities passed.')

local revision=1;tags.revision=function()return revision end
assert(view:setPayload(payload))
local before=described
assert(not view:setPayload(payload))
revision=2
assert(view:setPayload(payload) and described==before+100,
 'unchanged payload ignored changed tag catalog/type assignments')
