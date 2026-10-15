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
local involvesCart
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

function Carts.isTransfer(action)
    if not unchanged() or not transferUnchanged() or getmetatable(action) ~= class or action.Type ~= class.Type
        or action.onStartFunc or action.onCompleteFunc or action.onCancelFunc or action.retriggerLastAction
        or not instanceof(action.item, "InventoryItem") or not instanceof(action.cartItem, "InventoryContainer")
        or not core.safeIsCart(action.cartItem) or action.cartItem:getWorldItem()
        or not carried(action.cartItem:getContainer(), action.character)
        or not carried(action.srcContainer, action.character) or not carried(action.destContainer, action.character) then return false end
    local source, destination = action.srcContainer:getContainingItem(), action.destContainer:getContainingItem()
    if source ~= destination and core.safeIsCart(source) and core.safeIsCart(destination) then return false end
    local selected = core.safeIsCart(destination) and destination or source
    if action.cartItem ~= selected then return false end
    for name, value in pairs(methods) do if action[name] ~= value then return false end end
    return true
end

function Carts.isReturn(action)
    return not isClient() and Carts.isTransfer(action) and action.allowMissingItems
        and action.srcContainer == action.character:getInventory() and action.destContainer ~= action.srcContainer
end

local function inspect(action)
    local result = Policy.transferResources(action)
    if not result then return end
    result.items[action.cartItem:getID()] = true
    result.itemTypes[action.cartItem:getFullType()] = true
    result.preparationFinish = not isClient()
    -- shortcut: MP performs send a command without a receipt; audit acknowledgement before allowing in-flight cancellation/returns.
    if isClient() and action.action then result.cancelOperation = false end
    return result
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
    Toolkit.ActionQueueDefinitions.registerBehavior("compat.cart-transfer", {
        types = {"ISCartTransferAction"}, matches = Carts.isTransfer, inspect = inspect,
    })
    return trusted
end

return Carts
