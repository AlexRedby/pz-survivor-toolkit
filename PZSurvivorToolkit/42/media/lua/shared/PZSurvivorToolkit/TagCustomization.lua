-- World-owned tag definitions and additive/removal overrides. Native categories stay untouched.
local schema = require "PZSurvivorToolkit/ItemTagSchema"
PZSurvivorToolkit = PZSurvivorToolkit or {}
local C = {}
PZSurvivorToolkit.TagCustomization = C
C.MODULE, C.FIELD = "PZSTTagCustomization", "PZSTItemTags"
C.MAX_ITEMS, C.MAX_CHANGES, C.MAX_DEFINITIONS, C.MAX_TYPES = 128, 64, 512, 2048
local MAX_INTEGER = 2147483647
local received
local generation = 0
local listeners = {}

function C.integer(value, limit)
    return type(value) == "number" and value == math.floor(value) and math.abs(value) <= (limit or MAX_INTEGER)
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = copy(child) end
    return out
end
C.copy = copy
function C.canonicalId(id) return (schema.aliases or {})[id] or id end
function C.hasEntries(value) for _ in pairs(value) do return true end; return false end

-- Lua 5.1 strings index UTF-8 bytes; native Kahlua indexes UTF-16 code units.
local utf8Strings = #"é" > 1
-- Check character limits and reject malformed encodings before text reaches native controls.
local function safeText(value, chars, bytes)
    if type(value) ~= "string" or value == "" or #value > bytes or value:find("[%z\1-\31\127]") then return false end
    local at, count = 1, 0
    if not utf8Strings then
        while at <= #value do
            local unit = string.byte(value, at)
            if unit >= 55296 and unit <= 56319 then
                local following = string.byte(value, at + 1)
                if not following or following < 56320 or following > 57343 then return false end
                at = at + 1
            elseif unit >= 56320 and unit <= 57343 then return false end
            count, at = count + 1, at + 1
            if count > chars then return false end
        end
        return true
    end
    while at <= #value do
        local first = value:byte(at)
        local length = first < 128 and 1 or first >= 194 and first <= 223 and 2
            or first >= 224 and first <= 239 and 3 or first >= 240 and first <= 244 and 4
        if not length or at + length - 1 > #value then return false end
        for offset = 1, length - 1 do
            local byte = value:byte(at + offset)
            if byte < 128 or byte > 191 then return false end
        end
        local second = value:byte(at + 1)
        if length == 3 and (first == 224 and second < 160 or first == 237 and second > 159)
            or length == 4 and (first == 240 and second < 144 or first == 244 and second > 143) then return false end
        count, at = count + 1, at + length
        if count > chars then return false end
    end
    return true
end

function C.isValidId(id)
    if type(id) ~= "string" or #id > 160 then return false end
    if schema.labels[id] then return true end
    if id:sub(1, 9) == "category:" then return safeText(id:sub(10), 151, 151) end
    return id:match("^custom:%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

function C.customId(id) return C.isValidId(id) and id:sub(1, 7) == "custom:" end

function C.normalizeType(fullType)
    if not safeText(fullType, 160, 160) or not fullType:find(".", 1, true) then return end
    return fullType:lower()
end

function C.normalizeDefinition(value, patch)
    if type(value) ~= "table" then return nil, "invalid definition" end
    local out = {}
    for key in pairs(value) do
        if key ~= "name" and key ~= "color" and key ~= "icon" then return nil, "unknown definition field" end
    end
    if patch and value.name == false then out.name = false
    elseif value.name ~= nil then
        if not safeText(value.name, 80, 320) or not value.name:find("%S") then return nil, "invalid name" end
        out.name = value.name
    end
    if patch and value.color == false then out.color = false
    elseif value.color ~= nil then
        local source = value.color
        if type(source) ~= "table" then return nil, "invalid color" end
        for key in pairs(source) do if key ~= "r" and key ~= "g" and key ~= "b" then return nil, "invalid color" end end
        out.color = {}
        for _, key in ipairs({"r", "g", "b"}) do
            local n = source[key]
            if type(n) ~= "number" or n ~= n or n < 0 or n > 1 then return nil, "invalid color" end
            out.color[key] = n
        end
    end
    if patch and value.icon == false then out.icon = false
    elseif value.icon ~= nil then
        local icon = value.icon
        if type(icon) ~= "string" or #icon > 160 or icon:find("..", 1, true)
            or icon:find("//", 1, true) or not (icon:match("^Item_[%w_%-]+$")
                or icon:match("^media/ui/[%w_/%-]+%.png$")) then return nil, "invalid icon" end
        out.icon = icon
    end
    return out
end

function C.normalizeChanges(value, stored)
    if type(value) ~= "table" then return nil, "invalid changes" end
    local out, count = {}, 0
    for id, operation in pairs(value) do
        count = count + 1
        if count > C.MAX_CHANGES or not C.isValidId(id) or operation ~= "add" and operation ~= "remove"
            and (stored or operation ~= "default") then return nil, "invalid change" end
        local canonical = C.canonicalId(id)
        if canonical == id or value[canonical] == nil then out[canonical] = operation end
    end
    return out
end

function C.empty() return {version=1, revision=0, nextId=1, definitions={}, types={}} end

-- Network/catalog reads are all-or-nothing; malformed entries are never silently dropped.
function C.normalizeCatalog(value)
    if type(value) ~= "table" or value.version ~= 1 or not C.integer(value.revision) or value.revision < 0
        or not C.integer(value.nextId) or value.nextId < 1 or type(value.definitions) ~= "table"
        or type(value.types) ~= "table" then return nil, "invalid catalog" end
    for key in pairs(value) do
        if key ~= "version" and key ~= "revision" and key ~= "nextId" and key ~= "definitions" and key ~= "types" then return nil, "invalid catalog field" end
    end
    local out, count = C.empty(), 0
    out.revision, out.nextId = value.revision, value.nextId
    for id, definition in pairs(value.definitions) do
        count = count + 1
        if count > C.MAX_DEFINITIONS or not C.isValidId(id) then return nil, "invalid definition id" end
        if type(definition) == "table" and definition.deleted == true and C.customId(id) then
            local appearance = {}
            for key, value in pairs(definition) do
                if key ~= "deleted" then appearance[key] = value end
            end
            local clean = C.normalizeDefinition(appearance)
            if not clean then return nil, "invalid tombstone" end
            clean.deleted = true
            out.definitions[id] = clean
        else
            local clean = C.normalizeDefinition(definition)
            if not clean or C.customId(id) and not clean.name then return nil, "invalid definition" end
            local canonical = C.canonicalId(id)
            if canonical == id or value.definitions[canonical] == nil then out.definitions[canonical] = clean end
        end
    end
    count = 0
    for fullType, delta in pairs(value.types) do
        count = count + 1
        local normalized = C.normalizeType(fullType)
        local clean = C.normalizeChanges(delta, true)
        if count > C.MAX_TYPES or normalized ~= fullType or not clean then return nil, "invalid type delta" end
        out.types[fullType] = clean
    end
    return out
end

-- SP reads the live save's ModData each time, never a cached previous-world table.
function C.catalog()
    if isClient() then return received end
    local data = ModData.getOrCreate(C.MODULE)
    if not C.hasEntries(data) then for key, value in pairs(C.empty()) do data[key] = value end end
    return data
end
function C.synced() return not isClient() or received ~= nil end
function C.getRevision() local data = C.catalog(); return data and data.revision or 0 end
-- Local effective state can change when a delayed item State keeps the catalog revision.
function C.cacheRevision() return tostring(C.getRevision()) .. ":" .. tostring(generation) end
function C.snapshot() local data = C.catalog(); return data and copy(data) end
function C.definition(id)
    local data = C.catalog()
    id = C.canonicalId(id)
    local definition = data and data.definitions[id]
    if not definition and data then
        for alias, canonical in pairs(schema.aliases or {}) do
            if canonical == id and data.definitions[alias] then definition = data.definitions[alias]; break end
        end
    end
    return definition and copy(definition) or nil
end
function C.isActive(id)
    if not C.isValidId(id) then return false end
    if not C.customId(id) then return true end
    local definition = C.definition(id)
    return definition ~= nil and not definition.deleted
end
function C.customIds()
    local out, data = {}, C.catalog()
    for id, definition in pairs(data and data.definitions or {}) do
        if C.customId(id) and not definition.deleted then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end
function C.allIds()
    local out, seen = {}, {}
    for id in pairs(schema.labels) do
        id = C.canonicalId(id)
        if not seen[id] then out[#out + 1], seen[id] = id, true end
    end
    local data = C.catalog()
    for id, definition in pairs(data and data.definitions or {}) do
        id = C.canonicalId(id)
        if not seen[id] and not definition.deleted then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end
function C.typeDelta(fullType)
    local data, key = C.catalog(), C.normalizeType(fullType)
    return C.normalizeChanges(data and key and data.types[key] or {}, true) or {}
end
function C.itemDelta(item)
    if not item or not item.hasModData or not item.getModData or not item:hasModData() then return {} end
    return C.normalizeChanges(item:getModData()[C.FIELD] or {}, true) or {}
end
function C.projectSnapshot(baseTags, fullType, delta)
    local result, present = {}, {}
    -- Preserve classification provenance used by lossless legacy projections.
    for key, value in pairs(baseTags or {}) do if type(key) ~= "number" then result[key] = copy(value) end end
    local retired = schema.retiredTags or {}
    local function legacy(id, value)
        result.legacyTags = result.legacyTags or {}
        result.legacyTags[id] = value or nil
    end
    for _, id in ipairs(baseTags or {}) do
        id = C.canonicalId(id)
        if C.isActive(id) and not present[id] then
            if retired[id] then legacy(id, true)
            else result[#result + 1], present[id] = id, true end
        end
    end
    for _, delta in ipairs({C.typeDelta(fullType), C.normalizeChanges(delta or {}, true) or {}}) do
        for index = #result, 1, -1 do
            local id = result[index]
            if delta[id] == "remove" then table.remove(result, index); present[id] = nil end
        end
        local additions = {}
        for id, op in pairs(delta) do
            if retired[id] then legacy(id, op == "add" and C.isActive(id))
            elseif op == "add" and C.isActive(id) and not present[id] then additions[#additions + 1] = id end
        end
        table.sort(additions)
        for _, id in ipairs(additions) do result[#result + 1], present[id] = id, true end
    end
    return result
end
function C.project(baseTags, fullType, item)
    return C.projectSnapshot(baseTags, fullType, C.itemDelta(item))
end
function C.changeDelta(current, changes, reset)
    local delta = reset and {} or C.normalizeChanges(current, true) or {}
    for id, operation in pairs(C.normalizeChanges(changes) or {}) do delta[id] = operation ~= "default" and operation or nil end
    return delta
end
function C.onChange(fn) if type(fn) == "function" then listeners[#listeners + 1] = fn end end
function C.changed(payload)
    generation = generation + 1
    for _, fn in ipairs(listeners) do pcall(fn, payload) end
end
function C.resetReceived() received = nil; C.changed({reset=true}) end
function C.receive(value)
    local clean = C.normalizeCatalog(value)
    if not clean or received and clean.revision < received.revision then return false end
    received = clean
    C.changed({revision=clean.revision})
    return true
end
return C
