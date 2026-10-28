-- Small execution capabilities describe reviewed failure handling, never a
-- promise that future capacity will fit. Native validation owns admission.
require 'TimedActions/ISInventoryTransferAction'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local closure=Proof and Proof.closure
local Toolkit=PZSurvivorToolkit
local Execution={}
Toolkit.ActionQueueExecution=Execution
local transfer=ISInventoryTransferAction
local episodes={}
local activeActors={}
local descriptorMarker={}
local dependencies
local executionMatches
local names={'returnExecutionSupported','prepareReturnExecution','rejectReturnExecution',
    'resetReturnFailures','authorizeReturnRetention','blockedReturnInfo','blockedReturns','keepReturn'}
local function finite(value)return type(value)=='number'and value==value and value>-math.huge and value<math.huge end
local function plain(value)return type(value)=='table'and getmetatable(value)==nil end
local function returnShape(action)
    return type(action)=='table'and getmetatable(action)==transfer and action.Type=='ISInventoryTransferAction'
        and action.allowMissingItems==true
end
local function owned(callback,file)return type(callback)=='function'and type(closure)=='function'and closure(callback,file)end
local function accepted(callback,...)
    local ok,result=pcall(callback,...)
    return ok and result==true
end
local function ready()
    if PZSurvivorToolkit~=Toolkit or Toolkit.ActionQueueExecution~=Execution or ISInventoryTransferAction~=transfer
        or not Proof or Proof.closure~=closure or executionMatches and Execution.matches~=executionMatches then return false end
    local policy,settlement,bulk,settings=Toolkit.ActionQueuePolicy,Toolkit.ActionQueueSettlement,Toolkit.BulkActions,Toolkit.Settings
    if not dependencies then
        if not policy or not settlement or not bulk or not settings
            or not owned(policy.matchesNative,'ActionQueuePolicy.lua')or not owned(policy.isOrdinaryTransfer,'ActionQueuePolicy.lua')
            or not owned(bulk.guardTransfer,'BulkActions.lua')or not owned(bulk.isGuardedTransfer,'BulkActions.lua')
            or type(settings.actionQueue)~='function'then return false end
        local methods={}
        for _,name in ipairs(names)do
            if not owned(settlement[name],'ActionQueueSettlement.lua')then return false end
            methods[name]=settlement[name]
        end
        dependencies={policy=policy,settlement=settlement,bulk=bulk,settings=settings,methods=methods,
            matchesNative=policy.matchesNative,ordinary=policy.isOrdinaryTransfer,
            guard=bulk.guardTransfer,guarded=bulk.isGuardedTransfer,enabled=settings.actionQueue}
    end
    local saved=dependencies
    if policy~=saved.policy or settlement~=saved.settlement or bulk~=saved.bulk or settings~=saved.settings
        or policy.matchesNative~=saved.matchesNative or policy.isOrdinaryTransfer~=saved.ordinary
        or bulk.guardTransfer~=saved.guard or bulk.isGuardedTransfer~=saved.guarded or settings.actionQueue~=saved.enabled then return false end
    for _,name in ipairs(names)do if settlement[name]~=saved.methods[name]then return false end end
    return true
end
local function enabled()return ready()and dependencies.enabled()==true end
local function localActor(actor)
    return instanceof(actor,'IsoPlayer')and actor:isLocalPlayer()and getSpecificPlayer(actor:getPlayerNum())==actor
        and not actor:isDead()and not actor:isAsleep()
end
local function live(queue,actor)
    return localActor(actor)and queue and queue.character==actor and ISTimedActionQueue.queues[actor]==queue
end
local function idleEdit(queue,actor)
    return live(queue,actor)and not queue.toolkitCancel and not queue.toolkitGroupCancel and not queue.toolkitResume
        and not queue.toolkitOutcomeWait and not queue.toolkitStopIntent
        and not actor:isPlayerMoving()and not actor:pressedMovement(false)
end
local function itemMatches(item,id,fullType)
    return instanceof(item,'InventoryItem')and item:getID()==id and item:getFullType()==fullType
end
local function method(value,name)return value and type(value[name])=='function'end
local function unfilteredEndpoint(container)
    local seen={}
    -- Only endpoint ancestry is inspected. Native admission still owns target
    -- existence, capacity and acceptance; never execute a custom filter here.
    for _=1,64 do
        if not instanceof(container,'ItemContainer')or seen[container]then return false end
        seen[container]=true
        for _,name in ipairs({'getType','getAcceptItemFunction','getOnlyAcceptCategory','getContainingItem','getParent'})do
            if not method(container,name)then return false end
        end
        local kind=container:getType()
        if type(kind)~='string'or kind=='floor'or kind=='proximityInv'or kind=='twistInv_corpses'
            or container:getAcceptItemFunction()~=nil or container:getOnlyAcceptCategory()~=nil then return false end
        local parent=container:getParent()
        if (instanceof(parent,'IsoGameCharacter')or instanceof(parent,'IsoPlayer'))
            and (not method(parent,'getInventory')or parent:getInventory()~=container)then return false end
        local owner=container:getContainingItem()
        if owner==nil then return true end
        if not instanceof(owner,'InventoryContainer')or not method(owner,'getInventory')
            or owner:getInventory()~=container or not method(owner,'getContainer')then return false end
        container=owner:getContainer()
    end
    return false
end
local function facts(action,episode)
    return episode and action.character==episode.actor and action.toolkitQueueOperation==episode.token
        and action.srcContainer==episode.source and action.destContainer==episode.destination
        and action.srcContainer==episode.actor:getInventory()
        and (episode.queue.toolkitOperationGeneration or 0)==episode.generation
        and itemMatches(action.item,episode.id,episode.fullType)
end
local function singleton(action)
    local groups=action.queueList
    if not plain(groups)then return false end
    local count=0
    for key in pairs(groups)do if key~=1 then return false end;count=count+1 end
    if count==0 then
        local episode=episodes[action]
        return episode and episode.native and action.action==episode.native and facts(action,episode)or false
    end
    local group=groups[1]
    if not plain(group)or not plain(group.items)then return false end
    count=0
    for key in pairs(group.items)do if key~=1 then return false end;count=count+1 end
    return count==1 and itemMatches(group.items[1],action.item:getID(),action.item:getFullType())
end
local function guarded(action)
    local guard=action.toolkitTransferGuard
    return type(guard)=='table'and dependencies.guarded(action,guard.original)==true
        and action.onCompleteFunc~=nil and action.onCompleteFunc==action.toolkitQueueSafeOnComplete
        and owned(action.onCompleteFunc,'BulkActions.lua')
end
local function retire(action)
    local episode=episodes[action]
    if not episode then return end
    episodes[action]=nil
    local active=activeActors[episode.actor]
    if active and active.action==action and active.episode==episode then activeActors[episode.actor]=nil end
end
local function matches(action,reference)
    if reference~=nil and not plain(reference)then return false end
    if not returnShape(action)or not ready()or not localActor(action.character)
        or action.srcContainer~=action.character:getInventory()or action.destContainer==action.srcContainer
        or not instanceof(action.srcContainer,'ItemContainer')or not instanceof(action.destContainer,'ItemContainer')
        or not unfilteredEndpoint(action.srcContainer)or not unfilteredEndpoint(action.destContainer)
        or not instanceof(action.item,'InventoryItem')or instanceof(action.item,'InventoryContainer')
        or instanceof(action.item,'AnimalInventoryItem')or action.onStartFunc or action.onCancelFunc
        or action.onFailFunc or action.additionalTest or action.retriggerLastAction or action._isAddingActions then return false end
    local item=action.item
    local id,fullType=item:getID(),item:getFullType()
    if not finite(id)or id%1~=0 or type(fullType)~='string'or fullType==''
        or item:getType()=='CandleLit'or item:getType()=='Lantern_HurricaneLit'
        or reference and (reference.id~=id or reference.fullType~=fullType)then return false end
    if action.onCompleteFunc and not guarded(action)then return false end
    return singleton(action)and dependencies.matchesNative(action)==true and dependencies.ordinary(action)==true
end
function Execution.matches(action,reference)
    local ok,result=pcall(matches,action,reference)
    return ok and result==true
end
executionMatches=Execution.matches
function Execution.inspect(action)
    if not returnShape(action)or not enabled()or not Execution.matches(action)or not guarded(action)
        or not accepted(dependencies.methods.returnExecutionSupported,action,Execution.matches)then return end
    local actor=action.character
    local queue=ISTimedActionQueue.queues[actor]
    if not live(queue,actor)then return end
    local captured={queue=queue,list=queue.queue,actor=actor,generation=queue.toolkitOperationGeneration or 0,
        token=action.toolkitQueueOperation,source=action.srcContainer,destination=action.destContainer,
        id=action.item:getID(),fullType=action.item:getFullType(),native=action.action,
        stop=action.stop,complete=action.onCompleteFunc,guard=action.toolkitTransferGuard}
    local descriptor={version=1,admission='native-live',outcome='exact-item',failure='retain-return',atomic='single'}
    descriptor[descriptorMarker]=function(value,current)
        return rawequal(value,descriptor)and rawequal(current,action)and facts(current,captured)
            and live(captured.queue,captured.actor)and captured.queue.queue==captured.list
            and current.action==captured.native and current.stop==captured.stop
            and current.onCompleteFunc==captured.complete and current.toolkitTransferGuard==captured.guard
    end
    return descriptor
end
function Execution.capacityDeferred(action,descriptor)
    if not returnShape(action)or not enabled()or not plain(descriptor)
        or descriptor.version~=1 or descriptor.admission~='native-live'or descriptor.outcome~='exact-item'
        or descriptor.failure~='retain-return'or descriptor.atomic~='single'then return false end
    local seal=descriptor[descriptorMarker]
    return owned(seal,'ActionQueueExecution.lua')and accepted(seal,descriptor,action)
        and Execution.matches(action)and guarded(action)
        and accepted(dependencies.methods.returnExecutionSupported,action,Execution.matches)or false
end
function Execution.enqueued(action)
    if not returnShape(action)or not enabled()or not Execution.matches(action)then return false end
    local actor=action.character
    if not live(ISTimedActionQueue.queues[actor],actor)then return false end
    local ok=pcall(dependencies.guard,action)
    if not ok then return false end
    return Execution.matches(action)and guarded(action)or false
end
function Execution.admitEditMember(action)
    return enabled()and Execution.matches(action)and guarded(action)
        and accepted(dependencies.methods.authorizeReturnRetention,action,Execution.matches)or false
end
function Execution.begin(action)
    if not returnShape(action)or episodes[action]or not enabled()or not Execution.matches(action)or not guarded(action)then return false end
    local actor=action.character
    local queue=ISTimedActionQueue.queues[actor]
    if not live(queue,actor)or queue.current~=action or queue.queue[1]~=action
        or not accepted(dependencies.methods.prepareReturnExecution,action,Execution.matches)then return false end
    local episode={queue=queue,actor=actor,generation=queue.toolkitOperationGeneration or 0,
        token=action.toolkitQueueOperation,source=action.srcContainer,destination=action.destContainer,
        id=action.item:getID(),fullType=action.item:getFullType()}
    -- Queue replacement can orphan a native episode without invoking reset.
    -- Retire only our old capability; its native work and receipts remain owned
    -- by their original executor. One actor never retains several episodes.
    local previous=activeActors[actor]
    if previous then retire(previous.action)end
    episodes[action]=episode
    activeActors[actor]={action=action,episode=episode}
    return true
end
function Execution.bind(action)
    local episode=episodes[action]
    if not episode then return false end
    if not ready()or not facts(action,episode)or not live(episode.queue,episode.actor)
        or episode.queue.current~=action or episode.queue.queue[1]~=action or not action.action
        or not Execution.matches(action)or not guarded(action)then return false end
    if episode.native then return episode.native==action.action end
    episode.native=action.action
    return true
end
local function current(action,queue)
    local episode=episodes[action]
    if not episode then return end
    return ready()and facts(action,episode)and episode.queue==queue and episode.native
        and action.action==episode.native and idleEdit(queue,episode.actor)
        and queue.current==action and queue.queue[1]==action
        and Execution.matches(action)and guarded(action)and episode or nil
end
function Execution.beforeStop(action)
    local episode=current(action,action and ISTimedActionQueue.queues[action.character])
    if not episode or not isClient()then return false end
    episode.preserve=nil
    local transaction=action.transactionId
    if not finite(transaction)or transaction==0 or transaction%1~=0
        or not accepted(dependencies.methods.rejectReturnExecution,action,'server',Execution.matches)then return false end
    episode.preserve={native=episode.native,transaction=transaction}
    return true
end
function Execution.preserveStop(action)
    local episode=current(action,action and ISTimedActionQueue.queues[action.character])
    local preserve=episode and episode.preserve
    return preserve and preserve.native==action.action
        and (action.transactionId==0 or action.transactionId==preserve.transaction)and true or false
end
function Execution.skipUnstarted(queue,action)
    local episode=current(action,queue)
    if not episode or action.started or action.transactionId~=0 or episode.native:isStarted()
        or episode.actor:getCharacterActions():contains(episode.native)then return false end
    return accepted(dependencies.methods.rejectReturnExecution,action,'admission',Execution.matches)
end
function Execution.completionState(queue,action)
    local episode=current(action,queue)
    if not episode or isClient()then return end
    -- The common lifecycle calls this only after native perform/complete and
    -- Java removal. The observer owns exact item effect/rejection facts.
    if episode.actor:getCharacterActions():contains(episode.native)then return end
    accepted(dependencies.methods.rejectReturnExecution,action,'unmoved',Execution.matches)
end
function Execution.completed(action)
    local episode=episodes[action]
    if not episode or action.action~=episode.native or not episode.native
        or episode.actor:getCharacterActions():contains(episode.native)then return false end
    retire(action)
    return true
end
function Execution.reset(queue)
    local active=queue and activeActors[queue.character]
    if active and active.episode.queue==queue then retire(active.action)end
    if ready()then pcall(dependencies.methods.resetReturnFailures,queue)end
end
function Execution.blockedReturnInfo(character)
    if ready()and localActor(character)then return dependencies.methods.blockedReturnInfo(character)end
end
function Execution.blockedReturns(character)
    if ready()and localActor(character)then return dependencies.methods.blockedReturns(character)end
    return {}
end
function Execution.keepReturn(character,id)
    if ready()and localActor(character)then return dependencies.methods.keepReturn(character,id)end
    return false,'unavailable'
end
if Events and Events.OnGameStart then
    Events.OnGameStart.Add(function()episodes,activeActors={},{}end)
end
if Events and Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(function(actor)
        local active=activeActors[actor]
        if active then retire(active.action)end
    end)
end
return Execution
