if not getActivatedMods():contains("MoodleFramework") or getActivatedMods():contains("MedicineMoodlesB42") then return end
require "PZSurvivorToolkit"
require "TimedActions/ISEatFoodAction"

local Toolkit = PZSurvivorToolkit
if Toolkit.MedicineEffects then return Toolkit.MedicineEffects end
local Effects = {}
Toolkit.MedicineEffects = Effects
local cooldowns = setmetatable({}, {__mode = "k"})

function Effects.capture(player)
    local body = player:getBodyDamage()
    local values = {
        Antibiotics = player:getReduceInfectionPower(),
        Antidepressants = player:getDepressEffect(),
        BetaBlockers = player:getBetaEffect(),
        Painkillers = player:getPainEffect(),
        SleepingTablets = player:getSleepingTabletEffect(),
        SleepingIntensity = player:getSleepingTabletDelta(),
        LemonGrass = cooldowns[player] or 0,
        BlackSage = body:getPainReduction(),
        CommonMallow = body:getColdReduction(),
    }
    -- Native decay can cross zero by one update; a remaining effect cannot be negative.
    for name, value in pairs(values) do values[name] = math.max(0, value) end
    return values
end

local function observeEating(original)
    return function(action, ...)
        if isClient() or not action.item or action.item:getFoodSicknessChange() >= 0 then
            return original(action, ...)
        end
        local player, stats = action.character, action.character:getStats()
        local sickness, poison = stats:get(CharacterStat.FOOD_SICKNESS), stats:get(CharacterStat.POISON)
        local result = original(action, ...)
        if stats:get(CharacterStat.FOOD_SICKNESS) < sickness or stats:get(CharacterStat.POISON) < poison then
            -- shortcut: native randomized cooldown is private; use an upper bound until a getter exists.
            cooldowns[player] = player:hasTrait(CharacterTrait.IRON_GUT) and 150
                or player:hasTrait(CharacterTrait.WEAK_STOMACH) and 280 or 230
        end
        return result
    end
end

ISEatFoodAction.complete = observeEating(ISEatFoodAction.complete)
-- Cancellation can consume part of an item through eat() instead of complete().
ISEatFoodAction.eat = observeEating(ISEatFoodAction.eat)

local function advance(player)
    local timer = cooldowns[player]
    if not timer then return end
    if player:isDead() then cooldowns[player] = nil; return end
    timer = math.max(0, timer - getGameTime():getMultiplier() * 0.015)
    cooldowns[player] = timer > 0 and timer or nil
end
Events.OnTick.Add(function()
    if isServer() then for player in pairs(cooldowns) do advance(player) end end
end)
Events.OnPlayerUpdate.Add(function(player)
    if not isClient() and not isServer() then advance(player) end
end)

return Effects
