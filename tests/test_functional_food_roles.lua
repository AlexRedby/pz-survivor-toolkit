package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/?.lua;'..package.path
local world={}
isClient=function()return false end
ModData={getOrCreate=function()return world end}
PZSurvivorToolkit={Settings={itemTags=function()return true end}}
ItemType={FOOD='food',NORMAL='normal',LITERATURE='literature'}
ComponentType={FluidContainer='fluid'}
FluidCategory={Beverage='beverage',Alcoholic='alcoholic'}
local function list(values)return {size=function()return #values end,get=function(_,i)return values[i+1]end}end
local water={isCategory=function(_,id)return id=='beverage'end}
local whiskey={isCategory=function()return true end}
Fluid={getAllFluids=function()return list({water,whiskey})end}
-- Exercise item-tag refinement independently of legacy display-category rules.
package.loaded['PZSurvivorToolkit/ItemCategories']={forScript=function(s)return s:getDisplayCategory()end}
local Tags=require 'PZSurvivorToolkit/ItemTags'
local C=require 'PZSurvivorToolkit/TagCustomization'
local function has(values,id)for _,v in ipairs(values)do if v==id then return true end end return false end
local function rule(include,exclude,mode)return assert(Tags.normalizeRule({include=include or {},exclude=exclude or {},mode=mode or 'all'}))end
local function script(name,category,spice)
    return {getFullName=function()return 'Fixture.'..name end,getDisplayCategory=function()return category end,
        isItemType=function(_,kind)return kind==ItemType.FOOD end,isSpice=function()return spice end}
end
local function item(s,delta)
    return {getScriptItem=function()return s end,getFullType=function()return s:getFullName()end,
        IsFood=function()return s:isItemType(ItemType.FOOD)end,isSpice=function()return s:isSpice()end,
        getDisplayCategory=function()return s:getDisplayCategory()end,
        hasModData=function()return delta~=nil end,getModData=function()return {[C.FIELD]=delta}end}
end
local salt=script('Salt','foodNonPerishable_spice',true)
local bacon=script('BaconBits','foodPerishable_condiment',true)
local beans=script('Blackbeans','foodPerishable_condiment',false)
for _,s in ipairs({salt,bacon})do
    for _,tags in ipairs({Tags.forItem(item(s)),Tags.forScriptItem(s),Tags.forSnapshot(s,s:getFullName(),s:getDisplayCategory())})do
        assert(Tags.matches(tags,{'ingredient','seasoning'}),'native additive lost overlapping cooking role')
        assert(not has(tags,'condiment'),'duplicate legacy chip survived')
        assert(Tags.category(tags)==s:getDisplayCategory(),'native refinement lost exact legacy category')
    end
end
assert(not Tags.matches(Tags.forItem(item(beans)),{'seasoning'}),'ordinary beans inherited additive role')
assert(not Tags.matchesScriptRule(beans,rule({'seasoning'})))
assert(Tags.matchesScriptRule(bacon,rule({'condiment'})))
assert(Tags.requiresItemRule('seasoning') and Tags.requiresItemRule('condiment'))
assert(has(Tags.allIds(),'seasoning') and not has(Tags.allIds(),'condiment'))
assert(Tags.defaultLabel('experience')=='Learning')
assert(Tags.label('condiment')==Tags.label('seasoning'))

-- Old rules and manual corrections use the single canonical ID on read/write.
local merged=rule({'condiment','seasoning'})
assert(#merged.include==1 and merged.include[1]=='seasoning')
assert(rule({}, {'condiment'}).exclude[1]=='seasoning')
local opposing=rule({'condiment'},{'seasoning'})
assert(not Tags.matchesRule({'seasoning'},opposing) and not Tags.matchesRule({},opposing))
assert(Tags.normalizeRule(opposing),'old opposing aliases corrupted the saved preset format')
local alternative=rule({'condiment','tool'},{'seasoning'},'any')
assert(Tags.matchesRule({'tool'},alternative) and not Tags.matchesRule({'tool','seasoning'},alternative))
assert(Tags.normalizeRule({include={'seasoning'},exclude={'seasoning'}})==nil,'explicit conflicts became valid')
world.types['fixture.salt']={condiment='remove'}
assert(not Tags.matches(Tags.forItem(item(salt)),{'seasoning'}))
assert(Tags.matches(Tags.forItem(item(salt,{seasoning='add'})),{'seasoning'}))
assert(not Tags.matchesScriptRule(salt,rule({'seasoning'})))
world.types={}
assert(Tags.matches(Tags.forItem(item(beans,{condiment='add'})),{'seasoning'}))
assert(C.normalizeChanges({condiment='add',seasoning='remove'},true).seasoning=='remove')
assert(next(C.changeDelta({condiment='remove'},{seasoning='default'},false))==nil,
    'reset restored an old alias correction')
world.definitions.condiment={name='Kitchen extras'}
assert(C.definition('seasoning').name=='Kitchen extras','old appearance disappeared')
local clean=assert(C.normalizeCatalog(world))
assert(clean.definitions.condiment==nil and clean.definitions.seasoning.name=='Kitchen extras')
world.definitions.seasoning={name='New extras'}
assert(C.normalizeCatalog(world).definitions.seasoning.name=='New extras','alias overwrote canonical appearance')
world.definitions={}

-- Same bottle, changing actual contents; its stale display category is irrelevant.
local component={getCapacity=function()return 1 end,isInitialFluidsIsRandom=function()return false end,
    getInitialFluids=function()return list({{getFluid=function()return whiskey end,getPercentage=function()return 1 end}})end,
    getInitialAmount=function()error('content-role preview consumed RNG')end}
local bottle=script('Bottle','foodBeverage_alcoholic',false)
bottle.isItemType=function()return false end
bottle.getComponentScriptFor=function()return component end
local contents={}
local container={isEmpty=function()return next(contents)==nil end,
    isCategory=function(_,category)
        for fluid,amount in pairs(contents)do if amount>0 and fluid:isCategory(category)then return true end end
        return false
    end,getSpecificFluidAmount=function(_,fluid)return contents[fluid] or 0 end}
local physical=item(bottle)
physical.getFluidContainer=function()return container end
local empty=Tags.forItem(physical)
assert(not Tags.matches(empty,{'beverage','alcoholic'},'any'))
contents[water],contents[whiskey]=0.99,0.01
local mixed=Tags.forItem(physical)
assert(Tags.matches(mixed,{'beverage','alcoholic'}))
assert(Tags.signature(empty)~=Tags.signature(mixed),'mixed inventory stacks merged different contents')
contents[whiskey]=nil
assert(Tags.matches(Tags.forItem(physical),{'beverage'}) and not Tags.matches(Tags.forItem(physical),{'alcoholic'}))
local defaults=Tags.forScriptItem(bottle)
assert(not Tags.matches(defaults,{'beverage','alcoholic'},'any'),'script claimed current contents')
assert(has(Tags.choices(defaults),'beverage') and has(Tags.choices(defaults),'alcoholic'))
assert(Tags.matchesScriptRule(bottle,rule({'beverage','alcoholic'})))
assert(Tags.matchesScriptRule(bottle,rule({}, {'beverage','alcoholic'})),'empty preview missing')
assert(not Tags.matchesScriptRule(bottle,rule({'alcoholic'},{'beverage'})))
world.types['fixture.bottle']={alcoholic='remove'}
assert(not Tags.matchesScriptRule(bottle,rule({'alcoholic'})),'preview overrode manual removal')
world.types={}
local function snapshot(state,delta)
    return Tags.forSnapshot(bottle,bottle:getFullName(),bottle:getDisplayCategory(),nil,delta,false,nil,state)
end
assert(not Tags.matches(snapshot(nil),{'beverage','alcoholic'},'any'),'old snapshot invented factory contents')
assert(not Tags.matches(snapshot('none'),{'beverage','alcoholic'},'any'))
assert(Tags.matches(snapshot('alcoholic'),{'beverage','alcoholic'}))
assert(Tags.matches(snapshot('none',{beverage='add'}),{'beverage'}),'manual snapshot correction lost')
assert(Tags.requiresItemRule('beverage') and Tags.requiresItemRule('alcoholic'))

if NativeActionRoot then
    local file=assert(io.open(NativeActionRoot..'/../scripts/generated/items/food.txt'))
    local source=file:read('*a');file:close()
    local blocks={}
    for name,block in source:gmatch('item%s+([%w_]+)%s*(%b{})')do blocks[name]=block end
    for _,name in ipairs({'Salt','Ketchup','OilOlive','MayonnaiseFull','BaconBits','Blackbeans','DriedBlackBeans'})do
        local block=assert(blocks[name],name)
        local s=script(name,'foodPerishable_condiment',block:match('Spice%s*=%s*true')~=nil)
        local expected=name~='Blackbeans' and name~='DriedBlackBeans'
        assert(Tags.matches(Tags.forItem(item(s)),{'seasoning'})==expected,name..' got wrong native additive role')
    end
    print('native B42.21 additive flags checked: salt, sauces, oils, bacon and bean negatives')
else print('SKIP native additive flags (NativeActionRoot not supplied)') end
print('functional food roles: one seasoning, saved aliases, contents, previews, snapshots and manual precedence passed')
