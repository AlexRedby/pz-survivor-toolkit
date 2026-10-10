require "PZSurvivorToolkit/UninstallToGround"
require "Vehicles/ISUI/ISVehicleMechanics"
require "Vehicles/ISUI/ISVehiclePartMenu"

local function uninstallToGround(selectedCharacter, selectedPart)
    local nativeNew = ISUninstallVehiclePart.new
    -- Reuse native tool pickup, pathfinding and hood actions with a different final action.
    ISUninstallVehiclePart.new = function(class, character, part, workTime)
        if character == selectedCharacter and part == selectedPart then
            return PZSTUninstallToGround:new(character, part, workTime)
        end
        return nativeNew(class, character, part, workTime)
    end
    local ok, result = pcall(ISVehiclePartMenu.onUninstallPart, selectedCharacter, selectedPart)
    ISUninstallVehiclePart.new = nativeNew
    if not ok then error(result, 0) end
    return result
end

local function install()
    if ISVehicleMechanics.PZSTGroundInstalled then return end
    ISVehicleMechanics.PZSTGroundInstalled = true
    local doPartContextMenu = ISVehicleMechanics.doPartContextMenu
    function ISVehicleMechanics:doPartContextMenu(part, ...)
        local result = doPartContextMenu(self, part, ...)
        if not self.context then return result end
        local label = getText("UI_PZSurvivorToolkit_uninstall_ground")
        if self.context:getOptionFromName(label) then return result end
        for _, option in ipairs(self.context.options) do
            if option.onSelect == ISVehiclePartMenu.onUninstallPart and option.param1 == part then
                local ground = self.context:insertOptionAfter(option.name, label,
                    option.target, uninstallToGround, part)
                ground.notAvailable = option.notAvailable
                ground.toolTip = option.toolTip
                break
            end
        end
        return result
    end
end

Events.OnGameStart.Add(install)
