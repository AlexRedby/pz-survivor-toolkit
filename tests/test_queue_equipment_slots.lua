if not NativeActionRoot then print('Equipment slot native checks skipped (pass --native-action-root).'); return end
function require() end
function isServer() return false end
function isClient() return false end
function syncItemFields() end
ItemBodyLocation=setmetatable({},{__index=function(_,key) return key end})
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
 function i:getBodyLocation() if self.kind=='Base.Socks_Ankle' then return 'SOCKS' elseif self.kind=='Base.Belt2' then return 'BELT' end return '' end
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
 assert(Clothing.verify(state,true).id==state.clothingSocks:getID())
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
 local sock='Base.Socks_Ankle#'..state.clothingSocks:getID()..'@inventory'
 local prefix='[P4TidyUpMeister][P0][S17] '
 Clothing.observeLine(state,prefix:gsub('P0','P1')..'capture worn=[SOCKS='..sock..'] inventoryCount=5')
 assert(not state.clothingP4,'foreign player marker must not bind clothing source')
 Clothing.observeLine(state,prefix..'capture worn=[SOCKS='..sock..'] inventoryCount=5')
 Clothing.observeLine(state,prefix..'add[add] type=ISUnequipAction item='..sock)
 Clothing.observeLine(state,prefix..'add[add] type=ISCutHair item=nil')
 Clothing.observeLine(state,prefix..'RESTORE actionTotal=4 trace=[ISReadABook -> ISUnequipAction -> ISCutHair -> ISReadABook] reason=operation:ISReadABook')
 Clothing.observeLine(state,'[P4TidyUpMeister][P0][S-] restore queue complete S18')
 assert(state.clothingP4.restore and not state.clothingP4.completed,'foreign session completion must not settle clothing')
 Clothing.observeLine(state,'[P4TidyUpMeister][P0][S-] restore queue complete S17')
 assert(state.clothingP4.completed and not state.clothingP4.problem,'matching source-owned P4 restore evidence must settle')
 local captured=state.clothingP4;state.clothingP4=nil
 Clothing.observeLine(state,prefix..'capture worn=[SOCKS=Base.Socks_Ankle#-1@inventory] inventoryCount=5')
 assert(not state.clothingP4,'different exact socks identity must not bind P4 capture')
 Clothing.observeLine(state,prefix..'capture worn=[SOCKS='..sock..'] inventoryCount=5')
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
 sock='Base.Socks_Ankle#'..state.clothingSocks:getID()..'@inventory'
 Clothing.observeLine(state,prefix..'capture worn=[SOCKS='..sock..'] inventoryCount=5')
 assert(not state.clothingP4,'occupied original slot must not prove empty-slot restoration')
 Clothing.observeLine(state,prefix..'capture worn=[] inventoryCount=5')
 Clothing.observeLine(state,prefix..'add[add] type=ISWearClothing item='..sock)
 Clothing.observeLine(state,prefix..'add[add] type=ISCutHair item=nil')
 Clothing.observeLine(state,prefix..'RESTORE actionTotal=4 trace=[ISReadABook -> ISWearClothing -> ISCutHair -> ISReadABook] reason=operation:ISReadABook')
 Clothing.observeLine(state,'[P4TidyUpMeister][P0][S-] restore queue complete S17')
 assert(state.clothingP4.completed and not state.clothingP4.problem)
 -- The public observer must bind only the generated native cleanup, and
 -- generic acknowledgements must reach completed before final evidence passes.
 local generated=ISUnequipAction:new(player,state.clothingSocks,50)
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
 local duplicate=ISUnequipAction:new(player,state.clothingSocks,50)
 assert(not pcall(Clothing.observe,state,{queue={duplicate}},toolkit,true),'duplicate generated cleanup must fail')
 -- Native completion is replayed only to validate exact final-state assertions;
 -- real generation/authority is the responsibility of the native SP/Host case.
 assert(ISUnequipAction:new(player,state.clothingSocks,50):complete())
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
 for _,name in ipairs({'Bald','Mohawk','Spike','GreasedBack','Buffont'})do
  visual.hair=name;visual.attached='PreviousAttachedStyle'
  Clothing.prepare(state,function(key,kind)state[key]=makeItem(kind,state.root);return state[key]end)
  assert(visual.hair=='CrewCut'and not visual.attached,'random unsafe starting cosmetics must not make fixture flaky')
 end
 styleName='Mohawk'
 assert(not pcall(Clothing.prepare,state,function(key,kind)state[key]=makeItem(kind,state.root);return state[key]end),
  'changed/unsafe target style definition must fail closed')
 print('tidy-clothing: real native constructors/effects, exact socks and unchanged non-consuming hair fixture passed')
end
