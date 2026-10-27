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
        getFireFuelRatio=function(i)return i.s.ratio or 0 end,getCurrentUsesFloat=function(i)return i.fraction or i.uses end,
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

world.types={}
ItemTag.START_FIRE,ItemTag.ALREADY_COOKED='startfire','alreadyCooked'
local lighter=script('Base.Lighter','survivalLighting',ItemType.DRAINABLE)
lighter.startfire,lighter.fuel=true,true
local flame=item(lighter)
assert(Tags.matches(Tags.forItem(flame),{'ignite','fuel','lighting'}))
flame.uses=0
assert(not Tags.matches(Tags.forItem(flame),{'ignite','fuel'},'any'))
assert(Tags.matchesScriptRule(lighter,rule({'ignite','fuel'})))
assert(not Tags.matchesScriptRule(lighter,rule({'ignite'},{'fuel'})), 'one shared empty resource gained incompatible roles')
assert(Tags.matches(Tags.choices(Tags.automaticForScriptItem(lighter)),{'ignite'}))

local battery=script('Base.Battery','craftingElectrical',ItemType.DRAINABLE)
local charge=item(battery)
local charged=Tags.forItem(charge)
assert(Tags.matches(charged,{'crafting','electrical'}) and not Tags.matches(charged,{'junk'}))
charge.uses,charge.fraction=1,0.001
assert(not Tags.matches(Tags.forItem(charge),{'junk'}), 'fractional charge was discarded as empty')
charge.uses,charge.fraction=0,nil
local spent=Tags.forItem(charge)
assert(Tags.matches(spent,{'junk'}) and not Tags.matches(spent,{'crafting','electrical'},'any'))
assert(Tags.signature(spent)~=Tags.signature(charged), 'empty and charged battery stacks merged')
assert(Tags.matchesScriptRule(battery,rule({'junk'})))
assert(Tags.matchesScriptRule(battery,rule({'electrical'},{'junk'})))
assert(not Tags.matchesScriptRule(battery,rule({'junk','electrical'})), 'preview merged spent and charged states')
-- A native item with two use-dependent roles shares one integer remaining use.
battery.startfire=true
assert(not Tags.matchesScriptRule(battery,rule({'electrical'},{'ignite'})), 'preview invented charge without a remaining use')
assert(not Tags.matchesScriptRule(battery,rule({'junk','ignite'})), 'empty battery gained usable ignition')
battery.startfire=nil
local batteryState=Usage.encode(Usage.read(battery,charge))
assert(#batteryState==10 and Tags.matches(snapshot(battery,batteryState),{'junk'}))
assert(not Tags.matches(snapshot(battery,nil),{'junk'}), 'old battery snapshot fabricated depletion')
assert(not Tags.matches(snapshot(battery,'0000'),{'junk'}), 'legacy four-role snapshot fabricated depletion')
assert(Tags.matches(snapshot(battery,batteryState,{electrical='add'}),{'junk','electrical'}))
world.types['base.battery']={electrical='add'}
assert(Tags.matchesScriptRule(battery,rule({'junk','electrical'})), 'manual battery role lost to automatic state')
world.types={}
for _,name in ipairs({'Base.CarBattery1','Base.CarBattery2','Base.CarBattery3','Mod.Battery'})do
    local other=item(script(name,'mechanicsVehiclePart',ItemType.DRAINABLE));other.uses=0
    assert(not Tags.matches(Tags.forItem(other),{'junk'}), 'depletion rule escaped ordinary Base.Battery')
end

local spray=script('Base.GardeningSprayMilk','farmingTreatment',ItemType.DRAINABLE)
local garden=item(spray)
assert(Tags.matches(Tags.forItem(garden),{'farming','treatment'}))
garden.uses=0
assert(Tags.matches(Tags.forItem(garden),{'farming'}) and not Tags.matches(Tags.forItem(garden),{'treatment'}))
assert(Tags.matchesScriptRule(spray,rule({'treatment'})) and Tags.matchesScriptRule(spray,rule({}, {'treatment'})))
assert(not Tags.matches(snapshot(spray,nil),{'treatment'}), 'old spray snapshot inferred full contents')
local emptySpray=script('Base.GardeningSprayEmpty','farmingTreatment')
assert(Tags.matches(Tags.forItem(item(emptySpray)),{'farming'})
    and not Tags.matchesScriptRule(emptySpray,rule({'treatment'})))
assert(Tags.matches(Tags.forItem(item(script('Base.Pills','medicalTreatment'))),{'medical','treatment'}),
    'plant treatment rules removed an unrelated medical role')

Fishing={lure={Worms={['Base.Worm']={}},Flesh={['Base.FishFillet']={}},Plant={['Base.Bread']={}}}}
TrapAnimals={{baits={['Base.Worm']=50,['Base.Bread']=50}}}
local function food(name,category,cookable)
    local s=script(name,category,ItemType.FOOD)
    s.isIsCookable=function()return cookable end
    local i=item(s)
    i.isCooked=function(i)return i.cooked==true end
    i.isBurnt=function(i)return i.burnt==true end
    i.isCookable=function()return cookable end
    i.haveExtraItems=function(i)return i.extra==true end
    i.getCustomMenuOption=function(i)return i.menu end
    return s,i
end
local worm,wriggler=food('Base.Worm','survivalFishing_baitLure',true)
assert(Tags.matches(Tags.forItem(wriggler),{'bait','fishing','trapping'}))
wriggler.cooked=true
assert(not Tags.matches(Tags.forItem(wriggler),{'bait','fishing','trapping'},'any'))
assert(not Tags.matchesScriptRule(worm,rule({'bait','cooked'})), 'preview combined cooked and uncooked bait')
assert(Tags.matchesScriptRule(worm,rule({'bait','raw','fishing','trapping'})))
local fillet,fish=food('Base.FishFillet','foodPerishable_meat',true)
assert(Tags.matches(Tags.forItem(fish),{'bait','fishing','meat'}) and not Tags.matches(Tags.forItem(fish),{'trapping'}))
local fishState=Usage.encode(Usage.read(fillet,fish))
fish.cooked=true
assert(not Tags.matches(Tags.forItem(fish),{'bait'}))
assert(Tags.matches(snapshot(fillet,fishState),{'bait','fishing'}))
assert(not Tags.matches(snapshot(fillet,'0000'),{'bait'}), 'old food snapshot inferred bait eligibility')
local bread,loaf=food('Base.Bread','foodPerishable',false)
assert(Tags.matches(Tags.forItem(loaf),{'bait','fishing','trapping'}))
loaf.extra=true
assert(Tags.matches(Tags.forItem(loaf),{'bait','fishing'}) and not Tags.matches(Tags.forItem(loaf),{'trapping'}))
local ready=food('Base.FishFillet','foodPerishable_meat',false);ready.alreadyCooked=true
assert(not Tags.matchesScriptRule(ready,rule({'bait'})), 'inherently cooked food acquired uncooked bait preview')
world.types['base.worm']={bait='add'}
assert(Tags.matchesScriptRule(worm,rule({'bait','cooked'})), 'manual bait addition lost to preview constraint')
world.types={}

-- Complete native recipe metadata flows through the real supply reader.
ResourceType={Item='item'}
local glue=script('Base.Glue','toolLiterature',ItemType.DRAINABLE)
local clothSupply=script('Base.RippedSheets','craftingTailoring_cloth')
local function input(kept,damaged,items)
    return {getResourceType=function()return 'item'end,isKeep=function()return kept end,
        isDamaged=function()return damaged end,isTool=function()return false end,
        isApplyOnTick=function()return false end,hasConsumeFromItem=function()return false end,
        hasCreateToItem=function()return false end,isReplace=function()return false end,
        getIntAmount=function()return 2 end,getPossibleInputItems=function()return list(items or {})end}
end
local recipe={getName=function()return 'FixWithGlue'end,
    getInputs=function()return list({input(true,true),input(false,false,{glue,clothSupply})})end}
toolkitRecipeOnCreate=function()return 'RecipeCodeOnCreate.genericFixing'end
toolkitRecipeHasItemTest=function()return false end
local recipes=list({recipe})
local manager={getAllCraftRecipes=function()return recipes end,getAllItems=function()return list({lighter})end}
getScriptManager=function()return manager end
local glueItem=item(glue)
assert(Tags.matches(Tags.forItem(glueItem),{'tool','repair','maintenance'}))
glueItem.uses=0
assert(not Tags.matches(Tags.forItem(glueItem),{'repair'}))
assert(Tags.matchesScriptRule(glue,rule({'repair'})) and Tags.matchesScriptRule(glue,rule({}, {'repair'})))
assert(Tags.matches(Tags.forItem(item(clothSupply)),{'repair','tailoring','cloth'}))
assert(Tags.matches(Tags.allIds(),{'ignite'}), 'new dynamic-only role missing from global choices')
for _,id in ipairs({'bait','fishing','trapping','ignite','treatment','repair','junk','electrical','crafting'})do
    assert(Tags.requiresItemRule(id), 'category routing bypasses physical state for '..id)
end
print('bait, supplies, ignition, plant treatment and spent-battery integration passed')
