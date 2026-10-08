-- The server loads the host's options.ini, but each player's flag must decide.
-- Also restore this gate after reloadoptions; never save the host's options.
if not isServer() then return end

local function enablePlayerAutoDrink()
    local core = getCore()
    if not core:getOptionAutoDrink() then core:setOptionAutoDrink(true) end
end

Events.OnServerStarted.Add(enablePlayerAutoDrink)
Events.OnTick.Add(enablePlayerAutoDrink)
