local Settings = {}
local markerPath = "PZSurvivorToolkitCartControls.ini"
local markerVersion = "PushCartInteract=1"
local configuredBinding

-- Called while SaucedCarts still has its file-load default, before ModOptions:load().
function Settings.configureDefault(binding)
    if not binding or configuredBinding == binding then return end
    configuredBinding = binding
    binding.defaultkey = Keyboard.KEY_E
    if binding:getValue() == Keyboard.KEY_V then binding:setValue(Keyboard.KEY_E) end
end

local function readLines(path)
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

local function marked()
    local lines = readLines(markerPath)
    if not lines then return nil end
    return #lines == 1 and lines[1] == markerVersion
end

local function mark()
    local writer
    local ok = pcall(function()
        writer = getFileWriter(markerPath, true, false)
        if not writer then error("Cannot write cart controls version") end
        writer:write(markerVersion .. "\r\n")
    end)
    local closed = true
    if writer then closed = pcall(function() writer:close() end) end
    return ok and closed and marked() == true
end

local function saveBinding()
    local options = PZAPI and PZAPI.ModOptions
    if not options or type(options.save) ~= "function" then return false end
    local before = readLines("ModOptions.ini")
    if not before then return false end
    -- Native load strips newlines from entries belonging to absent mods, while
    -- native save writes OtherOptions verbatim. Retain each unrelated entry.
    local original = options.OtherOptions
    local terminated = {}
    for index, line in ipairs(original or {}) do
        terminated[index] = line:match("[\r\n]$") and line or line .. "\r\n"
    end
    options.OtherOptions = terminated
    local ok = pcall(function() options:save() end)
    options.OtherOptions = original
    if not ok then return false end
    -- Native PrintWriter may swallow errors; successful return is insufficient.
    local after = readLines("ModOptions.ini")
    if not after then return false end
    local counts = {}
    for _, line in ipairs(after) do counts[line] = (counts[line] or 0) + 1 end
    local prefix = "keybind|SaucedCarts|PushCart|"
    if not counts[prefix .. tostring(Keyboard.KEY_E)] then return false end
    -- Detect a swallowed partial write after the key line as well. Existing
    -- unrelated settings must still be readable as separate complete lines.
    for _, line in ipairs(before) do
        if line:sub(1, #prefix) ~= prefix then
            if not counts[line] or counts[line] == 0 then return false end
            counts[line] = counts[line] - 1
        end
    end
    return true
end

-- Called on game start, after native ModOptions has restored the user's choice.
function Settings.migrate(binding)
    if not binding or type(binding.getValue) ~= "function" or type(binding.setValue) ~= "function" then
        return false, "binding_missing"
    end
    local complete = marked()
    if complete == nil then return false, "marker_read" end
    if complete then return true, "already_migrated" end
    local previous = binding:getValue()
    if previous == Keyboard.KEY_V then
        binding:setValue(Keyboard.KEY_E)
        if not saveBinding() then
            binding:setValue(previous)
            return false, "binding_save"
        end
    end
    -- Also finish the decision for custom/disabled keys so a later chosen V is
    -- never confused with the old default. Those choices need no options save.
    if not mark() then return false, "marker_write" end
    return true, previous == Keyboard.KEY_V and "migrated" or "preserved"
end

return Settings
