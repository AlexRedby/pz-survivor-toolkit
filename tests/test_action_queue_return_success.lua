-- Real Settlement loan/step/receipt logic with the existing explicit engine
-- doubles. This does not qualify native Queue.begin, dispatch or Host transport.
local invoked=false
ReturnSuccessVectors=function(fixtures)
    invoked=true
    local function order(s, current, values)
        -- Keep the actual native queue list identity throughout an episode.
        for key in pairs(s.queue.queue) do s.queue.queue[key]=nil end
        for index,value in ipairs(values) do s.queue.queue[index]=value end
        s.queue.current=current
    end
    local function fixture(client, count)
        local s=fixtures.ownedBatchFixture(client)
        s.client,s.restores,s.observations,s.present=client,{},{},{}
        P4TidyUpMeister=nil
        local selected=false
        s.providerHook=nil
        getActivatedMods=function()
            if s.providerHook then s.providerHook() end
            return {contains=function() return selected end}
        end
        s.selected=function(value) selected=value end
        s.player.getCharacterActions=function()
            return {contains=function(_,native) return s.present[native]==true end}
        end
        s.queue.indexOf=function(self,wanted)
            for index,action in ipairs(self.queue) do if action==wanted then return index end end
            return -1
        end
        local observers={}
        PZSurvivorToolkit.ActionQueueLifecycle={registerObserver=function(name,observer)
            observers[name]=observer;return true
        end}
        PZSurvivorToolkit.ActionQueueTransfers={observeTransfers=function() end}
        for index=1,count or 1 do
            local action=s.action();action.Type='ISEquipWeaponAction'
            assert(s.settlement.cleanup(action,s.handles[1]))
            local value={action=action,effect=false,guard=true,captures=0}
            local spec={guard=function(candidate)
                    if value.guardHook then value.guardHook() end
                    return candidate==action and value.guard
                end,
                capture=function() value.captures=value.captures+1;return {before=true} end,
                observed=function(_,before) assert(before.before);return value.effect end}
            value.spec=spec
            value.handle=assert(s.settlement.observeCleanupEffect(action,spec))
            s.restores[index]=value;s.observations[index]=value.handle
        end
        s.observer=assert(observers['settlement-preparation'])
        s.returner=s.action();s.returner.Type='ISQueueActionsAction'
        assert(s.settlement.cleanup(s.returner,s.handles[1]))
        local values={s.parent}
        for _,value in ipairs(s.restores) do values[#values+1]=value.action end
        values[#values+1]=s.returner;values[#values+1]=s.tail
        order(s,s.parent,values)
        return s
    end
    local function register(s, dependencies)
        return s.settlement.requireBorrowedReturnSuccess(s.handles[1],dependencies or s.observations)
    end
    local function start(s,index,lateStart)
        local value=s.restores[index or 1];local action=value.action
        order(s,action,{action,s.returner,s.tail})
        action.action={};s.present[action.action]=true
        s.settlement.started(action);s.observer.started(action)
        if s.client then
            action.toolkitNativeTransaction,action.toolkitNativeKind=100+(index or 1),action.Type
            if not lateStart then s.receipt(action,'started') end
        end
        assert(s.observer.begin(action,'perform'))
        return value
    end
    local function finish(s,value,effect,outcome,success)
        value.effect=effect==true
        s.observer.finish(value.action,'perform',success~=false)
        if not s.client then s.observer.finish(value.action,'complete',success~=false) end
        if s.client and outcome then s.receipt(value.action,outcome) end
        s.present[value.action.action]=nil
        return s.settlement.completionState(s.queue,value.action)
    end
    local function atReturner(s) order(s,s.returner,{s.returner,s.tail}) end
    local function loanState(s)
        local result=assert(s.settlement.operationState(s.parent))
        for _,loan in ipairs(result.borrowings) do if loan.id==s.items[1]:getID() then return loan.state end end
        error('exact original borrowing missing')
    end
    local function blocked(s,reason,expectedState)
        local debts=s.settlement.blockedReturns(s.player)
        assert(#debts==1 and debts[1].itemId==s.items[1]:getID()
            and debts[1].itemType==s.items[1]:getFullType() and debts[1].state==(expectedState or 'blocked')
            and debts[1].reason==reason,'missing exact visible cleanup dependency debt: '..tostring(reason)
                ..' case='..tostring(s.label)..' count='..#debts..' actual='..tostring(debts[1] and debts[1].reason))
        assert(s.counts()==0 and #s.enqueued==0 and s.items[1]:getContainer()==s.root,
            'failed dependency constructed/enqueued a native return or moved the item')
        assert(loanState(s)=='active' and s.queue.queue[#s.queue.queue]==s.tail,
            'failed dependency paid debt or discarded independent tail')
        return debts[1]
    end

    -- Real completion is the conjunction of callback, exact observed effect
    -- and the matching native Host receipt, not merely continuationState ready.
    for _,client in ipairs({false,true}) do
        local s=fixture(client,2)
        assert(register(s))
        local first=start(s,1)
        assert(finish(s,first,true,client and 'completed' or nil)=='ready')
        assert(s.settlement.earned(first.handle))
        assert(not s.settlement.earned(s.observations[2]) and s.counts()==0)
        local second=start(s,2)
        assert(finish(s,second,true,client and 'completed' or nil)=='ready')
        atReturner(s)
        local returned=assert(s.settlement.enqueueBorrowedReturn(s.handles[1]))
        assert(returned.item==s.items[1] and returned.srcContainer==s.root and returned.destContainer==s.source)
        assert(s.settlement.requiredStep(returned) and s.counts()==1 and #s.enqueued==1)
        assert(loanState(s)=='active','scheduling a return paid the location debt')
        assert(not s.settlement.enqueueBorrowedReturn(s.handles[1]) and s.counts()==1,'return construction replayed')
    end
    for _,firstHalf in ipairs({'effect','receipt','late-start'}) do
        local s=fixture(true);assert(register(s))
        local value=start(s,1,firstHalf=='late-start')
        assert(finish(s,value,firstHalf~='receipt',firstHalf=='receipt' and 'completed' or nil)=='waiting')
        assert(s.counts()==0)
        assert(#s.settlement.blockedReturns(s.player)==0 and loanState(s)=='active')
        -- The real completion owner stays current until its late ACK/effect.
        if firstHalf=='late-start' then s.receipt(value.action,'started') end
        if firstHalf~='receipt' then s.receipt(value.action,'completed') else value.effect=true end
        assert(s.settlement.completionState(s.queue,value.action)=='ready')
        atReturner(s)
        assert(s.settlement.earned(value.handle) and s.settlement.enqueueBorrowedReturn(s.handles[1]))
    end

    -- The expansion itself has no waiting scheduler. Reaching it before the
    -- cleanup settles must leave visible terminal debt, never a delayed retry.
    do
        local s=fixture(true);assert(register(s));local value=start(s)
        assert(finish(s,value,true)=='waiting');atReturner(s)
        assert(not s.settlement.enqueueBorrowedReturn(s.handles[1]))
        local debt=blocked(s,'cleanup-unresolved')
        order(s,value.action,{value.action,s.returner,s.tail});s.receipt(value.action,'completed')
        assert(s.settlement.completionState(s.queue,value.action)=='ready' and s.settlement.earned(value.handle))
        atReturner(s)
        assert(not s.settlement.enqueueBorrowedReturn(s.handles[1]))
        assert(blocked(s,'cleanup-unresolved').id==debt.id)
        assert(s.settlement.keepReturn(s.player,debt.id) and loanState(s)=='waived'
            and s.settlement.earned(value.handle),'location Keep changed the independently earned hand outcome')
    end

    for _,client in ipairs({false,true}) do
        for _,outcome in ipairs(client and {'rejected','callback-failure','stopped','unknown'} or {'callback-failure','stopped','no-effect','unobserved-effect'}) do
            local s=fixture(client);s.label=tostring(client)..':'..outcome;assert(register(s))
            local value
            if outcome=='stopped' then
                value=s.restores[1];local action=value.action
                order(s,action,{action,s.returner,s.tail})
                action.action={};s.present[action.action]=true
                s.settlement.started(action);s.observer.started(action)
                if client then action.toolkitNativeTransaction,action.toolkitNativeKind=101,action.Type;s.receipt(action,'started') end
                assert(not s.observer.begin(action,'stop'))
                s.observer.finish(action,'stop',true);s.present[action.action]=nil
                if client then s.receipt(action,'canceled') end
            else
                value=start(s)
                local state=finish(s,value,outcome~='no-effect' and outcome~='unobserved-effect',client and outcome=='rejected' and 'rejected' or nil,
                    outcome~='callback-failure' and outcome~='no-effect')
                if outcome=='unknown' then
                    assert(state=='waiting');s.advance(30001)
                    assert(s.settlement.completionState(s.queue,value.action)=='failed')
                elseif outcome=='rejected' then
                    assert(state=='ready' and not s.settlement.earned(value.handle),
                        'fixture must distinguish terminal rejection from an earned success')
                end
            end
            atReturner(s)
            assert(not s.settlement.enqueueBorrowedReturn(s.handles[1]))
            local reason=(outcome=='callback-failure' or outcome=='no-effect') and 'cleanup-source' or 'cleanup-outcome'
            local debt=blocked(s,reason);local revision=s.settlement.blockedReturnInfo(s.player).revision
            if client then s.receipt(value.action,'completed') end
            value.effect=true;s.settlement.completionState(s.queue,value.action)
            assert(not s.settlement.enqueueBorrowedReturn(s.handles[1]))
            assert(blocked(s,reason).id==debt.id
                and s.settlement.blockedReturnInfo(s.player).revision==revision,'late outcome retried or duplicated blocked debt')
            assert(s.settlement.keepReturn(s.player,debt.id))
            assert(loanState(s)=='waived' and not s.settlement.earned(value.handle)
                and #s.settlement.blockedReturns(s.player)==0 and s.counts()==0,'Keep manufactured hand/return success')
            assert(not s.settlement.enqueueBorrowedReturn(s.handles[1]) and s.counts()==0)
        end
    end

    -- Snapshot all registered dependencies before any caller mutation; omitting
    -- an unfinished member afterward must not weaken the requirement.
    do
        local s=fixture(false,2);local input={s.observations[1],s.observations[2]}
        assert(register(s,input));input[2]=nil;input[1]={}
        local first=start(s,1);assert(finish(s,first,true)=='ready');assert(s.counts()==0)
        local second=start(s,2);finish(s,second,false,nil,false);atReturner(s)
        assert(not s.settlement.enqueueBorrowedReturn(s.handles[1]));blocked(s,'cleanup-source')
    end
    for _,shape in ipairs({'empty','duplicate','hole','key','metatable','copied','body','unobserved','foreign-owner','already-started','already-earned','forged-loan','unearned-loan','unauthorized-parent','loaded-provider','selected-provider'}) do
        local s=fixture(false);local dependencies={s.observations[1]};local handle=s.handles[1]
        if shape=='empty' then dependencies={}
        elseif shape=='duplicate' then dependencies[2]=dependencies[1]
        elseif shape=='hole' then dependencies={[2]=dependencies[1]}
        elseif shape=='key' then dependencies.extra=dependencies[1]
        elseif shape=='metatable' then setmetatable(dependencies,{})
        elseif shape=='copied' then local copy={};for key,value in pairs(dependencies[1]) do copy[key]=value end;dependencies[1]=copy
        elseif shape=='body' then dependencies[1]=s.handles[1]
        elseif shape=='unobserved' then
            local action=s.action();action.Type='ISEquipWeaponAction';assert(s.settlement.cleanup(action,s.handles[1]))
            dependencies[1]=s.settlement.track(action,'cleanup')
        elseif shape=='foreign-owner' then s.restores[1].action.toolkitQueueOperation={}
        elseif shape=='already-started' then start(s);order(s,s.parent,{s.parent,s.returner,s.tail})
        elseif shape=='already-earned' then local value=start(s);finish(s,value,true);order(s,s.parent,{s.parent,s.returner,s.tail})
        elseif shape=='forged-loan' then local copy={};for key,value in pairs(handle) do copy[key]=value end;handle=copy
        elseif shape=='unearned-loan' then
            local item=s.item(301,s.source);s.source.items[301]=item
            local pickup=s.action();pickup.Type='ISInventoryTransferAction';pickup.item=item
            pickup.srcContainer,pickup.destContainer=s.source,s.root
            assert(s.settlement.remember(s.scope,pickup,{knownInputs=true,items={[301]=true}}))
            assert(s.settlement.preparePickup(s.scope,pickup));handle=s.settlement.track(pickup,'prepare')
            local parent=s.action();parent.Type='ISQueueActionsAction'
            assert(s.settlement.cleanupAfter(parent,{s.handles[1],handle}))
            order(s,parent,{parent,s.tail})
        elseif shape=='unauthorized-parent' then
            local foreign=s.action();foreign.Type='ISQueueActionsAction';assert(s.settlement.cleanup(foreign,s.handles[2]))
            order(s,foreign,{foreign,s.tail})
        elseif shape=='loaded-provider' then P4TidyUpMeister={}
        elseif shape=='selected-provider' then s.selected(true) end
        assert(not s.settlement.requireBorrowedReturnSuccess(handle,dependencies),shape..': invalid enrollment gained return authority')
        assert(s.counts()==0 and #s.settlement.blockedReturns(s.player)==0,shape..': rejected enrollment changed effects/debt')
    end

    -- Metadata reentry cannot register another requirement or reuse a dependency
    -- under a replaced current expansion. Source changes after enrollment fail
    -- closed without constructing the suppressed transfer.
    do
        local s=fixture(false);local nested
        s.providerHook=function()
            if nested==nil then nested=false;nested=register(s) end
        end
        assert(register(s) and nested==false,'provider callback enrolled a nested return dependency')
    end
    do
        local s=fixture(false);local attempted=false
        s.providerHook=function()
            if not attempted then
                attempted=true
                assert(not s.settlement.enqueueBorrowedReturn(s.handles[1]),'enrollment callback issued its incomplete dependency')
            end
        end
        assert(register(s) and attempted and s.counts()==0 and #s.enqueued==0
            and #s.settlement.blockedReturns(s.player)==0,'enrollment reentry poisoned the outer private requirement')
    end
    do
        local s=fixture(false);local changed=false
        s.providerHook=function()
            if not changed then changed=true;s.queue.current=s.tail;s.queue.queue[1]=s.tail end
        end
        assert(not register(s),'registration metadata rebound a replaced current expansion')
        s.providerHook=nil;order(s,s.parent,{s.parent,s.returner,s.tail})
        assert(register(s),'rejected registration left a partial private dependency')
    end
    for _,change in ipairs({'guard','token','list','loaded-provider','selected-provider'}) do
        local s=fixture(false);assert(register(s));local value=start(s)
        assert(finish(s,value,true)=='ready');atReturner(s)
        if change=='guard' then value.guard=false
        elseif change=='token' then value.action.toolkitQueueOperation={}
        elseif change=='list' then local list={};for index,action in ipairs(s.queue.queue) do list[index]=action end;s.queue.queue=list
        elseif change=='loaded-provider' then P4TidyUpMeister={}
        else s.selected(true) end
        assert(not s.settlement.enqueueBorrowedReturn(s.handles[1]))
        blocked(s,(change=='guard' or change=='token') and 'cleanup-source' or 'cleanup-owner',
            change=='list' and 'revoked' or 'blocked')
    end
    do
        local s=fixture(false);assert(register(s));local value=start(s);assert(finish(s,value,true)=='ready');atReturner(s)
        local exists=s.source.isExistYet;local checked=false
        s.source.isExistYet=function(...)
            checked=true;value.guard=false
            return exists(...)
        end
        assert(not s.settlement.enqueueBorrowedReturn(s.handles[1]) and checked,
            'endpoint resolution did not exercise late dependency loss')
        blocked(s,'cleanup-source')
    end
    do
        local s=fixture(false);assert(register(s));local value=start(s);assert(finish(s,value,true)=='ready');atReturner(s)
        local construct=ISInventoryTransferUtil.newInventoryTransferAction;local nested=false
        ISInventoryTransferUtil.newInventoryTransferAction=function(...)
            if not nested then
                nested=true
                assert(not s.settlement.enqueueBorrowedReturn(s.handles[1]),'constructor reentry scheduled the same loan twice')
            end
            return construct(...)
        end
        assert(s.settlement.enqueueBorrowedReturn(s.handles[1]) and s.counts()==1 and #s.enqueued==1)
    end
    for _,callback in ipairs({'provider','guard'}) do
        local s=fixture(false);assert(register(s));local value=start(s);assert(finish(s,value,true)=='ready');atReturner(s)
        local attempted=false
        local function reenter()
            if not attempted then
                attempted=true
                assert(not s.settlement.enqueueBorrowedReturn(s.handles[1]),callback..': success inspection issued a nested native return')
            end
        end
        if callback=='provider' then s.providerHook=reenter else value.guardHook=reenter end
        assert(s.settlement.enqueueBorrowedReturn(s.handles[1]) and attempted
            and s.counts()==1 and #s.enqueued==1 and #s.settlement.blockedReturns(s.player)==0,
            callback..': refused nested inspection poisoned or duplicated the outer native return')
    end
    do
        local s=fixture(false);assert(register(s));local value=start(s);finish(s,value,false,nil,false);atReturner(s)
        local count,reason=fixtures.ownReturns(s,{s.handles[1]})
        assert(count==0 and reason=='cleanup_dependency','coordinator swallowed failed cleanup dependency disposition')
        blocked(s,'cleanup-source')
    end

    -- Unpaid identity remains visible even when the current replica has moved
    -- or disappeared; a historical notice is not a physical return/Keep proof.
    for _,missing in ipairs({false,true}) do
        local s=fixture(false);assert(register(s));local value=start(s);finish(s,value,false,nil,false);atReturner(s)
        local original=s.items[1];local id=original:getID();s.root.items[id]=nil
        original.container=missing and nil or s.source
        assert(not s.settlement.enqueueBorrowedReturn(s.handles[1]))
        local debts=s.settlement.blockedReturns(s.player)
        assert(#debts==1 and debts[1].itemId==id and debts[1].itemType==original:getFullType()
            and debts[1].state=='blocked' and debts[1].reason=='cleanup-source'
            and s.counts()==0 and #s.enqueued==0,'missing current replica hid or paid historical exact debt')
        assert(not s.settlement.keepReturn(s.player,debts[1].id) and loanState(s)=='active')
        if missing then
            local canonical=s.item(id,s.root);canonical.fullType=original:getFullType();s.root.items[id]=canonical
            assert(s.settlement.keepReturn(s.player,debts[1].id) and loanState(s)=='waived'
                and s.root.items[id]==canonical and not s.settlement.earned(value.handle) and s.counts()==0,
                'explicit location Keep rejected a genuine current canonical replica or manufactured native success')
        end
    end

    local function twoFailures()
        local s=fixture(false,2)
        assert(register(s,{s.observations[1]}))
        assert(s.settlement.requireBorrowedReturnSuccess(s.handles[2],{s.observations[2]}))
        -- This continuation owns both location loans; the ordinary fixture's
        -- singleton continuation deliberately authorizes only its first loan.
        s.returner=s.action();s.returner.Type='ISQueueActionsAction'
        assert(s.settlement.cleanupAfter(s.returner,{s.handles[1],s.handles[2]}))
        for index=1,2 do
            local value=start(s,index);finish(s,value,false,nil,false);atReturner(s)
            assert(not s.settlement.enqueueBorrowedReturn(s.handles[index]))
        end
        local debts=s.settlement.blockedReturns(s.player)
        assert(#debts==2 and s.counts()==0 and #s.enqueued==0,'two-loan continuation did not retain both exact failed debts')
        return s,debts[1],debts[2]
    end
    for _,mutation in ipairs({'nested','revoke','replace'}) do
        local s,first,neighbor=twoFailures();local calls,attempted=0,false
        local originalQueue=ISTimedActionQueue.queues[s.player]
        s.providerHook=function()
            calls=calls+1
            if calls==2 then
                attempted=true
                assert(not s.settlement.keepReturn(s.player,first.id),'last getter allowed nested Keep of the same notice')
                if mutation=='revoke' then s.settlement.resetReturnFailures(s.queue)
                elseif mutation=='replace' then ISTimedActionQueue.queues[s.player]={character=s.player,queue={}} end
            end
        end
        local kept=s.settlement.keepReturn(s.player,first.id)
        assert(attempted and kept==(mutation=='nested'),'Keep committed across a last-getter ownership change')
        s.providerHook=nil
        ISTimedActionQueue.queues[s.player]=originalQueue
        local debts=s.settlement.blockedReturns(s.player)
        assert(s.counts()==0 and #s.enqueued==0 and not s.settlement.earned(s.observations[1]))
        if mutation=='nested' then
            assert(#debts==1 and debts[1].id==neighbor.id and loanState(s)=='waived','Keep removed a neighboring loan notice')
        else
            assert(#debts==2 and debts[1].id==first.id and debts[2].id==neighbor.id
                and loanState(s)=='active','stale Keep waived its candidate or removed a neighbor')
        end
    end
    do
        local s=fixture(false);assert(register(s));local value=start(s);finish(s,value,false,nil,false);atReturner(s)
        local list={};for index,action in ipairs(s.queue.queue) do list[index]=action end;s.queue.queue=list
        assert(not s.settlement.enqueueBorrowedReturn(s.handles[1]))
        local notice=s.settlement.blockedReturns(s.player)[1]
        assert(notice and notice.state=='revoked' and notice.reason=='cleanup-owner'
            and not s.settlement.hasActiveBlockedReturn(s.player),'lazy owner loss published active cleanup authority')
        s.root.getItemById=function() error('historical Forget looked up a current item') end
        s.items[1].getContainer=function() error('historical Forget inspected physical ownership') end
        assert(s.settlement.keepReturn(s.player,notice.id) and #s.settlement.blockedReturns(s.player)==0
            and loanState(s)=='active' and not s.settlement.earned(value.handle) and s.counts()==0,
            'historical Forget waived location debt or manufactured hand/native success')
    end

    -- Craft-style optional returns are independent native rows. Keeping one
    -- exact loan must leave the other row and its original destination intact.
    local function nativeReturnsFixture(client,unconfirmed)
        local s=fixtures.setup(client)
        s.root.isExistYet=function()return true end
        s.scope=s.settlement.deferred(s.player,s.token)
        s.sources,s.items,s.rows={},{},{}
        for index=1,2 do
            local source={items={},carried=true,reachable=true,isExistYet=function()return true end}
            function source:getItemById(id)return self.items[id]end
            local bag=s.item(500+index,s.root);bag.fullType='Base.Bag_Schoolbag'
            bag.getInventory=function()return source end
            source.getContainingItem=function()return bag end;s.root.items[bag.id]=bag
            local item=s.item(600+index,source);source.items[item.id]=item
            local pickup=s.action();pickup.Type='ISInventoryTransferAction';pickup.item=item
            pickup.srcContainer,pickup.destContainer=source,s.root
            pickup.action,pickup.queueList,pickup.transactionId={},{{items={item}}},70+index
            order(s,pickup,{pickup,s.current,s.tail})
            assert(s.settlement.remember(s.scope,pickup,{knownInputs=true,items={[item.id]=true}}))
            assert(s.settlement.preparePickup(s.scope,pickup))
            assert(s.settlement.beginPickup(s.scope,pickup,function()return true end))
            source.items[item.id],s.root.items[item.id],item.container=nil,item,s.root
            if index~=unconfirmed then
                pickup.queueList,pickup.transactionId={},0
                assert(s.settlement.finishPickup(s.scope,pickup,true))
            end
            local row=s.action();row.Type='ISInventoryTransferAction';row.item=item
            row.srcContainer,row.destContainer,row.allowMissingItems=s.root,source,true
            assert(s.settlement.track(row,'body'))
            s.sources[index],s.items[index],s.rows[index]=source,item,row
        end
        s.current.Type='ISCraftRecipeAction';s.settlement.track(s.current,'body')
        order(s,s.current,{s.current,s.rows[1],s.rows[2],s.tail})
        PZSurvivorToolkit.ActionQueuePolicy.matchesNative=function(action)
            return action==s.rows[1] or action==s.rows[2]
        end
        s.returnGuard=function(action,reference)
            for index,row in ipairs(s.rows)do
                if action==row then return not reference or reference.id==s.items[index]:getID()
                    and reference.fullType==s.items[index]:getFullType()end
            end
            return false
        end
        return s
    end
    local function nativeLoanState(s,index)
        for _,loan in ipairs(assert(s.settlement.operationState(s.current)).borrowings)do
            if loan.id==s.items[index]:getID()then return loan.state end
        end
        error('missing exact native optional borrowing')
    end
    for _,client in ipairs({false,true})do
        for _,keptIndex in ipairs({1,2})do
            local s=nativeReturnsFixture(client);local returnedIndex=3-keptIndex
            local kept,returned=s.rows[keptIndex],s.rows[returnedIndex]
            local waiver=assert(s.settlement.pendingReturnWaiver(kept,s.returnGuard))
            assert(s.settlement.waivePendingReturn(waiver,kept,s.returnGuard))
            assert(nativeLoanState(s,keptIndex)=='waived'and nativeLoanState(s,returnedIndex)=='active'
                and s.queue.current==s.current and s.queue.queue[2]==s.rows[1]and s.queue.queue[3]==s.rows[2]
                and s.counts()==0,'Keep changed a neighboring native row, loan or active craft')
            assert(not s.settlement.waivePendingReturn(waiver,returned,s.returnGuard)
                and not s.settlement.waivePendingReturn(waiver,kept,s.returnGuard),
                'Keep capability was transferable or replayable')
            -- The reviewed row-removal boundary follows the committed waiver.
            for index,row in ipairs(s.queue.queue)do if row==kept then table.remove(s.queue.queue,index);break end end
            assert(s.settlement.canWaivePendingReturn(returned,s.returnGuard),
                'waiving one original container suppressed the independent sibling')
            order(s,returned,{returned,s.tail})
            returned.action,returned.queueList,returned.transactionId={},{{items={returned.item}}},91
            local obligation=assert(s.settlement.obligation(s.settlement.context(s.scope)))
            assert(s.settlement.beginReturn(returned,obligation,s.returnGuard))
            local item=s.items[returnedIndex];local destination=s.sources[returnedIndex]
            s.root.items[item.id],destination.items[item.id],item.container=nil,item,destination
            returned.queueList,returned.transactionId={},0
            assert(s.settlement.finishReturn(obligation,true)
                and s.settlement.returnState(obligation)=='completed')
            assert(nativeLoanState(s,keptIndex)=='waived'and nativeLoanState(s,returnedIndex)=='completed'
                and s.items[keptIndex]:getContainer()==s.root and s.root.items[s.items[keptIndex].id]==s.items[keptIndex]
                and s.sources[keptIndex].items[s.items[keptIndex].id]==nil
                and s.queue.queue[2]==s.tail and s.counts()==0,
                'sibling native completion moved the retained item or settled another origin')
        end
        for _,mutation in ipairs({'unconfirmed','stale-row','foreign-item','started'})do
            local s=nativeReturnsFixture(client,mutation=='unconfirmed'and 1 or nil)
            local row=s.rows[1];local waiver=s.settlement.pendingReturnWaiver(row,s.returnGuard)
            if mutation=='unconfirmed'then assert(not waiver,'unconfirmed pickup offered Keep')
            else
                assert(waiver)
                if mutation=='stale-row'then table.remove(s.queue.queue,2)
                elseif mutation=='foreign-item'then row.item=s.item(s.items[1].id,s.root)
                else row.action={}end
                assert(not s.settlement.waivePendingReturn(waiver,row,s.returnGuard),
                    mutation..': stale exact row acquired Keep')
            end
            assert(nativeLoanState(s,1)~='waived'and nativeLoanState(s,2)=='active'
                and s.settlement.canWaivePendingReturn(s.rows[2],s.returnGuard)
                and s.items[1]:getContainer()==s.root and s.items[2]:getContainer()==s.root and s.counts()==0,
                mutation..': rejected Keep altered or disabled its independent sibling')
        end
    end

    -- Cancellation must consult the exact same dependency, rather than its
    -- unconditional fallback synthesizing a return for an active location loan.
    do
        local s=fixture(false);assert(register(s))
        local constructions={};local construct=ISInventoryTransferUtil.newInventoryTransferAction
        ISInventoryTransferUtil.newInventoryTransferAction=function(actor,item,...)
            constructions[#constructions+1]=item;return construct(actor,item,...)
        end
        order(s,s.current,{s.current,s.parent,s.restores[1].action,s.returner,s.tail})
        assert(s.settlement.finish(s.queue,{action=s.current,token=s.token},s.discard))
        for _,item in ipairs(constructions) do assert(item~=s.items[1],'cancel synthesized a return around pending cleanup') end
        local debts=s.settlement.blockedReturns(s.player)
        assert(#debts==1 and debts[1].itemId==s.items[1]:getID() and debts[1].reason=='cleanup-canceled')
        assert(s.queue.queue[#s.queue.queue]==s.tail and s.items[1]:getContainer()==s.root)
        assert(not s.settlement.earned(s.observations[1]),'fresh cleanup owner borrowed the old effect observation')
    end
end
assert(loadfile(ProjectRoot..'/tests/test_action_queue_settlement.lua'))()
ReturnSuccessVectors=nil
assert(invoked,'Settlement fixture export did not execute return-success vectors')
print('Borrowed-return cleanup success dependencies passed with explicit engine/receipt doubles.')
