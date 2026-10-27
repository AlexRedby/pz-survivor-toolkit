local config=require 'QueueTestSelection'
if config.suite~='torch-refill'then return end
local F=require 'TorchRefillFixture'
local JSON=require 'QueueHealthEvents'
local Return=require 'PZSurvivorToolkit/TorchRefillReturn'
local Session=require 'TorchRefillSession'
local function factory(context)
assert(#ISTimedActionQueue.getTimedActionQueue(getPlayer()).queue==0,'preexisting actions prevent clean fixture baseline')
local baseline=F.clientBaseline(getPlayer())
local started,done,packet,state,authority,since,craft,seenCraft,placed,settleAt,drainedAt,returnWait,returnEntry,waitSeen,lastReceipt,localReceipt,restored,baselineAck
local phase='prepare'
local function emit(event,data)print('[TORCH_REFILL] '..event..' '..JSON.encode(data))end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function request(command)context.send(command,{})end
local function find(context,item)
 for _,option in ipairs(context.options or {})do
  if option.onSelect==ISInventoryPaneContextMenu.OnNewCraft and option.target==item
   and option.param1 and option.param1:getScriptObjectFullType()=='Base.RefillBlowTorch'then return option end
  if option.subOption then local sub=context:getSubMenu(option.subOption);local found=sub and find(sub,item);if found then return found end end
 end
end
context.observeProduct=function(module,command,args)
 if module=='PZSurvivorToolkitTorchRefill'and command=='Refilled'and packet and args.sourceID==packet.sourceID then
  lastReceipt=args;emit('REFILLED',args)
 end
end
context.events.OnServerCommand.Add(function(module,command,args)
 if command=='Prepared'then
  assert(not packet and args.case==context.case and args.epoch==context.epoch,'unexpected prepared phase');packet=args
 elseif command=='BaselineRestored'then
  assert(restored and not baselineAck,'unexpected baseline acknowledgement');baselineAck=true
 elseif command=='Verified'then
  assert(phase=='verify'and not authority,'unexpected authority receipt');authority=args
 else error('unexpected fixture reply '..tostring(command))end
end)
context.events.OnGameStart.Add(function()started=true end)
context.readyToClean=function()return #queue().queue==0 and authority~=nil and baselineAck==true end
context.cleanup=function()
 assert(context.readyToClean(),'actions or authority RPC pending')
 return F.restore(baseline)
end
local cleaned=false
context.clean=function(receipt)
 local ready,reason=F.clean(receipt,state,baseline.items)
 if ready and not cleaned then
  F.restore(baseline)
  cleaned=true;emit('CLEANUP',{case=context.case,epoch=context.epoch,role='client1',ownedRemoved=true,baselineRestored=true})
  emit('COMPLETE',{case=context.case,epoch=context.epoch,role='client1'})
 end
 return ready,reason
end
context.events.OnTick.Add(function()
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
   state=state or(packet and F.resolve(packet,getPlayer(),baseline.items,Session.localState and Session.localState()))
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
   -- Use the native selector before invoking its callback: foreign fuel must never be consumed.
   local logic=HandcraftLogic.new(getPlayer(),nil,nil)
   logic:setIsoObject(logic:findCraftSurface(getPlayer(),2));logic:setContainers(containers)
   logic:setRecipeFromContextClick(option.param1,torch)
   assert(logic:canPerformCurrentRecipe(),'native input selection unavailable')
   local inputs=logic:getRecipeData():getAllInputItems();local selected={}
   for index=0,inputs:size()-1 do
    local id=inputs:get(index):getID()
    assert((id==packet.sourceID or id==packet.tankID)and not selected[id],'native selector would borrow unrelated/repeated input')
    selected[id]=true
   end
   assert(inputs:size()==2 and selected[packet.sourceID]and selected[packet.tankID],'native selector changed fixture identities')
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
    emit('RETURN_DIAGNOSTIC',{problem=problem,refilled=lastReceipt or {},
     sourceAccess=getPlayer():canAccessContainer(state.source),actorX=getPlayer():getX(),actorY=getPlayer():getY(),
     trunkX=area and area:getX()or -1,trunkY=area and area:getY()or -1,
     captured=returnWait~=nil,outputID=returnEntry and returnEntry.outputID or -1,
     waitPresent=returnWait and queue():indexOf(returnWait)~=-1 or false,
     sourceSame=returnEntry and returnEntry.source==state.source or false,
     cancelled=returnWait and returnWait.toolkitQueueOperation and returnWait.toolkitQueueOperation.toolkitCancelled==true or false})
    error(problem)
   end
   assert(seenCraft,'native crafting was never observed running')
   localReceipt=receipt;emit('LOCAL',receipt)
   emit('NATIVE',{case=context.case,epoch=context.epoch,selectedID=packet.sourceID,recipe='Base.RefillBlowTorch',
    nativeDuration=true,craftObserved=true,queueDrained=true,duration=craft:getDuration()})
   phase='verify';since=getTimestampMs();request('Verify')
  elseif phase=='verify'then
   assert(getTimestampMs()-since<25000,'authority timeout')
   if authority then
    for key,value in pairs(localReceipt)do assert(authority[key]==value,'authority mismatch '..key)end
    if isClient()then assert(lastReceipt and lastReceipt.outputID==localReceipt.outputID,'product RPC not drained')end
    F.restore(baseline);restored=true;phase='restore';since=getTimestampMs()
    context.send('RestoreBaseline',{x=baseline.x,y=baseline.y,z=baseline.z,
     primaryID=baseline.primary and baseline.primary:getID()or -1,secondaryID=baseline.secondary and baseline.secondary:getID()or -1})
   end
  elseif phase=='restore'then
   assert(getTimestampMs()-since<15000,'authority baseline acknowledgement timeout')
   if baselineAck then done=true;context.finish(true)end
  end
 end)
 if not ok then done=true;error('torch '..phase..' '..tostring(reason))end
end)

end
local tick,session
Events.OnGameStart.Add(function()
 if config.kind=='sp'then tick=Session.singleplayer(config,factory)
 else
  session=Session.create(config,factory,false);session.prepare();tick=session.tick
 end
end)
Events.OnServerCommand.Add(function(module,command,args)
 if session then
  local ok,reason=pcall(session.command,module,command,nil,args)
  if not ok then session.quarantine(reason)end
 end
end)
Events.OnTick.Add(function()if tick then tick()end end)
