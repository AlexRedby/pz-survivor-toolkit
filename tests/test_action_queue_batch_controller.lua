if not NativeActionRoot then print('Batch controller native-contract checks skipped.'); return end
require = function() end
getText = function(key) return key end
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseObject, ISPanelJoypad, ISPanel = {derive = derive}, {derive = derive}, {derive = derive}
PZSurvivorToolkit = {Settings = {actionQueue = function() return true end}}
UIFont = {Small = 'Small'}
getTextManager = function() return {getFontHeight = function() return 12 end} end
instanceof = function(value, name) return value and value.class == name end
convertToPZNetTable = function(value) return value end
log, showDebugInfoInChat = function() end, function() end
DebugType = {CraftLogic = 'CraftLogic', Action = {warn = function() end}}
ISLogSystem = {logAction = function() end}
isClient, isServer = function() return true end, function() return false end
CharacterTrait = {ALL_THUMBS = 'AllThumbs', DISORGANIZED = 'disorganized'}
table.wipe = function(t) for key in pairs(t) do t[key] = nil end end
Events = {OnTick = {Add = function() end}, OnGameStart = {Add = function() end}}
for _, name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState',
    'ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do
    _G[name] = {instance = function() return {} end}
end
local function native(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
native('shared/TimedActions/ISBaseTimedAction.lua')
native('client/TimedActions/ISTimedActionQueue.lua')
native('shared/TimedActions/ISReadABook.lua')
native('shared/TimedActions/ISFixAction.lua')
for _, name in ipairs({'ISUnloadBulletsFromFirearm','ISUnloadBulletsFromMagazine','ISRemoveWeaponUpgrade'}) do
    native('shared/TimedActions/' .. name .. '.lua')
end
native('shared/TimedActions/ISCraftAction.lua')
native('shared/Entity/TimedActions/ISHandcraftAction.lua')
ISInventoryPage = {dirtyUI = function() end}
native('client/TimedActions/ISInventoryTransferAction.lua')
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
ISInventoryPage = {dirtyUI = function() end}
ISContextMenu, ISButton, ISInventoryPane = {}, {}, {}
local started = {}
ISBaseTimedAction.begin = function(action)
    started[#started + 1] = action
    action.action = {isStarted = function() return true end, finished = function() return false end,
        isForceComplete = function() return false end, hasStalled = function() return false end}
end
local function project(name)
    return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/' .. name .. '.lua'))()
end
project('BulkActions')
local Operations = project('ActionQueueOperations')
local Craft, Batch = project('ActionQueueCraft'), project('ActionQueueBatch')
project('ActionQueueDefinitions'); project('ActionQueueLabels')
PZSurvivorToolkit.ActionQueueWorld = {isApplianceAction = function() return false end}
project('ActionQueuePolicy')
local Controller = project('ActionQueue')
local function list(...)
    local values = {...}
    return {class = 'List', size = function() return #values end, get = function(_, i) return values[i + 1] end,
        isEmpty = function() return #values == 0 end, contains = function() return true end}
end
local inventory = {getType = function() return 'inventory' end}
local cupboard = {}
local player = {isPlayerMoving = function() return false end, pressedMovement = function() return false end, getInventory = function() return inventory end, hasTrait = function() return false end,
    getPlayerNum = function() return 0 end, isDead = function() return false end, isAsleep = function() return false end,
    isTimedActionInstant = function() return false end, isWearingAwkwardGloves = function() return false end,
    setIsFarming = function() end, isDriving = function() return false end}
getSpecificPlayer = function() return player end
local material = {class = 'InventoryItem', getContainer = function() return cupboard end,
    getFullType = function() return 'Base.Material' end, getID = function() return 42 end,
    setJobDelta = function() end}
inventory.getItemById = function() return material end
local recipe = {isCanBeDoneFromFloor = function() return false end, isStopOnWalk = function() return true end,
    isStopOnRun = function() return true end, getTimeToMake = function() return 10 end,
    getName = function() return 'Craft' end, isInSameInventory = function() return false end}
local containers = list(cupboard)
ISInventoryPaneContextMenu.getContainers = function() return containers end
ISInventoryPaneContextMenu.canAddManyItems = function() return true end
local canCraft = true
RecipeManager = {getNumberOfTimesRecipeCanBeDone = function() return 3 end,
    IsRecipeValid = function() return canCraft end, getAvailableItemsNeeded = function() return list(material) end}
ISInventoryTransferUtil = {newInventoryTransferAction = function(p, item, src, dst)
    local action = ISBaseTimedAction:new(p)
    setmetatable(action, ISInventoryTransferAction)
    action.Type, action.item, action.srcContainer, action.destContainer = 'ISInventoryTransferAction', item, src, dst
    return action
end}
local q = ISTimedActionQueue.getTimedActionQueue(player)
local function reset() q.queue, q.current, started = {}, nil, {} end
local function book()
    local action = ISBaseTimedAction.new(ISReadABook,player)
    action.item={class='InventoryItem',getID=function() return action end}
    return action
end
local function legacy()
    local action = ISCraftAction:new(player, material, recipe, inventory, containers)
    action:setOnComplete(ISInventoryPaneContextMenu.OnCraftComplete,
        action, recipe, player, inventory, containers, material:getFullType(), cupboard)
    return action
end
local first, initialReturn, unrelated
Operations.run(function()
    first = legacy(); ISTimedActionQueue.add(first)
    initialReturn = ISInventoryTransferUtil.newInventoryTransferAction(player, material, inventory, cupboard)
    initialReturn:setAllowMissingItems(true); ISTimedActionQueue.add(initialReturn)
end)
unrelated = book(); ISTimedActionQueue.add(unrelated)
first:perform()
assert(#q.queue == 5 and q.queue[1].Type == 'ISInventoryTransferAction' and q.queue[2].Type == 'ISCraftAction'
    and q.queue[3] == initialReturn and q.queue[4].Type == 'ISInventoryTransferAction' and q.queue[5] == unrelated)
local low, high = Operations.bounds(q, q.queue[2])
assert(low == 1 and high == 4 and started[#started] == q.queue[1] and started[#started] ~= unrelated,
    'legacy lazy pickups/crafts/plain returns remain contiguous before unrelated tail')
assert(Batch.progress(q, q.queue[2]).completed == 1)
reset()
local prefix, cancelled, tail = book(), legacy(), book()
ISTimedActionQueue.add(prefix); Operations.run(function() ISTimedActionQueue.add(cancelled) end); ISTimedActionQueue.add(tail)
assert(Controller.cancelOperation(q, cancelled) and #q.queue == 2 and q.queue[1] == prefix and q.queue[2] == tail)
cancelled.onCompleteFunc(unpack(cancelled.onCompleteArgs))
assert(#q.queue == 2 and cancelled.toolkitQueueOperation.toolkitCancelled,
    'controller cancellation rejects a delayed native Craft All callback')

if NativeWishlistWorkshopRoot or NativeNeatCraftingSource then
    assert(loadfile(ProjectRoot .. '/tests/support/action_queue_craft_owner.lua'))()(NativeNeatCraftingSource or read(NativeWishlistWorkshopRoot
        .. '/3502080466/mods/Neat_Crafting/common/media/lua/client/Neat_Crafting/NC_CraftActionPanel.lua'))
    reset()
    local stops = 0
    local logic = {class = 'HandcraftLogic', getPlayer = function() return player end,
        stopCraftAction = function() stops = stops + 1 end}
    local neat = setmetatable({player = player, logic = logic, craftTimes = 1,
        returnToContainer = {material}, queuedCraftActions = {}}, NC_CraftActionPanel)
    local handcraft = ISHandcraftAction:new(player,
        {class = 'CraftRecipe', getTimedActionScript = function() end, isCanWalk = function() return true end,
            getTime = function() return 10 end}, {})
    handcraft:setOnStart(neat.onHandcraftActionStart, neat)
    handcraft:setOnComplete(neat.onHandcraftActionComplete, neat)
    handcraft:setOnCancel(neat.onHandcraftActionCancelled, neat)
    Operations.run(function() ISTimedActionQueue.add(handcraft) end)
    unrelated = book(); ISTimedActionQueue.add(unrelated)
    handcraft:perform()
    assert(stops == 1 and #q.queue == 2 and q.queue[1].Type == 'ISInventoryTransferAction' and q.queue[2] == unrelated
        and started[#started] == q.queue[1] and Batch.progress(q, q.queue[1]).completed == 1,
        'actual Neat MP callback returns are inserted before native advancement can start an unrelated tail')
end

-- A failed callback propagates and never releases a deferred completion into an unrelated task.
reset()
local audited = ISHandcraftAction:new(player,
    {class = 'CraftRecipe', getTimedActionScript = function() end, isCanWalk = function() return true end,
        getTime = function() return 10 end}, {})
Operations.run(function() ISTimedActionQueue.add(audited) end)
unrelated = book(); ISTimedActionQueue.add(unrelated)
assert(not pcall(function() Operations.perform(audited, function(action)
    q:onCompleted(action); error('callback failed')
end) end))
assert(q.current == audited and q.queue[1] == audited and #started == 1)
q:onCompleted(audited)
assert(q.current == unrelated and #started == 2, 'deferral restores after an error')
reset()
audited = ISHandcraftAction:new(player, audited.craftRecipe, {})
Operations.run(function() ISTimedActionQueue.add(audited) end)
Operations.perform(audited, function(action)
    q:onCompleted(action)
    q:resetQueue()
    ISTimedActionQueue.add(book())
end)
assert(#started == 2 and q.current == started[2] and #q.queue == 1,
    'callback resetting the queue cannot flush completion into a new already-started head')
reset()
audited = ISHandcraftAction:new(player, audited.craftRecipe, {})
Operations.run(function() ISTimedActionQueue.add(audited) end)
unrelated = book(); ISTimedActionQueue.add(unrelated)
local extra, foreignReturn
Operations.perform(audited, function(action)
    -- SP recipe OnCreate can enqueue arbitrary mod actions; their native append order remains intact.
    extra = ISBaseTimedAction:new(player); ISTimedActionQueue.add(extra)
    foreignReturn = ISInventoryTransferUtil.newInventoryTransferAction(player, material, inventory, cupboard)
    foreignReturn:setAllowMissingItems(true); foreignReturn.onCompleteFunc = function() end
    ISTimedActionQueue.add(foreignReturn)
    q:onCompleted(action)
end)
assert(q.current == unrelated and q.queue[2] == extra and q.queue[3] == foreignReturn,
    'arbitrary SP recipe additions and foreign return callbacks keep the native tail ordering')

local ownerStops = 0
local nativeOwner = setmetatable({player = player, craftTimes = 2,
    logic = {class = 'HandcraftLogic', getPlayer = function() return player end,
        stopCraftAction = function() ownerStops = ownerStops + 1 end}}, ISWidgetHandCraftControl)
local function owned()
    local action = ISHandcraftAction:new(player, audited.craftRecipe, {})
    action:setOnStart(nativeOwner.onHandcraftActionStart, nativeOwner)
    action:setOnComplete(nativeOwner.onHandcraftActionComplete, nativeOwner)
    action:setOnCancel(nativeOwner.onHandcraftActionCancelled, nativeOwner)
    return action
end
reset()
ISTimedActionQueue.add(book())
local a, b = owned(), owned()
Operations.run(function() ISTimedActionQueue.add(a); ISTimedActionQueue.add(b) end)
q:clearQueue()
assert(ownerStops == 1 and nativeOwner.craftTimes == nil and #q.queue == 0,
    'native clear cleans an entirely waiting known UI owner once')
a.onCompleteFunc(a.onCompleteTarget)
assert(#q.queue == 0 and nativeOwner.craftTimes == nil and ownerStops == 2,
    'late callback after clear cannot revive the waiting UI batch')
reset(); nativeOwner.craftTimes, ownerStops = 2, 0
a, b = owned(), owned()
Operations.run(function() ISTimedActionQueue.add(a); ISTimedActionQueue.add(b) end)
a:stop()
assert(ownerStops == 2 and nativeOwner.craftTimes == nil and #q.queue == 0,
    'active native stop runs its original cancel/complete; reset does not cancel the same owner again')
reset(); nativeOwner.craftTimes, ownerStops = 2, 0
a, b = owned(), owned()
Operations.run(function() ISTimedActionQueue.add(a); ISTimedActionQueue.add(b) end)
a.action.isStarted = function() return false end
q:clearQueue()
assert(ownerStops == 1 and nativeOwner.craftTimes == nil and #q.queue == 0,
    'allocated but unstarted first Java action clears its waiting UI owner exactly once')
reset(); nativeOwner.craftTimes = 1
a = owned()
Operations.run(function() ISTimedActionQueue.add(a) end)
unrelated = book(); ISTimedActionQueue.add(unrelated)
PZSurvivorToolkit.Settings.actionQueue = function() return false end
nativeOwner.logic.stopCraftAction = function()
    assert(q.current == unrelated and #started == 2, 'disabled feature retains native advance-before-client-callback ordering')
end
a:perform()
PZSurvivorToolkit.Settings.actionQueue = function() return true end
reset()
a = ISHandcraftAction:new(player, audited.craftRecipe, {})
local unknownCalled = 0
a:setOnComplete(function()
    unknownCalled = unknownCalled + 1
    assert(q.current == unrelated and #started == 2, 'unknown callbacks retain native ordering')
    local returned = ISBaseTimedAction:new(player)
    ISTimedActionQueue.add(returned)
    assert(returned.toolkitQueueOperation ~= a.toolkitQueueOperation, 'unknown callback does not inherit audited completion scope')
end, {})
Operations.run(function() ISTimedActionQueue.add(a) end)
unrelated = book(); ISTimedActionQueue.add(unrelated)
a:perform(); assert(unknownCalled == 1)
print('Batch controller: native continuation/return ordering, cancellation, actual Neat late MP returns and callback errors passed.')

-- Native bulk actions mutate ammo during animation events; cancellation lets the current action finish.
player.isPlayerMoving, player.pressedMovement = function() return false end, function() return false end
for _, class in ipairs({ISUnloadBulletsFromFirearm, ISUnloadBulletsFromMagazine, ISRemoveWeaponUpgrade}) do
    reset()
    local current, pending = ISBaseTimedAction.new(class, player), ISBaseTimedAction.new(class, player)
    current.toolkitIndependentBulk, pending.toolkitIndependentBulk = true, true
    Operations.run(function() ISTimedActionQueue.add(current); ISTimedActionQueue.add(pending) end)
    local tail = book(); ISTimedActionQueue.add(tail)
    assert(PZSurvivorToolkit.BulkActions.canFinish(current))
    assert(Controller.cancelOperation(q, current), 'active audited bulk series must be cancellable')
    assert(q.current == current and not q.toolkitCancel, 'in-flight native ammo changes must finish')
    q:onCompleted(current)
    assert(#q.queue == 1 and q.current == tail and q.queue[1] == tail, 'drop future bulk work and retain unrelated tail')
    current.complete = function() end
    assert(not PZSurvivorToolkit.BulkActions.canFinish(current), 'foreign completion is not audited')
end
print('Bulk cancellation: audited native current action finishes; remaining members cancel without dropping unrelated work.')
