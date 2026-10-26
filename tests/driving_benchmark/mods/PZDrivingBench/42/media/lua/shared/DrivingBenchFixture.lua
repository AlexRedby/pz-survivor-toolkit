local F = {MODULE="PZDrivingBench", START_X=10818, START_Y=10118}
local STORE = "PZDrivingBenchFixture"

function F.allowed()
    -- Steam invitations do not set GameClient.serverName; direct joins use a display label.
    -- Clients may request readiness; only this module's server/SP authority can create a car.
    if isClient() then return true end
    if isServer() then return getServerName() == F.MODULE end
    local world = getWorld() and getWorld():getWorld()
    return type(world) == "string" and world:match("^PZDrivingBench%-") ~= nil
end

local function failure(reason, retryable, record)
    return {status="error", reason=reason, retryable=retryable == true,
        x=record and record.x, y=record and record.y, z=record and record.z}
end

local function ownerKey(player)
    if isServer() then
        local name = player:getUsername()
        assert(type(name) == "string" and name ~= "", "Player username is not ready")
        return "user:" .. name
    end
    return "local:" .. tostring(player:getPlayerNum())
end

local function ownedVehicle(owner, record)
    local vehicles = getCell():getVehicles():iterator()
    while vehicles:hasNext() do
        local vehicle = vehicles:next()
        local tag = vehicle:getModData()[STORE]
        if tag and tag.owner == owner and (not record or type(record.sqlId) ~= "number"
            or record.sqlId < 1 or vehicle:getSqlId() == record.sqlId) then
            return vehicle
        end
    end
end

local function street(x, y)
    local square = getCell():getGridSquare(x, y, 0)
    if not square or not square:isOutside() or not square:isFree(false)
        or square:getVehicleContainer() then return end
    local floor = square:getFloor()
    local sprite = floor and floor:getSprite()
    local name = sprite and sprite:getName()
    if name and name:find("street", 1, true) then return square end
end

local function spawnSquare(player)
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    assert(math.abs(px-F.START_X) <= 100 and math.abs(py-F.START_Y) <= 100,
        "New benchmark drivers must start near 10818,10118,0")
    for radius = 2, 32, 2 do
        for dx = -radius, radius, 2 do
            for dy = -radius, radius, 2 do
                if math.abs(dx) == radius or math.abs(dy) == radius then
                    local x, y = px+dx, py+dy
                    for _, direction in ipairs({{0,1,"N",180},{1,0,"E",90}}) do
                        local clear = true
                        for ahead = -4, 4 do
                            for side = -2, 2 do
                                local tx = x + direction[1]*ahead + direction[2]*side
                                local ty = y + direction[2]*ahead + direction[1]*side
                                if not street(tx, ty) then clear = false; break end
                            end
                            if not clear then break end
                        end
                        if clear then return street(x,y), direction[3], direction[4] end
                    end
                end
            end
        end
    end
end

local function initialize(vehicle)
    vehicle:repair()
    local tank = assert(vehicle:getPartById("GasTank"), "Car has no GasTank")
    tank:setContainerContentAmount(tank:getContainerCapacity())
    vehicle:transmitPartModData(tank)
    vehicle:setAlarmed(false)
    vehicle:transmitAlarmed()
    local part = assert(vehicle:getPartById("DoorFrontLeft"), "Car has no driver door")
    local door = assert(part:getDoor(), "Driver door is missing")
    door:setLocked(false)
    door:setLockBroken(false)
    vehicle:transmitPartDoor(part)
end

local function prepare(player)
    local owner = ownerKey(player)
    local store = ModData.getOrCreate(STORE)
    store.players = store.players or {}
    local record = store.players[owner]
    local vehicle = ownedVehicle(owner, record)
    local reused = vehicle ~= nil
    if record and not vehicle then
        return failure("The existing benchmark car is not loaded; return to its saved position. No duplicate was created.", false, record)
    end
    if not vehicle then
        local square, direction, yaw = spawnSquare(player)
        if not square then return failure("No loaded, clear street footprint near the start; wait for map loading and retry.", true) end
        vehicle = assert(addVehicleDebug("Base.CarNormal", IsoDirections[direction], nil, square), "Vehicle creation failed")
        assert(vehicle:getSquare(), "Native vehicle placement was rejected")
        record = {owner=owner, sqlId=vehicle:getSqlId(), x=vehicle:getX(), y=vehicle:getY(), z=vehicle:getZ(), yaw=yaw}
        store.players[owner] = record
        vehicle:getModData()[STORE] = record
    elseif not record then
        record = vehicle:getModData()[STORE]
        store.players[owner] = record
    end
    if not record.initialized then
        -- Persist ownership before setup so a failed setup cannot create a second car.
        -- The native spawner randomizes yaw; setAngles uses degrees and an integer early-out.
        vehicle:setAngles(0,record.yaw+2,0)
        vehicle:setAngles(0,record.yaw,0)
        initialize(vehicle)
        record.initialized = true
    end
    if not record.keyGiven then
        local inventory = player:getInventory()
        if not inventory:haveThisKeyId(vehicle:getKeyId()) then
            local key = assert(vehicle:createVehicleKey(), "Vehicle key creation failed")
            inventory:AddItem(key)
            record.keyGiven = true
            if isServer() then sendAddItemToContainer(inventory, key) end
        end
        record.keyGiven = true
    end
    local id, sqlId = vehicle:getId(), vehicle:getSqlId()
    if type(sqlId) ~= "number" or sqlId < 1 then
        return failure("Vehicle database identity is not ready; retry shortly.", true, record)
    end
    record.sqlId = sqlId
    if isServer() and (type(id) ~= "number" or id < 0) then
        return failure("Vehicle network identity is not ready; retry shortly.", true, record)
    end
    player:getModData()[STORE] = {sqlId=sqlId, owner=owner, complete=true}
    return {status="ready", id=id, sqlId=sqlId, x=vehicle:getX(), y=vehicle:getY(), z=vehicle:getZ(),
        script="Base.CarNormal", reused=reused}
end

function F.prepare(player)
    if not F.allowed() or isClient() then return failure("This is not an isolated PZDrivingBench authority.", false) end
    if not player or player:isDead() or not player:getCurrentSquare() then
        return failure("The player and starting map are not ready.", true)
    end
    local ok, result = pcall(prepare, player)
    if ok then return result end
    print("[PZDrivingBench] prepare failed: " .. tostring(result))
    return failure(tostring(result), false)
end


-- Manual recovery only. Never repair on load, ticks or multiplayer requests.
function F.canRepair(player, vehicle)
    if isClient() or isServer() or not F.allowed() or not player or not vehicle then
        return false, "Repair is available only in the isolated single-player driving test.", false
    end
    local owner = ownerKey(player)
    local tag = vehicle:getModData()[STORE]
    local store = ModData.getOrCreate(STORE)
    local record = store.players and store.players[owner]
    if type(tag) ~= "table" or tag.owner ~= owner or type(record) ~= "table"
        or record.owner ~= owner or not record.initialized
        or type(record.sqlId) ~= "number" or record.sqlId < 1
        or tag.sqlId ~= record.sqlId or vehicle:getSqlId() ~= record.sqlId then
        return false, "This is not your registered benchmark car.", false
    end
    if player:isDead() or not player:getCurrentSquare() or not vehicle:getSquare() then
        return false, "The player and test car must be loaded and alive.", true
    end
    -- Re-evaluate the target on click: an old menu must not repair a remote car.
    local current = player:getVehicle() or player:getNearVehicle()
    if current ~= vehicle then return false, "Stand next to, or sit in, your test car.", true end
    if math.abs(vehicle:getCurrentSpeedKmHour()) >= 0.8 then
        return false, "Stop the test car before repairing it.", true
    end
    if not vehicle:getPartById("GasTank") then
        return false, "This wreck has no normal vehicle parts; repair cannot replace a burnt shell.", true
    end
    return true, nil, true
end

function F.repairVehicle(player, vehicle)
    local allowed, reason = F.canRepair(player, vehicle)
    if not allowed then return failure(reason, false) end
    local ok, problem = pcall(initialize, vehicle)
    if not ok then
        print("[PZDrivingBench] repair failed: " .. tostring(problem))
        return failure(tostring(problem), false)
    end
    print("[PZDrivingBench] REPAIRED sqlId=" .. tostring(vehicle:getSqlId()))
    return {status="repaired", sqlId=vehicle:getSqlId()}
end

return F
