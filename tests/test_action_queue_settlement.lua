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
    local transaction = {done = true, rejected = false, calls = 0, byId = {}}
    isItemTransactionDone = function(id)
        transaction.calls = transaction.calls + 1
        transaction.lastId = id
        local state = transaction.byId[id] or transaction
        return state.done
    end
    isItemTransactionRejected = function(id)
        transaction.calls = transaction.calls + 1
        transaction.lastId = id
        local state = transaction.byId[id] or transaction
        return state.rejected
    end
    createItemTransaction = function() error('settlement must never create an item transaction') end
    removeItemTransaction = function() error('settlement must never remove an item transaction') end
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

for _, shape in ipairs({'no-groups', 'duplicate-across-groups', 'no-items', 'duplicate-id', 'conflicting-type', 'oversized', 'sparse', 'interior-hole', 'fractional-id', 'positive-infinity-id', 'negative-infinity-id', 'nan-id', 'different-id', 'different-type', 'no-native', 'foreign-obligation', 'guard'}) do
    local s = returnFixture(true)
    local action = s.current
    if shape == 'no-groups' then action.queueList = {}
    elseif shape == 'duplicate-across-groups' then action.queueList[2] = {items = {s.item(81, s.root)}}
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

for _, invalid in ipairs({'finished', 'not-current', 'not-first', 'native', 'guard', 'wrong-first-id', 'wrong-first-type', 'shrink'}) do
    local s = batchReturnFixture(false, invalid ~= 'shrink')
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
    elseif invalid == 'shrink' then s.current.queueList[1].items[2] = nil end
    assert(not s.settlement.refreshReturn(s.current, s.obligation), invalid .. ': unsupported merge cannot expand the captured group')
    assert(s.counts() == 0, 'rejected refresh cannot mutate native effects')
end

-- A native executor can consume several groups while retaining its Lua table
-- and Java action. Only its exact observed handoff may start a new attempt.
local function sequenceReturnFixture(client)
    local s = batchReturnFixture(client)
    s.members[3] = s.item(83, s.root)
    s.root.items[83] = s.members[3]
    s.groups = {s.current.queueList[1], {items = {s.members[3]}}}
    s.current.queueList[2] = s.groups[2]
    s.transaction.byId[17] = {done = true, rejected = false}
    s.transaction.byId[18] = {done = true, rejected = false}
    s.consume = function(nextTransaction)
        local consumed = table.remove(s.current.queueList, 1)
        s.current.item = consumed.items[#consumed.items]
        local nextGroup = s.current.queueList[1]
        if nextGroup then s.current.item = nextGroup.items[1] end
        s.current.transactionId = nextGroup and (nextTransaction or 18) or 0
        return s.settlement.finishReturn(s.obligation, true)
    end
    s.begin = function() return s.settlement.beginReturn(s.current, s.obligation, s.guard) end
    s.history = function() return s.settlement.returnAttempts(s.obligation) end
    s.unchanged = function()
        assert(s.counts() == 0 and s.queue.queue[2] == s.tail,
            'attempt observation must not construct, transfer, cancel or reorder native work')
    end
    return s
end

for _, client in ipairs({false, true}) do
    local s = sequenceReturnFixture(client)
    local native = s.current.action
    assert(s.begin() and not s.begin())
    local queries = s.transaction.calls
    assert(s.settlement.returnMatches(s.current, s.obligation))
    assert(s.transaction.calls == queries and #s.history() == 1,
        'matching the bound cursor is a pure observation and cannot capture another attempt')
    s.move(1); s.move(2)
    assert(s.consume() and s.settlement.returnState(s.obligation) == 'waiting',
        'successful first group must await the exact native continuation')
    assert(s.current.action == native and s.settlement.returnMatches(s.current, s.obligation))
    assert(s.begin() and not s.begin(), 'same native pointer must permit exactly one next attempt')
    s.move(3)
    assert(s.consume() and s.settlement.returnState(s.obligation) == 'completed')
    local history = s.history()
    assert(#history == 2 and history[1].ordinal == 1 and history[2].ordinal == 2
        and history[1].phase == 'perform' and history[2].phase == 'perform'
        and history[1].state == 'completed' and history[2].state == 'completed'
        and history[1].transaction == (client and 17 or 0) and history[2].transaction == (client and 18 or 0)
        and history[1].authority == (client and 'completed' or 'native')
        and #history[1].items == 2 and #history[2].items == 1
        and history[1].items[1].id == 81 and history[1].items[2].id == 82 and history[2].items[1].id == 83)
    assert(client and s.transaction.calls == 4 or not client and s.transaction.calls == 0)
    assert(not s.settlement.returnMatches(s.tail, s.obligation) and not s.begin())
    history[1].items[1].id, history[1].items[1].state = 999, 'unavailable'
    history[1].state, history[2], history[3] = 'rejected', nil, {ordinal = 3}
    local fresh = s.history()
    assert(#fresh == 2 and fresh[1].state == 'completed' and fresh[1].items[1].id == 81
        and fresh[1].items[1].state == 'completed', 'attempt history must expose fresh immutable value copies')
    local copied = {}; for key, value in pairs(s.obligation) do copied[key] = value end
    assert(s.settlement.returnAttempts(copied) == nil
        and not s.settlement.returnMatches(s.current, copied), 'history cannot forge the private observation capability')
    s.unchanged()
end

for _, client in ipairs({false, true}) do
    for _, sibling in ipairs({'timely', 'expired'}) do
        local s = sequenceReturnFixture(client)
        assert(s.begin()); s.move(1); assert(s.consume())
        s.advance(20000)
        assert(s.begin()); s.move(3); assert(s.consume())
        if sibling == 'timely' then
            s.move(2)
            assert(s.settlement.returnState(s.obligation) == 'completed',
                'first group replication may settle while a later group has already finished')
        else
            s.advance(10001)
            assert(s.settlement.returnState(s.obligation) == 'unavailable')
        end
        local history, items = s.history(), s.settlement.returnItems(s.obligation)
        assert(history[1].items[1].state == 'completed' and history[2].items[1].state == 'completed'
            and items[1].state == 'completed' and items[3].state == 'completed')
        assert(history[1].items[2].state == (sibling == 'timely' and 'completed' or 'unavailable'),
            'each group deadline must preserve earned siblings and later successful groups')
        if sibling == 'expired' then
            s.move(2)
            assert(s.history()[1].items[2].state == 'unavailable', 'expired old group must not revive from a late effect')
        end
        s.unchanged()
    end
end

for _, client in ipairs({false, true}) do
    local s = sequenceReturnFixture(client)
    assert(s.begin()); s.move(1); s.move(2); assert(s.consume())
    s.advance(31000)
    assert(s.begin()); assert(s.consume())
    assert(s.settlement.returnState(s.obligation) == 'waiting')
    s.advance(1000); s.move(3)
    assert(s.settlement.returnState(s.obligation) == 'completed'
        and s.history()[2].state == 'completed',
        'later attempt deadline must start at its own perform boundary, after the earlier deadline')
    s.unchanged()
end

for _, client in ipairs({false, true}) do
    local s = sequenceReturnFixture(client)
    assert(s.begin()); s.move(1); assert(s.consume())
    assert(s.begin()); s.move(3); assert(s.consume())
    s.queue.toolkitOperationGeneration = 1
    assert(s.settlement.returnState(s.obligation) == 'unavailable')
    s.move(2)
    local history = s.history()
    assert(history[1].items[1].state == 'completed' and history[1].items[2].state == 'unavailable'
        and history[2].items[1].state == 'completed',
        'stale archival reads must retain earned effects without upgrading later stale replication')
    for _, member in ipairs(s.settlement.returnItems(s.obligation)) do
        assert(member.state == 'unavailable', 'archival effects must not grant live queue rights')
    end
    s.unchanged()
end

for _, outcome in ipairs({'rejected', 'absent', 'unconfirmed'}) do
    local s = sequenceReturnFixture(true)
    assert(s.begin()); s.move(1); s.move(2); assert(s.consume())
    s.transaction.byId[18] = {done = outcome == 'absent', rejected = outcome ~= 'unconfirmed'}
    assert(s.begin()); s.move(3); assert(s.consume())
    local expected = outcome == 'rejected' and 'rejected' or 'unavailable'
    assert(s.settlement.returnState(s.obligation) == expected)
    local history = s.history()
    assert(history[1].state == 'completed' and history[1].items[1].state == 'completed'
        and history[1].items[2].state == 'completed' and history[2].state == expected
        and history[2].items[1].state == expected,
        outcome .. ': later transaction failure cannot erase earlier exact committed effects')
    s.transaction.byId[17], s.transaction.byId[18] = {done = false, rejected = true}, {done = true, rejected = false}
    assert(s.history()[1].state == 'completed' and s.history()[2].state == expected and s.transaction.calls == 4,
        'finished attempts must never query removed or reused native transaction IDs')
    s.unchanged()
end

for _, client in ipairs({false, true}) do
    for _, outcome in ipairs({'completed', 'rejected', 'absent', 'unconfirmed'}) do
      for _, visible in ipairs({false, true}) do
        local s = sequenceReturnFixture(client)
        assert(s.begin()); s.move(1); s.move(2); assert(s.consume())
        s.transaction.byId[18] = {done = outcome == 'completed' or outcome == 'absent',
            rejected = outcome == 'rejected' or outcome == 'absent'}
        -- A committed Host transaction can already have replicated before stop.
        -- This test moves it explicitly; the observer must never execute it.
        if visible then s.move(3) end
        assert(s.settlement.stopReturn(s.current, s.obligation, s.guard))
        assert(not s.settlement.stopReturn(s.current, s.obligation, s.guard)
            and not s.begin(), 'stop cannot allocate a duplicate attempt or restart native work')
        local history = s.history()
        local stopped = client and outcome == 'rejected' and 'rejected' or 'unavailable'
        assert(#history == 2 and history[1].phase == 'perform' and history[1].state == 'completed'
            and history[2].phase == 'stop' and history[2].state == stopped
            and history[2].items[1].state == (client and visible and outcome == 'completed' and 'completed' or stopped)
            and s.settlement.returnState(s.obligation) == stopped,
            outcome .. ': stop records exact authority and earned Host effects without normal completion')
        local calls = s.transaction.calls
        s.current.transactionId = 0 -- native stop removes its transaction next
        s.queue.toolkitOperationGeneration = 1
        assert(s.settlement.returnState(s.obligation) == 'unavailable'
            and not s.settlement.returnMatches(s.current, s.obligation))
        history = s.history()
        assert(history[1].state == 'completed' and history[1].items[1].state == 'completed'
            and history[2].phase == 'stop' and s.transaction.calls == calls,
            'reset may revoke live rights but cannot erase or requery historical attempts')
        local items = s.settlement.returnItems(s.obligation)
        for _, member in ipairs(items) do assert(member.state == 'unavailable') end
        s.unchanged()
      end
    end
end

for _, mutation in ipairs({'group-ref', 'group-members', 'item-id', 'item-type', 'transaction', 'native', 'current',
    'head', 'generation', 'queue', 'source-guard', 'done-helper', 'rejected-helper', 'create-helper', 'remove-helper'}) do
    local s = sequenceReturnFixture(true)
    assert(s.begin()); s.move(1); s.move(2); assert(s.consume())
    local calls = s.transaction.calls
    if mutation == 'group-ref' then s.current.queueList[1] = {items = {s.members[3]}}
    elseif mutation == 'group-members' then s.current.queueList[1].items[2] = s.item(84, s.root)
    elseif mutation == 'item-id' then s.current.item = s.item(84, s.root)
    elseif mutation == 'item-type' then s.current.item = s.item(83, s.root); s.current.item.fullType = 'Base.Other'
    elseif mutation == 'transaction' then s.current.transactionId = 19
    elseif mutation == 'native' then s.current.action = {}
    elseif mutation == 'current' then s.queue.current = s.tail
    elseif mutation == 'head' then s.queue.queue[1] = s.tail
    elseif mutation == 'generation' then s.queue.toolkitOperationGeneration = 1
    elseif mutation == 'queue' then ISTimedActionQueue.queues[s.player] = {}
    elseif mutation == 'source-guard' then s.guardLive = false
    elseif mutation == 'done-helper' then isItemTransactionDone = function() error('foreign done helper') end
    elseif mutation == 'rejected-helper' then isItemTransactionRejected = function() error('foreign rejected helper') end
    elseif mutation == 'create-helper' then createItemTransaction = function() error('foreign create helper') end
    else removeItemTransaction = function() error('foreign remove helper') end
    end
    assert(not s.begin() and s.transaction.calls == calls,
        mutation .. ': unproven continuation must not allocate or query a new attempt')
    local history = s.history()
    assert(#history == 1 and history[1].state == 'completed' and history[1].items[1].state == 'completed',
        mutation .. ': invalid cursor cannot rewrite already-earned historical effects')
    assert(s.counts() == 0, mutation .. ': rejected continuation cannot execute native work')
end

for _, outcome in ipairs({'completed', 'rejected'}) do
    local s = sequenceReturnFixture(true)
    assert(s.begin()); s.move(1); s.move(2); assert(s.consume(17))
    -- Native byte IDs can wrap/reuse while the same executor continues.
    s.transaction.byId[17] = {done = outcome == 'completed', rejected = outcome == 'rejected'}
    assert(s.begin()); s.move(3); assert(s.consume())
    local history = s.history()
    assert(#history == 2 and history[1].transaction == 17 and history[2].transaction == 17
        and history[1].state == 'completed' and history[2].state == outcome
        and s.transaction.calls == 4, 'numeric transaction reuse must bind a fresh ordinal without requerying old authority')
    s.unchanged()
end

for _, client in ipairs({false, true}) do
    local s = sequenceReturnFixture(client)
    assert(s.begin())
    local added = s.item(84, s.root)
    s.root.items[84] = added
    if client then
        table.remove(s.current.queueList, 1)
        s.current.item = s.members[2]
    end
    s.groups[2].items[2] = added
    assert(s.settlement.refreshReturn(s.current, s.obligation), 'native merge may append exact future group members')
    assert(not s.settlement.refreshReturn(s.current, s.obligation), 'one attempt may accept its native merge only once')
    s.move(1); s.move(2)
    if client then
        s.current.item, s.current.transactionId = s.members[3], 18
        assert(s.settlement.finishReturn(s.obligation, true))
    else assert(s.consume()) end
    assert(s.begin()); s.move(3)
    s.root.items[84], added.container, s.source.items[84] = nil, s.source, added
    assert(s.consume() and s.settlement.returnState(s.obligation) == 'completed')
    local history = s.history()
    assert(#history[1].items == 2 and #history[2].items == 2 and history[2].items[2].id == 84
        and history[2].items[2].state == 'completed', 'Host post-consumption merge cannot attach future members to the old receipt')
    s.unchanged()
end

for _, client in ipairs({false, true}) do
    local s = sequenceReturnFixture(client)
    assert(s.begin())
    s.members[4] = s.item(84, s.root)
    s.root.items[84] = s.members[4]
    if client then
        table.remove(s.current.queueList, 1)
        s.current.item = s.members[2]
    end
    s.current.queueList[#s.current.queueList + 1] = {items = {s.members[4]}}
    assert(s.settlement.refreshReturn(s.current, s.obligation), 'native merge may append a whole future group')
    s.move(1); s.move(2)
    if client then
        s.current.item, s.current.transactionId = s.members[3], 18
        assert(s.settlement.finishReturn(s.obligation, true))
    else assert(s.consume()) end
    assert(s.begin()); s.move(3); assert(s.consume(19))
    assert(s.begin()); s.move(4); assert(s.consume())
    local history = s.history()
    assert(s.settlement.returnState(s.obligation) == 'completed' and #history == 3
        and history[3].items[1].id == 84 and history[3].items[1].state == 'completed',
        'new future groups require their own callback and authority attempt')
    s.unchanged()
end

for _, client in ipairs({false, true}) do
    local s = sequenceReturnFixture(client)
    assert(s.begin()); s.move(1); s.move(2); assert(s.consume())
    s.queue.current, s.queue.queue = s.tail, {s.tail}
    assert(s.settlement.returnState(s.obligation) == 'unavailable',
        'a disappeared native continuation must not wait forever or regain a live capability')
    local history = s.history()
    assert(history[1].state == 'completed' and history[1].items[1].state == 'completed',
        'unexpected advancement must preserve the immutable earned history')
end
-- Kahlua exposes pairs but no global next; use its actual available boundary.
local savedNext = next
next = nil
-- Pickup claims are candidates until the exact native attempt earns an effect.
local function pickupFixture(client, ids)
    local s = setup(client)
    s.root.isExistYet = function() return true end
    s.scope = s.settlement.deferred(s.player, s.token)
    s.pickups, s.members, s.owners = {}, {}, {}
    s.guard = function(action, member)
        return s.guardLive ~= false and action.character == s.player and action.item
            and (not member or action.item:getID() == member.id and action.item:getFullType() == member.fullType)
    end
    for index, id in ipairs(ids or {181}) do
        local owner, value = index == 1 and s.token or {}, s.item(id, s.source)
        s.source.items[id] = value
        local action = {Type = 'ISInventoryTransferAction', character = s.player, toolkitQueueOperation = owner,
            item = value, srcContainer = s.source, destContainer = s.root, action = {},
            queueList = {{items = {value}}}, transactionId = 17 + index - 1}
        owner.toolkitPickups = {[value] = s.source}
        s.settlement.remember(s.scope, action, {knownInputs = true, items = {[id] = true}})
        s.settlement.preparePickup(s.scope, action)
        s.pickups[index], s.members[index], s.owners[index] = action, value, owner
    end
    s.pickup = s.pickups[1]
    s.queue.current, s.queue.queue = s.pickup, {}
    for _, action in ipairs(s.pickups) do s.queue.queue[#s.queue.queue + 1] = action end
    s.queue.queue[#s.queue.queue + 1] = s.tail
    s.mergePickup = function(separateGroup)
        s.settlement.beforePickupMerge(s.scope, s.pickup, s.guard)
        if separateGroup then s.pickup.queueList[#s.pickup.queueList + 1] = {items = {s.members[2]}}
        else s.pickup.queueList[1].items[#s.pickup.queueList[1].items + 1] = s.members[2] end
        assert(table.remove(s.queue.queue, 2) == s.pickups[2], 'fixture must remove the actual native child')
        for key in pairs(s.pickups[2]) do s.pickups[2][key] = nil end
        s.settlement.refreshPickup(s.scope, s.pickup)
    end
    s.movePickup = function(index, replacement)
        local old = s.members[index]
        local live = replacement or old
        s.source.items[old:getID()], old.container = nil, nil
        live.container, s.root.items[old:getID()] = s.root, live
        return live
    end
    s.finishPickup = function(succeeded)
        s.pickup.queueList, s.pickup.transactionId = {}, 0
        local result = s.settlement.finishPickup(s.scope, s.pickup, succeeded)
        s.settlement.poll(s.scope)
        return result
    end
    s.makeReturn = function()
        local action = {Type = 'ISInventoryTransferAction', character = s.player,
            toolkitQueueOperation = {}, item = s.members[1], srcContainer = s.root, destContainer = s.source,
            action = {}, transactionId = 71, queueList = {{items = s.members}}}
        s.queue.current, s.queue.queue = action, {action, s.tail}
        s.returnObligation = s.settlement.obligation(s.settlement.context(s.scope))
        assert(s.returnObligation and s.settlement.beginReturn(action, s.returnObligation, s.guard))
        s.returnAction = action
    end
    s.completeReturn = function()
        for _, value in ipairs(s.members) do
            local live = s.root:getItemById(value:getID())
            if live then live.container, s.root.items[value:getID()], s.source.items[value:getID()] = s.source, nil, live end
        end
        s.returnAction.item, s.returnAction.queueList, s.returnAction.transactionId = s.members[#s.members], {}, 0
        assert(s.settlement.finishReturn(s.returnObligation, true))
    end
    return s
end
-- Explicitly cancelling one pending return retains the exact earned item while
-- the body keeps running. Later body cancellation cannot recreate that return.
local function pendingReturnFixture(client, unearned)
    local s = pickupFixture(client)
    assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard))
    s.movePickup(1)
    if not unearned then assert(s.finishPickup(true)) end
    s.current.Type = 'ISReadABook'
    local action = {Type = 'ISInventoryTransferAction', character = s.player, toolkitQueueOperation = s.token,
        item = s.members[1], srcContainer = s.root, destContainer = s.source, allowMissingItems = true}
    s.settlement.track(s.current, 'body'); s.settlement.track(action, 'body')
    s.queue.current, s.queue.queue = s.current, {s.current, action, s.tail}
    PZSurvivorToolkit.ActionQueuePolicy.matchesNative = function(value) return value == action and s.nativeLive ~= false end
    s.returnGuard = function(value, member)
        return s.returnGuardLive ~= false and value == action and member.id == 181 and member.fullType == 'Base.Test'
    end
    s.pendingReturn = action
    return s
end
for _, client in ipairs({false, true}) do
    local s = pendingReturnFixture(client)
    local action = s.pendingReturn
    local handle = s.settlement.pendingReturnWaiver(action, s.returnGuard)
    assert(handle and s.settlement.canWaivePendingReturn(action, s.returnGuard)
        and s.settlement.operationState(s.current).borrowings[1].state == 'active',
        'preview must not waive an earned obligation')
    assert(s.settlement.waivePendingReturn(handle, action, s.returnGuard))
    assert(not s.settlement.waivePendingReturn(handle, action, s.returnGuard)
        and not s.settlement.pendingReturnWaiver(action, s.returnGuard), 'the exact loan can be waived only once')
    assert(s.queue.current == s.current and s.queue.queue[2] == action and s.root.items[181] == action.item
        and action.item:getContainer() == s.root and s.counts() == 0,
        'waiving a loan must not schedule, remove, transfer or release any native work')
    table.remove(s.queue.queue, 2)
    assert(s.settlement.operationState(s.current).borrowings[1].state == 'waived')
    s.token.toolkitCancelled = true
    assert(s.settlement.finish(s.queue, {action = s.current, token = s.token}, s.discard))
    assert(s.counts() == 0 and s.queue.queue[2] == s.tail and s.root.items[181] == action.item,
        'later cancellation must not resurrect a waived loan from its legacy pickup hint')
end
for _, client in ipairs({false, true}) do
    local s = pendingReturnFixture(client, true)
    assert(not s.settlement.canWaivePendingReturn(s.pendingReturn, s.returnGuard)
        and not s.settlement.pendingReturnWaiver(s.pendingReturn, s.returnGuard),
        'physical possession alone cannot waive an unearned native borrowing')
end
for _, client in ipairs({false, true}) do
    for _, mutation in ipairs({'native', 'guard', 'guard-error', 'started', 'native-start', 'step-start', 'required',
        'shared', 'destination', 'source', 'item', 'actor', 'generation', 'queue', 'removed', 'stop', 'token-stop', 'copy'}) do
        local s = pendingReturnFixture(client)
        local action = s.pendingReturn
        local handle = s.settlement.pendingReturnWaiver(action, s.returnGuard)
        assert(handle)
        if mutation == 'native' then s.nativeLive = false
        elseif mutation == 'guard' then s.returnGuardLive = false
        elseif mutation == 'guard-error' then s.returnGuard = function() error('changed guard') end
        elseif mutation == 'started' then action.started = true
        elseif mutation == 'native-start' then action.action = {}
        elseif mutation == 'step-start' then s.settlement.started(action)
        elseif mutation == 'required' then
            PZSurvivorToolkit.ActionQueuePolicy.inspect = function() return {} end
            local preparation = s.settlement.track(s.pickup, 'prepare')
            assert(s.settlement.cleanup(action, preparation))
        elseif mutation == 'shared' then
            s.settlement.remember(s.scope, {character = s.player, toolkitQueueOperation = {}}, {items = {[181] = true}})
        elseif mutation == 'destination' then action.destContainer = {}
        elseif mutation == 'source' then action.srcContainer = {}
        elseif mutation == 'item' then action.item = s.item(181, s.root); s.root.items[181] = action.item
        elseif mutation == 'actor' then action.character = {}
        elseif mutation == 'generation' then s.queue.toolkitOperationGeneration = 1
        elseif mutation == 'queue' then ISTimedActionQueue.queues[s.player] = {character = s.player, queue = {}}
        elseif mutation == 'removed' then table.remove(s.queue.queue, 2)
        elseif mutation == 'stop' then s.queue.toolkitGroupCancel = {}
        elseif mutation == 'token-stop' then s.token.toolkitCancelled = true
        elseif mutation == 'copy' then local copied = {}; for key, value in pairs(action) do copied[key] = value end; action = copied end
        assert(not s.settlement.waivePendingReturn(handle, action, s.returnGuard), mutation .. ': stale capability must not waive')
        local state = s.settlement.operationState(s.current)
        assert(not state or state.borrowings[1].state == 'active', mutation .. ': rejection altered its earned loan')
        assert(s.counts() == 0, mutation .. ': rejection must not construct cleanup')
    end
end
for _, client in ipairs({false, true}) do
    local s = pendingReturnFixture(client)
    local oldReturn = s.pendingReturn
    local handle = s.settlement.pendingReturnWaiver(oldReturn, s.returnGuard)
    assert(not s.settlement.waivePendingReturn({}, oldReturn, s.returnGuard)
        and not s.settlement.waivePendingReturn(handle, oldReturn, function() return true end),
        'neither a fabricated handle nor another caller proof can waive a borrowing')
    assert(s.settlement.waivePendingReturn(handle, oldReturn, s.returnGuard))
    -- A separate later native departure and pickup opens a genuinely new loan.
    -- Its fresh receipt must earn cleanup independently of the old user intent.
    local value = oldReturn.item
    s.root.items[181], s.source.items[181], value.container = nil, value, s.source
    local pickup = {Type = 'ISInventoryTransferAction', character = s.player, toolkitQueueOperation = s.token,
        item = value, srcContainer = s.source, destContainer = s.root, action = {}, transactionId = 91,
        queueList = {{items = {value}}}}
    s.settlement.remember(s.scope, pickup, {knownInputs = true, items = {[181] = true}})
    assert(s.settlement.preparePickup(s.scope, pickup))
    s.queue.current, s.queue.queue = pickup, {pickup, s.current, s.tail}
    assert(s.settlement.beginPickup(s.scope, pickup, s.guard))
    s.source.items[181], s.root.items[181], value.container = nil, value, s.root
    pickup.queueList, pickup.transactionId = {}, 0
    assert(s.settlement.finishPickup(s.scope, pickup, true))
    s.queue.current, s.queue.queue = s.current, {s.current, s.tail}
    local state = s.settlement.operationState(s.current)
    assert(state.borrowings[1].state == 'waived' and state.borrowings[2].state == 'active',
        'the old intent must not contaminate a distinct earned borrowing')
    assert(s.settlement.finish(s.queue, {action = s.current, token = s.token}, s.discard))
    assert(s.counts() == 1 and s.queue.queue[2].item == value and s.queue.queue[3] == s.tail,
        'a fresh exact loan needs its own required return despite the historical waiver')
end
for _, client in ipairs({false, true}) do
    local s = pendingReturnFixture(client)
    local secondItem = s.item(182, s.source); s.source.items[182] = secondItem
    local second = {Type = 'ISInventoryTransferAction', character = s.player, toolkitQueueOperation = s.token,
        item = secondItem, srcContainer = s.source, destContainer = s.root, action = {}, transactionId = 19,
        queueList = {{items = {secondItem}}}}
    s.settlement.remember(s.scope, second, {knownInputs = true, items = {[182] = true}})
    assert(s.settlement.preparePickup(s.scope, second))
    s.queue.current, s.queue.queue = second, {second, s.current, s.pendingReturn, s.tail}
    assert(s.settlement.beginPickup(s.scope, second, s.guard))
    s.source.items[182], s.root.items[182], secondItem.container = nil, secondItem, s.root
    second.queueList, second.transactionId = {}, 0
    assert(s.settlement.finishPickup(s.scope, second, true))
    s.queue.current, s.queue.queue = s.current, {s.current, s.pendingReturn, s.tail}
    local handle = s.settlement.pendingReturnWaiver(s.pendingReturn, s.returnGuard)
    assert(handle and s.settlement.waivePendingReturn(handle, s.pendingReturn, s.returnGuard))
    table.remove(s.queue.queue, 2)
    assert(s.settlement.finish(s.queue, {action = s.current, token = s.token}, s.discard))
    assert(s.counts() == 1 and s.queue.queue[2].item == secondItem and s.queue.queue[3] == s.tail,
        'waiving one loan must preserve required settlement for another exact item')
    assert(s.settlement.operationState(s.current).borrowings[1].state == 'waived'
        and s.settlement.operationState(s.current).borrowings[2].state == 'active')
end
local function assertOwnership(s, expected, owners, shared)
    local facts = s.settlement.returnOwnership(s.returnObligation)
    assert(#facts == #s.members, 'ownership diagnostics must retain every observed native member')
    for index, fact in ipairs(facts) do
        assert(fact.id == s.members[index]:getID() and fact.fullType == s.members[index]:getFullType()
            and fact.state == expected[index], 'return ownership lost the exact native member identity/state')
        assert(fact.owner == owners[index] and fact.shared == (not owners[index] or shared == true),
            'original pickup owner and shared cleanup classification must remain independent')
        if owners[index] then
            assert(fact.pickupAttempt == 1 and fact.pickupTransaction == (isClient() and 17 or 0)
                and fact.pickupAuthority == (isClient() and 'completed' or 'native'),
                'owned member must cite its exact earned native pickup attempt')
        else
            assert(fact.pickupAttempt == nil and fact.pickupTransaction == nil and fact.pickupAuthority == nil,
                'unbound member cannot borrow authority from its executor')
        end
    end
    assert(s.counts() == 0 and s.queue.queue[2] == s.tail,
        'pickup observation cannot construct effects, change native scheduling or consume the tail')
    return facts
end
for _, client in ipairs({false, true}) do
    local s = pickupFixture(client)
    assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard))
    assert(s.settlement.pickupMatches(s.scope, s.pickup))
    s.movePickup(1, s.item(181, nil)); assert(s.finishPickup(true))
    for action in pairs(s.scope.seen) do s.scope.seen[action] = nil end
    s.makeReturn(); assertOwnership(s, {'active'}, {s.token})
    local copied = s.settlement.returnOwnership(s.returnObligation)
    copied[1].id, copied[1].state, copied[1].owner, copied[1].shared = 999, 'completed', {}, true
    assertOwnership(s, {'active'}, {s.token})
    s.completeReturn(); assertOwnership(s, {'completed'}, {s.token})
end
-- Equipment readers retain exact current items and the proven queued writers;
-- unrelated borrowed items stay exclusive. Actor read scopes cannot create effects.
for _, client in ipairs({false, true}) do
    for _, mode in ipairs({'unrelated', 'future-gear', 'reader-first', 'other-actor', 'same-owner-reader'}) do
        local s = pickupFixture(client)
        local readerOwner = mode=='same-owner-reader' and s.token or {}
        local reader = {character=s.player,toolkitQueueOperation=readerOwner}
        local writer = {character=s.player,toolkitQueueOperation=s.token}
        local readerContract = {items={[999]=true}, equipment=mode=='other-actor' and {} or s.player}
        local writerContract = {items={[mode=='unrelated' and 998 or 181]=true},hands=s.player}
        if mode=='reader-first' then
            s.settlement.remember(s.scope,reader,readerContract)
            s.settlement.remember(s.scope,writer,writerContract)
        else
            s.settlement.remember(s.scope,writer,writerContract)
            s.settlement.remember(s.scope,reader,readerContract)
        end
        -- Mutating an accepted read/write descriptor cannot widen later claims.
        readerContract.equipment=nil;writerContract.items[777]=true
        assert(not s.scope.equipmentItems[777])
        local shared=mode=='future-gear' or mode=='reader-first'
        assert((s.settlement.owner(s.scope,181,'Base.Test',s.source)==nil)==shared,
            'legacy cleanup ownership lost equipment read/write scope: '..mode)
        assert(s.settlement.beginPickup(s.scope,s.pickup,s.guard))
        s.movePickup(1);assert(s.finishPickup(true));s.makeReturn()
        assertOwnership(s,{'active'},{s.token},shared)
        s.completeReturn();assertOwnership(s,{'completed'},{s.token},shared)
    end
end

-- SP discovers merged membership during perform; Host already merged in start.
for _, client in ipairs({false, true}) do
    local s = pickupFixture(client, {181, 182})
    if client then s.mergePickup() end
    assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard))
    if not client then s.mergePickup() end
    s.movePickup(1); s.movePickup(2, s.item(182, nil)); assert(s.finishPickup(true))
    s.makeReturn()
    assert(s.returnAction.toolkitQueueOperation ~= s.owners[1]
        and s.returnAction.toolkitQueueOperation ~= s.owners[2], 'fixture requires an unrelated executor token')
    assertOwnership(s, {'active', 'active'}, s.owners)
    s.completeReturn(); assertOwnership(s, {'completed', 'completed'}, s.owners)
end
for _, competing in ipairs({'same-item', 'unknown', 'dynamic'}) do
    local s = pickupFixture(true)
    local contract = {knownInputs = true, items = {}}
    if competing == 'same-item' then contract.items[181] = true
    elseif competing == 'unknown' then contract.knownInputs = false
    else contract.dynamicInputs = {['Base.Test'] = true} end
    s.settlement.remember(s.scope, {character = s.player, toolkitQueueOperation = {}}, contract)
    assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard))
    s.movePickup(1); assert(s.finishPickup(true)); s.makeReturn()
    assertOwnership(s, {'active'}, {s.token}, true)
    s.completeReturn(); assertOwnership(s, {'completed'}, {s.token}, true)
end
for _, client in ipairs({false, true}) do
    for _, outcome in ipairs({'no-callback', 'failed', 'missing', 'wrong-type', 'source-duplicate', 'expired'}) do
        local s = pickupFixture(client)
        assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard))
        if outcome == 'expired' then s.advance(30001) end
        if outcome ~= 'missing' then
            local live = s.movePickup(1, s.item(181, nil))
            if outcome == 'wrong-type' then live.fullType = 'Base.Other'
            elseif outcome == 'source-duplicate' then s.source.items[181] = s.item(181, s.source) end
        end
        if outcome ~= 'no-callback' then s.finishPickup(outcome ~= 'failed') end
        s.settlement.poll(s.scope)
        s.advance(30001); s.settlement.poll(s.scope)
        s.movePickup(1, s.item(181, nil)); s.settlement.poll(s.scope)
        s.makeReturn(); assertOwnership(s, {'unbound'}, {})
    end
end
for _, outcome in ipairs({'rejected', 'absent', 'pending'}) do
    local s = pickupFixture(true)
    s.transaction.done, s.transaction.rejected = outcome == 'absent', outcome ~= 'pending'
    assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard))
    s.movePickup(1); s.finishPickup(true)
    s.transaction.done, s.transaction.rejected = true, false
    s.settlement.poll(s.scope); s.makeReturn(); assertOwnership(s, {'unbound'}, {})
end
for _, client in ipairs({false, true}) do
    local s = pickupFixture(client)
    assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard))
    assert(s.finishPickup(true))
    s.movePickup(1, s.item(181, nil)); s.settlement.poll(s.scope)
    s.makeReturn(); assertOwnership(s, {'active'}, {s.token})
end
-- The exact successful sibling remains earned when another member expires.
for _, client in ipairs({false, true}) do
    local s = pickupFixture(client, {181, 182})
    if client then s.mergePickup() end
    assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard))
    if not client then s.mergePickup() end
    s.movePickup(1); s.finishPickup(true)
    s.advance(30001); s.settlement.poll(s.scope)
    s.movePickup(2); s.settlement.poll(s.scope)
    s.makeReturn(); assertOwnership(s, {'active', 'unbound'}, {s.token})
end
for _, boundary in ipairs({'cancel-before-effect', 'cancel-after-effect', 'generation', 'replacement', 'dead', 'closed'}) do
    local s = pickupFixture(true)
    assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard))
    if boundary == 'cancel-after-effect' then s.movePickup(1); s.finishPickup(true) end
    if boundary:match('^cancel') then s.token.toolkitCancelled = true
    elseif boundary == 'generation' then s.queue.toolkitOperationGeneration = 1
    elseif boundary == 'replacement' then ISTimedActionQueue.queues[s.player] = {character = s.player, queue = {}}
    elseif boundary == 'dead' then s.player.dead = true
    else s.settlement.close(s.scope) end
    if boundary ~= 'cancel-after-effect' then s.movePickup(1); s.finishPickup(true) end
    s.settlement.poll(s.scope)
    if boundary:match('^cancel') then
        s.settlement.remember(s.scope, {character = s.player, toolkitQueueOperation = {}}, {knownInputs = true, items = {}})
        s.makeReturn(); assertOwnership(s, {'active'}, {s.token})
    else
        s.player.dead = false; ISTimedActionQueue.queues[s.player] = s.queue
        s.scope = s.settlement.deferred(s.player, {})
        s.makeReturn(); assertOwnership(s, {'unbound'}, {})
    end
end
-- Unresolved repeated borrowing cannot select an owner by iteration order.
for _, client in ipairs({false, true}) do
    local s = pickupFixture(client)
    local second = {Type = 'ISInventoryTransferAction', character = s.player, toolkitQueueOperation = {},
        item = s.item(181, s.source), srcContainer = s.source, destContainer = s.root,
        action = {}, transactionId = 18}
    second.queueList = {{items = {second.item}}}
    s.settlement.remember(s.scope, second, {knownInputs = true, items = {[181] = true}})
    s.settlement.preparePickup(s.scope, second)
    assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard))
    s.movePickup(1); s.finishPickup(true)
    s.makeReturn(); assertOwnership(s, {'unbound'}, {})
end
do
    local s = returnFixture(true)
    assert(s.settlement.beginReturn(s.current, s.obligation, s.guard))
    local facts = s.settlement.returnOwnership(s.obligation)
    assert(#facts == 1 and facts[1].id == 81 and facts[1].state == 'unbound' and facts[1].owner == nil)
    facts[1].owner, facts[1].state, facts[1].pickupAuthority = s.token, 'active', 'completed'
    s.current.transactionId = 0; s.observeDestination(); assert(s.finishReturn(true))
    facts = s.settlement.returnOwnership(s.obligation)
    assert(facts[1].state == 'unbound' and facts[1].owner == nil and s.settlement.returnState(s.obligation) == 'completed',
        'legacy native return may complete without minting a pickup obligation from copied diagnostics')
end
-- Ordered groups on the same executor keep distinct native receipt ordinals.
for _, client in ipairs({false, true}) do
    local s = pickupFixture(client, {181, 182})
    if client then s.mergePickup(true) end
    assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard))
    if not client then s.mergePickup(true) end
    s.movePickup(1)
    table.remove(s.pickup.queueList, 1)
    if client then assert(s.settlement.refreshPickup(s.scope, s.pickup)) end
    s.pickup.item, s.pickup.transactionId = s.members[2], 18
    assert(s.settlement.finishPickup(s.scope, s.pickup, true))
    assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard))
    s.movePickup(2); s.pickup.queueList, s.pickup.transactionId = {}, 0
    assert(s.settlement.finishPickup(s.scope, s.pickup, true))
    s.settlement.poll(s.scope); s.makeReturn()
    local facts = s.settlement.returnOwnership(s.returnObligation)
    assert(#facts == 2 and facts[1].owner == s.owners[1] and facts[2].owner == s.owners[2]
        and facts[1].state == 'active' and facts[2].state == 'active'
        and facts[1].pickupAttempt == 1 and facts[2].pickupAttempt == 2
        and facts[1].pickupTransaction == (client and 17 or 0)
        and facts[2].pickupTransaction == (client and 18 or 0),
        'later pickup group must cite its own attempt/transaction without inheriting executor ownership')
end
-- An outbound native transfer starts a new borrowing boundary even while an
-- old successful pickup callback still awaits its exact replicated effect.
for _, client in ipairs({false, true}) do
    local s = pickupFixture(client)
    assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard))
    assert(s.finishPickup(true))
    local outbound = {character = s.player, srcContainer = s.root, destContainer = s.source,
        item = s.members[1], queueList = {{items = {s.members[1]}}}}
    s.settlement.departure(s.scope, outbound)
    s.movePickup(1, s.item(181, nil))
    s.settlement.poll(s.scope)
    s.makeReturn(); assertOwnership(s, {'unbound'}, {})
end
-- One activated candidate binds to one native return proof. A concurrent
-- observer cannot borrow either its live ownership or its later completion.
for _, client in ipairs({false, true}) do
    local s = pickupFixture(client)
    assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard))
    s.movePickup(1); assert(s.finishPickup(true))
    s.makeReturn(); assertOwnership(s, {'active'}, {s.token})
    local firstAction, firstObligation = s.returnAction, s.returnObligation
    s.makeReturn(); assertOwnership(s, {'unbound'}, {})
    local secondObligation = s.returnObligation
    local first = s.settlement.returnOwnership(firstObligation)
    assert(first[1].state == 'active' and first[1].owner == s.token,
        'second observer must not revoke or complete the first exact return proof')
    s.returnAction, s.returnObligation = firstAction, firstObligation
    s.queue.current, s.queue.queue = firstAction, {firstAction, s.tail}
    s.completeReturn(); assertOwnership(s, {'completed'}, {s.token})
    local second = s.settlement.returnOwnership(secondObligation)
    assert(#second == 1 and second[1].state == 'unbound' and second[1].owner == nil
        and second[1].pickupAttempt == nil and second[1].pickupAuthority == nil,
        'another return proof cannot inherit completion or authority from a shared candidate')
end
-- A matching queued candidate cannot lend ownership without an actual merge.
for _, client in ipairs({false, true}) do
    for _, preflight in ipairs({false, true}) do
        local s = pickupFixture(client, {181, 182})
        if not client then assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard)) end
        if preflight then s.settlement.beforePickupMerge(s.scope, s.pickup, s.guard) end
        s.pickup.queueList[1].items[2] = s.members[2]
        -- Its exact child remains queued and intact despite matching membership.
        s.settlement.refreshPickup(s.scope, s.pickup)
        if client then assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard)) end
        assert(s.queue.queue[2] == s.pickups[2] and s.pickups[2].character == s.player)
        s.movePickup(1); s.movePickup(2); assert(s.finishPickup(true))
        s.makeReturn(); assertOwnership(s, {'active', 'unbound'}, {s.token})
    end
end
for _,client in ipairs({false,true}) do
    local s=pickupFixture(client)
    assert(s.settlement.beginPickup(s.scope,s.pickup,s.guard))
    s.movePickup(1);assert(s.finishPickup(true));s.makeReturn();s.completeReturn()
    assertOwnership(s,{'completed'},{s.token})
    s.settlement.close(s.scope)
    assertOwnership(s,{'completed'},{s.token})
end
for _,client in ipairs({false,true}) do
    local s=pickupFixture(client)
    -- Ordinary producer pickup provenance may be absent from the legacy map.
    -- The sealed native source action, not that intent map, earns ownership.
    s.scope.tasks[s.token].pickups={};s.token.toolkitPickups={}
    s.settlement.remember(s.scope,{character=s.player,toolkitQueueOperation={}},{items={}})
    assert(s.settlement.owner(s.scope,181,'Base.Test',s.source)==nil)
    assert(s.settlement.beginPickup(s.scope,s.pickup,s.guard))
    s.movePickup(1);assert(s.finishPickup(true));s.makeReturn()
    assertOwnership(s,{'active'},{s.token})
    s.completeReturn();s.settlement.close(s.scope)
    assertOwnership(s,{'completed'},{s.token})
end
next = savedNext
-- Persistent phases require the exact native receipt and its observed effect,
-- never source membership. Diagnostics and copied handles grant no authority.
for _, client in ipairs({false, true}) do
    for _, outcome in ipairs({'completed', 'rejected', 'unobserved', 'different-action', 'copied', 'reset'}) do
        local s = setup(client)
        PZSurvivorToolkit.ActionQueuePolicy.inspect = function() return {} end
        local removal, restore = s.action(), s.action()
        removal.action = {}
        s.queue.current, s.queue.queue = removal, {removal, s.current, restore, s.tail}
        if client then
            removal.toolkitNativeTransaction, removal.toolkitNativeKind = 51, 'ISUnequipAction'
            s.receipt(removal, 'started')
        end
        local handle = s.settlement.track(removal, 'prepare')
        assert(handle == s.settlement.track(removal, 'body'), 'enqueue cannot replace the reviewed preparation role')
        assert(s.settlement.cleanup(restore, handle))
        local other = s.action(); other.action = {}
        local proof = s.settlement.captureEffect(outcome == 'different-action' and other or removal)
        if outcome ~= 'different-action' then assert(s.settlement.bindEffect(handle, proof)) end
        local credit = handle
        if outcome == 'copied' then credit = {}; for key, value in pairs(handle) do credit[key] = value end end
        if outcome == 'reset' then s.queue.toolkitOperationGeneration = 1 end
        if client then s.receipt(removal, outcome == 'rejected' and 'rejected' or 'completed') end
        local earned = s.settlement.earn(credit, proof, outcome ~= 'unobserved')
        assert(earned == (outcome == 'completed' or not client and outcome == 'rejected'),
            outcome .. ': effect proof must belong to the original live step')
        if earned or outcome ~= 'unobserved' then
            assert(not s.settlement.earn(credit, proof, true), 'an earned or invalid step cannot be credited twice')
        end
        if outcome ~= 'reset' then
            local state = s.settlement.operationState(removal)
            assert(state.steps[1].phase == 'prepare')
            state.steps[1].state = 'earned' -- value copy cannot pay the real obligation
            s.queue.current, s.queue.queue = s.current, {s.current, restore, s.tail} -- source removal is already pruned
            local request = {action = s.current, token = s.token}
            assert(s.settlement.finish(s.queue, request, s.discard))
            assert((s.queue.queue[2] == restore) == earned,
                outcome .. ': only a confirmed preparation retains restoration after source pruning')
            assert(s.queue.queue[#s.queue.queue] == s.tail)
            assert(not s.settlement.finish(s.queue, {action = s.current, token = s.token}, s.discard),
                'a new request object cannot settle the same operation twice')
        else
            assert(not s.settlement.operationState(removal), 'a reset permanently retires the old operation seal')
            assert(not s.settlement.track(s.current, 'body'), 'an old token cannot acquire a new generation')
        end
    end
end

-- The independent tail waits for late authority AND exact replication. A
-- rejected preparation is isolated; missing authority times out without replay.
for _, outcome in ipairs({'completed', 'rejected', 'timeout'}) do
    local s = setup(true)
    local removal = s.action(); removal.action = {}
    s.queue.current, s.queue.queue = removal, {removal, s.current, s.tail}
    removal.toolkitNativeTransaction, removal.toolkitNativeKind = 52, 'ISUnequipAction'
    s.receipt(removal, 'started')
    local handle = s.settlement.track(removal, 'prepare')
    local proof = s.settlement.captureEffect(removal)
    assert(s.settlement.bindEffect(handle, proof))
    s.queue.current, s.queue.queue = s.current, {s.current, s.tail}
    s.queue.toolkitGroupCancel = {action = s.current, token = s.token}
    assert(s.settlement.cancellationState(s.queue, s.current) == 'waiting')
    assert(not s.settlement.finish(s.queue, s.queue.toolkitGroupCancel, s.discard)
        and s.queue.queue[2] == s.tail and s.counts() == 0,
        'an uncertain preparation cannot schedule cleanup or release its tail')
    if outcome == 'timeout' then
        s.advance(30001)
        assert(s.settlement.cancellationState(s.queue, s.current) == 'failed')
    else
        s.receipt(removal, outcome)
        if outcome == 'completed' then
            assert(s.settlement.cancellationState(s.queue, s.current) == 'waiting',
                'authority alone cannot stand in for exact local replication')
            assert(s.settlement.earn(handle, proof, true))
        end
        assert(s.settlement.cancellationState(s.queue, s.current) == 'ready')
    end
end

-- Cancellation planning consumes the exact earned P4 episode. A legacy hint
-- may not resurrect an already-returned, shared, rejected or unresolved pickup.
for _, client in ipairs({false, true}) do
    for _, outcome in ipairs(client and {'earned', 'shared', 'returned', 'rejected', 'unresolved'}
        or {'earned', 'shared', 'returned', 'unresolved'}) do
        local s = pickupFixture(client)
        if outcome == 'shared' then
            s.settlement.remember(s.scope, {character = s.player, toolkitQueueOperation = {}}, {items = {[181] = true}})
        end
        if client and outcome == 'rejected' then s.transaction.done, s.transaction.rejected = false, true end
        assert(s.settlement.beginPickup(s.scope, s.pickup, s.guard))
        if outcome ~= 'unresolved' and outcome ~= 'rejected' then s.movePickup(1) end
        assert(s.finishPickup(true))
        if outcome == 'returned' then s.makeReturn(); s.completeReturn() end
        s.queue.current, s.queue.queue = s.current, {s.current, s.tail}
        s.token.toolkitCancelled = true
        local request = {action = s.current, token = s.token}
        s.queue.toolkitGroupCancel = request
        if outcome == 'unresolved' then
            assert(s.settlement.cancellationState(s.queue, s.current) == 'waiting')
            s.advance(30001)
            assert(s.settlement.cancellationState(s.queue, s.current) == 'failed')
        else
            assert(s.settlement.finish(s.queue, request, s.discard), outcome .. ': isolated cancellation must settle')
            local n = s.counts()
            assert(n == (outcome == 'earned' and 1 or 0), outcome .. ': only exclusively earned borrowing creates a return')
            assert(s.queue.queue[#s.queue.queue] == s.tail)
            if outcome == 'earned' then
                local action = s.queue.queue[2]
                s.queue.current = action; table.remove(s.queue.queue, 1)
                action.action, action.transactionId = {}, 80
                action.queueList = {{items = {action.item}}}
                s.transaction.done, s.transaction.rejected = true, false
                assert(s.settlement.beginPlannedReturn(action, s.guard))
                assert(s.settlement.requiredStep(action))
                local copy = {}; for key, value in pairs(action) do copy[key] = value end
                assert(not s.settlement.requiredStep(copy), 'copied cleanup presentation cannot acquire required ownership')
                action.queueList, action.transactionId = {}, 0
                assert(s.settlement.finishPlannedReturn(action, true))
                assert(s.settlement.completionState(s.queue, action) == 'waiting',
                    'retokenized return cannot release its tail before exact endpoint replication')
                s.root.items[181], s.members[1].container, s.source.items[181] = nil, s.source, s.members[1]
                assert(s.settlement.completionState(s.queue, action) == 'ready')
                assert(s.settlement.operationState(s.current).borrowings[1].state == 'completed',
                    'native return receipt retires the same borrowed episode')
            end
        end
    end
end
-- The common observer must see a real start, successful callback, exact live
-- effect and (in Host) sealed receipt, even on the normal non-cancelled path.
for _, client in ipairs({false, true}) do
    for _, outcome in ipairs({'completed', 'rejected', 'missing-start', 'unmarked', 'callback-failure', 'changed-guard', 'timeout', 'empty'}) do
        local s = setup(client)
        local observer, transfers
        PZSurvivorToolkit.ActionQueueLifecycle = {registerObserver = function(_, value) observer = value; return true end}
        PZSurvivorToolkit.ActionQueueTidyIntent = {observeTransfers = function(_, _, value) transfers = value end}
        PZSurvivorToolkit.ActionQueuePolicy.inspect = function() return {} end
        local action = s.action(); action.Type, action.action = 'ISUnequipAction', {}
        s.queue.current, s.queue.queue = action, {action, s.tail}
        local guard, changed, captures = true, false, 0
        local handle = s.settlement.observePreparation(action, {
            guard = function(value) return value == action and guard end,
            capture = function() captures = captures + 1; if outcome ~= 'empty' then return {original = true} end end,
            observed = function(_, before) assert(before.original); return changed end,
        })
        assert(handle and observer and transfers and not s.settlement.earned(handle))
        local restore = s.action(); restore.Type = 'ISQueueActionsAction'
        assert(s.settlement.cleanupAfter(restore, {handle}))
        if outcome ~= 'missing-start' then s.settlement.started(action); observer.started(action) end
        if client and outcome ~= 'unmarked' then
            action.toolkitNativeTransaction, action.toolkitNativeKind = 71, action.Type
            s.receipt(action, 'started')
        end
        observer.begin(action, 'perform')
        changed = true
        if outcome == 'changed-guard' then guard = false end
        observer.finish(action, 'perform', outcome ~= 'callback-failure')
        if not client then observer.finish(action, 'complete', outcome ~= 'callback-failure') end
        if outcome == 'changed-guard' then guard = false end
        if client and outcome ~= 'unmarked' then
            if outcome ~= 'timeout' then s.receipt(action, outcome == 'rejected' and 'rejected' or 'completed')
            else s.advance(30001) end
        end
        local expected = outcome == 'empty' and 'ready'
            or (outcome == 'completed' or not client and (outcome == 'rejected' or outcome == 'timeout' or outcome == 'unmarked')) and 'ready'
            or client and outcome == 'rejected' and 'ready' or 'failed'
        assert(s.settlement.completionState(s.queue, action) == expected, outcome .. ': normal continuation proof gate')
        local earned = expected == 'ready' and outcome ~= 'empty' and not (client and outcome == 'rejected')
        assert(s.settlement.earned(handle) == earned, outcome .. ': only actual preparation earns restoration')
        assert(captures == (outcome == 'missing-start' and 0 or 1))
        local copy = {}; for key, value in pairs(handle) do copy[key] = value end
        assert(not s.settlement.earned(copy))
        s.queue.current, s.queue.queue = restore, {restore, s.tail}
        local child = s.action(); child.Type = 'ISEquipWeaponAction'
        assert(s.settlement.inheritCleanup(child, restore) == earned)
        assert(s.settlement.requiredStep(child) == earned)
        s.queue.toolkitOperationGeneration = 1
        assert(not s.settlement.earned(handle) and not s.settlement.requiredStep(child))
    end
end

-- A late Host terminal and its exact local effect gate NORMAL continuation too.
do
    local s = setup(true)
    local observer
    PZSurvivorToolkit.ActionQueueLifecycle = {registerObserver = function(_, value) observer = value; return true end}
    PZSurvivorToolkit.ActionQueueTidyIntent = {observeTransfers = function() end}
    local action = s.action(); action.Type, action.action = 'ISUnequipAction', {}
    s.queue.current, s.queue.queue = action, {action, s.tail}
    local observed = false
    local handle = s.settlement.observePreparation(action, {guard = function() return true end,
        capture = function() return {} end, observed = function() return observed end})
    s.settlement.started(action); observer.started(action)
    action.toolkitNativeTransaction, action.toolkitNativeKind = 72, action.Type
    observer.begin(action, 'perform'); observer.finish(action, 'perform', true)
    assert(s.settlement.completionState(s.queue, action) == 'waiting')
    s.receipt(action, 'started'); s.receipt(action, 'completed')
    assert(s.settlement.completionState(s.queue, action) == 'waiting' and not s.settlement.earned(handle))
    observed = true
    assert(s.settlement.completionState(s.queue, action) == 'ready' and s.settlement.earned(handle))
end

-- Normal and cancelled cleanup consume the same private borrowing episode.
-- Scheduling a return is not payment and cannot schedule it a second time.
for _, client in ipairs({false, true}) do
    for _, cancelled in ipairs({false, true}) do
        local s = setup(client)
        s.root.isExistYet = function() return true end
        local observer, events
        PZSurvivorToolkit.ActionQueueLifecycle = {registerObserver = function(_, value) observer = value; return true end}
        PZSurvivorToolkit.ActionQueueTidyIntent = {observeTransfers = function(_, _, value) events = value end}
        PZSurvivorToolkit.ActionQueuePolicy.inspect = function() return {} end
        ISTimedActionQueue.add = function(action) table.insert(s.queue.queue, 2, action) end
        local value = s.item(191, s.source); s.source.items[191] = value
        local pickup = s.action()
        pickup.Type, pickup.action, pickup.item = 'ISInventoryTransferAction', {}, value
        pickup.srcContainer, pickup.destContainer = s.source, s.root
        pickup.queueList, pickup.transactionId = {{items = {value}}}, 21
        s.queue.current, s.queue.queue = pickup, {pickup, s.current, s.tail}
        local handle = s.settlement.observePreparation(pickup, {guard = function(action) return action == pickup end,
            capture = function() return {source = s.source} end, observed = function() return value.container == s.root end})
        assert(handle)
        s.settlement.started(pickup); observer.started(pickup)
        assert(events.begin(pickup))
        pickup.queueList, pickup.transactionId = {}, 0
        assert(events.finish(pickup, true))
        assert(s.settlement.completionState(s.queue, pickup) == 'waiting')
        s.source.items[191], s.root.items[191], value.container = nil, value, s.root
        assert(s.settlement.completionState(s.queue, pickup) == 'ready' and s.settlement.earned(handle))
        local restoration = s.action(); restoration.Type = 'ISQueueActionsAction'
        assert(s.settlement.cleanupAfter(restoration, {handle}))
        if cancelled then
            s.queue.current, s.queue.queue = s.current, {s.current, restoration, s.tail}
            assert(s.settlement.finish(s.queue, {action = s.current, token = s.token}, s.discard))
            assert(s.queue.queue[2] == restoration and s.queue.queue[3].Type == 'ISInventoryTransferAction')
            s.queue.current = restoration; table.remove(s.queue.queue, 1)
            assert(not s.settlement.enqueueBorrowedReturn(handle), 'retained command must not duplicate a planned return')
        else
            s.queue.current, s.queue.queue = restoration, {restoration, s.tail}
            local foreign = {character = s.player, toolkitQueueOperation = {}, Type = 'ISQueueActionsAction'}
            local foreignEffect = {character = s.player, toolkitQueueOperation = foreign.toolkitQueueOperation, action = {}}
            s.queue.current, s.queue.queue = foreignEffect, {foreignEffect, s.tail}
            local foreignHandle = s.settlement.track(foreignEffect, 'prepare')
            local receipt = s.settlement.captureEffect(foreignEffect)
            if client then
                foreignEffect.toolkitNativeTransaction, foreignEffect.toolkitNativeKind = 81, 'ISUnequipAction'
                s.receipt(foreignEffect, 'started'); receipt = s.settlement.captureEffect(foreignEffect)
                s.receipt(foreignEffect, 'completed')
            end
            assert(s.settlement.earn(foreignHandle, receipt, true))
            assert(s.settlement.cleanup(foreign, foreignHandle))
            s.queue.current, s.queue.queue = foreign, {foreign, s.tail}
            assert(not s.settlement.enqueueBorrowedReturn(handle), 'an unrelated required command cannot consume another operation borrowing')
            s.queue.current, s.queue.queue = restoration, {restoration, s.tail}
            local action = s.settlement.enqueueBorrowedReturn(handle)
            assert(action and s.settlement.requiredStep(action) and action.toolkitQueueOperation == s.token)
            assert(not s.settlement.enqueueBorrowedReturn(handle))
        end
        assert(s.counts() == 1 and value.container == s.root,
            'return scheduling must not synthesize item transfer or spend a confirmed borrowing')
        assert(s.settlement.operationState(pickup).borrowings[1].state == 'active')
    end
end

-- P4 sees synchronous enqueue first. Family preparation must reuse its exact
-- borrowing episode, including P4's foreign-task claims and transaction history.
for _, client in ipairs({false, true}) do
    for _, shared in ipairs({false, true}) do
        local s = pickupFixture(client)
        local observer, listeners = nil, {}
        ISInventoryTransferAction = {}
        setmetatable(s.pickup, ISInventoryTransferAction)
        PZSurvivorToolkit.ActionQueueLifecycle = {registerObserver = function(_, value) observer = value; return true end}
        PZSurvivorToolkit.ActionQueueTidyIntent = {observeTransfers = function(callback, canObserve, events)
            listeners[#listeners + 1] = {callback = callback, events = events}
        end}
        PZSurvivorToolkit.ActionQueuePolicy.inspect = function() return {} end
        PZSurvivorToolkit.ActionQueuePolicy.matchesNative = s.guard
        PZSurvivorToolkit.ActionQueuePolicy.isOrdinaryTransfer = function() return true end
        ISTimedActionQueue.add = function(action) table.insert(s.queue.queue, 2, action) end
        local constructor = ISInventoryTransferUtil.newInventoryTransferAction
        ISInventoryTransferUtil.newInventoryTransferAction = function(...)
            local action = constructor(...)
            action.action, action.transactionId, action.queueList = {}, 71, {{items = {action.item}}}
            return setmetatable(action, ISInventoryTransferAction)
        end
        local function event(name, action, ...)
            local accepted = false
            for _, listener in ipairs(listeners) do
                local callback = listener.events and listener.events[name]
                if callback and callback(action, ...) then accepted = true end
            end
            return accepted
        end
        local function merge(action)
            event('merging', action)
            for _, listener in ipairs(listeners) do listener.callback(action) end
        end
        if shared then
            local reader = {character = s.player, toolkitQueueOperation = {}}
            assert(s.settlement.remember(s.scope, reader, {knownInputs = true, items = {[181] = true}}))
        end
        local handle = s.settlement.observePreparation(s.pickup, {guard = s.guard,
            capture = function() return {source = s.source} end,
            observed = function() return s.members[1].container == s.root end})
        assert(handle and #s.settlement.operationState(s.pickup).borrowings == 1,
            'family observation duplicated the P4 native pickup episode')
        s.settlement.started(s.pickup); observer.started(s.pickup)
        assert(event('begin', s.pickup)); merge(s.pickup)
        s.movePickup(1)
        s.pickup.queueList, s.pickup.transactionId = {}, 0
        assert(event('finish', s.pickup, true))
        assert(s.settlement.completionState(s.queue, s.pickup) == 'ready' and s.settlement.earned(handle))
        local state = s.settlement.operationState(s.pickup)
        assert(#state.borrowings == 1 and state.borrowings[1].state == 'active',
            'shared observers did not earn one exact native pickup')
        local restoration = s.action(); restoration.Type = 'ISQueueActionsAction'
        assert(s.settlement.cleanupAfter(restoration, {handle}))
        s.queue.current, s.queue.queue = restoration, {restoration, s.tail}
        local returning = s.settlement.enqueueBorrowedReturn(handle)
        assert(not s.settlement.enqueueBorrowedReturn(handle), 'one pickup scheduled a duplicate return')
        if shared then
            assert(not returning and s.counts() == 0,
                'family observation lost P4 foreign-task ownership and created an exclusive return')
        else
            assert(returning and s.counts() == 1 and s.queue.queue[2] == returning,
                'the single shared native pickup must schedule one exact return')
            s.queue.current, s.queue.queue = returning, {returning, s.tail}
            assert(event('begin', returning)); merge(returning)
            local value = s.members[1]
            s.root.items[181], s.source.items[181], value.container = nil, value, s.source
            returning.queueList, returning.transactionId = {}, 0
            assert(event('finish', returning, true))
            assert(s.settlement.completionState(s.queue, returning) == 'ready')
            state = s.settlement.operationState(s.pickup)
            assert(#state.borrowings == 1 and state.borrowings[1].state == 'completed' and s.counts() == 1,
                'the shared pickup and return did not close one exact borrowing episode')
        end
    end
end

-- A stale or changed pre-enqueue binding cannot be replaced with a fresh claim.
for _, changed in ipairs({'source', 'generation', 'retired'}) do
    local s = pickupFixture(false)
    PZSurvivorToolkit.ActionQueueLifecycle = {registerObserver = function() return true end}
    PZSurvivorToolkit.ActionQueueTidyIntent = {observeTransfers = function() end}
    if changed == 'source' then s.pickup.srcContainer = {}
    elseif changed == 'generation' then s.scope.generation = s.scope.generation + 1
    else s.settlement.close(s.scope) end
    assert(not s.settlement.observePreparation(s.pickup, {guard = s.guard,
        capture = function() return {} end, observed = function() return true end}),
        changed .. ': a mismatched existing pickup acquired preparation proof')
    assert(#s.settlement.operationState(s.pickup).borrowings == 1,
        changed .. ': rejecting reuse created a replacement borrowing episode')
end

-- Floor cleanup is an earned-drop capability, not a generic floor edit grant.
-- Native transfer authority and exact replication still gate the following work.
for _, client in ipairs({false, true}) do
    for _, outcome in ipairs({'completed', 'unearned', 'wrong-world', 'different-item', 'changed-binding', 'rejected', 'timeout', 'reset'}) do
        local s = setup(client)
        s.root.isExistYet = function() return true end
        s.source.getType = function() return 'floor' end
        local observer
        PZSurvivorToolkit.ActionQueueLifecycle = {registerObserver = function(_, value) observer = value; return true end}
        PZSurvivorToolkit.ActionQueueTidyIntent = {observeTransfers = function() end}
        local value = s.item(211, s.root);s.root.items[211] = value
        local world, square = {}, {}
        world.getItem = function() return value end
        world.getSquare = function() return square end
        square.getWorldObjects = function() return {contains = function(_, item) return item == world end} end
        value.getWorldItem = function() return world end
        local drop = s.action();drop.Type, drop.action, drop.item = 'ISDropWorldItemAction', {}, value
        s.queue.current, s.queue.queue = drop, {drop, s.tail}
        local handle = s.settlement.observePreparation(drop, {guard = function() return true end,
            capture = function() return {square = square} end, observed = function() return value.container == s.source end})
        s.settlement.started(drop);observer.started(drop)
        if client then drop.toolkitNativeTransaction,drop.toolkitNativeKind = 75,drop.Type;s.receipt(drop,'started') end
        observer.begin(drop,'perform')
        s.root.items[211],s.source.items[211],value.container = nil,value,s.source
        if outcome ~= 'unearned' then
            if client then s.receipt(drop,'completed') end
            observer.finish(drop,client and 'perform' or 'complete',true)
            assert(s.settlement.earned(handle))
        end
        local parent = s.action();parent.Type = 'ISQueueActionsAction'
        assert(s.settlement.cleanup(parent,handle))
        s.queue.current,s.queue.queue = parent,{parent,s.tail}
        local action = s.action();action.Type,action.action,action.item = 'ISInventoryTransferAction',{},value
        action.srcContainer,action.destContainer,action.queueList,action.transactionId = s.source,s.root,{{items={value}}},19
        local policy=PZSurvivorToolkit.ActionQueuePolicy
        policy.inspect=function(current)
            if current.Type == 'ISInventoryTransferAction' then return s.settlement.isCleanupPickup(current) and {} or nil end
            return {}
        end
        policy.matchesCleanupPickupBinding=function(current) return outcome~='changed-binding' and current==action end
        policy.matchesNative=function(current) return s.settlement.isCleanupPickup(current) end
        policy.isOrdinaryTransfer=function() return false end
        if outcome=='wrong-world' then world.getSquare=function() return {} end end
        if outcome=='different-item' then action.item=s.item(212,s.source);action.item.getWorldItem=function() return world end end
        local allowed=outcome~='unearned' and outcome~='wrong-world' and outcome~='different-item' and outcome~='changed-binding'
        assert(s.settlement.observeCleanupTransfer(action,parent)==allowed,outcome..': only exact earned floor recovery may be observed')
        assert(s.settlement.isCleanupPickup(action)==allowed)
        local copy={};for key,v in pairs(action)do copy[key]=v end
        assert(not s.settlement.isCleanupPickup(copy),'copied safe fields cannot authorize a floor pickup')
        if allowed then
            s.queue.current,s.queue.queue=action,{action,s.tail}
            if outcome=='rejected' and client then s.transaction.done,s.transaction.rejected=false,true end
            assert(s.settlement.beginPlannedReturn(action,policy.matchesNative))
            action.queueList,action.transactionId={},0
            assert(s.settlement.finishPlannedReturn(action,true))
            if outcome=='reset' then
                s.queue.toolkitOperationGeneration=1
                assert(not s.settlement.isCleanupPickup(action) and not s.settlement.requiredStep(action)
                    and not s.settlement.operationState(action) and not s.settlement.plannedReturnMatches(action))
            elseif outcome=='rejected' and client then
                assert(s.settlement.completionState(s.queue,action)=='ready','a rejected native cleanup is isolated, never replayed')
            else
                assert(s.settlement.completionState(s.queue,action)=='waiting','native completion alone cannot replace replica proof')
                if outcome=='timeout' then s.advance(30001);assert(s.settlement.completionState(s.queue,action)=='failed')
                else
                    s.source.items[211],s.root.items[211],value.container=nil,value,s.root
                    assert(s.settlement.completionState(s.queue,action)=='ready')
                    local state=s.settlement.operationState(action)
                    local step=state.steps[#state.steps]
                    assert(step.phase=='cleanup' and step.state=='earned' and step.plannedTransfer and step.transferDirection=='pickup')
                    assert(#state.borrowings==0,'recovering a grounded bag must not borrow it back from the floor')
                end
            end
        end
    end
end

-- A source container can be reidentified only through its private exact owner
-- after native pickup replaces that bag's Java/container replica.
for _, client in ipairs({false,true}) do
    for _, ownerState in ipairs({'replaced','different-type','not-carried','missing'})do
        local s=setup(client)
        s.root.isExistYet=function()return true end
        local oldOwner=s.item(221,s.root);oldOwner.fullType='Base.Bag_Schoolbag'
        oldOwner.getInventory=function()return s.source end
        s.source.getContainingItem=function()return oldOwner end
        s.root.items[221]=oldOwner
        local value=s.item(222,s.source);s.source.items[222]=value
        local pickup=s.action();pickup.Type,pickup.action,pickup.item='ISInventoryTransferAction',{},value
        pickup.srcContainer,pickup.destContainer,pickup.queueList,pickup.transactionId=s.source,s.root,{{items={value}}},20
        local scope=s.settlement.deferred(s.player,s.token)
        assert(s.settlement.remember(scope,pickup,{knownInputs=true,items={[222]=true}}))
        assert(s.settlement.preparePickup(scope,pickup))
        local handle=s.settlement.track(pickup,'prepare')
        s.queue.current,s.queue.queue=pickup,{pickup,s.tail}
        local guard=function()return true end
        assert(s.settlement.beginPickup(scope,pickup,guard))
        s.source.items[222],s.root.items[222],value.container=nil,value,s.root
        pickup.queueList,pickup.transactionId={},0
        assert(s.settlement.finishPickup(scope,pickup,true) and s.settlement.earned(handle))
        local fresh={items={},carried=ownerState~='not-carried',isExistYet=function()return true end}
        fresh.getItemById=function(self,id)return self.items[id]end
        local owner=s.item(221,s.root);owner.fullType=ownerState=='different-type' and 'Base.Bag_Other' or 'Base.Bag_Schoolbag'
        owner.getInventory=function()return fresh end
        s.root.items[221]=ownerState~='missing' and owner or nil
        local parent=s.action();parent.Type='ISQueueActionsAction'
        PZSurvivorToolkit.ActionQueuePolicy.inspect=function()return {}end
        assert(s.settlement.cleanup(parent,handle))
        s.queue.current,s.queue.queue=parent,{parent,s.tail}
        ISTimedActionQueue.add=function(action)table.insert(s.queue.queue,2,action)end
        if ownerState=='replaced' then
            -- A cancelled workout cannot return its prop while its bag is still
            -- on the ground. Its retained restoration later recovers that owner.
            s.root.items[221]=nil
            s.queue.current,s.queue.queue=s.current,{s.current,parent,s.tail}
            assert(s.settlement.finish(s.queue,{action=s.current,token=s.token},s.discard))
            assert(s.counts()==0 and s.queue.queue[2]==parent)
            s.root.items[221]=owner
            s.queue.current,s.queue.queue=parent,{parent,s.tail}
            local child={Type='ISQueueActionsAction',character=s.player,toolkitQueueOperation=parent.toolkitQueueOperation}
            assert(s.settlement.remember(scope,child,{knownInputs=true,items={[222]=true}}))
            assert(not s.settlement.enqueueBorrowedReturn(handle),'an unproved new-token claim remains shared')
            assert(s.settlement.inheritCleanup(child,parent))
        end
        local action=s.settlement.enqueueBorrowedReturn(handle)
        assert((action~=nil)==(ownerState=='replaced'),ownerState..': source owner proof must remain exact and carried')
        if action then
            assert(action.destContainer==fresh and action.destContainer~=s.source)
            s.queue.current,s.queue.queue=action,{action,s.tail}
            action.action,action.transactionId,action.queueList={},21,{{items={value}}}
            assert(s.settlement.beginPlannedReturn(action,guard))
            s.root.items[222],fresh.items[222],value.container=nil,value,fresh
            action.queueList,action.transactionId={},0
            assert(s.settlement.finishPlannedReturn(action,true))
            assert(s.settlement.completionState(s.queue,action)=='ready')
            assert(s.settlement.operationState(pickup).borrowings[1].state=='completed')
        end
    end
end

print('Shared settlement: persistent phases, earned-only cleanup, late isolation and exact native P4 returns passed.')
