if isClient() then return end
local Retention = require "PZSurvivorToolkit/ItemRetention"
local requests = setmetatable({}, {__mode="k"})

local function integer(value, limit)
    return type(value) == "number" and value == math.floor(value) and math.abs(value) <= limit
end
local fields = {id=true, inv=true, x=true, y=true, z=true, vehicle=true, part=true}
local function validLocator(locator)
    if type(locator) ~= "table" or not integer(locator.id, 2147483647) then return false end
    local count = 0
    for key in pairs(locator) do
        count = count + 1
        if count > 7 or not fields[key] then return false end
    end
    if locator.inv == true then
        return locator.x == nil and locator.y == nil and locator.z == nil
            and locator.vehicle == nil and locator.part == nil
    end
    if locator.inv ~= nil or not integer(locator.x, 10000000) or not integer(locator.y, 10000000)
        or not integer(locator.z, 32) then return false end
    if locator.vehicle ~= nil then
        return integer(locator.vehicle, 32767) and integer(locator.part, 1024) and locator.part >= 0
    end
    return locator.part == nil
end

local function sameLocation(item, player, locator)
    local actual = Retention.locate(item, player)
    if not actual then return false end
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

function Retention.applyRequest(player, args)
    if not player or player:isDead() or not player:getCurrentSquare() or type(args) ~= "table"
        or not integer(args.request, 2147483647) or args.request < 1
        or type(args.retained) ~= "boolean" or type(args.items) ~= "table" then return end
    local count = 0
    for index, locator in pairs(args.items) do
        count = count + 1
        if count > Retention.MAX_ITEMS or not integer(index, Retention.MAX_ITEMS)
            or index < 1 or not validLocator(locator) then return end
    end
    for index = 1, count do if args.items[index] == nil then return end end
    if count == 0 then return end
    -- Native commands are connection-bound to this actor. The high-water mark
    -- additionally prevents a delayed/repeated old set from undoing a newer set.
    if args.request <= (requests[player] or 0) then return end
    requests[player] = args.request
    local accepted, seen = {}, {}
    for _, locator in ipairs(args.items) do
        local ok, item, root, square, part = pcall(Retention.resolve, player, locator)
        if ok and item and not seen[item] and (not square or
            square:getX() == locator.x and square:getY() == locator.y and square:getZ() == locator.z) then
            seen[item] = true
            local located, exact = pcall(sameLocation, item, player, locator)
            local accessible, allowed = pcall(canAccess, player, item, root, square, part)
            if located and exact and accessible and allowed then
                Retention.apply(item, args.retained)
                accepted[#accepted + 1] = locator
                -- Native ContainerID sync preserves the rest of the item ModData.
                if item:getContainer() then syncItemModData(player, item) end
            end
        end
    end
    if isServer() then
        -- This narrow state packet also covers loose world items (no native
        -- ContainerID) and gives owner/observer clients one cache invalidation.
        if #accepted > 0 then
            sendServerCommand(Retention.MODULE, "State", {owner=player:getOnlineID(),
                retained=args.retained, items=accepted})
        end
        sendServerCommand(player, Retention.MODULE, "Result", {request=args.request,
            accepted=#accepted, rejected=count-#accepted})
    end
    return #accepted
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module == Retention.MODULE and command == "Set" then Retention.applyRequest(player, args) end
end)
return Retention
