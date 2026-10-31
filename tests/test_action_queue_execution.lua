local function module(source,file,state)
    return assert(loadstring('return function(state) '..source..' end','@/fixture/'..file))()(state)
end
local function setup()
    local s={enabled=true,client=false,native=true,ordinary=true,earned=true,rejected=false,done=false,
        prepared={},calls={},debts={},revision=0,players={},stack={},transfers=0}
    instanceof=function(value,name)return type(value)=='table'and value.class==name end
    getSpecificPlayer=function(index)return s.players[index]end
    isClient=function()return s.client end
    getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
    PZSurvivorToolkit={Settings={actionQueue=function()return s.enabled end}}
    ISInventoryTransferAction={Type='ISInventoryTransferAction'};ISInventoryTransferAction.__index=ISInventoryTransferAction
    ISTimedActionQueue={queues={}}
    s.handlers={start={},death={}}
    Events={OnGameStart={Add=function(callback)s.handlers.start[#s.handlers.start+1]=callback end},
        OnPlayerDeath={Add=function(callback)s.handlers.death[#s.handlers.death+1]=callback end},
        OnTick={Add=function()error('execution bookkeeping must not install a per-frame sweep')end}}
    local policy=module([[return {
        matchesNative=function(action)return state.native and not action.foreign end,
        isOrdinaryTransfer=function(action)return state.ordinary end,
    }]],'ActionQueuePolicy.lua',s)
    local bulk=module([[local marker={}
        return {
            guardTransfer=function(action)
                state.guards=(state.guards or 0)+1
                if not action.onCompleteFunc then
                    action.onCompleteFunc=function()end
                    action.toolkitQueueSafeOnComplete=action.onCompleteFunc
                end
                if action.toolkitTransferGuard then return action end
                local original=action.stop
                local stop=function()end
                action.stop=stop
                action.toolkitTransferGuard={marker=marker,original=original,stop=stop}
                return action
            end,
            isGuardedTransfer=function(action,original)
                local guard=action.toolkitTransferGuard
                return guard and guard.marker==marker and guard.original==original and guard.stop==action.stop
            end,
        }
    ]],'BulkActions.lua',s)
    local settlement=module([[
        local function authorized(action,guard)
            return guard==PZSurvivorToolkit.ActionQueueExecution.matches and state.earned and guard(action)
        end
        local function addDebt(action,reason)
            if not state.debts[action]then
                state.revision=state.revision+1
                state.debts[action]={id=state.revision,itemId=action.item:getID(),itemType=action.item:getFullType(),
                    title='Book',reason=reason,state='blocked',actor=action.character}
            end
            return true
        end
        return {
            returnExecutionSupported=function(action,guard)return authorized(action,guard)end,
            prepareReturnExecution=function(action,guard)
                state.calls[#state.calls+1]={kind='prepare'}
                if not authorized(action,guard)then return false end
                state.prepared[action]=true;return true
            end,
            rejectReturnExecution=function(action,reason,guard)
                state.calls[#state.calls+1]={kind=reason,transaction=action.transactionId}
                if state.throwReject then error('deliberate rejected observer failure')end
                if not state.prepared[action]or not authorized(action,guard)then return false end
                if reason=='server'then
                    return state.client and action.transactionId~=0 and state.rejected and not state.done
                        and addDebt(action,reason)or false
                elseif reason=='admission'then
                    return action.transactionId==0 and not action.started and addDebt(action,reason)or false
                elseif reason=='unmoved'then return not state.client and not state.moved and addDebt(action,reason)or false end
                return false
            end,
            authorizeReturnRetention=function(action,guard)
                state.authorizations=(state.authorizations or 0)+1;return authorized(action,guard)
            end,
            resetReturnFailures=function(queue)
                state.resets=(state.resets or 0)+1
                for action in pairs(state.prepared)do if action.character==queue.character then state.prepared[action]=nil end end
            end,
            blockedReturnInfo=function(actor)
                local count=0;for _,debt in pairs(state.debts)do if debt.actor==actor then count=count+1 end end
                return {count=count,revision=state.revision}
            end,
            blockedReturns=function(actor)
                local values={};for _,debt in pairs(state.debts)do if debt.actor==actor then
                    values[#values+1]={id=debt.id,itemId=debt.itemId,itemType=debt.itemType,title=debt.title,
                        reason=debt.reason,state=debt.state}
                end end;return values
            end,
            keepReturn=function(actor,id)
                for action,debt in pairs(state.debts)do if debt.actor==actor and debt.id==id then
                    state.debts[action]=nil;state.revision=state.revision+1;return true
                end end;return false,'unavailable'
            end,
        }
    ]],'ActionQueueSettlement.lua',s)
    PZSurvivorToolkit.ActionQueuePolicy=policy;PZSurvivorToolkit.BulkActions=bulk;PZSurvivorToolkit.ActionQueueSettlement=settlement
    local function container(parent,owner)
        return {class='ItemContainer',parent=parent,owner=owner,
            getType=function(self)return self.kind or 'container'end,
            getParent=function(self)return self.parent end,getContainingItem=function(self)return self.owner end,
            getAcceptItemFunction=function(self)return self.filter end,
            getOnlyAcceptCategory=function(self)return self.category end,
            getItems=function()error('execution capability must never scan contents')end}
    end
    local function actor(index)
        local value={class='IsoPlayer',index=index}
        value.getPlayerNum=function(self)return self.index end
        value.isLocalPlayer=function(self)return not self.foreign end
        value.isDead=function(self)return self.dead or false end
        value.isAsleep=function(self)return self.asleep or false end
        value.isPlayerMoving=function(self)return self.moving or false end
        value.pressedMovement=value.isPlayerMoving
        value.inventory=container(value);value.getInventory=function(self)return self.inventory end
        value.getCharacterActions=function()return{contains=function(_,native)return s.stack[native]==true end}end
        s.players[index]=value
        return value
    end
    local function action(owner,id)
        local item={class='InventoryItem',id=id or 11,kind='Base.BookFirstAid1'}
        item.getID=function(self)return self.id end;item.getFullType=function(self)return self.kind end
        item.getType=function(self)return self.kind:match('%.(.+)$')end
        item.getContainer=function(self)return self.container end;item.container=owner.inventory
        local value=setmetatable({Type='ISInventoryTransferAction',character=owner,item=item,allowMissingItems=true,
            srcContainer=owner.inventory,destContainer=container({class='IsoObject'}),toolkitQueueOperation={},transactionId=0,
            started=false,stop=function()end},ISInventoryTransferAction)
        value.queueList={{items={item},type=item.kind,time=50}}
        return value
    end
    s.actor=actor(0);s.action=action(s.actor)
    s.queue={character=s.actor,queue={s.action},current=s.action,toolkitOperationGeneration=3}
    ISTimedActionQueue.queues[s.actor]=s.queue
    local proof=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
    local proofClosure=proof.closure
    proof.closure=function(...)
        s.proofCalls=(s.proofCalls or 0)+1
        return proofClosure(...)
    end
    local previous=require
    require=function(name)
        if name=='PZSurvivorToolkit/SourceProof'then return proof end
        if name=='TimedActions/ISInventoryTransferAction'then return true end
        error('unexpected execution dependency: '..name)
    end
    s.execution=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueExecution.lua'))()
    require=previous
    s.policy,s.bulk,s.settlement,s.proof=policy,bulk,settlement,proof
    s.actorFactory,s.actionFactory,s.containerFactory=actor,action,container
    s.prepare=function()
        assert(s.execution.enqueued(s.action));assert(s.execution.begin(s.action))
        local native={started=false};native.isStarted=function(self)return self.started end
        s.action.action=native;assert(s.execution.bind(s.action));return native
    end
    return s
end
local function count(values)local n=0;for _ in pairs(values)do n=n+1 end;return n end

do
    local s=setup();local e,a=s.execution,s.action
    assert(e.matches(a)and not e.inspect(a),'preview must not install a merge guard')
    assert(not s.guards and #s.calls==0)
    assert(e.enqueued(a));local description=assert(e.inspect(a))
    assert(description.version==1 and description.admission=='native-live'and description.outcome=='exact-item'
        and description.failure=='retain-return'and description.atomic=='single')
    assert(e.capacityDeferred(a,description))
    local copy,all={},{}
    for key,value in pairs(description)do all[key]=value;if type(key)=='string'then copy[key]=value end end
    assert(not e.capacityDeferred(a,copy)and not e.capacityDeferred(a,all),
        'copied flags or a copied private closure must not transfer descriptor authority')
    assert(not e.capacityDeferred(s.actionFactory(s.actor),description),'descriptor must belong to the exact action')
    assert(#s.calls==0 and not e.preserveStop(a)and not e.skipUnstarted(s.queue,a),
        'a copied descriptor or repeated preview must create no episode or rejection authority')
    description.failure='anything';assert(not e.capacityDeferred(a,description))
    assert(e.inspect(a).failure=='retain-return','descriptor must be a fresh value')
    assert(e.admitEditMember(a)and s.authorizations==1)
    s.earned=false;assert(not e.inspect(a)and not e.begin(a)and not e.admitEditMember(a),
        'enqueue/source shape must not invent an earlier borrowed-item receipt')
end
for _,change in ipairs({
    function(s)s.earned=false end,
    function(s)s.queue.toolkitOperationGeneration=s.queue.toolkitOperationGeneration+1 end,
    function(s)s.queue.queue={}end,
    function(s)ISTimedActionQueue.queues[s.actor]={}end,
    function(s)s.action.toolkitQueueOperation={}end,
    function(s)s.action.action={}end,
    function(s)s.action.item.id=42 end,
    function(s)s.action.destContainer=s.containerFactory()end,
    function(s)s.action.srcContainer.filter='Unknown.accept'end,
    function(s)s.enabled=false end,
})do
    local s=setup();assert(s.execution.enqueued(s.action));local descriptor=assert(s.execution.inspect(s.action))
    change(s)
    assert(not s.execution.capacityDeferred(s.action,descriptor),'stale descriptor borrowed live edit authority')
end
do
    local s=setup();s.enabled=false
    assert(not s.execution.enqueued(s.action)and not s.execution.inspect(s.action)and not s.execution.begin(s.action))
    assert(not s.guards and #s.calls==0,'disabled controls must not install guards or prepare debt')
end

local unsafe={
    ['foreign native']=function(s)s.native=false end,
    ['unknown endpoints']=function(s)s.ordinary=false end,
    ['pickup']=function(s)s.action.srcContainer=s.action.destContainer end,
    ['same endpoints']=function(s)s.action.destContainer=s.action.srcContainer end,
    ['ordinary transfer']=function(s)s.action.allowMissingItems=false end,
    ['inventory container']=function(s)s.action.item.class='InventoryContainer'end,
    ['replacement item']=function(s)s.action.item.kind='Base.CandleLit'end,
    ['foreign callback']=function(s)s.action.onCompleteFunc=function()error('must not execute callback')end end,
    ['batch']=function(s)s.action.queueList[2]=s.action.queueList[1]end,
    ['merged group']=function(s)s.action.queueList[1].items[2]=s.action.item end,
    ['wrong item']=function(s)s.action.queueList[1].items[1]={class='InventoryItem',getID=function()return 12 end,getFullType=function()return'Base.BookFirstAid1'end}end,
    ['empty list preview']=function(s)s.action.queueList={}end,
    ['source callback']=function(s)s.action.srcContainer.filter=function()error('acceptance callback must not execute')end end,
    ['destination callback']=function(s)s.action.destContainer.filter=function()error('acceptance callback must not execute')end end,
    ['source category']=function(s)s.action.srcContainer.category='Literature'end,
    ['destination category']=function(s)s.action.destContainer.category='Literature'end,
    ['floor destination']=function(s)s.action.destContainer.kind='floor'end,
    ['proximity destination']=function(s)s.action.destContainer.kind='proximityInv'end,
    ['corpse destination']=function(s)s.action.destContainer.kind='twistInv_corpses'end,
    ['missing endpoint getter']=function(s)s.action.destContainer.getAcceptItemFunction=nil end,
    ['actor root alias']=function(s)s.actor.inventory.parent={class='IsoPlayer',getInventory=function()return{}end}end,
    ['cyclic ancestor']=function(s)
        local endpoint=s.action.destContainer
        endpoint.owner={class='InventoryContainer',getInventory=function()return endpoint end,getContainer=function()return endpoint end}
    end,
    ['mismatched owner inventory']=function(s)
        s.action.destContainer.owner={class='InventoryContainer',getInventory=function()return{}end,getContainer=function()return s.actor.inventory end}
    end,
    ['filtered carried ancestor']=function(s)
        local ancestor=s.containerFactory();ancestor.filter=function()error('ancestor filter must not execute')end
        local endpoint=s.action.destContainer
        endpoint.owner={class='InventoryContainer',getInventory=function()return endpoint end,getContainer=function()return ancestor end}
    end,
    ['excessive ancestry']=function(s)
        local current=s.action.destContainer
        for _=1,64 do
            local node,ancestor=current,s.containerFactory()
            node.owner={class='InventoryContainer',getInventory=function()return node end,getContainer=function()return ancestor end}
            current=ancestor
        end
    end,
    ['foreign player']=function(s)s.actor.foreign=true end,
    ['dead player']=function(s)s.actor.dead=true end,
    ['asleep']=function(s)s.actor.asleep=true end,
    ['module replacement']=function(s)PZSurvivorToolkit.ActionQueueExecution={}end,
}
for label,change in pairs(unsafe)do
    local s=setup();change(s)
    assert(not s.execution.enqueued(s.action)and not s.execution.inspect(s.action),label..' gained capability')
    assert(not s.guards and count(s.debts)==0,label..' mutated unsupported action')
end

for _,phase in ipairs({'server','admission','unmoved'})do
    local s=setup();local native=s.prepare();s.client=phase=='server'
    if phase=='server'then
        native.started=true;s.action.started=true;s.action.transactionId=17;s.rejected=true
        assert(s.execution.beforeStop(s.action));assert(s.calls[#s.calls].transaction==17,
            'positive rejection must be observed before Bulk guard clears its transaction')
        s.action.transactionId=0;assert(s.execution.preserveStop(s.action))
    elseif phase=='admission'then assert(s.execution.skipUnstarted(s.queue,s.action))
    else s.execution.completionState(s.queue,s.action)end
    assert(count(s.debts)==1 and s.execution.blockedReturnInfo(s.actor).count==1)
    local values=s.execution.blockedReturns(s.actor);assert(#values==1 and values[1].reason==phase)
    values[1].state='forged';assert(s.execution.blockedReturns(s.actor)[1].state=='blocked','UI exposes a live debt')
    assert(s.execution.keepReturn(s.actor,values[1].id)and s.execution.blockedReturnInfo(s.actor).count==0)
    assert(s.transfers==0,'keeping an optional return must not transfer/replay an item')
end

do
    local s=setup();s.prepare();s.client=true;s.action.transactionId=7;s.rejected=true;s.throwReject=true
    assert(not s.execution.beforeStop(s.action)and not s.execution.preserveStop(s.action),
        'an observer exception must not suppress the original native stop')
    assert(count(s.debts)==0)
    local calls=0
    assert(not s.execution.matches(s.action,setmetatable({},{__index=function()calls=calls+1;error('foreign reference')end})))
    assert(calls==0,'reference validation must not execute foreign callbacks')
end

for _,state in ipairs({'pending','done','absent','zero'})do
    local s=setup();local native=s.prepare();s.client=true;s.action.transactionId=19
    s.rejected=state=='absent';s.done=state=='done'or state=='absent'
    if state=='zero'then s.action.transactionId=0;s.rejected=true end
    assert(not s.execution.beforeStop(s.action)and not s.execution.preserveStop(s.action),
        state..' must not count as an explicit server rejection')
    assert(count(s.debts)==0)
end

local stale={
    ['generation']=function(s)s.queue.toolkitOperationGeneration=4 end,
    ['native episode']=function(s)s.action.action={isStarted=function()return false end}end,
    ['operation token']=function(s)s.action.toolkitQueueOperation={}end,
    ['endpoints']=function(s)s.action.destContainer={class='ItemContainer'}end,
    ['item id']=function(s)s.action.item.id=42 end,
    ['type']=function(s)s.action.item.kind='Base.BookFirstAid2'end,
    ['current']=function(s)s.queue.current={}end,
    ['queue front']=function(s)s.queue.queue[1]={}end,
    ['queue replacement']=function(s)ISTimedActionQueue.queues[s.actor]={}end,
    ['moving']=function(s)s.actor.moving=true end,
    ['canceling']=function(s)s.queue.toolkitCancel=s.action end,
    ['group canceling']=function(s)s.queue.toolkitGroupCancel={}end,
    ['Bulk guard replacement']=function(s)s.bulk.guardTransfer=function()error('unowned guard')end end,
    ['Settlement replacement']=function(s)s.settlement.rejectReturnExecution=function()return true end end,
    ['matcher replacement']=function(s)s.policy.matchesNative=function()return true end end,
}
for label,change in pairs(stale)do
    local s=setup();s.prepare();s.client=true;s.action.transactionId=21;s.rejected=true
    change(s)
    local calls=#s.calls
    assert(not s.execution.beforeStop(s.action)and not s.execution.preserveStop(s.action)
        and not s.execution.skipUnstarted(s.queue,s.action),label..' episode was reused')
    assert(#s.calls==calls and count(s.debts)==0,label..' delegated stale authority')
end

do
    local s=setup();local native=s.prepare();s.client=true;s.action.transactionId=23;s.rejected=true;s.enabled=false
    assert(not s.execution.inspect(s.action)and not s.execution.enqueued(s.action),
        'disabled editor must not grant a new episode or edit capability')
    assert(s.execution.beforeStop(s.action),'an admitted sealed episode may observe its late terminal result')
    s.action.transactionId=0;assert(s.execution.preserveStop(s.action),'late observer must reach the unchanged native stop boundary')
    s.execution.reset(s.queue);assert(not s.execution.preserveStop(s.action),'disabled reset must revoke the admitted episode')
end
do
    local s=setup();s.prepare();s.client=true;s.action.transactionId=24;s.rejected=true;s.enabled=false;s.earned=false
    assert(not s.execution.beforeStop(s.action)and not s.execution.preserveStop(s.action),
        'late callback cannot revive an expired Settlement ownership scope')
end
do
    local s=setup();local endpoint=s.action.destContainer
    endpoint.owner={class='InventoryContainer',getInventory=function()return endpoint end,
        getContainer=function()return s.actor.inventory end}
    assert(s.execution.enqueued(s.action)and s.execution.inspect(s.action),'ordinary carried ancestry should qualify')
    local s=setup();local endpoint=s.action.destContainer
    local ancestor=s.containerFactory({class='IsoObject'})
    endpoint.owner={class='InventoryContainer',getInventory=function()return endpoint end,
        getContainer=function()return ancestor end}
    assert(s.execution.enqueued(s.action),'ordinary nested world ancestry remains under the native binding')
end

do
    local s=setup()
    local other={Type='ISReadABook',character=s.actor}
    assert(not s.execution.enqueued(other)and not s.execution.begin(other)and not s.execution.bind(other))
    assert(not s.execution.completed(other))
    s.execution.completionState(s.queue,other)
    assert((s.proofCalls or 0)==0,'ordinary completion must have only an episode lookup')
end

do
    local s=setup();local native=s.prepare();s.stack[native]=true
    assert(not s.execution.skipUnstarted(s.queue,s.action)and not s.execution.completed(s.action))
    s.stack[native]=nil;native.started=true;assert(not s.execution.skipUnstarted(s.queue,s.action))
    native.started=false;s.action.started=true;assert(not s.execution.skipUnstarted(s.queue,s.action))
    s.action.started=false;s.action.transactionId=1;assert(not s.execution.skipUnstarted(s.queue,s.action))
    s.action.transactionId=0;s.moved=true;s.action.item.container=s.action.destContainer;s.action.queueList={}
    assert(s.execution.matches(s.action),'native-success effect location must not break the source binding')
    s.execution.completionState(s.queue,s.action);assert(count(s.debts)==0,'a completed native move cannot become a failed return')
    assert(s.execution.completed(s.action));assert(not s.execution.matches(s.action),'consumed singleton needs its still-admitted episode')
end
do
    local s=setup();s.prepare();s.client=true
    local calls=#s.calls;s.execution.completionState(s.queue,s.action)
    assert(#s.calls==calls,'MP completion must use its exact existing Settlement observer')
    s.execution.reset(s.queue);assert(s.resets==1 and not s.execution.skipUnstarted(s.queue,s.action))
end
do
    local s=setup();s.prepare()
    local other=s.actorFactory(1);local action=s.actionFactory(other,22)
    local queue={character=other,queue={action},current=action,toolkitOperationGeneration=3};ISTimedActionQueue.queues[other]=queue
    assert(s.execution.enqueued(action)and s.execution.begin(action));action.action={isStarted=function()return false end}
    assert(s.execution.bind(action));s.execution.reset(s.queue)
    assert(s.execution.skipUnstarted(queue,action),'resetting one actor must preserve another independent episode')
end

do
    local s=setup();s.prepare();s.action.queueList={}
    local previous={s.action};local resets=s.resets or 0
    for index=1,80 do
        local action=s.actionFactory(s.actor,100+index)
        local queue={character=s.actor,queue={action},current=action,toolkitOperationGeneration=index+10}
        ISTimedActionQueue.queues[s.actor]=queue
        assert(s.execution.enqueued(action)and s.execution.begin(action))
        action.action={isStarted=function()return false end};assert(s.execution.bind(action));action.queueList={}
        assert(s.execution.matches(action),'new active singleton lost its admitted empty-batch proof')
        for _,old in ipairs(previous)do
            assert(not s.execution.matches(old),'queue replacement retained an older private episode')
            assert(not s.execution.completed(old),'late old completion must not retire the new active slot')
        end
        assert(s.execution.matches(action),'old completions corrupted the newest active episode')
        previous[#previous+1]=action
    end
    assert((s.resets or 0)==resets,'private retirement must not reset old native receipts')
    assert(s.transfers==0,'private retirement must not replay or cancel native effects')
end
for _,event in ipairs({'start','death'})do
    local s=setup();s.prepare();s.action.queueList={}
    assert(s.execution.matches(s.action))
    for _,callback in ipairs(s.handlers[event])do callback(s.actor)end
    assert(not s.execution.matches(s.action),'world/death boundary retained a private capability: '..event)
    assert(not s.resets,'world/death bookkeeping must not mutate Settlement receipts')
end
print('Action execution: source-only descriptors, earned single returns, exact episodes, admission/reject/unmoved settlement, UI debts and independent reset passed.')

-- A failed private eligibility proof must precede endpoint/native proof work.
do
    local s=setup();assert(s.execution.enqueued(s.action))
    s.earned=false
    local callbacks=0
    s.action.destContainer.getAcceptItemFunction=function()
        callbacks=callbacks+1;error('ineligible preview must not inspect endpoint callbacks')
    end
    assert(not s.execution.inspect(s.action)and callbacks==0,
        'private earned-loan eligibility must precede endpoint/source inspection')
end

-- A method-presence getter may reenter another return match. The private
-- endpoint method-name list must not share an iteration cursor between calls.
do
    local s=setup();local other=s.actorFactory(1);local sibling=s.actionFactory(other,912)
    local endpoint=s.action.destContainer
    local names={'getType','getAcceptItemFunction','getOnlyAcceptCategory','getContainingItem','getParent'}
    local getters={};for _,name in ipairs(names)do getters[name]=endpoint[name];endpoint[name]=nil end
    local trace={};local entered=false
    setmetatable(endpoint,{__index=function(_,name)
        local getter=getters[name]
        if getter then
            trace[#trace+1]=name
            if name=='getType'and not entered then
                entered=true;trace[#trace+1]='nested'
                assert(s.execution.matches(sibling),'reentrant sibling endpoint must remain supported')
            end
            return getter
        end
    end})
    assert(s.execution.matches(s.action)and entered)
    assert(table.concat({trace[1],trace[2],trace[3],trace[4],trace[5],trace[6]},',')==
        'getType,nested,getAcceptItemFunction,getOnlyAcceptCategory,getContainingItem,getParent',
        'reentrant endpoint validation skipped or reordered a method-presence check')
end
print('PASS Execution endpoint method checks retain their order across reentrant matching')
