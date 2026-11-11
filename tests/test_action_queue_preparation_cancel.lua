-- Cancellation-only native tail contract. No completion/setter or transport is
-- simulated as a success: the actual Queue path must only erase pending rows.
if not NativeActionRoot then
    if TestCoverage then TestCoverage('source-contract','skipped','Pending preparation cancellation requires native Lua sources.') end
    return
end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r','') end
    local file=assert(io.open(path));local text=file:read('*a');file:close();return text:gsub('\r','')
end
local function setup(changedSource)
    NativeKahluaTableLookup=true
    local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
    f.native('shared/TimedActions/ISEquipWeaponAction.lua')
    f.native('shared/TimedActions/ISEquipHeavyItem.lua')
    f.native('shared/TimedActions/ISUnequipAction.lua')
    local filename=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
    getFilenameOfClosure=filename
    getGameFilesInput=function(path)
        local text=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''))
        if changedSource then text=text..'-- unqualified source\n' end
        local position=1
        return {close=function()end,readLine=function()
            if position>#text then return end
            local boundary=text:find('\n',position,true)or #text+1
            local line=text:sub(position,boundary-1);position=boundary+1;return line
        end}
    end
    isClient,isServer=function()return false end,function()return false end
    getPlayerHotbar=function()return nil end
    local enabled=true
    PZSurvivorToolkit.Settings.actionQueue=function()return enabled end
    f.player.class='IsoPlayer'
    local effects=0
    local function forbidden()effects=effects+1;error('pending cancellation executed an effect')end
    f.player.setPrimaryHandItem,f.player.setSecondaryHandItem=forbidden,forbidden
    f.player.getPrimaryHandItem,f.player.getSecondaryHandItem=forbidden,forbidden
    f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
    local policy=f.project('ActionQueuePolicy')
    f.project('ActionQueueLabels');local queueAPI=f.project('ActionQueue')
    local function equip(primary,twoHands)
        local item=f.item('Base.Hammer')
        item.getName=function()return 'Hammer' end
        item.isRequiresEquippedBothHands=function()return false end
        item.setJobDelta=forbidden
        local action=ISEquipWeaponAction:new(f.player,item,50,primary,twoHands,false)
        action.toolkitQueueOperation={}
        return action,item
    end
    local function head()return f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})end
    return f,policy,queueAPI,equip,head,function(value)enabled=value end,function()return effects end
end
local f,policy,api,equip,head,enabled,effects=setup(false)
for _,mode in ipairs({{true,false},{false,false},{true,true}})do
    for _,client in ipairs({false,true})do
        isClient=function()return client end
        local current=head();local action,item=equip(mode[1],mode[2]);local token=action.toolkitQueueOperation
        local queue=f.queue(current,action)
        local contract=assert(policy.inspect(action))
        assert(contract.cancelWaiting==true and contract.cancelTailOnly==true and contract.edit==nil,
            'pending erasure acquired projection or lost its tail boundary')
        assert(policy.evaluateCancel(queue,action).allowed,'native trailing equipment remains blocked')
        assert(api.cancel(queue,action),'real row cancellation did not route to whole operation')
        assert(#queue.queue==1 and queue.queue[1]==current and queue.current==current and token.toolkitCancelled
            and not current.toolkitQueueOperation.toolkitCancelled and action.item==item and effects()==0,
            'tail erasure changed its prefix, item, hands or native effects')
    end
end
isClient=function()return false end
-- The group is atomic, including multiple pending hand changes of the same item.
do
    local current=head();local first,item=equip(true,false);local last=equip(false,false)
    last.item=item;last.toolkitQueueOperation=first.toolkitQueueOperation
    local queue=f.queue(current,first,last)
    assert(api.cancel(queue,last) and #queue.queue==1 and queue.queue[1]==current,
        'row cancellation detached one step from its preparation group')
end
local function denied(mutate)
    local current=head();local action=equip(true,false);local token=action.toolkitQueueOperation
    local queue=f.queue(current,action)
    local restore=mutate(queue,action,current)
    assert(not api.cancel(queue,action) and not api.cancelOperation(queue,action)
        and #queue.queue>=2 and not token.toolkitCancelled and effects()==0,
        'unsupported preparation cancellation changed queue or game state')
    if restore then restore()end
end
denied(function(queue)queue.queue[3]=head()end) -- Even an apparently independent suffix needs complete effects.
denied(function(_,action)action.started=true end)
denied(function(_,action)action.action={}end)
denied(function(_,action)action._isAddingActions=true end)
denied(function(_,action)action.toolkitNativeTransaction={}end)
denied(function(_,action)action.toolkitNativeKind='Equip'end)
denied(function(_,action)action.toolkitQueueOperation.toolkitStarted=true end)
denied(function(_,action)action.toolkitQueueLinked=true end)
denied(function(_,action)action.character={}end)
for _,name in ipairs({'onStartFunc','onCompleteFunc','onCancelFunc','onFailFunc','additionalTest','retriggerLastAction','forceCancel','complete'})do
    denied(function(_,action)action[name]=function()error('foreign callback executed')end end)
end
denied(function(_,action)
    local owner=PZSurvivorToolkit.ActionQueueOperations
    local continuation=owner.attachContinuation(action.toolkitQueueOperation,f.player)
    return function()owner.finishContinuation(continuation)end
end)
denied(function()
    enabled(false);return function()enabled(true)end
end)
-- A malformed token cannot become cancellation authority through native lookup.
denied(function(_,action)action.toolkitQueueOperation=setmetatable({},{__index={}})end)
-- Pure cancellation cannot broaden active, Heavy, Unequip, cleanup or P4 ownership.
do
    local action=equip(true,false);local queue=f.queue(action)
    assert(not api.cancel(queue,action) and #queue.queue==1)
    for _,class in ipairs({ISEquipHeavyItem,ISUnequipAction})do
        local waiting=f.action(class,{item=f.item('Base.Hammer')})
        local other=f.queue(head(),waiting)
        assert(not api.cancel(other,waiting) and #other.queue==2,'unqualified equipment family gained cancellation')
    end
    local settlement=PZSurvivorToolkit.ActionQueueSettlement
    for _,method in ipairs({'requiredStep','isCleanup'})do
        local original=settlement[method]
        denied(function(_,target)
            settlement[method]=function(member)return member==target or original(member)end
            return function()settlement[method]=original end
        end)
    end
end
-- One opt-in member never lends authority to an unsafe sibling.
for _,mutation in ipairs({'started','foreign-actor','cleanup','callback','transaction'})do
    local first=equip(true,false);local last=equip(false,false)
    last.toolkitQueueOperation=first.toolkitQueueOperation
    local queue=f.queue(head(),first,last)
    local settlement=PZSurvivorToolkit.ActionQueueSettlement
    local original=settlement.isCleanup
    if mutation=='started'then last.started=true
    elseif mutation=='foreign-actor'then last.character={}
    elseif mutation=='cleanup'then settlement.isCleanup=function(member)return member==last or original(member)end
    elseif mutation=='callback'then last.onCancelFunc=function()error('sibling callback executed')end
    else last.toolkitNativeTransaction={}end
    assert(not api.cancel(queue,first)and #queue.queue==3 and not first.toolkitQueueOperation.toolkitCancelled,
        'one safe member authorized an unsafe sibling: '..mutation)
    settlement.isCleanup=original
end
for _,method in ipairs({'complete','forceCancel'})do
    local original=ISEquipWeaponAction[method]
    denied(function()
        ISEquipWeaponAction[method]=function()error('replacement class callback executed')end
        return function()ISEquipWeaponAction[method]=original end
    end)
end
do
    local target=equip(true,false);local queue=f.queue(head(),target)
    -- Model a separately registered producer owner, rather than invoking its
    -- callbacks. Real P4 owner/effect qualification remains a separate bank.
    PZSurvivorToolkit.ActionQueueDefinitions.registerBehavior('fixture.owned-preparation',{
        types={'ISEquipWeaponAction'},matches=function(action)return action==target end,
        inspect=function()return {items={},targets={},cancelOperation=false}end,
    })
    assert(not policy.inspect(target)and not api.cancel(queue,target)and #queue.queue==2,
        'ambiguous native/producer ownership must not fall through to the native opt-in')
end
-- A staged permission does not survive a suffix inserted before commit.
do
    local action=equip(true,false);local queue=f.queue(head(),action)
    local staged=policy.evaluateCancel(queue,action)
    assert(staged.allowed)
    queue.queue[3]=head()
    assert(not policy.editUnchanged(queue,staged.snapshot)and not api.cancel(queue,action)and #queue.queue==3)
end
-- Source mismatch is not a cancellation-only exception to native forceCancel proof.
f,policy,api,equip,head,enabled,effects=setup(true)
local action=equip(true,false);local queue=f.queue(head(),action)
assert(not api.cancel(queue,action)and #queue.queue==2 and not action.toolkitQueueOperation.toolkitCancelled)
print('Pending preparation tail erasure: native Queue, grouped removal, ownership, callbacks, cleanup and unchanged effects passed; no move/Host transport authority.')
if TestCoverage then TestCoverage('source-contract','passed')end
