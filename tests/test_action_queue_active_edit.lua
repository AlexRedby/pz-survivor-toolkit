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
getFirstLineOfClosure=NativeFirstLineOfClosure or function(callback)return debug.getinfo(callback,'S').linedefined+1 end
local function sourceText(path)
    if NativeReadText then return NativeReadText(path)end
    local file=assert(io.open(path));local text=file:read('*a');file:close();return text
end
local function sourceReader(text)
    text=text:gsub('\r','')
    local position=1
    return {close=function()end,readLine=function()
        if position>#text then return end
        local boundary=text:find('\n',position,true)or #text+1
        local line=text:sub(position,boundary-1);position=boundary+1;return line
    end}
end
getModFileReader=function(mod,path)
    assert(mod=='PZSurvivorToolkit','only owned candidate sources are available')
    return sourceReader(sourceText(ProjectRoot..'/PZSurvivorToolkit/42/'..path))
end
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
isServer=function()return false end
local operations=f.project('ActionQueueOperations');f.project('ActionQueueDefinitions')
-- The policy captures this actual factory at load time. The helper bodies and
-- mod source reader use the installed/native and candidate files unchanged.
luautils={}
local utilities=sourceText(NativeActionRoot..'/shared/luautils.lua'):gsub('\r','')
assert(loadstring(assert(utilities:match('(function luautils.walkAdj%(.-\nend)'))..'\n'..
    assert(utilities:match('(luautils.getCorrectSquareForWall = function.-\nend)')),
    '@'..NativeActionRoot..'/shared/luautils.lua'))()
local nativeWalk=luautils.walkAdj
local approach=f.project('ActionQueueApproach');assert(approach.install())
local spatialFactory=approach.prepareSpatialLease
local foreignFactoryCalls=0
local function foreignFactory()foreignFactoryCalls=foreignFactoryCalls+1;error('foreign factory must not run')end
approach.prepareSpatialLease=foreignFactory
local foreignFactoryPolicy=f.project('ActionQueuePolicy')
local otherRole=approach.rebuild
approach.prepareSpatialLease=otherRole
f.project('ActionQueueDefinitions')
local sameFileFactoryPolicy=f.project('ActionQueuePolicy')
approach.prepareSpatialLease=spatialFactory
f.project('ActionQueueDefinitions')
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
local retainedProviderProbe
-- The retained-transfer helper establishes only the bounded private source
-- context. It delegates to the actual source factory and never reads endpoints,
-- native transfer facts, capacity, constructors or action validity.
do
    local owner=PZSurvivorToolkit.ActionQueueItemEditAdapters
    local factory=assert(owner.deferredTransferBinding)
    local function scene()
        local current=book('Base.BookCarpentry1',true)
        current.toolkitQueueOperation.toolkitStarted=true
        local destination={class='ItemContainer'}
        local action=f.action(ISInventoryTransferAction,{item=current.item,srcContainer=root,destContainer=destination,
            allowMissingItems=true,maxTime=31,queueList={{items={current.item},time=31,type=current.item:getFullType()}}})
        action.toolkitQueueOperation=current.toolkitQueueOperation
        local queue=f.queue(current,action)
        settlement.track(current,'body')
        return queue,current,action
    end
    local queue,current,action=scene()
    local endpointReads=0
    local getter=player.getInventory
    player.getInventory=function()endpointReads=endpointReads+1;error('source context read a live endpoint')end
    local validate,alias,sourceWatch=settlement.prepareRetainedTransferBinding(queue,current,action,factory)
    player.getInventory=getter
    assert(type(validate)=='function'and alias==nil and type(sourceWatch)=='function'and sourceWatch(),
        'bounded retained source context lost the actual source factory contract')
    local prepare=settlement.prepareRetainedTransferBinding
    settlement.prepareRetainedTransferBinding=function()error('changed retained API executed')end
    assert(not sourceWatch(),'late retained API replacement escaped the final source watch')
    assert(prepare(queue,current,action,factory)==nil,
        'captured retained helper accepted a substituted public API before preparation')
    settlement.prepareRetainedTransferBinding=prepare
    PZSurvivorToolkit.ActionQueueSettlement={}
    assert(not sourceWatch(),'late Settlement owner replacement escaped the final source watch')
    PZSurvivorToolkit.ActionQueueSettlement=settlement
    assert(endpointReads==0 and validate({schema=2}),'plain native source validator must remain separate from physical effect evidence')
    assert(not validate({schema=2}),'retained helper must preserve the one-use source validator')
    -- Inspect only the descriptor identities of the genuine source factory.
    -- This identity evidence is specific to the offline Lua debug host.
    -- No source callback, validator or binding check is substituted here.
    assert(debug and type(debug.getupvalue)=='function','source descriptor identity check requires the offline Lua debug host')
    local function descriptor(name)
        for index=1,80 do
            local key,value=debug.getupvalue(factory,index)
            if not key then break end
            if key==name then return value end
        end
        error('missing prepared source descriptor: '..name)
    end
    local function globals(specifications)
        for _,specification in ipairs(specifications)do if specification.owner==_G then return specification end end
        error('source descriptor lost its global dependency schema')
    end
    local core=descriptor('sourceFactorySpecs')
    local aliasSpecs=descriptor('sourceFactoryAliasSpecs')
    local first,_,firstWatch=prepare(queue,current,action,factory)
    local second,_,secondWatch=prepare(queue,current,action,factory)
    assert(descriptor('sourceFactorySpecs')==core and descriptor('sourceFactoryAliasSpecs')==aliasSpecs,
        'unchanged registry rebuilt its prepared source descriptions')
    assert(first~=second and firstWatch~=secondWatch and firstWatch()and secondWatch(),
        'reusable source description reused a decision watch or one-use validator')
    action.retainedFixtureAnnotation=true
    assert(not firstWatch()and not secondWatch(),'prepared source description cached action authority')
    local _,_,freshWatch=prepare(queue,current,action,factory)
    assert(type(freshWatch)=='function'and freshWatch(),'new preparation did not capture the changed action freshly')
    local transaction=createItemTransaction
    local aliasItem=f.item(current.item:getFullType())
    aliasItem.id=current.item:getID()
    action.queueList[1].items[1]=aliasItem
    local _,aliasMember,aliasWatch=prepare(queue,current,action,factory)
    local _,secondAlias,secondAliasWatch=prepare(queue,current,action,factory)
    assert(aliasMember==aliasItem and secondAlias==aliasItem and type(aliasWatch)=='function'and aliasWatch()
        and secondAliasWatch~=aliasWatch and secondAliasWatch(),
        'source-only Host alias preparation lost its fresh binding contract')
    assert(descriptor('sourceFactorySpecs')==core and descriptor('sourceFactoryAliasSpecs')==aliasSpecs and core~=aliasSpecs,
        'Host alias rebuilt or mutated the shared source descriptions')
    assert(#globals(core).keys==2 and #globals(aliasSpecs).keys==3 and globals(aliasSpecs).keys[3]=='createItemTransaction',
        'Host transaction dependency escaped its separate immutable source description')
    for index=1,#core-1 do assert(core[index]==aliasSpecs[index],'Host alias duplicated a shared module dependency description')end
    createItemTransaction=function()error('changed transaction callback must not execute')end
    assert(not aliasWatch()and not secondAliasWatch(),'Host alias lost its fresh transaction source watch')
    action.queueList[1].items[1]=current.item
    local _,_,ordinaryWatch=prepare(queue,current,action,factory)
    assert(type(ordinaryWatch)=='function'and ordinaryWatch(),'ordinary source preparation inherited the alias dependency')
    createItemTransaction=transaction
    assert(ordinaryWatch(),'ordinary source watch incorrectly retained a transaction dependency')
    -- A genuine source owner's definition-time registration replaces both
    -- descriptions and revokes the old watch; no positive fake is installed.
    assert(PZSurvivorToolkit.ActionQueueTidyIntent==nil,'registration probe must use a previously unloaded source owner')
    local intent=f.project('ActionQueueTidyIntent')
    assert(type(intent.transferListenerBinding)=='function'and not ordinaryWatch(),
        'genuine source registration did not revoke the prior decision')
    local newCore,newAlias=descriptor('sourceFactorySpecs'),descriptor('sourceFactoryAliasSpecs')
    local _,_,registeredWatch=prepare(queue,current,action,factory)
    assert(type(registeredWatch)=='function'and registeredWatch()and newCore~=core and newAlias~=aliasSpecs,
        'genuine source registration did not replace both descriptions')
    assert(owner.registerSourceFactory(intent,'transferListenerBinding',intent.transferListenerBinding))
    prepare(queue,current,action,factory)
    assert(descriptor('sourceFactorySpecs')==newCore and descriptor('sourceFactoryAliasSpecs')==newAlias,
        'idempotent source registration unnecessarily replaced the descriptions')
    local calls=0;local replacement=function()calls=calls+1;error('replacement source factory executed')end
    owner.deferredTransferBinding=replacement
    assert(settlement.prepareRetainedTransferBinding(queue,current,action,factory)==nil and calls==0,
        'retained source context discovered/invoked a replaced factory')
    owner.deferredTransferBinding=factory
    for _,change in ipairs({'foreign-token','started','removed','untracked-current'})do
        queue,current,action=scene()
        if change=='foreign-token'then action.toolkitQueueOperation={}
        elseif change=='started'then action.started=true
        elseif change=='removed'then queue.queue[2]=nil
        else
            current=book('Base.BookCooking1',true);queue=f.queue(current,action)
            action.toolkitQueueOperation=current.toolkitQueueOperation
        end
        assert(settlement.prepareRetainedTransferBinding(queue,current,action,factory)==nil,
            'unsupported retained source context accepted '..change)
    end
    -- A throwing real factory must not leave its private context installed;
    -- the next independent valid preparation must still succeed.
    queue,current,action=scene()
    local id=current.item.getID
    current.item.getID=function()error('expected retained factory getter failure')end
    assert(settlement.prepareRetainedTransferBinding(queue,current,action,factory)==nil)
    current.item.getID=id
    assert(type(settlement.prepareRetainedTransferBinding(queue,current,action,factory))=='function',
        'failed retained factory leaked its private source context')
    queue,current,action=scene()
    local _,_,beforeProvider=settlement.prepareRetainedTransferBinding(queue,current,action,factory)
    assert(type(beforeProvider)=='function'and beforeProvider())
    retainedProviderProbe=function()
        local previous=ISTimedActionQueue.queues[player]
        ISTimedActionQueue.queues[player]=queue
        assert(not beforeProvider(),'late cleanup provider registration escaped the retained source watch')
        assert(settlement.prepareRetainedTransferBinding(queue,current,action,factory)==nil,
            'unknown cleanup provider acquired a retained source context')
        ISTimedActionQueue.queues[player]=previous
    end
    ISTimedActionQueue.queues[player]=q
end
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

    -- Reproduce a genuine source-owned walkAdj in the TV operation. The
    -- native dispatcher owns routing and expansion when this helper runs.
    local forbiddenCalls=0
    local function noWorld()forbiddenCalls=forbiddenCalls+1;error('observer sampled future spatial execution')end
    player.isLocalPlayer=function()return true end
    player.isDraggingCorpse=function()return false end
    player.getX,player.getY,player.getSquare,player.getCurrentSquare=noWorld,noWorld,noWorld,noWorld
    square.getX,square.getY,square.getZ=noWorld,noWorld,noWorld
    local cellGetter=getCell;getCell=noWorld
    local count=#queue.queue
    operations.runWith(setting.toolkitQueueOperation,function()assert(luautils.walkAdj(player,square,false))end)
    assert(#queue.queue==count+1,'native walkAdj must enqueue its real deferred command')
    local spatial=table.remove(queue.queue)
    table.insert(queue.queue,2,spatial)
    assert(approach.isAction(spatial)and spatial.toolkitQueueOperation==setting.toolkitQueueOperation)
    local checkpointAction=current.action
    local forbiddenNative={[nativeWalk]=true,[spatial.toolkitQueueCommand.callback]=true}
    for _,name in ipairs({'isValid','start','update','stop','perform','complete','performSetVolume'})do
        if type(setting[name])=='function'then forbiddenNative[setting[name]]=true end
    end
    local function noExecution(callback)
        local calls=0
        debug.sethook(function(event)
            if event=='call'and forbiddenNative[debug.getinfo(2,'f').func]then
                calls=calls+1;error('observer executed a native action or route')
            end
        end,'c')
        local ok,result=pcall(callback)
        debug.sethook()
        assert(ok,result);assert(calls==0,'native callback was invoked and swallowed')
        return result
    end
    local function nativePhase(result)
        assert(result.status=='observed'and result.allowed==nil
            and result.projection.status=='deferred'and result.projection.reason=='edit_native_resolution'
            and result.projection.allowed==nil and #result.contractGaps==0,
            'genuine walkAdj must be deferred without a contract gap or new edit permission')
        assert(#result.projection.deferred==1 and result.projection.deferred[1].action==spatial
            and result.projection.blocker==spatial and result.projection.evaluatedPrefix==1)
        local phases=0
        for _,node in ipairs(result.nodes)do
            if node.deferred then
                phases=phases+1
                assert(node.action==spatial and node.edit==nil
                    and node.deferred.actor==player and node.deferred.targetSquare==square)
            end
        end
        assert(phases==1 and result.nodes[2].action==spatial and result.nodes[3].action==setting
            and result.nodes[4].kind=='resume'and result.nodes[5].action==tail)
        assert(current.action==checkpointAction and not spatial.started and not spatial.action
            and not setting.started and not setting.action and current.item:getAlreadyReadPages()==37)
    end
    nativePhase(noExecution(function()return observation(setting,current)end))
    nativePhase(noExecution(function()return observation(current,setting,true)end))

    -- A foreign closure and a different role in the same real source file
    -- must be rejected before invocation, even when captured at policy load.
    for _,case in ipairs({{policy=foreignFactoryPolicy,factory=foreignFactory},
        {policy=sameFileFactoryPolicy,factory=otherRole}})do
        approach.prepareSpatialLease=case.factory
        forbiddenNative[case.factory]=true
        local denied=noExecution(function()
            return case.policy.observeActiveEdit(queue,{kind='move',action=setting,target=current})
        end)
        assert(denied.status=='observed'and denied.projection.status=='unhandled'
            and #denied.contractGaps==1 and denied.contractGaps[1].action==spatial,
            'an unauthenticated factory role must leave the spatial helper unknown')
        forbiddenNative[case.factory]=nil
        approach.prepareSpatialLease=spatialFactory
        PZSurvivorToolkit.ActionQueuePolicy=policy
    end
    assert(foreignFactoryCalls==0)
    nativePhase(noExecution(function()return observation(setting,current)end))

    -- Init-time prerequisites cover used bindings, while unrelated mod helpers
    -- added to the standard libraries after load retain the native phase.
    local foreignHelperCalls=0
    local function foreignHelper()foreignHelperCalls=foreignHelperCalls+1;error('changed source prerequisite executed')end
    local owners={string,table,math};local previous={}
    for index,owner in ipairs(owners)do previous[index]=owner.activeEditFixtureUnused;owner.activeEditFixtureUnused=foreignHelper end
    local ok,extended=pcall(noExecution,function()return observation(setting,current)end)
    for index,owner in ipairs(owners)do owner.activeEditFixtureUnused=previous[index]end
    assert(ok,extended);nativePhase(extended)
    assert(foreignHelperCalls==0,'an unrelated standard-library helper was invoked')
    for _,binding in ipairs({{owner=string,name='byte'},{owner=string,name='sub'},{owner=_G,name='getModFileReader'}})do
        -- The successful controls above warmed native source pins. The changed
        -- identity must be rejected before own-module hash/source IO can run.
        local owner,name=binding.owner,binding.name;local original=owner[name]
        owner[name]=foreignHelper
        local valid,changed=pcall(noExecution,function()
            return policy.observeActiveEdit(queue,{kind='move',action=setting,target=current})
        end)
        owner[name]=original
        assert(valid,changed)
        assert(changed.status=='observed'and changed.projection.status=='unhandled'
            and #changed.contractGaps==1 and changed.contractGaps[1].action==spatial,
            'changed source prerequisite must leave the deferred helper unknown')
        assert(foreignHelperCalls==0,'a changed source prerequisite ran before identity rejection')
        nativePhase(noExecution(function()return observation(setting,current)end))
    end

    -- Calibrate the real final cleanup inventory read against a successful
    -- control; mutate after preparation to prove the query-local lease revokes.
    local inventoryGetter=player.getInventory
    for _,mutation in ipairs({'source','request'})do
        local reads=0
        player.getInventory=function(self,...)reads=reads+1;return inventoryGetter(self,...)end
        local control=noExecution(function()
            return policy.observeActiveEdit(queue,{kind='move',action=setting,target=current})
        end)
        nativePhase(control)
        local finalRead=reads
        local originalGuard=luautils.getCorrectSquareForWall
        local request=spatial.toolkitQueueCommand.snapshot
        local target=request.args[2]
        local mutated=false
        reads=0
        player.getInventory=function(self,...)
            reads=reads+1
            assert(reads<=finalRead,'observer called another getter after final cleanup facts')
            if reads==finalRead then
                mutated=true
                if mutation=='source'then luautils.getCorrectSquareForWall=noWorld
                else request.args[2]={}end
            end
            return inventoryGetter(self,...)
        end
        local changed=noExecution(function()
            return policy.observeActiveEdit(queue,{kind='move',action=setting,target=current})
        end)
        player.getInventory=inventoryGetter
        luautils.getCorrectSquareForWall=originalGuard;request.args[2]=target
        assert(mutated and changed.status=='unhandled'and changed.reason=='unavailable',
            'late '..mutation..' mutation escaped the final spatial lease')
        assert(queue.current==current and queue.queue[1]==current and queue.queue[2]==spatial
            and queue.queue[3]==setting and queue.queue[4]==tail and current.item:getAlreadyReadPages()==37)
        nativePhase(noExecution(function()return observation(setting,current)end))
    end
    local lineCapability=getFirstLineOfClosure
    getFirstLineOfClosure=nil
    local missing=noExecution(function()return observation(setting,current)end)
    getFirstLineOfClosure=lineCapability
    assert(missing.status=='observed'and missing.projection.status=='unhandled'
        and #missing.contractGaps==1 and missing.contractGaps[1].action==spatial,
        'missing role metadata must keep the helper unknown')
    nativePhase(noExecution(function()return observation(setting,current)end))
    assert(forbiddenCalls==0,'spatial observation executed a world callback')
    getCell=cellGetter
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
retainedProviderProbe()
assert(policy.observeActiveEdit(7,{}).status=='unhandled')
print('Active edit observation: native reader boundaries, shared progress, unchanged rights and no execution passed')
if TestCoverage then TestCoverage('source-contract','passed')end
