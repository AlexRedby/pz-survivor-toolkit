require 'PZSurvivorToolkit/ActionQueuePanel'
require 'XpSystem/ISUI/ISCharacterScreen'
require 'ISUI/ISInventoryPaneContextMenu'
local Razor=require 'PZSurvivorToolkit/ActionQueueRazorRestoration'
local F=require 'QueueRazorRestoration'
local P=require 'QueueEnergyPlacement'
local JSON=require 'QueueHealthEvents'
local config=require 'QueueTestSelection'
local T=PZSurvivorToolkit
local editorOff=config.options and config.options.queue_editor_enabled==false
local editorTicks=0
local Proof=require 'PZSurvivorToolkit/SourceProof'
-- Select the fixture character before ZZStartup advances the creation menu.
Events.OnPreUIDraw.Add(function()
 if isIngameState() then return end
 local main=MainScreen and MainScreen.instance
 local panel=main and main.charCreationMain
 if not panel or not panel.genderCombo or not main.desc or not main.avatar then return end
 if main.desc:isFemale() or panel.genderCombo.selected~=2 then
  assert(Proof.closure(panel.onGenderSelected,'CharacterCreationMain.lua'),'native character creation callback unavailable')
  panel.genderCombo.selected=2
  panel:onGenderSelected(panel.genderCombo)
 end
end)
local Approach=T.ActionQueueApproach
local isContainerApproach=Approach and Approach.isContainer
local phase,index,since='prepare',1,getTimestampMs()
local started,ready,done=false,false,false
local state,authority,previous,ids,receipt,placement,placing,placementProof,quiet
local evidence,actions,tracks,order={},{},{},{}
local menu,cutMenu,primaryMenu,nativeMethods
local originReceipt,originRequestedAt
local observeCancelStop
local function originCase()return ids.case=='full-origin'or ids.case=='unavailable-origin'or ids.case=='keep-return'end
local function q()return ISTimedActionQueue.getTimedActionQueue(getPlayer())end
local function empty()return #q().queue==0 and not getPlayer():hasTimedActions()end
local function raw(event,row)print('[RAZOR_RESTORATION] '..event..' '..JSON.encode(row))end
local function emit(row)row.suite='razor-restoration';row.actor='client1';row.kind=config.kind;row.mode=config.mode;JSON.emit(row)end
local function fail(reason)
 if done then return end;done=true;raw('FAILED',{phase=phase,error=tostring(reason)})
 print('[QUEUE_TEST] FAIL razor-restoration '..tostring(reason));emit({event='failure',id=config.cases[index],error=tostring(reason)})
end
local function checkEditor()
 if not editorOff then return end
 local option=PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):getValue()
 local setting=T.Settings.actionQueue()
 assert(option==false and setting==false,'queue editor enabled during editor-off native restore')
 return option,setting
end
local function observeEditor(boundary,action)
 if not editorOff then return end
 local option,setting=checkEditor()
 local observation={boundary=boundary,at=getTimestampMs(),option=option,setting=setting,ticks=editorTicks,actionRef=action and tostring(action)or false}
 evidence.editor[#evidence.editor+1]=observation;raw('EDITOR',{case=ids.case,observation=observation})
end
local function exactApproach(action)
 assert(T.ActionQueueApproach==Approach and Approach.isContainer==isContainerApproach
  and Proof.closure(isContainerApproach,'ActionQueueApproach.lua'),'container approach predicate binding changed')
 local bag=F.find(getPlayer(),ids.bag.id)or state and state.bag
 assert(bag and bag:getID()==ids.bag.id and bag:getFullType()==ids.bag.type,'exact origin bag observation unavailable')
 return isContainerApproach(action,bag:getItemContainer(),getPlayer())==true
end
local function role(action)
 if action.Type==(ids.case=='cut-hair-scissors'and'ISCutHair'or'ISTrimBeard')then return 'trim'end
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
 if tracks[action]then
  local row=tracks[action]
  if row.operation~=action.toolkitQueueOperation then
   local original=actions.trim and actions.trim.toolkitQueueOperation;local token=action.toolkitQueueOperation
   assert(ids.case=='cancel-active'and evidence.control and row.role=='command'and not row.operationTransition
    and row.actionRef==evidence.producerQueue[#evidence.producerQueue]and row.operation==original
    and token and token~=original and token~=actions.tail.toolkitQueueOperation and not action.action and not row.native,
    'operation changed outside exact preallocated canceled razor cleanup command')
   row.originalOperationRef=row.operationRef
   row.operationTransition={at=getTimestampMs(),from=row.operationRef,to=tostring(token),preallocation=true,sameAction=true}
   row.operation=token;row.operationRef=tostring(token)
   raw('RETOKEN',{case=ids.case,actionRef=row.actionRef,observation=row.operationTransition})
  end
  return row
 end
 local name=role(action);assert(name~='unknown','unexpected native producer action '..tostring(action.Type))
 if name~='command'then assert(not actions[name]or actions[name]==action,'duplicate exact native action '..name);actions[name]=action end
 local row={role=name,type=action.Type,actionRef=tostring(action),operationRef=tostring(action.toolkitQueueOperation),itemId=action.item and action.item:getID()or false,
  constructorDuration=action.maxTime,hairStyle=action.Type=='ISCutHair'and action.hairStyle or nil,sourceRef=action.srcContainer and tostring(action.srcContainer)or false,allocated=false,started=false,progress=false,events={},ack={},transfers={}}
 row.actor,row.queue,row.root,row.item,row.operation=action.character,q(),action.character:getInventory(),action.item,action.toolkitQueueOperation
 row.source,row.destination=action.srcContainer,action.destContainer
 tracks[action]=row;order[#order+1]=row
 raw('ACTION',{case=ids.case,action={role=name,type=row.type,actionRef=row.actionRef,itemId=row.itemId,constructorDuration=row.constructorDuration,hairStyle=row.hairStyle}})
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
 if boundary=='poll'and q().current~=action and(not row.started or row.transferDone)then return end
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
  if observeCancelStop then observeCancelStop('before-next-admission',action)end
  local row=track(action);row.admittedAt=getTimestampMs();observeEditor('native-admission',action)
  if row.role=='tail'then evidence.tailBoundary={at=getTimestampMs(),snapshot=F.snapshot(state),debts=T.ActionQueueSettlement.blockedReturns(getPlayer())}end
 end,
 begin=function(action,boundary)
  if phase~='running'or action.character~=getPlayer()then return end
  checkEditor();local row=track(action);if not row.native then row.native=action.action end
  transferObservation(action,row,'begin-'..boundary)
  row.events[#row.events+1]={boundary='begin',phase=boundary,at=getTimestampMs(),nativeRef=tostring(action.action)}
  return true
 end,
 finish=function(action,boundary,succeeded)
  if phase~='running'or action.character~=getPlayer()then return end
  checkEditor();local row=track(action);if not row.native then row.native=action.action end
  transferObservation(action,row,'finish-'..boundary)
  row.events[#row.events+1]={boundary='finish',phase=boundary,succeeded=succeeded==true,at=getTimestampMs(),nativeRef=tostring(action.action)}
  acknowledge(action,row)
 end,
}))
local function request(command)
 local args={case=config.cases[index],placement=placement,clientPlacement=placementProof,requestedAt=originRequestedAt}
 if isClient()then sendClientCommand('RazorRestorationTest',command,args)
 elseif command=='Prepare'then authority=F.prepare(getPlayer(),args.case,placement,placementProof,previous);previous=nil;ids=authority.ids;raw('PREPARED',ids)
 elseif command=='ChangeOrigin'then originReceipt=F.changeOrigin(authority,originRequestedAt);raw('ORIGIN',originReceipt)
 else receipt=assert(F.verify(authority),'SP exact physical authority differs');receipt.transfers=authority.transfers or{};raw('VERIFIED',receipt)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~='RazorRestorationTest'or done then return end
 if command=='Failed'then fail(args.error)
 elseif args and args.case==config.cases[index]then
  if command=='Prepared'then ids=args elseif command=='Verified'then receipt=args elseif command=='OriginChanged'then originReceipt=args end
 end
end)
local function callbacksUnchanged()
 if ISCharacterScreen.onTrimBeard~=menu or ISCharacterScreen.onCutHair~=cutMenu or ISInventoryPaneContextMenu.OnPrimaryWeapon~=primaryMenu then return false end
 for class,methods in pairs(nativeMethods)do for name,callback in pairs(methods)do if class[name]~=callback then return false end end end
 return true
end
local function produce()
 assert(empty()and F.same(F.snapshot(state),ids.baseline),'native producer baseline differs')
 actions,tracks,order={},{},{}
 local cut=ids.case=='cut-hair-scissors'
 evidence={before=F.snapshot(state),producer=cut and'ISCharacterScreen.onCutHair'or'ISCharacterScreen.onTrimBeard',target=cut and ids.targetHair or ids.targetBeard,installed=Razor.enabled()==true,
  explicitRequested=false,initialRevision=T.ActionQueueTidyIntent.primaryRequestRevision(getPlayer())}
 if editorOff then evidence.editor={};editorTicks=0;observeEditor('before-producer')end
 assert(evidence.initialRevision~=nil,'own primary intent tracking unavailable')
 local previous=assert(F.find(getPlayer(),ids.items.previous.id))
 local hands=T.ActionQueueEquip.restorationHands(getPlayer(),previous)
 evidence.handSeed={id=previous:getID(),type=previous:getFullType(),requiresBoth=previous:isRequiresEquippedBothHands(),
  handWeapon=instanceof(previous,'HandWeapon'),supportsTwo=instanceof(previous,'HandWeapon')and previous:isTwoHandWeapon()or false,
  ordinary=hands~=nil and hands.primary~=nil and hands.primary.item==previous}
 assert(evidence.handSeed.ordinary and not evidence.handSeed.requiresBoth and not evidence.handSeed.supportsTwo,
  'authority initial primary is outside ordinary one-hand restoration')
 phase='running'
 if cut then ISCharacterScreen.onCutHair(getPlayer(),ids.targetHair,300)
 else ISCharacterScreen.onTrimBeard(getPlayer(),ids.targetBeard)end
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
local function ownedPanel()
 local panel=T.ActionQueuePanel:new(80,80,460,640)
 panel.queue,panel.playerNum=q(),getPlayer():getPlayerNum();panel:initialise();panel:addToUIManager();panel:update()
 return panel
end
local function cancellationState(trim,row,boundary)
 local player=getPlayer()
 return{at=getTimestampMs(),boundary=boundary,actionRef=row.actionRef,nativeRef=tostring(trim.action),
  actionSame=actions.trim==trim,nativeSame=trim.action==row.native,actorSame=trim.character==row.actor and player==row.actor,
  queueSame=ISTimedActionQueue.queues[row.actor]==row.queue and q()==row.queue,rootSame=player:getInventory()==row.root,
  member=player:getCharacterActions():contains(row.native),current=q().current==trim,beard=player:getHumanVisual():getBeardModel()or''}
end
observeCancelStop=function(boundary,nextAction)
 local control=evidence.control
 if not ids or ids.case~='cancel-active'or not control or not control.nativeStop or control.nativeStop.after or control.accepted~=true then return end
 local trim=actions.trim;local row=tracks[trim];local sample=cancellationState(trim,row,boundary)
 assert(sample.actionSame and sample.nativeSame and sample.actorSame and sample.queueSame and sample.rootSame and sample.beard==ids.initialBeard,'canceled trim escaped exact native actor/queue/item episode')
 if not sample.member and not sample.current then
  sample.snapshot=F.snapshot(state);assert(F.same(sample.snapshot,control.before),'native cancellation mutated physical appearance or inventory before cleanup')
  control.nativeStop.after=sample;raw('CONTROL',{case=ids.case,observation=control});raw('CANCEL_NATIVE',{case=ids.case,observation=control.nativeStop})
 elseif nextAction and nextAction~=trim then error('razor cleanup/tail admitted before exact canceled native trim disappeared')end
end
local function cancelActive(trim,row)
 local panel=ownedPanel();local list=panel.list;list:setYScroll(0)
 local target
 for _,entry in ipairs(list.items)do if entry.header and entry.operation==trim.toolkitQueueOperation then assert(not target,'ambiguous razor header');target=entry end end
 target=assert(target,'real active razor operation header missing')
 local x,y=list:cancelX()+1,list:topOfItem(target.index)+target.height/2
 assert(list:rowUnderMouse(x,y)==target,'real cancel hit target differs')
 local before=F.snapshot(state);local token=trim.toolkitQueueOperation
 local control={source='ActionQueuePanel.List',input='programmatic-press-release',at=getTimestampMs(),trimRef=row.actionRef,
  trimNative=tostring(trim.action),trimDelta=trim:getJobDelta(),before=before,header=true,hitTested=true,targetRef=tostring(target.item),operationRef=tostring(token)}
 control.nativeStop={before=cancellationState(trim,row,'before-press')};control.at=control.nativeStop.before.at
 assert(control.nativeStop.before.member and control.nativeStop.before.current,'cancel press missed exact allocated active native trim')
 list:onMouseDown(x,y);control.pressCaptured=list.pressedOperation~=nil and list.pressedOperation.operation==token
 assert(control.pressCaptured,'real active razor header press rejected: '..tostring(list.cancelFeedback and list.cancelFeedback.text))
 local members={};for _,action in ipairs(list.pressedOperation.members)do members[#members+1]=tostring(action)end;control.members=members
 evidence.control=control;list:onMouseUp(x,y)
 for _,action in ipairs(q().queue)do track(action)end
 control.accepted=list.cancelFeedback==nil;control.reason=list.cancelFeedback and list.cancelFeedback.reason or false
 control.after=F.snapshot(state);control.tailQueued=false
 for _,action in ipairs(q().queue)do if action==actions.tail then control.tailQueued=true end end
 assert(control.accepted and control.tailQueued,'real active cancel rejected or removed independent tail')
 evidence.control=control;panel:removeFromUIManager();observeCancelStop('after-release')
end
local function keepBlocked()
 local debts=T.ActionQueueExecution.blockedReturns(getPlayer());if #debts==0 then return end
 assert(#debts==1 and debts[1].itemId==ids.items.razor.id and debts[1].state=='blocked','origin failure lost exact live razor debt')
 if not evidence.blocked then
  local tail=tracks[actions.tail]
  evidence.blocked={at=getTimestampMs(),debts=debts,snapshot=F.snapshot(state),tailRef=tail.actionRef,tailStarted=tail.started,tailProgress=tail.progress}
  local panel=ownedPanel();local selected=panel.returnEntries and panel.returnEntries[panel.returnIndex or 1]
  evidence.blocked.ui={source='ActionQueuePanel.KeepReturn',visible=panel:getIsVisible()and panel.keepReturnButton and panel.keepReturnButton:getIsVisible()or false,
   id=selected and selected.id or false,itemId=selected and selected.itemId or false}
  assert(evidence.blocked.ui.visible and evidence.blocked.ui.id==debts[1].id and evidence.blocked.ui.itemId==ids.items.razor.id,'exact blocked razor debt is absent from real footer')
  panel:removeFromUIManager()
  if actions.returned then
   local action=actions.returned;local attempt=tracks[action];local queued=false
   for _,candidate in ipairs(q().queue)do if candidate==action then queued=true end end
   evidence.blocked.returnAttempt={at=getTimestampMs(),actionRef=attempt.actionRef,nativeRef=tostring(action.action),
    reason=debts[1].reason,itemId=attempt.itemId,allocated=action.action~=nil,started=attempt.started,progress=attempt.progress,queued=queued,physical=F.transferSnapshot(state,'returned')}
  end
  raw('BLOCKED',{case=ids.case,observation=evidence.blocked})
 end
 if ids.case~='keep-return'or evidence.keep or not tracks[actions.tail].progress then return end
 local panel=ownedPanel();assert(panel:getIsVisible()and panel.keepReturnButton and panel.keepReturnButton:getIsVisible(),'real blocked return footer missing')
 local selected=assert(panel.returnEntries[panel.returnIndex or 1]);assert(selected.id==debts[1].id,'real Keep selected foreign debt')
 local button=panel.keepReturnButton;local before=F.snapshot(state)
 local receipt={source='ActionQueuePanel.KeepReturn',input='programmatic-press-callback',at=getTimestampMs(),id=selected.id,itemId=selected.itemId,
  visible=true,before=before,tailRef=tracks[actions.tail].actionRef,tailStarted=tracks[actions.tail].started,tailProgress=tracks[actions.tail].progress,queueActive=not empty()}
 button:onMouseDown(1,1);receipt.pressCaptured=button.returnId==selected.id
 panel:keepFailedReturn(button)
 receipt.after=F.snapshot(state);receipt.cleared=#T.ActionQueueExecution.blockedReturns(getPlayer())==0
 receipt.sameSnapshot=F.same(before,receipt.after);receipt.accepted=receipt.pressCaptured and receipt.cleared and receipt.sameSnapshot and not panel.returnRejected
 assert(receipt.pressCaptured and receipt.cleared and receipt.sameSnapshot and receipt.accepted and receipt.queueActive,'real Keep did not retire exact blocked debt without physical mutation')
 evidence.keep=receipt;raw('KEEP',{case=ids.case,observation=receipt});panel:removeFromUIManager()
end
local function observe()
 observeCancelStop('poll')
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
 -- Local animation can advance before Host admits the timed action.
 -- Use the same current Started receipt required by the grooming cancel policy.
 if row.progress and q().current==trim and (not isClient() or row.receipt
  and T.ActionQueueAcknowledgements.state(trim,row.receipt)=='started') then
  if ids.case=='cancel-active'and not evidence.control then cancelActive(trim,row)end
  if originCase()and not originRequestedAt then
   originRequestedAt=getTimestampMs()
   evidence.control={source='authority.ChangeOrigin',input='authority-command',at=originRequestedAt,requestedAt=originRequestedAt,
    trimRef=row.actionRef,trimNative=tostring(trim.action),trimDelta=trim:getJobDelta(),before=F.snapshot(state),accepted=false}
   request('ChangeOrigin')
  end
 end
 if originReceipt and not evidence.origin then
  evidence.origin=originReceipt;evidence.control.accepted=true;evidence.control.acceptedAt=originReceipt.at
  if isClient()and originReceipt.kind=='full'then
   local bag=assert(F.find(getPlayer(),ids.bag.id));local source=bag:getItemContainer();local razor=assert(F.find(getPlayer(),ids.items.razor.id))
   assert(q().current==trim and trim:isStarted()and trim:getJobDelta()>0 and trim:getJobDelta()<1 and bag:getFullType()==ids.bag.type
    and razor:getContainer()==getPlayer():getInventory()and getPlayer():getPrimaryHandItem()==razor,'capacity replica confirmation missed actual active trim')
   local replica={source='authority-confirmed-capacity',case=ids.case,at=getTimestampMs(),authorityAt=originReceipt.at,requestedAt=originRequestedAt,bagId=bag:getID(),itemId=razor:getID(),
    capacityBefore=source:getCapacity(),roomBefore=source:hasRoomFor(getPlayer(),razor),trimRef=row.actionRef,trimNative=tostring(trim.action),trimDelta=trim:getJobDelta(),before=F.snapshot(state)}
   assert(originReceipt.authority==true and originReceipt.capacityAfter==0 and originReceipt.roomAfter==false and replica.capacityBefore>0 and replica.roomBefore,'capacity authority/replica intervention mismatch')
   -- ItemContainer capacity is fixture-local data; mirror only the exact authoritative intervention, as the native wring fixture does.
   source:setCapacity(0);replica.capacityAfter=source:getCapacity();replica.roomAfter=source:hasRoomFor(getPlayer(),razor);replica.after=F.snapshot(state)
   replica.unchanged=F.same(replica.before,replica.after);assert(replica.capacityAfter==0 and not replica.roomAfter and replica.unchanged,'full origin replica did not preserve exact native inventory')
   evidence.originReplica=replica;raw('ORIGIN_REPLICA',replica)
  end
  raw('CONTROL',{case=ids.case,observation=evidence.control});raw('ORIGIN_CLIENT',originReceipt)
 end
 if originCase()then keepBlocked()end
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
   PZAPI.ModOptions:getOptions('PZSurvivorToolkit'):getOption('ActionQueue'):setValue(not editorOff)
   assert(Razor.install()and Razor.enabled(),'real Razor.install consumer did not install')
   player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false);getCore():setOptionAutoDrink(false);getCore():setOptionPauseOnFocusloss(false)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
   menu,cutMenu,primaryMenu=ISCharacterScreen.onTrimBeard,ISCharacterScreen.onCutHair,ISInventoryPaneContextMenu.OnPrimaryWeapon
   nativeMethods={}
   for _,class in ipairs({ISInventoryTransferAction,ISEquipWeaponAction,ISTrimBeard,ISCutHair,ISReadABook})do
    local methods={};for name,callback in pairs(class)do if type(callback)=='function'then methods[name]=callback end end;nativeMethods[class]=methods
   end
   ready=true;emit({event='setup',cases=config.cases,nativeDurations=true,provider='native-returns',installed=true});since=getTimestampMs()
  end
  checkEditor();if editorOff and phase=='running'then editorTicks=editorTicks+1 end
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
   if F.returnedCase(ids.case)then
    assert(actions.restore and actions.returned and #debts==0 and not evidence.explicitRequested,'ordinary producer restore/return missing')
    if ids.case=='cancel-active'then assert(evidence.control and evidence.control.nativeStop and evidence.control.nativeStop.after,'exact native trim cancellation was not observed before cleanup')end
   elseif ids.case=='new-primary-intent'then
    assert(evidence.explicitRequested and actions.explicitEquip and not actions.restore and not actions.returned,
     'new primary intent allowed old restore or borrowed return construction')
    assert(#debts==1 and debts[1].itemId==ids.items.razor.id and debts[1].state=='blocked','new primary intent lost exact unpaid razor debt')
   else
    assert(evidence.origin and evidence.blocked and actions.restore and not evidence.explicitRequested,'origin change lost authority receipt, restored hammer, or visible debt')
    if ids.case=='keep-return'then assert(evidence.keep and #debts==0,'real Keep did not retire exact debt')
    else assert(#debts==1 and debts[1].itemId==ids.items.razor.id and debts[1].state=='blocked','unpaid blocked razor debt missing')end
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
   evidence.actions=published;evidence.after=client;observeEditor('after-completion')
   emit({event='case',id=ids.case,status='passed',ids=ids,clientPlacement=placementProof,client=client,server=receipt,evidence=evidence})
   if not isClient()then previous=authority end
   index=index+1
   if not config.cases[index]then emit({event='complete',cases=config.cases,performed=index-1,failed=0,skipped=0});raw('COMPLETE',{cases=config.cases});done=true;return end
   for _,debt in ipairs(T.ActionQueueSettlement.blockedReturns(player))do assert(T.ActionQueueExecution.keepReturn(player,debt.id),'explicit fixture debt retirement refused')end
   state,authority,ids,receipt,placement,placing,placementProof,quiet=nil,nil,nil,nil,nil,nil,nil,nil
   originReceipt,originRequestedAt=nil,nil
   actions,tracks,order,evidence={},{},{},{};phase='prepare';since=getTimestampMs()
  end
 end)
 if not ok then fail(reason)end
end)
