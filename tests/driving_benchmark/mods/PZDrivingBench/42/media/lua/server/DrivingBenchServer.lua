if isClient() then return end
local F = require "DrivingBenchFixture"
local requests = setmetatable({}, {__mode="k"})

Events.OnClientCommand.Add(function(module, command, player)
    if module ~= F.MODULE or command ~= "prepare" or not isServer() or not F.allowed() or not player then return end
    local now = getTimestampMs()
    local bucket = requests[player]
    if not bucket or now < bucket.started or now-bucket.started >= 60000 then
        bucket = {started=now, count=0}
        requests[player] = bucket
    end
    local result
    if bucket.count >= 20 or bucket.last and now-bucket.last < 1000 then
        result = {status="error", reason="Benchmark preparation rate limit; wait before retrying.", retryable=true}
    else
        bucket.count = bucket.count + 1
        bucket.last = now
        result = F.prepare(player)
    end
    sendServerCommand(player, F.MODULE, result.status, result)
end)
