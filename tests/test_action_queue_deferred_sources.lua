if not NativeActionRoot then
    if TestCoverage then TestCoverage('source-contract','skipped','Native action sources unavailable; pass --game or --native-action-root.')end
    return
end
local root=ProjectRoot or '.'
local function read(path)
    if NativeReadText then return NativeReadText(path)end
    local file=assert(io.open(path));local value=file:read('*a');file:close();return value
end
TestReturnSourceFixtureOnly=true
local setup=assert(loadfile(root..'/tests/test_action_queue_item_edit_adapters.lua'))()
TestReturnSourceFixtureOnly=nil
assert(type(setup)=='function')
local queuePath=root..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueue.lua'
local queueSource=read(queuePath)
local beginFirst=assert(queueSource:find('local function updateOperationState(',1,true))
local beginLast=assert(queueSource:find('function Queue.cancel(',beginFirst,true))
local stopFirst=assert(queueSource:find('local stop = ISBaseTimedAction.stop',1,true))
local stopLast=assert(queueSource:find('-- Native reset/clear delegate',stopFirst,true))
local beginSource,stopSource=queueSource:sub(beginFirst,beginLast-1),queueSource:sub(stopFirst,stopLast-1)
local function fixture(bulkGuard,tidyObserver)
    local s=setup()
    getFirstLineOfClosure=NativeFirstLineOfClosure or function(callback)return debug.getinfo(callback,'S').linedefined end
    local lifecycle=s.f.project('ActionQueueLifecycle')
    local queueModule={};PZSurvivorToolkit.ActionQueue=queueModule
    -- These are the shipped hook bodies and actual adoption calls, not substitute
    -- delegates. They are inspected, never executed; lifecycle effects stay out
    -- of this source-only test, just as they stay out of the production lease.
    assert(loadstring([[local Toolkit,Policy,Operations,Queue=...
        local Settlement,Batch,Execution,PickupFailure=Toolkit.ActionQueueSettlement,Toolkit.ActionQueueBatch,
            Toolkit.ActionQueueExecution,Toolkit.ActionQueuePickupFailure
        local craft,live=Policy.isCraftAction,Policy.live
        ]]..beginSource..stopSource,'@'..queuePath))(PZSurvivorToolkit,s.policy,PZSurvivorToolkit.ActionQueueOperations,queueModule)
    local bulk=s.f.project('BulkActions')
    assert(s.adapters.registerSourceFactory(bulk,'transferBinding',bulk.transferBinding),'actual Bulk source factory registration failed')
    local intent,settlement
    if tidyObserver then
        intent=s.f.project('ActionQueueTidyIntent')
        -- Intent requires this module first. Reuse its real module instance;
        -- factory registration deliberately rejects a second same-slot loader.
        settlement=assert(PZSurvivorToolkit.ActionQueueSettlement)
        assert(settlement.observePlannedReturns(),'actual planned-return listener installation failed')
    end
    s.water.container=s.root
    local nativeCheckpoint={isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}
    local current=s.f.action(ISReadABook,{item=s.water,action=nativeCheckpoint})
    assert(current.started==nil,'native reader has no Lua started flag')
    current.toolkitQueueOperation.toolkitStarted=true
    local action=s.transfer(s.water,s.root,s.bagInventory)
    action.allowMissingItems=true;action.toolkitQueueOperation=current.toolkitQueueOperation
    if bulkGuard then bulk.guardTransfer(action)end
    local queue=s.f.queue(current,action)
    local facts={schema=2,item=s.water,source=s.root,destination=s.bagInventory,location=s.root,
        id=s.water:getID(),fullType=s.water:getFullType(),destinationOwner=s.bag,destinationOwnerFullType=s.bag:getFullType(),
        sourceParentTypes=false,destinationParentTypes=false,primaryItemContainerKnown=true}
    return s,current,action,queue,facts,bulk,intent,settlement,lifecycle
end
for _,bulkGuard in ipairs({false,true})do
    local s,current,action,queue,facts,bulk,intent=fixture(bulkGuard,false)
    local lease=assert(s.adapters.deferredTransferBinding(action,current),
        'combined native + Queue base + Bulk/Tidy source binding must prepare')
    local before={current=queue.current,first=queue.queue[1],second=queue.queue[2],item=action.item,
        source=action.srcContainer,destination=action.destContainer,started=action.started,transaction=action.transactionId}
    s.forbidProofReads()
    local function forbidden()error('callback/getter/constructor after final facts')end
    s.water.getID,s.water.getFullType,s.water.getContainer=forbidden,forbidden,forbidden
    s.f.player.getInventory,s.f.player.getPlayerNum,s.f.player.isDead=forbidden,forbidden,forbidden
    s.root.getItemById,s.bagInventory.getItemById,getTimestampMs=forbidden,forbidden,forbidden
    assert(lease(facts)and not lease(facts),'central source lease must be pure and single-use')
    assert(queue.current==before.current and queue.queue[1]==before.first and queue.queue[2]==before.second
        and action.item==before.item and action.srcContainer==before.source and action.destContainer==before.destination
        and action.started==before.started and action.transactionId==before.transaction and not queue.toolkitCancel,
        'source composition changed native queue/action state')
end
for _,mutation in ipairs({'class','base','factory','owner','descriptor','safe-completion','member','queue'})do
    local s,current,action,queue,facts,bulk=fixture(true,false)
    local lease=assert(s.adapters.deferredTransferBinding(action,current))
    if mutation=='class'then ISInventoryTransferAction.transferItem=function()error('changed class helper invoked')end
    elseif mutation=='base'then ISBaseTimedAction.stop=function()error('changed base invoked')end
    elseif mutation=='factory'then bulk.transferBinding=function()error('changed factory invoked')end
    elseif mutation=='owner'then PZSurvivorToolkit.BulkActions={transferBinding=bulk.transferBinding}
    elseif mutation=='descriptor'then action.toolkitTransferGuard.original=function()error('changed delegate invoked')end
    elseif mutation=='safe-completion'then action.toolkitQueueSafeOnComplete=function()error('changed metadata alias invoked')end
    elseif mutation=='member'then action.queueList[1].items[1]=s.item()
    else queue.toolkitOperationGeneration=1 end
    assert(not lease(facts),'combined source lease accepted changed '..mutation)
end
-- Genuine Host producers may refresh action.item while queueList retains a
-- detached same-ID copy. This layer must decline without canonicalizing either.
do
    local s,current,action,queue=fixture(true,false)
    local detached={}
    for key,value in pairs(s.water)do detached[key]=value end
    action.queueList[1].items[1]=detached
    assert(detached~=s.water and detached:getID()==s.water:getID()and detached:getFullType()==s.water:getFullType())
    assert(s.adapters.deferredTransferBinding(action,current)==nil,'same-ID queue member needs its own native/source alias contract')
    assert(action.item==s.water and action.queueList[1].items[1]==detached and queue.queue[2]==action,
        'unsupported Host alias observation must not rebind native producer state')
end
local function earnedObservation(bulkGuard,change)
    local s,current,action,queue,facts,bulk,intent,settlement=fixture(bulkGuard,true)
    assert(s.adapters.deferredTransferBinding(action,current)==nil,'Settlement listener cannot attest outside its private observation')
    local lookup=s.root.getItemById
    s.root.getItemById=function(self,id)if id==s.bag:getID()then return s.bag end;return lookup(self,id)end
    s.water.container=s.bagInventory
    local token=current.toolkitQueueOperation
    local scope=settlement.deferred(s.f.player,token)
    assert(settlement.remember(scope,current,{items={[facts.id]=true}}))
    local pickup=s.transfer(s.water,s.bagInventory,s.root);pickup.toolkitQueueOperation=token
    assert(settlement.preparePickup(scope,pickup))
    local record
    for key,seal in pairs(token)do if type(key)=='table'and type(seal)=='function'then record=seal(token)end end
    local candidate=assert(record and record.borrowings[1]).candidate
    -- The source-composition seam starts with earned private history. Native
    -- pickup receipts/physical DTO production retain their independent checks.
    candidate.phase,candidate.step.state='active','earned'
    s.water.container=s.root;token.toolkitPickups={[s.water]=s.bagInventory}
    if change=='unknown-listener'then intent.observeTransfers(function()error('unknown listener invoked')end,function()return false end,{})end
    local nativeReads=0
    toolkitLeafTransferFacts=function(actor,item,source,destination,id,fullType)
        nativeReads=nativeReads+1
        assert(actor==s.f.player and item==s.water and source==s.root and destination==s.bagInventory
            and id==facts.id and fullType==facts.fullType)
        if change=='class'then ISInventoryTransferAction.transferItem=function()error('changed class callback invoked')end
        elseif change=='private'then candidate.phase='waived'
        elseif change=='facts'then facts.id=facts.id+1
        elseif change=='location'then facts.location=facts.destination
        elseif change=='late-listener'then intent.observeTransfers(function()error('late listener invoked')end,function()return false end,{})end
        s.forbidProofReads()
        local function forbidden()error('source composition called a getter after final DTO')end
        s.water.getID,s.water.getFullType,s.water.getContainer=forbidden,forbidden,forbidden
        s.f.player.getInventory,s.f.player.getPlayerNum,s.f.player.isDead=forbidden,forbidden,forbidden
        s.root.getItemById,s.bagInventory.getItemById,getTimestampMs=forbidden,forbidden,forbidden
        return facts
    end
    local result=settlement.observeEditCleanup(queue,current)
    toolkitLeafTransferFacts=nil
    assert(queue.current==current and queue.queue[2]==action and not queue.toolkitCancel,'joint observation changed native queue ownership')
    return result,nativeReads
end
for _,bulkGuard in ipairs({false,true})do
    local result,reads=earnedObservation(bulkGuard)
    assert(reads==1 and result.status=='observed'and result.borrowings[1].effect=='native-leaf-location',
        'actual central/Tidy/Settlement composition failed to qualify the final return effect: reads='..tostring(reads)..' status='..tostring(result.status)..' reason='..tostring(result.reason)..' effect='..tostring(result.borrowings and result.borrowings[1]and result.borrowings[1].effect))
end
for _,change in ipairs({'unknown-listener','late-listener','class','private','facts','location'})do
    local result,reads=earnedObservation(true,change)
    assert(result.status=='unhandled'or result.borrowings[1].effect==nil,'joint source composition accepted '..change)
    assert(reads==(change=='unknown-listener'and 0 or 1),'unexpected final facts read count for '..change)
end
do
    local s,current,action=fixture(false,false)
    local calls=0
    local previous=ISInventoryTransferAction.start
    local replacement=function()error('unknown class wrapper invoked')end
    local guard=function()calls=calls+1;return true end
    ISInventoryTransferAction.start=replacement
    assert(s.adapters.adoptMethods(ISInventoryTransferAction,{start=previous},{start=replacement},guard))
    local before=calls
    assert(s.adapters.deferredTransferBinding(action,current)==nil and calls==before,
        'an unknown successful adoption guard cannot become a central observation contract')
end
print('Central deferred sources: actual native classes, Queue base ancestry, Bulk receipt and Settlement/Tidy listener composition; pure final validation and unknown-source fallback passed.')
if TestCoverage then TestCoverage('source-contract','passed')end
