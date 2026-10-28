-- Development-only synchronous snapshot qualification. Valid ordinary scenes
-- match the stateless production API bit-for-bit; ambiguous union ownership is
-- a deliberately unsupported subset, including old aggregate-hidden aliases.
local fixture=assert(loadfile(ProjectRoot..'/tests/support/action_queue_weights_fixture.lua'))()
local setup=fixture.setup
setup() -- Install the ordinary test environment before loading the development module.
local Snapshot=assert(loadfile(ProjectRoot..'/tests/support/queue_weight_snapshot.lua'))()
local vectors=0
local function count(values)local n=0;for _ in pairs(values)do n=n+1 end;return n end
local function noPublish(result,status,label)
    assert(type(result)=='table'and result.status==status,(label or 'failure')..': expected '..status)
    assert(result.containers==nil and result.items==nil,(label or 'failure')..': failed captures must publish no partial maps')
    vectors=vectors+1;return result
end
local function parity(s,containers,items,label,limits)
    local expectedContainers,expectedItems={},{}
    for _,value in ipairs(containers or{})do
        local upper,lower=s.weights.capacity(value,s.actor)
        assert(upper~=nil and lower~=nil,label..': stateless container must be supported')
        expectedContainers[value]={upper=upper,lower=lower}
    end
    for _,value in ipairs(items or{})do
        local upper,lower=s.weights.unequipped(value)
        assert(upper~=nil and lower~=nil,label..': stateless item must be supported')
        expectedItems[value]={upper=upper,lower=lower}
    end
    local result=Snapshot.capture(s.actor,{containers=containers or{},items=items or{}},limits)
    assert(result.status=='complete',label..': valid scene became '..tostring(result.status)..'/'..tostring(result.reason))
    assert(type(result.containers)=='table'and type(result.items)=='table',label..': complete maps missing')
    for name,expected in pairs({containers=expectedContainers,items=expectedItems})do
        assert(count(result[name])==count(expected),label..': map contains missing or unrequested entries')
        for value,bound in pairs(expected)do local actual=result[name][value]
            assert(actual and actual.upper==bound.upper and actual.lower==bound.lower,
                label..': '..name..' upper/lower changed: '..tostring(actual and actual.upper)..'/'..tostring(actual and actual.lower)
                    ..' expected '..tostring(bound.upper)..'/'..tostring(bound.lower))
        end
    end
    assert(type(result.counters)=='table'and type(result.counters.nodes)=='number'and type(result.counters.edges)=='number',label..': bounded work evidence missing')
    vectors=vectors+1;return result
end
local function affected()
    local s=setup();s.witness=s.add(s.item(1),s.root)
    s.outer=s.bag(s.root);s.inner=s.bag(s.outer.inventory);s.foodItem=s.food(s.inner.inventory)
    s.other=s.add(s.item(.25),s.outer.inventory)
    s.root.getCapacityWeight=fixture.impure
    return s
end

-- Native aggregate values must survive: they intentionally differ from a sum
-- of the fixture's item weights. Zero is a known result, not unknown.
do
    local s=setup();local zero=s.add(s.item(0),s.root);local item=s.add(s.item(1.25),s.root);s.root.nativeLoad=.375
    local result=parity(s,{s.root},{zero,item},'native exact aggregates')
    assert(result.containers[s.root].upper==.375 and result.containers[s.root].lower==.375)
    assert(result.items[zero].upper==0 and result.items[zero].lower==0)
    parity(s,{s.root,s.root},{item,item,zero},'duplicate requests deduplicate')
    local world=s.container();world.parent={class='IsoObject'};world.nativeLoad=7.125
    local outside=s.add(s.item(99),world)
    result=parity(s,{world,s.root},{outside},'ordinary world native aggregate')
    assert(result.containers[world].upper==7.125)
end

-- Overlap is legitimate across output requests, irrespective of order; it is
-- ownership duplication within the graph that must fail.
for _,order in ipairs({'root-first','child-first','inner-first'})do
    local s=affected();local containers=order=='root-first'and{s.root,s.outer.inventory,s.inner.inventory}
        or order=='child-first'and{s.outer.inventory,s.inner.inventory,s.root}or{s.inner.inventory,s.root,s.outer.inventory}
    parity(s,containers,{s.outer,s.inner,s.foodItem,s.witness},'overlap '..order)
end

-- Cache keys must preserve weight mode. A nested inner bag is unequipped when
-- included in its parent's contents, even if a fixture flag claims otherwise.
for _,mode in ipairs({'unequipped','equipped','fake','hotbar','light-hotbar'})do
    for _,multiplier in ipairs({.3,2})do
        local s=affected();s.nativeMultiplier=multiplier
        s.outer.equipped=mode=='equipped';s.outer.fake=mode=='fake'
        s.outer.slot=(mode=='hotbar'or mode=='light-hotbar')and 0 or -1;s.outer.light=mode=='light-hotbar'
        s.inner.equipped=true;s.inner.reduction=100
        parity(s,{s.root,s.outer.inventory,s.inner.inventory},{s.outer,s.inner,s.foodItem},'bag mode '..mode..'/'..multiplier)
        s.foodItem.equipped=mode=='equipped';s.foodItem.fake=mode=='fake'
        -- Put extra Food at the root to exercise its equipped/hotbar path as well.
        local rootFood=s.food(s.root);rootFood.equipped=mode=='equipped';rootFood.fake=mode=='fake'
        rootFood.slot=s.outer.slot;rootFood.light=s.outer.light
        parity(s,{s.root},{rootFood},'food mode '..mode..'/'..multiplier)
    end
end
for _,reduction in ipairs({0,80,100})do
    local s=affected();s.outer.equipped=true;s.outer.reduction=reduction
    s.inner.fluid={class='FluidContainer',amount=.4,getOwner=function()return s.inner end,getAmount=function(self)return self.amount end}
    parity(s,{s.root,s.outer.inventory,s.inner.inventory},{s.outer,s.inner,s.foodItem},'nested fluid/reduction '..reduction)
end

-- Fresh captures must reflect changes and must not retroactively mutate a
-- previously returned map. No cross-decision cache may carry success or nil.
do
    local s=affected();local containers={s.root,s.outer.inventory,s.inner.inventory};local items={s.outer,s.foodItem}
    local first=parity(s,containers,items,'before mutation');local saved=first.containers[s.root].upper
    for _,mutation in ipairs({
        function()s.foodItem.hunger=-.03 end,
        function()s.extra.weight=.4 end,
        function()s.outer.equipped=true;s.outer.reduction=50 end,
        function()s.nativeMultiplier=2 end,
        function()s.add(s.item(3),s.inner.inventory)end,
        function()s.inner.fluid={class='FluidContainer',amount=.8,getOwner=function()return s.inner end,getAmount=function(self)return self.amount end}end,
        function()s.foodItem.raw=.8 end,
    })do mutation();parity(s,containers,items,'fresh changed decision')end
    assert(first.containers[s.root].upper==saved,'new decision mutated a previously published snapshot')
    s.extra.callback='unsafe'
    assert(s.weights.unequipped(s.foodItem)==nil,'corrupted script must be unknown in baseline')
    noPublish(Snapshot.capture(s.actor,{containers=containers,items=items}),'unsupported','success -> unknown')
    s.extra.callback=nil
    parity(s,containers,items,'unknown -> repaired fresh decision')
end

-- All graph aliases/cycles are rejected before arithmetic, including the old
-- numeric corner hidden behind a safe native aggregate subtree.
do
    local s=setup();local item=s.add(s.item(1),s.root);s.root.items[2]=item
    local reads=0;s.root.getCapacityWeight=function()reads=reads+1;return 123 end
    noPublish(Snapshot.capture(s.actor,{containers={s.root}}),'unsupported','duplicate direct item')
    assert(reads==0,'duplicate topology reached aggregate arithmetic')
end
do
    local s=affected();local safe=s.bag(s.root);local hidden=s.add(s.item(.5),safe.inventory)
    local reads=0;safe.getUnequippedWeight=function()reads=reads+1;return 17 end
    safe.getEquippedWeight=safe.getUnequippedWeight;safe.getHotbarEquippedWeight=safe.getUnequippedWeight
    -- Deliberately corrupt ownership without moving the original object.
    s.root.items[#s.root.items+1]=hidden
    assert(s.weights.capacity(s.root,s.actor)~=nil,'baseline must exercise the numeric hidden-safe alias corner')
    reads=0
    noPublish(Snapshot.capture(s.actor,{containers={s.root,safe.inventory},items={hidden}}),'unsupported','hidden safe alias')
    assert(reads==0,'global alias validation must precede native aggregate arithmetic')
end
for _,cycle in ipairs({'self','two-bags','shared-container'})do
    local s=affected();local second=s.bag(s.root)
    if cycle=='self'then s.inner.inventory.items[#s.inner.inventory.items+1]=s.outer
    elseif cycle=='two-bags'then second.inventory.items={s.outer};s.inner.inventory.items[#s.inner.inventory.items+1]=second
    else second.inventory=s.inner.inventory end
    noPublish(Snapshot.capture(s.actor,{containers={s.root},items={s.outer}}),'unsupported',cycle)
end

-- Wrong actor-root aliases and affected ancestry must not receive cached proof
-- from an earlier successful read of related nodes.
for _,kind in ipairs({'root-alias','foreign-parent','owner-mismatch','missing-actor-method','missing-items','bad-fluid-owner','missing-witness'})do
    local s=affected();s.outer.equipped=true
    if kind=='root-alias'then s.outer.inventory.parent=s.actor
    elseif kind=='foreign-parent'then s.root.parent={class='IsoPlayer',getInventory=function()return{}end}
    elseif kind=='owner-mismatch'then s.outer.inventory.owner=s.inner
    elseif kind=='missing-actor-method'then s.actor.isEquipped=nil
    elseif kind=='missing-items'then s.inner.inventory.getItems=nil
    elseif kind=='bad-fluid-owner'then s.inner.fluid={class='FluidContainer',getOwner=function()return{}end,getAmount=function()return.4 end}
    else s.root.items={s.outer};s.witness.container=nil;s.outer.inventory.items={s.inner};s.other.container=nil end
    noPublish(Snapshot.capture(s.actor,{containers={s.root,s.outer.inventory},items={s.outer}}),'unsupported',kind)
end
for _,value in ipairs({-.1,math.huge,0/0})do
    local s=affected();s.inner.fluid={class='FluidContainer',amount=value,getOwner=function()return s.inner end,getAmount=function(self)return self.amount end}
    noPublish(Snapshot.capture(s.actor,{containers={s.root},items={s.inner}}),'unsupported','invalid fluid amount')
end

-- Unsupported metadata must not invoke arbitrary acceptance callbacks, factories
-- or any affected aggregate getter. Unknown is not silently converted to zero.
for _,kind in ipairs({'accept-callback','category','unknown-script','script-create','bad-hunger','bad-weight'})do
    local s=affected();local callbacks=0
    if kind=='accept-callback'then s.outer.inventory.callback=function()callbacks=callbacks+1;error('must not invoke acceptance')end
    elseif kind=='category'then s.outer.inventory.category='Food'
    elseif kind=='unknown-script'then s.foodItem.extraTypes={'Base.Unknown'}
    elseif kind=='script-create'then s.extra.callback=function()callbacks=callbacks+1;error('must not create')end
    elseif kind=='bad-hunger'then s.foodItem.hunger=.01
    else s.foodItem.raw=0/0 end
    noPublish(Snapshot.capture(s.actor,{containers={s.root,s.outer.inventory},items={s.foodItem}}),'unsupported',kind)
    assert(callbacks==0,'snapshot invoked a custom callback')
end

-- Valid bounds exhaust as limited; malformed request/limit shapes are rejected.
do
    local s=affected()
    for _,limits in ipairs({{nodes=0},{nodes=1},{edges=0},{edges=1},{depth=0},{depth=1}})do
        noPublish(Snapshot.capture(s.actor,{containers={s.root},items={s.foodItem}},limits),'limited','exhausted bound')
    end
    for _,request in ipairs({false,17,'items',setmetatable({},{__index={}}),{unknown=true},
        {containers=false},{items='bad'},{items={[2]=s.foodItem}}, {containers={[1]=s.root,[3]=s.inner.inventory}},
        {containers={s.foodItem}},{items={s.root}},{items={false}}, {containers=setmetatable({s.root},{})}})do
        noPublish(Snapshot.capture(s.actor,request),'unsupported','malformed request')
    end
    noPublish(Snapshot.capture(s.actor,nil),'unsupported','missing request')
    for _,limits in ipairs({false,'limits',{},setmetatable({nodes=10},{}),{nodes=-1},{nodes=1.5},
        {edges=math.huge},{depth=65},{depth=0/0},{depth=true},{unknown=1}})do
        if type(limits)=='table'and count(limits)==0 and getmetatable(limits)==nil then
            parity(s,{s.root},{s.foodItem},'explicit empty limits',limits)
        else noPublish(Snapshot.capture(s.actor,{containers={s.root}},limits),'unsupported','invalid limits')end
    end
    s.root.getItems=function()error('empty request must not enumerate inventory')end
    local result=Snapshot.capture(s.actor,{}, {nodes=0,edges=0,depth=0})
    assert(result.status=='complete'and count(result.containers)==0 and count(result.items)==0,'empty requests must complete with empty maps')
    vectors=vectors+1
end

-- A cached child subtree carries its height when reused below an ancestor.
-- Explicit request order must not evade the combined root-to-leaf depth bound.
do
    local s=affected()
    -- root -> outer bag -> outer inventory -> inner bag -> inner inventory -> Food
    local exactDepth=5
    for _,containers in ipairs({{s.root,s.inner.inventory},{s.inner.inventory,s.root}})do
        noPublish(Snapshot.capture(s.actor,{containers=containers},{depth=exactDepth-1}),'limited','cached subtree combined depth')
        parity(s,containers,{},'cached subtree exact depth',{depth=exactDepth})
    end
end

-- Getter failure/reentrancy must clear the synchronous capture capability; a
-- later clean decision still works, and neither failure may publish cached data.
do
    local s=setup();local item=s.add(s.item(1),s.root);s.root.nativeLoad=.25
    local original=s.root.getItems;s.root.getItems=function()error('deliberate malformed collection getter')end
    noPublish(Snapshot.capture(s.actor,{containers={s.root}}),'unsupported','throwing getter')
    s.root.getItems=original;parity(s,{s.root},{item},'fresh after getter exception')
    local aggregate=s.root.getCapacityWeight;local nested
    s.root.getCapacityWeight=function(self)
        nested=Snapshot.capture(s.actor,{items={item}})
        return aggregate(self)
    end
    noPublish(Snapshot.capture(s.actor,{containers={s.root}}),'unsupported','reentrant aggregate')
    assert(nested and nested.status=='unsupported'and nested.items==nil and nested.containers==nil,'reentrant call published weights')
    s.root.getCapacityWeight=aggregate;parity(s,{s.root},{item},'fresh after reentrant failure')
end

-- Actor-root rebinding is a fresh-decision fact, and must not reuse an earlier
-- native aggregate from the previous actor inventory.
do
    local s=setup();local old=s.root;s.add(s.item(1),old);old.nativeLoad=.375
    local first=parity(s,{old},{},'old actor root');local replacement=s.container();replacement.parent=s.actor;replacement.nativeLoad=.75
    s.root=replacement
    noPublish(Snapshot.capture(s.actor,{containers={old}}),'unsupported','stale actor root alias')
    local current=parity(s,{replacement},{},'new actor root')
    assert(first.containers[old].upper==.375 and current.containers[replacement].upper==.75,'actor rebind reused or changed an old snapshot')
end
for _,value in ipairs({-.1,math.huge,0/0})do
    local s=setup();s.add(s.item(1),s.root);s.root.nativeLoad=value
    assert(s.weights.capacity(s.root,s.actor)==nil,'invalid native aggregate must stay unknown')
    noPublish(Snapshot.capture(s.actor,{containers={s.root}}),'unsupported','invalid native aggregate')
end

-- Count observable reads, not just a candidate's self-reported work. A single
-- union graph scan must cover overlapping outputs without re-enumerating roots.
do
    local s=affected();local containers={s.root,s.outer.inventory,s.inner.inventory}
    local enumerations,reads,weightReads={},{},{}
    local function instrument(container)
        local original=container.getItems
        container.getItems=function(self)
            enumerations[self]=(enumerations[self]or 0)+1
            local values=original(self)
            return{size=function()return values:size()end,get=function(_,index)
                local item=values:get(index);reads[item]=(reads[item]or 0)+1;return item
            end}
        end
    end
    for _,container in ipairs(containers)do instrument(container)end
    for _,item in ipairs({s.witness,s.outer,s.inner,s.foodItem,s.other})do
        local callback=item.getUnequippedWeight
        item.getUnequippedWeight=function(self)weightReads[self]=(weightReads[self]or 0)+1;return callback(self)end
    end
    local result=Snapshot.capture(s.actor,{containers=containers,items={s.outer,s.inner,s.foodItem,s.witness,s.other}})
    assert(result.status=='complete','instrumented valid union failed')
    for _,container in ipairs(containers)do assert(enumerations[container]==1,'scope rescanned an overlapping container')end
    for _,item in ipairs({s.witness,s.outer,s.inner,s.foodItem,s.other})do assert(reads[item]==1,'scope reread an ownership edge')end
    assert(weightReads[s.witness]and weightReads[s.other],'input getter evidence was not observed')
    assert(result.counters.nodes>=8 and result.counters.edges>=5,'work counters omit the inspected graph')
    vectors=vectors+1
end
TestQueueWeightSnapshotPassed=true
print('Queue weight snapshot: '..vectors..' exact bounds, native aggregate, mode/order/freshness, unsupported graph/callback and bounded-work vectors passed.')
