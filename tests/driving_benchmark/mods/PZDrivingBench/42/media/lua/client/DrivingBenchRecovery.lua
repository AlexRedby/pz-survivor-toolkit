local F = require "DrivingBenchFixture"
require "ISUI/ISWorldObjectContextMenu"

local function repair(player, vehicle)
    local result = F.repairVehicle(player, vehicle)
    if result.status == "repaired" then
        player:Say("Test car repaired and refuelled. Restart the engine if needed.")
    else
        player:Say("Driving test: " .. tostring(result.reason))
    end
end

Events.OnFillWorldObjectContextMenu.Add(function(playerIndex, context, worldobjects, test)
    if isClient() or isServer() or not F.allowed() then return end
    local player = getSpecificPlayer(playerIndex)
    if not player then return end
    local vehicle = player:getVehicle() or player:getNearVehicle()
    local available, reason, owned = F.canRepair(player, vehicle)
    if not owned then return end
    if test then return ISWorldObjectContextMenu.setTest() end
    local option = context:addOption("Driving test: repair + refuel", player, repair, vehicle)
    if not available then
        option.notAvailable = true
        option.toolTip = ISWorldObjectContextMenu.addToolTip()
        option.toolTip.description = reason
    end
end)
