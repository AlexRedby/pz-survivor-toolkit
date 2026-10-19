local Storage = require "PZSurvivorToolkit/QuartermasterPresetStorage"
local Tags = require "PZSurvivorToolkit/ItemTags"
local Presets = {}
local ANY = "__PZST_ANY__"

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

local native, rules, snapshot

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
    ensure()
    return native
end

function Presets.rules()
    ensure()
    return rules
end

function Presets.transaction(fn)
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
