local Glass = require "PZSurvivorToolkit/VehicleGlass"
if not Glass.active() or Glass.eventsInstalled then return end

-- Require the upstream injector first, so its callbacks always precede ours.
-- Fixing.Load appends targets again on world initialization, including Host.
require "FixingRecipeHandler"
Events.OnInitWorld.Add(Glass.removeScriptRecipes)
if isServer() then Events.OnGameBoot.Add(Glass.removeScriptRecipes) end
Glass.eventsInstalled = true
