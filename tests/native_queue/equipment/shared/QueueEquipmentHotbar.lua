local Hotbar={}
function Hotbar.isCase(id)return id=='tidy-hotbar'end
local watched,installed
function Hotbar.watch(state)watched=state end
function Hotbar.observeLine(state,line)
 if not state or type(line)~='string'then return end
 local actor,session,message=line:match('^%[P4TidyUpMeister%]%[P(%d+)%]%[S([%d%-]+)%] (.+)$')
 if tonumber(actor)~=state.player:getPlayerNum()then return end
 local proof=state.hotbarP4
 if session=='-'then
  local completed=tonumber(message:match('^restore queue complete S(%d+)$'))
  if proof and proof.restore and completed==proof.session then proof.completed=true end
  return
 end
 session=tonumber(session);if not session or session<=0 then return end
 if message=='capture primary=nil secondary=nil'then
  if proof then proof.problem='duplicate P4 hotbar capture';return end
  proof={session=session};state.hotbarP4=proof
 end
 if not proof or proof.session~=session then return end
 if message:match('^capture worn=%[.-%] inventoryCount=%d+$')then proof.worn=true end
 local item=state.pickup:getFullType()..'#'..state.pickup:getID()..'@'..state.root:getType()
 if message:find('^add%[%w+%] type=ISEquipWeaponAction item=')and message:find(item,1,true)then proof.equip=true end
 if message:find('^add%[%w+%] type=ISRackFirearm item=nil$')then proof.producer=true end
 local trace='ISReadABook -> ISEquipWeaponAction -> ISRackFirearm -> ISReadABook'
 if message:find('^finish ')then
  proof.finished=message:find('finish armed=true cancelled=false prep=true transfer=false operation=true',1,true)~=nil
   and message:find('restoreHands=true restoreWorn=false',1,true)~=nil
   and message:find('actionTotal=4 transferCount=0',1,true)~=nil and message:find('trace=['..trace..']',1,true)~=nil
 end
 if message:find('^RESTORE actionTotal=')then
  if proof.restore or not proof.worn or not proof.equip or not proof.producer or not proof.finished
   or not message:find('RESTORE actionTotal=4 trace=['..trace..']',1,true)then proof.problem='P4 hotbar restore lacks exact native rack session' end
  proof.restore=true
 end
end
function Hotbar.install(withP4)
 if installed or not withP4 then return end
 local options=assert(PZAPI.ModOptions:getOptions('P4TidyUpMeister'),'P4 options unavailable')
 assert(options:getOption('DebugOutput'),'P4 debug option unavailable').selected=2
 local original=print
 print=function(...)
  if select('#',...)==1 then Hotbar.observeLine(watched,(...))end
  return original(...)
 end
 installed=true
end
function Hotbar.prepare(state,seed)
 seed('pickup','Base.Shotgun')
 local player,item=state.player,state.pickup
 assert(item:getAttachmentType()=='Rifle' and not item:canBeActivated()and not isForceDropHeavyItem(item)
  and not player:getWornItems():contains(item)and item:getCurrentAmmoCount()==0 and not item:isRoundChambered(),
  'ordinary nonactivated nonworn nonheavy empty Rifle fixture required')
 state.hotbarIndex,state.hotbarType,state.hotbarLocation=1,'Back','Rifle On Back with Bag'
 state.originalAttached={}
 local entries=player:getAttachedItems()
 for i=0,entries:size()-1 do
  local entry=entries:get(i);local other=entry:getItem()
  if other~=item then
   assert(other:getAttachedSlot()~=state.hotbarIndex and tostring(entry:getLocation())~=state.hotbarLocation,
    'fresh fixture requires a vacant native Back slot/model')
   state.originalAttached[tostring(entry:getLocation())]=other
  end
 end
 player:setPrimaryHandItem(nil);player:setSecondaryHandItem(nil)
 player:setAttachedItem(state.hotbarLocation,item)
 item:setAttachedSlot(state.hotbarIndex);item:setAttachedSlotType(state.hotbarType);item:setAttachedToModel(state.hotbarLocation)
 if not isServer()then
  local hotbar=assert(getPlayerHotbar(player:getPlayerNum()));hotbar:refresh();hotbar:reloadIcons()
  local slot=assert(hotbar.availableSlot[state.hotbarIndex],'native Back slot missing')
  assert(slot.def.type==state.hotbarType and slot.def.attachments.Rifle=='Rifle On Back'
   and hotbar.replacements and hotbar.replacements.Rifle==state.hotbarLocation
   and hotbar.attachedItems[state.hotbarIndex]==item,'native Rifle Back definition/replacement/icon differs')
 end
end
function Hotbar.enqueue(state,helpers)
 local queue=helpers.queue();local before=#queue.queue
 helpers.run(ISInventoryPaneContextMenu.onRackGun,state.player,state.pickup)
 assert(#queue.queue==before+2,'native root hotbar rack must enqueue only equip and rack')
 local equip,rack=queue.queue[before+1],queue.queue[before+2]
 assert(equip.Type=='ISEquipWeaponAction'and equip.item==state.pickup and equip.primary and equip.twoHands
  and equip.fromHotbar and equip.hotbar==getPlayerHotbar(state.player:getPlayerNum())and equip.maxTimeInit==50
  and type(equip.maxTime)=='number'and equip.maxTime>1 and equip.maxTime<math.huge
  and equip.create==ISBaseTimedAction.create and equip.adjustMaxTime==ISBaseTimedAction.adjustMaxTime
  and equip.animEvent==ISEquipWeaponAction.animEvent,'native fromHotbar equip differs')
 assert(rack.Type=='ISRackFirearm'and rack.gun==state.pickup,'native hotbar rack callback missing')
 state.hotbarEquip,state.rackAction=equip,rack
end
function Hotbar.observe(state,queue,toolkit,tidy)
 local current=queue.current
 if current==state.rackAction and current:isStarted()then state.hotbarProducerStarted=true end
 for _,action in ipairs(queue.queue)do
  if getmetatable(action)==ISUnequipAction and action.item and action.item:getID()==state.pickup:getID()then
   local nativeHotbar=action.hotbar==getPlayerHotbar(state.player:getPlayerNum())
   local nativeAnim=action.animEvent==ISUnequipAction.animEvent
   local nativeCreate=action.create==ISBaseTimedAction.create
   local nativeAdjust=action.adjustMaxTime==ISBaseTimedAction.adjustMaxTime
   assert(tidy and action.Type=='ISUnequipAction'and action.fromHotbar==true and action.reason==nil
    and nativeHotbar and action.maxTimeInit==50 and type(action.maxTime)=='number'and action.maxTime>1 and action.maxTime<math.huge
    and nativeAnim and nativeCreate and nativeAdjust,
    'unexpected P4 hotbar cleanup/native fields tidy='..tostring(tidy)..' Type='..tostring(action.Type)
     ..' fromHotbar='..tostring(action.fromHotbar)..' reason='..tostring(action.reason)..' hotbar='..tostring(nativeHotbar)
     ..' maxTime='..tostring(action.maxTime)..' maxTimeInit='..tostring(action.maxTimeInit)..' animEvent='..tostring(nativeAnim)
     ..' create='..tostring(nativeCreate)..' adjustMaxTime='..tostring(nativeAdjust))
   if state.hotbarRestoreDuration~=action.maxTime then
    state.hotbarRestoreDuration=action.maxTime
    print('[EQUIPMENT_TEST] HOTBAR_TIMING case='..state.id..' maxTimeInit='..action.maxTimeInit..' maxTime='..action.maxTime)
   end
   local source=state.hotbarP4
   assert(source and source.restore and not source.problem,'hotbar cleanup lacks exact source-owned P4 session')
   assert(not state.hotbarRestoreAction or state.hotbarRestoreAction==action,'P4 queued duplicate hotbar restores')
   state.hotbarRestoreAction=action
   if toolkit.Settings.actionQueue()then
    local _,kind=toolkit.ActionQueueDefinitions.inspect(action)
    assert(kind=='compat.tidy-equipment','P4 hotbar cleanup lacks verified scoped origin')
   end
   if isClient()and not state.hotbarRestoreReceipt then state.hotbarRestoreReceipt=toolkit.ActionQueueAcknowledgements.capture(action)end
  end
 end
end
function Hotbar.verify(state,restored,checkpoint)
 local player,item=state.player,state.pickup
 local live=assert(state.root:getItemById(item:getID()),'exact hotbar identity missing from root')
 assert(live==item and item:getFullType()=='Base.Shotgun'and item:getContainer()==state.root,'hotbar ID/type/root changed')
 assert(item:getAttachedSlot()==state.hotbarIndex and item:getAttachedSlotType()==state.hotbarType
  and item:getAttachedToModel()==state.hotbarLocation,'hotbar original metadata changed')
 assert(not player:getWornItems():contains(item)and not item:canBeActivated()and not isForceDropHeavyItem(item)
  and item:getCurrentAmmoCount()==0 and not item:isRoundChambered(),'hotbar ordinary item/ammunition changed')
 assert(player:getPrimaryHandItem()==(not restored and item or nil)and player:getSecondaryHandItem()==(not restored and item or nil),'hotbar final empty/held hands differ')
 local entries=player:getAttachedItems();local seen={}
 for i=0,entries:size()-1 do
  local entry=entries:get(i);local location=tostring(entry:getLocation());local actual=entry:getItem()
  assert(not seen[location],'duplicate hotbar attachment location');seen[location]=actual
  assert(state.originalAttached[location]==actual or restored and location==state.hotbarLocation and actual==item,
   'unrelated hotbar attachment changed')
 end
 for location,original in pairs(state.originalAttached)do assert(seen[location]==original,'unrelated hotbar attachment lost')end
 assert(restored and seen[state.hotbarLocation]==item or not restored and not seen[state.hotbarLocation],'native hotbar model attachment differs')
 if not isServer()then
  local hotbar=assert(getPlayerHotbar(player:getPlayerNum()));hotbar:reloadIcons()
  assert(hotbar.attachedItems[state.hotbarIndex]==item,'native hotbar icon identity changed')
 end
 if checkpoint then state.hotbarDetached=true end
 return {id=item:getID(),fullType=item:getFullType(),container='root',slotIndex=state.hotbarIndex,slotType=state.hotbarType,
  model=state.hotbarLocation,attached=restored,primary=not restored and item:getID()or false,secondary=not restored and item:getID()or false,worn=false,
  producer='onRackGun',producerCompleted=true,ammoUnchanged=true,unrelatedAttachmentsPreserved=true}
end
function Hotbar.settled(state,toolkit,tidy)
 -- This is a per-tick readiness probe. Vanilla assert logs even inside pcall;
 -- defer assert-based verification until the replicated state is ready.
 local player,root,item=state.player,state.root,state.pickup
 if not player or not root or not item or player:getInventory()~=root then return false end
 local live=root:getItemById(item:getID())
 if live~=item or item:getFullType()~='Base.Shotgun'or item:getContainer()~=root then return false end
 if item:getAttachedSlot()~=state.hotbarIndex or item:getAttachedSlotType()~=state.hotbarType
  or item:getAttachedToModel()~=state.hotbarLocation then return false end
 local held=not tidy and item or nil
 if player:getPrimaryHandItem()~=held or player:getSecondaryHandItem()~=held then return false end
 if player:getWornItems():contains(item)or item:canBeActivated()or isForceDropHeavyItem(item)
  or item:getCurrentAmmoCount()~=0 or item:isRoundChambered()then return false end
 local entries,seen=player:getAttachedItems(),{}
 for i=0,entries:size()-1 do
  local entry=entries:get(i);local location=tostring(entry:getLocation());local actual=entry:getItem()
  if seen[location]or not(state.originalAttached[location]==actual
   or tidy and location==state.hotbarLocation and actual==item)then return false end
  seen[location]=actual
 end
 for location,original in pairs(state.originalAttached)do if seen[location]~=original then return false end end
 if tidy and seen[state.hotbarLocation]~=item or not tidy and seen[state.hotbarLocation]then return false end
 if not isServer()then
  local hotbar=getPlayerHotbar(player:getPlayerNum())
  if not hotbar or not hotbar.attachedItems or hotbar.attachedItems[state.hotbarIndex]~=item then return false end
 end
 if tidy then
  local source=state.hotbarP4
  if not state.hotbarRestoreAction or not state.hotbarAttachConnect or not source or not source.restore
   or not source.completed or source.problem then return false end
  if isClient()and(not state.hotbarRestoreReceipt or toolkit.ActionQueueAcknowledgements.observe(state.hotbarRestoreAction,state.hotbarRestoreReceipt)~='completed')then return false end
 end
 return true
end
function Hotbar.evidence(state,toolkit,tidy,completion)
 assert(state.hotbarProducerStarted and state.hotbarDetached,'native rack producer/detached checkpoint missing')
 local result=Hotbar.verify(state,tidy)
 result.nativeGenerated=state.hotbarRestoreAction and 1 or 0
 assert(result.nativeGenerated==(tidy and 1 or 0),'P4 did not generate exactly one hotbar unequip')
 local source=state.hotbarP4
 assert(not tidy or source and source.restore and source.completed and not source.problem,'P4 source-owned hotbar session did not complete')
 if tidy and isClient()then
  local receipt=assert(state.hotbarRestoreReceipt,'hotbar native receipt missing')
  assert(toolkit.ActionQueueAcknowledgements.observe(state.hotbarRestoreAction,receipt)=='completed','hotbar unequip lacks authoritative hand mutation')
 end
 result.authoritativeRestore=tidy and isClient()or false
 result.sourceSession=source and source.session or false;result.sourceCompleted=tidy and source.completed or false
 result.attachConnectObserved=state.hotbarAttachConnect==true
 result.uiHotbarIdentity=true;result.sharedCompletion=completion;result.unrelatedTailPreserved=true
 return result
end
function Hotbar.release(state)
 local item=state.pickup
 state.player:removeAttachedItem(item);item:setAttachedSlot(-1);item:setAttachedSlotType(nil);item:setAttachedToModel(nil)
 if not isServer()then local hotbar=getPlayerHotbar(state.player:getPlayerNum());if hotbar then hotbar:reloadIcons()end end
end
return Hotbar
