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
    local context=Tags.newProjectionContext()
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

-- Standalone projections share getters among readers, then discard the context.
local before=beforeCalls()
assert(not Tags.matches(Tags.forScriptItem(script),{'ingredient'}))
expectCalls(before,1)
local nextRecipe={getFullResultItem=function() return 'Mod.Meal' end,isCookable=function() return true end,
    getBaseItem=function() return 'Mod.Pot' end,
    getPossibleItems=function() return list({{getUse=function() return 1 end,getFullType=function() return name end}}) end}
current.evolved={nextRecipe}
assert(Tags.matches(Tags.forScriptItem(script),{'ingredient'}),'ordinary projection hid changed live recipes')
expectCalls(before,2)

-- Older or unsupported Java Patches provide no trustworthy catalog epoch.
-- Fresh list reads alone cannot validate a same-count shared-list index.
current.evolved={{getFullResultItem=function() return 'Mod.Meal' end,isCookable=function() return true end,
    getBaseItem=function() return 'Mod.Pot' end,
    getPossibleItems=function() return list({{getUse=function() return 1 end,
        getFullType=function() return 'Mod.Other' end}}) end}}
assert(not Tags.matches(Tags.forScriptItem(script),{'ingredient'}),
    'unversioned same-count replacement retained the former ingredient')
current.evolved={nextRecipe}
assert(Tags.matches(Tags.forScriptItem(script),{'ingredient'}),
    'unversioned same-count replacement omitted the new ingredient')

-- Physical batches share metadata only, even for instances of the same script.
local Custom=require 'PZSurvivorToolkit/TagCustomization'
world=Custom.empty()
local customId='custom:12345678-1234-1234-1234-123456789abc'
world.definitions[customId]={name='Physical batch'}
world.types[name:lower()]={[customId]='add'}
local function physical(category,fresh,broken)
    return {category=category,fresh=fresh,broken=broken,delta={},
        getFullType=function() return name end,getScriptItem=function() return script end,
        getDisplayCategory=function(self) return self.category end,
        IsFood=function() return true end,isBroken=function(self) return self.broken end,
        getOffAge=function() return 2 end,getOffAgeMax=function() return 4 end,
        isFresh=function(self) return self.fresh end,isRotten=function(self) return not self.fresh end,
        hasModData=function() return true end,getModData=function(self) return {[Custom.FIELD]=self.delta} end}
end
local first=physical('Mod.First',true,false)
local second=physical('Mod.Second',false,true)
second.delta[customId]='remove'
before=beforeCalls()
local physicalContext=Tags.newProjectionContext()
for _=1,100 do
    local a,b=Tags.forItem(first,physicalContext),Tags.forItem(second,physicalContext)
    assert(Tags.matches(a,{'category:Mod.First','fresh','ingredient',customId})
        and not Tags.matches(a,{'rotten','broken'},'any'),'first instance lost its live classification')
    assert(Tags.matches(b,{'category:Mod.Second','rotten','broken','ingredient'})
        and not Tags.matches(b,{'fresh',customId},'any'),'same-type instances shared mutable results')
end
expectCalls(before,1)
first.category,first.fresh,first.broken='Mod.Changed',false,true
first.delta[customId]='remove'
local changed=Tags.forItem(first,physicalContext)
assert(Tags.matches(changed,{'category:Mod.Changed','rotten','broken','ingredient'})
    and not Tags.matches(changed,{'category:Mod.First','fresh',customId},'any'),
    'operation metadata context froze physical state or instance custom tags')
first.delta[customId]=nil
world.types[name:lower()]={}
assert(not Tags.matches(Tags.forItem(first,physicalContext),{customId}),
    'operation context froze type customization')
world.types[name:lower()]={[customId]='add'}
world.definitions[customId].deleted=true
assert(not Tags.matches(Tags.forItem(first,physicalContext),{customId}),
    'operation context froze live custom definition deletion')
expectCalls(before,1)

-- Each independent physical projection gets fresh metadata, including automatic
-- producers and serialized snapshots, while their readers share one getter call.
current.evolved={}
before=beforeCalls()
assert(not Tags.matches(Tags.forItem(first),{'ingredient'}),'next physical operation retained recipe roles')
expectCalls(before,1)
current.evolved={nextRecipe}
before=beforeCalls()
assert(Tags.matches(Tags.automaticForItem(first),{'ingredient'}),'standalone automatic projection hid recipe changes')
expectCalls(before,1)
before=beforeCalls()
Tags.forSnapshot(script,name,'Mod.Snapshot')
expectCalls(before,1)

-- Choice discovery projects every physical item in one synchronous metadata
-- window, then obtains fresh recipe lists on the next operation.
local physicalItems={}
for index=1,100 do physicalItems[index]=index%2==0 and first or second end
before=beforeCalls()
Tags.cachedIds(physicalItems)
expectCalls(before,1)
current.evolved={}
before=beforeCalls()
Tags.cachedIds(physicalItems)
expectCalls(before,1)
current.evolved={nextRecipe}
before=beforeCalls()
Tags.allIds(physicalItems)
expectCalls(before,1)

-- A getter exception propagates without leaving a global operation cache or
-- poisoning the next projection, which must retry the restored native getter.
local craftGetter=manager.getAllCraftRecipes
manager.getAllCraftRecipes=function() error('catalog unavailable') end
assert(not pcall(Tags.forItem,first),'metadata getter failure was hidden')
manager.getAllCraftRecipes=craftGetter
before=beforeCalls()
assert(Tags.matches(Tags.forItem(first),{'ingredient'}),'failed operation poisoned later projections')
expectCalls(before,1)

-- Unavailable catalogs are captured once for the operation, then retried next time.
local missingReads=0
local unavailable={getAllCraftRecipes=function() missingReads=missingReads+1 end}
local context=Tags.newProjectionContext()
assert(context:recipes(unavailable,'getAllCraftRecipes')==nil)
assert(context:recipes(unavailable,'getAllCraftRecipes')==nil and missingReads==1)
Tags.newProjectionContext():recipes(unavailable,'getAllCraftRecipes')
assert(missingReads==2,'fresh operation did not retry an unavailable catalog')
local missingMethod={}
assert(context:recipes(missingMethod,'getAllRecipes')==nil)
missingMethod.getAllRecipes=function() return shared.legacy end
assert(context:recipes(missingMethod,'getAllRecipes')==nil,'missing metadata was not stable within the operation')
assert(Tags.newProjectionContext():recipes(missingMethod,'getAllRecipes')==shared.legacy,
    'missing metadata persisted beyond its projection context')

-- UI discovery retains no partial global IDs and creates a recipe context for
-- each synchronous step, rather than keeping mutable native lists over frames.
local catalogEpoch = 1
toolkitRecipeCatalogRevision = function() return catalogEpoch end
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

-- A cold mixed catalog is one synchronous operation across both loaded scripts
-- and supplied physical items. A second operation reuses only the published
-- script IDs; physical categories and native recipe metadata remain live.
toScan[#toScan+1]={getFullName=function() return 'Mod.ColdMixed' end,
    getDisplayCategory=function() return 'Mod.ColdMixed' end,isItemType=function() return false end}
before=beforeCalls()
local mixed=Tags.allIds(physicalItems)
assert(contains(mixed,'category:Mod.ColdMixed') and contains(mixed,'category:Mod.Changed')
    and contains(mixed,'category:Mod.Second'),'mixed catalog omitted script or physical categories')
expectCalls(before,1)
first.category='Mod.AfterMixed'
before=beforeCalls()
mixed=Tags.allIds(physicalItems)
assert(contains(mixed,'category:Mod.AfterMixed') and not contains(mixed,'category:Mod.Changed'),
    'mixed catalog retained physical categories between operations')
expectCalls(before,1)

-- Recipe changes also invalidate published choice IDs and the public revision
-- used by already open editors, manifest views and distribution catalogues.
local previousScan = toScan
local previousCategory = script.getDisplayCategory
script.getDisplayCategory = function() return 'Mod.CatalogBefore' end
toScan = {script}
current.evolved = {nextRecipe}
catalogEpoch = catalogEpoch + 1
local oldRevision = Tags.revision()
assert(contains(Tags.allIds(), 'category:Mod.CatalogBefore'), 'catalog omitted the current script category')
current.evolved = {{getFullResultItem=function() return 'Mod.Meal' end,isCookable=function() return true end,
    getBaseItem=function() return 'Mod.Pot' end,
    getPossibleItems=function() return list({}) end}}
catalogEpoch = catalogEpoch + 1
script.getDisplayCategory = function() return 'Mod.CatalogAfter' end
assert(Tags.revision() ~= oldRevision, 'native reload did not invalidate open tag consumers')
assert(not contains(Tags.cachedIds(), 'category:Mod.CatalogBefore'), 'cached IDs retained an invalidated script category')
local updated = Tags.allIds()
assert(contains(updated, 'category:Mod.CatalogAfter') and not contains(updated, 'category:Mod.CatalogBefore'),
    'same-count native reload retained published automatic IDs')
assert(not Tags.matches(Tags.forScriptItem(script), {'ingredient'}), 'catalog refresh retained the old recipe role')
catalogEpoch = catalogEpoch + 1
local interrupted = assert(Tags.newAutomaticIdScan())
catalogEpoch = catalogEpoch + 1
assert(interrupted:step(4) and interrupted.cancelled, 'old discovery survived a native reload between frames')
assert(not contains(Tags.cachedIds(), 'category:Mod.CatalogAfter'), 'cancelled discovery published invalidated IDs')
script.getDisplayCategory = previousCategory
toScan = previousScan
print('Tag projection: bounded recipe getters, fresh operations, live physical instances and per-frame script catalogs passed')
