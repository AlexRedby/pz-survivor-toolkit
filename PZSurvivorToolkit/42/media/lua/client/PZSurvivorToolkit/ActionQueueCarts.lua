if not getActivatedMods or not getActivatedMods():contains("SaucedCarts") then return end
require "SaucedCarts/TimedActions/ISCartTransferAction"

local Toolkit = PZSurvivorToolkit
local Carts = {}
Toolkit.ActionQueueCarts = Carts
local Policy, Operations = Toolkit.ActionQueuePolicy, Toolkit.ActionQueueOperations
local class, core, network = ISCartTransferAction, SaucedCarts, SaucedCarts.Network
local constructors, methods, coreMethods = {}, {}, {}
local latestConstructor, latestPerform, latestTransferItem, installed, trusted
local compat, approvedPerform, approvePerform = Toolkit.ActionQueueCompat
local sendToServer
local involvesCart, isTransfer, capacitySafe
local function transferMethods()
    return {new = ISInventoryTransferAction.new, perform = ISInventoryTransferAction.perform, transferItem = ISInventoryTransferAction.transferItem}
end

local function filename(callback)
    if type(getFilenameOfClosure) ~= "function" then return end
    local ok, path = pcall(getFilenameOfClosure, callback)
    return ok and type(path) == "string" and path:gsub("\\", "/"):match("([^/]+)$") or nil
end

local function unchanged()
    if not trusted or Toolkit.ActionQueueCarts ~= Carts or Carts.involvesCart ~= involvesCart
        or Carts.isTransfer ~= isTransfer or Carts.capacitySafe ~= capacitySafe
        or ISCartTransferAction ~= class or SaucedCarts ~= core or core.Network ~= network then return false end
    if approvedPerform and (Toolkit.ActionQueueCompat ~= compat or compat.isTransferPerform ~= approvePerform
        or not approvePerform(approvedPerform)) then return false end
    for name, value in pairs(methods) do if class[name] ~= value then return false end end
    for name, value in pairs(coreMethods) do if (core[name] or false) ~= value then return false end end
    return network.sendToServer == sendToServer
end
local function transferUnchanged()
    return ISInventoryTransferAction.new == latestConstructor and ISInventoryTransferAction.perform == latestPerform
        and ISInventoryTransferAction.transferItem == latestTransferItem
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

local function loadHooks(module)
    local event, captured = Events.OnGameStart, false
    local add = event.Add
    event.Add = function(callback)
        captured = true
        add(function(...)
            local previous = transferMethods()
            callback(...)
            local replacement = transferMethods()
            if Policy.adoptTransferHooks(previous, replacement, unchanged)
                and Operations.adoptReturnHooks(previous, replacement, unchanged) then
                constructors[replacement.new], latestConstructor, latestPerform, latestTransferItem =
                    true, replacement.new, replacement.perform, replacement.transferItem
            else trusted = false end
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
local function installFoodMaskRemoval()
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
    equipmentGuard, equipmentPrevious = helpersSafe, previous
    Events.OnGameStart.Add(function()
        local replacement = {new = ISUnequipAction.new, complete = ISUnequipAction.complete}
        if filename(replacement.new) ~= "ContainerRestrictions.lua"
            or filename(replacement.complete) ~= "ContainerRestrictions.lua" then equipmentGuard = nil; return end
        local nativeMatches = Policy.nativeUnequipVariant(previous, replacement, helpersSafe)
        if not nativeMatches then equipmentGuard = nil; return end
        equipmentReplacement, equipmentMatch = replacement, nativeMatches
        local food = Toolkit.BulkFood
        local isRemoval = food and food.isMaskRemoval
        if type(isRemoval) ~= "function" then return end
        Toolkit.ActionQueueDefinitions.registerBehavior("compat.food-mask-unequip", {
            types = {"ISUnequipAction"}, matches = function(action)
                return nativeMatches(action) and ordinaryEquipment(action.item) and Toolkit.BulkFood == food and food.isMaskRemoval == isRemoval
                    and isRemoval(action) and action.item:getCategory() == "Clothing"
            end, inspect = function(action)
                return {items = {[action.item:getID()] = true}, itemTypes = {[action.item:getFullType()] = true},
                    targets = {}, hands = action.character, preparation = true, preparationFinish = true,
                    cancelWaiting = false, interrupt = "finish-step"}
            end,
        })
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
        if other and action.toolkitQueueOperation ~= other.toolkitQueueOperation then return false end
        return merge(action, other)
    end
    for name, value in pairs(class) do methods[name] = value end
    for _, name in ipairs({"isCart", "safeIsCart", "performCartTransfer", "flushContainerResync", "requestInventoryRefresh"}) do
        coreMethods[name] = core[name] or false
    end
    sendToServer = network.sendToServer
    constructors[latestConstructor], trusted = true, true
    if source == "ISInventoryTransferAction.lua" then
        local previous = transferMethods()
        -- Shared interception can wait for OnGameStart until the native client class exists.
        Events.OnGameStart.Add(function()
            local replacement = transferMethods()
            if filename(replacement.new) == "CartTransferInterceptor.lua"
                and replacement.perform == previous.perform and type(replacement.transferItem) == "function"
                and (replacement.transferItem == previous.transferItem
                    or (isClient() and filename(replacement.transferItem) == "CartTransferInterceptor.lua"))
                and Policy.adoptTransferHooks(previous, replacement, unchanged)
                and Operations.adoptReturnHooks(previous, replacement, unchanged) then
                constructors[replacement.new], latestConstructor, latestPerform, latestTransferItem =
                    true, replacement.new, replacement.perform, replacement.transferItem
            else trusted = false end
        end)
    end
    if not loadHooks("SaucedCarts/Restrictions/TransferRestrictions")
        or not loadHooks("SaucedCarts/CartState/VisualUpdateQueue") then trusted = false end
    installFoodMaskRemoval()
    installCapacity()
    Toolkit.ActionQueueDefinitions.registerBehavior("compat.cart-transfer", {
        types = {"ISCartTransferAction"}, matches = Carts.isTransfer, inspect = inspect,
    })
    return trusted
end

return Carts
