-- Common menu-Host startup owns launch; this fixture observes installed native UI/actions.
require 'TimedActions/ISInventoryTransferAction'
require 'TimedActions/ISInventoryTransferUtil'
local config=require 'QueueTestSelection'
local F=require 'QueueSmartDepositHostFixture'
local Proximity=require 'BetterContainers/Proximity'
local BCOptions=require 'BetterContainers/_Options'
local Category=require 'BetterContainers/Categorize/InventoryCategory'
local started,done,stage,index=false,false,'baseline',1
local began,stageAt,lastRequest,baseline,ui,initial,initialEquipment,initialIdentity,position,spawn,ids,state,current
local sourcePane,loot,pane,target,button,samples,expected,order,partialPreview,fullPreview,fullBefore
local phaseProperties,phaseInitialEndpoints,lastTransferDiagnostic
local modeLifecycle,lastModeDiagnostic
local holdDrag,ownsDrag,addObserver,observerFailure=false,false,nil,nil
local actions,actionSet,observers,allOwned,replies={},{},{},{},{}
local failing,failure,returnAt,positionProof,prepareSent,abortSent,motionProbe,positionTransition
local optionNames={'enableProximity','enableCorpseOnly','enableDualMode','enableNestedContainers_Loot','enableAutoLock'}
local function now()return getTimestampMs()end
local function pack(...)return {n=select('#',...),...}end
local function shallow(value)local result={};for key,item in pairs(value or {})do result[key]=item end;return result end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function idle()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function transition(value)stage=value;stageAt=now();lastRequest=nil end
local function emit(event,row)
 row=row or {};row.index=row.index or index;row.paneMode=row.paneMode or F.modes[index]
 F.emit(event,row)
end
local function request(name,args)
 args=args or {};args.case='partial';args.token=ids and ids.token;args.index=index
 if name=='Prepare'then args.spawn=spawn;prepareSent=true end
 sendClientCommand(F.module,name,args);lastRequest=now()
end
Events.OnServerCommand.Add(function(module,name,value)if module==F.module then replies[name]=value end end)
local function arrayIds(values)
 local result={};for id in pairs(values)do result[#result+1]=id end;table.sort(result);return result
end
local function equipment()
 local player=getPlayer();local result={worn={},primary=player:getPrimaryHandItem(),secondary=player:getSecondaryHandItem()}
 local worn=player:getWornItems()
 for i=0,worn:size()-1 do local entry=worn:get(i);result.worn[#result.worn+1]={location=entry:getLocation(),item=entry:getItem()}end
 return result
end
local function originalProof()
 local actual=F.originalItems(getPlayer());local expectedIds=arrayIds(initial);local actualIds=arrayIds(actual)
 assert(#actualIds==#expectedIds,'original root cardinality changed')
 for id,item in pairs(initial)do assert(actual[id]==item,'original root item identity changed')end
 local worn=equipment();assert(worn.primary==initialEquipment.primary and worn.secondary==initialEquipment.secondary,'original hand items changed')
 assert(#worn.worn==#initialEquipment.worn,'original worn cardinality changed')
 local proof={rootIds=actualIds,worn={},primaryHandId=worn.primary and worn.primary:getID()or 0,secondaryHandId=worn.secondary and worn.secondary:getID()or 0}
 for i,entry in ipairs(worn.worn)do local saved=initialEquipment.worn[i]
  assert(entry.location==saved.location and entry.item==saved.item,'original worn item/location changed')
  -- B42 body locations are native registry objects; retain identity above and
  -- serialize their stable resource names rather than exposing game userdata.
  proof.worn[i]={location=tostring(entry.location),id=entry.item:getID()}
 end
 return proof
end
local function nativeRows(q)
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
 local native=q:saveSelection({});local result={_cleanUISelectedGroups=shallow(native._cleanUISelectedGroups)};local aliases={}
 for _,row in ipairs(nativeRows(q))do if row.group and row.item then aliases[row.item]=row.name end end
 for item,kind in pairs(native)do if item~='_cleanUISelectedGroups'then
  assert(kind=='item'or kind=='group','unknown native selection marker')
  if kind=='group'then result._cleanUISelectedGroups[assert(aliases[item],'selected header has no group identity')]=true else result[item]=kind end
 end end
 for i,row in ipairs(nativeRows(q))do if row.group and q.selected[i]then result._cleanUISelectedGroups[assert(row.name)]=true end end
 for item,name in pairs(aliases)do if result._cleanUISelectedGroups[name]then result[item]=nil end end
 return result
end
local function restoreSelection(q,saved)
 local input=shallow(saved);input._cleanUISelectedGroups=shallow(saved._cleanUISelectedGroups)
 for _,row in ipairs(nativeRows(q))do if row.group and row.item and input._cleanUISelectedGroups[row.name]then input[row.item]='group'end end
 q.selected={};q:restoreSelection(input);local actual=saveSelection(q)
 for item,kind in pairs(saved)do if item~='_cleanUISelectedGroups'then assert(actual[item]==kind,'native item selection lost')end end
 for item in pairs(actual)do if item~='_cleanUISelectedGroups'then assert(saved[item],'foreign native selection')end end
 for name in pairs(saved._cleanUISelectedGroups)do assert(actual._cleanUISelectedGroups[name],'native group selection lost')end
 for name in pairs(actual._cleanUISelectedGroups)do assert(saved._cleanUISelectedGroups[name],'foreign native group selection')end
end
local function anchor(q,row)return {index=row,row=row and nativeRows(q)[row]or nil}end
local function restoreAnchor(q,saved)
 if not saved.row then return saved.index end
 for i,row in ipairs(nativeRows(q))do if row.group==saved.row.group and(row.group and row.name==saved.row.name or not row.group and row.item==saved.row.item)then return i end end
 error('native selection anchor lost')
end
local function geometry(element,value,prefix)
 prefix=prefix or '';local function key(name)return prefix==''and name or prefix..string.upper(string.sub(name,1,1))..string.sub(name,2)end
 -- Native top-level position setters clamp against the current dimensions.
 element:setWidth(value[key('width')]);element:setHeight(value[key('height')]);element:setX(value[key('x')]);element:setY(value[key('y')])
end
local function sameGeometry(element,value,prefix)
 prefix=prefix or '';local function key(name)return prefix==''and name or prefix..string.upper(string.sub(name,1,1))..string.sub(name,2)end
 return element:getX()==value[key('x')]and element:getY()==value[key('y')]and element:getWidth()==value[key('width')]and element:getHeight()==value[key('height')]
end
local function layoutProof(page,q)
 return {owner={x=page:getX(),y=page:getY(),width=page:getWidth(),height=page:getHeight(),visible=page:getIsVisible(),pin=page.pin,collapsed=page.isCollapsed,maxDrawHeight=page:getMaxDrawHeight()},
  pane={x=q:getX(),y=q:getY(),width=q:getWidth(),height=q:getHeight(),visible=q:getIsVisible(),mode=q.mode,scroll=q:getYScroll(),maxDrawHeight=q:getMaxDrawHeight(),equippedCollapsed=q.equippedCollapsed}}
end
local function ownerLayout(page)if page.cleanUIApplyScaleSettings then page:cleanUIApplyScaleSettings(true)else page:refreshBackpacks()end end
local function settledBaseline()
 baseline=baseline or {at=now(),samples=0,times={}}
 assert(now()-baseline.at<10000,'initial native UI layout did not settle within ten seconds')
 if baseline.last and now()-baseline.last<120 then return end;baseline.last=now()
 local pages={getPlayerInventory(0),getPlayerLoot(0)};if not pages[1]or not pages[2]then return end
 for _,page in ipairs(pages)do ownerLayout(page)end
 local values={}
 for i,page in ipairs(pages)do local q=page.inventoryPane
  if not q or q.inventory~=page.inventory or not q.inventory then return end
  values[i]={page=page,pane=q,inventory=q.inventory,x=page:getX(),y=page:getY(),width=page:getWidth(),height=page:getHeight(),
   paneX=q:getX(),paneY=q:getY(),paneWidth=q:getWidth(),paneHeight=q:getHeight()}
  local v=values[i]
  if v.width<=0 or v.height<=0 or v.paneWidth<=0 or v.paneHeight<=0 or v.paneX<0 or v.paneY<0 or v.paneX+v.paneWidth>v.width+.01 or v.paneY+v.paneHeight>v.height+.01 then return end
 end
 local same=baseline.previous~=nil
 if same then for i,value in ipairs(values)do for key,item in pairs(value)do if baseline.previous[i][key]~=item then same=false end end end end
 if same then baseline.samples=baseline.samples+1 else baseline.samples=1;baseline.times={}end
 baseline.previous=values;baseline.times[#baseline.times+1]=now();if baseline.samples<3 then return end
 return {samples=baseline.samples,intervalMs=120,stableSpanMs=baseline.times[#baseline.times]-baseline.times[#baseline.times-2],elapsedMs=now()-baseline.at}
end
local function saveUI(proof)
 local player=getPlayer();local saved={pages={},cleanMode=CleanUI_isCleanInventoryUIEnabled(),baseline=proof,options={},
  god=player:isGodMod(),ghost=player:isGhostMode(),autoDrink=player:getAutoDrink(),coreAutoDrink=getCore():getOptionAutoDrink(),focusLoss=getCore():getOptionPauseOnFocusloss()}
 for _,name in ipairs(optionNames)do saved.options[name]=BCOptions[name]end
 for _,page in ipairs({getPlayerInventory(0),getPlayerLoot(0)})do local q=page.inventoryPane
  saved.pages[#saved.pages+1]={pageClass=getmetatable(page),paneClass=getmetatable(q),inventory=q.inventory,visible=page:getIsVisible(),collapsed=page.isCollapsed,pin=page.pin,collapseCounter=page.collapseCounter,
   x=page:getX(),y=page:getY(),width=page:getWidth(),height=page:getHeight(),maxDrawHeight=page:getMaxDrawHeight(),paneX=q:getX(),paneY=q:getY(),paneWidth=q:getWidth(),paneHeight=q:getHeight(),
   paneVisible=q:getIsVisible(),paneMaxDrawHeight=q:getMaxDrawHeight(),paneMode=q.mode,scroll=q:getYScroll(),smoothScrollY=q.smoothScrollY,smoothScrollTargetY=q.smoothScrollTargetY,
   groups=shallow(q.collapsed),selected=saveSelection(q),equippedCollapsed=q.equippedCollapsed,doController=q.doController,
   firstSelect=anchor(q,q.firstSelect),joyselection=anchor(q,q.joyselection and q.joyselection+1),mouseOverOption=q.mouseOverOption,
   forceSelected=page.forceSelectedContainer,forceTime=page.forceSelectedContainerTime,mouseOverButton=page.mouseOverButton,
   collapseButton=page.collapseButton and page.collapseButton:getIsVisible(),pinButton=page.pinButton and page.pinButton:getIsVisible()}
 end
 for _,entry in ipairs({{name='guide',value=SurvivalGuide and SurvivalGuide.instance},{name='info',value=getPlayerInfoPanel and getPlayerInfoPanel(0)}})do
  if entry.value then saved[entry.name]={page=entry.value,visible=entry.value:getIsVisible()}end
 end
 return saved
end
local function restoreFlags()
 if not ui then return end
 local player=getPlayer();player:setGodMod(ui.god);player:setGhostMode(ui.ghost);player:setAutoDrink(ui.autoDrink)
 getCore():setOptionAutoDrink(ui.coreAutoDrink);getCore():setOptionPauseOnFocusloss(ui.focusLoss)
 for _,name in ipairs(optionNames)do BCOptions[name]=ui.options[name]end
 for _,name in ipairs({'guide','info'})do if ui[name]then ui[name].page:setVisible(ui[name].visible)end end
end
local function restoreUI()
 assert(not position,'original native square must settle before UI restoration')
 for _,name in ipairs(optionNames)do BCOptions[name]=ui.options[name]end
 CleanUI_setCleanInventoryUIEnabled(ui.cleanMode)
 local pages={getPlayerInventory(0),getPlayerLoot(0)};local proof={pages={},options={},flags={},core={},cleanMode={expected=ui.cleanMode,actual=CleanUI_isCleanInventoryUIEnabled()}}
 for i,page in ipairs(pages)do local saved=ui.pages[i];local q=page.inventoryPane
  assert(getmetatable(page)==saved.pageClass and getmetatable(q)==saved.paneClass,'original live UI classes not restored')
  page.forceSelectedContainer=nil;page.forceSelectedContainerTime=nil;geometry(page,saved)
  if saved.pin then page:setPinned()else page:collapse()end
  page:setVisible(saved.visible);page.isCollapsed=saved.collapsed;page.collapseCounter=saved.collapseCounter;page:setMaxDrawHeight(saved.maxDrawHeight)
  geometry(q,saved,'pane');q:setMode(saved.paneMode);q:setVisible(saved.paneVisible);q:setMaxDrawHeight(saved.paneMaxDrawHeight)
  q.collapsed=shallow(saved.groups);q.equippedCollapsed=saved.equippedCollapsed
  page:refreshBackpacks();local available={};for _,entry in ipairs(page.backpacks or {})do if entry.inventory then available[entry.inventory]=true end end
  assert(available[saved.inventory],'original native container unavailable after position return')
  page:setNewContainer(saved.inventory);assert(page.inventory==saved.inventory and q.inventory==saved.inventory,'original live UI binding not restored')
 end
 local matched=false
 for _=1,4 do
  for _,page in ipairs(pages)do ownerLayout(page)end
  matched=true;for i,page in ipairs(pages)do if not sameGeometry(page.inventoryPane,ui.pages[i],'pane')then matched=false end end
  if matched then break end
 end
 assert(matched,'native owner layout did not restore original pane geometry')
 for i,page in ipairs(pages)do local saved=ui.pages[i];local q=page.inventoryPane;local available={}
  for _,entry in ipairs(page.backpacks or {})do if entry.inventory then available[entry.inventory]=true end end
  assert(available[saved.inventory]and page.inventory==saved.inventory and q.inventory==saved.inventory and(q.lastinventory==nil or available[q.lastinventory]),'restored live UI binding/cache changed')
  restoreSelection(q,saved.selected);q.firstSelect=restoreAnchor(q,saved.firstSelect);local joy=restoreAnchor(q,saved.joyselection);q.joyselection=joy and joy-1 or nil
  q.doController=saved.doController;q.mouseOverOption=saved.mouseOverOption;q:setYScroll(saved.scroll);q.smoothScrollY=saved.smoothScrollY;q.smoothScrollTargetY=saved.smoothScrollTargetY
  page.forceSelectedContainer=saved.forceSelected;page.forceSelectedContainerTime=saved.forceTime;page.mouseOverButton=saved.mouseOverButton
  if page.collapseButton then page.collapseButton:setVisible(saved.collapseButton)end;if page.pinButton then page.pinButton:setVisible(saved.pinButton)end
  assert(page==(i==1 and getPlayerInventory(0)or getPlayerLoot(0))and sameGeometry(page,saved)and sameGeometry(q,saved,'pane'),'original active UI geometry changed')
  assert(page.pin==saved.pin and page.isCollapsed==saved.collapsed and page:getIsVisible()==saved.visible and page:getMaxDrawHeight()==saved.maxDrawHeight,'original native page state changed')
  assert(q.mode==saved.paneMode and q:getYScroll()==saved.scroll and q:getIsVisible()==saved.paneVisible and q:getMaxDrawHeight()==saved.paneMaxDrawHeight and q.equippedCollapsed==saved.equippedCollapsed,'original native pane state changed')
  proof.pages[i]={expected={owner={x=saved.x,y=saved.y,width=saved.width,height=saved.height,visible=saved.visible,pin=saved.pin,collapsed=saved.collapsed,maxDrawHeight=saved.maxDrawHeight},
   pane={x=saved.paneX,y=saved.paneY,width=saved.paneWidth,height=saved.paneHeight,visible=saved.paneVisible,mode=saved.paneMode,scroll=saved.scroll,maxDrawHeight=saved.paneMaxDrawHeight,equippedCollapsed=saved.equippedCollapsed}},
   actual=layoutProof(page,q),inventoryBound=page.inventory==saved.inventory and q.inventory==saved.inventory,selectionRestored=true}
 end
 restoreFlags();local player=getPlayer()
 assert(CleanUI_isCleanInventoryUIEnabled()==ui.cleanMode,'original inventory mode changed')
 for _,name in ipairs(optionNames)do assert(BCOptions[name]==ui.options[name],'original Better Containers option changed: '..name)end
 assert(player:isGodMod()==ui.god and player:isGhostMode()==ui.ghost and player:getAutoDrink()==ui.autoDrink,'original player flags changed')
 assert(getCore():getOptionAutoDrink()==ui.coreAutoDrink and getCore():getOptionPauseOnFocusloss()==ui.focusLoss,'original core options changed')
 for _,name in ipairs(optionNames)do proof.options[name]={expected=ui.options[name],actual=BCOptions[name]}end
 proof.flags={expected={god=ui.god,ghost=ui.ghost,autoDrink=ui.autoDrink},actual={god=player:isGodMod(),ghost=player:isGhostMode(),autoDrink=player:getAutoDrink()}}
 proof.core={expected={autoDrink=ui.coreAutoDrink,focusLoss=ui.focusLoss},actual={autoDrink=getCore():getOptionAutoDrink(),focusLoss=getCore():getOptionPauseOnFocusloss()}}
 return proof
end
local function clearDrag()
 if not ownsDrag then return end
 holdDrag=false;ownsDrag=false;ISMouseDrag.dragging=nil;ISMouseDrag.draggingFocus=nil
 if sourcePane then sourcePane.dragging=nil;sourcePane.dragStarted=false;sourcePane.draggedItems:reset()end
 if loot then loot.mouseOverButton=nil end
end
local function drag(items)
 assert(ISMouseDrag.dragging==nil,'unrelated native drag already active')
 ownsDrag=true;ISMouseDrag.dragging=items;ISMouseDrag.draggingFocus=nil;sourcePane.dragging=1;sourcePane.dragStarted=true
 sourcePane.draggingX=sourcePane:getMouseX();sourcePane.draggingY=sourcePane:getMouseY();sourcePane.draggedItems:reset();loot.mouseOverButton=button;holdDrag=true;sourcePane.draggedItems:update()
end
local function endpoint(container)
 if container==getPlayer():getInventory()then return 'root'end
 for slot,store in ipairs(state.stores)do if container==store then return 'crate'..slot end end
 return container and container:getType()or 'none'
end
local function restoreAdd()
 if not addObserver then return end
 assert(ISTimedActionQueue.add==addObserver.wrapper,'native add observer replaced');ISTimedActionQueue.add=addObserver.native;addObserver=nil
end
local function restoreObservers()
 restoreAdd()
 for i=#observers,1,-1 do local entry=observers[i]
  assert(entry.owner[entry.key]==entry.wrapper,'native action observer replaced');entry.owner[entry.key]=entry.raw
 end;observers={}
end
local function sampleAction(record)
 local action=record.action
 record.lastDuration=action.maxTime;record.lastTransactionId=action.transactionId
 if action.transactionId and action.transactionId~=0 then
  record.transactionId=action.transactionId
  -- A short accepted transaction can already be Done when native update runs.
  -- Its authoritative duration remains readable until native perform removes it.
  local duration=getItemTransactionDuration(action.transactionId)
  record.lastTransactionDuration=duration
  if duration>0 then record.transactionDuration=duration;record.duration=duration;record.durationSource='native-transaction-duration'end
 end
 if action.action and action:isStarted()then
  record.started=true;if action:getJobDelta()>0 then record.progressSamples=record.progressSamples+1 end
 end
 if action.maxTime>0 then record.observedMaxTime=action.maxTime end
end
local function observeMethod(action,key,record)
 local native,raw=action[key],nil;if not native then return end
 -- Kahlua rawget follows metatables; only own entries may be restored here.
 for name,value in pairs(action)do if name==key then raw=value;break end end
 local wrapper
 wrapper=function(self,...)
  local observed,problem=pcall(sampleAction,record);if not observed then observerFailure=observerFailure or tostring(problem)end
  local result=pack(pcall(native,self,...))
  if not result[1]then error(result[2],0)end
  if key=='perform'then record.performCalls=record.performCalls+1;record.completed=true
  elseif key=='stop'then record.stopCalls=record.stopCalls+1
  elseif key=='update'then record.updateCalls=record.updateCalls+1 else record.startCalls=record.startCalls+1 end
  observed,problem=pcall(sampleAction,record);if not observed then observerFailure=observerFailure or tostring(problem)end
  return unpack(result,2,result.n)
 end
 action[key]=wrapper;observers[#observers+1]={owner=action,key=key,raw=raw,wrapper=wrapper}
end
local function observeAdds(rejectAll)
 assert(not addObserver,'native add observer already installed');local native=ISTimedActionQueue.add;local wrapper
 wrapper=function(action,...)
  if rejectAll then observerFailure=observerFailure or 'fully rejected native drop queued an action'
  elseif action.Type~='ISInventoryTransferAction'then observerFailure=observerFailure or 'unexpected native action from adjacent deposit drop'
  else
   local item=action.item;local destination=expected[item]
   if not destination or actionSet[item]or action.srcContainer~=getPlayer():getInventory()or action.destContainer~=destination then observerFailure=observerFailure or 'native drop queued rejected/duplicate/wrong-endpoint item'end
   local record={action=action,id=item:getID(),source=endpoint(action.srcContainer),destination=endpoint(action.destContainer),type=action.Type,
    initialDuration=action.maxTime,initialTransactionId=action.transactionId,queueTime=action.queueList and action.queueList[1]and action.queueList[1].time,
    started=false,completed=false,progressSamples=0,startCalls=0,updateCalls=0,performCalls=0,stopCalls=0}
   if action.maxTime~=-1 then observerFailure=observerFailure or 'Host native transfer constructor duration must be -1'end
   actionSet[item]=record;actions[#actions+1]=record
   for _,key in ipairs({'start','update','perform','stop'})do observeMethod(action,key,record)end
  end
  return native(action,...)
 end
 addObserver={native=native,wrapper=wrapper};ISTimedActionQueue.add=wrapper
end
local function configureMode()
 clearDrag();assert(idle(),'previous native transfers did not drain');CleanUI_setCleanInventoryUIEnabled(index==1)
 local inventory=getPlayerInventory(0);sourcePane=inventory.inventoryPane;loot=getPlayerLoot(0);pane=loot.inventoryPane
 local class=index==1 and CleanUI_Clean_ISInventoryPane or CleanUI_Vanilla_ISInventoryPane
 assert(ISInventoryPane==class and getmetatable(sourcePane)==class and getmetatable(pane)==class,'selected native pane class differs')
 local width=math.min(620,math.floor((getCore():getScreenWidth()-70)/2));local height=math.min(760,getCore():getScreenHeight()-100)
 assert(width>=350 and height>=320,'native Smart Deposit viewport too small')
 for i,page in ipairs({inventory,loot})do
  geometry(page,{width=width,height=height,x=i==1 and 25 or getCore():getScreenWidth()-width-25,y=50})
  page:setPinned();page:setVisible(true);page.isCollapsed=false;page:clearMaxDrawHeight();local q=page.inventoryPane
  q:setMode('details');q:setVisible(true);q:clearMaxDrawHeight();q.smoothScrollY=nil;q.smoothScrollTargetY=nil;q:setYScroll(0)
 end
 inventory:setNewContainer(getPlayer():getInventory());target=Proximity.GetItemContainer(0);button=nil;order={}
 modeLifecycle.inventoryPage=inventory;modeLifecycle.lootPage=loot;modeLifecycle.configuredAt=now();modeLifecycle.refreshedAt=nil
end
local function discoverMode()
 -- The native mode switch recreates owners. Reacquire them before discovery,
 -- and let their first UI update finish before one explicit native refresh.
 local inventory=getPlayerInventory(0);loot=getPlayerLoot(0);sourcePane=inventory.inventoryPane;pane=loot.inventoryPane
 local class=index==1 and CleanUI_Clean_ISInventoryPane or CleanUI_Vanilla_ISInventoryPane
 assert(ISInventoryPane==class and getmetatable(sourcePane)==class and getmetatable(pane)==class,'active native pane mode changed during discovery')
 if not modeLifecycle.refreshedAt then
  if now()-modeLifecycle.configuredAt<200 then return false end
  inventory:refreshBackpacks();loot:refreshBackpacks();modeLifecycle.refreshedAt=now();return false
 end
 target=Proximity.GetItemContainer(0);button=nil;order={}
 local known={};for slot,store in ipairs(state.stores)do known[store]=slot end
 local seen={}
 for _,entry in ipairs(loot.backpacks or {})do local container=entry.inventory
  if container==target then button=entry elseif known[container]then
   assert(not seen[container],'duplicate native owned crate button');seen[container]=true;order[#order+1]=known[container]
  elseif container and container:getType()~='floor'then error('unrelated native nearby storage would change deposit admission: '..container:getType())end
 end
 if not button or #order~=3 then return false end
 loot:onBackpackClick(button);assert(pane.inventory==target,'native proximity button not selected')
 return true
end
local function modeDiagnostic()
 local inventory=getPlayerInventory(0);local liveLoot=getPlayerLoot(0);local player=getPlayer();local square=player:getSquare();local currentSquare=player:getCurrentSquare()
 motionProbe=motionProbe or Vector2.new();local motion=player:getDeferredMovement(motionProbe)
 local permissions=BCOptions.getEffectivePermissions()or {};local row={origin=ids.origin,
  actor={x=player:getX(),y=player:getY(),z=player:getZ(),squareX=square and square:getX(),squareY=square and square:getY(),squareZ=square and square:getZ(),
   currentSquareX=currentSquare and currentSquare:getX(),currentSquareY=currentSquare and currentSquare:getY(),currentSquareZ=currentSquare and currentSquare:getZ(),moving=player:isPlayerMoving(),hasPath=player:getPath2()~=nil,
   deferredX=motion:getX(),deferredY=motion:getY(),animationState=player:getAnimationStateName()},
  cleanMode=CleanUI_isCleanInventoryUIEnabled(),inventoryOwnerLive=inventory==modeLifecycle.inventoryPage,lootOwnerLive=liveLoot==modeLifecycle.lootPage,
  inventoryPaneClean=inventory and getmetatable(inventory.inventoryPane)==CleanUI_Clean_ISInventoryPane or false,
  lootPaneClean=liveLoot and getmetatable(liveLoot.inventoryPane)==CleanUI_Clean_ISInventoryPane or false,
  configuredAt=modeLifecycle.configuredAt,refreshedAt=modeLifecycle.refreshedAt,positionProof=modeLifecycle.positionProof,originAuthority=modeLifecycle.authority,
  permissions={proximityActive=permissions.proximityActive,corpseOnly=permissions.corpseOnly,dualMode=permissions.dualMode,autoLock=permissions.autoLock},buttons={},crates={}}
 local known={};for slot,store in ipairs(state.stores)do known[store]=slot end
 for i,entry in ipairs(liveLoot and liveLoot.backpacks or {})do local container=entry.inventory
  row.buttons[#row.buttons+1]={index=i,type=container and container:getType()or 'none',ownedSlot=known[container]or 0,isTarget=container==Proximity.GetItemContainer(0)}
 end
 for slot,object in ipairs(state.crates)do local desc=ids.crates[slot];local tile=getCell():getGridSquare(desc.x,desc.y,desc.z)
  local atIndex=tile and desc.index>=0 and desc.index<tile:getObjects():size()and tile:getObjects():get(desc.index)or nil
  row.crates[#row.crates+1]={slot=slot,descriptor=desc,objectIndex=object:getObjectIndex(),ownerToken=object:getModData().SmartDepositHostOwner,
   objectMatchesDescriptor=atIndex==object,containerMatchesObject=object:getContainer()==state.stores[slot],worldContainerMatches=atIndex and atIndex:getContainer()==state.stores[slot]or false}
 end
 return row
end
local function selectSamples()
 samples={};expected={};phaseProperties={};phaseInitialEndpoints={};local selected={}
 for _,id in ipairs(F.phaseIds(current))do local item,where,count=F.find(state,id)
  assert(item and count==1,'replicated owned item is not unique')
  phaseInitialEndpoints[id]=where
  phaseProperties[id]={id=id,type=item:getFullType(),name=item:getName(),weight=item:getUnequippedWeight()}
 end
 for _,id in ipairs(current.sampleIds)do local item,where,count=F.find(state,id);assert(item and where=='root'and count==1,'replicated sample is not a unique root item');samples[#samples+1]=item end
 sourcePane:sortItemsByTypeAndWeight(samples)
 for i=1,3 do expected[samples[i]]=state.stores[order[4-i]]end
 local stock=assert(F.find(state,current.stockIds[1]));assert(stock:getFullType()~=samples[1]:getFullType()and Category.get(stock)==Category.get(samples[1]),'native Nails/Screws category precondition changed')
 local weight=samples[1]:getUnequippedWeight();assert(weight>0,'native sample has zero weight')
 for _,store in ipairs(state.stores)do assert(store:hasRoomFor(getPlayer(),samples[1])and not store:hasRoomFor(getPlayer(),weight*2,weight*2),'replicated one-item capacity differs')end
 for _,item in ipairs(samples)do selected[item]='item'end
 sourcePane:refreshContainer();sourcePane.selected={}
 for _,group in ipairs(sourcePane.itemslist or {})do for _,item in ipairs(group.items or {})do if selected[item]then sourcePane.collapsed[group.name]=false;break end end end
 sourcePane:refreshContainer();sourcePane:restoreSelection(selected)
 local count=0;for _,item in pairs(sourcePane.selected)do assert(selected[item],'unrelated native row selected');count=count+1 end;assert(count==4,'four physical child rows must be selected')
 local first,last
 for row,value in ipairs(nativeRows(sourcePane))do if not value.group and selected[value.item]then first=first or row;last=row end end
 assert(first and last,'native selected sample rows missing')
 local minimum=math.min(0,sourcePane:getScrollAreaHeight()-sourcePane:getScrollHeight())
 sourcePane:setYScroll(math.max(minimum,-math.max(0,first-2)*sourcePane.itemHgt))
 local bottom=sourcePane.headerHgt+(last-1)*sourcePane.itemHgt+sourcePane:getYScroll()+sourcePane.itemHgt
 assert(bottom<sourcePane:getHeight(),'native sample selection is clipped')
end
local function preview(items,full)
 drag(items);local dragged=sourcePane.draggedItems
 assert(dragged.mouseOverContainer==target,'native dragged items did not discover proximity hover')
 local paneAllowed=pane:canPutIn();local pageAllowed=loot:canPutIn();local cannotAny=dragged:cannotDropAnyItem()
 assert(paneAllowed==not full and pageAllowed==not full and cannotAny==full,'installed native pane/page admission differs')
 local plan=assert(PZSurvivorToolkit.SmartDeposit.plan(sourcePane,items,target));local rows={}
 for _,item in ipairs(items)do local allowed=not full and expected[item]~=nil
  local denied=dragged.itemNotOK[item]==true;local cannot=dragged:cannotDropItem(item)
  assert(denied==not allowed and cannot==not allowed,'installed native per-item preview differs')
  assert(plan.accepted[item]==(allowed and expected[item]or nil),'public plan destination differs from finite native admission')
  rows[#rows+1]={id=item:getID(),allowed=not denied,cannotDrop=cannot,destination=plan.accepted[item]and endpoint(plan.accepted[item])or false}
 end
 return {items=rows,pane=paneAllowed,page=pageAllowed,cannotDropAny=cannotAny,accepted=full and 0 or 3,rejected=full and 4 or 1,
  paneClass=index==1 and 'CleanUI_Clean_ISInventoryPane'or 'CleanUI_Vanilla_ISInventoryPane',snapshot=F.snapshot(state)}
end
local function localEffectReady()
 -- Native transfer packets deserialize new client objects for moved items.
 -- Preserve owned IDs/properties; original unrelated objects remain exact.
 local endpoints=shallow(phaseInitialEndpoints)
 for i,item in ipairs(samples)do endpoints[item:getID()]=i<4 and endpoint(expected[item])or 'root'end
 for id,properties in pairs(phaseProperties)do local actual,where,count=F.find(state,id)
  if not actual or count~=1 or where~=endpoints[id]or actual:getID()~=id or actual:getFullType()~=properties.type
   or actual:getName()~=properties.name or math.abs(actual:getUnequippedWeight()-properties.weight)>.0001 then return false end
 end
 local seen={}
 for slot=0,3 do local container=slot==0 and getPlayer():getInventory()or state.stores[slot];local where=slot==0 and 'root'or 'crate'..slot
  local items=container:getItems()
  for i=0,items:size()-1 do local item=items:get(i);local id=item:getID();local wanted=endpoints[id]or(initial[id]and 'root')
   if wanted~=where or seen[id]or initial[id]and initial[id]~=item then return false end;seen[id]=true
  end
 end
 for id in pairs(initial)do if not seen[id]then return false end end
 return true
end
local function transferDiagnostic()
 local nativeQueue=queue();local row={queueCount=#nativeQueue.queue,hasTimedActions=getPlayer():hasTimedActions(),idle=idle(),queue={},actions={},samples={}}
 for _,action in ipairs(nativeQueue.queue)do
  row.queue[#row.queue+1]={type=action.Type,id=action.item and action.item:getID()or 0,source=endpoint(action.srcContainer),destination=endpoint(action.destContainer),
   maxTime=action.maxTime,transactionId=action.transactionId,current=nativeQueue.current==action,started=action.action and action:isStarted()or false,jobDelta=action.action and action:getJobDelta()or 0}
 end
 for _,record in ipairs(actions)do
  row.actions[#row.actions+1]={id=record.id,type=record.type,source=record.source,destination=record.destination,initialDuration=record.initialDuration,
   maxTime=record.action.maxTime,transactionId=record.transactionId,currentTransactionId=record.action.transactionId,transactionDuration=record.transactionDuration,
   lastTransactionDuration=record.lastTransactionDuration,observedMaxTime=record.observedMaxTime,started=record.started,completed=record.completed,
   startCalls=record.startCalls,updateCalls=record.updateCalls,performCalls=record.performCalls,stopCalls=record.stopCalls,progressSamples=record.progressSamples}
 end
 for i,item in ipairs(samples)do local actual,where,count=F.find(state,item:getID())
  row.samples[#row.samples+1]={id=item:getID(),count=count,endpoint=where or 'absent',expectedEndpoint=i<4 and endpoint(expected[item])or 'root',sameInstance=actual==item,
   type=actual and actual:getFullType()or '',name=actual and actual:getName()or '',weight=actual and actual:getUnequippedWeight()or 0,baseline=phaseProperties[item:getID()]}
 end
 return row
end
local function finishTiming()
 assert(#actions==3,'native drop did not queue exactly three transfers')
 for _,record in ipairs(actions)do
  assert(record.started and record.startCalls==1 and record.updateCalls>=1 and record.completed and record.performCalls==1 and record.stopCalls==0,'native transfer callbacks incomplete')
  assert(record.initialDuration==-1 and record.duration and record.duration>0 and record.transactionId and record.transactionId~=0,'native Host transaction timing not observed')
  emit('TIMING',{id=record.id,type=record.type,source=record.source,destination=record.destination,initialDuration=record.initialDuration,
   initialTransactionId=record.initialTransactionId,transactionId=record.transactionId,duration=record.duration,durationSource=record.durationSource,transactionDuration=record.transactionDuration,
   observedMaxTime=record.observedMaxTime,lastDuration=record.lastDuration,lastTransactionDuration=record.lastTransactionDuration,
   queueTime=record.queueTime,started=record.started,completed=record.completed,progressSamples=record.progressSamples,startCalls=record.startCalls,updateCalls=record.updateCalls,performCalls=record.performCalls,stopCalls=record.stopCalls})
 end
 restoreObservers()
end
local function readPosition()
 local player=getPlayer();local square=player:getSquare();local currentSquare=player:getCurrentSquare()
 motionProbe=motionProbe or Vector2.new();local motion=player:getDeferredMovement(motionProbe)
 return {x=player:getX(),y=player:getY(),z=player:getZ(),squareX=square and square:getX(),squareY=square and square:getY(),squareZ=square and square:getZ(),
  currentSquareX=currentSquare and currentSquare:getX(),currentSquareY=currentSquare and currentSquare:getY(),currentSquareZ=currentSquare and currentSquare:getZ(),moving=player:isPlayerMoving(),hasPath=player:getPath2()~=nil,
  deferredX=motion:getX(),deferredY=motion:getY(),animationState=player:getAnimationStateName()}
end
local function placementReady(value,minimumWaitMs)
 assert(now()-value.began<10000,'native position transition did not settle within ten seconds')
 local actual=readPosition();local quiet=idle()and not actual.moving and not actual.hasPath and actual.deferredX==0 and actual.deferredY==0
 if not value.placedAt then
  -- Native Loot blends translation for 0.40s after its action drains. A
  -- coordinate teleport does not clear this deferred animation movement.
  local previous=value.last
  if not quiet or not value.quietAt or not previous or actual.x~=previous.x or actual.y~=previous.y or actual.z~=previous.z then
   value.quietAt=quiet and now()or nil;value.quietFirst=quiet and actual or nil;value.quietSamples=quiet and 1 or 0
  else value.quietSamples=value.quietSamples+1 end
  value.last=actual
  if not value.quietAt or now()-value.quietAt<500 then return end
  value.quiescence={first=value.quietFirst,last=actual,stableMs=now()-value.quietAt,minimumStableMs=500,samples=value.quietSamples}
  local player=getPlayer();local target=value.target
  player:teleportTo(target.x,target.y,target.z)
  -- Native float teleport floors coordinates; restore next/last positions too.
  player:setForceX(target.x);player:setForceY(target.y);player:setZ(target.z);value.placedAt=now();return
 end
 local target=value.target;local elapsed=now()-value.placedAt
 if elapsed<minimumWaitMs or not quiet or math.abs(actual.x-target.x)>.01 or math.abs(actual.y-target.y)>.01 or math.abs(actual.z-target.z)>.01
  or actual.squareX~=target.squareX or actual.squareY~=target.squareY or actual.squareZ~=target.squareZ
  or actual.currentSquareX~=target.squareX or actual.currentSquareY~=target.squareY or actual.currentSquareZ~=target.squareZ then return end
 return {actual=actual,elapsedMs=elapsed,minimumWaitMs=minimumWaitMs,deadlineMs=10000,lifecycleElapsedMs=now()-value.began,quiescence=value.quiescence}
end
local function returnPosition()
 returnAt=now();positionTransition={began=returnAt,target=shallow(position)};transition('return-position')
end
local function positionReturnReady()
 local proof=placementReady(positionTransition,100);if not proof then return end
 proof.original=shallow(position);return proof
end
local function beginModePosition()
 assert(idle(),'mode placement requires the native queue to drain');clearDrag()
 local origin=ids.origin
 modeLifecycle={index=index,positionBegan=now(),before=readPosition()};lastModeDiagnostic=nil
 modeLifecycle.placement={began=now(),target={x=origin.x+.5,y=origin.y+.5,z=origin.z,squareX=origin.x,squareY=origin.y,squareZ=origin.z}}
 replies.Origind=nil
 transition('mode-position')
end
local function modePositionReady()
 local proof=placementReady(modeLifecycle.placement,1500);if not proof then return false end
 proof.before=modeLifecycle.before;proof.origin=ids.origin;modeLifecycle.positionProof=proof;return true
end
local function setupTick()
 if stage=='baseline'then
  assert(config.kind=='mp'and config.options and config.options.mp_host and #config.cases==1 and config.cases[1]=='partial','Smart Deposit requires selected one-client menu Host')
  assert(isClient()and not isServer(),'Smart Deposit client requires network Host');assert(idle()and not ISMouseDrag.dragging,'preexisting timed work/drag')
  assert(not getPlayer():isTimedActionInstant(),'ordinary native transfer timing required')
  assert(PZSurvivorToolkit and PZSurvivorToolkit.SmartDeposit and PZSurvivorToolkit.SmartDeposit.plan,'installed owned Smart Deposit missing')
  for _,id in ipairs({'ContainerCapacityIndicator','BravoItemDetails','Quartermaster','HasResearch','SeedSeasonIndicator'})do assert(not getActivatedMods():contains(id),'external inventory owner enabled: '..id)end
  local proof=settledBaseline();if not proof then return end
  ui=saveUI(proof);initial=F.originalItems(getPlayer());initialEquipment=equipment();initialIdentity=originalProof();position=readPosition()
  local player=getPlayer();player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false);getCore():setOptionAutoDrink(false);getCore():setOptionPauseOnFocusloss(false)
  for _,name in ipairs({'guide','info'})do if ui[name]then ui[name].page:setVisible(false)end end
  BCOptions.enableProximity=true;BCOptions.enableCorpseOnly=false;BCOptions.enableDualMode=false;BCOptions.enableNestedContainers_Loot=false;BCOptions.enableAutoLock=false
  local origin=F.chooseOrigin(player);spawn={x=origin:getX(),y=origin:getY(),z=origin:getZ()};player:teleportTo(spawn.x+.5,spawn.y+.5,spawn.z);transition('position')
 elseif stage=='position'then
  local actual=readPosition();if now()-stageAt<1500 or actual.squareX~=spawn.x or actual.squareY~=spawn.y or actual.squareZ~=spawn.z or actual.moving or actual.hasPath then return end
  request('Prepare');transition('prepared')
 elseif stage=='prepared'and replies.Prepared then
  if replies.Prepared.waiting then if not lastRequest or now()-lastRequest>=1000 then replies.Prepared=nil;request('Prepare')end;return end
  ids=replies.Prepared;state=F.resolve(getPlayer(),ids);if not state then return end;state.initial=initial;replies.Prepared=nil
  emit('SETUP',{index=0,ids=ids,original=initialIdentity,originalRootIds=arrayIds(initial),uiBaseline=ui.baseline,snapshot=F.snapshot(state),nativeDurations=true});beginModePosition()
 elseif stage=='mode-position'then
  if not modePositionReady()then
   if not lastModeDiagnostic or now()-lastModeDiagnostic>=2000 then emit('DIAGNOSTIC',{stage=stage,actor=readPosition(),placement=modeLifecycle.placement});lastModeDiagnostic=now()end;return
  end
  emit('DIAGNOSTIC',{stage=stage,positionProof=modeLifecycle.positionProof});transition('mode-origin');request('Origin')
 elseif stage=='mode-origin'then
  assert(now()-stageAt<10000,'authority mode origin did not settle within ten seconds')
  if not replies.Origind then return end
  local received=replies.Origind;assert(received.token==ids.token and received.index==index,'authority mode origin identity differs')
  if not received.ready then
   if not lastRequest or now()-lastRequest>=500 then replies.Origind=nil;request('Origin')end;return
  end
  modeLifecycle.authority=received;replies.Origind=nil
  emit('DIAGNOSTIC',{stage=stage,positionProof=modeLifecycle.positionProof,originAuthority=received});transition('mode')
 elseif stage=='mode'then
  configureMode();transition('mode-discovery')
 elseif stage=='mode-discovery'then
  assert(now()-stageAt<10000,'native mode container discovery did not settle within ten seconds')
  if not discoverMode()then
   if not lastModeDiagnostic or now()-lastModeDiagnostic>=2000 then emit('DIAGNOSTIC',{stage=stage,elapsedMs=now()-stageAt,discovery=modeDiagnostic()});lastModeDiagnostic=now()end;return
  end
  emit('DIAGNOSTIC',{stage=stage,elapsedMs=now()-stageAt,discovery=modeDiagnostic()});request('Seed',{order=order});transition('seeded')
 elseif stage=='seeded'and replies.Seeded then
  current=replies.Seeded;if not F.resolvePhase(state,current)then return end;replies.Seeded=nil
  assert(current.index==index and current.mode==F.modes[index],'replicated phase identity differs')
  for i,slot in ipairs(order)do assert(current.order[i]==slot,'authority changed actual native container order')end
  for _,id in ipairs(F.phaseIds(current))do allOwned[#allOwned+1]=id end
  selectSamples();local properties={};for _,id in ipairs(F.phaseIds(current))do properties[#properties+1]=phaseProperties[id]end
  emit('SEED',{phase=current,itemProperties=properties,originAuthority=modeLifecycle.authority,snapshot=F.snapshot(state)});transition('preview')
 end
end
local function transferTick()
 if stage=='preview'then
  partialPreview=preview(samples,false);emit('PREVIEW',partialPreview);transition('shot')
 elseif stage=='shot'then
  if now()-stageAt<300 then return end
  local name='smart-deposit-'..F.modes[index]..'-partial.png';getCore():TakeFullScreenshot(name);emit('SHOT',{name=name});transition('drop')
 elseif stage=='drop'then
  if now()-stageAt<200 then return end;assert(idle(),'native partial drop requires idle queue');actions={};actionSet={};observeAdds(false)
  assert(loot:dropItemsInContainer(button),'installed native container-button partial drop did not dispatch');clearDrag();transition('queued')
 elseif stage=='queued'then
  for _,record in ipairs(actions)do sampleAction(record)end
  if #actions<3 then return end;assert(#actions==3,'native partial drop queued extra transfers');restoreAdd()
  local records={};for _,record in ipairs(actions)do records[#records+1]={id=record.id,type=record.type,source=record.source,destination=record.destination,initialDuration=record.initialDuration,initialTransactionId=record.initialTransactionId,queueTime=record.queueTime}end
  emit('QUEUED',{nativeActions=#actions,rejectedQueued=false,items=records});transition('transferring')
 elseif stage=='transferring'then
  for _,record in ipairs(actions)do sampleAction(record)end
  if not idle()or not localEffectReady()then
   if not lastTransferDiagnostic or now()-lastTransferDiagnostic>=5000 then
    emit('DIAGNOSTIC',{stage=stage,elapsedMs=now()-stageAt,transfer=transferDiagnostic(),snapshot=F.snapshot(state)});lastTransferDiagnostic=now()
   end;return
  end
  finishTiming();local sorted={};for _,item in ipairs(samples)do sorted[#sorted+1]=item:getID()end
  request('Effect',{sampleIds=sorted});transition('effect')
 elseif stage=='effect'and replies.Effected then
  assert(idle()and localEffectReady(),'native effects changed before authority barrier')
  emit('EFFECT',{sampleIds=(function()local out={};for _,item in ipairs(samples)do out[#out+1]=item:getID()end;return out end)(),snapshot=F.snapshot(state),authority=replies.Effected})
  replies.Effected=nil;request('Extras');transition('extras')
 end
end
local function cleanupTick()
 if stage=='extras'and replies.Extrasd then
  current.extraIds=replies.Extrasd.extraIds;if not F.resolvePhase(state,current)then return end
  for _,id in ipairs(current.extraIds)do allOwned[#allOwned+1]=id end
  emit('EXTRAS',{extraIds=current.extraIds,snapshot=F.snapshot(state),authority=replies.Extrasd});replies.Extrasd=nil
  local overflow=assert(F.find(state,samples[4]:getID()))
  local batch={overflow};for _,id in ipairs(current.extraIds)do batch[#batch+1]=assert(F.find(state,id))end
  fullBefore=F.snapshot(state);fullPreview=preview(batch,true);observeAdds(true);fullPreview.dropResult=loot:dropItemsInContainer(button)==true;clearDrag();transition('full-idle')
 elseif stage=='full-idle'then
  if now()-stageAt<300 then return end;assert(idle(),'fully rejected native drop queued timed work');restoreAdd();request('Full');transition('full')
 elseif stage=='full'and replies.Fulld then
  fullPreview.before=fullBefore;fullPreview.snapshot=F.snapshot(state);fullPreview.authority=replies.Fulld;fullPreview.queuedActions=0;fullPreview.nativeActions=0;emit('FULL',fullPreview);replies.Fulld=nil
  request('Release');transition('release')
 elseif stage=='release'and replies.Released then
  if not F.absentPhase(state,current)then return end
  for _,store in ipairs(state.stores)do assert(store:getItems():isEmpty(),'client crate still contains released items')end
  state.phase=nil;state.owned={}
  emit('RELEASE',{removedIds=replies.Released.removedIds,authority=replies.Released,ownedAbsent=true,snapshot=F.snapshot(state),original=originalProof()});replies.Released=nil;current=nil
  if index==2 then request('Cleanup');transition('cleanup')else index=index+1;beginModePosition()end
 elseif stage=='cleanup'and replies.Cleanupd then
  if not F.absent(ids)then return end
  for _,id in ipairs(allOwned)do local _,_,count=F.find(state,id);assert(count==0,'owned item survived native replication cleanup')end
  returnPosition()
 elseif stage=='return-position'then
  positionProof=positionReturnReady();if not positionProof then return end;position=nil
  local uiProof=restoreUI();local actual=originalProof()
  emit('RESTORED',{original=initialIdentity,actual=actual,rootIds=actual.rootIds,originalRootIds=arrayIds(initial),allOwnedIds=allOwned,ownedAbsent=true,ui=true,uiProof=uiProof,options=true,flags=true,positionRestored=true,positionProof=positionProof,authority=replies.Cleanupd})
  emit('COMPLETE',{phases=2,nativeActions=6,restored=true});done=true
 end
end
-- Kahlua allows only 60 captured locals per function. Keep phase handlers
-- separate so ordinary Lua fixture growth cannot exceed the native compiler.
local setupStages={baseline=true,position=true,prepared=true,['mode-position']=true,['mode-origin']=true,mode=true,['mode-discovery']=true,seeded=true}
local transferStages={preview=true,shot=true,drop=true,queued=true,transferring=true,effect=true}
local function tick()
 assert(not observerFailure,observerFailure);assert(not replies.Failed,replies.Failed and replies.Failed.error)
 assert(now()-began<360000,'Smart Deposit Host lifecycle deadline exceeded');assert(now()-stageAt<60000,'Smart Deposit Host stage deadline exceeded: '..stage)
 if setupStages[stage]then setupTick()elseif transferStages[stage]then transferTick()else cleanupTick()end
end
local function fail(problem)
 clearDrag();local restored,restoreError=pcall(restoreObservers)
 failure={token=ids and ids.token or 'unprepared',stage=stage,index=index,error=tostring(problem),observersRestored=restored,observerRestoreError=not restored and tostring(restoreError)or nil}
 if state then local ok,value=pcall(F.snapshot,state);if ok then failure.snapshot=value end end
 if state and samples and phaseProperties then local ok,value=pcall(transferDiagnostic);if ok then failure.transfer=value else failure.transferError=tostring(value)end end
 if state and modeLifecycle then local ok,value=pcall(modeDiagnostic);if ok then failure.discovery=value else failure.discoveryError=tostring(value)end end
 if positionTransition then failure.positionTransition=positionTransition end
 -- Only the actions admitted by this fixture may be cancelled during failure cleanup.
 local ownedWork=#queue().queue>0
 for _,action in ipairs(queue().queue)do if not action.item or not actionSet[action.item]or actionSet[action.item].action~=action then ownedWork=false end end
 if ownedWork then ISTimedActionQueue.clear(getPlayer())end
 emit('FAIL',failure);failing=true;transition('abort')
end
local function abortTick()
 if stage=='abort'then
  assert(now()-stageAt<15000,'authority abort/replication cleanup timed out')
  -- A preparation reply can race a client-side failure before IDs resolve.
  if not ids and replies.Prepared and not replies.Prepared.waiting then ids=replies.Prepared;state=F.resolve(getPlayer(),ids)end
  if ids and not replies.Cleanupd and not replies.Abortd and not(replies.Failed and replies.Failed.restored)then
   if not idle()then return end
   if not abortSent then request('Abort');abortSent=true end;return
  end
  if not ids and prepareSent and not replies.Prepared and not replies.Failed then return end
  if state and current and not F.absentPhase(state,current)then return end
  if ids and not F.absent(ids)then return end
  if position then returnPosition()else if ui then restoreUI()end;done=true end
 elseif stage=='return-position'then
  if not positionReturnReady()then return end
  position=nil;restoreUI();emit('ABORT',{token=ids and ids.token or 'unprepared',restored=true,authority=replies.Abortd or replies.Failed});done=true
 end
end
Events.OnPreUIDraw.Add(function()
 if holdDrag and sourcePane then sourcePane.draggingX=sourcePane:getMouseX();sourcePane.draggingY=sourcePane:getMouseY()end
 if holdDrag and loot then loot.mouseOverButton=button end
end)
Events.OnGameStart.Add(function()started=true;began=now();stageAt=began end)
Events.OnTick.Add(function()
 if not started or done or not isIngameState()or not getPlayer()or not getPlayer():getSquare()or getPlayer():getOnlineID()<0 then return end
 local ok,problem=pcall(failing and abortTick or tick)
 if not ok then
  if failing then
   -- Restore unrelated flags/options even when native position/UI verification fails.
   restoreFlags();emit('FAIL',{token=ids and ids.token or 'unprepared',stage=stage,error=tostring(problem),restored=false,quarantined=true});done=true
  else fail(problem)end
 end
end)
