if not getActivatedMods():contains("SeedSeasonIndicator") then return end

local indicator = require "SeedSeasonIndicator"

-- Both the label renderer and category comparators consult this public function.
-- Keep inventory categories stable; season icons and tooltips have independent paths.
indicator.computeCategoryKey = function() return nil end
