assert(NativeActionRoot,'device admission checks require --game or --native-action-root')
-- Native queue/constructors and the real operation ledger execute below. The
-- Java reader and position-source/observer transports are explicit test doubles;
-- QueueSpatialFactsChecks owns actual JVM identity and invocation certification.
local function named(source,name)return assert(loadstring(source,'@/device-admission-fixture/'..name))()end
local function fresh(missingBridge,largeEnvironment)
 local f=assert(loadfile(ProjectRoot..'/tests/support/action_queue_native.lua'))()
 f.native('shared/RadioCom/ISRadioAction.lua')
 f.native('client/TimedActions/WalkToTimedAction.lua')
 f.native('shared/TimedActions/ISDeviceBatteryAction.lua')
 f.native('shared/TimedActions/ISDeviceMediaAction.lua')
 local metadataCalls,metadataHook=0,nil
 local filename=NativeFilenameOfClosure or function(callback)return debug.getinfo(callback,'S').source end
 getFilenameOfClosure=function(callback)
  metadataCalls=metadataCalls+1;if metadataHook then metadataHook(callback)end
  return filename(callback)
 end
 isServer=function()return false end
 local actor=f.player;actor.class='IsoPlayer'
 actor.isLocalPlayer=function()return true end;actor.isDraggingCorpse=function()return false end
 getSpecificPlayer=function(index)if index==0 then return actor end end
 local settlement=f.project('ActionQueueSettlement')
 local ops=f.project('ActionQueueOperations')
 local knownPositions,observer={},nil
 local policy=named([[return {matchesNative=function(action)
  return getmetatable(action)==ISRadioAction and action.onStartFunc==nil and action.onCompleteFunc==nil
 end}]],'ActionQueuePolicy.lua')
 local media=named([[return {pendingDeviceSupported=function(action)
  return getmetatable(action)==ISDeviceMediaAction or getmetatable(action)==ISDeviceBatteryAction
 end}]],'ActionQueueMedia.lua')
 DeviceAdmissionPositionCalls=0
 local approach=named([[return {prepareDevicePosition=function(action,parent)
  DeviceAdmissionPositionCalls=DeviceAdmissionPositionCalls+1
  local record=DeviceAdmissionPositions[action]
  if not record then return end
  local square,owner,class,callback=record.square,action.toolkitQueueOperation,getmetatable(action),action.perform
  return function()
   return DeviceAdmissionPositions[action]==record and record.valid and record.square==square
    and action.toolkitQueueOperation==owner and getmetatable(action)==class and action.perform==callback
  end,square
 end}]],'ActionQueueApproach.lua')
 DeviceAdmissionPositions=knownPositions
 local lifecycle=named([[return {current=function()end,registerObserver=function(id,value)
  assert(id=='device-target-admission');DeviceAdmissionObserver=value;return true
 end}]],'ActionQueueLifecycle.lua')
 PZSurvivorToolkit.ActionQueuePolicy=policy;PZSurvivorToolkit.ActionQueueMedia=media
 PZSurvivorToolkit.ActionQueueApproach=approach;PZSurvivorToolkit.ActionQueueLifecycle=lifecycle
 local captures,reads,worldGetters,phase=0,0,0,'source'
 local nativeHook
 local anchors={}
 local bridge,checker,classify
 bridge=function(device,data,anchor,route)
  reads=reads+1;if nativeHook then nativeHook()end
  local saved=anchor and anchors[anchor]
  if anchor and not saved then return end
  device=device or saved and saved.device or data and data.parent
  if not device or(device.class~='IsoTelevision'and device.class~='IsoRadio')or not data or data.class~='DeviceData'then return end
  if saved and(saved.device~=device or saved.data~=data)then return end
  if route~=nil and route~=(saved and saved.square or device.square)then return end
  if saved then return device.square==saved.square and device.data==data and data.parent==device and device.present end
  if not device.square or not device.present or device.data~=data or data.parent~=device then return end
  local handle={};anchors[handle]={device=device,data=data,square=device.square};captures=captures+1;return handle
 end
 checker=function(callback)return callback==bridge end
 classify=function(value)
  if value==checker or value==bridge then return 'LuaJavaInvoker'end
  if value==actor then return 'IsoPlayer'end
  return 'Foreign'
 end
 local largeProof
 if largeEnvironment then
  -- Genuine environment entries and pairs: no ordered-iterator/lookup stand-in.
  toolkitQueueDeviceTarget=nil;toolkitQueueDeviceApiMatches=nil;getClassSimpleName=nil
  for index=1,4096 do _G['DeviceAdmissionEnvironment'..index]=index end
 end
 toolkitQueueDeviceTarget=not missingBridge and bridge or nil
 toolkitQueueDeviceApiMatches=not missingBridge and checker or nil
 getClassSimpleName=classify
 if largeEnvironment then
  for attempt=1,8 do
   local total,positions=0,{}
   for key in pairs(_G)do
    total=total+1
    if key=='toolkitQueueDeviceTarget'or key=='toolkitQueueDeviceApiMatches'or key=='getClassSimpleName'then positions[key]=total end
   end
   if positions.toolkitQueueDeviceTarget>128 and positions.toolkitQueueDeviceApiMatches>128 and positions.getClassSimpleName>128 then
    largeProof={total=total,positions=positions};break
   end
   for index=1,4096 do local key=attempt*4096+index;_G['DeviceAdmissionEnvironment'..key]=key end
  end
  assert(largeProof and largeProof.total>4096,'large environment control must place all bridge keys beyond old cap')
 end
 local module=f.project('ActionQueueDeviceTargets')
 local installed=module.install();if not missingBridge then assert(installed)end
 observer=DeviceAdmissionObserver
 local function object(kind)
  local square={class='IsoGridSquare'};local device={class=kind or'IsoTelevision',square=square,present=true}
  local data={class='DeviceData',parent=device};device.data=data
  local function getter(value)
   if phase=='guarded'then worldGetters=worldGetters+1;error('Lua world getter invoked')end
   return value
  end
  device.getDeviceData=function()return getter(data)end
  device.getSquare=function()return getter(device.square)end
  data.getParent=function()return getter(data.parent)end
  square.getDeviceData=function()return getter(data)end
  return device,data,square
 end
 local function enqueue(action,token)
  ops.adopt(action,token)
  ISTimedActionQueue.add(action)
  module.enqueued(action)
  return action
 end
 local function external()
  local hold=f.action(ISReadABook,{toolkitQueueOperation={}});hold.action={};hold.started=true
  local queue=f.queue(hold)
  return queue,hold
 end
 local function body(device,mode,paid,isRemove)
  phase='construct'
  local action
  if paid=='media'then action=ISDeviceMediaAction:new(actor,isRemove,nil,device.square)
  elseif paid=='battery'then action=ISDeviceBatteryAction:new(actor,isRemove,nil,device.square)
  else action=ISRadioAction:new(mode or'SetVolume',actor,device,.75)end
  phase='guarded';return action
 end
 local function preparation(square,token,parent)
  local action=ops.command(actor,function()end,{square=square})
  knownPositions[action]={square=square,valid=true}
  if parent then
   ops.adopt(action,token);module.positionEnqueued(action,parent)
  else enqueue(action,token)end
  return action
 end
 return {f=f,actor=actor,ops=ops,settlement=settlement,module=module,observer=observer,object=object,
  enqueue=enqueue,external=external,body=body,preparation=preparation,known=knownPositions,
  largeProof=largeProof,counts=function()return captures,reads,worldGetters,DeviceAdmissionPositionCalls,metadataCalls end,hook=function(value)nativeHook=value end,
  metadataHook=function(value)metadataHook=value end,releaseBridgeAnchors=function()anchors={}end,
  check=function(action)return settlement.deviceStep(action)end}
end
local count=0
local function check(callback)callback();count=count+1 end
for _,class in ipairs({'IsoTelevision','IsoRadio'})do
 for _,loss in ipairs({'remove','move'})do
  check(function()
   local f=fresh();local queue,hold=f.external();local device,data,square=f.object(class)
   local token={};local prep=f.preparation(square,token)
   local body=f.enqueue(f.body(device),token)
   local tail=f.enqueue(f.f.action(ISReadABook,{toolkitQueueOperation={}}),{})
   local descriptor=assert(f.check(body));assert(f.module.owns(body,descriptor))
   assert(type(descriptor)=='table'and descriptor.admitted==nil and descriptor.role==nil,'mutable flags escaped')
   for _,seal in pairs(descriptor)do assert(type(seal)=='function'and seal({},body,descriptor)==nil,'closed state escaped')end
   f.module.enqueued(body);assert(f.counts()==1,'enqueue captured a replacement anchor')
   if loss=='remove'then device.square=nil;device.present=false else device.square={}end
   assert(f.module.skipUnavailable(queue,hold),'lost pending target not refused')
   assert(#queue.queue==2 and queue.queue[1]==hold and queue.queue[2]==tail and queue.current==hold)
   assert(body.action==nil and prep.action==nil and not token.toolkitCancelled)
   local _,_,getters=f.counts();assert(getters==0)
  end)
 end
end
for _,mode in ipairs({'ToggleOnOff','SetChannel','SetVolume','MuteVolume','UnMuteVolume','MuteMicrophone',
 'TogglePlayMedia','AddHeadphones','RemoveHeadphones'})do
 check(function()
  local f=fresh();local queue,hold=f.external();local device=f.object('IsoRadio')
  local action=f.enqueue(f.body(device,mode),{})
  assert(f.check(action),'native radio mode omitted: '..mode)
  device.square=nil;device.present=false
  assert(f.module.skipUnavailable(queue,hold)and #queue.queue==1)
 end)
end
for _,family in ipairs({'media','battery'})do
 for _,remove in ipairs({false,true})do
  check(function()
   local f=fresh();local queue,hold=f.external();local device=f.object('IsoRadio')
   local action=f.enqueue(f.body(device,nil,family,remove),{})
   assert(action.device==nil and f.check(action),'nil-device paid source family omitted')
   device.square={}
   assert(f.module.skipUnavailable(queue,hold)and #queue.queue==1)
  end)
 end
end
check(function()
 local f=fresh();local queue,hold=f.external();local device=f.object()
 local body=f.enqueue(f.body(device),{});local original=queue.queue
 assert(not f.module.skipUnavailable(queue,hold)and queue.queue==original and #queue.queue==2,'live target pruned')
 f.module.admitting(body);device.square=nil;device.present=false
 assert(not f.module.skipUnavailable(queue,hold)and #queue.queue==2,'admitted native body pruned')
end)
check(function()
 local f=fresh();local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
 body.action={};device.square=nil;device.present=false
 assert(not f.module.skipUnavailable(queue,hold)and #queue.queue==2,'allocated body pruned')
end)
check(function()
 local f=fresh();local queue,hold=f.external();local device=f.object();local token={}
 local prep=f.preparation(device.square,token);local body=f.enqueue(f.body(device),token)
 queue.queue={prep,body};queue.current=prep
 f.module.admitting(prep);f.settlement.started(prep);assert(f.observer.started(prep)==nil)
 prep.action={}
 assert(f.observer.begin(prep,'perform')==nil,'observer granted lifecycle permission')
 device.square=nil;device.present=false
 assert(f.module.skipUnavailable(queue,prep)and #queue.queue==1 and queue.current==prep and prep.action)
 assert(not token.toolkitCancelled,'paid position token invalidated')
end)
check(function()
 local f=fresh();local queue,hold=f.external();local device=f.object();local token={}
 local prep=f.preparation(device.square,token);local body=f.enqueue(f.body(device),token)
 f.module.admitting(prep);f.settlement.started(prep);f.observer.started(prep);prep.action={}
 f.observer.begin(prep,'perform');f.observer.finish(prep,'perform',true);f.observer.settled(prep)
 queue.queue={hold,body};queue.current=hold
 device.square=nil;device.present=false
 assert(f.module.skipUnavailable(queue,hold)and #queue.queue==1,'completed position history rejected')
end)
for _,change in ipairs({
 function(f,body,device)body.isValid=function()error('foreign validity invoked')end end,
 function(f,body,device)body.extra=function()error('foreign own callback invoked')end end,
 function(f,body,device)body.deviceData={}end,
 function(f,body,device)body.toolkitQueueOperation.toolkitContinuations=1 end,
 function(f,body,device)f.settlement.track(f.f.action(ISReadABook,{toolkitQueueOperation=body.toolkitQueueOperation}),'body')end,
})do
 check(function()
  local f=fresh();local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
  change(f,body,device);device.square=nil;device.present=false
  assert(not f.module.skipUnavailable(queue,hold)and #queue.queue==2,'unknown source/debt/history pruned')
 end)
end
check(function()
 local f=fresh();local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
 device.square=nil;device.present=false
 f.hook(function()body.device={}end)
 assert(not f.module.skipUnavailable(queue,hold)and #queue.queue==2,'world-read reentry used stale source')
end)
check(function()
 local f=fresh();local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
 local original=toolkitQueueDeviceTarget;local calls=0
 toolkitQueueDeviceTarget=function()calls=calls+1;error('foreign reader invoked')end
 device.square=nil;device.present=false
 assert(not f.module.skipUnavailable(queue,hold)and calls==0 and #queue.queue==2)
 toolkitQueueDeviceTarget=original
end)
check(function()
 local f=fresh(true);assert(not f.module.install(),'old bridge installed admission')
 local device=f.object();local body=f.body(device);f.module.enqueued(body);f.module.admitting(body)
 assert(not f.module.owns(body,{})and f.counts()==0)
end)
check(function()
 local f=fresh();local queue,hold=f.external();local beforeCapture,beforeRead,_,beforeFactory,beforeMetadata=f.counts()
 for index=1,24 do f.preparation({},{});f.enqueue(f.f.action(ISReadABook,{toolkitQueueOperation={}}),{})end
 local capture,read,_,factory,metadata=f.counts()
 assert(capture==beforeCapture and read==beforeRead and factory==beforeFactory and metadata==beforeMetadata,
  'generic queued preparation/tail paid device source or metadata cost')
end)
check(function()
 local f=fresh();local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
 local descriptor=assert(f.check(body));descriptor.admitted=false;descriptor.role='position';descriptor.completed=true
 f.module.admitting(body);device.square=nil;device.present=false
 assert(not f.module.skipUnavailable(queue,hold),'mutable handle flags forged pending authority')
end)
check(function()
 local f=fresh();local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
 device.square=nil;device.present=false
 local previous=string.gsub;local calls=0
 string.gsub=function()calls=calls+1;error('foreign source helper executed')end
 local skipped=f.module.skipUnavailable(queue,hold);string.gsub=previous
 assert(not skipped and calls==0 and #queue.queue==2,'source primitive changed before metadata was invoked')
end)
check(function()
 local f=fresh();local queue,hold=f.external();local device=f.object();local token={}
 local prep=f.preparation(device.square,token);local body=f.enqueue(f.body(device),token)
 queue.queue={prep,body};queue.current=prep
 f.module.admitting(prep);f.settlement.started(prep);f.observer.started(prep);prep.action={}
 local child=ISWalkToTimedAction:new(f.actor,device.square)
 f.known[child]={square=device.square,valid=true}
 f.ops.adopt(child,token);table.insert(queue.queue,2,child);f.module.positionEnqueued(child,prep)
 assert(f.check(child),'owned native child did not inherit device binding')
 f.observer.begin(prep,'perform');f.observer.finish(prep,'perform',true);f.observer.settled(prep)
 queue.queue={hold,child,body};queue.current=hold
 device.square=nil;device.present=false
 assert(f.module.skipUnavailable(queue,hold)and #queue.queue==1,'native child/history admission failed')
end)
check(function()
 local f=fresh();local queue,hold=f.external();local parent=f.ops.command(f.actor,function()end,{})
 local child=ISWalkToTimedAction:new(f.actor,{})
 f.known[child]={square={},valid=true}
 local _,reads,_,factory,metadata=f.counts()
 f.module.positionEnqueued(child,parent)
 local _,afterReads,_,afterFactory,afterMetadata=f.counts()
 assert(reads==afterReads and factory==afterFactory and metadata==afterMetadata,'generic child paid metadata/source cost')
end)
check(function()
 local f=fresh();local queue,hold=f.external();local device=f.object();local token={}
 local prep=f.preparation(device.square,token);local body=f.enqueue(f.body(device),token)
 f.module.admitting(prep);f.settlement.started(prep);f.observer.started(prep);prep.action={}
 f.observer.begin(prep,'perform');f.observer.finish(prep,'perform',false);f.observer.settled(prep)
 queue.queue={hold,body};queue.current=hold;device.square=nil;device.present=false
 assert(not f.module.skipUnavailable(queue,hold)and #queue.queue==2,'failed position forged completed history')
end)
check(function()
 local f=fresh();local queue,hold=f.external();local device=f.object();local token={}
 local prep=f.preparation({},token);local body=f.enqueue(f.body(device),token)
 device.square=nil;device.present=false
 assert(not f.module.skipUnavailable(queue,hold)and #queue.queue==3,'unrelated position inherited body target')
end)
check(function()
 local f=fresh();local queue,hold=f.external();local device=f.object();local body=f.body(device)
 body.maxTime=1;f.enqueue(body,{})
 assert(not f.check(body),'retimed action acquired native device admission contract')
end)
check(function()
 local f=fresh();local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
 local original= getmetatable(body);local calls=0
 setmetatable(body,{__metatable=original,__index=function()calls=calls+1;error('hidden class invoked')end})
 device.square=nil;device.present=false
 assert(not f.module.skipUnavailable(queue,hold)and calls==0 and #queue.queue==2,'protected foreign metatable acquired source authority')
end)
for _,mutation in ipairs({'native-handle','protected-meta'})do
 check(function()
  local f=fresh();local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
  local originalNative,originalClass=hold.action,getmetatable(hold);local calls=0
  device.square=nil;device.present=false
  f.hook(function()
   if mutation=='native-handle'then hold.action={}
   else setmetatable(hold,{__metatable=originalClass,__index=function()calls=calls+1;error('external hold callback invoked')end})end
  end)
  assert(not f.module.skipUnavailable(queue,hold)and #queue.queue==2 and queue.queue[1]==hold and queue.queue[2]==body,
   'final world read changed external head but pending device was dropped: '..mutation)
  assert(calls==0,'external head foreign callback executed during refusal')
 end)
end
check(function()
 local f=fresh(false,true);assert(f.largeProof.total>128)
 local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
 assert(f.check(body),'large plain native environment lost enqueue binding')
 device.square=nil;device.present=false
 assert(f.module.skipUnavailable(queue,hold)and #queue.queue==1,'large plain native environment lost refusal')
end)
check(function()
 local f=fresh(false,true);local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
 local previous=rawget;local calls=0
 rawget=function()calls=calls+1;error('replaced rawget invoked')end
 device.square=nil;device.present=false
 local skipped=f.module.skipUnavailable(queue,hold);rawget=previous
 assert(not skipped and calls==0 and #queue.queue==2,'changed rawget retained binding or executed')
end)
check(function()
 local f=fresh(false,true);local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
 local original=getmetatable(body);local calls=0
 setmetatable(body,{__metatable=original,__index=function()calls=calls+1;error('protected inherited getter invoked')end})
 device.square=nil;device.present=false
 assert(not f.module.skipUnavailable(queue,hold)and calls==0 and #queue.queue==2,'large env protected action invoked inherited lookup')
end)
check(function()
 local f=fresh(false,true);local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
 local previous=toolkitLuaMetatableMatches;local calls=0
 toolkitLuaMetatableMatches=function()calls=calls+1;error('foreign metatable helper invoked')end
 device.square=nil;device.present=false
 local skipped=f.module.skipUnavailable(queue,hold);toolkitLuaMetatableMatches=previous
 assert(not skipped and calls==0 and #queue.queue==2,'changed native identity root retained binding or executed')
end)
check(function()
 local f=fresh(false,true);local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
 local env,previousRaw,write,changeMeta=_G,rawget,rawset,setmetatable;local calls=0
 device.square=nil;device.present=false
 changeMeta(env,{__index=function()calls=calls+1;error('inherited global primitive invoked')end})
 write(env,'rawget',nil)
 local skipped=f.module.skipUnavailable(queue,hold)
 write(env,'rawget',previousRaw);changeMeta(env,nil)
 assert(not skipped and calls==0 and #queue.queue==2,'nonplain env dispatched inherited primitive')
end)
check(function()
 local f=fresh();local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
 device.square=nil;device.present=false
 local original=getFilenameOfClosure;local calls=0
 getFilenameOfClosure=function()calls=calls+1;error('foreign filename accessor invoked')end
 local skipped=f.module.skipUnavailable(queue,hold);getFilenameOfClosure=original
 assert(not skipped and calls==0 and #queue.queue==2,'changed filename accessor executed or retained authority')
end)
for _,mutation in ipairs({'accessor','action'})do
 check(function()
  local f=fresh();local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
  local descriptor=assert(f.check(body));local seal
  for _,value in pairs(descriptor)do seal=value end
  assert(type(seal)=='function')
  device.square=nil;device.present=false
  local original=getFilenameOfClosure;local calls,entered=0,false
  local foreign=function()calls=calls+1;error('foreign metadata/action callback invoked')end
  f.metadataHook(function(callback)
   if callback~=seal or entered then return end
   entered=true
   if mutation=='accessor'then getFilenameOfClosure=foreign else body.isValid=foreign end
  end)
  local skipped=f.module.skipUnavailable(queue,hold)
  getFilenameOfClosure=original;f.metadataHook(nil)
  assert(entered,'private seal provenance skipped uncached metadata')
  assert(not skipped and calls==0 and #queue.queue==2,'metadata reentry used stale source authority: '..mutation)
 end)
end
for _,retirement in ipairs({'refused','reset'})do
 check(function()
  -- Lua 5.1 weak references test ownership of the Lua graph only. Kahlua weak
  -- modes and native JVM collection are deliberately not inferred from this.
  local weak=setmetatable({},{__mode='v'})
  local keepModule
  do
   local f=fresh();local queue,hold=f.external();local device,data,square=f.object()
   local token={};local body=f.enqueue(f.body(device),token)
   local descriptor=assert(f.check(body));assert(f.module.owns(body,descriptor))
   weak[1],weak[2],weak[3],weak[4],weak[5],weak[6]=body,descriptor,token,device,data,square
   if retirement=='refused'then
    device.square=nil;device.present=false
    assert(f.module.skipUnavailable(queue,hold)and #queue.queue==1)
   else
    hold.action.isStarted=function()return true end
    queue:resetQueue();assert(#queue.queue==0 and queue.current==nil)
   end
   -- The bridge double uses a strong handle lookup unlike the opaque native
   -- snapshot. Release that double's independent roots before testing Module.
   f.releaseBridgeAnchors();keepModule=f.module
  end
  collectgarbage('collect');collectgarbage('collect')
  assert(keepModule==PZSurvivorToolkit.ActionQueueDeviceTargets and keepModule.install(),
   'module/provenance cache must remain live during collection')
  for index=1,6 do assert(weak[index]==nil,'private seal/provenance memo retained retired graph: '..retirement..'/'..index)end
 end)
end
for _,mutation in ipairs({'descriptor','action-slot'})do
 check(function()
  local f=fresh();local queue,hold=f.external();local device=f.object();local body=f.enqueue(f.body(device),{})
  local descriptor=assert(f.check(body));local sealKey,seal,actionKey
  for key,value in pairs(descriptor)do sealKey,seal=key,value end
  for key,value in pairs(body)do if value==descriptor then actionKey=key end end
  assert(sealKey and actionKey and type(seal)=='function')
  local calls,entered=0,false
  local foreign=function()calls=calls+1;error('foreign seal invoked')end
  f.metadataHook(function(callback)
   if callback~=seal or entered then return end
   entered=true
   if mutation=='descriptor'then descriptor[sealKey]=foreign else body[actionKey]={}end
  end)
  assert(not f.module.owns(body,descriptor),'metadata reentry retained a replaced private identity: '..mutation)
  f.metadataHook(nil)
  assert(entered and calls==0,'private identity change invoked a foreign seal')
  device.square=nil;device.present=false
  assert(not f.module.skipUnavailable(queue,hold)and #queue.queue==2,'replaced private identity dropped pending native body')
 end)
end
if TestCoverage then TestCoverage('source-contract','passed')end
print('Device pending admission: '..count..' native-constructor/real-ledger source checks passed; native bridge is an explicit double.')
