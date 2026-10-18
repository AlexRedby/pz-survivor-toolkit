local Proof = {}
local utf8Strings = string.byte("洗") == 230

local function hash(reader, adler, limit)
    local value, sum, units = adler and 1 or 5381, 0, 0
    local function add(code)
        units = units + 1
        if units > limit then return false end
        if adler then
            value = (value + code) % 65521
            sum = (sum + value) % 65521
        else
            value = (value * 33 + code) % 4294967296
        end
        return true
    end
    while true do
        local line = reader:readLine()
        if line == nil then break end
        if type(line) ~= "string" then return end
        local i = 1
        while i <= #line do
            local code = string.byte(line, i)
            if utf8Strings and code >= 128 then
                local count
                if code >= 194 and code < 224 then count = 2
                elseif code >= 224 and code < 240 then count = 3
                elseif code >= 240 and code <= 244 then count = 4
                else return end
                code = code % (2 ^ (7 - count))
                for offset = 1, count - 1 do
                    local nextByte = string.byte(line, i + offset)
                    if not nextByte or nextByte < 128 or nextByte > 191 then return end
                    code = code * 64 + nextByte % 64
                end
                if (count == 3 and code < 2048) or (count == 4 and code < 65536)
                    or code > 1114111 or (code >= 55296 and code <= 57343) then return end
                i = i + count - 1
                if code > 65535 then
                    code = code - 65536
                    if not add(55296 + math.floor(code / 1024)) then return end
                    code = 56320 + code % 1024
                end
            end
            if not add(code) then return end
            i = i + 1
        end
        -- Java readLine strips line endings; pins include one LF per returned line.
        if not add(10) then return end
    end
    return adler and sum * 65536 + value or value
end

function Proof.matches(path, expected, mod, adler, limit)
    local input = mod and getModFileReader or getGameFilesInput
    if type(input) ~= "function" or type(expected) ~= "number" then return false end
    local opened, reader
    if mod then opened, reader = pcall(input, mod, path, false)
    else opened, reader = pcall(input, path) end
    if not opened or not reader then return false end
    local valid, checksum = pcall(hash, reader, adler, limit or 2000000)
    local closed = pcall(function() reader:close() end)
    return valid and closed and checksum ~= nil and checksum == expected
end

function Proof.closure(callback, filename)
    if type(callback) ~= "function" or type(getFilenameOfClosure) ~= "function" then return false end
    local ok, source = pcall(getFilenameOfClosure, callback)
    return ok and type(source) == "string" and source:gsub("\\", "/"):match("([^/]+)$") == filename
end

return Proof
