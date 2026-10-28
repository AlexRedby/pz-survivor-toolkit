-- The final native DrainableComboItem use can remove the kit. Admit only a
-- plain, unheld kit whose exact source has a native removal-packet route.
-- Callers separately prove access, appearance effects and queue dependencies.
local FinalUse={}
local classifier,instance,managerOf,server=getClassSimpleName,instanceof,getScriptManager,isServer
local types,drainable=ItemType,ItemType and ItemType.DRAINABLE
local function finite(n)return type(n)=='number'and n==n and n>-math.huge and n<math.huge end
local function integer(n)return finite(n)and n%1==0 end
local function invoker(callback)
 if type(callback)~='function'then return false end
 local ok,kind=pcall(classifier,callback)
 return ok and(kind=='LuaJavaInvoker'or kind=='MultiLuaJavaInvoker')
end
local function member(container,item)
 if not instance(container,'ItemContainer')or classifier(container)~='ItemContainer'
  or item:getContainer()~=container then return false end
 local id,values=item:getID(),container:getItems()
 if not integer(id)or id<1 or id>2147483647 or container:getItemById(id)~=item then return false end
 local n=values:size()
 if not integer(n)or n<1 or n>10000 then return false end
 local refs,ids=0,0
 for i=0,n-1 do
  local value=values:get(i)
  if not instance(value,'InventoryItem')then return false end
  if value==item then refs=refs+1 end
  if value:getID()==id then ids=ids+1 end
 end
 return refs==1 and ids==1
end
local function sender(actor,kit)
 local root,source=actor:getInventory(),kit:getContainer()
 if not instance(root,'ItemContainer')or root:getParent()~=actor or root:getContainingItem()~=nil then return false end
 local item,container,seen=kit,source,{}
 for depth=1,32 do
  if not container or seen[container]or not member(container,item)or container:getVehiclePart()~=nil then return false end
  seen[container]=true
  if container==root then return true end
  local holder=container:getContainingItem()
  if holder then
   if not instance(holder,'InventoryContainer')or classifier(holder)~='InventoryContainer'
    or holder:getInventory()~=container or container:getParent()~=nil then return false end
   local world,parent=holder:getWorldItem(),holder:getContainer()
   if world then
    -- GameServer sends from inventoryContainer.worldItem only for this direct
    -- source. Nested world bags have no route; an outer-container substitute
    -- would address the wrong direct-only removeItemWithID lookup.
    return depth==1 and instance(world,'IsoWorldInventoryObject')and world:getItem()==holder
     and world:getSquare()~=nil and(not server()or parent==nil)
   end
   item,container=holder,parent
  else
   -- The other native world sender uses the direct source's IsoObject parent.
   -- Full live-square, membership and access admission belongs to the caller.
   local object=container:getParent()
   if depth~=1 or not object or not instance(object,'IsoObject')
    or instance(object,'IsoPlayer')or instance(object,'BaseVehicle')or object:getSquare()==nil then return false end
   local n,refs=object:getContainerCount(),0
   if not integer(n)or n<1 or n>32 then return false end
   for i=0,n-1 do if object:getContainerByIndex(i)==container then refs=refs+1 end end
   return refs==1
  end
 end
 return false
end
local function supports(actor,kit)
 if getClassSimpleName~=classifier or instanceof~=instance or getScriptManager~=managerOf or isServer~=server
  or ItemType~=types or not drainable or types.DRAINABLE~=drainable
  or not invoker(classifier)or not invoker(instance)or not invoker(managerOf)or not invoker(server)
  or not instance(actor,'IsoPlayer')or not instance(kit,'InventoryItem')or classifier(kit)~='DrainableComboItem'
  or kit:hasComponents()or kit:getCurrentUses()~=1 or kit:getUses()~=1 or kit:getWorldItem()~=nil
  or kit:getReplaceOnUse()~=nil or kit:getReplaceOnDeplete()~=nil or kit:getLuaCreate()~=nil
  or kit:isDisappearOnUse()~=true or kit:isKeepOnDeplete()~=false or kit:getWeightEmpty()~=0
  or not finite(kit:getActualWeight())or kit:getActualWeight()<0
  or not integer(kit:getAttachedSlot())or kit:getAttachedSlot()>=0
  or kit:getAttachedToModel()~=nil or kit:getAttachedSlotType()~=nil or kit:getEquipParent()~=nil
  or kit:isActivated()or kit:getIsCraftingConsumed()or actor:isEquipped(kit)
  or actor:getPrimaryHandItem()==kit or actor:getSecondaryHandItem()==kit then return false end
 local script,manager=kit:getScriptItem(),managerOf()
 if not script or classifier(script)~='Item'or not manager or classifier(manager)~='ScriptManager'
  or manager:FindItem(kit:getFullType())~=script or script:getFullName()~=kit:getFullType()
  or script:getItemType()~=drainable or script:hasComponents()or script:getObsolete()
  or script:getLuaCreate()~=nil or script:getItemConfigKey()~=nil or script:getItemConfig()~=nil
  or script:getReplaceOnUse()~=nil or script:getReplaceOnDeplete()~=nil or script:isDisappearOnUse()~=true
  or not finite(script:getActualWeight())or script:getActualWeight()<0 then return false end
 return sender(actor,kit)
end
function FinalUse.supports(actor,kit)
 local ok,allowed=pcall(supports,actor,kit)
 return ok and allowed==true
end
return FinalUse
