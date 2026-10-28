-- Development-only bank. No action executes and no shipped source is changed.
-- Native Kahlua timings are CPU fixture measurements, not live UI/Host latency.
assert(NativeActionRoot and NativeReadText and BenchmarkNanoTime and BenchmarkEmit)
next = nil
local read = NativeReadText
getFilenameOfClosure = NativeFilenameOfClosure
getGameFilesInput = function(path)
    local text = read(NativeActionRoot .. '/' .. path:gsub('^media/lua/', '')):gsub('\r', '')
    local at = 1
    return {close=function()end, readLine=function()
        if at > #text then return end
        local boundary = text:find('\n', at, true) or #text + 1
        local line = text:sub(at, boundary - 1); at = boundary + 1; return line
    end}
end
local f = assert(loadfile(ProjectRoot .. '/tests/support/action_queue_native.lua'))()
f.native('shared/TimedActions/ISTransferAction.lua')
isClient = function()return false end
f.project('ActionQueueOperations'); f.project('ActionQueueDefinitions')
local model = f.project('ActionQueueEditModel')
assert(loadfile(ProjectRoot .. '/tests/test_queue_resource_worklist.lua'))()
local worklist = assert(loadfile(ProjectRoot .. '/tests/support/queue_resource_worklist.lua'))()
local savedRequire = require
require = function(name)
    if name == 'PZSurvivorToolkit/ActionQueueEditModel' then return model end
    return savedRequire(name)
end
local sourcePath = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueuePolicy.lua'
local source = read(sourcePath):gsub('\r', '')
local function replaceOnce(text, old, new)
    local first, last = text:find(old, 1, true)
    assert(first and not text:find(old, last + 1, true), 'benchmark source instrumentation anchor changed')
    return text:sub(1, first - 1) .. new .. text:sub(last + 1)
end
-- Explicit in-memory development instrumentation. Both variants use the actual
-- inspector, footprint extraction, final component validation and EditModel.
-- The candidate replaces only the fixed-point connectivity expansion.
_G.QueueResourceBenchmarkWorklist = worklist
local function policyVariant(candidate)
    local definitions=f.project('ActionQueueDefinitions')
    local text = source
    if candidate then
        local first = assert(text:find('    -- Capacity validation remains downstream.', 1, true))
        local changed = assert(text:find('    local changed = true', first, true))
        local last = assert(text:find('    local externalCapacity = false', changed, true))
        local body=text:sub(first,last-1)
        body=replaceOnce(body,'    local changed = true\n    while changed do',[[
    if not index then return {status='unhandled',reason='edit_unknown'} end
    for _,member in ipairs(members)do
        if not footprints[member]then return {status='unhandled',reason='edit_unknown'} end
    end
    local changed,passes = true,0
    while changed do
        if passes==1 then
            local remaining=false
            for _,member in ipairs(members)do if not component[member]then remaining=true;break end end
            -- The ordinary first sweep has already completed independent/star
            -- graphs. Only unresolved transitive growth needs another index.
            if remaining then
                local collected=QueueResourceBenchmarkWorklist.collect(members,footprints,component)
                Policy.benchmarkCounters=collected.counters
                if collected.status~='complete' then return {status='unhandled',reason='edit_unknown'} end
                component=collected.component
            end
            break
        end
        passes=passes+1]])
        text=text:sub(1,first-1)..body..text:sub(last)
    end
    text = replaceOnce(text, '\nreturn Policy', '\nPolicy.benchmarkComponent = editComponent\nreturn Policy')
    return assert(loadstring(text, '@' .. sourcePath))(),definitions
end
local baseline,baselineDefinitions=policyVariant(false)
local candidate,candidateDefinitions=policyVariant(true)
require = savedRequire
local toolkit = PZSurvivorToolkit
local pairChecks, inspections = 0, 0
local world = {sharesTarget=function()pairChecks=pairChecks+1 end}
local generators = {sharesTarget=function()pairChecks=pairChecks+1 end}
toolkit.ActionQueueWorld, toolkit.ActionQueueGenerators = world, generators
toolkit.ActionQueueCraft = {supports=function()return false end,collectItems=function()end,repairInputs=function()end}
for _, policy in ipairs({baseline,candidate}) do
    policy.registerTargetChecker('world',world,world.sharesTarget)
    policy.registerTargetChecker('generators',generators,generators.sharesTarget)
end
local class = ISBaseTimedAction:derive('QueueResourceBenchmarkFixture')
for _,definitions in ipairs({baselineDefinitions,candidateDefinitions})do
definitions.registerBehavior('fixture.queue-resource-benchmark', {
    types={'QueueResourceBenchmarkFixture'},matches=function(action)return getmetatable(action)==class end,
    inspect=function(action)inspections=inspections+1;return action.fixtureContract end})
end
local function action(id, owner)
    local value = f.action(class,{item=f.item('Base.Nails')})
    value.item.id = id
    value.fixtureContract = {items={[id]=true},itemTypes={['Base.Nails']=true},targets={},
        containerOwners=owner and {[owner]=true} or {}, knownInputs=true,cancelWaiting=true,
        edit={version=1,complete=true,capacity='unchanged',resources={
            {domain='item',key=id,facts={ready=false},requires={},effects={{field='ready',set=true}}}}}}
    return value
end
local function scene(kind, count)
    local members = {}
    for i=1,count do members[i]=action(i,kind=='shared-owner' and -1 or nil) end
    if kind=='reverse' then
        for i=1,count-1 do
            local left=members[i].fixtureContract.edit.resources
            left[#left+1]={domain='link',key=i,facts={ready=false},requires={},effects={}}
            local resources=members[i+1].fixtureContract.edit.resources
            resources[#resources+1]={domain='link',key=i,facts={ready=false},requires={},effects={}}
        end
    elseif kind=='owner-mutation' then
        members[count].fixtureContract.items[-1]=true
        for i=1,count-1 do members[i].fixtureContract.containerOwners[-1]=true end
    elseif kind=='unknown' then members[math.max(1,math.floor(count/2))].fixtureContract.knownInputs=false
    end
    local queue=f.queue(); queue.queue=members;queue.current=nil
    return queue,members
end
local function collect(policy,queue,members)
    policy.benchmarkCounters=nil
    return policy.benchmarkComponent(queue,members,{[members[#members]]=true},{contracts={},items={}})
end
local function same(a,b,members)
    assert(a.status==b.status and a.reason==b.reason and a.blocker==b.blocker,'component verdict changed')
    if a.status=='allowed' then
        for _,member in ipairs(members)do
            assert(not not a.component[member]==not not b.component[member],'component membership changed')
        end
        assert(a.externalCapacity==b.externalCapacity)
    end
end
local function quantile(sorted,p)return sorted[math.max(1,math.ceil(#sorted*p))]end
local measurements=0
local function measure(label,callback,stress)
    local samples=stress and math.min(BenchmarkSamples,3) or BenchmarkSamples
    local warmup=stress and math.min(BenchmarkWarmup,1) or BenchmarkWarmup
    for _=1,warmup do callback()end
    local times,bytes={},{}
    for i=1,samples do
        local memoryBefore=BenchmarkAllocatedBytes()
        local before=BenchmarkNanoTime()
        callback()
        local after=BenchmarkNanoTime()
        local memoryAfter=BenchmarkAllocatedBytes()
        times[i]=(after-before)/1000000
        if memoryBefore and memoryAfter then bytes[i]=memoryAfter-memoryBefore end
    end
    table.sort(times);table.sort(bytes)
    BenchmarkEmit(label..'/samples',samples)
    BenchmarkEmit(label..'/p50_ms',quantile(times,.5))
    BenchmarkEmit(label..'/p95_ms',quantile(times,.95))
    BenchmarkEmit(label..'/p99_ms',quantile(times,.99))
    BenchmarkEmit(label..'/max_ms',times[#times])
    if #bytes>0 then BenchmarkEmit(label..'/p50_alloc_bytes',quantile(bytes,.5))end
    measurements=measurements+1
end
local sections={}
for section in (BenchmarkSections or 'component,edit,model,weights'):gmatch('[^,]+')do sections[section]=true end
local maxSteps=BenchmarkMaxSteps or 1000
BenchmarkEmit('scope','Native Kahlua CPU fixtures; no live UI, gameplay, MP, network or weaker-client performance qualification')
BenchmarkEmit('candidate','Test-only adaptive hybrid: retain the production first sweep for independent/star resources, use a worklist for unresolved growth; production inspector/validation/EditModel. Weights remain baseline.')
BenchmarkEmit('budgets','Proposed end-to-end targets: advisory p95<=1ms p99<=2ms; authoritative edit p95<=2ms p99<=4ms. This CPU bank does not time an end-to-end Queue.move commit.')
BenchmarkEmit('counter_scope','legacy_target_callbacks counts only world/generator hooks, not all pair probes. Worklist counters exclude footprint extraction and the retained first sweep; no whole-candidate linearity claim.')
BenchmarkEmit('parity_scope','Only reviewed ordinary fixture footprints are compared; complex/custom production footprints remain unsupported in this test-only candidate.')
if sections.component then
for _,count in ipairs({10,50,200,1000}) do
    if count<=maxSteps then
    for _,kind in ipairs({'independent','shared-owner','reverse','owner-mutation','unknown'}) do
        local queue,members=scene(kind,count)
        same(collect(baseline,queue,members),collect(candidate,queue,members),members)
        for index,policy in ipairs({baseline,candidate}) do
            pairChecks,inspections=0,0
            collect(policy,queue,members)
            local label='component/'..kind..'/n'..count..'/'..(index==1 and 'baseline' or 'candidate')
            BenchmarkEmit(label..'/legacy_target_callbacks',pairChecks)
            BenchmarkEmit(label..'/inspections',inspections)
            if index==2 then BenchmarkEmit(label..'/worklist_used',candidate.benchmarkCounters~=nil) end
            if index==2 and candidate.benchmarkCounters then
                for _,key in ipairs({'work','references','incidenceVisits','bucketVisits'}) do
                    BenchmarkEmit(label..'/'..key,candidate.benchmarkCounters[key] or 0)
                end
            end
            measure(label,function()collect(policy,queue,members)end,count>200)
        end
    end
    end
end
end
-- Public Policy edit paths retain source/native stop checks and full projections.
if sections.edit then
for _,count in ipairs({10,50,200}) do
    if count<=maxSteps then
    for _,kind in ipairs({'independent','reverse'}) do
        local queue,members=scene(kind,count)
        local head=f.action(ISReadABook,{item=f.item('Base.BookFirstAid1')})
        table.insert(members,1,head);queue.current=head
        local target=members[2]
        for index,policy in ipairs({baseline,candidate})do
            local label='edit/'..kind..'/n'..count..'/'..(index==1 and 'baseline' or 'candidate')
            local result=policy.evaluateMove(queue,members[#members],target,false)
            local other=(index==1 and candidate or baseline).evaluateMove(queue,members[#members],target,false)
            for _,key in ipairs({'allowed','reason','blocker','resource','to','first','last'})do
                assert(rawequal(result[key],other[key]),'public edit result changed: '..key)
            end
            BenchmarkEmit(label..'/allowed',tostring(result.allowed))
            BenchmarkEmit(label..'/reason',result.reason or 'none')
            measure(label,function()policy.evaluateMove(queue,members[#members],target,false)end,false)
        end
    end
    end
end
end
-- Exercise the actual pure evaluator separately. A steady snapshot is not
-- native transaction admission and no projected effect mutates the game.
if sections.model then
for _,count in ipairs({10,50,200,1000}) do
    if count<=maxSteps then
    local entries={}
    for i=1,count do entries[i]=action(i).fixtureContract.edit;entries[i]={action=i,edit=entries[i]}end
    assert(model.evaluate(entries).status=='allowed')
    measure('model/n'..count,function()model.evaluate(entries)end,count>200)
    end
end
end
-- Production weight baseline: unique nested endpoint requests, not an inflated
-- repeated-call comparison. Java endpoint getters are explicit doubles here;
-- timings isolate Lua traversal and underestimate native getter/bridge cost.
local reads,enumerations=0,0
instanceof=function(value,kind)return type(value)=='table' and (value.class==kind or kind=='InventoryItem' and
    (value.class=='InventoryContainer' or value.class=='Food'))end
getClassSimpleName=function(value)return value.nativeName or value.class end
ItemTag={LIGHT_WHEN_ATTACHED='light'}
local function impure()error('benchmark must not invoke a factory/impure weight getter')end
InventoryItemFactory={CreateItem=impure}
local function list(items)
    return {size=function()return #items end,get=function(_,i)reads=reads+1;return items[i+1]end}
end
local function plain(weight)
    return {class='InventoryItem',nativeName='ComboItem',raw=weight,
        getUnequippedWeight=function(self)return self.raw end,getEquippedWeight=function(self)return self.raw*.3 end,
        getAttachedSlot=function()return -1 end,isFakeEquipped=function()return false end,
        getActualWeightUnmodded=function(self)return self.raw end,getFluidContainer=function()end,
        getWorldItem=function()end,getAmmoType=function()end,getContainer=function(self)return self.container end}
end
local function box(owner)
    return {class='ItemContainer',owner=owner,items={},getContainingItem=function(self)return self.owner end,
        getParent=function(self)return self.parent end,getAcceptItemFunction=function()end,getOnlyAcceptCategory=function()end,
        getItems=function(self)enumerations=enumerations+1;return list(self.items)end,
        getCapacityWeight=function()return 0 end}
end
local function put(item,container)item.container=container;container.items[#container.items+1]=item;return item end
local function weightedScene(count,depth,worn)
    local actor={class='IsoPlayer'};local root=box();root.parent=actor
    actor.getInventory=function()return root end;actor.isEquipped=function(_,item)return item.equipped==true end
    local containers={root};local current=root
    put(plain(1),root) -- existing real-weight witness, no factory
    for i=1,depth do
        local bag=plain(2);bag.class='InventoryContainer';bag.inventory=box(bag);bag.equipped=worn and i==1
        bag.getInventory=function(self)return self.inventory end;bag.getWeightReduction=function()return 80 end
        bag.getUnequippedWeight=impure;bag.getEquippedWeight=impure
        put(bag,current);current=bag.inventory;containers[#containers+1]=current
    end
    for _=1,count do put(plain(.1),current)end
    local food=plain(.5);food.class='Food';food.haveExtraItems=function()return true end
    food.getExtraItems=function()return list({'Base.BenchmarkIngredient'})end
    food.getHungChange=function()return -.06 end;food.getBaseHunger=function()return -.06 end
    food.getReplaceOnUse=function()end;food.getReplaceOnUseFullType=function()end
    food.getUnequippedWeight=impure;food.getEquippedWeight=impure
    put(food,current)
    local ingredient={getItemType=function()return 'base:food'end,getHungerChange=function()return -12 end,
        getActualWeight=function()return .2 end,getLuaCreate=function()end,getItemConfig=function()end,
        getItemConfigKey=function()end,hasComponents=function()return false end,getReplaceOnUse=function()end}
    ScriptManager={instance={getItem=function(_,kind)if kind=='Base.BenchmarkIngredient'then return ingredient end end}}
    return actor,containers
end
local weights=assert(loadfile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueWeights.lua'))()
if sections.weights then
for _,count in ipairs({100,1000,10000})do
    for _,depth in ipairs({1,4,8})do
        for _,worn in ipairs({false,true})do
            local actor,containers=weightedScene(count,depth,worn)
            local function capture()
                for _,container in ipairs(containers)do
                    local upper=weights.capacity(container,actor)
                    assert(type(upper)=='number' and upper>=0,'weight snapshot unsupported')
                end
            end
            reads,enumerations=0,0;capture()
            local label='weight-baseline/items'..count..'/depth'..depth..'/'..(worn and 'worn' or 'nested')
            BenchmarkEmit(label..'/item_reads',reads);BenchmarkEmit(label..'/container_enumerations',enumerations)
            measure(label,capture,count>1000)
        end
    end
end
end
assert(measurements>0,'no benchmark cases selected')
BenchmarkEmit('measurements',measurements)
BenchmarkEmit('gate','incomplete: weight snapshot optimization, live idle/hover/drag/priority, retention and selected-pack Host contention are not qualified')
QueueResourceBenchmarkPassed=true
