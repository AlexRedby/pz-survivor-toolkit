local worldTags={}
ModData={getOrCreate=function()return worldTags end}
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
    return {ref = ref, fullType = fullType, cat = category, name = name, weight = weight or 1}, script
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
local function checkPlan(items, boxes, carriers, budget, accepts, acceptsDestination)
    local categories, categoryTables, knownItems, knownBoxes = {}, {}, {}, {}
    for _, record in ipairs(items) do categories[record], knownItems[record] = record.cat, true end
    for _, record in ipairs(boxes) do categoryTables[record], knownBoxes[record] = record.cats, true end
    local plan = LootSorter.planTrips(items, boxes, carriers or {carrier}, budget or 100, accepts, Rules.matcher(), acceptsDestination)
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
-- No-duplicates restrictions apply after matching, with reservations across all trips.
do
    local first = item('Base.BookCarpentry1', 'Literature', 'Carpentry Vol. 1')
    local second = item('Base.BookCarpentry1', 'Literature', 'Renamed copy')
    local nextVolume = item('Base.BookCarpentry2', 'Literature', 'Carpentry Vol. 2')
    local shelf, trash = box(nil, {Literature = true}), box(nil, {Literature = true})
    shelf.noDuplicates, shelf.priority, shelf.dist = true, 10, 20
    trash.priority, trash.dist = -1, 1
    shelf.existingTypes = {}
    local destinations, plan = checkPlan({first, second, nextVolume}, {trash, shelf},
        {{ref = {}, factor = 1, space = 1}}, 1)
    assert(destinations[first] == shelf and destinations[second] == trash and destinations[nextVolume] == shelf,
        'empty unique shelf must keep one of each full type across multiple trips')
    assert(#plan.trips == 3 and shelf.existingTypes[first.fullType] == nil,
        'duplicate reservations must not mutate the content snapshot')
    shelf.existingTypes[first.fullType] = {}
    destinations = checkPlan({first, second, nextVolume}, {trash, shelf})
    assert(destinations[first] == trash and destinations[second] == trash and destinations[nextVolume] == shelf,
        'existing copy must send duplicates to lower priority without rejecting a different volume')
    shelf.items[first.name], shelf.cats = true, {}
    destinations = checkPlan({first}, {trash, shelf})
    assert(destinations[first] == trash, 'explicit-name match bypassed duplicate exclusion')
    shelf.noDuplicates = false
    destinations = checkPlan({first, second}, {shelf, trash})
    assert(destinations[first] == shelf and destinations[second] == trash,
        'disabled restriction changed name/category matching')
    shelf.noDuplicates, shelf.cats = true, {Literature = true}
    destinations, plan = checkPlan({first}, {shelf})
    assert(not destinations[first] and #plan.leftover == 1 and plan.leftoverReasons.full == 1,
        'duplicate without fallback should remain in source')
    shelf.existingTypes = {}
    destinations = checkPlan({first, second}, {shelf, trash}, nil, nil,
        function(_, ref) return ref ~= first.ref end)
    assert(not destinations[first] and destinations[second] == shelf,
        'uncarryable item reserved the only unique slot')
    destinations = checkPlan({first, second}, {shelf, trash}, nil, nil, nil,
        function(dest, record) return dest ~= shelf or record ~= first end)
    assert(destinations[first] == trash and destinations[second] == shelf,
        'native-rejected item reserved the only unique slot')
    -- Sort the shelf itself: retain its first copy, route only extras, even when full.
    shelf.existingTypes[first.fullType], shelf.used, shelf.capacity = first.ref, 100, 100
    local source = {}; shelf.container, first.container, second.container = source, source, source
    destinations, plan = checkPlan({second, first}, {shelf, trash})
    assert(destinations[first] == shelf and destinations[second] == trash, 'sorting shelf evacuated its last copy')
    local kept, cut = LootSorter.stripSelfPlacements(plan.trips, source)
    assert(cut == 1 and #kept == 1 and kept[1].perBox[trash][1].item == second)
end
local seeds = box(seedRule)
do
    local one = item('Base.BookCooking1', 'Literature', 'Cooking Vol. 1')
    local extra = item('Base.BookCooking1', 'Literature', 'Cooking Vol. 1')
    local otherVolume = item('Base.BookCooking2', 'Literature', 'Cooking Vol. 2')
    local a, b, trash = box(nil, {Literature = true}), box(nil, {Literature = true}), box(nil, {Literature = true})
    a.noDuplicates, b.noDuplicates, a.duplicateScope, b.duplicateScope = true, true, 'library', 'library'
    a.priority, b.priority, trash.priority = 10, 9, -1
    a.container, b.container = {}, {}
    a.existingTypes, b.existingTypes = {}, {}
    a.capacity = 0
    local routed = checkPlan({one, extra, otherVolume}, {trash, a, b})
    assert(routed[one] == b and routed[extra] == trash and routed[otherVolume] == b,
        'full first member should overflow within group, duplicate should overflow out of group')
    a.capacity = 100
    a.existingTypes[one.fullType], b.existingTypes[one.fullType] = one.ref, one.ref
    one.container = b.container
    routed = checkPlan({extra, one}, {a, b, trash})
    assert(routed[extra] == trash and routed[one] == b,
        'group occupancy must preserve an existing copy in a different-priority member')
    local other = box(nil, {Literature = true})
    other.noDuplicates, other.duplicateScope, other.priority = true, 'other-library', 1
    routed = checkPlan({extra}, {a, b, other, trash})
    assert(routed[extra] == other, 'independent library was blocked by a different group')
    a.noDuplicates, b.noDuplicates = false, false
    routed = checkPlan({one, extra}, {a, b, trash})
    assert(routed[one] == a and routed[extra] == a, 'group membership imposed duplicate exclusion when disabled')
end
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

do
    -- The roomy bag rejects the loose seeds, while main inventory has no room.
    -- Those seeds must not reserve the only destination slot ahead of the packet.
    local small = box(seedRule); small.capacity = 1
    local bag, main = {ref = {}, factor = .1, space = 2}, {ref = {}, factor = 1, space = .5}
    local function accepts(ref, itemRef)
        return ref == main.ref or itemRef == full.ref
    end
    destinations, plan = checkPlan({sunflower, full}, {small}, {bag, main}, 2, accepts)
    assert(not destinations[sunflower] and destinations[full] == small,
        'uncarryable item reserved destination space ahead of a carryable item')
    assert(#plan.leftover == 1 and plan.leftover[1] == sunflower
        and plan.leftoverReasons.carry == 1 and plan.leftoverReasons.full == 0,
        'carrier-ineligible item must be accounted for once as carry, not full')
    assert(#plan.trips == 1 and plan.trips[1].perBox[small][1].carrier == bag,
        'carryable item lost its admissible carrier')

    -- The same phantom reservation must not push the packet to a lower-priority box.
    local overflow = box(seedRule); small.priority, overflow.priority = 10, 0
    destinations, plan = checkPlan({sunflower, full}, {small, overflow}, {bag, main}, 2, accepts)
    assert(destinations[full] == small and not destinations[sunflower] and #plan.leftover == 1,
        'uncarryable item forced a later item into an overflow destination')

    -- A new trip restores carrier space; it must retain the same item restrictions.
    bag.space = 1
    local second = item('Base.CarrotBagSeed2', 'farmingSeed', 'Second packet')
    destinations, plan = checkPlan({sunflower, full, second}, {seeds}, {bag, main}, 2,
        function(ref, itemRef) return ref == main.ref or itemRef ~= sunflower.ref end)
    assert(destinations[full] == seeds and destinations[second] == seeds and not destinations[sunflower]
        and #plan.trips == 2 and #plan.leftover == 1, 'carrier eligibility was lost between trips')
    for _, trip in ipairs(plan.trips) do
        assert(#trip.perBox[seeds] == 1 and trip.perBox[seeds][1].carrier == bag,
            'new trip exceeded carrier space or selected an ineligible carrier')
    end
end

do
    local rejected, allowed = box(seedRule), box(seedRule)
    rejected.priority, rejected.dist, allowed.dist = 10, 10, 1
    local function admits(destination, record)
        assert((destination == rejected or destination == allowed) and record == sunflower,
            'destination callback received cloned or unexpected records')
        return destination == allowed
    end
    destinations = checkPlan({sunflower}, {allowed, rejected}, nil, nil, nil, admits)
    assert(destinations[sunflower] == allowed, 'rejected priority destination prevented fallback')
    rejected.priority, rejected.dist, allowed.dist = 0, 1, 10
    destinations = checkPlan({sunflower}, {rejected, allowed}, nil, nil, nil, admits)
    assert(destinations[sunflower] == allowed, 'rejected nearest destination prevented fallback')
    destinations = checkPlan({sunflower}, {rejected, allowed})
    assert(destinations[sunflower] == rejected, 'omitting destination admission changed legacy routing')

    local namedRejected = box(nil, {}, {[sunflower.name] = true})
    local namedAllowed = box(nil, {}, {[sunflower.name] = true})
    local categoryAllowed = box(seedRule)
    namedRejected.priority, namedAllowed.dist, categoryAllowed.dist = 10, 10, 1
    local function admitsNamed(destination, record)
        assert(record == sunflower and (destination == namedRejected or destination == namedAllowed or destination == categoryAllowed),
            'explicit destination callback received cloned or unexpected records')
        return destination ~= namedRejected
    end
    destinations = checkPlan({sunflower}, {categoryAllowed, namedRejected, namedAllowed}, nil, nil, nil, admitsNamed)
    assert(destinations[sunflower] == namedAllowed, 'explicit fallback lost precedence over a nearer category destination')
    destinations = checkPlan({sunflower}, {namedRejected, categoryAllowed}, nil, nil, nil, admitsNamed)
    assert(destinations[sunflower] == categoryAllowed, 'rejected explicit destination prevented category fallback')

    local calls = 0
    destinations, plan = checkPlan({sunflower, candy}, {rejected}, nil, nil, nil, function(destination, record)
        assert(destination == rejected and record == sunflower, 'admission ran for an unmatched item')
        calls = calls + 1
        return false
    end)
    assert(next(destinations) == nil and calls == 1 and #plan.leftover == 2
        and plan.leftoverReasons.full == 1 and plan.leftoverReasons.nomatch == 1,
        'destination rejection changed matching or leftover reasons')

    local small = box(seedRule); small.capacity = 1
    destinations, plan = checkPlan({sunflower, full}, {small}, nil, nil, nil, function(destination, record)
        assert(destination == small and (record == sunflower or record == full), 'unexpected destination admission records')
        return record == full
    end)
    assert(not destinations[sunflower] and destinations[full] == small and plan.leftoverReasons.full == 1,
        'rejected item reserved destination space needed by an allowed item')
    small.capacity, calls = 0, 0
    destinations, plan = checkPlan({sunflower}, {small}, nil, nil, nil, function() calls = calls + 1; return true end)
    assert(next(destinations) == nil and calls == 0 and plan.leftoverReasons.full == 1,
        'destination admission bypassed planned capacity or ran before its cheap space check')
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
local originalMatcher, matchCalls = Tags.ruleMatcher, 0
Tags.ruleMatcher = function(...)
    local match = originalMatcher(...)
    return function(rule)
        matchCalls = matchCalls + 1
        if matchCalls == 2 then error('routing test failure') end
        return match(rule)
    end
end
assertFailureRestored(function() LootSorter.planTrips({sunflower, candy}, {seeds}, {carrier}, 100, nil, Rules.matches) end)
Tags.ruleMatcher = originalMatcher

-- A large set of alternative boxes must not reclassify each physical item for
-- each candidate. A new plan/standalone read still sees repaired or retagged items.
do
    local records, alternatives = {}, {}
    for index=1,100 do records[index]=item('Base.Candy','Food','Candy '..index) end
    for index=1,40 do alternatives[index]=box(seedRule) end
    local classify, prepare, reads, preparations, evaluations = Tags.forItem, Tags.ruleMatcher, 0, 0, 0
    Tags.forItem=function(ref) reads=reads+1; return classify(ref) end
    Tags.ruleMatcher=function(tags)
        preparations=preparations+1
        local match=prepare(tags)
        return function(rule) evaluations=evaluations+1; return match(rule) end
    end
    local _,failed=checkPlan(records,alternatives)
    assert(#failed.leftover==100 and failed.leftoverReasons.nomatch==100 and reads==100 and preparations==100,
        'routing rebuilt item classification/membership for alternative destinations')
    assert(evaluations==4000,'unsuccessful routing repeated rule evaluations for the refusal reason')
    reads,preparations=0,0
    checkPlan({candy},{box(nil,{[candy.cat]=true})})
    checkPlan({candy},{box(seedRule,{}, {[candy.name]=true})})
    assert(reads==0 and preparations==0,'direct category/name success eagerly prepared semantic tags')
    local brokenFood=item('Base.Candy','Food','Broken non-tool')
    brokenFood.ref.isBroken=function() return true end
    checkPlan({brokenFood},alternatives)
    assert(reads==1 and preparations==1,'broken non-tool rebuilt its prepared membership for rules')
    local brokenTool=item('Base.Hammer','toolCarpentry','Broken hammer')
    brokenTool.ref.isBroken=function() return true end
    reads,preparations=0,0
    checkPlan({brokenTool},{box(nil,{}, {[brokenTool.name]=true})})
    assert(reads==0 and preparations==0,'explicit broken-tool assignment eagerly prepared semantic tags')
    local brokenAlternatives={}
    for index=1,40 do
        brokenAlternatives[index]=box({mode='any',include={'broken','tool'},exclude={}})
        brokenAlternatives[index].capacity=0
    end
    checkPlan({brokenTool},brokenAlternatives)
    assert(reads==1 and preparations==1,'Broken destination exceptions reclassified each alternative')
    Tags.forItem,Tags.ruleMatcher=classify,prepare

    local state={category='Food',broken=false}
    local record={cat='Food',name='Mutable',weight=1,ref={
        getDisplayCategory=function() return state.category end,
        getFullType=function() return 'Base.Mutable' end,
        isBroken=function() return state.broken end}}
    local tools=box({mode='all',include={'tool'},exclude={}})
    local match=Rules.matcher()
    assert(not match(tools,record))
    state.category,record.cat='toolCarpentry','toolCarpentry'
    assert(Rules.matches(tools,record) and Rules.matcher()(tools,record),'next planning operation retained old item tags')
    state.broken=true
    assert(not Rules.matches(tools,record) and not Rules.matcher()(tools,record),'broken tool lost its exclusion')
    state.broken=false
    assert(Rules.matches(tools,record) and Rules.matcher()(tools,record),'repaired tool retained a previous planning snapshot')
    enabled=false
    local legacy=box(nil,{toolCarpentry=true})
    state.broken=true
    assert(Rules.matcher()(legacy,record),'tag opt-out retained a broken-tool classification')
    enabled=true
end
-- Refusal reasons come from the completed destination search, including named
-- destinations whose capacity/admission failed before a category could match.
do
    for _,fullBox in ipairs({true,false}) do
        local named=box(nil,{}, {[candy.name]=true})
        named.capacity=fullBox and 0 or 100
        local matched,admitted=0,0
        local result=LootSorter.planTrips({candy},{named},{carrier},100,nil,function()
            matched=matched+1; return false
        end,function()
            admitted=admitted+1; return false
        end)
        assert(#result.leftover==1 and result.leftoverReasons.full==1 and result.leftoverReasons.nomatch==0,
            'unavailable explicit destination lost its matching designation')
        assert(matched==1 and admitted==(fullBox and 0 or 1),'refusal changed matching/admission calls')
    end
    local fullBox=box(nil,{Food=true}); fullBox.capacity=0
    local calls=0
    local result=LootSorter.planTrips({candy},{fullBox},{carrier},100,nil,function()
        calls=calls+1; return true
    end,function() error('full destination reached admission') end)
    assert(calls==1 and result.leftoverReasons.full==1,'full category destination lost its first match')
    result=LootSorter.planTrips({candy},{fullBox},{{ref={},space=0,factor=1}},100,nil,
        function() error('uncarryable item reached designation matching') end)
    assert(result.leftoverReasons.carry==1 and result.leftoverReasons.full==0,'carry lost refusal precedence')
end
-- Explicit-name lookup must not scan unrelated boxes for every physical item.
do
    for _,count in ipairs({100,400,1000}) do
        local records,boxes,reads,admissions={},{},0,0
        for index=1,count do records[index]=item('Base.Candy','Food','Shared item') end
        for index=1,40 do
            local names={['Unrelated '..index]=true,disabled=false}
            local target=box(nil,{Food=true})
            target.capacity=count
            target.items=nil
            setmetatable(target,{__index=function(_,field)
                if field=='items' then reads=reads+1; return names end
            end})
            boxes[index]=target
        end
        local destinations,plan=checkPlan(records,boxes,{{ref={},space=count,factor=1}},count,nil,
            function() admissions=admissions+1; return true end)
        assert(#plan.leftover==0 and reads==40 and admissions==count,
            'routing repeated unrelated name lookups or cached per-item destination admission')
        for _,record in ipairs(records) do assert(destinations[record]==boxes[1]) end
    end
    local names={['Shared item']=true}
    for index=1,10000 do names['Unrelated preset name '..index]=true end
    local target=box(nil,{},names)
    local designationSet,enumerated=target.items,0
    local originalPairs=pairs
    pairs=function(value)
        local iterator,state,key=originalPairs(value)
        if value~=designationSet then return iterator,state,key end
        return function(...)
            local name,on=iterator(...)
            if name~=nil then enumerated=enumerated+1 end
            return name,on
        end,state,key
    end
    local record=item('Base.Candy','Food','Shared item')
    local destinations=checkPlan({record},{target})
    pairs=originalPairs
    assert(destinations[record]==target and enumerated<16,
        'one item caused enumeration of an unrelated large designation preset')
    local named,category=box(nil,{}, {['Shared item']=true}),box(nil,{Food=true})
    named.dist,category.dist=10,1
    local record=item('Base.Candy','Food','Shared item')
    local function noCategoryMatch() error('explicit-name routing called category fallback') end
    local plan=LootSorter.planTrips({record},{category,named},{carrier},100,nil,noCategoryMatch)
    assert(plan.trips[1].perBox[named][1].item==record,'name index lost explicit precedence')
    local tied=box(nil,{}, {['Shared item']=true})
    tied.dist,tied.priority=named.dist,named.priority
    local destinations=checkPlan({record},{tied,named})
    assert(destinations[record]==tied,'equal-preference name candidates lost incoming order')
    destinations=checkPlan({record},{named,tied})
    assert(destinations[record]==named,'name index retained a previous incoming tie order')
    named.items={Other=true}
    local destinations=checkPlan({record},{named,category})
    assert(destinations[record]==category,'a later plan reused an earlier name index')
end
print('Quartermaster item routing passed: seed/food roles, packets, broken tools, repair, box/preset rules, additive picks, display-name precedence, opt-out, identities, destination admission, capacity/carriers/leftovers and failure safety.')

-- Same type/name/category, different physical freshness: route using each instance.
do
    ItemTag={CANT_COMPOST='no-compost',IS_COMPOSTABLE='compostable'}
    local function apple(age, forbidden)
        local record=item('Base.Apple','foodPerishable_fruit','Apple')
        local value=record.ref
        value.age=age
        value.IsFood=function() return true end
        value.getOffAge=function() return 1 end
        value.getOffAgeMax=function() return 2 end
        value.isFresh=function(self) return self.age<1 end
        value.isRotten=function(self) return self.age>=2 end
        value.hasTag=function(_,tag) return forbidden and tag==ItemTag.CANT_COMPOST or false end
        return record
    end
    local fresh,stale,rotten,restricted=apple(0),apple(1),apple(2),apple(2,true)
    local compost=box({mode='all',include={'rotten'},exclude={}})
    local fridge=box({mode='all',include={'perishable'},exclude={'rotten'}})
    local route,plan=checkPlan({fresh,stale,rotten,restricted},{compost,fridge})
    assert(route[fresh]==fridge and route[stale]==fridge and route[rotten]==compost,
        'freshness routing mixed same-type physical food states')
    assert(route[restricted]==compost and #plan.leftover==0,'Rotten incorrectly depends on compost eligibility')
    fresh.ref.age=2
    route=checkPlan({fresh,stale,rotten},{compost,fridge})
    assert(route[fresh]==compost and route[stale]==fridge,'new plan retained pre-spoilage state')
    fresh.ref.age=0
    route=checkPlan({fresh},{compost,fridge})
    assert(route[fresh]==fridge,'new plan retained an earlier rotten state')
end
print('Freshness routing passed: same-type states, fridge exclusion, universal rotten state and new-plan refresh.')

-- Routing consumes effective exact tags instead of a cached category projection.
local customId='custom:12345678-1234-1234-1234-123456789abc'
local C=require 'PZSurvivorToolkit/TagCustomization'
worldTags.definitions[customId]={name='Workshop'}
worldTags.types['base.candy']={[customId]='add'}
local delta={}
candy.ref.hasModData=function()return true end
candy.ref.getModData=function()return {[C.FIELD]=delta}end
local customDestination=box({mode='all',include={customId},exclude={}})
destinations=checkPlan({candy,sunflower},{customDestination})
assert(destinations[candy]==customDestination and not destinations[sunflower])
delta[customId]='remove'
destinations=checkPlan({candy},{customDestination});assert(not destinations[candy])
delta[customId]=nil;worldTags.definitions[customId]={deleted=true}
destinations=checkPlan({candy},{customDestination});assert(not destinations[candy],
 'deleted tag routed an item through a saved include')

-- Sharpening is a current usable-item role, including partial sharpness loss.
do
    ItemTag=ItemTag or {};ItemTag.SHARPENABLE='base:sharpenable'
    Attribute={Sharpness='Sharpness'}
    local function blade(name,sharpness,broken)
        local record,definition=item(name,'toolCooking',name)
        record.ref.hasTag=function(_,id)return id==ItemTag.SHARPENABLE end
        record.ref.sharpness=sharpness
        record.ref.isBroken=function()return broken==true end
        record.ref.getMaxSharpness=function()return 1 end
        record.ref.getAttributes=function(ref)return {getAttribute=function(_,id)
            assert(id==Attribute.Sharpness)
            return {getFloatValue=function()return ref.sharpness end}
        end}end
        record.ref.getSharpness=function()error('planner read mutating native sharpness')end
        return record
    end
    local dull=blade('Base.KitchenKnife',0.8)
    local sharp=blade('Base.KitchenKnifeForged',1)
    local broken=blade('Base.Scissors',0.1,true)
    local station=box({mode='all',include={'sharpen'},exclude={}})
    local destinations=checkPlan({dull,sharp,broken},{station})
    assert(destinations[dull]==station and not destinations[sharp] and not destinations[broken],
        'sharpening box accepted fully sharpened/broken tools or lost partial sharpness')
    dull.ref.sharpness=1
    assert(not checkPlan({dull},{station})[dull],'new plan retained the old sharpening state')
end

-- Broken tools need a positive, currently matching destination role. In
-- particular, a false arm of an Any rule must not open ordinary tool routing.
do
    local Custom = require 'PZSurvivorToolkit/TagCustomization'
    local broken = item('Base.Hammer', 'toolCarpentry', 'Broken hammer')
    broken.ref.broken = true
    broken.ref.isBroken = function(ref) return ref.broken end
    local delta = {}
    broken.ref.hasModData = function() return true end
    broken.ref.getModData = function() return {[Custom.FIELD] = delta} end
    local brokenBox = box({mode = 'all', include = {'broken'}, exclude = {}})
    local smeltingBox = box({mode = 'all', include = {'smelting'}, exclude = {}})
    local combined = box({mode = 'all', include = {'broken', 'smelting'}, exclude = {}})
    local brokenAny = box({mode = 'any', include = {'broken', 'tool'}, exclude = {}}, {toolCarpentry = true})
    local smeltingAny = box({mode = 'any', include = {'smelting', 'tool'}, exclude = {}}, {toolCarpentry = true})
    local excludesBroken = box({mode = 'all', include = {'smelting'}, exclude = {'broken'}}, {toolCarpentry = true})
    local negativeOnly = box({mode = 'all', include = {'tool'}, exclude = {'broken'}}, {toolCarpentry = true})
    local function expect(target, record, wanted, message)
        assert(Rules.matches(target, record) == wanted, 'direct: ' .. message)
        assert((checkPlan({record}, {target})[record] == target) == wanted, 'plan: ' .. message)
    end
    expect(brokenBox, broken, true, 'Broken selection lost a broken tool')
    expect(brokenAny, broken, true, 'Any lost its matching Broken arm')
    expect(smeltingBox, broken, false, 'broken alone fabricated Smelting')
    expect(combined, broken, false, 'All skipped its absent Smelting requirement')
    expect(smeltingAny, broken, false, 'nonmatching Smelting alternative bypassed the tool guard')
    expect(negativeOnly, broken, false, 'Broken exclusion was ignored')

    delta.broken = 'remove'
    expect(brokenBox, broken, false, 'manual Broken removal was ignored')
    expect(brokenAny, broken, false, 'nonmatching Broken alternative or category bypassed the guard')
    expect(negativeOnly, broken, false, 'negative Broken reference opened ordinary tool routing')
    delta.smelting = 'add'
    expect(smeltingBox, broken, true, 'manual Smelting addition could not collect a broken tool')
    expect(smeltingAny, broken, true, 'Any lost its matching Smelting arm')
    expect(combined, broken, false, 'All ignored manually removed Broken')
    expect(excludesBroken, broken, true, 'Broken removal did not update an explicit exclusion')
    delta.broken = nil
    expect(combined, broken, true, 'explicit Broken and Smelting combination failed')
    expect(excludesBroken, broken, false, 'category bypassed a failed explicit exclusion')
    delta.smelting = 'remove'
    expect(smeltingAny, broken, false, 'manual Smelting removal left a false Any bypass')
    expect(combined, broken, false, 'All ignored manually removed Smelting')

    presetRules.BrokenTools = {gen = 31, rule = {mode = 'all', include = {'broken'}, exclude = {}}}
    local presets = {BrokenTools = {gen = 31, cats = {toolCarpentry = true}, items = {}}}
    local linked = box(nil, {}, {}, {BrokenTools = 31}, presets)
    expect(linked, broken, true, 'linked Broken preset did not collect a broken tool')
    delta.broken = 'remove'
    expect(linked, broken, false, 'linked preset category bypassed removed Broken')
    delta.broken = nil
    broken.ref.broken = false
    expect(brokenBox, broken, false, 'repaired item retained Broken in a later plan')
    expect(box(nil, {toolCarpentry = true}), broken, true, 'repair did not restore ordinary tool routing')
    broken.ref.broken = true
    enabled = false
    expect(box(nil, {toolCarpentry = true}), broken, true, 'tag opt-out changed legacy broken-tool routing')
    enabled = true
    presetRules.BrokenTools = nil
end

-- Scissors are both tools and genuine furnace subjects. Native furnace inputs
-- with AllowDestroyedItem accept their broken instances through Smelting.
do
    local savedManager, savedResource = getScriptManager, ResourceType
    local savedCreate, savedTest = toolkitRecipeOnCreate, toolkitRecipeHasItemTest
    ResourceType = {Item = 'item'}
    toolkitRecipeOnCreate = function() return nil end
    toolkitRecipeHasItemTest = function() return false end
    local scissors, definition = item('Base.Scissors', 'toolCooking', 'Scissors')
    scissors.ref.isBroken = function() return true end
    local allowDestroyed = true
    -- ExtractSteelFromSmallItem resolves smeltablesteelsmall at input 4/4;
    -- mode:destroy and ItemCount make the scissors a whole material subject.
    local input = {
        getResourceType = function() return ResourceType.Item end,
        getPossibleInputItems = function() return list({definition}) end,
        getIntAmount = function() return 1 end,
        isUsesPartialItem = function() return false end,
        doesItemPassRoutineStatusTests = function(_, ref, character)
            assert(ref == scissors.ref and character == nil)
            return not ref:isBroken() or allowDestroyed
        end,
    }
    for _, method in ipairs({'isKeep', 'isTool', 'isApplyOnTick', 'hasConsumeFromItem', 'hasCreateToItem', 'isReplace'}) do
        input[method] = function() return false end
    end
    local recipes = list({{
        getName = function() return 'ExtractSteelFromSmallItem' end,
        getInputs = function() return list({{}, {}, {}, input}) end,
        isVanilla = function() return true end,
    }})
    local manager = {getAllCraftRecipes = function() return recipes end}
    getScriptManager = function() return manager end
    local furnace = box({mode = 'all', include = {'smelting'}, exclude = {}})
    local combined = box({mode = 'all', include = {'broken', 'smelting'}, exclude = {}})
    for _, target in ipairs({furnace, combined}) do
        assert(Rules.matches(target, scissors) and checkPlan({scissors}, {target})[scissors] == target,
            'AllowDestroyedItem furnace subject was stopped by the broken-tool guard')
    end
    presetRules.Furnace = {gen = 32, rule = {mode = 'all', include = {'smelting'}, exclude = {}}}
    local linked = box(nil, {}, {}, {Furnace = 32}, {Furnace = {gen = 32, cats = {toolCooking = true}, items = {}}})
    assert(Rules.matches(linked, scissors) and checkPlan({scissors}, {linked})[scissors] == linked,
        'linked Smelting preset could not collect native broken scissors')
    allowDestroyed = false
    for _, target in ipairs({furnace, combined, linked}) do
        assert(not Rules.matches(target, scissors) and not checkPlan({scissors}, {target})[scissors],
            'native destroyed-item refusal was bypassed by a category or an explicit role')
    end
    presetRules.Furnace = nil
    getScriptManager, ResourceType = savedManager, savedResource
    toolkitRecipeOnCreate, toolkitRecipeHasItemTest = savedCreate, savedTest
end
