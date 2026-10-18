local Codec = require "PZSurvivorToolkit/QuartermasterPresetCodec"
local Proof = require "PZSurvivorToolkit/SourceProof"
local TextFile = require "PZSurvivorToolkit/TextFile"
local Storage = {}
local files = {"PZSTQuartermasterPresets_a.txt", "PZSTQuartermasterPresets_b.txt"}
local legacy = {"QuartermasterPresets.txt", "PZSTQuartermasterTagRules.txt"}
local MAGIC, LIMIT = "PZST_QM", 8000000

local function lines(text)
    local result = {}
    for line in (text:gsub("\n$", "") .. "\n"):gmatch("(.-)\n") do result[#result + 1] = line end
    return result
end

local function read(path)
    return TextFile.readLines(path, LIMIT)
end

local function checksum(values)
    local index = 0
    return Proof.checksum({readLine = function() index = index + 1; return values[index] end}, false, LIMIT)
end

local function parse(values, slot)
    if #values == 0 then return end
    local version = values[1]:match("^" .. MAGIC .. "|([^|]+)|")
    if version and version ~= "1" then error("Unsupported Quartermaster snapshot version") end
    local generation, nativeCount, rulesCount = values[1]:match("^" .. MAGIC .. "|1|(%d+)|(%d+)|(%d+)$")
    generation, nativeCount, rulesCount = tonumber(generation), tonumber(nativeCount), tonumber(rulesCount)
    if not generation or generation < 1 or generation > 2147483646 or not nativeCount or not rulesCount
        or nativeCount < 1 or rulesCount < 1 or nativeCount + rulesCount + 2 ~= #values then return end
    local body, native, rules = {}, {}, {}
    for index = 1, #values - 1 do
        body[index] = values[index]
        if index > 1 and index <= nativeCount + 1 then native[#native + 1] = values[index]
        elseif index > nativeCount + 1 then rules[#rules + 1] = values[index] end
    end
    local hash = checksum(body)
    if not hash or values[#values] ~= "END|" .. generation .. "|" .. string.format("%.0f", hash) then return end
    local nativeText, rulesText = table.concat(native, "\n"), table.concat(rules, "\n")
    local presets, nativeVersion = Codec.decode(nativeText)
    local tags, rulesVersion = Codec.decode(rulesText)
    if nativeVersion ~= 2 or rulesVersion ~= 2 then error("Invalid snapshot payload version") end
    return {native = presets, rules = tags, nativeVersion = 2, generation = generation, slot = slot}
end

function Storage.load()
    if isClient() or isServer() then error("Quartermaster file storage is single-player only") end
    local a, b = read(files[1]), read(files[2])
    local first, second = parse(a, 1), parse(b, 2)
    if first and second and first.generation == second.generation and table.concat(a, "\n") ~= table.concat(b, "\n") then
        error("Conflicting Quartermaster snapshots")
    end
    if first and (not second or first.generation >= second.generation) then return first end
    if second then return second end
    if #a > 0 and #b > 0 then error("No valid Quartermaster snapshot; existing files retained") end
    -- A failed first write has no other slot yet; the untouched legacy pair is its prior snapshot.
    if #a > 0 or #b > 0 then print("[PZSurvivorToolkit] Recovering Quartermaster presets from the retained legacy pair") end
    local native, version = Codec.decode(table.concat(read(legacy[1]), "\n"))
    return {native = native, nativeVersion = version,
        rules = Codec.decode(table.concat(read(legacy[2]), "\n")), generation = 0, slot = 2}
end

function Storage.save(previous, native, rules)
    local current = Storage.load()
    if current.generation ~= previous.generation or current.slot ~= previous.slot
        or Codec.encode(current.native) ~= Codec.encode(previous.native)
        or Codec.encode(current.rules) ~= Codec.encode(previous.rules) then error("Quartermaster presets changed; reload required") end
    if current.generation >= 2147483646 then error("Quartermaster snapshot sequence exhausted") end
    local nativeLines, rulesLines = lines(Codec.encode(native)), lines(Codec.encode(rules))
    local generation, slot = current.generation + 1, 3 - current.slot
    local body = {MAGIC .. "|1|" .. generation .. "|" .. #nativeLines .. "|" .. #rulesLines}
    for _, line in ipairs(nativeLines) do body[#body + 1] = line end
    for _, line in ipairs(rulesLines) do body[#body + 1] = line end
    local hash = checksum(body)
    if not hash then error("Quartermaster presets exceed storage limit or contain invalid text") end
    body[#body + 1] = "END|" .. generation .. "|" .. string.format("%.0f", hash)
    local text = table.concat(body, "\n") .. "\n"
    if #text > LIMIT then error("Quartermaster presets exceed storage limit") end
    TextFile.write(files[slot], text)
    local saved = read(files[slot])
    if table.concat(saved, "\n") .. "\n" ~= text then error("Quartermaster snapshot verification failed") end
    local result = parse(saved, slot)
    if not result then error("Quartermaster snapshot verification failed") end
    return result
end

return Storage
