local Codec = {}
local LIMIT, DEPTH = 2000000, 4

local function invalid(reason)
    error('Invalid Quartermaster presets: ' .. reason, 0)
end

local function integer(value)
    return type(value) == 'number' and value >= 0 and value <= 9007199254740991
        and value == math.floor(value)
end

local function presetsShape(presets)
    if type(presets) ~= 'table' then invalid('expected preset map') end
    for name, preset in pairs(presets) do
        if type(name) ~= 'string' or type(preset) ~= 'table' then invalid('expected named preset') end
        for field, value in pairs(preset) do
            if field == 'cats' or field == 'items' then
                if type(value) ~= 'table' then invalid('expected selection set') end
                for key, selected in pairs(value) do
                    if type(key) ~= 'string' or selected ~= true then invalid('expected string -> true selection') end
                end
            elseif field == 'gen' or field == 'rev' then
                if not integer(value) then invalid('invalid ' .. field) end
            elseif field == 'createdBy' then
                if type(value) ~= 'string' then invalid('invalid creator') end
            else
                invalid('unknown preset field')
            end
        end
    end
end

function Codec.decode(text)
    if type(text) ~= 'string' or #text > LIMIT then invalid('text size/type') end
    local cursor = 1
    local function space()
        local _, last = text:find('^%s*', cursor)
        cursor = last + 1
    end
    local function take(token)
        if text:sub(cursor, cursor + #token - 1) ~= token then invalid('expected ' .. token) end
        cursor = cursor + #token
        space()
    end
    local escapes = {a = '\a', b = '\b', f = '\f', v = '\v', n = '\n', r = '\r', t = '\t', ['\\'] = '\\', ['"'] = '"', ['\n'] = '\n'}
    local function quoted()
        cursor = cursor + 1
        local parts = {}
        while true do
            local char = text:sub(cursor, cursor)
            if char == '' then invalid('unterminated string') end
            cursor = cursor + 1
            if char == '"' then space(); return table.concat(parts) end
            if char == '\\' then
                local digits = text:match('^%d%d?%d?', cursor)
                if digits then
                    local code = tonumber(digits)
                    if code > 255 then invalid('decimal escape') end
                    parts[#parts + 1] = string.char(code)
                    cursor = cursor + #digits
                else
                    char = text:sub(cursor, cursor)
                    if not escapes[char] then invalid('unknown escape ' .. tostring(string.byte(char))) end
                    parts[#parts + 1] = escapes[char]
                    cursor = cursor + 1
                end
            else
                if char == '\n' or char == '\r' then invalid('unescaped line break') end
                parts[#parts + 1] = char
            end
        end
    end
    local value
    local function parseTable(depth)
        if depth > DEPTH then invalid('table depth') end
        take('{')
        local result, seen = {}, {}
        while text:sub(cursor, cursor) ~= '}' do
            local key
            if text:sub(cursor, cursor) == '[' then
                take('[')
                if text:sub(cursor, cursor) ~= '"' then invalid('expected quoted key') end
                key = quoted()
                take(']')
            else
                key = text:match('^[%a_][%w_]*', cursor)
                if not key then invalid('expected field') end
                cursor = cursor + #key
                space()
            end
            if seen[key] then invalid('duplicate field') end
            seen[key] = true
            take('=')
            result[key] = value(depth)
            if text:sub(cursor, cursor) == ',' then
                take(',')
            elseif text:sub(cursor, cursor) ~= '}' then
                invalid('expected comma or closing brace')
            end
        end
        take('}')
        return result
    end
    value = function(depth)
        local char = text:sub(cursor, cursor)
        if char == '{' then return parseTable(depth + 1) end
        if char == '"' then return quoted() end
        for _, token in ipairs({'true', 'false'}) do
            if text:sub(cursor, cursor + #token - 1) == token then
                take(token)
                return token == 'true'
            end
        end
        local number = text:match('^%-?%d+%.?%d*', cursor)
        if not number then invalid('expected literal') end
        cursor = cursor + #number
        space()
        return tonumber(number)
    end
    space()
    if cursor > #text then return {}, 1 end
    take('return')
    local result = value(0)
    if cursor <= #text then invalid('trailing content') end
    if type(result) ~= 'table' then invalid('expected root table') end
    local version = 1
    if result.version ~= nil and type(result.version) ~= 'table' then
        if result.version ~= 2 or type(result.presets) ~= 'table' then invalid('unsupported envelope') end
        for field in pairs(result) do
            if field ~= 'version' and field ~= 'presets' then invalid('unknown envelope field') end
        end
        result, version = result.presets, 2
    end
    presetsShape(result)
    for _, preset in pairs(result) do
        preset.cats, preset.items = preset.cats or {}, preset.items or {}
    end
    return result, version
end

local function keys(map)
    local result = {}
    for key in pairs(map) do result[#result + 1] = key end
    table.sort(result)
    return result
end

local function quote(value)
    -- Kahlua's %q leaves backslashes unescaped, so use one lossless dialect in both runtimes.
    return '"' .. value:gsub('[%z\1-\31\\"]', function(char)
        if char == '\\' then return '\\\\' end
        if char == '"' then return '\\"' end
        return string.format('\\%03d', string.byte(char))
    end) .. '"'
end

function Codec.encode(presets)
    presetsShape(presets)
    local parts, size = {}, 0
    local function emit(text)
        size = size + #text
        if size > LIMIT then invalid('text size') end
        parts[#parts + 1] = text
    end
    emit('return { version = 2, presets = {\n')
    for _, name in ipairs(keys(presets)) do
        local preset = presets[name]
        emit('  [' .. quote(name) .. '] = {')
        for _, field in ipairs({'cats', 'items'}) do
            emit(' ' .. field .. ' = {')
            for _, key in ipairs(keys(preset[field] or {})) do emit(' [' .. quote(key) .. ']=true,') end
            emit(' },')
        end
        for _, field in ipairs({'gen', 'rev'}) do
            if preset[field] ~= nil then emit(string.format(' %s = %d,', field, preset[field])) end
        end
        if preset.createdBy ~= nil then emit(' createdBy = ' .. quote(preset.createdBy) .. ',') end
        emit(' },\n')
    end
    emit('} }\n')
    return table.concat(parts)
end

return Codec
