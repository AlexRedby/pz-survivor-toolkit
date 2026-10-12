if not isServer() then return end
local Service = require "PZSurvivorWishlist/Service"
if PZSurvivorWishlist.serverInstalled then return end
PZSurvivorWishlist.serverInstalled = true
local snapshots = setmetatable({}, {__mode = "k"})
local requests = setmetatable({}, {__mode = "k"})
local nextRefresh = 0

local function same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not same(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function send(player, payload)
    sendServerCommand(player, "PZSurvivorWishlist", "snapshot", payload)
    snapshots[player] = {lists = payload.lists, error = payload.error, recipient = payload.recipient}
end
local function refresh(except)
    local online = getOnlinePlayers()
    for i = 0, online:size() - 1 do
        local player = online:get(i)
        if player ~= except then
            local payload = Service.snapshot(player)
            if not same(payload, snapshots[player]) then send(player, payload) end
        end
    end
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
            local payload = Service.snapshot(player)
            payload.error = "rate_limited"
            if type(args) == "table" and type(args.requestId) == "string" and #args.requestId > 0
                and #args.requestId <= 64 and not args.requestId:find("%c") then payload.requestId = args.requestId end
            send(player, payload)
        end
        return
    end
    local payload, changed = Service.request(player, args)
    send(player, payload)
    if changed then refresh(player) end
end)
Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now < nextRefresh then return end
    nextRefresh = now + 5000
    refresh()
end)
