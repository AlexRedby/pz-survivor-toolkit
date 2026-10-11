require "PZSurvivorToolkit/Settings"

local Resolver = {}
PZSurvivorToolkit.TVDeviceResolver = Resolver

function Resolver.fullType(device)
    if not device then return end
    if instanceof(device, "InventoryItem") then return device:getFullType() end
    if instanceof(device, "VehiclePart") then
        local item = device:getInventoryItem()
        return item and item:getFullType()
    end
    if not instanceof(device, "IsoObject") then return end
    local modData = device:getModData()
    local id = modData and modData.RadioItemID
    local square = device:getSquare()
    if id and square then
        for _, method in ipairs({"getWorldObjects", "getObjects"}) do
            local objects = square[method](square)
            if objects then
                for i = 0, objects:size() - 1 do
                    local object = objects:get(i)
                    if instanceof(object, "IsoWorldInventoryObject") then
                        local item = object:getItem()
                        if item and item:getID() == id then return item:getFullType() end
                    end
                end
            end
        end
    end
    local properties = device:getProperties()
    local item = properties and properties:get("CustomItem")
    if item then return item:find(".", 1, true) and item or "Base." .. item end
    if instanceof(device, "IsoTelevision") then return "Base.TvBlack" end
    if instanceof(device, "IsoRadio") then return "Base.RadioMakeShift" end
end

function Resolver.call(device, fn, ...)
    local fullType = Resolver.fullType(device)
    local data = fullType and device:getDeviceData()
    if not fullType or not data then return fn(...) end
    local original, name = getItemNameFromFullType, data:getDeviceName()
    -- Upstream only compares item names in these calls; use identity, then restore translations.
    getItemNameFromFullType = function(itemType)
        if itemType == fullType then return name end
    end
    local ok, result = pcall(fn, ...)
    getItemNameFromFullType = original
    if not ok then error(result) end
    return result
end

return Resolver
