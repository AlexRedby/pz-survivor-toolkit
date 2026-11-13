-- Shared native clothing facts. Legacy cleanup keeps its existing replica,
-- headwear and capacity rules; pending edits add a separate exact-only gate.
require 'TimedActions/ISUnequipAction'
require 'TimedActions/ISWearClothing'
local Proof=require 'PZSurvivorToolkit/SourceProof'
local Weights=require 'PZSurvivorToolkit/ActionQueueWeights'
local Toolkit=PZSurvivorToolkit
local Clothing={}
Toolkit.ActionQueueClothing=Clothing
local kind,equal,actualMeta,each=type,rawequal,toolkitLuaMetatableMatches,pairs
local unequippedWeight=Weights and Weights.unequipped
local factoryFreeWeight=Weights and Weights.factoryFree
local capacityWeight=Weights and Weights.capacity
local class,base,object=ISUnequipAction,ISBaseTimedAction,ISBaseObject
local chain=Proof.nativeActionClassChain
local inspect,lookupSafe,bindingsTrusted,removalWeight,adoptBase
local exported
bindingsTrusted=function()
 if kind(actualMeta)~='function'or not actualMeta(Toolkit,nil)or not actualMeta(Clothing,nil)
  or not equal(PZSurvivorToolkit,Toolkit)or not equal(Toolkit.ActionQueueClothing,Clothing)then return false end
 if not equal(Clothing.bindingsTrusted,bindingsTrusted)then return false end
 return true
end
lookupSafe=function(action)
 return kind(actualMeta)=='function'and actualMeta(Proof,nil)and kind(chain)=='function'
  and Proof.nativeActionClassChain==chain and chain(object,base,class,false)
  and ISUnequipAction==class and ISBaseTimedAction==base and kind(action)=='table'and actualMeta(action,class)
end
local function ordinaryClothingItem(item, character, allowHeadwear)
    if not instanceof(item, "Clothing") or not ItemTag or not ItemTag.REPLACE_PRIMARY or not ItemTag.WEARABLE
        or not ItemBodyLocation or not ItemBodyLocation.HAT or not ItemBodyLocation.FULL_HAT
        or item:getContainer() ~= character:getInventory()
        or (item:getCategory() ~= "Clothing" and not (item:getCategory() == "AlarmClock" and instanceof(item, "AlarmClockClothing")))
        or item:canBeEquipped() ~= nil or item:hasTag(ItemTag.WEARABLE)
        or item:hasTag(ItemTag.REPLACE_PRIMARY) or item:isBroken()
        or item:getAttachedSlot() ~= -1 or isForceDropHeavyItem(item) then return end
    local location = item:getBodyLocation()
    if not location or tostring(location) == "" then return end
    -- AlarmClockClothing is a final Clothing subtype; inventory alarm clocks
    -- share its category but not Wear's bounded single-wrist effects.
    if item:getCategory() == "AlarmClock" and (not ItemBodyLocation.LEFT_WRIST or not ItemBodyLocation.RIGHT_WRIST
        or (location ~= ItemBodyLocation.LEFT_WRIST and location ~= ItemBodyLocation.RIGHT_WRIST)) then return end
    -- Ordinary Wear retains matching hand references; Unequip releases them.
    -- Existing character-hand ownership covers preceding P4 hand restoration.
    -- Native clothing actions retain alarm state on the same watch;
    -- naturally starting/stopping its alarm does not change item ownership.
    if location == ItemBodyLocation.HAT or location == ItemBodyLocation.FULL_HAT then
        if not allowHeadwear then return end
        -- Java setWornItem also flattens Mohawk when newItem is nil. Its
        -- native appearance effect is owned separately from item/hand state.
        local visual = character:getHumanVisual()
        local hair = visual and visual:getHairModel()
        if not hair or type(hair.contains) ~= "function" then return end
    end
    return location
end
local function ordinaryClothing(action, allowHeadwear)
    local item, character = action.item, action.character
    local location = ordinaryClothingItem(item, character, allowHeadwear)
    if not location then return end
    -- Native MP start rebinds from the root by ID. A stale queued proxy must
    -- not prove a missing, replaced or differently configured live garment.
    local liveItem = character:getInventory():getItemById(item:getID())
    if not liveItem or liveItem:getFullType() ~= item:getFullType()
        or ordinaryClothingItem(liveItem, character, allowHeadwear) ~= location then return end
    return location, liveItem
end
-- Java WornItems removes exclusive slots even when setting a slot to nil.
-- Removal keeps the single-item proof. Wear may supply a bounded displaced
-- item collector; unknown/multi-item locations retain their native fallback.
local function clothingWornState(action, location, displaced)
    local character, item = action.character, action.item
    local group = character.getBodyLocationGroup and character:getBodyLocationGroup()
    if not group or not group.getLocation or not group.isMultiItem or not group.isExclusive
        or not group:getLocation(location) or group:isMultiItem(location) ~= false then return end
    local worn, exact, seen = character:getWornItems(), false, {}
    if not worn or not worn.size or not worn.get then return end
    for i = 0, worn:size() - 1 do
        local entry = worn:get(i)
        local otherLocation, other = entry:getLocation(), entry:getItem()
        if not other then return end
        if otherLocation ~= location and other:getID() == item:getID() then return end
        if otherLocation == location then
            if seen[otherLocation] then return end
            seen[otherLocation] = true
            if other:getID() == item:getID() then
                if other:getFullType() ~= item:getFullType() then return end
                exact = other
            elseif not displaced or not displaced(other, otherLocation, true, group) then return end
        else
            local exclusive = group:isExclusive(location, otherLocation)
            if exclusive ~= false then
                if exclusive ~= true or seen[otherLocation] or not displaced
                    or not displaced(other, otherLocation, false, group) then return end
                seen[otherLocation] = true
            end
        end
    end
    return true, exact
end
local function nonnegativeFinite(value)
    return type(value) == "number" and value >= 0 and value < math.huge
end
local function displacedClothing(item, character, location, group)
    return item:getCategory() == "Clothing" and not instanceof(item, "AlarmClockClothing")
        and not item:canBeActivated() and ordinaryClothingItem(item, character, true) == location
        and group:getLocation(location) and group:isMultiItem(location) == false
end
local function ordinaryClothingWear(action, saved)
    local location, liveItem = ordinaryClothing(action, true)
    if not location then return end
    local character, inventory = action.character, action.character:getInventory()
    local group = character.getBodyLocationGroup and character:getBodyLocationGroup()
    if not group or not group.getLocation or not group.isMultiItem then return end
    local proof, current, old, hasDisplaced = saved or {}, {}, nil, false
    -- Keep the original resource set through earlier cleanup and early Host
    -- completion. A newly occupying item cannot borrow an older action's proof.
    for id, entry in pairs(proof) do
        local item = inventory:getItemById(id)
        if not item or item:getFullType() ~= entry.fullType
            or not displacedClothing(item, character, entry.location, group) then return end
    end
    local function collect(item, otherLocation, sameSlot, wornGroup)
        local id = item:getID()
        if id == action.item:getID() or current[id] or inventory:getItemById(id) ~= item
            or not displacedClothing(item, character, otherLocation, wornGroup) then return false end
        local previous = proof[id]
        if saved and (not previous or previous.fullType ~= item:getFullType() or previous.location ~= otherLocation) then return false end
        proof[id] = previous or {fullType = item:getFullType(), location = otherLocation}
        current[id] = item
        hasDisplaced = true
        if sameSlot then old = item end
        return true
    end
    local safe, worn = clothingWornState(action, location, collect)
    if not safe then return end
    -- Native's same-object early return must not conceal a different worn proxy
    -- or an already inconsistent exclusive-slot combination.
    if worn and (worn ~= action.item or worn ~= liveItem or hasDisplaced) then return end
    if old then
        if not inventory.getCapacityWeight or not inventory.getEffectiveCapacity or not inventory.isItemAllowed then return end
        local weight, capacity = inventory:getCapacityWeight(), inventory:getEffectiveCapacity(character)
        if not nonnegativeFinite(weight) or not nonnegativeFinite(capacity) or inventory:isItemAllowed(old) ~= true then return end
        -- Java removes every exclusive entry but only capacity-checks the old
        -- same-slot item. Never credit the incoming item's worn-weight release.
        -- A changed native worn multiplier must not make that incoming item heavier.
        for _, item in ipairs({action.item, liveItem}) do
            local full, equipped = item:getUnequippedWeight(), item:getEquippedWeight()
            if not nonnegativeFinite(full) or not nonnegativeFinite(equipped) or equipped > full then return end
        end
        for _, item in pairs(current) do
            local full, equipped = item:getUnequippedWeight(), item:getEquippedWeight()
            if not nonnegativeFinite(full) or not nonnegativeFinite(equipped) or equipped > full then return end
            weight = weight + full
        end
        if weight + old:getUnequippedWeight() + 0.01 > capacity then return end
    end
    -- Exclusive-only changes have no native drop branch and need no reserve.
    return location, proof
end
local function clothingRemovalCapacity(action, liveItem, stillWorn)
    local inventory = action.character:getInventory()
    if not inventory.getCapacityWeight or not inventory.getEffectiveCapacity or not inventory.isItemAllowed then return false end
    local current, capacity = inventory:getCapacityWeight(), inventory:getEffectiveCapacity(action.character)
    if not nonnegativeFinite(current) or not nonnegativeFinite(capacity) then return false end
    local weight = 0
    for _, item in ipairs({action.item, liveItem, stillWorn or liveItem}) do
        if inventory:isItemAllowed(item) ~= true then return false end
        local value = item.getUnequippedWeight and item:getUnequippedWeight()
        if not nonnegativeFinite(value) then return false end
        local equipped = item.getEquippedWeight and item:getEquippedWeight()
        -- Removal may release worn/held weight before the native drop check.
        -- Negative equipped weight invalidates the full-weight upper bound.
        if not nonnegativeFinite(equipped) then return false end
        weight = math.max(weight, value)
    end
    -- setWornItem checks capacity after releasing worn weight, then adds the
    -- same item's full unequipped weight again. Never credit a pending release.
    -- Once authority removed the slot, one remaining reserve preserves this bound.
    return current + (stillWorn and 2 or 1) * weight + 0.01 <= capacity
end
local function ordinaryClothingRemoval(action)
    local location, item = ordinaryClothing(action, true)
    if not location or item:canBeActivated() or action.item:canBeActivated() then return end
    local safe, stillWorn = clothingWornState(action, location)
    if not safe or not clothingRemovalCapacity(action, item, stillWorn) then return end
    -- Native ordinary-clothing cleanup removes both worn and matching hand
    -- references. The shared contract owns the character's hands as well as
    -- this exact root item; earlier P4 hand restoration may already clear them.
    return location
end

-- Used base owners, not an unrelated whole-base method inventory.
local directBaseNames={'new','stop','perform'}
local inheritedNames={'begin','create','adjustMaxTime','isValidStart','isUsingTimeout','waitToStart','interruptWaitToStart',
 'isStarted','forceComplete','forceStop','forceCancel','getDeltaModifiers','getJobDelta','setActionAnim',
 'setAnimVariable','setOverrideHandModels','getDuration'}
local optionalNames={'serverStart','serverStop','failedPathfind','succeededPathfind','timedActionPathfind'}
local baseMethods,inherited={},{}
local baseSourceSafe=kind(chain)=='function'and chain(object,base,class,true)
if baseSourceSafe then
 for _,name in ipairs(directBaseNames)do baseMethods[name]=base[name]or false end
 for _,name in ipairs(inheritedNames)do inherited[name]=class[name]or false end
 for _,name in ipairs(optionalNames)do inherited[name]=false;if class[name]~=nil then baseSourceSafe=false end end
end
local queueSourceSafe
adoptBase=function(name,previous,replacement)
 if (name~='begin'and name~='stop')or not bindingsTrusted()or not baseSourceSafe
  or ISBaseTimedAction~=base or base[name]~=replacement or baseMethods[name]~=nil and baseMethods[name]~=previous
  or inherited[name]~=nil and inherited[name]~=previous
  or not Proof.closure(previous,'ISBaseTimedAction.lua')or not Proof.closure(replacement,'ActionQueue.lua')then return false end
 if queueSourceSafe==nil then queueSourceSafe=Proof.matches('media/lua/client/PZSurvivorToolkit/ActionQueue.lua',1272255806,'PZSurvivorToolkit',true)end
 if not queueSourceSafe then return false end
 if baseMethods[name]~=nil then baseMethods[name]=replacement end
 if inherited[name]~=nil then inherited[name]=replacement end
 return true
end
local function baseCallbacks(action,overrides)
 if not baseSourceSafe then return false end
 for name,callback in pairs(baseMethods)do if base[name]~=callback then return false end end
 for name,callback in pairs(inherited)do
  if not(overrides and overrides[name])and(action[name]or false)~=callback then return false end
 end
 return true
end
local globals={instanceof=instanceof,getSpecificPlayer=getSpecificPlayer,getClassSimpleName=getClassSimpleName,
 isForceDropHeavyItem=isForceDropHeavyItem,sendEquip=sendEquip,triggerEvent=triggerEvent,ItemTag=ItemTag,ItemBodyLocation=ItemBodyLocation,ISWearClothing=ISWearClothing}
local pendingBindings=Proof.captureBindings({{owner=_G,keys={'pairs','ipairs','math','tostring','instanceof',
 'getSpecificPlayer','getClassSimpleName','isForceDropHeavyItem','sendEquip','triggerEvent','ISWearClothing','ItemTag','ItemBodyLocation'}}})
local enumSlots={}
for owner,names in pairs({[ItemTag or false]={'REPLACE_PRIMARY','WEARABLE'},[ItemBodyLocation or false]={'HAT','FULL_HAT'}})do
 if kind(owner)=='table'or kind(owner)=='userdata'then
  for _,name in ipairs(names)do enumSlots[#enumSlots+1]={owner=owner,name=name,value=owner[name]}end
 end
end
local wear=ISWearClothing
local stopOnWalk=kind(wear)=='table'and wear.isStopOnWalk
local ownNames={'isValid','update','start','stop','animEvent','perform'}
local nativeMethods={}
if kind(class)=='table'then for _,name in ipairs(ownNames)do nativeMethods[name]=Proof.own(class,name)end end
local nativeSources
local function sourceShape(action)
 if not bindingsTrusted()or not lookupSafe(action)or not baseCallbacks(action)or not pendingBindings or not pendingBindings()then return false end
 for name,value in pairs(globals)do if _G[name]~=value then return false end end
 for _,slot in ipairs(enumSlots)do if slot.owner[slot.name]~=slot.value then return false end end
 if kind(stopOnWalk)~='function'or ISWearClothing.isStopOnWalk~=stopOnWalk then return false end
 if nativeSources==nil then
  nativeSources=Proof.matches('media/lua/shared/TimedActions/ISUnequipAction.lua',2851923231,nil,true)
   and Proof.matches('media/lua/shared/TimedActions/ISBaseTimedAction.lua',3104185167,nil,true)
   and Proof.matches('media/lua/shared/TimedActions/ISWearClothing.lua',1104211581,nil,true)
   and Proof.matches('media/lua/shared/TimedActions/ISEquipWeaponAction.lua',4117952124,nil,true)
   and Proof.closure(isForceDropHeavyItem,'ISEquipWeaponAction.lua')
   and Proof.closure(stopOnWalk,'ISWearClothing.lua')
 end
 if not nativeSources then return false end
 for _,name in ipairs(ownNames)do
  local callback=nativeMethods[name]
  if kind(callback)~='function'or Proof.own(class,name)~=callback or action[name]~=callback
   or not Proof.closure(callback,'ISUnequipAction.lua')then return false end
 end
 -- The native registry, including its approved Carts delegate, owns new/complete
 -- and the inherited lifecycle. No new native validity or executor runs here.
 return not action.onStartFunc and not action.onCompleteFunc and not action.onCancelFunc
  and not action.onFailFunc and not action.additionalTest and not action.additionalContext and not action.retriggerLastAction
end
-- Wear is observed independently of the edit registry. Its native callback
-- owner is sufficient for a rejection-only capacity witness, never an edit.
local wearMethods,wearRoles={}, {isValid=6,update=18,start=53,stop=77,perform=83,complete=102,
 isAlreadyEquipped=134,getDuration=144,stopSound=155,new=165,isStopOnWalk=206}
local wearLine=getFirstLineOfClosure
local wearInitial=kind(chain)=='function'and chain(object,base,wear,true)
if wearInitial then for name in pairs(wearRoles)do wearMethods[name]=Proof.own(wear,name)end end
local function wearLookup(action)
 return kind(actualMeta)=='function'and actualMeta(Proof,nil)and Proof.nativeActionClassChain==chain
  and kind(chain)=='function'and ISWearClothing==wear and ISBaseTimedAction==base
  and chain(object,base,wear,false)and kind(action)=='table'and actualMeta(action,wear)
end
local function wearSource(action)
 if not bindingsTrusted()or not wearInitial or not wearLookup(action)or not baseCallbacks(action,wearMethods)
  or not pendingBindings or not pendingBindings()or kind(wearLine)~='function'or getFirstLineOfClosure~=wearLine then return false end
 for name,value in pairs(globals)do if _G[name]~=value then return false end end
 for _,slot in ipairs(enumSlots)do if slot.owner[slot.name]~=slot.value then return false end end
 if nativeSources==nil then
  nativeSources=Proof.matches('media/lua/shared/TimedActions/ISUnequipAction.lua',2851923231,nil,true)
   and Proof.matches('media/lua/shared/TimedActions/ISBaseTimedAction.lua',3104185167,nil,true)
   and Proof.matches('media/lua/shared/TimedActions/ISWearClothing.lua',1104211581,nil,true)
   and Proof.matches('media/lua/shared/TimedActions/ISEquipWeaponAction.lua',4117952124,nil,true)
   and Proof.closure(isForceDropHeavyItem,'ISEquipWeaponAction.lua')
   and Proof.closure(stopOnWalk,'ISWearClothing.lua')
 end
 if not nativeSources then return false end
 for name,line in pairs(wearRoles)do
  local callback=wearMethods[name]
  if kind(callback)~='function'or Proof.own(wear,name)~=callback or action[name]~=callback
   or not Proof.closure(callback,'ISWearClothing.lua')or wearLine(callback)~=line then return false end
 end
 -- Every optional engine callback was absent in this native Wear class.
 if action.animEvent~=nil then return false end
 return not action.onStartFunc and not action.onCompleteFunc and not action.onCancelFunc
  and not action.onFailFunc and not action.additionalTest and not action.additionalContext and not action.retriggerLastAction
end
inspect=function(action)
 if not sourceShape(action)or action.action or action.started or action._isAddingActions
  or action.toolkitNativeTransaction~=nil or action.toolkitNativeKind~=nil
  or kind(action.toolkitQueueOperation)=='table'and(action.toolkitQueueOperation.toolkitStarted or action.toolkitQueueOperation.toolkitCancelled)
  or action.fromHotbar or action.reason~=nil or action.animSpeed~=1 or action.clothingAction~=true
  or action.ignoreHandsWounds~=true or action.stopOnAim~=false or action.stopOnRun~=true
  or not nonnegativeFinite(action.maxTimeInit)or action.maxTimeInit<1
  or not nonnegativeFinite(action.maxTime)or action.maxTime<1
  or action.maxTime~=1 and action.maxTime~=action.maxTimeInit then return end
 local actor,item=action.character,action.item
 if not instanceof(actor,'IsoPlayer')or getSpecificPlayer(actor:getPlayerNum())~=actor or actor:isDead()or actor:isAsleep()
  or not instanceof(item,'Clothing')or getClassSimpleName(item)~='Clothing'then return end
 local root=actor:getInventory();local id,fullType=item:getID(),item:getFullType()
 if not instanceof(root,'ItemContainer')or kind(id)~='number'or id~=id or math.abs(id)==math.huge or id%1~=0
  or kind(fullType)~='string'or fullType==''or root:getItemWithID(id)~=item
  or actor:getPrimaryHandItem()==item or actor:getSecondaryHandItem()==item or item:canBeActivated()then return end
 local location=ordinaryClothingItem(item,actor,false)
 if not location or action.stopOnWalk~=stopOnWalk(item)then return end
 local safe,worn=clothingWornState(action,location)
 if not safe or worn~=item or actor:getWornItem(location)~=item then return end
 return {items={[id]=true},itemTypes={[fullType]=true},targets={},hands=actor,
  preparation=true,preparationFinish=true,cancelWaiting=false,cancelOperation=true,interrupt='finish-step',
  moveRequiresProjection=true,clothingRemoval=true,
  edit={version=1,complete=true,capacity='external',resources={{domain='item',key=id,
   facts={item=item,location=root,worn=true},requires={{field='location',equal=root},{field='worn',equal=true}},
   effects={{field='worn',set=false}}}}}}
end
-- Explicit edit decisions only. The cached source-owned descriptor identifies
-- the item; this helper returns no item/queue authority and credits no release.
removalWeight=function(action,contract)
 if not bindingsTrusted()or not Weights or Toolkit.ActionQueueWeights~=Weights
  or kind(unequippedWeight)~='function'or Weights.unequipped~=unequippedWeight then return end
 local item,root=action.item,action.character:getInventory()
 if not instanceof(item,'Clothing')or item:getContainer()~=root or root:getItemWithID(item:getID())~=item
  or root:getAcceptItemFunction()~=nil or root:getOnlyAcceptCategory()~=nil
  or root:isItemAllowed(item)~=true then return end
 local full=unequippedWeight(item)
 local equipped=item:getEquippedWeight()
 if nonnegativeFinite(full)and nonnegativeFinite(equipped)then return full,equipped end
end
-- Rejection-only Host freshness. A positive native removal can finish before
-- its worn sync crosses the other ordered channel. Keep only unresolved owned
-- admissions; receipts alone never certify the local capacity mode.
local client,protectedCall=isClient,pcall
local nativeOwner,nativeBinding,lifecycle,acks
local registerObserver,captureAck,observeAck,resetAck
local notifications={}
local firstLine=getFirstLineOfClosure
local observerReady,observerFault,armed=false,false,false
local installing=false
local histories={}
local bindNative,installObserver,capacityFresh,handReserve
local witnessSourceTrusted
local bootstrapFailure
local function plain(value)return kind(value)=='table'and kind(actualMeta)=='function'and actualMeta(value,nil)end
local function witnessBindings()
 return bindingsTrusted()and plain(nativeOwner)and equal(Toolkit.ActionQueuePolicy,nativeOwner)
  and equal(nativeOwner.matchesNative,nativeBinding)and plain(lifecycle)and equal(Toolkit.ActionQueueLifecycle,lifecycle)
  and equal(lifecycle.registerObserver,registerObserver)and equal(lifecycle.started,notifications.started)
  and equal(lifecycle.begin,notifications.begin)and equal(lifecycle.finish,notifications.finish)
  and equal(lifecycle.flush,notifications.flush)and equal(lifecycle.reset,notifications.reset)and plain(acks)and equal(Toolkit.ActionQueueAcknowledgements,acks)
  and equal(acks.capture,captureAck)and equal(acks.observe,observeAck)and equal(acks.reset,resetAck)and equal(isClient,client)and equal(pcall,protectedCall)
end
local function canonical(record)
 local actor,item,root=record.actor,record.item,record.root
 if getSpecificPlayer(actor:getPlayerNum())~=actor or actor:isDead()or actor:getInventory()~=root then
  return false,'unresolved:actor-root'
 end
 if item:getID()~=record.id or item:getFullType()~=record.fullType or item:getContainer()~=root then
  return false,'unresolved:item-fields'
 end
 if root:getItemWithID(record.id)~=item then return false,'unresolved:canonical-item'end
 if item:getAttachedSlot()~=-1 then return false,'unresolved:attachment-mode'end
 return true
end
-- Host-only upper reserve for disappearance of the currently observed hand
-- discounts. This is a capacity bound, not an Equip outcome or incoming credit.
local handWeightClasses={InventoryItem=true,ComboItem=true,HandWeapon=true,Clothing=true,DrainableComboItem=true,
 Food=true,Key=true,KeyRing=true,Literature=true,MapItem=true}
handReserve=function(queue)
 if not bindingsTrusted()or not equal(isClient,client)then return end
 if not client()then return 0 end
 if not pendingBindings or not pendingBindings()or not plain(Weights)or Toolkit.ActionQueueWeights~=Weights
  or Weights.unequipped~=unequippedWeight or Weights.factoryFree~=factoryFreeWeight or Weights.capacity~=capacityWeight then return end
 local actor=queue and queue.character
 if not instanceof(actor,'IsoPlayer')or getSpecificPlayer(actor:getPlayerNum())~=actor or actor:isDead()then return end
 local root=actor:getInventory()
 if not instanceof(root,'ItemContainer')or root:getParent()~=actor then return end
 local primary,secondary=actor:getPrimaryHandItem(),actor:getSecondaryHandItem()
 local reserve=0
 local function add(item)
  if item==nil then return true end
  if not instanceof(item,'InventoryItem')or not handWeightClasses[getClassSimpleName(item)]
   or instanceof(item,'InventoryContainer')or instanceof(item,'AnimalInventoryItem')
   or item:getContainer()~=root or root:getItemWithID(item:getID())~=item
   or item:getAttachedSlot()~=-1 or isForceDropHeavyItem(item)or item:canBeActivated()
   or item:getWorldItem()or item:getIsCraftingConsumed()
   or instanceof(item,'Food')and item:haveExtraItems()then return false end
  local upper,equipped=unequippedWeight(item),item:getEquippedWeight()
  if not nonnegativeFinite(upper)or not nonnegativeFinite(equipped)then return false end
  reserve=reserve+math.max(0,upper-equipped)
  return nonnegativeFinite(reserve)
 end
 if not add(primary)or not equal(primary,secondary)and not add(secondary)then return end
 return reserve
end
local function recordSource(record)
 if record.wear then return wearSource(record.action)end
 return lookupSafe(record.action)and nativeBinding(record.action)and sourceShape(record.action)
end
local function settled(record)
 if not recordSource(record)then return false,'unresolved:source'end
 if record.failed then return false,'unresolved:capture-or-callback-failed'end
 if not record.receipt then return false,'unresolved:receipt-missing'end
 if not equal(record.action.action,record.native)or not equal(record.action.character,record.actor)
  or not equal(record.action.item,record.item)or not equal(record.action.toolkitQueueOperation,record.token)then
  return false,'unresolved:action-identity'
 end
 local valid,reason=canonical(record)
 if not valid then return false,reason end
 if record.displaced then for _,entry in ipairs(record.displaced)do
  valid,reason=canonical(entry);if not valid then return false,reason end
 end end
 local status=observeAck(record.action,record.receipt)
 if status==nil then return false,'unresolved:receipt-identity-or-pending'end
 if status=='started'then return false,'unresolved:receipt-started'end
 if status~='completed'and status~='canceled'and status~='rejected'then return false,'unresolved:receipt-terminal'end
 local actor,item=record.actor,record.item
 local primary=equal(actor:getPrimaryHandItem(),item)
 local secondary=equal(actor:getSecondaryHandItem(),item)
 local worn=actor:getWornItems():contains(item)
 if record.wear then
  if primary~=record.primary or secondary~=record.secondary then return false,'unresolved:physical-mode'end
  if status=='completed'then
   local safe,exact=clothingWornState(record.action,record.location)
   if not safe or exact~=item or actor:getWornItem(record.location)~=item then return false,'unresolved:physical-mode'end
   for _,entry in ipairs(record.displaced)do
    if actor:getWornItems():contains(entry.item)or actor:getPrimaryHandItem()==entry.item
     or actor:getSecondaryHandItem()==entry.item then return false,'unresolved:physical-mode'end
   end
   return true
  end
  if worn~=record.worn then return false,'unresolved:canceled-mode'end
  for _,entry in ipairs(record.displaced)do
   if actor:getWornItem(entry.location)~=entry.item or actor:getPrimaryHandItem()==entry.item
    or actor:getSecondaryHandItem()==entry.item then return false,'unresolved:canceled-mode'end
  end
  return true
 end
 if status=='completed'then
  if not primary and not secondary and worn==false then return true end
  return false,'unresolved:physical-mode'
 end
 if primary==record.primary and secondary==record.secondary and worn==record.worn then return true end
 return false,'unresolved:canceled-mode'
end
local function prune(history)
 if history.protected then return false,history.protectedReason or 'protected'end
 local reason,pending
 for index=#history.records,1,-1 do
  local record=history.records[index]
  if record.nonIncreasing then
   -- A single empty-slot Wear can only lower the observed load. Keep its
   -- source/receipt/physical identity until convergence nevertheless: a later
   -- Wear cannot classify displacement from an earlier stale worn snapshot.
   if record.receipt then
    local complete,why=settled(record)
    if complete then table.remove(history.records,index)
    elseif why~='unresolved:receipt-started'and why~='unresolved:physical-mode'then reason=reason or why;pending=true end
   elseif record.failed or not recordSource(record)or not canonical(record)or record.action.character~=record.actor
    or record.action.item~=record.item or record.action.toolkitQueueOperation~=record.token
    or record.native and not equal(record.action.action,record.native)then
    reason=reason or 'unresolved:source';pending=true
   end
  else
   local complete,why=settled(record)
   if complete then table.remove(history.records,index)else reason=reason or why;pending=true end
  end
 end
 return not pending,reason
end
local function observedKind(action)
 if kind(action)~='table'or kind(actualMeta)~='function'then return end
 if kind(class)=='table'and actualMeta(action,class)then return 'remove'end
 if kind(wear)=='table'and actualMeta(action,wear)then return 'wear'end
end
local function wearAdmission(action,actor,root,history)
 if not wearSource(action)or action.fromHotbar~=true or action.clothingAction~=true
  or action.stopOnAim~=true or action.stopOnRun~=true or not nonnegativeFinite(action.maxTime)
  or action.maxTime<1 or action.maxTime~=1 and action.maxTime~=50 then
  history.protected=true;history.protectedReason='protected:admission-source';return
 end
 local item=action.item
 if not instanceof(item,'Clothing')or getClassSimpleName(item)~='Clothing'or item:canBeActivated()
  or item:getContainer()~=root or root:getItemWithID(item:getID())~=item
  or actor:getPrimaryHandItem()==item or actor:getSecondaryHandItem()==item then
  history.protected=true;history.protectedReason='protected:admission-item';return
 end
 local location=ordinaryClothingItem(item,actor,false)
 if not location then history.protected=true;history.protectedReason='protected:admission-clothing';return end
 local displaced,seen={},{}
 local function collect(other,slot,_,group)
  local id=other:getID()
  if seen[id]or id==item:getID()or getClassSimpleName(other)~='Clothing'
   or root:getItemWithID(id)~=other or not displacedClothing(other,actor,slot,group)
   or ordinaryClothingItem(other,actor,false)~=slot
   or actor:getPrimaryHandItem()==other or actor:getSecondaryHandItem()==other then return false end
  seen[id]=true
  displaced[#displaced+1]={actor=actor,root=root,item=other,id=id,fullType=other:getFullType(),location=slot}
  return true
 end
 local safe,worn=clothingWornState(action,location,collect)
 if not safe or worn and(worn~=item or #displaced>0)then
  history.protected=true;history.protectedReason='protected:admission-worn';return
 end
 local full,equipped=item:getUnequippedWeight(),item:getEquippedWeight()
 if not nonnegativeFinite(full)or not nonnegativeFinite(equipped)or equipped>full then
  history.protected=true;history.protectedReason='protected:admission-weight';return
 end
 history.records[#history.records+1]={action=action,actor=actor,queue=history.queue,root=root,item=item,
  id=item:getID(),fullType=item:getFullType(),primary=false,secondary=false,worn=worn==item,
  token=action.toolkitQueueOperation,wear=true,location=location,displaced=displaced,nonIncreasing=#displaced==0}
end
local function admission(action)
 if not client()then return end
 local actionKind=observedKind(action);if not actionKind then return end
 local actor=Proof.own(action,'character')
 if not instanceof(actor,'IsoPlayer')or getSpecificPlayer(actor:getPlayerNum())~=actor then return end
 local queue=ISTimedActionQueue.queues[actor]
 if not queue or queue.current~=action or queue.queue[1]~=action then observerFault=true;return end
 local history=histories[actor:getPlayerNum()]
 if not history then history={actor=actor,queue=queue,root=actor:getInventory(),records={}};histories[actor:getPlayerNum()]=history end
 if not armed or not witnessBindings()or history.actor~=actor or history.queue~=queue or history.root~=actor:getInventory()then history.protected=true;history.protectedReason='protected:admission-context';return end
 -- This native admission boundary may retire older, already-proven receipts;
 -- it does not grant edits or run a capacity/inventory scan.
 prune(history)
 if history.protected or #history.records>=32 then
  history.protected=true;history.protectedReason=history.protectedReason or 'protected:overflow';return
 end
 if actionKind=='wear'then
  if #history.records>0 then
   history.protected=true;history.protectedReason='protected:overlapping-equipment';return
  end
  wearAdmission(action,actor,history.root,history);return
 end
 if not lookupSafe(action)or not nativeBinding(action)or not sourceShape(action)or action.fromHotbar or action.reason~=nil then
  history.protected=true;history.protectedReason='protected:admission-source';return
 end
 local item,root=action.item,actor:getInventory()
 if not instanceof(item,'InventoryItem')or item:getContainer()~=root or root:getItemWithID(item:getID())~=item
  or instanceof(item,'InventoryContainer')or isForceDropHeavyItem(item)or item:getAttachedSlot()~=-1 then history.protected=true;history.protectedReason='protected:admission-item';return end
 local worn=actor:getWornItems():contains(item)
 if worn then
  local location=ordinaryClothingItem(item,actor,false)
  if not location then history.protected=true;history.protectedReason='protected:admission-clothing';return end
  local safe,exact=clothingWornState(action,location)
  if item:canBeActivated()or not safe or exact~=item then history.protected=true;history.protectedReason='protected:admission-worn';return end
 end
 local primary,secondary=equal(actor:getPrimaryHandItem(),item),equal(actor:getSecondaryHandItem(),item)
 if not worn and not primary and not secondary then history.protected=true;history.protectedReason='protected:admission-mode';return end
 history.records[#history.records+1]={action=action,actor=actor,queue=queue,root=root,item=item,
  id=item:getID(),fullType=item:getFullType(),primary=primary,secondary=secondary,worn=worn,
  token=action.toolkitQueueOperation}
end
local function callback(action,phase)
 if not client()or not observedKind(action)or phase~='perform'and phase~='stop'then return end
 local actor=Proof.own(action,'character');local history=histories[actor:getPlayerNum()]
 if not history or history.protected then return end
 for _,record in ipairs(history.records)do
  if equal(record.action,action)then
   if not witnessBindings()or not recordSource(record)
    or not equal(ISTimedActionQueue.queues[actor],record.queue)or record.queue.current~=action
    or record.queue.queue[1]~=action or action.toolkitQueueOperation~=record.token then record.failed=true;return end
   if not action.action then record.failed=true;return end
   local receipt=captureAck(action)
   if not receipt or record.receipt and not equal(record.receipt,receipt)or not action.action then record.failed=true;return end
   record.receipt,record.native=receipt,action.action
   return
  end
 end
 history.protected=true;history.protectedReason='protected:callback-record-missing'
end
local function finished(action,phase,succeeded)
 if succeeded~=false or not observedKind(action)then return end
 local actor=Proof.own(action,'character');local history=actor and histories[actor:getPlayerNum()]
 if history then history.protected=true;history.protectedReason='protected:callback-failed'end
end
local function observed(callback,...)
 local ok=protectedCall(callback,...)
 if not ok then observerFault=true end
end
bindNative=function(owner,callback)
 if not bindingsTrusted()or not plain(owner)or not equal(Toolkit.ActionQueuePolicy,owner)
  or kind(callback)~='function'or not equal(owner.matchesNative,callback)then return false end
 if nativeOwner then return equal(nativeOwner,owner)and equal(nativeBinding,callback)end
 nativeOwner,nativeBinding=owner,callback
 -- Normal main load has Lifecycle/Acks before Policy. Register before gameplay,
 -- not from a potentially late GameStart handler; SP admissions are no-ops.
 installing=true
 local ok=installObserver and installObserver()
 installing=false
 if not ok then observerFault=true end
 return true
end
installObserver=function()
 if not bindingsTrusted()or not equal(isClient,client)then bootstrapFailure=bootstrapFailure or 'bootstrap:bindings';return false end
 if observerReady then armed=witnessBindings();return armed end
 if not installing then bootstrapFailure=bootstrapFailure or 'bootstrap:late-install';return false end
 lifecycle,acks=Toolkit.ActionQueueLifecycle,Toolkit.ActionQueueAcknowledgements
 if not plain(lifecycle)then bootstrapFailure=bootstrapFailure or 'bootstrap:missing-lifecycle';return false end
 if not plain(acks)then bootstrapFailure=bootstrapFailure or 'bootstrap:missing-acks';return false end
 if not plain(nativeOwner)then bootstrapFailure=bootstrapFailure or 'bootstrap:missing-native-owner';return false end
 registerObserver,captureAck,observeAck,resetAck=lifecycle.registerObserver,acks.capture,acks.observe,acks.reset
 for _,name in ipairs({'started','begin','finish','flush','reset'})do notifications[name]=lifecycle[name]end
 if kind(registerObserver)~='function'or kind(captureAck)~='function'or kind(observeAck)~='function'then bootstrapFailure=bootstrapFailure or 'bootstrap:api';return false end
 if kind(firstLine)~='function'or getFirstLineOfClosure~=firstLine then bootstrapFailure=bootstrapFailure or 'bootstrap:metadata';return false end
 local roles={{lifecycle.registerObserver,37,'ActionQueueLifecycle.lua','registerObserver'},
  {lifecycle.started,58,'ActionQueueLifecycle.lua','started'},
  {lifecycle.begin,336,'ActionQueueLifecycle.lua','begin'},
  {lifecycle.finish,360,'ActionQueueLifecycle.lua','finish'},
  {lifecycle.flush,420,'ActionQueueLifecycle.lua','flush'},
  {lifecycle.reset,397,'ActionQueueLifecycle.lua','reset'},
  {acks.capture,120,'ActionQueueAcknowledgements.lua','ack-capture'},
  {acks.observe,159,'ActionQueueAcknowledgements.lua','ack-observe'},
  {acks.reset,108,'ActionQueueAcknowledgements.lua','ack-reset'}}
 for _,role in ipairs(roles)do
  if kind(role[1])~='function'or not Proof.closure(role[1],role[3])then bootstrapFailure=bootstrapFailure or 'bootstrap:role:'..role[4];return false end
  local ok,line=protectedCall(firstLine,role[1])
  if not ok or line~=role[2]then bootstrapFailure=bootstrapFailure or 'bootstrap:role:'..role[4];return false end
 end
 if witnessSourceTrusted==nil then
  witnessSourceTrusted=Proof.closure(registerObserver,'ActionQueueLifecycle.lua')
   and Proof.closure(captureAck,'ActionQueueAcknowledgements.lua')and Proof.closure(observeAck,'ActionQueueAcknowledgements.lua')
   and Proof.matches('media/lua/client/PZSurvivorToolkit/ActionQueueLifecycle.lua',3632280204,'PZSurvivorToolkit',true)
   and Proof.matches('media/lua/client/PZSurvivorToolkit/ActionQueueAcknowledgements.lua',4157001195,'PZSurvivorToolkit',true)
 end
 if not witnessSourceTrusted then bootstrapFailure=bootstrapFailure or 'bootstrap:source';return false end
 if not witnessBindings()then bootstrapFailure=bootstrapFailure or 'bootstrap:bindings';return false end
 observerReady=registerObserver('ordinary-clothing-capacity',{
  started=function(action)observed(admission,action)end,
  begin=function(action,phase)observed(callback,action,phase)end,
  finish=function(action,phase,succeeded)observed(finished,action,phase,succeeded)end})==true
 armed=observerReady
 if not observerReady then bootstrapFailure=bootstrapFailure or 'bootstrap:register'end
 return observerReady
end
-- Optional scalar diagnostics never carry a receipt or change the first result.
capacityFresh=function(queue)
 if not equal(isClient,client)then return false,'mode-binding'end
 if not client()then return true end -- SP never reads or allocates Host history.
 if not armed or not observerReady then return false,bootstrapFailure or 'unarmed'end
 if observerFault then return false,bootstrapFailure or 'observer-fault'end
 if not witnessBindings()then return false,'bindings'end
 if not queue then return false,'queue-missing'end
 local actor=queue.character
 if ISTimedActionQueue.queues[actor]~=queue or getSpecificPlayer(actor:getPlayerNum())~=actor or actor:isDead()then return false,'queue-owner'end
 local history=histories[actor:getPlayerNum()]
 if not history then return true end
 if history.actor~=actor or history.queue~=queue or history.root~=actor:getInventory()then
  history.protected=true;history.protectedReason='protected:history-context';return false,history.protectedReason
 end
 local ok,clean,reason=protectedCall(prune,history)
 if not ok then observerFault=true;return false,'observer-fault'end
 if clean then if #history.records==0 then histories[actor:getPlayerNum()]=nil end;return true end
 return false,reason or 'unresolved'
end
if Events and Events.OnGameStart then Events.OnGameStart.Add(function()
 armed=observerReady and not observerFault and witnessBindings()or false
end)end
if Events and Events.OnMainMenuEnter then Events.OnMainMenuEnter.Add(function()
 histories={};armed=false;observerFault=false
end)end
exported={ordinaryClothingItem=ordinaryClothingItem,ordinaryClothing=ordinaryClothing,
 clothingWornState=clothingWornState,nonnegativeFinite=nonnegativeFinite,displacedClothing=displacedClothing,
 ordinaryClothingWear=ordinaryClothingWear,clothingRemovalCapacity=clothingRemovalCapacity,
 ordinaryClothingRemoval=ordinaryClothingRemoval,lookupSafe=lookupSafe,inspect=inspect,
 removalWeight=removalWeight,bindingsTrusted=bindingsTrusted,adoptBase=adoptBase,bindNative=bindNative,
 installObserver=installObserver,capacityFresh=capacityFresh,handReserve=handReserve}
for name,callback in pairs(exported)do Clothing[name]=callback end
return Clothing
