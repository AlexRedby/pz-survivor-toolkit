-- The CLIENT's view of the presets: where to read them from, and keeping that current.
-- The authority owns them (server/LootSorter_Presets.lua); this side only caches and asks.
--   single-player -- a file under <Zomboid>/Lua/, so presets follow you into every world
--   multiplayer   -- the server's per-world table, which arrives via OnReceiveGlobalModData; asking
--                    for it (and retrying once) is why this file exists
-- SP presets and tag rules share QuartermasterPresets' paired storage. MP retains both
-- existing ModData stores; neither can be used for tag routing until both have arrived.
-- Trade-off: in MP presets no longer follow you between servers. Import-from-library is the fix.

LootSorter = LootSorter or {}
local Presets = require "PZSurvivorToolkit/QuartermasterPresets"
local Rules = require "PZSurvivorToolkit/QuartermasterTagRules"
local Tags = require "PZSurvivorToolkit/ItemTags"

local MOD_DATA_KEY = "LootSorter_Presets"

-- On an MP client getOrCreate is permanently empty; the live table arrives via
-- OnReceiveGlobalModData. In SP that event never fires and the file-backed table is the truth.
function LootSorter.getPresetStore()
    if isClient() then return LootSorter._receivedPresets or {} end
    return Presets.native()
end

function LootSorter.arePresetsSynced()
    return not isClient() or (LootSorter._receivedPresets ~= nil
        and (not Tags.enabled() or Rules.presetsSynced()))
end

LootSorter.addOrReplaceHandler(Events.OnReceiveGlobalModData, "_onReceivePresets",
    function(key, receivedTable)
        if key ~= MOD_DATA_KEY or not receivedTable then return end
        receivedTable.presets = receivedTable.presets or {}
        LootSorter._receivedPresets = receivedTable.presets
        -- The round trip is async, so an open picker rendered before this arrived and is now stale.
        if LootSorter._picker then LootSorter._picker.needRebuild = true end
        if LootSorter._presetEditor then LootSorter._presetEditor.needRebuild = true end
        LootSorter.DBG("presets received from server")
    end)

function LootSorter.requestPresets()
    if not isClient() then return end
    ModData.request(Rules.STORE)
    pcall(function() ModData.request(MOD_DATA_KEY) end)
end

LootSorter.removeHandler(Events.OnTick, "_presetRetryTick")

LootSorter.addOrReplaceHandler(Events.OnGameStart, "_onGameStartPresets", function()
    -- A store held over from a previous server would read as synced and authorise pruning against
    -- the wrong world. Drop it and wait for this server's copy.
    LootSorter._receivedPresets, Rules.received = nil, nil
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
