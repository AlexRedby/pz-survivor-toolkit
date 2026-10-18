-- Native action fields and queue boundaries; Java start/stop is outside this regression.
if not NativeActionRoot then
    print('Action queue world-target checks skipped (pass --native-action-root media/lua).')
    return
end
require = function() end
getText = function(key) return key end
PZSurvivorToolkit = {Settings = {actionQueue = function() return true end}}
local function derive(self, name)
    local t = {Type = name, derive = derive}
    t.__index = t
    return setmetatable(t, {__index = self})
end
ISBaseObject = {derive = derive}
Events = {OnTick = {Add = function() end}}
Events.OnServerCommand = {Add = function() end}
for _, name in ipairs({'ClimbThroughWindowState', 'ClimbOverFenceState', 'ClimbOverWallState',
    'ClimbSheetRopeState', 'ClimbDownSheetRopeState', 'CloseWindowState', 'OpenWindowState'}) do
    _G[name] = {instance = function() return {} end}
end
instanceof = function(value, name) return type(value) == 'table' and value.class == name end
local function load(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
load('shared/TimedActions/ISBaseTimedAction.lua')
load('client/TimedActions/ISTimedActionQueue.lua')
load('client/TimedActions/ISQueueActionsAction.lua')
ISInventoryPage = {}
load('client/TimedActions/ISInventoryTransferAction.lua')
load('shared/TimedActions/ISActivateGenerator.lua')
load('shared/TimedActions/ISFixGenerator.lua')
load('shared/TimedActions/ISRemoveCarBatteryFromChargerAction.lua')
load('shared/TimedActions/ISTakeCarBatteryChargerAction.lua')
load('shared/TimedActions/ISToggleStoveAction.lua')
load('shared/Moveables/ISMoveablesAction.lua')
ISContextMenu, ISButton, ISInventoryPaneContextMenu, ISInventoryPane = {}, {}, {}, {}
Perks = {Electricity = 'Electricity'}
local player = {class = 'IsoPlayer', getPlayerNum = function() return 0 end,
    isAsleep = function() return false end, isDead = function() return false end,
    isLocalPlayer = function() return true end, isDraggingCorpse = function() return false end,
    isFarming = function() return false end, isTimedActionInstant = function() return false end,
    getPerkLevel = function() return 0 end,
    getInventory = function() return {containsTypeRecurse = function() return true end} end}
getSpecificPlayer = function() return player end
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueOperations.lua'))()
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueDefinitions.lua'))()
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLabels.lua'))()
if not PZSurvivorToolkit.ActionQueueDefinitions then assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueDefinitions.lua'))() end
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueuePolicy.lua'))()
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua'))()
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueAcknowledgements.lua'))()
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueue.lua'))()
local api, operations = PZSurvivorToolkit.ActionQueue, PZSurvivorToolkit.ActionQueueOperations
local function target()
    return {class = 'IsoObject', activated = false, getObjectIndex = function() return 0 end,
        getCondition = function() return 75 end, getFuel = function() return 10 end,
        isConnected = function() return true end, isActivated = function(self) return self.activated end,
        setActivated = function(self, value) self.activated = value end, sync = function() end}
end
local function pending(kind)
    return ISBaseTimedAction.new(kind or ISBaseTimedAction, player)
end
local function queue(...)
    local q = ISTimedActionQueue:new(player)
    local active = pending()
    active.begin = function(self) self.action = {} end
    ISTimedActionQueue.add(active)
    for _, action in ipairs({...}) do ISTimedActionQueue.add(action) end
    return q
end
local generator = target()
local repair = ISFixGenerator:new(player, generator)
local activate = ISActivateGenerator:new(player, generator, true)
assert(repair:isValid())
activate:complete()
assert(not repair:isValid(), 'native activation invalidates a following repair')
generator.activated = false
local q = queue(repair, activate)
assert(api.moveReason(q, activate, repair) == 'move_dependent')
assert(not api.move(q, activate, repair) and q.queue[2] == repair and q.queue[3] == activate)
assert(not api.move(q, repair, activate, true), 'both crossing directions preserve target order')
assert(api.cancelReason(q, activate) == 'dependent', 'world-target guard must not expand cancellation')
local charger = target()
local remove = ISRemoveCarBatteryFromChargerAction:new(player, charger)
local take = ISTakeCarBatteryChargerAction:new(player, charger)
q = queue(remove, take)
assert(api.moveReason(q, take, remove) == 'move_dependent')
local toggle = ISToggleStoveAction:new(player, charger)
local scrap = pending(ISMoveablesAction)
scrap.mode, scrap.moveProps = 'scrap', {object = charger}
q = queue(toggle, scrap)
assert(api.moveReason(q, scrap, toggle) == 'move_dependent', 'moveProps and object aliases identify the same target')
assert(api.moveReason(q, toggle, scrap, true) == 'move_dependent')
-- A crossing can touch a preparation step inside an entire operation.
local prep, unrelated = pending(), pending()
q = queue(remove)
take = ISTakeCarBatteryChargerAction:new(player, charger)
operations.run(function() ISTimedActionQueue.add(prep); ISTimedActionQueue.add(take) end)
assert(api.moveReason(q, prep, remove) == 'move_dependent')
ISTimedActionQueue.add(unrelated)
assert(not api.move(q, take, unrelated, true), 'unrecognized preparation and crossed actions remain barriers')
local other = ISActivateGenerator:new(player, target(), true)
q = queue(repair, other)
assert(not api.move(q, other, repair), 'generator power regions and recursive repairs remain barriers')
local otherCharger = ISToggleStoveAction:new(player, target())
q = queue(toggle, otherCharger)
assert(api.move(q, otherCharger, toggle), 'independent validated device targets remain reorderable')
local item = {class = 'InventoryItem', getID = function() return 1001 end}
local transfer, use = pending(ISInventoryTransferAction), pending(ISInventoryTransferAction)
transfer.item, use.item = item, item
q = queue(transfer, use)
assert(api.moveReason(q, use, transfer) == 'move_shared_item', 'existing inventory protections remain intact')
local a, b = pending(), pending()
a.object, b.object = 'label', 'label'
q = queue(a, b)
assert(not api.move(q, b, a), 'arbitrary base actions cannot inherit permission from unrecognized fields')
print('Action queue world-target ordering: native generator/charger, aliases, whole operations and independent targets passed.')
