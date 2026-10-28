-- Passive timings around the actual selected pane renderer, with native items.
local selection=require 'QueueTestSelection'
local sessionContext=#selection.cases>1 and require('StorageProfileSession').context()or nil
assert((sessionContext and sessionContext.case or selection.cases[1])=='inventory-work')
local Events=sessionContext and sessionContext.events or Events
local Lookup=require 'ReceiptLookupNative'
local freshnessOptions=require 'BetterContainers/_Options'
local entered,starting,started,done=false,false,false,false
local stage,since,phaseIndex,freshnessIndex,began='setup',0,0,1,0
local owned,food,foodSet,phases,restores={},{},{},{},{}
local player,inventory,page,pane,group,active,lookup,lookupBag,emptyBag,nested,first,last
local originalMode,initialIds,iconOriginal,iconWrapper,rendererFailure,renderObserver,originalFreshnessOptions
local fillVisibility
local sizes,modes,views={100,10000},{'clean','vanilla'},{'collapsed-visible','collapsed-clipped','expanded-clipped'}
for _,size in ipairs(sizes)do for _,mode in ipairs(modes)do for _,view in ipairs(views)do
 phases[#phases+1]={size=size,mode=mode,view=view,freshness=true}
end end end
for _,view in ipairs({'collapsed-visible','collapsed-clipped'})do
 phases[#phases+1]={size=10000,mode='clean',view=view,freshness=false}
end
local function now()return getTimestampMs()end
local function pack(...)return {n=select('#',...),...}end
local function json(value)
 if type(value)=='table'then
  local n,keys,parts=#value,{},{}
  local array=n>0
  for k in pairs(value)do keys[#keys+1]=k;if type(k)~='number'or k<1 or k>n or k%1~=0 then array=false end end
  if array then for i=1,n do parts[i]=json(value[i])end;return '['..table.concat(parts,',')..']'end
  table.sort(keys)
  for _,k in ipairs(keys)do parts[#parts+1]=string.format('%q',k)..':'..json(value[k])end
  return '{'..table.concat(parts,',')..'}'
 elseif type(value)=='string'then return string.format('%q',value)
 elseif type(value)=='number'then assert(value==value and math.abs(value)<math.huge);return tostring(value)
 elseif type(value)=='boolean'then return value and 'true'or'false'end
 return 'null'
end
local function log(kind,value)print('[STORAGE_PROFILE] '..kind..(value and ' '..json(value)or''))end
local function own(t,key)for k,v in pairs(t)do if k==key then return v end end end
local function restoreFreshnessOptions()
 if not originalFreshnessOptions then return end
 freshnessOptions.showFoodFreshnessBar=originalFreshnessOptions.bar
 freshnessOptions.showFoodFreshnessPercentage=originalFreshnessOptions.percentage
 assert(freshnessOptions.showFoodFreshnessBar==originalFreshnessOptions.bar
  and freshnessOptions.showFoodFreshnessPercentage==originalFreshnessOptions.percentage,'freshness options not restored')
end
local function phaseOptions(phase)
 assert(freshnessOptions.showFoodFreshnessBar==phase.freshness
  and freshnessOptions.showFoodFreshnessPercentage==phase.freshness,'native freshness options differ')
end
local function restorePane()
 active=nil
 for i=#restores,1,-1 do local r=restores[i];assert(r.owner[r.key]==r.wrapper,'observer changed');r.owner[r.key]=r.raw end
 restores={};renderObserver=nil
end
local function restoreFillVisibility()
 if not fillVisibility then return end
 local saved=fillVisibility
 saved.pane:setVisible(saved.visible)
 assert(saved.pane:getIsVisible()==saved.visible,'fill pane visibility not restored')
 fillVisibility=nil
end
local function beginFill()
 assert(not fillVisibility and not active and #restores==0,'fill overlaps measured observers')
 local owner=getPlayerInventory(0).inventoryPane
 fillVisibility={pane=owner,visible=owner:getIsVisible(),from=#food,target=phases[phaseIndex].size,index=phaseIndex}
 owner:setVisible(false);assert(not owner:getIsVisible(),'fill pane remained visible')
 stage='fill'
 log('FILL_BEGIN',{index=phaseIndex,from=#food,target=fillVisibility.target,measurement=false,paneHidden=true})
end
local function summary(values)
 local sorted,total,zeros={},0,0
 for i,v in ipairs(values)do sorted[i]=v;total=total+v;if v==0 then zeros=zeros+1 end end
 table.sort(sorted);assert(#sorted>0,'missing native draw samples')
 return {calls=#sorted,totalMs=total,meanMs=total/#sorted,p50=sorted[math.ceil(#sorted*.5)],
  p95=sorted[math.ceil(#sorted*.95)],maxMs=sorted[#sorted],zeroMsCalls=zeros}
end
local function identity()
 local seen={};local items=inventory:getItems()
 for i=0,items:size()-1 do local item=items:get(i);assert(not seen[item:getID()]);seen[item:getID()]=item end
 return seen
end
local function observe()
 local original,raw=pane.renderdetails,own(pane,'renderdetails')
 local wrapper=function(self,dragged,...)
  local measurement=active
  local startedAt=measurement and now()
  local result=pack(pcall(original,self,dragged,...))
  if not result[1]then
   -- UI callbacks run outside tick's protected call. Retain the failure until
   -- the next tick can emit FAIL and clean up, then preserve the UI error itself.
   rendererFailure=rendererFailure or {error=result[2]}
   error(result[2],0)
  end
  if measurement then
   local elapsed=now()-startedAt
   if elapsed<0 then rendererFailure=rendererFailure or {error='clock moved backwards'};error('clock moved backwards',0)end
   local values=dragged and measurement.dragged or measurement.primary;values[#values+1]=elapsed
  end
  return unpack(result,2,result.n)
 end
 renderObserver={owner=pane,key='renderdetails',raw=raw,wrapper=wrapper,original=original}
 pane.renderdetails=wrapper;restores[#restores+1]=renderObserver
 local originalRefresh,rawRefresh=pane.refreshContainer,own(pane,'refreshContainer')
 assert(type(originalRefresh)=='function','native refresh method missing')
 local refreshWrapper=function(self,...)
  local measurement=active
  local startedAt=measurement and now()
  local result=pack(pcall(originalRefresh,self,...))
  if not result[1]then
   rendererFailure=rendererFailure or {error=result[2]};error(result[2],0)
  end
  if measurement then
   local elapsed=now()-startedAt
   if elapsed<0 then rendererFailure=rendererFailure or {error='clock moved backwards'};error('clock moved backwards',0)end
   measurement.refresh.calls=measurement.refresh.calls+1
   measurement.refresh.totalMs=measurement.refresh.totalMs+elapsed
  end
  return unpack(result,2,result.n)
 end
 pane.refreshContainer=refreshWrapper
 restores[#restores+1]={owner=pane,key='refreshContainer',raw=rawRefresh,wrapper=refreshWrapper}
end
local function paneClass(mode,renderer)
 local name=mode=='clean'and 'CleanUI_Clean_ISInventoryPane'or 'CleanUI_Vanilla_ISInventoryPane'
 local class=_G[name]
 assert(type(class)=='table'and getmetatable(pane)==class and ISInventoryPane==class,
  'selected native pane class differs '..name)
 assert(type(renderer)=='function'and renderer==class.renderdetails,'selected native renderer differs '..name)
 return name
end
local function actualCount(value)return #value.items-(value.cleanUIFirstActualIndex or 2)+1 end
local function findFoodGroup()
 local found
 for _,candidate in ipairs(pane.itemslist or{})do
  if candidate.items and foodSet[candidate.items[1]]then assert(not found,'food unexpectedly split');found=candidate end
 end
 assert(found and actualCount(found)==#food,'native food stack cardinality differs')
 return found
end
local function configure()
 restorePane()
 local phase=phases[phaseIndex]
 freshnessOptions.showFoodFreshnessBar=phase.freshness
 freshnessOptions.showFoodFreshnessPercentage=phase.freshness
 phaseOptions(phase)
 CleanUI_setCleanInventoryUIEnabled(phase.mode=='clean')
 page=getPlayerInventory(0);pane=page.inventoryPane
 paneClass(phase.mode,pane.renderdetails)
 page:setVisible(true);page.isCollapsed=false;page:clearMaxDrawHeight();page:setPinned()
 page:setX(30);page:setY(50);page:setWidth(1000);page:setHeight(460)
 pane:setVisible(true);pane:setMode('details');pane:refreshContainer()
 getPlayerLoot(0):setVisible(false)
 assert(pane.inventory==inventory,'native inventory selection changed')
 group=findFoodGroup();assert(#pane.itemslist>=40,'native spacer groups missing')
 for _,row in ipairs(pane.itemslist)do pane.collapsed[row.name]=true end
 pane.collapsed[group.name]=phase.view~='expanded-clipped'
 pane:refreshContainer();group=findFoodGroup()
 pane.smoothScrollY=nil;pane.smoothScrollTargetY=nil
 pane:setYScroll(phase.view=='collapsed-visible'and 0 or -100000)
 observe();stage='warm';since=now()
end
local function beginPhase()
 phaseOptions(phases[phaseIndex])
 group=findFoodGroup()
 active={primary={},dragged={},foodIcons=0,refresh={calls=0,totalMs=0},started=now()}
 stage='measure'
end
local function endPhase()
 local phase=phases[phaseIndex];local measurement=active
 phaseOptions(phase)
 assert(pane.inventory==inventory and CleanUI_isCleanInventoryUIEnabled()==(phase.mode=='clean'))
 local observer=assert(renderObserver,'native renderer observer missing')
 assert(pane.renderdetails==observer.wrapper,'native renderer observer changed')
 local className=paneClass(phase.mode,observer.original)
 findFoodGroup()
 local visible=phase.view=='collapsed-visible'
 assert((measurement.foodIcons>0)==visible,'actual food visibility differs '..phase.view..' icons='..measurement.foodIcons)
 log('WORK_FOOD',{index=phaseIndex,size=phase.size,mode=phase.mode,view=phase.view,
  native=true,paneClass=className,rendererMatchesClass=true,
  freshnessBar=freshnessOptions.showFoodFreshnessBar,freshnessPercentage=freshnessOptions.showFoodFreshnessPercentage,
  elapsedMs=now()-measurement.started,warmupMs=1500,clockResolutionMs=1,
  foodIcons=measurement.foodIcons,groups=#pane.itemslist,rawItems=inventory:getItems():size(),
  primary=summary(measurement.primary),dragged=#measurement.dragged>0 and summary(measurement.dragged)or {calls=0},refresh=measurement.refresh,
  scrollY=pane:getYScroll(),width=pane:getWidth(),height=pane:getHeight(),groupObjects=actualCount(group)})
 restorePane();phaseIndex=phaseIndex+1
 if not phases[phaseIndex]then stage='freshness';since=now()
 elseif #food<phases[phaseIndex].size then beginFill()else configure()end
end
local function cleanup()
 restoreFillVisibility()
 restorePane()
 assert(ISInventoryItem.renderItemIcon==iconWrapper,'icon observer changed');ISInventoryItem.renderItemIcon=iconOriginal
 for _,item in ipairs(owned)do assert(item:getContainer()==inventory);inventory:Remove(item)end
 local after=identity();local n=0
 for id,item in pairs(initialIds)do assert(after[id]==item,'original inventory item changed');after[id]=nil;n=n+1 end
 for _ in pairs(after)do error('unexpected inventory item after cleanup')end
 CleanUI_setCleanInventoryUIEnabled(originalMode)
 restoreFreshnessOptions()
 lookupBag,emptyBag,nested,first,last=nil,nil,nil,nil,nil;lookup=nil
 log('WORK_RESTORED',{ownedRemoved=#owned,foodRemoved=#food,originalItems=n,observers=true,
  mode=CleanUI_isCleanInventoryUIEnabled()==originalMode,freshnessOptions=true,phases=#phases,lookupObjectsPreserved=true})
 log('COMPLETE');done=true
 if sessionContext then sessionContext.finish(true)end
end
local function setup()
 assert(not isClient()and not isServer(),'SP profile required')
 player=getPlayer();player:setGodMod(true);player:setGhostMode(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
 inventory=player:getInventory();initialIds=identity();originalMode=CleanUI_isCleanInventoryUIEnabled()
 originalFreshnessOptions={bar=freshnessOptions.showFoodFreshnessBar,percentage=freshnessOptions.showFoodFreshnessPercentage}
 assert(type(originalFreshnessOptions.bar)=='boolean'and type(originalFreshnessOptions.percentage)=='boolean','native freshness options unavailable')
 for i=1,60 do local item=assert(inventory:AddItem('Base.Nails'));item:setName(string.format('ZZZ fixture spacer %03d',i));owned[#owned+1]=item end
 lookupBag=assert(instanceItem('Base.Bag_Schoolbag'));emptyBag=assert(instanceItem('Base.Bag_Schoolbag'))
 local root=lookupBag:getInventory();first=assert(root:AddItem('Base.Nails'));nested=assert(root:AddItem('Base.Bag_Schoolbag')):getInventory()
 iconOriginal=ISInventoryItem.renderItemIcon
 iconWrapper=function(owner,item,...)
  if active and owner==pane and foodSet[item]then active.foodIcons=active.foodIcons+1 end
  return iconOriginal(owner,item,...)
 end
 ISInventoryItem.renderItemIcon=iconWrapper
 log('WORK_SETUP',{native=true,clock='getTimestampMs',resolutionMs=1,spacers=60,
  foodType='Base.Apple',lookupType='Base.Nails',phases=#phases,physicalInput=false,fpsMeasurement=false})
 stage='lookup-fill'
end
local function tick()
 if rendererFailure then error(rendererFailure.error,0)end
 assert(now()-began<300000,'inventory-work deadline exceeded')
 if stage=='setup'then setup()
 elseif stage=='lookup-fill'then
  for _=1,120 do if nested:getItems():size()<4800 then last=assert(nested:AddItem('Base.Nails'))end end
  if nested:getItems():size()==4800 then
   lookup=Lookup.new{container=lookupBag:getInventory(),nestedContainer=nested,firstItem=first,lastItem=last,
    emptyContainer=emptyBag:getInventory(),expectedCount=4800,log=function(kind,row)log('WORK_'..kind,row)end}
   stage='lookup'
  end
 elseif stage=='lookup'then if lookup:tick()then phaseIndex=1;beginFill()end
 elseif stage=='fill'then
  assert(fillVisibility and getPlayerInventory(0).inventoryPane==fillVisibility.pane
   and not fillVisibility.pane:getIsVisible()and not active and #restores==0,'fill pane/measurement state changed')
  for _=1,100 do if #food<phases[phaseIndex].size then
   local item=assert(inventory:AddItem('Base.Apple'));item:setAge(0)
   food[#food+1]=item;foodSet[item]=true;owned[#owned+1]=item
  end end
  if #food<phases[phaseIndex].size and #food%1000==0 then
   log('FILL_PROGRESS',{index=phaseIndex,count=#food,target=phases[phaseIndex].size,measurement=false})
  end
  if #food==phases[phaseIndex].size then
   local saved=fillVisibility;restoreFillVisibility()
   log('FILL_COMPLETE',{index=phaseIndex,from=saved.from,target=#food,measurement=false,visibilityRestored=true})
   configure()
  end
 elseif stage=='warm'then
  if phases[phaseIndex].view~='collapsed-visible'then pane:setYScroll(-pane:getScrollHeight())end
  if now()-since>=1500 then beginPhase()end
 elseif stage=='measure'and now()-active.started>=3000 and #active.primary>=60 then endPhase()
 elseif stage=='freshness'then
  -- A changed tail item must split from its former native stack after refresh.
  local mode=modes[freshnessIndex];CleanUI_setCleanInventoryUIEnabled(mode=='clean')
  pane=getPlayerInventory(0).inventoryPane
  local className=paneClass(mode,pane.renderdetails)
  local item=food[#food];local before=item:getAge();item:setAge(item:getOffAgeMax()+1)
  pane:refreshContainer();local matches=0;local tailSize=0
  for _,row in ipairs(pane.itemslist)do if row.items then
   local seen=false;for i=row.cleanUIFirstActualIndex or 2,#row.items do if row.items[i]==item then seen=true;matches=matches+1 end end
   if seen then tailSize=actualCount(row)end
  end end
  assert(matches==1 and tailSize==1,'native freshness regrouping failed')
  log('WORK_FRESHNESS',{mode=mode,paneClass=className,rendererMatchesClass=true,
   tailId=item:getID(),objects=#food,tailGroup=tailSize,unique=true,ageBefore=before,ageAfter=item:getAge()})
  item:setAge(before);pane:refreshContainer();freshnessIndex=freshnessIndex+1
  if freshnessIndex>#modes then cleanup()end
 end
end
Events.OnMainMenuEnter.Add(function()entered=true end)
Events.OnGameStart.Add(function()started=true;since=now();began=since end)
Events.OnPreUIDraw.Add(function()
 if started and isIngameState()and isGamePaused()then setGameSpeed(1)end
 if not entered or starting or isIngameState()then return end
 starting=true;getCore():setOptionPauseOnFocusloss(false)
 getWorld():setGameMode('Sandbox');getWorld():setWorld('InventoryWorkProfileNative');getWorld():setMap('Muldraugh, KY')
 MainScreen.instance:setDefaultSandboxVars()
 for name,value in pairs({Zombies=6,EnableVehicles=false,StartMonth=7,StartDay=9,StartTime=2})do getSandboxOptions():getOptionByName(name):setValue(value)end
 getSandboxOptions():toLua();MainScreen.instance.createWorld=true
 MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=10835,posY=10144,posZ=0}}}}
 MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'})
 MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
end)
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,error=pcall(tick)
 if not ok then
  local restored,restoreError=pcall(function()
   restoreFillVisibility()
   restoreFreshnessOptions()
   restorePane()
   if iconWrapper and ISInventoryItem.renderItemIcon==iconWrapper then ISInventoryItem.renderItemIcon=iconOriginal end
   for _,item in ipairs(owned)do if item:getContainer()==inventory then inventory:Remove(item)end end
   if originalMode~=nil then CleanUI_setCleanInventoryUIEnabled(originalMode)end
  end)
  log('FAIL',{stage=stage,phase=phaseIndex,error=tostring(error),restored=restored,restoreError=tostring(restoreError)});done=true
  if sessionContext then sessionContext.quarantine(error)end
 end
end)
