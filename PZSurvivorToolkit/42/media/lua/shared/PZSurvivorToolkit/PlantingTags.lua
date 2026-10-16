local Planting = {}
local cachedProps, plantingTypes, packetTypes

local function typeKey(fullType)
    return string.lower(tostring(fullType))
end

local function reset()
    cachedProps, plantingTypes, packetTypes = nil, nil, nil
end

if Events and Events.OnGameBoot then Events.OnGameBoot.Add(reset) end

local function plantingInputs()
    local props = farming_vegetableconf and farming_vegetableconf.props
    -- Shared item tags can load before the native farming definitions.
    if not props then return nil end
    local populated = false
    for _ in pairs(props) do populated = true; break end
    if not populated then return nil end
    -- shortcut: in-place crop edits after OnGameBoot need a reload; add invalidation if runtime editors appear.
    if cachedProps ~= props then
        plantingTypes, cachedProps = {}, props
        packetTypes = nil
        for _, crop in pairs(props) do
            if crop.seedTypes then
                for _, fullType in ipairs(crop.seedTypes) do plantingTypes[typeKey(fullType)] = true end
            elseif crop.seedName then
                plantingTypes[typeKey(crop.seedName)] = true
            end
        end
    end
    return plantingTypes
end

local function packets(inputs)
    if packetTypes then return packetTypes end
    local manager = ScriptManager and ScriptManager.instance
    local recipe = manager and manager:getCraftRecipe("Base.OpenPacketOfSeeds")
    if not recipe then return nil end
    local result = {}
    local sources = recipe:getInputs()
    local outputs = recipe:getOutputs()
    if sources:size() == 0 or outputs:size() == 0 then return nil end
    for i = 0, sources:size() - 1 do
        local items = sources:get(i):getPossibleInputItems()
        if items:size() == 0 then return nil end
        for j = 0, items:size() - 1 do result[typeKey(items:get(j):getFullName())] = "seed" end
    end
    for i = 0, outputs:size() - 1 do
        local items = outputs:get(i):getPossibleResultItems()
        if items:size() == 0 then return nil end
        for j = 0, items:size() - 1 do
            local fullType = typeKey(items:get(j):getFullName())
            if not inputs[fullType] then result[fullType] = "empty" end
        end
    end
    packetTypes = result
    return result
end

function Planting.role(fullType, script)
    if not fullType then return nil end
    if script and script.getDoubleClickRecipe then
        local recipe = typeKey(script:getDoubleClickRecipe())
        if recipe == "openpacketofseeds" or recipe == "base.openpacketofseeds" then return "seed" end
    end
    local inputs = plantingInputs()
    if not inputs then return nil end
    fullType = typeKey(fullType)
    if inputs[fullType] then return "seed" end
    local types = packets(inputs)
    return types and types[fullType]
end

return Planting
