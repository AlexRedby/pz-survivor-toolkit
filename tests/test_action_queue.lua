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
instanceof = function(value, name) return value.class == name end
local function derive(self, name)
    local t = {Type = name, derive = derive}
    t.__index = t
    return setmetatable(t, {__index = self})
end
ISBaseObject = {derive = derive}
table.wipe = function(t) for k in pairs(t) do t[k] = nil end end
Events = {OnTick = {Add = function() end}}
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
load('shared/TimedActions/ISReadABook.lua')
load('shared/Moveables/ISMoveablesAction.lua')
ISInventoryPage = {}
load('client/TimedActions/ISInventoryTransferAction.lua')
ISContextMenu, ISButton, ISInventoryPaneContextMenu = {}, {}, {}
Events.OnGameStart = {Add = function(fn) fn() end}
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueOperations.lua'))()
local operations = PZSurvivorToolkit.ActionQueueOperations
SkillBook, ItemTag, CharacterTrait, ItemBodyLocation = {}, {}, {}, {}
MoodleType = {}
getSandboxOptions = function() return {getOptionByName=function() return {getValue=function() return 2 end} end} end
getGameTime = function() return {getMinutesPerDay=function() return 60 end} end
-- Exercise the native constructor/duration; animation and Java validity are fixture doubles.
local newRead = ISReadABook.new
ISReadABook.new = function(self, character, item)
    local a = newRead(self, character, item)
    a.start = function(v) v.character:setReading(true) end
    a.isValid = function(v) return not v.missing end
    a.perform = function(v) v.character:setReading(false); ISBaseTimedAction.perform(v) end
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
    local p = {class = 'IsoPlayer', actions = {}, farming = false, reading = false}
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
local function book(p)
    local a = ISBaseTimedAction.new(ISReadABook, p)
    a.maxTime = 1
    a.item = {delta = .5, getNumberOfPages = function() return 100 end,
        getAlreadyReadPages = function(s) return s.pages or 12 end,
        setAlreadyReadPages=function(s,v) s.pages=v end, getFullType=function() return 'Base.BookCarpentry' end,
        getSkillTrained=function() return '' end, hasTag=function() return false end, getType = function() return 'BookCarpentry' end,
        setJobDelta = function(s,v) s.delta = v end, getDisplayName = function() return 'Book' end, getTex = function() return 'book-icon' end,
        class = 'InventoryItem'}
    a.start = function(self) self.character:setReading(true) end
    a.isValid = function(s) return not s.missing end
    a.perform = function(s) s.character:setReading(false); ISBaseTimedAction.perform(s) end
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
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueLabels.lua'))()
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueue.lua'))()
local api = PZSurvivorToolkit.ActionQueue
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
    local action = ISBaseTimedAction.new(ISBaseTimedAction:derive(kind), character)
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
assert(api.cancelOperation(q,b), 'the exact verified no-op completion marker allows guarded pickups')
b=pendingGroup(preparation(p,'ISInventoryTransferAction'),book(p));b.onCompleteFunc=function() end
b.toolkitQueueSafeOnComplete=b.onCompleteFunc;b.onCompleteFunc=function() error('changed callback') end
assert(api.cancelOperationReason(q,b)=='operation_dependent', 'changed callbacks invalidate the exact safety marker')
-- Started and partially completed operation tokens never become waiting operations again.
p=player();a,b=book(p),book(p)
operations.run(function() q=ISTimedActionQueue.add(a);ISTimedActionQueue.add(b) end)
assert(api.cancelOperationReason(q,b)=='operation_active')
frame(p);a.action.done=true;frame(p)
assert(api.cancelOperationReason(q,b)=='operation_active' and #q.queue==1)
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
    assert(api.cancelOperationReason(q,b)=='operation_shared_item', 'native craft input lists expose external dependencies')
end
b=pendingGroup(leaf(p,'output'),book(p));ISTimedActionQueue.add(preparation(p,'ISQueueActionsAction'))
assert(api.cancelOperationReason(q,b)=='operation_dependent', 'unknown output consumers remain protected')
b=pendingGroup(leaf(p,'output'),book(p));use=book(p);use.onCompleteFunc=function() error('later callback dependency') end
ISTimedActionQueue.add(use)
assert(api.cancelOperationReason(q,b)=='operation_dependent', 'later callbacks may depend on an otherwise removable operation output')
b=pendingGroup(book(p),book(p));use=preparation(p,'ModWork');use.items={custom='mod collection'};ISTimedActionQueue.add(use)
assert(api.cancelOperation(q,b), 'arbitrary mod collection fields are not interpreted as native craft lists')
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
assert(api.move(q,c,b) and q.queue == nativeQueue and q.queue[2] == c and q.queue[3] == b)
assert(q.current == a and a.action == originalCurrent and not b.action and not c.action)
assert(api.move(q,c,b,true) and q.queue[2] == b and q.queue[3] == c)
assert(not api.move(q,a,c), 'cannot drag an active operation')
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
ISTimedActionQueue.add(callbackMove);assert(api.move(q,callbackMove,pickup))
local deferred=leaf(p,'deferred');deferred.Type='ISQueueActionsAction'
ISTimedActionQueue.add(deferred);assert(api.move(q,deferred,callbackMove))
assert(api.move(q,callbackMove,deferred), 'pending native generators keep their operation boundary')
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
function widget:setY(v) self.y=v end
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
    assert(texture);self.lastTexture=texture;self.drawnTextures=self.drawnTextures or {};self.drawnTextures[#self.drawnTextures+1]=texture
end
function widget:setStencilRect(x,y,width,height)
    self.clips=self.clips or {};self.clips[#self.clips+1]={x=x,width=width}
end
function widget:clearStencilRect() end
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
assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueuePanel.lua'))()
p = player(); a,b,c = book(p),book(p),book(p)
q = ISTimedActionQueue.add(a); ISTimedActionQueue.add(b); ISTimedActionQueue.add(c)
refresh(); local panel=ui[#ui]; panel:update()
assert(panel.visible and #panel.list.items==3 and not panel.closeButton.visible)
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
click(1);assert(not q.toolkitCancel and #q.queue==3, 'current collapsed header cannot cancel its hidden current step')
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
enabled=false; refresh(); assert(not panel.visible and #panel.list.items==0, 'hidden view must release action snapshots')
assert(not hasEntry(panel.expanded) and not list.dragAction and not list.pressedToggle)
enabled=true; refresh(); assert(panel.visible and ui[#ui]==panel)
p.dead=true; refresh(); assert(not panel.visible)
p=player(); ISTimedActionQueue.add(book(p)); refresh()
assert(panel.removed and #panel.list.items==0 and not hasEntry(panel.expanded) and ui[#ui]~=panel and ui[#ui].queue.character==p)
local replaced = ui[#ui]
ISTimedActionQueue:new(p); ISTimedActionQueue.add(book(p)); refresh()
assert(replaced.removed and ui[#ui].queue == ISTimedActionQueue.queues[p])
ui[#ui]:update(); ISTimedActionQueue.clear(p); refresh()
assert(not ui[#ui].visible and #ui[#ui].list.items == 0, 'completed/stopped queue must release rows')
playerCount=0; refresh(); assert(ui[#ui].removed)
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
        if action.mpBuild then return false, "move_world_transaction" end
        return action.trustedBuild and action.onCompleteFunc == completeBuild
    end,
    resume = function(action)
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
