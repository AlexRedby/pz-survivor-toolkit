if not NativeActionRoot then
    print('Vegetation queue native-contract checks skipped (pass --native-action-root media/lua).')
    return
end

-- Exercise the actual cursor -> inherited tryBuild/walkTo -> native producer path.
-- Java supplies world objects and action scheduling; the Lua bodies remain stock.
local function read(path)
    if NativeReadText then return NativeReadText(NativeActionRoot .. '/' .. path):gsub('\r', '') end
    local f = assert(io.open(NativeActionRoot .. '/' .. path))
    local source = f:read('*a'); f:close(); return source:gsub('\r', '')
end
local function native(path) assert(loadstring(read(path), '@' .. NativeActionRoot .. '/' .. path))() end
local function nativeFunction(path, pattern)
    assert(loadstring(assert(read(path):match(pattern)), '@' .. NativeActionRoot .. '/' .. path))()
end
getFilenameOfClosure = NativeFilenameOfClosure or function(callback) return debug.getinfo(callback, 'S').source:gsub('^@', '') end
require = function(module)
    if module == 'PZSurvivorToolkit/SourceProof' then return dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/' .. module .. '.lua') end
    if module == 'PZSurvivorToolkit/InventoryClasses' then
        return dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/' .. module .. '.lua')
    end
    if module == 'PZSurvivorToolkit/ActionQueueApproach' then
        return dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/' .. module .. '.lua')
    end
end
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseObject = {derive = derive, new = function(self) return setmetatable({}, self) end}
local enabled, install, stopped, drag = true, nil, 0, nil
PZSurvivorToolkit = {Settings = {actionQueue = function() return enabled end}}
local noop = function() end
local event = {Add = noop}
Events = {OnTick = event, OnServerCommand = event, OnDoTileBuilding2 = event,
    OnDoTileBuilding3 = event, OnKeyPressed = event, OnDestroyIsoThumpable = event,
    RenderOpaqueObjectsInWorld = event, OnGameStart = {Add = function(callback) install = callback end}}
for _, name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState',
    'ClimbSheetRopeState','ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do
    _G[name] = {instance = function() return {} end}
end
table.wipe = function(value) for key in pairs(value) do value[key] = nil end end
instanceof = function(value, name)
    return value and (value.class == name or name == 'IsoGameCharacter' and value.class == 'IsoPlayer')
end
isServer, isClient = function() return false end, function() return false end
getText = function(key) return key end
showDebugInfoInChat = noop
DebugType = {Lua = {debugln = noop}}
ISLogSystem = {logAction = noop}
ISBuildMenu = {cheat = false}
ItemTag = {CUT_PLANT = 'cut', HAND_SCYTHE = 'handScythe'}
IsoFlagType = {canBeCut = 'cut', canBeRemoved = 'grass', solidfloor = 'floor', collideN = 'north', collideW = 'west', water = 'water'}
IsoObjectType = {doorFrN = 'doorN', doorFrW = 'doorW', wall = 'wall'}
Perks = {Woodwork = 'woodwork'}
CharacterTrait = {DEXTROUS = 'dextrous', ALL_THUMBS = 'allThumbs'}
BehaviorResult = {Failed = 'failed', Succeeded = 'succeeded', Working = 'working'}
MoodleType = {UNHAPPY = 'unhappy', DRUNK = 'drunk'}
BodyPartType = {Hand_L = 1, ForeArm_R = 1, ToIndex = function(value) return value end, FromIndex = function(value) return value end}

local function list(values)
    return {size = function() return #values end, get = function(_, index) return values[index + 1] end,
        isEmpty = function() return #values == 0 end,
        contains = function(_, item) for _, value in ipairs(values) do if value == item then return true end end; return false end}
end
local squares = {}
local function key(x, y, z) return x .. ':' .. y .. ':' .. z end
local function square(x, y, kind)
    local value = {x = x, y = y, z = 0, kind = kind, objects = {}}
    value.getX = function(self) return self.x end
    value.getY = function(self) return self.y end
    value.getZ = function(self) return self.z end
    value.getObjects = function(self) return list(self.objects) end
    value.has = function() return false end
    value.canReachTo = function() return true end
    value.DistToProper = function(self, other)
        local ox, oy = other.getX and other:getX() or other.x, other.getY and other:getY() or other.y
        return math.sqrt((self.x-ox)^2 + (self.y-oy)^2)
    end
    value.getProperties = function(self) return {has = function(_, flag) return self.flags and self.flags[flag] or false end} end
    value.isCouldSee = function() return true end
    value.checkHaveGrass = function(self) return self.kind == 'scythe' end
    squares[key(x, y, 0)] = value
    if kind then
        local properties = {has = function(_, flag) return flag == (kind == 'bush' and 'cut' or kind == 'grass' and 'grass') end}
        local sprite = {getProperties = function() return properties end}
        local object = {getSprite = function() return sprite end, getProperties = function() return properties end,
            getSquare = function() return value end, getObjectIndex = function() return 0 end}
        if kind == 'wallVine' then
            object.getAttachedAnimSprite = function()
                return list({{getParentSprite = function() return {getName = function() return 'f_wallvines_1_39' end} end}})
            end
        else object.getAttachedAnimSprite = function() return nil end end
        value.objects[1] = object
    end
    return value
end
local cell = {getGridSquare = function(_, x, y, z) return squares[key(x, y, z)] end,
    setDrag = function(_, value) drag = value end, getDrag = function() return drag end}
getCell = function() return cell end
getWorld = function() return {getCell = function() return cell end} end
getSquare = function(x, y, z) return squares[key(x, y, z)] end
luautils = {}
nativeFunction('shared/luautils.lua', '(luautils.stringStarts = function.-\nend)')
nativeFunction('shared/luautils.lua', '(luautils.getCorrectSquareForWall = function.-\nend)')
nativeFunction('shared/luautils.lua', '(function luautils.walkAdj%(.-\nend)')
nativeFunction('shared/luautils.lua', '(function luautils.walk%(.-\nend)')
nativeFunction('shared/luautils.lua', '(function luautils.walkAdjWall%(.-\nend)')
nativeFunction('shared/luautils.lua', '(function luautils.walkAdjWindowOrDoor%(.-\nend)')
nativeFunction('shared/luautils.lua', '(function luautils.walkAdjAltTest%(.-\nend)')
local adjacentSources = {assert(read('shared/luautils.lua'):match('(local function isAdjacentToSquare.-\nend)'))}
for _, name in ipairs({'walkAdjSquares', 'walkAdjSquaresExcluded'}) do
    adjacentSources[#adjacentSources + 1] = assert(read('shared/luautils.lua'):match('(function luautils%.' .. name .. '%(.-\nend)'))
end
assert(loadstring(table.concat(adjacentSources, '\n'), '@' .. NativeActionRoot .. '/shared/luautils.lua'))()
AdjacentFreeTileFinder = {Find = function(value, _, excluded)
    value.lastExcluded = excluded
    if not value.blocked then return value end
end, FindWall = function(value, north)
    value.lastNorth = north; return value.wallSquare or value
end, FindWindowOrDoor = function(value, item)
    value.lastDoor = item; return value.doorSquare or value
end}
ISMoveableSpriteProps = {}
nativeFunction('shared/Moveables/ISMoveableSpriteProps.lua', '(function ISMoveableSpriteProps:walkAdj%(.-\nend)')
nativeFunction('shared/Moveables/ISMoveableSpriteProps.lua', '(function ISMoveableSpriteProps:walkAdjMultiTile%(.-\nend)')
nativeFunction('shared/Moveables/ISMoveableSpriteProps.lua', '(function ISMoveableSpriteProps:getSpriteGridTopLeft%(.-\nend)')
nativeFunction('shared/Moveables/ISMoveableSpriteProps.lua', '(function ISMoveableSpriteProps:getMultiTileSquares%(.-\nend)')
IsoUtils = {DistanceTo = function(x, y, x2, y2) return math.sqrt((x-x2)^2 + (y-y2)^2) end}

local cuttingTool = {isBroken = function() return false end,
    hasTag = function(_, tag) return tag == ItemTag.CUT_PLANT end}
local scythe = {hasTag = function() return false end}
local inventory = {tool = cuttingTool}
function inventory:containsEvalRecurse(predicate) return self.tool and predicate(self.tool) or false end
function inventory:getFirstEvalRecurse(predicate) return self:containsEvalRecurse(predicate) and self.tool or nil end
function inventory:contains(item) return item == self.tool or item == scythe end
inventory.containsRecursive = inventory.contains
local player = {class = 'IsoPlayer', isAsleep = function() return false end, isLocalPlayer = function() return true end,
    isDead = function() return false end, isPlayerMoving = function() return false end,
    pressedMovement = function() return false end, pressedCancelAction = function(self) return self.cancel == true end,
    getCharacterActions = function() return list({}) end,
    isDraggingCorpse = function() return false end, isFarming = function() return false end,
    isSittingOnFurniture = function() return false end, isMovablesCheat = function() return false end,
    isBuildCheat = function() return false end, hasTrait = function() return false end,
    isWearingAwkwardGloves = function() return false end,
    faceLocation = noop,
    getPlayerNum = function() return 0 end, getInventory = function() return inventory end,
    getPerkLevel = function() return 0 end, isTimedActionInstant = function() return false end,
    getMoodles = function() return {getMoodleLevel = function() return 0 end} end,
    getBodyDamage = function() return {getBodyPart = function() return {getPain = function() return 0 end} end} end,
    getTimedActionTimeModifier = function() return 1 end,
    getPathFindBehavior2 = function() return {cancel = noop} end, setPath2 = noop,
    setTimedActionToRetrigger = noop, setIsFarming = noop, getJoypadBind = function() return -1 end,
    StopAllActionQueue = function() stopped = stopped + 1 end, StartAction = noop}
function player:getCurrentSquare() return self.square end
player.getSquare = player.getCurrentSquare
function player:getX() return self.square.x + 0.5 end
function player:getY() return self.square.y + 0.5 end
function player:getPrimaryHandItem() return self.hand end
getSpecificPlayer = function() return player end
LuaTimedActionNew = {new = function()
    return {isStarted = function() return true end, forceComplete = noop, forceStop = noop,
        setCurrentTime = noop, getJobDelta = function() return 0 end}
end}
native('shared/TimedActions/ISBaseTimedAction.lua')
native('client/TimedActions/ISTimedActionQueue.lua')
native('client/TimedActions/ISQueueActionsAction.lua')
native('client/TimedActions/WalkToTimedAction.lua')
native('server/BuildingObjects/ISBuildingObject.lua')
local nativeTryBuild = ISBuildingObject.tryBuild
native('server/BuildingObjects/ISRemovePlantCursor.lua')
native('server/BuildingObjects/ISSelectCursor.lua')
native('server/BuildingObjects/ISPickCharacterCursor.lua')
native('server/Animal/ISScytheGrassCursor.lua')
native('shared/TimedActions/ISRemoveBush.lua')
native('shared/TimedActions/ISRemoveGrass.lua')
native('shared/TimedActions/ISScything.lua')
-- Additional native skipBuildAction producers share the same entry boundary.
getDebug = function() return false end
native('server/Fishing/BuildingObjects/FishingNet.lua')
native('server/BuildingObjects/ISDestroyCursor.lua')
native('server/FireFighting/ISExtinguishCursor.lua')
ISMoveableCursor = ISBuildingObject:derive('ISMoveableCursor')
ISMoveableCursor.mode = {}
for _, name in ipairs({'create', 'cannotCreate', 'isValid'}) do
    nativeFunction('server/BuildingObjects/ISMoveableCursor.lua', '(function ISMoveableCursor:' .. name .. '%(.-\nend)')
end
ISPlace3DItemCursor = ISBuildingObject:derive('ISPlace3DItemCursor')
for _, name in ipairs({'create', 'walkTo'}) do
    nativeFunction('server/BuildingObjects/ISPlace3DItemCursor.lua', '(function ISPlace3DItemCursor:' .. name .. '%(.-\nend)')
end
nativeFunction('shared/Moveables/ISMoveableSpriteProps.lua', '(function ISMoveableSpriteProps:walkToAndEquip%(.-\nend)')
for _, name in ipairs({'findOnSquare', 'getFaceDirectionFromSpriteName'}) do
    nativeFunction('shared/Moveables/ISMoveableSpriteProps.lua', '(function ISMoveableSpriteProps:' .. name .. '%(.-\nend)')
end
native('shared/TimedActions/Fishing/TimedActions/ISPlaceFishingNetAction.lua')
native('shared/TimedActions/ISDismantleAction.lua')
native('shared/TimedActions/ISDestroyStuffAction.lua')
native('shared/TimedActions/ISPutOutFire.lua')
native('shared/TimedActions/ISDropWorldItemAction.lua')
native('shared/Moveables/ISMoveablesAction.lua')
ISMoveableDefinitions = {cheat = false}
FireFighting = {isExtinguisher = function(item) return item == cuttingTool end,
    getExtinguisherUses = function() return 1 end}
convertToPZNetTable = function(value) return value end
local nativeLifecycle = {}
for _, class in ipairs({ISRemoveBush, ISRemoveGrass, ISScything}) do
    local methods = {}; nativeLifecycle[class] = methods
    for _, name in ipairs({'start','stop','perform','complete','isValid','animEvent','serverStart'}) do methods[name] = class[name] end
end
ISInventoryTransferAction = {canMergeAction = function() return true end}
ISContextMenu, ISButton, ISInventoryPane = {}, {}, {}
local equipClass = ISBaseTimedAction:derive('ISEquipWeaponAction')
ISInventoryPaneContextMenu = {equipWeapon = function(item, _, _, playerNum)
    assert(playerNum == 0)
    local action = ISBaseTimedAction.new(equipClass, player)
    action.item = item; ISTimedActionQueue.add(action)
end}
ISInventoryPaneContextMenu.getContainers = function() return list({}) end
ISInventoryPaneContextMenu.transferIfNeeded = noop
ISWorldObjectContextMenu = {equip = function(character, _, item)
    ISInventoryPaneContextMenu.equipWeapon(item, true, false, character:getPlayerNum())
end}
ISWorldObjectContextMenu.equip2 = function() end
ISWorldObjectContextMenu.transferIfNeeded = noop
local worldSource = read('client/ISUI/ISWorldObjectContextMenu.lua')
local callbacks = {assert(worldSource:match('(local function predicateCutPlant.-\nend)'))}
for _, name in ipairs({'onRemovePlant','doRemovePlant','onRemoveGrass','doRemoveGrass','onScytheGrass'}) do
    callbacks[#callbacks + 1] = assert(worldSource:match('(ISWorldObjectContextMenu%.' .. name .. ' = function.-\nend)'))
end
assert(loadstring(table.concat(callbacks, '\n'), '@' .. NativeActionRoot .. '/client/ISUI/ISWorldObjectContextMenu.lua'))()
ISDisassembleMenu = {disassemble = noop}
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueOperations.lua'))()
local plantClass, scytheClass = ISRemovePlantCursor, ISScytheGrassCursor
ISRemovePlantCursor, ISScytheGrassCursor = nil, nil
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueWorld.lua'))()
ISRemovePlantCursor, ISScytheGrassCursor = plantClass, scytheClass
assert(install)()
local tryBuildHook = ISBuildingObject.tryBuild
install(); assert(ISBuildingObject.tryBuild == tryBuildHook, 'late cursor hook must install once')
local world, operations = PZSurvivorToolkit.ActionQueueWorld, PZSurvivorToolkit.ActionQueueOperations
-- Load the real shared completion/settlement boundaries. Edit-permission
-- decisions are outside this producer fixture, so their hooks are inert.
PZSurvivorToolkit.ActionQueuePolicy = {isCraftAction = function() return false end,
    live = function(queue) return queue.character == player and not player:isDead() end,
    stoppable = function() return false end, resumableWorld = function() return false end,
    adoptBegin = noop, replaceStop = noop, skipUnavailableHygiene = noop,
    hygieneUnavailable = function() return false end}
PZSurvivorToolkit.ActionQueueLabels = {label = function(action) return action.Type end}
for _, name in ipairs({'ActionQueueSettlement', 'ActionQueueLifecycle', 'ActionQueueAcknowledgements', 'ActionQueue'}) do
    assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/' .. name .. '.lua'))()
end
local q = ISTimedActionQueue.getTimedActionQueue(player)
local origin = square(0, 0)
local function reset()
    enabled, stopped, drag, inventory.tool, player.hand, player.square = true, 0, nil, cuttingTool, cuttingTool, origin
    player.cancel = false
    q.queue, q.current = {}, nil
end
local function enqueueTail()
    local tail = ISBaseTimedAction.new(ISBaseTimedAction, player)
    tail.Type = 'UnrelatedTail'; operations.run(function() ISTimedActionQueue.add(tail) end); return tail
end
local function selectPlant(kind)
    if kind == 'grass' then ISWorldObjectContextMenu.onRemoveGrass(nil, nil, 0)
    else ISWorldObjectContextMenu.onRemovePlant(nil, nil, kind == 'wallVine', 0) end
    assert(drag and drag.Type == 'ISRemovePlantCursor'); return drag
end
local function click(cursor, value) cursor:tryBuild(value.x, value.y, value.z) end
local function expand(command)
    assert(q.queue[1] == command and q.current == command and operations.isCommand(command))
    command:start()
    assert(stopped == 0, 'native preparation must preserve unrelated work')
    command:perform()
end
local function finish(action)
    assert(q.queue[1] == action)
    if action.Type == 'ISWalkToTimedAction' then player.square = action.location
    elseif action.Type == 'ISEquipWeaponAction' then player.hand = action.item end
    action:perform()
end
local function expandApproaches()
    while q.queue[1] and operations.isCommand(q.queue[1]) do expand(q.queue[1]) end
end
local function findRemoval(value)
    for _, action in ipairs(q.queue) do
        if (action.Type == 'ISRemoveBush' or action.Type == 'ISRemoveGrass') and action.square == value then return action end
    end
end
local function advanceUntilOperation(token)
    while q.queue[1] and q.queue[1].toolkitQueueOperation ~= token do
        if operations.isCommand(q.queue[1]) then expand(q.queue[1]) else finish(q.queue[1]) end
    end
end

-- Actual context-menu cursor modes share inherited walking and each click owns
-- all approach/equipment/removal steps. Preparation uses the future position.
for index, kind in ipairs({'bush', 'grass', 'wallVine'}) do
    reset()
    local firstSquare, secondSquare = square(10 + index * 10, 0, kind), square(1, 1, kind)
    local cursor = selectPlant(kind)
    click(cursor, firstSquare)
    local firstRemoval = assert(findRemoval(firstSquare), 'native producer must retain its action contract')
    expandApproaches()
    local active = q.queue[1]
    assert(active.Type == 'ISWalkToTimedAction' and active.location == firstSquare)
    local activeToken = active.toolkitQueueOperation
    click(cursor, secondSquare)
    local secondRemoval = assert(findRemoval(secondSquare))
    local secondToken = secondRemoval.toolkitQueueOperation
    assert(q.queue[1] == active and stopped == 0, 'second target must preserve the active native first operation')
    assert(secondToken ~= activeToken, 'separate clicks must have separate operation identities')
    local tail = enqueueTail()
    advanceUntilOperation(secondToken)
    assert(player.square == firstSquare)
    expandApproaches()
    local walking = q.queue[1]
    assert(walking.Type == 'ISWalkToTimedAction' and walking.location == secondSquare,
        'approach must use the future position after moving away from an initially nearby target')
    assert(secondRemoval.Type == (kind == 'grass' and 'ISRemoveGrass' or 'ISRemoveBush'))
    assert(kind == 'grass' or secondRemoval.wallVine == (kind == 'wallVine'))
    assert(walking.toolkitQueueOperation == secondToken and q.queue[#q.queue] == tail)
    assert(firstRemoval.toolkitQueueOperation == activeToken and tail.toolkitQueueOperation ~= secondToken)
end

-- Native subclasses use shared preparation without a cursor-type whitelist.
reset()
local derived = ISRemovePlantCursor:derive('ForeignPlantCursor')
local subclassCursor = derived:new(player, 'grass')
local subclassSquare = square(70, 0, 'grass')
local predecessor = enqueueTail()
click(subclassCursor, subclassSquare)
assert(q.queue[1] == predecessor and stopped == 0 and findRemoval(subclassSquare))
local removal = findRemoval(subclassSquare)
assert(removal.toolkitQueueOperation ~= predecessor.toolkitQueueOperation)
finish(predecessor); expandApproaches()
assert(q.queue[1].Type == 'ISWalkToTimedAction' and q.queue[1].location == subclassSquare)

-- Failed future routing rejects only its dependent operation.
reset()
local blocked = square(71, 0, 'grass'); local viable = square(72, 0, 'grass')
predecessor = enqueueTail()
click(selectPlant('grass'), blocked)
local blockedRemoval = assert(findRemoval(blocked))
click(selectPlant('grass'), viable)
local viableRemoval = assert(findRemoval(viable))
local tail = enqueueTail()
blocked.blocked = true
finish(predecessor)
expandApproaches()
assert(not findRemoval(blocked), 'unreachable approach must reject its not-yet-started dependent action')
assert(q.queue[#q.queue] == tail and not viableRemoval.cancelled and stopped == 0)
assert(q:indexOf(viableRemoval) ~= -1, 'route failure must preserve the next selected operation')
blocked.blocked = false

-- A square can unload while earlier work runs. Native routing must reject its
-- operation normally, rather than throwing out the independently queued tail.
reset()
local unloaded = square(75, 0, 'grass')
click(selectPlant('grass'), unloaded)
local unloadedTail = enqueueTail()
squares[key(unloaded.x, unloaded.y, unloaded.z)] = nil
expandApproaches()
assert(#q.queue == 1 and q.queue[1] == unloadedTail and not findRemoval(unloaded),
    'an unloaded target must settle its dependent operation and preserve the independent tail')
squares[key(unloaded.x, unloaded.y, unloaded.z)] = unloaded

-- A late wrapper on an unrelated native cursor cannot poison a direct helper
-- request whose own route callbacks and selected target remain unchanged.
reset()
predecessor = enqueueTail()
local directTarget = square(76, 0)
local directDependent = ISBaseTimedAction.new(ISBaseTimedAction, player)
operations.run(function()
    assert(luautils.walkAdj(player, directTarget, false))
    ISTimedActionQueue.add(directDependent)
end)
local scytheWalk = ISScytheGrassCursor.walkTo
ISScytheGrassCursor.walkTo = function(...) return scytheWalk(...) end
finish(predecessor)
expandApproaches()
ISScytheGrassCursor.walkTo = scytheWalk
assert(q.queue[1].Type == 'ISWalkToTimedAction' and q.queue[1].location == directTarget
    and q.queue[#q.queue] == directDependent,
    'unrelated native cursor rebinding must not reject the direct walk operation')

-- A native walking failure after successful route selection still settles
-- only its own operation, through the shared stop/completion boundary.
for _, cause in ipairs({'failed', 'cancel', 'interrupted'}) do
    reset()
    local destination = square(73, 0, 'grass')
    click(selectPlant('grass'), destination)
    local dependent = assert(findRemoval(destination))
    local independent = enqueueTail()
    expandApproaches()
    local walking = q.queue[1]
    assert(walking.Type == 'ISWalkToTimedAction')
    player.cancel = cause == 'cancel'
    walking.result = cause == 'failed' and BehaviorResult.Failed or BehaviorResult.Working
    walking:stop()
    if cause ~= 'failed' then
        assert(#q.queue == 0, cause .. ' must retain whole-queue native interruption semantics')
    else
        assert(q.queue[1] == walking and q.toolkitCancelStopped, 'owned path failure waits for native removal')
        q:tick()
        assert(#q.queue == 1 and q.queue[1] == independent and not findRemoval(destination),
            'owned path failure must drop the dependent action and preserve the independent operation')
    end
end
reset()
predecessor = enqueueTail()
luautils.walkAdj(player, square(74, 0))
assert(stopped == 1 and q.queue[1] ~= predecessor,
    'unscoped manual movement must retain native queue replacement')

-- A loaded target at a chunk boundary may need a corrected square that has
-- unloaded. That is an ordinary route refusal, while native fallbacks and
-- branches that never use correction must retain their original behavior.
for index, route in ipairs({'direct', 'floor', 'excluded-current', 'alt-near'}) do
    reset()
    local value = square(140 + index * 10, 0)
    value.has = function(_, flag) return flag == IsoFlagType.collideW end
    squares[key(value.x + 1, value.y, value.z)] = nil
    local fallback = square(value.x - 1, value.y)
    value.wallSquare = fallback
    predecessor = enqueueTail()
    local dependent = ISBaseTimedAction.new(ISBaseTimedAction, player)
    operations.run(function()
        local accepted
        if route == 'floor' then
            local cursor = setmetatable({Type = 'ISWoodenFloor', player = 0, character = player,
                create = ISRemovePlantCursor.create}, {__index = ISBuildingObject})
            accepted = cursor:walkTo(value.x, value.y, value.z)
        elseif route == 'excluded-current' then
            accepted = luautils.walkAdj(player, value, false, {origin})
        elseif route == 'alt-near' then
            accepted = luautils.walkAdjAltTest(player, value, square(value.x, value.y + 1), false)
        else accepted = luautils.walkAdj(player, value, false) end
        assert(accepted == true, 'initial dispatch must preserve the accepted native approach contract')
        ISTimedActionQueue.add(dependent)
    end)
    local pending = assert(q.queue[2])
    local independent = enqueueTail()
    finish(predecessor); expandApproaches()
    assert(pending._isAddingActions == nil, 'route refusal must close the native adding-actions boundary')
    assert(q.queue[#q.queue] == independent and stopped == 0)
    if route == 'direct' then
        assert(#q.queue == 1 and q.queue[1] == independent,
            'unloaded corrected square must reject only the dependent operation without throwing')
    elseif route == 'alt-near' then
        assert(q.queue[1] == dependent and #q.queue == 2,
            'native alt-near success must not require an unused corrected square')
    else
        assert(q.queue[1].Type == 'ISWalkToTimedAction'
            and q.queue[1].location == (route == 'floor' and fallback or value)
            and q.queue[2] == dependent,
            route .. ' must retain native routing when the corrected square is unavailable')
    end
end

-- Defer the routing ancestor as a unit: a failed first route must still try
-- the native floor/wall or moveable opposite-square fallback at execution.
for _, route in ipairs({'floor', 'wall', 'moveable'}) do
    reset()
    local value = square(100, 100)
    local fallback = square(99, 100)
    local corrected = square(101, 100)
    corrected.blocked = true
    value.blocked, value.wallSquare = true, fallback
    value.has = function(_, flag) return flag == IsoFlagType.collideW end
    fallback.getFloor = function() return {} end
    local cursor = {Type = route == 'floor' and 'ISWoodenFloor' or 'ForeignApproachCursor',
        player = 0, character = player, north = true, isWallLike = route == 'wall', create = ISRemovePlantCursor.create}
    setmetatable(cursor, {__index = ISBuildingObject})
    if route == 'moveable' then cursor.currentMoveProps = setmetatable({}, {__index = ISMoveableSpriteProps}) end
    predecessor = enqueueTail()
    local dependent = ISBaseTimedAction.new(ISBaseTimedAction, player)
    operations.run(function()
        assert(cursor:walkTo(value.x, value.y, value.z), 'accepted deferred approach must preserve the native boolean contract')
        ISTimedActionQueue.add(dependent)
    end)
    assert(q.queue[1] == predecessor and stopped == 0)
    cursor.north, cursor.isWallLike = false, false
    finish(predecessor); expandApproaches()
    assert(q.queue[1].Type == 'ISWalkToTimedAction' and q.queue[1].location == fallback,
        route .. ' must retain native routing fallback and selected receiver state')
    assert(q.queue[#q.queue] == dependent)
    if route == 'wall' then assert(value.lastNorth == true, 'wall direction must retain its selected value') end
end

-- Helper-specific trailing arguments and receiver-independent route data must
-- survive queuing. Native helpers return a boolean, never a queue/action table.
reset()
local helperTarget = square(110, 0)
local excluded = {square(111, 0)}
local selectedExcluded = excluded[1]
predecessor = enqueueTail()
local helperDependent = ISBaseTimedAction.new(ISBaseTimedAction, player)
operations.run(function()
    local accepted = luautils.walkAdj(player, helperTarget, false, excluded)
    assert(accepted == true and type(accepted) == 'boolean')
    ISTimedActionQueue.add(helperDependent)
end)
excluded[1] = origin
finish(predecessor); expandApproaches()
assert(q.queue[1].location == helperTarget and helperTarget.lastExcluded[1] == selectedExcluded,
    'exclude-list selection must not change when its caller mutates the table')
assert(q.queue[#q.queue] == helperDependent and stopped == 0)

-- Scythes retain their own native routing and selected per-action radius.
reset()
local scytheTarget = square(80, 0, 'scythe')
for x = 80, 82 do for y = 0, 2 do if not getSquare(x, y, 0) then square(x, y, 'scythe') end end end
ISWorldObjectContextMenu.onScytheGrass(player, scythe)
local scytheCursor = assert(drag)
click(scytheCursor, scytheTarget)
local queuedScythe
for _, value in ipairs(q.queue) do if value.Type == 'ISScything' then queuedScythe = value end end
scytheCursor.radius = 1
assert(queuedScythe and queuedScythe.sq == scytheTarget and queuedScythe.radius == 3)
expandApproaches()
assert(q.queue[1].Type == 'ISWalkToTimedAction')

-- Disabled behavior and synchronous UI/custom callback contracts remain native.
reset(); enabled = false
local original = enqueueTail(); local disabledSquare = square(90, 0, 'grass')
click(selectPlant('grass'), disabledSquare)
assert(stopped == 1 and q.queue[1] ~= original and q.queue[#q.queue].Type == 'ISRemoveGrass')
reset(); local custom = selectPlant('bush'); local customCalls = 0
custom.create = function() customCalls = customCalls + 1 end
original = enqueueTail(); click(custom, square(91, 0, 'bush'))
assert(customCalls == 1 and stopped == 1 and q.queue[1] ~= original,
    'untrusted custom callbacks must retain their synchronous native routing')
reset()
local selectionCalls = 0
local selectionUI = {cursor = {}, onSquareSelected = function() selectionCalls = selectionCalls + 1 end}
local selector = ISSelectCursor:new(player, selectionUI, selectionUI.onSquareSelected)
local unreachableSelection = square(93, 0); unreachableSelection.blocked = true
original = enqueueTail(); click(selector, unreachableSelection)
assert(selectionCalls == 0 and stopped == 1 and q.queue[1] ~= original,
    'a failed native selector route must not optimistically invoke its irreversible synchronous callback')
reset()
local pickCalls, selectedCharacter = 0, {}
local picker = ISPickCharacterCursor:new(player)
picker.isValidCharacter = function() return true end
picker.onPickCharacter = function(_, selected) assert(selected == selectedCharacter); pickCalls = pickCalls + 1 end
local unreachablePick = square(94, 0)
unreachablePick.blocked = true
unreachablePick.getMovingObjects = function() return list({selectedCharacter}) end
assert(picker:isValid(unreachablePick))
original = enqueueTail(); click(picker, unreachablePick)
assert(pickCalls == 0 and stopped == 1 and q.queue[1] ~= original,
    'native character-picker create must retain synchronous route-dependent selection semantics')

local function findType(kind)
    for _, action in ipairs(q.queue) do if action.Type == kind then return action end end
end
local function cursorAt(class, value)
    return setmetatable({Type = class.Type, character = player, player = 0, skipBuildAction = true,
        renderX = value.x, renderY = value.y, renderZ = value.z, sprite = 'fixture', nSprite = 1}, class)
end

-- FishingNet's native tryBuild permits a valid water target even if walking
-- fails. That OR branch must remain part of the accepted preparation contract.
for _, fallback in ipairs({false, true}) do
    reset()
    local value = square(fallback and 3 or 1, 0)
    value.flags = {[IsoFlagType.water] = true}
    value.blocked = fallback
    local cursor = fishingNet:new(player, cuttingTool)
    predecessor = enqueueTail()
    click(cursor, value)
    local placing = assert(findType('ISPlaceFishingNetAction'))
    assert(q.queue[1] == predecessor and stopped == 0,
        'native fishing-net placement must preserve its active predecessor')
    assert(PZSurvivorToolkit.ActionQueueApproach.isAction(q.queue[2]), 'fishing-net native route must actually defer')
    local independent = enqueueTail()
    if not fallback then player.square = square(220, 0) end
    finish(predecessor); expandApproaches()
    if fallback then
        assert(q.queue[1] == placing and not placing.cancelled,
            'native valid-water fallback must retain placement after a failed walk')
    else
        assert(q.queue[1].Type == 'ISWalkToTimedAction' and q.queue[1].location == value,
            'fishing-net approach must route from the future position')
    end
    assert(q.queue[#q.queue] == independent and placing.square == value)
end

-- Native destroy enumeration is reverse square order. Preserve the selected
-- object, then reindex it at execution rather than trusting its old list slot.
local function destroyObject(value, door)
    local props = {has = function(_, flag) return not door and flag == IsoFlagType.solidfloor end}
    return {class = 'IsoThumpable', getSquare = function() return value end,
        getObjectIndex = function() return 0 end, getProperties = function() return props end,
        getType = function() return door and IsoObjectType.doorFrN or 'fixture' end,
        isDoor = function() return false end,
        isDismantable = function() return true end, hasProperty = function() return false end}
end
for _, mode in ipairs({'reindexed', 'removed', 'floor-fallback'}) do
    reset()
    local value = square(230, 0)
    local selected, other = destroyObject(value, mode ~= 'floor-fallback'), destroyObject(value, true)
    value.objects = {other, selected}
    local cursor = ISDestroyCursor:new(player, true)
    cursor.renderX, cursor.renderY, cursor.renderZ = value.x, value.y, value.z
    predecessor = enqueueTail()
    click(cursor, value)
    local dismantle = assert(findType('ISDismantleAction'))
    assert(dismantle.thumpable == selected and q.queue[1] == predecessor and stopped == 0,
        'native destroy cursor must retain its selected object and active predecessor')
    assert(PZSurvivorToolkit.ActionQueueApproach.isAction(q.queue[2]), 'destroy native route must actually defer')
    local independent = enqueueTail()
    cursor.objectIndex, cursor.renderX = 2, 999
    if mode == 'removed' then value.objects = {other}
    elseif mode == 'reindexed' then value.objects = {other, selected, destroyObject(value, true)}
    else value.blocked = true; value.wallSquare = square(229, 0) end
    finish(predecessor); expandApproaches()
    if mode == 'removed' then
        assert(q.queue[1] == independent and not findType('ISDismantleAction'),
            'a removed selected destroy object must reject its group, not retarget its old list index')
    elseif mode == 'reindexed' then
        assert(value.lastDoor == selected and q.queue[1].location == value,
            'native destroy routing must resolve the originally selected object after enumeration changes')
    else
        assert(q.queue[1].location == value.wallSquare,
            'native destroy floor routing must retain its wall fallback without clearing earlier work')
    end
    assert(q.queue[#q.queue] == independent and stopped == 0)
end

reset()
local guardedSquare = square(232, 0)
local guardedObject = destroyObject(guardedSquare, true)
guardedSquare.objects = {guardedObject}
local guardedCursor = ISDestroyCursor:new(player, true)
guardedCursor.renderX, guardedCursor.renderY, guardedCursor.renderZ = guardedSquare.x, 0, 0
predecessor = enqueueTail()
click(guardedCursor, guardedSquare)
assert(PZSurvivorToolkit.ActionQueueApproach.isAction(q.queue[2]))
local guardedTail = enqueueTail()
local objectListCallback, selectorCalls = ISDestroyCursor.getObjectList, 0
ISDestroyCursor.getObjectList = function(...)
    selectorCalls = selectorCalls + 1; return objectListCallback(...)
end
finish(predecessor); expandApproaches()
ISDestroyCursor.getObjectList = objectListCallback
assert(q.queue[1] == guardedTail and selectorCalls == 0 and not findType('ISDismantleAction'),
    'replaced native selector authority must reject its dependent group before invoking the foreign callback')

-- The shared native cursor route must accept only World's exact owned create
-- wrapper. Its props route is still evaluated from the future player position.
reset()
local moveSquare = square(1, 0)
local moveObject = destroyObject(moveSquare, false)
local moveSprite = {getName = function() return 'fixture_moveable' end,
    getProperties = function() return {has = function() return false end} end}
moveObject.getSprite = function() return moveSprite end
moveSquare.objects = {moveObject}
local moveProps = setmetatable({type = 'fixture', object = moveObject, sprite = moveSprite,
    spriteName = 'fixture_moveable', isMoveable = false,
    spriteProps = moveSprite:getProperties(), canPickUpMoveable = function() return true end,
    getYOffsetCursor = function() return 0 end}, {__index = ISMoveableSpriteProps})
moveObject.props = moveProps
ISMoveableSpriteProps.fromObject = function(object) return object.props end
getPlayerRadialMenu = function() return nil end
local movingCursor = cursorAt(ISMoveableCursor, moveSquare)
movingCursor.currentSquare, movingCursor.currentMoveProps = moveSquare, moveProps
movingCursor.origSpriteName, movingCursor.canCreate = moveProps.spriteName, true
movingCursor.objectIndex = 1
movingCursor.objectListCache = {{object = moveObject, moveProps = moveProps}}
movingCursor.setInfoPanel = noop
ISMoveableCursor.mode[0] = 'pickup'
predecessor = enqueueTail()
click(movingCursor, moveSquare)
local moving = assert(findType('ISMoveablesAction'))
assert(q.queue[1] == predecessor and stopped == 0 and moving.object == moveObject,
    'owned World moveable create wrapper must retain common queued routing')
assert(PZSurvivorToolkit.ActionQueueApproach.isAction(q.queue[2]), 'moveable native route must actually defer')
local moveIndependent = enqueueTail()
local selectedProps = movingCursor.currentMoveProps
movingCursor.currentMoveProps = {walkAdj = function() error('mutable cursor props were used') end}
player.square = square(236, 0)
finish(predecessor); expandApproaches()
assert(q.queue[1].Type == 'ISWalkToTimedAction' and q.queue[1].location == moveSquare
    and q.queue[#q.queue] == moveIndependent and selectedProps == moveProps,
    'native moveable route must preserve its selected props across mutable cursor state')
reset()
local ownedMoveCreate = ISMoveableCursor.create
local moveCreateBody = assert(world.nativeMoveableCreate(ownedMoveCreate),
    'World must attest its exact live create wrapper for shared preparation')
assert(getFilenameOfClosure(moveCreateBody):match('/ISMoveableCursor.lua$'))
ISMoveableCursor.create = function(...) return ownedMoveCreate(...) end
local proven = world.nativeMoveableCreate and world.nativeMoveableCreate(ISMoveableCursor.create)
assert(not proven, 'a foreign wrapper must not inherit World native create authority')
ISMoveableCursor.create = ownedMoveCreate
local moveCursorClass = ISMoveableCursor
ISMoveableCursor = setmetatable({create = ownedMoveCreate}, {__index = moveCursorClass})
assert(not world.nativeMoveableCreate(ownedMoveCreate), 'replacement classes must not inherit World create authority')
ISMoveableCursor = moveCursorClass

-- Extinguishing chooses the closest member of its native 2x2 area when the
-- route reaches the head. Joypad create remains relative to the current actor.
reset()
local fireOrigin = square(240, 0)
local fireEast = square(241, 0)
square(240, 1); square(241, 1)
local extinguisher = ISExtinguishCursor:new(player, cuttingTool)
predecessor = enqueueTail()
click(extinguisher, fireOrigin)
local extinguishing = assert(findType('ISPutOutFire'))
assert(q.queue[1] == predecessor and stopped == 0)
assert(PZSurvivorToolkit.ActionQueueApproach.isAction(q.queue[2]), 'mouse extinguish native route must actually defer')
player.square = square(250, 0)
finish(predecessor); expandApproaches()
assert(q.queue[1].Type == 'ISWalkToTimedAction' and q.queue[1].location == fireEast,
    'native extinguish mouse routing must choose its closest square from the future actor position')
assert(extinguishing.squares[1] == fireOrigin and extinguishing.squares[2] == fireEast)
reset()
local nativeJoypad = player.getJoypadBind
player.getJoypadBind = function() return 0 end
player.isOnFire = function() return true end
local joypadSquare = player.square
local joypadCursor = ISExtinguishCursor:new(player, cuttingTool)
predecessor = enqueueTail()
click(joypadCursor, fireOrigin)
local joypadAction = assert(findType('ISPutOutFire'))
assert(q.queue[1] == predecessor and joypadAction.squares[1] == joypadSquare,
    'native joypad extinguish create must select its actor-relative area synchronously')
for _, action in ipairs(q.queue) do assert(not action.toolkitQueueApproach, 'joypad no-op walk must not queue stale relative intent') end
player.getJoypadBind = nativeJoypad

-- Place3D has a synchronous no-op cursor walk, while its actual create body
-- routes through the common helpers and consumes the immediate UI item choice.
reset()
local dropTarget, itemSquare = square(260, 0), square(1, 0)
local item = {getActualWeight = function() return 1 end}
local placingCursor = cursorAt(ISPlace3DItemCursor, dropTarget)
placingCursor.chr, placingCursor.itemSq, placingCursor.selectedSqDrop = player, itemSquare, dropTarget
placingCursor.items = {item}
player.isEquipped = function() return false end
isShiftKeyDown = function() return false end
predecessor = enqueueTail()
click(placingCursor, dropTarget)
local dropping = assert(findType('ISDropWorldItemAction'))
assert(q.queue[1] == predecessor and stopped == 0 and #placingCursor.items == 0,
    'native placement UI selection must remain synchronous while approach helpers preserve the predecessor')
assert(PZSurvivorToolkit.ActionQueueApproach.isAction(q.queue[2]), 'Place3D create helper must actually defer')
assert(dropping.item == item and dropping.sq == dropTarget)
player.square = square(270, 0)
finish(predecessor); expandApproaches()
assert(q.queue[1].Type == 'ISWalkToTimedAction' and q.queue[1].location == itemSquare,
    'native Place3D create helper must defer routing from the future position')
print('Native producer approach contracts: fishing fallback, destroy identity/guards, owned moveable routing, mouse/joypad fire and Place3D selection passed.')

-- Recovery captures native argument intent, then builds a fresh command and
-- token. It neither reuses the old action nor follows later argument mutation.
reset()
local approach = PZSurvivorToolkit.ActionQueueApproach
-- Provenance consumers retain the live dispatcher while checking its original
-- native body. An unrelated replacement never inherits that proof.
local helper=luautils.walkAdj
local originalHelper=assert(approach.nativeHelper(luautils,'walkAdj',helper))
assert(originalHelper~=helper and getFilenameOfClosure(originalHelper):match('luautils.lua$'))
assert(not approach.nativeHelper(luautils,'walk',helper))
assert(not approach.nativeHelper({walkAdj=helper},'walkAdj',helper))
luautils.walkAdj=function(...)return helper(...)end
assert(not approach.nativeHelper(luautils,'walkAdj',luautils.walkAdj))
assert(not approach.nativeHelper(luautils,'walkAdj',helper),'stale dispatcher inherited native proof')
luautils.walkAdj=helper
assert(approach.nativeHelper(luautils,'walkAdj',helper)==originalHelper)
predecessor = enqueueTail()
local recoverySquare, recoveryExcluded = square(120, 0), {square(121, 0)}
local intendedExclusion = recoveryExcluded[1]
operations.run(function() assert(luautils.walkAdj(player, recoverySquare, false, recoveryExcluded)) end)
local capturedCommand = assert(q.queue[2])
local handle = assert(approach.capture(capturedCommand), 'pending direct native approach must capture recoverable intent')
assert(not approach.rebuild({}, handle) and not approach.rebuild(player, {}), 'recovery seals must belong to the original actor')
-- Preview must reject foreign constructors before invoking them. Checking the
-- constructed action afterward cannot undo a constructor's side effects.
for _, variant in ipairs({'queue-new', 'base-new', 'queue-class', 'base-class', 'command-factory'}) do
    local queueClass, baseClass = ISQueueActionsAction, ISBaseTimedAction
    local queueNew, baseNew = queueClass.new, baseClass.new
    local commandFactory = operations.command
    local calls = 0
    local function foreignQueueNew(...)
        calls = calls + 1; return queueNew(...)
    end
    local function foreignBaseNew(...)
        calls = calls + 1; return baseNew(...)
    end
    if variant == 'queue-new' then queueClass.new = foreignQueueNew
    elseif variant == 'base-new' then baseClass.new = foreignBaseNew
    elseif variant == 'queue-class' then ISQueueActionsAction = setmetatable({new = foreignQueueNew}, {__index = queueClass})
    elseif variant == 'base-class' then ISBaseTimedAction = setmetatable({new = foreignBaseNew}, {__index = baseClass})
    else operations.command = function(...) calls = calls + 1; return commandFactory(...) end end
    local captured = approach.capture(capturedCommand)
    local ok, candidate = pcall(approach.rebuild, player, handle)
    ISQueueActionsAction, ISBaseTimedAction = queueClass, baseClass
    queueClass.new, baseClass.new = queueNew, baseNew
    operations.command = commandFactory
    assert(ok and candidate == nil and calls == 0,
        variant .. ': recovery must refuse changed class/constructor before executing foreign code; calls=' .. calls)
    assert(captured == nil, variant .. ': changed constructor authority must block pending-intent capture')
    local restored = assert(approach.rebuild(player, handle), variant .. ': restoring constructors must permit a fresh rebuild')
    assert(restored ~= capturedCommand and restored.action == nil and restored.toolkitQueueOperation == nil)
end
capturedCommand.toolkitQueueCommand.snapshot.args[4][1] = origin
operations.invalidate(capturedCommand.toolkitQueueOperation)
local recovered = assert(approach.rebuild(player, handle))
assert(recovered ~= capturedCommand and recovered.action == nil and recovered.toolkitQueueOperation == nil,
    'recovery must construct a fresh unstarted command without a canceled operation token')
local helperCallback = luautils.walkAdj
luautils.walkAdj = function(...) return helperCallback(...) end
assert(not approach.rebuild(player, handle), 'changed route callbacks must revoke recovery intent')
luautils.walkAdj = helperCallback
squares[key(recoverySquare.x, recoverySquare.y, recoverySquare.z)] = nil
assert(not approach.rebuild(player, handle), 'recovery must reject unloaded target squares')
squares[key(recoverySquare.x, recoverySquare.y, recoverySquare.z)] = recoverySquare
reset()
operations.run(function() ISTimedActionQueue.add(recovered) end)
assert(recovered.toolkitQueueOperation ~= capturedCommand.toolkitQueueOperation and not approach.capture(recovered),
    'started recovered commands cannot be captured as pending intent')
expandApproaches()
assert(q.queue[1].location == recoverySquare and recoverySquare.lastExcluded[1] == intendedExclusion,
    'recovered approach must retain the captured selection and execute native routing')
reset(); predecessor = enqueueTail()
click(selectPlant('grass'), square(122, 0, 'grass'))
assert(not approach.capture(q.queue[2]), 'mutable cursor receivers must stay outside the direct-helper recovery contract')
for class, methods in pairs(nativeLifecycle) do
    for name, callback in pairs(methods) do assert(class[name] == callback, 'native lifecycle must remain unchanged: ' .. name) end
end
assert(nativeTryBuild ~= ISBuildingObject.tryBuild)
print('Vegetation native contracts: bush/grass/vines and subclass FIFO, future walking, operation identity, route rejection, scythe radius, disabled/custom callbacks and native lifecycle passed.')

-- Reuse the established policy fixture rather than weakening the production
-- edit guards in the producer harness above. Pending preparation must remain
-- transparent to whole-operation edits while protecting its dependent body.
getFilenameOfClosure = NativeFilenameOfClosure or function(callback)
    local filename = debug.getinfo(callback, 'S').source:gsub('^@', '')
    if filename:match('^client/') or filename:match('^shared/') or filename:match('^server/') then
        return NativeActionRoot .. '/' .. filename
    end
    return filename
end
getGameFilesInput = function(path)
    local source = read(path:gsub('^media/lua/', ''))
    local position = 1
    return {close = noop, readLine = function()
        if position > #source then return end
        local boundary = source:find('\n', position, true) or #source + 1
        local line = source:sub(position, boundary - 1); position = boundary + 1; return line
    end}
end
local fixture = assert(loadfile(ProjectRoot .. '/tests/support/action_queue_native.lua'))()
local policyPlayer = fixture.player
policyPlayer.class = 'IsoPlayer'
policyPlayer.isLocalPlayer = function() return true end
policyPlayer.isDraggingCorpse = function() return false end
policyPlayer.square = origin
policyPlayer.getCurrentSquare = function(self) return self.square end
policyPlayer.getSquare = policyPlayer.getCurrentSquare
policyPlayer.getX = function(self) return self.square:getX() + 0.5 end
policyPlayer.getY = function(self) return self.square:getY() + 0.5 end
luautils = {}
nativeFunction('shared/luautils.lua', '(luautils.getCorrectSquareForWall = function.-\nend)')
nativeFunction('shared/luautils.lua', '(function luautils.walkAdj%(.-\nend)')
local policyOps = fixture.project('ActionQueueOperations')
fixture.project('ActionQueueDefinitions')
local policyApproach = fixture.project('ActionQueueApproach'); policyApproach.install()
local actualPolicy = fixture.project('ActionQueuePolicy')
local function bookAction()
    local book = fixture.item('Base.BookCarpentry1')
    book.getUnequippedWeight = function() return 0.1 end
    book.getIsCraftingConsumed = function() return false end
    book.getType = function() return 'BookCarpentry1' end
    return fixture.action(ISReadABook, {item = book})
end
local head, middle, body = bookAction(), bookAction(), bookAction()
local editQueue = fixture.queue(head, middle)
local policyTarget = square(130, 0)
body.toolkitQueueOperation = nil
policyOps.run(function()
    assert(luautils.walkAdj(policyPlayer, policyTarget, false))
    ISTimedActionQueue.add(body)
end)
local pendingApproach = assert(editQueue.queue[3])
assert(policyApproach.isAction(pendingApproach) and pendingApproach.toolkitQueueOperation == body.toolkitQueueOperation)
local cancel = actualPolicy.evaluateCancel(editQueue, pendingApproach, true)
assert(cancel.allowed and cancel.first == 3 and cancel.last == 4,
    'a pending approach and its supported body must retain whole-operation cancellation: ' .. tostring(cancel.reason))
local move = actualPolicy.evaluateMove(editQueue, pendingApproach, middle, false)
assert(move.allowed and move.first == 3 and move.last == 4 and move.to == 2,
    'pending native approach must not make an otherwise independent operation opaque to reordering: ' .. tostring(move.reason))
PZSurvivorToolkit.ActionQueueLabels = {label = function(action) return action.Type end}
local queueAPI = fixture.project('ActionQueue')
assert(queueAPI.cancel(editQueue, pendingApproach), 'the public cancellation entrypoint must accept the pending command group')
assert(#editQueue.queue == 2 and editQueue.queue[1] == head and editQueue.queue[2] == middle
    and editQueue:indexOf(pendingApproach) == -1 and editQueue:indexOf(body) == -1,
    'canceling a command row must remove its whole dependent operation and preserve preceding operations')
policyOps.run(function()assert(luautils.walkAdj(policyPlayer, policyTarget, false))end)
local standalone=assert(editQueue.queue[3])
assert(policyApproach.isAction(standalone) and queueAPI.cancel(editQueue,standalone),
    'a scoped approach without a later body must remain cancelable as its own operation')
assert(#editQueue.queue==2 and editQueue.queue[1]==head and editQueue.queue[2]==middle)
print('Approach pending intent capture/rebuild and actual-policy whole-operation edit contracts passed.')
