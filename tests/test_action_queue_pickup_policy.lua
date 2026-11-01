if not NativeActionRoot then print('Rejected pickup policy SKIP (pass --native-action-root).');return end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r','') end
    local file=assert(io.open(path));local source=file:read('*a');file:close();return source:gsub('\r','')
end
getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
getGameFilesInput=function(path)
    local source=read(NativeActionRoot..'/'..path:gsub('^media/lua/',''));local position=1
    return {close=function()end,readLine=function()
        if position>#source then return end
        local boundary=source:find('\n',position,true)or #source+1
        local line=source:sub(position,boundary-1);position=boundary+1;return line
    end}
end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
f.native('client/TimedActions/WalkToTimedAction.lua')
f.native('shared/TimedActions/ISEquipWeaponAction.lua')
isClient=function()return true end
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
local policy=f.project('ActionQueuePolicy')
local operations=PZSurvivorToolkit.ActionQueueOperations
local function container(parent,owner)
    return {class='ItemContainer',getType=function()return 'container'end,
        getParent=function()return parent end,getContainingItem=function()return owner end,
        getAcceptItemFunction=function()end}
end
local root=container(f.player);f.player.inventory=root
local bagOwner=f.item('Base.Bag_Schoolbag');bagOwner.class='InventoryContainer'
local bag=container(nil,bagOwner)
local function scene()
    local book=f.item('Base.BookCarpentry1');local other=f.item('Base.BookCooking1')
    local pickup=f.action(ISInventoryTransferAction,{item=book,srcContainer=bag,destContainer=root})
    local reader=f.action(ISReadABook,{item=book,toolkitQueueOperation=pickup.toolkitQueueOperation})
    local returning=f.action(ISInventoryTransferAction,{item=book,srcContainer=root,destContainer=bag,
        allowMissingItems=true,toolkitQueueOperation=pickup.toolkitQueueOperation})
    local tail=f.action(ISReadABook,{item=other})
    return f.queue(pickup,reader,returning,tail),pickup,reader,returning,tail
end
local q,pickup,reader,returning,tail=scene()
local plan,reason=policy.rejectedPickupPlan(q,pickup)
assert(plan,reason)
assert(#plan.members==2 and plan.members[1]==reader and plan.members[2]==returning)
assert(#plan.retained==1 and plan.retained[1]==tail and policy.editUnchanged(q,plan.snapshot))
assert(#q.queue==4 and q.queue[1]==pickup,'planning must not remove or execute native work')
tail.toolkitQueueOperation={};assert(not policy.editUnchanged(q,plan.snapshot),'token replacement must revoke plan')
q,pickup,reader,returning,tail=scene()
local walk=f.action(ISWalkToTimedAction);q.queue[5]=walk
plan,reason=policy.rejectedPickupPlan(q,pickup);assert(plan,reason)
assert(plan.retained[2]==walk,'pickup/return reachability does not make a later walk dependent')
-- Another book can share the source bag without depending on the lost book.
tail.item.getContainer=function()return bag end
assert(policy.rejectedPickupPlan(q,pickup),'same-bag different-item reader must remain independent')
-- Adjacent pickup preparations can belong to one native batch. Do not guard
-- the first as a singleton or disable merging for this unsupported producer.
q,pickup,reader,returning,tail=scene()
q.queue[2]=f.action(ISInventoryTransferAction,{item=f.item('Base.OtherInput'),srcContainer=bag,destContainer=root,
    toolkitQueueOperation=pickup.toolkitQueueOperation})
assert(not policy.rejectedPickupPlan(q,pickup),'multi-input preparation must retain native merging')
-- Owner token is grouping only: no independent child may be silently dropped.
q,pickup,reader,returning,tail=scene();tail.toolkitQueueOperation=pickup.toolkitQueueOperation
assert(not policy.rejectedPickupPlan(q,pickup),'same-token independent child is unsupported, not disposable')
q,pickup,reader,returning,tail=scene()
tail.item=pickup.item
local unsupported,why=policy.rejectedPickupPlan(q,pickup)
assert(not unsupported and why=='dependent_tail','cross-owner dependent work must keep native fallback')
for _,mutation in ipairs({'owner-callback','owner-method','tail-callback','tail-active','owner-active',
    'unknown-tail','owner-unknown','continuation','noncontiguous','cancelled','required','cleanup','started-tail'})do
    q,pickup,reader,returning,tail=scene()
    if mutation=='owner-callback'then reader.onCompleteFunc=function()error('callback executed')end
    elseif mutation=='owner-method'then reader.forceCancel=function()error('cancel executed')end
    elseif mutation=='tail-callback'then tail.onStartFunc=function()error('callback executed')end
    elseif mutation=='tail-active'then tail.action={}
    elseif mutation=='owner-active'then reader.action={}
    elseif mutation=='unknown-tail'then tail.Type='UnknownAction'
    elseif mutation=='owner-unknown'then reader.Type='UnknownAction'
    elseif mutation=='continuation'then operations.attachContinuation(pickup.toolkitQueueOperation,f.player)
    elseif mutation=='noncontiguous'then q.queue[5]=f.action(ISReadABook,{item=f.item('Base.Book'),toolkitQueueOperation=pickup.toolkitQueueOperation})
    elseif mutation=='cancelled'then pickup.toolkitQueueOperation.toolkitCancelled=true
    elseif mutation=='required'then PZSurvivorToolkit.ActionQueueSettlement={requiredStep=function(action)return action==returning end}
    elseif mutation=='cleanup'then PZSurvivorToolkit.ActionQueueSettlement={requiredStep=function()return false end,isCleanup=function(action)return action==tail end}
    elseif mutation=='started-tail'then tail.toolkitQueueOperation.toolkitStarted=true end
    assert(not policy.rejectedPickupPlan(q,pickup),'unsupported shape acquired plan: '..mutation)
    PZSurvivorToolkit.ActionQueueSettlement=nil
end
-- The caller must separately prove the exact native rejection and the private
-- no-prior-effects owner record; public token flags cannot grant either fact.
q,pickup,reader,returning,tail=scene();pickup.toolkitQueueOperation.toolkitStarted=true
assert(policy.rejectedPickupPlan(q,pickup),'current pickup begin marks owner started before native rejection')
for _,size in ipairs({32,33,200})do
    q,pickup=scene()
    for i=5,size do q.queue[i]=f.action(ISReadABook,{item=f.item('Base.OtherBook')})end
    if size>32 then q.indexOf=function()error('oversize plan scanned membership')end end
    local result,why=policy.rejectedPickupPlan(q,pickup)
    assert((result~=nil)==(size==32),why)
    if size>32 then assert(why=='unsupported_queue_size')end
end
print('Rejected pickup policy: bounded native owner partition, exact item dependencies, independent books/walk, closed callbacks/lifecycle/continuations and stale snapshots passed.')
