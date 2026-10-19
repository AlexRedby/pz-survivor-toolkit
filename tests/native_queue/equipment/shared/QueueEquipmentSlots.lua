local Slots={}
function Slots.isBelt(id) return id=='belt-knife' or id=='belt-hammer' end
function Slots.handles(id) return id=='clothing-chain' or id=='hotbar-chain' or Slots.isBelt(id) end
local function attached(player,exclude)
 local result={};local items=player:getAttachedItems()
 for i=0,items:size()-1 do
  local entry=items:get(i);local item=entry:getItem()
  if item~=exclude then result[tostring(entry:getLocation())]=item end
 end
 return result
end
local function sameAttached(player,expected)
 local actual=attached(player)
 for location,item in pairs(expected) do assert(actual[location]==item,'attached identity changed at '..location) end
 for location,item in pairs(actual) do assert(expected[location]==item,'unexpected attachment at '..location) end
end
function Slots.prepare(state,seed)
 if not Slots.handles(state.id) then return end
 if Slots.isBelt(state.id) then
  seed('belt','Base.Belt2')
  state.player:setWornItem(state.belt:getBodyLocation(),state.belt)
  seed('hotbarReplacement',state.id=='belt-knife' and 'Base.HuntingKnife' or 'Base.Hammer',state.source)
  state.beltFavorite=state.options and state.options.belt_favorite==true or false
  state.hotbarReplacement:setFavorite(state.beltFavorite)
  state.hotbarIndex,state.hotbarType=2,'SmallBeltLeft'
  state.hotbarLocation=state.id=='belt-knife' and 'Belt Left Upside' or 'Belt Left'
  state.originalAttached=attached(state.player)
  assert(not state.originalAttached[state.hotbarLocation],'fresh fixture belt model is occupied')
 elseif state.id=='clothing-chain' then
  seed('clothingA','Base.Socks_Ankle',state.source);seed('clothingB','Base.Socks_Ankle')
  state.clothingLocation=state.clothingA:getBodyLocation()
  assert(state.clothingLocation and tostring(state.clothingLocation)~='' and state.clothingB:getBodyLocation()==state.clothingLocation,
   'fixture socks must share one native clothing location')
 else
  seed('hotbarInitial','Base.BaseballBat');seed('hotbarReplacement','Base.BaseballBat',state.source)
  state.hotbarIndex,state.hotbarLocation,state.hotbarType=1,'Shovel Back with Bag','Back'
  assert(state.hotbarInitial:getAttachmentType()=='Shovel' and state.hotbarReplacement:getAttachmentType()=='Shovel',
   'fixture bats require the native Shovel attachment')
  state.originalAttached=attached(state.player,state.hotbarInitial)
  for _,item in pairs(state.originalAttached) do
   assert(item:getAttachedSlot()~=state.hotbarIndex,'fresh fixture requires a vacant native Back hotbar slot')
  end
  assert(not state.originalAttached[state.hotbarLocation],'fresh fixture model attachment is occupied')
  -- The MP client adopts the same server-created item, including its initial attachment.
  state.player:setAttachedItem(state.hotbarLocation,state.hotbarInitial)
  state.hotbarInitial:setAttachedSlot(state.hotbarIndex)
  state.hotbarInitial:setAttachedSlotType(state.hotbarType)
  state.hotbarInitial:setAttachedToModel(state.hotbarLocation)
 end
end
local function operation(state,helpers,callback,...)
 local queue=helpers.queue();local before=#queue.queue
 helpers.run(callback,...)
 local actions={}
 for i=before+1,#queue.queue do actions[#actions+1]=queue.queue[i] end
 assert(#actions>0,'native slot callback did not enqueue')
 return actions
end
local function transfer(state,action,item)
 assert(action and action.Type=='ISInventoryTransferAction' and action.item==item
  and action.srcContainer==state.source and action.destContainer==state.root,'native slot pickup differs')
end
local function wear(action,item)
 assert(action and action.Type=='ISWearClothing' and action.item==item,'native clothing callback differs')
 assert(action.getDuration==ISWearClothing.getDuration and action:getDuration()==50 and action.maxTime==50,
  'native clothing duration changed')
end
function Slots.enqueue(state,helpers)
 if not Slots.handles(state.id) then return false end
 assert(not state.player:isTimedActionInstant(),'native slot durations required')
 if Slots.isBelt(state.id) then
  local queue=helpers.queue()
  assert(#queue.queue==0 and not state.player:hasTimedActions(),'belt click must start with an empty native queue')
  local hotbar=assert(getPlayerHotbar(state.player:getPlayerNum()))
  hotbar:refresh();hotbar:reloadIcons()
  local slot=assert(hotbar.availableSlot[state.hotbarIndex],'native left belt slot missing')
  assert(slot.def.type==state.hotbarType and slot.def.attachments[state.hotbarReplacement:getAttachmentType()]==state.hotbarLocation
   and not hotbar.attachedItems[state.hotbarIndex],'native left belt definition or vacancy differs')
  local actions=operation(state,helpers,ISHotbar.attachItem,hotbar,state.hotbarReplacement,state.hotbarLocation,state.hotbarIndex,slot.def,true)
  assert(#actions==2,'native empty-belt click must enqueue only transfer and attach')
  transfer(state,actions[1],state.hotbarReplacement)
  local action=actions[2]
  assert(action.Type=='ISAttachItemHotbar' and action.item==state.hotbarReplacement and action.hotbar==hotbar
   and action.slot==state.hotbarLocation and action.slotIndex==state.hotbarIndex and action.slotDef==slot.def
   and action.maxTime==-1 and action.animEvent==ISAttachItemHotbar.animEvent,'native belt attach changed')
  state.slotFirst,state.slotLast=actions[1],action
  state.emptyQueueClick=true
 elseif state.id=='clothing-chain' then
  local first=operation(state,helpers,ISInventoryPaneContextMenu.onWearItems,{state.clothingA},state.player:getPlayerNum())
  assert(#first==2,'native bag clothing callback must enqueue pickup and wear')
  transfer(state,first[1],state.clothingA);wear(first[2],state.clothingA)
  state.slotFirst,state.wearAAction=first[1],first[2]
  local second=operation(state,helpers,ISInventoryPaneContextMenu.onWearItems,{state.clothingB},state.player:getPlayerNum())
  assert(#second==1,'native root clothing callback must enqueue one wear')
  wear(second[1],state.clothingB);state.slotLast=second[1]
 else
  local hotbar=assert(getPlayerHotbar(state.player:getPlayerNum()),'native player hotbar missing')
  hotbar:refresh();hotbar:reloadIcons()
  local slot=assert(hotbar.availableSlot[state.hotbarIndex],'native Back slot missing')
  assert(slot.def.type==state.hotbarType and slot.def.attachments[state.hotbarReplacement:getAttachmentType()]=='Shovel Back'
   and hotbar.replacements and hotbar.replacements.Shovel==state.hotbarLocation,
   'native Back definition differs')
  assert(hotbar.attachedItems[state.hotbarIndex]==state.hotbarInitial,'native initial hotbar identity missing')
  local actions=operation(state,helpers,ISHotbar.attachItem,hotbar,state.hotbarReplacement,state.hotbarLocation,state.hotbarIndex,slot.def,true)
  assert(#actions==3,'native hotbar replacement must enqueue pickup, detach and attach')
  transfer(state,actions[1],state.hotbarReplacement)
  local detach,attach=actions[2],actions[3]
  assert(detach.Type=='ISDetachItemHotbar' and detach.item==state.hotbarInitial and detach.hotbar==hotbar,
   'native hotbar detach differs')
  assert(attach.Type=='ISAttachItemHotbar' and attach.item==state.hotbarReplacement and attach.hotbar==hotbar
   and attach.slotIndex==state.hotbarIndex and attach.slot==state.hotbarLocation and attach.slotDef==slot.def,
   'native hotbar attach differs')
  assert(detach.maxTime==-1 and attach.maxTime==-1 and detach.animEvent==ISDetachItemHotbar.animEvent
   and attach.animEvent==ISAttachItemHotbar.animEvent,'native hotbar animation duration changed')
  state.slotFirst,state.detachAction,state.slotLast=actions[1],detach,attach
 end
 return true
end
function Slots.controls(state,helpers)
 if not Slots.handles(state.id) then return false end
 if not helpers.native then
  -- These native actions have display entries but no audited permission to reorder them.
  helpers.denied(state.slotFirst,state.tailAction,true,'move_dependent')
  helpers.denied(state.tailAction,state.slotFirst,false,'move_dependent')
  state.policyChecked=true
 end
 return true
end
function Slots.verify(state,mode)
 if not Slots.handles(state.id) then return end
 local player=state.player
 assert(player:getPrimaryHandItem()==state.hammer and player:getSecondaryHandItem()==state.screwdriver,
  'native slot chain changed unrelated hand identities')
 if state.id=='clothing-chain' then
  assert(player:getWornItem(state.clothingLocation)==state.clothingB,'native clothing replacement reached wrong slot')
  assert(not player:getWornItems():contains(state.clothingA),'replaced clothing remained worn')
  assert(state.clothingA:getContainer()==state.root and state.clothingB:getContainer()==state.root,
   'native clothing identities reached wrong containers')
  assert(state.source:getItems():isEmpty(),'native clothing source did not become empty')
  state.expectedWorn[state.clothingLocation]=state.clothingB
 else
  local expected={};for location,item in pairs(state.originalAttached) do expected[location]=item end
  expected[state.hotbarLocation]=state.hotbarReplacement;sameAttached(player,expected)
  assert(state.hotbarReplacement:getAttachedSlot()==state.hotbarIndex
   and state.hotbarReplacement:getAttachedSlotType()==state.hotbarType
   and state.hotbarReplacement:getAttachedToModel()==state.hotbarLocation,'native replacement attachment metadata differs')
  if state.hotbarInitial then assert(state.hotbarInitial:getAttachedSlot()==-1 and (state.hotbarInitial:getAttachedSlotType()==nil or state.hotbarInitial:getAttachedSlotType()=='')
   and (state.hotbarInitial:getAttachedToModel()==nil or state.hotbarInitial:getAttachedToModel()==''),'native detach did not clear exact initial metadata') end
  assert((not state.hotbarInitial or state.hotbarInitial:getContainer()==state.root) and state.hotbarReplacement:getContainer()==state.root,
   'native hotbar identities reached wrong containers')
  assert(state.source:getItems():isEmpty(),'native hotbar source did not become empty')
  if Slots.isBelt(state.id) then
   assert(state.hotbarReplacement:isFavorite()==state.beltFavorite,'belt click changed favorite flag')
   assert(state.bag:getFullType()=='Base.Bag_ALICEpack_Army' and player:getWornItem(state.location)==state.bag
    and player:getWornItem(state.belt:getBodyLocation())==state.belt,'belt fixture worn equipment changed')
  end
  if not isServer() then
   local hotbar=assert(getPlayerHotbar(player:getPlayerNum()));hotbar:reloadIcons()
   assert(hotbar.attachedItems[state.hotbarIndex]==state.hotbarReplacement,'native hotbar icon identity differs')
  end
 end
 return {slotsVerified=true,clothing=state.id=='clothing-chain',hotbar=state.id=='hotbar-chain',
  nativeDurations=true,policyChecked=mode=='toolkit' and not Slots.isBelt(state.id),emptyQueueClick=state.emptyQueueClick,
  belt=Slots.isBelt(state.id),favoritePreserved=Slots.isBelt(state.id) and state.hotbarReplacement:isFavorite()==state.beltFavorite or nil,
  clothingItem=state.clothingB and state.clothingB:getID(),hotbarItem=state.hotbarReplacement and state.hotbarReplacement:getID()}
end
function Slots.cleanup(state)
 if state.id~='hotbar-chain' and not Slots.isBelt(state.id) then return end
 for _,item in pairs({state.hotbarInitial,state.hotbarReplacement}) do
  state.player:removeAttachedItem(item);item:setAttachedSlot(-1);item:setAttachedSlotType(nil);item:setAttachedToModel(nil)
 end
 sameAttached(state.player,state.originalAttached)
 if not isServer() then
  local hotbar=getPlayerHotbar(state.player:getPlayerNum());if hotbar then hotbar:reloadIcons() end
 end
end
return Slots
