-- The native collector concatenates each container's item list without deduplicating aliases.
-- Exercise the owned engine through its public fetch/queue entrypoint with that contract.
local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
local modules = {}
require = function(name)
    if name == 'PZSurvivorToolkit/QuartermasterCraftContainers' or name == 'PZSurvivorToolkit/QuartermasterCraftState'
        or name == 'PZSurvivorToolkit/QuartermasterCraftUnits' then
        local scope = name == 'PZSurvivorToolkit/QuartermasterCraftUnits' and 'shared/' or 'client/'
        modules[name] = modules[name] or dofile(root .. scope .. name .. '.lua')
        return modules[name]
    end
end
local function list(values)
    values = values or {}
    return {size = function() return #values end,
        get = function(_, index) return values[index + 1] end,
        add = function(_, value) values[#values + 1] = value end}
end
ArrayList = {new = function() return list() end}
ResourceType, InputFlag = {Item = 'Item'}, {ToolLeft = 'Left', ToolRight = 'Right', DontReplace = 'DontReplace'}
ISBaseTimedAction = {}
function ISBaseTimedAction:derive()
    local class = {}; class.__index = class
    return setmetatable(class, {__index = self})
end
function ISBaseTimedAction:new(character) return setmetatable({character = character}, self) end
local queued, ordinary, boxes, errors = {}, {}, {}, {}
ISTimedActionQueue = {add = function(action) queued[#queued + 1] = action end}
ISInventoryTransferAction = {new = function(_, player, item, source, destination)
    return {kind = 'transfer', player = player, item = item, source = source, destination = destination}
end}
AdjacentFreeTileFinder = {Find = function(square) return square end}
local origin = {}
local inventory = {isInCharacterInventory = function() return true end}
local player = {getInventory = function() return inventory end, getCurrentSquare = function() return origin end}
ISInventoryPaneContextMenu = {getContainers = function(who) assert(who == player); return list(ordinary) end}
LootSorter = {
    DBG = function(message)
        if message:find('error:', 1, true) or message:find('failed', 1, true) then errors[#errors + 1] = message end
    end,
    notify = function() end,
    gatherBoxesOrWarn = function(who) assert(who == player); return boxes end,
    WalkAction = {new = function(_, who, square) return {kind = 'walk', player = who, square = square} end},
}
CraftRecipeManager = {
    getAllItemsFromContainers = function(containers, result)
        for i = 0, containers:size() - 1 do
            local items = containers:get(i):getItems()
            for j = 0, items:size() - 1 do result:add(items:get(j)) end
        end
        return result
    end,
    getValidInputScriptForItem = function(recipe, item) return recipe.byType[item.fullType] end,
}
dofile(root .. 'shared/LootSorter_CraftPlan.lua')
dofile(root .. 'client/LootSorter_Craft.lua')

-- InputScript's amount/full-type/relative-scale APIs are independent of physical item count.
-- Tests supply native recipe facts explicitly; no contribution or planner logic lives in this double.
local function inputScript(options)
    options = options or {}
    local amount = options.amount or 1
    return {getResourceType = function() return ResourceType.Item end,
        getIntAmount = function(_, kind)
            return options.amounts and options.amounts[kind] or amount
        end,
        getAmount = function(_, kind)
            return options.amounts and options.amounts[kind] or amount
        end,
        getRelativeScale = function(_, kind)
            return options.scales and options.scales[kind] or 1
        end,
        getItems = function() return list(options.kinds or {'Material'}) end,
        getPossibleInputItems = function()
            local scripts = {}
            for _, kind in ipairs(options.kinds or {'Material'}) do
                local fullName = kind
                scripts[#scripts + 1] = {getFullName = function() return fullName end}
            end
            return list(scripts)
        end,
        isUsesPartialItem = function() return options.partial ~= false end,
        isItemCount = function() return options.itemCount == true end,
        isExclusive = function() return options.exclusive == true end,
        isKeep = function() return options.keep == true end,
        isDestroy = function() return options.destroy == true end,
        hasFlag = function(_, flag) return flag == InputFlag.DontReplace and options.dontReplace == true end}
end
local function recipe(withTool)
    local inputs, byType = {}, {}
    for _, kind in ipairs(withTool and {'Material', 'Tool'} or {'Material'}) do
        local input = inputScript({keep = kind == 'Tool', kinds = {kind}})
        input.index = #inputs + 1
        inputs[input.index], byType[kind] = input, input
    end
    return {byType = byType, getInputs = function() return list(inputs) end,
        getIndexForIO = function(_, input) return input.index end}
end
local function unitRecipe(options, kinds)
    local target = recipe()
    options = options or {}
    options.kinds = kinds or {'DuctTape'}
    local input = inputScript(options)
    input.index = 1
    target.byType = {}
    for _, kind in ipairs(kinds or {'DuctTape'}) do target.byType[kind] = input end
    target.getInputs = function() return list({input}) end
    return target
end
local function item(kind, favorite, uses, replacements)
    replacements = replacements or {}
    return {fullType = kind or 'Material', getFullType = function(self) return self.fullType end,
        getID = function() return 17 end, isFavorite = function() return favorite == true end,
        getCurrentUses = function() return uses == nil and 1 or uses end,
        getReplaceOnUse = function() return replacements.onUse end,
        getScriptItem = function(self) return {getFullName = function() return self.fullType end,
            getReplaceOnDeplete = function() return replacements.onDeplete end} end,
        getContainer = function(self) return self.container end}
end
local function container(items, carried)
    local result = {getItems = function() return list(items) end,
        isInCharacterInventory = function(_, who) assert(who == player); return carried == true end}
    for _, value in ipairs(items) do value.container = result end
    return result
end
local function alias(items) return {getItems = function() return list(items) end} end
local function box(value) return {container = value, square = {}} end
local function setup(accessible, designated)
    ordinary, boxes, queued, errors = accessible, designated, {}, {}
end
local function transfers(targetRecipe, qty, surface, craftSquare)
    LootSorter.craft.gatherAndCraft(player, targetRecipe, {}, qty, nil, surface, craftSquare)
    assert(not LootSorter._activelyCrafting, 'source collection left injection suppressed')
    assert(#errors == 0, table.concat(errors, '\n'))
    local result, seen = {}, {}
    for _, action in ipairs(queued) do
        if action.kind == 'transfer' then
            assert(not seen[action.item], 'the exact same item was reserved twice')
            seen[action.item] = true
            assert(action.player == player and action.source == action.item:getContainer()
                and action.destination == inventory, 'native transfer received the wrong source or destination')
            result[#result + 1] = action.item
        end
    end
    assert(queued[#queued] and queued[#queued].recipe == targetRecipe, 'fetch did not queue the craft trigger')
    return result
end
local materialRecipe = recipe()

-- A reachable designated box is already ordinary availability, and must not be fetched again.
local reachable, remote = item(), item()
local reachableBox, remoteBox = container({reachable}), container({remote})
setup({reachableBox}, {box(reachableBox), box(remoteBox)})
local selected = transfers(materialRecipe, 2)
assert(#selected == 1 and selected[1] == remote, 'fetch must use only the remote shortfall')
assert(queued[#queued - 1].kind == 'walk' and queued[#queued - 1].square == origin,
    'fetch must return to the ordinary nearby inputs before triggering the craft')
local function walks()
    local result = {}
    for _, action in ipairs(queued) do
        if action.kind == 'walk' then result[#result + 1] = action.square end
    end
    return result
end
local path = walks()
assert(#path == 2 and path[1] == boxes[2].square and path[2] == origin,
    'nearby availability requires exactly one return after the remote trip')

-- A surface recipe keeps its captured crafting location, including when nearby inputs caused a return.
local surface, craftSquare = {}, {}
setup({reachableBox}, {box(reachableBox), box(remoteBox)})
selected = transfers(materialRecipe, 2, surface, craftSquare)
path = walks()
assert(#selected == 1 and selected[1] == remote and #path == 2 and path[2] == craftSquare,
    'surface crafting must preserve its own return square without an extra origin walk')
assert(queued[#queued].surface == surface, 'surface target was not preserved on the craft trigger')

-- BC-style virtual lists may repeat an original item through multiple ordinary containers.
setup({reachableBox, alias({reachable}), alias({reachable})}, {})
assert(#transfers(materialRecipe, 1) == 0, 'ordinary aliases unexpectedly fetched an item')
assert(#walks() == 0, 'ordinary nearby inputs without a fetch must not add a return walk')

-- Repeated box rows and aliased item lists reserve each physical item once.
local first, second = item(), item()
local firstBox, secondBox = container({first}), container({second})
setup({}, {box(firstBox), box(firstBox), box(alias({first})), box(secondBox)})
selected = transfers(materialRecipe, 3)
assert(#selected == 2 and selected[1] == first and selected[2] == second,
    'duplicate boxes changed nearest-first item reservations')

-- Object identity is essential: equal type and ID values do not collapse distinct objects.
setup({alias({first, second})}, {box(firstBox), box(secondBox)})
assert(first ~= second and first:getID() == second:getID())
assert(#transfers(materialRecipe, 2) == 0, 'distinct ordinary objects must each supply their own credit')
setup({}, {box(firstBox), box(secondBox)})
selected = transfers(materialRecipe, 2)
assert(#selected == 2 and selected[1] == first and selected[2] == second)

-- Preserve ordinary favorite availability, exclude remote favorites, and fetch a kept tool once.
local carried, favorite = item('Material', true), item('Material', true)
local near, far, spare, tool, spareTool = item(), item(), item(), item('Tool'), item('Tool')
local carriedBox = container({carried}, true)
local nearBox = container({favorite, near, tool, spareTool})
local farBox = container({far, spare})
local toolRecipe = recipe(true)
setup({carriedBox, container({item('Unrelated')})}, {box(nearBox), box(farBox)})
selected = transfers(toolRecipe, 3)
assert(#selected == 3 and selected[1] == near and selected[2] == tool and selected[3] == far,
    'nonoverlapping sources must fetch only the shortfall in box order, including one kept tool')
path = walks()
assert(#path == 2 and path[1] == boxes[1].square and path[2] == boxes[2].square,
    'carried-only ordinary inputs must not add an origin return to the fetch route')

local favoriteTool = item('Tool', true)
local favoriteToolBox = container({favoriteTool})
setup({carriedBox, favoriteToolBox}, {box(nearBox)})
selected = transfers(toolRecipe, 1)
assert(#selected == 0, 'already accessible favorite items and tools must remain ordinary availability')
setup({carriedBox}, {box(favoriteToolBox)})
assert(#transfers(toolRecipe, 1) == 0, 'a remote favorite tool must not be fetched')

-- Stock B42 DuctTape has four uses per full roll; FixWithDuctTape consumes two uses.
local tapeRecipe = unitRecipe({amount = 2})
local fullRoll, otherFullRoll = item('DuctTape', false, 4), item('DuctTape', false, 4)
setup({}, {box(container({fullRoll, otherFullRoll}))})
selected = transfers(tapeRecipe, 1)
assert(#selected == 1 and selected[1] == fullRoll, 'two tape uses must fetch one full roll')
setup({container({fullRoll}, true)}, {box(container({otherFullRoll}))})
assert(#transfers(tapeRecipe, 1) == 0, 'a carried full roll already covers two tape uses')

-- A partial roll contributes only its remaining uses, and can combine with another roll.
local partial, partial2, fullSpare = item('DuctTape', false, 1), item('DuctTape', false, 1), item('DuctTape', false, 4)
setup({}, {box(container({partial, partial2, fullSpare}))})
selected = transfers(tapeRecipe, 1)
assert(#selected == 2 and selected[1] == partial and selected[2] == partial2,
    'nearest partial rolls must combine to cover two tape uses')
setup({container({partial}, true)}, {box(container({fullSpare, otherFullRoll}))})
selected = transfers(tapeRecipe, 1)
assert(#selected == 1 and selected[1] == fullSpare, 'a carried partial roll leaves only one use to fetch')
setup({}, {box(container({fullRoll, otherFullRoll, fullSpare}))})
selected = transfers(tapeRecipe, 3)
assert(#selected == 2 and selected[1] == fullRoll and selected[2] == otherFullRoll,
    'three two-use crafts need six uses, supplied by two full rolls')
setup({container({fullRoll}, true)}, {box(container({otherFullRoll, fullSpare}))})
selected = transfers(tapeRecipe, 3)
assert(#selected == 1 and selected[1] == otherFullRoll, 'batch shortfall must subtract all carried uses')

-- Alternative item types use native full-type scaling, rather than assuming identical unit values.
-- This input needs two units of type A or four units of type B (relative scale two).
local scaledRecipe = unitRecipe({amount = 2, amounts = {A = 2, B = 4}, scales = {A = 1, B = 2}}, {'A', 'B'})
local scaledPartial, scaledOther, scaledSpare = item('B', false, 2), item('B', false, 2), item('B', false, 4)
setup({}, {box(container({scaledPartial, scaledOther, scaledSpare}))})
selected = transfers(scaledRecipe, 1)
assert(#selected == 2 and selected[1] == scaledPartial and selected[2] == scaledOther,
    'two half-quantity type-B objects must supply the four native type-B uses')
setup({container({scaledPartial}, true)}, {box(container({scaledOther, scaledSpare}))})
selected = transfers(scaledRecipe, 1)
assert(#selected == 1 and selected[1] == scaledOther,
    'carried quantities must use the same full-type scale as remote quantities')
setup({}, {box(container({scaledSpare, scaledOther}))})
selected = transfers(scaledRecipe, 1)
assert(#selected == 1 and selected[1] == scaledSpare, 'one four-use type-B object covers its native amount')

-- Native contribution is capped by raw current uses when a relative scale is below one.
local smallScale = unitRecipe({amount = 2, amounts = {A = 2, C = 1}, scales = {C = 0.5}}, {'A', 'C'})
local cFirst, cSecond, cSpare = item('C', false, 1), item('C', false, 1), item('C', false, 1)
setup({}, {box(container({cFirst, cSecond, cSpare}))})
selected = transfers(smallScale, 1)
assert(#selected == 2 and selected[1] == cFirst and selected[2] == cSecond,
    'a sub-one scale may not grant more contribution than the object has raw uses')

-- Exclusive alternatives stay within one full type for a craft, but may switch for the next craft.
local exclusive = unitRecipe({amount = 2, exclusive = true}, {'A', 'B'})
local aHalf, aOther, bHalf = item('A', false, 1), item('A', false, 1), item('B', false, 1)
setup({container({aHalf}, true)}, {box(container({bHalf, aOther}))})
selected = transfers(exclusive, 1)
assert(#selected == 1 and selected[1] == aOther,
    'exclusive inputs cannot mix a carried A with a remote B within one craft')
local aFull, bFull = item('A', false, 2), item('B', false, 2)
setup({}, {box(container({aFull, bFull}))})
selected = transfers(exclusive, 2)
assert(#selected == 2 and selected[1] == aFull and selected[2] == bFull,
    'exclusive alternatives may satisfy separate crafts with different full types')
local mixed = unitRecipe({amount = 2}, {'A', 'B'})
setup({container({aHalf}, true)}, {box(container({bHalf, aOther}))})
selected = transfers(mixed, 1)
assert(#selected == 1 and selected[1] == bHalf,
    'nonexclusive inputs may combine full types in nearest-box order')

-- Native whole-item consumption discards overhang; UI partial-use classification alone does not.
local whole = unitRecipe({amount = 2, destroy = true})
setup({}, {box(container({fullRoll, otherFullRoll, fullSpare}))})
selected = transfers(whole, 2)
assert(#selected == 2 and selected[1] == fullRoll and selected[2] == otherFullRoll,
    'whole-item consumption may not reuse an overfull object for the next craft')
setup({}, {box(container({fullRoll, otherFullRoll}))})
selected = transfers(tapeRecipe, 2)
assert(#selected == 1 and selected[1] == fullRoll,
    'a partial-use input may use the same full roll across two crafts')

local genericUses = unitRecipe({amount = 2, partial = false})
setup({}, {box(container({fullRoll, otherFullRoll}))})
assert(#transfers(genericUses, 2) == 1,
    'generic multi-use items retain uses even when isUsesPartialItem is false')
local dontReplace = unitRecipe({amount = 2, dontReplace = true})
local replacesOnUse = item('DuctTape', false, 4, {onUse = 'Base.Scrap'})
local replacesOnDeplete = item('DuctTape', false, 4, {onDeplete = 'Base.Scrap'})
for _, replacementItem in ipairs({replacesOnUse, replacesOnDeplete}) do
    setup({}, {box(container({replacementItem, otherFullRoll}))})
    selected = transfers(dontReplace, 2)
    assert(#selected == 2 and selected[1] == replacementItem and selected[2] == otherFullRoll,
        'DontReplace with either native replacement consumes the entire item')
end
setup({}, {box(container({fullRoll, otherFullRoll}))})
assert(#transfers(dontReplace, 2) == 1,
    'DontReplace without a replacement does not discard remaining uses')
setup({}, {box(container({replacesOnUse, otherFullRoll}))})
assert(#transfers(tapeRecipe, 2) == 1,
    'a replacement without DontReplace does not make each craft consume the whole item')

-- Explicit item-count inputs consume physical objects even when those objects have many uses.
local counted = unitRecipe({amount = 2, itemCount = true})
setup({}, {box(container({fullRoll, otherFullRoll, fullSpare}))})
selected = transfers(counted, 1)
assert(#selected == 2 and selected[1] == fullRoll and selected[2] == otherFullRoll,
    'item-count inputs must reserve two rolls rather than two uses')
setup({container({fullRoll}, true)}, {box(container({otherFullRoll, fullSpare}))})
selected = transfers(counted, 1)
assert(#selected == 1 and selected[1] == otherFullRoll, 'carried count-based items contribute one object')

-- Keep is batch-fixed, but still requires the complete input amount rather than an invented one tool.
local kept = unitRecipe({amount = 2, itemCount = true, keep = true})
setup({}, {box(container({fullRoll, otherFullRoll, fullSpare}))})
selected = transfers(kept, 5)
assert(#selected == 2 and selected[1] == fullRoll and selected[2] == otherFullRoll,
    'two kept items are fetched once for the whole batch')
setup({container({fullRoll}, true)}, {box(container({otherFullRoll, fullSpare}))})
selected = transfers(kept, 5)
assert(#selected == 1 and selected[1] == otherFullRoll, 'carried kept input reduces the batch-fixed shortfall')
local keptUses = unitRecipe({amount = 2, keep = true})
setup({}, {box(container({fullRoll, otherFullRoll}))})
assert(#transfers(keptUses, 5) == 1, 'kept use-based input is satisfied once, using its current uses')

-- Positive usable contributions are required: malformed or empty items cannot create credit.
local zero, negative, invalid = item('DuctTape', false, 0), item('DuctTape', false, -1), item('DuctTape', false, 'bad')
local infinite, nan, unavailable = item('DuctTape', false, math.huge), item('DuctTape', false, 0 / 0), item('DuctTape')
unavailable.getCurrentUses = function() error('native quantity unavailable') end
local malformed = {zero, negative, invalid, infinite, nan, unavailable}
setup({}, {box(container({zero, negative, invalid, infinite, nan, unavailable, fullSpare}))})
selected = transfers(tapeRecipe, 1)
assert(#selected == 1 and selected[1] == fullSpare, 'empty or invalid-use objects must not be fetched')
setup({container(malformed, true)}, {box(container({fullSpare}))})
selected = transfers(tapeRecipe, 1)
assert(#selected == 1 and selected[1] == fullSpare, 'invalid carried quantities must not reduce the shortfall')

-- Use quantities preserve physical identity, ordinary-container overlap and favorite policy.
local favoriteRoll = item('DuctTape', true, 4)
local nearbyRoll = item('DuctTape', false, 4)
local nearbyRollBox = container({nearbyRoll})
setup({nearbyRollBox, alias({nearbyRoll})}, {box(nearbyRollBox), box(container({favoriteRoll, fullSpare}))})
selected = transfers(tapeRecipe, 3)
assert(#selected == 1 and selected[1] == fullSpare,
    'aliases may not duplicate use credit and remote favorites may not be fetched')
setup({container({favoriteRoll}, true)}, {box(container({fullSpare}))})
assert(#transfers(tapeRecipe, 1) == 0, 'an ordinary favorite roll must retain all its available uses')
-- The pure planner reports a real deficit when no exclusive full-type group can finish a craft.
local failedExclusive = LootSorter.craftPlan.plan(
    {{per = 2, tool = false, exclusive = true, types = {'A', 'B'}}}, 1, {}, {
        {{input = 1, uses = 1, scale = 1, partial = true, fullType = 'A'},
         {input = 1, uses = 1, scale = 1, partial = true, fullType = 'B'}}})
assert(failedExclusive.shortfall[1] == 1 and #failedExclusive.trips == 1
    and #failedExclusive.trips[1].picks == 1,
    'two incomplete exclusive groups may not masquerade as one complete craft')

print('Quartermaster craft sources: identity, overlap, units, batches and favorite/tool rules passed.')
