require 'PZSurvivorToolkit/ActionQueuePanel'
require 'ISUI/ISInventoryPaneContextMenu'
require 'TimedActions/ISWringClothing'
require 'TimedActions/ISWearClothing'
local P=require 'QueueEnergyPlacement'
local F=require 'QueueWringClothing'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local native=config.mode=='native'
local callbacks={};for _,name in ipairs({'isValid','update','start','stopSound','stop','perform','complete','getDuration','new'})do callbacks[name]=ISWringClothing[name]end
local phase,index='prepare',1
local started,ready,done=false,false,false
local state,authority,previous,ids,receipt,placement,placementState,proof,quiet
local wearSetup,wearReceipt
local tracks,commands={},{}
local edits={cancelled=false,reordered=false,repeatDenied=false,untouched=true}
local function now()return getTimestampMs()end
local since=now()
local waitingSince=since;local waits={}
local function case()return config.cases[index]end
local function queue()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #queue().queue==0 and not getPlayer():hasTimedActions()end
local function raw(event,value)print('[WRING_CLOTHING] '..event..' '..JSON.encode(value))end
local function emit(v)v.suite='wring-clothing';v.actor='client1';v.kind=config.kind;v.mode=config.mode;JSON.emit(v)end
local function diagnostic(reason,force)
 if not ids or not getPlayer()or not force and(waits[phase]or now()-waitingSince<2000)then return end
 waits[phase]=true;local ok,value=pcall(F.preparedDiagnostic,getPlayer(),ids)
 raw(force and'FAILED_STATE'or'PREPARED_WAIT',{phase=phase,reason=reason,state=ok and value or tostring(value)})
end
local function fail(e)if done then return end;done=true;diagnostic(tostring(e),true);print('[QUEUE_TEST] FAIL wring-clothing '..tostring(e));emit({event='case',id=case(),status='failed',phase=phase,reason=tostring(e)})end
local function request(command)
 local args={case=case()};if command=='Prepare'then args.placement=placement;args.clientPlacement=proof end
 if isClient()then sendClientCommand('WringClothingTest',command,args);return end
 if command=='Prepare'then authority=F.prepare(getPlayer(),args.case,config.mode,placement,proof,previous);previous=nil;ids=authority.ids;raw('PREPARED',ids)
 else receipt=assert(F.verify(authority));raw('VERIFIED',receipt)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if done or module~='WringClothingTest'then return end
 if command=='Failed'then fail(args.error)
 elseif args and args.case==case()then if command=='Prepared'then ids=args elseif command=='Verified'then receipt=args elseif command=='WearBaselined'then wearReceipt=args end end
end)
local function produce(name,item)
 local emitted={};local add=ISTimedActionQueue.add
 ISTimedActionQueue.add=function(action)
  local record={name=name,type=action.Type,producer='native ISInventoryPaneContextMenu.onWringClothing',item=item:getID(),
   duration=action.maxTime,started=false,progress=false}
  if action.Type=='ISWringClothing'then
   assert(action.item==item and action.maxTime==math.ceil(item:getWetness()*5),'native wring constructor differs')
   for key,callback in pairs(callbacks)do assert(action[key]==callback and ISWringClothing[key]==callback,'native wring callback changed '..key)end
   record.constructorWetness=item:getWetness();record.callbacksUntouched=true
  else assert(action.Type=='ISInventoryTransferAction'or action.Type=='ISUnequipAction','unexpected native wring prelude '..tostring(action.Type))end
  emitted[#emitted+1]=action;commands[#commands+1]=record;tracks[action]=record
  return add(action)
 end
 local ok,error=pcall(ISInventoryPaneContextMenu.onWringClothing,{item},getPlayer():getPlayerNum())
 ISTimedActionQueue.add=add;assert(ok,error)
 local action=emitted[#emitted];assert(action and action.Type=='ISWringClothing','missing native wring action')
 local expected=1+((name=='target'and case()=='worn')and 1 or 0)+((name=='target'and(case()=='worn-bag'or case()=='world'))and 1 or 0)
 assert(#emitted==expected,'native transfer/unequip producer shape differs')
 return action
end
local function observe()
 for action,row in pairs(tracks)do
  if queue().current==action and action:isStarted()then
   if not row.started then row.started=true;row.startedAt=now()end
   if action:getJobDelta()>0 then row.progress=true end
  end
 end
end
require('QueuePreflight').onGameStart(Events,function()started=true;since=now()end)
require('QueuePreflight').onTick(Events,function()
 if not started or done then return end
 local ok,error=pcall(function()
  local p=getPlayer();if not isIngameState()or not p or not p:getSquare()then return end
  if not ready then
   if isClient()~=(config.kind=='mp')or isClient()and(p:getOnlineID()<0 or p:getUsername()~='client1')then return end
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(not native)
   assert(PZSurvivorToolkit.Settings.actionQueue()==not native and not p:isTimedActionInstant())
   local adapter=assert(PZSurvivorToolkit.ActionQueueWring,'wring adapter missing')
   local installed=adapter.install();raw('ADAPTER',{installed=installed,queueEnabled=not native})
   if not native then assert(installed,'full-pack wring callback/helper binding differs')end
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);p:setGodMod(true);p:setGhostMode(true);p:setAutoDrink(false)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
   ready=true;since=now();emit({event='setup',cases=config.cases,queueEnabled=not native,nativeDurations=true,adapterInstalled=installed})
  end
  assert(now()-since<120000,'wring fixture timeout '..phase);observe()
  if phase=='prepare'then
   assert(empty());if not placementState then placement=P.choose(p);placementState=P.beginCentered(p,placement)end
   proof=P.poll(placementState);if not proof then return end
   raw('CLIENT_PLACEMENT',{case=case(),proof=proof});phase='prepared';waitingSince=now();request('Prepare')
  elseif phase=='prepared'and ids then
   state=F.resolve(p,ids,ids.nativeWearSetup==true);if not state then diagnostic('inventory/source binding not ready');return end
   if ids.nativeWearSetup then
    assert(isClient()and(case()=='worn'or case()=='worn-bag'),'unexpected native wear setup')
    local item=case()=='worn'and state.items.target or state.bag
    local action=ISWearClothing:new(p,item)
    assert(action.item==item and action.getDuration==ISWearClothing.getDuration and action.maxTime==50,'native wear setup constructor differs')
    wearSetup={type=action.Type,producer='native ISWearClothing constructor',item=item:getID(),duration=action.maxTime,started=false,progress=false}
    tracks[action]=wearSetup;ISTimedActionQueue.add(action);phase='wear-setup';waitingSince=now();return
   end
   if case()=='world'then
    local loot=assert(getPlayerLoot(p:getPlayerNum()));loot:refreshBackpacks()
    local available=false;for _,entry in ipairs(loot.backpacks)do if entry.inventory==state.source then available=true end end
    if not available then state=nil;return end
   end
   state.input=F.snapshot(state);state.frontAction=produce('front',state.items.front);phase='front'
  elseif phase=='wear-setup'and empty()then
   if not wearSetup.started or not wearSetup.progress then diagnostic('native setup wear progress missing');return end
   state=F.resolve(p,ids)
   if not state or not F.wearBaseline(state)then diagnostic('native setup wear canonical binding not ready');return end
   phase='wear-baseline';waitingSince=now();request('WearBaseline')
  elseif phase=='wear-baseline'then
   if not wearReceipt then diagnostic('authoritative native wear baseline pending');return end
   state=assert(F.resolve(p,ids),'native wear canonical identity lost after authority baseline')
   state.input=assert(F.wearBaseline(state),'native wear input baseline changed')
   state.frontAction=produce('front',state.items.front);phase='front'
  elseif phase=='front'and tracks[state.frontAction].progress then
   local before=JSON.encode(F.snapshot(state))
   if not native and case()=='root'then
    local discard=produce('cancelled',state.items.cancelled)
    assert(PZSurvivorToolkit.ActionQueue.cancelOperation(queue(),discard),'pending independent wring cancellation denied')
    tracks[discard].cancelled=true;edits.cancelled=true
   end
   local target=produce('target',state.items.target)
   if not native and case()=='root'then
    local repeatAction=produce('repeat',state.items.target)
    local ordered={};for i,action in ipairs(queue().queue)do ordered[i]=action end
    assert(not PZSurvivorToolkit.ActionQueue.move(queue(),repeatAction,target),'same clothing cap10 dependency accepted')
    for i,action in ipairs(ordered)do assert(queue().queue[i]==action,'denied move changed queue')end
    assert(PZSurvivorToolkit.ActionQueue.cancelOperation(queue(),repeatAction),'pending duplicate cleanup denied')
    tracks[repeatAction].cancelled=true;edits.repeatDenied=true
   end
   local tail=produce('tail',state.items.tail)
   if not native and case()=='root'then
    assert(PZSurvivorToolkit.ActionQueue.move(queue(),target,tail,true),'distinct garment reorder denied')
    assert(queue().queue[#queue().queue]==target,'distinct garment move did not commit')
    assert(PZSurvivorToolkit.ActionQueue.move(queue(),target,tail),'distinct garment return denied')
    assert(queue().queue[#queue().queue]==tail,'distinct garment return did not commit');edits.reordered=true
   end
   edits.untouched=before==JSON.encode(F.snapshot(state));assert(edits.untouched,'pending edits changed physical clothing state');phase='running'
  elseif phase=='running'and empty()then
   if not F.verify(state)then quiet=nil;return end
   quiet=quiet or now();if now()-quiet>=1000 then phase='verified';request('Verify')end
  elseif phase=='verified'and receipt then
   local client=assert(F.verify(state))
   for _,row in ipairs(commands)do
    if row.type=='ISWringClothing'then assert(row.cancelled and not row.started and not row.progress or not row.cancelled and row.started and row.progress,'native wring progress/cancellation evidence missing')end
   end
   local row={event='case',id=case(),status='passed',ids=ids,clientPlacement=proof,input=state.input,client=client,server=receipt,
    commands=commands,edit=edits,queueIdle=true,settleMilliseconds=now()-quiet}
   if ids.nativeWearSetup then row.wearSetup=wearSetup;row.authorityBaseline=wearReceipt end
   emit(row)
   if not isClient()then previous=authority end
   index=index+1
   if not case()then emit({event='complete',cases=config.cases,performed=index-1,failed=0,skipped=0});raw('COMPLETE',{cases=config.cases});done=true;return end
   state,authority,ids,receipt,placement,placementState,proof,quiet=nil,nil,nil,nil,nil,nil,nil,nil
   wearSetup,wearReceipt=nil,nil;waits={};waitingSince=now()
   tracks,commands={},{};edits={cancelled=false,reordered=false,repeatDenied=false,untouched=true};phase='prepare';since=now()
  end
 end)
 if not ok then fail(error)end
end)
