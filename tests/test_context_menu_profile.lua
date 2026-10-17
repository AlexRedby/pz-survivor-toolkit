local content='E|legacy|Old entry\nR|legacy|medical\nR|bad|missing\nO|*|root|0|bad\nO|*|root|999999|bad\nP|bad scope|x|medical\n'
getText=function(key) return key end
getFileReader=function()
 local index=0;local lines={};for line in content:gmatch('[^\n]+') do lines[#lines+1]=line end
 return {readLine=function() index=index+1;return lines[index] end,close=function() end}
end
getFileWriter=function()
 content='';return {write=function(_,s) content=content..s end,close=function() end}
end
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
assert(content:find('%%7C') and content:find('%%0A') and content:find('%%25'))
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
content=string.rep('D|Base.Pot|a|A|root\n',20000)..'P|Base.Pot|a|hidden\n'
local large=Profile.new(rules)
assert(large.getOverride('a','Base.Pot')=='hidden','large discovery files must not truncate user rules at the tail')
print('PASS large discovery file retains configuration records')
