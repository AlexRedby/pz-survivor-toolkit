if not isServer() or not getActivatedMods():contains("MedicineMoodlesB42") then return end
local Effects = require "PZSurvivorToolkit/MedicineEffects"
local lastRequests = setmetatable({}, {__mode = "k"})

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "PZSurvivorToolkitMedicine" or command ~= "Read" or player:isDead() then return end
    local request = type(args) == "table" and args.request
    if type(request) ~= "number" or request ~= math.floor(request) or request < 1 or request > 2147483647 then return end
    local now = getTimestampMs()
    if lastRequests[player] and now - lastRequests[player] < 750 then return end
    lastRequests[player] = now
    local values = Effects.capture(player)
    values.request, values.onlineID = request, player:getOnlineID()
    -- The authenticated command player is the only possible source and recipient.
    sendServerCommand(player, "PZSurvivorToolkitMedicine", "State", values)
end)
