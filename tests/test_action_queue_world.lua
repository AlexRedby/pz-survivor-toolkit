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
local installWorldQueue, buildStateEvent
Events = {OnServerCommand = {Add = function(callback) buildStateEvent = callback end}, OnTick = {Add = function() end}, OnGameStart = {Add = function(callback) installWorldQueue = callback end}}
for _, name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState',
    'ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do
    _G[name] = {instance = function() return {} end}
end
table.wipe = function(t) for k in pairs(t) do t[k] = nil end end
instanceof = function(value, name) return value and (value.class == name or (name == 'IsoObject' and value.class == 'IsoDoor')) end
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
Events.OnDoTileBuilding2 = {Add = function() end}
Events.OnDoTileBuilding3 = {Add = function() end}
Events.OnKeyPressed = {Add = function() end}
Events.OnDestroyIsoThumpable = {Add = function() end}
Events.RenderOpaqueObjectsInWorld = {Add = function() end}
native('server/BuildingObjects/ISBuildingObject.lua')
native('client/BuildingObjects/TimedActions/ISBuildAction.lua')
local nativeBuildStart, nativeBuildPerform, nativeBuildStop = ISBuildAction.start, ISBuildAction.perform, ISBuildAction.stop
ISBuildIsoEntity = ISBuildingObject:derive('ISBuildIsoEntity')
nativeFunction('server/BuildingObjects/ISBuildIsoEntity.lua', '(function ISBuildIsoEntity:tryBuild.-\nend)')
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
player.getOnlineID = function() return 17 end
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
    a.moveProps = object and object.moveProps
    a.isValidObject = function(self) return self.square.exists ~= false end
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
local cursorHook, menuHook, buildHook = ISMoveableCursor.create, ISDisassembleMenu.disassemble, ISBuildingObject.tryBuild
installWorldQueue()
assert(ISMoveableCursor.create == cursorHook and ISDisassembleMenu.disassemble == menuHook and ISBuildingObject.tryBuild == buildHook)
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
    object.moveProps = props
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
        forceComplete = function(self) self.completed = true end, forceStop = function(self) self.stopped = true end}
    deferred:start()
end
reset()
local first = seed()
local door = target('Metal door')
player.square = door.square.walkSquare
ISDisassembleMenu.disassemble(player, door)
local deferred = q.queue[2]
assert(#q.queue == 2 and q.queue[1] == first and stopped == 0)
assert(PZSurvivorToolkit.ActionQueueWorld.isDeferredAction(deferred))
assert(not PZSurvivorToolkit.ActionQueueWorld.isDeferredAction({Type = 'ISQueueActionsAction', toolkitWorldDismantle = true, addActionsFunction = deferred.addActionsFunction}))
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

-- Native entity building also implements stock wood/sheet-metal/metal-bar barricade placement.
local world = PZSurvivorToolkit.ActionQueueWorld
DebugType = {Lua = {debugln = function() end}}
Perks, ItemTag, CharacterTrait = {Woodwork = 'woodwork'}, {HAMMER = 'hammer'}, {HANDY = 'handy'}
ISBuildMenu = {cheat = false}
isClient = function() return false end
player.getInventory = function() return {} end
player.getPerkLevel = function() return 0 end
player.isTimedActionInstant = function() return false end
player.hasTrait = function() return false end
player.isBuildCheat = function() return false end
copyTable = function(source)
    local result = {}; for k, v in pairs(source) do result[k] = v end; return result
end
local buildSquare = {name = 'build target'}
getCell = function() return {getGridSquare = function(_, x, y, z)
    assert(x == 12 and y == 34 and z == 1, 'placement must retain the selected square')
    return buildSquare
end, setDrag = function() end} end
local containers, materials, tool, records = {}, true, true, {}
ISInventoryPaneContextMenu.getContainers = function() return containers end
BuildLogic = {new = function()
    local logic = {}
    function logic:setContainers(value) self.containers = value end
    function logic:setRecipe(value) self.recipe = value end
    function logic:copyManualInputsFrom(other) self.selected = other.selected end
    function logic:updateFloorContainer() self.refreshed = true end
    function logic:canPerformCurrentRecipe() return materials and tool and self.recipe == 'build recipe' end
    function logic:startCraftAction(value) self.current = value; records[#records + 1] = self end
    function logic:stopCraftAction() self.current = nil end
    return logic
end}
local function buildCursor(kind, name)
    local script = {getTimedActionOnIsValid = function() return 'nativeRecipeValidity' end,
        getOnCreate = function() return nil end, getOnIsValid = function() return nil end}
    local cursor = setmetatable({Type = kind, character = player, player = 0, name = name, north = true,
        sprite = 'original build sprite', northSprite = 'original build sprite', nSprite = 2, modData = {['need:Base.Plank'] = 1}, noNeedHammer = true,
        objectInfo = {getScript = function() return script end}, craftRecipe = 'build recipe',
        getFace = function() return {getWidth = function() return 2 end, getHeight = function() return 1 end, getzLayers = function() return 1 end} end,
        buildPanelLogic = kind == 'ISBuildIsoEntity' and BuildLogic.new() or nil,
        isValid = function(self, square) return square == buildSquare and materials and tool end,
        walkTo = function(self)
            return luautils.walkAdjWindowOrDoor(player, {walkSquare = {name = 'future build approach'}}, {class = 'IsoDoor'}, false)
        end}, {__index = kind == 'ISBuildIsoEntity' and ISBuildIsoEntity or ISBuildingObject})
    if cursor.buildPanelLogic then
        cursor.buildPanelLogic:setRecipe('build recipe'); cursor.buildPanelLogic.selected = 'original manual item'
    end
    return cursor
end
for _, name in ipairs({'Wooden barricade', 'Metal sheet barricade', 'Metal bar barricade', 'Wall'}) do
    reset(); materials, tool, records = true, true, {}; first = seed(); player.square = {}
    local build = buildCursor('ISBuildIsoEntity', name)
    build:tryBuild(12, 34, 1)
    deferred = q.queue[2]
    assert(#q.queue == 2 and stopped == 0 and not build.buildPanelLogic.current)
    assert(world.isDeferredAction(deferred) and deferred.toolkitWorldOperation == 'build' and deferred.toolkitWorldName == name)
    local selection = build.buildPanelLogic
    build.north, build.nSprite, build.sprite = false, 4, 'rotated sprite'
    build.modData['need:Base.Plank'] = 99
    selection.recipe, selection.selected = 'another recipe', 'replacement item'
    tail = action('LaterOperation'); ISTimedActionQueue.add(tail)
    containers = {name = 'future containers'}
    expand(deferred)
    local constructed = q.queue[#q.queue - 1]
    assert(constructed.Type == 'ISBuildAction' and q.queue[#q.queue] == tail and stopped == 0)
    assert(constructed.x == 12 and constructed.y == 34 and constructed.z == 1 and constructed.north
        and constructed.item.nSprite == 2 and constructed.spriteName == 'original build sprite')
    assert(constructed.item.modData['need:Base.Plank'] == 1 and constructed.item.modData ~= build.modData)
    assert(constructed.item.buildPanelLogic ~= selection and constructed.item.buildPanelLogic.containers == containers
        and constructed.item.buildPanelLogic.selected == 'original manual item' and constructed.onIsValid == 'nativeRecipeValidity')
    assert(selection.current == nil and #records == 1 and records[1].current == constructed)
    assert(q.queue[2].Type == 'ISWalkToTimedAction' and q.queue[2].toolkitQueueOperation == deferred.toolkitQueueOperation
        and constructed.toolkitQueueOperation == deferred.toolkitQueueOperation)
    assert(world.canResume(constructed) and world.sharesTarget(deferred, constructed))
    assert(world.sharesTarget(deferred, {toolkitWorldX = 13, toolkitWorldY = 34, toolkitWorldZ = 1}))
    assert(not world.sharesTarget(deferred, {toolkitWorldX = 14, toolkitWorldY = 34, toolkitWorldZ = 1}))
    local resumed = world.resume(constructed)
    assert(world.isDeferredAction(resumed) and resumed ~= deferred)
    constructed.onCompleteFunc = function() end
    assert(not world.canResume(constructed) and not world.resume(constructed), 'foreign callbacks cannot be resumed')
end
for _, missing in ipairs({'materials', 'tool'}) do
    reset(); materials, tool, records = true, true, {}; seed()
    local build = buildCursor('ISBuildIsoEntity', 'Missing ' .. missing)
    build:tryBuild(12, 34, 1); deferred = q.queue[2]
    if missing == 'materials' then materials = false else tool = false end
    expand(deferred)
    assert(#records == 0 and #q.queue == 1 and stopped == 0, 'missing resources must not prepare or submit a build')
end
-- Legacy supported build cursors revalidate placement/materials and retain native preparation.
reset(); materials, tool = true, true; seed(); player.square = {}
local legacy = buildCursor('ISWoodenWall', 'Legacy wall')
legacy:tryBuild(12, 34, 1); deferred = q.queue[2]; legacy.north = false
expand(deferred)
assert(q.queue[#q.queue].Type == 'ISBuildAction' and q.queue[#q.queue].north and stopped == 0)
reset(); seed(); materials = true
legacy = buildCursor('ISWoodenWall', 'Missing legacy materials'); legacy:tryBuild(12, 34, 1)
deferred = q.queue[2]; materials = false; expand(deferred)
assert(#q.queue == 1 and stopped == 0)
-- Disabled building retains native replacement; skip-build UI/tool cursors do not get deferred.
reset(); materials, tool, enabled = true, true, false; first = seed(); player.square = {}
buildCursor('ISBuildIsoEntity', 'Disabled build'):tryBuild(12, 34, 1)
assert(stopped == 1 and q.queue[1] ~= first and q.queue[#q.queue].Type == 'ISBuildAction')
enabled = true
print('World building native contracts: wood/metal barricades, future materials/tools, isolated recipe/manual inputs, rotation, legacy path, tokens, resume factories and disabled behavior passed.')

-- The same interrupted scrap command rebuilds native preparation, including attached-sprite cursor state.
reset(); seed(); door = target('Resume scrap'); player.square = {}
ISDisassembleMenu.disassemble(player, door); deferred = q.queue[2]; expand(deferred)
local originalScrap = q.queue[#q.queue]
assert(world.canResume(originalScrap))
local resumeScrap = world.resume(originalScrap)
assert(world.isDeferredAction(resumeScrap) and resumeScrap.toolkitWorldTarget == door.object)
q.queue = {resumeScrap}; q.current = resumeScrap
player.square, player.hand = {}, {}
resumeScrap.action = {isStarted = function() return true end, forceComplete = function() end, forceStop = function() end}
resumeScrap:start()
assert(q.queue[#q.queue].Type == 'ISMoveablesAction' and q.queue[#q.queue] ~= originalScrap
    and q.queue[#q.queue].object == door.object and stopped == 0)
door.square.exists = false
assert(not world.canResume(originalScrap) and not world.resume(originalScrap))
-- Placement footprints protect overlapping entity tiles and legacy furniture/stairs/doors.
for _, case in ipairs({{'ISDoubleTileFurniture', 34 - 1, 1}, {'ISWoodenStairs', 34 - 2, 2}, {'ISDoubleDoor', 34, 1}}) do
    reset(); seed(); materials, tool = true, true
    local build = buildCursor(case[1], 'Footprint')
    build:tryBuild(12, 34, 1); deferred = q.queue[2]
    assert(world.sharesTarget(deferred, {toolkitWorldX = 12, toolkitWorldY = case[2], toolkitWorldZ = case[3]}))
end
-- Stock barricade context menu selects an entity cursor; all three material variants use the same hook.
nativeFunction('client/ISUI/ISWorldObjectContextMenu.lua', '(function ISWorldObjectContextMenu.onBarricade.-\nend)')
local drag
getCell = function() return {getGridSquare = function() return buildSquare end,
    setDrag = function(_, value) drag = value end} end
local oldNew = ISBuildIsoEntity.new
ISBuildIsoEntity.new = function(_, character, info, rotation, selectedContainers)
    assert(character == player and rotation == 1 and selectedContainers == containers)
    local cursor = buildCursor('ISBuildIsoEntity', info.name); cursor.info = info; return cursor
end
SpriteConfigManager = {getObjectInfoFromSprite = function(sprite) return {name = sprite} end}
for _, sprite in ipairs({'wood barricade sprite', 'metal sheet sprite', 'metal bars sprite'}) do
    reset(); seed(); materials, tool = true, true
    ISWorldObjectContextMenu.onBarricade(sprite, player)
    assert(drag.info.name == sprite and drag.dragNilAfterPlace == false)
    drag:tryBuild(12, 34, 1)
    assert(#q.queue == 2 and world.isDeferredAction(q.queue[2]) and stopped == 0)
end
ISBuildIsoEntity.new = oldNew
print('World queue resume/footprint/native barricade cursor contracts passed.')

assert(ISBuildAction.start == nativeBuildStart and ISBuildAction.perform == nativeBuildPerform and ISBuildAction.stop == nativeBuildStop,
    'native build transaction/start/completion/cancel semantics must remain unchanged')
-- Instant/custom cursors still execute the original path rather than a delayed placement command.
reset(); seed(); materials, tool = true, true; player.square = {}
local instant = buildCursor('ISWoodenWall', 'Instant cursor')
local created = 0
instant.skipBuildAction = true
instant.create = function() created = created + 1 end
instant:tryBuild(12, 34, 1)
assert(created == 1 and stopped == 1 and not world.isDeferredAction(q.queue[#q.queue]))
print('World native transaction callbacks and instant-cursor behavior unchanged.')

-- Empty native generators forceStop and erase the tail; toolkit commands complete normally instead.
player.setIsFarming = function() end
ISLogSystem = {logAction = function() end}
for _, missing in ipairs({'materials', 'placement', 'scrap target'}) do
    reset(); seed(); materials, tool = true, true
    if missing == 'scrap target' then
        local removed = target('Gone after enqueue')
        ISDisassembleMenu.disassemble(player, removed); deferred = q.queue[2]; removed.square.exists = false
    else
        local build = buildCursor('ISBuildIsoEntity', 'Invalid future command')
        if missing == 'placement' then build.isValid = function() return false end end
        build:tryBuild(12, 34, 1); deferred = q.queue[2]
        if missing == 'materials' then materials = false end
    end
    tail = action('Unrelated tail'); ISTimedActionQueue.add(tail)
    expand(deferred)
    assert(deferred.action.completed and not deferred.action.stopped and #q.queue == 2 and q.queue[2] == tail)
    assert(world.isDeferredAction(deferred))
    deferred:perform()
    assert(#q.queue == 1 and q.current == tail and tail.started and stopped == 0,
        'invalid command must complete through native lifecycle and start unrelated tail')
    local ownedStart = deferred.start
    deferred.start = ISQueueActionsAction.start
    assert(not world.isDeferredAction(deferred), 'foreign start handlers cannot borrow trusted callbacks')
    deferred.start = ownedStart
end
print('World empty-command native completion preserves unrelated tail.')

reset()
local ordinary = ISQueueActionsAction:new(player, function() end)
tail = action('Native empty-generator tail')
q.queue, q.current = {ordinary, tail}, ordinary
ordinary.action = {isStarted = function() return true end, forceStop = function(self) self.stopped = true end, forceComplete = function(self) self.completed = true end}
ordinary:start()
assert(ordinary.action.stopped and not ordinary.action.completed)
ordinary:stop()
assert(#q.queue == 0, 'stock empty generators still keep their native reset behavior')
-- Errors remain errors; the native update fallback is still available for a failed owned command.
reset(); seed(); materials, tool = true, true
local failedBuild = buildCursor('ISBuildIsoEntity', 'Broken validation callback')
failedBuild.isValid = function() error('fixture validation failed') end
failedBuild:tryBuild(12, 34, 1); deferred = q.queue[2]
q:removeFromQueue(q.queue[1]); q.current = deferred
deferred.action = {forceComplete = function(self) self.completed = true end, forceStop = function(self) self.stopped = true end}
local ok, failure = pcall(function() deferred:start() end)
assert(not ok and tostring(failure):find('fixture validation failed') and not deferred.action.completed)
deferred:update()
assert(deferred.action.stopped, 'native generator fallback must still stop on an actual exception')
print('World command completion changes only expected empty validation results; native failure handling preserved.')

-- MP replay requires a server-started UUID bound to this exact active native action.
reset(); seed(); materials, tool = true, true; player.square = {}
isClient = function() return true end
local mpBuild = buildCursor('ISBuildIsoEntity', 'MP stacked crate')
mpBuild:tryBuild(12, 34, 1); deferred = q.queue[2]
assert(world.isDeferredAction(deferred) and #q.queue == 2 and stopped == 0)
expand(deferred)
local mpConstructed = q.queue[#q.queue]
assert(mpConstructed.Type == 'ISBuildAction' and mpConstructed.maxTime == -1 and stopped == 0)
local allowed, reason = world.canResume(mpConstructed)
assert(not allowed and reason == 'move_world_transaction' and not world.resume(mpConstructed))
local token = '12345678-1234-1234-1234-123456789abc'
local function acknowledge(state, overrides)
    local args = {player = 17, transaction = -128, token = token, state = state}
    for key, value in pairs(overrides or {}) do args[key] = value end
    buildStateEvent('PZSurvivorToolkitBuild', 'State', args)
end
-- Waiting, unstarted and copied actions cannot borrow a matching signed byte.
mpConstructed.transactionId = -128
acknowledge('started'); assert(not world.canResume(mpConstructed))
q.queue, q.current = {mpConstructed}, mpConstructed
mpConstructed.action, mpConstructed.started = {}, true
for _, args in ipairs({{player = 18}, {transaction = 128}, {transaction = -127}, {transaction = 1.5},
    {token = 'invalid'}, {state = 'unknown'}}) do
    acknowledge('started', args); assert(not world.canResume(mpConstructed))
end
acknowledge('canceled'); assert(not world.canResume(mpConstructed), 'terminal cannot bind an unknown UUID')
acknowledge('started'); assert(world.canResume(mpConstructed))
local ack = world.buildAcknowledgement(mpConstructed)
assert(ack and ack.token == token and world.buildState(mpConstructed, ack) == 'started')
local clone = {}; for key, value in pairs(mpConstructed) do clone[key] = value end
assert(not world.canResume(clone) and not world.buildState(clone, ack))
acknowledge('started', {token = '22345678-1234-1234-1234-123456789abc'})
assert(world.buildAcknowledgement(mpConstructed) == ack, 'duplicate starts never replace the bound UUID')
acknowledge('completed', {token = '22345678-1234-1234-1234-123456789abc'})
assert(world.buildState(mpConstructed, ack) == 'started', 'foreign terminal ignored')
acknowledge('canceled')
assert(world.buildState(mpConstructed, ack) == 'canceled' and not world.canResume(mpConstructed))
assert(not world.resume(mpConstructed) and world.isDeferredAction(world.resume(mpConstructed, ack)))
acknowledge('completed'); assert(world.buildState(mpConstructed, ack) == 'canceled', 'terminal is immutable')
local originalX = mpConstructed.x; mpConstructed.x = originalX + 1
assert(not world.buildState(mpConstructed, ack) and not world.resume(mpConstructed, ack), 'retargeted snapshots fail closed')
mpConstructed.x = originalX
-- Reused native signed bytes cannot bind the previous known token.
reset(); materials, tool = true, true
buildCursor('ISBuildIsoEntity', 'Next MP build'):tryBuild(12, 34, 1)
local nextBuild = q.queue[#q.queue]
q.queue, q.current = {nextBuild}, nextBuild
nextBuild.transactionId, nextBuild.started, nextBuild.action = -128, true, {}
acknowledge('started'); assert(not world.canResume(nextBuild))
acknowledge('started', {token = '32345678-1234-1234-1234-123456789abc'})
local nextAck = world.buildAcknowledgement(nextBuild); assert(nextAck)
acknowledge('canceled'); assert(world.buildState(nextBuild, nextAck) == 'started', 'prior transaction terminal cannot cancel a reused byte')
acknowledge('completed', {token = nextAck.token})
assert(world.buildState(nextBuild, nextAck) == 'completed' and not world.resume(nextBuild, nextAck))
isClient = function() return false end
assert(world.canResume(mpConstructed), 'single-player native building remains resumable')
-- Scrap completion removes its target, so replay revalidates existence in MP as in SP.
reset(); seed(); door = target('MP scrap'); player.square = {}
isClient = function() return true end
ISDisassembleMenu.disassemble(player, door); deferred = q.queue[2]; expand(deferred)
assert(world.canResume(q.queue[#q.queue]) and world.isDeferredAction(world.resume(q.queue[#q.queue])))
isClient = function() return false end

-- Native barricade completion targets S/E adjacent squares and scans objects in reverse order.
local function positionedSquare(x, y, z, list)
    local square = {getX = function() return x end, getY = function() return y end, getZ = function() return z end}
    square.getObjects = function() return {size = function() return #list end,
        get = function(_, index) return list[index + 1] end,
        contains = function(_, object) for _, member in ipairs(list) do if member == object then return true end end; return false end} end
    return square
end
BuildRecipeCode = {barricade = {}}
nativeFunction('server/BuildRecipeCode/buildRecipeCode.lua', '(function BuildRecipeCode.barricade.OnCreate.-\nend)')
ArrayList = {new = function() return {isEmpty = function() return true end} end}
isServer = function() return false end
getWorld = function() return {getCell = function() return getCell() end} end
for _, facing in ipairs({'n', 'w', 's', 'e'}) do
    reset(); seed(); materials, tool = true, true; player.square = {}
    local north = facing == 'n' or facing == 's'
    local objects = {}
    local tx, ty = 12 + (facing == 'e' and 1 or 0), 34 + (facing == 's' and 1 or 0)
    local square = positionedSquare(tx, ty, 1, objects)
    local original = {class = 'IsoDoor', getNorth = function() return north end, getSquare = function() return square end}
    objects[1] = {class = 'IsoDoor', getNorth = function() return north end, getSquare = function() return square end}
    objects[2] = original
    getCell = function() return {getGridSquare = function(_, x, y, z)
        if x == tx and y == ty and z == 1 then return square end
        return buildSquare
    end, setDrag = function() end} end
    local build = buildCursor('ISBuildIsoEntity', 'Canonical barricade')
    local script = build.objectInfo:getScript()
    script.getOnCreate = function() return 'BuildRecipeCode.barricade.OnCreate' end
    build.getFace = function() return {getWidth = function() return 1 end, getHeight = function() return 1 end,
        getzLayers = function() return 1 end, getFaceName = function() return facing end} end
    build.isValid = function() return true end
    build:tryBuild(12, 34, 1); deferred = q.queue[2]
    assert(deferred.toolkitWorldTarget == original, 'canonical target must match native facing and reverse object scan')
    local placement = (facing == 'n' or facing == 'w') and square or positionedSquare(12, 34, 1, {})
    local completedTarget, completedOpposite
    for _, member in ipairs(objects) do
        member.getOppositeSquare = function() return (facing == 's' or facing == 'e') and placement or nil end
        member.getBarricadeOnSameSquare = function() return nil end
        member.getBarricadeOnOppositeSquare = function() return nil end
        member.addBarricadesFromCraftRecipe = function(self, _, _, _, opposite)
            completedTarget, completedOpposite = self, opposite
        end
    end
    BuildRecipeCode.barricade.OnCreate({thumpable = {getSquare = function() return placement end, hasModData = function() return false end},
        craftRecipeData = {getAllRecordedConsumedItems = function() return nil end}, character = player, facing = facing})
    assert(completedTarget == deferred.toolkitWorldTarget and completedOpposite == (facing == 's' or facing == 'e'),
        'snapshot dependency target must match actual native completion callback')
    local scrapTarget = {object = original}
    assert(world.sharesTarget(deferred, scrapTarget) and world.sharesTarget(scrapTarget, deferred))
    -- A removed/replaced door must not silently retarget the queued barricade.
    objects[2] = {class = 'IsoDoor', getNorth = function() return north end, getSquare = function() return square end}
    tail = action('Tail after removed target'); ISTimedActionQueue.add(tail)
    expand(deferred)
    assert(deferred.action.completed and #q.queue == 2 and q.queue[2] == tail and stopped == 0)
end
local function objectAt(x, y, z)
    local square = positionedSquare(x, y, z, {})
    return {class = 'IsoDoor', getSquare = function() return square end}
end
local footprint = {toolkitWorldX = 12, toolkitWorldY = 34, toolkitWorldZ = 1,
    toolkitWorldWidth = 2, toolkitWorldHeight = 1, toolkitWorldLayers = 2}
assert(world.sharesTarget(footprint, {object = objectAt(13, 34, 2)}))
assert(world.sharesTarget({object = objectAt(13, 34, 2)}, footprint))
assert(not world.sharesTarget(footprint, {object = objectAt(14, 34, 1)}))
assert(not world.sharesTarget(footprint, {object = objectAt(12, 34, 3)}))
-- Multi-tile moveables intersect even if their origin object lies outside the build footprint.
local origin = objectAt(11, 34, 1)
local multi = {object = origin, moveProps = {object = origin,
    getSpriteGridTopLeft = function(_, x, y) assert(x == 11 and y == 34); return x, y end,
    getMultiTileSquares = function() return {positionedSquare(11, 34, 1, {}), positionedSquare(12, 34, 1, {})} end}}
assert(world.sharesTarget(footprint, multi) and world.sharesTarget(multi, footprint))
print('World MP resume transaction gate and canonical/multi-tile build-scrap dependencies passed.')

-- A removed native scrap target can be skipped after stop/removal without claiming world completion.
nativeFunction('shared/Moveables/ISMoveablesAction.lua', '(function ISMoveablesAction:isValidObject.-\nend)')
local missing = target('Tracked removed scrap')
missing.square.getObjects = function() return {
    size = function() return missing.square.exists == false and 0 or 1 end,
    get = function(_, index) return index == 0 and missing.object or nil end,
} end
local trackedScrap = ISMoveablesAction:new(player, missing.square, 'scrap', nil, missing.object, 'N', nil, nil)
trackedScrap.isValidObject = ISMoveablesAction.isValidObject
assert(not world.targetGone(trackedScrap), 'existing targets retain native lifecycle')
missing.square.exists = false
assert(world.targetGone(trackedScrap) and not world.canResume(trackedScrap))
assert(not world.targetGone(nil))
assert(not world.targetGone({Type = 'ISMoveablesAction', mode = 'scrap', object = missing.object,
    square = missing.square, moveProps = missing.moveProps, isValidObject = ISMoveablesAction.isValidObject}))
local cloned = {}; for key, value in pairs(trackedScrap) do cloned[key] = value end
assert(not world.targetGone(cloned), 'a copied record is not the constructor-owned action')
for _, changed in ipairs({'mode', 'object', 'square', 'moveProps'}) do
    local original = trackedScrap[changed]
    trackedScrap[changed] = changed == 'mode' and 'pickup' or {}
    assert(not world.targetGone(trackedScrap), 'retargeted or different-mode records must fail closed: ' .. changed)
    trackedScrap[changed] = original
end
assert(world.targetGone(trackedScrap))
print('World targetGone: exact constructor-owned scrap, native missing-object check and retarget protection passed.')

-- MP NetTimedAction.set uses constructor parameter names to look up action fields for serialization.
local function readSource(path)
    if NativeReadText then return NativeReadText(path) end
    local file = assert(io.open(path)); local source = file:read('*a'); file:close(); return source
end
local nativeConstructor = assert(readSource(NativeActionRoot .. '/shared/Moveables/ISMoveablesAction.lua')
    :match('function ISMoveablesAction:new%s*(%b())'))
local wrappedConstructor = assert(readSource(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueWorld.lua')
    :match('ISMoveablesAction.new%s*=%s*function%s*(%b())'))
local nativeParameters = ('(self,' .. nativeConstructor:sub(2)):gsub('%s+', '')
assert(wrappedConstructor:gsub('%s+', '') == nativeParameters,
    'native MP constructor field names/order must remain exact, including origSpriteName and moveCursor')
local attachedCursor = {}
local attached = ISMoveablesAction:new(player, missing.square, 'scrap', 'attached sprite', missing.object, 'W', nil, attachedCursor)
assert(attached.origSpriteName == 'attached sprite' and attached.moveCursor == attachedCursor
    and attached.toolkitWorldResume.snapshot.origSpriteName == 'attached sprite'
    and attached.toolkitWorldResume.snapshot.cursor == attachedCursor)
print('World native MP constructor field-name and attached-sprite/cursor contracts passed.')
