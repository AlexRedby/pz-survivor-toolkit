local Membership = TestInventoryMembership or dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/InventoryMembership.lua')
instanceof = function(value, kind) return value.class == kind end
local reads = 0
local function item(id) return {getID = function() return id end} end
local function container(values)
    local items = {
        size = function() return #values end,
        get = function(_, i) reads = reads + 1; return values[i + 1] end,
        contains = function(_, item) for _, value in ipairs(values) do if value == item then return true end end return false end,
    }
    return {getItems = function() return items end}
end
local childValues = {item(-4), item(20)}
local child = container(childValues)
local bag = {class = 'InventoryContainer', getID = function() return 7 end, getItemContainer = function() return child end}
local emptyBag = {class = 'InventoryContainer', getID = function() return 8 end, getItemContainer = function() end}
local direct = item(1)
local root = container({direct, bag, emptyBag})
local index = {}
assert(Membership.containsId(index, root, 1) and Membership.containsId(index, root, 7))
assert(Membership.containsId(index, root, -4) and Membership.containsId(index, root, 20))
assert(Membership.containsId(index, root, 8) and not Membership.containsId(index, root, 99))
assert(reads == 5, 'one recursive source enumeration serves every ID lookup')
assert(Membership.contains(index, root, direct), 'direct object membership remains a separate contract')
assert(not Membership.contains(index, root, item(1)), 'direct membership must reject a same-ID different object')
assert(Membership.containsId(index, root, item(1):getID()), 'recursive membership uses ID existence, not object identity')
assert(not Membership.contains(index, root, childValues[1]), 'direct membership cannot accept a nested item')
childValues[1] = item(30)
assert(not Membership.containsId({}, root, -4) and Membership.containsId({}, root, 30),
    'new enumeration sees same-size replacement in a nested container')
local large = {item(99)}
for i = 1, 4096 do large[#large + 1] = item(1000 + i) end
reads = 0
local largeRoot, prefix = container(large), {}
assert(Membership.containsId(prefix, largeRoot, 99) and reads == 1,
    'one selected item at the head must not enumerate an unrelated large tail')
assert(Membership.containsId(prefix, largeRoot, 1001) and reads == 2,
    'the next lookup resumes from the saved prefix')
assert(Membership.containsId(prefix, largeRoot, 99) and reads == 2,
    'already seen IDs must not revisit the prefix')
local liveCalls = 0
root.getItemById = function(_, id) liveCalls = liveCalls + 1; if id == 17 then return direct end end
assert(Membership.containsId(nil, root, 17) and not Membership.containsId(nil, root, 18))
assert(liveCalls == 2, 'without an enumeration index, native recursive ID membership stays live')
print('Inventory membership: direct objects, recursive IDs, nested replacement and one-pass enumeration passed.')
