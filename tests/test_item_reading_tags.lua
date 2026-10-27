package.path = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/?.lua;' .. package.path
ItemType = {LITERATURE='literature', MAP='map', CONTAINER='container'}
ItemTag = {PICTURE='picture', UNINTERESTING='uninteresting'}
toolkitScriptCanBeWrite = function(script) return script.writeable == true end
local Tags = require 'PZSurvivorToolkit/ItemTags'
local function list(values)
    return {size=function() return #values end}
end
local function script(id, category, kind, fields)
    local value=fields or {}
    value.id, value.category, value.kind = 'Base.'..id, category, kind
    value.nativeCategory=category
    value.getFullName=function(self) return self.id end
    value.getDisplayCategory=function(self) return self.category end
    value.isItemType=function(self, kind) return self.kind==kind end
    value.hasTag=function(self, tag) return self.tags and self.tags[tag] or false end
    value.getSkillTrained=function(self) return self.skill end
    value.getLearnedRecipes=function(self) return self.recipes and list(self.recipes) end
    value.getBoredomChange=function(self) return self.boredom or 0 end
    value.getStressChange=function(self) return self.stress or 0 end
    value.getUnhappyChange=function(self) return self.unhappy or 0 end
    return value
end
local function item(definition)
    return {definition=definition,empty=true,writeable=definition.writeable or false,
        getFullType=function(self) return self.definition.id end,
        getDisplayCategory=function(self) return self.definition.uiCategory or self.definition.category end,
        getScriptItem=function(self) return self.definition end,
        IsLiterature=function(self) return self.definition.kind=='literature' end,
        IsMap=function(self) return self.definition.kind=='map' end,
        IsInventoryContainer=function(self) return self.definition.kind=='container' end,
        canBeWrite=function(self) return self.writeable end,
        isEmptyPages=function(self) return self.empty end,
        hasTag=function(self,tag) return self.definition:hasTag(tag) end,
        getSkillTrained=function(self) return self.definition:getSkillTrained() end,
        getLearnedRecipes=function(self) return self.definition:getLearnedRecipes() end,
        hasModData=function(self) return self.md~=nil end,
        getModData=function(self) assert(self.md,'read allocated ModData');return self.md end}
end
OrganizedCategories={getScriptInventoryDisplayCategory=function(definition)
    return definition.uiCategory or definition.category
end}
-- Native B42 definitions: effects, tags and type matter independently of OC labels.
local cases={
    {script('Book','Literature','literature',{boredom=-50,stress=-40,unhappy=-40}),true,true,false},
    {script('ComicBook','Literature','literature',{boredom=-30,tags={picturebook=true}}),true,true,false},
    {script('ChildsPictureBook','Literature','literature',{unhappy=-40,tags={picturebook=true}}),true,true,false},
    {script('MagazineCrossword','Literature','literature',{boredom=-20}),true,true,false},
    {script('BookCarpentry1','SkillBook','literature',{skill='Carpentry'}),true,false,false,'experience'},
    {script('KeyMag1','RecipeResource','literature',{boredom=-20,recipes={'CopyBuildingKey'}}),true,false,false},
    {script('RecipeClipping','RecipeResource','literature'),true,false,false},
    {script('Photo','Memento','literature',{boredom=-5,tags={picture=true}}),true,false,false},
    {script('Doodle','Memento','literature',{boredom=-5,tags={picture=true}}),true,false,false},
    {script('Brochure','Junk','literature',{tags={picture=true}}),true,false,false},
    {script('Newspaper_Recent','Literature','literature'),true,false,false},
    {script('Newspaper','Literature','literature',{tags={uninteresting=true}}),false,false,false},
    {script('Receipt','Junk','literature',{tags={uninteresting=true}}),false,false,false},
    {script('IDcard','Memento','literature',{tags={uninteresting=true}}),false,false,false},
    {script('Notebook','Literature','literature',{writeable=true}),false,false,true},
    {script('SheetPaper2','Literature','literature',{writeable=true}),false,false,true},
    {script('Map','Cartography','map'),true,false,false,'cartography'},
    {script('HollowBook','Literature','container'),false,false,false,'container'},
    {script('PhotoAlbum','Container','container'),false,false,false,'container'},
    {script('Pen','Tool','normal'),false,false,false},
}
local readableRule=assert(Tags.normalizeRule({include={'readable'},exclude={'literature'}}))
for _,case in ipairs(cases) do
    local definition=case[1]
    -- OC changes some script categories as well as physical inventory labels.
    for _,mode in ipairs({'native','inventory','script'}) do
        local oc=mode~='native'
        definition.category=definition.nativeCategory
        definition.uiCategory=oc and 'literatureReadable' or nil
        if oc and definition.kind=='normal' then definition.uiCategory='toolLiterature' end
        if oc and definition.skill then definition.uiCategory='literatureExperience' end
        if oc and definition.category=='RecipeResource' then definition.uiCategory='literatureRecipe' end
        if oc and definition.kind=='map' then definition.uiCategory='literatureCartography' end
        if oc and (definition.writeable or definition.id=='Base.Doodle') then definition.uiCategory='literatureWriteable' end
        if mode=='script' then definition.category=definition.uiCategory end
        for _,ids in ipairs({Tags.forScriptItem(definition),Tags.forItem(item(definition))}) do
            for index,id in ipairs({'readable','literature','writeable'}) do
                assert(Tags.matches(ids,{id})==case[index+1],definition.id..' incorrect '..id)
            end
            if case[5] then assert(Tags.matches(ids,{case[5]}),definition.id..' lost '..case[5]) end
            if oc and definition.nativeCategory=='RecipeResource' then assert(Tags.matches(ids,{'recipe'})) end
            assert(Tags.matchesRule(ids,readableRule)==(case[2] and not case[3]),'filter disagreed')
            local category=definition.uiCategory or definition.category
            assert(Tags.category(ids)==category and Tags.matches(ids,{'category:'..category}),
                definition.id..' lost exact category compatibility')
            assert(#ids>0,'unreadable item fell back to the old misleading category text')
        end
    end
end

local notebook=item(cases[15][1])
notebook.empty=false
assert(Tags.matches(Tags.forItem(notebook),{'readable','writeable'}),'written note was not readable')
notebook.empty=true
assert(not Tags.matches(Tags.forItem(notebook),{'readable'}),'cleared pages retained stale Readable')
notebook.empty=false
notebook.writeable=false
assert(not Tags.matches(Tags.forItem(notebook),{'writeable'}),'live capability was replaced by script default')
local newspaper=item(cases[11][1]);newspaper.md={printMedia='newspaper'}
assert(Tags.matches(Tags.forItem(newspaper),{'readable'}),'print-content Inspect lost Readable')
local printedBook=item(cases[1][1]);printedBook.md={printMedia='custom-print'}
assert(not Tags.matches(Tags.forItem(printedBook),{'literature'}),'print content retained the base recreational role')
local taught=script('CustomBook','Literature','literature',{boredom=-20,recipes={'Example'}})
assert(not Tags.matches(Tags.forScriptItem(taught),{'literature'}),'recipe book became recreational from mood effects')
taught.recipes=nil;taught.skill='Cooking'
assert(not Tags.matches(Tags.forScriptItem(taught),{'literature'}),'skill book became recreational from mood effects')
-- ReadType is an animation selector. Generic item inspection does not read content.
local receipt=cases[13][1];receipt.getReadType=function() return 'photo' end
assert(not Tags.matches(Tags.forScriptItem(receipt),{'readable'}),'animation implied readable content')
local generic=item(cases[20][1]);generic.inspect=function() error('do not invoke gameplay actions') end
assert(not Tags.matches(Tags.forItem(generic),{'readable'}),'generic Inspect became content viewing')
local manifest=script('StorageManifest','Literature','normal')
manifest.id='Quartermaster.StorageManifest'
for _,ids in ipairs({Tags.forScriptItem(manifest),Tags.forItem(item(manifest))}) do
    assert(Tags.matches(ids,{'readable'}) and not Tags.matches(ids,{'literature'}),
        'the mod-owned manifest content viewer lost Readable')
end
manifest.id='Other.StorageManifest'
assert(not Tags.matches(Tags.forScriptItem(manifest),{'readable'}),'custom viewer matched another module by suffix')
toolkitScriptCanBeWrite=nil
assert(Tags.matches(Tags.forItem(item(cases[1][1])),{'readable','literature'}),'live item requires optional Java bridge')
assert(Tags.matches(Tags.forScriptItem(cases[15][1]),{'writeable'}),'missing bridge erased the imported fallback')
assert(not Tags.matches(Tags.forScriptItem(cases[15][1]),{'readable'}),'missing bridge invented notebook content')
print('Reading tags passed: native roles, OC mappings, blank/written pages, print content, recipes/skills, maps, exact categories and filters.')
