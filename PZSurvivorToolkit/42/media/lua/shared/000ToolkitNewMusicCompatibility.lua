local mods = getActivatedMods and getActivatedMods()
if not mods or not (mods:contains("NewMusic") or mods:contains("\\NewMusic")) then return end
local Compatibility = require "PZSurvivorToolkit/NewMusicCompatibility"
Compatibility.installShared()
if Compatibility.sharedEventsInstalled then return end
-- Reapply after the engine finishes loading shared files and at world/session
-- boundaries. No recurring tick callback or sandbox mutation is needed.
for _, name in ipairs({"OnGameBoot", "OnInitGlobalModData", "OnGameStart", "OnServerStarted"}) do
    local event = Events and Events[name]
    if event and event.Add then event.Add(Compatibility.installShared) end
end
Compatibility.sharedEventsInstalled = true
