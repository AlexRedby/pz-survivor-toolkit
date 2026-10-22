-- Cancellation settles already-earned obligations; it never undoes native effects.
local Toolkit = PZSurvivorToolkit
local Settlement = {}
Toolkit.ActionQueueSettlement = Settlement
local providers, byId = {}, {}
local cleanupMarker = {}

-- Families retain their own identity/effect proofs. Registration grants no edit rights.
function Settlement.register(id, provider)
    assert(type(id) == "string" and type(provider) == "table" and type(provider.retain) == "function")
    assert(provider.ownsPickup == nil or type(provider.ownsPickup) == "function")
    local entry = byId[id]
    if not entry then
        entry = {id = id}
        providers[#providers + 1], byId[id] = entry, entry
    end
    entry.retain, entry.ownsPickup = provider.retain, provider.ownsPickup
end

local function retained(action, current, queue)
    for _, provider in ipairs(providers) do
        if provider.retain(action, current, queue) then return provider.id end
    end
end

local function ownedPickup(current, id)
    for _, provider in ipairs(providers) do
        if provider.ownsPickup and provider.ownsPickup(current, id) then return true end
    end
    return false
end

function Settlement.isCleanup(action)
    return action and action.toolkitQueueReturn == cleanupMarker or false
end

local function insert(queue, action, index)
    -- Required work gets a fresh operation: cancelling its former owner cannot revoke it.
    action.toolkitQueueOperation, action.toolkitQueueReturn = {}, cleanupMarker
    table.insert(queue.queue, index, action)
end

-- A local effect is not an authoritative outcome. Marked client actions need
-- both observations; unmarked native/SP callbacks retain their existing proof.
local effectMarker = {}
local function effectProof(handle)
    if type(handle) ~= "table" then return end
    local seal = rawget(handle, effectMarker)
    if type(seal) == "function" then return seal(handle) end
end
function Settlement.captureEffect(action)
    local character = action.character
    local queue = ISTimedActionQueue.queues[character]
    local required = isClient() and (action.toolkitNativeTransaction ~= nil or action.toolkitNativeKind ~= nil)
    local acknowledgements = Toolkit.ActionQueueAcknowledgements
    local now = type(getTimestampMs) == "function" and getTimestampMs() or nil
    local handle = {}
    local proof = {action = action, native = action.action, character = character, queue = queue,
        generation = queue and (queue.toolkitOperationGeneration or 0), required = required,
        transaction = action.toolkitNativeTransaction, kind = action.toolkitNativeKind,
        acknowledgements = acknowledgements, capture = acknowledgements and acknowledgements.capture,
        observe = acknowledgements and acknowledgements.observe, deadline = now and now + 30000}
    handle[effectMarker] = function(candidate) if candidate == handle then return proof end end
    if required and type(proof.capture) == "function" then proof.receipt = proof.capture(action) end
    return handle
end

local function effectTerminal(proof, status)
    proof.terminal = status
    return status
end

function Settlement.effectState(handle, observed)
    local proof = effectProof(handle)
    if not proof then return "unavailable" end
    if proof.terminal then return proof.terminal end
    local character, action, queue = proof.character, proof.action, proof.queue
    if action.character ~= character or action.action ~= proof.native or not queue
        or ISTimedActionQueue.queues[character] ~= queue or character:isDead()
        or (queue.toolkitOperationGeneration or 0) ~= proof.generation
        or action.toolkitNativeTransaction ~= proof.transaction or action.toolkitNativeKind ~= proof.kind then return effectTerminal(proof, "unavailable") end
    if proof.confirmed then return "completed" end
    if not proof.required then
        return observed == true and "completed" or effectTerminal(proof, "unavailable")
    end
    local acknowledgements = proof.acknowledgements
    if not acknowledgements or Toolkit.ActionQueueAcknowledgements ~= acknowledgements
        or type(proof.capture) ~= "function" or type(proof.observe) ~= "function"
        or acknowledgements.capture ~= proof.capture or acknowledgements.observe ~= proof.observe
        or not proof.deadline or type(getTimestampMs) ~= "function" then return effectTerminal(proof, "unavailable") end
    -- An early observer may precede Started, but can only bind that exact
    -- still-current native action. Never replace a receipt after binding it.
    if not proof.receipt then proof.receipt = proof.capture(action) end
    if proof.receipt then
        local state = proof.observe(action, proof.receipt)
        if state == "canceled" or state == "rejected" then return effectTerminal(proof, state) end
        if state == nil then return effectTerminal(proof, "unavailable") end
        if state == "completed" and observed == true then return "completed" end
    end
    if getTimestampMs() >= proof.deadline then return effectTerminal(proof, "unavailable") end
    return "waiting"
end

function Settlement.confirmEffect(handle, observed)
    local proof = effectProof(handle)
    if not proof or proof.confirmed or Settlement.effectState(handle, observed) ~= "completed" then return false end
    proof.confirmed = true
    return true
end

-- A delayed producer may collect several operations before constructing its
-- native cleanup. These are ownership claims, not proof that an effect ran.
local deferredMarker, obligationMarker, obligationScope, returnMarker = {}, {}, {}, {}
local itemTransactionDone, itemTransactionRejected = isItemTransactionDone, isItemTransactionRejected
local function deferred(scope)
    return type(scope) == "table" and scope.marker == deferredMarker
end

function Settlement.deferred(character, token)
    local queue = ISTimedActionQueue.getTimedActionQueue(character)
    return {marker = deferredMarker, character = character, token = token, queue = queue,
        generation = queue.toolkitOperationGeneration or 0, tasks = {}, seen = {}, mixed = false, phase = "prepare"}
end

function Settlement.remember(scope, action, contract)
    if not deferred(scope) or scope.phase == "retired" or action.character ~= scope.character
        or not action.toolkitQueueOperation then return false end
    local token = action.toolkitQueueOperation
    if scope.token ~= token then scope.mixed = true end
    if scope.seen[action] then return false end
    scope.seen[action] = true
    local task = scope.tasks[token]
    if not task then task = {items = {}, pickups = {}}; scope.tasks[token] = task end
    if not contract or contract.knownInputs == false or contract.dynamicInputs or contract.dynamicInputsByType then
        task.unknownInputs = true
    end
    for id in pairs(contract and contract.items or {}) do task.items[id] = true end
    for id in pairs(contract and contract.containerOwners or {}) do task.items[id] = true end
    for item, container in pairs(token.toolkitPickups or {}) do
        local id, fullType = item:getID(), item:getFullType()
        local previous = task.pickups[id]
        task.pickups[id] = {container = container, fullType = fullType,
            ambiguous = previous and (previous.ambiguous or previous.container ~= container or previous.fullType ~= fullType) or false}
    end
    return true
end

function Settlement.owner(scope, id, fullType, destination)
    if not deferred(scope) or scope.phase == "retired" then return end
    local owner
    for token, task in pairs(scope.tasks) do
        local pickup = task.pickups[id]
        if pickup and pickup.ambiguous then return end
        if pickup and pickup.fullType == fullType and pickup.container == destination then
            if owner then return end
            owner = token
        end
    end
    if not owner then return end
    for token, task in pairs(scope.tasks) do
        if token ~= owner and (task.unknownInputs or task.items[id]) then return end
    end
    return owner
end

function Settlement.context(scope, owner)
    if not deferred(scope) or scope.phase == "retired" or owner ~= nil and not scope.tasks[owner] then return end
    local token = owner or scope.token
    local shared = owner == nil and scope.mixed
    if shared then
        scope.restoreToken = scope.restoreToken or {}
        token = scope.restoreToken
    end
    if scope.phase == "prepare" then scope.phase = "cleanup" end
    return {settlement = scope, character = scope.character, token = token, queue = scope.queue,
        generation = scope.generation, sharedCleanup = shared or nil}
end

function Settlement.isLive(context)
    local scope = context and context.settlement
    if not deferred(scope) or scope.phase == "retired" or context.character ~= scope.character
        or context.queue ~= scope.queue or context.generation ~= scope.generation then return false end
    local character, queue, token = scope.character, scope.queue, context.token
    if not token or token.toolkitCancelled or token ~= scope.token and token ~= scope.restoreToken and not scope.tasks[token]
        or context.sharedCleanup and (not scope.mixed or token ~= scope.restoreToken)
        or not Toolkit.Settings or not Toolkit.Settings.actionQueue() or character:isDead()
        or ISTimedActionQueue.queues[character] ~= queue
        or (queue.toolkitOperationGeneration or 0) ~= scope.generation then return false end
    return true
end

function Settlement.obligation(context)
    if not Settlement.isLive(context) then return end
    context.settlement.phase = "scheduled"
    local scope = context.settlement
    local token = context.token
    local obligation = {marker = obligationMarker, token = token, phase = "cleanup",
        required = scope.mixed and token == scope.restoreToken}
    obligation[obligationScope] = function(candidate) if candidate == obligation then return scope, token end end
    return obligation
end

-- Native item transfers use their own transaction manager, not the generic
-- timed-action ACK. Observe its result before perform removes that transaction.
-- These observations do not grant edit rights or advance/retry native work.
local function returnProof(obligation)
    local seal = type(obligation) == "table" and rawget(obligation, returnMarker)
    return type(seal) == "function" and seal(obligation) or nil
end

function Settlement.beginReturn(action, obligation, guard)
    local seal = type(obligation) == "table" and rawget(obligation, obligationScope)
    local scope, token
    if type(seal) == "function" then scope, token = seal(obligation) end
    if not scope or obligation.token ~= token or scope.phase == "retired" then return false, "obligation" end
    if returnProof(obligation) then return false, "duplicate" end
    if type(guard) ~= "function" or not guard(action) then return false, "source" end
    local character, queue = action.character, scope.queue
    local item, destination, groups = action.item, action.destContainer, action.queueList
    if character ~= scope.character or queue ~= ISTimedActionQueue.queues[character]
        or (queue.toolkitOperationGeneration or 0) ~= scope.generation
        or queue.current ~= action or queue.queue[1] ~= action or not action.action
        or character:isDead() or getSpecificPlayer(character:getPlayerNum()) ~= character then return false, "native_scope" end
    if action.srcContainer ~= character:getInventory() or not destination or destination == action.srcContainer
        or not item then return false, "endpoints" end
    if not groups or #groups ~= 1 or not groups[1].items or #groups[1].items ~= 1 then return false, "singleton" end
    local member = groups[1].items[1]
    -- Host replication can rebind action.item while its native group retains
    -- the earlier Java proxy. Inventory identity, not proxy equality, is stable.
    if not member or type(member.getID) ~= "function" or type(member.getFullType) ~= "function"
        or member:getID() ~= item:getID() or member:getFullType() ~= item:getFullType() then return false, "item_identity" end
    local client, transaction, authority = isClient(), action.transactionId, "native"
    if client then
        authority = "unavailable"
        if type(transaction) == "number" and transaction ~= 0 and transaction % 1 == 0
            and type(itemTransactionDone) == "function" and type(itemTransactionRejected) == "function"
            and isItemTransactionDone == itemTransactionDone and isItemTransactionRejected == itemTransactionRejected then
            local done, rejected = itemTransactionDone(transaction), itemTransactionRejected(transaction)
            -- Both queries are true for a missing native transaction (empty allMatch).
            if done == true and rejected == false then authority = "completed"
            elseif done == false and rejected == true then authority = "rejected" end
        end
    end
    local proof = {scope = scope, token = token, queue = queue, generation = scope.generation, action = action, native = action.action,
        character = character, player = character:getPlayerNum(), online = character:getOnlineID(),
        id = item:getID(), fullType = item:getFullType(), source = action.srcContainer,
        destination = destination, guard = guard, client = client, transaction = transaction, authority = authority,
        deadline = type(getTimestampMs) == "function" and getTimestampMs() + 30000}
    obligation[returnMarker] = function(candidate) if candidate == obligation then return proof end end
    return true
end

function Settlement.finishReturn(obligation, succeeded)
    local proof = returnProof(obligation)
    if not proof or proof.finished then return false end
    proof.finished, proof.succeeded = true, succeeded == true
    Settlement.returnState(obligation)
    return true
end

function Settlement.returnState(obligation)
    local proof = returnProof(obligation)
    if not proof then return end
    local action, character, scope = proof.action, proof.character, proof.scope
    local queue = proof.queue
    if scope.phase == "retired" or scope.queue ~= queue or scope.character ~= character
        or scope.generation ~= proof.generation or obligation.token ~= proof.token or action.character ~= character
        or action.action ~= proof.native or isClient() ~= proof.client
        or character:isDead() or character:getPlayerNum() ~= proof.player or character:getOnlineID() ~= proof.online
        or getSpecificPlayer(proof.player) ~= character or ISTimedActionQueue.queues[character] ~= queue
        or (queue.toolkitOperationGeneration or 0) ~= proof.generation
        or action.srcContainer ~= proof.source or action.destContainer ~= proof.destination
        or character:getInventory() ~= proof.source or not action.item
        or action.item:getID() ~= proof.id or action.item:getFullType() ~= proof.fullType
        or not proof.guard(action) or proof.client and (isItemTransactionDone ~= itemTransactionDone
            or isItemTransactionRejected ~= itemTransactionRejected
            or action.transactionId ~= proof.transaction and action.transactionId ~= 0) then
        proof.terminal = "unavailable"
    end
    if proof.terminal then return proof.terminal end
    if not proof.deadline or type(getTimestampMs) ~= "function" or getTimestampMs() >= proof.deadline then
        proof.terminal = "unavailable"
        return proof.terminal
    end
    if not proof.finished then return "waiting" end
    if not proof.succeeded or proof.authority == "unavailable" then proof.terminal = "unavailable"
    elseif proof.authority == "rejected" then proof.terminal = "rejected"
    elseif action.queueList and #action.queueList > 0 or not proof.destination:isExistYet() then proof.terminal = "unavailable"
    else
        local item = proof.destination:getItemById(proof.id)
        local sourceItem = proof.source:getItemById(proof.id)
        if item and item:getID() == proof.id and item:getFullType() == proof.fullType
            and item:getContainer() == proof.destination and not item:getIsCraftingConsumed()
            and not (sourceItem and sourceItem:getContainer() == proof.source) then proof.terminal = "completed"
        end
    end
    return proof.terminal or "waiting"
end

function Settlement.required(obligation)
    return type(obligation) == "table" and obligation.marker == obligationMarker and obligation.required == true
end

function Settlement.close(scope)
    if deferred(scope) then scope.phase = "retired" end
end

-- Called only after the current native step/Host receipt has settled. Pickup
-- locations are intents: only the surviving exact direct-root item can activate
-- a return. Family adapters own any stronger effect/cleanup proof they require.
function Settlement.finish(queue, request, discard)
    local current, token = request.action, request.token
    if request.settlement or not queue or queue.current ~= current or queue.queue[1] ~= current
        or current.character ~= queue.character or current.toolkitQueueOperation ~= token then return false end
    local state = {phase = "body", obligations = {}, discarded = 0}
    request.settlement = state
    local operations = Toolkit.ActionQueueOperations
    local inventory = queue.character:getInventory()
    local last = 1
    while token and queue.queue[last + 1] and queue.queue[last + 1].toolkitQueueOperation == token do last = last + 1 end
    local returns, cleanup = {}, {}
    local function rememberReturn(item, destination)
        local id, fullType = item:getID(), item:getFullType()
        local previous = returns[id]
        if previous then
            if previous.fullType ~= fullType or previous.destination ~= destination then previous.ambiguous = true end
        else
            returns[id] = {fullType = fullType, destination = destination, ambiguous = destination == nil}
        end
    end
    for i = last, 2, -1 do
        local member = table.remove(queue.queue, i)
        if operations.isTransfer(member) and member.allowMissingItems and member.item
            and member.srcContainer == inventory and member.destContainer ~= inventory then
            rememberReturn(member.item, member.destContainer)
        end
        local provider = retained(member, current, queue)
        if provider then
            table.insert(cleanup, 1, {kind = "cleanup", provider = provider, action = member})
        else
            discard(member, false)
            state.discarded = state.discarded + 1
        end
    end
    -- The current effect is already native/authoritative. Only release its owned
    -- bookkeeping; never force-cancel it again or synthesize a compensating effect.
    discard(current, true)
    for item, source in pairs(type(token) == "table" and token.toolkitPickups or {}) do rememberReturn(item, source) end
    local containers = ISInventoryPaneContextMenu.getContainers(queue.character)
    local index = 2
    state.phase = "cleanup"
    for _, obligation in ipairs(cleanup) do
        insert(queue, obligation.action, index)
        state.obligations[#state.obligations + 1] = obligation
        index = index + 1
    end
    for id, expected in pairs(returns) do
        -- Replica replacement must preserve the exact ID/type. Conflicting history
        -- cannot choose a source by table iteration order or reclaim another item.
        local destination = expected.destination
        local item = not expected.ambiguous and inventory:getItemById(id)
        if not ownedPickup(current, id) and item and item:getID() == id and item:getFullType() == expected.fullType
            and item:getContainer() == inventory and not item:getIsCraftingConsumed()
            and destination:isExistYet() and (containers:contains(destination)
                or Toolkit.ActionQueuePolicy.isCarriedContainer(destination, queue.character)) then
            local action = ISInventoryTransferUtil.newInventoryTransferAction(queue.character, item, inventory, destination)
            if action.Type == "ISInventoryTransferAction"
                or (not isClient() and Toolkit.ActionQueueCarts and Toolkit.ActionQueueCarts.isTransfer(action)) then
                if action.Type == "ISInventoryTransferAction" then Toolkit.BulkActions.guardTransfer(action) end
                action:setAllowMissingItems(true)
                insert(queue, action, index)
                state.obligations[#state.obligations + 1] = {kind = "return", itemId = id, itemType = expected.fullType, destination = destination, action = action}
                index = index + 1
            end
        end
    end
    state.phase = "scheduled"
    return true
end

return Settlement
