if not NativeActionRoot then print('Equipment slot native checks skipped (pass --native-action-root).'); return end
function require() end
function isServer() return false end
function isClient() return false end
function syncItemFields() end
ItemBodyLocation=setmetatable({SOCKS='base:socks',HAT='base:hat',FULL_HAT='base:fullhat'},{__index=function(_,key) return key end})
ItemTag={WEARABLE='Wearable'}
ISBaseTimedAction={}
function ISBaseTimedAction:derive(name) local c={Type=name};setmetatable(c,{__index=self});c.__index=c;return c end
function ISBaseTimedAction:new(chr) return setmetatable({character=chr},self) end
function ISBaseTimedAction:adjustMaxTime(time) return time end
function ISBaseTimedAction.perform() end
function instanceof(item,kind) return item.kind and item.kind:find('WristWatch',1,true)~=nil and (kind=='AlarmClockClothing'or kind=='Clothing')or false end
ISInventoryPage={}

local function native(path) assert(loadfile(NativeActionRoot..'/'..path))() end
native('shared/TimedActions/ISWearClothing.lua')
native('shared/TimedActions/ISAttachItemHotbar.lua')
native('client/TimedActions/ISDetachItemHotbar.lua')
local function read(path)
 local file=assert(io.open(NativeActionRoot..'/'..path));local text=file:read('*a');file:close();return text
end
local function excerpt(source,first,last)
 local start=assert(source:find(first,1,true));local finish=assert(source:find(last,start+#first,true))
 assert(loadstring(source:sub(start,finish-1)))()
end
ISInventoryPaneContextMenu={};ISInventoryPane={getActualItems=function(items) return items end}
local context=read('client/ISUI/ISInventoryPaneContextMenu.lua')
excerpt(context,'ISInventoryPaneContextMenu.onWearItems = function','ISInventoryPaneContextMenu.onActivateItem = function')
excerpt(context,'ISInventoryPaneContextMenu.wearItem = function','ISInventoryPaneContextMenu.onPutItems = function')
ISHotbar={}
excerpt(read('client/Hotbar/ISHotbar.lua'),'function ISHotbar:attachItem (','function ISHotbar:reloadIcons()')
local Slots=assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/shared/QueueEquipmentSlots.lua'))()
local nextID=0
function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
function container() return {items={},getItems=function(self) return {isEmpty=function() return next(self.items)==nil end} end} end
function makeItem(kind,dest)
 nextID=nextID+1
 local i={kind=kind,id=nextID,container=dest,slot=-1}
 function i:getID() return self.id end
 function i:getBodyLocation()
  if self.kind=='Base.Socks_Ankle'or self.kind=='Base.Socks_Long'then return 'base:socks'
  elseif self.kind=='Base.WristWatch_Left_DigitalBlack'then return 'base:leftwrist'
  elseif self.kind=='Base.WristWatch_Right_ClassicBlack'then return 'base:rightwrist'
  elseif self.kind=='Base.Hat_Beany'then return 'base:hat'
  elseif self.kind=='Base.Hat_BoxingRed'then return 'base:fullhat'
  elseif self.kind=='Base.Belt2'then return 'BELT'end
  return ''
 end
 function i:canBeEquipped() end
 function i:getAttachmentType() if self.kind=='Base.HuntingKnife' then return 'Knife' elseif self.kind=='Base.Hammer' then return 'Hammer' end return 'Shovel' end
 function i:getFullType() return self.kind end
 function i:setFavorite(value) self.favorite=value end
 function i:isFavorite() return self.favorite==true end
 function i:getContainer() return self.container end
 function i:getAttachedSlot() return self.slot end
 function i:setAttachedSlot(v) self.slot=v end
 function i:getAttachedSlotType() return self.slotType end
 function i:setAttachedSlotType(v) self.slotType=v end
 function i:getAttachedToModel() return self.model end
 function i:setAttachedToModel(v) self.model=v end
 function i:hasTag() return false end
 function i:getCategory() return self.kind:find('WristWatch',1,true)and 'AlarmClock'or 'Clothing' end
 function i:getHour()return self.hour end;function i:getMinute()return self.minute end
 function i:setHour(value)self.hour=value end;function i:setMinute(value)self.minute=value end
 function i:isAlarmSet()return self.alarm==true end;function i:isRinging()return self.ringing==true end
 function i:setAlarmSet(value)self.alarm=value;self.ringing=false end
 function i:syncAlarmClock()self.alarmSynced=true end
 function i:isBroken() return false end
 function i:getClothingItem() return true end
 function i:getEquipSound() end
 function i:getJobDelta() return 0 end
 function i:setJobDelta() end
 function i:IsInventoryContainer() return false end
 dest.items[i]=true;return i
end
local function runCase(id,favorite)
 local player={worn={},attached={}}
 function player:isEquipped() return false end
 function player:isTimedActionInstant() return false end
 function player:hasTimedActions() return false end
 function player:getPlayerNum() return 0 end
 function player:getAttachedItems()
  local entries={};for location,item in pairs(self.attached) do local loc,it=location,item;entries[#entries+1]={getLocation=function() return loc end,getItem=function() return it end} end
  return list(entries)
 end
 function player:setAttachedItem(location,item) self.attached[location]=item end
 function player:removeAttachedItem(item) for location,value in pairs(self.attached) do if value==item then self.attached[location]=nil end end end
 function player:getHumanVisual() return {getHairModel=function() return {contains=function() return false end} end} end
 function player:getWornItem(location) return self.worn[location] end
 function player:setWornItem(location,item) self.worn[location]=item end
 function player:removeFromHands() end
 function player:getWornItems() return {contains=function(_,item) for _,value in pairs(player.worn) do if value==item then return true end end return false end} end
 function player:getPrimaryHandItem() return self.hammer end
 function player:getSecondaryHandItem() return self.screwdriver end
 local state={id=id,options={belt_favorite=favorite==true},player=player,root=container(),source=container(),expectedWorn={}}
 local unrelated=makeItem('Base.HolsterSimple',state.root)
 local unrelatedIndex=Slots.isBelt(id) and 4 or 2
 unrelated:setAttachedSlot(unrelatedIndex);unrelated:setAttachedSlotType('HolsterRight');unrelated:setAttachedToModel('Holster Right')
 player:setAttachedItem('Holster Right',unrelated)
 state.hammer=makeItem('Base.Hammer',state.root);state.screwdriver=makeItem('Base.Screwdriver',state.root)
 player.hammer,player.screwdriver=state.hammer,state.screwdriver
 if Slots.isBelt(id) then
  state.bag=makeItem('Base.Bag_ALICEpack_Army',state.root);state.location='Back';player:setWornItem(state.location,state.bag)
 end
 local queue={queue={}}
 ISTimedActionQueue={add=function(action) queue.queue[#queue.queue+1]=action end}
 function ISInventoryPaneContextMenu.transferIfNeeded(_,item)
  if item.container~=state.root then ISTimedActionQueue.add({Type='ISInventoryTransferAction',item=item,srcContainer=item.container,destContainer=state.root}) end
 end
 function getSpecificPlayer() return player end
 local hotbar={chr=player,attachedItems={},availableSlot={{def={name='Back',type='Back',attachments={Shovel='Shovel Back'}}}},replacements={Shovel='Shovel Back with Bag'}}
 hotbar.availableSlot[2]={def={name='Belt Left',type='SmallBeltLeft',attachments={Knife='Belt Left Upside',Hammer='Belt Left'}}}
 setmetatable(hotbar,{__index=ISHotbar})
 function hotbar:refresh() end
 function hotbar:setAttachAnim() end
 function hotbar:reloadIcons() self.attachedItems={};for _,item in pairs(player.attached) do self.attachedItems[item:getAttachedSlot()]=item end end
 function getPlayerHotbar() return hotbar end
 local identities={}
 Slots.prepare(state,function(name,kind,dest)
  state[name]=makeItem(kind,dest or state.root);local item=state[name]
  assert(not identities[item:getID()]);identities[item:getID()]=item;return item
 end)
 if Slots.isBelt(id) then
  queue.queue[1]={}
  assert(not pcall(Slots.enqueue,state,{queue=function() return queue end}),'belt fixture accepted a nonempty queue')
  queue.queue={}
 end
 assert(Slots.enqueue(state,{queue=function() return queue end,run=function(fn,...) return fn(...) end}))
 state.tailAction={};local denied=0
 if Slots.isBelt(id) then
  assert(#queue.queue==2 and queue.queue[1].Type=='ISInventoryTransferAction' and queue.queue[2].Type=='ISAttachItemHotbar'
   and queue.queue[2].start==ISAttachItemHotbar.start and queue.queue[2].isValid==ISAttachItemHotbar.isValid,
   'empty belt must retain unmodified native transfer/attach methods')
 else
  Slots.controls(state,{native=false,denied=function(_,_,_,reason) assert(reason=='move_dependent');denied=denied+1 end})
  assert(denied==2 and state.policyChecked)
 end
 for _,action in ipairs(queue.queue) do
  if action.Type=='ISInventoryTransferAction' then action.srcContainer.items[action.item]=nil;action.destContainer.items[action.item]=true;action.item.container=action.destContainer
  elseif action.Type=='ISWearClothing' then assert(action:complete())
  elseif action.Type=='ISAttachItemHotbar' then
   assert(action:complete() and player:getAttachedItems():size()==1 and action.item:getAttachedSlot()==-1,
    'native server attach complete must leave client-owned effects untouched')
   action:perform()
  else action:perform() end
 end
 local outcome=Slots.verify(state,'toolkit');assert(outcome.slotsVerified)
 for identity,item in pairs(identities) do assert(item:getID()==identity,'fixture item identity changed') end
 if id=='clothing-chain' then
  assert(outcome.clothingItem==state.clothingB:getID() and state.expectedWorn[state.clothingLocation]==state.clothingB)
  player:setWornItem(state.clothingLocation,state.clothingA)
  assert(not pcall(Slots.verify,state,'toolkit'),'wrong clothing identity escaped verification')
  player:setWornItem(state.clothingLocation,state.clothingB)
 else
  assert(outcome.hotbarItem==state.hotbarReplacement:getID())
  state.hotbarReplacement:setAttachedSlotType(nil)
  assert(not pcall(Slots.verify,state,'toolkit'),'missing hotbar metadata escaped verification')
  state.hotbarReplacement:setAttachedSlotType(state.hotbarType)
  player:setAttachedItem(state.hotbarLocation,state.hotbarInitial or unrelated)
  assert(not pcall(Slots.verify,state,'toolkit'),'wrong attached identity escaped verification')
  player:setAttachedItem(state.hotbarLocation,state.hotbarReplacement)
 end
 assert(Slots.verify(state,'toolkit').slotsVerified)
 Slots.cleanup(state)
 assert(player.attached['Holster Right']==unrelated and unrelated:getAttachedSlot()==unrelatedIndex
  and unrelated:getAttachedSlotType()=='HolsterRight' and unrelated:getAttachedToModel()=='Holster Right',
  'unrelated attachment changed during execution or cleanup')
 if Slots.isBelt(id) then
  assert(outcome.belt and outcome.emptyQueueClick and outcome.favoritePreserved and outcome.policyChecked==false)
  assert(player.attached[state.hotbarLocation]==nil and state.hotbarReplacement:getAttachedSlot()==-1,'belt item survived cleanup')
 elseif id=='hotbar-chain' then
  assert(player.attached[state.hotbarLocation]==nil and state.hotbarInitial:getAttachedSlot()==-1
   and state.hotbarReplacement:getAttachedSlot()==-1,'owned hotbar attachment survived cleanup')
  for _,item in ipairs({state.hotbarInitial,state.hotbarReplacement}) do
   assert(item:getAttachedSlotType()==nil and item:getAttachedToModel()==nil,'owned attachment metadata survived cleanup')
  end
 end
 print(id..': real native callback composition, native final mutation, policy assertions, cleanup passed')
end
runCase('clothing-chain');runCase('hotbar-chain');runCase('belt-knife');runCase('belt-hammer');runCase('belt-knife',true)

-- Unit replay of the new constructor fixture with real native action sources;
-- this does not substitute for observing P4-generated wear in SP/Host runs.
do
 native('shared/TimedActions/ISUnequipAction.lua');native('shared/TimedActions/ISCutHair.lua')
 local Clothing=assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/shared/QueueEquipmentClothing.lua'))()
 string.contains=function(value,part)return value:find(part,1,true)~=nil end
 local visual={hair='Bald',getHairModel=function(self)return self.hair end,getNonAttachedHair=function(self)return self.attached end,
  setHairModel=function(self,value)self.hair=value end,setNonAttachedHair=function(self,value)self.attached=value end}
 local styleName='CrewCut'
 local style={isAttachedHair=function()return false end,getName=function()return styleName end}
 getHairStylesInstance=function()return {FindMaleStyle=function()return style end}end
 local player={worn={}}
 function player:getHumanVisual()return visual end
 function player:isFemale()return false end
 function player:setWornItem(location,item)
  if self.worn[location]==item then return end
  if self.getBodyLocationGroup then
   local group=self:getBodyLocationGroup()
   for other in pairs(self.worn)do if other~=location and group:isExclusive(location,other)then self.worn[other]=nil end end
  end
  self.worn[location]=item
 end
 function player:getWornItem(location)return self.worn[location]end
 function player:removeWornItem(item)for key,value in pairs(self.worn)do if value==item then self.worn[key]=nil end end end
 function player:isTimedActionInstant()return false end
 function player:getPlayerNum()return 0 end
 function player:getPrimaryHandItem()return self.primary end
 function player:getSecondaryHandItem()return self.secondary end
 function player:resetModel()end;function player:resetHairGrowingTime()end
 getPlayerHotbar=function()return {isItemAttached=function()return false end}end
 triggerEvent=function()end;sendEquip=function()end;sendHumanVisual=function()end
 isForceDropHeavyItem=function()return false end
 local state={id='tidy-clothing',player=player,root=container()}
 function state.root:getType()return 'inventory'end
 state.hammer=makeItem('Base.Hammer',state.root);state.screwdriver=makeItem('Base.Screwdriver',state.root)
 player.primary,player.secondary=state.hammer,state.screwdriver
 function state.root:getItemById(id)for item in pairs(self.items)do if item:getID()==id then return item end end end
 Clothing.prepare(state,function(name,kind)state[name]=makeItem(kind,state.root);return state[name]end)
 assert(visual.hair=='CrewCut','disposable authority must deterministically configure a plain style')
 assert(Clothing.verify(state,true).id==state.clothingItem:getID())
 local queue={queue={}}
 ISTimedActionQueue={add=function(action)queue.queue[#queue.queue+1]=action end}
 Clothing.enqueue(state,{run=function(callback)return callback()end})
 assert(#queue.queue==2 and getmetatable(queue.queue[1])==ISUnequipAction and getmetatable(queue.queue[2])==ISCutHair)
 assert(queue.queue[1].complete==ISUnequipAction.complete and queue.queue[2].complete==ISCutHair.complete)
 assert(queue.queue[1]:complete());assert(queue.queue[2]:complete())
 assert(Clothing.verify(state,false).hairUnchanged,'native producer must preserve the requested plain style')
 -- Restored-state verification is exact; another same-type pair cannot satisfy it.
 player:setWornItem(state.clothingLocation,makeItem('Base.Socks_Ankle',state.root))
 assert(not pcall(Clothing.verify,state,true),'same-type replacement must not pass the exact socks slot check')
 local sock='Base.Socks_Ankle#'..state.clothingItem:getID()..'@inventory'
 local prefix='[P4TidyUpMeister][P0][S17] '
 Clothing.observeLine(state,prefix:gsub('P0','P1')..'capture worn=[base:socks='..sock..'] inventoryCount=5')
 assert(not state.clothingP4,'foreign player marker must not bind clothing source')
 Clothing.observeLine(state,prefix..'capture worn=[base:socks='..sock..'] inventoryCount=5')
 Clothing.observeLine(state,prefix..'add[add] type=ISUnequipAction item='..sock)
 Clothing.observeLine(state,prefix..'add[add] type=ISCutHair item=nil')
 Clothing.observeLine(state,prefix..'RESTORE actionTotal=4 trace=[ISReadABook -> ISUnequipAction -> ISCutHair -> ISReadABook] reason=operation:ISReadABook')
 Clothing.observeLine(state,'[P4TidyUpMeister][P0][S-] restore queue complete S18')
 assert(state.clothingP4.restore and not state.clothingP4.completed,'foreign session completion must not settle clothing')
 Clothing.observeLine(state,'[P4TidyUpMeister][P0][S-] restore queue complete S17')
 assert(state.clothingP4.completed and not state.clothingP4.problem,'matching source-owned P4 restore evidence must settle')
 local captured=state.clothingP4;state.clothingP4=nil
 Clothing.observeLine(state,prefix..'capture worn=[base:socks=Base.Socks_Ankle#-1@inventory] inventoryCount=5')
 assert(not state.clothingP4,'different exact socks identity must not bind P4 capture')
 Clothing.observeLine(state,prefix..'capture worn=[base:socks='..sock..'] inventoryCount=5')
 Clothing.observeLine(state,prefix..'RESTORE actionTotal=2 trace=[ISReadABook] reason=operation:ISReadABook')
 assert(state.clothingP4.problem,'restore without real native producer evidence must fail proof')
 state.clothingP4=captured
 -- Removal variant starts empty, uses a real wear constructor, and accepts
 -- only absent-slot capture plus wear/hair source trace before generated cleanup.
 state.id='tidy-clothing-remove';state.clothingP4=nil;player.worn={}
 Clothing.prepare(state,function(key,kind)state[key]=makeItem(kind,state.root);return state[key]end)
 assert(not player:getWornItem(state.clothingLocation),'removal fixture must start with an empty socks slot')
 queue.queue={};Clothing.enqueue(state,{run=function(callback)return callback()end})
 assert(#queue.queue==2 and getmetatable(queue.queue[1])==ISWearClothing and getmetatable(queue.queue[2])==ISCutHair)
 assert(queue.queue[1].complete==ISWearClothing.complete and queue.queue[2].complete==ISCutHair.complete)
 assert(queue.queue[1]:complete());assert(queue.queue[2]:complete())
 assert(Clothing.verify(state,true).hairUnchanged)
 sock='Base.Socks_Ankle#'..state.clothingItem:getID()..'@inventory'
 Clothing.observeLine(state,prefix..'capture worn=[base:socks='..sock..'] inventoryCount=5')
 assert(not state.clothingP4,'occupied original slot must not prove empty-slot restoration')
 Clothing.observeLine(state,prefix..'capture worn=[] inventoryCount=5')
 Clothing.observeLine(state,prefix..'add[add] type=ISWearClothing item='..sock)
 Clothing.observeLine(state,prefix..'add[add] type=ISCutHair item=nil')
 Clothing.observeLine(state,prefix..'RESTORE actionTotal=4 trace=[ISReadABook -> ISWearClothing -> ISCutHair -> ISReadABook] reason=operation:ISReadABook')
 Clothing.observeLine(state,'[P4TidyUpMeister][P0][S-] restore queue complete S17')
 assert(state.clothingP4.completed and not state.clothingP4.problem)
 -- The public observer must bind only the generated native cleanup, and
 -- generic acknowledgements must reach completed before final evidence passes.
 local generated=ISUnequipAction:new(player,state.clothingItem,50)
 state.clothingProducerStarted=true
 local ackState='pending';local receipt={token='native'}
 local toolkit={Settings={actionQueue=function()return true end},
  ActionQueueDefinitions={inspect=function(action)assert(action==generated);return {},'compat.tidy-equipment'end},
  ActionQueueAcknowledgements={capture=function(action)assert(action==generated);return receipt end,
   observe=function(action,value)assert(action==generated and value==receipt);return ackState end}}
 isClient=function()return true end
 Clothing.observe(state,{queue={queue.queue[1],generated}},toolkit,true)
 assert(state.clothingRestoreAction==generated and state.clothingRestoreReceipt==receipt)
 assert(not Clothing.settled(state,toolkit,true),'pending cleanup cannot settle while worn')
 local duplicate=ISUnequipAction:new(player,state.clothingItem,50)
 assert(not pcall(Clothing.observe,state,{queue={duplicate}},toolkit,true),'duplicate generated cleanup must fail')
 -- Native completion is replayed only to validate exact final-state assertions;
 -- real generation/authority is the responsibility of the native SP/Host case.
 assert(ISUnequipAction:new(player,state.clothingItem,50):complete())
 assert(not Clothing.verify(state,false).worn)
 assert(not Clothing.settled(state,toolkit,true),'unworn alone cannot replace authoritative completion')
 assert(not pcall(Clothing.evidence,state,toolkit,true,{perform=1,complete=0,flush=1,legacy=0}))
 ackState='completed'
 assert(Clothing.settled(state,toolkit,true))
 assert(Clothing.evidence(state,toolkit,true,{perform=1,complete=0,flush=1,legacy=0}).nativeGenerated==1)
 isClient=function()return false end
 player:setWornItem(state.clothingLocation,makeItem('Base.Socks_Ankle',state.root))
 assert(not pcall(Clothing.verify,state,false),'foreign socks in the slot must not satisfy absence')
 player:setWornItem(state.clothingLocation,nil)
 -- Temporary cases create overlap through native Equip then ordinary Wear;
 -- desired cases seed the baseline outside tested native actions, then native
 -- Unequip removes both worn and held state. P4 generation and transport are
 -- observed by separate SP/Host gates; this replay checks the observer contract.
 native('shared/TimedActions/ISEquipWeaponAction.lua')
 getText=function(value)return value end
 function player:getInventory()return state.root end
 function player:getClothingItem_Back()end
 function player:getCurrentSquare()return {}end
 function player:setPrimaryHandItem(value)self.primary=value end
 function player:setSecondaryHandItem(value)self.secondary=value end
 function player:isEquippedClothing(value)return self.worn[value:getBodyLocation()]==value end
 function player:getWornItems()return {contains=function(_,value)return player:isEquippedClothing(value)end}end
 getPlayerInventory=function()return {refreshBackpacks=function()end}end
 P4RestoreAction={Type='P4RestoreAction'};P4RestoreAction.__index=P4RestoreAction
 -- Headwear setup must preserve existing slots and prove spare native capacity.
 -- Java callbacks/transport remain doubles; SP/Host proves actual P4 generation.
 local group={multi=false}
 function group:getLocation(location)return location end
 function group:isMultiItem()return self.multi end
 function group:isExclusive(a,b)
  return a~=b and (a=='base:leftwrist'and b=='base:forearmleft'or a=='base:rightwrist'and b=='base:forearmright'
   or a==ItemBodyLocation.FULL_HAT and (b==ItemBodyLocation.HAT or b=='base:mask')
   or b==ItemBodyLocation.FULL_HAT and (a==ItemBodyLocation.HAT or a=='base:mask'))
 end
 function player:getBodyLocationGroup()return group end
 function player:getWornItems()
  local entries={}
  for location,item in pairs(self.worn)do
   local l,v=location,item;entries[#entries+1]={getLocation=function()return l end,getItem=function()return v end}
  end
  local values=list(entries);values.getBodyLocationGroup=function()return group end
  values.contains=function(_,item)return player.worn[item:getBodyLocation()]==item end;return values
 end
 state.root.getCapacityWeight=function()return 2 end
 local capacity=50
 state.root.getEffectiveCapacity=function()return capacity end
 state.root.isItemAllowed=function()return true end
 local function seedHead(key,kind)
  local item=makeItem(kind,state.root);state[key]=item
  item.getUnequippedWeight=function()return 0.5 end
  item.getEquippedWeight=function()return 0.15 end
  item.canBeActivated=function()return false end;item.isForceDropHeavyItem=function()return false end
  return item
 end
 function player:getInventory()return state.root end
 getGameTime=function()return {getHour=function()return 9 end}end
 getCell=function()return {getProcessItems=function()return {contains=function(_,item)
  return state.clothingWatch and state.clothingWatch.alarmSet and player:getWornItem(item:getBodyLocation())==item
 end}end,getProcessItemsRemove=function()return {contains=function()return false end}end}end
 for _,caseID in ipairs({'tidy-clothing-overlap','tidy-clothing-overlap-primary','tidy-clothing-overlap-both',
  'tidy-clothing-held-primary','tidy-clothing-held-secondary','tidy-clothing-held-both',
  'tidy-watch-overlap-primary','tidy-watch-overlap-secondary','tidy-watch-overlap-both',
  'tidy-watch-held-primary','tidy-watch-held-secondary','tidy-watch-held-both'})do
  state.id=caseID;state.clothingP4=nil;state.clothingRestoreAction=nil;state.clothingRestoreReceipt=nil
  state.clothingOverlap=nil;state.clothingCaptureHands=nil;state.clothingProducerStarted=nil;state.clothingCleanup=nil;state.clothingReceipts=nil;state.clothingWatchReady=nil
  player.worn={};player.primary,player.secondary=state.hammer,state.screwdriver
  -- The real fixture seeds Base.Torch inactive. These inventory doubles model
  -- activation observations; native Equip/Wear/Unequip effects remain untouched.
  state.hammer.kind='Base.Torch'
  Clothing.prepare(state,seedHead)
  function state.root:getItemWithID(id)return self:getItemById(id)end
  for _,item in ipairs({state.hammer,state.screwdriver,state.clothingItem})do
   item.isTwoHandWeapon=function()return false end;item.isForceDropHeavyItem=function()return false end;item.isRequiresEquippedBothHands=function()return false end
   item.getCurrentUsesFloat=function()return 1 end;item.canBeActivated=function()return false end
   item.isActivated=function(self)return self.activated==true end;item.getName=item.getFullType
  end
  queue.queue={};queue.current=nil;Clothing.enqueue(state,{run=function(callback)return callback()end})
  local hand=Clothing.overlapHand(state);local primary,secondary=Clothing.expectedHands(state,false)
  local desired=Clothing.desired(state)
  local originalPrimary,originalSecondary=Clothing.expectedHands(state,true)
  if desired then
   assert(player.primary==originalPrimary and player.secondary==originalSecondary
    and player:getWornItem(state.clothingLocation)==state.clothingItem,'desired initial socks must be both held and worn')
   assert(#queue.queue==2 and getmetatable(queue.queue[1])==ISUnequipAction and getmetatable(queue.queue[2])==ISCutHair)
   assert(queue.queue[1]:complete());assert(queue.queue[2]:complete())
   assert(player.primary==primary and player.secondary==secondary and not player:getWornItem(state.clothingLocation))
  else
  assert(#queue.queue==3 and getmetatable(queue.queue[1])==ISEquipWeaponAction
   and queue.queue[1].primary==(hand~='secondary')and queue.queue[1].twoHands==(hand=='both')
   and getmetatable(queue.queue[2])==ISWearClothing and getmetatable(queue.queue[3])==ISCutHair)
  assert(not player:getWornItem(state.clothingLocation)and player.primary==state.hammer and player.secondary==state.screwdriver)
  assert(queue.queue[1]:complete());assert(player.primary==primary and player.secondary==secondary and not player:getWornItem(state.clothingLocation))
  assert(queue.queue[2]:complete());assert(queue.queue[3]:complete())
  assert(player.primary==primary and player.secondary==secondary and player:getWornItem(state.clothingLocation)==state.clothingItem)
  end
  local function id(item)return item and item:getID()or false end
  local native=Clothing.verify(state,not desired)
  if Clothing.wristwatch(state)then assert(native.watchProcessing.active==not desired and not native.watchProcessing.pendingRemoval)end
  assert(native.primary==id(primary)and native.secondary==id(secondary)
   and native.originalPrimary==id(originalPrimary)and native.originalSecondary==id(originalSecondary))
  assert(not Clothing.settled(state,{},false),'unobserved overlap must not settle')
  local sockID=state.clothingItem:getID()
  local acks,captures={},{};local ack='completed'
  toolkit={Settings={actionQueue=function()return true end},
   ActionQueueDefinitions={inspect=function()return {},'compat.tidy-equipment'end},
   ActionQueueAcknowledgements={capture=function(action)if queue.current==action then captures[action]=(captures[action]or 0)+1;acks[action]=acks[action]or {};return acks[action]end end,
    observe=function(action,receipt)assert(acks[action]==receipt);return ack end}}
  -- Empty pre-start current and nil producer are a quiet no-op.
  local nextProducer=state.clothingProducer;state.clothingProducer=nil;queue.current=nil
  assert(pcall(Clothing.observe,state,queue,toolkit,true));state.clothingProducer=nextProducer
  state.clothingProducer.isStarted=function()return true end;queue.current=state.clothingProducer
  -- A correct worn ID alone cannot prove either held slot.
  player.primary=primary==state.clothingItem and state.hammer or state.clothingItem;assert(not pcall(Clothing.observe,state,queue,toolkit,true));player.primary=primary
  player.secondary=secondary==state.clothingItem and state.screwdriver or state.clothingItem;assert(not pcall(Clothing.observe,state,queue,toolkit,true));player.secondary=secondary
  Clothing.observe(state,queue,toolkit,true)
  assert(state.clothingOverlap.primary==id(primary)and state.clothingOverlap.secondary==id(secondary)and state.clothingOverlap.worn==(not desired and sockID or false))
  assert(Clothing.settled(state,toolkit,false),'observed native/no-P4 overlap should settle')
  for _,action in ipairs(queue.queue)do queue.current=action;isClient=function()return true end;Clothing.observe(state,queue,toolkit,true)end
  isClient=function()return false end
  local location=Clothing.spec(state).location
  sock=Clothing.spec(state).fullType..'#'..sockID..'@inventory'
  if desired then
   Clothing.observeLine(state,prefix..'capture primary='..state.hammer:getFullType()..'#'..state.hammer:getID()..'@inventory secondary='..state.screwdriver:getFullType()..'#'..state.screwdriver:getID()..'@inventory')
   Clothing.observeLine(state,prefix..'capture worn=['..location..'='..sock..'] inventoryCount=5')
   assert(state.clothingP4 and not state.clothingP4.hands,'desired capture must reject merely worn socks without preferred held IDs')
   state.clothingP4=nil
   Clothing.observeLine(state,prefix..'capture worn=['..location..'='..Clothing.spec(state).fullType..'#-1@inventory] inventoryCount=5')
   assert(not state.clothingP4,'desired capture must reject another exact worn ID')
  end
  Clothing.observeLine(state,prefix..'capture primary='..originalPrimary:getFullType()..'#'..originalPrimary:getID()..'@inventory secondary='..originalSecondary:getFullType()..'#'..originalSecondary:getID()..'@inventory')
  Clothing.observeLine(state,prefix..'capture worn=['..(desired and location..'='..sock or '')..'] inventoryCount=5')
  if not desired then Clothing.observeLine(state,prefix..'add[add] type=ISEquipWeaponAction item='..sock)end
  Clothing.observeLine(state,prefix..'add[add] type='..(desired and 'ISUnequipAction'or 'ISWearClothing')..' item='..sock)
  Clothing.observeLine(state,prefix..'add[add] type=ISCutHair item=nil')
  Clothing.observeLine(state,prefix..'RESTORE actionTotal=5 trace=[ISReadABook -> '..(desired and 'ISUnequipAction'or 'ISEquipWeaponAction -> ISWearClothing')..' -> ISCutHair -> ISReadABook] reason=operation:ISReadABook')
  assert(state.clothingP4.restore and not state.clothingP4.problem)
  -- P4 generation/transport is verified by SP/Host gates. This replay verifies
  -- the shared exact cleanup contract against actual native constructors.
  local cleanup={}
  for _,spec in ipairs(Clothing.cleanupSpec(state))do
   local action
   if spec.class==ISEquipWeaponAction then action=ISEquipWeaponAction:new(player,spec.item,50,spec.primary,spec.twoHands)
   elseif spec.class==P4RestoreAction then action=setmetatable({item=spec.item,activated=spec.activated},P4RestoreAction)
   else action=spec.class:new(player,spec.item,50)end
   cleanup[#cleanup+1]=action
  end
  local function rejected(actions,message)
   queue.queue=actions;queue.current=nil
   assert(not pcall(Clothing.observe,state,queue,toolkit,true),message)
   assert(not state.clothingCleanup,'rejected cleanup must not bind')
  end
  local absent={};for i=2,#cleanup do absent[#absent+1]=cleanup[i]end
  rejected(absent,'missing P4 cleanup must fail')
  local reordered={};for i,action in ipairs(cleanup)do reordered[i]=action end
  reordered[1],reordered[2]=reordered[2],reordered[1];rejected(reordered,'reordered P4 cleanup must fail')
  for _,action in ipairs(cleanup)do
   if getmetatable(action)==ISEquipWeaponAction then
    action.primary=not action.primary;rejected(cleanup,'wrong cleanup hand must fail');action.primary=not action.primary
    local saved=action.twoHands;action.twoHands=not saved;rejected(cleanup,'wrong cleanup twoHands must fail');action.twoHands=saved
   elseif getmetatable(action)==P4RestoreAction then
    action.activated=true;rejected(cleanup,'changed baseline activation must fail');action.activated=false
   end
  end
  queue.queue=cleanup;Clothing.observe(state,queue,toolkit,true)
  assert(#state.clothingCleanup==(not desired and hand=='both'and 5 or 3))
  for _,action in ipairs(cleanup)do
   if getmetatable(action)~=P4RestoreAction then assert(action:complete())end
  end
  assert(player.primary==originalPrimary and player.secondary==originalSecondary
   and player:getWornItem(state.clothingLocation)==(desired and state.clothingItem or nil))
  assert(Clothing.verify(state,desired).originalPrimary==id(originalPrimary))
  Clothing.observeLine(state,'[P4TidyUpMeister][P0][S-] restore queue complete S17')
  isClient=function()return true end
  for _,action in ipairs(queue.queue)do queue.current=action;Clothing.observe(state,queue,toolkit,true)end
  queue.current=nil
  local function quietReady(expected)
   local ok,value=pcall(Clothing.settled,state,toolkit,true);assert(ok and value==expected,'clothing overlap readiness must wait quietly')
  end
  for _,value in ipairs({'pending','started','canceled'})do
   ack=value;quietReady(false)
   assert(not pcall(Clothing.evidence,state,toolkit,true,{}),'incomplete Host receipt must fail evidence')
  end
  ack='completed';quietReady(true)
  for _,action in ipairs((function()local actions=Clothing.producerActions(state);for _,action in ipairs(cleanup)do actions[#actions+1]=action end;return actions end)())do
   local saved=state.clothingReceipts[action];state.clothingReceipts[action]=nil;quietReady(false)
   assert(not pcall(Clothing.evidence,state,toolkit,true,{}),'missing any Host receipt must fail evidence')
   state.clothingReceipts[action]=saved
  end
  player.primary=originalPrimary==state.clothingItem and state.hammer or state.clothingItem;quietReady(false);assert(not pcall(Clothing.verify,state,desired));player.primary=originalPrimary
  player.secondary=originalSecondary==state.clothingItem and state.screwdriver or state.clothingItem;quietReady(false);assert(not pcall(Clothing.verify,state,desired));player.secondary=originalSecondary
  state.hammer.activated=true;quietReady(false);assert(not pcall(Clothing.verify,state,desired));state.hammer.activated=false
  local count=not desired and hand=='both'and 4 or 2
  local hands={perform=count,complete=0,flush=count,legacy=0,equip=count/2,activation=count/2,unequip=0}
  local effect=Clothing.evidence(state,toolkit,true,{perform=1,complete=0,flush=1,legacy=0},hands)
  assert(#effect.overlap.cleanup==count+1 and #effect.overlap.acknowledgements==count+(desired and 3 or 4) and effect.overlap.sharedHands==hands)
  if Clothing.wristwatch(state)then
   assert(effect.watchBaseline.alarmSet and effect.watchSetup.emptyExclusiveSlots and not effect.watchAcknowledgements,
    'held watches must preserve alarm setup and reuse the single overlap receipt list')
   for key,bad in pairs({hour=22,minute=30,alarm=false,ringing=true})do
    local item=state.clothingItem;local before=item[key];item[key]=bad
    quietReady(false);assert(not pcall(Clothing.evidence,state,toolkit,true,{},hands),'watch overlap accepted changed '..key)
    item[key]=before
   end
  end
  for action in pairs(state.clothingReceipts)do assert(captures[action]==1,'native action receipt captured twice')end
  for i,row in ipairs(effect.overlap.cleanup)do
   if row.kind=='ISEquipWeaponAction'then assert(type(row.primary)=='boolean'and row.twoHands==(desired and hand=='both'))
   elseif row.kind=='P4RestoreAction'then assert(row.activated==false)end
  end
  isClient=function()return false end
  if Clothing.wristwatch(state)then assert(Clothing.verify(state,desired).watchProcessing.active==desired)end
  print(caseID..': native clothing effects, exact intermediate/hands/cleanup flags, ordering and all Host receipt gates passed')
 end
 state.id='tidy-clothing'
 for _,name in ipairs({'Bald','Mohawk','Spike','GreasedBack','Buffont'})do
  visual.hair=name;visual.attached='PreviousAttachedStyle'
  Clothing.prepare(state,function(key,kind)state[key]=makeItem(kind,state.root);return state[key]end)
  assert(visual.hair=='CrewCut'and not visual.attached,'random unsafe starting cosmetics must not make fixture flaky')
 end
 for _,case in ipairs({'tidy-headwear-hat-remove','tidy-headwear-full-hat-remove','tidy-headwear-hat-restore','tidy-headwear-full-hat-restore'})do
  local remove=case:match('%-remove$')~=nil
  state.id=case;state.clothingP4=nil;state.clothingCaptureHands=nil;state.clothingRestoreAction=nil;state.clothingRestoreReceipt=nil
  state.clothingHeadwearReady=nil;state.clothingProducerStarted=nil;state.clothingEmptyHeadwear=nil;player.worn={}
  player.primary,player.secondary=state.hammer,state.screwdriver;visual.hair='CrewCut';visual.attached=nil
  local location=case:find('full%-hat')and ItemBodyLocation.FULL_HAT or ItemBodyLocation.HAT
  local foreign=makeItem('Base.Other',state.root);player.worn[location]=foreign
  assert(not pcall(Clothing.prepare,state,seedHead),'occupied head slot must fail fixture setup')
  assert(player.worn[location]==foreign,'fixture cleared baseline headwear');player.worn={}
  local exclusive=location==ItemBodyLocation.HAT and ItemBodyLocation.FULL_HAT or 'base:mask'
  player.worn[exclusive]=foreign
  assert(not pcall(Clothing.prepare,state,seedHead),'exclusive baseline headwear must fail setup')
  assert(player.worn[exclusive]==foreign,'fixture cleared baseline exclusive item');player.worn={}
  group.multi=true;assert(not pcall(Clothing.prepare,state,seedHead),'multi-item head slot must fail setup');group.multi=false
  capacity=3;assert(not pcall(Clothing.prepare,state,seedHead),'insufficient capacity must fail setup');capacity=50
  Clothing.prepare(state,seedHead);assert(player.worn[location]==(not remove and state.clothingItem or nil)and state.clothingEmptyHeadwear)
  assert(state.clothingRestoreType==(remove and 'ISUnequipAction'or 'ISWearClothing'))
  local prepared=state.clothingItem
  local ids={case=case,items={clothingItem=prepared:getID()},clothingHair='CrewCut'}
  assert(Clothing.available(player,ids),'exact authority setup must be ready')
  player.worn[location]=remove and prepared or nil
  assert(not Clothing.available(player,ids),'wrong native setup must wait for clothing replication')
  player.worn[location]=not remove and prepared or nil
  state.ids=ids;isClient=function()return true end
  Clothing.prepare(state,function(key)state[key]=prepared end)
  assert(player.worn[location]==(not remove and prepared or nil),'client must adopt the authority worn snapshot')
  state.ids=nil;isClient=function()return false end
  queue.queue={};Clothing.enqueue(state,{run=function(callback)return callback()end})
  local first=remove and ISWearClothing or ISUnequipAction
  assert(#queue.queue==2 and getmetatable(queue.queue[1])==first and queue.queue[1].maxTime==50)
  assert(queue.queue[1]:complete());assert(queue.queue[2]:complete())
  assert(player.worn[location]==(remove and state.clothingItem or nil)and visual.hair=='CrewCut'and not visual.attached)
  state.clothingProducer.isStarted=function()return true end;queue.current=state.clothingProducer
  player.worn[location]=not remove and state.clothingItem or nil
  assert(not pcall(Clothing.observe,state,queue,toolkit,true),'headwear must prove the expected intermediate worn state')
  player.worn[location]=remove and state.clothingItem or nil
  Clothing.observe(state,queue,toolkit,true);assert(state.clothingHeadwearReady)
  local spec=Clothing.spec(state);local label=spec.fullType..'#'..state.clothingItem:getID()..'@inventory'
  Clothing.observeLine(state,prefix..'capture worn=['..(remove and ''or tostring(location)..'='..label)..'] inventoryCount=5')
  Clothing.observeLine(state,prefix..'add[add] type='..first.Type..' item='..label)
  Clothing.observeLine(state,prefix..'add[add] type=ISCutHair item=nil')
  Clothing.observeLine(state,prefix..'RESTORE actionTotal=4 trace=[ISReadABook -> '..first.Type..' -> ISCutHair -> ISReadABook] reason=operation:ISReadABook')
  local cleanup=(remove and ISUnequipAction or ISWearClothing):new(player,state.clothingItem,50)
  local nativeReceipt={};local receiptState='started'
  toolkit={Settings={actionQueue=function()return true end},ActionQueueDefinitions={inspect=function(action)assert(action==cleanup);return {},'compat.tidy-equipment'end},
   ActionQueueAcknowledgements={capture=function(action)if queue.current==action then return nativeReceipt end end,
    observe=function(action,receipt)assert(action==cleanup and receipt==nativeReceipt);return receiptState end}}
  queue.queue={cleanup};queue.current=cleanup;isClient=function()return true end
  Clothing.observe(state,queue,toolkit,true);assert(state.clothingRestoreReceipt==nativeReceipt)
  assert(cleanup:complete());assert(Clothing.verify(state,not remove).fullType==spec.fullType)
  Clothing.observeLine(state,'[P4TidyUpMeister][P0][S-] restore queue complete S17')
  assert(not Clothing.settled(state,toolkit,true),'headwear needs completed native authority')
  receiptState='completed';assert(Clothing.settled(state,toolkit,true))
  local outcome=Clothing.evidence(state,toolkit,true,{perform=1,complete=0,flush=1,legacy=0})
  assert(outcome.headwearSetup.emptyExclusiveSlots and outcome.headwearSetup.capacityBeforeRemoval and outcome.bodyLocation==spec.location)
  isClient=function()return false end
  print(case..': native clothing/CutHair/cleanup, empty exclusive slots, spare capacity, unchanged hair and Host receipt passed')
  if not remove then
   -- Native SyncClothingPacket.process first retains WornItems.getItemById;
   -- only an absent worn ID reaches inventory.getItemWithID/CreateItem. An
   -- early snapshot therefore pins a worn-only proxy after AddItems arrives.
   player.worn={};isServer=function()return true end
   local sync={}
   sendClothing=function(actor,slot,item)
    assert(actor==player and slot==location and item==state.clothingItem)
    sync[#sync+1]=item
   end
   Clothing.prepare(state,seedHead)
   local rootItem=state.clothingItem
   assert(state.clothingSetupPending==true and next(player.worn)==nil and #sync==0,
    'Host prepare must never wear before client exact-root acknowledgement')
   local pendingIds={case=case,items={clothingItem=rootItem:getID()},clothingHair='CrewCut',clothingSetupPending=true}
   local client={worn={}}
   function client:getHumanVisual()return visual end
   function client:getInventory()return state.root end
   function client:getWornItem(slot)return self.worn[slot]end
   local function nativeSync(rootPresent)
    if client.worn[location] and client.worn[location]:getID()==rootItem:getID()then return end
    client.worn[location]=rootPresent and rootItem or {
     getID=function()return rootItem:getID()end,getFullType=function()return rootItem:getFullType()end,
     getBodyLocation=function()return location end,getContainer=function()return nil end}
   end
   nativeSync(false);nativeSync(true)
   assert(client.worn[location]~=rootItem and not Clothing.available(client,pendingIds),
    'a native same-ID worn proxy must never pass exact root readiness')
   client.worn={}
   state.root.items[rootItem]=nil
   assert(not Clothing.available(client,pendingIds),'root acknowledgement must wait for AddItems')
   state.root.items[rootItem]=true
   assert(Clothing.available(client,pendingIds),'root acknowledgement requires exact root item and empty head')
   assert(not pcall(Clothing.configure,state,rootItem:getID()+1),'wrong setup ID accepted')
   local kind=rootItem.kind;rootItem.kind='Base.Other'
   assert(not pcall(Clothing.configure,state,rootItem:getID()),'same-ID wrong setup type accepted');rootItem.kind=kind
   local caseID=state.id;state.id='tidy-headwear-hat-remove'
   assert(not pcall(Clothing.configure,state,rootItem:getID()),'removal case setup accepted');state.id=caseID
   isClient=function()return true end
   assert(not pcall(Clothing.configure,state,rootItem:getID()),'client cannot own setup mutation')
   isClient=function()return false end
   assert(next(player.worn)==nil and #sync==0 and state.clothingSetupPending,
    'rejected setup must preserve exact pending authority state')
   Clothing.configure(state,rootItem:getID())
   assert(player.worn[location]==rootItem and not state.clothingSetupPending and #sync==1)
   assert(not pcall(Clothing.configure,state,rootItem:getID())and #sync==1,'duplicate setup accepted')
   pendingIds.clothingSetupPending=nil
   assert(not Clothing.available(client,pendingIds),'configuration acknowledgement alone cannot replace worn replication')
   nativeSync(true)
   assert(Clothing.available(client,pendingIds)and client.worn[location]==rootItem,
    'post-ack native snapshot must bind the already-present exact root object')
   player.worn={};isServer=function()return false end
   print(case..': two-phase Host setup rejects early native proxy, absent root, wrong ID/type/case and duplicates')
  end
 end
 -- Same-slot and exclusive replacements share the same native producer,
 -- observer, cleanup specification and authoritative receipt gates.
 for _,case in ipairs({'tidy-clothing-replace','tidy-headwear-hat-exclusive','tidy-headwear-full-hat-exclusive'})do
  state.id=case;state.ids=nil;state.clothingP4=nil;state.clothingRestoreAction=nil;state.clothingRestoreReceipt=nil
  state.clothingCleanup=nil;state.clothingReceipts=nil;state.clothingProducerStarted=nil;state.clothingDisplacementReady=nil
  state.clothingSetupPending=nil;player.worn={};player.primary,player.secondary=state.hammer,state.screwdriver
  visual.hair='CrewCut';visual.attached=nil;isClient,isServer=function()return false end,function()return false end
  Clothing.prepare(state,seedHead)
  local spec=Clothing.spec(state);local baseline,temp=state.clothingItem,state.clothingTemporary
  local initial=Clothing.verify(state,true)
  assert(initial.worn and initial.temporary.id==temp:getID()and not initial.temporary.worn)
  queue.queue={};queue.current=nil;Clothing.enqueue(state,{run=function(callback)return callback()end})
  assert(#queue.queue==2 and queue.queue[1].item==temp and getmetatable(queue.queue[1])==ISWearClothing)
  assert(queue.queue[1].maxTime==50 and queue.queue[2].maxTime==100)
  assert(queue.queue[1]:complete()and queue.queue[2]:complete())
  local receipts={};local ack='completed';local inspected={};local omitTemporary=false
  toolkit={Settings={actionQueue=function()return true end},ActionQueueDefinitions={inspect=function(action)
   inspected[action]=true
   return {items={[baseline:getID()]=true,[temp:getID()]=not omitTemporary},
    itemTypes={[baseline:getFullType()]=true,[temp:getFullType()]=true},hands=player},'compat.tidy-equipment'
  end},
   ActionQueueAcknowledgements={capture=function(action)if queue.current==action then receipts[action]=receipts[action]or {};return receipts[action]end end,
    observe=function(action,receipt)assert(receipts[action]==receipt);return ack end}}
  state.clothingProducer.isStarted=function()return true end
  for _,action in ipairs(queue.queue)do queue.current=action;isClient=function()return true end;Clothing.observe(state,queue,toolkit,true)end
  local intermediate=Clothing.verify(state,false)
  assert(not intermediate.worn and intermediate.temporary.worn and intermediate.temporary.container=='root'
   and baseline:getContainer()==state.root and temp:getContainer()==state.root and state.clothingDisplacementReady)
  local label=baseline:getFullType()..'#'..baseline:getID()..'@inventory'
  local tempLabel=temp:getFullType()..'#'..temp:getID()..'@inventory'
  Clothing.observeLine(state,prefix..'capture worn=['..spec.location..'='..label..'] inventoryCount=6')
  Clothing.observeLine(state,prefix..'add[add] type=ISWearClothing item='..tempLabel)
  Clothing.observeLine(state,prefix..'add[add] type=ISCutHair item=nil')
  Clothing.observeLine(state,prefix..'RESTORE actionTotal=4 trace=[ISReadABook -> ISWearClothing -> ISCutHair -> ISReadABook] reason=operation:ISReadABook')
  assert(state.clothingP4 and state.clothingP4.restore and not state.clothingP4.problem)
  local cleanup={}
  for _,row in ipairs(Clothing.cleanupSpec(state))do cleanup[#cleanup+1]=row.class:new(player,row.item,50)end
  assert(#cleanup==(spec.location==spec.temporaryLocation and 1 or 2))
  if #cleanup==2 then
   local reversed={cleanup[2],cleanup[1]}
   assert(not pcall(Clothing.verifyCleanup,state,reversed),'exclusive cleanup prefix order must remain exact')
  end
  queue.queue=cleanup;queue.current=nil;omitTemporary=true
  assert(not pcall(Clothing.observe,state,queue,toolkit,true),'replacement Wear without temporary resource ownership accepted')
  omitTemporary=false;Clothing.observe(state,queue,toolkit,true)
  for _,action in ipairs(cleanup)do
   assert(inspected[action],'every generated displacement cleanup needs shared source definition')
   queue.current=action;Clothing.observe(state,queue,toolkit,true);assert(action:complete())
  end
  Clothing.observeLine(state,'[P4TidyUpMeister][P0][S-] restore queue complete S17')
  assert(Clothing.settled(state,toolkit,true))
  local outcome=Clothing.evidence(state,toolkit,true,{perform=#cleanup,complete=0,flush=#cleanup,legacy=0})
  assert(outcome.worn and not outcome.temporary.worn and outcome.temporary.id==temp:getID()
   and #outcome.displacement.cleanup==#cleanup and #outcome.displacement.acknowledgements==#cleanup+2)
  for _,action in ipairs((function()local actions=Clothing.producerActions(state);for _,value in ipairs(cleanup)do actions[#actions+1]=value end;return actions end)())do
   local receipt=state.clothingReceipts[action];state.clothingReceipts[action]=nil
   assert(not Clothing.settled(state,toolkit,true)and not pcall(Clothing.evidence,state,toolkit,true,{}),'missing displacement receipt accepted')
   state.clothingReceipts[action]=receipt
  end
  local kind=temp.kind;temp.kind='Base.Other';assert(not Clothing.settled(state,toolkit,true)and not pcall(Clothing.verify,state,true));temp.kind=kind
  player.worn[temp:getBodyLocation()]=temp
  assert(not Clothing.settled(state,toolkit,true),'temporary worn replacement must not satisfy restored baseline')
  player.worn={};player:setWornItem(state.clothingLocation,baseline)
  ack='started';assert(not Clothing.settled(state,toolkit,true));ack='completed'
  isClient=function()return false end
  print(case..': native temporary Wear/CutHair, exact same/exclusive cleanup, root identities and all Host receipts passed')
 end
 -- Mohawk cases replay the real native constructors and CutHair consumption.
 -- Java storage/transport remain doubles; full-pack SP/Host is the live gate.
 do
  local previousSet,previousRemove=player.setWornItem,player.removeWornItem
  local previousItems,previousSend=state.root.getItems,sendClothing
  sendClothing=function()end
  local growthResets=0
  function player:resetHairGrowingTime()growthResets=growthResets+1 end
  function player:setWornItem(location,item)
   if self.worn[location]==item then return end
   previousSet(self,location,item)
   if (location==ItemBodyLocation.HAT or location==ItemBodyLocation.FULL_HAT)and visual.hair:find('Mohawk',1,true)then visual.hair='MohawkFlat'end
  end
  function player:removeWornItem(item)
   for location,value in pairs(self.worn)do if value==item then self:setWornItem(location,nil);return end end
  end
  local color={getRedFloat=function()return 0.2 end,getGreenFloat=function()return 0.3 end,getBlueFloat=function()return 0.4 end}
  function visual:getHairColor()return color end
  function state.root:getItems()local values={};for item in pairs(self.items)do values[#values+1]=item end;return list(values)end
  function state.root:getItemFromType(kind)
   if kind=='Hairgel'then return state.clothingGel end
  end
  for _,case in ipairs({'tidy-headwear-mohawk-hat-restore','tidy-headwear-mohawk-hat-remove','tidy-headwear-mohawk-full-hat-restore','tidy-headwear-mohawk-full-hat-remove'})do
   isClient,isServer=function()return false end,function()return false end
   state.id=case;state.ids=nil;state.clothingP4=nil;state.clothingRestoreAction=nil;state.clothingRestoreReceipt=nil
   state.clothingReceipts=nil;state.clothingFirstObserved=nil;state.clothingAppearanceCheckpoint=nil
   state.clothingProducerStarted=nil;state.clothingSetupPending=nil;player.worn={};visual.hair='CrewCut';visual.attached=nil
   player.primary,player.secondary=state.hammer,state.screwdriver;styleName='MohawkFan'
   local uses=20;local consumed=0
   Clothing.prepare(state,function(name,kind)
    local item=seedHead(name,kind)
    if name=='clothingGel'then
     function item:getMaxUses()return 20 end;function item:getCurrentUses()return uses end
     function item:getUseDelta()return 0.05 end;function item:setCurrentUses(value)uses=value end
     function item:UseAndSync()uses=uses-1;consumed=consumed+1 end
    end
    return item
   end)
   assert(state.clothingAppearanceBaseline.hairModel=='MohawkFan'and state.clothingAppearanceBaseline.gel.uses==20)
   if not Clothing.removes(state)then
    player.worn[state.clothingLocation]=nil;state.clothingSetupPending=true;state.clothingSetupPrevious=nil
    isServer=function()return true end
    Clothing.configure(state,state.clothingItem:getID())
    assert(visual.hair=='MohawkFan'and player.worn[state.clothingLocation]==state.clothingItem and uses==20,'once-only Host setup must restore initial upright hair after wearing')
    assert(not pcall(Clothing.configure,state,state.clothingItem:getID()),'duplicate Mohawk setup accepted')
    isServer=function()return false end
   end
   local safe,ready=pcall(Clothing.appearanceReady,state,'checkpoint');assert(safe and not ready,'readiness must wait for native producer without asserting')
   queue.queue={};queue.current=nil;Clothing.enqueue(state,{run=function(callback)return callback()end})
   local first,producer=queue.queue[1],queue.queue[2]
   assert(first.maxTime==50 and producer.maxTime==100 and producer.hairStyle=='MohawkFan'and producer.item==nil)
   assert(first:complete()and visual.hair=='MohawkFlat'and uses==20)
   local firstSnapshot=Clothing.verify(state,Clothing.removes(state),true,'first')
   assert(firstSnapshot.appearance.hairModel=='MohawkFlat'and firstSnapshot.appearance.gel.uses==20
    and firstSnapshot.appearance.gel.id==state.clothingGel:getID()and firstSnapshot.appearance.gel.container=='root'
    and firstSnapshot.hairUnchanged==false,'SP first-phase appearance/gel flags must remain unchanged')
   isServer=function()return true end;visual.hair=Clothing.removes(state)and 'MohawkFlat'or 'MohawkFan'
   assert(Clothing.appearanceReady(state,'first'),'Host server first Wear/Unequip phase differs')
   visual.hair=Clothing.removes(state)and 'MohawkFan'or 'MohawkFlat'
   assert(not Clothing.appearanceReady(state,'first'),'Host server first-phase counterpart accepted')
   isServer=function()return false end;visual.hair='MohawkFlat'
   local receipts={};local ack='completed'
   toolkit={Settings={actionQueue=function()return true end},ActionQueueDefinitions={inspect=function()return {targets={[visual]=true}},'compat.tidy-equipment'end},
    ActionQueueAcknowledgements={capture=function(action)receipts[action]=receipts[action]or {};return receipts[action]end,
     observe=function(action,receipt)assert(receipt==receipts[action]);return ack end}}
   producer.isStarted=function()return true end;queue.current=producer
   Clothing.observe(state,queue,toolkit,true)
   local beforeGrowth=growthResets
   assert(producer:complete()and visual.hair=='MohawkFan'and consumed==1 and uses==19 and growthResets==beforeGrowth+1)
   Clothing.appearanceCheckpoint(state)
   local checkpoint=Clothing.verify(state,Clothing.removes(state),nil,'checkpoint')
   assert(checkpoint.appearance.hairModel=='MohawkFan'and checkpoint.appearance.gel.uses==19
    and checkpoint.hairUnchanged==true and not checkpoint.appearance.hairGrowthTime,'SP checkpoint appearance/gel flags must remain unchanged')
   -- Completion notification can observe the still-current producer again.
   Clothing.observe(state,queue,toolkit,true)
   local remove=Clothing.removes(state);local label=state.clothingItem:getFullType()..'#'..state.clothingItem:getID()..'@inventory'
   Clothing.observeLine(state,prefix..'capture worn=['..(remove and ''or tostring(state.clothingLocation)..'='..label)..'] inventoryCount=9')
   Clothing.observeLine(state,prefix..'add[add] type='..first.Type..' item='..label)
   Clothing.observeLine(state,prefix..'add[add] type=ISCutHair item=nil')
   Clothing.observeLine(state,prefix..'RESTORE actionTotal=4 trace=[ISReadABook -> '..first.Type..' -> ISCutHair -> ISReadABook] reason=operation:ISReadABook')
   local cleanup=(remove and ISUnequipAction or ISWearClothing):new(player,state.clothingItem,50)
   queue.queue={cleanup};queue.current=cleanup;Clothing.observe(state,queue,toolkit,true)
   beforeGrowth=growthResets;assert(cleanup:complete())
   assert(visual.hair=='MohawkFlat'and uses==19 and consumed==1 and growthResets==beforeGrowth)
   Clothing.observeLine(state,'[P4TidyUpMeister][P0][S-] restore queue complete S17')
   assert(Clothing.settled(state,toolkit,true))
   local proof=Clothing.evidence(state,toolkit,true,{perform=1,complete=1,flush=1,legacy=0})
   assert(proof.appearance.hairModel=='MohawkFlat'and proof.appearanceBaseline.hairModel=='MohawkFan'
    and proof.appearanceCheckpoint.gel.uses==19 and #proof.appearanceAcknowledgements==0 and not proof.hairUnchanged)
   uses=18;assert(not Clothing.appearanceReady(state,'final',true),'extra styling use accepted');uses=19
   local gelKind=state.clothingGel.kind;state.clothingGel.kind='Base.Other'
   local safe,ready=pcall(Clothing.appearanceReady,state,'checkpoint');assert(safe and not ready,'readiness threw while native styling state converges')
   state.clothingGel.kind=gelKind
   visual.attached='Ponytail';assert(not Clothing.appearanceReady(state,'final',true));visual.attached=nil
   isClient=function()return true end;visual.hair='MohawkFan';Clothing.observe(state,queue,toolkit,true)
   assert(Clothing.settled(state,toolkit,true),'MP client native unflattened model must use per-role contract')
   local mpProof=Clothing.evidence(state,toolkit,true,{perform=1,complete=0,flush=1,legacy=0})
   assert(#mpProof.appearanceAcknowledgements==3)
   -- A failed strict final proof logs actual read-only values using the real
   -- fixture JSON writer, before retaining its original assertion failure.
   local previousRequire,previousPrint=require,print
   local JSON=assert(loadfile(ProjectRoot..'/tests/native_queue/health/shared/QueueHealthEvents.lua'))()
   local encoded,diagnostic,printed
   require=function(name)assert(name=='QueueHealthEvents');return {encode=function(value)
    diagnostic=value;encoded=JSON.encode(value);return encoded
   end}end
   print=function(line)assert(not printed,'appearance mismatch emitted more than one diagnostic');printed=line end
   isClient=function()return false end;isServer=function()return true end
   visual.hair=remove and 'MohawkFan'or 'MohawkFlat'
   assert(Clothing.appearanceReady(state,'final',true),'normal Host server must follow exact native Wear/Unequip hair effect')
   visual.hair=remove and 'MohawkFlat'or 'MohawkFan'
   assert(not Clothing.appearanceReady(state,'final',true),'Host server counterpart hairstyle must remain rejected')
   local gelBefore,styleBefore,attachedBefore=uses,visual.hair,visual.attached
   local ok,problem=pcall(Clothing.verify,state,not remove)
   require,print=previousRequire,previousPrint
   assert(not ok and tostring(problem):find('native Mohawk phase effect differs',1,true),'diagnostic must retain the exact strict failure')
   assert(diagnostic.case==case and diagnostic.phase=='final'and diagnostic.tidy==true and diagnostic.role=='server'
    and diagnostic.restored==not remove and diagnostic.currentAppearance.hairModel==styleBefore
    and diagnostic.currentAppearance.gel.uses==19 and diagnostic.currentAppearance.gel.id==state.clothingGel:getID()
    and diagnostic.baseline==state.clothingAppearanceBaseline and diagnostic.checkpoint==state.clothingAppearanceCheckpoint
    and diagnostic.worn.location==tostring(state.clothingLocation)
    and diagnostic.worn.id==(not remove and state.clothingItem:getID()or false)
    and printed=='[EQUIPMENT_TEST] APPEARANCE_MISMATCH '..encoded
    and encoded:find('"hairGrowthTime":false',1,true),'diagnostic omitted/misrepresented actual phase/appearance/worn values')
   assert(uses==gelBefore and visual.hair==styleBefore and visual.attached==attachedBefore,'failure diagnostic mutated native state')
   isClient=function()return true end;isServer=function()return false end;visual.hair='MohawkFan'
   for _,action in ipairs({first,producer,cleanup})do
    local receipt=state.clothingReceipts[action];state.clothingReceipts[action]=nil
    assert(not Clothing.settled(state,toolkit,true),'missing Mohawk native receipt accepted');state.clothingReceipts[action]=receipt
   end
   ack='started';assert(not Clothing.settled(state,toolkit,true));ack='completed'
   state.root.items[state.clothingGel]=nil
   print(case..': native haircut consumes one root gel use; cleanup-only appearance, per-role effects and3 Host receipts passed')
  end
  styleName='CrewCut';visual.hair='CrewCut';player.worn={};state.id='tidy-clothing';isClient=function()return false end
  player.setWornItem,player.removeWornItem=previousSet,previousRemove;state.root.getItems=previousItems;sendClothing=previousSend
 end
 -- Wristwatches use the same real Wear/Unequip and CutHair paths, preserving
 -- authority-seeded alarm configuration and capturing all three native receipts.
 local previousInstanceof=instanceof
 instanceof=function(item,kind)
  if item.kind and item.kind:find('WristWatch',1,true)and (kind=='AlarmClockClothing'or kind=='Clothing')then return true end
  return previousInstanceof(item,kind)
 end
 getGameTime=function()return {getHour=function()return 9 end}end
 local processPending=false
 getCell=function()return {getProcessItems=function()return {contains=function()return true end}end,
  getProcessItemsRemove=function()return {contains=function()return processPending end}end}end
 for _,case in ipairs({'tidy-watch-digital-restore','tidy-watch-digital-remove','tidy-watch-classic-restore','tidy-watch-classic-remove'})do
  local remove=case:match('%-remove$')~=nil
  state.id=case;state.ids=nil;state.clothingP4=nil;state.clothingRestoreAction=nil;state.clothingRestoreReceipt=nil
  state.clothingReceipts=nil;state.clothingProducerStarted=nil;state.clothingWatchReady=nil
  state.clothingSetupPending=nil;state.clothingSetupPrevious=nil;player.worn={};player.primary,player.secondary=state.hammer,state.screwdriver
  visual.hair='CrewCut';visual.attached=nil;isClient,isServer=function()return false end,function()return true end
  local forearm=case:find('digital',1,true)and 'base:forearmleft'or 'base:forearmright'
  local foreign=makeItem('Base.ForearmGuard',state.root);player.worn[forearm]=foreign
  assert(not pcall(Clothing.prepare,state,seedHead)and player.worn[forearm]==foreign,'watch fixture must reject occupied exclusive forearm')
  player.worn[forearm]=nil
  Clothing.prepare(state,seedHead)
  local watch=state.clothingItem;local location=state.clothingLocation;local spec=Clothing.spec(state)
  assert(watch.alarmSynced and watch:getHour()==21 and watch:getMinute()==40 and watch:isAlarmSet()==spec.alarmSet and not watch:isRinging())
  local ids={case=case,items={clothingItem=watch:getID()},clothingHair='CrewCut',clothingSetupPending=state.clothingSetupPending,clothingWatch=state.clothingWatch}
  assert(Clothing.available(player,ids),'exact watch root/alarm setup must become ready')
  watch.minute=41;assert(not Clothing.available(player,ids),'watch replication may not repair alarm minute');watch.minute=40
  if not remove then
   assert(not player:getWornItem(location)and state.clothingSetupPending,'watch restore must wait for root identity before wearing')
   sendClothing=function(actor,slot,item)assert(actor==player and slot==location and item==watch)end
   Clothing.configure(state,watch:getID());ids.clothingSetupPending=nil
  end
  assert(player:getWornItem(location)==(not remove and watch or nil))
  local prior=player.worn[location]
  player.worn[location]={getID=function()return watch:getID()end}
  assert(not Clothing.available(player,ids),'same-ID worn proxy cannot replace the exact root watch')
  player.worn[location]=prior
  local expected=ids.clothingWatch
  ids.clothingWatch={alarmHour=21,alarmMinute=40,alarmSet=spec.alarmSet,ringing=false,unexpected=true}
  assert(not Clothing.available(player,ids),'watch descriptor must reject unreviewed alarm fields');ids.clothingWatch=expected
  isClient,isServer=function()return true end,function()return false end;state.ids=ids
  local setWorn=player.setWornItem;local setAlarm=watch.setAlarmSet
  player.setWornItem=function()error('client must not repair watch worn setup')end
  watch.setAlarmSet=function()error('client must not repair watch alarm setup')end
  Clothing.prepare(state,function(key)state[key]=watch end)
  player.setWornItem=setWorn;watch.setAlarmSet=setAlarm;state.ids=nil
  isClient=function()return false end
  queue.queue={};queue.current=nil;Clothing.enqueue(state,{run=function(callback)return callback()end})
  local first=state.clothingFirst;local producer=state.clothingProducer
  local receipts,receiptStates={},{}
  toolkit={Settings={actionQueue=function()return true end},ActionQueueDefinitions={inspect=function()return {},'compat.tidy-equipment'end},
   ActionQueueAcknowledgements={capture=function(action)
    if queue.current~=action then return nil end
    receipts[action]=receipts[action]or {};return receipts[action]
   end,observe=function(action,receipt)assert(receipt==receipts[action]);return receiptStates[action]end}}
  for _,action in ipairs({first,producer})do
   queue.current=action;isClient=function()return true end
   action.isStarted=function()return true end
   if action==producer then assert(first:complete())end
   Clothing.observe(state,queue,toolkit,true)
   receiptStates[action]='completed'
  end
  assert(producer:complete());assert(state.clothingWatchReady)
  assert(Clothing.verify(state,remove).watch.alarmSet==spec.alarmSet)
  local label=spec.fullType..'#'..watch:getID()..'@inventory'
  Clothing.observeLine(state,prefix..'capture worn=['..(remove and ''or tostring(location)..'='..label)..'] inventoryCount=5')
  Clothing.observeLine(state,prefix..'add[add] type='..first.Type..' item='..label)
  Clothing.observeLine(state,prefix..'add[add] type=ISCutHair item=nil')
  Clothing.observeLine(state,prefix..'RESTORE actionTotal=4 trace=[ISReadABook -> '..first.Type..' -> ISCutHair -> ISReadABook] reason=operation:ISReadABook')
  local cleanup=(remove and ISUnequipAction or ISWearClothing):new(player,watch,50)
  queue.queue={cleanup};queue.current=cleanup
  Clothing.observe(state,queue,toolkit,true);assert(cleanup:complete());receiptStates[cleanup]='completed'
  Clothing.observeLine(state,'[P4TidyUpMeister][P0][S-] restore queue complete S17')
  assert(Clothing.settled(state,toolkit,true))
  for _,action in ipairs({first,producer,cleanup})do
   receiptStates[action]='started';assert(not Clothing.settled(state,toolkit,true))
   assert(not pcall(Clothing.evidence,state,toolkit,true,{}),'each watch native authority receipt must complete')
   receiptStates[action]='completed'
  end
  local outcome=Clothing.evidence(state,toolkit,true,{perform=1,complete=0,flush=1,legacy=0})
  assert(#outcome.watchAcknowledgements==3 and outcome.watchAcknowledgements[1].kind==first.Type
   and outcome.watchAcknowledgements[2].kind=='ISCutHair'and outcome.watchAcknowledgements[2].id==false
   and outcome.watchAcknowledgements[3].kind==cleanup.Type and outcome.watchBaseline.alarmHour==21)
  for key,bad in pairs({hour=22,minute=30,alarm=not spec.alarmSet,ringing=true})do
   local before=watch[key];watch[key]=bad
   assert(not pcall(Clothing.verify,state,not remove)and not Clothing.settled(state,toolkit,true),'changed watch '..key..' accepted')
   watch[key]=before
  end
  isClient=function()return false end
  processPending=true;assert(not Clothing.settled(state,toolkit,true),'authority must wait for native process removal drain')
  processPending=false;local authoritative=Clothing.verify(state,not remove)
  assert(authoritative.watchProcessing.active and not authoritative.watchProcessing.pendingRemoval)
  print(case..': native watch lifecycle, alarm conservation, no client repair and three Host receipts passed')
 end
 instanceof=previousInstanceof
 -- Socks use the same Host restore handshake, retaining a real starter socks
 -- baseline until configuration instead of repairing a client worn proxy.
 state.id='tidy-clothing';player.worn={};isServer=function()return true end
 local starterSocks=makeItem('Base.Socks_Ankle',state.root)
 player.worn['base:socks']=starterSocks
 local synced
 sendClothing=function(actor,location,item)
  assert(actor==player and location=='base:socks');synced=item
 end
 Clothing.prepare(state,seedHead)
 local socks=state.clothingItem
 assert(state.clothingSetupPending and player.worn['base:socks']==starterSocks and not synced)
 local setupIds={case=state.id,items={clothingItem=socks:getID()},clothingHair='CrewCut',clothingSetupPending=true,
  originalWorn={{location='base:socks',id=starterSocks:getID(),fullType='Base.Socks_Ankle'}}}
 assert(Clothing.available(player,setupIds))
 player.worn['base:socks']=nil
 assert(not Clothing.available(player,setupIds),'socks setup must preserve exact authoritative starter baseline')
 assert(not pcall(Clothing.configure,state,socks:getID()),'changed starter baseline must fail configuration')
 player.worn['base:socks']=starterSocks
 Clothing.configure(state,socks:getID())
 assert(synced==socks and player.worn['base:socks']==socks and not state.clothingSetupPending)
 setupIds.clothingSetupPending=nil;state.ids=setupIds
 isClient,isServer=function()return true end,function()return false end
 local setWorn=player.setWornItem
 player.setWornItem=function()error('client must not repair the authoritative restore setup')end
 Clothing.prepare(state,function(key)state[key]=socks end)
 assert(Clothing.available(player,setupIds)and player.worn['base:socks']==socks)
 player.setWornItem=setWorn;state.ids=nil;isClient=function()return false end
 print('tidy-clothing: shared Host handshake conserves starter socks and client only adopts native worn/root identity')
 for _,caseID in ipairs({'tidy-clothing-held-primary','tidy-clothing-held-secondary','tidy-clothing-held-both','tidy-watch-held-primary','tidy-watch-held-secondary','tidy-watch-held-both'})do
  state.id=caseID;state.ids=nil;player.worn={['base:socks']=starterSocks}
  local location=Clothing.spec(state).location
  local prior=not Clothing.wristwatch(state)and starterSocks or nil
  player.primary,player.secondary=state.hammer,state.screwdriver
  local syncOrder={}
  sendEquip=function(actor)assert(actor==player);syncOrder[#syncOrder+1]='hands'end
  sendClothing=function(actor,location,item)
   assert(actor==player and tostring(location)==Clothing.spec(state).location and item==state.clothingItem)
   assert(player.primary==select(1,Clothing.expectedHands(state,true))and player.secondary==select(2,Clothing.expectedHands(state,true)))
   syncOrder[#syncOrder+1]='worn'
  end
  isServer=function()return true end
  Clothing.prepare(state,seedHead)
  local socks=state.clothingItem
  local ids={case=caseID,items={clothingItem=socks:getID(),hammer=state.hammer:getID(),screwdriver=state.screwdriver:getID()},
   clothingHair='CrewCut',clothingSetupPending=true,clothingWatch=state.clothingWatch,originalWorn={{location='base:socks',id=starterSocks:getID(),fullType='Base.Socks_Ankle'}}}
  assert(state.clothingSetupPending and player.worn[location]==(prior or nil) and #syncOrder==0)
  assert(player.primary==state.hammer and player.secondary==state.screwdriver and Clothing.available(player,ids))
  assert(not pcall(Clothing.configure,state,socks:getID()+1),'desired setup accepted wrong exact ID')
  local kind=socks.kind;socks.kind='Base.Other';assert(not pcall(Clothing.configure,state,socks:getID()));socks.kind=kind
  local original=player.primary;player.primary=socks
  assert(not Clothing.available(player,ids)and not pcall(Clothing.configure,state,socks:getID()),'desired pending setup accepted changed baseline hand')
  player.primary=original
  if prior then player.worn[location]=nil else player.worn[location]=starterSocks end
  assert(not pcall(Clothing.configure,state,socks:getID()),'desired setup accepted changed prior worn baseline')
  player.worn[location]=prior or nil
  assert(#syncOrder==0 and state.clothingSetupPending,'rejected desired setup mutated authority')
  Clothing.configure(state,socks:getID())
  assert(syncOrder[1]=='hands'and syncOrder[2]=='worn'and #syncOrder==2)
  assert(not pcall(Clothing.configure,state,socks:getID())and #syncOrder==2,'duplicate desired configuration mutated authority')
  ids.clothingSetupPending=nil
  assert(Clothing.available(player,ids),'desired setup must include exact worn and held root IDs')
  local primary,secondary=player.primary,player.secondary
  player.primary=primary==socks and state.hammer or socks
  assert(not Clothing.available(player,ids),'desired readiness accepted wrong primary hand');player.primary=primary
  player.secondary=secondary==socks and state.screwdriver or socks
  assert(not Clothing.available(player,ids),'desired readiness accepted wrong secondary hand');player.secondary=secondary
  player.worn[location]=starterSocks;assert(not Clothing.available(player,ids));player.worn[location]=socks
  socks.kind='Base.Other';assert(not Clothing.available(player,ids));socks.kind=kind
  state.ids=ids;isServer=function()return false end;isClient=function()return true end
  local p,s,w=player.setPrimaryHandItem,player.setSecondaryHandItem,player.setWornItem
  player.setPrimaryHandItem=function()error('client repaired desired primary')end
  player.setSecondaryHandItem=function()error('client repaired desired secondary')end
  player.setWornItem=function()error('client repaired desired worn')end
  Clothing.prepare(state,function(key)state[key]=socks end)
  assert(Clothing.available(player,ids),'client adoption must preserve exact desired setup')
  assert(not pcall(Clothing.configure,state,socks:getID()))
  player.setPrimaryHandItem,player.setSecondaryHandItem,player.setWornItem=p,s,w
  state.ids=nil;isClient=function()return false end
  print(caseID..': authoritative root/worn/hands handshake, order, wrong identity/type/hands/prior wear, duplicate and client repair gates passed')
 end

 sendEquip=function()end
 state.id='tidy-clothing';player.worn={};styleName='Mohawk'
 assert(not pcall(Clothing.prepare,state,function(key,kind)state[key]=makeItem(kind,state.root);return state[key]end),
  'changed/unsafe target style definition must fail closed')
 print('tidy-clothing: real native constructors/effects, exact socks and unchanged non-consuming hair fixture passed')
end

-- Real native fromHotbar constructors and unequip effects; P4's generated
-- queue/authority are still observed only by the separate SP/Host scenario.
for _,caseID in ipairs({'tidy-hotbar','tidy-hotbar-holster-left','tidy-hotbar-holster-right','tidy-hotbar-normal-left','tidy-hotbar-normal-right','tidy-hotbar-radio-off','tidy-hotbar-radio-on','tidy-hotbar-flashlight-charged','tidy-hotbar-flashlight-empty','tidy-hotbar-flashlight-deplete'})do
 local ordinary=caseID:find('normal',1,true)~=nil;local radio=caseID:find('radio',1,true)~=nil;local flashlight=caseID:match('^tidy%-hotbar%-flashlight%-(.+)$');local passive=ordinary or radio or flashlight~=nil;local prior=caseID=='tidy-hotbar-normal-right'
 getClassSimpleName=function(item)return item.javaClass end
 local provider=caseID~='tidy-hotbar' native('shared/TimedActions/ISEquipWeaponAction.lua');native('shared/TimedActions/ISRackFirearm.lua');native('shared/TimedActions/ISCutHair.lua')
 local baseSource=read('shared/TimedActions/ISBaseTimedAction.lua')
 excerpt(baseSource,'function ISBaseTimedAction:isStarted()','function ISBaseTimedAction:stop()')
 excerpt(baseSource,'function ISBaseTimedAction:create()','function ISBaseTimedAction:begin()')
 excerpt(baseSource,'function ISBaseTimedAction:adjustMaxTime(maxTime)','function ISBaseTimedAction:setActionAnim(')
 MoodleType={UNHAPPY='unhappy',DRUNK='drunk'}
 local createdTime
 LuaTimedActionNew={new=function(action,character)createdTime=action.maxTime;return {isStarted=function()return false end}end}
 excerpt(context,'ISInventoryPaneContextMenu.onRackGun = function','ISInventoryPaneContextMenu.onLoadBulletsIntoFirearm = function')
 excerpt(context,'ISInventoryPaneContextMenu.equipWeapon = function','ISInventoryPaneContextMenu.onInformationItems = function')
 excerpt(read('client/Hotbar/ISHotbar.lua'),'function ISHotbar:isItemAttached(item)','function ISHotbar:attachItem (')
 excerpt(read('client/Hotbar/ISHotbar.lua'),'function ISHotbar:getThisSlotIndex(slotType, list)','function ISHotbar:compareWornItems()')
 excerpt(read('client/Hotbar/ISHotbar.lua'),'local dropItemNow = function','function ISHotbar:getSlotIndexAt(x, y)')
 ISHotbarAttachDefinition=nil;native('client/Hotbar/ISHotbarAttachDefinition.lua')
 local function slot(kind)for _,def in ipairs(ISHotbarAttachDefinition)do if def.type==kind then return {slotType=kind,def=def}end end end
 local Hotbar=assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/shared/QueueEquipmentHotbar.lua'))()
 isClient=function()return false end;isServer=function()return false end
 getText=function(text)return text end
 ISBaseTimedAction.setOverrideHandModels=function()end
 ISBaseTimedAction.setActionAnim=function()end
 ItemTag.FLASHLIGHT='Flashlight';ItemType={RADIO='base:radio'}
 local activatedSync={}
 syncItemActivated=function(_,item)activatedSync[#activatedSync+1]={activated=item:isActivated(),uses=item:getCurrentUses()}end
 local color={getRedFloat=function()return 0.2 end,getGreenFloat=function()return 0.3 end,getBlueFloat=function()return 0.4 end}
 local visual={hair='CrewCut',getHairModel=function(self)return self.hair end,setHairModel=function(self,value)self.hair=value end,
  getNonAttachedHair=function(self)return self.nonAttached end,setNonAttachedHair=function(self,value)self.nonAttached=value end,getHairColor=function()return color end}
 local style={getName=function()return 'CrewCut'end,isAttachedHair=function()return false end}
 getHairStylesInstance=function()return {FindMaleStyle=function()return style end}end
 local player={primary=nil,secondary=nil,attached={},worn={}}
 function player:isFemale()return false end
 function player:getHumanVisual()return visual end
 function player:resetModel()end
 function player:setVariable()end;function player:reportEvent()end
 function player:isHandItem(item)return self.primary==item or self.secondary==item end
 function player:resetHairGrowingTime()self.growthReset=(self.growthReset or 0)+1 end
 function player:getClothingItem_Back()return nil end
 function player:isEquippedClothing()return false end
 function player:getCurrentSquare()return nil end
 getPlayerData=function()return {playerInventory={refreshBackpacks=function()end}}end
 getPlayerInventory=function()return {refreshBackpacks=function()end}end
 sendHumanVisual=function()end
 function player:getPlayerNum()return 0 end
 function player:isTimedActionInstant()return false end
 function player:getMoodles()return {getMoodleLevel=function()return 0 end}end
 function player:getTimedActionTimeModifier()return 1.2 end
 function player:getPrimaryHandItem()return self.primary end
 function player:getSecondaryHandItem()return self.secondary end
 function player:getEquipedRadio()return self.primary and self.primary.javaClass=='Radio'and self.primary or self.secondary and self.secondary.javaClass=='Radio'and self.secondary or nil end
 function player:setPrimaryHandItem(item)self.primary=item end
 function player:setSecondaryHandItem(item)self.secondary=item end
 function player:setAttachedItem(location,item)self.attached[location]=item end
 function player:removeAttachedItem(item)for location,value in pairs(self.attached)do if value==item then self.attached[location]=nil end end end
 function player:removeWornItem()end
 function player:setWornItem(location,item)
  if self.worn[location]==item then return end
  if self.getBodyLocationGroup then
   local group=self:getBodyLocationGroup()
   for other in pairs(self.worn)do if other~=location and group:isExclusive(location,other)then self.worn[other]=nil end end
  end
  self.worn[location]=item
 end
 function player:getWornItem(location)return self.worn[location]end
 function player:getWornItems()return {contains=function(_,item)for _,worn in pairs(self.worn)do if worn==item then return true end end;return false end}end
 function player:getAttachedItems()
  local entries={};for loc,item in pairs(self.attached)do
   local location,value=loc,item;entries[#entries+1]={getLocation=function()return location end,getItem=function()return value end}
  end
  local values=list(entries);values.getItem=function(_,location)return self.attached[location]end;return values
 end
 local state={id=caseID,player=player,root=container()}
 if prior then state.screwdriver=makeItem('Base.Screwdriver',state.root);state.screwdriver.isRequiresEquippedBothHands=function()return false end end
 function player:getInventory()return state.root end
 function state.root:getType()return 'inventory'end
 function state.root:getItemById(id)for item in pairs(self.items)do if item:getID()==id then return item end end end
 function state.root:setDrawDirty()end
 local hotbar={chr=player,availableSlot={[1]=slot('Back'),[7]=slot('HolsterLeft'),[9]=slot('HolsterRight'),[11]=slot('SmallBeltLeft'),[13]=slot('SmallBeltRight'),[15]=slot('WebbingLeft')},replacements={Rifle='Rifle On Back with Bag'}}
 setmetatable(hotbar,{__index=ISHotbar})
 function hotbar:refresh()end
 function hotbar:setAttachAnim()end
 function hotbar:reloadIcons()
  self.attachedItems={};for item in pairs(state.root.items)do if item:getAttachedSlot()>-1 then self.attachedItems[item:getAttachedSlot()]=item end end
 end
 getPlayerHotbar=function()return hotbar end;getSpecificPlayer=function()return player end
 Hotbar.prepare(state,function(name,kind)
  local item=makeItem(kind,state.root);state[name]=item;item.javaClass=flashlight and kind=='Base.FlashLight_AngleHead'and 'DrainableComboItem'or (ordinary or kind=='Base.ScissorsBluntMedical')and 'ComboItem'or radio and kind=='Base.WalkieTalkie2'and 'Radio'or 'HandWeapon'
  function item:getAttachmentType()return flashlight and 'Webbing'or ordinary and 'Screwdriver'or radio and 'Walkie'or provider and 'Holster'or 'Rifle'end
  if kind=='Base.HolsterDouble'then function item:getBodyLocation()return 'base:beltextra'end end
  if kind=='Base.Belt2'then function item:getBodyLocation()return 'base:belt'end end
  if kind=='Base.SCBA_notank'then function item:getBodyLocation()return 'base:scbanotank'end end
  function item:getScriptItem()return {getItemType=function()return item.javaClass=='Radio'and 'base:radio'or item.javaClass=='DrainableComboItem'and 'base:drainable'or 'base:normal'end,isItemType=function(_,kind)return item.javaClass=='Radio'and kind=='base:radio'end}end
  function item:IsWeapon()return not passive end
  function item:getCondition()return self.condition or 10 end;function item:getSharpness()return self.sharpness or 1 end
  function item:getCurrentUsesFloat()return 1 end
  function item:canBeActivated()return false end;function item:isForceDropHeavyItem()return false end
  function item:getCurrentAmmoCount()return 0 end;function item:isRoundChambered()return false end
  function item:isRequiresEquippedBothHands()return not provider end;function item:isTwoHandWeapon()return not provider end
  function item:getName()return 'Shotgun'end;function item:getUnequipSound()end
  function item:getWorldItem()end
  function item:IsClothing()return false end
  if flashlight and kind=='Base.FlashLight_AngleHead'then
   function item:hasTag(tag)return tag==ItemTag.FLASHLIGHT end
   function item:setJobType()end
   function item:canBeActivated()return true end
   function item:setActivated(value)self.activated=value end;function item:isActivated()return self.activated==true end
   function item:playActivateSound()self.onSound=(self.onSound or 0)+1 end
   function item:playDeactivateSound()self.offSound=(self.offSound or 0)+1 end
   function item:getCurrentUses()return self.uses or 0 end;function item:setCurrentUses(value)self.uses=value end
   function item:getCurrentUsesFloat()return self:getCurrentUses()*0.006000000052154064 end
   function item:getUseDelta()return 0.006000000052154064 end;function item:getMaxUses()return 166 end
   function item:isKeepOnDeplete()return true end;function item:isUseWhileEquiped()return true end;function item:isUseWhileUnequiped()return false end
   function item:getReplaceOnDeplete()end;function item:isCookable()return false end;function item:getOnCooked()end;function item:getOnEat()end
   function item:getLightStrength()return 1.5 end;function item:getLightDistance()return 15 end;function item:isTorchCone()return true end
   function item:isEmittingLight()return self:isActivated()and self:getCurrentUses()>0 end
  end
  if radio and kind=='Base.WalkieTalkie2'then
   local data={javaClass='DeviceData',parent=item,power=1,on=false,channel=0,volume=0.5,mic=false}
   for name,key in pairs({getParent='parent',getPower='power',getIsTurnedOn='on',getChannel='channel',getDeviceVolume='volume',getMicIsMuted='mic'})do
    local field=key;data[name]=function(self)return self[field]end
   end
   for name,key in pairs({setPower='power',setTurnedOnRaw='on',setIsTurnedOn='on',setChannelRaw='channel',setDeviceVolumeRaw='volume',setMicIsMuted='mic',setHasBattery='battery'})do
    local field=key;data[name]=function(self,value)self[field]=value end
   end
   function data:getIsPortable()return true end;function data:getIsBatteryPowered()return true end
   function data:getIsTelevision()return false end;function data:hasMedia()return false end;function data:isPlayingMedia()return false end
   function data:getHasBattery()return self.battery end;function data:getHeadphoneType()return -1 end
   function data:getEmitter()return self.on and player:getEquipedRadio()==item and self or nil end
   function item:getDeviceData()return data end;function item:isActivated()return self.activated or false end;function item:setActivated(value)self.activated=value end
  end
  return item
 end)
 -- Host pauses here for its setup acknowledgement before any action exists.
 Hotbar.observe(state,{current=nil,queue={}},nil,true)
 assert(not state.hotbarProducerStarted,'empty pre-enqueue queue counted as native rack start')
 local queue={queue={{Type='ISReadABook'}}}
 ISTimedActionQueue={add=function(action)queue.queue[#queue.queue+1]=action end}
 ISInventoryPaneContextMenu.transferIfNeeded=function(_,item)assert(item:getContainer()==state.root)end
 Hotbar.enqueue(state,{queue=function()return queue end,run=function(fn,...)return fn(...)end})
 queue.current=state.rackAction;Hotbar.observe(state,queue,nil,true)
 assert(not state.hotbarProducerStarted,'unstarted native rack counted as producer start');queue.current=nil
 assert(#queue.queue==3 and state.hotbarEquip.twoHands==not provider and state.hotbarEquip.fromHotbar and (passive and state.rackAction.item==(state.hotbarTool or state.pickup)or not passive and state.rackAction.gun==state.pickup))
 state.hotbarEquip:setOverrideHandModels(nil,nil)
 player:removeAttachedItem(state.pickup)
 if passive then
  assert(state.hotbarEquip.primary==prior and state.hotbarEquip:complete(),'real native nonweapon hand selection failed')
  if flashlight then
   Hotbar.observe(state,{current=state.rackAction,queue={}},nil,true)
   assert(state.pickup:isActivated()==(flashlight~='empty'),'native equip activation differs')
   if flashlight=='deplete'then
    -- Feed the observed native Use result; standalone JVM preflight exercises
    -- actual DrainableComboItem.Use and proves the kept activation/emission edge.
    state.pickup.uses=0;Hotbar.observe(state,{current=state.rackAction,queue={}},nil,true)
   end
  end
  assert(state.rackAction:complete()and player.growthReset==1,'real plain CutHair complete failed')
  assert(state.rackAction.item==(state.hotbarTool or state.pickup)and state.rackAction.maxTime==(flashlight=='deplete'and 3600 or 100))
 else player.primary,player.secondary=Hotbar.expectedHands(state,false)end
 Hotbar.observe(state,{current=nil,queue={}},nil,true)
 assert(not Hotbar.verify(state,false,true).attached)
 if radio then
  local data=state.pickup:getDeviceData();local held=data.on
  data.on=not held
  assert(not Hotbar.radioReady(state,false),'wrong held radio power must fail readiness')
  data.on=held;assert(Hotbar.radioReady(state,false))
 end
 local prefix='[P4TidyUpMeister][P0][S21] '
 local producer=passive and 'ISCutHair'or 'ISRackFirearm'
 local trace='ISReadABook -> ISEquipWeaponAction -> '..producer..' -> ISReadABook'
 local function source(state,omit)
  Hotbar.observeLine(state,prefix..'capture primary=nil secondary='..(prior and 'Base.Screwdriver#'..state.screwdriver:getID()..'@inventory'or 'nil'))
  Hotbar.observeLine(state,prefix..'capture worn=['..(provider and tostring(Hotbar.providerLocation(state))..'='..Hotbar.provider(state):getFullType()..'#'..Hotbar.provider(state):getID()..'@inventory'or '')..'] inventoryCount=4')
  if omit~='equip'then Hotbar.observeLine(state,prefix..'add[add] type=ISEquipWeaponAction item='..state.pickup:getFullType()..'#'..state.pickup:getID()..'@inventory')end
  if omit~='producer'then Hotbar.observeLine(state,prefix..'add[add] type='..producer..' item='..(passive and (state.hotbarTool or state.pickup):getFullType()..'#'..(state.hotbarTool or state.pickup):getID()..'@inventory'or 'nil'))end
  if omit~='finish'then Hotbar.observeLine(state,prefix..'finish armed=true cancelled=false prep=true transfer=false operation=true dismantle=nil restoreHands=true restoreWorn='..tostring(passive)..' queueRestoreOnCancel=nil actionTotal=4 transferCount=0 counts=[ISEquipWeaponAction=1, ISRackFirearm=1, ISReadABook=2] trace=['..trace..']')end
  Hotbar.observeLine(state,prefix..'RESTORE actionTotal=4 trace=['..trace..'] reason=operation:ISReadABook')
 end
 for _,omit in ipairs({'equip','producer','finish'})do state.hotbarP4=nil;source(state,omit);assert(state.hotbarP4.problem,'incomplete native source proof accepted '..omit)end
 state.hotbarP4=nil;source(state)
 assert(state.hotbarP4.restore and not state.hotbarP4.problem)
 Hotbar.observeLine(state,'[P4TidyUpMeister][P0][S-] restore queue complete S22')
 assert(not state.hotbarP4.completed,'foreign completion must not settle')
 local cleanup=ISUnequipAction:new(player,state.pickup,50)
 assert(cleanup.fromHotbar and cleanup.maxTime==50 and cleanup.maxTimeInit==50 and cleanup.animEvent==ISUnequipAction.animEvent)
 local nativeCreate,nativeAdjust=cleanup.create,cleanup.adjustMaxTime
 cleanup:create()
 assert(cleanup.maxTime==60 and cleanup.maxTimeInit==50 and createdTime==60,
  'real native create/adjustMaxTime must apply the 1.2 modifier without changing constructor duration')
 assert(cleanup.create==nativeCreate and cleanup.adjustMaxTime==nativeAdjust,'native timing methods changed')
 queue.queue={cleanup};queue.current=cleanup
 local ack='started'
 local toolkit={Settings={actionQueue=function()return true end},ActionQueueDefinitions={inspect=function()return {},'compat.tidy-equipment'end},
  ActionQueueAcknowledgements={capture=function()return {}end,observe=function()return ack end}}
 Hotbar.observe(state,queue,toolkit,true)
 assert(state.hotbarRestoreDuration==60,'observer must retain the native adjusted duration')
 local originalTime,originalInit=cleanup.maxTime,cleanup.maxTimeInit
 for _,value in ipairs({1,0,-1,math.huge,0/0})do
  cleanup.maxTime=value
  local ok,problem=pcall(Hotbar.observe,state,queue,toolkit,true)
  assert(not ok and tostring(problem):find('maxTime=',1,true),'invalid effective duration must fail with detailed diagnostics')
 end
 cleanup.maxTime=originalTime;cleanup.maxTimeInit=1
 assert(not pcall(Hotbar.observe,state,queue,toolkit,true),'changed constructor duration must fail')
 cleanup.maxTimeInit=originalInit
 for _,name in ipairs({'create','adjustMaxTime'})do
  local original=cleanup[name];cleanup[name]=function()error('foreign timing method')end
  assert(not pcall(Hotbar.observe,state,queue,toolkit,true),'foreign native timing method must fail '..name)
  cleanup[name]=original
 end
 Hotbar.observe(state,queue,toolkit,true)
 assert(not state.hotbarAttachConnect,'cleanup adoption alone must not prove attachConnect')
 cleanup:animEvent('attachConnect')
 Hotbar.observe(state,queue,toolkit,true)
 assert(not state.hotbarAttachConnect,'polling must not claim pre-perform attachment evidence')
 assert(player:getAttachedItems():getItem(state.hotbarLocation)==state.pickup)
 state.hotbarAttachConnect=true -- lifecycle.begin observes this before native perform in the scenario
 if flashlight then
  cleanup.action={isStarted=function()return true end};cleanup:start();Hotbar.observe(state,queue,toolkit,true)
  assert(not state.pickup:isActivated()and (flashlight=='empty'and #activatedSync==0 or flashlight~='empty'and #activatedSync==1 and activatedSync[1].activated==false),'native unequip start must own the off packet')
 end
 cleanup:perform();assert(cleanup:complete());local baselinePrimary,baselineSecondary=Hotbar.expectedHands(state,true);assert(player.primary==baselinePrimary and player.secondary==baselineSecondary)
 if radio then
  -- Exercise vanilla's actual inventory-radio window update: native hand
  -- removal makes it call DeviceData.setIsTurnedOn(false), then close.
  ISRadioWindow={};ISCollapsableWindow={update=function()end}
  excerpt(read('client/RadioCom/ISRadioWindow.lua'),'function ISRadioWindow:update()','function ISRadioWindow:prerender()')
  local window={player=player,device=state.pickup,deviceData=state.pickup:getDeviceData(),deviceType='InventoryItem',
   getIsVisible=function()return true end,close=function(self)self.closed=true end}
  ISRadioWindow.update(window)
  assert(window.closed and not state.pickup:getDeviceData():getIsTurnedOn(),'native radio window did not apply unequip power-off')
 end
 assert(Hotbar.verify(state,true).attached)
 state.hotbarProducerStarted=true
 Hotbar.observeLine(state,'[P4TidyUpMeister][P0][S-] restore queue complete S21')
 isClient=function()return true end
 Hotbar.observe(state,queue,toolkit,true)
 assert(not Hotbar.settled(state,toolkit,true),'started receipt must not settle native hand mutation')
 ack='canceled';assert(not Hotbar.settled(state,toolkit,true),'canceled receipt must not settle native hand mutation')
 ack='completed';assert(Hotbar.settled(state,toolkit,true))
 -- Readiness must never call assert, including successful checks before a
 -- later delayed field/receipt. Vanilla logs assertions even through pcall.
 local originalAssert=assert
 local function quietReady(expected)
  local calls=0
  assert=function(...)calls=calls+1;return originalAssert(...)end
  local ready=Hotbar.settled(state,toolkit,true)
  assert=originalAssert
  assert(calls==0,'hotbar readiness invoked assert while waiting/settled')
  assert(ready==expected,'hotbar readiness accepted partial state or rejected final state')
 end
 quietReady(true)
 state.root.items[state.pickup]=nil;quietReady(false);state.root.items[state.pickup]=true
 local getType=state.pickup.getFullType
 state.pickup.getFullType=function()return provider and 'Base.Shotgun'or 'Base.Pistol'end;quietReady(false);state.pickup.getFullType=getType
 state.pickup:setAttachedSlot(-1);quietReady(false);state.pickup:setAttachedSlot(state.hotbarIndex)
 state.pickup:setAttachedSlotType(nil);quietReady(false);state.pickup:setAttachedSlotType(state.hotbarType)
 state.pickup:setAttachedToModel(nil);quietReady(false);state.pickup:setAttachedToModel(state.hotbarLocation)
 player.primary=state.pickup;quietReady(false);player.primary=nil
 player.secondary=state.pickup;quietReady(false);player.secondary=baselineSecondary
 player:removeAttachedItem(state.pickup);quietReady(false);player:setAttachedItem(state.hotbarLocation,state.pickup)
 hotbar.attachedItems[state.hotbarIndex]=nil;quietReady(false);hotbar.attachedItems[state.hotbarIndex]=state.pickup
 state.hotbarP4.completed=nil;quietReady(false);state.hotbarP4.completed=true
 local receipt=state.hotbarRestoreReceipt;state.hotbarRestoreReceipt=nil;quietReady(false);state.hotbarRestoreReceipt=receipt
 ack='started';quietReady(false);ack='canceled';quietReady(false);ack='completed';quietReady(true)
 assert(Hotbar.evidence(state,toolkit,true,{perform=1,complete=0,flush=1,legacy=0}).nativeGenerated==1)
 state.pickup:setAttachedToModel('Rifle On Back');assert(not pcall(Hotbar.verify,state,true),'wrong model must fail')
 state.pickup:setAttachedToModel(state.hotbarLocation)
 if provider then
  local location,item=Hotbar.providerLocation(state),Hotbar.provider(state)
  player.worn[location]=nil;quietReady(false);player.worn[location]=item
  assert(state.hotbarIndex==(flashlight and 15 or passive and ((prior or caseID=='tidy-hotbar-radio-on')and 13 or 11)or caseID:find('left',1,true)and 7 or 9),'fixture must use the actual dynamic native slot index')
  local effect=Hotbar.verify(state,true)
  assert(effect.providerItem==item:getID()and effect.providerWorn and effect.secondary==(prior and state.screwdriver:getID()or false))
 end
 if radio then
  local effect=Hotbar.evidence(state,toolkit,true,{perform=1,complete=0,flush=1,legacy=0})
  assert(effect.radio.class=='Radio'and effect.radio.parent and not effect.radio.equippedRadio and not effect.radio.emitter)
  assert(effect.radioLifecycle.heldPointer and effect.radioLifecycle.emitterCreated==(caseID=='tidy-hotbar-radio-on'))
  assert(effect.acknowledgements[2].id==state.hotbarTool:getID()and effect.acknowledgements[2].id~=state.pickup:getID(), 'radio must not be passed as haircut tool')
  local data=state.pickup:getDeviceData()
  data.on=true;quietReady(false);data.on=false;quietReady(true)
  local savedServer=isServer;isServer=function()return true end
  local nativeOn=caseID=='tidy-hotbar-radio-on'
  data.on=nativeOn;assert(Hotbar.radioReady(state,true),'server must retain independently seeded native power state')
  data.on=not nativeOn;assert(not Hotbar.radioReady(state,true),'unexpected server power transition must fail')
  data.on=false;isServer=savedServer;quietReady(true)
  data.parent={};quietReady(false);data.parent=state.pickup
  data.power=0.8;quietReady(true);data.power=1.1;quietReady(false);data.power=1
  data.channel=90000;quietReady(false)
  local savedPrint,diagnostics=print,0
  print=function(message)
   if type(message)=='string'and message:find('[EQUIPMENT_TEST] RADIO_STATE ',1,true)then
    diagnostics=diagnostics+1;assert(message:find('reason=setting:channel',1,true)and message:find('baseline=',1,true)and message:find('current=',1,true))
   else savedPrint(message)end
  end
  assert(not pcall(Hotbar.verify,state,true));assert(not pcall(Hotbar.verify,state,true))
  print=savedPrint;assert(diagnostics==1,'radio mismatch diagnostic must print current/baseline once')
  data.channel=88000
  state.hotbarTool.condition=9;quietReady(false);state.hotbarTool.condition=nil;quietReady(true)
  state.hotbarRadioDiagnostic=nil;state.hotbarAttachConnect=false
  local output,assertCalls={},0
  local savedAssert=assert
  print=function(line)output[#output+1]=line end
  assert=function(...)assertCalls=assertCalls+1;return savedAssert(...)end
  local gates={phase='drain',idleUpdates=6,empty=true}
  Hotbar.diagnoseWaiting(state,queue,toolkit,true,10000,gates)
  Hotbar.diagnoseWaiting(state,queue,toolkit,true,10999,gates)
  local early=#output
  Hotbar.diagnoseWaiting(state,queue,toolkit,true,11000,gates)
  Hotbar.diagnoseWaiting(state,queue,toolkit,true,12000,gates)
  assert=savedAssert;print=savedPrint
  assert(early==0 and #output==1 and assertCalls==0,'quiet readiness diagnostic must wait grace, print once and call no asserts')
  assert(output[1]:find('reason=surrounding-readiness',1,true)and output[1]:find('attachConnect=false',1,true)
   and output[1]:find('baseline=',1,true)and output[1]:find('current=',1,true)and output[1]:find('canonical=true',1,true))
  state.hotbarAttachConnect=true;quietReady(true)
  -- A surrounding transaction gate must still be diagnosed when Hotbar.settled
  -- itself is already true and the normal branch never reaches that check.
  state.hotbarRadioDiagnostic=nil;state.hotbarRadioGraceAt=nil;gates.finalGate='transactions'
  output={};assertCalls=0;print=function(line)output[#output+1]=line end
  assert=function(...)assertCalls=assertCalls+1;return savedAssert(...)end
  Hotbar.diagnoseWaiting(state,queue,toolkit,true,20000,gates)
  Hotbar.diagnoseWaiting(state,queue,toolkit,true,21000,gates)
  Hotbar.diagnoseWaiting(state,queue,toolkit,true,22000,gates)
  assert=savedAssert;print=savedPrint
  assert(assertCalls==0 and #output==1 and output[1]:find('finalGate=transactions',1,true)and output[1]:find('settled=true',1,true))
 end
 if flashlight then
  local effect=Hotbar.evidence(state,toolkit,true,{perform=1,complete=0,flush=1,legacy=0})
  assert(effect.providerType=='Base.SCBA_notank'and effect.providerLocation=='base:scbanotank'and effect.flashlight.keepOnDeplete)
  assert(effect.flashlightLifecycle.depleted==(flashlight=='deplete')and not effect.flashlight.activated and not effect.flashlight.emitting)
  assert(effect.acknowledgements[2].id==state.hotbarTool:getID()and effect.acknowledgements[2].id~=state.pickup:getID())
  state.pickup.activated=true;quietReady(false);state.pickup.activated=false;quietReady(true)
  local uses=state.pickup.uses;state.pickup.uses=-1;quietReady(false);state.pickup.uses=uses
  local keep=state.pickup.isKeepOnDeplete;state.pickup.isKeepOnDeplete=function()return false end;quietReady(false);state.pickup.isKeepOnDeplete=keep
  state.hotbarTool.condition=9;quietReady(false);state.hotbarTool.condition=nil;quietReady(true)
  local oldPrint,lines=print,{}
  print=function(line)lines[#lines+1]=line end
  state.pickup.activated=true
  assert(not pcall(Hotbar.verify,state,true));assert(not pcall(Hotbar.verify,state,true))
  state.pickup.activated=false;print=oldPrint
  assert(#lines==1 and lines[1]:find('FLASHLIGHT_STATE',1,true)and lines[1]:find('activation-emission-phase',1,true),'flashlight failure must snapshot once before assertion')
 end
 if ordinary then
  local effect=Hotbar.evidence(state,toolkit,true,{perform=1,complete=0,flush=1,legacy=0})
  assert(#effect.acknowledgements==3 and effect.acknowledgements[2].kind=='ISCutHair'and effect.acknowledgements[2].id==state.pickup:getID())
  assert(effect.ordinary.condition==10 and effect.ordinary.sharpness==1 and effect.ordinary.hairColor.r==0.2)
  for _,class in ipairs({'InventoryItem','DrainableComboItem','Radio'})do
   state.pickup.javaClass=class;quietReady(false);assert(not pcall(Hotbar.verify,state,true),'wrong native factory class accepted '..class)
  end
  state.pickup.javaClass='ComboItem';quietReady(true)
  state.pickup.condition=9;quietReady(false);assert(not pcall(Hotbar.verify,state,true));state.pickup.condition=nil
  state.pickup.sharpness=0.5;quietReady(false);state.pickup.sharpness=nil
  visual.hair='MohawkFan';quietReady(false);visual.hair='CrewCut'
  visual.nonAttached='Ponytail';quietReady(false);visual.nonAttached=nil
  local savedColor=color.getRedFloat;color.getRedFloat=function()return 0.7 end;quietReady(false);color.getRedFloat=savedColor
  if prior then state.root.items[state.screwdriver]=nil;quietReady(false);state.root.items[state.screwdriver]=true end
  quietReady(true)
 end
 Hotbar.release(state);assert(state.pickup:getAttachedSlot()==-1 and next(player.attached)==nil)
 if provider then
  isServer=function()return true end
  assert(not pcall(Hotbar.configure,state,1),'holster cannot use reserved Back index')
  Hotbar.configure(state,state.hotbarIndex);assert(state.pickup:getAttachedSlot()==state.hotbarIndex)
  Hotbar.release(state);isServer=function()return false end
 end
 print(caseID..': native constructors/attachConnect/hand effects, exact source proof and strict Host receipts passed')
end
