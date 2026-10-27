local world = {}
isClient=function() return false end
ModData={getOrCreate=function() return world end}
package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/?.lua;'..package.path
local Tags=require 'PZSurvivorToolkit/ItemTags'
local Custom=require 'PZSurvivorToolkit/TagCustomization'
local Schema=require 'PZSurvivorToolkit/ItemTagSchema'
local function contains(values,id)
    for _,value in ipairs(values) do if value==id then return true end end
    return false
end
local oldRule=assert(Tags.normalizeRule({include={'food'},exclude={}}))
for category in pairs(Schema.retiredCategories.food) do
    local ids=Tags.forCategory(category)
    assert(not contains(ids,'food') and not contains(Tags.choices(ids),'food'),'retired Food surfaced in '..category)
    assert(Tags.matchesRule(ids,oldRule),'saved Food rule lost '..category)
    assert(Tags.category(ids)==category,'retirement lost exact category '..category)
    assert(Tags.matches(ids,{'category:'..category}),'exact saved category lost '..category)
end
assert(not contains(Tags.allIds(),'food'),'Food remains selectable as a new tag')
assert(Tags.matches('petsFood',{'pets','feed'}),'animal food lost its concrete feed role')
assert(Tags.matches('foodPerishable_meat',{'meat','perishable'}))
assert(Tags.matches('foodPerishable_vegetable',{'vegetable','perishable'}))
assert(Tags.matches('foodBeverage_alcoholic',{'beverage','alcoholic'}))
assert(not Tags.matches('cookingIngredient',{'food'}),'old Food rule expanded to all ingredients')
assert(not Tags.matches('survivalTrapping_baitLure',{'food'}),'old Food rule expanded to bait')

Custom.catalog()
world.types['fixture.apple']={food='remove'}
local definition={getFullName=function() return 'Fixture.Apple' end,
    getDisplayCategory=function() return 'foodPerishable_fruit' end}
local delta={}
local actual={getFullType=function() return definition:getFullName() end,
    getScriptItem=function() return definition end,
    getDisplayCategory=function() return definition:getDisplayCategory() end,
    hasModData=function() return true end,getModData=function() return {[Custom.FIELD]=delta} end}
local hidden=Tags.forItem(actual)
assert(not Tags.matchesRule(hidden,oldRule),'type removal no longer affects saved Food rules')
delta.food='add'
local restored=Tags.forItem(actual)
assert(Tags.matchesRule(restored,oldRule) and not contains(restored,'food'),
    'instance Food override must preserve old rule membership without becoming a visible tag')
assert(Tags.signature(restored)~=Tags.signature(hidden),'inventory stacks merged different saved-rule membership')
assert(Tags.matchesRule(Tags.forSnapshot(definition,definition:getFullName(),definition:getDisplayCategory(),nil,delta),oldRule),
    'warehouse snapshot lost retired Food assignment')
delta.food='remove'
world.types['fixture.apple']={food='add'}
assert(not Tags.matchesRule(Tags.forItem(actual),oldRule),'instance removal lost precedence over type addition')
local projected=Custom.projectSnapshot({'food','fruit'},'Fixture.Other',{food='remove'})
assert(not contains(projected,'food') and not Tags.matchesRule(projected,oldRule),'legacy input bypassed retirement/overrides')
assert(not contains(Tags.allIds({actual}),'food'),'manual legacy assignments resurfaced Food in editors')
print('Food taxonomy passed: concrete roles, hidden legacy membership, saved exact/semantic rules, manual precedence and stack partitioning.')
