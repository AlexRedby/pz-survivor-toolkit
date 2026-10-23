require 'PZSurvivorToolkit/ActionQueuePanel'
require 'BuildingObjects/ISRemovePlantCursor'
require 'TimedActions/ISReadABook'
local F=require 'QueueApproach';local JSON=require 'QueueHealthEvents';local config=require 'QueueTestSelection'
local nativeHost=config.mode=='native'and config.kind=='mp'
local native=config.mode=='native';local phase,index,since='prepare',1,0
local started,ready,done=false,false,false
local state,authority,ids,baseline,receipt,input,tracks,commands,walks,order,secondIssue,quiet,lifecycle
local resolveDiagnosed,lastResolveWait={},nil
local idleCaptured,lastServerSnapshot,wireBindings=false,nil,{}
local idleReceipt,manualInputSeen=nil,false
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
local function raw(event,value)print('[QUEUE_APPROACH] '..event..' '..JSON.encode(value))end
local function emit(row)row.suite,row.kind,row.mode,row.actor='approach-queue',config.kind,config.mode,'client1';JSON.emit(row)end
local function snapshotDiagnostic()
 if not state then return false end
 local ok,value=pcall(F.snapshot,state);return ok and value or{snapshotError=tostring(value)}
end
local function queueDiagnostic()
 local player=getPlayer();if not player then return false end
 local q=queue();local pending={}
 for _,action in ipairs(q.queue)do local row=tracks and tracks[action]
  pending[#pending+1]={name=row and row.name or false,type=action.Type,actionRef=tostring(action),token=tokenId(action.toolkitQueueOperation),
   nativeRef=action.action and tostring(action.action)or false,transaction=action.toolkitNativeTransaction or false,kind=action.toolkitNativeKind or false}
 end
 return{current=q.current and tostring(q.current)or false,currentType=q.current and q.current.Type or false,pending=pending,
  hasTimedActions=player:hasTimedActions(),nativeCount=player:getCharacterActions():size(),pressedMovement=player:pressedMovement(false),pressedCancel=player:pressedCancelAction(),manualInputSeen=manualInputSeen,position={x=player:getX(),y=player:getY(),z=player:getZ()}}
end
local function fail(error)
 if done then return end
 emit({event='case',id=case(),status='failed',reason=tostring(error),phase=phase,ids=ids,commands=commands,walks=walks,order=order,
  resolveWait=lastResolveWait,clientSnapshot=snapshotDiagnostic(),lastServerSnapshot=lastServerSnapshot or false,queueCurrent=queueDiagnostic()})
 print('[QUEUE_TEST] FAIL approach-queue '..tostring(error));done=true
end
local function request(command)
 if isClient()then sendClientCommand('QueueApproachTest',command,{case=case()});return end
 if command=='Prepare'then authority=F.prepare(getPlayer(),case(),config.mode);ids=authority.ids;raw('PREPARED',ids)
 elseif command=='Baseline'then baseline=assert(F.baseline(authority));raw('BASELINE',baseline)
 elseif command=='Snapshot'then lastServerSnapshot=F.snapshot(authority);raw('SNAPSHOT',lastServerSnapshot)
 else receipt=assert(F.verify(authority));raw('VERIFIED',receipt)end
end
-- Diagnostic observation only: keep the real action/native references across
-- Done advancing the queue, and associate every receipt with its native identity.
local function observeNative(module,command,args)
 if module~='PZSurvivorToolkitActions'or command~='State'or not isClient()or not tracks or type(args)~='table'then return end
 local player=getPlayer()
 if not player or args.protocol~=1 or args.player~=player:getOnlineID()or type(args.transaction)~='number'or args.transaction%1~=0
  or args.transaction==0 or args.transaction< -128 or args.transaction>127 or type(args.kind)~='string'or type(args.token)~='string'
  or not args.token:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')then return end
 local binding=wireBindings[args.token]
 if not binding then
  local found
  for action,row in pairs(tracks)do
   if action.character==player and action.toolkitNativeTransaction==args.transaction and action.toolkitNativeKind==args.kind then
    if found then found=false;break end
    found={action=action,row=row,native=action.action,player=args.player,transaction=args.transaction,kind=args.kind,token=args.token}
   end
  end
  if found then binding=found;wireBindings[args.token]=binding end
 end
 local matched=binding and binding.player==args.player and binding.transaction==args.transaction and binding.kind==args.kind
 local action=matched and binding.action;local row=matched and binding.row
 local value={case=case(),observedAt=now(),player=args.player,transaction=args.transaction,kind=args.kind,token=args.token,state=args.state,
  matched=matched==true,name=row and row.name or false,type=row and row.type or false,actionRef=action and tostring(action)or false,
  nativeRef=matched and binding.native and tostring(binding.native)or false,currentActionRef=queue().current and tostring(queue().current)or false,
  referenceStable=matched and action.action==binding.native and action.toolkitNativeTransaction==args.transaction and action.toolkitNativeKind==args.kind or false}
 if row then row.nativeStates=row.nativeStates or{};row.nativeStates[#row.nativeStates+1]=value end
 raw('NATIVE_STATE',value)
end
Events.OnServerCommand.Add(function(module,command,args)
 observeNative(module,command,args)
 if module~='QueueApproachTest'or done then return end
 if command=='Failed'then fail(args.error)
 elseif args and args.case==case()then if command=='Prepared'then ids=args elseif command=='Baselined'then baseline=args elseif command=='Verified'then receipt=args elseif command=='Snapshot'then lastServerSnapshot=args;raw('SERVER_SNAPSHOT',args)end end
end)
local function position()local p=getPlayer();return{x=p:getX(),y=p:getY(),z=p:getZ()}end
local function near(p,id)return p.z==id.z and math.abs(p.x-id.x-.5)<=1.6 and math.abs(p.y-id.y-.5)<=1.6 end
local function finite(value)return type(value)=='number'and value==value and value>-math.huge and value<math.huge end
local function duration(action,row)
 if row.allocatedAt then assert(action.maxTime==row.effectiveDuration,'allocated duration changed');return end
 if not action.action then return end
 local after=action:adjustMaxTime(row.duration);local before=row.nativeDurationBefore;local effective=action.maxTime
 assert(finite(before)and finite(after)and finite(effective)and before>1 and after>1 and effective>1)
 assert(math.abs(after-before)<=math.max(.001,row.duration*.00001),'native duration bracket too wide')
 assert(effective>=math.min(before,after)-.001 and effective<=math.max(before,after)+.001,'native duration allocation differs')
 local at=now();row.nativeDurationAfter=after;row.durationSampleAfter=at;row.effectiveDuration=effective;row.allocatedAt=at
end
-- Observe native queue admission; no action lifecycle callback is replaced.
local add=ISTimedActionQueue.add
ISTimedActionQueue.add=function(action)
 local row
 if state and tracks and action.character==getPlayer()then
  local name
  if action.Type=='ISRemoveBush'or action.Type=='ISRemoveGrass'then
   for _,n in ipairs({'first','second'})do local id=ids.targets[n];if action.square:getX()==id.x and action.square:getY()==id.y and action.square:getZ()==id.z then name=n end end
  elseif action.Type=='ISReadABook'and action.item:getID()==ids.book.id then name='tail'end
  if name then
   for _,r in ipairs(commands)do assert(r.name~=name,'duplicate native operation '..name)end
   row={name=name,admittedAt=now(),type=action.Type,duration=action.maxTime,producer=name=='tail'and'native ISReadABook constructor'or'native ISRemovePlantCursor.tryBuild',started=false,progress=false,
    itemId=name=='tail'and action.item:getID()or false,target=name~='tail'and ids.targets[name]or false,nativeDurationBefore=action:adjustMaxTime(action.maxTime),durationSampleBefore=now(),durationSamples=1}
   commands[#commands+1]=row;tracks[action]=row
  elseif action.Type=='ISWalkToTimedAction'then
   row={type=action.Type,started=false,progress=false,admittedAt=now(),duration=action.maxTime,destination={x=action.location:getX(),y=action.location:getY(),z=action.location:getZ()}};walks[#walks+1]=row;tracks[action]=row
  end
 end
 local result=add(action);if row then row.token=tokenId(action.toolkitQueueOperation);if row.name then duration(action,row)end end;return result
end
local function observe()
 for action,row in pairs(tracks or{})do
  row.cancelled=type(action.toolkitQueueOperation)=='table'and action.toolkitQueueOperation.toolkitCancelled==true
  if row.type=='ISWalkToTimedAction'then assert(action.maxTime==row.duration and row.duration==-1,'native walk duration changed')end
  if row.name then
   if not row.allocatedAt and not action.action then row.nativeDurationBefore=action:adjustMaxTime(row.duration);row.durationSampleBefore=now();row.durationSamples=row.durationSamples+1
   elseif action.action and queue():indexOf(action)~=-1 then duration(action,row)end
  end
  if queue().current==action and action:isStarted()then
   if not row.started then
    row.started=true;row.startedAt=now();row.startPosition=position()
    if row.name then order[#order+1]=row.name;assert(row.name=='tail'or near(row.startPosition,ids.targets[row.name]),'removal started outside native reach')end
   end
   if row.type=='ISWalkToTimedAction'then local p=position();if math.abs(p.x-row.startPosition.x)+math.abs(p.y-row.startPosition.y)>.02 then row.progress=true end
   elseif action:getJobDelta()>0 then row.progress=true end
  end
  if row.started and not row.endedAt and queue():indexOf(action)==-1 then row.endedAt=now();row.endPosition=position()end
 end
 if state then F.snapshot(state)end
 if authority then F.snapshot(authority)end
end
local function cursor(name)
 local id=ids.targets[name];local c=ISRemovePlantCursor:new(getPlayer(),case()=='bush'and'bush'or'grass')
 assert(c:isValid(getCell():getGridSquare(id.x,id.y,id.z))and not ISBuildMenu.cheat)
 c:tryBuild(id.x,id.y,id.z)
end
local function freeze()
 local value={};for _,class in ipairs({ISRemoveBush,ISRemoveGrass,ISWalkToTimedAction,ISReadABook})do
  for _,name in ipairs({'new','start','stop','update','perform','complete','getDuration','isValid','waitToStart','animEvent','serverStart'})do value[#value+1]={class=class,name=name,callback=class[name]}end
 end;return value
end
local function unchanged()for _,v in ipairs(lifecycle)do assert(v.class[v.name]==v.callback,'native lifecycle callback changed '..v.name)end;return true end
local function finish()
 observe();local client=assert(F.verify(state));unchanged()
 local enabled=not native;local expected=enabled and{'first','second','tail'}or nativeHost and{'second'}or{'second','tail'}
 assert(#order==#expected);for i,name in ipairs(expected)do assert(order[i]==name,'native start order differs')end
 secondIssue.action=nil
 emit({event='case',id=case(),status='passed',ids=ids,input=input,authorityBaseline=baseline,client=client,server=receipt,
  commands=commands,walks=walks,order=order,secondIssue=secondIssue,clientIdle=idleReceipt,serverIdle=lastServerSnapshot,manualInputSeen=manualInputSeen,queueIdle=true,settleMilliseconds=now()-quiet,lifecycleUnchanged=true})
 index=index+1;if not case()then emit({event='complete',cases=config.cases,performed=2,failed=0,skipped=0});raw('COMPLETE',{cases=config.cases});done=true;return end
 state,authority,ids,baseline,receipt,input,tracks,commands,walks,order,secondIssue,quiet=nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil,nil
 resolveDiagnosed,lastResolveWait={},nil;idleCaptured,lastServerSnapshot,wireBindings=false,nil,{};idleReceipt,manualInputSeen=nil,false;phase='prepare';since=now()
end
Events.OnGameStart.Add(function()started=true;since=now()end)
Events.OnTick.Add(function()
 if not started or done then return end
 local ok,error=pcall(function()
  local player=getPlayer();if not isIngameState()or not player or not player:getSquare()then return end
  if not ready then
   if isClient()~=(config.kind=='mp')or isClient()and(player:getOnlineID()<0 or player:getUsername()~='client1')then return end
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(not native)
   assert(PZSurvivorToolkit.Settings.actionQueue()==not native and not player:isTimedActionInstant())
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
   lifecycle=freeze();ready=true;emit({event='setup',cases=config.cases,queueEnabled=not native,nativeDurations=true})
  end
  if(phase=='walking'or phase=='running')and(player:pressedMovement(false)or player:pressedCancelAction())then manualInputSeen=true end
  assert(now()-since<180000,'approach timeout '..tostring(case())..' phase='..phase);observe();unchanged()
  if phase=='running'and #queue().queue==0 and not idleCaptured then
   idleCaptured=true;idleReceipt={case=case(),phase=phase,observedAt=now(),client=snapshotDiagnostic(),queue=queueDiagnostic()};raw('CLIENT_IDLE',idleReceipt);request('Snapshot')
  end
  if phase=='prepare'then assert(empty());phase='prepared';request('Prepare')
  elseif phase=='prepared'and ids then
   state,lastResolveWait=F.resolve(player,ids)
   if not state then
    local reason=lastResolveWait and lastResolveWait.reason or'unknown resolve wait'
    if not resolveDiagnosed[reason]then resolveDiagnosed[reason]=true;raw('RESOLVE_WAIT',lastResolveWait or{case=case(),reason=reason})end
    return
   end
   tracks,commands,walks,order={},{},{},{};input=assert(F.baseline(state));phase='baseline';request('Baseline')
  elseif phase=='baseline'and baseline then cursor('first');phase='walking'
  elseif phase=='walking'then
   local active=queue().current;local row=tracks[active]
   if not row or row.type~='ISWalkToTimedAction'or not row.started then return end
   local p=position();assert(near(p,ids.targets.second)and not near(p,ids.targets.first),'second no longer initially near')
   secondIssue={firstWalking=true,position=p,firstStartedAt=row.startedAt,issuedAt=now(),action=active}
   cursor('second');secondIssue.firstRetainedAfterIssue=queue():indexOf(active)~=-1
   secondIssue.firstJavaRetainedAfterIssue=active.action and player:getCharacterActions():contains(active.action)or false
   ISTimedActionQueue.add(ISReadABook:new(player,state.book));phase='running'
  elseif phase=='running'and empty()then
   if nativeHost then
    local second
    for _,row in ipairs(commands)do if row.name=='second'then second=row end end
    local receipts=second and second.nativeStates or{}
    if #receipts~=2 or receipts[1].state~='started'or receipts[2].state~='completed'or not lastServerSnapshot then quiet=nil;return end
   end
   if not F.verify(state)then quiet=nil;return end
   quiet=quiet or now();if now()-quiet>=1000 then phase='verified';request('Verify')end
  elseif phase=='verified'and receipt then finish()end
 end);if not ok then fail(error)end
end)
