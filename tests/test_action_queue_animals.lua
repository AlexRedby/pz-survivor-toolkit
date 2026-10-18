if not NativeActionRoot then print('Animal butchering native-contract checks skipped.'); return end
require = function() end
local enabled = true
PZSurvivorToolkit = {Settings = {actionQueue = function() return enabled end}}
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseObject = {derive = derive}
local install
Events = setmetatable({OnGameStart = {Add = function(callback) install = callback end}},
    {__index = function() return {Add = function() end} end})
for _, name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState',
    'ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do
    _G[name] = {instance = function() return {} end}
end
table.wipe = function(t) for key in pairs(t) do t[key] = nil end end
instanceof = function(value, name) return value and value.class == name end
getText = function(key) return key end
isServer, isClient = function() return false end, function() return false end
ItemTag, Perks = {BUTCHER_ANIMAL = 'BUTCHER_ANIMAL'}, {Butchering = 'Butchering'}
ISLogSystem, AnimalAvatarDefinition = {logAction = function() end}, {}
local function native(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
local function nativeFunction(path, pattern)
    local source
    if NativeReadText then source = NativeReadText(NativeActionRoot .. '/' .. path)
    else
        local file = assert(io.open(NativeActionRoot .. '/' .. path)); source = file:read('*a'); file:close()
    end
    assert(loadstring(assert(source:gsub('\r', ''):match(pattern))))()
end
native('shared/TimedActions/ISBaseTimedAction.lua')
native('client/TimedActions/ISTimedActionQueue.lua')
native('client/TimedActions/ISQueueActionsAction.lua')
native('shared/TimedActions/Animals/ISButcherAnimal.lua')
AnimalContextMenu = {}
nativeFunction('client/ISUI/Animal/ISAnimalContextMenu.lua', '(AnimalContextMenu.onButcherAnimal = function.-\nend)')
local nativeCallback, nativeButcherNew = AnimalContextMenu.onButcherAnimal, ISButcherAnimal.new
luautils = {getCorrectSquareForWall = function(_, square) return square end,
    haveToBeTransfered = function() return false end}
nativeFunction('shared/luautils.lua', '(function luautils.walkAdj%(.-)\nfunction luautils.walkAdjTest')
ISWorldObjectContextMenu = {}
nativeFunction('client/ISUI/ISWorldObjectContextMenu.lua', '(function ISWorldObjectContextMenu.transferIfNeeded%(.-)\nISWorldObjectContextMenu.equip2')
ISBaseTimedAction.adjustMaxTime = function(_, duration) return duration end
ISInventoryTransferAction = ISBaseTimedAction:derive('ISInventoryTransferAction')
ISInventoryTransferAction.canMergeAction = function() return false end
ISEquipWeaponAction = ISBaseTimedAction:derive('ISEquipWeaponAction')
ISEquipWeaponAction.isValid = function() return true end
function ISEquipWeaponAction:new(character, item)
    local action = ISBaseTimedAction.new(self, character); action.item = item; return action
end
ISWalkToTimedAction = ISBaseTimedAction:derive('ISWalkToTimedAction')
ISWalkToTimedAction.isValid = function() return true end
function ISWalkToTimedAction:new(character, square)
    local action = ISBaseTimedAction.new(self, character); action.square = square; return action
end
ISContextMenu, ISButton, ISInventoryPaneContextMenu, ISInventoryPane = {}, {}, {}, {}
local inventory = {items = {}}
function inventory:getFirstTagEvalRecurse(tag, predicate)
    for _, item in ipairs(self.items) do if item:hasTag(tag) and predicate(item) then return item end end
end
local square = {getX = function(self) return self.x end, getY = function() return 0 end,
    canReachTo = function() return true end}
local player = {class = 'IsoPlayer', getPlayerNum = function() return 0 end,
    isDead = function(self) return self.dead == true end, getVehicle = function(self) return self.vehicle end,
    isAsleep = function() return false end, isLocalPlayer = function() return true end,
    isDraggingCorpse = function() return false end, isFarming = function() return false end,
    setIsFarming = function() end, setTimedActionToRetrigger = function() end,
    getInventory = function() return inventory end, getPrimaryHandItem = function(self) return self.primary end,
    getPerkLevel = function() return 0 end, isTimedActionInstant = function() return false end,
    getX = function(self) return self.x end, getY = function() return 0 end,
    getSquare = function() return square end, getCurrentSquare = function() return square end,
    faceThisObject = function() end, shouldBeTurning = function() return false end,
    SetVariable = function() end, reportEvent = function() end, playSound = function() return 1 end,
    getEmitter = function() return {isPlaying = function() return false end} end,
    StopAllActionQueue = function(self) self.stops = self.stops + 1 end}
getSpecificPlayer = function() return player end
local pathRequests = {}
AdjacentFreeTileFinder = {Find = function(target, character)
    pathRequests[#pathRequests + 1] = {target = target, from = character.x}; return target
end}
LuaTimedActionNew = {new = function(owner)
    return {owner = owner, isStarted = function(self) return self.started == true end,
        forceComplete = function(self) self.completed = true end,
        forceStop = function() error('invalid animal command must preserve unrelated work') end,
        setActionAnim = function() end}
end}
function player:StartAction(action)
    assert(action.owner:isValid(), 'Java StartAction validates before starting')
    if not action.owner:waitToStart() then action.started = true; action.owner:start() end
end
local completed = {}
ButcheringUtil = {butcherAnimalFromGround = function(body)
    assert(body:hasAnimalParts(), 'a corpse must never be butchered twice')
    body.parts = false; body.data.parts = nil; completed[#completed + 1] = body
end}
local function project(name)
    assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/' .. name .. '.lua'))()
end
project('ActionQueueOperations'); project('ActionQueueAnimals'); install()
local q = ISTimedActionQueue.getTimedActionQueue(player)
local function knife()
    return {class = 'InventoryItem', hasTag = function(_, tag) return tag == ItemTag.BUTCHER_ANIMAL end,
        isBroken = function(self) return self.broken == true end}
end
local function corpse(x)
    local target = {x = x or 0, getX = square.getX, getY = square.getY}
    return {square = target, parts = true, data = {parts = true}, index = 0,
        getSquare = function(self) return self.square end, getModData = function(self) return self.data end,
        hasAnimalParts = function(self) return self.parts end,
        getStaticMovingObjectIndex = function(self) return self.index end}
end
local function reset()
    q.queue, q.current, completed, pathRequests = {}, nil, {}, {}
    player.primary, player.stops, player.x, square.x = nil, 0, 0, 0
    player.dead, player.vehicle, inventory.items = false, nil, {knife()}
end
local function unrelated(name)
    local action = ISBaseTimedAction.new(ISBaseTimedAction, player)
    action.Type, action.isValid = name or 'UnrelatedTail', function() return true end
    ISTimedActionQueue.add(action); return action
end
local function step()
    local action = assert(q.current)
    if not action.action.started then
        assert(not action:waitToStart(), 'animal command must yield exactly once')
        action.action.started = true; action:start()
    end
    assert(action:isValid())
    if action.Type == 'ISQueueActionsAction' then
        assert(action.toolkitWorldOperation == 'butcher' and action.body, 'command must retain its corpse target')
        assert(action.action.completed, 'empty animal expansion must complete')
    elseif action.Type == 'ISEquipWeaponAction' then player.primary = action.item
    elseif action.Type == 'ISWalkToTimedAction' then player.x, square.x = action.square.x, action.square.x end
    -- Native SP advances the queue before complete() consumes the corpse parts.
    action:perform()
    if action.Type == 'ISButcherAnimal' then assert(action:complete()) end
    return action
end
local function drain()
    local remaining = 50
    while q.current do remaining = remaining - 1; assert(remaining > 0, 'animal queue stalled'); step() end
end
reset()
local active = unrelated('ActiveWork')
nativeCallback(corpse(), player, inventory.items[1])
assert(player.stops == 1 and q.current ~= active, 'native adjacent butchering must reproduce the active-action reset')

reset()
active = unrelated('ActiveWork')
local first, second = corpse(), corpse(8)
AnimalContextMenu.onButcherAnimal(first, player, inventory.items[1])
AnimalContextMenu.onButcherAnimal(second, player, inventory.items[1])
local ending = unrelated()
assert(q.current == active and active.action.started and #q.queue == 4 and player.stops == 0,
    'successive clicks must leave the active action and tail in place')
drain()
assert(#completed == 2 and completed[1] == first and completed[2] == second and ending.action.started and player.stops == 0,
    'both native butcher actions and unrelated work must finish in click order')
assert(ISButcherAnimal.new == nativeButcherNew, 'native constructor metadata must stay untouched')

reset(); active = unrelated('MoveBeforeButchering'); first = corpse(8)
AnimalContextMenu.onButcherAnimal(first, player, inventory.items[1]); ending = unrelated()
assert(#pathRequests == 0, 'click must not compute the path before earlier work finishes')
player.x, square.x = 20, 20; step(); step()
assert(#pathRequests == 1 and pathRequests[1].from == 20 and pathRequests[1].target == first.square,
    'dispatch must compute the route from the current player location')
drain(); assert(#completed == 1 and ending.action.started)

reset(); first = corpse()
AnimalContextMenu.onButcherAnimal(first, player, inventory.items[1])
AnimalContextMenu.onButcherAnimal(first, player, inventory.items[1]); ending = unrelated(); drain()
assert(#completed == 1 and ending.action.started, 'consumed duplicate corpse must skip without clearing the tail')
for _, change in ipairs({
    function(body) body.square = nil end,
    function(body) body.index = -1 end,
    function(body) body.parts = false; body.data.parts = nil end,
    function() inventory.items = {} end,
    function() inventory.items[1].broken = true end,
    function() player.dead = true end,
    function() player.vehicle = {} end,
}) do
    reset(); first = corpse(); active = unrelated('ActiveWork')
    AnimalContextMenu.onButcherAnimal(first, player, inventory.items[1]); ending = unrelated(); change(first); drain()
    assert(#completed == 0 and ending.action.started and player.stops == 0,
        'stale corpse, tool or player state must skip only the animal command')
end
for _, keepBroken in ipairs({false, true}) do
    reset(); first = corpse(); active = unrelated('ActiveWork')
    local previous, replacement = inventory.items[1], knife()
    AnimalContextMenu.onButcherAnimal(first, player, previous)
    previous.broken = true
    inventory.items = keepBroken and {previous, replacement} or {replacement}
    ending = unrelated(); drain()
    assert(player.primary == replacement and player.primary ~= previous and #completed == 1,
        'dispatch must replace a removed or broken context-menu knife with a current usable knife')
end

enabled = false; reset(); active = unrelated('ActiveWork'); first = corpse()
AnimalContextMenu.onButcherAnimal(first, player, inventory.items[1])
assert(player.stops == 1 and q.current ~= active and q.queue[#q.queue].Type == 'ISButcherAnimal',
    'disabled setting must retain the native immediate clear behavior')
drain(); assert(#completed == 1 and nativeCallback ~= AnimalContextMenu.onButcherAnimal)
print('Animal butchering native reset, deferred dispatch, stale targets, current tools and opt-out checks passed.')
