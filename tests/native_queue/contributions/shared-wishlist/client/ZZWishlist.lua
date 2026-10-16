local Session=QueueWishlistSession
local Events=Session and Session.events or Events
-- Intake fixture: install only in disposable two-client native MP caches.
local failures,connecting,advanced=0,false,false
local reader=assert(getFileReader('wishlist-fixture.txt',false),'Missing wishlist fixture configuration')
local config={};for _,key in ipairs({'user','mode','host','port','password','mods'})do config[key]=assert(reader:readLine(),'Missing '..key)end;reader:close()
if Session then config.mode=Session.case end
local user=config.user;assert(user=='client1'or user=='client2','Expected two fixed fixture actors')
assert(config.mode=='full'or config.mode=='standalone'or config.mode=='reload'or config.mode=='visual','Invalid fixture mode')
local standalone=not getActivatedMods():contains('PZSurvivorToolkit')
local reload=config.mode=='reload'
if not Session then
Events.OnConnected.Add(function()connecting=true end)
Events.OnMainMenuEnter.Add(function()
 if connecting or isClient()then return end;connecting=true
 ConnectToServer.instance:connect(MainScreen.instance,'Wishlist isolated test',user,config.password,config.host,'',config.port,'',false,true,1)
end)
Events.OnPreUIDraw.Add(function()
 if(not connecting and not isClient())or advanced or isIngameState()then return end
 if MainScreen.instance.charCreationProfession:getIsVisible()or MapSpawnSelect.instance:getIsVisible()then
  advanced=true;MapSpawnSelect.instance:useDefaultSpawnRegion();MapSpawnSelect.instance:setVisible(false)
  MainScreen.instance.charCreationProfession:onOptionMouseDown({internal='NEXT'});MainScreen.instance.charCreationMain:onOptionMouseDown({internal='NEXT'})
 end
end)
end
local ids,data,stages,step,lastStage,started,lastReady=nil,{},{},1,0,nil,0
local function fixtureSend(command,args)
 if Session then Session.send(command,args) else sendClientCommand('WishlistTest',command,args or {}) end
end
local function stage(name,fn,delay)stages[#stages+1]={name,fn,delay or 2}end
local function joint(name,key,observe,after,delay)
 stage(name,observe,delay);stages[#stages].barrier=key;stages[#stages].after=after
end
local pending,aborted
local barrierTimeout=15000
local function W()return assert(PZSurvivorWishlist)end
local function list(id)for _,l in ipairs(W().Client.state(0).lists)do if l.id==(id or user)then return l end end end
local function item(name)local items=getPlayer():getInventory():getItems();for i=0,items:size()-1 do local it=items:get(i);if it:getID()==ids[name]then return it end end end
local function flatten(menu,out)out=out or{};for _,o in ipairs(menu.options)do out[#out+1]=o;if o.subOption then local s=menu:getSubMenu(o.subOption);if s then flatten(s,out)end end end;return out end
local function preparePane(page)page:setVisible(true);page:setPinned();page.inventoryPane:setYScroll(0);page.inventoryPane:refreshContainer();ISInventoryPage.renderDirty=true end
local function rowHasType(row,fullType)
 if instanceof(row,'InventoryItem')then return row:getFullType()==fullType end
 if type(row)=='table'and type(row.items)=='table'then for _,it in ipairs(row.items)do
  if instanceof(it,'InventoryItem')and it:getFullType()==fullType then return true end
 end end
 return false
end
local function targetRow(pane,fullType)
 for index,row in ipairs(pane.items)do if rowHasType(row,fullType)then return index end end
end
local function selectCombinedLoot(page)
 local p=require'BetterContainers/Proximity';local container=assert(p.GetItemContainer(0))
 page:refreshBackpacks();local selected=false
 for _,button in ipairs(page.backpacks)do if button.inventory==container then page:selectContainer(button);selected=true;break end end
 assert(selected,'combined loot button absent')
 assert(page.inventoryPane.inventory==container,'combined loot container not actually selected')
end
local function checkHighlight(page,fullType)
 local pane=page.inventoryPane;local borders,calls={},0
 -- Native rendering builds flattened rows and scroll height, including rows outside the viewport.
 pane.smoothScrollTargetY=nil;pane.smoothScrollY=nil;pane:refreshContainer();pane:renderdetails(false)
 local index=assert(targetRow(pane,fullType),'wanted item absent from native rows: '..fullType)
 assert(pane.itemHgt>0 and pane:getScrollAreaHeight()>0,'inventory viewport has no row area')
 local maxScroll=math.max(0,pane:getScrollHeight()-pane:getScrollAreaHeight())
 pane.smoothScrollTargetY=nil;pane.smoothScrollY=nil
 pane:setYScroll(-math.min((index-1)*pane.itemHgt,maxScroll))
 local original,originalDraw=pane.drawRectBorder,W().Inventory.draw
 pane.drawRectBorder=function(self,x,y,w,h,a,r,g,b)
  if math.abs((r or 0)-.25)<.001 and math.abs((g or 0)-.85)<.001 and math.abs((b or 0)-.75)<.001 then borders[#borders+1]={y=y,h=h}end
  return original(self,x,y,w,h,a,r,g,b)
 end
 W().Inventory.draw=function(target,...)
  if target==pane then calls=calls+1 end
  return originalDraw(target,...)
 end
 local ok,err=pcall(function()pane:renderdetails(false)end)
 pane.drawRectBorder=original;W().Inventory.draw=originalDraw;assert(ok,err)
 local marks=W().Inventory.marks(pane);local visible,targetVisible=0,false;local scroll=pane:getYScroll()
 for _,marked in ipairs(marks)do
  local top=(marked-1)*pane.itemHgt+pane.headerHgt+scroll
  if top+pane.itemHgt>pane.headerHgt and top<pane:getHeight()then
   visible=visible+1;if rowHasType(pane.items[marked],fullType)then targetVisible=true end
  end
 end
 print('[WISHLIST_TEST] HIGHLIGHT '..user..' calls='..calls..' marks='..#marks..' visible='..visible..' borders='..#borders..' height='..pane:getHeight()..' header='..pane.headerHgt..' row='..pane.itemHgt..' scroll='..scroll..' target='..fullType..' index='..index..' rows='..#pane.items)
 assert(#marks>0 and visible>0 and targetVisible,'wanted row absent from viewport')
 assert(calls==1,'highlight overlay missing/duplicated')
 assert(#borders==visible,'visible highlight borders missing/duplicated')
 for _,border in ipairs(borders)do
  assert(border.h>0 and border.y+scroll>=pane.headerHgt-.001 and border.y+border.h+scroll<=pane:getHeight()+.001,'highlight border outside viewport')
 end
end
local function separate(a,b)
 local ax,ay,bx,by=a:getAbsoluteX(),a:getAbsoluteY(),b:getAbsoluteX(),b:getAbsoluteY()
 return ax+a:getWidth()<=bx or bx+b:getWidth()<=ax or ay+a:getHeight()<=by or by+b:getHeight()<=ay
end
local function findButton(node)
 if node.pzswButton then return node.pzswButton,node end
 if node.getChildren then for _,child in pairs(node:getChildren())do local b,p=findButton(child);if b then return b,p end end end
end
local function checkCraft(window,label)
 local button,panel=findButton(window);assert(button,label..' wishlist button absent')
 assert(button:getX()>=0 and button:getY()>=0 and button:getBottom()<=panel:getHeight()+2,label..' button outside panel')
 button:prerender();local menu=W().Crafting.openMenu(panel);assert(menu and #menu.options>=2,label..' missing menu')
 print('[WISHLIST_TEST] CRAFT '..label..' type='..tostring(panel.Type)..' button='..button:getY()..'/'..panel:getHeight())
 menu:hideAndChildren();window:setVisible(false)
 return panel
end
stage('all selected mods and independent wishlist loaded',function()
 local n=0;for id in config.mods:gmatch('[^;]+')do n=n+1;assert(getActivatedMods():contains(id),id)end
 assert(n>0);assert(W().Client and W().Crafting and W().Inventory and W().UI)
 assert(list() and not W().Client.state(0).error,'personal snapshot unavailable: '..tostring(W().Client.state(0).error))
end)
if reload then
 stage('private persistent list survives native server and client restart',function()
  local l=assert(list('client1'),'shared list absent after reconnect')
  assert(l.entries['Base.Hammer'].amount==7 and not l.entries['Base.Hammer'].done)
  assert(l.members.client2==true)
 end)
 stage('reconnected client can edit existing shared list',function()
  if user=='client2'then W().Client.select(0,'client1');W().Client.edit(0,'set',{fullType='Base.Hammer',amount=8})end
 end)
 stage('reconnected peer edit reaches both clients',function()assert(list('client1').entries['Base.Hammer'].amount==8)end)
 stage('reconnected wishlist renders',function()local window=W().UI.open(0);window:prerender();assert(#window.list.items>0);window:close()end)
else
 stage('catalog opens without recipe or owned sample and adds item',function()
  local window=W().UI.open(0);data.window=window;window:prerender();window:catalog()
  local catalog=assert(window.catalogWindow);catalog.search:setText('Base.Hammer');catalog:filter()
  assert(#catalog.list.items>0)
  for i,row in ipairs(catalog.list.items)do if row.item.fullType=='Base.Hammer'then catalog.list.selected=i end end
  catalog.quantity:setText('2');catalog:prerender();catalog:add();catalog:close()
 end)
 stage('catalog edit confirmed and native rows render',function()
  assert(list().entries['Base.Hammer'].amount==2)
  local window=data.window;window:prerender();assert(#window.list.items==1);window.list:render();window:close()
 end)
 stage('native grouped inventory context adds each selected type once',function()
  local m=ISInventoryPaneContextMenu.createMenu(0,true,{item('watch1'),item('watch2')},40,40)
  if PZSurvivorToolkit then PZSurvivorToolkit.ContextMenus.organize(m)end
  local found;for _,o in ipairs(flatten(m))do if o.name==getText('UI_PZSW_AddWanted')then assert(not found);found=o end end
  assert(found,'context action absent');found.onSelect(found.target);m:hideAndChildren();preparePane(getPlayerInventory(0))
 end)
 stage('CleanUI inventory highlights real rows once',function()
  assert(list().entries['Base.AlarmClock2'].amount==1);checkHighlight(getPlayerInventory(0),'Base.AlarmClock2')
 end)
 stage('sidebar opens wishlist without overlapping existing buttons',function()
  local equipped=getPlayerData(0).equipped
  local toolkit=getActivatedMods():contains('PZSurvivorToolkit')
  local b=assert(toolkit and equipped.toolkitToolsButton or equipped.pzswButton,'wishlist sidebar control absent')
  assert(b:getIsVisible()and b:getWidth()>0 and b:getHeight()>0,'wishlist sidebar control hidden')
  if toolkit then assert(not equipped.pzswButton,'duplicate standalone wishlist sidebar control')end
  for _,child in pairs(equipped:getChildren())do if child~=b and child.Type=='ISButton'and child:getIsVisible()then
   assert(separate(b,child),'sidebar overlap')
  end end
  local highlight=equipped.toolkitHighlightButton
  if highlight and highlight:getIsVisible()then assert(separate(b,highlight),'sidebar controls overlap')end
  if W().UI.windows[0] then W().UI.windows[0]:close()end;b.onclick(b.target,b)
  if toolkit then
   local menu=assert(getPlayerContextMenu(0));local found
   for _,option in ipairs(flatten(menu))do if option.name==getText('UI_PZSW_Open')then assert(not found,'duplicate Wishlist hub action');found=option end end
   assert(found,'Wishlist hub action absent');found.onSelect(found.target);menu:hideAndChildren()
  end
  assert(W().UI.windows[0]:getIsVisible());W().UI.windows[0]:close()
 end)
 stage('switch CleanUI off',function()CleanUI_setCleanInventoryUIEnabled(false)end)
 stage('prepare native inventory mode',function()preparePane(getPlayerInventory(0))end)
 stage('native inventory mode preserves highlights',function()checkHighlight(getPlayerInventory(0),'Base.AlarmClock2')end)
 stage('restore CleanUI',function()CleanUI_setCleanInventoryUIEnabled(true)end)
 stage('prepare Better Containers combined loot',function()
  local page=getPlayerLoot(0);selectCombinedLoot(page);preparePane(page);W().Client.addItem(0,'Base.Nails',1)
 end)
 stage('combined reachable loot highlights item rows',function()local page=getPlayerLoot(0);selectCombinedLoot(page);checkHighlight(page,'Base.Nails')end)
 stage('Neat Crafting panel integrates wishlist',function()
  ISEntityUI.OpenHandcraftWindow(getPlayer(),nil,'*',false)
  local window=assert(ISEntityUI.GetWindowInstance(0,'HandcraftWindow'));data.nc=window;if Session then Session.ownWindow(window) end
  data.ncPanel=checkCraft(window,'Neat Crafting')
 end)
 stage('Neat Crafting parses real recipe inputs and outputs',function()
  local recipes=ScriptManager.instance:getAllCraftRecipes();local tested=0
  for i=0,math.min(recipes:size()-1,50)do
   data.ncPanel.logic:setRecipe(recipes:get(i));W().Crafting.missing(data.ncPanel.logic);W().Crafting.results(data.ncPanel.logic);tested=tested+1
  end
  assert(tested>20)
 end)
 stage('Neat Building panel integrates wishlist',function()
  ISEntityUI.OpenBuildWindow(getPlayer(),nil,nil,true,ScriptManager.instance:getAllBuildableRecipes():get(0))
  local window=assert(ISEntityUI.GetWindowInstance(0,'BuildWindow'));if Session then Session.ownWindow(window) end;if standalone then checkCraft(window,'Native building');return end;if not window.logic:getRecipe() then window.logic:setRecipe(ScriptManager.instance:getAllBuildableRecipes():get(0))end;window:showBuildingInfoPanel();window.BuildingInfoPanel:setVisible(true);checkCraft(window.BuildingInfoPanel,'Neat Building');window:setVisible(false)
 end)
 stage('Project Cook lazy recipe panel integrates wishlist',function()
  PJCK_CookingUI.OnOpenPanel(getPlayer(),nil);local window=assert(PJCK_CookingUI.GetWindowInstance(0))
  window:switchToPanel(PJCK_TAB_CRAFT or 'craft');window:createHandCraftPanel();window.HandCraftPanel:setVisible(true)
  data.cook=checkCraft(window,'Project Cook')
 end)
 stage('owner shares through native access dialog',function()
  if user=='client1'then local window=W().UI.open(0);window:share();local share=window.shareWindow
   share.username:setText('client2');share:addMember();share:save();window:close()
  end
 end)
 stage('peer receives shared list and edits it',function()
  assert(list('client1') and list('client1').members.client2)
  if user=='client2'then W().Client.select(0,'client1');W().Client.addItem(0,'Base.Nails',standalone and 3 or 2)end
 end)
 stage('shared peer edit is visible to owner and peer',function()assert(list('client1').entries['Base.Nails'].amount==3)end)
 stage('concurrent edits are issued against one revision',function()
  W().Client.select(0,'client1');W().Client.edit(0,'set',{fullType='Base.Hammer',amount=user=='client1'and 7 or 8})
 end)
 stage('concurrent edits retain one consistent result',function()
  local amount=list('client1').entries['Base.Hammer'].amount;assert(amount==7 or amount==8)
  local err=W().Client.state(0).error;assert(err==nil or err=='stale_revision',tostring(err))
  print('[WISHLIST_TEST] CONCURRENT amount='..amount..' error='..tostring(err))
  if user=='client2'then W().Client.edit(0,'done',{fullType='Base.Hammer',done=true})end
 end)
 joint('peer completion synchronizes and removes owner highlight','completion-observed',function()
  assert(list('client1').entries['Base.Hammer'].done)
  if user=='client1'then assert(not W().Client.isWanted(0,'Base.Hammer'))end
  data.lastRevision=list('client1').revision
 end,function()
  if user=='client1'then W().Client.edit(0,'share',{members={},faction=false})end
 end)
 stage('explicit revocation removes cached shared list',function()
  if user=='client2'then assert(not list('client1'));if Session then Session.trackRequest('forged') end;sendClientCommand(getPlayer(),'PZSurvivorWishlist','request',
   {action='set',listId='client1',revision=data.lastRevision,fullType='Base.Hammer',amount=900,requestId='forged'})end
 end)
 stage('revoked editor is rejected authoritatively',function()
  if user=='client2'then assert(W().Client.state(0).error=='forbidden')else assert(list('client1').entries['Base.Hammer'].amount<900)end
  if user=='client1'then fixtureSend('Faction',{})end
 end)
 stage('owner enables current faction access',function()
  if user=='client1'then W().Client.edit(0,'share',{members={},faction=true})end
 end)
 stage('faction peer edits shared list',function()
  assert(list('client1') and list('client1').faction=='WishlistTest')
  if user=='client2'then W().Client.select(0,'client1');W().Client.edit(0,'set',{fullType='Base.Nails',amount=5})end
 end)
 joint('faction edit reaches owner','faction-edit-observed',function()
  assert(list('client1').entries['Base.Nails'].amount==5)
 end,function()
  if user=='client1'then fixtureSend('Faction',{remove=true})end
 end)
 joint('faction departure revokes access without another list edit','faction-revocation-observed',function()
  if user=='client2'then assert(not list('client1'),'stale faction access')end
 end,function()
  if user=='client1'then W().Client.edit(0,'share',{members={'client2'},faction=false});W().Client.edit(0,'set',{fullType='Base.Hammer',amount=7});W().Client.edit(0,'done',{fullType='Base.Hammer',done=false})end
 end,7)
 stage('visible loose wanted item highlights without claiming container',function()
  local it=getPlayer():getCurrentSquare():AddWorldInventoryItem('Base.Hammer',0.4,0.4,0);data.world=it:getWorldItem()
  assert(data.world);if Session then Session.ownWorld(data.world) end;getPlayer():getCurrentSquare():setIsSeen(0,true)
 end)
 stage('ground highlight uses wishlist colour',function()
  assert(W().Highlighter.getStatus().lastError==nil,tostring(W().Highlighter.getStatus().lastError))
  local object=data.world;assert(object:isHighlighted(0),'visible wanted item not highlighted')
  assert(math.abs(object:getHighlightColor(0):getG()-.85)<.01,'Toolkit colour won')
  W().Client.select(0,'client1');fixtureSend('Verify',{})
 end,4)
 stage('authoritative final list is ready for restart check',function()
  assert(data.Verified and data.Verified.ok);assert(list('client1').entries['Base.Hammer'].amount==7)
  assert(not list('client1').entries['Base.Hammer'].done)
  local window=W().UI.open(0);window:prerender()
 end)
 stage('capture actual wishlist UI',function()getCore():TakeFullScreenshot('wishlist-'..user..'.png')end)
 stage('both clients remain connected after all integrations',function()assert(isClient()and getPlayer());W().UI.windows[0]:close()end)
end
if config.mode=='visual' then
 stages={}
 stage('native handcraft window opens',function()
  ISEntityUI.OpenHandcraftWindow(getPlayer(),nil,'*',false)
  data.visual=assert(ISEntityUI.GetWindowInstance(0,'HandcraftWindow'));if Session then Session.ownWindow(data.visual) end
 end)
 stage('native handcraft final rendered layout',function()
  local b,p=findButton(data.visual);assert(b and b:getWidth()>60 and b:getY()>0)
  assert(b:getBottom()<=p:getHeight()+2)
  getCore():TakeFullScreenshot('native-handcraft-'..user..'.png')
 end)
 stage('native building window opens',function()
  data.visual:setVisible(false)
  ISEntityUI.OpenBuildWindow(getPlayer(),nil,nil,true,ScriptManager.instance:getAllBuildableRecipes():get(0))
  data.visual=assert(ISEntityUI.GetWindowInstance(0,'BuildWindow'));if Session then Session.ownWindow(data.visual) end
 end)
 stage('native building final rendered layout',function()
  local b,p=findButton(data.visual);assert(b and b:getWidth()>60 and b:getY()>0,'button did not receive final layout')
  assert(b:getBottom()<=p:getHeight()+2)
  getCore():TakeFullScreenshot('native-building-'..user..'.png')
 end)
 stage('catalog opens above wishlist',function()
  data.visual:setVisible(false);data.window=W().UI.open(0);data.window:catalog()
  data.window.catalogWindow.search:setText(user=='client2'and'\209\130\208\190\208\191\208\190\209\128'or'axe')
 end)
 stage('translated catalog search and rendered layout',function()
  local c=data.window.catalogWindow;assert(#c.list.items>0);c.list.selected=1
  print('[WISHLIST_TEST] SEARCH '..c.query..' matches='..#c.list.items)
  getCore():TakeFullScreenshot('catalog-'..user..'.png')
 end)
 stage('catalog close releases quantity keyboard focus',function()
  local c=data.window.catalogWindow;c.quantity:focus();assert(getCore():isDoingTextEntry());c:close()
  assert(not getCore():isDoingTextEntry())
  data.closed={c.javaObject}
  for i=1,20 do data.window:catalog();local w=data.window.catalogWindow;data.closed[#data.closed+1]=w.javaObject;w:close()end
 end)
 stage('repeated closed catalogs leave UIManager',function()
  local ui=UIManager.getUI();for _,closed in ipairs(data.closed)do assert(not ui:contains(closed),'closed catalog retained by UIManager')end
 end)
 stage('sharing dialog renders',function()
  data.window.catalogWindow:close();W().Client.select(0,user);data.window:share()
 end)
 stage('sharing dialog remains inside its window',function()
  local w=assert(data.window.shareWindow);assert(w.saveButton:getBottom()<w.height)
  getCore():TakeFullScreenshot('sharing-'..user..'.png')
 end)
 stage('native UI switches remain toggleable',function()
  local options=PZAPI.ModOptions:getOptions('PZSurvivorWishlist')
  local b,p=findButton(data.visual);options:getOption('Crafting'):setValue(false)
  p:prerender();assert(not b:getIsVisible())
  options:getOption('Crafting'):setValue(true);p:prerender();assert(b:getIsVisible())
  data.window.shareWindow:close();data.window:close()
 end)
end
if standalone then
 local skip={['switch CleanUI off']=true,['prepare native inventory mode']=true,['native inventory mode preserves highlights']=true,['restore CleanUI']=true,['prepare Better Containers combined loot']=true,['combined reachable loot highlights item rows']=true,['Project Cook lazy recipe panel integrates wishlist']=true}
 local filtered={};for _,s in ipairs(stages)do if not skip[s[1]]then filtered[#filtered+1]=s end end;stages=filtered
end
local stageNames={};for _,spec in ipairs(stages)do stageNames[#stageNames+1]=spec[1]end
WishlistTestFixture={stageCount=#stages,mode=config.mode,standalone=standalone,stageNames=stageNames,stages=stages,checkHighlight=checkHighlight,separate=separate}
Events.OnGameStart.Add(function()
 print('[WISHLIST_TEST] CONNECTED '..user..' language='..tostring(getCore():getOptionLanguageName()))
 if user=='client2'and not reload and not Session then local p=getPlayer();p:teleportTo(math.floor(p:getX())+8,math.floor(p:getY())+8,0)end
 started=getTimestampMs();if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
Events.OnServerCommand.Add(function(module,command,args)
 if module~='WishlistTest'then return end
 if command=='Start'then ids=args;lastStage=getTimestampMs()
 elseif command=='Continue'then
  assert(pending and args.key==pending.spec.barrier,'unexpected joint observation release');pending.released=true
 else data[command]=args end
end)
local function finish(s,ok,err,now)
 if not ok then failures=failures+1 end
 print('[WISHLIST_TEST] '..(ok and'PASS 'or'FAIL ')..s[1]..' '..tostring(err))
 step=step+1;lastStage=now
 if not ok and (s.barrier or Session) then aborted=true end
 if step>#stages or aborted then
  print('[WISHLIST_TEST] COMPLETE checks='..(step-1)..' failures='..failures)
  if Session then Session.finish(failures==0,(not ok and s.barrier~=nil) or tostring(err):find('deadline',1,true)~=nil) end
 end
end
Events.OnTick.Add(function()
 local now=getTimestampMs()
 if aborted then return end
 if pending then
  if pending.released then
   local s=pending.spec;pending=nil;local ok,err=pcall(s.after);finish(s,ok,err,now)
  elseif now-pending.since>=barrierTimeout then
   local s=pending.spec;pending=nil;finish(s,false,'joint observation deadline '..s.barrier,now)
  end
  return
 end
 if not ids then if started and now-started>2000 and now-lastReady>1000 then lastReady=now;fixtureSend('Ready',{})end;return end
 local s=stages[step];if not s or now-lastStage<s[3]*1000 then return end
 local ok,err=pcall(s[2])
 if ok and s.barrier then
  pending={spec=s,since=now};fixtureSend('Observed',{key=s.barrier})
 else finish(s,ok,err,now)end
end)

if Session then
 local state=W().Client.state(0)
 local option=PZAPI.ModOptions:getOptions('PZSurvivorWishlist'):getOption('Crafting')
 local originalOption,originalWindow=option:getValue(),W().UI.windows[0]
 local pages={};for _,page in ipairs({getPlayerInventory(0),getPlayerLoot(0)}) do
  pages[#pages+1]={page=page,visible=page:getIsVisible(),pin=page.pin,scroll=page.inventoryPane:getYScroll(),inventory=page.inventoryPane.inventory,
   smoothTarget=page.inventoryPane.smoothScrollTargetY,smooth=page.inventoryPane.smoothScrollY}
 end
 local worlds,requests,windows={},{},{}
 Session.ownWindow=function(window) windows[window]=true end
 Session.ownerKey='WishlistTestOwner'
 Session.trackRequest=function(id) assert(not requests[id],'duplicate raw fixture product request');requests[id]=true end
 Session.observeProduct=function(module,command,args)
  if module=='PZSurvivorWishlist' and command=='snapshot' and args and args.requestId then requests[args.requestId]=nil end
 end
 Session.ownWorld=function(world) worlds[#worlds+1]={world=world,square=world:getSquare()} end
 Session.readyToClean=function()
  assert(state.error~='timeout','product request timed out with unknown effects')
  if state.pending or #state.queue>0 or next(requests) then return false end
  return true
 end
 Session.cleanup=function()
  assert(Session.readyToClean(),'product requests still pending')
  assert(not getPlayer():hasTimedActions(),'native actions still active')
  local queue=ISTimedActionQueue.getTimedActionQueue(getPlayer());assert(#queue.queue==0,'native queue still active')
  local window=W().UI.windows[0];if window and window~=originalWindow then window:close() end
  for window in pairs(windows) do window:close() end
  for _,entry in ipairs(worlds) do if entry.square:getWorldObjects():contains(entry.world) then entry.square:transmitRemoveItemFromSquare(entry.world) end end
  W().UI.windows[0]=originalWindow;option:setValue(originalOption)
  assert(option:getValue()==originalOption and not getCore():isDoingTextEntry(),'Wishlist option/focus did not restore')
  pending=nil;data={};Session.restoreClient()
  return true
 end
 Session.clean=function(receipt)
  local ready,reason=Session.verifyOwned(receipt);if not ready then return false,reason end
  for _,entry in ipairs(worlds) do if entry.square:getWorldObjects():contains(entry.world) then return false,'owned loose item remains' end end
  for _,entry in ipairs(pages) do
   local page=entry.page
   if entry.pin then page:setPinned() else page:collapse() end
   page.inventoryPane.inventory=entry.inventory;page.inventoryPane:refreshContainer();page.inventoryPane:setYScroll(entry.scroll)
   page.inventoryPane.smoothScrollTargetY=entry.smoothTarget;page.inventoryPane.smoothScrollY=entry.smooth;page:setVisible(entry.visible)
  end
  assert(Session.readyToClean(),'late product request appeared during reset')
  assert(not state.error or state.error=='stale_revision','unresolved product error after reset')
  return true
 end
end
