local Clothing={}
local cases={
 ['tidy-clothing']={fullType='Base.Socks_Ankle',location='base:socks'},
 ['tidy-clothing-remove']={fullType='Base.Socks_Ankle',location='base:socks',remove=true},
 ['tidy-clothing-overlap']={fullType='Base.Socks_Ankle',location='base:socks',remove=true,overlapHand='secondary'},
 ['tidy-clothing-overlap-primary']={fullType='Base.Socks_Ankle',location='base:socks',remove=true,overlapHand='primary'},
 ['tidy-clothing-overlap-both']={fullType='Base.Socks_Ankle',location='base:socks',remove=true,overlapHand='both'},
 ['tidy-clothing-held-primary']={fullType='Base.Socks_Ankle',location='base:socks',overlapHand='primary'},
 ['tidy-clothing-held-secondary']={fullType='Base.Socks_Ankle',location='base:socks',overlapHand='secondary'},
 ['tidy-clothing-held-both']={fullType='Base.Socks_Ankle',location='base:socks',overlapHand='both'},
 ['tidy-headwear-hat-restore']={fullType='Base.Hat_Beany',location='base:hat',headwear=true},
 ['tidy-headwear-full-hat-restore']={fullType='Base.Hat_BoxingRed',location='base:fullhat',headwear=true},
 ['tidy-headwear-hat-remove']={fullType='Base.Hat_Beany',location='base:hat',remove=true,headwear=true},
 ['tidy-headwear-full-hat-remove']={fullType='Base.Hat_BoxingRed',location='base:fullhat',remove=true,headwear=true},
}
function Clothing.isCase(id)return cases[id]~=nil end
function Clothing.spec(state)return assert(cases[state.id],'unknown clothing case')end
function Clothing.overlapHand(state)return cases[state.id]and cases[state.id].overlapHand or nil end
function Clothing.overlap(state)return Clothing.overlapHand(state)~=nil end
-- The same native hand expectation serves checkpoint, readiness and final
-- authority. P4 restores the baseline; ordinary Wear keeps the held item.
function Clothing.desired(state)return Clothing.overlap(state)and not Clothing.removes(state)end
function Clothing.expectedHands(state,tidy)
 local hand=Clothing.overlapHand(state)
 local selected=Clothing.desired(state)and tidy or not Clothing.desired(state)and not tidy
 local primary,secondary=state.hammer,state.screwdriver
 if hand=='primary'or hand=='both'then primary=selected and state.clothingItem or nil end
 if hand=='secondary'or hand=='both'then secondary=selected and state.clothingItem or nil end
 if not Clothing.desired(state)and tidy then primary,secondary=state.hammer,state.screwdriver end
 return primary,secondary
end
function Clothing.producerActions(state)
 local result={}
 if state.clothingEquip then result[#result+1]=state.clothingEquip end
 result[#result+1]=state.clothingFirst;result[#result+1]=state.clothingProducer
 return result
end
function Clothing.cleanupSpec(state)
 local result={}
 local function hand(item,primary,twoHands)
  result[#result+1]={class=ISEquipWeaponAction,item=item,primary=primary,twoHands=twoHands==true}
  result[#result+1]={class=P4RestoreAction,item=item,activated=false}
 end
 local slot=Clothing.overlapHand(state)
 if Clothing.desired(state)then
  hand(state.clothingItem,slot~='secondary',slot=='both')
  result[#result+1]={class=ISWearClothing,item=state.clothingItem}
 else
  if slot=='primary'or slot=='both'then hand(state.hammer,true)end
  if slot=='secondary'or slot=='both'then hand(state.screwdriver,false)end
  if slot then result[#result+1]={class=ISUnequipAction,item=state.clothingItem}end
 end
 return result
end
function Clothing.cleanupMember(state,action)
 for _,spec in ipairs(Clothing.cleanupSpec(state))do
  if getmetatable(action)==spec.class and action.item==spec.item then return spec end
 end
end
local function handActivation(state)
 assert(not state.hammer:isActivated()and not state.screwdriver:isActivated(),
  'native overlap changed the inactive baseline hand activation')
end
function Clothing.verifyCleanup(state,actions)
 local expected=Clothing.cleanupSpec(state)
 assert(#actions==#expected,'P4 overlap native cleanup count differs')
 for i,spec in ipairs(expected)do
  local action=actions[i]
  assert(getmetatable(action)==spec.class and action.item==spec.item
   and action.item==state.root:getItemById(spec.item:getID())and action.item:getContainer()==state.root
   and action.item:getFullType()==spec.item:getFullType(), 'P4 overlap native cleanup members/order differ')
  if spec.class==ISEquipWeaponAction then
   assert(action.primary==spec.primary and action.twoHands==spec.twoHands,'P4 overlap restored wrong hand')
  elseif spec.class==P4RestoreAction then
   assert(action.activated==spec.activated,'P4 overlap changed baseline activation')
  end
 end
 return actions
end
function Clothing.removes(state)return cases[state.id]and cases[state.id].remove==true or false end
function Clothing.headwear(state)return cases[state.id]and cases[state.id].headwear==true or false end
local function capacitySafe(state)
 local weight,full,capacity=state.root:getCapacityWeight(),state.clothingItem:getUnequippedWeight(),state.root:getEffectiveCapacity(state.player)
 return weight>=0 and full>=0 and weight+2*full+0.01<=capacity and state.root:isItemAllowed(state.clothingItem)
end
local function emptyHeadwearSlots(state,allowed)
 local values=state.player:getWornItems();local group=values:getBodyLocationGroup()
 assert(group==state.player:getBodyLocationGroup()and group:getLocation(state.clothingLocation)
  and not group:isMultiItem(state.clothingLocation),'headwear fixture needs a real single worn slot')
 for i=0,values:size()-1 do
  local location=values:get(i):getLocation()
  assert(location==state.clothingLocation and values:get(i):getItem()==allowed
   or location~=state.clothingLocation and not group:isExclusive(state.clothingLocation,location),
   'headwear fixture requires empty target/exclusive slots in the prepared scene')
 end
end
function Clothing.restoreType(state)return Clothing.removes(state)and 'ISUnequipAction'or 'ISWearClothing'end
function Clothing.finalWorn(state,tidy)return Clothing.removes(state)and not tidy or not Clothing.removes(state)and tidy end
local watched,installed
function Clothing.watch(state)watched=state end
function Clothing.observeLine(state,line)
 if not state or type(line)~='string'then return end
 local actor,session,message=line:match('^%[P4TidyUpMeister%]%[P(%d+)%]%[S([%d%-]+)%] (.+)$')
 if tonumber(actor)~=state.player:getPlayerNum()then return end
 local proof=state.clothingP4
 if session=='-'then
  local completed=tonumber(message:match('^restore queue complete S(%d+)$'))
  if proof and proof.restore and completed==proof.session then proof.completed=true end
  return
 end
 session=tonumber(session)
 if not session or session<=0 then return end
 local sock=Clothing.spec(state).fullType..'#'..state.clothingItem:getID()..'@'..state.root:getType()
 if Clothing.overlap(state)and message:find('^capture primary=')then
  local p,s=Clothing.expectedHands(state,true)
  local primary=p:getFullType()..'#'..p:getID()..'@'..state.root:getType()
  local secondary=s:getFullType()..'#'..s:getID()..'@'..state.root:getType()
  state.clothingCaptureHands={session=session,valid=message=='capture primary='..primary..' secondary='..secondary}
 end
 local worn=message:match('^capture worn=%[(.-)%] inventoryCount=%d+$')
 local capture=worn and (Clothing.removes(state)and not worn:find(tostring(state.clothingLocation)..'=',1,true)
  or not Clothing.removes(state)and worn:find(tostring(state.clothingLocation)..'='..sock,1,true))
 if capture then
  if proof then proof.problem='duplicate P4 clothing capture';return end
  proof={session=session,hands=not Clothing.overlap(state)or state.clothingCaptureHands
   and state.clothingCaptureHands.session==session and state.clothingCaptureHands.valid};state.clothingP4=proof
 end
 if not proof or proof.session~=session then return end
 local first=Clothing.removes(state)and 'ISWearClothing'or 'ISUnequipAction'
 if Clothing.overlap(state)and message:find('^add%[%w+%] type=ISEquipWeaponAction item=')and message:find(sock,1,true)then proof.equip=true end
 if message:find('^add%[%w+%] type='..first..' item=')and message:find(sock,1,true)then proof.clothing=true end
 if message:find('^add%[%w+%] type=ISCutHair item=nil$')then proof.producer=true end
 if message:find('^RESTORE actionTotal=')then
  local trace=message:match(' trace=%[(.-)%] reason=')
  if proof.restore or not proof.hands or not proof.clothing or not proof.producer or not trace
   or not trace:find((Clothing.overlap(state)and not Clothing.desired(state)and 'ISEquipWeaponAction -> 'or '')..first..' -> ISCutHair',1,true)
   or Clothing.overlap(state)and not Clothing.desired(state)and not proof.equip then proof.problem='P4 restore missing native clothing producer evidence' end
  proof.restore=true
 end
end
function Clothing.install(withP4)
 if installed or not withP4 then return end
 local options=assert(PZAPI.ModOptions:getOptions('P4TidyUpMeister'),'P4 options unavailable')
 assert(options:getOption('DebugOutput'),'P4 debug option unavailable').selected=2
 local original=print
 print=function(...)
  if select('#',...)==1 then Clothing.observeLine(watched,(...))end
  return original(...)
 end
 -- Capture short native transactions when their public started/completed
 -- notifications arrive; ordinary OnTick observation remains the fallback.
 Events.OnServerCommand.Add(function(module,command)
  if module=='PZSurvivorToolkitActions'and command=='State'and watched and Clothing.overlap(watched)then
   Clothing.observe(watched,ISTimedActionQueue.getTimedActionQueue(watched.player),PZSurvivorToolkit,true)
  end
 end)
 installed=true
end
function Clothing.prepare(state,seed)
 local spec=Clothing.spec(state)
 assert(not isClient()or not state.ids.clothingSetupPending,'client cannot prepare before authoritative clothing setup')
 state.clothingRestoreType=Clothing.restoreType(state)
 seed('clothingItem',spec.fullType)
 local item=state.clothingItem
 state.clothingLocation=item:getBodyLocation()
 assert(item:getCategory()=='Clothing' and item:canBeEquipped()==nil and tostring(state.clothingLocation)==spec.location
  and not item:hasTag(ItemTag.WEARABLE)and not item:hasTag(ItemTag.REPLACE_PRIMARY),'ordinary configured Clothing fixture required')
 if Clothing.headwear(state)then
  assert(not item:canBeActivated()and item:getAttachedSlot()==-1 and not item:isBroken()and not isForceDropHeavyItem(item),
   'headwear fixture must be plain unattached non-heavy Clothing')
  assert(capacitySafe(state),'headwear fixture lacks conservative root capacity')
  if isClient()then
   assert(Clothing.available(state.player,state.ids),'client has not adopted authoritative headwear setup')
  else
   emptyHeadwearSlots(state)
   if not Clothing.removes(state)then
    if isServer()then
     state.clothingSetupPending=true;state.clothingSetupPrevious=state.player:getWornItem(state.clothingLocation)
    else state.player:setWornItem(state.clothingLocation,item)end
   end
  end
  emptyHeadwearSlots(state,not Clothing.removes(state)and not state.clothingSetupPending and item or nil)
  state.clothingEmptyHeadwear=true
 elseif Clothing.removes(state)then state.player:setWornItem(state.clothingLocation,nil)
 elseif isClient()then
  assert(Clothing.available(state.player,state.ids),'client has not adopted authoritative clothing setup')
 elseif isServer()then
  state.clothingSetupPending=true;state.clothingSetupPrevious=state.player:getWornItem(state.clothingLocation)
 else
  if Clothing.desired(state)then
   local primary,secondary=Clothing.expectedHands(state,true)
   state.player:setPrimaryHandItem(primary);state.player:setSecondaryHandItem(secondary)
  end
  state.player:setWornItem(state.clothingLocation,item)
 end
 local visual=state.player:getHumanVisual()
 state.clothingHair=state.ids and assert(state.ids.clothingHair,'authoritative clothing hair style missing')
  or (state.player:isFemale()and 'Bob'or 'CrewCut')
 if Clothing.headwear(state)then
  assert(state.clothingHair==(state.player:isFemale()and 'Bob'or 'CrewCut'),'headwear requires the configured plain native style')
 end
 local styles=getHairStylesInstance()
 local style=state.player:isFemale() and styles:FindFemaleStyle(state.clothingHair) or styles:FindMaleStyle(state.clothingHair)
 assert(style and tostring(style:getName())==state.clothingHair and not style:isAttachedHair(),'plain native hair definition required')
 for _,name in ipairs({'Bald','Mohawk','Spike','Greased','Buffont'})do
  assert(not tostring(style:getName()):find(name,1,true),'haircut fixture must not consume styling items or reset hair color')
 end
 if isClient()then
  assert(tostring(visual:getHairModel())==state.clothingHair and not visual:getNonAttachedHair(),
   'client has not adopted authoritative plain hair setup')
 else
  -- Disposable-character setup, like seeding socks/hands. The tested native
  -- haircut later requests this same validated style without consumables.
  visual:setNonAttachedHair(nil);visual:setHairModel(state.clothingHair);state.player:resetModel()
  if isServer()then sendHumanVisual(state.player)end
 end
end
function Clothing.available(player,ids)
 if type(ids.clothingHair)~='string'or tostring(player:getHumanVisual():getHairModel())~=ids.clothingHair
  or player:getHumanVisual():getNonAttachedHair()then return false end
 local spec=cases[ids.case]
 if spec and (spec.headwear or not spec.remove)then
  local root=player:getInventory();local item=root:getItemById(ids.items.clothingItem)
  if not item or item:getFullType()~=spec.fullType or item:getContainer()~=root
   or tostring(item:getBodyLocation())~=spec.location then return false end
  local expected=not spec.remove and not ids.clothingSetupPending and item or nil
  if ids.clothingSetupPending then
   for _,record in ipairs(ids.originalWorn or {})do
    if record.location==spec.location then
     expected=root:getItemById(record.id)
     if not expected or expected:getFullType()~=record.fullType or expected:getContainer()~=root then return false end
    end
   end
  end
  if player:getWornItem(item:getBodyLocation())~=expected then return false end
  if spec.overlapHand and not spec.remove then
   local primary=root:getItemById(ids.items.hammer);local secondary=root:getItemById(ids.items.screwdriver)
   if not primary or primary:getFullType()~='Base.Torch'or primary:getContainer()~=root
    or not secondary or secondary:getFullType()~='Base.Screwdriver'or secondary:getContainer()~=root then return false end
   if not ids.clothingSetupPending then
    if spec.overlapHand=='primary'or spec.overlapHand=='both'then primary=item end
    if spec.overlapHand=='secondary'or spec.overlapHand=='both'then secondary=item end
   end
   if player:getPrimaryHandItem()~=primary or player:getSecondaryHandItem()~=secondary then return false end
  end
 end
 return true
end
-- SyncClothingPacket.process keeps an already-worn ID even if it was created
-- before inventory replication. Send the first worn snapshot only after the
-- owning client confirms its exact root item, avoiding a permanent worn proxy.
function Clothing.configure(state,itemID)
 assert(isServer()and not isClient()and Clothing.isCase(state.id)and not Clothing.removes(state)
  and state.clothingSetupPending==true,'invalid authoritative clothing setup phase')
 local item=state.clothingItem
 assert(type(itemID)=='number'and itemID==item:getID()and state.player:getInventory()==state.root
  and state.root:getItemById(itemID)==item and item:getContainer()==state.root
  and item:getFullType()==Clothing.spec(state).fullType and item:getBodyLocation()==state.clothingLocation,
  'authoritative clothing setup identity/root differs')
 assert(state.player:getWornItem(state.clothingLocation)==state.clothingSetupPrevious,
  'authoritative clothing setup baseline changed')
 if Clothing.headwear(state)then
  emptyHeadwearSlots(state)
  assert(capacitySafe(state),'authoritative headwear setup lacks conservative root capacity')
 end
 if Clothing.desired(state)then
  assert(state.player:getPrimaryHandItem()==state.hammer and state.player:getSecondaryHandItem()==state.screwdriver,
   'authoritative clothing setup baseline hands changed')
  local primary,secondary=Clothing.expectedHands(state,true)
  state.player:setPrimaryHandItem(primary);state.player:setSecondaryHandItem(secondary)
 end
 state.player:setWornItem(state.clothingLocation,item)
 assert(state.player:getWornItem(state.clothingLocation)==item,'authoritative clothing setup did not wear exact root item')
 state.clothingSetupPending=nil;state.clothingSetupPrevious=nil
 if Clothing.desired(state)then sendEquip(state.player)end
 sendClothing(state.player,state.clothingLocation,item)
end
function Clothing.enqueue(state,helpers)
 require 'TimedActions/ISCutHair'
 -- Explicit native constructors exercise P4's public queue observer, rather
 -- than UI explicit-equip intent. The unchanged haircut arms restoreWorn.
 -- Only P4 constructs the eventual wear/unequip cleanup action.
 local remove=Clothing.removes(state)
 state.clothingEquip=nil
 helpers.run(function()
  if Clothing.overlap(state)and not Clothing.desired(state)then
   local hand=Clothing.overlapHand(state)
   handActivation(state)
   state.clothingEquip=ISEquipWeaponAction:new(state.player,state.clothingItem,50,hand~='secondary',hand=='both')
   ISTimedActionQueue.add(state.clothingEquip)
   assert(state.clothingEquip.maxTime==50 and state.clothingEquip.primary==(hand~='secondary')
    and state.clothingEquip.twoHands==(hand=='both')and state.clothingEquip.complete==ISEquipWeaponAction.complete,
    'native overlap equip fixture changed')
  end
  local class=remove and ISWearClothing or ISUnequipAction
  state.clothingFirst=class:new(state.player,state.clothingItem,50)
  ISTimedActionQueue.add(state.clothingFirst)
  state.clothingProducer=ISCutHair:new(state.player,state.clothingHair,nil,100)
  ISTimedActionQueue.add(state.clothingProducer)
 end)
 assert(state.clothingFirst.maxTime==50 and state.clothingProducer.maxTime==100
  and state.clothingProducer.complete==ISCutHair.complete,'native constructor durations/effects changed')
end
function Clothing.observe(state,queue,toolkit,tidy)
 local current=queue.current
 if current and current==state.clothingProducer and current:isStarted()then
  state.clothingProducerStarted=true
  if Clothing.headwear(state)then
   assert(state.clothingEmptyHeadwear and capacitySafe(state),'headwear removal lacks setup/capacity proof')
   emptyHeadwearSlots(state,Clothing.removes(state)and state.clothingItem or nil)
   Clothing.verify(state,Clothing.removes(state))
   state.clothingHeadwearReady=true
  end
  if Clothing.overlap(state)then
   local item=assert(state.root:getItemById(state.clothingItem:getID()),'overlap exact socks missing')
   local primary,secondary=Clothing.expectedHands(state,false)
   local expectedWorn=not Clothing.desired(state)and item or nil
   assert(item:getContainer()==state.root and item:getFullType()==Clothing.spec(state).fullType
    and state.player:getSecondaryHandItem()==secondary and state.player:getWornItem(state.clothingLocation)==expectedWorn
    and state.player:getPrimaryHandItem()==primary,'native clothing actions did not create the exact intermediate hand/worn state')
   handActivation(state)
   state.clothingOverlap={primary=primary and primary:getID()or false,secondary=secondary and secondary:getID()or false,
    worn=not Clothing.desired(state)and item:getID()or false,container='root'}
  end
 end
 if Clothing.overlap(state)and state.clothingP4 and state.clothingP4.restore and not state.clothingCleanup then
  local cleanup={}
  for _,action in ipairs(queue.queue)do
   if Clothing.cleanupMember(state,action)then
    cleanup[#cleanup+1]=action
   end
  end
  Clothing.verifyCleanup(state,cleanup)
  if toolkit.Settings.actionQueue()then
   for _,action in ipairs(cleanup)do
    local _,kind=toolkit.ActionQueueDefinitions.inspect(action)
    assert(kind=='compat.tidy-equipment','P4 overlap cleanup lacks verified scoped origin')
   end
  end
  state.clothingCleanup=cleanup
 end
 for _,action in ipairs(queue.queue)do
  local class=Clothing.removes(state)and ISUnequipAction or ISWearClothing
  if getmetatable(action)==class and action.Type==Clothing.restoreType(state)and action.item
    and action.item:getID()==state.clothingItem:getID()then
   assert(tidy and action~=state.clothingProducer,'unexpected non-P4 clothing restoration')
   local source=state.clothingP4
   assert(source and source.restore and not source.problem,'socks wear lacks real source-owned P4 restore evidence')
   assert(not state.clothingRestoreAction or state.clothingRestoreAction==action,'P4 queued duplicate socks restores')
   state.clothingRestoreAction=action
   if toolkit.Settings.actionQueue()then
    local _,kind=toolkit.ActionQueueDefinitions.inspect(action)
    assert(kind=='compat.tidy-equipment','P4 wear lacks verified scoped origin')
   end
   if isClient()and not state.clothingRestoreReceipt then
    state.clothingRestoreReceipt=toolkit.ActionQueueAcknowledgements.capture(action)
   end
  end
 end
 if Clothing.overlap(state)and isClient()then
  state.clothingReceipts=state.clothingReceipts or {}
  for _,actions in ipairs({Clothing.producerActions(state),state.clothingCleanup or {}})do
   for _,action in ipairs(actions)do
    if not state.clothingReceipts[action]then state.clothingReceipts[action]=toolkit.ActionQueueAcknowledgements.capture(action)end
   end
  end
 end
end
function Clothing.evidence(state,toolkit,tidy,completion,hands)
 assert(state.clothingProducerStarted,'native haircut producer was never observed running')
 local result=Clothing.verify(state,Clothing.finalWorn(state,tidy))
 result.nativeGenerated=state.clothingRestoreAction and 1 or 0
 assert(result.nativeGenerated==(tidy and 1 or 0),'P4 did not generate exactly one socks restore')
 if tidy and isClient()then
  local receipt=assert(state.clothingRestoreReceipt,'P4 clothing restore native receipt not captured')
  assert(toolkit.ActionQueueAcknowledgements.observe(state.clothingRestoreAction,receipt)=='completed',
   'P4 clothing restore lacks authoritative completion')
 end
 result.authoritativeRestore=tidy and isClient()or false
 local source=state.clothingP4
 assert(not tidy or source and source.restore and source.completed and not source.problem,
  'P4 source-owned restore session did not complete')
 result.sourceSession=source and source.session or false
 result.sourceCompleted=tidy and source.completed or false
 result.sharedCompletion=completion
 result.unrelatedTailPreserved=true
 if Clothing.headwear(state)then
  assert(state.clothingEmptyHeadwear and state.clothingHeadwearReady,'headwear native setup/producer was not verified')
  result.headwearSetup={emptyExclusiveSlots=true,capacityBeforeRemoval=true}
 end
 if Clothing.overlap(state)then
  local overlap={intermediate=assert(state.clothingOverlap,'native overlap was never observed'),cleanup={},acknowledgements={},sharedHands=hands}
  local cleanup=state.clothingCleanup or {}
  if tidy then Clothing.verifyCleanup(state,cleanup)else assert(#cleanup==0,'unexpected non-P4 overlap cleanup')end
  for _,action in ipairs(cleanup)do
   local row={kind=action.Type,id=action.item:getID()}
   if getmetatable(action)==ISEquipWeaponAction then row.primary=action.primary;row.twoHands=action.twoHands
   elseif getmetatable(action)==P4RestoreAction then row.activated=action.activated end
   overlap.cleanup[#overlap.cleanup+1]=row
  end
  if isClient()then
   for _,actions in ipairs({Clothing.producerActions(state),state.clothingCleanup or {}})do
    for _,action in ipairs(actions)do
     local receipt=assert(state.clothingReceipts and state.clothingReceipts[action],'overlap native acknowledgement not captured')
     assert(toolkit.ActionQueueAcknowledgements.observe(action,receipt)=='completed','overlap native action did not complete authoritatively')
     overlap.acknowledgements[#overlap.acknowledgements+1]={kind=action.Type,id=action.item and action.item:getID()or false,state='completed'}
    end
   end
  end
  result.overlap=overlap
 end
 return result
end
function Clothing.settled(state,toolkit,tidy)
 local live=state.root:getItemById(state.clothingItem:getID())
 if not live or live:getFullType()~=Clothing.spec(state).fullType or live:getContainer()~=state.root then return false end
 local worn=state.player:getWornItem(state.clothingLocation)
 if Clothing.finalWorn(state,tidy)then if worn~=live then return false end elseif worn~=nil then return false end
 if tidy then
  if not state.clothingRestoreAction then return false end
  local source=state.clothingP4
  if not source or not source.completed or source.problem then return false end
  if isClient()and (not state.clothingRestoreReceipt
   or toolkit.ActionQueueAcknowledgements.observe(state.clothingRestoreAction,state.clothingRestoreReceipt)~='completed')then return false end
 end
 if Clothing.headwear(state)and (not state.clothingHeadwearReady or state.player:getPrimaryHandItem()~=state.hammer
  or state.player:getSecondaryHandItem()~=state.screwdriver)then return false end
 if Clothing.overlap(state)then
  local primary,secondary=Clothing.expectedHands(state,tidy)
  if state.player:getPrimaryHandItem()~=primary or state.player:getSecondaryHandItem()~=secondary
   or state.hammer:isActivated()or state.screwdriver:isActivated()then return false end
  if not state.clothingOverlap or tidy and not state.clothingCleanup then return false end
  if isClient()then
   for _,actions in ipairs({Clothing.producerActions(state),state.clothingCleanup or {}})do
    for _,action in ipairs(actions)do
     local receipt=state.clothingReceipts and state.clothingReceipts[action]
     if not receipt or toolkit.ActionQueueAcknowledgements.observe(action,receipt)~='completed'then return false end
    end
   end
  end
 end
 return true
end
function Clothing.verify(state,restored)
 local player,item=state.player,state.clothingItem
 local live=assert(state.root:getItemById(item:getID()),'exact socks identity missing from root')
 assert(live:getFullType()==Clothing.spec(state).fullType and live:getContainer()==state.root,'socks type/container changed')
 assert(restored and player:getWornItem(state.clothingLocation)==live
  or not restored and player:getWornItem(state.clothingLocation)==nil,'exact socks worn slot differs')
 assert(tostring(player:getHumanVisual():getHairModel())==state.clothingHair and not player:getHumanVisual():getNonAttachedHair(),'native haircut changed the requested existing style')
 local primary,secondary=Clothing.expectedHands(state,Clothing.removes(state)and not restored or not Clothing.removes(state)and restored)
 if Clothing.overlap(state)then handActivation(state)end
 assert(player:getPrimaryHandItem()==primary and player:getSecondaryHandItem()==secondary,
  'clothing restoration changed unrelated hands')
 local result={id=live:getID(),fullType=live:getFullType(),bodyLocation=tostring(state.clothingLocation),container='root',
  worn=restored,producer='ISCutHair',producerCompleted=true,hairUnchanged=true,hairStyle=state.clothingHair,unrelatedHandsPreserved=true}
 if Clothing.overlap(state)then
  result.primary=primary and primary:getID()or false;result.secondary=secondary and secondary:getID()or false
  local originalPrimary,originalSecondary=Clothing.expectedHands(state,true)
  result.originalPrimary=originalPrimary:getID();result.originalSecondary=originalSecondary:getID()
 end
 return result
end
return Clothing
