local root=ProjectRoot..'/PZSurvivorToolkit/42/media/lua/'
local glassNames={['Fix Window Welding']=true,['Fix Window']=true,['Fix Window 1']=true,
 ['Fix Military Windows Welding']=true}
local ballistic={['Base.BallisticGlassWindowSC2']=true,['Base.BallisticGlassWindshieldSC2']=true}
local function javaList(values)
 local list={values=values or {}}
 function list:size() return #self.values end
 function list:get(index) return self.values[index+1] end
 function list:contains(value) for _,item in ipairs(self.values) do if item==value then return true end end;return false end
 function list:clear() self.values={} end
 function list:remove(index) table.remove(self.values,index+1) end
 function list:add(value) self.values[#self.values+1]=value end
 return list
end
local function fallbackRecipes()
 return {recipes={{name='Fix Window Welding',require='@Window_All'},
  {name='Fix Window',require='@Window_All'},{name='Fix Window 1',require='@Window_All'},
  {name='Fix Military Windows Welding',require={'@MilitaryWindow_All','USMIL.LargeViewportPack0'}},
  {name='Fix Hood',require='@Hood_All'},{name='Fix Military Hood',require='@MilitaryHood_All'}}}
end
local function setup(active,server,upstreamFirst,late,serverOnly)
 local w={loaded={},events={},fixings={},externalLoads=0,sourceCopies={}}
 local vro={}
 local function event(name)
  local callbacks={};w.events[name]=callbacks
  return {Add=function(fn) callbacks[#callbacks+1]=fn end}
 end
 Events={OnInitWorld=event('world'),OnGameBoot=event('boot')}
 isServer=function() return server end
 getActivatedMods=function() return {contains=function(_,id) return id==active end} end
 local function fixing(name,body)
  local value={name=name,fixers=javaList({}),loads=0}
  for material in (body or ''):gmatch('Fixer%s*=%s*([^,\r\n]+)') do value.fixers:add(material) end
  function value:getRequiredItem() return self.required end
  function value:getFixers() return self.fixers end
  function value:Load(_,text)
   self.loads=self.loads+1
   self.required=self.required or javaList({})
   local targets=text:match('Require%s*=%s*([^,}]+)')
   for target in (targets or ''):gmatch('[^;]+') do self.required:add(target:match('^%s*(.-)%s*$')) end
  end
  w.fixings[name]=value
 end
 if VROScriptFixingsSource then
  for name,body in VROScriptFixingsSource:gmatch('fixing%s+([^\r\n{]+)%s*{(.-)}') do
   fixing(name:match('^%s*(.-)%s*$'),body)
  end
 else
  for name in pairs(glassNames) do fixing('VRO '..name,'Fixer = Base.SheetMetal,') end
  fixing('VRO Fix Hood','Fixer = Base.SheetMetal,')
  fixing('VRO Fix Military Hood','Fixer = Base.SheetMetal,')
 end
 for name,value in pairs(w.fixings) do w.sourceCopies[name]={fixers=value.fixers.values, count=value.fixers:size()} end
 ScriptManager={instance={getFixing=function(_,name) return w.fixings[name] end,getItem=function() return {} end}}
 require=function(name)
  if w.loaded[name] then return w.loaded[name] end
  local value
  if name=='PZSurvivorToolkit/VehicleGlass' then value=dofile(root..'shared/'..name..'.lua')
  elseif name=='VRO/Core' then value=vro
  elseif name=='VRO_Recipes' then
   w.externalLoads=w.externalLoads+1
   value=VRORecipesSource and assert(loadstring(VRORecipesSource))() or fallbackRecipes()
  elseif name=='VRO_PartLists' then
   if VROPartListsSource then value=assert(loadstring(VROPartListsSource))()
   else
    vro.PartLists={Window_All={'Base.Windshield1','Base.FrontWindow1'},MilitaryWindow_All={'Base.M998_Windshield2'},
     Hood_All={'Base.EngineDoor1'},MilitaryHood_All={'Base.BallisticGlassWindowSC2','Base.WindowArmor'}}
    value=vro.PartLists
   end
  elseif name=='FixingRecipeHandler' then
   w.externalLoads=w.externalLoads+1
   if VROFixingRegistrationSource then value=assert(loadstring(VROFixingRegistrationSource))()
   else
    local function inject()
     for recipeName in pairs(glassNames) do w.fixings['VRO '..recipeName]:Load('', '{ Require = Base.Windshield1, }') end
     w.fixings['VRO Fix Hood']:Load('', '{ Require = Base.EngineDoor1, }')
     w.fixings['VRO Fix Military Hood']:Load('', '{ Require = Base.BallisticGlassWindowSC2;Base.WindowArmor, }')
    end
    Events.OnInitWorld.Add(inject);if server then Events.OnGameBoot.Add(inject) end
   end
  else error('unexpected require '..name) end
  w.loaded[name]=value or true
  return value
 end
 if upstreamFirst then require('FixingRecipeHandler') end
 if late then
  local list=require('VRO_Recipes').recipes;require('VRO_PartLists')
  vro.Recipes={};for _,recipe in ipairs(list) do vro.Recipes[#vro.Recipes+1]=recipe end
 end
 dofile(root..'shared/000ToolkitVROGlassCompatibility.lua')
 if not serverOnly then dofile(root..'client/000ToolkitVROGlassRecipes.lua') end
 w.vro=vro
 function w.fire(name) for _,fn in ipairs(w.events[name]) do fn() end end
 return w
end

for _,inactive in ipairs({'','OtherMod'}) do
 local w=setup(inactive,false,false,false)
 assert(w.externalLoads==0 and #w.events.world==0 and #w.events.boot==0,'absent VRO must not load upstream or register callbacks')
end
for _,server in ipairs({false,true}) do
 for _,upstreamFirst in ipairs({false,true}) do
  for _,late in ipairs({false,true}) do
   local w=setup(late and '\\VehicleRepairOverhaul' or 'VehicleRepairOverhaul',server,upstreamFirst,late)
   local source=w.loaded.VRO_Recipes.recipes
   local function checkLua(list)
    local count=0
    for _,recipe in ipairs(list) do
     assert(not glassNames[recipe.name],'glass recipe survived early/late registry cleanup')
     if recipe.name=='Fix Hood' then count=count+1 end
     for _,target in ipairs(type(recipe.require)=='table' and recipe.require or {recipe.require}) do
      assert(not ballistic[target],'explicit ballistic glass target survived')
     end
    end
    assert(count==1,'unrelated hood recipe removed or duplicated')
   end
   checkLua(source)
   if late then checkLua(w.vro.Recipes) end
   -- This is the actual upstream loader's append contract; removed source entries cannot reappear.
   if not late then w.vro.Recipes={};for _,recipe in ipairs(source) do w.vro.Recipes[#w.vro.Recipes+1]=recipe end end
   checkLua(w.vro.Recipes)
   for _,items in pairs(w.vro.PartLists) do for _,target in ipairs(items) do assert(not ballistic[target]) end end
   assert(#w.vro.PartLists.Window_All>0 and #w.vro.PartLists.MilitaryWindow_All>0,
    'classification lists must remain available to VRO')
   local glassTypes={['USMIL.LargeViewportPack0']=true,['USMIL.SmallViewportPack0']=true}
   for _,name in ipairs({'Window_All','MilitaryWindow_All'}) do
    for _,target in ipairs(w.vro.PartLists[name]) do glassTypes[target]=true end
   end
   for target in pairs(ballistic) do glassTypes[target]=true end
   local function checkTarget(target)
    if target:sub(1,1)=='@' then
     for _,item in ipairs(w.vro.PartLists[target:sub(2)] or {}) do assert(not glassTypes[item],item..' can still be repaired') end
    else assert(not glassTypes[target],target..' can still be repaired') end
   end
   for _,recipe in ipairs(source) do
    for _,target in ipairs(type(recipe.require)=='table' and recipe.require or {recipe.require}) do checkTarget(target) end
   end
   if server then w.fire('boot') end
   w.fire('world');w.fire('world')
   for name in pairs(glassNames) do
    local fixing=assert(w.fixings['VRO '..name])
    assert(fixing:getRequiredItem():size()==0 and fixing:getFixers():size()==0,
     'script glass repair returned after upstream injection')
   end
   for name,fixing in pairs(w.fixings) do
    if not glassNames[name:sub(5)] then
     assert(fixing:getFixers().values==w.sourceCopies[name].fixers
      and fixing:getFixers():size()==w.sourceCopies[name].count,'unrelated fixer materials changed')
    end
   end
   for _,name in ipairs({'VRO Fix Military Hood Welding','VRO Fix Military Hood'}) do
    local required=w.fixings[name] and w.fixings[name]:getRequiredItem()
    if required then for _,target in ipairs(required.values) do assert(not ballistic[target]) end end
   end
   -- Native getFixes uses required.contains(fullType): no glass definition can match any item.
   local hood=assert(w.fixings['VRO Fix Hood'])
   assert(hood:getRequiredItem():contains('Base.EngineDoor1') and hood:getFixers():size()>0,
    'ordinary hood repair is no longer available')
   local worldCount,bootCount=#w.events.world,#w.events.boot
   dofile(root..'shared/000ToolkitVROGlassCompatibility.lua')
   dofile(root..'client/000ToolkitVROGlassRecipes.lua')
   assert(#w.events.world==worldCount and #w.events.boot==bootCount,'repeat loads stacked policy callbacks')
  end
 end
end
-- Host's separate server process only loads shared/server Lua, not client recipe tables.
do
 local w=setup('VehicleRepairOverhaul',true,false,false,true)
 assert(not w.loaded.VRO_Recipes and not w.loaded.VRO_PartLists,'server policy loaded client-only sources')
 w.fire('boot');w.fire('world')
 for name in pairs(glassNames) do
  assert(w.fixings['VRO '..name]:getRequiredItem():size()==0)
  assert(w.fixings['VRO '..name]:getFixers():size()==0)
 end
 assert(w.fixings['VRO Fix Hood']:getFixers():size()>0,'server removed unrelated material choices')
end
print('PASS replacement-only VRO glass: absent/prefixed mod, early/late load, Lua/script registries, SP/Host callbacks, repeat world injection and preserved other repairs')
if VRORecipesSource then
 print('PASS actual VRO recipe tables, part lists, script fixer definitions and complete FixingRecipeHandler source')
else
 print('SKIP upstream VRO source checks require --vro-source effective content root')
end
