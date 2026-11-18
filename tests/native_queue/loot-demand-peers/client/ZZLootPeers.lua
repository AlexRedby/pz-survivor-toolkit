local config = require 'QueueTestSelection'
if config.suite ~= 'loot-demand-peers' then return end

local preflight = require 'QueuePreflight'
local started, sent, ready, requested, observed, done = false, false, false, false, false, false
local probe, release, at, sendAt, receiveAt

local function fail(problem)
    done = true
    print('[LOOT_PEERS] FAIL ' .. tostring(problem))
end

local function container()
    if not probe then return end
    local square = getCell():getGridSquare(probe.x, probe.y, probe.z)
    if not square or square:getObjects():size() <= probe.index then return end
    local object = square:getObjects():get(probe.index)
    if object:getName() ~= probe.name then return end
    return object:getContainer()
end

preflight.onGameStart(Events, function()
    started = true
end)

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= 'LootPeers' or done then return end
    local ok, problem = pcall(function()
        assert(type(args) == 'table', 'bad server arguments')
        if command == 'Probe' then
            assert(sent and not probe, 'unexpected probe')
            probe = args
        elseif command == 'Release' then
            assert(ready and not release, 'unexpected release')
            release = args.at
        elseif command == 'Complete' then
            assert(observed and args.ok == true, 'unverified completion')
            done = true
            print('[LOOT_PEERS] COMPLETE same-bin')
        else
            error('unexpected command')
        end
    end)
    if not ok then fail(problem) end
end)

preflight.onTick(Events, function()
    if done or not started or not isIngameState() then return end
    local player = getPlayer()
    if not player or player:isDead() or not player:getSquare()
            or not isClient() or player:getOnlineID() < 0 then return end
    local ok, problem = pcall(function()
        assert(lootDemandInstalled(), 'hooks inactive')
        if not sent then
            sent = true
            at = getTimestampMs()
            sendClientCommand('LootPeers', 'Join', {ready = true})
            return
        end
        assert(getTimestampMs() - at < 150000, 'peer response timeout')
        local current = container()
        if not current then return end
        if not ready then
            assert(current:isEmpty() and not current:isExplored(), 'source filled before common release')
            ready = true
            sendClientCommand('LootPeers', 'Ready', {empty = true, explored = false})
            return
        end
        if release and not requested and getTimestampMs() >= release then
            assert(current:isEmpty() and not current:isExplored(), 'source filled before request')
            requested = true
            sendAt = getTimestampMs()
            current:requestServerItemsForContainer()
            current:requestServerItemsForContainer()
            sendClientCommand('LootPeers', 'Sent', {at = sendAt, requests = 2})
            print('[LOOT_PEERS] SENT at=' .. sendAt .. ' requests=2')
        elseif requested and not observed and not current:isEmpty() then
            observed = true
            receiveAt = getTimestampMs()
            local rows = lootDemandRows(current)
            print('[LOOT_PEERS] OBSERVED sent_at=' .. sendAt .. ' received_at=' .. receiveAt
                .. ' rows=' .. string.gsub(rows, '\n', ';'))
            sendClientCommand('LootPeers', 'Observe', {
                rows = rows, fingerprint = lootDemandFingerprint(current),
                sentAt = sendAt, receivedAt = receiveAt,
            })
        end
    end)
    if not ok then fail(problem) end
end)
