-- Full production Queue and installed native Lua callbacks; Java allocation,
-- removal, server delivery and replication are explicit engine doubles. No
-- automatic tool producer or live Host transport is qualified by this fixture.
assert(NativeActionRoot,'cleanup failure composition requires --game or --native-action-root')
local create=assert(loadfile(ProjectRoot..'/tests/support/borrowing_composition.lua'))()

local function allocations(f,action)
    local count=0
    for _,event in ipairs(f.engineTrace) do
        if event.event=='native-allocation' and event.action==action then count=count+1 end
    end
    return count
end
local function sourceGuard(f)
    local e=f.env;local class,base=e.ISEquipWeaponAction,e.ISBaseTimedAction
    local classParent,baseParent=getmetatable(class),getmetatable(base)
    local heavy,drop=e.isForceDropHeavyItem,e.forceDropHeavyItems
    local methods,baseMethods={},{}
    for name,callback in pairs(class) do if type(callback)=='function' then methods[name]=callback end end
    for name,callback in pairs(base) do if type(callback)=='function' then baseMethods[name]=callback end end
    return function(action)
        if e.ISEquipWeaponAction~=class or e.ISBaseTimedAction~=base or getmetatable(action)~=class
            or getmetatable(class)~=classParent or getmetatable(base)~=baseParent
            or e.isForceDropHeavyItem~=heavy or e.forceDropHeavyItems~=drop then return false end
        for name,callback in pairs(methods) do if class[name]~=callback or action[name]~=callback then return false end end
        for name,callback in pairs(class) do if type(callback)=='function' and methods[name]~=callback then return false end end
        for name,callback in pairs(baseMethods) do
            if base[name]~=callback or action[name]~=(methods[name] or callback) then return false end
        end
        return true
    end
end
local function loanState(f)
    local state=f.t.ActionQueueSettlement.operationState(f.reading)
    for _,loan in ipairs(state and state.borrowings or {}) do
        if loan.id==f.borrowed:getID() then return loan.state end
    end
end
local function finish(f,action,outcome)
    local e=f.env
    f.start(action)
    if f.client and action.Type=='ISEquipWeaponAction' then
        local result=action:complete() -- Explicit genuine server effect/replication seam.
        f.acknowledge(action,outcome or (result and 'completed' or 'rejected'))
    end
    f.dispatch(action,'perform')
end
local function fixture(client,options,reused,episode)
    options=options or {}
    local f=reused or create(client,{p4=false,carried=true})
    local e,t,q=f.env,f.env.PZSurvivorToolkit,f.queue
    f.t,f.client=t,client
    f.initialEffects=#f.effects
    f.preparationEquip,f.returned,f.returnCalls=nil,nil,nil
    local owned=f.cleanupCommands or {}
    -- Exact test-owned command contract for cleanup plumbing only. Native
    -- Equip/Transfer bodies and production Policy inspection stay unchanged.
    if not f.cleanupCommands then t.ActionQueueDefinitions.registerBehavior('fixture.cleanup-failure',{
        types={'ISQueueActionsAction'},
        matches=function(action) return owned[action]~=nil and t.ActionQueueOperations.isCommand(action) end,
        inspect=function(action)
            assert(owned[action] and action.addActionsFunction==owned[action])
            return {knownInputs=true,items={},targets={[f.player]=true},hands=f.player,equipment=f.player,
                deferred=options.cancelBeforeExpansion or nil,cancelWaiting=options.cancelBeforeExpansion or nil}
        end,
    });f.cleanupCommands=owned end
    local function command(callback)
        local action=t.ActionQueueOperations.command(f.player,callback,{})
        owned[action]=callback
        return action
    end
    local offset=(episode or 0)*10
    f.previous=f.book(8101+offset,f.inventory)
    f.borrowed=f.book(8102+offset)
    f.player:setPrimaryHandItem(f.previous) -- Disposable baseline, before native work.
    e.ISInventoryPaneContextMenu.readItem(f.borrowed,0)
    local approach,pickup,reading,originalReturn=unpack(q.queue)
    f.approach,f.pickup,f.reading,f.originalReturn=approach,pickup,reading,originalReturn
    local settlement=t.ActionQueueSettlement
    f.loan=assert(settlement.track(pickup,'prepare'))
    assert(not settlement.earned(f.loan),'enqueue manufactured an earned loan')
    -- Replace only the pending native return in this disclosed test topology;
    -- no Keep or item/equipment effect is applied at this setup boundary.
    assert(q:indexOf(originalReturn)>1 and not originalReturn.action)
    q:removeFromQueue(originalReturn)
    local nativeSource=sourceGuard(f)
    local expansion
    expansion=command(function()
        assert(q.current==expansion and expansion._isAddingActions,'cleanup did not use its actual expansion boundary')
        if options.abandonExpansion then f.abandoned=true;return end
        local restore=e.ISEquipWeaponAction:new(f.player,f.previous,50,true,false)
        t.ActionQueueOperations.adopt(restore,expansion.toolkitQueueOperation)
        assert(options.cancelBeforeExpansion and settlement.inheritCleanup(restore,expansion)
            or not options.cancelBeforeExpansion and settlement.cleanup(restore,f.loan))
        local specification={
            guard=function(action) return action==restore and action.item==f.previous and action.character==f.player end,
            capture=function()
                if options.capture=='nil' then return end
                if options.capture=='error' then error('test engine capture unavailable') end
                return {primary=f.player:getPrimaryHandItem(),secondary=f.player:getSecondaryHandItem()}
            end,
            observed=function(_,before)
                return before.primary~=f.previous and f.player:getPrimaryHandItem()==f.previous
                    and f.player:getSecondaryHandItem()==before.secondary
            end,
        }
        if options.sourceGuard~=false then specification.sourceGuard=nativeSource end
        f.restoreHandle=assert(settlement.observeCleanupEffect(restore,specification))
        f.restore=restore
        local continuation
        continuation=command(function()
            f.returnCalls=(f.returnCalls or 0)+1
            f.returned=settlement.enqueueBorrowedReturn(f.loan)
        end)
        t.ActionQueueOperations.adopt(continuation,expansion.toolkitQueueOperation)
        assert(options.cancelBeforeExpansion and settlement.inheritCleanup(continuation,expansion)
            or not options.cancelBeforeExpansion and settlement.cleanup(continuation,f.loan))
        f.continuation=continuation
        if options.enrolled~=false then
            assert(settlement.requireBorrowedReturnSuccess(f.loan,{f.restoreHandle},continuation))
        end
        e.ISTimedActionQueue.add(restore)
        e.ISTimedActionQueue.add(continuation)
        if options.beforeAdmission then options.beforeAdmission(f) end
    end)
    t.ActionQueueOperations.adopt(expansion,reading.toolkitQueueOperation)
    assert(settlement.cleanup(expansion,f.loan))
    if options.cancelBeforeExpansion and not options.unclaimed then
        assert(settlement.claimBorrowedReturn(expansion,f.loan))
    end
    t.ActionQueueOperations.runWith(reading.toolkitQueueOperation,function() e.ISTimedActionQueue.add(expansion) end)
    f.expansion=expansion
    e.ISInventoryPaneContextMenu.readItem(f.book(8103+offset,f.inventory),0)
    f.tail=q.queue[#q.queue]
    assert(f.tail.Type=='ISReadABook' and f.tail.toolkitQueueOperation~=reading.toolkitQueueOperation)
    f.start(approach);f.dispatch(approach,'perform')
    assert(q.current==pickup and allocations(f,pickup)==1)
    f.start(pickup);f.deliver(pickup)
    if options.cancelBeforeExpansion then
        -- This genuine equip precedes the body that will be canceled, so the
        -- retained cleanup must still restore an actual different hand item.
        local equip=e.ISEquipWeaponAction:new(f.player,f.borrowed,50,true,false)
        t.ActionQueueOperations.adopt(equip,reading.toolkitQueueOperation)
        e.ISTimedActionQueue.addAfter(pickup,equip)
        f.preparationEquip=equip
    end
    f.dispatch(pickup,'perform')
    if options.cancelBeforeExpansion then
        assert(q.current==f.preparationEquip)
        finish(f,f.preparationEquip)
        assert(f.player:getPrimaryHandItem()==f.borrowed)
    end
    assert(q.current==reading and settlement.earned(f.loan) and loanState(f)=='active'
        and f.borrowed:getContainer()==f.inventory and #f.effects==f.initialEffects+1,'genuine native fetch did not earn its exact loan')
    if not options.alreadyHeld and not options.cancelBeforeExpansion then
        -- A genuine native preparation equip, not a test hand write, establishes
        -- the different current primary that the cleanup is meant to restore.
        local equip=e.ISEquipWeaponAction:new(f.player,f.borrowed,50,true,false)
        t.ActionQueueOperations.adopt(equip,reading.toolkitQueueOperation)
        e.ISTimedActionQueue.addAfter(reading,equip)
        f.preparationEquip=equip
    end
    f.start(reading)
    if options.cancelBeforeExpansion then
        local originalToken=reading.toolkitQueueOperation
        local accepted,reason=t.ActionQueue.cancelOperation(q,reading)
        assert(accepted,'earned reading cancellation was rejected: '..tostring(reason))
        assert(reading.action.stopped and q.current==reading and not f.restore and not f.continuation,
            'cancellation expanded cleanup before native stop/removal')
        f.stop(reading,true)
        local expectedRows=options.unclaimed and 3 or 2
        assert(q.current==expansion and #q.queue==expectedRows and q.queue[expectedRows]==f.tail
            and expansion.toolkitQueueOperation~=originalToken
            and settlement.requiredStep(expansion) and settlement.isCleanup(expansion)
            and not f.tail.toolkitQueueOperation.toolkitCancelled
            and f.borrowed:getContainer()==f.inventory and #f.effects==f.initialEffects+1,
            'future return owner lost retained cleanup or synthesized an eager return')
        f.canceledToken=originalToken
        if options.unclaimed then
            f.eagerReturn=q.queue[2]
            assert(f.eagerReturn.Type=='ISInventoryTransferAction' and f.eagerReturn.item==f.borrowed
                and f.eagerReturn.srcContainer==f.inventory and f.eagerReturn.destContainer==f.source)
        end
    else f.dispatch(reading,'perform') end
    if f.preparationEquip and not options.cancelBeforeExpansion then
        assert(q.current==f.preparationEquip)
        finish(f,f.preparationEquip)
        assert(f.player:getPrimaryHandItem()==f.borrowed,'native preparation equip did not change the real hand')
    end
    assert(q.current==expansion)
    f.start(expansion);f.dispatch(expansion,'perform')
    if options.abandonExpansion then return f end
    assert(q.current==f.restore and allocations(f,f.restore)==1 and allocations(f,f.continuation)==0)
    return f
end
local function debt(f)
    local notices=f.t.ActionQueueSettlement.blockedReturns(f.player)
    assert(#notices==1 and notices[1].itemId==f.borrowed:getID()
        and notices[1].itemType==f.borrowed:getFullType(),'missing exact visible unresolved location debt')
    assert(f.borrowed:getContainer()==f.inventory and #f.effects==f.initialEffects+1 and loanState(f)=='active')
    assert(allocations(f,f.continuation)==0 and f.returned==nil and not f.originalReturn.action,
        'failed enrolled cleanup allocated its dependent continuation/return')
    return notices[1]
end
local function tail(f)
    local q=f.queue
    assert(q.current==f.tail and q:indexOf(f.restore)==-1 and not f.tail.toolkitQueueOperation.toolkitCancelled,
        'failed enrolled cleanup lost its independent native tail')
    assert(allocations(f,f.tail)==1)
    f.start(f.tail);f.dispatch(f.tail,'perform')
    assert(#q.queue==0 and f.borrowed:getContainer()==f.inventory and #f.effects==f.initialEffects+1)
end

for _,client in ipairs({false,true}) do
    local f=fixture(client)
    finish(f,f.restore)
    assert(f.queue.current==f.continuation and f.t.ActionQueueSettlement.earned(f.restoreHandle))
    f.start(f.continuation);f.dispatch(f.continuation,'perform')
    assert(f.returned and f.queue.current==f.returned and f.returnCalls==1)
    f.start(f.returned);f.deliver(f.returned);f.dispatch(f.returned,'perform')
    assert(f.borrowed:getContainer()==f.source and #f.effects==2 and loanState(f)=='completed'
        and f.player:getPrimaryHandItem()==f.previous,'successful cleanup/return did not retain real native effects')
    f.start(f.tail);f.dispatch(f.tail,'perform')
    assert(#f.queue.queue==0)
end
-- A future return owner is declared before canceling its native body. The
-- retained expansion receives a fresh operation and enrolls fresh children only
-- when its real callback runs; cancellation must not race it with a transfer.
for _,client in ipairs({false,true}) do
    local f=fixture(client,{cancelBeforeExpansion=true})
    local settlement,q=f.t.ActionQueueSettlement,f.queue
    local token=f.expansion.toolkitQueueOperation
    assert(f.restore.toolkitQueueOperation==token and f.continuation.toolkitQueueOperation==token
        and token~=f.canceledToken and #q.queue==3 and q.queue[2]==f.continuation and q.queue[3]==f.tail
        and settlement.requiredStep(f.restore) and settlement.requiredStep(f.continuation)
        and allocations(f,f.originalReturn)==0 and f.returnCalls==nil,
        'retained expansion reused canceled siblings or admitted an eager duplicate return')
    finish(f,f.restore)
    assert(q.current==f.continuation and settlement.earned(f.restoreHandle))
    f.start(f.continuation);f.dispatch(f.continuation,'perform')
    assert(f.returnCalls==1 and f.returned and q.current==f.returned
        and #q.queue==2 and q.queue[2]==f.tail and allocations(f,f.returned)==1
        and f.borrowed:getContainer()==f.inventory,
        'fresh cleanup did not issue exactly its own borrowed return before the independent tail')
    f.start(f.returned);f.deliver(f.returned);f.dispatch(f.returned,'perform')
    assert(q.current==f.tail and #q.queue==1 and not f.tail.toolkitQueueOperation.toolkitCancelled
        and f.player:getPrimaryHandItem()==f.previous and f.borrowed:getContainer()==f.source
        and #f.effects==f.initialEffects+2 and loanState(f)=='completed'
        and #settlement.blockedReturns(f.player)==0,
        'retained native cleanup lost effects, paid the loan twice or blocked independent work')
    f.start(f.tail);f.dispatch(f.tail,'perform')
    assert(#q.queue==0 and f.returnCalls==1 and #f.effects==f.initialEffects+2
        and allocations(f,f.originalReturn)==0)
end
-- Cancellation retention does not turn fresh enrollment into successful
-- restoration: a native stop must leave visible debt and release the tail.
for _,client in ipairs({false,true}) do
    local f=fixture(client,{cancelBeforeExpansion=true})
    local settlement,q=f.t.ActionQueueSettlement,f.queue
    assert(f.restore.toolkitQueueOperation==f.expansion.toolkitQueueOperation
        and f.restore.toolkitQueueOperation~=f.canceledToken)
    f.start(f.restore);f.restore:forceStop();f.stop(f.restore,true)
    if client then
        assert(q.current==f.restore and allocations(f,f.continuation)==0 and allocations(f,f.tail)==0,
            'retained cleanup advanced before its exact Host canceled terminal')
        f.acknowledge(f.restore,'canceled');q:tick()
    end
    debt(f)
    assert(f.player:getPrimaryHandItem()==f.borrowed and not settlement.earned(f.restoreHandle),
        'stopped retained cleanup manufactured a successful native hand restoration')
    tail(f)
end
-- Existing callers without a declared future owner retain ordinary eager
-- cancellation return synthesis; only an explicit claim can defer that debt.
for _,client in ipairs({false,true}) do
    local f=fixture(client,{cancelBeforeExpansion=true,abandonExpansion=true,unclaimed=true})
    local q=f.queue
    assert(f.abandoned and q.current==f.eagerReturn and #q.queue==2 and q.queue[2]==f.tail
        and f.returnCalls==nil and allocations(f,f.eagerReturn)==1
        and f.borrowed:getContainer()==f.inventory and #f.effects==f.initialEffects+1)
    f.start(f.eagerReturn);f.deliver(f.eagerReturn);f.dispatch(f.eagerReturn,'perform')
    assert(q.current==f.tail and f.borrowed:getContainer()==f.source
        and #f.effects==f.initialEffects+2 and loanState(f)=='completed')
    f.start(f.tail);f.dispatch(f.tail,'perform')
    assert(#q.queue==0 and #f.effects==f.initialEffects+2)
end
-- A claimed expansion that never enrolls its children cannot silently lose
-- the borrowed-location debt or fall back to an immediate native transfer.
for _,client in ipairs({false,true}) do
    local f=fixture(client,{cancelBeforeExpansion=true,abandonExpansion=true})
    local settlement,q=f.t.ActionQueueSettlement,f.queue
    local notices=settlement.blockedReturns(f.player)
    assert(f.abandoned and not f.restore and not f.continuation and f.returnCalls==nil
        and q.current==f.tail and #q.queue==1 and not f.tail.toolkitQueueOperation.toolkitCancelled
        and #notices==1 and notices[1].itemId==f.borrowed:getID()
        and notices[1].itemType==f.borrowed:getFullType()
        and f.borrowed:getContainer()==f.inventory and #f.effects==f.initialEffects+1
        and loanState(f)=='active' and allocations(f,f.originalReturn)==0,
        'abandoned future return owner lost its exact debt, synthesized a transfer or blocked the tail')
    f.start(f.tail);f.dispatch(f.tail,'perform')
    local after=settlement.blockedReturns(f.player)
    assert(#q.queue==0 and #after==1 and after[1].id==notices[1].id
        and f.borrowed:getContainer()==f.inventory and #f.effects==f.initialEffects+1)
end
for _,client in ipairs({false,true}) do
    local f=fixture(client,{alreadyHeld=true})
    f.start(f.restore)
    if client then assert(f.restore:complete()==false);f.acknowledge(f.restore,'rejected') end
    local _,performed=f.phase(f.restore,'perform');assert(performed)
    f.queue:tick()
    assert(f.queue.current==f.restore and f.queue:indexOf(f.tail)>1,'perform advanced before native complete/removal')
    if not client then local _,succeeded=f.phase(f.restore,'complete');assert(not succeeded) end
    f.queue:tick()
    assert(f.queue.current==f.restore and f.queue:indexOf(f.tail)>1,'failed callback advanced before Java removed its native episode')
    assert(allocations(f,f.continuation)==0,'no-effect callback advanced before native removal')
    f.remove(f.restore);f.queue:tick()
    debt(f);tail(f)
end
-- Successful local callbacks cannot release a Host dependency before both its
-- exact authority receipt and physical hand replication reach the same episode.
for _,first in ipairs({'receipt','effect'}) do
    local f=fixture(true)
    f.start(f.restore)
    f.phase(f.restore,'perform')
    f.remove(f.restore)
    if first=='receipt' then f.acknowledge(f.restore,'completed')
    else assert(f.restore:complete()) end
    f.queue:tick();f.queue:tick()
    assert(f.queue.current==f.restore and allocations(f,f.continuation)==0
        and f.queue:indexOf(f.tail)>1 and not f.t.ActionQueueSettlement.earned(f.restoreHandle),
        first..': half an outcome released the dependent native continuation')
    if first=='receipt' then assert(f.restore:complete())
    else f.acknowledge(f.restore,'completed') end
    f.queue:tick()
    assert(f.queue.current==f.continuation and allocations(f,f.continuation)==1
        and f.t.ActionQueueSettlement.earned(f.restoreHandle))
end
do
    local f=fixture(true,{alreadyHeld=true})
    f.start(f.restore);assert(f.restore:complete()==false)
    f.phase(f.restore,'perform');f.remove(f.restore);f.queue:tick()
    assert(f.queue.current==f.restore and allocations(f,f.continuation)==0 and f.queue:indexOf(f.tail)>1,
        'local no-effect callback advanced before its authoritative rejected terminal')
    f.acknowledge(f.restore,'rejected');f.queue:tick()
    debt(f);tail(f)
end
for _,client in ipairs({false,true}) do
    local f=fixture(client)
    f.start(f.restore);f.restore:forceStop()
    f.stop(f.restore,true)
    if client then
        assert(f.queue.current==f.restore and allocations(f,f.continuation)==0 and f.queue:indexOf(f.tail)>1,
            'native stop advanced before its exact Host canceled terminal')
        f.acknowledge(f.restore,'canceled');f.queue:tick()
    end
    debt(f);tail(f)
    assert(not f.t.ActionQueueSettlement.earned(f.restoreHandle),'native stop earned a hand restoration')
end
-- A real Host lag window can expose the unpaid item before the authenticated
-- canceled terminal arrives. Refine the existing notice rather than preserving
-- the early unknown label or publishing another debt for the same native stop.
for _,cancelBeforeExpansion in ipairs({false,true}) do
    local f=fixture(true,{cancelBeforeExpansion=cancelBeforeExpansion})
    local settlement=f.t.ActionQueueSettlement
    f.start(f.restore);f.restore:forceStop();f.stop(f.restore,true)
    local waiting=debt(f);local before=settlement.blockedReturnInfo(f.player)
    assert(waiting.reason=='cleanup-unresolved' and f.queue.current==f.restore,
        'Host lag did not preserve the unresolved exact cleanup notice')
    f.queue:tick()
    assert(settlement.blockedReturnInfo(f.player).revision==before.revision,
        'repeated pending observations revised unchanged cleanup debt')
    f.acknowledge(f.restore,'canceled');f.queue:tick()
    local confirmed=debt(f);local after=settlement.blockedReturnInfo(f.player)
    assert(confirmed.id==waiting.id and confirmed.itemId==waiting.itemId and confirmed.state=='blocked'
        and confirmed.reason=='cleanup-outcome' and after.count==before.count and after.revision==before.revision+1,
        'exact Host terminal did not refine the same live cleanup notice once')
    f.queue:tick()
    assert(settlement.blockedReturnInfo(f.player).revision==after.revision,
        'settled cleanup terminal repeatedly revised its existing notice')
    tail(f)
end
do
    local f=fixture(true)
    local settlement=f.t.ActionQueueSettlement
    f.start(f.restore);f.restore:forceStop();f.stop(f.restore,true)
    local waiting=debt(f)
    settlement.resetReturnFailures(f.queue)
    local revoked=settlement.blockedReturns(f.player)
    assert(#revoked==1 and revoked[1].id==waiting.id and revoked[1].state=='revoked')
    assert(settlement.keepReturn(f.player,waiting.id),'revoked cleanup notice could not be explicitly forgotten')
    local forgottenRevision=settlement.blockedReturnInfo(f.player).revision
    f.acknowledge(f.restore,'canceled');f.queue:tick()
    assert(#settlement.blockedReturns(f.player)==0
        and settlement.blockedReturnInfo(f.player).revision==forgottenRevision
        and f.queue.current==f.tail and allocations(f,f.continuation)==0,
        'late terminal recreated or revised an explicitly forgotten cleanup notice')
    tail(f)
end
do
    local f=fixture(false)
    f.start(f.restore);f.phase(f.restore,'perform')
    assert(f.queue.current==f.restore and allocations(f,f.continuation)==0)
    f.restore:forceStop();f.stop(f.restore,true)
    debt(f);tail(f)
    assert(not f.t.ActionQueueSettlement.earned(f.restoreHandle),
        'stop after perform was mistaken for a completed SP hand effect')
end
for _,capture in ipairs({'nil','error'}) do
    local f=fixture(false,{alreadyHeld=true,capture=capture})
    f.start(f.restore);f.phase(f.restore,'perform')
    local _,success=f.phase(f.restore,'complete');assert(not success)
    f.remove(f.restore);f.queue:tick()
    debt(f);tail(f)
end
do
    local f=fixture(true,{alreadyHeld=true,capture='nil'})
    f.start(f.restore);assert(f.restore:complete()==false)
    f.phase(f.restore,'perform');f.remove(f.restore);f.queue:tick()
    local notice=debt(f)
    assert(f.queue.current==f.restore and f.queue:indexOf(f.tail)>1)
    assert(f.t.ActionQueueSettlement.keepReturn(f.player,notice.id))
    local keptRevision=f.t.ActionQueueSettlement.blockedReturnInfo(f.player).revision
    assert(loanState(f)=='waived' and not f.t.ActionQueueSettlement.earned(f.restoreHandle))
    f.acknowledge(f.restore,'rejected');f.queue:tick()
    assert(f.queue.current==f.tail and allocations(f,f.continuation)==0
        and #f.t.ActionQueueSettlement.blockedReturns(f.player)==0
        and f.t.ActionQueueSettlement.blockedReturnInfo(f.player).revision==keptRevision,
        'explicit Keep while waiting made retired publication block the later exact terminal')
    tail(f)
end
for _,client in ipairs({false,true}) do
    local f=fixture(client)
    -- Model an external authority removing the prior item before Java admission.
    -- This grants no cleanup success; the exact borrowed item remains untouched.
    f.previous.container=nil
    assert(not f.restore:isValid() and not f.restore:isStarted())
    f.remove(f.restore);f.queue:tick()
    debt(f)
    if client then
        assert(f.queue.current==f.restore and f.queue:indexOf(f.tail)>1 and allocations(f,f.tail)==0,
            'unstarted Host removal borrowed authority without sealed Started/terminal')
    else tail(f) end
end
do
    local foreign=0
    local f=fixture(false,{beforeAdmission=function(value)
        value.env.ISEquipWeaponAction.update=function() foreign=foreign+1;error('foreign update executed') end
    end})
    f.previous.container=nil
    assert(not f.restore:isValid() and not f.restore:isStarted())
    f.remove(f.restore)
    local warn=f.env.DebugType.Action.warn
    f.env.DebugType.Action.warn=function(_,message,kind)
        assert(message=='ISTimedActionQueue:tick: bugged action %s, cleared queue' and kind==f.restore.Type)
    end
    f.queue:tick();f.env.DebugType.Action.warn=warn
    assert(#f.queue.queue==0 and allocations(f,f.continuation)==0 and allocations(f,f.tail)==0 and foreign==0,
        'unbound changed-source admission failure acquired cleanup isolation')
end
do
    local f=fixture(true)
    f.start(f.restore);f.phase(f.restore,'perform');f.remove(f.restore);f.queue:tick()
    assert(f.queue.current==f.restore and f.queue:indexOf(f.tail)>1 and allocations(f,f.continuation)==0)
    f.advance(30001);f.queue:tick()
    local notice=debt(f)
    local expiredRevision=f.t.ActionQueueSettlement.blockedReturnInfo(f.player).revision
    assert(f.queue.current==f.restore and f.queue:indexOf(f.tail)>1,
        'expired unknown Host outcome discarded protected head/tail')
    assert(f.restore:complete());f.acknowledge(f.restore,'completed')
    f.queue:tick();f.queue:tick()
    assert(debt(f).id==notice.id and debt(f).reason=='cleanup-unresolved'
        and f.t.ActionQueueSettlement.blockedReturnInfo(f.player).revision==expiredRevision
        and f.queue.current==f.restore and f.queue:indexOf(f.tail)>1
        and not f.t.ActionQueueSettlement.earned(f.restoreHandle),
        'late terminal/effect revived cleanup after its native authority deadline')
end
-- Source-less, unregistered, copied and replaced native episodes must retain
-- the conservative reset path; failure cannot retrospectively mint a binder.
for _,mode in ipairs({'unregistered','no-source-guard','source-changed','copied','replaced-native'}) do
    local f=fixture(false,{alreadyHeld=true,enrolled=mode~='unregistered',sourceGuard=mode~='no-source-guard'})
    local action=f.restore
    local foreignCalls=0
    if mode=='source-changed' then
        f.env.ISEquipWeaponAction.update=function() foreignCalls=foreignCalls+1;error('foreign source callback executed') end
    elseif mode=='copied' then
        local copy={};for key,value in pairs(action) do copy[key]=value end
        setmetatable(copy,getmetatable(action));f.queue.queue[1],f.queue.current=copy,copy;action=copy
    elseif mode=='replaced-native' then
        f.remove(action)
        action.action=f.env.LuaTimedActionNew.new(action,f.player) -- Explicit engine replacement, without fresh Queue admission.
    end
    f.start(action);f.phase(action,'perform')
    local _,success=f.phase(action,'complete');assert(not success)
    f.remove(action);f.queue:tick()
    assert(#f.queue.queue==0 and allocations(f,f.continuation)==0 and allocations(f,f.tail)==0
        and f.borrowed:getContainer()==f.inventory and #f.effects==1 and foreignCalls==0,
        mode..': unmanaged/stale native failure acquired isolated continuation rights')
end
-- Change the public command and its callback together at the LAST metadata
-- boundary, after the capsule's genuine source was authenticated. This must
-- still fail its original callback-free anchors before native allocation.
for _,mutation in ipairs({'callback','registry','head'}) do
    local f=fixture(false)
    local capsuleSeal
    for key,value in pairs(f.continuation) do
        if type(key)=='table' and type(value)=='table' and getmetatable(value)==nil
            and type(value[key])=='function' then
            assert(capsuleSeal==nil,'ambiguous private continuation capsule in fixture')
            capsuleSeal=value[key]
        end
    end
    assert(capsuleSeal,'actual enrolled continuation capsule missing')
    local e=f.env
    local metadata,enabled=e.getFilenameOfClosure,f.t.Settings.actionQueue
    local armed,changed,foreignCalls=false,false,0
    e.getFilenameOfClosure=function(callback)
        local filename=metadata(callback)
        if callback==capsuleSeal and not changed then armed=true end
        return filename
    end
    f.t.Settings.actionQueue=function()
        if armed and not changed then
            armed=false;changed=true
            if mutation=='callback' then
                local foreign=function() foreignCalls=foreignCalls+1;error('foreign continuation executed') end
                f.continuation.addActionsFunction=foreign
                f.continuation.toolkitQueueCommand.callback=foreign
            elseif mutation=='registry' then
                e.ISTimedActionQueue.queues[f.player]={character=f.player,queue={}}
            else
                f.queue.current=f.tail;f.queue.queue[1]=f.tail
            end
        end
        return enabled()
    end
    finish(f,f.restore)
    assert(changed and foreignCalls==0 and allocations(f,f.continuation)==0 and f.returnCalls==nil
        and f.returned==nil and #f.effects==1 and f.borrowed:getContainer()==f.inventory,
        mutation..': final metadata mutation issued a replaced or foreign continuation')
end
-- Fill the real bounded notice ledger through distinct genuine native fetch
-- and failed cleanup episodes, not copied diagnostics or private state writes.
local function saturation(client,withSourceGuard)
    local f,firstNotice
    local retired={}
    local function reject(value)
        value.start(value.restore)
        if client then assert(value.restore:complete()==false);value.acknowledge(value.restore,'rejected') end
        value.phase(value.restore,'perform')
        if not client then local _,success=value.phase(value.restore,'complete');assert(not success) end
        value.remove(value.restore);value.queue:tick()
    end
    for episode=1,32 do
        f=fixture(client,{alreadyHeld=true,sourceGuard=withSourceGuard},f,episode)
        reject(f)
        local notices=f.t.ActionQueueSettlement.blockedReturns(f.player)
        assert(#notices==episode and loanState(f)=='active' and allocations(f,f.continuation)==0,
            'real failed cleanup lost an earlier exact unpaid notice')
        firstNotice=firstNotice or notices[1]
        retired[#retired+1]=f.continuation
        tail(f)
    end
    f=fixture(client,{alreadyHeld=true,sourceGuard=withSourceGuard},f,33)
    reject(f);f.queue:tick()
    local notices=f.t.ActionQueueSettlement.blockedReturns(f.player)
    assert(#notices==32 and notices[1].id==firstNotice.id and loanState(f)=='active'
        and f.queue.current==f.restore and f.queue:indexOf(f.tail)>1
        and allocations(f,f.continuation)==0 and allocations(f,f.tail)==0
        and f.borrowed:getContainer()==f.inventory and #f.effects==f.initialEffects+1,
        'notice saturation advanced dependent native work or silently discarded debt')
    assert(f.t.ActionQueueSettlement.keepReturn(f.player,firstNotice.id))
    f.queue:tick()
    notices=f.t.ActionQueueSettlement.blockedReturns(f.player)
    local current=false
    for _,notice in ipairs(notices) do if notice.itemId==f.borrowed:getID() then current=notice end end
    assert(#notices==32 and current and f.queue.current==f.tail and loanState(f)=='active'
        and allocations(f,f.continuation)==0 and #f.effects==f.initialEffects+1,
        'freeing one notice slot replayed cleanup or failed to publish the held unpaid loan')
    tail(f)
    return f,retired
end
local saturated,retired=saturation(false,true)
-- A normal, ready-but-unearned Host rejection uses only the exact continuation
-- gate. No sourceGuard/bound failure episode was issued anywhere in this VM.
saturation(true,false)

-- Replay exactly the bounded number of ACTUAL retired, never-allocated commands
-- from the completed native episodes. Removing that prefix must expose the
-- independent tail; reaching the bound itself is not proof of another capsule.
do
    local f=saturated
    local e,q=f.env,f.queue
    local effects=#f.effects
    e.ISInventoryPaneContextMenu.readItem(f.book(9901,f.inventory),0)
    local head=q.current
    e.ISInventoryPaneContextMenu.readItem(f.book(9902,f.inventory),0)
    local independent=q.queue[2]
    assert(head.Type=='ISReadABook' and independent.Type=='ISReadABook'
        and head.toolkitQueueOperation~=independent.toolkitQueueOperation)
    for index,command in ipairs(retired) do
        assert(command.action==nil and allocations(f,command)==0,'captured replay was previously native-issued')
        table.insert(q.queue,index+1,command)
    end
    local before=f.t.ActionQueueSettlement.blockedReturns(f.player)
    f.start(head);f.dispatch(head,'perform')
    assert(q.current==independent and allocations(f,independent)==1 and #q.queue==1
        and #f.effects==effects,'exact bounded replay prefix reset or blocked the independent native tail')
    for _,command in ipairs(retired) do
        assert(q:indexOf(command)==-1 and allocations(f,command)==0,'retired capsule replay allocated native work')
    end
    local after=f.t.ActionQueueSettlement.blockedReturns(f.player)
    assert(#after==#before)
    for index,notice in ipairs(before) do
        assert(after[index].id==notice.id and after[index].itemId==notice.itemId and after[index].state==notice.state,
            'retired command replay changed an existing location debt')
    end
    f.start(independent);f.dispatch(independent,'perform')
    assert(#q.queue==0 and #f.effects==effects)
end
print('Enrolled cleanup failures: real native Queue allocation, callbacks and explicit engine delivery checks passed.')

if TestCoverage then TestCoverage('source-contract','passed') end
