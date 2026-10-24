local F = {}
function F.prepare(player)
    local px, py = math.floor(player:getX()), math.floor(player:getY())
    local square
    for radius = 4, 22 do
        for dx = -radius, radius do
            for dy = -radius, radius do
                local candidate = getCell():getGridSquare(px + dx, py + dy, 0)
                local clear = candidate ~= nil
                for x = -2, 2 do for y = -3, 3 do
                    local nearby = getCell():getGridSquare(px + dx + x, py + dy + y, 0)
                    if not nearby or not nearby:isOutside() or not nearby:isFree(false) or nearby:getVehicleContainer() then clear = false end
                end end
                if clear then square = candidate; break end
            end
            if square then break end
        end
        if square then break end
    end
    F.vehicle = assert(addVehicleDebug('Base.CarNormal', IsoDirections.N, nil, assert(square)))
    local door = assert(F.vehicle:getPartById('DoorFrontLeft'))
    door:getDoor():setLocked(false)
    door:getDoor():setOpen(true)
    F.vehicle:transmitPartDoor(door)
    print('[VEHICLE_DIAGNOSTICS] SPAWN id=' .. F.vehicle:getId())
    return F.vehicle:getId()
end
return F
