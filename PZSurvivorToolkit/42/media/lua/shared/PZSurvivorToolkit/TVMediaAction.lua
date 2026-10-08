-- A transfer can fail or another player can take the tape while actions are queued.
-- Validate ownership on both client and server before the native device action runs.
if not getActivatedMods():contains("TVRadio_ReInvented") then return end
require "TimedActions/ISDeviceMediaAction"

local isValid = ISDeviceMediaAction.isValid
function ISDeviceMediaAction:isValid()
    if not self.isRemove and (not self.secondaryItem
        or self.secondaryItem:getContainer() ~= self.character:getInventory()) then
        return false
    end
    return isValid(self)
end
