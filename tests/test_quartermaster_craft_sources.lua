-- The native collector concatenates each container's item list without deduplicating aliases.
-- Exercise the owned engine through its public count and queue entrypoints with that contract.
local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
local modules = {}
require = function(name)
    if name == 'PZSurvivorToolkit/QuartermasterCraftContainers' or name == 'PZSurvivorToolkit/QuartermasterCraftState' then
        modules[name] = modules[name] or dofile(root .. 'client/' .. name .. '.lua')
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
ResourceType, InputFlag = {Item = 'Item'}, {ToolLeft = 'Left', ToolRight = 'Right'}
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

local function recipe(withTool)
    local inputs, byType = {}, {}
    for _, kind in ipairs(withTool and {'Material', 'Tool'} or {'Material'}) do
        local index, keep = #inputs + 1, kind == 'Tool'
        local input = {getResourceType = function() return ResourceType.Item end,
            getIntAmount = function() return 1 end, isKeep = function() return keep end,
            hasFlag = function() return false end, index = index}
        inputs[index], byType[kind] = input, input
    end
    return {byType = byType, getInputs = function() return list(inputs) end,
        getIndexForIO = function(_, input) return input.index end}
end
local function item(kind, favorite)
    return {fullType = kind or 'Material', getFullType = function(self) return self.fullType end,
        getID = function() return 17 end, isFavorite = function() return favorite == true end,
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
assert(LootSorter.craft.maxCraftable(materialRecipe, player, boxes) == 2,
    'reachable designated items inflated the craft count')
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
assert(LootSorter.craft.maxCraftable(materialRecipe, player, boxes) == 1,
    'ordinary aliases inflated the craft count')
assert(#transfers(materialRecipe, 1) == 0, 'ordinary aliases unexpectedly fetched an item')
assert(#walks() == 0, 'ordinary nearby inputs without a fetch must not add a return walk')

-- Repeated box rows and aliased item lists reserve each physical item once.
local first, second = item(), item()
local firstBox, secondBox = container({first}), container({second})
setup({}, {box(firstBox), box(firstBox), box(alias({first})), box(secondBox)})
assert(LootSorter.craft.maxCraftable(materialRecipe, player, boxes) == 2,
    'duplicate designated boxes inflated the craft count')
selected = transfers(materialRecipe, 3)
assert(#selected == 2 and selected[1] == first and selected[2] == second,
    'duplicate boxes changed nearest-first item reservations')

-- Object identity is essential: equal type and ID values do not collapse distinct objects.
setup({alias({first, second})}, {})
assert(first ~= second and first:getID() == second:getID())
assert(LootSorter.craft.maxCraftable(materialRecipe, player, boxes) == 2,
    'distinct ordinary objects sharing an ID were collapsed')
setup({}, {box(firstBox), box(secondBox)})
assert(LootSorter.craft.maxCraftable(materialRecipe, player, boxes) == 2,
    'distinct designated objects sharing an ID were collapsed')
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
assert(LootSorter.craft.maxCraftable(toolRecipe, player, boxes) == 4,
    'favorite or kept-tool rules changed the maximum craft count')
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
assert(LootSorter.craft.maxCraftable(toolRecipe, player, boxes) == 0,
    'a remote favorite tool must not satisfy the recipe')
assert(#transfers(toolRecipe, 1) == 0, 'a remote favorite tool must not be fetched')

print('Quartermaster craft sources: identity, overlap, shortfall and favorite/tool rules passed.')
