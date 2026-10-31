-- Native UI observations delegate unchanged; authority alone seeds phase setup.
local config=require 'QueueTestSelection'
local F=require 'QueueFoodAgeFixture'
local started,done,stage,index=false,false,'setup',1
local session,current,authority,page,pane,ui,ids,spawn,position
local replies,restores={},{}
local published,passes,observerFailure,events,eventClock,head,tail,foods,foodSet,fillerSet
local began,phaseBegan,stageAt,lastDiagnostic,lastRequest,initialOptimized,tailBeyond50
local exposureStart,exposureFinish,foodVisiblePasses,concealing,concealedAt,proofPass
local cycle,cycleMode,cycles,expandedProof,phaseReceipt,releaseIds
local returnPosition={}
local uiLifecycle={}
local function now()return getTimestampMs()end
local function pack(...)return {n=select('#',...),...}end
local function shallow(value)local copy={};for key,item in pairs(value or {})do copy[key]=item end;return copy end
local function nativeRowIdentities(q)
 local result={};local limit=q.MAX_ITEMS_IN_STACK_TO_RENDER or ISInventoryPane.MAX_ITEMS_IN_STACK_TO_RENDER or 50
 for _,group in ipairs(q.itemslist or {})do if not(q.equippedCollapsed and group.equipped)then
  result[#result+1]={item=group.cleanUIDisplayItem or group.firstItem or(group.items and group.items[1]),name=group.name,group=true}
  if group.items and not q.collapsed[group.name]then
   local first=group.cleanUIFirstActualIndex or(group.cleanUILargeStackOptimized and 1)or 2
   for i=first,math.min(#group.items,first+limit-1)do result[#result+1]={item=group.items[i],group=false}end
  end
 end end;return result
end
local function saveSelection(q)
 local saved=q:saveSelection({});local groups=shallow(saved._cleanUISelectedGroups);local result={_cleanUISelectedGroups=groups}
 local aliases={};for _,row in ipairs(nativeRowIdentities(q))do if row.group and row.item then aliases[row.item]=row.name end end
 for item,value in pairs(saved)do if item~='_cleanUISelectedGroups'then
  assert(value=='item'or value=='group','unknown native selection marker')
  if value=='group'then groups[assert(aliases[item],'selected native header has no identity')]=true else result[item]=value end
 end end
 for i,row in ipairs(nativeRowIdentities(q))do if row.group and q.selected[i]then groups[assert(row.name)]=true end end
 for item,name in pairs(aliases)do if groups[name]then result[item]=nil end end
 return result
end
local function restoreSelection(q,saved)
 local input=shallow(saved);input._cleanUISelectedGroups=shallow(saved._cleanUISelectedGroups)
 for _,row in ipairs(nativeRowIdentities(q))do
  if row.group and row.item and input._cleanUISelectedGroups[row.name]then input[row.item]='group'end
 end
 q.selected={};q:restoreSelection(input);local actual=saveSelection(q)
 for item,value in pairs(saved)do if item~='_cleanUISelectedGroups'then assert(actual[item]==value,'native item selection lost')end end
 for item in pairs(actual)do if item~='_cleanUISelectedGroups'then assert(saved[item],'foreign native item selection')end end
 for name in pairs(saved._cleanUISelectedGroups)do assert(actual._cleanUISelectedGroups[name],'native group selection lost')end
 for name in pairs(actual._cleanUISelectedGroups)do assert(saved._cleanUISelectedGroups[name],'foreign native group selection')end
end
local function anchor(q,index)return {index=index,row=index and nativeRowIdentities(q)[index]or nil}end
local function restoreAnchor(q,saved)
 if not saved.row then return saved.index end
 for i,row in ipairs(nativeRowIdentities(q))do
  if row.group==saved.row.group and(row.group and row.name==saved.row.name or not row.group and row.item==saved.row.item)then return i end
 end
 error('native selection anchor lost')
end
local function transition(value)stage=value;stageAt=now();lastRequest=nil end
local function request(name,args)
 args=args or {};args.case='inventory-food-age';args.index=index;args.token=ids and ids.token
 if name=='Prepare'then args.spawn=spawn end
 if isClient()then sendClientCommand(F.module,name,args);return end
 if name=='Prepare'then replies.Prepared=F.preparePhase(session,index);authority=session.phase
 elseif name=='Ready'then replies.Readyd=F.snapshot(session,current)
 elseif name=='Status'then local snap=F.snapshot(session,current);snap.ready=not snap.tailFresh;replies.Statusd=snap
 elseif name=='Finish'then replies.Finishd=F.snapshot(session,current)
 elseif name=='Release'then replies.Released=F.release(session)
 elseif name=='Cleanup'then replies.Cleanupd=true end
end
Events.OnServerCommand.Add(function(module,name,value)if module==F.module then replies[name]=value end end)
local function saveUI(baseline)
 if baseline then return {lifecycle=uiLifecycle,baseline=uiLifecycle.beginBaseline()}end
 local player=getPlayer();local saved={pages={},mode=CleanUI_isCleanInventoryUIEnabled(),god=player:isGodMod(),ghost=player:isGhostMode(),
  focusLoss=getCore():getOptionPauseOnFocusloss()}
 for _,p in ipairs({getPlayerInventory(0),getPlayerLoot(0)})do local q=p.inventoryPane
  saved.pages[#saved.pages+1]={page=p,pane=q,inventory=q.inventory,visible=p:getIsVisible(),collapsed=p.isCollapsed,pin=p.pin,collapseCounter=p.collapseCounter,
   x=p:getX(),y=p:getY(),width=p:getWidth(),height=p:getHeight(),maxDrawHeight=p:getMaxDrawHeight(),
   paneX=q:getX(),paneY=q:getY(),paneWidth=q:getWidth(),paneHeight=q:getHeight(),paneVisible=q:getIsVisible(),paneMaxDrawHeight=q:getMaxDrawHeight(),
   paneMode=q.mode,scroll=q:getYScroll(),smoothScrollY=q.smoothScrollY,smoothScrollTargetY=q.smoothScrollTargetY,
   groups=shallow(q.collapsed),selected=saveSelection(q),equippedCollapsed=q.equippedCollapsed,
   firstSelect=anchor(q,q.firstSelect),joyselection=anchor(q,q.joyselection and q.joyselection+1),mouseOverOption=q.mouseOverOption,
   forceSelected=p.forceSelectedContainer,forceTime=p.forceSelectedContainerTime,
   collapseButton=p.collapseButton and p.collapseButton:getIsVisible(),pinButton=p.pinButton and p.pinButton:getIsVisible()}
 end
 saved.option=assert(PZAPI.ModOptions:getOptions('CleanUI'):getOption('optimizeLargeStacks'),'large-stack option missing')
 saved.optimize=saved.option:getValue();saved.returnPosition=returnPosition;saved.lifecycle=uiLifecycle;return saved
end
local function restoreObserver()
 for i=#restores,1,-1 do local r=restores[i]
  assert(r.owner[r.key]==r.wrapper,'native food-age observer replaced');r.owner[r.key]=r.raw
 end
 restores={};published=nil;passes=0
end
local function restoredPaneGeometry(saved,p)
 local q=p.inventoryPane
 return q:getX()==saved.paneX and q:getY()==saved.paneY and q:getWidth()==saved.paneWidth and q:getHeight()==saved.paneHeight
end
local function settleRestoredLayout(savedPages,livePages)
 -- arrange() wraps at its old width before adopting the restored owner width.
 -- Restore both bindings first: inventory controls also consult the loot page.
 for attempt=1,4 do
  for _,p in ipairs(livePages)do uiLifecycle.ownerLayout(p)end
  local matched=true
  for i,p in ipairs(livePages)do if not restoredPaneGeometry(savedPages[i],p)then matched=false end end
  if matched then return end
 end
 local proof=uiLifecycle.restorationProof(savedPages,livePages);proof.stage='restore-ui-layout';proof.attempts=4
 F.emit('DIAGNOSTIC',proof);error('live UI pane geometry not restored after bounded native owner layout',0)
end
local function restoreUI()
 restoreObserver();if not ui or not ui.option then return end
 ui.option:setValue(ui.optimize);CleanUI_setCleanInventoryUIEnabled(ui.mode)
 local player=getPlayer()
 if position then player:teleportTo(position.x,position.y,position.z);position=nil end
 local livePages={getPlayerInventory(0),getPlayerLoot(0)}
 for i,saved in ipairs(ui.pages)do local p=livePages[i]
  p.forceSelectedContainer=nil;p.forceSelectedContainerTime=nil
  uiLifecycle.setGeometry(p,{x=saved.x,y=saved.y,width=saved.width,height=saved.height})
  if saved.pin then p:setPinned()else p:collapse()end
  p:setVisible(saved.visible);p.isCollapsed=saved.collapsed;p.collapseCounter=saved.collapseCounter;p:setMaxDrawHeight(saved.maxDrawHeight)
  local q=p.inventoryPane
  uiLifecycle.setGeometry(q,{x=saved.paneX,y=saved.paneY,width=saved.paneWidth,height=saved.paneHeight});q:setMode(saved.paneMode)
  q:setVisible(saved.paneVisible);q:setMaxDrawHeight(saved.paneMaxDrawHeight);q.collapsed=shallow(saved.groups);q.equippedCollapsed=saved.equippedCollapsed
  p:refreshBackpacks();local available={}
  for _,button in ipairs(p.backpacks or {})do if button.inventory then available[button.inventory]=true end end
  uiLifecycle.requireRestore(available[saved.inventory],'original native UI container unavailable after restore',ui.pages,livePages)
  p:setNewContainer(saved.inventory)
  uiLifecycle.requireRestore(q==p.inventoryPane and q.inventory==saved.inventory and p.inventory==saved.inventory,'active native UI binding not restored',ui.pages,livePages)
 end
 settleRestoredLayout(ui.pages,livePages)
 for i,saved in ipairs(ui.pages)do local p=livePages[i];local q=p.inventoryPane;local available={}
  for _,button in ipairs(p.backpacks or {})do if button.inventory then available[button.inventory]=true end end
  uiLifecycle.requireRestore(available[saved.inventory]and q.inventory==saved.inventory and p.inventory==saved.inventory,'active native UI binding changed during layout',ui.pages,livePages)
  uiLifecycle.requireRestore(q.lastinventory==nil or available[q.lastinventory],'native UI cache has unavailable container',ui.pages,livePages)
  restoreSelection(q,saved.selected);q.firstSelect=restoreAnchor(q,saved.firstSelect)
  local joy=restoreAnchor(q,saved.joyselection);q.joyselection=joy and joy-1 or nil;q.mouseOverOption=saved.mouseOverOption
  q:setYScroll(saved.scroll);q.smoothScrollY=saved.smoothScrollY;q.smoothScrollTargetY=saved.smoothScrollTargetY
  p.forceSelectedContainer=saved.forceSelected;p.forceSelectedContainerTime=saved.forceTime
  if p.collapseButton then p.collapseButton:setVisible(saved.collapseButton)end
  if p.pinButton then p.pinButton:setVisible(saved.pinButton)end
  uiLifecycle.requireRestore(p==(i==1 and getPlayerInventory(0)or getPlayerLoot(0))and p:getX()==saved.x and p:getY()==saved.y and p:getWidth()==saved.width and p:getHeight()==saved.height,'live UI page geometry not restored',ui.pages,livePages)
  uiLifecycle.requireRestore(p.pin==saved.pin and p.isCollapsed==saved.collapsed and p:getIsVisible()==saved.visible and p:getMaxDrawHeight()==saved.maxDrawHeight,'live UI page state not restored',ui.pages,livePages)
  uiLifecycle.requireRestore(restoredPaneGeometry(saved,p),'live UI pane geometry changed after selection restore',ui.pages,livePages)
  uiLifecycle.requireRestore(q:getYScroll()==saved.scroll and q.mode==saved.paneMode and q:getIsVisible()==saved.paneVisible and q:getMaxDrawHeight()==saved.paneMaxDrawHeight,'live UI pane state not restored',ui.pages,livePages)
 end
 player:setGodMod(ui.god);player:setGhostMode(ui.ghost)
 getCore():setOptionPauseOnFocusloss(ui.focusLoss)
 uiLifecycle.requireRestore(CleanUI_isCleanInventoryUIEnabled()==ui.mode and ui.option:getValue()==ui.optimize,'food-age mode/options restoration differs',ui.pages,livePages)
 uiLifecycle.requireRestore(player:isGodMod()==ui.god and player:isGhostMode()==ui.ghost,'food-age player flags restoration differs',ui.pages,livePages)
end
function uiLifecycle.setGeometry(element,value)
 -- Top-level native setters clamp position against the element's current size.
 element:setWidth(value.width);element:setHeight(value.height);element:setX(value.x);element:setY(value.y)
end
function uiLifecycle.fixtureGeometry()
 local width=math.min(1000,getCore():getScreenWidth()-60);local height=math.min(460,getCore():getScreenHeight()-110)
 assert(width>=400 and height>=150,'native food-age viewport too small')
 return {x=30,y=50,width=width,height=height}
end
function uiLifecycle.restorationProof(savedPages,livePages)
 local proof={stage='restore-ui',pages={}}
 for i,saved in ipairs(savedPages)do local p=livePages[i];local q=p.inventoryPane
  proof.pages[i]={page=i,
   expected={owner={x=saved.x,y=saved.y,width=saved.width,height=saved.height},pane={x=saved.paneX,y=saved.paneY,width=saved.paneWidth,height=saved.paneHeight},
    visible=saved.visible,pin=saved.pin,collapsed=saved.collapsed,maxDrawHeight=saved.maxDrawHeight,paneVisible=saved.paneVisible,paneMode=saved.paneMode,scroll=saved.scroll,paneMaxDrawHeight=saved.paneMaxDrawHeight},
   actual={owner={x=p:getX(),y=p:getY(),width=p:getWidth(),height=p:getHeight()},pane={x=q:getX(),y=q:getY(),width=q:getWidth(),height=q:getHeight()},
    visible=p:getIsVisible(),pin=p.pin,collapsed=p.isCollapsed,maxDrawHeight=p:getMaxDrawHeight(),paneVisible=q:getIsVisible(),paneMode=q.mode,scroll=q:getYScroll(),paneMaxDrawHeight=q:getMaxDrawHeight()},
   controls=p.controlsUI and {width=p.controlsUI.width,height=p.controlsUI.height}or nil,
   inventoryBound=q.inventory==saved.inventory and p.inventory==saved.inventory,
   livePage=p==(i==1 and getPlayerInventory(0)or getPlayerLoot(0))}
 end
 return proof
end
function uiLifecycle.requireRestore(condition,message,savedPages,livePages)
 if condition then return end
 local proof=uiLifecycle.restorationProof(savedPages,livePages);proof.error=message
 F.emit('DIAGNOSTIC',proof);error(message,0)
end
function uiLifecycle.ownerLayout(p)
 if p.cleanUIApplyScaleSettings then p:cleanUIApplyScaleSettings(true)else p:refreshBackpacks()end
end
function uiLifecycle.beginBaseline()
 return {startedAt=now(),samples=0,times={},intervalMs=120,deadlineMs=10000}
end
function uiLifecycle.readLayout()
 local pages={getPlayerInventory(0),getPlayerLoot(0)}
 if not pages[1]or not pages[2]then return end
 local result={}
 for i,p in ipairs(pages)do local q=p.inventoryPane
  if not q or not q.inventory or p.inventory~=q.inventory then return end
  local controls=p.controlsUI
  result[i]={page=p,pane=q,inventory=q.inventory,controls=controls or false,
   x=p:getX(),y=p:getY(),width=p:getWidth(),height=p:getHeight(),
   paneX=q:getX(),paneY=q:getY(),paneWidth=q:getWidth(),paneHeight=q:getHeight(),
   controlsWidth=controls and controls.width or 0,controlsHeight=controls and controls.height or 0}
 end
 return result
end
function uiLifecycle.describeLayout(layout)
 local result={}
 for i,value in ipairs(layout or {})do
  result[i]={page=i,owner={x=value.x,y=value.y,width=value.width,height=value.height},
   pane={x=value.paneX,y=value.paneY,width=value.paneWidth,height=value.paneHeight},
   controls={width=value.controlsWidth,height=value.controlsHeight},inventoryBound=true}
 end
 return result
end
function uiLifecycle.sampleBaseline(state)
 local elapsed=now()-state.startedAt
 if elapsed>=state.deadlineMs then
  F.emit('DIAGNOSTIC',{stage='ui-baseline',elapsedMs=elapsed,deadlineMs=state.deadlineMs,
   samples=state.samples,pages=uiLifecycle.describeLayout(uiLifecycle.readLayout())})
  error('initial native UI layout did not settle within ten seconds',0)
 end
 local pages={getPlayerInventory(0),getPlayerLoot(0)}
 if not pages[1]or not pages[2]or not pages[1].inventoryPane or not pages[2].inventoryPane then
  state.samples=0;state.candidate=nil;state.times={};state.lastSampleAt=nil;return
 end
 if state.lastSampleAt and now()-state.lastSampleAt<state.intervalMs then return end
 state.lastSampleAt=now()
 for _,p in ipairs(pages)do uiLifecycle.ownerLayout(p)end
 local layout=uiLifecycle.readLayout();local valid=layout~=nil
 for _,value in ipairs(layout or {})do
  if value.width<=0 or value.height<=0 or value.paneWidth<=0 or value.paneHeight<=0
   or value.paneX<0 or value.paneY<0 or value.paneX+value.paneWidth>value.width+.01 or value.paneY+value.paneHeight>value.height+.01 then valid=false end
 end
 if not valid then state.samples=0;state.candidate=nil;state.times={};return end
 local same=state.candidate~=nil
 if same then for i,value in ipairs(layout)do
  for key,item in pairs(value)do if state.candidate[i][key]~=item then same=false end end
 end end
 if same then state.samples=state.samples+1 else state.samples=1;state.times={}end
 state.candidate=layout;state.times[#state.times+1]=now()
 if state.samples<3 then return end
 local proof={stable=true,samples=3,intervalMs=state.intervalMs,deadlineMs=state.deadlineMs,elapsedMs=elapsed,
  stableSpanMs=state.times[3]-state.times[1],sampleTimesMs=state.times,pages=uiLifecycle.describeLayout(layout)}
 F.emit('DIAGNOSTIC',{stage='ui-baseline',proof=proof});return proof
end
function uiLifecycle.preflight(saved)
 assert(ui==saved,'UI preflight must own the captured baseline')
 local began=now();local proof={modeChanged=true,resized=true,relocated=true,restored=false,originalMode=saved.mode,
  temporaryMode=not saved.mode,deadlineMs=10000,pages={}}
 CleanUI_setCleanInventoryUIEnabled(not saved.mode)
 assert(CleanUI_isCleanInventoryUIEnabled()==not saved.mode,'UI preflight mode did not change')
 for i,p in ipairs({getPlayerInventory(0),getPlayerLoot(0)})do local original=saved.pages[i]
  local geometry=uiLifecycle.fixtureGeometry()
  if geometry.width==original.width then geometry.width=geometry.width-40 end
  if geometry.height==original.height then geometry.height=geometry.height-30 end
  if geometry.x==original.x then geometry.x=geometry.x+10 end
  if geometry.y==original.y then geometry.y=geometry.y+10 end
  uiLifecycle.setGeometry(p,geometry);p:refreshBackpacks()
  proof.pages[i]={page=i,original={x=original.x,y=original.y,width=original.width,height=original.height},temporary={x=p:getX(),y=p:getY(),width=p:getWidth(),height=p:getHeight()}}
  assert(p:getWidth()~=original.width and p:getHeight()~=original.height,'UI preflight owner dimensions did not change')
  assert(p:getX()~=original.x and p:getY()~=original.y,'UI preflight owner position did not change')
 end
 F.emit('DIAGNOSTIC',{stage='ui-preflight',event='changed',proof=proof})
 restoreUI()
 for i,p in ipairs({getPlayerInventory(0),getPlayerLoot(0)})do
  proof.pages[i].restored={x=p:getX(),y=p:getY(),width=p:getWidth(),height=p:getHeight()}
 end
 proof.elapsedMs=now()-began;assert(proof.elapsedMs<proof.deadlineMs,'UI preflight exceeded ten seconds')
 proof.restored=true;F.emit('DIAGNOSTIC',{stage='ui-preflight',event='restored',proof=proof});return proof
end
local function paneClass()
 local name=current.spec.paneMode=='clean'and 'CleanUI_Clean_ISInventoryPane'or 'CleanUI_Vanilla_ISInventoryPane'
 assert(getmetatable(pane)==_G[name]and ISInventoryPane==_G[name],'selected native pane class differs');return name
end
local function bounds(row)
 local top=pane.headerHgt+(row-1)*pane.itemHgt+pane:getYScroll();local bottom=top+pane.itemHgt
 local pageVisible=page:getIsVisible()and page:isReallyVisible()and not page.isCollapsed
 local paneVisible=pane:getIsVisible()and pane:isReallyVisible()
 local height=pane:getHeight();local max=pane:getMaxDrawHeight();if max>=0 then height=math.min(height,max)end
 local scrollHeight=pane:getScrollHeight();local scrollAreaHeight=pane:getScrollAreaHeight()
 return {world=getGameTime():getWorldAgeHours(),age=tail:getAge(),events=events,primaryPasses=passes,
  pageVisible=pageVisible,paneVisible=paneVisible,rowTop=top,rowBottom=bottom,header=pane.headerHgt,height=height,
  scroll=pane:getYScroll(),minScroll=math.min(0,scrollAreaHeight-scrollHeight),scrollHeight=scrollHeight,scrollAreaHeight=scrollAreaHeight,
  rowVisible=pageVisible and paneVisible and bottom>pane.headerHgt and top<height-1}
end
-- Published group membership includes every actual item; native expansion still caps child rows at 50.
local function rows()
 if passes==0 then return end
 assert(published==pane.items,'native rows changed after publication')
 local seen,rendered,headRow,tailRow,headGroup,tailGroup={}, {},nil,nil,nil,nil
 local groups,expandedRows,fillerVisibleRows={},0,0
 for row,value in ipairs(published)do
  if type(value)=='table'and value.items then
   local first=value.cleanUIFirstActualIndex or 2;local count=#value.items-first+1;local ownedGroup=false
   for i=first,#value.items do local item=value.items[i]
    if foodSet[item]then
     assert(not seen[item],'food duplicated across published native groups');seen[item]=true;ownedGroup=true
     if item==head then headRow=row;headGroup=count end
     if item==tail then tailRow=row;tailGroup=count end
    end
   end
   if ownedGroup then
    groups[#groups+1]={row=row,value=value,count=count}
    local item=value.items[first];if foodSet[item]then rendered[item]=true end
   end
   if fillerSet then for i=first,#value.items do if fillerSet[value.items[i]]then
    if bounds(row).rowVisible then fillerVisibleRows=fillerVisibleRows+1 end;break
   end end end
  elseif foodSet[value]then rendered[value]=true;expandedRows=expandedRows+1
  elseif fillerSet and fillerSet[value]and bounds(row).rowVisible then fillerVisibleRows=fillerVisibleRows+1 end
 end
 local count,renderCount=0,0;for _ in pairs(seen)do count=count+1 end;for _ in pairs(rendered)do renderCount=renderCount+1 end
 assert(count==#foods and headRow and tailRow,'native published food identity/cardinality differs')
 local foodVisible=false
 for _,group in ipairs(groups)do if bounds(group.row).rowVisible then foodVisible=true end end
 for row,value in ipairs(published)do if foodSet[value]and bounds(row).rowVisible then foodVisible=true end end
 return {headRow=headRow,tailRow=tailRow,headGroup=headGroup,tailGroup=tailGroup,count=count,groups=groups,
  foodVisible=foodVisible,fillerVisibleRows=fillerVisibleRows,expandedRows=expandedRows,renderedFoodCount=renderCount,publishedRows=#published}
end
local function observe()
 local native,raw=pane.renderdetails,rawget(pane,'renderdetails');local wrapper
 wrapper=function(self,dragged,...)
  local result=pack(pcall(native,self,dragged,...))
  if not result[1]then observerFailure=observerFailure or result[2];error(result[2],0)end
  if self==pane and dragged==false then
   published=pane.items;passes=passes+1
   if concealing then
    local ok,value=pcall(rows)
    if not ok then observerFailure=observerFailure or value
    elseif value and value.foodVisible then foodVisiblePasses=foodVisiblePasses+1 end
   end
  end
  return unpack(result,2,result.n)
 end
 pane.renderdetails=wrapper;restores[#restores+1]={owner=pane,key='renderdetails',raw=raw,wrapper=wrapper}
end
local function containerUpdate(item)
 if item==tail and current then events=events+1;eventClock=getGameTime():getWorldAgeHours()end
end
local function nativeGroups(collapsed)
 for _,group in ipairs(pane.itemslist or {})do if group.items then
  for i=group.cleanUIFirstActualIndex or 2,#group.items do
   if foodSet[group.items[i]]then pane.collapsed[group.name]=collapsed;break end
  end
 end end
 pane:refreshContainer()
end
local function selectContainer()
 if pane.inventory==current.container then
  if isClient()then page:setForceSelectedContainer(current.container,4000)end;return true
 end
 if isClient()then page:refreshBackpacks();page:selectButtonForContainer(current.container);page:setForceSelectedContainer(current.container,4000)
 else page:setNewContainer(current.container)end
 return pane.inventory==current.container
end
local function configureUI()
 CleanUI_setCleanInventoryUIEnabled(current.spec.paneMode=='clean')
 page=isClient()and getPlayerLoot(0)or getPlayerInventory(0);pane=page.inventoryPane;paneClass()
 for _,p in ipairs({getPlayerInventory(0),getPlayerLoot(0)})do p:setVisible(p==page)end
 uiLifecycle.setGeometry(page,uiLifecycle.fixtureGeometry());page:setVisible(true);page.isCollapsed=false;page:setPinned();page:clearMaxDrawHeight()
 pane:setVisible(true);pane:clearMaxDrawHeight();pane:setMode('details');pane.smoothScrollY=nil;pane.smoothScrollTargetY=nil;pane:setYScroll(0)
 foods=current.foods;tail=current.tail;head=nil;foodSet={};for _,item in ipairs(foods)do foodSet[item]=true end
 fillerSet={};for _,item in ipairs(current.fillers)do fillerSet[item]=true end
 passes=0;published=nil;events=0;eventClock=nil;observerFailure=nil;cycles={};concealing=false;foodVisiblePasses=0
 observe();transition('select')
end
local function collapseInitial()
 pane:refreshContainer();local found
 for _,group in ipairs(pane.itemslist)do if group.items then
  local start=group.cleanUIFirstActualIndex or 2
  for i=start,#group.items do if group.items[i]==tail then
   assert(not found);found=group;head=group.items[start];assert(head~=tail and head:isFresh()and i-start+1>50,'tail not beyond younger native header/first50')
   tailBeyond50=true;pane.collapsed[group.name]=true
  end end
  for i=start,#group.items do if group.items[i]==current.fillers[1]then pane.collapsed[group.name]=false end end
 end end
 assert(found,'initial native food group missing');current.head=head
 pane:refreshContainer();proofPass=passes;transition('initial')
end
local function placeVisible(info)
 local minimum=math.min(0,pane:getScrollAreaHeight()-pane:getScrollHeight())
 pane.smoothScrollY=nil;pane.smoothScrollTargetY=nil;pane:setYScroll(math.max(minimum,-math.max(0,info.tailRow-2)*pane.itemHgt))
end
local function conceal(info)
 local exposure=current.spec.exposure
 if exposure=='hidden'then page:setVisible(false)
 elseif exposure=='clipped'then
  pane.smoothScrollY=nil;pane.smoothScrollTargetY=nil
  local minimum=math.min(0,pane:getScrollAreaHeight()-pane:getScrollHeight())
  pane:setYScroll(info.tailRow<=info.publishedRows/2 and minimum or 0)
 else placeVisible(info)end
 foodVisiblePasses=0;concealing=true;proofPass=passes;concealedAt=now();transition('conceal')
end
local function diagnostics(force,problem)
 if not force and lastDiagnostic and now()-lastDiagnostic<10000 then return end;lastDiagnostic=now()
 local row={stage=stage,index=index,error=problem and tostring(problem)or nil,elapsedMs=phaseBegan and now()-phaseBegan or 0,
  events=events,primaryPasses=passes,foodVisiblePasses=foodVisiblePasses}
 if current then
  local ok,value=pcall(F.snapshot,session,current);if ok then row.snapshot=value else row.snapshotError=tostring(value)end
  if pane and tail then
   local read,info=pcall(rows);if read and info then row.row=bounds(info.tailRow);row.headGroup=info.headGroup;row.tailGroup=info.tailGroup
   elseif not read then row.rowError=tostring(info)end
  end
 end
 if stage=='return-position'and position then
  row.position={original=shallow(position),actual=returnPosition.read(),elapsedMs=now()-returnPosition.startedAt,deadlineMs=10000}
 end
 F.emit(force and 'FAIL'or 'DIAGNOSTIC',row)
end
local function startPhase()
 restoreObserver();current=nil;authority=nil;ids=ids and {token=ids.token}or nil
 phaseBegan=now();request('Prepare');transition('prepared')
end
local function split(info)
 assert(head:isFresh(),'younger native header unexpectedly stale')
 return not tail:isFresh()and info.headRow~=info.tailRow and info.tailGroup==1 and info.headGroup==#foods-1
end
local function beginCycles()
 concealing=false;cycle=1;cycleMode='expanded';nativeGroups(false);proofPass=passes;transition('cycles')
end
function returnPosition.read()
 local player=getPlayer();local square,currentSquare=player:getSquare(),player:getCurrentSquare()
 return {x=player:getX(),y=player:getY(),z=player:getZ(),squareX=square and square:getX(),squareY=square and square:getY(),squareZ=square and square:getZ(),
  currentSquareX=currentSquare and currentSquare:getX(),currentSquareY=currentSquare and currentSquare:getY(),currentSquareZ=currentSquare and currentSquare:getZ(),
  moving=player:isPlayerMoving(),hasPath=player:getPath2()~=nil}
end
function returnPosition.begin()
 assert(isClient()and position,'Host return requires the captured original position')
 local player=getPlayer();player:teleportTo(position.x,position.y,position.z)
 -- teleportTo's float overload floors coordinates; restore native next/last positions too.
 player:setForceX(position.x);player:setForceY(position.y);player:setZ(position.z)
 returnPosition.startedAt=now();transition('return-position')
end
function returnPosition.poll()
 local elapsed=now()-returnPosition.startedAt
 assert(elapsed<10000,'Host original-position return did not settle within ten seconds')
 local actual=returnPosition.read()
 if elapsed<100 or actual.squareX==nil or actual.currentSquareX==nil then return end
 if math.abs(actual.x-position.x)>.01 or math.abs(actual.y-position.y)>.01 or math.abs(actual.z-position.z)>.01
  or actual.squareX~=position.squareX or actual.squareY~=position.squareY or actual.squareZ~=position.squareZ
  or actual.currentSquareX~=position.squareX or actual.currentSquareY~=position.squareY or actual.currentSquareZ~=position.squareZ
  or actual.moving or actual.hasPath then return end
 return {original=shallow(position),actual=actual,elapsedMs=elapsed,deadlineMs=10000,minimumWaitMs=100}
end
local function tick()
 if observerFailure then error(observerFailure,0)end
 assert(not replies.Failed,replies.Failed and replies.Failed.error)
 assert(now()-began<1800000,'food-age lifecycle deadline exceeded')
 assert(not phaseBegan or now()-phaseBegan<180000,'food-age phase deadline exceeded: '..stage)
 if current and stage~='release'then
  F.conserved(session,current)
  if stage~='select'then assert(selectContainer(),'native selected food-age container changed')end
 end
 diagnostics(false)
 if stage=='setup'then
  assert(config.cases[1]=='inventory-food-age'and #config.cases==1,'food-age selection differs')
  assert(config.kind=='sp'or config.kind=='mp'and config.options and config.options.mp_host,'food-age requires SP or menu Host')
  ui=saveUI(true);transition('ui-baseline')
 elseif stage=='ui-baseline'then
  local proof=ui.lifecycle.sampleBaseline(ui.baseline);if not proof then return end
  ui=saveUI();ui.baselineProof=proof;ui.preflightProof=ui.lifecycle.preflight(ui);transition('setup-fixture')
 elseif stage=='setup-fixture'then
  local player=getPlayer();player:setGodMod(true);player:setGhostMode(true);getCore():setOptionPauseOnFocusloss(false)
  ui.option:setValue(true);session=F.newSession(player);F.setup(session,{uiBaseline=ui.baselineProof,uiPreflight=ui.preflightProof});Events.OnContainerUpdate.Add(containerUpdate)
  if SurvivalGuide and SurvivalGuide.instance then ui.survivalGuide=SurvivalGuide.instance;ui.guideVisible=ui.survivalGuide:getIsVisible();ui.survivalGuide:setVisible(false)end
  if isClient()then
   local square=player:getSquare()
   position={x=player:getX(),y=player:getY(),z=player:getZ(),squareX=square:getX(),squareY=square:getY(),squareZ=square:getZ()}
   local origin=F.chooseOrigin(player)
   spawn={x=origin:getX(),y=origin:getY(),z=origin:getZ()}
   if player:getSquare()~=origin then player:teleportTo(spawn.x+.5,spawn.y+.5,spawn.z)end
   transition('position')
  else startPhase()end
 elseif stage=='position'then
  local square=getPlayer():getSquare()
  if now()-stageAt>=1500 and square:getX()==spawn.x and square:getY()==spawn.y and square:getZ()==spawn.z then startPhase()end
 elseif stage=='prepared'and replies.Prepared then
  if replies.Prepared.waiting then
   if not lastRequest or now()-lastRequest>=1000 then replies.Prepared=nil;request('Prepare');lastRequest=now()end;return
  end
  local received=replies.Prepared
  if isClient()then current=F.resolve(session,received);if not current then return end;session.index=index;session.phase=current;current.beforeWorld=getGameTime():getWorldAgeHours()
  else current=authority end
  ids=received;replies.Prepared=nil;configureUI()
 elseif stage=='select'then
  if not selectContainer()then return end;collapseInitial()
 elseif stage=='initial'and passes>proofPass then
  local info=rows();assert(head and tail:isFresh()and events==0,'fresh initial native proof missed deadline')
  assert(info.headRow==info.tailRow and info.headGroup==#foods,'initial native food group differs')
  for _,group in ipairs(info.groups)do if group.row==info.tailRow then initialOptimized=group.value.cleanUILargeStackOptimized==true end end
  assert(initialOptimized==(current.spec.paneMode=='clean'and #foods==200),'native large-stack threshold differs')
  placeVisible(info);proofPass=passes;transition('position-row')
 elseif stage=='position-row'and passes>proofPass then
  local info=rows();assert(bounds(info.tailRow).rowVisible,'initial native food group is not visible')
  assert(tail:isFresh()and events==0,'tail expired before concealed observation');request('Ready',{tailId=tail:getID()});transition('ready')
 elseif stage=='ready'and replies.Readyd then
  assert(replies.Readyd.index==index and replies.Readyd.tailId==tail:getID(),'native initial authority receipt differs')
  replies.Readyd=nil;conceal(rows())
 elseif stage=='conceal'then
  local exposure=current.spec.exposure
  if exposure~='hidden'and passes<=proofPass+1 then return end
  if exposure=='hidden'and now()-concealedAt<100 then return end
  local info=rows();local value=bounds(info.tailRow)
  if exposure=='clipped'then
   assert(not info.foodVisible and info.fillerVisibleRows>0,'native food clipping needs visible owned filler rows')
   assert(value.scroll>=value.minScroll-.01 and value.scroll<=0,'native clipped scroll is outside its real range')
  end
  assert(tail:isFresh()and events==0,'freshness boundary preceded exposure proof')
  assert(exposure=='visible'and value.rowVisible or exposure=='hidden'and not value.pageVisible or exposure=='clipped'and value.pageVisible and value.paneVisible and not value.rowVisible,'native exposure geometry differs')
  value.fillerVisibleRows=info.fillerVisibleRows;foodVisiblePasses=0;exposureStart=value;transition('observe')
 elseif stage=='observe'then
  local info=rows();local exposure=current.spec.exposure
  if exposure~='visible'then assert(not info.foodVisible,'concealed food became visible before barrier')end
  if exposure=='clipped'then assert(info.fillerVisibleRows>0,'clipped native viewport lost visible filler rows')end
  assert(head:isFresh(),'younger native food expired')
  local world=getGameTime():getWorldAgeHours()
  if world<current.potentialThresholdWorld+.002 then return end
  if isClient()then
   if replies.Statusd then assert(replies.Statusd.index==index and replies.Statusd.tailId==tail:getID(),'native threshold authority receipt differs')end
   if not replies.Statusd or not replies.Statusd.ready then
    if not lastRequest or now()-lastRequest>=500 then request('Status');lastRequest=now()end;return
   end
  end
  exposureFinish=bounds(info.tailRow)
  exposureFinish.fillerVisibleRows=info.fillerVisibleRows
  assert(exposureStart.world<exposureFinish.world,'food-age concealment lacks forward world clock')
  if exposure~='visible'then assert(foodVisiblePasses==0,'food rendered visibly during concealed ageing')end
  concealing=false;page:setVisible(true);placeVisible(info);proofPass=passes;transition('reveal')
 elseif stage=='reveal'and passes>proofPass then
  local info=rows();if not split(info)then return end
  assert(events==1 and eventClock and eventClock>current.beforeWorld,'missing/duplicate exact native freshness event')
  assert(bounds(info.tailRow).rowVisible,'revealed stale native row not visible');beginCycles()
 elseif stage=='cycles'and passes>proofPass then
  local info=rows();assert(split(info)and events==1,'rebuild changed native freshness grouping/event')
  if cycleMode=='expanded'then
   assert(info.expandedRows>=2 and info.renderedFoodCount>=2,'native expanded children not published')
   expandedProof={expandedActualCount=info.count,expandedPublishedRows=info.expandedRows+#info.groups,expandedRenderedFoodCount=info.renderedFoodCount}
   nativeGroups(true);cycleMode='collapsed';proofPass=passes
  else
   for _,group in ipairs(info.groups)do assert(pane.collapsed[group.value.name]==true,'native group did not collapse')end
   expandedProof.cycle=cycle;expandedProof.collapsedActualCount=info.count;expandedProof.headGroup=info.headGroup;expandedProof.tailGroup=info.tailGroup;expandedProof.identities=true
   cycles[#cycles+1]=expandedProof
   if cycle<3 then cycle=cycle+1;cycleMode='expanded';nativeGroups(false);proofPass=passes
   else
    local row=F.receipt(session,current);row.events=events;row.eventWorld=eventClock;row.paneClass=paneClass();row.optimized=initialOptimized
    row.headGroup=info.headGroup;row.tailGroup=info.tailGroup;row.separatePublishedRows=true;row.tailBeyond50=tailBeyond50;row.primaryPasses=passes;row.cycles=cycles
    row.exposureProof={start=exposureStart,finish=exposureFinish,potentialThresholdWorld=current.potentialThresholdWorld,
     concealedWorldHours=exposureFinish.world-exposureStart.world,foodVisiblePasses=foodVisiblePasses}
    row.elapsedMs=now()-phaseBegan;phaseReceipt=row;request('Finish',{headId=head:getID()});transition('finish')
   end
  end
 elseif stage=='finish'and replies.Finishd then
  assert(replies.Finishd.index==index and replies.Finishd.headId==head:getID()and replies.Finishd.tailId==tail:getID(),'native final authority receipt differs')
  if isClient()then phaseReceipt.authority=replies.Finishd end;replies.Finishd=nil
  F.emit('AGE_PHASE',phaseReceipt);restoreObserver();releaseIds=ids;request('Release');transition('release')
 elseif stage=='release'and replies.Released then
  if isClient()and not F.absent(releaseIds)then return end
  if isClient()then
   session.removed=session.removed+#current.foods;session.fillerRemoved=session.fillerRemoved+#current.fillers
   session.objectsRemoved=session.objectsRemoved+1;session.phase=nil
  end
  replies.Released=nil;replies.Statusd=nil;current=nil;tail=nil;head=nil
  if index==#F.phases then request('Cleanup');transition('cleanup')else index=index+1;startPhase()end
 elseif stage=='cleanup'and replies.Cleanupd then
  if isClient()then ui.returnPosition.begin();return end
  Events.OnContainerUpdate.Remove(containerUpdate);restoreUI()
  if ui.survivalGuide then ui.survivalGuide:setVisible(ui.guideVisible)end
  F.restored(session,{ui=true,observers=true,mode=true,optimize=true});done=true
 elseif stage=='return-position'then
  local positionProof=ui.returnPosition.poll();if not positionProof then return end
  position=nil;Events.OnContainerUpdate.Remove(containerUpdate);restoreUI()
  if ui.survivalGuide then ui.survivalGuide:setVisible(ui.guideVisible)end
  F.restored(session,{ui=true,observers=true,mode=true,optimize=true,positionRestored=true,positionProof=positionProof});done=true
 end
end
Events.OnGameStart.Add(function()started=true;began=now()end)
Events.OnTick.Add(function()
 if not started or done or not isIngameState()or not getPlayer()then return end
 if not getPlayer():getSquare()and stage~='return-position'then return end
 if isClient()and getPlayer():getOnlineID()<0 then return end
 local ok,problem=pcall(tick)
 if not ok then
  diagnostics(true,problem)
  local restored,restoreError=pcall(function()
   Events.OnContainerUpdate.Remove(containerUpdate)
   if isClient()then if ids and ids.token and not replies.Cleanupd then sendClientCommand(F.module,'Abort',{case='inventory-food-age',token=ids.token,index=index})end
   elseif session then F.release(session,true)end
   restoreUI();if ui and ui.survivalGuide then ui.survivalGuide:setVisible(ui.guideVisible)end
  end)
  F.emit('FAIL',{stage=stage,index=index,error=tostring(problem),restored=restored,restoreError=tostring(restoreError)});done=true
 end
end)
