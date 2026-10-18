package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/?.lua;'..package.path
getText=function(key) return key end
local Profile=dofile(ProjectRoot..'/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ContextMenuProfile.lua')
local Tags=require 'PZSurvivorToolkit/ItemTags'
local rules={groups={'equipment','medical','world'}}
local disk=dofile(ProjectRoot..'/tests/support/context_menu_files.lua')()
local legacy='G|custom:1|Kitchen\nE|drop|Drop|world\nR|drop|custom:1\nI|Base.Pot|Pot\nN|*|equipment|Hands\nO|*|root|1|drop\nF|tags:1|Food|all\nA|tags:1|include|food\nP|tags:1|drop|hidden\n'
local a,b='PZSurvivorToolkit_ContextMenus_a.txt','PZSurvivorToolkit_ContextMenus_b.txt'
for _,failure in ipairs({'nilReader','open','read','close'}) do
 disk.reset(legacy);disk.faults[a]={[failure]=true}
 local blocked=Profile.new(rules,Tags)
 assert(blocked.storageError=='ReadFailed' and type(blocked.setOverride)=='function')
 blocked.record('Base.Pot','new','New discovery','world')
 assert(not blocked.setOverride('drop','hidden') and not blocked.save() and disk.writes==0)
 assert(disk.files['PZSurvivorToolkit_ContextMenus.ini']==legacy)
 disk.faults={}
 assert(blocked.ensureLoaded() and blocked.getOverride('drop')=='custom:1')
 assert(blocked.discovered['Base.Pot'].new and blocked.tagProfiles[1].id=='tags:1')
 assert(blocked.setOverride('new','medical') and Profile.new(rules,Tags).getOverride('new')=='medical')
end
assert(disk.opened==disk.closed,'profile reader leak')
for _,fault in ipairs({{nilWriter=true},{writerOpen=true},{prefix=0},{prefix=20},{prefix=20,write=true},
 {prefix=20,writerClose=true},{writerClose=true},{readback=true}}) do
 disk.reset(legacy)
 local editable=Profile.new(rules,Tags);assert(editable.save())
 local previous=disk.files[a]
 local notifications=0;editable.settingsChanged=function() notifications=notifications+1 end
 disk.faults[b]=fault
 assert(not editable.renameGroup('equipment','Attempted rename'))
 assert(editable.storageError=='WriteFailed' and editable.groupName('equipment')=='Hands')
 assert(editable.getOverride('drop')=='custom:1' and editable.tagProfiles[1].id=='tags:1')
 assert(editable.getOrder('*','root')[1]=='drop' and notifications==0,'failed change notified/applied')
 assert(disk.files[a]==previous and disk.files['PZSurvivorToolkit_ContextMenus.ini']==legacy)
 disk.faults={}
 assert(editable.ensureLoaded())
 local ambiguous=not fault.prefix and (fault.writerClose or fault.readback)
 assert(editable.groupName('equipment')==(ambiguous and 'Attempted rename' or 'Hands'))
 assert(editable.renameGroup('equipment','Verified rename') and notifications==1)
 local cold=Profile.new(rules,Tags)
 assert(cold.groupName('equipment')=='Verified rename' and cold.getOverride('drop')=='custom:1')
 assert(cold.getOverride('drop','*',{'tags:1'})=='hidden' and cold.items['Base.Pot']=='Pot')
end
-- A stale editor must reload another writer's profile rather than erase it.
disk.reset(legacy)
local older,newer=Profile.new(rules,Tags),Profile.new(rules,Tags)
assert(newer.setOverride('other','medical'))
local writes=disk.writes
assert(not older.setOverride('drop','hidden') and disk.writes==writes)
assert(older.ensureLoaded() and older.getOverride('other')=='medical' and older.getOverride('drop')=='custom:1')
print('PASS stable profile object, blocked-load retry, discovery merge, rollback, ambiguous commits, cold reload and stale writers')
