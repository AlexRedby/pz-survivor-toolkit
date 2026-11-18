require 'PZSurvivorToolkit/ActionQueuePanel'
require 'XpSystem/ISUI/ISCharacterScreen'
require 'ISUI/ISInventoryPaneContextMenu'
local Razor=require 'PZSurvivorToolkit/ActionQueueRazorRestoration'
local F=require 'QueueRazorRestoration'
local P=require 'QueueEnergyPlacement'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local T=PZSurvivorToolkit
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Approach=T.ActionQueueApproach
local isContainerApproach=Approach and Approach.isContainer
local phase,index,since='prepare',1,getTimestampMs()
local started,ready,done=false,false,false
local state,authority,previous,ids,receipt,placement,placing,placementProof,quiet
local evidence,actions,tracks,order={},{},{},{}
local menu,primaryMenu,nativeMethods
local function q()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #q().queue==0 and not getPlayer():hasTimedActions()end
local function raw(event,row)print('[RAZOR_RESTORATION] '..event..' '..JSON.encode(row))end
local function emit(row)row.suite='razor-restoration';row.actor='client1';row.kind=config.kind;row.mode=config.mode;JSON.emit(row)end
local function fail(reason)
 if done then return end;done=true;raw('FAILED',{phase=phase,error=tostring(reason)})
 print('[QUEUE_TEST] FAIL razor-restoration '..tostring(reason));emit({event='failure',id=config.cases[index],error=tostring(reason)})
end
local function exactApproach(action)
 assert(T.ActionQueueApproach==Approach and Approach.isContainer==isContainerApproach
  and Proof.closure(isContainerApproach,'ActionQueueApproach.lua'),'container approach predicate binding changed')
 local bag=assert(F.find(getPlayer(),ids.bag.id))
 return isContainerApproach(action,bag:getItemContainer(),getPlayer())==true
end
local function role(action)
 if action.Type=='ISTrimBeard'then return 'trim'end
 if action.Type=='ISReadABook'then return 'tail'end
 if action.Type=='ISInventoryTransferAction'and action.item and action.item:getID()==ids.items.razor.id then
  return action.destContainer==getPlayer():getInventory()and'pickup'or'returned'
 end
 if action.Type=='ISEquipWeaponAction'and action.item then
  for name,spec in pairs(ids.items)do if action.item:getID()==spec.id then
   return({razor='preparationEquip',previous='restore',replacement='explicitEquip'})[name]or'unknown'
  end end
 end
 if action.Type=='ISQueueActionsAction'then return exactApproach(action)and'approach'or'command'end
 return 'unknown'
end
local function track(action)
 if tracks[action]then return tracks[action]end
 local name=role(action);assert(name~='unknown','unexpected native producer action '..tostring(action.Type))
 if name~='command'then assert(not actions[name]or actions[name]==action,'duplicate exact native action '..name);actions[name]=action end
 local row={role=name,type=action.Type,actionRef=tostring(action),itemId=action.item and action.item:getID()or false,
  constructorDuration=action.maxTime,sourceRef=action.srcContainer and tostring(action.srcContainer)or false,allocated=false,started=false,progress=false,events={},ack={},transfers={}}
 row.actor,row.queue,row.root,row.item,row.operation=action.character,q(),action.character:getInventory(),action.item,action.toolkitQueueOperation
 row.source,row.destination=action.srcContainer,action.destContainer
 tracks[action]=row;order[#order+1]=row
 raw('ACTION',{case=ids.case,action={role=name,type=row.type,actionRef=row.actionRef,itemId=row.itemId,constructorDuration=row.constructorDuration}})
 return row
end
local function itemIdentity(action,row,boundary)
 if row.itemId==false then return{exact=true,state='none',canonical=true}end
 local current=action.item;local canonical=F.find(row.actor,row.itemId)
 local original=row.item
 local exact=current~=nil and current:getID()==row.itemId and original~=nil and current:getFullType()==original:getFullType()
 if current~=nil then
  assert(exact and(current==original or current==row.boundItem or current==canonical),row.role..'/'..boundary..': foreign item ID/type/reference')
  if current==canonical then row.boundItem=current end
 elseif not isClient()or(row.role~='pickup'and row.role~='returned')then
  error(row.role..'/'..boundary..': missing exact native item')
 else
  local physical=F.transferSnapshot(state,row.role)
  local tx=action.transactionId
  local terminal=type(tx)=='number'and tx~=0 and isItemTransactionDone(tx)
  assert(physical.canonical and((physical.sourceCount==0 and physical.destinationCount==1 and terminal)or row.transferDone),row.role..'/'..boundary..': nil item without exact completed transfer/physical effect')
  exact=true
 end
 if current~=nil and row.role~='pickup'and row.role~='returned'and action.action and q().current==action and action:isStarted()then
  assert(current==canonical,row.role..'/'..boundary..': started item is not exact current canonical replica')
 end
 return{exact=exact,state=current==nil and'nil'or current==original and'original'or'canonical-replica',canonical=current==canonical}
end
local function transferObservation(action,row,boundary)
 if row.role~='pickup'and row.role~='returned'then return end
 local identity=itemIdentity(action,row,boundary);local physical=F.transferSnapshot(state,row.role)
 local transaction=action.transactionId or 0
 local done=isClient()and transaction~=0 and isItemTransactionDone(transaction)or false
 local rejected=isClient()and transaction~=0 and isItemTransactionRejected(transaction)or false
 local duration=isClient()and transaction~=0 and getItemTransactionDuration(transaction)or false
 if done then row.transferDone=true end
 local sample={at=getTimestampMs(),boundary=boundary,transaction=transaction,done=done,rejected=rejected,duration=duration,
  physical=physical,itemState=identity.state,itemExact=identity.exact,itemCanonical=identity.canonical,
  nativeRef=tostring(action.action),operationRef=tostring(action.toolkitQueueOperation),
  nativeSame=action.action==row.native,actorSame=action.character==row.actor,operationSame=action.toolkitQueueOperation==row.operation,
  sourceSame=action.srcContainer==row.source,destinationSame=action.destContainer==row.destination,
  queueSame=ISTimedActionQueue.queues[row.actor]==row.queue,rootSame=row.actor:getInventory()==row.root}
 local last=row.transfers[#row.transfers]
 if not last or last.transaction~=transaction or last.done~=done or last.rejected~=rejected or last.itemState~=sample.itemState
  or last.boundary~=boundary or last.physical.destinationCount~=physical.destinationCount then
  row.transfers[#row.transfers+1]=sample;raw('TRANSFER',{case=ids.case,actionRef=row.actionRef,observation=sample})
 end
end
local function acknowledge(action,row)
 if not isClient()or not action.action or row.role=='pickup'or row.role=='returned'then return end
 local A=T.ActionQueueAcknowledgements
 if not row.receipt then row.receipt=A.capture(action)end
 if not row.receipt then return end
 local status=A.observe(action,row.receipt)
 if not status or row.lastAck==status then return end
 row.lastAck=status
 local item={at=getTimestampMs(),state=status,transaction=action.toolkitNativeTransaction or false,kind=action.toolkitNativeKind or false,
  token=row.receipt.token or false,nativeRef=tostring(action.action),operationRef=tostring(action.toolkitQueueOperation),
  nativeSame=action.action==row.native,actorSame=action.character==row.actor and getPlayer()==row.actor,
  queueSame=ISTimedActionQueue.queues[row.actor]==row.queue and q()==row.queue,rootSame=row.actor:getInventory()==row.root,
  itemSame=itemIdentity(action,row,'ack').exact,itemCanonical=itemIdentity(action,row,'ack').canonical,operationSame=action.toolkitQueueOperation==row.operation}
 row.ack[#row.ack+1]=item;raw('ACK',{case=ids.case,actionRef=row.actionRef,observation=item})
end
assert(T.ActionQueueLifecycle.registerObserver('fixture-razor-restoration',{
 started=function(action)
  if phase~='running'or action.character~=getPlayer()then return end
  local row=track(action);row.admittedAt=getTimestampMs()
  if row.role=='tail'then evidence.tailBoundary={at=getTimestampMs(),snapshot=F.snapshot(state),debts=T.ActionQueueSettlement.blockedReturns(getPlayer())}end
 end,
 begin=function(action,boundary)
  if phase~='running'or action.character~=getPlayer()then return end
  local row=track(action);if not row.native then row.native=action.action end
  transferObservation(action,row,'begin-'..boundary)
  row.events[#row.events+1]={boundary='begin',phase=boundary,at=getTimestampMs(),nativeRef=tostring(action.action)}
  return true
 end,
 finish=function(action,boundary,succeeded)
  if phase~='running'or action.character~=getPlayer()then return end
  local row=track(action);if not row.native then row.native=action.action end
  transferObservation(action,row,'finish-'..boundary)
  row.events[#row.events+1]={boundary='finish',phase=boundary,succeeded=succeeded==true,at=getTimestampMs(),nativeRef=tostring(action.action)}
  acknowledge(action,row)
 end,
}))
local function request(command)
 local args={case=config.cases[index],placement=placement,clientPlacement=placementProof}
 if isClient()then sendClientCommand('RazorRestorationTest',command,args)
 elseif command=='Prepare'then authority=F.prepare(getPlayer(),args.case,placement,placementProof,previous);previous=nil;ids=authority.ids;raw('PREPARED',ids)
 else receipt=assert(F.verify(authority),'SP exact physical authority differs');receipt.transfers=authority.transfers or{};raw('VERIFIED',receipt)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~='RazorRestorationTest'or done then return end
 if command=='Failed'then fail(args.error)
 elseif args and args.case==config.cases[index]then
  if command=='Prepared'then ids=args elseif command=='Verified'then receipt=args end
 end
end)
local function callbacksUnchanged()
 if ISCharacterScreen.onTrimBeard~=menu or ISInventoryPaneContextMenu.OnPrimaryWeapon~=primaryMenu then return false end
 for class,methods in pairs(nativeMethods)do for name,callback in pairs(methods)do if class[name]~=callback then return false end end end
 return true
end
local function produce()
 assert(empty()and F.same(F.snapshot(state),ids.baseline),'native producer baseline differs')
 actions,tracks,order={},{},{}
 evidence={before=F.snapshot(state),producer='ISCharacterScreen.onTrimBeard',target=ids.targetBeard,installed=Razor.enabled()==true,
  explicitRequested=false,initialRevision=T.ActionQueueTidyIntent.primaryRequestRevision(getPlayer())}
 assert(evidence.initialRevision~=nil,'own primary intent tracking unavailable')
 local previous=assert(F.find(getPlayer(),ids.items.previous.id))
 local hands=T.ActionQueueEquip.restorationHands(getPlayer(),previous)
 evidence.handSeed={id=previous:getID(),type=previous:getFullType(),requiresBoth=previous:isRequiresEquippedBothHands(),
  handWeapon=instanceof(previous,'HandWeapon'),supportsTwo=instanceof(previous,'HandWeapon')and previous:isTwoHandWeapon()or false,
  ordinary=hands~=nil and hands.primary~=nil and hands.primary.item==previous}
 assert(evidence.handSeed.ordinary and not evidence.handSeed.requiresBoth and not evidence.handSeed.supportsTwo,
  'authority initial primary is outside ordinary one-hand restoration')
 phase='running'
 ISCharacterScreen.onTrimBeard(getPlayer(),ids.targetBeard)
 for _,action in ipairs(q().queue)do track(action)end
 assert(actions.pickup and actions.preparationEquip and actions.trim,'actual razor menu did not produce native pickup/equip/trim')
 local queue=q();local list=queue.queue;local prefix=actions.approach and 1 or 0
 local expected=prefix==1 and {'approach','pickup','preparationEquip','trim','command'}or{'pickup','preparationEquip','trim','command'}
 assert(#list==#expected,'actual producer cleanup topology differs')
 evidence.producerQueue,evidence.producerEntries={},{}
 for position,action in ipairs(list)do
  local row=track(action);assert(row.role==expected[position],'actual producer queue role/order differs')
  evidence.producerQueue[#evidence.producerQueue+1]=row.actionRef
  evidence.producerEntries[#evidence.producerEntries+1]={position=position,actionRef=row.actionRef,role=row.role,
   operationRef=tostring(action.toolkitQueueOperation),sameToken=action.toolkitQueueOperation==actions.trim.toolkitQueueOperation,
   actorSame=action.character==getPlayer(),queueEntrySame=list[position]==action}
 end
 evidence.approach=false
 if prefix==1 then
  local bag=assert(F.find(getPlayer(),ids.bag.id));local container=bag:getItemContainer();local action=actions.approach
  evidence.approach={actionRef=tracks[action].actionRef,position=queue:indexOf(action),type=action.Type,
   sourceBound=exactApproach(action),bagId=bag:getID(),containerRef=tostring(container),
   pickupSourceSame=actions.pickup.srcContainer==container,canonicalBag=getPlayer():getInventory():getItemById(ids.bag.id)==bag
    and bag:getContainer()==getPlayer():getInventory()and getPlayer():getWornItems():contains(bag),
   actorSame=action.character==getPlayer(),sameToken=action.toolkitQueueOperation==actions.trim.toolkitQueueOperation,
   operationRef=tostring(action.toolkitQueueOperation),queueSame=q()==queue,listSame=queue.queue==list,queueEntrySame=list[1]==action}
 end
 for position,entry in ipairs(evidence.producerEntries)do
  assert(list[position]and tracks[list[position]].actionRef==entry.actionRef and entry.sameToken and entry.actorSame
   and entry.queueEntrySame and q()==queue and queue.queue==list,'producer receipt escaped exact queue array/token/actor')
 end
 ISInventoryPaneContextMenu.readItem(assert(F.find(getPlayer(),ids.items.tail.id)),getPlayer():getPlayerNum())
 for _,action in ipairs(q().queue)do track(action)end
 assert(actions.tail and actions.tail.toolkitQueueOperation~=actions.trim.toolkitQueueOperation,'native independent reader tail missing')
end
local function observe()
 assert(callbacksUnchanged(),'fixture observed replaced native action or UI callbacks')
 for _,action in ipairs(q().queue)do track(action)end
 for action,row in pairs(tracks)do
  if action.action then
   if not row.native then row.native=action.action end
   assert(row.native==action.action,row.role..'/poll: native allocation changed')
   assert(row.operation==action.toolkitQueueOperation,row.role..'/poll: operation token changed')
   assert(action.character==row.actor and ISTimedActionQueue.queues[row.actor]==row.queue,row.role..'/poll: actor/queue changed')
   assert(action.srcContainer==row.source and action.destContainer==row.destination,row.role..'/poll: transfer endpoints changed')
   itemIdentity(action,row,'poll')
   transferObservation(action,row,'poll')
   row.allocated=true;row.nativeRef=tostring(action.action);row.operationRef=tostring(action.toolkitQueueOperation)
   row.effectiveDuration=math.max(row.effectiveDuration or -1,action.action:getTime())
   if q().current==action and action:isStarted()then
    if not row.started then row.started=true;row.startedAt=getTimestampMs()end
    local delta=action:getJobDelta();if delta>0 and delta<1 then row.progress=true end
   end
   acknowledge(action,row)
  end
 end
 local trim=actions.trim;local row=tracks[trim]
 if ids.case=='new-primary-intent'and row.progress and q().current==trim and not evidence.explicitRequested then
  assert(getPlayer():getPrimaryHandItem()==F.find(getPlayer(),ids.items.razor.id),'explicit request missed actual razor held during trim')
  local before=T.ActionQueueTidyIntent.primaryRequestRevision(getPlayer())
  local snapshot=F.snapshot(state);local count=#q().queue
  ISInventoryPaneContextMenu.OnPrimaryWeapon({assert(F.find(getPlayer(),ids.items.replacement.id))},getPlayer():getPlayerNum())
  for _,action in ipairs(q().queue)do track(action)end
  assert(#q().queue==count+1 and actions.explicitEquip and not actions.explicitEquip.action,'native primary UI intent topology differs')
  local after=T.ActionQueueTidyIntent.primaryRequestRevision(getPlayer())
  assert(type(after)=='number'and after>before,'explicit native primary menu request was not accepted')
  evidence.explicitRequested=true;evidence.intent={at=getTimestampMs(),before=before,after=after,trimRef=row.actionRef,
   trimNative=tostring(trim.action),trimDelta=trim:getJobDelta(),snapshot=snapshot,explicitActionRef=tracks[actions.explicitEquip].actionRef,explicitUnallocated=actions.explicitEquip.action==nil}
  raw('INTENT',{case=ids.case,observation=evidence.intent})
 end
end
require('QueuePreflight').onGameStart(Events,function()started=true;since=getTimestampMs()end)
require('QueuePreflight').onTick(Events,function()
 if not started or done then return end
 local ok,reason=pcall(function()
  local player=getPlayer();if not isIngameState()or not player or not player:getSquare()then return end
  if not ready then
   if isClient()~=(config.kind=='mp')or isClient()and(player:getOnlineID()<0 or player:getUsername()~='client1')then return end
   assert(config.mode=='toolkit'and not player:isTimedActionInstant(),'ordinary Toolkit native durations required')
   assert(not P4TidyUpMeister and not getActivatedMods():contains('P4TidyUpMeister'),'native own return provider required')
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(true)
   assert(Razor.install()and Razor.enabled(),'real Razor.install consumer did not install')
   player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false);getCore():setOptionAutoDrink(false);getCore():setOptionPauseOnFocusloss(false)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
   menu,primaryMenu=ISCharacterScreen.onTrimBeard,ISInventoryPaneContextMenu.OnPrimaryWeapon
   nativeMethods={}
   for _,class in ipairs({ISInventoryTransferAction,ISEquipWeaponAction,ISTrimBeard,ISReadABook})do
    local methods={};for name,callback in pairs(class)do if type(callback)=='function'then methods[name]=callback end end;nativeMethods[class]=methods
   end
   ready=true;emit({event='setup',cases=config.cases,nativeDurations=true,provider='native-returns',installed=true});since=getTimestampMs()
  end
  assert(getTimestampMs()-since<120000,'razor restoration timeout '..phase)
  if authority and not isClient()then
   local transfer=F.observeTransferAuthority(authority);if transfer then raw('TRANSFER_AUTHORITY',transfer)end
  end
  if phase=='prepare'then
   assert(empty());placement=placement or P.choose(player);placing=placing or P.beginCentered(player,placement);placementProof=P.poll(placing);if not placementProof then return end
   raw('CLIENT_PLACEMENT',{case=config.cases[index],proof=placementProof});phase='prepared';request('Prepare')
  elseif phase=='prepared'and ids then
   state=F.resolve(player,ids);if not state then return end
   local pane=assert(getPlayerInventory(player:getPlayerNum()));pane:refreshBackpacks();local available=false
   local bag=F.find(player,ids.bag.id)
   for _,entry in ipairs(pane.backpacks)do if entry.inventory==bag:getItemContainer()then available=true end end
   if available then produce()end
  elseif phase=='running'then
   observe();if not empty()then return end
   assert(actions.trim and tracks[actions.trim].started and tracks[actions.trim].progress,'real native trim did not progress')
   assert(actions.tail and tracks[actions.tail].started and tracks[actions.tail].progress,'independent native reader did not progress')
   local debts=T.ActionQueueSettlement.blockedReturns(player)
   if ids.case=='restore-success'then
    assert(actions.restore and actions.returned and #debts==0 and not evidence.explicitRequested,'ordinary producer restore/return missing')
   else
    assert(evidence.explicitRequested and actions.explicitEquip and not actions.restore and not actions.returned,
     'new primary intent allowed old restore or borrowed return construction')
    assert(#debts==1 and debts[1].itemId==ids.items.razor.id and debts[1].state=='blocked','new primary intent lost exact unpaid razor debt')
   end
   if not F.verify(state)then return end
   quiet=quiet or getTimestampMs();if getTimestampMs()-quiet<500 then return end
   evidence.debts=debts;evidence.queueIdle=true;evidence.nativeCallbacksUntouched=callbacksUnchanged();phase='verified';request('Verify')
  elseif phase=='verified'and receipt then
   local client=assert(F.verify(state));local published={}
   for _,row in ipairs(order)do
    local copy={};for key,value in pairs(row)do if key~='native'and key~='item'and key~='operation'and key~='receipt'and key~='lastAck'and key~='actor'and key~='queue'and key~='root'and key~='source'and key~='destination'and key~='transferDone'and key~='boundItem'then copy[key]=value end end
    published[#published+1]=copy
   end
   evidence.actions=published;evidence.after=client
   emit({event='case',id=ids.case,status='passed',ids=ids,clientPlacement=placementProof,client=client,server=receipt,evidence=evidence})
   if not isClient()then previous=authority end
   index=index+1
   if not config.cases[index]then emit({event='complete',cases=config.cases,performed=index-1,failed=0,skipped=0});raw('COMPLETE',{cases=config.cases});done=true;return end
   for _,debt in ipairs(T.ActionQueueSettlement.blockedReturns(player))do assert(T.ActionQueueExecution.keepReturn(player,debt.id),'explicit fixture debt retirement refused')end
   state,authority,ids,receipt,placement,placing,placementProof,quiet=nil,nil,nil,nil,nil,nil,nil,nil
   actions,tracks,order,evidence={},{},{},{};phase='prepare';since=getTimestampMs()
  end
 end)
 if not ok then fail(reason)end
end)
