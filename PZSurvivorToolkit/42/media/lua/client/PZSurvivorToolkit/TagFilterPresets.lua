local Tags = require "PZSurvivorToolkit/ItemTags"
local Presets = {}
PZSurvivorToolkit.TagFilterPresets = Presets

local files = {"PZSurvivorToolkit_TagFilters_a.txt", "PZSurvivorToolkit_TagFilters_b.txt"}
local MAGIC, VERSION, MAX_GENERATION = "PZST_TAG_FILTERS", "1", 2147483647
local MAX_PRESETS, MAX_LINE, MAX_BYTES = 32, 62000, 2000000

local function name(value)
    if type(value) ~= "string" or value:find("[%z\1-\31\127]") then return end
    value = value:match("^%s*(.-)%s*$")
    if value == "" or #value > 160 then return end
    return value
end

local function encode(value)
    return value:gsub("%%", "%%25"):gsub("|", "%%7C"):gsub(",", "%%2C")
end

local function decode(value)
    if value:gsub("%%[%x][%x]", ""):find("%", 1, true) then return end
    local valid = true
    local decoded = value:gsub("%%(%x%x)", function(hex)
        local char = ({["25"] = "%", ["7C"] = "|", ["2C"] = ","})[hex:upper()]
        if not char then valid = false; return "" end
        return char
    end)
    if valid then return decoded end
end

local function integer(value, maximum)
    if not value or not value:match("^%d+$") or #value > 10 then return end
    local number = tonumber(value)
    if number and number <= maximum then return number end
end

local function tagList(value)
    local result = {}
    if value == "" then return result end
    for part in (value .. ","):gmatch("(.-),") do
        local id = decode(part)
        if not id or id == "" or #result >= 64 then return end
        result[#result + 1] = id
    end
    return result
end

local function parse(reader)
    local bytes = 0
    local function line()
        local value = reader:readLine()
        if value == nil then return end
        if type(value) ~= "string" or #value > MAX_LINE then return end
        bytes = bytes + #value + 1
        if bytes > MAX_BYTES then return end
        return value
    end
    local header = reader:readLine()
    if header == nil then return nil, "Missing" end
    if type(header) ~= "string" or #header > MAX_LINE then return nil, "Corrupt" end
    bytes = #header + 1
    local version = header:match("^" .. MAGIC .. "|([^|]+)")
    if version and version ~= VERSION then return nil, "Version" end
    if #header > 100 then return nil, "Corrupt" end
    local _, generation, count = header:match("^" .. MAGIC .. "|([^|]+)|([^|]+)|([^|]+)$")
    generation, count = integer(generation, MAX_GENERATION), integer(count, MAX_PRESETS)
    if not generation or generation < 1 or not count then return nil, "Corrupt" end
    local entries, seen = {}, {}
    for index = 1, count do
        local record = line()
        local encodedName, mode, include, exclude
        if record then encodedName, mode, include, exclude = record:match("^P|([^|]*)|([^|]*)|([^|]*)|([^|]*)$") end
        local decodedName = encodedName and decode(encodedName)
        local normalizedName = name(decodedName)
        include, exclude = include and tagList(include), exclude and tagList(exclude)
        if not normalizedName or normalizedName ~= decodedName or seen[normalizedName]
            or not include or not exclude then return nil, "Corrupt" end
        local rule = Tags.normalizeRule({mode = mode, include = include, exclude = exclude})
        if not rule or not Tags.ruleActive(rule) then return nil, "Corrupt" end
        entries[#entries + 1], seen[normalizedName] = {name = normalizedName, rule = rule}, true
    end
    if line() ~= "END|" .. generation .. "|" .. count or reader:readLine() ~= nil then return nil, "Corrupt" end
    table.sort(entries, function(a, b) return a.name < b.name end)
    return {generation = generation, entries = entries}
end

local function readSlot(index)
    -- Create only if absent: native nil readers then always mean I/O failure.
    local ok, reader = pcall(getFileReader, files[index], true)
    if not ok or not reader then return nil, "ReadFailed" end
    local parsed, value, err = pcall(parse, reader)
    local closed = pcall(function() reader:close() end)
    if not parsed or not closed then return nil, "ReadFailed" end
    return value, err
end

local function serialize(entries, generation)
    local lines = {MAGIC .. "|" .. VERSION .. "|" .. generation .. "|" .. #entries}
    for _, entry in ipairs(entries) do
        local lists = {}
        for _, field in ipairs({"include", "exclude"}) do
            local values = {}
            for _, id in ipairs(entry.rule[field]) do values[#values + 1] = encode(id) end
            lists[#lists + 1] = table.concat(values, ",")
        end
        lines[#lines + 1] = "P|" .. encode(entry.name) .. "|" .. entry.rule.mode .. "|" .. lists[1] .. "|" .. lists[2]
    end
    lines[#lines + 1] = "END|" .. generation .. "|" .. #entries
    return table.concat(lines, "\n") .. "\n"
end

local function load()
    local a, aerr = readSlot(1)
    local b, berr = readSlot(2)
    if aerr == "Version" or berr == "Version" then return nil, "Version" end
    if aerr == "ReadFailed" or berr == "ReadFailed" then return nil, "ReadFailed" end
    if not a and not b then
        if aerr ~= "Missing" or berr ~= "Missing" then return nil, "ReadFailed" end
        return {entries = {}, generation = 0, slot = 2}
    end
    if a and b and a.generation == b.generation
        and serialize(a.entries, a.generation) ~= serialize(b.entries, b.generation) then return nil, "ReadFailed" end
    local current = a and (not b or a.generation >= b.generation) and a or b
    current.slot = current == a and 1 or 2
    return current
end

local function write(current)
    if current.generation >= MAX_GENERATION then return nil, "Limit" end
    local generation, target = current.generation + 1, 3 - current.slot
    table.sort(current.entries, function(a, b) return a.name < b.name end)
    local text = serialize(current.entries, generation)
    if #text > MAX_BYTES then return nil, "Limit" end
    local ok, writer = pcall(getFileWriter, files[target], true, false)
    if not ok or not writer then return nil, "WriteFailed" end
    local written = pcall(function() writer:write(text) end)
    local closed = pcall(function() writer:close() end)
    if not written or not closed then return nil, "WriteFailed" end
    local saved = readSlot(target)
    if not saved or saved.generation ~= generation or serialize(saved.entries, generation) ~= text then return nil, "WriteFailed" end
    return true
end

function Presets.list()
    local current, err = load()
    if not current then return nil, err end
    return current.entries
end

function Presets.save(value, incomingRule)
    local normalizedName = name(value)
    if not normalizedName then return nil, "InvalidName" end
    local rule = Tags.normalizeRule(incomingRule)
    if not rule or not Tags.ruleActive(rule) then return nil, "InvalidRule" end
    local current, err = load()
    if not current then return nil, err end
    for _, entry in ipairs(current.entries) do
        if entry.name == normalizedName then entry.rule = rule; return write(current) end
    end
    if #current.entries >= MAX_PRESETS then return nil, "Limit" end
    current.entries[#current.entries + 1] = {name = normalizedName, rule = rule}
    return write(current)
end

function Presets.remove(value)
    local normalizedName = name(value)
    if not normalizedName then return nil, "InvalidName" end
    local current, err = load()
    if not current then return nil, err end
    for index, entry in ipairs(current.entries) do
        if entry.name == normalizedName then table.remove(current.entries, index); return write(current) end
    end
    return true
end

return Presets
