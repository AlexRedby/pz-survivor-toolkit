local config=require 'QueueTestSelection'
if config.suite~='magazine-unload'or config.cases[1]~='equip-edit'or isServer()then return end
if PZ_QUEUE_EQUIP_EDIT_RUNNING then return end;PZ_QUEUE_EQUIP_EDIT_RUNNING=true
require 'PZSurvivorToolkit/ActionQueuePanel'
require 'TimedActions/ISEquipWeaponAction'
require 'TimedActions/ISReadABook'
require 'TimedActions/ISInventoryTransferAction'
local F=require 'QueueEquipEdit'
local HostPoint=require 'QueueEquipHostPoint'
local P=require 'QueueEnergyPlacement'
local JSON=require 'QueueHealthEvents'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Quiescence=require 'QueueEquipEditQuiescence'
local CallbackObservation=require 'QueueEquipCallbackObservation'
local tidyObserver
local workloadEnabled=config.options and config.options.equip_workload==true
local work
local native=config.mode=='native';local canEdit=not native
local started,ready,done=false,false,false
local phase,index='prepare',1
local state,authority,previous,ids,receipt,placement,arrival,proof,quiet
local tracks,commands,edits={}, {}, {}
local pendingBefore,pendingAfter,pendingOrder,componentGuard,handPoint
local frameLast,frameCadence=nil,{count=0,totalMilliseconds=0,maxMilliseconds=0}
local since=getTimestampMs();local serial,episodeSerial=0,0;local episodes={}
local callbacks={}
local callbackObserver,callbackReaders=nil,{}
-- Take the immutable baseline after selected-pack OnGameStart integrations,
-- including the source-owned MPFastForward reading animation fix.
local function captureCallbacks()
for _,class in ipairs({ISEquipWeaponAction,ISReadABook,ISInventoryTransferAction})do
 local values={};for _,key in ipairs({'new','isValid','waitToStart','start','update','perform','complete','stop','getDuration','animEvent'})do values[key]=class[key]end
 callbacks[class.Type]=values
end
end
local function now()return getTimestampMs()end
local function segment()return F.segments[index]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function tidyQuiet()return tidyObserver and tidyObserver.read(tracks)end
local function raw(event,value)print('[EQUIP_EDIT] '..event..' '..JSON.encode(value))end
local function emit(value)value.suite='magazine-unload';value.actor='client1';value.kind=config.kind;value.mode=config.mode;JSON.emit(value)end
local function failureFacts()
 local result={};local registry=PZSurvivorToolkit.ActionQueueHandEvents
 if registry then
  local current=registry.registeredCallbacks();result.handlers={}
  for _,phase in ipairs({'primary','secondary'})do
   local rows={};for _,callback in ipairs(current and current[phase]or{})do rows[#rows+1]={source=getFilenameOfClosure(callback),line=getFirstLineOfClosure(callback)}end
   result.handlers[phase]=rows
  end
 end
 result.globals=toolkitEquipGlobalsTrusted and toolkitEquipGlobalsTrusted()or false
 result.idle=toolkitEquipEventDispatchIdle and toolkitEquipEventDispatchIdle()or false
 result.equips={}
 for _,action in ipairs(queue().queue)do if action.Type=='ISEquipWeaponAction'then
  local items={action.item};local player=getPlayer();for _,item in ipairs({player:getPrimaryHandItem()or false,player:getSecondaryHandItem()or false})do
   if item and item~=action.item and item~=items[2]then items[#items+1]=item end
  end
  local row={id=action.item:getID(),itemClass=getClassSimpleName(action.item),fromHotbar=action.fromHotbar==true,
   quiet=toolkitEquipNativeQuiet and toolkitEquipNativeQuiet(player,items)or false,
   ownerTrusted=PZSurvivorToolkit.ActionQueueEquip.bindingsTrusted(),methods={}}
  for _,name in ipairs({'new','isValid','start','stop','perform','complete','begin','forceCancel'})do
   local callback=action[name];row.methods[name]={source=getFilenameOfClosure(callback),line=getFirstLineOfClosure(callback)}
  end
  local effect=PZSurvivorToolkit.ActionQueueHandEffects.certify(player,items);row.effects=type(effect)=='function'and effect()==true
  row.contract=PZSurvivorToolkit.ActionQueueEquip.inspect(action)~=nil;result.equips[#result.equips+1]=row
 end end
 return result
end
local function fail(reason)
 if done then return end;done=true
 local observed,tidy=pcall(function()return tidyObserver and tidyObserver.diagnose(tracks)or false end)
 raw('FAILED_STATE',{segment=segment(),phase=phase,reason=tostring(reason),state=state and F.snapshot(state)or false,
  facts=failureFacts(),commands=commands,tidyObservation=observed and tidy or tostring(tidy)})
 print('[QUEUE_TEST] FAIL magazine-unload equip-edit '..tostring(reason))
 emit({event='case',id='equip-edit',status='failed',segment=segment(),phase=phase,reason=tostring(reason)})
end
local function record(action,event,phase,succeeded)
 local row=tracks[action];if not row then return end
 local callbackProof=callbackReaders[action](event)
 if #callbackProof.differences>0 or not callbackProof.classUnchanged or not callbackProof.customCallbacksAbsent then row.callbacksUntouched=false end
 local actual=action.action;local episode=false
 if actual then if not episodes[actual]then episodeSerial=episodeSerial+1;episodes[actual]=episodeSerial end;episode=episodes[actual]end
 local item=action.item;local container=item:getContainer();local owner=container and container:getContainingItem()
 local itemLocation={root=container==getPlayer():getInventory(),containerPresent=container~=nil,owner=owner and owner:getID()or false}
 serial=serial+1;row.lifecycle[#row.lifecycle+1]={sequence=serial,event=event,phase=phase or false,succeeded=succeeded==true,
  callbackObservation=callbackProof,nativeEpisode=episode,nativeClass=actual and getClassSimpleName(actual)or false,hands=F.hands(getPlayer()),itemLocation=itemLocation}
end
assert(PZSurvivorToolkit.ActionQueueLifecycle.registerObserver('equip-edit-native-boundaries',{
 started=function(action)record(action,'admission')end,
 begin=function(action,phase)if tracks[action]then record(action,'begin',phase);return true end end,
 finish=function(action,phase,succeeded)record(action,'finish',phase,succeeded)end}))
local function track(name,action)
 local row={name=name,type=action.Type,item=action.item:getID(),duration=action.maxTime,callbacksUntouched=true,lifecycle={},started=false,progress=false}
 if action.Type=='ISEquipWeaponAction'then
  assert(action.maxTime==50 and action.maxTimeInit==50 and not action.twoHands and not action.fromHotbar,'explicit native equip constructor changed')
  row.primary=action.primary;row.twoHands=action.twoHands;row.maxTimeInit=action.maxTimeInit
 end
 if action.Type=='ISInventoryTransferAction'and isClient()then
  -- Native clients wait for the server transaction to supply the timer.
  local group=action.queueList and action.queueList[1]
  assert(config.kind=='mp'and row.duration==-1 and #action.queueList==1 and group.time==-1
   and #group.items==1 and group.items[1]==action.item and action.transactionId==0,'native client transfer constructor changed')
 else assert(type(row.duration)=='number'and row.duration>0 and row.duration<math.huge,'native action duration changed')end
 for key,callback in pairs(callbacks[action.Type])do assert(action[key]==callback,'native action callback changed '..key)end
 local read=callbackObserver.track(action);row.callbackConstructor=read('constructor')
 assert(row.callbackConstructor.verified and #row.callbackConstructor.differences==0,'native constructor callbacks differ')
 callbackReaders[action]=read;tracks[action]=row;commands[#commands+1]=row;ISTimedActionQueue.add(action);return action
end
local function book(name)return track(name,ISReadABook:new(getPlayer(),state.items[name]))end
local function equip(name,item,primary)return track(name,ISEquipWeaponAction:new(getPlayer(),item,50,primary,false))end
local function transfer(item,source)return track('transfer',ISInventoryTransferAction:new(getPlayer(),item,source,getPlayer():getInventory()))end
local function queueOrder()
 local order={};for _,action in ipairs(queue().queue)do order[#order+1]=assert(tracks[action],'unexpected native/P4 queued action').name end;return order
end
local function unchanged(before)
 assert(F.equal(before,F.snapshot(state)),'pending equip edit changed physical inventory/hands/pages')
end
local function attempt(name,fn,wanted,selected,target)
 local before=F.snapshot(state);local order=queueOrder();local schedule=false
 if not native and config.kind=='mp'and wanted then
  local policy=PZSurvivorToolkit.ActionQueuePolicy
  local decision=name=='cancel'and policy.evaluateCancel(queue(),selected,true)or policy.evaluateMove(queue(),selected,target)
  assert(decision.allowed and decision.nativeSchedule==true,'Host edit bypassed the native-unsubmitted decision')
  schedule=true
 end
 local began=now();local ok,reason=fn();local elapsed=now()-began
 assert(ok==wanted,'equip edit decision differs '..name..' '..tostring(reason))
 if not ok then assert(type(reason)=='string'and reason~='','denial lacks reason');assert(F.equal(order,queueOrder()),'denied equip edit changed queue')end

 unchanged(before);edits[#edits+1]={name=name,allowed=ok,reason=reason or false,decisionMilliseconds=elapsed,nativeSchedule=schedule,queueBefore=order,queueAfter=queueOrder()};return ok
end
local function guardedComponentFacts(item)
 local size=item:componentSize();assert(type(size)=='number'and size%1==0 and size>=0 and size<=8,'bounded component metadata unavailable')
 local components,types={},{}
 for index=0,size-1 do
  local component=assert(item:getComponentForIndex(index),'component index missing');local name=tostring(component:getComponentType())
  assert(not types[name],'duplicate component type');types[name]=true
  components[#components+1]={index=index,type=name,class=getClassSimpleName(component)}
 end
 local quietResult=toolkitEquipNativeQuiet(getPlayer(),{item})
 assert(size==2 and types.Script and types.Attributes and quietResult==false,'Hammer must retain Script+Attributes and protected eligibility')
 return{item=item:getID(),size=size,components=components,quiet=quietResult}
end
local function enqueuePending()
 local p,item,Q=getPlayer(),state.items,PZSurvivorToolkit.ActionQueue
 if segment()=='reorder-two'then
  local a=equip('equip-a',item.a,true);local b=equip('equip-b',item.b,true);book('tail')
  if not native then attempt('reorder',function()if work then return work:drag(queue(),b,a,canEdit)end;return Q.move(queue(),b,a)end,canEdit,b,a)
  elseif work then work:native(queue())end
 elseif segment()=='reorder-three'then
  local a=equip('equip-a',item.a,false);equip('equip-b',item.b,true);local c=equip('equip-c',item.c,false);book('tail')
  if not native then attempt('reorder',function()return Q.move(queue(),c,a)end,canEdit,c,a)end
 elseif segment()=='cancel'then
  equip('equip-a',item.a,true);equip('equip-b',item.b,false);local c=equip('equip-c',item.c,true);book('tail')
  if not native and attempt('cancel',function()if work then return work:cancel(queue(),c,canEdit)end;return Q.cancelOperation(queue(),c)end,canEdit,c)then tracks[c].cancelled=true end
 elseif segment()=='dependent'then
  local move=transfer(item.nested,item.bag:getItemContainer());local held=equip('equip-nested',item.nested,true);book('tail')
  if not native then
   attempt('unavailable-input',function()return Q.move(queue(),held,move)end,false)
   attempt('dependent-transfer',function()return Q.cancelOperation(queue(),move)end,false)
  end
 elseif segment()=='component-guard'then
  componentGuard=guardedComponentFacts(item.a)
  local a=equip('equip-a',item.a,true);local b=equip('equip-b',item.b,true);book('tail')
  if not native then
   attempt('component-reorder',function()return Q.move(queue(),b,a)end,false)
   attempt('component-cancel',function()return Q.cancelOperation(queue(),a)end,false)
  end
 elseif segment()=='capacity'then
  local held=equip('equip-bag',item.heldBag,true);local move=transfer(item.nested,item.heldBag:getItemContainer());book('tail')
  if not native then
   attempt('capacity-transfer',function()return Q.move(queue(),held,move,true)end,false)
   attempt('capacity-cancel',function()return Q.cancelOperation(queue(),held)end,false)
  end
 else error('unknown equip segment')end
end
local function request(command)
 local args={case='equip-edit',segment=segment()}
 if command=='Prepare'then args.placement=placement;args.clientPlacement=proof end
 if isClient()then sendClientCommand('EquipEditTest',command,args)
 elseif command=='Prepare'then authority=F.prepare(getPlayer(),segment(),config.mode,config.kind,placement,proof,previous,workloadEnabled);previous=nil;ids=authority.ids;raw('PREPARED',ids)
 else receipt=assert(F.verify(authority));raw('VERIFIED',receipt)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if done or module~='EquipEditTest'then return end
 if command=='Failed'then fail(args.error)
 elseif args and args.segment==segment()then if command=='Prepared'then ids=args elseif command=='Verified'then receipt=args end end
end)
local segments={}
require('QueuePreflight').onGameStart(Events,function()started=true;since=now()end)
require('QueuePreflight').onTick(Events,function()
 if not started or done then return end
 local ok,reason=pcall(function()
  local p=getPlayer();if not isIngameState()or not p or not p:getSquare()then return end
  if not ready then
   if isClient()~=(config.kind=='mp')or isClient()and(p:getOnlineID()<0 or p:getUsername()~='client1')then return end
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(not native)
   assert(PZSurvivorToolkit.Settings.actionQueue()==not native and not p:isTimedActionInstant())
   captureCallbacks()
   callbackObserver=CallbackObservation.new(PZSurvivorToolkit,config,Proof,{ISEquipWeaponAction,ISReadABook,ISInventoryTransferAction})
   tidyObserver=Quiescence.new(PZSurvivorToolkit,p,empty,Proof,Events)
   if workloadEnabled then work=require('QueueEquipWork').new(config)end
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);p:setGodMod(true);p:setGhostMode(true);p:setAutoDrink(false)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
   ready=true;since=now();emit({event='setup',cases=config.cases,segments=F.segments,queueEnabled=not native,nativeDurations=true})
  end
  if frameLast then
   local timestamp=now();local gap=timestamp-frameLast;assert(gap>=0,'native OnTick clock moved backwards')
   frameCadence.count=frameCadence.count+1;frameCadence.totalMilliseconds=frameCadence.totalMilliseconds+gap
   frameCadence.maxMilliseconds=math.max(frameCadence.maxMilliseconds,gap);frameLast=timestamp
  end
  assert(now()-since<150000,'equip edit fixture timeout '..tostring(segment())..' '..phase)
  for action,row in pairs(tracks)do if queue().current==action and action:isStarted()then row.started=true;if action:getJobDelta()>0 then row.progress=true end end end
  if phase=='prepare'then
   assert(empty());if not arrival then placement=P.choose(p);arrival=P.beginCentered(p,placement)end
   proof=P.poll(arrival);if not proof then return end
   raw('CLIENT_PLACEMENT',{case='equip-edit',segment=segment(),proof=proof});phase='prepared';request('Prepare')
  elseif phase=='prepared'and ids then
   state=F.resolve(p,ids);if not state or p:tooDarkToRead()then return end
   -- Positive scenes use only currently eligible native instances. Keep
   -- extra-component inputs in the separate protected-boundary scene.
   local ordinary={state.items.b,state.items.c}
   if segment()~='component-guard'then ordinary[#ordinary+1]=state.items.a end
   assert(toolkitEquipNativeQuiet(p,ordinary)==true,'ordinary Equip fixture inputs failed native eligibility')
   if index==1 and not work then raw('EFFECT_DIAGNOSTICS',require('QueueEquipEffectDiagnostics').observe(p,state.items.a))end
   assert(not p:isTimedActionInstant());tidyObserver.reset();state.front=book('front');phase='front';frameLast=now()
  elseif phase=='front'and tracks[state.front].progress then
   assert(queue().current==state.front and state.front:isStarted(),'front book must remain active during pending edit')
   -- AddUI is staged natively: let the normal UIManager update register the
   -- actual front-reader panel before sending a programmatic widget gesture.
   if work and not native and(index==1 or segment()=='cancel')and not work:panelReady(queue())then return end
   if index==1 and not HostPoint.poll(state.front,segment(),F.hands)then return end
   if index==1 then handPoint=HostPoint.result()end
   if index==1 and work then work:arm()end
   pendingBefore=F.snapshot(state);enqueuePending();pendingAfter=F.snapshot(state);unchanged(pendingBefore);pendingOrder=queueOrder();phase=index==1 and work and'work'or'running'
  elseif phase=='work'then
   if work:tick(queue(),state.front)then phase='running'end
  elseif phase=='running'and empty()and tidyQuiet()then
   if not F.verify(state)then return end
   quiet=quiet or now();if now()-quiet>=1000 then phase='verified';request('Verify')end
  elseif phase=='verified'and receipt then
   local client=assert(F.verify(state));assert(F.equal(client,receipt),'client/authority equip effect differs')
   local tidyProof=assert(tidyQuiet(),'P4 idle cleanup observation unavailable');assert(empty(),'native queue became active after observation')
   segments[#segments+1]={segment=segment(),ids=ids,input=state.input,clientPlacement=proof,client=client,server=receipt,
    commands=commands,edits=edits,handPoint=handPoint,workload=index==1 and work and work.result or nil,componentGuard=componentGuard or false,pendingBefore=pendingBefore,pendingAfter=pendingAfter,pendingOrder=pendingOrder,
    queueIdle=true,tidyQuiescent=true,tidyObservation=tidyProof,settleMilliseconds=now()-quiet,frameCadence=frameCadence}
   if not isClient()then previous=authority end
   index=index+1
   if not segment()then
    emit({event='case',id='equip-edit',status='passed',segments=segments,queueIdle=true,tidyQuiescent=true})
    emit({event='complete',cases=config.cases,performed=1,failed=0,skipped=0});print('[MAGAZINE_UNLOAD] COMPLETE '..JSON.encode({cases=config.cases}));done=true;return
   end
   state,authority,ids,receipt,placement,arrival,proof,quiet=nil,nil,nil,nil,nil,nil,nil,nil
   handPoint=nil;tracks,commands,edits={}, {}, {};callbackReaders={};pendingBefore,pendingAfter,pendingOrder,componentGuard=nil,nil,nil,nil;frameLast=nil;frameCadence={count=0,totalMilliseconds=0,maxMilliseconds=0};phase='prepare';since=now()
  end
 end)
 if not ok then fail(reason)end
end)
