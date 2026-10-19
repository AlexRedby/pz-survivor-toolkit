if not getActivatedMods():contains("SaucedCarts") then return end
require "TimedActions/ISTimedActionQueue"
local hotkeys = require "PZSurvivorToolkit/CartHotkeys"
local settings = require "PZSurvivorToolkit/CartKeySettings"
local binding

-- The upstream callback is added on OnGameStart. Register this snapshot first,
-- then its observer after it; no private upstream callback is replaced.
Events.OnKeyStartPressed.Add(function(key) hotkeys.beforePress(key, binding) end)
require "SaucedCarts/Hotkeys"
binding = PZAPI.ModOptions:getOptions("SaucedCarts"):getOption("PushCart")
settings.configureDefault(binding)
Events.OnGameStart.Add(function()
    hotkeys.reset()
    local ok, reason = settings.migrate(binding)
    if not ok then print("[PZSurvivorToolkit] Cart key migration deferred: " .. tostring(reason)) end
    Events.OnKeyStartPressed.Remove(hotkeys.afterPress)
    Events.OnKeyStartPressed.Add(hotkeys.afterPress)
    -- CartStateHandler registers at file load and clears context on unequip.
    -- Reapply a captured gesture after that handler, before native updateUseKey.
    Events.OnPlayerUpdate.Remove(hotkeys.playerUpdate)
    Events.OnPlayerUpdate.Add(hotkeys.playerUpdate)
end)
Events.OnTick.Add(hotkeys.tick)
Events.OnPlayerDeath.Add(function(player)
    if player == getSpecificPlayer(0) then hotkeys.reset() end
end)
Events.OnMainMenuEnter.Add(hotkeys.reset)
