local tickCallbacks={}
Events={OnTick={Add=function(callback)tickCallbacks[#tickCallbacks+1]=callback end}}
-- Isolated lifecycle vectors model bridge provenance; the animal-stop suite
-- separately executes the actual native source, wrapper and replacement proofs.
local originalStop, wrappedStop = function() end, function() end
local proof = {
    closure = function(callback, name)
        return callback == originalStop and name == 'ISBaseTimedAction.lua'
            or callback == wrappedStop and name == 'ActionQueue.lua'
    end,
    matches = function(path, pin, mod, adler)
        return path == 'media/lua/shared/TimedActions/ISBaseTimedAction.lua' and pin == 3104185167 and mod == nil and adler == true
    end,
}
require = function(name) if name == 'PZSurvivorToolkit/SourceProof' then return proof end end
ISBaseTimedAction = {stop = wrappedStop}
ISQueueActionsAction = {start = function() end}
getFilenameOfClosure = function() return 'TimedActions/ISQueueActionsAction.lua' end
local settings, client, specific = false, false, {}
PZSurvivorToolkit = {Settings = {actionQueue = function() return settings end}}
ISTimedActionQueue = {queues = {}}
isClient = function() return client end
getSpecificPlayer = function(slot) return specific[slot] end
getTimestampMs = function() return 100 end
local root = ProjectRoot or '.'
local Lifecycle = assert(loadfile(root .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua'))()
PZSurvivorToolkit.ActionQueue = {}
assert(Lifecycle.bindStopBridge(originalStop, wrappedStop))
assert(not Lifecycle.bindStopBridge(originalStop, wrappedStop), 'bridge installation cannot be replaced')
local function pack(...) return {n = select('#', ...), ...} end
local serial = 0
local function fixture()
    serial = serial + 1
    local actor = {slot = serial, present = {}}
    function actor:getCharacterActions() return {contains = function(_, native) return self.present[native] end} end
    function actor:getPlayerNum() return self.slot end
    function actor:isDead() return self.dead end
    function actor:isAsleep() return self.asleep end
    function actor:isLocalPlayer() return self.localPlayer ~= false end
    function actor:isPlayerMoving() return self.moving end
    function actor:pressedMovement() return self.input end
    function actor:pressedCancelAction() return self.cancel end
    function actor:isRunning() return self.running end
    function actor:isSprinting() return self.sprinting end
    function actor:isAiming() return self.aiming end
    specific[serial] = actor
    local action = {character = actor, action = {}, toolkitQueueOperation = {}}
    actor.present[action.action] = true
    local tail = {character = actor}
    local queue = {character = actor, current = action, queue = {action, tail}}
    ISTimedActionQueue.queues[actor] = queue
    return queue, action, actor
end
local function prepare(queue, action, options)
    options = options or {}; options.guarded = true
    assert(Lifecycle.prepareStop(queue, action, 'natural-end', 'action', options))
end
local function stopped(queue, action)
    local result = Lifecycle.runStop(action, function(candidate)
        assert(candidate == action)
        assert(Lifecycle.deferStop(queue, candidate) == true)
    end)
    action.character.present[action.action] = nil
    return result
end

-- Legacy callers retain their existing request/receipt semantics.
local q, a = fixture()
local forced = 0
function a:forceStop() forced = forced + 1 end
local receipt = {}
PZSurvivorToolkit.ActionQueueAcknowledgements = {capture = function() return receipt end}
assert(Lifecycle.requestStop(q, a, 'cancel', 'operation'))
assert(forced == 1 and q.toolkitCancel == a and q.toolkitOutcomeWait.acknowledgement == receipt)
assert(q.toolkitOutcomeWait.generic and q.toolkitOutcomeWait.deadline == 30100)
assert(Lifecycle.stopValid(q, a) and Lifecycle.deferStop(q, a) == nil and Lifecycle.takeStopCleanup(q, a))
local intent, wait = q.toolkitStopIntent, q.toolkitOutcomeWait
assert(Lifecycle.prepareStop(q, a, 'other', 'other', {guarded = true}))
assert(q.toolkitStopIntent == intent and q.toolkitOutcomeWait == wait, 'same-action stop replaced existing flags')
PZSurvivorToolkit.ActionQueueAcknowledgements = nil
q, a = fixture(); client = true
a.toolkitNativeTransaction, a.toolkitNativeKind = 7, 'ISFitnessAction'
prepare(q, a, {pendingStart = true})
local binding = q.toolkitOutcomeWait.pendingStart
assert(binding.native == a.action and binding.transaction == 7 and binding.kind == 'ISFitnessAction' and binding.generation == 0)
assert(q.toolkitOutcomeWait.generic and Lifecycle.stopValid(q, a))
Lifecycle.clearStop(q); client = false

-- Exact raw baselines survive disabled queue bookkeeping, including false/nil.
for _, invalid in ipairs({true, false, 'nil'}) do
    for _, cancelled in ipairs({true, false, 'nil'}) do
        q, a = fixture(); settings = false
        if invalid ~= 'nil' then q.toolkitOperationsInvalid = invalid end
        if cancelled ~= 'nil' then a.toolkitQueueOperation.toolkitCancelled = cancelled end
        prepare(q, a)
        assert(Lifecycle.stopValid(q, a), 'unchanged disabled baseline was rejected')
        stopped(q, a)
        assert(Lifecycle.takeStopCleanup(q, a))
    end
end

-- Every ownership/baseline revocation sticks even when the mutable field is restored.
local mutations = {
    actor = function(q, a) a.character = {} end,
    owner = function(q) q.character = {} end,
    registration = function(q, a) ISTimedActionQueue.queues[a.character] = {} end,
    list = function(q) q.queue = {q.current} end,
    head = function(q) q.queue[1] = {} end,
    current = function(q) q.current = {} end,
    native = function(q, a) a.action = {} end,
    token = function(q, a) a.toolkitQueueOperation = {} end,
    cancelled = function(q, a) a.toolkitQueueOperation.toolkitCancelled = false end,
    invalid = function(q) q.toolkitOperationsInvalid = false end,
    generation = function(q) q.toolkitOperationGeneration = 1 end,
    settings = function() settings = true end,
    stopIntent = function(q) q.toolkitStopIntent = {} end,
    outcomeWait = function(q) q.toolkitOutcomeWait = {} end,
    cancelFlag = function(q) q.toolkitCancel = {} end,
    groupCancel = function(q) q.toolkitGroupCancel = {} end,
    resume = function(q) q.toolkitResume = {} end,
    dead = function(q, a, actor) actor.dead = true end,
    asleep = function(q, a, actor) actor.asleep = true end,
    localPlayer = function(q, a, actor) actor.localPlayer = false end,
    slot = function(q, a, actor) specific[actor.slot] = {} end,
    cancelInput = function(q, a, actor) actor.cancel = true end,
    moving = function(q, a, actor) actor.moving = true end,
    movementInput = function(q, a, actor) actor.input = true end,
    running = function(q, a, actor) a.stopOnRun = true; actor.running = true end,
    sprinting = function(q, a, actor) a.stopOnRun = true; actor.sprinting = true end,
    aiming = function(q, a, actor) a.stopOnAim = true; actor.aiming = true end,
}
for name, mutate in pairs(mutations) do
    settings = false
    local actor, releases
    q, a, actor = fixture(); releases = 0
    prepare(q, a, {release = function() releases = releases + 1 end})
    mutate(q, a, actor)
    assert(not Lifecycle.stopValid(q, a), 'accepted changed ' .. name)
    assert(not Lifecycle.takeStopCleanup(q, a), 'invalid stop earned cleanup: ' .. name)
    Lifecycle.clearStop(q); Lifecycle.reset(q)
    assert(releases == 1, 'revoked stop did not release exactly once: ' .. name)
end
settings = false
for _, flag in ipairs({'toolkitCancel', 'toolkitStopIntent', 'toolkitOutcomeWait', 'toolkitGroupCancel', 'toolkitResume'}) do
    q, a = fixture(); q[flag] = {}
    assert(not Lifecycle.prepareStop(q, a, 'end', 'action', {guarded = true}), 'foreign flag acquired guard: ' .. flag)
end

-- Base.stop can be deferred only inside its exact original stop callback.
q, a = fixture(); prepare(q, a)
assert(Lifecycle.deferStop(q, a) == false and not Lifecycle.stopValid(q, a), 'unguarded callback scope suppressed reset')
Lifecycle.clearStop(q)
q, a = fixture(); prepare(q, a)
assert(not Lifecycle.takeStopCleanup(q, a), 'cleanup ran before native stop')
local args = pack(Lifecycle.runStop(a, function(candidate, first, second, third)
    assert(candidate == a and first == nil and second == 'middle' and third == nil)
    local otherQ, otherA = fixture()
    Lifecycle.runStop(otherA, function()
        assert(Lifecycle.deferStop(otherQ, otherA) == nil)
    end)
    assert(Lifecycle.deferStop(q, a) == true, 'nested independent callback lost the outer scope')
    return nil, 'native-result', nil
end, nil, 'middle', nil))
assert(args.n == 3 and args[1] == nil and args[2] == 'native-result' and args[3] == nil)
assert(not Lifecycle.takeStopCleanup(q, a), 'cleanup transferred before native removal')
a.character.present[a.action] = nil
assert(Lifecycle.takeStopCleanup(q, a))

q, a = fixture(); local releases = 0
prepare(q, a, {release = function() releases = releases + 1 end})
local failure = {}
local ok, problem = pcall(Lifecycle.runStop, a, function()
    assert(Lifecycle.deferStop(q, a)); error(failure)
end)
assert(not ok and problem == failure and not Lifecycle.stopValid(q, a) and not Lifecycle.takeStopCleanup(q, a))
assert(releases == 1, 'native error retained the UI hold')
Lifecycle.reset(q); assert(releases == 1)
q, a = fixture(); prepare(q, a)
Lifecycle.runStop(a, function() end)
assert(not Lifecycle.takeStopCleanup(q, a), 'callback without Base.stop earned cleanup')
Lifecycle.clearStop(q)
q, a = fixture(); prepare(q, a); stopped(q, a)
assert(Lifecycle.deferStop(q, a) == false and not Lifecycle.takeStopCleanup(q, a), 'late Base.stop reused a successful scope')
Lifecycle.clearStop(q)
q, a = fixture(); prepare(q, a)
Lifecycle.runStop(a, function()
    Lifecycle.runStop(a, function() assert(Lifecycle.deferStop(q, a) == false) end)
end)
assert(not Lifecycle.stopValid(q, a), 'same-action recursive stop reused capability')
Lifecycle.clearStop(q)

-- Reset during the native callback revokes the capability before it can advance.
q, a = fixture(); releases = 0
prepare(q, a, {release = function() releases = releases + 1 end})
Lifecycle.runStop(a, function()
    assert(Lifecycle.deferStop(q, a)); Lifecycle.reset(q)
end)
assert(releases == 1 and Lifecycle.deferStop(q, a) == nil)

-- Cleanup ownership transfers without effects; the returned closure is one-shot.
for _, fails in ipairs({false, true}) do
    q, a = fixture(); local cleanups = 0; releases = 0
    prepare(q, a, {cleanup = function(candidate)
        assert(candidate == a); cleanups = cleanups + 1
        if fails then error(failure) end
        return nil, 'cleaned', nil
    end, release = function() releases = releases + 1 end})
    stopped(q, a)
    local accepted, cleanup = Lifecycle.takeStopCleanup(q, a)
    assert(accepted and type(cleanup) == 'function' and cleanups == 0 and releases == 0)
    Lifecycle.clearStop(q); assert(releases == 0, 'transferred cleanup was released before execution')
    local result = pack(pcall(cleanup, a))
    assert(cleanups == 1 and releases == 1)
    if fails then assert(result[1] == false and result[2] == failure)
    else assert(result.n == 4 and result[1] and result[2] == nil and result[3] == 'cleaned' and result[4] == nil) end
    cleanup(a); Lifecycle.reset(q)
    assert(cleanups == 1 and releases == 1, 'cleanup or release replayed')
    local again, replay = Lifecycle.takeStopCleanup(q, a)
    assert(again and replay == nil, 'taken guard returned its cleanup twice')
end
q, a = fixture(); local accepts = true
prepare(q, a, {validate = function() return accepts end})
assert(Lifecycle.stopValid(q, a)); accepts = false
assert(not Lifecycle.stopValid(q, a)); accepts = true
assert(not Lifecycle.stopValid(q, a), 'restored validation resurrected revoked guard')
Lifecycle.clearStop(q)
q, a = fixture(); prepare(q, a, {validate = function() error(failure) end})
assert(not Lifecycle.stopValid(q, a), 'validator error granted terminal continuation')
Lifecycle.reset(q)
-- Release failures cannot replace the original native/cleanup exception.
local releaseFailure = {}
for _, phase in ipairs({'native', 'cleanup', 'release'}) do
    q, a = fixture()
    prepare(q, a, {cleanup = function() if phase == 'cleanup' then error(failure) end end,
        release = function() error(releaseFailure) end})
    if phase == 'native' then
        local success, problem = pcall(Lifecycle.runStop, a, function() error(failure) end)
        assert(not success and problem == failure and not Lifecycle.stopValid(q, a))
        local cleared, releaseProblem = Lifecycle.clearStop(q)
        assert(not cleared and releaseProblem == releaseFailure)
    else
        stopped(q, a)
        local accepted, cleanup = Lifecycle.takeStopCleanup(q, a)
        assert(accepted)
        local success, problem = pcall(cleanup, a)
        assert(not success and problem == (phase == 'cleanup' and failure or releaseFailure))
        assert(pcall(cleanup, a), 'failed cleanup replayed release')
    end
end
q, a = fixture(); prepare(q, a)
local nestedQ, nestedA = fixture()
Lifecycle.runStop(a, function()
    Lifecycle.runStop(nestedA, function()
        assert(Lifecycle.deferStop(q, a) == false, 'another native callback borrowed the outer stop scope')
    end)
end)
assert(not Lifecycle.stopValid(q, a))
Lifecycle.clearStop(q)
-- UI cancellation revokes only its exact terminal and keeps restoration held
-- until native reset; a foreign row must not release another action's hold.
q, a = fixture(); releases = 0
prepare(q, a, {release = function() releases = releases + 1 end})
stopped(q, a)
assert(not Lifecycle.invalidateStop(q, {}) and Lifecycle.stopValid(q, a))
assert(Lifecycle.invalidateStop(q, a) and not Lifecycle.stopValid(q, a))
assert(releases == 0 and not Lifecycle.takeStopCleanup(q, a), 'UI cancel released restoration ahead of reset')
Lifecycle.reset(q); Lifecycle.clearStop(q)
assert(releases == 1)
assert(not Lifecycle.invalidateStop(q, a))

-- An authorized policy stop takes over an existing guarded stop while retaining
-- the already outgoing stop's exact public intent, receipt and deadline.
q, a = fixture(); releases = 0
PZSurvivorToolkit.ActionQueueAcknowledgements = {capture = function() return receipt end}
prepare(q, a, {cleanup = function() error('policy takeover replayed terminal cleanup') end,
    release = function() releases = releases + 1 end})
intent, wait = q.toolkitStopIntent, q.toolkitOutcomeWait
local deadline = wait.deadline
forced = 0
function a:forceStop() forced = forced + 1 end
assert(Lifecycle.requestStop(q, a, 'cancel', 'operation'))
assert(forced == 1 and releases == 1 and q.toolkitStopIntent == intent and q.toolkitOutcomeWait == wait
    and wait.deadline == deadline and wait.acknowledgement == receipt)
assert(Lifecycle.deferStop(q, a) == nil, 'policy takeover retained private terminal ownership')
a.toolkitQueueOperation.toolkitCancelled = true
q.toolkitGroupCancel = {action = a}
assert(Lifecycle.stopValid(q, a), 'legacy policy stop inherited guarded token/flag restrictions')
local accepted, cleanup = Lifecycle.takeStopCleanup(q, a)
assert(accepted and cleanup == nil, 'policy takeover retained terminal cleanup')
Lifecycle.reset(q); assert(releases == 1)
do
    local queue, action, actor = fixture()
    local released = 0
    prepare(queue, action, {release=function() released=released+1 end})
    local head={character=actor};local replacement={character=actor,current=head,queue={head},generation=71}
    ISTimedActionQueue.queues[actor]=replacement
    for _, callback in ipairs(tickCallbacks) do callback() end
    for _, callback in ipairs(tickCallbacks) do callback() end
    assert(released==1 and Lifecycle.deferStop(queue,action)==nil,'detached guard retained private capability/hold')
    assert(ISTimedActionQueue.queues[actor]==replacement and replacement.current==head and #replacement.queue==1
        and replacement.queue[1]==head and replacement.generation==71,'detached sweep modified replacement queue')
end
print('Action queue terminal stop checks passed (ownership, exact baselines, native callback scope, reset, errors and one-shot cleanup).')
