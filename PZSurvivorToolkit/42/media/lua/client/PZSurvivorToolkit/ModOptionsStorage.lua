local Storage = {}

function Storage.readLines(path)
    local reader
    local ok, lines = pcall(function()
        reader = getFileReader(path, false)
        local result = {}
        if not reader then return result end
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

function Storage.matches(path, line)
    local lines = Storage.readLines(path)
    if not lines then return nil end
    return #lines == 1 and lines[1] == line
end

function Storage.mark(path, line)
    local writer
    local ok = pcall(function()
        writer = getFileWriter(path, true, false)
        if not writer then error("Cannot write marker") end
        writer:write(line .. "\r\n")
    end)
    local closed = true
    if writer then closed = pcall(function() writer:close() end) end
    return ok and closed and Storage.matches(path, line) == true
end

-- Preserve native OtherOptions entries, including options for absent mods.
function Storage.save(expected)
    local options = PZAPI and PZAPI.ModOptions
    if not options or type(options.save) ~= "function" then return false end
    local before = Storage.readLines("ModOptions.ini")
    if not before then return false end
    local original = options.OtherOptions
    -- Native load strips line endings; native save emits OtherOptions verbatim.
    local terminated = {}
    for index, line in ipairs(original or {}) do
        terminated[index] = line:match("[\r\n]$") and line or line .. "\r\n"
    end
    options.OtherOptions = terminated
    local ok = pcall(function() options:save() end)
    options.OtherOptions = original
    if not ok then return false end
    -- PrintWriter can swallow IO failures, including a partial save after a
    -- target line. Verify the targets and every unrelated line before success.
    local after = Storage.readLines("ModOptions.ini")
    if not after then return false end
    local counts = {}
    for _, line in ipairs(after) do counts[line] = (counts[line] or 0) + 1 end
    for prefix, value in pairs(expected) do
        local line = prefix .. value
        if not counts[line] or counts[line] == 0 then return false end
        counts[line] = counts[line] - 1
    end
    for _, line in ipairs(before) do
        local targeted = false
        for prefix in pairs(expected) do
            if line:sub(1, #prefix) == prefix then targeted = true; break end
        end
        if not targeted then
            if not counts[line] or counts[line] == 0 then return false end
            counts[line] = counts[line] - 1
        end
    end
    return true
end

return Storage
