local Search = dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/InventorySearch.lua')
local player = {}
getSpecificPlayer = function(index) assert(index == 0);return player end
local labels = {Food = 'Fresh food', Tool = 'Tools'}
getText = function(key) return labels[key:gsub('^IGUI_ItemCat_', '')] or key end
local item = {
    getName = function(_, owner) assert(owner == player);return 'My [special] hammer' end,
    getDisplayName = function() return 'Display hammer' end,
    getType = function() return 'HammerType' end,
    getDisplayCategory = function() return 'Tool' end,
    getCategory = function() return 'Weapon' end,
}
local function matches(mode, name, category)
    return Search.matches(Search.forPane({player=0, searchMode=mode, searchText=name, searchCategoryText=category}), item)
end
assert(matches('name', '[SPECIAL]') and not matches('name', '.*'), 'Search must remain literal and case insensitive')
assert(matches('name', 'display') and matches('name', 'hammertype'), 'Display name and script type fallbacks lost')
assert(matches('category', 'ignored', 'TOOLS') and matches('category', nil, 'Weapon'), 'Localized or base category lost')
assert(matches('both', 'hammer', 'tool') and not matches('both', 'hammer', 'food'), 'Combined search must match both fields')
assert(matches('name', '', 'ignored') and matches('category', 'ignored', ''), 'Inactive search field must be ignored')
assert(not Search.forPane({player=0}), 'Empty query should not activate the filter')

if CleanUIInventoryPaneSource then
    -- Compare the selected provider's actual search helpers, without loading its
    -- entire UI. Singleton groups must retain its public search behavior.
    local first = assert(CleanUIInventoryPaneSource:find('local function CleanUI_normalizeSearchText', 1, true))
    local last = assert(CleanUIInventoryPaneSource:find('function ISInventoryPane:searchContainer', first, true))
    local source = CleanUIInventoryPaneSource:sub(first, last-1) ..
        '\nreturn CleanUI_normalizeSearchText, CleanUI_itemMatchesNameSearch, CleanUI_itemMatchesCategorySearch'
    local chunk = assert(loadstring(source))
    setfenv(chunk, setmetatable({CleanUI_getCachedCategoryText=function(key) return getText('IGUI_ItemCat_'..key) end},
        {__index=_G}))
    local normalize, nameMatches, categoryMatches = chunk()
    local group = {name=item:getName(player), cat=item:getDisplayCategory(), items={item,item}}
    for _, query in ipairs({'', 'HAMMER', '[special]', '.*', 'display', 'HammerType', 'missing'}) do
        assert(matches('name',query) == nameMatches(group,normalize(query)), 'Name search differs from CleanUI: '..query)
    end
    for _, query in ipairs({'', 'tool', 'TOOLS', 'Weapon', 'food', '.*'}) do
        assert(matches('category',nil,query) == categoryMatches(group,normalize(query)), 'Category search differs from CleanUI: '..query)
    end
    local food = {
        getName=function() return 'Food parcel' end, getDisplayName=function() return 'Food parcel' end,
        getType=function() return 'FoodParcel' end, getDisplayCategory=function() return 'Food' end,
        getCategory=function() return 'Food' end,
    }
    local mixed = {name=group.name,cat=group.cat,items={item,item,food}}
    assert(nameMatches(mixed,'hammer') and categoryMatches(mixed,'food'),
        'Actual upstream mixed-group search no longer reproduces the cross-item AND')
    local query = Search.forPane({player=0, searchMode='both',searchText='hammer',searchCategoryText='food'})
    assert(not Search.matches(query,item) and not Search.matches(query,food),
        'Different children must not satisfy the two halves of one query')
    print('Actual CleanUI search contract and mixed-group false-positive reproduction passed.')
end
print('Physical-item inventory search checks passed.')
