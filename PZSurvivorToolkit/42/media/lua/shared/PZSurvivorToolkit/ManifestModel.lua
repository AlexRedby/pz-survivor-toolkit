-- Locale-independent, world-owned warehouse snapshots. Names are custom/legacy labels only.
local Categories = require "PZSurvivorToolkit/ItemCategories"
local Custom = require "PZSurvivorToolkit/TagCustomization"
local Cooking = require "PZSurvivorToolkit/ItemCookingTags"
local CookingStates = require "PZSurvivorToolkit/ItemCookingStates"
local Fluids = require "PZSurvivorToolkit/ItemFluidTags"
local Usage = require "PZSurvivorToolkit/ItemUsageTags"
local Model = {SCHEMA = 2, STORE = "LootSorter_Manifest", PAGE_ROWS = 96, PAGE_CONTAINERS = 24,
    PAGE_BYTES = 24000, POLL_MS = 2000}
PZSurvivorToolkit = PZSurvivorToolkit or {}
PZSurvivorToolkit.ManifestModel = Model
-- Lua 5.1 tests index UTF-8 bytes; native Kahlua indexes UTF-16 code units.
local utf8Strings = #"é" > 1
function Model.text(value, limit)
    if type(value) ~= "string" then return nil end
    limit = limit or 512
    if #value <= limit then return value end
    if utf8Strings then
        local cut = limit + 1
        local byte = string.byte(value, cut)
        while cut > 1 and byte and byte >= 128 and byte < 192 do
            cut = cut - 1
            byte = string.byte(value, cut)
        end
        return value:sub(1, cut - 1)
    end
    local left, right = string.byte(value, limit), string.byte(value, limit + 1)
    if left and left >= 55296 and left <= 56319 and right >= 56320 and right <= 57343 then
        limit = limit - 1
    end
    return value:sub(1, limit)
end
function Model.identity(ft, name, cat, media)
    ft, name, cat, media = ft or "", name or "", cat or "", media or ""
    return #ft .. ":" .. ft .. #name .. ":" .. name .. #cat .. ":" .. cat .. #media .. ":" .. media
end
function Model.tagIdentity(delta)
    local ids, out = {}, {}
    for id in pairs(delta or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local operation = delta[id]
        out[#out + 1] = #id .. ":" .. id .. ":" .. operation
    end
    return table.concat(out)
end
function Model.item(item)
    Categories.prepareItem(item)
    local ft = Model.text(item:getFullType())
    if not ft then return nil end
    local name
    if item.isCustomName and item:isCustomName() then
        name = Model.text(item:getDisplayName())
    end
    local mediaIndex = item.getRecordedMediaIndex and item:getRecordedMediaIndex()
    local mediaId
    if type(mediaIndex) == "number" and mediaIndex >= 0 then
        local media = item.getMediaData and item:getMediaData()
        mediaId = media and Model.text(media:getId())
    else mediaIndex = nil end
    local cat = Model.text(item:getDisplayCategory(), 256)
    local mediaKey = mediaId or (mediaIndex and ("#" .. tostring(mediaIndex)))
    local delta = Custom.itemDelta(item)
    local tagKey = Model.tagIdentity(delta)
    local script = item.getScriptItem and item:getScriptItem()
    local ingredient = Cooking.read(script, item)
    if type(ingredient) ~= "boolean" then ingredient = nil end
    local cookingState = CookingStates.read(script, item)
    if cookingState ~= false and cookingState ~= "raw" and cookingState ~= "cooked"
        and cookingState ~= "burnt" then cookingState = nil end
    local fluidState = Fluids.read(script, item)
    if fluidState ~= "none" and fluidState ~= "beverage" and fluidState ~= "alcoholic" then fluidState = nil end
    local usageState = Usage.encode(Usage.read(script, item))
    local key = Model.identity(ft, name, cat, mediaKey)
    if ingredient ~= nil then key = key .. ":ingredient:" .. tostring(ingredient) end
    if cookingState ~= nil then key = key .. ":cookingState:" .. tostring(cookingState) end
    if fluidState ~= nil then key = key .. ":fluidState:" .. fluidState end
    if usageState ~= nil then key = key .. ":usageState:" .. usageState end
    if tagKey ~= "" then key = key .. #tagKey .. ":" .. tagKey end
    return {key = key, ft = ft, name = name, cat = cat,
        ingredient = ingredient, cookingState = cookingState, fluidState = fluidState, usageState = usageState,
        tagDelta = tagKey ~= "" and delta or nil, tagKey = tagKey ~= "" and tagKey or nil,
        mediaId = mediaId, mediaIndex = mediaIndex, n = 1}
end
function Model.header(record)
    return {id = record.id, key = record.key, x = record.x, y = record.y, z = record.z,
        object = record.object, ci = record.ci, kind = record.kind, name = record.name,
        icon = record.icon, color = record.color, sampledAt = record.sampledAt,
        loaded = record.loaded, legacy = record.legacy, entries = {}}
end
return Model
