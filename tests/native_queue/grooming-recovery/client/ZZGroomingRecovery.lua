require 'PZSurvivorToolkit/ActionQueuePanel'
require 'XpSystem/ISUI/ISCharacterScreen'
require 'TimedActions/ISReadABook'
require 'TimedActions/ISTrimBeard'
local F=require 'QueueGroomingRecovery';local JSON=require 'QueueHealthEvents';local config=require 'QueueTestSelection'
local Proof=require 'PZSurvivorToolkit/SourceProof';local T=PZSurvivorToolkit;local R=T.ActionQueueRecovery
local native=config.mode=='native';local producer=ISCharacterScreen.onTrimBeard
local trimClass=ISTrimBeard;local methods={}
for _,name in ipairs({'new','getDuration','isValid','start','stop','update','perform','complete','begin','adjustMaxTime','forceCancel','forceStop'})do methods[name]=trimClass[name]end
Events.OnPreUIDraw.Add(function()
 if isIngameState()then return end
 local main=MainScreen and MainScreen.instance;local panel=main and main.charCreationMain
 if not panel or not panel.genderCombo or not main.desc or not main.avatar then return end
 if panel.genderCombo.selected~=2 or main.desc:isFemale()then
  assert(Proof.closure(panel.onGenderSelected,'CharacterCreationMain.lua'));panel.genderCombo.selected=2;panel:onGenderSelected(panel.genderCombo)
 end
end)
local entered,ready,done=false,false,false
local phase,index,since='prepare',1,0
local state,authority,previous,ids,authorityBaseline,removed,authorityFinal,input,quiet
local tracks,commands,starts,cancellations,recoveries,admission,draining,generation,body
local tokenIds,serial={},0
local function tokenID(token)
 assert(type(token)=='table','operation token missing')
 if not tokenIds[token]then serial=serial+1;tokenIds[token]=serial end;return tokenIds[token]
end
local function now()return getTimestampMs()end
local function case()return config.cases[index]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function raw(marker,value)print('[GROOMING_RECOVERY] '..marker..' '..JSON.encode(value))end
local function emit(row)row.suite,row.kind,row.mode,row.actor='grooming-recovery',config.kind,config.mode,'client1';JSON.emit(row)end
local function fail(error)
 if done then return end
 emit({event='case',id=case(),status='failed',reason=tostring(error),phase=phase,ids=ids,commands=commands,cancellations=cancellations,recoveries=recoveries})
 print('[QUEUE_TEST] FAIL grooming-recovery '..tostring(error));done=true
end
local function intact()
 assert(ISTrimBeard==trimClass and ISCharacterScreen.onTrimBeard==producer and Proof.closure(producer,'ISCharacterScreen.lua'),'native beard producer replaced')
 for name,callback in pairs(methods)do
  assert(trimClass[name]==callback,'native beard method replaced '..name)
 end
 for _,name in ipairs({'new','getDuration','isValid','start','stop','update','perform','complete'})do assert(Proof.closure(methods[name],'ISTrimBeard.lua'),'native beard source differs '..name)end
end
local function role(action)
 if not state or action.character~=state.player then return end
 if action.Type=='ISTrimBeard'then assert(action.item and action.item:getID()==ids.razor.id and action.beardStyle==ids.targetBeard);return'trim'end
 if action.Type=='ISReadABook'and action.item then
  if action.item:getID()==ids.front.id then return'front'elseif action.item:getID()==ids.tail.id then return'tail'end
 end
end
local function captureDuration(action,row)
 if row.allocatedAt then assert(action.maxTime==row.effectiveDuration,'native allocated duration changed');return end
 if not action.action then return end
 local after=action:adjustMaxTime(row.duration);local at=now();local before=row.nativeDurationBefore
 assert(before>1 and after>1 and action.maxTime>1 and math.abs(after-before)<=math.max(.001,row.duration*.00001),'invalid native allocation duration bracket')
 assert(action.maxTime>=math.min(before,after)-.001 and action.maxTime<=math.max(before,after)+.001,'shortened native duration')
 row.nativeDurationAfter=after;row.durationSampleAfter=at;row.effectiveDuration=action.maxTime;row.allocatedAt=at
end
-- Admission observation only. Native begin/update/perform/complete remain intact.
local add=ISTimedActionQueue.add
ISTimedActionQueue.add=function(action)
 local name=tracks and role(action);local row
 if name then
  assert(not tracks[action],'native action admitted twice')
  row={role=name,generation=generation,type=action.Type,itemId=action.item:getID(),duration=action.maxTime,
   nativeDurationBefore=action:adjustMaxTime(action.maxTime),durationSampleBefore=now(),durationSamples=1,
   started=false,progress=false,cancelled=false,callbacksIntact=true,nativeSource=true}
  tracks[action]=row;commands[#commands+1]=row
  if name=='trim'then intact();assert(getmetatable(action)==trimClass and action.maxTime==300 and not action.action,'non-native trim admission')end
 end
 local result=add(action)
 if row then row.token=tokenID(action.toolkitQueueOperation);captureDuration(action,row)end
 return result
end
local function observe()
 intact()
 for action,row in pairs(tracks or{})do
  if row.role=='trim'then
   for name,callback in pairs(methods)do assert(action[name]==callback,'native beard instance callback replaced '..name)end
   for _,name in ipairs({'onStartFunc','onCancelFunc','onCompleteFunc','onFailFunc','retriggerLastAction','additionalTest','additionalContext'})do assert(not action[name],'injected native beard callback '..name)end
  end
  if not row.cancelled then
   if not action.action then row.nativeDurationBefore=action:adjustMaxTime(row.duration);row.durationSampleBefore=now();row.durationSamples=row.durationSamples+1
   else captureDuration(action,row)end
   if queue().current==action and action.action and action:isStarted()then
    if not row.started then row.started=true;row.startedAt=now();row.nativeRef=tostring(action.action);starts[#starts+1]=row.role..':'..row.generation end
    local initial=action.Type=='ISReadABook'and action.startPage/action.item:getNumberOfPages()or 0
    if action:getJobDelta()>initial then row.progress=true end
    if isClient()and row.role=='trim'and not row.ack then
     local receipt=T.ActionQueueAcknowledgements.capture(action)
     if receipt then
      row.ack={kind=receipt.kind,transaction=receipt.transaction,token=receipt.token,state='started'};row.receipt=receipt
      raw('ACK',{case=case(),generation=row.generation,kind=receipt.kind,transaction=receipt.transaction,token=receipt.token,state='started'})
     end
    end
   end
   if row.receipt then
    local terminal=T.ActionQueueAcknowledgements.observe(action,row.receipt)
    if terminal and terminal~='started'and row.ack.state=='started'then
     row.ack.state=terminal;raw('ACK',{case=case(),generation=row.generation,kind=row.ack.kind,transaction=row.ack.transaction,token=row.ack.token,state=terminal})
    end
   end
  end
 end
end
local function read(name)
 local item=assert(F.find(state.player,ids[name].id));local action=ISReadABook:new(state.player,item);ISTimedActionQueue.add(action);return action
end
local function queueEvidence()
 local rows={};local seen={}
 for _,action in ipairs(queue().queue)do
  local name=role(action)
  if not name then
   local record=action.toolkitQueueCommand and action.toolkitQueueCommand.snapshot
   assert(T.ActionQueueOperations.isCommand(action)and record.kind=='read'and record.character==state.player,'foreign recovery preparation')
   name=record.itemId==ids.front.id and'front'or record.itemId==ids.tail.id and'tail'or nil;assert(name,'foreign recovered reader')
  end
  local token=assert(action.toolkitQueueOperation);assert(not seen[token],'non-singleton physical operation');seen[token]=true
  rows[#rows+1]={role=name,type=action.Type,token=tokenID(token),itemId=name=='trim'and ids.razor.id or ids[name].id,allocated=action.action~=nil}
 end
 return rows
end
local function request(command)
 if isClient()then sendClientCommand('GroomingRecoveryTest',command,{case=case()});return end
 if command=='Prepare'then authority=F.prepare(getPlayer(),case(),config.mode,previous);previous=nil;ids=authority.ids;raw('PREPARED',ids)
 elseif command=='Baseline'then authorityBaseline=F.snapshot(authority);assert(F.same(authorityBaseline,ids.baseline));raw('BASELINE',authorityBaseline)
 elseif command=='Remove'then removed=F.removeRazor(authority);raw('REMOVED',removed)
 elseif command=='Verify'then authorityFinal=assert(F.verify(authority));raw('VERIFIED',authorityFinal)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~='GroomingRecoveryTest'or done then return end
 if command=='Failed'then fail(args.error);return end
 if not args or args.case~=case()then return end
 if command=='Prepared'then ids=args elseif command=='Baselined'then authorityBaseline=args elseif command=='Removed'then removed=args elseif command=='Verified'then authorityFinal=args end
end)
local function enqueue()
 input=F.snapshot(state);assert(F.same(input,ids.baseline));tracks,commands,starts,cancellations,recoveries={},{},{},{},{};generation=0
 if case()~='active-denied'then read('front')end
 local p,root=state.player,state.player:getInventory();local razor=assert(F.find(p,ids.razor.id));assert(p:getPrimaryHandItem()==razor and not p:getSecondaryHandItem()and razor:getContainer()==root and razor:isFavorite())
 local before=#queue().queue;producer(p,'Moustache');assert(#queue().queue==before+1,'native menu producer added equipment/preparation chain')
 body=queue().queue[#queue().queue];assert(body.Type=='ISTrimBeard'and body.item==razor and(case()=='active-denied'or not body.action),'pending trim was allocated at menu admission')
 admission={producer='ISCharacterScreen.onTrimBeard',target='Moustache',initial='LongScruffy',singleton=true,alreadyHeld=true,exactRootTool=true,preparationCount=0,sourceBound=true,queue=queueEvidence()}
 read('tail');phase='boundary'
end
local function cancel()
 local steps=queueEvidence();local natives,tokens={},{}
 for _,action in ipairs(queue().queue)do
  tokens[#tokens+1]=action.toolkitQueueOperation
  if action.action then natives[#natives+1]=action.action end
  if tracks[action]then tracks[action].cancelled=true end
 end
 local current=queue().current;local row=current and tracks[current]
 local receipt={generation=generation,entrypoint='ISTimedActionQueue.clear',steps=steps,before=F.snapshot(state),nativeCount=#natives,
  boundary={role=row and row.role or false,started=row and row.started or false,progress=row and row.progress or false,
   delta=current and current:getJobDelta()or 0,trimUnallocated=body.action==nil,startedReceipt=row and row.ack or false}}
 ISTimedActionQueue.clear(state.player)
 receipt.oldTokens={};for _,token in ipairs(tokens)do receipt.oldTokens[#receipt.oldTokens+1]={id=tokenID(token),cancelled=token.toolkitCancelled==true}end
 cancellations[#cancellations+1]=receipt;draining={receipt=receipt,natives=natives};phase='drain'
end
local function restore()
 assert(empty()and draining.receipt.drained,'restore before cancellation drain')
 local p=state.player
 if native then
  assert(not R.info(p)and not R.preview(p)and not R.restore(p),'disabled queue recovered work')
  recoveries[#recoveries+1]={available=false,restored=false,historyAbsent=true};phase='running';return
 end
 local info=assert(R.info(p));local preview=assert(R.preview(p));local count=case()=='active-denied'and 1 or 3
 assert(info.count==count and info.skipped==(case()=='active-denied'and 1 or 0),'wrong recovery eligibility')
 local before=JSON.encode(F.snapshot(state));local beforeQueue=JSON.encode(queueEvidence());R.preview(p)
 assert(JSON.encode(F.snapshot(state))==before and JSON.encode(queueEvidence())==beforeQueue,'preview mutated state or queue')
 local receipt={id=info.id,count=info.count,skipped=info.skipped,reason=info.reason or false,available=preview.available,previewPure=true,generation=generation+1}
 assert(not R.restore(p,info.id-1),'stale recovery ID accepted');receipt.staleRejected=true
 if case()=='lost-tool'then
  assert(preview.available==false and not R.restore(p,info.id),'lost exact tool restored')
  assert(empty()and JSON.encode(F.snapshot(state))==before and R.info(p).id==info.id,'failed recovery had side effects')
  receipt.restored=false;receipt.refusedWithoutEffects=true;receipt.historyAbsent=false;recoveries[#recoveries+1]=receipt;phase='running';return
 end
 assert(preview.available==true);generation=generation+1
 assert(R.restore(p,info.id),'public recovery failed');receipt.restored=true;receipt.duplicateRejected=not R.restore(p,info.id);receipt.historyAbsent=not R.info(p)
 assert(receipt.duplicateRejected and receipt.historyAbsent);receipt.steps=queueEvidence()
 for _,step in ipairs(receipt.steps)do if step.role=='trim'then assert(not step.allocated,'pending restored trim already allocated')end end
 recoveries[#recoveries+1]=receipt
 if case()=='pending-restore'and generation<3 then phase='recovery-boundary'else phase='running'end
end
local function finish()
 local actual=assert(F.verify(state));local cleanCommands={}
 for _,row in ipairs(commands)do
  local clean={};for key,value in pairs(row)do if key~='receipt'then clean[key]=value end end;cleanCommands[#cleanCommands+1]=clean
 end
 emit({event='case',id=case(),status='passed',ids=ids,input=input,authorityBaseline=authorityBaseline,removed=removed or false,
  client=actual,server=authorityFinal,admission=admission,cancellations=cancellations,recoveries=recoveries,commands=cleanCommands,starts=starts,queueIdle=true,settleMilliseconds=now()-quiet,
  completionProof=isClient()and'sealed-native-outcome-and-authority-effects'or'native-authority-effects'})
 previous=ids;index=index+1
 if not case()then emit({event='complete',cases=config.cases,performed=3,failed=0,skipped=0});raw('COMPLETE',{cases=config.cases});done=true;return end
 state,authority,ids,authorityBaseline,removed,authorityFinal,input,quiet,tracks,commands,starts,cancellations,recoveries,admission,draining,body=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
 phase='prepare';since=now()
end
Events.OnGameStart.Add(function()entered=true;since=now()end)
Events.OnTick.Add(function()
 if not entered or done then return end
 local ok,error=pcall(function()
  local p=getPlayer();if not isIngameState()or not p or not p:getSquare()then return end
  if not ready then
   if isClient()~=(config.kind=='mp')or isClient()and(p:getOnlineID()<0 or p:getUsername()~='client1')then return end
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(not native)
   assert(T.Settings.actionQueue()==not native and not p:isTimedActionInstant()and not getDebug())
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);p:setAutoDrink(false)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
   ready=true;emit({event='setup',cases=config.cases,queueEnabled=not native,nativeDurations=true,blocker='native-reader-three-pages'})
  end
  assert(now()-since<150000,'grooming recovery timeout '..phase);observe()
  if phase=='prepare'then assert(empty());phase='prepared';request('Prepare')
  elseif phase=='prepared'and ids then state=F.resolve(p,ids);if not state or p:tooDarkToRead()then return end;phase='baseline';request('Baseline')
  elseif phase=='baseline'and authorityBaseline then enqueue()
  elseif phase=='boundary'then
   local current=queue().current;local row=current and tracks[current]
   if not row or not row.started or not row.progress then return end
   if case()=='active-denied'then
    assert(current==body and row.role=='trim');if isClient()and not row.ack then return end
    if current:getJobDelta()<.02 then return end;assert(current:getJobDelta()<.5,'active trim already near completion')
   else assert(row.role=='front'and not body.action,'pending trim started before reset')end
   assert(F.same(F.snapshot(state),input),'native pending/reset boundary mutated input');cancel()
  elseif phase=='recovery-boundary'then
   local current=queue().current;local row=current and tracks[current]
   if not row or not row.started or not row.progress then return end
   assert(row.role=='front'and row.generation==generation and not body.action,'repeated pending trim allocated')
   assert(F.same(F.snapshot(state),input),'reader checkpoint advanced before repeated reset');cancel()
  elseif phase=='drain'and empty()and not p:isPlayerMoving()and not p:pressedMovement(false)then
   for _,action in ipairs(draining.natives)do assert(not p:getCharacterActions():contains(action),'cancelled Java action retained')end
   draining.receipt.drained=true;draining.receipt.movementStopped=true
   if case()=='lost-tool'and not removed then phase='removed';request('Remove')else restore()end
  elseif phase=='removed'and removed then if not F.same(F.snapshot(state),removed)then return end;restore()
  elseif phase=='running'and empty()then
   if not F.verify(state)then quiet=nil;return end
   if isClient()and case()=='pending-restore'and not native then
    local paid;for _,row in ipairs(commands)do if row.role=='trim'and row.generation==3 then paid=row end end
    if not paid or not paid.ack or paid.ack.state~='completed'then return end
   end
   quiet=quiet or now();if now()-quiet>=1000 then phase='verify';request('Verify')end
  elseif phase=='verify'and authorityFinal then finish()end
 end)
 if not ok then fail(error)end
end)
