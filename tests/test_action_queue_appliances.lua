if not NativeActionRoot then print('Appliance native-contract checks skipped.'); return end
require = function() end
local enabled = true
PZSurvivorToolkit = {Settings = {actionQueue = function() return enabled end}}
local function derive(self, name)
    local t = {Type = name, derive = derive}; t.__index = t
    return setmetatable(t, {__index = self})
end
ISBaseObject = {derive = derive}
local install
Events = {OnServerCommand = {Add = function() end}, OnTick = {Add = function() end},
    OnGameStart = {Add = function(callback) install = callback end}}
for _, name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState',
    'ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do
    _G[name] = {instance = function() return {} end}
end
table.wipe = function(t) for key in pairs(t) do t[key] = nil end end
instanceof = function(value, name) return value and value.class == name end
local function native(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r', '') end
    local file = assert(io.open(path)); local source = file:read('*a'); file:close(); return source:gsub('\r', '')
end
local function extract(path, pattern)
    assert(loadstring(assert(read(path):match(pattern), pattern)))()
end
native('shared/TimedActions/ISBaseTimedAction.lua')
native('client/TimedActions/ISTimedActionQueue.lua')
native('client/TimedActions/ISQueueActionsAction.lua')
ISInventoryPage = {}
native('client/TimedActions/ISInventoryTransferAction.lua')
for _, name in ipairs({'ISToggleStoveAction', 'ISToggleClothingWasher', 'ISToggleClothingDryer',
    'ISToggleComboWasherDryer', 'ISSetComboWasherDryerMode'}) do native('shared/TimedActions/' .. name .. '.lua') end
native('client/TimedActions/ISOvenUITimedAction.lua')
assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SetStoveStateAction.lua'))()
local contextPath = NativeActionRoot .. '/client/ISUI/ISWorldObjectContextMenu.lua'
ISWorldObjectContextMenu = {}
ISLootWindowObjectControlHandler = ISBaseObject:derive('ISLootWindowObjectControlHandler')
for _, kind in ipairs({'Stove','ClothingWasher','ClothingDryer','CombinationWasherDryer'}) do
    native('client/ISUI/LootWindow/Handlers/' .. kind .. 'Toggle.lua')
end
getText = function(key) return key end
getTextManager = function() return {getFontHeight = function() return 14 end} end
UIFont = {Small = 1}
if NativeWishlistWorkshopRoot then
    for _, kind in ipairs({'Stove','ClothingWasher','ClothingDryer','CombinationWasherDryer'}) do
        assert(loadfile(NativeWishlistWorkshopRoot .. '/3437629766/mods/CleanUI/42.19/media/lua/client/ISUI/LootWindow/Handlers/' .. kind .. 'Toggle.lua'))()
    end
end
function ISLootWindowObjectControlHandler:getButtonControl() return self.control end
for _, name in ipairs({'onToggleClothingDryer','onToggleClothingWasher','onToggleComboWasherDryer','onSetComboWasherDryerMode'}) do
    extract(contextPath, '(function ISWorldObjectContextMenu%.' .. name .. '.-\nend)')
end
for _, name in ipairs({'onToggleStove','onMicrowaveSetting','onStoveSetting'}) do
    extract(contextPath, '(ISWorldObjectContextMenu%.' .. name .. ' = function.-\nend)')
end
local function pageSource(path)
    extract(path, '(local TurnOnOff = .-)\nfunction [^\n]*:syncAddFuel')
end
pageSource(NativeActionRoot .. '/client/ISUI/ISInventoryPage.lua')
if NativeWishlistWorkshopRoot then
    CleanUI_Vanilla_ISInventoryPage = {}
    pageSource(NativeWishlistWorkshopRoot .. '/3437629766/mods/CleanUI/42.19/media/lua/client/CleanUI/Vanilla/CleanUI_Vanilla_ISInventoryPage.lua')
end
luautils = {getCorrectSquareForWall = function(_, square) return square end}
extract(NativeActionRoot .. '/shared/luautils.lua', '(function luautils.walkAdj%(.-\nend)')
isServer, isClient = function() return false end, function() return false end
ISDisassembleMenu = {disassemble = function() end}
ISMoveableCursor = {create = function() end}
ISBuildingObject = {tryBuild = function() end}
ISMoveablesAction = {new = function() return {} end}
ISContextMenu, ISButton, ISInventoryPane, ISInventoryPaneContextMenu = {}, {}, {}, {}
ISReadABook = ISBaseTimedAction:derive('ISReadABook')
ISReadABook.isValidStart = function() return true end
local paused, stopped = false, 0
UIManager = {getSpeedControls = function() return {getCurrentGameSpeed = function() return paused and 0 or 1 end} end}
local square = {getX = function() return 10 end, getY = function() return 10 end,
    getZ = function() return 0 end,
    canReachTo = function() return true end}
local walkSquare = {getX = function() return 11 end, getY = function() return 10 end}
local player = {class = 'IsoPlayer', getPlayerNum = function() return 0 end,
    isDead = function() return false end, isAsleep = function() return false end,
    isLocalPlayer = function() return true end, isDraggingCorpse = function() return false end,
    isFarming = function() return false end, isTimedActionInstant = function() return false end,
    isPlayerMoving = function() return false end, pressedMovement = function() return false end,
    getCurrentSquare = function(self) return self.square end, getSquare = function(self) return self.square end,
    getX = function(self) return self.x end, getY = function() return 10.5 end,
    StopAllActionQueue = function() stopped = stopped + 1 end}
getSpecificPlayer = function(n) assert(n == 0); return player end
getPlayer = function() return player end
AdjacentFreeTileFinder = {Find = function() return walkSquare end}
ISWalkToTimedAction = ISBaseTimedAction:derive('ISWalkToTimedAction')
function ISWalkToTimedAction:new(character, destination)
    local action = ISBaseTimedAction.new(self, character); action.square = destination; return action
end
local function project(name)
    if name == 'ActionQueue' then project('ActionQueueLifecycle'); project('ActionQueueAcknowledgements') end
 assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/' .. name .. '.lua'))() end
project('ActionQueueOperations'); project('ActionQueueDefinitions'); project('ActionQueueLabels'); project('ActionQueuePolicy'); project('ActionQueue'); project('ActionQueueWorld')
local api, world = PZSurvivorToolkit.ActionQueue, PZSurvivorToolkit.ActionQueueWorld
local toggleTypes = {Stove = 'PZSurvivorToolkitSetStoveState', ClothingWasher = 'ISToggleClothingWasher',
    ClothingDryer = 'ISToggleClothingDryer', CombinationWasherDryer = 'ISToggleComboWasherDryer'}
local q = ISTimedActionQueue.getTimedActionQueue(player)
local bookID = 0
local function action(kind)
    local a = ISBaseTimedAction.new(kind or ISReadABook, player)
    a.begin = function(self)
        self.started = true
        self.action = {isStarted = function() return true end, finished = function() return false end,
            isForceComplete = function() return false end, forceStop = function(self) self.stopped = true end}
    end
    bookID = bookID + 1
    local id = bookID
    a.item = {class='InventoryItem',getID=function() return id end,getFullType=function() return 'Base.Book'..id end}
    return a
end
local function reset()
    q.queue, q.current, q.toolkitCancel, q.toolkitResume = {}, nil, nil, nil
    player.square, player.x, stopped = square, 10.5, 0
    local book = action(); ISTimedActionQueue.add(book)
    return book
end
local function target(kind)
    return {class = (not kind or kind == 'Stove') and 'IsoStove' or 'IsoObject', getObjectName = function() return kind or 'Stove' end,
        Activated = function() return false end, isActivated = function() return false end,
        container = {isPowered = function(self) return self.powered ~= false end}, getContainer = function(self) return self.container end,
        getSquare = function(self) return self.square end, square = square,
        getObjectIndex = function(self) return self.removed and -1 or 0 end}
end
local cachedHandlers = {}
for _, kind in ipairs({'Stove','ClothingWasher','ClothingDryer','CombinationWasherDryer'}) do
    local class = _G['ISLootWindowObjectControlHandler_' .. kind .. 'Toggle']
    local handler = setmetatable({playerObj = player, playerNum = 0, object = target(kind),
        container = {isPowered = function(self) return self.powered ~= false end}}, class)
    handler.object.container = handler.container
    -- CleanUI caches Handler.perform when the button is created before OnGameStart.
    handler.control = {target = handler, onclick = class.perform}
    cachedHandlers[kind] = handler
end
install()
local function expand(command)
    q:removeFromQueue(q.queue[1]); q.current = command
    command.action = {forceComplete = function(self) self.completed = true end,
        forceStop = function() error('deferred command must not stop unrelated actions') end}
    command:start()
end
for _, pageClass in ipairs({ISInventoryPage, CleanUI_Vanilla_ISInventoryPage}) do
    for _, kind in ipairs({'Stove','ClothingWasher','ClothingDryer','CombinationWasherDryer'}) do
        local book, object = reset(), target(kind)
        local page = {player = 0, inventoryPane = {inventory = {getParent = function() return object end}}}
        pageClass.toggleStove(page)
        local command = q.queue[2]
        assert(#q.queue == 2 and q.current == book and stopped == 0 and world.isDeferredAction(command))
        assert(not api.cancelOperationReason(q, command))
        assert(api.move(q, command, book) and book.action.stopped and q.toolkitResume == command)
        reset(); pageClass.toggleStove(page); command = q.queue[2]
        player.x = 40 -- A preceding action moved us; pathfinding happens now.
        local tail = action(); ISTimedActionQueue.add(tail)
        expand(command)
        assert(q.queue[2].Type == 'ISWalkToTimedAction' and world.isApplianceAction(q.queue[3])
            and q.queue[4] == tail and stopped == 0 and q.queue[3].Type == toggleTypes[kind])
        assert(q.queue[3].toolkitQueueOperation == command.toolkitQueueOperation)
        local walk, toggle = q.queue[2], q.queue[3]
        reset(); ISTimedActionQueue.add(walk); ISTimedActionQueue.add(toggle)
        assert(not api.cancelOperationReason(q, toggle), 'pending native toggle can cancel together with its approach')
    end
end
for _, name in ipairs({'onToggleStove','onToggleClothingWasher','onToggleClothingDryer','onMicrowaveSetting','onStoveSetting'}) do
    local book, object = reset(), target()
    ISWorldObjectContextMenu[name](nil, object, 0)
    assert(q.current == book and stopped == 0 and #q.queue == 2)
    local command = q.queue[2]
    local tail = action(); ISTimedActionQueue.add(tail)
    object.removed = true
    expand(command)
    assert(#q.queue == 2 and q.queue[2] == tail and command.action.completed and stopped == 0,
        'removed target skips only its deferred command')
end
for _, kind in ipairs({'Stove','ClothingWasher','ClothingDryer','CombinationWasherDryer'}) do
    local book, object = reset(), target(kind)
    local handler = setmetatable({playerObj = player, playerNum = 0, object = object},
        _G['ISLootWindowObjectControlHandler_' .. kind .. 'Toggle'])
    handler.container = {isPowered = function() return true end}
    object.container = handler.container
    handler:perform()
    local command = q.queue[2]
    assert(q.current == book and stopped == 0 and world.isDeferredAction(command), 'actual B42 loot-button handler appends')
    handler.object = target(kind) -- Loot panel reuse cannot retarget the queued request.
    expand(command)
    assert(q.queue[2].object == object and world.isApplianceAction(q.queue[2]) and stopped == 0
        and q.queue[2].Type == toggleTypes[kind])
end
for kind, handler in pairs(cachedHandlers) do
    local book, object = reset(), target(kind)
    handler.object = object
    object.container = handler.container
    local control = handler:getControl()
    assert(control == handler.control and control.onclick == handler.perform, 'cached native button must use the installed adapter')
    control.onclick(control.target)
    local command = q.queue[2]
    assert(q.current == book and stopped == 0 and world.isDeferredAction(command), 'cached button must not stop active reading')
    handler.object = target(kind)
    handler.object.container = handler.container
    expand(command)
    assert(q.queue[2].object == object and world.isApplianceAction(q.queue[2]), 'cached-button snapshot preserves the clicked target')
    local custom = function() error('custom control callback must remain untouched') end
    control.onclick = custom
    assert(handler:getControl().onclick == custom, 'custom onclick must not borrow the native adapter')
    if NativeWishlistWorkshopRoot then
        reset(); handler.container.powered = true; handler:perform(); command = q.queue[2]
        local tail = action(); ISTimedActionQueue.add(tail)
        handler.container.powered = false
        expand(command)
        assert(#q.queue == 2 and q.queue[2] == tail and command.action.completed and stopped == 0,
            'actual CleanUI power validation must run again before the deferred toggle')
    end
end
reset(); local object = target('CombinationWasherDryer')
ISWorldObjectContextMenu.onSetComboWasherDryerMode(player, object, 'dryer')
local command = q.queue[2]; expand(command)
assert(q.queue[2].Type == 'ISSetComboWasherDryerMode' and q.queue[2].mode == 'dryer')
reset(); object = target(); enabled = false
ISToggleStoveAction.begin = function() end
ISWorldObjectContextMenu.onToggleStove(nil, object, 0)
assert(stopped == 1 and q.queue[1].Type == 'ISToggleStoveAction', 'disabled setting preserves native replacement')
enabled = true; reset(); paused = true
ISInventoryPage.toggleStove({player = 0, inventoryPane = {inventory = {getParent = function() return object end}}})
assert(#q.queue == 1 and stopped == 0)
paused = false; reset()
luautils.walkAdj(player, square)
assert(#q.queue == 0 and stopped == 1, 'ordinary movement still cancels')
local foreign = ISToggleStoveAction:new(player, target())
foreign.object.removed = true
assert(world.targetGone(foreign), 'target removal after approach must preserve the remaining queue')
foreign.complete = function() end
assert(not world.isApplianceAction(foreign), 'foreign lifecycle override cannot borrow cancellation support')
print('Appliance native-contract checks passed: native/CleanUI clicks, delayed paths, priority, cancellation, missing targets and native opt-out.')
