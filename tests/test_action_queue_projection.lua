local Projection
if TestProjectionSource then
    Projection = assert(loadstring(TestProjectionSource, '@ActionQueueProjection.lua'))()
else
    Projection = dofile(ProjectRoot ..
        '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueProjection.lua')
end

local originalCapture, originalCurrent = toolkitQueueViewSnapshot, toolkitQueueViewCurrentIndex
if not originalCapture then
    -- API test double for the offline Lua runtime. Native Kahlua runners provide
    -- the real bridge, which must remain installed for these same assertions.
    assert(not TestProjectionSource, 'the native projection runner must install the actual bridge')
    toolkitQueueViewSnapshot = function(list, previous, current)
        local unchanged = previous and previous.list == list and #previous.actions == #list
        for index = 1, #list do
            if type(list[index].toolkitQueueOperation) ~= 'table' then return nil end
            if not previous or previous.actions[index] ~= list[index]
                or previous.tokens[index] ~= list[index].toolkitQueueOperation then unchanged = false end
        end
        local state = unchanged and previous or {list = list, actions = {}, tokens = {}}
        state.current = nil
        for index = 1, #list do
            state.actions[index], state.tokens[index] = list[index], list[index].toolkitQueueOperation
            if list[index] == current then state.current = index end
        end
        return state
    end
    toolkitQueueViewCurrentIndex = function(state) return state.current end
end
local capture, currentIndex = toolkitQueueViewSnapshot, toolkitQueueViewCurrentIndex
assert(type(capture) == 'function' and type(currentIndex) == 'function')

local function action(token) return {toolkitQueueOperation = token} end
local firstToken, secondToken = {}, {}
local a, b, c, d = action(firstToken), action(firstToken), action(secondToken), action({})
local queue = {queue = {a, b, c, d}, current = b}
local state = Projection.capture(queue)
assert(not state.stable and state.native and state.currentIndex == 2)
local native = state.native
assert(Projection.capture(queue, state) == state and state.stable and state.native == native,
    'unchanged identities reuse the opaque snapshot')
queue.current = d
Projection.capture(queue, state)
assert(state.stable and state.currentIndex == 4,
    'current-only changes stay live without invalidating structure')
queue.current = {}
Projection.capture(queue, state)
assert(state.stable and state.currentIndex == nil, 'an absent current action has no projected index')
queue.current = nil
Projection.capture(queue, state)
assert(state.stable and state.currentIndex == nil)

-- Foreign writes deliberately bypass every queue API and generation counter.
queue.queue[2], queue.queue[3] = queue.queue[3], queue.queue[2]
Projection.capture(queue, state)
assert(not state.stable and state.native ~= native,
    'a same-size interior reorder must invalidate the native proof')
native = state.native
local replacement = action(secondToken)
queue.queue[2] = replacement
Projection.capture(queue, state)
assert(not state.stable and state.native ~= native,
    'a same-size interior replacement must be observed')
native = state.native
replacement.toolkitQueueOperation = firstToken
Projection.capture(queue, state)
assert(not state.stable and state.native ~= native,
    'retokening must invalidate the proof without replacing actions')
native = state.native
queue.queue[5] = action(firstToken)
Projection.capture(queue, state)
assert(not state.stable and state.native ~= native, 'raw append must invalidate the proof')
native = state.native
queue.queue[5] = nil
Projection.capture(queue, state)
assert(not state.stable and state.native ~= native, 'raw tail removal must invalidate the proof')
native = state.native
queue.queue = {a, replacement, b, d}
Projection.capture(queue, state)
assert(not state.stable and state.native ~= native, 'array replacement must not keep the former array snapshot')
queue.queue = {a, c, a}
queue.current = a
Projection.capture(queue, state)
assert(state.currentIndex == 3, 'duplicate action identities use the last matching current slot')
Projection.capture(queue, state)
assert(state.stable and state.currentIndex == 3)
local other = {queue = queue.queue, current = c}
local otherState = Projection.capture(other, state)
assert(otherState ~= state and otherState.queue == other and otherState.currentIndex == 2,
    'queue owners cannot retain one another\'s projection')
queue.queue, queue.current = {}, nil
Projection.capture(queue, state)
assert(not state.stable and state.native and state.currentIndex == nil)
Projection.capture(queue, state)
assert(state.stable and state.currentIndex == nil)

d.toolkitQueueOperation = nil
queue.queue, queue.current = {a, d}, d
Projection.capture(queue, state)
assert(not state.native and not state.stable and state.currentIndex == nil,
    'tokenless actions hand both grouping and current-index scans to the panel')

for _, mode in ipairs({'absent', 'unsupported', 'missing-current-reader'}) do
    toolkitQueueViewSnapshot = mode == 'unsupported' and function() return nil end
        or mode == 'missing-current-reader' and capture or nil
    toolkitQueueViewCurrentIndex = mode ~= 'missing-current-reader' and currentIndex or nil
    queue.queue, queue.current = {a, b, c}, b
    state = Projection.capture(queue)
    assert(not state.native and not state.stable and state.currentIndex == nil,
        mode .. ' fallback must defer its current-index scan to the panel')
    assert(Projection.capture(queue, state) == state and not state.stable and not state.native)
    queue.queue[2] = c
    Projection.capture(queue, state)
    assert(not state.native and not state.stable and state.currentIndex == nil)
    c.toolkitQueueOperation = firstToken
    Projection.capture(queue, state)
    assert(not state.native and not state.stable and state.currentIndex == nil)
    assert(queue.queue[1] == a and queue.queue[2] == c and queue.queue[3] == c
        and queue.current == b, mode .. ' fallback must not mutate native queue identities')
    c.toolkitQueueOperation = secondToken
end
toolkitQueueViewSnapshot, toolkitQueueViewCurrentIndex = originalCapture, originalCurrent
print('Queue projection: exact foreign-write detection, live native current indices, owner replacement and conservative fallback passed.')
