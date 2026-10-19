if not isServer() or not getActivatedMods():contains("MoodleFramework")
    or getActivatedMods():contains("MedicineMoodlesB42") then return end
local Effects = require "PZSurvivorToolkit/MedicineEffects"
if Effects.serverInstalled then return end
Effects.serverInstalled = true
local lastRequests = {}

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "PZSurvivorToolkitMedicine" or command ~= "Read" or player:isDead() then return end
    local request = type(args) == "table" and args.request
    if type(request) ~= "number" or not (request >= 1 and request <= 2147483647 and request == math.floor(request)) then return end
    local now = getTimestampMs()
    -- Kahlua ignores weak keys; retain only the current throttle window.
    for previous, receivedAt in pairs(lastRequests) do
        if now - receivedAt >= 750 then lastRequests[previous] = nil end
    end
    if lastRequests[player] and now - lastRequests[player] < 750 then return end
    lastRequests[player] = now
    local values = Effects.capture(player)
    values.request, values.onlineID = request, player:getOnlineID()
    -- The authenticated command player is the only possible source and recipient.
    sendServerCommand(player, "PZSurvivorToolkitMedicine", "State", values)
end)
