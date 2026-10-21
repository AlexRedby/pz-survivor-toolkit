local Duplicates = {}

local function plainAction(option)
    return getmetatable(option) == nil and option.onSelect and not option.isTitle
end

local function sameAction(left, right)
    if not plainAction(left) or not plainAction(right) then return false end
    -- Labels cannot distinguish different targets, arguments or foreign metadata.
    for key, value in pairs(left) do
        if key ~= "id" and right[key] ~= value then return false end
    end
    for key, value in pairs(right) do
        if key ~= "id" and left[key] ~= value then return false end
    end
    return true
end

function Duplicates.collect(options)
    local named, unique, aliases = {}, {}, {}
    for _, option in ipairs(options) do
        if plainAction(option) then
            local name = option.name or false
            local group = named[name]
            if not group then group = {options = {}, kept = {}}; named[name] = group end
            group.options[#group.options + 1] = option
        end
    end
    local tokens, nextToken, opaque = {}, 0, {}
    local function token(value, raw)
        -- A protected metatable can expose an arbitrary mask, even a table
        -- hiding __eq. Opaque values share a token; exact comparisons decide.
        if not raw and getmetatable(value) ~= nil then value = opaque end
        if type(value) == "number" then
            if value ~= value then return nil end
            -- Java Double table keys distinguish -0.0 from 0.0; Lua equality does not.
            if value == 0 then value = 0 end
        end
        local id = tokens[value]
        if not id then
            -- Products remain exact in both Lua 5.1 and Kahlua's doubles.
            if nextToken >= 67108863 then return nil end
            nextToken = nextToken + 1; id = nextToken; tokens[value] = id
        end
        return id
    end
    for _, group in pairs(named) do
        if #group.options > 1 then
            local hashes, safe, types = {}, true, {}
            for _, option in ipairs(group.options) do
                for key, value in pairs(option) do
                    if key ~= "id" then
                        local kind = type(value)
                        if types[key] == nil then types[key] = kind
                        elseif types[key] ~= kind then types[key] = false end
                    end
                end
            end
            for _, option in ipairs(group.options) do
                local hash = 0
                for key, value in pairs(option) do
                    if key ~= "id" then
                        -- Field keys use raw table lookup. Uniform string/number
                        -- fields use Lua value equality, even with standard metatables.
                        -- Mixed fields retain opaque tokens for possible custom __eq.
                        local rawValue = types[key] == "string" or types[key] == "number"
                        local k, v = token(key, true), token(value, rawValue)
                        if not k or not v then safe = false; break end
                        hash = (hash + k * v) % 2147483647
                    end
                end
                if not safe then break end
                hashes[option] = hash
            end
            -- A hash only narrows candidates. Exact comparison below remains
            -- authoritative, so collisions never discard a distinct command.
            if safe then group.hashes, group.buckets = hashes, {} end
        end
    end
    for _, option in ipairs(options) do
        local duplicate
        if plainAction(option) then
            local group = named[option.name or false]
            local matches = group.kept
            if group.hashes then
                local hash = group.hashes[option]
                matches = group.buckets[hash]
                if not matches then matches = {}; group.buckets[hash] = matches end
            end
            for _, kept in ipairs(matches) do
                if sameAction(option, kept) then duplicate = kept; break end
            end
            if not duplicate then matches[#matches + 1] = option end
        end
        if duplicate then aliases[option] = duplicate else unique[#unique + 1] = option end
    end
    return unique, aliases
end

return Duplicates
