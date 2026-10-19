local config=require 'QueueTestSelection'
local Fixture=require 'QuartermasterDistributionFixture'
local Rules=require 'PZSurvivorToolkit/QuartermasterTagRuleClient'
local JSON=require 'QueueHealthEvents'
local started,done,since,phase=false,false,0,'prepare'
local state,packet,boxes,point,saved,receipt,cleaned,arrived,designatedAt
local cleanupRetry=0
local playerUpdates=0
local stagingWalk,stagingComplete,stagingTarget
local walked,loaded,deposited=false,false,{}
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function stageWalk(x)
 stagingTarget=assert(getCell():getGridSquare(x,point.y,point.z));stagingComplete=false
 stagingWalk=LootSorter.WalkAction:new(getPlayer(),stagingTarget)
 stagingWalk:setOnComplete(function()stagingComplete=true end)
 ISTimedActionQueue.add(stagingWalk)
end
local function stageArrived()
 if #queue().queue>0 or getPlayer():hasTimedActions()then return false end
 assert(stagingComplete and getPlayer():getCurrentSquare()==stagingTarget,
  'preparation walk did not arrive: result='..tostring(stagingWalk.result))
 return true
end
Events.OnPlayerUpdate.Add(function(player)
 if started and player==getPlayer()then playerUpdates=playerUpdates+1 end
end)
Events.OnServerCommand.Add(function(module,command,value)
 if module~='QuartermasterDistributionTest'then return end
 if command=='Prepared'then packet=value elseif command=='Verified'then receipt=value elseif command=='Cleaned'then cleaned=true end
end)
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs();getPlayer():setGodMod(true);getPlayer():setGhostMode(true)
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
local function tick()
 local player=getPlayer()
 if phase=='prepare'then
  point=Fixture.place(player)
  if isClient()then sendClientCommand('QuartermasterDistributionTest','Prepare',point)
  else state=Fixture.prepare(player,point);packet=Fixture.descriptor(state)end
  phase='resolve'
 elseif phase=='resolve'then
  -- Allow initial character/map updates before starting navigation around new crates.
  if not packet or playerUpdates<30 then return end
  boxes=Fixture.resolve(packet);if not boxes then return end
  print('[QM_DISTRIBUTION] PREPARED '..JSON.encode(packet))
  LootSorter.setBoxItems(boxes[2],0,{[boxes[1]:getContainer():getItemById(packet.ids[1]):getDisplayName()]=true})
  stageWalk(point.x+4)
  phase='configure'
 elseif phase=='configure'then
  if not stageArrived()then return end
  arrived=arrived or getTimestampMs();if getTimestampMs()-arrived<500 then return end
  Rules.saveBox(boxes[3],0,{mode='all',include={'food','perishable'},exclude={'meat'}},player,function(verdict)
   assert(verdict=='ok','tag designation rejected '..tostring(verdict));saved=true;designatedAt=getTimestampMs()
  end)
  phase='return'
 elseif phase=='return'then
  if not saved then return end
  stageWalk(point.x)
  phase='ready'
 elseif phase=='ready'then
  if not stageArrived()then return end
  if not saved or not LootSorter.isRegistrySynced() or not LootSorter.arePresetsSynced()then return end
  local targets=LootSorter.gatherBoxes(player);local found={}
  for _,entry in ipairs(targets or {})do
   for i=2,3 do if entry.obj==boxes[i]then found[i]=true end end
  end
  if not found[2]or not found[3]then return end
  local loot=assert(getPlayerLoot(0));loot:refreshBackpacks();loot.inventoryPane:refreshContainer()
  local controls=assert(loot.controlsUI)
  local handler=controls:checkHandler(ISLootWindowObjectControlHandler_LootSorterDistribute,boxes[1],boxes[1]:getContainer())
  assert(handler:shouldBeVisible(),'distribution control hidden')
  local button=handler:getControl();local before=LootSorter._sortRunSeq or 0
  LootSorter.DEBUG=true;button.onclick(button.target,button)
  assert((LootSorter._sortRunSeq or 0)>before and #queue().queue>0,'distribution did not start')
  phase='sorting'
 elseif phase=='sorting'then
  local current=queue().current
  if math.abs(player:getX()-(point.x+0.5))>1 then walked=true end
  if current and current.Type=='LootSorterDeposit'and current:isStarted()and current:getJobDelta()>0 then
   if current.srcContainer==boxes[1]:getContainer()then loaded=true end
   for i=2,3 do if current.destContainer==boxes[i]:getContainer()then deposited[i]=true end end
  end
  if #queue().queue~=0 or player:hasTimedActions()then return end
  local localReceipt=Fixture.receipt(player,boxes,packet.ids,state and state.original)
  if not localReceipt then return end
  assert(walked and loaded and deposited[2]and deposited[3],'missing real walk/pickup/deposit progress')
  print('[QM_DISTRIBUTION] LOCAL '..JSON.encode(localReceipt))
  if isClient()then sendClientCommand('QuartermasterDistributionTest','Verify',{})
  else receipt=localReceipt;print('[QM_DISTRIBUTION] AUTHORITY '..JSON.encode(receipt))end
  phase='verified'
 elseif phase=='verified'then
  if not receipt then return end
  -- Respect native delayed registry-add grace before removing designations.
  if getTimestampMs()-designatedAt<LootSorter.ADD_GRACE_MS+1000 then return end
  LootSorter.setBoxItems(boxes[2],0,{})
  saved=false;Rules.saveBox(boxes[3],0,{mode='all',include={},exclude={}},player,function(verdict)
   assert(verdict=='ok','tag cleanup rejected');saved=true
  end)
  phase='cleanup'
 elseif phase=='cleanup'then
  if not saved then return end
  local registry=LootSorter.getRegistry()
  local keys={}
  for i=2,3 do
   local sq=boxes[i]:getSquare();local key=sq:getX()..','..sq:getY()..','..sq:getZ()
   if registry[key]then keys[#keys+1]=key end
  end
  if #keys>0 then
   -- Native object ModData and coordinate removal arrive on separate channels.
   if getTimestampMs()-cleanupRetry>1000 then LootSorter.removeCoords({keys=keys});cleanupRetry=getTimestampMs()end
   return
  end
  if isClient()then sendClientCommand('QuartermasterDistributionTest','Cleanup',{})else Fixture.cleanup(state);cleaned=true end
  phase='cleaned'
 elseif phase=='cleaned'and cleaned then
  print('[QM_DISTRIBUTION] COMPLETE moved=2 retained=2 walking=true pickup=true destinations=2 favorite=true')
  done=true
 end
end
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,problem=pcall(function()assert(getTimestampMs()-since<180000,'distribution timeout phase='..phase);tick()end)
 if not ok then done=true;print('[QUEUE_TEST] FAIL distribution '..tostring(problem))end
end)
