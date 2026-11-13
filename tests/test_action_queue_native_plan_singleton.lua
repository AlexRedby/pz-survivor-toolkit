-- This checks a private-ledger fact, not native admission or queue-edit authority.
local root=ProjectRoot or '.'
toolkitLuaMetatableMatches=assert(loadfile(root..'/tests/support/source_binding.lua'))()
local metadata=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
local function fixture(track,proofObserver)
    local callbacks=0
    local actor={isDead=function()callbacks=callbacks+1;return false end,
        getPlayerNum=function()callbacks=callbacks+1;return 0 end,
        getInventory=function(self)callbacks=callbacks+1;return self.root end}
    actor.root={}
    PZSurvivorToolkit={Settings={actionQueue=function()callbacks=callbacks+1;return true end},
        ActionQueueOperations={isTransfer=function()return false end,adoptCommandLifecycle=function()end},
        ActionQueueTidyIntent={observeTransfers=function()end}}
    local front={character=actor,toolkitQueueOperation={},action={}}
    local action={character=actor,toolkitQueueOperation={}}
    local queue={character=actor,current=front,queue={front,action}}
    local base={};base.__index=base
    ISTimedActionQueue=setmetatable({queues={[actor]=queue},
        getTimedActionQueue=function(value)return ISTimedActionQueue.queues[value]end},base)
    ISTimedActionQueue.__index=ISTimedActionQueue -- Native queue registry derives from ISBaseObject.
    getSpecificPlayer=function()callbacks=callbacks+1;return actor end
    getFilenameOfClosure=metadata
    isClient=function()return false end
    Events={}
    ISQueueActionsAction={start=function()error('native command executed')end}
    ISInventoryTransferAction={}
    ISInventoryPaneContextMenu={getContainers=function()return {}end}
    local modules={}
    require=function(name)
        if name=='TimedActions/ISQueueActionsAction'then return ISQueueActionsAction end
        if name=='PZSurvivorToolkit/ActionQueueOperations'then return PZSurvivorToolkit.ActionQueueOperations end
        if not modules[name]then
            local side=(name=='PZSurvivorToolkit/SourceProof'or name=='PZSurvivorToolkit/ActionQueueTransferOutcome')and'shared'or'client'
            modules[name]=assert(loadfile(root..'/PZSurvivorToolkit/42/media/lua/'..side..'/'..name..'.lua'))()
        end
        return modules[name]
    end
    if proofObserver then proofObserver(require('PZSurvivorToolkit/SourceProof'))end
    local settlement=require('PZSurvivorToolkit/ActionQueueSettlement')
    local lifecycle=require('PZSurvivorToolkit/ActionQueueLifecycle')
    local handle=track~=false and settlement.track(action,'body')
    local function query(active)return settlement.nativePlanSingleton(queue,action,active)end
    local function start()
        queue.current,queue.queue=action,{action}
        lifecycle.started(action)
        action.toolkitQueueOperation.toolkitStarted=true -- Queue.begin's actual post-observer stamp.
        action.action={}
    end
    return {actor=actor,front=front,action=action,queue=queue,settlement=settlement,lifecycle=lifecycle,
        proof=modules['PZSurvivorToolkit/SourceProof'],query=query,start=start,handle=handle,
        callbacks=function()return callbacks end}
end
local function check(value,message)assert(value,message)end

do
    local s=fixture(false)
    check(not s.query(),'absent private history must not mean no obligations')
    check(s.settlement.track(s.action,'body'),'real enqueue did not track')
    local before=s.callbacks()
    for _=1,3 do check(s.query(),'fresh singleton rejected')end
    check(s.callbacks()==before,'ledger query invoked settings/actor getters')
    local diagnostic=s.settlement.operationState(s.action)
    diagnostic.steps[1].started=true;diagnostic.steps[1].state='earned'
    check(s.query(),'copied diagnostics gained authority over private ledger')
    check(not s.settlement.nativePlanSingleton(s.queue,s.action,'yes'),'truthy active permission admitted')
    check(not s.settlement.nativePlanSingleton(s.queue),'omitted action inherited stale argument')
    check(not s.settlement.nativePlanSingleton(s.queue,s.action,false,{}),'extra arguments admitted')
end

for _,mode in ipairs({'prepare','cleanup','receipt','earned','historical-step','sibling','untracked-sibling','borrowed','preparation','settlement'})do
    local s=fixture()
    if mode=='prepare'then s.settlement.track(s.action,'prepare')
    elseif mode=='cleanup'then check(s.settlement.cleanupAfter(s.action,{}))
    elseif mode=='receipt'or mode=='earned'then
        local receipt=s.settlement.captureEffect(s.action)
        if mode=='receipt'then check(s.settlement.bindEffect(s.handle,receipt))
        else check(s.settlement.earn(s.handle,receipt,true))end
    elseif mode=='historical-step'or mode=='sibling'then
        local sibling={character=s.actor,toolkitQueueOperation=s.action.toolkitQueueOperation}
        s.settlement.track(sibling,'body')
        if mode=='historical-step'then s.settlement.started(sibling)
        else s.queue.queue[#s.queue.queue+1]=sibling end
    elseif mode=='untracked-sibling'then
        s.queue.queue[#s.queue.queue+1]={character=s.actor,toolkitQueueOperation=s.action.toolkitQueueOperation}
    elseif mode=='borrowed'then
        local source={}
        local item={getID=function()return 41 end,getFullType=function()return 'Base.Test'end,getContainer=function()return source end}
        s.action.item,s.action.srcContainer,s.action.destContainer=item,source,s.actor.root
        local scope=s.settlement.deferred(s.actor,s.action.toolkitQueueOperation)
        check(s.settlement.remember(scope,s.action,{knownInputs=true,items={[41]=true}}))
        check(s.settlement.preparePickup(scope,s.action),'real borrowing setup failed')
        check(#s.settlement.operationState(s.action).borrowings==1)
    elseif mode=='preparation'then
        s.action.Type='ISUnequipAction'
        check(s.settlement.observePreparation(s.action,{guard=function()return true end,
            capture=function()return {}end,observed=function()return true end}),'real preparation setup failed')
    else
        s.queue.current,s.queue.queue=s.action,{s.action}
        check(s.settlement.finish(s.queue,{action=s.action,token=s.action.toolkitQueueOperation},function()end),
            'real settlement setup failed')
    end
    check(not s.query(),mode..': operation with obligations qualified as singleton')
end

for _,field in ipairs({'toolkitPickups','toolkitCancelled','toolkitStarted','toolkitContinuations'})do
    local s=fixture();s.action.toolkitQueueOperation[field]=field=='toolkitPickups'and{}or true
    check(not s.query(),field..': public pending history ignored')
end
for _,field in ipairs({'action','started','toolkitNativeTransaction','toolkitNativeKind','transactionId',
    'toolkitQueueReturn','toolkitQueueLinked','toolkitQueueContinuation','_isAddingActions',
    'onStartFunc','onCompleteFunc','onCancelFunc','onFailFunc','retriggerLastAction'})do
    local s=fixture();s.action[field]=true
    check(not s.query(),field..': nonpending/decorated row admitted')
end
for _,field in ipairs({'toolkitCancel','toolkitGroupCancel','toolkitResume','toolkitOutcomeWait','toolkitStopIntent','toolkitOperationsInvalid'})do
    local s=fixture();s.queue[field]={}
    check(not s.query(),field..': queue transition ignored')
end
for _,mode in ipairs({'generation','registry','token','duplicate','missing','sparse','list-meta','token-meta','owner','source'})do
    local s=fixture()
    if mode=='generation'then s.queue.toolkitOperationGeneration=1
    elseif mode=='registry'then ISTimedActionQueue.queues[s.actor]={}
    elseif mode=='token'then s.action.toolkitQueueOperation={}
    elseif mode=='duplicate'then s.queue.queue[3]=s.action
    elseif mode=='missing'then s.queue.queue={s.front}
    elseif mode=='sparse'then s.queue.queue.other=s.action
    elseif mode=='list-meta'then setmetatable(s.queue.queue,{})
    elseif mode=='token-meta'then setmetatable(s.action.toolkitQueueOperation,{__metatable=false})
    elseif mode=='owner'then s.action.character={}
    else s.proof.closure=function()error('replaced source checker called')end end
    check(not s.query(),mode..': stale/malformed ledger accepted')
end

do
    local s=fixture();s.action.toolkitQueueOperation.toolkitContinuations=0;s.action.transactionId=0
    local inherited=0
    setmetatable(s.action,{__index=function()inherited=inherited+1;error('inherited action getter')end})
    setmetatable(s.queue,{__index=function()inherited=inherited+1;error('inherited queue getter')end})
    check(s.query()and inherited==0,'own-field query dispatched inherited defaults')
end

for _,mode in ipairs({'registry','front','owner'})do
    local s=fixture();local calls=0
    local equal=function()calls=calls+1;error('identity query invoked __eq')end
    if mode=='registry'then
        local meta={__eq=equal};setmetatable(s.queue,meta)
        ISTimedActionQueue.queues[s.actor]=setmetatable({},meta)
    elseif mode=='front'then
        local meta={__eq=equal};setmetatable(s.front,meta)
        s.queue.queue[1]=setmetatable({character=s.actor},meta)
    else
        local meta={__eq=equal};setmetatable(s.actor,meta)
        s.action.character=setmetatable({},meta)
    end
    check(not s.query()and calls==0,mode..': identity guard dispatched __eq')
end

do
    local s=fixture();s.start()
    local state=s.settlement.operationState(s.action)
    check(state.phase=='body'and state.steps[1].state=='pending'and state.steps[1].started,
        'actual Lifecycle.started ledger state changed')
    local before=s.callbacks()
    check(not s.query()and s.query(true),'active exception did not require explicit permission')
    check(s.callbacks()==before,'active observation invoked actor/settings getters')
    s.queue.current=s.front;s.queue.queue={s.front,s.action}
    check(not s.query(true),'started tail acquired unchanged-front exception')
end

do
    local s=fixture();s.action.action={}
    s.queue.current,s.queue.queue=s.action,{s.action}
    s.action.toolkitQueueOperation.toolkitStarted=true
    check(not s.query(true),'public active flags replaced private Lifecycle.started history')
end

-- Mutations below operate on a real track-created seal; a copied diagnostic is
-- never used as the record. Metadata is the explicit external/reentry seam.
for _,mode in ipairs({'untrusted','seal-replaced','generation','extra-step','throw'})do
    local s=fixture()
    local token=s.action.toolkitQueueOperation
    local marker,seal
    for key,value in pairs(token)do if type(key)=='table'and type(value)=='function'then marker,seal=key,value end end
    check(marker and seal,'real private operation seal missing')
    local invoked=0
    if mode=='untrusted'then
        token[marker]=function()invoked=invoked+1;error('untrusted seal executed')end
    else
        getFilenameOfClosure=function(callback)
            if callback==seal then
                if mode=='seal-replaced'then token[marker]=function()invoked=invoked+1;error('replacement executed')end
                elseif mode=='generation'then s.queue.toolkitOperationGeneration=1
                elseif mode=='extra-step'then
                    check(s.settlement.track({character=s.actor,toolkitQueueOperation=token},'body')==nil,
                        'source metadata reentry minted private history')
                    local record=seal(token);record.steps[2]=record.steps[1]
                else error('metadata unavailable')end
            end
            return metadata(callback)
        end
    end
    check(not s.query(),mode..': source boundary mutation retained singleton fact')
    check(invoked==0,mode..': seal ran before source proof')
end
getFilenameOfClosure=metadata

local function privateRecord(s)
    for key,seal in pairs(s.action.toolkitQueueOperation)do
        if type(key)=='table'and type(seal)=='function'then return assert(seal(s.action.toolkitQueueOperation)),key end
    end
    error('real track-created private record missing')
end

do
    local s=fixture();s.action.item={}
    local lease=assert(s.settlement.nativePlanLease(s.queue,s.action))
    local before=s.callbacks()
    getFilenameOfClosure=function()error('lease reopened closure metadata')end
    s.actor.isDead=function()error('lease called actor getter')end
    s.actor.getInventory=function()error('lease called inventory getter')end
    PZSurvivorToolkit.Settings.actionQueue=function()error('lease called settings')end
    for _=1,3 do check(lease(),'unchanged decision-local lease rejected')end
    check(s.callbacks()==before,'lease invoked an external observer')
end

-- A later member's getter may mutate an already observed earlier member. The
-- checker must compare that saved decision, never rebuild it from changed data.
for _,mode in ipairs({'callback','item','token','hints','continuation','native','generation','queue-list',
    'alias','seal','private-step','private-steps','private-actions','private-borrowings','preparation-scope','step-handle'})do
    local s=fixture();s.action.item={}
    local record,marker=privateRecord(s)
    local step=record.steps[1]
    local lease=assert(s.settlement.nativePlanLease(s.queue,s.action))
    local calls=0
    local later={getID=function()
        calls=calls+1
        if mode=='callback'then s.action.onCancelFunc=function()error('new callback executed')end
        elseif mode=='item'then s.action.item={}
        elseif mode=='token'then s.action.toolkitQueueOperation={}
        elseif mode=='hints'then s.action.toolkitQueueOperation.toolkitPickups={}
        elseif mode=='continuation'then s.action.toolkitQueueOperation.toolkitContinuations=1
        elseif mode=='native'then s.action.action={}
        elseif mode=='generation'then s.queue.toolkitOperationGeneration=1
        elseif mode=='queue-list'then s.queue.queue={s.front,s.action}
        elseif mode=='alias'then s.front.toolkitQueueOperation=s.action.toolkitQueueOperation
        elseif mode=='seal'then s.action.toolkitQueueOperation[marker]=function()error('late seal executed')end
        elseif mode=='private-step'then step.receipt={}
        elseif mode=='private-steps'then record.steps={step}
        elseif mode=='private-actions'then record.actions[s.action]=nil
        elseif mode=='private-borrowings'then record.borrowings[1]={}
        elseif mode=='preparation-scope'then record.preparationScope={}
        else for key in pairs(step.handle)do step.handle[key]=function()error('late handle executed')end end end
        return 42
    end}
    later:getID()
    local before=s.callbacks()
    getFilenameOfClosure=function()error('lease reopened metadata after '..mode)end
    check(not lease(),mode..': stale earlier observation was renewed')
    check(calls==1 and s.callbacks()==before,mode..': freshness checker invoked getters')
end

do
    local s=fixture();s.start()
    local lease=assert(s.settlement.nativePlanLease(s.queue,s.action,true))
    PZSurvivorToolkit.ActionQueuePolicy={editUnchanged=function()return true end}
    check(s.settlement.admitCancellation(s.queue,{action=s.action,token=s.action.toolkitQueueOperation},
        {allowed=true,first=1,last=1,snapshot={}}),'real cancellation admission failed')
    check(not lease(),'private cancellation state was omitted from lease')
end

for _,mode in ipairs({'item','callback','queue-field'})do
    local s=fixture();s.action.item={}
    local record,marker=privateRecord(s)
    local seal=s.action.toolkitQueueOperation[marker]
    getFilenameOfClosure=function(callback)
        if callback==seal then
            if mode=='item'then s.action.item={}
            elseif mode=='callback'then s.action.onCancelFunc=function()end
            else s.queue.unrelatedNewField=true end
        end
        return metadata(callback)
    end
    check(s.settlement.nativePlanLease(s.queue,s.action)==nil,
        mode..': builder recaptured invalidated incoming data after metadata')
end

do
    local s=fixture(false)
    check(s.settlement.nativePlanLease(s.queue,s.action)==nil,'lease manufactured missing history')
    s.settlement.track(s.action,'body');s.start()
    check(s.settlement.nativePlanLease(s.queue,s.action)==nil,'lease ignored explicit active permission')
    check(type(s.settlement.nativePlanLease(s.queue,s.action,true))=='function')
end
-- Generic private operation consumers must enforce provenance too, before
-- operationLive can invoke actor/settings methods or create over bad history.
for _,mode in ipairs({'foreign','malformed','inherited','copied','missing-metadata'})do
    local s=fixture()
    local record,marker=privateRecord(s)
    local token=s.action.toolkitQueueOperation
    local seal=token[marker]
    local invoked=0
    if mode=='foreign'then token[marker]=function()invoked=invoked+1;error('foreign operation seal executed')end
    elseif mode=='malformed'then token[marker]=true
    elseif mode=='inherited'then s.action.toolkitQueueOperation=setmetatable({},{__index=token})
    elseif mode=='copied'then s.action.toolkitQueueOperation={[marker]=seal}
    else getFilenameOfClosure=nil end
    local before=s.callbacks()
    check(not s.settlement.requiredStep(s.action),mode..': bad history produced a required step')
    check(s.settlement.operationState(s.action)==nil,mode..': bad history produced diagnostics')
    check(s.settlement.track(s.action,'body')==nil,mode..': bad marker was overwritten with new history')
    check(s.callbacks()==before and invoked==0,mode..': provenance failure invoked a seal or actor/settings getter')
end

for _,mode in ipairs({'nested','replaced','metadata-error'})do
    local s=fixture()
    local record,marker=privateRecord(s)
    local token=s.action.toolkitQueueOperation
    local seal=token[marker]
    local calls,invoked=0,0
    getFilenameOfClosure=function(callback)
        if callback==seal then
            calls=calls+1
            check(not s.settlement.requiredStep(s.action),'metadata lookup reentered its private operation')
            if mode=='replaced'then token[marker]=function()invoked=invoked+1;error('replaced operation seal executed')end
            elseif mode=='metadata-error'then error('fixture metadata error')end
        end
        return metadata(callback)
    end
    local observed=s.settlement.operationState(s.action)
    check(calls==1 and invoked==0,mode..': operation provenance recursed or invoked replacement')
    check((observed~=nil)==(mode=='nested'),mode..': invalid operation observation escaped')
    token[marker]=seal;getFilenameOfClosure=metadata
    check(s.settlement.operationState(s.action)~=nil,mode..': transient metadata fence was not released')
end

-- The real registry is an inherited class. Its queues slot must still be
-- own data; inherited lookalikes cannot supply queue ownership through __index.
do
    local s=fixture();local calls=0
    local queues=ISTimedActionQueue.queues
    ISTimedActionQueue.queues=nil
    setmetatable(ISTimedActionQueue,{__index=function(_,key)
        calls=calls+1
        if key=='queues'then return queues end
        error('unexpected registry getter')
    end})
    check(not s.query()and s.settlement.nativePlanLease(s.queue,s.action)==nil and calls==0,
        'inherited registry queues dispatched __index or acquired ownership')
end

-- Private seals must never enter the general SourceProof closure cache. This
-- explicit pre-load observer delegates all ordinary helper checks unchanged.
do
    local seals,checked={},0
    local s=fixture(nil,function(proof)
        local original=proof.closure
        proof.closure=function(callback,...)
            check(not seals[callback],'operation seal reached cached SourceProof.closure')
            checked=checked+1
            return original(callback,...)
        end
    end)
    local record,marker=privateRecord(s)
    local seal=s.action.toolkitQueueOperation[marker];seals[seal]=true
    local calls=0
    getFilenameOfClosure=function(callback)
        if callback==seal then calls=calls+1 end
        return metadata(callback)
    end
    check(s.settlement.operationState(s.action)~=nil)
    check(s.query())
    check(type(s.settlement.nativePlanLease(s.queue,s.action))=='function')
    check(calls==3,'operation/singleton/lease did not perform independent uncached filename reads')
    s.queue.current,s.queue.queue=s.action,{s.action}
    check(s.settlement.editLedger(s.queue,s.action).status=='observed')
    check(calls==4,'editLedger reused retained seal metadata')
end

for _,mode in ipairs({'accessor-replaced','windows-path','trailing-slash','trailing-backslash','nonstring'})do
    local s=fixture()
    local record,marker=privateRecord(s)
    local seal=s.action.toolkitQueueOperation[marker]
    getFilenameOfClosure=function(callback)
        if callback~=seal then return metadata(callback)end
        if mode=='accessor-replaced'then
            getFilenameOfClosure=function()error('replacement accessor executed')end
            return 'ActionQueueSettlement.lua'
        elseif mode=='windows-path'then return 'media\\lua\\client\\ActionQueueSettlement.lua'
        elseif mode=='trailing-slash'then return 'ActionQueueSettlement.lua/'
        elseif mode=='trailing-backslash'then return 'ActionQueueSettlement.lua\\'
        else return {}end
    end
    local accepted=s.settlement.operationState(s.action)~=nil
    check(accepted==(mode=='windows-path'),mode..': filename normalization/accessor freshness changed')
    getFilenameOfClosure=metadata
    check(s.settlement.operationState(s.action)~=nil,mode..': metadata fence remained active')
end


-- Count necessary work, not elapsed time. Native rawget is safe for plain
-- selected owners; inherited owners must retain own-slot pairs traversal.
do
    local originalPairs,watched,visits=pairs,{},{}
    pairs=function(owner)
        if watched[owner]then visits[owner]=(visits[owner]or 0)+1 end
        return originalPairs(owner)
    end
    local ok,problem=pcall(function()
        local s=fixture()
        local inherited=0
        local meta={__index=function()inherited=inherited+1;error('inherited selected getter executed')end}
        setmetatable(s.action,meta);setmetatable(s.queue,meta);setmetatable(s.front,meta)
        local plain={_G,PZSurvivorToolkit,s.settlement,s.proof,ISTimedActionQueue.queues}
        local derived={s.action,s.queue,s.front,ISTimedActionQueue}
        for _,owner in ipairs(plain)do watched[owner]=true end
        for _,owner in ipairs(derived)do watched[owner]=true end
        local function work()
            for _,owner in ipairs(plain)do check(not visits[owner],'plain selected owner was enumerated')end
            for _,owner in ipairs(derived)do check((visits[owner]or 0)>0,'inherited owner lost own-slot traversal')end
            check(inherited==0,'work check dispatched inherited getter')
        end
        local lease=assert(s.settlement.nativePlanLease(s.queue,s.action))
        work()
        for owner in originalPairs(visits)do visits[owner]=nil end
        check(lease(),'unchanged raw-read lease rejected')
        work()
        local saved=s.proof.closure
        s.proof.closure=false;check(not lease(),'false selected module slot was missed')
        s.proof.closure=nil;check(not lease(),'absent selected module slot was missed')
        s.proof.closure=saved;check(lease())
    end)
    pairs=originalPairs
    for owner in originalPairs(watched)do watched[owner]=nil end
    for owner in originalPairs(visits)do visits[owner]=nil end
    check(ok,problem)
end


-- Cohort queries share structural observations but still open each real token.
local function cohortFixture(size,proofObserver)
    local s=fixture(nil,proofObserver)
    s.queue.queue={s.front}
    s.front.action=nil
    assert(s.settlement.track(s.front,'body'))
    s.lifecycle.started(s.front)
    s.front.toolkitQueueOperation.toolkitStarted=true;s.front.action={}
    for index=2,size do
        local action=index==2 and s.action or {character=s.actor,toolkitQueueOperation={}}
        assert(s.settlement.track(action,'body'))
        s.queue.queue[index]=action
    end
    return s
end
local function actualRecord(action)
    for key,seal in pairs(action.toolkitQueueOperation)do
        if type(key)=='table'and type(seal)=='function'then return assert(seal(action.toolkitQueueOperation)),key end
    end
    error('actual private operation missing')
end
local function allStandalone(s)
    for index,action in ipairs(s.queue.queue)do
        local lease=s.settlement.nativePlanLease(s.queue,action,index==1)
        if type(lease)~='function'or not lease()then return false end
    end
    return true
end
for _,mode in ipairs({'fresh','missing','cleanup','receipt','earned','history','alias','duplicate','started-tail',
    'hint','continuation','foreign-seal','copied-seal','generation','registry','wrong-owner','pending-false','active-false'})do
    local s=cohortFixture(4)
    local action=s.queue.queue[2]
    if mode=='missing'then
        action={character=s.actor,toolkitQueueOperation={}};s.queue.queue[2]=action
    elseif mode=='cleanup'then assert(s.settlement.cleanupAfter(action,{}))
    elseif mode=='receipt'or mode=='earned'then
        local handle=s.settlement.track(action,'body');local receipt=s.settlement.captureEffect(action)
        if mode=='receipt'then assert(s.settlement.bindEffect(handle,receipt))
        else assert(s.settlement.earn(handle,receipt,true))end
    elseif mode=='history'then
        assert(s.settlement.track({character=s.actor,toolkitQueueOperation=action.toolkitQueueOperation},'body'))
    elseif mode=='alias'then s.queue.queue[3].toolkitQueueOperation=action.toolkitQueueOperation
    elseif mode=='duplicate'then s.queue.queue[3]=action
    elseif mode=='started-tail'then
        s.lifecycle.started(action);action.toolkitQueueOperation.toolkitStarted=true;action.action={}
    elseif mode=='hint'then action.toolkitQueueOperation.toolkitPickups={}
    elseif mode=='continuation'then action.toolkitQueueOperation.toolkitContinuations=1
    elseif mode=='foreign-seal'then
        local record,key=actualRecord(action)
        action.toolkitQueueOperation[key]=function()error('foreign cohort seal executed')end
    elseif mode=='copied-seal'then
        local record,key=actualRecord(action)
        local other=s.queue.queue[3]
        local otherRecord,otherKey=actualRecord(other)
        action.toolkitQueueOperation[key]=other.toolkitQueueOperation[otherKey]
    elseif mode=='generation'then s.queue.toolkitOperationGeneration=1
    elseif mode=='registry'then ISTimedActionQueue.queues[s.actor]={}
    elseif mode=='wrong-owner'then action.character={}
    elseif mode=='pending-false'then action.action=false;action.transactionId=0
    elseif mode=='active-false'then s.front.action=false end
    local old=allStandalone(s)
    local cohort=s.settlement.nativePlanCohort(s.queue)
    check((type(cohort)=='function')==old,mode..': standalone/cohort acceptance diverged')
    if cohort then check(cohort(),mode..': new cohort lease was born stale')end
end
for _,size in ipairs({1,2,4,32})do
    local s=cohortFixture(size)
    local checkCohort=assert(s.settlement.nativePlanCohort(s.queue))
    local before=s.callbacks()
    getFilenameOfClosure=function()error('cohort final check reopened metadata')end
    s.actor.isDead=function()error('cohort final check invoked actor getter')end
    PZSurvivorToolkit.Settings.actionQueue=function()error('cohort final check invoked settings')end
    check(checkCohort()and s.callbacks()==before,'cohort final check was not callback-free')
end
for _,mode in ipairs({'empty','oversize','sparse','extra-key','current','inherited-queues'})do
    local s=cohortFixture(mode=='oversize'and 33 or 4)
    if mode=='empty'then s.queue.queue={}
    elseif mode=='sparse'then s.queue.queue[2]=nil
    elseif mode=='extra-key'then s.queue.queue.extra=s.action
    elseif mode=='current'then s.queue.current=s.queue.queue[2]
    elseif mode=='inherited-queues'then
        local queues=ISTimedActionQueue.queues;ISTimedActionQueue.queues=nil
        setmetatable(ISTimedActionQueue,{__index={queues=queues}})
    end
    check(s.settlement.nativePlanCohort(s.queue)==nil,mode..': unsupported cohort acquired a lease')
end
-- Standalone queries retain their narrower history question and handle rules.
do
    local s=fixture();s.queue.queue[3]=s.front
    check(s.query()and type(s.settlement.nativePlanLease(s.queue,s.action))=='function',
        'standalone query began rejecting unrelated duplicate rows')
    check(s.settlement.nativePlanCohort(s.queue)==nil)
    local record=actualRecord(s.action);record.steps[1].handle=nil
    check(s.query()and s.settlement.nativePlanLease(s.queue,s.action)==nil,
        'singleton acquired the lease-only handle prerequisite')
end
for _,mode in ipairs({'callback','item','token','hints','cleanup','receipt','private-step','private-map','alias','queue','api'})do
    local s=cohortFixture(4)
    local action=s.queue.queue[2];local record=actualRecord(action)
    local cohort=assert(s.settlement.nativePlanCohort(s.queue))
    -- Explicit later-getter double; no claim about physical input/native work.
    local later={getID=function()
        if mode=='callback'then action.onCancelFunc=function()error('late callback executed')end
        elseif mode=='item'then action.item={}
        elseif mode=='token'then action.toolkitQueueOperation={}
        elseif mode=='hints'then action.toolkitQueueOperation.toolkitPickups={}
        elseif mode=='cleanup'then assert(s.settlement.cleanupAfter(action,{}))
        elseif mode=='receipt'then
            assert(s.settlement.bindEffect(s.settlement.track(action,'body'),s.settlement.captureEffect(action)))
        elseif mode=='private-step'then record.steps[1].required=true
        elseif mode=='private-map'then record.borrowings={}
        elseif mode=='alias'then s.queue.queue[3].toolkitQueueOperation=action.toolkitQueueOperation
        elseif mode=='queue'then s.queue.queue={s.front,action}
        else s.settlement.nativePlanCohort=function()error('replacement cohort API executed')end end
        return 42
    end}
    later:getID()
    local before=s.callbacks()
    getFilenameOfClosure=function()error('stale cohort check reopened source')end
    check(not cohort()and s.callbacks()==before,mode..': later mutation renewed an earlier cohort observation')
end
for _,mode in ipairs({'earlier-private','earlier-handle','later-public','later-token-meta','nested','accessor'})do
    local s=cohortFixture(4)
    local firstRecord=actualRecord(s.front)
    local later=s.queue.queue[3];local record,key=actualRecord(later)
    local seal=later.toolkitQueueOperation[key]
    getFilenameOfClosure=function(callback)
        if callback==seal then
            if mode=='earlier-private'then firstRecord.steps[1].receipt={}
            elseif mode=='earlier-handle'then
                for marker in pairs(firstRecord.steps[1].handle)do
                    firstRecord.steps[1].handle[marker]=function()error('changed private handle executed')end
                end
            elseif mode=='later-public'then s.queue.queue[4].item={}
            elseif mode=='later-token-meta'then
                setmetatable(s.queue.queue[4].toolkitQueueOperation,{__index=function()error('late token getter executed')end})
            elseif mode=='nested'then check(s.settlement.nativePlanCohort(s.queue)==nil,'nested source query reopened cohort')
            else getFilenameOfClosure=function()error('replacement accessor executed')end end
        end
        return metadata(callback)
    end
    local cohort=s.settlement.nativePlanCohort(s.queue)
    check((type(cohort)=='function')==(mode=='nested'),mode..': cohort recaptured source-boundary mutations')
end
-- A shared snapshot performs the same common queue/list/registry passes for
-- different cohort sizes. Each distinct private record still requires source
-- provenance and a final private-data comparison; no timing budget is imposed.
local function cohortWork(size,shared)
    local originalPairs,watched,counts=pairs,{},{}
    pairs=function(owner)
        local name=watched[owner]
        if name then counts[name]=(counts[name]or 0)+1 end
        return originalPairs(owner)
    end
    local ok,result=pcall(function()
        local s=cohortFixture(size)
        watched[s.queue.queue],watched[ISTimedActionQueue]='list','registry'
        local seals={}
        for _,action in ipairs(s.queue.queue)do
            local record,key=actualRecord(action)
            watched[record.steps]='private'
            seals[action.toolkitQueueOperation[key]]=true
        end
        local sources=0
        getFilenameOfClosure=function(callback)
            if seals[callback]then sources=sources+1 end
            return metadata(callback)
        end
        local checks={}
        if shared then checks[1]=assert(s.settlement.nativePlanCohort(s.queue))
        else for index,action in ipairs(s.queue.queue)do checks[index]=assert(s.settlement.nativePlanLease(s.queue,action,index==1))end end
        local observed={listBuild=counts.list,registryBuild=counts.registry,sources=sources}
        for key in originalPairs(counts)do counts[key]=nil end
        local before=s.callbacks()
        for _,fresh in ipairs(checks)do check(fresh())end
        observed.listCheck,observed.registryCheck,observed.privateCheck=counts.list,counts.registry,counts.private
        check(sources==size and s.callbacks()==before,'cohort omitted source proof or final check invoked a getter')
        return observed
    end)
    pairs=originalPairs;getFilenameOfClosure=metadata
    for owner in originalPairs(watched)do watched[owner]=nil end
    check(ok,result)
    return result
end
local sharedBase
for _,size in ipairs({2,4,8,32})do
    local shared,bank=cohortWork(size,true),cohortWork(size,false)
    if sharedBase then
        check(shared.listBuild==sharedBase.listBuild and shared.registryBuild==sharedBase.registryBuild,
            'common capture/alias work grew once per row')
        check(shared.listCheck==sharedBase.listCheck and shared.registryCheck==sharedBase.registryCheck,
            'common final freshness grew once per row')
    else sharedBase=shared end
    check(shared.listBuild<bank.listBuild and shared.registryBuild<bank.registryBuild,
        'cohort rebuilt common captures per private record')
    check(shared.listCheck<bank.listCheck and shared.registryCheck<bank.registryCheck,
        'cohort repeated common final checks per row')
    check(shared.privateCheck==size and bank.privateCheck==size,'final comparison skipped a private step')
end

getFilenameOfClosure=metadata
-- Build the same private links as Operations stamping plus Compat's
-- rememberTidy/preparePickup. Endpoint objects below are explicit Lua doubles;
-- this fixture makes no native item, UI or transport claim.
local function preparedFixture(borrowed,proofObserver)
    local s=cohortFixture(2,proofObserver)
    local approach=s.action
    local token=approach.toolkitQueueOperation
    local source={}
    local item={container=source,getID=function()return 41 end,getFullType=function()return 'Base.Test'end,
        getContainer=function(self)return self.container end,getIsCraftingConsumed=function()return false end}
    local bag={getID=function()return 42 end,getFullType=function()return 'Base.Bag'end,
        getInventory=function()return source end}
    source.getContainingItem=function()return bag end
    local fetch={character=s.actor,toolkitQueueOperation=token,item=item,srcContainer=source,
        destContainer=s.actor.root,transactionId=0,started=false}
    local body={character=s.actor,toolkitQueueOperation=token,item=item}
    approach.toolkitQueueApproach=true
    assert(s.settlement.track(fetch,'body'));assert(s.settlement.track(body,'body'))
    s.queue.queue={s.front,approach,fetch,body}
    token.toolkitPickups={[item]=source}
    local scope
    if borrowed~=false then
        scope=s.settlement.deferred(s.actor,s.front.toolkitQueueOperation)
        assert(s.settlement.remember(scope,s.front,{knownInputs=true,items={[90]=true}}))
        for _,action in ipairs({approach,fetch,body})do
            assert(s.settlement.remember(scope,action,{knownInputs=true,items={[41]=true}}))
        end
        assert(s.settlement.preparePickup(scope,fetch))
    end
    s.group={approach=approach,fetch=fetch,body=body,source=source,destination=s.actor.root,item=item}
    s.groups={[token]=s.group};s.scope=scope
    s.groupRecord=actualRecord(approach)
    s.candidate=s.groupRecord.borrowings[1]and s.groupRecord.borrowings[1].candidate
    return s
end
for _,borrowed in ipairs({false,true})do
    local s=preparedFixture(borrowed)
    check(s.settlement.nativePlanCohort(s.queue)==nil,'unselected prepared group gained singleton authority')
    check(s.settlement.nativePlanLease(s.queue,s.group.body)==nil,'standalone lease gained prepared authority')
    local fresh,facts=s.settlement.nativePlanCohort(s.queue,s.groups)
    check(type(fresh)=='function'and fresh(),'real untouched prepared group rejected')
    local input=facts[s.action.toolkitQueueOperation]
    check(input.hasBorrowing==borrowed,'prepared borrowing observation differs')
    if borrowed then
        check(input.id==41 and input.fullType=='Base.Test'and input.sourceOwner.id==42
            and input.sourceOwner.fullType=='Base.Bag','private candidate identity copy differs')
    end
    local before=s.callbacks()
    getFilenameOfClosure=function()error('prepared final check reopened seal metadata')end
    s.actor.getInventory=function()error('prepared final check read inventory')end
    s.group.item.getID=function()error('prepared final check read item ID')end
    check(fresh()and s.callbacks()==before,'prepared final check invoked a getter')
    input.hasBorrowing=not borrowed
    check(not fresh(),'mutable candidate DTO gained authority')
    getFilenameOfClosure=metadata
end
local function scopeLedger(scope)
    for key,seal in pairs(scope)do
        if type(key)=='table'and type(seal)=='function'then return assert(seal(scope)),key,seal end
    end
    error('real deferred borrowing seal missing')
end
local function addPreparedGroup(s,id,existing)
    local source=s.group.source
    local item=existing or{getID=function()return id end,getFullType=function()return 'Base.Test'end,
        getContainer=function()return source end}
    local token={toolkitPickups={[item]=source}}
    local approach={character=s.actor,toolkitQueueOperation=token,toolkitQueueApproach=true}
    local fetch={character=s.actor,toolkitQueueOperation=token,item=item,srcContainer=source,
        destContainer=s.actor.root,transactionId=0,started=false}
    local body={character=s.actor,toolkitQueueOperation=token,item=item}
    for _,action in ipairs({approach,fetch,body})do
        assert(s.settlement.track(action,'body'));s.queue.queue[#s.queue.queue+1]=action
        assert(s.settlement.remember(s.scope,action,{knownInputs=true,items={[id]=true}}))
    end
    assert(s.settlement.preparePickup(s.scope,fetch))
    local group={approach=approach,fetch=fetch,body=body,source=source,destination=s.actor.root,item=item}
    s.groups[token]=group
    return group
end
do
    local s=preparedFixture();local second=addPreparedGroup(s,43)
    local fresh,facts=s.settlement.nativePlanCohort(s.queue,s.groups)
    check(type(fresh)=='function'and fresh(),'shared prepared scope rejected distinct genuine groups')
    check(facts[second.body.toolkitQueueOperation].id==43,'shared scope renewed another candidate identity')
    s.groupRecord.steps[2].handle={}
    check(not fresh(),'shared scope omitted earlier private handle')
end
for _,mode in ipairs({'no-hint','extra-hint','wrong-hint','hint-meta','descriptor-meta','descriptor-extra','missing-row',
    'split','row-alias','token-alias','wrong-item','wrong-source','history','cleanup','paid','started','submitted','expanded',
    'candidate-phase','candidate-owner','candidate-source','candidate-item-proof','candidate-owner-meta','candidate-ambiguous',
    'shared-input','shared-pickup','shared-unknown','scope-retired','scope-generation','scope-continued','ledger-handle','ledger-merging',
    'ledger-executor','ledger-actions','ledger-alias','foreign-scope-seal','copied-scope-seal'})do
    local s=preparedFixture()
    local token=s.action.toolkitQueueOperation
    local ledger,marker,seal=scopeLedger(s.scope)
    local invoked=0
    if mode=='no-hint'then token.toolkitPickups=nil
    elseif mode=='extra-hint'then token.toolkitPickups[{}]=s.group.source
    elseif mode=='wrong-hint'then token.toolkitPickups[s.group.item]={}
    elseif mode=='hint-meta'then setmetatable(token.toolkitPickups,{})
    elseif mode=='descriptor-meta'then setmetatable(s.group,{})
    elseif mode=='descriptor-extra'then s.group.permission=true
    elseif mode=='missing-row'then s.queue.queue[4]=nil
    elseif mode=='split'then s.queue.queue[3],s.queue.queue[4]=s.group.body,s.group.fetch
    elseif mode=='row-alias'then s.queue.queue[4]=s.group.fetch
    elseif mode=='token-alias'then s.front.toolkitQueueOperation=token
    elseif mode=='wrong-item'then s.group.body.item={}
    elseif mode=='wrong-source'then s.group.fetch.srcContainer={}
    elseif mode=='history'then assert(s.settlement.track({character=s.actor,toolkitQueueOperation=token},'body'))
    elseif mode=='cleanup'then assert(s.settlement.cleanupAfter(s.group.body,{}))
    elseif mode=='paid'then
        local handle=s.settlement.track(s.group.body,'body')
        assert(s.settlement.bindEffect(handle,s.settlement.captureEffect(s.group.body)))
    elseif mode=='started'then s.lifecycle.started(s.group.fetch)
    elseif mode=='submitted'then s.group.fetch.transactionId=12
    elseif mode=='expanded'then s.action._isAddingActions=true
    elseif mode=='candidate-phase'then s.candidate.phase='active'
    elseif mode=='candidate-owner'then s.candidate.owner=s.front.toolkitQueueOperation
    elseif mode=='candidate-source'then s.candidate.source={}
    elseif mode=='candidate-item-proof'then s.candidate.proof={}
    elseif mode=='candidate-owner-meta'then setmetatable(s.candidate.sourceOwner,{})
    elseif mode=='candidate-ambiguous'then s.candidate.ambiguous=true
    elseif mode=='shared-input'then s.scope.tasks[s.front.toolkitQueueOperation].items[41]=true
    elseif mode=='shared-pickup'then s.scope.tasks[s.front.toolkitQueueOperation].pickups[41]={container=s.group.source,fullType='Base.Test'}
    elseif mode=='shared-unknown'then s.scope.tasks[s.front.toolkitQueueOperation].unknownInputs=true
    elseif mode=='scope-retired'then s.scope.phase='retired'
    elseif mode=='scope-generation'then s.scope.generation=1
    elseif mode=='scope-continued'then s.scope.restoreToken={continued=true}
    elseif mode=='ledger-handle'then ledger.handles[s.group.fetch]={}
    elseif mode=='ledger-merging'then ledger.merging[s.group.fetch]={}
    elseif mode=='ledger-executor'then ledger.executors[s.group.fetch][41]={}
    elseif mode=='ledger-actions'then ledger.actions[s.group.fetch]=nil
    elseif mode=='ledger-alias'then ledger.candidates[2]=s.candidate
    elseif mode=='foreign-scope-seal'then s.scope[marker]=function()invoked=invoked+1;error('foreign deferred seal executed')end
    else
        local other=s.settlement.deferred(s.actor,token)
        local _,otherMarker,otherSeal=scopeLedger(other)
        s.scope[marker]=otherSeal
    end
    check(s.settlement.nativePlanCohort(s.queue,s.groups)==nil,mode..': invalid prepared private group admitted')
    check(invoked==0,mode..': foreign deferred seal ran before provenance')
end
do
    local s=preparedFixture()
    local context=assert(s.settlement.context(s.scope))
    check(s.scope.phase=='cleanup'and context.sharedCleanup==true and context.token==s.scope.restoreToken,
        'real P4 presentation context shape differs')
    s.scope.idleTicks=0;s.scope.restored=false
    local fresh=assert(s.settlement.nativePlanCohort(s.queue,s.groups));check(fresh())
    s.scope.restoreToken.claim=true
    check(not fresh()and s.settlement.nativePlanCohort(s.queue,s.groups)==nil,
        'presentation restore token acquired an admission')
end
for _,idle in ipairs({-1,0.5,math.huge,'0'})do
    local s=preparedFixture();s.settlement.context(s.scope);s.scope.idleTicks=idle
    check(s.settlement.nativePlanCohort(s.queue,s.groups)==nil,'invalid P4 idle counter admitted')
end
do
    local s=preparedFixture()
    local reader=s.front.toolkitQueueOperation
    s.scope.tasks[reader].readsEquipment=true;s.scope.equipmentItems[41]=true
    local fresh,facts=s.settlement.nativePlanCohort(s.queue,s.groups)
    check(type(fresh)=='function'and fresh(),'unearned implicit hand use was mistaken for exclusive item debt')
    local readers=facts[s.action.toolkitQueueOperation].equipmentReaders
    check(type(readers)=='table'and readers[reader]==true,'implicit equipment reader token not reported')
    readers[reader]=nil
    check(not fresh(),'equipment reader DTO mutation escaped final freshness')
    -- This does not authorize the active reader: Policy must reject its token
    -- unless it separately qualifies an untouched native Equip in this cohort.
end
local function addPreparedTail(s)
    local tail={character=s.actor,toolkitQueueOperation={}}
    assert(s.settlement.track(tail,'body'));s.queue.queue[#s.queue.queue+1]=tail
    if s.scope then assert(s.settlement.remember(s.scope,tail,{knownInputs=true,items={[91]=true}}))end
    return tail
end
for _,mode in ipairs({'step','callback','item','token','hint','candidate','candidate-owner','task','scope','ledger','dto','dto-owner','groups'})do
    local s=preparedFixture();addPreparedTail(s)
    local ledger=scopeLedger(s.scope)
    local fresh,facts=s.settlement.nativePlanCohort(s.queue,s.groups)
    check(type(fresh)=='function'and fresh(),'shared reader scope lost genuine prepared group')
    if mode=='step'then s.groupRecord.steps[2].receipt={}
    elseif mode=='callback'then s.group.body.onCompleteFunc=function()error('late callback executed')end
    elseif mode=='item'then s.group.fetch.item={}
    elseif mode=='token'then s.group.body.toolkitQueueOperation={}
    elseif mode=='hint'then s.action.toolkitQueueOperation.toolkitPickups={}
    elseif mode=='candidate'then s.candidate.phase='active'
    elseif mode=='candidate-owner'then s.candidate.sourceOwner.id=43
    elseif mode=='task'then s.scope.tasks[s.front.toolkitQueueOperation].items[41]=true
    elseif mode=='scope'then s.scope.tasks={}
    elseif mode=='ledger'then ledger.executors[s.group.fetch][41]=nil
    elseif mode=='dto'then facts[s.action.toolkitQueueOperation].id=55
    elseif mode=='dto-owner'then facts[s.action.toolkitQueueOperation].sourceOwner.fullType='Base.Other'
    else s.groups[s.action.toolkitQueueOperation]={}end
    local before=s.callbacks()
    getFilenameOfClosure=function()error('prepared stale checker invoked metadata')end
    check(not fresh()and s.callbacks()==before,mode..': prepared late mutation renewed an earlier capture')
    getFilenameOfClosure=metadata
end
for _,mode in ipairs({'earlier-private','candidate','scope-task','scope-marker','scope-seal-replaced','throw','nested'})do
    local s=preparedFixture()
    local tail=addPreparedTail(s)
    local _,tokenMarker=actualRecord(tail)
    local tailSeal=tail.toolkitQueueOperation[tokenMarker]
    local ledger,marker,seal=scopeLedger(s.scope)
    local invoked=0
    getFilenameOfClosure=function(callback)
        if callback==(mode=='earlier-private'and tailSeal or seal)then
            if mode=='earlier-private'then s.groupRecord.steps[2].required=true
            elseif mode=='candidate'then s.candidate.sourceOwner.id=50
            elseif mode=='scope-task'then s.scope.tasks[s.action.toolkitQueueOperation].pickups[41].container={}
            elseif mode=='scope-marker'then s.scope.marker={}
            elseif mode=='scope-seal-replaced'then s.scope[marker]=function()invoked=invoked+1;error('replacement deferred seal executed')end
            elseif mode=='throw'then error('native metadata unavailable')
            else check(s.settlement.nativePlanCohort(s.queue,s.groups)==nil,'deferred metadata reentered private cohort')end
        end
        return metadata(callback)
    end
    local fresh=s.settlement.nativePlanCohort(s.queue,s.groups)
    check((type(fresh)=='function')==(mode=='nested'),mode..': deferred source boundary renewed stale captures')
    check(invoked==0,mode..': replaced deferred seal executed')
    getFilenameOfClosure=metadata
end
do
    local seals={}
    local s=preparedFixture(true,function(proof)
        local original=proof.closure
        proof.closure=function(callback,...)
            check(not seals[callback],'prepared private seal reached retained SourceProof cache')
            return original(callback,...)
        end
    end)
    for _,action in ipairs({s.front,s.action})do
        local _,marker=actualRecord(action);seals[action.toolkitQueueOperation[marker]]=true
    end
    local _,_,seal=scopeLedger(s.scope);seals[seal]=true
    local fresh=assert(s.settlement.nativePlanCohort(s.queue,s.groups));check(fresh())
end
for _,mode in ipairs({'later-record','earlier-candidate','ledger-mutation','scope-mutation'})do
    local s=preparedFixture();local second=addPreparedGroup(s,43)
    local record,marker=actualRecord(second.body)
    local seal=second.body.toolkitQueueOperation[marker]
    local ledger=scopeLedger(s.scope)
    getFilenameOfClosure=function(callback)
        if callback==seal then
            if mode=='later-record'then record.steps[2].receipt={}
            elseif mode=='earlier-candidate'then s.candidate.sourceOwner.id=99
            elseif mode=='ledger-mutation'then ledger.executors[s.group.fetch]={}
            else s.scope.tasks[s.front.toolkitQueueOperation].items[41]=true end
        end
        return metadata(callback)
    end
    check(s.settlement.nativePlanCohort(s.queue,s.groups)==nil,mode..': shared scope recaptured a later seal mutation')
    getFilenameOfClosure=metadata
end
-- Common scope/ledger snapshots and native filename reads are independent of
-- the number of groups. Each real operation still needs its own seal read.
local preparedBase
for _,size in ipairs({1,2,4})do
    local originalPairs,watched,counts=pairs,{},{}
    pairs=function(owner)
        local name=watched[owner]
        if name then counts[name]=(counts[name]or 0)+1 end
        return originalPairs(owner)
    end
    local ok,result=pcall(function()
        local s=preparedFixture()
        for index=2,size do addPreparedGroup(s,41+index)end
        local ledger,_,scopeSeal=scopeLedger(s.scope)
        watched[s.scope],watched[ledger.candidates]='scope','candidates'
        local seals,scopeReads,operationReads={},0,0
        for _,action in ipairs(s.queue.queue)do
            local _,marker=actualRecord(action);seals[action.toolkitQueueOperation[marker]]=true
        end
        getFilenameOfClosure=function(callback)
            if callback==scopeSeal then scopeReads=scopeReads+1
            elseif seals[callback]then operationReads=operationReads+1 end
            return metadata(callback)
        end
        local fresh=assert(s.settlement.nativePlanCohort(s.queue,s.groups));check(fresh())
        check(scopeReads==1 and operationReads==size+1,'shared scope repeated source lookup or skipped real operation proof')
        return {scope=counts.scope,candidates=counts.candidates}
    end)
    pairs=originalPairs;getFilenameOfClosure=metadata
    check(ok,result)
    if preparedBase then
        check(result.scope==preparedBase.scope and result.candidates==preparedBase.candidates,
            'common producer scope/ledger work repeated per group')
    else preparedBase=result end
end
local function removedPrepared(s)
    local group=s.group;local token=group.body.toolkitQueueOperation
    local members={group.body,group.fetch,group.approach}
    s.queue.queue={s.front};token.toolkitCancelled=true
    return token,members
end
do
    local s=preparedFixture();local ledger=scopeLedger(s.scope)
    local old=s.group;local candidate=s.candidate;local record=s.groupRecord
    local token,members=removedPrepared(s)
    check(s.settlement.discardUnstartedPickups(s.queue,token,members))
    check(s.scope.tasks[token]==nil and ledger.actions[old.fetch]==nil and ledger.executors[old.fetch]==nil
        and #ledger.candidates==0,'cancelled group kept live producer claims')
    for _,member in ipairs(members)do check(s.scope.seen[member]==nil,'cancelled action remained seen')end
    check(record.borrowings[1].candidate==candidate and candidate.phase=='waived'
        and candidate.waiverReason=='cancelled-before-start','cancellation erased private waived history')
    check(s.settlement.context(s.scope),'real post-discard presentation context unavailable')
    local replacement=addPreparedGroup(s,41,old.item)
    s.groups={[replacement.body.toolkitQueueOperation]=replacement}
    local replacementRecord=actualRecord(replacement.body)
    check(not replacementRecord.borrowings[1].candidate.ambiguous,'old waived episode poisoned same-item retry')
    local fresh=assert(s.settlement.nativePlanCohort(s.queue,s.groups));check(fresh(),
        'same exact item could not acquire a fresh private prepared group after cancellation')
end
do
    local s=preparedFixture();local other=addPreparedGroup(s,43)
    local ledger=scopeLedger(s.scope);local otherRecord=actualRecord(other.body)
    local otherCandidate=otherRecord.borrowings[1].candidate
    local executors=ledger.executors[other.fetch]
    local token=s.group.body.toolkitQueueOperation;token.toolkitCancelled=true
    s.queue.queue={s.front,other.approach,other.fetch,other.body}
    check(s.settlement.discardUnstartedPickups(s.queue,token,{s.group.body,s.group.fetch,s.group.approach}))
    check(#ledger.candidates==1 and ledger.candidates[1]==otherCandidate and otherCandidate.phase=='prepare'
        and ledger.actions[other.fetch]==otherCandidate and ledger.executors[other.fetch]==executors,
        'cancellation removed or changed a neighboring live candidate')
    s.groups={[other.body.toolkitQueueOperation]=other};s.settlement.context(s.scope)
    local fresh=assert(s.settlement.nativePlanCohort(s.queue,s.groups));check(fresh(),
        'cancellation blocked the untouched neighboring prepared group')
end
for _,mode in ipairs({'task-unknown','task-foreign-action','task-missing-action','task-seen','task-pickup',
    'task-alias','other-task-action','ledger-action-alias','ledger-executor-alias','late-task','late-seen','late-executor'})do
    local s=preparedFixture();local token,members=removedPrepared(s)
    local ledger,_,seal=scopeLedger(s.scope)
    local task=s.scope.tasks[token];local foreign={character=s.actor,toolkitQueueOperation={}}
    if mode=='task-unknown'then task.unknownInputs=true
    elseif mode=='task-foreign-action'then task.actions[foreign]=true
    elseif mode=='task-missing-action'then task.actions[s.group.body]=nil
    elseif mode=='task-seen'then s.scope.seen[s.group.body]=nil
    elseif mode=='task-pickup'then task.pickups[90]={container=s.group.source,fullType='Base.Other'}
    elseif mode=='task-alias'then s.scope.tasks[{}]=task
    elseif mode=='other-task-action'then s.scope.tasks[s.front.toolkitQueueOperation].actions[s.group.body]=true
    elseif mode=='ledger-action-alias'then ledger.actions[foreign]=s.candidate
    elseif mode=='ledger-executor-alias'then ledger.executors[foreign]={[41]=s.candidate}
    else getFilenameOfClosure=function(callback)
        if callback==seal then
            if mode=='late-task'then task.actions[s.group.body]=nil
            elseif mode=='late-seen'then s.scope.seen[foreign]=true
            else ledger.executors[foreign]={[41]=s.candidate}end
        end
        return metadata(callback)
    end end
    check(not s.settlement.discardUnstartedPickups(s.queue,token,members),mode..': foreign/unknown live claims released')
    check(s.candidate.phase=='prepare'and s.scope.tasks[token]==task and ledger.actions[s.group.fetch]==s.candidate,
        mode..': rejected release partially changed live ownership')
    getFilenameOfClosure=metadata
end
for _,stale in ipairs({false,true})do
    local s=preparedFixture();local token,members=removedPrepared(s)
    s.queue.queue={};s.queue.current=stale and s.group.approach or nil
    check(s.settlement.discardUnstartedPickups(s.queue,token,members),
        'last never-admitted group required a remaining active reader')
end
do
    local s=preparedFixture();s.settlement.context(s.scope)
    local token,members=removedPrepared(s)
    local before=s.callbacks()
    s.actor.getInventory=function()error('unstarted discard read physical inventory')end
    s.group.item.getID=function()error('unstarted discard read item ID')end
    check(s.settlement.discardUnstartedPickups(s.queue,token,members),'real removed unstarted pickup was not retired')
    check(s.candidate.phase=='waived'and s.candidate.waiverReason=='cancelled-before-start'and s.callbacks()==before,
        'unstarted discard invented a completion or invoked gameplay getters')
    check(s.groupRecord.steps[2].state=='pending'and s.groupRecord.steps[2].receipt==nil,
        'unstarted waiver fabricated a paid step')
    check(not s.settlement.discardUnstartedPickups(s.queue,token,members),'historical waiver was accepted again')
end
for _,mode in ipairs({'queued','not-cancelled','partial','duplicate','history','started','native','transaction','receipt','required',
    'callback','proof','attempt','active','planned-return','executor','handle','generation','foreign-seal','late-private','late-hint'})do
    local s=preparedFixture()
    local token,members=removedPrepared(s)
    local ledger,marker,seal=scopeLedger(s.scope)
    local invoked=0
    if mode=='queued'then s.queue.queue[2]=s.group.fetch
    elseif mode=='not-cancelled'then token.toolkitCancelled=nil
    elseif mode=='partial'then members[3]=nil
    elseif mode=='duplicate'then members[3]=members[2]
    elseif mode=='history'then s.groupRecord.steps[4]=s.groupRecord.steps[1]
    elseif mode=='started'then s.groupRecord.steps[2].started=true
    elseif mode=='native'then s.group.fetch.action={}
    elseif mode=='transaction'then s.group.fetch.transactionId=12
    elseif mode=='receipt'then s.groupRecord.steps[3].receipt={}
    elseif mode=='required'then s.groupRecord.steps[3].required=true
    elseif mode=='callback'then s.group.fetch.onCompleteFunc=function()error('discard callback executed')end
    elseif mode=='proof'then s.candidate.proof={}
    elseif mode=='attempt'then s.candidate.attempt=1
    elseif mode=='active'then s.candidate.phase='active'
    elseif mode=='planned-return'then s.candidate.plannedReturn={}
    elseif mode=='executor'then ledger.executors[s.group.fetch][41]={}
    elseif mode=='handle'then ledger.handles[s.group.fetch]={}
    elseif mode=='generation'then s.queue.toolkitOperationGeneration=1
    elseif mode=='foreign-seal'then s.scope[marker]=function()invoked=invoked+1;error('discard invoked foreign scope')end
    else getFilenameOfClosure=function(callback)
        if callback==seal then
            if mode=='late-private'then s.groupRecord.steps[3].receipt={}
            else token.toolkitPickups[s.group.item]={}end
        end
        return metadata(callback)
    end end
    check(not s.settlement.discardUnstartedPickups(s.queue,token,members),mode..': unknown/paid/partial pickup was discarded')
    check(s.candidate.phase~='waived'and invoked==0,mode..': invalid discard mutated bookkeeping or invoked foreign seal')
    getFilenameOfClosure=metadata
end
-- The role metadata/source matcher below is an explicit test double. Native
-- pickup/effect receipts and private records are produced by real Settlement
-- APIs; this does not claim native actor, transport or getter provenance.
local function retainedFixture(waiting)
    local role={source=true,line=147,calls=0}
    local s=preparedFixture(true,function(proof)
        proof.matches=function(path,adler,mod,fresh)
            check(path=='media/lua/client/PZSurvivorToolkit/ActionQueueTidyIntent.lua'and adler==1408351481
                and mod=='PZSurvivorToolkit'and fresh==true,'explicit getter source role loosened')
            return role.source
        end
    end)
    s.role=role
    local root,source,item,body,fetch=s.actor.root,s.group.source,s.group.item,s.group.body,s.group.fetch
    root.items={};source.items={[41]=item}
    root.getItemById=function(self,id)return self.items[id]end
    source.getItemById=function(self,id)return self.items[id]end
    root.isExistYet=function()return true end;source.isExistYet=function()return true end
    s.actor.getOnlineID=function()return 101 end
    s.actor.getPrimaryHandItem=function(self)return self.primary end
    s.actor.getSecondaryHandItem=function(self)return self.secondary end
    getTimestampMs=function()return 100 end
    fetch.action={};fetch.queueList={{items={item}}}
    s.queue.current=fetch;s.queue.queue={fetch,body}
    s.lifecycle.started(fetch);fetch.toolkitQueueOperation.toolkitStarted=true
    check(s.settlement.beginPickup(s.scope,fetch,function(action)return action==fetch end),'real pickup receipt did not bind')
    s.pickup=s.candidate.proof;s.member=s.candidate.member
    local function finish()
        source.items[41]=nil;root.items[41]=item;item.container=root;fetch.queueList={}
        check(s.settlement.finishPickup(s.scope,fetch,true),'real pickup did not finish')
    end
    if not waiting then finish()end
    -- Explicit effect may be observed while the pickup observer still waits;
    -- the retry case below finishes the same genuine receipt, never replaces it.
    root.items[41]=item;source.items[41]=nil;item.container=root
    body.action={};body.primary=true;body.twoHands=false
    s.queue.current=body;s.queue.queue={body}
    s.lifecycle.started(body);s.actor.primary=item
    s.receipt=s.settlement.captureEffect(body)
    check(s.settlement.confirmEffect(s.receipt,true),'real explicit effect receipt not confirmed')
    local getter=function(action,receipt)
        role.calls=role.calls+1
        if s.mutate then s.mutate()end
        if action==body and receipt==s.receipt and role.accepted~=false then return{id=role.id or 41,fullType=role.fullType or'Base.Test'}end
    end
    PZSurvivorToolkit.ActionQueueTidyIntent.confirmedEquipmentIntent=getter
    getFilenameOfClosure=function(callback)
        if callback==getter then return 'fixture/ActionQueueTidyIntent.lua'end
        return metadata(callback)
    end
    getFirstLineOfClosure=function(callback)if callback==getter then return role.line end;return 1 end
    s.getter=getter
    s.finishPickup=finish
    s.retain=function(receipt)return s.settlement.retainExplicitEquipment(body,receipt or s.receipt)end
    return s
end
do
    local s=retainedFixture();local ledger=scopeLedger(s.scope)
    local paid,proof,member=s.candidate,s.pickup,s.member
    local handle=ledger.handles[s.group.fetch]
    local pending=addPreparedGroup(s,43)
    local token=pending.body.toolkitQueueOperation;token.toolkitCancelled=true
    s.queue.queue={s.group.body}
    check(s.settlement.discardUnstartedPickups(s.queue,token,{pending.body,pending.fetch,pending.approach}))
    check(#ledger.candidates==1 and ledger.candidates[1]==paid and paid.phase=='active'
        and paid.proof==proof and paid.member==member and member.completed==true
        and ledger.handles[s.group.fetch]==handle,'unstarted cancellation altered a neighboring earned receipt')
end
do
    local s=cohortFixture(2)
    getFirstLineOfClosure=function()error('root no-borrow Equip paid getter metadata work')end
    s.actor.getInventory=function()error('root no-borrow Equip scanned inventory')end
    s.proof.matches=function()error('root no-borrow Equip hashed prepared source')end
    check(s.settlement.retainExplicitEquipment(s.action,{})==true,'root no-own-borrow fast path rejected')
end
for _,both in ipairs({false,true})do
    local s=retainedFixture()
    s.group.body.twoHands=both;if both then s.actor.secondary=s.group.item end
    check(s.retain()==true,'confirmed explicit equipment loan was not retained')
    check(s.candidate.phase=='waived'and s.candidate.waiverReason=='explicit-equipment-intent'
        and s.member.completed==true and s.groupRecord.steps[2].state=='earned',
        'explicit retention fabricated/removed native payment')
    check(s.retain()==true,'settled explicit loan did not remain settled')
end
do
    local s=retainedFixture()
    local consumer={character=s.actor,toolkitQueueOperation={},item=s.group.item}
    check(s.settlement.remember(s.scope,consumer,{knownInputs=true,items={[41]=true},equipment=s.actor}))
    s.queue.queue[2]=consumer
    check(s.retain()==true,'future native consumer blocked already-confirmed explicit retention')
end
do
    local s=retainedFixture(true)
    s.pickup.active.authority=nil -- Real beginPickup before its terminal observation.
    check(s.retain()==nil and s.candidate.phase=='prepare','genuine pending native pickup lost retry')
    s.pickup.active.authority='native';s.finishPickup()
    check(s.candidate.phase=='active'and s.member.completed,'existing poll did not promote real pickup')
    check(s.retain()==true and s.candidate.phase=='waived','same confirmed explicit proof could not retry')
end
for _,mode in ipairs({'foreign-getter','wrong-line','wrong-source','foreign-receipt','copied-receipt','unconfirmed','wrong-id','wrong-type',
    'returning','planned','ambiguous','rejected','unknown','root-missing','wrong-hand','opposite-only','duplicate-source','foreign-member','late-private','late-receipt',
    'late-module','late-root','nested','throw'})do
    local s=retainedFixture();local item=s.group.item;local body=s.group.body
    local receipt=s.receipt
    if mode=='foreign-getter'then PZSurvivorToolkit.ActionQueueTidyIntent.confirmedEquipmentIntent=function()error('foreign intent getter executed')end
    elseif mode=='wrong-line'then s.role.line=148
    elseif mode=='wrong-source'then s.role.source=false
    elseif mode=='foreign-receipt'then
        local foreign={character=s.actor,toolkitQueueOperation={},action={}}
        receipt=s.settlement.captureEffect(foreign);check(s.settlement.confirmEffect(receipt,true))
    elseif mode=='copied-receipt'then
        receipt={};for key,value in pairs(s.receipt)do receipt[key]=value end
    elseif mode=='unconfirmed'then receipt=s.settlement.captureEffect(body)
    elseif mode=='wrong-id'then s.role.id=43
    elseif mode=='wrong-type'then s.role.fullType='Base.Other'
    elseif mode=='returning'then s.candidate.returning={}
    elseif mode=='planned'then s.candidate.plannedReturn={}
    elseif mode=='ambiguous'then s.candidate.ambiguous=true
    elseif mode=='rejected'then s.pickup.active.terminal='rejected'
    elseif mode=='unknown'then s.pickup.active.terminal='unavailable'
    elseif mode=='root-missing'then s.actor.root.items[41]=nil
    elseif mode=='wrong-hand'then s.actor.primary={}
    elseif mode=='opposite-only'then s.actor.primary=nil;s.actor.secondary=item
    elseif mode=='duplicate-source'then s.group.source.items[41]=item
    elseif mode=='foreign-member'then s.candidate.member={}
    elseif mode=='late-private'then s.mutate=function()s.candidate.returning={}end
    elseif mode=='late-receipt'then s.mutate=function()
        for _,seal in pairs(s.receipt)do local effect=seal(s.receipt);effect.confirmed=false end
    end
    elseif mode=='late-module'then s.mutate=function()PZSurvivorToolkit.ActionQueueTidyIntent={}end
    elseif mode=='late-root'then
        item.getFullType=function()s.candidate.plannedReturn={};return 'Base.Test'end
    elseif mode=='nested'then s.mutate=function()check(s.retain()==false,'intent getter reentered private settlement')end
    else s.mutate=function()error('confirmed intent getter unavailable')end end
    local retained=s.retain(receipt)
    check(retained==(mode=='nested')and s.candidate.phase==(mode=='nested'and'waived'or'active'),
        mode..': unsupported/stale intent waived a native loan')
end
getFilenameOfClosure=metadata
print('Native-plan singleton and lease: real private ledger, source-boundary and later-getter invalidation, callback-free freshness passed.')
