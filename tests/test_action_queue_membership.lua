local Membership = TestQueueMembership or dofile(ProjectRoot ..
    '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueMembership.lua')
local nativeNext = next
next = nil -- Kahlua does not provide this standard Lua global.

local function count(values)
    local size = 0
    for _ in pairs(values) do size = size + 1 end
    return size
end
local function player(dead)
    return {isDead = function() return dead == true end}
end
local first, second, dead = player(), player(), player(true)
local a, b, absent, unrelated = {character = first}, {character = first}, {}, {}
ISTimedActionQueue = {queues = nil}
assert(count(Membership.find({{}, {}})) == 0, 'empty registries must not inspect native queues')

local firstQueue, secondQueue = {queue = {a, unrelated}}, {queue = {b}}
ISTimedActionQueue.queues = {[first] = firstQueue, [second] = secondQueue}
local firstRegistry, secondRegistry = {[a] = {}}, {[b] = true, [absent] = true}
local found = Membership.find({firstRegistry, secondRegistry})
assert(count(found) == 2 and found[a] and found[b] and not found[absent] and not found[unrelated],
    'scan multiple queues, retaining only present tracked identities')
assert(count(firstRegistry) == 1 and count(secondRegistry) == 2, 'membership lookup must not mutate registries')
assert(b.character == first and found[b], 'identity in another player queue retains membership')

ISTimedActionQueue.queues = {[first] = {queue = {a, a}}, [second] = {queue = {a, b}}}
found = Membership.find({{[a] = true}, {[a] = true, [b] = true}})
assert(count(found) == 2 and found[a] and found[b],
    'duplicate registry and queue entries cannot finish the search before every distinct action is found')

ISTimedActionQueue.queues = {[dead] = {queue = {a, b}}, [first] = {queue = {a}}}
found = Membership.find({{[a] = true, [b] = true}})
assert(count(found) == 1 and found[a] and not found[b], 'dead player queues do not retain membership')
ISTimedActionQueue.queues = {[{}] = {queue = {b}}}
assert(Membership.find({{[b] = true}})[b], 'players without an isDead method preserve bulk-food semantics')
ISTimedActionQueue.queues = {[first] = {}, [second] = {queue = {}}}
assert(count(Membership.find({{[a] = true}})) == 0, 'missing or empty queue arrays contain no actions')

local queue = {queue = {a, unrelated}}
ISTimedActionQueue.queues = {[first] = queue}
assert(Membership.find({{[a] = true, [b] = true}})[a])
queue.queue[1] = b
found = Membership.find({{[a] = true, [b] = true}})
assert(not found[a] and found[b], 'same-size direct replacement must be observed on the next call')
ISTimedActionQueue.queues[first] = {queue = {a}}
found = Membership.find({{[a] = true, [b] = true}})
assert(found[a] and not found[b], 'replacing the native queue must discard its former membership')

local tail = {a, b}
for index = 3, 4098 do tail[index] = {} end
ISTimedActionQueue.queues = {[first] = {queue = tail}}
local nativeIpairs, visits = ipairs, 0
ipairs = function(values)
    local iterator, state, initial = nativeIpairs(values)
    if values ~= tail then return iterator, state, initial end
    return function(current, index)
        local following, value = iterator(current, index)
        if following then visits = visits + 1 end
        return following, value
    end, state, initial
end
local ok, failure = pcall(function()
    found = Membership.find({{[a] = true}, {[a] = true, [b] = true}})
    assert(found[a] and found[b] and visits == 2, 'stop before visiting the 4096 unrelated queued actions')
    visits = 0
    found = Membership.find({{[a] = true, [absent] = true}})
    assert(found[a] and not found[absent] and visits == #tail,
        'an absent tracked action requires the complete fresh queue scan')
end)
ipairs, next = nativeIpairs, nativeNext
assert(ok, failure)
print('Queue membership: fresh identities, all live queues and bounded unrelated-tail visits passed.')
