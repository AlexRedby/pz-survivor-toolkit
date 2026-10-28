-- Development-only connectivity experiment. Does not inspect actions or grant edits.
-- collect(members, footprints, seeds, limits) -> {status, component, counters, reason?}
-- members: dense ordered array of unique opaque identities.
-- footprints[member]: exactly {items=set, owners=set, edits={domain=set}};
-- sets contain only true values. Domain names are nonempty strings. Resource
-- keys and member identities may be finite numbers, strings, booleans, tables
-- or userdata; table/userdata equality is raw identity, without callbacks.
-- seeds: member set. Empty seeds are valid. Every footprint is checked, including
-- disconnected ones; unknown/complex input returns 'unsupported'.
-- limits: optional {members=4096, references=65536, work=262144}. Each bound
-- is a nonnegative integer <= 2147483647. Exceeding one returns 'limited'.
-- Only 'complete' means graph closure finished. No status is permission to edit;
-- partial components from other statuses are diagnostics, never usable results.
-- Edges: item-item, item-owner in either direction, equal domain/key edits.
-- Owner-owner references alone never connect. Worklist enqueue follows native
-- member order within each resource bucket; each bucket is expanded once.
-- Counters measure bounded loops, not elapsed time or allocator overhead:
-- members/references/buckets/visits/bucketVisits/incidenceVisits/work.
local Worklist={}
local defaults={members=4096,references=65536,work=262144}
local function plain(value)return type(value)=='table'and getmetatable(value)==nil end
local function finite(value)
    return type(value)=='number'and value==value and value>-math.huge and value<math.huge
end
local function key(value)
    local kind=type(value)
    return kind=='table'or kind=='userdata'or kind=='string'or kind=='boolean'or finite(value)
end
function Worklist.collect(members,footprints,seeds,limits)
    local counters={members=0,references=0,buckets=0,visits=0,bucketVisits=0,incidenceVisits=0,work=0}
    local result={status='unsupported',component={},counters=counters,reason='shape'}
    if not plain(members)or not plain(footprints)or not plain(seeds)
        or limits~=nil and not plain(limits)then return result end
    local bound={}
    for name,value in pairs(limits or {})do
        if defaults[name]==nil or not finite(value)or value<0 or value%1~=0 or value>2147483647 then
            result.reason='limits';return result
        end
        bound[name]=value
    end
    for name,value in pairs(defaults)do if bound[name]==nil then bound[name]=value end end
    local function spend(name)
        local value=counters[name]+1
        if value>bound[name]then result.status,result.reason='limited',name;return false end
        counters[name]=value
        return true
    end
    local positions,records={},{}
    local count,maximum=0,0
    for index,member in pairs(members)do
        if not spend('work')or not spend('members')then return result end
        if not finite(index)or index<1 or index%1~=0 or not key(member)or positions[member]then return result end
        count=count+1;maximum=math.max(maximum,index);positions[member]=index
    end
    if maximum~=count then return result end
    for member in pairs(footprints)do
        if not spend('work')then return result end
        if not key(member)or not positions[member]then return result end
    end
    local itemBuckets,ownerBuckets,editBuckets={},{},{}
    local function append(index,buckets,resource)
        if not spend('work')or not spend('references')then return false end
        local bucket=buckets[resource]
        if not bucket then bucket={members={}};buckets[resource]=bucket;counters.buckets=counters.buckets+1 end
        bucket.members[#bucket.members+1]=index
        return true
    end
    local function capture(index,set,buckets,keys)
        if not plain(set)then return false end
        for resource,value in pairs(set)do
            if not key(resource)or value~=true then return false end
            if not append(index,buckets,resource)then return false end
            keys[#keys+1]=resource
        end
        return true
    end
    for index=1,count do
        if not spend('work')then return result end
        local footprint=footprints[members[index]]
        if not plain(footprint)then result.reason='footprint';return result end
        for field in pairs(footprint)do
            if not spend('work')then return result end
            if field~='items'and field~='owners'and field~='edits'then return result end
        end
        local record={items={},owners={},edits={}};records[index]=record
        if not capture(index,footprint.items,itemBuckets,record.items)
            or not capture(index,footprint.owners,ownerBuckets,record.owners)
            or not plain(footprint.edits)then return result end
        for domain,resources in pairs(footprint.edits)do
            if not spend('work')then return result end
            if type(domain)~='string'or domain==''then return result end
            local buckets=editBuckets[domain]
            if not buckets then buckets={};editBuckets[domain]=buckets end
            local keys={}
            if not capture(index,resources,buckets,keys)then return result end
            for _,resource in ipairs(keys)do record.edits[#record.edits+1]=buckets[resource]end
        end
    end
    for member,value in pairs(seeds)do
        if not spend('work')then return result end
        if not key(member)or value~=true or not positions[member]then result.reason='seeds';return result end
    end
    local pending={}
    local function enqueue(index)
        local member=members[index]
        if not result.component[member]then result.component[member]=true;pending[#pending+1]=index end
    end
    for index=1,count do
        if not spend('work')then return result end
        if seeds[members[index]]then enqueue(index)end
    end
    local function scan(bucket)
        if not bucket or bucket.scanned then return true end
        bucket.scanned=true;counters.bucketVisits=counters.bucketVisits+1
        for _,index in ipairs(bucket.members)do
            if not spend('work')then return false end
            counters.incidenceVisits=counters.incidenceVisits+1;enqueue(index)
        end
        return true
    end
    local cursor=1
    while cursor<=#pending do
        if not spend('work')then return result end
        local record=records[pending[cursor]];cursor=cursor+1;counters.visits=counters.visits+1
        for _,resource in ipairs(record.items)do
            if not spend('work')or not scan(itemBuckets[resource])or not scan(ownerBuckets[resource])then return result end
        end
        for _,resource in ipairs(record.owners)do
            if not spend('work')or not scan(itemBuckets[resource])then return result end
        end
        for _,bucket in ipairs(record.edits)do
            if not spend('work')or not scan(bucket)then return result end
        end
    end
    result.status,result.reason='complete',nil
    return result
end
return Worklist
