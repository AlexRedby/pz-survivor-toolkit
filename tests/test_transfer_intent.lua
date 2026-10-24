-- Match the game sandbox: native Kahlua has no global next().
local savedNext = next
next = nil
local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/'
local nativeRequire = require
local retention = {isRetained=function(item) return item.retained == true end}
require = function(name)
    if name == 'PZSurvivorToolkit/ItemRetention' then return retention end
    return nativeRequire(name)
end
PZSurvivorToolkit = {ItemRetention=retention}
instanceof = function(value, class)
    return class == 'InventoryItem' and type(value) == 'table' and value.isItem == true
end
local P = dofile(root .. 'PZSurvivorToolkit/InventoryTransferProtection.lua')

local function item(name, source)
    return {isItem=true, name=name, source=source, retained=true,
        getName=function(self) return self.name end,
        getContainer=function(self) return self.source end}
end
local first, second = {}, {}
local hammer, beans, other = item('Hammer', first), item('Beans', second), item('Hammer', first)
local separator = {type='separator', items={other, other}}
local rows = {{items={hammer, hammer}}, {items={beans, beans}}, separator}
local function exact(actual, expected, message)
    assert(#actual == #expected, message .. ': item count')
    for index, value in ipairs(expected) do assert(actual[index] == value, message .. ': item identity') end
end
local function pack(...) return {n=select('#', ...), ...} end

exact(P.items(rows), {hammer, beans}, 'mixed types and real sources remain an explicit selection')
exact(P.items({separator, hammer, {items={hammer, hammer, beans}}, beans}),
    {hammer, beans}, 'flattening deduplicates physical copies and ignores separators')
exact(P.items({{items={hammer, beans}, cleanUILargeStackOptimized=true}}),
    {hammer, beans}, 'optimized stacks have no duplicate header')
exact(P.items({{items={other, hammer, beans}, cleanUIFirstActualIndex=2}}),
    {hammer, beans}, 'explicit first actual index excludes the header')
exact(P.items({{items={hammer, beans}, cleanUIFirstActualIndex=1}}),
    {hammer, beans}, 'headerless stacks include their first actual item')
exact(P.items({}), {}, 'empty rows')
exact(P.items({separator}), {}, 'separator-only rows')

assert(P.containsSelection(rows, {hammer, beans}), 'multirow membership accepts different types and sources')
assert(P.containsSelection(rows, {beans}), 'the actual transfer may contain a selected subset')
assert(P.containsSelection(rows, {{items={hammer, hammer, beans}}}), 'membership also flattens transfer rows')
assert(not P.containsSelection(rows, {other}), 'same name and source do not confer physical identity')
assert(not P.containsSelection(rows, {hammer, other}), 'one foreign reference rejects the transfer list')
assert(not P.containsSelection(rows, {}), 'an empty transfer is not explicit intent')
assert(not P.containsSelection({}, {hammer}), 'an empty source selection grants no intent')
assert(not P.containsSelection({separator}, {other}), 'separator contents grant no intent')

local selected = {hammer, beans}
assert(not P.selectionAllowsStuck(selected, 0), 'shape alone cannot authorize a callback array')
P.rememberSelection(selected, 0)
assert(P.selectionAllowsStuck(selected, 0), 'remembered exact callback array is deliberate')
assert(not P.selectionAllowsStuck({hammer, beans}, 0), 'a copy cannot inherit remembered array intent')
assert(not P.selectionAllowsStuck(selected, 1), 'another player cannot inherit remembered selection')
selected[2] = other
assert(not P.selectionAllowsStuck(selected, 0), 'reusing the remembered array for a foreign item invalidates intent')
local grouped = {{items={hammer, hammer, beans}}}
P.rememberSelection(grouped, 0)
assert(P.selectionAllowsStuck(grouped, 0), 'grouped callback array is deliberate')
grouped[1].items[3] = other
assert(not P.selectionAllowsStuck(grouped, 0), 'changing a remembered group child invalidates intent')
local empty = {}
P.rememberSelection(empty, 0)
assert(not P.selectionAllowsStuck(empty, 0), 'remembering an empty selection grants no intent')
local separators = {separator}
P.rememberSelection(separators, 0)
assert(not P.selectionAllowsStuck(separators, 0), 'remembering separator-only rows grants no intent')

local outerRows, innerRows = {hammer, beans}, {other}
local returned = pack(P.withSelection(outerRows, 0, function(a, b, c)
    assert(a == 'argument' and b == nil and c == 7, 'scope forwards every callback argument')
    assert(P.selectionAllowsStuck({hammer, beans}, 0), 'active intent follows physical selected items')
    assert(P.selectionAllowsStuck({beans}, 0), 'active intent permits a selected subset')
    assert(not P.selectionAllowsStuck({hammer, other}, 0), 'active scope rejects foreign items')
    assert(not P.selectionAllowsStuck({hammer}, 1), 'active scope is bound to the player')
    assert(not P.selectionAllowsStuck({}, 0), 'active scope does not bless empty arrays')
    P.withSelection(innerRows, 0, function()
        assert(P.selectionAllowsStuck({other}, 0), 'nested scope uses the inner exact selection')
        assert(not P.selectionAllowsStuck({hammer}, 0), 'nested selection does not inherit outer items')
    end)
    assert(P.selectionAllowsStuck({hammer, beans}, 0), 'successful nested scope restores outer selection')
    assert(not P.selectionAllowsStuck({other}, 0), 'successful nested scope retires inner selection')
    local ok, err = pcall(function()
        P.withSelection(innerRows, 0, function() error('nested intent failure') end)
    end)
    assert(not ok and tostring(err):find('nested intent failure', 1, true), 'nested error propagates')
    assert(P.selectionAllowsStuck({hammer}, 0), 'failed nested scope restores outer selection')
    assert(not P.selectionAllowsStuck({other}, 0), 'failed nested scope retires inner selection')
    return 'result', nil, 19, nil
end, 'argument', nil, 7))
assert(returned.n == 4 and returned[1] == 'result' and returned[2] == nil
    and returned[3] == 19 and returned[4] == nil, 'scope preserves all returns including nil slots')
assert(not P.selectionAllowsStuck({hammer, beans}, 0), 'completed scope leaves no ambient intent')
local ok, err = pcall(function()
    P.withSelection(outerRows, 0, function() error('outer intent failure') end)
end)
assert(not ok and tostring(err):find('outer intent failure', 1, true), 'outer error propagates')
assert(not P.selectionAllowsStuck({hammer}, 0), 'failed scope leaves no ambient intent')

local changed = {hammer}
P.withSelection(changed, 0, function()
    changed[2] = other
    assert(P.selectionAllowsStuck({hammer}, 0), 'active scope retains its original physical selection')
    assert(not P.selectionAllowsStuck({other}, 0), 'mutating caller rows cannot widen active intent')
end)
assert(not P.selectionAllowsStuck({other}, 0), 'mutated scope also cleans up')
print('Transfer intent: exact UI selection identity, grouped rows, player ownership, bounded scopes and error cleanup passed.')

next = savedNext
