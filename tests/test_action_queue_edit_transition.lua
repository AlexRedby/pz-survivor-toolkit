local prefix=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/'
PZSurvivorToolkit={}
getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
local modules={}
local previousRequire=require
require=function(name)
    if modules[name]then return modules[name]end
    if name=='PZSurvivorToolkit/ActionQueueEditModel'then
        modules[name]=assert(loadfile(prefix..'client/'..name..'.lua'))();return modules[name]
    end
    if name=='PZSurvivorToolkit/SourceProof'then
        modules[name]=assert(loadfile(prefix..'shared/'..name..'.lua'))();return modules[name]
    end
    return previousRequire(name)
end
local Model=require 'PZSurvivorToolkit/ActionQueueEditModel'
local T=assert(loadfile(prefix..'client/PZSurvivorToolkit/ActionQueueEditTransition.lua'))()
local function edit(resources)return {version=1,complete=true,capacity='unchanged',resources=resources or {}}end
local function entry(action,descriptor,active)return {action=action,edit=descriptor or edit(),active=active}end
local function project(entries,kind,first,last,checkpoint,ledger)
    return T.project(entries,{kind=kind,first=first,last=last,generation=7,checkpoint=checkpoint or edit(),ledger=ledger})
end
local function sequence(plan)
    local result={}
    for _,node in ipairs(plan.nodes)do if node.kind~='checkpoint'then result[#result+1]=node end end
    return result
end
local current,returned,power,insert,play,tail={},{},{},{},{},{}
local before={entry(current,nil,true),entry(returned),entry(power),entry(insert),entry(play),entry(tail)}
local plan=project(before,'preempt',3,5)
assert(plan.status=='observed'and plan.allowed==nil and plan.projection.status=='allowed')
local nodes=sequence(plan)
assert(#nodes==6 and nodes[1].action==power and nodes[2].action==insert and nodes[3].action==play
    and nodes[4].kind=='resume'and nodes[4].action==current and nodes[5].action==returned and nodes[6].action==tail,
    'promoted range must precede reconstructed reader, still-owned return and unrelated tail')
assert(#plan.removed==0 and before[1].active and before[1].action==current)
local external=edit();external.capacity='external'
assert(project({entry(current,nil,true),entry(power,external)},'preempt',2,2).projection.externalCapacity,
    'a resource forecast must not erase the separate native capacity/admission boundary')
assert(Model.evaluate(before).reason=='edit_in_flight','the ordinary model must still reject the original active entry')
-- Range/property bank: exactly one future instance of every original pending action;
-- one virtual reader after the complete promoted range, with every other relative order retained.
for count=2,10 do
    local rows={entry(current,nil,true)}
    for i=2,count do rows[i]=entry({index=i})end
    for first=2,count do for last=first,count do
        local observed=project(rows,'preempt',first,last)
        assert(observed.status=='observed')
        local future,seen=sequence(observed),{}
        assert(#future==count and future[last-first+2].kind=='resume')
        local previousSelected,previousRest=0,0
        for index,node in ipairs(future)do
            if node.kind~='resume'then
                local original=node.action.index
                assert(not seen[original]);seen[original]=true
                if original>=first and original<=last then assert(original>previousSelected);previousSelected=original
                else assert(original>previousRest and index>last-first+2);previousRest=original end
            end
        end
        for i=2,count do assert(seen[i])end
    end end
end
-- Current facts already include paid effects. Do not replay the old active command.
local stock,itemKey,root,box={},{},{},{}
local checkpoint=edit({{domain='stock',key=stock,facts={amount=1},effects={}}})
local paid=edit({{domain='stock',key=stock,facts={amount=1},effects={{field='amount',delta=-1}},bounds={amount={min=0}}}})
local consume=edit({{domain='stock',key=stock,facts={amount=1},requires={{field='amount',min=1}},effects={{field='amount',delta=-1}},bounds={amount={min=0}}}})
local observed=project({entry(current,paid,true),entry(power,consume)},'preempt',2,2,checkpoint)
assert(observed.projection.status=='allowed','active paid effect was replayed')
local read=edit({{domain='item',key=itemKey,facts={location=root},requires={{field='location',equal=root}},effects={}}})
local move=edit({{domain='item',key=itemKey,facts={location=root},requires={{field='location',equal=root}},effects={{field='location',set=box}}}})
observed=project({entry(current,nil,true),entry(power,move)},'preempt',2,2,read)
assert(observed.projection.status=='denied'and observed.projection.reason=='edit_required_state'
    and observed.projection.blocker.kind=='resume','resumed reader must recheck its future item location')
local body=project(before,'cancel-body',1,1)
assert(#body.removed==1 and body.removed[1]==current and #sequence(body)==5)
local ledger={status='observed',generation=7,steps={{action=returned,required=true}},borrowings={},legacyHints=false,providersPresent=false}
local whole=project(before,'cancel-operation',1,2,nil,ledger)
nodes=sequence(whole)
assert(nodes[1].kind=='cleanup'and nodes[1].action==returned and nodes[2].action==power)
assert(#whole.removed==1 and whole.removed[1]==current,'earned cleanup cannot disappear with the operation')
ledger.steps[1].required=false
ledger.providersPresent=true
whole=project(before,'cancel-operation',1,2,nil,ledger)
assert(whole.projection.status=='unhandled'and #whole.removed==1,
    'a provider may retain the pending child: do not claim it removed')
ledger.providersPresent=false
ledger.borrowings={{id=4,fullType='Base.Book',state='active',source=box,destination=root,sourceOwner={id=8,fullType='Base.Bag'}}}
whole=project(before,'cancel-operation',1,2,nil,ledger)
assert(whole.projection.reason=='edit_obligation_unknown'and whole.unresolved[1].detail.id==4)
whole.unresolved[1].detail.sourceOwner.id=99
assert(ledger.borrowings[1].sourceOwner.id==8,'result must not mutate copied debt metadata')
ledger.borrowings={};ledger.legacyHints=true
assert(project(before,'cancel-operation',1,2,nil,ledger).projection.reason=='edit_obligation_unknown')
ledger.legacyHints=false;ledger.generation=8
assert(project(before,'cancel-operation',1,2,nil,ledger).projection.reason=='edit_obligation_unknown')
assert(project(before,'cancel-operation',1,2).projection.reason=='edit_obligation_unknown')
-- Input purity and unavailable schema/binding cases cannot execute arbitrary code.
local calls=0
local badMeta={__index=function()calls=calls+1;error('input callback')end}
assert(T.project(setmetatable({},badMeta),{}).status=='unhandled')
assert(project({entry(0/0,nil,true)},'cancel-body',1,1).status=='unhandled')
assert(project({entry(current,nil,true),entry(power,nil,true)},'preempt',2,2).reason=='edit_in_flight')
assert(project({entry(current,nil,true),entry(current)},'preempt',2,2).status=='unhandled')
assert(project(before,'preempt',1,2).status=='unhandled')
ledger.generation=7;ledger.steps={{action=0/0,required=true}}
assert(project(before,'cancel-operation',1,2,nil,ledger).status=='unhandled')
local saved=Model.evaluate
Model.evaluate=function()calls=calls+1;error('replaced model')end
assert(project(before,'preempt',3,5).status=='unhandled')
Model.evaluate=saved
assert(calls==0)
require=previousRequire
print('Edit transition: paid checkpoint, resumed requirements, range ordering and uncertain cleanup passed')
