package.path = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/?.lua;'
    .. ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/?.lua;' .. package.path
local function list(values)
    return {size=function() return #values end, get=function(_,i) return values[i+1] end}
end
string.contains = function(text, part) return text:find(part, 1, true) ~= nil end
ItemType = {FOOD='Food', CLOTHING='Clothing', LITERATURE='Literature', WEAPON='Weapon', NORMAL='Normal'}
ComponentType = {FluidContainer='FluidContainer'}
FluidCategory = {Medical='Medical', Alcoholic='Alcoholic', Beverage='Beverage', Fuel='Fuel', HairDyes='HairDyes',
    Dyes='Dyes', Paint='Paint', Water='Water', Hazardous='Hazardous'}
WeaponCategory = {FIREARM='Firearm', SMALL_BLADE='SmallBlade', LONG_BLADE='LongBlade',
    SMALL_BLUNT='SmallBlunt', BLUNT='Blunt', AXE='Axe', SPEAR='Spear'}
ItemBodyLocation = {}
SkillBook = {Carpentry={}}
ItemTag = {IS_SEED='IsSeed'}
OrganizedCategories = setmetatable({}, {__index=function() error('removed runtime provider accessed') end})
local Categories = require 'PZSurvivorToolkit/ItemCategories'
local function script(name, category, kind)
    return {name=name, category=category, kind=kind or ItemType.NORMAL,
        getFullName=function(self) return self.name end,
        getDisplayCategory=function(self) return self.category end,
        getItemType=function(self) return self.kind end,
        containsComponent=function(self) return self.fluidScript~=nil end,
        getComponentScriptFor=function(self) return self.fluidScript end,
        getBodyLocation=function(self) return self.body end,
        getDaysTotallyRotten=function(self) return self.rotten or 100000000 end,
        hasTag=function(self) return self.seed==true end,
        isRanged=function(self) return self.ranged==true end,
        getAmmoType=function(self) return self.ammo end,
        containsWeaponCategory=function(self, value) return self.weapon==value end,
        getSkillTrained=function(self) return self.skill end,
        getLearnedRecipes=function(self) return list(self.recipes or {}) end,
        getStressChange=function(self) return self.stress or 0 end,
        getBoredomChange=function() return 0 end, getUnhappyChange=function() return 0 end,
        DoParam=function() error('classification modified a ScriptItem loot category') end}
end
local function item(source)
    return {source=source, category=source.category, md={},
        getScriptItem=function(self) return self.source end,
        getDisplayCategory=function(self) return self.category end,
        setDisplayCategory=function(self,value) self.category=value end,
        getModData=function(self) return self.md end, hasModData=function() return true end,
        isFluidContainer=function(self) return self.fluid~=nil end,
        getFluidContainer=function(self) return self.fluid end,
        getItemType=function(self) return self.source.kind end,
        getDaysTotallyRotten=function(self) return self.source:getDaysTotallyRotten() end,
        getMediaData=function(self) return self.media end}
end
for _, vector in ipairs({{'Base.Thread','Material','craftingTailoring_material'},
    {'base.Primitive_Bow','Weapon','weaponRanged'}, {'Base.VHS_Retail','Entertainment','entertainmentVideo'},
    {'Base.Axe','Weapon','weaponAxe'}, {'Base.CarrotBagSeed2_Empty','RecipeResource','farmingSeed'},
    {'Mod.Unknown','NewModCategory','NewModCategory'}, {'Mod.Tool','Tool','toolSurvival'},
    {'Mod.Preserved','customOpaque_category','customOpaque_category'}}) do
    local source=script(vector[1],vector[2])
    assert(Categories.forScript(source)==vector[3], vector[1] .. ' classification changed')
    local live=item(source)
    Categories.prepareContainer({getItems=function() return list({live}) end})
    assert(live.category==vector[3] and source.category==vector[2], 'instance/script boundary broken')
end
local food=script('Example.NewFood','Food',ItemType.FOOD);food.rotten=10
assert(Categories.forScript(food)=='foodPerishable')
food.rotten=100000000;assert(Categories.forScript(food)=='foodNonPerishable')
food.seed=true;assert(Categories.forScript(food)=='farmingSeed','plantable food lost seed classification')
food.seed=false;food.body='Jacket';assert(Categories.forScript(food)=='clothingOuterwear','malformed clothing fell into food')
local firearm=script('Example.Gun','Weapon',ItemType.WEAPON);firearm.ammo='Base.308Bullets';firearm.weapon=WeaponCategory.BLUNT
assert(Categories.forScript(firearm)=='weaponFirearm','gun bashing displaced firearm classification')
local literature=script('Example.Recipe','Literature',ItemType.LITERATURE);literature.recipes={'MakeSomething'}
assert(Categories.forScript(literature)=='literatureRecipe')
literature.skill='Carpentry';assert(Categories.forScript(literature)=='literatureExperience')

local Rules=require 'PZSurvivorToolkit/ItemCategoryRules'
local lateBook=script('WPANC.BookArchery1','SkillBook',ItemType.LITERATURE);lateBook.skill='WPANCArchery'
getAllItems=function()return list({lateBook})end
Rules.snapshotScripts()
SkillBook.WPANCArchery={}
assert(Categories.forScript(lateBook)=='literatureWriteable','late SkillBook registration reclassified a boot-time claim')
getAllItems=nil

local furniture=script('Base.FridgeOpen2','Furniture')
local closed=Categories.forScript(script('Base.Fridge','Furniture'))
assert(Categories.forScript(furniture)==closed,'open furniture lost precise closed category')
local override=item(script('Base.Thread','Material'));override.md.OC_DisplayCategory='My.ExactSavedCategory'
assert(Categories.prepareItem(override)=='My.ExactSavedCategory','saved per-instance category lost')

local function fluid(name, category)
    return {getFluidTypeString=function() return name end,isCategory=function(_,value) return value==category end}
end
local fuel, water, medical = fluid('Petrol','Fuel'), fluid('Water','Water'), fluid('RubbingAlcohol','Medical')
local container={entries={{fluid=fuel,amount=1}}, amount=1}
function container:getAmount() return self.amount end
function container:isEmpty() return self.amount<=0 end
function container:getPrimaryFluid() return self.entries[1] and self.entries[1].fluid end
function container:getContainerName() return 'Bottle' end
function container:getSpecificFluidAmount(value)
    for _,entry in ipairs(self.entries) do if entry.fluid==value then return entry.amount end end
    return 0
end
function container:createFluidSample()
    local entries=self.entries
    return {size=function() return #entries end,getFluid=function(_,index) return entries[index+1].fluid end,release=function() end}
end
local bottle=item(script('Base.WaterBottle','Water'));bottle.fluid=container
Categories.prepareItem(bottle);assert(bottle.category=='mechanicsFuel','live fuel kept bottle category')
container.entries={{fluid=fuel,amount=1},{fluid=water,amount=1}};container.amount=2
Categories.prepareItem(bottle);assert(bottle.category=='containerLiquid','even mix did not choose newly added water')
container.entries={{fluid=fuel,amount=3},{fluid=water,amount=1}};container.amount=4
Categories.prepareItem(bottle);assert(bottle.category=='mechanicsFuel','majority did not win fluid mixture')
bottle.category='Water';Categories.prepareItem(bottle);assert(bottle.category=='mechanicsFuel','save reload lost cached fluid category')
container.amount=0;container.entries={}
Categories.prepareItem(bottle);assert(bottle.category==Categories.forScript(bottle.source),'empty container retained old fluid category')
container.amount=1;container.entries={{fluid=medical,amount=1}}
Categories.prepareItem(bottle);assert(bottle.category=='medicalFirstAid')
bottle.md.OC_DisplayCategory='My.FluidOverride'
container.entries={{fluid=fuel,amount=2}};container.amount=2
Categories.prepareItem(bottle);assert(bottle.category=='My.FluidOverride','fluid sorter replaced migrated instance override')

local function media(id, codes)
    return {getId=function() return id end,getLineCount=function() return #codes end,
        getLine=function(_,index) return {getCodes=function() return codes[index+1] end} end}
end
local tape=item(script('Base.VHS_Retail','Entertainment'))
tape.media=media('recipe',{'BOR-1,RCP=MakeSushi'})
Categories.prepareItem(tape);assert(tape.category=='entertainmentVideo_recipe')
tape.media=media('skill',{'RCP=MakeSushi,CRP+1'})
Categories.prepareItem(tape);assert(tape.category=='entertainmentVideo_experience','recipe displaced XP tape classification')
tape.media=nil;Categories.prepareItem(tape);assert(tape.category=='entertainmentVideo','changed media binding stayed refined')
assert(tape.source.category=='Entertainment')

-- The product hook prepares before native grouping and also installs on a new
-- CleanUI class created by an inventory-mode toggle.
local callbacks={}
Events={}
for _,name in ipairs({'OnGameBoot','OnGameStart','OnCreatePlayer'}) do
    Events[name]={Add=function(fn) callbacks[name]=fn end}
end
CleanUI_RegisterInventoryUiToggleCallback=function(fn) callbacks.toggle=fn end
local function paneClass()
    return {refreshContainer=function(pane)
        assert(pane.inventory:getItems():get(0).category=='craftingTailoring_material','native grouping saw loot category')
        pane.called=true;return 'native-result'
    end}
end
ISInventoryPane=paneClass()
local requireLua=require
require=function(name) if name=='ISUI/ISInventoryPane' then return end return requireLua(name) end
dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/ToolkitItemCategories.lua')
callbacks.OnGameStart()
local liveThread=item(script('Base.Thread','Material'))
local pane=setmetatable({inventory={getItems=function() return list({liveThread}) end}},{__index=ISInventoryPane})
assert(pane:refreshContainer()=='native-result' and pane.called)
CleanUI_Clean_ISInventoryPane=paneClass();callbacks.toggle()
liveThread.category='Material'
local clean=setmetatable({inventory=pane.inventory},{__index=CleanUI_Clean_ISInventoryPane})
assert(clean:refreshContainer()=='native-result' and clean.called)
print('ItemCategories: owned exact/fallback classifications, migrated overrides, mixtures, media, loot invariance and native/CleanUI refresh passed.')
