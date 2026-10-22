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
local deferredMarker, obligationMarker, obligationScope, returnMarker, borrowingMarker = {}, {}, {}, {}, {}
local pollPickups, bindOwnership, bindPickup, sharedBorrowing
local itemTransactionDone, itemTransactionRejected = isItemTransactionDone, isItemTransactionRejected
local function deferred(scope)
    return type(scope) == "table" and scope.marker == deferredMarker
end

function Settlement.deferred(character, token)
    local queue = ISTimedActionQueue.getTimedActionQueue(character)
    local scope = {marker = deferredMarker, character = character, token = token, queue = queue,
        generation = queue.toolkitOperationGeneration or 0, tasks = {}, seen = {}, mixed = false, phase = "prepare"}
    local ledger = {candidates = {}, actions = {}, handles = {}, executors = {}, merging = {}}
    scope[borrowingMarker] = function(candidate) if candidate == scope then return ledger end end
    return scope
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

local function arraySize(values)
    if type(values) ~= "table" then return end
    local size = #values
    for key in pairs(values) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > size then return end
    end
    for index = 1, size do if values[index] == nil then return end end
    return size
end

local function returnGroups(action, empty)
    local groups, result, ids = action.queueList, {}, {}
    local size = arraySize(groups)
    if not size or size == 0 and not empty then return end
    for index = 1, size do
        local group = groups[index]
        local count = type(group) == "table" and arraySize(group.items)
        if not count or count < 1 or count > 20 then return end
        local members = {}
        for memberIndex = 1, count do
            local item = group.items[memberIndex]
            if not item or type(item.getID) ~= "function" or type(item.getFullType) ~= "function" then return end
            local id, fullType = item:getID(), item:getFullType()
            if type(id) ~= "number" or id % 1 ~= 0 or ids[id] or type(fullType) ~= "string" then return end
            ids[id] = true
            members[#members + 1] = {id = id, fullType = fullType}
        end
        result[#result + 1] = {ref = group, members = members}
    end
    return result
end

local function sameMember(item, member)
    return item and member and type(item.getID) == "function" and type(item.getFullType) == "function"
        and item:getID() == member.id and item:getFullType() == member.fullType
end

local function findMember(members, item)
    for _, member in ipairs(members or {}) do if sameMember(item, member) then return member end end
end

local function groupTail(groups)
    local result = {}
    for index = 2, #groups do result[#result + 1] = groups[index] end
    return result
end

local function groupsMatch(expected, actual, append)
    if not actual or (append and #actual < #expected or not append and #actual ~= #expected) then return false end
    for index, group in ipairs(expected) do
        local other = actual[index]
        if group.ref ~= other.ref or (append and #other.members < #group.members
            or not append and #other.members ~= #group.members) then return false end
        for memberIndex, member in ipairs(group.members) do
            local value = other.members[memberIndex]
            if value.id ~= member.id or value.fullType ~= member.fullType then return false end
        end
    end
    return true
end

-- Membership is an execution fact, never ownership of a wiped child action.
local function bindMembers(proof, groups)
    for _, group in ipairs(groups) do
        for _, member in ipairs(group.members) do
            local previous = proof.byId[member.id]
            if previous and (previous.fullType ~= member.fullType or previous.group ~= group.ref) then return false end
        end
    end
    for _, group in ipairs(groups) do
        for index, member in ipairs(group.members) do
            local previous = proof.byId[member.id]
            if not previous then
                previous = {id = member.id, fullType = member.fullType, group = group.ref}
                proof.byId[member.id] = previous
                proof.members[#proof.members + 1] = previous
                if proof.direction == "pickup" then bindPickup(proof, previous)
                else bindOwnership(proof, previous) end
            end
            group.members[index] = previous
        end
    end
    return true
end

local function baseReturnValid(proof)
    local action, character, scope, queue = proof.action, proof.character, proof.scope, proof.queue
    return not proof.invalid and scope.phase ~= "retired" and scope.queue == queue and scope.character == character
        and scope.generation == proof.generation and proof.obligation.token == proof.token and action.character == character
        and action.action == proof.native and isClient() == proof.client
        and not character:isDead() and character:getPlayerNum() == proof.player and character:getOnlineID() == proof.online
        and getSpecificPlayer(proof.player) == character and ISTimedActionQueue.queues[character] == queue
        and (queue.toolkitOperationGeneration or 0) == proof.generation
        and action.srcContainer == proof.source and action.destContainer == proof.destination
        and character:getInventory() == (proof.direction == "pickup" and proof.destination or proof.source)
        and (not proof.client or isItemTransactionDone == itemTransactionDone
            and isItemTransactionRejected == itemTransactionRejected
            and (not proof.continuing or createItemTransaction == proof.createTransaction
                and removeItemTransaction == proof.removeTransaction))
end

local function guardedMember(proof, members)
    local member = findMember(members, proof.action.item)
    return member and proof.guard(proof.action, {id = member.id, fullType = member.fullType})
end

local function cursorValid(proof)
    if not baseReturnValid(proof) then return false end
    local action, attempt = proof.action, proof.active
    if attempt and not attempt.finished then
        return guardedMember(proof, attempt.members)
            and (not proof.client or action.transactionId == attempt.transaction or action.transactionId == 0)
    end
    if proof.next then
        return proof.queue.current == action and proof.queue.queue[1] == action
            and sameMember(action.item, proof.next.groups[1].members[1])
            and guardedMember(proof, proof.next.groups[1].members)
            and (not proof.client or action.transactionId == proof.next.transaction)
    end
    return attempt and guardedMember(proof, attempt.members)
        and (not proof.client or action.transactionId == attempt.transaction or action.transactionId == 0)
end

local function returnAuthority(client, transaction)
    if not client then return "native" end
    if type(transaction) ~= "number" or transaction == 0 or transaction % 1 ~= 0
        or type(itemTransactionDone) ~= "function" or type(itemTransactionRejected) ~= "function"
        or isItemTransactionDone ~= itemTransactionDone or isItemTransactionRejected ~= itemTransactionRejected then return "unavailable" end
    local done, rejected = itemTransactionDone(transaction), itemTransactionRejected(transaction)
    -- Both predicates are true for an absent transaction (empty allMatch).
    if done == true and rejected == false then return "completed" end
    if done == false and rejected == true then return "rejected" end
    return "unavailable"
end

local function observeAttempt(proof, attempt)
    if attempt.terminal then return attempt.terminal end
    if not attempt.finished then return "waiting" end
    if attempt.invalid or not attempt.succeeded or attempt.authority == "unavailable" then attempt.terminal = "unavailable"
    elseif attempt.authority == "rejected" then attempt.terminal = "rejected"
    elseif not attempt.deadline or type(getTimestampMs) ~= "function" or getTimestampMs() >= attempt.deadline
        or not proof.destination:isExistYet() then attempt.terminal = "unavailable"
    else
        local completed = 0
        for _, member in ipairs(attempt.members) do
            if not member.completed then
                local item, sourceItem = proof.destination:getItemById(member.id), proof.source:getItemById(member.id)
                if sameMember(item, member) and item:getContainer() == proof.destination and not item:getIsCraftingConsumed()
                    and not (sourceItem and sourceItem:getContainer() == proof.source) then
                    member.completed = true
                    local candidate = member.borrowed
                    if proof.direction ~= "pickup" and candidate and not candidate.ambiguous then
                        member.shared = member.shared or sharedBorrowing(proof.scope, candidate)
                        candidate.phase = "completed"
                    end
                end
            end
            if member.completed then completed = completed + 1 end
        end
        if completed == #attempt.members then attempt.terminal = "completed" end
    end
    return attempt.terminal or "waiting"
end

-- This capability is only for observation at the already-owned native cursor.
-- Ordinary source matching and policy permissions keep their original item.
function Settlement.returnMatches(action, obligation)
    local proof = returnProof(obligation)
    if not proof or proof.action ~= action or proof.stopped or proof.sequenceError or not cursorValid(proof) then return false end
    local queue = proof.queue
    return queue.current == action and queue.queue[1] == action
end

function Settlement.beginReturn(action, obligation, guard)
    local proof = returnProof(obligation)
    local groups = returnGroups(action)
    if not groups then return false, "group" end
    if proof then
        if not proof.next or proof.active and not proof.active.finished then return false, "duplicate" end
        if not Settlement.returnMatches(action, obligation) or not groupsMatch(proof.next.groups, groups, false) then return false, "continuation" end
    else
        local seal = type(obligation) == "table" and rawget(obligation, obligationScope)
        local scope, token, direction
        if type(seal) == "function" then scope, token, direction = seal(obligation) end
        if not scope or obligation.token ~= token or scope.phase == "retired" then return false, "obligation" end
        if type(guard) ~= "function" or not guard(action) then return false, "source" end
        local character, queue = action.character, scope.queue
        if character ~= scope.character or queue ~= ISTimedActionQueue.queues[character]
            or (queue.toolkitOperationGeneration or 0) ~= scope.generation
            or queue.current ~= action or queue.queue[1] ~= action or not action.action
            or character:isDead() or getSpecificPlayer(character:getPlayerNum()) ~= character then return false, "native_scope" end
        local inventory = character:getInventory()
        if not action.srcContainer or not action.destContainer or action.destContainer == action.srcContainer or not action.item
            or direction == "pickup" and action.destContainer ~= inventory
            or direction ~= "pickup" and action.srcContainer ~= inventory then return false, "endpoints" end
        if not sameMember(action.item, groups[1].members[1]) then return false, "item_identity" end
        if direction ~= "pickup" then pollPickups(scope) end
        proof = {scope = scope, token = token, direction = direction, obligation = obligation, queue = queue, generation = scope.generation,
            action = action, native = action.action, character = character, player = character:getPlayerNum(), online = character:getOnlineID(),
            source = action.srcContainer, destination = action.destContainer, guard = guard, client = isClient(),
            createTransaction = createItemTransaction, removeTransaction = removeItemTransaction,
            members = {}, byId = {}, attempts = {}}
        obligation[returnMarker] = function(candidate) if candidate == obligation then return proof end end
    end
    if proof.direction ~= "pickup" then pollPickups(proof.scope) end
    if not bindMembers(proof, groups) then proof.sequenceError = true; return false, "item_identity" end
    for _, member in ipairs(groups[1].members) do
        if member.attempt then proof.sequenceError = true; return false, "duplicate_item" end
    end
    local ordinal = #proof.attempts + 1
    local transaction = action.transactionId
    local attempt = {ordinal = ordinal, phase = "perform", members = groups[1].members, before = groups,
        transaction = transaction, authority = returnAuthority(proof.client, transaction),
        deadline = type(getTimestampMs) == "function" and getTimestampMs() + 30000}
    for _, member in ipairs(attempt.members) do member.attempt = ordinal end
    proof.active, proof.next = attempt, nil
    proof.attempts[ordinal] = attempt
    return true
end

function Settlement.refreshReturn(action, obligation)
    local proof = returnProof(obligation)
    local attempt = proof and proof.active
    if not attempt or proof.action ~= action or attempt.finished or attempt.refreshed
        or not Settlement.returnMatches(action, obligation) then return false end
    attempt.refreshed = true
    if proof.direction ~= "pickup" then pollPickups(proof.scope) end
    local groups = returnGroups(action, proof.client)
    local expected = proof.client and groupTail(attempt.before) or attempt.before
    -- Native isValid failure may discard the whole unexecuted suffix.
    local truncated = proof.client and groups and #groups == 0
    if not groups or not truncated and not groupsMatch(expected, groups, true) or not bindMembers(proof, groups) then
        attempt.invalid, proof.sequenceError = true, true; return false
    end
    if proof.client then attempt.after = groups
    else
        attempt.before, attempt.members = groups, groups[1].members
        for _, member in ipairs(attempt.members) do member.attempt = attempt.ordinal end
    end
    return true
end

function Settlement.finishReturn(obligation, succeeded)
    local proof = returnProof(obligation)
    local attempt = proof and proof.active
    if not attempt or attempt.finished then return false end
    attempt.finished, attempt.succeeded = true, succeeded == true
    local groups = returnGroups(proof.action, true)
    local expected = attempt.after or groupTail(attempt.before)
    local member = findMember(attempt.members, proof.action.item)
        or groups and groups[1] and groups[1].members[1]
    if not baseReturnValid(proof) or not member or not sameMember(proof.action.item, member)
        or not proof.guard(proof.action, {id = member.id, fullType = member.fullType}) then
        proof.invalid, attempt.invalid = true, true
    end
    if not groups or #groups > 0 and not groupsMatch(expected, groups, false)
        or groups and groups[1] and groups[1].ref == attempt.before[1].ref then
        proof.sequenceError, attempt.invalid = true, true
    end
    -- Capture earned effects before changing the cursor to a later transaction.
    if not proof.invalid then observeAttempt(proof, attempt) end
    if attempt.succeeded and groups and #groups > 0 and not proof.invalid and not proof.sequenceError then
        proof.continuing = true
        local transaction = proof.action.transactionId
        if proof.client and (type(transaction) ~= "number" or transaction == 0 or transaction % 1 ~= 0
            or type(proof.createTransaction) ~= "function" or type(proof.removeTransaction) ~= "function"
            or createItemTransaction ~= proof.createTransaction or removeItemTransaction ~= proof.removeTransaction) then proof.sequenceError = true end
        proof.next = {groups = groups, transaction = transaction}
    else proof.ended = true end
    Settlement.returnState(obligation)
    return true
end

-- Observe before native stop retires its transaction. An unconfirmed cancel is
-- unavailable, never a fabricated server cancellation. Native stop still owns all effects.
function Settlement.stopReturn(action, obligation, guard)
    local proof = returnProof(obligation)
    if proof and proof.active and not proof.active.finished then return false end
    if proof then Settlement.returnState(obligation) end
    if not Settlement.beginReturn(action, obligation, guard) then return false end
    proof = returnProof(obligation)
    local attempt = proof.active
    attempt.phase, attempt.finished = "stop", true
    if proof.client and attempt.authority == "completed" then
        attempt.succeeded = true
        observeAttempt(proof, attempt)
    end
    attempt.succeeded = false
    attempt.terminal = attempt.authority == "rejected" and "rejected" or "unavailable"
    proof.stopped, proof.ended, proof.next = true, true, nil
    return true
end

function Settlement.returnState(obligation)
    local proof = returnProof(obligation)
    if not proof then return end
    if not cursorValid(proof) then proof.invalid = true end
    if proof.invalid then return "unavailable" end
    local waiting, failed, rejected = false, proof.sequenceError or proof.stopped, false
    for _, attempt in ipairs(proof.attempts) do
        local state = observeAttempt(proof, attempt)
        waiting = waiting or state == "waiting"
        failed = failed or state == "unavailable"
        rejected = rejected or state == "rejected"
    end
    if proof.sequenceError then return "unavailable" end
    if proof.next or not proof.ended then return "waiting" end
    for _, member in ipairs(proof.members) do if not member.attempt then failed = true end end
    if waiting then return "waiting" end
    if rejected then return "rejected" end
    return failed and "unavailable" or "completed"
end

function Settlement.returnItems(obligation)
    local state = Settlement.returnState(obligation)
    local proof = returnProof(obligation)
    if not proof then return end
    local items = {}
    for _, member in ipairs(proof.members) do
        local attempt = member.attempt and proof.attempts[member.attempt]
        items[#items + 1] = {id = member.id, fullType = member.fullType,
            state = proof.invalid and "unavailable" or member.completed and "completed"
                or attempt and (attempt.terminal or "waiting") or ((proof.ended or proof.sequenceError) and "unavailable" or "waiting")}
    end
    return items
end

-- Historical receipts are value copies, not live capabilities. They retain
-- already-earned effects after stop/reset and cannot activate a new obligation.
function Settlement.returnAttempts(obligation)
    Settlement.returnState(obligation)
    local proof = returnProof(obligation)
    if not proof then return end
    local attempts = {}
    for _, attempt in ipairs(proof.attempts) do
        local state = attempt.terminal or (proof.invalid and "unavailable" or "waiting")
        local items = {}
        for _, member in ipairs(attempt.members) do
            items[#items + 1] = {id = member.id, fullType = member.fullType, state = member.completed and "completed" or state}
        end
        attempts[#attempts + 1] = {ordinal = attempt.ordinal, phase = attempt.phase, state = state,
            transaction = proof.client and attempt.transaction or 0, authority = attempt.authority, items = items}
    end
    return attempts
end

-- Pickup candidates and activated obligations are separate from enqueue claims.
-- The sealed ledger survives child-action wipe and source membership pruning.
local function borrowing(scope)
    local seal = type(scope) == "table" and rawget(scope, borrowingMarker)
    return type(seal) == "function" and seal(scope) or nil
end

local function borrowingLive(scope)
    return deferred(scope) and scope.phase ~= "retired" and Toolkit.Settings and Toolkit.Settings.actionQueue()
        and not scope.character:isDead() and ISTimedActionQueue.queues[scope.character] == scope.queue
        and (scope.queue.toolkitOperationGeneration or 0) == scope.generation
end

-- The exact native pickup proves its original owner without relying on the
-- older enqueue-only pickup map. Competing task claims still prevent exclusive
-- cleanup; this classification grants no operation edit permission.
sharedBorrowing = function(scope, candidate)
    if not scope.tasks[candidate.owner] then return true end
    for token, task in pairs(scope.tasks) do
        local pickup = task.pickups[candidate.id]
        if pickup and (pickup.ambiguous or pickup.fullType ~= candidate.fullType
            or pickup.container ~= candidate.source or token ~= candidate.owner) then return true end
        if token ~= candidate.owner and (task.unknownInputs or task.items[candidate.id]) then return true end
    end
    return false
end

function Settlement.preparePickup(scope, action)
    local ledger = borrowing(scope)
    if not ledger or not borrowingLive(scope) or not action or action.character ~= scope.character
        or not scope.tasks[action.toolkitQueueOperation] or not action.item
        or not action.srcContainer or action.srcContainer == scope.character:getInventory()
        or action.destContainer ~= scope.character:getInventory() or action.item:getContainer() ~= action.srcContainer then return false end
    if ledger.actions[action] then return false end
    local id, fullType = action.item:getID(), action.item:getFullType()
    if type(id) ~= "number" or id % 1 ~= 0 or type(fullType) ~= "string" then return false end
    pollPickups(scope)
    local candidate = {id = id, fullType = fullType, source = action.srcContainer, destination = action.destContainer,
        owner = action.toolkitQueueOperation, phase = "prepare"}
    -- No outbound proof separates two unresolved borrowing episodes. Never let
    -- a late old pickup acquire the new episode merely because its ID matches.
    for _, previous in ipairs(ledger.candidates) do
        if previous.id == id and previous.phase ~= "completed" then previous.ambiguous, candidate.ambiguous = true, true end
    end
    ledger.candidates[#ledger.candidates + 1], ledger.actions[action] = candidate, candidate
    ledger.executors[action] = {[id] = candidate}
    return true
end

bindPickup = function(proof, member)
    local ledger = borrowing(proof.scope)
    local mapped = ledger and ledger.executors[proof.action]
    local candidate = mapped and mapped[member.id]
    if candidate and candidate.fullType == member.fullType and candidate.source == proof.source
        and candidate.destination == proof.destination and candidate.phase == "prepare" and not candidate.ambiguous then
        member.borrowed = candidate
    end
end

local function queued(queue, action)
    for _, value in ipairs(queue.queue) do if value == action then return true end end
    return false
end

function Settlement.beforePickupMerge(scope, action, guard)
    local ledger = borrowing(scope)
    if not ledger or not borrowingLive(scope) or not ledger.actions[action] or not queued(scope.queue, action)
        or type(guard) ~= "function" or not guard(action) then return false end
    local pending, following = {}, false
    for _, child in ipairs(scope.queue.queue) do
        if child == action then following = true
        elseif following then
            local candidate = ledger.actions[child]
            if candidate and child.character == scope.character and child.toolkitQueueOperation == candidate.owner
                and child.srcContainer == candidate.source and child.destContainer == candidate.destination
                and child.srcContainer == action.srcContainer and child.destContainer == action.destContainer
                and sameMember(child.item, candidate) and guard(child) then
                pending[#pending + 1] = {action = child, candidate = candidate}
            end
        end
    end
    ledger.merging[action] = pending
    return true
end

local function wiped(action)
    for _ in pairs(action) do return false end
    return true
end

local function mergedPickups(scope, action, ledger)
    local pending = ledger.merging[action]
    ledger.merging[action] = nil
    if not pending or not borrowingLive(scope) then return end
    local groups, members = returnGroups(action, true), {}
    for _, group in ipairs(groups or {}) do
        for _, member in ipairs(group.members) do members[member.id] = member.fullType end
    end
    local mapped = ledger.executors[action]
    for _, entry in ipairs(pending) do
        local child, candidate = entry.action, entry.candidate
        -- The reviewed native merge removes and wipes the actual child. A
        -- matching item from an unrelated executor is not pickup provenance.
        if mapped and not queued(scope.queue, child) and wiped(child)
            and members[candidate.id] == candidate.fullType then mapped[candidate.id] = candidate end
    end
end

pollPickups = function(scope)
    local ledger = borrowing(scope)
    if not ledger or not borrowingLive(scope) then return end
    for _, handle in pairs(ledger.handles) do
        Settlement.returnState(handle)
        local proof = returnProof(handle)
        if proof and not proof.invalid then
            for _, member in ipairs(proof.members) do
                local candidate = member.borrowed
                if candidate and candidate.phase == "prepare" and not candidate.ambiguous and member.completed then
                    local attempt = proof.attempts[member.attempt]
                    candidate.phase, candidate.attempt = "active", attempt.ordinal
                    candidate.transaction = proof.client and attempt.transaction or 0
                    candidate.authority = attempt.authority
                end
            end
        end
    end
end

function Settlement.poll(scope) pollPickups(scope) end

-- Any reviewed native departure fences an unconfirmed borrowing episode,
-- even when the departure itself has no P4 cleanup record.
function Settlement.departure(scope, action)
    local ledger = borrowing(scope)
    if not ledger or not borrowingLive(scope) or action.srcContainer ~= scope.character:getInventory()
        or action.destContainer == action.srcContainer then return end
    pollPickups(scope)
    local groups = returnGroups(action)
    for _, group in ipairs(groups or {}) do
        for _, member in ipairs(group.members) do
            for _, candidate in ipairs(ledger.candidates) do
                if candidate.id == member.id and candidate.fullType == member.fullType and candidate.phase == "prepare" then
                    candidate.ambiguous = true
                end
            end
        end
    end
end

function Settlement.beginPickup(scope, action, guard)
    local ledger = borrowing(scope)
    local candidate = ledger and ledger.actions[action]
    if not candidate or not borrowingLive(scope) or type(guard) ~= "function" then return false end
    local handle = ledger.handles[action]
    if not handle then
        local owner, source, destination = candidate.owner, candidate.source, candidate.destination
        if action.toolkitQueueOperation ~= owner or action.srcContainer ~= source or action.destContainer ~= destination
            or not guard(action) then return false end
        handle = {token = owner}
        handle[obligationScope] = function(value) if value == handle then return scope, owner, "pickup" end end
        ledger.handles[action] = handle
    end
    return Settlement.beginReturn(action, handle, function(value)
        return value == action and action.toolkitQueueOperation == candidate.owner
            and action.srcContainer == candidate.source and action.destContainer == candidate.destination and guard(value)
    end)
end

function Settlement.pickupMatches(scope, action)
    local ledger = borrowing(scope)
    local handle = ledger and ledger.handles[action]
    return handle and borrowingLive(scope) and Settlement.returnMatches(action, handle) or false
end

function Settlement.refreshPickup(scope, action)
    local ledger = borrowing(scope)
    if ledger then mergedPickups(scope, action, ledger) end
    local handle = ledger and ledger.handles[action]
    return handle and Settlement.refreshReturn(action, handle) or false
end

function Settlement.finishPickup(scope, action, succeeded)
    local ledger = borrowing(scope)
    local handle = ledger and ledger.handles[action]
    if not handle then return false end
    local result = Settlement.finishReturn(handle, succeeded)
    pollPickups(scope)
    return result
end

bindOwnership = function(proof, member)
    local ledger, found = borrowing(proof.scope)
    for _, candidate in ipairs(ledger and ledger.candidates or {}) do
        if candidate.id == member.id and candidate.fullType == member.fullType and not candidate.ambiguous
            and candidate.phase == "active" and (not candidate.returning or candidate.returning == proof)
            and candidate.source == proof.destination and candidate.destination == proof.source then
            if found then return end
            found = candidate
        end
    end
    member.borrowed = found
    if found then
        found.returning = proof
        member.shared = sharedBorrowing(proof.scope, found)
    end
end

-- Value copies describe earned ownership, never a capability to edit or execute.
function Settlement.returnOwnership(obligation)
    local proof = returnProof(obligation)
    if not proof or proof.direction == "pickup" then return end
    Settlement.returnState(obligation)
    local result = {}
    for _, member in ipairs(proof.members) do
        local candidate = member.borrowed
        local bound = candidate and not candidate.ambiguous and (member.completed or borrowingLive(proof.scope))
        local value = {id = member.id, fullType = member.fullType, state = "unbound", shared = true}
        if bound then
            value.owner, value.state = candidate.owner, member.completed and "completed" or "active"
            value.shared = member.shared or not member.completed
                and sharedBorrowing(proof.scope, candidate)
            value.pickupAttempt, value.pickupTransaction, value.pickupAuthority = candidate.attempt, candidate.transaction, candidate.authority
        end
        result[#result + 1] = value
    end
    return result
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
