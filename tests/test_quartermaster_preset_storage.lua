if not TestPresetStorage then package.path = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/?.lua;' .. package.path end
local Codec = TestPresetCodec or require 'PZSurvivorToolkit/QuartermasterPresetCodec'
local Storage = TestPresetStorage or require 'PZSurvivorToolkit/QuartermasterPresetStorage'
local client, server = false, false
isClient, isServer = function() return client end, function() return server end
local a, b = 'PZSTQuartermasterPresets_a.txt', 'PZSTQuartermasterPresets_b.txt'
local nativeFile, rulesFile = 'QuartermasterPresets.txt', 'PZSTQuartermasterTagRules.txt'
local presetName = TestPresetName or 'Pantry 洗 😀'
local function records(rev)
    return {[presetName] = {cats = {Food = true}, items = {['Base.TinOpener'] = true},
        gen = 17, rev = rev, createdBy = TestPresetOwner or 'Игрок'}},
        {[presetName] = {cats = {food = true}, items = {__PZST_ANY__ = true}, gen = 17}}
end
local disk, behavior, opened, closed, writes = {}, {}, 0, 0, 0
local function reader(path, create)
    if behavior.read == path then error('read failed') end
    if behavior.nilRead == path then return nil end
    if create and disk[path] == nil then disk[path] = '' end
    if disk[path] == nil then return nil end
    opened = opened + 1
    local values, index = {}, 0
    for line in disk[path]:gmatch('(.-)\n') do values[#values + 1] = line end
    if disk[path]:sub(-1) ~= '\n' and #disk[path] > 0 then values[#values + 1] = disk[path]:match('([^\n]*)$') end
    return {readLine = function()
        if behavior.line == path then error('readLine failed') end
        index = index + 1; return values[index]
    end, close = function()
        closed = closed + 1
        if behavior.readerClose == path then error('reader close failed') end
    end}
end
getFileReader = reader
getFileWriter = function(path, create, append)
    assert(create and not append)
    writes = writes + 1
    if behavior.open then return nil end
    disk[path] = ''
    return {write = function(_, text)
        disk[path] = behavior.headerCut and text:sub(1, 5) or (behavior.short or behavior.write) and text:sub(1, math.floor(#text / 2)) or text
        if behavior.write then error('write failed') end
    end, close = function()
        behavior.writerClosed = true
        if behavior.readback then behavior.read = path end
        if behavior.writerClose then error('writer close failed') end
    end}
end
local native, rules = records(2)
disk[nativeFile], disk[rulesFile] = Codec.encode(native), Codec.encode(rules)
local legacyNative, legacyRules = disk[nativeFile], disk[rulesFile]
local imported = Storage.load()
assert(imported.generation == 0 and imported.nativeVersion == 2 and imported.native[presetName].rev == 2)
native, rules = records(3)
local first = Storage.save(imported, native, rules)
assert(first.generation == 1 and first.native[presetName].rev == 3)
local firstBytes = disk[a]
for _, fault in ipairs({'short', 'headerCut', 'write', 'open', 'writerClose', 'readback'}) do
    disk[a], disk[b], behavior = '', '', {}
    behavior[fault] = true
    assert(not pcall(Storage.save, imported, native, rules), 'first migration failure was hidden')
    behavior = {}
    local recovered = Storage.load()
    if fault == 'writerClose' or fault == 'readback' then
        assert(recovered.generation == 1 and recovered.native[presetName].rev == 3,
            'first complete ambiguous commit was replaced by legacy')
        local before = writes
        assert(not pcall(Storage.save, imported, native, rules) and writes == before)
    else
        assert(recovered.generation == 0 and recovered.native[presetName].rev == 2,
            'partial first migration stranded the retained legacy pair')
        assert(Storage.save(recovered, native, rules).generation == 1, 'first migration could not retry')
    end
    assert(disk[nativeFile] == legacyNative and disk[rulesFile] == legacyRules)
end
disk[a], disk[b], behavior = firstBytes, '', {}
assert(firstBytes and disk[nativeFile] == legacyNative and disk[rulesFile] == legacyRules, 'migration rewrote legacy files')
local function baseline()
    disk[a], disk[b], behavior = firstBytes, '', {}
end
local function assertFirst()
    local current = Storage.load()
    assert(current.generation == 1 and current.native[presetName].rev == 3
        and current.rules[presetName].gen == 17 and disk[a] == firstBytes, 'failed write destroyed the last coherent pair')
end
for _, fault in ipairs({'short', 'write', 'open'}) do
    baseline(); behavior[fault] = true
    native, rules = records(4)
    assert(not pcall(Storage.save, first, native, rules), fault .. ' write was acknowledged')
    if fault ~= 'open' then assert(behavior.writerClosed, 'writer leaked after failure') end
    behavior = {}; assertFirst()
end
for _, fault in ipairs({'writerClose', 'readback'}) do
    baseline(); behavior[fault] = true
    native, rules = records(4)
    assert(not pcall(Storage.save, first, native, rules), fault .. ' failure hidden')
    behavior = {}
    local current = Storage.load()
    assert(current.generation == 2 and current.native[presetName].rev == 4, 'complete slot was lost after ambiguous I/O result')
    local before = writes
    assert(not pcall(Storage.save, first, native, rules) and writes == before, 'stale sequence overwrote a later commit')
    native, rules = records(5)
    local nextState = Storage.save(current, native, rules)
    assert(nextState.generation == 3 and Storage.load().native[presetName].rev == 5)
end
baseline(); native, rules = records(4)
local second = Storage.save(first, native, rules)
local secondBytes = disk[b]
assert(second.slot == 2 and second.generation == 2 and disk[a] == firstBytes)
assert(Storage.load().native[presetName].rev == 4, 'cold load missed newest slot')
for _, corrupt in ipairs({secondBytes:sub(1, #secondBytes - 20), secondBytes .. 'trailing\n', (secondBytes:gsub('Base.TinOpener', 'Base.OtherItem'))}) do
    disk[b] = corrupt; assertFirst()
end
disk[a], disk[b] = 'broken\n', 'also broken\n'
assert(not pcall(Storage.load), 'two broken slots silently fell back to obsolete legacy files')
disk[a], disk[b] = firstBytes, secondBytes:gsub('PZST_QM|1|', 'PZST_QM|9|', 1)
assert(not pcall(Storage.load), 'unknown newer format was silently overwritten')
baseline(); native, rules = records(9); Storage.save(first, native, rules)
local alternative = disk[b]
disk[a], disk[b] = secondBytes, alternative
assert(not pcall(Storage.load), 'same-generation disagreement was silently resolved')
for _, fault in ipairs({'read', 'nilRead', 'line', 'readerClose'}) do
    baseline(); behavior[fault] = a
    assert(not pcall(Storage.load), fault .. ' reader failure hidden')
end
behavior = {}; assert(opened == closed, 'snapshot reader leak')
disk[a], disk[b], disk[nativeFile] = '', '', 'return { damaged'
assert(not pcall(Storage.load), 'malformed legacy store became empty')
assert(disk[nativeFile] == 'return { damaged' and disk[rulesFile] == legacyRules)
local before = opened
client = true; assert(not pcall(Storage.load) and opened == before); client = false
server = true; assert(not pcall(Storage.load) and opened == before); server = false
print('Quartermaster snapshot storage passed: legacy migration, coherent Unicode pairs, partial/silent writes, ambiguous commits, recovery, stale contexts and reader failures.')
