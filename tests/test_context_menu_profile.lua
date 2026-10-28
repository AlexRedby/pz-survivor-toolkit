local content='E|legacy|Old entry\nR|legacy|medical\nR|bad|missing\nO|*|root|0|bad\nO|*|root|999999|bad\nP|bad scope|x|medical\n'
getText=function(key) return key end
package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/?.lua;'..package.path
local disk=dofile(ProjectRoot..'/tests/support/context_menu_files.lua')(content)
local Profile=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ContextMenuProfile.lua')
local rules={groups={'equipment','medical','world'}}
local model=Profile.new(rules)
assert(model.getOverride('legacy')=='medical' and model.getOverride('bad')==nil)
assert(#model.getOrder('*','root')==0 and model.scoped['bad scope']==nil,'malformed records accepted')
local custom=assert(model.createGroup('Kitchen | Кухня'))
assert(model.renameGroup(custom,'Name % | with unicode: Кухня','Base.Pot'))
local key='label:pipe|percent%\nnewline'
assert(model.setOverride(key,custom,'Base.Pot'))
assert(model.setOrder('Base.Pot','root',{'group:'..custom,key}))
model.items['Base.Pot']='Кастрюля'
model.record('Base.Pot',key,'Escaped | entry','root');model.save()
local saved=table.concat({disk.files['PZSurvivorToolkit_ContextMenus_a.txt'],disk.files['PZSurvivorToolkit_ContextMenus_b.txt']})
assert(saved:find('%%7C') and saved:find('%%0A') and saved:find('%%25'))
assert(disk.files['PZSurvivorToolkit_ContextMenus.ini']==content,'legacy import was overwritten')
local again=Profile.new(rules)
assert(again.getOverride(key,'Base.Pot')==custom and again.getOverride(key,'Base.Hammer')==nil)
assert(again.groupName(custom,'Base.Pot')=='Name % | with unicode: Кухня' and again.items['Base.Pot']=='Кастрюля')
assert(again.getOrder('Base.Pot','root')[2]==key and again.getEntries('Base.Pot')[1].label=='Escaped | entry')
assert(not again.setOverride('x','missing') and not again.setOrder('*','root',{'x','x'}))
assert(not again.renameGroup('root','Forbidden') and not again.createGroup('') and not again.renameGroup(custom,'in\nvalid'))
assert(not again.deleteGroup('equipment'))
again.setOverride('a',custom);again.setOverride('b',custom,'Base.Pot')
again.deleteGroup(custom)
assert(again.getOverride('a')==nil and again.getOverride('b','Base.Pot')==nil and #again.getOrder('Base.Pot','root')==1)
again.reset();local reset=Profile.new(rules)
assert(reset.getOverride('legacy')==nil and #reset.groupIds()==3 and reset.entries.legacy,'reset must retain discovery but clear preferences')

reset.record('*','eat','Eat','consume')
reset.captureLayout('*',{root={{key='eat',label='Eat',kind='action'}}})
assert(reset.getEntries('*')[1].category=='root','compact defaults must use actual placement')
reset.captureLayout('*',{root={{key='a',label='A',kind='action'},{key='title:section',label='Section',kind='title'},{key='b',label='B',kind='action'}}})
assert(not reset.moveEntry('*','root','b',-1))
reset.setOrder('*','root',{'b','a'})
local layout=reset.getLayout('*','root')
assert(layout[1].key=='a' and layout[2].kind=='title' and layout[3].key=='b','preview must honor the same title barriers as native menu')
print('Context menu profile checks passed: legacy and escaped persistence, validation, scoped inheritance, deletion, resets and exact preview placement.')
disk.reset(string.rep('D|Base.Pot|a|A|root\n',20000)..'P|Base.Pot|a|hidden\n')
local large=Profile.new(rules)
assert(large.getOverride('a','Base.Pot')=='hidden','large discovery files must not truncate user rules at the tail')
print('PASS large discovery file retains configuration records')

package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/?.lua;'..package.path
local Tags=require 'PZSurvivorToolkit/ItemTags'
disk.reset('')
local tagged=Profile.new(rules,Tags)
local kitchen=assert(tagged.createTagProfile('Kitchen | Кухня',{include={'cooking'}}))
local weapons=assert(tagged.createTagProfile('Weapons',{include={'weapon'}}))
assert(not tagged.createTagProfile('Empty',{}) and not tagged.createTagProfile('Invalid',{include={'unknown'}}))
assert(not tagged.updateTagProfile(kitchen,'Empty',{}))
tagged.rememberItem('Base.Pot','Pot',Tags.forCategory('CookingWeapon'))
tagged.rememberItem('Base.Bowl','Bowl',Tags.forCategory('Cooking'))
tagged.rememberItem('Base.Hammer','Hammer',Tags.forCategory('Tool'))
assert(tagged.matchingTagProfiles({tagged.typeTags['Base.Pot']})[1]==kitchen)
assert(#tagged.matchingTagProfiles({tagged.typeTags['Base.Pot'],tagged.typeTags['Base.Bowl']})==1)
assert(#tagged.matchingTagProfiles({tagged.typeTags['Base.Pot'],tagged.typeTags['Base.Hammer']})==0)
assert(#tagged.matchingTagProfiles({})==0)
tagged.setOverride('drop','hidden')
tagged.setOverride('drop','root',kitchen)
tagged.setOverride('drop','medical',weapons)
tagged.renameGroup('equipment','General hands')
tagged.renameGroup('equipment','Weapon hands',weapons)
tagged.setOrder('*','root',{'drop','equip'})
tagged.setOrder(weapons,'root',{'equip','drop'})
assert(tagged.getOverride('drop','Base.Pot')=='root' and tagged.getOverride('drop','Base.Hammer')=='hidden')
assert(tagged.groupName('equipment','Base.Pot')=='Weapon hands','unset higher field must inherit a lower matching profile')
assert(tagged.getOrder('Base.Pot','root')[1]=='equip')
assert(tagged.getOwnOverride('drop','Base.Pot')==nil)
assert(tagged.getOverride('drop','Base.Pot',{})=='hidden','explicit disabled/mixed context must not infer tags')
assert(tagged.getOverride('drop','*',{kitchen})=='root','mixed matching selections should use shared profiles')
assert(tagged.getOverride('drop','*','Base.Pot')=='hidden','global editor scope must not inherit item profiles')
assert(tagged.moveTagProfile(weapons,-1))
assert(tagged.getOverride('drop','Base.Pot')=='medical','higher priority profile did not win')
tagged.setOverride('drop','equipment','Base.Pot')
assert(tagged.getOverride('drop','Base.Pot')=='equipment','exact type must win over tags')
tagged.reset('Base.Pot')
assert(tagged.getOverride('drop','Base.Pot')=='medical' and tagged.getTagProfile(weapons))
for _,id in ipairs({'Base.Pot','Base.Bowl','Base.Hammer'}) do
 tagged.record(id,'drop','Drop','root');tagged.record(id,'equip','Equip','equipment')
 tagged.captureLayout(id,{root={{key='drop',label='Drop',kind='action'},{key='group:equipment',label='Hands',kind='group',category='equipment'}},equipment={{key='equip',label='Equip',kind='action'}}})
end
assert(#tagged.getEntries(kitchen)==2)
assert(#tagged.getLayout(kitchen,'root','Base.Hammer')==0,'nonmatching sample should not preview tag rules')
assert(#tagged.getLayout(kitchen,'root','Base.Pot')==2)
assert(tagged.moveEntry(kitchen,'root','drop',1,'Base.Pot'),'preview-aware ordering failed')
local exactCategory=assert(tagged.createTagProfile('Exact category',{include={'category:CookingWeapon'}}))
assert(tagged.matchingTagProfiles({tagged.typeTags['Base.Pot']})[3]==exactCategory,'lost legacy category before persistence')
tagged.save()
local restored=Profile.new(rules,Tags)
assert(#restored.tagProfiles==3 and restored.tagProfiles[1].id==weapons and restored.tagProfiles[2].name=='Kitchen | Кухня')
assert(restored.getOverride('drop','Base.Pot')=='medical' and #restored.getEntries(kitchen)==2)
assert(restored.typeTags['Base.Pot'].legacyCategory=='CookingWeapon')
assert(restored.matchingTagProfiles({restored.typeTags['Base.Pot']})[3]==exactCategory,'exact-category predicate changed after restart')
restored.reset(weapons)
assert(restored.getTagProfile(weapons) and restored.getOverride('drop','Base.Pot')=='root','profile reset should retain filter and inherit lower fields')
assert(restored.deleteTagProfile(kitchen) and not restored.getTagProfile(kitchen) and not restored.scoped[kitchen])
assert(restored.getOverride('drop','Base.Pot')=='hidden','deleting tag profile must restore inheritance')
restored.reset()
assert(#restored.tagProfiles==0 and restored.getOverride('drop','Base.Pot')==nil and restored.items['Base.Pot'])
disk.reset('P|tags:1|drop|hidden\nF|tags:1|Invalid|all\nA|tags:1|include|not-a-tag\nF|tags:2|Empty|all\n')
local invalid=Profile.new(rules,Tags)
assert(#invalid.tagProfiles==0 and not invalid.scoped['tags:1'],'invalid persisted filters must not activate scoped rules')
print('PASS tag profile precedence, field inheritance, mixed selections, sample isolation, escaped persistence, exact-category matching, validation and resets')

-- The shared rule editor can save OR branches without changing profile inheritance.
disk.reset('')
local groupedModel=Profile.new(rules,Tags)
local draft={groups={{include={'mechanics'},exclude={'vehiclepart'}},{include={'perishable'},exclude={}}}}
local groupedID=assert(groupedModel.createTagProfile('Mechanics | food %',draft))
draft.groups[1].include[1]='food'
assert(groupedModel.getTagProfile(groupedID).rule.groups[1].include[1]=='mechanics','grouped profile aliases editor draft')
local anyID=assert(groupedModel.createTagProfile('Legacy any',{mode='any',include={'food','mechanics'},exclude={'vehiclepart'}}))
groupedModel.rememberItem('Base.Tool','Tool',{'mechanics'})
groupedModel.rememberItem('Base.Food','Food',{'perishable','vehiclepart'})
groupedModel.rememberItem('Base.Part','Part',{'mechanics','vehiclepart'})
assert(groupedModel.setOverride('drop','hidden',groupedID))
assert(groupedModel.renameGroup('equipment','Grouped hands',groupedID))
assert(groupedModel.setOrder(groupedID,'root',{'drop','equip'}))
assert(groupedModel.getOverride('drop','Base.Tool')=='hidden' and groupedModel.getOverride('drop','Base.Food')=='hidden')
assert(groupedModel.getOverride('drop','Base.Part')==nil,'branch exclusion escaped or disappeared')
assert(groupedModel.matchingTagProfiles({{'mechanics'},{'perishable','vehiclepart'}})[1]==groupedID,
 'mixed selection lost distinct matching OR branches')
local groupedReload=Profile.new(rules,Tags)
local groupedRule=groupedReload.getTagProfile(groupedID).rule
assert(groupedRule.groups[1].include[1]=='mechanics' and #groupedRule.groups==2)
assert(Tags.matchesRule({'mechanics'},groupedRule) and Tags.matchesRule({'perishable','vehiclepart'},groupedRule))
assert(not Tags.matchesRule({'mechanics','vehiclepart'},groupedRule))
assert(groupedReload.getTagProfile(anyID).rule.mode=='any','v2 storage changed legacy rule shape')
assert(groupedReload.getOverride('drop','Base.Tool')=='hidden' and groupedReload.groupName('equipment','Base.Tool')=='Grouped hands')
assert(groupedReload.getOrder('Base.Tool','root')[2]=='equip','grouped profile lost scoped preferences on reload')
local negative={groups={{exclude={'vehiclepart'}},{include={'perishable'}}}}
assert(groupedReload.updateTagProfile(groupedID,'Negative branch',negative))
local negativeReload=Profile.new(rules,Tags).getTagProfile(groupedID).rule
assert(Tags.matchesRule({},negativeReload) and not Tags.matchesRule({'vehiclepart'},negativeReload)
 and Tags.matchesRule({'vehiclepart','perishable'},negativeReload),'negative-only branch changed after reload')
local large={mode='any',include={},exclude={}}
for index=1,64 do large.include[index]='category:Include'..index;large.exclude[index]='category:Exclude'..index end
local largeID=assert(groupedReload.createTagProfile('Legacy limit',large))
local largeRule=Profile.new(rules,Tags).getTagProfile(largeID).rule
assert(largeRule.mode=='any' and #largeRule.include==64 and #largeRule.exclude==64,'legacy rule limit did not survive mixed v2 storage')
local escaped={groups={{include={'category:Part|100%'}},{exclude={'food'}}}}
local escapedID=assert(groupedReload.createTagProfile('Escaped grouped',escaped))
local escapedReload=Profile.new(rules,Tags).getTagProfile(escapedID).rule
assert(escapedReload.groups[1].include[1]=='category:Part|100%' and Tags.matchesRule({'category:Part|100%'},escapedReload))
local Storage=require 'PZSurvivorToolkit/ContextMenuProfileStorage'
assert(Storage.load().version==2,'grouped profile was saved in an unversioned legacy envelope')
local before=disk.writes
assert(not groupedReload.createTagProfile('Empty branches',{groups={}})
 and not groupedReload.createTagProfile('Unconditional',{groups={{},{include={'food'}}}})
 and not groupedReload.updateTagProfile(groupedID,'Conflicting',{groups={{include={'food'},exclude={'food'}}}}))
assert(disk.writes==before,'invalid grouped editor input reached storage')
local tooMany={};for index=1,65 do tooMany[index]={include={'food'}} end
assert(not groupedReload.createTagProfile('Too many',{groups=tooMany}) and disk.writes==before)

local header='F|tags:1|Grouped|groups|2'
local terms={'B|tags:1|1|include|mechanics','B|tags:1|1|exclude|vehiclepart','B|tags:1|2|include|perishable'}
local malformed={
 {header,'B|tags:1|0|include|food'}, {header,'B|tags:1|3|include|food'},
 {header,'B|tags:1|01|include|food'}, {header,'B|tags:1|1|other|food'},
 {header,'B|tags:1|1|include|food|extra'}, {header,'A|tags:1|include|food'},
 {header,'B|tags:1|1|include|not-a-tag'},
 {header,'B|tags:1|1|include|food','B|tags:1|1|exclude|food'},
 {header,header}, {'F|tags:1|Grouped|groups|0'}, {'F|tags:1|Grouped|groups|65'},
 {'F|tags:1|Grouped|groups|01'}, {'F|tags:1|Grouped|groups|2|extra'},
}
local overLimit={header}
for index=1,65 do overLimit[#overLimit+1]='B|tags:1|1|include|category:Term'..index end
malformed[#malformed+1]=overLimit
for _,records in ipairs(malformed) do
 disk.reset('')
 local lines={};for _,record in ipairs(records) do lines[#lines+1]=record end
 for _,record in ipairs(terms) do lines[#lines+1]=record end
 lines[#lines+1]='P|tags:1|drop|hidden'
 Storage.save(Storage.load(),lines,2)
 local invalidGrouped=Profile.new(rules,Tags)
 assert(#invalidGrouped.tagProfiles==0 and not invalidGrouped.scoped['tags:1'],
  'malformed grouped profile activated its scoped preferences')
end
disk.reset('')
Storage.save(Storage.load(),{header,unpack(terms)},1)
assert(#Profile.new(rules,Tags).tagProfiles==0,'legacy envelope accepted grouped profile records')
print('PASS grouped profile branches, negative-only conditions, legacy limits, escaped persistence, inherited scopes and bounded malformed records')
