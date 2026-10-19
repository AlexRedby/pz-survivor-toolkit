-- LootSorter shared utilities, auto-loaded from media/lua/shared.
-- Debug-specific helpers (isDebug / DBG / describeContainer) live in LootSorter_Debug.lua.
local Tags = require "PZSurvivorToolkit/ItemTags"
LootSorter = LootSorter or {}

-- Unregister a handler and forget it. Safe when nothing is registered, so a file whose handler has
-- been retired can still tear down the one an earlier load left behind.
function LootSorter.removeHandler(event, key)
    local previous = LootSorter[key]
    if previous then event.Remove(previous) end
    LootSorter[key] = nil
end

-- Register an event handler so reloading the file REPLACES it instead of stacking another copy.
-- key names the slot on LootSorter, because a fresh closure cannot identify the one it supersedes.
function LootSorter.addOrReplaceHandler(event, key, fn)
    LootSorter.removeHandler(event, key)
    LootSorter[key] = fn
    event.Add(fn)
end

-- Run fn in a pcall; return its result, or dflt if it errored or returned nil. Keeps engine-poking
-- diagnostics (getType/getParent/isExistYet/...) from throwing.
function LootSorter.safeCall(fn, dflt)
    local ok, v = pcall(fn)
    if ok and v ~= nil then return v end
    return dflt
end

-- An item's inventory icon, by full type ("Base.Axe"), or nil. Cached per type -- resolving a script
-- item every frame for every visible row is the one place a list draw gets expensive. A failed lookup
-- caches as false so it isn't retried on every frame either.
local textureCache = {}
function LootSorter.itemTexture(fullType)
    if not fullType then return nil end
    local cached = textureCache[fullType]
    if cached ~= nil then return cached or nil end
    local texture = false
    pcall(function()
        local manager = getScriptManager()
        local script = manager.getItem and manager:getItem(fullType)
            or (manager.FindItem and manager:FindItem(fullType))
        if script and script.getNormalTexture then texture = script:getNormalTexture() end
    end)
    textureCache[fullType] = texture
    return texture or nil
end

-- Any designation at all? Must look inside: clearing one leaves an empty table behind, and an empty
-- table is truthy. Counts preset-linked boxes without resolving them, since the preset store is
-- client-only -- so the server can use this too.
function LootSorter.modDataHasDesignation(modData)
    if type(modData) ~= "table" then return false end
    for _, field in ipairs({ "LSBox", "LSBoxItems", "LSBoxPresets" }) do
        local perContainer = modData[field]
        if type(perContainer) == "table" then
            for _, set in pairs(perContainer) do
                if type(set) == "table" then
                    for _, on in pairs(set) do
                        if on then return true end
                    end
                end
            end
        end
    end
    for _, rule in pairs(type(modData.PZSTQuartermasterTagRules) == "table" and modData.PZSTQuartermasterTagRules or {}) do
        if Tags.ruleActive(Tags.normalizeRule(rule)) then return true end
    end
    return false
end

-- Does any object on this square carry a designation? Deliberately does NOT resolve presets: a
-- client whose preset store hasn't synced would otherwise read a presets-only box as undesignated
-- and drop its coord for everyone. hasModData() avoids instantiating ModData on every wall it sees.
function LootSorter.squareHasDesignation(square)
    if not square then return false end
    local objects = square:getObjects()
    if not objects then return false end
    for index = 0, objects:size() - 1 do
        local object = objects:get(index)
        if object and object.hasModData and object:hasModData() then
            if LootSorter.modDataHasDesignation(object:getModData()) then return true end
        end
    end
    return false
end

-- "x,y,z" -> numbers, or nil if it isn't a coordinate key.
function LootSorter.parseCoordKey(key)
    if type(key) ~= "string" then return nil end
    local x, y, z = key:match("^(-?%d+),(-?%d+),(-?%d+)$")
    if not x then return nil end
    return tonumber(x), tonumber(y), tonumber(z)
end

-- Can this player loot containers on that square? Vanilla's own gate, used the same way it uses it in
-- ISInventoryPage: safehouses only exist in multiplayer, so single-player is always allowed. Wrapped
-- because a nil square or a missing SafeHouse class must not deny access -- failing closed here would
-- silently hide every box.
function LootSorter.canLootSquare(square, player)
    if not isClient() then return true end
    if not square or not player then return true end
    -- Only an explicit false denies. Comparing == true would also deny on any unexpected return,
    -- which would silently hide every box in the game -- the exact outcome this must never produce.
    local allowed = true
    pcall(function()
        if SafeHouse.isSafehouseAllowLoot(square, player) == false then allowed = false end
    end)
    return allowed
end
