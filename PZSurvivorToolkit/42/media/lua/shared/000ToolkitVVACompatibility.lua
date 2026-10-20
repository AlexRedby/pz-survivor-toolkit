local mods, id = getActivatedMods(), "VanillaVehiclesAnimated"
if not mods:contains(id) then
    id = "\\" .. id
    if not mods:contains(id) then return end
end
require "PZSurvivorToolkit"
if PZSurvivorToolkit.VVACompatibility then return end

local Proof = require "PZSurvivorToolkit/SourceProof"
-- Reviewed VVA core v4. Unknown/fixed upstream sources keep their own behavior.
for _, file in ipairs({
    {"media/lua/shared/VVA_core.lua", 2714564573},
    {"media/lua/shared/VVA_applyAnimations.lua", 2749323844},
}) do
    if not Proof.matches(file[1], file[2], id, true) then return end
end

local manager = ScriptManager and ScriptManager.instance
local missing, decor = "VVA_StepVan_Decor_Trunk", "VVA_StepVan_Trunk_Decor"
-- Scripts load before shared Lua. Respect any real template supplied by another mod.
if not manager then return end
local VVA = require "VVA_core"
if VVA.version ~= 4 or not Proof.closure(VVA.addToProfile, "VVA_core.lua")
    or not Proof.closure(VVA.IsProfileDefined, "VVA_core.lua") then return end

-- StepVan_Common already includes the real decor. An empty composite removes only
-- the extra misspelled leaf before VVA expands its profiles on OnInitGlobalModData.
-- Aliasing it to the real template would risk applying that template twice.
if Proof.matches("media/scripts/vehicles/VVA2/StepVan/TrunkFill.txt", 2061071433, id, true)
    and manager:getVehicleTemplate("Base." .. decor)
    and not manager:getVehicleTemplate("Base." .. missing) and not VVA.IsProfileDefined(missing) then
    VVA.addToProfile(missing, {})
    PZSurvivorToolkit.VVACompatibility = true
    print("[PZSurvivorToolkit] VVA StepVan template compatibility active")
end

-- Unlike the redundant StepVan leaf, the misspelled Modern leaf has not applied
-- its decor yet. Resolve it to the existing, source-verified bars template.
missing, decor = "VVA_Modern_DecorBars", "VVA_ModernBars_Decor"
if Proof.matches("media/scripts/vehicles/VVA2/Modern/Bars.txt", 684814076, id, true)
    and manager:getVehicleTemplate("Base." .. decor)
    and not manager:getVehicleTemplate("Base." .. missing) and not VVA.IsProfileDefined(missing) then
    VVA.addToProfile(missing, {decor})
    PZSurvivorToolkit.VVACompatibility = true
    print("[PZSurvivorToolkit] VVA Modern bars template compatibility active")
end

-- Upstream 7cc1115985835bb2b48d5d6b6c702ac296085270 migrated normal police
-- separators to NormalBars_Decor, but left CarLightsRanger using the old name.
-- The pinned apply source uses this missing leaf only for that ranger profile.
missing, decor = "VVA_Normal_PoliceSeparator", "VVA_NormalBars_Decor"
if Proof.matches("media/scripts/vehicles/VVA2/Normal/interiorDecor.txt", 4002040244, id, true)
    and manager:getVehicleTemplate("Base." .. decor)
    and not manager:getVehicleTemplate("Base." .. missing) and not VVA.IsProfileDefined(missing) then
    VVA.addToProfile(missing, {decor})
    PZSurvivorToolkit.VVACompatibility = true
    print("[PZSurvivorToolkit] VVA ranger bars template compatibility active")
end
