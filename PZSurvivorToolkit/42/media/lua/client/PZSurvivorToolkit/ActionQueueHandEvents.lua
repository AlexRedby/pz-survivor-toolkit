-- Read-only hand-event inputs. These facts do not prove the complete event
-- registry, native Equip effects, execution freshness or any queue edit right.
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Toolkit=PZSurvivorToolkit
local Events={}
Toolkit.ActionQueueHandEvents=Events
local kind,equal,call=type,rawequal,pcall
local meta=toolkitLuaMetatableMatches
local native=toolkitArcheryTrackingAbsent
local nativeAPI=toolkitArcheryTrackingApiMatches
local own,capture,closure,matches=Proof.own,Proof.captureBindings,Proof.closure,Proof.matches
local sourceTrusted
local observe
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
return Events
