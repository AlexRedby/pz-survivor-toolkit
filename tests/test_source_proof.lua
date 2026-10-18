local Proof = TestSourceProof or dofile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/SourceProof.lua')
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
getFilenameOfClosure = function(fn) assert(fn == callback); return 'C:\\mods\\reviewed.lua' end
assert(Proof.closure(callback, 'reviewed.lua'))
assert(not Proof.closure(callback, 'other.lua'))
assert(not Proof.closure({}, 'reviewed.lua'))
getFilenameOfClosure = function() error('not a Lua closure') end
assert(not Proof.closure(callback, 'reviewed.lua'))
getFilenameOfClosure = function() return 1 end
assert(not Proof.closure(callback, 'reviewed.lua'))
getFilenameOfClosure = nil
assert(not Proof.closure(callback, 'reviewed.lua'))
assert(opened == closed)
print('Source proof checks passed: Unicode pins, reader failures/close, limits, fresh reads and closure identity.')
