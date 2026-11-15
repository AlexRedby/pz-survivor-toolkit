-- Composition/lifetime checks with explicit predicate doubles. The native source
-- check separately loads actual prototypes/recipes/registry and the same consumer.
local root=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/'
local function setup()
    local env={PZSurvivorToolkit={}}
    for key,value in pairs(_G)do if key~='PZSurvivorToolkit'then env[key]=value end end
    env._G=env
    env.toolkitLuaMetatableMatches=function(value,expected)return type(value)=='table'and getmetatable(value)==expected end
    local origins={}
    env.getFilenameOfClosure=function(callback)return origins[callback]end
    local proof=assert(setfenv(assert(loadfile(root..'shared/PZSurvivorToolkit/SourceProof.lua')),env))()
    local recipes=assert(setfenv(assert(loadfile(root..'client/PZSurvivorToolkit/ActionQueueHandEventRecipes.lua')),env))()
    for _,value in pairs(recipes)do if type(value)=='function'then origins[value]='ActionQueueHandEventRecipes.lua'end end
    local sourceOK,readerHook=true,nil
    local opens=0
    proof.matches=function(path,checksum,mod,adler)
        assert(type(path)=='string'and type(checksum)=='number'and adler==true)
        opens=opens+1;if readerHook then readerHook()end;return sourceOK
    end
    local calls,readHook=0,nil
    local values={}
    local function handler(filename)
        local callback=function()error('handler executed')end
        origins[callback]=filename;values[callback]=true;return callback
    end
    local snow=handler('ISnow_CharSnow.lua');local neat=handler('NEQ_HideEquipped.lua')
    local carts=handler('HolderRegistry.lua');local fishing=handler('FishingHandler.lua')
    local refresh=handler('NEQ_HideEquipped.lua')
    env.NEQ_State={hideEquipped=false};env.NEQ_HideEquipped={refreshFor=refresh}
    env.Fishing={Handler={onEquipPrimary=fishing,handleFishing=handler('FishingHandler.lua'),isFishingValid=handler('FishingHandler.lua')},ManagerInstances={}}
    local snapshot={primary={snow,neat,carts,fishing},secondary={snow,neat}}
    local registry=true
    local events={registeredCallbacksMatch=function(value)return registry and value==snapshot end,
        archeryTrackingAbsent=function()return true end}
    local native=function(callback,recipe)
        assert(type(recipe)=='table'and #recipe.fingerprint==64)
        calls=calls+1;if readHook then readHook()end;return values[callback]
    end
    env.toolkitLuaCaptureFactsMatch=native;env.toolkitLuaCaptureFactsApiMatches=function(value)return value==native end
    env.PZSurvivorToolkit.ActionQueueHandEvents=events
    env.require=function(path)
        if path=='PZSurvivorToolkit/SourceProof'then return proof end
        if path=='PZSurvivorToolkit/ActionQueueHandEventRecipes'then return recipes end
        assert(path=='PZSurvivorToolkit/ActionQueueHandEvents');return events
    end
    local facts=assert(setfenv(assert(loadfile(root..'client/PZSurvivorToolkit/ActionQueueHandEffectFacts.lua')),env))()
    return {env=env,facts=facts,snapshot=snapshot,values=values,snow=snow,neat=neat,carts=carts,fishing=fishing,
        callback=handler,events=events,recipes=recipes,proof=proof,
        registry=function(value)registry=value end,source=function(value)sourceOK=value end,
        sourceHook=function(value)readerHook=value end,readHook=function(value)readHook=value end,
        counts=function()return calls,opens end}
end
local f=setup();local result=assert(f.facts.observe(false,f.snapshot))
assert(result.status=='observed'and result.effectComplete==false and result.edit==nil and #result.callbacks==6)
assert(result.callbacks[1].facts.swappedEmpty==true and result.callbacks[3].facts.holderQueryTableEmpty==true
    and result.callbacks[4].facts.managerTableEmpty==true)
local calls,opens=f.counts();assert(calls==7 and opens==4,'duplicate handlers repeated source/predicate work within one observation')
f.values[f.snow]=false;f.env.NEQ_State.hideEquipped=true;f.env.Fishing.ManagerInstances[0]={}
result=assert(f.facts.observe(false,f.snapshot))
assert(result.callbacks[1].facts.swappedEmpty==false and result.callbacks[2].facts.hideEquipped==true
    and result.callbacks[4].facts.managerTableEmpty==false,'fresh nonempty/private/public state became an absent fact')
assert(result.effectComplete==false,'state predicates became an effect certificate')
f.values[f.snow]=nil
result=assert(f.facts.observe(false,f.snapshot));assert(result.status=='partial'and result.callbacks[1].status=='unhandled')
f.snapshot.primary[5]=f.callback('Foreign.lua')
result=assert(f.facts.observe(false,f.snapshot));assert(result.status=='partial'and result.callbacks[5].profile=='unknown')
assert(f.facts.observe(false)==nil and f.facts.observe(false,f.snapshot,true)==nil)
local function rejected(mutate)
    local case=setup();mutate(case)
    assert(case.facts.observe(false,case.snapshot)==nil,'changed source/registry binding produced planning facts')
end
rejected(function(case)case.registry(false)end)
rejected(function(case)case.env.toolkitLuaCaptureFactsMatch=function()return true end end)
rejected(function(case)case.events.registeredCallbacksMatch=function()return true end end)
rejected(function(case)case.recipes.snow=function()return {}end end)
rejected(function(case)case.sourceHook(function()case.env.NEQ_State={}end)end)
rejected(function(case)case.readHook(function()case.env.Fishing={}end)end)
do
    local case=setup();case.source(false)
    local value=assert(case.facts.observe(false,case.snapshot))
    assert(value.status=='partial'and value.callbacks[1].status=='unhandled')
end
-- All cold readers finish before private predicates, so rebinds in qualification
-- cannot be reported using a pre-reader state observation.
do
    local case=setup();case.sourceHook(function()case.values[case.snow]=false end)
    assert(case.facts.observe(false,case.snapshot).callbacks[1].facts.swappedEmpty==false)
end
-- One current shared archery capture can describe both exported callbacks,
-- but callback/phase binding still belongs to each separate registration row.
do
    local case=setup();local p=case.callback('R5_AimState.lua');local s=case.callback('R5_AimState.lua')
    case.env.WPANC={BowState={onEquipPrimary=p,onEquipSecondary=s}}
    case.snapshot.primary={p};case.snapshot.secondary={s}
    local value=assert(case.facts.observe({},case.snapshot))
    assert(value.status=='observed'and value.callbacks[1].facts.trackingAbsent==true
        and value.callbacks[2].facts.trackingAbsent==true and value.effectComplete==false)
end
print('Hand-effect planning facts: source qualification, current-state predicates, partial unknowns, decision-local reuse and no authority passed.')
