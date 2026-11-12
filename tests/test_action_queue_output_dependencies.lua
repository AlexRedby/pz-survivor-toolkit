-- Exercise fresh-output connectivity through real registered Policy decisions.
-- Factory effects are declarative here; actual magazine events have their own
-- source-backed suite and native bank.
assert(NativeActionRoot, 'output dependencies require --game')
local f = assert(loadfile(ProjectRoot .. '/tests/support/action_queue_native.lua'))()
f.native('shared/RadioCom/ISRadioAction.lua')
getFilenameOfClosure = NativeFilenameOfClosure or function(callback) return debug.getinfo(callback, 'S').source end
getGameFilesInput = function(path)
    local file = assert(io.open(NativeActionRoot .. '/' .. path:gsub('^media/lua/', '')))
    return {readLine = function() local line = file:read('*l'); return line and line:gsub('\r$', '') end,
        close = function() file:close() end}
end
local previousRequire, modules = require, {}
require = function(name)
    if name == 'PZSurvivorToolkit/ActionQueueEditModel' or name == 'PZSurvivorToolkit/ActionQueueEditAdapters' then
        if not modules[name] then modules[name] = f.project(name:match('/([^/]+)$')) end
        return modules[name]
    end
    return previousRequire(name)
end
isClient = function() return false end
f.project('ActionQueueOperations'); f.project('ActionQueueDefinitions')
local policy = f.project('ActionQueuePolicy')
local definitions = PZSurvivorToolkit.ActionQueueDefinitions
local Producer = ISBaseTimedAction:derive('FixtureFreshOutputAction')
local Consumer = ISBaseTimedAction:derive('FixtureOutputConsumerAction')
local ammo = 'Base.Bullets9mm'
local root = f.player:getInventory()
local inspections = 0
local function outputContract(action)
    inspections = inspections + 1
    local item = action.item
    local value = {items = {[item:getID()] = true}, itemTypes = {[item:getFullType()] = true}, targets = {},
        equipment = f.player, outputTypes = {[ammo] = true}, freshOutputTypes = action.fresh,
        knownInputs = action.knownInputs, unknownOutputs = action.unknownOutputs,
        cancelWaiting = true, cancelOperation = true, interrupt = 'finish-step', moveRequiresProjection = action.strict}
    if not action.action then
        value.edit = {version = 1, complete = true, capacity = 'external', resources = {{domain = 'item',
            key = item:getID(), facts = {item = item, location = root},
            requires = {{field = 'location', equal = root}}, effects = {}}}}
    end
    return value
end
definitions.registerBehavior('fixture.fresh-output', {types = {'FixtureFreshOutputAction'},
    matches = function(action) return getmetatable(action) == Producer end, inspect = outputContract})
definitions.registerBehavior('fixture.output-consumer', {types = {'FixtureOutputConsumerAction'},
    matches = function(action) return getmetatable(action) == Consumer end,
    inspect = function(action)
        return {items = {}, itemTypes = action.selector and {} or {[ammo] = true}, targets = {},
            dynamicInputs = action.selector == 'full' and {[ammo] = true} or nil,
            dynamicInputsByType = action.selector == 'short' and {Bullets9mm = true} or nil,
            hands = action.writesEquipment and f.player or nil, cancelWaiting = true, interrupt = 'finish-step'}
    end})
local function producer(item)
    return f.action(Producer, {item = item or f.item('Base.9mmClip'), fresh = {[ammo] = true}})
end
local function consumer(selector)
    return f.action(Consumer, {selector = selector})
end
local front, first, second = producer(), producer(), producer()
local queue = f.queue(front, first, second)
local context = {}
assert(policy.evaluateMove(queue, second, first, false, context).allowed and context.editFallback == nil,
    'independent same-type fresh producers must remain editable behind an active producer')
assert(policy.evaluateCancel(queue, first, true).allowed,
    'removing a pending producer must not depend on an independent active output of the same type')
assert(inspections > 0 and queue.current == front and #queue.queue == 3,
    'preview must inspect contracts without mutating the queue')
for _, missing in ipairs({'left', 'right'}) do
    front, first, second = producer(), producer(), producer()
    if missing == 'left' then front.fresh = nil else second.fresh = nil end
    queue = f.queue(front, first, second)
    second.strict = true
    assert(not policy.evaluateMove(queue, second, first).allowed,
        'a projection-required move cannot inherit legacy output/output fallback')
end
for _, fresh in ipairs({{[ammo] = 'true'}, setmetatable({}, {__index = function() error('foreign output lookup') end})}) do
    front, first, second = producer(), producer(), producer()
    second.fresh = fresh
    queue = f.queue(front, first, second)
    assert(not policy.evaluateMove(queue, second, first).allowed,
        'malformed/inherited output metadata must not grant independence or invoke its callback')
end
front, first, second = producer(), producer(), producer()
second.item = front.item
second.strict = true
queue = f.queue(front, first, second)
assert(not policy.evaluateMove(queue, second, first).allowed,
    'fresh output instances do not erase an exact shared input dependency with the active action')
for _, selector in ipairs({false, 'full', 'short'}) do
    local head = f.action(ISReadABook, {item = f.item('Base.BookCarpentry1')})
    first, second = producer(), producer()
    local use = consumer(selector)
    queue = f.queue(head, first, use, second)
    assert(not policy.evaluateMove(queue, second, first).allowed,
        'a fresh factory must retain output/input and full/short selector dependencies in either direction')
    assert(not policy.evaluateMove(queue, first, second, true).allowed,
        'crossing an output consumer in the reverse direction must remain protected')
    assert(not policy.evaluateCancel(queue, first, true).allowed,
        'future output cannot be removed from an unmodeled downstream consumer')
end
front, first, second = producer(), producer(), producer()
local gear = consumer('full'); gear.writesEquipment = true
queue = f.queue(front, first, gear, second)
assert(not policy.evaluateMove(queue, second, first).allowed,
    'factory independence must preserve equipment-writer dependencies')
front, first, second = producer(), producer(), producer()
second.unknownOutputs = true
queue = f.queue(front, first, second)
assert(not policy.evaluateMove(queue, second, first).allowed,
    'unknown outputs must not inherit a fresh-output independence declaration')
-- A grouped prefix without an edit contract must not return early before
-- discovering the stronger move requirement on the following body.
local head = f.action(ISReadABook, {item = f.item('Base.BookCarpentry1')})
local prefix, body, tail = consumer(false), producer(), producer()
body.strict = true
local token = {}
prefix.toolkitQueueOperation, body.toolkitQueueOperation = token, token
queue = f.queue(head, prefix, body, tail)
local grouped = policy.evaluateMove(queue, body, tail, true)
assert(not grouped.allowed and grouped.reason == 'edit_unknown',
    'an incomplete grouped prefix must not bypass its body projection requirement')
print('Fresh output dependencies: independent factories, shared inputs, consumers, selectors and equipment guards passed.')
if TestCoverage then TestCoverage('source-contract', 'passed', 'Registered Policy fresh-output connectivity and retained dependent consumers.') end
