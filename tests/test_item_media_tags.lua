package.path = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/?.lua;' .. package.path
local invalidate
Events = {OnInitRecordedMedia = {Add = function(callback) invalidate = callback end}}
local Media = require 'PZSurvivorToolkit/ItemMediaTags'
local function list(values)
    return {size=function() return #values end, get=function(_, index) return values[index+1] end}
end
local scans = 0
local function recording(codes)
    return {getId=function() return codes end,
        getTranslatedItemDisplayName=function() return 'Recorded lesson' end,
        getLineCount=function() scans=scans+1; return #codes end,
        getLine=function(_,index) return {getCodes=function() return codes[index+1] end} end}
end
local cases = {
    {recording({'BOR-1,FIT+1,STS-2,XXX+5,CRP+0,ELC-1'}),false,false},
    {recording({'CRP+1','BOR-1'}),true,false},
    {recording({'RCP=MakeCakeBatter','BOR-1'}),false,true},
    {recording({'COO+1','RCP=MakeCakeBatter','RCP=MakePieDough'}),true,true},
    {recording({'COO+1,RCP=MakeCakeBatter'}),true,true},
    {recording({'RCP','CRP+','CRP=2'}),true,false},
}
for _,case in ipairs(cases) do
    local experience,recipe = Media.effects(case[1])
    assert(experience==case[2] and recipe==case[3],'recorded content effects disagree')
end
local initialScans=scans
for _=1,20 do Media.effects(cases[4][1]) end
assert(scans==initialScans,'immutable recording rescanned per item/frame')
local script={getRecordedMediaCat=function() return 'Retail-VHS' end}
local item={getMediaData=function() return cases[4][1] end}
local xp,recipe,states=Media.read(script,item)
assert(xp and recipe and states==nil,'physical tape lost one of its independent effects')
assert(Media.read(script,{getMediaData=function() end})==false,'unrecorded carrier invented a lesson')
assert(Media.read({})==nil,'ordinary literature was treated as a media carrier')
assert(Media.read(script)==nil,'unloaded catalog invented possible recording effects')

-- Only recipe-only and XP-only recordings exist in this catalog. Combining both is impossible.
local enumerations=0
local registered={getAllMediaForCategory=function(_,category)
    assert(category=='Retail-VHS');enumerations=enumerations+1
    return list({cases[2][1],cases[3][1],cases[3][1]})
end}
getZomboidRadio=function() return {getRecordedMedia=function() return registered end} end
xp,recipe,states=Media.read(script)
assert(xp==false and recipe==false and #states==2,'script carrier claimed a particular lesson')
local seen={}
for _,state in ipairs(states) do
    seen[(state.experience and '1' or '0')..(state.recipe and '1' or '0')]=true
end
assert(seen['10'] and seen['01'] and not seen['11'] and not seen['00'],'preview invented an unavailable combination')
states[1].experience=false;states[1].recipe=false
for _=1,20 do Media.read(script) end
assert(enumerations==1,'registered catalog was enumerated per preview/frame')
local _,_,fresh=Media.read(script)
assert(fresh[1].experience or fresh[1].recipe,'caller changed cached media possibilities')
registered={getAllMediaForCategory=function() return list({cases[4][1]}) end}
local _,_,replacement=Media.read(script)
assert(#replacement==1 and replacement[1].experience and replacement[1].recipe,'catalog replacement reused stale possibilities')
getZomboidRadio=nil
RecMedia={a={category='Retail-VHS',lines={{codes='RCP=MakeCakeBatter'}}},
    b={category='CDs',lines={{codes='COO+1'}}}}
local _,_,fallback=Media.read(script)
assert(#fallback==1 and fallback[1].recipe and not fallback[1].experience,'raw catalog fallback mixed carrier categories')
RecMedia.c={category='Retail-VHS',lines={{codes='BOR-1'}}}
invalidate()
local _,_,updated=Media.read(script)
assert(#updated==2,'native content initialization did not invalidate script possibilities')
print('Media tags passed: independent effects, recipe-only/XP-only/both/neither, carrier combinations, catalog identity and cache invalidation.')

if NativeActionRoot then
    RecMedia={}
    dofile(NativeActionRoot..'/shared/RecordedMedia/recorded_media.lua')
    Media.invalidate()
    local known={
        ['e6fd44a9-1774-4204-ab45-9b316301aa2b']='The Cook Show E1',
        ['ffe28381-b743-4300-8c5a-89b4c4983d05']='Muldraugh AV Club',
    }
    for id,name in pairs(known) do
        local experience,learnsRecipe=Media.effects(assert(RecMedia[id],name..' absent from native catalog'))
        assert(experience and learnsRecipe,name..' lost native XP or recipe')
    end
    local recipeCount,recipeOnly=0,0
    for _,record in pairs(RecMedia) do
        local experience,learnsRecipe=Media.effects(record)
        if learnsRecipe then
            recipeCount=recipeCount+1
            if not experience then recipeOnly=recipeOnly+1 end
        end
    end
    assert(recipeCount>0,'native source check found no recipes')
    print('Native recorded-media source verified: '..recipeCount..' recordings teach recipes; '..recipeOnly..' teach recipes without XP.')
else print('SKIP native recorded-media definitions: pass --native-action-root or --game') end


-- Consumers project one physical recording, or one possible recording, before manual overrides.
local worldTags={}
isClient=function() return false end
ModData={getOrCreate=function() return worldTags end}
PZSurvivorToolkit={Settings={itemTags=function() return true end}}
ItemType={NORMAL='normal'}
InventoryItemFactory={CreateItem=function() error('media preview created an inventory item') end}
instanceItem=function() error('media preview instantiated a script item') end
package.preload['Moveables/ISMoveableDefinitions']=function() return {} end
local Tags=require 'PZSurvivorToolkit/ItemTags'
local Custom=require 'PZSurvivorToolkit/TagCustomization'
local definition={getFullName=function() return 'Fixture.RecordingCarrier' end,
    getDisplayName=function() return 'Carrier' end,
    getDisplayCategory=function() return 'entertainmentVideo' end,
    getRecordedMediaCat=function() return 'Retail-VHS' end,
    isItemType=function() return false end,
    InstanceItem=function() error('media script preview ran OnCreate') end}
local function physical(record)
    return {record=record,
        getFullType=function() return definition:getFullName() end,
        getDisplayCategory=function() return 'entertainmentVideo_experience' end,
        getScriptItem=function() return definition end,
        getMediaData=function(self) return self.record end,
        hasModData=function(self) return self.md~=nil end,
        getModData=function(self) assert(self.md);return self.md end}
end
local function rule(include,exclude,mode)
    return assert(Tags.normalizeRule({include=include or {},exclude=exclude or {},mode=mode or 'all'}))
end
local xpOnly=rule({'experience'},{'recipe'})
local recipeOnly=rule({'recipe'},{'experience'})
local both=rule({'experience','recipe'})
local neither=rule({}, {'experience','recipe'})
for _,case in ipairs(cases) do
    local actual=physical(case[1])
    local ids=Tags.forItem(actual)
    assert(Tags.matches(ids,{'experience'})==case[2] and Tags.matches(ids,{'recipe'})==case[3],
        "same-fulltype recordings inherited one another's effects or stale category")
    assert(Tags.matchesRule(ids,both)==(case[2] and case[3]),'actual media invented a joint lesson')
end
local actual=physical(cases[2][1])
assert(Tags.matchesRule(Tags.forItem(actual),xpOnly))
actual.record=cases[3][1]
assert(Tags.matchesRule(Tags.forItem(actual),recipeOnly),'changing the same physical tape reused cached type effects')

registered={getAllMediaForCategory=function() return list({cases[2][1],cases[3][1]}) end}
getZomboidRadio=function() return {getRecordedMedia=function() return registered end} end
Media.invalidate()
local preview=Tags.forScriptItem(definition)
assert(not Tags.matches(preview,{'experience'}) and not Tags.matches(preview,{'recipe'}),
    'script default claimed a particular recorded lesson')
local choices=Tags.choices(preview)
assert(Tags.matches(choices,{'experience','recipe'}),'carrier menu omitted possible lessons')
assert(Tags.matchesScriptRule(definition,xpOnly) and Tags.matchesScriptRule(definition,recipeOnly),
    'script preview omitted an actually available exclusive lesson')
assert(not Tags.matchesScriptRule(definition,both) and not Tags.matchesScriptRule(definition,neither),
    'preview combined different tapes or invented an unrecorded possibility')
assert(Tags.matchesScriptRule(definition,rule({'experience','recipe'},nil,'any')),
    'any-rule rejected available media effects')

worldTags.types['fixture.recordingcarrier']={experience='remove'}
assert(not Tags.matchesScriptRule(definition,rule({'experience'}))
    and Tags.matchesScriptRule(definition,neither),
    'hypothetical XP state overrode a manual removal')
worldTags.types['fixture.recordingcarrier'].recipe='add'
assert(not Tags.matchesScriptRule(definition,both) and Tags.matchesScriptRule(definition,recipeOnly),
    'hypothetical states overrode manual removal/addition')
worldTags.types['fixture.recordingcarrier']={experience='add'}
assert(Tags.matchesScriptRule(definition,both),'manual addition was applied before selecting a real recipe-only tape')
actual=physical(cases[3][1]);actual.md={[Custom.FIELD]={experience='remove',recipe='remove'}}
assert(Tags.matchesRule(Tags.forItem(actual),neither),'instance removals failed to override type addition and content')
worldTags.types={}

registered={getAllMediaForCategory=function() return list({cases[1][1],cases[4][1]}) end}
assert(Tags.matchesScriptRule(definition,both) and Tags.matchesScriptRule(definition,neither),
    'replacement catalog lost actual both/neither combinations')
assert(not Tags.matchesScriptRule(definition,xpOnly) and not Tags.matchesScriptRule(definition,recipeOnly),
    'replacement catalog retained impossible exclusive states')

-- Snapshots carry explicit content but no live InventoryItem for native predicates.
assert(Tags.requiresItemRule('experience') and Tags.requiresItemRule('recipe'))
local snapshot=Tags.forSnapshot(definition,definition:getFullName(),'entertainmentVideo_experience',cases[4][1])
assert(Tags.matchesRule(snapshot,both) and snapshot.mediaStates==nil
    and Tags.category(snapshot)=='entertainmentVideo_experience'
    and Tags.matches(snapshot,{'category:entertainmentVideo_experience'}),
    'snapshot lost captured effects, cleared provenance or retained preview possibilities')
local emptySnapshot=Tags.forSnapshot(definition,definition:getFullName(),'entertainmentVideo_experience')
assert(Tags.matchesRule(emptySnapshot,neither) and emptySnapshot.mediaStates==nil,
    'missing snapshot recording invented lessons from its category or carrier catalog')
local savedDelta={recipe='remove'}
local changedSnapshot=Tags.forSnapshot(definition,definition:getFullName(),'entertainmentVideo_experience',cases[4][1],savedDelta)
assert(Tags.matchesRule(changedSnapshot,xpOnly) and savedDelta.recipe=='remove',
    'snapshot manual changes were ignored or mutated')
assert(Tags.matchesRule(Tags.forSnapshot(definition,definition:getFullName(),'entertainmentVideo_experience',
    cases[4][1],{recipe='invalid-operation'}),both),'snapshot accepted an invalid unnormalized manual delta')

-- The real presentation module must pass resolved MediaData to the snapshot service.
registered.getMediaData=function(_,id) assert(id=='fixture-both');return cases[4][1] end
registered.getMediaDataFromIndex=function(_,index) assert(index==7);return cases[3][1] end
local nativePredicateCalls=0
ResourceType={Item=1}
toolkitRecipeHasItemTest=function() return false end
local subject={getResourceType=function() return ResourceType.Item end,
    isKeep=function() return false end, getIntAmount=function() return 1 end,
    hasConsumeFromItem=function() return false end, hasCreateToItem=function() return false end,
    isApplyOnTick=function() return false end,isReplace=function() return false end,
    getPossibleInputItems=function() return list({definition}) end,
    isUsesPartialItem=function() return false end,
    doesItemPassRoutineStatusTests=function(_,item)
        nativePredicateCalls=nativePredicateCalls+1
        assert(item==actual,'native predicate received a Lua snapshot proxy')
        return false
    end}
local dismantle={getName=function() return 'DismantleElectronics' end,
    getInputs=function() return list({subject}) end, getXPAwardCount=function() return 0 end}
local manager={FindItem=function(_,fullType)
    assert(fullType==definition:getFullName());return definition
end,getAllCraftRecipes=function() return list({dismantle}) end}
getScriptManager=function() return manager end
local Presentation=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ManifestPresentation.lua')
local name,_,ids=Presentation.describe({ft=definition:getFullName(),cat='entertainmentVideo',mediaId='fixture-both'})
assert(name=='Recorded lesson' and Tags.matchesRule(ids,both),'manifest lost actual MediaData or its second effect')
name,_,ids=Presentation.describe({ft=definition:getFullName(),cat='entertainmentVideo',mediaIndex=7,name='Named carrier'})
assert(name=='Named carrier' and Tags.matchesRule(ids,recipeOnly),'manifest index reused another recording or overwrote its name')
_,_,ids=Presentation.describe({ft=definition:getFullName(),cat='entertainmentVideo',mediaId='fixture-both',
    tagDelta={recipe='remove'}})
assert(Tags.matchesRule(ids,xpOnly),'manifest media content overrode saved instance tag changes')
local View=require 'PZSurvivorToolkit/ManifestView'
local view=View.new(Presentation.describe,Tags)
assert(view:setPayload({containers={box={entries={
    both={ft=definition:getFullName(),cat='entertainmentVideo',mediaId='fixture-both',n=2},
    recipe={ft=definition:getFullName(),cat='entertainmentVideo',mediaIndex=7,n=3},
    manual={ft=definition:getFullName(),cat='entertainmentVideo',mediaId='fixture-both',n=5,
        tagDelta={recipe='remove'}},
}}}}))
local xpRows,xpCount=view:select('', 'experience')
local recipeRows,recipeCount=view:select('', 'recipe')
assert(#xpRows==2 and xpCount==7 and #recipeRows==2 and recipeCount==5,
    'filtered manifest mixed recorded content or lost manual snapshot changes')
assert(nativePredicateCalls==0,'snapshot/filtered manifest invoked live native item predicates')
assert(Tags.matches(Tags.forSnapshot(definition,definition:getFullName(),'entertainmentVideo',cases[4][1]),{'dismantle'}),
    'snapshot omitted script disassembly capability')
assert(not Tags.matches(Tags.forItem(actual),{'dismantle'}) and nativePredicateCalls==1,
    'native predicate regression fixture did not exercise the live-item path')
print('Media consumer integration passed: same-type recordings, exclusive/joint previews, post-state changes, snapshots and filtered manifests without live predicates.')
