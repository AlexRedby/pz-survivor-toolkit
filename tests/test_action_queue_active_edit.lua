if not NativeActionRoot then if TestCoverage then TestCoverage('source-contract','skipped','Active edit observation SKIP (pass --game).')end;return end
-- Offline Lua models the JVM's actual-metatable check explicitly. Native
-- Kahlua runs use the real exported helper instead of this fixture.
if not toolkitLuaMetatableMatches and debug and debug.getmetatable then
    local fixtureType,fixtureEqual,fixtureMeta=type,rawequal,debug.getmetatable
    toolkitLuaMetatableMatches=function(owner,expected)
        return fixtureType(owner)=='table'and fixtureEqual(fixtureMeta(owner),expected)
    end
end
local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
f.native('shared/RadioCom/ISRadioAction.lua')
f.native('shared/TimedActions/ISEquipWeaponAction.lua')
getFilenameOfClosure=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
-- Source proofs read the installed vanilla text, without inventing checksums
-- or treating the fixture's Java objects as native execution evidence.
getGameFilesInput=function(path)
    local filename=NativeActionRoot..'/'..path:gsub('^media/lua/','')
    local text
    if NativeReadText then text=NativeReadText(filename)
    else local file=assert(io.open(filename));text=file:read('*a');file:close()end
    text=text:gsub('\r','')
    local position=1
    return {close=function()end,readLine=function()
        if position>#text then return end
        local boundary=text:find('\n',position,true)or #text+1
        local line=text:sub(position,boundary-1);position=boundary+1;return line
    end}
end
local savedRequire=require
local modules={}
require=function(name)
    if name=='PZSurvivorToolkit/ActionQueueEditModel'or name=='PZSurvivorToolkit/ActionQueueEditTransition'
        or name=='PZSurvivorToolkit/ActionQueueEditAdapters'then
        if not modules[name]then modules[name]=f.project(name:match('/([^/]+)$'))end
        return modules[name]
    end
    return savedRequire(name)
end
isClient=function()return false end
f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
local policy=f.project('ActionQueuePolicy')
local settlement=f.project('ActionQueueSettlement')
local player=f.player
player.class='IsoPlayer'
local root={class='ItemContainer',getType=function()return 'inventory'end,
    getParent=function()return player end,getContainingItem=function()end,getAcceptItemFunction=function()end}
player.inventory=root
local function book(kind,active)
    local item=f.item(kind)
    item.getNumberOfPages=function()return 100 end
    item.getAlreadyReadPages=function()return 37 end
    return f.action(ISReadABook,{item=item,action=active and {isStarted=function()return true end,finished=function()return false end,isForceComplete=function()return false end}or nil,started=active and true or nil})
end
local a,b,c=book('Base.BookCarpentry1',true),book('Base.BookCooking1'),book('Base.BookFirstAid1')
local q=f.queue(a,b,c)
local forbidden={[ISReadABook.new]=true,[ISReadABook.isValid]=true,[ISReadABook.start]=true,
    [ISReadABook.stop]=true,[ISReadABook.perform]=true,[ISReadABook.complete]=true}
local function observe(intent)
    local unchanged={q.queue[1],q.queue[2],q.queue[3]}
    debug.sethook(function(event)
        if event=='call'and forbidden[debug.getinfo(2,'f').func]then error('observer executed native action')end
    end,'c')
    local ok,result=pcall(policy.observeActiveEdit,q,intent)
    debug.sethook()
    assert(ok,result)
    assert(q.current==a and not q.toolkitCancel and not q.toolkitResume)
    for index,action in ipairs(unchanged)do assert(q.queue[index]==action)end
    return result
end
local started=a.action.isStarted
a.action.isStarted=function()return false end
assert(observe({kind='move',action=c,target=a}).reason=='edit_in_flight','allocation is not a started read checkpoint')
a.action.isStarted=started
settlement.track(a,'body')
local before=policy.evaluateMove(q,c,a)
local promotion=observe({kind='move',action=c,target=a})
assert(promotion.status=='observed'and promotion.allowed==nil)
assert(promotion.nodes[2].action==c and promotion.nodes[3].kind=='resume'and promotion.nodes[3].action==a
    and promotion.nodes[4].action==b)
assert(promotion.checkpoint.stage=='before-stop'and promotion.checkpoint.pages==37
    and promotion.checkpoint.id==a.item:getID())
assert(promotion.projection.status=='allowed','distinct native root reads should project their item requirements')
local after=policy.evaluateMove(q,c,a)
assert(before.allowed==after.allowed and before.reason==after.reason,'observation changed native edit permission')
local demotion=observe({kind='move',action=a,target=c,after=true})
assert(demotion.status=='observed'and demotion.nodes[2].action==b and demotion.nodes[3].action==c
    and demotion.nodes[4].kind=='resume')
local body=observe({kind='cancel',action=a})
assert(body.status=='observed'and body.nodes[2].action==b and #body.removed==1)
local untracked=book('Base.BookFirstAid2',true)
local untrackedQueue=f.queue(untracked,book('Base.BookCooking2'))
local unknown=policy.observeActiveEdit(untrackedQueue,{kind='cancel',action=untracked,whole=true})
assert(unknown.projection.reason=='edit_obligation_unknown','missing private ledger must stay unknown')
ISTimedActionQueue.queues[player]=q
local whole=observe({kind='cancel',action=a,whole=true})
assert(whole.status=='observed'and whole.projection.status=='allowed'and #whole.removed==1)
-- Shared native progress belongs to book type even for a different item ID.
local original=c.item.getFullType
c.item.getFullType=function()return a.item:getFullType()end
assert(policy.evaluateMove(q,c,a).reason=='move_shared_book')
assert(observe({kind='move',action=c,target=a}).projection.status=='unhandled')
c.item.getFullType=original
local savedItem=c.item
c.item=nil
assert(observe({kind='move',action=c,target=a}).projection.status=='unhandled',
    'a missing future book item must stay unknown without a metadata callback error')
c.item=savedItem
-- Before-stop observation cannot be used after replacement/reset/changed source.
local getPages=a.item.getAlreadyReadPages
local originalItem=a.item
local replacement=f.item('Base.BookCarpentry1')
a.item.getAlreadyReadPages=function()a.item=replacement;return 37 end
assert(observe({kind='move',action=c,target=a}).status=='unhandled')
a.item=originalItem;a.item.getAlreadyReadPages=getPages
local savedGeneration=q.toolkitOperationGeneration
-- Inspect freshness at the last current getter.
a.item.getAlreadyReadPages=function()q.toolkitOperationGeneration=91;return 37 end
assert(observe({kind='move',action=c,target=a}).reason=='unavailable')
q.toolkitOperationGeneration=savedGeneration;a.item.getAlreadyReadPages=getPages
local start=a.start
a.start=function()error('changed source must not execute')end
assert(observe({kind='move',action=c,target=a}).status=='unhandled')
a.start=start
local inspect=policy.inspect
policy.inspect=function()error('public inspector replacement must not run')end
-- The internal source-bound inspector is used, not a replaceable public callback.
assert(observe({kind='move',action=c,target=a}).status=='observed')
policy.inspect=inspect
-- Exercise the real cleanup observer. Calibrate its final inventory read on
-- an unchanged control, then mutate exactly that read in a disposable queue.
-- No replacement cleanup contract or debug hook supplies the observation.
do
    local call,setMeta,getMeta,each=pcall,setmetatable,getmetatable,ipairs
    local globals,toolkit=_G,PZSurvivorToolkit
    local transition=toolkit.ActionQueueEditTransition
    local transitionProject,transitionMeta=transition.project,getMeta(transition)
    local inventoryGetter=player.getInventory
    local originalPairs=pairs
    local function probeQueue()
        local current=book('Base.BookCarpentry1',true);current.started=nil
        local queue=f.queue(current,book('Base.BookCooking1'),book('Base.BookFirstAid1'))
        settlement.track(current,'body')
        return queue,current,{kind='cancel',action=current,whole=true}
    end
    for _,boundary in each({'transition-meta','queue-meta','masked-queue-meta','pairs'})do
        local queue,current,intent=probeQueue()
        local reads=0
        player.getInventory=function(self,...)reads=reads+1;return inventoryGetter(self,...)end
        local control=policy.observeActiveEdit(queue,intent)
        assert(control.status=='observed'and control.projection.status=='allowed'and reads>0)
        local finalRead=reads
        local lateCalls,mutated=0,false
        local function hostile()lateCalls=lateCalls+1;error('post-cleanup callback')end
        local queueMeta=getMeta(queue)
        reads=0
        player.getInventory=function(self,...)
            reads=reads+1
            if reads>finalRead then hostile()end
            if reads==finalRead then
                mutated=true
                if boundary=='transition-meta'then transition.project=nil;setMeta(transition,{__index=hostile})
                elseif boundary=='queue-meta'then setMeta(queue,{__index=hostile})
                elseif boundary=='masked-queue-meta'then setMeta(queue,{__metatable=queueMeta,__index=hostile})
                else globals.pairs=hostile end
            end
            return inventoryGetter(self,...)
        end
        local ok,result=call(policy.observeActiveEdit,queue,intent)
        -- The protected disposable queue is never used again. Restore the live
        -- registry directly, without unmasking through a Lua metatable getter.
        globals.pairs=originalPairs
        setMeta(transition,transitionMeta);transition.project=transitionProject
        player.getInventory=inventoryGetter
        ISTimedActionQueue.queues[player]=q
        assert(mutated and ok and result.status=='unhandled'and lateCalls==0,
            boundary..': final cleanup read reached a hostile callback')
        assert(queue.current==current and queue.queue[1]==current,'observation changed its disposable native queue')
    end
    local helper=toolkitLuaMetatableMatches
    toolkitLuaMetatableMatches=nil
    local ok,result=call(policy.observeActiveEdit,q,{kind='cancel',action=a,whole=true})
    toolkitLuaMetatableMatches=helper
    assert(ok and result.status=='unhandled','metatable-bearing queue must decline without its native identity helper')
end
-- Borrowed book + return + plain hand equip: record the unresolved return and
-- preserve the existing capacity guard. Neither hints nor previews earn a loan.
do
    local returned=f.action(ISInventoryTransferAction,{item=a.item,srcContainer=root,
        destContainer={class='ItemContainer',getType=function()return 'container'end,
            getParent=function()return {class='IsoObject'}end,getContainingItem=function()end,
            getAcceptItemFunction=function()return function()error('acceptance callback must not run')end end},
        allowMissingItems=true})
    returned.toolkitQueueOperation=a.toolkitQueueOperation
    local equip=f.action(ISEquipWeaponAction,{item=f.item('Base.Pen'),primary=true,twoHands=false})
    q=f.queue(a,returned,equip)
    a.toolkitQueueOperation.toolkitPickups={[a.item]=returned.destContainer}
    local copied=policy.observeActiveEdit(q,{kind='cancel',action=a,whole=true})
    assert(copied.status=='observed'and copied.projection.reason=='edit_obligation_unknown')
    assert(not policy.evaluateCancel(q,a,true).allowed,'observation must not wash a protected callback/capacity gate')
end
-- A source-owned direct TV setter has a complete observation contract. This
-- deliberately has no producer-inserted approach and proves no routing support.
do
    local tv={class='IsoTelevision'}
    local square={class='IsoGridSquare'}
    local data={class='DeviceData'}
    tv.getObjectIndex=function()return 0 end;tv.getSquare=function()return square end
    tv.getDeviceData=function()return data end
    data.getParent=function()return tv end;data.isIsoDevice=function()return true end
    data.isVehicleDevice=function()return false end;data.getIsTurnedOn=function()return true end
    data.getPower=function()return 1 end;data.getDeviceVolume=function()return .5 end
    data.getChannel=function()return 200 end;data.getMicIsMuted=function()return false end
    data.getMinChannelRange=function()return 100 end;data.getMaxChannelRange=function()return 1000 end
    local function volume()
        local action=ISRadioAction:new('SetVolume',player,tv,.25)
        action.toolkitQueueOperation={}
        return action
    end
    local current,setting,tail=book('Base.BookCarpentry2',true),volume(),book('Base.BookCooking2')
    local queue=f.queue(current,setting,tail)
    settlement.track(current,'body')
    local leaf=toolkitLeafTransferFacts
    local leafReads=0
    toolkitLeafTransferFacts=function()leafReads=leafReads+1;error('root reader has no borrowed transfer')end
    local function observation(action,target,after)
        local members={}
        for i,member in ipairs(queue.queue)do members[i]=member end
        local before=policy.evaluateMove(queue,action,target,after)
        local result=policy.observeActiveEdit(queue,{kind='move',action=action,target=target,after=after})
        local unchanged=policy.evaluateMove(queue,action,target,after)
        assert(before.allowed==unchanged.allowed and before.reason==unchanged.reason,
            'observation changed the existing authoritative edit permission')
        assert(result.allowed==nil,'an observation must not export public edit permission')
        assert(queue.current==current and not queue.toolkitCancel and not queue.toolkitResume
            and not queue.toolkitGroupCancel and #queue.queue==#members,'observation mutated active queue')
        for i,member in ipairs(members)do assert(queue.queue[i]==member,'observation changed queue order')end
        assert(current.item:getAlreadyReadPages()==37 and setting.secondaryItem==.25)
        return result
    end
    local promoted=observation(setting,current)
    assert(promoted.status=='observed'and promoted.projection.status=='allowed'
        and promoted.nodes[2].action==setting and promoted.nodes[3].kind=='resume'
        and #promoted.contractGaps==0,'direct root TV setter should project without claiming native approach support')
    local demoted=observation(current,setting,true)
    assert(demoted.status=='observed'and demoted.projection.status=='allowed'
        and demoted.nodes[2].action==setting and demoted.nodes[3].kind=='resume')

    local nativeHelper=setting.performSetVolume
    setting.performSetVolume=function()error('foreign mode helper must not run')end
    local changedCallback=observation(setting,current)
    assert(changedCallback.projection.status=='unhandled'and #changedCallback.contractGaps==1
        and changedCallback.contractGaps[1].action==setting,
        'changing a native helper must leave an explicit observation contract gap')
    setting.performSetVolume=nativeHelper
    assert(observation(setting,current).projection.status=='allowed',
        'restoring the exact native helper restores only its observation contract')

    local helperCalls=0
    -- This owned generic command intentionally has no routing edit contract;
    -- it is not presented as a proven ActionQueueApproach request.
    local helper=PZSurvivorToolkit.ActionQueueOperations.command(player,function()
        helperCalls=helperCalls+1;error('planner must not execute deferred helper')
    end,{})
    helper.toolkitQueueOperation=setting.toolkitQueueOperation
    table.insert(queue.queue,2,helper)
    local unresolved=observation(setting,current)
    assert(unresolved.status=='observed'and unresolved.projection.status=='unhandled'
        and #unresolved.contractGaps==1 and unresolved.contractGaps[1].action==helper
        and unresolved.contractGaps[1].actionType=='ISQueueActionsAction'and helperCalls==0,
        'an uncontracted helper must remain diagnostic unknown without running its native expansion')
    table.remove(queue.queue,2)

    local destination={class='ItemContainer',getType=function()return 'container'end,
        getParent=function()return {class='IsoObject'}end,getContainingItem=function()end,
        getAcceptItemFunction=function()end}
    local unpaid=f.action(ISInventoryTransferAction,{item=current.item,srcContainer=root,
        destContainer=destination,allowMissingItems=true})
    unpaid.toolkitQueueOperation=current.toolkitQueueOperation
    table.insert(queue.queue,2,unpaid)
    assert(observation(setting,current).projection.status=='unhandled',
        'a lookalike optional return without earned descriptor must remain observation unknown')
    table.remove(queue.queue,2)

    local providerCalls=0
    settlement.register('active-edit-test-unknown',{retain=function()providerCalls=providerCalls+1;error('provider must not run')end})
    local providerUnknown=observation(setting,current)
    assert(providerUnknown.projection.reason=='edit_obligation_unknown'and providerCalls==0,
        'an unknown cleanup provider must remain unresolved without executing it')
    assert(leafReads==0,'root-only observations did not earn transfer facts or runtime rights')
    toolkitLeafTransferFacts=leaf
end
assert(policy.observeActiveEdit(7,{}).status=='unhandled')
print('Active edit observation: native reader boundaries, shared progress, unchanged rights and no execution passed')
if TestCoverage then TestCoverage('source-contract','passed')end
