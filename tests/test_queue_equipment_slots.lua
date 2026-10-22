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
function instanceof(item,kind) return false end
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
  if self.kind=='Base.Socks_Ankle'then return 'base:socks'
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
 function i:getCategory() return 'Clothing' end
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
 function player:setWornItem(location,item)self.worn[location]=item end
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
 -- Native Equip -> ordinary Wear produces the overlap; fixture setup does
 -- not seed a held+worn dual state. Generated actions below replay only the
 -- observer contract; real P4 generation and transport belong to SP/Host gates.
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
 state.id='tidy-clothing-overlap';state.clothingP4=nil;state.clothingRestoreAction=nil;state.clothingRestoreReceipt=nil
 state.clothingOverlap=nil;state.clothingProducerStarted=nil;state.clothingCleanup=nil;player.worn={};player.secondary=state.screwdriver
 Clothing.prepare(state,function(key,kind)state[key]=makeItem(kind,state.root);return state[key]end)
 function state.root:getItemWithID(id)return self:getItemById(id)end
 for _,item in ipairs({state.hammer,state.screwdriver,state.clothingItem})do
  item.isForceDropHeavyItem=function()return false end;item.isRequiresEquippedBothHands=function()return false end
  item.getCurrentUsesFloat=function()return 1 end;item.canBeActivated=function()return false end
  item.isActivated=function()return false end;item.getName=item.getFullType
 end
 queue.queue={};Clothing.enqueue(state,{run=function(callback)return callback()end})
 assert(#queue.queue==3 and getmetatable(queue.queue[1])==ISEquipWeaponAction and not queue.queue[1].primary
  and not queue.queue[1].twoHands and getmetatable(queue.queue[2])==ISWearClothing and getmetatable(queue.queue[3])==ISCutHair)
 assert(not player:getWornItem(state.clothingLocation)and player.secondary==state.screwdriver)
 assert(queue.queue[1]:complete());assert(player.secondary==state.clothingItem and not player:getWornItem(state.clothingLocation))
 assert(queue.queue[2]:complete());assert(queue.queue[3]:complete())
 assert(player.secondary==state.clothingItem and player:getWornItem(state.clothingLocation)==state.clothingItem)
 local sockID=state.clothingItem:getID()
 local acks={};local ack='completed'
 toolkit={Settings={actionQueue=function()return true end},
  ActionQueueDefinitions={inspect=function()return {},'compat.tidy-equipment'end},
  ActionQueueAcknowledgements={capture=function(action)if queue.current==action then acks[action]=acks[action]or {};return acks[action]end end,
   observe=function(action,receipt)assert(acks[action]==receipt);return ack end}}
 -- Empty pre-start current and nil producer are a quiet no-op.
 local nextProducer=state.clothingProducer;state.clothingProducer=nil;queue.current=nil
 assert(pcall(Clothing.observe,state,queue,toolkit,true));state.clothingProducer=nextProducer
 state.clothingProducer.isStarted=function()return true end;queue.current=state.clothingProducer
 Clothing.observe(state,queue,toolkit,true)
 assert(state.clothingOverlap.secondary==sockID and state.clothingOverlap.worn==sockID)
 for _,action in ipairs(queue.queue)do queue.current=action;isClient=function()return true end;Clothing.observe(state,queue,toolkit,true)end
 isClient=function()return false end
 sock='Base.Socks_Ankle#'..sockID..'@inventory'
 Clothing.observeLine(state,prefix..'capture primary='..state.hammer:getFullType()..'#'..state.hammer:getID()..'@inventory secondary='..state.screwdriver:getFullType()..'#'..state.screwdriver:getID()..'@inventory')
 Clothing.observeLine(state,prefix..'capture worn=[] inventoryCount=5')
 Clothing.observeLine(state,prefix..'add[add] type=ISEquipWeaponAction item='..sock)
 Clothing.observeLine(state,prefix..'add[add] type=ISWearClothing item='..sock)
 Clothing.observeLine(state,prefix..'add[add] type=ISCutHair item=nil')
 Clothing.observeLine(state,prefix..'RESTORE actionTotal=5 trace=[ISReadABook -> ISEquipWeaponAction -> ISWearClothing -> ISCutHair -> ISReadABook] reason=operation:ISReadABook')
 assert(state.clothingP4.restore and not state.clothingP4.problem)
 P4RestoreAction={Type='P4RestoreAction'};P4RestoreAction.__index=P4RestoreAction
 local equip=ISEquipWeaponAction:new(player,state.screwdriver,50,false,false)
 local activation=setmetatable({item=state.screwdriver,activated=false},P4RestoreAction)
 local unequip=ISUnequipAction:new(player,state.clothingItem,50)
 queue.queue={activation,equip,unequip};queue.current=nil
 assert(not pcall(Clothing.observe,state,queue,toolkit,true),'reordered P4 cleanup must fail')
 queue.queue={equip,activation,unequip};Clothing.observe(state,queue,toolkit,true)
 assert(state.clothingCleanup[1]==equip and state.clothingCleanup[2]==activation and state.clothingCleanup[3]==unequip)
 assert(equip:complete());assert(player.secondary==state.screwdriver and player:getWornItem(state.clothingLocation)==state.clothingItem)
 assert(unequip:complete());assert(Clothing.verify(state,false).secondary==state.screwdriver:getID())
 Clothing.observeLine(state,'[P4TidyUpMeister][P0][S-] restore queue complete S17')
 isClient=function()return true end
 for _,action in ipairs(queue.queue)do queue.current=action;Clothing.observe(state,queue,toolkit,true)end
 queue.current=nil
 local function quietReady(expected)
  local ok,value=pcall(Clothing.settled,state,toolkit,true);assert(ok and value==expected,'clothing overlap readiness must wait quietly')
 end
 ack='started';quietReady(false);ack='completed';quietReady(true)
 player.secondary=state.clothingItem;quietReady(false);player.secondary=state.screwdriver
 local hands={perform=2,complete=0,flush=2,legacy=0,equip=1,activation=1,unequip=0}
 local effect=Clothing.evidence(state,toolkit,true,{perform=1,complete=0,flush=1,legacy=0},hands)
 assert(#effect.overlap.cleanup==3 and #effect.overlap.acknowledgements==6 and effect.overlap.sharedHands==hands)
 isClient=function()return false end
 print('tidy-clothing-overlap: real native secondary Equip/Wear effects, exact observed overlap, cleanup order and strict Host receipts passed')
 for _,name in ipairs({'Bald','Mohawk','Spike','GreasedBack','Buffont'})do
  visual.hair=name;visual.attached='PreviousAttachedStyle'
  Clothing.prepare(state,function(key,kind)state[key]=makeItem(kind,state.root);return state[key]end)
  assert(visual.hair=='CrewCut'and not visual.attached,'random unsafe starting cosmetics must not make fixture flaky')
 end
 -- Headwear setup must preserve existing slots and prove spare native capacity.
 -- Java callbacks/transport remain doubles; SP/Host proves actual P4 generation.
 local group={multi=false}
 function group:getLocation(location)return location end
 function group:isMultiItem()return self.multi end
 function group:isExclusive(a,b)
  return a~=b and (a==ItemBodyLocation.FULL_HAT and (b==ItemBodyLocation.HAT or b=='base:mask')
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
  item.canBeActivated=function()return false end;item.isForceDropHeavyItem=function()return false end
  return item
 end
 for _,case in ipairs({'tidy-headwear-hat-remove','tidy-headwear-full-hat-remove'})do
  state.id=case;state.clothingP4=nil;state.clothingCaptureHands=nil;state.clothingRestoreAction=nil;state.clothingRestoreReceipt=nil
  state.clothingHeadwearReady=nil;state.clothingProducerStarted=nil;state.clothingEmptyHeadwear=nil;player.worn={}
  player.primary,player.secondary=state.hammer,state.screwdriver;visual.hair='CrewCut';visual.attached=nil
  local location=case=='tidy-headwear-hat-remove'and ItemBodyLocation.HAT or ItemBodyLocation.FULL_HAT
  local foreign=makeItem('Base.Other',state.root);player.worn[location]=foreign
  assert(not pcall(Clothing.prepare,state,seedHead),'occupied head slot must fail fixture setup')
  assert(player.worn[location]==foreign,'fixture cleared baseline headwear');player.worn={}
  local exclusive=location==ItemBodyLocation.HAT and ItemBodyLocation.FULL_HAT or 'base:mask'
  player.worn[exclusive]=foreign
  assert(not pcall(Clothing.prepare,state,seedHead),'exclusive baseline headwear must fail setup')
  assert(player.worn[exclusive]==foreign,'fixture cleared baseline exclusive item');player.worn={}
  group.multi=true;assert(not pcall(Clothing.prepare,state,seedHead),'multi-item head slot must fail setup');group.multi=false
  capacity=3;assert(not pcall(Clothing.prepare,state,seedHead),'insufficient capacity must fail setup');capacity=50
  Clothing.prepare(state,seedHead);assert(next(player.worn)==nil and state.clothingEmptyHeadwear)
  queue.queue={};Clothing.enqueue(state,{run=function(callback)return callback()end})
  assert(#queue.queue==2 and getmetatable(queue.queue[1])==ISWearClothing and queue.queue[1].maxTime==50)
  assert(queue.queue[1]:complete());assert(queue.queue[2]:complete())
  assert(player.worn[location]==state.clothingItem and visual.hair=='CrewCut'and not visual.attached)
  state.clothingProducer.isStarted=function()return true end;queue.current=state.clothingProducer
  Clothing.observe(state,queue,toolkit,true);assert(state.clothingHeadwearReady)
  local spec=Clothing.spec(state);local label=spec.fullType..'#'..state.clothingItem:getID()..'@inventory'
  Clothing.observeLine(state,prefix..'capture worn=[] inventoryCount=5')
  Clothing.observeLine(state,prefix..'add[add] type=ISWearClothing item='..label)
  Clothing.observeLine(state,prefix..'add[add] type=ISCutHair item=nil')
  Clothing.observeLine(state,prefix..'RESTORE actionTotal=4 trace=[ISReadABook -> ISWearClothing -> ISCutHair -> ISReadABook] reason=operation:ISReadABook')
  local cleanup=ISUnequipAction:new(player,state.clothingItem,50)
  local nativeReceipt={};local receiptState='started'
  toolkit={Settings={actionQueue=function()return true end},ActionQueueDefinitions={inspect=function(action)assert(action==cleanup);return {},'compat.tidy-equipment'end},
   ActionQueueAcknowledgements={capture=function(action)if queue.current==action then return nativeReceipt end end,
    observe=function(action,receipt)assert(action==cleanup and receipt==nativeReceipt);return receiptState end}}
  queue.queue={cleanup};queue.current=cleanup;isClient=function()return true end
  Clothing.observe(state,queue,toolkit,true);assert(state.clothingRestoreReceipt==nativeReceipt)
  assert(cleanup:complete());assert(Clothing.verify(state,false).fullType==spec.fullType)
  Clothing.observeLine(state,'[P4TidyUpMeister][P0][S-] restore queue complete S17')
  assert(not Clothing.settled(state,toolkit,true),'headwear needs completed native authority')
  receiptState='completed';assert(Clothing.settled(state,toolkit,true))
  local outcome=Clothing.evidence(state,toolkit,true,{perform=1,complete=0,flush=1,legacy=0})
  assert(outcome.headwearSetup.emptyExclusiveSlots and outcome.headwearSetup.capacityBeforeRemoval and outcome.bodyLocation==spec.location)
  isClient=function()return false end
  print(case..': native Wear/CutHair/Unequip, empty exclusive slots, spare capacity, unchanged hair and Host receipt passed')
 end
 state.id='tidy-clothing';player.worn={};styleName='Mohawk'
 assert(not pcall(Clothing.prepare,state,function(key,kind)state[key]=makeItem(kind,state.root);return state[key]end),
  'changed/unsafe target style definition must fail closed')
 print('tidy-clothing: real native constructors/effects, exact socks and unchanged non-consuming hair fixture passed')
end

-- Real native fromHotbar constructors and unequip effects; P4's generated
-- queue/authority are still observed only by the separate SP/Host scenario.
for _,caseID in ipairs({'tidy-hotbar','tidy-hotbar-holster-left','tidy-hotbar-holster-right'})do
 local provider=caseID~='tidy-hotbar' native('shared/TimedActions/ISEquipWeaponAction.lua');native('shared/TimedActions/ISRackFirearm.lua')
 local baseSource=read('shared/TimedActions/ISBaseTimedAction.lua')
 excerpt(baseSource,'function ISBaseTimedAction:isStarted()','function ISBaseTimedAction:stop()')
 excerpt(baseSource,'function ISBaseTimedAction:create()','function ISBaseTimedAction:begin()')
 excerpt(baseSource,'function ISBaseTimedAction:adjustMaxTime(maxTime)','function ISBaseTimedAction:setActionAnim(')
 MoodleType={UNHAPPY='unhappy',DRUNK='drunk'}
 local createdTime
 LuaTimedActionNew={new=function(action,character)createdTime=action.maxTime;return {}end}
 excerpt(context,'ISInventoryPaneContextMenu.onRackGun = function','ISInventoryPaneContextMenu.onLoadBulletsIntoFirearm = function')
 excerpt(context,'ISInventoryPaneContextMenu.equipWeapon = function','ISInventoryPaneContextMenu.onInformationItems = function')
 excerpt(read('client/Hotbar/ISHotbar.lua'),'function ISHotbar:isItemAttached(item)','function ISHotbar:attachItem (')
 excerpt(read('client/Hotbar/ISHotbar.lua'),'function ISHotbar:getThisSlotIndex(slotType, list)','function ISHotbar:compareWornItems()')
 ISHotbarAttachDefinition=nil;native('client/Hotbar/ISHotbarAttachDefinition.lua')
 local function slot(kind)for _,def in ipairs(ISHotbarAttachDefinition)do if def.type==kind then return {slotType=kind,def=def}end end end
 local Hotbar=assert(loadfile(ProjectRoot..'/tests/native_queue/equipment/shared/QueueEquipmentHotbar.lua'))()
 isClient=function()return false end;isServer=function()return false end
 getText=function(text)return text end
 ISBaseTimedAction.setOverrideHandModels=function()end
 local player={primary=nil,secondary=nil,attached={},worn={}}
 function player:getPlayerNum()return 0 end
 function player:isTimedActionInstant()return false end
 function player:getMoodles()return {getMoodleLevel=function()return 0 end}end
 function player:getTimedActionTimeModifier()return 1.2 end
 function player:getPrimaryHandItem()return self.primary end
 function player:getSecondaryHandItem()return self.secondary end
 function player:setPrimaryHandItem(item)self.primary=item end
 function player:setSecondaryHandItem(item)self.secondary=item end
 function player:setAttachedItem(location,item)self.attached[location]=item end
 function player:removeAttachedItem(item)for location,value in pairs(self.attached)do if value==item then self.attached[location]=nil end end end
 function player:removeWornItem()end
 function player:setWornItem(location,item)self.worn[location]=item end
 function player:getWornItem(location)return self.worn[location]end
 function player:getWornItems()return {contains=function(_,item)for _,worn in pairs(self.worn)do if worn==item then return true end end;return false end}end
 function player:getAttachedItems()
  local entries={};for loc,item in pairs(self.attached)do
   local location,value=loc,item;entries[#entries+1]={getLocation=function()return location end,getItem=function()return value end}
  end
  local values=list(entries);values.getItem=function(_,location)return self.attached[location]end;return values
 end
 local state={id=caseID,player=player,root=container()}
 function player:getInventory()return state.root end
 function state.root:getType()return 'inventory'end
 function state.root:getItemById(id)for item in pairs(self.items)do if item:getID()==id then return item end end end
 function state.root:setDrawDirty()end
 local hotbar={chr=player,availableSlot={[1]=slot('Back'),[7]=slot('HolsterLeft'),[9]=slot('HolsterRight')},replacements={Rifle='Rifle On Back with Bag'}}
 setmetatable(hotbar,{__index=ISHotbar})
 function hotbar:refresh()end
 function hotbar:reloadIcons()
  self.attachedItems={};for item in pairs(state.root.items)do if item:getAttachedSlot()>-1 then self.attachedItems[item:getAttachedSlot()]=item end end
 end
 getPlayerHotbar=function()return hotbar end;getSpecificPlayer=function()return player end
 Hotbar.prepare(state,function(name,kind)
  local item=makeItem(kind,state.root);state[name]=item
  function item:getAttachmentType()return provider and 'Holster'or 'Rifle'end
  if kind=='Base.HolsterDouble'then function item:getBodyLocation()return 'base:beltextra'end end
  function item:canBeActivated()return false end;function item:isForceDropHeavyItem()return false end
  function item:getCurrentAmmoCount()return 0 end;function item:isRoundChambered()return false end
  function item:isRequiresEquippedBothHands()return not provider end;function item:isTwoHandWeapon()return not provider end
  function item:getName()return 'Shotgun'end;function item:getUnequipSound()end
  function item:getWorldItem()end
  function item:IsClothing()return false end
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
 assert(#queue.queue==3 and state.hotbarEquip.twoHands==not provider and state.hotbarEquip.fromHotbar and state.rackAction.gun==state.pickup)
 state.hotbarEquip:setOverrideHandModels(nil,nil)
 player:removeAttachedItem(state.pickup);player.primary,player.secondary=state.pickup,Hotbar.secondary(state)
 assert(not Hotbar.verify(state,false,true).attached)
 local prefix='[P4TidyUpMeister][P0][S21] '
 local trace='ISReadABook -> ISEquipWeaponAction -> ISRackFirearm -> ISReadABook'
 local function source(state,omit)
  Hotbar.observeLine(state,prefix..'capture primary=nil secondary=nil')
  Hotbar.observeLine(state,prefix..'capture worn=['..(provider and 'base:beltextra=Base.HolsterDouble#'..state.holster:getID()..'@inventory'or '')..'] inventoryCount=4')
  if omit~='equip'then Hotbar.observeLine(state,prefix..'add[add] type=ISEquipWeaponAction item='..state.pickup:getFullType()..'#'..state.pickup:getID()..'@inventory')end
  if omit~='producer'then Hotbar.observeLine(state,prefix..'add[add] type=ISRackFirearm item=nil')end
  if omit~='finish'then Hotbar.observeLine(state,prefix..'finish armed=true cancelled=false prep=true transfer=false operation=true dismantle=nil restoreHands=true restoreWorn=false queueRestoreOnCancel=nil actionTotal=4 transferCount=0 counts=[ISEquipWeaponAction=1, ISRackFirearm=1, ISReadABook=2] trace=['..trace..']')end
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
 cleanup:perform();assert(cleanup:complete());assert(not player.primary and not player.secondary)
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
 player.secondary=state.pickup;quietReady(false);player.secondary=nil
 player:removeAttachedItem(state.pickup);quietReady(false);player:setAttachedItem(state.hotbarLocation,state.pickup)
 hotbar.attachedItems[state.hotbarIndex]=nil;quietReady(false);hotbar.attachedItems[state.hotbarIndex]=state.pickup
 state.hotbarP4.completed=nil;quietReady(false);state.hotbarP4.completed=true
 local receipt=state.hotbarRestoreReceipt;state.hotbarRestoreReceipt=nil;quietReady(false);state.hotbarRestoreReceipt=receipt
 ack='started';quietReady(false);ack='canceled';quietReady(false);ack='completed';quietReady(true)
 assert(Hotbar.evidence(state,toolkit,true,{perform=1,complete=0,flush=1,legacy=0}).nativeGenerated==1)
 state.pickup:setAttachedToModel('Rifle On Back');assert(not pcall(Hotbar.verify,state,true),'wrong model must fail')
 state.pickup:setAttachedToModel(state.hotbarLocation)
 if provider then
  player.worn[state.holsterLocation]=nil;quietReady(false);player.worn[state.holsterLocation]=state.holster
  assert(state.hotbarIndex==(caseID:find('left',1,true)and 7 or 9),'fixture must use the actual dynamic native slot index')
  local effect=Hotbar.verify(state,true)
  assert(effect.providerItem==state.holster:getID()and effect.providerWorn and effect.secondary==false)
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
