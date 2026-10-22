-- Shared settlement owns cancellation bookkeeping, never item/equipment effects.
local function setup(client)
    local root = {items = {}}
    function root:getItemById(id) return self.items[id] end
    local player = {getInventory = function() return root end, isDead = function(self) return self.dead == true end,
        getPlayerNum = function() return 0 end, getOnlineID = function() return 101 end}
    local token = {}
    local current = {character = player, toolkitQueueOperation = token, action = {}}
    local tail = {character = player, toolkitQueueOperation = {}}
    local queue = {character = player, current = current, queue = {current, tail}}
    local source = {exists = true, reachable = true, items = {}}
    function source:isExistYet() return self.exists end
    function source:getItemById(id) return self.items[id] end
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
    local clock, receive = 100, nil
    getTimestampMs = function() return clock end
    getSpecificPlayer = function(slot) if slot == 0 then return player end end
    Events = {OnServerCommand = {Add = function(callback) receive = callback end}}
    isClient = function() return client == true end
    local transaction = {done = true, rejected = false, calls = 0}
    isItemTransactionDone = function(id)
        transaction.calls = transaction.calls + 1
        transaction.lastId = id
        return transaction.done
    end
    isItemTransactionRejected = function(id)
        transaction.calls = transaction.calls + 1
        transaction.lastId = id
        return transaction.rejected
    end
    instanceof = function(value, kind) return type(value) == 'table' and value.class == kind end
    local loaded = {}
    require = function(name)
        if name == 'PZSurvivorToolkit/ActionQueueAcknowledgements' then
            if not loaded[name] then
                loaded[name] = assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/' .. name .. '.lua'))()
            end
            return loaded[name]
        end
    end
    local acknowledgements = require('PZSurvivorToolkit/ActionQueueAcknowledgements')
    local function receipt(action, state, receiptToken, transaction)
        receive('PZSurvivorToolkitActions', 'State', {protocol = 1, player = 101,
            transaction = transaction or action.toolkitNativeTransaction, kind = action.toolkitNativeKind,
            token = receiptToken or '11111111-1111-4111-8111-111111111111', state = state})
    end
    local settlement = assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueSettlement.lua'))()
    local function item(id, container)
        local value = {id = id, container = container, class = 'InventoryItem'}
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
        acknowledgements = acknowledgements, receipt = receipt, transaction = transaction,
        advance = function(ms) clock = clock + ms end,
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

-- A generic return needs one unambiguous ID/type/source tuple. Other returns
-- and the independent tail must survive when one item's history is unsafe.
for _, conflict in ipairs({'live-type', 'pickup-type', 'pickup-source', 'queued-type', 'queued-source'}) do
    local s = setup()
    local old, duplicate = s.item(61, nil), s.item(61, nil)
    local live, other = s.item(61, s.root), s.item(62, s.root)
    s.root.items[61], s.root.items[62] = live, other
    s.token.toolkitPickups = {[old] = s.source, [other] = s.source}
    local alternative = {isExistYet = function() return true end, reachable = true}
    local body = s.action()
    s.queue.queue = {s.current, body, s.tail}
    if conflict == 'live-type' then live.fullType = 'Base.Other'
    elseif conflict:match('^pickup') then
        if conflict == 'pickup-type' then duplicate.fullType = 'Base.Other' end
        s.token.toolkitPickups[duplicate] = conflict == 'pickup-source' and alternative or s.source
    else
        if conflict == 'queued-type' then duplicate.fullType = 'Base.Other' end
        local nativeReturn = s.action()
        nativeReturn.Type, nativeReturn.item = 'ISInventoryTransferAction', duplicate
        nativeReturn.srcContainer = s.root
        nativeReturn.destContainer = conflict == 'queued-source' and alternative or s.source
        nativeReturn.allowMissingItems = true
        table.insert(s.queue.queue, 3, nativeReturn)
    end
    assert(s.settlement.finish(s.queue, {action = s.current, token = s.token}, s.discard))
    assert(#s.queue.queue == 3 and s.queue.queue[1] == s.current and s.queue.queue[3] == s.tail
        and s.queue.queue[2].item == other and s.queue.queue[2].destContainer == s.source
        and s.counts() == 1,
        conflict .. ': ambiguous or changed-type returns must be skipped without losing a safe return or the tail')
    assert(live.container == s.root and other.container == s.root,
        conflict .. ': settlement must not execute either native transfer')
end

do
    local s = setup()
    local old, duplicate, live = s.item(63, nil), s.item(63, nil), s.item(63, s.root)
    s.root.items[63] = live
    s.token.toolkitPickups = {[old] = s.source, [duplicate] = s.source}
    local nativeReturn = s.action()
    nativeReturn.Type, nativeReturn.item = 'ISInventoryTransferAction', old
    nativeReturn.srcContainer, nativeReturn.destContainer, nativeReturn.allowMissingItems = s.root, s.source, true
    s.queue.queue = {s.current, nativeReturn, s.tail}
    assert(s.settlement.finish(s.queue, {action = s.current, token = s.token}, s.discard))
    local returned = s.queue.queue[2]
    assert(#s.queue.queue == 3 and s.queue.queue[3] == s.tail and returned.item == live
        and returned.srcContainer == s.root and returned.destContainer == s.source and s.counts() == 1,
        'duplicate exact tuples must produce one return using the surviving same-ID/same-type proxy')
    assert(old.container == nil and duplicate.container == nil and live.container == s.root,
        'deduplication must not revive stale proxies or execute the return')
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
-- A completion receipt and the observed native effect are independent gates.
for _, order in ipairs({'receipt-first', 'effect-first'}) do
    local s = setup(true)
    local action = s.current
    action.toolkitNativeTransaction, action.toolkitNativeKind = 7, 'fixture'
    s.receipt(action, 'started')
    local proof = s.settlement.captureEffect(action)
    assert(proof and s.settlement.effectState(proof, false) == 'waiting')
    s.queue.current, s.queue.queue = nil, {}
    if order == 'receipt-first' then
        s.receipt(action, 'completed')
        assert(s.settlement.effectState(proof, false) == 'waiting'
            and not s.settlement.confirmEffect(proof, false), 'receipt alone cannot prove the native effect')
    else
        assert(s.settlement.effectState(proof, true) == 'waiting'
            and not s.settlement.confirmEffect(proof, true), 'an observed effect alone cannot prove completion')
        s.receipt(action, 'completed')
    end
    assert(s.settlement.effectState(proof, true) == 'completed'
        and s.settlement.confirmEffect(proof, true), order .. ': correlated completion must survive leaving the queue')
    s.receipt(action, 'completed')
    assert(not s.settlement.confirmEffect(proof, true), 'duplicate receipts cannot grant another confirmation')
    assert(s.counts() == 0, 'effect correlation cannot construct or replay any native effect')
end

for _, terminal in ipairs({'canceled', 'rejected'}) do
    local s = setup(true); local action = s.current
    action.toolkitNativeTransaction, action.toolkitNativeKind = 8, 'fixture'
    s.receipt(action, 'started')
    local proof = s.settlement.captureEffect(action)
    s.queue.current, s.queue.queue = nil, {}
    s.receipt(action, terminal)
    assert(s.settlement.effectState(proof, true) == terminal and not s.settlement.confirmEffect(proof, true),
        terminal .. ': an inventory effect cannot override the authoritative terminal result')
end

for _, mutation in ipairs({'native', 'transaction', 'kind', 'character', 'generation', 'queue', 'reset', 'module', 'observe', 'receipt-token', 'receipt-state'}) do
    local s = setup(true); local action = s.current
    action.toolkitNativeTransaction, action.toolkitNativeKind = 9, 'fixture'
    s.receipt(action, 'started')
    local proof = s.settlement.captureEffect(action)
    if mutation == 'native' then action.action = {}
    elseif mutation == 'transaction' then action.toolkitNativeTransaction = 10
    elseif mutation == 'kind' then action.toolkitNativeKind = 'other'
    elseif mutation == 'character' then action.character = {}
    elseif mutation == 'generation' then s.queue.toolkitOperationGeneration = 1
    elseif mutation == 'queue' then ISTimedActionQueue.queues[s.player] = {character = s.player, queue = {}}
    elseif mutation == 'reset' then s.acknowledgements.reset(s.queue)
    elseif mutation == 'observe' then s.acknowledgements.observe = function() return 'completed' end
    elseif mutation == 'receipt-token' then s.acknowledgements.capture(action).token = '22222222-2222-4222-8222-222222222222'
    elseif mutation == 'receipt-state' then s.acknowledgements.capture(action).state = 'completed'
    else PZSurvivorToolkit.ActionQueueAcknowledgements = {capture = s.acknowledgements.capture, observe = s.acknowledgements.observe} end
    assert(not s.settlement.confirmEffect(proof, true), mutation .. ': changed receipt ancestry must fail closed')
    s.advance(30001)
    assert(s.settlement.effectState(proof, true) == 'unavailable'
        and not s.settlement.confirmEffect(proof, true), mutation .. ': invalid proof cannot wait indefinitely')
end

do
    local s = setup(true); local action = s.current
    action.toolkitNativeTransaction, action.toolkitNativeKind = 11, 'fixture'
    local proof = s.settlement.captureEffect(action)
    s.queue.current, s.queue.queue = nil, {}
    s.receipt(action, 'started'); s.receipt(action, 'completed')
    assert(not s.settlement.confirmEffect(proof, true), 'a late receipt cannot attach after unproven action left its queue')
    s.advance(30001)
    assert(s.settlement.effectState(proof, true) == 'unavailable')
end

do
    local s = setup(true); local action = s.current
    action.toolkitNativeTransaction, action.toolkitNativeKind = 12, 'fixture'
    s.receipt(action, 'started')
    local oldProof = s.settlement.captureEffect(action)
    s.acknowledgements.reset(s.queue)
    local nextAction = {character = s.player, action = {}, toolkitNativeTransaction = 12, toolkitNativeKind = 'fixture'}
    s.queue.current, s.queue.queue = nextAction, {nextAction}
    s.receipt(nextAction, 'started', '22222222-2222-4222-8222-222222222222')
    local nextProof = s.settlement.captureEffect(nextAction)
    s.receipt(nextAction, 'completed', '11111111-1111-4111-8111-111111111111')
    assert(not s.settlement.confirmEffect(oldProof, true) and not s.settlement.confirmEffect(nextProof, true),
        'reused signed-byte ID cannot consume a stale transaction token')
    s.receipt(nextAction, 'completed', '22222222-2222-4222-8222-222222222222')
    assert(s.settlement.confirmEffect(nextProof, true) and not s.settlement.confirmEffect(oldProof, true))
end

do
    local s = setup(true); local action = s.current
    action.toolkitNativeTransaction, action.toolkitNativeKind = 13, 'fixture'
    local proof = s.settlement.captureEffect(action)
    assert(s.settlement.effectState(proof, true) == 'waiting')
    s.receipt(action, 'started')
    assert(s.settlement.effectState(proof, false) == 'waiting', 'Started can bind only while exact native ownership remains current')
    s.queue.current, s.queue.queue = nil, {}
    s.receipt(action, 'completed')
    assert(s.settlement.confirmEffect(proof, true), 'a boundary preceding Started lost its later correlated completion')
end

do
    local s = setup(true); local action = s.current
    action.toolkitNativeTransaction, action.toolkitNativeKind = 14, 'fixture'
    s.receipt(action, 'started')
    local proof = s.settlement.captureEffect(action)
    s.queue.current, s.queue.queue = nil, {}
    s.advance(30001)
    assert(s.settlement.effectState(proof, true) == 'unavailable', 'a missing terminal receipt must expire')
    s.receipt(action, 'completed')
    assert(s.settlement.effectState(proof, true) == 'unavailable' and not s.settlement.confirmEffect(proof, true),
        'a late completed receipt and visible effect cannot revive a proof already retired at timeout')
end

for _, client in ipairs({false, true}) do
    local s = setup(client)
    s.player.queueEnabled = false
    local missing = s.settlement.captureEffect(s.current)
    assert(s.settlement.effectState(missing, false) == 'unavailable',
        'an unmarked native callback cannot wait for an unrelated later effect')
    local proof = s.settlement.captureEffect(s.current)
    local copied = {}; for key, value in pairs(proof) do copied[key] = value end
    assert(not s.settlement.confirmEffect(copied, true), 'a copied public proof cannot mint another effect confirmation')
    assert(s.settlement.effectState(proof, true) == 'completed' and s.settlement.confirmEffect(proof, true),
        'explicit native effect proof must remain available with queue management disabled')
    assert(not s.settlement.confirmEffect(proof, true) and not s.settlement.confirmEffect({}, true),
        'unmarked proof must also be private and once-only')
end
-- Native inventory transfers use their own item transaction protocol. Observe
-- one native group's outcome before perform removes it; never execute that payload.
local function returnFixture(client)
    local s = setup(client)
    local value = s.item(81, s.root)
    s.root.items[81] = value
    local scope = s.settlement.deferred(s.player, s.token)
    s.returnScope = scope
    s.settlement.remember(scope, s.current, {knownInputs = true, items = {[81] = true}})
    s.obligation = s.settlement.obligation(s.settlement.context(scope))
    local action = s.current
    action.Type, action.item = 'ISInventoryTransferAction', value
    action.srcContainer, action.destContainer = s.root, s.source
    action.transactionId, action.queueList = 17, {{items = {value}}}
    s.guardLive = true
    s.guard = function() return s.guardLive end
    s.finishReturn = function(succeeded)
        action.queueList = {} -- the native singleton perform consumed its batch
        return s.settlement.finishReturn(s.obligation, succeeded)
    end
    s.observeDestination = function(replacement)
        local observed = replacement or value
        s.root.items[81] = nil
        value.container = nil
        observed.container = s.source
        s.source.items[81] = observed
        return observed
    end
    return s
end

for _, client in ipairs({false, true}) do
    for _, timing in ipairs({'late-effect', 'late-finish', 'effect-at-finish'}) do
        local s = returnFixture(client)
        assert(s.settlement.beginReturn(s.current, s.obligation, s.guard))
        s.current.transactionId = 0
        if timing == 'late-effect' then
            assert(s.finishReturn(true))
            s.advance(30001)
            s.observeDestination()
        elseif timing == 'late-finish' then
            s.advance(30001)
            s.observeDestination()
            assert(s.finishReturn(true))
        else
            s.observeDestination()
            assert(s.finishReturn(true))
            s.advance(30001)
        end
        -- No polling occurs between capture and this first explicit late read.
        local expected = timing == 'effect-at-finish' and 'completed' or 'unavailable'
        assert(s.settlement.returnState(s.obligation) == expected,
            timing .. ': observation deadline must expire without polling while preserving effect earned at native finish')
        assert(s.counts() == 0 and s.queue.queue[2] == s.tail,
            timing .. ': timeout observation cannot change native effects or unrelated queue work')
    end
end

for _, client in ipairs({false, true}) do
    for _, order in ipairs({'effect-first', 'finish-first'}) do
        local s = returnFixture(client)
        local settlement, action, obligation = s.settlement, s.current, s.obligation
        assert(settlement.returnState(obligation) == nil and not settlement.finishReturn(obligation, true),
            'an uncaptured obligation has no native outcome')
        assert(settlement.beginReturn(action, obligation, s.guard))
        assert(not settlement.beginReturn(action, obligation, s.guard), 'duplicate begin cannot replace the captured transaction')
        assert(settlement.returnState(obligation) == 'waiting')
        local copied = {}; for key, value in pairs(obligation) do copied[key] = value end
        assert(settlement.returnState(copied) == nil and not settlement.finishReturn(copied, true),
            'a copied obligation cannot observe or finish the exact native return')
        action.transactionId = 0 -- native perform retires its original transaction
        if order == 'effect-first' then
            s.observeDestination()
            assert(settlement.returnState(obligation) == 'waiting', 'visible effect still needs its completed callback')
        end
        assert(s.finishReturn(true))
        assert(not settlement.finishReturn(obligation, true), 'duplicate finish cannot mint another completion')
        if order == 'finish-first' then
            assert(settlement.returnState(obligation) == 'waiting', 'callback success still needs the exact inventory effect')
            -- A client replica may have a new Java proxy for the same identity.
            s.observeDestination(s.item(81, nil))
        end
        s.queue.current, s.queue.queue = s.tail, {s.tail}
        assert(settlement.returnState(obligation) == 'completed'
            and settlement.returnState(obligation) == 'completed', order .. ': exact completion must remain readable after native advancement')
        assert(s.counts() == 0 and #s.queue.queue == 1 and s.queue.queue[1] == s.tail,
            'return observation cannot construct effects or advance/discard unrelated work')
        assert(client and s.transaction.calls == 2 or not client and s.transaction.calls == 0,
            'capture transaction predicates exactly once, only for client transfers')
    end
end

-- A native group may retain the older Java proxy after Host rebinds action.item.
for _, client in ipairs({false, true}) do
    local s = returnFixture(client)
    s.current.queueList[1].items[1] = s.item(81, nil)
    assert(s.settlement.beginReturn(s.current, s.obligation, s.guard),
        'same-ID/same-type native group proxy must retain its return observation')
    s.current.transactionId = 0
    s.observeDestination()
    assert(s.finishReturn(true) and s.settlement.returnState(s.obligation) == 'completed'
        and s.counts() == 0, 'proxy replacement must preserve exact effects without executing a transfer')
end

for _, outcome in ipairs({'rejected', 'absent', 'unconfirmed'}) do
    local s = returnFixture(true)
    s.transaction.done = outcome == 'absent'
    s.transaction.rejected = outcome ~= 'unconfirmed'
    assert(s.settlement.beginReturn(s.current, s.obligation, s.guard))
    s.current.transactionId = 0
    assert(s.finishReturn(true))
    s.observeDestination()
    local expected = outcome == 'rejected' and 'rejected' or 'unavailable'
    assert(s.settlement.returnState(s.obligation) == expected,
        outcome .. ': callback and destination replica cannot invent native transaction success')
    s.transaction.done, s.transaction.rejected = true, false
    assert(s.settlement.returnState(s.obligation) == expected and s.transaction.calls == 2,
        outcome .. ': later helper values cannot revive a retired transaction')
    assert(s.counts() == 0 and s.queue.queue[2] == s.tail)
end

for _, client in ipairs({false, true}) do
    local s = returnFixture(client)
    assert(s.settlement.beginReturn(s.current, s.obligation, s.guard))
    assert(s.finishReturn(false))
    s.observeDestination()
    assert(s.settlement.returnState(s.obligation) == 'unavailable'
        and not s.settlement.finishReturn(s.obligation, true), 'failed native callback cannot become completed later')
end

for _, shape in ipairs({'no-groups', 'extra-group', 'no-items', 'duplicate-id', 'conflicting-type', 'oversized', 'sparse', 'interior-hole', 'fractional-id', 'positive-infinity-id', 'negative-infinity-id', 'nan-id', 'different-id', 'different-type', 'no-native', 'foreign-obligation', 'guard'}) do
    local s = returnFixture(true)
    local action = s.current
    if shape == 'no-groups' then action.queueList = {}
    elseif shape == 'extra-group' then action.queueList[2] = {items = {s.item(82, s.root)}}
    elseif shape == 'no-items' then action.queueList[1].items = {}
    elseif shape == 'duplicate-id' then action.queueList[1].items[2] = s.item(81, s.root)
    elseif shape == 'conflicting-type' then
        local duplicate = s.item(81, s.root); duplicate.fullType = 'Base.Other'
        action.queueList[1].items[2] = duplicate
    elseif shape == 'oversized' then
        for i = 2, 21 do action.queueList[1].items[i] = s.item(80 + i, s.root) end
    elseif shape == 'sparse' then action.queueList[1].items[3] = s.item(83, s.root)
    elseif shape == 'interior-hole' then
        action.queueList[1].items = {action.item, s.item(82, s.root), s.item(83, s.root), s.item(84, s.root)}
        action.queueList[1].items[2] = nil
        assert(#action.queueList[1].items == 4, 'interior-hole regression needs a nontrivial Lua array boundary')
    elseif shape == 'fractional-id' then action.queueList[1].items[2] = s.item(82.5, s.root)
    elseif shape == 'positive-infinity-id' then action.queueList[1].items[2] = s.item(math.huge, s.root)
    elseif shape == 'negative-infinity-id' then action.queueList[1].items[2] = s.item(-math.huge, s.root)
    elseif shape == 'nan-id' then action.queueList[1].items[2] = s.item(0 / 0, s.root)
    elseif shape == 'different-id' then action.queueList[1].items[1] = s.item(82, s.root)
    elseif shape == 'different-type' then
        local member = s.item(81, s.root); member.fullType = 'Base.Other'
        action.queueList[1].items[1] = member
    elseif shape == 'no-native' then action.action = nil
    elseif shape == 'foreign-obligation' then s.obligation = {phase = 'cleanup', token = s.token}
    else s.guardLive = false end
    assert(not s.settlement.beginReturn(action, s.obligation, s.guard)
        and s.settlement.returnState(s.obligation) == nil, shape .. ': unsupported returns must not acquire an observation')
    assert(s.transaction.calls == 0 and s.counts() == 0, shape .. ': unsupported capture must not touch transaction/effects')
end

for _, transaction in ipairs({0, 1.5, '17', false}) do
    local s = returnFixture(true)
    s.current.transactionId = transaction
    local captured = s.settlement.beginReturn(s.current, s.obligation, s.guard)
    if captured then
        s.finishReturn(true); s.observeDestination()
        assert(s.settlement.returnState(s.obligation) == 'unavailable')
    else assert(s.settlement.returnState(s.obligation) == nil) end
    assert(s.transaction.calls == 0, 'invalid transaction IDs must not query native predicates')
end

for _, mode in ipairs({'missing', 'wrong-id', 'wrong-type', 'wrong-container', 'source-duplicate', 'consumed'}) do
    local s = returnFixture(true)
    assert(s.settlement.beginReturn(s.current, s.obligation, s.guard))
    assert(s.finishReturn(true))
    local observed = s.item(81, s.source)
    s.root.items[81] = nil
    if mode ~= 'missing' then s.source.items[81] = observed end
    if mode == 'wrong-id' then observed.id = 82
    elseif mode == 'wrong-type' then observed.fullType = 'Base.Other'
    elseif mode == 'wrong-container' then observed.container = {}
    elseif mode == 'source-duplicate' then s.root.items[81] = s.item(81, s.root)
    elseif mode == 'consumed' then observed.consumed = true end
    assert(s.settlement.returnState(s.obligation) ~= 'completed', mode .. ': exact destination and removal proof are both required')
    s.advance(30001)
    assert(s.settlement.returnState(s.obligation) == 'unavailable', mode .. ': missing exact effect must expire')
    s.observeDestination()
    assert(s.settlement.returnState(s.obligation) == 'unavailable', mode .. ': an expired observation cannot revive')
end

for _, afterCompleted in ipairs({false, true}) do
    for _, mutation in ipairs({'native', 'character', 'online', 'slot', 'local-player', 'queue', 'generation', 'dead',
        'src', 'dest', 'root-replacement', 'item-id', 'item-type', 'transaction', 'done-helper', 'rejected-helper', 'source-guard', 'closed'}) do
        local s = returnFixture(true)
        local action = s.current
        assert(s.settlement.beginReturn(action, s.obligation, s.guard))
        assert(s.finishReturn(true))
        if afterCompleted then
            s.observeDestination()
            assert(s.settlement.returnState(s.obligation) == 'completed')
        end
        if mutation == 'native' then action.action = {}
        elseif mutation == 'character' then action.character = {}
        elseif mutation == 'online' then s.player.getOnlineID = function() return 102 end
        elseif mutation == 'slot' then s.player.getPlayerNum = function() return 1 end
        elseif mutation == 'local-player' then getSpecificPlayer = function() return {} end
        elseif mutation == 'queue' then ISTimedActionQueue.queues[s.player] = {}
        elseif mutation == 'generation' then s.queue.toolkitOperationGeneration = 1
        elseif mutation == 'dead' then s.player.dead = true
        elseif mutation == 'src' then action.srcContainer = {}
        elseif mutation == 'dest' then action.destContainer = {}
        elseif mutation == 'root-replacement' then s.player.getInventory = function() return {} end
        elseif mutation == 'item-id' then action.item.id = 82
        elseif mutation == 'item-type' then action.item.fullType = 'Base.Other'
        elseif mutation == 'transaction' then action.transactionId = 18
        elseif mutation == 'done-helper' then isItemTransactionDone = function() return true end
        elseif mutation == 'rejected-helper' then isItemTransactionRejected = function() return false end
        elseif mutation == 'closed' then s.settlement.close(s.returnScope)
        else s.guardLive = false end
        assert(s.settlement.returnState(s.obligation) == 'unavailable', mutation .. ': stale ancestry must fail even after completed was observed')
        assert(s.counts() == 0 and s.queue.queue[2] == s.tail, mutation .. ': invalidation must preserve unrelated work')
    end
end

do
    local s = returnFixture(true)
    assert(s.settlement.beginReturn(s.current, s.obligation, s.guard))
    -- A remaining group means native reset for another transaction; this proof
    -- cannot silently claim that whole action's work completed.
    assert(s.settlement.finishReturn(s.obligation, true))
    s.observeDestination()
    assert(s.settlement.returnState(s.obligation) == 'unavailable', 'a continuing native batch is not a completed singleton return')
    s.current.queueList = {}
    assert(s.settlement.returnState(s.obligation) == 'unavailable', 'clearing a later batch cannot revive an unsupported completion')
end

do
    local s = returnFixture(false)
    isItemTransactionDone, isItemTransactionRejected = nil, nil
    assert(s.settlement.beginReturn(s.current, s.obligation, s.guard))
    assert(s.finishReturn(true))
    s.observeDestination()
    assert(s.settlement.returnState(s.obligation) == 'completed', 'SP return observation must not require client transaction helpers')
end

local function batchReturnFixture(client, beforeMerge)
    local s = returnFixture(client)
    s.members = {s.current.item, s.item(82, s.root)}
    s.root.items[82] = s.members[2]
    if not beforeMerge then s.current.queueList[1].items[2] = s.members[2] end
    -- The observer may tolerate a native-selected member, while ordinary source
    -- matching still requires the original item when no member is supplied.
    s.guard = function(action, member)
        return s.guardLive and action == s.current and action.item
            and action.item:getID() == (member and member.id or 81)
            and action.item:getFullType() == (member and member.fullType or 'Base.Test')
    end
    s.move = function(index, replacement)
        local original = s.members[index]
        local observed = replacement or original
        s.root.items[original:getID()] = nil
        original.container = nil
        observed.container = s.source
        s.source.items[original:getID()] = observed
        return observed
    end
    return s
end

local function assertReturnItems(s, first, second)
    local items = s.settlement.returnItems(s.obligation)
    assert(#items == 2 and items[1].id == 81 and items[1].fullType == 'Base.Test'
        and items[2].id == 82 and items[2].fullType == 'Base.Test'
        and items[1].state == first and items[2].state == second,
        'native group must preserve exact identities and independent member states')
    assert(s.counts() == 0 and s.queue.queue[2] == s.tail,
        'native group observation cannot replay effects or edit unrelated work')
    return items
end

do
    local s = batchReturnFixture(false)
    local mutatingGuard = function(action, member)
        local accepted = s.guard(action, member)
        if member then
            member.completed = true
            member.id, member.fullType = 999, 'Base.Other'
        end
        return accepted
    end
    assert(s.settlement.beginReturn(s.current, s.obligation, mutatingGuard))
    assert(s.finishReturn(true))
    assertReturnItems(s, 'waiting', 'waiting')
    s.current.item = s.members[2]
    assertReturnItems(s, 'waiting', 'waiting')
    assert(s.root.items[81] == s.members[1] and s.root.items[82] == s.members[2],
        'guard callback cannot mint native effects or mutate the private item ledger')
    s.move(1); s.move(2)
    assert(s.settlement.returnState(s.obligation) == 'completed')
    assertReturnItems(s, 'completed', 'completed')
end

for _, client in ipairs({false, true}) do
    local s = batchReturnFixture(client)
    -- Replication may leave older proxies in the native group.
    s.current.queueList[1].items = {s.item(81, nil), s.item(82, nil)}
    assert(s.settlement.beginReturn(s.current, s.obligation, s.guard))
    assertReturnItems(s, 'waiting', 'waiting')
    local copied = {}; for key, value in pairs(s.obligation) do copied[key] = value end
    assert(s.settlement.returnItems(copied) == nil, 'copied obligations cannot expose the native ledger')
    s.current.item = s.item(82, nil)
    s.current.transactionId = 0
    s.move(1, s.item(81, nil)); s.move(2, s.item(82, nil))
    assertReturnItems(s, 'waiting', 'waiting')
    assert(s.finishReturn(true) and s.settlement.returnState(s.obligation) == 'completed',
        'native selection of a captured nonoriginal member must preserve the group result')
    local public = assertReturnItems(s, 'completed', 'completed')
    public[1].id, public[1].fullType, public[1].state = 999, 'Base.Other', 'unavailable'
    public[2], public[3] = nil, {id = 83, state = 'completed'}
    assertReturnItems(s, 'completed', 'completed')
    assert(client and s.transaction.calls == 2 or not client and s.transaction.calls == 0,
        'one group must capture its native transaction predicates exactly once')
    s.queue.toolkitOperationGeneration = 1
    assertReturnItems(s, 'unavailable', 'unavailable')
end

do
    local s = batchReturnFixture(false)
    for i = 3, 20 do
        s.members[i] = s.item(80 + i, s.root)
        s.root.items[80 + i] = s.members[i]
        s.current.queueList[1].items[i] = s.members[i]
    end
    assert(s.settlement.beginReturn(s.current, s.obligation, s.guard), 'native maximum group size remains supported')
    for i = 1, 20 do s.move(i) end
    s.current.item = s.members[20]
    assert(s.finishReturn(true) and s.settlement.returnState(s.obligation) == 'completed')
    local items = s.settlement.returnItems(s.obligation)
    assert(#items == 20 and s.counts() == 0)
    for i, member in ipairs(items) do
        assert(member.id == 80 + i and member.fullType == 'Base.Test' and member.state == 'completed')
    end
end

for _, client in ipairs({false, true}) do
    for _, outcome in ipairs({'delayed-sibling', 'missing-sibling', 'late-finish', 'failed-callback'}) do
        local s = batchReturnFixture(client)
        assert(s.settlement.beginReturn(s.current, s.obligation, s.guard))
        s.current.item, s.current.transactionId = s.members[2], 0
        s.move(1)
        if outcome == 'late-finish' then s.advance(30001) end
        assert(s.finishReturn(outcome ~= 'failed-callback'))
        if outcome == 'late-finish' or outcome == 'failed-callback' then
            assertReturnItems(s, 'unavailable', 'unavailable')
        else
            assert(s.settlement.returnState(s.obligation) == 'waiting')
            assertReturnItems(s, 'completed', 'waiting')
            if outcome == 'delayed-sibling' then
                s.move(2, s.item(82, nil))
                assert(s.settlement.returnState(s.obligation) == 'completed')
                assertReturnItems(s, 'completed', 'completed')
            else
                s.advance(30001)
                assert(s.settlement.returnState(s.obligation) == 'unavailable')
                assertReturnItems(s, 'completed', 'unavailable')
                s.move(2)
                assertReturnItems(s, 'completed', 'unavailable')
            end
        end
    end
end

for _, badEffect in ipairs({'wrong-type', 'consumed', 'source-duplicate'}) do
    local s = batchReturnFixture(true)
    assert(s.settlement.beginReturn(s.current, s.obligation, s.guard))
    s.current.item, s.current.transactionId = s.item(82, nil), 0
    s.move(1)
    local observed = s.move(2, s.item(82, nil))
    if badEffect == 'wrong-type' then observed.fullType = 'Base.Other'
    elseif badEffect == 'consumed' then observed.consumed = true
    else s.root.items[82] = s.item(82, s.root) end
    assert(s.finishReturn(true))
    assertReturnItems(s, 'completed', 'waiting')
    s.advance(30001)
    assertReturnItems(s, 'completed', 'unavailable')
end

for _, outcome in ipairs({'rejected', 'absent', 'unconfirmed'}) do
    local s = batchReturnFixture(true)
    s.transaction.done, s.transaction.rejected = outcome == 'absent', outcome ~= 'unconfirmed'
    assert(s.settlement.beginReturn(s.current, s.obligation, s.guard))
    s.current.item, s.current.transactionId = s.members[2], 0
    s.move(1); s.move(2)
    assert(s.finishReturn(true))
    local expected = outcome == 'rejected' and 'rejected' or 'unavailable'
    assertReturnItems(s, expected, expected)
    assert(s.transaction.calls == 2, 'visible members cannot replace missing native group authority')
end

for _, mutation in ipairs({'unknown-member', 'wrong-member-type', 'generation', 'guard', 'closed'}) do
    local s = batchReturnFixture(true)
    assert(s.settlement.beginReturn(s.current, s.obligation, s.guard))
    s.current.item, s.current.transactionId = s.members[2], 0
    s.move(1)
    assert(s.finishReturn(true))
    assertReturnItems(s, 'completed', 'waiting')
    if mutation == 'unknown-member' then s.current.item = s.item(83, nil)
    elseif mutation == 'wrong-member-type' then s.current.item = s.item(82, nil); s.current.item.fullType = 'Base.Other'
    elseif mutation == 'generation' then s.queue.toolkitOperationGeneration = 1
    elseif mutation == 'closed' then s.settlement.close(s.returnScope)
    else s.guardLive = false end
    assert(s.settlement.returnState(s.obligation) == 'unavailable')
    assertReturnItems(s, 'unavailable', 'unavailable')
end

do
    local s = batchReturnFixture(false, true)
    assert(s.settlement.beginReturn(s.current, s.obligation, s.guard))
    s.current.queueList[1].items[2] = s.members[2]
    assert(s.settlement.refreshReturn(s.current, s.obligation), 'SP merge may expand its exact original first group')
    assert(not s.settlement.refreshReturn(s.current, s.obligation), 'one native merge observation cannot refresh twice')
    s.current.item = s.members[2]
    s.move(1); s.move(2)
    assert(s.finishReturn(true) and s.settlement.returnState(s.obligation) == 'completed')
    assertReturnItems(s, 'completed', 'completed')
end

do
    local s = batchReturnFixture(false, true)
    assert(s.settlement.beginReturn(s.current, s.obligation, s.guard))
    s.advance(30001)
    s.current.queueList[1].items[2] = s.members[2]
    s.settlement.refreshReturn(s.current, s.obligation)
    s.current.item = s.members[2]
    s.move(1); s.move(2)
    assert(s.finishReturn(true) and s.settlement.returnState(s.obligation) == 'unavailable',
        'late merge observation must not restart the captured group deadline')
    assertReturnItems(s, 'unavailable', 'unavailable')
end

for _, invalid in ipairs({'client', 'finished', 'not-current', 'not-first', 'native', 'guard', 'wrong-first-id', 'wrong-first-type', 'shrink', 'next-group'}) do
    local s = batchReturnFixture(invalid == 'client', invalid ~= 'shrink')
    assert(s.settlement.beginReturn(s.current, s.obligation, s.guard))
    s.current.queueList[1].items[2] = s.members[2]
    if invalid == 'finished' then s.finishReturn(true)
    elseif invalid == 'not-current' then s.queue.current = s.tail
    elseif invalid == 'not-first' then s.queue.queue[1] = s.tail
    elseif invalid == 'native' then s.current.action = {}
    elseif invalid == 'guard' then s.guardLive = false
    elseif invalid == 'wrong-first-id' then s.current.queueList[1].items[1] = s.item(83, s.root)
    elseif invalid == 'wrong-first-type' then
        s.current.queueList[1].items[1] = s.item(81, s.root)
        s.current.queueList[1].items[1].fullType = 'Base.Other'
    elseif invalid == 'shrink' then s.current.queueList[1].items[2] = nil
    elseif invalid == 'next-group' then s.current.queueList[2] = {items = {s.item(83, s.root)}} end
    assert(not s.settlement.refreshReturn(s.current, s.obligation), invalid .. ': unsupported merge cannot expand the captured group')
    assert(s.counts() == 0, 'rejected refresh cannot mutate native effects')
end

print('Shared settlement: deferred ownership, native group return outcomes, partial exact-ID effects, immutable ancestry and no effect replay passed.')
