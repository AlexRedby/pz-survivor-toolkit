if not TestContextStorage then
    package.path = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/?.lua;' .. package.path
end
local Storage = TestContextStorage or require 'PZSurvivorToolkit/ContextMenuProfileStorage'
local a, b = 'PZSurvivorToolkit_ContextMenus_a.txt', 'PZSurvivorToolkit_ContextMenus_b.txt'
local legacy = 'PZSurvivorToolkit_ContextMenus.ini'
local disk, fault, opens, closes, writes, writerCloses = {}, {}, 0, 0, 0, 0
getFileReader = function(path, create)
    assert(create == true)
    if fault.readOpen == path then error('reader open failed') end
    if fault.readNil == path then return nil end
    if disk[path] == nil then disk[path] = '' end
    local values, index = {}, 0
    for line in disk[path]:gmatch('(.-)\n') do values[#values + 1] = line end
    if disk[path]:sub(-1) ~= '\n' and #disk[path] > 0 then
        values[#values + 1] = disk[path]:match('([^\n]*)$')
    end
    opens = opens + 1
    return {readLine = function()
        if fault.readLine == path then error('reader line failed') end
        if fault.readType == path then return false end
        index = index + 1
        return values[index]
    end, close = function()
        closes = closes + 1
        if fault.readClose == path then error('reader close failed') end
    end}
end
getFileWriter = function(path, create, append)
    assert(create == true and append == false and path ~= legacy)
    writes = writes + 1
    if fault.writerOpen then error('writer open failed') end
    if fault.writerNil then return nil end
    disk[path] = ''
    return {write = function(_, text)
        disk[path] = fault.cut and text:sub(1, fault.cut) or text
        if fault.write then error('write failed') end
    end, close = function()
        writerCloses = writerCloses + 1
        if fault.readback then fault.readOpen = path end
        if fault.writerClose then error('writer close failed') end
    end}
end
local function fails(fn, ...)
    assert(not pcall(fn, ...), 'storage accepted an invalid operation')
end
local function equal(a, b)
    assert(#a == #b)
    for index, value in ipairs(a) do assert(value == b[index], 'raw record changed') end
end
local empty = Storage.load()
assert(empty.generation == 0 and empty.slot == 2 and #empty.lines == 0 and writes == 0)
assert(disk[a] == '' and disk[b] == '' and disk[legacy] == '')
assert(#Storage.load().lines == 0 and writes == 0, 'empty slots prevented a repeated load')
local emptySnapshot = Storage.save(empty, {})
assert(emptySnapshot.generation == 1 and #Storage.load().lines == 0)

local name = TestContextUnicode or 'Кухня 食料 😀'
local baseline = {'G|custom:1|' .. name, 'R|label:Drop|custom:1', '', 'legacy-unknown-record|retained'}
local changed = {'G|custom:1|' .. name, 'R|label:Drop|hidden', 'N|*|equipment|Hands'}
disk, fault = {[legacy] = table.concat(baseline, '\n') .. '\n'}, {}
local legacyBytes = disk[legacy]
local imported = Storage.load()
assert(imported.generation == 0 and imported.slot == 2)
equal(imported.lines, baseline)
local first = Storage.save(imported, changed)
assert(first.slot == 1 and first.generation == 1)
equal(first.lines, changed); equal(Storage.load().lines, changed)
local firstBytes = disk[a]
assert(disk[legacy] == legacyBytes, 'migration modified the legacy file')

for _, kind in ipairs({'writerNil', 'writerOpen', 'zero', 'short', 'write', 'writeFull', 'writerClose', 'readback'}) do
    disk[a], disk[b], fault = '', '', {}
    if kind == 'zero' then fault.cut = 0
    elseif kind == 'short' or kind == 'write' then fault.cut = 8; fault.write = kind == 'write'
    elseif kind == 'writeFull' then fault.write = true
    else fault[kind] = true end
    local closedBefore = writerCloses
    fails(Storage.save, imported, changed)
    if kind ~= 'writerNil' and kind ~= 'writerOpen' then assert(writerCloses == closedBefore + 1) end
    fault = {}
    local recovered = Storage.load()
    if kind == 'writeFull' or kind == 'writerClose' or kind == 'readback' then
        assert(recovered.generation == 1, 'complete ambiguous migration was replaced by legacy')
        equal(recovered.lines, changed)
        local before = writes
        fails(Storage.save, imported, baseline)
        assert(writes == before, 'stale migration context opened a writer')
    else
        assert(recovered.generation == 0, 'interrupted first migration could not use retained legacy')
        equal(recovered.lines, baseline)
        assert(Storage.save(recovered, changed).generation == 1, 'migration retry failed')
    end
    assert(disk[legacy] == legacyBytes)
end
local function restore()
    disk[a], disk[b], fault = firstBytes, '', {}
end
for _, kind in ipairs({'writerNil', 'writerOpen', 'short', 'write', 'writeFull', 'writerClose', 'readback'}) do
    restore()
    if kind == 'short' or kind == 'write' then fault.cut = 8; fault.write = kind == 'write'
    elseif kind == 'writeFull' then fault.write = true
    else fault[kind] = true end
    fails(Storage.save, first, baseline)
    fault = {}
    local recovered = Storage.load()
    assert(disk[a] == firstBytes and disk[legacy] == legacyBytes, 'failure changed the retained snapshot')
    if kind == 'writeFull' or kind == 'writerClose' or kind == 'readback' then
        assert(recovered.generation == 2)
        equal(recovered.lines, baseline)
        local before = writes
        fails(Storage.save, first, changed)
        assert(writes == before, 'stale context overwrote a complete ambiguous commit')
        assert(Storage.save(recovered, changed).generation == 3)
    else
        assert(recovered.generation == 1)
        equal(recovered.lines, changed)
    end
end
restore()
local second = Storage.save(first, baseline)
local secondBytes = disk[b]
assert(second.slot == 2 and second.generation == 2 and disk[a] == firstBytes)
equal(Storage.load().lines, baseline)
for _, corrupt in ipairs({secondBytes:sub(1, #secondBytes - 8), secondBytes .. 'trailing\n',
    secondBytes:gsub('custom:1', 'custom:2'), 'PZST_CONTEXT|1|2|999999\n'}) do
    disk[b] = corrupt
    assert(Storage.load().generation == 1, 'corrupt newer slot did not fall back')
    equal(Storage.load().lines, changed)
end
disk[a], disk[b] = '', firstBytes
assert(Storage.load().slot == 2)
assert(Storage.save(Storage.load(), baseline).slot == 1, 'reverse-slot recovery did not alternate')
disk[a], disk[b] = 'broken\n', 'also broken\n'
fails(Storage.load)
disk[a], disk[b] = firstBytes, 'PZST_CONTEXT|99|future|shape\n'
fails(Storage.load)
restore()
local alternative = Storage.save(first, {'different'})
assert(alternative.generation == second.generation)
disk[a] = secondBytes
fails(Storage.load)

for _, kind in ipairs({'readOpen', 'readNil', 'readLine', 'readType', 'readClose'}) do
    for _, path in ipairs({a, b}) do
        restore(); fault[kind] = path
        local before = writes
        fails(Storage.load); fails(Storage.save, first, baseline)
        assert(writes == before and disk[a] == firstBytes and disk[b] == '', 'reader failure allowed a write')
    end
    disk[a], disk[b], fault = '', '', {[kind] = legacy}
    fails(Storage.load)
end
fault = {}
assert(opens == closes, 'reader leaked on an error path')
restore()
local stale = {generation = first.generation, slot = first.slot, lines = {'modified'}}
local before = writes
fails(Storage.save, stale, baseline)
fails(Storage.save, {generation = first.generation, slot = 2, lines = first.lines}, baseline)
fails(Storage.save, {generation = first.generation, slot = first.slot, lines = {[0] = 'extra', unpack(first.lines)}}, baseline)
assert(writes == before, 'changed raw context opened a writer')
local sparse = {[1] = 'first', [3] = 'third'}
for _, invalid in ipairs({false, {'bad\nrecord'}, {'bad\rrecord'}, {string.rep('x', 8193)}, sparse,
    {extra = 'field'}, {false}, {string.rep('x', 8192), nil, 'hole'}}) do
    fails(Storage.save, first, invalid)
end
if string.byte('洗') == 230 then fails(Storage.save, first, {string.char(255)}) end
local oversized = {}
for index = 1, 2442 do oversized[index] = string.rep('x', 8192) end
fails(Storage.save, first, oversized)
assert(writes == before, 'invalid records opened a writer')
local boundary = {string.rep('x', 8192)}
equal(Storage.save(first, boundary).lines, boundary)
equal(Storage.load().lines, boundary)
local Proof = require 'PZSurvivorToolkit/SourceProof'
local header = 'PZST_CONTEXT|1|2147483646|0'
local readHeader = false
local hash = Proof.checksum({readLine = function()
    if not readHeader then readHeader = true; return header end
end}, false, 20000000)
disk[a], disk[b] = header .. '\n' .. string.format('END|2147483646|%d\n', hash), ''
local maximum = Storage.load()
before = writes
assert(maximum.generation == 2147483646)
fails(Storage.save, maximum, {})
assert(writes == before, 'exhausted sequence opened a writer')
disk[a], disk[b], fault = '', '', {}
disk[legacy] = string.rep('x', 8193) .. '\nR|tail|hidden\n'
local longLegacy = disk[legacy]
local withTail = Storage.load()
equal(withTail.lines, {string.rep('x', 8193), 'R|tail|hidden'})
equal(Storage.save(withTail, {'R|tail|hidden'}).lines, {'R|tail|hidden'})
assert(disk[legacy] == longLegacy, 'oversized legacy record import changed the original file')
disk[a], disk[b] = '', ''
disk[legacy] = string.rep(string.rep('x', 8192) .. '\n', 2442)
fails(Storage.load)
assert(opens == closes)
print('Context menu profile storage passed: raw Unicode/legacy records, empty payload, alternating recovery, stale/ambiguous commits, bounds and I/O failures.')

-- Grouped payloads opt into v2; legacy raw records and v1 remain readable.
disk[a],disk[b],disk[legacy],fault='','','',{}
local groupedLines={'F|tags:1|Grouped|groups|2','B|tags:1|1|include|mechanics',
 'B|tags:1|1|exclude|vehiclepart','B|tags:1|2|include|perishable','R|drop|hidden'}
local groupedSnapshot=Storage.save(Storage.load(),groupedLines,2)
assert(groupedSnapshot.version==2 and disk[a]:find('PZST_CONTEXT|2|',1,true))
equal(Storage.load().lines,groupedLines)
assert(Storage.load().version==2)
local beforeWrites=writes
fails(Storage.save,groupedSnapshot,groupedLines,3)
assert(writes==beforeWrites,'unsupported write version opened a writer')
disk[b]='PZST_CONTEXT|3|future|shape\n'
fails(Storage.load)
fails(Storage.save,groupedSnapshot,baseline)
assert(writes==beforeWrites,'future profile snapshot was overwritten')
disk[b]=''
local withoutGroups=Storage.save(Storage.load(),baseline,1)
assert(withoutGroups.version==1)
equal(Storage.load().lines,baseline)
print('PASS context storage v1/v2 payloads, explicit write versions and unsupported-version overwrite guard')
