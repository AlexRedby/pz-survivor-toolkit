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
 function i:getBodyLocation() if self.kind=='Base.Socks_Ankle' then return 'SOCKS' end return '' end
 function i:canBeEquipped() return '' end
 function i:getAttachmentType() return 'Shovel' end
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
local function runCase(id)
 local player={worn={},attached={}}
 function player:isEquipped() return false end
 function player:isTimedActionInstant() return false end
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
 local state={id=id,player=player,root=container(),source=container(),expectedWorn={}}
 local unrelated=makeItem('Base.HolsterSimple',state.root)
 unrelated:setAttachedSlot(2);unrelated:setAttachedSlotType('HolsterRight');unrelated:setAttachedToModel('Holster Right')
 player:setAttachedItem('Holster Right',unrelated)
 state.hammer=makeItem('Base.Hammer',state.root);state.screwdriver=makeItem('Base.Screwdriver',state.root)
 player.hammer,player.screwdriver=state.hammer,state.screwdriver
 local queue={queue={}}
 ISTimedActionQueue={add=function(action) queue.queue[#queue.queue+1]=action end}
 function ISInventoryPaneContextMenu.transferIfNeeded(_,item)
  if item.container~=state.root then ISTimedActionQueue.add({Type='ISInventoryTransferAction',item=item,srcContainer=item.container,destContainer=state.root}) end
 end
 function getSpecificPlayer() return player end
 local hotbar={chr=player,attachedItems={},availableSlot={{def={name='Back',type='Back',attachments={Shovel='Shovel Back'}}}},replacements={Shovel='Shovel Back with Bag'}}
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
 assert(Slots.enqueue(state,{queue=function() return queue end,run=function(fn,...) return fn(...) end}))
 state.tailAction={};local denied=0
 Slots.controls(state,{native=false,denied=function(_,_,_,reason) assert(reason=='move_dependent');denied=denied+1 end})
 assert(denied==2 and state.policyChecked)
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
  player:setAttachedItem(state.hotbarLocation,state.hotbarInitial)
  assert(not pcall(Slots.verify,state,'toolkit'),'wrong attached identity escaped verification')
  player:setAttachedItem(state.hotbarLocation,state.hotbarReplacement)
 end
 assert(Slots.verify(state,'toolkit').slotsVerified)
 Slots.cleanup(state)
 assert(player.attached['Holster Right']==unrelated and unrelated:getAttachedSlot()==2
  and unrelated:getAttachedSlotType()=='HolsterRight' and unrelated:getAttachedToModel()=='Holster Right',
  'unrelated attachment changed during execution or cleanup')
 if id=='hotbar-chain' then
  assert(player.attached[state.hotbarLocation]==nil and state.hotbarInitial:getAttachedSlot()==-1
   and state.hotbarReplacement:getAttachedSlot()==-1,'owned hotbar attachment survived cleanup')
  for _,item in ipairs({state.hotbarInitial,state.hotbarReplacement}) do
   assert(item:getAttachedSlotType()==nil and item:getAttachedToModel()==nil,'owned attachment metadata survived cleanup')
  end
 end
 print(id..': real native callback composition, native final mutation, policy assertions, cleanup passed')
end
runCase('clothing-chain');runCase('hotbar-chain')
