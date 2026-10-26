require 'PZSurvivorToolkit/ActionQueuePanel'
require 'ISUI/Crafting/ISHandcraftWindow'
require 'Neat_Crafting/NC_CraftActionPanel'
require 'Project_Cook/PJCK_Window'
local Fixture=require 'QueueCraftUIFixture'
local Evolved=require 'QueueCookEvolved'
local config=require 'QueueTestSelection'
local JSON=require 'QueueHealthEvents'
local actor=config.actor or 'client1'
local joined=actor=='client2'
local Sandwich=joined and require 'QueueCookSandwich'or nil
local SandwichFixture=joined and require 'QueueCookSandwichFixture'or nil
local Toolkit=PZSurvivorToolkit
local enabled=config.mode=='toolkit'
local step,failed,phase,since,idle=1,0,'prepare',0,0
local started,done=false,false
local ids,state,authorityState,authority,previousAuthority,window,owner,logic,tail,actions
local evolvedRun
local sandwichRun,actorStarted
local observerIds,observerBefore,observerAfter,observerReadySent,observerInstruction
local progress,picked,returned,boundaries={},{},{},{perform=0,complete=0}
local callbacks,callbackClass,returnsBeforeRead,localDeferrals
local interrupted,interruptionProgress
local removal,poolPhaseProof,manualMaterialIds,manualMaterialIdsAfterRemoval
local previousCleanupIds,previousBagIds={},{}
local secondAllocated,secondStarted=false,false
local outcomeTrace={};local tailProgress=false
local function case()return config.cases[step]end
local function evolved()return require('QueueCookEvolvedFixture').isCase(case())end
local function sandwich()return case()=='cook-sandwich-plain-joined'or case()=='cook-sandwich-enriched-joined'end
local function automatic()return case():sub(-5)=='-auto'end
local function context()return case():match('^context')~=nil end
local function pool()return case():find('missing-batch-pool',1,true)~=nil end
local function failure()return case():find('cancel-active',1,true)~=nil or pool()end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function sorted(set)local out={};for id in pairs(set)do out[#out+1]=id end;table.sort(out);return out end
local function refreshSources(player)
 getPlayerInventory(player:getPlayerNum()):refreshBackpacks();getPlayerLoot(player:getPlayerNum()):refreshBackpacks()
 local containers=ISInventoryPaneContextMenu.getContainers(player)
 for _,id in ipairs(ids.bags)do
  local bag=assert(state.root:getItemById(id));local found=false
  for i=0,containers:size()-1 do if containers:get(i)==bag:getItemContainer()then found=true end end
  assert(found,'UI did not expose an equipped exact tool source')
 end
 state.containers=containers
end
local function emit(value)
 value.suite='craft-ui';value.kind=config.kind;value.mode=config.mode
 value.actor=joined and assert(getPlayer()):getUsername()or 'client1'
 if value.event=='observer'then print('[CRAFT_UI_OBSERVER] '..JSON.encode(value))else JSON.emit(value)end
end
local function observerTick(player)
 assert(player:getUsername()=='client1','joined fixture observer identity differs')
 assert(#queue().queue==0 and not player:hasTimedActions(),'host observer performed unexpected timed actions')
 if not observerReadySent then
  if step==1 then emit({event='setup',cases=config.cases,expected=#config.cases,queueEnabled=enabled,
   nativeDurations=true,participation='observer',producerActor=actor})end
  sendClientCommand('CraftUITest','ObserverReady',{case=case()});observerReadySent=true;phase='observer-awaiting-prepare'
 end
 if not observerIds or not observerInstruction then return end
 local snapshot=SandwichFixture.observerSnapshot(player,observerIds,observerInstruction)
 if not snapshot then return end
 if observerInstruction=='before'then
  assert(not observerBefore,'duplicate independent observer before snapshot');observerBefore=snapshot
  emit({event='observer',id=case(),stage='before',snapshot=snapshot})
  sendClientCommand('CraftUITest','ObservedBefore',{case=case(),snapshot=snapshot})
  observerInstruction=nil;phase='observer-awaiting-effects'
 elseif observerInstruction=='after'then
  assert(observerBefore and not observerAfter,'invalid independent observer after snapshot');observerAfter=snapshot
  emit({event='observer',id=case(),stage='after',snapshot=snapshot})
  sendClientCommand('CraftUITest','Observed',{case=case(),snapshot=snapshot})
  observerInstruction=nil;phase='observer-awaiting-done'
 end
end
local function request(command)
 if isClient()then sendClientCommand('CraftUITest',command,{case=case()})
 elseif command=='Prepare'then
  authorityState=Fixture.prepare(getPlayer(),case(),previousAuthority);previousAuthority=nil;ids=Fixture.descriptor(authorityState)
  print('[CRAFT_UI_TEST] PREPARED '..JSON.encode(ids))
 elseif command=='RemovePool'then
  removal=Fixture.removePool(authorityState);print('[CRAFT_UI_TEST] REMOVED '..JSON.encode(removal))
 else
  authority=assert(Fixture.verify(authorityState));print('[CRAFT_UI_TEST] VERIFIED '..JSON.encode(authority))
 end
end
Events.OnServerCommand.Add(function(module,command,value)
 local first=actions and actions[1]
 if module=='PZSurvivorToolkitActions'and command=='State'and failure()and first
  and value.player==ids.playerId and value.transaction==first.toolkitNativeTransaction and value.kind==first.toolkitNativeKind then
  local row={protocol=value.protocol,player=value.player,transaction=value.transaction,kind=value.kind,token=value.token,state=value.state}
  outcomeTrace[#outcomeTrace+1]=row
  print('[CRAFT_UI_TEST] OUTCOME '..JSON.encode({case=case(),receipt=row}));return
 end
 if module~='CraftUITest'then return end
 assert(command~='Failed',value.error)
 if joined and getPlayer()and getPlayer():getUsername()=='client1'then
  assert(value.case==case(),'observer server case differs')
  if command=='ObservePrepared'then
   assert(not observerIds,'duplicate observer preparation');observerIds=value;observerInstruction='before'
  elseif command=='Observe'then
   assert(observerBefore and not observerAfter and not observerInstruction,'observer effect request differs')
   observerInstruction='after'
  elseif command=='Done'then
   assert(observerBefore and observerAfter and not observerInstruction,'observer completed before independent snapshots')
   emit({event='case',id=case(),status='observed',participation='observer',producerActor=actor,
    before=observerBefore,after=observerAfter})
   if step==#config.cases then
    emit({event='complete',cases=config.cases,expected=#config.cases,performed=0,observed=#config.cases,failed=0,skipped=0})
    print('[CRAFT_UI_TEST] COMPLETE actor=client1');done=true
   else
    step=step+1;since=getTimestampMs();phase='observer-ready'
    observerIds,observerBefore,observerAfter,observerReadySent=nil,nil,nil,nil
   end
  else error('unexpected observer server command '..tostring(command))end
  return
 end
 if command=='Start'then assert(joined and value.case==case()and not actorStarted,'actor start barrier differs');actorStarted=true;return end
 if command=='Prepared'then ids=value elseif command=='Verified'then authority=value elseif command=='Removed'then removal=value end
end)
local begin=Toolkit.ActionQueueLifecycle.begin
Toolkit.ActionQueueLifecycle.begin=function(action,nativePhase)
 local active=begin(action,nativePhase)
 for _,expected in ipairs(actions or {})do
  if action==expected and active and Toolkit.ActionQueueLifecycle.current(action.character)==action
   and boundaries[nativePhase]~=nil then boundaries[nativePhase]=boundaries[nativePhase]+1 end
 end
 return active
end
local defer=Toolkit.ActionQueueOperations.deferCompletion
Toolkit.ActionQueueOperations.deferCompletion=function(q,action)
 local result=defer(q,action)
 for _,expected in ipairs(actions or {})do if action==expected and result then localDeferrals=localDeferrals+1 end end
 return result
end
local function openUI(player,recipe)
 if case():match('^vanilla%-')then
  window=ISXuiSkin.build(XuiManager.GetDefaultSkin(),'HandcraftWindow',ISHandcraftWindow,20,20,900,600,player,nil,'InHandCraft')
  window:initialise();window:instantiate();window:addToUIManager()
  local panel=assert(window.handCraftPanel);logic=panel.logic;owner=assert(panel.recipePanel.craftControl)
  assert(getmetatable(owner)==ISWidgetHandCraftControl,'vanilla control replaced')
  callbackClass='ISWidgetHandCraftControl'
 elseif case():match('^neat%-')then
  ISEntityUI.OpenHandcraftWindow(player,nil,'InHandCraft',true,recipe)
  window=assert(ISEntityUI.GetWindowInstance(player:getPlayerNum(),'HandcraftWindow'))
  local panel=assert(window.HandCraftPanel or window.handCraftPanel)
  logic=panel.logic;owner=assert(panel.craftActionPanel)
  assert(getmetatable(owner)==NC_CraftActionPanel,'Neat control replaced');callbackClass='NC_CraftActionPanel'
 else
  window=PJCK_Window:new(20,20,900,600,player);window:initialise();window:instantiate();window:addToUIManager()
  window:switchToPanel('craft')
  local panel=assert(window.HandCraftPanel);logic=panel.logic;owner=assert(panel.craftActionPanel)
  assert(getmetatable(owner)==PJCK_CraftActionPanel,'Project Cook control replaced');callbackClass='PJCK_CraftActionPanel'
 end
 logic:setContainers(state.containers);logic:setRecipe(recipe);logic:setManualSelectInputs(not automatic());logic:clearManualInputs()
 if automatic()then return end
 for index=0,recipe:getInputs():size()-1 do
  local input=recipe:getInputs():get(index);local items=ArrayList.new()
  if index==0 then for _,id in ipairs(ids.materials)do items:add(assert(state.root:getItemById(id)))end
  else items:add(assert(state.root:getItemById(ids.toolMeta[index].id)))end
  assert(logic:setManualInputsFor(input,items),'UI explicit input selection rejected')
 end
end
local function snapshotCallbacks()
 callbacks={}
 for i,action in ipairs(actions)do
  assert(action:getDuration()==150 and not action.character:isTimedActionInstant(),'UI native duration changed')
  assert(Toolkit.ActionQueueCraft.supports(action),'UI craft callback owner unsupported: '..case())
  callbacks[i]={action.onStartFunc,action.onStartTarget,action.onCompleteFunc,action.onCompleteTarget,
   action.onCancelFunc,action.onCancelTarget}
  if context()then
   logic=action.onCompleteTarget;assert(action.onCompleteFunc==ISInventoryPaneContextMenu.OnNewCraftComplete,'context callback replaced')
  else
   assert(action.onStartTarget==owner and action.onCompleteTarget==owner and action.onCancelTarget==owner,'UI callback target differs')
  end
 end
end
local function captureMaterialIds()
 local result={}
 local recipe=actions[1].craftRecipe
 local materialIndex=recipe:getIndexForIO(recipe:getInputs():get(0))
 local expected={};for _,id in ipairs(ids.materials)do expected[id]=true end
 for i,action in ipairs(actions)do
  local selected=assert(action.manualInputs[materialIndex]);local selectedIds={}
  assert(selected:size()==2,'UI craft did not retain the full shared material pool')
  for index=0,selected:size()-1 do
   local item=selected:get(index);assert(item:getFullType()=='Base.Plank'and expected[item:getID()],'UI shared pool selected another material')
   assert(not selectedIds[item:getID()],'UI shared pool contains duplicate material identity');selectedIds[item:getID()]=true
  end
  result[i]=sorted(selectedIds)
 end
 return result
end
local function enqueue(player)
 if sandwich()then
  sandwichRun=sandwichRun or Sandwich.start(player,state,ids,enabled)
  if not sandwichRun.dispatched then Sandwich.continueStart(sandwichRun)end
  Sandwich.observe(sandwichRun)
  return sandwichRun.dispatched==true
 end
 if evolved()then
  evolvedRun=evolvedRun or Evolved.start(player,state,ids,enabled)
  if not evolvedRun.dispatched then Evolved.continueStart(evolvedRun)end
  return evolvedRun.dispatched==true
 end
 local recipe=assert(getScriptManager():getCraftRecipe('QueueBorrowedTools'))
 if context()then
  callbackClass='context'
  local menu=ISContextMenu.get(player:getPlayerNum(),20,20)
  menu:addOption(recipe:getTranslationName(),state.root:getItemById(ids.materials[1]),
   ISInventoryPaneContextMenu.OnNewCraft,recipe,player:getPlayerNum(),false)
  menu.mouseOver=1;menu:onJoypadDown(Joypad.AButton)
 else
  if not window then openUI(player,recipe);return false end
  logic:canPerformCurrentRecipe()
  if not logic:canPerformCurrentRecipe()then return false end
  assert(logic:getPossibleCraftCount(true)>=2,'UI batch has insufficient real inputs')
  if case():match('^vanilla%-')then
   owner:setCraftQuantity(2);if not owner.buttonCraft.enable then return false end;owner.buttonCraft:forceClick()
  else
   owner.quantityInput:setText('2');if not owner.craftButton.enable then return false end;owner.craftButton:forceClick()
  end
 end
 actions={}
 for _,action in ipairs(queue().queue)do
  if action.Type=='ISHandcraftAction'and action.craftRecipe==recipe then actions[#actions+1]=action end
 end
 assert(#actions==#ids.materials,'UI did not enqueue requested craft count: '..case()..' '..#actions)
 snapshotCallbacks()
 if pool()then
  manualMaterialIds=captureMaterialIds()
 end
 if automatic()then
  assert(not logic:isManualSelectInputs(),'automatic UI switched to manual selection')
  for _,action in ipairs(actions)do assert(not action.manualInputs,'automatic action has pinned manual inputs')end
 end
 local book=state.book
 book:setAlreadyReadPages(book:getNumberOfPages()-1);player:setAlreadyReadPages(book:getFullType(),book:getNumberOfPages()-1)
 tail=ISReadABook:new(player,book)
 assert(tail.minutesPerPage==2.0 and tail.maxTime>1,'UI reader duration changed')
 ISTimedActionQueue.add(tail)
 if enabled then
  for _,action in ipairs(actions)do assert(action.toolkitQueueOperation==actions[1].toolkitQueueOperation,'UI batch split into different operations')end
  assert(tail.toolkitQueueOperation~=actions[1].toolkitQueueOperation,'UI reader not independent')
 end
 return true
end
local function observe()
 if sandwich()then Sandwich.observe(sandwichRun);return end
 if evolved()then Evolved.observe(evolvedRun);return end
 local current=queue().current
 if pool()then
  secondAllocated=secondAllocated or actions[2].action~=nil
  secondStarted=secondStarted or actions[2].craftStarted==true or actions[2]:isStarted()==true
 end
 for i,action in ipairs(actions)do if current==action and action:isStarted()and action:getJobDelta()>0 then progress[i]=true end end
 if current and current.Type=='ISInventoryTransferAction'and current:isStarted()and current:getJobDelta()>0 then
  local items=current.queueList and current.queueList[1]and current.queueList[1].items or {current.item}
  for _,item in ipairs(items)do for _,meta in ipairs(ids.toolMeta)do
   if item:getID()==meta.id then
    if current.destContainer==state.root then picked[meta.id]=true end
    if current.srcContainer==state.root then returned[meta.id]=true end
   end
  end end
 end
 if current==tail and tail:isStarted()and tail:getJobDelta()>0 and returnsBeforeRead==nil then
  tailProgress=true;returnsBeforeRead=true
  for i,meta in ipairs(ids.toolMeta)do
   local bag=state.root:getItemById(ids.bags[i]);local tool=bag and bag:getItemContainer():getItemById(meta.id)
   if not tool then returnsBeforeRead=false end
  end
 end
end
local function intervene()
 if not failure()then return end
 local first=actions[1]
 if not interrupted and queue().current==first and first.craftStarted==true and first:isStarted()and first:getJobDelta()>0 then
  local ack=config.kind=='mp'and Toolkit.ActionQueueAcknowledgements.capture(first)
  if config.kind=='sp'or ack and Toolkit.ActionQueueAcknowledgements.state(first,ack)=='started'then
   interruptionProgress=first:getJobDelta();assert(interruptionProgress<=0.25,'UI active intervention missed early native progress')
   interrupted=true
   if pool()then
    assert(actions[2].action==nil and actions[2].craftStarted==false,'UI second craft allocated before pool-removal request')
    poolPhaseProof={secondAllocatedAtRequest=false,observedBeforeSecondAllocation=false}
    request('RemovePool')
   elseif enabled then
    local allowed,reason=Toolkit.ActionQueue.cancelOperation(queue(),first);assert(allowed,reason)
   else first:forceStop()end
  end
 end
 if pool()and interrupted and not poolPhaseProof.observedBeforeSecondAllocation then
  assert(actions[2].action==nil and actions[2].craftStarted==false,'UI second craft allocated before pool removal was observed')
  local absent=removal~=nil
  for _,id in ipairs(ids.materials)do if state.root:getItemById(id)then absent=false end end
  if absent and Fixture.sparePresent(getPlayer(),removal.introducedSpare)then
   manualMaterialIdsAfterRemoval=captureMaterialIds()
   poolPhaseProof.secondAllocatedAtRemoval=false;poolPhaseProof.observedBeforeSecondAllocation=true
  end
 end
end
local function advance(retain)
 previousCleanupIds=retain and {} or {authority.bookId}
 if not retain then for _,id in ipairs(authority.outputIds)do previousCleanupIds[#previousCleanupIds+1]=id end end
 previousBagIds=ids.bags
 local bags={}
 for _,id in ipairs(previousBagIds)do
  if not retain then previousCleanupIds[#previousCleanupIds+1]=id end;bags[#bags+1]=assert(state.root:getItemById(id))
 end
 ISInventoryPaneContextMenu.onUnEquip(bags,getPlayer():getPlayerNum())
 for _,id in ipairs(not retain and authority.materialIds or {})do previousCleanupIds[#previousCleanupIds+1]=id end
 if authority.introducedSpare then previousCleanupIds[#previousCleanupIds+1]=authority.introducedSpare.id end
 for _,resource in ipairs(not retain and authority.resources or {})do
  previousCleanupIds[#previousCleanupIds+1]=resource.id
 end
 previousAuthority=authorityState
 step=step+1;phase='unequip';since=getTimestampMs()
 ids,state,authorityState,authority,window,owner,logic,tail,actions=nil,nil,nil,nil,nil,nil,nil,nil,nil
 progress,picked,returned,boundaries={},{},{},{perform=0,complete=0}
 returnsBeforeRead,localDeferrals,idle=nil,0,0
 interrupted,interruptionProgress=nil,nil
 removal,poolPhaseProof,manualMaterialIds,manualMaterialIdsAfterRemoval=nil,nil,nil,nil
 secondAllocated,secondStarted=false,false
 outcomeTrace={};tailProgress=false;evolvedRun=nil
end
local function finish()
 if sandwich()then
  local value,reason=Sandwich.finish(sandwichRun,authority)
  if reason then failed=failed+1 end;emit(value)
  if step==#config.cases then
   emit({event='complete',cases=config.cases,expected=#config.cases,performed=#config.cases,failed=failed,skipped=0})
   print('[CRAFT_UI_TEST] COMPLETE actor=client2');done=true
  else
   step=step+1;since=getTimestampMs();phase='prepare';idle=0
   ids,state,authorityState,authority,sandwichRun,actorStarted=nil,nil,nil,nil,nil,nil
  end
  return
 end
 if evolved()then
  local value,reason=Evolved.finish(evolvedRun,authority)
  if reason then failed=failed+1 end;emit(value)
  if step<#config.cases then advance(true);return end
  emit({event='complete',cases=config.cases,expected=#config.cases,performed=#config.cases,failed=failed,skipped=0})
  print('[CRAFT_UI_TEST] COMPLETE');done=true;return
 end
 local unchanged,safe=true,true
 for i,action in ipairs(actions)do
  local now={action.onStartFunc,action.onStartTarget,action.onCompleteFunc,action.onCompleteTarget,action.onCancelFunc,action.onCancelTarget}
  for n=1,6 do if now[n]~=callbacks[i][n]then unchanged=false end end
  safe=safe and Toolkit.ActionQueueCraft.callbacksSafe(action)
 end
 local ownerIdle=not logic:isCraftActionInProgress();local remaining=owner and owner.craftTimes or 0
 local reason=(not ownerIdle or remaining>0)and 'owner-still-busy'or not authority.tailRead and 'native-independent-tail-not-preserved'
  or not returnsBeforeRead and 'native-returns-not-before-tail'or nil
 if pool()then
  if secondAllocated or secondStarted then reason='native-second-craft-allocated'
  elseif authority.outputs~=1 or #authority.outputPlankCounts~=1 or authority.outputPlankCounts[1]~=1 then reason='native-retained-input-effect-differs'end
 end
 local value={event='case',id=case(),status=reason and 'failed'or 'passed',reason=reason,
  requested=#ids.materials,actions=#actions,progressIds=sorted(progress),callbackClass=callbackClass,
  callbacksUnchanged=unchanged,callbackSafe=safe,nativeDuration=150,localDeferrals=localDeferrals,
  sharedPerformCount=boundaries.perform,sharedCompleteCount=boundaries.complete,
  ownerIdle=ownerIdle,remaining=remaining,pickupIds=sorted(picked),returnIds=sorted(returned),returnsBeforeRead=returnsBeforeRead==true}
 if failure()then
  assert(interrupted and progress[1],'UI active cancellation gate was not reached')
  value.interrupted=true;value.interruptionProgress=interruptionProgress;value.outcomeTrace=outcomeTrace
  value.playerId=ids.playerId;value.tailProgress=tailProgress
  value.tokenCancelled=actions[1].toolkitQueueOperation and actions[1].toolkitQueueOperation.toolkitCancelled==true or false
  if pool()then
   assert(poolPhaseProof.observedBeforeSecondAllocation,'UI shared-pool prestart removal gate was not reached')
   value.poolPhaseProof=poolPhaseProof;value.manualMaterialIds=manualMaterialIds
   value.manualMaterialIdsAfterRemoval=manualMaterialIdsAfterRemoval
   value.secondAllocated=secondAllocated;value.secondStarted=secondStarted
  end
 end
 if automatic()then
  value.manualSelect=owner.logic:isManualSelectInputs();value.manualInputTypes={};value.automaticToolIds={}
  for _,action in ipairs(actions)do
   value.manualInputTypes[#value.manualInputTypes+1]=type(action.manualInputs)
   local tools={}
   assert(action.items,'automatic craft has no native input allocation')
   for i=0,action.items:size()-1 do
    local item=action.items:get(i)
    if item:getFullType()=='Base.Hammer'or item:getFullType()=='Base.Saw'then tools[item:getID()]=true end
   end
   value.automaticToolIds[#value.automaticToolIds+1]=sorted(tools)
  end
 end
 for key,entry in pairs(authority)do if key~='case'then value[key]=entry end end
 if reason then failed=failed+1 end;emit(value)
 if window then window:setVisible(false);window:removeFromUIManager()end
 if step==#config.cases then
  emit({event='complete',cases=config.cases,expected=#config.cases,performed=#config.cases,failed=failed,skipped=0})
  print('[CRAFT_UI_TEST] COMPLETE');done=true;return
 end
 advance(false)
end
Events.OnPlayerUpdate.Add(function(player)
 if started and player==getPlayer()then idle=#queue().queue==0 and not player:hasTimedActions()and idle+1 or 0 end
end)
Events.OnGameStart.Add(function()
 started=true;since=getTimestampMs();localDeferrals=0;getCore():setOptionPauseOnFocusloss(false)
 if not isClient()then getPlayer():setGhostMode(true)end
 if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
end)
Events.OnTick.Add(function()
 if not started or done or not isIngameState()then return end
 local ok,problem=pcall(function()
  assert(getTimestampMs()-since<(joined and 360000 or 180000),'UI craft deadline: '..phase)
  local player=getPlayer()
  if not player or player:isDead()or not player:getSquare()then return end
  if config.kind=='mp'and(not isClient()or player:getOnlineID()<0)then return end
  if joined then
   assert(player:getUsername()==actor or player:getUsername()=='client1','joined fixture local identity differs')
   if player:getUsername()~=actor then observerTick(player);return end
  end
  if phase=='unequip'then
   if #queue().queue>0 or player:hasTimedActions()or idle<10 then return end
   for _,id in ipairs(previousBagIds)do
    local bag=assert(player:getInventory():getItemById(id))
    assert(not player:isEquipped(bag),'UI previous source bag remains equipped')
   end
   phase='prepare';return
  end
  if phase=='prepare'then
   assert(Toolkit.Settings.actionQueue()==enabled,'UI queue option differs')
   if step==1 then emit({event='setup',cases=config.cases,expected=#config.cases,queueEnabled=enabled,nativeDurations=true})end
   request('Prepare');phase='ready';return
  end
  if phase=='ready'then
   if not ids then return end
   for _,id in ipairs(previousCleanupIds)do if player:getInventory():getItemById(id)then return end end
   previousCleanupIds={}
   state=state or Fixture.resolve(player,ids)
   if not state or not state.containers then return end
   if sandwich()then phase='ui';return end
   ISInventoryPaneContextMenu.onWearItems({state.root:getItemById(ids.bags[1])},player:getPlayerNum())
   ISInventoryPaneContextMenu.OnSecondWeapon({state.root:getItemById(ids.bags[2])},player:getPlayerNum())
   phase='equip';return
  end
  if phase=='equip'then
   if #queue().queue>0 or player:hasTimedActions()or idle<10 then return end
   refreshSources(player);phase='ui';return
  end
  if phase=='ui'then
   if joined and not actorStarted then return end
   if not enqueue(player)then return end
   phase='running';since=getTimestampMs();return
  end
  if phase=='running'then
   observe();intervene()
   if idle>=10 and #queue().queue==0 and not player:hasTimedActions()then
    if failure()and config.kind=='mp'then
     if #outcomeTrace<2 then return end
     assert(#outcomeTrace==2 and outcomeTrace[1].state=='started','UI native State lifecycle differs')
    end
    request('Verify');phase='receipt'
   end
  elseif phase=='receipt'and authority then finish()end
 end)
 if not ok then print('[QUEUE_TEST] FAIL craft UI '..tostring(problem));done=true end
end)
