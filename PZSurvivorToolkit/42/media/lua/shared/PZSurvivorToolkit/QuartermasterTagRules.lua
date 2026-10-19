local Tags = require "PZSurvivorToolkit/ItemTags"

local Rules = {}
PZSurvivorToolkit.QuartermasterTagRules = Rules
local FIELD, STORE = "PZSTQuartermasterTagRules", "PZSTQuartermasterTagRules"
local REVISIONS = FIELD .. "Revisions"

local function copy(rule)
    return rule and Tags.normalizeRule(rule) or nil
end

function Rules.getBox(obj, ci)
    local md = obj and obj:getModData()
    return copy(md and type(md[FIELD]) == "table" and md[FIELD][tostring(ci)])
end

function Rules.getBoxRevision(obj, ci)
    local md = obj and obj:getModData()
    return tonumber(md and type(md[REVISIONS]) == "table" and md[REVISIONS][tostring(ci)]) or 0
end

function Rules.presetsSynced()
    return not isClient() or Rules.received ~= nil
end

function Rules.presetStore()
    if isClient() then return Rules.received or {} end
    if isServer() then
        local store = ModData.getOrCreate(STORE)
        store.presets = store.presets or {}
        return store.presets
    end
    return require("PZSurvivorToolkit/QuartermasterPresets").rules()
end

function Rules.getPreset(name, preset)
    local entry = Rules.presetStore()[name]
    if type(entry) ~= "table" or not preset or tostring(entry.gen) ~= tostring(preset.gen) then return nil end
    return copy(entry.rule)
end

function Rules.scriptItems()
    local items = getAllItems and getAllItems()
    local result = {}
    if items then
        for i = 0, items:size() - 1 do
            local script = items:get(i)
            if script and (not script.getObsolete or not script:getObsolete()) then result[#result + 1] = script end
        end
    end
    return result
end

function Rules.forBox(obj, ci, links, presets)
    local rules = {}
    if not Tags.enabled() then return rules end
    local function include(rule)
        if Tags.ruleActive(rule) then rules[#rules + 1] = rule end
    end
    include(Rules.getBox(obj, ci))
    for name, link in pairs(links or {}) do
        local preset = presets and presets[name]
        if LootSorter.linkResolves(preset, link) then include(Rules.getPreset(name, preset)) end
    end
    return rules
end

function Rules.matches(box, item)
    -- Tag/category selections describe usable tools. Explicit item assignments still
    -- take precedence in the planner, so broken tools can be collected separately.
    local ref = item.ref
    if Tags.enabled() and ref and ref.isBroken and ref:isBroken()
        and Tags.matches(Tags.forItem(ref), {"tool"}) then return false end
    if item.cat and box.cats and box.cats[item.cat] then return true end
    if not Tags.enabled() or not box.rules or #box.rules == 0 then return false end
    local tags = Tags.forItem(item.ref)
    for _, rule in ipairs(box.rules) do
        if Tags.matchesRule(tags, rule) then return true end
    end
    return false
end

Rules.FIELD, Rules.STORE, Rules.REVISIONS = FIELD, STORE, REVISIONS
return Rules
