-- Test observer only. Install wrap(label, fn) at declaration time in disposable
-- sources, before other mods capture the callback. Wrappers retain their identity
-- across phases; begin/finish never replace a callback. The supplied monotonic
-- clock returns milliseconds. Measurements include observer overhead.
local Profile = {}
local MAX_LABELS, MAX_DEPTH, MAX_SAMPLES = 64, 128, 256
local registrations, registrationCount = {}, 0
local active

local function pack(...)
    return {n = select('#', ...), ...}
end

function Profile.wrap(label, fn)
    assert(type(label) == 'string' and label ~= '', 'profile label must be a nonempty string')
    assert(type(fn) == 'function', 'profile target must be a function')
    local registered = registrations[label]
    if registered and registered.fn == fn then
        return registered.wrapper
    end
    if not registered then assert(registrationCount < MAX_LABELS, 'profile label limit exceeded') end
    local wrapper = function(...)
        local session = active
        if not session or session.pane and select(1, ...) ~= session.pane then return fn(...) end
        assert(session.depth < MAX_DEPTH, 'profile nesting limit exceeded')
        local metric = session.metrics[label]
        if not metric then
            metric = {calls = 0, inclusiveMs = 0, exclusiveMs = 0, maxMs = 0,
                errors = 0, samplesMs = {}, droppedSamples = 0}
            session.metrics[label] = metric
        end
        local parent = session.frame
        local frame = {parent = parent, childMs = 0, startedMs = session.clock()}
        session.frame, session.depth = frame, session.depth + 1
        local result = pack(pcall(fn, ...))
        -- Read the clock under protection too: a faulty observer clock must not
        -- leave a live frame after a caught error.
        local clockOk, stoppedMs = pcall(session.clock)
        session.frame, session.depth = parent, session.depth - 1
        if not clockOk then
            if not result[1] then error(result[2], 0) end
            error(stoppedMs, 0)
        end
        local elapsedMs = stoppedMs - frame.startedMs
        if parent then parent.childMs = parent.childMs + elapsedMs end
        metric.calls = metric.calls + 1
        metric.inclusiveMs = metric.inclusiveMs + elapsedMs
        metric.exclusiveMs = metric.exclusiveMs + elapsedMs - frame.childMs
        if elapsedMs > metric.maxMs then metric.maxMs = elapsedMs end
        if #metric.samplesMs < MAX_SAMPLES then
            metric.samplesMs[#metric.samplesMs + 1] = elapsedMs
        else
            metric.droppedSamples = metric.droppedSamples + 1
        end
        if not result[1] then
            metric.errors = metric.errors + 1
            error(result[2], 0)
        end
        return unpack(result, 2, result.n)
    end
    registrations[label] = {fn = fn, wrapper = wrapper}
    -- A source owner may reinstall its callback on a UI mode change. Keep only
    -- its latest registration; captured older wrappers stay valid and inert.
    if not registered then registrationCount = registrationCount + 1 end
    return wrapper
end

function Profile.begin(phase, monotonicClockFunction, pane)
    assert(not active, 'profile phase already active')
    assert(type(phase) == 'string' and phase ~= '', 'profile phase must be a nonempty string')
    assert(type(monotonicClockFunction) == 'function', 'profile clock must be a function')
    assert(pane == nil or type(pane) == 'table', 'profile target must be a pane table')
    active = {phase = phase, clock = monotonicClockFunction, metrics = {}, depth = 0, pane = pane}
end

function Profile.finish()
    assert(active, 'no active profile phase')
    assert(active.depth == 0 and active.frame == nil, 'profile phase has active frames')
    local receipt = {phase = active.phase, metrics = active.metrics, observerOverheadIncluded = true}
    active = nil
    return receipt
end

return Profile
