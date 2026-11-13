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

getFilenameOfClosure=metadata
print('Native-plan singleton and lease: real private ledger, source-boundary and later-getter invalidation, callback-free freshness passed.')
