local root=ProjectRoot..'/tests/native_tags/'
local baseline=BaselineTagReconnect==true
local restart=RestartTagReconnect==true
local cases=restart and {'server-restart','restart-sort'} or baseline and {'configure','reopen','sort','baseline-reconnect'} or {'configure','reopen','icons','inventory-all','inventory-any','inventory-exclude','preset-save','inventory-empty',
 'preset-apply','rule-save','rule-reopen','rule-stale','rule-peer','rule-toggle','sort','rule-reconnect'}
local files={['smoke-user.txt']='client1',['queue-health-language.txt']='EN',['tag-fixture-reconnect.txt']='pending'}
if restart then files['tag-fixture-reconnect.txt']=nil end
getFileReader=function(path)
 local value=files[path];if not value then return end
 return {readLine=function() return value end,close=function() end}
end
getFileWriter=function(path) return {write=function(_,value) files[path]=value end,close=function() end} end
local now,events,commands=1000,{},{}
getTimestampMs=function() return now end
local Fixture=dofile(root..'shared/TagFixture.lua')
local presetStored,presetReads,presetDeletes=true,0,0
local providerOptions={showAdvancedDisplayCategories=true}
local providerPanel={getOption=function(_,id)
 assert(id=='showAdvancedDisplayCategories')
 return {setValue=function(_,value) providerOptions.showAdvancedDisplayCategories=value end}
end,apply=function() providerOptions.applied=true end}
local originalRequire=require
require=function(name)
 if name=='QueueTestSelection' then return {tagRules=not baseline,tagRestart=restart and {} or nil,cases=cases,port=19101} end
 if name=='TagTestEvents' then return {emit=function(event) events[#events+1]=event end,encode=function() return '{}' end} end
 if name=='TagFixture' then return Fixture end
 if name=='PZSurvivorToolkit/QuartermasterTagRules' then
  return {getBox=function() return Fixture.rule() end,getBoxRevision=function() return 5 end}
 end
 if name=='PZSurvivorToolkit/ItemTags' then return {} end
 if name=='PZSurvivorToolkit/TagFilterPresets' then return {list=function()
  presetReads=presetReads+1
  return presetStored and {{name='Toolkit food client1',rule=Fixture.rule()}} or {}
 end} end
 if name=='BetterContainers/_Options' then return providerOptions end
 return originalRequire(name)
end
PZAPI={ModOptions={getOptions=function(_,id)
 if id=='BetterContainers' then return providerPanel end
 return {getOption=function() return {setValue=function() end} end}
end}}
Events={}
for _,name in ipairs({'OnMainMenuEnter','OnPreUIDraw','OnGameStart','OnServerCommand','OnTick'}) do
 local event={handlers={}};event.Add=function(fn) event.handlers[#event.handlers+1]=fn end;Events[name]=event
end
local function fire(name,...)
 for _,fn in ipairs(Events[name].handlers) do fn(...) end
end
isClient=function() return true end
isIngameState=function() return true end
local core={setOptionPauseOnFocusloss=function() end,setOptionAutoDrink=function() end,TakeFullScreenshot=function() end}
getCore=function() return core end
local function container(ids)
 local items={};for _,id in ipairs(ids) do items[#items+1]={getID=function() return id end} end
 return {_testItems=items,getItems=function() return {size=function() return #items end,get=function(_,index) return items[index+1] end} end}
end
instanceof=function() return false end
local sourceContainer,destContainer=container(baseline and {2} or {3,4}),container(baseline and {1} or {1,2})
local bag={getID=function() return 99 end,getModData=function() return {PZSTTagFixtureOwner='client1'} end,
 getInventory=function() return sourceContainer end}
local inv={getItems=function() return {size=function() return 1 end,get=function() return bag end} end}
local player={getInventory=function() return inv end,setAutoDrink=function() end,setGodMod=function() end}
getPlayer=function() return player end
local box={hasModData=function() return true end,getModData=function() return {PZSTTagFixtureOwner='client1'} end,
 getContainerCount=function() return 1 end,getContainerByIndex=function() return destContainer end}
local square={getObjects=function() return {size=function() return 1 end,get=function() return box end} end}
getCell=function() return {getGridSquare=function() return square end} end
LootSorter={getBoxCats=function() return {BatteryCategory=true} end,openPicker=function()
 LootSorter._picker={toolkitTagRule=Fixture.rule(),selectedCats={BatteryCategory=true},closePicker=function() end}
end}
local deletion={options={{pzstKey='tagPresetDelete:Toolkit food client1',onSelect=function()
 presetStored=false;presetDeletes=presetDeletes+1
end}}}
local saved={options={{pzstKey='tagPresetDelete',subOption=2}},getSubMenu=function() return deletion end}
local menu={options={{pzstKey='tagPresets',subOption=1}},getSubMenu=function() return saved end,hideAndChildren=function() end}
ISContextMenu={get=function() return menu end}
local button={getAbsoluteX=function() return 0 end,getAbsoluteY=function() return 0 end,getHeight=function() return 20 end,
 onclick=function() ISContextMenu.get() end}
local pane={prerender=function() end,setVisible=function() end,toolkitCategoryButton=button}
local page={inventoryPane=pane,setVisible=function() end,setPinned=function() end,refreshBackpacks=function() end,
 setNewContainer=function(_,container) pane.inventory=container end}
getPlayerInventory=function() return page end
if restart then
 player.hasTimedActions=function() return false end
 player.getCurrentSquare=function() return square end
 square.canStand=function() return true end;square.canReachTo=function() return true end
 box.getSquare=function() return square end
 AdjacentFreeTileFinder={Find=function() return square end}
 LootSorter.isRegistrySynced=function() return true end
 LootSorter.arePresetsSynced=function() return true end
 LootSorter.gatherBoxes=function() return {{obj=box,container=destContainer}},true end
 LootSorter.WalkAction={new=function() end}
 local function move(from,to)
  for index,item in ipairs(from._testItems) do
   if item:getID()==2 then table.remove(from._testItems,index);to._testItems[#to._testItems+1]=item;return end
  end
  error('exact Apple missing')
 end
 ISInventoryTransferAction={new=function(_,auth,item,from,to)
  assert(auth==player and item:getID()==2 and from==destContainer and to==sourceContainer)
  return {from=from,to=to}
 end}
 ISTimedActionQueue={getTimedActionQueue=function() return {queue={}} end,
  add=function(action) move(action.from,action.to) end}
 LootSorter.sort=function(from,index)
  assert(from==sourceContainer and index==0)
  LootSorter._sortRunSeq=(LootSorter._sortRunSeq or 0)+1;move(sourceContainer,destContainer)
 end
end
sendClientCommand=function(module,command,args) commands[#commands+1]={module=module,command=command,args=args} end
dofile(root..'client/ZZTagBaseline.lua')
fire('OnGameStart')
assert(#events==(restart and 1 or 0),'resume setup count differs')
now=3000;fire('OnTick')
assert(providerOptions.applied and providerOptions.showAdvancedDisplayCategories==false and #commands==0,'provider was not configured before resumed phases')
now=3001;fire('OnTick')
assert(#commands==1 and commands[1].command=='Ready' and commands[1].args.reconnect,'resume did not request existing fixture')
fire('OnServerCommand','TagBaseline','Setup',{x=10,y=20,z=0,index=0,source=99,revision=5,manualCategory='BatteryCategory',battery=1,apple=2,beans=not baseline and 3 or nil,steak=not baseline and 4 or nil})
now=5000;fire('OnTick')
if not baseline then
assert(commands[2].command=='VerifyRule' and commands[2].args.phase==(restart and 'restart-before' or 'reconnect'),'resume did not audit rule authority')
assert(commands[3].command=='Verify' and commands[3].args.phase=='enabled','resume did not audit exact item receipts')
fire('OnServerCommand','TagBaseline','RuleVerified',{ok=true,phase=restart and 'restart-before' or 'reconnect',revision=5})
fire('OnServerCommand','TagBaseline','Verified',{ok=true,phase='enabled',ids={}})
else
 assert(#commands==2 and commands[2].command=='Verify' and commands[2].args.phase=='baseline','baseline reconnect missed exact authority receipt')
 fire('OnServerCommand','TagBaseline','Verified',{ok=true,phase='baseline',ids={}})
end
now=7000;fire('OnTick')
if restart then
 assert(files['tag-fixture-reconnect.txt']=='done' and #events==2 and events[2].id=='server-restart')
 assert(presetReads==2 and presetDeletes==0 and presetStored,'cold restart mutated saved local filter')
 now=9000;fire('OnTick')
 assert(Fixture.find(sourceContainer,2),'restart did not queue exact native Apple pickup')
 now=11000;fire('OnTick')
 assert(commands[#commands].command=='Verify' and commands[#commands].args.phase=='disabled')
 fire('OnServerCommand','TagBaseline','Verified',{ok=true,phase='disabled',ids={}})
 now=13000;fire('OnTick');assert(LootSorter._sortRunSeq==1,'restart skipped native Quartermaster planner')
 now=15000;fire('OnTick')
 assert(commands[#commands].command=='Verify' and commands[#commands].args.phase=='enabled','restart reused pre-sort receipt')
 fire('OnServerCommand','TagBaseline','Verified',{ok=true,phase='enabled',ids={}})
 now=17000;fire('OnTick')
 assert(commands[#commands].command=='VerifyRule' and commands[#commands].args.phase=='restart-after')
 fire('OnServerCommand','TagBaseline','RuleVerified',{ok=true,phase='restart-after',revision=5})
 now=19000;fire('OnTick');assert(#events==3 and events[3].id=='restart-sort')
 now=21000;fire('OnTick')
 assert(#events==4 and events[4].event=='complete' and events[4].performed==2)
 print('Native tag cold restart checks passed: fresh setup, persisted preset read-only, exact pickup, fresh authority receipts and native re-sort.')
 return
end
assert(files['tag-fixture-reconnect.txt']=='done' and #events==1 and events[1].id==cases[#cases],'reconnect completion not gated by authority')
if baseline then
 assert(presetReads==0 and presetDeletes==0,'baseline invoked candidate-only preset API')
else
 assert(presetReads==2 and presetDeletes==1 and not presetStored,'reconnect missed preset disk read or native menu deletion')
end
now=9000;fire('OnTick')
assert(#events==2 and events[2].event=='complete' and events[2].performed==#cases,'resume repeated old cases or missed completion')
print('Native tag reconnect fixture checks passed: resume-only Ready, no duplicate setup/cases, authority gates, mode='..(baseline and 'baseline4' or 'candidate16'))
