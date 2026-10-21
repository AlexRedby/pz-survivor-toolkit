require = function() end
PZSurvivorToolkit = {}
ISTimedActionQueue = {queues = {}}
local receive, client = nil, true
Events = {OnServerCommand = {Add = function(callback) receive = callback end}}
isClient = function() return client end
sendClientCommand = function() error('receipts must never send commands or create native actions') end
local players = {}
getSpecificPlayer = function(slot) return players[slot] end
local sourcePath = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueAcknowledgements.lua'
local source
if NativeReadText then source = NativeReadText(sourcePath)
else local file = assert(io.open(sourcePath)); source = file:read('*a'); file:close() end
local seams
source, seams = source:gsub('\nreturn Acknowledgements', '\nAcknowledgements.fixtureRecords = records\nreturn Acknowledgements')
assert(seams == 1, 'receipt retention fixture must expose only its private current registry')
local acknowledgements = assert(loadstring(source))()
assert(type(receive) == 'function')

local serial = 0
local function token()
    serial = serial + 1
    return string.format('00000000-0000-0000-0000-%012x', serial)
end
local function character(slot, online)
    local value = {slot = slot, online = online, dead = false}
    function value:getPlayerNum() return self.slot end
    function value:getOnlineID() return self.online end
    function value:isDead() return self.dead end
    players[slot] = value
    return value
end
local function action(character, id, kind)
    return {character = character, action = {}, toolkitNativeTransaction = id, toolkitNativeKind = kind}
end
local function queue(character, action)
    local value = {current = action, queue = {action}, toolkitOperationGeneration = 1}
    ISTimedActionQueue.queues[character] = value
    return value
end
local function message(character, state, identity, id, kind)
    return {protocol = 1, player = character:getOnlineID(), transaction = id or -126,
        kind = kind or 'ToolkitAckProbe', token = identity, state = state}
end
local function deliver(args) receive('PZSurvivorToolkitActions', 'State', args) end
local function state(action)
    local record = acknowledgements.capture(action)
    return acknowledgements.state(action, record), record
end

local first, second = character(0, 19), character(1, 20)
local current = action(first, -126, 'ToolkitAckProbe')
local currentQueue = queue(first, current)
local foreign = action(second, -126, 'ToolkitAckProbe')
local foreignQueue = queue(second, foreign)
assert(state(current) == nil and state(foreign) == nil, 'unpatched server granted permission without a receipt')
deliver(message(first, 'completed', token()))
assert(state(current) == nil, 'terminal receipt without start granted permission')

local invalid = {
    {protocol = 2}, {player = '19'}, {transaction = 0}, {transaction = 128}, {transaction = -129},
    {transaction = 1.5}, {transaction = '1'}, {kind = {}}, {kind = 'OtherAction'},
    {token = string.rep('z', 36)}, {token = '00000000-0000-0000-0000-00000000000'}, {state = 'done'},
}
for _, patch in ipairs(invalid) do
    local data = message(first, 'started', token())
    for key, value in pairs(patch) do data[key] = value end
    deliver(data)
    assert(state(current) == nil, 'malformed or mismatched receipt granted permission')
end
receive('OtherModule', 'State', message(first, 'started', token()))
receive('PZSurvivorToolkitActions', 'OtherCommand', message(first, 'started', token()))
deliver(nil)
client = false; deliver(message(first, 'started', token())); client = true
assert(state(current) == nil, 'foreign command or single-player granted permission')

local firstToken, foreignToken = token(), token()
deliver(message(first, 'started', firstToken))
local started, record = state(current)
assert(started == 'started' and state(foreign) == nil, 'same byte id crossed owner boundary')
deliver(message(first, 'started', firstToken))
deliver(message(first, 'started', token()))
assert(acknowledgements.capture(current) == record and record.token == firstToken, 'duplicate start replaced identity')
deliver(message(first, 'completed', token()))
assert(state(current) == 'started', 'foreign token completed the action')
deliver(message(second, 'started', foreignToken))
assert(state(foreign) == 'started' and record.token == firstToken, 'second local player replaced first receipt')

deliver(message(first, 'completed', firstToken))
deliver(message(first, 'canceled', firstToken))
deliver(message(first, 'rejected', firstToken))
assert(state(current) == 'completed', 'cancel after completion rewrote settled outcome')
deliver(message(second, 'canceled', foreignToken))
deliver(message(second, 'completed', foreignToken))
assert(state(foreign) == 'canceled', 'completion after cancellation rewrote settled outcome')

local replacement = action(first, -126, 'ToolkitAckProbe')
currentQueue.current, currentQueue.queue = replacement, {replacement}
assert(acknowledgements.state(current, record) == nil, 'removed action kept live permission')
deliver(message(first, 'started', firstToken))
deliver(message(first, 'completed', firstToken))
assert(state(replacement) == nil, 'replayed byte-id start attached to replacement')
local replacementToken = token()
deliver(message(first, 'started', replacementToken))
local _, replacementRecord = state(replacement)
assert(replacementRecord and replacementRecord.token == replacementToken, 'new token could not reuse signed byte id')
deliver(message(first, 'completed', firstToken))
assert(state(replacement) == 'started', 'old terminal completed reused byte id')
deliver(message(first, 'rejected', replacementToken))
assert(state(replacement) == 'rejected', 'native failure did not settle receipt')

currentQueue.toolkitOperationGeneration = 2
assert(acknowledgements.state(replacement, replacementRecord) == nil, 'generation change retained permission')
currentQueue.toolkitOperationGeneration = 1
currentQueue.queue[1] = foreign
assert(state(replacement) == nil, 'current action without queue head retained permission')
currentQueue.queue[1] = replacement
local oldQueue = currentQueue
ISTimedActionQueue.queues[first] = {current = replacement, queue = {replacement}}
assert(state(replacement) == nil, 'replaced queue retained receipt')
ISTimedActionQueue.queues[first] = oldQueue
first.dead = true; assert(state(replacement) == nil, 'dead character retained permission'); first.dead = false
players[0] = second; assert(state(replacement) == nil, 'replaced local player retained permission'); players[0] = first
replacement.toolkitNativeTransaction = 127
assert(state(replacement) == nil, 'changed transaction retained permission')
replacement.toolkitNativeTransaction = -126; replacement.toolkitNativeKind = 'OtherAction'
assert(state(replacement) == nil, 'changed type retained permission')

local build = action(first, 127, 'build')
currentQueue.current, currentQueue.queue = build, {build}
local buildToken = token()
deliver(message(first, 'started', buildToken, 127, 'ToolkitAckProbe'))
assert(state(build) == nil, 'generic type matched native build')
deliver(message(first, 'started', buildToken, 127, 'build'))
deliver(message(first, 'completed', buildToken, 127, 'build'))
assert(state(build) == 'completed', 'native build outcome was not recognized')
-- Native retriggering can reuse the Lua table with a fresh Java action.
local reused = action(first, 123, 'ToolkitAckProbe')
currentQueue.current, currentQueue.queue = reused, {reused}
local oldToken = token()
deliver(message(first, 'started', oldToken, 123))
local _, oldRecord = state(reused)
deliver(message(first, 'completed', oldToken, 123))
reused.action = {}
assert(state(reused) == nil, 'retriggered Lua table inherited old native outcome')
local newToken = token()
deliver(message(first, 'started', newToken, 123))
local _, newRecord = state(reused)
assert(newRecord and newRecord ~= oldRecord and newRecord.state == 'started')
deliver(message(first, 'completed', oldToken, 123))
assert(newRecord.state == 'started', 'old outcome settled a new Java action on reused Lua table')
deliver(message(first, 'canceled', newToken, 123))
assert(newRecord.state == 'canceled')
-- A following ordered receipt may be dispatched after native Done advanced the queue.
local completedAction = action(first, 125, 'ToolkitAckProbe')
currentQueue.current, currentQueue.queue = completedAction, {completedAction}
local completedToken = token()
deliver(message(first, 'started', completedToken, 125))
local _, completedRecord = state(completedAction)
currentQueue.current, currentQueue.queue = build, {build}
local nextToken = token()
deliver(message(first, 'started', nextToken, 127, 'build'))
assert(acknowledgements.capture(build), 'following action must acquire its own current receipt')
deliver(message(first, 'completed', completedToken, 125))
assert(completedRecord.state == 'completed' and acknowledgements.capture(completedAction) == nil,
    'late outcome must settle observation without granting removed action permission')
local resetAction = action(first, 124, 'ToolkitAckProbe')
currentQueue.current, currentQueue.queue = resetAction, {resetAction}
local resetToken = token()
deliver(message(first, 'started', resetToken, 124))
local _, resetRecord = state(resetAction)
acknowledgements.reset(currentQueue)
assert(not acknowledgements.capture(resetAction) and not acknowledgements.fixtureRecords[first.slot],
    'reset must release the current action receipt as well as terminal observation')
assert(acknowledgements.capture(foreign), 'reset must preserve another local player\'s current receipt')
deliver(message(first, 'completed', resetToken, 124))
assert(resetRecord.state == 'started', 'explicit reset retained pending terminal observation')
-- Inspect strong registry keys directly: Lua 5.1 weak-key collection would hide
-- Kahlua's ignored __mode, so GC cannot establish that completed actions retire.
for i = 1, 500 do
    local finished = action(first, -126, 'ToolkitAckProbe')
    currentQueue.current, currentQueue.queue = finished, {finished}
    local identity = token()
    deliver(message(first, 'started', identity))
    deliver(message(first, 'completed', identity))
    assert(state(finished) == 'completed')
    local count = 0
    for slot, entry in pairs(acknowledgements.fixtureRecords) do
        assert(type(slot) == 'number' and (entry.action == finished or entry.action == foreign),
            'current receipts must retain only each local slot\'s latest action')
        count = count + 1
    end
    assert(count == 2, 'completed actions must not accumulate in the current receipt registry')
end
acknowledgements.reset(currentQueue)
assert(not acknowledgements.fixtureRecords[first.slot] and acknowledgements.fixtureRecords[second.slot],
    'reset must release only its queue\'s bounded current receipt')
currentQueue.current, currentQueue.queue = build, {build}
assert(currentQueue.current == build and currentQueue.queue[1] == build
    and foreignQueue.current == foreign and foreignQueue.queue[1] == foreign, 'receipt handling mutated native queue')
print('Action queue acknowledgement checks passed.')
