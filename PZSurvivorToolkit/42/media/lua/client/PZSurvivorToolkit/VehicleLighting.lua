require "PZSurvivorToolkit/Settings"

-- Small, client-local approximation of lamp spill/reflected road light. Native
-- IsoLightSource supplies tile occlusion/falloff; this is not global ambient light.
local Toolkit = PZSurvivorToolkit
local L = { states = {}, nextUpdate = 0 }
Toolkit.VehicleLighting = L
local options = PZAPI.ModOptions:getOptions("PZSurvivorToolkit")
options:addTitle(getText("UI_PZST_VehicleLightTitle"))
local spill = options:addComboBox("VehicleLightSpill", getText("UI_PZST_VehicleLightSpill"),
    getText("UI_PZST_VehicleLightSpillTip"))
for i, key in ipairs({"Off", "Weak", "Normal", "Strong"}) do
    spill:addItem(getText("UI_PZST_VehicleLight" .. key), i == 3)
end
local shape = options:addTickBox("VehicleBeamShape", getText("UI_PZST_VehicleBeamShape"), true,
    getText("UI_PZST_VehicleBeamShapeTip"))
local reverse
if getActivatedMods():contains("ReverseDriveLights") then
    require "ReverseDriveLights/ReverseDriveLightsShared"
    reverse = options:addComboBox("VehicleReverseLight", getText("UI_PZST_VehicleReverseLight"),
        getText("UI_PZST_VehicleReverseLightTip"))
    for i, key in ipairs({"Weak", "Normal", "Original"}) do
        reverse:addItem(getText("UI_PZST_VehicleLight" .. key), i == 2)
    end
end
local strengths = {0, 0.5, 1, 1.5}
local reverseProfiles = {{8, .2}, {12, .3}}
local originalReverse
if reverse then
    originalReverse = {ReverseDriveLights.REVERSE_DISTANCE, ReverseDriveLights.REVERSE_INTENSITY}
end
local out = Vector3f.new()
local lampOrigins = require "PZSurvivorToolkit/VehicleLampOrigins"
local sides = {
    {front="HeadlightLeft", rear="HeadlightRearLeft", frontKey="frontLeft", rearKey="rearLeft", sign=1},
    {front="HeadlightRight", rear="HeadlightRearRight", frontKey="frontRight", rearKey="rearRight", sign=-1},
}

function L.configureReverse()
    if not reverse then return end
    local profile = reverseProfiles[reverse:getValue()] or originalReverse
    ReverseDriveLights.REVERSE_DISTANCE = profile[1]
    ReverseDriveLights.REVERSE_INTENSITY = profile[2]
end

-- Numeric centres of the actual lamp faces, extracted from the current FBX
-- and shader's separate left/right lamp mask zones. Loaded() already scales
-- the script extents and model offset; getWorldPos does not scale them again.
function L.lampOrigin(vehicle, id, script)
    script = script or vehicle:getScript()
    local model = script:getModel()
    local origins = model and lampOrigins[model:getFile()]
    local anchor = origins and origins[id]
    if not anchor then return end -- unknown models retain their upstream light
    local rotate = model:getRotate()
    if rotate:x() ~= 0 or rotate:y() ~= 0 or rotate:z() ~= 0 then return end
    local offset, scale, extents = script:getModelOffset(), script:getModelScale(), script:getExtents()
    if extents:x() <= 0 or extents:z() <= 0 then return end
    local x, y, z = offset:x()+anchor[1]*scale, offset:y()+anchor[2]*scale, offset:z()+anchor[3]*scale
    -- createSpotLight takes fractions of HALF the loaded chassis dimensions.
    return x, y, z, x*2/extents:x(), z*2/extents:z()
end

-- Keep upstream switching, raw power/range, lamp colour and condition effects.
-- dot is a horizontal cone approximation, not a real low-beam vertical cutoff.
function L.shapeFront(vehicle)
    if not shape:getValue() then return end
    local high = NepHBO7.getModData(vehicle).highBeamsOn == true
    for _, side in ipairs(sides) do
        local id = side.front
        local part = vehicle:getPartById(id)
        local light = part and part:getLight()
        local _, _, _, x, z = L.lampOrigin(vehicle, id)
        if light and x then
            part:createSpotLight(x, z, light:getDistanization(),
                light:getIntensity(), high and .98 or .94, light:getFocusing())
        end
    end
end

function L.installBeamHooks()
    if NepHBO7 and not L.frontHook then
        local original = NepHBO7.UpdateLights
        L.frontHook = function(vehicle)
            original(vehicle)
            if vehicle then L.shapeFront(vehicle) end
        end
        NepHBO7.UpdateLights = L.frontHook
    end
    local client = reverse and ReverseDriveLights.Client
    if client and not L.reverseHook then
        local original = client.onPlayerUpdate
        L.reverseHook = function(player)
            original(player)
            if not shape:getValue() or not player or not player:isLocalPlayer() then return end
            local state = client.players[player:getPlayerNum()]
            if not state then return end
            for part in pairs(state.parts) do
                local light = part:getLight()
                if light and part:getInventoryItem() then
                    local _, _, _, x, z = L.lampOrigin(state.vehicle, part:getId())
                    if x then
                        part:createSpotLight(x, z, light:getDistanization(),
                            light:getIntensity(), .75, light:getFocusing())
                    end
                end
            end
        end
        Events.OnPlayerUpdate.Remove(original)
        client.onPlayerUpdate = L.reverseHook
        Events.OnPlayerUpdate.Add(L.reverseHook)
    end
end

function L.refreshBeams()
    L.installBeamHooks()
    local cell = getCell()
    if not cell or not L.frontHook then return end
    local iterator = cell:getVehicles():iterator()
    while iterator:hasNext() do
        local vehicle = iterator:next()
        if not vehicle:isRemovedFromWorld() then NepHBO7.UpdateLights(vehicle) end
    end
end

local function remove(state)
    for _, entry in pairs(state.lights) do state.cell:removeLamppost(entry.source) end
end

function L.clear()
    for _, state in pairs(L.states) do remove(state) end
    L.states = {}
end

local function lamp(vehicle, id)
    local part = vehicle:getPartById(id)
    local item = part and part:getInventoryItem()
    local light = part and part:getLight()
    return item and item:getCondition() > 0 and light and light:getActive() and part or nil
end

local function put(state, registered, key, vehicle, x, z, radius, r, g, b)
    vehicle:getWorldPos(x, 0, z, out)
    local wx, wy, wz = math.floor(out:x()), math.floor(out:y()), math.floor(vehicle:getZ())
    local entry = state.lights[key]
    -- JNI registers position/radius once, so moving an existing Java object is
    -- insufficient. Remove OUR object and register a new source on tile changes.
    if entry and (entry.x ~= wx or entry.y ~= wy or entry.z ~= wz or entry.radius ~= radius
            or not registered:contains(entry.source)) then
        state.cell:removeLamppost(entry.source); state.lights[key] = nil; entry = nil
    end
    if not entry then
        local source = IsoLightSource.new(wx, wy, wz, r, g, b, radius)
        state.cell:addLamppost(source)
        entry = {source=source, x=wx, y=wy, z=wz, radius=radius}
        state.lights[key] = entry
    else
        entry.source:setR(r); entry.source:setG(g); entry.source:setB(b)
    end
    entry.keep = true
end

-- Local-player positions are one synchronous update snapshot, never a cross-tick cache.
local function playerPositions()
    local positions = {}
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p and not p:isDead() then
            positions[#positions + 1] = {x=p:getX(), y=p:getY(), z=p:getZ()}
        end
    end
    return positions
end

local function nearby(vehicle, positions)
    if #positions == 0 then return false end
    local x, y, z = vehicle:getX(), vehicle:getY(), vehicle:getZ()
    for _, p in ipairs(positions) do
        if math.abs(p.z - z) < 1 then
            local dx, dy = p.x - x, p.y - y
            if dx*dx + dy*dy < 2500 then return true end
        end
    end
    return false
end

local function reversing(vehicle)
    if reverse and ReverseDriveLights.Client then
        for _, state in pairs(ReverseDriveLights.Client.players) do
            if state.vehicle == vehicle then return true end
        end
    end
    return false
end

function L.update()
    L.configureReverse()
    local strength = strengths[spill:getValue()] or 1
    local cell = getCell()
    if not cell or strength == 0 then L.clear(); return end
    local seen = {}
    local positions, registered
    local vehicles = cell:getVehicles()
    local iterator = vehicles:iterator()
    while iterator:hasNext() do
        local vehicle = iterator:next()
        -- Most parked vehicles are unlit; avoid player/position and lamp reads for them.
        local eligible = vehicle:getHeadlightsOn() and vehicle:getSquare()
            and not vehicle:isRemovedFromWorld() and vehicle:getBatteryCharge() > 0
        if eligible then positions = positions or playerPositions() end
        if eligible and nearby(vehicle, positions) then
            registered = registered or cell:getLamppostPositions()
            local state = L.states[vehicle]
            if state and state.cell ~= cell then remove(state); state = nil end
            state = state or {cell=cell, lights={}}
            L.states[vehicle] = state; seen[vehicle] = true
            for _, entry in pairs(state.lights) do entry.keep = false end
            local script = vehicle:getScript()
            local extents = script:getExtents()
            local reverseOn = reversing(vehicle)
            -- Loaded script dimensions already include the model scale.
            local halfWidth, halfLength = extents:x() * .4, extents:z() * .5
            for _, side in ipairs(sides) do
                local front = lamp(vehicle, side.front)
                if front then
                    local x, _, z = L.lampOrigin(vehicle, side.front, script)
                    put(state, registered, side.frontKey, vehicle, x or halfWidth*side.sign, z or halfLength,
                        4, .16*strength, .152*strength, .128*strength)
                end
                local rear = lamp(vehicle, side.rear)
                if rear then
                    local x, _, z = L.lampOrigin(vehicle, side.rear, script)
                    x, z = x or halfWidth*side.sign, z or -halfLength
                    if reverseOn then
                        put(state, registered, side.rearKey, vehicle, x, z,
                            3, .08*strength, .08*strength, .072*strength)
                    else
                        put(state, registered, side.rearKey, vehicle, x, z,
                            2, .035*strength, .005*strength, .003*strength)
                    end
                end
            end
            for key, entry in pairs(state.lights) do
                if not entry.keep then cell:removeLamppost(entry.source); state.lights[key] = nil end
            end
        end
    end
    for vehicle, state in pairs(L.states) do
        if not seen[vehicle] then remove(state); L.states[vehicle] = nil end
    end
end

local previousApply = options.apply
options.apply = function(...)
    if previousApply then previousApply(...) end
    L.configureReverse(); L.refreshBeams(); L.update()
end
Events.OnGameStart.Add(function() L.clear(); L.nextUpdate = 0; L.configureReverse(); L.refreshBeams() end)
Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now >= L.nextUpdate then L.nextUpdate = now + 100; L.update() end
end)
Events.OnMainMenuEnter.Add(L.clear)
