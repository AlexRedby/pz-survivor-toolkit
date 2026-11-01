package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/?.lua;'..package.path
local world={}
isClient=function()return false end
ModData={getOrCreate=function()return world end}
PZSurvivorToolkit={Settings={itemTags=function()return true end}}
ItemType={FOOD='food',NORMAL='normal',DRAINABLE='drainable',LITERATURE='literature'}
ItemTag={}
FluidCategory={Beverage='beverage',Alcoholic='alcoholic',Fuel='fuel'}
-- The physical APIs below retain the native instance's category. Script
-- classification is outside this test and need not load the native rules.
package.loaded['PZSurvivorToolkit/ItemCategories']={forScript=function(s)return s.category end}
local Tags=require 'PZSurvivorToolkit/ItemTags'
local Custom=require 'PZSurvivorToolkit/TagCustomization'
local function script(name,category,kind)
 return {name=name,category=category,kind=kind or ItemType.NORMAL,
  getFullName=function(s)return s.name end,getDisplayCategory=function(s)return s.category end,
  isItemType=function(s,k)return s.kind==k end,hasTag=function()return false end,
  isCantEat=function()return false end,isIsCookable=function(s)return s.kind==ItemType.FOOD end}
end
local function item(s)
 return {s=s,category=s.category,data={},freshness='fresh',
  getScriptItem=function(i)return i.s end,getFullType=function(i)return i.s.name end,
  getDisplayCategory=function(i)return i.category end,getCategory=function()return 'Food'end,
  hasModData=function(i)return next(i.data)~=nil end,getModData=function(i)return i.data end,
  hasTag=function()return false end,IsFood=function(i)return i.s.kind==ItemType.FOOD end,
  IsDrainable=function(i)return i.s.kind==ItemType.DRAINABLE end,
  getFluidContainer=function(i)return i.container end,isBroken=function(i)return i.broken==true end,
  getOffAge=function()return 2 end,getOffAgeMax=function()return 5 end,
  isFresh=function(i)return i.freshness=='fresh'end,isRotten=function(i)return i.freshness=='rotten'end,
  isCooked=function(i)return i.cooked==true end,isBurnt=function(i)return i.burnt==true end,
  isCookable=function(i)return i.s.kind==ItemType.FOOD end,getHungChange=function()return -.1 end,
  getCustomMenuOption=function()return nil end,getCurrentUses=function()return 1 end}
end
local checked=0
local function parity(physical,reason,context)
 local full=Tags.forItem(physical,context)
 local membership=Tags.membershipForItem(physical,context)
 assert(Tags.signature(full)==Tags.signature(membership),reason..': effective physical stack membership changed')
 for key in pairs(membership)do assert(type(key)=='number' or key=='legacyTags',reason..': unused metadata retained: '..tostring(key))end
 if membership.legacyTags then
  assert(membership.legacyTags~=full.legacyTags,reason..': legacy membership aliases full projection')
 end
 checked=checked+1
 return membership,full,Tags.signature(membership)
end
assert(#Tags.membershipForItem(nil)==0)
local definition=script('Fixture.Shared','foodPerishable_fruit',ItemType.FOOD)
local a,b=item(definition),item(definition)
local context=Tags.newProjectionContext()
local fresh,full,freshKey=parity(a,'fresh',context)
assert(Tags.matches(fresh,{'fresh','fruit'}) and full.itemSignature and full.itemCategory==a.category)
b.freshness='rotten'
local rotten,_,rottenKey=parity(b,'rotten same type',context)
assert(Tags.matches(rotten,{'rotten','fruit'}) and freshKey~=rottenKey,'same-type physical freshness was cached')
a.freshness='stale';local stale,_,staleKey=parity(a,'mutated freshness',context)
assert(Tags.matches(stale,{'stale'}) and staleKey~=freshKey and staleKey~=rottenKey)
a.broken=true;local broken,_,brokenKey=parity(a,'mutated native broken flag',context)
assert(Tags.matches(broken,{'broken'}) and brokenKey~=staleKey)
a.category='foodPerishable_meat';local meat,_,meatKey=parity(a,'mutated same-type category',context)
assert(Tags.matches(meat,{'meat'}) and not Tags.matches(meat,{'fruit'}) and meatKey~=brokenKey)
a.category=nil;parity(a,'native category fallback',context)

local bottle=item(script('Fixture.Bottle','containerLiquid'))
local amount,kind=1,'beverage'
bottle.container={isEmpty=function()return amount==0 end,getAmount=function()return amount end,
 isCategory=function(_,category)return amount>0 and kind==category end,
 getProperties=function()return {getAlcohol=function()return 0 end}end}
local beverage,_,beverageKey=parity(bottle,'current beverage',context)
assert(Tags.matches(beverage,{'beverage','liquid'}))
kind='fuel';local fuel,_,fuelKey=parity(bottle,'mutated fluid contents',context)
assert(Tags.matches(fuel,{'fuel'}) and not Tags.matches(fuel,{'beverage'}) and fuelKey~=beverageKey)
amount=0;local empty,_,emptyKey=parity(bottle,'emptied physical fluid container',context)
assert(Tags.matches(empty,{'empty'}) and not Tags.matches(empty,{'fuel','beverage'},'any') and emptyKey~=fuelKey)

-- Live usage projection must preserve unknown legacy roles, remove known false
-- roles, and keep the original support tags while deriving related capabilities.
-- Keep the ordinary producer as the oracle; only its membership sibling takes
-- the allocation-saving path. Reuse and mutate one role table/context throughout.
do
 local Usage=require 'PZSurvivorToolkit/ItemUsageTags'
 local schema=require 'PZSurvivorToolkit/ItemTagSchema'
 local nativeRead=Usage.read
 local category='FixtureUsageMembership'
 local previousCategory=schema.categories[category]
 local sample=item(script('Fixture.UsageMembership',category))
 local usageContext=Tags.newProjectionContext()
 local roles,states,reads={},{},0
 Usage.read=function(_,physical,projectionContext)
  assert(physical==sample and projectionContext==usageContext,'usage projection changed its live item/context')
  reads=reads+1
  return roles,states,false
 end
 local function expect(reason,expected)
  local before=reads
  local result=parity(sample,reason,usageContext)
  assert(reads==before+2,reason..': full/membership projection stopped reading live usage')
  for id,value in pairs(expected)do
   assert(Tags.matches(result,{id})==value,reason..': unexpected '..id..' membership')
  end
  return result
 end
 local ids={'bandage','disinfectant','dirty','fuel','ignite','treatment','repair','smelting','sharpen','broken','empty'}
 for _,id in ipairs(ids)do
  for _,present in ipairs({false,true})do
   schema.categories[category]=present and {id} or {}
   for _,value in ipairs({'unknown',false,true})do
    for key in pairs(roles)do roles[key]=nil end
    if value~='unknown' then roles[id]=value end
    expect(id..' '..tostring(value)..' with base '..tostring(present),
     {[id]=value=='unknown' and present or value==true})
   end
  end
 end
 local function current(values)
  for key in pairs(roles)do roles[key]=nil end
  for key,value in pairs(values)do roles[key]=value end
 end
 schema.categories[category]={}
 current({bandage=true,disinfectant=true,repair=true,fishBait=true,trapBait=true,spentBattery=false})
 expect('combined live capabilities without inherited support',
  {medical=true,firstaid=true,maintenance=true,fishing=true,trapping=true,bait=true,
   junk=false,crafting=false,electrical=false})
 schema.categories[category]={'medical','firstaid','maintenance','bait','fishing','trapping','crafting','electrical'}
 current({bandage=false,disinfectant=false,repair=false,fishBait=false,trapBait=false,spentBattery=true})
 expect('known negatives with inherited support and spent battery',
  {medical=true,firstaid=true,maintenance=true,fishing=false,trapping=false,bait=false,
   junk=true,crafting=false,electrical=false})
 current({bandage=false,disinfectant=false,repair=false,trapBait=false,spentBattery=false})
 expect('unknown fishing and replenished battery in the same context',
  {medical=true,firstaid=true,maintenance=true,fishing=true,trapping=false,bait=true,
   junk=false,crafting=true,electrical=true})
 schema.categories[category]={'fishing','trapping','crafting','electrical'}
 current({fishBait=false,trapBait=false,spentBattery=true})
 expect('nonbait fishing and trapping survive known bait negatives',
  {fishing=true,trapping=true,bait=false,junk=true,crafting=false,electrical=false})
 schema.categories[category]={'medical','firstaid','maintenance','bait','fishing','trapping','junk','crafting','electrical'}
 current({})
 expect('unknown usage retains all inherited support',
  {medical=true,firstaid=true,maintenance=true,fishing=true,trapping=true,bait=true,
   junk=true,crafting=true,electrical=true})
 schema.categories[category]={}
 expect('unknown usage does not invent support',
  {medical=false,firstaid=false,maintenance=false,fishing=false,trapping=false,bait=false,
   junk=false,crafting=false,electrical=false})

 -- A replacement reader can expose physical preview states. Their managed
 -- fields still suppress unknown current roles, so this must use the old path.
 schema.categories[category]={'fuel','dirty','broken'}
 states[1]={fuel=false,dirty=true}
 expect('physical previews manage unknown current roles',{fuel=false,dirty=false,broken=true})
 states[1].fuel=nil
 expect('mutated physical preview management',{fuel=true,dirty=false,broken=true})
 states[1]=nil
 expect('empty physical previews restore ordinary unknown handling',{fuel=true,dirty=true,broken=true})
 states=nil
 expect('absent physical previews preserve unknown handling',{fuel=true,dirty=true,broken=true})
 Usage.read=nativeRead
 schema.categories[category]=previousCategory
end

local custom='custom:00000000-0000-4000-8000-000000000001'
local deleted='custom:00000000-0000-4000-8000-000000000002'
local catalog=Custom.catalog()
catalog.definitions[custom]={name='Keep'};catalog.definitions[deleted]={name='Deleted',deleted=true}
catalog.types['fixture.shared']={[custom]='add',[deleted]='add',fruit='remove',condiment='add',food='remove'}
a.category='foodPerishable_fruit';a.freshness='fresh';a.broken=false
a.data[Custom.FIELD]={fruit='add',[custom]='remove',seasoning='remove',food='add'}
local overrides=parity(a,'type/item precedence and canonical alias',context)
assert(Tags.matches(overrides,{'fruit'}) and not Tags.matches(overrides,{custom,deleted,'seasoning'},'any'))
local retiredRule=assert(Tags.normalizeRule({exclude={'food'}}))
assert(not Tags.matchesRule(overrides,retiredRule),'retired exclusion disappeared from stack membership')
a.data[Custom.FIELD].food='remove';local removed=parity(a,'retired item exclusion',context)
assert(Tags.matchesRule(removed,retiredRule),'retired removal did not override inherited membership')
a.data[Custom.FIELD]={[custom]='add'};catalog.definitions[custom].deleted=true
local tombstone=parity(a,'live custom deletion',context)
assert(not Tags.matches(tombstone,{custom,deleted},'any'),'deleted custom definition remained effective')
catalog.definitions[custom].deleted=nil
assert(Tags.matches(parity(a,'live custom restoration',context),{custom}),'custom restoration was cached')

-- Membership owns the one metadata table used by Tags.signature. Preview and
-- provenance trees are intentionally unvisited; ordinary projections still
-- return independently mutable full snapshots.
catalog.types={}
local previews={foodStates={'fresh','rotten'},cookingStates={'raw','cooked'},usageStates={{broken=true}},
 mediaStates={{experience=true}},provenance={nested={value=7}}}
local base={'condiment','seasoning','food',custom,deleted,legacyCategory='Food',legacyTags={food=true}}
for key,value in pairs(previews)do base[key]=value end
local nativePairs,pairsRead= pairs,{}
pairs=function(value)
 for key,watched in nativePairs(previews)do if value==watched then pairsRead[key]=(pairsRead[key] or 0)+1 end end
 return nativePairs(value)
end
local member=Custom.projectMembership(base,'Fixture.Shared',nil)
pairs=nativePairs
assert(next(pairsRead)==nil,'membership traversed unused preview/provenance trees')
local ordinary=Custom.project(base,'Fixture.Shared',nil)
assert(Tags.signature(member)==Tags.signature(ordinary),'direct customization canonical/retired/deleted parity failed')
assert(Tags.matches(member,{'seasoning',custom}) and not Tags.matches(member,{deleted}))
assert(member.legacyTags and member.legacyTags~=base.legacyTags)
member.legacyTags.food=nil;assert(base.legacyTags.food and ordinary.legacyTags.food,'membership mutated source/default legacy tags')
for key,value in pairs(previews)do
 assert(member[key]==nil and ordinary[key]~=value,'default projection stopped owning '..key)
end
ordinary.provenance.nested.value=99;ordinary.usageStates[1].broken=false
assert(base.provenance.nested.value==7 and base.usageStates[1].broken,'default nested snapshots alias input')

-- With no custom additions, the physical grouping path sorts membership only
-- once, in the consumer's final signature. It must not precompute the unused
-- automatic itemSignature and sort those same IDs a second time.
a.data={};a.category='foodPerishable_fruit';a.freshness='fresh'
local nativeSort,nonemptySorts=table.sort,0
table.sort=function(values,...)
 if #values>0 then nonemptySorts=nonemptySorts+1 end
 return nativeSort(values,...)
end
local projected=Tags.membershipForItem(a,context)
assert(nonemptySorts==0,'membership precomputed an unused automatic signature')
Tags.signature(projected)
table.sort=nativeSort
assert(nonemptySorts==1,'physical stack membership sorted its IDs more than once')
local default=Tags.forItem(a,context)
assert(default.itemSignature and default.itemCategory and default.legacyCategory and default.foodStates and default.cookingStates,
 'ordinary physical projection lost metadata after membership-only reads')
default.foodStates[1]='changed'
assert(Tags.forItem(a,context).foodStates[1]~='changed','ordinary physical previews stopped owning their state')

-- Share only pure raw-string normalization within an operation. Catalog and
-- physical overrides remain live even when neither the type nor context moves.
local normalizer=Custom.normalizeType
local normalizationCalls={}
Custom.normalizeType=function(value)
 local key=type(value)..':'..tostring(value)
 normalizationCalls[key]=(normalizationCalls[key] or 0)+1
 return normalizer(value)
end
local function calls(value)return normalizationCalls[type(value)..':'..tostring(value)] or 0 end
local live=item(script('Fixture.Normalized','foodPerishable_fruit',ItemType.FOOD))
local sibling=item(live.s)
local operation=Tags.newProjectionContext()
local first=Tags.membershipForItem(live,operation)
local firstKey=Tags.signature(first)
Tags.membershipForItem(sibling,operation)
assert(calls('Fixture.Normalized')==1,'same-type physical copies repeated pure normalization within one operation')
world.types['fixture.normalized']={fruit='remove',seasoning='add'}
local changed=Tags.membershipForItem(live,operation)
assert(Tags.matches(changed,{'seasoning'}) and not Tags.matches(changed,{'fruit'})
 and Tags.signature(changed)~=firstKey,'cached type key froze the current type delta')
world.types['fixture.normalized'].fruit='add';world.types['fixture.normalized'].seasoning='remove'
local changedAgain=Tags.membershipForItem(live,operation)
assert(Tags.matches(changedAgain,{'fruit'}) and not Tags.matches(changedAgain,{'seasoning'}),'in-place type delta mutation was cached')
live.data[Custom.FIELD]={fruit='remove',seasoning='add'}
local itemOverride=Tags.membershipForItem(live,operation)
assert(Tags.matches(itemOverride,{'seasoning'}) and not Tags.matches(itemOverride,{'fruit'}),'cached type key froze the item delta')
live.data[Custom.FIELD].fruit='add';live.data[Custom.FIELD].seasoning='remove'
assert(Tags.matches(Tags.membershipForItem(live,operation),{'fruit'}),'in-place item delta mutation was cached')
local oldWorld=world
world=Custom.empty();world.types['fixture.normalized']={lighting='add'}
live.data={}
local replaced=Tags.membershipForItem(live,operation)
assert(Tags.matches(replaced,{'lighting','fruit'}) and Tags.signature(replaced)~=firstKey,'same-context read retained a previous world catalog')
assert(calls('Fixture.Normalized')==1,'live catalog/delta reads reran the cached pure string transformation')
Tags.membershipForItem(live,Tags.newProjectionContext())
assert(calls('Fixture.Normalized')==2,'a new explicit operation reused an earlier type transformation')
Tags.membershipForItem(live);Tags.membershipForItem(live)
assert(calls('Fixture.Normalized')==4,'omitted context leaked normalization across independent membership operations')

-- The cache is indexed by the current raw string, including invalid strings.
-- A changed physical type cannot borrow its earlier normalized key.
live.s.name='InvalidType'
local invalid=Tags.membershipForItem(live,operation)
Tags.membershipForItem(live,operation)
assert(calls('InvalidType')==1 and not Tags.matches(invalid,{'lighting'}),'invalid raw type borrowed a prior key or repeated normalization')
live.s.name='Fixture.Other';world.types['fixture.other']={maintenance='add'}
local other=Tags.membershipForItem(live,operation)
assert(calls('Fixture.Other')==1 and Tags.matches(other,{'maintenance'}) and not Tags.matches(other,{'lighting'}),
 'mutated physical type retained the previous normalized key')
live.s.name='Fixture.Normalized'
assert(Tags.matches(Tags.membershipForItem(live,operation),{'lighting'}) and calls('Fixture.Normalized')==4,
 'returning to an already seen raw type lost its key or read stale type data')

-- Replacing the normalizer invalidates this operation's existing cache. Test
-- a semantic replacement rather than merely replacing a counting wrapper.
local replacementCalls=0
Custom.normalizeType=function(value)
 replacementCalls=replacementCalls+1
 if value=='InvalidType' then return 'fixture.other' end
 if value=='Fixture.Normalized' then return 'fixture.other' end
 return normalizer(value)
end
local remapped=Tags.membershipForItem(live,operation)
assert(replacementCalls==1 and Tags.matches(remapped,{'maintenance'}) and not Tags.matches(remapped,{'lighting'}),
 'normalizer replacement retained the old successful cached key')
Tags.membershipForItem(live,operation);assert(replacementCalls==1,'replacement normalizer was not batched')
live.s.name='InvalidType'
assert(Tags.matches(Tags.membershipForItem(live,operation),{'maintenance'}) and replacementCalls==2,
 'normalizer replacement retained an old cached invalid-type result')
Custom.normalizeType=normalizer
assert(not Tags.matches(Tags.membershipForItem(live,operation),{'maintenance','lighting'},'any'),
 'restoring the normalizer retained the replacement key')
world=oldWorld
print('Item tag membership: '..checked..' physical parity cases, mutable state, overrides, retired exclusions, owned metadata and single signature sort passed.')
