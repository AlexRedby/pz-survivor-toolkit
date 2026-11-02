require "TimedActions/ISInventoryTransferAction"
require "TimedActions/ISTransferAction"
require "TimedActions/ISDrinkFluidAction"
require "TimedActions/ISEatFoodAction"
require "Fluids/ISFluidEmptyAction"
require "Fluids/ISFluidContainer"
require "Fluids/ISFluidUtil"
local Proof = require "PZSurvivorToolkit/SourceProof"
local EmptyRepair = require "PZSurvivorToolkit/EmptyFluidAction"
local emptyRepairAuthorizes = type(EmptyRepair)=="table" and EmptyRepair.authorizes
local DrinkRepair = require "PZSurvivorToolkit/DrinkFluidCompletion"
local drinkRepairAuthorizes = type(DrinkRepair)=="table" and DrinkRepair.authorizes
local drinkRepairAdoptStart = type(DrinkRepair)=="table" and DrinkRepair.adoptStart
local Weights = require "PZSurvivorToolkit/ActionQueueWeights"
local Toolkit = PZSurvivorToolkit
local Adapters = {}
Toolkit.ActionQueueItemEditAdapters = Adapters
local base = ISBaseTimedAction
local transfer, lowlevel, drink = ISInventoryTransferAction, ISTransferAction, ISDrinkFluidAction
local eat = ISEatFoodAction
local empty, fluidWrapper, fluidUtil = ISFluidEmptyAction, ISFluidContainer, ISFluidUtil
local emptyEnabled = type(empty)=="table" and type(fluidWrapper)=="table" and type(fluidUtil)=="table"
local operations=Toolkit.ActionQueueOperations
local mergeDelegate=operations and operations.transferMergeDelegate
local lifecycle = {"new", "begin", "create", "adjustMaxTime", "isValid", "isValidStart", "waitToStart", "start", "update", "stop",
    "perform", "complete", "getDuration", "serverStart", "serverStop", "animEvent", "forceComplete", "forceStop", "forceCancel", "invoke"}
local snapshots, approved, guards, baseHooks, pins = {}, {}, {}, {}, {}
local bindingAccessor, bindingOrigin, bindingMatches = getFilenameOfClosure, Proof and Proof.closure, Proof and Proof.matches
local bindingPairs, bindingType, bindingMeta, bindingEqual = pairs, type, getmetatable, rawequal
local bindingGlobals, bindingRaw, bindingIpairs, bindingParent = _G, rawget, ipairs, ISBaseObject
local baseMethods={}
local ownMethods,ownerSafe,baselineSafe={},{},true
local baseDelegates, sourceFactories, sourceFactoryRefs, factoryRevision = {}, {}, {}, 0
local bindingCapture = Proof and Proof.captureBindings
local bindingNativeMeta = toolkitLuaMetatableMatches
-- These are the own methods in the pinned native files, including helpers called
-- by other methods. Enumerating only surviving callbacks would trust a class
-- whose effect/helper was deleted before this module loaded, or inherited instead.
local requiredOwn={
    [base]={"isValidStart","isValid","isUsingTimeout","update","forceComplete","forceStop","forceCancel",
        "getJobDelta","setJobDelta","resetJobDelta","waitToStart","interruptWaitToStart","start","isStarted","stop",
        "perform","getDuration","create","begin","setCurrentTime","setTime","adjustMaxTime","setActionAnim",
        "setOverrideHandModels","setOverrideHandModelsString","overrideWeaponType","restoreWeaponType","setAnimVariable",
        "addAfter","beginAddingActions","endAddingActions","getDeltaModifiers","new"},
    [transfer]={"isValid","update","doActionAnim","startActionAnim","waitToStart","start","playSourceContainerOpenSound",
        "playSourceContainerCloseSound","playDestContainerOpenSound","playDestContainerCloseSound","getTransferStartSoundName",
        "getTransferCompleteSoundName","playTransferCompleteSound","stopLoopingSound","stop","forceComplete","perform",
        "isAlreadyTransferred","floorHasRoomFor","canDropOnFloor","getNotFullFloorSquare","transferItem","setOnComplete",
        "getTimeDelta","canMergeAction","checkQueueList","setAllowMissingItems","getExtraLogData","new"},
    [lowlevel]={"floorHasRoomFor","canDropOnFloor","getNotFullFloorSquare","GetDropItemOffset","removeItemOnCharacter","transferItem"},
    [drink]={"isValidStart","waitToStart","isValid","update","serverStart","animEvent","start","stop","perform",
        "complete","updateEat","getDuration","new"},
    [eat]={"isValidStart","waitToStart","isValid","update","start","stop","serverStop","perform","complete",
        "getRequiredItem","eat","getDuration","getSecondItem","isEatingRemaining","new"},
}
if emptyEnabled then
    requiredOwn[empty]={"isValid","update","serverStart","animEvent","getDuration","updateEmpty","start","stop","perform","complete","new"}
    requiredOwn[fluidWrapper]={"new","initFromObject","copy","isItem","isResource","getFluidResource","isIsoPanel",
        "resetObject","isValid","getFluidContainer","getOwner","getFluidObject","sync"}
    requiredOwn[fluidUtil]={"validateContainer","doWalkTo","getContainerOwner","getTransferActionTimePerLiter",
        "getMinTransferActionTime","getLuaFluidContainer"}
end
local function ownsRequired(owner,own,methods)
    for _,name in ipairs(requiredOwn[owner]) do
        local callback=own[name]
        if type(callback)~="function" or methods and callback~=methods[name] then return false end
    end
    return true
end
local function unique(methods)
    local seen={}
    for name,callback in pairs(methods) do
        if name~="derive" and type(callback)=="function" then
            if seen[callback] then return false end
            seen[callback]=name
        end
    end
    return true
end
for name,callback in pairs(base) do if type(callback)=="function" then baseMethods[name]=callback end end
baselineSafe=ownsRequired(base,baseMethods) and unique(baseMethods)
local files = {[transfer] = "ISInventoryTransferAction.lua", [lowlevel] = "ISTransferAction.lua", [drink] = "ISDrinkFluidAction.lua", [eat] = "ISEatFoodAction.lua"}
if emptyEnabled then
    files[empty],files[fluidWrapper],files[fluidUtil]="ISFluidEmptyAction.lua","ISFluidContainer.lua","ISFluidUtil.lua"
end
local allowed = {[transfer] = {new=true,isValid=true,start=true,perform=true,stop=true,transferItem=true,checkQueueList=true,getNotFullFloorSquare=true},
    [lowlevel] = {transferItem=true,GetDropItemOffset=true}, [drink] = {start=true}, [eat] = {start=true}}
for owner in pairs(files) do
    local methods,own = {},{}
    for name, callback in pairs(owner) do if type(callback) == "function" then methods[name],own[name] = callback,true end end
    ownerSafe[owner]=ownsRequired(owner,methods) and unique(methods)
    ownMethods[owner]=own
    if owner==transfer or owner==drink or owner==eat or owner==empty then for _, name in ipairs(lifecycle) do methods[name] = owner[name] or false end end
    snapshots[owner], approved[owner], guards[owner] = methods, {}, {}
end
local function finite(value) return type(value)=="number" and value==value and value>-math.huge and value<math.huge end
local function guarded(callback) local ok, result = pcall(callback); return ok and result == true end
local function pinned(path, checksum, mod)
    if not Proof or type(getFilenameOfClosure)~="function" or type(getGameFilesInput)~="function"
        or (mod and type(getModFileReader)~="function") then return false end
    if pins[path]==nil then pins[path]=Proof.matches(path,checksum,mod,true) end
    return pins[path]
end
local function origin(owner,name,callback)
    if type(callback)~="function" then return callback==false end
    if approved[owner][name]==callback then return true end
    if owner==empty and (name=="isValid" or name=="updateEmpty")
        and Proof.closure(callback,"EmptyFluidAction.lua") then
        return type(emptyRepairAuthorizes)=="function" and EmptyRepair.authorizes==emptyRepairAuthorizes
            and Proof.closure(emptyRepairAuthorizes,"EmptyFluidAction.lua")
            and pinned("media/lua/shared/PZSurvivorToolkit/EmptyFluidAction.lua",1033539181,"PZSurvivorToolkit")
            and guarded(function()return emptyRepairAuthorizes(owner,name,callback)end)
    end
    if owner==drink and (name=="isValid" or name=="updateEat")
        and Proof.closure(callback,"DrinkFluidCompletion.lua") then
        return type(drinkRepairAuthorizes)=="function" and DrinkRepair.authorizes==drinkRepairAuthorizes
            and Proof.closure(drinkRepairAuthorizes,"DrinkFluidCompletion.lua")
            and pinned("media/lua/shared/PZSurvivorToolkit/DrinkFluidCompletion.lua",789574824,"PZSurvivorToolkit")
            and guarded(function()return drinkRepairAuthorizes(owner,name,callback)end)
    end
    if owner==drink and name=="isValidStart" and Proof.closure(callback,"DrinkFluidAction.lua") then
        return pinned("media/lua/shared/PZSurvivorToolkit/DrinkFluidAction.lua",3238429308,"PZSurvivorToolkit")
    end
    if owner==transfer and name=="canMergeAction" and Proof.closure(callback,"ActionQueueOperations.lua") then
        if Toolkit.ActionQueueOperations~=operations or type(mergeDelegate)~="function"
            or operations.transferMergeDelegate~=mergeDelegate or not Proof.closure(mergeDelegate,"ActionQueueOperations.lua") then return false end
        local ok,delegate=pcall(mergeDelegate,callback)
        return ok and Proof.closure(delegate,"ISInventoryTransferAction.lua")
    end
    if ownMethods[owner][name] then return Proof.closure(callback,files[owner]) end
    return callback==base[name] and (Proof.closure(callback,"ISBaseTimedAction.lua")
        or baseHooks[name]==callback and Proof.closure(callback,"ActionQueue.lua"))
end

-- Policy calls this only after its source-owned adoption path succeeds. Keep every
-- predecessor guard live, including when another approved wrapper delegates to it.
function Adapters.adoptMethods(owner,previous,replacement,guard)
    if not allowed[owner] or type(previous)~="table" or type(replacement)~="table" or getmetatable(previous) or getmetatable(replacement)
        or type(guard)~="function" or not guarded(guard) then return false end
    local count=0
    for name, callback in pairs(replacement) do
        if not allowed[owner][name] or type(callback)~="function" or snapshots[owner][name]~=previous[name]
            or Proof.own(owner,name)~=callback or not origin(owner,name,previous[name]) then return false end
        count=count+1
    end
    for name in pairs(previous) do if replacement[name]==nil then return false end end
    if count==0 then return false end
    if owner==drink and DrinkRepair then
        if replacement.start==nil or count~=1 or type(drinkRepairAdoptStart)~="function"
            or DrinkRepair.adoptStart~=drinkRepairAdoptStart
            or not guarded(function()return drinkRepairAdoptStart(previous.start,replacement.start,guard)end) then return false end
    end
    for name,callback in pairs(replacement) do snapshots[owner][name],approved[owner][name]=callback,callback end
    guards[owner][#guards[owner]+1]=guard
    return true
end
function Adapters.adoptBase(name,previous,replacement)
    if (name~="begin" and name~="stop") or ISBaseTimedAction~=base or Proof.own(base,name)~=replacement
        or baseMethods[name]~=previous
        or not Proof.closure(previous,"ISBaseTimedAction.lua") or not Proof.closure(replacement,"ActionQueue.lua") then return false end
    for _,owner in ipairs({transfer,drink,eat,empty}) do
        if snapshots[owner][name]==previous and owner[name]==replacement then snapshots[owner][name]=replacement end
    end
    baseDelegates[name]=previous
    baseHooks[name],baseMethods[name]=replacement,replacement
    return true
end
local function unchanged(owner,action)
    if not baselineSafe or ISBaseTimedAction~=base or ISInventoryTransferAction~=transfer or ISTransferAction~=lowlevel
        or ISDrinkFluidAction~=drink or ISEatFoodAction~=eat then return false end
    if owner==empty and (not emptyEnabled or ISFluidEmptyAction~=empty or ISFluidContainer~=fluidWrapper
        or ISFluidUtil~=fluidUtil) then return false end
    -- Kahlua rawget follows metatables. Enumerate own callbacks once per
    -- current owner, never once for every required lifecycle method.
    local currentBase={}
    for name,callback in pairs(base) do if type(callback)=="function" then currentBase[name]=callback end end
    if not ownsRequired(base,currentBase,baseMethods) then return false end
    local policy=Toolkit.ActionQueuePolicy
    if not policy or type(policy.matchesNative)~="function" or not policy.matchesNative(action) then return false end
    for name,callback in pairs(baseMethods) do
        if base[name]~=callback or name~="derive" and not Proof.closure(callback,"ISBaseTimedAction.lua")
            and not (baseHooks[name]==callback and Proof.closure(callback,"ActionQueue.lua")) then return false end
    end
    for _, candidate in ipairs(owner==transfer and {transfer,lowlevel} or owner==empty and {empty,fluidWrapper,fluidUtil} or {owner}) do
        if not ownerSafe[candidate] then return false end
        for _,guard in ipairs(guards[candidate]) do if not guarded(guard) then return false end end
        local currentOwn={}
        for name,callback in pairs(candidate) do
            if type(callback)=="function" then
                if snapshots[candidate][name]~=callback then return false end
                currentOwn[name]=callback
            end
        end
        if not ownsRequired(candidate,currentOwn,snapshots[candidate]) then return false end
        for name,callback in pairs(snapshots[candidate]) do
            if (candidate[name] or false)~=callback or name~="derive" and not origin(candidate,name,callback) then return false end
            if candidate==owner and (action[name] or false)~=callback then
                local bulk=Toolkit.BulkActions
                if name~="stop" or not bulk or not bulk.isGuardedTransfer or not bulk.isGuardedTransfer(action,callback) then return false end
            end
        end
    end
    for name,callback in pairs(action) do
        if type(callback)=="function" and snapshots[owner][name]~=callback then
            local bulk=Toolkit.BulkActions
            local guardedTransfer=owner==transfer and bulk and bulk.isGuardedTransfer
                and bulk.isGuardedTransfer(action,snapshots[owner].stop)
            if not guardedTransfer or (name~="stop" and name~="onCompleteFunc") then return false end
        end
    end
    return true
end
local function pending(action,owner)
    if type(action)~="table" or getmetatable(action)~=owner or action.Type~=owner.Type or action.action or action.started
        or action._isAddingActions or action.transactionId and action.transactionId~=0
        or type(action.toolkitQueueOperation)=="table" and (action.toolkitQueueOperation.toolkitStarted or action.toolkitQueueOperation.toolkitCancelled)
        or not instanceof(action.character,"IsoPlayer") then return false end
    if not pinned("media/lua/shared/TimedActions/ISBaseTimedAction.lua",3104185167) then return false end
    if owner==transfer then
        if not pinned("media/lua/client/TimedActions/ISInventoryTransferAction.lua",3739549534)
            or not pinned("media/lua/shared/TimedActions/ISTransferAction.lua",798240932) then return false end
    elseif owner==empty then
        if not pinned("media/lua/shared/Fluids/ISFluidEmptyAction.lua",4049618573)
            or not pinned("media/lua/shared/Fluids/ISFluidContainer.lua",2954809783)
            or not pinned("media/lua/shared/Fluids/ISFluidUtil.lua",299578700) then return false end
    elseif owner==eat then
        if not pinned("media/lua/shared/TimedActions/ISEatFoodAction.lua",178315973) then return false end
    elseif not pinned("media/lua/shared/TimedActions/ISDrinkFluidAction.lua",3564665289) then return false end
    return unchanged(owner,action)
end
-- Fixed source owners register their immutable factory identity during module
-- initialization. Observation never discovers or invokes a replacement callback
-- just because it shares a filename with another reviewed function.
local sourceRoles = {
    BulkActions={transferBinding="BulkActions.lua"},
    ActionQueueCompat={transferBinding="ActionQueueCompat.lua",transferListenerBinding="ActionQueueCompat.lua",tidyBinding="ActionQueueCompat.lua"},
    ActionQueuePolicy={transferBinding="ActionQueuePolicy.lua"},
    ActionQueueTidyIntent={queueObserverBinding="ActionQueueTidyIntent.lua"},
    ActionQueueCarts={transferBinding="ActionQueueCarts.lua"},
    ActionQueueSettlement={transferListenerBinding="ActionQueueSettlement.lua"},
    FitnessEquipment={transferListenerBinding="FitnessEquipment.lua"},
}
local function bindingOwn(owner,key)
    if bindingType(owner)~="table" then return end
    if bindingMeta(owner)==nil then return bindingRaw(owner,key) end
    local count=0
    for name,value in bindingPairs(owner) do
        count=count+1;if count>128 then return end
        if bindingEqual(name,key) then return value end
    end
end
function Adapters.registerSourceFactory(owner,key,factory)
    if bindingType(owner)~="table" or bindingMeta(owner)~=nil or bindingType(factory)~="function"
        or bindingType(bindingCapture)~="function" or Proof.captureBindings~=bindingCapture
        or getFilenameOfClosure~=bindingAccessor or Proof.closure~=bindingOrigin then return false end
    for module,roles in bindingPairs(sourceRoles) do
        if bindingEqual(bindingOwn(Toolkit,module),owner) and roles[key]
            and bindingEqual(bindingOwn(owner,key),factory) then
            local slot=module.."."..key
            if sourceFactories[slot] then return bindingEqual(sourceFactories[slot].factory,factory) end
            if sourceFactoryRefs[factory] then return false end
            local revision=factoryRevision
            if not bindingOrigin(factory,roles[key]) or revision~=factoryRevision
                or not bindingEqual(bindingOwn(Toolkit,module),owner)
                or bindingMeta(owner)~=nil or not bindingEqual(bindingOwn(owner,key),factory) then return false end
            local record={owner=owner,module=module,key=key,factory=factory}
            sourceFactories[slot],sourceFactoryRefs[factory]=record,record
            factoryRevision=factoryRevision+1
            return true
        end
    end
    return false
end
local function registeredFactory(module,key)
    local record=sourceFactories[module.."."..key]
    if record and bindingMeta(record.owner)==nil and bindingEqual(bindingOwn(Toolkit,module),record.owner)
        and bindingEqual(bindingOwn(record.owner,key),record.factory) then return record.factory,record end
end

local function leaf(item,player)
    if not instanceof(item,"InventoryItem") or instanceof(item,"InventoryContainer") or instanceof(item,"AnimalInventoryItem")
        or instanceof(item,"Radio") or item:getWorldItem() or item:getIsCraftingConsumed() or player:isEquipped(item)
        or item:getEquipParent() or item:getAttachedSlot()>=0 then return false end
    local kind=item:getType()
    return kind~="CandleLit" and kind~="Lantern_HurricaneLit"
end
local function ancestry(container,player)
    local root,seen=player:getInventory(),{}
    while instanceof(container,"ItemContainer") and not seen[container] do
        seen[container]=true
        local kind=container:getType()
        if kind=="floor" or kind=="proximityInv" or kind=="twistInv_corpses" or kind=="TradeUI"
            or not container:isExistYet() or container:getAcceptItemFunction()~=nil or container:getOnlyAcceptCategory()~=nil then return false end
        if container==root then return true end
        local owner=container:getContainingItem()
        if not instanceof(owner,"InventoryContainer") or owner:getInventory()~=container then return false end
        container=owner:getContainer()
    end
    return false
end
local worldStorageTypes={crate=true,shelf=true,shelves=true,metal_shelves=true}
local function method(value,name)return value and type(value[name])=="function" end
-- Only adjacent anchored ordinary storage. isExistYet alone can return true
-- with world sync disabled, even after its parent has left the square.
local function anchoredWorldContainer(container,player)
    if not instanceof(container,"ItemContainer") then return end
    for _,name in ipairs({"getType","getContainingItem","isExistYet","getAcceptItemFunction","getOnlyAcceptCategory",
        "getVehiclePart","getSourceGrid","getParent"})do if not method(container,name) then return end end
    if not worldStorageTypes[container:getType()]
        or container:getContainingItem() or not container:isExistYet()
        or container:getAcceptItemFunction()~=nil or container:getOnlyAcceptCategory()~=nil
        or not method(container,"getVehiclePart") or container:getVehiclePart()
        or not method(container,"getSourceGrid") or type(getClassSimpleName)~="function" then return end
    local parent=container:getParent()
    if not instanceof(parent,"IsoObject") then return end
    local class=getClassSimpleName(parent)
    if class~="IsoObject" and class~="IsoThumpable" then return end
    if class=="IsoThumpable" then
        for _,name in ipairs({"isDoor","isDoorFrame","isWindowN","isWindowW","isBarricaded",
            "isLocked","isLockedByKey","isLockedByPadlock"}) do
            if not method(parent,name) or parent[name](parent) then return end
        end
        if not method(parent,"getLockedByCode") or parent:getLockedByCode()~=0 then return end
    end
    for _,name in ipairs({"getSquare","getContainerCount","getContainerByIndex"})do if not method(parent,name) then return end end
    local square=parent:getSquare()
    if not square or container:getSourceGrid()~=square or not method(square,"getObjects")
        or not square:getObjects():contains(parent) or not instanceof(player,"IsoPlayer") then return end
    local origin=player:getCurrentSquare()
    if not origin or origin:getZ()~=square:getZ() or math.abs(origin:getX()-square:getX())>1
        or math.abs(origin:getY()-square:getY())>1 then return end
    local count=parent:getContainerCount()
    if not finite(count) or count<1 or count%1~=0 then return end
    for i=0,count-1 do if parent:getContainerByIndex(i)==container then return {container} end end
end
-- A world bag has no stable MP ContainerID in B42.21: the packet stores the
-- outer object's index for the inner inventory (-1), not the owner bag's ID.
-- SP can prove the physical owner chain without changing native transfers.
function Adapters.worldContainer(container,player)
    local chain,seen={},{}
    while instanceof(container,"ItemContainer") and not seen[container] do
        seen[container]=true
        chain[#chain+1]=container
        if not method(container,"getContainingItem") then return end
        local owner=container:getContainingItem()
        if not owner then
            if anchoredWorldContainer(container,player) then return chain end
            return
        end
        if isClient() or not instanceof(owner,"InventoryContainer")
            or type(getClassSimpleName)~="function" or getClassSimpleName(owner)~="InventoryContainer" then return end
        for _,name in ipairs({"getType","isExistYet","getAcceptItemFunction","getOnlyAcceptCategory","getVehiclePart","getParent"}) do
            if not method(container,name) then return end
        end
        local kind=container:getType()
        if kind=="floor" or kind=="proximityInv" or kind=="twistInv_corpses" or kind=="TradeUI"
            or not container:isExistYet() or container:getAcceptItemFunction()~=nil
            or container:getOnlyAcceptCategory()~=nil or container:getVehiclePart() or container:getParent() then return end
        for _,name in ipairs({"getID","getInventory","getContainer","getWorldItem","getIsCraftingConsumed",
            "getEquipParent","getAttachedSlot"}) do if not method(owner,name) then return end end
        local id=owner:getID()
        if not finite(id) or id%1~=0 or owner:getInventory()~=container or owner:getWorldItem()
            or owner:getIsCraftingConsumed() or owner:getEquipParent() or owner:getAttachedSlot()>=0
            or not instanceof(player,"IsoPlayer") or player:isEquipped(owner) then return end
        local parent=owner:getContainer()
        if not instanceof(parent,"ItemContainer") or not method(parent,"contains") or not parent:contains(owner)
            or not method(parent,"getItemById") or parent:getItemById(id)~=owner then return end
        container=parent
    end
end
local function coldCookableState(item,player)
    if not instanceof(player,"IsoPlayer") then return false end
    local heat,ambient=item:getHeat(),player:getInventory():getTemperature()
    return finite(heat) and heat>=0 and heat<=1.6 and finite(ambient) and ambient>=0 and ambient<=1.6
        and not item:isFertilized() and not item:getReplaceOnRotten()
        and ItemTag and ItemTag.ALREADY_COOKED~=nil
        and (item:isCooked() or not item:hasTag(ItemTag.ALREADY_COOKED))
end
local function coldEndpoint(container,player)
    if ancestry(container,player) then return true end
    -- Prove the owner chain before calling the native recursive getter. The
    -- outer inventory alone controls Food.updateTemperature, including bags.
    local chain=Adapters.worldContainer(container,player)
    if not chain or not method(container,"getOutermostContainer") then return false end
    local outer=chain[#chain]
    if container:getOutermostContainer()~=outer then return false end
    for _,name in ipairs({"getCustomTemperature","getTemperature","isFridge","isFreezer","isStove",
        "isMicrowave","isTemperatureChanging"}) do if not method(outer,name) then return false end end
    -- Fridge classification also reads sprite flags, not just container type.
    -- These exact ordinary endpoints keep the native ambient fixed at one.
    return outer:getCustomTemperature()==0 and outer:getTemperature()==1
        and outer:isFridge()==false and outer:isFreezer()==false and outer:isStove()==false
        and outer:isMicrowave()==false and outer:isTemperatureChanging()==false
end
function Adapters.worldTransferItem(item,returning,player,source,destination)
    if not instanceof(item,"InventoryItem") or returning and item:isFavorite() then return false end
    if not instanceof(item,"Food") or not item:isCookable() then return true end
    -- The global capacity prefix uses this same proof even when no food edit
    -- belongs to its selected dependency component. Do not admit a hot return
    -- simply because the food happens to be carried at inspection time.
    return coldCookableState(item,player) and (item:getContainer()==source or item:getContainer()==destination)
        and coldEndpoint(source,player) and coldEndpoint(destination,player)
end
local function itemFacts(item)
    local id=item:getID()
    if not finite(id) or id%1~=0 then return end
    local facts={item=item,location=item:getContainer()}
    if not instanceof(facts.location,"ItemContainer") or not facts.location:contains(item)
        or facts.location:getItemById(id)~=item then return end
    local fluid=item:getFluidContainer()
    if fluid then
        if not instanceof(fluid,"FluidContainer") or fluid:getOwner()~=item then return end
        facts.fluid=fluid
    end
    if instanceof(item,"Food") then
        local amount=-item:getHungChange()
        if finite(amount) and amount>0 then facts.foodLower,facts.foodUpper=amount,amount end
    end
    return facts
end
local function singleton(value)
    if type(value)~="table" or getmetatable(value) or value[1]==nil then return false end
    for key in pairs(value) do if key~=1 then return false end end
    return true
end

-- Observation only, for an existing return behind the current action. Starting
-- its shared operation does not start this transfer. Keep the ordinary pending
-- adapter and all runtime permissions unchanged. Generic adopted wrappers need
-- their own pure dependency lease before they can join this final-read seam.
function Adapters.deferredTransferBinding(action,current)
    local function own(owner,key)
        if bindingType(owner)~="table" then return end
        if bindingMeta(owner)==nil then return bindingRaw(owner,key) end
        local count=0
        for name,value in bindingPairs(owner) do
            count=count+1
            if count>128 then return end
            if name==key then return value end
        end
    end
    local function plain(value)return bindingType(value)=="table" and bindingMeta(value)==nil end
    if bindingType(action)~="table" or bindingType(current)~="table" or action==current
        or bindingMeta(action)~=transfer or bindingMeta(bindingGlobals)~=nil
        or bindingType(bindingAccessor)~="function" or getFilenameOfClosure~=bindingAccessor
        or not Proof or Proof.closure~=bindingOrigin or Proof.matches~=bindingMatches or bindingType(bindingOrigin)~="function"
        or not baselineSafe or not ownerSafe[transfer] or not ownerSafe[lowlevel]
        or bindingType(bindingCapture)~="function" or Proof.captureBindings~=bindingCapture then return end
    local revision=factoryRevision
    -- Only successful native-to-Toolkit adoptions have private delegates here.
    -- Their source ancestry does not grant lifecycle or native-outcome authority.
    for name,callback in bindingPairs(baseHooks) do
        if not baseDelegates[name] or baseMethods[name]~=callback then return end
    end
    local token,actor,native=own(current,"toolkitQueueOperation"),own(current,"character"),own(current,"action")
    if not plain(token) or own(token,"toolkitCancelled") or own(token,"toolkitStarted")~=true
        -- Native checkpoint ownership proves the active step; reading does not
        -- set the transfer-specific Lua `started` flag in stock B42.
        or native==nil
        or own(action,"toolkitQueueOperation")~=token or own(action,"character")~=actor
        or own(action,"action")~=nil or own(action,"started") or own(action,"_isAddingActions")
        or own(action,"transactionId")~=nil and own(action,"transactionId")~=0
        or own(action,"allowMissingItems")~=true then return end
    local queueClass=ISTimedActionQueue
    local queueMap=bindingType(queueClass)=="table" and own(queueClass,"queues")
    local queue=bindingType(queueMap)=="table" and own(queueMap,actor)
    local list=bindingType(queue)=="table" and own(queue,"queue")
    if bindingType(queue)~="table" or bindingMeta(queue)~=queueClass or not plain(list)
        or own(queue,"character")~=actor or own(queue,"current")~=current
        or list[1]~=current or #list<2 or #list>32 or own(queue,"toolkitCancel") or own(queue,"toolkitGroupCancel")
        or own(queue,"toolkitResume") or own(queue,"toolkitOutcomeWait") or own(queue,"toolkitStopIntent") then return end
    local found,ended=false,false
    for index=1,#list do
        local member=list[index]
        if bindingType(member)~="table" then return end
        if own(member,"toolkitQueueOperation")==token then
            if ended or own(member,"character")~=actor then return end
            if member==action then if found then return end;found=true end
        else ended=true end
    end
    for key in bindingPairs(list) do if bindingType(key)~="number" or key%1~=0 or key<1 or key>#list then return end end
    if not found then return end
    local groups=own(action,"queueList")
    if not singleton(groups) or not plain(groups[1]) or not singleton(own(groups[1],"items")) then return end
    local group,items=groups[1],own(groups[1],"items")
    local item=own(action,"item")
    if items[1]~=item or own(action,"srcContainer")==own(action,"destContainer")
        or not finite(own(action,"maxTime")) or not finite(group.time) or group.time~=own(action,"maxTime") then return end
    for key in bindingPairs(group) do if key~="items" and key~="time" and key~="type" then return end end
    for _,key in ipairs({"onStartFunc","onCancelFunc","onFailFunc","additionalTest","retriggerLastAction"}) do
        if own(action,key) then return end
    end
    -- Capture before file/metadata/member getters. Every table below has a fixed
    -- role; no item/container state, metatable callbacks or recursive object
    -- graph is read by the returned validator. Kahlua rawget is not a raw read.
    local records={}
    local function capture(owner)
        local fields,count={},0
        -- Native class/action records fit well below this existing inspection
        -- ceiling; oversized extension tables stay outside the narrow contract.
        for key,value in bindingPairs(owner) do
            count=count+1
            if count>128 then return false end
            fields[key]=value
        end
        local parent=bindingMeta(owner)
        if parent~=nil and (bindingType(bindingNativeMeta)~="function"or not bindingNativeMeta(owner,parent))then return false end
        records[#records+1]={owner=owner,fields=fields,count=count,meta=parent}
        return true
    end
    local function inherits(owner,parent)
        local meta=bindingMeta(owner)
        if meta==parent then return own(parent,"__index")==parent end
        -- Standard Lua fixtures encode table inheritance through a plain proxy;
        -- stock Kahlua uses the parent table directly.
        if not plain(meta) or own(meta,"__index")~=parent then return false end
        for key in bindingPairs(meta) do if key~="__index" then return false end end
        return capture(meta)
    end
    if bindingType(bindingParent)~="table" or bindingMeta(bindingParent)~=nil
        or not inherits(base,bindingParent) or not inherits(lowlevel,bindingParent)
        or not inherits(transfer,base) or not inherits(queueClass,bindingParent)
        or own(base,"__index")~=base or own(transfer,"__index")~=transfer
        or own(queueClass,"__index")~=queueClass then return end
    for _,owner in ipairs({Proof,Adapters,bindingParent,base,transfer,lowlevel,queueClass,operations,action,current,token,queue,list,groups,group,items}) do
        if bindingType(owner)~="table" then return end
        if not capture(owner) then return end
    end
    for _,member in ipairs(list) do if member~=action and member~=current and not capture(member) then return end end
    for _,owner in ipairs({baseHooks,baseDelegates,guards[transfer],guards[lowlevel],sourceFactories,sourceFactoryRefs}) do
        if not capture(owner) then return end
    end
    local factorySpecs,byOwner,moduleKeys,seenModules={},{},{},{}
    for _,record in bindingPairs(sourceFactories) do
        local specification=byOwner[record.owner]
        if not specification then
            specification={owner=record.owner,keys={}}
            byOwner[record.owner]=specification;factorySpecs[#factorySpecs+1]=specification
        end
        specification.keys[#specification.keys+1]=record.key
        if not seenModules[record.module] then seenModules[record.module]=true;moduleKeys[#moduleKeys+1]=record.module end
    end
    if #moduleKeys>0 then factorySpecs[#factorySpecs+1]={owner=Toolkit,keys=moduleKeys} end
    factorySpecs[#factorySpecs+1]={owner=Proof,keys={"captureBindings","closure"}}
    factorySpecs[#factorySpecs+1]={owner=bindingGlobals,keys={"getFilenameOfClosure","toolkitLuaMetatableMatches"}}
    local factoryWatch=bindingCapture(factorySpecs)
    if not factoryWatch then return end
    local generation=own(queue,"toolkitOperationGeneration")
    local function unchanged()
        if bindingMeta(bindingGlobals)~=nil or not bindingEqual(own(bindingGlobals,"PZSurvivorToolkit"),Toolkit)
            or not bindingEqual(own(Toolkit,"ActionQueueItemEditAdapters"),Adapters)
            or not bindingEqual(own(Toolkit,"ActionQueueOperations"),operations)
            or not bindingEqual(own(bindingGlobals,"ISBaseTimedAction"),base)
            or not bindingEqual(own(bindingGlobals,"ISInventoryTransferAction"),transfer)
            or not bindingEqual(own(bindingGlobals,"ISTransferAction"),lowlevel)
            or not bindingEqual(own(bindingGlobals,"ISBaseObject"),bindingParent)
            or not bindingEqual(own(bindingGlobals,"ISTimedActionQueue"),queueClass)
            or not bindingEqual(own(queueClass,"queues"),queueMap) or not bindingEqual(own(queueMap,actor),queue)
            or not bindingEqual(own(bindingGlobals,"getFilenameOfClosure"),bindingAccessor)
            or not bindingEqual(own(bindingGlobals,"toolkitLuaMetatableMatches"),bindingNativeMeta)
            or not bindingEqual(own(queue,"toolkitOperationGeneration"),generation)
            or factoryRevision~=revision or not factoryWatch() then return false end
        for _,record in bindingIpairs(records) do
            if not bindingEqual(bindingMeta(record.owner),record.meta)
                or record.meta~=nil and not bindingNativeMeta(record.owner,record.meta) then return false end
            local count=0
            for key,value in bindingPairs(record.owner) do
                count=count+1
                if count>record.count or not bindingEqual(record.fields[key],value) then return false end
            end
            if count~=record.count then return false end
        end
        return true
    end
    local leases,sourceChanged={},false
    local function trustedFactory(factory)
        local record=sourceFactoryRefs[factory]
        return not sourceChanged and record~=nil and bindingEqual(registeredFactory(record.module,record.key),factory)
            and factoryWatch() and factoryRevision==revision
    end
    local compatFactory=registeredFactory("ActionQueueCompat","transferBinding")
    local policyFactory=registeredFactory("ActionQueuePolicy","transferBinding")
    local cartsFactory=registeredFactory("ActionQueueCarts","transferBinding")
    local function prepare(factory,guard)
        if not factory or not trustedFactory(factory) then return end
        local ok,lease,description=pcall(factory,guard,action,trustedFactory)
        if not unchanged() then sourceChanged=true;return end
        if not ok or bindingType(lease)~="function" then return end
        leases[#leases+1]=lease
        return lease,description
    end
    local preparedGuards={}
    for _,owner in ipairs({transfer,lowlevel}) do
        if #guards[owner]>32 then return end
        for _,guard in ipairs(guards[owner]) do
            if not preparedGuards[guard] then
                -- Filename chooses the owner to ask, never authorizes a guard.
                -- The owner's immutable registration must recognize its exact
                -- private guard; no arbitrary guard is executed to classify it.
                local factory
                if bindingOrigin(guard,"ActionQueueCompat.lua") then factory=compatFactory
                elseif bindingOrigin(guard,"ActionQueuePolicy.lua") then factory=policyFactory
                elseif bindingOrigin(guard,"ActionQueueCarts.lua") then factory=cartsFactory end
                if not unchanged() or not prepare(factory,guard) then return end
                -- Several audited wrappers share one guard/dependency set. Its
                -- first lease stays live through every later preparation and is
                -- checked after the same native facts; recapturing adds no proof.
                preparedGuards[guard]=true
            end
        end
    end
    local _,instance=prepare(compatFactory,false)
    if instance~=nil and (not plain(instance) or instance.completeWasAbsent~=true) then return end
    local function effective(name)
        local value=own(action,name)
        if value==nil then return transfer[name] end
        return value
    end
    local bulk
    local guard=own(action,"toolkitTransferGuard")
    if guard~=nil then
        local factory=registeredFactory("BulkActions","transferBinding")
        if not factory or not trustedFactory(factory) or not plain(guard)
            or not pinned("media/lua/client/PZSurvivorToolkit/BulkActions.lua",3109997898,"PZSurvivorToolkit") then return end
        local ok,lease,description=pcall(factory,action,own(guard,"original"),own(guard,"stop"))
        if not ok or bindingType(lease)~="function" or not plain(description) or not unchanged() then return end
        leases[#leases+1]=lease;bulk=description
    end
    local methodOverrides={}
    local performed=effective("perform")
    if instance and instance.wrappedPerform then
        if not bindingEqual(performed,instance.wrappedPerform) or not bindingEqual(instance.perform,snapshots[transfer].perform) then return end
        methodOverrides.perform=performed
    elseif not bindingEqual(performed,snapshots[transfer].perform) then return end
    local stopped=effective("stop")
    local usedInstance,usedBulk=false,false
    for _=1,2 do
        if bindingEqual(stopped,snapshots[transfer].stop) then break end
        if instance and not usedInstance and bindingEqual(stopped,instance.wrappedStop) then
            stopped=instance.stop;usedInstance=true
        elseif bulk and not usedBulk and bindingEqual(stopped,bulk.wrappedStop) then
            stopped=bulk.stop;usedBulk=true
        else return end
    end
    if not bindingEqual(stopped,snapshots[transfer].stop) or instance and instance.wrappedStop and not usedInstance
        or bulk and not usedBulk then return end
    methodOverrides.stop=effective("stop")
    if own(action,"onCompleteFunc") then
        if not bulk or not bindingEqual(own(action,"onCompleteFunc"),bulk.onComplete) then return end
        methodOverrides.onCompleteFunc=bulk.onComplete
        methodOverrides.toolkitQueueSafeOnComplete=bulk.onComplete
    elseif bulk then return end
    if not unchanged() or getFilenameOfClosure~=bindingAccessor then return end
    if not pinned("media/lua/shared/TimedActions/ISBaseTimedAction.lua",3104185167)
        or not pinned("media/lua/client/TimedActions/ISInventoryTransferAction.lua",3739549534)
        or not pinned("media/lua/shared/TimedActions/ISTransferAction.lua",798240932) then return end
    for name,callback in bindingPairs(baseMethods) do
        if own(base,name)~=callback then return end
        if name~="derive" and not bindingOrigin(callback,"ISBaseTimedAction.lua") then
            if not bindingEqual(baseHooks[name],callback) or not bindingOrigin(callback,"ActionQueue.lua")
                or not bindingOrigin(baseDelegates[name],"ISBaseTimedAction.lua") then return end
        end
    end
    for _,owner in ipairs({transfer,lowlevel}) do
        local currentOwn={}
        for name,callback in bindingPairs(owner) do
            if bindingType(callback)=="function" then
                if snapshots[owner][name]~=callback then return end
                currentOwn[name]=callback
            end
        end
        if not ownsRequired(owner,currentOwn,snapshots[owner]) then return end
        for name,callback in bindingPairs(snapshots[owner]) do
            if (owner[name] or false)~=callback then return end
            if owner==transfer and (action[name] or false)~=callback and not bindingEqual(methodOverrides[name],action[name]) then return end
            if bindingType(callback)=="function" and name~="derive" and not bindingEqual(approved[owner][name],callback) then
                if owner==transfer and name=="canMergeAction" and bindingOrigin(callback,"ActionQueueOperations.lua") then
                    if own(operations,"transferMergeDelegate")~=mergeDelegate or bindingType(mergeDelegate)~="function"
                        or not bindingOrigin(mergeDelegate,"ActionQueueOperations.lua") then return end
                    local ok,delegate=pcall(mergeDelegate,callback)
                    if not ok or not bindingOrigin(delegate,"ISInventoryTransferAction.lua") then return end
                elseif not bindingOrigin(callback,ownMethods[owner][name] and files[owner] or "ISBaseTimedAction.lua") then
                    if not bindingEqual(baseHooks[name],callback) or not bindingOrigin(callback,"ActionQueue.lua")
                        or not bindingOrigin(baseDelegates[name],"ISBaseTimedAction.lua") then return end
                end
            end
        end
    end
    for name,value in bindingPairs(action) do
        if bindingType(value)=="function" and snapshots[transfer][name]~=value and not bindingEqual(methodOverrides[name],value) then return end
    end
    if action.Type~=transfer.Type or not instanceof(actor,"IsoPlayer") or not instanceof(item,"InventoryItem")
        or not instanceof(action.srcContainer,"ItemContainer") or not instanceof(action.destContainer,"ItemContainer") then return end
    local id,fullType=item:getID(),item:getFullType()
    if not finite(id) or id%1~=0 or bindingType(fullType)~="string" or fullType=="" or group.type~=fullType
        or not unchanged() then return end
    local used=false
    return function(facts)
        if used then return false end
        used=true
        if not unchanged() then return false end
        for _,lease in bindingIpairs(leases) do if not lease(facts) then return false end end
        return unchanged()
    end
end
Adapters.weightInspectionSafe=Weights.factoryFree
-- Host item transactions preserve queue member IDs while authority replication
-- can replace the carried Java instance. This proves binding only: callers still
-- own all source, pending, effect and capacity checks. Never rewrite native lists.
function Adapters.matchesTransferMember(action,member)
    local item=action and action.item
    if not instanceof(item,"InventoryItem") or not instanceof(member,"InventoryItem") then return false end
    if member==item then return true end
    if not isClient() or not action.character or type(action.character.getInventory)~="function"
        or type(member.getContainer)~="function" or type(member.getID)~="function"
        or type(member.getFullType)~="function" then return false end
    local inventory=action.character:getInventory()
    return inventory~=nil and action.srcContainer==inventory and member:getContainer()==nil
        and member:getID()==item:getID() and member:getFullType()==item:getFullType()
        and item:getContainer()==inventory and inventory:getItemById(item:getID())==item
end
function Adapters.transfer(action)
    if not pending(action,transfer) or not leaf(action.item,action.character) or action.srcContainer==action.destContainer
        then return end
    local sourceCarried,destinationCarried=ancestry(action.srcContainer,action.character),ancestry(action.destContainer,action.character)
    if not sourceCarried and not destinationCarried then return end
    if not sourceCarried and not Adapters.worldContainer(action.srcContainer,action.character)
        or not destinationCarried and not Adapters.worldContainer(action.destContainer,action.character) then return end
    if (not sourceCarried or not destinationCarried) and not Adapters.worldTransferItem(action.item,not destinationCarried,action.character,action.srcContainer,action.destContainer) then return end
    local provenWeight
    if not Weights.factoryFree(action.item) then
        provenWeight=Weights.unequipped(action.item)
        if not finite(provenWeight) or provenWeight<0 then return end
    end
    local bag=action.destContainer:getContainingItem()
    if bag then
        local maximum,weight=bag:getMaxItemSize(),provenWeight or Weights.unequipped(action.item)
        if not finite(maximum) or maximum<0 or not finite(weight) or weight<0 or maximum>0 and weight>maximum then return end
    end
    local groups=action.queueList
    if not singleton(groups) or type(groups[1])~="table" or getmetatable(groups[1])
        or not singleton(groups[1].items) or not Adapters.matchesTransferMember(action,groups[1].items[1])
        or groups[1].type~=action.item:getFullType() or not finite(groups[1].time) or groups[1].time~=action.maxTime
        or action.allowMissingItems~=nil and type(action.allowMissingItems)~="boolean" then return end
    for key in pairs(groups[1]) do if key~="items" and key~="time" and key~="type" then return end end
    local facts=itemFacts(action.item)
    if not facts or facts.location~=action.srcContainer and facts.location~=action.destContainer then return end
    -- Ancestry owner mutations remain linked by Policy.transferResources.containerOwners.
    local requires={{field="location",oneOf={action.srcContainer,action.destContainer}}}
    if facts.foodLower then requires[#requires+1]={field="foodLower",above=0} end
    return {version=1,complete=true,capacity="external",resources={{domain="item",key=action.item:getID(),facts=facts,
        requires=requires,effects={{field="location",set=action.destContainer}}}}}
end
local function fullness(player)
    local damage=player:getBodyDamage()
    local timer,standard=damage:getHealthFromFoodTimer(),damage:getStandardHealthFromFoodTime()
    if not finite(timer) or timer>11000 or not finite(standard) or standard<=0 then return end
    -- Native decay can overshoot zero and leave a small negative timer.
    return {domain="actor",key=player,facts={foodTimerUpper=math.max(0,timer)},
        requires={{field="foodTimerUpper",max=2*standard}},effects={}}
end
local zeroProperties={"getFatigueChange","getHungerChange","getStressChange","getUnhappyChange","getCalories","getCarbohydrates",
    "getLipids","getProteins","getAlcohol","getPoison","getFluReduction","getPainReduction","getEnduranceChange","getFoodSicknessChange"}
local function cleanWater(fluid)
    if not instanceof(fluid,"FluidContainer") or not Fluid or not Fluid.Water or not fluid:isPureFluid(Fluid.Water)
        or fluid:isTainted() or fluid:isPoisonous() then return false end
    local properties=fluid:getProperties()
    for _,name in ipairs(zeroProperties) do if properties[name](properties)~=0 then return false end end
    local thirst=properties:getThirstChange()
    return finite(thirst) and thirst<=0
end
function Adapters.fullnessNeutralDrink(action)
    -- An already-running clean-water action changes no fullness. Other fluid
    -- consumption must join the actor dependency component even without a
    -- supported edit contract of its own.
    return type(action)=="table" and getmetatable(action)==drink and action.useUtensil==false
        and pinned("media/lua/shared/TimedActions/ISDrinkFluidAction.lua",3564665289)
        and pinned("media/lua/shared/TimedActions/ISBaseTimedAction.lua",3104185167)
        and unchanged(drink,action) and cleanWater(action.fluidContainer)
end
function Adapters.drink(action)
    -- A draining native update can otherwise invalidate itself and reset the
    -- entire tail. Promise a local effect only with the owned completion guard.
    if type(drinkRepairAuthorizes)~="function" or DrinkRepair.authorizes~=drinkRepairAuthorizes
        or not guarded(function()return drinkRepairAuthorizes(drink,"isValid",drink.isValid)
            and drinkRepairAuthorizes(drink,"updateEat",drink.updateEat)end)
        or not instanceof(action and action.item,"ComboItem") then return end
    if not pending(action,drink) or not finite(action.maxTime) or action.maxTime<=0
        or action.useUtensil~=false or not leaf(action.item,action.character)
        or not ancestry(action.item:getContainer(),action.character) or not Fluid or not Fluid.Water then return end
    local facts=itemFacts(action.item)
    local fluid=action.fluidContainer
    if not facts or facts.fluid~=fluid or not cleanWater(fluid) then return end
    local amount,capacity,ratio=fluid:getAmount(),fluid:getCapacity(),fluid:getFilledRatio()
    if not finite(amount) or not finite(capacity) or not finite(ratio) or capacity<=0 or amount<=0 or amount>capacity
        or ratio<=0 or ratio>1 or math.abs(amount/capacity-ratio)>0.000001 then return end
    for _,field in ipairs({"percentage","startRatio","endRatio","targetConsumedRatio","consumedRatio"}) do
        if not finite(action[field]) or action[field]<0 or action[field]>1 then return end
    end
    if action.percentage<=0 or action.startRatio<=0 or action.consumedRatio~=0 or action.endRatio>ratio or ratio>action.startRatio
        or action.endRatio~=action.startRatio*(1-action.percentage)
        or action.targetConsumedRatio~=action.startRatio-action.endRatio then return end
    local resources={{domain="item",key=action.item:getID(),facts=facts,
        requires={{field="location",equal=action.character:getInventory()},{field="fluid",equal=fluid}},effects={}}}
    local effects
    if isClient() then effects={{field="amountLower",set=0},{field="amountUpper",scale=1-action.percentage}}
    else
        local endpoint=capacity*action.endRatio
        -- Native FluidContainer removes a fluid instance below 1e-4. Do not
        -- promise nonempty near that boundary, including the ratio/float
        -- uncertainty already accepted by the amount/filled-ratio shape check.
        local pruningBoundary=0.0001+capacity*0.000001
        local lower=(endpoint<=pruningBoundary or amount<=pruningBoundary)
            and {field="amountLower",set=0} or {field="amountLower",cap=endpoint}
        effects={lower,{field="amountUpper",cap=endpoint}}
    end
    resources[#resources+1]={domain="fluid",key=fluid,facts={amountLower=amount,amountUpper=amount},
        requires={{field="amountLower",above=0}},effects=effects,bounds={amountLower={min=0,max=capacity},amountUpper={min=0,max=capacity}}}
    if Proof.closure(drink.isValidStart,"ISDrinkFluidAction.lua") then
        local actor=fullness(action.character)
        if not actor then return end
        resources[#resources+1]=actor
    end
    return {version=1,complete=true,capacity="external",resources=resources}
end

function Adapters.emptyFluid(action)
    -- Native self-pruning can abort the whole tail. A complete local effect
    -- requires the owned active-empty completion repair, even before it starts.
    if not emptyEnabled or type(emptyRepairAuthorizes)~="function" or EmptyRepair.authorizes~=emptyRepairAuthorizes
        or Proof.own(empty,"__index")~=empty or Proof.own(fluidWrapper,"__index")~=fluidWrapper
        or not guarded(function()return emptyRepairAuthorizes(empty,"isValid",empty.isValid)
            and emptyRepairAuthorizes(empty,"updateEmpty",empty.updateEmpty)end)
        or not pending(action,empty) then return end
    local wrapper=action.container
    if type(wrapper)~="table" or getmetatable(wrapper)~=fluidWrapper or Proof.own(fluidWrapper,"__index")~=fluidWrapper
        or wrapper.Type~=fluidWrapper.Type
        or wrapper.isFluidResource~=false or wrapper.fluidResource~=nil
        or wrapper.isInventoryItem~=true or wrapper.isoPanel~=false then return end
    for _,value in pairs(wrapper) do if type(value)=="function" then return end end
    for name,callback in pairs(snapshots[fluidWrapper]) do if wrapper[name]~=callback then return end end
    local fluid=wrapper.fluidContainer
    if not instanceof(fluid,"FluidContainer") or action.containerObject~=fluid or not cleanWater(fluid)
        or not fluid:canPlayerEmpty() then return end
    local item=fluid:getOwner()
    if not instanceof(item,"ComboItem") or not leaf(item,action.character)
        or not ancestry(item:getContainer(),action.character) or not Weights.factoryFree(item) then return end
    local facts=itemFacts(item)
    if not facts or facts.fluid~=fluid then return end
    local amount,capacity,ratio,rate=fluid:getAmount(),fluid:getCapacity(),fluid:getFilledRatio(),fluid:getTransferRate()
    if not finite(amount) or not finite(capacity) or not finite(ratio) or not finite(rate)
        or amount<=0 or capacity<=0 or amount>capacity or ratio<=0 or ratio>1 or rate<0
        or math.abs(amount/capacity-ratio)>0.000001 or action.amount~=amount then return end
    -- Inspection never executes timing helpers. Native construction owns the
    -- duration, which this edit leaves unchanged; the resource bound depends
    -- on captured amount, not speed. Invalid/unbounded timing stays protected.
    if not finite(action.maxTime) or action.maxTime<=0 then return end
    -- updateEmpty may raise a previously reduced amount back towards the
    -- constructor's capture. Its peak stays within this initial full weight;
    -- the external capacity gate must never spend the eventual release.
    return {version=1,complete=true,capacity="external",resources={
        {domain="item",key=item:getID(),facts=facts,
            requires={{field="location",oneOf={facts.location,action.character:getInventory()}},
                {field="fluid",equal=fluid}},effects={}},
        {domain="fluid",key=fluid,facts={amountLower=amount,amountUpper=amount},
            requires={{field="amountLower",above=0}},
            effects={{field="amountLower",set=0},{field="amountUpper",set=0}},
            bounds={amountLower={min=0,max=capacity},amountUpper={min=0,max=capacity}}}}}
end

local function partialReplacement(item,script)
    -- Even without creating the empty container, native partial eating uses its
    -- script weight. Reviewed evolved extras use the shared pure view; every
    -- retained portion must still prove that no replacement is created.
    local fullType=item:getReplaceOnUseFullType()
    if type(fullType)~="string" or fullType=="" or not ScriptManager or not ScriptManager.instance then return false end
    local output=ScriptManager.instance:getItem(fullType)
    if not output then return false end
    local emptyWeight=output:getActualWeight()
    if item:haveExtraItems() then return Weights.extraFood(item)~=nil end
    if item:isCustomWeight() then
        -- Without extras, Food.getActualWeight uses InventoryItem.actualWeight.
        -- Native partial Eat only writes the separate weight field. Keep both
        -- observed weights finite and above the empty shell's native weight.
        local weight,actual=item:getWeight(),item:getActualWeight()
        return finite(weight) and finite(actual) and finite(emptyWeight)
            and emptyWeight>=0 and emptyWeight<=weight and emptyWeight<=actual
    end
    local hunger,weight=script:getHungerChange(),script:getActualWeight()
    return finite(hunger) and hunger<0 and finite(weight) and finite(emptyWeight)
        and emptyWeight>=0 and emptyWeight<=weight
end


-- Read authored component scripts without constructing a temporary item. In
-- particular getInitialAmount may draw RNG and is not an emptiness predicate.
local function emptyFluidOutput(script)
    if not script:hasComponents() then return true end
    if not ComponentType or not ComponentType.FluidContainer
        or not method(script,"getComponentScripts") or not method(script,"getComponentScriptFor") then return false end
    local components=script:getComponentScripts()
    if not method(components,"size") or not method(components,"get") or components:size()~=1 then return false end
    local fluid=components:get(0)
    if not fluid or type(getClassSimpleName)~="function" or getClassSimpleName(fluid)~="FluidContainerScript"
        or script:getComponentScriptFor(ComponentType.FluidContainer)~=fluid
        or not method(fluid,"getInitialFluids") or not method(fluid,"getCapacity") then return false end
    local initial=fluid:getInitialFluids()
    if initial~=nil and (not method(initial,"size") or initial:size()~=0) then return false end
    local capacity=fluid:getCapacity()
    return finite(capacity) and capacity>0
end

-- Full consumption allocates a new native item before removing the original.
-- Prove a plain or empty-fluid factory output without instantiating it.
local function fullReplacement(action,item,script)
    if action.percentage~=1 or not finite(action.maxTime) or action.maxTime<=0
        or item:getContainer()~=action.character:getInventory() or action.container~=action.character:getInventory()
        or type(getClassSimpleName)~="function" or getClassSimpleName(item)~="Food"
        or item:haveExtraItems() or item:isCustomWeight() or item:isCookable() then return end
    local kind=item:getReplaceOnUseFullType()
    if type(kind)~="string" or not kind:match("^[%w_]+%.[%w_]+$")
        or not ScriptManager or not ScriptManager.instance then return end
    local output=ScriptManager.instance:getItem(kind)
    if not output then return end
    for _,value in ipairs({script,output}) do
        for _,name in ipairs({"getItemType","getLuaCreate","getItemConfig","getItemConfigKey","hasComponents",
            "getCount","getObsolete","getActualWeight","getReplaceOnUse","getReplaceOnDeplete"}) do
            if not method(value,name) then return end
        end
        if value:getLuaCreate() or value:getItemConfig() or value:getItemConfigKey()
            or value:getCount()~=1 or value:getObsolete()
            or value:getReplaceOnDeplete() then return end
    end
    if script:hasComponents() or not emptyFluidOutput(output) then return end
    if tostring(script:getItemType())~="base:food" or tostring(output:getItemType())~="base:normal"
        or not item:getReplaceOnUse() or script:getReplaceOnUse()~=item:getReplaceOnUse()
        or output:getReplaceOnUse() then return end
    local sourceWeight,outputWeight=item:getActualWeight(),output:getActualWeight()
    if not finite(sourceWeight) or not finite(outputWeight) or outputWeight<0 or outputWeight>sourceWeight then return end
    return kind
end

function Adapters.food(action)
    if not pending(action,eat) or not instanceof(action.container,"ItemContainer")
        or action.carLighter or action.openFlame or action.fromRelaunch or not leaf(action.item,action.character)
        or not instanceof(action.item,"Food") then return end
    local item=action.item
    if not ancestry(item:getContainer(),action.character)
        and not Adapters.worldContainer(item:getContainer(),action.character) then return end
    -- Use the constructor's captured reference, never a fresh inventory search.
    -- Native getSecondItem/start select only one of the two remembered utensils.
    local kind=item:getEatType()
    local utensil
    if kind=="2handbowl" then utensil=action.spoon
    elseif kind=="Can" or kind=="Candrink" or kind=="2hand" or kind=="Plate" then utensil=action.fork or action.spoon end
    if action.useUtensil~=(utensil~=nil) then return end
    local utensilFacts
    if utensil~=nil then
        if not instanceof(utensil,"HandWeapon") or not leaf(utensil,action.character) or utensil:isBroken()
            or not ancestry(utensil:getContainer(),action.character) then return end
        utensilFacts=itemFacts(utensil)
        if not utensilFacts then return end
    end
    local script=item:getScriptItem()
    local cookedOutputs=item:getReplaceOnCooked()
    local replacement=script and (script:getReplaceOnUse() or item:getReplaceOnUse())
    local fullOutput=script and replacement and fullReplacement(action,item,script)
    if not script or script:isCantEat() or script:getOpeningRecipe() or script:getOnBreak()
        or script:getReplaceOnDeplete() or item:haveExtraItems() and not replacement
        or replacement and not fullOutput and not partialReplacement(item,script)
        or item:getOnEat() or item:getOnCooked() or item:getReplaceOnRotten()
        or cookedOutputs and not cookedOutputs:isEmpty() and not item:isCookable()
        or item:getRequireInHandOrInventory() or item:getCustomMenuOption()
        or item:hasTag(ItemTag.SMOKABLE) or not item:isDisappearOnUse() or item:isKeepOnDeplete()
        or item:getUses()~=1 or item:getFluidContainer() or item:isTainted() or item:getPoisonPower()~=0
        or item:isAlcoholic() or item:getReduceInfectionPower()~=0 or item:isBurnt() or item:isRotten()
        or item:isbDangerousUncooked() and not item:isCooked() then return end
    if item:isCookable() then
        -- Cold food stays below the native cooking/replacement gate throughout
        -- carried and proven constant-cold ordinary world endpoint transfers.
        if not coldCookableState(item,action.character) or not coldEndpoint(item:getContainer(),action.character) then return end
    end
    local facts=itemFacts(item)
    local base=-item:getBaseHunger()
    local portion=action.percentage
    if not facts or not facts.foodLower or not finite(base) or base<=0 or facts.foodUpper>base+0.000001
        or not finite(portion) or portion<=0 or portion>1 then return end
    local actor=fullness(action.character)
    if not actor then return end
    local debit=base*portion
    -- Java float division/multiplication and the strict native .01 tail test
    -- are enclosed, not rounded into a promise that an item survives.
    local margin=0.00001*math.max(1,base)
    local effects={{field="foodLower",deplete={amount=debit+margin,minimum=0.01+margin}},
        {field="foodUpper",deplete={amount=math.max(0,debit-margin),minimum=0.01-margin}}}
    -- Food timers only grow at minimum hunger. Ignoring that condition and
    -- decay is conservative; cooked food has a 1.3 multiplier and doubles
    -- the timer bonus. The extra .01 covers the native final-tail rounding.
    local multiplier=item:isCooked() and 33800 or 13000
    actor.effects={{field="foodTimerUpper",delta=multiplier*(debit+0.01+margin)+1},{field="foodTimerUpper",cap=11000}}
    -- Partial replacement food must survive every proposed step. Guaranteed
    -- full consumption instead proves the bounded output and removes all food.
    -- Keep the native .01 tail and float slack for the surviving-food branch.
    local minimum=replacement and not fullOutput and debit+0.01+2*margin or 0
    if fullOutput then effects={{field="foodLower",set=0},{field="foodUpper",set=0}} end
    local resources={
        {domain="item",key=item:getID(),facts=facts,
            requires={{field="location",equal=action.character:getInventory()},{field="foodLower",above=minimum}},effects=effects,
            bounds={foodLower={min=0},foodUpper={min=0}}},actor}
    if utensil then
        -- Native Eat receives a boolean: it neither consumes nor equips cutlery.
        -- Keep the exact selected tool reachable; a bag/root transfer can commute
        -- without changing the captured duration or mood benefit.
        resources[#resources+1]={domain="item",key=utensil:getID(),facts=utensilFacts,
            requires={{field="location",oneOf={utensilFacts.location,action.character:getInventory()}}},effects={}}
    end
    return {version=1,complete=true,capacity="external",resources=resources},fullOutput
end
for module,roles in bindingPairs(sourceRoles) do
    local owner=bindingOwn(Toolkit,module)
    if bindingType(owner)=="table" then
        for key in bindingPairs(roles) do Adapters.registerSourceFactory(owner,key,bindingOwn(owner,key)) end
    end
end
return Adapters
