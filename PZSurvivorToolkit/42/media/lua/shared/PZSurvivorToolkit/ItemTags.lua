local schema = require "PZSurvivorToolkit/ItemTagSchema"
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

function Tags.forItem(item)
    -- Import the current instance category every time: fluids and other mods can change it.
    return Tags.forCategory(item and (item:getDisplayCategory() or item:getCategory()))
end

function Tags.category(tags, originalKey)
    originalKey = originalKey or tags.legacyCategory
    local key = signature(tags)
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

function Tags.matches(categoryOrTags, selected, mode)
    local tags = type(categoryOrTags) == "string" and Tags.forCategory(categoryOrTags) or categoryOrTags
    local present = {}
    for _, id in ipairs(tags or {}) do present[id] = true end
    local count = 0
    for _, id in ipairs(selected) do
        count = count + 1
        if mode == "any" and present[id] then return true end
        if mode ~= "any" and not present[id] then return false end
    end
    return count == 0 or mode ~= "any"
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
    local tags = type(categoryOrTags) == "string" and Tags.forCategory(categoryOrTags) or categoryOrTags
    for _, id in ipairs(rule.exclude) do if Tags.matches(tags, {id}) then return false end end
    return #rule.include == 0 or Tags.matches(tags, rule.include, rule.mode)
end

return Tags
