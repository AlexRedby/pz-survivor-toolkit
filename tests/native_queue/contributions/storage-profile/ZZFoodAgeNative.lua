-- Natural-expiry SP gate. Observers delegate; only phase setup writes food ages.
local selection=require 'QueueTestSelection'
assert(selection.cases[1]=='inventory-food-age')
local entered,starting,started,done=false,false,false,false
local stage,index,began='setup',1,0
local inventory,page,pane,initial,originalMode,optimizeOption,originalOptimize
local foods,foodSet,owned,restores={},{},{},{}
local head,tail,published,passes,observerFailure,events,eventClock
local beforeAge,beforeWorld,phaseBegan,initialOptimized,reopenPass,hiddenAt
local totalRemoved=0
local phases={{size=199,mode='clean'},{size=200,mode='clean'},
 {size=199,mode='vanilla'},{size=200,mode='vanilla'}}
local function now()return getTimestampMs()end
local function pack(...)return {n=select('#',...),...}end
local function json(value)
 if type(value)=='table'then
  local keys,parts={},{};for key in pairs(value)do keys[#keys+1]=key end;table.sort(keys)
  for _,key in ipairs(keys)do parts[#parts+1]=string.format('%q',key)..':'..json(value[key])end
  return '{'..table.concat(parts,',')..'}'
 elseif type(value)=='string'then return string.format('%q',value)
 elseif type(value)=='number'then assert(value==value and math.abs(value)<math.huge);return tostring(value)
 elseif type(value)=='boolean'then return value and 'true'or'false'end
 return 'null'
end
local function log(kind,value)print('[STORAGE_PROFILE] '..kind..(value and ' '..json(value)or''))end
local function snapshot()
 local result={};local items=inventory:getItems()
 for i=0,items:size()-1 do local item=items:get(i);assert(not result[item:getID()]);result[item:getID()]=item end
 return result
end
local function conserved()
 local actual=snapshot()
 for id,item in pairs(initial)do assert(actual[id]==item,'original item identity changed');actual[id]=nil end
 for _,item in ipairs(owned)do assert(actual[item:getID()]==item and item:getContainer()==inventory,'food identity/endpoint changed');actual[item:getID()]=nil end
 for _ in pairs(actual)do error('unexpected native inventory item')end
end
local function restoreObserver()
 for i=#restores,1,-1 do local r=restores[i];assert(r.owner[r.key]==r.wrapper,'native observer replaced');r.owner[r.key]=r.raw end
 restores={};published=nil;passes=0
end
local function observe()
 local original,raw=pane.renderdetails,nil
 for key,value in pairs(pane)do if key=='renderdetails'then raw=value end end
 local wrapper=function(self,dragged,...)
  local result=pack(pcall(original,self,dragged,...))
  if not result[1]then observerFailure=observerFailure or result[2];error(result[2],0)end
  if self==pane and dragged==false then published=pane.items;passes=passes+1 end
  return unpack(result,2,result.n)
 end
 pane.renderdetails=wrapper;restores[#restores+1]={owner=pane,key='renderdetails',raw=raw,wrapper=wrapper}
end
local function paneClass()
 local name=phases[index].mode=='clean'and 'CleanUI_Clean_ISInventoryPane'or 'CleanUI_Vanilla_ISInventoryPane'
 local class=_G[name]
 assert(getmetatable(pane)==class and ISInventoryPane==class,'selected native pane class differs')
 return name
end
local function rows()
 if passes==0 then return end
 assert(published==pane.items,'native rows changed after publication')
 local seen,headRow,tailRow,headGroup,tailGroup={},nil,nil,nil,nil
 for row,value in ipairs(published)do if type(value)=='table'and value.items then
  local start=value.cleanUIFirstActualIndex or 2
  local size=#value.items-start+1
  for i=start,#value.items do local item=value.items[i]
   if foodSet[item]then
    assert(not seen[item],'food duplicated in published rows');seen[item]=true
    if item==head then headRow=row;headGroup=size end
    if item==tail then tailRow=row;tailGroup=size end
   end
  end
 end end
 local count=0;for _ in pairs(seen)do count=count+1 end
 assert(count==#foods and headRow and tailRow,'native published food identity/cardinality differs')
 return {headRow=headRow,tailRow=tailRow,headGroup=headGroup,tailGroup=tailGroup}
end
local function visible(row)
 local top=pane.headerHgt+(row-1)*pane.itemHgt+pane:getYScroll()
 return page:getIsVisible()and pane:getIsVisible()and not page.isCollapsed
  and top+pane.itemHgt>pane.headerHgt and top<pane:getHeight()-1
end
local function containerUpdate(item)
 if item==tail and stage~='setup'and stage~='seed'then events=events+1;eventClock=getGameTime():getWorldAgeHours()end
end
local function removeFood()
 restoreObserver()
 for _,item in ipairs(owned)do assert(item:getContainer()==inventory);inventory:Remove(item);totalRemoved=totalRemoved+1 end
 owned={};foods={};foodSet={};head=nil;tail=nil;conserved()
end
local function configure()
 stage='seed';observerFailure=nil;passes=0;events=0;eventClock=nil
 local phase=phases[index]
 CleanUI_setCleanInventoryUIEnabled(phase.mode=='clean')
 page=getPlayerInventory(0);pane=page.inventoryPane;paneClass()
 page:setVisible(true);page.isCollapsed=false;page:clearMaxDrawHeight();page:setPinned()
 page:setX(30);page:setY(50);page:setWidth(1000);page:setHeight(460)
 pane:setVisible(true);pane:setMode('details');getPlayerLoot(0):setVisible(false)
 assert(pane.inventory==inventory,'native selected inventory changed')
 local world=getGameTime():getWorldAgeHours()
 for i=1,phase.size do
  local item=assert(inventory:AddItem('Base.Apple'))
  assert(item:getOffAge()==5 and item:getOffAgeMax()==8,'Apple freshness thresholds changed')
  item:setAge(i==phase.size and 5-.004 or .1);item:setLastAged(world)
  foods[i]=item;owned[i]=item;foodSet[item]=true
 end
 tail=foods[#foods]
 pane:refreshContainer()
 local group
 for _,candidate in ipairs(pane.itemslist)do if candidate.items then
  for _,item in ipairs(candidate.items)do if item==tail then assert(not group or group==candidate);group=candidate end end
 end end
 assert(group,'initial native food group missing')
 pane.collapsed[group.name]=true;pane:refreshContainer()
 pane.smoothScrollY=nil;pane.smoothScrollTargetY=nil;pane:setYScroll(0)
 beforeAge=tail:getAge();beforeWorld=world;phaseBegan=now()
 assert(tail:isFresh(),'tail expired during phase setup')
 observe();stage='position'
end
local function cleanup()
 removeFood();Events.OnContainerUpdate.Remove(containerUpdate)
 optimizeOption:setValue(originalOptimize)
 CleanUI_setCleanInventoryUIEnabled(originalMode)
 conserved()
 log('AGE_RESTORED',{ownedRemoved=totalRemoved,originalItems=inventory:getItems():size(),
  observers=true,items=true,mode=CleanUI_isCleanInventoryUIEnabled()==originalMode,
  optimize=optimizeOption:getValue()==originalOptimize,phases=#phases})
 log('COMPLETE');done=true
end
local function tick()
 if observerFailure then error(observerFailure,0)end
 assert(now()-began<180000,'natural food-age fixture deadline exceeded')
 if stage=='setup'then
  assert(not isClient()and not isServer(),'SP natural-age gate required; Host needs authoritative evidence')
  local player=getPlayer();player:setGodMod(true);player:setGhostMode(true)
  if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
  inventory=player:getInventory();initial=snapshot();originalMode=CleanUI_isCleanInventoryUIEnabled()
  optimizeOption=assert(PZAPI.ModOptions:getOptions('CleanUI'):getOption('optimizeLargeStacks'),'large-stack option missing')
  originalOptimize=optimizeOption:getValue();optimizeOption:setValue(true)
  Events.OnContainerUpdate.Add(containerUpdate)
  log('AGE_SETUP',{native=true,foodType='Base.Apple',phases=#phases,kind='sp',naturalAgeing=true,
   ageControl='phase-setup-only',physicalInput=false,network=false,timing=false})
  configure()
 elseif stage=='position'then
  if passes==0 then return end
  -- Select the actual group head only after the real primary renderer publishes it.
  local found
  for row,value in ipairs(published)do if type(value)=='table'and value.items then
   local start=value.cleanUIFirstActualIndex or 2
   for i=start,#value.items do if value.items[i]==tail then
    assert(not found);found=row;head=value.items[start]
    assert(head~=tail and head:getAge()<1 and i-start+1>50,'older tail is not beyond the younger header/first50')
    initialOptimized=value.cleanUILargeStackOptimized==true
    assert(initialOptimized==(phases[index].mode=='clean'and phases[index].size==200),'large-stack threshold path differs')
   end end
  end end
  assert(found and tail:isFresh()and events==0,'initial fresh native row absent')
  pane:setYScroll(-math.max(0,found-2)*pane.itemHgt);stage='observe'
 elseif stage=='observe'then
  local current=rows();if not current then return end
  conserved()
  assert(head:isFresh(),'younger header unexpectedly stale')
  if tail:isFresh()then
   assert(current.headRow==current.tailRow and visible(current.tailRow),'fresh group must stay visible')
   assert(now()-phaseBegan<45000,'older tail did not expire naturally through the native UI')
   return
  end
  assert(events==1 and eventClock and eventClock>beforeWorld,'missing/duplicate natural freshness event')
  if current.headRow==current.tailRow then
   assert(now()-phaseBegan<45000,'native freshness event did not regroup');return
  end
  assert(current.tailGroup==1 and current.headGroup==#foods-1,'natural tail did not split from younger native group')
  page:setVisible(false);hiddenAt=now();stage='hidden'
 elseif stage=='hidden'and now()-hiddenAt>=500 then
  assert(not page:getIsVisible(),'native page did not hide');conserved()
  page:setVisible(true);reopenPass=passes;stage='reopen'
 elseif stage=='reopen'and passes>reopenPass then
  local current=rows();conserved()
  assert(current.headRow~=current.tailRow and current.tailGroup==1 and current.headGroup==#foods-1,'reopen changed natural food grouping')
  assert(events==1 and not tail:isFresh()and head:isFresh(),'reopen freshness/event guard differs')
  local phase=phases[index]
  log('AGE_PHASE',{index=index,size=phase.size,mode=phase.mode,paneClass=paneClass(),native=true,
   optimized=initialOptimized,headId=head:getID(),tailId=tail:getID(),ageBefore=beforeAge,ageAfter=tail:getAge(),
   worldBefore=beforeWorld,worldAfter=getGameTime():getWorldAgeHours(),eventWorld=eventClock,
   events=events,headFresh=true,tailFresh=false,headGroup=current.headGroup,tailGroup=1,
   separatePublishedRows=true,identities=true,visibleObservation=true,hiddenReopen=true,primaryPasses=passes,
   naturalAgeing=true,observationAgeWrites=0,elapsedMs=now()-phaseBegan})
  if index==#phases then cleanup()else removeFood();index=index+1;configure()end
 end
end
Events.OnMainMenuEnter.Add(function()entered=true end)
Events.OnGameStart.Add(function()started=true;began=now()end)
Events.OnPreUIDraw.Add(function()
 if started and isIngameState()and isGamePaused()then setGameSpeed(1)end
 if not entered or starting or isIngameState()then return end
 starting=true;getCore():setOptionPauseOnFocusloss(false)
 getWorld():setGameMode('Sandbox');getWorld():setWorld('InventoryFoodAgeNative');getWorld():setMap('Muldraugh, KY')
 MainScreen.instance:setDefaultSandboxVars()
 for name,value in pairs({Zombies=6,EnableVehicles=false,StartMonth=7,StartDay=9,StartTime=2})do getSandboxOptions():getOptionByName(name):setValue(value)end
 getSandboxOptions():toLua();MainScreen.instance.createWorld=true
 MapSpawnSelect.instance.selectedRegion={points={unemployed={{posX=10835,posY=10144,posZ=0}}}}
 MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'});MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
end)
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,err=pcall(tick)
 if not ok then
  local restored,restoreError=pcall(function()
   restoreObserver();Events.OnContainerUpdate.Remove(containerUpdate)
   for _,item in ipairs(owned)do if item:getContainer()==inventory then inventory:Remove(item)end end
   if optimizeOption then optimizeOption:setValue(originalOptimize)end
   if originalMode~=nil then CleanUI_setCleanInventoryUIEnabled(originalMode)end
  end)
  log('FAIL',{stage=stage,index=index,error=tostring(err),restored=restored,restoreError=tostring(restoreError)});done=true
 end
end)
