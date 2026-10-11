require "PZSurvivorToolkit/Settings"
if not getActivatedMods():contains("MoodleFramework") then return end
if getActivatedMods():contains("MedicineMoodlesB42") then
    if not PZSurvivorToolkit.medicineLegacyWarning then
        print("[PZSurvivorToolkit] MedicineMoodlesB42 is active; Toolkit medicine indicators are disabled to avoid duplicates.")
        PZSurvivorToolkit.medicineLegacyWarning = true
    end
    return
end
if PZSurvivorToolkit.MedicineMoodles then return end
require "MF_ISMoodle"
local Effects = require "PZSurvivorToolkit/MedicineEffects"
local Toolkit = PZSurvivorToolkit
local Medicine = {states = {}, sequence = 0, names = {}}
Toolkit.MedicineMoodles = Medicine
local medicines = {
    Antibiotics = {50, "Base.Antibiotics"}, Antidepressants = {6600, "Base.PillsAntiDep"},
    BetaBlockers = {6600, "Base.PillsBeta"}, Painkillers = {5400, "Base.Pills"},
    SleepingTablets = {6600, "Base.PillsSleepingTablets"}, LemonGrass = {280, "Base.LemonGrass"},
    BlackSage = {7, "Base.BlackSage"}, CommonMallow = {5, "Base.CommonMallow"},
}
local herbs = {BlackSage = true, CommonMallow = true}

local function reading(player)
    if player:isDead() then return end
    if not isClient() then return Effects.capture(player) end
    local state = Medicine.states[player:getPlayerNum()]
    if state and state.player == player and state.values and getTimestampMs() - state.receivedAt <= 10000 then
        return state.values
    end
end

local function setup(moodle, name, spec)
    -- Zero is neutral; positive remaining pools are beneficial, negative values mark cooldown/waiting.
    moodle:setThresholds(-0.7, -0.4, -0.1, -0.000001, 0.000001, 0.1, 0.4, 0.7)
    moodle:setValue(0)
    local item = getScriptManager():getItem(spec[2])
    if item then
        for kind = 1, 2 do for level = 1, 4 do
            moodle:setTitle(kind, level, herbs[name]
                and getText("UI_PZSurvivorToolkit_medicine_" .. name) or item:getDisplayName())
            moodle:setPicture(kind, level, item:getNormalTexture())
        end end
    end
    moodle.toolkitMedicineSetup = true
end

local function update(player)
    if not player:isLocalPlayer() then return end
    local values = reading(player)
    for name, spec in pairs(medicines) do
        local moodle = MF.getMoodle(Medicine.names[name], player:getPlayerNum())
        if not moodle or moodle.char ~= player then
            moodle = MF.ISMoodle:new(Medicine.names[name], player)
        end
        if not moodle.toolkitMedicineSetup then setup(moodle, name, spec) end
        local enabled = herbs[name] and Toolkit.Settings.medicineHerbs()
            or not herbs[name] and Toolkit.Settings.medicineMoodleSync()
        local value = enabled and values and values[name] / spec[1] or 0
        local shown, kind, description = value, 1
        if name == "Antidepressants" and value >= 1 then
            shown, kind = -0.05, 2
            description = getText("UI_PZSurvivorToolkit_medicine_pending")
        elseif name == "LemonGrass" then
            shown, kind = -value, 2
            description = getText("UI_PZSurvivorToolkit_medicine_cooldown", round(value * 100))
        else
            description = getText("IGUI_RemainingPercent", round(value * 100))
            if name == "SleepingTablets" and value > 0 and values.SleepingIntensity > 0 then
                description = getText("IGUI_climate_intensity") .. ": " .. round(values.SleepingIntensity / 0.1, 2)
                    .. " / " .. description
            end
        end
        if moodle:getValue() ~= shown then moodle:setValue(shown) end
        local level = moodle:getLevel()
        if level > 0 and moodle:getDescription(kind, level) ~= description then
            moodle:setDescription(kind, level, description)
        end
    end
end

for name in pairs(medicines) do
    Medicine.names[name] = "PZSurvivorToolkitMedicine" .. name
    MF.createMoodle(Medicine.names[name])
end
Events.OnCreatePlayer.Add(function(num) update(getSpecificPlayer(num)) end)
Events.OnPlayerUpdate.Add(function(player)
    if not player:isLocalPlayer() then return end
    update(player)
    if not isClient() then return end
    local num, now = player:getPlayerNum(), getTimestampMs()
    if player:isDead() or not (Toolkit.Settings.medicineMoodleSync() or Toolkit.Settings.medicineHerbs()) then
        Medicine.states[num] = nil; return
    end
    local state = Medicine.states[num]
    if not state or state.player ~= player then state = {player = player, lastPoll = -1000}; Medicine.states[num] = state end
    if now - state.lastPoll < 1000 or state.request and now - state.lastPoll < 5000 then return end
    Medicine.sequence = Medicine.sequence % 2147483647 + 1
    state.request, state.lastPoll = Medicine.sequence, now
    sendClientCommand(player, "PZSurvivorToolkitMedicine", "Read", {request = state.request})
end)
Events.OnServerCommand.Add(function(module, command, values)
    if module ~= "PZSurvivorToolkitMedicine" or command ~= "State" or type(values) ~= "table" then return end
    for name in pairs(medicines) do
        local value = values[name]
        if type(value) ~= "number" or not (value >= 0 and value <= 1000000000) then return end
    end
    if type(values.SleepingIntensity) ~= "number" or not (values.SleepingIntensity >= 0 and values.SleepingIntensity <= 1000000000) then return end
    for num, state in pairs(Medicine.states) do
        local player = getSpecificPlayer(num)
        if player == state.player and player:isLocalPlayer() and not player:isDead() and player:getOnlineID() == values.onlineID
            and state.request ~= nil and state.request == values.request then
            state.values, state.receivedAt, state.request = values, getTimestampMs(), nil
        end
    end
end)
Events.OnMainMenuEnter.Add(function() Medicine.states = {} end)
Events.OnPlayerDeath.Add(function(player) Medicine.states[player:getPlayerNum()] = nil end)
