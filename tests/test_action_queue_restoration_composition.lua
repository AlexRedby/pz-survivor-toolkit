-- Actual native reading/transfer producers and Toolkit hooks, with offline
-- Java/server delivery models. These checks do not establish live Host transport.
local checks={'native-return','pending-keep','return-failure','provider-controls',
    'wring-return','wring-keep','wring-refusal','wring-provider-controls'}
if not NativeActionRoot or not ((P4TidySource and P4RestoreSource and P4RestoreFloorSource)or NativeP4TidySource)then
    for _,id in ipairs(checks)do
        if TestCoverage then TestCoverage(id,'skipped','Native Lua and selected P4 source inputs are required.')end
    end
    return
end
local create=assert(loadfile(ProjectRoot..'/tests/support/borrowing_composition.lua'))()
local function loan(client)
    local f=create(client,{p4=false,carried=true})
    local e=f.env;local toolkit=e.PZSurvivorToolkit
    assert(e.P4TidyUpMeister==nil and not e.getActivatedMods():contains('P4TidyUpMeister'),
        'own observation requires both actual P4 absence and an unselected provider')
    assert(toolkit.ActionQueuePolicy.isCarriedContainer(f.source,f.player),
        'fixture must use a native-shaped carried InventoryContainer owner')
    local book=f.book(601)
    e.ISInventoryPaneContextMenu.readItem(book,0)
    local q=f.queue
    assert(#q.queue==4,'actual native readItem must retain carried approach/fetch/read/return topology')
    local approach,pickup,reading,returned=unpack(q.queue)
    assert(toolkit.ActionQueueApproach.isContainer(approach,f.source,f.player)
        and pickup.Type=='ISInventoryTransferAction'and reading.Type=='ISReadABook'
        and returned.Type=='ISInventoryTransferAction'and returned.allowMissingItems==true
        and returned.srcContainer==f.inventory and returned.destContainer==f.source,
        'own observation replaced the native carried read producer or return')
    local before=assert(toolkit.ActionQueueSettlement.operationState(pickup))
    assert(#before.borrowings==1 and before.borrowings[1].state=='prepare',
        'pre-enqueue source observation must prepare exactly one unearned borrowing')
    assert(not toolkit.ActionQueueSettlement.requiredStep(returned)
        and not toolkit.ActionQueueSettlement.isCleanup(returned),
        'ordinary native return acquired required cleanup authority')
    for _,step in ipairs(before.steps)do
        assert(not step.plannedTransfer,'enqueue must not bind an execution/planned-return capability')
    end
    f.start(approach);f.dispatch(approach,'perform')
    assert(q.current==pickup and pickup.action,'carried approach must reach the actual native fetch without a walk')
    local allocation
    for _,entry in ipairs(f.engineTrace)do if entry.event=='native-allocation'and entry.action==pickup then allocation=entry end end
    assert(allocation and allocation.borrowings==1,
        'own borrowing observation must precede the native fetch allocation')
    f.start(pickup);f.deliver(pickup);f.dispatch(pickup,'perform')
    local earned=assert(toolkit.ActionQueueSettlement.operationState(reading))
    assert(q.current==reading and #earned.borrowings==1 and earned.borrowings[1].state=='active'
        and book.container==f.inventory and #f.effects==1,
        'only the real completed native fetch may earn its exact item loan')
    f.borrowed,f.reading,f.returned=book,reading,returned
    return f
end
local function nativeReturn(client)
    local f=loan(client);local t=f.env.PZSurvivorToolkit;local q=f.queue
    f.dispatch(f.reading,'perform')
    assert(q.current==f.returned,'actual read completion must preserve its single native return')
    f.start(f.returned);f.deliver(f.returned);f.dispatch(f.returned,'perform')
    local state=assert(t.ActionQueueSettlement.operationState(f.reading))
    assert(#q.queue==0 and f.borrowed.container==f.source and #f.effects==2
        and state.borrowings[1].state=='completed',
        'native return must pay the earned loan once without a second restoration producer')
    if not client then assert(f.player.readCount==1,'offline SP native reading body must execute once')end
end
local function pendingKeep(client)
    local f=loan(client);local t=f.env.PZSurvivorToolkit;local token=f.reading.toolkitQueueOperation
    local kept,reason=t.ActionQueue.cancel(f.queue,f.returned)
    assert(kept,'ordinary pending Keep must remain available: '..tostring(reason))
    local state=assert(t.ActionQueueSettlement.operationState(f.reading))
    assert(state.borrowings[1].state=='waived'and f.queue.current==f.reading
        and not token.toolkitCancelled and f.queue:indexOf(f.returned)==-1
        and f.borrowed.container==f.inventory,
        'Keep must waive only the exact loan and retain its live reading body')
    f.dispatch(f.reading,'perform')
    assert(#f.queue.queue==0 and f.borrowed.container==f.inventory and #f.effects==1,
        'kept loan was returned/replayed or prevented native reading completion')
    if not client then assert(f.player.readCount==1,'Keep cancelled the offline SP native reading body')end
end
local function returnFailure(client)
    local f=loan(client);local e=f.env;local t=e.PZSurvivorToolkit;local q=f.queue
    local tailBook=f.book(602,f.inventory)
    e.ISInventoryPaneContextMenu.readItem(tailBook,0)
    local tail=q.queue[#q.queue]
    assert(tail.Type=='ISReadABook'and tail.toolkitQueueOperation~=f.reading.toolkitQueueOperation)
    f.source.room=false
    f.dispatch(f.reading,'perform')
    assert(q.current==f.returned and f.returned.action and not f.returned:isStarted()
        and f.returned:isValid()==false,'actual native admission must reject the now-full carried source')
    f.returned.action.removed=true -- Java removes invalid actions before start, without stop().
    q:tick()
    assert(q.current==tail and q:indexOf(f.returned)==-1 and not tail.toolkitQueueOperation.toolkitCancelled,
        'failed optional native return discarded its independent reading tail')
    local failures=t.ActionQueueExecution.blockedReturns(f.player)
    local state=assert(t.ActionQueueSettlement.operationState(f.reading))
    assert(#failures==1 and failures[1].state=='blocked'and failures[1].itemId==f.borrowed:getID()
        and state.borrowings[1].state=='active'and f.borrowed.container==f.inventory,
        'source-full admission must retain the exact unpaid loan and blocked debt')
    f.dispatch(tail,'perform')
    assert(#q.queue==0 and f.borrowed.container==f.inventory and #f.effects==1,
        'independent tail replayed the failed return')
end
local function controls(client)
    do
        local f=create(client,{p4=false,carried=true})
        local e=f.env;local t=e.PZSurvivorToolkit
        local contains=e.ItemContainer.chainContainsContainingItem
        assert(e.getClassSimpleName(contains)=='LuaJavaInvoker',
            'native containment fixture lost its exact Java invoker identity')
        local replacement=function(...)return contains(...)end
        assert(e.getClassSimpleName(replacement)=='KahluaClosure',
            'a replacement Lua callback borrowed the canonical containment invoker identity')
        local book=f.book(604)
        -- This actual helper is explicit manual movement, outside the native
        -- readItem producer receipt. It must never become an automatic loan.
        e.ISInventoryPaneContextMenu.transferIfNeeded(f.player,book)
        local pickup=f.queue.current
        assert(pickup and pickup.Type=='ISInventoryTransferAction')
        local state=assert(t.ActionQueueSettlement.operationState(pickup))
        assert(#state.borrowings==0,'explicit manual carried transfer acquired an automatic return loan')
        for _,step in ipairs(state.steps)do
            assert(not step.observedPreparation,'explicit manual transfer acquired own preparation observation')
        end
        assert(not t.ActionQueueRestoration.observeNative(pickup),
            'post-dispatch call reconstructed an ordinary producer receipt')
    end
    do
        local f=create(client,{p4=false,carried=true,readProducer='transferIfNeeded'})
        local e=f.env;local t=e.PZSurvivorToolkit
        local book=f.book(605)
        -- Same native filename and file hash, different executable source role.
        -- The genuine transfer helper is captured as readItem before wrapping.
        e.ISInventoryPaneContextMenu.readItem(f.player,book)
        local pickup
        for _,action in ipairs(f.queue.queue)do
            if action.Type=='ISInventoryTransferAction'and action.destContainer==f.inventory then pickup=action;break end
        end
        assert(pickup,'same-file role control must exercise an actual native fetch')
        local state=assert(t.ActionQueueSettlement.operationState(pickup))
        assert(#state.borrowings==0,'another native same-file callback inherited readItem borrowing authority')
        for _,step in ipairs(state.steps)do
            assert(not step.observedPreparation,'another same-file callback acquired preparation observation')
        end
    end
    do
        local original,armed,changed,foreignCalls=nil,false,false,0
        local foreign=function()foreignCalls=foreignCalls+1;return false end
        local f=create(client,{p4=false,carried=true,metadataHook=function(env,callback)
            -- Reenter only at this exact original source qualification, while
            -- the stable delegate still returns the genuine native metadata.
            if armed and callback==original then
                armed=false;changed=true
                env.PZSurvivorToolkit.ActionQueueSettlement.rememberPreparation=foreign
            end
        end})
        local e=f.env;local t=e.PZSurvivorToolkit
        original=t.ActionQueueSettlement.rememberPreparation;armed=true
        e.ISInventoryPaneContextMenu.readItem(f.book(606),0)
        assert(changed,'source qualification did not exercise the armed metadata reentry')
        assert(#f.queue.queue==4,'source reentry must preserve native fetch/read/return production')
        local pickup=f.queue.queue[2]
        assert(pickup.Type=='ISInventoryTransferAction'and f.queue.queue[3].Type=='ISReadABook'
            and f.queue.queue[4].allowMissingItems==true,'source rejection replaced the native reading pipeline')
        local state=assert(t.ActionQueueSettlement.operationState(pickup))
        assert(#state.borrowings==0 and foreignCalls==0,
            'metadata reentry enrolled an own loan or executed the replaced Settlement export')
        for _,step in ipairs(state.steps)do
            assert(not step.observedPreparation,'metadata reentry acquired own preparation observation')
        end
    end
    do
        local original,armed,changed=nil,false,false
        local f=create(client,{p4=false,carried=true,metadataHook=function(env,callback)
            if armed and callback==original then
                armed=false;changed=true
                env.P4TidyUpMeister={}
            end
        end})
        local e=f.env;local t=e.PZSurvivorToolkit
        original=t.ActionQueueOperations.producer;armed=true
        e.ISInventoryPaneContextMenu.readItem(f.book(607),0)
        assert(changed and e.P4TidyUpMeister~=nil and not e.getActivatedMods():contains('P4TidyUpMeister'),
            'producer metadata reentry must introduce only the previously absent provider global')
        assert(#f.queue.queue==4,'new provider presence must preserve native fetch/read/return production')
        local pickup=f.queue.queue[2]
        assert(pickup.Type=='ISInventoryTransferAction'and f.queue.queue[3].Type=='ISReadABook'
            and f.queue.queue[4].allowMissingItems==true,'provider reentry replaced the native reading pipeline')
        local state=assert(t.ActionQueueSettlement.operationState(pickup))
        assert(#state.borrowings==0,'newly present provider was snapshotted as permission for own loan observation')
        for _,step in ipairs(state.steps)do
            assert(not step.observedPreparation,'provider metadata reentry acquired own preparation observation')
        end
    end
    for _,options in ipairs({{p4=true,carried=true},{p4=false,p4Selected=true,carried=true},
        {p4=false,carried=true,queue=false}})do
        local f=create(client,options);local e=f.env;local t=e.PZSurvivorToolkit
        local book=f.book(603)
        e.ISInventoryPaneContextMenu.readItem(book,0)
        local pickup
        for _,action in ipairs(f.queue.queue)do
            if action.Type=='ISInventoryTransferAction'and action.destContainer==f.inventory then pickup=action;break end
        end
        assert(pickup,'provider controls must exercise the real native carried fetch')
        -- Disabled editor bookkeeping may have no operation record at all.
        local state=t.ActionQueueSettlement.operationState(pickup)
        if options.queue~=false then assert(state,'selected P4 control lost its ordinary operation record')end
        state=state or {steps={},borrowings={}}
        for _,step in ipairs(state.steps)do
            assert(not step.observedPreparation,'P4-selected/queue-off control created own preparation scope')
        end
        assert(not t.ActionQueueRestoration.observeNative(pickup),
            'P4-selected/queue-off control admitted own restoration observation')
        if options.queue==false then
            assert(#state.borrowings==0,'queue-off control acquired an own borrowing')
        elseif options.p4~=false then
            assert(e.P4TidyUpMeister~=nil and t.ActionQueueCompat.isInstalled('P4TidyUpMeister'),
                'selected-provider control must retain the real P4 integration')
        else
            assert(e.P4TidyUpMeister==nil and e.getActivatedMods():contains('P4TidyUpMeister')
                and #state.borrowings==0,'selected-but-unloaded P4 provider enabled own loan observation')
        end
    end
end
-- The native wring producer has no return. This exercises the shared own
-- producer and pre-native admission through real queue/lifecycle/ledger modules.
local WringScenario=dofile(ProjectRoot..'/tests/native_queue/wring-clothing/shared/QueueWringScenario.lua')
local function wringLoan(client,foreignRole,cleanUISelector,cleanUIContext,compiledSelector)
    local f=create(client,{p4=false,carried=true,canonicalBodyReplacement=client,
        primaryProducer=foreignRole and 'OnSecondWeapon'or nil,
        cleanUISelectorSource=cleanUISelector and CleanUIInventoryPaneSource or nil,
        cleanUISelectorCompiledSource=compiledSelector and CleanUIInventoryPaneCompiledSource or nil,
        cleanUIContextSource=cleanUIContext and CleanUIInventoryContextMenuSource or nil})
    local e,t,q=f.env,f.env.PZSurvivorToolkit,f.queue
    if cleanUISelector then
        local count=0;for _ in pairs(e.ISInventoryPane)do count=count+1 end
        assert(count>128 and getmetatable(e.ISInventoryPane)==e.ISPanel,
            'selected source fixture lost its real large derived pane class: '..tostring(count))
    end
    local item=f.garment(701)
    e.ISInventoryPaneContextMenu.onWringClothing({item},0)
    if cleanUISelector then
        local installed,reason=t.ActionQueueTidyIntent.status()
        assert(installed,'selected derived UI did not install own intent: '..tostring(reason))
    end
    WringScenario.checkProducer(q.queue,'toolkit','target')
    local approach,pickup,body=unpack(q.queue)
    assert(body.Type=='ISWringClothing'and body.item==item)
    local before=assert(t.ActionQueueSettlement.operationState(body))
    assert(#before.borrowings==1 and before.borrowings[1].state=='prepare',
        'native producer did not enroll an unearned exact wring loan')
    for _,step in ipairs(before.steps)do assert(not step.plannedTransfer,'optional return was prebound before earning')end
    e.ISInventoryPaneContextMenu.onWringClothing({f.garment(702,f.inventory)},0)
    local tail=q.queue[#q.queue]
    WringScenario.checkProducer({tail},'toolkit','tail')
    f.start(approach);f.dispatch(approach,'perform')
    f.start(pickup);f.deliver(pickup);f.dispatch(pickup,'perform')
    item=assert(f.inventory:getItemById(item:getID()))
    local returned=q.queue[2]
    assert(q.current==body and returned and returned.Type=='ISInventoryTransferAction'
        and returned.item==item and returned.srcContainer==f.inventory and returned.destContainer==f.source
        and returned.allowMissingItems==true and q.queue[3]==tail and #q.queue==3,
        'earned pickup must insert one exact optional return after its body and before the independent tail: '..tostring(t.ActionQueueSettlement.operationState(body).optionalReturnState))
    assert(not body.toolkitQueueLinked and not returned.toolkitQueueLinked
        and not t.ActionQueueSettlement.requiredStep(returned)and not t.ActionQueueSettlement.isCleanup(returned),
        'optional restoration acquired linked or required-cleanup authority')
    local active=assert(t.ActionQueueSettlement.operationState(body))
    assert(active.borrowings[1].state=='active')
    for _,step in ipairs(active.steps)do assert(not step.plannedTransfer,'created optional return bypassed pending Keep')end
    f.borrowed,f.wringBody,f.returned,f.tail=item,body,returned,tail
    return f
end
local function wringComplete(f,client)
    -- Server delivery is modeled explicitly; the actual native complete body
    -- caps the same garment. No client queue callback supplies that authority.
    if client then assert(f.wringBody:complete())end
    f.dispatch(f.wringBody,'perform')
    assert(f.borrowed:getWetness()==10,'native wring lost its exact wetness effect')
end
local function wringReturn(client)
    local f=wringLoan(client);local t=f.env.PZSurvivorToolkit
    wringComplete(f,client)
    assert(f.queue.current==f.returned,'native advancement lost the qualified generated return')
    f.start(f.returned);f.deliver(f.returned);f.dispatch(f.returned,'perform')
    assert(f.queue.current==f.tail and f.borrowed.container==f.source and #f.effects==2
        and t.ActionQueueSettlement.operationState(f.wringBody).borrowings[1].state=='completed',
        'generated return did not pay its exact loan once')
    f.dispatch(f.tail,'perform');assert(#f.queue.queue==0)
end
local function wringKeep(client)
    local f=wringLoan(client);local t=f.env.PZSurvivorToolkit
    local kept,reason=t.ActionQueue.cancel(f.queue,f.returned)
    assert(kept,'generated pending Keep unavailable: '..tostring(reason))
    assert(f.queue.current==f.wringBody and f.queue:indexOf(f.returned)==-1
        and t.ActionQueueSettlement.operationState(f.wringBody).borrowings[1].state=='waived')
    wringComplete(f,client);assert(f.queue.current==f.tail)
    f.dispatch(f.tail,'perform')
    assert(#f.queue.queue==0 and f.borrowed.container==f.inventory and #f.effects==1,
        'pending Keep replayed/returned the item or cancelled its wring body')
end
local function laterEquipment(client,mode)
    local selectedContext=mode:find('^cleanui%-')~=nil
    local f=wringLoan(client,mode=='source-role',mode=='cleanui'or selectedContext,selectedContext,mode=='cleanui-compiled')
    local e,t,q=f.env,f.env.PZSurvivorToolkit,f.queue
    f.start(f.wringBody)
    f.wringBody.action.getJobDelta=function()return .5 end -- Java progress model.
    local native,token=f.wringBody.action,f.wringBody.toolkitQueueOperation
    local selected=mode=='unrelated'and f.garment(709,f.inventory)or f.borrowed
    local function ownUpdate()
        for _,callback in ipairs(f.events.OnPlayerUpdate or {})do callback(f.player)end
    end
    local late=mode=='late-ack'or mode=='late-rejected'or mode=='late-provider-loss'
        or mode=='late-generation'or mode=='late-death'
    if mode=='cleanui-helper-loss'then
        e.ISInventoryPaneContextMenu.cleanUIResetStaleTimedActionRetrigger=function()return false end
    end
    local foreignGetters=0
    if mode=='cleanui-parent-selector'then
        e.ISPanel.getActualItems=e.ISInventoryPane.getActualItems;e.ISInventoryPane.getActualItems=nil
    elseif mode=='cleanui-parent-index'then
        e.ISPanel.__index=function()foreignGetters=foreignGetters+1;error('foreign UI lookup')end
    elseif mode=='cleanui-util-index'then
        e.ISInventoryTransferUtil.newInventoryTransferAction=nil
        setmetatable(e.ISInventoryTransferUtil,{__index=function()foreignGetters=foreignGetters+1;error('foreign transfer helper lookup')end})
    elseif mode=='cleanui-no-parent'then
        setmetatable(e.ISInventoryPane,nil)
    elseif mode=='cleanui-class-equality'then
        e.ISBaseObject.__eq=function()foreignGetters=foreignGetters+1;error('foreign class equality')end
        e.ISUIElement.__index=setmetatable({},e.ISBaseObject)
        assert(not t.ActionQueueTidyIntent.status()and foreignGetters==0,'ancestry proof invoked __eq')
        e.ISBaseObject.__eq=nil;e.ISUIElement.__index=e.ISUIElement
    elseif mode=='cleanui-reentrant'then
        f.setModProbe(function()
            f.setModProbe(nil)
            e.ISPanel.__index=function()foreignGetters=foreignGetters+1;error('reentrant UI lookup')end
        end)
        assert(not t.ActionQueueTidyIntent.status()and foreignGetters==0,
            'mod metadata reentry invalidated ancestry after its last proof')
        e.ISPanel.__index=e.ISPanel
    end
    if mode=='cleanui-parent-selector'or mode=='cleanui-parent-index'or mode=='cleanui-util-index'or mode=='cleanui-no-parent'then
        assert(not t.ActionQueueTidyIntent.status()and foreignGetters==0,
            'changed own helper lookup executed a getter or kept its source proof')
    end
    t.ActionQueueOperations.run(e.ISInventoryPaneContextMenu.OnPrimaryWeapon,{selected},0)
    local equip=q.queue[#q.queue]
    if mode=='cleanui-no-pane-scan'then
        local each=e.pairs
        e.pairs=function(value)assert(value~=e.ISInventoryPane,'own event scanned the UI class');return each(value)end
    end
    assert(equip.Type=='ISEquipWeaponAction'and equip.item==selected and equip.toolkitQueueOperation~=token
        and q.current==f.wringBody and f.wringBody.action==native and not native.stopped,
        'later real equipment command disturbed the progressed wring prefix')
    assert(t.ActionQueueSettlement.operationState(f.wringBody).borrowings[1].state=='active',
        'queued intent alone waived an earned loan')
    if mode=='cancelled'then q:removeFromQueue(equip)end -- Native pending removal, without an effect.
    if mode=='unrelated'or mode=='cancelled'then f.source.room=false end
    wringComplete(f,client)
    if mode=='unrelated'or mode=='cancelled'then
        -- Produce real debt independently of the later command. A successful
        -- effect on another same-type garment must leave that exact debt alone.
        if q.current==f.returned then
            assert(not f.returned:isValid());f.returned.action.removed=true;q:tick()
        end
    else
        assert(not f.returned.action,'dependent optional return allocated native work')
    end
    assert(q.current==f.tail and f.borrowed.container==f.inventory,
        'later exact equipment must retain the existing safe unallocated-return fence')
    if client then assert(f.tail:complete())end
    f.dispatch(f.tail,'perform')
    if mode=='cancelled'then
        ownUpdate() -- Idle pruning owns only our removed, unfinished observations.
        f.player:setPrimaryHandItem(selected);ownUpdate()
        local debts=t.ActionQueueExecution.blockedReturns(f.player)
        assert(#q.queue==0 and #debts==1
            and t.ActionQueueSettlement.operationState(f.wringBody).borrowings[1].state=='active',
            'cancelled queued intent waived an earned loan')
        return
    end
    assert(q.current==equip and equip:isValid())
    if mode=='failed'or mode=='late-rejected'then
        -- Native no-effect completion: already held equipment returns false.
        f.player:setPrimaryHandItem(selected)
    end
    f.start(equip)
    if mode=='unmarked'then equip.toolkitNativeTransaction,equip.toolkitNativeKind=nil,nil end
    if client then
        local result=equip:complete();assert(result==(mode~='failed'and mode~='late-rejected'))
        if mode~='unmarked'and not late then f.acknowledge(equip,result and 'completed'or 'rejected')end
        if mode=='late-replication'then f.player:setPrimaryHandItem(nil)end
    end
    f.dispatch(equip,'perform')
    if late then
        assert(#t.ActionQueueExecution.blockedReturns(f.player)==1,
            'pending native outcome cleared the old debt before its receipt')
        if mode=='late-provider-loss'then e.P4TidyUpMeister={};ownUpdate();e.P4TidyUpMeister=nil end
        if mode=='late-generation'then
            local generation=q.toolkitOperationGeneration
            q.toolkitOperationGeneration=(generation or 0)+1;ownUpdate();q.toolkitOperationGeneration=generation
        end
        if mode=='late-death'then
            local alive=f.player.isDead
            f.player.isDead=function()return true end;ownUpdate();f.player.isDead=alive
        end
        f.acknowledge(equip,mode=='late-rejected'and 'rejected'or 'completed')
        ownUpdate()
    end
    if mode=='late-replication'then
        ownUpdate()
        assert(#t.ActionQueueExecution.blockedReturns(f.player)==1,
            'completed receipt alone waived debt before the exact equipment effect replicated')
        f.player:setPrimaryHandItem(selected);ownUpdate()
    end
    local state=t.ActionQueueSettlement.operationState(f.wringBody)
    local debts=t.ActionQueueExecution.blockedReturns(f.player)
    if mode=='failed'or mode=='unrelated'or mode=='source-role'or mode=='unmarked'
        or mode=='late-rejected'or mode=='late-provider-loss'or mode=='late-generation'or mode=='late-death'
        or mode=='cleanui-helper-loss'or mode=='cleanui-parent-selector'or mode=='cleanui-parent-index'
        or mode=='cleanui-util-index'or mode=='cleanui-no-parent'then
        assert((not state or state.borrowings[1].state=='active')and #debts==1,
            'failed native equipment, hand mutation or unrelated effect waived an earned loan')
    else
        assert(f.player:getPrimaryHandItem()==f.borrowed and state.borrowings[1].state=='waived'and #debts==0,
            'successful later exact native equipment left stale owned restoration debt')
        assert(#f.effects==1 and f.borrowed:getWetness()==10 and #q.queue==0,
            'later equipment replayed the pickup, return, wring or independent tail')
        -- With no private pending receipts the own event has no item/queue lookup.
        f.player.getInventory=function()error('empty own poll inspected inventory')end
        q.indexOf=function()error('empty own poll scanned queue')end
        ownUpdate()
    end
end
local function equipmentBeforeReborrow(mode)
    local f=create(true,{p4=false,carried=true});local e,t,q=f.env,f.env.PZSurvivorToolkit,f.queue
    local item=f.garment(711,f.inventory)
    -- A root-only native producer installs own observation without earning a loan.
    e.ISInventoryPaneContextMenu.onWringClothing({item},0)
    local rootBody=q.current;assert(#q.queue==1)
    f.start(rootBody);assert(rootBody:complete());f.dispatch(rootBody,'perform')
    t.ActionQueueOperations.run(e.ISInventoryPaneContextMenu.OnPrimaryWeapon,{item},0)
    local earlier=q.current
    if mode=='rejected'then f.player:setPrimaryHandItem(item)end
    f.start(earlier)
    assert(earlier:complete()==(mode~='rejected'))
    f.dispatch(earlier,'perform') -- The old native receipt is still pending.
    f.player:setPrimaryHandItem(nil)
    if mode=='outbound'then
        t.ActionQueueOperations.run(function()
            e.ISTimedActionQueue.add(e.ISInventoryTransferUtil.newInventoryTransferAction(
                f.player,item,f.inventory,f.source))
        end)
        local moved=q.current;f.start(moved);f.deliver(moved);f.dispatch(moved,'perform')
    else
        -- Authoritative server relocation can precede client action/hand delivery.
        -- No client transfer callback is invented for that engine-boundary effect.
        f.inventory:DoRemoveItem(item);f.source:AddItem(item)
    end
    item:setWetness(80)
    e.ISInventoryPaneContextMenu.onWringClothing({item},0)
    local approach,pickup,body=unpack(q.queue)
    e.ISInventoryPaneContextMenu.onWringClothing({f.garment(712,f.inventory)},0)
    local tail=q.queue[#q.queue]
    f.start(approach);f.dispatch(approach,'perform')
    f.start(pickup);f.deliver(pickup);f.dispatch(pickup,'perform')
    local returned=q.queue[2]
    t.ActionQueueOperations.run(e.ISInventoryPaneContextMenu.OnPrimaryWeapon,{item},0)
    local cancelled=q.queue[#q.queue]
    f.start(body);assert(body:complete());f.dispatch(body,'perform')
    assert(q.current==tail and not returned.action and q:indexOf(returned)==-1)
    q:removeFromQueue(cancelled) -- This newer command never earns an equipment effect.
    assert(tail:complete());f.dispatch(tail,'perform')
    assert(t.ActionQueueSettlement.operationState(body).borrowings[1].state=='active')
    -- Late replication of the earlier hand state is not a new equipment command.
    f.player:setPrimaryHandItem(item)
    f.acknowledge(earlier,mode=='rejected'and 'rejected'or 'completed')
    for _,callback in ipairs(f.events.OnPlayerUpdate or {})do callback(f.player)end
    assert(t.ActionQueueSettlement.operationState(body).borrowings[1].state=='active'
        and #t.ActionQueueExecution.blockedReturns(f.player)==1,
        'old equipment receipt waived a later borrowing episode: '..mode)
end
local function ownInstallReentry()
    local f=create(false,{p4=false,carried=true,cleanUISelectorSource=CleanUIInventoryPaneSource,
        cleanUIContextSource=CleanUIInventoryContextMenuSource})
    local e,t=f.env,f.env.PZSurvivorToolkit
    local adapters=t.ActionQueueItemEditAdapters
    local register=adapters.registerSourceFactory
    local calls=0
    adapters.registerSourceFactory=function(...)
        e.ISInventoryTransferUtil.newInventoryTransferAction=nil
        setmetatable(e.ISInventoryTransferUtil,{__index=function()calls=calls+1;error('initial helper capture invoked foreign lookup')end})
        return register(...)
    end
    e.ISInventoryPaneContextMenu.onWringClothing({f.garment(713,f.inventory)},0)
    assert(not t.ActionQueueTidyIntent.status()and calls==0,
        'own installation captured helpers after a source-registration reentry')
end
local function wringRefusal(client)
    for _,mode in ipairs({'success','failed','cancelled','unrelated','source-role'})do laterEquipment(client,mode)end
    if client then
        for _,mode in ipairs({'unmarked','late-ack','late-rejected','late-provider-loss','late-generation','late-death','late-replication'})do laterEquipment(client,mode)end
        for _,mode in ipairs({'remote','outbound','rejected'})do equipmentBeforeReborrow(mode)end
    end
    if CleanUIInventoryPaneSource then laterEquipment(client,'cleanui')end
    if CleanUIInventoryContextMenuSource then
        assert(CleanUIInventoryPaneSource,'selected CleanUI context needs its actual selector')
        for _,mode in ipairs({'cleanui-context','cleanui-helper-loss','cleanui-parent-selector','cleanui-parent-index',
            'cleanui-util-index','cleanui-no-parent','cleanui-class-equality','cleanui-reentrant','cleanui-no-pane-scan'})do laterEquipment(client,mode)end
        if CleanUIInventoryPaneCompiledSource then laterEquipment(client,'cleanui-compiled')end
        if not client then ownInstallReentry()end
    end
    if client then
        local f=create(true,{p4=false,carried=true,canonicalBodyReplacement=true,guardLostAtReplacement=true})
        local e,t=f.env,f.env.PZSurvivorToolkit;local item=f.garment(707)
        e.ISInventoryPaneContextMenu.onWringClothing({item},0)
        local approach,pickup,body=unpack(f.queue.queue)
        f.start(approach);f.dispatch(approach,'perform')
        f.start(pickup);f.deliver(pickup);f.dispatch(pickup,'perform')
        local current=assert(f.inventory:getItemById(item:getID()));assert(current~=item and body.item==current)
        local debts=t.ActionQueueExecution.blockedReturns(f.player)
        assert(#debts==1 and debts[1].state=='blocked','lost producer after Host replacement did not retain debt')
        assert(t.ActionQueueExecution.keepReturn(f.player,debts[1].id),'canonical Host debt could not be explicitly kept')
        assert(t.ActionQueueSettlement.operationState(body).borrowings[1].state=='waived')
        assert(body:complete());f.dispatch(body,'perform')
        assert(#f.queue.queue==0 and current.container==f.inventory and #f.effects==1)
    end
    do
        local f=wringLoan(client);local t=f.env.PZSurvivorToolkit
        f.source.room=false;wringComplete(f,client)
        assert(f.queue.current==f.returned and f.returned.action and not f.returned:isValid(),
            'capacity must still be checked by native admission')
        f.returned.action.removed=true;f.queue:tick()
        assert(f.queue.current==f.tail and f.borrowed.container==f.inventory
            and t.ActionQueueSettlement.operationState(f.wringBody).borrowings[1].state=='active')
        local blocked=t.ActionQueueExecution.blockedReturns(f.player)
        assert(#blocked==1 and blocked[1].state=='blocked'and blocked[1].itemId==f.borrowed:getID(),
            'native capacity rejection lost its unpaid generated-return debt')
        f.dispatch(f.tail,'perform');assert(#f.queue.queue==0)
    end
    do
        local f=wringLoan(client);local t=f.env.PZSurvivorToolkit
        local allocations=#f.engineTrace
        t.ActionQueueRestoration.observeNative=function()return false end
        wringComplete(f,client)
        assert(f.queue.current==f.tail and not f.returned.action and f.borrowed.container==f.inventory
            and #f.effects==1,'lost source qualification fell back to executing a generated native transfer')
        local blocked=t.ActionQueueExecution.blockedReturns(f.player)
        assert(#blocked==1 and blocked[1].state=='blocked'and blocked[1].itemId==f.borrowed:getID(),
            'source loss must retain visible unallocated debt without a synthetic native receipt')
        f.dispatch(f.tail,'perform');assert(#f.queue.queue==0)
    end
end
local function wringControls(client)
    do
        local f=create(client,{p4=false,carried=true});local item=f.garment(706)
        f.env.ISInventoryPaneContextMenu.onWringClothing({{items={item,item}}},0)
        local body=f.queue.queue[#f.queue.queue]
        local state=assert(f.env.PZSurvivorToolkit.ActionQueueSettlement.operationState(body))
        assert(#state.borrowings==1 and state.optionalReturnState=='planned',
            'ordinary single-item UI group lost native producer enrollment')
    end
    do
        local f=create(client,{p4=false,carried=true})
        f.env.ISInventoryPaneContextMenu.onWringClothing({f.garment(704),f.garment(705)},0)
        local body=f.queue.queue[#f.queue.queue]
        local state=assert(f.env.PZSurvivorToolkit.ActionQueueSettlement.operationState(body))
        assert(#state.borrowings==0,'unsupported bulk producer partially enrolled optional loans')
    end
    for _,options in ipairs({{p4=true,carried=true},{p4=false,p4Selected=true,carried=true},
        {p4=false,carried=true,queue=false}})do
        local f=create(client,options);local e,t=f.env,f.env.PZSurvivorToolkit
        e.ISInventoryPaneContextMenu.onWringClothing({f.garment(703)},0)
        local pickup,body
        for _,action in ipairs(f.queue.queue)do
            if action.Type=='ISInventoryTransferAction'and action.destContainer==f.inventory then pickup=action end
            if action.Type=='ISWringClothing'then body=action end
        end
        assert(pickup and body,'wring provider control did not invoke the real native chain')
        local state=t.ActionQueueSettlement.operationState(body)or {steps={},borrowings={}}
        for _,step in ipairs(state.steps)do assert(not step.observedPreparation,'provider control enrolled own optional preparation')end
        if options.p4==false then assert(#state.borrowings==0)end
    end
end
for _,entry in ipairs({{'native-return',nativeReturn},{'pending-keep',pendingKeep},
    {'return-failure',returnFailure},{'provider-controls',controls},
    {'wring-return',wringReturn},{'wring-keep',wringKeep},{'wring-refusal',wringRefusal},
    {'wring-provider-controls',wringControls}})do
    for _,client in ipairs({false,true})do entry[2](client)end
    if TestCoverage then TestCoverage(entry[1],'passed')end
end
print('PASS restoration composition: native reading/wringing, earned optional returns, Keep, blocked debt and provider controls in offline SP/Host models')
