-- Exercise the selected CleanUI drop callback and its real deferred queue flush.
if not NativeActionRoot or not CleanUIInventoryPaneSource or not CleanUIVanillaInventoryPaneSource then
    print('Inventory transfer operation checks skipped (pass --game and --cleanui-inventory-pane).')
    return
end

local starts, toggles, ticks = {}, {}, {}
Events = {OnGameStart = {Add = function(fn) starts[#starts + 1] = fn end}, OnTick = {
    Add = function(fn) ticks[fn] = true end, Remove = function(fn) ticks[fn] = nil end}}
CleanUI_RegisterInventoryUiToggleCallback = function(fn) toggles[#toggles + 1] = fn end
local function tick()
    local pending = {}
    for fn in pairs(ticks) do pending[#pending + 1] = fn end
    for _, fn in ipairs(pending) do fn() end
end
require = function(name)
    if name == 'PZSurvivorToolkit/InventoryClasses' then
        return dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/' .. name .. '.lua')
    end
end
PZSurvivorToolkit = {Settings = {actionQueue = function() return true end}}
local function derive(self, name)
    local class = {Type = name, derive = derive}
    class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseObject = {derive = derive}
for _, name in ipairs({'ClimbThroughWindowState', 'ClimbOverFenceState', 'ClimbOverWallState',
    'ClimbSheetRopeState', 'ClimbDownSheetRopeState', 'CloseWindowState', 'OpenWindowState'}) do
    _G[name] = {instance = function() return {} end}
end
table.wipe = function(value) for key in pairs(value) do value[key] = nil end end
timSort = table.sort
round = function(value) return value end
instanceof = function(value, name) return value and value.class == name end
getTimestampMs = function() return 1 end
isClient = function() return true end
isShiftKeyDown = function() return false end
isCtrlKeyDown = function() return false end
getCore = function() return {getGameMode = function() return 'Sandbox' end,
    getOptionTimedActionGameSpeedReset = function() return false end} end
CharacterTrait = {DEXTROUS = 'dextrous', ALL_THUMBS = 'allthumbs'}
local function native(path) dofile(NativeActionRoot .. '/' .. path) end
native('shared/TimedActions/ISBaseTimedAction.lua')
native('client/TimedActions/ISTimedActionQueue.lua')
native('client/TimedActions/ISQueueActionsAction.lua')
ISInventoryPage = {}
native('client/TimedActions/ISInventoryTransferAction.lua')
native('shared/TimedActions/ISInventoryTransferUtil.lua')
local player = {class = 'IsoPlayer', getPlayerNum = function() return 0 end,
    hasTrait = function() return false end, isWearingAwkwardGloves = function() return false end,
    isTimedActionInstant = function() return false end, isLocalPlayer = function() return true end,
    isDraggingCorpse = function() return false end,
    getCharacterActions = function() return {contains = function() return true end} end}
local function container(kind)
    local value = {kind = kind, items = {}}
    function value:getType() return self.kind end
    function value:getItems()
        return {size = function() return #self.items end, get = function(_, i) return self.items[i + 1] end}
    end
    function value:contains(item) return item:getContainer() == self end
    function value:isInside() return false end
    function value:isItemAllowed() return true end
    function value:hasRoomFor() return true end
    function value:isInCharacterInventory() return self == player.inventory end
    function value:getParent() return nil end
    function value:isVehicleSeat() return false end
    return value
end
player.inventory = container('inventory')
function player:getInventory() return self.inventory end
getSpecificPlayer = function() return player end
local trunk = container('TruckBed')
local inventoryPage, lootPage = {inventory = player.inventory, inventoryPane = {}}, {inventory = trunk, inventoryPane = {}}
getPlayerInventory = function() return inventoryPage end
getPlayerLoot = function() return lootPage end
luautils = {walkToContainer = function() return true end}
ISContextMenu, ISButton, ISInventoryPaneContextMenu = {}, {}, {}

local function method(source, marker)
    local first = assert(source:find(marker, 1, true), 'missing source method: ' .. marker)
    local last = source:find('\nfunction ', first + #marker, true) or #source + 1
    return source:sub(first, last - 1)
end
local function paneClass(source, name)
    source = source:gsub('\r', '')
    local class = {}
    _G[name] = class
    local first = assert(source:find('local CleanUI_transferGuardLog = {}', 1, true))
    local finalHelper = assert(source:find('local function CleanUI_queueInventoryTransferSafely(', first, true))
    local last = assert(source:find('\nend', finalHelper, true)) + 4
    local safe = source:match('(local function CleanUI_safeIsItemAllowed%([^\n]*.-\nend)') or ''
    local code = 'local corpseStorageCheck = ISInventoryTransferUtil\n' .. safe .. '\n' .. source:sub(first, last)
    for _, entry in ipairs({'sortItemsByTypeAndWeight', 'transferItemsByWeight', 'onMouseUp', 'canPutIn'}) do
        code = code .. '\n' .. method(source, 'function ' .. name .. ':' .. entry .. '(')
    end
    code = code .. '\n' .. method(source, 'function ' .. name .. '.getActualItems(')
    assert(loadstring(code, name .. ' selected source'))()
    return class
end
local clean = paneClass(CleanUIInventoryPaneSource, 'ISInventoryPane')
local vanilla = paneClass(CleanUIVanillaInventoryPaneSource, 'CleanUI_Vanilla_ISInventoryPane')
CleanUI_Clean_ISInventoryPane = clean
local nativeFactory = ISInventoryTransferUtil.newInventoryTransferAction
local constructed, factoryError = {}, false
local function foreignFactory(...)
    if factoryError then error('factory failure') end
    local action = nativeFactory(...)
    constructed[#constructed + 1] = action
    return action
end
ISInventoryTransferUtil.newInventoryTransferAction = foreignFactory
dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueOperations.lua')
for _, fn in ipairs(starts) do fn() end
local operations = PZSurvivorToolkit.ActionQueueOperations
local queue = ISTimedActionQueue.getTimedActionQueue(player)
local function resetQueue()
    -- Keep native engine begin() out of this contract test; additions use the actual native queue.
    local blocker = {character = player, Type = 'TestBlocker', action = {hasStalled = function() return false end}}
    queue.queue, queue.current = {blocker}, blocker
end
local function items(count)
    local values = {}
    for i = 1, count do
        values[i] = {class = 'InventoryItem', getContainer = function() return player.inventory end,
            getDisplayName = function() return 'Engine parts' end, getName = function() return 'Engine parts' end,
            getFullType = function() return 'Base.EngineParts' end, getActualWeight = function() return 0.1 end,
            getUnequippedWeight = function() return 0.1 end, getWeight = function() return 0.1 end,
            isFavorite = function() return false end, isHumanCorpse = function() return false end}
    end
    player.inventory.items = values
    return values
end
local function pane(class)
    return setmetatable({player = 0, inventory = trunk, items = {}, selected = {}, mouseOverOption = 0,
        column2 = 10, downX = -1, downY = -1}, {__index = class})
end
local function drop(class, count)
    local view = pane(class)
    ISMouseDrag = {dragging = items(count), draggingFocus = {onMouseUp = function() end}}
    view:onMouseUp(20, 10)
    assert(ISMouseDrag.dragging == nil, 'native drop must finish the drag immediately')
    assert(ISInventoryTransferUtil.newInventoryTransferAction == foreignFactory, 'restore current factory after drop')
    return view
end
local function merge(first)
    local token, ids = first.toolkitQueueOperation, {}
    for index = 2, #queue.queue do
        local action = queue.queue[index]
        assert(action.toolkitQueueOperation == token, 'one drag must retain one operation through deferred add')
        ids[action.item] = true
    end
    first:checkQueueList()
    local merged = 0
    for _, group in ipairs(first.queueList) do
        for _, item in ipairs(group.items) do assert(ids[item]); ids[item] = nil; merged = merged + 1 end
    end
    assert(merged == 15 and next(ids) == nil and #queue.queue == 2, 'native checkQueueList must merge all 15 exact items')
end

for _, class in ipairs({clean, vanilla}) do
    resetQueue(); constructed = {}
    drop(class, 15)
    assert(#constructed == 15, 'all transfer actions must be constructed in the drop callback')
    if class == clean then
        assert(#queue.queue == 1, 'CleanUI transfer additions must remain deferred until OnTick')
        tick()
    else
        assert(#queue.queue == 16, 'CleanUI vanilla mode must retain its synchronous additions')
    end
    local first = queue.queue[2]
    assert(first and first.toolkitQueueOperation)
    merge(first)
    local token = first.toolkitQueueOperation
    drop(class, 15)
    if class == clean then tick() end
    assert(queue.queue[3].toolkitQueueOperation ~= token, 'a second drag is a distinct operation')
    assert(not first:canMergeAction(queue.queue[3]), 'native transfers must not merge separate drags')
    local installed = class.transferItemsByWeight
    for _, callback in ipairs(toggles) do callback() end
    for _, callback in ipairs(starts) do callback() end
    assert(class.transferItemsByWeight == installed, 'start/toggle must not stack wrappers')
end

-- Two commands before the same deferred flush still have independent identities.
resetQueue(); constructed = {}
drop(clean, 15); drop(clean, 15)
assert(#queue.queue == 1 and #constructed == 30)
tick()
local firstBatch, secondBatch = queue.queue[2], queue.queue[17]
assert(firstBatch.toolkitQueueOperation ~= secondBatch.toolkitQueueOperation, 'same-tick drags must stay separate')
firstBatch:checkQueueList()
secondBatch:checkQueueList()
assert(#queue.queue == 3 and #firstBatch.queueList[1].items == 15 and #secondBatch.queueList[1].items == 15,
    'native merging must preserve both same-tick commands')

-- A runtime UI class replacement and a later factory owner must also be respected.
local late = paneClass(CleanUIVanillaInventoryPaneSource, 'CleanUI_Vanilla_ISInventoryPane')
for _, callback in ipairs(toggles) do callback() end
resetQueue(); constructed = {}
local previousFactory, laterFactoryCalls = foreignFactory, 0
foreignFactory = function(...)
    laterFactoryCalls = laterFactoryCalls + 1
    return previousFactory(...)
end
ISInventoryTransferUtil.newInventoryTransferAction = foreignFactory
drop(late, 15)
assert(laterFactoryCalls == 15, 'call the current factory owner after UI toggle')
merge(queue.queue[2])

resetQueue(); constructed = {}; factoryError = true
drop(clean, 1)
assert(#constructed == 0 and #queue.queue == 1, 'preserve CleanUI constructor-error handling')
factoryError = false
local view = pane(clean)
view.sortItemsByTypeAndWeight = function() error('sort failure') end
assert(not pcall(function() view:transferItemsByWeight(items(1), trunk) end), 'propagate native callback errors')
assert(ISInventoryTransferUtil.newInventoryTransferAction == foreignFactory, 'restore factory after callback error')
local unrelated = nativeFactory(player, items(1)[1], player.inventory, trunk)
ISTimedActionQueue.add(unrelated)
drop(clean, 15); tick()
assert(unrelated.toolkitQueueOperation ~= queue.queue[3].toolkitQueueOperation, 'error must not leak the operation scope')
print('Inventory transfer operation checks passed: real CleanUI deferred/synchronous drops, native merge, separate drags and factory restoration.')
