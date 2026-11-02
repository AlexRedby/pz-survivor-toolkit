toolkitLuaMetatableMatches=assert(loadfile((ProjectRoot or '.')..'/tests/support/source_binding.lua'))()
-- Exercise owner-created leases independently of native admission/gameplay.
local root=ProjectRoot or '.'
local function read(path)
    if NativeReadText then return NativeReadText(path)end
    local file=assert(io.open(path));local value=file:read('*a');file:close();return value
end
local source=read(root..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua')
local factories=assert(source:match('(local bindingCapture =.-)local function verified'))
local methods=assert(source:match('(local function transferMethods%(%).-\nend)'))
local bcInstall=assert(source:match('(local function installContainerTransfers%(%).-\nend)'))
local fridgeInstall=assert(source:match('(local function installFridgeTransfers%(%).-\nend)'))
local query=assert(source:match('(function Compat.isTransferPerform%(callback%).-\nend)'))
local function fixture()
    local origins={}
    local frozen=false
    getFilenameOfClosure=function(callback)
        assert(not frozen,'post-lease metadata')
        return origins[callback]or (NativeFilenameOfClosure and NativeFilenameOfClosure(callback))or debug.getinfo(callback,'S').source
    end
    local proof=assert(loadfile(root..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
    local callbacks={}
    local function native()error('source lease executed gameplay')end
    local toolkit={Settings={actionQueue=native}}
    local operations={perform=native,adoptReturnMethods=function()return true end,adoptReturnHooks=function()return true end}
    local settlement={}
    for _,name in ipairs({'admittedPickupScope','refreshPickup','departure','pickupMatches','beforePickupMerge','beginPickup',
        'finishPickup','refreshReturn','returnMatches','beginReturn','finishReturn','stopReturn'})do settlement[name]=native end
    local policy={matchesNative=native,isOrdinaryTransfer=native,adoptTransferMethods=function(_,_,guard)callbacks[#callbacks+1]=guard;return true end,
        adoptTransferHooks=function(_,_,guard)callbacks[#callbacks+1]=guard;return true end}
    toolkit.ActionQueueOperations,toolkit.ActionQueueSettlement,toolkit.ActionQueueTidyIntent,toolkit.ActionQueuePolicy=operations,settlement,{},policy
    PZSurvivorToolkit=toolkit
    ISInventoryTransferAction={}
    for _,name in ipairs({'new','isValid','start','perform','stop','transferItem'})do
        local callback=function()error('source lease executed transfer method')end
        ISInventoryTransferAction[name]=callback;origins[callback]='ISInventoryTransferAction.lua'
    end
    EURY_CONTAINERS={isStaleVehicleContainer=native}
    local proximity={invName='proximityInv',invName_corpses='twistInv_corpses',_TransferRunning={},_BrowseElapsedMs={}}
    for _,name in ipairs({'isLockedForPlayer','setTransferRunning','hasQueuedTransferAction','isProximityType'})do proximity[name]=native end
    TurnOffFridges={MODULE='TurnOffFridges',AUTO_KEY='TOF_auto',ON={fridgeoff='fridge',freezeroff='freezer'},OFF={fridge='fridgeoff',freezer='freezeroff'}}
    for _,name in ipairs({'clearFridgeProperty','autoTick','isFridgeObject','isAuto','isUnitEmpty','isUnplugged','requestAutoEval','applyLight'})do
        local callback=function()error('source lease executed fridge callback')end
        TurnOffFridges[name]=callback
        origins[callback]=name=='clearFridgeProperty'and 'TOF_TileProps.lua'or name=='autoTick'and 'TOF_Client.lua'
            or name=='applyLight'and 'TOF_Light.lua'or 'TOF_Core.lua'
    end
    local modules={['BetterContainers/Proximity']=proximity,['BetterContainers/Helpers']=EURY_CONTAINERS}
    for _,name in ipairs({'BetterContainers/Proximity/Proximity_ISInventoryTransferAction','BetterContainers/Nested'})do
        modules[name]={_installed=false,install=function()
            for _,method in ipairs({'isValid','start','perform','stop'})do
                local callback=function()error('source lease executed BC callback')end
                ISInventoryTransferAction[method]=callback;origins[callback]='BC.lua'
            end
        end}
    end
    local previousRequire=require
    require=function(name)
        if name=='TurnOffFridges/TOF_Client'then
            local callback=function()error('source lease executed TOF transfer')end
            ISInventoryTransferAction.perform=callback;origins[callback]='TOF_Client.lua';return true
        elseif name=='TurnOffFridges/TOF_Light'then return true end
        if modules[name]then return modules[name]end
        return previousRequire(name)
    end
    getActivatedMods=function()return {contains=function()return true end}end
    local build=assert(loadstring([[return function(Toolkit,Operations,Settlement,TidyIntent,Proof)
        local Compat={};Toolkit.ActionQueueCompat=Compat
        local ready,records,sessions={},{},{}
        local containerHelpersUnchanged,reviewedTransferPerform,transferPerformGuard
        local function verified()return true end
        ]]..factories..methods..'\n'..bcInstall..'\n'..fridgeInstall..'\n'..query..[[
        return {compat=Compat,bc=installContainerTransfers,tof=installFridgeTransfers,
            instance=function(action,record)records[action]=record end,
            dependencies=bindingDependencies,p4=function(guard,owner)
                ready.P4TidyUpMeister=true
                transferBindingRecords[guard]={kind='p4',id='P4TidyUpMeister',owner=owner,
                    ownerMethods={registerActionPolicy=owner.registerActionPolicy,registerWornItemReplacement=owner.registerWornItemReplacement}}
            end}
    end]],'@fixture/ActionQueueCompat.lua'))()(toolkit,operations,settlement,toolkit.ActionQueueTidyIntent,proof)
    build.proof,build.callbacks,build.proximity,build.toolkit=proof,callbacks,proximity,toolkit
    build.freeze=function()frozen=true end
    build.bc()
    return build
end
do
    local s=fixture();local action={character={}}
    assert(s.compat.transferBinding(function()error('unknown guard invoked')end,action)==nil)
    local lease=assert(s.compat.transferBinding(s.callbacks[1],action))
    s.freeze()
    getGameFilesInput=function()error('post-lease source reader')end
    assert(lease(),'BC source lease must be callback-free')
    s.proximity.isLockedForPlayer=function()end
    assert(not lease(),'BC helper replacement must revoke existing source proof')
end
do
    local s=fixture();s.tof();local action={character={}}
    local lease=assert(s.compat.transferBinding(s.callbacks[#s.callbacks],action))
    assert(lease({schema=2,sourceParentTypes=false,destinationParentTypes={'crate'}}))
    assert(not lease({schema=2,sourceParentTypes={'fridge'},destinationParentTypes=false}))
    assert(not lease({schema=2,sourceParentTypes=false,destinationParentTypes={'crate','freezeroff'}}),
        'ordinary container type cannot hide a fridge sibling')
    assert(not lease({schema=2,sourceParentTypes=false,destinationParentTypes={}}),'incomplete empty DTO must be rejected')
    s.proximity.isProximityType=function()end
    assert(not lease({schema=2,sourceParentTypes=false,destinationParentTypes=false}),'TOF lease must retain predecessor dependencies')
end
do
    local s=fixture();local owner={registerActionPolicy=function()end,registerWornItemReplacement=function()end}
    P4TidyUpMeister=owner
    local guard=function()error('P4 guard executed')end;s.p4(guard,owner)
    local lease=assert(s.compat.transferBinding(guard,{}));assert(lease())
    owner.registerActionPolicy=function()end;assert(not lease())
end
do
    local s=fixture();local originalPerform,originalStop=function()end,function()end
    local wrappedPerform,wrappedStop=function()end,function()end
    local action={perform=wrappedPerform,stop=function()error('outer Bulk stop invoked')end,onCompleteFunc=function()end}
    local record={id='P4TidyUpMeister',class=ISInventoryTransferAction,fields={},transferBinding={performDelegate=originalPerform,
        performWrapper=wrappedPerform,stopDelegate=originalStop,stopWrapper=wrappedStop,dependencies=s.dependencies()}}
    s.instance(action,record)
    local lease,description=s.compat.transferBinding(false,action)
    assert(lease and lease()and description.wrappedPerform==wrappedPerform and description.perform==originalPerform
        and description.wrappedStop==wrappedStop and description.stop==originalStop and description.completeWasAbsent)
    record.transferBinding.completion=function()end
    assert(not lease()and s.compat.transferBinding(false,action)==nil,'custom continuation completion cannot gain a source lease')
end
do
    local s=fixture()
    getFirstLineOfClosure=NativeFirstLineOfClosure or function(callback)return debug.getinfo(callback,'S').linedefined end
    local previousRequire=require
    require=function(name)if name=='PZSurvivorToolkit/SourceProof'then return s.proof end;return previousRequire(name)end
    local bulkSource=read(root..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/BulkActions.lua')
    local first=assert(bulkSource:find('local Actions = {}',1,true))
    local last=assert(bulkSource:find('function Actions.transfer(',first,true))
    local bulk=assert(loadstring(bulkSource:sub(first,last-1)..'\nreturn Actions','@fixture/BulkActions.lua'))()
    local originalPerform,originalStop=function()end,function()end
    local wrappedPerform,wrappedStop=function()end,function()end
    local action={perform=wrappedPerform,stop=wrappedStop,setOnComplete=function(self,callback)self.onCompleteFunc=callback end}
    local record={id='P4TidyUpMeister',class=ISInventoryTransferAction,fields={},transferBinding={performDelegate=originalPerform,
        performWrapper=wrappedPerform,stopDelegate=originalStop,stopWrapper=wrappedStop,dependencies=s.dependencies()}}
    s.instance(action,record)
    bulk.guardTransfer(action)
    local compatLease,compatDescription=s.compat.transferBinding(false,action)
    local bulkLease,bulkDescription=bulk.transferBinding(action,compatDescription.wrappedStop)
    assert(compatLease and bulkLease and bulkDescription.wrappedStop==action.stop
        and bulkDescription.stop==compatDescription.wrappedStop and compatDescription.stop==originalStop
        and bulkDescription.onComplete==action.onCompleteFunc,'sealed outer Bulk and private Compat ancestry must compose')
    s.freeze()
    assert(compatLease()and bulkLease(),'composed instance leases invoked metadata/gameplay')
    action.stop=function()error('unknown outer stop invoked')end
    assert(not compatLease(),'unknown later stop layer must invalidate the source lease')
end
local function tidyFixture()
    getFilenameOfClosure=function()return 'fixture.lua'end
    local proof=assert(loadfile(root..'/PZSurvivorToolkit/42/media/lua/shared/PZSurvivorToolkit/SourceProof.lua'))()
    PZSurvivorToolkit={}
    local previous=function()error('native merge executed')end
    ISInventoryTransferAction={checkQueueList=previous}
    local oldRequire=require
    require=function(name)
        if name=='PZSurvivorToolkit/SourceProof'then return proof end
        if name=='PZSurvivorToolkit/ActionQueueSettlement'then return {}end
        if name=='Hotbar/ISHotbar'or name=='PZSurvivorToolkit/ActionQueueAcknowledgements'then return true end
        return oldRequire(name)
    end
    local intent=assert(loadfile(root..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueTidyIntent.lua'))()
    return intent,previous,proof
end
do
    local intent,previous=tidyFixture();local calls=0
    local callback=function()error('listener executed while inspecting')end
    local canObserve=function()error('listener guard executed while inspecting')end
    local events={begin=function()error('listener event executed while inspecting')end}
    local factory=function(action,observedCallback,observedGuard,observedEvents)
        calls=calls+1;assert(observedCallback==callback and observedGuard==canObserve and observedEvents==events)
        return function()return true end
    end
    intent.observeTransfers(callback,canObserve,events,factory)
    local action={character={}}
    local replacement=ISInventoryTransferAction.checkQueueList
    assert(intent.queueObserverBinding(previous,replacement,action,function()return false end)==nil and calls==0,
        'untrusted owner factory must not execute')
    local lease=assert(intent.queueObserverBinding(previous,replacement,action,function(value)return value==factory end))
    assert(calls==1 and lease({})and calls==1,'final lease must not re-run owner preparation')
    events.begin=function()end;assert(not lease(),'listener event mutation must invalidate the lease')
    intent.observeTransfers(function()end,function()return false end,{})
    assert(intent.queueObserverBinding(previous,replacement,action,function()return true end)==nil,'unattested listener stays unknown')
end
do
    local intent,previous=tidyFixture();local events={}
    local factory=function()events.begin=function()end;return function()return true end end
    intent.observeTransfers(function()end,function()return false end,events,factory)
    assert(intent.queueObserverBinding(previous,ISInventoryTransferAction.checkQueueList,{character={}},function()return true end)==nil,
        'owner preparation reentry must not replace a previously frozen dispatch field')
end
do
    local intent,previous=tidyFixture()
    local function forbidden()error('old Tidy source guard/helper executed')end
    ISInventoryPaneContextMenu={equipWeapon=forbidden,transferIfNeeded=forbidden,unequipItem=forbidden}
    ISInventoryPane={getActualItems=forbidden};ISInventoryTransferUtil={newInventoryTransferAction=forbidden}
    ISTimedActionQueue={add=forbidden,addAfter=forbidden,addToQueue=forbidden};Events={}
    local wrapper=function()error('UI wrapper checker executed')end
    local prepared=0
    local factory=function(action,valid,approvedWrapper)
        assert(valid==forbidden and approvedWrapper==wrapper);prepared=prepared+1
        return function()return true end
    end
    intent.install(forbidden,wrapper,factory)
    intent.observeTransfers(nil)
    local lease=assert(intent.queueObserverBinding(previous,ISInventoryTransferAction.checkQueueList,{character={}},
        function(candidate)return candidate==factory end))
    assert(lease()and prepared==1,'installed guard needs exact owner preparation without executing the old guard')
    ISInventoryPaneContextMenu.transferIfNeeded=function()end
    assert(not lease(),'one owner with several fixed helper slots must preserve every slot')
end
print('Reviewed transfer sources: BC/P4/TOF dependencies, exact instance ancestry, dormant fridge branches and authenticated Tidy listeners passed.')
-- External BC/P4/TOF behavior is deliberately stubbed here. This receipt covers
-- the project's owner/dependency protocol, not actual external mod coverage.
