-- Lua boundary tests with an explicit native-registration double. Real Java
-- registry/add/remove/reset and actual private callbacks are covered by the JVM check.
local root=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/'
local function setup()
    local env={PZSurvivorToolkit={}}
    for key,value in pairs(_G)do if key~='PZSurvivorToolkit'then env[key]=value end end
    env._G=env
    env.toolkitLuaMetatableMatches=function(value,expected)return type(value)=='table'and getmetatable(value)==expected end
    local proof=assert(setfenv(assert(loadfile(root..'shared/PZSurvivorToolkit/SourceProof.lua')),env))()
    local a,b=function()error('private callback invoked')end,function()error('private callback invoked')end
    local primary,secondary={a,b},{b};local available=true;local during
    local function copy(values)local result={};for i,value in ipairs(values)do result[i]=value end;return result end
    local function matches(p,s)
        if not available then return nil end
        if during then during()end
        if #p~=#primary or #s~=#secondary then return false end
        for i,value in ipairs(p)do if value~=primary[i]then return false end end
        for i,value in ipairs(s)do if value~=secondary[i]then return false end end
        return true
    end
    local function snapshot()
        if not available then return nil end
        if during then during()end
        return {primary=copy(primary),secondary=copy(secondary)}
    end
    env.toolkitEquipEventCallbacks=snapshot
    env.toolkitEquipEventCallbacksMatch=matches
    env.toolkitEquipEventRegistryApiMatches=function(value)return value==snapshot or value==matches end
    env.require=function(path)assert(path=='PZSurvivorToolkit/SourceProof');return proof end
    local api=assert(setfenv(assert(loadfile(root..'client/PZSurvivorToolkit/ActionQueueHandEvents.lua')),env))()
    return {api=api,env=env,proof=proof,primary=primary,secondary=secondary,
        available=function(value)available=value end,during=function(value)during=value end}
end
local f=setup();local snapshot=assert(f.api.registeredCallbacks())
assert(f.api.registeredCallbacksMatch(snapshot)==true)
assert(snapshot.primary~=f.primary and snapshot.secondary~=f.secondary,'snapshot leaked registration storage')
snapshot.primary[1]=nil
assert(f.primary[1]~=nil and f.api.registeredCallbacksMatch(snapshot)==nil,'sparse caller data passed revalidation')
snapshot=assert(f.api.registeredCallbacks());snapshot.primary[1],snapshot.primary[2]=snapshot.primary[2],snapshot.primary[1]
assert(f.api.registeredCallbacksMatch(snapshot)==false,'reordering lost exact identity/order')
snapshot=assert(f.api.registeredCallbacks());f.primary[3]=f.primary[1]
assert(f.api.registeredCallbacksMatch(snapshot)==false,'new duplicate callback went unnoticed')
f.primary[3]=nil;assert(f.api.registeredCallbacksMatch(snapshot)==true)
f.available(false);assert(f.api.registeredCallbacks()==nil and f.api.registeredCallbacksMatch(snapshot)==nil)
f.available(true)
assert(f.api.registeredCallbacks(true)==nil and f.api.registeredCallbacksMatch()==nil
    and f.api.registeredCallbacksMatch(snapshot,true)==nil)
for _,value in ipairs({{}, {primary={},secondary={},extra=true}, {primary=setmetatable({},{__index=function()error('index invoked')end}),secondary={}},
    {primary={[1]=false},secondary={}}, {primary={[2]=function()end},secondary={}}})do
    assert(f.api.registeredCallbacksMatch(value)==nil,'malformed registry data produced a boolean fact')
end
local function rejected(mutate)
    local case=setup();local saved=assert(case.api.registeredCallbacks());mutate(case)
    assert(case.api.registeredCallbacks()==nil and case.api.registeredCallbacksMatch(saved)==nil,
        'a replaced or reentrant binding produced current-registration evidence')
end
rejected(function(case)case.env.toolkitEquipEventCallbacks=function()return {primary={},secondary={}}end end)
rejected(function(case)case.env.toolkitEquipEventCallbacksMatch=function()return true end end)
rejected(function(case)case.env.toolkitEquipEventRegistryApiMatches=function()return true end end)
rejected(function(case)case.env.PZSurvivorToolkit.ActionQueueHandEvents={}end)
rejected(function(case)case.proof.captureBindings=function()return function()return true end end end)
rejected(function(case)case.during(function()case.env.toolkitEquipEventCallbacksMatch=function()return true end end)end)
-- Mutation of supplied data while metadata guards execute cannot lend a fresh witness.
do
    local case=setup();local value=assert(case.api.registeredCallbacks())
    case.during(function()value.secondary[1]=nil end)
    assert(case.api.registeredCallbacksMatch(value)==nil)
end
print('Equip registry Lua boundary: copied private callbacks, exact ordered revalidation, malformed inputs and stale/reentrant bindings passed; no effect or edit authority.')
