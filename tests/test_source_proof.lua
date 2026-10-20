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
