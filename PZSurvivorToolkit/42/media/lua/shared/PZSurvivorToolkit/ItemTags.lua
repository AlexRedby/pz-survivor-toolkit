local schema = require "PZSurvivorToolkit/ItemTagSchema"
local planting = require "PZSurvivorToolkit/PlantingTags"
local categories = require "PZSurvivorToolkit/ItemCategories"
local properties = require "PZSurvivorToolkit/ItemTagProperties"
local media = require "PZSurvivorToolkit/ItemMediaTags"
local disassembly = require "PZSurvivorToolkit/ItemDisassemblyTags"
local cooking = require "PZSurvivorToolkit/ItemCookingTags"
local cookingStates = require "PZSurvivorToolkit/ItemCookingStates"
local Custom = require "PZSurvivorToolkit/TagCustomization"
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
    if id == "fresh" or id == "stale" or id == "rotten" or id == "edible" or id == "dismantle"
        or id == "experience" or id == "recipe" or id == "ingredient"
        or id == "raw" or id == "cooked" or id == "burnt" then return true end
    return id == "readable" or id == "literature" or id == "writeable"
end

function Tags.forCategory(category)
    local result = {}
    if not category or category == "" then return result end
    local definition = schema.categories[category] or {"category:" .. category}
    for i, id in ipairs(definition) do result[i] = id end
    for id, categories in pairs(schema.retiredCategories or {}) do
        if categories[category] then
            result.legacyTags = result.legacyTags or {}
            result.legacyTags[id] = true
        end
    end
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

local function itemTags(category, fullType, script, item, recording, snapshot, snapshotIngredient, snapshotCookingState)
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
    local wearable, container, furniture, fluid = properties.read(script, item)
    local refined = setTag(tags, "wearable", wearable)
    if container then refined = setTag(tags, "container", true) or refined end
    if furniture then refined = setTag(tags, "furniture", true) or refined end
    if fluid then refined = setTag(tags, "liquid", true) or refined end
    refined = setTag(tags, "edible", properties.edible(script, item)) or refined
    local ingredient
    if snapshot and type(snapshotIngredient) == "boolean" then ingredient = snapshotIngredient
    else ingredient = cooking.read(script, item, snapshot) end
    refined = setTag(tags, "ingredient", ingredient) or refined
    local cookingState, possibleCookingStates
    if snapshot then cookingState = snapshotCookingState
    else cookingState, possibleCookingStates = cookingStates.read(script, item) end
    if cookingState ~= nil then
        for _, id in ipairs({"raw", "cooked", "burnt"}) do
            refined = setTag(tags, id, cookingState == id) or refined
        end
    end
    tags.cookingStates = possibleCookingStates
    local canDismantle, skills = disassembly.read(script, item)
    refined = setTag(tags, "dismantle", canDismantle) or refined
    for _, id in ipairs(skills or {}) do refined = setTag(tags, id, true) or refined end
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
    local experience, recipe, mediaStates
    if snapshot then
        if recording then experience, recipe = media.effects(recording)
        elseif script and script.getRecordedMediaCat then
            local carrier = script:getRecordedMediaCat()
            if carrier and tostring(carrier) ~= "" then experience, recipe = false, false end
        end
    else experience, recipe, mediaStates = media.read(script, item) end
    refined = setTag(tags, "experience", experience) or refined
    refined = setTag(tags, "recipe", recipe) or refined
    tags.mediaStates = mediaStates
    if override or role or refined then tags.itemCategory, tags.itemSignature = category, signature(tags) end
    return tags
end

function Tags.automaticForScriptItem(script)
    if not script then return {} end
    return itemTags(categories.forScript(script), script:getFullName(), script)
end

function Tags.automaticForItem(item)
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
    for _, id in ipairs(tags.cookingStates or {}) do setTag(result, id, true) end
    for _, state in ipairs(tags.mediaStates or {}) do
        if state.experience then setTag(result, "experience", true) end
        if state.recipe then setTag(result, "recipe", true) end
    end
    return result
end

function Tags.forScriptItem(script)
    if not script then return {} end
    return Custom.project(Tags.automaticForScriptItem(script), script:getFullName())
end

function Tags.forItem(item)
    if not item then return {} end
    return Custom.project(Tags.automaticForItem(item), item.getFullType and item:getFullType(), item)
end

-- Serialized rows have no InventoryItem. Use script capabilities and the captured
-- recording, without invoking predicates that require a live native item.
function Tags.forSnapshot(script, fullType, category, recording, tagDelta, ingredient, cookingState)
    return Custom.projectSnapshot(itemTags(category, fullType, script, nil, recording, true, ingredient, cookingState), fullType, tagDelta)
end

-- Cache only automatic script tags. World custom definitions are merged live.
local automaticIds, automaticManager, automaticCount
local function loadedAutomaticIds()
    if not getScriptManager then return {} end
    local manager = getScriptManager()
    if not manager or not manager.getAllItems then return {} end
    local scripts = manager:getAllItems()
    if not scripts or not scripts.size or not scripts.get then return {} end
    local count = scripts:size()
    if automaticIds and automaticManager == manager and automaticCount == count then return automaticIds end
    local ids = {}
    for index = 0, count - 1 do
        local script = scripts:get(index)
        for _, id in ipairs(Tags.automaticForScriptItem(script)) do ids[id] = true end
    end
    automaticIds, automaticManager, automaticCount = ids, manager, count
    return ids
end

function Tags.allIds(items)
    local ids, seen = {}, {}
    local function add(id)
        if id ~= "general" and not (schema.retiredTags or {})[id] and not seen[id] then
            ids[#ids + 1], seen[id] = id, true
        end
    end
    for _, id in ipairs(Custom.allIds()) do add(id) end
    for id in pairs(loadedAutomaticIds()) do add(id) end
    for _, item in ipairs(items or {}) do
        for _, id in ipairs(Tags.automaticForItem(item)) do add(id) end
    end
    table.sort(ids)
    return ids
end
function Tags.revision() return Custom.cacheRevision() end
function Tags.signature(tags)
    local ids = {}
    for _, id in ipairs(tags) do ids[#ids + 1] = id end
    -- Stack partitions must preserve saved-rule membership even for retired tags.
    for id, value in pairs(tags.legacyTags or {}) do if value then ids[#ids + 1] = id end end
    return signature(ids)
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
    local definition = Custom.definition(id)
    if definition and definition.name then
        local label = definition.name
        if definition.deleted then
            label = label .. " (" .. ((getTextOrNull and getTextOrNull("UI_PZST_TagEdit_Deleted")) or "Deleted") .. ")"
        end
        return label
    end
    return Tags.defaultLabel(id)
end

function Tags.defaultLabel(id)
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
    for id, value in pairs(tags and tags.legacyTags or {}) do if value then present[id] = true end end
    -- Saved exact-category filters survive a category gaining semantic tags later.
    if tags and schema.categories[tags.legacyCategory] then
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
                or not Custom.isValidId(id) then
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

local function validRule(rule)
    return type(rule) == "table" and (rule.mode == "all" or rule.mode == "any")
        and type(rule.include) == "table" and type(rule.exclude) == "table"
end

local function matchesRule(present, rule)
    for _, id in ipairs(rule.exclude) do if present[id] then return false end end
    return #rule.include == 0 or matchesSelection(present, rule.include, rule.mode)
end

function Tags.matchesScriptRule(script, rule)
    if not script then return false end
    local tags = Tags.automaticForScriptItem(script)
    -- Scripts have no current age or cooking flags. Match one coherent possible
    -- item at a time, then apply the same manual corrections as for live items.
    local function matchesFoodStates(burnt)
        for _, state in ipairs(tags.foodStates or {}) do
            -- Burnt food loses Fresh/Stale but may still be Rotten. A pre-rot
            -- burnt item has no freshness tag, not a fabricated Fresh state.
            local visible = not burnt or state == "rotten"
            if visible then tags[#tags + 1] = state end
            local matches = Tags.matchesRule(Custom.project(tags, script:getFullName()), rule)
            if visible then table.remove(tags) end
            if matches then return true end
        end
        if tags.foodStates and #tags.foodStates > 0 then return false end
        return Tags.matchesRule(Custom.project(tags, script:getFullName()), rule)
    end
    local function matchesCookingStates()
        for _, state in ipairs(tags.cookingStates or {}) do
            for _, id in ipairs({"raw", "cooked", "burnt"}) do setTag(tags, id, state == id) end
            if matchesFoodStates(state == "burnt") then return true end
        end
        if tags.cookingStates and #tags.cookingStates > 0 then return false end
        return matchesFoodStates(false)
    end
    -- A carrier preview must use one real recording's combination of effects.
    -- Project manual changes after these automatic possibilities, just as for live items.
    if tags.mediaStates then
        for _, state in ipairs(tags.mediaStates) do
            setTag(tags, "experience", state.experience)
            setTag(tags, "recipe", state.recipe)
            if matchesCookingStates() then return true end
        end
        return false
    end
    return matchesCookingStates()
end

function Tags.matchesRule(categoryOrTags, rule)
    if not validRule(rule) then return false end
    return matchesRule(tagSet(categoryOrTags), rule)
end

-- A private snapshot for callers comparing one classification against many rules.
-- Keep it within the current operation; ordinary matchesRule reads remain live.
function Tags.ruleMatcher(categoryOrTags)
    local present = tagSet(categoryOrTags)
    return function(rule) return validRule(rule) and matchesRule(present, rule) end
end

return Tags
