require 'PZSurvivorToolkit/ActionQueuePanel'
local F=require 'QueueBulkReadingFixture'
local JSON=require 'QueueHealthEvents'
local selection=require 'QueueTestSelection'
local started,done,phase=false,false,'prepare'
local packet,state,items,box,authority,since,lastAdd,previousFrame
local profiles,frames,enqueue={}, {}, {}
local added,seenRead=0,false
local function now()return getTimestampMs()end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function samplePhase()return phase=='idle'and 'idle'or phase=='running'and 'running'or nil end
local function pack(...)return {n=select('#',...),...}end
local function measure(name,fn,...)
 local stage=samplePhase();if not stage then return fn(...)end
 local before=now();local result=pack(fn(...));local elapsed=now()-before
 profiles[stage]=profiles[stage]or {};local value=profiles[stage][name]or {calls=0,totalMs=0,maxMs=0}
 profiles[stage][name]=value;value.calls=value.calls+1;value.totalMs=value.totalMs+elapsed;value.maxMs=math.max(value.maxMs,elapsed)
 return unpack(result,1,result.n)
end
local function wrap(owner,name,label)
 local original=owner and owner[name];if type(original)~='function'then return end
 owner[name]=function(...)return measure(label or name,original,...)end
end
local function profile()
 local panel=PZSurvivorToolkit.ActionQueuePanel
 wrap(panel,'drawRow')
 if selection.options and selection.options.profile_queue_hover then
  local update=panel.update
  panel.update=function(self,...)
   local result=measure('update',update,self,...)
   local list=self.list
   -- Drive native widget hit testing without moving the user's physical mouse.
   -- Only the isolated fixture's own queue list is affected; no edits are issued.
   if not list.bulkReadingHover then
    list.bulkReadingHover=true
    list.isMouseOver=function()return phase=='running'end
    list.getMouseX=function()return list:cancelX()+12 end
    list.getMouseY=function()return list:topOfItem(list.items[2]and 2 or 1)+16 end
   end
   return result
  end
 else wrap(panel,'update')end
 local refresh=panel.refresh;Events.OnTickEvenPaused.Remove(refresh)
 panel.refresh=function(...)return measure('refresh',refresh,...)end;Events.OnTickEvenPaused.Add(panel.refresh)
 local policy=PZSurvivorToolkit.ActionQueuePolicy
 for _,name in ipairs({'evaluateMove','evaluateCancel','previewMove','previewCancel'})do wrap(policy,name)end
end
local function summary(values)
 table.sort(values);local sum=0;for _,value in ipairs(values)do sum=sum+value end
 return {samples=#values,meanMs=#values>0 and sum/#values or 0,p95Ms=values[math.max(1,math.ceil(#values*.95))]or 0,maxMs=values[#values]or 0}
end
local function report()
 local frameReport={};for stage,values in pairs(frames)do frameReport[stage]=summary(values)end
 print('[BULK_READING] PROFILE '..JSON.encode({frames=frameReport,calls=profiles,enqueue=enqueue}))
end
local function request(command)
 if isClient()then sendClientCommand('BulkReadingTest',command,{});return end
 if command=='Prepare'then state=F.prepare(getPlayer());packet=F.descriptor(state)
  print('[BULK_READING] PREPARED '..JSON.encode(packet))
 else authority=assert(F.receipt(state));print('[BULK_READING] AUTHORITY '..JSON.encode(authority))end
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~='BulkReadingTest'then return end
 if command=='Prepared'then packet=args elseif command=='Verified'then authority=args end
end)
Events.OnGameStart.Add(function()started=true end)
Events.OnTickEvenPaused.Add(function()
 if not started or done then return end
 local stage=samplePhase();local timestamp=now()
 if stage and previousFrame and previousFrame.stage==stage then
  frames[stage]=frames[stage]or {};frames[stage][#frames[stage]+1]=timestamp-previousFrame.time
 end
 previousFrame={stage=stage,time=timestamp}
end)
Events.OnTick.Add(function()
 if not started or done or not getPlayer()or not getPlayer():getCurrentSquare()then return end
 local ok,problem=pcall(function()
  if phase=='prepare'then
   if selection.kind=='mp'and(not isClient()or getPlayer():getOnlineID()<0)then return end
   request('Prepare');phase='resolve';since=now()
  elseif phase=='resolve'then
   if packet then box,items=F.resolve(packet)end
   if not items then assert(now()-since<30000,'fixture replication timeout');return end
   state=state or {player=getPlayer(),box=box,ids=packet.ids}
   local inventory,loot=getPlayerInventory(0),getPlayerLoot(0)
   inventory:setVisible(true);inventory.isCollapsed=false;inventory:clearMaxDrawHeight();inventory:setPinned()
   loot:setVisible(true);loot.isCollapsed=false;loot:clearMaxDrawHeight();loot:setPinned();loot:refreshBackpacks()
   loot:selectButtonForContainer(box:getContainer());loot:setForceSelectedContainer(box:getContainer(),700000)
   assert(loot.inventoryPane.inventory==box:getContainer(),'dresser is not in native loot pane')
   profile();phase='idle';since=now()
  elseif phase=='idle'and now()-since>=5000 then
   local batch={};for index=1,5 do batch[index]=items[index]end
   phase='running';local before=now();ISInventoryPaneContextMenu.onLiteratureItems(batch,0)
   enqueue[#enqueue+1]={count=5,elapsedMs=now()-before,actions=#queue().queue};added=5;lastAdd=now();since=now()
  elseif phase=='running'then
   local current=queue().current
   if current and current.Type=='ISReadABook'and current.action and current:isStarted()then seenRead=true end
   if added<#items and now()-lastAdd>=1000 then
    added=added+1;local before=now();ISInventoryPaneContextMenu.onLiteratureItems({items[added]},0)
    enqueue[#enqueue+1]={count=added,elapsedMs=now()-before,actions=#queue().queue};lastAdd=now()
   end
   assert(now()-since<650000,'bulk reading timed out')
   if added==#items and #queue().queue==0 then
    assert(seenRead,'no native reading observed')
    local receipt,reason=F.receipt(state);assert(receipt,reason)
    print('[BULK_READING] LOCAL '..JSON.encode(receipt));report();phase='verify';since=now();request('Verify')
   end
  elseif phase=='verify'then
   assert(now()-since<25000,'authority timeout')
   if authority then
    assert(authority.count==F.count,'authority count mismatch')
    done=true;print('[BULK_READING] COMPLETE')
   end
  end
 end)
 if not ok then done=true;print('[QUEUE_TEST] FAIL bulk reading '..tostring(problem))end
end)
