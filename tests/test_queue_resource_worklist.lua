local Worklist=assert(loadfile(ProjectRoot..'/tests/support/queue_resource_worklist.lua'))()
local function footprint(items,owners,edits)return {items=items or {},owners=owners or {},edits=edits or {}}end
local function overlaps(left,right)
    for a in pairs(left)do for b in pairs(right)do if rawequal(a,b)then return true end end end
end
local function adjacent(a,b)
    if overlaps(a.items,b.items)or overlaps(a.items,b.owners)or overlaps(a.owners,b.items)then return true end
    for domain,keys in pairs(a.edits)do
        if b.edits[domain]and overlaps(keys,b.edits[domain])then return true end
    end
    return false
end
local function oracle(members,footprints,seeds)
    local found={};for member in pairs(seeds)do found[member]=true end
    local changed=true
    while changed do
        changed=false
        for _,candidate in ipairs(members)do
            if not found[candidate]then
                for _,member in ipairs(members)do
                    if found[member]and adjacent(footprints[candidate],footprints[member])then
                        found[candidate],changed=true,true;break
                    end
                end
            end
        end
    end
    return found
end
local function compare(members,footprints,seeds)
    local result=Worklist.collect(members,footprints,seeds)
    assert(result.status=='complete','ordinary graph was not completed')
    local expected=oracle(members,footprints,seeds)
    for _,member in ipairs(members)do
        assert(result.component[member]==expected[member],'worklist differs from independent pair graph')
    end
    assert(result.counters.incidenceVisits<=result.counters.references,'a resource bucket was expanded more than once')
    return result
end
local function bit(value,index)return math.floor(value/2^index)%2==1 end
local exhaustive=0
for graph=0,511 do
    local members,footprints={{},{},{}},{}
    for index,member in ipairs(members)do
        footprints[member]=footprint(bit(graph,(index-1)*3)and {[1]=true}or {},
            bit(graph,(index-1)*3+1)and {[1]=true}or {},
            bit(graph,(index-1)*3+2)and {location={[1]=true}}or {})
    end
    for seedMask=0,7 do
        local seeds={};for index,member in ipairs(members)do if bit(seedMask,index-1)then seeds[member]=true end end
        compare(members,footprints,seeds);exhaustive=exhaustive+1
    end
end
local state=1729
local function random(maximum)state=(state*48271)%2147483647;return state%maximum+1 end
local randomCases=1500
for case=1,randomCases do
    local members,footprints,seeds={},{},{}
    for index=1,random(8)do
        local member={};members[index]=member
        local value=footprint(nil,nil,{location={},device={}});footprints[member]=value
        for resource=1,5 do
            for _,set in ipairs({value.items,value.owners,value.edits.location,value.edits.device})do
                if random(5)==1 then set[resource]=true end
            end
        end
        if random(3)==1 then seeds[member]=true end
    end
    compare(members,footprints,seeds)
end

do
    local equalCalls=0
    local mt={__eq=function()equalCalls=equalCalls+1;error('opaque identity equality callback executed')end}
    local a,b=setmetatable({},mt),setmetatable({},mt)
    local first,second,third=setmetatable({},mt),setmetatable({},mt),{}
    local members={first,second,third}
    local footprints={[first]=footprint({[a]=true}),[second]=footprint({[b]=true}),
        [third]=footprint(nil,nil,{item={[a]=true}})}
    local result=compare(members,footprints,{[first]=true})
    assert(result.component[first]and not result.component[second]and not result.component[third])
    assert(equalCalls==0,'resource lookup must preserve raw key identity')
end

local function stress(count,kind)
    local members,footprints={},{},{}
    for index=1,count do members[index]={}end
    for index,member in ipairs(members)do
        if kind=='reverse'then footprints[member]=footprint({[index]=true},index<count and {[index+1]=true}or {})
        elseif kind=='owners'then footprints[member]=footprint(nil,{bag=true})
        elseif kind=='dense'then footprints[member]=footprint({common=true})
        else footprints[member]=footprint({[index]=true},{bag=true},{location={[index]=true}})end
    end
    local seed=kind=='reverse'and members[count]or members[1]
    local result=Worklist.collect(members,footprints,{[seed]=true})
    assert(result.status=='complete')
    local expected=(kind=='reverse'or kind=='dense')and count or 1
    assert(result.counters.visits==expected,'shared owner or reverse-chain reachability changed')
    assert(result.counters.incidenceVisits<=result.counters.references)
    assert(result.counters.work<=20*(count+result.counters.references+1),'ordinary work exceeded its linear bound')
    return result.counters.work
end
for _,kind in ipairs({'reverse','owners','dense','disjoint'})do
    local small=stress(256,kind)
    local large=stress(1024,kind)
    assert(large<=4*small+32,'ordinary scaling gained a pair product: '..kind)
end

local function baseline()
    local a,b={},{}
    return {a,b},{[a]=footprint({key=true}),[b]=footprint(nil,{key=true})},{[a]=true}
end
local changes={
    function(m,f,s)m[3]=0/0 end,
    function(m,f,s)m[4]={}end,
    function(m,f,s)m[2]=m[1]end,
    function(m,f,s)f[m[2]]=false end,
    function(m,f,s)f[m[2]]=nil end,
    function(m,f,s)f[m[2]].unknown=true end,
    function(m,f,s)f[m[1]].items=setmetatable({},{__index=function()error('no callback')end})end,
    function(m,f,s)f[m[1]].items.key=false end,
    function(m,f,s)f[m[1]].items[math.huge]=true end,
    function(m,f,s)f[m[1]].items[function()end]=true end,
    function(m,f,s)f[m[1]].owners=nil end,
    function(m,f,s)f[m[1]].edits['']= {}end,
    function(m,f,s)f[m[1]].edits[true]={}end,
    function(m,f,s)f[m[1]].edits.device=false end,
    function(m,f,s)f[{}]=footprint()end,
    function(m,f,s)s[{}]=true end,
    function(m,f,s)s[m[1]]=false end,
}
for _,change in ipairs(changes)do
    local members,footprints,seeds=baseline();change(members,footprints,seeds)
    assert(Worklist.collect(members,footprints,seeds).status=='unsupported','malformed graph was accepted')
end
for _,limits in ipairs({{members=-1},{work=math.huge},{references=0/0},{references=1.5},{unexpected=1}})do
    local m,f,s=baseline();assert(Worklist.collect(m,f,s,limits).status=='unsupported')
end
for _,limits in ipairs({{members=1},{references=1},{work=0},{work=10}})do
    local m,f,s=baseline();local result=Worklist.collect(m,f,s,limits)
    assert(result.status=='limited','exhausted budget must never look complete')
    for field,value in pairs(limits)do assert(result.counters[field]<=value,'budget overshot')end
end
assert(Worklist.collect({},{},{},{members=0,references=0,work=0}).status=='complete')
print('Resource worklist: '..exhaustive..' exhaustive + '..randomCases..' random graph closures, raw identities, linear stress, malformed input and budgets passed.')
