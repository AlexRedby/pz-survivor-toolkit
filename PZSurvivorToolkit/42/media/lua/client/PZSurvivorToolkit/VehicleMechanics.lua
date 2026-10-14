require "PZSurvivorToolkit/UninstallToGround"
require "PZSurvivorToolkit/Settings"
require "Vehicles/ISUI/ISVehicleMechanics"
require "Vehicles/ISUI/ISVehiclePartMenu"

local function uninstallToGround(selectedCharacter, selectedPart)
    if not PZSurvivorToolkit.Settings.uninstallToGround() then return end
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

local function uniqueItems(groups)
    if not groups then return groups end
    for _, items in pairs(groups) do
        local seen, count = {}, 0
        for _, item in ipairs(items) do
            if not seen[item] then
                seen[item] = true
                count = count + 1
                items[count] = item
            end
        end
        for i = #items, count + 1, -1 do items[i] = nil end
    end
    return groups
end

local function install()
    if ISVehicleMechanics.PZSTGroundInstalled then return end
    ISVehicleMechanics.PZSTGroundInstalled = true
    local getItems = VehicleUtils.getItems
    function VehicleUtils.getItems(...)
        local byType, byTag = getItems(...)
        -- Proximity views expose the same physical items as their real containers.
        return uniqueItems(byType), uniqueItems(byTag)
    end
    local doPartContextMenu = ISVehicleMechanics.doPartContextMenu
    function ISVehicleMechanics:doPartContextMenu(part, ...)
        local result = doPartContextMenu(self, part, ...)
        if not PZSurvivorToolkit.Settings.uninstallToGround() then return result end
        if not self.context then return result end
        local label = getText("UI_PZSurvivorToolkit_uninstall_ground")
        if self.context:getOptionFromName(label) then return result end
        for _, option in ipairs(self.context.options) do
            if option.onSelect == ISVehiclePartMenu.onUninstallPart and option.param1 == part then
                local ground = self.context:insertOptionAfter(option.name, label,
                    option.target, uninstallToGround, part)
                ground.notAvailable = option.notAvailable
                ground.toolTip = option.toolTip
                ground.pzstCategory, ground.pzstKey = "vehicle", "uninstallGround"
                break
            end
        end
        return result
    end
end

Events.OnGameStart.Add(install)
