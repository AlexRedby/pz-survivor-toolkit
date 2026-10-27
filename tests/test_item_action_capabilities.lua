local world = {}
isClient = function() return false end
ModData = {getOrCreate=function() return world end}
package.path = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/?.lua;' .. package.path
ItemType = {FOOD='food', NORMAL='normal', CONTAINER='container'}
ComponentType = {FluidContainer='fluid'}
getText = function(key) return key end
toolkitScriptHasEatMenu = function(script) return script.menu == nil or script.menu == 'Eat' end
InventoryItemFactory = {CreateItem=function() error('tag read created an item') end}
instanceItem = function() error('tag read instantiated an item') end
local recipes = {OpenTin={}}
getScriptManager = function() return {getCraftRecipe=function(_,id) return recipes[id] end} end
local Tags = require 'PZSurvivorToolkit/ItemTags'
local Properties = require 'PZSurvivorToolkit/ItemTagProperties'

local function script(name, hunger, cantEat, menu, opening, kind, fluid)
    return {name='Fixture.'..name, hunger=hunger, cantEat=cantEat, menu=menu, opening=opening,
        kind=kind or ItemType.FOOD, fluid=fluid,
        getFullName=function(self) return self.name end,
        getDisplayCategory=function(self) return self.kind==ItemType.FOOD and 'Food' or 'mechanicsFuel' end,
        isItemType=function(self,kind) return self.kind==kind end,
        isCantEat=function(self) return self.cantEat end,
        getOpeningRecipe=function(self) return self.opening end,
        getHungerChange=function(self) return self.hunger end,
        containsComponent=function(self,kind) return kind==ComponentType.FluidContainer and self.fluid or false end,
        InstanceItem=function() error('tag preview ran OnCreate') end}
end

local function item(definition)
    return {definition=definition, hunger=definition.hunger, menu=definition.menu,
        opening=definition.opening, fluid=definition.fluid, category=definition:getDisplayCategory(),
        getScriptItem=function(self) return self.definition end,
        getFullType=function(self) return self.definition.name end,
        getDisplayCategory=function(self) return self.category end,
        getCategory=function(self) return self.definition.kind==ItemType.FOOD and 'Food' or 'Normal' end,
        IsFood=function(self) return self.definition.kind==ItemType.FOOD end,
        getCustomMenuOption=function(self) return self.menu and getText('ContextMenu_'..self.menu) end,
        getOpeningRecipe=function(self) return self.opening end,
        getHungChange=function(self) return self.hunger end,
        getHungerChange=function(self) return self.hunger end,
        getBaseHunger=function(self) return self.hunger end,
        isFluidContainer=function(self) return self.fluid or false end}
end

local cases = {
    {script('Meal',-0.2),true},
    {script('RottenMeal',-0.1),true},
    {script('InedibleIngredient',-0.1,true),false},
    {script('Cigarette',0,false,'Smoke'),false},
    {script('CustomDrink',-0.1,false,'Drink'),false},
    {script('NoNutrition',0),false},
    {script('EmptyCustomMenu',-0.1,false,''),false},
    {script('ExplicitEat',-0.1,false,'Eat'),true},
    {script('OpenAndEat',0,true,nil,'OpenTin'),true},
    {script('MissingOpeningRecipe',0,true,nil,'Missing'),false},
    {script('NonFood',-0.2,false,nil,nil,ItemType.NORMAL),false},
}
for _,case in ipairs(cases) do
    local definition, expected = case[1], case[2]
    assert(Tags.matches(Tags.forScriptItem(definition),{'edible'})==expected,definition.name..' script Eat')
    assert(Tags.matches(Tags.forItem(item(definition)),{'edible'})==expected,definition.name..' physical Eat')
    assert(Tags.matchesScriptRule(definition,{include={'edible'},exclude={},mode='all'})==expected,
        definition.name..' Eat filter preview')
end
local live = item(cases[1][1])
live.menu='Smoke'
assert(not Tags.matches(Tags.forItem(live),{'edible'}),'script menu overrode the physical instance')
live.menu=nil; live.hunger=0
assert(not Tags.matches(Tags.forItem(live),{'edible'}),'live hunger change was cached')
toolkitScriptHasEatMenu=nil
assert(Properties.edible(cases[1][1])==nil,'missing script metadata guessed Eat')
assert(Properties.edible(cases[1][1],item(cases[1][1]))==true,'physical Eat requires Java metadata')
toolkitScriptHasEatMenu=function() return nil end
assert(Properties.edible(cases[1][1])==nil,'unsupported script metadata guessed Eat')

local bottle=script('Bottle',0,false,nil,nil,ItemType.NORMAL,true)
assert(Tags.matches(Tags.forScriptItem(bottle),{'container','liquid'}),'script fluid component lost capability')
local vessel=item(bottle)
for _,category in ipairs({'containerLiquid','foodNonPerishable','mechanicsFuel','medicalDisinfectant'}) do
    vessel.category=category
    assert(Tags.matches(Tags.forItem(vessel),{'container','liquid'}),'contents erased vessel roles: '..category)
    assert(Tags.matches(Tags.forItem(vessel),{'category:'..category}),'vessel role erased exact contents category')
end
vessel.category='mechanicsFuel'; vessel.fluid=false
assert(not Tags.matches(Tags.forItem(vessel),{'container'}),'script component overrode actual removed fluid component')
vessel.isFluidContainer=nil
vessel.getFluidContainer=function() return {} end
assert(Tags.matches(Tags.forItem(vessel),{'container','liquid'}),'fluid component getter fallback lost vessel')
assert(not Tags.matches(Tags.forScriptItem(script('SolidFuel',0,false,nil,nil,ItemType.NORMAL)),{'container'}),
    'a contents category alone invented a fluid vessel')

if NativeActionRoot then
    local file=assert(io.open(NativeActionRoot..'/client/ISUI/ISInventoryPaneContextMenu.lua','r'))
    local source=file:read('*a');file:close()
    local gate=assert(source:match('(if testItem:getCategory%(%) ~= "Food".-tests.isAllFood = false;.-end)'))
    local body=assert(source:match('    if tests.isAllFood then\r?\n(.-)    if tests.isAllPills then'))
    -- Execute the native option builder in a neutral player/tool context. Tagging
    -- describes an item's action, not temporary hunger or tool availability.
    local native=assert(loadstring('return function(testItem,context) local tests={isAllFood=true}; '..gate..
        '; local items={testItem};local player=0;local playerObj=CapabilityPlayer; if tests.isAllFood then '..body..' end'))()
    ISInventoryPane={getActualItems=function(items) return items end}
    ISInventoryPaneContextMenu={getContainers=function() return {} end,doEatOption=function(context,cmd) context:addOption(cmd) end}
    Moodles={};MoodleType={FOOD_EATEN='eaten'}
    CapabilityPlayer={getMoodles=function() return {getMoodleLevel=function() return 0 end} end}
    HandcraftLogic={new=function() return {setContainers=function() end,setRecipeFromContextClick=function() end,
        canPerformCurrentRecipe=function() return true end} end}
    for _,case in ipairs(cases) do
        local context={eat=false,addSubMenu=function() end}
        function context:addOption(cmd)
            if cmd==getText('ContextMenu_Eat') or cmd==getText('ContextMenu_OpenAndEat') then self.eat=true end
            return {}
        end
        context.getNew=function(self) return self end
        native(item(case[1]),context)
        assert(context.eat==case[2],case[1].name..' diverged from native Eat/OpenAndEat menu')
    end
    print('Native Eat/OpenAndEat option builder verified against capability cases.')
else
    print('SKIP native Eat menu comparison (NativeActionRoot not supplied)')
end
print('Item action capabilities passed: Eat versus Food/Smoke/Drink, opening recipes, live metadata and filled fluid vessels.')
