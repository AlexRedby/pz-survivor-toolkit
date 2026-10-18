require "PZSurvivorWishlist/UI"
require "PZSurvivorWishlist/Settings"

local W = PZSurvivorWishlist
Events.OnKeyPressed.Add(function(key)
    if key == 0 or key ~= W.Settings.key() then return end
    if not getPlayer() or getPlayer():isDead() or getCore():isDoingTextEntry() then return end
    if MainOptions and MainOptions.instance and MainOptions.instance:isVisible() then return end
    W.UI.toggle(0)
end)
