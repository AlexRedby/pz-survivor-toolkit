-- The CLIENT's view of the presets: where to read them from, and keeping that current.
-- The authority owns them (server/LootSorter_Presets.lua); this side only caches and asks.
--   single-player -- a file under <Zomboid>/Lua/, so presets follow you into every world
--   multiplayer   -- the server's per-world table, which arrives via OnReceiveGlobalModData; asking
--                    for it (and retrying once) is why this file exists
-- Shape: presets = { [name] = { cats={..}, items={..} } }. The (de)serialization is pure and lives
-- in shared/LootSorter_Presets.lua; this file is just the engine I/O around it.
-- Trade-off: in MP presets no longer follow you between servers. Import-from-library is the fix.

LootSorter = LootSorter or {}

local PRESET_FILE = "QuartermasterPresets.txt"
local MOD_DATA_KEY = "LootSorter_Presets"

local function translateItems(presets, translate)
    local out = {}
    for name, preset in pairs(presets) do
        local items = {}
        for key in pairs(preset.items or {}) do
            local mapped = translate(key)
            if mapped then items[mapped] = true end
        end
        local cats = {}
        for key, value in pairs(preset.cats or {}) do if value then cats[key] = true end end
        out[name] = { cats = cats, items = items, gen = preset.gen, rev = preset.rev, createdBy = preset.createdBy }
    end
    return out
end

function LootSorter.loadPresets()
    local presets = {}
    pcall(function()
        local reader = getFileReader(PRESET_FILE, false)   -- do not create; nil when the file is absent
        if reader then
            local buffer = {}
            local line = reader:readLine()
            while line ~= nil do buffer[#buffer + 1] = line; line = reader:readLine() end
            reader:close()
            local stored, version = LootSorter.presetDeserialize(table.concat(buffer, "\n"))
            if version and version >= 2 then
                presets = translateItems(stored, LootSorter.getDisplayNameForFullType)
            else
                presets = stored
            end
        end
    end)
    LootSorter._presets = presets
    return presets
end

function LootSorter.savePresets()
    if isClient() then return end          -- MP writes go to the server, not the local file
    pcall(function()
        LootSorter.getItemNames()
        local forWrite = translateItems(LootSorter._presets or {}, function(displayName)
            return LootSorter.getItemFullType(displayName) or displayName
        end)
        local writer = getFileWriter(PRESET_FILE, true, false)   -- create if missing, overwrite (no append)
        if writer then
            writer:write(LootSorter.presetSerialize(forWrite))
            writer:close()
        end
    end)
end

-- On an MP client getOrCreate is permanently empty; the live table arrives via
-- OnReceiveGlobalModData. In SP that event never fires and the file-backed table is the truth.
function LootSorter.getPresetStore()
    if isClient() then return LootSorter._receivedPresets or {} end
    if not LootSorter._presets then LootSorter.loadPresets() end
    return LootSorter._presets
end

function LootSorter.arePresetsSynced()
    if LootSorter._receivedPresets then return true end
    return not isClient()
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
    pcall(function() if isClient() then ModData.request(MOD_DATA_KEY) end end)
end

LootSorter.removeHandler(Events.OnTick, "_presetRetryTick")

LootSorter.addOrReplaceHandler(Events.OnGameStart, "_onGameStartPresets", function()
    -- A store held over from a previous server would read as synced and authorise pruning against
    -- the wrong world. Drop it and wait for this server's copy.
    LootSorter._receivedPresets = nil
    LootSorter.requestPresets()
    -- one retry, in case the first request raced the connection
    local retryAt = getTimestampMs() + LootSorter.SYNC_RETRY_MS
    local retryTick
    retryTick = function()
        if getTimestampMs() < retryAt then return end
        Events.OnTick.Remove(retryTick)
        if LootSorter._presetRetryTick == retryTick then LootSorter._presetRetryTick = nil end
        if not LootSorter._receivedPresets then LootSorter.requestPresets() end
    end
    LootSorter.addOrReplaceHandler(Events.OnTick, "_presetRetryTick", retryTick)
end)
