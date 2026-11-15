local Storage = {}
local optionsPath = "ModOptions.ini"
local recoveryPath = "PZSurvivorToolkitModOptionsRecovery.ini"
local reloadNeeded = false

-- A single, sealed before-image protects only Toolkit's native ModOptions saves.
-- Closed native readers preserve lines, not their original LF/CRLF spelling.
local function checksum(lines)
    local a, b = 1, 0
    for _, line in ipairs(lines) do
        for index = 1, #line do
            a = (a + line:byte(index)) % 65521
            b = (b + a) % 65521
        end
        a = (a + 10) % 65521
        b = (b + a) % 65521
    end
    return string.format("%.0f", b * 65536 + a)
end

local function equal(left, right)
    if not left or not right or #left ~= #right then return false end
    for index, line in ipairs(left) do if right[index] ~= line then return false end end
    return true
end

local function write(path, text, append)
    local writer
    local ok = pcall(function()
        writer = getFileWriter(path, true, append == true)
        if not writer then error("Cannot write settings") end
        writer:write(text)
    end)
    local closed = true
    if writer then closed = pcall(function() writer:close() end) end
    return ok and closed
end

function Storage.readLines(path)
    local reader
    local ok, lines = pcall(function()
        reader = getFileReader(path, false)
        local result = {}
        if not reader then
            -- Native getFileReader can return nil after an IO exception too.
            if cacheFileExists and cacheFileExists("Lua/" .. path) then error("Cannot read existing settings") end
            return result
        end
        while true do
            local line = reader:readLine()
            if line == nil then return result end
            result[#result + 1] = line
        end
    end)
    local closed = true
    if reader then closed = pcall(function() reader:close() end) end
    if not ok or not closed then return nil end
    return lines
end

local function snapshot(lines)
    if not lines or not lines[1] then return nil end
    local count, digest = lines[1]:match("^PZST ModOptions recovery 1|(%d+)|(%d+)$")
    count = tonumber(count)
    if not count or count > #lines - 2 or lines[count + 2] ~= "SEALED|" .. digest then return nil end
    local before = {}
    for index = 1, count do before[index] = lines[index + 1] end
    if checksum(before) ~= digest then return nil end
    return before, digest, #lines > count + 2 and lines[#lines] == "COMMITTED|" .. digest
end

local function commit(digest)
    -- A leading newline separates a previous interrupted append from this one.
    if not write(recoveryPath, "\r\nCOMMITTED|" .. digest .. "\r\n", true) then return false end
    local _, actual, committed = snapshot(Storage.readLines(recoveryPath))
    return actual == digest and committed == true
end

function Storage.recover()
    local lines = Storage.readLines(recoveryPath)
    if not lines then return false end
    local before, digest, committed = snapshot(lines)
    -- An unsealed backup never authorized touching the target. A committed
    -- backup must not roll back later deliberate native UI changes.
    if not before or committed then return true end
    if not write(optionsPath, table.concat(before, "\r\n") .. (#before > 0 and "\r\n" or ""))
        or not equal(before, Storage.readLines(optionsPath)) then return false end
    reloadNeeded = true
    -- Retain the sealed before-image if restoration or its acknowledgement
    -- fails, so the next process can repeat the same recovery.
    return commit(digest)
end

local function ready()
    if not Storage.recover() then return false end
    -- A previously failed boot recovery may finish after upstream loaded a
    -- truncated file. Refresh those values before a consumer makes its once-only
    -- decision. Do not reload during save failure cleanup: Peek keeps its safe
    -- runtime preset until the next attempt.
    local options = PZAPI and PZAPI.ModOptions
    if reloadNeeded and options and type(options.load) == "function" then
        if not pcall(function() options:load() end) then return false end
        reloadNeeded = false
    end
    return true
end

function Storage.matches(path, line)
    if not ready() then return nil end
    local lines = Storage.readLines(path)
    if not lines then return nil end
    return #lines == 1 and lines[1] == line
end

function Storage.mark(path, line)
    if not ready() then return false end
    return write(path, line .. "\r\n") and Storage.matches(path, line) == true
end

-- Preserve native OtherOptions entries, including options for absent mods.
function Storage.save(expected)
    if not Storage.recover() then return false end
    local options = PZAPI and PZAPI.ModOptions
    if not options or type(options.save) ~= "function" then return false end
    local before = Storage.readLines(optionsPath)
    if not before then return false end
    local digest = checksum(before)
    local backup = {"PZST ModOptions recovery 1|" .. #before .. "|" .. digest}
    for _, line in ipairs(before) do backup[#backup + 1] = line end
    backup[#backup + 1] = "SEALED|" .. digest
    if not write(recoveryPath, table.concat(backup, "\r\n") .. "\r\n")
        or not equal(backup, Storage.readLines(recoveryPath))
        or not equal(before, Storage.readLines(optionsPath)) then return false end
    local original = options.OtherOptions
    -- Native load strips line endings; native save emits OtherOptions verbatim.
    local terminated = {}
    for index, line in ipairs(original or {}) do
        terminated[index] = line:match("[\r\n]$") and line or line .. "\r\n"
    end
    options.OtherOptions = terminated
    local ok = pcall(function() options:save() end)
    options.OtherOptions = original
    local function failed()
        Storage.recover()
        return false
    end
    if not ok then return failed() end
    -- PrintWriter can swallow IO failures, including a partial save after a
    -- target line. Verify the targets and every unrelated line before success.
    local after = Storage.readLines(optionsPath)
    if not after then return failed() end
    local counts = {}
    for _, line in ipairs(after) do counts[line] = (counts[line] or 0) + 1 end
    for prefix, value in pairs(expected) do
        local line = prefix .. value
        if not counts[line] or counts[line] == 0 then return failed() end
        counts[line] = counts[line] - 1
    end
    for _, line in ipairs(before) do
        local targeted = false
        for prefix in pairs(expected) do
            if line:sub(1, #prefix) == prefix then targeted = true; break end
        end
        if not targeted then
            if not counts[line] or counts[line] == 0 then return failed() end
            counts[line] = counts[line] - 1
        end
    end
    if not commit(digest) then return failed() end
    reloadNeeded = false
    return true
end

return Storage
