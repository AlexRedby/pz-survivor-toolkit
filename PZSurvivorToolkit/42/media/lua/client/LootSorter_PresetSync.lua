-- The CLIENT's view of the presets: where to read them from, and keeping that current.
-- The authority owns them (server/LootSorter_Presets.lua); this side only caches and asks.
--   single-player -- a file under <Zomboid>/Lua/, so presets follow you into every world
--   multiplayer   -- the server's per-world table, which arrives via OnReceiveGlobalModData; asking
--                    for it (and retrying once) is why this file exists
-- QuartermasterPresets owns both selections and rules: paired SP files or one Host snapshot.
-- Trade-off: in MP presets no longer follow you between servers. Import-from-library is the fix.

LootSorter = LootSorter or {}
local Presets = require "PZSurvivorToolkit/QuartermasterPresets"

-- On an MP client getOrCreate is permanently empty; the live table arrives via
-- OnReceiveGlobalModData. In SP that event never fires and the file-backed table is the truth.
function LootSorter.getPresetStore()
    return Presets.native()
end

function LootSorter.arePresetsSynced()
    return Presets.synced()
end

LootSorter.addOrReplaceHandler(Events.OnReceiveGlobalModData, "_onReceivePresets",
    function(key, receivedTable)
        if key ~= Presets.STORE or not Presets.receive(receivedTable) then return end
        -- The round trip is async, so an open picker rendered before this arrived and is now stale.
        if LootSorter._picker then LootSorter._picker.needRebuild = true end
        -- An open preset editor keeps its entire draft and original revision. Replacing only
        -- its rule would mix two edits; the existing save conflict check handles newer snapshots.
        LootSorter.DBG("presets received from server")
    end)

function LootSorter.requestPresets()
    if not isClient() then return end
    ModData.request(Presets.STORE)
end

LootSorter.removeHandler(Events.OnTick, "_presetRetryTick")

LootSorter.addOrReplaceHandler(Events.OnGameStart, "_onGameStartPresets", function()
    -- A store held over from a previous server belongs to a different world/revision sequence.
    Presets.resetReceived()
    LootSorter.requestPresets()
    -- one retry, in case the first request raced the connection
    local retryAt = getTimestampMs() + LootSorter.SYNC_RETRY_MS
    local retryTick
    retryTick = function()
        if getTimestampMs() < retryAt then return end
        Events.OnTick.Remove(retryTick)
        if LootSorter._presetRetryTick == retryTick then LootSorter._presetRetryTick = nil end
        if not LootSorter.arePresetsSynced() then LootSorter.requestPresets() end
    end
    LootSorter.addOrReplaceHandler(Events.OnTick, "_presetRetryTick", retryTick)
end)
