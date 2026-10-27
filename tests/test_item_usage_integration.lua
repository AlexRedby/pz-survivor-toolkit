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

-- Fitness keeps the native and forged equipment out of the imported mixed group.
for _, name in ipairs({'Base.DumbBell','Base.BarBell','Base.DumbBell_Forged','Base.BarBell_Forged'}) do
    local gear=script(name,'characterHygieneFitness')
    assert(Tags.matches(Tags.forItem(item(gear)),{'fitness','character'}))
    assert(not Tags.matches(Tags.forScriptItem(gear),{'hygiene'}))
    assert(Tags.matchesScriptRule(gear,rule({'fitness'},{'hygiene'})))
end
local soap=script('Base.Soap2','characterHygieneFitness')
assert(Tags.matches(Tags.forScriptItem(soap),{'hygiene'}) and not Tags.matches(Tags.forScriptItem(soap),{'fitness'}))
FitnessExercises={exercisesType={custom={item='Fixture.ExerciseGear'}}}
local extra=script('Fixture.ExerciseGear','characterHygieneFitness')
assert(Tags.matches(Tags.forScriptItem(extra),{'fitness'}) and not Tags.matches(Tags.forScriptItem(extra),{'hygiene'}))
FitnessExercises=nil
for _, id in ipairs({'fitness','hygiene','dirty','smelting'}) do assert(Tags.requiresItemRule(id)) end

-- Real laundry reader feeds physical tags, state alternatives and stored snapshots.
ItemType.CLOTHING,ItemType.CONTAINER='clothing','container'
ItemTag.BREAK_WHEN_WET='breakwet'
local function list(values)return {size=function()return #values end,get=function(_,i)return values[i+1]end}end
BloodClothingType={getCoveredParts=function(types)return types end}
toolkitItemLaundryDirty=function(i)return i.stains end
local shirt=script('Fixture.Shirt','clothingTop',ItemType.CLOTHING)
shirt.isHidden=function()return false end
shirt.getBloodClothingType=function()return list({'Torso'})end
local laundryItem=item(shirt)
laundryItem.isHidden=shirt.isHidden
laundryItem.stains=true
assert(Tags.matches(Tags.forItem(laundryItem),{'clothing','dirty'}))
local dirtyMask=Usage.encode(Usage.read(shirt,laundryItem))
assert(Tags.matches(snapshot(shirt,dirtyMask),{'dirty'}))
laundryItem.stains=false
local cleanMask=Usage.encode(Usage.read(shirt,laundryItem))
assert(cleanMask~=dirtyMask and not Tags.matches(snapshot(shirt,cleanMask),{'dirty'}))
assert(not Tags.matches(Tags.forItem(laundryItem),{'dirty'}))
assert(not Tags.matches(snapshot(shirt,nil),{'dirty'}),'old snapshot guessed laundry state')
assert(not Tags.matches(Tags.forScriptItem(shirt),{'dirty'}),'definition claimed a current stain')
assert(Tags.matches(Tags.choices(Tags.forScriptItem(shirt)),{'dirty'}))
assert(Tags.matchesScriptRule(shirt,rule({'dirty'})) and Tags.matchesScriptRule(shirt,rule({}, {'dirty'})))
local bridge=toolkitItemLaundryDirty;toolkitItemLaundryDirty=nil
assert(Usage.read(shirt,laundryItem).dirty==nil,'missing bridge guessed clean')
toolkitItemLaundryDirty=bridge
world.types['fixture.shirt']={dirty='remove'}
assert(not Tags.matchesScriptRule(shirt,rule({'dirty'})))
world.types={}

-- Composition must not tie independent stains to remaining material/uses.
local Smelting=require 'PZSurvivorToolkit/ItemSmeltingTags'
local readSmelting=Smelting.read
Smelting.read=function(s,i)
    if s==shirt then
        if i then return i.uses>0 end
        return nil,{false,true}
    end
    return readSmelting(s,i)
end
for _, withDirty in ipairs({false,true})do
    for _, withSmelting in ipairs({false,true})do
        local included,excluded={},{}
        for id,enabled in pairs({dirty=withDirty,smelting=withSmelting})do
            local target=enabled and included or excluded;target[#target+1]=id
        end
        assert(Tags.matchesScriptRule(shirt,rule(included,excluded)),'independent stains/material states collapsed')
    end
end
laundryItem.stains,laundryItem.uses=true,1
local current=Usage.encode(Usage.read(shirt,laundryItem))
assert(#current==11 and Tags.matches(snapshot(shirt,current),{'dirty','smelting'}))
assert(not Tags.matches(snapshot(shirt,current:sub(1,10)),{'smelting'}),'legacy snapshot fabricated smelting')
laundryItem.uses=0
local exhausted=Usage.encode(Usage.read(shirt,laundryItem))
assert(current~=exhausted and not Tags.matches(snapshot(shirt,exhausted),{'smelting'}))
assert(Tags.matches(snapshot(shirt,exhausted,{smelting='add'}),{'smelting'}))
Smelting.read=readSmelting

if NativeActionRoot then
    local f=assert(io.open(NativeActionRoot..'/shared/Definitions/FitnessExercises.lua','r'))
    local content=f:read('*a');f:close()
    assert(content:find('item = "Base.BarBell"',1,true) and content:find('item = "Base.DumbBell"',1,true))
end

-- A refill is a fuel supply, including partial contents, rather than a lamp.
local refill=script('Base.Propane_Refill','survivalLighting',ItemType.DRAINABLE)
local refillItem=item(refill)
assert(Tags.matches(Tags.forItem(refillItem),{'fuel','survival'}))
assert(not Tags.matches(Tags.forItem(refillItem),{'lighting'}))
refillItem.fraction=0.00001
assert(Tags.matches(Tags.forItem(refillItem),{'fuel'}))
local fullMask=Usage.encode(Usage.read(refill,refillItem))
assert(Tags.matches(snapshot(refill,fullMask),{'fuel'}) and not Tags.matches(snapshot(refill,fullMask),{'lighting'}))
refillItem.fraction,refillItem.uses=0,0
assert(not Tags.matches(Tags.forItem(refillItem),{'fuel','lighting'},'any'))
assert(Tags.matchesScriptRule(refill,rule({'fuel'},{'lighting'})))
assert(Tags.matchesScriptRule(refill,rule({}, {'fuel'})))
assert(not Tags.matches(snapshot(refill,nil),{'fuel'}),'old refill snapshot invented usable fuel')
assert(Tags.matches(Tags.forItem(item(script('Base.Lantern_Propane','survivalLighting',ItemType.DRAINABLE))),{'lighting'}))

ItemTag.THREAD='thread'
for _, spec in ipairs({{'Base.Thread','craftingTailoring_material'}, {'Base.Thread_Aramid','craftingTailoring_material'},
    {'Base.Thread_Sinew','husbandryAnimalPart'}, {'Fixture.NewThread','husbandryAnimalPart'}})do
    local thread=script(spec[1],spec[2],ItemType.DRAINABLE);thread.thread=true
    assert(Tags.matches(Tags.forItem(item(thread)),{'crafting','tailoring','material'}))
    assert(Tags.matchesScriptRule(thread,rule({'tailoring','material'})))
    assert(Tags.matches(snapshot(thread,nil),{'tailoring','material'}))
    if spec[2]=='husbandryAnimalPart' then
        assert(Tags.matches(Tags.forScriptItem(thread),{'husbandry','animalpart'}),'thread lost animal origin')
    end
end
local adapter=script('Base.ThreadAdapter','weaponPart_firearm')
assert(not Tags.matches(Tags.forItem(item(adapter)),{'tailoring'}),'thread name was confused with native sewing tag')
world.types['base.thread_sinew']={tailoring='remove'}
local sinew=script('Base.Thread_Sinew','husbandryAnimalPart',ItemType.DRAINABLE);sinew.thread=true
assert(not Tags.matchesScriptRule(sinew,rule({'tailoring'})))
world.types={}

-- Current sharpening state flows through common rules and snapshot codecs.
ItemTag.SHARPENABLE='sharp';Attribute={Sharpness='sharpness'};ComponentType.Attributes='attributes'
local function attributes(value)return {getAttribute=function()return {getFloatValue=function()return value end}end}end
local knife=script('Base.KitchenKnife','toolCooking');knife.sharp=true
knife.getComponentScriptFor=function(_,id)
    if id==ComponentType.Attributes then return {getTemplateContainer=function()return attributes(1)end}end
end
local blade=item(knife);blade.sharpness=0.8
blade.getAttributes=function(i)return attributes(i.sharpness)end
blade.getMaxSharpness=function()return 1 end
blade.isBroken=function(i)return i.broken==true end
blade.getSharpness=function()error('classification mutated native sharpness')end
assert(Tags.matches(Tags.forItem(blade),{'sharpen','tool','cooking'}))
assert(Tags.matchesScriptRule(knife,rule({'sharpen'})) and Tags.matchesScriptRule(knife,rule({}, {'sharpen'})))
assert(not Tags.matches(Tags.forScriptItem(knife),{'sharpen'}))
assert(Tags.matches(Tags.choices(Tags.forScriptItem(knife)),{'sharpen'}))
local bluntMask=Usage.encode(Usage.read(knife,blade))
assert(#bluntMask==12 and Tags.matches(snapshot(knife,bluntMask),{'sharpen'}))
for _, length in ipairs({4,10,11})do
    assert(not Tags.matches(snapshot(knife,bluntMask:sub(1,length)),{'sharpen'}),'legacy snapshot fabricated sharpness')
end
blade.sharpness=1
local sharpMask=Usage.encode(Usage.read(knife,blade))
assert(sharpMask~=bluntMask and not Tags.matches(snapshot(knife,sharpMask),{'sharpen'}))
assert(not Tags.matches(Tags.forItem(blade),{'sharpen'}))
blade.sharpness,blade.broken=0.1,true
assert(not Tags.matches(Tags.forItem(blade),{'sharpen'}),'broken blade treated as sharpenable')
world.types['base.kitchenknife']={sharpen='remove'}
assert(not Tags.matchesScriptRule(knife,rule({'sharpen'})))
world.types={}
assert(Tags.matches(snapshot(knife,sharpMask,{sharpen='add'}),{'sharpen'}),'manual snapshot correction lost')
for _, id in ipairs({'sharpen','lighting','tailoring','material'})do assert(Tags.requiresItemRule(id))end

-- Unusual mod items can combine independent stains, uses and sharpening.
shirt.sharp=true;shirt.getComponentScriptFor=knife.getComponentScriptFor
Smelting.read=function(s,i)
    if s==shirt then
        if i then return i.uses>0 end
        return nil,{false,true}
    end
    return readSmelting(s,i)
end
for _, dirty in ipairs({false,true})do
    for _, sharpen in ipairs({false,true})do
        for _, smelting in ipairs({false,true})do
            local included,excluded={},{}
            for id,value in pairs({dirty=dirty,sharpen=sharpen,smelting=smelting})do
                local target=value and included or excluded;target[#target+1]=id
            end
            assert(Tags.matchesScriptRule(shirt,rule(included,excluded)),'independent sharpening state was coupled to stains/uses')
        end
    end
end
Smelting.read=readSmelting

if NativeActionRoot then
    local f=assert(io.open(NativeActionRoot..'/../scripts/generated/items/drainable.txt','r'))
    local content=f:read('*a');f:close()
    local sinewBlock=assert(content:match('item Thread_Sinew%s*(%b{})'))
    assert(sinewBlock:find('base:thread',1,true),'native sinew lost sewing role')
    f=assert(io.open(NativeActionRoot..'/../scripts/generated/recipes/recipes_lightsources.txt','r'))
    content=f:read('*a');f:close()
    local insert=assert(content:match('craftRecipe InsertPropaneBottleIntoLantern%s*(%b{})'))
    assert(insert:find('[Base.Propane_Refill] flags[ItemCount;InheritUses]',1,true),'refill no longer transfers fuel to a lantern')
end
