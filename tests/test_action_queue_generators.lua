if not NativeActionRoot then print('Generator native contracts SKIP.'); return end
local f = assert(loadfile(ProjectRoot .. '/tests/support/action_queue_native.lua'))()
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
p.stopOrTriggerSound = function() end
getPlayerHotbar = function() return nil end
local function square(x, y, z)
    return {getX = function() return x or 0 end, getY = function() return y or 0 end, getZ = function() return z or 0 end,
        getObjects = function() return list({}) end, has = function() return false end, canReachTo = function() return true end}
end
p.square = square(); p.getSquare = function(self) return self.square end
p.getCurrentSquare = p.getSquare
p.getX, p.getY = function() return 0.5 end, function() return 0.5 end
AdjacentFreeTileFinder = {Find = function(target) return target end}
native('client/TimedActions/WalkToTimedAction.lua')
IsoGenerator = {isPoweringSquare = function(x, y, z, tx, ty, tz) return (x - tx)^2 + (y - ty)^2 <= 400 and math.abs(z - tz) <= 3 end}
local originalInstanceof = instanceof
instanceof = function(value, name)
    return originalInstanceof(value, name) or name == 'InventoryItem' and type(value) == 'table' and value.class == 'InventoryContainer'
        or name == 'IsoObject' and type(value) == 'table' and value.class == 'IsoGenerator'
end
sendRemoveItemFromContainer = function() end
sendAddItemToContainer, sendEquip = function() end, function() end
addXp = function(_, _, xp) assert(xp == 5) end
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
repair:perform(); assert(q.current == repair and g.condition == 92, 'native SP performs before completing')
assert(repair:complete() and g.condition == 96 and #q.queue == 2 and q.queue[1].Type == 'ISFixGenerator')
local second = q.queue[1]; assert(second.toolkitQueueOperation == repair.toolkitQueueOperation and q.queue[2] == ending)
second:perform(); assert(q.current == second)
assert(second:complete() and g.condition == 100 and #inv.items == 0 and q.current == ending)
-- A cancellation between native perform and complete suppresses only future repairs, not the completed effect.
inv.items = {scrap1, scrap2}; g.condition = 92
repair = ISFixGenerator:new(p, g); repair.toolkitQueueOperation = {}; q = f.queue(repair, ending)
repair:perform(); PZSurvivorToolkit.ActionQueueOperations.invalidate(repair.toolkitQueueOperation)
assert(repair:complete() and g.condition == 96 and #inv.items == 1 and q.current == ending and #q.queue == 1)
-- MP perform predicts the same child using native addAfter; server-side complete never creates a client child.
client = true; inv.items = {scrap1, scrap2}; g.condition = 92
repair = ISFixGenerator:new(p, g); repair.toolkitQueueOperation = {}; q = f.queue(repair, ending)
repair:perform(); assert(q.current.Type == 'ISFixGenerator' and q.queue[2] == ending)
server, client = true, false; inv.items = {scrap1, scrap2}; g.condition = 92
repair = ISFixGenerator:new(p, g); repair.toolkitQueueOperation = {}; q = f.queue(repair, ending)
assert(repair:complete() and #q.queue == 2); server = false
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
ISInventoryTransferAction.new=transferConstructor
print('Generator native contracts passed: native callbacks/completions, resource/power edges, cancellation guards, recursive SP/MP repair and source/helper trust.')
