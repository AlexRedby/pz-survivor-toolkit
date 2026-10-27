local schema = require "PZSurvivorToolkit/ItemTagSchema"
local planting = require "PZSurvivorToolkit/PlantingTags"
local categories = require "PZSurvivorToolkit/ItemCategories"
local properties = require "PZSurvivorToolkit/ItemTagProperties"
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

function Tags.requiresItemRule(id)
    -- Content and freshness depend on the physical instance, even when all
    -- script defaults in a legacy category currently agree.
    if id == "fresh" or id == "stale" or id == "rotten" then return true end
    return id == "readable" or id == "literature" or id == "writeable"
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

local function setTag(tags, id, value)
    if value == nil then return false end
    for i, existing in ipairs(tags) do
        if existing == id then
            if not value then table.remove(tags, i); return true end
            return false
        end
    end
    if value then tags[#tags + 1] = id; return true end
    return false
end

local function itemTags(category, fullType, script, item)
    local tags = Tags.forCategory(category)
    local override = fullType and schema.items[string.lower(tostring(fullType))]
    if override then
        tags = {legacyCategory = category}
        for i, id in ipairs(override) do tags[i] = id end
    end
    local role = planting.role(fullType, script)
    if role then
        for i = #tags, 1, -1 do if tags[i] == "seed" then table.remove(tags, i) end end
        local farming = false
        for _, id in ipairs(tags) do if id == "farming" then farming = true end end
        if not farming then tags[#tags + 1] = "farming" end
        if role == "seed" then tags[#tags + 1] = "seed" end
    end
    local wearable, container, furniture = properties.read(script, item)
    local refined = setTag(tags, "wearable", wearable)
    if container then refined = setTag(tags, "container", true) or refined end
    if furniture then refined = setTag(tags, "furniture", true) or refined end
    local readable, recreational, writeable = properties.reading(script, item)
    if fullType and schema.readableItems[string.lower(tostring(fullType))] then readable = true end
    refined = setTag(tags, "readable", readable) or refined
    refined = setTag(tags, "literature", recreational) or refined
    refined = setTag(tags, "writeable", writeable) or refined
    -- Unreadable papers must not fall back to the old Literature category text.
    if readable == false and #tags == 0 then refined = setTag(tags, "miscellaneous", true) or refined end
    local freshness, perishable, foodStates = properties.food(script, item)
    if perishable ~= nil then
        refined = setTag(tags, "perishable", perishable) or refined
        refined = setTag(tags, "nonperishable", not perishable) or refined
        if freshness then refined = setTag(tags, freshness, true) or refined end
        tags.foodStates = foodStates
    end
    if override or role or refined then tags.itemCategory, tags.itemSignature = category, signature(tags) end
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
    return itemTags(category, item.getFullType and item:getFullType(), item.getScriptItem and item:getScriptItem(), item)
end

-- Menu availability is distinct from actual item matching. A player can choose
-- Rotten before any food has spoiled, without labelling fresh items as rotten.
function Tags.choices(tags)
    local result = {}
    for _, id in ipairs(tags) do result[#result + 1] = id end
    for _, id in ipairs(tags.foodStates or {}) do setTag(result, id, true) end
    return result
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

local formerGeneral = {Bag = true, Bear = true, containerGeneral = true}
local function tagSet(categoryOrTags)
    local tags = type(categoryOrTags) == "string" and Tags.forCategory(categoryOrTags) or categoryOrTags
    local present = {}
    for _, id in ipairs(tags or {}) do present[id] = true end
    -- Saved exact-category filters survive a category gaining semantic tags later.
    if tags and type(tags.legacyCategory) == "string" then
        present["category:" .. tags.legacyCategory] = true
        -- Hide the redundant General chip without broadening or breaking saved rules.
        if formerGeneral[tags.legacyCategory] then present.general = true end
    end
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

function Tags.normalizeRule(value)
    if value == nil then return {mode = "all", include = {}, exclude = {}} end
    if type(value) ~= "table" then return nil, "invalid rule" end
    for key in pairs(value) do
        if key ~= "mode" and key ~= "include" and key ~= "exclude" then return nil, "unknown rule field" end
    end
    local mode = value.mode == nil and "all" or value.mode
    if mode ~= "all" and mode ~= "any" then return nil, "invalid match mode" end
    local result, included = {mode = mode}, {}
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

function Tags.ruleActive(rule)
    return type(rule) == "table" and type(rule.include) == "table" and type(rule.exclude) == "table"
        and (#rule.include > 0 or #rule.exclude > 0)
end

function Tags.matchesRule(categoryOrTags, rule)
    if type(rule) ~= "table" or (rule.mode ~= "all" and rule.mode ~= "any")
        or type(rule.include) ~= "table" or type(rule.exclude) ~= "table" then return false end
    local present = tagSet(categoryOrTags)
    for _, id in ipairs(rule.exclude) do if present[id] then return false end end
    return #rule.include == 0 or matchesSelection(present, rule.include, rule.mode)
end

function Tags.matchesScriptRule(script, rule)
    local tags = Tags.forScriptItem(script)
    -- Scripts have no current age. Preview types that can match in at least one
    -- state; never put mutually exclusive states on the same imagined item.
    for _, state in ipairs(tags.foodStates or {}) do
        tags[#tags + 1] = state
        local matches = Tags.matchesRule(tags, rule)
        table.remove(tags)
        if matches then return true end
    end
    if tags.foodStates and #tags.foodStates > 0 then return false end
    return Tags.matchesRule(tags, rule)
end

return Tags
