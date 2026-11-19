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
    f.loans,f.borroweds={f.loan},{f.borrowed}
    if options.multi then
        -- Test-owned generic producer topology: a genuine second native fetch
        -- shares the operation; no automatic gameplay producer is qualified.
        local source=f.source
        if options.separateSources then
            source={}
            for key,value in pairs(f.source)do source[key]=value end
            local bag=f.book(8106+offset,f.inventory)
            for key,value in pairs(f.bag)do if key~='id'and key~='container'then bag[key]=value end end
            bag.getInventory=function()return source end;bag.getItemContainer=bag.getInventory
            source.owner=bag
            f.secondSource=source
        end
        local item=f.book(8104+offset,source)
        local second=e.ISInventoryTransferUtil.newInventoryTransferAction(f.player,item,source,f.inventory)
        t.ActionQueueOperations.adopt(second,reading.toolkitQueueOperation)
        local handle=assert(settlement.observePreparation(second,{
            guard=function(action)return action==second and action.item==item end,
            capture=function()return {source=item:getContainer()}end,
            observed=function(_,before)return before.source==source and item:getContainer()==f.inventory end,
        }))
        t.BulkActions.guardTransfer(pickup)
        t.BulkActions.guardTransfer(second)
        e.ISTimedActionQueue.addAfter(pickup,second)
        if options.partialLoan then q:removeFromQueue(second)end
        f.secondPickup=second
        f.loans[2],f.borroweds[2]=handle,item
    end
    f.paidCount=options.partialLoan and 1 or #f.loans
    assert(not settlement.earned(f.loan),'enqueue manufactured an earned loan')
    -- Replace only the pending native return in this disclosed test topology;
    -- no Keep or item/equipment effect is applied at this setup boundary.
    assert(q:indexOf(originalReturn)>1 and not originalReturn.action)
    if not options.keepBeforeCancel then q:removeFromQueue(originalReturn)end
    local nativeSource=sourceGuard(f)
    local expansion
    expansion=command(function()
        assert(q.current==expansion and expansion._isAddingActions,'cleanup did not use its actual expansion boundary')
        if options.reserveDenied then
            assert(not settlement.reserveClaimedReturn(expansion,f.loan),'unclaimed expansion acquired fallback debt ownership')
        end
        if options.multi and not options.direct then
            for _,bad in ipairs({{f.loan},{f.loan,f.loan},{f.loan,{}}})do
                assert(not settlement.reserveClaimedReturns(expansion,bad),
                    'partial, duplicate or copied batch gained fallback debt ownership')
            end
            local getter=e.getActivatedMods
            e.getActivatedMods=function()return {contains=function()return true end}end
            assert(not settlement.reserveClaimedReturns(expansion,f.loans),'provider refusal partially reserved a batch')
            e.getActivatedMods=getter
            assert(settlement.reserveClaimedReturns(expansion,f.loans),'actual batch expansion lost its complete claim')
            assert(settlement.reserveClaimedReturns(expansion,f.loans),'same batch reservation must remain idempotent')
        end
        if options.reserve then
            assert(not settlement.reserveClaimedReturn(expansion,{}),'copied loan acquired fallback debt ownership')
            assert(not settlement.reserveClaimedReturn(f.tail,f.loan),'unrelated command acquired claimed loan')
            assert(settlement.reserveClaimedReturn(expansion,f.loan),'actual claimed expansion could not reserve its exact loan')
            assert(settlement.reserveClaimedReturn(expansion,f.loan),'same claimed expansion did not preserve its reservation')
        end
        if options.direct then
            local issued,rows=settlement.enqueueClaimedReturns(expansion,f.loans)
            assert(issued,'actual direct expansion could not issue its paid subset')
            f.returnedRows=rows
            assert(not settlement.enqueueClaimedReturns(expansion,f.loans),'direct batch expansion replayed native returns')
            return
        end
        if options.abandonExpansion then f.abandoned=true;return end
        local restore=e.ISEquipWeaponAction:new(f.player,f.previous,50,true,false)
        t.ActionQueueOperations.adopt(restore,expansion.toolkitQueueOperation)
        assert(options.cancelBeforeExpansion and settlement.inheritCleanup(restore,expansion)
            or not options.cancelBeforeExpansion and settlement.cleanupAfter(restore,f.loans))
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
        if options.admit then specification.admit=function(action)
            f.admitCalls=(f.admitCalls or 0)+1
            return options.admit(f,action)
        end end
        f.restoreHandle=assert(settlement.observeCleanupEffect(restore,specification))
        f.restore=restore
        f.restoreHandles={f.restoreHandle}
        if options.multiEffects then
            local secondary=f.book(8105+offset,f.inventory)
            local nextRestore=e.ISEquipWeaponAction:new(f.player,secondary,50,false,false)
            t.ActionQueueOperations.adopt(nextRestore,expansion.toolkitQueueOperation)
            assert(options.cancelBeforeExpansion and settlement.inheritCleanup(nextRestore,expansion)
                or not options.cancelBeforeExpansion and settlement.cleanupAfter(nextRestore,f.loans))
            f.secondRestoreHandle=assert(settlement.observeCleanupEffect(nextRestore,{
                guard=function(action)return action==nextRestore and action.item==secondary end,
                capture=function()return {secondary=f.player:getSecondaryHandItem()}end,
                observed=function(_,before)return before.secondary~=secondary and f.player:getSecondaryHandItem()==secondary end,
                sourceGuard=nativeSource,
            }))
            f.restoreHandles[2]=f.secondRestoreHandle
            f.secondRestore=nextRestore
        end
        local continuation
        continuation=command(function()
            f.returnCalls=(f.returnCalls or 0)+1
            if options.multi then
                f.returnedRows={}
                for _,handle in ipairs(f.loans)do
                    f.returnedRows[#f.returnedRows+1]=assert(settlement.enqueueBorrowedReturn(handle))
                end
                f.returned=f.returnedRows[1]
            else f.returned=settlement.enqueueBorrowedReturn(f.loan)end
        end)
        t.ActionQueueOperations.adopt(continuation,expansion.toolkitQueueOperation)
        assert(options.cancelBeforeExpansion and settlement.inheritCleanup(continuation,expansion)
            or not options.cancelBeforeExpansion and settlement.cleanupAfter(continuation,f.loans))
        f.continuation=continuation
        if options.enrolled~=false then
            if options.multi then
                for _,bad in ipairs({{f.loan},{f.loan,f.loan},{f.loan,{}}})do
                    assert(not settlement.requireBorrowedReturnsSuccess(bad,{f.restoreHandle},continuation),
                        'partial, duplicate or copied loan batch gained continuation authority')
                end
                assert(not settlement.requireBorrowedReturnsSuccess(f.loans,{f.restoreHandle,f.restoreHandle},continuation),
                    'duplicate effect dependencies enrolled a shared continuation')
                local input={}
                for index,handle in ipairs(f.loans)do input[index]=handle end
                local dependencies={}
                for index,handle in ipairs(f.restoreHandles)do dependencies[index]=handle end
                assert(settlement.requireBorrowedReturnsSuccess(input,dependencies,continuation))
                input[2],input[1]=nil,{}
                dependencies[2],dependencies[1]=nil,{}
                assert(not settlement.requireBorrowedReturnsSuccess(f.loans,{f.restoreHandle},continuation),
                    'same batch enrolled the same continuation twice')
            else assert(settlement.requireBorrowedReturnSuccess(f.loan,{f.restoreHandle},continuation))end
        end
        e.ISTimedActionQueue.add(restore)
        if f.secondRestore then e.ISTimedActionQueue.add(f.secondRestore)end
        e.ISTimedActionQueue.add(continuation)
        if options.beforeAdmission then options.beforeAdmission(f) end
    end)
    t.ActionQueueOperations.adopt(expansion,reading.toolkitQueueOperation)
    assert(settlement.cleanupAfter(expansion,f.loans))
    if options.multi then
        for _,bad in ipairs({{f.loan},{f.loan,f.loan},{f.loan,{}}})do
            assert(not settlement.claimBorrowedReturns(expansion,bad),
                'partial, duplicate or copied batch gained future return ownership')
        end
        local getter=e.getActivatedMods
        e.getActivatedMods=function()return {contains=function()return true end}end
        assert(not settlement.claimBorrowedReturns(expansion,f.loans),'provider refusal partially claimed a batch')
        e.getActivatedMods=getter
        local input={f.loans[1],f.loans[2]}
        assert(settlement.claimBorrowedReturns(expansion,input),'complete batch failed to claim its future returns')
        input[2],input[1]=nil,{}
        assert(not settlement.claimBorrowedReturns(expansion,f.loans),'batch claim replay was accepted')
    end
    if not options.multi and (options.cancelBeforeExpansion or options.claim) and not options.unclaimed then
        assert(settlement.claimBorrowedReturn(expansion,f.loan))
    end
    if options.dormant then
        assert(settlement.onCancelBorrowedReturns(expansion,f.loans),'dormant cleanup registration was refused')
        assert(not settlement.onCancelBorrowedReturns(expansion,f.loans),'dormant cleanup registration replayed')
        assert(q:indexOf(expansion)==-1 and allocations(f,expansion)==0,'dormant registration scheduled native work')
    else t.ActionQueueOperations.runWith(reading.toolkitQueueOperation,function() e.ISTimedActionQueue.add(expansion) end)end
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
        e.ISTimedActionQueue.addAfter(f.secondPickup or pickup,equip)
        f.preparationEquip=equip
    end
    f.dispatch(pickup,'perform')
    if options.multi and not options.partialLoan then
        assert(q.current==f.secondPickup,'second native fetch must precede body and owned restoration')
        f.start(f.secondPickup);f.deliver(f.secondPickup);f.dispatch(f.secondPickup,'perform')
        assert(settlement.earned(f.loans[2]) and f.borroweds[2]:getContainer()==f.inventory)
    end
    if options.cancelBeforeExpansion then
        assert(q.current==f.preparationEquip)
        finish(f,f.preparationEquip)
        assert(f.player:getPrimaryHandItem()==f.borrowed)
    end
    assert(q.current==reading and settlement.earned(f.loan) and loanState(f)=='active'
        and f.borrowed:getContainer()==f.inventory and #f.effects==f.initialEffects+f.paidCount,'genuine native fetch did not earn its exact loan')
    if not options.alreadyHeld and not options.cancelBeforeExpansion then
        -- A genuine native preparation equip, not a test hand write, establishes
        -- the different current primary that the cleanup is meant to restore.
        local equip=e.ISEquipWeaponAction:new(f.player,f.borrowed,50,true,false)
        t.ActionQueueOperations.adopt(equip,reading.toolkitQueueOperation)
        e.ISTimedActionQueue.addAfter(reading,equip)
        f.preparationEquip=equip
    end
    f.start(reading)
    if options.keepBeforeCancel then
        local kept,reason=t.ActionQueue.cancel(q,originalReturn)
        assert(kept,'native pending Keep was refused before batch cancellation: '..tostring(reason))
        assert(q.current==reading and q:indexOf(originalReturn)==-1 and loanState(f)=='waived'
            and f.borrowed:getContainer()==f.inventory and allocations(f,originalReturn)==0,
            'native Keep rewrote another loan or performed a location effect')
    end
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
            and f.borrowed:getContainer()==f.inventory and #f.effects==f.initialEffects+f.paidCount,
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
    if options.dormant and not options.cancelBeforeExpansion then
        assert(q.current==f.tail and q:indexOf(expansion)==-1 and allocations(f,expansion)==0
            and not f.returnedRows,'dormant cancellation owner executed during ordinary completion')
        return f
    end
    assert(q.current==expansion)
    if options.reserve then
        assert(not settlement.reserveClaimedReturn(expansion,f.loan),'claim was reserved outside its actual expansion')
    end
    f.start(expansion);f.dispatch(expansion,'perform')
    if options.abandonExpansion or options.direct then return f end
    if options.heldVeto then
        assert(q.current==f.restore and allocations(f,f.restore)==0 and allocations(f,f.continuation)==0)
    elseif options.veto then
        assert(q.current==f.tail and allocations(f,f.restore)==0 and allocations(f,f.continuation)==0,
            'declined cleanup allocated native work or failed to release the independent tail')
    else assert(q.current==f.restore and allocations(f,f.restore)==1 and allocations(f,f.continuation)==0) end
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

-- Generic batch plumbing uses the actual Queue.begin, native transfer/equip
-- callbacks and full observer/receipt lifecycle. Its extra fetch and cleanup
-- commands are explicit test topology, not a claimed automatic game producer.
local function batchStates(f,expected)
    local seen={}
    for _,loan in ipairs(assert(f.t.ActionQueueSettlement.operationState(f.reading)).borrowings)do
        seen[loan.id]=loan.state
    end
    for _,item in ipairs(f.borroweds)do
        assert(seen[item:getID()]==expected,'a batch member lost its independent exact loan state')
    end
end
local function batchDebts(f)
    local notices=f.t.ActionQueueSettlement.blockedReturns(f.player)
    local wanted={}
    for _,item in ipairs(f.borroweds)do wanted[item:getID()]=item end
    assert(#notices==#f.borroweds,'shared cleanup failure lost an exact unpaid batch member: '..tostring(f.batchLabel)..' notices='..#notices)
    for _,notice in ipairs(notices)do
        local item=assert(wanted[notice.itemId],'batch debt was duplicated or rebound')
        assert(notice.itemType==item:getFullType() and notice.state=='blocked'
            and item:getContainer()==f.inventory,'failed shared cleanup moved or rebound an unpaid item')
        wanted[notice.itemId]=nil
    end
    assert(next(wanted)==nil and f.returnCalls==nil and not f.returnedRows
        and allocations(f,f.continuation)==0 and #f.effects==f.initialEffects+#f.loans,
        'failed shared cleanup issued its dependent continuation or native returns')
    batchStates(f,'active')
    return notices
end
for _,client in ipairs({false,true})do
    for _,canceled in ipairs({false,true})do
        local f=fixture(client,{multi=true,cancelBeforeExpansion=canceled})
        local settlement,q=f.t.ActionQueueSettlement,f.queue
        batchStates(f,'active')
        finish(f,f.restore)
        assert(q.current==f.continuation and settlement.earned(f.restoreHandle)
            and allocations(f,f.continuation)==1,'successful shared restore did not release its one continuation')
        f.start(f.continuation);f.dispatch(f.continuation,'perform')
        assert(f.returnCalls==1 and #f.returnedRows==#f.loans
            and q.queue[#q.queue]==f.tail,'shared continuation lost a loan or independent native tail')
        for index,row in ipairs(f.returnedRows)do
            assert(q.current==row and row.item==f.borroweds[index]
                and row.srcContainer==f.inventory and row.destContainer==f.source
                and allocations(f,row)==1,'batch return lost its exact native item/endpoints')
            f.start(row);f.deliver(row);f.dispatch(row,'perform')
        end
        batchStates(f,'completed')
        assert(q.current==f.tail and not f.tail.toolkitQueueOperation.toolkitCancelled
            and #settlement.blockedReturns(f.player)==0 and #f.effects==f.initialEffects+2*#f.loans)
        for _,item in ipairs(f.borroweds)do assert(item:getContainer()==f.source)end
        f.start(f.tail);f.dispatch(f.tail,'perform')
        assert(#q.queue==0 and f.returnCalls==1,'independent tail replayed a completed batch return')

        local partial=fixture(client,{multi=true,multiEffects=true,cancelBeforeExpansion=canceled})
        finish(partial,partial.restore)
        assert(partial.queue.current==partial.secondRestore and partial.t.ActionQueueSettlement.earned(partial.restoreHandle)
            and not partial.t.ActionQueueSettlement.earned(partial.secondRestoreHandle)
            and allocations(partial,partial.continuation)==0,
            'only a paid prefix of shared cleanup released the entire batch continuation')
        partial.start(partial.secondRestore);partial.secondRestore:forceStop();partial.stop(partial.secondRestore,true)
        if client then
            assert(partial.queue.current==partial.secondRestore and allocations(partial,partial.continuation)==0)
            partial.acknowledge(partial.secondRestore,'canceled');partial.queue:tick()
        end
        partial.batchLabel=tostring(client)..':'..tostring(canceled)..':partial-effect'
        batchDebts(partial)
        assert(partial.t.ActionQueueSettlement.earned(partial.restoreHandle)
            and not partial.t.ActionQueueSettlement.earned(partial.secondRestoreHandle)
            and partial.queue.current==partial.tail,'failed second dependency rewrote its already-earned predecessor')
        partial.start(partial.tail);partial.dispatch(partial.tail,'perform')
        assert(#partial.queue.queue==0 and #partial.effects==#partial.loans)

        for _,failure in ipairs({'admission','stopped','abandoned'})do
            local options={multi=true,cancelBeforeExpansion=canceled}
            if failure=='admission'then options.veto=true;options.admit=function()return false end
            elseif failure=='abandoned'then options.abandonExpansion=true end
            local failed=fixture(client,options)
            if failure=='stopped'then
                failed.start(failed.restore);failed.restore:forceStop();failed.stop(failed.restore,true)
                if client then
                    assert(failed.queue.current==failed.restore and allocations(failed,failed.tail)==0,
                        'stopped shared restore advanced before its exact Host terminal')
                    failed.acknowledge(failed.restore,'canceled');failed.queue:tick()
                end
            end
            failed.batchLabel=tostring(client)..':'..tostring(canceled)..':'..failure
            local before=batchDebts(failed)
            assert(failed.queue.current==failed.tail and allocations(failed,failed.tail)==1
                and not failed.tail.toolkitQueueOperation.toolkitCancelled,
                'failed batch cleanup discarded its independent native tail')
            failed.start(failed.tail);failed.dispatch(failed.tail,'perform')
            local after=failed.t.ActionQueueSettlement.blockedReturns(failed.player)
            assert(#failed.queue.queue==0 and #after==#before and #failed.effects==#failed.loans)
            for index,notice in ipairs(before)do assert(after[index].id==notice.id)end
        end
    end
end

-- A no-effect continuation returns only paid loans. Pending Keep and a full
-- source retain independent per-item outcomes; dormant cancellation ownership
-- must stay absent from the normal queue until an actual cancellation occurs.
for _,client in ipairs({false,true})do
    local partial=fixture(client,{multi=true,direct=true,partialLoan=true,alreadyHeld=true})
    assert(#partial.returnedRows==1 and partial.queue.current==partial.returnedRows[1]
        and partial.returnedRows[1].item==partial.borroweds[1]
        and not partial.t.ActionQueueSettlement.earned(partial.loans[2])
        and partial.borroweds[2]:getContainer()==partial.source,
        'direct cleanup returned an unpaid loan or omitted its paid member')
    local row=partial.returnedRows[1]
    partial.start(row);partial.deliver(row);partial.dispatch(row,'perform')
    assert(partial.queue.current==partial.tail and #partial.effects==2)
    partial.start(partial.tail);partial.dispatch(partial.tail,'perform')
    assert(#partial.queue.queue==0 and #partial.t.ActionQueueSettlement.blockedReturns(partial.player)==0)

    local full=fixture(client,{multi=true,direct=true,alreadyHeld=true})
    local t,q=full.t,full.queue;local first,second=unpack(full.returnedRows)
    assert(q.current==first and q:indexOf(second)>1 and not second.action)
    full.start(first);full.deliver(first);full.dispatch(first,'perform')
    assert(q.current==second and full.borroweds[1]:getContainer()==full.source)
    full.source.room=false
    assert(second:isValid()==false,'full source did not reject the genuine second native return')
    full.remove(second);q:tick()
    local notices=t.ActionQueueSettlement.blockedReturns(full.player)
    assert(q.current==full.tail and #notices==1 and notices[1].itemId==full.borroweds[2]:getID()
        and full.borroweds[1]:getContainer()==full.source and full.borroweds[2]:getContainer()==full.inventory
        and not full.tail.toolkitQueueOperation.toolkitCancelled and #full.effects==3,
        'full origin lost its exact unpaid member or blocked the independent tail after a paid return')
    full.start(full.tail);full.dispatch(full.tail,'perform')
    assert(#q.queue==0 and #full.effects==3,'independent tail replayed a refused batch return')

    -- Distinct origins prove refusal isolation is tied to the exact claimed
    -- sibling, rather than a same-destination or transfer-kind shortcut.
    local firstFull=fixture(client,{multi=true,direct=true,separateSources=true,alreadyHeld=true})
    local settlement,queue=firstFull.t.ActionQueueSettlement,firstFull.queue
    local refused,sibling=unpack(firstFull.returnedRows)
    assert(queue.current==refused and sibling.destContainer==firstFull.secondSource
        and refused.destContainer==firstFull.source and not sibling.action)
    firstFull.source.room=false
    assert(not refused:isValid(),'full first origin did not refuse native admission')
    firstFull.remove(refused);queue:tick()
    local unpaid=settlement.blockedReturns(firstFull.player)
    assert(queue.current==sibling and #unpaid==1 and unpaid[1].itemId==firstFull.borroweds[1]:getID()
        and firstFull.borroweds[1]:getContainer()==firstFull.inventory and allocations(firstFull,sibling)==1
        and not firstFull.tail.toolkitQueueOperation.toolkitCancelled,
        'first full origin lost exact debt or discarded its independently owned sibling return')
    firstFull.start(sibling);firstFull.deliver(sibling);firstFull.dispatch(sibling,'perform')
    assert(queue.current==firstFull.tail and firstFull.borroweds[2]:getContainer()==firstFull.secondSource
        and firstFull.borroweds[1]:getContainer()==firstFull.inventory and #firstFull.effects==3,
        'valid sibling did not retain its exact native return after another origin refused admission')
    firstFull.start(firstFull.tail);firstFull.dispatch(firstFull.tail,'perform')
    local after=settlement.blockedReturns(firstFull.player)
    assert(#queue.queue==0 and #after==1 and after[1].id==unpaid[1].id and #firstFull.effects==3,
        'independent tail retried the refused first return or lost its exact debt')

    local boundaries=fixture(client,{multi=true,direct=true,separateSources=true,alreadyHeld=true})
    local e,t,q=boundaries.env,boundaries.t,boundaries.queue
    local first,sibling=unpack(boundaries.returnedRows)
    assert(t.ActionQueuePolicy.returnFailureIndependent(q,first),'exact claimed sibling did not qualify refusal isolation')
    local source,destination=sibling.srcContainer,sibling.destContainer
    sibling.srcContainer,sibling.destContainer=destination,source
    assert(not t.ActionQueuePolicy.returnFailureIndependent(q,first),'reverse movement inherited claimed sibling failure isolation')
    sibling.srcContainer,sibling.destContainer=source,destination
    local token=sibling.toolkitQueueOperation
    sibling.toolkitQueueOperation={}
    assert(not t.ActionQueuePolicy.returnFailureIndependent(q,first),'foreign operation token inherited claimed sibling failure isolation')
    sibling.toolkitQueueOperation=token
    local foreign=e.ISInventoryTransferUtil.newInventoryTransferAction(boundaries.player,boundaries.book(8199,boundaries.inventory),
        boundaries.inventory,boundaries.secondSource)
    foreign:setAllowMissingItems(true)
    t.ActionQueueOperations.adopt(foreign,token);t.BulkActions.guardTransfer(foreign)
    q.queue[2]=foreign
    assert(not t.ActionQueuePolicy.returnFailureIndependent(q,first),'unclaimed native transfer inherited a sibling location capability')
    q.queue[2]=sibling
    table.insert(q.queue,3,sibling)
    assert(not t.ActionQueuePolicy.returnFailureIndependent(q,first),'duplicate sibling queue row qualified refusal isolation')
    table.remove(q.queue,3)
    assert(t.ActionQueuePolicy.returnFailureIndependent(q,first),'rejected foreign suffix poisoned the untouched claimed batch')
    for _,row in ipairs(boundaries.returnedRows)do
        boundaries.start(row);boundaries.deliver(row);boundaries.dispatch(row,'perform')
    end
    boundaries.start(boundaries.tail);boundaries.dispatch(boundaries.tail,'perform')
    assert(#q.queue==0 and #boundaries.effects==4)

    local kept=fixture(client,{multi=true,direct=true,dormant=true,cancelBeforeExpansion=true,keepBeforeCancel=true})
    assert(#kept.returnedRows==1 and kept.returnedRows[1].item==kept.borroweds[2]
        and kept.borroweds[1]:getContainer()==kept.inventory and allocations(kept,kept.originalReturn)==0,
        'batch cancellation resurrected the explicitly kept native loan')
    local returned=kept.returnedRows[1]
    kept.start(returned);kept.deliver(returned);kept.dispatch(returned,'perform')
    local states={}
    for _,loan in ipairs(kept.t.ActionQueueSettlement.operationState(kept.reading).borrowings)do states[loan.id]=loan.state end
    assert(states[kept.borroweds[1]:getID()]=='waived'and states[kept.borroweds[2]:getID()]=='completed'
        and kept.borroweds[1]:getContainer()==kept.inventory and kept.borroweds[2]:getContainer()==kept.source
        and #kept.effects==3 and #kept.t.ActionQueueSettlement.blockedReturns(kept.player)==0,
        'dormant cancellation cleanup changed the native Keep or omitted its independent paid loan')
    assert(kept.queue.current==kept.tail)
    kept.start(kept.tail);kept.dispatch(kept.tail,'perform');assert(#kept.queue.queue==0)

    for _,canceled in ipairs({false,true})do
        local f=fixture(client,{multi=true,direct=true,dormant=true,cancelBeforeExpansion=canceled,alreadyHeld=true})
        if canceled then
            assert(#f.returnedRows==#f.loans and f.expansion.toolkitQueueOperation~=f.canceledToken
                and allocations(f,f.expansion)==1,'cancellation did not activate its one dormant native cleanup owner')
            for _,returned in ipairs(f.returnedRows)do
                assert(f.queue.current==returned)
                f.start(returned);f.deliver(returned);f.dispatch(returned,'perform')
            end
            batchStates(f,'completed')
        else
            batchStates(f,'active')
            assert(not f.returnedRows and #f.effects==#f.loans and allocations(f,f.expansion)==0)
        end
        assert(f.queue.current==f.tail)
        f.start(f.tail);f.dispatch(f.tail,'perform')
        assert(#f.queue.queue==0)
    end
end

-- A private opt-in gate runs before Java can allocate the cleanup. Refusal
-- and unavailable observations retain the exact debt without any deferred equip.
for _,client in ipairs({false,true}) do
    for _,result in ipairs({'declined','unknown','error'}) do
        local f=fixture(client,{veto=true,admit=function(_,action)
            assert(not action.action and not action.started,'cleanup admission ran after native allocation')
            if result=='error' then error('admission unavailable') end
            if result=='declined' then return false end
        end})
        debt(f)
        assert(f.admitCalls==1 and not f.t.ActionQueueSettlement.earned(f.restoreHandle)
            and f.player:getPrimaryHandItem()==f.borrowed and not f.restore.action,
            'declined admission restored a hand, earned an effect or retried its callback')
        -- A late begin on the retired Lua object must not turn a sticky veto
        -- into native execution after the independent tail already owns begin.
        f.restore:begin();f.queue:tick()
        assert(f.admitCalls==1 and allocations(f,f.restore)==0 and f.returnCalls==nil)
        tail(f)
    end
    local f=fixture(client,{admit=function()return true end})
    assert(f.admitCalls==1)
    finish(f,f.restore)
    assert(f.queue.current==f.continuation and f.t.ActionQueueSettlement.earned(f.restoreHandle),
        'accepted opt-in cleanup lost its ordinary native effect gate')
    local unrelated=fixture(client,{enrolled=false,admit=function()error('unenrolled action called admission')end})
    assert(not unrelated.admitCalls and allocations(unrelated,unrelated.restore)==1,
        'an observer without private dependency enrollment acquired admission authority')
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
-- Normal completion and cancellation share the same fallback reservation.
-- Abandoning a claimed expansion before child construction publishes its exact
-- unpaid loan and releases independent work without synthesizing a return.
for _,client in ipairs({false,true}) do
    for _,canceled in ipairs({false,true}) do
        local f=fixture(client,{claim=true,reserve=true,abandonExpansion=true,cancelBeforeExpansion=canceled})
        local settlement,q=f.t.ActionQueueSettlement,f.queue
        local notices=settlement.blockedReturns(f.player)
        assert(f.abandoned and not f.restore and not f.continuation and f.returnCalls==nil
            and q.current==f.tail and #q.queue==1 and allocations(f,f.originalReturn)==0
            and #notices==1 and notices[1].itemId==f.borrowed:getID()
            and f.borrowed:getContainer()==f.inventory and loanState(f)=='active',
            'claimed early exit lost normal-path fallback debt or blocked the independent tail')
        assert(not settlement.reserveClaimedReturn(f.expansion,f.loan),
            'retired claimed expansion reacquired fallback debt ownership')
        f.start(f.tail);f.dispatch(f.tail,'perform')
        local after=settlement.blockedReturns(f.player)
        assert(#q.queue==0 and #after==1 and after[1].id==notices[1].id and #f.effects==f.initialEffects+1)
    end
    local unclaimed=fixture(client,{reserveDenied=true})
    assert(unclaimed.queue.current==unclaimed.restore and allocations(unclaimed,unclaimed.restore)==1)
    local f=fixture(client,{claim=true,reserve=true})
    finish(f,f.restore)
    f.start(f.continuation);f.dispatch(f.continuation,'perform')
    assert(f.returnCalls==1 and f.returned and f.queue.current==f.returned)
    f.start(f.returned);f.deliver(f.returned);f.dispatch(f.returned,'perform')
    assert(f.queue.current==f.tail and loanState(f)=='completed'
        and #f.t.ActionQueueSettlement.blockedReturns(f.player)==0,
        'normal child enrollment did not replace its fallback reservation')
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
    local visible,status=settlement.waitingForHandAuthority(f.queue,f.restore)
    assert(visible and status=='waiting' and not settlement.waitingForHandAuthority(f.queue,f.tail))
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
    local visible,status=f.t.ActionQueueSettlement.waitingForHandAuthority(f.queue,f.restore)
    assert(visible and status=='waiting' and allocations(f,f.tail)==0, 'Keep dismissed the unresolved hand episode')
    f.acknowledge(f.restore,'rejected');f.queue:tick()
    assert(not f.t.ActionQueueSettlement.waitingForHandAuthority(f.queue,f.restore))
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
    local pending,reason=f.t.ActionQueueSettlement.waitingForHandAuthority(f.queue,f.restore)
    assert(pending and reason=='waiting','local completion hid the pending Host outcome')
    f.advance(30001);f.queue:tick()
    local notice=debt(f)
    local expiredRevision=f.t.ActionQueueSettlement.blockedReturnInfo(f.player).revision
    local visible,status=f.t.ActionQueueSettlement.waitingForHandAuthority(f.queue,f.restore)
    assert(visible and status=='unknown','expired authority still advertised a pending confirmation')
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
local function saturation(client,withSourceGuard,admission)
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
    local lastOptions={alreadyHeld=true,sourceGuard=withSourceGuard}
    if admission then
        lastOptions.heldVeto=true
        lastOptions.admit=function(value)return value.admitCalls>1 end
    end
    f=fixture(client,lastOptions,f,33)
    if not admission then reject(f) end
    f.queue:tick()
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
    if admission then
        assert(f.admitCalls==1 and allocations(f,f.restore)==0,
            'freeing debt capacity retried a declined admission or allocated stale cleanup')
    end
    tail(f)
    return f,retired
end
saturation(false,true,true)
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
