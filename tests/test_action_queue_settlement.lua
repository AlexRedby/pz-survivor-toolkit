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
    local clock, receive = 100, nil
    getTimestampMs = function() return clock end
    getSpecificPlayer = function(slot) if slot == 0 then return player end end
    Events = {OnServerCommand = {Add = function(callback) receive = callback end}}
    isClient = function() return client == true end
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
        acknowledgements = acknowledgements, receipt = receipt,
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
print('Shared settlement: deferred ownership claims/lifetimes, ordered required cleanup, exact-ID returns, no effect replay, duplicate completion, owned props and lost resources passed.')
