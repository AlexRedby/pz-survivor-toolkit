-- Exact ordinary mandatory-grip drop identity. This module only reads facts:
-- it grants no queue/edit/transport rights and never creates a floor container.
-- The caller must earn the native drop, transfer and equip outcomes separately.
-- Generators become IsoGenerator on drop and require a distinct output contract.
local Proof = require'PZSurvivorToolkit/SourceProof'
local Toolkit = PZSurvivorToolkit
local Heavy = {}
Toolkit.ActionQueueHeavyPickup = Heavy
local captureBindings, own = Proof.captureBindings, Proof.own
local classify, instance, cellOf, playerOf, client = getClassSimpleName, instanceof, getCell, getSpecificPlayer, isClient
local sealKey, dispatch, dispatched = {}, nil, nil

local function integer(n, limit)
    return type(n) == 'number' and n == n and n%1 == 0 and math.abs(n) <= limit
end

local function sizeOf(values)
    local name = values and classify(values)
    if name ~= 'ArrayList' and name ~= 'PZArrayList' then return end
    local size = values:size()
    if integer(size, 2147483647) and size >= 0 then return size end
end

local function java(callback)
    if type(callback) ~= 'function' then return false end
    local ok, name = pcall(classify, callback)
    return ok and (name == 'LuaJavaInvoker' or name == 'MultiLuaJavaInvoker')
end

local function list(values, item, id)
    local size = sizeOf(values)
    if not size then return false end
    local refs, ids = 0, 0
    for index = 0, size-1 do
        local value = values:get(index)
        if value == item then refs = refs+1 end
        if id ~= nil then
            if not instance(value, 'InventoryItem') then return false end
            if value:getID() == id then ids = ids+1 end
        end
    end
    return refs == 1 and (id == nil or ids == 1)
end

local function anchored(square)
    if not square or classify(square) ~= 'IsoGridSquare' then return false end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local cell = cellOf()
    return integer(x, 10000000) and integer(y, 10000000) and integer(z, 32)
         and cell ~= nil and cell:getGridSquare(x, y, z) == square
end

local function ordinary(item)
    return item and instance(item, 'InventoryItem') and classify(item) == 'ComboItem' and not item:hasComponents()
         and item:isForceDropHeavyItem() == true and item:isRequiresEquippedBothHands() == true
         and item:isHumanCorpse() == false and item:canBeActivated() == false and item:getAttachedSlot() == -1
         and item:getIsCraftingConsumed() == false and item:hasTag(ItemTag.GENERATOR) == false
         and item:hasTag(ItemTag.WEARABLE) == false and item:hasTag(ItemTag.REPLACE_PRIMARY) == false
         and type(item:getFullType()) == 'string' and not item:getFullType():find('.Generator', 1, true)
end

local function actorValid(s)
    local actor = s.actor
    if not s.watch() or classify(actor) ~= 'IsoPlayer' or not instance(actor, 'IsoPlayer') then return false end
    local back = actor:getClothingItem_Back()
    return actor:isLocalPlayer()
         and playerOf(s.playerNum) == actor and actor:getPlayerNum() == s.playerNum and not actor:isDead() and not actor:isAsleep()
         and actor:getOnlineID() == s.onlineId and actor:getInventory() == s.root and classify(s.root) == 'ItemContainer'
         and actor:getCurrentSquare() == s.square and anchored(s.square)
         and actor:getX() == s.actorX and actor:getY() == s.actorY and actor:getZ() == s.actorZ
         and not (back and back:hasTag(ItemTag.REPLACE_PRIMARY))
end

local function exact(s, item)
    return ordinary(item) and item:getID() == s.id and item:getFullType() == s.fullType
         and (item == s.item or client()) and s.watch()
end

local function state(record)
    if type(record) ~= 'table' or getmetatable(record) ~= nil then return end
    dispatch, dispatched = record, nil
    local seal = own(record, sealKey)
    if type(seal) == 'function' then seal() end
    local s = dispatched
    dispatch, dispatched = nil, nil
    if not s then return end
    for key, value in pairs(record) do
        if key ~= sealKey and s[key] ~= value then return end
    end
    for _, key in ipairs({'actor', 'root', 'item', 'id', 'fullType', 'square', 'x', 'y', 'z'}) do
        if record[key] ~= s[key] then return end
    end
    if actorValid(s) then return s end
end

function Heavy.capture(actor)
    if PZSurvivorToolkit ~= Toolkit or Toolkit.ActionQueueHeavyPickup ~= Heavy
         or Proof.captureBindings ~= captureBindings or Proof.own ~= own
         or getClassSimpleName ~= classify or instanceof ~= instance or getCell ~= cellOf
         or getSpecificPlayer ~= playerOf or isClient ~= client then return end
    if not java(classify) or not java(instance) or not java(cellOf) or not java(playerOf) or not java(client)
         or not instance(actor, 'IsoPlayer') or classify(actor) ~= 'IsoPlayer' then return end
    local tags, safehouse = ItemTag, SafeHouse
    if not tags or not tags.GENERATOR or not tags.WEARABLE or not tags.REPLACE_PRIMARY
         or not safehouse or not java(safehouse.isSafehouseAllowLoot) then return end
    local watch = captureBindings({
        {owner = _G, keys = {'PZSurvivorToolkit', 'getClassSimpleName', 'instanceof', 'getCell', 'getSpecificPlayer', 'isClient', 'ItemTag', 'SafeHouse'}},
        {owner = Toolkit, keys = {'ActionQueueHeavyPickup'}}, {owner = Heavy, exact = true},
        {owner = Proof, keys = {'captureBindings', 'own'}},
        {owner = tags, keys = {'GENERATOR', 'WEARABLE', 'REPLACE_PRIMARY'}},
        {owner = safehouse, keys = {'isSafehouseAllowLoot'}},
    })
    if not watch then return end
    local item, root, square = actor:getPrimaryHandItem(), actor:getInventory(), actor:getCurrentSquare()
    if not ordinary(item) or actor:getSecondaryHandItem() ~= item or not anchored(square)
         or not root or classify(root) ~= 'ItemContainer' or item:getContainer() ~= root or item:getWorldItem() ~= nil
         or root:getItemWithID(item:getID()) ~= item or not list(root:getItems(), item, item:getID()) then return end
    local id, fullType = item:getID(), item:getFullType()
    if not integer(id, 2147483647) or id == -1 or fullType == '' then return end
    local s = {actor = actor, root = root, item = item, id = id, fullType = fullType, watch = watch,
        square = square, x = square:getX(), y = square:getY(), z = square:getZ(), playerNum = actor:getPlayerNum(), onlineId = actor:getOnlineID(),
        actorX = actor:getX(), actorY = actor:getY(), actorZ = actor:getZ(), safehouse = safehouse}
    if not integer(s.playerNum, 3) or s.playerNum<0 or not actorValid(s) then return end
    local record = {actor = actor, root = root, item = item, id = id, fullType = fullType, square = square, x = s.x, y = s.y, z = s.z}
    record[sealKey] = function()
        if dispatch == record then dispatched = s end
    end
    return record
end

local function placed(s)
    local objects = s.square:getWorldObjects()
    local count = sizeOf(objects)
    if not count then return end
    local found, world
    for index = 0, count-1 do
        local candidate = objects:get(index)
        if not candidate or classify(candidate) ~= 'IsoWorldInventoryObject' then return end
        local item = candidate:getItem()
        if item and item:getID() == s.id then
            if found then return end
            found, world = item, candidate
        end
    end
    if not found or not exact(s, found) or world:hasComponents() or world:getSquare() ~= s.square
         or s.world and s.world ~= world or found:getWorldItem() ~= world or not list(s.square:getObjects(), world)
         or not list(objects, world)
         or s.root:getItemWithID(s.id) ~= nil or s.actor:isEquipped(found)
         or s.safehouse.isSafehouseAllowLoot(s.square, s.actor) ~= true
         or not actorValid(s) then return end
    -- Bind once, including before the floor UI has seen the native drop.
    s.world = world
    return found, world
end

function Heavy.placed(record)
    local s = state(record)
    if not s then return end
    return placed(s)
end

function Heavy.resolveFloor(record)
    local s = state(record)
    if not s then return end
    local found, world = placed(s)
    if not found then return end
    local page = ISInventoryPage
    local caches = type(page) == 'table' and own(page, 'floorContainer')
    local floor = type(caches) == 'table' and getmetatable(caches) == nil and own(caches, s.playerNum+1)
    if not floor or classify(floor) ~= 'ItemContainer' or floor == s.root or floor:getType() ~= 'floor'
         or floor:getParent() ~= nil or floor:getContainingItem() ~= nil or floor:getVehiclePart() ~= nil
         or floor:getAcceptItemFunction() ~= nil or floor:getOnlyAcceptCategory() ~= nil
         or found:getContainer() ~= floor or not list(floor:getItems(), found, s.id) or floor:getItemWithID(s.id) ~= found
         or not s.actor:canAccessContainer(floor)
         or not floor:isExistYet() or not s.root:isExistYet()
         or not floor:isRemoveItemAllowed(found) or not s.root:isItemAllowed(found)
         or not s.root:hasRoomFor(s.actor, found) or s.root:isInside(found)
         or not actorValid(s) then return end
    return found, floor, world
end

function Heavy.restoredRoot(record)
    local s = state(record)
    if not s or not s.world then return end
    local item = s.root:getItemWithID(s.id)
    if not item or not exact(s, item) or item:getContainer() ~= s.root or item:getWorldItem() ~= nil
         or not list(s.root:getItems(), item, s.id) then return end
    local objects = s.square:getWorldObjects()
    local size = sizeOf(objects)
    if not size then return end
    for index = 0, size-1 do
        local object = objects:get(index)
        if not object or classify(object) ~= 'IsoWorldInventoryObject' then return end
        local worldItem = object:getItem()
        if worldItem and worldItem:getID() == s.id then return end
    end
    if actorValid(s) then return item end
end
return Heavy
