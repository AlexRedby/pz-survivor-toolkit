return function(world, slots)
    assert(isServer() and not isClient(), 'Wishlist restore requires the dedicated test server')
    assert(getCurrentSaveName() == world, 'Wishlist restore world identity differs')
    local encoded = world:gsub('.', function(char) return string.format('%04x', string.byte(char)) end)
    local parts = {'PZSurvivorWishlist'}
    for index = 1, #encoded, 80 do parts[#parts + 1] = encoded:sub(index, index + 79) end
    local prefix = table.concat(parts, '/') .. '/'
    local count = 0
    for slot, text in pairs(slots) do
        assert((slot == 'a' or slot == 'b') and type(text) == 'string', 'Invalid wishlist restore slot')
        local path = prefix .. slot .. '.txt'
        local existing = getFileReader(path, false)
        if existing then existing:close(); error('Wishlist restore target is not fresh') end
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
        assert(table.concat(lines, '\n') .. '\n' == text, 'Wishlist restore readback differs')
        count = count + 1
        print('[WISHLIST_TEST] RESTORE slot=' .. slot .. ' chars=' .. #text)
    end
    assert(count > 0, 'Wishlist restore has no slots')
    print('[WISHLIST_TEST] RESTORE_COMPLETE slots=' .. count)
end
