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
local savedRequire=require
local modules={}
require=function(name)
    if name=='PZSurvivorToolkit/ActionQueueEditModel'or name=='PZSurvivorToolkit/ActionQueueEditTransition'then
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
local unknown=observe({kind='cancel',action=a,whole=true})
assert(unknown.projection.reason=='edit_obligation_unknown','missing private ledger must stay unknown')
settlement.track(a,'body')
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
assert(policy.observeActiveEdit(7,{}).status=='unhandled')
print('Active edit observation: native reader boundaries, shared progress, unchanged rights and no execution passed')
if TestCoverage then TestCoverage('source-contract','passed')end
