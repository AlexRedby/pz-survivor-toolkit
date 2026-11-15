local Proof = require "PZSurvivorToolkit/SourceProof"
local Transfers = {}
PZSurvivorToolkit.ActionQueueTransfers = Transfers
local original,observer
local listeners={}
local registry={revision=0}
local capture=Proof and Proof.captureBindings
local valueType,valueMeta,valueRaw,valuePairs,valueEach,valueEqual=type,getmetatable,rawget,pairs,ipairs,rawequal
local globals,toolkit,filename=_G,PZSurvivorToolkit,getFilenameOfClosure
local observerFactory
local function own(owner,key)
    if valueType(owner)~='table'then return nil end
    if valueMeta(owner)==nil then return valueRaw(owner,key)end
    local count=0
    for name,value in valuePairs(owner)do
        count=count+1
        if count>128 then return nil end
        if valueEqual(name,key)then return value end
    end
end
local function pack(...)return {n=select('#',...),...}end
local function registerObserver()
    local sourceAdapters=toolkit.ActionQueueItemEditAdapters
    if sourceAdapters and type(sourceAdapters.registerSourceFactory)=='function'then
        sourceAdapters.registerSourceFactory(Transfers,'queueObserverBinding',observerFactory)
    end
end
-- Failures quarantine observations only. Native effects and their return values
-- always complete normally; a failed observer can never make them replay.
function Transfers.dispatch(event,action,...)
    local observed=false
    for _,listener in ipairs(listeners)do
        local callback=listener.events and listener.events[event]
        if not listener.failed and type(callback)=='function'then
            local ok,result=pcall(callback,action,...)
            if not ok then listener.failed=true
            elseif result==true then observed=true end
        end
    end
    return observed
end
function Transfers.observeTransfers(onMerged,canObserve,events,sourceFactory)
    registerObserver()
    if type(onMerged)=='function'then
        local present=false
        for _,listener in ipairs(listeners)do if listener.callback==onMerged then present=true;break end end
        if not present then
            listeners[#listeners+1]={callback=onMerged,canObserve=canObserve,events=events,sourceFactory=sourceFactory}
            registry.revision=registry.revision+1
        end
    end
    if observer or type(ISInventoryTransferAction.checkQueueList)~='function'then return end
    original=ISInventoryTransferAction.checkQueueList
    observer=function(action,...)
        local observation=false
        for _,listener in ipairs(listeners)do
            if not listener.failed and type(listener.canObserve)=='function'then
                local ok,accepted=pcall(listener.canObserve,action)
                if not ok then listener.failed=true
                elseif accepted==true then observation=true;break end
            end
        end
        if not observation then return original(action,...)end
        -- Keep each owner's transient pre-merge context only for its own paired
        -- callback. Native merge may wipe child actions before returning.
        local pending={}
        for _,listener in ipairs(listeners)do
            if not listener.failed then
                local context
                local merging=listener.events and listener.events.merging
                if type(merging)=='function'then
                    local ok,result=pcall(merging,action)
                    if ok then context=result else listener.failed=true end
                end
                if not listener.failed then pending[#pending+1]={listener=listener,context=context}end
            end
        end
        local result=pack(original(action,...))
        for _,entry in ipairs(pending)do
            local listener=entry.listener
            if not listener.failed then listener.failed=not pcall(listener.callback,action,entry.context)end
        end
        return unpack(result,1,result.n)
    end
    ISInventoryTransferAction.checkQueueList=observer
end
function Transfers.isQueueObserver(previous,replacement)
    return previous==original and replacement==observer and replacement~=nil
end
local dispatch,observe,isObserver=Transfers.dispatch,Transfers.observeTransfers,Transfers.isQueueObserver
-- Freeze every listener and event reference before consulting any source owner.
-- Authenticate all factories first, then compose their query-local pure leases.
observerFactory=function(previous,replacement,action,trustedFactory)
    if valueType(action)~='table'or valueType(trustedFactory)~='function'
        or not valueEqual(previous,original)or not valueEqual(replacement,observer)or replacement==nil
        or valueType(capture)~='function'or valueMeta(globals)~=nil or valueMeta(toolkit)~=nil
        or valueMeta(Transfers)~=nil or valueMeta(Proof)~=nil
        or not valueEqual(own(globals,'PZSurvivorToolkit'),toolkit)
        or not valueEqual(own(globals,'getFilenameOfClosure'),filename)
        or not valueEqual(own(toolkit,'ActionQueueTransfers'),Transfers)
        or not valueEqual(own(Transfers,'queueObserverBinding'),observerFactory)
        or not valueEqual(own(Transfers,'dispatch'),dispatch)
        or not valueEqual(own(Transfers,'observeTransfers'),observe)
        or not valueEqual(own(Transfers,'isQueueObserver'),isObserver)
        or not valueEqual(own(Proof,'captureBindings'),capture)then return nil end
    local specifications={{owner=globals,keys={'PZSurvivorToolkit','getFilenameOfClosure'}},
        {owner=toolkit,keys={'ActionQueueTransfers'}},{owner=Transfers,keys={'queueObserverBinding','observeTransfers','dispatch','isQueueObserver'}},
        {owner=Proof,keys={'captureBindings'}},{owner=registry,keys={'revision'}},{owner=listeners,exact=true}}
    local pending={}
    for _,listener in valueEach(listeners)do
        if valueType(listener.sourceFactory)~='function'then return nil end
        specifications[#specifications+1]={owner=listener,exact=true}
        if listener.events then specifications[#specifications+1]={owner=listener.events,exact=true}end
        pending[#pending+1]={factory=listener.sourceFactory,callback=listener.callback,
            canObserve=listener.canObserve,events=listener.events}
    end
    local watch=capture(specifications)
    if not watch then return nil end
    for _,entry in valueEach(pending)do if not trustedFactory(entry.factory)then return nil end end
    if not watch()then return nil end
    local leases={}
    for _,entry in valueEach(pending)do
        local lease=entry.factory(action,entry.callback,entry.canObserve,entry.events,trustedFactory)
        if valueType(lease)~='function'or not watch()then return nil end
        leases[#leases+1]=lease
    end
    return function(facts)
        if not watch()then return false end
        for _,lease in valueEach(leases)do if not lease(facts)then return false end end
        return watch()
    end
end
Transfers.queueObserverBinding=observerFactory
registerObserver()
return Transfers
