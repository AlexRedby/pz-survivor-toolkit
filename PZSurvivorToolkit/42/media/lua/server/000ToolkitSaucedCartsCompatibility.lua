if not isServer() or not getActivatedMods():contains("SaucedCarts") then return end

-- Upstream registers these shared hooks only for client game-start events.
Events.OnServerStarted.Add(function()
    local restrictions = require "SaucedCarts/ContainerRestrictions"
    if restrictions.initDropActionHook then restrictions.initDropActionHook() end
    if restrictions.initUnequipHook then restrictions.initUnequipHook() end
    local guard = require "SaucedCarts/ForceDropGuard"
    guard.install()
end)
