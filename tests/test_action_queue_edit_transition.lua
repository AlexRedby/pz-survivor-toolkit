local prefix=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/'
-- Offline Lua models the JVM's actual-metatable check explicitly. Native
-- Kahlua runs use the real exported helper instead of this fixture.
if not toolkitLuaMetatableMatches and debug and debug.getmetatable then
    local fixtureType,fixtureEqual,fixtureMeta=type,rawequal,debug.getmetatable
    toolkitLuaMetatableMatches=function(owner,expected)
        return fixtureType(owner)=='table'and fixtureEqual(fixtureMeta(owner),expected)
    end
end
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
-- Fresh ownership supplies an exact future return payload, never a resource
-- permission or an existing executor. Effect compilation is a separate gate.
do
    local book,cleanup,prototype,later={},{},{},{}
    local root,box={},{}
    local returnEdit={version=1,complete=true,capacity='external',resources={{domain='item',key=4,
        facts={item=book,location=root},requires={{field='location',oneOf={root,box}}},effects={{field='location',set=box}}}}}
    local checkpoint=edit({{domain='item',key=4,facts={item=book,location=root},effects={}}})
    local rows={entry(current,nil,true),entry(cleanup),entry(prototype,returnEdit),entry(later)}
    local loan={id=4,fullType='Base.Book',state='active',ambiguous=false,returning=false,
        disposition='synthesize-return',item=book,source=root,destination=box,edit=returnEdit}
    local fresh={status='observed',fresh=true,generation=7,steps={{action=cleanup,required=true}},
        borrowings={loan},legacyHints=false,providersPresent=false}
    local plan=project(rows,'cancel-operation',1,3,checkpoint,fresh)
    local future=sequence(plan)
    assert(plan.status=='observed'and plan.allowed==nil and plan.projection.status=='unhandled'
        and plan.projection.externalCapacity and #plan.unresolved==0)
    assert(#future==3 and future[1].kind=='cleanup'and future[1].action==cleanup)
    assert(future[2].kind=='return'and future[2].synthetic and future[2].action==nil and future[2].edit==nil
        and future[2].item==book and future[2].destination==box and future[2].source==root)
    assert(future[3].action==later and #plan.removed==2 and plan.removed[2]==prototype,
        'old optional return must be removed; only a virtual future return may precede the tail')
    assert(rows[3].edit==returnEdit and loan.edit==returnEdit,'caller descriptors must remain unchanged')
    -- Only a final native/source-qualified marker compiles the location effect;
    -- arbitrary caller edits above remain ignored. Capacity is still external.
    loan.effect='native-leaf-location'
    local exact=project(rows,'cancel-operation',1,3,checkpoint,fresh)
    local exactFuture=sequence(exact)
    assert(exact.projection.status=='allowed'and exact.allowed==nil and exact.projection.externalCapacity)
    local declaration=exactFuture[2].edit
    assert(declaration.version==1 and declaration.complete and declaration.capacity=='external')
    local resource=declaration.resources[1]
    assert(#declaration.resources==1 and resource.domain=='item'and resource.key==4
        and resource.facts.item==book and resource.facts.location==root
        and resource.requires[1].equal==root and resource.effects[1].set==box)
    local dependent=edit({{domain='item',key=4,facts={item=book,location=root},
        requires={{field='location',equal=root}},effects={}}})
    rows[4].edit=dependent
    assert(project(rows,'cancel-operation',1,3,checkpoint,fresh).projection.reason=='edit_required_state',
        'independent tail requiring the book in root must see the virtual return effect')
    rows[4].edit=edit();loan.effect=nil
    for _,phase in ipairs({'completed','waived'})do
        loan.disposition,loan.state='settled',phase
        local settled=project(rows,'cancel-operation',1,3,checkpoint,fresh)
        assert(settled.projection.status=='allowed'and #sequence(settled)==2,'settled loan resurrected its return')
    end
    loan.disposition,loan.state='synthesize-return','active'
    for _,boundary in ipairs({'metadata','hint','provider','shared','ambiguous','returning','planned','unearned','unearned-settled','missing-item','same-endpoint'})do
        if boundary=='metadata'then fresh.fresh=nil
        elseif boundary=='hint'then fresh.legacyHints=true
        elseif boundary=='provider'then fresh.providersPresent=true
        elseif boundary=='shared'then loan.disposition='unresolved'
        elseif boundary=='ambiguous'then loan.ambiguous=true
        elseif boundary=='returning'then loan.returning=true
        elseif boundary=='planned'then loan.plannedReturn={}
        elseif boundary=='unearned'then loan.state='prepare'
        elseif boundary=='unearned-settled'then loan.disposition,loan.state='settled','prepare'
        elseif boundary=='missing-item'then loan.item=nil
        elseif boundary=='same-endpoint'then loan.destination=root end
        local result=project(rows,'cancel-operation',1,3,checkpoint,fresh)
        assert(result.projection.status=='unhandled'and #result.unresolved>0,boundary..': incomplete ownership was presented as exact')
        fresh.fresh,fresh.legacyHints,fresh.providersPresent=true,false,false
        loan.disposition,loan.state,loan.ambiguous,loan.returning='synthesize-return','active',false,false
        loan.plannedReturn=nil;loan.item=book;loan.destination=box
    end
end
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
-- The prepared projection validates source before fresh facts and does not
-- call the metadata accessor afterward, even when that accessor stays live.
do
    local accessor=getFilenameOfClosure
    local armed,reads=false,0
    getFilenameOfClosure=function(callback)
        reads=reads+1
        assert(not armed,'prepared projection invoked late source metadata')
        return accessor(callback)
    end
    local prepared=assert(T.prepare())
    assert(reads>0)
    armed=true
    local count=reads
    local result=prepared(before,{kind='cancel-body',first=1,last=1,generation=7,checkpoint=edit()})
    assert(result.status=='observed'and reads==count)
    assert(prepared(before,{kind='cancel-body',first=1,last=1,generation=7,checkpoint=edit()}).status=='unhandled',
        'a prepared source lease is one-use, never a cached queue decision')
    getFilenameOfClosure=accessor
    local stale=assert(T.prepare())
    getFilenameOfClosure=function()error('replacement metadata must not execute')end
    assert(stale(before,{kind='cancel-body',first=1,last=1,generation=7,checkpoint=edit()}).status=='unhandled')
    getFilenameOfClosure=accessor
end
-- A final fact read may remove an own source field and install __index, or
-- replace a primitive used by the projection. Preparation must reject those
-- changes using captured reads before either hostile callback can run.
do
    local call,setMeta,getMeta=pcall,setmetatable,getmetatable
    local toolkit=PZSurvivorToolkit
    local evaluate,modelMeta=Model.evaluate,getMeta(Model)
    local modelSlot,toolkitMeta=toolkit.ActionQueueEditModel,getMeta(toolkit)
    local maximum=math.max
    for _,boundary in ipairs({'model-meta','module-meta','math-max'})do
        local prepared=assert(T.prepare())
        local lateCalls=0
        local function hostile()lateCalls=lateCalls+1;error('post-facts source callback')end
        if boundary=='model-meta'then Model.evaluate=nil;setMeta(Model,{__index=hostile})
        elseif boundary=='module-meta'then toolkit.ActionQueueEditModel=nil;setMeta(toolkit,{__index=hostile})
        else math.max=hostile end
        local ok,result=call(prepared,before,{kind='cancel-body',first=1,last=1,generation=7,checkpoint=edit()})
        setMeta(Model,modelMeta);Model.evaluate=evaluate
        setMeta(toolkit,toolkitMeta);toolkit.ActionQueueEditModel=modelSlot;math.max=maximum
        assert(ok and result.status=='unhandled'and lateCalls==0,boundary..': prepared projection executed a late callback')
    end
end
local saved=Model.evaluate
Model.evaluate=function()calls=calls+1;error('replaced model')end
assert(project(before,'preempt',3,5).status=='unhandled')
Model.evaluate=saved
assert(calls==0)
require=previousRequire
print('Edit transition: paid checkpoint, resumed requirements, range ordering and uncertain cleanup passed')

-- Retain the original native pending return across a preempt/body cancellation;
-- only an exact fresh earned witness supplies its missing resource descriptor.
do
 local item,root,destination={},{},{}
 local returning={}
 local rows={entry(current,nil,true),{action=returning},entry(power),entry(tail)}
 local loan={id=91,fullType='Base.Book',state='active',ambiguous=false,returning=false,
  disposition='synthesize-return',item=item,source=root,destination=destination,
  effect='native-leaf-location',returnAction=returning}
 local ledger={status='observed',fresh=true,generation=7,providersPresent=false,legacyHints=false,steps={},borrowings={loan}}
 local result=project(rows,'preempt',3,3,edit(),ledger)
 assert(result.status=='observed'and result.projection.status=='allowed')
 local found
 for _,node in ipairs(result.nodes)do if node.action==returning then found=node end end
 assert(found and found.kind=='pending'and found.edit.complete and found.edit.capacity=='external')
 assert(rows[2].edit==nil and found.edit.resources[1].facts.item==item,'retained contract mutated native input or item identity')
 assert(project(rows,'cancel-body',1,1,edit(),ledger).projection.status=='allowed')
 -- The final native loan witness is fresher than an earlier ordinary inspection.
 local earlier={version=1,complete=false,capacity='external',resources={}}
 rows[2].edit=earlier
 local fresh=project(rows,'preempt',3,3,edit(),ledger)
 assert(fresh.projection.status=='allowed'and rows[2].edit==earlier,'fresh retained effect must not reuse or mutate an earlier descriptor')
 for _,node in ipairs(fresh.nodes)do if node.action==returning then
  assert(node.edit~=earlier and node.edit.resources[1].facts.item==item,'final loan facts lost precedence')
 end end
 rows[2].edit=nil
 for _,key in ipairs({'fresh','providersPresent','legacyHints'})do
  local old=ledger[key];ledger[key]=not old
  assert(project(rows,'preempt',3,3,edit(),ledger).projection.status=='unhandled',key)
  ledger[key]=old
 end
 for _,change in ipairs({'action','effect','state','duplicate'})do
  local a,e,state=loan.returnAction,loan.effect,loan.state
  if change=='action'then loan.returnAction={}
  elseif change=='effect'then loan.effect=nil
  elseif change=='state'then loan.state='pending'
  else ledger.borrowings[2]=loan end
  assert(project(rows,'preempt',3,3,edit(),ledger).projection.status=='unhandled',change)
  loan.returnAction,loan.effect,loan.state=a,e,state;ledger.borrowings[2]=nil
 end
end
