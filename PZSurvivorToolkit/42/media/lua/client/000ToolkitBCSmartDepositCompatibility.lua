if not getActivatedMods():contains("EURY_CONTAINERS") then return end
local upstream = require "BetterContainers/Proximity/Proximity_SmartDeposit"
if upstream._installed then
    print("[PZSurvivorToolkit] Smart Deposit compatibility needs Toolkit before Better Containers")
    return
end
local Deposit = require "PZSurvivorToolkit/SmartDeposit"
-- BC calls this after installing its proximity pane/page hooks.
upstream.install = function()
    upstream._installed = true
    Deposit.install()
end
