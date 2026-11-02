if not getActivatedMods or not getActivatedMods():contains("SaucedCarts") then return end
require "SaucedCarts/TimedActions/ISCartTransferAction"
require "TimedActions/ISDropWorldItemAction"

local Toolkit = PZSurvivorToolkit
local Carts = {}
Toolkit.ActionQueueCarts = Carts
local Policy, Operations = Toolkit.ActionQueuePolicy, Toolkit.ActionQueueOperations
local class, core, network = ISCartTransferAction, SaucedCarts, SaucedCarts.Network
local constructors, methods, coreMethods = {}, {}, {}
local latestConstructor, latestPerform, latestTransferItem, installed, trusted, trustFailure
local compat, approvedPerform, approvePerform = Toolkit.ActionQueueCompat
local sendToServer
local involvesCart, isTransfer, capacitySafe
local Proof=require "PZSurvivorToolkit/SourceProof"
local bindingType,bindingMeta,bindingRaw,bindingPairs,bindingEach,bindingEqual,bindingCall=type,getmetatable,rawget,pairs,ipairs,rawequal,pcall
local bindingCapture,bindingOrigin,bindingMatches=Proof and Proof.captureBindings,Proof and Proof.closure,Proof and Proof.matches
local bindingGlobals,bindingFilename,bindingLine,bindingReader=_G,getFilenameOfClosure,getFirstLineOfClosure,getModFileReader
local bindingTransferOwner=ISInventoryTransferAction
local bindingPolicyAdopt,bindingReturnAdopt=Policy and Policy.adoptTransferHooks,Operations and Operations.adoptReturnHooks
local bindingState={revision=0,complete=true,records={}}
local bindingBusy,bindingEpoch=false,0
local transferBindingFactory
local bindingPins={}
local transferKeys={"new","perform","transferItem"}
local function bindingOwn(owner,key)
    if bindingType(owner)~="table" then return nil end
    if bindingMeta(owner)==nil then local value=bindingRaw(owner,key);return value end
    local count=0
    for name,value in bindingPairs(owner) do
        count=count+1;if count>128 then return nil end
        if bindingEqual(name,key) then return value end
    end
    return nil
end
local function copyTransfer(values)
    if bindingType(values)~="table" or bindingMeta(values)~=nil then return nil end
    local copy={}
    for _,key in bindingEach(transferKeys) do
        local value=bindingOwn(values,key)
        if bindingType(value)~="function" then return nil end
        copy[key]=value
    end
    return copy
end
local function sameTransfer(owner,values)
    if not values then return false end
    for _,key in bindingEach(transferKeys) do
        if not bindingEqual(bindingOwn(owner,key),values[key]) then return false end
    end
    return true
end
local function transferMethods()
    return {new = ISInventoryTransferAction.new, perform = ISInventoryTransferAction.perform, transferItem = ISInventoryTransferAction.transferItem}
end

local function filename(callback)
    if type(getFilenameOfClosure) ~= "function" then return end
    local ok, path = pcall(getFilenameOfClosure, callback)
    return ok and type(path) == "string" and path:gsub("\\", "/"):match("([^/]+)$") or nil
end

local function unchanged()
    if not trusted then return false, trustFailure or "not_installed" end
    if Toolkit.ActionQueueCarts ~= Carts or Carts.involvesCart ~= involvesCart
        or Carts.isTransfer ~= isTransfer or Carts.capacitySafe ~= capacitySafe
        or ISCartTransferAction ~= class or SaucedCarts ~= core or core.Network ~= network then return false,"owner_changed" end
    if approvedPerform and (Toolkit.ActionQueueCompat ~= compat or compat.isTransferPerform ~= approvePerform
        or not approvePerform(approvedPerform)) then return false,"container_delegate_changed" end
    for name, value in pairs(methods) do if class[name] ~= value then return false,"cart_method_changed:"..name end end
    for name, value in pairs(coreMethods) do if (core[name] or false) ~= value then return false,"cart_helper_changed:"..name end end
    if network.sendToServer ~= sendToServer then return false,"network_helper_changed" end
    return true
end
local function transferUnchanged()
    return ISInventoryTransferAction.new == latestConstructor and ISInventoryTransferAction.perform == latestPerform
        and ISInventoryTransferAction.transferItem == latestTransferItem
end

-- Read-only provenance diagnostics; callers still need their action contract.
function Carts.status()
    local available,reason=unchanged()
    if not available then return false,reason end
    if not transferUnchanged() then return false,"transfer_methods_changed" end
    return true
end

function Carts.isTransferConstructor(callback)
    return unchanged() and constructors[callback] == true and transferUnchanged()
end

local function carried(container, player)
    local seen = {}
    while instanceof(container, "ItemContainer") and not seen[container] do
        if container == player:getInventory() then return true end
        seen[container] = true
        local owner = container:getContainingItem()
        if not instanceof(owner, "InventoryContainer") or owner:getWorldItem() then return false end
        container = owner:getContainer()
    end
    return false
end
involvesCart = function(action)
    if not unchanged() or not transferUnchanged() then return false end
    for _, container in pairs({source = action.srcContainer, destination = action.destContainer}) do
        local seen = {}
        while instanceof(container, "ItemContainer") and not seen[container] do
            seen[container] = true
            local owner = container:getContainingItem()
            if core.safeIsCart(owner) then return true end
            if not instanceof(owner, "InventoryContainer") then break end
            container = owner:getContainer()
        end
    end
    return false
end
Carts.involvesCart = involvesCart

isTransfer = function(action)
    if not unchanged() or not transferUnchanged() or getmetatable(action) ~= class or action.Type ~= class.Type
        or action.onStartFunc or action.onCompleteFunc or action.onCancelFunc or action.retriggerLastAction
        or not instanceof(action.item, "InventoryItem") or not instanceof(action.cartItem, "InventoryContainer")
        or not core.safeIsCart(action.cartItem) or action.cartItem:getWorldItem()
        or not carried(action.cartItem:getContainer(), action.character)
        or not carried(action.srcContainer, action.character) or not carried(action.destContainer, action.character) then return false end
    local source, destination = action.srcContainer:getContainingItem(), action.destContainer:getContainingItem()
    local intoCart = core.safeIsCart(destination)
    local selected = intoCart and destination or source
    if action.cartItem ~= selected or action.direction ~= (intoCart and "in" or "out") then return false end
    for name, value in pairs(methods) do if action[name] ~= value then return false end end
    return true
end
Carts.isTransfer = isTransfer

function Carts.isReturn(action)
    return not isClient() and Carts.isTransfer(action) and action.allowMissingItems
        and action.srcContainer == action.character:getInventory() and action.destContainer ~= action.srcContainer
end

local function inspect(action)
    local result = Policy.transferResources(action)
    if not result then return end
    -- Endpoint owners are references; moving the cart itself still conflicts with either endpoint.
    result.preparationFinish = not isClient()
    -- shortcut: MP performs send a command without a receipt; audit acknowledgement before allowing in-flight cancellation/returns.
    if isClient() and action.action then result.cancelOperation = false end
    return result
end

local capacityGuard
capacitySafe = function(container)
    if not capacityGuard or not capacityGuard(container) then return false end
    local owner = container:getContainingItem()
    if not core.safeIsCart(owner) then return true end
    if type(SandboxVars) ~= "table" or getmetatable(SandboxVars) ~= nil then return false end
    local options = SandboxVars.SaucedCarts
    if options ~= nil and (type(options) ~= "table" or getmetatable(options) ~= nil) then return false end
    local data = core.CartTypes[owner:getFullType()]
    local multiplier = options and options.CapacityMultiplier or 100
    return type(data) == "table" and getmetatable(data) == nil
        and type(data.capacity) == "number" and data.capacity >= 0 and data.capacity < math.huge
        and type(multiplier) == "number" and multiplier >= 0 and multiplier < math.huge
        and data.capacity * multiplier < math.huge
end
Carts.capacitySafe = capacitySafe
local function installCapacity()
    local sourceQuery = compat and compat.isCartCapacitySource
    local nativeMatches = Toolkit.cartCapacityMatches
    if type(sourceQuery) ~= "function" or not sourceQuery() or type(nativeMatches) ~= "function" then return end
    local cartTypes, getCartData = core.CartTypes, core.getCartData
    if type(cartTypes) ~= "table" or getmetatable(cartTypes) ~= nil or filename(getCartData) ~= "CartData.lua" then return end
    Events.OnGameStart.Add(function()
        local meta = ItemContainer and __classmetatables and __classmetatables[ItemContainer.class]
        local methods = meta and meta.__index
        if not methods then return end
        local effective, room = methods.getEffectiveCapacity, methods.hasRoomFor
        if filename(effective) ~= "CapacityOverride.lua" or filename(room) ~= "CapacityOverride.lua" then return end
        capacityGuard = function(container)
            return unchanged() and transferUnchanged() and Toolkit.ActionQueueCompat == compat
                and compat.isCartCapacitySource == sourceQuery and core.CartTypes == cartTypes
                and getmetatable(cartTypes) == nil and core.getCartData == getCartData
                and Toolkit.cartCapacityMatches == nativeMatches and nativeMatches(container)
                and container.getEffectiveCapacity == effective and container.hasRoomFor == room
        end
    end)
end

local function adoptHooks(previous,replacement,source)
    -- Keep private copies before either adopter can run callbacks. A failed or
    -- mutated provenance record disables only this optional observation seam.
    local before,after=copyTransfer(previous),copyTransfer(replacement)
    local policyAdopt,returnAdopt=bindingOwn(Policy,"adoptTransferHooks"),bindingOwn(Operations,"adoptReturnHooks")
    local accepted,reason=Policy.adoptTransferHooks(previous,replacement,unchanged)
    if not accepted then return false,"policy:"..tostring(reason) end
    accepted,reason=Operations.adoptReturnHooks(previous,replacement,unchanged)
    if not accepted then return false,"returns:"..tostring(reason) end
    if not before or not after or not sameTransfer(previous,before) or not sameTransfer(replacement,after)
        or not bindingEqual(policyAdopt,bindingPolicyAdopt) or not bindingEqual(returnAdopt,bindingReturnAdopt)
        or #bindingState.records>=4 then bindingState.complete=false
    else bindingState.records[#bindingState.records+1]={previous=before,replacement=after,source=source} end
    bindingState.revision=bindingState.revision+1
    return true
end

local function loadHooks(module)
    local event, captured = Events.OnGameStart, false
    local add = event.Add
    event.Add = function(callback)
        captured = true
        add(function(...)
            local previous = transferMethods()
            callback(...)
            local replacement = transferMethods()
            local adopted,reason=adoptHooks(previous,replacement,module)
            if adopted then
                constructors[replacement.new], latestConstructor, latestPerform, latestTransferItem =
                    true, replacement.new, replacement.perform, replacement.transferItem
            else trusted=false;trustFailure=trustFailure or "late_hook_rejected:"..module..":"..tostring(reason) end
        end)
    end
    local ok, result = pcall(require, module)
    event.Add = add
    return ok and captured
end

local equipmentGuard, equipmentMatch, equipmentPrevious, equipmentReplacement
local function ordinaryEquipment(item)
    return item == nil or (instanceof(item, "InventoryItem") and not core.CartTypes[item:getFullType()]
        and not core.safeIsCart(item))
end
local function isUnequipConstructor(callback)
    return equipmentGuard and equipmentGuard() and equipmentPrevious
        and (callback == equipmentPrevious.new or equipmentReplacement and callback == equipmentReplacement.new)
        and ISUnequipAction.new == (equipmentReplacement or equipmentPrevious).new
        and ISUnequipAction.complete == (equipmentReplacement or equipmentPrevious).complete or false
end
Carts.isUnequipConstructor = isUnequipConstructor
function Carts.isNonCartItem(item)
    return equipmentGuard and equipmentGuard() and ordinaryEquipment(item) or false
end
function Carts.isNonCartUnequip(action)
    return equipmentMatch and equipmentMatch(action) and ordinaryEquipment(action.item) or false
end
function Carts.equipmentSafe(character)
    return isUnequipConstructor(ISUnequipAction.new) and character
        and ordinaryEquipment(character:getPrimaryHandItem()) and ordinaryEquipment(character:getSecondaryHandItem()) or false
end
-- Fitness uses the ordinary-bag branches of the pinned global cart drop hooks.
-- Capture native predecessors before OnGameStart, then retain exact replacements.
local dropGuard, dropPrevious, dropReplacement
local dropMethods = {new = true, isValid = true, complete = true}
local function dropCallbacksSafe()
    if not dropGuard or not dropGuard() then return false end
    for name, callback in pairs(dropReplacement or dropPrevious) do
        if ISDropWorldItemAction[name] ~= callback then return false end
    end
    return true
end
function Carts.isDropCallback(name, callback)
    return dropMethods[name] and dropCallbacksSafe()
        and (callback == dropPrevious[name] or dropReplacement and callback == dropReplacement[name]) or false
end
function Carts.isNonCartDrop(action)
    if not dropCallbacksSafe() or getmetatable(action) ~= ISDropWorldItemAction or action.Type ~= "ISDropWorldItemAction"
        or not instanceof(action.item, "InventoryContainer") or not ordinaryEquipment(action.item)
        or action.onStartFunc or action.onCompleteFunc or action.onCancelFunc or action.retriggerLastAction
        or action.onFailFunc or action.additionalTest then return false end
    for name, callback in pairs(dropReplacement or dropPrevious) do if action[name] ~= callback then return false end end
    return true
end
local function installFitnessStorageDrop()
    local sourceQuery = compat and compat.isCartMaskSource
    local owner = ISDropWorldItemAction
    if type(sourceQuery) ~= "function" or not sourceQuery() or not owner then return end
    local previous, lifecycle = {}, {}
    for name, callback in pairs(owner) do
        if type(callback) == "function" then
            if name ~= "derive" and filename(callback) ~= "ISDropWorldItemAction.lua" then return end
            if dropMethods[name] then previous[name] = callback else lifecycle[name] = callback end
        end
    end
    for name in pairs(dropMethods) do if type(previous[name]) ~= "function" then return end end
    local cartTypes, classifier = core.CartTypes, core.safeIsCart
    if type(cartTypes) ~= "table" or getmetatable(cartTypes) ~= nil or filename(classifier) ~= "Core.lua" then return end
    dropPrevious = previous
    dropGuard = function()
        if not unchanged() or ISDropWorldItemAction ~= owner or Toolkit.ActionQueueCompat ~= compat
            or compat.isCartMaskSource ~= sourceQuery or core.CartTypes ~= cartTypes
            or core.safeIsCart ~= classifier or getmetatable(cartTypes) ~= nil then return false end
        for name, callback in pairs(lifecycle) do if owner[name] ~= callback then return false end end
        return true
    end
    Events.OnGameStart.Add(function()
        local replacement = {}
        for name in pairs(dropMethods) do
            if filename(owner[name]) ~= "ContainerRestrictions.lua" then dropGuard = nil; return end
            replacement[name] = owner[name]
        end
        dropReplacement = replacement
    end)
end

local function installEquipmentBinding()
    local sourceQuery = compat and compat.isCartMaskSource
    if type(sourceQuery) ~= "function" or not sourceQuery() or not ISUnequipAction
        or filename(ISUnequipAction.new) ~= "ISUnequipAction.lua"
        or filename(ISUnequipAction.complete) ~= "ISUnequipAction.lua" then return end
    local previous = {new = ISUnequipAction.new, complete = ISUnequipAction.complete}
    local unequipOwner, lifecycle = ISUnequipAction, {}
    for name, callback in pairs(unequipOwner) do
        if type(callback) == "function" and name ~= "new" and name ~= "complete" then
            if name ~= "derive" and filename(callback) ~= "ISUnequipAction.lua" then return end
            lifecycle[name] = callback
        end
    end
    local cartTypes, debugHelper = core.CartTypes, core.debug
    if type(cartTypes) ~= "table" or getmetatable(cartTypes) ~= nil or filename(debugHelper) ~= "Core.lua" then return end
    local function helpersSafe()
        if ISUnequipAction ~= unequipOwner then return false end
        for name, callback in pairs(lifecycle) do if unequipOwner[name] ~= callback then return false end end
        return unchanged() and Toolkit.ActionQueueCompat == compat
            and compat.isCartMaskSource == sourceQuery and core.CartTypes == cartTypes
            and core.debug == debugHelper and getmetatable(cartTypes) == nil
    end
    local function ordinaryUnequip(action) return ordinaryEquipment(action.item) end
    equipmentGuard, equipmentPrevious = helpersSafe, previous
    Events.OnGameStart.Add(function()
        local replacement = {new = ISUnequipAction.new, complete = ISUnequipAction.complete}
        if filename(replacement.new) ~= "ContainerRestrictions.lua"
            or filename(replacement.complete) ~= "ContainerRestrictions.lua" then equipmentGuard = nil; return end
        local nativeMatches = Policy.nativeUnequipVariant(previous, replacement, helpersSafe)
        if not nativeMatches then equipmentGuard = nil; return end
        equipmentReplacement, equipmentMatch = replacement, nativeMatches
        if not Policy.adoptNativeUnequipVariant(previous, replacement, helpersSafe, ordinaryUnequip) then
            equipmentGuard, equipmentMatch = nil, nil
        end
    end)
end

function Carts.install()
    if installed then return trusted end
    installed = true
    latestConstructor, latestPerform, latestTransferItem = ISInventoryTransferAction.new,
        ISInventoryTransferAction.perform, ISInventoryTransferAction.transferItem
    local source = filename(latestConstructor)
    if source ~= "CartTransferInterceptor.lua" and source ~= "ISInventoryTransferAction.lua" then return false end
    if filename(latestPerform) ~= "ISInventoryTransferAction.lua" then
        if not compat or Toolkit.ActionQueueCompat ~= compat or type(compat.isTransferPerform) ~= "function"
            or not compat.isTransferPerform(latestPerform) then return false end
        approvedPerform, approvePerform = latestPerform, compat.isTransferPerform
    end
    if type(class) ~= "table" or class.Type ~= "ISCartTransferAction"
        or (filename(latestTransferItem) ~= "ISInventoryTransferAction.lua"
            and not (source == "CartTransferInterceptor.lua" and isClient() and filename(latestTransferItem) == "CartTransferInterceptor.lua")) then return false end
    for name, value in pairs(class) do
        if type(value) == "function" and name ~= "derive" and filename(value) ~= "ISCartTransferAction.lua" then return false end
    end
    for name, expected in pairs({isCart = "Core.lua", safeIsCart = "Core.lua", performCartTransfer = "CartTransferInterceptor.lua",
        flushContainerResync = "CartTransferInterceptor.lua", requestInventoryRefresh = "CartTransferInterceptor.lua"}) do
        if filename(core[name]) ~= expected then return false end
    end
    if filename(network.sendToServer) ~= "Network.lua" then return false end
    local merge = class.canMergeAction
    class.canMergeAction = function(action, other)
        if Toolkit.Settings.actionQueue() and other
            and action.toolkitQueueOperation ~= other.toolkitQueueOperation then return false end
        return merge(action, other)
    end
    for name, value in pairs(class) do methods[name] = value end
    for _, name in ipairs({"isCart", "safeIsCart", "performCartTransfer", "flushContainerResync", "requestInventoryRefresh"}) do
        coreMethods[name] = core[name] or false
    end
    sendToServer = network.sendToServer
    bindingState.initial=copyTransfer(transferMethods())
    if bindingState.initial then
        bindingState.initial.approved=approvedPerform
        bindingState.initial.approve=approvePerform
        bindingState.initial.cartTypes=bindingOwn(core,"CartTypes")
        bindingState.initial.getCart=bindingOwn(network,"getCartFromContainer")
        bindingState.initial.getCartData=bindingOwn(core,"getCartData")
    else bindingState.complete=false end
    bindingState.revision=bindingState.revision+1
    constructors[latestConstructor], trusted = true, true
    if source == "ISInventoryTransferAction.lua" then
        local previous = transferMethods()
        -- Shared interception can wait for OnGameStart until the native client class exists.
        Events.OnGameStart.Add(function()
            local replacement = transferMethods()
            local valid=filename(replacement.new) == "CartTransferInterceptor.lua"
                and replacement.perform == previous.perform and type(replacement.transferItem) == "function"
                and (replacement.transferItem == previous.transferItem
                    or (isClient() and filename(replacement.transferItem) == "CartTransferInterceptor.lua"))
            local adopted,reason
            if valid then adopted,reason=adoptHooks(previous,replacement,"SaucedCarts/CartTransferInterceptor") end
            if adopted then
                constructors[replacement.new], latestConstructor, latestPerform, latestTransferItem =
                    true, replacement.new, replacement.perform, replacement.transferItem
            else
                trusted=false
                trustFailure=trustFailure or "shared_hook_rejected:"..tostring(reason or
                    "source_changed:new="..tostring(filename(replacement.new))
                    ..",perform="..tostring(filename(replacement.perform))..",samePerform="..tostring(replacement.perform==previous.perform)
                    ..",transferItem="..tostring(filename(replacement.transferItem))..",sameTransferItem="..tostring(replacement.transferItem==previous.transferItem))
            end
        end)
    end
    if not loadHooks("SaucedCarts/Restrictions/TransferRestrictions")
        or not loadHooks("SaucedCarts/CartState/VisualUpdateQueue") then trusted=false;trustFailure=trustFailure or "hook_registration_missing" end
    installEquipmentBinding()
    installFitnessStorageDrop()
    installCapacity()
    Toolkit.ActionQueueDefinitions.registerBehavior("compat.cart-transfer", {
        types = {"ISCartTransferAction"}, matches = Carts.isTransfer, inspect = inspect,
    })
    return trusted
end

-- Source provenance for the exact guard submitted at successful hook adoption.
-- Main composes every Compat predecessor separately; this never calls a generic
-- guard/status helper or derives cart classification from live Java getters.
local function bindingFields(specifications,owner,expected)
    if bindingType(owner)~="table" then return false end
    local keys={}
    for key,value in bindingPairs(expected) do
        if not bindingEqual(bindingOwn(owner,key),value) then return false end
        keys[#keys+1]=key
    end
    if #keys>0 then specifications[#specifications+1]={owner=owner,keys=keys} end
    return true
end
local function completeParentTypes(values)
    if values==false then return true end
    if bindingType(values)~="table" or bindingMeta(values)~=nil then return false end
    local count,size=0,#values
    if size<1 or size>64 then return false end
    for key,value in bindingPairs(values) do
        if bindingType(key)~="number" or key%1~=0 or key<1 or key>size
            or bindingType(value)~="string" or value=="" then return false end
        count=count+1
    end
    return count==size
end
local function reference(value)local kind=bindingType(value);return kind=="table" or kind=="userdata"end
local function nonCartFacts(facts,item,source,destination,cartTypes)
    if bindingType(facts)~="table" or bindingMeta(facts)~=nil or bindingOwn(facts,"schema")~=2
        or not bindingEqual(bindingOwn(facts,"item"),item)
        or not bindingEqual(bindingOwn(facts,"source"),source) or not bindingEqual(bindingOwn(facts,"destination"),destination)
        or not completeParentTypes(bindingOwn(facts,"sourceParentTypes"))
        or not completeParentTypes(bindingOwn(facts,"destinationParentTypes")) then return false end
    local fullType=bindingOwn(facts,"fullType")
    if bindingType(fullType)~="string" or fullType=="" or bindingOwn(cartTypes,fullType)~=nil then return false end
    local holder,holderType=bindingOwn(facts,"destinationOwner"),bindingOwn(facts,"destinationOwnerFullType")
    if holder~=nil then
        if not reference(holder) or bindingType(holderType)~="string" or holderType==""
            or bindingOwn(cartTypes,holderType)~=nil then return false end
    elseif holderType~=nil then return false end
    if bindingOwn(facts,"primaryItemContainerKnown")~=true then return false end
    local primary,primaryType=bindingOwn(facts,"primaryItem"),bindingOwn(facts,"primaryFullType")
    local internal=bindingOwn(facts,"primaryItemContainer")
    if primary==nil then return primaryType==nil and internal==nil end
    if not reference(primary) or bindingType(primaryType)~="string" or primaryType==""
        or internal~=nil and not reference(internal) then return false end
    -- Network's hand fallback is relevant only when that internal inventory is
    -- this endpoint. A cart held over an unrelated ordinary bag adds no branch.
    return not (bindingEqual(internal,source) or bindingEqual(internal,destination))
        or bindingOwn(cartTypes,primaryType)==nil
end
local function bindingSource(record)
    local previous,replacement=record.previous,record.replacement
    if record.source=="SaucedCarts/CartTransferInterceptor" then
        return not bindingEqual(previous.new,replacement.new) and bindingOrigin(replacement.new,"CartTransferInterceptor.lua")
            and bindingEqual(previous.perform,replacement.perform)
            and (bindingEqual(previous.transferItem,replacement.transferItem)
                or bindingOrigin(replacement.transferItem,"CartTransferInterceptor.lua"))
    elseif record.source=="SaucedCarts/Restrictions/TransferRestrictions" then
        return not bindingEqual(previous.new,replacement.new) and bindingOrigin(replacement.new,"TransferRestrictions.lua")
            and bindingEqual(previous.perform,replacement.perform) and bindingEqual(previous.transferItem,replacement.transferItem)
    elseif record.source=="SaucedCarts/CartState/VisualUpdateQueue" then
        return not bindingEqual(previous.perform,replacement.perform) and bindingOrigin(replacement.perform,"VisualUpdateQueue.lua")
            and bindingEqual(previous.new,replacement.new) and bindingEqual(previous.transferItem,replacement.transferItem)
    end
    return false
end
local function sourcesPinned()
    for _,entry in bindingEach({
        {"shared/SaucedCarts/TimedActions/ISCartTransferAction.lua",3962234240},
        {"shared/SaucedCarts/CartTransferInterceptor.lua",2772644904},
        {"shared/SaucedCarts/Core.lua",2570266575},{"shared/SaucedCarts/Network.lua",2897409368},
        {"shared/SaucedCarts/CartData.lua",3388888445},
        {"client/SaucedCarts/Restrictions/TransferRestrictions.lua",2976371209},
        {"client/SaucedCarts/CartState/VisualUpdateQueue.lua",2627823607}}) do
        local path=entry[1]
        if bindingPins[path]==nil then bindingPins[path]=bindingMatches("media/lua/"..path,entry[2],"SaucedCarts",true) end
        if not bindingPins[path] then return false end
    end
    return true
end
transferBindingFactory=function(guard,action)
    bindingEpoch=bindingEpoch+1
    local epoch=bindingEpoch
    local initial,records=bindingState.initial,bindingState.records
    if bindingBusy or not installed or trusted~=true or not bindingState.complete
        or not bindingEqual(guard,unchanged) or bindingType(action)~="table"
        or bindingType(initial)~="table" or #records<1 or #records>4
        or bindingType(Proof)~="table" or bindingMeta(Proof)~=nil
        or bindingType(bindingCapture)~="function" or bindingType(bindingOrigin)~="function"
        or bindingType(bindingMatches)~="function" or bindingType(bindingFilename)~="function" or bindingType(bindingLine)~="function"
        or bindingType(bindingReader)~="function" or bindingMeta(bindingGlobals)~=nil
        or bindingMeta(Toolkit)~=nil or bindingMeta(Carts)~=nil or bindingMeta(core)~=nil
        or bindingMeta(network)~=nil or bindingMeta(Policy)~=nil or bindingMeta(Operations)~=nil then return nil end
    local item,source,destination=bindingOwn(action,"item"),bindingOwn(action,"srcContainer"),bindingOwn(action,"destContainer")
    local cartTypes=initial.cartTypes
    if not reference(item) or not reference(source) or not reference(destination) or bindingEqual(source,destination)
        or bindingType(cartTypes)~="table" or bindingMeta(cartTypes)~=nil
        or bindingType(initial.getCart)~="function" or bindingType(initial.getCartData)~="function" then return nil end
    local specifications={{owner=bindingGlobals,keys={"PZSurvivorToolkit","SaucedCarts","ISCartTransferAction","ISInventoryTransferAction","getFilenameOfClosure","getFirstLineOfClosure","getModFileReader"}},
        {owner=Toolkit,keys={"ActionQueueCarts","ActionQueueCompat","ActionQueuePolicy","ActionQueueOperations"}},
        {owner=Carts,keys={"transferBinding","involvesCart","isTransfer","capacitySafe"}},
        {owner=Proof,keys={"captureBindings","closure","matches"}},
        {owner=bindingState,exact=true},{owner=initial,exact=true},{owner=records,exact=true},
        {owner=methods,exact=true},{owner=coreMethods,exact=true},{owner=cartTypes,exact=true},
        {owner=action,keys={"item","srcContainer","destContainer","character"}}}
    if not bindingFields(specifications,bindingGlobals,{PZSurvivorToolkit=Toolkit,SaucedCarts=core,
        ISCartTransferAction=class,ISInventoryTransferAction=bindingTransferOwner,getFilenameOfClosure=bindingFilename,getFirstLineOfClosure=bindingLine,getModFileReader=bindingReader})
        or not bindingFields(specifications,Toolkit,{ActionQueueCarts=Carts,ActionQueuePolicy=Policy,ActionQueueOperations=Operations})
        or not bindingFields(specifications,Carts,{transferBinding=transferBindingFactory,involvesCart=involvesCart,isTransfer=isTransfer,capacitySafe=capacitySafe})
        or not bindingFields(specifications,Proof,{captureBindings=bindingCapture,closure=bindingOrigin,matches=bindingMatches})
        or not bindingFields(specifications,Policy,{adoptTransferHooks=bindingPolicyAdopt})
        or not bindingFields(specifications,Operations,{adoptReturnHooks=bindingReturnAdopt})
        or not bindingFields(specifications,class,methods)
        or not bindingFields(specifications,core,coreMethods)
        or not bindingFields(specifications,core,{Network=network,CartTypes=cartTypes,getCartData=initial.getCartData})
        or not bindingFields(specifications,network,{sendToServer=sendToServer,getCartFromContainer=initial.getCart}) then return nil end
    if initial.approved then
        if bindingType(compat)~="table" or bindingMeta(compat)~=nil or not bindingEqual(initial.perform,initial.approved) or not bindingEqual(initial.approve,approvePerform)
            or not bindingEqual(initial.approved,approvedPerform)
            or not bindingFields(specifications,compat,{isTransferPerform=initial.approve})
            or not bindingFields(specifications,Toolkit,{ActionQueueCompat=compat}) then return nil end
    end
    local cursor=initial
    for _,record in bindingEach(records) do
        if not sameTransfer(record.previous,cursor) then return nil end
        specifications[#specifications+1]={owner=record,exact=true}
        specifications[#specifications+1]={owner=record.previous,exact=true}
        specifications[#specifications+1]={owner=record.replacement,exact=true}
        cursor=record.replacement
    end
    if not sameTransfer(bindingTransferOwner,cursor) or not bindingEqual(cursor.new,latestConstructor)
        or not bindingEqual(cursor.perform,latestPerform) or not bindingEqual(cursor.transferItem,latestTransferItem)
        or not bindingFields(specifications,bindingTransferOwner,cursor) then return nil end
    -- Merge duplicate selected owners before the shared bounded watcher; exact
    -- snapshots are never merged with a selected owner specification.
    local merged,seen,selected={},{},{}
    for _,specification in bindingEach(specifications) do
        local owner=specification.owner
        local prior=seen[owner]
        if prior then
            if prior.exact or specification.exact then return nil end
            for _,key in bindingEach(specification.keys) do
                if not selected[owner][key] then
                    prior.keys[#prior.keys+1]=key;selected[owner][key]=true
                end
            end
        else
            seen[owner]=specification;merged[#merged+1]=specification
            if not specification.exact then
                selected[owner]={}
                for _,key in bindingEach(specification.keys) do selected[owner][key]=true end
            end
        end
    end
    local watch=bindingCapture(merged)
    if not watch then return nil end
    bindingBusy=true
    local ok,known=bindingCall(function()
        -- Native first-instruction lines identify roles inside these checksum-
        -- pinned source versions, rather than trusting any same-file alias.
        -- Verified with real Kahlua: Core 2570266575, Network 2897409368,
        -- CartData 3388888445. Source updates require auditing both pins/roles.
        if not sourcesPinned() or not bindingOrigin(coreMethods.isCart,"Core.lua")
            or bindingLine(coreMethods.isCart)~=295 or not bindingOrigin(coreMethods.safeIsCart,"Core.lua")
            or bindingLine(coreMethods.safeIsCart)~=320 or not bindingOrigin(initial.getCart,"Network.lua")
            or bindingLine(initial.getCart)~=175 or not bindingOrigin(initial.getCartData,"CartData.lua")
            or bindingLine(initial.getCartData)~=561 then return false end
        if initial.approved then
            if not bindingOrigin(initial.approve,"ActionQueueCompat.lua") then return false end
        elseif not bindingOrigin(initial.perform,"ISInventoryTransferAction.lua") then return false end
        for _,record in bindingEach(records) do if not bindingSource(record) then return false end end
        return true
    end)
    bindingBusy=false
    if not ok or not known or bindingEpoch~=epoch or trusted~=true or not watch() then return nil end
    return function(facts)
        return trusted==true and watch() and nonCartFacts(facts,item,source,destination,cartTypes)
    end
end
Carts.transferBinding=transferBindingFactory
local bindingAdapters=Toolkit.ActionQueueItemEditAdapters
if bindingType(bindingAdapters)=="table" and bindingMeta(bindingAdapters)==nil then
    local register=bindingOwn(bindingAdapters,"registerSourceFactory")
    if bindingType(register)=="function" then register(Carts,"transferBinding",transferBindingFactory) end
end

return Carts
