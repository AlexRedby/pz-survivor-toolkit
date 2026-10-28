-- Only the fresh performance baseline followed by the functional UI gate.
local create=require 'QueueFixtureSession'
require 'TimedActions/ISTimedActionQueue'
local M={}
local current
local function copy(value)
 local result={};for key,item in pairs(value or{})do result[key]=item end;return result
end
local function identity(inventory)
 local result={};local items=inventory:getItems()
 for i=0,items:size()-1 do local item=items:get(i);assert(not result[item:getID()]);result[item:getID()]=item end
 return result
end
local function conserved(state)
 local after=identity(state.inventory)
 for id,item in pairs(state.items)do assert(after[id]==item and item:getContainer()==state.inventory,'original inventory changed');after[id]=nil end
 for _ in pairs(after)do error('owned inventory survived cleanup')end
 assert(math.abs(state.inventory:getCapacityWeight()-state.weight)<.0001,'inventory weight not restored')
end
local function idle()
 local player=getPlayer()
 return player and #ISTimedActionQueue.getTimedActionQueue(player).queue==0 and not player:hasTimedActions()
end
local function rows(pane)
 local result={}
 local limit=pane.MAX_ITEMS_IN_STACK_TO_RENDER or(ISInventoryPane and ISInventoryPane.MAX_ITEMS_IN_STACK_TO_RENDER)or 50
 for _,group in ipairs(pane.itemslist or{})do
  if not(pane.equippedCollapsed and group.equipped)then
   result[#result+1]={item=group.cleanUIDisplayItem or group.firstItem or(group.items and group.items[1]),name=group.name,group=true}
   if group.items and not pane.collapsed[group.name]then
    local first=group.cleanUIFirstActualIndex or(group.cleanUILargeStackOptimized and 1)or 2
    for index=first,math.min(#group.items,first+limit-1)do result[#result+1]={item=group.items[index],group=false}end
   end
  end
 end
 return result
end
local function selected(pane)
 local saved=pane:saveSelection({})
 -- CleanUI always returns this metadata table, even for no selection. Its
 -- group names are logical identities; neither table nor header aliases are.
 local groups=copy(saved._cleanUISelectedGroups)
 local result={_cleanUISelectedGroups=groups}
 local aliases={}
 for _,group in ipairs(pane.itemslist or{})do
  local item=group.cleanUIDisplayItem or group.firstItem or(group.items and group.items[1])
  if item then aliases[item]=group.name end
 end
 for item,value in pairs(saved)do
  if item~='_cleanUISelectedGroups'then
   assert(value=='item'or value=='group','unknown native selection marker')
   if value=='group'then groups[assert(aliases[item],'selected group has no current row')]=true
   else result[item]=value end
  end
 end
 -- Vanilla's restored header is a raw InventoryItem. Keep its group semantic
 -- without confusing the same physical item's expanded child row with it.
 for index,row in ipairs(rows(pane))do
  if row.group and pane.selected[index]then groups[assert(row.name,'selected header has no name')]=true end
 end
 for item,name in pairs(aliases)do if groups[name]then result[item]=nil end end
 for name,value in pairs(groups)do assert(type(name)=='string'and value==true,'invalid native selected group')end
 return result
end
local function restoreSelection(pane,saved)
 local input=copy(saved);input._cleanUISelectedGroups=copy(saved._cleanUISelectedGroups)
 for _,row in ipairs(rows(pane))do
  if row.group and row.item and input._cleanUISelectedGroups[row.name]then input[row.item]='group'end
 end
 pane.selected={};pane:restoreSelection(input)
 local actual=selected(pane)
 for item,value in pairs(saved)do
  if item~='_cleanUISelectedGroups'then assert(actual[item]==value,'native item selection lost')end
 end
 for item in pairs(actual)do if item~='_cleanUISelectedGroups'then assert(saved[item],'foreign native item selection')end end
 for name in pairs(saved._cleanUISelectedGroups)do assert(actual._cleanUISelectedGroups[name],'native group selection lost')end
 for name in pairs(actual._cleanUISelectedGroups)do assert(saved._cleanUISelectedGroups[name],'foreign native group selection')end
end
local function anchor(pane,index)
 return {index=index,row=index and rows(pane)[index]or nil}
end
local function restoreAnchor(pane,saved)
 if not saved.row then return saved.index end
 for index,row in ipairs(rows(pane))do
  if row.group==saved.row.group and(row.group and row.name==saved.row.name or not row.group and row.item==saved.row.item)then return index end
 end
 error('native selection anchor lost')
end
local function capturePage(page)
 local pane=page.inventoryPane
 return {x=page:getX(),y=page:getY(),width=page:getWidth(),height=page:getHeight(),visible=page:getIsVisible(),
  collapsed=page.isCollapsed,pin=page.pin,maxDrawHeight=page:getMaxDrawHeight(),
  inventory=pane.inventory,forced=page.forceSelectedContainer,forcedTime=page.forceSelectedContainerTime,
  mode=pane.mode,paneVisible=pane:getIsVisible(),selected=selected(pane),groups=copy(pane.collapsed),
  equippedCollapsed=pane.equippedCollapsed,
  firstSelect=anchor(pane,pane.firstSelect),joyselection=anchor(pane,pane.joyselection and pane.joyselection+1),mouseOverOption=pane.mouseOverOption,
  scroll=pane:getYScroll(),smoothScrollY=pane.smoothScrollY,smoothScrollTargetY=pane.smoothScrollTargetY}
end
local function restorePage(saved,page)
 local function describe(container)return tostring(container):sub(1,120)end
 local function binding()
  local pane=page.inventoryPane
  return ' target='..describe(saved.inventory)..' pane='..describe(pane.inventory)
   ..' page='..describe(page.inventory)..' cache='..describe(pane.lastinventory)
 end
 page.forceSelectedContainer=nil;page.forceSelectedContainerTime=nil
 -- Geometry/native resize may invalidate derived pane caches. Complete it
 -- before binding a container or restoring the rows/selection/scroll it owns.
 page:setX(saved.x);page:setY(saved.y);page:setWidth(saved.width);page:setHeight(saved.height)
 if saved.pin then page:setPinned()else page:collapse()end
 page.isCollapsed=saved.collapsed;page:setMaxDrawHeight(saved.maxDrawHeight)
 local pane=page.inventoryPane
 pane:setVisible(saved.paneVisible);page:setVisible(saved.visible)
 pane.collapsed=copy(saved.groups);pane.equippedCollapsed=saved.equippedCollapsed;pane:setMode(saved.mode);page:refreshBackpacks()
 local available={}
 for _,button in ipairs(page.backpacks or{})do if button.inventory then available[button.inventory]=true end end
 assert(available[saved.inventory],'native saved container unavailable after refresh'..binding())
 page:setNewContainer(saved.inventory)
 assert(page.inventoryPane==pane and pane.inventory==saved.inventory and page.inventory==saved.inventory,
  'native active container not restored'..binding())
 -- lastinventory belongs to native refresh/selection, not the saved UI state.
 -- Nil is a legitimate invalidated cache; a live value must still be available.
 assert(pane.lastinventory==nil or available[pane.lastinventory],'native container cache is unavailable'..binding())
 page.forceSelectedContainer=saved.forced;page.forceSelectedContainerTime=saved.forcedTime
 restoreSelection(pane,saved.selected)
 pane.firstSelect=restoreAnchor(pane,saved.firstSelect)
 local joy=restoreAnchor(pane,saved.joyselection);pane.joyselection=joy and joy-1 or nil
 pane.mouseOverOption=saved.mouseOverOption
 pane:setYScroll(saved.scroll);pane.smoothScrollY=saved.smoothScrollY;pane.smoothScrollTargetY=saved.smoothScrollTargetY
 assert(pane.inventory==saved.inventory and page.inventory==saved.inventory,'native active container changed after row restore'..binding())
 assert(page:getX()==saved.x and page:getY()==saved.y and page:getWidth()==saved.width and page:getHeight()==saved.height,'page geometry not restored')
 assert(page.pin==saved.pin and page.isCollapsed==saved.collapsed and page:getIsVisible()==saved.visible,'page state not restored')
 assert(pane:getYScroll()==saved.scroll and pane.mode==saved.mode and pane:getIsVisible()==saved.paneVisible,'pane state not restored')
end
local function capture()
 assert(not isClient()and not isServer(),'storage session is SP only')
 assert(idle(),'foreign timed actions before storage phase')
 local player=getPlayer();local inventory=player:getInventory()
 return {player=player,inventory=inventory,items=identity(inventory),weight=inventory:getCapacityWeight(),
  god=player:isGodMod(),ghost=player:isGhostMode(),primary=player:getPrimaryHandItem(),secondary=player:getSecondaryHandItem(),
  x=player:getX(),y=player:getY(),z=player:getZ(),mode=CleanUI_isCleanInventoryUIEnabled(),
  guide=SurvivalGuide and SurvivalGuide.instance,guideVisible=SurvivalGuide and SurvivalGuide.instance and SurvivalGuide.instance:getIsVisible(),
  pages={capturePage(getPlayerInventory(0)),capturePage(getPlayerLoot(0))}}
end
local function restore(state)
 assert(idle(),'pending timed actions at storage cleanup');assert(getPlayer()==state.player,'storage actor changed')
 conserved(state)
 local player=state.player
 -- Neither phase moves/equips/heals the player; unexpected changes quarantine.
 assert(player:getPrimaryHandItem()==state.primary and player:getSecondaryHandItem()==state.secondary,'equipment changed')
 assert(player:getX()==state.x and player:getY()==state.y and player:getZ()==state.z,'player moved')
 CleanUI_setCleanInventoryUIEnabled(state.mode)
 restorePage(state.pages[1],getPlayerInventory(0));restorePage(state.pages[2],getPlayerLoot(0))
 player:setGodMod(state.god);player:setGhostMode(state.ghost)
 if state.guide then assert(SurvivalGuide.instance==state.guide,'guide replaced');state.guide:setVisible(state.guideVisible)end
 assert(player:isGodMod()==state.god and player:isGhostMode()==state.ghost,'player flags not restored')
 return true
end
function M.context()return assert(current,'storage fixture outside its phase')end
function M.run(config)
 assert(#config.cases==2 and config.cases[1]=='inventory-work'and config.cases[2]=='inventory-freshness','fresh work baseline must run first')
 local messages={}
 local function options(server)
  return {cases=config.cases,user=server and 'server'or'client1',actors={'client1'},module='StorageProfileFixture',
   actor=function()return 'client1'end,localPlayerReady=function(player)return player:getCurrentSquare()~=nil end,
   transport=function(module,command,player,args,authority)
    messages[#messages+1]={module=module,command=command,player=player or getPlayer(),args=args,authority=authority}
   end}
 end
 local function authorityFactory(context)
  context.cleanup=function()context.receipt={case=context.case,epoch=context.epoch};return true end
 end
 local modules={['inventory-work']='ZZInventoryWorkProfile',['inventory-freshness']='ZZInventoryFreshness'}
 local authority,client
 local function clientFactory(context)
  local state=capture();current=context;context.quarantine=function(reason)client.quarantine(reason)end
  print('[STORAGE_SESSION] BEGIN case='..context.case..' epoch='..context.epoch)
  -- Menu/world creation is owned once by the bootstrap, never by a case.
  context.events.OnMainMenuEnter={Add=function()end};context.events.OnPreUIDraw={Add=function()end}
  context.readyToClean=idle
  context.cleanup=function()
   assert(restore(state));current=nil
   for _,handlers in pairs(context.handlers)do for index=#handlers,1,-1 do handlers[index]=nil end end
   print('[STORAGE_SESSION] RESTORED case='..context.case..' epoch='..context.epoch..' inventory=true weight=true ui=true player=true observers=true queue=true rpc=none time=forward')
   return true
  end
  context.clean=function(receipt)
   assert(receipt.case==context.case and receipt.epoch==context.epoch,'wrong cleanup receipt');conserved(state);return idle()
  end
  require(modules[context.case])()
 end
 local authorities,clients={},{}
 for _,case in ipairs(config.cases)do authorities[case]=authorityFactory;clients[case]=clientFactory end
 authority=create(options(true),authorities,true);client=create(options(false),clients,false)
 authority.prepare();client.prepare()
 return function()
  local pending=messages;messages={}
  for _,entry in ipairs(pending)do
   local target=entry.authority and client or authority
   local ok,reason=pcall(target.command,entry.module,entry.command,entry.authority and nil or entry.player,entry.args)
   if not ok then target.quarantine(reason)end
  end
  authority.tick();client.tick()
 end
end
return M
