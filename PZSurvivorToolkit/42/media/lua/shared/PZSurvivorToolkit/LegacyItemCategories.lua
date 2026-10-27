-- Read-only compatibility with OC's saved category assignments. The source files
-- remain untouched; labels, colors and editor state are deliberately not loaded.
local Legacy = {}
local mode, loadedSource, assignments

local function readLines(name, maxBytes, maxLines)
    if not getFileReader then return {} end
    local opened, reader = pcall(getFileReader, name, false)
    if not opened then return nil end
    if not reader then return {} end
    local lines, bytes = {}, 0
    local ok = pcall(function()
        while true do
            local value = reader:readLine()
            if value == nil then break end
            local line = tostring(value):gsub('\r$', '')
            bytes = bytes + #line + 1
            assert(bytes <= maxBytes and #lines < maxLines, 'legacy category file exceeds bounds')
            lines[#lines + 1] = line
        end
    end)
    pcall(function() reader:close() end)
    return ok and lines or nil
end

local function settings()
    if mode then return mode end
    mode = {perSave=false, sessionOnly=false, vanilla=false}
    local lines = readLines('ModOptions.ini', 2097152, 20000)
    if not lines then mode.invalid=true;return mode end
    for _, line in ipairs(lines) do
        if line:find('|organizedCategories_core|', 1, true) then
            local kind, key, value = line:match('^([^|]+)|organizedCategories_core|([^|]+)|([^|]+)$')
            if key == 'perSaveDisplayOverrides' or key == 'sessionOnlyDisplayOverrides' or key == 'useVanillaDefaults' then
                if kind ~= 'tickbox' or (value ~= 'true' and value ~= 'false') then
                    mode.invalid=true;return mode
                end
                if key == 'perSaveDisplayOverrides' then mode.perSave=value=='true'
                elseif key == 'sessionOnlyDisplayOverrides' then mode.sessionOnly=value=='true'
                else mode.vanilla=value=='true' end
            elseif not kind then
                mode.invalid=true;return mode
            end
        end
    end
    return mode
end

local function source()
    local options = settings()
    if options.invalid or (options.perSave and options.sessionOnly) then return nil end
    if not options.perSave then return 'organizedCategories_displayOverrides.txt' end
    local core = getCore and getCore()
    local world = core and core.getWorld and core:getWorld()
    if (world == nil or tostring(world) == '') and getWorld then
        local current = getWorld()
        world = current and current.getWorld and current:getWorld()
    end
    if world == nil or tostring(world) == '' then return nil end
    local safe = tostring(world):gsub('[^%w%._%-]+', '_')
    if safe == '' then return nil end
    return 'organizedCategories_displayOverrides_'..safe..'.txt'
end

local function parse(lines)
    if not lines then return nil end
    local result = {}
    for _, line in ipairs(lines) do
        if line ~= '' then
            local kind, key, value = line:match('^([TCLA])=(.-)=(.+)$')
            -- Atomic rejection prevents a damaged file from applying only an
            -- arbitrary prefix. C/L/A are recognized records, but never imported.
            if not kind or key == '' or #key > 512 or #value > 2048
                or key:find('[%z\1-\31]') or value:find('[%z\1-\31]') then return nil end
            if kind == 'T' then
                if not key:match('^[%w_%-]+%.[%w_%.%-]+$')
                    or not value:match('^[%a][%w_%.%-]*$') then return nil end
                result[string.lower(key)] = value
            end
        end
    end
    return result
end

function Legacy.forType(fullType)
    if not fullType then return nil end
    local name = source()
    if name ~= loadedSource or assignments == nil then
        loadedSource = name
        assignments = name and parse(readLines(name, 2097152, 20000)) or {}
        if not assignments then
            assignments = {}
            if print then print('[PZSurvivorToolkit] Ignored invalid legacy category assignments: '..name) end
        end
    end
    return assignments[string.lower(tostring(fullType))]
end

function Legacy.instancesEnabled()
    local options = settings()
    return not options.invalid and not (options.perSave and options.sessionOnly)
end

function Legacy.useVanillaDefaults()
    local options = settings()
    return not options.invalid and options.vanilla
end

function Legacy.reset()
    mode, loadedSource, assignments = nil, nil, nil
end

return Legacy
