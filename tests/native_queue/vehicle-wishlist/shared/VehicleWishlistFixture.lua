local F = {}
local function clear(x,y)
    for dx=-6,6 do for dy=-6,6 do
        local square=getCell():getGridSquare(x+dx,y+dy,0)
        if math.abs(dx)<=3 and math.abs(dy)<=3 and
            (not square or not square:isOutside() or not square:isFree(false)) then return false end
        if square then
            local objects=square:getMovingObjects()
            for i=0,objects:size()-1 do
                if instanceof(objects:get(i),'BaseVehicle') then return false end
            end
        end
    end end
    -- addToWorld is deferred; reserve this fixture's earlier spawns too.
    for _,vehicle in ipairs(F.vehicles or {}) do
        if math.abs(vehicle:getX()-x)<7 and math.abs(vehicle:getY()-y)<7 then return false end
    end
    return true
end
local function position(player)
    local px,py=math.floor(player:getX()),math.floor(player:getY())
    for radius=3,25 do
        for dx=-radius,radius do for dy=-radius,radius do
            if (math.abs(dx)==radius or math.abs(dy)==radius) and clear(px+dx,py+dy) then
                return getCell():getGridSquare(px+dx,py+dy,0)
            end
        end end
    end
    error('No clear exterior 7x7 vehicle fixture position')
end
function F.prepare(player)
    local ids = {}
    F.vehicles = {}
    for i, name in ipairs({"Base.PickUpVan", "Base.PickUpVan", "Base.CarNormal", "Base.SportsCar"}) do
        local square = assert(position(player))
        local vehicle = assert(addVehicleDebug(name, IsoDirections.N, nil, square))
        assert(vehicle:getSquare(), 'Native vehicle spawn rejected: '..name)
        if isServer() then assert(vehicle:getId()>=0, 'Native spawn has no network ID') end
        print('[VEHICLE_WISHLIST] SPAWN '..name..' id='..vehicle:getId()..' square='..square:getX()..','..square:getY())
        local part = assert(vehicle:getPartById("TireFrontLeft"))
        local class = vehicle:getScript():getMechanicType()
        assert(class == (i <= 2 and 2 or (i == 3 and 1 or 3)))
        local item = i > 1 and instanceItem("Base.ModernTire" .. class) or nil
        if item then item:setCondition(80) end
        part:setInventoryItem(item)
        if isServer() then vehicle:transmitPartItem(part) end
        ids[i] = vehicle:getId()
        F.vehicles[i] = vehicle
    end
    return ids
end
return F
