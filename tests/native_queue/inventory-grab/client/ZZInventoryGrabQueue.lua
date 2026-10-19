require 'PZSurvivorToolkit/ActionQueuePanel'
require 'TimedActions/ISWearClothing'
require 'TimedActions/ISUnequipAction'
local Fixture=require 'QueueInventoryGrabFixture'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local started,done=false,false
local step,failed,phase,since,idle=1,0,'prepare',0,0
local ids,state,authority,previous,receipt,command,observed,quietSince,previousBag
local function case()return config.cases[step]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function emit(row)row.suite,row.kind,row.mode,row.actor='inventory-grab',config.kind,config.mode,'client1';JSON.emit(row)end
local function trace(event,row)row=row or {};row.event=event;row.case=case();print('[INVENTORY_GRAB_TEST] TRACE '..JSON.encode(row))end
local function request(name)
 if isClient()then sendClientCommand('InventoryGrabTest',name,{case=case(),targetId=command and command.targetId});return end
 if name=='Prepare'then authority=Fixture.prepare(getPlayer(),case(),previous);previous=nil;ids=authority.ids
  print('[INVENTORY_GRAB_TEST] PREPARED '..JSON.encode(ids))
 else receipt=assert(Fixture.receipt(authority,command.targetId));print('[INVENTORY_GRAB_TEST] VERIFIED '..JSON.encode(receipt))end
end
Events.OnServerCommand.Add(function(module,name,value)
 if module~='InventoryGrabTest'then return end
 assert(name~='Failed',value.error)
 if name=='Prepared'then ids=value elseif name=='Verified'then receipt=value end
end)
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs();getCore():setOptionPauseOnFocusloss(false)
 getCore():setOptionAutoDrink(false);getPlayer():setAutoDrink(false);getPlayer():setGhostMode(true)
end)
local function dispatch()
 local player=getPlayer();local spec=Fixture.spec(case());local root=player:getInventory()
 local destination=spec.bag and state.bag:getItemContainer()or root
 local source=state.object:getContainer();local inventory=getPlayerInventory(0);local loot=getPlayerLoot(0)
 inventory:refreshBackpacks();inventory:setNewContainer(destination);loot:setNewContainer(source)
 loot:setVisible(true);loot.isCollapsed=false;loot:setMaxDrawHeight(loot.height)
 local pane=loot.inventoryPane;pane:refreshContainer()
 local group
 for _,row in ipairs(pane.itemslist)do if row.items[1]:getID()==ids.bottles[1].id or row.items[1]:getID()==ids.bottles[2].id then group=row;break end end
 assert(group and #group.items==3,'two bottles did not form a native stack')
 pane.collapsed[group.name]=spec.one
 pane:refreshContainer();pane:prerender()
 local selection,index,target
 if spec.one then
  for i,row in ipairs(pane.items)do if not instanceof(row,'InventoryItem')and row.name==group.name then selection={row};index=i;target=row.items[2];break end end
 else
  -- Select an explicit child of the expanded stack, never the duplicated header.
  for i,row in ipairs(pane.items)do if instanceof(row,'InventoryItem')and row:getID()==ids.bottles[2].id then selection={row};index=i;target=row;break end end
 end
 assert(selection and target and target:getContainer()==source,'native inventory row missing')
 pane.selected={[index]=selection[1]}
 assert(source:getCapacityWeight()+destination:getCapacityWeight()>=0 and destination:hasRoomFor(player,target),'destination capacity unavailable')
 assert(math.abs(player:getX()-ids.x)<2 and math.abs(player:getY()-ids.y)<2,'microwave not adjacent')
 command={targetId=target:getID(),selectedRows=1,rowKind=spec.one and 'collapsed-group'or 'expanded-child',
  destination=spec.bag and 'bag'or 'root',menuDispatched=false,transferCount=0,transferProgress=false,
  backpackWorn=player:getClothingItem_Back()==state.bag,queueEmptyBefore=#queue().queue==0 and not player:hasTimedActions(),
  adjacent=true,capacityAvailable=true,nativeDurations=true}
 observed={};local original=ISTimedActionQueue.add
 ISTimedActionQueue.add=function(action)
  trace('enqueue',{actionType=action.Type,itemId=action.item and action.item:getID(),duration=action.maxTime})
  if action.Type=='ISInventoryTransferAction'then
   observed[#observed+1]=action;command.transferCount=command.transferCount+1
   assert(action.item==target and action.srcContainer==source and action.destContainer==destination,'native transfer identity/endpoints differ')
   command.nativeDuration=action.maxTime
  end
  return original(action)
 end
 local ok,problem=pcall(function()
  -- A closed first build also exercises the native pooled-menu reuse path.
  local preview=assert(ISInventoryPaneContextMenu.createMenu(0,false,selection,20,20))
  preview:prerender();preview:closeAll()
  local menu=assert(ISInventoryPaneContextMenu.createMenu(0,false,selection,20,20),'native inventory menu missing')
  command.menuBuilds=2
  local label=getText(spec.one and 'ContextMenu_Grab_one'or 'ContextMenu_Grab')
  local visited={}
  local function choose(current,depth)
   assert(depth<8,'inventory menu recursion too deep')
   if visited[current]then return false end;visited[current]=true
   -- Toolkit organizes during prerender. Search the final tree and keep the exact option identity.
   current:setVisible(true);current:prerender()
   for _,option in ipairs(current.options)do
    if option.name==label and option.onSelect then
     current:prerender()
     local index
     for i,value in ipairs(current.options)do if value==option then index=i;break end end
     assert(index and current.options[index].name==label,'Grab option changed during layout')
     command.callbackFile=getFilenameOfClosure and getFilenameOfClosure(option.onSelect)or 'unavailable'
     command.targetType=type(option.target);command.callbackType=type(option.onSelect)
     command.menuLabel=option.name;command.menuDepth=depth;command.menuIndex=index
     trace('menu-option',{label=label,targetType=command.targetType,callbackFile=command.callbackFile,
      callbackType=command.callbackType,selectedRows=1,depth=depth,index=index,
      notAvailable=option.notAvailable==true,isDisabled=option.isDisabled==true})
     assert(not option.notAvailable and not option.isDisabled,'native Grab option disabled')
     current.mouseOver=index;current:ensureVisible()
     -- onMouseUp dispatches mouseOver; use the content area so native scroll arrows cannot intercept.
     local scroll=current:getScrollHeight()>current:getScrollAreaHeight()
     local y=current.padTopBottom+(scroll and current.scrollIndicatorHgt or 0)
      +current:getScrollAreaHeight()/2-current:getYScroll()
     assert(current.options[current.mouseOver]==option,'dispatch lost exact Grab option')
     current:onMouseUp(5,y)
     command.menuDispatched=true;return true
    end
   end
   for _,option in ipairs(current.options)do if option.subOption then
    local submenu=current:getSubMenu(option.subOption)
    current:displaySubMenu(submenu,option)
    if choose(submenu,depth+1)then return true end
   end end
   return false
  end
  assert(choose(menu,0),'native Grab menu option missing '..label)
 end)
 ISTimedActionQueue.add=original;assert(ok,problem)
 trace('dispatch',command)
end
local function finish()
 local localReceipt=Fixture.receipt(state,command.targetId)
 local reason
 if not localReceipt then reason='client-endpoint-differs'
 elseif JSON.encode(localReceipt)~=JSON.encode(receipt)then
  -- JSON object key order need not match. Compare the exact authoritative item identities and endpoints.
  for i,row in ipairs(receipt.bottles)do local item=localReceipt.bottles[i]
   if item.id~=row.id or item.count~=row.count or item.endpoint~=row.endpoint or math.abs(item.amount-row.amount)>.0001 then reason='client-authority-differs'end
  end
 end
 if command.transferCount~=1 or not command.transferProgress then reason='native-transfer-not-observed'end
 local row={event='case',id=case(),status=reason and 'failed'or 'passed',reason=reason,command=command,
  queueIdle=true,settleMilliseconds=getTimestampMs()-quietSince,clientIdentityVerified=localReceipt~=nil}
 for key,value in pairs(receipt)do row[key]=value end
 emit(row);if reason then failed=failed+1 end
 previous=authority;previousBag=state.bag;step=step+1
 if not case()then
  emit({event='complete',cases=config.cases,expected=#config.cases,performed=step-1,failed=failed,skipped=0})
  print('[INVENTORY_GRAB_TEST] COMPLETE');done=true;return
 end
 ids,state,authority,receipt,command,observed,quietSince=nil,nil,nil,nil,nil,nil,nil
 getPlayerInventory(0):setNewContainer(getPlayer():getInventory());getPlayerLoot(0):setNewContainer(getPlayer():getInventory())
 ISTimedActionQueue.add(ISUnequipAction:new(getPlayer(),previousBag,50));phase='unequipped';since=getTimestampMs()
end
Events.OnTick.Add(function()
 if not started or done or not isIngameState()or not getPlayer()or not getPlayer():getSquare()then return end
 local ok,problem=pcall(function()
  local player=getPlayer();getCore():setOptionAutoDrink(false);player:setAutoDrink(false)
  if getTimestampMs()-since>90000 then error('inventory grab timeout '..phase)end
  idle=(not player:hasTimedActions()and #queue().queue==0)and idle+1 or 0
  if phase=='unequipped'then if idle<10 then return end;assert(not player:isEquipped(previousBag));phase='prepare'end
  if phase=='prepare'then
   if step==1 then emit({event='setup',cases=config.cases,expected=#config.cases,queueEnabled=PZSurvivorToolkit.Settings.actionQueue(),nativeDurations=true})end
   phase='prepared';request('Prepare');return
  elseif phase=='prepared'and ids then
   state=Fixture.resolve(player,ids);if not state then return end
   ISTimedActionQueue.add(ISWearClothing:new(player,state.bag,50));phase='equipped';return
  elseif phase=='equipped'then
   if idle<10 then return end
   assert(player:getClothingItem_Back()==state.bag,'military backpack not worn');dispatch();phase='running';since=getTimestampMs();idle=0;return
  elseif phase=='running'then
   local current=queue().queue[1]
   for _,action in ipairs(observed)do if current==action and action:isStarted()and action:getJobDelta()>0 then
    if not command.transferProgress then trace('transfer-progress',{id=action.item:getID(),duration=action.maxTime})end
    command.transferProgress=true;command.progressDuration=action.maxTime
   end end
   if idle>=10 then
    quietSince=quietSince or getTimestampMs()
    -- P4 restores run after native OnPlayerUpdate. Retain real timers and observe their delayed effects.
    if getTimestampMs()-quietSince>=6000 then phase='receipt';request('Verify')end
   else quietSince=nil end
  elseif phase=='receipt'and receipt then finish()end
 end)
 if not ok then print('[QUEUE_TEST] FAIL inventory grab client '..tostring(problem));done=true end
end)
