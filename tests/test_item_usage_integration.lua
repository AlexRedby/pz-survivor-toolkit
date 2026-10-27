package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/?.lua;'..package.path
local world={}
isClient=function()return false end
ModData={getOrCreate=function()return world end}
PZSurvivorToolkit={Settings={itemTags=function()return true end}}
ItemType={FOOD='food',NORMAL='normal',DRAINABLE='drainable',LITERATURE='literature'}
ItemTag={CAN_BE_WASHED='wash',IS_FIRE_FUEL='fuel',IS_FIRE_FUEL_SINGLE_USE='single'}
ComponentType={FluidContainer='fluid'}
FluidCategory={Beverage='beverage',Alcoholic='alcoholic',Fuel='fuel'}
toolkitScriptBandagePower=function(s)return s.bandage or 0 end
toolkitScriptAlcoholPower=function(s)return s.alcohol or 0 end
package.loaded['PZSurvivorToolkit/ItemCategories']={forScript=function(s)return s.category end}
local Tags=require 'PZSurvivorToolkit/ItemTags'
local Usage=require 'PZSurvivorToolkit/ItemUsageTags'
local function rule(include,exclude)return assert(Tags.normalizeRule({include=include or {},exclude=exclude or {}}))end
local function script(name,category,kind)
    return {name=name,category=category,kind=kind or ItemType.NORMAL,
        getFullName=function(s)return s.name end,getDisplayCategory=function(s)return s.category end,
        isItemType=function(s,k)return s.kind==k end,hasTag=function(s,t)return s[t]==true end,
        getFireFuelRatio=function(s)return s.ratio or 0 end,getItemAfterCleaning=function(s)return s.cleaning end,
        getComponentScriptFor=function(s)return s.component end}
end
local function item(s)
    return {s=s,uses=1,getScriptItem=function(i)return i.s end,getFullType=function(i)return i.s.name end,
        getDisplayCategory=function(i)return i.s.category end,IsDrainable=function(i)return i.s.kind==ItemType.DRAINABLE end,
        getBandagePower=function(i)return i.s.bandage or 0 end,getAlcoholPower=function(i)return i.s.alcohol or 0 end,
        getItemAfterCleaning=function(i)return i.s.cleaning end,hasTag=function(i,t)return i.s[t]==true end,
        getFireFuelRatio=function(i)return i.s.ratio or 0 end,getCurrentUsesFloat=function(i)return i.uses end,
        getCurrentUses=function(i)return math.floor(i.uses)end,getFluidContainer=function(i)return i.container end}
end
local cloth=script('Fixture.DirtyCloth','craftingTailoring_cloth')
cloth.bandage,cloth.wash,cloth.cleaning=0.5,true,'Base.RippedSheets'
local physical=item(cloth)
assert(Tags.matches(Tags.forItem(physical),{'bandage','dirty','medical','firstaid','cloth'}))
assert(Tags.matchesScriptRule(cloth,rule({'bandage','dirty'})))
world.types['fixture.dirtycloth']={dirty='remove'}
assert(not Tags.matchesScriptRule(cloth,rule({'dirty'})) and not Tags.matches(Tags.forItem(physical),{'dirty'}))
world.types={}
local function snapshot(s,encoded,delta,fluid)
    return Tags.forSnapshot(s,s.name,s.category,nil,delta,nil,nil,fluid,encoded)
end
assert(Tags.matches(snapshot(cloth,Usage.encode(Usage.read(cloth,physical))),{'bandage','dirty'}))
assert(not Tags.matches(snapshot(cloth,nil),{'bandage','dirty'},'any'),'old snapshot fabricated medical state')

local propane=script('Base.PropaneTank','toolWelding',ItemType.DRAINABLE)
local tank=item(propane)
assert(Tags.matches(Tags.forItem(tank),{'fuel','tool','welding'}))
tank.uses=0
assert(not Tags.matches(Tags.forItem(tank),{'fuel'}))
assert(Tags.matchesScriptRule(propane,rule({'fuel'})) and Tags.matchesScriptRule(propane,rule({}, {'fuel'})))
local empty=script('Base.PropaneTankEmpty','mechanicsFuel')
assert(not Tags.matches(Tags.forItem(item(empty)),{'fuel'}),'legacy empty tank category retained Fuel')
assert(not Tags.matches(snapshot(empty,nil),{'fuel'}),'uncaptured fuel snapshot inferred contents')
assert(Tags.matches(snapshot(empty,nil,{fuel='add'}),{'fuel'}),'manual snapshot correction lost')
local charcoal=script('Base.Charcoal','craftingMetalworking_material');charcoal.fuel,charcoal.ratio=true,2
assert(Tags.matches(Tags.forItem(item(charcoal)),{'fuel','metalworking','material'}))

local function list(values)return {size=function()return #values end,get=function(_,i)return values[i+1]end}end
local water={isCategory=function(_,id)return id=='beverage'end,getProperties=function()return {getAlcohol=function()return 0 end}end}
local whiskey={isCategory=function(_,id)return id=='beverage' or id=='alcoholic'end,
    getProperties=function()return {getAlcohol=function()return 0.4 end}end}
local petrol={isCategory=function(_,id)return id=='fuel'end,getProperties=function()return {getAlcohol=function()return 0 end}end}
Fluid={getAllFluids=function()return list({water,whiskey,petrol})end}
local bottle=script('Fixture.Bottle','foodBeverage_alcoholic')
bottle.component={getCapacity=function()return 1 end,isInitialFluidsIsRandom=function()return true end,
    getInitialFluids=function()return list({
        {getFluid=function()return water end,getPercentage=function()return 1 end},
        {getFluid=function()return whiskey end,getPercentage=function()return 1 end},
        {getFluid=function()return petrol end,getPercentage=function()return 1 end}})end,
    getInitialAmount=function()error('preview consumed RNG')end}
local live=item(bottle)
local amount,strength,current=1,0.4,whiskey
live.container={isEmpty=function()return amount==0 end,getAmount=function()return amount end,
    isCategory=function(_,id)return amount>0 and current:isCategory(id)end,
    getSpecificFluidAmount=function(_,f)return f==current and amount or 0 end,
    getProperties=function()return {getAlcohol=function()return amount*strength end}end}
local suitable=Tags.forItem(live)
assert(Tags.matches(suitable,{'beverage','alcoholic','disinfectant','medical'}))
local captured=Usage.encode(Usage.read(bottle,live))
amount=0.15
assert(not Tags.matches(Tags.forItem(live),{'disinfectant'}),'native strict amount boundary lost')
assert(Tags.signature(suitable)~=Tags.signature(Tags.forItem(live)),'stacks merged different usable quantities')
amount,strength=1,0.2
assert(not Tags.matches(Tags.forItem(live),{'disinfectant'}),'dilution retained disinfectant capability')
assert(Tags.matches(snapshot(bottle,captured,nil,'alcoholic'),{'disinfectant'}))
assert(not Tags.matches(snapshot(bottle,nil,nil,'alcoholic'),{'disinfectant'}),'old alcohol snapshot invented disinfection')
current,strength=petrol,0
assert(Tags.matches(Tags.forItem(live),{'fuel'}) and not Tags.matches(Tags.forItem(live),{'beverage','disinfectant'},'any'))
amount=0
assert(not Tags.matches(Tags.forItem(live),{'fuel','beverage','disinfectant'},'any'))
assert(Tags.matchesScriptRule(bottle,rule({'disinfectant','alcoholic'})))
assert(Tags.matchesScriptRule(bottle,rule({'fuel'},{'beverage'})))
assert(not Tags.matchesScriptRule(bottle,rule({'fuel','beverage'})),'preview combined two different random fluids')
assert(not Tags.matchesScriptRule(bottle,rule({'disinfectant'},{'alcoholic'})),'preview combined water and whiskey roles')
assert(Tags.matchesScriptRule(bottle,rule({'beverage'},{'medical'})),'medical role leaked from another possible state')
world.types['fixture.bottle']={fuel='add'}
assert(Tags.matchesScriptRule(bottle,rule({'fuel','disinfectant'})),'manual changes were applied before possible states')
for _,id in ipairs({'bandage','disinfectant','dirty','fuel'})do assert(Tags.requiresItemRule(id))end
print('medical/fuel integration: actual states, legacy negatives, joint previews, snapshots and manual overrides passed')
