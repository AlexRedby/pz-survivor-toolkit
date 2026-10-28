-- Optional first-open profile. Runs before menu probes can warm the editor.
local Timing = {}
local JSON = require 'QueueHealthEvents'
local Tags = require 'PZSurvivorToolkit/ItemTags'
local Categories = require 'PZSurvivorToolkit/ItemCategories'
local Adapter = require 'PZSurvivorToolkit/QuartermasterTags'
local Rules = require 'PZSurvivorToolkit/TagRulePicker'
local Visuals = require 'PZSurvivorToolkit/TagVisuals'
local Appearance = require 'PZSurvivorToolkit/ContainerAppearanceControls'
local restores, results, active, lastDraw, drawStart, stage, untilAt = {}, {}, nil, nil, nil, 0, 0
local owner, targetWindow
local function wrap(object, key, label, countOnly)
 local original = object[key]
 if type(original) ~= 'function' then return end
 restores[#restores+1] = function() object[key] = original end
 object[key] = function(...)
  if not active then return original(...) end
  local record = active.functions[label] or {calls=0,totalMs=0,maxMs=0}
  active.functions[label] = record; record.calls = record.calls + 1
  if countOnly then return original(...) end
  local start = getTimestampMs()
  local function returned(...)
   local elapsed = getTimestampMs()-start
   record.totalMs=record.totalMs+elapsed;record.maxMs=math.max(record.maxMs,elapsed)
   if object==targetWindow and key=='render' and not active.firstTargetRenderMs then
    active.firstTargetRenderMs=getTimestampMs()-active.started
   end
   return ...
  end
  return returned(original(...))
 end
end
local function watch(window,label)
 targetWindow=window
 wrap(window,'prerender',label..'.prerender')
 wrap(window,'render',label..'.render')
 local list=window.listbox or window.list
 if list then wrap(list,'prerender',label..'.list.prerender');wrap(list,'render',label..'.list.render') end
end
local function preDraw() drawStart=getTimestampMs() end
local function postDraw()
 local now=getTimestampMs()
 if active then
  if lastDraw then active.frameGaps[#active.frameGaps+1]=now-lastDraw end
  active.uiMs[#active.uiMs+1]=drawStart and now-drawStart or 0
  if not active.firstUiPassMs then active.firstUiPassMs=now-active.started end
 end
 lastDraw=now
end
function Timing.begin()
 for _,key in ipairs({'getCategories','getTagScriptItems','getItemNames','getItemsInCategory','getPresetStore'})do
  wrap(LootSorter,key,key)
 end
 for _,key in ipairs({'catalog','rows'})do wrap(Adapter,key,'tags.'..key)end
 wrap(Rules,'catalogEntries','rules.catalogEntries')
 wrap(Tags,'forScriptItem','Tags.forScriptItem',true)
 wrap(Categories,'forScript','Categories.forScript',true)
 wrap(Visuals,'get','Visuals.get')
 wrap(Appearance,'create','appearance.create')
 Events.OnPreUIDraw.Add(preDraw);Events.OnPostUIDraw.Add(postDraw)
 untilAt=getTimestampMs()+2500
end
local function sample(name,action)
 active={name=name,started=getTimestampMs(),functions={},frameGaps={},uiMs={}}
 local start=getTimestampMs();action();active.callbackMs=getTimestampMs()-start
 results[#results+1]=active
end
function Timing.step(obj)
 if getTimestampMs()<untilAt then return false end
 if active then
  assert(#active.frameGaps>=5,'Opening profile did not observe UI frames')
  assert(active.name=='idle' or active.firstTargetRenderMs,'Opening profile did not observe the target window render')
  active=nil
 end
 stage=stage+1
 if stage==1 then sample('idle',function()end)
 elseif stage==2 then sample('containerCold',function()
  LootSorter.openPicker(obj,0,0);owner=assert(LootSorter._picker);watch(owner,'container')
 end)
 elseif stage==3 then sample('ruleCold',function()
  owner:onTagRule();watch(assert(owner.toolkitRulePicker),'rule')
 end)
 elseif stage==4 then sample('chooserCold',function()
  local choice=owner.toolkitRulePicker:addCondition(1);watch(assert(choice),'chooser')
 end)
 elseif stage==5 then
  owner.toolkitRulePicker.tagChoice:close()
  sample('chooserWarm',function()watch(assert(owner.toolkitRulePicker:addCondition(1)),'chooser')end)
 elseif stage==6 then
  owner.toolkitRulePicker:close()
  sample('ruleWarm',function()owner:onTagRule();watch(assert(owner.toolkitRulePicker),'rule')end)
 elseif stage==7 then
  owner:closePicker()
  sample('containerWarm',function()
   LootSorter.openPicker(obj,0,0);owner=assert(LootSorter._picker);watch(owner,'container')
  end)
 else
  owner:closePicker()
  Events.OnPreUIDraw.Remove(preDraw);Events.OnPostUIDraw.Remove(postDraw)
  for i=#restores,1,-1 do restores[i]()end
  print('[CONTAINER_CONFIG] PERF '..JSON.encode({samples=results}))
  return true
 end
 untilAt=getTimestampMs()+800
 return false
end
return Timing
