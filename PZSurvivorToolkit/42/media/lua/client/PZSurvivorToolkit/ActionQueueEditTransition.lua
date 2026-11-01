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
local function modelBindingsReady()
    return rawequal(PZSurvivorToolkit,Toolkit)and rawequal(Toolkit.ActionQueueEditTransition,Transition)
        and rawequal(Toolkit.ActionQueueEditModel,Model)and Model and Model.evaluate==evaluate
        and Proof and Proof.closure==origin and type(origin)=='function'
end
local function modelReady()
    return modelBindingsReady()and origin(evaluate,'ActionQueueEditModel.lua')and modelBindingsReady()
end
local function project(entries,change,prepared)
    local count=array(entries)
    if not count or count==0 or not plain(change)or not plain(change.checkpoint)
        or not integer(change.first,1,count)or not integer(change.last,change.first,count)or not integer(change.generation,0,math.huge)
        or not (prepared and modelBindingsReady()or not prepared and modelReady())then return unknown()end
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
        seen[entry.action]=i
    end
    local current=entries[1].action
    local plan={status='observed',kind=change.kind,generation=change.generation,nodes={},removed={},unresolved={}}
    local declarations,externalCapacity={},false
    local function node(kind,action,edit,snapshotOnly)
        local value={kind=kind,action=action,edit=edit}
        externalCapacity=externalCapacity or plain(edit)and edit.capacity=='external'
        plan.nodes[#plan.nodes+1]=value
        -- Resume/checkpoint are virtual instructions, never existing native actions to execute.
        declarations[#declarations+1]={action=(kind=='checkpoint'or kind=='resume'or kind=='return')and value or action,
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
        local debts,loanIds={}, {}
        if not steps or not borrowings or ledger.generation~=change.generation then
            debts[#debts+1]={kind='unresolved'}
        else
            if type(ledger.legacyHints)~='boolean'or type(ledger.providersPresent)~='boolean'
                or ledger.fresh~=nil and type(ledger.fresh)~='boolean'then return unknown('edit_obligation_unknown')end
            providerUnknown=ledger.providersPresent
            for i=1,steps do
                local step=ledger.steps[i]
                if not plain(step)or not identity(step.action)or type(step.required)~='boolean'then return unknown('edit_obligation_unknown')end
                if step.required then retained[step.action]=true end
            end
            for i=1,borrowings do
                local borrowing=ledger.borrowings[i]
                if not plain(borrowing)then return unknown('edit_obligation_unknown')end
                local copy={}
                for _,key in ipairs({'id','fullType','state','ambiguous','source','destination','returning','plannedReturn','disposition'})do
                    copy[key]=borrowing[key]
                end
                if borrowing.sourceOwner then
                    if not plain(borrowing.sourceOwner)then return unknown('edit_obligation_unknown')end
                    copy.sourceOwner={id=borrowing.sourceOwner.id,fullType=borrowing.sourceOwner.fullType}
                end
                if ledger.fresh and borrowing.disposition=='settled'
                    and (borrowing.state=='completed'or borrowing.state=='waived')then
                    -- Irreversible private disposition, never enqueue hints.
                elseif ledger.fresh and borrowing.disposition=='synthesize-return'and not providerUnknown then
                    if borrowing.state~='active'or borrowing.ambiguous~=false or borrowing.returning~=false
                        or borrowing.plannedReturn~=nil or type(borrowing.id)~='number'or borrowing.id%1~=0 or loanIds[borrowing.id]
                        or type(borrowing.fullType)~='string'or borrowing.fullType==''
                        or not identity(borrowing.item)or not identity(borrowing.source)or not identity(borrowing.destination)
                        or rawequal(borrowing.source,borrowing.destination) then
                        debts[#debts+1]={kind='unresolved',detail=copy}
                    else
                        loanIds[borrowing.id]=true
                        debts[#debts+1]={kind='return',borrowing=borrowing}
                    end
                else
                    -- Metadata phase alone is not exclusive ownership or a receipt.
                    debts[#debts+1]={kind='unresolved',detail=copy}
                end
            end
            if ledger.legacyHints then debts[#debts+1]={kind='unresolved',detail={kind='enqueue-hints'}}end
        end
        -- Keep existing earned cleanup first. Exact return payloads still lack
        -- a jointly fresh native effect contract: never recycle an old executor.
        for i=1,change.last do
            local entry=entries[i]
            if i>1 and retained[entry.action]then node('cleanup',entry.action,entry.edit)
            elseif i>1 and providerUnknown then uncertain('edit_obligation_unknown',{kind='pending-disposition',action=entry.action})
            else plan.removed[#plan.removed+1]=entry.action end
        end
        for _,debt in ipairs(debts)do
            if debt.kind=='return'then
                local borrowing=debt.borrowing
                local value=node('return',nil,nil)
                value.item,value.id,value.fullType=borrowing.item,borrowing.id,borrowing.fullType
                externalCapacity=true
                value.source,value.destination=borrowing.source,borrowing.destination
                value.synthetic=true
            else uncertain('edit_obligation_unknown',debt.detail)end
        end
        for i=change.last+1,count do node('pending',entries[i].action,entries[i].edit)end
    end
    -- The resource model remains pending-only: current effects enter only as a
    -- separately declared snapshot; its original active entry is never evaluated.
    if not (prepared and modelBindingsReady()or not prepared and modelReady())then return unknown()end
    plan.projection=#plan.unresolved>0 and unknown('edit_obligation_unknown')or evaluate(declarations)
    plan.projection.externalCapacity=externalCapacity
    return plan
end
-- Source validation can call the live metadata accessor. Prepare it before
-- reading fresh obligations; the one-use projection then performs only bindings
-- and plain-data work, never a post-observation metadata callback.
function Transition.prepare()
    if not modelReady()then return end
    local accessor=getFilenameOfClosure
    local used=false
    return function(entries,change)
        if used then return unknown()end
        used=true
        if getFilenameOfClosure~=accessor or not modelBindingsReady()then return unknown()end
        return project(entries,change,true)
    end
end
function Transition.project(entries,change)return project(entries,change,false)end
return Transition
