if not isServer() then return end
local Service = require "PZSurvivorWishlist/Service"
if PZSurvivorWishlist.serverInstalled then return end
PZSurvivorWishlist.serverInstalled = true
local versions, requests = {}, {}
local nextRefresh = 0

local function send(player, payload, version)
    sendServerCommand(player, "PZSurvivorWishlist", "snapshot", payload)
    version.error = payload.error
    versions[player] = version
end
local function refresh(except)
    local online = getOnlinePlayers()
    -- Kahlua ignores weak keys; retain state only for players still online.
    local currentVersions, currentRequests = {}, {}
    for i = 0, online:size() - 1 do
        local player = online:get(i)
        if player ~= except then
            local payload, version = Service.snapshot(player, versions[player])
            if payload then send(player, payload, version) end
        end
        currentVersions[player], currentRequests[player] = versions[player], requests[player]
    end
    versions, requests = currentVersions, currentRequests
end
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "PZSurvivorWishlist" or command ~= "request" or not player then return end
    local now = getTimestampMs()
    local bucket = requests[player]
    if not bucket or now - bucket.start >= 1000 then bucket = {start = now, count = 0}; requests[player] = bucket end
    bucket.count = bucket.count + 1
    if bucket.count > 8 then
        -- Reply once per burst; additional flood traffic does no model work.
        if bucket.count == 9 then
            local payload, version = Service.snapshot(player)
            payload.error = "rate_limited"
            if type(args) == "table" and type(args.requestId) == "string" and #args.requestId > 0
                and #args.requestId <= 64 and not args.requestId:find("%c") then payload.requestId = args.requestId end
            send(player, payload, version)
        end
        return
    end
    local payload, changed, version = Service.request(player, args)
    send(player, payload, version)
    if changed then refresh(player) end
end)
Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now < nextRefresh then return end
    nextRefresh = now + 5000
    refresh()
end)
