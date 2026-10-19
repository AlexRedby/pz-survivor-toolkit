-- The preset store and the two commands that mutate it.
--
-- In server/ because this is where the data is owned. That folder does NOT gate execution -- it loads
-- on multiplayer clients too -- so isServer()/isAuthority() below still does the real gating. What it
-- does give is tier order: shared/ always loads first, so serverFn and the verdicts are already there.
--
-- No isClient() early return on purpose: the caller half (LootSorter.putPreset) is assigned here and
-- has to exist on a client, which only sends the command rather than running it.
LootSorter = LootSorter or {}

local MOD_DATA_KEY = "LootSorter_Presets"

local function worldStore()
    local store = ModData.getOrCreate(MOD_DATA_KEY)
    store.presets = store.presets or {}
    return store
end

local function transmit()
    pcall(function() ModData.transmit(MOD_DATA_KEY) end)
end

-- Transport is shared but the STORE is not: a server owns the world's copy in global ModData,
-- single-player owns the player's file. Writing the wrong one loses the change silently.
local function ownedPresets()
    if isServer() then return worldStore().presets end
    return LootSorter.getPresetStore()
end

local function persist()
    if isServer() then transmit() else LootSorter.savePresets() end
end

-- Only string -> true survives, so a malformed or hostile packet can't put arbitrary values in a
-- table every client will read.
local function cleanSet(value)
    local out = {}
    if type(value) ~= "table" then return out end
    for key, on in pairs(value) do
        if type(key) == "string" and on then out[key] = true end
    end
    return out
end

-- The write is refused if either claim is wrong: expectExisting means someone deleted or created the
-- name meanwhile, baseRev/baseGen mean someone else changed it while this editor was open.
LootSorter.putPreset = LootSorter.serverFn("putPreset", function(player, args)
    local name = args and args.name
    if type(name) ~= "string" or name == "" then return "ok" end
    local presets = ownedPresets()

    local existing = presets[name]
    local verdict = LootSorter.presetWriteVerdict(existing, args.expectExisting or false,
        args.baseRev or 0, args.baseGen)
    if verdict ~= "ok" then
        LootSorter.DBG(("preset %s refused: %s"):format(name, verdict))
        return verdict, { name = name, action = "save" }
    end
    local exists = existing ~= nil
    presets[name] = {
        cats = cleanSet(args.cats),
        items = cleanSet(args.items),
        rev = (exists and (existing.rev or 0) or 0) + 1,
        gen = (exists and existing.gen) or getTimestampMs(),
        createdBy = (exists and existing.createdBy)
            or (player and player:getUsername()) or nil,
    }
    persist()
    LootSorter.DBG("preset saved: " .. name)
    return "ok"
end)

-- baseGen is the generation the user was looking at when they chose to delete, so a name that has
-- since been remade is refused rather than destroyed.
LootSorter.removePreset = LootSorter.serverFn("removePreset", function(player, args)
    local name = args and args.name
    if type(name) ~= "string" or name == "" then return "ok" end
    local presets = ownedPresets()
    local verdict = LootSorter.presetDeleteVerdict(presets[name], args.baseGen)
    if verdict == "gone" then return "ok" end           -- already the outcome they wanted
    if verdict ~= "ok" then
        LootSorter.DBG(("preset %s delete refused: %s"):format(name, verdict))
        return verdict, { name = name, action = "delete" }
    end
    presets[name] = nil
    persist()
    LootSorter.DBG("preset removed: " .. name)
    return "ok"
end)

-- isServer, not isAuthority, to match ownedPresets/persist above: single-player's store is the file,
-- so creating the world table there would leave an empty one in the save and report a count of 0
-- however many presets the file holds.
if isServer() then
    -- Make sure the table exists (and so is saved with the world) before anyone writes a preset.
    LootSorter.addOrReplaceHandler(Events.OnInitGlobalModData, "_presetStoreInit", function()
        local store = worldStore()
        local count = 0
        for _ in pairs(store.presets) do count = count + 1 end
        LootSorter.DBG("preset store ready, " .. count .. " preset(s)")
        transmit()
    end)
end

-- Unconditional, and NOT isServer-gated: without it a module that failed to load looks identical to
-- an empty store, and that has to be visible in single-player too.
if LootSorter.isAuthority() then
    print("[Quartermaster] preset commands loaded")
end
