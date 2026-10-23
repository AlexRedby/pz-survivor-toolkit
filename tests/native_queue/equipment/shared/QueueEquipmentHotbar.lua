local Hotbar={}
-- TVRadio_ReInvented sets an off radio to 0.1 when its native on-equip UI opens.
-- Seed that installed UI default on the authority; keep 0.25 for the on case.
-- This gate checks unchanged settings from those explicit baselines, not
-- preservation of arbitrary off-state volume through the third-party UI.
-- Vanilla ISRadioWindow.update (152-154) and the installed full-pack override
-- (185) turn an inventory radio off after it leaves hands/back. Observe that
-- client UI transition; the fixture never calls a gameplay power setter.
-- B42.21 GameServer.receiveRadioDeviceDataState lacks the unheld selector0
-- item-ID route emitted by DeviceData, so authority retains its initial power
-- state. Preserve that exact native role baseline; this gate does not fix it.
local function radioVolume(on)return on and 0.25 or 0.1 end
local cases={
 ['tidy-hotbar-flashlight-charged']={item='Base.FlashLight_AngleHead',attachment='Webbing',kind='WebbingLeft',model='Webbing Left Walkie',twoHands=false,provider=true,providerItem='Base.SCBA_notank',flashlight='charged'},
 ['tidy-hotbar-flashlight-empty']={item='Base.FlashLight_AngleHead',attachment='Webbing',kind='WebbingLeft',model='Webbing Left Walkie',twoHands=false,provider=true,providerItem='Base.SCBA_notank',flashlight='empty'},
 ['tidy-hotbar-flashlight-deplete']={item='Base.FlashLight_AngleHead',attachment='Webbing',kind='WebbingLeft',model='Webbing Left Walkie',twoHands=false,provider=true,providerItem='Base.SCBA_notank',flashlight='deplete'},
 ['tidy-hotbar-radio-off']={item='Base.WalkieTalkie2',attachment='Walkie',kind='SmallBeltLeft',model='Walkie Belt Left',twoHands=false,provider=true,radio=true},
 ['tidy-hotbar-radio-on']={item='Base.WalkieTalkie2',attachment='Walkie',kind='SmallBeltRight',model='Walkie Belt Right',twoHands=false,provider=true,radio=true,on=true},
 ['tidy-hotbar-normal-left']={item='Base.ScissorsBluntMedical',attachment='Screwdriver',kind='SmallBeltLeft',model='Belt Left Screwdriver',twoHands=false,provider=true,ordinary=true},
 ['tidy-hotbar-normal-right']={item='Base.ScissorsBluntMedical',attachment='Screwdriver',kind='SmallBeltRight',model='Belt Right Screwdriver',twoHands=false,provider=true,ordinary=true,priorSecondary=true},
 ['tidy-hotbar']={item='Base.Shotgun',attachment='Rifle',index=1,kind='Back',baseModel='Rifle On Back',model='Rifle On Back with Bag',twoHands=true},
 ['tidy-hotbar-holster-left']={item='Base.Pistol',attachment='Holster',kind='HolsterLeft',model='Holster Left',twoHands=false,provider=true},
 ['tidy-hotbar-holster-right']={item='Base.Pistol',attachment='Holster',kind='HolsterRight',model='Holster Right',twoHands=false,provider=true},
}
function Hotbar.isCase(id)return cases[id]~=nil end
function Hotbar.ordinary(state)return cases[state.id]and cases[state.id].ordinary==true or false end
function Hotbar.radio(state)return cases[state.id]and cases[state.id].radio==true or false end
function Hotbar.flashlight(state)return cases[state.id]and cases[state.id].flashlight or false end
function Hotbar.passiveProducer(state)return Hotbar.ordinary(state)or Hotbar.radio(state)or Hotbar.flashlight(state)~=false end
local function providerType(spec)return spec.providerItem or ((spec.ordinary or spec.radio or spec.flashlight)and 'Base.Belt2'or 'Base.HolsterDouble')end
local function producerDuration(spec)return spec.flashlight=='deplete'and 3600 or 100 end
function Hotbar.provider(state)return Hotbar.passiveProducer(state)and state.belt or state.holster end
function Hotbar.providerLocation(state)local item=Hotbar.provider(state);return item and item:getBodyLocation()end
function Hotbar.expectedHands(state,restored)
 local spec=cases[state.id];if not spec then return nil,nil end
 local secondary=spec.priorSecondary and state.screwdriver or nil
 if restored then return nil,secondary end
 if (spec.ordinary or spec.radio or spec.flashlight)and not spec.priorSecondary then return nil,state.pickup end
 return state.pickup,spec.twoHands and state.pickup or secondary
end
function Hotbar.available(player,ids)
 if not Hotbar.passiveProducer({id=ids.case})then return true end
 if Hotbar.flashlight({id=ids.case})then
  local item=player:getInventory():getItemById(ids.items.pickup);local mode=cases[ids.case].flashlight
  local uses=item and(mode=='charged'and item:getMaxUses()or mode=='deplete'and 1 or 0)
  if not item or item:isActivated()or item:getCurrentUses()~=uses then return false end
 end
 if Hotbar.radio({id=ids.case})then
  local item=player:getInventory():getItemById(ids.items.pickup);local data=item and item:getDeviceData()
  if not data or data:getParent()~=item or data:getIsTurnedOn()~=(cases[ids.case].on==true)
   or data:getPower()~=1 or data:getChannel()~=88000 or math.abs(data:getDeviceVolume()-radioVolume(cases[ids.case].on))>0.0000001 or not data:getMicIsMuted()then return false end
 end
 return (ids.hotbarHair=='CrewCut'or ids.hotbarHair=='Bob')
  and tostring(player:getHumanVisual():getHairModel())==ids.hotbarHair and not player:getHumanVisual():getNonAttachedHair()
end
local function ordinarySnapshot(state,quiet)
 local item,player=state.hotbarTool or state.pickup,state.player;local visual=player:getHumanVisual()
 local color=visual:getHairColor()
 local secondary=cases[state.id].priorSecondary and state.screwdriver or nil
 if not quiet then assert(not secondary or state.root:getItemById(secondary:getID())==secondary and secondary:getContainer()==state.root
  and secondary:getFullType()=='Base.Screwdriver','ordinary hotbar baseline secondary identity/root changed')end
 return {condition=item:getCondition(),sharpness=item:getSharpness(),hairColor={r=color:getRedFloat(),g=color:getGreenFloat(),b=color:getBlueFloat()},hairStyle=tostring(visual:getHairModel()),nonAttachedHair=visual:getNonAttachedHair()or false,
  secondary=secondary and {id=secondary:getID(),fullType=secondary:getFullType(),container='root'}or false}
end
local function ordinaryMatches(state)
 local item=state.hotbarTool or state.pickup;local baseline=state.hotbarOrdinaryBaseline
 if not baseline or getClassSimpleName(item)~='ComboItem'or instanceof(item,'HandWeapon')or tostring(item:getScriptItem():getItemType())~='base:normal'
  or item:getCondition()~=baseline.condition or item:getSharpness()~=baseline.sharpness
  or tostring(state.player:getHumanVisual():getHairModel())~=baseline.hairStyle or state.player:getHumanVisual():getNonAttachedHair()then return false end
 local color=state.player:getHumanVisual():getHairColor()
 if not color or color:getRedFloat()~=baseline.hairColor.r or color:getGreenFloat()~=baseline.hairColor.g or color:getBlueFloat()~=baseline.hairColor.b then return false end
 local secondary=cases[state.id].priorSecondary and state.screwdriver or nil
 return not secondary or state.root:getItemById(secondary:getID())==secondary and secondary:getContainer()==state.root
  and secondary:getFullType()==baseline.secondary.fullType and secondary:getID()==baseline.secondary.id
end
local function radioSnapshot(state)
 local item=state.pickup;local data=item:getDeviceData();local tool=state.hotbarTool
 return {class=getClassSimpleName(item),deviceClass=data and getClassSimpleName(data)or false,
  parent=data and data:getParent()==item or false,canonical=tostring(item:getScriptItem():getItemType())=='base:radio',
  portable=data:getIsPortable(),batteryPowered=data:getIsBatteryPowered(),television=data:getIsTelevision(),
  hasBattery=data:getHasBattery(),turnedOn=data:getIsTurnedOn(),power=data:getPower(),channel=data:getChannel(),volume=data:getDeviceVolume(),
  micMuted=data:getMicIsMuted(),headphones=data:getHeadphoneType(),hasMedia=data:hasMedia(),playingMedia=data:isPlayingMedia(),activated=item:isActivated(),
  equippedRadio=not isServer()and state.player:getEquipedRadio()==item or false,emitter=data:getEmitter()~=nil,
  scissors={id=tool:getID(),fullType=tool:getFullType(),container=tool:getContainer()==state.root and 'root'or false},producer=ordinarySnapshot(state,true)}
end
local function radioMatches(state,restored)
 local item=state.pickup;local data=item:getDeviceData();local baseline=state.hotbarRadioBaseline
 if not data or not baseline or getClassSimpleName(item)~='Radio'or getClassSimpleName(data)~='DeviceData'
  or data:getParent()~=item then return false,'device-shape-parent' end
 if not ordinaryMatches(state)then return false,'scissors-hair' end
 local value=radioSnapshot(state)
 for key,expected in pairs(baseline)do
  if key~='power'and key~='turnedOn'and key~='equippedRadio'and key~='emitter'and key~='producer'and key~='scissors'and value[key]~=expected then return false,'setting:'..key end
 end
 if value.power~=value.power or value.power<0 or value.power>baseline.power or value.scissors.container~='root'
  or value.scissors.id~=baseline.scissors.id or value.scissors.fullType~=baseline.scissors.fullType then return false,'power-scissors-root' end
 if data:getIsTurnedOn()~=(cases[state.id].on==true and(isServer()or not restored))then return false,'turnedOn-phase' end
 -- Server updateTextObjects returns before radioEquipedCheck.
 if not isServer()and(state.player:getEquipedRadio()~=(not restored and item or nil)
  or (data:getEmitter()~=nil)~=(cases[state.id].on==true and not restored))then return false,'pointer-emitter' end
 return true
end
-- Native drainable depletion keeps the item and its activation bit; light
-- emission becomes false at zero. Native Unequip.start owns off+network sync.
local function flashlightSnapshot(state)
 local item,tool=state.pickup,state.hotbarTool
 return {class=getClassSimpleName(item),canonical=tostring(item:getScriptItem():getItemType())=='base:drainable',
  flashlight=item:hasTag(ItemTag.FLASHLIGHT),canActivate=item:canBeActivated(),keepOnDeplete=item:isKeepOnDeplete(),
  useWhileEquipped=item:isUseWhileEquiped(),useWhileUnequipped=item:isUseWhileUnequiped(),
  replaceOnDeplete=item:getReplaceOnDeplete()or false,cookable=item:isCookable(),onCooked=item:getOnCooked()or false,onEat=item:getOnEat()or false,
  lightStrength=item:getLightStrength(),lightDistance=item:getLightDistance(),torchCone=item:isTorchCone(),useDelta=item:getUseDelta(),
  maxUses=item:getMaxUses(),uses=item:getCurrentUses(),activated=item:isActivated(),emitting=item:isEmittingLight(),
  scissors={id=tool:getID(),fullType=tool:getFullType(),container=tool:getContainer()==state.root and 'root'or false},producer=ordinarySnapshot(state,true)}
end
local function flashlightMatches(state,restored)
 local baseline=state.hotbarFlashlightBaseline;local item=state.pickup;local mode=cases[state.id].flashlight
 if not baseline or not ordinaryMatches(state)then return false,'scissors-hair' end
 local value=flashlightSnapshot(state)
 for key,expected in pairs(baseline)do
  if key~='uses'and key~='activated'and key~='emitting'and key~='producer'and key~='scissors'and value[key]~=expected then return false,'setting:'..key end
 end
 if type(value.uses)~='number'or value.uses~=value.uses or value.uses%1~=0 or value.uses<0 or value.uses>baseline.uses
  or mode=='charged'and value.uses<=0 or mode~='charged'and value.uses~=0 then return false,'uses-phase' end
 local activated=mode~='empty'and not restored
 if value.activated~=activated or value.emitting~=(activated and value.uses>0)then return false,'activation-emission-phase' end
 if value.scissors.container~='root'or value.scissors.id~=baseline.scissors.id or value.scissors.fullType~=baseline.scissors.fullType then return false,'scissors-root' end
 return true
end
function Hotbar.flashlightReady(state,restored)return not Hotbar.flashlight(state)or flashlightMatches(state,restored)end
local function diagnosticValue(value)
 if type(value)~='table'then return tostring(value)end
 local keys,parts={},{};for key in pairs(value)do keys[#keys+1]=key end;table.sort(keys)
 for _,key in ipairs(keys)do parts[#parts+1]=key..'='..diagnosticValue(value[key])end
 return '{'..table.concat(parts,',')..'}'
end
local function diagnoseRadio(state,restored,reason,details)
 if state.hotbarRadioDiagnostic then return end
 state.hotbarRadioDiagnostic=true
 local ok,current=pcall(radioSnapshot,state)
 print('[EQUIPMENT_TEST] RADIO_STATE case='..state.id..' restored='..tostring(restored)..' reason='..tostring(reason)
  ..' baseline='..diagnosticValue(state.hotbarRadioBaseline)..' current='..(ok and diagnosticValue(current)or tostring(current))
  ..' readiness='..diagnosticValue(details or {}))
end
local function diagnoseFlashlight(state,restored,reason,details)
 if state.hotbarFlashlightDiagnostic then return end
 state.hotbarFlashlightDiagnostic=true
 local ok,current=pcall(flashlightSnapshot,state)
 print('[EQUIPMENT_TEST] FLASHLIGHT_STATE case='..state.id..' restored='..tostring(restored)..' reason='..tostring(reason)
  ..' baseline='..diagnosticValue(state.hotbarFlashlightBaseline)..' current='..(ok and diagnosticValue(current)or tostring(current))
  ..' readiness='..diagnosticValue(details or {}))
end
function Hotbar.radioReady(state,restored)return not Hotbar.radio(state)or radioMatches(state,restored)end
function Hotbar.diagnoseAuthority(state,restored)
 if Hotbar.flashlight(state)then
  local valid,reason=flashlightMatches(state,restored)
  if not valid then diagnoseFlashlight(state,restored,reason,{role='server',primary=state.player:getPrimaryHandItem()~=nil,secondary=state.player:getSecondaryHandItem()~=nil})end
  return
 end
 if not Hotbar.radio(state)then return end
 local valid,reason=radioMatches(state,restored)
 if not valid then diagnoseRadio(state,restored,reason,{role='server',primary=state.player:getPrimaryHandItem()~=nil,secondary=state.player:getSecondaryHandItem()~=nil})end
end
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
 local secondary=cases[state.id].priorSecondary and state.screwdriver or nil
 local capture='capture primary=nil secondary='..(secondary and secondary:getFullType()..'#'..secondary:getID()..'@'..state.root:getType()or 'nil')
 if message==capture then
  if proof then proof.problem='duplicate P4 hotbar capture';return end
  proof={session=session};state.hotbarP4=proof
 end
 if not proof or proof.session~=session then return end
 if message:match('^capture worn=%[.-%] inventoryCount=%d+$')then
  local provider=Hotbar.provider(state)
  proof.worn=not provider or message:find(tostring(Hotbar.providerLocation(state))..'='..provider:getFullType()..'#'..provider:getID()..'@'..state.root:getType(),1,true)~=nil
 end
 local item=state.pickup:getFullType()..'#'..state.pickup:getID()..'@'..state.root:getType()
 if message:find('^add%[%w+%] type=ISEquipWeaponAction item=')and message:find(item,1,true)then proof.equip=true end
 local producer=Hotbar.passiveProducer(state)and 'ISCutHair'or 'ISRackFirearm'
 local tool=state.hotbarTool or state.pickup;local producerItem=tool:getFullType()..'#'..tool:getID()..'@'..state.root:getType()
 if message:find('^add%[%w+%] type='..producer..' item=')and message:find('item='..(Hotbar.passiveProducer(state)and producerItem or 'nil'),1,true)then proof.producer=true end
 local trace='ISReadABook -> ISEquipWeaponAction -> '..producer..' -> ISReadABook'
 if message:find('^finish ')then
  proof.finished=message:find('finish armed=true cancelled=false prep=true transfer=false operation=true',1,true)~=nil
   and message:find('restoreHands=true restoreWorn='..(Hotbar.passiveProducer(state)and 'true'or 'false'),1,true)~=nil
   and message:find('actionTotal=4 transferCount=0',1,true)~=nil and message:find('trace=['..trace..']',1,true)~=nil
 end
 if message:find('^RESTORE actionTotal=')then
  if proof.restore or not proof.worn or not proof.equip or not proof.producer or not proof.finished
   or not message:find('RESTORE actionTotal=4 trace=['..trace..']',1,true)then proof.problem='P4 hotbar restore lacks exact native producer session' end
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
 Events.OnServerCommand.Add(function(module,command)
  if module=='PZSurvivorToolkitActions'and command=='State'and watched and Hotbar.passiveProducer(watched)then
   Hotbar.observe(watched,ISTimedActionQueue.getTimedActionQueue(watched.player),PZSurvivorToolkit,true)
  end
 end)
 installed=true
end
function Hotbar.configure(state,index)
 local spec=cases[state.id]
 assert(type(index)=='number'and index%1==0 and index>=1 and (spec.provider and index>1 or not spec.provider and index==1),'invalid native hotbar index')
 for _,other in pairs(state.originalAttached)do assert(other:getAttachedSlot()~=index,'native hotbar slot already occupied')end
 state.hotbarIndex=index
 local item=state.pickup
 state.player:setAttachedItem(state.hotbarLocation,item)
 item:setAttachedSlot(index);item:setAttachedSlotType(state.hotbarType);item:setAttachedToModel(state.hotbarLocation)
end
function Hotbar.prepare(state,seed)
 local spec=assert(cases[state.id],'unknown hotbar fixture case')
 local player=state.player
 if spec.provider then
  seed('belt',spec.providerItem or 'Base.Belt2');player:setWornItem(state.belt:getBodyLocation(),state.belt)
 end
 if spec.provider and not(spec.ordinary or spec.radio or spec.flashlight)then
  seed('holster','Base.HolsterDouble');state.holsterLocation=state.holster:getBodyLocation()
  player:setWornItem(state.holsterLocation,state.holster)
  assert(tostring(state.holsterLocation)=='base:beltextra','native double holster location differs')
 end
 seed('pickup',spec.item)
 local item=state.pickup
 state.hotbarTwoHands=spec.twoHands
 assert(item:getAttachmentType()==spec.attachment and (spec.flashlight and item:canBeActivated()or not spec.flashlight and not item:canBeActivated())and not isForceDropHeavyItem(item)
  and not player:getWornItems():contains(item)and (spec.ordinary or spec.radio or spec.flashlight or item:getCurrentAmmoCount()==0 and not item:isRoundChambered()),
  'native hotbar activation/worn/heavy fixture shape differs')
 state.hotbarIndex,state.hotbarType,state.hotbarLocation=spec.index,spec.kind,spec.model
 state.originalAttached={}
 local entries=player:getAttachedItems()
 for i=0,entries:size()-1 do
  local entry=entries:get(i);local other=entry:getItem()
  if other~=item then
   assert(other:getAttachedSlot()~=state.hotbarIndex and tostring(entry:getLocation())~=state.hotbarLocation,
    'fresh fixture requires a vacant native hotbar slot/model')
   state.originalAttached[tostring(entry:getLocation())]=other
  end
 end
 if spec.radio then
  seed('hotbarTool','Base.ScissorsBluntMedical')
  local data=assert(item:getDeviceData(),'native radio device missing')
  assert(getClassSimpleName(item)=='Radio'and getClassSimpleName(data)=='DeviceData'and data:getParent()==item
   and tostring(item:getScriptItem():getItemType())=='base:radio'and data:getIsPortable()and data:getIsBatteryPowered()
   and not data:getIsTelevision()and not data:hasMedia()and not data:isPlayingMedia(),'native portable radio shape differs')
  if not isClient()then
   data:setHasBattery(true);data:setPower(1);data:setChannelRaw(88000);data:setDeviceVolumeRaw(radioVolume(spec.on));data:setMicIsMuted(true)
   data:setTurnedOnRaw(spec.on==true)
  end
 end
 if spec.flashlight then
  seed('hotbarTool','Base.ScissorsBluntMedical')
  assert(getClassSimpleName(item)=='DrainableComboItem'and tostring(item:getScriptItem():getItemType())=='base:drainable'
   and item:hasTag(ItemTag.FLASHLIGHT)and item:isKeepOnDeplete()and not item:getReplaceOnDeplete()
   and item:isUseWhileEquiped()and not item:isUseWhileUnequiped()and not item:isCookable()
   and not item:getOnCooked()and not item:getOnEat(),'native kept flashlight shape differs')
  if not isClient()then
   item:setCurrentUses(spec.flashlight=='charged'and item:getMaxUses()or spec.flashlight=='deplete'and 1 or 0)
   item:setActivated(false)
  end
 end
 if spec.ordinary or spec.radio or spec.flashlight then
  local tool=state.hotbarTool or item
  assert(getClassSimpleName(tool)=='ComboItem'and not instanceof(tool,'HandWeapon')and tostring(tool:getScriptItem():getItemType())=='base:normal'and tool:getCondition()==10 and tool:getSharpness()==1,'ordinary hotbar fixture needs the native nonweapon normal item')
  state.hotbarHair=state.ids and state.ids.hotbarHair or (player:isFemale()and 'Bob'or 'CrewCut')
  assert(state.hotbarHair==(player:isFemale()and 'Bob'or 'CrewCut'),'ordinary hotbar requires configured plain native hair')
  local styles=getHairStylesInstance();local style=player:isFemale()and styles:FindFemaleStyle(state.hotbarHair)or styles:FindMaleStyle(state.hotbarHair)
  assert(style and tostring(style:getName())==state.hotbarHair and not style:isAttachedHair(),'ordinary hotbar haircut must not consume styling items')
  if isClient()then assert(Hotbar.available(player,state.ids),'ordinary hotbar hair setup has not replicated')
  else local visual=player:getHumanVisual();visual:setNonAttachedHair(nil);visual:setHairModel(state.hotbarHair);player:resetModel();if isServer()then sendHumanVisual(player)end end
  state.hotbarOrdinaryBaseline=ordinarySnapshot(state)
  if spec.radio then state.hotbarRadioBaseline=radioSnapshot(state)end
  if spec.flashlight then state.hotbarFlashlightBaseline=flashlightSnapshot(state)end
 end
 local primary,secondary=Hotbar.expectedHands(state,true)
 player:setPrimaryHandItem(primary);player:setSecondaryHandItem(secondary)
 if isServer()then
  -- Only the client owns native saved hotbar ordering. Providers are configured
  -- by its setup handshake before any timed actions are enqueued.
  if not spec.provider then Hotbar.configure(state,spec.index)end
 else
  local hotbar=assert(getPlayerHotbar(player:getPlayerNum()));hotbar:refresh()
  local index=hotbar:getThisSlotIndex(state.hotbarType)
  assert(index and (spec.provider or index==1),'native hotbar slot index missing')
  Hotbar.configure(state,index);hotbar:reloadIcons()
  local slot=assert(hotbar.availableSlot[state.hotbarIndex],'native hotbar slot missing')
  assert(slot.def.type==state.hotbarType and slot.slotType==state.hotbarType
   and slot.def.attachments[spec.attachment]==(spec.baseModel or spec.model)
   and (not spec.baseModel or hotbar.replacements and hotbar.replacements[spec.attachment]==state.hotbarLocation)
   and hotbar.attachedItems[state.hotbarIndex]==item,'native hotbar definition/replacement/index/icon differs')
 end
end
function Hotbar.enqueue(state,helpers)
 local queue=helpers.queue();local before=#queue.queue
 local spec=cases[state.id]
 if spec.ordinary or spec.radio or spec.flashlight then
  require 'TimedActions/ISCutHair'
  helpers.run(function()
   getPlayerHotbar(state.player:getPlayerNum()):equipItem(state.pickup)
   ISTimedActionQueue.add(ISCutHair:new(state.player,state.hotbarHair,state.hotbarTool or state.pickup,producerDuration(spec)))
  end)
 else helpers.run(ISInventoryPaneContextMenu.onRackGun,state.player,state.pickup)end
 assert(#queue.queue==before+2,'native root hotbar producer must enqueue only equip and operation')
 local equip,rack=queue.queue[before+1],queue.queue[before+2]
 local primary=not(spec.ordinary or spec.radio or spec.flashlight)or spec.priorSecondary==true
 assert(equip.Type=='ISEquipWeaponAction'and equip.item==state.pickup and equip.primary==primary and equip.twoHands==state.hotbarTwoHands
  and equip.fromHotbar and equip.hotbar==getPlayerHotbar(state.player:getPlayerNum())and equip.maxTimeInit==((spec.ordinary or spec.radio or spec.flashlight)and 20 or 50)
  and type(equip.maxTime)=='number'and equip.maxTime>1 and equip.maxTime<math.huge
  and equip.create==ISBaseTimedAction.create and equip.adjustMaxTime==ISBaseTimedAction.adjustMaxTime
  and equip.animEvent==ISEquipWeaponAction.animEvent,'native fromHotbar equip differs')
 if spec.ordinary or spec.radio or spec.flashlight then assert(rack.Type=='ISCutHair'and rack.item==(state.hotbarTool or state.pickup) and rack.hairStyle==state.hotbarHair and rack.maxTime==producerDuration(spec) and rack.complete==ISCutHair.complete,'native ordinary hotbar producer differs')
 else assert(rack.Type=='ISRackFirearm'and rack.gun==state.pickup,'native hotbar rack callback missing')end
 state.hotbarEquip,state.rackAction=equip,rack
end
function Hotbar.observe(state,queue,toolkit,tidy)
 if Hotbar.radio(state)and not isServer()and state.player:getEquipedRadio()==state.pickup then
  state.hotbarRadioHeldPointer=true
  if state.pickup:getDeviceData():getEmitter()then state.hotbarRadioEmitterStarted=true end
 end
 if Hotbar.flashlight(state)and not isServer()and state.player:isHandItem(state.pickup)then
  local item=state.pickup
  state.hotbarFlashlightHeld=true
  if item:isActivated()then
   state.hotbarFlashlightActivated=true
   if item:isEmittingLight()then state.hotbarFlashlightEmitted=true end
   if item:getCurrentUses()==0 and not item:isEmittingLight()then state.hotbarFlashlightDepleted=true end
  end
 end
 if Hotbar.flashlight(state)and Hotbar.flashlight(state)~='empty'and state.hotbarRestoreAction and state.hotbarRestoreAction:isStarted()
  and not state.pickup:isActivated()then state.hotbarFlashlightDeactivated=true end
 local current=queue.current
 if current and current==state.rackAction and current:isStarted()then state.hotbarProducerStarted=true end
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
    if kind~='compat.tidy-equipment'and not state.hotbarGuardDiagnostic then
     state.hotbarGuardDiagnostic=true
     local item=action.item;local script=item:getScriptItem();local values={'kind='..tostring(kind),'class='..tostring(getClassSimpleName(item))}
     for _,entry in ipairs({{item,{'getFullType','hasComponents','getFluidContainer','isWet','getItemWhenDry'}},
      {script,{'getFullName','getItemType','getLuaCreate','getItemConfig','getItemConfigKey','hasComponents'}}})do
      for _,name in ipairs(entry[2])do
       local target=entry[1];local callback=target and target[name]
       values[#values+1]=name..':'..type(callback)..'='..tostring(type(callback)=='function'and callback(target)or false)
      end
     end
     local scripts=script:getComponentScripts();local attributes=item:getAttributes()
     values[#values+1]='scriptCount='..scripts:size()..' componentCount='..item:componentSize()
     for i=0,scripts:size()-1 do values[#values+1]='script'..i..'='..getClassSimpleName(scripts:get(i))end
     values[#values+1]='attributes='..tostring(attributes and getClassSimpleName(attributes))
     values[#values+1]='attributesType='..tostring(attributes and attributes:getComponentType())
     values[#values+1]='attributesOwner='..tostring(attributes and attributes:getOwner()==item)
     values[#values+1]='attributesIndex='..tostring(attributes and item:getComponentForIndex(0)==attributes)
     values[#values+1]='attributesMapping='..tostring(ComponentType.Attributes and scripts:size()==1 and script:getComponentScriptFor(ComponentType.Attributes)==scripts:get(0))
     local hotbar=getPlayerHotbar(state.player:getPlayerNum());local count=0
     for _,slot in pairs(hotbar.availableSlot)do if slot.def.type==item:getAttachedSlotType()then count=count+1 end end
     values[#values+1]='slotCount='..count..' attached='..tostring(hotbar:isItemAttached(item))
     values[#values+1]='held='..tostring(state.player:isHandItem(item))..' nativePerform='..tostring(action.perform==ISUnequipAction.perform)
     local carts=toolkit.ActionQueueCarts
     values[#values+1]='cartConstructor='..tostring(carts.isUnequipConstructor(ISUnequipAction.new))..' nonCart='..tostring(carts.isNonCartItem(item))
     print('[EQUIPMENT_TEST] HOTBAR_GUARD '..table.concat(values,' '))
    end
    assert(kind=='compat.tidy-equipment','P4 hotbar cleanup lacks verified scoped origin')
   end
   if isClient()and not state.hotbarRestoreReceipt then state.hotbarRestoreReceipt=toolkit.ActionQueueAcknowledgements.capture(action)end
  end
 end
 if Hotbar.passiveProducer(state)and isClient()then
  state.hotbarReceipts=state.hotbarReceipts or {}
  for _,action in ipairs({state.hotbarEquip,state.rackAction,state.hotbarRestoreAction})do
   if action and not state.hotbarReceipts[action]then state.hotbarReceipts[action]=toolkit.ActionQueueAcknowledgements.capture(action)end
  end
 end
end
function Hotbar.verify(state,restored,checkpoint)
 local player,item=state.player,state.pickup
 local spec=cases[state.id]
 local live=assert(state.root:getItemById(item:getID()),'exact hotbar identity missing from root')
 assert(live==item and item:getFullType()==spec.item and item:getContainer()==state.root,'hotbar ID/type/root changed')
 assert(item:getAttachedSlot()==state.hotbarIndex and item:getAttachedSlotType()==state.hotbarType
  and item:getAttachedToModel()==state.hotbarLocation,'hotbar original metadata changed')
 local radioValid,radioReason=true,nil
 if spec.radio then
  radioValid,radioReason=radioMatches(state,restored)
  if not radioValid then diagnoseRadio(state,restored,radioReason)end
 end
 local flashlightValid,flashlightReason=true,nil
 if spec.flashlight then
  flashlightValid,flashlightReason=flashlightMatches(state,restored)
  if not flashlightValid then diagnoseFlashlight(state,restored,flashlightReason)end
 end
 assert(not player:getWornItems():contains(item)and (spec.flashlight and item:canBeActivated()or not spec.flashlight and not item:canBeActivated())and not isForceDropHeavyItem(item)
  and (spec.flashlight and flashlightValid or spec.radio and radioValid or spec.ordinary and ordinaryMatches(state)or not(spec.ordinary or spec.radio or spec.flashlight)and item:getCurrentAmmoCount()==0 and not item:isRoundChambered()),'hotbar ordinary item/ammunition changed')
 local primary,secondary=Hotbar.expectedHands(state,restored)
 assert(player:getPrimaryHandItem()==primary and player:getSecondaryHandItem()==secondary,'hotbar final baseline/held hands differ')
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
 local provider=Hotbar.provider(state);local location=Hotbar.providerLocation(state)
 if spec.provider then
  assert(provider and provider:getFullType()==providerType(spec)and provider:getContainer()==state.root
   and state.root:getItemById(provider:getID())==provider and player:getWornItem(location)==provider,'exact worn hotbar provider changed')
 end
 if checkpoint then state.hotbarDetached=true end
 local function id(value)return value and value:getID()or false end
 local result={case=state.id,providerItem=id(provider),
  providerType=provider and provider:getFullType()or false,providerLocation=provider and tostring(location)or false,
  providerWorn=spec.provider==true,id=item:getID(),fullType=item:getFullType(),container='root',slotIndex=state.hotbarIndex,slotType=state.hotbarType,
  model=state.hotbarLocation,attached=restored,primary=id(primary),secondary=id(secondary),worn=false,
  producer=(spec.ordinary or spec.radio or spec.flashlight)and 'ISCutHair'or 'onRackGun',producerCompleted=true,ammoUnchanged=not(spec.ordinary or spec.radio or spec.flashlight)and true or nil,unrelatedAttachmentsPreserved=true}
 if spec.ordinary then result.ordinary=ordinarySnapshot(state);if not checkpoint then result.ordinaryBaseline=state.hotbarOrdinaryBaseline end end
 if spec.radio then result.radio=radioSnapshot(state);if not checkpoint then result.radioBaseline=state.hotbarRadioBaseline end end
 if spec.flashlight then result.flashlight=flashlightSnapshot(state);if not checkpoint then result.flashlightBaseline=state.hotbarFlashlightBaseline end end
 return result
end
function Hotbar.settled(state,toolkit,tidy)
 -- This is a per-tick readiness probe. Vanilla assert logs even inside pcall;
 -- defer assert-based verification until the replicated state is ready.
 local player,root,item=state.player,state.root,state.pickup
 local spec=cases[state.id]
 if not spec or not player or not root or not item or player:getInventory()~=root then return false end
 local live=root:getItemById(item:getID())
 if live~=item or item:getFullType()~=spec.item or item:getContainer()~=root then return false end
 if item:getAttachedSlot()~=state.hotbarIndex or item:getAttachedSlotType()~=state.hotbarType
  or item:getAttachedToModel()~=state.hotbarLocation then return false end
 local primary,secondary=Hotbar.expectedHands(state,tidy)
 if player:getPrimaryHandItem()~=primary or player:getSecondaryHandItem()~=secondary then return false end
 if player:getWornItems():contains(item)or item:canBeActivated()~=(spec.flashlight~=nil)or isForceDropHeavyItem(item)
  or (spec.flashlight and not flashlightMatches(state,tidy)or spec.radio and not radioMatches(state,tidy)or spec.ordinary and not ordinaryMatches(state)or not(spec.ordinary or spec.radio or spec.flashlight)and(item:getCurrentAmmoCount()~=0 or item:isRoundChambered()))then return false end
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
 local provider=Hotbar.provider(state)
 if spec.provider and(not provider or provider:getFullType()~=providerType(spec)
  or provider:getContainer()~=root or root:getItemById(provider:getID())~=provider or player:getWornItem(Hotbar.providerLocation(state))~=provider)then return false end
 if (spec.ordinary or spec.radio or spec.flashlight)and isClient()then
  for _,action in ipairs({state.hotbarEquip,state.rackAction,state.hotbarRestoreAction})do
   local receipt=state.hotbarReceipts and state.hotbarReceipts[action]
   if not receipt or toolkit.ActionQueueAcknowledgements.observe(action,receipt)~='completed'then return false end
  end
 end
 if tidy then
  local source=state.hotbarP4
  if not state.hotbarRestoreAction or not state.hotbarAttachConnect or not source or not source.restore
   or not source.completed or source.problem then return false end
  if isClient()and(not state.hotbarRestoreReceipt or toolkit.ActionQueueAcknowledgements.observe(state.hotbarRestoreAction,state.hotbarRestoreReceipt)~='completed')then return false end
 end
 return true
end
-- Diagnose a quiet final wait only after P4 has completed and the normal
-- convergence grace elapsed. This reads state; it does not advance or repair it.
function Hotbar.diagnoseWaiting(state,queue,toolkit,tidy,now,gates)
 local flashlight=Hotbar.flashlight(state)
 if not(Hotbar.radio(state)or flashlight)or (flashlight and state.hotbarFlashlightDiagnostic or not flashlight and state.hotbarRadioDiagnostic)or not gates
  or (gates.phase~='drain'and gates.phase~='checkpoint'and gates.phase~='checkpointReceipt')then return end
 local source=state.hotbarP4
 if not source or not source.completed then return end
 if not state.hotbarRadioGraceAt then state.hotbarRadioGraceAt=now;return end
 if now-state.hotbarRadioGraceAt<1000 then return end
 local settled=Hotbar.settled(state,toolkit,tidy)
 if settled and gates.phase=='drain'and gates.empty==true and gates.idleUpdates>=6 and gates.finalGate~='transactions'then return end
 local player,root,item=state.player,state.root,state.pickup
 local valid,reason
 if flashlight then valid,reason=flashlightMatches(state,tidy)else valid,reason=radioMatches(state,tidy)end
 local function id(value)return value and value:getID()or false end
 local bar=getPlayerHotbar(player:getPlayerNum())
 local provider=Hotbar.provider(state);local location=Hotbar.providerLocation(state)
 local primary,secondary=Hotbar.expectedHands(state,tidy)
 local attached=player:getAttachedItems():getItem(state.hotbarLocation)
 local details={phase=gates.phase,finalGate=gates.finalGate or 'not-reached',idleUpdates=gates.idleUpdates,empty=gates.empty,settled=settled,radioMatches=valid,
  queueSize=#queue.queue,current=queue.current and queue.current.Type or false,
  primary=id(player:getPrimaryHandItem()),secondary=id(player:getSecondaryHandItem()),expectedPrimary=id(primary),expectedSecondary=id(secondary),
  canonical=root:getItemById(item:getID())==item,root=player:getInventory()==root,itemRoot=item:getContainer()==root,
  slotIndex=item:getAttachedSlot(),expectedIndex=state.hotbarIndex,slotType=item:getAttachedSlotType(),expectedType=state.hotbarType,
  model=item:getAttachedToModel(),expectedModel=state.hotbarLocation,attached=id(attached),icon=bar and bar.attachedItems and id(bar.attachedItems[state.hotbarIndex])or false,
  provider=id(provider),providerRoot=provider and provider:getContainer()==root or false,providerWorn=provider and player:getWornItem(location)==provider or false,
  sourceSession=source.session or false,sourceRestore=source.restore==true,sourceCompleted=source.completed==true,sourceProblem=source.problem or false,
  attachConnect=state.hotbarAttachConnect==true,restoreAction=state.hotbarRestoreAction~=nil,producerStarted=state.hotbarProducerStarted==true,detached=state.hotbarDetached==true,
  heldPointerObserved=state.hotbarRadioHeldPointer==true,emitterObserved=state.hotbarRadioEmitterStarted==true,receipts={}}
 for _,action in ipairs({state.hotbarEquip,state.rackAction,state.hotbarRestoreAction})do
  local receipt=state.hotbarReceipts and state.hotbarReceipts[action]
  details.receipts[#details.receipts+1]=action.Type..':'..(isClient()and(receipt and toolkit.ActionQueueAcknowledgements.observe(action,receipt)or 'missing')or 'sp')
 end
 local receipt=state.hotbarRestoreReceipt
 details.restoreReceipt=isClient()and(receipt and toolkit.ActionQueueAcknowledgements.observe(state.hotbarRestoreAction,receipt)or 'missing')or 'sp'
 if flashlight then diagnoseFlashlight(state,tidy,reason or 'surrounding-readiness',details)
 else diagnoseRadio(state,tidy,reason or 'surrounding-readiness',details)end
end
function Hotbar.evidence(state,toolkit,tidy,completion)
 assert(state.hotbarProducerStarted and state.hotbarDetached,'native hotbar producer/detached checkpoint missing')
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
 if Hotbar.radio(state)then
  assert(state.hotbarRadioHeldPointer,'native held radio pointer never observed')
  assert(not cases[state.id].on or state.hotbarRadioEmitterStarted,'powered native radio emitter never observed')
  result.radioLifecycle={heldPointer=true,emitterCreated=state.hotbarRadioEmitterStarted==true,emitterCleaned=cases[state.id].on==true and tidy or false}
 end
 if Hotbar.flashlight(state)then
  local mode=cases[state.id].flashlight
  assert(state.hotbarFlashlightHeld,'native held flashlight never observed')
  assert(mode=='empty'or state.hotbarFlashlightActivated and state.hotbarFlashlightEmitted,'native flashlight activation/emission never observed')
  assert(mode~='deplete'or state.hotbarFlashlightDepleted,'native kept same-item depletion while activated never observed')
  assert(mode~='empty'or not state.hotbarFlashlightActivated and not state.hotbarFlashlightEmitted and not state.hotbarFlashlightDepleted,'empty flashlight unexpectedly activated/emitted/depleted')
  assert(not tidy or mode=='empty'or state.hotbarFlashlightDeactivated,'native flashlight cleanup deactivation never observed')
  result.flashlightLifecycle={held=true,activated=mode~='empty',emitted=mode~='empty',depleted=mode=='deplete',deactivated=state.hotbarFlashlightDeactivated==true}
 end
 if Hotbar.passiveProducer(state)then
  result.acknowledgements={}
  if isClient()then
   for _,action in ipairs({state.hotbarEquip,state.rackAction,state.hotbarRestoreAction})do
    local receipt=assert(state.hotbarReceipts and state.hotbarReceipts[action],'ordinary hotbar native receipt missing')
    assert(toolkit.ActionQueueAcknowledgements.observe(action,receipt)=='completed','ordinary hotbar native receipt incomplete')
    result.acknowledgements[#result.acknowledgements+1]={kind=action.Type,id=action.item and action.item:getID()or false,state='completed'}
   end
  end
 end
 return result
end
function Hotbar.release(state)
 local item=state.pickup
 state.player:removeAttachedItem(item);item:setAttachedSlot(-1);item:setAttachedSlotType(nil);item:setAttachedToModel(nil)
 if not isServer()then local hotbar=getPlayerHotbar(state.player:getPlayerNum());if hotbar then hotbar:reloadIcons()end end
end
return Hotbar
