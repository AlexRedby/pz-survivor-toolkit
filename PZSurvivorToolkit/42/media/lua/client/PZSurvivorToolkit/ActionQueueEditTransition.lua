-- Structural observation after a reviewed native stop. This never authorizes an edit.
local Model = require 'PZSurvivorToolkit/ActionQueueEditModel'
local Proof = require 'PZSurvivorToolkit/SourceProof'
local origin = Proof and Proof.closure
local evaluate = Model and Model.evaluate
local Toolkit = PZSurvivorToolkit
local Transition = {}
PZSurvivorToolkit.ActionQueueEditTransition = Transition
local LIMIT = 32
local function plain(value)return type(value)=='table'and getmetatable(value)==nil end
local function array(value)
    if not plain(value)then return end
    local count,maximum=0,0
    for key in pairs(value)do
        if type(key)~='number'or key~=key or key%1~=0 or key<1 or key>LIMIT then return end
        count,maximum=count+1,math.max(maximum,key)
    end
    if count==maximum then return count end
end
local function unknown(reason)return {status='unhandled',reason=reason or 'edit_unknown'}end
local function integer(value,minimum,maximum)
    return type(value)=='number'and value==value and value%1==0 and value>=minimum and value<=maximum
end
local function identity(value)
    local kind=type(value)
    return kind=='string'or kind=='boolean'or kind=='table'or kind=='userdata'
        or kind=='number'and value==value and math.abs(value)<math.huge
end
local function modelReady()
    return PZSurvivorToolkit==Toolkit and Toolkit.ActionQueueEditTransition==Transition
        and Toolkit.ActionQueueEditModel==Model and Model and Model.evaluate==evaluate
        and Proof and Proof.closure==origin and type(origin)=='function'
        and origin(evaluate,'ActionQueueEditModel.lua')and Model.evaluate==evaluate
        and Toolkit.ActionQueueEditModel==Model and Proof.closure==origin
end
function Transition.project(entries,change)
    local count=array(entries)
    if not count or count==0 or not plain(change)or not plain(change.checkpoint)
        or not integer(change.first,1,count)or not integer(change.last,change.first,count)or not integer(change.generation,0,math.huge)
        or not modelReady()then return unknown()end
    if change.kind~='preempt'and change.kind~='cancel-body'and change.kind~='cancel-operation'then return unknown()end
    if change.kind=='preempt'and change.first<2
        or change.kind~='preempt'and change.first~=1
        or change.kind=='cancel-body'and change.last~=1 then return unknown()end
    local seen={}
    for i=1,count do
        local entry=entries[i]
        if not plain(entry)or not identity(entry.action)or seen[entry.action]
            or (entry.active~=nil and type(entry.active)~='boolean')then return unknown()end
        if i==1 and entry.active~=true or i>1 and entry.active then return unknown('edit_in_flight')end
        seen[entry.action]=true
    end
    local current=entries[1].action
    local plan={status='observed',kind=change.kind,generation=change.generation,nodes={},removed={},unresolved={}}
    local declarations,externalCapacity={},false
    local function node(kind,action,edit,snapshotOnly)
        local value={kind=kind,action=action,edit=edit}
        externalCapacity=externalCapacity or plain(edit)and edit.capacity=='external'
        plan.nodes[#plan.nodes+1]=value
        -- Resume/checkpoint are virtual instructions, never existing native actions to execute.
        declarations[#declarations+1]={action=(kind=='checkpoint'or kind=='resume')and value or action,
            edit=edit,snapshotOnly=snapshotOnly}
        return value
    end
    local function uncertain(reason,detail)
        local value={kind='unresolved',reason=reason,detail=detail}
        plan.nodes[#plan.nodes+1]=value;plan.unresolved[#plan.unresolved+1]=value
    end
    node('checkpoint',current,change.checkpoint,true)
    if change.kind=='preempt'then
        for i=change.first,change.last do node('pending',entries[i].action,entries[i].edit)end
        node('resume',current,change.checkpoint)
        for i=2,count do
            if i<change.first or i>change.last then node('pending',entries[i].action,entries[i].edit)end
        end
    elseif change.kind=='cancel-body'then
        plan.removed[1]=current
        for i=2,count do node('pending',entries[i].action,entries[i].edit)end
    else
        local ledger=change.ledger
        local steps=plain(ledger)and ledger.status=='observed'and array(ledger.steps)
        local borrowings=steps and array(ledger.borrowings)
        local retained,providerUnknown={},true
        if not steps or not borrowings or ledger.generation~=change.generation then
            uncertain('edit_obligation_unknown')
        else
            if type(ledger.legacyHints)~='boolean'or type(ledger.providersPresent)~='boolean'then return unknown('edit_obligation_unknown')end
            providerUnknown=ledger.providersPresent
            for i=1,steps do
                local step=ledger.steps[i]
                if not plain(step)or not identity(step.action)or type(step.required)~='boolean'then return unknown('edit_obligation_unknown')end
                if step.required then retained[step.action]=true end
            end
            for i=1,borrowings do
                local borrowing=ledger.borrowings[i]
                if not plain(borrowing)then return unknown('edit_obligation_unknown')end
                -- Recorded phase is not fresh exclusive ownership or a physical receipt.
                -- Keep the obligation visible instead of inventing/removing its return.
                local copy={}
                for _,key in ipairs({'id','fullType','state','ambiguous','source','destination','returning','plannedReturn'})do
                    copy[key]=borrowing[key]
                end
                if borrowing.sourceOwner then
                    if not plain(borrowing.sourceOwner)then return unknown('edit_obligation_unknown')end
                    copy.sourceOwner={id=borrowing.sourceOwner.id,fullType=borrowing.sourceOwner.fullType}
                end
                uncertain('edit_obligation_unknown',copy)
            end
            if ledger.legacyHints then uncertain('edit_obligation_unknown',{kind='enqueue-hints'})end
        end
        -- Required cleanup precedes the unrelated tail, matching the native settlement boundary.
        -- Unknown provider/borrowed returns are placeholders, never constructor calls.
        local debtNodes=plan.nodes
        plan.nodes={debtNodes[1]}
        for i=1,change.last do
            local entry=entries[i]
            if i>1 and retained[entry.action]then node('cleanup',entry.action,entry.edit)
            elseif i>1 and providerUnknown then uncertain('edit_obligation_unknown',{kind='pending-disposition',action=entry.action})
            else plan.removed[#plan.removed+1]=entry.action end
        end
        for i=2,#debtNodes do plan.nodes[#plan.nodes+1]=debtNodes[i]end
        for i=change.last+1,count do node('pending',entries[i].action,entries[i].edit)end
    end
    -- The resource model remains pending-only: current effects enter only as a
    -- separately declared snapshot; its original active entry is never evaluated.
    if not modelReady()then return unknown()end
    plan.projection=#plan.unresolved>0 and unknown('edit_obligation_unknown')or evaluate(declarations)
    plan.projection.externalCapacity=externalCapacity
    return plan
end
return Transition
