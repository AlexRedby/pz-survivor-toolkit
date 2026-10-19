local shared = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/'
package.path = shared .. '?.lua;' .. package.path
local enabled = true
PZSurvivorToolkit = {Settings = {itemTags = function() return enabled end}}
Events = {OnGameBoot = {Add = function() end}}
isClient, isServer = function() return false end, function() return false end
getFileReader = function() return {readLine = function() end, close = function() end} end
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
dofile(shared .. 'LootSorter_Plan.lua')
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
local presetRules = require('PZSurvivorToolkit/QuartermasterPresets').rules()
local seedRule = {mode = 'all', include = {'seed'}, exclude = {}}
local function box(rule, manual, named, links, presets)
    local cats = manual or {}
    local md = {LSBox = {['0'] = cats}, [Rules.FIELD] = rule and {['0'] = rule} or {}}
    local object = {hasModData = function() return true end, getModData = function() return md end}
    local effective, items = LootSorter.resolveEffective(cats, named or {}, links, presets)
    return {ref = object, cats = effective, items = items, rules = Rules.forBox(object, 0, links, presets),
        capacity = 100, used = 0, dist = 1}
end
local carrier = {ref = {}, factor = 1, space = 100}
local function checkPlan(items, boxes, carriers, budget, accepts)
    local categories, categoryTables, knownItems, knownBoxes = {}, {}, {}, {}
    for _, record in ipairs(items) do categories[record], knownItems[record] = record.cat, true end
    for _, record in ipairs(boxes) do categoryTables[record], knownBoxes[record] = record.cats, true end
    local plan = LootSorter.planTrips(items, boxes, carriers or {carrier}, budget or 100, accepts, Rules.matches)
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
presetRules.Seeds = {gen = 7, rule = seedRule}
local presetBox = box(nil, {}, {}, {Seeds = 7}, presets)
destinations = checkPlan({sunflower, candy, potato, empty}, {presetBox})
assert(destinations[sunflower] == presetBox and destinations[potato] == presetBox
    and not destinations[candy] and not destinations[empty], 'preset tag-only rule lost actual item semantics')
local stalePreset = box(nil, {}, {}, {Seeds = 6}, presets)
destinations = checkPlan({sunflower}, {stalePreset}); assert(not destinations[sunflower], 'stale preset link routed an item')
presetRules.Seeds.gen = 8
local staleRule = box(nil, {}, {}, {Seeds = 7}, presets)
destinations = checkPlan({sunflower}, {staleRule})
assert(not destinations[sunflower], 'remade sidecar preset inherited an old native generation')
presetRules.Seeds.gen = 7
local combined = box({mode = 'all', include = {'food'}, exclude = {'seed'}}, {}, {}, {Seeds = 7}, presets)
destinations = checkPlan({sunflower, candy, full, empty}, {combined})
assert(destinations[sunflower] == combined and destinations[candy] == combined and destinations[full] == combined
    and not destinations[empty], 'manual and linked preset rules stopped being additive')
local excluded = box({mode = 'all', include = {}, exclude = {'seed'}})
destinations = checkPlan({sunflower, candy}, {excluded})
assert(not destinations[sunflower] and destinations[candy] == excluded, 'exclusion-only rule lost its match')
local emptyRule = box({mode = 'all', include = {}, exclude = {}})
destinations = checkPlan({sunflower, candy}, {emptyRule})
assert(next(destinations) == nil, 'empty rule matched every item')
local customItem = item('Mod.Custom', 'ModCategory', 'Custom item')
local customBox = box({mode = 'all', include = {'category:ModCategory'}, exclude = {}})
destinations = checkPlan({customItem, candy}, {customBox})
assert(destinations[customItem] == customBox and not destinations[candy], 'custom category rule widened or disappeared')
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

do
    local hammer = item('Base.Hammer', 'toolCarpentry', 'Hammer')
    local broken = item('Base.Hammer', 'toolCarpentry', 'Hammer')
    local wrench = item('Base.Wrench', 'toolMechanics', 'Wrench')
    local nativeTool = item('Base.Tool', 'Tool', 'Native tool')
    local plank = item('Base.Plank', 'craftingCarpentry_material', 'Plank')
    local weapon = item('Base.BaseballBat', 'Weapon', 'Bat')
    for _, record in ipairs({hammer, broken, wrench, nativeTool, plank, weapon}) do
        record.ref.broken = record ~= hammer
        record.ref.isBroken = function(self) return self.broken end
    end
    local tools = box(nil, {toolCarpentry = true, toolMechanics = true, Tool = true})
    destinations, plan = checkPlan({hammer, broken, wrench, nativeTool}, {tools})
    assert(destinations[hammer] == tools and not destinations[broken] and not destinations[wrench]
        and not destinations[nativeTool] and #plan.leftover == 3 and plan.leftoverReasons.nomatch == 3,
        'default tool categories admitted broken instances or rejected a usable tool')

    local carpentry = box(nil, {toolCarpentry = true, craftingCarpentry_material = true})
    destinations = checkPlan({hammer, broken, plank}, {carpentry})
    assert(destinations[hammer] == carpentry and destinations[plank] == carpentry and not destinations[broken],
        'default carpentry selection admitted broken tools or lost materials')
    local toolRule = box({mode = 'all', include = {'tool'}, exclude = {}})
    local carpentryRule = box({mode = 'all', include = {'carpentry'}, exclude = {}})
    for _, target in ipairs({toolRule, carpentryRule}) do
        destinations = checkPlan({hammer, broken, plank}, {target})
        assert(destinations[hammer] == target and not destinations[broken], 'tag rule admitted a broken tool')
    end
    assert(destinations[plank] == carpentryRule, 'carpentry rule lost non-tool materials')
    local weaponBox = box(nil, {Weapon = true})
    destinations = checkPlan({weapon}, {weaponBox})
    assert(destinations[weapon] == weaponBox, 'tool exclusion changed unrelated broken-item routing')

    local toolPresets = {Tools = {gen = 9, cats = {toolCarpentry = true}, items = {}}}
    local presetTools = box(nil, {}, {}, {Tools = 9}, toolPresets)
    destinations = checkPlan({hammer, broken}, {presetTools})
    assert(destinations[hammer] == presetTools and not destinations[broken], 'linked default preset admitted a broken tool')
    local namedTool = box(nil, {}, {Hammer = true})
    destinations = checkPlan({hammer, broken}, {tools, namedTool})
    assert(destinations[hammer] == namedTool and destinations[broken] == namedTool,
        'default tool exclusion overrode explicit item assignments')

    broken.ref.broken = false
    destinations = checkPlan({broken}, {tools})
    assert(destinations[broken] == tools, 'repair did not restore routing for the same tool instance')
    broken.ref.broken = true
    enabled = false
    destinations = checkPlan({broken}, {tools})
    assert(destinations[broken] == tools, 'disabled item tags changed legacy category routing')
    enabled = true
end

do
    local small = box(seedRule); small.capacity, small.used = 2, 1
    local heavy = item('Base.Potato', 'foodPerishable_vegetable', 'Heavy potato', 11)
    destinations, plan = checkPlan({sunflower, full, candy, heavy}, {small}, {{ref = {}, factor = 1, space = 10}}, 10)
    assert(destinations[sunflower] == small and not destinations[full] and #plan.leftover == 3,
        'item routing bypassed native capacity, used space or carrier size')
    assert(plan.leftoverReasons.full == 1 and plan.leftoverReasons.nomatch == 1 and plan.leftoverReasons.carry == 1,
        'native leftover reasons changed under item-aware routing')
    local far = box(seedRule); far.dist = 10
    small.capacity, small.used = 1, 0
    destinations, plan = checkPlan({sunflower, full}, {small, far}, {{ref = {}, factor = 1, space = 10}}, 1)
    assert(destinations[sunflower] == small and destinations[full] == far and #plan.trips == 2,
        'tag matches changed capacity overflow or carry-budget trip batching')
    destinations = checkPlan({sunflower}, {seeds}, nil, nil, function()
        assert(sunflower.cat == 'foodNonPerishable_candySnack' and next(seeds.cats) == nil,
            'planner exposed temporary item categories or sentinel box categories during execution')
        return true
    end)
    assert(destinations[sunflower] == seeds)
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
    LootSorter.planTrips({sunflower, candy}, {seeds}, {carrier}, 100, function() error('routing test failure') end, Rules.matches)
end)
local originalForItem = Tags.forItem
Tags.forItem = function(ref) if ref == candy.ref then error('routing test failure') end; return originalForItem(ref) end
assertFailureRestored(function() LootSorter.planTrips({sunflower, candy}, {seeds}, {carrier}, 100, nil, Rules.matches) end)
Tags.forItem = originalForItem
local originalMatches, matchCalls = Tags.matchesRule, 0
Tags.matchesRule = function(...)
    matchCalls = matchCalls + 1
    if matchCalls == 2 then error('routing test failure') end
    return originalMatches(...)
end
assertFailureRestored(function() LootSorter.planTrips({sunflower, candy}, {seeds}, {carrier}, 100, nil, Rules.matches) end)
Tags.matchesRule = originalMatches
print('Quartermaster item routing passed: seed/food roles, packets, broken tools, repair, box/preset rules, additive picks, display-name precedence, opt-out, identities, capacity/carriers/leftovers and failure safety.')
