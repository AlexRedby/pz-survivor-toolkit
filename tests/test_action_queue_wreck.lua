if not NativeActionRoot then print('Wreck native-contract checks skipped.'); return end
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
ItemTag = {BLOW_TORCH = 'BLOW_TORCH', WELDING_MASK = 'WELDING_MASK'}
Perks, Metabolics = {MetalWelding = 'MetalWelding', Mechanics = 'Mechanics'}, {HeavyWork = 'HeavyWork'}
ZombRand, addXp = function() return 1 end, function() end
ISLogSystem = {logAction = function() end}
Vector3f = {new = function() return {} end}
local function native(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
local function nativeFunction(path, pattern)
    local source
    if NativeReadText then source = NativeReadText(NativeActionRoot .. '/' .. path)
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
native('shared/Vehicles/TimedActions/ISRemoveBurntVehicle.lua')
native('client/Vehicles/ISUI/ISVehicleMenu.lua')
local nativeWreckNew = ISRemoveBurntVehicle.new
local nativeCallback = ISVehicleMenu.onRemoveBurntVehicle
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
function ISEquipWeaponAction:new(character, item, duration, primary)
    local action = ISBaseTimedAction.new(self, character); action.item, action.primary = item, primary; return action
end
ISDisassembleMenu, ISMoveableCursor, ISBuildingObject = {disassemble = function() end}, {create = function() end}, {tryBuild = function() end}
ISMoveablesAction, ISVehiclePartMenu = {new = function() return {} end}, {}
ISContextMenu, ISButton, ISInventoryPane = {}, {}, {}
ISInventoryPaneContextMenu = {wearItem = function(item) item.worn = true end}
local inventory = {items = {}}
function inventory:getFirstEvalRecurse(predicate)
    for _, item in ipairs(self.items) do if predicate(item) then return item end end
end
function inventory:containsEvalRecurse(predicate) return self:getFirstEvalRecurse(predicate) ~= nil end
local player = {class = 'IsoPlayer', getPlayerNum = function() return 0 end,
    isDead = function() return false end, isAsleep = function() return false end,
    isLocalPlayer = function() return true end, isDraggingCorpse = function() return false end,
    isFarming = function() return false end, setIsFarming = function() end, setTimedActionToRetrigger = function() end,
    getInventory = function() return inventory end, getPrimaryHandItem = function(self) return self.primary end,
    getPerkLevel = function() return 0 end, isMechanicsCheat = function() return false end,
    isTimedActionInstant = function() return false end, getX = function() return 0 end, getY = function() return 0 end,
    playSound = function() return 1 end, getEmitter = function() return {stopSound = function() end} end,
    StopAllActionQueue = function(self) self.stops = self.stops + 1 end}
getSpecificPlayer = function() return player end
local square = {getX = function(self) return self.x or 0 end, getY = function() return 0 end,
    canReachTo = function() return true end}
AdjacentFreeTileFinder = {Find = function() return nil end}
player.getSquare, player.getCurrentSquare = function() return square end, function() return square end
LuaTimedActionNew = {new = function(owner)
    return {owner = owner, isStarted = function(self) return self.started == true end,
        forceComplete = function(self) self.completed = true end,
        forceStop = function() error('invalid wreck must skip without stopping unrelated work') end,
        setActionAnim = function() end, setOverrideHandModelsObject = function() end}
end}
function player:StartAction(action)
    assert(action.owner:isValid(), 'Java StartAction validates before starting')
    if not action.owner:waitToStart() then action.started = true; action.owner:start() end
end
local function project(name) assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/' .. name .. '.lua'))() end
project('ActionQueueOperations'); project('ActionQueueWorld'); install()
local world = PZSurvivorToolkit.ActionQueueWorld
local q = ISTimedActionQueue.getTimedActionQueue(player)
local completed = {}
local function item(kind, uses, tag)
    return {class = 'InventoryItem', uses = uses, getType = function() return kind end,
        hasTag = function(_, wanted) return tag == wanted end, getCurrentUses = function(self) return self.uses end,
        Use = function(self) self.uses = self.uses - 1; assert(self.uses >= 0) end,
        setJobDelta = function() end}
end
local function wreck()
    return {square = square, getSquare = function(self) return self.square end,
        isRemovedFromWorld = function(self) return self.removed == true end,
        permanentlyRemove = function(self) assert(not self.removed); self.removed = true end}
end
local function reset(items)
    q.queue, q.current, completed = {}, nil, {}
    player.primary, player.stops, inventory.items = nil, 0, items
    square.x = 0
end
local function tail()
    local action = ISBaseTimedAction.new(ISBaseTimedAction, player)
    action.Type, action.isValid = 'UnrelatedTail', function() return true end
    ISTimedActionQueue.add(action); return action
end
local function step()
    local action = assert(q.current)
    if not action.action.started then
        assert(not action:waitToStart(), 'wreck command must yield exactly once')
        action.action.started = true; action:start()
    end
    assert(action:isValid(), 'delayed equipment choices must survive previous native complete')
    if action.Type == 'ISQueueActionsAction' then
        assert(action.toolkitWorldOperation == 'wreck' and not world.isDeferredAction(action), 'wreck inputs stay protected')
        assert(action.action.completed, 'empty wreck expansion must complete')
    elseif action.Type == 'ISEquipWeaponAction' then
        player.primary = action.item
    end
    -- Java SP performs first; onCompleted synchronously begins the next command before resource consumption.
    action:perform()
    if action.Type == 'ISRemoveBurntVehicle' then
        assert(action:complete()); completed[#completed + 1] = action
    end
    return action
end
local function drain()
    local remaining = 40
    while q.current do remaining = remaining - 1; assert(remaining > 0, 'wreck queue stalled'); step() end
end
local mask = item('WeldingMask', nil)
local a, b = item('BlowTorch', 10), item('BlowTorch', 10)
local first, second = wreck(), wreck()
reset({a, b, mask})
ISVehicleMenu.onRemoveBurntVehicle(player, first)
assert(#q.queue == 1 and not q.current.action.started, 'first click must defer expansion until native completion is settled')
while q.current.Type ~= 'ISRemoveBurntVehicle' do step() end
local active = q.current
ISVehicleMenu.onRemoveBurntVehicle(player, second)
assert(q.current == active and active.action.started and not first.removed and player.stops == 0,
    'clicking another wreck must preserve the active native dismantling')
local ending = tail(); drain()
assert(#completed == 2 and completed[1].item == a and completed[2].item == b, 'successive wrecks must select successive fueled torches')
assert(first.removed and second.removed and a.uses == 0 and b.uses == 0 and ending.action.started and player.stops == 0,
    'native rewards/removal and unrelated tail must survive both callbacks')
assert(ISRemoveBurntVehicle.new == nativeWreckNew, 'MP constructor parameter metadata must remain untouched')
assert(world.wreckTargetGone(completed[1]), 'owned native removed wreck must be recognized')
local foreign = ISRemoveBurntVehicle:new(player, first)
assert(not world.wreckTargetGone(foreign), 'unowned native wreck must retain native stop behavior')
local originalStop = completed[1].stop
completed[1].stop = function() end
assert(not world.wreckTargetGone(completed[1]), 'modded native lifecycle must not gain queue-stop protection')
completed[1].stop = originalStop
reset({item('BlowTorch', 20), mask}); first = wreck()
ISVehicleMenu.onRemoveBurntVehicle(player, first); ISVehicleMenu.onRemoveBurntVehicle(player, first)
ending = tail(); drain()
assert(#completed == 1 and inventory.items[1].uses == 10 and ending.action.started, 'duplicate target must skip without double rewards')
reset({item('BlowTorch', 10), mask}); first, second = wreck(), wreck()
ISVehicleMenu.onRemoveBurntVehicle(player, first); ISVehicleMenu.onRemoveBurntVehicle(player, second)
ending = tail(); drain()
assert(#completed == 1 and first.removed and not second.removed and ending.action.started,
    'torch exhausted by preceding complete must skip the second wreck and preserve the tail')
for _, change in ipairs({
    function(target) target.removed = true end,
    function(target) target.square = nil end,
    function() inventory.items[1].uses = 9 end,
    function() inventory.items = {inventory.items[1]} end,
    function() inventory.items = {mask} end,
    function() square.x = 100 end,
}) do
    reset({item('BlowTorch', 10), mask}); first = wreck()
    ISVehicleMenu.onRemoveBurntVehicle(player, first); ending = tail(); change(first); drain()
    assert(#completed == 0 and ending.action.started and player.stops == 0, 'stale target/tools must skip only their command')
end
reset({item('TaggedTorch', 10, ItemTag.BLOW_TORCH), item('TaggedMask', nil, ItemTag.WELDING_MASK)})
first = wreck(); ISVehicleMenu.onRemoveBurntVehicle(player, first); drain()
assert(first.removed and #completed == 1, 'native tag-based equipment alternatives must remain supported')
enabled = false
reset({item('BlowTorch', 10), mask}); first = wreck(); ending = tail()
ISVehicleMenu.onRemoveBurntVehicle(player, first)
assert(player.stops == 1 and q.queue[#q.queue].Type == 'ISRemoveBurntVehicle', 'disabled setting must preserve immediate native callback and clear behavior')
drain(); assert(first.removed and #completed == 1 and not world.wreckTargetGone(completed[1]))
assert(nativeCallback ~= ISVehicleMenu.onRemoveBurntVehicle)
print('Wreck native callback, SP completion ordering, equipment, stale-target, ownership and opt-out checks passed.')
