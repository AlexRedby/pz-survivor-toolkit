local Identity = require "PZSurvivorWishlist/StorageIdentity"
local function checksum(hash, line)
    for index = 1, #line do hash = (hash * 33 + string.byte(line, index)) % 2147483647 end
    return (hash * 33 + 10) % 2147483647
end
local function rebound(text, source, world)
    if not text:find("^PZSW\t3\t") then
        -- Unrecognizable peers stay corrupt without choosing a different namespace.
        if text:find("^PZSW\t[12]\t") then return text, false end
        return text, nil
    end
    assert(Identity.valid(source), 'Wishlist restore source identity missing')
    local header, encoded, rest = text:match("^([^\n]+)\nI\t([0-9a-f]+)\n(.*)$")
    if not header or #encoded > 2048 or #encoded % 4 ~= 0 then return text, true end
    assert(encoded == Identity.encode(source), 'Wishlist restore source identity differs')
    local oldHash, newHash = checksum(0, header), checksum(0, header)
    oldHash, newHash = checksum(oldHash, 'I\t' .. encoded), checksum(newHash, 'I\t' .. Identity.encode(world))
    local lines, generation = {}, header:match('^PZSW\t3\t(%d+)$')
    local position = 1
    -- Rebind a complete checksum, retaining any interrupted/corrupt peer as corrupt.
    while true do
        local finish = rest:find('\n', position, true)
        local line = rest:sub(position, finish and finish - 1 or #rest)
        if (not finish or finish == #rest) and line == 'END\t' .. (generation or '') .. '\t' .. oldHash then
            line = 'END\t' .. generation .. '\t' .. newHash
        else
            oldHash, newHash = checksum(oldHash, line), checksum(newHash, line)
        end
        lines[#lines + 1] = line .. (finish and '\n' or '')
        if not finish then break end
        position = finish + 1
    end
    return header .. '\nI\t' .. Identity.encode(world) .. '\n' .. table.concat(lines), true
end
return function(world, slots, source)
    assert(isServer() and not isClient(), 'Wishlist restore requires the dedicated test server')
    assert(getCurrentSaveName() == world and Identity.valid(world), 'Wishlist restore world identity differs')
    local prepared, modern, count = {}, nil, 0
    for slot, text in pairs(slots) do
        assert((slot == 'a' or slot == 'b') and type(text) == 'string', 'Invalid wishlist restore slot')
        local value, bound = rebound(text, source, world)
        if text ~= '' then
            if bound ~= nil then
                assert(modern == nil or modern == bound, 'Wishlist restore mixes storage formats')
                modern = bound
            end
            prepared[slot], count = value, count + 1
        end
    end
    assert(count > 0, 'Wishlist restore has no slots')
    local prefix = modern and Identity.prefix(world) or Identity.legacyPrefix(world)
    -- Refuse either preexisting slot before opening any writer.
    for _, slot in ipairs({'a', 'b'}) do
        local path = prefix .. slot .. '.txt'
        assert(not cacheFileExists(path), 'Wishlist restore target is not fresh')
    end
    for slot, text in pairs(prepared) do
        local path = prefix .. slot .. '.txt'
        local writer = assert(getFileWriter(path, true, false), 'Wishlist restore writer unavailable')
        writer:write(text); writer:close()
        local reader = assert(getFileReader(path, false), 'Wishlist restore readback unavailable')
        local lines = {}
        while true do
            local line = reader:readLine()
            if not line then break end
            lines[#lines + 1] = line
        end
        reader:close()
        -- BufferedReader discards the final line terminator; retain original bytes in the writer.
        assert(table.concat(lines, '\n') == text:gsub('\n$', ''), 'Wishlist restore readback differs')
        print('[WISHLIST_TEST] RESTORE slot=' .. slot .. ' chars=' .. #text)
    end
    print('[WISHLIST_TEST] RESTORE_COMPLETE slots=' .. count)
end
