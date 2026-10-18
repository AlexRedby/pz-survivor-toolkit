if not isServer() or not getActivatedMods():contains("SaucedCarts") then return end

local wrapped = {}
local function serverCompletion(class)
    if class.complete == wrapped[class] then return end
    local complete = class.complete
    wrapped[class] = function(self)
        local item, character = self.item, self.character
        if not item or not character or not SaucedCarts.safeIsCart(item) then return complete(self) end
        local perform = ISBaseTimedAction.perform
        -- Upstream ends its server completion through the client-only queue; suppress only this exact action.
        ISBaseTimedAction.perform = function(action, ...)
            if action ~= self then return perform(action, ...) end
        end
        local ok, result = pcall(complete, self)
        ISBaseTimedAction.perform = perform
        if not ok then error(result, 0) end
        if result ~= nil then return result end
        if character:getPrimaryHandItem() == item or character:getSecondaryHandItem() == item
            or character:getInventory():contains(item) then return false end
        local world = item:getWorldItem()
        return world ~= nil and world:getItem() == item and world:getSquare() ~= nil
            or item:getCondition() <= 0 and item:getInventory():getItems():isEmpty()
    end
    class.complete = wrapped[class]
end

-- Upstream registers these shared hooks only for client game-start events.
Events.OnServerStarted.Add(function()
    local restrictions = require "SaucedCarts/ContainerRestrictions"
    if restrictions.initDropActionHook then restrictions.initDropActionHook(); serverCompletion(ISDropWorldItemAction) end
    if restrictions.initUnequipHook then restrictions.initUnequipHook(); serverCompletion(ISUnequipAction) end
    local guard = require "SaucedCarts/ForceDropGuard"
    guard.install()
end)
