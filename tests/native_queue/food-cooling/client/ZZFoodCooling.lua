require 'TimedActions/ISPlugGenerator'
require 'TimedActions/ISActivateGenerator'
require 'TimedActions/ISInventoryTransferAction'
require 'TimedActions/WalkToTimedAction'
local F=require 'QueueFoodCoolingFixture'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local started,done,phase,index,since=false,false,'prepare',0,0
local state,authority,ids,original,initial,ui,command,before,ack
local replies={};local actions={};local renderProof,readinessProof,observers={},{},{}
local targetIndex,targetAt,lastDiagnostic=1,0,0
local helperObserver,baselineSample
local helperProof={}
local observerFailure
local primaryPasses,lastObserved,desiredScroll={},{},{}
local walk,walkNumber,settleSequence,settleThen,settlePurpose,originRequestAt,observationStarted
local phaseReadyRequestAt
walkNumber,settleSequence=0,0
local spawn,position,placeTime,prepareAt,positionReturnAt
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function idle()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function request(name,extra)
 local args=extra or {};args.case=F.case;args.token=ids and ids.token
 if name=='Prepare'then args.spawn=spawn end
 if isClient()then sendClientCommand(F.module,name,args);return end
 if name=='Prepare'then authority=F.prepare(getPlayer());replies.Prepared=authority.ids
 elseif name=='Begin'then replies.Begind=F.begin(authority,args.index)
 elseif name=='End'then replies.Endd=F.finish(authority,args.index)
 elseif name=='Cleanup'then replies.Cleanupd=F.cleanup(authority)end
 if name=='Origin'then replies.Origind=F.settled(authority,args.index,args.sequence,args.purpose)end
end
Events.OnServerCommand.Add(function(module,name,value)
 if module~=F.module then return end
 replies[name]=value
end)
local function copyUIState(value)local copy={};for key,item in pairs(value or {})do copy[key]=item end;return copy end
local function nativeUIRows(pane)
 local rows={};local limit=pane.MAX_ITEMS_IN_STACK_TO_RENDER or(ISInventoryPane and ISInventoryPane.MAX_ITEMS_IN_STACK_TO_RENDER)or 50
 for _,group in ipairs(pane.itemslist or {})do if not(pane.equippedCollapsed and group.equipped)then
  rows[#rows+1]={item=group.cleanUIDisplayItem or group.firstItem or(group.items and group.items[1]),name=group.name,group=true}
  if group.items and not pane.collapsed[group.name]then
   local first=group.cleanUIFirstActualIndex or(group.cleanUILargeStackOptimized and 1)or 2
   for i=first,math.min(#group.items,first+limit-1)do rows[#rows+1]={item=group.items[i],group=false}end
  end
 end end;return rows
end
local function saveUISelection(pane)
 local native=pane:saveSelection({});local groups=copyUIState(native._cleanUISelectedGroups)
 local saved={_cleanUISelectedGroups=groups};local aliases={}
 for _,row in ipairs(nativeUIRows(pane))do if row.group and row.item then aliases[row.item]=row.name end end
 for item,kind in pairs(native)do if item~='_cleanUISelectedGroups'then
  assert(kind=='item'or kind=='group','unknown native cooling UI selection marker')
  if kind=='group'then groups[assert(aliases[item],'selected cooling header has no native group identity')]=true else saved[item]=kind end
 end end
 for i,row in ipairs(nativeUIRows(pane))do if row.group and pane.selected[i]then groups[assert(row.name)]=true end end
 for item,name in pairs(aliases)do if groups[name]then saved[item]=nil end end
 return saved
end
local function restoreUISelection(pane,saved)
 local input=copyUIState(saved);input._cleanUISelectedGroups=copyUIState(saved._cleanUISelectedGroups)
 for _,row in ipairs(nativeUIRows(pane))do
  if row.group and row.item and input._cleanUISelectedGroups[row.name]then input[row.item]='group'end
 end
 pane.selected={};pane:restoreSelection(input);local actual=saveUISelection(pane)
 for item,kind in pairs(saved)do if item~='_cleanUISelectedGroups'then assert(actual[item]==kind,'native cooling item selection lost')end end
 for item in pairs(actual)do if item~='_cleanUISelectedGroups'then assert(saved[item],'foreign native cooling item selection')end end
 for name in pairs(saved._cleanUISelectedGroups)do assert(actual._cleanUISelectedGroups[name],'native cooling group selection lost')end
 for name in pairs(actual._cleanUISelectedGroups)do assert(saved._cleanUISelectedGroups[name],'foreign native cooling group selection')end
end
local function captureUIAnchor(pane,index)return {index=index,row=index and nativeUIRows(pane)[index]or nil}end
local function restoreUIAnchor(pane,saved)
 if not saved.row then return saved.index end
 for i,row in ipairs(nativeUIRows(pane))do
  if row.group==saved.row.group and(row.group and row.name==saved.row.name or not row.group and row.item==saved.row.item)then return i end
 end
 error('native cooling selection anchor lost')
end
local function verifyUIAnchor(pane,index,saved)
 local actual=captureUIAnchor(pane,index)
 if not saved.row then assert(actual.index==saved.index,'native cooling inactive anchor changed');return end
 assert(actual.row and actual.row.group==saved.row.group
  and(actual.row.group and actual.row.name==saved.row.name or not actual.row.group and actual.row.item==saved.row.item),
  'native cooling anchor identity not restored')
end
local function settledUIBaseline()
 if not F.collapsedStacks then return true end
 local now=getTimestampMs();baselineSample=baselineSample or {began=now,count=0,times={}}
 local baseline=baselineSample
 if now-baseline.began>=10000 then F.emit('DIAGNOSTIC',{stage='ui-baseline',samples=baseline.count,elapsedMs=now-baseline.began});error('initial cooling UI layout did not settle within ten seconds',0)end
 if baseline.last and now-baseline.last<120 then return false end;baseline.last=now
 local values={};local pages={getPlayerInventory(0),getPlayerLoot(0)};local valid=pages[1]~=nil and pages[2]~=nil
 if not valid then baseline.count=0;baseline.previous=nil;baseline.times={};return false end
 for _,page in ipairs(pages)do if page.cleanUIApplyScaleSettings then page:cleanUIApplyScaleSettings(true)else page:refreshBackpacks()end end
 for i,page in ipairs(pages)do local pane=page.inventoryPane
  if not pane or not pane.inventory or pane.inventory~=page.inventory then valid=false;break end
  values[i]={page=page,pane=pane,inventory=pane.inventory,x=page:getX(),y=page:getY(),width=page:getWidth(),height=page:getHeight(),
   paneX=pane:getX(),paneY=pane:getY(),paneWidth=pane:getWidth(),paneHeight=pane:getHeight()}
  local value=values[i]
  if value.width<=0 or value.height<=0 or value.paneWidth<=0 or value.paneHeight<=0 or value.paneX<0 or value.paneY<0
   or value.paneX+value.paneWidth>value.width+.01 or value.paneY+value.paneHeight>value.height+.01 then valid=false end
 end
 local same=valid and baseline.previous~=nil
 if same then for i,value in ipairs(values)do for key,item in pairs(value)do if baseline.previous[i][key]~=item then same=false end end end end
 if not valid then baseline.count=0;baseline.previous=nil;baseline.times={};return false end
 if same then baseline.count=baseline.count+1 else baseline.count=1;baseline.times={}end
 baseline.previous=values;baseline.times[#baseline.times+1]=now
 if baseline.count<3 then return false end
 local proof={cleanMode=CleanUI_isCleanInventoryUIEnabled(),samples=baseline.count,sampleTimesMs=baseline.times,stableSpanMs=baseline.times[3]-baseline.times[1],pages={}}
 for i,value in ipairs(values)do proof.pages[i]={x=value.x,y=value.y,width=value.width,height=value.height,
  paneX=value.paneX,paneY=value.paneY,paneWidth=value.paneWidth,paneHeight=value.paneHeight,inventoryBound=true}end
 F.emit('UI_BASELINE',proof);return true
end
local function saveUI()
 local inventory,loot=getPlayerInventory(0),getPlayerLoot(0)
 local saved={inventory=inventory,loot=loot,pages={},cleanMode=F.collapsedStacks and CleanUI_isCleanInventoryUIEnabled(),focusLoss=getCore():getOptionPauseOnFocusloss()}
 for _,page in ipairs({inventory,loot})do
  local pane=page.inventoryPane;local collapsedItems={}
  for name,value in pairs(pane.collapsed or {})do collapsedItems[name]=value end
  saved.pages[#saved.pages+1]={page=page,pane=pane,pageClass=getmetatable(page),paneClass=getmetatable(pane),visible=page:getIsVisible(),collapsed=page.isCollapsed,pin=page.pin,collapseCounter=page.collapseCounter,
   inventory=pane.inventory,mode=pane.mode,collapsedItems=collapsedItems,
   selected=F.collapsedStacks and saveUISelection(pane)or nil,
   firstSelect=F.collapsedStacks and captureUIAnchor(pane,pane.firstSelect)or nil,
   joyselection=F.collapsedStacks and captureUIAnchor(pane,pane.joyselection and pane.joyselection+1)or nil,
   equippedCollapsed=pane.equippedCollapsed,doController=pane.doController,mouseOverOption=pane.mouseOverOption,paneVisible=pane:getIsVisible(),maxDrawHeight=page:getMaxDrawHeight(),paneMaxDrawHeight=pane:getMaxDrawHeight(),
   x=page:getX(),y=page:getY(),width=page:getWidth(),height=page:getHeight(),paneX=pane:getX(),paneY=pane:getY(),paneWidth=pane:getWidth(),paneHeight=pane:getHeight(),
   scroll=pane:getYScroll(),smoothScrollY=pane.smoothScrollY,smoothScrollTargetY=pane.smoothScrollTargetY,
   forceSelected=page.forceSelectedContainer,forceTime=page.forceSelectedContainerTime,
   collapseButtonVisible=page.collapseButton and page.collapseButton:getIsVisible(),pinButtonVisible=page.pinButton and page.pinButton:getIsVisible()}
 end
 return saved
end
local function restoreObservers()
 if helperObserver then
  assert(CleanUI_ToolkitFoodAge==helperObserver.namespace and helperObserver.namespace.updateCollapsedStack==helperObserver.wrapper,'public food-age observer replaced')
  helperObserver.namespace.updateCollapsedStack=helperObserver.native;helperObserver=nil
 end
 for i=#observers,1,-1 do local entry=observers[i]
  assert(entry.pane.renderdetails==entry.wrapper,'native renderer observer replaced');entry.pane.renderdetails=entry.raw
 end;observers={}
end
local function geometry(element,saved,prefix)
 prefix=prefix or ''
 local function key(name)return prefix==''and name or prefix..string.upper(string.sub(name,1,1))..string.sub(name,2)end
 element:setWidth(saved[key('width')]);element:setHeight(saved[key('height')])
 element:setX(saved[key('x')]);element:setY(saved[key('y')])
end
local function sameGeometry(element,saved,prefix)
 prefix=prefix or ''
 local function key(name)return prefix==''and name or prefix..string.upper(string.sub(name,1,1))..string.sub(name,2)end
 return element:getX()==saved[key('x')]and element:getY()==saved[key('y')]
  and element:getWidth()==saved[key('width')]and element:getHeight()==saved[key('height')]
end
local function requireUIRestore(condition,message,pages)
 if condition then return end
 local proof={stage='restore-collapsed-ui',error=message,expectedMode=ui.cleanMode,actualMode=CleanUI_isCleanInventoryUIEnabled(),quarantined=true,pages={}}
 for i,page in ipairs(pages or {})do local saved=ui.pages[i];local pane=page.inventoryPane
  proof.pages[i]={expected={x=saved.x,y=saved.y,width=saved.width,height=saved.height,paneX=saved.paneX,paneY=saved.paneY,paneWidth=saved.paneWidth,paneHeight=saved.paneHeight},
   actual={x=page:getX(),y=page:getY(),width=page:getWidth(),height=page:getHeight(),paneX=pane:getX(),paneY=pane:getY(),paneWidth=pane:getWidth(),paneHeight=pane:getHeight()},
   inventoryBound=page.inventory==saved.inventory and pane.inventory==saved.inventory}
 end
 F.emit('DIAGNOSTIC',proof);error(message,0)
end
local function readReturnPosition()
 local player=getPlayer();local square=player:getSquare();local current=player:getCurrentSquare()
 return {x=player:getX(),y=player:getY(),z=player:getZ(),squareX=square and square:getX(),squareY=square and square:getY(),squareZ=square and square:getZ(),
  currentSquareX=current and current:getX(),currentSquareY=current and current:getY(),currentSquareZ=current and current:getZ(),
  moving=player:isPlayerMoving(),hasPath=player:getPath2()~=nil}
end
local function beginPositionReturn()
 assert(position,'original cooling position missing')
 local player=getPlayer();player:teleportTo(position.x,position.y,position.z)
 -- The float teleport overload floors coordinates; retain exact native next/last coordinates.
 player:setForceX(position.x);player:setForceY(position.y);player:setZ(position.z)
 positionReturnAt=getTimestampMs();phase='return-position';since=positionReturnAt
end
local function pollPositionReturn()
 local elapsed=getTimestampMs()-positionReturnAt
 assert(elapsed<10000,'original cooling position did not settle within ten seconds')
 local actual=readReturnPosition()
 if elapsed<100 or math.abs(actual.x-position.x)>.01 or math.abs(actual.y-position.y)>.01 or math.abs(actual.z-position.z)>.01
  or actual.squareX~=position.squareX or actual.squareY~=position.squareY or actual.squareZ~=position.squareZ
  or actual.currentSquareX~=position.squareX or actual.currentSquareY~=position.squareY or actual.currentSquareZ~=position.squareZ
  or actual.moving or actual.hasPath then return end
 return {original=position,actual=actual,elapsedMs=elapsed,deadlineMs=10000,minimumWaitMs=100}
end
local function restoreCollapsedUI()
 requireUIRestore(position==nil,'original position has not settled before native UI restoration',{})
 -- Mode switching recreates pages. Restore only the reacquired active owners.
 CleanUI_setCleanInventoryUIEnabled(ui.cleanMode)
 local pages={getPlayerInventory(0),getPlayerLoot(0)}
 requireUIRestore(CleanUI_isCleanInventoryUIEnabled()==ui.cleanMode,'original inventory UI mode not restored',pages)
 for i,page in ipairs(pages)do local saved=ui.pages[i];local pane=page.inventoryPane
  requireUIRestore(getmetatable(page)==saved.pageClass and getmetatable(pane)==saved.paneClass,'original live UI classes not restored',pages)
  page.forceSelectedContainer=nil;page.forceSelectedContainerTime=nil
  geometry(page,saved)
  if saved.pin then page:setPinned()else page:collapse()end
  page:setVisible(saved.visible);page.isCollapsed=saved.collapsed;page.collapseCounter=saved.collapseCounter;page:setMaxDrawHeight(saved.maxDrawHeight)
  geometry(pane,saved,'pane');pane:setMode(saved.mode);pane:setVisible(saved.paneVisible);pane:setMaxDrawHeight(saved.paneMaxDrawHeight)
  pane.collapsed=copyUIState(saved.collapsedItems);pane.equippedCollapsed=saved.equippedCollapsed
  page:refreshBackpacks();local available={};for _,button in ipairs(page.backpacks or {})do if button.inventory then available[button.inventory]=true end end
  requireUIRestore(available[saved.inventory],'original native UI container unavailable after restore',pages)
  page:setNewContainer(saved.inventory)
  requireUIRestore(page.inventory==saved.inventory and pane==page.inventoryPane and pane.inventory==saved.inventory,'original native UI binding not restored',pages)
 end
 -- Bind both pages before native layout: each page may consult its peer.
 local matched=false
 for attempt=1,4 do
  for _,page in ipairs(pages)do if page.cleanUIApplyScaleSettings then page:cleanUIApplyScaleSettings(true)else page:refreshBackpacks()end end
  matched=true;for i,page in ipairs(pages)do if not sameGeometry(page.inventoryPane,ui.pages[i],'pane')then matched=false end end
  if matched then break end
 end
 requireUIRestore(matched,'native owner layout did not restore original pane geometry',pages)
 for i,page in ipairs(pages)do local saved=ui.pages[i];local pane=page.inventoryPane;local available={}
  for _,button in ipairs(page.backpacks or {})do if button.inventory then available[button.inventory]=true end end
  requireUIRestore(available[saved.inventory]and page.inventory==saved.inventory and pane.inventory==saved.inventory
   and(pane.lastinventory==nil or available[pane.lastinventory]),'native layout changed original container binding',pages)
  restoreUISelection(pane,saved.selected);pane.firstSelect=restoreUIAnchor(pane,saved.firstSelect)
  local joy=restoreUIAnchor(pane,saved.joyselection);pane.joyselection=joy and joy-1 or nil
  pane.doController=saved.doController;pane.mouseOverOption=saved.mouseOverOption
  requireUIRestore(pane.equippedCollapsed==saved.equippedCollapsed,'original equipped-items collapse state not restored',pages)
  pane:setYScroll(saved.scroll);pane.smoothScrollY=saved.smoothScrollY;pane.smoothScrollTargetY=saved.smoothScrollTargetY
  page.forceSelectedContainer=saved.forceSelected;page.forceSelectedContainerTime=saved.forceTime
  if page.collapseButton then page.collapseButton:setVisible(saved.collapseButtonVisible)end
  if page.pinButton then page.pinButton:setVisible(saved.pinButtonVisible)end
  requireUIRestore(page==(i==1 and getPlayerInventory(0)or getPlayerLoot(0))and sameGeometry(page,saved)and sameGeometry(pane,saved,'pane'),
   'original active UI geometry not restored',pages)
  verifyUIAnchor(pane,pane.firstSelect,saved.firstSelect)
  verifyUIAnchor(pane,pane.joyselection and pane.joyselection+1,saved.joyselection)
  requireUIRestore(pane.doController==saved.doController and pane.mouseOverOption==saved.mouseOverOption,'original controller/mouse anchor state not restored',pages)
  requireUIRestore(page.pin==saved.pin and page.isCollapsed==saved.collapsed and page:getIsVisible()==saved.visible and page:getMaxDrawHeight()==saved.maxDrawHeight
   and pane.mode==saved.mode and pane:getYScroll()==saved.scroll and pane:getIsVisible()==saved.paneVisible and pane:getMaxDrawHeight()==saved.paneMaxDrawHeight,
   'original active UI state not restored',pages)
 end
 getCore():setOptionPauseOnFocusloss(ui.focusLoss)
 F.emit('UI_RESTORED',{cleanMode=ui.cleanMode,activePages=true,geometry=true,bindings=true,states=true,selection=true,anchors=true,equipped=true})
end
local function restoreUI()
 if not ui then return end
 -- Restore the unrelated focus-loss setting even when an observer/binding assertion quarantines UI restoration.
 if F.collapsedStacks then getCore():setOptionPauseOnFocusloss(ui.focusLoss)end
 restoreObservers()
 if F.collapsedStacks then restoreCollapsedUI();return end
 for _,saved in ipairs(ui.pages)do
  local page,pane=saved.page,saved.pane
  page:setNewContainer(saved.inventory);page:setX(saved.x);page:setY(saved.y);page:setWidth(saved.width);page:setHeight(saved.height)
  page:setVisible(saved.visible);page.isCollapsed=saved.collapsed;page.pin=saved.pin;page.collapseCounter=saved.collapseCounter;page:setMaxDrawHeight(saved.maxDrawHeight)
  pane:setX(saved.paneX);pane:setY(saved.paneY);pane:setWidth(saved.paneWidth);pane:setHeight(saved.paneHeight)
  pane:setMode(saved.mode);pane:setVisible(saved.paneVisible);pane:setMaxDrawHeight(saved.paneMaxDrawHeight);pane:setYScroll(saved.scroll)
  pane.smoothScrollY=saved.smoothScrollY;pane.smoothScrollTargetY=saved.smoothScrollTargetY
  page.forceSelectedContainer=saved.forceSelected;page.forceSelectedContainerTime=saved.forceTime
  if page.collapseButton then page.collapseButton:setVisible(saved.collapseButtonVisible)end
  if page.pinButton then page.pinButton:setVisible(saved.pinButtonVisible)end
 end
 getCore():setOptionPauseOnFocusloss(ui.focusLoss)
 if position then getPlayer():teleportTo(position.x,position.y,position.z);position=nil end
end
local function endpoint(container)
 if not state then return 'unknown'end
 if container==getPlayer():getInventory()then return 'root'end
 for _,name in ipairs({'fridge','freezer','ambient'})do if container==state[name]then return name end end
 return container and container:getType()or 'none'
end
local function unclipped(element)return element:getMaxDrawHeight()<0 or element:getMaxDrawHeight()>=element:getHeight()end
local function paneState(page)
 local pane=page.inventoryPane;local buttons={}
 for _,button in ipairs(page.backpacks)do buttons[#buttons+1]=endpoint(button.inventory)end
 return {visible=page:getIsVisible(),reallyVisible=page:isReallyVisible(),collapsed=page.isCollapsed,pin=page.pin,maxDrawHeight=page:getMaxDrawHeight(),
  x=page:getX(),y=page:getY(),width=page:getWidth(),height=page:getHeight(),paneVisible=pane:getIsVisible(),paneReallyVisible=pane:isReallyVisible(),
  paneMode=pane.mode,paneMaxDrawHeight=pane:getMaxDrawHeight(),paneHeight=pane:getHeight(),paneWidth=pane:getWidth(),header=pane.headerHgt,
  selectedEndpoint=endpoint(pane.inventory),backpackEndpoints=buttons,publishedRows=#(pane.items or {}),primaryPasses=primaryPasses[pane]or 0,
  observedRows=lastObserved[pane]or {},unclipped=unclipped(page)and unclipped(pane)}
end
local function uiState()
 return {inventory=paneState(ui.inventory),loot=paneState(ui.loot),targetEndpoint=({'fridge','freezer','ambient'})[targetIndex],
  dwellMs=getTimestampMs()-targetAt,rendered=renderProof,ready=readinessProof}
end
local function queueState()
 local q=queue();local entries={}
 for _,action in ipairs(q.queue)do
  local row={type=action.Type,started=action.action and action:isStarted()or false,duration=action.maxTime}
  if action.location then row.target={x=action.location:getX(),y=action.location:getY(),z=action.location:getZ()}end
  entries[#entries+1]=row
 end
 return {size=#q.queue,idle=idle(),currentType=q.current and q.current.Type or 'none',entries=entries,actor=F.actor(getPlayer()),walks=walkNumber}
end
local function pack(...)return {n=select('#',...),...}end
local function groupProof(pane,value,item)
 if not F.collapsedStacks then return end
 assert(type(value)=='table'and value.items,'collapsed qualification needs native group rows')
 local actual=#value.items-1;local indexFound
 for i=2,#value.items do if value.items[i]==item then indexFound=i-1 end end
 return {vanilla=getmetatable(pane)==CleanUI_Vanilla_ISInventoryPane and ISInventoryPane==CleanUI_Vanilla_ISInventoryPane and not CleanUI_isCleanInventoryUIEnabled(),
  collapsed=pane.collapsed[value.name]==true,actualCount=actual,actualIndex=indexFound,
  headerId=value.items[1]:getID(),tailId=item:getID()}
end
local function observeHelper()
 if not F.collapsedStacks then return end
 local namespace=assert(CleanUI_ToolkitFoodAge,'reviewed public food-age updater missing')
 assert(type(namespace)=='table'and namespace.protocol==1
  and namespace.enhancedSourceSha256=='f5992aaebc4f629fd6ebb7b049be86a3e0995ea82276b23f22cf921a18bb7cc0'
  and type(namespace.updateCollapsedStack)=='function','public food-age updater protocol/source differs')
 local native=namespace.updateCollapsedStack;local wrapper
 wrapper=function(group,admitted,...)
  local samples={}
  if phase=='observe'and admitted==true then
   for _,name in ipairs({'chilled','frozen'})do
    local item,where=F.find(state,ids.foods[name])
    if item and (where=='fridge'or where=='freezer')and group.items then
     local members=ids.stackMembers[name];local count=#group.items-1;local matched=count==#members
     if matched then for i=1,#members do if group.items[i+1]:getID()~=members[i]then matched=false;break end end end
     if matched then samples[name]={item=item,before=item:getLastAged(),intervalBefore=tonumber(group._cleanUILastFoodAgeUpdateMs)or 0,count=count,endpoint=where,headerId=group.items[1]:getID()}end
    end
   end
  end
  local result=pack(pcall(native,group,admitted,...))
  if not result[1]then error(result[2],0)end
  for name,sample in pairs(samples)do
   local after=sample.item:getLastAged()
   local intervalAfter=tonumber(group._cleanUILastFoodAgeUpdateMs)or 0
   if intervalAfter~=sample.intervalBefore then
    helperProof[name]={id=sample.item:getID(),endpoint=sample.endpoint,actualCount=sample.count,actualIndex=sample.count,
     headerId=sample.headerId,tailId=sample.item:getID(),admitted=true,delegated=true,protocol=namespace.protocol,
     enhancedSourceSha256=namespace.enhancedSourceSha256,intervalBefore=sample.intervalBefore,intervalAfter=intervalAfter,beforeLastAged=sample.before,afterLastAged=after,world=getGameTime():getWorldAgeHours()}
   end
  end
  return unpack(result,2,result.n)
 end
 namespace.updateCollapsedStack=wrapper;helperObserver={namespace=namespace,native=native,wrapper=wrapper}
end
local function observePage(page)
 local pane=page.inventoryPane;local native=pane.renderdetails;local raw=rawget(pane,'renderdetails');local wrapper
 wrapper=function(self,dragged,...)
  local result=pack(pcall(native,self,dragged,...))
  if not result[1]then observerFailure=observerFailure or tostring(result[2]);error(result[2],0)end
  if dragged==false then
   local ok,problem=pcall(function()
    primaryPasses[self]=(primaryPasses[self]or 0)+1;lastObserved[self]={}
    local selected=endpoint(self.inventory)
    local visible=page:getIsVisible()and page:isReallyVisible()and not page.isCollapsed and page.pin and self:getIsVisible()and self:isReallyVisible()
    local screen=getCore();local inside=page:getX()>=0 and page:getY()>=0 and page:getX()+page:getWidth()<=screen:getScreenWidth()and page:getY()+page:getHeight()<=screen:getScreenHeight()
    local seen={}
    for row,value in ipairs(self.items or {})do
     local values=type(value)=='table'and value.items or {value}
     local first=type(value)=='table'and value.items and (value.cleanUIFirstActualIndex or 2)or 1
     for i=first,#values do local item=values[i]
      if item and instanceof(item,'InventoryItem')then for name,id in pairs(ids.foods)do if item:getID()==id and not seen[id]then
       seen[id]=true;local actual,where=F.find(state,id);assert(actual==item,'rendered food identity differs')
       local top=self.headerHgt+(row-1)*self.itemHgt+self:getYScroll();local bottom=top+self.itemHgt
       lastObserved[self][#lastObserved[self]+1]={id=id,endpoint=where,selectedEndpoint=selected,rowTop=top,rowBottom=bottom,header=self.headerHgt,height=self:getHeight()}
       if visible and inside and unclipped(page)and unclipped(self)and selected==where and bottom>self.headerHgt and top<self:getHeight()-1 then
        local previous=renderProof[name]
        local proof={id=id,endpoint=where,passes=(previous and previous.passes or 0)+1,rowTop=top,rowBottom=bottom,header=self.headerHgt,height=self:getHeight(),
         pageVisible=true,paneVisible=true,primary=true,pinned=true,unclipped=true,selected=true,screenBounds=true,world=getGameTime():getWorldAgeHours(),stack=groupProof(self,value,item)}
        if phase=='observe'then renderProof[name]=proof end
        readinessProof[name]=proof
       elseif where=='root'and selected=='root'and phase=='observe'and index==2 then
        desiredScroll[self]=-math.max(0,row-2)*self.itemHgt
       end
      end end end
     end
    end
   end)
   if not ok then observerFailure=observerFailure or tostring(problem)end
  end
  return unpack(result,2,result.n)
 end
 pane.renderdetails=wrapper;observers[#observers+1]={pane=pane,raw=raw,wrapper=wrapper}
end
local function prepareUI()
 observeHelper()
 local width=math.min(440,math.floor((getCore():getScreenWidth()-60)/2));local height=math.min(420,getCore():getScreenHeight()-130)
 assert(width>=200 and height>=150,'native inventory viewport too small')
 for i,page in ipairs({ui.inventory,ui.loot})do
  page:setX(i==1 and 20 or getCore():getScreenWidth()-width-20);page:setY(90);page:setWidth(width);page:setHeight(height)
  page:setPinned();page:setVisible(true);page.isCollapsed=false;page:clearMaxDrawHeight()
  page.inventoryPane:setVisible(true);page.inventoryPane:clearMaxDrawHeight();page.inventoryPane:setMode('details')
  page.inventoryPane.smoothScrollY=nil;page.inventoryPane.smoothScrollTargetY=nil;page.inventoryPane:setYScroll(0)
  observePage(page)
 end
 ui.inventory:setNewContainer(getPlayer():getInventory());targetAt=getTimestampMs();targetIndex=1
end
local function collapseOwnedGroups(pane)
 if not F.collapsedStacks then return end
 for _,group in ipairs(pane.itemslist or {})do
  for _,item in ipairs(group.items or {})do
   for _,id in pairs(ids.foods)do if item:getID()==id then pane.collapsed[group.name]=true end end
  end
 end
end
local function renderContainers()
 if not state or phase=='cleanup'then return end
 local target=({'fridge','freezer','ambient'})[targetIndex];local page=ui.loot;local pane=page.inventoryPane
 for _,current in ipairs({ui.inventory,page})do
  current:setVisible(true);current.isCollapsed=false;current:clearMaxDrawHeight();current.inventoryPane:setVisible(true);current.inventoryPane:clearMaxDrawHeight()
  local currentPane=current.inventoryPane;collapseOwnedGroups(currentPane)
  if desiredScroll[currentPane]then
   currentPane.smoothScrollY=nil;currentPane.smoothScrollTargetY=nil;currentPane:setYScroll(desiredScroll[currentPane]);desiredScroll[currentPane]=nil
  end
 end
 -- Selection is native and requires actual discovery of the target button.
 if pane.inventory~=state[target]then
  page:refreshBackpacks();page:selectButtonForContainer(state[target]);page:setForceSelectedContainer(state[target],4000)
  pane:refreshContainer()
 else page:setForceSelectedContainer(state[target],4000)end
 collapseOwnedGroups(pane)
 local proved=false;local expected=0
 for name,id in pairs(ids.foods)do local _,where=F.find(state,id)
  if where==target then expected=expected+1;local proof=readinessProof[name];proved=proof and proof.endpoint==target and proof.world>=getGameTime():getWorldAgeHours()-.25 or false end
 end
 if pane.inventory==state[target]and getTimestampMs()-targetAt>=3000 and (expected==0 or proved)then
  targetIndex=targetIndex%3+1;targetAt=getTimestampMs()
 elseif getTimestampMs()-targetAt>20000 then error('native selected container did not render owned food: '..target)end
end
local function allRendered(proofs)
 for name,id in pairs(ids.foods)do local _,where=F.find(state,id);local proof=proofs[name]
  if not proof or proof.id~=id or proof.endpoint~=where or proof.passes<1 then return false end
 end;return true
end
local function diagnostic(force)
 if not state or not ui or phase=='cleanup'then return end
 if not force and getTimestampMs()-lastDiagnostic<5000 then return end;lastDiagnostic=getTimestampMs()
 local row=F.failureSnapshot(state,{phase=phase,index=index,elapsedMs=getTimestampMs()-since});local ok,value=pcall(uiState)
 if ok then row.ui=value else row.uiError=tostring(value)end;row.queue=queueState();row.authorityReadiness=replies.Readyd;F.emit('DIAGNOSTIC',row)
end
local function atOrigin()
 local square=getPlayer():getSquare();local origin=ids.origin
 return square:getX()==origin.x and square:getY()==origin.y and square:getZ()==origin.z
end
local function nativeReturn()
 if walk then
  if queue().current==walk.action and walk.action.action and walk.action:isStarted()then walk.started=true end
  assert(getTimestampMs()-walk.since<15000,'native return to observation origin timed out')
  if not idle()then return false end
  assert(walk.started and walk.action.result==BehaviorResult.Succeeded and atOrigin(),'native return path failed or did not arrive')
  F.emit('WALK',{index=index,event='completed',number=walkNumber,type=walk.action.Type,duration=walk.action.maxTime,
   started=walk.started,completed=true,origin=ids.origin,actor=F.actor(getPlayer()),queue=queueState(),world=getGameTime():getWorldAgeHours()})
  walk=nil;targetAt=getTimestampMs()
 end
 if not atOrigin()then
  if not idle()then return false end
  local origin=ids.origin;local square=assert(getCell():getGridSquare(origin.x,origin.y,origin.z))
  assert(square:canStand()and square:isFree(false),'observation origin is no longer walkable')
  local action=ISWalkToTimedAction:new(getPlayer(),square)
  assert(action.maxTime==-1,'native walking duration must remain path-based')
  walkNumber=walkNumber+1;walk={action=action,since=getTimestampMs(),started=false}
  F.emit('WALK',{index=index,event='dispatched',number=walkNumber,type=action.Type,duration=action.maxTime,
   started=false,completed=false,origin=origin,actor=F.actor(getPlayer()),queue=queueState(),world=getGameTime():getWorldAgeHours()})
  ISTimedActionQueue.add(action);return false
 end
 return idle()and F.originStatus(state,idle()).ready
end
local function startSettling(continuation,purpose)
 phase='settle';settleThen=continuation;settlePurpose=purpose or 'before-begin';settleSequence=settleSequence+1
 originRequestAt=nil;replies.Origind=nil;since=getTimestampMs();targetAt=since
 phaseReadyRequestAt=nil;replies.Readyd=nil
end
local function enqueue(action,source,destination,itemId)
 assert(idle(),'cooling command needs empty native queue')
 assert(not getPlayer():isTimedActionInstant(),'instant native cooling action forbidden')
 local transfer=action.Type=='ISInventoryTransferAction'
 assert(transfer and (action.maxTime>1 or isClient()and action.maxTime==-1)
  or not transfer and action.maxTime==action:getDuration()and action.maxTime>1,'native cooling action duration changed')
 local record={index=index,type=action.Type,itemId=itemId or 0,source=source,destination=destination,duration=action.maxTime,
  initialDuration=action.maxTime,durationSource=transfer and isClient()and 'native-transaction'or 'native-constructor',nativeDuration=true,
  started=false,completed=false,before=F.snapshot(state)}
 command={action=action,record=record};actions[#actions+1]=record
 -- Ordinary game pathfinding precedes admission; no teleport or physical input.
 local square=action.generator and action.generator:getSquare()or source=='fridge'and state.appliance:getSquare()or destination=='fridge'and state.appliance:getSquare()
 assert(luautils.walkAdj(getPlayer(),square),'no native adjacent path to cooling endpoint')
 ISTimedActionQueue.add(action);phase='command';since=getTimestampMs()
end
local function beginPhase()
 request('Begin',{index=index});phase='begin';since=getTimestampMs()
end
local function nextStep()
 if index==0 then
  if not state.generator:isConnected()then enqueue(ISPlugGenerator:new(getPlayer(),state.generator,true),'generator','generator')
  elseif not state.generator:isActivated()then enqueue(ISActivateGenerator:new(getPlayer(),state.generator,true),'generator','generator')
  else index=1;startSettling('begin')end
 elseif index==2 then
  local item=assert(F.find(state,ids.foods.chilled));assert(item:getContainer()==state.fridge and item:getHeat()<=.35,'transfer requires naturally chilled food')
  enqueue(ISInventoryTransferAction:new(getPlayer(),item,state.fridge,getPlayer():getInventory()),'fridge','root',item:getID())
 elseif index==3 then
  local item=assert(F.find(state,ids.foods.chilled));assert(item:getContainer()==getPlayer():getInventory(),'return requires root food')
  enqueue(ISInventoryTransferAction:new(getPlayer(),item,getPlayer():getInventory(),state.fridge),'root','fridge',item:getID())
 elseif index==4 then enqueue(ISActivateGenerator:new(getPlayer(),state.generator,false),'generator','generator')end
end
local function effectSettled()
 local record=command.record
 if record.type=='ISPlugGenerator'then return state.generator:isConnected()end
 if record.type=='ISActivateGenerator'then
  local active=index==0
  return state.generator:isActivated()==active and state.fridge:isPowered()==active and state.freezer:isPowered()==active
 end
 local item,endpoint=F.find(state,record.itemId);return item and endpoint==record.destination
end
local function emitSetup()
 if not isClient()then return end
 F.emit('SETUP',{ids=ids,original=original,controls=F.controls,minutesPerDay=5,snapshot=F.snapshot(state),
  limits={physicalInput=false,observationAgeWrites=0,forcedAgeUpdates=0,nativeDurations=true,nativeInventoryRendering=true,stackFoodProcessing=F.collapsedStacks and 'active-cookable'or nil,
   rootTransfer=F.collapsedStacks and 'singleton'or nil}})
end
local function readyToEnd(after)
 if not allRendered(renderProof)then return false end
 if F.collapsedStacks then
  for _,name in ipairs({'chilled','frozen','control'})do
   local proof=renderProof[name];local stack=proof.stack
   local expected=name=='chilled'and(index==2 and 1 or 199)or name=='frozen'and 200 or 1
   if not stack or not stack.vanilla or not stack.collapsed or stack.actualCount~=expected or stack.actualIndex~=expected
    or stack.tailId~=ids.foods[name]or(expected>1 and stack.headerId==stack.tailId)then return false end
  end
  for _,name in ipairs(index==2 and {'frozen'}or {'chilled','frozen'})do
   if not helperProof[name]then return false end
  end
 end
 return F.readiness(before,after,index)
end
local function tick()
 if observationStarted then assert(getTimestampMs()-observationStarted<180000,'overall food observation deadline '..index)end
 if state and ui and phase~='cleanup'and phase~='return-position'then
  F.originStatus(state,idle())
  if phase=='observe'and (not atOrigin()or not idle()or getPlayer():isPlayerMoving()or getPlayer():getPath2()~=nil)then
   startSettling('observe','observation-recovery')
  end
  if not walk and atOrigin()then renderContainers()else targetAt=getTimestampMs()end
  diagnostic(false)
 end
 assert(not observerFailure,observerFailure)
 assert(not replies.Failed,replies.Failed and replies.Failed.error)
 assert(getTimestampMs()-since<180000,'food cooling stage deadline '..phase)
 if phase=='prepare'then
  assert((F.case=='appliances'or F.collapsedStacks)and #config.cases==1,'food cooling case selection differs')
  assert(idle(),'preexisting timed action queue')
  if not settledUIBaseline()then return end
  ui=saveUI();initial=F.originalItems(getPlayer())
  if F.collapsedStacks then
   CleanUI_setCleanInventoryUIEnabled(false)
   assert(ISInventoryPane==CleanUI_Vanilla_ISInventoryPane and not CleanUI_isCleanInventoryUIEnabled(),'vanilla inventory mode required')
  end
  ui.inventory=getPlayerInventory(0);ui.loot=getPlayerLoot(0)
  if isClient()then original=F.configure()end
  local player=getPlayer();local square=assert(player:getSquare());position={x=player:getX(),y=player:getY(),z=player:getZ(),squareX=square:getX(),squareY=square:getY(),squareZ=square:getZ()};local origin=F.chooseOrigin(player)
  spawn={x=origin:getX(),y=origin:getY(),z=origin:getZ()}
  if player:getSquare()~=origin then player:teleportTo(spawn.x+.5,spawn.y+.5,spawn.z)end
  placeTime=getTimestampMs();phase='position';since=placeTime
 elseif phase=='position'then
  local square=getPlayer():getSquare()
  if square:getX()~=spawn.x or square:getY()~=spawn.y or square:getZ()~=spawn.z or getTimestampMs()-placeTime<1500 then return end
  request('Prepare');prepareAt=getTimestampMs();phase='prepared'
 elseif phase=='prepared'and replies.Prepared then
  if replies.Prepared.waiting then
   if getTimestampMs()-prepareAt>=1000 then replies.Prepared=nil;request('Prepare');prepareAt=getTimestampMs()end
   return
  end
  ids=replies.Prepared;state=F.resolve(getPlayer(),ids);if not state then return end
  if not isClient()then original=authority.original end
  state.original=original
  assert(state.fridge:isFridge()and state.freezer:isFreezer()and state.fridge:getCustomTemperature()==0 and state.freezer:getCustomTemperature()==0,'real unmodified refrigeration containers required')
  emitSetup();prepareUI();phase='ui-ready';since=getTimestampMs()
 elseif phase=='ui-ready'then
  if not allRendered(readinessProof)then return end
  F.emit('READY',{ui=uiState(),snapshot=F.snapshot(state)});nextStep()
 elseif phase=='command'then
  if queue().current==command.action and command.action.action and command.action:isStarted()and command.action:getJobDelta()>0 then
   command.record.started=true
   if command.action.maxTime>1 then command.record.duration=command.action.maxTime end
  end
  if not idle()or not effectSettled()then return end
  assert(command.record.started,'native cooling action never observed running')
  command.record.completed=true;command.record.after=F.snapshot(state);F.emit('COMMAND',command.record)
  command=nil
  if index==0 then nextStep()else startSettling('begin')end
 elseif phase=='settle'then
  assert(getTimestampMs()-since<30000,'native observation-origin settling timed out')
  if not nativeReturn()then return end
  if not replies.Origind or not replies.Origind.ready then
   if not originRequestAt or getTimestampMs()-originRequestAt>=1000 then
    request('Origin',{index=index,sequence=settleSequence,purpose=settlePurpose});originRequestAt=getTimestampMs()
   end
   return
  end
  assert(replies.Origind.index==index and replies.Origind.sequence==settleSequence,'origin authority receipt differs')
  F.emit('SETTLED',{index=index,sequence=settleSequence,purpose=settlePurpose,origin=ids.origin,
   actor=F.actor(getPlayer()),stableMs=F.originStatus(state,idle()).stableMs,queue=queueState(),authority=replies.Origind,ready=true})
  if settleThen=='begin'then beginPhase()else phase='observe';targetAt=getTimestampMs()end
 elseif phase=='begin'and replies.Begind then
  ack=replies.Begind;replies.Begind=nil;assert(ack.index==index and ack.name==F.names[index],'phase authority differs')
  before=F.snapshot(state);renderProof={};helperProof={};phase='observe';since=getTimestampMs();observationStarted=since
  phaseReadyRequestAt=nil;replies.Readyd=nil
  if isClient()then F.emit('BEGIN',{index=index,name=F.names[index],snapshot=before})end
 elseif phase=='observe'then
  local after=F.snapshot(state)
  if not readyToEnd(after)then return end
  if isClient()then
   local readiness=replies.Readyd
   if not readiness or readiness.index~=index or readiness.sequence~=settleSequence or not readiness.ready then
    if not phaseReadyRequestAt or getTimestampMs()-phaseReadyRequestAt>=500 then
     request('Ready',{index=index,sequence=settleSequence});phaseReadyRequestAt=getTimestampMs()
    end
    return
   end
   F.emit('PHASE_READY',{index=index,sequence=settleSequence,ready=true,authority=readiness})
  end
  F.emit('RENDERED',{index=index,foods=renderProof,helper=F.collapsedStacks and helperProof or nil})
  if isClient()then F.emit('PHASE',{index=index,name=F.names[index],before=before,after=after,elapsedWorldHours=after.world-before.world})end
  request('End',{index=index});phase='end';since=getTimestampMs()
 elseif phase=='end'and replies.Endd then
  assert(replies.Endd.index==index,'phase end authority differs');replies.Endd=nil
  if index==4 then
   assert(idle());observationStarted=nil
   if F.collapsedStacks then beginPositionReturn();return end
   restoreUI();request('Cleanup');phase='cleanup'
  else index=index+1;observationStarted=nil;nextStep()end
  since=getTimestampMs()
 elseif phase=='return-position'then
  local proof=pollPositionReturn();if not proof then return end
  F.emit('POSITION_RESTORED',proof);position=nil
  restoreUI();request('Cleanup');phase='cleanup';since=getTimestampMs()
 elseif phase=='cleanup'and replies.Cleanupd then
  if not F.absent(ids)then return end
  if isClient()then
   local prior=getGameTime():getMinutesPerDay();local sandboxBefore=F.options();F.restore(original)
   F.cleanupReceipt(getPlayer(),ids,original,initial,3,prior,sandboxBefore)
  end
  JSON.emit({suite='food-cooling',kind=config.kind,mode=config.mode,actor='client1',event='case',id=F.case,status='passed',phases=4,nativeDurations=true,commands=#actions})
  JSON.emit({suite='food-cooling',kind=config.kind,mode=config.mode,actor='client1',event='complete',cases=config.cases,expected=1,performed=1,failed=0,skipped=0})
  done=true
 end
end
Events.OnGameStart.Add(function()started=true;since=getTimestampMs()end)
Events.OnTick.Add(function()
 if not started or done or not isIngameState()or not getPlayer()or(not getPlayer():getSquare()and phase~='return-position')then return end
 if isClient()and getPlayer():getOnlineID()<0 then return end
 local ok,problem=pcall(tick)
 if not ok then
  local failure={phase=phase,index=index,error=tostring(problem)}
  if state then F.failureSnapshot(state,failure)end
  if state then local captured,value=pcall(queueState);if captured then failure.queue=value else failure.queueError=tostring(value)end end
  if ui then local observed,value=pcall(uiState);if observed then failure.ui=value else failure.uiError=tostring(value)end end
  local restored,restoreError=pcall(function()
   if isClient()then
    if ids then sendClientCommand(F.module,'Abort',{case=F.case,token=ids.token})end
    if original then F.restore(original)end
   else F.abort(authority or F.preparing)end
  end)
  local uiRestored,uiRestoreError=pcall(restoreUI)
  failure.restored=restored and uiRestored;failure.restoreError=tostring(restoreError);failure.uiRestored=uiRestored;failure.uiRestoreError=tostring(uiRestoreError)
  if F.collapsedStacks and ui then failure.focusRestored=getCore():getOptionPauseOnFocusloss()==ui.focusLoss;failure.quarantined=not uiRestored end
  F.emit('FAIL',failure)
  print('[QUEUE_TEST] FAIL food cooling client '..tostring(problem));done=true
 end
end)
