if not NativeActionRoot then print('Queue edit policy SKIP (pass --game).'); return end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
f.native('shared/RadioCom/ISRadioAction.lua')
getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
getGameFilesInput=function(path)
    local file=assert(io.open(NativeActionRoot..'/'..path:gsub('^media/lua/','')))
    return {readLine=function()local line=file:read('*l');return line and line:gsub('\r$','')end,close=function()file:close()end}
end
local previousRequire=require
local modules={}
require=function(name)
    if name=='PZSurvivorToolkit/ActionQueueEditModel' or name=='PZSurvivorToolkit/ActionQueueEditAdapters' then
        if not modules[name] then modules[name]=f.project(name:match('/([^/]+)$')) end
        return modules[name]
    end
    return previousRequire(name)
end
isClient=function()return false end
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
local policy=f.project('ActionQueuePolicy')
local definitions=PZSurvivorToolkit.ActionQueueDefinitions
local StateAction=ISBaseTimedAction:derive('FixtureStateAction')
local effects=0
function StateAction:complete()
    effects=effects+1
    if self.value~=nil then self.target.on=self.value end
    return true
end
local inspectionHook
local function stateContract(action)
    if inspectionHook then inspectionHook(action) end
    local result={items={},itemTypes={},targets=action.declaredOnly and {} or {[action.target]=true},cancelWaiting=true,
        edit={version=action.version or 1,complete=true,capacity=action.externalCapacity and 'external' or 'unchanged',resources={{
            domain='fixture',key=action.target,facts={on=action.target.on},
            requires=action.needsOn and {{field='on',equal=true}} or {},
            effects=action.value~=nil and {{field='on',set=action.value}} or {},
        }}}}
    if action.unknown then result.edit=nil end
    return result
end
definitions.registerBehavior('fixture.state', {types={'FixtureStateAction'},
    matches=function(action)return getmetatable(action)==StateAction and action.complete==StateAction.complete end,
    inspect=stateContract})
local head=f.action(ISReadABook,{item=f.item('Base.BookCarpentry1')})
local target={on=false}
local function command(value,needsOn)
    return f.action(StateAction,{target=target,value=value,needsOn=needsOn})
end
local on,off,use=command(true),command(false),command(nil,true)
local queue=f.queue(head,on,off)
local decision=policy.evaluateMove(queue,off,on)
assert(decision.allowed and decision.to==2,'same-target setters may change their final result')
assert(effects==0 and target.on==false and queue.queue[2]==on,'inspection cannot execute or reorder')
queue=f.queue(head,off,on,use)
decision=policy.evaluateMove(queue,off,on,true)
assert(not decision.allowed and decision.reason=='edit_required_state' and decision.blocker==use and decision.resource==target,
    'projection must include unchanged downstream state consumers')
use.declaredOnly=true
assert(policy.evaluateMove(queue,off,on,true).reason=='edit_required_state',
    'declarative resource identity must discover suffix dependencies without duplicate legacy footprints')
use.declaredOnly=nil
assert(queue.queue[2]==off and queue.queue[3]==on and effects==0 and target.on==false)
queue=f.queue(head,use,on)
assert(policy.evaluateMove(queue,on,use).allowed,'the proposed order may repair an already-invalid queue')
queue=f.queue(head,on,use)
assert(policy.evaluateCancel(queue,on,true).reason=='edit_required_state','cannot remove a required producer')
queue=f.queue(head,off,on,use)
assert(policy.evaluateCancel(queue,off,true).allowed,'a redundant setter can be removed before the same-target consumer')
queue=f.queue(head,use,on)
assert(policy.evaluateCancel(queue,use,true).allowed,'removal does not execute or require the removed action')
-- Unknown semantics retain the conservative shared-target restriction.
off.version=2
queue=f.queue(head,on,off)
assert(not policy.evaluateMove(queue,off,on).allowed)
on.declaredOnly,off.declaredOnly,use.declaredOnly=true,true,true
queue=f.queue(head,off,on,use)
assert(policy.evaluateMove(queue,off,on,true).reason=='edit_unknown',
    'unsupported declarations cannot escape through a legacy footprint without the declared resources')
on.declaredOnly,off.declaredOnly,use.declaredOnly=nil,nil,nil
off.version=nil
local missing=command(true);missing.unknown=true
queue=f.queue(head,on,missing,off)
assert(not policy.evaluateMove(queue,off,on).allowed,'unknown connected semantics cannot be silently skipped')
queue=f.queue(on,off,use)
assert(not policy.evaluateMove(queue,use,off).allowed,'an active prefix cannot be projected as unstarted work')
-- A stale decision cannot survive a lifecycle/member/ownership change.
queue=f.queue(head,on,off)
decision=policy.evaluateMove(queue,off,on)
assert(policy.editUnchanged(queue,decision.snapshot))
queue.toolkitOperationGeneration=1
assert(not policy.editUnchanged(queue,decision.snapshot))
queue.toolkitOperationGeneration=nil
on.toolkitQueueOperation.toolkitStarted=true
assert(not policy.editUnchanged(queue,decision.snapshot))
on.toolkitQueueOperation.toolkitStarted=nil
assert(policy.editUnchanged(queue,decision.snapshot))
local originalToken=on.toolkitQueueOperation
on.toolkitQueueOperation={}
assert(not policy.editUnchanged(queue,decision.snapshot))
on.toolkitQueueOperation=originalToken
inspectionHook=function(action)
    if action==off then queue.toolkitOperationGeneration=2 end
end
assert(policy.evaluateMove(queue,off,on).reason=='unavailable','reentrant inspection invalidates the whole decision')
inspectionHook=nil;queue.toolkitOperationGeneration=nil
-- Queue commands re-evaluate before applying, rather than trusting an earlier UI decision.
f.project('ActionQueueLabels')
local Queue=f.project('ActionQueue')
queue=f.queue(head,on,off)
assert(Queue.move(queue,off,on))
assert(queue.queue[2]==off and queue.queue[3]==on and effects==0)
queue.queue[2]:complete();queue.queue[3]:complete()
assert(target.on==true and effects==2,'only the native executor applies the newly chosen outcome')
target.on=false;effects=0
queue=f.queue(head,on,use)
local oldToken=on.toolkitQueueOperation
assert(not Queue.cancelOperation(queue,on))
assert(#queue.queue==3 and queue.queue[2]==on and not oldToken.toolkitCancelled and effects==0)
queue=f.queue(head,off,on,use)
assert(Queue.cancelOperation(queue,off))
assert(#queue.queue==3 and queue.queue[2]==on and queue.queue[3]==use and effects==0 and not target.on)
off=command(false)
-- Linked steps remain one atomic edit unit.
local a,b=command(false),command(true)
b.toolkitQueueOperation=a.toolkitQueueOperation
local c=command(false)
queue=f.queue(head,a,b,c)
assert(Queue.move(queue,a,c,true))
assert(queue.queue[2]==c and queue.queue[3]==a and queue.queue[4]==b)
-- Last-moment mutation after evaluation (diagnostics/hooks) must be rejected before table.remove/invalidate.
local record=policy.record
queue=f.queue(head,on,off)
policy.record=function()queue.toolkitOperationGeneration=9 end
assert(not Queue.move(queue,off,on) and queue.queue[2]==on and queue.queue[3]==off)
queue=f.queue(head,command(false),on,use)
local removable=queue.queue[2]
assert(not Queue.cancelOperation(queue,removable) and queue.queue[2]==removable and not removable.toolkitQueueOperation.toolkitCancelled)
policy.record=record
target.on=true
queue=f.queue(head,on,use)
policy.record=function()target.on=false end
assert(not Queue.move(queue,use,on) and queue.queue[2]==on,
    'resource conditions are read again after diagnostic/preparation hooks')
policy.record=record
queue=f.queue(head,command(false),on,use)
removable=queue.queue[2]
policy.record=function()removable.forceCancel=function()error('changed cancellation callback must not execute')end end
assert(not Queue.cancelOperation(queue,removable) and queue.queue[2]==removable,
    'cancellation handlers are validated again before removal')
policy.record=record
queue=f.queue(head,on,use)
decision=policy.evaluateMove(queue,on,use,true)
ISTimedActionQueue.queues[f.player]={}
assert(not policy.editUnchanged(queue,decision.snapshot),'a replaced owner queue revokes its old edit snapshot')
-- Location/effect approval must never bypass the separate conservative weight gate,
-- including a single later transfer which is outside the edited resource component.
do
    local root=f.player.inventory
    f.player.class='IsoPlayer'
    root.class='ItemContainer'
    root.getType=function()return 'inventory'end
    root.getContainingItem=function()end
    root.getParent=function()end
    root.getAcceptItemFunction=function()end
    root.getOnlyAcceptCategory=function()end
    root.getCapacityWeight=function()return root.load or 0 end
    root.getItems=function()return {size=function()return 0 end,get=function()end}end
    root.getEffectiveCapacity=function()return 50 end
    local bag=f.item('Base.Bag_DuffelBag');bag.class='InventoryContainer'
    local container={class='ItemContainer',getType=function()return 'bag'end,
        getContainingItem=function()return bag end,getParent=function()end,getAcceptItemFunction=function()end,
        getCapacityWeight=function()return 0 end,getEffectiveCapacity=function()return 50 end}
    container.getItems=function()return {size=function()return 0 end,get=function()end}end
    local item=f.item('Base.Nails')
    item.getType=function()return 'Nails'end
    item.getUnequippedWeight=function()return 2 end
    local transfer=f.action(ISInventoryTransferAction,{item=item,srcContainer=root,destContainer=container})
    local first,second=command(false),command(true)
    first.externalCapacity,second.externalCapacity=true,true
    queue=f.queue(head,first,second,transfer)
    assert(policy.evaluateMove(queue,second,first).reason=='container_capacity'
        and policy.evaluateCancel(queue,first,true).reason=='container_capacity',
        'an external contract does not prove the unknown weight effects of its prefix, even at empty loads')
    assert(not Queue.move(queue,second,first) and queue.queue[2]==first,
        'an external capacity requirement cannot be bypassed by a successful state projection')
end
print('Queue edit policy: changed outcomes, downstream prerequisites, removal, fallback, native execution and stale edits passed.')
