local schema = require "PZSurvivorToolkit/ItemTagSchema"
local planting = require "PZSurvivorToolkit/PlantingTags"
local categories = require "PZSurvivorToolkit/ItemCategories"
PZSurvivorToolkit = PZSurvivorToolkit or {}
local Tags = {}
PZSurvivorToolkit.ItemTags = Tags

local function signature(tags)
    local result, seen = {}, {}
    for _, id in ipairs(tags) do
        if not seen[id] then result[#result + 1], seen[id] = id, true end
    end
    table.sort(result)
    return table.concat(result, "\0")
end

local reverse = {}
for category, tags in pairs(schema.categories) do
    local key = signature(tags)
    reverse[key] = reverse[key] or {}
    reverse[key][#reverse[key] + 1] = category
end

function Tags.enabled()
    local settings = PZSurvivorToolkit.Settings
    return settings and settings.itemTags and settings.itemTags() or false
end

function Tags.forCategory(category)
    local result = {}
    if not category or category == "" then return result end
    local definition = schema.categories[category] or {"category:" .. category}
    for i, id in ipairs(definition) do result[i] = id end
    -- Distinct legacy aliases can have identical tags (e.g. two 7.62x51 keys).
    result.legacyCategory = category
    return result
end

local function itemTags(category, fullType, script)
    local tags = Tags.forCategory(category)
    local role = planting.role(fullType, script)
    if role then
        for i = #tags, 1, -1 do if tags[i] == "seed" then table.remove(tags, i) end end
        local farming = false
        for _, id in ipairs(tags) do if id == "farming" then farming = true end end
        if not farming then tags[#tags + 1] = "farming" end
        if role == "seed" then tags[#tags + 1] = "seed" end
        tags.itemCategory, tags.itemSignature = category, signature(tags)
    end
    return tags
end

function Tags.forScriptItem(script)
    if not script then return {} end
    return itemTags(categories.forScript(script), script:getFullName(), script)
end

function Tags.forItem(item)
    if not item then return {} end
    -- Import the current instance category every time: fluids and other mods can change it.
    local category = item:getDisplayCategory() or (item.getCategory and item:getCategory())
    return itemTags(category, item.getFullType and item:getFullType(), item.getScriptItem and item:getScriptItem())
end

function Tags.category(tags, originalKey)
    originalKey = originalKey or tags.legacyCategory
    local key = signature(tags)
    if originalKey == tags.itemCategory and key == tags.itemSignature then return originalKey end
    if originalKey and key == signature(Tags.forCategory(originalKey)) then return originalKey end
    local candidates = reverse[key]
    if candidates and #candidates == 1 then return candidates[1] end
    if #tags == 1 and tags[1]:sub(1, 9) == "category:" then return tags[1]:sub(10) end
    -- An arbitrary combination has no lossless legacy equivalent; never invent a category ID.
end

function Tags.label(id)
    if id:sub(1, 9) == "category:" then
        local category = id:sub(10)
        return (getTextOrNull and getTextOrNull("IGUI_ItemCat_" .. category)) or category
    end
    return (getTextOrNull and getTextOrNull("UI_PZST_Tag_" .. id)) or schema.labels[id] or id
end

local function tagSet(categoryOrTags)
    local tags = type(categoryOrTags) == "string" and Tags.forCategory(categoryOrTags) or categoryOrTags
    local present = {}
    for _, id in ipairs(tags or {}) do present[id] = true end
    -- Saved exact-category filters survive a category gaining semantic tags later.
    if tags and type(tags.legacyCategory) == "string" then present["category:" .. tags.legacyCategory] = true end
    return present
end

local function matchesSelection(present, selected, mode)
    local count = 0
    for _, id in ipairs(selected) do
        count = count + 1
        if mode == "any" and present[id] then return true end
        if mode ~= "any" and not present[id] then return false end
    end
    return count == 0 or mode ~= "any"
end

function Tags.matches(categoryOrTags, selected, mode)
    return matchesSelection(tagSet(categoryOrTags), selected, mode)
end

Tags.MAX_RULE_GROUPS = 64
Tags.MAX_RULE_TERMS = 64

local function normalizeGroup(value)
    if type(value) ~= "table" then return nil, "invalid group" end
    for key in pairs(value) do
        if key ~= "include" and key ~= "exclude" then return nil, "unknown group field" end
    end
    local result, included = {}, {}
    for _, field in ipairs({"include", "exclude"}) do
        local source, seen, list, count = value[field], {}, {}, 0
        if source == nil then source = {} end
        if type(source) ~= "table" then return nil, "invalid tag list" end
        for index, id in pairs(source) do
            count = count + 1
            if count > 64 or type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > 64
                or type(id) ~= "string" or #id > 160 or id:find("[%z\1-\31]")
                or (not schema.labels[id] and not id:match("^category:.+")) then
                return nil, "invalid tag"
            end
            if field == "exclude" and included[id] then return nil, "conflicting tags" end
            if not seen[id] then list[#list + 1], seen[id] = id, true end
        end
        -- Sparse network arrays must not silently lose entries through ipairs.
        for index = 1, count do if source[index] == nil then return nil, "sparse tag list" end end
        table.sort(list)
        result[field] = list
        if field == "include" then included = seen end
    end
    return result
end

function Tags.normalizeRule(value)
    if value == nil then return {mode = "all", include = {}, exclude = {}} end
    if type(value) ~= "table" then return nil, "invalid rule" end
    if value.groups ~= nil then
        for key in pairs(value) do if key ~= "groups" then return nil, "unknown rule field" end end
        if type(value.groups) ~= "table" then return nil, "invalid groups" end
        local count, groups = 0, {}
        for index, group in pairs(value.groups) do
            count = count + 1
            if count > 64 or type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > 64 then
                return nil, "invalid group index"
            end
            local normalized, err = normalizeGroup(group)
            if not normalized then return nil, err end
            groups[index] = normalized
        end
        if count == 0 then return nil, "empty groups" end
        for index = 1, count do if value.groups[index] == nil then return nil, "sparse groups" end end
        return {groups = groups}
    end
    for key in pairs(value) do
        if key ~= "mode" and key ~= "include" and key ~= "exclude" then return nil, "unknown rule field" end
    end
    local mode = value.mode == nil and "all" or value.mode
    if mode ~= "all" and mode ~= "any" then return nil, "invalid match mode" end
    local group, err = normalizeGroup({include = value.include, exclude = value.exclude})
    if not group then return nil, err end
    group.mode = mode
    return group
end

-- Expand legacy ANY without moving its global exclusions outside their branches.
function Tags.ruleGroups(rule)
    local normalized, err = Tags.normalizeRule(rule)
    if not normalized then return nil, err end
    if normalized.groups then return normalized.groups end
    if normalized.mode ~= "any" or #normalized.include == 0 then
        return {{include = normalized.include, exclude = normalized.exclude}}
    end
    local groups = {}
    for _, id in ipairs(normalized.include) do
        local excludes = {}
        for index, excluded in ipairs(normalized.exclude) do excludes[index] = excluded end
        groups[#groups + 1] = {include = {id}, exclude = excludes}
    end
    return groups
end

function Tags.fromRuleGroups(groups)
    local normalized, err = Tags.normalizeRule({groups = groups})
    if not normalized then return nil, err end
    groups = normalized.groups
    if #groups == 1 then
        return {mode = "all", include = groups[1].include, exclude = groups[1].exclude}
    end
    local includes, common = {}, signature(groups[1].exclude)
    for _, group in ipairs(groups) do
        if #group.include ~= 1 or signature(group.exclude) ~= common then return normalized end
        includes[#includes + 1] = group.include[1]
    end
    return Tags.normalizeRule({mode = "any", include = includes, exclude = groups[1].exclude})
end

function Tags.ruleIncludes(rule, id)
    local normalized = Tags.normalizeRule(rule)
    if not normalized then return false end
    for _, group in ipairs(normalized.groups or {normalized}) do
        for _, included in ipairs(group.include) do if included == id then return true end end
    end
    return false
end

local function groupShape(group)
    return type(group) == "table" and type(group.include) == "table" and type(group.exclude) == "table"
end

local function groupsShape(groups)
    if type(groups) ~= "table" or #groups < 1 or #groups > Tags.MAX_RULE_GROUPS then return false end
    for index = 1, #groups do if not groupShape(groups[index]) then return false end end
    return true
end

-- Rules are validated at persistence and authority boundaries; matching keeps the
-- existing cheap shape guards and does not copy/sort a rule for every item.
function Tags.ruleActive(rule)
    if type(rule) ~= "table" then return false end
    if rule.groups == nil then
        return groupShape(rule) and (#rule.include > 0 or #rule.exclude > 0)
    end
    if not groupsShape(rule.groups) then return false end
    for _, group in ipairs(rule.groups) do
        if #group.include == 0 and #group.exclude == 0 then return false end
    end
    return true
end

local function matchesGroup(present, group, mode)
    for _, id in ipairs(group.exclude) do if present[id] then return false end end
    return matchesSelection(present, group.include, mode)
end

function Tags.matchesRule(categoryOrTags, rule)
    if type(rule) ~= "table" then return false end
    if rule.groups == nil then
        if (rule.mode ~= "all" and rule.mode ~= "any") or not groupShape(rule) then return false end
        return matchesGroup(tagSet(categoryOrTags), rule, rule.mode)
    end
    if not groupsShape(rule.groups) then return false end
    local present = tagSet(categoryOrTags)
    for _, group in ipairs(rule.groups) do
        if matchesGroup(present, group, "all") then return true end
    end
    return false
end

return Tags
