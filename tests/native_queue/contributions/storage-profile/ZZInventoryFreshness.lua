-- Functional native UI gate. Observers forward real calls; no timing claim.
local selection=require 'QueueTestSelection'
assert(selection.cases[1]=='inventory-freshness')
local Presenter=require 'PZSurvivorToolkit/InventoryFreshness'
local Options=require 'BetterContainers/_Options'
local entered,starting,started,done=false,false,false,false
local stage,index,began='setup',1,0
local pane,page,inventory,initial,originalMode,originalOptions,observerFailure,activeMode
local owned,foods,restores,phases={},{},{},{}
local probe,frame,drawCalls,tailRestore=nil,nil,0,nil
local primaryPasses,publishedRows=0,nil
local views={'grouped','hover','expanded','partial','offscreen','bar-only','percentage-only','disabled','hidden'}

local function pack(...)return {n=select('#',...),...}end
local function json(value)
 if type(value)=='table'then
  local n,keys,parts=#value,{},{};local array=n>0
  for k in pairs(value)do keys[#keys+1]=k;if type(k)~='number'or k<1 or k>n or k%1~=0 then array=false end end
  if array then for i=1,n do parts[i]=json(value[i])end;return '['..table.concat(parts,',')..']'end
  table.sort(keys);for _,k in ipairs(keys)do parts[#parts+1]=string.format('%q',k)..':'..json(value[k])end
  return '{'..table.concat(parts,',')..'}'
 elseif type(value)=='string'then return string.format('%q',value)
 elseif type(value)=='number'then return tostring(value)
 elseif type(value)=='boolean'then return value and 'true'or'false'end
 return 'null'
end
local function log(kind,value)print('[STORAGE_PROFILE] '..kind..(value and ' '..json(value)or''))end
local function snapshot()
 local seen={};local items=inventory:getItems()
 for i=0,items:size()-1 do local item=items:get(i);seen[item:getID()]=item end
 return seen
end
local function sameItems(before)
 local after=snapshot();for id,item in pairs(before)do assert(after[id]==item,'native item changed');after[id]=nil end
 for _ in pairs(after)do error('unexpected native item')end
end
local function intercept(owner,key,wrapper)
 local raw;for k,v in pairs(owner)do if k==key then raw=v end end
 restores[#restores+1]={owner=owner,key=key,raw=raw,wrapper=wrapper};owner[key]=wrapper
end
local function unobserve()
 probe=nil
 for i=#restores,1,-1 do local r=restores[i];assert(r.owner[r.key]==r.wrapper,'observer replaced');r.owner[r.key]=r.raw end
 restores={}
end
local function fresh(item)
 if not item or not instanceof(item,'Food')then return end
 local max=item:getOffAgeMax();if not max or max<=0 or max>=1000000000 then return end
 return math.max(0,math.min(1,1-(item:getAge()or 0)/max)),math.max(0,math.min(1,1-(item:getOffAge()or 0)/max))
end
local function output(expected,item,row,child)
 local f,s=fresh(item);if not f then return end
 local top=pane.headerHgt+(row-1)*pane.itemHgt
 local font=pane.font or UIFont.Medium
 local percent=Options.showFoodFreshnessPercentage and(child or pane.mouseOverOption==row)
 local slot=percent and getTextManager():MeasureStringX(font,'100%')or 0
 local x,right=pane.column2+8,pane.column3-8
 if child and slot>0 then right=pane.column3-slot-4 end
 local width=right-x
 local function rect(...)expected.rects[#expected.rects+1]={...}end
 if Options.showFoodFreshnessBar and width>=48 then
  local y=top+pane.itemHgt-4;local fill=math.floor(width*f+.5)
  local stale=x+math.floor(width*s+.5)-1
  rect(x,y,width,3,.62,.08,.08,.08)
  if fill>0 then if f>s then rect(x,y,fill,3,.88,.30,.62,.34)else rect(x,y,fill,3,.88,.72,.48,.18)end end
  rect(stale-1,y-2,4,7,.80,.08,.08,.08);rect(stale,y-1,2,5,.92,.88,.66,.38)
 end
 if percent then
  local text=tostring(math.floor(f*100+.5))..'%';local textWidth=getTextManager():MeasureStringX(font,text)
  local slotX=pane.column3-slot;local textX=slotX+math.floor((slot-textWidth)/2)
  local h=pane.fontHgt or getTextManager():getFontHeight(font)
  rect(slotX,top,slot,pane.itemHgt,1,0,0,0)
  expected.texts[#expected.texts+1]={text,textX,top+math.max(0,(pane.itemHgt-h)/2),.7,.7,.7,1,font}
 end
 expected.foodRows=expected.foodRows+1
end
local function expectedRows()
 local result={rects={},texts={},allowed={},foodRows=0,separators=0,rows=#pane.items,visibleRows=0,visibleSeparators=0,hiddenVisits=0,visits=0}
 local enabled=phases[index].mode==activeMode and(Options.showFoodFreshnessBar or Options.showFoodFreshnessPercentage)
 local visible=page:getIsVisible()and pane:getIsVisible()and not page.isCollapsed
 for row,value in ipairs(pane.items)do
  local separator=type(value)=='table'and(value.type=='separator'or value._bcEquippedAttachedSeparator)
  if separator then result.separators=result.separators+1 end
  local top=pane.headerHgt+(row-1)*pane.itemHgt+pane:getYScroll()
  if visible and separator and top+pane.itemHgt>pane.headerHgt and top<pane:getHeight()-1 then result.visibleSeparators=result.visibleSeparators+1 end
  if enabled and visible and not separator and top+pane.itemHgt>pane.headerHgt and top<pane:getHeight()-1 then
   result.visibleRows=result.visibleRows+1
   if type(value)=='table'and value.items then
    local worst,least
    for _,item in ipairs(value.items)do
     result.allowed[item]=true;local f=fresh(item)
     if f and(not least or f<least)then worst,least=item,f end
    end
    output(result,worst,row,false)
   else result.allowed[value]=true;output(result,value,row,true)end
  end
 end
 return result
end
local function equals(a,b)
 assert(#a==#b,'native output count differs '..#a..'/'..#b)
 for i,row in ipairs(a)do assert(#row==#b[i],'native output shape differs')
  for j,v in ipairs(row)do local expected=b[i][j]
   if type(v)=='number'and type(expected)=='number'then assert(math.abs(v-expected)<.000001,'native output coordinate/value differs')
   else assert(v==expected,'native output text/font differs')end
  end
 end
end
local function groupRow()
 local found
 for row,value in ipairs(pane.items or{})do if type(value)=='table'and value.items then
  for _,item in ipairs(value.items)do if item==foods[1]then assert(not found or found==row,'fixture stack split/duplicated');found=row end end
 end end
 return assert(found,'actual native food row absent')
end
local function publishedRow()
 -- CleanUI replaces both windows on a class toggle. Its new pane has no
 -- published map until its first actual primary prerender has completed.
 if primaryPasses==0 then return end
 assert(publishedRows==pane.items,'native row map replaced after primary render')
 return groupRow()
end
local function observe()
 local render=pane.renderdetails
 intercept(pane,'renderdetails',function(self,dragged,...)
  local result=pack(pcall(render,self,dragged,...))
  if not result[1]then observerFailure=result[2];error(result[2],0)end
  if self==pane and dragged==false then primaryPasses=primaryPasses+1;publishedRows=pane.items end
  return unpack(result,2,result.n)
 end)
 local originalInstance=instanceof
 intercept(_G,'instanceof',function(item,class,...)
  if probe and class=='Food'then probe.visits=probe.visits+1;if not probe.allowed[item]then probe.hiddenVisits=probe.hiddenVisits+1 end end
  return originalInstance(item,class,...)
 end)
 local rect,text=pane.drawRect,pane.drawText
 intercept(pane,'drawRect',function(self,...)if probe and self==pane then probe.actualRects[#probe.actualRects+1]={...}end;return rect(self,...)end)
 intercept(pane,'drawText',function(self,...)if probe and self==pane then probe.actualTexts[#probe.actualTexts+1]={...}end;return text(self,...)end)
 local draw=Presenter.draw
 intercept(Presenter,'draw',function(owner,...)
  if owner~=pane or stage~='observe'then return draw(owner,...)end
  drawCalls=drawCalls+1
  local previousHover=pane.mouseOverOption
  local phase=phases[index];local row=groupRow()
  local children=0
  for _,value in ipairs(pane.items)do for _,item in ipairs(foods)do if value==item then children=children+1 end end end
  local expanded=phase.view=='expanded'or phase.view=='partial'
  assert(children==(expanded and #foods or 0),'native food expansion differs from current source rows')
  pane.mouseOverOption=(phase.view=='hover'or phase.view=='percentage-only')and row or 0
  -- Fixture-only age change happens after native grouping, then is restored.
  -- This establishes full-stack worst-tail math, not natural ageing/regroup time.
  local tail=foods[#foods];local foundTail=false
  for _,item in ipairs(pane.items[row].items)do if item==tail then foundTail=true end end
  assert(foundTail,'worst tail not in current native stack')
  local beforeAge=tail:getAge();tailRestore={item=tail,age=beforeAge}
  tail:setAge(tail:getOffAgeMax()*.48)
  local expected=expectedRows();expected.fixtureChildren=children;expected.actualRects={};expected.actualTexts={}
  local rowMap=pane.items;local sourceRows={}
  for sourceIndex,value in ipairs(rowMap)do sourceRows[sourceIndex]=value end
  local before=snapshot();local bar,percentage=Options.showFoodFreshnessBar,Options.showFoodFreshnessPercentage
  probe=expected;local result=pack(pcall(draw,owner,...));probe=nil
  tail:setAge(beforeAge);tailRestore=nil;pane.mouseOverOption=previousHover
  if not result[1]then observerFailure=result[2];error(result[2],0)end
  local ok,err=pcall(function()
   equals(expected.actualRects,expected.rects);equals(expected.actualTexts,expected.texts)
   assert(expected.hiddenVisits==0,'presenter visited hidden/separator items')
   assert(Options.showFoodFreshnessBar==bar and Options.showFoodFreshnessPercentage==percentage,'presenter changed live options')
   assert(pane.items==rowMap and #pane.items==#sourceRows,'presenter replaced native row map')
   for sourceIndex,value in ipairs(sourceRows)do assert(pane.items[sourceIndex]==value,'presenter changed native row order')end
   sameItems(before);assert(tail:getAge()==beforeAge,'fixture age not restored')
  end)
  if not ok then observerFailure=err;error(err,0)end
  frame=expected;return unpack(result,2,result.n)
 end)
end
local function configure()
 unobserve();local phase=phases[index]
 CleanUI_setCleanInventoryUIEnabled(phase.mode=='clean');page=getPlayerInventory(0);pane=page.inventoryPane
 local class=_G[phase.mode=='clean'and 'CleanUI_Clean_ISInventoryPane'or 'CleanUI_Vanilla_ISInventoryPane']
 assert(getmetatable(pane)==class and ISInventoryPane==class,'native pane class differs')
 page:setVisible(true);page.isCollapsed=false;page:clearMaxDrawHeight();page:setPinned()
 page:setX(30);page:setY(50);page:setWidth(1000);page:setHeight(460)
 pane:setVisible(true);pane:setMode('details');getPlayerLoot(0):setVisible(false)
 assert(pane.inventory==inventory,'native player inventory selection changed')
 pane:refreshContainer()
 for _,group in ipairs(pane.itemslist)do pane.collapsed[group.name]=true end
 for _,group in ipairs(pane.itemslist)do for _,item in ipairs(group.items or{})do
  if item==foods[1]then pane.collapsed[group.name]=phase.view~='expanded'and phase.view~='partial' end
 end end
 pane:refreshContainer();pane.smoothScrollY=nil;pane.smoothScrollTargetY=nil;pane:setYScroll(0)
 Options.showFoodFreshnessBar=phase.view~='percentage-only'and phase.view~='disabled'
 Options.showFoodFreshnessPercentage=phase.view~='bar-only'and phase.view~='disabled'
 frame=nil;drawCalls=0;primaryPasses=0;publishedRows=nil;observe();stage='position'
end
local function cleanup()
 if tailRestore then tailRestore.item:setAge(tailRestore.age);tailRestore=nil end
 unobserve()
 for _,item in ipairs(owned)do assert(item:getContainer()==inventory);inventory:Remove(item)end
 sameItems(initial)
 Options.showFoodFreshnessBar=originalOptions.bar;Options.showFoodFreshnessPercentage=originalOptions.percentage
 CleanUI_setCleanInventoryUIEnabled(originalMode)
 log('FRESH_RESTORED',{ownedRemoved=#owned,foodRemoved=#foods,originalItems=inventory:getItems():size(),observers=true,items=true,options=true,mode=true,fixtureAges=true,phases=#phases})
 log('COMPLETE');done=true
end
local function tick()
 if observerFailure then error(observerFailure,0)end
 assert(getTimestampMs()-began<120000,'freshness fixture deadline exceeded')
 if stage=='setup'then
  assert(not isClient()and not isServer(),'SP fixture required')
  local player=getPlayer();player:setGodMod(true);player:setGhostMode(true)
  if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
  inventory=player:getInventory();initial=snapshot();originalMode=CleanUI_isCleanInventoryUIEnabled()
  activeMode=originalMode and 'clean'or 'vanilla'
  for _,mode in ipairs({activeMode,originalMode and 'vanilla'or 'clean'})do for _,view in ipairs(views)do phases[#phases+1]={mode=mode,view=view}end end
  phases[#phases+1]={mode=activeMode,view='hover'}
  originalOptions={bar=Options.showFoodFreshnessBar,percentage=Options.showFoodFreshnessPercentage}
  assert(type(originalOptions.bar)=='boolean'and type(originalOptions.percentage)=='boolean','live BC options missing')
  for i=1,6 do local item=assert(inventory:AddItem('Base.Apple'));foods[i]=item;owned[#owned+1]=item;item:setAge(0)end
  for i=1,45 do local item=assert(inventory:AddItem('Base.Nails'));item:setName(string.format('ZZZ freshness spacer %03d',i));owned[#owned+1]=item end
  log('FRESH_SETUP',{native=true,foodType='Base.Apple',food=6,spacers=45,phases=#phases,activeMode=activeMode,physicalInput=false,pixelCoverage=false,timing=false,naturalAgeing=false,ageControl='fixture-only-restored'})
  configure()
 elseif stage=='position'then
  local row=publishedRow();if not row then return end
  local phase=phases[index]
  local scroll=-math.max(0,row-2)*pane.itemHgt
  if phase.view=='partial'then scroll=-(row-1)*pane.itemHgt-pane.itemHgt/2
  elseif phase.view=='offscreen'then scroll=-pane:getScrollHeight()end
  pane:setYScroll(scroll);stage='observe'
  if phase.view=='hidden'then page:setVisible(false);Presenter.draw(pane)end
 elseif stage=='observe'and frame then
  local phase=phases[index];local row=groupRow();local top=pane.headerHgt+(row-1)*pane.itemHgt+pane:getYScroll()
  assert(phase.view~='partial'or(top<pane.headerHgt and top+pane.itemHgt>pane.headerHgt),'partial native row absent')
  assert(phase.view~='offscreen'or top+pane.itemHgt<=pane.headerHgt,'native food did not scroll off')
  if phase.mode~=activeMode or phase.view=='disabled'or phase.view=='hidden'then assert(frame.visits==0 and #frame.actualRects==0 and #frame.actualTexts==0,'disabled/hidden presenter did item work')end
  local layout=Presenter.layout(getmetatable(pane),pane,foods[1])
  local reserved=phase.mode==activeMode and Options.showFoodFreshnessPercentage
  if reserved then
   local width=getTextManager():MeasureStringX(pane.font or UIFont.Medium,'100%')
   assert(layout and layout.reservedLeft==pane.column3-width and layout.reservedRight==pane.column3,'native percentage reservation differs')
  else assert(layout==nil,'inactive/disabled percentage reserved a column')end
  local beforeCalls=drawCalls;local before=snapshot()
  pane:renderdetails(true)
  assert(drawCalls==beforeCalls,'dragged renderer invoked freshness presenter');sameItems(before)
  log('FRESH_PHASE',{index=index,mode=phase.mode,view=phase.view,native=true,paneClass=phase.mode=='clean'and 'CleanUI_Clean_ISInventoryPane'or 'CleanUI_Vanilla_ISInventoryPane',
   primaryPublished=primaryPasses>0,fixtureChildren=frame.fixtureChildren,pageVisible=page:getIsVisible(),paneVisible=pane:getIsVisible(),rows=frame.rows,separators=frame.separators,
   visibleRows=frame.visibleRows,visibleSeparators=frame.visibleSeparators,foodRows=frame.foodRows,visits=frame.visits,hiddenVisits=frame.hiddenVisits,
   rects=#frame.actualRects,texts=#frame.actualTexts,exactOutput=true,currentRows=true,items=true,options=true,tailWorst=true,fixtureAgeRestored=true,
   bar=Options.showFoodFreshnessBar,percentage=Options.showFoodFreshnessPercentage,draggedNative=true,draggedPresenterCalls=drawCalls-beforeCalls,
   layout=true,layoutReserved=reserved,active=phase.mode==activeMode,primary=phase.view~='hidden',directHidden=phase.view=='hidden'})
  index=index+1;if phases[index]then configure()else cleanup()end
 end
end
Events.OnMainMenuEnter.Add(function()entered=true end)
Events.OnGameStart.Add(function()started=true;began=getTimestampMs()end)
Events.OnPreUIDraw.Add(function()
 if started and isIngameState()and isGamePaused()then setGameSpeed(1)end
 if not entered or starting or isIngameState()then return end
 starting=true;getCore():setOptionPauseOnFocusloss(false)
 getWorld():setGameMode('Sandbox');getWorld():setWorld('InventoryFreshnessNative');getWorld():setMap('Muldraugh, KY')
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
   if tailRestore then tailRestore.item:setAge(tailRestore.age);tailRestore=nil end
   unobserve()
   if originalOptions then Options.showFoodFreshnessBar=originalOptions.bar;Options.showFoodFreshnessPercentage=originalOptions.percentage end
   for _,item in ipairs(owned)do if item:getContainer()==inventory then inventory:Remove(item)end end
   if originalMode~=nil then CleanUI_setCleanInventoryUIEnabled(originalMode)end
  end)
  log('FAIL',{stage=stage,index=index,error=tostring(err),restored=restored,restoreError=tostring(restoreError)});done=true
 end
end)
