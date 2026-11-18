local config = require 'QueueTestSelection'
if config.suite ~= 'loot-demand-peers' or not isServer() then return end

local peers, ready, sent, observed = {}, {}, {}, {}
local network, release, done, startedAt

local function check(value, message)
    assert(value, 'loot peers: ' .. message)
end

local function fail(problem)
    done = true
    print('[LOOT_PEERS] FAIL ' .. tostring(problem))
end

local function both(values)
    return values.client1 and values.client2
end

local function prepare()
    local origin = peers.client1:getSquare()
    local square
    for dx = 5, 7 do
        local candidate = getCell():getGridSquare(origin:getX() + dx, origin:getY(), origin:getZ())
        if candidate and candidate:getFloor() then
            square = candidate
            break
        end
    end
    check(square, 'no loaded square outside nearby scan')
    local object = IsoObject.new(getCell(), square, assert(getSprite(lootDemandSprite('bin'))))
    object:createContainersFromSpriteProperties()
    object:setName('LootDemandSameBinPeers')
    square:AddTileObject(object)
    local current = assert(object:getContainer())
    check(lootDemandPending(current), 'source not pending')
    lootDemandAutomatic(object, false)
    lootDemandAutomatic(object, true)
    check(current:isEmpty() and not current:isExplored(), 'loader did not defer source')
    network = {object = object, container = current, calls = 0}
    network.callback = function(room, kind, container)
        if container ~= current then return end
        network.calls = network.calls + 1
        check(network.calls == 1, 'duplicate generation')
        local sentinel = assert(current:AddItem('Base.Nails'))
        local bag = assert(current:AddItem('Base.Bag_Schoolbag'))
        local child = assert(bag:getInventory():AddItem('Base.Bandage'))
        network.sentinel = sentinel:getID()
        network.bag = bag:getID()
        network.child = child:getID()
        print('[LOOT_PEERS] FILL callback=1 at=' .. getTimestampMs() .. ' sentinel=' .. network.sentinel
            .. ' bag=' .. network.bag .. ' child=' .. network.child)
    end
    Events.OnFillContainer.Add(network.callback)
    object:transmitCompleteItemToClients()
    local args = {
        x = square:getX(), y = square:getY(), z = square:getZ(),
        index = object:getObjectIndex(), name = object:getName(),
    }
    for _, peer in pairs(peers) do
        sendServerCommand(peer, 'LootPeers', 'Probe', args)
    end
    print('[LOOT_PEERS] PENDING x=' .. args.x .. ' y=' .. args.y
        .. ' z=' .. args.z .. ' index=' .. args.index)
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= 'LootPeers' or done then return end
    local ok, problem = pcall(function()
        local role = player and player:getUsername()
        check(role == 'client1' or role == 'client2', 'foreign actor')
        check(type(args) == 'table', 'bad client args')
        if command == 'Join' then
            check(args.ready == true, 'join missing readiness')
            check(not peers[role], 'duplicate join')
            peers[role] = player
            startedAt = startedAt or getTimestampMs()
            return
        end
        check(network and peers[role] == player, 'unprepared actor')
        if command == 'Ready' then
            check(not ready[role] and args.empty == true and args.explored == false, 'bad readiness')
            ready[role] = true
        elseif command == 'Sent' then
            check(release and not sent[role] and args.requests == 2
                and type(args.at) == 'number' and args.at >= release, 'bad native request witness')
            sent[role] = args.at
        elseif command == 'Observe' then
            check(sent[role] and not observed[role] and args.sentAt == sent[role]
                and args.receivedAt >= args.sentAt, 'bad observation')
            check(network.calls == 1 and network.container:isExplored(),
                'generation not completed exactly once')
            local rows = lootDemandRows(network.container)
            local ids, rowSet = {}, {}
            for row in string.gmatch(rows, '[^\n]+') do
                local leaf = string.match(row, '([^/]+)$')
                local id = string.match(leaf, '^(%-?%d+):')
                check(id and not ids[id], 'duplicate recursive item identity')
                ids[id] = true
                rowSet[row] = true
            end
            check(type(args.rows) == 'string' and args.rows == rows
                and args.fingerprint == lootDemandFingerprint(network.container), 'replicated identities differ')
            network.rows = network.rows or rows
            check(rows == network.rows, 'authority changed between clients')
            check(rowSet[tostring(network.sentinel) .. ':Base.Nails'], 'lost original root sentinel')
            local bagRow = tostring(network.bag) .. ':Base.Bag_Schoolbag'
            check(rowSet[bagRow], 'lost original root bag')
            check(rowSet[bagRow .. '/' .. tostring(network.child) .. ':Base.Bandage'],
                'lost original nested child or parent')
            observed[role] = args
            print('[LOOT_PEERS] MATCH role=' .. role .. ' sent_at=' .. args.sentAt
                .. ' received_at=' .. args.receivedAt .. ' sha=' .. args.fingerprint)
        else
            error('unexpected command')
        end
    end)
    if not ok then fail(problem) end
end)

Events.OnTick.Add(function()
    if done or not startedAt then return end
    local ok, problem = pcall(function()
        check(getTimestampMs() - startedAt < 150000, 'server timeout')
        if both(peers) and not network then
            prepare()
            return
        end
        if network and both(ready) and not release then
            check(network.calls == 0 and network.container:isEmpty()
                and not network.container:isExplored(), 'early generation')
            release = getTimestampMs() + 1800
            for _, peer in pairs(peers) do
                sendServerCommand(peer, 'LootPeers', 'Release', {at = release})
            end
            print('[LOOT_PEERS] RELEASE at=' .. release)
            return
        end
        if both(observed) then
            check(network.calls == 1, 'repeat native request generated again')
            check(lootDemandRows(network.container) == network.rows, 'late authoritative item loss')
            check(math.max(sent.client1, sent.client2)
                <= math.min(observed.client1.receivedAt, observed.client2.receivedAt),
                'requests did not overlap before first observed contents')
            local delta = math.abs(sent.client1 - sent.client2)
            print('[LOOT_PEERS] PASS same-bin fills=1 send_delta_ms=' .. delta
                .. ' sha=' .. lootDemandFingerprint(network.container)
                .. ' rows=' .. string.gsub(network.rows, '\n', ';'))
            Events.OnFillContainer.Remove(network.callback)
            network.object:getSquare():transmitRemoveItemFromSquare(network.object)
            for _, peer in pairs(peers) do
                sendServerCommand(peer, 'LootPeers', 'Complete', {ok = true})
            end
            done = true
        end
    end)
    if not ok then fail(problem) end
end)
