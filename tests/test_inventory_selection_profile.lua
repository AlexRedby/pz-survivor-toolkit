local fixture = ProjectRoot .. '/tests/native_queue/contributions/storage-profile/InventorySelectionProfile.lua'
local function fresh()
    return dofile(fixture)
end
local function pack(...)
    return {n = select('#', ...), ...}
end
local function sequence(values)
    local calls = 0
    return function()
        calls = calls + 1
        return assert(values[calls], 'unexpected clock read')
    end, function() return calls end
end
local function metricEquals(actual, calls, inclusive, exclusive, maximum, errors)
    assert(actual.calls == calls and actual.inclusiveMs == inclusive
        and actual.exclusiveMs == exclusive and actual.maxMs == maximum
        and actual.errors == errors)
end

do
    local profile=fresh()
    local first=profile.wrap('reinstalled',function()return 'first'end)
    local secondFn=function()return 'second'end
    local second=profile.wrap('reinstalled',secondFn)
    assert(second==profile.wrap('reinstalled',secondFn) and first()=='first' and second()=='second')
    profile.begin('owner reinstall',(sequence({0,1,2,4})))
    first();second()
    metricEquals(profile.finish().metrics.reinstalled,2,3,3,2,0)
end

do
    local profile,target,other=fresh(),{},{}
    local wrapped=profile.wrap('pane',function(pane)return pane end)
    profile.begin('one actual pane',sequence({0,3}),target)
    assert(wrapped(other)==other and wrapped(target)==target)
    metricEquals(profile.finish().metrics.pane,1,3,3,3,0)
end

do
    local profile = fresh()
    local child = profile.wrap('child', function() return nil, 'child', nil end)
    local parentFn = function(...)
        assert(select('#', ...) == 3 and select(1, ...) == 'argument'
            and select(2, ...) == nil and select(3, ...) == nil)
        local values = pack(child())
        assert(values.n == 3 and values[1] == nil and values[2] == 'child' and values[3] == nil)
        return nil, false, nil, 4, nil
    end
    local parent = profile.wrap('parent', parentFn)
    assert(profile.wrap('parent', parentFn) == parent, 'registration must retain wrapper identity')
    local clock, clockCalls = sequence({0, 2, 5, 10})
    local values = pack(parent('argument', nil, nil))
    assert(values.n == 5 and values[1] == nil and values[2] == false
        and values[3] == nil and values[4] == 4 and values[5] == nil)
    assert(clockCalls() == 0, 'inactive calls must not touch the phase clock')
    profile.begin('nested', clock)
    values = pack(parent('argument', nil, nil))
    assert(values.n == 5 and values[2] == false and values[4] == 4)
    local receipt = profile.finish()
    assert(receipt.phase == 'nested' and receipt.observerOverheadIncluded == true and clockCalls() == 4)
    metricEquals(receipt.metrics.parent, 1, 10, 7, 10, 0)
    metricEquals(receipt.metrics.child, 1, 3, 3, 3, 0)
    assert(receipt.metrics.parent.samplesMs[1] == 10 and receipt.metrics.child.samplesMs[1] == 3)
    parent('argument', nil, nil)
    assert(clockCalls() == 4, 'finish must make existing captured wrappers inert')
    profile.begin('empty', function() error('inactive clock must not be consulted') end)
    local empty = profile.finish()
    assert(empty.phase == 'empty' and empty.metrics.parent == nil, 'metrics must not leak across phases')
    metricEquals(receipt.metrics.parent, 1, 10, 7, 10, 0)
end

do
    local profile, failure = fresh(), {}
    local child = profile.wrap('error child', function() error(failure, 0) end)
    local parent = profile.wrap('error parent', function() return child() end)
    local ok, problem = pcall(parent)
    assert(not ok and problem == failure, 'inactive error object must remain identical')
    local clock = sequence({0, 1, 3, 7, 8, 11})
    profile.begin('caught error', clock)
    ok, problem = pcall(parent)
    assert(not ok and problem == failure, 'active error object must remain identical')
    -- This call after the caught error proves the prior parent is no longer live.
    local subsequent = profile.wrap('subsequent', function() end)
    assert(select('#', subsequent()) == 0, 'zero returns must stay zero returns')
    local receipt = profile.finish()
    metricEquals(receipt.metrics['error parent'], 1, 7, 5, 7, 1)
    metricEquals(receipt.metrics['error child'], 1, 2, 2, 2, 1)
    metricEquals(receipt.metrics.subsequent, 1, 3, 3, 3, 0)
end

do
    local profile, time = fresh(), 0
    local wrapped = profile.wrap('bounded', function() end)
    profile.begin('bounded', function() local value = time; time = time + 1; return value end)
    for _ = 1, 300 do wrapped() end
    local metric = profile.finish().metrics.bounded
    metricEquals(metric, 300, 300, 300, 1, 0)
    assert(#metric.samplesMs == 256 and metric.droppedSamples == 44)
    assert(metric.samplesMs[1] == 1 and metric.samplesMs[256] == 1)
end

do
    local profile = fresh()
    local recursive
    recursive = profile.wrap('recursive', function(depth)
        if depth > 0 then recursive(depth - 1) end
    end)
    local clock = sequence({0, 1, 2, 3, 5, 8})
    profile.begin('recursion', clock)
    recursive(2)
    local metric = profile.finish().metrics.recursive
    metricEquals(metric, 3, 13, 8, 8, 0)
    assert(metric.samplesMs[1] == 1 and metric.samplesMs[2] == 4 and metric.samplesMs[3] == 8)
end

do
    local profile, ticks = fresh(), 0
    local wrapped = profile.wrap('finish guard', function()
        local ok = pcall(profile.finish)
        assert(not ok, 'finish must reject active frames')
        assert(not pcall(profile.begin, 'replacement', function() return 0 end))
    end)
    assert(not pcall(profile.finish), 'finish must require an active phase')
    profile.begin('guarded', function() ticks = ticks + 1; return ticks end)
    wrapped()
    metricEquals(profile.finish().metrics['finish guard'], 1, 1, 1, 1, 0)
end

do
    local profile, failure, reads = fresh(), {}, 0
    local wrapped = profile.wrap('clock error', function() return 'ok' end)
    profile.begin('clock error', function()
        reads = reads + 1
        if reads == 2 then error(failure, 0) end
        return reads
    end)
    local ok, problem = pcall(wrapped)
    assert(not ok and problem == failure)
    profile.finish() -- The observer must unwind its frame even if its clock fails.
end

-- Kahlua does not provide next. A restricted environment also catches accidental
-- writes to global state while exercising the complete module lifecycle.
do
    local environment = {assert = assert, type = type, select = select, pcall = pcall,
        error = error, unpack = unpack}
    local chunk = assert(loadfile(fixture))
    setfenv(chunk, setmetatable(environment, {__newindex = function() error('global write') end}))
    local profile = chunk()
    local wrapped = profile.wrap('restricted', function() return nil, 'ok', nil end)
    local ticks = 0
    profile.begin('restricted', function() ticks = ticks + 1; return ticks end)
    local result = pack(wrapped())
    assert(result.n == 3 and result[2] == 'ok')
    metricEquals(profile.finish().metrics.restricted, 1, 1, 1, 1, 0)
end

print('PASS inventory selection observer: inert stable wrappers, nested timing, fidelity, errors and bounded collection')
