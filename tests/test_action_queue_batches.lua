if not NativeActionRoot then print('Batch native-contract checks skipped.'); return end
require = function() end
PZSurvivorToolkit = {}
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseObject, ISPanelJoypad = {derive = derive}, {derive = derive}
UIFont = {Small = 'Small'}
getTextManager = function() return {getFontHeight = function() return 12 end} end
instanceof = function(value, name) return value and value.class == name end
convertToPZNetTable = function(value) return value end
log, showDebugInfoInChat = function() end, function() end
DebugType = {CraftLogic = 'CraftLogic'}
isClient, isServer = function() return false end, function() return false end
CharacterTrait = {ALL_THUMBS = 'AllThumbs', DISORGANIZED = 'disorganized'}
local function native(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
native('shared/TimedActions/ISBaseTimedAction.lua')
native('shared/TimedActions/ISFixAction.lua')
native('shared/TimedActions/ISCraftAction.lua')
native('shared/Entity/TimedActions/ISHandcraftAction.lua')
native('client/ISUI/ISCraftingUI.lua')
native('client/Entity/ISUI/CraftRecipe/ISWidgetHandCraftControl.lua')
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r', '') end
    local file = assert(io.open(path)); local value = file:read('*a'); file:close(); return value:gsub('\r', '')
end
ISInventoryPaneContextMenu = {}
local source = read(NativeActionRoot .. '/client/ISUI/ISInventoryPaneContextMenu.lua')
for _, method in ipairs({'OnNewCraftComplete', 'OnCraftComplete'}) do
    assert(loadstring(assert(source:match('(ISInventoryPaneContextMenu%.' .. method .. ' = function.-\nend)'))))()
end
local function project(name)
    return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/' .. name .. '.lua'))()
end
local scope
PZSurvivorToolkit.ActionQueueOperations = {runWith = function(token, callback, ...)
    local previous = scope; scope = token
    local value = callback(...); scope = previous; return value
end}
PZSurvivorToolkit.ActionQueueOperations.perform = function(action, callback, ...)
    return PZSurvivorToolkit.ActionQueueOperations.runWith(action.toolkitQueueOperation, callback, action, ...)
end
local Craft, Batch = project('ActionQueueCraft'), project('ActionQueueBatch')
local function list(...)
    local values = {...}
    return {size = function() return #values end, get = function(_, i) return values[i + 1] end,
        isEmpty = function() return #values == 0 end}
end
local inventory, cupboard = {}, {}
local player = {getInventory = function() return inventory end, hasTrait = function() return false end,
    isTimedActionInstant = function() return false end, isWearingAwkwardGloves = function() return false end}
local selected = {class = 'InventoryItem', getContainer = function() return cupboard end,
    getFullType = function() return 'Base.Material' end}
local recipe = {isCanBeDoneFromFloor = function() return false end, isStopOnWalk = function() return true end,
    isStopOnRun = function() return true end, getTimeToMake = function() return 10 end,
    getName = function() return 'Craft' end, isInSameInventory = function() return false end}
local containers = {}
local token, queue = {}, {}
local selections, valid, possible = 0, true, 3
RecipeManager = {getNumberOfTimesRecipeCanBeDone = function() return possible end,
    IsRecipeValid = function() return valid end,
    getAvailableItemsNeeded = function() selections = selections + 1; return list(selected) end}
ISInventoryPaneContextMenu.canAddManyItems = function() return true end
local function append(action, after)
    action.toolkitQueueOperation = after and after.toolkitQueueOperation or scope
    Batch.attach(action)
    queue[#queue + 1] = action
    return queue, action
end
ISTimedActionQueue = {add = append, addAfter = function(previous, action) return append(action, previous) end}
ISInventoryTransferUtil = {newInventoryTransferAction = function(p, item, src, dst)
    return {Type = 'ISInventoryTransferAction', character = p, item = item, srcContainer = src, destContainer = dst,
        setAllowMissingItems = function() end}
end}
local function legacy()
    local action = ISCraftAction:new(player, selected, recipe, inventory, containers)
    action:setOnComplete(ISInventoryPaneContextMenu.OnCraftComplete,
        action, recipe, player, inventory, containers, selected:getFullType(), cupboard)
    action.toolkitQueueOperation = token; Batch.attach(action); return action
end
local first = legacy()
assert(Craft.supports(first) and Craft.isLegacyAll(first))
local progress = Batch.progress(queue, first)
assert(progress.total == 3 and progress.completed == 0 and progress.remaining == 3 and progress.unit == 'craft')
local args = first.onCompleteArgs
first.onCompleteFunc(unpack(args))
assert(selections == 1 and #queue == 3 and queue[1].Type == 'ISInventoryTransferAction'
    and queue[2].Type == 'ISCraftAction' and queue[3].Type == 'ISInventoryTransferAction')
for _, action in ipairs(queue) do assert(action.toolkitQueueOperation == token) end
Batch.completed(first); Batch.completed(first); Batch.completed(queue[1])
progress = Batch.progress(queue, queue[2])
assert(progress.completed == 1 and progress.remaining == 2, 'one iteration; pickups and returns do not count')
local second = queue[2]
valid = false
second.onCompleteFunc(unpack(second.onCompleteArgs)); Batch.completed(second)
progress = Batch.progress(queue, second)
assert(progress.total == 2 and progress.completed == 2 and progress.remaining == 0 and not progress.lazy,
    'native early exhaustion ends the batch rather than displaying phantom remaining iterations')
valid = true; queue = {}; token = {}; first = legacy()
Batch.cancel(first); first.onCompleteFunc(unpack(first.onCompleteArgs))
assert(#queue == 0 and selections == 1, 'cancel blocks lazy revalidation and every future continuation')
token = {}; possible = -1; first = legacy()
assert(Batch.progress(queue, first).remaining == nil, 'unbounded native recipes never invent a remaining count')
local unknown = ISCraftAction:new(player, selected, recipe, inventory, containers)
unknown.onCompleteFunc = function() end; unknown.toolkitQueueOperation = {}
Batch.attach(unknown); assert(not Craft.supports(unknown) and not Batch.progress(queue, unknown))

token = {}; queue = {}
local callback = function() end
PZSurvivorToolkit.CraftChainRecipes = {addStep = callback}
local generator = {Type = 'ISQueueActionsAction', toolkitCraftPlanCancellation = true,
    addActionsFunction = callback, toolkitQueueOperation = token}
Batch.attach(generator); Batch.completed(generator)
local generated = ISHandcraftAction:new(player,
    {class = 'CraftRecipe', getTimedActionScript = function() end, isCanWalk = function() return true end,
        getTime = function() return 10 end}, {})
generated.toolkitQueueOperation, generated.toolkitBatchIteration = token, generator.toolkitBatchIteration
Batch.attach(generated); Batch.completed(generated)
progress = Batch.progress(queue, generated)
assert(progress.total == 1 and progress.completed == 1, 'plan expansion counts only its actual craft once')
local bulk = {Type = 'ISRemoveWeaponUpgrade', toolkitIndependentBulk = true, toolkitQueueOperation = {}}
Batch.attach(bulk); Batch.attach(bulk)
assert(Batch.progress(queue, bulk).total == 1 and Batch.progress(queue, bulk).unit == 'action')
Batch.completed(bulk); assert(Batch.progress(queue, bulk).completed == 1)
local remainingBulk = {Type = 'ISRemoveWeaponUpgrade', toolkitIndependentBulk = true,
    toolkitQueueOperation = bulk.toolkitQueueOperation}
Batch.attach(remainingBulk); Batch.discard(remainingBulk); Batch.discard(remainingBulk)
Batch.completed(remainingBulk)
assert(Batch.progress(queue, bulk).total == 1 and Batch.progress(queue, bulk).completed == 1
    and not bulk.toolkitQueueOperation.toolkitCancelled, 'one cancelled bulk leaf leaves its siblings and completed count intact')

-- The actual native handcraft callback runs after base perform; retain its token then.
local nativePerform, called = ISBaseTimedAction.perform, 0
ISBaseTimedAction.perform = function() end
ISInventoryPage = {dirtyUI = function() end}
isClient = function() return true end
generated:setOnComplete(function()
    called = called + 1
    local returned = {Type = 'ISInventoryTransferAction', character = player}
    ISTimedActionQueue.add(returned)
    assert(returned.toolkitQueueOperation == token)
end, {})
generated:perform()
assert(called == 1)
ISBaseTimedAction.perform = nativePerform

-- Cancellation guards the continuation, never a native completion that already made results.
inventory.getType = function() return 'inventory' end
local products = 0
RecipeManager.PerformMakeItem = function() return list({}) end
Actions = {addOrDropItem = function() products = products + 1 end}
Batch.cancel(first)
assert(first:complete() and products == 1)
Batch.completed(first)
assert(Batch.progress(queue, first).completed == 1, 'an already completed cancelled iteration retains its result')

if NativeWishlistWorkshopRoot or NativeNeatCraftingSource then
    ISPanel = {derive = derive}
    local neatSource = NativeNeatCraftingSource or read(NativeWishlistWorkshopRoot
        .. '/3502080466/mods/Neat_Crafting/common/media/lua/client/Neat_Crafting/NC_CraftActionPanel.lua')
    assert(loadstring(neatSource))()
    local stops, refreshes = 0, 0
    local logic = {class = 'HandcraftLogic', getPlayer = function() return player end,
        stopCraftAction = function() stops = stops + 1 end}
    local neat = setmetatable({player = player, logic = logic, craftTimes = 1,
        returnToContainer = {selected}, queuedCraftActions = {},
        refreshAfterCraftBatch = function() refreshes = refreshes + 1 end}, NC_CraftActionPanel)
    local function owned()
        local a = ISHandcraftAction:new(player, generated.craftRecipe, {})
        a:setOnStart(neat.onHandcraftActionStart, neat)
        a:setOnComplete(neat.onHandcraftActionComplete, neat)
        a:setOnCancel(neat.onHandcraftActionCancelled, neat)
        a.toolkitQueueOperation = {}; Batch.attach(a); return a
    end
    local a = owned(); assert(Craft.supports(a))
    token, queue = a.toolkitQueueOperation, {}
    ISBaseTimedAction.perform = function(action) Batch.completed(action) end
    a:perform()
    assert(stops == 1 and refreshes == 1 and neat.craftTimes == nil and #queue == 1
        and queue[1].toolkitQueueOperation == token and Batch.progress(queue, queue[1]).completed == 1,
        'actual Neat final callback returns share the batch after native MP onCompleted')
    neat.craftTimes = 2
    local cancelled, tail = owned(), owned()
    tail.toolkitQueueOperation = cancelled.toolkitQueueOperation
    Batch.attach(tail)
    Batch.cancel(cancelled); queue = {}
    assert(Craft.cancelWaiting(cancelled) and Craft.cancelWaiting(tail))
    cancelled.onCompleteFunc(cancelled.onCompleteTarget)
    assert(neat.craftTimes == nil and #queue == 0 and stops == 3,
        'cancel cleans a known owner once; delayed complete does not revive crafts or returns')
    ISBaseTimedAction.perform = nativePerform
end
print('Batch contracts: legacy native selection/continuation, cancel, bounded/unknown counts, plan expansion and late MP returns passed.')
