local F=require 'QuartermasterGroupsFixture'
local Groups=require 'PZSurvivorToolkit/ContainerGroups'
local Controls=require 'PZSurvivorToolkit/ContainerGroupControls'
local Appearance=require 'PZSurvivorToolkit/ContainerAppearanceControls'
local Rules=require 'PZSurvivorToolkit/QuartermasterTagRuleClient'
local JSON=require 'QueueHealthEvents'
local G={};local run
local function emit(event,value)print('[QM_DISTRIBUTION] GROUP_'..event..' '..JSON.encode(value))end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
Events.OnServerCommand.Add(function(module,command,value)
 if module~='QuartermasterDistributionTest'or not run then return end
 if command=='GroupsPrepared'then assert(not run.packet,'duplicate group preparation');run.packet=value
 elseif command=='GroupVerified'then
  assert(not run.authority,'duplicate group stage authority');run.authority=value
 elseif command=='GroupTransfersVerified'then assert(not run.transfers,'duplicate grouped transfer authority');run.transfers=value end
end)
local function walk(index,nextPhase)
 local point=run.point;local x=index==1 and point.x or index==2 and point.x+2 or index==3 and point.x+4 or point.x+6
 run.square=assert(getCell():getGridSquare(x,point.y,point.z));run.arrived=nil;run.walkComplete=false
 local action=LootSorter.WalkAction:new(getPlayer(),run.square)
 action:setOnComplete(function()run.walkComplete=true end);ISTimedActionQueue.add(action)
 run.phase=nextPhase
end
local function settled()
 if #queue().queue>0 or getPlayer():hasTimedActions()then return false end
 assert(run.walkComplete and getPlayer():getCurrentSquare()==run.square,'group staging walk did not arrive')
 run.arrived=run.arrived or getTimestampMs()
 return getTimestampMs()-run.arrived>=500
end
local function draft(stage)
 local p=run.picker;local config=F.configuration(stage,run.packet.names)
 p.selectedCats,p.selectedItems,p.selectedPresets=config.cats,config.items,config.presets
 p:setPriority(config.priority)
 p.toolkitTagRule=F.rule(stage);p.toolkitTagRuleTouched=true
 Appearance.setValue(p,config.appearance)
 if p.noDuplicates~=config.noDuplicates then p.chkNoDuplicates.onclick(p.chkNoDuplicates.target,p.chkNoDuplicates)end
 assert(p.noDuplicates==config.noDuplicates,'group checkbox draft differs')
end
local function open(index)
 LootSorter.openPicker(run.boxes[index],0,0);run.picker=assert(LootSorter._picker)
 assert(run.picker.groupSelect and run.picker.groupScope,'group selector/scope controls missing')
end
local function save(stage)
 run.picker.btnSave.onclick(run.picker);run.stage=stage;run.phase='saved'
end
local function verify(stage)
 local receipt=F.configurationReceipt(run.localState,stage);emit('LOCAL',receipt)
 if isClient()then sendClientCommand('QuartermasterDistributionTest','VerifyGroup',{stage=stage})
 else run.authority=receipt;emit('AUTHORITY',receipt)end
 run.phase='authority'
end
function G.begin(boxes,point,state)
 assert(not run,'group pass started twice')
 run={boxes=boxes,point=point,phase='resolve',state=state,since=getTimestampMs()}
 if isClient()then sendClientCommand('QuartermasterDistributionTest','PrepareGroups',{})
 else run.packet=F.prepare(state)end
end
function G.tick()
 assert(run and getTimestampMs()-run.since<200000,'group fixture timeout: '..tostring(run and run.phase))
 local player=getPlayer();local phase=run.phase
 if phase=='resolve'then
  if not run.packet or not Groups.synced()or not F.resolve(run.boxes,run.packet)then return false end
  emit('PREPARED',run.packet)
  run.localState={player=player,boxes=run.boxes,groupPacket=run.packet,groupStage=0}
  walk(3,'create')
 elseif phase=='create'then
  if not settled()then return false end
  open(3);Controls.createGroup(run.picker);draft('created');save('created')
 elseif phase=='join'or phase=='rejoin'then
  if phase=='join'and not settled()then return false end
  open(4);local record=assert(Groups.resolve(run.boxes[3],0));Controls.select(run.picker,record)
  assert(F.equal(Controls.snapshot(run.picker),{configuration=record.configuration,rule=record.rule}),
   'selecting existing group failed to inherit complete appearance/filter/priority')
  save(phase=='join'and 'joined'or 'rejoined')
 elseif phase=='update'then
  if not settled()then return false end
  open(3);Controls.setScope(run.picker,'group');draft('updated')
  run.renderAt=getTimestampMs()+500;run.phase='screenshot'
 elseif phase=='screenshot'then
  if getTimestampMs()<run.renderAt then return false end
  assert(run.picker.groupSelect:getIsVisible()and run.picker.groupScope:getIsVisible(),'group editor selector/scope not visible')
  getCore():TakeFullScreenshot('quartermaster-group-editor.png')
  emit('SHOT',{name='quartermaster-group-editor',width=run.picker:getWidth(),height=run.picker:getHeight()})
  save('updated')
 elseif phase=='detach'then
  if not settled()then return false end
  open(4);Controls.setScope(run.picker,'local');draft('detached');save('detached')
 elseif phase=='unique'then
  if not settled()then return false end
  open(3);Controls.setScope(run.picker,'group');draft('unique');save('unique')
 elseif phase=='saved'then
  if LootSorter._picker==run.picker then return false end
  verify(run.stage)
 elseif phase=='authority'then
  if not run.authority then return false end
  assert(run.authority.stage==run.stage,'group authority stage differs')
  run.authority=nil
  if run.stage=='created'then walk(4,'join')
  elseif run.stage=='joined'then walk(3,'update')
  elseif run.stage=='updated'then walk(4,'detach')
  elseif run.stage=='detached'then run.phase='rejoin'
  elseif run.stage=='rejoined'then walk(3,'unique')
  else walk(2,'fallback')end
 elseif phase=='fallback'then
  if not settled()then return false end
  open(2);local p=run.picker
  p.selectedCats={};p.selectedItems={[run.packet.names[1]]=true,[run.packet.names[2]]=true};p.selectedPresets={}
  p:setPriority(5);p.noDuplicates=false;p.toolkitTagRule={mode='all',include={},exclude={}};p.toolkitTagRuleTouched=true
  p.btnSave.onclick(p);run.phase='fallback-saved'
 elseif phase=='fallback-saved'then
  if LootSorter._picker==run.picker then return false end
  assert(not Groups.link(run.boxes[2],0)and not LootSorter.getBoxNoDuplicates(run.boxes[2],0),'fallback joined group/unique mode')
  walk(1,'sort')
 elseif phase=='sort'then
  if not settled()then return false end
  local loot=assert(getPlayerLoot(0));loot:refreshBackpacks();loot.inventoryPane:refreshContainer()
  local handler=loot.controlsUI:checkHandler(ISLootWindowObjectControlHandler_LootSorterDistribute,run.boxes[1],run.boxes[1]:getContainer())
  assert(handler:shouldBeVisible(),'group distribution toolbar hidden')
  local button=handler:getControl();local before=LootSorter._sortRunSeq or 0
  button.onclick(button.target,button)
  assert((LootSorter._sortRunSeq or 0)>before and #queue().queue>0,'group distribution did not start');run.phase='sorting'
 elseif phase=='sorting'then
  local action=queue().current
  if action and action.Type=='LootSorterWalkAction'and action:isStarted()then run.walked=true end
  if action and action.Type=='LootSorterDeposit'and action:isStarted()and action:getJobDelta()>0 then run.transferred=true end
  if #queue().queue>0 or player:hasTimedActions()then return false end
  local result=F.transferReceipt(player,run.boxes,run.packet);if not result then return false end
  assert(run.walked and run.transferred,'missing grouped native walk/transfer');emit('TRANSFERS_LOCAL',result)
  if isClient()then sendClientCommand('QuartermasterDistributionTest','VerifyGroupTransfers',{})
  else run.transfers=result;emit('TRANSFERS_AUTHORITY',result)end
  run.phase='transfers'
 elseif phase=='transfers'then
  if not run.transfers then return false end
  walk(4,'cleanup')
 elseif phase=='cleanup'then
  if not settled()then return false end
  run.cleaned=false
  Rules.saveBox(run.boxes[4],0,{mode='all',include={},exclude={}},player,function(verdict)
   assert(verdict=='ok','group member cleanup rejected');run.cleaned=true
  end,nil,{cats={},items={},presets={},priority=0,noDuplicates=false,appearance={},groupOperation={mode='detach'}})
  run.phase='cleaned'
 elseif phase=='cleaned'then
  if not run.cleaned then return false end
  assert(not Groups.link(run.boxes[4],0),'group member cleanup retained link')
  local square=run.boxes[4]:getSquare();local key=square:getX()..','..square:getY()..','..square:getZ()
  if LootSorter.getRegistry()[key]then
   if not run.cleanupRetry or getTimestampMs()-run.cleanupRetry>1000 then
    LootSorter.removeCoords({keys={key}});run.cleanupRetry=getTimestampMs()
   end
   return false
  end
  emit('COMPLETE',{stages=6,members=2,localDetached=true,groupDuplicates=true})
  return true
 end
 return false
end
return G
