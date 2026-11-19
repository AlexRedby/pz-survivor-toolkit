-- Identity/access facts only; native transfer effects are checked separately below.
toolkitLuaMetatableMatches = assert(loadfile(ProjectRoot..'/tests/support/source_binding.lua'))()
local Proof = assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
local invokers = {}
local function java(fn)invokers[fn] = true;return fn end
getClassSimpleName = java(function(value)return invokers[value] and 'LuaJavaInvoker'or type(value) == 'table'and value.class or 'KahluaClosure'end)
instanceof = java(function(value, name)return type(value) == 'table'and(value.class == name or name == 'InventoryItem'and value.class == 'ComboItem') end )
local function values(...)
    local result = {class = 'ArrayList', ...}
    function result:size()return #self end
    function result:get(index)return self[index+1] end
    return result
end
local player, currentCell, multiplayer
getCell = java(function()return currentCell end )
getSpecificPlayer = java(function(number)if number == 0 then return player end end )
isClient = java(function()return multiplayer end )
local allow = true
SafeHouse = {isSafehouseAllowLoot = java(function()return allow end )}
ItemTag = {GENERATOR = {}, WEARABLE = {}, REPLACE_PRIMARY = {}}
PZSurvivorToolkit = {}
require = function(name)assert(name == 'PZSurvivorToolkit/SourceProof');return Proof end
local Heavy = assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueHeavyPickup.lua'))()
local function fixture()
    multiplayer = false;allow = true
    local square = {class = 'IsoGridSquare', worlds = values(), objects = values()}
    function square:getX()return 10 end ;function square:getY()return 20 end ;function square:getZ()return 0 end
    function square:getWorldObjects()return self.worlds end ;function square:getObjects()return self.objects end
    currentCell = {getGridSquare = function(_, x, y, z)if x == 10 and y == 20 and z == 0 then return square end end }
    local function container(kind)
        local c = {class = 'ItemContainer', items = values(), kind = kind}
        function c:getItems()return self.items end
        function c:getItemWithID(id)for _, item in ipairs(self.items) do if item.id == id then return item end end end
        function c:getType()return self.kind end
        function c:getParent() end ;function c:getContainingItem() end ;function c:getVehiclePart() end
        function c:getAcceptItemFunction() end ;function c:getOnlyAcceptCategory() end
        function c:isExistYet()return true end ;function c:isRemoveItemAllowed()return true end
        function c:isItemAllowed()return true end ;function c:hasRoomFor()return true end ;function c:isInside()return false end
        return c
    end
    local root, floor = container('inventory'), container('floor')
    local item = {class = 'ComboItem', id = 42, fullType = 'Base.StoneAnvil', container = root}
    function item:getID()return self.id end ;function item:getFullType()return self.fullType end
    function item:getContainer()return self.container end ;function item:getWorldItem()return self.world end
    function item:hasComponents()return false end ;function item:isForceDropHeavyItem()return true end
    function item:isRequiresEquippedBothHands()return true end ;function item:isHumanCorpse()return false end
    function item:canBeActivated()return false end ;function item:getAttachedSlot()return -1 end
    function item:getIsCraftingConsumed()return false end ;function item:hasTag(tag)return self.tag == tag end
    root.items = values(item)
    player = {class = 'IsoPlayer', primary = item, secondary = item, root = root, square = square, x = 10.25, y = 20.75, z = 0, onlineId = 7}
    function player:getPrimaryHandItem()return self.primary end ;function player:getSecondaryHandItem()return self.secondary end
    function player:getInventory()return self.root end ;function player:getCurrentSquare()return self.square end
    function player:getX()return self.x end ;function player:getY()return self.y end ;function player:getZ()return self.z end
    function player:getPlayerNum()return 0 end ;function player:getOnlineID()return self.onlineId end
    function player:getClothingItem_Back()return self.back end
    function player:isLocalPlayer()return true end ;function player:isDead()return false end ;function player:isAsleep()return false end
    function player:isEquipped(value)return value == self.primary or value == self.secondary end
    function player:canAccessContainer()return true end
    ISInventoryPage = {floorContainer = {[1] = floor}}
    local function drop(replacement)
        player.primary, player.secondary = nil, nil;root.items = values()
        if replacement then item = replacement end
        local world = {class = 'IsoWorldInventoryObject', item = item, square = square}
        function world:getItem()return self.item end ;function world:getSquare()return self.square end
        function world:hasComponents()return false end
        item.container = nil;item.world = world;square.worlds = values(world);square.objects = values(world)
        return world, item
    end
    local function refresh()floor.items = values(item);item.container = floor end
    local function pickup()square.worlds = values();square.objects = values();floor.items = values();item.world = nil;item.container = root;root.items = values(item) end
    return item, root, floor, square, drop, refresh, pickup
end
do
    local item, root, floor, square, drop, refresh, pickup = fixture()
    local record = assert(Heavy.capture(player))
    assert(record.actor == player and record.root == root and record.item == item and record.id == 42
        and record.fullType == 'Base.StoneAnvil'and record.square == square)
    assert(not Heavy.placed(record) and not Heavy.restoredRoot(record), 'root proof preceded earned drop')
    local world = drop()
    assert(Heavy.placed(record) == item and not Heavy.resolveFloor(record), 'world earning required a synthetic UI floor')
    refresh();local found, source, resolved = Heavy.resolveFloor(record)
    assert(found == item and source == floor and resolved == world)
    pickup();assert(Heavy.restoredRoot(record) == item and not Heavy.placed(record) and not Heavy.resolveFloor(record))
end
-- Every refusal leaves the model untouched; the adapter never manufactures an effect.
for _, mutation in ipairs({'world-replaced', 'world-missing', 'duplicate-id', 'floor-stale', 'foreign-floor', 'wrong-type', 'wrong-id',
    'moved', 'actor-replaced', 'root-replaced', 'root-duplicate', 'safehouse', 'access', 'capacity', 'acceptance', 'removal',
    'item-world', 'world-square', 'world-components', 'back-replacement', 'global'}) do
    local item, root, floor, square, drop, refresh = fixture()
    local record = assert(Heavy.capture(player));local world = drop();refresh()
    assert(Heavy.placed(record) == item)
    local restore
    if mutation == 'world-replaced'then drop();refresh()
    elseif mutation == 'world-missing'then square.worlds = values();square.objects = values()
    elseif mutation == 'duplicate-id'then local copy = {getID = function()return item.id end };square.worlds[2] = {class = 'IsoWorldInventoryObject', getItem = function()return copy end }
    elseif mutation == 'floor-stale'then floor.items = values()
    elseif mutation == 'foreign-floor'then ISInventoryPage.floorContainer[1] = {}
    elseif mutation == 'wrong-type'then item.fullType = 'Base.Other'
    elseif mutation == 'wrong-id'then item.id = 43
    elseif mutation == 'moved'then player.x = player.x+.01
    elseif mutation == 'actor-replaced'then player = {}
    elseif mutation == 'root-replaced'then player.root = {}
    elseif mutation == 'root-duplicate'then root.items = values(item)
    elseif mutation == 'safehouse'then allow = false
    elseif mutation == 'access'then player.canAccessContainer = function()return false end
    elseif mutation == 'capacity'then root.hasRoomFor = function()return false end
    elseif mutation == 'acceptance'then root.isItemAllowed = function()return false end
    elseif mutation == 'removal'then floor.isRemoveItemAllowed = function()return false end
    elseif mutation == 'item-world'then item.world = {}
    elseif mutation == 'world-square'then world.square = {}
    elseif mutation == 'world-components'then world.hasComponents = function()return true end
    elseif mutation == 'back-replacement'then player.back = {hasTag = function()return true end }
    elseif mutation == 'global'then local previous = getCell;getCell = function()return currentCell end ;restore = function()getCell = previous end end
    assert(not Heavy.resolveFloor(record), 'unsafe floor admitted: '..mutation)
    if restore then restore() end
end
    for _, mutation in ipairs({'generator-name', 'generator-tag', 'activation', 'attached', 'wearable', 'replacement', 'components', 'single-hand', 'not-mandatory', 'back-replacement'}) do
    local item = fixture()
    if mutation == 'generator-name'then item.fullType = 'Base.Generator'
    elseif mutation == 'generator-tag'then item.tag = ItemTag.GENERATOR
    elseif mutation == 'activation'then item.canBeActivated = function()return true end
    elseif mutation == 'attached'then item.getAttachedSlot = function()return 0 end
    elseif mutation == 'wearable'then item.tag = ItemTag.WEARABLE
    elseif mutation == 'replacement'then item.tag = ItemTag.REPLACE_PRIMARY
    elseif mutation == 'components'then item.hasComponents = function()return true end
    elseif mutation == 'single-hand'then player.secondary = nil
    elseif mutation == 'not-mandatory'then item.isRequiresEquippedBothHands = function()return false end end
    if mutation == 'back-replacement'then player.back = {hasTag = function()return true end } end
    assert(not Heavy.capture(player), 'unsupported heavy admitted: '..mutation)
end
do
    local item, root, floor, square, drop, refresh = fixture()
    local function extra(id)
        return {class = 'ComboItem', getID = function()return id end }
    end
    for id = 1000, 1300 do root.items[#root.items+1] = extra(id) end
    local record = assert(Heavy.capture(player), 'ordinary larger inventory was arbitrarily excluded')
    drop();refresh()
    for id = 1000, 1300 do
        local value = extra(id)
        floor.items[#floor.items+1] = value
        square.worlds[#square.worlds+1] = {class = 'IsoWorldInventoryObject', getItem = function()return value end }
    end
    assert(Heavy.resolveFloor(record) == item, 'ordinary larger world/floor view was arbitrarily excluded')
end
do
    local item, root, floor, square, drop, refresh, pickup = fixture()
    local record = assert(Heavy.capture(player));drop();refresh();assert(Heavy.placed(record));pickup()
    square.worlds = values({class = 'IsoWorldInventoryObject', getItem = function()return item end })
    assert(not Heavy.restoredRoot(record), 'inventory plus same-ID world representation treated as restored')
end
do
    local item, root, floor, square, drop, refresh, pickup = fixture()
    local record = assert(Heavy.capture(player));multiplayer = true
    local replacement = {};for key, value in pairs(item) do replacement[key] = value end
    drop(replacement);refresh();assert(Heavy.placed(record) == replacement and Heavy.resolveFloor(record) == replacement,
        'Host canonical item replica refused')
    pickup();assert(Heavy.restoredRoot(record) == replacement, 'Host root replica lost exact-ID proof')
    record.id = 123;assert(not Heavy.restoredRoot(record), 'mutated record retained identity')
end
print('PASS ordinary heavy drop identity, canonical Host replicas, latched world identity, access and duplicate refusals')

-- Run installed B42 Lua unchanged. The direct heavy action does not implement
-- the world-removal branch; the transfer action does. These are SP effect
-- doubles and do not establish live Host transport or server authority.
if NativeActionRoot then
    local function native(path)
        local file = assert(io.open(NativeActionRoot..'/'..path))
        local text = file:read('*a')
        file:close()
        return assert(loadstring(text, '@media/lua/'..path))()
    end
    require = function() end
    native('shared/ISBaseObject.lua')
    native('shared/TimedActions/ISBaseTimedAction.lua')
    native('shared/TimedActions/ISEquipHeavyItem.lua')
    native('shared/TimedActions/ISTransferAction.lua')
    native('shared/TimedActions/ISEquipWeaponAction.lua')
    isServer = function()return false end
    ItemContainer = {chainContainsContainingItem = function()return false end }
    DesignationZoneAnimal = {removeItemFromGround = function() end }
    sendRemoveItemFromContainer = function() end
    sendAddItemToContainer = function() end
    sendEquip = function() end
    triggerEvent = function() end
    getPlayerHotbar = function() end
    getPlayerInventory = function()return {refreshBackpacks = function() end } end
    local item, root, floor, square, drop, refresh, pickup = fixture()
    function root:AddItem(value)self.items = values(value);value.container = self end
    function floor:DoRemoveItem(value)self.items = values();value.container = nil end
    function player:setPrimaryHandItem(value)self.primary = value end
    function player:setSecondaryHandItem(value)self.secondary = value end
    function player:isTimedActionInstant()return false end
    function player:isEquippedClothing()return false end
    function item:getName()return 'Stone Anvil' end
    function item:getCurrentUsesFloat()return 1 end
    getText = function(key)return key end
    local world = drop();refresh()
    local action = ISEquipHeavyItem:new(player, item)
    assert(action:complete() and root.items[1] == item and square.worlds[1] == world and item.world == world,
        'native floor-heavy action unexpectedly removed its world representation')
    local record
    pickup();player.primary, player.secondary = item, item
    record = assert(Heavy.capture(player))
    world = drop();refresh();assert(Heavy.placed(record))
    local removals = 0
    function square:transmitRemoveItemFromSquare(value)assert(value == world);removals = removals+1 end
    function square:removeWorldObject(value)assert(value == world);self.worlds = values();self.objects = values() end
    function item:setWorldItem(value)self.world = value end
    assert(ISTransferAction:transferItem(player, item, floor, root) == item)
    assert(removals == 1 and Heavy.restoredRoot(record) == item and item.world == nil,
        'native transfer failed to conserve exact heavy identity and remove world representation')
    local equip = ISEquipWeaponAction:new(player, item, 50, true, true, false)
    assert(equip:complete() and player.primary == item and player.secondary == item and Heavy.restoredRoot(record) == item,
        'native carried-heavy equip failed to restore both hands after the real transfer')
    print('PASS installed native SP floor transfer removes the world item; direct floor-heavy equip does not')
    if TestCoverage then TestCoverage('native-heavy-transfer', 'passed') end
elseif TestCoverage then
    TestCoverage('native-heavy-transfer', 'skipped', 'Native heavy transfer requires the installed game action sources.')
end
