local shared = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/'
package.path = shared .. '?.lua;' .. package.path
local enabled = true
PZSurvivorToolkit = {Settings = {itemTags = function() return enabled end}}
getTextOrNull = function(key) if key == 'UI_PZST_Tag_food' then return 'Еда' end end
local Tags = require 'PZSurvivorToolkit/ItemTags'
local schema = require 'PZSurvivorToolkit/ItemTagSchema'
local count = 0
for category, definition in pairs(schema.categories) do
 local tags = Tags.forCategory(category)
 assert(Tags.category(tags) == category, 'lost legacy key '..category)
 for _, id in ipairs(tags) do assert(schema.labels[id] and Tags.label(id)) end
 local shuffled = {}; for i=#tags,1,-1 do shuffled[#shuffled+1]=tags[i] end
 assert(Tags.category(shuffled,category)==category,'tag order changed projection')
 count=count+1
end
assert(count==357)
assert(Tags.label('food')=='Еда')
assert(Tags.matches('toolElectrical',{'electrical'}))
assert(Tags.matches('craftingElectrical_material',{'electrical','material'}))
assert(not Tags.matches('toolElectrical',{'electrical','material'}))
assert(Tags.matches('toolElectrical',{'electrical','material'},'any'))
assert(not Tags.matches('foodNonPerishable',{'perishable'}))
assert(Tags.matches('foodPerishable_fruit',{'food','perishable','fruit'}))
assert(not Tags.matches('junkMiscellaneous',{'food'}))
assert(Tags.matches('Food',{'food'}))
assert(Tags.matches('FurnitureDoor',{'furniture','door'}))
assert(Tags.matches('furnitureDoor',{'furniture','door'}))
assert(Tags.category(Tags.forCategory('FurnitureDoor'))=='FurnitureDoor')
assert(Tags.category(Tags.forCategory('furnitureDoor'))=='furnitureDoor')
assert(Tags.matches('Communications',{'survival','communication'}))
assert(Tags.matches('Animal',{'pets','animalcare'}))
assert(Tags.matches('AnimalPartWeapon',{'weapon','animalpart'}))
assert(Tags.matches('Badger',{'collectable','plushie'}))
assert(Tags.matches('Frog',{'miscellaneous'}))
assert(Tags.matches('Wound',{'character'}))
assert(Tags.matches('Mod.Unknown',{}))
local unknown=Tags.forCategory('Mod.Unknown-Leaf')
assert(#unknown==1 and Tags.category(unknown)=='Mod.Unknown-Leaf')
assert(Tags.label(unknown[1])=='Mod.Unknown-Leaf')
local tags=Tags.forCategory('toolElectrical');tags[1]='food'
assert(Tags.forCategory('toolElectrical')[1]=='tool','caller mutated schema')
assert(Tags.category({'food','tool'})==nil,'invented legacy key')
local a=Tags.forCategory('weaponFirearm_P308');a.legacyCategory=nil
assert(Tags.category(a)==nil,'ambiguous caliber guessed')
assert(Tags.category(a,'weaponFirearm_7P62X51MM')=='weaponFirearm_7P62X51MM')
local item={category='containerLiquid',getDisplayCategory=function(self) return self.category end}
assert(Tags.matches(Tags.forItem(item),{'liquid'}))
item.category='mechanicsFuel'
assert(Tags.matches(Tags.forItem(item),{'fuel'}))
assert(not Tags.matches(Tags.forItem(item),{'liquid'}),'stale fluid classification')
assert(Tags.category(Tags.forItem(item))==item.category)
assert(Tags.enabled());enabled=false;assert(not Tags.enabled())
assert(#Tags.forItem(nil)==0)
local nativeItem={getDisplayCategory=function() return nil end,getCategory=function() return 'Food' end}
assert(Tags.matches(Tags.forItem(nativeItem),{'food'}),'native category fallback missing')
local rule=assert(Tags.normalizeRule({include={'perishable','food','food'},exclude={'meat'}}))
assert(rule.mode=='all' and #rule.include==2 and rule.include[1]=='food')
assert(Tags.matchesRule('foodPerishable_fruit',rule))
assert(not Tags.matchesRule({'food','perishable','meat'},rule))
assert(not Tags.matchesRule('foodNonPerishable',rule))
rule.mode='any'
assert(Tags.matchesRule('foodNonPerishable',rule))
assert(Tags.matchesRule('Food',assert(Tags.normalizeRule(nil))))
assert(not Tags.ruleActive(Tags.normalizeRule(nil)))
assert(Tags.matchesRule('toolElectrical',assert(Tags.normalizeRule({exclude={'food'},mode='any'}))))
assert(not Tags.matchesRule('Food',assert(Tags.normalizeRule({exclude={'food'}}))))
assert(Tags.matchesRule('New.Mod',assert(Tags.normalizeRule({include={'category:New.Mod'}}))))
for _,bad in ipairs({false,1,'food',{mode='ALL'},{mode=false},{include=false},{include='food'},
 {include={[2]='food'}},{include={food=true}},{include={'unknown-tag'}},{include={'category:'}},
 {include={'category:x\n'}},{include={'food'},exclude={'food'}},{include={},extra=true}}) do
 assert(Tags.normalizeRule(bad)==nil,'accepted malformed rule')
end
local huge={};for i=1,65 do huge[i]='food' end
assert(Tags.normalizeRule({include=huge})==nil)
local draft={include={'food'}};local normalized=Tags.normalizeRule(draft)
draft.include[1]='tool';assert(normalized.include[1]=='food','normalization retained caller data')
assert(not Tags.matchesRule('Food',nil))
local oldExact=assert(Tags.normalizeRule({include={'category:FurnitureDoor'}}))
assert(Tags.matchesRule('FurnitureDoor',oldExact),'old exact-category rule stopped matching newly tagged category')
assert(Tags.matchesRule(Tags.forCategory('FurnitureDoor'),oldExact),'item origin was lost in exact-category match')
assert(not Tags.matchesRule('furnitureDoor',oldExact),'exact-category filter became case insensitive')
assert(not Tags.matchesRule('FurnitureDoor',assert(Tags.normalizeRule({include={'furniture'},exclude={'category:FurnitureDoor'}}))),
 'old exact-category exclusion stopped working')
assert(Tags.matches('FurnitureDoor',{'category:FurnitureDoor'}),'single exact tag filter stopped working')
print('ItemTags: '..count..' exact legacy projections, independent tags, aliases, unknown/ambiguous keys and live fluid changes passed.')
