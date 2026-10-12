if not NativeActionRoot then
    print('World queue native-contract checks skipped (pass --native-action-root media/lua).')
    return
end
require = function() end
local enabled = true
PZSurvivorToolkit = {Settings = {actionQueue = function() return enabled end}}
local function derive(self, name)
    local t = {Type = name, derive = derive}; t.__index = t
    return setmetatable(t, {__index = self})
end
ISBaseObject = {derive = derive}
local installWorldQueue
Events = {OnTick = {Add = function() end}, OnGameStart = {Add = function(callback) installWorldQueue = callback end}}
for _, name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState',
    'ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do
    _G[name] = {instance = function() return {} end}
end
table.wipe = function(t) for k in pairs(t) do t[k] = nil end end
instanceof = function(value, name) return value and value.class == name end
local function native(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
local function nativeFunction(path, pattern)
    local source
    if NativeReadText then
        source = NativeReadText(NativeActionRoot .. '/' .. path)
    else
        local file = assert(io.open(NativeActionRoot .. '/' .. path))
        source = file:read('*a'); file:close()
    end
    source = source:gsub('\r', '')
    assert(loadstring(assert(source:match(pattern))))()
end
native('shared/TimedActions/ISBaseTimedAction.lua')
native('client/TimedActions/ISTimedActionQueue.lua')
native('client/TimedActions/ISQueueActionsAction.lua')
native('client/ISUI/ISDisassembleMenu.lua')
ISMoveableSpriteProps, luautils = {}, {}
nativeFunction('shared/Moveables/ISMoveableSpriteProps.lua', '(function ISMoveableSpriteProps:walkToAndEquip.-\nend)')
nativeFunction('shared/luautils.lua', '(function luautils.walkAdjWindowOrDoor.-\nend)')
ISMoveableCursor = {mode = {}}
nativeFunction('server/BuildingObjects/ISMoveableCursor.lua', '(function ISMoveableCursor:create.-\nend)')
ISInventoryTransferAction = {canMergeAction = function() return true end}
ISContextMenu, ISButton, ISInventoryPane, ISInventoryPaneContextMenu = {}, {}, {}, {}
IsoFlagType = {solidfloor = 'floor'}
IsoObjectType = {wall = 'wall'}
ISMoveableDefinitions = {cheat = false}
showDebugInfoInChat = function() end
local stopped = 0
local player = {class = 'IsoPlayer', isAsleep = function() return false end,
    isLocalPlayer = function() return true end, isDraggingCorpse = function() return false end,
    isFarming = function() return false end, getPlayerNum = function() return 0 end,
    isSittingOnFurniture = function(self) return self.sitting end, isEquippedClothing = function() return false end,
    StopAllActionQueue = function() stopped = stopped + 1 end}
function player:getCurrentSquare() return self.square end
function player:getPrimaryHandItem() return self.hand end
function player:getSecondaryHandItem() return nil end
getSpecificPlayer = function() return player end
local function action(kind, object)
    return {Type = kind, character = player, object = object,
        begin = function(self) self.action = {}; self.started = true end,
        isValidStart = function() return true end, isStarted = function(self) return self.started end,
        forceCancel = function(self) self.cancelled = true end}
end
ISWalkToTimedAction = {new = function(_, character, square)
    local a = action('ISWalkToTimedAction'); a.square = square; return a
end}
ISWaitWhileGettingUp = {new = function() return action('ISWaitWhileGettingUp') end}
ISMoveablesAction = {new = function(_, character, square, mode, origSpriteName, object, direction, item, cursor)
    local a = action('ISMoveablesAction', object)
    a.square, a.mode, a.origSpriteName, a.moveCursor = square, mode, origSpriteName, cursor
    return a
end}
ISLightActions = {new = function() return action('ISLightActions') end}
local torch = {getType = function() return 'BlowTorch' end}
local mask = {class = 'Clothing'}
predicateBlowTorch = function(item) return item == torch end
ISWorldObjectContextMenu = {equip = function(character, held, predicate)
    if not predicate(held) then ISTimedActionQueue.add(action('ISEquipWeaponAction', torch)) end
end}
ISInventoryPaneContextMenu.wearItem = function() ISTimedActionQueue.add(action('ISWearClothing', mask)) end
AdjacentFreeTileFinder = {FindWindowOrDoor = function(square) return square.walkSquare end,
    Find = function(square) return square.walkSquare end}
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueOperations.lua'))()
local nativeCursor = ISMoveableCursor
ISMoveableCursor = nil -- Native client Lua loads before the server-side cursor class.
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueWorld.lua'))()
ISMoveableCursor = nativeCursor
assert(installWorldQueue)()
local cursorHook, menuHook = ISMoveableCursor.create, ISDisassembleMenu.disassemble
installWorldQueue()
assert(ISMoveableCursor.create == cursorHook and ISDisassembleMenu.disassemble == menuHook)
local operations = PZSurvivorToolkit.ActionQueueOperations
local q = ISTimedActionQueue.getTimedActionQueue(player)
local function reset()
    q.queue, q.current, stopped, player.hand, player.sitting = {}, nil, 0, torch, false
end
local function target(name)
    local object = {class = 'IsoDoor', getProperties = function() return {has = function() return false end} end}
    local square = {walkSquare = {name = name .. ' approach'}}
    square.getObjects = function() return {contains = function(_, value) return square.exists ~= false and value == object end} end
    local props = setmetatable({object = object, name = name, spriteName = name,
        sprite = {getName = function() return name end}}, {__index = ISMoveableSpriteProps})
    function props:canScrapObject() self.checked = (self.checked or 0) + 1; return true end
    function props:hasScrapTool(_, second) if self.missingTool then return false end; return second and mask or torch end
    function props:getFaceDirectionFromSpriteName() return 'N' end
    function props:findOnSquare() return object end
    return {object = object, square = square, moveProps = props}
end
local function seed()
    local first = action('FirstOperation')
    ISTimedActionQueue.add(first)
    return first
end
local function expand(deferred)
    q:removeFromQueue(q.queue[1]); q.current = deferred
    deferred.action = {isStarted = function() return true end,
        forceComplete = function() end, forceStop = function(self) self.stopped = true end}
    deferred:start()
end
reset()
local first = seed()
local door = target('Metal door')
player.square = door.square.walkSquare
ISDisassembleMenu.disassemble(player, door)
local deferred = q.queue[2]
assert(#q.queue == 2 and q.queue[1] == first and stopped == 0)
assert(deferred.toolkitWorldDismantle and deferred.toolkitWorldTarget == door.object and deferred.toolkitWorldName == 'Metal door')
assert(not door.moveProps.checked, 'preparation must run at the future position with the future tools')
local originalObject = door.object
door.object = {} -- Mutating the caller's record must not retarget the queued command.
player.square, player.hand = {}, {} -- The preceding operation moved and equipped a different tool.
expand(deferred)
assert(#q.queue == 5 and q.queue[2].Type == 'ISWalkToTimedAction' and q.queue[3].Type == 'ISEquipWeaponAction'
    and q.queue[4].Type == 'ISWearClothing' and q.queue[5].Type == 'ISMoveablesAction')
assert(q.queue[5].object == originalObject and stopped == 0)
for _, added in ipairs(q.queue) do assert(added.toolkitQueueOperation == deferred.toolkitQueueOperation) end
-- The native seated clear must remove only this expansion's new steps and preserve later requests.
reset(); seed(); local seatedDoor = target('Seated door'); player.square, player.sitting = {}, true
ISDisassembleMenu.disassemble(player, seatedDoor)
local seated = q.queue[2]
local tail = action('LaterOperation'); ISTimedActionQueue.add(tail)
expand(seated)
assert(q.queue[2].Type == 'ISWaitWhileGettingUp' and q.queue[#q.queue] == tail and stopped == 0)
for i = 2, #q.queue - 1 do assert(q.queue[i].toolkitQueueOperation == seated.toolkitQueueOperation) end
assert(tail.toolkitQueueOperation ~= seated.toolkitQueueOperation)
-- Ordinary movement and disabled-option commands retain native queue replacement.
luautils.walkAdjWindowOrDoor(player, door.square, originalObject, false)
assert(stopped == 1 and #q.queue == 1 and q.queue[1].Type == 'ISWalkToTimedAction')
reset(); first = seed(); enabled = false
door = target('Disabled')
player.square = {}
ISDisassembleMenu.disassemble(player, door)
assert(stopped == 1 and q.queue[1] ~= first and q.queue[#q.queue].Type == 'ISMoveablesAction')
enabled = true
-- Missing tools and removed targets still pass through the native checks and never create a scrap action.
for _, mode in ipairs({'tool', 'removed'}) do
    reset(); seed(); door = target(mode); player.square = {}
    ISDisassembleMenu.disassemble(player, door); deferred = q.queue[2]
    if mode == 'tool' then door.moveProps.missingTool = true else door.square.exists = false end
    expand(deferred)
    for _, queued in ipairs(q.queue) do assert(queued.Type ~= 'ISMoveablesAction') end
    assert(stopped == 0)
end
-- Cursor requests keep their original door and mode even after the UI cursor changes.
reset(); seed(); door = target('Cursor door'); player.square = {}
local cursor = {player = 0, character = player, currentMoveProps = door.moveProps, origMoveProps = door.moveProps,
    currentSquare = door.square, origSpriteName = 'original attached sprite', cursorFacing = 'N', joypadFacing = 'N',
    objectListCache = {}, cannotCreate = function(self) return self.invalid end}
ISMoveableCursor.mode[0] = 'scrap'
ISMoveableCursor.create(cursor, 1, 2, 0, true, 'sprite')
deferred = q.queue[2]
assert(deferred.toolkitWorldTarget == door.object and not cursor.cursorFacing and not cursor.joypadFacing and not cursor.objectListCache)
cursor.currentMoveProps, cursor.currentSquare, cursor.origSpriteName = {}, {}, 'replacement'
ISMoveableCursor.mode[0] = 'place'
expand(deferred)
local scrap = q.queue[#q.queue]
assert(scrap.Type == 'ISMoveablesAction' and scrap.object == door.object and scrap.mode == 'scrap'
    and scrap.origSpriteName == 'original attached sprite' and scrap.moveCursor == cursor and stopped == 0)
print('World queue native contracts: deferred doors, future movement/tools, operation tokens, target snapshots, native cancellation and validation passed.')
