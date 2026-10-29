local function eq(a,b,where)
    assert(type(a)==type(b), where .. ': type')
    if type(a)=='table' then
        for k,v in pairs(a) do eq(v,b[k],where..'.'..k) end
        for k in pairs(b) do assert(a[k]~=nil,where..'.extra.'..k) end
    else assert(a==b, where .. ': value') end
end
local fields={'ProximityEnabled','ForceCorpseOnly','AllowToggleProximity','AllowSwitchMode','AutoLockEnabled','AllowToggleAutoLock'}
local optionsFields={'enableProximity','enableCorpseOnly','enableDualMode','enableAutoLock','showCorpsesOnlyWhenNearby','hideIndividualCorpseContainers'}
local values={false,true,0,'true'}
-- Compute the stock module independently under the same environment.
local stock = StockPermissions
local function restore()
    SandboxVars={BetterContainers={}}
    getTextOrNull=function(k) return k end
end
restore()
local function compare(o,label)
    eq(stock.compute(o),Permissions.compute(o),label)
end
compare(nil,'defaults')
-- All Boolean policy/preference combinations; non-Boolean normalization below.
for mask=0,4095 do
    local sb,o={},{}
    for i,k in ipairs(fields) do sb[k]=math.floor(mask/2^(i-1))%2==1 end
    for i,k in ipairs(optionsFields) do o[k]=math.floor(mask/2^(i+5))%2==1 end
    SandboxVars={BetterContainers=sb}; compare(o,'mask'..mask)
end
for _,v in ipairs(values) do
    for _,k in ipairs(fields) do restore(); SandboxVars.BetterContainers[k]=v; compare({},'policy value') end
    for _,k in ipairs(optionsFields) do restore(); compare({[k]=v},'option value') end
end
restore()
local a=Permissions.compute({}); a.sandbox.ProximityEnabled=false; a.ui.toggleLock.reason='mutated'; a.ui.enableProximity.enabled=false; a.proximityActive='changed'
local b=Permissions.compute({})
assert(a~=b and a.sandbox~=b.sandbox and a.ui~=b.ui and a.ui.toggleLock~=b.ui.toggleLock and a.ui.enableProximity~=b.ui.enableProximity,'fresh owned results')
compare({},'result mutation')
-- Ordered translator calls, mutation during translation, and reentry. Each invocation retains its sandbox snapshot.
local function callbackScenario(module)
    restore(); local trace={}; local inside=false; local nested
    getTextOrNull=function(k)
        trace[#trace+1]=k
        if not inside then
            inside=true; SandboxVars.BetterContainers.ProximityEnabled=false
            nested=module.compute({enableProximity=true}); inside=false
        end
        return k..#trace
    end
    local result=module.compute({enableProximity=true})
    return {result=result,nested=nested,trace=trace}
end
eq(callbackScenario(stock),callbackScenario(Permissions),'translator reentry')
-- A replaced public getSandbox may return shared/metatable tables: candidate must delegate unchanged.
local custom={ProximityEnabled=true,AllowToggleProximity=true,ForceCorpseOnly=false,AllowSwitchMode=true,AutoLockEnabled=true,AllowToggleAutoLock=true}
local stockGetter,candidateGetter=stock.getSandbox,Permissions.getSandbox
stock.getSandbox=function() return custom end; Permissions.getSandbox=stock.getSandbox
restore(); getTextOrNull=function(k) custom.AllowSwitchMode=false; return k end
custom.AllowSwitchMode=true; local customStock=stock.compute({enableProximity=true})
custom.AllowSwitchMode=true; eq(customStock,Permissions.compute({enableProximity=true}),'public getter replacement'); assert(Permissions.compute({}).sandbox==custom,'shared custom snapshot identity')
stock.getSandbox=stockGetter; Permissions.getSandbox=candidateGetter
-- Distinct callback boundaries in update may alter policy between all four reads.
restore(); local sequence={}
for i=1,4 do SandboxVars.BetterContainers.ProximityEnabled=i%2==0; sequence[i]=Permissions.compute({enableProximity=true}).proximityActive end
assert(sequence[1]==false and sequence[2]==true and sequence[3]==false and sequence[4]==true,'fresh policy at consumer boundaries')
restore()
-- Truthy translated strings and nil fallback are checked without changing call count/order.
local translations={}; getTextOrNull=function(k) translations[#translations+1]=k; return nil end
compare({enableProximity=true},'nil translations'); assert(#translations==6,'three translation calls per compute')
-- Lua-visible table __index side effects on options are retained, including order.
local function optionScenario(module)
    restore(); local trace={}
    local o=setmetatable({}, {__index=function(t,k) trace[#trace+1]=k; return true end})
    return {result=module.compute(o),trace=trace}
end
eq(optionScenario(stock),optionScenario(Permissions),'option callbacks')
restore()
-- Execute the selected external inventory-page update and unedited DoAutoLock body.
-- Their Lua callbacks deliberately change settings between permission consumers.
local function updateScenario(module)
    restore(); local trace={}; local reads=0; local translations=0
    getTextOrNull=function(k) translations=translations+1; return k end
    local o={enableProximity=true,enableAutoLock=true,enableProximityHighlight=true}
    o.getEffectivePermissions=function()
        reads=reads+1; local e=module.compute(o)
        trace[#trace+1]='permissions:'..tostring(e.corpseOnly)..':'..tostring(e.allowSwitchMode)
        return e
    end
    ISInventoryPage={update=function() trace[#trace+1]='base-update' end}
    Proximity={_ForceSwitchIntent={},forceSelectedType={},isForceSelected={},_BrowseElapsedMs={},invName='prox',invName_corpses='corpses'}
    Proximity.isTransferActive=function() trace[#trace+1]='transfer'; o.enableCorpseOnly=true; return false end
    Proximity.GetPreferredType=function() trace[#trace+1]='preferred'; return 'prox' end
    Proximity.isProximityType=function(t) return t=='prox' end
    Proximity.getVanillaHoveredItem=function() return {} end
    Proximity.getProximityHoveredItem=function() return {} end
    local inv={getType=function() trace[#trace+1]='getType'; SandboxVars.BetterContainers.AllowSwitchMode=false; return 'prox' end}
    local parent={}
    parent.setHighlighted=function() trace[#trace+1]='highlight'; SandboxVars.BetterContainers.ForceCorpseOnly=true end
    parent.setOutlineHighlight=function() trace[#trace+1]='outline' end
    parent.setOutlineHlAttached=function() trace[#trace+1]='attached' end
    instanceof=function() return false end
    local color={getR=function() return 1 end,getG=function() return 1 end,getB=function() return 1 end}
    getCore=function() return {getObjectHighlitedColor=function() return color end} end
    local previousRequire=require
    require=function(name)
        if name=='BetterContainers/_Options' then return o end
        if name=='BetterContainers/Proximity' then return Proximity end
        if name=='ISUI/ISInventoryPage' then return true end
        error('unexpected require '..name)
    end
    assert(loadstring(AutoLockSource))()
    local pageModule=assert(loadstring(InventoryPageSource))(); pageModule.install()
    local page={player=0,inventory=inv,backpacks={},coloredProximityInventories={[{}]=true},getContainerParent=function() return parent end}
    ISInventoryPage.update(page)
    require=previousRequire
    assert(reads==4 and translations==12,'four original permission boundaries with translator effects')
    local remaining=0; for _ in pairs(page.coloredProximityInventories) do remaining=remaining+1 end
    assert(remaining==0,'clear highlights retained')
    return trace
end
eq(updateScenario(stock),updateScenario(Permissions),'actual update callback boundaries')
restore()
workloads={}
local o={enableProximity=true,enableCorpseOnly=false,enableDualMode=false,enableAutoLock=false,showCorpsesOnlyWhenNearby=true,hideIndividualCorpseContainers=false}
local function read(i)
    -- Alternate live preferences and consume a nested gate; retain fresh result contract.
    o.enableCorpseOnly=i%2==0
    local e=Permissions.compute(o)
    return (e.proximityActive and 1 or 0)+(e.corpseOnly and 2 or 0)+(e.ui.toggleLock.enabled and 4 or 0)
end
workloads.single=read
workloads['four-consumer']=function(i) return read(i)+read(i+1)+read(i+2)+read(i+3) end
