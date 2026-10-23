PZSurvivorToolkit = PZSurvivorToolkit or {}
local Retention = {}
PZSurvivorToolkit.ItemRetention = Retention
Retention.FIELD = "pzstRetained"
Retention.MODULE = "PZSurvivorToolkitRetention"
Retention.MAX_ITEMS = 128

function Retention.isEnabled() return true end

function Retention.isRetained(item)
    if not item or not item:hasModData() then return false end
    local data = item:getModData()
    return data[Retention.FIELD] == true or data.ocStuck == true
end

-- Saved OC flags are read in place; the first authoritative edit migrates them.
function Retention.apply(item, value)
    local data = item:getModData()
    data[Retention.FIELD] = value and true or nil
    data.ocStuck = nil
end

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

function Retention.locate(item, player)
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
function Retention.resolve(player, locator)
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

return Retention
