toolkitLuaMetatableMatches=NativeMetatableMatches or assert(loadfile((ProjectRoot or '.')..'/tests/support/source_binding.lua'))()
local loadProof = TestLoadSourceProof or function()
    return dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua')
end
local Proof = TestSourceProof or loadProof()
local unicodeA, unicodeB = TestUnicodeA or 'A洗😀é', TestUnicodeB or '第二行'
local path, opened, closed = 'media/lua/reviewed.lua', 0, 0
local lines, failRead, failClose = {}, false, false
local function input(request)
    assert(request == path)
    opened = opened + 1
    local index = 0
    return {readLine = function()
        if failRead then error('read failure') end
        index = index + 1
        return lines[index]
    end, close = function()
        closed = closed + 1
        if failClose then error('close failure') end
    end}
end
getGameFilesInput = input
getModFileReader = function(mod, request, create)
    assert(mod == 'ReviewedMod' and create == false)
    return input(request)
end
-- Values calculated independently from UTF16LE code units, with LF after each reader line.
for caseIndex, case in ipairs({{{}, 5381, 1}, {{''}, 177583, 720907},
    {{'ASCII'}, 2776777944, 95289716}, {{unicodeA}, 3486596461, 541533351},
    {{unicodeA, unicodeB}, 3972438779, 2618652356}}) do
    lines = case[1]
    assert(Proof.matches(path, case[2]), 'DJB vector ' .. caseIndex)
    assert(Proof.matches(path, case[3], 'ReviewedMod', true), 'Adler vector ' .. caseIndex)
    assert(not Proof.matches(path, case[2] + 1))
end
assert(opened == closed)
lines = {unicodeA}
assert(Proof.matches(path, 3486596461, nil, false, 6))
assert(not Proof.matches(path, 3486596461, nil, false, 5))
failRead = true; assert(not Proof.matches(path, 3486596461)); failRead = false
failClose = true; assert(not Proof.matches(path, 3486596461)); failClose = false
assert(opened == closed, 'every opened reader must be closed, including failures')
lines = {'ASCII'}
assert(Proof.matches(path, 2776777944))
lines = {'changed'}
assert(not Proof.matches(path, 2776777944), 'source proofs must not cache previous success')
lines = {false}
assert(not Proof.matches(path, 5381), 'invalid reader data is not EOF')
assert(not Proof.matches(path, nil), 'failed hashing cannot match a missing expected pin')
getGameFilesInput = function() error('open failure') end
assert(not Proof.matches(path, 5381))
getGameFilesInput = function() return nil end
assert(not Proof.matches(path, 5381))
getGameFilesInput = nil
assert(not Proof.matches(path, 5381))
getGameFilesInput = input
if string.byte('洗') == 230 then
    for _, bytes in ipairs({{128}, {192, 128}, {226, 130}, {224, 128, 128},
        {237, 160, 128}, {240, 128, 128, 128}, {244, 144, 128, 128}, {245, 128, 128, 128}}) do
        lines = {string.char(unpack(bytes))}
        local naive = 5381
        for _, byte in ipairs(bytes) do naive = (naive * 33 + byte) % 4294967296 end
        assert(not Proof.matches(path, (naive * 33 + 10) % 4294967296), 'reject malformed UTF8 even at its raw-byte pin')
    end
end
-- These pins describe the reader's returned content, not a second newline or
-- Unicode normalization pass. Native real-reader transport is checked separately.
do
    local function reader(values)
        local index = 0
        return {readLine = function() index = index + 1; return values[index] end}
    end
    for _, case in ipairs({{{'A'}, 5862064, 9306188}, {{'A\r\nB'}, 211717353, 36307109},
        {{'A', 'B'}, 2088822588, 28573848}, {{string.char(0)}, 5859919, 786443},
        {{'', ''}, 5860249, 2097173}, {{'\r'}, 5860348, 2490392}}) do
        assert(Proof.checksum(reader(case[1]), false) == case[2], 'literal reader-content DJB pin changed')
        assert(Proof.checksum(reader(case[1]), true) == case[3], 'literal reader-content Adler pin changed')
    end
    for _, case in ipairs({{expected=5862064}, {adler=false, expected=5862064},
        {adler=0, expected=9306188}, {adler='false', expected=9306188}, {adler={}, expected=9306188}}) do
        assert(Proof.checksum(reader({'A'}), case.adler) == case.expected, 'checksum changed Lua algorithm truthiness')
    end
    for _, limit in ipairs({2, 2.5, math.huge, 0/0, false}) do
        assert(Proof.checksum(reader({'A'}), false, limit) == 5862064, 'accepted limit semantics changed')
    end
    for _, limit in ipairs({0, 1, 1.5, -1, -math.huge}) do
        assert(Proof.checksum(reader({'A'}), false, limit) == nil, 'character/LF limit boundary changed')
    end
    for _, limit in ipairs({0, -1, -math.huge, {}, 'invalid'}) do
        assert(Proof.checksum(reader({}), false, limit) == 5381, 'empty input unexpectedly validated an unused limit')
    end
    assert(Proof.checksum(reader({''}), false, 0) == nil, 'blank reader record lost its synthetic LF')
    assert(Proof.checksum(reader({''}), false, 1) == 177583)
    assert(not pcall(Proof.checksum, reader({'A'}), false, {}), 'direct checksum swallowed a limit comparison error')
    local closeCalls = 0
    assert(not pcall(Proof.checksum, {readLine=function() error('direct read failure') end,
        close=function() closeCalls=closeCalls+1 end}, false), 'direct checksum swallowed a reader error')
    assert(closeCalls == 0, 'checksum assumed matches ownership of reader close')
end

-- Supplementary characters consume two UTF16 units, then the synthetic LF.
-- The native harness supplies Unicode strings intact; the offline UTF8 branch
-- builds the same character without relying on its byte/character index layout.
do
    local utf8 = string.byte('洗') == 230
    local supplementary = utf8 and string.char(240, 159, 152, 128) or string.sub(unicodeA, 3, 4)
    local function reader()
        local first = true
        return {readLine=function() if first then first=false; return supplementary end end}
    end
    for _, limit in ipairs({0, 1, 2, 2.5}) do
        assert(Proof.checksum(reader(), false, limit) == nil, 'surrogate/LF boundary gained a unit')
    end
    assert(Proof.checksum(reader(), false, 3) == 255536236, 'supplementary DJB pin changed')
    assert(Proof.checksum(reader(), true, 3) == 1157674583, 'supplementary Adler pin changed')
    local floor, floorCalls = math.floor, 0
    math.floor = function(value) floorCalls=floorCalls+1; return floor(value) end
    local ok, value = pcall(Proof.checksum, reader(), false, 0)
    math.floor = floor
    assert(ok and value == nil and floorCalls == (utf8 and 1 or 0),
        'UTF8 high-unit argument was not evaluated before the exhausted limit')
end

-- A live byte replacement may supply continuation units beyond the returned
-- string. The decoder still owes one LF after its logical character, even when
-- its byte cursor jumps beyond the physical string and the limit stops at LF.
if string.byte('洗') == 230 then
    local line, byte = string.char(240), string.byte
    for _, case in ipairs({{adler=false, expected=255536236}, {adler=true, expected=1157674583}}) do
        for _, limit in ipairs({1, 2, 3}) do
            local indexes, reads = {}, 0
            string.byte = function(value, index)
                assert(value == line and index >= 1 and index <= 4)
                indexes[#indexes+1] = index
                if index == 1 then return byte(value, index) end
                return ({159, 152, 128})[index-1]
            end
            local ok, actual = pcall(Proof.checksum, {readLine=function()
                reads=reads+1; if reads == 1 then return line end
            end}, case.adler, limit)
            string.byte = byte
            local expected = limit == 3 and case.expected or nil
            assert(ok and actual == expected, 'replaced byte cursor skipped the mandatory LF/limit')
            assert(table.concat(indexes, ',') == '1,2,3,4', 'replacement byte lookup order changed or included synthetic LF')
            assert(reads == (limit == 3 and 2 or 1), 'limit rejection read past the current logical character/LF')
        end
    end
end

-- Method/global bindings remain live across reader reentry. The synthetic LF
-- never causes an extra string.byte lookup, and matches closes the current method.
do
    local byte, trace = string.byte, {}
    local replacementOpens = 0
    local function secondByte(value, index)
        trace[#trace+1]='byte-second:'..index; assert(index == 2)
        return byte(value, index)
    end
    local function firstByte(value, index)
        trace[#trace+1]='byte-first:'..index; assert(index == 1)
        string.byte=secondByte
        return byte(value, index)
    end
    getGameFilesInput = function(request)
        assert(request == path)
        getGameFilesInput = function() replacementOpens=replacementOpens+1; error('replacement opener') end
        local reader
        reader = {close=function() error('stale close method') end, readLine=function(self)
            trace[#trace+1]='read-first'
            local once = true
            assert(Proof.checksum({readLine=function() if once then once=false; return 'C' end end}, false) == 5862130,
                'nested checksum corrupted its parent state')
            self.readLine = function(current)
                trace[#trace+1]='read-next'
                current.close=function() trace[#trace+1]='close-current' end
            end
            string.byte=firstByte
            return 'AB'
        end}
        return reader
    end
    local ok, matched = pcall(Proof.matches, path, 193449970)
    string.byte = byte
    local replaced = Proof.matches(path, 193449970)
    getGameFilesInput = input
    assert(ok and matched and not replaced and replacementOpens == 1, 'opener capture/replacement semantics changed')
    assert(table.concat(trace, ',') == 'read-first,byte-first:1,byte-second:2,read-next,close-current',
        'reader/byte/current-close observation order changed')
end

do
    local trace = {}
    getGameFilesInput = function()
        return {readLine=function() trace[#trace+1]='read'; return 'A' end,
            close=function() trace[#trace+1]='close' end}
    end
    local accepted = Proof.matches(path, 5862064, nil, false, 1)
    getGameFilesInput = input
    assert(not accepted and table.concat(trace, ',') == 'read,close', 'limit rejection read past the current line or skipped close')
    trace = {}
    getGameFilesInput = function()
        return {readLine=function(self)
            trace[#trace+1]='read-error'; self.close=function() trace[#trace+1]='close-after-error' end
            error('reentrant read failure')
        end, close=function() error('stale error close') end}
    end
    accepted = Proof.matches(path, 5381)
    getGameFilesInput = input
    assert(not accepted and table.concat(trace, ',') == 'read-error,close-after-error', 'read failure lost current close/reentry order')
end

local callback = function() end
local otherCallback = function() end
local filenameCalls = 0
getFilenameOfClosure = function(fn)
    assert(fn == callback or fn == otherCallback)
    filenameCalls = filenameCalls + 1
    return fn == callback and 'C:\\mods\\reviewed.lua' or '/native/other.lua'
end
local nativeAccessor = getFilenameOfClosure
Proof = loadProof()
assert(Proof.closure(callback, 'reviewed.lua'))
assert(not Proof.closure(callback, 'other.lua'))
for i = 1, 100 do
    assert(Proof.closure(callback, 'reviewed.lua'))
    assert(not Proof.closure(otherCallback, 'reviewed.lua') and Proof.closure(otherCallback, 'other.lua'))
end
assert(filenameCalls == 2, 'each distinct loaded callback has one independent source lookup, not one per action')
assert(not Proof.closure({}, 'reviewed.lua'))
assert(not Proof.closure(callback, nil))
getFilenameOfClosure = function() error('not a Lua closure') end
assert(not Proof.closure(callback, 'reviewed.lua'))
getFilenameOfClosure = function() return 1 end
assert(not Proof.closure(callback, 'reviewed.lua'))
getFilenameOfClosure = nil
assert(not Proof.closure(callback, 'reviewed.lua'))
local replacement = function() end
filenameCalls = 0
getFilenameOfClosure = function(fn)
    filenameCalls = filenameCalls + 1
    return fn == callback and 'reviewed.lua' or 'replacement.lua'
end
assert(Proof.closure(callback, 'reviewed.lua'))
assert(not Proof.closure(replacement, 'reviewed.lua'))
assert(Proof.closure(replacement, 'replacement.lua') and filenameCalls == 3,
    'different closures never inherit another function\'s origin')
local currentFilename = 'changed.lua'
getFilenameOfClosure = function() return currentFilename end
assert(not Proof.closure(callback, 'reviewed.lua') and Proof.closure(callback, 'changed.lua'),
    'replacing the filename accessor invalidates previous metadata')
currentFilename = 'changed-again.lua'
assert(not Proof.closure(callback, 'changed.lua') and Proof.closure(callback, currentFilename),
    'a replacement accessor remains live even if it changes results without changing identity')
getFilenameOfClosure = nativeAccessor
local callsBeforeRestore = filenameCalls
assert(Proof.closure(callback, 'reviewed.lua') and filenameCalls == callsBeforeRestore + 1,
    'restoring the original accessor cannot reuse metadata from before replacement')
local available = false
getFilenameOfClosure = function()
    if not available then error('temporary lookup failure') end
    return 'restored.lua'
end
Proof = loadProof()
assert(not Proof.closure(callback, 'restored.lua'))
available = true
assert(Proof.closure(callback, 'restored.lua'), 'failed lookups remain retryable')
local lookupResult = 1
getFilenameOfClosure = function() return lookupResult end
Proof = loadProof()
assert(not Proof.closure(callback, 'restored.lua'))
lookupResult = 'restored.lua'
assert(Proof.closure(callback, 'restored.lua'), 'nonstring lookup results remain retryable')
filenameCalls = 0
getFilenameOfClosure = function() filenameCalls = filenameCalls + 1; return 'bounded.lua' end
Proof = loadProof()
assert(Proof.closure(callback, 'bounded.lua'))
local transient = {}
for i = 1, 1100 do
    transient[i] = function() return i end
    assert(Proof.closure(transient[i], 'bounded.lua'))
end
local before = filenameCalls
assert(Proof.closure(callback, 'bounded.lua') and filenameCalls == before + 1,
    'transient callbacks cannot leave an unbounded retained origin table in Kahlua')
assert(Proof.closure(callback, 'bounded.lua') and filenameCalls == before + 1)
assert(opened == closed)
print('Source proof checks passed: Unicode pins, fresh reads, bounded closure origins, replacement and retry.')


-- This is a synchronous binding watcher only; it never runs a proof/guard.
do
    local callbackCalls = 0
    local prototype = {inherited = 8}
    local meta = {__index = function() callbackCalls = callbackCalls + 1; error('watcher index callback') end,
        __eq = function() callbackCalls = callbackCalls + 1; error('watcher equality callback') end}
    local owner = setmetatable({value = {}, unused = 1}, meta)
    local marker = owner.value
    local keys = {'value', 'missing'}
    local specifications = {{owner = owner, keys = keys}}
    local watch = assert(Proof.captureBindings(specifications))
    keys[1] = 'other'; specifications[1].owner = prototype
    assert(watch() and callbackCalls == 0, 'watcher retained caller-owned specifications')
    owner.unused = 2
    assert(watch(), 'unselected state invalidated a selected binding')
    owner.missing = true
    assert(not watch() and callbackCalls == 0, 'missing own-field insertion was not observed')
    owner.missing = nil; owner.value = nil
    assert(not watch() and callbackCalls == 0, 'removed field dispatched __index')
    owner.value = marker
    assert(watch())
    setmetatable(owner, {})
    assert(not watch() and callbackCalls == 0, 'metatable identity was not observed')
end
do
    local meta = {__index = {value = 1}}
    local owner = setmetatable({}, meta)
    local watch = assert(Proof.captureBindings({{owner = owner, keys = {'value'}}}))
    assert(watch(), 'inherited Kahlua fields must be treated as absent own fields')
    owner.value = 1
    assert(not watch(), 'inherited and own bindings were confused')
    owner.value = nil
    assert(watch())
end
do
    local owner = {value = {}, disabled = false}
    local watch = assert(Proof.captureBindings({{owner = owner, exact = true}}))
    assert(watch())
    owner.new = false; assert(not watch()); owner.new = nil
    owner.disabled = nil; assert(not watch()); owner.disabled = false
    assert(watch(), 'exact map failed after exact restoration')
    owner.value = {}; assert(not watch(), 'object equality must use reference identity')
end
do
    local owner = {}
    for index = 1, 300 do owner[index] = index end
    local watch = assert(Proof.captureBindings({{owner = owner, keys = {1, 300, 'absent'}}}))
    assert(watch(), 'selected plain fields must not scan an entire large global table')
    assert(not Proof.captureBindings({{owner = owner, exact = true}}), 'whole-map capture exceeded its structural bound')
    setmetatable(owner, {__index=function()error('unknown inheritance callback')end})
    assert(not Proof.captureBindings({{owner = owner, keys = {1}}}), 'metatable-bearing scan exceeded its structural bound')
end
for _, bindings in ipairs({{}, {{owner = {}, keys = {}}}, {{owner = {}, keys = {'x', 'x'}}},
    {{owner = {}, exact = true, keys = {'x'}}}, {{owner = {}, exact = 'yes'}}, {{owner = {}, keys = {[2] = 'x'}}}}) do
    assert(not Proof.captureBindings(bindings), 'malformed binding specifications accepted')
end
do
    local owner = {}
    assert(not Proof.captureBindings({{owner = owner, keys = {'x'}}, {owner = owner, keys = {'y'}}}),
        'duplicate owners should be combined by their source owner')
    local values = {}
    for index = 1, 33 do values[index] = {owner = {}, keys = {'x'}} end
    assert(not Proof.captureBindings(values), 'too many source roles accepted')
end
print('Source binding watchers: selected/exact own fields, no callbacks, caller isolation and bounded work passed.')

do
    local action,owner={},{}
    for index=1,3000 do owner[index]=index end
    local parent={__mode='k'}
    setmetatable(owner,parent)
    local watch=assert(Proof.captureBindings({{owner=owner,keys={action}}}))
    assert(watch(),'selected weak-mode registry lookup must not scan the whole registry')
    parent[action]='inherited'
    assert(not watch(),'parent mutation could make native rawget inherit an action entry')
    parent[action]=nil
    assert(watch())
    owner[action]=true
    assert(not watch(),'new direct action claim was not observed')
    owner[action]=nil;parent.__mode='v'
    assert(not watch(),'inert metatable state changed after preparation')
end
print('Source selected registry lookup: large inert weak-mode maps retain exact own-field and parent-change semantics.')

do
    local parent,called={},0
    local owner=setmetatable({value=7},parent)
    local watch=assert(Proof.captureBindings({{owner=owner,keys={'value','missing'}}}))
    setmetatable(owner,{__metatable=parent,__index=function()called=called+1;error('hidden lookup invoked')end})
    assert(rawequal(getmetatable(owner),parent),'fixture must conceal the actual replacement')
    assert(not watch()and called==0,'visible metatable equality must not attest actual lookup ancestry')
end

-- Shared native class-chain proof preserves first-constructor absence and
-- rejects hidden/foreign lookup before Kahlua can invoke __index.
do
    local savedObject,savedBase=ISBaseObject,ISBaseTimedAction
    local function hierarchy()
        local object={};object.__index=object
        local base=setmetatable({},object);base.__index=base
        local class=setmetatable({},base)
        ISBaseObject,ISBaseTimedAction=object,base
        return object,base,class
    end
    local object,base,class=hierarchy()
    assert(Proof.nativeActionClassChain(object,base,class,true))
    assert(not Proof.nativeActionClassChain(object,base,class,false))
    class.__index=class
    assert(Proof.nativeActionClassChain(object,base,class,false))
    for _,slot in ipairs({'object','base','class','hidden-class'})do
        object,base,class=hierarchy();class.__index=class
        local calls=0
        local function foreign()calls=calls+1;error('foreign native-chain lookup invoked')end
        if slot=='object'then object.__index=foreign
        elseif slot=='base'then base.__index=foreign
        elseif slot=='class'then class.__index=foreign
        else setmetatable(class,{__metatable=base,__index=foreign})end
        assert(not Proof.nativeActionClassChain(object,base,class,false)and calls==0,
            'shared native-chain proof invoked '..slot..' __index')
    end
    ISBaseObject,ISBaseTimedAction=savedObject,savedBase
end
