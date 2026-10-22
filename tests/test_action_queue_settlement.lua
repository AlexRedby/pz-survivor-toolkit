-- Shared settlement owns cancellation bookkeeping, never item/equipment effects.
local function setup()
    local root = {items = {}}
    function root:getItemById(id) return self.items[id] end
    local player = {getInventory = function() return root end, isDead = function(self) return self.dead == true end}
    local token = {}
    local current = {character = player, toolkitQueueOperation = token}
    local tail = {character = player, toolkitQueueOperation = {}}
    local queue = {character = player, current = current, queue = {current, tail}}
    local source = {exists = true, reachable = true}
    function source:isExistYet() return self.exists end
    local constructions, guards, discards, releases = 0, 0, {}, 0
    PZSurvivorToolkit = {
        Settings = {actionQueue = function() return player.queueEnabled ~= false end},
        ActionQueueOperations = {isTransfer = function(action) return action.Type == 'ISInventoryTransferAction' end},
        ActionQueuePolicy = {isCarriedContainer = function(destination) return destination.carried == true end},
        BulkActions = {guardTransfer = function() guards = guards + 1 end}}
    ISTimedActionQueue = {queues = {[player] = queue}, getTimedActionQueue = function(character)
        return ISTimedActionQueue.queues[character]
    end}
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
        function value:getFullType() return self.fullType or 'Base.Test' end
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

-- Deferred native producers retain historical ownership even after their source
-- actions have left the queue. They do not inherit permission to replay effects.
do
    local s = setup()
    local first, second = s.item(21, s.root), s.item(22, s.root)
    local other = {}
    s.token.toolkitPickups = {[first] = s.source}
    other.toolkitPickups = {[second] = s.source}
    local scope = s.settlement.deferred(s.player, s.token)
    assert(scope.character == s.player and scope.token == s.token and scope.queue == s.queue
        and scope.generation == 0 and scope.phase == 'prepare' and not scope.mixed)
    local original = s.action()
    local contract = {knownInputs = true, items = {[21] = true}, containerOwners = {[91] = true}}
    s.settlement.remember(scope, original, contract)
    -- A repeated accepted action cannot gain new claims from later mutation.
    contract.items[22], contract.containerOwners[92] = true, true
    s.token.toolkitPickups[first] = {}
    s.settlement.remember(scope, original, contract)
    assert(scope.tasks[s.token].items[21] and scope.tasks[s.token].items[91]
        and not scope.tasks[s.token].items[22] and not scope.tasks[s.token].items[92],
        'remember must snapshot claims once per accepted source action')
    local following = {character = s.player, toolkitQueueOperation = other}
    s.settlement.remember(scope, following, {knownInputs = true, items = {[22] = true}})
    assert(scope.mixed and s.settlement.owner(scope, 21, 'Base.Test', s.source) == s.token
        and s.settlement.owner(scope, 22, 'Base.Test', s.source) == other)
    for action in pairs(scope.seen) do scope.seen[action] = nil end
    s.queue.queue, s.queue.current = {}, nil
    assert(s.settlement.owner(scope, 21, 'Base.Test', s.source) == s.token,
        'pruning source membership must not discard its delayed pickup history')
    assert(not s.settlement.owner(scope, 21, 'Base.Other', s.source)
        and not s.settlement.owner(scope, 21, 'Base.Test', {})
        and not s.settlement.owner(scope, 999, 'Base.Test', s.source),
        'a pickup owner requires the same ID, full type and original destination')
    local shared = s.settlement.context(scope)
    local again = s.settlement.context(scope)
    local unique = s.settlement.context(scope, s.token)
    assert(shared.settlement == scope and shared.character == s.player and shared.queue == s.queue
        and shared.generation == 0 and shared.sharedCleanup and shared.token == again.token
        and shared.token ~= s.token and shared.token ~= other,
        'mixed delayed cleanup needs one stable independent restore token')
    assert(unique.token == s.token and not unique.sharedCleanup)
    local unknown = s.settlement.context(scope, {})
    assert(not unknown,
        'an unrecognized requested owner cannot acquire exclusive cleanup')
    local required, optional = s.settlement.obligation(shared), s.settlement.obligation(unique)
    local unlabelled = {}; for key, value in pairs(shared) do unlabelled[key] = value end
    unlabelled.sharedCleanup = nil
    assert(s.settlement.required(s.settlement.obligation(unlabelled)),
        'required cleanup derives from the private shared owner, not a copied presentation flag')
    assert(s.settlement.required(required) and not s.settlement.required(optional)
        and not s.settlement.required({sharedCleanup = true}),
        'only a private shared cleanup obligation is required')
    s.token.toolkitCancelled = true
    other.toolkitCancelled = true
    assert(not s.settlement.isLive(unique) and s.settlement.isLive(shared),
        'cancelling a unique owner must leave shared native cleanup live')
    assert(first.container == s.root and second.container == s.root and s.counts() == 0,
        'deferred ownership bookkeeping must not construct or replay native effects')
end

for _, mode in ipairs({'shared-item', 'container-owner', 'missing-contract', 'unknown-inputs', 'dynamic-inputs',
    'dynamic-types', 'same-pickup'}) do
    local s = setup(); local value = s.item(31, s.root)
    s.token.toolkitPickups = {[value] = s.source}
    local scope = s.settlement.deferred(s.player, s.token)
    s.settlement.remember(scope, s.current, {knownInputs = true, items = {[31] = true}})
    local other = {}
    local contract = {knownInputs = true, items = {}}
    if mode == 'shared-item' then contract.items[31] = true
    elseif mode == 'container-owner' then contract.containerOwners = {[31] = true}
    elseif mode == 'missing-contract' then contract = nil
    elseif mode == 'unknown-inputs' then contract.knownInputs = false
    elseif mode == 'dynamic-inputs' then contract.dynamicInputs = {['Base.Test'] = true}
    elseif mode == 'dynamic-types' then contract.dynamicInputsByType = {['Base.Test'] = true}
    else other.toolkitPickups = {[value] = s.source} end
    s.settlement.remember(scope, {character = s.player, toolkitQueueOperation = other}, contract)
    assert(not s.settlement.owner(scope, 31, 'Base.Test', s.source),
        mode .. ': another task claim must prevent exclusive pickup ownership')
    local context = s.settlement.context(scope)
    s.token.toolkitCancelled = true
    assert(context.sharedCleanup and s.settlement.isLive(context),
        mode .. ': ambiguous native cleanup must survive cancellation of one task')
end

for _, mode in ipairs({'destination', 'full-type'}) do
    local s = setup(); local original, conflicting = s.item(32, s.root), s.item(32, s.root)
    local destination = s.source
    if mode == 'destination' then destination = {} else conflicting.fullType = 'Base.Other' end
    s.token.toolkitPickups = {[original] = s.source}
    local scope = s.settlement.deferred(s.player, s.token)
    s.settlement.remember(scope, s.current, {knownInputs = true, items = {[32] = true}})
    s.token.toolkitPickups = {[conflicting] = destination}
    s.settlement.remember(scope, s.action(), {knownInputs = true, items = {[32] = true}})
    assert(not s.settlement.owner(scope, 32, 'Base.Test', s.source)
        and not s.settlement.owner(scope, 32, conflicting:getFullType(), destination),
        mode .. ': conflicting same-ID pickup history cannot select an arbitrary exclusive owner')
end

for _, mode in ipairs({'closed', 'generation', 'replacement', 'world', 'dead', 'disabled',
    'cancelled', 'context-owner', 'context-queue', 'context-generation', 'context-character', 'forged'}) do
    local s = setup()
    local scope = s.settlement.deferred(s.player, s.token)
    s.settlement.remember(scope, s.current, {knownInputs = true, items = {}})
    local context = s.settlement.context(scope)
    assert(s.settlement.isLive(context), mode .. ': initial context must be live')
    if mode == 'closed' then s.settlement.close(scope)
    elseif mode == 'generation' then s.queue.toolkitOperationGeneration = 1
    elseif mode == 'replacement' then ISTimedActionQueue.queues[s.player] = {character = s.player, queue = {}}
    elseif mode == 'world' then ISTimedActionQueue.queues = {}
    elseif mode == 'dead' then s.player.dead = true
    elseif mode == 'disabled' then s.player.queueEnabled = false
    elseif mode == 'cancelled' then s.token.toolkitCancelled = true
    elseif mode == 'context-owner' then context.token = {}
    elseif mode == 'context-queue' then context.queue = {}
    elseif mode == 'context-generation' then context.generation = 1
    elseif mode == 'context-character' then context.character = {}
    else context = {settlement = {}, character = s.player, queue = s.queue, generation = 0, token = s.token} end
    assert(not s.settlement.isLive(context), mode .. ': stale or unproven deferred context must not adopt native work')
    if mode == 'closed' then
        assert(not s.settlement.isLive(s.settlement.context(scope)),
            'rebuilding a context cannot reopen a retired deferred scope')
    end
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
print('Shared settlement: deferred ownership claims/lifetimes, ordered required cleanup, exact-ID returns, no effect replay, duplicate completion, owned props and lost resources passed.')
