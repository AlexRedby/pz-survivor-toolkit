local selection = require 'QueueTestSelection'
local JSON = require 'QueueHealthEvents'
local Categories = require 'PZSurvivorToolkit/ItemCategories'
local Rules = require 'PZSurvivorToolkit/ItemCategoryRules'
local started, done, since = false, false, 0
local function emit(event, value) print('[CLASSIFICATION_BASELINE] '..event..' '..JSON.encode(value)) end
local function text(value) return value == nil and '' or tostring(value) end
local differences, instances = 0, 0
local function compare(kind, name, expected, actual)
 if text(expected) ~= text(actual) then
  differences=differences+1
  emit('DIFF',{kind=kind,name=text(name),expected=text(expected),actual=text(actual)})
 end
end
local function prepareReference(item)
 if item:isFluidContainer() then OrganizedCategories.autoSortLiquid(item) end
 OrganizedCategories.applyItemDisplayOverride(item)
end
local function checkItem(item, label)
 instances=instances+1
 local source=item:getScriptItem();local before=text(source:getDisplayCategory())
 prepareReference(item);local expected=text(item:getDisplayCategory())
 Categories.prepareItem(item)
 compare('instance',label,expected,item:getDisplayCategory())
 assert(text(source:getDisplayCategory())==before,'ScriptItem changed for '..label)
end
local function run()
 assert(selection.kind=='sp' and not isClient() and not isServer(),'SP baseline required')
 assert(getActivatedMods():contains('organizedCategories_core'),'Reviewed OC reference absent')
 assert(OrganizedCategories and OrganizedCategories.getScriptInventoryDisplayCategory,'Reference getter absent')
 local scripts=getAllItems();assert(scripts and scripts:size()>5000,'Native item catalog absent/incomplete')
 for i=0,scripts:size()-1 do
  local source=scripts:get(i);local before=text(source:getDisplayCategory())
  local expected=OrganizedCategories.getScriptInventoryDisplayCategory(source)
  compare('script',source:getFullName(),expected,Categories.forScript(source))
  assert(text(source:getDisplayCategory())==before,'Classification changed native ScriptItem '..text(source:getFullName()))
 end
 for _,name in ipairs({'Base.Thread','Base.Primitive_Bow','Base.Axe','Base.CarrotBagSeed2','Base.VHS_Retail'})do
  checkItem(assert(instanceItem(name),'Factory item absent: '..name),name)
 end
 local bottle=assert(instanceItem('Base.WaterBottle'),'WaterBottle factory absent')
 local container=assert(bottle:getFluidContainer(),'Native fluid container absent')
 for _,entry in ipairs({{name='fuel',fluid=Fluid.Petrol},{name='water',fluid=Fluid.Water}})do
  container:Empty();container:addFluid(entry.fluid,math.min(0.5,container:getCapacity()))
  checkItem(bottle,'WaterBottle-'..entry.name)
 end
 container:Empty();checkItem(bottle,'WaterBottle-empty')
 local tape=assert(instanceItem('Base.VHS_Retail'))
 local media=getZomboidRadio():getRecordedMedia():getAllMediaForCategory(tape:getScriptItem():getRecordedMediaCat())
 assert(media and media:size()>0,'Native recorded media registry absent')
 local covered={};local mediaSamples=0
 for i=0,media:size()-1 do
  tape:setRecordedMediaData(media:get(i))
  local refinement=OrganizedCategories.refineMediaCategory(tape,'entertainmentVideo') or 'entertainmentVideo'
  if not covered[refinement] then
   covered[refinement]=true;mediaSamples=mediaSamples+1
   checkItem(tape,'VHS-'..text(media:get(i):getId()))
  end
 end
 assert(mediaSamples>0,'No recorded-media instance checked')
 tape:setRecordedMediaIndexInteger(-1);checkItem(tape,'VHS-unbound')
 local old=assert(instanceItem('Base.Thread'));old:getModData().OC_DisplayCategory='My.Saved.ExactCategory'
 Categories.prepareItem(old);assert(old:getDisplayCategory()=='My.Saved.ExactCategory','Legacy instance override lost')
 emit('VERIFIED',{scripts=scripts:size(),instances=instances,mediaKinds=mediaSamples,differences=differences,
  scriptCategoriesUnchanged=true,legacyOverride=true,role='client1'})
 emit('COMPLETE',{case='parity',role='client1'});done=true
end
Events.OnGameStart.Add(function() started=true;since=getTimestampMs() end)
Events.OnTick.Add(function()
 if not started or done or not isIngameState() or getTimestampMs()-since<2000 then return end
 local player=getPlayer();if not player or not player:getSquare() then return end
 local ok,err=pcall(run)
 if not ok then done=true;emit('FAIL',{message=tostring(err),role='client1'}) end
end)
