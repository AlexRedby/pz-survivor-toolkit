require "PZAPI/ModOptions"
local Options = {}
-- Persisted preferences survive removal of the external indicator.
local page = PZAPI.ModOptions:create("SeedSeasonIndicator", getText("UI_PZST_PlantingOptions"))
Options.config = {}
for _, entry in ipairs({
    {"enabled", "UI_PZST_PlantingEnabled", true},
    {"tooltip", "UI_PZST_PlantingTooltip", true},
    {"noBestStar", "UI_PZST_PlantingBest", false},
    {"badMonth", "UI_PZST_PlantingBadMonths", false},
}) do
    Options.config[entry[1]] = page:addTickBox(entry[1], getText(entry[2]), entry[3])
end
function Options.enabled() return Options.config.enabled:getValue() end
function Options.tooltip() return Options.config.tooltip:getValue() end
function Options.preferBest() return Options.config.noBestStar:getValue() end
function Options.badMonths() return Options.config.badMonth:getValue() end
return Options
