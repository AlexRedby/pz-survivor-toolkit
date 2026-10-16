local shared = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/'
package.path = shared .. '?.lua;' .. package.path
local enabled = true
PZSurvivorToolkit = {Settings = {itemTags = function() return enabled end}}
Events = {OnGameBoot = {Add = function() end}}
isClient, isServer = function() return false end, function() return false end
getFileReader = function() return nil end
local function list(values)
    return {size = function() return #values end, get = function(_, index) return values[index + 1] end}
end
local function union(target, source)
    for key, value in pairs(source or {}) do if value then target[key] = value end end
end
LootSorter = {
    getCategories = function() return {'foodNonPerishable_candySnack', 'farmingSeed', 'foodPerishable_vegetable', 'Food'} end,
    modDataHasDesignation = function() return false end,
    linkResolves = function(preset, link) return preset and (link == true or preset.gen == link) end,
    resolveEffective = function(cats, items, links, presets)
        local resultCats, resultItems = {}, {}
        union(resultCats, cats); union(resultItems, items)
        for name, link in pairs(links or {}) do
            local preset = presets and presets[name]
            if LootSorter.linkResolves(preset, link) then union(resultCats, preset.cats); union(resultItems, preset.items) end
        end
        return resultCats, resultItems
    end,
}
if NativeQuartermasterLuaRoot then
    dofile(NativeQuartermasterLuaRoot .. '/shared/LootSorter_Plan.lua')
else
    -- The installed planner exercises capacity and carrier details below; this fallback checks the adapter contract.
    function LootSorter.planTrips(items, boxes, carriers, _, accepts)
        local trip, leftovers = {perBox = {}, visit = {}}, {}
        for _, item in ipairs(items) do
            local destination
            for _, box in ipairs(boxes) do if box.items and box.items[item.name] then destination = box; break end end
            if not destination then
                for _, box in ipairs(boxes) do if box.cats and box.cats[item.cat] then destination = box; break end end
            end
            if destination and (not accepts or accepts(carriers[1].ref, item.ref)) then
                if not trip.perBox[destination] then trip.perBox[destination] = {}; trip.visit[#trip.visit + 1] = destination end
                trip.perBox[destination][#trip.perBox[destination] + 1] = {item = item, carrier = carriers[1]}
            else leftovers[#leftovers + 1] = item end
        end
        return {trips = #trip.visit > 0 and {trip} or {}, leftover = leftovers}
    end
end
local Tags = require 'PZSurvivorToolkit/ItemTags'
local Rules = require 'PZSurvivorToolkit/QuartermasterTagRules'
farming_vegetableconf = {props = {
    Sunflower = {seedName = 'Base.SunflowerSeeds'},
    Potatoes = {seedName = 'Base.Potato', seedTypes = {'Base.Potato', 'Base.PotatoSeed'}},
    Carrots = {seedName = 'Base.CarrotSeed'},
}}
local function item(fullType, category, name, weight, doubleClick)
    local script = {getFullName = function() return fullType end,
        getDisplayCategory = function() return category end,
        getDoubleClickRecipe = function() return doubleClick end}
    local ref = {getFullType = function() return fullType end,
        getDisplayCategory = function() return category end,
        getScriptItem = function() return script end}
    return {ref = ref, cat = category, name = name, weight = weight or 1}, script
end
local sunflower = item('base.SunflowerSeeds', 'foodNonPerishable_candySnack', 'Sunflower seeds')
local candy = item('Base.Candy', 'foodNonPerishable_candySnack', 'Candy')
local potato = item('Base.Potato', 'foodPerishable_vegetable', 'Potato')
local full, fullScript = item('Base.CarrotBagSeed2', 'farmingSeed', 'Carrot seed packet', 1, 'OpenPacketOfSeeds')
local empty, emptyScript = item('Base.CarrotBagSeed2_Empty', 'farmingSeed', 'Empty carrot seed packet')
local seedScript = {getFullName = function() return 'base.CarrotSeed' end}
local recipe = {
    getInputs = function() return list({{getPossibleInputItems = function() return list({fullScript}) end}}) end,
    getOutputs = function() return list({{getPossibleResultItems = function() return list({seedScript, emptyScript}) end}}) end,
}
ScriptManager = {instance = {getCraftRecipe = function(_, name) assert(name == 'Base.OpenPacketOfSeeds'); return recipe end}}
Rules.installClient()
Rules.localPresets = {}
local seedRule = {mode = 'all', include = {'seed'}, exclude = {}}
local function box(rule, manual, named, links, presets)
    local cats = manual or {}
    local md = {LSBox = {['0'] = cats}, [Rules.FIELD] = rule and {['0'] = rule} or {}}
    local object = {hasModData = function() return true end, getModData = function() return md end}
    Rules.indexSquare({getObjects = function() return list({object}) end})
    local effective, items = LootSorter.resolveEffective(cats, named or {}, links, presets)
    return {ref = object, cats = effective, items = items, capacity = 100, used = 0, dist = 1}
end
local carrier = {ref = {}, factor = 1, space = 100}
local function checkPlan(items, boxes, carriers, budget, accepts)
    local categories, categoryTables, knownItems, knownBoxes = {}, {}, {}, {}
    for _, record in ipairs(items) do categories[record], knownItems[record] = record.cat, true end
    for _, record in ipairs(boxes) do categoryTables[record], knownBoxes[record] = record.cats, true end
    local plan = LootSorter.planTrips(items, boxes, carriers or {carrier}, budget or 100, accepts)
    for _, record in ipairs(items) do assert(record.cat == categories[record], 'planner left a transient item category') end
    for _, record in ipairs(boxes) do assert(record.cats == categoryTables[record], 'planner replaced original category-table identity') end
    local destinations = {}
    for _, trip in ipairs(plan.trips) do
        for destination, entries in pairs(trip.perBox) do
            assert(knownBoxes[destination], 'planner cloned a box record')
            for _, entry in ipairs(entries) do
                assert(knownItems[entry.item], 'planner cloned an item record')
                assert(not destinations[entry.item], 'item routed twice')
                destinations[entry.item] = destination
            end
        end
    end
    for _, record in ipairs(plan.leftover) do assert(knownItems[record], 'planner cloned a leftover record') end
    return destinations, plan
end
local seeds = box(seedRule)
local destinations, plan = checkPlan({sunflower, candy, potato, full, empty}, {seeds})
assert(destinations[sunflower] == seeds and destinations[potato] == seeds and destinations[full] == seeds,
    'native item-aware seed rule missed planting inputs')
assert(not destinations[candy] and not destinations[empty] and #plan.leftover == 2,
    'seed rule admitted candy or empty packets through shared legacy categories')
local uncategorized = item('Base.SunflowerSeeds', nil, 'Uncategorized planting input')
destinations = checkPlan({uncategorized}, {seeds})
assert(destinations[uncategorized] == seeds and uncategorized.cat == nil,
    'item role required a legacy category or failed to restore its absence')
assert(Tags.matches(Tags.forItem(potato.ref), {'food', 'perishable', 'vegetable', 'seed'}),
    'planting role replaced potato food semantics')
local food = box({mode = 'all', include = {'food'}, exclude = {'seed'}})
destinations = checkPlan({sunflower, candy, potato, full, empty}, {food})
assert(destinations[candy] == food and not destinations[sunflower] and not destinations[potato],
    'food rule exclusions used coarse categories instead of item planting roles')
local additive = box(seedRule, {foodNonPerishable_candySnack = true})
destinations = checkPlan({sunflower, candy, full, empty}, {additive})
assert(destinations[candy] == additive and destinations[full] == additive and not destinations[empty],
    'rule exclusions stripped additive manual categories or widened unrelated seed categories')
local presets = {Seeds = {gen = 7, cats = {}, items = {}}}
Rules.localPresets.Seeds = {gen = 7, rule = seedRule}
local presetBox = box(nil, {}, {}, {Seeds = 7}, presets)
destinations = checkPlan({sunflower, candy, potato, empty}, {presetBox})
assert(destinations[sunflower] == presetBox and destinations[potato] == presetBox
    and not destinations[candy] and not destinations[empty], 'preset tag-only rule lost actual item semantics')
local stalePreset = box(nil, {}, {}, {Seeds = 6}, presets)
destinations = checkPlan({sunflower}, {stalePreset}); assert(not destinations[sunflower], 'stale preset link routed an item')
local named = box(nil, {}, {['Sunflower seeds'] = true})
named.dist, named.priority, seeds.priority = 50, -10, 100
destinations = checkPlan({sunflower, full}, {seeds, named})
assert(destinations[sunflower] == named and destinations[full] == seeds,
    'tag routing overrode native specific-display-name precedence')
local sameNameSeed = item('Base.SunflowerSeeds', 'foodNonPerishable_candySnack', 'Shared name')
local sameNameFood = item('Base.Candy', 'foodNonPerishable_candySnack', 'Shared name')
destinations = checkPlan({sameNameSeed, sameNameFood}, {seeds})
assert(destinations[sameNameSeed] == seeds and not destinations[sameNameFood], 'dynamic rule conflated display-name homonyms')
local homonymBox = box(nil, {}, {['Shared name'] = true})
destinations = checkPlan({sameNameSeed, sameNameFood}, {seeds, homonymBox})
assert(destinations[sameNameSeed] == homonymBox and destinations[sameNameFood] == homonymBox,
    'adapter changed native explicit display-name homonym behavior')
enabled = false
destinations = checkPlan({sunflower, candy, potato, full, empty}, {seeds})
assert(next(destinations) == nil, 'disabled tags kept dynamic routing active')
destinations = checkPlan({sunflower, candy, potato, full, empty}, {additive})
assert(destinations[sunflower] == additive and destinations[candy] == additive
    and not destinations[potato] and not destinations[full], 'disabled tags changed manual exact categories')
enabled = true

if NativeQuartermasterLuaRoot then
    local small = box(seedRule); small.capacity, small.used = 2, 1
    local heavy = item('Base.Potato', 'foodPerishable_vegetable', 'Heavy potato', 11)
    destinations, plan = checkPlan({sunflower, full, candy, heavy}, {small}, {{ref = {}, factor = 1, space = 10}}, 10)
    assert(destinations[sunflower] == small and not destinations[full] and #plan.leftover == 3,
        'item routing bypassed native capacity, used space or carrier size')
    assert(plan.leftoverReasons.full == 1 and plan.leftoverReasons.nomatch == 1 and plan.leftoverReasons.carry == 1,
        'native leftover reasons changed under item-aware routing')
    local restricted, main = {ref = {}, factor = .1, space = 2}, {ref = {}, factor = 1, space = 2}
    local calls = 0
    destinations, plan = checkPlan({sunflower, full}, {seeds}, {restricted, main}, 2, function(carrierRef, itemRef)
        assert((carrierRef == restricted.ref or carrierRef == main.ref) and (itemRef == sunflower.ref or itemRef == full.ref),
            'carrier callback received cloned or unexpected references')
        calls = calls + 1; return carrierRef == main.ref
    end)
    assert(destinations[sunflower] == seeds and destinations[full] == seeds and calls >= 4)
    for _, trip in ipairs(plan.trips) do
        for _, entries in pairs(trip.perBox) do for _, entry in ipairs(entries) do assert(entry.carrier == main) end end
    end
    destinations, plan = checkPlan({sunflower, full}, {seeds}, {restricted, main}, 2, function() return false end)
    assert(next(destinations) == nil and #plan.leftover == 2 and plan.leftoverReasons.carry == 2,
        'carrier rejection was bypassed or lost leftover records')
end

local function assertFailureRestored(callback)
    local originalSunflower, originalCandy, originalCats = sunflower.cat, candy.cat, seeds.cats
    local ok, failure = pcall(callback)
    assert(not ok and tostring(failure):find('routing test failure', 1, true), 'expected planner failure did not propagate')
    assert(sunflower.cat == originalSunflower and candy.cat == originalCandy and seeds.cats == originalCats,
        'failed routing corrupted original item categories or box category-table identity')
end
assertFailureRestored(function()
    LootSorter.planTrips({sunflower, candy}, {seeds}, {carrier}, 100, function() error('routing test failure') end)
end)
local originalForItem = Tags.forItem
Tags.forItem = function(ref) if ref == candy.ref then error('routing test failure') end; return originalForItem(ref) end
assertFailureRestored(function() LootSorter.planTrips({sunflower, candy}, {seeds}, {carrier}, 100) end)
Tags.forItem = originalForItem
local originalMatches, matchCalls = Tags.matchesRule, 0
Tags.matchesRule = function(...)
    matchCalls = matchCalls + 1
    if matchCalls == 2 then error('routing test failure') end
    return originalMatches(...)
end
assertFailureRestored(function() LootSorter.planTrips({sunflower, candy}, {seeds}, {carrier}, 100) end)
Tags.matchesRule = originalMatches
print('Quartermaster item routing passed: seed/food roles, packets, box/preset rules, additive picks, display-name precedence, opt-out, identities and error restoration'
    .. (NativeQuartermasterLuaRoot and ', installed native planner capacity/carriers/leftovers.' or '; minimal planner fallback (native capacity/carriers skipped).'))
