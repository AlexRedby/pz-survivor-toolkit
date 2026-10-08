require "OptionScreens/MainOptions"

local function syncAutoDrink()
    if not isClient() then return end
    for i = 0, getMaxActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player then player:setAutoDrink(getCore():getOptionAutoDrink()) end
    end
end

-- Vanilla MainOptions changes Core only; player packets carry a separate flag.
local originalApply = MainOptions.apply
function MainOptions:apply(...)
    local result = originalApply(self, ...)
    syncAutoDrink()
    return result
end

Events.OnGameStart.Add(syncAutoDrink)
Events.OnCreatePlayer.Add(syncAutoDrink)
