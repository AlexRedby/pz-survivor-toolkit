require 'PZSurvivorToolkit/ActionQueuePanel'
require 'RadioCom/RadioWindowModules/RWMMergedTV'
require 'TimedActions/ISReadABook'
local F=require 'QueueRecovery'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local T=PZSurvivorToolkit
local R=T.ActionQueueRecovery
local WishlistGate=require 'RecoveryWishlistUI'
local ProjectionUI=require 'QueueProjectionUI'
local wishlistGate,wishlistReceipt,previewWatch,previewWorkload
local native=config.mode=='native'
local started,ready,done=false,false,false
local phase,index,since='prepare',1,0
local state,authority,ids,baselineReceipt,receipt,tracks,commands,order,panel,quiet
local cancelled,restoration,oldActions,oldNatives,oldTokens,restoredQueue
local tokenIds,tokenSerial={},0
local function tokenId(token)
 if type(token)~='table'then return false end
 if not tokenIds[token]then tokenSerial=tokenSerial+1;tokenIds[token]=tokenSerial end
 return tokenIds[token]
end
local function now()return getTimestampMs()end
local function case()return config.cases[index]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function raw(event,value)print('[QUEUE_RECOVERY] '..event..' '..JSON.encode(value))end
local function emit(row)row.suite,row.kind,row.mode,row.actor='queue-recovery',config.kind,config.mode,'client1';JSON.emit(row)end
local function fail(error)
 if done then return end
 local pending={}
 for _,action in ipairs(queue().queue)do
  pending[#pending+1]={type=action.Type,itemId=action.item and action.item:getID()or false,
   mode=action.mode or false,value=type(action.secondaryItem)=='number'and action.secondaryItem or false,
   current=action==queue().current,token=tokenId(action.toolkitQueueOperation)}
 end
 emit({event='case',id=case(),status='failed',reason=tostring(error),phase=phase,ids=ids,commands=commands,order=order,
  pending=pending,wishlist=wishlistReceipt})
 print('[QUEUE_TEST] FAIL queue-recovery '..tostring(error));done=true
end
local function request(command)
 if isClient()then sendClientCommand('QueueRecoveryTest',command,{case=case()});return end
 if command=='Prepare'then authority=F.prepare(getPlayer(),case(),config.mode);ids=authority.ids;raw('PREPARED',ids)
 elseif command=='Baseline'then baselineReceipt=assert(F.baseline(authority));raw('BASELINE',baselineReceipt)
 else receipt=assert(F.verify(authority));raw('VERIFIED',receipt)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if done then return end
 if module=='QueueRecoveryTest'then
  if command=='Failed'then fail(args and args.error or'authority failed')
  elseif args and args.case==case()then
   if command=='Prepared'then ids=args elseif command=='Baselined'then baselineReceipt=args elseif command=='Verified'then receipt=args end
  end
 elseif module=='PZSurvivorToolkitActions'and command=='State'and tracks then
  local found
  for action,row in pairs(tracks)do
   if row.type=='ISRadioAction'and args.state=='started'and queue().current==action and action.toolkitNativeTransaction==args.transaction
    and action.toolkitNativeKind==args.kind and action.character:getOnlineID()==args.player then found=row;break
   elseif row.ack and row.ack.token==args.token then found=row;break end
  end
  if not found then return end
  local ok,error=pcall(function()
   assert(args.protocol==1 and args.kind=='ISRadioAction'and type(args.token)=='string'and #args.token==36)
   if args.state=='started'then assert(not found.ack);found.ack={kind=args.kind,transaction=args.transaction,token=args.token,state='started'}
   else assert(found.ack and found.ack.state=='started'and args.state=='completed'and found.ack.transaction==args.transaction);found.ack.state='completed'end
   raw('ACK',{case=case(),name=found.name,kind=args.kind,transaction=args.transaction,token=args.token,state=args.state})
  end)
  if not ok then fail(error)end
 end
end)
local function finite(value)
 return type(value)=='number'and value==value and value>-math.huge and value<math.huge
end
local function captureDuration(action,row)
 if row.allocatedAt then
  assert(action.maxTime==row.effectiveDuration,'allocated native duration changed '..row.name)
  return
 end
 if not action.action then return end
 local after=action:adjustMaxTime(row.duration);local at=now()
 local before=row.nativeDurationBefore;local effective=action.maxTime
 assert(finite(before)and finite(after)and finite(effective)and before>1 and after>1 and effective>1,
  'invalid native duration bracket '..row.name)
 -- This is an independently observed interval, not a relative tolerance on
 -- effective duration. A stale or large modifier transition fails closed.
 assert(math.abs(after-before)<=math.max(.001,row.duration*.00001),'native duration bracket too wide '..row.name)
 assert(effective>=math.min(before,after)-.001 and effective<=math.max(before,after)+.001,
  'native adjusted duration outside allocation bracket '..row.name)
 row.nativeDurationAfter=after;row.durationSampleAfter=at
 row.effectiveDuration=effective;row.allocatedAt=at
end

-- Observe admission without replacing any native action lifecycle or timer.
-- Deferred recovery reads are bound by the exact item ID when the real action is produced.
local add=ISTimedActionQueue.add
ISTimedActionQueue.add=function(action)
 local row
 if state and tracks and action.character==getPlayer()then
  local name
  if action.Type=='ISReadABook'and action.item then
   if action.item:getID()==ids.front.id then name=restoration and'restoredFront'or'front'
   elseif action.item:getID()==ids.tail.id then name=restoration and'restoredTail'or'tail'end
  elseif action.Type=='ISRadioAction'and action.device==state.tv and action.mode=='SetVolume'then
   name=action.secondaryItem==.4 and'prefix'or restoration and'restoredVolume'or'volume'
  end
  if name then
   for _,existing in ipairs(commands)do assert(existing.name~=name,'duplicate native operation '..name)end
   row={name=name,type=action.Type,mode=action.mode or'',duration=action.maxTime,producer=action.Type=='ISReadABook'and'native ISReadABook constructor'or name=='restoredVolume'and'recovery native ISRadioAction constructor'or'native RWM callback',
    started=false,progress=false,cancelled=false,itemId=action.item and action.item:getID()or false,
    initialPages=action.item and action.item:getAlreadyReadPages()or false,nativeDurationBefore=action:adjustMaxTime(action.maxTime),durationSampleBefore=now(),durationSamples=1}
   commands[#commands+1]=row;tracks[action]=row
  end
 end
 local result=add(action)
 if row then row.token=tokenId(action.toolkitQueueOperation);captureDuration(action,row)end
 return result
end
local function observe()
 for action,row in pairs(tracks or{})do
  if not row.cancelled and not row.allocatedAt and not action.action then
   row.nativeDurationBefore=action:adjustMaxTime(row.duration);row.durationSampleBefore=now();row.durationSamples=row.durationSamples+1
  elseif not row.cancelled and action.action and queue():indexOf(action)~=-1 then captureDuration(action,row)end
  if queue().current==action and action:isStarted()and not row.cancelled then
   if not row.started then row.started=true;row.startedAt=now();order[#order+1]=row.name end
   if action.Type=='ISReadABook'then if action.item:getAlreadyReadPages()>row.initialPages then row.progress=true end
   elseif action:getJobDelta()>0 then row.progress=true end
  end
 end
end
local function receipts()
 if not isClient()then return true end
 for _,row in ipairs(commands)do if row.type=='ISRadioAction'and row.started and(not row.ack or row.ack.state~='completed')then return false end end
 return true
end
local function volume(value)
 local n=#commands;panel.volumeBar.onVolumeChange(panel,value*panel.volumeBar:getVolumeSteps())
 assert(#commands==n+1,'native UI did not produce exactly one adjacent setter')
 local action;for a,r in pairs(tracks)do if r==commands[#commands]then action=a end end
 assert(action and action.Type=='ISRadioAction'and action.mode=='SetVolume'and commands[#commands].duration==30 and action.deviceData==state.data)
 return action
end
local function read(item)local action=ISReadABook:new(getPlayer(),item);ISTimedActionQueue.add(action);return action end
local function ownedApproach(action)
 local owner=T.ActionQueueApproach
 if not owner or not owner.isAction(action)or not owner.capture(action)then return false end
 local request=action.toolkitQueueCommand.snapshot
 return request.binding.owner==luautils and request.binding.name=='walkAdj'and request.args.n==3
  and request.args[1]==getPlayer()and request.args[2]==state.tv:getSquare()and request.args[3]==true
end
local function queueNames()
 local names={}
 for _,a in ipairs(queue().queue)do
  local id=a.item and a.item:getID()or a.toolkitQueueCommand and a.toolkitQueueCommand.snapshot.itemId
  names[#names+1]=id==ids.front.id and'front'or id==ids.tail.id and'tail'or ownedApproach(a)and'approach'or a.Type=='ISRadioAction'and a.secondaryItem==.25 and'volume'or a.Type
 end
 return names
end
local function same(a,b)if #a~=#b then return false end;for i,v in ipairs(a)do if b[i]~=v then return false end end;return true end
-- Physical preparation is part of the volume operation, not an independent
-- cancellation intent. Pin its exact native helper and contiguous membership.
local function queueEvidence(restored)
 local names=queueNames()
 local expected=native and{'front','volume','tail'}or{'front','approach','volume','tail'}
 assert(same(names,expected),'unexpected remainder '..JSON.encode(names))
 local steps,tokens,seen={},{},{}
 local previous
 for index,action in ipairs(queue().queue)do
  local name=names[index];local token=assert(action.toolkitQueueOperation)
  if token~=previous then
   assert(not seen[token],'interleaved recovery operation')
   tokens[#tokens+1]=token;seen[token]=true;previous=token
  end
  if restored then
   assert(not token.toolkitCancelled,'restored operation is cancelled')
   for _,old in ipairs(oldTokens)do assert(token~=old,'recovery reused cancelled token')end
  end
  local proof=false
  if name=='approach'then
   assert(ownedApproach(action),'foreign volume preparation')
   local following=queue().queue[index+1]
   assert(following and names[index+1]=='volume'and following.toolkitQueueOperation==token,'volume lost its preparation operation')
   local square=action.toolkitQueueCommand.snapshot.args[2]
   proof={owned=true,helper='walkAdj',target={x=square:getX(),y=square:getY(),z=square:getZ()}}
  elseif name=='volume'then
   assert(action.Type=='ISRadioAction'and action.device==state.tv and action.deviceData==state.data and action.mode=='SetVolume'and action.secondaryItem==.25)
   if not native then assert(queue().queue[index-1].toolkitQueueOperation==token,'volume preparation token differs')end
  elseif restored then
   local record=action.toolkitQueueCommand and action.toolkitQueueCommand.snapshot
   assert(T.ActionQueueOperations.isCommand(action)and record.kind=='read'and record.character==getPlayer()
    and record.itemId==ids[name].id,'foreign deferred read')
  else assert(action==oldActions[name=='front'and 1 or 3]and action.Type=='ISReadABook','original native read differs')end
  steps[#steps+1]={name=name,type=action.Type,token=tokenId(token),approach=proof}
 end
 assert(#tokens==3,'remainder must retain three operations')
 for index,name in ipairs(names)do
  local group=name=='front'and 1 or name=='tail'and 3 or 2
  assert(queue().queue[index].toolkitQueueOperation==tokens[group],'remainder operation order differs')
 end
 local projectionUI
 if not native then projectionUI=ProjectionUI.capture(queue(),tokens,tokenId)end
 return names,steps,tokens,projectionUI
end
local function cancel()
 oldActions={state.frontAction,volume(.25),read(state.tail)};oldNatives={};oldTokens={}
 local names,steps,tokens,projectionUI=queueEvidence(false);oldTokens=tokens
 for _,a in ipairs(oldActions)do
  if a.action then oldNatives[#oldNatives+1]=a.action end
 end
 local before=F.snapshot(state);assert(before.books.front.pages>ids.front.initial and before.books.front.pages<ids.front.pages)
 cancelled={entrypoint=case()=='movement-cancel'and'IsoGameCharacter.StopAllActionQueueWalking'or'ISTimedActionQueue.clear',before=before,initialQueue=names,steps=steps,projectionUI=projectionUI}
 if case()=='movement-cancel'then getPlayer():StopAllActionQueueWalking()else ISTimedActionQueue.clear(getPlayer())end
 for _,a in ipairs(oldActions)do tracks[a].cancelled=true end
 phase='draining'
end
local function startPreviewWatch()
 local A=T.ActionQueueRecoveryAdapters
 previewWatch={since=now(),previews=0,plans=0,before=JSON.encode(F.snapshot(state)),
  preview=R.preview,plan=A.plan}
 local watch=previewWatch
 R.preview=function(...)watch.previews=watch.previews+1;return watch.preview(...)end
 A.plan=function(...)watch.plans=watch.plans+1;return watch.plan(...)end
 phase='preview-workload'
end
local function finishPreviewWatch()
 local watch=previewWatch
 assert(empty()and JSON.encode(F.snapshot(state))==watch.before,'idle recovery preview mutated state')
 assert(watch.previews>=4 and watch.plans==0,'native UI preview reconstructed actions')
 local live=false;local windows=UIManager.getUI()
 for i=0,windows:size()-1 do
  local element=windows:get(i);local view=element and element.getTable and element:getTable()
  if type(view)=='table'and getmetatable(view)==T.ActionQueuePanel and view.queue==queue()and view:getIsVisible()then live=true end
 end
 assert(live,'recovery preview did not have a visible native queue panel')
 R.preview,T.ActionQueueRecoveryAdapters.plan=watch.preview,watch.plan
 previewWorkload={elapsedMs=now()-watch.since,previews=watch.previews,plans=watch.plans,nativeUI=true}
 previewWatch=nil
end
local function restore()
 local player=getPlayer();assert(empty()and not player:isPlayerMoving()and not player:pressedMovement(false))
 for _,a in ipairs(oldNatives)do assert(not player:getCharacterActions():contains(a),'cancelled Java action still retained')end
 cancelled.drained=true;cancelled.movementStopped=true;cancelled.nativeCount=#oldNatives
 cancelled.oldTokens={};for _,token in ipairs(oldTokens)do
  cancelled.oldTokens[#cancelled.oldTokens+1]={id=tokenId(token),cancelled=type(token)=='table'and token.toolkitCancelled==true}
 end
 if native then
  assert(not R.info(player)and not R.preview(player),'disabled queue retained recovery history')
  restoration={available=false,restored=false,historyAbsent=true,duplicateRejected=true};phase='running';return
 end
 local info=assert(R.info(player));local preview=assert(R.preview(player))
 assert(info.count==3 and info.skipped==0 and preview.available==true,'remainder unavailable '..JSON.encode(preview))
 assert(not R.restore(player,info.id-1),'stale recovery ID accepted')
 local before=JSON.encode(F.snapshot(state));R.preview(player);assert(JSON.encode(F.snapshot(state))==before,'preview mutated world/pages')
 restoration={id=info.id,count=info.count,skipped=info.skipped,available=preview.available,restored=false,historyAbsent=false,duplicateRejected=false,previewPure=true,previewWorkload=previewWorkload}
 assert(R.restore(player,info.id),'public recovery failed');restoration.restored=true
 restoration.duplicateRejected=not R.restore(player,info.id);restoration.historyAbsent=not R.info(player)
 assert(restoration.duplicateRejected and restoration.historyAbsent)
 local steps,tokens,projectionUI
 restoredQueue,steps,tokens,projectionUI=queueEvidence(true);restoration.steps=steps;restoration.tokens={};restoration.projectionUI=projectionUI
 for _,token in ipairs(tokens)do restoration.tokens[#restoration.tokens+1]=tokenId(token)end
 phase='running'
end
local function finish()
 local client=assert(F.verify(state));assert(receipt and receipts())
 local expected=native and{'prefix','front'}or{'prefix','front','restoredFront','restoredVolume','restoredTail'}
 assert(same(order,expected),'actual native starts differ '..JSON.encode(order))
 emit({event='case',id=case(),status='passed',ids=ids,input=state.input,baseline=state.baseline,authorityBaseline=baselineReceipt,
  client=client,server=receipt,commands=commands,order=order,cancellation=cancelled,recovery=restoration,wishlist=wishlistReceipt,restoredQueue=restoredQueue or{},queueIdle=true,settleMilliseconds=now()-quiet})
 index=index+1
 if not case()then emit({event='complete',cases=config.cases,performed=2,failed=0,skipped=0});raw('COMPLETE',{cases=config.cases});done=true;return end
 state,authority,ids,baselineReceipt,receipt,tracks,commands,order,panel,quiet=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
 cancelled,restoration,oldActions,oldNatives,oldTokens,restoredQueue=nil,nil,nil,nil,nil,nil
 wishlistGate,wishlistReceipt,previewWorkload=nil,nil,nil;phase='prepare';since=now()
end
Events.OnPostUIDraw.Add(function()
 if not wishlistGate or done then return end
 local ok,error=pcall(function()wishlistGate:draw()end);if not ok then fail(error)end
end)
Events.OnGameStart.Add(function()started=true;since=now()end)
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,error=pcall(function()
  local player=getPlayer();if not isIngameState()or not player or not player:getSquare()then return end
  if not ready then
   if isClient()~=(config.kind=='mp')or isClient()and(player:getOnlineID()<0 or player:getUsername()~='client1')then return end
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(not native)
   assert(T.Settings.actionQueue()==not native and not player:isTimedActionInstant())
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
   ready=true;emit({event='setup',cases=config.cases,queueEnabled=not native,nativeDurations=true})
  end
  assert(now()-since<150000,'recovery timeout '..tostring(case())..' phase='..phase)
  observe()
  if phase=='prepare'then assert(empty());phase='prepared';request('Prepare')
  elseif phase=='prepared'and ids then
   state=F.resolve(player,ids);if not state or player:tooDarkToRead()or not F.approach(state)then return end
   tracks,commands,order={},{},{};state.input=F.snapshot(state)
   panel=RWMMergedTV:new(-1000,-1000,300,100);panel:initialise();panel:instantiate();assert(panel:readFromObject(player,state.tv,state.data,'IsoObject'))
   wishlistGate=WishlistGate.new();phase='wishlist-ui'
  elseif phase=='wishlist-ui'then
   wishlistReceipt=wishlistGate:tick()
   if wishlistReceipt then wishlistGate=nil;volume(.4);phase='prefix'end
  elseif phase=='prefix'and empty()and receipts()then assert(math.abs(state.data:getDeviceVolume()-.4)<.0001);state.frontAction=read(state.front);phase='front'
  elseif phase=='front'and tracks[state.frontAction].progress then cancel()
  elseif phase=='draining'and empty()and not player:isPlayerMoving()and not player:pressedMovement(false)then
   if not F.baseline(state)then return end
   phase='authorityBaseline';request('Baseline')
  elseif phase=='authorityBaseline'and baselineReceipt then if native then restore()else startPreviewWatch()end
  elseif phase=='preview-workload'and now()-previewWatch.since>=1700 then finishPreviewWatch();restore()
  elseif phase=='running'and empty()then
   if not F.verify(state)or not receipts()then quiet=nil;return end
   quiet=quiet or now();if now()-quiet>=1000 then phase='verified';request('Verify')end
  elseif phase=='verified'and receipt then finish()end
 end)
 if not ok then fail(error)end
end)
