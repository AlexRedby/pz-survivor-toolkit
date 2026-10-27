-- B42 complete sends the kit in place of the newly added cosmetic. Preserve
-- its body and packet order, correcting only that argument for reviewed inputs.
if not isServer() or isClient() then return end
require 'TimedActions/ISApplyMakeUp'
require 'Definitions/MakeUpDefinitions'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Access=require 'PZSurvivorToolkit/ItemAccess'
local matches,closure=Proof.matches,Proof.closure
local owner,locations=ISApplyMakeUp,ItemBodyLocation
local globals={}
for _,name in ipairs({'isServer','isClient','instanceof','getClassSimpleName','getScriptManager','instanceItem',
 'sendAddItemToContainer','sendRemoveItemFromContainer','sendClothing','sendItemStats','getCell','getVehicleById'})do
 globals[name]=_G[name]
 if type(globals[name])~='function'then return end
end
local function invoker(callback)
 local ok,kind=pcall(globals.getClassSimpleName,callback)
 return ok and(kind=='LuaJavaInvoker'or kind=='MultiLuaJavaInvoker')
end
for _,callback in pairs(globals)do if not invoker(callback)then return end end
if type(owner)~='table'or not locations or type(matches)~='function'or type(closure)~='function'
 or not matches('media/lua/shared/TimedActions/ISApplyMakeUp.lua',3487330035,nil,true)
 or not matches('media/lua/shared/Definitions/MakeUpDefinitions.lua',2881080941,nil,true)then return end
-- Reuse the shared exact-resolution/access boundary rather than a second world
-- or bag permission implementation. Refuse changed entry points before calling it.
if type(Access)~='table'or getmetatable(Access)then return end
local accessMethods={}
for _,name in ipairs({'locate','resolve','integer','validLocator','sameLocation','admit'})do
 local callback=Access[name]
 if type(callback)~='function'or not closure(callback,'ItemAccess.lua')then return end
 accessMethods[name]=callback
end
local safehouse,allowLoot=SafeHouse,SafeHouse and SafeHouse.isSafehouseAllowLoot
if allowLoot and not invoker(allowLoot)then return end
local methods,seen={},{}
for name,callback in pairs(owner)do
 if type(callback)=='function'and name~='derive'then
  if seen[callback]or not closure(callback,'ISApplyMakeUp.lua')then return end
  methods[name],seen[callback]=callback,true
 end
end
for _,name in ipairs({'new','isValid','start','update','stop','perform','complete','getDuration'})do
 if type(methods[name])~='function'then return end
end
local slots={locations.MAKE_UP_FULL_FACE,locations.MAKE_UP_EYES,locations.MAKE_UP_EYES_SHADOW,locations.MAKE_UP_LIPS}
if #slots~=4 then return end
local original,kind,replacement=methods.complete,owner.Type
local function supported(slot)
 for _,value in ipairs(slots)do if value==slot then return true end end
 return false
end
local function live(action)
 if not globals.isServer()or globals.isClient()or ISApplyMakeUp~=owner or ItemBodyLocation~=locations
  or Proof.matches~=matches or Proof.closure~=closure or owner.Type~=kind
  or(owner.__index~=nil and owner.__index~=owner)or type(action)~='table'or getmetatable(action)~=owner
  or action.Type~=kind then return false end
 for name,callback in pairs(globals)do if _G[name]~=callback or not invoker(callback)then return false end end
 if getmetatable(Access)or SafeHouse~=safehouse or(safehouse and safehouse.isSafehouseAllowLoot~=allowLoot)then return false end
 for name,callback in pairs(accessMethods)do
  if Access[name]~=callback or not closure(callback,'ItemAccess.lua')then return false end
 end
 if locations.MAKE_UP_FULL_FACE~=slots[1]or locations.MAKE_UP_EYES~=slots[2]
  or locations.MAKE_UP_EYES_SHADOW~=slots[3]or locations.MAKE_UP_LIPS~=slots[4]then return false end
 for name,callback in pairs(methods)do
  local expected=name=='complete'and replacement or callback
  if owner[name]~=expected or action[name]~=expected then return false end
 end
 for name,callback in pairs(owner)do
  if type(callback)=='function'and name~='derive'and not methods[name]then return false end
 end
 for _,value in pairs(action)do if type(value)=='function'then return false end end
 return not action.onStartFunc and not action.onCompleteFunc and not action.onCancelFunc and not action.onFailFunc
  and not action.additionalTest and not action.retriggerLastAction
end
-- Check native direct membership and bag backrefs before recursive resolution.
-- This also bounds malformed/cyclic ancestry while preserving root duplicate guards.
local function exactChain(item)
 local member,container=item,item:getContainer()
 local seen={}
 for depth=1,32 do
  if not container or seen[container]or not globals.instanceof(container,'ItemContainer')then return false end
  seen[container]=true
  local id=member:getID()
  if not accessMethods.integer(id,2147483647)or container:getItemById(id)~=member then return false end
  local refs,ids=0,0
  local values=container:getItems()
  for i=0,values:size()-1 do
   local value=values:get(i)
   if value==member then refs=refs+1 end
   if value:getID()==id then ids=ids+1 end
  end
  if refs~=1 or ids~=1 then return false end
  local holder=container:getContainingItem()
  if not holder then return true end
  if not globals.instanceof(holder,'InventoryContainer')or not accessMethods.integer(holder:getID(),2147483647)
   or holder:getInventory()~=container then return false end
  local parent=holder:getContainer()
  if not parent then
   local world=holder:getWorldItem()
   return world~=nil and world:getItem()==holder
  end
  member,container=holder,parent
 end
 return false
end
local function eligible(action)
 if not live(action)or not globals.instanceof(action.character,'IsoPlayer')
  or not globals.instanceof(action.item,'InventoryItem')then return false end
 local actor,kit=action.character,action.item
 local root=actor:getInventory()
 if not globals.instanceof(root,'ItemContainer')or root:getParent()~=actor or root:getContainingItem()~=nil
  or not exactChain(kit)then return false end
 local locator=accessMethods.locate(kit,actor)
 if not locator or accessMethods.admit(actor,locator)~=kit then return false end
 if type(MakeUpDefinitions)~='table'or getmetatable(MakeUpDefinitions)
  or type(MakeUpDefinitions.makeup)~='table'or getmetatable(MakeUpDefinitions.makeup)then return false end
 for _,definition in ipairs(MakeUpDefinitions.makeup)do
  if type(definition)~='table'or getmetatable(definition)or type(definition.makeuptypes)~='table'
   or getmetatable(definition.makeuptypes)then return false end
 end
 local manager=globals.getScriptManager()
 if not manager or globals.getClassSimpleName(manager)~='ScriptManager'then return false end
 local script=manager:FindItem(action.type)
 return script~=nil and globals.getClassSimpleName(script)=='Item'and script:getFullName()==action.type
  and script:getLuaCreate()==nil and script:getItemConfigKey()==nil and script:getItemConfig()==nil
  and supported(script:getBodyLocation())
end
-- Corrected native body: only the sendAddItemToContainer item argument differs.
local function correctedComplete(self)
    -- checking
    local canUse = false
    for i,v in ipairs(MakeUpDefinitions.makeup) do
        if v.makeuptypes[self.item:getMakeUpType()] then
            if self.type == v.item  then
                canUse = true
                break
            end
        end
    end
    if not canUse then
        return false
    end

    local makeUpSelected = instanceItem(self.type)
    local previousMakeUp = self.character:getWornItem(makeUpSelected:getBodyLocation());

    self.character:getInventory():AddItem(makeUpSelected);
    sendAddItemToContainer(self.character:getInventory(), makeUpSelected);

    if previousMakeUp and self.character:getInventory():contains(previousMakeUp) then
        sendRemoveItemFromContainer(self.character:getInventory(), previousMakeUp);
        self.character:getInventory():Remove(previousMakeUp);
    end

    self.character:setWornItem(makeUpSelected:getBodyLocation(), makeUpSelected);
    sendClothing(self.character,makeUpSelected:getBodyLocation(), makeUpSelected);

    self.item:Use()
    sendItemStats(self.item)
    return true
end
replacement=function(action)
 local inspected,allowed=pcall(eligible,action)
 if inspected and allowed then return correctedComplete(action)end
 return original(action)
end
owner.complete=replacement
