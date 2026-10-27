local worldTags = {}
isClient = function() return false end
ModData = {getOrCreate=function() return worldTags end}
package.path = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/?.lua;' .. package.path
ItemType = {CONTAINER='container'}
ItemTag = {WEARABLE='wearable'}
toolkitScriptCanBeEquipped = function(script) return script.equip ~= nil end
local Tags = require 'PZSurvivorToolkit/ItemTags'
local function script(id, category, kind, body, equip, world, nativeWearable)
    return {id=id,category=category,kind=kind,body=body,equip=equip,world=world,nativeWearable=nativeWearable,
        getFullName=function(self) return self.id end,
        getDisplayCategory=function(self) return self.category end,
        getBodyLocation=function(self) return self.body end,
        getWorldObjectSprite=function(self) return self.world end,
        isItemType=function(self,kind) return self.kind==kind end,
        hasTag=function(self,tag) return tag==ItemTag.WEARABLE and self.nativeWearable or false end}
end
local function item(definition)
    return {definition=definition,body=definition.body,equip=definition.equip,world=definition.world,
        getFullType=function(self) return self.definition.id end,
        getDisplayCategory=function(self) return self.definition.category end,
        getScriptItem=function(self) return self.definition end,
        getBodyLocation=function(self) return self.body end,
        canBeEquipped=function(self) return self.equip end,
        getWorldSprite=function(self) return self.world end,
        IsInventoryContainer=function(self) return self.definition.kind=='container' end,
        hasTag=function(self,tag) return self.definition:hasTag(tag) end,
        getContainer=function() error('parent inventory is not an item capability') end}
end
local function sprite(storage)
    return {getProperties=function() return {has=function(_,key) return key=='container' and storage end} end,
        getSpriteGrid=function(self) return self.grid end}
end
local sprites={dresser=sprite(true),crate=sprite(true),fridge=sprite(true),speaker=sprite(false),part=sprite(false)}
sprites.part.grid={getSpriteCount=function() return 2 end,
    getSpriteFromIndex=function(_,i) return i==0 and sprites.part or sprites.dresser end}
getSprite=function(name) return sprites[name] end
local cases={
    {script('Base.Shirt','clothingTop','clothing','Torso'),true,false,false},
    {script('Base.Hat_SurgicalMask','medicalWearable','clothing','Mask'),true,false,false},
    {script('Base.Hat_GasMask','clothingProtection','clothing','FullHat'),true,false,false},
    {script('Base.Bag_Schoolbag_Travel','Memento','container',nil,'Back'),true,true,false},
    {script('Base.Bag_Satchel','containerWearable','container',nil,'Satchel'),true,true,false},
    {script('Base.Bag_RifleCase','containerGeneral','container'),false,true,false},
    {script('Base.Bag_DoctorBag','containerWearable','container'),false,true,false},
    {script('Base.Plasticbag','Container','container'),false,true,false},
    {script('Base.ManPackRadio','survivalCommunication','radio',nil,nil,nil,true),true,false,false},
    {script('Base.Bandage','medicalFirstAid','normal'),false,false,false},
    {script('Base.Mov_WhiteFancyDrawers','furnitureStorage','moveable',nil,nil,'dresser'),false,true,true},
    {script('Base.Mov_MilitaryCrate','Furniture','moveable',nil,nil,'crate'),false,true,true},
    {script('Base.Mov_BlueFridge','furnitureRefrigeration','moveable',nil,nil,'fridge'),false,true,true},
    {script('Base.Mov_WoodSpeakerCabinet','furnitureStorage','moveable',nil,nil,'speaker'),false,false,true},
    {script('Mod.CupboardPart','Mod.Category','moveable',nil,nil,'part'),false,true,true},
    {script('Base.Mov_FancyChestnutDrawers','furnitureSurface','moveable',nil,nil,'dresser'),false,true,true},
}
local ownedCategories={
    ['Base.Bag_Schoolbag_Travel']='containerWearable',
    ['Base.Plasticbag']='containerGeneral',
    ['Base.Mov_MilitaryCrate']='furnitureStorage',
}
local notWornContainers=assert(Tags.normalizeRule({include={'container'},exclude={'wearable'}}))
for _,case in ipairs(cases) do
    local definition=case[1]
    for _,projection in ipairs({{Tags.forItem(item(definition)),definition.category},
        {Tags.forScriptItem(definition),ownedCategories[definition.id] or definition.category}}) do
        local ids,category=projection[1],projection[2]
        for i,id in ipairs({'wearable','container','furniture'}) do
            assert(Tags.matches(ids,{id})==case[i+1],definition.id..' incorrect '..id)
        end
        assert(Tags.matchesRule(ids,notWornContainers)==(case[3] and not case[2]),definition.id..' filter mismatch')
        assert(Tags.category(ids)==category,'capability refinement lost projected exact category')
        assert(Tags.matches(ids,{'category:'..category}),'saved exact-category rule no longer matches')
    end
end
for _,ids in ipairs({Tags.forScriptItem(cases[#cases][1]),Tags.forItem(item(cases[#cases][1]))}) do
    assert(Tags.matches(ids,{'furniture','surface','storage','container'}),
        'storage furniture that is also a native crafting surface lost one of its roles')
    assert(Tags.matches(ids,{'category:furnitureSurface'}),'dresser correction broke saved exact-category selection')
end
local bag=script('Mod.DynamicBag','containerWearable','container',nil,'Back')
local live=item(bag)
live.equip=nil
assert(not Tags.matches(Tags.forItem(live),{'wearable'}),'script slot overrode changed physical item')
bag.equip=nil
assert(not Tags.matches(Tags.forScriptItem(bag),{'wearable'}),'script slot was cached')
local furniture=item(cases[11][1])
furniture.world='speaker'
assert(not Tags.matches(Tags.forItem(furniture),{'container'}),'script sprite overrode changed furniture part')
furniture.world='not-loaded'
assert(not Tags.matches(Tags.forItem(furniture),{'container'}),'unknown sprite invented storage')
sprites['not-loaded']=sprites.crate
assert(Tags.matches(Tags.forItem(furniture),{'container'}),'late sprite load was cached as absent')
toolkitScriptCanBeEquipped=nil
assert(Tags.matches(Tags.forScriptItem(cases[1][1]),{'wearable'}),'body-slot detection requires Java helper')
assert(Tags.matches(Tags.forScriptItem(cases[9][1]),{'wearable'}),'native wearable tag requires Java helper')
assert(Tags.matches(Tags.forItem(item(cases[4][1])),{'wearable'}),'physical bag requires Java helper')
assert(Tags.matches(Tags.forScriptItem(cases[5][1]),{'wearable'}),'missing optional helper erased imported tags')
print('Native tag properties passed: wearable/body/bag/medical/radio, hand-held negatives, storage furniture/grids, live metadata, exact categories and exclusion rules.')
