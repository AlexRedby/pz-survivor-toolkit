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

-- Numeric caps preserve captured endpoints; scales explicitly describe a different operation.
local function numeric(value, effect, predicate)
    local e = entry({}, {resource('numeric', target, {amount = value}, predicate and {predicate} or nil,
        effect and {effect} or nil, {amount = {min = 0, max = 1}})})
    e.edit.capacity = 'external'
    return e
end
local function exact(value, expected)
    return numeric(value, nil, {field = 'amount', equal = expected})
end
status({numeric(1, {field = 'amount', cap = .5}), numeric(1, {field = 'amount', cap = .5}), exact(1, .5)}, 'allowed')
status({numeric(1, {field = 'amount', scale = .5}), numeric(1, {field = 'amount', scale = .5}), exact(1, .25)}, 'allowed')
status({numeric(.25, {field = 'amount', cap = .5}), exact(.25, .25)}, 'allowed')
status({numeric(1, {field = 'amount', scale = 0}), exact(1, 0)}, 'allowed')
status({numeric(.5, nil, {field = 'amount', above = .5})}, 'denied', 'edit_resource_amount')
status({numeric(.5, nil, {field = 'amount', above = .25, min = .5, max = .5})}, 'allowed')
status({numeric(.5, nil, {field = 'amount', above = .25, min = 0, max = .75})}, 'allowed')
local access = entry({}, {resource('location', target, {location = opaque}, {{field = 'location', oneOf = {false, opaque, 'root'}}})})
status({access}, 'allowed')
access.edit.resources[1].facts.location = another
status({access}, 'denied', 'edit_required_state')
assert(hiddenCalls == 0, 'membership never invokes opaque metamethods')
local invalidPredicates = {
    {field = 'amount', oneOf = {}}, {field = 'amount', oneOf = false},
    {field = 'amount', oneOf = {[2] = .5}}, {field = 'amount', oneOf = {.5, function()error('never execute')end}},
    {field = 'amount', oneOf = {math.huge}}, {field = 'amount', oneOf = {0/0}},
    {field = 'amount', oneOf = setmetatable({.5}, {__index = function()error('never read')end})},
    {field = 'amount', oneOf = {.5}, equal = .5}, {field = 'amount', oneOf = {.5}, min = 0},
    {field = 'amount', oneOf = {.5}, above = 0}, {field = 'amount', equal = .5, above = 0},
    {field = 'amount', above = false}, {field = 'amount', above = math.huge}, {field = 'amount', above = 0/0},
    {field = 'amount', above = 1, max = 1}, {field = 'amount', above = 1, max = 0},
    {field = 'amount', above = 0, min = 2, max = 1},
}
for _, predicate in ipairs(invalidPredicates) do
    local e = numeric(.5, nil, predicate)
    status({e}, 'unhandled', 'edit_unknown')
    e.snapshotOnly = true; status({e}, 'unhandled', 'edit_unknown')
end
local invalidEffects = {
    {field = 'amount', cap = math.huge}, {field = 'amount', cap = 0/0}, {field = 'amount', cap = false},
    {field = 'amount', cap = .5, delta = 0}, {field = 'amount', cap = .5, scale = 1},
    {field = 'amount', scale = -1}, {field = 'amount', scale = math.huge},
    {field = 'amount', scale = 0/0}, {field = 'amount', scale = false},
    {field = 'amount', scale = 1, set = .5}, {field = 'missing', scale = 1},
}
for _, effect in ipairs(invalidEffects) do
    local e = numeric(.5, effect)
    status({e}, 'unhandled', 'edit_unknown')
    e.snapshotOnly = true; status({e}, 'unhandled', 'edit_unknown')
end
for _, operation in ipairs({'scale', 'cap'}) do
    local e = entry({}, {resource('numeric', target, {amount = 'unknown'}, nil, {{field = 'amount', [operation] = .5}})})
    status({e}, 'unhandled', 'edit_unknown')
    e.snapshotOnly = true; status({e}, 'unhandled', 'edit_unknown')
end
local overflow = entry({}, {resource('numeric', target, {amount = 1e308}, nil, {{field = 'amount', scale = 1e308}})})
status({overflow}, 'unhandled', 'edit_unknown')
overflow.snapshotOnly = true; status({overflow}, 'unhandled', 'edit_unknown')
local deltaOverflow = amount(1e308, 1e308); deltaOverflow.snapshotOnly = true
status({deltaOverflow}, 'unhandled', 'edit_unknown')
local removedCap = numeric(.5, {field = 'amount', cap = 0}, {field = 'amount', above = .75})
removedCap.snapshotOnly = true
status({removedCap, exact(.5, .5)}, 'allowed')
status({numeric(.5, {field = 'amount', cap = -1})}, 'denied', 'edit_resource_amount')
-- A finite operand can overflow only after a preceding action changes the projected value.
local large = entry({}, {resource('large', target, {amount = 1}, nil, {{field = 'amount', set = 1e308}})})
local multiply = entry({}, {resource('large', target, {amount = 1}, nil, {{field = 'amount', scale = 2}})})
status({large, multiply}, 'unhandled', 'edit_unknown')

-- This second oracle executes direct numeric/location commands; it never decodes effects or predicates.
local numericKey = {}
local function numericExecute(initial, commands)
    local value, location = initial.amount, initial.location
    for _, command in ipairs(commands) do
        local kind = command.kind
        if kind == 'capturedHalf' or kind == 'halfCurrent' or kind == 'empty' then
            if value <= 0 or (location ~= 'root' and location ~= 'bag') then return end
            if kind == 'capturedHalf' then if value > .5 then value = .5 end
            elseif kind == 'halfCurrent' then value = value / 2
            else value = 0 end
        elseif kind == 'nonempty' then if value <= 0 then return end
        elseif kind == 'accessible' then if location ~= 'root' and location ~= 'bag' then return end
        elseif kind == 'root' then location = 'root'
        elseif kind == 'floor' then location = 'floor'
        else error('unknown direct oracle command') end
    end
    return {amount = value, location = location}
end
local function numericDeclaration(initial, command)
    local kind, predicates, effects = command.kind, {}, {}
    if kind == 'capturedHalf' or kind == 'halfCurrent' or kind == 'empty' then
        predicates = {{field = 'amount', above = 0}, {field = 'location', oneOf = {'root', 'bag'}}}
        if kind == 'capturedHalf' then effects = {{field = 'amount', cap = .5}}
        elseif kind == 'halfCurrent' then effects = {{field = 'amount', scale = .5}}
        else effects = {{field = 'amount', set = 0}} end
    elseif kind == 'nonempty' then predicates = {{field = 'amount', above = 0, min = 0, max = 1}}
    elseif kind == 'accessible' then predicates = {{field = 'location', oneOf = {'root', 'bag'}}}
    else effects = {{field = 'location', set = kind}} end
    local e = entry(command, {resource('numeric-location', numericKey, {amount = initial.amount, location = initial.location},
        predicates, effects, {amount = {min = 0, max = 1}})})
    e.edit.capacity = 'external'
    return e
end
local numericChecked = 0
local function numericCheck(initial, commands)
    local entries = {}
    for i, command in ipairs(commands) do entries[i] = numericDeclaration(initial, command) end
    local before = fingerprint(entries)
    local expected = numericExecute(initial, commands)
    status(entries, expected and 'allowed' or 'denied')
    assert(fingerprint(entries) == before, 'numeric/location projection mutated input')
    if expected then
        local probe = entry({}, {resource('numeric-location', numericKey, {amount = initial.amount, location = initial.location},
            {{field = 'amount', equal = expected.amount}, {field = 'location', equal = expected.location}})})
        entries[#entries + 1] = probe
        status(entries, 'allowed')
    end
    numericChecked = numericChecked + 1
end
local numericKinds = {'capturedHalf', 'halfCurrent', 'empty', 'nonempty', 'accessible', 'root', 'floor'}
for _, initial in ipairs({{amount = 0, location = 'root'}, {amount = .25, location = 'bag'},
    {amount = .5, location = 'floor'}, {amount = 1, location = 'root'}}) do
    for ai, a in ipairs(numericKinds) do for bi, b in ipairs(numericKinds) do
        local commands = {{kind = a}, {kind = b}, {kind = numericKinds[(ai + bi) % #numericKinds + 1]}}
        numericCheck(initial, commands)
        for from = 1, 3 do
            local rest = {}
            for i = 1, 3 do if i ~= from then rest[#rest + 1] = commands[i] end end
            numericCheck(initial, rest)
            for to = 1, 3 do
                local moved = {}
                for _, command in ipairs(rest) do moved[#moved + 1] = command end
                table.insert(moved, to, commands[from]); numericCheck(initial, moved)
            end
        end
    end end
end
assert(numericChecked == 2548)
print('Declarative numeric/location extension: ' .. numericChecked .. ' independent move/removal cases, strict thresholds, membership, captured caps, scales and external capacity passed.')
