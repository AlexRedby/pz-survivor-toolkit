require "OptionScreens/MainOptions"

local pendingPlayers = {}

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
Events.OnCreatePlayer.Add(function(playerNum, player)
    if not isClient() then return end
    syncAutoDrink()
    -- ConnectedPacket applies the server flag after this event returns.
    pendingPlayers[playerNum] = player
end)

Events.OnPlayerUpdate.Add(function(player)
    if not isClient() then return end
    local playerNum = player:getPlayerNum()
    if pendingPlayers[playerNum] ~= player or getSpecificPlayer(playerNum) ~= player then return end
    player:setAutoDrink(getCore():getOptionAutoDrink())
    pendingPlayers[playerNum] = nil
end)
