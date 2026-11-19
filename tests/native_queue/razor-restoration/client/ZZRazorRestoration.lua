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
local handDelay=config.options and config.options.razor_hand_ack_delay_ms~=nil
local handAuthority
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
local state,authority,previous,ids,receipt,placement,placing,placementProof,quiet,beltRequested,beltTraceAt,beltClientWorn,beltClientConfigured
local evidence,actions,tracks,order={},{},{},{}
local menu,cutMenu,primaryMenu,nativeMethods
local originReceipt,originRequestedAt,heavyReceipt,heavyRequestedAt
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
 if F.beltCase(ids.case)and action.Type=='ISDetachItemHotbar'then return 'slotDetach'end
 if F.beltCase(ids.case)and action.Type=='ISAttachItemHotbar'then return 'slotAttach'end
 if F.heavyCase(ids.case)and action.Type=='ISInventoryTransferAction'and action.item and action.item:getID()==ids.items.previous.id then return'heavyPickup'end
 if action.Type=='ISInventoryTransferAction'and action.item and action.item:getID()==ids.items.razor.id then
  return action.destContainer==getPlayer():getInventory()and'pickup'or'returned'
 end
 if ids.case=='empty-primary'and action.Type=='ISUnequipAction'and action.item and action.item:getID()==ids.items.razor.id then return 'restore'end
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
   assert(F.cancelCase(ids.case)and evidence.control and row.role=='command'and not row.operationTransition
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
  constructorDuration=action.maxTime,fromHotbar=action.fromHotbar==true,hairStyle=action.Type=='ISCutHair'and action.hairStyle or nil,sourceRef=action.srcContainer and tostring(action.srcContainer)or false,allocated=false,started=false,progress=false,events={},ack={},transfers={}}
 if action.Type=='ISEquipWeaponAction'then row.equipPrimary=action.primary==true;row.equipTwoHands=action.twoHands==true end
 row.actor,row.queue,row.root,row.item,row.operation=action.character,q(),action.character:getInventory(),action.item,action.toolkitQueueOperation
 row.source,row.destination=action.srcContainer,action.destContainer
 tracks[action]=row;order[#order+1]=row
 raw('ACTION',{case=ids.case,action={role=name,type=row.type,actionRef=row.actionRef,itemId=row.itemId,constructorDuration=row.constructorDuration,fromHotbar=row.fromHotbar,hairStyle=row.hairStyle,equipPrimary=row.equipPrimary,equipTwoHands=row.equipTwoHands}})
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
 elseif not isClient()or(row.role~='pickup'and row.role~='returned'and row.role~='heavyPickup')then
  error(row.role..'/'..boundary..': missing exact native item')
 else
  local physical=F.transferSnapshot(state,row.role)
  local tx=action.transactionId
  local terminal=type(tx)=='number'and tx~=0 and isItemTransactionDone(tx)
  assert(physical.canonical and((physical.sourceCount==0 and physical.destinationCount==1 and terminal)or row.transferDone),row.role..'/'..boundary..': nil item without exact completed transfer/physical effect')
  exact=true
 end
 if current~=nil and row.role~='pickup'and row.role~='returned'and row.role~='heavyPickup'and action.action and q().current==action and action:isStarted()then
  assert(current==canonical,row.role..'/'..boundary..': started item is not exact current canonical replica')
 end
 return{exact=exact,state=current==nil and'nil'or current==original and'original'or'canonical-replica',canonical=current==canonical}
end
local function transferObservation(action,row,boundary)
 if row.role~='pickup'and row.role~='returned'and row.role~='heavyPickup'then return end
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
 if not isClient()or not action.action or row.role=='pickup'or row.role=='returned'or row.role=='heavyPickup'then return end
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
  local row=track(action)
  if F.restoreBoundaryCase(ids.case)and row.role=='returned'then
   local restore=assert(actions.restore);acknowledge(restore,assert(tracks[restore]))
  end
  row.admittedAt=getTimestampMs();observeEditor('native-admission',action)
  if F.restoreBoundaryCase(ids.case)and row.role=='returned'then
   local restore=assert(actions.restore);local restored=assert(tracks[restore])
   evidence.restoreBoundary={at=getTimestampMs(),actionRef=restored.actionRef,nativeRef=tostring(restore.action),
    returnRef=row.actionRef,snapshot=F.snapshot(state)}
   raw('RESTORE_BOUNDARY',{case=ids.case,observation=evidence.restoreBoundary})
  end
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
 local args={case=config.cases[index],placement=placement,clientPlacement=placementProof,requestedAt=command=='ChangeHeavy'and heavyRequestedAt or originRequestedAt}
 if isClient()then sendClientCommand('RazorRestorationTest',command,args)
 elseif command=='Prepare'then authority=F.prepare(getPlayer(),args.case,placement,placementProof,previous);previous=nil;ids=authority.ids;if not F.beltCase(ids.case)then raw('PREPARED',ids)end
 elseif command=='ChangeHeavy'then heavyReceipt=F.removeHeavy(authority,heavyRequestedAt);raw('HEAVY_REMOVED',heavyReceipt)
 elseif command=='ChangeOrigin'then originReceipt=F.changeOrigin(authority,originRequestedAt);raw('ORIGIN',originReceipt)
 else receipt=assert(F.verify(authority),'SP exact physical authority differs');receipt.transfers=authority.transfers or{};receipt.heavyTransitions=authority.heavy or{};raw('VERIFIED',receipt)end
end
Events.OnServerCommand.Add(function(module,command,args)
 if module~='RazorRestorationTest'or done then return end
 if command=='Failed'then fail(args.error)
 elseif args and args.case==config.cases[index]then
  if command=='Prepared'or command=='BeltConfigured'then ids=args elseif command=='Verified'then receipt=args elseif command=='OriginChanged'then originReceipt=args elseif command=='HeavyChanged'then heavyReceipt=args end
 end
end)
local function callbacksUnchanged()
 if ISCharacterScreen.onTrimBeard~=menu or ISCharacterScreen.onCutHair~=cutMenu or ISInventoryPaneContextMenu.OnPrimaryWeapon~=primaryMenu then return false end
 for class,methods in pairs(nativeMethods)do for name,callback in pairs(methods)do if class[name]~=callback then return false end end end
 return true
end
local function beltWaiting(gate,details)
 if beltTraceAt and getTimestampMs()-beltTraceAt<2000 then return end
 beltTraceAt=getTimestampMs();details=details or{};details.case=ids.case;details.gate=gate;raw('BELT_READY',details)
end
local function beltReady()
 if not F.beltCase(ids.case)then return true end
 local player=getPlayer();local tool=F.find(player,ids.items.razor.id);local belt=F.find(player,ids.items.belt.id)
 if not tool or not belt then
  beltWaiting('replicated-items',{tool=tool and tool:getID()or false,expectedTool=ids.items.razor.id,belt=belt and belt:getID()or false,expectedBelt=ids.items.belt.id});return false
 end
 local root=player:getInventory()
 if root:getItemById(tool:getID())~=tool or tool:getContainer()~=root or root:getItemById(belt:getID())~=belt or belt:getContainer()~=root then
  beltWaiting('canonical-root',{toolRoot=tool:getContainer()==root,beltRoot=belt:getContainer()==root});return false
 end
 if isClient()and not beltClientWorn then
  assert(phase=='prepared'and empty(),'client belt fixture setup escaped pre-menu boundary')
  -- Match the qualified equipment fixture: disposable replica setup uses the
  -- authority-created exact root provider before discovering its actual slots.
  player:setWornItem(belt:getBodyLocation(),belt);beltClientWorn=true
 end
 if player:getWornItem(belt:getBodyLocation())~=belt then
  local worn=player:getWornItem(belt:getBodyLocation())
  beltWaiting('provider-worn',{expected=belt:getID(),worn=worn and worn:getID()or false,sameReference=worn==belt});return false
 end
 local bar=getPlayerHotbar(player:getPlayerNum());if not bar then beltWaiting('native-hotbar');return false end
 bar:refresh();bar:reloadIcons()
 local index=bar:getThisSlotIndex('SmallBeltLeft');local slot=index and bar.availableSlot[index]
 local definition=slot and slot.def
 local mapped=definition and definition.attachments and definition.attachments[tool:getAttachmentType()]
 if not index or not definition or definition.type~='SmallBeltLeft'or slot.slotType~='SmallBeltLeft'or mapped~='Belt Left Screwdriver'then
  error('native left belt slot unavailable or incompatible: '..JSON.encode({index=index or false,kind=definition and definition.type or false,map=mapped or false}))
 end
 if not ids.beltConfigured then
  beltWaiting('authority-configure',{requested=beltRequested==true,index=index})
  if not beltRequested then
   beltRequested=true
   if isClient()then sendClientCommand('RazorRestorationTest','ConfigureBelt',{case=ids.case,slotIndex=index})
   else ids=F.configureBelt(authority,index);raw('PREPARED',ids)end
  end
  return false
 end
 if isClient()and not beltClientConfigured then
  assert(phase=='prepared'and empty()and index==ids.beltIndex,'replica belt configuration escaped confirmed authority setup')
  assert(ids.baseline.belt.tool.id==tool:getID()and ids.baseline.belt.tool.slot==index
   and ids.baseline.belt.provider==belt:getID(),'authority exact belt baseline differs from replica setup')
  -- Native attach(..., false) is disposable initial fixture setup only. No
  -- hand, ownership or attachment repair is permitted after the real menu.
  bar:attachItem(tool,mapped,index,definition,false);bar:reloadIcons();beltClientConfigured=true
 end
 local Belt=require 'PZSurvivorToolkit/ActionQueueBeltTool';local captured=Belt.capture(player,tool)
 local ready=index==ids.beltIndex and tool:getAttachedSlot()==index and tool:getAttachedSlotType()=='SmallBeltLeft'
  and tool:getAttachedToModel()==mapped and bar.attachedItems[index]==tool and bar:isItemAttached(tool)
  and player:getAttachedItem(mapped)==tool and captured~=nil
 if not ready and(not beltTraceAt or getTimestampMs()-beltTraceAt>2000)then
  beltTraceAt=getTimestampMs()
  raw('BELT_READY',{case=ids.case,index=index,expected=ids.beltIndex,slot=tool:getAttachedSlot(),kind=tool:getAttachedSlotType()or false,
   model=tool:getAttachedToModel()or false,map=mapped,cache=bar.attachedItems[index]and bar.attachedItems[index]:getID()or false,
   physical=player:getAttachedItem(mapped)and player:getAttachedItem(mapped):getID()or false,class=getClassSimpleName(tool),
   canonical=player:getInventory():getItemById(tool:getID())==tool,enabled=Razor.enabled(player)==true,captured=captured~=nil,
   nativeGetter=Proof.closure(getPlayerHotbar,'ISPlayerData.lua')==true,nativeAttached=Proof.closure(ISHotbar.isItemAttached,'ISHotbar.lua')==true,
   nativeAnimate=Proof.closure(ISHotbar.setAttachAnim,'ISHotbar.lua')==true})
 end
 return ready
end
local function produce()
 assert(empty()and F.same(F.snapshot(state),ids.baseline),'native producer baseline differs')
 assert(beltReady(),'exact native belt cache/slot not ready at menu boundary')
 actions,tracks,order={},{},{}
 local cut=ids.case=='cut-hair-scissors'
 evidence={before=F.snapshot(state),producer=cut and'ISCharacterScreen.onCutHair'or'ISCharacterScreen.onTrimBeard',target=cut and ids.targetHair or ids.targetBeard,installed=Razor.enabled()==true,
  explicitRequested=false,initialRevision=T.ActionQueueTidyIntent.primaryRequestRevision(getPlayer())}
 if editorOff then evidence.editor={};editorTicks=0;observeEditor('before-producer')end
 assert(evidence.initialRevision~=nil,'own primary intent tracking unavailable')
 local previous=assert(F.find(getPlayer(),ids.items.previous.id))
 local hands=T.ActionQueueEquip.restorationHands(getPlayer())
 if ids.case=='empty-primary'then
  evidence.handSeed={primary=false,secondary=previous:getID(),type=previous:getFullType(),requiresBoth=previous:isRequiresEquippedBothHands(),
   handWeapon=instanceof(previous,'HandWeapon'),supportsTwo=instanceof(previous,'HandWeapon')and previous:isTwoHandWeapon()or false,
   ordinary=hands~=nil and hands.primary==false and hands.secondary and hands.secondary.item==previous}
 else
 evidence.handSeed={id=previous:getID(),type=previous:getFullType(),requiresBoth=previous:isRequiresEquippedBothHands(),
  handWeapon=instanceof(previous,'HandWeapon'),supportsTwo=instanceof(previous,'HandWeapon')and previous:isTwoHandWeapon()or false,
  ordinary=hands~=nil and hands.primary~=nil and hands.primary.item==previous}
  if F.equipmentCase(ids.case)then
   local secondary=assert(F.find(getPlayer(),(ids.items.secondary or ids.items.previous).id))
   evidence.handSeed.secondary=secondary:getID()
   evidence.handSeed.ordinary=evidence.handSeed.ordinary and hands.secondary and hands.secondary.item==secondary
  end
 end
 if F.mandatoryCase(ids.case)or F.heavyCase(ids.case)then
  evidence.handSeed.forceDropHeavy=previous:isForceDropHeavyItem()
  assert(evidence.handSeed.forceDropHeavy==F.heavyCase(ids.case),'fixture force-drop contract differs')
 end
 local weapon=F.axeCase(ids.case)or F.mandatoryType(ids.case)=='Base.WoodAxe'
 if F.heavyCase(ids.case)then
  local player=getPlayer();local captured=T.ActionQueueHeavyPickup.capture(player)
  evidence.handSeed.ordinaryUnavailable=hands==nil
  evidence.handSeed.heavy={captured=captured~=nil,actorSame=captured and captured.actor==player or false,
   rootSame=captured and captured.root==player:getInventory()or false,itemSame=captured and captured.item==previous or false,
   id=captured and captured.id or false,type=captured and captured.fullType or false,
   squareSame=captured and captured.square==player:getCurrentSquare()or false,
   primarySame=player:getPrimaryHandItem()==previous,secondarySame=player:getSecondaryHandItem()==previous,
   position={x=player:getX(),y=player:getY(),z=player:getZ()},
   square={x=player:getCurrentSquare():getX(),y=player:getCurrentSquare():getY(),z=player:getCurrentSquare():getZ()}}
  raw('HAND_SEED',{case=ids.case,observation=evidence.handSeed})
  local heavy=evidence.handSeed.heavy
  assert(evidence.handSeed.ordinary==false and evidence.handSeed.ordinaryUnavailable and heavy.captured
   and heavy.actorSame and heavy.rootSame and heavy.itemSame and heavy.squareSame and heavy.primarySame and heavy.secondarySame
   and heavy.id==ids.items.previous.id and heavy.type==ids.items.previous.type,
   'authority initial heavy item lacks exact native Heavy.capture and shared grips')
 else
  assert(evidence.handSeed.ordinary,'authority initial primary is outside the exact ordinary restoration topology')
 end
 assert(evidence.handSeed.requiresBoth==(F.mandatoryCase(ids.case)or F.heavyCase(ids.case))and evidence.handSeed.supportsTwo==weapon,
  'authority initial item mandatory/optional both-hands contract differs')
 phase='running'
 if cut then ISCharacterScreen.onCutHair(getPlayer(),ids.targetHair,300)
 else ISCharacterScreen.onTrimBeard(getPlayer(),ids.targetBeard)end
 for _,action in ipairs(q().queue)do track(action)end
 assert((F.beltCase(ids.case)or actions.pickup)and actions.preparationEquip and actions.trim,'actual razor menu did not produce native pickup/equip/trim')
 local queue=q();local list=queue.queue;local prefix=actions.approach and 1 or 0
 local expected=F.beltCase(ids.case)and{'preparationEquip','trim','command'}or prefix==1 and {'approach','pickup','preparationEquip','trim','command'}or{'pickup','preparationEquip','trim','command'}
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
handAuthority=require('QueueRazorHandAuthority').install(config,{
 current=function()
  local action=actions.restore
  if not action then return end
  return action,assert(tracks[action]),actions.tail,assert(tracks[actions.tail]),state
 end,
 queue=q,snapshot=function()return F.snapshot(state)end,panel=ownedPanel,evidence=function()return evidence end,
 emit=function(marker,row)raw(marker,{case=ids.case,observation=row})end,
})
local function cancellationState(trim,row,boundary)
 local player=getPlayer()
 return{at=getTimestampMs(),boundary=boundary,actionRef=row.actionRef,nativeRef=tostring(trim.action),
  actionSame=actions.trim==trim,nativeSame=trim.action==row.native,actorSame=trim.character==row.actor and player==row.actor,
  queueSame=ISTimedActionQueue.queues[row.actor]==row.queue and q()==row.queue,rootSame=player:getInventory()==row.root,
  member=player:getCharacterActions():contains(row.native),current=q().current==trim,beard=player:getHumanVisual():getBeardModel()or''}
end
observeCancelStop=function(boundary,nextAction)
 local control=evidence.control
 if not ids or not F.cancelCase(ids.case)or not control or not control.nativeStop or control.nativeStop.after or control.accepted~=true then return end
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
 if handAuthority then handAuthority.poll()end
 local trim=actions.trim;local row=tracks[trim]
 -- Local animation can advance before Host admits the timed action.
 -- Use the same current Started receipt required by the grooming cancel policy.
 if row.progress and q().current==trim and (not isClient() or row.receipt
  and T.ActionQueueAcknowledgements.state(trim,row.receipt)=='started') then
  if(F.oneHandedCase(ids.case)or F.mandatoryCase(ids.case)or F.heavyCase(ids.case))and not evidence.preparationBoundary then
   local prepared=assert(actions.preparationEquip);local equipped=assert(tracks[prepared])
   evidence.preparationBoundary={at=getTimestampMs(),actionRef=equipped.actionRef,nativeRef=tostring(prepared.action),
    groomingRef=row.actionRef,groomingNative=tostring(trim.action),groomingDelta=trim:getJobDelta(),snapshot=F.snapshot(state)}
   raw('PREPARATION_BOUNDARY',{case=ids.case,observation=evidence.preparationBoundary})
  end
  if F.unavailableHeavy(ids.case)and not heavyRequestedAt then
   heavyRequestedAt=getTimestampMs();request('ChangeHeavy')
  end
  if F.cancelCase(ids.case)and not evidence.control then cancelActive(trim,row)end
  if originCase()and not originRequestedAt then
   originRequestedAt=getTimestampMs()
   evidence.control={source='authority.ChangeOrigin',input='authority-command',at=originRequestedAt,requestedAt=originRequestedAt,
    trimRef=row.actionRef,trimNative=tostring(trim.action),trimDelta=trim:getJobDelta(),before=F.snapshot(state),accepted=false}
   request('ChangeOrigin')
  end
 end
 if heavyReceipt and not evidence.heavyRemoval then
  evidence.heavyRemoval=heavyReceipt;raw('HEAVY_REMOVAL_CLIENT',heavyReceipt)
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
 if ids.case=='belt-scissors-replace'and row.progress and q().current==trim and not evidence.replacement then
  if isClient()and(not row.receipt or T.ActionQueueAcknowledgements.state(trim,row.receipt)~='started')then return end
  local bar=assert(getPlayerHotbar(getPlayer():getPlayerNum()));bar:refresh();bar:reloadIcons()
  local slot=assert(bar.availableSlot[ids.beltIndex]);local replacement=assert(F.find(getPlayer(),ids.items.replacement.id))
  assert(slot.def.type=='SmallBeltLeft'and slot.def.attachments[replacement:getAttachmentType()]=='Belt Left Screwdriver')
  local before=F.snapshot(state);bar:attachItem(replacement,'Belt Left Screwdriver',ids.beltIndex,slot.def,true)
  for _,action in ipairs(q().queue)do track(action)end
  assert(actions.slotDetach and actions.slotAttach and not actions.slotDetach.action and not actions.slotAttach.action)
  evidence.replacement={at=getTimestampMs(),source='ISHotbar.attachItem',before=before,after=F.snapshot(state),trimRef=row.actionRef,trimNative=tostring(trim.action),trimDelta=trim:getJobDelta(),detachRef=tracks[actions.slotDetach].actionRef,attachRef=tracks[actions.slotAttach].actionRef}
  raw('REPLACEMENT',{case=ids.case,observation=evidence.replacement})
 end
 if F.intentCase(ids.case)and row.progress and q().current==trim and not evidence.explicitRequested then
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
   if not F.beltCase(config.cases[index])then assert(Razor.install()and Razor.enabled(),'real Razor.install consumer did not install')else assert(Razor.enabled(),'shipped grooming activation unavailable')end
   player:setGodMod(true);player:setGhostMode(true);player:setAutoDrink(false);getCore():setOptionAutoDrink(false);getCore():setOptionPauseOnFocusloss(false)
   if SurvivalGuide and SurvivalGuide.instance then SurvivalGuide.instance:setVisible(false)end
   menu,cutMenu,primaryMenu=ISCharacterScreen.onTrimBeard,ISCharacterScreen.onCutHair,ISInventoryPaneContextMenu.OnPrimaryWeapon
   nativeMethods={}
   for _,class in ipairs({ISInventoryTransferAction,ISEquipWeaponAction,ISUnequipAction,ISTrimBeard,ISCutHair,ISReadABook})do
    local methods={};for name,callback in pairs(class)do if type(callback)=='function'then methods[name]=callback end end;nativeMethods[class]=methods
   end
   ready=true;emit({event='setup',cases=config.cases,nativeDurations=true,provider='native-returns',installed=true});since=getTimestampMs()
  end
  checkEditor();if editorOff and phase=='running'then editorTicks=editorTicks+1 end
  assert(getTimestampMs()-since<120000,'razor restoration timeout '..phase)
  if authority and not isClient()then
   local transfer=F.observeTransferAuthority(authority);if transfer then raw('TRANSFER_AUTHORITY',transfer)end
   local heavy=F.observeHeavyAuthority(authority);if heavy then raw('HEAVY_AUTHORITY',heavy)end
  end
  if phase=='prepare'then
   assert(empty());placement=placement or P.choose(player);placing=placing or P.beginCentered(player,placement);placementProof=P.poll(placing);if not placementProof then return end
   raw('CLIENT_PLACEMENT',{case=config.cases[index],proof=placementProof});phase='prepared';request('Prepare')
  elseif phase=='prepared'and ids then
   if not beltReady()then return end
   state=F.resolve(player,ids);if not state then
    if F.beltCase(ids.case)then
     local missing={};for name,spec in pairs(ids.items)do if not F.find(player,spec.id)then missing[#missing+1]=name..':'..tostring(spec.id)end end
     local primary=player:getPrimaryHandItem();local secondary=player:getSecondaryHandItem();local bag=F.find(player,ids.bag.id)
     beltWaiting('baseline-resolve',{missing=missing,primary=primary and primary:getID()or false,expectedPrimary=ids.baseline.primary,
      secondary=secondary and secondary:getID()or false,expectedSecondary=ids.baseline.secondary,beard=player:getHumanVisual():getBeardModel(),
      bagWorn=bag and player:getWornItems():contains(bag)or false})
    end
    return
   end
   local pane=assert(getPlayerInventory(player:getPlayerNum()));pane:refreshBackpacks();local available=false
   local bag=F.find(player,ids.bag.id)
   for _,entry in ipairs(pane.backpacks)do if entry.inventory==bag:getItemContainer()then available=true end end
   if available then produce()end
  elseif phase=='running'then
   observe();if not empty()then return end
   assert(actions.trim and tracks[actions.trim].started and tracks[actions.trim].progress,'real native trim did not progress')
   assert(actions.tail and tracks[actions.tail].started and tracks[actions.tail].progress,'independent native reader did not progress')
   local debts=T.ActionQueueSettlement.blockedReturns(player)
   if F.beltCase(ids.case)then
    assert(not actions.pickup and not actions.returned and #debts==0,'belt tool created inventory loan/debt')
    if ids.case=='belt-scissors-replace'then assert(evidence.replacement and actions.slotAttach and actions.slotDetach ,'newer native slot intent lost native actions')
    else assert(actions.restore,'belt grooming hand restoration missing')end
    if F.cancelCase(ids.case)then assert(evidence.control and evidence.control.nativeStop.after,'belt active cancel lacked native stop')end
   elseif handDelay then
    evidence.handAuthority=handAuthority.complete()
    assert(actions.restore and not actions.returned and #debts==0,'hand Keep constructed a location return or lost debt retirement')
   elseif F.returnedCase(ids.case)then
    assert((not F.heavyCase(ids.case)or actions.heavyPickup)and actions.restore and actions.returned and #debts==0 and not evidence.explicitRequested,'ordinary producer restore/return missing')
    if F.cancelCase(ids.case)then assert(evidence.control and evidence.control.nativeStop and evidence.control.nativeStop.after,'exact native trim cancellation was not observed before cleanup')end
   elseif F.unavailableHeavy(ids.case)then
    assert(evidence.heavyRemoval and not actions.heavyPickup and not actions.restore and not actions.returned,'unavailable heavy recovery constructed native work')
    assert(#debts==1 and debts[1].itemId==ids.items.razor.id and debts[1].state=='blocked','unavailable heavy lost exact unpaid razor debt')
   elseif F.intentCase(ids.case)then
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
   originReceipt,originRequestedAt,heavyReceipt,heavyRequestedAt,beltRequested,beltTraceAt,beltClientWorn,beltClientConfigured=nil,nil,nil,nil,nil,nil,nil,nil
   actions,tracks,order,evidence={},{},{},{};phase='prepare';since=getTimestampMs()
  end
 end)
 if not ok then fail(reason)end
end)
