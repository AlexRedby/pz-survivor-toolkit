-- Observation-only ledger tests. Private-state seams model retained native
-- outcomes; they do not establish transfer admission or authoritative receipts.
local settlementPath=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueSettlement.lua'
local function fixture()
    local actor={isDead=function()return false end}
    local token={}
    local current={character=actor,toolkitQueueOperation=token,Type='FixtureRead'}
    local queue={character=actor,current=current,queue={current}}
    PZSurvivorToolkit={Settings={actionQueue=function()return true end}}
    ISTimedActionQueue={queues={[actor]=queue}}
    Events={}
    getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
    local loaded={}
    local oldRequire=require
    require=function(name)
        if loaded[name]then return loaded[name]end
        local directory=({['PZSurvivorToolkit/SourceProof']='shared',
            ['PZSurvivorToolkit/ActionQueueTransferOutcome']='shared',
            ['PZSurvivorToolkit/ActionQueueTransferRequests']='client'})[name]
        if not directory then return oldRequire(name)end
        loaded[name]=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/'..directory..'/'..name..'.lua'))()
        return loaded[name]
    end
    local settlement=assert(loadfile(settlementPath))()
    require=oldRequire
    local function action()
        return {character=actor,toolkitQueueOperation=token,Type='FixtureCleanup'}
    end
    local function record()
        -- The test alone opens the source-owned seal to arrange private history.
        -- Production observers must never publish this record or its handles.
        for key,seal in pairs(token)do
            if type(key)=='table'and type(seal)=='function'then return seal(token),key end
        end
    end
    return {actor=actor,token=token,current=current,queue=queue,settlement=settlement,action=action,
        record=record,proof=loaded['PZSurvivorToolkit/SourceProof']}
end
local function unknown(result,message)
    assert(result.status=='unhandled'and result.reason=='edit_obligation_unknown',message)
    assert(result.steps==nil and result.borrowings==nil,'cutoffs must not expose partial observations')
end
local function observed(s)
    local result=s.settlement.editLedger(s.queue,s.current)
    assert(result.status=='observed')
    return result
end

do
    local s=fixture()
    unknown(s.settlement.editLedger(s.queue,s.current),'missing history cannot imply no debt')
    assert(next(s.token)==nil,'observation created a private operation')
    local prepare=s.settlement.track(s.current,'prepare')
    local cleanup=s.action()
    assert(s.settlement.cleanupAfter(cleanup,{prepare}))
    local record=s.record()
    record.steps[1].state='earned'
    record.steps[1].started=true
    record.steps[2].returning={private=true}
    local source,destination,planned={},{},s.action()
    record.borrowings[1]={scope={private=true},candidate={id=7,fullType='Base.Book',phase='active',owner=s.token,
        source=source,destination=destination,sourceOwner={id=8,fullType='Base.Bag'},
        returning={private=true},plannedReturn=planned}}
    s.token.toolkitPickups={[{}]={}}
    s.settlement.register('fixture',{retain=function()error('provider must not execute')end})
    local function forbidden()error('observation invoked a callback or native operation')end
    PZSurvivorToolkit.Settings.actionQueue=forbidden
    PZSurvivorToolkit.ActionQueuePolicy={inspect=forbidden}
    s.actor.isDead=forbidden
    s.settlement.pollPickups=forbidden
    s.settlement.returnState=forbidden
    getSpecificPlayer=forbidden
    ISInventoryTransferUtil={newInventoryTransferAction=forbidden}
    isItemTransactionDone,isItemTransactionRejected=forbidden,forbidden
    getTimestampMs=forbidden
    local beforePhase=record.phase
    local poll
    for index=1,40 do
        local name,value=debug.getupvalue(s.settlement.preparePickup,index)
        if name=='pollPickups'then poll=value;break end
        if name==nil then break end
    end
    assert(type(poll)=='function','fixture did not identify private polling boundary')
    debug.sethook(function()
        assert(debug.getinfo(2,'f').func~=poll,'observation polled native outcome state')
    end,'c')
    local first,second=observed(s),observed(s)
    debug.sethook()
    assert(first.generation==0 and first.legacyHints and first.providersPresent)
    assert(first.steps[1].action==s.current and first.steps[1].phase=='prepare'and first.steps[1].state=='earned'
        and first.steps[1].started and not first.steps[1].required)
    assert(first.steps[2].action==cleanup and first.steps[2].required and first.steps[2].returning)
    local borrowed=first.borrowings[1]
    assert(borrowed.id==7 and borrowed.fullType=='Base.Book'and borrowed.state=='active'and not borrowed.ambiguous
        and borrowed.source==source and borrowed.destination==destination and borrowed.plannedReturn==planned and borrowed.returning)
    assert(first~=second and first.steps~=second.steps and first.steps[1]~=second.steps[1]
        and borrowed~=second.borrowings[1]and borrowed.sourceOwner~=second.borrowings[1].sourceOwner)
    first.steps[1].state='invented';first.steps[2].required=false;borrowed.sourceOwner.id=99
    first.steps[3]={};first.borrowings[2]={}
    assert(record.steps[1].state=='earned'and record.steps[2].required==nil
        and record.borrowings[1].candidate.sourceOwner.id==8 and #record.steps==2 and #record.borrowings==1)
    assert(record.phase==beforePhase and record.steps[2].state=='pending','observation advanced settlement')
    local allowedStep={action=true,phase=true,state=true,started=true,required=true,returning=true}
    for key,value in pairs(second.steps[2])do assert(allowedStep[key]and type(value)~='function')end
    local allowedBorrow={id=true,fullType=true,state=true,ambiguous=true,source=true,destination=true,
        sourceOwner=true,returning=true,plannedReturn=true}
    for key,value in pairs(second.borrowings[1])do assert(allowedBorrow[key]and type(value)~='function')end
    for _,phase in ipairs({'prepare','active','unavailable','completed','waived'})do
        local candidate=record.borrowings[1].candidate
        candidate.phase,candidate.ambiguous,candidate.returning,candidate.plannedReturn=phase,true,nil,nil
        local result=observed(s)
        assert(result.borrowings[1].state==phase and result.borrowings[1].ambiguous
            and not result.borrowings[1].returning and result.borrowings[1].plannedReturn==nil,
            'unknown or unearned metadata was promoted into an earned obligation')
    end
    record.steps[1].state='pending'
    assert(not observed(s).steps[2].required,'unearned prerequisite cannot require cleanup')
    record.steps[2].required=true
    assert(observed(s).steps[2].required,'private mandatory cleanup must remain visible')
end

for _,mode in ipairs({'generation','registry-reset','list-reentry','foreign-actor','foreign-token','foreign-head',
    'cancelled','cancel','group-cancel','resume','outcome','stop','settled','foreign-seal','proof-replaced','source-reentry'})do
    local s=fixture();s.settlement.track(s.current,'body')
    local record,key=s.record()
    assert(observed(s).status=='observed')
    if mode=='generation'then s.queue.toolkitOperationGeneration=1
    elseif mode=='registry-reset'then ISTimedActionQueue.queues={}
    elseif mode=='list-reentry'then
        getFilenameOfClosure=function(callback)
            s.queue.queue={s.current}
            return debug.getinfo(callback,'S').source
        end
    elseif mode=='foreign-actor'then s.current.character={}
    elseif mode=='foreign-token'then s.current.toolkitQueueOperation={}
    elseif mode=='foreign-head'then s.queue.queue[1]=s.action()
    elseif mode=='cancelled'then s.token.toolkitCancelled=true
    elseif mode=='cancel'then s.queue.toolkitCancel=s.current
    elseif mode=='group-cancel'then s.queue.toolkitGroupCancel={}
    elseif mode=='resume'then s.queue.toolkitResume=s.current
    elseif mode=='outcome'then s.queue.toolkitOutcomeWait={}
    elseif mode=='stop'then s.queue.toolkitStopIntent={}
    elseif mode=='settled'then record.settlement={}
    elseif mode=='foreign-seal'then s.token[key]=function()error('foreign seal must not execute')end
    elseif mode=='proof-replaced'then s.proof.closure=function()error('foreign source proof must not execute')end
    elseif mode=='source-reentry'then
        getFilenameOfClosure=function(callback)
            s.queue.current=s.action()
            return debug.getinfo(callback,'S').source
        end
    end
    unknown(s.settlement.editLedger(s.queue,s.current),mode)
end

for _,mode in ipairs({'steps','borrowings','prerequisites'})do
    local s=fixture();s.settlement.track(s.current,'body');local record=s.record()
    if mode=='steps'then
        for _=2,33 do s.settlement.track(s.action(),'body')end
    elseif mode=='borrowings'then
        for index=1,33 do record.borrowings[index]={candidate={}}end
    else
        local cleanup=s.action();s.settlement.track(cleanup,'cleanup')
        local previous=record.steps[1]
        record.steps[2].prerequisites={}
        for index=1,129 do record.steps[2].prerequisites[index]=previous end
    end
    unknown(s.settlement.editLedger(s.queue,s.current),mode..' bounded work')
end

do
    local s=fixture();s.settlement.track(s.current,'body')
    s.token.toolkitPickups={[{}]={}}
    local result=observed(s)
    assert(result.legacyHints and #result.borrowings==0 and result.steps[1].state=='pending'
        and not result.steps[1].required,'enqueue hints cannot create earned borrowing evidence')
    local record=s.record()
    for _=2,32 do s.settlement.track(s.action(),'body')end
    local prerequisite=record.steps[1]
    for index=2,5 do
        record.steps[index].prerequisites={}
        for position=1,32 do record.steps[index].prerequisites[position]=prerequisite end
    end
    assert(#observed(s).steps==32,'supported bounds must remain observable')
    record.steps[6].prerequisites={prerequisite}
    unknown(s.settlement.editLedger(s.queue,s.current),'prerequisite budget must cover the whole record')
end
print('Queue edit ledger: bounded fresh metadata, cleanup dependencies, uncertainty and mutation-free observation passed.')

do
    local s=fixture()
    s.settlement.track(s.current,'body')
    s.token.toolkitPickups={}
    assert(not observed(s).legacyHints,'an empty enqueue map cannot add a synthetic obligation')
    s.token.toolkitPickups={[{}]={}}
    assert(observed(s).legacyHints)
end

do
    local s=fixture()
    s.settlement.track(s.current,'body')
    local record=s.record()
    local missing=setmetatable({toolkitQueueOperation=s.token},{__index=function()error('metadata invoked a foreign action lookup')end})
    local step={operation=record,action=missing,phase='cleanup',state='pending'}
    record.steps[2]=step;record.actions[missing]=step
    unknown(s.settlement.editLedger(s.queue,s.current),'missing public action metadata must not invoke a callback')
end

do
    local s=fixture()
    s.settlement.track(s.current,'body')
    local record=s.record()
    assert(record.list==nil,'private operation must not retain an entire historical queue array')
    s.queue.queue={s.current}
    assert(observed(s).status=='observed',
        'a fresh view of the same episode must preserve its private debt after array replacement')
end
