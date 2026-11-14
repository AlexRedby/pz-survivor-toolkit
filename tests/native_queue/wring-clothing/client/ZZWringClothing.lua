require 'PZSurvivorToolkit/ActionQueuePanel'
require 'ISUI/ISInventoryPaneContextMenu'
require 'TimedActions/ISWringClothing'
require 'TimedActions/ISWearClothing'
local P=require 'QueueEnergyPlacement'
local F=require 'QueueWringClothing'
local profile={module=require 'QueueWringCapacityProfile',scenario=require 'QueueWringScenario',diagnostics=require 'QueueWringDiagnostics'}
local Ops=require 'PZSurvivorToolkit/ActionQueueOperations'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Witness=require 'QueueWringWitnessDiagnostics'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local native=config.mode=='native'
profile.restoration=config.options and config.options.wring_restoration_provider=='native-returns'
local callbacks={};for _,name in ipairs({'isValid','update','start','stopSound','stop','perform','complete','getDuration','new'})do callbacks[name]=ISWringClothing[name]end
local phase,index='prepare',1
local started,ready,done=false,false,false
local state,authority,previous,ids,receipt,placement,placementState,proof,quiet
local wearSetup,wearReceipt,wearIndex
local unequipCallbacks={}
local wearCallbacks={}
local wornEvidence,swapEvidence,swapAction,swapTail
local function nativeWear(action)
 for _,key in ipairs({'new','isValid','start','update','perform','complete','getDuration'})do assert(action[key]==wearCallbacks[key]and ISWearClothing[key]==wearCallbacks[key]and Proof.closure(action[key],'ISWearClothing.lua'),'native wear callback source changed '..key)end
end
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
Witness.configure(function(value)raw('HOST_WITNESS',value)end,function()return case(),phase end)
assert(PZSurvivorToolkit.ActionQueueLifecycle.registerObserver('wring-host-witness-diagnostics',{started=function(action)Witness.started(action,tracks[action]~=nil)end,begin=Witness.begin,finish=Witness.finish}))
function profile.sample(point)
 if not profile.restoration then return end
 assert(P4TidyUpMeister==nil and not getActivatedMods():contains('P4TidyUpMeister'),'P4 loaded or selected')
 assert(PZSurvivorToolkit.ActionQueueSettlement==profile.loanModule and profile.loanModule.operationState==profile.loanReader,'settlement observer changed')
 local body=groups.target and groups.target[#groups.target];local view=body and profile.loanReader(body);local loans=view and view.borrowings or{}
 profile.observation={case=case(),point=point,observedAt=now(),ledger=view or false,debts=false}
 local found=nil;for _,value in ipairs(loans)do if value.id==ids.items.target.id and value.fullType==ids.items.target.type then assert(not found,'duplicate garment loan');found=value end end
 local observed,planned=false,0
 for _,step in ipairs(view and view.steps or{})do
  if step.itemId==ids.items.target.id and step.itemType==ids.items.target.type and step.phase=='prepare' and step.observedPreparation then observed=true end
  if step.plannedTransfer then planned=planned+1 end
 end
 local sample={case=case(),point=point,loaded=false,selected=false,itemId=ids.items.target.id,itemType=ids.items.target.type,state=found and found.state or false,candidates=#loans,observedPreparation=observed}
 sample.plannedTransfers=planned
 if point=='body'then
  sample.returnRef=false;sample.bodyIndex=false;sample.returnIndex=false;sample.tailIndex=false
  for index,action in ipairs(queue().queue)do
   if action==body then sample.bodyIndex=index end
   if action==state.tailAction then sample.tailIndex=index end
   if action.Type=='ISInventoryTransferAction'and action.srcContainer==getPlayer():getInventory()and action.destContainer==state.source then
    local members=F.returnMembers(action,{})
    if #members==1 and members[1].id==ids.items.target.id and members[1].type==ids.items.target.type then
     assert(not sample.returnRef,'duplicate generated garment return');sample.returnRef=tostring(action);sample.returnIndex=index
    end
   end
  end
 end
 profile.restorationEvidence.samples[#profile.restorationEvidence.samples+1]=sample;raw('RESTORATION',sample)
end
local function diagnostic(reason,force)
 if not ids or not getPlayer()or not force and(waits[phase]or now()-waitingSince<2000)then return end
 waits[phase]=true
 local body=groups.target and groups.target[#groups.target]
 raw(force and'FAILED_STATE'or'PREPARED_WAIT',{phase=phase,reason=reason,
  state=profile.diagnostics.capture(getPlayer(),ids,state,queue(),body,state and state.tailAction,profile.observation)})
end
local function fail(e)if done then return end;done=true;diagnostic(tostring(e),true);print('[QUEUE_TEST] FAIL wring-clothing '..tostring(e));emit({event='case',id=case(),status='failed',phase=phase,reason=tostring(e)})end
local function request(command)
 local args={case=case()};if command=='Prepare'then args.placement=placement;args.clientPlacement=proof end
 if isClient()then sendClientCommand('WringClothingTest',command,args);return end
 if command=='Prepare'then authority=F.prepare(getPlayer(),args.case,config.mode,placement,proof,previous,config.options and config.options.profile_capacity,config.options and config.options.wring_restoration_provider=='native-returns');previous=nil;ids=authority.ids;raw('PREPARED',ids)
 elseif command=='ProfileCleanup'then
  assert(authority and authority.ids.capacityProfile,'unexpected profile cleanup');F.dispose(authority);profile.cleanupReceipt=profile.module.cleanupProof(authority);raw('PROFILE_CLEANED',profile.cleanupReceipt);authority=nil;previous=nil
 elseif command=='WearBaseline'then wearReceipt=assert(F.wearBaseline(authority));raw('WEAR_BASELINE',wearReceipt)
 else receipt=assert(F.verify(authority));raw('VERIFIED',receipt)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if done or module~='WringClothingTest'then return end
 if command=='Failed'then fail(args.error)
 elseif args and args.case==case()then if command=='Prepared'then ids=args elseif command=='Verified'then receipt=args elseif command=='WearBaselined'then wearReceipt=args elseif command=='ProfileCleaned'then profile.cleanupReceipt=args end end
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
local function describeWorn(name)
 local list=assert(groups[name]);local unequip,body=list[1],list[2]
 assert(#list==2 and unequip.Type=='ISUnequipAction'and body.Type=='ISWringClothing'and unequip.item==body.item,'worn native producer differs')
 local operation=token(unequip);local span=bounds(unequip)
 assert(span.last==span.first+1 and queue().queue[span.first]==unequip and queue().queue[span.last]==body,'worn operation bounds/order differ')
 for _,member in ipairs(list)do assert(not member.action and not member.started and token(member)==operation and member.toolkitQueueOperation~=state.frontAction.toolkitQueueOperation,'worn group allocated/token differs')end
 local result={token=operation,unequip=tracks[unequip].actionRef,body=tracks[body].actionRef,bounds=span,item=body.item:getID(),unallocated=true}
 if not native then
  local before,source=PZSurvivorToolkit.ActionQueueDefinitions.inspect(unequip)
  local after,bodySource=PZSurvivorToolkit.ActionQueueDefinitions.inspect(body)
  assert(before and before.edit and before.hands==getPlayer()and before.preparation==true and before.cancelWaiting==false and before.moveRequiresProjection==true
   and before.clothingRemoval==true and before.edit.version==1 and before.edit.complete==true and before.edit.capacity=='external'
   and #before.edit.resources==1 and after and after.edit,'worn native descriptors missing')
  local resource=assert(before.edit.resources[1]);local effect=false;local root=false;local worn=false
  for _,predicate in ipairs(resource.requires)do
   if predicate.field=='location'and predicate.equal==getPlayer():getInventory()then root=true end
   if predicate.field=='worn'and predicate.equal==true then worn=true end
  end
  for _,value in ipairs(resource.effects)do if value.field=='worn'and value.set==false then effect=true end end
  assert(resource.domain=='item'and resource.key==result.item and resource.facts.item==body.item and resource.facts.location==getPlayer():getInventory()
   and resource.facts.worn==true and #resource.requires==2 and #resource.effects==1 and root and worn and effect,'worn native root/slot descriptor differs')
  local projection=PZSurvivorToolkit.ActionQueueEditModel.evaluate({{action=unequip,edit=before.edit},{action=body,edit=after.edit}})
  assert(projection.status=='allowed','native unequip/body projection denied')
  result.descriptor={unequipSource=source,bodySource=bodySource,item=result.item,actual='root',worn=true,slot=tostring(body.item:getBodyLocation()),
   setsWorn=false,capacity=before.edit.capacity,bodyCapacity=after.edit.capacity,equipmentWriter=true,cancelWaiting=false,moveRequiresProjection=true,projection=projection.status,canonical=true}
 end
 return result
end
local function wornEvent(action,row,boundary,phase,succeeded)
 if action.Type=='ISWearClothing'then nativeWear(action)
 elseif action.Type=='ISUnequipAction'then for key,callback in pairs(unequipCallbacks)do assert(action[key]==callback and ISUnequipAction[key]==callback,'qualified unequip callback drift')end
 elseif action.Type=='ISWringClothing'then for key,callback in pairs(callbacks)do assert(action[key]==callback and ISWringClothing[key]==callback,'native wring callback drift')end end
 row.events=row.events or{};row.events[#row.events+1]={boundary=boundary,phase=phase,succeeded=succeeded==true,
  nativeRef=action.action and tostring(action.action)or false,nativeClass=action.action and getClassSimpleName(action.action)or false,
  state=F.unequipSnapshot(state,row.name)}
end
Events.OnClothingUpdated.Add(function(player)
 if not state or not ids or not F.observesClothing(ids) or player~=getPlayer()then return end
 local ok,error=pcall(F.clothingTransition,state);if not ok then fail(error)end
 -- SP authority and client share canonical items but keep independent observations.
 if authority and authority~=state then local good,reason=pcall(F.clothingTransition,authority);if not good then fail(reason)end end
end)
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
  if profile.restoration and tracked and tracked.name=='target' and action.Type=='ISWringClothing' then profile.sample('body') end
  if tracked and tracked.preparation then tracked.admitted=true end
  if tracked and tracked.name and ids and F.observesClothing(ids)and(tracked.type=='ISUnequipAction'or tracked.type=='ISWringClothing')then tracked.admission=F.unequipSnapshot(state,tracked.name)end
  if not ids or not state or not ids.preparedGroups or action.Type~='ISInventoryTransferAction'or action.srcContainer~=getPlayer():getInventory()or action.destContainer~=state.source then return end
  local members=F.returnMembers(action,{})
  local row={actionRef=tostring(action),type=action.Type,from='root',toBag=ids.source.bag,duration=action.maxTime,allowMissing=action.allowMissingItems==true,items=members,events={}}
  if profile.restoration then row.bodySettled=profile.bodySettled==true end
  returns[#returns+1]=row;returnTracks[action]=row
 end,
 begin=function(action,phase)
  local tracked=tracks[action]
  if tracked and tracked.name and ids and F.observesClothing(ids)and(phase=='perform'or phase=='complete')then wornEvent(action,tracked,'begin',phase,false);return true end
  if tracked and tracked.preparation then prepEvent(action,tracked,'begin',phase,false);return true end
  local row=returnTracks[action];if not row then return end
  F.returnMembers(action,row.items)
  row.events[#row.events+1]={boundary='begin',phase=phase,nativeRef=action.action and tostring(action.action)or false};return true
 end,
 settled=function(action)
  if profile.restoration and groups.target and action==groups.target[#groups.target]then profile.bodySettled=true end
 end,
 finish=function(action,phase,succeeded)
  local tracked=tracks[action]
  if tracked and tracked.name and ids and F.observesClothing(ids)and(phase=='perform'or phase=='complete')then wornEvent(action,tracked,'finish',phase,succeeded);return end
  if tracked and tracked.preparation and(phase=='perform'or phase=='complete')then prepEvent(action,tracked,'finish',phase,succeeded);return end
  local row=returnTracks[action];if row then row.events[#row.events+1]={boundary='finish',phase=phase,succeeded=succeeded==true,nativeRef=action.action and tostring(action.action)or false}end
 end}))
local function produce(name,item)
 local emitted={};local add=ISTimedActionQueue.add
 ISTimedActionQueue.add=function(action)
  Witness.before(action,true)
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
  elseif action.Type=='ISUnequipAction'and F.observesClothing(ids)then
   local carts=assert(PZSurvivorToolkit.ActionQueueCarts)
   assert(action.item==item and action.maxTime==50 and carts.isUnequipConstructor(ISUnequipAction.new)and carts.isNonCartUnequip(action)and carts.equipmentSafe(getPlayer()),'native/Carts unequip binding differs')
   for key,callback in pairs(unequipCallbacks)do assert(action[key]==callback and ISUnequipAction[key]==callback,'qualified unequip callback changed '..key)end
   record.callbacksUntouched=true;record.cartsGuard=true
  else assert(action.Type=='ISInventoryTransferAction'or action.Type=='ISUnequipAction','unexpected native wring prelude '..tostring(action.Type))end
  emitted[#emitted+1]=action;commands[#commands+1]=record;tracks[action]=record
  return add(action)
 end
 local ok,error=pcall(function()
  if case()=='worn-bag'or F.observesClothing(ids)then return Ops.run(ISInventoryPaneContextMenu.onWringClothing,{item},getPlayer():getPlayerNum())end
  return ISInventoryPaneContextMenu.onWringClothing({item},getPlayer():getPlayerNum())
 end)
 ISTimedActionQueue.add=add;assert(ok,error)
 local action=emitted[#emitted];assert(action and action.Type=='ISWringClothing','missing native wring action')
 if case()=='worn-bag'then profile.scenario.checkProducer(emitted,config.mode,name)
 else
  local expected=1+((name=='target'and case()=='worn'or(case()=='worn-prepared'and(name=='target'or name=='cancelled')or ids.wearSwap and name=='target'))and 1 or 0)+(name=='target'and case()=='world'and 1 or 0)
  assert(#emitted==expected,'native transfer/unequip producer shape differs')
 end
 if case()=='worn-bag'or F.observesClothing(ids)then
  groups[name]=emitted
  for _,member in ipairs(emitted)do local row=tracks[member];row.actionRef=tostring(member);row.operation=token(member)end
 end
 return action
end
local function swapWear()
 local add=ISTimedActionQueue.add;local action
 ISTimedActionQueue.add=function(value)
  assert(not action and value.Type=='ISWearClothing'and value.item==state.items.incoming and value.maxTime==50,'native swap producer topology differs')
  nativeWear(value);action=value
  local row={name='incoming',type=value.Type,producer='native ISInventoryPaneContextMenu.onWearItems',item=value.item:getID(),duration=value.maxTime,
   callbacksUntouched=true,started=false,progress=false,actionRef=tostring(value)}
  tracks[value]=row;swapEvidence.wear=row
  return add(value)
 end
 local ok,error=pcall(ISInventoryPaneContextMenu.onWearItems,{state.items.incoming},getPlayer():getPlayerNum())
 ISTimedActionQueue.add=add;assert(ok,error);assert(action,'native swap Wear missing');return action
end
local function swapPermission()
 assert(queue().current==state.frontAction and state.frontAction.action and tracks[state.frontAction].progress,'Wear freshness did not converge during natural front')
 local current=order();local before=F.snapshot(state)
 local fresh,reason=PZSurvivorToolkit.ActionQueueClothing.capacityFresh(queue())
 local physical=F.swapPhysical(state)
 assert(type(fresh)=='boolean','native Wear freshness result differs')
 if fresh then assert(physical,'Wear capacity declared fresh before exact physical swap')end
 local signature=tostring(fresh)..':'..tostring(reason)..':'..tostring(physical)
 if not fresh then
  if swapEvidence.lastRefusal~=signature then
   local accepted=false
   if not native then accepted=PZSurvivorToolkit.ActionQueue.move(queue(),groups.target[1],swapTail,true);assert(not accepted,'unfresh Wear allowed retained Unequip capacity edit')end
   assert(JSON.encode(current)==JSON.encode(order())and JSON.encode(before)==JSON.encode(F.snapshot(state)),'unfresh Wear refusal mutated native queue/clothing')
   swapEvidence.attempts[#swapEvidence.attempts+1]={fresh=false,reason=type(reason)=='string'and reason or false,physical=physical,accepted=accepted,attempted=not native,beforeOrder=current,afterOrder=order(),before=before,after=F.snapshot(state)}
   swapEvidence.lastRefusal=signature
  end
  diagnostic('native Wear freshness pending: '..tostring(reason));return false
 end
 swapEvidence.permission={fresh=true,reason=type(reason)=='string'and reason or false,physical=true,before=before,after=false}
 swapEvidence.ack=Witness.receipt(swapAction)
 if isClient()then local ack=swapEvidence.ack;assert(ack.capturePresent and ack.ackState=='completed'and ack.nativeSame and ack.itemSame and ack.actorSame and ack.rootSame and ack.queueSame and ack.canonicalRoot and ack.rootOwned and ack.worn and ack.slotSame and ack.slotId==ids.items.incoming.id,'fresh Wear permission lacks exact real terminal Ack')end
 swapEvidence.initialOrder=current;swapEvidence.target=describeWorn('target');swapEvidence.front=tracks[state.frontAction].actionRef;swapEvidence.frontNative=tostring(state.frontAction.action)
 if not native then
  for _,move in ipairs({{selected=groups.target[1],after=true},{selected=groups.target[2],after=false}})do
   assert(PZSurvivorToolkit.ActionQueue.move(queue(),move.selected,swapTail,move.after),'fresh Wear retained whole-group move denied')
   local described=describeWorn('target');assert(described.token==swapEvidence.target.token,'Wear retained move changed group token')
   swapEvidence.moves[#swapEvidence.moves+1]={selected=tracks[move.selected].actionRef,after=move.after,accepted=true,order=order(),bounds=described.bounds}
  end
  edits.reordered=true
 end
 swapEvidence.permission.after=F.snapshot(state);swapEvidence.finalOrder=order()
 assert(JSON.encode(before)==JSON.encode(swapEvidence.permission.after),'fresh Wear pending edits changed physical clothing')
 assert(queue().current==state.frontAction and tostring(state.frontAction.action)==swapEvidence.frontNative,'Wear retained move changed native front')
 return true
end
function profile.run()
 if not ids.capacityProfile then return end
 local function unchanged()
  for name,callback in pairs(callbacks)do assert(ISWringClothing[name]==callback,'profile native wring callback changed')end
  assert(profile.setupActions and profile.setupActions[1],'profile native bag wear missing');nativeWear(profile.setupActions[1])
 end
 unchanged();profile.evidence=profile.module.measure(state,queue(),function()return F.snapshot(state)end);unchanged()
 profile.evidence.callbacksUntouched=true;raw('CAPACITY_PROFILE',profile.evidence)
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
   for _,key in ipairs({'new','isValid','update','start','stop','perform','complete','animEvent'})do unequipCallbacks[key]=ISUnequipAction[key]end
   for _,key in ipairs({'new','isValid','start','update','perform','complete','getDuration'})do wearCallbacks[key]=ISWearClothing[key]end
   getCore():setOptionPauseOnFocusloss(false);getCore():setOptionAutoDrink(false);p:setGodMod(true);p:setGhostMode(true);p:setAutoDrink(false)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
   if profile.restoration then
    assert(P4TidyUpMeister==nil and not getActivatedMods():contains('P4TidyUpMeister'),'P4 loaded or selected')
    profile.loanModule=assert(PZSurvivorToolkit.ActionQueueSettlement);profile.loanReader=assert(profile.loanModule.operationState)
    profile.restorationEvidence={provider='native-returns',samples={}}
   end
   ready=true;since=now();Witness.setup();emit({event='setup',cases=config.cases,queueEnabled=not native,nativeDurations=true,adapterInstalled=installed})
  end
  assert(now()-since<120000,'wring fixture timeout '..phase);observe();Witness.poll()
  if phase=='prepare'then
   assert(empty());if not placementState then placement=P.choose(p);placementState=P.beginCentered(p,placement)end
   proof=P.poll(placementState);if not proof then return end
   raw('CLIENT_PLACEMENT',{case=case(),proof=proof});phase='prepared';waitingSince=now();request('Prepare')
  elseif phase=='prepared'and ids then
   state=F.resolve(p,ids,ids.nativeWearSetup==true);if not state then diagnostic('inventory/source binding not ready');return end
   if ids.nativeWearSetup then
    if F.observesClothing(ids)and not F.equipmentMatches(p,ids.initialEquipment)then diagnostic('previous native equipment cleanup has not reached authority baseline');return end
    assert(F.observesClothing(ids)or ids.capacityProfile or isClient()and(case()=='worn'or case()=='worn-bag'),'unexpected native wear setup')
    wearIndex=1;profile.setupActions={}
    local item=F.observesClothing(ids)and state.items.target or case()=='worn'and state.items.target or state.bag
    local action=ISWearClothing:new(p,item)
    assert(action.item==item and action.getDuration==ISWearClothing.getDuration and action.maxTime==50,'native wear setup constructor differs')
    if F.observesClothing(ids)then nativeWear(action)end
    wearSetup={type=action.Type,producer='native ISWearClothing constructor',item=item:getID(),duration=action.maxTime,started=false,progress=false}
    if F.observesClothing(ids)then wearSetup.name='target';wearSetup.callbacksUntouched=true end
    if F.observesClothing(ids)then wearSetup={wearSetup};tracks[action]=wearSetup[1]else tracks[action]=wearSetup end;profile.setupActions[1]=action;ISTimedActionQueue.add(action);phase='wear-setup';waitingSince=now();return
   end
   if case()=='world'then
    local loot=assert(getPlayerLoot(p:getPlayerNum()));loot:refreshBackpacks()
    local available=false;for _,entry in ipairs(loot.backpacks)do if entry.inventory==state.source then available=true end end
    if not available then state=nil;return end
   end
   state.input=F.snapshot(state);state.frontAction=produce('front',state.items.front);phase='front'
  elseif phase=='wear-setup'and empty()then
   local observed=F.observesClothing(ids)and wearSetup[wearIndex]or wearSetup
   if not observed.started or not observed.progress then diagnostic('native setup wear progress missing');return end
   if ids.wearSwap then
    local name=wearIndex==1 and'target'or'displaced';local item=state.items[name]
    local fresh,reason=PZSurvivorToolkit.ActionQueueClothing.capacityFresh(queue());local ack=Witness.receipt(profile.setupActions[wearIndex])
    local settled=p:getWornItem(item:getBodyLocation())==item and item:getContainer()==p:getInventory()
    if not settled or not fresh or isClient()and(not ack.capturePresent or ack.ackState~='completed'or not ack.nativeSame or not ack.itemSame or not ack.actorSame or not ack.rootSame or not ack.queueSame or not ack.canonicalRoot or not ack.rootOwned or not ack.worn or not ack.slotSame or ack.slotId~=item:getID())then
     diagnostic('native swap setup terminal/physical/freshness pending: '..tostring(reason));return
    end
    observed.settled=F.unequipSnapshot(state,name);observed.fresh=true;observed.ack=ack
   end
   if F.observesClothing(ids)and wearIndex==1 then
    wearIndex=2;local name=ids.wearSwap and'displaced'or'cancelled';local item=state.items[name];local action=ISWearClothing:new(p,item)
    assert(action.maxTime==50 and action.item==item and action.getDuration==ISWearClothing.getDuration,'second native wear constructor differs')
    nativeWear(action)
    local row={name=name,callbacksUntouched=true,type=action.Type,producer='native ISWearClothing constructor',item=item:getID(),duration=action.maxTime,started=false,progress=false}
    wearSetup[2]=row;tracks[action]=row;profile.setupActions[2]=action;ISTimedActionQueue.add(action);return
   end
   state=F.resolve(p,ids)
   if not state or not F.wearBaseline(state)then diagnostic('native setup wear canonical binding not ready');return end
   phase='wear-baseline';waitingSince=now();request('WearBaseline')
  elseif phase=='wear-baseline'then
   if not wearReceipt then diagnostic('authoritative native wear baseline pending');return end
   state=assert(F.resolve(p,ids),'native wear canonical identity lost after authority baseline')
   state.input=assert(F.wearBaseline(state),'native wear input baseline changed')
   if ids.wearSwap then
    local fresh,reason=PZSurvivorToolkit.ActionQueueClothing.capacityFresh(queue());if not fresh then diagnostic('native swap prelude freshness pending: '..tostring(reason));return end
    swapEvidence={attempts={},moves={},before=F.snapshot(state)};Witness.freshness('before-wear-swap');swapAction=swapWear();phase='swap-active'
   else profile.run();state.frontAction=produce('front',state.items.front);phase='front'end
  elseif phase=='swap-active'and tracks[swapAction].progress then
   assert(queue().current==swapAction,'native Wear ended before genuine pending producer capture')
   state.frontAction=produce('front',state.items.front);produce('target',state.items.target);swapTail=produce('tail',state.items.tail)
   swapEvidence.queuedOrder=order();phase='swap-front';waitingSince=now()
  elseif phase=='swap-front'and queue().current==state.frontAction then
   if not tracks[state.frontAction].progress then return end
   if swapPermission()then phase='running'end
  elseif phase=='swap-front'then
   assert(queue().current==swapAction,'native Wear/front boundary elapsed before freshness permission');return
  elseif phase=='front'and tracks[state.frontAction].progress then
   if ids.wornPrepared then Witness.freshness('before-producers')end
   local before=JSON.encode(F.snapshot(state))
   if not native and case()=='root'then
    local discard=produce('cancelled',state.items.cancelled)
    assert(PZSurvivorToolkit.ActionQueue.cancelOperation(queue(),discard),'pending independent wring cancellation denied')
    tracks[discard].cancelled=true;edits.cancelled=true
   end
   if case()=='worn-bag'or case()=='worn-prepared'then produce('cancelled',state.items.cancelled)end
   local target=produce('target',state.items.target)
   if not native and case()=='root'then
    local repeatAction=produce('repeat',state.items.target)
    local ordered={};for i,action in ipairs(queue().queue)do ordered[i]=action end
    assert(not PZSurvivorToolkit.ActionQueue.move(queue(),repeatAction,target),'same clothing cap10 dependency accepted')
    for i,action in ipairs(ordered)do assert(queue().queue[i]==action,'denied move changed queue')end
    assert(PZSurvivorToolkit.ActionQueue.cancelOperation(queue(),repeatAction),'pending duplicate cleanup denied')
    tracks[repeatAction].cancelled=true;edits.repeatDenied=true
   end
   local tail=produce('tail',state.items.tail);state.tailAction=tail
   if case()=='worn-bag'then profile.scenario.check(commands,config.mode)end
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
    profile.sample('queued')
    assert(queue().current==state.frontAction and tostring(state.frontAction.action)==preparedEvidence.frontNative,'pending edits changed active native front')
   end
   if case()=='worn-prepared'then
    local discarded,kept=describeWorn('cancelled'),describeWorn('target')
    wornEvidence={front=tracks[state.frontAction].actionRef,frontNative=tostring(state.frontAction.action),initialOrder=order(),cancelled=discarded,target=kept,moves={},before=F.snapshot(state)}
    if not native then
     assert(PZSurvivorToolkit.ActionQueue.cancelOperation(queue(),groups.cancelled[2]),'pending worn group cancellation denied')
     for _,member in ipairs(groups.cancelled)do assert(queue():indexOf(member)==-1,'cancelled worn child survived');tracks[member].cancelled=true end
     discarded.selected=discarded.body;discarded.accepted=true;discarded.afterOrder=order();edits.cancelled=true
     for _,move in ipairs({{selected=groups.target[1],after=true},{selected=groups.target[2],after=false}})do
      assert(PZSurvivorToolkit.ActionQueue.move(queue(),move.selected,tail,move.after),'pending worn whole-group move denied')
      local current=describeWorn('target');assert(current.token==kept.token,'worn move changed token')
      wornEvidence.moves[#wornEvidence.moves+1]={selected=tracks[move.selected].actionRef,after=move.after,accepted=true,order=order(),bounds=current.bounds}
     end
     edits.reordered=true
    end
    wornEvidence.finalOrder=order();wornEvidence.after=F.snapshot(state)
    assert(queue().current==state.frontAction and tostring(state.frontAction.action)==wornEvidence.frontNative,'worn edit changed active front')
   end
   edits.untouched=before==JSON.encode(F.snapshot(state));assert(edits.untouched,'pending edits changed physical clothing state');phase='running'
  elseif phase=='running'and empty()then
   if not F.verify(state)then
    if profile.restoration and not profile.drainedDiagnostic then
     profile.drainedDiagnostic=true
     local body=groups.target and groups.target[#groups.target]
     local settlement=PZSurvivorToolkit.ActionQueueSettlement
     local ledger=body and settlement.operationState(body)
     profile.observation={case=case(),point='drained',observedAt=now(),ledger=ledger or false,debts=PZSurvivorToolkit.ActionQueueExecution.blockedReturns(getPlayer())}
     raw('RESTORATION_DIAGNOSTIC',profile.diagnostics.capture(getPlayer(),ids,state,queue(),body,state.tailAction,profile.observation))
     assert(not ledger or ledger.optionalReturnState~='blocked','optional restoration blocked: '..tostring(ledger and ledger.optionalReturnDetail))
    end
    quiet=nil;return
   end
   quiet=quiet or now();if now()-quiet>=1000 then phase='verified';request('Verify')end
  elseif phase=='verified'and receipt then
   local client=profile.final or assert(F.verify(state))
   if F.observesClothing(ids)then
    local clothing=assert(PZSurvivorToolkit.ActionQueueClothing,'native clothing witness missing')
    assert(type(clothing.capacityFresh)=='function'and Proof.closure(clothing.capacityFresh,'ActionQueueClothing.lua'),'native clothing freshness API differs')
    -- Query only after authority Verify and physical convergence; the original
    -- fixture deadline bounds passive packet arrival, with no native wait owner.
    Witness.finalWait()
    if clothing.capacityFresh(queue())~=true then diagnostic('native clothing capacity freshness pending');return end
    if ids.wearSwap then
     swapEvidence.capacityFresh=true;swapEvidence.finalAck=Witness.receipt(swapAction)
    else wornEvidence.capacityFresh=true end
   end
   for _,row in ipairs(commands)do
    if row.type=='ISWringClothing'then assert(row.cancelled and not row.started and not row.progress or not row.cancelled and row.started and row.progress,'native wring progress/cancellation evidence missing')end
   end
   local cleanupClient
   if ids.capacityProfile then
    if not profile.cleanupRequested then profile.final=client;profile.cleanupRequested=true;request('ProfileCleanup');return end
    if not profile.cleanupReceipt then diagnostic('profile authority cleanup pending');return end
    local ok,value=pcall(profile.module.cleanupProof,state);if not ok then diagnostic('profile local cleanup sync pending');return end
    cleanupClient=value
   end
   profile.sample('final')
   local row={event='case',id=case(),status='passed',ids=ids,clientPlacement=proof,input=state.input,client=client,server=receipt,
    commands=commands,edit=edits,queueIdle=true,settleMilliseconds=now()-quiet}
   if profile.restoration then row.restoration=profile.restorationEvidence end
   if ids.capacityProfile then row.capacityProfile={measurement=profile.evidence,cleanupClient=cleanupClient,cleanupServer=profile.cleanupReceipt}end
   if ids.nativeWearSetup then row.wearSetup=wearSetup;row.authorityBaseline=wearReceipt end
   if ids.preparedGroups then row.prepared=preparedEvidence end
   if ids.wornPrepared then row.wornPrepared=wornEvidence end
   if ids.wearSwap then swapEvidence.lastRefusal=nil;row.wearSwap=swapEvidence end
   emit(row)
   if not isClient()then previous=authority end
   index=index+1
   if not case()then emit({event='complete',cases=config.cases,performed=index-1,failed=0,skipped=0});raw('COMPLETE',{cases=config.cases});done=true;return end
   state,authority,ids,receipt,placement,placementState,proof,quiet=nil,nil,nil,nil,nil,nil,nil,nil
   profile.observation=nil
   profile.evidence,profile.final,profile.cleanupReceipt,profile.cleanupRequested=nil,nil,nil,nil;wearSetup,wearReceipt,wearIndex,profile.setupActions=nil,nil,nil,nil;wornEvidence,swapEvidence,swapAction,swapTail=nil,nil,nil,nil;waits={};waitingSince=now()
   tracks,commands,groups,tokens,returns,returnTracks={}, {}, {}, {}, {}, {};preparedEvidence=nil;prepCallbacks={};edits={cancelled=false,reordered=false,repeatDenied=false,untouched=true};phase='prepare';since=now()
  end
 end)
 if not ok then fail(error)end
end)
