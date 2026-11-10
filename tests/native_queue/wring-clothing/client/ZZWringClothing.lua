require 'PZSurvivorToolkit/ActionQueuePanel'
require 'ISUI/ISInventoryPaneContextMenu'
require 'TimedActions/ISWringClothing'
require 'TimedActions/ISWearClothing'
local P=require 'QueueEnergyPlacement'
local F=require 'QueueWringClothing'
local Ops=require 'PZSurvivorToolkit/ActionQueueOperations'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local native=config.mode=='native'
local callbacks={};for _,name in ipairs({'isValid','update','start','stopSound','stop','perform','complete','getDuration','new'})do callbacks[name]=ISWringClothing[name]end
local phase,index='prepare',1
local started,ready,done=false,false,false
local state,authority,previous,ids,receipt,placement,placementState,proof,quiet
local wearSetup,wearReceipt
local tracks,commands,groups,tokens,returns,returnTracks={}, {}, {}, {}, {}, {}
local preparedEvidence
local prepCallbacks={}
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
local function token(action)
 local value=assert(action.toolkitQueueOperation,'native producer operation missing')
 if not tokens[value]then local count=0;for _ in pairs(tokens)do count=count+1 end;tokens[value]=count+1 end
 return tokens[value]
end
local function order()
 local result={};for _,action in ipairs(queue().queue)do result[#result+1]=assert(tracks[action],'untracked native queue member').actionRef end;return result
end
local function bounds(member)
 local first,last=Ops.bounds(queue(),member);assert(first and last,'native producer bounds missing');return{first=first,last=last}
end
local function describe(name)
 local list=assert(groups[name]);local count=native and 2 or 3
 local fetch,body=list[count-1],list[count];local prep=not native and list[1]or nil
 assert(#list==count and fetch.Type=='ISInventoryTransferAction'and body.Type=='ISWringClothing'
  and(not prep or prep.Type=='ISQueueActionsAction'and PZSurvivorToolkit.ActionQueueApproach.isContainer(prep,state.source,getPlayer())),'carried native producer differs')
 local operation=token(list[1])
 for _,member in ipairs(list)do
  assert(not member.action and not member.started,'carried group already allocated/admitted')
  assert(token(member)==operation and member.toolkitQueueOperation~=state.frontAction.toolkitQueueOperation,'native preparation/fetch/body token differs')
 end
 local span=bounds(list[1]);assert(span.last==span.first+count-1,'native carried group bounds differ')
 for index,member in ipairs(list)do assert(queue().queue[span.first+index-1]==member,'native carried group order changed')end
 local result={token=operation,fetch=tracks[fetch].actionRef,body=tracks[body].actionRef,bounds=span,item=body.item:getID(),unallocated=true}
 if prep then result.prep=tracks[prep].actionRef end
 if not native then
  local fetchContract,fetchSource=PZSurvivorToolkit.ActionQueueDefinitions.inspect(fetch)
  local bodyContract,bodySource=PZSurvivorToolkit.ActionQueueDefinitions.inspect(body)
  assert(fetchContract and fetchContract.edit and bodyContract and bodyContract.edit,'carried native descriptors missing')
  local resource=assert(bodyContract.edit.resources[1]);local needRoot=false
  for _,predicate in ipairs(resource.requires)do if predicate.field=='location'and predicate.equal==getPlayer():getInventory()then needRoot=true end end
  local transfer=assert(fetchContract.edit.resources[1]);local setsRoot=false
  for _,effect in ipairs(transfer.effects)do if effect.field=='location'and effect.set==getPlayer():getInventory()then setsRoot=true end end
  assert(resource.domain=='item'and resource.key==result.item and resource.facts.item==body.item and resource.facts.location==state.source and needRoot
   and transfer.key==result.item and transfer.facts.location==state.source and setsRoot,'source/root native descriptor binding differs')
  local prepContract,prepSource=PZSurvivorToolkit.ActionQueueDefinitions.inspect(prep)
  assert(prepContract and prepSource=='toolkit.approach'and prepContract.deferred and prepContract.preparation,'owned captured container preparation missing')
  local factory=PZSurvivorToolkit.ActionQueueApproach.prepareCarriedContainerEditLease
  assert(type(factory)=='function'and Proof.closure(factory,'ActionQueueApproach.lua'),'carried-container lease source missing')
  local check,prepEdit,ownerKeys=factory(prep,state.source)
  assert(type(check)=='function'and prepEdit and prepEdit.version==1 and prepEdit.complete==true and prepEdit.capacity=='unchanged'
   and #prepEdit.resources==1 and ownerKeys[state.bag:getID()]==true,'carried-container no-movement lease missing')
  local owner=prepEdit.resources[1];local owners=0;for key,value in pairs(ownerKeys)do assert(key==state.bag:getID()and value==true);owners=owners+1 end
  assert(owners==1 and owner.domain=='item'and owner.key==state.bag:getID()and owner.facts.item==state.bag
   and owner.facts.location==getPlayer():getInventory()and #owner.requires==1 and owner.requires[1].field=='location'
   and owner.requires[1].equal==getPlayer():getInventory()and #owner.effects==0,'carried-container owner/root/empty effects differ')
  local projection=PZSurvivorToolkit.ActionQueueEditModel.evaluate({{action=prep,edit=prepEdit},{action=fetch,edit=fetchContract.edit},{action=body,edit=bodyContract.edit}})
  assert(projection.status=='allowed'and check()==true,'valid native preparation/fetch/body fresh descriptor order denied')
  result.descriptor={fetchSource=fetchSource,bodySource=bodySource,item=result.item,actual='bag',requires='root',fetchSets='root',
   sourceBag=state.bag:getID(),canonical=true,prepSource=prepSource,prepOwned=true,prepLease={capacity=prepEdit.capacity,owner=owner.key,ownerRoot=true,effectsEmpty=true,fresh=true},bodyCapacity=bodyContract.edit.capacity,fetchCapacity=fetchContract.edit.capacity,projection=projection.status}
 end
 return result
end
local function prepEvent(action,row,boundary,phase,succeeded)
 local methods=assert(prepCallbacks[action])
 for name,callback in pairs(methods)do if action[name]~=callback then row.preparation.callbacksUntouched=false end end
 local unexpected={}
 for _,member in ipairs(queue().queue)do if not tracks[member]then unexpected[#unexpected+1]={type=member.Type,actionRef=tostring(member)}end end
 local player=getPlayer()
 local event={boundary=boundary,phase=phase,succeeded=succeeded==true,nativeRef=action.action and tostring(action.action)or false,
  nativeClass=action.action and getClassSimpleName(action.action)or false,ownedContainer=PZSurvivorToolkit.ActionQueueApproach.isContainer(action,state.source,player)==true,
  position={x=player:getX(),y=player:getY(),z=player:getZ()},unexpectedChildren=unexpected,
  expansionClosed=action._isAddingActions==nil and action._numAddedActions==nil}
 row.resolver=row.resolver or{};row.resolver[#row.resolver+1]=event
end
assert(PZSurvivorToolkit.ActionQueueLifecycle.registerObserver('prepared-carried-wring-return',{
 started=function(action)
  local tracked=tracks[action]
  if tracked and tracked.preparation then tracked.admitted=true end
  if not ids or not state or not ids.preparedGroups or action.Type~='ISInventoryTransferAction'or action.srcContainer~=getPlayer():getInventory()or action.destContainer~=state.source then return end
  local members=F.returnMembers(action,{})
  local row={actionRef=tostring(action),type=action.Type,from='root',toBag=ids.source.bag,duration=action.maxTime,allowMissing=action.allowMissingItems==true,items=members,events={}}
  returns[#returns+1]=row;returnTracks[action]=row
 end,
 begin=function(action,phase)
  local tracked=tracks[action]
  if tracked and tracked.preparation then prepEvent(action,tracked,'begin',phase,false);return true end
  local row=returnTracks[action];if not row then return end
  F.returnMembers(action,row.items)
  row.events[#row.events+1]={boundary='begin',phase=phase,nativeRef=action.action and tostring(action.action)or false};return true
 end,
 finish=function(action,phase,succeeded)
  local tracked=tracks[action]
  if tracked and tracked.preparation and(phase=='perform'or phase=='complete')then prepEvent(action,tracked,'finish',phase,succeeded);return end
  local row=returnTracks[action];if row then row.events[#row.events+1]={boundary='finish',phase=phase,succeeded=succeeded==true,nativeRef=action.action and tostring(action.action)or false}end
 end}))
local function produce(name,item)
 local emitted={};local add=ISTimedActionQueue.add
 ISTimedActionQueue.add=function(action)
  local record={name=name,type=action.Type,producer='native ISInventoryPaneContextMenu.onWringClothing',item=item:getID(),
   duration=action.maxTime,started=false,progress=false}
  if action.Type=='ISWringClothing'then
   assert(action.item==item and action.maxTime==math.ceil(item:getWetness()*5),'native wring constructor differs')
   for key,callback in pairs(callbacks)do assert(action[key]==callback and ISWringClothing[key]==callback,'native wring callback changed '..key)end
   record.constructorWetness=item:getWetness();record.callbacksUntouched=true
  elseif action.Type=='ISQueueActionsAction'then
   assert(not native and case()=='worn-bag'and(name=='target'or name=='cancelled')and action.maxTime==-1
    and PZSurvivorToolkit.ActionQueueApproach.isContainer(action,state.source,getPlayer()),'unexpected/unowned native container preparation')
   assert(Proof.closure(action.start,'ActionQueueOperations.lua')and Proof.closure(action.waitToStart,'ActionQueueOperations.lua')
    and Proof.closure(action.addActionsFunction,'ActionQueueApproach.lua'),'owned native container resolver changed')
   record.preparation={container=ids.source.bag,owned=true,callbacksUntouched=true};record.admitted=false
   prepCallbacks[action]={};for _,key in ipairs({'start','waitToStart','addActionsFunction','isValid','update','perform','stop','new'})do prepCallbacks[action][key]=action[key]end
  else assert(action.Type=='ISInventoryTransferAction'or action.Type=='ISUnequipAction','unexpected native wring prelude '..tostring(action.Type))end
  emitted[#emitted+1]=action;commands[#commands+1]=record;tracks[action]=record
  return add(action)
 end
 local ok,error=pcall(function()
  if case()=='worn-bag'then return Ops.run(ISInventoryPaneContextMenu.onWringClothing,{item},getPlayer():getPlayerNum())end
  return ISInventoryPaneContextMenu.onWringClothing({item},getPlayer():getPlayerNum())
 end)
 ISTimedActionQueue.add=add;assert(ok,error)
 local action=emitted[#emitted];assert(action and action.Type=='ISWringClothing','missing native wring action')
 local expected=1+((name=='target'and case()=='worn')and 1 or 0)+(((name=='target'or name=='cancelled')and case()=='worn-bag'or name=='target'and case()=='world')and 1 or 0)
 if not native and case()=='worn-bag'and(name=='target'or name=='cancelled')then expected=expected+1 end
 assert(#emitted==expected,'native transfer/unequip producer shape differs')
 if case()=='worn-bag'then
  groups[name]=emitted
  for _,member in ipairs(emitted)do local row=tracks[member];row.actionRef=tostring(member);row.operation=token(member)end
 end
 return action
end
local function observe()
 for action,row in pairs(tracks)do
  if queue().current==action and action:isStarted()then
   if not row.started then
    row.started=true;row.startedAt=now()
    if ids and ids.preparedGroups and action.Type=='ISWringClothing'then row.rootAtStart=F.snapshot(state).items[row.name]end
   end
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
   if case()=='worn-bag'then produce('cancelled',state.items.cancelled)end
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
   if case()=='worn-bag'then
    local discarded=describe('cancelled');local kept=describe('target')
    preparedEvidence={sourceBag=ids.source.bag,front=tracks[state.frontAction].actionRef,frontNative=tostring(state.frontAction.action),
     initialOrder=order(),cancelled=discarded,target=kept,moves={},returns=returns,before=F.snapshot(state)}
    if not native then
     assert(PZSurvivorToolkit.ActionQueue.cancelOperation(queue(),groups.cancelled[#groups.cancelled]),'pending carried wring group cancellation denied')
     for _,member in ipairs(groups.cancelled)do assert(queue():indexOf(member)==-1,'cancelled carried child survived');tracks[member].cancelled=true end
     discarded.selected=discarded.body;discarded.accepted=true;discarded.afterOrder=order();edits.cancelled=true
     for _,move in ipairs({{selected=groups.target[#groups.target-1],after=true},{selected=groups.target[#groups.target],after=false}})do
      assert(PZSurvivorToolkit.ActionQueue.move(queue(),move.selected,tail,move.after),'carried wring whole group move denied')
      local keptNow=describe('target');assert(keptNow.token==kept.token,'carried move changed operation token')
      preparedEvidence.moves[#preparedEvidence.moves+1]={selected=tracks[move.selected].actionRef,after=move.after,accepted=true,order=order(),bounds=keptNow.bounds}
     end
     edits.reordered=true
    end
    preparedEvidence.finalOrder=order();preparedEvidence.after=F.snapshot(state)
    assert(queue().current==state.frontAction and tostring(state.frontAction.action)==preparedEvidence.frontNative,'pending edits changed active native front')
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
   if ids.preparedGroups then row.prepared=preparedEvidence end
   emit(row)
   if not isClient()then previous=authority end
   index=index+1
   if not case()then emit({event='complete',cases=config.cases,performed=index-1,failed=0,skipped=0});raw('COMPLETE',{cases=config.cases});done=true;return end
   state,authority,ids,receipt,placement,placementState,proof,quiet=nil,nil,nil,nil,nil,nil,nil,nil
   wearSetup,wearReceipt=nil,nil;waits={};waitingSince=now()
   tracks,commands,groups,tokens,returns,returnTracks={}, {}, {}, {}, {}, {};preparedEvidence=nil;prepCallbacks={};edits={cancelled=false,reordered=false,repeatDenied=false,untouched=true};phase='prepare';since=now()
  end
 end)
 if not ok then fail(error)end
end)
