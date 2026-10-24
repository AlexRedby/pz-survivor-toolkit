-- Shared exact item identity, root and access admission for authoritative item edits.
local Access = {}

local function squareOf(container)
    local part = container and container:getVehiclePart()
    if part then return part:getVehicle():getCurrentSquare(), part end
    local parent = container and container:getParent()
    if parent and parent.getSquare then return parent:getSquare() end
    local holder = container and container:getContainingItem()
    local world = holder and holder:getWorldItem()
    if world then return world:getSquare() end
    return container and container:getSourceGrid()
end

function Access.locate(item, player)
    local container = item:getContainer()
    if container and container:isInCharacterInventory(player) then return {id=item:getID(), inv=true} end
    local outer = item:getOutermostContainer() or container
    local square, part = squareOf(outer)
    local world = item:getWorldItem()
    if not square and world then square = world:getSquare() end
    if not square then return end
    local locator = {id=item:getID(), x=square:getX(), y=square:getY(), z=square:getZ()}
    if part then locator.vehicle, locator.part = part:getVehicle():getId(), part:getIndex() end
    return locator
end

local function findInItem(item, id)
    if item:getID() == id then return item end
    if instanceof(item, "InventoryContainer") then return item:getInventory():getItemWithIDRecursiv(id) end
end

-- Resolve actual game objects; the server separately admits the exact item/root.
function Access.resolve(player, locator)
    if locator.inv then
        local root = player:getInventory()
        return root:getItemWithIDRecursiv(locator.id), root
    end
    if locator.vehicle ~= nil then
        local vehicle = getVehicleById(locator.vehicle)
        local part = vehicle and vehicle:getPartByIndex(locator.part)
        local root = part and part:getItemContainer()
        return root and root:getItemWithIDRecursiv(locator.id), root, vehicle and vehicle:getCurrentSquare(), part
    end
    local square = getCell():getGridSquare(locator.x, locator.y, locator.z)
    if not square then return end
    local objects = square:getObjects()
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if instanceof(object, "IsoWorldInventoryObject") then
            local item = object:getItem()
            local found = item and findInItem(item, locator.id)
            if found then
                local root
                if found == item then root = item:getContainer() else root = item:getInventory() end
                return found, root, square
            end
        else
            for ci = 0, object:getContainerCount() - 1 do
                local root = object:getContainerByIndex(ci)
                local found = root:getItemWithIDRecursiv(locator.id)
                if found then return found, root, square end
            end
        end
    end
    local bodies = square:getStaticMovingObjects()
    for index = 0, bodies:size() - 1 do
        local body = bodies:get(index)
        local root = body.getContainer and body:getContainer()
        local found = root and root:getItemWithIDRecursiv(locator.id)
        if found then return found, root, square end
    end
end


function Access.integer(value, limit)
    return type(value) == "number" and value == math.floor(value) and math.abs(value) <= limit
end
local fields = {id=true, inv=true, x=true, y=true, z=true, vehicle=true, part=true}
function Access.validLocator(locator)
    if type(locator) ~= "table" or not Access.integer(locator.id, 2147483647) then return false end
    local count = 0
    for key in pairs(locator) do
        count = count + 1
        if count > 7 or not fields[key] then return false end
    end
    if locator.inv == true then
        return locator.x == nil and locator.y == nil and locator.z == nil
            and locator.vehicle == nil and locator.part == nil
    end
    if locator.inv ~= nil or not Access.integer(locator.x, 10000000) or not Access.integer(locator.y, 10000000)
        or not Access.integer(locator.z, 32) then return false end
    if locator.vehicle ~= nil then
        return Access.integer(locator.vehicle, 32767) and Access.integer(locator.part, 1024) and locator.part >= 0
    end
    return locator.part == nil
end

function Access.sameLocation(item, player, locator)
    local actual = Access.locate(item, player)
    if not actual then return false end
    -- A replicated vehicle can occupy a different grid square on each peer.
    -- Its exact item/vehicle/part identity is stable; admission below uses the
    -- live server square and native container access, never this position hint.
    if actual.vehicle ~= nil and locator.vehicle ~= nil then
        return actual.id == locator.id and actual.inv == locator.inv
            and actual.vehicle == locator.vehicle and actual.part == locator.part
    end
    for field in pairs(fields) do if actual[field] ~= locator[field] then return false end end
    return true
end

local function containerAccess(player, source, root)
    local container, depth = source, 0
    while container do
        depth = depth + 1
        if depth > 32 or not player:canAccessContainer(container) then return false end
        if container == root then return true end
        local holder = container:getContainingItem()
        container = holder and holder:getContainer()
    end
    return false
end

local function canAccess(player, item, root, square, part)
    local source = item:getContainer()
    if root and root:isInCharacterInventory(player) then
        return source and source:isInCharacterInventory(player) and containerAccess(player, source, root)
    end
    local current = player:getCurrentSquare()
    if not square or not current or current:getZ() ~= square:getZ() then return false end
    local distance = part and 8 or 1
    if math.abs(current:getX() - square:getX()) > distance
        or math.abs(current:getY() - square:getY()) > distance then return false end
    if part then
        if part:getItemContainer() ~= root or not part:getVehicle():canAccessContainer(part:getIndex(), player) then return false end
    elseif current ~= square and current:isBlockedTo(square) then return false end
    if isServer() and (not SafeHouse or not SafeHouse.isSafehouseAllowLoot
        or SafeHouse.isSafehouseAllowLoot(square, player) ~= true) then return false end
    -- Check every containing bag too; an accessible outer crate must not unlock
    -- a mod's protected nested container. Bound malformed/cyclic ancestry.
    if root then return containerAccess(player, source, root) end
    return not source and item:getWorldItem() and item:getWorldItem():getSquare() == square
end

function Access.admit(player, locator)
    if not player or player:isDead() or not player:getCurrentSquare() or not Access.validLocator(locator) then return end
    local ok, item, root, square, part = pcall(Access.resolve, player, locator)
    if not ok or not item or square and not part and (square:getX() ~= locator.x
        or square:getY() ~= locator.y or square:getZ() ~= locator.z) then return end
    local located, exact = pcall(Access.sameLocation, item, player, locator)
    local accessible, allowed = pcall(canAccess, player, item, root, square, part)
    if located and exact and accessible and allowed then return item end
end

return Access
