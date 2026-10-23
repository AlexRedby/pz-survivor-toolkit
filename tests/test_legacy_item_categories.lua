package.path=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/shared/?.lua;'..package.path
local files, reads, closes, world = {}, {}, 0, 'Save.One'
getCore=function() return {getWorld=function() return world end} end
getFileWriter=function() error('migration must not write legacy files') end
fileDelete=function() error('migration must not remove legacy files') end
getFileReader=function(name, create)
 assert(create==false,'migration tried to create a file');reads[name]=(reads[name] or 0)+1
 local lines=files[name];if not lines then return nil end
 local index=0
 return {readLine=function() index=index+1;if lines.error and index==2 then error('damaged reader') end;return lines[index] end,
  close=function() closes=closes+1 end}
end
local Legacy=require 'PZSurvivorToolkit/LegacyItemCategories'
local global='organizedCategories_displayOverrides.txt'
local perSave='organizedCategories_displayOverrides_Save.One.txt'
files[global]={'C=customSupplies=My Supplies','L=Food=My Food','A=Food=FF0000,1',
 'T=Base.Thread=customSupplies','T=Base.Apple=foodNonPerishable'}
assert(Legacy.forType('base.thread')=='customSupplies' and Legacy.forType('Base.Apple')=='foodNonPerishable')
assert(Legacy.instancesEnabled() and Legacy.forType('Base.Missing')==nil)
assert(reads[global]==1,'legacy file was reread per item')
files[perSave]={'T=Base.Thread=MyExactCategory'}
files['ModOptions.ini']={'tickbox|organizedCategories_core|perSaveDisplayOverrides|true',
 'tickbox|organizedCategories_core|sessionOnlyDisplayOverrides|false','textentry|another_mod|anything|value'}
Legacy.reset();assert(Legacy.forType('BASE.THREAD')=='MyExactCategory')
world='Other/Save';files['organizedCategories_displayOverrides_Other_Save.txt']={'T=Base.Thread=OtherExactCategory'}
assert(Legacy.forType('Base.Thread')=='OtherExactCategory','per-save category leaked between worlds')
world='NoSavedFile';assert(Legacy.forType('Base.Thread')==nil,'missing per-save file imported global assignments')
files['ModOptions.ini'][2]='tickbox|organizedCategories_core|sessionOnlyDisplayOverrides|true'
Legacy.reset();assert(Legacy.forType('Base.Thread')==nil and not Legacy.instancesEnabled(),'session-only mode resurrected stale saved assignments')
files['ModOptions.ini']=nil
for _,invalid in ipairs({{'T=Base.Thread=customSupplies','unrecognized=data'}, {'T=Base.Thread='},
 {'T=../Thread=customSupplies'}, {'T=Base.Thread=custom\0invalid'}, {string.rep('x',2097153)},
 setmetatable({'T=Base.Thread=customSupplies'},{__index={error=true}})}) do
 files[global]=invalid;Legacy.reset()
 assert(Legacy.forType('Base.Thread')==nil,'partially imported corrupt/unrecognized file')
end
files[global]={'T=Base.Thread=Good'};files['ModOptions.ini']={'tickbox|organizedCategories_core|perSaveDisplayOverrides|maybe'}
Legacy.reset();assert(Legacy.forType('Base.Thread')==nil and not Legacy.instancesEnabled(),'invalid mode activated assignments')
assert(closes>0,'readers were not closed')
print('LegacyItemCategories: read-only atomic global/per-save migration, exact IDs, session-only scope and corrupt/missing files passed.')
