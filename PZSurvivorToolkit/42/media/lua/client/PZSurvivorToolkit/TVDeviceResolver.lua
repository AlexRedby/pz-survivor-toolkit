require "PZSurvivorToolkit/Settings"

local Resolver = {}
PZSurvivorToolkit.TVDeviceResolver = Resolver

local function boundItem(binding, device, square, id)
    if not binding or binding.device ~= device or binding.square ~= square or binding.id ~= id then return end
    local objects = square[binding.method](square)
    if objects ~= binding.objects or binding.index >= objects:size()
        or objects:get(binding.index) ~= binding.world then return end
    local item = binding.world:getItem()
    if item == binding.item and item:getID() == id then return item end
end

function Resolver.fullType(device, binding)
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
        local bound = boundItem(binding, device, square, id)
        if bound then return bound:getFullType(), binding end
        for _, method in ipairs({"getWorldObjects", "getObjects"}) do
            local objects = square[method](square)
            if objects then
                for i = 0, objects:size() - 1 do
                    local object = objects:get(i)
                    if instanceof(object, "IsoWorldInventoryObject") then
                        local item = object:getItem()
                        if item and item:getID() == id then
                            -- Square/reverse links can survive removal. Keep the exact live list
                            -- slot so reuse proves membership without another linear indexOf scan.
                            return item:getFullType(), {device = device, square = square, id = id,
                                method = method, objects = objects, index = i, world = object, item = item}
                        end
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

function Resolver.call(device, binding, fn, ...)
    local fullType, resolved = Resolver.fullType(device, binding)
    local data = fullType and device:getDeviceData()
    if not fullType or not data then return fn(...), nil, nil end
    local original, name = getItemNameFromFullType, data:getDeviceName()
    -- Upstream only compares item names in these calls; use identity, then restore translations.
    getItemNameFromFullType = function(itemType)
        if itemType == fullType then return name end
    end
    local ok, result = pcall(fn, ...)
    getItemNameFromFullType = original
    if not ok then error(result) end
    return result, resolved, data
end

return Resolver
