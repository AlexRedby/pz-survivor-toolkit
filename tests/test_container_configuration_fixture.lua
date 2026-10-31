-- The native fixture must use the current public taxonomy and owned picker categories.
next=nil -- Stock B42 Kahlua exposes pairs, but has no global next.
package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/?.lua;'..package.path
local Schema=require 'PZSurvivorToolkit/ItemTagSchema'
local Categories=require 'PZSurvivorToolkit/ItemCategories'
isClient=function()return false end
local catalog={}
ModData={getOrCreate=function()return catalog end}
Events={OnClientCommand={Add=function()end},OnInitGlobalModData={Add=function()end}}
getRandomUUID=function()return '01234567-89ab-cdef-0123-456789abcdef'end
local originalRequire=require
require=function(name)
 if name=='PZSurvivorToolkit/QuartermasterContainerConfig'
  or name=='PZSurvivorToolkit/ContainerAppearance'
  or name=='PZSurvivorToolkit/QuartermasterTagRules'then return {} end
 if name=='PZSurvivorToolkit/TagCustomizationAuthority'then
  return dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/server/'..name..'.lua')
 end
 return originalRequire(name)
end
local F=dofile(ProjectRoot..'/tests/native_queue/container-configuration/shared/ContainerConfigurationFixture.lua')
assert(Schema.labels[F.tag] and not (Schema.retiredTags or {})[F.tag],
 'Native editor fixture searches for a retired or unknown visible tag')
local script={getFullName=function()return F.item end,getDisplayCategory=function()return 'ToolWeapon' end}
getScriptManager=function()return {FindItem=function(_,name)assert(name==F.item);return script end}end
-- Native ScriptItem categories remain loot-safe; the owned inventory catalog classifies Hammer separately.
instanceItem=function()return {getDisplayCategory=function()return script:getDisplayCategory()end}end
local square={getX=function()return 10 end,getY=function()return 20 end,getZ=function()return 0 end,
 canStand=function()return true end,isFree=function()return true end,
 getObjects=function()return {size=function()return 1 end}end,AddSpecialObject=function()end}
local cell={getGridSquare=function()return square end}
getCell=function()return cell end
isServer=function()return false end
local container={setType=function()end,setCapacity=function()end,setExplored=function()end}
local md={}
local obj={setBlockAllTheSquare=function()end,setIsContainer=function()end,
 getContainer=function()return container end,getModData=function()return md end,
 getObjectIndex=function()return 1 end}
IsoThumpable={new=function()return obj end}
local actual,packet=F.prepare({getSquare=function()return square end,getCurrentSquare=function()return square end,
 isDead=function()return false end,getOnlineID=function()return 1 end})
assert(actual==obj and packet.category==Categories.forScript(script) and packet.category=='toolCarpentry',
 'Native editor fixture persisted the native loot category instead of the owned picker category')
assert(packet.customId=='custom:01234567-89ab-cdef-0123-456789abcdef'
 and packet.customName==F.customName and F.customReady(packet)
 and md.PZSTContainerConfigurationCustomTag==packet.customId,
 'Production authority did not allocate and publish the owned custom tag')
local value={name=F.name,iconKind='pzst-tag',iconValue=F.tag,
 r=F.color.r,g=F.color.g,b=F.color.b,a=1,category=packet.category,categorySelected=true,
 categoryCount=1,itemCount=0,presetCount=0,priority=6,ruleMode='',include={},exclude={},
 customId=packet.customId,customName=F.customName,
 groups={{include={F.tag,'perishable'},exclude={'meat'}},
  {include={'mechanics'},exclude={'vehiclepart'}},{include={packet.customId},exclude={}}},revision=1}
assert(F.matches(value),'Current fixture payload does not match its authority contract')
value.groups[1].include[1]='food'
assert(not F.matches(value),'Fixture accepted a retired visible tag in the newly edited rule')
value.groups[1].include[1]=F.tag;value.categorySelected=false
assert(not F.matches(value),'Fixture accepted a rule without its exact category selection')
print('Container configuration fixture uses visible semantic tags and owned categories.')

-- Execute the actual client helper with real rule callbacks and normalization.
-- Window construction/rendering, chooser presentation and the script catalog are stand-ins.
PZSurvivorToolkit.Settings={itemTags=function()return true end}
isClient=function()return false end
getText=function(key)return key end
getSpecificPlayer=function()return {} end
ISCollapsableWindowJoypad={derive=function()return {} end}
local Tags=originalRequire('PZSurvivorToolkit/ItemTags')
local RulePicker,TagPicker
local encoded={}
require=function(name)
 if name:sub(1,5)=='ISUI/' or name=='LootSorter_Categories'then return end
 if name=='PZSurvivorToolkit/UIStyle'then return {fit=function(value)return value end}end
 if name=='PZSurvivorToolkit/TagVisuals'then return {}end
 if name=='PZSurvivorToolkit/TagRuleTagPicker'then return {}end
 if name=='PZSurvivorToolkit/ContainerAppearanceControls'then return {select=function()end}end
 if name=='PZSurvivorToolkit/QuartermasterTagRuleClient'then return {}end
 if name=='PZSurvivorToolkit/TagRulePicker'then return RulePicker end
 if name=='PZSurvivorToolkit/QuartermasterTags'then return TagPicker end
 if name=='QueueTestSelection'then return {kind='sp'}end
 if name=='ContainerConfigurationFixture'then return F end
 if name=='PZSurvivorToolkit/ContainerConfigurationMenus' or name=='BetterContainers/Helpers'then return {}end
 if name=='QueueHealthEvents'then return {encode=function(value)encoded[#encoded+1]=value;return 'encoded'end}end
 return originalRequire(name)
end
local clientRoot=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'
RulePicker=dofile(clientRoot..'PZSurvivorToolkit/TagRulePicker.lua')
TagPicker=dofile(clientRoot..'PZSurvivorToolkit/QuartermasterTags.lua')
local opened=0
RulePicker.open=function(options)
 opened=opened+1
 local list={items={},height=200,itemheight=32,
  getYScroll=function()return 0 end,setScrollHeight=function()end,
  setYScroll=function()end,ensureVisible=function()end,
  clear=function(self)self.items={}end,
  addItem=function(self,label,item)self.items[#self.items+1]={text=label,item=item}end}
 local advanced=setmetatable({owner=options.owner,onApply=options.onApply,
  rule=assert(Tags.normalizeRule(options.rule)),conditions={},selectionOrder={},list=list,
  applyButton={setEnable=function()end},
  setVisible=function()end,removeFromUIManager=function()end},{__index=RulePicker})
 options.owner.toolkitRulePicker=advanced
 return advanced
end
RulePicker.chooseTag=function(self,onPick)
 local chooser={search={setText=function(self,value)self.value=value end},
  choose=function(self,row)onPick(row.id);self:close()end,
  close=function()self.tagChoice=nil end}
 self.tagChoice=chooser
 return chooser
end
Events={OnServerCommand={Add=function()end},OnGameStart={Add=function()end},OnTick={Add=function()end}}
local file=assert(io.open(ProjectRoot..'/tests/native_queue/container-configuration/client/ZZContainerConfiguration.lua'))
local source=file:read('*a');file:close()
local probe=assert(loadstring(source..[[
 return {configure=configureFinalRule,assertGrouped=assertGroupedConditions,parity=checkScriptChoiceParity,
  tick=tick,setPicker=function(value)picker=value end,
  setPacket=function(value)packet=value end,
  finalPhase=function()phase='final-rule' end}
]]))()
local admitted=false
local owner={selectedCats={[packet.category]=true},toolkitTagRule={mode='any',include={F.tag,'medical'},exclude={}},
 toolkitTagCatalog={revision=Tags.revision(),scriptItems={}},activeList=function()return {packet.category}end,
 isReallyVisible=function()return admitted end,getIsVisible=function()return true end}
owner.toolkitTagRuleButton={onclick=function(self)TagPicker.openRule(self,self.toolkitTagRule)end}
probe.setPicker(owner)
probe.setPacket(packet)
-- The real fixture must wait for admission instead of invoking Apply in the opening tick.
probe.finalPhase()
getPlayer=function()return {}end
local beforeOpened=opened
probe.tick()
assert(opened==beforeOpened,'Final-rule phase opened advanced UI before owner admission')
admitted=true
owner.toolkitTagSwitch={onclick=function()error('test: admitted final-rule dispatch')end}
local ok,err=pcall(probe.tick)
assert(not ok and tostring(err):find('test: admitted final-rule dispatch',1,true),
 'Admitted final-rule phase did not resume its actual callback path')
probe.configure()
local advanced=assert(owner.toolkitRulePicker)
assert(advanced.tagChoice.search.value==Tags.label(F.tag) and #advanced.conditions==0,
 'Final-rule fixture did not open and filter a chooser from a blank grouped draft')
assert(owner.toolkitTagRule.mode=='any' and table.concat(owner.toolkitTagRule.include,',')=='edible,medical',
 'Opening the grouped fixture changed its owner before Apply')
advanced.tagChoice:choose({id=F.tag})
advanced:addCondition(1,'perishable');advanced:addCondition(1,'meat',true)
advanced:addGroup('mechanics');advanced:addCondition(2,'vehiclepart',true)
advanced:addGroup(packet.customId)
probe.assertGrouped(advanced)
admitted=false
advanced:apply()
assert(not owner.toolkitRulePicker and not owner.toolkitTagRuleTouched,
 'Unadmitted owner accepted the grouped rule despite native lifetime protection')
admitted=true
probe.configure();advanced=assert(owner.toolkitRulePicker)
advanced.tagChoice:choose({id=F.tag})
advanced:addCondition(1,'perishable');advanced:addCondition(1,'meat',true)
advanced:addGroup('mechanics');advanced:addCondition(2,'vehiclepart',true)
advanced:addGroup(packet.customId)
probe.assertGrouped(advanced);advanced:apply()
local rule=owner.toolkitTagRule
assert(not owner.toolkitRulePicker and owner.toolkitTagRuleTouched and owner.needRebuild
 and rule.groups and #rule.groups==3
 and table.concat(rule.groups[1].include,',')=='edible,perishable'
 and table.concat(rule.groups[1].exclude,',')=='meat'
 and table.concat(rule.groups[2].include,',')=='mechanics'
 and table.concat(rule.groups[2].exclude,',')=='vehiclepart'
 and rule.groups[3].include[1]==packet.customId and #rule.groups[3].exclude==0
 and owner.selectedCats[packet.category],
 'Admitted owner failed to receive the complete callback-built final payload')
print('Admitted owner receives semantic and authority-created custom branches and retains its exact owned category.')

-- The optional native audit compares complete batches with separate shared contexts.
local originalProjection,originalChoices,originalContext,originalFast=
 Tags.forScriptItem,Tags.choices,Tags.newScriptProjectionContext,Tags.choicesForScriptItem
local contexts,referenceCalls,fastCalls={},0,0
Tags.newScriptProjectionContext=function()local context={};contexts[#contexts+1]=context;return context end
local scripts={{getFullName=function()return 'Fixture.First'end},{getFullName=function()return 'Fixture.Second'end}}
getAllItems=function()return {size=function()return #scripts end,get=function(_,index)return scripts[index+1]end}end
Tags.forScriptItem=function(script,context)
 referenceCalls=referenceCalls+1;assert(context==contexts[1],'Reference batch did not reuse its context')
 return {'first',script:getFullName(),legacyCategory='fixture'}
end
Tags.choices=function(tags)return {tags[1],tags[2]}end
local mismatch
Tags.choicesForScriptItem=function(script,context)
 fastCalls=fastCalls+1;assert(context==contexts[2] and context~=contexts[1],'Fast batch reused the reference context')
 local choices={'first',script:getFullName(),legacyCategory='fixture'}
 if mismatch=='count'then table.remove(choices,2)
 elseif mismatch=='order'then choices[1],choices[2]=choices[2],choices[1]
 elseif mismatch=='category'then choices.legacyCategory='other'end
 return choices
end
probe.parity()
assert(#contexts==2 and referenceCalls==2 and fastCalls==2 and #encoded==1 and encoded[1].scripts==2,
 'Native parity audit omitted scripts or emitted the wrong receipt')
for _,kind in ipairs({'count','order','category'})do
 mismatch=kind;contexts={}
 local accepted=pcall(probe.parity)
 assert(not accepted and #encoded==1,'Native parity audit accepted a '..kind..' mismatch')
end
Tags.forScriptItem,Tags.choices,Tags.newScriptProjectionContext,Tags.choicesForScriptItem=
 originalProjection,originalChoices,originalContext,originalFast
print('Native script parity compares count, order and category with independent batch contexts.')
