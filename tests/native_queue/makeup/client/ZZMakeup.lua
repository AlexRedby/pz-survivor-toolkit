require 'PZSurvivorToolkit/ActionQueuePanel'
require 'ISUI/ISMakeUpUI'
require 'TimedActions/ISReadABook'
require 'TimedActions/ISApplyMakeUp'
local F=require 'QueueMakeup';local JSON=require 'QueueHealthEvents';local config=require 'QueueTestSelection'
local Proof=require 'PZSurvivorToolkit/SourceProof';local T=PZSurvivorToolkit;local native=config.mode=='native'
local entered,ready,done=false,false,false
local phase,index,since='prepare',1,0
local state,ids,previous,ui,front,tail,body,submitted,second,beforeTail,edit,verified,pending,authority
local checkpoints,sequence,outcomes,renderWitness,renderLabel,renderNext,bodyQuiet,finalQuiet
local bodyRecord,applyQueues,transferStarts,submitting,placement
local previewShotFrames,previewShotSince,previewShotTaken=0,nil,false
local uiMethods,bodyMethods={},{}
local observerFailure
local function now()return getTimestampMs()end
local function case()return config.cases[index]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function snapshot()return F.snapshot(state)end
local function raw(marker,row)print('[MAKEUP_TEST] '..marker..' '..JSON.encode(row))end
local function emit(row)row.suite,row.kind,row.mode,row.actor='makeup',config.kind,config.mode,'client1';JSON.emit(row)end
local function preview()
 local item=ui and ui.makeUpSelected
 return item and {id=item:getID(),kind=item:getFullType(),slot=tostring(item:getBodyLocation()),root=item:getContainer()~=nil,
  previous=ui.previousMakeUp and ui.previousMakeUp:getID()or false}or false
end
local function intact()
 assert(not observerFailure,'native makeup observer failed '..tostring(observerFailure))
 for name,callback in pairs(uiMethods)do assert(ISMakeUpUI[name]==callback,'makeup UI callback replaced '..name)end
 for name,callback in pairs(bodyMethods)do assert(ISApplyMakeUp[name]==callback,'native makeup body callback replaced '..name)end
 assert(Proof.closure(ISApplyMakeUp.complete,'ISApplyMakeUp.lua')and Proof.closure(ISApplyMakeUp.new,'ISApplyMakeUp.lua'),'native makeup executor source changed')
end
local function observe(callback)
 return function(...)
  local ok,result=pcall(callback,...)
  if not ok then observerFailure=tostring(result);return false end
  return result
 end
end
local function command(name,args)
 args=args or{};args.case=case()
 if isClient()then sendClientCommand('MakeupTest',name,args);return end
 if name=='Prepare'then
  if config.options and config.options.makeup_supplies==true then assert(F.same(args.placement,placement)and F.atPlacement(getPlayer(),placement),'SP makeup supply placement is not settled')end
  state=F.prepare(getPlayer(),case(),previous,args.placement);ids=state.ids;raw('PREPARED',ids)
 elseif name=='Snapshot'then
  authority={case=case(),label=args.label,sequence=args.sequence,at=now(),snapshot=snapshot()};raw('SNAPSHOT',authority)
 elseif name=='Finish'then verified={case=case(),sequence=sequence,snapshot=snapshot()};raw('VERIFIED',verified)end
end
local function checkpoint(label,nextPhase)
 sequence=sequence+1
 pending={case=case(),label=label,sequence=sequence,at=now(),snapshot=snapshot(),preview=preview(),render=renderWitness or false,
  bodyUnallocated=not body or body.action==nil,edit=edit or false}
 renderWitness=nil;authority=nil
 raw('CLIENT_SNAPSHOT',pending);phase='checkpoint';pending.nextPhase=nextPhase
 -- nextPhase is local control state and deliberately excluded from published evidence.
 command('Snapshot',{label=label,sequence=sequence})
end
local function close()
 assert(ui,'real makeup window missing');ui:close()
 assert(ISMakeUpUI.windows[state.player:getPlayerNum()+1]==nil,'makeup window close did not unregister')
end
local function chooseLocation(kind)
 local definition=F.definition(kind);local found
 for i,option in ipairs(ui.location.options)do if option.data and option.data.category==definition.category then found=i end end
 assert(found,'native makeup category not offered');ui.location.selected=found;ui:onSelectLocation()
end
local function choose(kind,locationReady)
 if not locationReady then chooseLocation(kind)end
 local found
 for i,option in ipairs(ui.comboMakeup.options)do if option.data and option.data.item==kind then found=i end end
 assert(found,'native makeup target not offered');ui.comboMakeup.selected=found;ui:onSelectMakeUp()
 local current=assert(preview(),'native selector made no preview')
 assert(current.kind==kind and not current.root and ui.character==state.player,'selected cosmetic escaped avatar ownership')
 return current
end
local function rendered(label,nextPhase)
 previewShotFrames,previewShotSince=0,nil
 renderLabel,renderNext=label,nextPhase;phase='render'
end
local function open()
 assert(not ISMakeUpUI.windows[state.player:getPlayerNum()+1],'previous native makeup window remains')
 ISInventoryPaneContextMenu.onMakeUp(assert(F.kit(state)),state.player)
 ui=assert(ISMakeUpUI.windows[state.player:getPlayerNum()+1],'native inventory producer made no real makeup UI')
 assert(ui.avatarPanel and ui.avatarPanel.javaObject and getClassSimpleName(ui.avatarPanel.javaObject)=='UI3DModel','native avatar renderer unavailable')
 submitted=choose(ids.target);rendered('preview','after-preview')
end
local function addTail()
 assert(not tail,'independent tail duplicated');tail=ISReadABook:new(state.player,state.player:getInventory():getItemById(ids.items.tail));ISTimedActionQueue.add(tail)
end
local function queueSnapshot()
 local types={};for _,action in ipairs(queue().queue)do types[#types+1]=action.Type end
 return {types=types,hasTimedActions=state.player:hasTimedActions(),nativeActions=state.player:getCharacterActions():size()}
end
local function apply()
 if ids.supply then
  applyQueues={before=queueSnapshot()}
  assert(empty()and applyQueues.before.nativeActions==0,'supply native application did not start with empty queue')
 end
 if isClient()and(not ids.supply or F.cancel(case()))then
  front=ISReadABook:new(state.player,state.player:getInventory():getItemById(ids.items.front));ISTimedActionQueue.add(front)
 end
 if isClient()then bodyRecord={duration=1,starts=0,finishes={},nativeRef=false}end
 submitting=true;ui:onApplyMakeUp();submitting=false
 if ids.supply then applyQueues.after=queueSnapshot();raw('APPLY_QUEUES',{case=case(),evidence=applyQueues})end
 if isClient()then
  for _,action in ipairs(queue().queue)do
   if action.Type=='ISApplyMakeUp'then assert(not body or body==action,'duplicate native makeup action');body=action end
  end
  assert(body and body.maxTime==1 and body.item:getID()==ids.items.kit and body.type==ids.target,'native makeup constructor/duration changed')
  local contract,adapter=T.ActionQueuePolicy.inspect(body)
  assert(contract and adapter=='native.ISApplyMakeUp'and contract.cancelWaiting==(not native and body.action==nil),'native makeup producer receipt/allocation differs')
  addTail()
  if case()=='apply-while-preview'then second=choose(ids.alternate);rendered('overlap-preview','wait-body')
  else close();phase=F.cancel(case())and'wait-front'or'wait-body'end
 else
  for _,action in ipairs(queue().queue)do assert(action.Type~='ISApplyMakeUp','SP immediate UI emitted timed makeup')end
  close();checkpoint('after-body','tail')
 end
end
local function completed()
 if not body then return false end
 for _,row in ipairs(outcomes)do if row.state=='completed'then return true end end
 return false
end
local function afterBody()
 if not empty()and queue():indexOf(body)~=-1 then bodyQuiet=nil;return end
 local cancelled=F.cancel(case())and not native
 if not cancelled and (not completed()or snapshot().kit.uses~=ids.kitUses-1)then return end
 bodyQuiet=bodyQuiet or now();if now()-bodyQuiet<750 then return end
 checkpoint('after-body',case()=='apply-while-preview'and'close-overlap'or'final-drain')
end
Events.OnPostUIDraw.Add(function()
 if done or phase~='render'or not ui then return end
 local ok,problem=pcall(function()
  assert(ui.character==state.player,'makeup preview actor changed')
  -- Production deliberately leaves Apply disabled while an async cosmetic asset loads.
  -- Keep the same render phase and existing case timeout; unsupported/failed rendering
  -- cannot become a pass just because we waited.
  if not ui.add.enable then previewShotFrames,previewShotSince=0,nil;return end
  local item=assert(ui.makeUpSelected);local before=snapshot();local accepted=true
  if not native then
   -- Observe the real bridge on the native model after its normal prerender.
   -- Reset only the UI avatar first so this observation does not stack overlays.
   ui.avatarPanel:setCharacter(state.player)
   accepted=toolkitMakeupAvatarPreview(ui.avatarPanel.javaObject,state.player,item)==true
  end
  local after=snapshot();assert(F.same(before,after),'avatar renderer changed actual actor/supply state')
  assert(accepted,'actual native avatar bridge rejected isolated preview')
  -- The probe observes the real native AnimatedModel in BOTH modes. A bridge
  -- return alone proves only overlay admission, not submitted pixels/ready textures.
  if UIManager.getFadeAlpha()>.001 or UIManager.getFadeAlpha(0)>.001
   or not makeupAvatarRendered(ui.avatarPanel.javaObject)then previewShotFrames,previewShotSince=0,nil;return end
  previewShotSince=previewShotSince or now();previewShotFrames=previewShotFrames+1
  local stableMs=now()-previewShotSince
  if previewShotFrames<3 or stableMs<500 then return end
  if case()==config.cases[1]and not previewShotTaken then
   local filename='makeup-preview-'..config.kind..'-'..config.mode..'.png'
   getCore():TakeFullScreenshot(filename);previewShotTaken=true
   raw('SCREENSHOT',{case=case(),file=filename,renderFrames=previewShotFrames,renderMs=stableMs,fadeClear=true,nativeRendered=true})
  end
  renderWitness={ok=true,actorUnchanged=true,selected=item:getID(),uiType='UI3DModel',source=native and'native-worn'or'toolkitMakeupAvatarPreview',
   nativeRendered=true,stableFrames=previewShotFrames,stableMs=stableMs}
 end)
 if not ok then raw('RENDER_FAILURE',{case=case(),error=tostring(problem)});print('[QUEUE_TEST] FAIL makeup '..tostring(problem));done=true end
end)
Events.OnServerCommand.Add(function(module,name,args)
 if module=='PZSurvivorToolkitActions'and name=='State'and body and ids and args.player==ids.actor and args.kind=='ISApplyMakeUp'then
  local row={protocol=args.protocol,player=args.player,transaction=args.transaction,kind=args.kind,token=args.token,state=args.state}
  outcomes[#outcomes+1]=row;raw('OUTCOME',{case=case(),receipt=row});return
 end
 if module~='MakeupTest'or done then return end
 if name=='Prepared'then ids=args
 elseif name=='Snapshot'then authority=args
 elseif name=='Verified'then verified=args
 elseif name=='Failed'then print('[QUEUE_TEST] FAIL makeup authority '..tostring(args.error));done=true end
end)
Events.OnGameStart.Add(function()entered=true;since=now()end)
Events.OnTick.Add(function()
 if not entered or done then return end
 local ok,problem=pcall(function()
  local player=getPlayer();if not isIngameState()or not player or not player:getCurrentSquare()then return end
  if not ready then
   if isClient()~=(config.kind=='mp')or isClient()and player:getUsername()~='client1'then return end
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(not native)
   assert(T.ActionQueueMakeup.installUI()and toolkitMakeupAvatarPreviewSupported(),'isolated makeup UI/renderer source support unavailable')
   assert(type(makeupAvatarCaptureSupported)=='function'and makeupAvatarCaptureSupported()
    and type(makeupAvatarRendered)=='function','test-only native avatar capture probe unavailable')
   for _,name in ipairs({'onSelectMakeUp','onSelectLocation','onApplyMakeUp','prerender','reinit','close'})do uiMethods[name]=ISMakeUpUI[name]end
   for _,name in ipairs({'new','isValid','start','update','stop','perform','complete','getDuration'})do bodyMethods[name]=ISApplyMakeUp[name]end
   assert(T.ActionQueueLifecycle.registerObserver('fixture.makeup',{
    started=observe(function(action)
     if submitting and ids.supply and action.Type=='ISApplyMakeUp'then
      assert(not body and action.item==F.kit(state)and action.type==ids.target,'unexpected native supply body began');body=action
     end
     if ids and ids.supply and action.Type=='ISInventoryTransferAction'then transferStarts=transferStarts+1 end
     if action==body then bodyRecord.starts=bodyRecord.starts+1;assert(bodyRecord.starts==1,'native makeup started twice')end
     if action==tail then assert(not beforeTail,'tail began twice');beforeTail={at=now(),snapshot=snapshot()};raw('BEFORE_TAIL',{case=case(),evidence=beforeTail})end
    end),
    begin=observe(function(action,step)
     if action~=body then return false end
     bodyRecord.nativeRef=tostring(action.action);return step=='perform'or step=='complete'
    end),
    finish=observe(function(action,step,succeeded)
     if action==body then bodyRecord.finishes[#bodyRecord.finishes+1]={phase=step,succeeded=succeeded==true,at=now()}end
    end)}),'native makeup lifecycle observer unavailable')
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);player:setAutoDrink(false)
   ready=true;emit({event='setup',cases=config.cases,queueEnabled=not native,nativeDurations=true,avatarSupported=true,captureSupported=true})
  end
  assert(now()-since<180000,'makeup timeout '..tostring(case())..' phase='..phase)
  intact()
  if phase=='prepare'then
   if config.options and config.options.makeup_supplies==true and index==1 then
    assert(type(makeupClientReady)=='function','test-only native clothing connection readiness probe unavailable')
    if not makeupClientReady()then return end
   end
   if not empty()then return end
   if config.options and config.options.makeup_supplies==true then
    if not placement then
     local square=require('QueueEnergyPlacement')(player)
     placement={x=square:getX(),y=square:getY(),z=square:getZ()};return
    end
    if index==1 and not F.atPlacement(player,placement)then return end
    assert(F.atPlacement(player,placement),'makeup supply actor left the settled placement tile')
   end
   checkpoints,sequence,outcomes,transferStarts={},0,{},0;phase='prepared';command('Prepare',{placement=placement})
  elseif phase=='prepared'and ids then
   if not state then state=F.resolve(player,ids);if not state then return end end
   if player:tooDarkToRead()then return end
   checkpoint('baseline','open')
  elseif phase=='checkpoint'and authority then
   assert(authority.case==case()and authority.label==pending.label and authority.sequence==pending.sequence,'authority checkpoint identity differs')
   local nextPhase=pending.nextPhase;pending.nextPhase=nil
   checkpoints[#checkpoints+1]={client=pending,authority=authority};pending,authority=nil,nil;phase=nextPhase
  elseif phase=='open'then open()
  elseif phase=='render'and renderWitness then checkpoint(renderLabel,renderNext)
  elseif phase=='after-preview'then
   if case()=='preview-close'then close();checkpoint('closed','tail')
   elseif case()=='preview-location'then choose(ids.alternate);rendered('same-preview','location-clear')
   else apply()end
  elseif phase=='location-clear'then chooseLocation(ids.different);checkpoint('location-cleared','different')
  elseif phase=='different'then choose(ids.different,true);rendered('different-preview','close-location')
  elseif phase=='close-location'then close();checkpoint('closed','tail')
  elseif phase=='wait-front'then
   if queue().current~=front or not front.action or not front:isStarted()or front:getJobDelta()<=0 then return end
   assert(not body.action and bodyRecord.starts==0,'pending makeup body allocated before cancellation')
   local accepted,reason=false,false
   if not native then accepted,reason=T.ActionQueue.cancelOperation(queue(),body);assert(accepted,'pending makeup cancellation rejected '..tostring(reason))end
   edit={at=now(),accepted=accepted,bodyUnallocated=true,bodyAbsent=queue():indexOf(body)==-1,
    frontSame=queue().current==front,frontNative=tostring(front.action),tailRetained=queue():indexOf(tail)~=-1,reason=reason or false}
   assert(edit.frontSame and edit.tailRetained,'makeup cancellation lost independent readers')
   raw('EDIT',{case=case(),evidence=edit});checkpoint('cancelled','wait-body')
  elseif phase=='wait-body'then afterBody()
  elseif phase=='close-overlap'then close();checkpoint('closed','final-drain')
  elseif phase=='tail'then addTail();phase='final-drain'
  elseif phase=='final-drain'then
   if not empty()or snapshot().tailPages~=ids.tailTotal then finalQuiet=nil;return end
   finalQuiet=finalQuiet or now();if now()-finalQuiet<1500 then return end
   checkpoint('final','verify')
  elseif phase=='verify'then phase='verified';command('Finish')
  elseif phase=='verified'and verified then
   assert(verified.case==case()and verified.sequence==sequence,'authority final receipt identity differs')
   local final=snapshot();local output=F.output(verified.snapshot,ids)
   emit({event='case',id=case(),status='passed',ids=ids,checkpoints=checkpoints,receipt=verified,clientFinal=final,
    submitted=submitted,second=second or false,output=output,body=bodyRecord or false,outcomes=outcomes,
    edit=edit or false,beforeTail=beforeTail,nativeMethodsUnchanged=true,applyQueues=applyQueues,supplyTransferStarts=ids.supply and transferStarts or nil})
   previous=ids;index=index+1
   state,ids,ui,front,tail,body,submitted,second,beforeTail,edit,verified,pending,authority=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
   bodyQuiet,finalQuiet,renderWitness,renderLabel,renderNext,bodyRecord,applyQueues=nil,nil,nil,nil,nil,nil,nil;since=now();phase='prepare'
   if not case()then emit({event='complete',cases=config.cases,performed=#config.cases,skipped=0,failed=0});raw('COMPLETE',{cases=config.cases});done=true end
  end
 end)
 if not ok then
  emit({event='case',id=case(),status='failed',phase=phase,reason=tostring(problem),ids=ids or false,
   checkpoints=checkpoints or{},clientActual=state and snapshot()or false})
  print('[QUEUE_TEST] FAIL makeup '..tostring(problem));done=true
 end
end)
