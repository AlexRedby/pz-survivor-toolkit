local worldTags = {}
isClient = function() return false end
ModData = {getOrCreate=function() return worldTags end}
package.path = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/?.lua;' .. package.path
ItemType = {FOOD='food', NORMAL='normal', CONTAINER='container', LITERATURE='literature', MAP='map'}
ItemTag = {CANT_COMPOST='cantcompost', IS_COMPOSTABLE='iscompostable'}
PZSurvivorToolkit = {Settings={itemTags=function() return true end}}
-- Preview classification must never instantiate an item or run an OnCreate hook.
InventoryItemFactory = {CreateItem=function() error('food preview created an item') end}
instanceItem = function() error('food preview instantiated a script item') end
local Tags = require 'PZSurvivorToolkit/ItemTags'
local NEVER = 1000000000
local states = {'fresh','stale','rotten'}

local function script(name, category, fresh, rotten, kind)
    return {name='Fixture.'..name,category=category,fresh=fresh,rotten=rotten,kind=kind or ItemType.FOOD,tags={},
        getFullName=function(self) return self.name end,
        getDisplayCategory=function(self) return self.category end,
        isItemType=function(self, expected) return self.kind==expected end,
        getDaysFresh=function(self) return self.fresh end,
        getDaysTotallyRotten=function(self) return self.rotten end,
        hasTag=function(self,tag) return self.tags[tag]==true end,
        InstanceItem=function() error('preview ran ScriptItem.InstanceItem') end}
end

local function food(definition)
    return {definition=definition,category=definition.category,age=0,
        fresh=definition.fresh,rotten=definition.rotten,burnt=false,frozen=false,fertilized=false,
        getFullType=function(self) return self.definition.name end,
        getDisplayCategory=function(self) return self.category end,
        getScriptItem=function(self) return self.definition end,
        hasTag=function(self,tag) return (self.tags or self.definition.tags)[tag]==true end,
        IsFood=function() return true end,
        isFood=function() return true end,
        getAge=function(self) return self.age end,
        getOffAge=function(self) return self.fresh end,
        getOffAgeMax=function(self) return self.rotten end,
        isFresh=function(self) return self.fertilized or self.age<self.fresh end,
        isRotten=function(self) return not self.fertilized and self.age>=self.rotten end,
        IsRotten=function() error('used legacy IsRotten instead of Food:isRotten') end,
        isBurnt=function(self) return self.burnt end,
        isFrozen=function(self) return self.frozen end,
        isCooked=function(self) return self.cooked or false end,
        isFertilized=function(self) return self.fertilized end}
end

local function has(values, id)
    for _, value in ipairs(values or {}) do if value==id then return true end end
    return false
end

local function actual(item, expected)
    local ids=Tags.forItem(item)
    for _, state in ipairs(states) do
        assert(Tags.matches(ids,{state})==(state==expected),
            'wrong actual '..state..' for '..tostring(expected)..' at age '..tostring(item.age))
    end
    return ids
end

local function possible(ids, expected)
    for _, state in ipairs(states) do
        assert(has(ids.foodStates,state)==has(expected,state),'wrong possible '..state)
    end
    assert(#(ids.foodStates or {})==#expected,'unexpected possible-state entries')
end

local function rule(include, exclude, mode)
    return assert(Tags.normalizeRule({include=include or {},exclude=exclude or {},mode=mode or 'all'}))
end

local apple=script('Apple','foodPerishable_fruit',3,5)
local item=food(apple)
local ids=actual(item,'fresh')
assert(Tags.matches(ids,{'food','perishable','fruit'}))
possible(ids,states)
assert(not Tags.matches(ids,{'rotten'}),'possible states leaked into actual matching')
item.age=3
actual(item,'stale') -- Native equality is stale, not fresh.
item.age=4.999
actual(item,'stale')
item.age=5
actual(item,'rotten') -- Native equality is rotten, not stale.
item.age=0
actual(item,'fresh')
item.frozen=true
item.age=3
actual(item,'stale') -- Frozen does not reset the native age or freshness state.
item.frozen=false
item.cooked=true
actual(item,'stale')
item.burnt=true
actual(item,nil)
item.age=5
actual(item,'rotten') -- Burnt food can still rot and enter the native compost conversion.
item.burnt=false
item.fertilized=true
actual(item,'fresh') -- Fertilized eggs use the native predicates, not a copied age comparison.
item.fertilized=false
actual(item,'rotten')

-- Instance expiry is authoritative, including cooking or mod changes to script defaults.
item.age=0
item.fresh,item.rotten=NEVER,NEVER
ids=actual(item,nil)
assert(Tags.matches(ids,{'nonperishable'}) and not Tags.matches(ids,{'perishable'}))
possible(ids,{})
item.fresh,item.rotten=1,2
item.age=1
ids=actual(item,'stale')
assert(Tags.matches(ids,{'perishable'}) and not Tags.matches(ids,{'nonperishable'}))
item.age=2
actual(item,'rotten')
assert(apple.fresh==3 and apple.rotten==5,'classification wrote script expiry')

-- Static categories cannot override native lifetime, but exact saved categories survive.
for _,category in ipairs({'Food','foodNonPerishable_candySnack','foodPerishable_fruit'}) do
    local definition=script('CategoryTest',category,2,4)
    local physical=food(definition)
    for _,values in ipairs({Tags.forItem(physical),Tags.forScriptItem(definition)}) do
        assert(Tags.matches(values,{'perishable'}) and not Tags.matches(values,{'nonperishable'}))
        assert(Tags.category(values)==category,'food refinement lost legacy category projection')
        assert(Tags.matchesRule(values,rule({'category:'..category})),'exact saved include stopped matching')
        assert(not Tags.matchesRule(values,rule({}, {'category:'..category})),'exact saved exclusion stopped matching')
    end
end
local canned=script('Canned','foodPerishable_fruit',NEVER,NEVER)
local cannedItem=food(canned)
for _,values in ipairs({actual(cannedItem,nil),Tags.forScriptItem(canned)}) do
    assert(Tags.matches(values,{'nonperishable'}) and not Tags.matches(values,{'perishable'}))
    possible(values,{})
end

-- Zero is a valid native expiry (RatKing), and equal thresholds have no stale interval.
local zero=script('RatKing','Food',0,0)
actual(food(zero),'rotten')
possible(Tags.forScriptItem(zero),{'rotten'})
local equal=script('EqualExpiry','Food',3,3)
local equalItem=food(equal)
actual(equalItem,'fresh')
equalItem.age=3
actual(equalItem,'rotten')
possible(Tags.forScriptItem(equal),{'fresh','rotten'})
local noFresh=script('OnlyRottenExpiry','Food',NEVER,5)
local noFreshItem=food(noFresh)
-- A finite rotten deadline does not make a sentinel fresh threshold a visible Fresh state.
actual(noFreshItem,nil)
noFreshItem.age=5
actual(noFreshItem,'rotten')
possible(Tags.forScriptItem(noFresh),{'rotten'})

-- Unknown APIs retain imported static roles without inventing an actual state.
local incomplete=food(apple)
incomplete.isFresh,incomplete.isRotten=nil,nil
actual(incomplete,nil)
local unknown=food(apple)
unknown.getOffAge,unknown.getOffAgeMax=nil,nil
actual(unknown,nil)
local notFood={getDisplayCategory=function() return 'foodPerishable_fruit' end,
    IsFood=function() return false end,isFood=function() return false end,
    getOffAge=function() error('queried food lifetime on a non-Food') end,
    getOffAgeMax=function() error('queried food lifetime on a non-Food') end}
ids=Tags.forItem(notFood)
assert(Tags.matches(ids,{'food','perishable','fruit'}) and not Tags.matches(ids,{'fresh'}))
assert(Tags.category(ids)=='foodPerishable_fruit')

-- Script reads carry possibilities, never a made-up current physical state.
ids=Tags.forScriptItem(apple)
for _,state in ipairs(states) do assert(not Tags.matches(ids,{state}),'script got actual '..state) end
possible(ids,states)
local choices=Tags.choices(ids)
for _,state in ipairs(states) do assert(has(choices,state),'menu omitted possible '..state) end
assert(not has(ids,'fresh'),'choice expansion mutated original tags')
choices[1]='invented'
ids.foodStates[1]='invented'
ids[1]='invented'
local reread=Tags.forScriptItem(apple)
possible(reread,states)
assert(not has(reread,'invented'),'caller mutated later script reads')
local physicalTags=Tags.forItem(food(apple))
physicalTags.foodStates[1]='invented'
physicalTags[1]='invented'
possible(Tags.forItem(food(apple)),states)

-- Preview matches one possible state at a time; exclusive states cannot satisfy all.
assert(not Tags.matchesScriptRule(apple,rule({'fresh','rotten'})))
assert(Tags.matchesScriptRule(apple,rule({'fresh','rotten'}, {}, 'any')))
assert(Tags.matchesScriptRule(apple,rule({'food','fresh'},{'rotten'})))
assert(Tags.matchesScriptRule(apple,rule({}, {'fresh'})),'exclusion rejected other possible states')
assert(not Tags.matchesScriptRule(apple,rule({}, states)),
    'preview invented a state-less normal-aging possibility')
assert(Tags.matchesScriptRule(apple,rule({'stale'},{'fresh','rotten'})))
assert(not Tags.matchesScriptRule(zero,rule({'fresh'})))
assert(not Tags.matchesScriptRule(zero,rule({'stale'})))
assert(Tags.matchesScriptRule(zero,rule({'rotten'})))
assert(not Tags.matchesScriptRule(zero,rule({}, {'rotten'})),
    'zero-expiry preview invented a state before immediate rot')
assert(not Tags.matchesScriptRule(equal,rule({'stale'})))
assert(not Tags.matchesScriptRule(canned,rule({'fresh','stale','rotten'}, {}, 'any')))
for _,definition in ipairs({apple,canned,zero,equal}) do
    local plain=rule({'food'},{'meat'})
    assert(Tags.matchesScriptRule(definition,plain)==Tags.matchesRule(Tags.forScriptItem(definition),plain),
        'possible states changed a plain saved rule')
    assert(Tags.matchesScriptRule(definition,rule({'category:'..Tags.forScriptItem(definition).legacyCategory})),
        'preview lost exact category matching')
end

-- Rotten describes spoilage, regardless of compost restrictions or food category.
local worm=script('Worm','foodPerishable_insect',4,8)
worm.tags[ItemTag.CANT_COMPOST]=true
local wormItem=food(worm)
actual(wormItem,'fresh')
wormItem.age=4
actual(wormItem,'stale')
wormItem.age=8
ids=actual(wormItem,'rotten')
assert(Tags.matchesRule(ids,rule({'rotten'})))
assert(not Tags.matchesRule(ids,rule({'perishable'},{'rotten'})))
wormItem.burnt=true
actual(wormItem,'rotten')
assert(Tags.matchesScriptRule(worm,rule({'rotten'})))

-- Innate compostability does not label unspoiled matter as Rotten.
local dung=script('Dung_Cow','Food',NEVER,NEVER)
dung.tags[ItemTag.IS_COMPOSTABLE]=true
actual(food(dung),nil)
assert(not Tags.matchesScriptRule(dung,rule({'rotten'})))
for _,definition in ipairs({apple,worm,dung}) do
    for _,values in ipairs({Tags.forScriptItem(definition),Tags.forItem(food(definition))}) do
        assert(not has(values,'compost') and not has(Tags.choices(values),'compost'),
            'removed Compost tag remains on items or in choices')
        assert(Tags.category(values)==values.legacyCategory,'freshness lost exact legacy category')
    end
end
-- Compost was removed before release; unknown rule IDs remain invalid, not an empty rule.
assert(Tags.normalizeRule({include={'compost'},exclude={}})==nil)
-- Apply the same saved manual type corrections to actual and possible age states.
worldTags.types['fixture.apple']={rotten='remove'}
local corrected=food(apple);corrected.age=5
assert(not Tags.matchesRule(Tags.forItem(corrected),rule({'rotten'})))
assert(not Tags.matchesScriptRule(apple,rule({'rotten'})), 'preview restored a manually removed age tag')
worldTags.types['fixture.apple'].recipe='add'
assert(Tags.matchesScriptRule(apple,rule({'recipe','stale'})), 'preview lost a manual type addition')
worldTags.types={}
print('food freshness tags: OK')
