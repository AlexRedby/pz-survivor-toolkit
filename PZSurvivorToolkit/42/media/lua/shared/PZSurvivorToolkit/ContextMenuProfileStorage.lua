local Proof = require "PZSurvivorToolkit/SourceProof"
local TextFile = require "PZSurvivorToolkit/TextFile"
local Storage = {}
local files = {"PZSurvivorToolkit_ContextMenus_a.txt", "PZSurvivorToolkit_ContextMenus_b.txt"}
local legacy = "PZSurvivorToolkit_ContextMenus.ini"
local MAGIC, LIMIT, MAX_LINE, MAX_GENERATION = "PZST_CONTEXT", 20000000, 8192, 2147483646

local function read(path)
    -- Legacy parsing skips oversized records so valid later preferences survive.
    return TextFile.readLines(path, LIMIT, path ~= legacy and MAX_LINE or nil)
end

local function checksum(values)
    local index = 0
    return Proof.checksum({readLine = function() index = index + 1; return values[index] end}, false, LIMIT)
end

local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" or #a ~= #b then return false end
    for index, line in ipairs(a) do if line ~= b[index] then return false end end
    for index, line in pairs(b) do if line ~= a[index] then return false end end
    return true
end

local function parse(values, slot)
    if #values == 0 then return end
    local version = values[1]:match("^" .. MAGIC .. "|([^|]+)")
    if version and version ~= "1" and version ~= "2" then error("Unsupported context menu profile snapshot version") end
    local generation, count = values[1]:match("^" .. MAGIC .. "|[12]|(%d+)|(%d+)$")
    generation, count = tonumber(generation), tonumber(count)
    if not generation or generation < 1 or generation > MAX_GENERATION
        or not count or count + 2 ~= #values then return end
    local body, lines = {}, {}
    for index = 1, #values - 1 do
        body[index] = values[index]
        if index > 1 then lines[#lines + 1] = values[index] end
    end
    local hash = checksum(body)
    if not hash or values[#values] ~= string.format("END|%d|%d", generation, hash) then return end
    return {lines = lines, version = tonumber(version), generation = generation, slot = slot}
end

function Storage.load()
    local a, b = read(files[1]), read(files[2])
    local first, second = parse(a, 1), parse(b, 2)
    if first and second and first.generation == second.generation and not same(a, b) then
        error("Conflicting context menu profile snapshots")
    end
    if first and (not second or first.generation >= second.generation) then return first end
    if second then return second end
    if #a > 0 and #b > 0 then error("No valid context menu profile snapshot; files retained") end
    -- The untouched legacy file is the prior snapshot when the first migration write is interrupted.
    return {lines = read(legacy), version = 1, generation = 0, slot = 2}
end

function Storage.save(previous, lines, version)
    version = version or 1
    if version ~= 1 and version ~= 2 then error("Unsupported context menu profile snapshot version") end
    local current = Storage.load()
    if type(previous) ~= "table" or current.generation ~= previous.generation
        or current.slot ~= previous.slot or not same(current.lines, previous.lines) then
        error("Context menu profile changed; reload required")
    end
    if current.generation >= MAX_GENERATION then error("Context menu profile sequence exhausted") end
    if type(lines) ~= "table" then error("Invalid context menu profile records") end
    local count, size = 0, 0
    for index, line in pairs(lines) do
        if type(index) ~= "number" or index < 1 or index > #lines or index ~= math.floor(index)
            or type(line) ~= "string" or #line > MAX_LINE or line:find("[\r\n]") then
            error("Invalid context menu profile record")
        end
        count, size = count + 1, size + #line + 1
        if size > LIMIT then error("Context menu profile exceeds storage limit") end
    end
    if count ~= #lines then error("Sparse context menu profile records") end
    local generation, slot = current.generation + 1, 3 - current.slot
    local body = {string.format("%s|%d|%d|%d", MAGIC, version, generation, count)}
    for _, line in ipairs(lines) do body[#body + 1] = line end
    local hash = checksum(body)
    if not hash then error("Invalid context menu profile text or storage limit") end
    body[#body + 1] = string.format("END|%d|%d", generation, hash)
    local text = table.concat(body, "\n") .. "\n"
    if #text > LIMIT then error("Context menu profile exceeds storage limit") end
    TextFile.write(files[slot], text)
    local saved = read(files[slot])
    if table.concat(saved, "\n") .. "\n" ~= text then error("Context menu profile verification failed") end
    local result = parse(saved, slot)
    if not result then error("Context menu profile verification failed") end
    return result
end

return Storage
