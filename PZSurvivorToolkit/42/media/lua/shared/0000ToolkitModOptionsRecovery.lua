-- The Host child shares its owner's cache but must never restore client files.
if isServer and isServer() then return end
-- Recovery is independent of today's mod selection and preset markers. Shared
-- file load precedes shared category readers and client OnGameBoot callbacks.
local storage = require "PZSurvivorToolkit/ModOptionsStorage"
if not storage.recover() then
    print("[PZSurvivorToolkit] ModOptions recovery deferred; saved preferences remain backed up")
end
