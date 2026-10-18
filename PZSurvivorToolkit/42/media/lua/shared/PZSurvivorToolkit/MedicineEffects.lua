if not getActivatedMods():contains("MoodleFramework") or getActivatedMods():contains("MedicineMoodlesB42") then return end
require "PZSurvivorToolkit"

local Toolkit = PZSurvivorToolkit
if Toolkit.MedicineEffects then return Toolkit.MedicineEffects end
local Effects = {}
Toolkit.MedicineEffects = Effects

function Effects.capture(player)
    local body = player:getBodyDamage()
    local values = {
        Antibiotics = player:getReduceInfectionPower(),
        Antidepressants = player:getDepressEffect(),
        BetaBlockers = player:getBetaEffect(),
        Painkillers = player:getPainEffect(),
        SleepingTablets = player:getSleepingTabletEffect(),
        SleepingIntensity = player:getSleepingTabletDelta(),
        BlackSage = body:getPainReduction(),
        CommonMallow = body:getColdReduction(),
    }
    -- Native decay can cross zero by one update; a remaining effect cannot be negative.
    for name, value in pairs(values) do values[name] = math.max(0, value) end
    local cooldown = toolkitMedicineCooldown and toolkitMedicineCooldown(player)
    -- A distinct key prevents an older server's estimate from becoming an exact reading.
    values.LemonGrassCooldown = type(cooldown) == "number"
        and cooldown >= 0 and cooldown <= 1000000000 and cooldown or false
    return values
end

return Effects
