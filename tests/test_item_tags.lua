local shared = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/shared/'
package.path = shared .. '?.lua;' .. package.path
local enabled = true
PZSurvivorToolkit = {Settings = {itemTags = function() return enabled end}}
local resetPlanting
Events={OnGameBoot={Add=function(fn) resetPlanting=fn end}}
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

-- Exclusions share one item-tag lookup, regardless of how many alternatives a
-- saved rule contains. Retain exact legacy-category matching in that lookup.
do
 local tags=Tags.forCategory('foodPerishable_fruit')
 local excluded={}; for i=1,64 do excluded[i]='category:Absent'..i end
 local rule={mode='all',include={'food','fruit','category:foodPerishable_fruit'},exclude=excluded}
 local originalIpairs, traversals=ipairs,0
 ipairs=function(values)
  if values==tags then traversals=traversals+1 end
  return originalIpairs(values)
 end
 local accepted=Tags.matchesRule(tags,rule)
 ipairs=originalIpairs
 assert(accepted and traversals==1,'tag rule rebuilt item membership for each exclusion')
 tags[1]='changed'
 assert(not Tags.matchesRule(tags,rule),'rule matching retained an earlier tag-set cache')
end

-- Grouped conditions use OR between branches and AND within each branch.
do
 local grouped=assert(Tags.normalizeRule({groups={
  {include={'mechanics'},exclude={'vehiclepart'}}, {include={'perishable'},exclude={}}
 }}))
 assert(Tags.matchesRule({'mechanics'},grouped))
 assert(not Tags.matchesRule({'mechanics','vehiclepart'},grouped))
 assert(Tags.matchesRule({'perishable','vehiclepart'},grouped),'exclusion escaped its own branch')
 assert(not Tags.matchesRule({'food'},grouped))
 assert(Tags.ruleActive(grouped) and Tags.ruleIncludes(grouped,'mechanics') and not Tags.ruleIncludes(grouped,'vehiclepart'))
 local draft=Tags.ruleGroups(grouped);draft[1].include[1]='food'
 assert(grouped.groups[1].include[1]=='mechanics','group draft aliases saved rule')
 assert(Tags.fromRuleGroups({{include={'food','perishable'},exclude={'meat'}}}).mode=='all')
 local legacy={mode='any',include={'food','mechanics'},exclude={'vehiclepart'}}
 local branches=assert(Tags.ruleGroups(legacy))
 assert(#branches==2 and branches[1].exclude~=branches[2].exclude)
 local collapsed=assert(Tags.fromRuleGroups(branches));assert(collapsed.mode=='any')
 for _,itemTags in ipairs({{}, {'food'}, {'mechanics'}, {'food','vehiclepart'}, {'mechanics','perishable'}}) do
  assert(Tags.matchesRule(itemTags,legacy)==Tags.matchesRule(itemTags,{groups=branches}))
  assert(Tags.matchesRule(itemTags,legacy)==Tags.matchesRule(itemTags,collapsed))
 end
 local large={mode='any',include={},exclude={}}
 for i=1,64 do large.include[i]='category:Include'..i;large.exclude[i]='category:Exclude'..i end
 local roundtrip=assert(Tags.fromRuleGroups(assert(Tags.ruleGroups(large))))
 assert(roundtrip.mode=='any' and #roundtrip.include==64 and #roundtrip.exclude==64)
 assert(Tags.matchesRule({'category:Include64'},roundtrip))
 assert(not Tags.matchesRule({'category:Include64','category:Exclude64'},roundtrip))
 local negative=assert(Tags.fromRuleGroups({{exclude={'vehiclepart'}},{include={'perishable'}}}))
 assert(Tags.matchesRule({},negative) and not Tags.matchesRule({'vehiclepart'},negative))
 assert(Tags.matchesRule({'vehiclepart','perishable'},negative))
 local unconditional=assert(Tags.normalizeRule({groups={{include={'food'}},{}}}))
 assert(Tags.matchesRule({},unconditional) and not Tags.ruleActive(unconditional),'empty branch truth changed')
 assert(Tags.matchesRule({},Tags.fromRuleGroups(Tags.ruleGroups({mode='any',exclude={'food'}}))))
 for _,bad in ipairs({{groups={}}, {groups=false}, {groups={[2]={}}}, {groups={extra={}}},
  {groups={{mode='all'}}}, {groups={{include={'food'},exclude={'food'}}}},
  {groups={{include={[2]='food'}}}}, {groups={{include={'unknown'}}}},
  {groups={{}},mode='all'}, {groups={{}},include={}}, {groups={{}},extra=true}}) do
  assert(not Tags.normalizeRule(bad) and not Tags.matchesRule({},bad),'malformed grouped rule accepted')
 end
 local tooMany={};for i=1,65 do tooMany[i]={include={'food'}} end
 assert(not Tags.fromRuleGroups(tooMany))
 assert(not Tags.fromRuleGroups({{include=huge}}))
end

local function scriptItem(fullType, category, doubleClick)
 return {fullType=fullType,category=category,
  getFullName=function(self) return self.fullType end,
  getDisplayCategory=function(self) return self.category end,
  getDoubleClickRecipe=function() return doubleClick end}
end
local function inventoryItem(script)
 return {category=script.category,getFullType=function() return script.fullType end,
  getDisplayCategory=function(self) return self.category end,getScriptItem=function() return script end}
end
local function javaList(values)
 return {size=function() return #values end,get=function(_,index) return values[index+1] end}
end
-- PZ's Kahlua exposes pairs but not Lua 5.1's next global.
local luaNext = next
next = nil
local sunflower=scriptItem('Base.SunflowerSeeds','foodNonPerishable_candySnack')
assert(not Tags.matches(Tags.forScriptItem(sunflower),{'seed'}),'guessed a role before farming loaded')
farming_vegetableconf={props={}}
assert(not Tags.matches(Tags.forScriptItem(sunflower),{'seed'}))
farming_vegetableconf.props.Sunflower={seedName='Base.SunflowerSeeds'}
farming_vegetableconf.props.Potatoes={seedName='Base.Potato',seedTypes={'Base.Potato','Base.PotatoSeed'}}
farming_vegetableconf.props.LemonGrass={seedName='Base.LemonGrass'}
farming_vegetableconf.props.Barley={seedName='Base.BarleySheaf',seedTypes={'Base.BarleySeed'}}
local enriched=Tags.forScriptItem(sunflower)
assert(Tags.matches(Tags.forScriptItem(scriptItem('base.sunflowerseeds',sunflower.category)),{'seed'}),
 'lowercase native module lost planting metadata')
local javaFullType=setmetatable({},{__tostring=function() return 'base.SunflowerSeeds' end})
assert(Tags.matches(Tags.forScriptItem(scriptItem(javaFullType,sunflower.category)),{'seed'}),
 'Java-style full type was not normalized')
assert(Tags.matches(enriched,{'food','snack','farming','seed'}),'lost food or planting roles')
assert(Tags.category(enriched)=='foodNonPerishable_candySnack','enrichment lost exact legacy origin')
enriched.legacyCategory='Invented.Category'
assert(Tags.category(enriched)==nil,'mutated origin invented a category')
enriched.legacyCategory=sunflower.category
enriched[#enriched+1]='weapon'
assert(Tags.category(enriched)==nil,'mutated enrichment invented a legacy category')
enriched[1]='medical'
assert(Tags.matches(Tags.forScriptItem(sunflower),{'food'}),'caller mutated classification cache')
assert(not Tags.matches(Tags.forCategory(sunflower.category),{'seed'}),'item role contaminated its category')
for _,case in ipairs({{'Base.Potato','foodPerishable_vegetable','food'},
 {'Base.LemonGrass','medicalTreatment','medical'},{'Base.BarleySeed','Gardening','farming'}}) do
 local script=scriptItem(case[1],case[2]);local values=Tags.forScriptItem(script)
 assert(Tags.matches(values,{case[3],'farming','seed'}),case[1]..' lost native planting role')
 assert(Tags.category(values)==case[2],'planting tags changed legacy category')
end
for _,fullType in ipairs({'Base.BarleySheaf','Base.GingerRoot','Base.HempBundle','Base.MarigoldDried','Base.UnconfiguredSeed'}) do
 local script=scriptItem(fullType,'Food');script.hasTag=function() return true end
 assert(not Tags.matches(Tags.forScriptItem(script),{'seed'}),'tag or name alone inferred planting: '..fullType)
end
local live=inventoryItem(sunflower)
live.category='medicalTreatment'
assert(Tags.matches(Tags.forItem(live),{'medical','treatment','seed'}),'inventory category was not read live')
assert(not Tags.matches(Tags.forItem(live),{'food'}),'script category overrode inventory category')
assert(Tags.category(Tags.forItem(live))=='medicalTreatment')
local full=scriptItem('Base.CarrotBagSeed2','Gardening','OpenPacketOfSeeds')
local empty=scriptItem('Base.CarrotBagSeed2_Empty','farmingSeed')
assert(Tags.matches(Tags.forScriptItem(full),{'farming','seed'}),'full packet lacks seed role')
assert(Tags.matches(Tags.forScriptItem(scriptItem('base.CarrotBagSeed2','Gardening','Base.OpenPacketOfSeeds')),{'seed'}),
 'qualified packet recipe lost seed role')
-- The resolver must retry a recipe unavailable at the first item read.
ScriptManager={instance={getCraftRecipe=function() return nil end}}
assert(Tags.matches(Tags.forScriptItem(empty),{'seed'}))
local input={getPossibleInputItems=function() return javaList({full}) end}
local output={getPossibleResultItems=function() return javaList({sunflower,empty}) end}
local recipe={getInputs=function() return javaList({input}) end,getOutputs=function() return javaList({output}) end}
ScriptManager.instance.getCraftRecipe=function(_,name) assert(name=='Base.OpenPacketOfSeeds');return recipe end
local emptyTags=Tags.forScriptItem(empty)
assert(Tags.matches(emptyTags,{'farming'}) and not Tags.matches(emptyTags,{'seed'}),'empty packet still counted as seed')
assert(Tags.category(emptyTags)=='farmingSeed','seed removal lost exact legacy origin')
assert(Tags.matches(emptyTags,{'category:farmingSeed'}),'exact saved category lost on empty packet')
empty.category='RecipeResource'
assert(Tags.matches(Tags.forScriptItem(empty),{'crafting','farming'}),'vanilla empty packet lost farming role')
assert(not Tags.matches(Tags.forScriptItem(empty),{'seed'}))
local book=scriptItem('Base.BookFarming1','Literature')
local food=scriptItem('Base.UnconfiguredSeed_Empty','Food')
assert(not Tags.matches(Tags.forScriptItem(book),{'seed'}),'farming book mistaken for seed packet')
assert(not Tags.matches(Tags.forScriptItem(food),{'farming'}),'empty suffix inferred packet metadata')
assert(#Tags.forScriptItem(nil)==0)
farming_vegetableconf.props.LateCrop={seedName='Mod.LateCrop'}
resetPlanting()
assert(Tags.matches(Tags.forScriptItem(scriptItem('Mod.LateCrop','Food')),{'food','seed'}),
 'preboot planting cache ignored definitions loaded later')
next = luaNext

-- Script loot buckets must not leak into inventory tag/catalog choices. The
-- optional provider may load after this module; live instance overrides win.
local Categories = require 'PZSurvivorToolkit/ItemCategories'
local thread = scriptItem('Base.Thread', 'Material')
thread.getDisplayName = function() return 'Thread' end
local stone = scriptItem('Base.LargeStone', 'Material')
stone.getDisplayName = function() return 'Stone' end
assert(Categories.forScript(thread) == 'Material' and Categories.forScript(nil) == nil)
local liveThread = inventoryItem(thread)
Categories.prepareItem(liveThread)
assert(liveThread.category == 'Material', 'provider-free preparation changed item')
local providerCategory = 'craftingTailoring_material'
local prepared = {}
OrganizedCategories = {
 getScriptInventoryDisplayCategory = function(script)
  if script == thread then return providerCategory end
 end,
 autoSortLiquid = function(item) prepared[#prepared+1] = 'fluid';item.category = 'mechanicsFuel' end,
 applyItemDisplayOverride = function(item)
  prepared[#prepared+1] = 'override'
  if item == liveThread then item.category = 'medicalTreatment' end
 end,
}
assert(Tags.matches(Tags.forScriptItem(thread), {'tailoring', 'material'}), 'script tags used loot bucket')
assert(Categories.forScript(stone) == 'Material', 'missing provider value lost raw fallback')
providerCategory = ''
assert(Categories.forScript(thread) == 'Material', 'empty provider value lost raw fallback')
providerCategory = 'craftingTailoring_material'
local liquid = inventoryItem(scriptItem('Base.Bottle', 'Container'))
liquid.isFluidContainer = function() return true end
Categories.prepareContainer({getItems=function() return javaList({liveThread, liquid}) end})
assert(table.concat(prepared, ',') == 'override,fluid,override', 'fluid preparation must precede instance overrides')
assert(Tags.matches(Tags.forItem(liveThread), {'medical'}) and not Tags.matches(Tags.forItem(liveThread), {'tailoring'}),
 'live instance override replaced by script/type category')
assert(Tags.matches(Tags.forItem(liquid), {'fuel'}), 'fluid result lost')
assert(thread.category == 'Material', 'inventory preparation rewrote loot-safe ScriptItem')

-- Exercise the owned catalog without organizedCategories replacing its functions.
getScriptManager = function() return {getAllItems=function() return javaList({thread, stone}) end} end
dofile(shared .. 'LootSorter_Categories.lua')
local cats = LootSorter.getCategories()
assert(#cats == 2 and cats[1] == 'Material' and cats[2] == providerCategory, 'owned catalog ignored inventory categories')
local entries = LootSorter.getItemsInCategory(providerCategory)
assert(#entries == 1 and entries[1].fullType == 'Base.Thread', 'owned catalog grouped by loot bucket')
assert(#LootSorter.getItemsInCategory('Material') == 1 and thread.category == 'Material', 'catalog changed script data')
OrganizedCategories = nil
dofile(shared .. 'LootSorter_Categories.lua')
assert(#LootSorter.getCategories() == 1 and #LootSorter.getItemsInCategory('Material') == 2, 'provider-free catalog failed')
local hidden = scriptItem('Base.Hidden', 'HiddenCategory')
hidden.isHidden = function() return true end
hidden.getObsolete = function() return false end
local obsolete = scriptItem('Base.Obsolete', 'ObsoleteCategory')
obsolete.isHidden = function() return false end
obsolete.getObsolete = function() return true end
getAllItems = function() return javaList({thread, hidden, obsolete}) end
getScriptManager = function() return {getAllItems = getAllItems} end
dofile(shared .. 'LootSorter_Categories.lua')
local ruleScripts = LootSorter.getTagScriptItems()
assert(#ruleScripts == 2 and ruleScripts[1] == thread and ruleScripts[2] == hidden,
 'rule catalog must include hidden items but exclude obsolete scripts')
assert(#LootSorter.getCategories() == 1 and LootSorter.getCategories()[1] == 'Material',
 'visible category picker inherited rule-preview inclusion policy')
print('ItemTags: '..count..' exact legacy projections, independent tags, aliases, unknown/ambiguous keys and live fluid changes passed.')
