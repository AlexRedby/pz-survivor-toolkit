if not NativeActionRoot then print('Automatic queue priority native checks skipped (pass --native-action-root media/lua).'); return end
require = function() end
local enabled = true
PZSurvivorToolkit = {Settings = {actionQueue = function() return enabled end}, BulkActions = {canFinish = function() return false end}}
local function derive(self, name)
    local class = {Type = name, derive = derive}; class.__index = class
    return setmetatable(class, {__index = self})
end
ISBaseObject = {derive = derive}
local install
Events = {OnTick = {Add = function() end}, OnServerCommand = {Add = function() end}, OnGameStart = {Add = function(callback) install = callback end}}
for _, name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState',
    'ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do _G[name] = {instance = function() return {} end} end
table.wipe = function(t) for key in pairs(t) do t[key] = nil end end
instanceof = function(value, name) return value and value.class == name end
getText = function(key) return key end
isClient, isServer = function() return false end, function() return false end
DebugType = {Action = {warn = function() end}}
ISLogSystem = {logAction = function() end}
local function native(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
native('shared/TimedActions/ISBaseTimedAction.lua')
native('client/TimedActions/ISTimedActionQueue.lua')
native('client/TimedActions/ISQueueActionsAction.lua')
native('shared/TimedActions/ISReadABook.lua')
native('shared/TimedActions/ISToggleStoveAction.lua')
native('client/TimedActions/ISOvenUITimedAction.lua')
ISInventoryPage = {}; native('client/TimedActions/ISInventoryTransferAction.lua')
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SetStoveStateAction.lua'))()
ISContextMenu, ISButton, ISInventoryPane, ISInventoryPaneContextMenu = {}, {}, {}, {}
ISMoveableCursor = {create = function() end}; ISBuildingObject = {tryBuild = function() end}
ISMoveablesAction = {new = function() end}; ISDisassembleMenu = {disassemble = function() end}
ISWorldObjectContextMenu = {onToggleStove = function() error('queued stove must use desired state action') end}
ISWorldObjectContextMenu.onMicrowaveSetting = function(worldobjects, object, playerNum)
    ISTimedActionQueue.add(ISOvenUITimedAction:new(getSpecificPlayer(playerNum), nil, object))
end
SkillBook, ItemTag, CharacterTrait, ItemBodyLocation, MoodleType = {}, {}, {}, {}, {}
getSandboxOptions = function() return {getOptionByName = function() return {getValue = function() return 2 end} end} end
getGameTime = function() return {getMinutesPerDay = function() return 60 end} end
ISReadABook.start = function(self) self.character.reading = true end
ISReadABook.isValid = function(self) return not self.missing end
ISReadABook.perform = function(self) self.character.reading = false; ISBaseTimedAction.perform(self) end
local function java(action)
    return {table = action, isStarted = function(self) return self.started end, finished = function(self) return self.done end,
        forceStop = function(self) self.stopping = true end, forceComplete = function(self) self.completing = true end,
        isForceComplete = function(self) return self.completing end, hasStalled = function() return false end}
end
ISBaseTimedAction.create = function(self) self.action = java(self) end
local player = {class = 'IsoPlayer', actions = {}, pages = 37, inventory = {}, reading = false}
function player:getPlayerNum() return 0 end
function player:isDead() return self.dead == true end
function player:isAsleep() return false end
function player:isLocalPlayer() return true end
function player:isDraggingCorpse() return false end
function player:isFarming() return false end
function player:isTimedActionInstant() return false end
function player:isPlayerMoving() return self.moving == true end
function player:pressedMovement() return self.moving == true end
function player:setTimedActionToRetrigger() end
function player:StartAction(action) self.actions[action] = true end
function player:getCharacterActions() return {contains = function(_, action) return self.actions[action] == true end} end
function player:setIsFarming() end
function player:setReading(value) self.reading = value end
function player:playSound() end
function player:getAlreadyReadPages() return self.pages end
function player:hasTrait() return false end
function player:getWornItems() return {getItem = function() end} end
function player:isSitting() return false end
function player:getInventory() return self.inventory end
function player:getCurrentSquare() return self.square end
function player:StopAllActionQueue() self.actions = {} end
getSpecificPlayer = function() return player end
local square = {getX = function() return 10 end, getY = function() return 10 end, getZ = function() return 0 end, canReachTo = function() return true end}
player.square = square
luautils = {walkAdj = function(character)
    ISTimedActionQueue.clear(character)
    return true
end}
local function project(name)
    if name == 'ActionQueue' then project('ActionQueueLifecycle'); project('ActionQueueAcknowledgements') end
 assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/' .. name .. '.lua'))() end
project('ActionQueueOperations'); project('ActionQueueDefinitions'); project('ActionQueueLabels'); project('ActionQueuePolicy'); project('ActionQueue'); project('ActionQueueWorld'); install()
local operations, api = PZSurvivorToolkit.ActionQueueOperations, PZSurvivorToolkit.ActionQueue
local q = ISTimedActionQueue.getTimedActionQueue(player)
local leaf = ISBaseTimedAction:derive('PriorityFixture')
local completed = {}
function leaf:isValid() return true end
function leaf:perform() completed[#completed + 1] = self.name; ISBaseTimedAction.perform(self) end
PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior('priority.fixture', {
    types = {leaf.Type},
    matches = function(action) return getmetatable(action) == leaf end,
    inspect = function() return {items = {}, targets = {}, cancelWaiting = true, interrupt = 'finish-step'} end,
})
local function ordinary(name)
    local action = ISBaseTimedAction.new(leaf, player); action.name, action.maxTime = name, 1
    ISTimedActionQueue.add(action); return action
end
local function stove()
    local object = {class = 'IsoStove', active = false, calls = 0}
    function object:getSquare() return square end
    function object:getObjectIndex() return 0 end
    function object:getContainer() return {isPowered = function() return true end} end
    function object:Activated() return self.active end
    function object:PlayToggleSound() end
    function object:Toggle() self.active = not self.active; self.calls = self.calls + 1 end
    return object
end
local nextBook = 0
local function reading()
    nextBook = nextBook + 1
    local item = {class = 'InventoryItem', id = nextBook, pages = player.pages}
    function item:getID() return self.id end
    function item:getContainer() return player.inventory end
    function item:getFullType() return 'Base.BookCarpentry' end
    function item:getType() return 'BookCarpentry' end
    function item:getSkillTrained() return '' end
    function item:getNumberOfPages() return 100 end
    function item:getAlreadyReadPages() return self.pages end
    function item:setAlreadyReadPages(value) self.pages = value end
    function item:setJobDelta(value) self.delta = value end
    function item:hasTag() return false end
    local action = ISReadABook:new(player, item); ISTimedActionQueue.add(action)
    action.action.started = true; action:start()
    return action
end
local function reset()
    q:resetQueue(); player.actions, player.dead, player.moving, player.reading = {}, false, false, false
    completed, enabled = {}, true
end
local function frame()
    local action = q.queue[1]
    if action and action.action and player.actions[action.action] then
        local nativeAction = action.action
        if not nativeAction.started then nativeAction.started = true; action:start() end
        if nativeAction.done or nativeAction.completing then action:perform(); if action.complete then action:complete() end end
        if nativeAction.stopping or not action:isValid() then action:stop() end
        if nativeAction.stopping or nativeAction.done or nativeAction.completing or not action:isValid() then player.actions[nativeAction] = nil end
    end
    q:tick()
end
local function finish() q.current.action.done = true; frame() end

-- A click gains priority automatically; native Java removal gates exactly one resumed book.
reset(); local book = reading(); local tail = ordinary('tail'); local object = stove()
ISWorldObjectContextMenu.onToggleStove(nil, object, 0); local urgent = q.queue[3]
q:tick()
assert(q.current == book and book.action.stopping and q.queue[2] == urgent and q.queue[3] == tail)
q:tick(); assert(#q.queue == 3 and q.current == book, 'wait for Java removal rather than Lua completion')
frame()
local resumed = q.queue[2]
assert(q.current == urgent and resumed.Type == 'ISReadABook' and resumed ~= book and resumed.item == book.item
    and resumed.startPage == 37 and resumed.pageTimer == 0 and q.queue[3] == tail)
q:tick(); assert(q.queue[2] == resumed and #q.queue == 3, 'repeated ticks cannot append another resume')
frame(); frame(); finish()
assert(object.calls == 1 and object.active and q.current == resumed and q.queue[2] == tail)

-- Two urgent requests retain FIFO, and the unrelated waiting tail retains its relative order.
reset(); book = reading(); local firstTail, secondTail = ordinary('one'), ordinary('two')
local firstStove, secondStove = stove(), stove()
ISWorldObjectContextMenu.onToggleStove(nil, firstStove, 0); local firstUrgent = q.queue[4]
ISWorldObjectContextMenu.onToggleStove(nil, secondStove, 0); local secondUrgent = q.queue[5]
q:tick(); frame(); frame(); frame()
assert(q.current.Type == 'PZSurvivorToolkitSetStoveState')
q:tick(); assert(q.queue[2] == secondUrgent, 'second urgent waits behind first urgent whole operation')
finish(); frame(); frame(); finish()
assert(firstStove.calls == 1 and secondStove.calls == 1)
assert(q.queue[#q.queue - 1] == firstTail and q.queue[#q.queue] == secondTail)

-- A multi-step active operation is never split/preempted; urgent waits at its whole-token boundary.
reset(); local active, activeTail
operations.run(function() active = ordinary('active'); activeTail = ordinary('active-tail') end)
tail = ordinary('tail'); object = stove(); ISWorldObjectContextMenu.onToggleStove(nil, object, 0); urgent = q.queue[4]
q:tick()
assert(q.current == active and not active.action.stopping and q.queue[2] == activeTail and q.queue[3] == urgent and q.queue[4] == tail)
finish(); assert(q.current == activeTail and q.queue[2] == urgent)
finish(); assert(q.current == urgent and q.queue[2] == tail)

-- User cancellation, death, movement and disabled settings suppress an in-flight automatic resume.
for _, mode in ipairs({'clear', 'death', 'movement', 'disabled'}) do
    reset(); book = reading(); ordinary('tail'); object = stove(); ISWorldObjectContextMenu.onToggleStove(nil, object, 0)
    q:tick(); assert(book.action.stopping)
    if mode == 'clear' then q:clearQueue()
    elseif mode == 'death' then player.dead = true
    elseif mode == 'movement' then player.moving = true
    else enabled = false end
    frame()
    assert(not q.toolkitResume and not q.toolkitCancel, mode .. ' must revoke pending automatic continuation')
    for _, queued in ipairs(q.queue) do assert(queued.item ~= book.item, mode .. ' must not restore the book') end
    enabled, player.dead, player.moving = true, false, false
    q:tick()
    for _, queued in ipairs(q.queue) do assert(queued.item ~= book.item, mode .. ' old generation cannot resume after reactivation') end
end

-- A pending microwave/settings operation on the same stove blocks automatic crossing; a different target permits it.
for _, sameTarget in ipairs({true, false}) do
    reset(); book = reading(); object = stove()
    -- Native UI uses the explicit actor argument; avoid a closure on mutable fixture state.
    ISWorldObjectContextMenu.onMicrowaveSetting(nil, sameTarget and object or stove(), 0)
    local settings = q.queue[2]; tail = ordinary('tail')
    ISWorldObjectContextMenu.onToggleStove(nil, object, 0); urgent = q.queue[4]
    local decision = PZSurvivorToolkit.ActionQueuePolicy.evaluatePriority(q, urgent, true)
    assert(decision.allowed ~= sameTarget, 'microwave settings and power requests share the actual stove target')
    q:tick()
    if sameTarget then
        assert(not book.action.stopping and q.queue[2] == settings and q.queue[4] == urgent)
        assert(urgent.toolkitQueueOperation.toolkitPriorityReason, 'blocked urgent request exposes its current reason')
    else assert(book.action.stopping and q.queue[2] == urgent) end
end

-- Native transfer helper overrides are rejected without running the helper, even with the exact Type/metatable.
reset(); book = reading(); getTimestampMs = function() return 0 end
local item = {class = 'InventoryItem', getID = function() return 1000 end,
    getFullType = function() return 'Base.Test' end, getContainer = function() return player.inventory end}
local transfer = ISInventoryTransferAction:new(player, item, nil, nil)
transfer.srcContainer, transfer.destContainer = player.inventory, {}
ISTimedActionQueue.add(transfer)
local policy = PZSurvivorToolkit.ActionQueuePolicy
assert(policy.inspect(transfer), 'native transfer constructor remains recognized')
local original = transfer.checkQueueList
transfer.checkQueueList = function() error('read-only policy cannot run a modified native helper') end
assert(not policy.inspect(transfer), 'changed native transfer helper invalidates its contract')
object = stove(); ISWorldObjectContextMenu.onToggleStove(nil, object, 0); urgent = q.queue[3]
assert(not policy.evaluatePriority(q, urgent, true).allowed, 'unverified transfer blocks automatic crossing')
transfer.checkQueueList = original
assert(policy.inspect(transfer) and policy.evaluatePriority(q, urgent, true).allowed)
print('Automatic priority native queue: once-only book resume, Java removal, FIFO, preserved tail, whole active operation boundary and lifecycle invalidation passed.')

-- Changes between Lua stop and Java removal are rechecked at the final resume boundary.
for _, mode in ipairs({'late-movement','late-disable','changed-constructor'}) do
    reset();book=reading();tail=ordinary('tail');object=stove()
    ISWorldObjectContextMenu.onToggleStove(nil,object,0);urgent=q.queue[3]
    q:tick();book:stop()
    assert(q.toolkitCancelStopped and player.actions[book.action])
    local constructor=ISReadABook.new
    if mode=='late-movement' then player.moving=true
    elseif mode=='late-disable' then enabled=false
    else ISReadABook.new=function()error('unknown constructor must not run during resume')end end
    player.actions[book.action]=nil
    q:tick()
    assert(not q.toolkitResume and not q.toolkitCancel)
    for _,queued in ipairs(q.queue) do assert(queued.item~=book.item,mode..' must suppress automatic book reconstruction') end
    if mode=='changed-constructor' then assert(q.current==urgent and q.queue[2]==tail,'unrelated work retained after unsafe resume is omitted')
    else assert(#q.queue==0,'manual abort must clear queued work')end
    ISReadABook.new=constructor
end
