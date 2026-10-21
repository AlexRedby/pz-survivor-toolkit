local Duplicates = TestContextMenuDuplicates or dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ContextMenuDuplicates.lua')
local function callback() end
local target = {}
local function option(value)
    return {name = 'Action', onSelect = callback, target = target, param1 = value}
end
local first, duplicate, different = option(1), option(1), option(2)
first.id, duplicate.id = 1, 200
local unique, aliases = Duplicates.collect({first, duplicate, different})
assert(#unique == 2 and unique[1] == first and unique[2] == different and aliases[duplicate] == first)
local reversed = {param1 = 1, target = target, onSelect = callback, name = 'Action'}
assert(#Duplicates.collect({first, reversed}) == 1, 'field iteration/insertion order cannot change exact equality')
local metadata = option(1); metadata.foreign = true
assert(#Duplicates.collect({first, metadata}) == 2, 'arbitrary metadata remains part of identity')
local zero, negativeZero = option(0), option(-1 / math.huge)
assert(#Duplicates.collect({zero, negativeZero}) == 1, 'signed zero arguments compare equal in Lua')
local nan = option(0/0)
assert(#Duplicates.collect({nan, option(0/0)}) == 2, 'NaN metadata must not become an invalid hash key')
local equality = {__eq = function(a, b) return a.value == b.value end}
local equalA, equalB = option(setmetatable({value=3}, equality)), option(setmetatable({value=3}, equality))
local unequal = option(setmetatable({value=4}, equality))
unique, aliases = Duplicates.collect({equalA, equalB, unequal})
assert(#unique == 2 and aliases[equalB] == equalA, 'custom equality must retain the original exact comparison')
for _, mask in ipairs({{}, false, 'hidden'}) do
    local mt = {__eq = function(a,b) return a.value == b.value end, __metatable = mask}
    local a, b = option(setmetatable({value=5},mt)), option(setmetatable({value=5},mt))
    assert(#Duplicates.collect({a,b}) == 1, 'protected metadata equality must still remove exact duplicate actions')
end
local opaqueA, opaqueB = option(1), option(1)
setmetatable(opaqueA, {__metatable=false}); setmetatable(opaqueB, {__metatable=false})
assert(#Duplicates.collect({opaqueA, opaqueB}) == 2, 'protected false metatables must keep opaque mod commands intact')
if TestUserdataA then
    assert(#Duplicates.collect({option(TestUserdataA), option(TestUserdataA)}) == 1)
    assert(#Duplicates.collect({option(TestUserdataA), option(TestUserdataB)}) == 2,
        'distinct native userdata remain distinct even if Java table keys collide')
end
for _, mode in ipairs({"objects", "strings"}) do
for _, count in ipairs({32, 128, 512}) do
    local rows, tracked, passes = {}, {}, 0
    for i=1,count do rows[i]=option(mode == "strings" and ("Base.Item" .. i) or {}); tracked[rows[i]]=true end
    local original = pairs
    pairs = function(value)
        if tracked[value] then passes=passes+1 end
        return original(value)
    end
    local ok, failure = pcall(function()
        local kept = Duplicates.collect(rows)
        assert(#kept == count and passes <= count*3,
            'same-name native-style actions must not compare every pair of distinct arguments')
    end)
    pairs = original
    assert(ok, failure)
end
end
print('Context duplicate checks passed: exact metadata, custom equality, native identities and linear candidate preparation.')
