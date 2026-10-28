local mods = getActivatedMods and getActivatedMods()
if not mods or not (mods:contains("NewMusic") or mods:contains("\\NewMusic")) then return end
local Compatibility = require "PZSurvivorToolkit/NewMusicCompatibility"
Compatibility.installClient()
if Compatibility.clientEventsInstalled then return end
for _, name in ipairs({"OnGameBoot", "OnGameStart"}) do
    local event = Events and Events[name]
    if event and event.Add then event.Add(Compatibility.installClient) end
end
Compatibility.clientEventsInstalled = true
