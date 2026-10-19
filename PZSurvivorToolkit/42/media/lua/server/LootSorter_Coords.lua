-- The designated-box index ("x,y,z" -> true): the store, its replication, and the two commands that
-- mutate it. Only the authority may write it -- a client-side ModData.transmit is a silent no-op --
-- so clients send deltas as commands. Snapshots would clobber another player's concurrent designation.
--
-- Shared, not server/, for the same reason as LootSorter_Presets.lua: this is authority code, and
-- the caller half must exist on a multiplayer client even though the work never runs there.
LootSorter = LootSorter or {}

local MOD_DATA_KEY = "LootSorter_Registry"


local function getBoxes()
    local registry = ModData.getOrCreate(MOD_DATA_KEY)
    registry.boxes = registry.boxes or {}
    return registry
end

-- nil = "cannot tell" (square not loaded), which the caller treats as "keep the coord".
local function squareHasDesignation(x, y, z)
    local square = getCell() and getCell():getGridSquare(x, y, z)
    if not square then return nil end          -- nil = "cannot tell", not "no"
    local objects = square:getObjects()
    if not objects then return false end
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        if object and object.hasModData and object:hasModData() then
            if LootSorter.modDataHasDesignation(object:getModData()) then return true end
        end
    end
    return false
end

local function transmit()
    pcall(function() ModData.transmit(MOD_DATA_KEY) end)
end

-- transmit sends the whole index to every client, and one gatherBoxes pass can emit many removals.
local function transmitSoon()
    if LootSorter._transmitPending then return end
    LootSorter._transmitPending = true
end

if LootSorter.isAuthority() then
    LootSorter.addOrReplaceHandler(Events.OnTick, "_serverFlushTick", function()
        if not LootSorter._transmitPending then return end
        LootSorter._transmitPending = false
        transmit()
    end)
end

-- Object ModData and the coord travel on separate channels, so a client can inspect a tile before a
-- fresh designation reaches it and ask to drop a box that does exist.
local function withinGracePeriod(key)
    local addedAt = LootSorter._coordAddedAt and LootSorter._coordAddedAt[key]
    if not addedAt then return false end
    return (getTimestampMs() - addedAt) < LootSorter.ADD_GRACE_MS
end

local function markAdded(key)
    LootSorter._coordAddedAt = LootSorter._coordAddedAt or {}
    LootSorter._coordAddedAt[key] = getTimestampMs()
end

-- Derive the square from the key, never from client-sent coords: it keeps the check honest and
-- guarantees numbers reach getGridSquare, which throws on anything else.
LootSorter.addCoord = LootSorter.serverFn("addCoord", function(player, args)
    local key = args and args.key
    local x = LootSorter.parseCoordKey(key)
    if not x then return "badKey" end               -- unparseable key names no real square
    local registry = getBoxes()
    markAdded(key)                                  -- refresh the grace window even if known
    if registry.boxes[key] then return "ok" end     -- already known, don't re-broadcast
    registry.boxes[key] = true
    transmit()                                      -- immediate: a user is waiting to see it
    return "ok"
end)

-- Verified rather than trusted: dropping a coord removes the box for every player, so refuse unless
-- the server agrees the square really is undesignated. Returns nothing per key -- a self-heal pass
-- sends whatever it could not account for and does not care which ones the server kept.
local function dropOne(registry, key)
    if not key or not registry.boxes[key] then return end        -- already gone is what they wanted
    if withinGracePeriod(key) then
        LootSorter.DBG("removeCoord " .. tostring(key) .. " refused: added too recently")
        return
    end
    local x, y, z = LootSorter.parseCoordKey(key)
    if not x then                                   -- can't name a square, so nothing to verify
        registry.boxes[key] = nil
        LootSorter.DBG("dropped malformed coord " .. tostring(key))
        return true
    end
    local stillDesignated = squareHasDesignation(x, y, z)
    if stillDesignated == false then
        registry.boxes[key] = nil
        if LootSorter._coordAddedAt then LootSorter._coordAddedAt[key] = nil end
        return true
    elseif stillDesignated == nil then
        LootSorter.DBG("removeCoord " .. tostring(key) .. " ignored: square not loaded server-side")
        return
    end
    LootSorter.DBG("removeCoord " .. tostring(key) .. " refused: box still designated")
end

-- Takes a LIST: a self-heal pass finds stale coords in bursts, and one command with twenty keys beats
-- twenty commands. Verification is per key; only the broadcast is shared.
LootSorter.removeCoords = LootSorter.serverFn("removeCoords", function(player, args)
    local keys = args and args.keys
    if type(keys) ~= "table" then return "ok" end
    local registry = getBoxes()
    local dropped = 0
    for _, key in ipairs(keys) do
        if type(key) == "string" and dropOne(registry, key) then dropped = dropped + 1 end
    end
    if dropped > 0 then transmitSoon() end          -- coalesced: one flush however many keys came in
    return "ok"
end)

-- Make sure the table exists (and so is saved with the world) even before anyone designates.
if LootSorter.isAuthority() then
    LootSorter.addOrReplaceHandler(Events.OnInitGlobalModData, "_serverOnInitGlobalModData", function()
        local registry = getBoxes()
        local count = 0
        for _ in pairs(registry.boxes) do count = count + 1 end
        LootSorter.DBG("registry ready, " .. count .. " designated coord(s)")
        transmit()
    end)

    -- Unconditional: without it, a module that failed to load looks identical to an empty index.
    print("[Quartermaster] coord commands loaded")
end
