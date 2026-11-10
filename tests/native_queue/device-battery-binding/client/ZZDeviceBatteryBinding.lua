require 'PZSurvivorToolkit/ActionQueuePanel'
require 'RadioCom/RadioWindowModules/RWMPower'
require 'TimedActions/ISReadABook'
local P=require 'QueueEnergyPlacement'
local F=require 'QueueDeviceBatteryBinding'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local native=config.mode=='native'
local phase='prepare';local started,ready,done=false,false,false;local index=1;local previous
local function case()return config.cases[index]end
local state,authority,ids,baseline,receipt,placement,placementState,proof,panel,quiet
local tracks,commands={},{}
local edits={cancelled=false,reordered=false,untouched=true}
local function now()return getTimestampMs()end
local since=now()
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function raw(event,value)print('[DEVICE_BATTERY_BINDING] '..event..' '..JSON.encode(value))end
local function emit(v)v.suite='device-battery-binding';v.actor='client1';v.kind=config.kind;v.mode=config.mode;JSON.emit(v)end
local function fail(e)if done then return end;done=true;print('[QUEUE_TEST] FAIL device-battery-binding '..tostring(e));emit({event='case',id=case(),status='failed',phase=phase,reason=tostring(e)})end
local function request(command)
 local args={case=case()};if command=='Prepare'then args.placement=placement;args.clientPlacement=proof end
 if isClient()then sendClientCommand('DeviceBatteryBindingTest',command,args);return end
 if command=='Prepare'then authority=F.prepare(getPlayer(),args.case,config.mode,placement,proof,previous);previous=nil;ids=authority.ids;raw('PREPARED',ids)
 elseif command=='Baseline'then baseline=assert(F.baseline(authority));raw('BASELINE',baseline)
 else receipt=assert(F.verify(authority));raw('VERIFIED',receipt)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if done then return end
 if module=='DeviceBatteryBindingTest'then
  if command=='Failed'then fail(args.error)elseif args and args.case==case()then
   if command=='Prepared'then ids=args elseif command=='Baselined'then baseline=args elseif command=='Verified'then receipt=args end
  end
 elseif module=='PZSurvivorToolkitActions'and command=='State'and isClient()then
  for action,row in pairs(tracks)do
   if row.type=='ISDeviceBatteryAction'and ((args.state=='started'and queue().current==action and action.toolkitNativeTransaction==args.transaction and action.toolkitNativeKind==args.kind)or(row.ack and row.ack.token==args.token))then
    if args.state=='started'then assert(not row.ack and args.kind==row.type);row.ack={kind=args.kind,transaction=args.transaction,token=args.token,state='started'}
    else assert(row.ack and row.ack.state=='started'and args.state=='completed'and row.ack.transaction==args.transaction and row.ack.kind==args.kind);row.ack.state=args.state end
    raw('ACK',{case=case(),name=row.name,kind=args.kind,transaction=args.transaction,token=args.token,state=args.state});break
   end
  end
 end
end)
local function track(name,action,producer,constructorDuration)
 local row={name=name,type=action.Type,producer=producer,duration=constructorDuration or action.maxTime,started=false,progress=false}
 assert(type(row.duration)=='number'and row.duration>0);tracks[action]=row;commands[#commands+1]=row;return action
end
local function action(name,callback,remove)
 local emitted={};local add=ISTimedActionQueue.add
 ISTimedActionQueue.add=function(a)emitted[#emitted+1]={action=a,duration=a.maxTime};return add(a)end
 local ok,e=pcall(callback);ISTimedActionQueue.add=add;assert(ok,e)
 assert(#emitted==1,'unexpected native battery producer shape')
 local captured=emitted[1];local a=captured.action;assert(a.Type=='ISDeviceBatteryAction'and a.isRemove==remove and a.parameter==state.target and a.deviceData==state.data and captured.duration==30,'native battery constructor/binding differs')
 assert(remove and a.secondaryItem==nil or not remove and a.secondaryItem==state.battery)
 return track(name,a,'native RWMPower callback',captured.duration)
end
local function book(name,item)
 local a=ISReadABook:new(getPlayer(),item);track(name,a,'native ISReadABook constructor');ISTimedActionQueue.add(a);return a
end
local function observe()
 for a,row in pairs(tracks)do if queue().current==a and a:isStarted()then if not row.started then row.started=true;row.startedAt=now()end;if a:getJobDelta()>0 then row.progress=true end end end
end
local function acknowledgements()
 if not isClient()then return true end
 for _,row in ipairs(commands)do if row.type=='ISDeviceBatteryAction'and not row.cancelled and(not row.ack or row.ack.state~='completed')then return false end end
 return true
end
require('QueuePreflight').onGameStart(Events,function()started=true;since=now()end)
require('QueuePreflight').onTick(Events,function()
 if not started or done then return end
 local ok,e=pcall(function()
  local p=getPlayer();if not isIngameState()or not p or not p:getSquare()then return end
  if not ready then
   if isClient()~=(config.kind=='mp')or isClient()and(p:getOnlineID()<0 or p:getUsername()~='client1')then return end
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(not native)
   assert(PZSurvivorToolkit.Settings.actionQueue()==not native and not p:isTimedActionInstant())
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);p:setGodMod(true);p:setGhostMode(true);p:setAutoDrink(false)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
   ready=true;since=now();emit({event='setup',cases=config.cases,queueEnabled=not native,nativeDurations=true})
  end
  assert(now()-since<150000,'battery fixture timeout '..phase);observe()
  if phase=='prepare'then
   assert(empty());if not placementState then placement=P.choose(p);placementState=P.begin(p,placement)end
   proof=P.poll(placementState);if not proof then return end
   raw('CLIENT_PLACEMENT',{case=case(),proof=proof});phase='prepared';request('Prepare')
  elseif phase=='prepared'and ids then
   state=F.resolve(p,ids);if not state or p:tooDarkToRead()then return end
   panel=RWMPower:new(-1000,-1000,300,100);panel:initialise();panel:instantiate();assert(panel:readFromObject(p,state.target,state.data,'IsoObject'))
   state.input=F.snapshot(state);action('insert',function()panel:addBattery({state.battery})end,false);phase='insert'
  elseif phase=='insert'and empty()then
   if not F.baseline(state)or not acknowledgements()then return end
   phase='baseline';request('Baseline')
  elseif phase=='baseline'and baseline then
   state.frontAction=book('front',state.front);phase='front'
  elseif phase=='front'and tracks[state.frontAction].progress then
   local before=JSON.encode(F.snapshot(state))
   if not native and case()=='root'then
    local discard=action('cancelled-eject',function()panel:removeBattery()end,true)
    assert(PZSurvivorToolkit.ActionQueue.cancelOperation(queue(),discard),'pending battery cancellation denied')
    tracks[discard].cancelled=true;edits.cancelled=true
    assert(not discard.action and not tracks[discard].started and not tracks[discard].progress,'cancelled battery action started')
   end
   local eject=action('eject',function()panel:removeBattery()end,true)
   local tail=book('tail',state.tail)
   if not native and case()=='root'then
    assert(PZSurvivorToolkit.ActionQueue.move(queue(),eject,tail,true),'battery crossing independent book denied')
    assert(queue().queue[#queue().queue]==eject,'battery move did not commit')
    assert(PZSurvivorToolkit.ActionQueue.move(queue(),eject,tail),'battery return crossing independent book denied')
    assert(queue().queue[#queue().queue]==tail,'battery return move did not commit')
    edits.reordered=true
   end
   edits.untouched=before==JSON.encode(F.snapshot(state));assert(edits.untouched,'pending battery edits changed physical effects')
   phase='running'
  elseif phase=='running'and empty()then
   if not F.verify(state)or not acknowledgements()then quiet=nil;return end
   quiet=quiet or now();if now()-quiet>=1000 then phase='verified';request('Verify')end
  elseif phase=='verified'and receipt then
   local client=assert(F.verify(state));for _,row in ipairs(commands)do assert(row.cancelled and not row.started and not row.progress and not row.ack
    or not row.cancelled and row.started and row.progress,'missing native action progress/cancellation '..row.name)end
   emit({event='case',id=case(),status='passed',ids=ids,clientPlacement=proof,input=state.input,baseline=state.baseline,
    authorityBaseline=baseline,client=client,server=receipt,commands=commands,edit=edits,queueIdle=true,settleMilliseconds=now()-quiet})
   if not isClient()then previous=authority end
   index=index+1
   if not case()then emit({event='complete',cases=config.cases,performed=index-1,failed=0,skipped=0});raw('COMPLETE',{cases=config.cases});done=true;return end
   state,authority,ids,baseline,receipt,placement,placementState,proof,panel,quiet=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
   tracks,commands={},{};edits={cancelled=false,reordered=false,untouched=true};phase='prepare';since=now()
  end
 end)
 if not ok then fail(e)end
end)
