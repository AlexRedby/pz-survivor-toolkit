local F = {}
F.types = {'Base.Apple','Base.Bandage','Base.Nails','Base.Screwdriver','Base.Screwdriver','Base.Screwdriver_Improvised'}

function F.quote(value)
    return '"'..tostring(value):gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n'):gsub('\r','\\r')..'"'
end

function F.signature(container)
    local items, result = container:getItems(), {}
    for index=0,items:size()-1 do
        local item=items:get(index)
        result[#result+1]={id=item:getID(),fullType=item:getFullType()}
    end
    table.sort(result,function(a,b) return a.id<b.id end)
    local values={}
    for _, item in ipairs(result) do values[#values+1]=tostring(item.id)..':'..item.fullType end
    return table.concat(values,'|')
end

local function clear(x,y,clearance)
    local radius=math.max(6,clearance)
    for dx=-radius,radius do for dy=-radius,radius do
        local square=getCell():getGridSquare(x+dx,y+dy,0)
        if math.abs(dx)<=clearance and math.abs(dy)<=clearance and
            (not square or not square:isOutside() or not square:isFree(false)) then return false end
        if square then
            local objects=square:getMovingObjects()
            for index=0,objects:size()-1 do
                if instanceof(objects:get(index),'BaseVehicle') then return false end
            end
        end
    end end
    return true
end

function F.spawn(player, deferItems, clearance)
    clearance=clearance or 3
    local px,py=math.floor(player:getX()),math.floor(player:getY())
    local spot
    for radius=4,24 do
        for dx=-radius,radius do for dy=-radius,radius do
            if not spot and (math.abs(dx)==radius or math.abs(dy)==radius) and clear(px+dx,py+dy,clearance) then
                spot=getCell():getGridSquare(px+dx,py+dy,0)
            end
        end end
        if spot then break end
    end
    assert(spot,'No clear truck spawn square')
    local vehicle=assert(addVehicleDebug('Base.PickUpVan',IsoDirections.N,nil,spot))
    assert(vehicle:getSquare(),'Native truck placement was rejected')
    if isServer() then assert(vehicle:getId()>=0,'Truck has no network ID') end
    local part=assert(vehicle:getPartById('TruckBed'),'Truck has no TruckBed')
    local container=assert(part:getItemContainer(),'TruckBed has no item container')
    container:setExplored(true)
    local door=vehicle:getPartById('TrunkDoor')
    if door and door:getDoor() then
        door:getDoor():setLocked(false);door:getDoor():setOpen(true)
        if isServer() then vehicle:transmitPartDoor(door) end
    end
    container:clear()
    for _, fullType in ipairs(F.types) do assert(container:AddItem(fullType),'Missing fixture item '..fullType) end
    assert(container:getItems():size()==#F.types)
    if isServer() and not deferItems then sendItemsInContainer(vehicle,container) end
    print('[PIN_ITEMS] SPAWN script='..vehicle:getScriptName()..' id='..vehicle:getId()..' container='..container:getType())
    return vehicle,container
end

return F
