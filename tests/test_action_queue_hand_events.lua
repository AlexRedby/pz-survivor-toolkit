-- Lua binding/observation contract only. The JVM check separately exercises the
-- native bridge and actual selected companion source; these callbacks are doubles.
local root=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/'
local function setup()
    local origin={}
    local env={PZSurvivorToolkit={}}
    for key,value in pairs(_G)do if key~='PZSurvivorToolkit'then env[key]=value end end
    env._G=env
    env.toolkitLuaMetatableMatches=function(value,expected)
        return type(value)=='table'and getmetatable(value)==expected
    end
    env.getFilenameOfClosure=function(callback)return origin[callback]end
    local proof=assert(setfenv(assert(loadfile(root..'shared/PZSurvivorToolkit/SourceProof.lua')),env))()
    local sourceOK,sourceReads,observations,nativeError=true,0,0,false
    proof.matches=function(path,checksum,mod,adler)
        assert(path=='media/lua/shared/R5_AimState.lua'and checksum==2769489859
            and mod=='WildernessProgressionArcheryNexusCompanion'and adler==true)
        sourceReads=sourceReads+1;return sourceOK
    end
    local function forbidden()error('observation invoked a hand-event callback')end
    local primary,secondary,updated=function()forbidden()end,function()forbidden()end,function()forbidden()end
    origin[primary],origin[secondary],origin[updated]='R5_AimState.lua','R5_AimState.lua','R5_AimState.lua'
    local state={onEquipPrimary=primary,onEquipSecondary=secondary,markUpdated=updated,
        EventHandlers={onEquipPrimary=primary,onEquipSecondary=secondary}}
    env.WPANC={BowState=state}
    local tracked={};local duringRead
    local native=function(actor,p,s,u)
        assert(p==primary and s==secondary and u==updated)
        observations=observations+1
        if nativeError then error('native metadata unavailable')end
        if duringRead then duringRead()end
        if tracked==nil then return nil end
        return tracked[actor]==nil
    end
    env.toolkitArcheryTrackingAbsent=native
    env.toolkitArcheryTrackingApiMatches=function(callback)return callback==native end
    env.require=function(path)assert(path=='PZSurvivorToolkit/SourceProof');return proof end
    local function load()
        return assert(setfenv(assert(loadfile(root..'client/PZSurvivorToolkit/ActionQueueHandEvents.lua')),env))()
    end
    return {env=env,proof=proof,state=state,origin=origin,native=native,load=load,
        counts=function()return sourceReads,observations end,
        source=function(value)sourceOK=value end,tracking=function(value)tracked=value end,
        during=function(value)duringRead=value end,throws=function(value)nativeError=value end}
end
local f=setup();local observer=f.load();local actor,other={},{}
assert(observer.archeryTrackingAbsent(actor)==true)
local tracked={[actor]={}};f.tracking(tracked)
assert(observer.archeryTrackingAbsent(actor)==false and observer.archeryTrackingAbsent(other)==true,
    'tracking belongs to the exact actor, not the visible hands')
tracked[actor]=nil;assert(observer.archeryTrackingAbsent(actor)==true)
f.tracking({[actor]={}});assert(observer.archeryTrackingAbsent(actor)==false)
f.tracking({});assert(observer.archeryTrackingAbsent(actor)==true,'table reset reused a cached negative/positive fact')
f.tracking(nil);assert(observer.archeryTrackingAbsent(actor)==nil,'unavailable capture became absent')
f.throws(true);assert(observer.archeryTrackingAbsent(actor)==nil,'native failure became absent');f.throws(false)
local sourceReads=f.counts();assert(sourceReads==1,'source was reopened after loaded closure qualification')
assert(observer.archeryTrackingAbsent()==nil and observer.archeryTrackingAbsent(actor,true)==nil)
for key in pairs(observer)do assert(key=='archeryTrackingAbsent','observation exposed unrelated authority')end
local function rejected(mutate)
    local case=setup();local api=case.load();mutate(case)
    assert(api.archeryTrackingAbsent(actor)==nil,'unsupported hand-event binding returned a fact')
end
rejected(function(case)case.source(false)end)
rejected(function(case)case.env.WPANC=nil end)
rejected(function(case)case.state.EventHandlers.onEquipPrimary=function()end end)
rejected(function(case)case.state.markUpdated=function()end end)
rejected(function(case)case.env.toolkitArcheryTrackingAbsent=function()return true end end)
rejected(function(case)case.env.toolkitArcheryTrackingApiMatches=function()return true end end)
rejected(function(case)case.env.toolkitLuaMetatableMatches=function()return true end end)
rejected(function(case)case.proof.captureBindings=function()return function()return true end end end)
rejected(function(case)setmetatable(case.state,{__index=function()error('inherited callback executed')end})end)
rejected(function(case)case.env.PZSurvivorToolkit.ActionQueueHandEvents={}end)
rejected(function(case)case.during(function()case.state.EventHandlers={}end)end)
rejected(function(case)case.during(function()case.env.toolkitArcheryTrackingAbsent=function()return true end end)end)
rejected(function(case)case.during(function()case.env.WPANC={BowState=case.state}end)end)
-- A same-file closure is still not native upvalue proof: the bridge can refuse it.
rejected(function(case)case.tracking(nil)end)
print('Hand-event Lua observation: source/API identity, fresh actor facts, rebinding, unavailable captures and reentry passed; no edit rights.')
