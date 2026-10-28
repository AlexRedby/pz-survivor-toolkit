package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/?.lua;'..package.path
isClient=function() return false end
local world={}
ModData={getOrCreate=function() return world end}
ItemType={FOOD='food',NORMAL='normal',WEAPON='weapon',CLOTHING='clothing',CONTAINER='container',DRAINABLE='drainable'}
ResourceType={Item='item',Fluid='fluid'}
toolkitRecipeOnCreate=function() end
toolkitRecipeHasItemTest=function() return false end
local function list(values)
    return {size=function() return #values end,get=function(_,index) return values[index+1] end}
end
local name='Mod.ProjectionSubject'
local script={getFullName=function() return name end,getDisplayCategory=function() return 'Mod.Projection' end,
    isItemType=function() return false end,getConditionMax=function() return 10 end}
local unusedRecipe={getName=function() return 'Mod.Unrelated' end,getInputs=function() return list({}) end}
local current={craft={unusedRecipe},evolved={},legacy={}}
local calls={craft=0,evolved=0,legacy=0}
-- Like native ScriptBucketCollection, getters refill the same list object.
local shared, getters={},{}
for _,kind in ipairs({'craft','evolved','legacy'}) do
    local key, values=kind,{}
    shared[key]=list(values)
    getters[key]=function()
        calls[key]=calls[key]+1
        for index=#values,1,-1 do values[index]=nil end
        for index,value in ipairs(current[key]) do values[index]=value end
        return shared[key]
    end
end
local manager={getAllCraftRecipes=getters.craft,getAllEvolvedRecipesList=getters.evolved,getAllRecipes=getters.legacy,
    getItem=function(_,fullType)
        if fullType=='Mod.Meal' then return {isItemType=function(_,kind) return kind==ItemType.FOOD end} end
    end}
getScriptManager=function() return manager end
local Tags=require 'PZSurvivorToolkit/ItemTags'
local function beforeCalls() return {craft=calls.craft,evolved=calls.evolved,legacy=calls.legacy} end
local function expectCalls(before,amount)
    for key,value in pairs(calls) do assert(value==before[key]+amount,'recipe getter was not bounded for '..key) end
end
local function batch(expected)
    local before=beforeCalls()
    local context=Tags.newScriptProjectionContext()
    for _=1,100 do
        assert(Tags.matches(Tags.forScriptItem(script,context),{'ingredient'})==expected,'batch projected stale recipe roles')
    end
    expectCalls(before,1)
end
batch(false)
current.evolved={{getFullResultItem=function() return 'Mod.Meal' end,isCookable=function() return true end,
    getBaseItem=function() return 'Mod.Pot' end,
    getPossibleItems=function() return list({{getUse=function() return 1 end,getFullType=function() return name end}}) end}}
batch(true) -- A fresh window must obtain current recipe lists even at identical list identities.
current.evolved={}
batch(false)

-- Nonbatch callers keep the live getter path and its fresh recipe semantics.
local before=beforeCalls()
assert(not Tags.matches(Tags.forScriptItem(script),{'ingredient'}))
local nextRecipe={getFullResultItem=function() return 'Mod.Meal' end,isCookable=function() return true end,
    getBaseItem=function() return 'Mod.Pot' end,
    getPossibleItems=function() return list({{getUse=function() return 1 end,getFullType=function() return name end}}) end}
current.evolved={nextRecipe}
assert(Tags.matches(Tags.forScriptItem(script),{'ingredient'}),'ordinary projection hid changed live recipes')
assert(calls.craft>before.craft+1 and calls.evolved==before.evolved+2 and calls.legacy==before.legacy+2,
    'ordinary projections unexpectedly retained a batch context')

-- Unavailable catalogs are captured once for the operation, then retried next time.
local missingReads=0
local unavailable={getAllCraftRecipes=function() missingReads=missingReads+1 end}
local context=Tags.newScriptProjectionContext()
assert(context:recipes(unavailable,'getAllCraftRecipes')==nil)
assert(context:recipes(unavailable,'getAllCraftRecipes')==nil and missingReads==1)
Tags.newScriptProjectionContext():recipes(unavailable,'getAllCraftRecipes')
assert(missingReads==2,'fresh operation did not retry an unavailable catalog')

-- UI discovery retains no partial global IDs and creates a recipe context for
-- each synchronous step, rather than keeping mutable native lists over frames.
local toScan, enumerations = {}, 0
for index=1,120 do
    local category='Mod.Scan'..index
    toScan[index]={getFullName=function() return 'Mod.ScanItem'..index end,
        getDisplayCategory=function() return category end,isItemType=function() return false end}
end
manager.getAllItems=function() enumerations=enumerations+1;return list(toScan) end
local function contains(ids,wanted)
    for _,id in ipairs(ids) do if id==wanted then return true end end
    return false
end
assert(not contains(Tags.cachedIds(),'category:Mod.Scan1') and enumerations==0,
    'cached IDs forced script discovery')
local scan=assert(Tags.newAutomaticIdScan())
assert(enumerations==1)
local clock,now=getTimestampMs,0
getTimestampMs=function() now=now+1;return now end
local before=beforeCalls()
assert(not scan:step(4) and scan.index==5,'ID scan ignored the per-step time budget')
expectCalls(before,1)
assert(not contains(Tags.cachedIds(),'category:Mod.Scan1'),'partial automatic IDs leaked to another window')
before=beforeCalls()
assert(not scan:step(4) and scan.index==9)
expectCalls(before,1)
toScan[1]={getFullName=function() return 'Mod.Later' end,getDisplayCategory=function() return 'Mod.Later' end}
local frames=2
while not scan:step(4) do frames=frames+1;assert(frames<100) end
assert(contains(Tags.cachedIds(),'category:Mod.Scan1') and not contains(Tags.cachedIds(),'category:Mod.Later'),
    'ID scan did not publish its stable raw snapshot atomically')
assert(Tags.newAutomaticIdScan()==nil,'warm discovery did not reuse the completed automatic cache')
toScan[#toScan+1]={getFullName=function() return 'Mod.New' end,getDisplayCategory=function() return 'Mod.New' end}
local cancelled=assert(Tags.newAutomaticIdScan())
cancelled:step(4);cancelled:cancel()
assert(cancelled:step(4) and not contains(Tags.cachedIds(),'category:Mod.New'),
    'cancelled discovery published its partial IDs')
scan=assert(Tags.newAutomaticIdScan())
while not scan:step(4) do end
assert(contains(Tags.cachedIds(),'category:Mod.New') and contains(Tags.cachedIds(),'category:Mod.Later'),
    'fresh discovery missed changed script registrations')
getTimestampMs=clock
print('Script tag projection: bounded native recipe getters, fresh batch catalogs and live nonbatch reads passed')
