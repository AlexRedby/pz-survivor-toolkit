-- The native fixture must use the current public taxonomy and owned picker categories.
next=nil -- Stock B42 Kahlua exposes pairs, but has no global next.
package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/?.lua;'..package.path
local Schema=require 'PZSurvivorToolkit/ItemTagSchema'
local Categories=require 'PZSurvivorToolkit/ItemCategories'
local originalRequire=require
require=function(name)
 if name=='PZSurvivorToolkit/QuartermasterContainerConfig'
  or name=='PZSurvivorToolkit/ContainerAppearance'
  or name=='PZSurvivorToolkit/QuartermasterTagRules'then return {} end
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
local actual,packet=F.prepare({getSquare=function()return square end})
assert(actual==obj and packet.category==Categories.forScript(script) and packet.category=='toolCarpentry',
 'Native editor fixture persisted the native loot category instead of the owned picker category')
local value={name=F.name,iconKind='pzst-tag',iconValue=F.tag,
 r=F.color.r,g=F.color.g,b=F.color.b,a=1,category=packet.category,categorySelected=true,
 categoryCount=1,itemCount=0,presetCount=0,priority=6,ruleMode='all',
 include={F.tag,'perishable'},exclude={'meat'},revision=1}
assert(F.matches(value),'Current fixture payload does not match its authority contract')
value.include[1]='food'
assert(not F.matches(value),'Fixture accepted a retired visible tag in the newly edited rule')
value.include[1]=F.tag;value.categorySelected=false
assert(not F.matches(value),'Fixture accepted a rule without its exact category selection')
print('Container configuration fixture uses visible semantic tags and owned categories.')

-- Execute the actual client helper with real rule callbacks and normalization.
-- Only window construction/rendering and the script catalog are stand-ins.
PZSurvivorToolkit.Settings={itemTags=function()return true end}
isClient=function()return false end
ModData={getOrCreate=function()return {} end}
getText=function(key)return key end
getSpecificPlayer=function()return {} end
ISCollapsableWindowJoypad={derive=function()return {} end}
local Tags=originalRequire('PZSurvivorToolkit/ItemTags')
local RulePicker,TagPicker
require=function(name)
 if name:sub(1,5)=='ISUI/' or name=='LootSorter_Categories'then return end
 if name=='PZSurvivorToolkit/UIStyle'then return {fit=function(value)return value end}end
 if name=='PZSurvivorToolkit/TagVisuals'then return {}end
 if name=='PZSurvivorToolkit/ContainerAppearanceControls'then return {select=function()end}end
 if name=='PZSurvivorToolkit/QuartermasterTagRuleClient'then return {}end
 if name=='PZSurvivorToolkit/TagRulePicker'then return RulePicker end
 if name=='PZSurvivorToolkit/QuartermasterTags'then return TagPicker end
 if name=='QueueTestSelection'then return {kind='sp'}end
 if name=='ContainerConfigurationFixture'then return F end
 if name=='PZSurvivorToolkit/ContainerConfigurationMenus' or name=='BetterContainers/Helpers'
  or name=='QueueHealthEvents'then return {}end
 return originalRequire(name)
end
local clientRoot=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/'
RulePicker=dofile(clientRoot..'PZSurvivorToolkit/TagRulePicker.lua')
TagPicker=dofile(clientRoot..'PZSurvivorToolkit/QuartermasterTags.lua')
local opened=0
RulePicker.open=function(options)
 opened=opened+1
 local preview={clear=function()end,addItem=function()end}
 local advanced=setmetatable({owner=options.owner,onApply=options.onApply,
  rule=assert(Tags.normalizeRule(options.rule)),selectionOrder={},sourceScriptItems={},
  entries={{id=F.tag},{id='perishable'},{id='meat'}},preview=preview,list={},group={},
  search={unfocus=function()end},modeButton={setTitle=function()end},
  setVisible=function()end,removeFromUIManager=function()end},{__index=RulePicker})
 options.owner.toolkitRulePicker=advanced
 return advanced
end
Events={OnServerCommand={Add=function()end},OnGameStart={Add=function()end},OnTick={Add=function()end}}
local file=assert(io.open(ProjectRoot..'/tests/native_queue/container-configuration/client/ZZContainerConfiguration.lua'))
local source=file:read('*a');file:close()
local probe=assert(loadstring(source..[[
 return {configure=configureFinalRule,tick=tick,setPicker=function(value)picker=value end,
  finalPhase=function()phase='final-rule' end}
]]))()
local admitted=false
local owner={selectedCats={[packet.category]=true},toolkitTagRule={mode='any',include={F.tag,'medical'},exclude={}},
 toolkitTagCatalog={revision=Tags.revision(),scriptItems={}},activeList=function()return {packet.category}end,
 isReallyVisible=function()return admitted end,getIsVisible=function()return true end}
owner.toolkitTagRuleButton={onclick=function(self)TagPicker.openRule(self,self.toolkitTagRule)end}
probe.setPicker(owner)
local ok,err=pcall(probe.configure)
assert(not ok and tostring(err):find('Advanced Apply lost the final rule',1,true),
 'Unadmitted-owner probe did not reproduce the actual native Apply refusal')
assert(not owner.toolkitRulePicker and owner.toolkitTagRule.mode=='any'
 and table.concat(owner.toolkitTagRule.include,',')=='edible,medical' and #owner.toolkitTagRule.exclude==0,
 'Unadmitted owner changed its draft despite native lifetime protection')
print('Unadmitted owner retains mode=any include=edible,medical exclude=empty; popup closes without Apply.')
-- The real fixture must wait for admission instead of invoking Apply in the opening tick.
probe.finalPhase()
getPlayer=function()return {}end
local beforeOpened=opened
probe.tick()
assert(opened==beforeOpened,'Final-rule phase opened advanced UI before owner admission')
admitted=true
owner.toolkitTagSwitch={onclick=function()error('test: admitted final-rule dispatch')end}
ok,err=pcall(probe.tick)
assert(not ok and tostring(err):find('test: admitted final-rule dispatch',1,true),
 'Admitted final-rule phase did not resume its actual callback path')
probe.configure()
local rule=owner.toolkitTagRule
assert(not owner.toolkitRulePicker and owner.toolkitTagRuleTouched and owner.needRebuild
 and rule.mode=='all' and table.concat(rule.include,',')=='edible,perishable'
 and table.concat(rule.exclude,',')=='meat' and owner.selectedCats[packet.category],
 'Admitted owner failed to receive the complete callback-built final payload')
print('Admitted owner receives mode=all include=edible,perishable exclude=meat; exact owned category retained.')
