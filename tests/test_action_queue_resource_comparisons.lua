if not NativeActionRoot then print('SKIP Policy resource comparisons: supply --game');return end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
local policy=f.project('ActionQueuePolicy')
local toolkit=PZSurvivorToolkit
local class=ISBaseTimedAction:derive('ResourceComparisonFixture')
toolkit.ActionQueueCraft=nil
local providerContexts={}
toolkit.ActionQueueDefinitions.registerBehavior('fixture.resource-comparisons',{
    types={'ResourceComparisonFixture'},
    matches=function(action)return action.Type=='ResourceComparisonFixture'end,
    inspect=function(action,context)
        providerContexts[action]=context
        return action.resourceContract
    end,
})
local function contract()
    return {knownInputs=true,cancelWaiting=true,interrupt='finish-step'}
end
local function scene()
    toolkit.ActionQueueGenerators,toolkit.ActionQueueWorld=nil,nil
    providerContexts={}
    local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
    local crossed=f.action(class,{item=f.item('Base.Crossed'),resourceContract=contract()})
    local moving=f.action(class,{item=f.item('Base.Moving'),resourceContract=contract()})
    -- A false spatial field is inert, but keeps the complete legacy comparison
    -- path in cases whose otherwise empty contracts permit broad-phase pruning.
    moving.toolkitWorldTarget=false
    return f.queue(head,crossed,moving),moving,crossed
end
local function result(queue,moving,crossed)
    return policy.evaluateMove(queue,moving,crossed)
end
local function denied(label,configure,reason,resource)
    local queue,moving,crossed=scene()
    local expected=configure(moving,crossed)
    local decision=result(queue,moving,crossed)
    assert(not decision.allowed and decision.reason==reason and decision.blocker==crossed
        and decision.resource==(resource or expected),label..': wrong resource denial')
end
local maps={'items','itemTypes','containerOwners','dynamicInputs','dynamicInputsByType','outputTypes','targets','positions'}
for _,mode in ipairs({'absent','false','empty'})do
    local queue,moving,crossed=scene()
    for _,action in ipairs({moving,crossed})do
        for _,name in ipairs(maps)do
            if mode=='false'then action.resourceContract[name]=false
            elseif mode=='empty'then action.resourceContract[name]={}end
        end
        action.resourceContract.hands,action.resourceContract.equipment=false,false
    end
    assert(result(queue,moving,crossed).allowed,mode..' resource maps must remain independent')
end

denied('shared direct item',function(moving,crossed)
    moving.item=crossed.item;return moving.item:getID()
end,'move_shared_item')
denied('shared declared item',function(moving,crossed)
    moving.resourceContract.items={[50101]=true};crossed.resourceContract.items={[50101]=true};return 50101
end,'move_shared_item')
denied('moving container owner',function(moving,crossed)
    moving.resourceContract.containerOwners={[crossed.item:getID()]=true};return crossed.item:getID()
end,'move_shared_item')
denied('crossed container owner',function(moving,crossed)
    crossed.resourceContract.containerOwners={[moving.item:getID()]=true};return moving.item:getID()
end,'move_shared_item')
for _,field in ipairs({'itemTypes','dynamicInputs','outputTypes'})do
    denied('dynamic short type against '..field,function(moving,crossed)
        moving.resourceContract.dynamicInputsByType={Nails=true}
        crossed.resourceContract[field]={['Base.Nails']=true};return 'Nails'
    end,'move_craft_inputs')
end
for _,field in ipairs({'itemTypes','dynamicInputs','outputTypes'})do
    denied('dynamic full type against '..field,function(moving,crossed)
        moving.resourceContract.dynamicInputs={['Base.Nails']=true}
        crossed.resourceContract[field]={['Base.Nails']=true};return 'Base.Nails'
    end,'move_craft_inputs')
end
for _,field in ipairs({'itemTypes','outputTypes'})do
    denied('produced full type against '..field,function(moving,crossed)
        moving.resourceContract.outputTypes={['Base.Nails']=true}
        crossed.resourceContract[field]={['Base.Nails']=true};return 'Base.Nails'
    end,'move_craft_inputs')
end
denied('unknown outputs against dynamic input',function(moving,crossed)
    moving.resourceContract.dynamicInputs={['Base.Nails']=true};crossed.resourceContract.unknownOutputs=true
end,'move_craft_inputs',true)
for _,field in ipairs({'targets','positions'})do
    denied('shared '..field,function(moving,crossed)
        local target={};moving.resourceContract[field]={[target]=true};crossed.resourceContract[field]={[target]=true};return target
    end,'move_dependent')
end
-- Resource properties are extension points too: the left map expression is
-- read once, while conditional right-map lookups retain their two live reads.
for _,field in ipairs({'positions','targets'})do
    local queue,moving,crossed=scene();local target=field=='positions'and f.player or {}
    local reads=0
    setmetatable(moving.resourceContract,{__index=function(_,key)
        if key==field then reads=reads+1;return reads==1 and {[target]=true}or false end
    end})
    crossed.resourceContract[field]={[target]=true}
    local decision=result(queue,moving,crossed)
    assert(decision.reason=='move_dependent'and decision.resource==target and reads==1,
        field..': the left resource expression must be captured once')
    queue,moving,crossed=scene();reads=0
    moving.resourceContract[field]={[target]=true}
    setmetatable(crossed.resourceContract,{__index=function(_,key)
        if key==field then reads=reads+1;return reads==1 and {}or {[target]=true}end
    end})
    decision=result(queue,moving,crossed)
    assert(decision.reason=='move_dependent'and decision.resource==target and reads==2,
        field..': right resource property reads must remain live and ordered')
end
do
    local queue,moving,crossed=scene();local reads=0
    moving.resourceContract.dynamicInputs={['Base.Nails']=true}
    setmetatable(crossed.resourceContract,{__index=function(_,key)
        if key=='itemTypes'then reads=reads+1;return reads==1 and {}or {['Base.Nails']=true}end
    end})
    local decision=result(queue,moving,crossed)
    assert(decision.reason=='move_craft_inputs'and decision.resource=='Base.Nails'and reads==2,
        'dynamic-input right-map properties must retain their repeated conditional reads')
end
denied('shared hands',function(moving,crossed)
    moving.resourceContract.hands,crossed.resourceContract.hands=f.player,f.player;return f.player
end,'move_dependent')
for _,reverse in ipairs({false,true})do
    denied('hands/equipment '..tostring(reverse),function(moving,crossed)
        local left,right=moving.resourceContract,crossed.resourceContract
        if reverse then left,right=right,left end
        left.hands,right.equipment=f.player,f.player;return f.player
    end,'move_dependent')
end

for _,field in ipairs({'isoObject','moveProps'})do
    denied('sparse late spatial '..field,function(moving,crossed)
        local target={class='IsoObject'}
        if field=='moveProps'then moving.moveProps={object=target};crossed.moveProps={object=target}
        else moving.isoObject,crossed.isoObject=target,target end
        return target
    end,'move_dependent',true)
end
do
    local queue,moving,crossed=scene()
    moving.generator,moving.charger,moving.object,moving.moveProps,moving.isoObject=false,false,false,false,false
    assert(result(queue,moving,crossed).allowed,'all-false source spatial expressions must stay independent')
end

-- The generator extension runs before shared-world contract reads. It may
-- replace the cached tuple; a previously captured contract must not hide that.
do
    local queue,moving,crossed=scene();local target={};local calls=0
    crossed.resourceContract.targets={[target]=true}
    toolkit.ActionQueueGenerators={sharesTarget=function(left,right,context)
        assert(left==moving and right==crossed and context==providerContexts[moving])
        calls=calls+1
        local changed=contract();changed.targets={[target]=true}
        context.contracts[moving]={changed,'fixture.changed-by-generator'}
    end}
    local decision=result(queue,moving,crossed)
    assert(decision.reason=='move_dependent'and decision.resource==target and calls==1,
        'generator callback must precede the compared contract snapshot')
end

-- A world extension may populate a source spatial field. Source expressions
-- are read eagerly after that callback, including a truthy moveProps read twice.
do
    local queue,moving,crossed=scene();local first={class='IsoObject'};local target={class='IsoObject'}
    moving.toolkitWorldTarget=nil
    local trace={};local spatial={generator=first,charger=false,toolkitWorldTarget=false}
    local props=setmetatable({}, {__index=function(_,key)
        assert(key=='object');trace[#trace+1]='moveProps.object'
    end})
    spatial.moveProps=props
    local names={generator=true,charger=true,object=true,moveProps=true,toolkitWorldTarget=true,isoObject=true}
    setmetatable(moving,{__index=function(_,key)
        if names[key]then trace[#trace+1]=key;return spatial[key]end
        return class[key]
    end})
    crossed.isoObject=target
    toolkit.ActionQueueWorld={sharesTarget=function(left,right)
        assert(left==moving and right==crossed);trace[#trace+1]='world';spatial.isoObject=target
    end}
    local previousInstance=instanceof
    instanceof=function(value,kind)
        if value==first and kind=='IsoObject'then trace[#trace+1]='instanceof' end
        return previousInstance(value,kind)
    end
    local ok,decision=pcall(result,queue,moving,crossed)
    instanceof=previousInstance
    assert(ok,decision)
    assert(decision.reason=='move_dependent'and decision.resource==true)
    assert(table.concat(trace,',')=='world,generator,charger,object,moveProps,moveProps,moveProps.object,toolkitWorldTarget,isoObject,instanceof',
        'world callback or eager source spatial read order changed: '..table.concat(trace,','))
end

-- instanceof may have observable effects. All source expressions belong to
-- the same eager snapshot taken before the first candidate is classified.
do
    local queue,moving,crossed=scene();local first={class='IsoObject'};local later={class='IsoObject'}
    moving.generator=first;crossed.isoObject=later
    local calls=0;local previousInstance=instanceof
    instanceof=function(value,kind)
        if value==first and kind=='IsoObject'then calls=calls+1;moving.isoObject=later end
        return previousInstance(value,kind)
    end
    local ok,decision=pcall(result,queue,moving,crossed)
    instanceof=previousInstance
    assert(ok,decision)
    assert(decision.allowed and calls==1 and moving.isoObject==later,
        'later spatial reads must not observe an instanceof mutation within the same comparison')
end
-- Presence-only ancestry has the same observable walk as the full-chain
-- planner: reject special containers before inventory/owner callbacks and stop
-- at the root without asking it for a containing item.
do
    local calls={}
    local function box(label,kind)
        return {class='ItemContainer',kind=kind,
            getType=function(self)calls[#calls+1]=label..'.type';return self.kind end,
            getContainingItem=function(self)calls[#calls+1]=label..'.owner';return self.owner end}
    end
    local root=box('root','inventory')
    local actor={class='IsoPlayer',getInventory=function()calls[#calls+1]='inventory';return root end}
    local function bag(label,parent)
        return {class='InventoryContainer',getContainer=function()calls[#calls+1]=label..'.container';return parent end}
    end
    local function check(container,expected,order)
        calls={}
        assert(policy.isCarriedContainer(container,actor)==expected)
        assert(table.concat(calls,',')==order,'carried ancestry callback order changed: '..table.concat(calls,','))
    end
    check(root,true,'root.type,inventory')
    local inner=box('inner','bag');inner.owner=bag('bag',root)
    check(inner,true,'inner.type,inventory,inner.owner,bag.container,root.type,inventory')
    local cycle=box('cycle','bag');cycle.owner=bag('loop',cycle)
    check(cycle,false,'cycle.type,inventory,cycle.owner,loop.container')
    check(box('floor','floor'),false,'floor.type')
    check(box('missing','bag'),false,'missing.type,inventory,missing.owner')
end

-- Native resource inspection can reenter through an item getter. Both walks
-- must keep their own iteration position through secondaryItem and battery.
do
    local trace={};local nested,entered
    local sibling=f.action(ISReadABook,{item=f.item('Base.Sibling'),secondaryItem=f.item('Base.SiblingSecondary'),battery=f.item('Base.SiblingBattery')})
    local outer=f.action(ISReadABook,{item=f.item('Base.Outer'),secondaryItem=f.item('Base.OuterSecondary'),battery=f.item('Base.OuterBattery')})
    for _,entry in ipairs({{outer.item,'outer.item'},{outer.secondaryItem,'outer.secondaryItem'},{outer.battery,'outer.battery'},
        {sibling.item,'sibling.item'},{sibling.secondaryItem,'sibling.secondaryItem'},{sibling.battery,'sibling.battery'}})do
        local item,label=entry[1],entry[2]
        item.getID=function(self)
            trace[#trace+1]=label
            if item==outer.item and not entered then
                entered=true
                local source;nested,source=policy.inspect(sibling)
                assert(source=='native.ISReadABook','reentrant sibling must use the native resource inspector')
            end
            return self.id
        end
    end
    local inspected,source=policy.inspect(outer)
    assert(source=='native.ISReadABook'and inspected and nested)
    assert(table.concat(trace,',')=='outer.item,sibling.item,sibling.secondaryItem,sibling.battery,outer.secondaryItem,outer.battery',
        'reentrant resource inspection changed a field walk: '..table.concat(trace,','))
    for _,entry in ipairs({{outer,inspected},{sibling,nested}})do
        for _,field in ipairs({'item','secondaryItem','battery'})do
            assert(entry[2].items[entry[1][field].id],'resource iteration lost '..field)
        end
    end
end
print('PASS Policy resource comparisons: absent/false/empty maps, exact conflicts, sparse spatial targets and callback/snapshot ordering')
