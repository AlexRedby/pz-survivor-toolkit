require 'PZSurvivorToolkit/ActionQueuePanel'
require 'ISUI/Animal/ISAnimalContextMenu'
require 'TimedActions/Animals/ISPetAnimal'
require 'TimedActions/ISReadABook'
local F=require 'QueueAnimalTerminal';local JSON=require 'QueueHealthEvents';local cfg=require 'QueueTestSelection'
local Proof=require 'PZSurvivorToolkit/SourceProof';local T=PZSurvivorToolkit;local native=cfg.mode=='native'
local entered,ready,done=false,false,false
local index,phase,since=1,'prepare',0
local state,previous,ids,baseline,authorityBaseline,receipt,body,tail,recovery,tracks,classes,ack,quiet,terminal,intervention
local producer=AnimalContextMenu.onPetAnimal
local nativeAdjust=ISBaseTimedAction.adjustMaxTime
local clientPlacement,clientPlacementSince,clientPlacementReady,clientPlacementPollAt
local function now()return getTimestampMs()end
local function case()return cfg.cases[index]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function raw(name,row)print('[ANIMAL_TERMINAL] '..name..' '..JSON.encode(row))end
local function emit(row)row.suite,row.kind,row.mode,row.actor='animal-terminal',cfg.kind,cfg.mode,'client1';JSON.emit(row)end
local function snap()return F.snapshot(state)end
local function register(action,name)
 local row={name=name,type=action.Type,duration=action.maxTime,started=false,starts=0,nativeRef=false,finishes={},terminal=false,ack=false}
 tracks[action]=row
 local class=getmetatable(action);if not classes[class]then
  local methods={};for _,key in ipairs({'new','isValid','waitToStart','start','update','stop','perform','complete','forceStop','animEvent','getDuration','create','adjustMaxTime'})do methods[key]=class[key]or false end
  classes[class]=methods
 end
 return row
end
local function intact()
 assert(AnimalContextMenu.onPetAnimal==producer and Proof.closure(producer,'ISAnimalContextMenu.lua'),'native animal producer changed')
 for class,methods in pairs(classes)do for key,fn in pairs(methods)do assert((class[key]or false)==fn,'native animal/book callback changed '..key)end end
 assert(getmetatable(body)==ISPetAnimal,'native pet class changed')
 assert(body.animal==state.animal,'native pet animal identity changed')
 assert(tracks[body].duration==400,'native pet constructor duration changed')
 if not body.action then assert(body.maxTime==400,'native pet waiting duration changed before create')end
end
local function started(action)
 local row=tracks and tracks[action];if not row then return end
 assert(action.adjustMaxTime==nativeAdjust and Proof.closure(nativeAdjust,'ISBaseTimedAction.lua'),'native adjustMaxTime source changed')
 assert(action.maxTime==row.duration,'native constructor duration changed before begin '..row.name)
 row.beginAt=now();row.before=snap()
 row.timing={constructor=row.duration,beforeCreate=action.maxTime,expectedAdjusted=nativeAdjust(action,action.maxTime),sampleAt=row.beginAt,
  source='ISBaseTimedAction.adjustMaxTime',allocated=false,samples={}}
 assert(type(row.timing.expectedAdjusted)=='number'and row.timing.expectedAdjusted>1,'invalid native adjusted duration '..row.name)
 raw('BEGIN',{case=case(),name=row.name,at=row.beginAt,snapshot=row.before,timing={constructor=row.timing.constructor,
  beforeCreate=row.timing.beforeCreate,expectedAdjusted=row.timing.expectedAdjusted,sampleAt=row.timing.sampleAt,source=row.timing.source}})
end
local function sampleNative(action,row,phase)
 if not action.action then return end
 assert(row.timing,'native allocation has no before-create duration witness '..row.name)
 local timing=row.timing
 if not timing.allocated then
  assert(action.maxTime==timing.expectedAdjusted,'native create duration differs from synchronous source adjustment '..row.name)
  timing.allocated=action.maxTime;row.allocatedAt=now();row.nativeRef=tostring(action.action)
 end
 local sample={phase=phase,at=now(),luaMaxTime=action.maxTime,nativeCurrentTime=action.action:getCurrentTime(),jobDelta=action:getJobDelta()}
 timing.samples[#timing.samples+1]=sample;raw('DURATION',{case=case(),name=row.name,sample=sample})
end
local function finish(action,step,ok)
 local row=tracks and tracks[action];if not row then return end
 sampleNative(action,row,step)
 local value={phase=step,succeeded=ok==true,at=now(),snapshot=snap()}
 row.finishes[#row.finishes+1]=value
 raw('CALLBACK',{case=case(),name=row.name,callback=value})
end
local function observe()
 intact()
 for action,row in pairs(tracks)do
  if action.action and not row.allocatedAt then sampleNative(action,row,'allocated')end
  if action.action and action:isStarted()and not row.started then
   row.started=true;row.starts=row.starts+1;row.startedAt=now();row.nativeRef=tostring(action.action);sampleNative(action,row,'started')
  end
  if isClient()and action==queue().current and not ack[action]then
   local record=T.ActionQueueAcknowledgements.capture(action)
   if record then ack[action]=record;row.ack={transaction=record.transaction,kind=record.kind,token=record.token}end
  end
  if ack[action]then
   local status=T.ActionQueueAcknowledgements.observe(action,ack[action])
   if status and status~='started'then row.terminal=status;row.terminalProof='sealed-native-receipt'end
   if row.terminal==false and row.wireTerminal then row.terminal=row.wireTerminal;row.terminalProof='correlated-wire-after-reset'end
  end
 end
end
local function request(command)
 if isClient()then
  local args={case=case()}
  if command=='Prepare'then
   if not clientPlacement then
    local player=getPlayer();player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false)
    local square=require('QueueEnergyPlacement')(player)
    clientPlacement=F.placementTarget({x=square:getX(),y=square:getY(),z=square:getZ()})
    clientPlacementSince=now();phase='mp-placement';return
   end
   if not clientPlacementReady then
    assert(now()-clientPlacementSince<30000,'local-client fixture placement did not settle')
    if not F.at(getPlayer(),clientPlacement)then
     if not clientPlacementPollAt or now()-clientPlacementPollAt>=5000 then
      clientPlacementPollAt=now();local player=getPlayer();local square=player:getSquare()
      raw('CLIENT_PLACEMENT_WAIT',{target=clientPlacement,actual={x=player:getX(),y=player:getY(),z=player:getZ()},
       square=square and{x=square:getX(),y=square:getY(),z=square:getZ()}or false})
     end
     phase='mp-placement';return
    end
    clientPlacementReady=true;raw('CLIENT_PLACEMENT',{target=clientPlacement,arrived=true,teleports=1})
   end
   args.placement=clientPlacement;phase='prepared'
  end
  sendClientCommand('AnimalTerminalTest',command,args);return
 end
 if command=='Prepare'then
  state=F.prepare(getPlayer(),case(),previous)
  if not state then phase='placing';return end
  previous=nil;ids=state.ids;phase='prepared';raw('PREPARED',ids)
 elseif command=='Baseline'then authorityBaseline=snap();raw('BASELINE',authorityBaseline)
 elseif command=='Verify'then receipt={case=case(),baseline=authorityBaseline,final=snap()};raw('VERIFIED',receipt)end
end
Events.OnServerCommand.Add(function(module,name,args)
 if done then return end
 if module=='PZSurvivorToolkitActions'and name=='State'and tracks then
  for _,row in pairs(tracks)do
   local receipt=row.ack
   if receipt and args.protocol==1 and args.player==ids.actor and args.kind==receipt.kind and args.transaction==receipt.transaction and args.token==receipt.token and args.state~='started'then
    assert(not row.wireTerminal,'duplicate native terminal receipt');row.wireTerminal=args.state
    raw('ACK',{case=case(),name=row.name,transaction=args.transaction,kind=args.kind,token=args.token,state=args.state,player=args.player})
   end
  end
  return
 end
 if module~='AnimalTerminalTest'then return end
 if name=='Prepared'then ids=args
 elseif name=='Baselined'then authorityBaseline=args
 elseif name=='Verified'then receipt=args
 elseif name=='Failed'then error(args.error)end
end)
local function enqueue()
 assert(empty()and not state.player:isTimedActionInstant()and not getDebug(),'ordinary native empty queue/durations required')
 baseline=snap();tracks,classes,ack={},{},{}
 assert(baseline.book.pages==ids.book.initial and F.clean(baseline),'client animal/book baseline differs')
 assert(state.animal:canBePet(),'animal has no native pet menu entry')
 local valid=case()~='pet-invalid'
 if valid then
  assert(Proof.closure(producer,'ISAnimalContextMenu.lua'),'native pet producer unavailable')
  T.ActionQueueOperations.run(function()producer(state.animal,state.player)end)
  for _,action in ipairs(queue().queue)do if action.Type=='ISPetAnimal'then assert(not body,'duplicate pet body');body=action end end
 else
  body=ISPetAnimal:new(state.player,state.animal)
  assert(not body:isValid(),'far-animal native precondition unexpectedly valid')
  -- Keep one native action ahead of the invalid body so both body and independent
  -- tail exist before the ordinary queue attempts the failing precondition.
  local gate=ISReadABook:new(state.player,state.gate);register(gate,'gate');ISTimedActionQueue.add(gate)
  ISTimedActionQueue.add(body)
 end
 assert(body and body.maxTime==400,'native pet body missing')
 local row=register(body,'body');row.initialValid=body:isValid();row.producer=valid and'AnimalContextMenu.onPetAnimal'or'native ISPetAnimal constructor'
 tail=ISReadABook:new(state.player,state.book);ISTimedActionQueue.add(tail);register(tail,'tail')
 assert(queue():indexOf(tail)>queue():indexOf(body),'independent reader not queued behind native pet')
 raw('ENQUEUED',{case=case(),body=row,baseline=baseline,tailDuration=tail.maxTime})
 phase='running'
end
local function afterTerminal()
 local success=case()=='pet-success';local preserved=success and not native
 local row=tracks[body]
 if isClient()and row.started and row.terminal==false then return end
 local value=snap()
 assert(F.clean(value),'native animal terminal cleanup incomplete')
 assert(tracks[tail].started==preserved,'independent tail retained/aborted behavior differs')
 if not isClient()then assert(F.effect(state,value),'native SP paid pet effect differs')end
 terminal={case=case(),at=now(),snapshot=value,preserved=preserved,originalTailStarted=tracks[tail].started,intervention=intervention or false}
 raw('TERMINAL',terminal)
 if preserved then phase='settle';return end
 -- Reusing the normal queue happens only after native terminal idle. The aborted
 -- tail is never manually performed; this is a fresh actual book action.
 recovery=ISReadABook:new(state.player,state.book);register(recovery,'recovery');ISTimedActionQueue.add(recovery);phase='settle'
end
local function completeCase()
 local success=case()=='pet-success';local row=tracks[body]
 assert(receipt and F.effect(state,receipt.final)and F.clean(receipt.final),'authority animal result differs')
 assert(row.started==(case()~='pet-invalid'),'native body allocation differs')
 local commands={body=row,tail=tracks[tail],recovery=recovery and tracks[recovery]or false}
 if case()=='pet-invalid'then commands.gate=nil;for _,record in pairs(tracks)do if record.name=='gate'then commands.gate=record end end end
 local result={event='case',id=case(),status='passed',ids=ids,baseline=baseline,authorityBaseline=authorityBaseline,commands=commands,
  terminal=terminal,receipt=receipt,clientFinal=snap(),nativeMethodsUnchanged=true,settleMilliseconds=now()-quiet,queueIdle=empty(),
  limits='Paid effect uses one native authority Husbandry XP event plus exact float32 XP delta and native timer range; acceptance is descriptive because native spotted/held behavior drifts it. Java invocation counts are unavailable; terminal wire after native queue reset is correlated to a sealed start without granting rights; invalid covers start precondition only. Lure and mid-animation prerequisite loss are excluded.'}
 emit(result)
 previous=state;index=index+1;state,ids,baseline,authorityBaseline,receipt,body,tail,recovery,tracks,classes,ack,quiet,terminal,intervention=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
 phase='prepare';since=now()
 if not case()then emit({event='complete',cases=cfg.cases,performed=#cfg.cases,failed=0,skipped=0});raw('COMPLETE',{cases=cfg.cases});done=true end
end
Events.OnGameStart.Add(function()entered=true;since=now()end)
Events.OnTick.Add(function()
 if not entered or done then return end
 local ok,problem=pcall(function()
  local player=getPlayer();if not isIngameState()or not player or not player:getSquare()then return end
  if not ready then
   if isClient()~=(cfg.kind=='mp')or isClient()and player:getUsername()~='client1'then return end
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(not native)
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);player:setAutoDrink(false)
   assert(T.ActionQueueLifecycle.registerObserver('fixture.animal-terminal',{started=started,begin=function(action,step)return tracks and tracks[action]~=nil end,finish=finish}),'native animal observer unavailable')
   ready=true;emit({event='setup',cases=cfg.cases,queueEnabled=not native,nativeDurations=true})
  end
  assert(now()-since<180000,'animal terminal timeout '..tostring(case())..' phase='..phase)
  if tracks then observe()end
  if phase=='prepare'then if not empty()then return end;phase='prepared';request('Prepare')
  elseif phase=='placing'or phase=='mp-placement'then request('Prepare')
  elseif phase=='prepared'and ids then
   if not state then state=F.resolve(player,ids);if not state then return end end
   phase='baseline';request('Baseline')
  elseif phase=='baseline'and authorityBaseline then if not player:tooDarkToRead()then enqueue()end
  elseif phase=='running'then
   local row=tracks[body]
   if case()=='pet-cancel'and row.started and(not isClient()or ack[body])and not intervention then
    assert(player:getVariableBoolean('petanimal'),'cancel did not enter native pet animation')
    intervention={kind='ISTimedActionQueue.clear',at=now(),snapshot=snap()};raw('CANCEL',intervention);ISTimedActionQueue.clear(player)
   end
   if empty()then afterTerminal()end
  elseif phase=='settle'then
   if not empty()then quiet=nil;return end
   local value=snap();assert(value.book.pages==ids.book.total and value.book.itemPages==ids.book.total,'independent native book did not complete')
   quiet=quiet or now();if now()-quiet>=2000 then phase='verify';request('Verify')end
  elseif phase=='verify'and receipt then completeCase()end
 end)
 if not ok then emit({event='case',id=case(),status='failed',phase=phase,reason=tostring(problem),ids=ids or false});print('[QUEUE_TEST] FAIL animal-terminal '..tostring(problem));done=true end
end)
