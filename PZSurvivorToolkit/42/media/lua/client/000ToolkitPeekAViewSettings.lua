local mods = getActivatedMods and getActivatedMods()
if not mods or not (mods:contains("PeekAView") or mods:contains("\\PeekAView")) then return end
require "PZAPI/ModOptions"
-- Register upstream's load-and-sync callback first, regardless of file order.
require "PeekAView_Options"
local settings = require "PZSurvivorToolkit/PeekAViewSettings"
Events.OnGameBoot.Remove(settings.onBoot)
Events.OnGameBoot.Add(settings.onBoot)
