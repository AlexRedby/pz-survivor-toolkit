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

function Presets.install(Rules)
    local owner = LootSorter
    if owner.pzstPresetStorage then return owner.pzstPresetStorage end
    if isClient() or isServer() then error("Quartermaster file storage is single-player only") end
    local state, snapshot, staging = {}, nil, false
    local function load()
        local candidate = Storage.load()
        local presets = candidate.nativeVersion == 1 and copy(candidate.native)
            or translate(candidate.native, owner.getDisplayNameForFullType)
        local rules = decodeRules(candidate.rules)
        owner._presets, Rules.localPresets, snapshot = presets, rules, candidate
        return presets
    end
    local function ensure()
        if not snapshot or not owner._presets or not Rules.localPresets then load() end
    end
    local function save(presets, rules)
        local ok, candidate = pcall(function()
            owner.getItemNames()
            local records = translate(presets, function(item) return owner.getItemFullType(item) or item end)
            return Storage.save(snapshot, records, encodeRules(rules))
        end)
        if not ok then
            -- A complete new slot may exist despite an I/O error; rescan before any later write.
            owner._presets, Rules.localPresets, snapshot = nil, nil, nil
            error(candidate)
        end
        owner._presets, Rules.localPresets, snapshot = presets, rules, candidate
    end
    function state.rules()
        ensure()
        return Rules.localPresets
    end
    function state.save()
        if staging then return end
        ensure()
        save(owner._presets, Rules.localPresets)
    end
    function state.transaction(fn)
        ensure()
        local previous, oldRules = owner._presets, Rules.localPresets
        owner._presets, Rules.localPresets = copy(previous), copy(oldRules)
        staging = true
        local ok, verdict, detail = pcall(fn)
        staging = false
        local presets, rules = owner._presets, Rules.localPresets
        owner._presets, Rules.localPresets = previous, oldRules
        if not ok then error(verdict) end
        if verdict == "ok" then save(presets, rules) end
        return verdict, detail
    end
    owner.loadPresets = load
    owner.savePresets = state.save
    owner._presets, Rules.localPresets = nil, nil
    owner.pzstPresetStorage = state
    return state
end

return Presets
