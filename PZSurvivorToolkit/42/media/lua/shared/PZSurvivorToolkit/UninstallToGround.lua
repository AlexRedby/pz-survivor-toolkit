require "Vehicles/TimedActions/ISUninstallVehiclePart"
require "TimedActions/ISTransferAction"

PZSTUninstallToGround = ISUninstallVehiclePart:derive("PZSTUninstallToGround")
local nativeNew = ISUninstallVehiclePart.new

function PZSTUninstallToGround:new(character, part, workTime)
    -- Named constructor fields are serialized by the multiplayer timed-action protocol.
    return nativeNew(self, character, part, workTime)
end

function PZSTUninstallToGround:isValid()
    return self.character:getCurrentSquare() ~= nil and ISUninstallVehiclePart.isValid(self)
end

function PZSTUninstallToGround:complete()
    local square = self.character:getCurrentSquare()
    if not square then return false end
    local item = self.part and self.part:getInventoryItem()
    local result = ISUninstallVehiclePart.complete(self)
    local inventory = self.character:getInventory()
    -- Native completion may fail or already drop the part when the inventory is full.
    if result and item and not self.part:getInventoryItem() and inventory:contains(item) then
        local x, y, z = ISTransferAction.GetDropItemOffset(self.character, square, item)
        if square:AddWorldInventoryItem(item, x, y, z) then
            inventory:Remove(item)
            sendRemoveItemFromContainer(inventory, item)
            if not isServer() then ISInventoryPage.renderDirty = true end
        end
    end
    return result
end
