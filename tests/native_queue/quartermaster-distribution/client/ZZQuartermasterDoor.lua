local config=require 'QueueTestSelection'
if config.cases[1]~='barricaded-door' then return end
local F=require 'QuartermasterDoorFixture'
local JSON=require 'QueueHealthEvents'
local started,done,since,phase=false,false,0,'prepare'
local point,state,packet,authority,cleaned
local updates,walked,detour=0,false,false
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function emit(event,value)print('[QM_DOOR] '..event..' '..JSON.encode(value))end
Events.OnServerCommand.Add(function(module,command,value)
 if module~=F.module then return end
 if command=='Prepared'then assert(not packet,'duplicate door preparation reply');packet=value
 elseif command=='Verified'then assert(not authority,'duplicate door authority reply');authority=value
 elseif command=='Cleaned'then assert(not cleaned,'duplicate door cleanup reply');cleaned=value end
end)
local function dispatch()
 local loot=assert(getPlayerLoot(0));loot:refreshBackpacks();loot.inventoryPane:refreshContainer()
 local controls=assert(loot.controlsUI)
 local handler=controls:checkHandler(ISLootWindowObjectControlHandler_LootSorterDistribute,state.boxes[1],state.boxes[1]:getContainer())
 assert(handler:shouldBeVisible(),'distribution control hidden')
 local button=handler:getControl();local before=LootSorter._sortRunSeq or 0
 LootSorter.DEBUG=true;button.onclick(button.target,button)
 assert((LootSorter._sortRunSeq or 0)>before and #queue().queue>0,'distribution did not start')
end
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs();getPlayer():setGodMod(true);getPlayer():setGhostMode(true)
 getCore():setOptionAutoDrink(false);getPlayer():setAutoDrink(false)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
Events.OnPlayerUpdate.Add(function(player)
 if started and player==getPlayer()then updates=updates+1 end
end)
local function tick()
 local player=getPlayer()
 if phase=='prepare'then
  if updates<30 then return end
  point=F.place(player)
  if isClient()then sendClientCommand(F.module,'Prepare',point)
  else state=F.prepare(player,point);packet=F.descriptor(state)end
  phase='resolve'
 elseif phase=='resolve'then
  if not packet then return end
  if not state then state=F.resolve(packet);if not state then return end end
  assert(#state.owned==15 and #state.ids==2,'door fixture descriptor differs')
  emit('PREPARED',{ids=state.ids});phase='settle';updates=0
 elseif phase=='settle'then
  if updates<60 or not LootSorter.isRegistrySynced()or not LootSorter.arePresetsSynced()then return end
  local found={}
  for _,entry in ipairs(LootSorter.gatherBoxes(player))do
   for index=2,3 do if entry.obj==state.boxes[index]then found[index]=true end end
  end
  if not found[2]or not found[3]then return end
  assert(not state.doors[3]:IsOpen(),'ordinary detour door was opened before distribution')
  dispatch();phase='sorting'
 elseif phase=='sorting'then
  local current=queue().current
  if current and current.Type=='LootSorterWalkAction'and current:isStarted()then walked=true end
  if player:getY()>point.y+2 and player:getY()<point.y+4 then detour=true end
  assert(not state.doors[0]:IsOpen()and state.doors[0]:isBarricaded()
   and state.barricade:getNumPlanks()==state.planks and state.barricade:getHealth()==state.originalHealth,
   'routing opened/damaged the barricaded door')
  if #queue().queue>0 or player:hasTimedActions()then return end
  assert(walked and detour,'native walk did not take the ordinary-door detour')
  local result=F.receipt(player,state);if not result then return end
  local localResult={};for key,value in pairs(result)do localResult[key]=value end
  localResult.nativeWalking=true;localResult.detour=true;emit('RESULT',localResult)
  if isClient()then sendClientCommand(F.module,'Verify',{})
  else authority=result;emit('AUTHORITY',result)end
  phase='verified'
 elseif phase=='verified'then
  if not authority then return end
  assert(authority.ids[1]==state.ids[1]and authority.ids[2]==state.ids[2]and authority.moved==2
   and authority.conserved and authority.normalDoorOpened and authority.barricadedDoorClosed and authority.barricadeIntact,
   'door authority reply differs')
  if isClient()then sendClientCommand(F.module,'Cleanup',{});phase='cleaned'
  else
   cleaned=F.cleanup(state)
   if cleaned then phase='cleaned'end
  end
 elseif phase=='cleaned'and cleaned then
  assert(cleaned.objects==15,'door cleanup did not acknowledge all owned objects')
  -- Server removal and registry replication travel independently of the cleanup ACK.
  for _,object in ipairs(state.owned)do if object:getObjectIndex()>=0 then return end end
  local registry=LootSorter.getRegistry()
  for index=2,3 do
   local target=packet.objects[packet.boxes[index]]
   local key=math.floor(target.x)..','..math.floor(target.y)..','..math.floor(target.z)
   if registry[key]then return end
  end
  emit('CLEANUP',{objects=15,localRemoved=true,registryCleared=true})
  emit('COMPLETE',{case='barricaded-door'});done=true
 end
end
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,problem=pcall(function()assert(getTimestampMs()-since<240000,'door distribution timeout phase='..phase);tick()end)
 if not ok then done=true;print('[QM_DOOR] FAIL '..tostring(problem))end
end)
