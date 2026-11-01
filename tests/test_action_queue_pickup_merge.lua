if not NativeActionRoot then print('Pickup merge policy SKIP (pass --native-action-root).');return end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
isClient=function()return true end
round=function(value)return value end
local operations=f.project('ActionQueueOperations')
local bulk=f.project('BulkActions')
local nativeStop=ISInventoryTransferAction.stop
local source,destination={},f.player:getInventory()
local function item(kind)
    local value=f.item(kind)
    value.getWeight=function()return .05 end
    value.getContainer=function()return source end
    return value
end
local function action(value,callback)
    local transfer=f.action(ISInventoryTransferAction,{item=value,srcContainer=source,destContainer=destination,
        queueList={{items={value},time=10,type=value:getFullType()}},maxTime=10,onCompleteFunc=callback})
    transfer.toolkitQueueOperation=nil
    return transfer
end
local function uiOrder(allowNativeMerge,callback,sameType)
    local q=f.queue()
    local first=action(item('Base.Nails'),callback)
    local second=action(item(sameType and 'Base.Nails'or 'Base.Screws'))
    local began=false
    -- Native addToQueue begins the first action synchronously. Java allocation
    -- is outside this source-only check; install the real stop guard at that
    -- boundary, before the UI producer gets to enqueue its next pickup.
    first.begin=function(self)
        assert(#q.queue==1 and q.current==self,'first action did not begin immediately')
        bulk.guardTransfer(self,allowNativeMerge)
        self:checkQueueList()
        began=true
    end
    operations.run(function()
        ISTimedActionQueue.add(first)
        assert(began and #q.queue==1 and #first.queueList==1,'producer did not pause at first begin')
        ISTimedActionQueue.add(second)
    end)
    assert(#q.queue==2 and first.toolkitQueueOperation==second.toolkitQueueOperation)
    assert(bulk.isGuardedTransfer(first,nativeStop),'optional mode lost exact native stop guard')
    local guarded=first.stop
    bulk.guardTransfer(first,allowNativeMerge)
    assert(first.stop==guarded,'repeated guard wrapped native stop twice')
    first:checkQueueList()
    return q,first,second
end
local q,first,second=uiOrder(true,nil,true)
assert(#q.queue==1 and q.queue[1]==first and #first.queueList==1 and #first.queueList[1].items==2,
    'optional pickup stop guard disabled native same-type item merge')
assert(first.onCompleteFunc==nil and first.toolkitQueueSafeOnComplete==nil and second.item==nil,
    'merge must remain the native child-wiping path without an empty completion callback')
q,first,second=uiOrder(true,nil,false)
assert(#q.queue==1 and #first.queueList==2 and first.queueList[2].type=='Base.Screws'and second.item==nil,
    'optional pickup stop guard disabled native multigroup merge')
q,first,second=uiOrder(nil,nil,true)
assert(#q.queue==2 and #first.queueList==1 and #first.queueList[1].items==1 and second.item~=nil,
    'default return guard must retain its singleton merge exclusion')
assert(first.onCompleteFunc~=nil and first.onCompleteFunc==first.toolkitQueueSafeOnComplete)
local sentinel,stop=first.onCompleteFunc,first.stop
bulk.guardTransfer(first,true)
assert(first.onCompleteFunc==sentinel and first.stop==stop,'optional mode must not remove an existing singleton guard')
local callback=function()error('owner callback must not execute while guarding or merging')end
q,first=uiOrder(true,callback,true)
assert(#q.queue==2 and first.onCompleteFunc==callback,'optional mode must preserve existing owner callback')
-- A later explicit singleton owner may strengthen a previously mergeable guard.
local upgraded=action(item('Base.Nails'));bulk.guardTransfer(upgraded,true)
local originalGuard=upgraded.stop;bulk.guardTransfer(upgraded)
assert(upgraded.stop==originalGuard and upgraded.onCompleteFunc==upgraded.toolkitQueueSafeOnComplete
    and upgraded.onCompleteFunc~=nil,'default owner must still install its sentinel on an existing optional guard')
-- Operations owns producer isolation independently of native merge eligibility.
q=f.queue();first=action(item('Base.Nails'));second=action(item('Base.Nails'))
first.begin=function(self)bulk.guardTransfer(self,true)end
operations.run(function()ISTimedActionQueue.add(first)end)
operations.run(function()ISTimedActionQueue.add(second)end)
first:checkQueueList()
assert(#q.queue==2 and first.toolkitQueueOperation~=second.toolkitQueueOperation,
    'allowing native merge must not cross distinct operation tokens')
print('Pickup native merge: synchronous first begin, same-type and multigroup siblings, default singleton returns, callback retention and producer isolation passed.')
