local Tags = require "PZSurvivorToolkit/ItemTags"
local Presets = require "PZSurvivorToolkit/QuartermasterPresets"
local Groups = require "PZSurvivorToolkit/ContainerGroups"

local Rules = {}
PZSurvivorToolkit.QuartermasterTagRules = Rules
local FIELD = "PZSTQuartermasterTagRules"
local REVISIONS = FIELD .. "Revisions"

local function copy(rule)
    return rule and Tags.normalizeRule(rule) or nil
end

function Rules.getBox(obj, ci)
    local group = Groups.resolve(obj, ci)
    if group then return copy(group.rule) end
    local md = obj and obj:getModData()
    return copy(md and type(md[FIELD]) == "table" and md[FIELD][tostring(ci)])
end

function Rules.getBoxRevision(obj, ci)
    local md = obj and obj:getModData()
    return tonumber(md and type(md[REVISIONS]) == "table" and md[REVISIONS][tostring(ci)]) or 0
end

function Rules.presetsSynced()
    return Presets.synced()
end

function Rules.presetStore()
    return Presets.rules()
end

function Rules.getPreset(name, preset)
    local entry = Rules.presetStore()[name]
    if type(entry) ~= "table" or not preset or tostring(entry.gen) ~= tostring(preset.gen) then return nil end
    return copy(entry.rule)
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

local toolRule = {mode = "all", include = {"tool"}, exclude = {}}
local brokenDestinations = {
    broken = {mode = "all", include = {"broken"}, exclude = {}},
    smelting = {mode = "all", include = {"smelting"}, exclude = {}},
}

local function itemMatcher(state)
    if not state.matchRule then state.matchRule = Tags.ruleMatcher(Tags.forItem(state.ref)) end
    return state.matchRule
end

local function itemState(item)
    local ref = item.ref
    local state = {ref = ref}
    if ref and ref.isBroken and ref:isBroken() then
        state.blocked = itemMatcher(state)(toolRule)
    end
    return state
end

local function acceptsBrokenTool(state, rule, matchRule)
    for _, id in ipairs(rule.include) do
        local role = brokenDestinations[id]
        if role then
            state.brokenRoles = state.brokenRoles or {}
            local present = state.brokenRoles[id]
            if present == nil then
                present = matchRule(role)
                state.brokenRoles[id] = present
            end
            if present then return true end
        end
    end
    return false
end

local function matches(box, item, enabled, state)
    -- Ordinary tool selections describe usable items. A broken tool needs a
    -- matching positive Broken/Smelting role; category picks cannot supply it.
    -- Explicit item assignments still take precedence in the planner.
    local blocked = enabled and state.blocked
    if not blocked and item.cat and box.cats and box.cats[item.cat] then return true end
    if not enabled or not box.rules or #box.rules == 0 then return false end
    local matchRule = itemMatcher(state)
    for _, rule in ipairs(box.rules) do
        if matchRule(rule) and (not blocked or acceptsBrokenTool(state, rule, matchRule)) then return true end
    end
    return false
end

-- Standalone reads remain live. Planning uses one private classification of each
-- item while testing its alternative destinations; the next plan starts fresh.
function Rules.matches(box, item)
    local enabled = Tags.enabled()
    return matches(box, item, enabled, enabled and itemState(item))
end

function Rules.matcher()
    local enabled, states = Tags.enabled(), {}
    return function(box, item)
        local state = states[item]
        if enabled and not state then state = itemState(item); states[item] = state end
        return matches(box, item, enabled, state)
    end
end

Rules.FIELD, Rules.REVISIONS = FIELD, REVISIONS
return Rules
