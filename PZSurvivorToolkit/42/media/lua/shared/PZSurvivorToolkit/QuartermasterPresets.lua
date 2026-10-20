local Storage = require "PZSurvivorToolkit/QuartermasterPresetStorage"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Presets = {}
local ANY = "__PZST_ANY__"
Presets.STORE = "LootSorter_Presets"
local LEGACY_RULES = "PZSTQuartermasterTagRules"

local function translate(presets, convert)
    local result = {}
    for name, preset in pairs(presets) do
        local cats, items = {}, {}
        for key, value in pairs(preset.cats) do cats[key] = value end
        for key in pairs(preset.items) do
            local item = convert(key)
            if item then items[item] = true end
        end
        result[name] = {cats = cats, items = items, gen = preset.gen, rev = preset.rev, createdBy = preset.createdBy}
    end
    return result
end

local function decodeRules(records)
    local result = {}
    for name, entry in pairs(records) do
        local rule = {mode = entry.items[ANY] and "any" or "all", include = {}, exclude = {}}
        for id in pairs(entry.cats) do rule.include[#rule.include + 1] = id end
        for id in pairs(entry.items) do if id ~= ANY then rule.exclude[#rule.exclude + 1] = id end end
        rule = Tags.normalizeRule(rule)
        if not rule then error("Invalid saved Quartermaster tag rule") end
        result[name] = {rule = rule, gen = entry.gen}
    end
    return result
end

local function encodeRules(presets)
    local records = {}
    for name, entry in pairs(presets) do
        local rule = Tags.normalizeRule(entry.rule)
        if not rule then error("Invalid Quartermaster tag rule") end
        if Tags.ruleActive(rule) then
            local record = {cats = {}, items = {}, gen = entry.gen}
            for _, id in ipairs(rule.include) do record.cats[id] = true end
            for _, id in ipairs(rule.exclude) do record.items[id] = true end
            if rule.mode == "any" then record.items[ANY] = true end
            records[name] = record
        end
    end
    return records
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copy(entry) end
    return result
end

local native, rules, snapshot, received

-- A Host persists and publishes one table. The old sidecar is read only during migration;
-- schema marks that even an empty rules table is authoritative after a later delete.
local function world()
    local store = ModData.getOrCreate(Presets.STORE)
    store.presets = store.presets or {}
    if store.schema == nil then
        local legacy = ModData.getOrCreate(LEGACY_RULES)
        local migrated = {}
        for name, entry in pairs(legacy.presets or {}) do
            local preset = store.presets[name]
            if type(entry) == "table" and preset and tostring(entry.gen) == tostring(preset.gen) then
                local rule = Tags.normalizeRule(entry.rule)
                if rule and Tags.ruleActive(rule) then migrated[name] = {gen = preset.gen, rule = rule} end
            end
        end
        store.rules, store.revision, store.schema = migrated, 0, 1
    end
    assert(store.schema == 1 and type(store.rules) == "table", "Invalid Quartermaster world preset snapshot")
    return store
end

function Presets.publish()
    assert(isServer(), "Only the server publishes Quartermaster presets")
    world()
    ModData.transmit(Presets.STORE)
end

function Presets.resetReceived()
    received = nil
end

function Presets.receive(value)
    if type(value) ~= "table" or value.schema ~= 1 or type(value.presets) ~= "table"
        or type(value.rules) ~= "table" or type(value.revision) ~= "number"
        or value.revision < 0 or value.revision % 1 ~= 0 then return false end
    if received and value.revision <= received.revision then return false end
    received = value
    return true
end

function Presets.synced()
    return not isClient() or received ~= nil
end

local function singlePlayer()
    if isClient() or isServer() then error("Quartermaster file storage is single-player only") end
end

function Presets.load()
    singlePlayer()
    local candidate = Storage.load()
    local loaded = candidate.nativeVersion == 1 and copy(candidate.native)
        or translate(candidate.native, LootSorter.getDisplayNameForFullType)
    local loadedRules = decodeRules(candidate.rules)
    native, rules, snapshot = loaded, loadedRules, candidate
    return native
end

local function ensure()
    singlePlayer()
    if not snapshot then Presets.load() end
end

function Presets.native()
    if isClient() then return received and received.presets or {} end
    if isServer() then return world().presets end
    ensure()
    return native
end

function Presets.rules()
    if isClient() then return received and received.rules or {} end
    if isServer() then return world().rules end
    ensure()
    return rules
end

function Presets.transaction(fn)
    assert(not isClient(), "Only the authority changes Quartermaster presets")
    if isServer() then
        local store = world()
        local draftNative, draftRules = copy(store.presets), copy(store.rules)
        local verdict, detail, nativeChanged, rulesChanged = fn(draftNative, draftRules)
        if verdict ~= "ok" or (nativeChanged == false and rulesChanged == false) then return verdict, detail end
        store.presets, store.rules, store.revision = draftNative, draftRules, store.revision + 1
        Presets.publish()
        return verdict, detail
    end
    ensure()
    local draftNative, draftRules = copy(native), copy(rules)
    local verdict, detail = fn(draftNative, draftRules)
    if verdict ~= "ok" then return verdict, detail end
    local ok, candidate = pcall(function()
        LootSorter.getItemNames()
        local records = translate(draftNative, function(item) return LootSorter.getItemFullType(item) or item end)
        return Storage.save(snapshot, records, encodeRules(draftRules))
    end)
    if not ok then
        -- A complete new slot may exist despite an I/O error; rescan before any later use.
        native, rules, snapshot = nil, nil, nil
        error(candidate)
    end
    native, rules, snapshot = draftNative, draftRules, candidate
    return verdict, detail
end

return Presets
