if not NativeActionRoot then print('Generator native contracts SKIP.'); return end
local f = assert(loadfile(ProjectRoot .. '/tests/support/action_queue_native.lua'))()
local craftContainers
require = function(name)
    if name == 'PZSurvivorToolkit/InventoryClasses' then return dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/' .. name .. '.lua') end
    if name == 'PZSurvivorToolkit/SourceProof' then return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))() end
    if name == 'PZSurvivorToolkit/QuartermasterCraftContainers' then
        craftContainers = craftContainers or f.project('QuartermasterCraftContainers')
        return craftContainers
    end
    if name == 'PZSurvivorToolkit/ActionQueueGeneratorOverlay' then
        return PZSurvivorToolkit.ActionQueueGeneratorOverlay or f.project('ActionQueueGeneratorOverlay')
    end
end
local function readText(path, raw)
    if raw and NativeReadRawText then return NativeReadRawText(path) end
    if NativeReadText then return NativeReadText(path) end
    local reader = assert(io.open(path)); local source = reader:read('*a'); reader:close(); return source
end
local function native(path)
    assert(loadstring(readText(NativeActionRoot .. '/' .. path):gsub('(%d+%.%d+)f', '%1'), '@' .. NativeActionRoot .. '/' .. path))()
end
getFilenameOfClosure = NativeFilenameOfClosure or function(callback) return debug.getinfo(callback, 'S').source:gsub('^@', '') end
getGameFilesInput = function(path)
    local text = readText(NativeActionRoot .. '/' .. path:gsub('^media/lua/', ''), true):gsub('\r', '')
    local index = 1
    return {readLine = function()
        if index > #text then return end
        local ending = text:find('\n', index, true)
        local line = text:sub(index, ending and ending - 1 or #text); index = ending and ending + 1 or #text + 1; return line
    end, close = function() end}
end
Events.OnPressWalkTo = {Add = function() end}
-- ActionQueueCompat's manifest installer reads the owned Quartermaster namespace even when
-- the native-source fixture does not exercise manifest transfers.
LootSorter = LootSorter or {}
local mainMenuCleanup
Events.OnMainMenuEnter = {Add = function(callback) mainMenuCleanup=callback end}
native('shared/luautils.lua')
native('client/ISUI/ISWorldObjectContextMenu.lua')
local source = readText(NativeActionRoot .. '/client/ISUI/ISInventoryPaneContextMenu.lua')
local first = assert(source:find('function ISInventoryPaneContextMenu.transferIfNeeded', 1, true))
local last = assert(source:find('ISInventoryPaneContextMenu.onEjectMagazine', first, true))
assert(loadstring(source:sub(first, last - 1), '@media/lua/client/ISUI/ISInventoryPaneContextMenu.lua'))()
native('client/TimedActions/ISInventoryTransferAction.lua')
native('shared/TimedActions/ISInventoryTransferUtil.lua')
for _, name in ipairs({'ISPlugGenerator', 'ISActivateGenerator', 'ISFixGenerator', 'ISAddFuel', 'ISTakeGenerator',
    'ISEquipWeaponAction', 'ISUnequipAction'}) do native('shared/TimedActions/' .. name .. '.lua') end
native('client/TimedActions/ISGeneratorInfoAction.lua')
local client, server, enabled = false, false, true
PZSurvivorToolkit.Settings.actionQueue = function() return enabled end
isClient, isServer = function() return client end, function() return server end
IsoFlagType = {solidtrans = 'solidtrans', cutW = 'cutW', cutN = 'cutN'}
Fluid, Perks = {Petrol = 'Petrol'}, {Electricity = 'Electricity'}
local p, inv = f.player, f.player.inventory
p.class = 'IsoPlayer'
p.isLocalPlayer = function() return true end
p.isFarming, p.isDraggingCorpse = function() return false end, function() return false end
p.setIsFarming = function() end
p.StopAllActionQueue = function() end
inv.items = {}
local function list(values) return {size = function() return #values end, get = function(_, i) return values[i + 1] end} end
function inv:getFirstEvalRecurse(predicate) for _, item in ipairs(self.items) do if predicate(item) then return item end end end
function inv:getFirstTypeRecurse(kind) return self:getFirstEvalRecurse(function(item) return item:getFullType() == 'Base.' .. kind end) end
function inv:containsTypeRecurse(kind) return self:getFirstTypeRecurse(kind) ~= nil end
function inv:Remove(item) for i, value in ipairs(self.items) do if item == value then table.remove(self.items, i); return end end end
function inv:AddItem(item) self.items[#self.items + 1] = item end
function inv:setDrawDirty() end
function inv:getType() return 'inventory' end
p.getPerkLevel = function() return 0 end
p.removeFromHands = function() end
p.getVehicle = function() return nil end
p.getPrimaryHandItem = function(self) return self.primary end
p.getSecondaryHandItem = function(self) return self.secondary end
p.setPrimaryHandItem = function(self, item) self.primary = item end
p.setSecondaryHandItem = function(self, item) self.secondary = item end
local stoppedSounds, removedScraps, repairXp = 0, 0, 0
p.stopOrTriggerSound = function() stoppedSounds = stoppedSounds + 1 end
getPlayerHotbar = function() return nil end
local function square(x, y, z)
    return {getX = function() return x or 0 end, getY = function() return y or 0 end, getZ = function() return z or 0 end,
        getObjects = function() return list({}) end, getBuilding = function(self) return self.building end,
        has = function() return false end, canReachTo = function() return true end}
end
p.square = square(); p.getSquare = function(self) return self.square end
p.getCurrentSquare = p.getSquare
p.getX, p.getY = function() return 0.5 end, function() return 0.5 end
AdjacentFreeTileFinder = {Find = function(target) return target end}
native('client/TimedActions/WalkToTimedAction.lua')
IsoGenerator = {isPoweringSquare = function(x, y, z, tx, ty, tz) return (x - tx)^2 + (y - ty)^2 <= 400 and math.abs(z - tz) <= 3 end}
getSandboxOptions = function() return {getOptionByName = function(_, name)
    return {getValue = function() return name == 'GeneratorTileRange' and 20 or 3 end}
end} end
local originalInstanceof = instanceof
instanceof = function(value, name)
    return originalInstanceof(value, name) or name == 'InventoryItem' and type(value) == 'table' and value.class == 'InventoryContainer'
        or name == 'IsoObject' and type(value) == 'table' and value.class == 'IsoGenerator'
end
sendRemoveItemFromContainer = function() removedScraps = removedScraps + 1 end
sendAddItemToContainer, sendEquip = function() end, function() end
addXp = function(_, _, xp) assert(xp == 5); repairXp = repairXp + xp end
forceDropHeavyItems = function() end
instanceItem = function(kind)
    local item = f.item(kind); item.setCondition = function(self, value) self.condition = value end
    item.getModData = function(self) self.data = self.data or {}; return self.data end
    return item
end
ZombRand = function() return 1 end
ISLogSystem = {logAction = function() end}
ISBaseTimedAction.begin = function(action)
    action.action = {isStarted = function() return true end, finished = function() return false end,
        isForceComplete = function() return false end, forceComplete = function(self) self.completed = true end,
        forceStop = function() end, getJobDelta = function() return 0 end}
end
f.project('ActionQueueOperations'); f.project('ActionQueueDefinitions')
local policy = f.project('ActionQueuePolicy')
local originalProject=f.project
f.project=function(name)
    if name~='ActionQueueGenerators' then return originalProject(name) end
    local source=readText(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/'..name..'.lua')
    return assert(loadstring((source:gsub('\nreturn Generators','\nGenerators.fixtureRegistries = {records, continued, pendingPerform}\nreturn Generators'))))()
end
local adapter = f.project('ActionQueueGenerators'); adapter.install(); policy.installContracts()
local function generator(x, y, z)
    return {class = 'IsoGenerator', square = square(x, y, z), activated = false, connected = false, fuel = 20, condition = 92,
        getSquare = function(self) return self.square end, getObjectIndex = function(self) return self.removed and -1 or 0 end,
        isActivated = function(self) return self.activated end, isConnected = function(self) return self.connected end,
        getFuel = function(self) return self.fuel end, getMaxFuel = function() return 100 end,
        getFuelPercentage = function(self) return self.fuel end, getCondition = function(self) return self.condition end,
        setFuel = function(self, value) self.fuel = value end, setCondition = function(self, value) self.condition = value end,
        setActivated = function(self, value) self.activated = value end, setConnected = function(self, value) self.connected = value end,
        getGeneratorItemType = function() return 'Base.Generator' end, sync = function(self) self.synced = true end,
        remove = function(self) self.removed = true end}
end
local function fuel(id, amount)
    local item = f.item('Base.PetrolCan'); item.id = id
    item.fluid = {amount = amount, getAmount = function(self) return self.amount end,
        contains = function(self, kind) return kind == Fluid.Petrol and self.amount > 0 end,
        adjustAmount = function(self, value) self.amount = value end}
    item.getName = function() return 'Fuel can' end
    item.isRequiresEquippedBothHands = function() return false end
    item.getFluidContainer = function(self) return self.fluid end
    item.syncItemFields = function(self) self.synced = true end
    item.setJobDelta = function() end
    return item
end
local function head() return f.action(ISReadABook, {item = f.item('Base.BookCarpentry1')}) end
local function queued(method, object, mode)
    local q = f.queue(head())
    if method == 'onActivateGenerator' then ISWorldObjectContextMenu[method](nil, mode, object, 0)
    else ISWorldObjectContextMenu[method](nil, object, 0, mode) end
    return q, assert(q.queue[2])
end
local g, other = generator(), generator(100, 100)
do
    local function count(registry) local n=0; for _ in pairs(registry) do n=n+1 end; return n end
    local records, continued, pendingPerform=unpack(adapter.fixtureRegistries)
    for i=1,500 do
        local current, command=queued('onPlugGenerator',g,true)
        adapter.prune(); assert(count(records)==1 and records[command], 'old generator commands must be released during a busy queue')
    end
    for _,state in ipairs({'cancel','dead','replacement','world'}) do
        local current,command=queued('onPlugGenerator',g,true)
        if state=='cancel' then PZSurvivorToolkit.ActionQueueOperations.invalidate(command.toolkitQueueOperation); current.queue={}
        elseif state=='dead' then p.isDead=function() return true end
        elseif state=='replacement' then f.queue(head())
        else ISTimedActionQueue.queues={} end
        adapter.prune(); assert(count(records)==0 and count(continued)==0 and count(pendingPerform)==0,state..' must release generator registries')
        p.isDead=function() return false end
    end
    queued('onPlugGenerator',g,true); mainMenuCleanup()
    assert(count(records)==0 and count(continued)==0 and count(pendingPerform)==0, 'main menu must release generator world references immediately')
end
for _, method in ipairs({'onInfoGenerator', 'onPlugGenerator', 'onActivateGenerator', 'onFixGenerator', 'onTakeGenerator'}) do
    local q, action = queued(method, g, true)
    assert(policy.inspect(action), method .. ' native command must be trusted')
    assert(not policy.cancelOperationReason(q, action), method .. ' independent waiting command can cancel')
end
local badQueue, malformed = queued('onPlugGenerator', g, 'yes')
assert(not policy.inspect(malformed), 'invalid native mode cannot receive a command contract')
local q, action = queued('onPlugGenerator', g, true)
ISWorldObjectContextMenu.onActivateGenerator(nil, true, g, 0)
local activation = q.queue[3]
assert(policy.moveReason(q, activation, action) == 'move_dependent')
assert(policy.moveReason(q, action, activation, true) == 'move_dependent')
assert(policy.cancelOperationReason(q, action) == 'operation_dependent')
ISWorldObjectContextMenu.onPlugGenerator(nil, other, 0, true)
local independent = q.queue[4]
q = f.queue(head(), action, independent)
assert(not policy.moveReason(q, independent, action))
assert(not policy.moveReason(q, action, independent, true))
assert(not policy.cancelOperationReason(q, independent))
-- Engine geometry protects object and transfer-container resources in both directions.
local appliance = {class = 'IsoObject', getSquare = function() return square(20, 0, 3) end}
local outside = {class = 'IsoObject', getSquare = function() return square(20, 1, 3) end}
assert(adapter.sharesTarget(action, {object = appliance}) and adapter.sharesTarget({object = appliance}, action))
assert(not adapter.sharesTarget(action, {object = outside}))
assert(not adapter.sharesTarget(action, {object = {class = 'IsoObject', getSquare = function() return square(0, 0, 4) end}}))
local container = {class = 'ItemContainer', getParent = function() return appliance end}
assert(adapter.sharesTarget(action, {srcContainer = container}))
assert(adapter.sharesTarget(action, {toolkitWorldX = 20, toolkitWorldY = 0, toolkitWorldZ = 3, toolkitWorldWidth = 3}))
assert(not adapter.sharesTarget(action, {toolkitWorldX = 21, toolkitWorldY = 0, toolkitWorldZ = 3}))
for _, spec in ipairs({{40, 0, 6, true}, {41, 0, 6, false}, {40, 1, 0, false}, {0, 0, 7, false}, {0, 0, -6, true}}) do
    local neighbour = generator(spec[1], spec[2], spec[3])
    local _, command = queued('onPlugGenerator', neighbour, true)
    local current = f.queue(head(), action, command)
    assert((policy.moveReason(current, command, action) == 'move_dependent') == spec[4], 'generator power overlap must preserve consumers')
    assert((policy.moveReason(current, action, command, true) == 'move_dependent') == spec[4])
    assert((policy.cancelOperationReason(current, action) == 'operation_dependent') == spec[4])
end
local indoor = generator(100, 100)
g.square.building, indoor.square.building = {}, nil
indoor.square.building = g.square.building
assert(adapter.sharesTarget(action, {generator = indoor}), 'indoor generators share building toxicity beyond their power areas')
indoor.square.building = {}
assert(not adapter.sharesTarget(action, {generator = indoor}), 'different buildings with disjoint power areas stay independent')
g.square.building = nil
assert(adapter.sharesTarget(action, {object = {class = 'IsoObject', getSquare = function() end}}), 'unloaded world targets retain protection')
local options = getSandboxOptions; getSandboxOptions = nil
assert(adapter.sharesTarget(action, {generator = other}), 'missing native range options cannot grant independence')
getSandboxOptions = options
-- A native appliance inspector supplies the same dependency to the policy.
local applianceClass = ISBaseTimedAction:derive('ISToggleStoveAction')
-- Register the class before its constructor instance is inspected.
ISToggleStoveAction = applianceClass
policy.registerNative('ISToggleStoveAction', function(a) return {items = {}, targets = {[a.object] = true}, cancelWaiting = true} end)
local stove = f.action(applianceClass, {object = appliance})
q = f.queue(head(), action, stove)
assert(policy.moveReason(q, stove, action) == 'move_dependent')
assert(policy.moveReason(q, action, stove, true) == 'move_dependent')
assert(policy.cancelOperationReason(q, action) == 'operation_dependent')
local book = f.action(ISReadABook, {item = f.item('Base.ElectronicsScrap')})
q, action = queued('onFixGenerator', g)
q.queue[#q.queue + 1] = book
assert(policy.moveReason(q, book, action) == 'move_craft_inputs')
assert(policy.moveReason(q, action, book, true) == 'move_craft_inputs')
assert(policy.cancelOperationReason(q, action) == 'operation_dependent')
local modScrap = f.action(ISReadABook, {item = f.item('Custom.ElectronicsScrap')})
q = f.queue(head(), action, modScrap)
assert(policy.moveReason(q, modScrap, action) == 'move_craft_inputs')
assert(policy.moveReason(q, action, modScrap, true) == 'move_craft_inputs')
assert(policy.cancelOperationReason(q, action) == 'operation_dependent', 'moduleless native repair reserves mod-defined scrap too')
-- Exact fuel IDs, bag ownership and hand slots are resources; menu-list edits cannot retarget them.
local a, b = fuel(100, 50), fuel(101, 20)
inv.items = {a, b}
q = f.queue(head()); local selection = {a}
ISWorldObjectContextMenu.doAddFuelGenerator(nil, g, selection, nil, 0); action = q.queue[2]
ISWorldObjectContextMenu.doAddFuelGenerator(nil, other, {a}, nil, 0); local sameFuel = q.queue[3]
assert(policy.moveReason(q, sameFuel, action) == 'move_shared_item')
assert(policy.cancelOperationReason(q, action) == 'operation_shared_item')
local bag = f.item('Base.Bag'); bag.class = 'InventoryContainer'
local nested = {class = 'ItemContainer', getContainingItem = function() return bag end,
    getParent = function() return nil end}
inv.class, inv.getContainingItem, inv.getParent = 'ItemContainer', function() return nil end, function() return nil end
local contained = fuel(103, 5); contained.getContainer = function() return nested end
q = f.queue(head()); ISWorldObjectContextMenu.doAddFuelGenerator(nil, g, {contained}, nil, 0)
local bagFuel = q.queue[2]; local bagMove = f.action(ISReadABook, {item = bag}); q.queue[3] = bagMove
assert(policy.moveReason(q, bagMove, bagFuel) == 'move_shared_item')
assert(policy.moveReason(q, bagFuel, bagMove, true) == 'move_shared_item')
assert(policy.cancelOperationReason(q, bagFuel) == 'operation_shared_item', 'moving the selected fuel bag is a resource dependency')
q = f.queue(head(), action)
local replace = fuel(100, 50); inv.items = {replace, b}; selection[1] = b
q.queue = {action}; q.current = action; action:begin(); action:start()
local fuelAction
for _, value in ipairs(q.queue) do if value.Type == 'ISAddFuel' then fuelAction = value end end
assert(fuelAction and fuelAction.petrol == replace, 'deferred native executor resolves saved IDs and owns selection order')
assert(fuelAction:complete() and g.fuel == 70 and replace.fluid.amount == 0 and replace.synced and g.synced)
local petrol = fuel(102, 10); inv.items = {petrol}
local refill = ISAddFuel:new(p, g, petrol, 70); refill.toolkitQueueOperation = {}
assert(policy.inspect(refill)); g.fuel = 100; assert(adapter.canSkip(refill)); g.fuel = 20
local connected = ISPlugGenerator:new(p, g, true); connected.toolkitQueueOperation = {}; assert(not adapter.canSkip(connected))
g.connected = true; assert(adapter.canSkip(connected)); g.connected = false
-- Native repair recursively consumes one scrap per completion, then stops without deleting the unrelated tail.
local scrap1, scrap2 = f.item('Base.ElectronicsScrap'), f.item('Base.ElectronicsScrap')
inv.items = {scrap1, scrap2}; g.condition = 92
local repair = ISFixGenerator:new(p, g); repair.toolkitQueueOperation = {}
local ending = head(); q = f.queue(repair, ending); repair:begin()
assert(policy.inspect(repair) and not policy.cancelOperationReason(q, repair), 'audited active repair can stop before completion')
local soundsBefore, removalsBefore, xpBefore = stoppedSounds, removedScraps, repairXp
repair:perform(); adapter.prune(); assert(adapter.fixtureRegistries[3][repair]==q, 'SP advancement must survive housekeeping until complete')
assert(q.current == repair and g.condition == 92 and #inv.items == 2
    and stoppedSounds == soundsBefore + 1 and removedScraps == removalsBefore and repairXp == xpBefore,
    'native SP perform stops sound before complete owns scrap, condition and XP')
assert(q.onCompleted == ISTimedActionQueue.onCompleted, 'temporary advancement interception restores the inherited queue method')
assert(repair:complete() and g.condition == 96 and #q.queue == 2 and q.queue[1].Type == 'ISFixGenerator')
adapter.prune(); assert(not adapter.fixtureRegistries[2][repair] and not adapter.fixtureRegistries[3][repair], 'completed repair must release its continuation guards')
local second = q.queue[1]; assert(second.toolkitQueueOperation == repair.toolkitQueueOperation and q.queue[2] == ending)
second:perform(); assert(q.current == second)
assert(second:complete() and g.condition == 100 and #inv.items == 0 and q.current == ending)
assert(stoppedSounds == soundsBefore + 2 and removedScraps == removalsBefore + 2 and repairXp == xpBefore + 10)
-- A cancellation between native perform and complete suppresses only future repairs, not the completed effect.
inv.items = {scrap1, scrap2}; g.condition = 92
repair = ISFixGenerator:new(p, g); repair.toolkitQueueOperation = {}; q = f.queue(repair, ending)
repair:perform(); PZSurvivorToolkit.ActionQueueOperations.invalidate(repair.toolkitQueueOperation)
assert(repair:complete() and g.condition == 96 and #inv.items == 1 and q.current == ending and #q.queue == 1)
repair:continueFixing(); assert(#q.queue == 1, 'cancelled completed repair cannot add a late child')
-- A queue replacement between perform and complete cannot advance or append to the new queue.
inv.items = {scrap1, scrap2}; g.condition = 92
repair = ISFixGenerator:new(p, g); repair.toolkitQueueOperation = {}; q = f.queue(repair, ending)
repair:perform(); local replacement = f.queue(ending)
assert(repair:complete() and g.condition == 96 and #inv.items == 1 and replacement.current == ending
    and #replacement.queue == 1 and q.current == repair, 'native effect survives reset without reviving the old queue')
-- MP perform predicts the same child using native addAfter; server-side complete never creates a client child.
client = true; inv.items = {scrap1, scrap2}; g.condition = 92
repair = ISFixGenerator:new(p, g); repair.toolkitQueueOperation = {}; q = f.queue(repair, ending)
removalsBefore, xpBefore = removedScraps, repairXp
repair:perform(); assert(q.current ~= repair and q.current.Type == 'ISFixGenerator' and q.queue[2] == ending
    and q.current.toolkitQueueOperation == repair.toolkitQueueOperation and g.condition == 92 and #inv.items == 2
    and removedScraps == removalsBefore and repairXp == xpBefore, 'MP perform enqueues a child without predicting server effects')
server, client = true, false; inv.items = {scrap1, scrap2}; g.condition = 92
repair = ISFixGenerator:new(p, g); repair.toolkitQueueOperation = {}; q = f.queue(repair, ending)
assert(repair:complete() and #q.queue == 2 and q.current == repair and g.condition == 96 and #inv.items == 1); server = false
-- Canceled operations and queue reset reject a late continuation while allowing native cleanup.
repair = ISFixGenerator:new(p, g); repair.toolkitQueueOperation = {}; q = f.queue(repair, ending)
PZSurvivorToolkit.ActionQueueOperations.invalidate(repair.toolkitQueueOperation)
repair:continueFixing(); assert(#q.queue == 2)
q.queue, q.current = {ending}, ending
repair:continueFixing(); assert(#q.queue == 1)
local late = ISFixGenerator:new(p, g); late.toolkitQueueOperation = {}
late:continueFixing(); assert(#q.queue == 1, 'an old action outside the live queue cannot attach a fresh continuation')
local saved = ISFixGenerator.continueFixing
ISFixGenerator.continueFixing = function() end
assert(not policy.inspect(ISFixGenerator:new(p, g)), 'changed continuation helper revokes permission')
ISFixGenerator.continueFixing = saved
for _,name in ipairs({'luautils','ISWorldObjectContextMenu','ISInventoryPaneContextMenu','ISInventoryTransferUtil',
    'ISInventoryTransferAction','ISEquipWeaponAction','ISUnequipAction','ISWalkToTimedAction'}) do
    local original=_G[name];local replacement={}
    for key,value in pairs(original) do replacement[key]=value end
    _G[name]=replacement
    assert(not policy.inspect(refill), 'replacing the global helper owner revokes native fuel permission: '..name)
    _G[name]=original
    assert(policy.inspect(refill),'restoring exact helper owner restores native permission: '..name)
end
local changedPlug = ISPlugGenerator.complete
ISPlugGenerator.complete = function() end
assert(policy.inspect(refill), 'an unrelated changed generator class cannot revoke native fuel permission')
assert(not policy.inspect(ISPlugGenerator:new(p, g, true)), 'changed plug class remains protected')
ISPlugGenerator.complete = changedPlug
local helper = ISWorldObjectContextMenu.equip
ISWorldObjectContextMenu.equip = function() error('foreign helper') end
assert(not policy.inspect(refill) and not adapter.canSkip(refill), 'changed shared executor helper revokes controls')
ISWorldObjectContextMenu.equip = helper
local constructor = ISEquipWeaponAction.new
ISEquipWeaponAction.new = function() error('foreign preparation') end
assert(not policy.inspect(refill), 'changed native preparation constructor revokes generator controls')
ISEquipWeaponAction.new = constructor
q, action = queued('onPlugGenerator', g, true)
action.args[1].callback = function() error('tampered command') end
assert(not policy.inspect(action), 'mutated private command snapshot revokes permission')
q.queue, q.current = {action}, action; action:begin(); action:start(); assert(#q.queue == 1)
-- Native completion still owns generator pickup, fuel/state synchronization and activation idempotence.
local take = ISTakeGenerator:new(p, other); assert(take:complete() and other.removed and p.primary == p.secondary)
local activate = ISActivateGenerator:new(p, g, true); g.connected = true; assert(activate:complete() and g.activated and g.synced)
assert(adapter.canSkip(activate))
local plug = ISPlugGenerator:new(p, g, false); assert(plug:complete() and not g.connected)
-- Disabled queue restores the native callback rather than leaving deferred work.
enabled = false; q = f.queue(head()); ISWorldObjectContextMenu.onPlugGenerator(nil, g, 0, true)
assert(q.queue[#q.queue].Type == 'ISPlugGenerator' and #q.queue == 1)
enabled = true
local originalCallback = ISWorldObjectContextMenu.onPlugGenerator
ISWorldObjectContextMenu.onPlugGenerator = function(_, object, num, mode)
    luautils.walkAdj(getSpecificPlayer(num), object:getSquare())
    ISTimedActionQueue.add(ISPlugGenerator:new(getSpecificPlayer(num), object, mode))
end
local sourceReader = getGameFilesInput
getGameFilesInput = function() return {readLine = function() return nil end, close = function() end} end
local opaque = f.project('ActionQueueGenerators'); opaque.install()
q = f.queue(head()); ISWorldObjectContextMenu.onPlugGenerator(nil, g, 0, true)
assert(#q.queue == 2 and q.queue[2].toolkitWorldOperation == 'device' and not policy.inspect(q.queue[2]),
    'an unknown producer still defers safely, without receiving queue permissions')
local deferred = q.queue[2]; q.queue, q.current = {deferred}, deferred; deferred:begin(); deferred:start()
assert(#q.queue == 2 and q.queue[2].Type == 'ISPlugGenerator', 'opaque fallback keeps the native executor')
getGameFilesInput = sourceReader
-- A preinstalled mod hook affects only its own class, even before source capture.
native('client/ISUI/ISWorldObjectContextMenu.lua')
for _,name in ipairs({'ISPlugGenerator','ISActivateGenerator','ISFixGenerator','ISAddFuel','ISTakeGenerator'}) do
    native('shared/TimedActions/'..name..'.lua')
end
native('client/TimedActions/ISGeneratorInfoAction.lua')
local bgiSource=NativeBGIPowerRangeSource or (NativeWishlistWorkshopRoot and readText(NativeWishlistWorkshopRoot
    .. '/3576056135/mods/Better Generator Info/42.20/media/lua/client/BGI/BGI_PowerRange.lua'))
if bgiSource then
    local begin=assert(bgiSource:find('-- Track only the generator explicitly requested for activation.',1,true))
    local ending=assert(bgiSource:find('-- [BGI] Expose internal helpers',begin,true))
    BGI_PowerRange={}
    local helpers='local function _BGI_ensureGenRegistered() return false end\nlocal function _BGI_requestUnionRebuild() end\n'
    assert(loadstring(helpers..bgiSource:sub(begin,ending-1),'@BGI/BGI_PowerRange.lua'))()
    assert(getFilenameOfClosure(ISPlugGenerator.complete):match('BGI_PowerRange.lua$'))
    assert(getFilenameOfClosure(ISActivateGenerator.complete):match('BGI_PowerRange.lua$'))
else
    ISPlugGenerator.complete=function() end
    ISActivateGenerator.complete=function() end
    ISWorldObjectContextMenu.onActivateGenerator=function() end
    BGI_PowerRange={}
end
f.project('ActionQueueOperations'); f.project('ActionQueueDefinitions'); policy=f.project('ActionQueuePolicy')
adapter=f.project('ActionQueueGenerators');adapter.install()
local repaired=ISFixGenerator:new(p,g);repaired.toolkitQueueOperation={}
local refilled=ISAddFuel:new(p,g,petrol,70);refilled.toolkitQueueOperation={}
local info=ISGeneratorInfoAction:new(p,g);info.toolkitQueueOperation={}
local carried=ISTakeGenerator:new(p,g);carried.toolkitQueueOperation={}
assert(policy.inspect(repaired) and policy.inspect(refilled) and policy.inspect(info) and policy.inspect(carried),
    'native repair/fuel/info/take survive preinstalled plug/activate hooks')
assert(not policy.inspect(ISPlugGenerator:new(p,g,true)) and not policy.inspect(ISActivateGenerator:new(p,g,true)),
    'modded plug/activate lifecycle stays opaque')
q,action=queued('onFixGenerator',g)
assert(policy.inspect(action) and not policy.cancelOperationReason(q,action),'native repair remains cancellable beside the book')
ISWorldObjectContextMenu.onPlugGenerator(nil,g,0,true)
assert(q.queue[3].toolkitWorldOperation=='device' and not policy.inspect(q.queue[3]),'modded plug producer stays opaque')
local distant={class='IsoObject',getSquare=function() return square(200,200,8) end}
local farStove=f.action(applianceClass,{object=distant})
policy.registerNative('ISToggleStoveAction',function(a) return {items={},targets={[a.object]=true},cancelWaiting=true} end)
q=f.queue(head(),action,farStove)
assert(policy.moveReason(q,farStove,action)=='move_dependent')
assert(policy.moveReason(q,action,farStove,true)=='move_dependent')
assert(policy.cancelOperationReason(q,action)=='operation_dependent','BGI unknown power scope protects distant world targets')
local distantContainer={class='ItemContainer',getParent=function() return distant end}
assert(adapter.sharesTarget(action,{srcContainer=distantContainer}) and adapter.sharesTarget({srcContainer=distantContainer},action))
assert(adapter.sharesTarget(action,{toolkitWorldX=200,toolkitWorldY=200,toolkitWorldZ=8}))
assert(not adapter.sharesTarget(action,head()),'native books remain independent of unknown BGI world scope')
local walk=luautils.walkAdj;luautils.walkAdj=function() end
assert(not policy.inspect(action) and not policy.inspect(repaired),'changed shared executor still revokes per-kind repair permission')
luautils.walkAdj=walk;BGI_PowerRange=nil
if bgiSource then
    native('client/ISUI/ISWorldObjectContextMenu.lua')
    for _,name in ipairs({'ISPlugGenerator','ISActivateGenerator','ISFixGenerator','ISAddFuel','ISTakeGenerator'}) do
        native('shared/TimedActions/'..name..'.lua')
    end
    native('client/TimedActions/ISGeneratorInfoAction.lua')
    local beforeRequire, beforeMods, beforeReader = require, getActivatedMods, getModFileReader
    local beforeGameInput = getGameFilesInput
    local beforeCell, beforePlayer = getCell, getPlayer
    getActivatedMods = function() return {contains=function(_, id) return id=='BetterGeneratorInfo' end} end
    local function reader(source)
        local text,index=source:gsub('\r',''),1
        return {readLine=function()
            if index>#text then return end
            local ending=text:find('\n',index,true)
            local line=text:sub(index,ending and ending-1 or #text);index=ending and ending+1 or #text+1;return line
        end,close=function() end}
    end
    getModFileReader = function(id, path)
        assert(id=='BetterGeneratorInfo' and path=='media/lua/client/BGI/BGI_PowerRange.lua')
        return reader(bgiSource)
    end
    getGameFilesInput = function(path)
        if path~='media/lua/client/BGI/BGI_PowerRange.lua' then return beforeGameInput(path) end
        return reader(NativeReadRawText and NativeWishlistWorkshopRoot and readText(NativeWishlistWorkshopRoot
            .. '/3576056135/mods/Better Generator Info/42.20/media/lua/client/BGI/BGI_PowerRange.lua',true) or bgiSource)
    end
    Events.LoadGridsquare, Events.OnObjectAboutToBeRemoved = {Add=function() end}, {Add=function() end}
    ISGeneratorInfoWindow={}
    getCell, getPlayer=function() return {} end, function() end
    require=function(name)
        if name=='BGI/BGI_PowerRange' then return assert(loadstring(bgiSource,'@BGI/BGI_PowerRange.lua'))() end
        return beforeRequire(name)
    end
    f.project('ActionQueueOperations'); f.project('ActionQueueDefinitions'); policy=f.project('ActionQueuePolicy')
    f.project('ActionQueueCompat'); local overlay=f.project('ActionQueueGeneratorOverlay')
    local beforeUnequip=ISUnequipAction.new
    ISUnequipAction.new=function() error('generator control called an unrelated equipment helper') end
    adapter=f.project('ActionQueueGenerators');adapter.prepareOverlay();adapter.install();policy.installContracts()
    assert(overlay.powerScopeKnown(), 'actual BGI must be installed around verified native delegates')
    for _,method in ipairs({'onPlugGenerator','onActivateGenerator'}) do
        q,action=queued(method,g,true)
        local book=head();q.queue[#q.queue+1]=book
        assert(policy.inspect(action) and not policy.cancelOperationReason(q,action), 'verified BGI command must be cancellable')
        assert(not policy.moveReason(q,book,action) and not policy.moveReason(q,action,book,true), 'BGI command can cross independent reading')
        local nativeAction=method=='onPlugGenerator' and ISPlugGenerator:new(p,g,true) or ISActivateGenerator:new(p,g,true)
        nativeAction.toolkitQueueOperation={}
        assert(policy.inspect(nativeAction), 'expanded BGI native step must retain its contract')
        assert(not adapter.sharesTarget(action,{object=distant}) and not adapter.sharesTarget({object=distant},action), 'audited overlay must not expand real power scope')
        assert(adapter.sharesTarget(action,{object=appliance}), 'audited overlay must retain actual power dependencies')
        local rebuild=BGI_PowerRange._rebuildUnionEdges
        BGI_PowerRange._rebuildUnionEdges=function() error('foreign overlay helper') end
        assert(not policy.inspect(action) and not policy.inspect(nativeAction), 'changed overlay helper must revoke deferred and expanded contracts')
        assert(adapter.sharesTarget(action,{object=distant}), 'changed overlay helper restores conservative world scope')
        BGI_PowerRange._rebuildUnionEdges=rebuild
        assert(policy.inspect(action) and policy.inspect(nativeAction))
        local match=overlay.matches;overlay.matches=function() return true end
        assert(not policy.inspect(action) and not policy.inspect(nativeAction), 'replaced overlay verifier must revoke contracts')
        overlay.matches=match
        PZSurvivorToolkit.ActionQueueGeneratorOverlay={}
        assert(not policy.inspect(action), 'replaced overlay adapter must revoke contracts')
        PZSurvivorToolkit.ActionQueueGeneratorOverlay=overlay
        g.removed=true;assert(adapter.canSkip(nativeAction));g.removed=nil
        enabled=false
        q=f.queue(head())
        if method=='onPlugGenerator' then ISWorldObjectContextMenu[method](nil,g,0,true)
        else ISWorldObjectContextMenu[method](nil,true,g,0) end
        for _,a in ipairs(q.queue) do assert(a.Type~='ISQueueActionsAction', 'disabled queue must preserve native BGI dispatch') end
        enabled=true
    end
    q,action=queued('onPlugGenerator',g,true)
    q.queue,q.current={action},action;action:begin();action:start()
    assert(q.queue[#q.queue].Type=='ISPlugGenerator' and policy.inspect(q.queue[#q.queue]), 'deferred BGI executor must expand to a trusted native step')
    require,getActivatedMods,getModFileReader=beforeRequire,beforeMods,beforeReader
    getGameFilesInput=beforeGameInput
    getCell,getPlayer=beforeCell,beforePlayer
    ISUnequipAction.new=beforeUnequip
    BGI_PowerRange=nil;f.project('ActionQueueGeneratorOverlay')
end
local cleanSource=NativeCleanUIInventoryContextSource or (NativeWishlistWorkshopRoot and readText(NativeWishlistWorkshopRoot
    .. '/3437629766/mods/CleanUI/42.19/media/lua/client/ISUI/ISInventoryPaneContextMenu.lua'))
if cleanSource then
    native('client/ISUI/ISWorldObjectContextMenu.lua')
    for _,name in ipairs({'ISPlugGenerator','ISActivateGenerator','ISFixGenerator','ISAddFuel','ISTakeGenerator'}) do
        native('shared/TimedActions/'..name..'.lua')
    end
    native('client/TimedActions/ISGeneratorInfoAction.lua')
    local helperEnd=assert(cleanSource:find('local CleanUI_reportedEvolvedRecipeRenameErrors',1,true))
    local transferStart=assert(cleanSource:find('function ISInventoryPaneContextMenu.transferIfNeeded',1,true))
    local transferEnd=assert(cleanSource:find('ISInventoryPaneContextMenu.onEjectMagazine',transferStart,true))
    local resetStart=assert(cleanSource:find('ISInventoryPaneContextMenu.cleanUILogTimedActionFix =',1,true))
    local resetEnd=assert(cleanSource:find('ISInventoryPaneContextMenu.cleanUIResetStaleEatingRetrigger =',resetStart,true))
    assert(loadstring(cleanSource:sub(1,helperEnd-1)..cleanSource:sub(transferStart,transferEnd-1)
        ..cleanSource:sub(resetStart,resetEnd-1),'@CleanUI/ISUI/ISInventoryPaneContextMenu.lua'))()
    local readerBefore=getGameFilesInput
    getGameFilesInput=function(path)
        if path~='media/lua/client/ISUI/ISInventoryPaneContextMenu.lua' then return readerBefore(path) end
        local rawSource=NativeReadRawText and NativeWishlistWorkshopRoot and readText(NativeWishlistWorkshopRoot
            .. '/3437629766/mods/CleanUI/42.19/media/lua/client/ISUI/ISInventoryPaneContextMenu.lua',true) or cleanSource
        local text,index=rawSource:gsub('\r',''),1
        return {readLine=function()
            if index>#text then return end
            local ending=text:find('\n',index,true)
            local line=text:sub(index,ending and ending-1 or #text);index=ending and ending+1 or #text+1;return line
        end,close=function() end}
    end
    f.project('ActionQueueOperations');f.project('ActionQueueDefinitions');policy=f.project('ActionQueuePolicy')
    adapter=f.project('ActionQueueGenerators');adapter.install()
    q,action=queued('onFixGenerator',g)
    assert(policy.inspect(action) and not policy.cancelOperationReason(q,action),'resolved pinned CleanUI source allows native repair controls')
    p.retrigger={stale=true};p.getTimedActionToRetrigger=function(self) return self.retrigger end
    p.setTimedActionToRetrigger=function(self,value) self.retrigger=value end
    local bagSource={class='ItemContainer',getType=function() return 'bag' end,getParent=function() return nil end,
        isInCharacterInventory=function() return true end,isVehicleSeat=function() return false end}
    local scrap=f.item('Base.ElectronicsScrap');scrap.getContainer=function() return bagSource end
    scrap.getActualWeight=function() return 0.1 end;scrap.isHumanCorpse=function() return false end
    scrap.isFavorite=function() return false end
    inv.isInCharacterInventory=function() return true end;inv.isVehicleSeat=function() return false end
    getTimestampMs=function() return 1 end;getCore=function() return {getGameMode=function() return 'Sandbox' end} end
    CharacterTrait={DEXTROUS='DEXTROUS',ALL_THUMBS='ALL_THUMBS'}
    p.hasTrait=function() return false end;p.isWearingAwkwardGloves=function() return false end
    q=f.queue(head())
    assert(ISInventoryPaneContextMenu.transferIfNeeded(p,scrap),'actual CleanUI lexical safe transfer helper failed')
    assert(not p.retrigger and #q.queue==2 and q.queue[2].Type=='ISInventoryTransferAction'
        and q.queue[2].item==scrap and q.queue[2].srcContainer==bagSource and q.queue[2].destContainer==inv,
        'actual CleanUI helper must clear stale retrigger and enqueue the native exact-item transfer')
    inv.items={scrap};g.activated=false;g.condition=92;p.retrigger={stale=true}
    q,action=queued('onFixGenerator',g)
    q.queue,q.current={action},action;action:begin();action:start()
    assert(not p.retrigger and #q.queue==3 and q.queue[2].Type=='ISInventoryTransferAction'
        and q.queue[2].item==scrap and q.queue[3].Type=='ISFixGenerator'
        and q.queue[2].toolkitQueueOperation==action.toolkitQueueOperation
        and q.queue[3].toolkitQueueOperation==action.toolkitQueueOperation,
        'actual deferred generator producer keeps CleanUI private pickup and native repair in one operation')
    local reset=ISInventoryPaneContextMenu.cleanUIResetStaleTimedActionRetrigger
    ISInventoryPaneContextMenu.cleanUIResetStaleTimedActionRetrigger=function() error('foreign cleanup') end
    assert(not policy.inspect(action),'changed CleanUI retrigger cleanup revokes generator permission')
    ISInventoryPaneContextMenu.cleanUIResetStaleTimedActionRetrigger=reset
    local logger=ISInventoryPaneContextMenu.cleanUILogTimedActionFix
    ISInventoryPaneContextMenu.cleanUILogTimedActionFix=function() error('foreign diagnostics') end
    assert(not policy.inspect(action),'changed CleanUI logger revokes generator permission')
    ISInventoryPaneContextMenu.cleanUILogTimedActionFix=logger
    assert(policy.inspect(action),'restored exact CleanUI helpers restore command trust')
    getGameFilesInput=readerBefore
end
-- Unknown preparation constructors keep deferred native requests opaque and preserve a book tail.
native('client/ISUI/ISWorldObjectContextMenu.lua')
for _,name in ipairs({'ISPlugGenerator','ISActivateGenerator','ISFixGenerator','ISAddFuel','ISTakeGenerator'}) do
    native('shared/TimedActions/'..name..'.lua')
end
native('client/TimedActions/ISGeneratorInfoAction.lua')
local transferConstructor=ISInventoryTransferAction.new
ISInventoryTransferAction.new=function(self,...) return transferConstructor(self,...) end
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions');policy=f.project('ActionQueuePolicy')
adapter=f.project('ActionQueueGenerators');adapter.install()
local opaqueScrap=f.item('Base.ElectronicsScrap');inv.items={opaqueScrap};g.activated=false;g.condition=92
q,action=queued('onFixGenerator',g)
assert(#q.queue==2 and action.toolkitWorldOperation=='device' and not policy.inspect(action),
    'an unknown transfer constructor keeps the generator request deferred and uneditable')
local bookTail=head();q.queue,q.current={action,bookTail},action;action:begin();action:start()
assert(#q.queue==3 and q.queue[2].Type=='ISFixGenerator' and q.queue[3]==bookTail,
    'opaque native callback executes without removing the unrelated book tail')
inv.items={scrap1,scrap2};g.condition=92
local opaqueRepair=q.queue[2];q.queue,q.current={opaqueRepair,bookTail},opaqueRepair
assert(not policy.inspect(opaqueRepair), 'native repair with an unknown transfer helper stays protected')
opaqueRepair:perform();assert(q.current==opaqueRepair and g.condition==92 and #inv.items==2,
    'opaque native repair retains its continuation parent until complete')
assert(opaqueRepair:complete() and g.condition==96 and #inv.items==1 and #q.queue==2
    and q.queue[1].Type=='ISFixGenerator' and q.queue[2]==bookTail,
    'protected native repair continues even when a mod owns inventory transfer construction')
local opaqueChild=q.queue[1]
assert(opaqueChild.toolkitQueueOperation==opaqueRepair.toolkitQueueOperation and not policy.inspect(opaqueChild))
opaqueChild:perform();assert(opaqueChild:complete() and g.condition==100 and #inv.items==0 and q.current==bookTail)
ISInventoryTransferAction.new=transferConstructor
-- Only the verified cart adapter may authorize exact observed transfer constructor replacements.
native('client/ISUI/ISWorldObjectContextMenu.lua')
assert(loadstring(source:sub(first,last-1),'@media/lua/client/ISUI/ISInventoryPaneContextMenu.lua'))()
for _,name in ipairs({'ISPlugGenerator','ISActivateGenerator','ISFixGenerator','ISAddFuel','ISTakeGenerator'}) do
    native('shared/TimedActions/'..name..'.lua')
end
native('client/TimedActions/ISGeneratorInfoAction.lua')
local cartInitial=function(self,...) return transferConstructor(self,...) end
local cartLater=function(self,...) return cartInitial(self,...) end
local approved,cartActive,latest={[cartInitial]=true,[cartLater]=true},true,cartInitial
PZSurvivorToolkit.ActionQueueCarts={isTransferConstructor=function(callback)
    return cartActive and approved[callback]==true and ISInventoryTransferAction.new==latest
end,isTransfer=function() return false end,isReturn=function() return false end}
ISInventoryTransferAction.new=cartInitial
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions');policy=f.project('ActionQueuePolicy')
local pendingCarts=PZSurvivorToolkit.ActionQueueCarts;PZSurvivorToolkit.ActionQueueCarts=nil
adapter=f.project('ActionQueueGenerators');PZSurvivorToolkit.ActionQueueCarts=pendingCarts;adapter.install()
q,action=queued('onFixGenerator',g)
local cartRepair=ISFixGenerator:new(p,g)
assert(policy.inspect(action) and policy.inspect(cartRepair), 'verified initial cart constructor allows native generator contracts')
latest=cartLater;ISInventoryTransferAction.new=cartLater
assert(policy.inspect(action) and policy.inspect(cartRepair), 'verified later cart constructor preserves captured native generator contracts')
local cartAPI=PZSurvivorToolkit.ActionQueueCarts
PZSurvivorToolkit.ActionQueueCarts=nil
assert(not policy.inspect(action), 'removing the verified cart adapter revokes captured generator trust')
PZSurvivorToolkit.ActionQueueCarts=cartAPI
local cartCheck=cartAPI.isTransferConstructor
cartAPI.isTransferConstructor=function() return true end
assert(not policy.inspect(action), 'replacing the cart verification callback cannot grant generator trust')
cartAPI.isTransferConstructor=cartCheck
cartActive=false
assert(not policy.inspect(action) and not policy.inspect(cartRepair), 'cart guard revocation protects generator controls even with an unchanged current constructor')
cartActive=true;approved[cartInitial]=nil
assert(not policy.inspect(action), 'the captured cart constructor must remain approved alongside the current one')
approved[cartInitial]=true
ISInventoryTransferAction.new=function(self,...) return cartLater(self,...) end
assert(not policy.inspect(action), 'unobserved transfer constructor replacement cannot inherit cart trust')
ISInventoryTransferAction.new=cartLater
local equipConstructor=ISEquipWeaponAction.new
local foreignEquip=function(self,...) return equipConstructor(self,...) end
local cartRefill=ISAddFuel:new(p,g,petrol,70)
local cartTake=ISTakeGenerator:new(p,g)
assert(policy.inspect(cartRefill) and policy.inspect(cartTake),'verified cart constructor must preserve other native generator permissions before equipment changes')
approved[foreignEquip]=true;ISEquipWeaponAction.new=foreignEquip
assert(policy.inspect(action) and policy.inspect(cartRepair) and not policy.inspect(cartRefill) and not policy.inspect(cartTake),
    'an unrelated equipment constructor cannot revoke repair or inherit fuel permission from cart approval')
ISEquipWeaponAction.new=equipConstructor
assert(policy.inspect(action), 'restoring the exact native helper restores verified cart generator contracts')
-- The equipment proof boundary admits actual non-cart wrappers only for this producer's preparations.
if SaucedCartsSource then
    native('client/ISUI/ISWorldObjectContextMenu.lua')
    for _,name in ipairs({'ISPlugGenerator','ISActivateGenerator','ISFixGenerator','ISAddFuel','ISTakeGenerator','ISUnequipAction'}) do
        native('shared/TimedActions/'..name..'.lua')
    end
    native('client/TimedActions/ISGeneratorInfoAction.lua')
    f.project('ActionQueueOperations');f.project('ActionQueueDefinitions');policy=f.project('ActionQueuePolicy')
    local previous={new=ISUnequipAction.new,complete=ISUnequipAction.complete}
    local path=SaucedCartsSource..'/ContainerRestrictions.lua'
    local text=readText(path):gsub('\r','')
    SaucedCarts={debug=function() end,safeIsCart=function(value) return value and value.cart==true end}
    local code='local unequipHookInitialized=false\n'
        ..assert(text:match('(local function flushDistanceOnCreate%(character, item, label%).-\nend)'))..'\n'
        ..assert(text:match('(local function wrapUnequipNew%(%).-\nend)'))..'\n'
        ..assert(text:match('(local function initUnequipHook%(%).-\nend)'))..'\ninitUnequipHook()'
    assert(loadstring(code,'@'..path))()
    local replacement={new=ISUnequipAction.new,complete=ISUnequipAction.complete}
    local equipmentActive=true
    local matcher=assert(policy.nativeUnequipVariant(previous,replacement,function() return equipmentActive end))
    cartAPI.isUnequipConstructor=function(callback)
        return equipmentActive and (callback==previous.new or callback==replacement.new)
            and ISUnequipAction.new==replacement.new and ISUnequipAction.complete==replacement.complete
    end
    cartAPI.isNonCartUnequip=function(value) return matcher(value) and not value.item.cart end
    cartAPI.equipmentSafe=function(character)
        return equipmentActive and not (character.primary and character.primary.cart) and not (character.secondary and character.secondary.cart)
    end
    adapter=f.project('ActionQueueGenerators');adapter.install()
    p.primary,p.secondary=nil,nil
    local refill=ISAddFuel:new(p,g,petrol,70)
    assert(policy.inspect(refill) and policy.inspect(ISTakeGenerator:new(p,g)),'audited non-cart equipment did not restore native generator kinds')
    for _,hand in ipairs({'primary','secondary'}) do
        p[hand]={cart=true}
        assert(not policy.inspect(refill) and not policy.inspect(ISTakeGenerator:new(p,g)),'held cart acquired generator equipment permission: '..hand)
        q,action=queued('onTakeGenerator',g)
        assert(not policy.inspect(action) and action.toolkitWorldOperation=='device','held cart acquired deferred pickup permission')
        p[hand]=nil
    end
    q,action=queued('onTakeGenerator',g)
    assert(policy.inspect(action),'ordinary pickup request stayed opaque')
    p.primary={cart=true}
    assert(not policy.inspect(action),'cart acquired after enqueue retained deferred generator trust')
    q.queue,q.current={action},action;action:begin();action:start()
    assert(#q.queue==1,'deferred pickup expanded after a cart entered the hands')
    p.primary=nil
    ISWearClothing={isStopOnWalk=function() return false end}
    p.primary=f.item('Base.Hammer');p.primary.isTwoHandWeapon=function() return false end
    p.primary.isRequiresEquippedBothHands=function() return false end
    q,action=queued('onTakeGenerator',g)
    q.queue,q.current={action},action;action:begin();action:start()
    local preparation
    for _,member in ipairs(q.queue) do if member.Type=='ISUnequipAction' then preparation=member end end
    assert(preparation and policy.inspect(preparation),'producer-owned actual non-cart unequip stayed opaque')
    assert(not policy.inspect(ISUnequipAction:new(p,p.primary,50)),'unowned unequip borrowed generator preparation trust')
    equipmentActive=false
    assert(not policy.inspect(preparation) and not policy.inspect(refill),'equipment proof revocation retained generator rights')
    equipmentActive=true;p.primary=nil
    cartAPI.equipmentSafe,cartAPI.isUnequipConstructor,cartAPI.isNonCartUnequip=nil,nil,nil
end
cartActive=false
native('client/ISUI/ISWorldObjectContextMenu.lua')
for _,name in ipairs({'ISPlugGenerator','ISActivateGenerator','ISFixGenerator','ISAddFuel','ISTakeGenerator'}) do
    native('shared/TimedActions/'..name..'.lua')
end
native('client/TimedActions/ISGeneratorInfoAction.lua')
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions');policy=f.project('ActionQueuePolicy')
adapter=f.project('ActionQueueGenerators');adapter.install()
q,action=queued('onFixGenerator',g)
assert(not policy.inspect(action) and action.toolkitWorldOperation=='device', 'unverified cart adapter cannot grant generator controls during installation')
PZSurvivorToolkit.ActionQueueCarts=nil
assert(not policy.inspect(action), 'absent cart adapter keeps the unknown constructor protected')
ISInventoryTransferAction.new=transferConstructor
-- Native repair does not call equipment helpers, even when SaucedCarts wraps unequip before capture.
native('client/ISUI/ISWorldObjectContextMenu.lua')
for _,name in ipairs({'ISPlugGenerator','ISActivateGenerator','ISFixGenerator','ISAddFuel','ISTakeGenerator','ISUnequipAction'}) do
    native('shared/TimedActions/'..name..'.lua')
end
native('client/TimedActions/ISGeneratorInfoAction.lua')
local unequipConstructor=ISUnequipAction.new
if SaucedCartsSource then
    local path=SaucedCartsSource..'/ContainerRestrictions.lua'
    local wrapper=assert(readText(path):gsub('\r',''):match('(local function wrapUnequipNew%(%).-\nend)'))
    SaucedCarts={debug=function() end}
    assert(loadstring('local function flushDistanceOnCreate() error("repair called an unrelated unequip helper") end\n'
        ..wrapper..'\nwrapUnequipNew()','@'..path))()
else
    ISUnequipAction.new=function() error('repair called an unrelated unequip constructor') end
end
local nativeGeneratorComplete=ISFixGenerator.complete
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions');policy=f.project('ActionQueuePolicy')
adapter=f.project('ActionQueueGenerators');adapter.install()
inv.items={scrap1,scrap2};g.activated=false;g.condition=92
q,action=queued('onFixGenerator',g)
assert(policy.inspect(action) and action.toolkitWorldOperation=='generator',
    'preinstalled unrelated unequip hook revoked the native repair producer')
assert(not policy.inspect(ISTakeGenerator:new(p,g)) and not policy.inspect(ISAddFuel:new(p,g,petrol,70)),
    'equipment-dependent generator kinds must remain protected under an unaudited unequip hook')
local equipHelper=ISWorldObjectContextMenu.equip
ISWorldObjectContextMenu.equip=function() error('repair called an unrelated equip helper') end
assert(policy.inspect(action),'changed unused equipment helper revoked native repair');ISWorldObjectContextMenu.equip=equipHelper
local unequipOwner=ISUnequipAction;ISUnequipAction={new=function() error('foreign unequip owner') end}
assert(policy.inspect(action),'replacing an unused equipment class revoked native repair');ISUnequipAction=unequipOwner
local scrapTransfer=ISInventoryPaneContextMenu.transferIfNeeded
ISInventoryPaneContextMenu.transferIfNeeded=function() end
assert(not policy.inspect(action),'native repair must still guard its scrap transfer helper');ISInventoryPaneContextMenu.transferIfNeeded=scrapTransfer
local moveConstructor=ISWalkToTimedAction.new;ISWalkToTimedAction.new=function() end
assert(not policy.inspect(action),'native repair must still guard its walking constructor');ISWalkToTimedAction.new=moveConstructor
ISInventoryTransferAction.new=function() end
assert(not policy.inspect(action),'unknown scrap transfer constructor gained permission through equipment scope');ISInventoryTransferAction.new=transferConstructor
local repairTail=head();q.queue,q.current={action,repairTail},action;action:begin();action:start()
local scopedRepair=q.queue[2];q.queue,q.current={scopedRepair,repairTail},scopedRepair;scopedRepair:begin()
assert(policy.inspect(scopedRepair) and not policy.cancelOperationReason(q,scopedRepair),
    'native active repair must remain cancellable beside unrelated reading under the unequip hook')
scopedRepair:perform();assert(scopedRepair:complete() and g.condition==96 and #inv.items==1)
local scopedChild=q.current
assert(scopedChild.Type=='ISFixGenerator' and policy.inspect(scopedChild) and not policy.cancelOperationReason(q,scopedChild)
    and scopedChild.toolkitQueueOperation==scopedRepair.toolkitQueueOperation and q.queue[2]==repairTail,
    'continuation lost the scoped repair permission, token or unrelated reading')
PZSurvivorToolkit.ActionQueueLabels={label=function() return 'fixture' end}
local queueAPI=f.project('ActionQueue')
ISInventoryPaneContextMenu.getContainers=function() return {contains=function(_,value) return value==inv end} end
p.getCharacterActions=function() return {contains=function(_,value) return value and not value.fixtureStopped end} end
p.tooDarkToRead=function() return false end
inv.contains=function(self,value) for _,item in ipairs(self.items) do if item==value then return true end end return false end
repairTail.item.getNumberOfPages=function() return 100 end;repairTail.item.getAlreadyReadPages=function() return 99 end
inv.items[#inv.items+1]=repairTail.item
scopedChild.action.forceStop=function(self) self.fixtureStopped=true end
local committedXP=repairXp
assert(queueAPI.cancelOperation(q,scopedChild) and scopedChild.toolkitQueueOperation.toolkitCancelled,
    'actual queue API rejected the second scoped repair cancellation')
scopedChild:stop();q:tick()
assert(g.condition==96 and repairXp==committedXP and inv:contains(scrap2) and not inv:contains(scrap1)
    and q.current==repairTail and #q.queue==1,'second scoped repair cancellation changed committed effects, unused scrap or reading tail')
ISUnequipAction.new=unequipConstructor
-- Supported native completion must replace both family and Operations completion scopes.
do
    local lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
    local protected,localCompleteCalls=pcall,0
    pcall=function(callback,...)
        if callback==nativeGeneratorComplete then localCompleteCalls=localCompleteCalls+1 end
        return protected(callback,...)
    end
    local bookTail=head()
    bookTail.item.getNumberOfPages=function() return 100 end
    bookTail.item.getAlreadyReadPages=function() return 99 end
    inv.items={scrap1,scrap2,bookTail.item};g.condition=92
    local parent=ISFixGenerator:new(p,g);parent.toolkitQueueOperation={}
    local currentQueue=f.queue(parent,bookTail);parent:begin();adapter.prune()
    assert(next(adapter.fixtureRegistries[3])==nil,'native-boundary regression requires an empty fallback registry')
    local stopSound,sharedPerforms=p.stopOrTriggerSound,0
    p.stopOrTriggerSound=function(...)
        local active=currentQueue.current
        assert(lifecycle.current(p)==active and not PZSurvivorToolkit.ActionQueueOperations.deferCompletion(currentQueue,active),
            'migrated repair acquired the legacy Operations completion scope')
        sharedPerforms=sharedPerforms+1
        return stopSound(...)
    end
    for iteration=1,2 do
        local repairing=currentQueue.current
        assert(repairing.Type=='ISFixGenerator' and repairing.toolkitQueueOperation==parent.toolkitQueueOperation,
            'native continuation lost the original operation')
        assert(bookTail.toolkitQueueOperation~=parent.toolkitQueueOperation,'independent reading tail joined the repair operation')
        local condition,removals,xp=g.condition,removedScraps,repairXp
        assert(lifecycle.begin(repairing,'perform') and lifecycle.current(p)==repairing)
        repairing:perform()
        assert(next(adapter.fixtureRegistries[3])==nil,
            'active common lifecycle must bypass the generator pendingPerform fallback')
        lifecycle.finish(repairing,'perform',true)
        assert(lifecycle.current(p)==nil and currentQueue.current==repairing
            and g.condition==condition and removedScraps==removals and repairXp==xp,
            'SP perform advanced or applied complete effects before the common lifecycle settled')
        assert(lifecycle.flush(currentQueue)=='waiting','common lifecycle skipped the SP complete gate')
        assert(lifecycle.begin(repairing,'complete'))
        assert(repairing:complete())
        lifecycle.finish(repairing,'complete',true)
        assert(g.condition==condition+4 and removedScraps==removals+1 and repairXp==xp+5 and currentQueue.current==repairing,
            'native completion must apply one effect while retaining its parent')
        assert(currentQueue.queue[#currentQueue.queue]==bookTail and next(adapter.fixtureRegistries[3])==nil,
            'native completion changed the independent tail or reactivated the fallback')
        if iteration==1 then
            local child=currentQueue.queue[2]
            assert(#currentQueue.queue==3 and child.Type=='ISFixGenerator'
                and child.toolkitQueueOperation==parent.toolkitQueueOperation,
                'SP complete did not insert its child into the same operation before reading')
        else assert(#currentQueue.queue==2,'final native repair added an extra continuation') end
        assert(lifecycle.flush(currentQueue)=='waiting' and currentQueue.current==repairing,
            'common lifecycle advanced before native removal')
        repairing.action.fixtureStopped=true
        assert(lifecycle.flush(currentQueue)=='completed' and currentQueue.current~=repairing,
            'common lifecycle did not advance after native completion and removal')
    end
    assert(g.condition==100 and not inv:contains(scrap1) and not inv:contains(scrap2)
        and inv:contains(bookTail.item) and currentQueue.current==bookTail and #currentQueue.queue==1,
        'native completion bypass changed exact repair consumption or the independent reading tail')
    assert(localCompleteCalls==0,'shared native completion still entered the local protected completion layer')
    -- The Host client adds its continuation in perform; complete/effects stay server-owned.
    client=true;g.condition=92;inv.items={scrap1,scrap2,bookTail.item}
    parent=ISFixGenerator:new(p,g);parent.toolkitQueueOperation={}
    currentQueue=f.queue(parent,bookTail);parent:begin()
    local condition,removals,xp=g.condition,removedScraps,repairXp
    assert(lifecycle.begin(parent,'perform'))
    parent:perform();lifecycle.finish(parent,'perform',true)
    local child=currentQueue.queue[2]
    assert(child.Type=='ISFixGenerator' and child.generator==g and policy.inspect(child)
        and child.toolkitQueueOperation==parent.toolkitQueueOperation and currentQueue.queue[3]==bookTail,
        'Host native repair continuation lost its contract or independent tail')
    assert(g.condition==condition and removedScraps==removals and repairXp==xp
        and next(adapter.fixtureRegistries[3])==nil,'Host client applied server effects or used SP fallback')
    assert(lifecycle.flush(currentQueue)=='waiting','Host client advanced before native removal')
    parent.action.fixtureStopped=true
    assert(lifecycle.flush(currentQueue)=='completed' and currentQueue.current==child
        and lifecycle.flush(currentQueue)==nil,'Host completion needed a client complete phase or replayed advancement')
    assert(sharedPerforms==3,'native repair perform checks did not run for both SP steps and Host')
    p.stopOrTriggerSound=stopSound;client=false
    -- Native false/error results still settle a pending SP fallback, but direct calls need no local protection.
    local getScrap=inv.getFirstTypeRecurse
    for _,fallback in ipairs({false,true}) do
        for _,fails in ipairs({false,true}) do
            local parent=ISFixGenerator:new(p,g);parent.toolkitQueueOperation={}
            local ending=head();local currentQueue=f.queue(parent,ending);parent:begin()
            if fallback then parent:perform();assert(adapter.fixtureRegistries[3][parent]==currentQueue) end
            inv.getFirstTypeRecurse=function()
                if fails then error('fixture generator completion failed',0) end
            end
            local before=localCompleteCalls
            local ok,result=protected(function() return parent:complete() end)
            assert(ok==not fails and (fails and tostring(result):find('fixture generator completion failed',1,true) or not fails and result==false),
                'native completion false/error result was lost')
            assert(localCompleteCalls-before==(fallback and 1 or 0)
                and adapter.fixtureRegistries[3][parent]==nil and currentQueue.current==(fallback and ending or parent),
                'completion protection or settlement escaped its pending SP fallback')
            inv.getFirstTypeRecurse=getScrap
        end
    end
    pcall=protected
end
print('Generator native contracts passed: native callbacks/completions, resource/power edges, cancellation guards, recursive SP/MP repair and source/helper trust.')
