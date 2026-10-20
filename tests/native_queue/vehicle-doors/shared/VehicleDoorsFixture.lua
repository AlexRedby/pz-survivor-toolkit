local F = {}
function F.prepare(player)
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    local square
    for radius = 4, 22 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local candidate = getCell():getGridSquare(px + dx, py + dy, 0)
                if candidate and candidate:isOutside() and candidate:isFree(false) and not candidate:getVehicleContainer() then
                    local clear = true
                    for x = -2, 2 do for y = -3, 3 do
                        local nearby = getCell():getGridSquare(px + dx + x, py + dy + y, 0)
                        if not nearby or not nearby:isOutside() or not nearby:isFree(false) or nearby:getVehicleContainer() then clear = false end
                    end end
                    if clear then square = candidate; break end
                end
            end
            if square then break end
        end
        if square then break end
    end
    local vehicle = assert(addVehicleDebug('Base.CarNormal', IsoDirections.N, nil, assert(square)))
    assert(vehicle:getSquare())
    F.vehicle = vehicle
    for _, id in ipairs({'DoorFrontLeft', 'DoorFrontRight'}) do
        local part = assert(vehicle:getPartById(id))
        assert(part:getInventoryItem() and part:getDoor())
        part:getDoor():setLocked(false)
        part:getDoor():setOpen(true)
        if isServer() then vehicle:transmitPartDoor(part) end
    end
    print('[VEHICLE_DOORS] SPAWN id=' .. vehicle:getId())
    return vehicle:getId()
end
function F.verify(vehicle, player)
    assert(vehicle and vehicle == player:getVehicle() and vehicle:getSeat(player) == 0)
    assert(not vehicle:getPartById('DoorFrontLeft'):getDoor():isOpen())
    assert(vehicle:getPartById('DoorFrontRight'):getDoor():isOpen(), 'Unrelated passenger door changed')
    print('[VEHICLE_DOORS] AUTHORITY closed-driver-only id=' .. vehicle:getId())
end
return F
