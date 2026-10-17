if not NativeActionRoot then
    print('Repair reorder native-contract checks skipped (pass --native-action-root media/lua).')
    return
end
require = function() end
getText = function(key) return key end
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseObject = {derive = derive}
Events = {OnTick = {Add = function() end}, OnGameStart = {Add = function(fn) fn() end}}
for _, name in ipairs({'ClimbThroughWindowState', 'ClimbOverFenceState', 'ClimbOverWallState', 'ClimbSheetRopeState',
    'ClimbDownSheetRopeState', 'CloseWindowState', 'OpenWindowState'}) do
    _G[name] = {instance = function() return {} end}
end
instanceof = function(value, name)
    return type(value) == 'table' and (value.class == name or name == 'InventoryItem' and value.class == 'InventoryContainer')
end
local function native(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
native('shared/TimedActions/ISBaseTimedAction.lua')
native('client/TimedActions/ISTimedActionQueue.lua')
native('client/TimedActions/ISQueueActionsAction.lua')
native('shared/TimedActions/ISReadABook.lua')
native('shared/TimedActions/ISFixAction.lua')
native('shared/TimedActions/ISFixVehiclePartAction.lua')
native('shared/TimedActions/ISCraftAction.lua')
native('shared/Entity/TimedActions/ISHandcraftAction.lua')
native('shared/RadioCom/ISRadioAction.lua')
ISInventoryPage, ISContextMenu, ISButton, ISInventoryPaneContextMenu = {}, {}, {}, {}
native('client/TimedActions/ISInventoryTransferAction.lua')
native('shared/TimedActions/ISEquipWeaponAction.lua')
local enabled = true
PZSurvivorToolkit = {Settings = {actionQueue = function() return enabled end}, ActionQueueLabels = {},
    BulkActions = {isGuardedTransfer = function() return false end}}
local function toolkit(name)
    return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/' .. name .. '.lua'))()
end
local operations = toolkit('ActionQueueOperations')
local craft = toolkit('ActionQueueCraft')
if not PZSurvivorToolkit.ActionQueueDefinitions then assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueDefinitions.lua'))() end
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueuePolicy.lua'))()
Events.OnServerCommand = {Add = function() end}
toolkit('ActionQueueLifecycle'); toolkit('ActionQueueAcknowledgements')
local queueAPI = toolkit('ActionQueue')
local player = {getPlayerNum = function() return 0 end, isDead = function() return false end,
    isAsleep = function() return false end, isTimedActionInstant = function() return false end}
player.inventory = {}
player.getInventory = function() return player.inventory end
getSpecificPlayer = function() return player end
local function list(...)
    local values = {...}
    return {class = 'List', size = function() return #values end, get = function(_, index) return values[index + 1] end}
end
local nextID = 0
local function item(fullType, class)
    nextID = nextID + 1
    return {class = class or 'InventoryItem', id = nextID, getID = function(self) return self.id end,
        getName = function() return fullType end, getFullType = function() return fullType end, getContainer = function() return player.inventory end}
end
local target, firstDonor, anotherDonor, global = item('Base.Shotgun'), item('Base.Shotgun'), item('Base.Shotgun'), item('Base.Glue')
local fixer = {getFixerName = function() return 'Base.Shotgun' end}
local globalFixer = {getFixerName = function() return 'Base.Glue' end}
local fixing = {getFixers = function() return list(fixer) end, getGlobalItem = function() return globalFixer end,
    getRequiredItems = function() return list(firstDonor, global) end}
FixingManager = {getFixes = function() return list(fixing) end}
local function repair()
    local action = ISFixAction:new(player, target, 0, 0)
    action.toolkitQueueOperation = {}
    return action
end
local function action(class, value)
    local a = ISBaseTimedAction.new(class, player)
    a.item, a.toolkitQueueOperation = value, {}
    return a
end
local function queue(...)
    local values = {...}
    local q = setmetatable({character = player, queue = values, current = values[1]}, ISTimedActionQueue)
    ISTimedActionQueue.queues[player] = q
    return q
end
local head = action(ISReadABook, item('Base.BookCarpentry1'))
local reading = action(ISReadABook, item('Base.BookMechanic1'))
local fix = repair()
local inputs = assert(craft.repairInputs(fix))
assert(inputs['Base.Shotgun'] and inputs['Base.Glue'])
assert(not craft.collectItems(fix, {}), 'cancellation must retain the existing unknown-input protection')
-- A caught assertion still logs in Kahlua on every queue-panel redraw.
local function withoutAssertions(callback)
    local originalAssert, calls = assert, 0
    assert = function(...) calls = calls + 1; return originalAssert(...) end
    local ok, result = pcall(callback)
    assert = originalAssert
    assert(ok, result)
    assert(calls == 0, 'repair inspection must not invoke assert (Kahlua logs caught assertions): ' .. calls)
    return result
end
local policy = PZSurvivorToolkit.ActionQueuePolicy
local fixerName, globalName = fixer.getFixerName, globalFixer.getFixerName
for _, invalid in ipairs({'fixing-index', 'fixer-index', 'fixer-name', 'global-name'}) do
    local rejected = repair()
    if invalid == 'fixing-index' then rejected.fixing = {getRequiredItems=function() return list() end}
    elseif invalid == 'fixer-index' then rejected.fixer = {}
    elseif invalid == 'fixer-name' then fixer.getFixerName = function() return '' end
    else globalFixer.getFixerName = function() return 99 end end
    local redrawQueue = queue(head, reading, rejected)
    for redraw = 1, 3 do
        local checked = withoutAssertions(function()
            return {inputs=craft.repairInputs(rejected), contract=policy.inspect(rejected),
                cancel=policy.evaluateCancel(redrawQueue, reading, true),
                move=policy.evaluateMove(redrawQueue, rejected, reading)}
        end)
        assert(not checked.inputs and not checked.contract.dynamicInputs and not checked.contract.knownInputs,
            invalid .. ' keeps stale or malformed native repair selections protected')
        assert(not checked.cancel.allowed and checked.cancel.reason == 'operation_dependent')
        assert(not checked.move.allowed and checked.move.reason == 'move_craft_inputs')
    end
    fixer.getFixerName, globalFixer.getFixerName = fixerName, globalName
end
inputs = withoutAssertions(function() return craft.repairInputs(fix) end)
assert(inputs['Base.Shotgun'] and inputs['Base.Glue'], 'valid repair donors still pass without assertions')
local q = queue(head, reading, fix)
assert(not queueAPI.moveReason(q, fix, reading) and queueAPI.move(q, fix, reading))
assert(q.queue[2] == fix and q.queue[3] == reading and fix.fixer == fixer and fix.fixing == fixing and fix.item == target,
    'pending repair moves without pinning/replacing native donors or repair data')
assert(queueAPI.move(q, reading, fix) and q.queue[2] == reading and q.queue[3] == fix,
    'crossing the pending repair works in either direction')
head.action = {isStarted = function() return true end, finished = function() return false end,
    isForceComplete = function() return false end, forceStop = function(self) self.stopped = true end}
q = queue(head, fix)
assert(queueAPI.move(q, fix, head) and head.action.stopped and q.toolkitCancel == head and q.toolkitResume == fix,
    'independent pending repair can preempt an active native book through the ordinary stop/resume path')
head.action = nil
local tv = action(ISRadioAction)
tv.mode = 'ToggleOnOff'
q = queue(head, tv, fix)
assert(queueAPI.move(q, fix, tv))
tv.mode = 'SetChannel'; q = queue(head, fix, tv)
assert(queueAPI.move(q, tv, fix))
tv.mode = 'RemoveHeadphones'; q = queue(head, tv, fix)
assert(queueAPI.moveReason(q, fix, tv) == 'move_dependent', 'inventory-producing radio modes stay protected')
tv.mode = 'ToggleOnOff'; tv.performToggleOnOff = function() end
assert(queueAPI.moveReason(q, fix, tv) == 'move_dependent', 'custom mode callbacks cannot inherit native permission')
tv.performToggleOnOff = nil
for _, crossed in ipairs({action(ISInventoryTransferAction, anotherDonor), action(ISInventoryTransferAction, item('Base.Glue')),
    action(ISInventoryTransferAction, item('Base.Bag_Schoolbag', 'InventoryContainer')),
    action(ISEquipWeaponAction, anotherDonor), action(ISEquipWeaponAction, item('Base.BookMechanic1')), repair(), action(ISBaseTimedAction:derive('UnknownModAction'))}) do
    q = queue(head, crossed, fix)
    assert(queueAPI.moveReason(q, fix, crossed), 'changed donors, bags, repair outputs and unknown actions stay protected')
    assert(queueAPI.moveReason(q, crossed, fix, true), 'dependency checks must be symmetric')
end
local transfer = action(ISInventoryTransferAction, item('Base.BookMechanic1'))
q = queue(head, transfer, fix)
assert(queueAPI.move(q, fix, transfer), 'unrelated native transfers can cross a repair')
transfer.queueList = {{items = {transfer.item, anotherDonor}}}
q = queue(head, transfer, fix)
assert(queueAPI.moveReason(q, fix, transfer), 'merged transfer batches must include every donor candidate')
transfer.queueList = nil
transfer.onCompleteFunc = function() end
assert(queueAPI.moveReason(q, fix, transfer), 'unknown transfer completion is not independent')
transfer.onCompleteFunc = nil
local readWithPickup = action(ISReadABook, transfer.item)
transfer.toolkitQueueOperation = readWithPickup.toolkitQueueOperation
q = queue(head, transfer, readWithPickup, fix)
assert(queueAPI.move(q, fix, readWithPickup) and q.queue[2] == fix and q.queue[3] == transfer and q.queue[4] == readWithPickup,
    'the complete reading operation, including pickup, moves together')
-- A rehydrated MP target object still conflicts by ID.
local replacement = item('Base.Shotgun'); replacement.id = target.id
transfer.item = replacement
q = queue(head, transfer, fix)
assert(queueAPI.moveReason(q, fix, transfer), 'native object replacement must not erase item dependencies')
-- Unknown/malformed repair data and substituted lifecycle stay closed.
local oldFixing = fix.fixing
fix.fixing = {getGlobalItem = function() error('missing native data') end}
assert(not craft.repairInputs(fix) and queueAPI.moveReason(q, fix, reading) == 'unavailable')
q = queue(head, reading, fix)
assert(queueAPI.moveReason(q, fix, reading) == 'move_craft_inputs')
fix.fixing = oldFixing
fix.fixer = {getFixerName = function() return 'Base.DuctTape' end}
assert(not craft.repairInputs(fix), 'cached donor fields must agree with the indices sent to the native server')
fix.fixer = fixer
fix.complete = function() end
assert(not craft.repairInputs(fix) and queueAPI.moveReason(q, fix, reading) == 'move_dependent')
fix.complete = nil
enabled = false
assert(queueAPI.moveReason(q, fix, reading) == 'unavailable')
print('Repair native reorder: independent book/TV/preparation groups, dynamic/global donor types, merged batches, stable IDs and unknown outputs protected.')

enabled = true
local vehiclePart={getInventoryItem=function() return target end}
local vehicleRepair=ISFixVehiclePartAction:new(player,vehiclePart,0,0)
vehicleRepair.toolkitQueueOperation={}
assert(craft.supports(vehicleRepair) and craft.repairInputs(vehicleRepair)['Base.Shotgun'])
q=queue(head,reading,vehicleRepair)
assert(queueAPI.move(q,vehicleRepair,reading),'native vehicle repair can cross independent reading')
transfer.item=anotherDonor
q=queue(head,transfer,vehicleRepair)
assert(queueAPI.moveReason(q,vehicleRepair,transfer)=='move_craft_inputs')
assert(queueAPI.moveReason(q,transfer,vehicleRepair,true)=='move_craft_inputs')
assert(queueAPI.cancelOperationReason(q,vehicleRepair),'dynamic vehicle donor selection stays protected on cancel')
