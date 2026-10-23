local Clothing={}
local cases={
 ['tidy-watch-digital-restore']={fullType='Base.WristWatch_Left_DigitalBlack',location='base:leftwrist',wristwatch=true,alarmSet=true},
 ['tidy-watch-digital-remove']={fullType='Base.WristWatch_Left_DigitalBlack',location='base:leftwrist',wristwatch=true,alarmSet=true,remove=true},
 ['tidy-watch-classic-restore']={fullType='Base.WristWatch_Right_ClassicBlack',location='base:rightwrist',wristwatch=true,alarmSet=false},
 ['tidy-watch-classic-remove']={fullType='Base.WristWatch_Right_ClassicBlack',location='base:rightwrist',wristwatch=true,alarmSet=false,remove=true},
 ['tidy-watch-overlap-primary']={fullType='Base.WristWatch_Left_DigitalBlack',location='base:leftwrist',wristwatch=true,alarmSet=true,remove=true,overlapHand='primary'},
 ['tidy-watch-overlap-secondary']={fullType='Base.WristWatch_Left_DigitalBlack',location='base:leftwrist',wristwatch=true,alarmSet=true,remove=true,overlapHand='secondary'},
 ['tidy-watch-overlap-both']={fullType='Base.WristWatch_Left_DigitalBlack',location='base:leftwrist',wristwatch=true,alarmSet=true,remove=true,overlapHand='both'},
 ['tidy-watch-held-primary']={fullType='Base.WristWatch_Left_DigitalBlack',location='base:leftwrist',wristwatch=true,alarmSet=true,overlapHand='primary'},
 ['tidy-watch-held-secondary']={fullType='Base.WristWatch_Left_DigitalBlack',location='base:leftwrist',wristwatch=true,alarmSet=true,overlapHand='secondary'},
 ['tidy-watch-held-both']={fullType='Base.WristWatch_Left_DigitalBlack',location='base:leftwrist',wristwatch=true,alarmSet=true,overlapHand='both'},
 ['tidy-watch-ringing-restore']={fullType='Base.WristWatch_Left_DigitalBlack',location='base:leftwrist',wristwatch=true,alarmSet=true,ringing=true,},
 ['tidy-watch-ringing-remove']={fullType='Base.WristWatch_Left_DigitalBlack',location='base:leftwrist',wristwatch=true,alarmSet=true,ringing=true,remove=true,},
 ['tidy-watch-ringing-overlap-both']={fullType='Base.WristWatch_Left_DigitalBlack',location='base:leftwrist',wristwatch=true,alarmSet=true,ringing=true,remove=true,overlapHand='both',},
 ['tidy-watch-ringing-held-both']={fullType='Base.WristWatch_Left_DigitalBlack',location='base:leftwrist',wristwatch=true,alarmSet=true,ringing=true,overlapHand='both',},
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
-- One ordered native receipt list serves ordinary overlaps and watches.
-- Watch overlaps reuse overlap.acknowledgements without a duplicate watch list.
local function nativeActions(state,tidy)
 local result=Clothing.producerActions(state)
 if tidy then
  if Clothing.overlap(state)then
   for _,action in ipairs(state.clothingCleanup or {})do result[#result+1]=action end
  elseif state.clothingRestoreAction then result[#result+1]=state.clothingRestoreAction end
 end
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
function Clothing.wristwatch(state)return cases[state.id]and cases[state.id].wristwatch==true or false end
function Clothing.ringing(state)return cases[state.id]and cases[state.id].ringing==true or false end
local function strictWatch(value,spec,pending)
 if type(value)~='table'or getmetatable(value)~=nil then return false end
 local count=0
 for key in pairs(value)do
  if key~='alarmHour'and key~='alarmMinute'and key~='alarmSet'and key~='ringing'then return false end
  count=count+1
 end
 return count==4 and type(value.alarmHour)=='number'and value.alarmHour%1==0 and value.alarmHour>=0 and value.alarmHour<24
  and type(value.alarmMinute)=='number'and value.alarmMinute%1==0 and value.alarmMinute>=0 and value.alarmMinute<60
  and (spec.ringing or value.alarmMinute==40)and value.alarmSet==spec.alarmSet
  and value.ringing==(spec.ringing==true and not pending)
end
local function watchSnapshot(item)
 return {alarmHour=item:getHour(),alarmMinute=item:getMinute(),alarmSet=item:isAlarmSet(),ringing=item:isRinging()}
end
-- Readiness must not throw assertions while native alarm packets converge.
function Clothing.watchMatches(state,item)
 if not Clothing.wristwatch(state)then return true end
 item=item or state.clothingItem
 if not strictWatch(state.clothingWatch,Clothing.spec(state),state.clothingRingPending)
  or not instanceof(item,'AlarmClockClothing')or not instanceof(item,'Clothing')or item:getCategory()~='AlarmClock'then return false end
 local value=watchSnapshot(item)
 for key,expected in pairs(state.clothingWatch)do if value[key]~=expected then return false end end
 return true
end
function Clothing.watchState(state,item)
 if not Clothing.wristwatch(state)then return nil end
 assert(Clothing.watchMatches(state,item),'native watch alarm changed or invalid authoritative watch baseline')
 return watchSnapshot(item or state.clothingItem)
end
local function finite(value)return type(value)=='number'and value==value and value>-math.huge and value<math.huge end
function Clothing.watchTiming(state)
 if not Clothing.ringing(state)or state.clothingRingPending then return nil end
 local started,observed=state.clothingWatchStartedAge,getGameTime():getWorldAgeHours()
 assert(finite(started)and finite(observed)and observed>=started and observed-started<0.5,'native ring lifetime evidence expired or clock changed')
 return {startedAgeHours=started,observedAgeHours=observed}
end
function Clothing.armRing(state,itemID)
 assert(not isClient()and Clothing.ringing(state)and state.clothingRingPending==true and not state.clothingSetupPending,
  'ring arming belongs to the once-only SP/server root-ready phase')
 local item=state.clothingItem
 assert(itemID==item:getID()and state.root==state.player:getInventory()and state.root:getItemById(itemID)==item
  and item:getContainer()==state.root and item:getFullType()==Clothing.spec(state).fullType and Clothing.watchMatches(state),
  'ring arming exact root/configuration differs')
 local primary,secondary=Clothing.expectedHands(state,true)
 assert(state.player:getPrimaryHandItem()==primary and state.player:getSecondaryHandItem()==secondary
  and state.player:getWornItem(state.clothingLocation)==(not Clothing.removes(state)and item or nil),
  'ring arming must follow exact authoritative hand/worn setup')
 local time=getGameTime();local minute=time:getMinutes()
 if isServer()then minute=math.floor(minute/10)*10 end
 item:setAlarmSet(true);item:setHour(time:getHour());item:setMinute(minute);item:setForceDontRing(-1)
 state.clothingWatchStartedAge=time:getWorldAgeHours()
 -- This is the real alarm trigger. Its server start sends the native packet;
 -- the owning client applies its setters/force flag then calls native update.
 item:update()
 assert(item:isRinging(),'native alarm update did not start the prepared ring')
 state.clothingWatch=watchSnapshot(item);state.clothingRingPending=nil
 Clothing.watchState(state);Clothing.watchTiming(state)
end
function Clothing.stopRing(state)
 if not Clothing.ringing(state)or state.clothingRingStopped then return nil end
 local item=state.clothingItem
 item:stopRinging()
 if isServer()then item:syncStopRinging()end
 local value=watchSnapshot(item)
 assert(not value.ringing and value.alarmHour==state.clothingWatch.alarmHour and value.alarmMinute==state.clothingWatch.alarmMinute
  and value.alarmSet==state.clothingWatch.alarmSet,'fixture cleanup changed alarm configuration')
 state.clothingRingStopped=true
 return {id=item:getID(),watch=value}
end
function Clothing.watchProcessing(state)
 if not Clothing.wristwatch(state)or isClient()then return nil end
 local cell=getCell()
 return {active=cell:getProcessItems():contains(state.clothingItem),pendingRemoval=cell:getProcessItemsRemove():contains(state.clothingItem)}
end
-- The server ProcessItems sweep runs on a separate >5s cadence. Observe its
-- native settled state before taking authority snapshots; never register or
-- remove an item to make the expected state happen. SP keeps its existing gate.
function Clothing.watchProcessingReady(state,worn)
 if not isServer()or isClient()or not Clothing.wristwatch(state)then return true end
 local processing=Clothing.watchProcessing(state)
 return not processing.pendingRemoval and processing.active==(state.clothingWatch.alarmSet and worn)
end
local function preparedSlots(state)return Clothing.headwear(state)or Clothing.wristwatch(state)end
local function capacitySafe(state)
 local weight,full,capacity=state.root:getCapacityWeight(),state.clothingItem:getUnequippedWeight(),state.root:getEffectiveCapacity(state.player)
 return weight>=0 and full>=0 and weight+2*full+0.01<=capacity and state.root:isItemAllowed(state.clothingItem)
end
local function emptyHeadwearSlots(state,allowed)
 local values=state.player:getWornItems();local group=values:getBodyLocationGroup()
 assert(group==state.player:getBodyLocationGroup()and group:getLocation(state.clothingLocation)
  and not group:isMultiItem(state.clothingLocation),'clothing fixture needs a real single worn slot')
 for i=0,values:size()-1 do
  local location=values:get(i):getLocation()
  assert(location==state.clothingLocation and values:get(i):getItem()==allowed
   or location~=state.clothingLocation and not group:isExclusive(state.clothingLocation,location),
   'clothing fixture requires empty target/exclusive slots in the prepared scene')
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
  if module=='PZSurvivorToolkitActions'and command=='State'and watched and (Clothing.overlap(watched)or Clothing.wristwatch(watched))then
   Clothing.observe(watched,ISTimedActionQueue.getTimedActionQueue(watched.player),PZSurvivorToolkit,true)
  end
 end)
 installed=true
end
function Clothing.prepare(state,seed)
 local spec=Clothing.spec(state)
 assert(not isClient()or not state.ids.clothingSetupPending,'client cannot prepare before authoritative clothing setup')
 state.clothingRestoreType=Clothing.restoreType(state)
 if spec.ringing then
  state.clothingRingPending=not isClient()or state.ids.clothingRingPending or nil
  state.clothingWatchStartedAge=state.ids and state.ids.clothingWatchStartedAge or nil
 end
 seed('clothingItem',spec.fullType)
 local item=state.clothingItem
 state.clothingLocation=item:getBodyLocation()
 assert((spec.wristwatch and item:getCategory()=='AlarmClock'and instanceof(item,'AlarmClockClothing')and instanceof(item,'Clothing')
  or not spec.wristwatch and item:getCategory()=='Clothing') and item:canBeEquipped()==nil and tostring(state.clothingLocation)==spec.location
  and not item:hasTag(ItemTag.WEARABLE)and not item:hasTag(ItemTag.REPLACE_PRIMARY),'configured native Clothing fixture required')
 if spec.wristwatch then
  if isClient()then state.clothingWatch=state.ids.clothingWatch
  else
   -- A valid native MP alarm minute, twelve game hours from this bounded run.
   state.clothingWatch={alarmHour=(getGameTime():getHour()+12)%24,alarmMinute=40,alarmSet=spec.alarmSet,ringing=false}
   item:setHour(state.clothingWatch.alarmHour);item:setMinute(state.clothingWatch.alarmMinute);item:setAlarmSet(spec.alarmSet)
   item:syncAlarmClock()
  end
  Clothing.watchState(state)
 end
 if preparedSlots(state)then
  assert(not item:canBeActivated()and item:getAttachedSlot()==-1 and not item:isBroken()and not isForceDropHeavyItem(item),
   'clothing fixture must be plain unattached non-heavy Clothing')
  assert(capacitySafe(state),'clothing fixture lacks conservative root capacity')
  if isClient()then
   assert(Clothing.available(state.player,state.ids),'client has not adopted authoritative prepared clothing setup')
  else
   emptyHeadwearSlots(state)
   if not Clothing.removes(state)then
    if isServer()then
     state.clothingSetupPending=true;state.clothingSetupPrevious=state.player:getWornItem(state.clothingLocation)
    else
     if Clothing.desired(state)then
      local primary,secondary=Clothing.expectedHands(state,true)
      state.player:setPrimaryHandItem(primary);state.player:setSecondaryHandItem(secondary)
     end
     state.player:setWornItem(state.clothingLocation,item)
    end
   end
  end
  emptyHeadwearSlots(state,not Clothing.removes(state)and not state.clothingSetupPending and item or nil)
  if Clothing.headwear(state)then state.clothingEmptyHeadwear=true else state.clothingEmptyWatchSlots=true end
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
 if spec.ringing and not isClient()and not isServer()then Clothing.armRing(state,item:getID())end
end
function Clothing.available(player,ids)
 if type(ids.clothingHair)~='string'or tostring(player:getHumanVisual():getHairModel())~=ids.clothingHair
  or player:getHumanVisual():getNonAttachedHair()then return false end
 local spec=cases[ids.case]
 if spec and (spec.headwear or spec.wristwatch or not spec.remove)then
  local root=player:getInventory();local item=root:getItemById(ids.items.clothingItem)
  if not item or item:getFullType()~=spec.fullType or item:getContainer()~=root
   or tostring(item:getBodyLocation())~=spec.location then return false end
  if spec.wristwatch then
   if not Clothing.watchMatches({id=ids.case,clothingItem=item,clothingWatch=ids.clothingWatch,clothingRingPending=ids.clothingRingPending})then return false end
   if spec.ringing and not ids.clothingRingPending then
    local age=getGameTime():getWorldAgeHours();local started=ids.clothingWatchStartedAge
    if not finite(started)or not finite(age)or age<started or age-started>=0.5 then return false end
   end
  end
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
 if preparedSlots(state)then
  emptyHeadwearSlots(state)
  assert(capacitySafe(state),'authoritative clothing setup lacks conservative root capacity')
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
  if preparedSlots(state)then
   assert((state.clothingEmptyHeadwear or state.clothingEmptyWatchSlots)and capacitySafe(state),'clothing removal lacks setup/capacity proof')
   emptyHeadwearSlots(state,Clothing.removes(state)and state.clothingItem or nil)
   Clothing.verify(state,Clothing.removes(state),true)
   if Clothing.headwear(state)then state.clothingHeadwearReady=true else state.clothingWatchReady=true end
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
    if Clothing.overlap(state)or Clothing.wristwatch(state)then
     state.clothingReceipts=state.clothingReceipts or {}
     state.clothingReceipts[action]=state.clothingRestoreReceipt
    end
   end
  end
 end
 if (Clothing.overlap(state)or Clothing.wristwatch(state))and isClient()then
  state.clothingReceipts=state.clothingReceipts or {}
  for _,action in ipairs(nativeActions(state,tidy))do
   if not state.clothingReceipts[action]then state.clothingReceipts[action]=toolkit.ActionQueueAcknowledgements.capture(action)end
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
 if Clothing.wristwatch(state)then
  assert(state.clothingEmptyWatchSlots and state.clothingWatchReady,'watch native setup/producer was not verified')
  result.watchBaseline=state.clothingWatch
  result.watchSetup={emptyExclusiveSlots=true,capacityBeforeRemoval=true}
  if not Clothing.overlap(state)then
   result.watchAcknowledgements={}
   if isClient()then
    for _,action in ipairs(nativeActions(state,tidy))do
     local receipt=assert(state.clothingReceipts and state.clothingReceipts[action],'watch native acknowledgement not captured')
     assert(toolkit.ActionQueueAcknowledgements.observe(action,receipt)=='completed','watch native action did not complete authoritatively')
     result.watchAcknowledgements[#result.watchAcknowledgements+1]={kind=action.Type,id=action.item and action.item:getID()or false,state='completed'}
    end
   end
  end
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
   for _,action in ipairs(nativeActions(state,tidy))do
    local receipt=assert(state.clothingReceipts and state.clothingReceipts[action],'overlap native acknowledgement not captured')
    assert(toolkit.ActionQueueAcknowledgements.observe(action,receipt)=='completed','overlap native action did not complete authoritatively')
    overlap.acknowledgements[#overlap.acknowledgements+1]={kind=action.Type,id=action.item and action.item:getID()or false,state='completed'}
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
 if Clothing.wristwatch(state)then
  if not isClient()and Clothing.watchProcessing(state).pendingRemoval then return false end
  local primary,secondary=Clothing.expectedHands(state,tidy)
  if not state.clothingWatchReady or not Clothing.watchMatches(state,live)
   or state.player:getPrimaryHandItem()~=primary or state.player:getSecondaryHandItem()~=secondary then return false end
  if isClient()and not Clothing.overlap(state)then
   for _,action in ipairs(nativeActions(state,tidy))do
    local receipt=state.clothingReceipts and state.clothingReceipts[action]
    if not receipt or toolkit.ActionQueueAcknowledgements.observe(action,receipt)~='completed'then return false end
   end
  end
 end
 if Clothing.headwear(state)and (not state.clothingHeadwearReady or state.player:getPrimaryHandItem()~=state.hammer
  or state.player:getSecondaryHandItem()~=state.screwdriver)then return false end
 if Clothing.overlap(state)then
  local primary,secondary=Clothing.expectedHands(state,tidy)
  if state.player:getPrimaryHandItem()~=primary or state.player:getSecondaryHandItem()~=secondary
   or state.hammer:isActivated()or state.screwdriver:isActivated()then return false end
  if not state.clothingOverlap or tidy and not state.clothingCleanup then return false end
  if isClient()then
   for _,action in ipairs(nativeActions(state,tidy))do
    local receipt=state.clothingReceipts and state.clothingReceipts[action]
    if not receipt or toolkit.ActionQueueAcknowledgements.observe(action,receipt)~='completed'then return false end
   end
  end
 end
 return true
end
function Clothing.verify(state,restored,transient)
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
 if Clothing.wristwatch(state)then
  result.watch=Clothing.watchState(state,live)
  result.watchTiming=Clothing.watchTiming(state)
  result.watchProcessing=not transient and Clothing.watchProcessing(state)or nil
  assert(not result.watchProcessing or not result.watchProcessing.pendingRemoval,'watch processing removal has not settled')
 end
 if Clothing.overlap(state)then
  result.primary=primary and primary:getID()or false;result.secondary=secondary and secondary:getID()or false
  local originalPrimary,originalSecondary=Clothing.expectedHands(state,true)
  result.originalPrimary=originalPrimary:getID();result.originalSecondary=originalSecondary:getID()
 end
 return result
end
return Clothing
