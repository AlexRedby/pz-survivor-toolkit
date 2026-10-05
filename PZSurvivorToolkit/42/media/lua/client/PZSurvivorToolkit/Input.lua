require("PZSurvivorToolkit/Settings")

PZSurvivorToolkit = PZSurvivorToolkit or {}

local Toolkit = PZSurvivorToolkit

local function onKeyPressed(key)
    if key ~= Toolkit.Settings.getToggleKey() or key <= 0 then return end
    local player = getPlayer()
    if not player or player:isDead() then return end
    if getCore():isDoingTextEntry() then return end
    -- Suppress gameplay hotkeys while the settings screen is capturing a new binding.
    if MainOptions and MainOptions.instance and MainOptions.instance:isVisible() then return end
    Toolkit.Settings.toggle()
end

Events.OnKeyPressed.Add(onKeyPressed)
