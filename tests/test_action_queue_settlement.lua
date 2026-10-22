-- Shared settlement owns cancellation bookkeeping, never item/equipment effects.
local function setup()
    local root = {items = {}}
    function root:getItemById(id) return self.items[id] end
    local player = {getInventory = function() return root end}
    local token = {}
    local current = {character = player, toolkitQueueOperation = token}
    local tail = {character = player, toolkitQueueOperation = {}}
    local queue = {character = player, current = current, queue = {current, tail}}
    local source = {exists = true, reachable = true}
    function source:isExistYet() return self.exists end
    local constructions, guards, discards, releases = 0, 0, {}, 0
    PZSurvivorToolkit = {
        ActionQueueOperations = {isTransfer = function(action) return action.Type == 'ISInventoryTransferAction' end},
        ActionQueuePolicy = {isCarriedContainer = function(destination) return destination.carried == true end},
        BulkActions = {guardTransfer = function() guards = guards + 1 end}}
    ISInventoryPaneContextMenu = {getContainers = function() return {contains = function(_, destination) return destination.reachable end} end}
    ISInventoryTransferUtil = {newInventoryTransferAction = function(character, item, from, to)
        constructions = constructions + 1
        return {Type = 'ISInventoryTransferAction', character = character, item = item, srcContainer = from, destContainer = to,
            setAllowMissingItems = function(self, value) self.allowMissingItems = value end}
    end}
    isClient = function() return false end
    local settlement = assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueSettlement.lua'))()
    local function item(id, container)
        local value = {id = id, container = container}
        function value:getID() return self.id end
        function value:getContainer() return self.container end
        function value:getIsCraftingConsumed() return self.consumed end
        return value
    end
    local function action()
        return {character = player, toolkitQueueOperation = token}
    end
    local function discard(value, completed)
        if completed then assert(value == current); releases = releases + 1
        else discards[#discards + 1] = value end
    end
    return {root = root, player = player, token = token, current = current, tail = tail, queue = queue,
        source = source, item = item, action = action, discard = discard, settlement = settlement,
        counts = function() return constructions, guards, #discards, releases end}
end

do
    local s = setup()
    local old = s.item(10, nil)
    local live = s.item(10, s.root)
    s.root.items[10] = live
    s.token.toolkitPickups = {[old] = s.source}
    local first, body, second = s.action(), s.action(), s.action()
    first.restore, second.restore = true, true
    local nativeReturn = s.action()
    nativeReturn.Type, nativeReturn.item = 'ISInventoryTransferAction', live
    nativeReturn.srcContainer, nativeReturn.destContainer, nativeReturn.allowMissingItems = s.root, s.source, true
    s.queue.queue = {s.current, first, body, nativeReturn, second, s.tail}
    s.settlement.register('fixture-equipment', {retain = function(value) return value.restore == true end})
    local request = {action = s.current, token = s.token}
    assert(s.settlement.finish(s.queue, request, s.discard))
    local returned = s.queue.queue[4]
    assert(#s.queue.queue == 5 and s.queue.queue[1] == s.current and s.queue.queue[2] == first
        and s.queue.queue[3] == second and s.queue.queue[5] == s.tail,
        'retained native cleanup must keep its order before the unchanged independent tail')
    assert(returned.item == live and returned.srcContainer == s.root and returned.destContainer == s.source
        and returned.allowMissingItems and old.container == nil and live.container == s.root,
        'resolve the exact surviving object once; settlement itself cannot move or recreate it')
    local n, guards, dropped, released = s.counts()
    assert(n == 1 and guards == 1 and dropped == 2 and released == 1)
    for _, value in ipairs({first, second, returned}) do
        assert(s.settlement.isCleanup(value) and value.toolkitQueueOperation ~= s.token)
    end
    assert(not s.settlement.isCleanup(s.tail) and not s.settlement.isCleanup({toolkitQueueReturn = true}))
    assert(request.settlement.phase == 'scheduled' and #request.settlement.obligations == 3
        and request.settlement.obligations[1].kind == 'cleanup'
        and request.settlement.obligations[3].kind == 'return'
        and request.settlement.obligations[3].itemId == 10)
    assert(not s.settlement.finish(s.queue, request, s.discard), 'a repeated completion cannot settle or allocate twice')
    local n2, _, dropped2, released2 = s.counts()
    assert(n2 == n and dropped2 == dropped and released2 == released and #s.queue.queue == 5)
end

for _, mode in ipairs({'absent', 'consumed', 'nested', 'unreachable', 'removed-source'}) do
    local s = setup(); local old, live = s.item(11, nil), s.item(11, s.root)
    s.root.items[11] = live; s.token.toolkitPickups = {[old] = s.source}
    local body = s.action(); s.queue.queue = {s.current, body, s.tail}
    if mode == 'absent' then s.root.items[11] = nil
    elseif mode == 'consumed' then live.consumed = true
    elseif mode == 'nested' then live.container = {}
    elseif mode == 'unreachable' then s.source.reachable = false
    else s.source.exists = false end
    assert(s.settlement.finish(s.queue, {action = s.current, token = s.token}, s.discard))
    local n, _, dropped, released = s.counts()
    assert(n == 0 and dropped == 1 and released == 1 and #s.queue.queue == 2 and s.queue.queue[2] == s.tail,
        mode .. ': unavailable returns must not recreate resources or discard the independent tail')
end

do
    local s = setup(); local live = s.item(12, s.root); s.root.items[12] = live
    s.token.toolkitPickups = {[live] = s.source}
    local cleanup = s.action(); s.queue.queue = {s.current, cleanup, s.tail}
    local calls = 0
    s.settlement.register('fixture-owned-prop', {retain = function() error('superseded registration must not run') end})
    s.settlement.register('fixture-owned-prop', {retain = function(value) calls = calls + 1; return value == cleanup end,
        ownsPickup = function(current, id) return current == s.current and id == 12 end})
    assert(s.settlement.finish(s.queue, {action = s.current, token = s.token}, s.discard))
    local n = s.counts()
    assert(n == 0 and calls == 1 and s.queue.queue[2] == cleanup and s.queue.queue[3] == s.tail,
        'the family that already owns a prop return must not receive another generic transfer')
end

for _, mode in ipairs({'head', 'owner', 'token'}) do
    local s = setup(); local body = s.action(); s.queue.queue = {s.current, body, s.tail}
    local request = {action = s.current, token = s.token}
    if mode == 'head' then s.queue.current = s.tail
    elseif mode == 'owner' then s.current.character = {}
    else request.token = {} end
    assert(not s.settlement.finish(s.queue, request, s.discard))
    local n, _, dropped, released = s.counts()
    assert(n == 0 and dropped == 0 and released == 0 and #s.queue.queue == 3 and not request.settlement,
        mode .. ': stale settlement ownership cannot touch another native operation')
end
print('Shared settlement: ordered required cleanup, exact-ID returns, no effect replay, duplicate completion, owned props, lost resources and stale ownership passed.')
