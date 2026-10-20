PZSurvivorToolkit = {}
local Model = assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueEditModel.lua'))()
local function entry(action, resources)
    return {action = action, edit = {version = 1, complete = true, capacity = 'unchanged', resources = resources}}
end
local function resource(domain, key, facts, requires, effects, bounds)
    return {domain = domain, key = key, facts = facts, requires = requires, effects = effects, bounds = bounds}
end
local function status(entries, expected, reason, blocker, key, field)
    local decision = Model.evaluate(entries)
    assert(decision.status == expected, 'status: ' .. tostring(decision.status) .. ' expected ' .. expected)
    if reason then assert(decision.reason == reason, 'reason: ' .. tostring(decision.reason) .. ' expected ' .. reason) end
    if blocker then assert(rawequal(decision.blocker, blocker)) end
    if key then assert(rawequal(decision.resource, key)) end
    if field then assert(decision.field == field) end
    return decision
end
local target, first, second = {}, {}, {}
local function device(action, effects, requires, facts)
    return entry(action, {resource('device', target, facts or {on = false}, requires, effects)})
end
local on, off = device(first, {{field = 'on', set = true}}), device(second, {{field = 'on', set = false}})
status({on, off}, 'allowed'); status({off, on}, 'allowed')
local use = device({}, nil, {{field = 'on', equal = true}})
status({on, off, use}, 'denied', 'edit_required_state', use.action, target, 'on')
status({off, on, use}, 'allowed')
status({on, use}, 'allowed')
status({use}, 'denied', 'edit_required_state')
status({device(first, {{field = 'on', toggle = true}}), use}, 'allowed')
assert(on.edit.resources[1].facts.on == false and on.edit.resources[1].effects[1].set == true, 'projection never changes contracts or live snapshot')
local atomic = entry({}, {resource('device', target, {on = false}, nil, {{field = 'on', set = true}}),
    resource('device', target, {on = false}, {{field = 'on', equal = true}})})
status({atomic}, 'denied', 'edit_required_state')
-- All snapshot declarations describe the same current state, rather than successive expected states.
status({on, device(second, nil, nil, {on = true})}, 'unhandled', 'edit_unknown')
local otherDomain = entry({}, {resource('other', target, {on = true}, {{field = 'on', equal = true}})})
status({on, otherDomain}, 'allowed')
local function amount(value, delta, bound, requires)
    local result = entry({}, {resource('stock', target, {count = value}, requires,
        delta and {{field = 'count', delta = delta}} or nil, bound and {count = bound} or nil)})
    if bound and bound.reason == 'edit_capacity' then result.edit.capacity = 'modeled' end
    return result
end
status({amount(1, -1, {min = 0, max = 2})}, 'allowed')
status({amount(1, -2, {min = 0, max = 2})}, 'denied', 'edit_resource_amount')
status({amount(3, nil, {min = 0, max = 2, reason = 'edit_capacity'})}, 'denied', 'edit_capacity')
status({amount(1, 2, {max = 2, reason = 'edit_capacity'})}, 'denied', 'edit_capacity')
status({amount(1, nil, {min = 0}), amount(1, nil, {min = 1})}, 'unhandled', 'edit_unknown')
status({amount(1, nil, nil, {{field = 'count', min = 2}})}, 'denied', 'edit_resource_amount')
status({amount(1, nil, nil, {{field = 'count', min = 0, max = 2}})}, 'allowed')
-- Removed commands still contribute their audited live snapshot, never their execution requirements/effects.
local removed = device({}, {{field = 'on', set = true}}, {{field = 'on', equal = true}})
removed.snapshotOnly = true
status({removed}, 'allowed')
status({removed, use}, 'denied', 'edit_required_state')
local removedSnapshot = entry({}, {resource('stock', target, {count = 1})}); removedSnapshot.snapshotOnly = true
local futureConsumer = entry({}, {resource('stock', target, {}, {{field = 'count', min = 1}}, {{field = 'count', delta = -1}})})
status({futureConsumer, removedSnapshot}, 'allowed')
removed.edit.version = 99; status({removed}, 'unhandled', 'edit_unknown')
removed.edit.version = 1; removed.active = true; status({removed}, 'unhandled', 'edit_in_flight')
local malformedRemoved = device({}, {{field = 'on', delta = -1}}); malformedRemoved.snapshotOnly = true
status({malformedRemoved}, 'unhandled', 'edit_unknown')
local hiddenCalls = 0
local opaqueMeta = {__eq = function() hiddenCalls = hiddenCalls + 1; error('opaque equality must be raw') end,
    __index = function() hiddenCalls = hiddenCalls + 1; error('opaque fields must not be read') end}
local opaque, another = setmetatable({}, opaqueMeta), setmetatable({}, opaqueMeta)
status({entry(first, {resource('identity', opaque, {value = opaque}, {{field = 'value', equal = opaque}})})}, 'allowed')
status({entry(first, {resource('identity', opaque, {value = opaque}, {{field = 'value', equal = another}})})},
    'denied', 'edit_required_state')
assert(hiddenCalls == 0)

local malformed = {
    function(e) e.edit.version = 2 end,
    function(e) e.edit.complete = false end,
    function(e) e.edit.capacity = 'unknown' end,
    function(e) e.edit.execute = function() error('never execute') end end,
    function(e) setmetatable(e.edit, {__index = function() error('never read') end}) end,
    function(e) e.edit.resources = {[2] = e.edit.resources[1]} end,
    function(e) e.edit.resources[1].facts.on = 0/0 end,
    function(e) e.edit.resources[1].facts.on = math.huge end,
    function(e) e.edit.resources[1].facts.on = function() error('never execute') end end,
    function(e) e.edit.resources[1].effects[1].set = nil; e.edit.resources[1].effects[1].delta = math.huge end,
    function(e) e.edit.resources[1].effects[1].delta = 1 end,
    function(e) e.edit.resources[1].effects[1].set = nil; e.edit.resources[1].effects[1].toggle = false end,
    function(e) e.edit.resources[1].effects[1].field = 'missing' end,
    function(e) e.edit.resources[1].requires = {{field = 'missing', equal = true}} end,
    function(e) e.edit.resources[1].requires = {{field = 'on', equal = true, min = 0}} end,
    function(e) e.edit.resources[1].requires = {{field = 'on', min = 2, max = 1}} end,
    function(e) e.edit.resources[1].bounds = {on = {min = 0, reason = 'arbitrary'}} end,
    function(e) e.edit.resources[1].bounds = {on = {min = 0}} end,
    function(e) e.edit.resources[1].key = nil end,
    function(e) e.edit.resources[1].domain = '' end,
    function(e) e.edit.resources[1].requires = false end,
    function(e) e.edit.resources[1].effects = false end,
    function(e) e.snapshotOnly = 1 end,
    function(e) e.edit.resources[1].facts = setmetatable({}, {__index = function() error('never execute') end}) end,
}
for _, mutate in ipairs(malformed) do
    local e = device(first, {{field = 'on', set = true}})
    mutate(e); status({e}, 'unhandled', 'edit_unknown')
end
local active = device(first); active.active = true
status({active}, 'unhandled', 'edit_in_flight', first)
status({device(first, {{field = 'on', toggle = true}}, nil, {on = 1})}, 'unhandled', 'edit_unknown')
status({amount(1e308, 1e308)}, 'unhandled', 'edit_unknown')
status({}, 'allowed'); status(setmetatable({}, {}), 'unhandled', 'edit_unknown')

-- Independent oracle: direct commands mutate a small inventory. It does not interpret model contracts.
local function execute(initial, commands)
    local state = {on = initial.on, stock = initial.stock, alive = initial.alive, location = initial.location,
        load = initial.load, capacity = initial.capacity}
    for _, command in ipairs(commands) do
        local kind = command.kind
        if kind == 'on' then state.on = true
        elseif kind == 'off' then state.on = false
        elseif kind == 'toggle' then state.on = not state.on
        elseif kind == 'useDevice' then if not state.on then return false end
        elseif kind == 'produce' then state.stock = state.stock + 1
        elseif kind == 'consume' then if state.stock < 1 then return false end; state.stock = state.stock - 1
        elseif kind == 'pickup' then
            if not state.alive or state.location ~= 'floor' then return false end
            state.location, state.load = 'bag', state.load + 1
        elseif kind == 'drop' then
            if not state.alive or state.location ~= 'bag' then return false end
            state.location, state.load = 'floor', state.load - 1
        elseif kind == 'useItem' then
            if not state.alive or state.location ~= 'bag' then return false end
            state.alive, state.location, state.load = false, 'absent', state.load - 1
        elseif kind == 'createItem' then
            if state.alive or state.stock < 1 then return false end
            state.alive, state.location, state.stock = true, 'floor', state.stock - 1
        else error('bad oracle command') end
        if state.stock < 0 or state.stock > 3 or state.load < 0 or state.load > state.capacity then return false end
    end
    return true
end
local deviceKey, stockKey, itemKey, bagKey = {}, {}, {}, {}
local function declaration(initial, command)
    local kind, resources = command.kind, {}
    local function add(domain, key, facts, requires, effects, bounds)
        resources[#resources + 1] = resource(domain, key, facts, requires, effects, bounds)
    end
    if kind == 'on' or kind == 'off' or kind == 'toggle' or kind == 'useDevice' then
        local effects = kind ~= 'useDevice' and {{field = 'on', set = kind == 'on'}} or nil
        if kind == 'toggle' then effects = {{field = 'on', toggle = true}} end
        add('device', deviceKey, {on = initial.on}, kind == 'useDevice' and {{field = 'on', equal = true}} or nil, effects)
    elseif kind == 'produce' or kind == 'consume' then
        add('stock', stockKey, {count = initial.stock}, kind == 'consume' and {{field = 'count', min = 1}} or nil,
            {{field = 'count', delta = kind == 'produce' and 1 or -1}}, {count = {min = 0, max = 3}})
    else
        local creating = kind == 'createItem'
        local requires = {{field = 'alive', equal = not creating}}
        if not creating then requires[#requires + 1] = {field = 'location', equal = kind == 'pickup' and 'floor' or 'bag'} end
        local effects = {{field = 'location', set = (kind == 'pickup' and 'bag') or (kind == 'useItem' and 'absent') or 'floor'}}
        if creating or kind == 'useItem' then effects[#effects + 1] = {field = 'alive', set = creating} end
        add('item', itemKey, {alive = initial.alive, location = initial.location}, requires, effects)
        if creating then
            add('stock', stockKey, {count = initial.stock}, {{field = 'count', min = 1}},
                {{field = 'count', delta = -1}}, {count = {min = 0, max = 3}})
        else
            add('bag', bagKey, {load = initial.load}, nil, {{field = 'load', delta = kind == 'pickup' and 1 or -1}},
                {load = {min = 0, max = initial.capacity, reason = 'edit_capacity'}})
        end
    end
    local result = entry(command, resources)
    if kind == 'pickup' or kind == 'drop' or kind == 'useItem' then result.edit.capacity = 'modeled' end
    return result
end
local function fingerprint(value)
    if type(value) ~= 'table' then return type(value) .. ':' .. tostring(value) end
    if value == deviceKey or value == stockKey or value == itemKey or value == bagKey then return tostring(value) end
    local fields = {}
    for key, item in pairs(value) do fields[#fields + 1] = fingerprint(key) .. '=' .. fingerprint(item) end
    table.sort(fields); return '{' .. table.concat(fields, ',') .. '}'
end
local checked = 0
local function check(initial, commands, protect)
    local entries = {}
    for i, command in ipairs(commands) do entries[i] = declaration(initial, command) end
    local before = protect and fingerprint(entries)
    local decision = Model.evaluate(entries)
    local expected = execute(initial, commands)
    assert(decision.status == (expected and 'allowed' or 'denied'), 'oracle disagreement for ' .. fingerprint(commands))
    if protect then assert(fingerprint(entries) == before, 'projection changed declarative input') end
    checked = checked + 1
end
local kinds = {'on', 'off', 'toggle', 'useDevice', 'produce', 'consume', 'pickup', 'drop', 'useItem', 'createItem'}
local initialStates = {
    {on = false, stock = 0, alive = true, location = 'floor', load = 0, capacity = 1},
    {on = true, stock = 1, alive = true, location = 'floor', load = 0, capacity = 1},
    {on = false, stock = 3, alive = true, location = 'bag', load = 1, capacity = 1},
    {on = true, stock = 0, alive = true, location = 'bag', load = 1, capacity = 2},
    {on = false, stock = 1, alive = false, location = 'absent', load = 0, capacity = 1},
    {on = true, stock = 3, alive = false, location = 'absent', load = 0, capacity = 2},
}
for _, initial in ipairs(initialStates) do
    -- Cover every pair of command kinds with a deterministic third command, then every single-step edit.
    for ai, a in ipairs(kinds) do for bi, b in ipairs(kinds) do
        local c = kinds[(ai * 3 + bi * 7) % #kinds + 1]
        local commands = {{kind = a}, {kind = b}, {kind = c}}
        check(initial, commands, true)
        for from = 1, 3 do
            local removed = {}
            for i = 1, 3 do if i ~= from then removed[#removed + 1] = commands[i] end end
            check(initial, removed)
            for to = 1, 3 do
                local moved = {}
                for _, command in ipairs(removed) do moved[#moved + 1] = command end
                table.insert(moved, to, commands[from]); check(initial, moved)
            end
        end
    end end
end
assert(checked == 7800)
print('Declarative edit model: ' .. checked .. ' independent oracle move/removal cases, legal differing outcomes, identities, bounds and malformed contracts passed.')
