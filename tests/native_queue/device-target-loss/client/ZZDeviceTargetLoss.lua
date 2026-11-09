require 'PZSurvivorToolkit/ActionQueuePanel'
require 'RadioCom/ISRadioAction'
require 'RadioCom/ISUIRadio/ISItemDropBox'
require 'RadioCom/ISUIRadio/ISSpeakerButton'
require 'RadioCom/ISUIRadio/ISVolumeBar'
require 'RadioCom/RadioWindowModules/RWMVolume'
require 'TimedActions/ISReadABook'
local F=require 'QueueDeviceTargetLoss'
local P=require 'QueueEnergyPlacement'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local stages=require('QueueCaseStages').new('device-target-loss','client1')
local T=PZSurvivorToolkit
local started,ready,done=false,false,false
local index,phase,since=1,'prepare',0
local ids,state,authority,placement,placementState,clientPlacement,mutation,observed,receipt,cleanup,quiet
local commands,tracked,hold,setter,tail,initial,before,observedAt,drainedAt,outcome,acks,callbacks
local functionBindings
local walkBank
local pendingCommand
local function now()return getTimestampMs()end
local function case()return config.cases[index]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function idle()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function raw(name,value)print('[DEVICE_TARGET_LOSS] '..name..' '..JSON.encode(value))end
local function emit(row)
 row.suite,row.kind,row.mode,row.actor='device-target-loss',config.kind,config.mode,'client1';JSON.emit(row)
end
local function fail(error)
 if done then return end
 stages:fail(error)
 emit({event='case',id=case(),status='failed',phase=phase,reason=tostring(error),commands=commands,
  ids=ids,mutation=mutation,observed=observed,server=receipt})
 print('[QUEUE_TEST] FAIL device-target-loss '..tostring(error));done=true
end
local function request(command)
 local args={case=case()}
 if command=='Prepare'then
  assert(clientPlacement and P.at(getPlayer(),placement),'device loss Prepare requires fresh placement')
  args.placement=placement;args.clientPlacement=clientPlacement
 end
 if isClient()then pendingCommand=command;sendClientCommand('DeviceTargetLossTest',command,args);return end
 if command=='Prepare'then authority=F.prepare(getPlayer(),case(),config.mode,placement,clientPlacement);ids=authority.ids;raw('PREPARED',ids)
 elseif command=='Mutate'then mutation=F.mutate(authority);raw('MUTATED',mutation)
 elseif command=='Verify'then receipt=F.snapshot(authority);raw('VERIFIED',receipt)
 elseif command=='Cleanup'then cleanup=F.cleanup(authority);raw('CLEANED',cleanup)
 else error('unknown device loss request')end
end
Events.OnServerCommand.Add(function(module,command,args)
 if done or not args then return end
 if module=='DeviceTargetLossTest'then
  if args.case~=case()then return end
  if command=='Failed'then
   if args.command==pendingCommand and pendingCommand then fail(args.error)end
   return
  end
  local requests={Prepared='Prepare',Mutated='Mutate',Verified='Verify',Cleaned='Cleanup'}
  if not pendingCommand or requests[command]~=pendingCommand then return end
  pendingCommand=nil
  if command=='Prepared'then ids=args elseif command=='Mutated'then mutation=args
  elseif command=='Verified'then receipt=args elseif command=='Cleaned'then cleanup=args end
 elseif module=='PZSurvivorToolkitActions'and command=='State'and tracked then
  -- Capture only ACKs linked to the exact original setter transaction or its
  -- already observed token. Unrelated late packets remain outside this receipt.
  if not setter then return end
  local row=tracked[setter]
  if row.ackToken==args.token or args.state=='started'and queue().current==setter
   and setter.toolkitNativeTransaction==args.transaction and setter.toolkitNativeKind==args.kind
   and getPlayer():getOnlineID()==args.player then
   assert(args.protocol==1 and args.kind=='ISRadioAction'and type(args.token)=='string','invalid device loss ACK')
   if args.state=='started'then assert(not row.ackToken,'duplicate device loss started ACK');row.ackToken=args.token
   else assert(row.ackToken==args.token,'device loss terminal ACK before start')end
   acks[#acks+1]={token=args.token,transaction=args.transaction,kind=args.kind,state=args.state,at=now()}
  end
 end
end)
local function functionSource(callback)
 if type(callback)~='function'then return type(callback)end
 if getFilenameOfClosure then
  local ok,source=pcall(getFilenameOfClosure,callback);if ok then return tostring(source)end
 end
 return 'unknown'
end
local function captureFunctions(action)
 assert(not functionBindings[action],'native action function baseline captured twice')
 local bindings={}
 for key,value in pairs(action)do if type(value)=='function'then bindings[key]=value end end
 functionBindings[action]=bindings
end
local function unchangedFunctions(action,name)
 local bindings=assert(functionBindings[action],'missing native function baseline '..name)
 local function mismatch(key,actual,expected)
  return 'native instance callback changed action='..name..' key='..tostring(key)
   ..' actualSource='..functionSource(actual)..' expectedSource='..functionSource(expected)
 end
 for key,value in pairs(action)do
  if type(value)=='function'then assert(bindings[key]==value,mismatch(key,value,bindings[key]))end
 end
 for key,value in pairs(bindings)do assert(rawget(action,key)==value,mismatch(key,rawget(action,key),value))end
end
local function track(action,name)
 local row={name=name,type=action.Type,duration=action.maxTime,started=false,progress=false,
  starts=0,performed=false,stopped=false,allocated=false}
 if name=='setter'then
  row.mode=action.mode;row.value=action.secondaryItem;row.targetKey=ids.key
  row.originalDevice=action.device==state.object;row.originalData=action.deviceData==state.data
 end
 commands[#commands+1]=row;tracked[action]=row
 return row
end
local observerError
-- Diagnostic observers never opt native controls into lifecycle phase tracking.
local function guarded(callback)
 return function(...)
  local ok,problem=pcall(callback,...)
  if not ok then observerError=tostring(problem)end
 end
end
local function watch()
 assert(T.ActionQueueLifecycle.registerObserver('fixture.device-target-loss',{
  started=guarded(function(action)
   local row=tracked and tracked[action];if not row then return end
   row.starts=row.starts+1;assert(row.starts==1,'device loss action replayed')
   row.started=true;row.startedAt=now()
   -- Base.begin/create samples this same modifier before any world tick.
   -- Reading it on the next fixture tick can observe changed body temperature.
   row.nativeDurationExpected=action:adjustMaxTime(row.duration)
   if row.name=='setter'then assert(action.device==state.object and action.deviceData==state.data,'original setter binding changed')end
   if walkBank then walkBank:started(action)end
  end),
  begin=guarded(function(action,step)
   if walkBank then walkBank:begin(action,step)end
   local row=tracked and tracked[action]
   if row then
    if step=='perform'then row.performAt=now()end
   end
  end),
  finish=guarded(function(action,step,succeeded)
   local row=tracked and tracked[action];if not row then return end
   if step=='perform'then row.performed=succeeded==true;row.finishedAt=now()
   elseif step=='stop'then row.stopped=succeeded==true;row.stoppedAt=now()end
  end),
 }),'device loss lifecycle observer unavailable')
end
local function checkCallbacks()
 for _,entry in ipairs(callbacks)do assert(entry.class[entry.name]==entry.callback,'native device loss callback replaced '..entry.name)end
 for action,row in pairs(tracked)do
  unchangedFunctions(action,row.name)
  if action.action and not row.allocated then
   row.allocated=true;row.effectiveDuration=action.maxTime
   assert(row.started and type(row.nativeDurationExpected)=='number','native duration admission sample missing')
   assert(math.abs(row.effectiveDuration-row.nativeDurationExpected)<.001,'native device loss action retimed')
  elseif row.allocated then assert(action.maxTime==row.effectiveDuration,'device loss active duration changed')end
  if queue().current==action and action:isStarted()then
   if row.name=='hold'or row.name=='tail'then
    if action.item:getAlreadyReadPages()>ids[row.name].initial then row.progress=true;row.progressAt=row.progressAt or now()end
   elseif row.name~='setter:walk'and action:getJobDelta()>0 then row.progress=true;row.progressAt=row.progressAt or now()end
  end
 end
 assert(not observerError,observerError)
 if walkBank then walkBank:observe()end
end
local function begin()
 assert(idle(),'device loss case begins with native work')
 commands,tracked,acks,callbacks,functionBindings={},{},{},{},{}
 walkBank=F.walkCase(case())and require('QueueDeviceTargetLossWalk').new(state,tracked,captureFunctions,config.mode)or nil
 for _,class in ipairs({ISReadABook,ISRadioAction,ISQueueActionsAction})do
  for _,name in ipairs({'new','begin','start','update','stop','perform','complete','isValid','isValidStart','waitToStart','adjustMaxTime'})do
   callbacks[#callbacks+1]={class=class,name=name,callback=class[name]}
  end
 end
 before=F.snapshot(state)
 assert(before.heldDataSame and before.heldDataParentSame and before.oldPresent and not before.destinationPresent)
 stages:gameplay()
 hold=ISReadABook:new(getPlayer(),state.hold);track(hold,'hold');ISTimedActionQueue.add(hold);captureFunctions(hold)
 phase='hold'
end
local function enqueue()
 assert(queue().current==hold and hold:isStarted()and tracked[hold].progress,'device loss hold has no real reading progress')
 local panel=RWMVolume:new(-1000,-1000,300,100);panel:initialise();panel:instantiate()
 assert(panel:readFromObject(getPlayer(),state.object,state.data,'IsoObject'),'native RWM rejected loss target')
 local emitted={};local original=ISTimedActionQueue.add
 ISTimedActionQueue.add=function(action)emitted[#emitted+1]=action;return original(action)end
 local ok,error=pcall(function()
  local function invoke()panel:onVolumeChange(.75*panel.volumeBar:getVolumeSteps())end
  if config.mode=='native'then invoke()else T.ActionQueueOperations.run(invoke)end
 end)
 ISTimedActionQueue.add=original;assert(ok,error)
 assert(#emitted==(config.mode=='native'and not walkBank and 1 or 2),'native loss producer shape differs')
 setter=emitted[#emitted]
 assert(getmetatable(setter)==ISRadioAction and setter.mode=='SetVolume'and setter.device==state.object
  and setter.deviceData==state.data and setter.secondaryItem==.75 and setter.maxTime==30,'native loss producer binding differs')
 if config.mode=='toolkit'then
  local preparation=emitted[1];local token=setter.toolkitQueueOperation
  assert(T.ActionQueueApproach.isAction(preparation)and type(token)=='table'and preparation.toolkitQueueOperation==token)
  local intent=preparation.toolkitQueueCommand.snapshot
  assert(intent.binding.owner==luautils and intent.binding.name=='walkAdj'and intent.args.n==3
   and intent.args[1]==getPlayer()and intent.args[2]==state.object:getSquare()and intent.args[3]==true)
  track(preparation,'setter:approach')
  captureFunctions(preparation)
 end
 local setterRow=track(setter,'setter')
 captureFunctions(setter)
 if config.mode=='toolkit'and config.options and config.options.device_target_loss_expect=='safe'then
  assert(T.ActionQueueDeviceTargets and T.ActionQueueDeviceTargets.install(),'device target admission capability unavailable')
  assert(T.ActionQueueSettlement.deviceStep(setter),'original pending device admission binding missing')
  assert(T.ActionQueueSettlement.deviceStep(emitted[1]),'source-owned device preparation binding missing')
 end
 if walkBank then walkBank:produced(emitted)end
 tail=ISReadABook:new(getPlayer(),state.tail);track(tail,'tail');ISTimedActionQueue.add(tail);captureFunctions(tail)
 if walkBank then walkBank:tail(tail)end
 initial={}
 for _,action in ipairs(queue().queue)do
  initial[#initial+1]=assert(tracked[action],'foreign initial device loss action').name
  if action~=hold then assert(not action.action and not action:isStarted(),'loss command started before mutation')end
 end
 assert(math.abs(F.snapshot(state).held.volume-.5)<.0001,'pending producer changed target')
 if walkBank then phase='walking'
 else setterRow.pendingAtMutate=true;setterRow.mutationRequestedAt=now();phase='mutation';request('Mutate')end
end
local function finish()
 assert(idle()and cleanup and F.cleaned(state),'device loss cleanup did not replicate')
 stages:complete()
 local setterRow=tracked[setter]
 local safe=config.mode=='toolkit'and outcome.queueIdle and outcome.recovery=='none'
  and not setterRow.started and setterRow.starts==0 and not setterRow.allocated and not setterRow.performed
  and setterRow.performAt==nil and #acks==0
  and outcome.client.held.volume==.5 and receipt.held.volume==.5
  and (not outcome.client.live or outcome.client.live.volume==.5)and(not receipt.live or receipt.live.volume==.5)
  and outcome.client.books.tail.pages==ids.tail.pages and outcome.client.books.tail.characterPages==ids.tail.pages
  and tracked[tail].started and tracked[tail].progress and tracked[tail].performed
  and(not walkBank or walkBank:safe())
 local expected=config.options and config.options.device_target_loss_expect or'capture'
 assert(expected=='capture'or expected=='safe','unknown device loss expectation')
 if expected=='safe'then assert(config.mode=='toolkit'and safe,'safe target loss/tail outcome not observed')end
 emit({event='case',id=case(),status=expected=='capture'and'captured'or'passed',expectation=expected,
  safeOutcome=safe,ids=ids,clientPlacement=clientPlacement,before=before,initialQueue=initial,
  mutation=mutation,observed=observed,observedAt=observedAt,commands=commands,acks=acks,
  client=outcome.client,server=receipt,queueIdle=outcome.queueIdle,queueTimedOut=outcome.queueTimedOut,
  recovery=outcome.recovery,settleMilliseconds=outcome.settleMilliseconds,cleanup=cleanup,
  cleanupObserved=true,cleanupSettleMilliseconds=now()-quiet,nativeCallbacksUnchanged=true,
  paidApproach=walkBank and walkBank.proof or nil,
  originalSetterBinding=setter.device==state.object and setter.deviceData==state.data})
 index=index+1
 if not case()then
  emit({event='complete',cases=config.cases,expected=#config.cases,performed=index-1,failed=0,skipped=0})
  print('[DEVICE_TARGET_LOSS] COMPLETE');done=true;return
 end
 ids,state,authority,placement,placementState,clientPlacement,mutation,observed,receipt,cleanup,quiet=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
 commands,tracked,hold,setter,tail,initial,before,observedAt,drainedAt,outcome,acks=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
 phase='prepare';since=now()
 walkBank,pendingCommand=nil,nil
 stages:setup(case())
end
require('QueuePreflight').onGameStart(Events,function()stages:setup(case());started=true;since=now()end)
require('QueuePreflight').onTick(Events,function()
 if not started or done then return end
 local ok,error=pcall(function()
  local player=getPlayer()
  if not ready then
   if not isIngameState()or not player or not player:getSquare()then return end
   if isClient()~=(config.kind=='mp')then return end
   if isClient()and(player:getOnlineID()<0 or player:getUsername()~='client1')then return end
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(config.mode=='toolkit')
   assert(T.Settings.actionQueue()==(config.mode=='toolkit')and not player:isTimedActionInstant())
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false)
   player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
   watch();ready=true;since=now()
   emit({event='setup',cases=config.cases,queueEnabled=config.mode=='toolkit',nativeDurations=true,
    producer='native RWM callback',expectation=config.options and config.options.device_target_loss_expect or'capture'})
  end
  assert(now()-since<180000,'device loss case timed out '..phase)
  if tracked then checkCallbacks()end
  if phase=='prepare'then
   assert(idle(),'device loss placement requires idle queue')
   if not placementState then placement=F.choosePlacement(player,case());placementState=P.begin(player,placement)end
   clientPlacement=P.poll(placementState);if not clientPlacement then return end
   raw('CLIENT_PLACEMENT',{case=case(),proof=clientPlacement});phase='prepared';request('Prepare')
  elseif phase=='prepared'and ids then state=F.resolve(player,ids);if state then begin()end
  elseif phase=='hold'then if tracked[hold].progress then enqueue()end
  elseif phase=='walking'then
   if walkBank:ready()then
    walkBank:requestMutation();local row=tracked[setter]
    row.pendingAtMutate=true;row.mutationRequestedAt=now();phase='mutation';request('Mutate')
   end
  elseif phase=='mutation'then
   if walkBank then
    assert(not setter.action and not setter.started,'body admitted before replicated paid-walk target loss')
   else assert(queue().current==hold and hold:isStarted(),'native hold ended before replicated mutation observation')end
   if mutation then observed=F.observed(state)
    if observed then
     if walkBank then walkBank:observed()end
     observedAt=now();phase='running';drainedAt=now()
    end
   end
  elseif phase=='running'then
   if idle()then
    quiet=quiet or now()
    if now()-quiet>=1500 then
     outcome={client=F.snapshot(state),queueIdle=true,queueTimedOut=false,recovery='none',settleMilliseconds=now()-quiet}
     phase='verify';request('Verify')
    end
   else
    quiet=nil
    if now()-drainedAt>=90000 then
     outcome={client=F.snapshot(state),queueIdle=false,queueTimedOut=true,recovery='native-stop-all',settleMilliseconds=0}
     player:StopAllActionQueue();phase='recovery';quiet=nil
    end
   end
  elseif phase=='recovery'then
   if idle()then quiet=quiet or now();if now()-quiet>=1500 then phase='verify';request('Verify')end else quiet=nil end
  elseif phase=='verify'and receipt then
   assert(idle(),'device loss cleanup requires drained actions')
   stages:cleanup();phase='cleanup';quiet=nil;request('Cleanup')
  elseif phase=='cleanup'and cleanup then
   if F.cleaned(state)and idle()then quiet=quiet or now();if now()-quiet>=1500 then finish()end else quiet=nil end
  end
 end)
 if not ok then fail(error)end
end)
