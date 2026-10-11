require "PZSurvivorToolkit/Settings"
if not getActivatedMods():contains("MedicineMoodlesB42") then return end
local Effects = require "PZSurvivorToolkit/MedicineEffects"
local Toolkit = PZSurvivorToolkit
local Medicine = {states = {}, sequence = 0}
Toolkit.MedicineMoodles = Medicine
local scales = {Antibiotics = 50, Antidepressants = 6600, BetaBlockers = 6600,
    Painkillers = 5400, SleepingTablets = 6600, LemonGrass = 280, BlackSage = 7, CommonMallow = 5}
local herbs = {BlackSage = true, CommonMallow = true}

local function reading(player)
    if player:isDead() then return end
    if not isClient() then return Effects.capture(player) end
    local state = Medicine.states[player:getPlayerNum()]
    if state and state.player == player and state.values and getTimestampMs() - state.receivedAt <= 10000 then
        return state.values
    end
end

local function getValue(name, original)
    return function(self, player)
        if herbs[name] then
            if not Toolkit.Settings.medicineHerbs() then return 0 end
        elseif not Toolkit.Settings.medicineMoodleSync() then
            return original(self, player)
        end
        local values = reading(player)
        local value = values and values[name] / scales[name] or 0
        if name == "Antidepressants" and value >= 1 then
            return self.MoodleLevels.Bad[1], self.MoodleType.Special
        elseif name == "LemonGrass" then
            return value, self.MoodleType.Bad
        elseif name == "SleepingTablets" then
            return value, nil, values and values.SleepingIntensity / 0.1
        end
        return value
    end
end

function Medicine.install()
    local mod = ModMedicineMoodles
    if not mod or Medicine.installed == mod then return end
    Medicine.installed = mod
    mod:addMedicine("BlackSage", "Base.BlackSage", getValue("BlackSage"))
    mod:addMedicine("CommonMallow", "Base.CommonMallow", getValue("CommonMallow"))
    for name in pairs(scales) do
        if not herbs[name] and mod.Medicines[name] then
            mod.Medicines[name].getValue = getValue(name, mod.Medicines[name].getValue)
        end
    end
    local setupMoodle, updateMoodle = mod.setupMoodle, mod.updateMoodle
    mod.setupMoodle = function(self, moodle)
        setupMoodle(self, moodle)
        if not moodle or not herbs[moodle.name] then return end
        local item = getScriptManager():getItem(self.Medicines[moodle.name].item)
        local texture = item and item:getNormalTexture()
        for kind = 1, 2 do for level = 1, 4 do
            moodle:setTitle(kind, level, getText("UI_PZSurvivorToolkit_medicine_" .. moodle.name))
            if texture then moodle:setPicture(kind, level, texture) end
        end end
    end
    -- addMedicine can create moodles before the picture/title override is installed.
    for _, moodles in pairs(mod.PlayerMoodles) do
        for name in pairs(herbs) do mod:setupMoodle(moodles[name]) end
    end
    mod.updateMoodle = function(self, moodle)
        updateMoodle(self, moodle)
        if not moodle or not scales[moodle.name] or moodle:getLevel() == 0 or not self:checkSkillRequirements(moodle) then return end
        if not herbs[moodle.name] and not Toolkit.Settings.medicineMoodleSync() then return end
        local value, kind, intensity = self.Medicines[moodle.name].getValue(self, moodle.char)
        kind = kind or self.MoodleType.Good
        local description
        if moodle.name == "Antidepressants" and kind == self.MoodleType.Special then
            kind = self.MoodleType.Bad
            description = getText("UI_PZSurvivorToolkit_medicine_pending")
        elseif moodle.name == "LemonGrass" and Toolkit.Settings.medicineMoodleSync() then
            description = getText("UI_PZSurvivorToolkit_medicine_cooldown", round(value * 100))
        elseif kind ~= self.MoodleType.Special then
            description = getText("IGUI_RemainingPercent", round(value * 100))
            if intensity and intensity > 0 then
                description = getText("IGUI_climate_intensity") .. ": " .. round(intensity, 2) .. " / " .. description
            end
        end
        if description and moodle:getDescription(kind, moodle:getLevel()) ~= description then
            moodle:setDescription(kind, moodle:getLevel(), description)
        end
    end
end

Events.OnGameStart.Add(Medicine.install)
Events.OnPlayerUpdate.Add(function(player)
    if not isClient() or not player:isLocalPlayer() then return end
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
    for name in pairs(scales) do
        local value = values[name]
        if type(value) ~= "number" or value ~= value or value < 0 or value > 1000000000 then return end
    end
    if type(values.SleepingIntensity) ~= "number" or values.SleepingIntensity ~= values.SleepingIntensity
        or values.SleepingIntensity < 0 or values.SleepingIntensity > 1000000000 then return end
    for num, state in pairs(Medicine.states) do
        local player = getSpecificPlayer(num)
        if player == state.player and not player:isDead() and player:getOnlineID() == values.onlineID
            and state.request ~= nil and state.request == values.request then
            state.values, state.receivedAt, state.request = values, getTimestampMs(), nil
        end
    end
end)
Events.OnMainMenuEnter.Add(function() Medicine.states = {} end)
Events.OnPlayerDeath.Add(function(player) Medicine.states[player:getPlayerNum()] = nil end)
