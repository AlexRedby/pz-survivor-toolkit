PZSurvivorToolkit = {}
local Model = assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueEditModel.lua'))()

local function entry(resources)
    return {action = {}, edit = {version = 1, complete = true, capacity = 'unchanged', resources = resources or {}}}
end
local function resource(key, facts, requires, effects, bounds)
    return {domain = 'test', key = key, facts = facts, requires = requires, effects = effects, bounds = bounds}
end
local nativeCalls = 0
local function native()
    nativeCalls = nativeCalls + 1
    error('the pure model must never resolve native actions, routing or coordinates')
end
local opaqueMeta = {__index = native, __eq = native, __tostring = native}
local actor, square = setmetatable({}, opaqueMeta), setmetatable({}, opaqueMeta)
local function boundary()
    return {action = {isValid = native, perform = native, getPath = native}, deferred = {
        version = 1, kind = 'deferred-spatial', actor = actor, targetSquare = square,
        invalidates = 'all-resources', routing = 'native', expansion = 'native', outcome = 'native',
    }}
end
-- Save the complete raw input graph, including table identities and metatables.
local function capture(root)
    local records = {}
    local function visit(value)
        if type(value) ~= 'table' or records[value] then return end
        local record = {meta = getmetatable(value), values = {}, count = 0}
        records[value] = record
        for key, child in next, value do
            record.values[key], record.count = child, record.count + 1
            visit(key); visit(child)
        end
    end
    visit(root)
    return function()
        for value, record in next, records do
            assert(rawequal(getmetatable(value), record.meta), 'input metatable changed')
            local count = 0
            for key, child in next, value do
                assert(rawequal(record.values[key], child), 'input field or identity changed')
                count = count + 1
            end
            assert(count == record.count, 'input field removed')
        end
    end
end
local checked = 0
local function evaluate(entries, expected, reason, blocker)
    local unchanged = capture(entries)
    local decision = Model.evaluate(entries)
    unchanged()
    checked = checked + 1
    assert(decision.status == expected, 'case ' .. checked .. ': expected ' .. expected .. ', got ' .. tostring(decision.status))
    if reason then assert(decision.reason == reason, 'case ' .. checked .. ': unexpected reason ' .. tostring(decision.reason)) end
    if blocker then assert(rawequal(decision.blocker, blocker.action), 'wrong blocking action') end
    return decision
end
local function deferred(entries, prefix, boundaries)
    local first = entries[prefix + 1]
    local decision = evaluate(entries, 'deferred', 'edit_native_resolution', first)
    assert(decision.evaluatedPrefix == prefix, 'must stop strictly before the first native boundary')
    local allowedFields = {status = true, reason = true, blocker = true, evaluatedPrefix = true, deferred = true}
    for key in pairs(decision) do assert(allowedFields[key], 'deferred decision exposes a forecast or permission field') end
    assert(type(decision.deferred) == 'table' and #decision.deferred == #boundaries)
    for i, index in ipairs(boundaries) do
        local item, expected = decision.deferred[i], entries[index]
        assert(item.index == index and rawequal(item.action, expected.action), 'wrong boundary order or action')
        for key, value in pairs(expected.deferred) do assert(rawequal(item.descriptor[key], value), 'wrong deferred descriptor') end
        for key in pairs(item.descriptor) do assert(expected.deferred[key] ~= nil, 'invented descriptor field') end
    end
    return decision
end
local key = {}
local function amount(value, requires, effect, bounds)
    return entry({resource(key, {amount = value}, requires and {requires}, effect and {effect}, bounds and {amount = bounds})})
end
local walk = boundary()
deferred({walk}, 0, {1})
local explicitFlags = boundary(); explicitFlags.active, explicitFlags.snapshotOnly = false, false
deferred({explicitFlags}, 0, {1})
deferred({entry(), walk, entry(), boundary()}, 1, {2, 4})
local removed = amount(0, {field = 'amount', min = 1}, {field = 'amount', delta = -1})
removed.snapshotOnly = true
deferred({removed, walk}, 1, {2})

-- Current suffix preconditions, bounds and arithmetic are not forecasts of the world after walking.
local suffixes = {
    amount(0, {field = 'amount', min = 1}),
    amount(0, {field = 'amount', equal = 1}),
    amount(0, {field = 'amount', oneOf = {1, 2}}),
    amount(-1, nil, nil, {min = 0}),
    amount(0, nil, {field = 'amount', delta = -1}, {min = 0}),
    amount(1e308, nil, {field = 'amount', delta = 1e308}),
    amount(1e308, nil, {field = 'amount', scale = 1e308}),
    amount(-1e308, nil, {field = 'amount', deplete = {amount = 1e308, minimum = 0}}),
}
for _, suffix in ipairs(suffixes) do deferred({boundary(), suffix}, 0, {1}) end
-- Multiple boundaries never restart prediction, including an independent tail resource.
local independent = entry({resource({}, {ready = false}, {{field = 'ready', equal = true}})})
deferred({entry(), boundary(), suffixes[1], boundary(), independent}, 1, {2, 4})
local setType = amount(1, nil, {field = 'amount', set = false})
deferred({boundary(), setType, amount(1, nil, {field = 'amount', delta = 1})}, 0, {1})

-- A boundary cannot erase contradictions that already occur in the known prefix.
local hungry = amount(0, {field = 'amount', min = 1})
evaluate({hungry, boundary()}, 'denied', 'edit_resource_amount', hungry)
local overflow = amount(1e308, nil, {field = 'amount', delta = 1e308})
evaluate({overflow, boundary()}, 'unhandled', 'edit_unknown', overflow)
-- Bounds are phase-local declarations. A suffix constraint cannot be applied
-- retroactively to a prefix resource or its projected effects.
local overdraw = amount(1, nil, {field = 'amount', delta = -2})
local declaration = amount(1, nil, nil, {min = 0})
deferred({overdraw, boundary(), declaration}, 1, {2})
local invalidCurrent = amount(-1)
deferred({invalidCurrent, boundary(), amount(-1, nil, nil, {min = 0})}, 1, {2})
deferred({amount(1), boundary(), amount(1, nil, nil, {min = 2})}, 1, {2})
deferred({amount(0, nil, {field = 'amount', delta = 1}), boundary(), amount(0, nil, nil, {max = 0})}, 1, {2})
local intrinsicViolation = amount(0, nil, {field = 'amount', delta = 1}, {max = 0})
evaluate({intrinsicViolation, boundary(), amount(0, nil, nil, {max = 2})}, 'denied', 'edit_resource_amount', intrinsicViolation)
deferred({amount(1, nil, nil, {min = 0}), boundary(), amount(1, nil, nil, {min = 2})}, 1, {2})
deferred({boundary(), amount(1, nil, nil, {min = 0}), boundary(), amount(1, nil, nil, {min = 2})}, 0, {1, 3})
-- Type validation still covers every phase before any prefix semantic denial.
local wrongBoundOperand = entry({resource({}, {amount = false}, nil, nil, {amount = {min = 0}})})
evaluate({boundary(), wrongBoundOperand}, 'unhandled', 'edit_unknown', wrongBoundOperand)
evaluate({intrinsicViolation, boundary(), wrongBoundOperand}, 'unhandled', 'edit_unknown', wrongBoundOperand)

-- All declarations still refer to one current snapshot, even across native boundaries.
evaluate({amount(1), boundary(), amount(2)}, 'unhandled', 'edit_unknown')
evaluate({boundary(), amount(1, nil, nil, {min = 0}), amount(1, nil, nil, {min = 1})}, 'unhandled', 'edit_unknown')
local supplied = entry({resource(key, {}, {{field = 'amount', min = 1}})})
deferred({supplied, boundary(), amount(1)}, 1, {2})

-- Full suffix schema/type validation remains mandatory; only future evaluation is deferred.
local badSuffixes = {
    function() return {action = {}} end,
    function() local e = amount(1); e.edit.version = 2; return e end,
    function() local e = amount(1); e.edit.resources = {[2] = e.edit.resources[1]}; return e end,
    function() return entry({resource(key, {}, {{field = 'missing', equal = true}})}) end,
    function() return entry({resource(key, {}, nil, {{field = 'missing', set = true}})}) end,
    function() return amount(false, {field = 'amount', min = 1}) end,
    function() return amount(false, nil, {field = 'amount', delta = 1}) end,
    function() return amount(1, nil, {field = 'amount', toggle = true}) end,
    function() return amount(1, nil, {field = 'amount', delta = math.huge}) end,
    function() return amount(1, nil, {field = 'amount', delta = 1, set = 2}) end,
    function() return amount(1, nil, {field = 'amount', scale = -1}) end,
    function() return amount(1, nil, {field = 'amount', deplete = {amount = 1, minimum = -1}}) end,
    function() return amount(1, {field = 'amount', min = 2, max = 1}) end,
    function() return amount(false, nil, nil, {min = 0}) end,
    function() return amount(1, nil, nil, {min = 0, reason = 'invented'}) end,
    function() local e = amount(1); e.edit.resources[1].facts = setmetatable({}, {__index = native}); return e end,
    function() local e = amount(1, nil, {field = 'amount', delta = 1}); setmetatable(e.edit.resources[1].effects, {__index = native}); return e end,
}
for _, make in ipairs(badSuffixes) do
    evaluate({boundary(), make()}, 'unhandled', 'edit_unknown')
    evaluate({hungry, boundary(), make()}, 'unhandled', 'edit_unknown')
end
local active = entry(); active.active = true
evaluate({boundary(), active}, 'unhandled', 'edit_in_flight', active)

-- Exact DTOs exclude guessed routes/outcomes, mixed contracts and nonopaque identities.
local malformed = {
    function(e) e.deferred.version = 2 end,
    function(e) e.deferred.kind = 'walk' end,
    function(e) e.deferred.invalidates = 'position' end,
    function(e) e.deferred.routing = 'direct' end,
    function(e) e.deferred.expansion = 'known' end,
    function(e) e.deferred.outcome = 'success' end,
    function(e) e.deferred.targetSquare = nil end,
    function(e) e.deferred.actor = nil end,
    function(e) e.deferred.path = {} end,
    function(e) e.deferred.execute = native end,
    function(e) setmetatable(e.deferred, {__index = native}) end,
    function(e) e.edit = entry().edit end,
    function(e) e.snapshotOnly = true end,
    function(e) e.active = true end,
    function(e) e.snapshotOnly = 1 end,
    function(e) e.active = 'false' end,
    function(e) setmetatable(e, {__index = native}) end,
    function(e) e.deferred = false end,
    function(e) e.action = native end,
}
for _, mutate in ipairs(malformed) do
    local e = boundary(); mutate(e)
    evaluate({e}, 'unhandled')
    evaluate({boundary(), e}, 'unhandled')
end
for _, value in ipairs({false, true, 0, 1, 'actor', native}) do
    for _, field in ipairs({'actor', 'targetSquare'}) do
        local e = boundary(); e.deferred[field] = value
        evaluate({e}, 'unhandled', 'edit_unknown')
    end
end
for _, field in ipairs({'version', 'kind', 'invalidates', 'routing', 'expansion', 'outcome'}) do
    local e = boundary(); e.deferred[field] = nil
    evaluate({boundary(), e}, 'unhandled', 'edit_unknown')
end
local protected = boundary()
protected.deferred.actor = setmetatable({}, {__metatable = 'opaque', __index = native, __eq = native})
protected.deferred.targetSquare = setmetatable({}, {__metatable = false, __index = native, __eq = native})
deferred({protected}, 0, {1})
evaluate({boundary(), [3] = boundary()}, 'unhandled', 'edit_unknown')
evaluate(setmetatable({boundary()}, {__index = native}), 'unhandled', 'edit_unknown')

-- Book checkpoint, walk, TV set/read/resume/pending-return and unrelated tail.
-- These are pure resource declarations: no native methods are needed to accept deferral.
local book, television, root, shelf = {}, {}, {}, {}
local function bookStep(requires, effects)
    return entry({resource(book, {root = root, pages = 0}, requires, effects)})
end
local checkpoint = bookStep(nil, {{field = 'pages', set = 10}})
local tvSet = entry({resource(television, {on = false}, nil, {{field = 'on', set = true}})})
local read = bookStep({{field = 'pages', min = 10}, {field = 'root', equal = root}}, {{field = 'pages', delta = 10}})
local resume = entry({resource(television, {on = false}, {{field = 'on', equal = true}})})
local pendingReturn = bookStep({{field = 'pages', min = 20}}, {{field = 'root', set = shelf}})
local queue = {checkpoint, boundary(), tvSet, read, resume, pendingReturn, independent}
deferred(queue, 1, {2})
assert(checkpoint.edit.resources[1].facts.pages == 0, 'checkpoint leaked into live snapshot')
assert(rawequal(pendingReturn.edit.resources[1].facts.root, root), 'return target leaked into live snapshot')
assert(nativeCalls == 0, 'native callback or opaque metamethod executed')
print('Deferred edit model: ' .. checked .. ' prefix, suffix validation, native boundary and immutable-input checks passed.')
