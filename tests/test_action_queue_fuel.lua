if not NativeActionRoot then print('Fuel native-contract checks skipped.'); return end
require = function() end
local enabled = true
PZSurvivorToolkit = {Settings = {actionQueue = function() return enabled end}}
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseObject = {derive = derive}
local install
Events = {OnTick = {Add = function() end}, OnServerCommand = {Add = function() end},
    OnGameStart = {Add = function(callback) install = callback end}}
for _, name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState',
    'ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do
    _G[name] = {instance = function() return {} end}
end
table.wipe = function(t) for key in pairs(t) do t[key] = nil end end
instanceof = function(value, name) return value and value.class == name end
getText = function(key) return key end
isServer, isClient = function() return false end, function() return false end
Fluid, ItemTag = {Petrol = 'Petrol'}, {PETROL = 'PETROL', SIPHON_GAS = 'SIPHON_GAS'}
ZomboidGlobals = {EquippedOrWornEncumbranceMultiplier = 1}
local function native(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
native('shared/TimedActions/ISBaseTimedAction.lua')
native('client/TimedActions/ISTimedActionQueue.lua')
native('client/TimedActions/ISQueueActionsAction.lua')
ISInventoryPage = {}
native('client/TimedActions/ISInventoryTransferAction.lua')
native('shared/Vehicles/TimedActions/ISAddGasolineToVehicle.lua')
native('shared/Vehicles/TimedActions/ISTakeGasolineFromVehicle.lua')
native('client/Vehicles/ISUI/ISVehiclePartMenu.lua')
ISDisassembleMenu, ISMoveableCursor, ISBuildingObject = {disassemble = function() end}, {create = function() end}, {tryBuild = function() end}
ISMoveablesAction = {new = function() return {} end}
ISContextMenu, ISButton, ISInventoryPane, ISWorldObjectContextMenu = {}, {}, {}, {}
local function list(items)
    return {size = function() return #items end, get = function(_, index) return items[index + 1] end,
        isEmpty = function() return #items == 0 end}
end
local inventory = {items = {}}
function inventory:getAllEvalRecurse(predicate)
    local result = {}
    for _, item in ipairs(self.items) do if predicate(item) then result[#result + 1] = item end end
    return list(result)
end
function inventory:containsEvalRecurse(predicate) return not self:getAllEvalRecurse(predicate):isEmpty() end
function inventory:getFirstEvalRecurse(predicate) return self:getAllEvalRecurse(predicate):get(0) end
function inventory:getFirstTagRecurse(tag) return self:getFirstEvalRecurse(function(item) return item:hasTag(tag) end) end
function inventory:contains(item) for _, candidate in ipairs(self.items) do if candidate == item then return true end end; return false end
local square = {}
local vehicle = {square = square, getSquare = function(self) return self.square end,
    isEngineStarted = function(self) return self.engine or false end,
    transmitPartModData = function(self) self.transmits = (self.transmits or 0) + 1 end}
local part = {amount = 0, capacity = 100, getVehicle = function() return vehicle end,
    getId = function() return 'GasTank' end, getArea = function() return 'GasTank' end,
    getContainerContentAmount = function(self) return self.amount end,
    getContainerCapacity = function(self) return self.capacity end,
    setContainerContentAmount = function(self, amount) self.amount = amount end}
vehicle.getPartById = function(self, id) assert(id == 'GasTank'); return self.part end
vehicle.part = part
local player = {class = 'IsoPlayer', getPlayerNum = function() return 0 end,
    isDead = function() return false end, isAsleep = function() return false end,
    isLocalPlayer = function() return true end, isDraggingCorpse = function() return false end,
    isFarming = function() return false end, hasFullInventory = function(self) return self.full or false end,
    getInventory = function() return inventory end, getVehicle = function() return nil end,
    getPrimaryHandItem = function(self) return self.primary end,
    getFreeInventoryCapacity = function() return 100 end, stopOrTriggerSound = function() end}
getSpecificPlayer = function(num) assert(num == 0); return player end
VehicleUtils = {getItems = function()
    local hose = inventory:getFirstTagRecurse(ItemTag.SIPHON_GAS)
    return {}, {[ItemTag.SIPHON_GAS] = hose and {hose} or nil}
end}
ISVehicleMenu = {onExit = function() error('not seated') end}
ISLogSystem = {logAction = function() end}
player.setIsFarming = function() end
ISBaseTimedAction.begin = function(action)
    action.action = {isStarted = function() return true end,
        forceComplete = function(self) self.completed = true end,
        forceStop = function() error('deferred command must preserve unrelated queue') end}
end
ISPathFindAction = ISBaseTimedAction:derive('ISPathFindAction')
function ISPathFindAction:pathToVehicleArea(character, target, area)
    local action = ISBaseTimedAction.new(self, character); action.vehicle, action.area = target, area; return action
end
ISEquipWeaponAction = ISBaseTimedAction:derive('ISEquipWeaponAction')
function ISEquipWeaponAction:new(character, item, duration, primary)
    local action = ISBaseTimedAction.new(self, character); action.item, action.primary = item, primary; return action
end
ISInventoryPaneContextMenu = {equipWeapon = function(item, primary, _, num)
    ISTimedActionQueue.add(ISEquipWeaponAction:new(getSpecificPlayer(num), item, 50, primary))
end}
local function project(name) assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/' .. name .. '.lua'))() end
project('ActionQueueOperations'); project('ActionQueueWorld'); install()
local world = PZSurvivorToolkit.ActionQueueWorld
local q = ISTimedActionQueue.getTimedActionQueue(player)
local function can(id, amount, fullType, petrol)
    local fluid = {amount = amount, capacity = 10, petrol = petrol ~= false}
    function fluid:getAmount() return self.amount end
    function fluid:getCapacity() return self.capacity end
    function fluid:getFreeCapacity() return self.capacity - self.amount end
    function fluid:isEmpty() return self.amount == 0 end
    function fluid:contains(kind) return kind == Fluid.Petrol and self.petrol and self.amount > 0 end
    function fluid:adjustAmount(value) self.amount = value end
    function fluid:addFluid(kind, value) assert(kind == Fluid.Petrol); self.petrol, self.amount = true, self.amount + value end
    return {class = 'InventoryItem', fluid = fluid, getFluidContainer = function(self) return self.fluid end,
        getID = function() return id end, getFullType = function() return fullType or 'Base.PetrolCan' end,
        getContainer = function() return inventory end, hasTag = function(_, tag) return tag == ItemTag.PETROL end,
        setJobDelta = function() end, syncItemFields = function(self) self.synced = true end}
end
local hose = {class = 'InventoryItem', getID = function() return 99 end,
    getFluidContainer = function() return nil end, getFullType = function() return 'Base.Hose' end,
    getContainer = function() return inventory end, hasTag = function(_, tag) return tag == ItemTag.SIPHON_GAS end}
local function reset(amount, items)
    q.queue, q.current = {}, nil
    part.amount, part.capacity, vehicle.square, vehicle.part, vehicle.engine = amount, 100, square, part, false
    player.primary, player.secondary, player.full = nil, nil, false
    inventory.items = items
end
local function tail()
    local action = ISBaseTimedAction.new(ISBaseTimedAction, player); action.Type = 'UnrelatedTail'
    ISTimedActionQueue.add(action); return action
end
local completed = {}
local function step()
    local action = assert(q.current)
    if action.Type == 'ISQueueActionsAction' then
        assert(action.toolkitWorldOperation == 'fuel' and not world.isDeferredAction(action), 'fuel commands retain conservative queue protections')
        action:start(); assert(action.action.completed, 'empty expansion must also finish safely')
    elseif action.Type == 'ISAddGasolineToVehicle' or action.Type == 'ISTakeGasolineFromVehicle' then
        assert(action:complete()); completed[#completed + 1] = action
        assert(action.item.synced, 'native fuel completion must synchronize the item')
    elseif action.Type == 'ISEquipWeaponAction' then
        if action.primary then player.primary = action.item else player.secondary = action.item end
    end
    action:perform()
    return action
end
local function drain()
    local limit = 40
    while q.current do limit = limit - 1; assert(limit > 0, 'queue stalled'); step() end
end
local function fuelActions() completed = {} end
for _, take in ipairs({false, true}) do
    local a, b = can(1, take and 0 or 10), can(2, take and 0 or 10)
    reset(take and 50 or 0, {a, b, hose}); fuelActions()
    local callback = take and ISVehiclePartMenu.onTakeGasoline or ISVehiclePartMenu.onAddGasoline
    callback(player, part); callback(player, part)
    assert(#q.queue == 2 and q.queue[1].Type == 'ISQueueActionsAction', 'even the first click must select its can only at execution')
    local ending = tail(); drain()
    assert(#completed == 2 and completed[1].item == a and completed[2].item == b, 'two queued radial clicks must use successive eligible cans')
    assert(part.amount == (take and 30 or 20) and a.fluid.amount == (take and 10 or 0) and b.fluid.amount == a.fluid.amount,
        'native sequential complete must conserve the tank and both cans')
    assert(completed[2].tankStart == (take and 40 or 10), 'second constructor baseline must reflect the first completion')
    assert(take and player.primary == hose and player.secondary == b or not take and player.primary == b,
        'native hand slots must preserve the siphon hose and the selected can')
    assert(ending.action, 'unrelated tail must execute')
end
for _, take in ipairs({false, true}) do
    local a, b = can(1, take and 0 or 10), can(2, take and 0 or 10)
    reset(take and 50 or 0, {a, b, hose}); fuelActions()
    local callback = take and ISVehiclePartMenu.onTakeFuelNew or ISVehiclePartMenu.onAddFuelNew
    callback(nil, part, nil, a, 0); callback(nil, part, nil, a, 0); drain()
    assert(#completed == 2 and completed[1].item == a and completed[2].item == b,
        'repeated context AddOne/FillOne must fall back to an eligible can of the selected type')
    local stale, replacement = can(3, take and 0 or 10), can(3, take and 0 or 10)
    reset(take and 50 or 0, {stale, hose}); fuelActions()
    callback(nil, part, nil, stale, 0); inventory.items = {replacement, hose}; drain()
    assert(#completed == 1 and completed[1].item == replacement, 'MP replacement retaining item ID must resolve the live object')
    a, b = can(1, take and 0 or 10), can(2, take and 0 or 10)
    reset(take and 50 or 0, {a, b, hose}); fuelActions()
    local selected = {a, b}; callback(nil, part, selected, nil, 0)
    assert(#selected == 2 and selected[1] == a and selected[2] == b, 'FillAll must not mutate the caller list at click')
    selected[1], selected[2] = b, a -- Later menu reuse cannot retarget the saved IDs.
    drain()
    assert(#completed == 2 and completed[1].item == a and completed[2].item == b and selected[1] == b and selected[2] == a,
        'FillAll keeps the original order and native continuations mutate only the private remaining list')
    reset(take and 50 or 0, {a, b, hose}); fuelActions()
    a.fluid.amount, b.fluid.amount = take and 0 or 10, take and 0 or 10
    callback(nil, part, {a, b}, nil, 0); inventory.items = {b, hose}; drain()
    assert(#completed == 1 and completed[1].item == b, 'a filtered singleton must avoid native #list > 1 selection hole')
    a, b = can(1, take and 0 or 10), can(2, take and 0 or 10)
    reset(take and 50 or 0, {a, b, hose}); fuelActions()
    selected = {a, b}
    callback(nil, part, selected, nil, 0); callback(nil, part, selected, nil, 0)
    local ending = tail(); drain()
    assert(#completed == 2 and part.amount == (take and 30 or 20) and ending.action,
        'repeated All must skip exhausted containers without duplicate transfers or dropping the tail')
    a.fluid.amount, b.fluid.amount = take and 0 or 10, take and 0 or 10
    reset(take and 50 or 0, {a, b, hose}); fuelActions()
    callback(nil, part, nil, a, 0); callback(nil, part, nil, a, 0)
    q:resetQueue()
    callback(nil, part, nil, a, 0); drain()
    assert(#completed == 1 and completed[1].item == a, 'clearing queued commands must leave their cans available for retry')
end
local skipCases = {
    {'missing can', false, function() inventory.items = {hose} end},
    {'missing hose', true, function() inventory.items = {inventory.items[1]} end},
    {'removed vehicle', false, function() vehicle.square = nil end},
    {'replaced part', false, function() vehicle.part = {} end},
    {'started engine', false, function() vehicle.engine = true end},
    {'full tank', false, function() part.amount = part.capacity end},
    {'empty tank', true, function() part.amount = 0 end},
    {'full inventory', true, function() player.full = true end},
}
for _, case in ipairs(skipCases) do
    local take, item = case[2], can(1, case[2] and 0 or 10)
    reset(take and 50 or 0, {item, hose}); fuelActions()
    local callback = take and ISVehiclePartMenu.onTakeGasoline or ISVehiclePartMenu.onAddGasoline
    callback(player, part); local ending = tail(); case[3](); step()
    assert(q.current == ending and #q.queue == 1 and #completed == 0, case[1] .. ' must skip only its command')
    drain()
end
-- Context fallback must preserve the selected type instead of borrowing another kind of bottle.
local preferred, wrong = can(1, 10), can(2, 10, 'Base.Bottle')
reset(0, {preferred, wrong, hose}); fuelActions()
ISVehiclePartMenu.onAddFuelNew(nil, part, nil, preferred, 0); local ending = tail()
inventory.items = {wrong, hose}; step()
assert(q.current == ending and #completed == 0, 'missing selected type must leave unrelated work intact')
-- FillAll candidates are click-time IDs: it cannot consume a new can picked up later.
reset(0, {preferred, hose}); fuelActions()
ISVehiclePartMenu.onAddFuelNew(nil, part, {preferred}, nil, 0); ending = tail()
inventory.items = {wrong, hose}; step(); assert(q.current == ending)
-- Empty non-petrol containers remain supported by native siphoning.
local bottle = can(7, 0, 'Base.Bottle', false)
reset(20, {bottle, hose}); fuelActions()
ISVehiclePartMenu.onTakeFuelNew(nil, part, nil, bottle, 0); drain()
assert(#completed == 1 and bottle.fluid.amount == 10 and part.amount == 10)
-- With the setting disabled, native callbacks expand immediately as before.
enabled = false
for _, take in ipairs({false, true}) do
    local item = can(1, take and 0 or 10)
    reset(take and 50 or 0, {item, hose}); fuelActions()
    local callback = take and ISVehiclePartMenu.onTakeGasoline or ISVehiclePartMenu.onAddGasoline
    callback(player, part)
    assert(q.queue[1].Type == 'ISPathFindAction' and q.queue[#q.queue].item == item, 'native radial opt-out must stay immediate')
    drain()
    item.fluid.amount = take and 0 or 10
    reset(take and 50 or 0, {item, hose}); fuelActions()
    callback = take and ISVehiclePartMenu.onTakeFuelNew or ISVehiclePartMenu.onAddFuelNew
    callback(nil, part, nil, item, 0)
    assert(q.queue[1].Type == 'ISPathFindAction' and q.queue[#q.queue].item == item, 'native context opt-out must stay immediate')
    drain()
end
print('Fuel native-contract checks passed: deferred native selectors/transactions, context fallback, copied batches, live IDs, safe skips and opt-out.')
