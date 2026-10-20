local function hasEntry(value)
    for _ in pairs(value) do return true end
    return false
end
-- Native Lua queue/base/book callbacks; Java lifecycle is exercised by the MP smoke.
require = function() end
local enabled, activePlayer = true, nil
PZSurvivorToolkit = {Settings = {actionQueue = function() return enabled end}}
getSpecificPlayer = function() return activePlayer end
getText = function(key) return key end
instanceof = function(value, name) return type(value) == 'table' and value.class == name end
local function derive(self, name)
    local t = {Type = name, derive = derive}
    t.__index = t
    return setmetatable(t, {__index = self})
end
ISBaseObject = {derive = derive}
table.wipe = function(t) for k in pairs(t) do t[k] = nil end end
Events = {OnTick = {Add = function() end}}
Events.OnServerCommand = {Add = function() end}
for _, name in ipairs({'ClimbThroughWindowState','ClimbOverFenceState','ClimbOverWallState','ClimbSheetRopeState',
    'ClimbDownSheetRopeState','CloseWindowState','OpenWindowState'}) do
    _G[name] = {instance = function() return {} end}
end
DebugType = {Action = {warn = function() end}}
ISLogSystem = {logAction = function() end}
if not NativeActionRoot then
    print('Action queue native-contract checks skipped (pass --native-action-root media/lua).')
    return
end
local function load(path) assert(loadfile(NativeActionRoot .. '/' .. path))() end
load('shared/TimedActions/ISBaseTimedAction.lua')
load('client/TimedActions/ISTimedActionQueue.lua')
load('client/TimedActions/ISQueueActionsAction.lua')
local nativeResetQueue = ISTimedActionQueue.resetQueue
local function reloadQuartermaster()
    assert(loadfile(NativeQuartermasterLuaRoot .. '/client/LootSorter_WalkAction.lua'))()
end
if NativeQuartermasterLuaRoot then
    load('client/TimedActions/WalkToTimedAction.lua')
    LootSorter = {isDebug = function() return false end, addOrReplaceHandler = function() end}
    reloadQuartermaster()
end
load('shared/TimedActions/ISReadABook.lua')
load('shared/Moveables/ISMoveablesAction.lua')
load('shared/Vehicles/TimedActions/ISRemoveBurntVehicle.lua')
ISInventoryPage = {}
load('client/TimedActions/ISInventoryTransferAction.lua')
ISContextMenu, ISButton, ISInventoryPaneContextMenu = {}, {}, {getContainers=function() return {contains=function() return true end} end}
Events.OnGameStart = {Add = function(fn) fn() end}
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueOperations.lua'))()
local operations = PZSurvivorToolkit.ActionQueueOperations
SkillBook, ItemTag, CharacterTrait, ItemBodyLocation = {}, {}, {}, {}
MoodleType = {}
getSandboxOptions = function() return {getOptionByName=function() return {getValue=function() return 2 end} end} end
getGameTime = function() return {getMinutesPerDay=function() return 60 end} end
-- Exercise the native constructor/duration; animation and Java validity are fixture doubles.
ISReadABook.start = function(self) self.character:setReading(true) end
ISReadABook.isValid = function(self) return not self.missing end
ISReadABook.perform = function(self) self.character:setReading(false); ISBaseTimedAction.perform(self) end
local newRead = ISReadABook.new
ISReadABook.new = function(self, character, item)
    local a = newRead(self, character, item)
    return a
end
LuaTimedActionNew = {new = function(t)
    return {table = t, started = false, progress = 0,
        isStarted = function(s) return s.started end,
        forceStop = function(s) s.stopping = true end,
        forceComplete = function(s) s.completing = true end,
        isForceComplete = function(s) return s.completing == true end,
        finished = function(s) return s.done == true end,
        hasStalled = function() return false end,
        getJobDelta = function(s) return s.progress end}
end}
local function player()
    local p = {class = 'IsoPlayer', actions = {}, inventory = {items = {}}, farming = false, reading = false}
    function p.inventory:getItemById(id)
        local item = self.items[id]
        if item and item:getContainer() == self then return item end
    end
    function p:getInventory() return self.inventory end
    function p:getPlayerNum() return 0 end
    function p:isTimedActionInstant() return false end
    function p:getAlreadyReadPages() return self.pages or 12 end
    function p:hasTrait() return false end
    function p:getWornItems() return {getItem=function() end} end
    function p:isSitting() return false end
    function p:getMoodles() return {getMoodleLevel=function() return 0 end} end
    function p:getTimedActionTimeModifier() return 1 end
    function p:isDead() return self.dead == true end
    function p:isAsleep() return false end
    function p:isLocalPlayer() return true end
    function p:isDraggingCorpse() return false end
    function p:isFarming() return self.farming end
    function p:isPlayerMoving() return self.moving == true end
    function p:pressedMovement() return self.moving == true end
    function p:setIsFarming(v) self.farming = v end
    function p:setReading(v) self.reading = v end
    function p:playSound() end
    function p:setTimedActionToRetrigger(v) self.retrigger = v end
    function p:getCharacterActions()
        return {contains = function(_, action) return self.actions[action] == true end}
    end
    function p:StartAction(a) self.actions[a] = true end
    function p:StopAllActionQueue()
        for a in pairs(self.actions) do if a.started then a.table:stop() end end
        self.actions = {}
    end
    activePlayer = p
    return p
end
local nextItemID = 0
local function book(p)
    local a = ISBaseTimedAction.new(ISReadABook, p)
    a.maxTime = 1
    nextItemID = nextItemID + 1
    a.item = {id = nextItemID, container = p.inventory, delta = .5, getNumberOfPages = function() return 100 end,
        getID = function(self) return self.id end, getContainer = function(self) return self.container end,
        getAlreadyReadPages = function(s) return s.pages or 12 end,
        setAlreadyReadPages=function(s,v) s.pages=v end, getFullType=function() return 'Base.BookCarpentry' end,
        getSkillTrained=function() return '' end, hasTag=function() return false end, getType = function() return 'BookCarpentry' end,
        setJobDelta = function(s,v) s.delta = v end, getDisplayName = function() return 'Book' end, getTex = function() return 'book-icon' end,
        class = 'InventoryItem'}
    p.inventory.items[a.item:getID()] = a.item
    return a
end
local completions = {}
local leafType = ISBaseTimedAction:derive('ToolkitTestLeaf')
local function leaf(p, name)
    local a = ISBaseTimedAction.new(leafType, p)
    a.maxTime, a.name, a.toolkitIndependentBulk = 1, name, true
    a.isValid = function(s) return not s.missing end
    a.perform = function(s) completions[#completions+1] = s.name; ISBaseTimedAction.perform(s) end
    return a
end
-- Uses the native updater's perform-before-stop and remove-after-stop ordering.
local function frame(p)
    local q = ISTimedActionQueue.getTimedActionQueue(p)
    local a = q.queue[1]
    if a and a.action and p.actions[a.action] then
        local j = a.action
        if not j.started then j.started = true; a:start() end
        if j.done or j.completing then a:perform() end
        if j.stopping or not a:isValid() then a:stop() end
        if j.stopping or j.done or j.completing or not a:isValid() then p.actions[j] = nil end
    end
    q:tick()
end
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueDefinitions.lua'))()
for kind, key in pairs({ToolkitWoodCartPickup='ContextMenu_Grab', ToolkitWoodCartSetdown='ContextMenu_Drop', ToolkitWoodCartDrop='ContextMenu_Drop'}) do
    local shown = PZSurvivorToolkit.ActionQueueDefinitions.describe({Type=kind})
    assert(shown.role=='preparation' and shown.title==getText(key), 'cart interaction lost its queue presentation')
end
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLabels.lua'))()
-- Simulate transfer execution while keeping exact class methods for active-preparation validation.
ISInventoryTransferAction.start = function() end
ISInventoryTransferAction.isValid = function() return true end
ISInventoryTransferAction.stop = function(self) ISBaseTimedAction.stop(self) end
ISInventoryTransferAction.perform = function(self)
    self.item.container = self.destContainer
    ISBaseTimedAction.perform(self)
end
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/BulkActions.lua'))()
if not PZSurvivorToolkit.ActionQueueDefinitions then assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueDefinitions.lua'))() end
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueuePolicy.lua'))()
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua'))()
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueAcknowledgements.lua'))()
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueue.lua'))()
local api = PZSurvivorToolkit.ActionQueue
assert(loadfile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueReading.lua"))()
if NativeQuartermasterLuaRoot then
    for reload = 0, 3 do
        if reload == 3 then
            ISTimedActionQueue.resetQueue = nativeResetQueue
            LootSorter._vanillaResetQueue = nil
        end
        if reload > 0 then reloadQuartermaster() end
        for _, method in ipairs({'resetQueue', 'clearQueue'}) do
            local p = player()
            local action = book(p)
            local q = ISTimedActionQueue.add(action)
            local token = action.toolkitQueueOperation
            local resumed = false
            local pending = operations.attachContinuation(token, p)
            local generation = q.toolkitOperationGeneration or 0
            local cancellations = 0
            action.forceCancel = function()
                assert(token.toolkitCancelled and q.toolkitOperationGeneration == generation + 1,
                    'native cancellation ran before Toolkit invalidation')
                cancellations = cancellations + 1
            end
            q.toolkitCancel, q.toolkitResume, q.toolkitGroupCancel = action, action, {}
            q[method](q)
            assert((q.toolkitOperationGeneration or 0) == generation + 1 and token.toolkitCancelled,
                'Quartermaster reload ' .. reload .. ' bypassed operation invalidation')
            operations.runContinuation(pending, function() resumed = true end)
            assert(not resumed and #q.queue == 0 and cancellations == 1
                and q.current == (method == 'clearQueue' and action or nil)
                and not q.toolkitCancel and not q.toolkitResume and not q.toolkitGroupCancel,
                'reset allowed a canceled continuation to refill the queue')
        end
    end
end
do
    local p = player()
    local parent, child, tail = book(p), book(p), book(p)
    local q = ISTimedActionQueue.add(parent)
    ISTimedActionQueue.add(child); ISTimedActionQueue.add(tail)
    parent._isAddingActions, parent._numAddedActions = true, 1
    child.toolkitQueueOperation = parent.toolkitQueueOperation
    local pending = operations.attachContinuation(parent.toolkitQueueOperation, p)
    local generation, canceled = q.toolkitOperationGeneration or 0, 0
    child.forceCancel = function() canceled = canceled + 1 end
    q:clearQueue()
    assert(#q.queue == 2 and q.queue[1] == parent and q.queue[2] == tail and canceled == 1
        and parent._numAddedActions == 0 and not parent.toolkitQueueOperation.toolkitCancelled
        and (q.toolkitOperationGeneration or 0) == generation, 'expansion clear invalidated its parent or unrelated tail')
    local resumed = false
    operations.runContinuation(pending, function() resumed = true end)
    assert(resumed, 'expansion clear revoked a valid continuation')
end
do
    local idlePlayer=player()
    local idleQueue=ISTimedActionQueue.getTimedActionQueue(idlePlayer)
    local generation=idleQueue.toolkitOperationGeneration or 0
    local resumed=0
    local pending=operations.attachContinuation({},idlePlayer)
    idleQueue:tick();idleQueue:tick()
    assert((idleQueue.toolkitOperationGeneration or 0)==generation,
        'native empty ticks are housekeeping, not explicit queue cancellation')
    operations.runContinuation(pending,function() resumed=resumed+1 end)
    assert(resumed==1,'late continuation survives normal native idle ticks')
    for _,mode in ipairs({'clear','reset','disabled','dead'}) do
        pending=operations.attachContinuation({},idlePlayer)
        generation=idleQueue.toolkitOperationGeneration or 0
        if mode=='clear' then idleQueue:clearQueue()
        elseif mode=='reset' then idleQueue:resetQueue()
        elseif mode=='disabled' then enabled=false;idleQueue:tick()
        else idlePlayer.dead=true;idleQueue:tick() end
        assert((idleQueue.toolkitOperationGeneration or 0)==generation+1,
            mode..' still invalidates an empty queue with pending callbacks')
        operations.runContinuation(pending,function() resumed=resumed+1 end)
        assert(resumed==1,mode..' prevents late continuation from repopulating the empty queue')
        enabled,idlePlayer.dead=true,false
        idleQueue:tick()
    end
end

-- These lifecycle tests use explicit doubles; only the audited fixture classes get contracts.
local fixtureClasses = {[leafType] = true}
local function fixtureResources(action)
    local result = {items = {}, targets = {}, cancelWaiting = false, bulk = action.toolkitIndependentBulk == true,
        preparation = action.Type == "ISInventoryTransferAction" or action.Type == "ISWalkToTimedAction" or action.Type == "ISEquipWeaponAction"}
    for _, key in ipairs({'item','gun','magazine','weapon','primary','secondary'}) do
        local value = action[key]
        if value and instanceof(value, 'InventoryItem') then result.items[value:getID()] = true end
    end
    if action.fixtureScrap then result.interrupt = 'audited-stop' end
    return result
end
PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior('fixture.lifecycle', {
    types = {'ToolkitTestLeaf', 'ISInventoryTransferAction', 'ISEquipWeaponAction', 'ISWalkToTimedAction', 'ISMoveablesAction', 'ISRemoveBurntVehicle'},
    matches = function(action)
        if action.onStartFunc or action.onCompleteFunc or action.onCancelFunc or action.Type == 'ISQueueActionsAction' then return false end
        if action.fixtureScrap then return true end
        return fixtureClasses[getmetatable(action)] and (action.Type == getmetatable(action).Type
            or (getmetatable(action) == leafType and (action.Type == 'ISInventoryTransferAction' or action.Type == 'ISEquipWeaponAction')))
    end,
    inspect = fixtureResources,
})

local p = player()
local a, b, c = book(p), book(p), leaf(p, 'tail')
local q = ISTimedActionQueue.add(a); ISTimedActionQueue.add(b); ISTimedActionQueue.add(c)
frame(p)
assert(api.cancel(q,b) and q.queue[1] == a and q.queue[2] == c and q.current == a)
assert(not api.cancel(q,b), 'stale identity must never cancel another row')
assert(api.cancel(q,a)); assert(q.current == a and q.queue[2] == c)
q:tick(); assert(q.current == a, 'wait for engine stop and packet before resuming')
frame(p)
assert(q.current == c and #q.queue == 1 and not p.reading and a.item.delta == 0)
assert(not q.toolkitCancel and not p.actions[a.action] and p.actions[c.action])
c.action.done = true; frame(p); assert(#q.queue == 0 and completions[1] == 'tail')
-- More than five rows; removal preserves all identities and order.
p = player(); q = ISTimedActionQueue.add(book(p)); local originals = {}
for i=1,20 do originals[i] = book(p); ISTimedActionQueue.add(originals[i]) end
assert(api.cancel(q, originals[10]) and #q.queue == 20)
for i=1,9 do assert(q.queue[i+1] == originals[i]) end
for i=11,20 do assert(q.queue[i] == originals[i]) end
-- Dependencies, callbacks and utility operations are never removed blindly.
local utility = leaf(p, 'transfer'); utility.toolkitIndependentBulk = nil; utility.Type = 'ISInventoryTransferAction'
ISTimedActionQueue.add(utility)
assert(not api.cancel(q, utility) and #q.queue == 21)
local linked = book(p); ISTimedActionQueue.addAfter(originals[1], linked)
assert(api.cancelReason(q, linked) == 'dependent' and api.cancelReason(q, originals[1]) == 'dependent')
local callback = book(p); callback.onCompleteFunc = function() error('must not invoke') end
ISTimedActionQueue.add(callback); assert(api.cancelReason(q, callback) == 'dependent')
local bulk = leaf(p, 'dismantle'); ISTimedActionQueue.add(bulk)
assert(api.cancel(q, bulk), 'independent pending bulk leaf')
bulk = leaf(p, 'dismantle'); ISTimedActionQueue.add(bulk)
local generator = leaf(p, 'generator'); generator.Type = 'ISQueueActionsAction'; generator.toolkitIndependentBulk = nil
ISTimedActionQueue.add(generator); assert(api.cancelReason(q, bulk) == 'dependent')
-- Started transfers/crafts are blocked; no item transaction API is called.
p = player(); a = leaf(p, 'active'); q = ISTimedActionQueue.add(a); frame(p)
assert(api.cancelReason(q, a) == 'active')
-- A deferred world command can be removed before it prepares tools or touches the target.
p=player();q=ISTimedActionQueue.add(book(p))
local deferredWeld=ISQueueActionsAction:new(p,function() error('cancelled command executed') end)
local worldCallback=deferredWeld.addActionsFunction
PZSurvivorToolkit.ActionQueueWorld={isDeferredAction=function(action)
    return (action.toolkitWorldDismantle == true or action.toolkitWorldOperation == 'build')
        and action.addActionsFunction == worldCallback
end}
deferredWeld.toolkitWorldDismantle=true
ISTimedActionQueue.add(deferredWeld)
assert(api.cancel(q,deferredWeld) and #q.queue==1 and not deferredWeld.action)
local forgedWorld=ISQueueActionsAction:new(p,function() error('unverified callback must not execute') end)
forgedWorld.toolkitWorldDismantle=true
ISTimedActionQueue.add(forgedWorld)
assert(api.cancelReason(q,forgedWorld)=='dependent' and not api.cancel(q,forgedWorld))
deferredWeld.toolkitWorldName='Metal Door'
Translator={getMoveableDisplayName=function(name) return 'Translated '..name end}
assert(api.label(deferredWeld)=='ContextMenu_Disassemble: Translated Metal Door')
-- Dismantling stop uses native cleanup without performing scrap/material transactions.
ISInventoryPage.OnObjectHighlighted = function(_, object, highlighted) object.uiHighlight = highlighted end
ISMoveableCursor = {clearCacheForAllPlayers=function() end}
local function weld(character)
    local action = ISBaseTimedAction.new(ISMoveablesAction, character)
    action.fixtureScrap = true
    local target = {highlighted=true, setHighlighted=function(self, _, value) self.highlighted=value end}
    action.mode, action.maxTime, action.playerNum, action.sound = 'scrap', 1, 0, 123
    action.moveProps = {object=target, scrapObjectViaCursor=function() error('cancel must not produce scrap or consume fuel') end}
    action.start = function() end
    action.isValid = function() return true end
    character.stopOrTriggerSound = function(self, sound) self.stoppedSound=sound end
    return action
end
p=player();a,b,c=weld(p),weld(p),weld(p)
q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b);ISTimedActionQueue.add(c)
assert(api.cancel(q,b) and q.queue[2]==c and b.moveProps.object.highlighted, 'pending cancel never runs stop/complete')
assert(api.cancelReason(q,a)=='starting');frame(p)
assert(not api.move(q,c,a), 'cancellable welding must not enable read-only preemption')
assert(api.cancel(q,a));q:tick();assert(q.current==a and not c.action)
frame(p)
assert(q.current==c and not p.actions[a.action] and not a.moveProps.object.highlighted)
assert(a.moveProps.object.uiHighlight==false and p.stoppedSound==123)
for _,mode in ipairs({'finish','normal','clear','move','dead','respawn','dropped'}) do
    p=player();a,b=weld(p),leaf(p,'weld-'..mode);q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b);frame(p)
    if mode=='normal' then a:forceStop() else assert(api.cancel(q,a)) end
    if mode=='finish' then a.action.completing=true
    elseif mode=='clear' then ISTimedActionQueue.clear(p)
    elseif mode=='move' then p.moving=true
    elseif mode=='dead' then p.dead=true
    elseif mode=='respawn' then activePlayer=player()
    elseif mode=='dropped' then p.actions={} end
    frame(p)
    assert(not q.toolkitCancel and #q.queue==(mode=='finish' and 1 or 0), 'weld '..mode..' resurrected a tail')
end
print('Native dismantling cancellation: pending/current, sound/highlights, no scrap transaction, completion and stop races passed.')
-- Skip one bulk operation, retaining the next selected weapon's native preparation.
p = player(); q = ISTimedActionQueue.add(book(p))
local first, equip, second = leaf(p,'first-weapon'), leaf(p,'equip'), leaf(p,'second-weapon')
equip.Type, equip.toolkitIndependentBulk, equip.toolkitBulkPreparation = 'ISEquipWeaponAction', nil, true
ISTimedActionQueue.add(first); ISTimedActionQueue.add(equip); ISTimedActionQueue.add(second)
assert(api.cancel(q, first) and q.queue[2] == equip and q.queue[3] == second)
assert(api.cancelReason(q, equip) == 'dependent', 'preparation itself remains protected')
-- Whole waiting operations remove preparation/main/returns atomically, preserving unrelated identities.
local function preparation(character, kind, item)
    local class = ISBaseTimedAction:derive(kind)
    if kind == 'ISInventoryTransferAction' or kind == 'ISWalkToTimedAction' or kind == 'ISEquipWeaponAction' then fixtureClasses[class] = true end
    local action = ISBaseTimedAction.new(class, character)
    action.item = item
    return action
end
p=player();a,d=book(p),book(p);q=ISTimedActionQueue.add(a)
local pickup, read, restore, walk, equip=preparation(p,'ISInventoryTransferAction'),book(p),
    preparation(p,'ISInventoryTransferAction'),preparation(p,'ISWalkToTimedAction'),preparation(p,'ISEquipWeaponAction')
pickup.item,restore.item,equip.item=read.item,read.item,read.item
operations.run(function()
    for _, member in ipairs({walk,pickup,equip,read,restore}) do ISTimedActionQueue.add(member) end
end)
ISTimedActionQueue.add(d)
local originalQueue,currentNative=q.queue,a.action
assert(api.cancelOperationReason(q,pickup)==nil and api.cancelReason(q,pickup)=='dependent')
assert(api.cancelOperation(q,read) and q.queue==originalQueue and #q.queue==2 and q.queue[1]==a and q.queue[2]==d)
assert(q.current==a and a.action==currentNative and not pickup.action and not restore.action)
assert(not api.cancelOperation(q,read), 'removed group identity cannot select a replacement')
-- Native addAfter links are safe only when every member is removed together.
b,c=book(p),book(p);ISTimedActionQueue.add(b);ISTimedActionQueue.addAfter(b,c)
assert(api.cancelReason(q,b)=='dependent' and api.cancelOperation(q,c) and #q.queue==2)
-- A mixed verified batch is eligible; unsupported callbacks/actions and preparation-only groups are protected.
local function pendingGroup(...)
    p=player();q=ISTimedActionQueue.add(book(p))
    local members={...}
    operations.run(function()
        for _, member in ipairs(members) do member.character=p;ISTimedActionQueue.add(member) end
    end)
    return members[1]
end
b=pendingGroup(book(p),leaf(p,'verified-mixed'))
assert(api.cancelOperation(q,b) and #q.queue==1)
b=pendingGroup(preparation(p,'ISWalkToTimedAction'),preparation(p,'ISEquipWeaponAction'))
assert(api.cancelOperationReason(q,b)=='operation_dependent')
b=pendingGroup(book(p),preparation(p,'ModWork'))
assert(api.cancelOperationReason(q,b)=='operation_dependent')
for _, field in ipairs({'onCompleteFunc','onStartFunc','onCancelFunc','forceCancel'}) do
    b=pendingGroup(book(p),book(p));c=q.queue[3]
    assert(not api.cancelOperationReason(q,b))
    c[field]=function() error('protected callback must not execute') end
    assert(api.cancelOperationReason(q,b)=='operation_dependent' and not api.cancelOperation(q,b) and #q.queue==3)
end
b=pendingGroup(preparation(p,'ISInventoryTransferAction'),book(p))
b.onCompleteFunc=function() error('completion is never called for pending removal') end
b.toolkitQueueSafeOnComplete=b.onCompleteFunc
assert(not api.cancelOperation(q,b), 'a copied public completion marker cannot approve an unknown transfer callback')
b=pendingGroup(preparation(p,'ISInventoryTransferAction'),book(p));b.onCompleteFunc=function() end
b.toolkitQueueSafeOnComplete=b.onCompleteFunc;b.onCompleteFunc=function() error('changed callback') end
assert(api.cancelOperationReason(q,b)=='operation_dependent', 'changed callbacks invalidate the exact safety marker')
-- The active group can be cancelled after start; detached started tails stay protected.
p=player();a,b=book(p),book(p)
operations.run(function() q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b) end)
assert(api.cancelOperationReason(q,b)=='starting')
frame(p);assert(not api.cancelOperationReason(q,b))
a.action.done=true;frame(p);frame(p)
assert(not api.cancelOperationReason(q,b) and #q.queue==1)
b.action=nil;q.current=nil
local placeholder=book(p);placeholder.action={};table.insert(q.queue,1,placeholder)
assert(api.cancelOperationReason(q,b)=='operation_active', 'even an unstarted tail of an already started group remains protected')
-- Split tokens and known external item/world/output dependencies cannot be removed as one operation.
b=pendingGroup(book(p),book(p));c=q.queue[3];d=book(p);ISTimedActionQueue.add(d)
q.queue[3],q.queue[4]=d,c
assert(api.cancelOperationReason(q,b)=='operation_dependent')
b=pendingGroup(book(p),book(p));local use=book(p);use.item=b.item;ISTimedActionQueue.add(use)
assert(api.cancelOperationReason(q,b)=='operation_shared_item')
local function nativeList(item) return {size=function() return 1 end,get=function() return item end} end
for _, field in ipairs({'items','manualInputs'}) do
    b=pendingGroup(book(p),book(p));use=preparation(p,'ISHandcraftAction')
    use[field]=field=='items' and nativeList(b.item) or {[0]=nativeList(b.item)}
    ISTimedActionQueue.add(use)
    assert(api.cancelOperationReason(q,b)=='operation_dependent', 'unverified craft inputs remain protected')
    use[field]={malformed=true}
    assert(api.cancelOperationReason(q,b)=='operation_dependent', 'malformed input lists must fail closed')
end
b=pendingGroup(leaf(p,'output'),book(p));ISTimedActionQueue.add(preparation(p,'ISQueueActionsAction'))
assert(api.cancelOperationReason(q,b)=='operation_dependent', 'unknown output consumers remain protected')
b=pendingGroup(leaf(p,'output'),book(p));use=book(p);use.onCompleteFunc=function() error('later callback dependency') end
ISTimedActionQueue.add(use)
assert(api.cancelOperationReason(q,b)=='operation_dependent', 'later callbacks may depend on an otherwise removable operation output')
b=pendingGroup(book(p),book(p));use=preparation(p,'ModWork');use.items={custom='mod collection'};ISTimedActionQueue.add(use)
assert(not api.cancelOperation(q,b), 'unknown mod actions are barriers even when their item fields look unrelated')
local world={class='IsoObject'}
b=pendingGroup(leaf(p,'scrap'),preparation(p,'ISWalkToTimedAction'));b.toolkitWorldTarget=world
use=preparation(p,'ISActivateGenerator');use.generator=world;ISTimedActionQueue.add(use)
assert(api.cancelOperationReason(q,b)=='operation_dependent')
-- Deferred world groups require their module-owned exact callback validator.
b=pendingGroup(ISQueueActionsAction:new(p,worldCallback),preparation(p,'ISWalkToTimedAction'))
b.toolkitWorldDismantle=true
assert(api.cancelOperation(q,b) and #q.queue==1)
b=pendingGroup(ISQueueActionsAction:new(p,worldCallback),book(p));b.toolkitWorldDismantle=true
b.addActionsFunction=function() error('substituted world callback must not execute') end
assert(api.cancelOperationReason(q,b)=='operation_dependent' and not api.cancelOperation(q,b))
b=pendingGroup(ISQueueActionsAction:new(p,worldCallback),book(p));b.toolkitIndependentBulk=true
assert(api.cancelOperationReason(q,b)=='operation_dependent', 'a bulk marker cannot approve an arbitrary generator')
-- A press snapshot protects against insertion/removal even before the panel refreshes.
b=pendingGroup(book(p),book(p));local snapshot={b,q.queue[3]};ISTimedActionQueue.addAfter(b,book(p))
assert(not api.cancelOperation(q,b,snapshot) and #q.queue==4)
-- Only our verified craft-plan generators support pending whole-plan removal.
local addCraftStep=function() error('a cancelled recipe generator must never expand') end
PZSurvivorToolkit.CraftChainRecipes={addStep=addCraftStep}
local function craftPlaceholder()
    local action=ISQueueActionsAction:new(p,addCraftStep)
    action.toolkitCraftPlanCancellation=true
    return action
end
b=pendingGroup(craftPlaceholder(),craftPlaceholder());d=book(p);ISTimedActionQueue.add(d)
assert(api.cancelOperation(q,b) and #q.queue==2 and q.queue[2]==d)
b=pendingGroup(craftPlaceholder(),craftPlaceholder());c=q.queue[3]
c.addActionsFunction=function() error('substituted generator must never execute') end
assert(api.cancelOperationReason(q,b)=='operation_dependent' and not api.cancelOperation(q,b) and #q.queue==3)
c.addActionsFunction=addCraftStep;c.toolkitCraftPlanCancellation=nil
assert(api.cancelOperationReason(q,b)=='operation_dependent', 'the callback alone does not approve arbitrary native generators')
c.toolkitCraftPlanCancellation=true;c.addActionsFunction=nil;PZSurvivorToolkit.CraftChainRecipes.addStep=nil
assert(api.cancelOperationReason(q,b)=='operation_dependent', 'missing callbacks cannot match a missing provider')
PZSurvivorToolkit.CraftChainRecipes.addStep=addCraftStep
print('Whole-operation cancellation: preparation/returns, linked/mixed groups, active tails, callbacks, external targets and stale snapshots passed.')
-- Pending operations retain all native identities, including pickup/read/return and callbacks.
p = player(); a,b,c = book(p),book(p),book(p)
q = ISTimedActionQueue.add(a); ISTimedActionQueue.add(b); ISTimedActionQueue.add(c); frame(p)
local originalCurrent, nativeQueue = a.action, q.queue
b.forceCancel = function() error('reorder must not cancel') end
assert(not api.move(q,c,b), 'a replaced lifecycle cannot inherit native reorder permission')
b.forceCancel = nil
assert(api.move(q,c,b) and q.queue == nativeQueue and q.queue[2] == c and q.queue[3] == b)
assert(q.current == a and a.action == originalCurrent and not b.action and not c.action)
assert(api.move(q,c,b,true) and q.queue[2] == b and q.queue[3] == c)
assert(not api.move(q,a,c), 'active reading cannot cross another copy with shared native book progress')
local pickup, read, restore = leaf(p,'pickup'),book(p),leaf(p,'return')
pickup.Type,restore.Type='ISInventoryTransferAction','ISInventoryTransferAction'
pickup.item,restore.item=read.item,read.item
operations.run(function()
    ISTimedActionQueue.add(pickup);ISTimedActionQueue.add(read);ISTimedActionQueue.add(restore)
end)
assert(api.move(q,read,b) and q.queue[2]==pickup and q.queue[3]==read and q.queue[4]==restore)
assert(api.move(q,b,read) and q.queue[2]==b and q.queue[3]==pickup, 'target inside group resolves to whole operation')
assert(api.move(q,read,c,true) and q.queue[4]==pickup and q.queue[6]==restore)
local stale=book(p); assert(not api.move(q,b,stale) and not api.move(q,stale,b))
local linkedBook=book(p); ISTimedActionQueue.addAfter(b,linkedBook)
assert(api.move(q,linkedBook,restore,true) and q.queue[6]==b and q.queue[7]==linkedBook, 'addAfter steps move together')
local reused=book(p);reused.item=read.item;ISTimedActionQueue.add(reused)
assert(api.moveReason(q,reused,read)=='move_shared_item','shared-item operation order remains protected')
local callbackMove=leaf(p,'callback');callbackMove.onCompleteFunc=function() error('move must not invoke callbacks') end
ISTimedActionQueue.add(callbackMove);assert(not api.move(q,callbackMove,pickup), 'unknown callbacks are barriers')
local deferred=leaf(p,'deferred');deferred.Type='ISQueueActionsAction'
ISTimedActionQueue.add(deferred);assert(not api.move(q,deferred,callbackMove))
assert(not api.move(q,callbackMove,deferred), 'unowned generators cannot inherit permission from a Type string')
for _,kind in ipairs({'fuel','wreck'}) do
    deferred.toolkitWorldOperation=kind
    assert(api.moveReason(q,deferred,callbackMove)=='move_dependent', 'future vehicle inputs prevent moving its command')
    assert(api.moveReason(q,callbackMove,deferred,true)=='move_dependent', 'other work cannot cross unresolved vehicle inputs')
end
-- Interrupt a read only after native stop/removal; a fresh native read preserves saved pages.
p=player();a,b=book(p),book(p)
q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b);frame(p)
assert(api.moveReason(q,b,a)=='move_shared_book', 'different copies share native reading progress')
p=player();a,b,c=book(p),leaf(p,'walk'),leaf(p,'tv')
q=ISTimedActionQueue.add(a)
operations.run(function() ISTimedActionQueue.add(b);ISTimedActionQueue.add(c) end)
frame(p);p.pages=37
assert(api.move(q,c,a) and q.current==a and q.queue[2]==b and q.queue[3]==c)
q:tick();assert(#q.queue==3 and q.current==a, 'no premature read reconstruction')
assert(not api.move(q,c,c), 'in-flight stop blocks edits')
frame(p)
local resumed=q.queue[3]
assert(q.current==b and resumed~=a and resumed.item==a.item and resumed.Type=='ISReadABook')
assert(resumed.startPage==37 and resumed.pageTimer==0 and not resumed.action and not q.toolkitResume)
b.action.done=true;frame(p);c.action.done=true;frame(p)
assert(q.current==resumed and not p.actions[a.action] and p.actions[resumed.action])
-- A natural finish or external stop wins over a requested read resumption.
for _, mode in ipairs({'finish','clear','move','dead','respawn','dropped'}) do
    p=player();a,b=book(p),leaf(p,mode);q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b);frame(p)
    assert(api.move(q,b,a))
    if mode=='finish' then a.action.completing=true
    elseif mode=='clear' then ISTimedActionQueue.clear(p)
    elseif mode=='move' then p.moving=true
    elseif mode=='dead' then p.dead=true
    elseif mode=='respawn' then activePlayer=player()
    else p.actions={} end
    frame(p)
    assert(not q.toolkitResume and not q.toolkitCancel)
    assert(#q.queue==(mode=='finish' and 1 or 0), mode..' reconstructed a read')
end
print('Native reorder: whole operations, linked steps, shared items, preemption, fresh read and stop races passed.')
-- A finishing read wins the native completion race; never complete it twice.
p = player(); a,b = book(p),leaf(p,'finish-race'); q = ISTimedActionQueue.add(a); ISTimedActionQueue.add(b)
assert(api.cancelReason(q,a) == 'starting'); frame(p)
a.action.done = true; assert(api.cancelReason(q,a) == 'starting'); a.action.done = false
assert(api.cancel(q,a)); a.action.completing = true; frame(p)
assert(q.current == b and #q.queue == 1 and not q.toolkitCancel)
-- Disable-after-click still drains an already accepted stop; no orphaned tail.
p = player(); a,b = book(p),leaf(p,'disabled'); q = ISTimedActionQueue.add(a); ISTimedActionQueue.add(b); frame(p)
assert(api.cancel(q,a)); enabled = false; frame(p); assert(q.current == b)
assert(not api.cancel(q,b)); enabled = true
-- External clear, movement, death/respawn and dropped Java stack cannot resurrect actions.
for _, mode in ipairs({'clear','move','dead','respawn','dropped'}) do
    p = player(); a,b = book(p),leaf(p,mode); q = ISTimedActionQueue.add(a); ISTimedActionQueue.add(b); frame(p)
    assert(api.cancel(q,a))
    if mode == 'clear' then ISTimedActionQueue.clear(p)
    elseif mode == 'move' then p.moving = true
    elseif mode == 'dead' then p.dead = true
    elseif mode == 'respawn' then activePlayer = player()
    else p.actions = {} end
    frame(p)
    assert(#q.queue == 0 and not q.toolkitCancel, mode .. ' retained/resurrected a tail')
end
-- Native invalid isValidStart on the successor retains the game's reset semantics.
p = player(); a,b = book(p),leaf(p,'missing-target'); b.isValidStart = function() return false end
q = ISTimedActionQueue.add(a); ISTimedActionQueue.add(b); frame(p); assert(api.cancel(q,a)); frame(p)
assert(#q.queue == 0 and q.current == nil, 'vanished successor must not be started')
assert(api.label(book(p)):find('Book',1,true))
print('Native queue cancellation: middle/current, 21 rows, callbacks, dependencies, completion race, lifecycle, invalid tail passed.')
-- Fire cleanup runs before native completion starts the remaining return/tail.
do
    local previous=PZSurvivorToolkit.ActionQueueFire
    for _, setting in ipairs({true,false}) do
        enabled=setting;p=player();a,b,c=book(p),book(p),book(p)
        q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b);ISTimedActionQueue.add(c);frame(p)
        local calls=0
        PZSurvivorToolkit.ActionQueueFire={skipUnavailableReturns=function(queue,action)
            calls=calls+1;assert(queue==q and action==a and q.current==a and q.queue[1]==a and q.queue[2]==b)
            table.remove(q.queue,2)
        end}
        a.action.done=true;frame(p)
        assert(calls==(setting and 1 or 0) and q.current==(setting and c or b))
    end
    enabled=true;PZSurvivorToolkit.ActionQueueFire=previous
end
-- Family-owned invalidation drops only the failed operation and lets the native stop finish first.
for _, module in ipairs({'ActionQueueGenerators', 'ActionQueueFire'}) do
    local previous = PZSurvivorToolkit[module]
    for _, scenario in ipairs({{true, true}, {false, true}, {true, false}}) do
        local allowed = scenario[1]
        enabled = scenario[2]
        p = player(); a,b,c = book(p),book(p),book(p)
        operations.run(function() q=ISTimedActionQueue.add(a); ISTimedActionQueue.add(b) end)
        ISTimedActionQueue.add(c); frame(p)
        PZSurvivorToolkit[module] = {canSkip = function(action) return allowed and action == a end,
            supports = function() return false end}
        a:forceStop(); frame(p)
        assert(a.toolkitQueueOperation.toolkitCancelled)
        assert(not p.actions[a.action] and not q.toolkitGroupCancel)
        if allowed and enabled then assert(q.current == c and #q.queue == 1 and not c.toolkitQueueOperation.toolkitCancelled)
        else assert(q.current == nil and #q.queue == 0) end
    end
    enabled = true
    PZSurvivorToolkit[module] = previous
end

-- Lost pre-start manual craft work is removed before native start can reset its independent tail.
do
    local previous=PZSurvivorToolkit.ActionQueueCraft
    for _,scenario in ipairs({{true,true},{false,true},{true,false}}) do
        local missing=scenario[1];enabled=scenario[2]
        p=player();a,b,c=book(p),book(p),leaf(p,'independent craft tail')
        operations.run(function() q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b) end)
        ISTimedActionQueue.add(c);frame(p)
        PZSurvivorToolkit.ActionQueueCraft={supports=function() return false end,collectItems=function() end,
            canSkip=function(action) return missing and action==b end}
        a.action.done=true;frame(p)
        local skipped=missing and enabled
        assert(q.current==(skipped and c or b) and (not enabled or not c.toolkitQueueOperation.toolkitCancelled))
        assert((b.action==nil)==skipped,'skipped manual craft never enters native start')
        assert((a.toolkitQueueOperation.toolkitCancelled==true)==(skipped or not enabled))
    end
    enabled=true;PZSurvivorToolkit.ActionQueueCraft=previous
end

-- The view keeps real action identities across refreshes, hide/show and player replacement.
local ui, refresh, playerCount = {}, nil, 1
local widget = {derive = derive}
function widget:new(x,y,w,h)
    return setmetatable({x=x,y=y,width=w,height=h,items={},selected=-1,scroll=0}, {__index=self})
end
function widget:initialise() if self.createChildren then self:createChildren() end end
function widget:instantiate() end
function widget:titleBarHeight() return 20 end
function widget:addChild(child) child.parent=self end
function widget:addToUIManager() ui[#ui+1]=self end
function widget:removeFromUIManager() self.removed=true end
function widget:setVisible(v) self.visible=v end
function widget:setEnable(v) self.enabled=v end
function widget:setTooltip(v) self.tooltip=v end
function widget:update() end
function widget:onResize() end
function widget:setWidth(v) self.width=v end
function widget:setHeight(v) self.height=v end
function widget:setX(v) self.x=v end
function widget:setY(v) self.y=v end
function widget:getX() return self.x end
function widget:getY() return self.y end
function widget:getYScroll() return self.scroll end
function widget:setYScroll(v) self.scroll=v end
function widget:setScrollHeight(v) self.scrollHeight=v end
function widget:clear() self.items={} end
function widget:isMouseOverScrollBar() return self.overScrollbar==true end
function widget:getMouseX() return self.mouseX or 0 end
function widget:getMouseY() return self.mouseY or 0 end
function widget:drawRect(...) self.drawnRects=self.drawnRects or {};self.drawnRects[#self.drawnRects+1]={...} end
function widget:drawText(text) self.drawnTexts=self.drawnTexts or {};self.drawnTexts[#self.drawnTexts+1]=text end
function widget:drawTextRight(text,x) self:drawText(text);self.rightText={text=text,x=x} end
function widget:drawTextureScaledAspect(texture)
    assert(not self.clearedClip, 'text clipping must restore the parent stencil before drawing controls')
    assert(texture);self.lastTexture=texture;self.drawnTextures=self.drawnTextures or {};self.drawnTextures[#self.drawnTextures+1]=texture
end
function widget:setStencilRect(x,y,width,height)
    assert(not self.clearedClip, 'nested clipping must restore the previous stencil before clipping again')
    self.clips=self.clips or {};self.clips[#self.clips+1]={x=x,y=y,width=width,height=height}
end
function widget:clearStencilRect() self.clearedClip=self.clips[#self.clips] end
function widget:repaintStencilRect(x,y,width,height)
    local clip=assert(self.clearedClip)
    assert(clip.x==x and clip.y==y and clip.width==width and clip.height==height,
        'nested text masks must repaint exactly the cleared rectangle')
    self.clearedClip=nil
end
function widget:addItem(text, item) self.items[#self.items+1]={item=item,index=#self.items+1,height=self.itemheight} end
ISCollapsableWindow = widget:derive('ISCollapsableWindow')
function ISCollapsableWindow:createChildren() self.closeButton=widget:new(); self.closeButtonTexture="close-icon" end
UIFont = {Small=1}
getTextManager = function() return {getFontHeight=function() return 14 end,
    MeasureStringX=function(_,font,text) return #text end} end
-- Use native variable-height row geometry; Java rendering remains a fixture double.
ISPanelJoypad = widget
load('client/ISUI/ISScrollingListBox.lua')
widget.rowAt,widget.topOfItem=ISScrollingListBox.rowAt,ISScrollingListBox.topOfItem
ISScrollingListBox = widget:derive('ISScrollingListBox')
function ISScrollingListBox:onMouseDown(x,y) self.selected=self:rowAt(x,y) end
function ISScrollingListBox:onMouseUp() end
function ISScrollingListBox:onMouseUpOutside() end
function ISScrollingListBox:onMouseMove() self.mouseoverselected=self:rowAt(self:getMouseX(),self:getMouseY()) end
getTexture=function(path) return path end
getText=function(key,...) local args={...};for i,v in ipairs(args) do args[i]=tostring(v) end;return key .. (#args>0 and '('..table.concat(args,',')..')' or '') end
getNumActivePlayers = function() return playerCount end
getPlayerScreenLeft = function() return 0 end
getPlayerScreenTop = function() return 0 end
getPlayerScreenHeight = function() return 720 end
getPlayerScreenWidth = function() return 1280 end
Events.OnTickEvenPaused = {Add=function(fn) refresh=fn end}
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueBatch.lua'))()
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueuePanel.lua'))()
p = player(); a,b,c = book(p),book(p),book(p)
q = ISTimedActionQueue.add(a); ISTimedActionQueue.add(b); ISTimedActionQueue.add(c)
refresh(); local panel=ui[#ui]; panel:update()
assert(panel.visible and #panel.list.items==3 and not panel.closeButton.visible)
assert(panel:getX()==840 and panel:getY()==420, 'first queue window retains its default position')
assert(panel.list.doRepaintStencil, 'native list viewport must restore its enclosing window stencil')
local list=panel.list
local function click(n)
    local x,y=list:cancelX()+12,list:topOfItem(n)+list.items[n].height/2
    list:onMouseDown(x,y);list:onMouseUp(x,y);panel:update()
end
local function drag(from,to,after)
    list:onMouseDown(30,list:topOfItem(from)+list.items[from].height/2)
    list.mouseX,list.mouseY=30,list:topOfItem(to)+(after and list.items[to].height-2 or 2)
    list:onMouseMove(0,1);list:onMouseUp(list.mouseX,list.mouseY);panel:update()
end
assert(PZSurvivorToolkit.ActionQueuePanel.icon(a)=='book-icon')
assert(PZSurvivorToolkit.ActionQueuePanel.icon({craftRecipe={class='CraftRecipe',getIconTexture=function() return 'recipe-icon' end}})=='recipe-icon')
assert(PZSurvivorToolkit.ActionQueuePanel.icon({Type='ISWalkToTimedAction'}):find('Walking',1,true))
assert(PZSurvivorToolkit.ActionQueuePanel.icon({}):find('Icon_Tools',1,true))
assert(PZSurvivorToolkit.ActionQueuePanel.icon({toolkitWorldOperation='fuel',toolkitFuelTake=true}):find('gas_siphon',1,true))
assert(PZSurvivorToolkit.ActionQueuePanel.icon({toolkitWorldOperation='fuel',toolkitFuelTake=false}):find('gas_refuel',1,true))
list.doDrawItem(list,0,list.items[1],false); assert(list.items[1].tooltip)
list.selected=3; click(2) -- cancel directly, without selecting the row
assert(#list.items==2 and list.items[2].item==c and list.selected==2)
assert(q.current==a and #q.queue==2)
local d=book(p); ISTimedActionQueue.add(d);panel:update()
drag(3,2,false); assert(q.queue[2]==d and q.queue[3]==c and list.items[list.selected].item==d)
drag(2,3,true); assert(q.queue[2]==c and q.queue[3]==d)
drag(3,1,false); assert(q.queue[1]==a and q.queue[3]==d, 'blocked drop preserves order')
list:onMouseDown(30,list:topOfItem(3)+16);list:onMouseUpOutside(-10,-10)
assert(not list.dragAction and q.queue[3]==d)
list:onMouseDown(list:cancelX()+12,list:topOfItem(2)+16)
assert(api.cancel(q,c));panel:update();list:onMouseUp(list:cancelX()+12,list:topOfItem(2)+16)
assert(q.queue[2]==d, 'queue refresh between press/release must not cancel replacement')
list.overScrollbar=true;click(2);assert(q.queue[2]==d);list.overScrollbar=false
click(1);assert(q.current==a and #q.queue==2, 'starting read is protected even on direct click')
frame(p);click(1);assert(q.toolkitCancel==a);frame(p);panel:update()
assert(q.current==d and #q.queue==1, 'one-click current read cancellation preserves tail')
-- Headers count the current native queue, preserve identities, and never cancel a hidden first step.
p = player();a,b,c,d = book(p),book(p),book(p),book(p)
q = ISTimedActionQueue.add(a)
operations.run(function() ISTimedActionQueue.add(b);ISTimedActionQueue.add(c) end)
ISTimedActionQueue.add(d)
refresh();panel=ui[#ui];panel:update();list=panel.list
local token=b.toolkitQueueOperation
assert(#list.items==3 and list.items[2].header and list.items[2].item==b and list.items[2].last==3)
assert(list.items[2].task=='ContextMenu_Read', 'heading remains separate from the first native action identity')
assert(list.scrollHeight==list.itemheight*3+16, 'native scroll extent includes the taller operation header before restoring the scroll offset')
list.drawnTextures={};list.doDrawItem(list,list:topOfItem(2),list.items[2],false)
assert(list.drawnTextures[#list.drawnTextures]=='close-icon', 'operation headers expose whole-operation cancellation')
assert(list.items[2].tooltip:find('queue_remaining(2)',1,true) and list.items[2].tooltip:find('queue_group(2)',1,true))
local function dropLine(target,after,expected)
    list.dragAction,list.dragging,list.dropTarget,list.dropAfter=d,true,list.items[target].item,after
    list.drawnRects={}
    for index, row in ipairs(list.items) do list.doDrawItem(list,list:topOfItem(index),row,false) end
    local lines={}
    for _, rect in ipairs(list.drawnRects) do if rect[4]==2 then lines[#lines+1]=rect end end
    assert(#lines==1 and lines[1][2]==list:topOfItem(expected)+(after and list.items[expected].height-2 or 0),
        'drop line must follow the visible whole-operation boundary')
    list:clearGesture()
end
dropLine(2,true,2)
local function toggle(n)
    local y=list:topOfItem(n)+16
    list:onMouseDown(10,y);assert(not list.dragAction);list:onMouseUp(10,y);panel:update()
end
toggle(2)
assert(#list.items==5 and list.items[3].item==b and list.items[4].item==c and panel.expanded[token])
dropLine(4,false,2);dropLine(3,true,4)
toggle(2);assert(#list.items==3 and not panel.expanded[token])
drag(2,3,true)
assert(q.queue[2]==d and q.queue[3]==b and q.queue[4]==c, 'collapsed header drag moves the whole operation')
toggle(3);drag(5,2,false)
assert(q.queue[2]==b and q.queue[3]==c and q.queue[4]==d, 'expanded child drag moves the whole operation')
assert(panel.expanded[token] and list.items[4].item==c)
click(4)
assert(q.queue[2]==b and q.queue[3]==d and #list.items==3, 'expanded cross cancels only its actual step')
-- A dynamic native addAfter expands the same token, retaining the user's expanded state.
local generated=book(p)
ISTimedActionQueue.addAfter(b,generated);panel:update()
assert(list.items[2].header and #list.items==5 and list.items[3].item==b and list.items[4].item==generated)
-- Queue mutation between press/release cancels the gesture, including a header toggle.
list:onMouseDown(10,list:topOfItem(2)+16)
q:removeFromQueue(generated);panel:update();list:onMouseUp(10,list:topOfItem(2)+16)
assert(not list.pressedToggle and not list.items[2].header and panel.expanded[token])
-- Native transfers wipe their action table. Stale tokens cannot preserve a phantom group.
table.wipe(b);panel:update()
assert(not panel.expanded[token] and not list.items[2].operation and not list.items[2].header)
q:removeFromQueue(b);panel:update()
-- A heading describes the remaining work, without keeping removed actions or mistaking preparation for the task.
local taskTitle=PZSurvivorToolkit.ActionQueuePanel.taskTitle
local walk={Type='ISWalkToTimedAction'}
local equip={Type='ISEquipWeaponAction',twoHands=true}
local unload={Type='ISUnloadBulletsFromFirearm'}
local transfer={Type='ISInventoryTransferAction'}
local taskQueue={queue={walk,equip,unload,equip,unload,transfer}}
assert(taskTitle(taskQueue,1,6)=='IGUI_JobType_UnloadBulletsFromFirearm', 'preparation and returns must not name a task')
assert(taskTitle(taskQueue,4,6)=='IGUI_JobType_UnloadBulletsFromFirearm', 'a partly completed batch retains its remaining task')
taskQueue.queue[5]=transfer
assert(taskTitle(taskQueue,4,6)=='UI_PZSurvivorToolkit_queue_action_transfer', 'removed final operation must not leave a stale task heading')
taskQueue.queue={equip,{Type='ISReadABook'},unload,transfer}
assert(taskTitle(taskQueue,1,4)=='UI_PZSurvivorToolkit_queue_mixed', 'different remaining tasks must not impersonate the first task')
assert(taskTitle({queue={walk,equip}},1,2)=='UI_PZSurvivorToolkit_queue_mixed')
local unknown={Type='ModWork'}
assert(taskTitle({queue={walk,unknown,transfer}},1,3)=='UI_PZSurvivorToolkit_queue_action_unknown(ModWork)')
assert(taskTitle({queue={unknown,{Type='OtherModWork'}}},1,2)=='UI_PZSurvivorToolkit_queue_mixed')
local function recipe(name) return {class='CraftRecipe',getName=function() return name end,getTranslationName=function() return 'Recipe '..name end} end
assert(taskTitle({queue={equip,{craftRecipe=recipe('A')},transfer}},1,3)=='Recipe A')
assert(taskTitle({queue={{craftRecipe=recipe('A')},{craftRecipe=recipe('B')}}},1,2)=='UI_PZSurvivorToolkit_queue_mixed')
-- Batch counts describe completed crafts/actions, never outputs or native preparation steps.
p=player();a,b,c,d=book(p),book(p),book(p),book(p)
operations.run(function() q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b);ISTimedActionQueue.add(c) end)
ISTimedActionQueue.add(d)
local batchToken=a.toolkitQueueOperation
batchToken.toolkitBatch={total=3,completed=0,unit='craft'}
refresh();panel=ui[#ui];panel:update();list=panel.list
assert(#list.items==2 and panel.title=='UI_PZSurvivorToolkit_queue_title(2)')
list.doDrawItem(list,0,list.items[1],false)
assert(list.rightText.text=='UI_PZSurvivorToolkit_queue_craft_progress(0,3)')
assert(not list.items[1].tooltip:find('queue_steps',1,true) and not list.items[1].tooltip:find('queue_group',1,true))
local batchRow=list.items[1]
list:onMouseDown(10,16)
batchToken.toolkitBatch.completed=1;panel:update()
assert(list.items[1]==batchRow and list.pressedToggle==batchToken, 'progress updates do not rebuild or discard a gesture')
list.doDrawItem(list,0,list.items[1],false)
assert(list.rightText.text=='UI_PZSurvivorToolkit_queue_craft_progress(1,3)')
list:onMouseUp(10,16);panel:update()
assert(panel.expanded[batchToken] and #list.items==5 and panel.title=='UI_PZSurvivorToolkit_queue_title(2)')
q:removeFromQueue(a);q:removeFromQueue(b);batchToken.toolkitBatch.completed=2;panel:update()
assert(list.items[1].header and list.items[1].item==c and list.items[2].item==c,
    'a final native child keeps its batch heading and expansion')
list.doDrawItem(list,0,list.items[1],false)
assert(list.rightText.text=='UI_PZSurvivorToolkit_queue_craft_progress(2,3)')
batchToken.toolkitBatch.unit='action';panel:update();list.doDrawItem(list,0,list.items[1],false)
assert(list.rightText.text=='UI_PZSurvivorToolkit_queue_action_progress(2,3)')
batchToken.toolkitBatch.total=nil;batchToken.toolkitBatch.lazy=true
panel:update();list.doDrawItem(list,0,list.items[1],false)
assert(list.rightText.text=='UI_PZSurvivorToolkit_queue_action_completed(2)', 'unbounded work must not invent a total')
-- Lazy Craft All keeps one header while native continuations replace its only child.
p=player();a=book(p);q=ISTimedActionQueue.add(a)
batchToken=a.toolkitQueueOperation
batchToken.toolkitBatch={completed=0,unit='craft',lazy=true}
refresh();panel=ui[#ui];panel:update();list=panel.list
assert(#list.items==1 and list.items[1].header)
frame(p);toggle(1);b=book(p);ISTimedActionQueue.addAfter(a,b);a.action.done=true;frame(p)
batchToken.toolkitBatch.completed=1;panel:update()
assert(#list.items==2 and list.items[1].header and list.items[2].item==b and panel.expanded[batchToken])
list.doDrawItem(list,0,list.items[1],false)
assert(list.rightText.text=='UI_PZSurvivorToolkit_queue_craft_completed(1)')
local unrelated=book(p);ISTimedActionQueue.add(unrelated);panel:update()
frame(p);click(1);assert(q.toolkitCancel==b);frame(p);panel:update()
assert(#q.queue==1 and q.queue[1]==unrelated, 'one header cross cancels the lazy task and retains unrelated work')
-- A plain one-off craft does not need a batch header.
unrelated.toolkitQueueOperation.toolkitBatch={total=1,completed=0,unit='craft'}
panel:update();assert(#list.items==1 and not list.items[1].header)
print('Queue batch view: dynamic logical counters, unknown totals, singleton continuation headers, expansion and cancellation passed.')
-- Active headers show the actual current native step and its progress; completed/cancelled steps leave only a remaining count.
p=player();a,b,c=book(p),book(p),book(p)
operations.run(function() q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b);ISTimedActionQueue.add(c) end)
refresh();panel=ui[#ui];panel:update();list=panel.list
frame(p);a.action.progress=.42
list.drawnTexts={};list.doDrawItem(list,0,list.items[1],false)
assert(list.items[1].header and list.items[1].tooltip:find('[42%]',1,true)
    and list.items[1].tooltip:find('queue_remaining(3)',1,true) and list.lastTexture=='close-icon')
assert(table.concat(list.drawnTexts,'\n'):find('ContextMenu_Read',1,true))
assert(list.rightText.text=='UI_PZSurvivorToolkit_queue_steps(3)')
local title=list.items[1].task
list.items[1].task=string.rep('Long recipe ',50);list.clips={}
list.doDrawItem(list,0,list.items[1],false)
assert(list.clips[1].x+list.clips[1].width <= list.rightText.x-#list.rightText.text-8,
    'a long title must not overlap the separately visible step count')
list.items[1].task=title
assert(not api.cancelOperationReason(q,a), 'current collapsed header offers whole-operation cancellation')
a.action.done=true;frame(p);panel:update()
assert(list.items[1].header and list.items[1].item==b and list.items[1].last==2)
frame(p);b.action.progress=.15
list.doDrawItem(list,0,list.items[1],false)
assert(list.items[1].tooltip:find('[15%]',1,true) and list.items[1].tooltip:find('queue_remaining(2)',1,true))
toggle(1);click(2);assert(q.toolkitCancel==b)
frame(p);panel:update()
assert(#list.items==1 and list.items[1].item==c and not list.items[1].header, 'a cancelled/completed batch tail becomes a normal single row')
local nextBook=book(p);ISTimedActionQueue.add(nextBook);panel:update();d=nextBook
-- getMouseY/onMouseDown use content-space coordinates, including the scroll offset.
list.scroll=-32;list:onMouseDown(30,40)
assert(list.dragAction==d, 'visible scrolled content-space row must be hit')
list:clearGesture()
list.scroll=-16;list:onMouseDown(30,8);assert(not list.dragAction, 'clipped rows cannot be hit')
list.scroll=0;list:onMouseDown(30,16)
panel:setX(125);panel:setY(85)
enabled=false; refresh(); assert(not panel.visible and #panel.list.items==0, 'hidden view must release action snapshots')
assert(not hasEntry(panel.expanded) and not list.dragAction and not list.pressedToggle)
enabled=true; refresh(); assert(panel.visible and ui[#ui]==panel)
assert(panel:getX()==125 and panel:getY()==85, 'feature hide/show retains the moved position')
p.dead=true; refresh(); assert(not panel.visible)
p=player(); ISTimedActionQueue.add(book(p)); refresh()
assert(panel.removed and #panel.list.items==0 and not hasEntry(panel.expanded) and ui[#ui]~=panel and ui[#ui].queue.character==p)
local replaced = ui[#ui]
assert(replaced:getX()==125 and replaced:getY()==85, 'player replacement retains the window position')
replaced:setX(0);replaced:setY(140)
ISTimedActionQueue:new(p); ISTimedActionQueue.add(book(p)); refresh()
assert(replaced.removed and ui[#ui].queue == ISTimedActionQueue.queues[p])
assert(ui[#ui]:getX()==0 and ui[#ui]:getY()==140, 'queue replacement retains the latest position, including zero')
ui[#ui]:update(); ISTimedActionQueue.clear(p); refresh()
assert(not ui[#ui].visible and #ui[#ui].list.items == 0, 'completed/stopped queue must release rows')
local emptyPanel=ui[#ui]
ISTimedActionQueue.queues[p]=nil;refresh()
assert(emptyPanel.removed and #emptyPanel.list.items==0, 'a missing queue still removes its stale window')
ISTimedActionQueue.add(book(p));refresh()
assert(ui[#ui]~=emptyPanel and ui[#ui]:getX()==0 and ui[#ui]:getY()==140,
    'a new queue after an empty/missing queue restores the moved position')
playerCount=0; refresh(); assert(ui[#ui].removed)
-- Each local player keeps an independent position, including removal and rejoining.
do
    local first=player()
    local second=player()
    local specificPlayer=getSpecificPlayer
    getSpecificPlayer=function(index) return index==0 and first or second end
    playerCount=2
    ISTimedActionQueue.add(book(first));ISTimedActionQueue.add(book(second));refresh()
    local firstPanel,secondPanel=ui[#ui-1],ui[#ui]
    assert(firstPanel:getX()==0 and firstPanel:getY()==140, 'removed player slot retains its position')
    assert(secondPanel:getX()==840 and secondPanel:getY()==420, 'another player starts at the default position')
    firstPanel:setX(210);firstPanel:setY(90)
    secondPanel:setX(680);secondPanel:setY(250)
    ISTimedActionQueue:new(first);ISTimedActionQueue.add(book(first))
    ISTimedActionQueue:new(second);ISTimedActionQueue.add(book(second));refresh()
    assert(firstPanel.removed and secondPanel.removed)
    assert(ui[#ui-1]:getX()==210 and ui[#ui-1]:getY()==90)
    assert(ui[#ui]:getX()==680 and ui[#ui]:getY()==250, 'queue replacements do not share player positions')
    playerCount=0;refresh()
    getSpecificPlayer=specificPlayer
end
print('Queue window: moved positions survive hide/show, native queue replacement, missing queues and player-slot removal independently.')
-- The header cross removes every waiting step; child crosses retain their existing individual semantics.
playerCount=1;p=player();a,d=book(p),book(p);q=ISTimedActionQueue.add(a)
pickup,read,restore=preparation(p,'ISInventoryTransferAction'),book(p),preparation(p,'ISInventoryTransferAction')
pickup.item,restore.item=read.item,read.item
operations.run(function() ISTimedActionQueue.add(pickup);ISTimedActionQueue.add(read);ISTimedActionQueue.add(restore) end)
ISTimedActionQueue.add(d);refresh();panel=ui[#ui];panel:update();list=panel.list
list.mouseoverselected,list.mouseX=2,list:cancelX()+12
list.doDrawItem(list,list:topOfItem(2),list.items[2],false)
assert(list.items[2].tooltip:find('queue_cancel_operation_tip',1,true), 'header tooltip describes the whole operation')
toggle(2);assert(#list.items==6 and api.cancelReason(q,pickup)=='dependent')
click(3);assert(#q.queue==5, 'protected pickup child cross cannot cancel preparation alone')
click(2);assert(#q.queue==2 and q.queue[1]==a and q.queue[2]==d and #list.items==2)
assert(not hasEntry(panel.expanded), 'removed operation must release its expansion token')
-- Group changes and callback changes after mouse-down must be checked again on mouse-up.
b,c=book(p),book(p);operations.run(function() ISTimedActionQueue.add(b);ISTimedActionQueue.add(c) end)
panel:update();local headerIndex=3
local x,y=list:cancelX()+12,list:topOfItem(headerIndex)+16
list:onMouseDown(x,y);assert(list.pressedOperation)
local inserted=book(p);ISTimedActionQueue.addAfter(b,inserted)
list:onMouseUp(x,y);assert(#q.queue==5, 'no refresh is needed to reject a changed operation snapshot')
panel:update();y=list:topOfItem(headerIndex)+16;list:onMouseDown(x,y)
c.onCancelFunc=function() error('changed callback must not run') end
list:onMouseUp(x,y);assert(#q.queue==5, 'a newly attached callback is revalidated at release')
c.onCancelFunc=nil;list:onMouseDown(x,y)
q:removeFromQueue(inserted);panel:update();list:onMouseUp(x,y)
assert(#q.queue==4 and not list.pressedOperation, 'refresh discards a removed-member header gesture')
list:onMouseDown(x,y);assert(list.pressedOperation)
panel:onResize();assert(not list.pressedOperation)
click(headerIndex);assert(#q.queue==2, 'current identities still cancel after a stale gesture is cleared')
-- A single verified recipe placeholder has an operation cross without exposing ordinary craft removal.
b=craftPlaceholder();ISTimedActionQueue.add(b);panel:update()
assert(not list.items[3].header and api.cancelReason(q,b)=='dependent')
list.mouseoverselected,list.mouseX=3,list:cancelX()+12
list.doDrawItem(list,list:topOfItem(3),list.items[3],false)
assert(list.items[3].tooltip:find('queue_cancel_operation_tip',1,true))
click(3);assert(#q.queue==2 and q.queue[2]==d)
b=craftPlaceholder();ISTimedActionQueue.add(b);panel:update()
x,y=list:cancelX()+12,list:topOfItem(3)+16;list:onMouseDown(x,y)
b.addActionsFunction=function() error('changed single generator must never run') end
list:onMouseUp(x,y);assert(#q.queue==3, 'single placeholder callback replacement prevents operation routing')
click(3);assert(#q.queue==3, 'an arbitrary native craft generator retains normal protection')
-- Remove the deliberately corrupted test operation before testing an independent UI gesture.
table.remove(q.queue,3)
local placeholderTail=book(p);ISTimedActionQueue.add(placeholderTail)
-- A verified single world placeholder routes through the same complete operation safety check.
b=ISQueueActionsAction:new(p,worldCallback);b.toolkitWorldDismantle=true
ISTimedActionQueue.add(b);panel:update();click(4)
assert(#q.queue==3 and q.queue[2]==d, 'single trusted world command cancels without expansion')
b=ISQueueActionsAction:new(p,worldCallback);b.toolkitWorldDismantle=true
ISTimedActionQueue.add(b);panel:update()
x,y=list:cancelX()+12,list:topOfItem(4)+16;list:onMouseDown(x,y)
b.addActionsFunction=function() error('changed world callback must never expand') end
list:onMouseUp(x,y);assert(#q.queue==4, 'release rechecks a world command callback')
print('Queue view: operation header/child crosses, callback and member revalidation, group drag, dynamic expansion, native scroll geometry and snapshot lifecycle passed.')
-- Audited world work uses the native build stop/transaction path and resumes after urgent work.
load('client/BuildingObjects/TimedActions/ISBuildAction.lua')
local oldWorld = PZSurvivorToolkit.ActionQueueWorld
local removedTransactions, resumedCalls, rebuilt = {}, 0, nil
local acknowledgementClock = 0
getTimestampMs = function() return acknowledgementClock end
removeAction = function(character, transaction, cancelled)
    removedTransactions[#removedTransactions+1] = {transaction, cancelled}
end
local completeBuild = function() end
local function build(character)
    local action = ISBaseTimedAction.new(ISBuildAction, character)
    action.maxTime, action.transactionId, action.trustedBuild = 1, 42, true
    action.onCompleteFunc = completeBuild
    action.item = {ghostSprite=true, onTimedActionStop=function(self) self.stopped=true end}
    action.start = function() end
    action.isValid = function() return true end
    action.perform = function(self) ISBaseTimedAction.perform(self) end
    return action
end
PZSurvivorToolkit.ActionQueueWorld = {
    canResume = function(action)
        if action.mpBuild then return action.ack and action.ack.state == "started", "move_world_transaction" end
        return action.trustedBuild and action.onCompleteFunc == completeBuild
    end,
    buildAcknowledgement = function(action) return action.mpBuild and action.ack end,
    buildState = function(action, ack) return action.ack == ack and ack.state end,
    resume = function(action, ack)
        if action.mpBuild then assert(ack == action.ack and ack.state == "canceled") end
        assert(not action.character.actions[action.action], 'new command must wait for native Java removal')
        resumedCalls = resumedCalls + 1
        return ISQueueActionsAction:new(action.character, function(character)
            rebuilt = build(character)
            ISTimedActionQueue.add(rebuilt)
        end)
    end,
}
p=player();a=build(p);q=ISTimedActionQueue.add(a);frame(p)
b,c=leaf(p,'urgent-world'),book(p);ISTimedActionQueue.add(b);ISTimedActionQueue.add(c)
assert(not api.cancelReason(q,a) and api.move(q,b,a))
assert(q.current==a and q.queue[2]==b and resumedCalls==0)
q:tick();assert(resumedCalls==0 and q.current==a)
frame(p)
assert(resumedCalls==1 and q.current==b and #q.queue==3)
assert(a.item.stopped and a.item.ghostSprite==nil)
assert(#removedTransactions==1 and removedTransactions[1][1]==42 and removedTransactions[1][2]==true)
local deferred=q.queue[2]
assert(deferred.Type=='ISQueueActionsAction' and deferred.toolkitQueueOperation==a.toolkitQueueOperation)
assert(not rebuilt and q.queue[3]==c, 'world preparation must happen after the urgent operation')
b.action.done=true;frame(p);frame(p)
assert(rebuilt and rebuilt~=a and q.current==rebuilt and q.queue[2]==c)
assert(rebuilt.toolkitQueueOperation==a.toolkitQueueOperation and rebuilt.transactionId==42)
assert(rebuilt.action~=a.action and rebuilt.item.ghostSprite, 'fresh native action does not reuse cleared stop state')
-- Multiplayer building cannot be replayed before authoritative cancellation is known.
p=player();a=build(p);a.mpBuild=true;q=ISTimedActionQueue.add(a);frame(p)
b=book(p);ISTimedActionQueue.add(b)
assert(api.moveReason(q,b,a)=="move_world_transaction" and not api.move(q,b,a))
assert(q.queue[1]==a and q.queue[2]==b and not q.toolkitCancel and not a.action.stopped)
refresh();panel=ui[#ui];panel:update();list=panel.list
list.dragAction,list.dragging,list.dropTarget,list.dropAfter=b,true,a,false
list.doDrawItem(list,0,list.items[1],false)
assert(list.items[1].tooltip:find("queue_move_world_transaction",1,true), "blocked drop must explain the actual target restriction")
list:clearGesture()
-- Matching terminal and Java removal may arrive in either order; completion never repeats world work.
for _, state in ipairs({'canceled', 'completed'}) do
    for _, first in ipairs({'terminal', 'removal'}) do
        p=player();a=build(p);a.mpBuild=true;a.ack={state='started'}
        q=ISTimedActionQueue.add(a);frame(p);b=book(p);c=leaf(p,'mp-tail')
        ISTimedActionQueue.add(b);ISTimedActionQueue.add(c)
        local before=resumedCalls
        assert(api.move(q,b,a) and q.toolkitOutcomeWait)
        if first=='terminal' then
            a.ack.state=state;q:tick()
            assert(q.current==a and resumedCalls==before, 'terminal must wait Java removal')
        else
            frame(p)
            assert(q.current==a and #q.queue==3 and resumedCalls==before, 'local stop must wait terminal')
            a.ack.state=state
        end
        frame(p)
        assert(q.current==b and not q.toolkitOutcomeWait and not q.toolkitCancel)
        if state=='canceled' then
            assert(resumedCalls==before+1 and q.queue[2].Type=='ISQueueActionsAction' and q.queue[3]==c)
        else
            assert(resumedCalls==before and q.queue[2]==c, 'server completion must never replay')
        end
        q:tick();assert(resumedCalls==before+(state=='canceled' and 1 or 0), 'duplicate ticks cannot resume twice')
    end
end
-- Native perform can happen after preemption but before stop/removal; hold its onCompleted callback.
p=player();a=build(p);a.mpBuild=true;a.ack={state='started'}
q=ISTimedActionQueue.add(a);frame(p);b=book(p);ISTimedActionQueue.add(b)
local before=resumedCalls
assert(api.move(q,b,a));a.ack.state='completed';a.action.completing=true
q:onCompleted(a)
assert(q.current==a and q.toolkitOutcomeWait.localCompleted, 'perform cannot start urgent work before Java removes current')
frame(p)
assert(q.current==b and resumedCalls==before and #q.queue==1)
-- Lost terminal, explicit clear, movement and death fail closed without replay or an indefinite wait.
for _, mode in ipairs({'timeout','clear','move','dead','respawn'}) do
    p=player();a=build(p);a.mpBuild=true;a.ack={state='started'}
    q=ISTimedActionQueue.add(a);frame(p);b=book(p);ISTimedActionQueue.add(b)
    before=resumedCalls;assert(api.move(q,b,a));frame(p)
    assert(q.current==a and q.toolkitOutcomeWait)
    if mode=='timeout' then acknowledgementClock=acknowledgementClock+30000
    elseif mode=='clear' then ISTimedActionQueue.clear(p)
    elseif mode=='move' then p.moving=true
    elseif mode=='dead' then p.dead=true
    elseif mode=='respawn' then activePlayer=player() end
    q:tick()
    assert(resumedCalls==before and not q.toolkitOutcomeWait and not q.toolkitCancel)
    if mode=='timeout' or mode=='clear' or mode=='move' then assert(#q.queue==0) end
end
-- Unknown callbacks and untracked build transactions retain native protection.
p=player();a=build(p);q=ISTimedActionQueue.add(a);frame(p);b=book(p);ISTimedActionQueue.add(b)
a.onCompleteFunc=function() error('unknown callback') end
assert(not api.move(q,b,a) and api.cancelReason(q,a)=='dependent')
a.onCompleteFunc=completeBuild;a.trustedBuild=nil
assert(not api.move(q,b,a) and api.cancelReason(q,a)=='dependent')
for _, mode in ipairs({'finish','clear','move','dead','respawn','dropped'}) do
    p=player();a=build(p);q=ISTimedActionQueue.add(a);frame(p)
    b=book(p);ISTimedActionQueue.add(b);local before=resumedCalls
    assert(api.move(q,b,a))
    if mode=='finish' then a.action.completing=true
    elseif mode=='clear' then ISTimedActionQueue.clear(p)
    elseif mode=='move' then p.moving=true
    elseif mode=='dead' then p.dead=true
    elseif mode=='respawn' then activePlayer=player()
    elseif mode=='dropped' then p.actions={} end
    frame(p)
    assert(resumedCalls==before and not q.toolkitCancel, 'world '..mode..' must not resurrect completed/aborted work')
end
PZSurvivorToolkit.ActionQueueWorld=oldWorld
-- Independent deferred targets retain selective cancellation with more world work behind them.
p=player();q=ISTimedActionQueue.add(book(p))
b=ISQueueActionsAction:new(p,worldCallback);b.toolkitWorldDismantle=true;b.toolkitWorldOperation='dismantle'
c=ISQueueActionsAction:new(p,worldCallback);c.toolkitWorldDismantle=true;c.toolkitWorldOperation='dismantle'
b.toolkitWorldTarget,c.toolkitWorldTarget={class='IsoObject'},{class='IsoObject'}
ISTimedActionQueue.add(b);ISTimedActionQueue.add(c)
assert(api.cancelOperation(q,b) and q.queue[2]==c, 'canceling the second door must preserve a third door command')
b=ISQueueActionsAction:new(p,worldCallback);b.toolkitWorldOperation='build'
ISTimedActionQueue.add(b);local another=ISQueueActionsAction:new(p,worldCallback);another.toolkitWorldOperation='build'
ISTimedActionQueue.add(another)
assert(api.cancelOperation(q,b) and q.queue[#q.queue]==another, 'independent waiting builds do not produce inventory inputs for later jobs')
print('World preemption: native build stop/transaction cleanup, lazy fresh preparation, unrelated tail, callback protection and stop races passed.')
-- Native MP scrap validity calls stop before reporting false when replication removes the target.
local priorWorld = PZSurvivorToolkit.ActionQueueWorld
PZSurvivorToolkit.ActionQueueWorld = {targetGone=function(action)
    return action.trackedScrap and not action:isValidObject()
end}
ISMoveableDefinitions={cheat=false}
isClient=function() return false end
local function disappearingScrap(character)
    local action=weld(character)
    action.trackedScrap=true
    action.object=action.moveProps.object
    action.square={getZ=function() return 0 end, getObjects=function()
        return {size=function() return action.gone and 0 or 1 end, get=function() return action.object end}
    end}
    action.isValid=ISMoveablesAction.isValid
    action.isAdjacentToAnySquare=function() return true end
    character.getSquare=function() return action.square end
    character.isMovablesCheat=function() return false end
    return action
end
p=player();a=disappearingScrap(p);b,c=book(p),leaf(p,'retained-after-replication')
q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b);ISTimedActionQueue.add(c);frame(p)
a.gone=true
assert(not a:isValid() and q.toolkitCancel==a and q.current==a and #q.queue==3)
assert(not a.moveProps.object.highlighted and p.stoppedSound==123)
a:stop();q:tick()
assert(q.current==a and q.queue[2]==b, 'duplicate native stop cannot start the next action before Java removal')
frame(p)
assert(q.current==b and q.queue[2]==c and not q.toolkitCancel and not q.toolkitResume)
assert(not p.actions[a.action] and p.actions[b.action], 'missing target is dropped without invoking scrap completion')
-- An object disappearing during preparation also skips its leaf before native start.
p=player();a=disappearingScrap(p);q=ISTimedActionQueue.add(a);b=book(p);ISTimedActionQueue.add(b)
a.gone=true;assert(not a:isValid() and q.toolkitCancel==a)
p.actions[a.action]=nil;q:tick();assert(q.current==b and not q.toolkitCancel)
for _,mode in ipairs({'moving','dead','disabled','callback','untracked','clear'}) do
    p=player();a=disappearingScrap(p);q=ISTimedActionQueue.add(a);b=book(p);ISTimedActionQueue.add(b);frame(p)
    a.gone=true
    if mode=='moving' then p.moving=true
    elseif mode=='dead' then p.dead=true
    elseif mode=='disabled' then enabled=false
    elseif mode=='callback' then a.onCompleteFunc=function() error('unknown callback invoked') end
    elseif mode=='untracked' then a.trackedScrap=nil
    elseif mode=='clear' then ISTimedActionQueue.clear(p) end
    if mode~='clear' then a:isValid() end
    p.actions[a.action]=nil;q:tick()
    assert(#q.queue==0 and not q.toolkitCancel, 'missing target '..mode..' must retain native abort behavior')
    enabled=true
end
PZSurvivorToolkit.ActionQueueWorld=priorWorld
print('Native missing scrap target: double-stop cleanup, delayed Java removal, retained tail and abort guards passed.')
-- VehicleRemove may precede Done; preserve only the owned native wreck's remaining work.
PZSurvivorToolkit.ActionQueueWorld={wreckTargetGone=function(action)
    return enabled and action.trackedWreck and action.vehicle:isRemovedFromWorld() and not action.onCompleteFunc
end}
local function disappearingWreck(character)
    local action=ISBaseTimedAction.new(ISRemoveBurntVehicle,character)
    action.trackedWreck,action.toolkitWorldOperation,action.maxTime,action.sound=true,'wreck',1,0
    action.vehicle={isRemovedFromWorld=function() return action.gone == true end}
    action.item={hasTag=function() return true end,getCurrentUses=function() return 10 end,setJobDelta=function() end}
    character.getPrimaryHandItem=function() return action.item end
    action.start=function() end
    action.complete=function() error('target removal must never replay wreck completion') end
    return action
end
p=player();a=disappearingWreck(p);q=ISTimedActionQueue.add(a);b,c=book(p),leaf(p,'after-wreck')
ISTimedActionQueue.add(b);ISTimedActionQueue.add(c);frame(p)
assert(api.cancelReason(q,a)=='dependent', 'removed-target recovery must not enable user cancellation')
a.gone=true;assert(not a:isValid());a:stop();a:stop();q:tick()
assert(q.current==a and q.toolkitCancel==a and q.queue[2]==b, 'duplicate stop waits for Java removal')
frame(p)
assert(q.current==b and q.queue[2]==c and not q.toolkitCancel and not p.actions[a.action])
for _,mode in ipairs({'moving','dead','disabled','callback','untracked','not-removed','clear'}) do
    p=player();a=disappearingWreck(p);q=ISTimedActionQueue.add(a);b=book(p);ISTimedActionQueue.add(b);frame(p)
    a.gone=mode~='not-removed'
    if mode=='moving' then p.moving=true
    elseif mode=='dead' then p.dead=true
    elseif mode=='disabled' then enabled=false
    elseif mode=='callback' then a.onCompleteFunc=function() error('unverified callback') end
    elseif mode=='untracked' then a.trackedWreck=nil
    elseif mode=='clear' then ISTimedActionQueue.clear(p) end
    if mode~='clear' then a:stop() end
    p.actions[a.action]=nil;q:tick()
    assert(#q.queue==0 and not q.toolkitCancel, 'wreck '..mode..' must keep native abort behavior')
    enabled=true
end
PZSurvivorToolkit.ActionQueueWorld=priorWorld
print('Native removed wreck: retained tail, delayed Java removal, duplicate stops and abort guards passed.')
-- Cancel an already-started group through its header, with native stop/removal before returns.
local function sourceContainer()
    return {isExistYet=function(self) return not self.gone end}
end
local function transfer(character, item, source, destination)
    local action = ISBaseTimedAction.new(ISInventoryTransferAction, character)
    action.item = item
    action.srcContainer, action.destContainer = source, destination
    action.transactionId = 0
    return action
end
ISInventoryTransferUtil = {newInventoryTransferAction=transfer}
local function borrowed(item, container)
    item.container=container
    item.getContainer=function(self) return self.container end
    item.getIsCraftingConsumed=function(self) return self.consumed==true end
    return item
end
-- Drag active shelf reading down once: preserve the intervening command order and return.
do
    local function scenario()
        local character=player()
        local read=book(character)
        local shelf=sourceContainer()
        borrowed(read.item,character.inventory)
        local returned=transfer(character,read.item,character.inventory,shelf)
        returned.allowMissingItems=true
        local queue
        operations.run(function() queue=ISTimedActionQueue.add(read);ISTimedActionQueue.add(returned) end)
        local power,insert,play=leaf(character,'power'),leaf(character,'insert'),leaf(character,'play')
        ISTimedActionQueue.add(power);ISTimedActionQueue.add(insert);ISTimedActionQueue.add(play)
        frame(character);character.pages=37
        return character,queue,read,returned,power,insert,play,shelf
    end
    local character,queue,read,returned,power,insert,play,shelf=scenario()
    refresh();panel=ui[#ui];panel:update();list=panel.list
    assert(list.items[1].header and not api.moveReason(queue,read),'active reading header must be draggable')
    drag(1,#list.items,true)
    assert(queue.current==read and queue.queue[2]==power and queue.queue[3]==insert
        and queue.queue[4]==play and queue.queue[5]==returned and queue.toolkitResume==play)
    assert(not api.move(queue,read,power),'stop in progress rejects a second edit')
    queue:tick();assert(queue.current==read and #queue.queue==5,'no construction before native removal')
    frame(character)
    local resumed=queue.queue[4]
    assert(queue.current==power and resumed~=read and resumed.item==read.item and resumed.startPage==37
        and resumed.toolkitQueueOperation==returned.toolkitQueueOperation and queue.queue[5]==returned)
    local first,last=operations.bounds(queue,resumed)
    assert(first==4 and last==5,'resumed reading and shelf return stay one contiguous operation')
    for _,command in ipairs({power,insert,play}) do
        assert(queue.current==command);command.action.done=true;frame(character)
    end
    assert(queue.current==resumed and read.item:getContainer()==character.inventory,'return cannot run before continued reading')
    resumed.action.done=true;frame(character)
    assert(queue.current==returned);returned.action.done=true;frame(character)
    assert(#queue.queue==0 and read.item:getContainer()==shelf,'return the original book once')

    for _,mode in ipairs({'missing-book','missing-shelf','changed-callback'}) do
        character,queue,read,returned,power,insert,play,shelf=scenario()
        assert(api.move(queue,read,play,true));frame(character)
        local resumed=queue.queue[4]
        if mode=='missing-shelf' then shelf.gone=true
        else character.inventory.items[read.item:getID()]=nil;read.item.container=nil end
        if mode=='changed-callback' then
            resumed.onCompleteFunc=function()error('unknown callback must not be suppressed')end
            queue.queue={play,resumed,returned};queue.current=play
            PZSurvivorToolkit.ActionQueueReading.skipUnavailable(queue)
            assert(queue.queue[2]==resumed,'unknown callback preserves native failure behavior')
        else
            for _,command in ipairs({power,insert,play}) do command.action.done=true;frame(character) end
            if mode=='missing-book' then assert(#queue.queue==0,'missing book skips only marked read/return without recreation')
            else
                assert(queue.current==resumed);resumed.action.done=true;frame(character)
                assert(#queue.queue==0 and read.item:getContainer()==character.inventory,'lost shelf keeps book carried')
            end
        end
    end

    -- Dropping above a target crosses only earlier whole operations; dropping on oneself is a no-op.
    character,queue,read,returned,power,insert,play=scenario()
    assert(api.move(queue,read,returned,true) and not queue.toolkitCancel)
    assert(api.move(queue,read,play,false));frame(character)
    assert(queue.queue[1]==power and queue.queue[2]==insert and queue.queue[3].item==read.item
        and queue.queue[4]==returned and queue.queue[5]==play)
    for _,mode in ipairs({'callback','shared-book','linked-tape','split','started','unknown'}) do
        character,queue,read,returned,power,insert,play=scenario()
        if mode=='callback' then returned.onCompleteFunc=function()end
        elseif mode=='shared-book' then local copy=book(character);copy.toolkitQueueOperation=insert.toolkitQueueOperation;queue.queue[4]=copy
        elseif mode=='linked-tape' then insert.item=read.item
        elseif mode=='split' then play.toolkitQueueOperation=read.toolkitQueueOperation
        elseif mode=='started' then insert.action={}
        elseif mode=='unknown' then insert.Type='UnknownDeviceAction' end
        assert(not api.move(queue,read,play,true) and queue.current==read and not queue.toolkitCancel,
            'demotion must reject '..mode)
    end
    -- A Host receipt gates reconstruction, and a changed reader constructor cannot be invoked late.
    local ack=PZSurvivorToolkit.ActionQueueAcknowledgements
    for _,outcome in ipairs({'canceled','completed','rejected','changed-constructor'}) do
        character,queue,read,returned,power,insert,play=scenario()
        local receipt={state='started'}
        PZSurvivorToolkit.ActionQueueAcknowledgements={capture=function(action)if action==read then return receipt end end,
            state=function()return receipt.state end,reset=function()end}
        assert(api.move(queue,read,play,true));frame(character)
        assert(queue.current==read and #queue.queue==5)
        local constructor=ISReadABook.new
        if outcome=='changed-constructor' then ISReadABook.new=function()error('changed constructor must not run')end end
        receipt.state=outcome=='changed-constructor' and 'canceled' or outcome
        queue:tick();ISReadABook.new=constructor
        assert(queue.current==power and queue.queue[2]==insert and queue.queue[3]==play)
        if outcome=='canceled' then assert(#queue.queue==5 and queue.queue[4].item==read.item and queue.queue[5]==returned)
        else assert(#queue.queue==4 and queue.queue[4]==returned,'terminal action cannot be replayed') end
        queue:tick();assert(queue.current==power,'duplicate terminal must not replay or advance')
    end
    PZSurvivorToolkit.ActionQueueAcknowledgements=ack
    print('Active reading demotion: UI drag, ordered range, saved pages, shelf return, dependencies and Host terminal races passed.')
end
-- Walking must not erase a successful native transfer's deferred completion boundary.
do
    local Lifecycle=PZSurvivorToolkit.ActionQueueLifecycle
    local previousClient=isClient
    for _,client in ipairs({false,true}) do
        isClient=function() return client end
        for _,movement in ipairs({'moving','pressed'}) do
            local character=player()
            local item=book(character).item
            local source=sourceContainer();borrowed(item,source)
            local pickup=transfer(character,item,source,character.inventory)
            pickup.stopOnWalk=false
            local followup=book(character)
            local starts=0
            local startAction=character.StartAction
            character.StartAction=function(self,native)
                if native.table==followup then starts=starts+1 end
                return startAction(self,native)
            end
            local queue=ISTimedActionQueue.add(pickup);ISTimedActionQueue.add(followup)
            frame(character)
            assert(pickup.action.started and not followup.action,'transfer must start before native completion')
            assert(Lifecycle.begin(pickup,'perform'))
            pickup:perform()
            assert(queue.current==pickup and queue.queue[1]==pickup and not followup.action,
                'native perform must defer followup until callbacks and Java removal finish')
            Lifecycle.finish(pickup,'perform',true)
            if not client then
                assert(Lifecycle.begin(pickup,'complete'))
                Lifecycle.finish(pickup,'complete',true)
            end
            if movement=='moving' then character.moving=true
            else character.pressedMovement=function() return true end end
            queue:tick()
            assert(queue.current==pickup and not followup.action and starts==0,
                'walking transfer must wait while its completed Java action is still present')
            character.actions[pickup.action]=nil
            queue:tick()
            assert(queue.current==followup and #queue.queue==1 and starts==1 and followup.action
                and item:getContainer()==character.inventory,
                (client and 'MP' or 'SP')..' '..movement..' lost a successful walking transfer completion')
            queue:tick();queue:tick()
            assert(queue.current==followup and starts==1 and #queue.queue==1,
                'walking completion must start the original followup exactly once')
        end
        for _,abort in ipairs({'reset','clear','stop'}) do
            local character=player()
            local item=book(character).item
            local source=sourceContainer();borrowed(item,source)
            local pickup=transfer(character,item,source,character.inventory)
            pickup.stopOnWalk=false
            local followup=book(character)
            local queue=ISTimedActionQueue.add(pickup);ISTimedActionQueue.add(followup)
            frame(character)
            assert(Lifecycle.begin(pickup,'perform'))
            pickup:perform()
            if abort=='reset' then queue:resetQueue()
            elseif abort=='clear' then queue:clearQueue()
            else pickup:stop() end
            Lifecycle.finish(pickup,'perform',true)
            character.actions[pickup.action]=nil;character.moving=true
            queue:tick()
            -- Native clearQueue empties the queue without clearing its current pointer.
            assert(#queue.queue==0 and queue.current~=followup and not followup.action and Lifecycle.flush(queue)==nil,
                abort..' must invalidate deferred completion rather than resurrecting its followup')
        end
    end
    isClient=previousClient
end
print('Walking native completion: SP/MP callbacks, movement input, Java removal, single followup start and explicit abort guards passed.')
-- Skip audited unavailable successors before native validation/start, preserving cleanup and independent work.
for _,family in ipairs({'ActionQueueGenerators','ActionQueueFire'}) do
    local previous=PZSurvivorToolkit[family]
    for _,sameOperation in ipairs({false,true}) do
        p=player()
        local blocker,missing,linked,ending=book(p),leaf(p,'unavailable successor'),leaf(p,'linked successor'),leaf(p,'independent tail')
        local bag=sourceContainer()
        local item=borrowed(book(p).item,sameOperation and p.inventory or bag)
        local originalReturn=transfer(p,item,p.inventory,bag);originalReturn.allowMissingItems=true
        missing.isValidStart=function() return family=='ActionQueueFire' end
        missing.isValid=function() error('an unavailable successor must never reach native validation') end
        if not sameOperation then q=ISTimedActionQueue.add(blocker) end
        operations.run(function()
            if sameOperation then q=ISTimedActionQueue.add(blocker) end
            ISTimedActionQueue.add(missing);ISTimedActionQueue.addAfter(missing,linked);ISTimedActionQueue.add(originalReturn)
        end)
        ISTimedActionQueue.add(ending);frame(p)
        local token=missing.toolkitQueueOperation
        if sameOperation then token.toolkitPickups={[item]=bag} end
        PZSurvivorToolkit[family]={canSkip=function(action) return action==missing end}
        blocker.action.forceStop=function() error('completion must not stop its already-finished owner') end
        blocker.action.done=true;frame(p)
        assert(token.toolkitCancelled and not missing.action and not linked.action and not originalReturn.action
            and not blocker.action.stopping and not ending.toolkitQueueOperation.toolkitCancelled,
            'an audited unavailable successor must drop its linked operation without stopping the finished owner or independent tail')
        if sameOperation then
            local cleanup=q.current
            assert(#q.queue==2 and cleanup~=originalReturn and cleanup.Type=='ISInventoryTransferAction'
                and cleanup.item==item and cleanup.destContainer==bag and cleanup.allowMissingItems
                and q.queue[2]==ending and not ending.action,
                'same-operation completion must rebuild exactly one borrowed-item return before the independent tail')
            cleanup.action.done=true;frame(p)
            assert(item.container==bag and q.current==ending,'borrowed cleanup must finish before the independent tail starts')
        else
            assert(#q.queue==1 and q.current==ending and item.container==bag,
                'a separate unavailable operation must not discard the independent native tail')
        end
    end
    for _,mode in ipairs({'unknown','disabled','allocated','unknown-child'}) do
        p=player()
        local blocker,missing,ending=book(p),leaf(p,'protected invalid successor'),leaf(p,'native reset tail')
        missing.isValidStart=function() return false end
        operations.run(function()
            q=ISTimedActionQueue.add(blocker);ISTimedActionQueue.add(missing)
            if mode=='unknown-child' then
                local child=leaf(p,'foreign linked child');child.onCompleteFunc=function() error('foreign callback must not run') end
                ISTimedActionQueue.addAfter(missing,child)
            end
        end)
        ISTimedActionQueue.add(ending);frame(p)
        if mode=='allocated' then missing.action=LuaTimedActionNew.new(missing) end
        enabled=mode~='disabled'
        PZSurvivorToolkit[family]={canSkip=function(action) return mode~='unknown' and action==missing end}
        blocker.action.done=true;frame(p)
        assert(#q.queue==0 and q.current==nil and not ending.action,
            mode..' invalid successor must retain native reset semantics')
        enabled=true
    end
    PZSurvivorToolkit[family]=previous
end
p=player();a,b,d=book(p),book(p),book(p)
local bag=sourceContainer();borrowed(a.item,bag)
pickup=transfer(p,a.item,bag,p.inventory)
restore=transfer(p,a.item,p.inventory,bag);restore.allowMissingItems=true
operations.run(function()
    q=ISTimedActionQueue.add(pickup);ISTimedActionQueue.add(a);ISTimedActionQueue.add(b);ISTimedActionQueue.add(restore)
end)
ISTimedActionQueue.add(d);frame(p);pickup.action.done=true;frame(p);frame(p)
assert(q.current==a and a.item.container==p.inventory and a.toolkitQueueOperation.toolkitPickups[a.item]==bag)
refresh();panel=ui[#ui];panel:update();list=panel.list
local header=list.items[1];assert(header.header)
local cancelX,cancelY=list:cancelX()+12,list:topOfItem(1)+16
list:onMouseDown(cancelX,cancelY);list:onMouseUp(cancelX,cancelY)
assert(q.toolkitCancel==a and q.toolkitGroupCancel and q.current==a and #q.queue==4)
q:tick();assert(q.current==a and not restore.action)
frame(p)
local returned=q.current
assert(returned.Type=='ISInventoryTransferAction' and returned~=restore and returned.item==a.item)
assert(returned.allowMissingItems and #q.queue==2 and q.queue[2]==d and not q.toolkitGroupCancel)
assert(not b.action and not p.actions[a.action], 'group stop must precede native cleanup; remaining work never starts')
returned.action.done=true;frame(p)
assert(a.item.container==bag and q.current==d, 'borrowed item returns once, then the unrelated operation starts')
-- A running transfer is allowed to finish its native transaction before cancellation cleans the group.
p=player();a,d=book(p),book(p);bag=sourceContainer();borrowed(a.item,bag)
pickup=transfer(p,a.item,bag,p.inventory)
operations.run(function() q=ISTimedActionQueue.add(pickup);ISTimedActionQueue.add(a) end)
ISTimedActionQueue.add(d);frame(p)
assert(api.cancelOperation(q,a) and q.toolkitGroupCancel and not q.toolkitCancel and not pickup.action.stopping)
assert(api.cancelOperationReason(q,a)=='stopping' and not api.move(q,d,pickup))
pickup.action.done=true;frame(p)
assert(not a.action and q.current.item==a.item and q.current.destContainer==bag)
q.current.action.done=true;frame(p);assert(q.current==d and a.item.container==bag)
-- Completed outputs/consumed inputs are not recreated; removed containers leave surviving items carried.
for _, mode in ipairs({'consumed','missing-source','completion-race','ordinary-clear','movement','death'}) do
    p=player();a,b,d=book(p),book(p),book(p);bag=sourceContainer();borrowed(a.item,p.inventory)
    operations.run(function() q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b) end)
    a.toolkitQueueOperation.toolkitPickups={[a.item]=bag}
    ISTimedActionQueue.add(d);frame(p)
    assert(api.cancelOperation(q,a))
    if mode=='consumed' then a.item.consumed=true
    elseif mode=='missing-source' then bag.gone=true
    elseif mode=='completion-race' then a.action.completing=true;a.item.consumed=true
    elseif mode=='ordinary-clear' then ISTimedActionQueue.clear(p)
    elseif mode=='movement' then p.moving=true
    elseif mode=='death' then p.dead=true end
    frame(p)
    if mode=='ordinary-clear' or mode=='movement' or mode=='death' then
        assert(#q.queue==0 and not q.toolkitGroupCancel and not q.toolkitCancel, mode.." count="..#q.queue.." group="..tostring(q.toolkitGroupCancel).." cancel="..tostring(q.toolkitCancel))
    else
        assert(q.current==d and #q.queue==1 and not b.action and a.item.container==p.inventory, mode)
    end
end
-- A failed cleanup transfer must not discard the unrelated tail.
p=player();a,d=book(p),book(p);bag=sourceContainer();borrowed(a.item,p.inventory)
q=ISTimedActionQueue.add(a);a.toolkitQueueOperation.toolkitPickups={[a.item]=bag}
ISTimedActionQueue.add(d);frame(p);assert(api.cancelOperation(q,a));frame(p)
returned=q.current;assert(returned.toolkitQueueReturn)
frame(p);returned:forceStop();frame(p)
assert(q.current==d and a.item.container==p.inventory, 'failed native return keeps the item and the unrelated queue')
print('Started-operation cancellation: header, native stop ordering, pickup transaction completion, returns, consumed inputs, lost containers, completion races and abort guards passed.')

-- A mod cannot opt an active preparation into cancellation by copying a native Type.
p=player();a=book(p);bag=sourceContainer();borrowed(a.item,bag)
pickup=transfer(p,a.item,bag,p.inventory)
operations.run(function() q=ISTimedActionQueue.add(pickup);ISTimedActionQueue.add(a) end)
frame(p);local nativePerform=pickup.perform
pickup.perform=function() error('unverified preparation') end
assert(api.cancelOperationReason(q,a)=='operation_dependent' and not api.cancelOperation(q,a))
pickup.perform=nativePerform
PZSurvivorToolkit.BulkActions.guardTransfer(pickup)
assert(not api.cancelOperationReason(q,a), 'the exact Toolkit pickup guard remains supported')
PZSurvivorToolkit.BulkActions.guardTransfer(pickup)
assert(not api.cancelOperationReason(q,a), 'repeated guards must retain exact native stop support')
local safeCompletion = pickup.onCompleteFunc
local foreignCompletion = function() end
pickup.onCompleteFunc = foreignCompletion
PZSurvivorToolkit.BulkActions.guardTransfer(pickup)
assert(pickup.onCompleteFunc == foreignCompletion, 'a later owner keeps its completion callback')
assert(api.cancelOperationReason(q,a) == 'operation_dependent' and not api.cancelOperation(q,a),
    'an unknown completion callback must remain opaque after reapplying the guard')
pickup.onCompleteFunc = safeCompletion

-- Native MP object replacement updates action fields, but pickup-token keys retain the old object.
local function replacementItem(character, original, container)
    local replacement = book(character).item
    character.inventory.items[replacement:getID()] = nil
    replacement.id = original:getID()
    borrowed(replacement, container)
    character.inventory.items[replacement:getID()] = replacement
    return replacement
end
p=player();a,b,d=book(p),book(p),book(p);bag=sourceContainer()
local original=borrowed(a.item,nil)
local replacement=replacementItem(p,original,p.inventory)
a.item=replacement
restore=transfer(p,replacement,p.inventory,bag);restore.allowMissingItems=true
operations.run(function() q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b);ISTimedActionQueue.add(restore) end)
a.toolkitQueueOperation.toolkitPickups={[original]=bag}
ISTimedActionQueue.add(d);frame(p)
assert(api.cancelOperation(q,a));frame(p)
returned=q.current
assert(returned.item==replacement and returned.destContainer==bag and #q.queue==2 and q.queue[2]==d,
    'old pickup and new native-return references to one ID must produce exactly one live-item return')
returned.action.done=true;frame(p)
assert(q.current==d and replacement.container==bag and original.container==nil,
    'return the resolved native object without recreating the stale object')
-- A consumed-input pickup has no native return; recovery must resolve its stale token key itself.
p=player();a,b,d=book(p),book(p),book(p);bag=sourceContainer()
original=borrowed(a.item,nil)
replacement=replacementItem(p,original,p.inventory);a.item=replacement
operations.run(function() q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b) end)
a.toolkitQueueOperation.toolkitPickups={[original]=bag}
ISTimedActionQueue.add(d);frame(p)
assert(api.cancelOperation(q,a));frame(p)
returned=q.current
assert(returned.Type=='ISInventoryTransferAction' and returned.item==replacement
    and returned.destContainer==bag and #q.queue==2 and q.queue[2]==d,
    'pickup-only stale reference must return the live replacement once before the independent tail')
returned.action.done=true;frame(p)
assert(q.current==d and replacement.container==bag and original.container==nil)
for _, mode in ipairs({'absent','consumed','nested'}) do
    p=player();a,b,d=book(p),book(p),book(p);bag=sourceContainer()
    original=borrowed(a.item,nil)
    replacement=replacementItem(p,original,p.inventory);a.item=replacement
    operations.run(function() q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b) end)
    a.toolkitQueueOperation.toolkitPickups={[original]=bag}
    ISTimedActionQueue.add(d);frame(p)
    if mode=='absent' then p.inventory.items[replacement:getID()]=nil
    elseif mode=='consumed' then replacement.consumed=true
    elseif mode=='nested' then replacement.container=sourceContainer() end
    assert(api.cancelOperation(q,a));frame(p)
    assert(q.current==d and #q.queue==1 and original.container==nil,
        mode .. ': resolve only surviving direct-root items; preserve unrelated work')
end

-- Different native objects with the same ID retain cancellation and reorder dependencies.
p=player();a,b,d=book(p),book(p),book(p)
original=b.item;replacement=replacementItem(p,original,p.inventory);d.item=replacement
q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b);ISTimedActionQueue.add(d)
assert(api.cancelOperationReason(q,b)=='operation_shared_item')
assert(api.moveReason(q,b,d,true)=='move_shared_item')
p=player();a,b,d=book(p),book(p),book(p);bag=sourceContainer()
original=borrowed(book(p).item,nil);replacement=replacementItem(p,original,p.inventory);d.item=replacement
q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b);b.toolkitQueueOperation.toolkitPickups={[original]=bag}
ISTimedActionQueue.add(d)
assert(api.cancelOperationReason(q,b)=='operation_shared_item', 'completed pickup dependencies also use stable IDs')

-- UI callback owners are dependency objects, not InventoryItems with native IDs.
local previousCraft=PZSurvivorToolkit.ActionQueueCraft
PZSurvivorToolkit.ActionQueueCraft={supports=function(action) return action.owner~=nil end,
    collectItems=function(action, items)
        if action.owner then items[action.owner]=true;return true,true end
        return false,false
    end}
p=player();a,b,d=book(p),book(p),book(p)
local owner={getID=function() error('UI owners must retain reference identity') end}
b.owner,d.owner=owner,owner
q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b);ISTimedActionQueue.add(d)
assert(api.cancelOperationReason(q,b)=='operation_shared_item' and api.moveReason(q,b,d,true)=='move_shared_item')
d.owner={getID=owner.getID}
assert(not api.cancelOperationReason(q,b) and not api.moveReason(q,b,d,true), 'different UI owners stay independent')
PZSurvivorToolkit.ActionQueueCraft=previousCraft
print('Stable item IDs: stale pickup replacement, deduplicated native returns, absent/consumed/nested items, same-ID dependencies and UI-owner identities passed.')

-- Standard native actions use the same outcome gate as custom build synchronization.
local realAcknowledgements = PZSurvivorToolkit.ActionQueueAcknowledgements
for _, outcome in ipairs({'canceled', 'completed', 'rejected'}) do
    p=player();a=book(p);b=leaf(p,'urgent-native-outcome');c=book(p)
    q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b);ISTimedActionQueue.add(c);frame(p)
    local receipt={state='started'}
    PZSurvivorToolkit.ActionQueueAcknowledgements={
        capture=function(action) if action==a then return receipt end end,
        state=function(action, record) if action==a and record==receipt then return record.state end end,
        reset=function() end,
    }
    assert(api.move(q,b,a) and q.toolkitOutcomeWait.generic)
    frame(p)
    assert(q.current==a and q.toolkitCancelStopped and not p.actions[a.action],
        'local stop/removal must still wait for the standard server outcome')
    receipt.state=outcome
    q:tick()
    assert(q.current==b and not q.toolkitOutcomeWait and not q.toolkitCancel)
    assert(#q.queue==(outcome=='canceled' and 3 or 2), 'only confirmed cancellation may replay reading')
    if outcome=='canceled' then
        assert(q.queue[2]~=a and q.queue[2].Type=='ISReadABook' and q.queue[2].item==a.item and q.queue[3]==c)
    else assert(q.queue[2]==c, 'completed/rejected effect was replayed') end
end
PZSurvivorToolkit.ActionQueueAcknowledgements=realAcknowledgements
print('Generic native outcomes: local stop/removal waits for receipt; only canceled resumes, completed/rejected preserve independent tail without replay.')

-- A replicated BBQ effect can invalidate native isValid() before local completion/Done arrives.
do
    load('shared/TimedActions/ISBBQLightFromPetrol.lua')
    local previousFire, previousClient = PZSurvivorToolkit.ActionQueueFire, isClient
    local previousEvent = Events.OnServerCommand.Add
    local receive
    Events.OnServerCommand.Add=function(callback) receive=callback end
    assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueAcknowledgements.lua'))()
    Events.OnServerCommand.Add=previousEvent
    isClient=function() return true end
    local oldGlobals, oldChange=ZomboidGlobals, IsoObjectChange
    ZomboidGlobals, IsoObjectChange={LightFromPetrolAmount=.1}, {STATE='state'}
    local serial=0
    local function setup(uses, supported)
        serial=serial+1
        local character=player()
        function character:getOnlineID() return 100 end
        function character:stopOrTriggerSound() end
        function character.inventory:contains(item) return item:getContainer()==self end
        local source=sourceContainer()
        local petrol, matches=borrowed(book(character).item,character.inventory),borrowed(book(character).item,character.inventory)
        local fluid={amount=2,getAmount=function(self) return self.amount end,
            adjustAmount=function(self,value) self.amount=value end}
        petrol.getFluidContainer=function() return fluid end
        petrol.getCurrentUsesFloat=function() return fluid.amount end
        matches.uses=uses
        matches.getCurrentUsesFloat=function(self) return self.uses end
        matches.UseAndSync=function(self) self.uses=self.uses-1;if self.uses==0 then self.container=nil end end
        local bbq={lit=false,gone=false,getObjectIndex=function(self) return self.gone and -1 or 1 end,
            isLit=function(self) return self.lit end,hasFuel=function() return true end,
            turnOn=function(self) self.lit=true end,sendObjectChange=function() end}
        local ignition=ISBBQLightFromPetrol:new(character,bbq,matches,petrol)
        ignition.ignoreHandsWounds=true
        local originalReturn=transfer(character,matches,character.inventory,source)
        originalReturn.allowMissingItems=true
        local queue
        operations.run(function() queue=ISTimedActionQueue.add(ignition);ISTimedActionQueue.add(originalReturn) end)
        local token=ignition.toolkitQueueOperation
        token.toolkitPickups={[petrol]=source,[matches]=source}
        local reader=book(character);ISTimedActionQueue.add(reader)
        -- The native action is already started; its real isValid/complete/stop callbacks are exercised below.
        ignition.action.started=true
        ignition.toolkitNativeTransaction,ignition.toolkitNativeKind=serial,'ISBBQLightFromPetrol'
        local args={protocol=1,player=100,transaction=serial,kind=ignition.toolkitNativeKind,
            token=string.format('00000000-0000-0000-0000-%012x',serial),state='started'}
        local function receipt(state) args.state=state;receive('PZSurvivorToolkitActions','State',args) end
        if supported~=false then receipt('started') end
        PZSurvivorToolkit.ActionQueueFire={
            canSkip=function(action) return action==ignition and not action.onCompleteFunc and not action:isValid() end,
            skipUnavailableReturns=function(q,current)
                if current==ignition and q.queue[2]==originalReturn and not character.inventory:contains(matches) then
                    table.remove(q.queue,2)
                end
            end,
        }
        assert(ignition:isValid())
        return character,queue,ignition,originalReturn,reader,token,source,petrol,matches,fluid,bbq,receipt
    end
    for _,scenario in ipairs({'completed-last-use','completed-return','canceled','rejected','unsupported','stale','token-changed','timeout','disabled','moving','unknown-callback'}) do
        local character,queue,ignition,originalReturn,reader,token,source,petrol,matches,fluid,bbq,receipt=
            setup(scenario=='completed-return' and 2 or 1,scenario~='unsupported')
        local completed=scenario=='completed-last-use' or scenario=='completed-return'
        if completed then assert(ignition:complete());assert(bbq.lit and fluid.amount==1.9)
        else bbq.gone=true end
        assert(not ignition:isValid(),'real native BBQ validity must reject the replicated effect/removed target')
        if scenario=='disabled' then enabled=false
        elseif scenario=='moving' then character.moving=true
        elseif scenario=='unknown-callback' then ignition.onCompleteFunc=function() end end
        -- Native Java stop calls Lua before removing the action from characterActions.
        ignition:stop()
        if scenario=='disabled' or scenario=='moving' or scenario=='unknown-callback' then
            assert(#queue.queue==0,'unaudited/disabled/moving stops retain native reset')
        elseif scenario=='unsupported' then
            assert(token.toolkitCancelled and queue.toolkitGroupCancel,'no receipt retains conservative group cleanup')
        else
            assert(queue.toolkitOutcomeWait and not token.toolkitCancelled and not queue.toolkitGroupCancel,
                'correlated stop must wait before canceling a possibly completed Fire operation')
            if scenario=='completed-return' then receipt('completed') end
            queue:tick()
            assert(queue.current==ignition and not originalReturn.action and not reader.action,
                'terminal ACK alone must not cross the native removal boundary')
        end
        character.actions[ignition.action]=nil
        if scenario=='stale' then queue.toolkitOperationGeneration=(queue.toolkitOperationGeneration or 0)+1
        elseif scenario=='token-changed' then ignition.toolkitQueueOperation={}
        elseif scenario=='timeout' then acknowledgementClock=acknowledgementClock+30000
        elseif scenario~='unsupported' and scenario~='disabled' and scenario~='moving' and scenario~='unknown-callback' then
            receipt(completed and 'completed' or scenario)
        end
        queue:tick()
        if completed then
            assert(not token.toolkitCancelled and petrol.container==character.inventory and fluid.amount==1.9,
                'completed server effect must keep spent petrol carried without group rollback')
            if scenario=='completed-return' then
                assert(queue.current==originalReturn and originalReturn.toolkitQueueOperation==token,
                    'completed ACK must preserve the original native return and operation token')
                originalReturn.action.done=true;frame(character)
                assert(matches.container==source)
            end
            assert(queue.current==reader and not queue.toolkitOutcomeWait and not queue.toolkitGroupCancel)
            frame(character);reader.action.done=true;frame(character)
            assert(#queue.queue==0,'independent reading must finish after completed Fire effects and native returns')
        elseif scenario=='canceled' or scenario=='rejected' or scenario=='unsupported' then
            assert(token.toolkitCancelled and not originalReturn.action and not reader.action)
            while queue.current~=reader do
                local cleanup=queue.current
                assert(cleanup and cleanup.toolkitQueueReturn and cleanup.destContainer==source)
                cleanup.action.done=true;frame(character)
            end
            assert(petrol.container==source and matches.container==source and fluid.amount==2,
                'canceled/rejected effects retain exact borrowed cleanup before the independent reader')
        else assert(#queue.queue==0 and not queue.toolkitOutcomeWait,'stale/unsupported ownership must not replay work') end
        enabled=true
    end
    PZSurvivorToolkit.ActionQueueFire=previousFire
    PZSurvivorToolkit.ActionQueueAcknowledgements=realAcknowledgements
    isClient,ZomboidGlobals,IsoObjectChange=previousClient,oldGlobals,oldChange
end
print('Native BBQ stop race: correlated completed/canceled/rejected outcomes, native removal, exact returns, independent reading and conservative abort guards passed.')
