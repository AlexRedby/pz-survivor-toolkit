-- Source-backed composition; Java allocation/transport/world state is modeled.
-- This is deliberately not Host authority or packet ordering evidence.
local checks={'plain','singleton-guarded','merge-preserving','return-failure'}
if not NativeActionRoot or not ((P4TidySource and P4RestoreSource and P4RestoreFloorSource)or NativeP4TidySource)then
    for _,id in ipairs(checks)do
        if TestCoverage then TestCoverage(id,'skipped','Native Lua and selected P4 source inputs are required.')end
    end
    return
end
local create=assert(loadfile(ProjectRoot..'/tests/support/borrowing_composition.lua'))()
local function run(mode,client)
    local f=create(client);local e=f.env;local toolkit=e.PZSurvivorToolkit
    local book=f.book(101)
    e.ISInventoryPaneContextMenu.onLiteratureItems({book},0)
    local q=f.queue
    assert(#q.queue==4 and toolkit.ActionQueueApproach.isContainer(q.queue[1],f.source,f.player),
        'real literature producer must defer approach before pickup/read/native return')
    local approach,pickup,reading,returned=unpack(q.queue)
    assert(pickup.Type=='ISInventoryTransferAction'and reading.Type=='ISReadABook'and returned.allowMissingItems==true)
    assert(approach.toolkitQueueOperation==pickup.toolkitQueueOperation and pickup.toolkitQueueOperation==reading.toolkitQueueOperation)
    if mode~='plain'then toolkit.BulkActions.guardTransfer(pickup,mode=='merge-preserving')end
    local pending=assert(toolkit.ActionQueueSettlement.operationState(pickup))
    assert(#pending.borrowings==1 and pending.borrowings[1].state~='active','enqueue must not earn a pickup')
    f.start(approach);f.dispatch(approach,'perform')
    assert(q.current.Type=='ISWalkToTimedAction','deferred real container helper did not insert native walking')
    local walk=q.current;f.player.square=f.adjacent;f.dispatch(walk,'perform')
    assert(q.current==pickup and pickup.action,'full native first begin failed to reach pickup')
    if client then
        -- This public map is only the Java request-observer lookup hint. Its
        -- publication proves Failure.begin accepted the actual completed
        -- approach history; it grants neither receipt nor refusal authority.
        assert(toolkit.ActionQueueTransferRequests.pending[f.player]==pickup,
            'first client begin failed to publish its request observation after the completed native approach')
        assert(toolkit.ActionQueuePickupFailure.nativeRequestState(pickup)==nil,
            'offline pre-start observation must not fabricate a Java request receipt')
    end
    f.start(pickup);f.deliver(pickup);f.dispatch(pickup,'perform')
    local earned=assert(toolkit.ActionQueueSettlement.operationState(reading))
    assert(#earned.borrowings==1 and earned.borrowings[1].state=='active'and book.container==f.inventory,
        'actual first pickup lifecycle did not earn its borrowing')
    f.dispatch(reading,'perform')
    assert(q.current==returned,'read completion lost native optional return')
    f.start(returned);f.deliver(returned);f.dispatch(returned,'perform')
    assert(book.container==f.source and #q.queue==0,'native source return did not settle its exact borrowed item')
    print('PASS borrowing composition '..mode..': native literature producer, deferred approach, real begin/observers and return')
end
local function merge(mode,client)
    local f=create(client);local e=f.env;local toolkit=e.PZSurvivorToolkit;local q=f.queue
    f.player.square=f.adjacent
    local one,two=f.book(201),f.book(202)
    local command=toolkit.ActionQueueOperations.command(f.player,e.ISInventoryPaneContextMenu.transferIfNeeded,f.list({one,two}))
    toolkit.ActionQueueOperations.run(function()e.ISTimedActionQueue.add(command)end)
    f.start(command)
    assert(#q.queue==3,'actual native array producer did not enqueue adjacent pickups inside its command')
    local first,child=q.queue[2],q.queue[3]
    if mode~='plain'then
        for _,action in ipairs({first,child})do toolkit.BulkActions.guardTransfer(action,mode=='merge-preserving')end
    end
    f.dispatch(command,'perform')
    assert(q.current==first and first.action and not child.action,'first native pickup must begin synchronously before its sibling')
    f.start(first);f.deliver(first);f.dispatch(first,'perform')
    if mode=='singleton-guarded'then
        assert(q.current==child and child.item==two,'singleton native merge exclusion was lost')
        f.start(child);f.deliver(child);f.dispatch(child,'perform')
    else
        assert(next(child)==nil and q:indexOf(child)==-1,'native grouped pickup must remove and wipe the actual child')
    end
    local earned=assert(toolkit.ActionQueueSettlement.operationState(first)).borrowings
    assert(#earned==2 and earned[1].state=='active'and earned[2].state=='active',
        'native neighboring pickup execution did not earn both original borrowing episodes')
    assert(one.container==f.inventory and two.container==f.inventory and #f.effects==2 and #q.queue==0,
        'native neighboring pickup effects must occur once each')
end
local function directProducer(singleton,client)
    local f=create(client);local e=f.env;local toolkit=e.PZSurvivorToolkit;local q=f.queue
    f.player.square=f.adjacent
    local one,two=f.book(501),f.book(502)
    assert(#q.queue==0,'direct native producer must enter an empty queue')
    if singleton then
        -- The shipped producer installs the actual guard before enqueueing.
        -- Neither the transfer constructor nor any begin/observer is replaced.
        local first=toolkit.BulkActions.transfer(f.player,one)
        assert(q.current==first and first.action and #q.queue==1,
            'first real Bulk transfer did not begin before the next producer call')
        toolkit.BulkActions.transfer(f.player,two)
    else
        -- No Operations scope: the actual Approach wrapper consequently keeps
        -- this native synchronous producer synchronous, even with full hooks.
        e.ISInventoryPaneContextMenu.transferIfNeeded(f.player,f.list({one,two}))
    end
    local first,child=q.queue[1],q.queue[2]
    local allocation=f.engineTrace[1]
    assert(#q.queue==2 and first.item==one and child.item==two and first.action and not child.action)
    assert(allocation.event=='native-allocation'and allocation.action==first and allocation.current==first
        and allocation.queueSize==1 and allocation.borrowings==0,
        'full first begin must precede sibling enqueue and Compat post-enqueue pickup preparation')
    assert(first.begin==e.ISBaseTimedAction.begin and first.toolkitQueueOperation~=child.toolkitQueueOperation,
        'direct native additions must keep full begin and their independent operation ownership')
    if singleton then
        assert(first.onCompleteFunc==first.toolkitQueueSafeOnComplete and first.onCompleteFunc~=nil
            and toolkit.BulkActions.isGuardedTransfer(first,e.ISInventoryTransferAction.stop),
            'real Bulk producer lost its pre-enqueue singleton guard')
    else
        assert(first.onCompleteFunc==nil,'plain direct producer acquired a singleton merge sentinel')
    end
    local prepared=assert(toolkit.ActionQueueSettlement.operationState(first)).borrowings
    assert(#prepared==1 and prepared[1].state~='active','post-enqueue observation must prepare without earning')
    f.start(first);f.deliver(first);f.dispatch(first,'perform')
    local earned=assert(toolkit.ActionQueueSettlement.operationState(first)).borrowings
    assert(#earned==1 and earned[1].state=='active'and one.container==f.inventory and two.container==f.source,
        'synchronously begun first pickup failed to earn its exact effect after post-enqueue preparation')
    assert(q.current==child and child.item==two and child.action and next(child)~=nil,
        'independent direct additions must not be merged across operation tokens')
    f.start(child);f.deliver(child);f.dispatch(child,'perform')
    local second=assert(toolkit.ActionQueueSettlement.operationState(child)).borrowings
    assert(#second==1 and second[1].state=='active'and two.container==f.inventory and #f.effects==2 and #q.queue==0,
        'direct native sibling lost its own borrowing or repeated a pickup effect')
end
local function stopOrder(mode,client)
    local f=create(client);local e=f.env;local toolkit=e.PZSurvivorToolkit;local q=f.queue
    e.ISInventoryPaneContextMenu.onLiteratureItems({f.book(401)},0)
    local approach,pickup=unpack(q.queue)
    if mode~='plain'then toolkit.BulkActions.guardTransfer(pickup,mode=='merge-preserving')end
    f.start(approach);f.dispatch(approach,'perform')
    local walk=q.current;f.player.square=f.adjacent;f.dispatch(walk,'perform')
    f.start(pickup)
    local token,transaction=pickup.toolkitQueueOperation,pickup.transactionId
    assert(pickup.begin==e.ISBaseTimedAction.begin and toolkit.ActionQueueLifecycle.hasNativeStopBridge(),
        'composition must retain the full production begin and stop bridge')
    if client then f.transactions[transaction].status='rejected'end
    local boundary=#f.engineTrace
    pickup:stop() -- Bulk guard (when selected), native transfer stop, Queue.stop, native Base.stop.
    pickup.action.removed=true
    assert(#q.queue==0 and q.current==nil and token.toolkitCancelled and #f.effects==0,
        'unearned native pickup stop must reset safely without fabricating borrowing effects')
    assert(toolkit.ActionQueueTransferRequests.pending[f.player]==nil,
        'native fallback stop left a stale Java request-observer lookup hint')
    local trace=f.engineTrace
    local guarded=toolkit.BulkActions.isGuardedTransfer(pickup,e.ISInventoryTransferAction.stop)
    if client and guarded then
        assert(trace[boundary+1].event=='transaction-remove'and trace[boundary+1].id==transaction
            and trace[boundary+1].cancelled==false and pickup.transactionId==0,
            'Bulk stop must retire rejected client transaction before native stop cancellation')
        assert(trace[boundary+2].id==0 and trace[boundary+2].cancelled==true,
            'actual native transfer stop must run after Bulk clears its transaction')
    else
        assert(trace[boundary+1].event=='transaction-remove'and trace[boundary+1].id==transaction
            and trace[boundary+1].cancelled==true,'plain native transfer stop did not cancel its own transaction')
    end
    assert(trace[#trace].event=='native-base-cleanup','full Queue.stop must delegate the unhandled stop to native Base.stop')
end
for _,mode in ipairs({'plain','singleton-guarded','merge-preserving'})do
    for _,client in ipairs({false,true})do run(mode,client);merge(mode,client);stopOrder(mode,client)end
    if mode~='merge-preserving'then
        for _,client in ipairs({false,true})do directProducer(mode=='singleton-guarded',client)end
    end
    if TestCoverage then TestCoverage(mode,'passed')end
end
local function returnFailure(mode,client)
    local f=create(client);local e=f.env;local toolkit=e.PZSurvivorToolkit;local q=f.queue
    local borrowed,tailBook=f.book(301),f.book(302,f.inventory)
    e.ISInventoryPaneContextMenu.onLiteratureItems({borrowed},0)
    e.ISInventoryPaneContextMenu.onLiteratureItems({tailBook},0)
    local approach,pickup,reading,returned,tail=unpack(q.queue)
    assert(returned.allowMissingItems and tail.Type=='ISReadABook'and tail.toolkitQueueOperation~=reading.toolkitQueueOperation)
    if mode~='plain'then toolkit.BulkActions.guardTransfer(pickup,mode=='merge-preserving')end
    f.start(approach);f.dispatch(approach,'perform')
    local walk=q.current;f.player.square=f.adjacent;f.dispatch(walk,'perform')
    f.start(pickup);f.deliver(pickup);f.dispatch(pickup,'perform')
    assert(toolkit.ActionQueueSettlement.operationState(reading).borrowings[1].state=='active')
    f.source.room=false
    f.dispatch(reading,'perform')
    assert(q.current==returned and returned.action and not returned:isStarted())
    assert(returned:isValid()==false,'real native admission must reject the now-full return destination')
    returned.action.removed=true -- Java removes invalid actions before start, without stop().
    q:tick()
    assert(q.current==tail and q:indexOf(returned)==-1 and not tail.toolkitQueueOperation.toolkitCancelled,
        'failed optional return discarded the independent native tail')
    assert(borrowed.container==f.inventory and #f.effects==1,'failed return must leave the earned item in the actor root')
    local failures=toolkit.ActionQueueExecution.blockedReturns(f.player)
    assert(#failures==1 and failures[1].state=='blocked'and failures[1].itemId==borrowed:getID(),
        'failed optional return must retain one exact blocked debt')
    local debt=toolkit.ActionQueueSettlement.operationState(reading).borrowings[1]
    assert(debt.state=='active','native admission failure silently settled or waived the earned borrowing')
    f.dispatch(tail,'perform')
    assert(#q.queue==0 and borrowed.container==f.inventory and #f.effects==1,'independent tail replayed the blocked return')
    print('PASS borrowing composition return-failure: exact debt retained, no return effect, independent native tail completed')
end
for _,mode in ipairs({'plain','singleton-guarded','merge-preserving'})do
    for _,client in ipairs({false,true})do returnFailure(mode,client)end
end
if TestCoverage then TestCoverage('return-failure','passed')end
