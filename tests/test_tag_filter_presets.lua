local root = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/'
local loaded = {}
require = function(module)
    if not loaded[module] then loaded[module] = assert(loadfile(root .. 'shared/' .. module .. '.lua'))() end
    return loaded[module]
end
local a, b = 'PZSurvivorToolkit_TagFilters_a.txt', 'PZSurvivorToolkit_TagFilters_b.txt'
local disk, faults, writes, reads, enumerations = {}, {}, 0, 0, 0
listFilesInZomboidLuaDirectory = function(path)
    assert(path == '')
    enumerations = enumerations + 1
    local names = {}
    if not faults.directory then for file in pairs(disk) do names[#names + 1] = file end end
    return {size = function() return #names end, get = function(_, index) return names[index + 1] end}
end
getFileReader = function(path, create)
    assert(create == true); reads = reads + 1
    local fault = faults[path] or {}
    if fault.readerThrows then error('reader unavailable') end
    if fault.readerNil or faults.directory then return end
    if disk[path] == nil then disk[path] = '' end
    local text = disk[path]
    if text == nil then return end
    if fault.readback and fault.written then text = text:match('^[^\n]*\n') end
    local position, lines = 1, 0
    return {readLine = function()
        lines = lines + 1
        if fault.readThrows and lines >= fault.readThrows then error('read failed') end
        if fault.readInvalid then return false end
        if position > #text then return end
        local newline = text:find('\n', position, true)
        local line = text:sub(position, newline and newline - 1 or #text)
        position = newline and newline + 1 or #text + 1
        return line
    end, close = function() if fault.readCloseThrows then error('reader close failed') end end}
end
getFileWriter = function(path, create, append)
    assert(create == true and append == false)
    local fault = faults[path] or {}
    if fault.writerThrows then error('writer unavailable') end
    if fault.writerNil then return end
    writes = writes + 1; disk[path] = ''
    return {write = function(_, text)
        fault.written = true
        disk[path] = fault.prefix and text:sub(1, fault.prefix) or text
        if fault.writeThrows then error('write failed') end
    end, close = function() if fault.writeCloseThrows then error('writer close failed') end end}
end
local function reopen() return dofile(root .. 'client/PZSurvivorToolkit/TagFilterPresets.lua') end
local Presets = reopen()
local rule = {mode = 'all', include = {'food', 'perishable'}, exclude = {'meat'}}
local function errorIs(expected, fn, ...)
    local value, err = fn(...)
    assert(value == nil and err == expected, 'expected ' .. expected .. ', got ' .. tostring(value) .. '/' .. tostring(err))
end
local function reset() disk, faults, writes = {}, {}, 0; Presets = reopen() end
assert(#Presets.list() == 0 and writes == 0 and disk[a] == '' and disk[b] == '', 'empty list wrote a snapshot')
assert(#Presets.list() == 0 and #reopen().list() == 0 and writes == 0,
    'new empty slots blocked repeated reads or cold reopen')
assert(Presets.save('  Food  ', rule))
assert(disk[a] ~= '' and disk[b] == '', 'first save did not select first slot')
rule.include[1] = 'electrical'
local entries = reopen().list()
assert(#entries == 1 and entries[1].name == 'Food' and entries[1].rule.include[1] == 'food', 'input alias or reopen failed')
entries[1].name = 'Mutated'; entries[1].rule.include[1] = 'electrical'
assert(Presets.list()[1].name == 'Food' and Presets.list()[1].rule.include[1] == 'food', 'list returned stored aliases')
local earlierReads = reads; Presets.list(); assert(reads >= earlierReads + 2, 'list used persistent module cache')
assert(Presets.save('Food', {mode = 'any', include = {'electrical'}, exclude = {}}))
assert(#Presets.list() == 1 and Presets.list()[1].rule.mode == 'any' and disk[b], 'overwrite did not replace rule')
local unicodeName = 'Еда|быстро, 100%'
local escapedRule = {mode = 'all', include = {'category:日本,raw|100%'}, exclude = {}}
assert(Presets.save(unicodeName, escapedRule))
local found
for _, entry in ipairs(reopen().list()) do if entry.name == unicodeName then found = entry.rule end end
assert(found and found.include[1] == escapedRule.include[1], 'Unicode or escaped separator did not round-trip')
assert(disk[a]:find('%%7C') and disk[a]:find('%%2C') and disk[a]:find('%%25'), 'unsafe line delimiter encoding')
assert(Presets.save("loadstring('never execute this')", {exclude = {'meat'}}), 'text resembling code was evaluated/rejected')
assert(Presets.save('AAA', {include = {'food'}}))
assert(Presets.list()[1].name == 'AAA', 'list is not sorted')
assert(Presets.remove(' Food ') and #Presets.list() == 3, 'remove failed')
local beforeWrites = writes
assert(Presets.remove('missing') and writes == beforeWrites, 'absent delete rewrote disk')
for _, entry in ipairs(Presets.list()) do assert(Presets.remove(entry.name)) end
assert(#reopen().list() == 0, 'empty collection did not persist')

for _, value in ipairs({'', '   ', 'line\nname', '\tname', 'nul\0name', 'del\127name', string.rep('x', 161)}) do
    errorIs('InvalidName', Presets.save, value, {include = {'food'}})
    errorIs('InvalidName', Presets.remove, value)
end
errorIs('InvalidName', Presets.save, false, {include = {'food'}})
for _, value in ipairs({false, 'food', {}, {mode = 'wrong', include = {'food'}}, {include = {'unknown'}},
    {include = {'food'}, exclude = {'food'}}}) do errorIs('InvalidRule', Presets.save, 'invalid', value) end
errorIs('InvalidRule', Presets.save, 'invalid', nil)
reset()
assert(Presets.save(string.rep('я', 80), {include = {'food'}}), '160-byte Unicode name rejected')
errorIs('InvalidName', Presets.save, string.rep('я', 81), {include = {'food'}})
reset()
for index = 1, 32 do assert(Presets.save(tostring(index), {include = {'food'}})) end
errorIs('Limit', Presets.save, '33', {include = {'food'}})
assert(Presets.save('1', {include = {'electrical'}}), 'overwrite incorrectly counted against limit')
assert(Presets.remove('1') and Presets.save('33', {include = {'food'}}))

local function stable()
    reset(); assert(Presets.save('original', {include = {'food'}}))
    return disk[a]
end
local original = stable()
assert(Presets.save('newer', {include = {'electrical'}}))
disk[b] = disk[b]:sub(1, #disk[b] - 8)
assert(#reopen().list() == 1 and reopen().list()[1].name == 'original', 'truncated newer slot did not recover older')
assert(Presets.save('repaired', {exclude = {'meat'}}) and disk[a] == original, 'recovery overwrote selected old slot')
assert(#reopen().list() == 2, 'corrupt slot was not repairable')
disk[a], disk[b] = disk[b], 'truncated old write'
assert(#reopen().list() == 2 and Presets.save('other-slot', {include = {'food'}}), 'reverse-slot recovery failed')

for _, fault in ipairs({{writerNil = true}, {writerThrows = true}, {prefix = 0}, {prefix = 12}, {prefix = 12, writeThrows = true},
    {prefix = 12, writeCloseThrows = true}, {readback = true}}) do
    original = stable(); faults[b] = fault
    errorIs('WriteFailed', Presets.save, 'replacement', {include = {'electrical'}})
    assert(disk[a] == original, 'failed write modified previous valid slot')
    faults = {}
    if fault.prefix or disk[b] == '' then
        assert(reopen().list()[1].name == 'original', 'partial failed write lost old preset')
    end
end
for _, fault in ipairs({{readerNil = true}, {readerThrows = true}, {readThrows = 1}, {readThrows = 2},
    {readInvalid = true}, {readCloseThrows = true}}) do
    original = stable(); faults[a] = fault
    errorIs('ReadFailed', Presets.list)
    errorIs('ReadFailed', Presets.save, 'new', {include = {'food'}})
    errorIs('ReadFailed', Presets.remove, 'original')
    assert(disk[a] == original and disk[b] == '' and writes == 1, 'read error permitted write')
end
for _, fault in ipairs({{readerNil = true}, {readThrows = 1}, {readCloseThrows = true}}) do
    original = stable(); faults[b] = fault
    errorIs('ReadFailed', Presets.list)
    errorIs('ReadFailed', Presets.save, 'new', {include = {'food'}})
    assert(disk[a] == original and disk[b] == '' and writes == 1, 'failed empty-slot read permitted write')
end
original = stable(); faults.directory = true
errorIs('ReadFailed', Presets.list)
errorIs('ReadFailed', Presets.save, 'new', {include = {'food'}})
errorIs('ReadFailed', Presets.remove, 'original')
assert(disk[a] == original and disk[b] == '' and writes == 1,
    'native nil readers plus an empty inaccessible directory enumeration permitted overwrite')
assert(enumerations == 0, 'store still depends on ambiguous directory enumeration')
faults = {}
assert(reopen().list()[1].name == 'original', 'transient directory failure replaced readable data')

reset(); disk[a], disk[b] = '', ''
assert(#Presets.list() == 0 and #reopen().list() == 0 and writes == 0, 'zero-length slots are not uninitialized')
assert(Presets.save('initialized', {include = {'food'}}) and #reopen().list() == 1,
    'uninitialized slots cannot create a valid store')

-- Grouped entries require v2 so older readers cannot silently fall back to stale rules.
reset()
assert(Presets.save('legacy', {mode='any',include={'food','mechanics'},exclude={'vehiclepart'}}))
local grouped={groups={{include={'mechanics'},exclude={'vehiclepart'}},{include={'perishable'},exclude={}}}}
assert(Presets.save('grouped', grouped))
assert(disk[a]:find('PZST_TAG_FILTERS|1|',1,true) and disk[b]:find('PZST_TAG_FILTERS|2|',1,true))
grouped.groups[1].include[1]='food'
local reloaded=reopen().list()
local Tags=require 'PZSurvivorToolkit/ItemTags'
assert(#reloaded==2 and reloaded[1].rule.groups[1].include[1]=='mechanics')
assert(Tags.matchesRule({'perishable','vehiclepart'},reloaded[1].rule))
assert(not Tags.matchesRule({'mechanics','vehiclepart'},reloaded[1].rule))
assert(reloaded[2].rule.mode=='any' and #reloaded[2].rule.exclude==1,'mixed legacy rule changed during v2 reload')
for _,malformed in ipairs({
 'PZST_TAG_FILTERS|2|1|1\nG|Bad|0\nEND|1|1\n',
 'PZST_TAG_FILTERS|2|1|1\nG|Bad|65\nEND|1|1\n',
 'PZST_TAG_FILTERS|2|1|1\nG|Bad|2\nC|food|\nEND|1|1\n',
 'PZST_TAG_FILTERS|2|1|1\nG|Bad|1\nC|food|food\nEND|1|1\n',
 'PZST_TAG_FILTERS|1|1|1\nG|Bad|1\nC|food|\nEND|1|1\n',
}) do
 reset();disk[a]=malformed
 errorIs('ReadFailed',Presets.list)
 assert(writes==0)
end

for _, unknown in ipairs({'3', '100', 'future'}) do
    original = stable(); disk[b] = 'PZST_TAG_FILTERS|' .. unknown .. '|2|0\nEND|2|0\n'
    local protected = disk[b]
    errorIs('Version', Presets.list)
    errorIs('Version', Presets.save, 'new', {include = {'food'}})
    errorIs('Version', Presets.remove, 'original')
    assert(disk[a] == original and disk[b] == protected, 'unknown version overwritten')
end
original = stable(); disk[b] = 'PZST_TAG_FILTERS|3|future|header|changed|shape\n'
errorIs('Version', Presets.save, 'new', {include = {'food'}})
assert(disk[a] == original and disk[b]:find('changed|shape', 1, true), 'future header shape overwritten')

for _, malformed in ipairs({
    '\n', 'not a preset file', 'PZST_TAG_FILTERS|1|1|33\nEND|1|33\n',
    'PZST_TAG_FILTERS|1|0|0\nEND|0|0\n',
    'PZST_TAG_FILTERS|1|1|1\nP|Bad%ZZ|all|food|\nEND|1|1\n',
    'PZST_TAG_FILTERS|1|1|1\nP|Bad%0Aname|all|food|\nEND|1|1\n',
    'PZST_TAG_FILTERS|1|1|1\nP|Empty|all||\nEND|1|1\n',
    'PZST_TAG_FILTERS|1|1|1\nP|Sparse|all|food,|\nEND|1|1\n',
    'PZST_TAG_FILTERS|1|1|2\nP|Same|all|food|\nP|Same|all|food|\nEND|1|2\n',
    'PZST_TAG_FILTERS|1|1|0\nEND|1|1\n',
    'PZST_TAG_FILTERS|1|1|0\nEND|1|0\ntrailing\n',
    string.rep('x', 62001),
}) do
    reset(); disk[a] = malformed
    errorIs('ReadFailed', Presets.list)
    errorIs('ReadFailed', Presets.save, 'new', {include = {'food'}})
    assert(disk[a] == malformed and disk[b] == '' and writes == 0, 'unrecoverable corrupt file overwritten')
end
reset(); disk[a] = 'PZST_TAG_FILTERS|1|2147483647|0\nEND|2147483647|0\n'
errorIs('Limit', Presets.save, 'new', {include = {'food'}})
reset(); disk[a] = 'PZST_TAG_FILTERS|1|1|1\nP|A|all|food|\nEND|1|1\n'
disk[b] = 'PZST_TAG_FILTERS|1|1|1\nP|B|all|food|\nEND|1|1\n'
errorIs('ReadFailed', Presets.list)
assert(writes == 0, 'conflicting generation overwrote data')
print('Tag filter preset checks passed: fresh reads, normalization/detachment, sorted Unicode/escaping, overwrite/delete, limits, recovery, versions and IO/readback failures.')
