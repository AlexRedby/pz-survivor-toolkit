require 'PZSurvivorToolkit/ActionQueuePanel'
require 'RadioCom/RadioWindowModules/RWMMergedTV'
require 'RadioCom/RadioWindowModules/RWMMedia'
require 'RadioCom/RadioWindowModules/RWMVolume'
require 'TimedActions/ISReadABook'
local F=require 'QueueTVControls'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local T=PZSurvivorToolkit
local native=config.mode=='native'
local started,ready,done=false,false,false
local phase,index,since='prepare',1,0
local diagnosed=false
local state,localAuthority,ids,baselineReceipt,receipt,panels,tracks,commands,setup,order,initialQueue,editedQueue,edit,quiet
local function now()return getTimestampMs()end
local function case()return config.cases[index]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function raw(event,value)print('[TV_CONTROLS] '..event..' '..JSON.encode(value))end
local function emit(row)
 row.suite,row.kind,row.mode,row.actor='tv-controls',config.kind,config.mode,'client1';JSON.emit(row)
end
local function fail(error)
 if done then return end
 local actual
 if state then local ok,v=pcall(F.snapshot,state);if ok then actual=v end end
 emit({event='case',id=case(),status='failed',reason=tostring(error),ids=ids,client=actual,server=receipt,
  phase=phase,commands=commands,setup=setup,order=order})
 print('[QUEUE_TEST] FAIL tv-controls '..tostring(error));done=true
end
local function request(command)
 if isClient()then sendClientCommand('TVControlsTest',command,{case=case()});return end
 if command=='Prepare'then
  localAuthority=F.prepare(getPlayer(),case(),config.mode);ids=localAuthority.ids;raw('PREPARED',ids)
 elseif command=='Baseline'then baselineReceipt=assert(F.baseline(localAuthority));raw('BASELINE',baselineReceipt)
 else receipt=assert(F.verify(localAuthority));raw('VERIFIED',receipt)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if done then return end
 if module=='TVControlsTest'then
  if command=='Failed'then fail(args and args.error or 'authority failed')
  elseif args and args.case==case()then
   if command=='Prepared'then ids=args elseif command=='Baselined'then baselineReceipt=args
   elseif command=='Verified'then receipt=args end
  end
 elseif module=='PZSurvivorToolkitActions'and command=='State'and isClient()and tracks then
  local found
  for action,row in pairs(tracks)do
   if row.type~='ISReadABook'and args.state=='started'and queue().current==action and action.toolkitNativeTransaction==args.transaction
    and action.toolkitNativeKind==args.kind and action.character:getOnlineID()==args.player then found=row;break
   elseif row.type~='ISReadABook'and row.ack and row.ack.token==args.token then found=row;break end
  end
  if not found then return end
  local ok,error=pcall(function()
   assert(args.protocol==1 and args.kind==found.type and type(args.token)=='string'and #args.token==36,'bad native ACK binding')
   if args.state=='started'then
    assert(not found.ack,'duplicate native started ACK')
    found.ack={token=args.token,transaction=args.transaction,kind=args.kind,state='started'}
   else
    assert(found.ack and found.ack.state=='started'and args.state=='completed','native TV command did not complete')
    assert(found.ack.transaction==args.transaction and found.ack.kind==args.kind,'native ACK identity changed')
    found.ack.state=args.state
   end
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
local function register(name,action,rows,producer,duration,before,beforeAt)
 assert(action and not tracks[action],'duplicate fixture action')
 local row={name=name,type=action.Type,mode=action.mode or '',duration=duration or action.maxTime,
  producer=producer,started=false,progress=false,cancelled=false}
 assert(type(row.duration)=='number'and row.duration>0,'native constructor duration missing')
 row.nativeDurationBefore=before or action:adjustMaxTime(row.duration)
 row.durationSampleBefore=beforeAt or now();row.durationSamples=1
 tracks[action]=row;rows[#rows+1]=row;captureDuration(action,row);return action,row
end
local function nativeUI(name,rows,invoke,kind,mode)
 local emitted,declared,before,beforeAt={},{},{},{};local add=ISTimedActionQueue.add
 ISTimedActionQueue.add=function(action)
  emitted[#emitted+1]=action;declared[#emitted]=action.maxTime
  before[#emitted]=action:adjustMaxTime(action.maxTime);beforeAt[#emitted]=now()
  return add(action)
 end
 local ok,error=pcall(invoke);ISTimedActionQueue.add=add;assert(ok,error)
 if #emitted~=1 then raw('APPROACH_FAILURE',{case=case(),name=name,actual=F.approach(state),emitted=#emitted})end
 assert(#emitted==1,'adjacent native UI producer emitted unexpected work '..name..' count='..#emitted)
 local a=emitted[1]
 assert(a.Type==kind and (not mode or a.mode==mode),'wrong native TV UI action '..name)
 assert(declared[1]==30 and a.stopOnWalk==false and a.stopOnRun==true and a.ignoreHandsWounds==true,
  'native TV UI timing/flags changed '..name)
 if kind=='ISRadioAction'then assert(a.device==state.tv and a.deviceData==state.data)
 else assert(a.deviceData==state.data and a.parameter==state.tv:getSquare())end
 register(name,a,rows,'native RWM callback',declared[1],before[1],beforeAt[1]);return a
end
local function book(name,item)
 local a=ISReadABook:new(getPlayer(),item);register(name,a,commands,'native ISReadABook constructor')
 ISTimedActionQueue.add(a);captureDuration(a,tracks[a]);return a
end
local function observe()
 local current=queue().current
 for action,row in pairs(tracks or {})do
  if not row.cancelled and not row.allocatedAt and not action.action then
   row.nativeDurationBefore=action:adjustMaxTime(row.duration);row.durationSampleBefore=now()
   row.durationSamples=row.durationSamples+1
  elseif action.action and queue():indexOf(action)~=-1 then captureDuration(action,row)end
  if current==action and action:isStarted()then
   assert(not row.cancelled,'cancelled TV setter started')
   if not row.started then
    assert(row.allocatedAt,'native allocation duration was not observed '..row.name)
    row.started=true;row.startedAt=now()
    if row.name=='eject'then
     row.mediaAtStart=state.data:getMediaIndex();row.playingAtStart=state.data:isPlayingMedia()
     assert(row.mediaAtStart==ids.tape.index and row.playingAtStart==(case()=='eject-playing'),'eject lost native media/playback baseline')
    end
    if row.name~='insert'and row.name~='play'then order[#order+1]=row.name end
   end
   if row.type=='ISReadABook'then
    local spec=row.name=='front'and ids.front or ids.tail
    if action.item:getAlreadyReadPages()>spec.initial then row.progress=true end
   elseif action:getJobDelta()>0 then row.progress=true end
  end
 end
end
local function allReceipts()
 if not isClient()then return true end
 for _,rows in ipairs({setup,commands})do for _,row in ipairs(rows)do
  if not row.cancelled and row.type~='ISReadABook'and (not row.ack or row.ack.state~='completed')then return false end
 end end
 return true
end
local function names()
 local result={}
 for _,a in ipairs(queue().queue)do result[#result+1]=assert(tracks[a],'unexpected queue action '..tostring(a.Type)).name end
 return result
end
local function same(a,b)
 if #a~=#b then return false end;for i,v in ipairs(a)do if v~=b[i]then return false end end;return true
end
local function createPanels()
 local function panel(class)
  local p=class:new(-1000,-1000,300,100);p:initialise();p:instantiate()
  assert(p:readFromObject(getPlayer(),state.tv,state.data,'IsoObject'),'native TV panel rejected fixture')
  return p
 end
 panels={tv=panel(RWMMergedTV),volume=panel(RWMVolume)}
end
local function pending()
 assert(queue().current==state.frontAction and state.frontAction:isStarted(),'reader lost before pending controls')
 local before=F.snapshot(state);local actions={}
 actions.volume=nativeUI('volume',commands,function()panels.tv.volumeBar.onVolumeChange(panels.tv,.25*panels.tv.volumeBar:getVolumeSteps())end,'ISRadioAction','SetVolume')
 actions.redundant=nativeUI('redundant',commands,function()panels.tv.volumeBar.onVolumeChange(panels.tv,.25*panels.tv.volumeBar:getVolumeSteps())end,'ISRadioAction','SetVolume')
 actions.mute=nativeUI('mute',commands,function()RWMVolume.onSpeakerButton(panels.tv,true)end,'ISRadioAction','MuteVolume')
 actions.unmute=nativeUI('unmute',commands,function()RWMVolume.onSpeakerButton(panels.tv,false)end,'ISRadioAction','UnMuteVolume')
 actions.channel=nativeUI('channel',commands,function()panels.tv:doTuneInButton(panels.tv.channelUp)end,'ISRadioAction','SetChannel')
 actions.eject=nativeUI('eject',commands,function()panels.tv:removeMedia()end,'ISDeviceMediaAction')
 assert(actions.eject.isRemove==true and actions.eject.secondaryItem==nil,'native eject constructor differs')
 assert(actions.channel.secondaryItem==95000 and actions.unmute.secondaryItem==.25,'native setting value differs')
 state.tailAction=book('tail',state.tail)
 initialQueue=names()
 assert(same(initialQueue,{'front','volume','redundant','mute','unmute','channel','eject','tail'}),'native TV producer sequence differs')
 edit={reordered=false,cancelled={},untouched=false,atomic=true}
 if not native then
  assert(T.ActionQueue.move(queue(),actions.eject,actions.channel),'independent eject/channel reorder denied')
  assert(T.ActionQueue.cancelOperation(queue(),actions.redundant),'redundant pending setter cancellation denied')
  tracks[actions.redundant].cancelled=true;edit.cancelled={'redundant'};edit.reordered=true
 end
 editedQueue=names()
 local expected=native and initialQueue or {'front','volume','mute','unmute','eject','channel','tail'}
 assert(same(editedQueue,expected),'edited TV sequence differs')
 local after=F.snapshot(state)
 edit.untouched=before.originalCount==after.originalCount
 for key,value in pairs(before.device)do if after.device[key]~=value then edit.untouched=false end end
 assert(edit.untouched,'pending TV producer/edit mutated device state')
 phase='running'
end
local function finish()
 assert(empty()and allReceipts(),'TV final queue/ACKs unsettled')
 local client=assert(F.verify(state),'client TV output/settings/books not settled')
 assert(receipt and receipt.case==case(),'server TV receipt missing')
 local expected=native and initialQueue or {'front','volume','mute','unmute','eject','channel','tail'}
 assert(same(order,expected),'actual native TV start order differs')
 for _,rows in ipairs({setup,commands})do for _,row in ipairs(rows)do
  assert(row.cancelled and not row.started and not row.progress or not row.cancelled and row.started and row.progress,
   'native action progress/cancellation missing '..row.name)
 end end
 emit({event='case',id=case(),status='passed',ids=ids,input=state.input,baseline=state.baseline,
  authorityBaseline=baselineReceipt,client=client,server=receipt,setup=setup,commands=commands,
  initialQueue=initialQueue,editedQueue=editedQueue,order=order,edit=edit,queueIdle=true,settleMilliseconds=now()-quiet})
 index=index+1
 if not case()then
  emit({event='complete',cases=config.cases,performed=index-1,failed=0,skipped=0});raw('COMPLETE',{cases=config.cases});done=true;return
 end
 state,localAuthority,ids,baselineReceipt,receipt,panels,tracks,commands,setup,order=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
 initialQueue,editedQueue,edit,quiet=nil,nil,nil,nil;phase='prepare';since=now();diagnosed=false
end
Events.OnGameStart.Add(function()started=true;since=now()end)
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,error=pcall(function()
  local player=getPlayer();if not isIngameState()or not player or not player:getSquare()then return end
  if not ready then
   if isClient()~=(config.kind=='mp')or isClient()and (player:getOnlineID()<0 or player:getUsername()~='client1')then return end
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(not native)
   assert(T.Settings.actionQueue()==not native and not player:isTimedActionInstant())
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false)
   player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
   ready=true;since=now();emit({event='setup',cases=config.cases,queueEnabled=not native,nativeDurations=true})
  end
  if not diagnosed and now()-since>30000 then
   diagnosed=true
   local ok,value=pcall(function()return state and F.snapshot(state)end)
   raw('WAIT',{case=case(),phase=phase,current=queue().current and queue().current.Type or '',
    queueCount=#queue().queue,actual=ok and value or tostring(value),commands=commands,setup=setup})
  end
  assert(now()-since<150000,'TV controls timeout '..tostring(case())..' phase='..phase)
  if tracks then observe()end
  if phase=='prepare'then
   assert(empty(),'TV case initial queue not empty');phase='prepared';request('Prepare')
  elseif phase=='prepared'and ids then
   state=F.resolve(player,ids);if not state or player:tooDarkToRead()then return end
   assert(empty(),'scene setup queued unexpected work')
   tracks,commands,setup,order={},{},{},{};state.input=F.snapshot(state)
   assert(state.input.originalCount==1,'initial exact VHS not present')
   createPanels()
   nativeUI('insert',setup,function()RWMMedia.addMediaAux(panels.tv,state.tape)end,'ISDeviceMediaAction')
   phase='insert'
  elseif phase=='insert'and empty()then
   if not state.data:hasMedia()or player:getInventory():getItemById(ids.tape.id)then return end
   if case()=='eject-playing'then
    nativeUI('play',setup,function()panels.tv:togglePlayMedia()end,'ISRadioAction','TogglePlayMedia');phase='play'
   else phase='baseline'end
  elseif phase=='play'and empty()and state.data:isPlayingMedia()then phase='baseline'
  elseif phase=='baseline'then
   if not allReceipts()then return end
   local approach=F.approach(state)
   if not approach.reachable or not F.baseline(state)then return end
   raw('APPROACH',{case=case(),actual=approach})
   phase='authorityBaseline';request('Baseline')
  elseif phase=='authorityBaseline'and baselineReceipt then
   assert(empty(),'baseline native queue not empty');state.frontAction=book('front',state.front);phase='front'
  elseif phase=='front'then
   if tracks[state.frontAction].progress then pending()end
  elseif phase=='running'and empty()then
   local final=F.verify(state)
   if not final or not allReceipts()then quiet=nil;return end
   quiet=quiet or now()
   if now()-quiet>=1000 then phase='verified';request('Verify')end
  elseif phase=='verified'and receipt then finish()end
 end)
 if not ok then fail(error)end
end)
