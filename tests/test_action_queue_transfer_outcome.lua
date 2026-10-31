local modulePath = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/ActionQueueTransferOutcome.lua'
local events = Events
Events = setmetatable({}, {__index = function() error('transfer outcomes must not register polling') end})
local clockCalls = 0
getTimestampMs = function() clockCalls = clockCalls + 1; error('unexpected eager observation') end
local Outcome = assert(loadfile(modulePath))()
local observeWithoutHook = Outcome.observer(nil)
local unusedReader = Outcome.authorityReader(function() error('eager authority') end, function() error('eager authority') end)
assert(type(observeWithoutHook) == 'function' and type(unusedReader) == 'function' and clockCalls == 0,
    'loading/factory creation must not observe or poll')
Events = events

local checked = 0
local function test(label, body)
    body(); checked = checked + 1
end
local function equalTrace(trace, expected)
    assert(table.concat(trace, ',') == expected, 'getter order: ' .. table.concat(trace, ','))
end
local function item(id, kind, container, trace, prefix)
    local value = {id = id, kind = kind or 'Base.Book', container = container, consumed = false}
    local function record(name) if trace then trace[#trace + 1] = (prefix or '') .. name end end
    function value:getID() record('id'); return self.id end
    function value:getFullType() record('type'); return self.kind end
    function value:getContainer() record('container'); return self.container end
    function value:getIsCraftingConsumed() record('consumed'); return self.consumed end
    return value
end
local function fixture(authority, members)
    local state = {now = 100, trace = {}, arrived = {}, clock = 0}
    state.source = {items = {}}
    state.destination = {items = {}, exists = true}
    function state.source:getItemById(id)
        state.trace[#state.trace + 1] = 'source:' .. id; return self.items[id]
    end
    function state.destination:getItemById(id)
        state.trace[#state.trace + 1] = 'destination:' .. id; return self.items[id]
    end
    function state.destination:isExistYet()
        state.trace[#state.trace + 1] = 'exists'; return self.exists
    end
    getTimestampMs = function() state.clock = state.clock + 1; return state.now end
    state.proof = {source = state.source, destination = state.destination, direction = 'return'}
    state.attempt = {finished = true, succeeded = true, authority = authority, deadline = 200,
        members = members or {{id = 81, fullType = 'Base.Book'}}}
    state.observe = Outcome.observer(function(proof, member)
        assert(proof == state.proof and member.completed == true and not state.attempt.terminal,
            'arrival callback must follow confirmation and precede terminal counting')
        state.arrived[member.id] = (state.arrived[member.id] or 0) + 1
    end)
    function state.put(id, target, kind)
        local value = item(id, kind, target, state.trace)
        target.items[id] = value
        return value
    end
    return state
end

test('authority is explicit, fresh and identity-bound', function()
    local doneValue, rejectedValue, calls = true, false, {}
    local done = function(id) calls[#calls + 1] = 'done:' .. id; return doneValue end
    local rejected = function(id) calls[#calls + 1] = 'rejected:' .. id; return rejectedValue end
    isItemTransactionDone, isItemTransactionRejected = done, rejected
    local read = Outcome.authorityReader(done, rejected)
    assert(read(false, nil) == 'native' and #calls == 0)
    assert(read(true, 17) == 'completed'); equalTrace(calls, 'done:17,rejected:17')
    calls = {}; doneValue, rejectedValue = false, true
    assert(read(true, 17) == 'rejected'); equalTrace(calls, 'done:17,rejected:17')
    for _, pair in ipairs({{true, true}, {false, false}, {'yes', false}}) do
        doneValue, rejectedValue = pair[1], pair[2]
        assert(read(true, 17) == 'unavailable', 'ambiguous/absent authority cannot complete')
    end
    calls = {}
    for _, invalid in ipairs({0, false, '17', 1.5, math.huge}) do
        assert(read(true, invalid) == 'unavailable')
    end
    assert(#calls == 0, 'invalid transaction IDs must not query authority')
    isItemTransactionDone = function() error('foreign transaction helper must not run') end
    assert(read(true, 17) == 'unavailable' and #calls == 0)
    isItemTransactionDone = done
end)

for _, authority in ipairs({'native', 'completed'}) do
    test(authority .. ' still requires exact physical effect', function()
        local s = fixture(authority)
        assert(s.observe(s.proof, s.attempt) == 'waiting' and not s.attempt.members[1].completed)
        s.put(81, s.destination)
        assert(s.observe(s.proof, s.attempt) == 'completed' and s.arrived[81] == 1)
    end)
end
for _, authority in ipairs({'rejected', 'unavailable'}) do
    test(authority .. ' cannot be promoted by physical effect', function()
        local s = fixture(authority); s.put(81, s.destination)
        assert(s.observe(s.proof, s.attempt) == authority and not s.arrived[81])
        assert(#s.trace == 0 and s.clock == 0, 'terminal authority must precede endpoint/time getters')
    end)
end

for _, invalid in ipairs({'wrong-id', 'wrong-type', 'wrong-container', 'consumed', 'source-duplicate'}) do
    test('effect rejection: ' .. invalid, function()
        local s = fixture('completed'); local value = s.put(81, s.destination)
        if invalid == 'wrong-id' then value.id = 82
        elseif invalid == 'wrong-type' then value.kind = 'Base.Other'
        elseif invalid == 'wrong-container' then value.container = s.source
        elseif invalid == 'consumed' then value.consumed = true
        else s.put(81, s.source, 'Base.Other') end
        assert(s.observe(s.proof, s.attempt) == 'waiting' and not s.arrived[81], invalid)
        s.now = 200
        assert(s.observe(s.proof, s.attempt) == 'unavailable')
    end)
end

test('endpoint lookup order before exact item getters', function()
    local s = fixture('native'); s.put(81, s.destination)
    assert(s.observe(s.proof, s.attempt) == 'completed')
    equalTrace(s.trace, 'exists,destination:81,source:81,id,type,container,consumed')
end)
test('partial prefix stays confirmed; callback runs once', function()
    local s = fixture('completed', {{id = 81, fullType = 'Base.Book'}, {id = 82, fullType = 'Base.Book'}})
    s.put(81, s.destination)
    assert(s.observe(s.proof, s.attempt) == 'waiting' and s.attempt.members[1].completed and not s.attempt.members[2].completed)
    s.destination.items[81] = nil
    s.trace = {}; s.put(82, s.destination)
    assert(s.observe(s.proof, s.attempt) == 'completed' and s.arrived[81] == 1 and s.arrived[82] == 1)
    equalTrace(s.trace, 'exists,destination:82,source:82,id,type,container,consumed')
    getTimestampMs = function() error('terminal result must not poll time') end
    s.destination.isExistYet = function() error('terminal result must not poll destination') end
    assert(s.observe(s.proof, s.attempt) == 'completed' and s.arrived[81] == 1 and s.arrived[82] == 1)
end)
test('timeout is sticky and unfinished attempts do not poll', function()
    local s = fixture('native'); s.attempt.finished = false
    assert(s.observe(s.proof, s.attempt) == 'waiting' and s.clock == 0 and #s.trace == 0)
    s.attempt.finished = true; s.now = 200
    assert(s.observe(s.proof, s.attempt) == 'unavailable' and #s.trace == 0)
    s.now = 100; s.put(81, s.destination)
    assert(s.observe(s.proof, s.attempt) == 'unavailable' and not s.arrived[81])
end)
test('failed native callback becomes terminal before effect polling', function()
    local s = fixture('native'); s.put(81, s.destination); s.attempt.succeeded = false
    assert(s.observe(s.proof, s.attempt) == 'unavailable' and not s.arrived[81])
    assert(s.clock == 0 and #s.trace == 0)
    s.attempt.succeeded = true
    assert(s.observe(s.proof, s.attempt) == 'unavailable' and s.clock == 0 and #s.trace == 0)
end)
test('observer has no cross-proof item-ID cache', function()
    local observe = Outcome.observer(nil)
    local first = fixture('native'); first.put(81, first.destination)
    assert(observe(first.proof, first.attempt) == 'completed')
    local second = fixture('native')
    assert(observe(second.proof, second.attempt) == 'waiting' and not second.attempt.members[1].completed)
end)

local function retentionFixture(kind)
    local trace, root, destination = {}, {items = {}}, {items = {}}
    function root:getItemById(id) trace[#trace + 1] = 'root:' .. id; return self.items[id] end
    function destination:getItemById(id) trace[#trace + 1] = 'destination:' .. id; return self.items[id] end
    local actual = item(81, kind, root, trace)
    root.items[81] = actual
    local character = {getInventory = function() trace[#trace + 1] = 'inventory'; return root end}
    local action = setmetatable({character = character}, {__index = function(_, key)
        assert(key == 'item'); trace[#trace + 1] = 'action.item'; return actual
    end})
    return action, {source = root, destination = destination, id = 81, fullType = 'Base.Book'}, trace, actual
end
test('proxy identity is value-based but retention reads action.item late', function()
    local proxy = item(81, 'Base.Book', nil)
    assert(Outcome.sameMember(proxy, {id = 81, fullType = 'Base.Book'}))
    local action, execution, trace = retentionFixture('Base.Book')
    assert(Outcome.retained(action, execution))
    equalTrace(trace, 'inventory,root:81,destination:81,id,type,action.item,container,consumed')
end)
test('wrong type never evaluates action.item', function()
    local action, execution, trace = retentionFixture('Base.Other')
    assert(not Outcome.retained(action, execution))
    equalTrace(trace, 'inventory,root:81,destination:81,id,type')
end)
test('retention still performs both lookups before source comparison', function()
    local action, execution, trace = retentionFixture('Base.Book'); execution.source = {}
    assert(not Outcome.retained(action, execution))
    equalTrace(trace, 'inventory,root:81,destination:81')
end)
test('same ID does not replace retained action object identity', function()
    local action, execution, trace = retentionFixture('Base.Book')
    rawset(action, 'item', item(81, 'Base.Book', execution.source))
    assert(not Outcome.retained(action, execution))
    equalTrace(trace, 'inventory,root:81,destination:81,id,type')
end)

local function sourceFixture()
    local s = fixture('native')
    s.actor = {}
    s.action = {character = s.actor, srcContainer = s.source, destContainer = s.destination}
    s.action.item = s.put(81, s.source)
    s.expected = {actor = s.actor, source = s.source, destination = s.destination, id = 81, fullType = 'Base.Book'}
    return s
end

test('fresh source evidence is bounded and invokes no native admission or mutation', function()
    local s = sourceFixture()
    local function forbidden() error('source evidence must not execute native work') end
    s.action.isValid, s.action.checkQueueList, s.action.transferItem = forbidden, forbidden, forbidden
    s.source.isExistYet, s.destination.isExistYet = forbidden, forbidden
    assert(Outcome.atSource(s.action, s.expected) == true)
    equalTrace(s.trace, 'source:81,destination:81,id,type,container,consumed')
    assert(not s.attempt.members[1].completed and not s.attempt.terminal and s.clock == 0,
        'at-source evidence must not mark an arrival, query time or imply admission')
end)
for _, invalid in ipairs({'actor', 'source', 'destination', 'same-endpoint', 'missing', 'proxy', 'id', 'type',
    'location', 'consumed', 'duplicate'}) do
    test('fresh source rejection: ' .. invalid, function()
        local s = sourceFixture()
        if invalid == 'actor' then s.action.character = {}
        elseif invalid == 'source' then s.action.srcContainer = {}
        elseif invalid == 'destination' then s.action.destContainer = {}
        elseif invalid == 'same-endpoint' then s.expected.destination = s.source; s.action.destContainer = s.source
        elseif invalid == 'missing' then s.source.items[81] = nil
        elseif invalid == 'proxy' then s.action.item = item(81, 'Base.Book', s.source)
        elseif invalid == 'id' then s.action.item.id = 82
        elseif invalid == 'type' then s.action.item.kind = 'Base.Other'
        elseif invalid == 'location' then s.action.item.container = s.destination
        elseif invalid == 'consumed' then s.action.item.consumed = true
        elseif invalid == 'duplicate' then s.put(81, s.destination) end
        assert(not Outcome.atSource(s.action, s.expected), invalid)
        assert(not s.attempt.terminal and not s.attempt.members[1].completed)
    end)
end
test('fresh source evidence is never cached and ignores a stale opposite index', function()
    local s = sourceFixture()
    s.destination.items[81] = item(81, 'Base.Book', {})
    assert(Outcome.atSource(s.action, s.expected))
    s.action.item.consumed = true
    assert(not Outcome.atSource(s.action, s.expected))
    s.action.item.consumed = false
    assert(Outcome.atSource(s.action, s.expected), 'a previous refusal must not reserve or retire an item')
end)
for _, invalid in ipairs({'actor', 'source', 'destination', 'item'}) do
    test('source getters cannot rebind ' .. invalid .. ' unnoticed', function()
        local s = sourceFixture()
        s.action.item.getIsCraftingConsumed = function()
            if invalid == 'item' then s.action.item = item(81, 'Base.Book', s.source)
            elseif invalid == 'actor' then s.action.character = {}
            elseif invalid == 'source' then s.action.srcContainer = {}
            else s.action.destContainer = {} end
            return false
        end
        assert(not Outcome.atSource(s.action, s.expected))
    end)
end

-- Optional private-host counter; no runtime hook is required by this suite.
if type(NativeTableCount) == 'function' then
    test('hot observations allocate no Lua tables', function()
        local waiting = fixture('native')
        local observed = fixture('native'); observed.put(81, observed.destination)
        local terminal = fixture('native'); terminal.attempt.terminal = 'completed'
        local source = sourceFixture()
        local before = NativeTableCount()
        for _ = 1, 32 do
            assert(Outcome.atSource(source.action, source.expected))
            assert(waiting.observe(waiting.proof, waiting.attempt) == 'waiting')
            observed.attempt.terminal = nil; observed.attempt.members[1].completed = nil
            assert(observed.observe(observed.proof, observed.attempt) == 'completed')
            assert(terminal.observe(terminal.proof, terminal.attempt) == 'completed')
        end
        assert(NativeTableCount() == before, 'observation must reuse caller-owned evidence')
    end)
end

print('Action transfer outcome: ' .. checked .. ' focused source/authority/effect, sticky-prefix, getter-order and stateless-observer cases passed.')
