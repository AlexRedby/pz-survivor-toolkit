if isServer() or not getActivatedMods():contains("SaucedCarts") then return end
require "SaucedCarts/Core"
require "SaucedCarts/TimedActions/ISCartPickupAction"
require "SaucedCarts/TimedActions/ISCartEquipAction"

local function completedCart(self, idField)
    if not isClient() or not self:isStarted() then return end
    local inventory = self.character:getInventory()
    local cart = inventory:getItemById(self[idField])
    local held = self.character:getPrimaryHandItem()
    if cart and SaucedCarts.isCart(cart) and not cart:getWorldItem()
        and inventory:contains(cart) and (not held or held == cart or not held:isForceDropHeavyItem()) then return cart end
end

-- Inventory and equip packets can arrive before the client's action completes.
for action, idField in pairs({[ISCartPickupAction] = "itemId", [ISCartEquipAction] = "cartId"}) do
    local isValid, perform = action.isValid, action.perform
    local findTarget = action == ISCartPickupAction and action.findWorldItem or action.findCart
    action.isValid = function(self)
        if completedCart(self, idField) then return true end
        local valid = isValid(self)
        if valid or not isClient() or not self:isStarted() then return valid end
        local held = self.character:getPrimaryHandItem()
        if not findTarget(self) and (not held or not held:isForceDropHeavyItem() or held:getID() == self[idField]) then
            -- World removal may arrive a frame before inventory/equip; never extend the grace.
            local now = getTimestampMs()
            self.toolkitCartSyncUntil = self.toolkitCartSyncUntil or now + 1000
            if now < self.toolkitCartSyncUntil then return true end
        end
        return valid
    end
    action.perform = function(self)
        local cart = completedCart(self, idField)
        if cart and (self.character:getPrimaryHandItem() ~= cart or self.character:getSecondaryHandItem() ~= cart) then
            self.character:setPrimaryHandItem(cart)
            self.character:setSecondaryHandItem(cart)
            sendEquip(self.character)
        end
        return perform(self)
    end
end

if not getActivatedMods():contains("P4TidyUpMeister") then return end

local function clearStaleCart(player, item)
    if item and SaucedCarts.isCart(item)
        and (item:getWorldItem() or not player:getInventory():contains(item)) then
        player:removeFromHands(item)
        return true
    end
    return false
end

-- Tidy's cancellation restore can reference a cart already dropped for the tool.
Events.OnPlayerUpdate.Add(function(player)
    if not player:isLocalPlayer() then return end
    local changed = clearStaleCart(player, player:getPrimaryHandItem())
    changed = clearStaleCart(player, player:getSecondaryHandItem()) or changed
    if changed then
        player:resetEquippedHandsModels()
        sendEquip(player)
    end
end)
