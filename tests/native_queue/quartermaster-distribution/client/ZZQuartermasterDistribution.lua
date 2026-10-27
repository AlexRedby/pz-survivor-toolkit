local config=require 'QueueTestSelection'
if config.cases[1]~='sort' then return end
local Fixture=require 'QuartermasterDistributionFixture'
local Rules=require 'PZSurvivorToolkit/QuartermasterTagRuleClient'
local JSON=require 'QueueHealthEvents'
local Books=require 'QuartermasterBooksFixture'
local bookPacket,bookReceipt,bookPicker,bookWalked,bookTransferred
local started,done,since,phase=false,false,0,'prepare'
local state,packet,boxes,point,saved,receipt,cleaned,arrived,designatedAt
local designationPicker,presetEditor,presetGeneration
local pasteRevision,pasteReceipt
local cleanupRetry=0
local playerUpdates=0
local stagingWalk,stagingComplete,stagingTarget
local walked,loaded,deposited=false,false,{}
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function stageWalk(x)
 stagingTarget=assert(getCell():getGridSquare(x,point.y,point.z));stagingComplete=false
 local player=getPlayer()
 print('[QM_DISTRIBUTION] STAGE_START '..JSON.encode({phase=phase,x=player:getX(),y=player:getY(),z=player:getZ(),
  targetX=x,targetY=point.y,targetZ=point.z}))
 stagingWalk=LootSorter.WalkAction:new(getPlayer(),stagingTarget)
 stagingWalk:setOnComplete(function()stagingComplete=true end)
 ISTimedActionQueue.add(stagingWalk)
end
local function stageArrived()
 if #queue().queue>0 or getPlayer():hasTimedActions()then return false end
 assert(stagingComplete and getPlayer():getCurrentSquare()==stagingTarget,
  'preparation walk did not arrive: phase='..phase..' result='..tostring(stagingWalk.result)
  ..' actor='..getPlayer():getX()..','..getPlayer():getY()..','..getPlayer():getZ()
  ..' target='..stagingTarget:getX()..','..stagingTarget:getY()..','..stagingTarget:getZ())
 return true
end
Events.OnPlayerUpdate.Add(function(player)
 if started and player==getPlayer()then playerUpdates=playerUpdates+1 end
end)
Events.OnServerCommand.Add(function(module,command,value)
 if module~='QuartermasterDistributionTest'then return end
 if command=='BooksPrepared'then bookPacket=value elseif command=='BooksVerified'then bookReceipt=value
 elseif command=='Prepared'then packet=value elseif command=='Verified'then receipt=value
 elseif command=='PasteVerified'then pasteReceipt=value elseif command=='Cleaned'then cleaned=true end
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
  stageWalk(point.x+2)
  phase='configure-item'
 elseif phase=='configure-item'then
  if not stageArrived()then return end
  arrived=arrived or getTimestampMs();if getTimestampMs()-arrived<500 then return end
  arrived=nil
  LootSorter.openPicker(boxes[2],0,0)
  designationPicker=assert(LootSorter._picker)
  designationPicker.selectedItems={[boxes[1]:getContainer():getItemById(packet.ids[1]):getDisplayName()]=true}
  designationPicker.priority=5;designationPicker.btnSave.onclick(designationPicker)
  phase='item-saved'
 elseif phase=='item-saved'then
  if LootSorter._picker==designationPicker then return end
  assert(LootSorter.getBoxPriority(boxes[2],0)==5,'item editor lost accepted designation')
  LootSorter.copyDesignation(boxes[2],0)
  stageWalk(point.x+4)
  phase='paste'
 elseif phase=='paste'then
  if not stageArrived()then return end
  arrived=arrived or getTimestampMs();if getTimestampMs()-arrived<500 then return end
  pasteRevision=Rules.getBoxRevision(boxes[3],0)
  assert(LootSorter.pasteDesignation(boxes[3],0),'copy/paste did not start')
  phase='pasted'
 elseif phase=='pasted'then
  if Rules.getBoxRevision(boxes[3],0)<=pasteRevision then return end
  assert(LootSorter.getBoxPriority(boxes[3],0)==5,'copy/paste lost priority')
  if isClient()then sendClientCommand('QuartermasterDistributionTest','VerifyPaste',{})
  else pasteReceipt=Fixture.pasteReceipt(boxes)end
  phase='configure'
 elseif phase=='configure'then
  if not pasteReceipt then return end
  assert(pasteReceipt.revision==pasteRevision+1,'paste was not one authoritative revision')
  print('[QM_DISTRIBUTION] PASTE '..JSON.encode(pasteReceipt))
  if isClient()then
   saved=false
   LootSorter.putPreset({name=Fixture.presetName,cats={Food=true},items={},expectExisting=false,
    pzstTagRule={mode='all',include={'electrical'},exclude={}}},function(verdict)
     assert(verdict=='ok','Host preset creation refused');saved=true
    end)
   phase='preset-created'
  else phase='configure-target'end
 elseif phase=='preset-created'then
  local preset=LootSorter.getPresetStore()[Fixture.presetName]
  if not saved or not preset then return end
  local rule=assert(Rules.getPreset(Fixture.presetName,preset),'new preset missing its matching rule')
  assert(preset.rev==1 and preset.cats.Food and rule.include[1]=='electrical','initial preset snapshot differs')
  presetGeneration=preset.gen
  LootSorter.openPresetEditor(Fixture.presetName,0)
  presetEditor=assert(LootSorter._presetEditor)
  presetEditor.selectedCats={};presetEditor.selectedItems={}
  presetEditor.toolkitTagRule={mode='all',include={'food','perishable'},exclude={'meat'}}
  presetEditor.toolkitTagRuleTouched=true
  presetEditor.btnSave.onclick(presetEditor)
  phase='preset-edited'
 elseif phase=='preset-edited'then
  if LootSorter._presetEditor==presetEditor then return end
  local preset=LootSorter.getPresetStore()[Fixture.presetName]
  if not preset or preset.rev~=2 then return end
  local rule=assert(Rules.getPreset(Fixture.presetName,preset),'edited preset missing matching rule')
  assert(preset.gen==presetGeneration and Fixture.empty(preset.cats) and Fixture.empty(preset.items)
   and rule.include[1]=='food' and rule.include[2]=='perishable' and rule.exclude[1]=='meat',
   'preset edit combined old selections with new rule')
  print('[QM_DISTRIBUTION] PRESET_SNAPSHOT '..JSON.encode({generation=preset.gen,revision=preset.rev,matching=true}))
  phase='configure-target'
 elseif phase=='configure-target'then
  LootSorter.openPicker(boxes[3],0,0)
  designationPicker=assert(LootSorter._picker)
  designationPicker.selectedItems={};designationPicker.priority=7
  if isClient()then designationPicker.selectedPresets={[Fixture.presetName]=presetGeneration}
  else
   designationPicker.toolkitTagRule={mode='all',include={'food','perishable'},exclude={'meat'}}
   designationPicker.toolkitTagRuleTouched=true
  end
  designationPicker.btnSave.onclick(designationPicker)
  phase='return'
 elseif phase=='return'then
  if LootSorter._picker==designationPicker then return end
  assert((isClient() and LootSorter.getBoxPresets(boxes[3],0)[Fixture.presetName]==presetGeneration
   or not isClient() and Rules.getBox(boxes[3],0)) and not LootSorter.getBoxItems(boxes[3],0)
   and LootSorter.getBoxPriority(boxes[3],0)==7,'editor lost accepted designation')
  saved=true;designatedAt=getTimestampMs()
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
  if isClient()then sendClientCommand('QuartermasterDistributionTest','PrepareBooks',{})
  else bookPacket=Books.prepare(state)end
  phase='books-resolve'
 elseif phase=='books-resolve'then
  if not bookPacket or not Books.resolve(boxes,bookPacket)then return end
  print('[QM_DISTRIBUTION] BOOKS_PREPARED '..JSON.encode(bookPacket))
  stageWalk(point.x+2);phase='books-fallback'
 elseif phase=='books-fallback'or phase=='books-unique'then
  if not stageArrived()then return end
  arrived=arrived or getTimestampMs();if getTimestampMs()-arrived<500 then return end
  arrived=nil
  local index=phase=='books-fallback'and 2 or 3
  LootSorter.openPicker(boxes[index],0,0);bookPicker=assert(LootSorter._picker)
  bookPicker.selectedCats={};bookPicker.selectedPresets={};bookPicker.selectedItems={}
  for _,id in ipairs({bookPacket.ids[1],bookPacket.ids[3]})do
   local item=assert(boxes[1]:getContainer():getItemById(id));bookPicker.selectedItems[item:getDisplayName()]=true
  end
  bookPicker.toolkitTagRule={mode='all',include={},exclude={}};bookPicker.toolkitTagRuleTouched=true
  bookPicker.priority=index==3 and 7 or 5
  assert(bookPicker.chkNoDuplicates,'native container unique checkbox missing')
  if bookPicker.noDuplicates~=(index==3)then
   bookPicker.chkNoDuplicates.onclick(bookPicker.chkNoDuplicates.target,bookPicker.chkNoDuplicates)
  end
  assert(bookPicker.noDuplicates==(index==3),'native checkbox callback did not update draft')
  bookPicker.btnSave.onclick(bookPicker)
  phase=index==2 and 'books-fallback-saved'or 'books-unique-saved'
 elseif phase=='books-fallback-saved'then
  if LootSorter._picker==bookPicker then return end
  assert(not LootSorter.getBoxNoDuplicates(boxes[2],0),'fallback saved unique mode')
  stageWalk(point.x+4);phase='books-unique'
 elseif phase=='books-unique-saved'then
  if LootSorter._picker==bookPicker then return end
  assert(LootSorter.getBoxNoDuplicates(boxes[3],0),'unique mode did not save')
  designatedAt=getTimestampMs();stageWalk(point.x);phase='books-ready'
 elseif phase=='books-ready'then
  if not stageArrived()then return end
  local loot=assert(getPlayerLoot(0));loot:refreshBackpacks();loot.inventoryPane:refreshContainer()
  local handler=loot.controlsUI:checkHandler(ISLootWindowObjectControlHandler_LootSorterDistribute,boxes[1],boxes[1]:getContainer())
  assert(handler:shouldBeVisible(),'book distribution control hidden')
  local button=handler:getControl();local before=LootSorter._sortRunSeq or 0
  button.onclick(button.target,button)
  assert((LootSorter._sortRunSeq or 0)>before and #queue().queue>0,'book distribution did not start')
  phase='books-sorting'
 elseif phase=='books-sorting'then
  local current=queue().current
  if current and current.Type=='LootSorterWalkAction'and current:isStarted()then bookWalked=true end
  if current and current.Type=='LootSorterDeposit'and current:isStarted()and current:getJobDelta()>0 then bookTransferred=true end
  if #queue().queue>0 or player:hasTimedActions()then return end
  local result=Books.receipt(player,boxes,bookPacket);if not result then return end
  assert(bookWalked and bookTransferred,'missing native skill book walk/transfer')
  print('[QM_DISTRIBUTION] BOOKS_LOCAL '..JSON.encode(result))
  if isClient()then sendClientCommand('QuartermasterDistributionTest','VerifyBooks',{})
  else bookReceipt=result;print('[QM_DISTRIBUTION] BOOKS_AUTHORITY '..JSON.encode(result))end
  phase='books-verified'
 elseif phase=='books-verified'then
  if not bookReceipt then return end
  -- Respect native delayed registry-add grace before removing designations.
  if getTimestampMs()-designatedAt<LootSorter.ADD_GRACE_MS+1000 then return end
  LootSorter.setBoxItems(boxes[2],0,{})
  saved=false;Rules.saveBox(boxes[3],0,{mode='all',include={},exclude={}},player,function(verdict)
   assert(verdict=='ok','tag cleanup rejected');saved=true
  end,nil,{cats={},items={},presets={},priority=0,noDuplicates=false})
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
 local ok,problem=pcall(function()assert(getTimestampMs()-since<240000,'distribution timeout phase='..phase);tick()end)
 if not ok then done=true;print('[QUEUE_TEST] FAIL distribution '..tostring(problem))end
end)
