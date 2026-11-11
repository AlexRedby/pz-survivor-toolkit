-- Read-only hand-event inputs. Registry observations describe current callbacks
-- only: no closure effects, queued dispatch, execution freshness or edit rights.
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Toolkit=PZSurvivorToolkit
local Events={}
Toolkit.ActionQueueHandEvents=Events
local kind,equal,call=type,rawequal,pcall
local meta=toolkitLuaMetatableMatches
local native=toolkitArcheryTrackingAbsent
local nativeAPI=toolkitArcheryTrackingApiMatches
local snapshotNative=toolkitEquipEventCallbacks
local matchNative=toolkitEquipEventCallbacksMatch
local registryAPI=toolkitEquipEventRegistryApiMatches
local own,capture,closure,matches=Proof.own,Proof.captureBindings,Proof.closure,Proof.matches
local sourceTrusted
local observe,registered,revalidate
local function plain(value)return kind(value)=='table'and kind(meta)=='function'and meta(value,nil)end
local function observeTracking(actor)
    if not plain(Toolkit)or not plain(Events)or not plain(Proof)
        or not equal(PZSurvivorToolkit,Toolkit)or not equal(Toolkit.ActionQueueHandEvents,Events)
        or not equal(Events.archeryTrackingAbsent,observe)
        or not equal(toolkitLuaMetatableMatches,meta)
        or not equal(toolkitArcheryTrackingAbsent,native)or not equal(toolkitArcheryTrackingApiMatches,nativeAPI)
        or kind(native)~='function'or kind(nativeAPI)~='function'or not nativeAPI(native)
        or Proof.own~=own or Proof.captureBindings~=capture or Proof.closure~=closure or Proof.matches~=matches then return end
    local owner=WPANC
    if not plain(owner)then return end
    local state=own(owner,'BowState')
    if not plain(state)then return end
    local handlers=own(state,'EventHandlers')
    if not plain(handlers)then return end
    local primary,secondary,updated=own(state,'onEquipPrimary'),own(state,'onEquipSecondary'),own(state,'markUpdated')
    if own(handlers,'onEquipPrimary')~=primary or own(handlers,'onEquipSecondary')~=secondary
        or not closure(primary,'R5_AimState.lua')or not closure(secondary,'R5_AimState.lua')
        or not closure(updated,'R5_AimState.lua')then return end
    local watch=capture({{owner=_G,keys={'WPANC','toolkitLuaMetatableMatches','toolkitArcheryTrackingAbsent','toolkitArcheryTrackingApiMatches'}},
        {owner=Toolkit,keys={'ActionQueueHandEvents'}},{owner=Events,keys={'archeryTrackingAbsent'}},
        {owner=Proof,keys={'own','captureBindings','closure','matches'}},
        {owner=owner,keys={'BowState'}},{owner=state,keys={'onEquipPrimary','onEquipSecondary','markUpdated','EventHandlers'}},
        {owner=handlers,keys={'onEquipPrimary','onEquipSecondary'}}})
    if kind(watch)~='function'or not watch()then return end
    if sourceTrusted==nil then
        sourceTrusted=matches('media/lua/shared/R5_AimState.lua',2769489859,'WildernessProgressionArcheryNexusCompanion',true)
    end
    if not sourceTrusted or not watch()then return end
    -- The bridge checks the loaded prototypes/shared capture and reads its
    -- CURRENT table entry. A reset/rebind never reuses an old negative fact.
    local value=native(actor,primary,secondary,updated)
    if kind(value)=='boolean'and watch()then return value end
end
observe=function(...)
    if select('#',...)~=1 then return end
    local ok,value=call(observeTracking,...)
    if ok then return value end
end
Events.archeryTrackingAbsent=observe

local function registryBindings()
    if not plain(Toolkit)or not plain(Events)or not plain(Proof)
        or not equal(PZSurvivorToolkit,Toolkit)or not equal(Toolkit.ActionQueueHandEvents,Events)
        or Events.registeredCallbacks~=registered or Events.registeredCallbacksMatch~=revalidate
        or not equal(toolkitLuaMetatableMatches,meta)
        or not equal(toolkitEquipEventCallbacks,snapshotNative)or not equal(toolkitEquipEventCallbacksMatch,matchNative)
        or not equal(toolkitEquipEventRegistryApiMatches,registryAPI)
        or kind(snapshotNative)~='function'or kind(matchNative)~='function'or kind(registryAPI)~='function'
        or not registryAPI(snapshotNative)or not registryAPI(matchNative)
        or Proof.captureBindings~=capture then return end
    return capture({{owner=_G,keys={'toolkitLuaMetatableMatches','toolkitEquipEventCallbacks',
            'toolkitEquipEventCallbacksMatch','toolkitEquipEventRegistryApiMatches'}},
        {owner=Toolkit,keys={'ActionQueueHandEvents'}},
        {owner=Events,keys={'registeredCallbacks','registeredCallbacksMatch'}},
        {owner=Proof,keys={'captureBindings'}}})
end
local function list(value)
    if not plain(value)then return false end
    local count,maximum=0,0
    for key,callback in pairs(value)do
        if kind(key)~='number'or key%1~=0 or key<1 or kind(callback)~='function'then return false end
        count=count+1;if key>maximum then maximum=key end
    end
    return count==maximum
end
local function snapshotShape(value)
    if not plain(value)or not list(value.primary)or not list(value.secondary)then return false end
    for key in pairs(value)do if key~='primary'and key~='secondary'then return false end end
    return true
end
local function currentSnapshot()
    local watch=registryBindings()
    if kind(watch)~='function'or not watch()then return end
    local value=snapshotNative()
    if snapshotShape(value)and watch()and matchNative(value.primary,value.secondary)==true and watch()then return value end
end
registered=function(...)
    if select('#',...)~=0 then return end
    local ok,value=call(currentSnapshot)
    if ok then return value end
end
local function sameSnapshot(value)
    if not snapshotShape(value)then return end
    local watch=registryBindings()
    -- Native matching is read-only and cannot reenter Lua. Retain the caller's
    -- exact array contents across the metadata/API guards as well.
    local input=capture({{owner=value,exact=true},{owner=value.primary,exact=true},{owner=value.secondary,exact=true}})
    if kind(watch)~='function'or kind(input)~='function'or not watch()or not input()then return end
    local matched=matchNative(value.primary,value.secondary)
    if kind(matched)=='boolean'and watch()and input()then return matched end
end
revalidate=function(...)
    if select('#',...)~=1 then return end
    local ok,value=call(sameSnapshot,...)
    if ok then return value end
end
Events.registeredCallbacks,Events.registeredCallbacksMatch=registered,revalidate
return Events
