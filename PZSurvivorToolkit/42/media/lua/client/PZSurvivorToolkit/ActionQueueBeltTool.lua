-- Native equip keeps the hotbar assignment while hiding its attached model.
-- Restore hands only; native unequip/ISHotbar.update own model reattachment.
require 'Hotbar/ISHotbar'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Belt={}
local helpers
local function native(hotbar)
 if not helpers then
  if not Proof.matches('media/lua/client/Hotbar/ISHotbar.lua',919776062,nil,true)
   or not Proof.matches('media/lua/client/ISUI/PlayerData/ISPlayerData.lua',2353448738,nil,true)
   or not Proof.closure(getPlayerHotbar,'ISPlayerData.lua')
   or not Proof.closure(ISHotbar.isItemAttached,'ISHotbar.lua')
   or not Proof.closure(ISHotbar.setAttachAnim,'ISHotbar.lua')then return false end
  helpers={owner=ISHotbar,getter=getPlayerHotbar,attached=ISHotbar.isItemAttached,animate=ISHotbar.setAttachAnim}
 end
 return ISHotbar==helpers.owner and getPlayerHotbar==helpers.getter
  and ISHotbar.isItemAttached==helpers.attached and ISHotbar.setAttachAnim==helpers.animate
  and hotbar and hotbar.isItemAttached==helpers.attached and hotbar.setAttachAnim==helpers.animate
end
local function state(actor,item,allowDetached)
 if not instanceof(item,'InventoryItem')or getClassSimpleName(item)~='HandWeapon'
  or item:getFullType()~='Base.Scissors'or item:getAttachmentType()~='Screwdriver'
  or item:getContainer()~=actor:getInventory()or actor:getInventory():getItemById(item:getID())~=item
  or item:isBroken()or item:getIsCraftingConsumed()or item:canBeActivated()
  or item:isForceDropHeavyItem()or item:isRequiresEquippedBothHands()or actor:isEquippedClothing(item)then return end
 local hotbar=getPlayerHotbar(actor:getPlayerNum())
 if not native(hotbar)or hotbar.chr~=actor or type(hotbar.attachedItems)~='table'
  or getmetatable(hotbar.attachedItems)then return end
 local index,kind,model=item:getAttachedSlot(),item:getAttachedSlotType(),item:getAttachedToModel()
 if index==-1 and allowDetached then
  -- SyncItemFields reads a cleared native UTF field back as an empty string.
  if (kind~=nil and kind~='') or (model~=nil and model~='') or hotbar:isItemAttached(item)then return end
  return {item=item,hotbar=hotbar,detached=true}
 end
 if type(index)~='number'or index<1 or index%1~=0 or type(kind)~='string'or kind==''
  or type(model)~='string'or model==''or model=='null'
  or type(hotbar.availableSlot)~='table'or getmetatable(hotbar.availableSlot)then return end
 local slot=hotbar.availableSlot[index]
 local definition=type(slot)=='table'and not getmetatable(slot)and slot.def
 if type(definition)~='table'or getmetatable(definition)or definition.name=='Back'
  or slot.slotType~=kind or definition.type~=kind
  or type(definition.attachments)~='table'or getmetatable(definition.attachments)
  or definition.attachments.Screwdriver~=model or type(definition.animset)~='string'or definition.animset==''
  or hotbar.attachedItems[index]~=item or not hotbar:isItemAttached(item)then return end
 local count=0
 for _,candidate in pairs(hotbar.availableSlot)do
  if type(candidate)~='table'or getmetatable(candidate)or type(candidate.def)~='table'or getmetatable(candidate.def)then return end
  if candidate.def.type==kind then count=count+1 end
 end
 local attached=actor:getAttachedItem(model)
 if count~=1 or attached and attached~=item then return end
 return {item=item,hotbar=hotbar,index=index,kind=kind,model=model,definition=definition}
end
function Belt.capture(actor,item)
 local ok,result=pcall(state,actor,item,false)
 if ok then return result end
end
function Belt.current(actor,item)
 -- A newer native detach/replacement clears assignment metadata. In that case
 -- ordinary hand cleanup is safe and must never resurrect the original slot.
 local ok,result=pcall(state,actor,item,true)
 if ok then return result end
end
function Belt.available(actor)
 local ok,result=pcall(function()
  local hotbar=getPlayerHotbar(actor:getPlayerNum())
  if not hotbar or type(hotbar.attachedItems)~='table' or getmetatable(hotbar.attachedItems) then return false end
  -- This only opens observation of the menu. Capture verifies the item the
  -- native producer actually selected, before any hand restoration is owned.
  for _,item in pairs(hotbar.attachedItems)do
   if item:getFullType()=='Base.Scissors' then return true end
  end
  return false
 end)
 return ok and result==true
end
return Belt
