-- Native UI state/selection restoration shared by the two warehouse clients.
local Options=require 'BetterContainers/_Options'
local U={}
local paneFields={'toolkitVisibleItems','toolkitCategory','toolkitTag','toolkitTagRule','searchText','searchCategoryText','joyfocus','dragging','dragStarted','draggingMarquis','toolkitPendingMarquee'}
local optionNames={'enableProximity','enableCorpseOnly','enableDualMode','enableNestedContainers_Loot','enableAutoLock'}
local function now()return getTimestampMs()end
local function shallow(value)local r={};for k,v in pairs(value or {})do r[k]=v end;return r end
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

function U.pages(player)return {getPlayerInventory(player:getPlayerNum()),getPlayerLoot(player:getPlayerNum())}end
function U.normalize(player)for _,page in ipairs(U.pages(player))do ownerLayout(page)end end
function U.save(player)
 local saved={pages={},cleanMode=CleanUI_isCleanInventoryUIEnabled(),options={},god=player:isGodMod(),ghost=player:isGhostMode(),
  autoDrink=player:getAutoDrink(),coreAutoDrink=getCore():getOptionAutoDrink(),focusLoss=getCore():getOptionPauseOnFocusloss()}
 for _,name in ipairs(optionNames)do saved.options[name]=Options[name]end
 for _,page in ipairs(U.pages(player))do local q=assert(page.inventoryPane)
  saved.pages[#saved.pages+1]={pageClass=getmetatable(page),paneClass=getmetatable(q),inventory=q.inventory,visible=page:getIsVisible(),collapsed=page.isCollapsed,pin=page.pin,collapseCounter=page.collapseCounter,
   x=page:getX(),y=page:getY(),width=page:getWidth(),height=page:getHeight(),maxDrawHeight=page:getMaxDrawHeight(),paneX=q:getX(),paneY=q:getY(),paneWidth=q:getWidth(),paneHeight=q:getHeight(),
   paneVisible=q:getIsVisible(),paneMaxDrawHeight=q:getMaxDrawHeight(),paneMode=q.mode,scroll=q:getYScroll(),smoothScrollY=q.smoothScrollY,smoothScrollTargetY=q.smoothScrollTargetY,
   groups=shallow(q.collapsed),selected=saveSelection(q),equippedCollapsed=q.equippedCollapsed,doController=q.doController,
   firstSelect=anchor(q,q.firstSelect),joyselection=anchor(q,q.joyselection and q.joyselection+1),mouseOverOption=q.mouseOverOption,
   forceSelected=page.forceSelectedContainer,forceTime=page.forceSelectedContainerTime,mouseOverButton=page.mouseOverButton,joyfocus=page.joyfocus,
   collapseButton=page.collapseButton and page.collapseButton:getIsVisible(),pinButton=page.pinButton and page.pinButton:getIsVisible()}
  local fields={};for _,name in ipairs(paneFields)do fields[name]=q[name]end;saved.pages[#saved.pages].fields=fields
 end
 for _,entry in ipairs({{name='guide',value=SurvivalGuide and SurvivalGuide.instance},{name='info',value=getPlayerInfoPanel and getPlayerInfoPanel(player:getPlayerNum())}})do
  if entry.value then saved[entry.name]={page=entry.value,visible=entry.value:getIsVisible()}end
 end
 return saved
end
function U.flags(player,saved)
 player:setGodMod(saved.god);player:setGhostMode(saved.ghost);player:setAutoDrink(saved.autoDrink)
 getCore():setOptionAutoDrink(saved.coreAutoDrink);getCore():setOptionPauseOnFocusloss(saved.focusLoss)
 for _,name in ipairs(optionNames)do Options[name]=saved.options[name]end
 for _,name in ipairs({'guide','info'})do if saved[name]then saved[name].page:setVisible(saved[name].visible)end end
end
function U.protect(player,saved)
 player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false);getCore():setOptionAutoDrink(false);getCore():setOptionPauseOnFocusloss(false)
 for _,name in ipairs({'guide','info'})do if saved[name]then saved[name].page:setVisible(false)end end
end
function U.configure(player,mode)
 -- Save must precede even a same-value toggle: that operation can recreate pages.
 if CleanUI_isCleanInventoryUIEnabled()~=(mode=='clean')then CleanUI_setCleanInventoryUIEnabled(mode=='clean')end
 Options.enableProximity=true;Options.enableCorpseOnly=false;Options.enableDualMode=false;Options.enableNestedContainers_Loot=false;Options.enableAutoLock=false
 player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false);getCore():setOptionAutoDrink(false);getCore():setOptionPauseOnFocusloss(false)
 local class=mode=='clean'and CleanUI_Clean_ISInventoryPane or CleanUI_Vanilla_ISInventoryPane
 for _,page in ipairs(U.pages(player))do local q=page.inventoryPane
  assert(getmetatable(q)==class,'native warehouse inventory class differs')
  page:setPinned();page:setVisible(true);page.isCollapsed=false;page:clearMaxDrawHeight()
  q:setMode('details');q:setVisible(true);q:clearMaxDrawHeight();q.selected={};q.firstSelect=nil;q.doController=nil
  q.toolkitVisibleItems=nil;q.toolkitCategory=nil;q.toolkitTag=nil;q.toolkitTagRule=nil;q.searchText='';q.searchCategoryText=''
  q.smoothScrollY=nil;q.smoothScrollTargetY=nil;q:setYScroll(0);page:refreshBackpacks()
 end
end
function U.restore(player,saved)
 for _,name in ipairs(optionNames)do Options[name]=saved.options[name]end
 if CleanUI_isCleanInventoryUIEnabled()~=saved.cleanMode then CleanUI_setCleanInventoryUIEnabled(saved.cleanMode)end
 local pages=U.pages(player);local proof={pages={},options={},cleanMode={expected=saved.cleanMode,actual=CleanUI_isCleanInventoryUIEnabled()}}
 for i,page in ipairs(pages)do local value=saved.pages[i];local q=page.inventoryPane
  assert(getmetatable(page)==value.pageClass and getmetatable(q)==value.paneClass,'original native UI classes not restored')
  page.forceSelectedContainer=nil;page.forceSelectedContainerTime=nil;geometry(page,value)
  if value.pin then page:setPinned()else page:collapse()end
  page:setVisible(value.visible);page.isCollapsed=value.collapsed;page.collapseCounter=value.collapseCounter;page:setMaxDrawHeight(value.maxDrawHeight)
  geometry(q,value,'pane');q:setMode(value.paneMode);q:setVisible(value.paneVisible);q:setMaxDrawHeight(value.paneMaxDrawHeight)
  q.collapsed=shallow(value.groups);q.equippedCollapsed=value.equippedCollapsed
  for _,name in ipairs(paneFields)do q[name]=value.fields[name]end
  page:refreshBackpacks();local available={};for _,entry in ipairs(page.backpacks or {})do if entry.inventory then available[entry.inventory]=true end end
  assert(available[value.inventory],'original native container unavailable after position return');page:setNewContainer(value.inventory)
 end
 local matched=false
 for _=1,4 do
  for _,page in ipairs(pages)do ownerLayout(page)end
  matched=true;for i,page in ipairs(pages)do if not sameGeometry(page.inventoryPane,saved.pages[i],'pane')then matched=false end end
  if matched then break end
 end
 assert(matched,'native owner layout did not restore original pane geometry')
 for i,page in ipairs(pages)do local value=saved.pages[i];local q=page.inventoryPane
  restoreSelection(q,value.selected);q.firstSelect=restoreAnchor(q,value.firstSelect);local joy=restoreAnchor(q,value.joyselection);q.joyselection=joy and joy-1 or nil
  q.doController=value.doController;q.mouseOverOption=value.mouseOverOption;q:setYScroll(value.scroll);q.smoothScrollY=value.smoothScrollY;q.smoothScrollTargetY=value.smoothScrollTargetY
  page.forceSelectedContainer=value.forceSelected;page.forceSelectedContainerTime=value.forceTime;page.mouseOverButton=value.mouseOverButton;page.joyfocus=value.joyfocus
  if page.collapseButton then page.collapseButton:setVisible(value.collapseButton)end;if page.pinButton then page.pinButton:setVisible(value.pinButton)end
  assert(sameGeometry(page,value)and sameGeometry(q,value,'pane'),'original active UI geometry changed')
  assert(page.pin==value.pin and page.isCollapsed==value.collapsed and page:getIsVisible()==value.visible and page:getMaxDrawHeight()==value.maxDrawHeight,'original native page state changed')
  assert(q.mode==value.paneMode and q:getYScroll()==value.scroll and q:getIsVisible()==value.paneVisible and q:getMaxDrawHeight()==value.paneMaxDrawHeight and q.equippedCollapsed==value.equippedCollapsed,'original native pane state changed')
  local available={};for _,entry in ipairs(page.backpacks or {})do if entry.inventory then available[entry.inventory]=true end end
  assert(page.inventory==value.inventory and q.inventory==value.inventory and(q.lastinventory==nil or available[q.lastinventory]),'original live UI binding/cache changed')
  proof.pages[i]={expected={owner={x=value.x,y=value.y,width=value.width,height=value.height,visible=value.visible,pin=value.pin,collapsed=value.collapsed,maxDrawHeight=value.maxDrawHeight},
   pane={x=value.paneX,y=value.paneY,width=value.paneWidth,height=value.paneHeight,visible=value.paneVisible,mode=value.paneMode,scroll=value.scroll,maxDrawHeight=value.paneMaxDrawHeight,equippedCollapsed=value.equippedCollapsed}},
   actual=layoutProof(page,q),inventoryBound=true,selectionRestored=true,pageClass=tostring(getmetatable(page).Type),paneClass=tostring(getmetatable(q).Type)}
 end
 U.flags(player,saved)
 assert(CleanUI_isCleanInventoryUIEnabled()==saved.cleanMode,'original clean mode changed')
 for _,name in ipairs(optionNames)do assert(Options[name]==saved.options[name],'original option changed: '..name);proof.options[name]={expected=saved.options[name],actual=Options[name]}end
 assert(player:isGodMod()==saved.god and player:isGhostMode()==saved.ghost and player:getAutoDrink()==saved.autoDrink,'original flags changed')
 assert(getCore():getOptionAutoDrink()==saved.coreAutoDrink and getCore():getOptionPauseOnFocusloss()==saved.focusLoss,'original core options changed')
 proof.flags={expected={god=saved.god,ghost=saved.ghost,autoDrink=saved.autoDrink},actual={god=player:isGodMod(),ghost=player:isGhostMode(),autoDrink=player:getAutoDrink()}}
 proof.core={expected={autoDrink=saved.coreAutoDrink,focusLoss=saved.focusLoss},actual={autoDrink=getCore():getOptionAutoDrink(),focusLoss=getCore():getOptionPauseOnFocusloss()}};return proof
end
function U.original(player)
 local value={items={},worn={},primary=player:getPrimaryHandItem(),secondary=player:getSecondaryHandItem()}
 local function visit(c)
  for i=0,c:getItems():size()-1 do local item=c:getItems():get(i)
   value.items[item:getID()]={item=item,container=c,kind=item:getFullType(),name=item:getName(),favorite=item:isFavorite(),condition=item:getCondition(),weight=item:getUnequippedWeight()}
   if instanceof(item,'InventoryContainer')then visit(item:getItemContainer())end
  end
 end
 visit(player:getInventory());local worn=player:getWornItems()
 for i=0,worn:size()-1 do local e=worn:get(i);value.worn[#value.worn+1]={location=e:getLocation(),item=e:getItem()}end
 return value
end
function U.originalProof(player,value)
 local actual=U.original(player);local ids={};local count=0
 for id,saved in pairs(value.items)do local entry=actual.items[id];count=count+1;ids[#ids+1]=id
  assert(entry and entry.item==saved.item and entry.container==saved.container,'original item identity/endpoint changed')
  assert(entry.kind==saved.kind and entry.name==saved.name and entry.favorite==saved.favorite and entry.condition==saved.condition and entry.weight==saved.weight,'original item payload changed')
 end
 local n=0;for _ in pairs(actual.items)do n=n+1 end;assert(n==count,'nonoriginal inventory survived cleanup')
 assert(actual.primary==value.primary and actual.secondary==value.secondary and #actual.worn==#value.worn,'original equipment changed')
 for i,entry in ipairs(actual.worn)do assert(entry.item==value.worn[i].item and entry.location==value.worn[i].location,'original worn item/location changed')end
 table.sort(ids);return {ids=ids,identity=true,payload=true,equipment=true}
end
function U.position(player)
 local square=player:getSquare();local current=player:getCurrentSquare();local motion=player:getDeferredMovement(Vector2.new())
 return {x=player:getX(),y=player:getY(),z=player:getZ(),squareX=square and square:getX(),squareY=square and square:getY(),squareZ=square and square:getZ(),
  currentSquareX=current and current:getX(),currentSquareY=current and current:getY(),currentSquareZ=current and current:getZ(),moving=player:isPlayerMoving(),hasPath=player:getPath2()~=nil,deferredX=motion:getX(),deferredY=motion:getY()}
end
function U.place(player,value,idle)
 assert(now()-value.began<15000,'native position transition did not settle')
 local actual=U.position(player);local quiet=idle and not actual.moving and not actual.hasPath and actual.deferredX==0 and actual.deferredY==0
 if not value.placedAt then
  local previous=value.last
  if not quiet or not value.quietAt or not previous or actual.x~=previous.x or actual.y~=previous.y or actual.z~=previous.z then value.quietAt=quiet and now()or nil;value.samples=quiet and 1 or 0
  else value.samples=value.samples+1 end
  value.last=actual;if not value.quietAt or now()-value.quietAt<500 then return end
  value.quiescence={stableMs=now()-value.quietAt,minimumStableMs=500,samples=value.samples};local target=value.target
  player:teleportTo(target.x,target.y,target.z);player:setForceX(target.x);player:setForceY(target.y);player:setZ(target.z);value.placedAt=now();return
 end
 local target=value.target
 if now()-value.placedAt<100 or not quiet or math.abs(actual.x-target.x)>.01 or math.abs(actual.y-target.y)>.01 or math.abs(actual.z-target.z)>.01
  or actual.squareX~=target.squareX or actual.squareY~=target.squareY or actual.squareZ~=target.squareZ
  or actual.currentSquareX~=target.squareX or actual.currentSquareY~=target.squareY or actual.currentSquareZ~=target.squareZ then return end
 return {target=value.target,actual=actual,quiescence=value.quiescence,elapsedMs=now()-value.placedAt,lifecycleElapsedMs=now()-value.began,deadlineMs=15000,singlePlacement=true}
end
return U
