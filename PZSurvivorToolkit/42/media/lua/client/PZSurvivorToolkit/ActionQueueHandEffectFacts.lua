-- Opt-in planning facts, never called by tick/hover/admission. A predicate on
-- selected private state is not a complete handler effect or an edit right.
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Recipes=require 'PZSurvivorToolkit/ActionQueueHandEventRecipes'
local HandEvents=require 'PZSurvivorToolkit/ActionQueueHandEvents'
local Toolkit=PZSurvivorToolkit
local Facts={}
Toolkit.ActionQueueHandEffectFacts=Facts
local kind,equal,call,each,array=type,rawequal,pcall,pairs,ipairs
local meta=toolkitLuaMetatableMatches
local native,api=toolkitLuaCaptureFactsMatch,toolkitLuaCaptureFactsApiMatches
local capture,closure,matches=Proof.captureBindings,Proof.closure,Proof.matches
local registryMatch=HandEvents.registeredCallbacksMatch
local archery=HandEvents.archeryTrackingAbsent
local sourceFactory=Recipes.source
local factories={snow=Recipes.snow,neat=Recipes.neat,neatRefresh=Recipes.neatRefresh,
    carts=Recipes.cartsHoldersEmpty,fishing=Recipes.fishing,fishingHandle=Recipes.fishingHandle,fishingValid=Recipes.fishingValid}
local sources,sourceTrusted={},{}
for _,name in array({'snow','neat','carts','fishing'})do sources[name]=sourceFactory(name)end
local observe
local function plain(value)return kind(value)=='table'and kind(meta)=='function'and meta(value,nil)end
local function bootstrap()
    if not plain(_G)or not plain(Toolkit)or not plain(Facts)or not plain(Proof)or not plain(Recipes)or not plain(HandEvents)
        or PZSurvivorToolkit~=Toolkit or Toolkit.ActionQueueHandEffectFacts~=Facts or Toolkit.ActionQueueHandEvents~=HandEvents or Facts.observe~=observe
        or toolkitLuaMetatableMatches~=meta or toolkitLuaCaptureFactsMatch~=native or toolkitLuaCaptureFactsApiMatches~=api
        or kind(native)~='function'or kind(api)~='function'or not api(native)
        or Proof.captureBindings~=capture or Proof.closure~=closure or Proof.matches~=matches
        or Recipes.source~=sourceFactory or HandEvents.registeredCallbacksMatch~=registryMatch
        or HandEvents.archeryTrackingAbsent~=archery then return end
    for name,callback in each(factories)do
        local field=name=='carts'and'cartsHoldersEmpty'or name
        if Recipes[field]~=callback or not closure(callback,'ActionQueueHandEventRecipes.lua')then return end
    end
    return capture({{owner=_G,keys={'PZSurvivorToolkit','toolkitLuaMetatableMatches','toolkitLuaCaptureFactsMatch',
            'toolkitLuaCaptureFactsApiMatches','Fishing','NEQ_State','NEQ_HideEquipped','WPANC','getModFileReader','getGameFilesInput'}},
        {owner=Toolkit,keys={'ActionQueueHandEffectFacts','ActionQueueHandEvents'}},{owner=Facts,keys={'observe'}},
        {owner=Proof,keys={'captureBindings','closure','matches'}},{owner=Recipes,exact=true},
        {owner=HandEvents,keys={'registeredCallbacksMatch','archeryTrackingAbsent'}}})
end
local function empty(value)
    if not plain(value)then return end
    for _ in each(value)do return false end
    return true
end
local function check(callback,recipe)
    local value=native(callback,recipe)
    if kind(value)=='boolean'then return value end
end
local function row(phase,callback,profile)
    return {phase=phase,callback=callback,profile=profile,status='unhandled',reason='source_or_capture_unknown'}
end
local function inspect(actor,snapshot)
    local watch=bootstrap()
    if kind(watch)~='function'or not watch()or registryMatch(snapshot)~=true then return end
    local fishing,neat,hide=Fishing,NEQ_State,NEQ_HideEquipped
    local public={}
    if plain(fishing)then
        public[#public+1]={owner=fishing,keys={'Handler','ManagerInstances'}}
        if plain(fishing.Handler)then public[#public+1]={owner=fishing.Handler,keys={'onEquipPrimary','handleFishing','isFishingValid'}}end
    end
    if plain(neat)then public[#public+1]={owner=neat,keys={'hideEquipped'}}end
    if plain(hide)then public[#public+1]={owner=hide,keys={'refreshFor'}}end
    local publicWatch=#public==0 and function()return true end or capture(public)
    if kind(publicWatch)~='function'then return end
    local selected={}
    local needsArchery=false
    -- Qualify file inputs before reading private facts. Cold file readers may
    -- reenter; no earlier capture value may survive that boundary as a fact.
    for _,phase in array({'primary','secondary'})do
        for _,callback in array(snapshot[phase])do
            local profile
            for name,source in each(sources)do
                if closure(callback,source.filename)then profile=name;break end
            end
            if not profile and closure(callback,'R5_AimState.lua')then profile='archery';needsArchery=true end
            selected[#selected+1]=row(phase,callback,profile or 'unknown')
            if profile and sources[profile]and sourceTrusted[profile]==nil then
                local source=sources[profile]
                sourceTrusted[profile]=matches(source.path,source.adler,source.mod,true)
            end
        end
    end
    if needsArchery then archery(actor)end -- discard the cold source observation
    if not watch()or not publicWatch()or registryMatch(snapshot)~=true then return end
    local partial=false
    local factCache={}
    local archeryQueried,archeryValue=false,nil
    for _,entry in array(selected)do
        local profile,callback=entry.profile,entry.callback
        local values
        local cached=profile~='archery'and factCache[callback]
        if cached then values=cached.facts
        elseif sourceTrusted[profile]then
            if profile=='snow'then
                local value=check(callback,factories.snow())
                if value~=nil then values={swappedEmpty=value}end
            elseif profile=='carts'then
                local value=check(callback,factories.carts())
                if value~=nil then values={holderQueryTableEmpty=value}end
            elseif profile=='neat'and plain(neat)and plain(hide)and kind(neat.hideEquipped)=='boolean'then
                local linked=check(callback,factories.neat(neat,hide))
                local refresh=check(hide.refreshFor,factories.neatRefresh(neat))
                if linked~=nil and refresh~=nil then values={captureBindingsMatch=linked,refreshBindingsMatch=refresh,hideEquipped=neat.hideEquipped}end
            elseif profile=='fishing'and plain(fishing)and plain(fishing.Handler)then
                local handlers=fishing.Handler
                local linked=equal(callback,handlers.onEquipPrimary)
                local callbackShape=check(callback,factories.fishing())
                local handleShape=check(handlers.handleFishing,factories.fishingHandle())
                local validShape=check(handlers.isFishingValid,factories.fishingValid())
                local managers=empty(fishing.ManagerInstances)
                if callbackShape~=nil and handleShape~=nil and validShape~=nil and managers~=nil then
                    values={callbackBindingMatch=linked,callbackSourceMatch=callbackShape,
                        handleSourceMatch=handleShape,validSourceMatch=validShape,managerTableEmpty=managers}
                end
            end
        elseif profile=='archery'then
            -- The existing observer proves shared public callback captures. This
            -- row also has to be that exact exported callback for its phase.
            local owner=WPANC
            local state=plain(owner)and owner.BowState
            local callbackName=entry.phase=='primary'and'onEquipPrimary'or'onEquipSecondary'
            if plain(state)and equal(callback,state[callbackName])then
                if not archeryQueried then archeryValue=archery(actor);archeryQueried=true end
                if kind(archeryValue)=='boolean'then values={trackingAbsent=archeryValue}end
            end
        end
        -- The same private handler often appears in both events. Reuse its
        -- facts only in this callback-free synchronous read, preserving every
        -- registration row and never caching across public observations.
        if not cached and profile~='archery'then factCache[callback]={facts=values}end
        if values then entry.status,entry.reason,entry.facts='observed',nil,values
        else partial=true end
    end
    if not watch()or not publicWatch()or registryMatch(snapshot)~=true then return end
    return {status=partial and'partial'or'observed',version=1,callbacks=selected,
        effectComplete=false,scope='current-source-state-only'}
end
observe=function(...)
    if select('#',...)~=2 then return end
    local ok,value=call(inspect,...)
    if ok then return value end
end
Facts.observe=observe
return Facts
