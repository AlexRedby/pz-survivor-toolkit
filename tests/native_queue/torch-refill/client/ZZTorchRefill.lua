local config=require 'QueueTestSelection'
if config.suite~='torch-refill'then return end
local F=require 'TorchRefillFixture'
local JSON=require 'QueueHealthEvents'
local Return=require 'PZSurvivorToolkit/TorchRefillReturn'
local started,done,packet,state,authority,since,craft,seenCraft,placed,settleAt,drainedAt,returnWait,returnEntry,waitSeen,lastReceipt
local phase='prepare'
local function emit(event,data)print('[TORCH_REFILL] '..event..' '..JSON.encode(data))end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function request(command)
 if isClient()then sendClientCommand(F.module,command,{});return end
 if command=='Prepare'then state=F.prepare(getPlayer());packet=state.packet;emit('PREPARED',packet)
 else authority=assert(F.receipt(state));emit('AUTHORITY',authority)end
end
local function find(context,item)
 for _,option in ipairs(context.options or {})do
  if option.onSelect==ISInventoryPaneContextMenu.OnNewCraft and option.target==item
   and option.param1 and option.param1:getScriptObjectFullType()=='Base.RefillBlowTorch'then return option end
  if option.subOption then local sub=context:getSubMenu(option.subOption);local found=sub and find(sub,item);if found then return found end end
 end
end
Events.OnServerCommand.Add(function(module,command,args)
 if module=='PZSurvivorToolkitTorchRefill'and command=='Refilled'then
  lastReceipt=args;emit('REFILLED',args);return
 end
 if module~=F.module then return end
 if command=='Prepared'then packet=args elseif command=='Verified'then authority=args end
end)
Events.OnGameStart.Add(function()
 started=true;getPlayer():setGodMod(true);getPlayer():setGhostMode(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
Events.OnTick.Add(function()
 if not started or done or not getPlayer()or not getPlayer():getCurrentSquare()then return end
 local ok,reason=pcall(function()
  if phase=='prepare'then
   if config.kind=='mp'and(not isClient()or getPlayer():getOnlineID()<0)then return end
   assert(Return.install(),'torch return wrapper unavailable')
   assert(not getPlayer():isTimedActionInstant(),'instant action player invalidates native duration')
   request('Prepare');phase='resolve';since=getTimestampMs()
  elseif phase=='resolve'then
   if packet and not placed then
    if packet.case~='root-retained'then
     local player=getPlayer();player:teleportTo(math.floor(packet.x),math.floor(packet.y),0)
     player:setX(packet.x);player:setY(packet.y);player:setNextX(packet.x);player:setNextY(packet.y)
     player:setLastX(packet.x);player:setLastY(packet.y)
    end
    placed=true
   end
   state=state or(packet and F.resolve(packet,getPlayer()))
   assert(getTimestampMs()-since<30000,'fixture replication timeout')
   if not state then return end
   if not settleAt then settleAt=getTimestampMs()+1500 end
   if getTimestampMs()<settleAt then return end
   local torch=assert(state.source:getItemById(packet.sourceID))
   local page=packet.case=='root-retained'and getPlayerInventory(0)or getPlayerLoot(0)
   page:refreshBackpacks();page:setForceSelectedContainer(state.source)
   local containers=ISInventoryPaneContextMenu.getContainers(getPlayer())
   if not containers:contains(state.source)then return end
   local context=assert(ISInventoryPaneContextMenu.createMenu(0,packet.case=='root-retained',{torch},150,150,page.inventoryPane))
   local option=find(context,torch)
   if not option then
    local rows={}
    local function inspect(menu)
     for _,row in ipairs(menu.options or {})do
      rows[#rows+1]={name=tostring(row.name),callback=tostring(row.onSelect),
       newCraft=row.onSelect==ISInventoryPaneContextMenu.OnNewCraft,targetSelected=row.target==torch,
       recipe=row.param1 and type(row.param1)=='userdata'and tostring(row.param1)or tostring(row.param1)}
      if row.subOption then local sub=menu:getSubMenu(row.subOption);if sub then inspect(sub)end end
     end
    end
    inspect(context);emit('MENU_DIAGNOSTIC',{rows=rows,canAccess=getPlayer():canAccessContainer(state.source),
     nativeContainers=containers:size()})
   end
   assert(option,'native refill menu option missing')
   assert(not option.notAvailable,'native refill unavailable')
   option.onSelect(option.target,option.param1,option.param2,option.param3,option.param4,option.param5,option.param6)
   context:hideAndChildren()
   local rows={}
   for _,action in ipairs(queue().queue)do
    local command=action.toolkitQueueCommand
    local entry=command and command.snapshot
    local ids={}
    for _,items in pairs(action.manualInputs or {})do
     for index=0,items:size()-1 do ids[#ids+1]=items:get(index):getID()end
    end
    if entry and entry.id==packet.sourceID then returnWait=action;returnEntry=entry end
    rows[#rows+1]={type=action.Type,manualIDs=ids,returnWait=entry and entry.id==packet.sourceID or false}
    if action.Type=='ISHandcraftAction'and action.craftRecipe:getScriptObjectFullType()=='Base.RefillBlowTorch'then
     assert(not craft,'duplicate refill craft');craft=action
     assert(action:getDuration()==action.craftRecipe:getTime(getPlayer())*5 and action:getDuration()>1,'native duration changed')
    end
   end
   emit('ENQUEUED',{actions=rows,selectedID=packet.sourceID})
   assert(craft,'native craft was not queued');phase='running';since=getTimestampMs()
  elseif phase=='running'then
   if queue().current==craft and craft.action and craft:isStarted()then seenCraft=true end
   assert(getTimestampMs()-since<120000,'refill/return timed out')
   if returnWait and queue().current==returnWait and not waitSeen then
    waitSeen=true;emit('RETURN_WAIT',{present=queue():indexOf(returnWait)~=-1,
     current=true,outputID=returnEntry.outputID or -1,sourceSame=returnEntry.source==state.source,
     cancelled=returnWait.toolkitQueueOperation and returnWait.toolkitQueueOperation.toolkitCancelled==true or false})
   end
   if #queue().queue~=0 then return end
   local receipt,problem=F.receipt(state)
   if not receipt then
    drainedAt=drainedAt or getTimestampMs()
    if getTimestampMs()-drainedAt<10000 then return end
    local area=state.vehicle and state.vehicle:getAreaCenter(state.vehicle:getPartById('TruckBed'):getArea())
    emit('RETURN_DIAGNOSTIC',{items=F.diagnostic(state),problem=problem,refilled=lastReceipt or {},
     sourceAccess=getPlayer():canAccessContainer(state.source),actorX=getPlayer():getX(),actorY=getPlayer():getY(),
     trunkX=area and area:getX()or -1,trunkY=area and area:getY()or -1,
     captured=returnWait~=nil,outputID=returnEntry and returnEntry.outputID or -1,
     waitPresent=returnWait and queue():indexOf(returnWait)~=-1 or false,
     sourceSame=returnEntry and returnEntry.source==state.source or false,
     cancelled=returnWait and returnWait.toolkitQueueOperation and returnWait.toolkitQueueOperation.toolkitCancelled==true or false})
    error(problem)
   end
   assert(seenCraft,'native crafting was never observed running')
   emit('LOCAL',receipt)
   emit('NATIVE',{selectedID=packet.sourceID,recipe='Base.RefillBlowTorch',
    nativeDuration=true,craftObserved=true,queueDrained=true,duration=craft:getDuration()})
   phase='verify';since=getTimestampMs();request('Verify')
  elseif phase=='verify'then
   assert(getTimestampMs()-since<25000,'authority timeout')
   if authority then done=true;emit('COMPLETE',{case=config.cases[1],role='client1'})end
  end
 end)
 if not ok then done=true;emit('FAIL',{phase=phase,error=tostring(reason)})end
end)
