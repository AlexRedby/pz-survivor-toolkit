-- Cancellation settles already-earned obligations; it never undoes native effects.
local Toolkit = PZSurvivorToolkit
local Settlement = {}
Toolkit.ActionQueueSettlement = Settlement
local providers, byId = {}, {}
local executionProof = require "PZSurvivorToolkit/SourceProof"
-- Keep the new dependency inside the existing source-owned wrapper boundary.
-- Unknown factories must never receive private callbacks or attempt records.
local function transferOutcomes(module)
    if type(module) ~= "table" or getmetatable(module) ~= nil or not executionProof
        or type(executionProof.own) ~= "function" or type(executionProof.closure) ~= "function" then return end
    local own, origin = executionProof.own, executionProof.closure
    local member = own(module, "sameMember")
    local retained = own(module, "retained")
    local authority = own(module, "authorityReader")
    local observer = own(module, "observer")
    local source = own(module, "atSource")
    local file = "ActionQueueTransferOutcome.lua"
    if origin(member, file) and origin(retained, file) and origin(authority, file) and origin(observer, file)
        and origin(source, file) and executionProof.own == own and executionProof.closure == origin then
        return member, retained, authority, observer, source
    end
end
local outcomeModule = require "PZSurvivorToolkit/ActionQueueTransferOutcome"
local bindTransferOutcomes
local sameMember, retainedTransfer, returnAuthority, observeAttempt, sourceEvidence
-- Some native-source fixtures and delayed loaders expose metadata only later.
-- Bootstrap once when it becomes available; verified hot calls use the direct
-- captured functions and unsupported modules never receive private arguments.
sameMember = function(item, member)
    if bindTransferOutcomes and bindTransferOutcomes() then return sameMember(item, member) end
    return false
end
retainedTransfer = function(action, execution)
    if bindTransferOutcomes and bindTransferOutcomes() then return retainedTransfer(action, execution) end
    return false
end
returnAuthority = function(client, transaction)
    if bindTransferOutcomes and bindTransferOutcomes() then return returnAuthority(client, transaction) end
    return "unavailable"
end
observeAttempt = function(proof, attempt)
    if bindTransferOutcomes and bindTransferOutcomes() then return observeAttempt(proof, attempt) end
    return "unavailable"
end
sourceEvidence = function(action, expected)
    if bindTransferOutcomes and bindTransferOutcomes() then return sourceEvidence(action, expected) end
    return false
end
local returnFailures, failureSerial = {}, 0
local MAX_RETURN_FAILURES = 32
local MAX_EXECUTION_MEMBERS, MAX_EXECUTION_BORROWING_WORK = 32, 128
local cleanupMarker = {}

local operationMarker, stepMarker = {}, {}
-- An accepted cancellation owns only its current native episode and earned
-- cleanup. Editor invalidation still revokes all optional continuations.
local cancellations = {}
local function cancellation(queue)
    local state = cancellations[queue]
    if not state then return end
    local current = queue.current
    local member = state.members[current]
    if ISTimedActionQueue.queues[state.character] ~= queue or queue.character ~= state.character
        or queue.queue ~= state.list or state.character:isDead()
        or getSpecificPlayer(state.character:getPlayerNum()) ~= state.character
        or state.request.action ~= state.action or state.request.token ~= state.token
        or (queue.toolkitOperationGeneration or 0) ~= state.generation
        or queue.queue[1] ~= current
        or not (current == state.action and current.action == state.native
            and current.toolkitQueueOperation == state.token
            and (queue.toolkitGroupCancel == state.request or state.scheduled and queue.toolkitGroupCancel == nil)
            or state.scheduled and member and not queue.toolkitGroupCancel
                and current.toolkitQueueOperation == member.token
                and (not member.native or current.action == member.native)) then
        cancellations[queue] = nil; return
    end
    return state
end
local function cancellationRecord(record)
    local state = record and cancellation(record.queue)
    if not state then return end
    if state.record == record then return state end
    for action, member in pairs(state.members) do
        if action.toolkitQueueOperation == member.token and record.token == member.token then return state end
    end
end
local function generationMatches(character, queue, generation, action)
    if (queue.toolkitOperationGeneration or 0) == generation then return true end
    local state = cancellation(queue)
    if not state or state.character ~= character then return false end
    local member = state.members[action]
    return state.record.actions[action] ~= nil and generation == state.originalGeneration
        or member ~= nil and (member.generation == generation or member.nativeGeneration == generation
            or state.originalGeneration == generation)
            and action.toolkitQueueOperation == member.token
end
function Settlement.cancellationGeneration(action, generation)
    local queue = action and ISTimedActionQueue.queues[action.character]
    local state = queue and cancellation(queue)
    return not not (state and generationMatches(action.character, queue, generation, action))
end
function Settlement.drainingAction(action)
    local queue = action and ISTimedActionQueue.queues[action.character]
    local state = queue and cancellation(queue)
    return not not (state and queue.current == action
        and (action == state.action or state.members[action]))
end
function Settlement.bindCancellation(action)
    local queue = action and ISTimedActionQueue.queues[action.character]
    local state = queue and cancellation(queue)
    local member = state and state.members[action]
    if member and not member.native and action.action then
        member.native, member.nativeGeneration = action.action, queue.toolkitOperationGeneration or 0
    end
end
function Settlement.resetCancellation(queue) cancellations[queue] = nil end
function Settlement.completeCancellation(queue, action)
    local state = cancellation(queue)
    if not state then return end
    if state.members[action] then state.members[action] = nil end
    for _ in pairs(state.members) do return end
    cancellations[queue] = nil
end
-- Only this actual editor transition may bridge a generation for admitted debt.
-- Reset/death/replaced queues and arbitrary generation changes never do.
function Settlement.invalidateEditor(queue)
    local state = cancellation(queue)
    -- Explicit editor invalidation revokes optional UI debt; admitted native
    -- cancellation receipts retain their separate generation bridge below.
    Settlement.resetReturnFailures(queue)
    Toolkit.ActionQueueOperations.invalidateQueue(queue)
    if state and not Toolkit.Settings.actionQueue()
        and (queue.toolkitOperationGeneration or 0) == state.generation + 1 then
        state.generation = queue.toolkitOperationGeneration
    end
end
local function operationLive(record)
    return record and record.queue == ISTimedActionQueue.queues[record.character]
        and record.queue.character == record.character and not record.character:isDead()
        and ((record.queue.toolkitOperationGeneration or 0) == record.generation
            and Toolkit.Settings and Toolkit.Settings.actionQueue() or cancellationRecord(record))
end

local function operation(character, token, create)
    if type(token) ~= "table" or not character then return end
    local seal = rawget(token, operationMarker)
    local record = type(seal) == "function" and seal(token)
    if record then return operationLive(record) and record.character == character and record or nil end
    local queue = ISTimedActionQueue.queues[character]
    if not create or not queue then return end
    record = {character = character, token = token, queue = queue,
        generation = queue.toolkitOperationGeneration or 0, phase = "prepare", steps = {}, actions = {}, borrowings = {}}
    if not operationLive(record) then return end
    token[operationMarker] = function(value) if value == token then return record end end
    return record
end

function Settlement.admitCancellation(queue, request, decision)
    local policy = Toolkit.ActionQueuePolicy
    local action = request and request.action
    if not Toolkit.Settings.actionQueue() or not decision or decision.allowed ~= true or decision.first ~= 1
        or not policy or not policy.editUnchanged(queue, decision.snapshot)
        or not action or not action.action
        or action.character ~= queue.character or queue.current ~= action or queue.queue[1] ~= action
        or request.token ~= action.toolkitQueueOperation or type(request.token) ~= "table" or request.token.toolkitCancelled then return false end
    local record = operation(action.character, request.token, true)
    if not record then return false end
    local scopes = {}
    local function capture(scope)
        if scope and scope.phase ~= "retired" and scope.character == action.character
            and scope.queue == queue and scope.generation == record.generation then scopes[scope] = true end
    end
    capture(record.preparationScope)
    for _, binding in ipairs(record.borrowings) do capture(binding.scope) end
    local execution = Toolkit.ActionQueueExecution
    if execution and type(execution.admitEditMember) == "function" then
        for index = decision.first, decision.last do execution.admitEditMember(queue.queue[index]) end
    end
    cancellations[queue] = {character = action.character, action = action, native = action.action,
        token = request.token, request = request, record = record, list = queue.queue, members = {}, scopes = scopes,
        generation = queue.toolkitOperationGeneration or 0, originalGeneration = record.generation}
    return true
end
local function admitCleanup(queue, action)
    local state = cancellation(queue)
    if state then state.members[action] = {token = action.toolkitQueueOperation,
        generation = queue.toolkitOperationGeneration or 0, native = action.action} end
end

local function stepProof(handle)
    local seal = type(handle) == "table" and rawget(handle, stepMarker)
    return type(seal) == "function" and seal(handle) or nil
end

-- Records live with their operation, not the shrinking native queue. Merely
-- accepting or removing a step never earns an effect or permission to replay it.
function Settlement.track(action, phase)
    if phase ~= "prepare" and phase ~= "body" and phase ~= "cleanup" then return end
    local record = action and operation(action.character, action.toolkitQueueOperation, true)
    if not record then return end
    local step = record.actions[action]
    if step then
        -- Generic enqueue tracking must not overwrite a reviewed adapter's role.
        if phase ~= "body" and step.state == "pending" then step.phase = phase end
        return step.handle
    end
    step = {operation = record, action = action, phase = phase, state = "pending"}
    local handle = {}
    handle[stepMarker] = function(value) if value == handle then return step end end
    step.handle = handle
    record.actions[action], record.steps[#record.steps + 1] = step, step
    return handle
end

function Settlement.started(action)
    Settlement.track(action, "body")
    local record = action and operation(action.character, action.toolkitQueueOperation)
    local step = record and record.actions[action]
    if step then step.started, record.phase = true, step.phase end
end

-- The native callback's receipt AND the adapter's exact observed effect must
-- refer to this step. A receipt from another action cannot pay its obligation.
function Settlement.bindEffect(handle, receipt)
    local step = stepProof(handle)
    if not step or not operationLive(step.operation) or step.state ~= "pending"
        or step.receipt or not Settlement.effectBelongs(receipt, step.action) then return false end
    step.receipt = receipt
    return true
end

function Settlement.earn(handle, receipt, observed)
    local step = stepProof(handle)
    if not step or not operationLive(step.operation) or step.action.character ~= step.operation.character
        or step.action.toolkitQueueOperation ~= step.operation.token then return false end
    if step.state == "earned" then return false end
    if not Settlement.effectBelongs(receipt, step.action) or not Settlement.confirmEffect(receipt, observed) then return false end
    step.state, step.receipt = "earned", receipt
    return true
end

function Settlement.earned(handle)
    local step = stepProof(handle)
    return step and operationLive(step.operation) and step.state == "earned"
        and step.action.character == step.operation.character
        and step.action.toolkitQueueOperation == step.operation.token or false
end

function Settlement.cleanupAfter(action, prerequisites)
    if type(prerequisites) ~= "table" then return false end
    local handle = Settlement.track(action, "cleanup")
    local step, before = stepProof(handle), {}
    if not step or step.prerequisites then return false end
    for _, prerequisite in ipairs(prerequisites) do
        local previous = stepProof(prerequisite)
        if not previous or previous.operation ~= step.operation or previous == step
            or previous.phase == "cleanup" then return false end
        before[#before + 1] = previous
    end
    step.prerequisites, step.kind = before, action.Type
    if action.item then step.item = {id = action.item:getID(), fullType = action.item:getFullType()} end
    return true
end

function Settlement.cleanup(action, prerequisite)
    return Settlement.cleanupAfter(action, {prerequisite})
end

local function requiredCleanup(action, expanding)
    local record = action and operation(action.character, action.toolkitQueueOperation)
    local step = record and record.actions[action]
    if not step or step.phase ~= "cleanup" then return false end
    local reviewed = Toolkit.ActionQueuePolicy and type(Toolkit.ActionQueuePolicy.inspect) == "function"
        and Toolkit.ActionQueuePolicy.inspect(action)
    if not reviewed and expanding and action._isAddingActions and action.Type == "ISQueueActionsAction"
        and Toolkit.ActionQueueOperations and Toolkit.ActionQueueOperations.isCommand(action)
        and Toolkit.ActionQueueDefinitions then
        reviewed = Toolkit.ActionQueueDefinitions.inspect(action)
    end
    if action.Type ~= step.kind
        or step.item and (not action.item or action.item:getID() ~= step.item.id
            or action.item:getFullType() ~= step.item.fullType)
        or not reviewed then return false end
    if step.required then return true end
    for _, previous in ipairs(step.prerequisites or {}) do
        if previous.state == "earned" then return true end
    end
    return false
end

-- Only a live, reviewed cleanup command can pass its private obligation to the
-- children it is currently expanding. Copied flags and historical handles do not.
function Settlement.inheritCleanup(action, parent)
    local queue = parent and ISTimedActionQueue.queues[parent.character]
    if not queue or queue.current ~= parent or queue.queue[1] ~= parent
        or parent.Type ~= "ISQueueActionsAction" or not requiredCleanup(parent, true)
        or action.character ~= parent.character or action.toolkitQueueOperation ~= parent.toolkitQueueOperation then return false end
    if not Toolkit.ActionQueuePolicy.inspect(action) then return false end
    admitCleanup(queue, action)
    local step = stepProof(Settlement.track(action, "cleanup"))
    if not step then return false end
    local parentRecord = operation(parent.character, parent.toolkitQueueOperation)
    step.kind, step.required = action.Type, true
    step.prerequisites = parentRecord.actions[parent].prerequisites
    if action.item then step.item = {id = action.item:getID(), fullType = action.item:getFullType()} end
    return true
end

-- Value-only diagnostics. Callers cannot mutate proof, renew it after reset or
-- turn an enqueue claim into an authoritative result.
function Settlement.operationState(action)
    local record = action and operation(action.character, action.toolkitQueueOperation)
    if not record then return end
    local result = {phase = record.phase, generation = record.generation, steps = {}}
    for _, step in ipairs(record.steps) do
        result.steps[#result.steps + 1] = {phase = step.phase, state = step.state, started = step.started == true,
            observedPreparation = step.preparation ~= nil, kind = step.action.Type,
            plannedTransfer = step.returning ~= nil, transferDirection = step.returning and step.returning.direction,
            itemId = step.item and step.item.id, itemType = step.item and step.item.fullType}
    end
    result.borrowings = {}
    for _, binding in ipairs(record.borrowings) do
        local candidate = binding.candidate
        result.borrowings[#result.borrowings + 1] = {id = candidate.id, fullType = candidate.fullType, state = candidate.phase}
    end
    return result
end

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
    if requiredCleanup(action) then return "operation-effect" end
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

function Settlement.requiredStep(action)
    local record = action and operation(action.character, action.toolkitQueueOperation)
    local step = record and record.actions[action]
    return step and step.required == true or false
end

function Settlement.isCleanup(action)
    return action and action.toolkitQueueReturn == cleanupMarker or false
end

local function insert(queue, action, index)
    local previous = operation(action.character, action.toolkitQueueOperation)
    local inherited = previous and previous.actions[action]
    -- Required work gets a fresh operation: cancelling its former owner cannot revoke it.
    action.toolkitQueueOperation, action.toolkitQueueReturn = {}, cleanupMarker
    admitCleanup(queue, action)
    local step = stepProof(Settlement.track(action, "cleanup"))
    if step then
        step.required, step.kind = true, action.Type
        step.prerequisites = inherited and inherited.prerequisites
        if action.item then step.item = {id = action.item:getID(), fullType = action.item:getFullType()} end
    end
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
        or not generationMatches(character, queue, proof.generation, action)
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

function Settlement.effectBelongs(handle, action)
    local proof = effectProof(handle)
    return proof and proof.action == action or false
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

-- Closing a producer remains permanent. Only the scopes enrolled while the
-- cancellation was admitted retain observation of already-earned native debt.
local function cancellationScope(scope)
    local state = deferred(scope) and cancellation(scope.queue)
    return state and state.scopes[scope] == true and scope.character == state.character
        and scope.generation == state.originalGeneration or false
end

function Settlement.deferred(character, token)
    local queue = ISTimedActionQueue.getTimedActionQueue(character)
    local scope = {marker = deferredMarker, character = character, token = token, queue = queue,
        generation = queue.toolkitOperationGeneration or 0, tasks = {}, equipmentItems = {}, seen = {}, mixed = false, phase = "prepare"}
    local ledger = {candidates = {}, actions = {}, handles = {}, executors = {}, merging = {}}
    scope[borrowingMarker] = function(candidate) if candidate == scope then return ledger end end
    return scope
end

function Settlement.remember(scope, action, contract)
    if not deferred(scope) or scope.phase == "retired" or action.character ~= scope.character
        or not action.toolkitQueueOperation then return false end
    local token = action.toolkitQueueOperation
    Settlement.track(action, "body")
    if scope.token ~= token then scope.mixed = true end
    if scope.seen[action] then return false end
    scope.seen[action] = true
    local task = scope.tasks[token]
    if not task then task = {items = {}, pickups = {}, actions = {}}; scope.tasks[token] = task end
    task.actions[action] = true
    if not contract or contract.knownInputs == false or contract.dynamicInputs or contract.dynamicInputsByType then
        task.unknownInputs = true
    end
    for id in pairs(contract and contract.items or {}) do
        task.items[id] = true
        if contract.hands == scope.character then scope.equipmentItems[id] = true end
    end
    if contract and contract.equipment == scope.character then task.readsEquipment = true end
    for id in pairs(contract and contract.containerOwners or {}) do task.items[id] = true end
    for item, container in pairs(token.toolkitPickups or {}) do
        local id, fullType = item:getID(), item:getFullType()
        local previous = task.pickups[id]
        task.pickups[id] = {container = container, fullType = fullType,
            ambiguous = previous and (previous.ambiguous or previous.container ~= container or previous.fullType ~= fullType) or false}
    end
    return true
end

local function claimedInput(scope, task, id)
    return task.unknownInputs or task.items[id] or task.readsEquipment and scope.equipmentItems[id]
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
        if token ~= owner and claimedInput(scope, task, id) then return end
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
    return not proof.invalid and (scope.phase ~= "retired" or cancellationScope(scope)) and scope.queue == queue and scope.character == character
        and scope.generation == proof.generation and proof.obligation.token == proof.token and action.character == character
        and action.action == proof.native and isClient() == proof.client
        and not character:isDead() and character:getPlayerNum() == proof.player and character:getOnlineID() == proof.online
        and getSpecificPlayer(proof.player) == character and ISTimedActionQueue.queues[character] == queue
        and generationMatches(character, queue, proof.generation, action)
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

local outcomeAttempted, outcomeBinding
bindTransferOutcomes = function()
    if outcomeAttempted or outcomeBinding or type(getFilenameOfClosure) ~= "function" then return false end
    outcomeBinding = true
    local function prepare()
        local member, retained, authority, observer, source = transferOutcomes(outcomeModule)
        if not member then return end
        local readAuthority = authority(itemTransactionDone, itemTransactionRejected)
        local observe = observer(function(proof, value)
            -- Physical arrival is common evidence; only this owner settles
            -- the corresponding private borrowing/cleanup obligation.
            local candidate = value.borrowed
            if proof.direction ~= "pickup" and candidate and not candidate.ambiguous then
                value.shared = value.shared or sharedBorrowing(proof.scope, candidate)
                candidate.phase = "completed"
            end
        end)
        if type(readAuthority) == "function" and type(observe) == "function" then
            return member, retained, readAuthority, observe, source
        end
    end
    local ok, member, retained, authority, observer, source = pcall(prepare)
    outcomeBinding, outcomeAttempted = false, true
    if not ok or not member then return false end
    sameMember, retainedTransfer, returnAuthority, observeAttempt, sourceEvidence = member, retained, authority, observer, source
    return true
end
bindTransferOutcomes()

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
        if not scope or obligation.token ~= token or scope.phase == "retired" and not cancellationScope(scope) then return false, "obligation" end
        if type(guard) ~= "function" or not guard(action) then return false, "source" end
        local character, queue = action.character, scope.queue
        if character ~= scope.character or queue ~= ISTimedActionQueue.queues[character]
            or not generationMatches(character, queue, scope.generation, action)
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
    if not deferred(scope) or scope.character:isDead()
        or ISTimedActionQueue.queues[scope.character] ~= scope.queue then return false end
    if cancellationScope(scope) then return true end
    return scope.phase ~= "retired" and Toolkit.Settings and Toolkit.Settings.actionQueue()
        and (scope.queue.toolkitOperationGeneration or 0) == scope.generation
end

-- The exact native pickup proves its original owner without relying on the
-- older enqueue-only pickup map. Competing task claims still prevent exclusive
-- cleanup; this classification grants no operation edit permission.
-- Execution probes have a small private-ledger work budget. Legacy explicit
-- waiver/cancellation proofs retain their existing path when no budget is passed.
local function takeExecutionWork(budget)
    if not budget then return true end
    budget.remaining = budget.remaining - 1
    return budget.remaining >= 0
end
local function restoringBorrowing(scope, task, candidate, budget)
    local present = false
    for action in pairs(task.actions or {}) do
        if not takeExecutionWork(budget) then return false end
        present = true
        local record = operation(scope.character, action.toolkitQueueOperation)
        local step = record and record.actions[action]
        if not step or not step.required or step.phase ~= "cleanup" then return false end
        local owned = false
        for _, previous in ipairs(step.prerequisites or {}) do
            if not takeExecutionWork(budget) then return false end
            if previous == candidate.step and previous.state == "earned" then owned = true; break end
        end
        if not owned then return false end
    end
    return present
end

sharedBorrowing = function(scope, candidate, budget)
    if not scope.tasks[candidate.owner] then return true end
    for token, task in pairs(scope.tasks) do
        if not takeExecutionWork(budget) then return true end
        local pickup = task.pickups[candidate.id]
        if pickup and (pickup.ambiguous or pickup.fullType ~= candidate.fullType
            or pickup.container ~= candidate.source or token ~= candidate.owner) then return true end
        if token ~= candidate.owner and claimedInput(scope, task, candidate.id)
            and not restoringBorrowing(scope, task, candidate, budget) then return true end
    end
    return false
end

function Settlement.preparePickup(scope, action)
    local ledger = borrowing(scope)
    if not ledger or scope.phase == "retired" or not borrowingLive(scope) or not action or action.character ~= scope.character
        or not scope.tasks[action.toolkitQueueOperation] or not action.item
        or not action.srcContainer or action.srcContainer == scope.character:getInventory()
        or action.destContainer ~= scope.character:getInventory() or action.item:getContainer() ~= action.srcContainer then return false end
    if ledger.actions[action] then return false end
    local id, fullType = action.item:getID(), action.item:getFullType()
    if type(id) ~= "number" or id % 1 ~= 0 or type(fullType) ~= "string" then return false end
    pollPickups(scope)
    local candidate = {id = id, fullType = fullType, source = action.srcContainer, destination = action.destContainer,
        owner = action.toolkitQueueOperation, phase = "prepare"}
    local holder = type(candidate.source.getContainingItem) == "function" and candidate.source:getContainingItem()
    if holder and type(holder.getInventory) == "function" and holder:getInventory() == candidate.source then
        candidate.sourceOwner = {id = holder:getID(), fullType = holder:getFullType()}
    end
    -- No outbound proof separates two unresolved borrowing episodes. Never let
    -- a late old pickup acquire the new episode merely because its ID matches.
    for _, previous in ipairs(ledger.candidates) do
        if previous.id == id and previous.phase ~= "completed" and previous.phase ~= "waived" then
            previous.ambiguous, candidate.ambiguous = true, true
        end
    end
    local record = operation(scope.character, candidate.owner, true)
    if not record then return false end
    local binding = {scope = scope, candidate = candidate}
    record.borrowings[#record.borrowings + 1] = binding
    candidate.step = stepProof(Settlement.track(action, "prepare"))
    candidate.step.borrowing = binding
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
        member.borrowed, candidate.proof, candidate.member = candidate, proof, member
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
                    if candidate.step then candidate.step.state = "earned" end
                    candidate.transaction = proof.client and attempt.transaction or 0
                    candidate.authority = attempt.authority
                end
            end
        end
    end
end

function Settlement.poll(scope) pollPickups(scope) end

-- Deliberately keeping a borrowed item cancels one pending native return, not
-- the body that still uses it. A sealed, revalidated capability retires only the
-- exact earned loan; its historical ID still fences enqueue-only return hints.
local returnWaiverMarker = {}
local function returnWaiverCandidate(action, guard, allowCurrent, budget)
    local record = action and operation(action.character, action.toolkitQueueOperation)
    local queue, token = record and record.queue, action and action.toolkitQueueOperation
    local step = record and record.actions[action]
    local policy = Toolkit.ActionQueuePolicy
    if not record or not step or record.settlement or token.toolkitCancelled
        or queue.toolkitCancel or queue.toolkitGroupCancel or not queue.current or queue.queue[1] ~= queue.current
        or queue.current.character ~= record.character
        or (not allowCurrent and (action == queue.current or action == queue.queue[1]))
        or action.action or action.started or step.started or step.state ~= "pending" or step.required
        or Settlement.isCleanup(action) or requiredCleanup(action) or step.returning
        or action.Type ~= "ISInventoryTransferAction" or not action.allowMissingItems
        or not policy or type(policy.matchesNative) ~= "function"
        or type(guard) ~= "function"
        or getSpecificPlayer(record.character:getPlayerNum()) ~= record.character then return nil, "operation" end
    local inventory = record.character:getInventory()
    local item = action.item
    if not instanceof(item, "InventoryItem") or action.srcContainer ~= inventory or action.destContainer == inventory then
        return nil, "item_identity"
    end
    local found, foundScope
    for _, binding in ipairs(record.borrowings) do
        if not takeExecutionWork(budget) then return nil, "work_limit" end
        local candidate, scope = binding.candidate, binding.scope
        if sameMember(item, candidate) then
            -- Even another unresolved episode for this ID prevents choosing by
            -- iteration order. A completed old loan has no outstanding claim.
            if candidate.phase ~= "completed" and candidate.phase ~= "waived" then
                if found or candidate.owner ~= token or not borrowingLive(scope)
                    or candidate.phase ~= "active" or candidate.ambiguous or not candidate.step
                    or candidate.step.state ~= "earned" or candidate.returning or candidate.plannedReturn
                    or sharedBorrowing(scope, candidate, budget) or candidate.source ~= action.destContainer
                    or candidate.destination ~= inventory then return nil, "borrowing_state" end
                found, foundScope = candidate, scope
            end
        end
    end
    if not found then return nil, "borrowing_missing" end
    if not policy.matchesNative(action) then return nil, "operation" end
    if item:getContainer() ~= inventory or inventory:getItemById(item:getID()) ~= item
        or item:getIsCraftingConsumed() then return nil, "item_identity" end
    if not queued(queue, action) then return nil, "operation" end
    local ok, valid = pcall(guard, action, {id = found.id, fullType = found.fullType})
    if not ok or valid ~= true then return nil, "native_guard" end
    return found, foundScope, record
end

function Settlement.canWaivePendingReturn(action, guard)
    local candidate, detail = returnWaiverCandidate(action, guard)
    return candidate ~= nil, not candidate and detail or nil
end

function Settlement.pendingReturnWaiver(action, guard)
    local candidate, scope, record = returnWaiverCandidate(action, guard)
    if not candidate then return end
    local handle = {}
    local proof = {action = action, candidate = candidate, scope = scope, record = record, guard = guard,
        item = action.item, source = action.srcContainer, destination = action.destContainer}
    handle[returnWaiverMarker] = function(value) if value == handle then return proof end end
    return handle
end

-- Only the synchronous commit recipient can consume this private, one-use
-- receipt. A historical waiver cannot re-arm a later P4 restoration session.
function Settlement.returnRetention(handle, action)
    local seal = type(handle) == "table" and rawget(handle, returnWaiverMarker)
    local proof = type(seal) == "function" and seal(handle)
    if not proof or not proof.publishing or proof.retentionRead or not proof.used
        or proof.action ~= action or proof.candidate.phase ~= "waived"
        or not operationLive(proof.record) then return end
    local character, candidate = proof.record.character, proof.candidate
    local inventory = character:getInventory()
    local item = inventory:getItemById(candidate.id)
    if getSpecificPlayer(character:getPlayerNum()) ~= character or item ~= proof.item
        or not sameMember(item, candidate) or item:getContainer() ~= inventory
        or proof.source ~= inventory or action.srcContainer ~= proof.source
        or action.destContainer ~= proof.destination or action.item ~= item then return end
    proof.retentionRead = true
    local owner = candidate.sourceOwner
    return {character = character, queue = proof.record.queue, generation = proof.record.generation,
        item = item, source = inventory, destination = proof.destination,
        owner = owner and {id = owner.id, fullType = owner.fullType} or nil}
end

-- The caller commits immediately before its reviewed empty native forceCancel
-- and removal. Re-querying after reset, start, identity changes or another stop
-- cannot turn the old capability into a cleanup exemption.
function Settlement.waivePendingReturn(handle, action, guard)
    local seal = type(handle) == "table" and rawget(handle, returnWaiverMarker)
    local proof = type(seal) == "function" and seal(handle)
    if not proof or proof.used or proof.action ~= action or proof.guard ~= guard
        or action.item ~= proof.item or action.srcContainer ~= proof.source
        or action.destContainer ~= proof.destination then return false end
    local candidate, scope, record = returnWaiverCandidate(action, guard)
    if candidate ~= proof.candidate or scope ~= proof.scope or record ~= proof.record then return false end
    proof.used, candidate.phase = true, "waived"
    local intent = Toolkit.ActionQueueTidyIntent
    if intent and type(intent.keepReturn) == "function" then
        proof.publishing = true
        local ok, kept = pcall(intent.keepReturn, action, handle)
        proof.publishing = false
        if not ok or kept ~= true then
            proof.used, proof.retentionRead, candidate.phase = false, nil, "active"
            return false
        end
    end
    return true
end

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

-- The producer registry may close while an accepted native pickup is still
-- executing. Reuse only its already-bound observation handle, never a context
-- that could admit new work or a handle from another native episode.
function Settlement.admittedPickupScope(action)
    local queue = action and ISTimedActionQueue.queues[action.character]
    local state = queue and cancellation(queue)
    if not state or queue.current ~= action or queue.queue[1] ~= action then return end
    local found
    for scope in pairs(state.scopes) do
        local ledger = borrowing(scope)
        local proof = ledger and returnProof(ledger.handles[action])
        if proof and not proof.invalid and not proof.stopped and proof.direction == "pickup"
            and proof.action == action and proof.native == action.action and proof.queue == queue then
            if found then return end -- Ambiguous observers cannot select an owner.
            found = scope
        end
    end
    return found
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
            and (candidate.source == proof.destination or candidate.returnDestination == proof.destination)
            and candidate.destination == proof.source then
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

-- Preparation observation shares the native boundary and transfer merge observer;
-- it does not replace a native callback or grant permission to interrupt it.
local preparationObserver
local function preparationStep(action)
    local record = action and operation(action.character, action.toolkitQueueOperation)
    local step = record and record.actions[action]
    return step and step.preparation and step or nil
end
local function preparationGuard(action)
    local step = preparationStep(action)
    if not step or step.preparation.failed then return false end
    local ok, valid = pcall(step.preparation.guard, action)
    if not ok or valid ~= true then step.preparation.failed = true; return false end
    return true
end
local function preparationState(step)
    local watch = step.preparation
    if step.state == "earned" then return "ready" end
    if watch.failed then return "failed" end
    if not watch.started or watch.empty then return "ready" end
    if not preparationGuard(step.action) then return "failed" end
    if not watch.finished then return "waiting" end
    if watch.scope then
        pollPickups(watch.scope)
        if step.state == "earned" then return "ready" end
        local candidate = step.borrowing and step.borrowing.candidate
        local member, proof = candidate and candidate.member, candidate and candidate.proof
        if not member or not member.attempt or not proof or proof.invalid then return "failed" end
        local state = observeAttempt(proof, proof.attempts[member.attempt])
        return state == "waiting" and "waiting" or state == "rejected" and "ready" or "failed"
    end
    if not step.receipt then return "failed" end
    local ok, observed = pcall(watch.observed, step.action, watch.before)
    if not ok then watch.failed = true; return "failed" end
    local state = Settlement.effectState(step.receipt, observed == true)
    if state == "completed" then
        return Settlement.earn(step.handle, step.receipt, observed == true) and "ready" or "failed"
    end
    return state == "waiting" and "waiting" or (state == "rejected" or state == "canceled") and "ready" or "failed"
end

local plannedReturnObserver
function Settlement.observePlannedReturns()
    local transfers = Toolkit.ActionQueueTidyIntent
    if plannedReturnObserver then
        return transfers == plannedReturnObserver.transfers and transfers.observeTransfers == plannedReturnObserver.observe
            and plannedReturnObserver.valid
    end
    if not transfers or type(transfers.observeTransfers) ~= "function" then return false end
    local function guard(action)
        local policy = Toolkit.ActionQueuePolicy
        return getmetatable(action) == ISInventoryTransferAction and policy and policy.matchesNative(action)
            and (policy.isOrdinaryTransfer(action) or Settlement.isCleanupPickup(action))
    end
    local previous = ISInventoryTransferAction and ISInventoryTransferAction.checkQueueList
    transfers.observeTransfers(function(action) Settlement.refreshPlannedReturn(action) end,
        function(action) return Settlement.plannedReturnMatches(action) end, {
            begin = function(action) return guard(action) and Settlement.beginPlannedReturn(action, guard) end,
            finish = function(action, succeeded) return Settlement.finishPlannedReturn(action, succeeded) end,
        })
    local replacement = ISInventoryTransferAction and ISInventoryTransferAction.checkQueueList
    local valid, policy = previous == replacement, Toolkit.ActionQueuePolicy
    if not valid and policy and type(policy.adoptTransferQueueObserver) == "function" then
        valid = policy.adoptTransferQueueObserver(previous, replacement) == true
    end
    plannedReturnObserver = {transfers = transfers, observe = transfers.observeTransfers, valid = valid}
    return valid
end

function Settlement.preparationAvailable()
    local lifecycle, transfers = Toolkit.ActionQueueLifecycle, Toolkit.ActionQueueTidyIntent
    if preparationObserver then
        return preparationObserver.valid and lifecycle == preparationObserver.lifecycle and lifecycle.registerObserver == preparationObserver.register
            and transfers == preparationObserver.transfers and transfers.observeTransfers == preparationObserver.observe
    end
    if not lifecycle or type(lifecycle.registerObserver) ~= "function"
        or not transfers or type(transfers.observeTransfers) ~= "function" then return false end
    if not Settlement.observePlannedReturns() then return false end
    local observer = {
        started = function(action)
            local step = preparationStep(action)
            if not step or not preparationGuard(action) then return end
            local watch = step.preparation
            if watch.started then watch.failed = true; return end
            watch.started = true
            local ok, before = pcall(watch.capture, action)
            if not ok or before ~= nil and type(before) ~= "table" then watch.failed = true; return end
            watch.before, watch.empty = before, before == nil
        end,
        begin = function(action, phase)
            local step = preparationStep(action)
            if not step or step.preparation.scope or phase ~= "perform" then return false end
            local watch = step.preparation
            if watch.empty then return false end
            if not watch.started or not preparationGuard(action) or watch.begun
                or isClient() and (action.toolkitNativeTransaction == nil or action.toolkitNativeKind == nil) then
                watch.failed = true; return false
            end
            watch.begun = true
            return Settlement.bindEffect(step.handle, Settlement.captureEffect(action))
        end,
        finish = function(action, phase, succeeded)
            local step = preparationStep(action)
            if not step or step.preparation.scope then return end
            local watch = step.preparation
            if not succeeded then watch.failed = true end
            if phase == (isClient() and "perform" or "complete") then
                watch.finished = true
                preparationState(step)
            end
        end,
    }
    if not lifecycle.registerObserver("settlement-preparation", observer) then return false end
    local previous = ISInventoryTransferAction and ISInventoryTransferAction.checkQueueList
    transfers.observeTransfers(function(action)
        local step = preparationStep(action)
        if step and step.preparation.scope then Settlement.refreshPickup(step.preparation.scope, action) end
    end, function(action)
        local step = preparationStep(action)
        return step and step.preparation.scope and preparationGuard(action) or false
    end, {
        merging = function(action)
            local step = preparationStep(action)
            return step and step.preparation.scope and Settlement.beforePickupMerge(step.preparation.scope, action, preparationGuard) or false
        end,
        begin = function(action)
            local step = preparationStep(action)
            if not step or not step.preparation.scope then return false end
            local watch = step.preparation
            if not watch.started or watch.empty or not preparationGuard(action) then watch.failed = true; return false end
            return Settlement.beginPickup(watch.scope, action, preparationGuard)
        end,
        finish = function(action, succeeded)
            local step = preparationStep(action)
            if not step or not step.preparation.scope then return false end
            local watch = step.preparation
            if not succeeded then watch.failed = true end
            watch.finished = true
            local result = Settlement.finishPickup(watch.scope, action, succeeded)
            preparationState(step)
            return result
        end,
    })
    local replacement = ISInventoryTransferAction and ISInventoryTransferAction.checkQueueList
    local valid = previous == replacement
    local policy = Toolkit.ActionQueuePolicy
    if not valid and policy and type(policy.adoptTransferQueueObserver) == "function" then
        valid = policy.adoptTransferQueueObserver(previous, replacement) == true
    end
    preparationObserver = {lifecycle = lifecycle, register = lifecycle.registerObserver,
        transfers = transfers, observe = transfers.observeTransfers, valid = valid}
    return valid
end

function Settlement.observePreparation(action, specification)
    if not Settlement.preparationAvailable() or type(specification) ~= "table"
        or type(specification.guard) ~= "function" or type(specification.capture) ~= "function"
        or type(specification.observed) ~= "function" then return end
    local step = stepProof(Settlement.track(action, "prepare"))
    if not step or step.started or step.preparation then return end
    step.preparation = {guard = specification.guard, capture = specification.capture, observed = specification.observed}
    if action.item then step.item = {id = action.item:getID(), fullType = action.item:getFullType()} end
    if action.Type == "ISInventoryTransferAction" then
        local record, binding = step.operation, step.borrowing
        local scope = binding and binding.scope
        if binding then
            -- P4 observes synchronous enqueue before the family adapter binds its
            -- preparation. Both observers must use that same native borrowing.
            local candidate, ledger = binding.candidate, borrowing(scope)
            if not borrowingLive(scope) or scope.character ~= record.character or scope.queue ~= record.queue
                or scope.generation ~= record.generation or not scope.tasks[record.token]
                or not candidate or candidate.step ~= step or candidate.owner ~= record.token
                or candidate.phase ~= "prepare" or candidate.ambiguous or not ledger
                or ledger.actions[action] ~= candidate or not ledger.executors[action]
                or ledger.executors[action][candidate.id] ~= candidate
                or candidate.source ~= action.srcContainer or candidate.destination ~= action.destContainer
                or candidate.destination ~= record.character:getInventory()
                or not sameMember(action.item, candidate) or action.item:getContainer() ~= candidate.source then
                step.preparation.failed = true; return
            end
        else
            record.preparationScope = record.preparationScope or Settlement.deferred(action.character, record.token)
            scope = record.preparationScope
            Settlement.remember(scope, action, {knownInputs = true, items = {[action.item:getID()] = true}})
            if not Settlement.preparePickup(scope, action) then step.preparation.failed = true; return end
        end
        step.preparation.scope = scope
    end
    return step.handle
end

-- Do not release an independent tail while a preparation result can still
-- arrive. Pending unstarted work has no receipt; a rejected attempt is isolated.
-- A lost/expired authority is a failure, never an invitation to guess or retry.
function Settlement.cancellationState(queue, action)
    local request = queue and queue.toolkitGroupCancel
    if not request or request.action ~= action then return "ready" end
    local record = operation(action.character, request.token)
    if not record then return "ready" end
    for _, step in ipairs(record.steps) do
        if step.preparation then
            local state = preparationState(step)
            if state ~= "ready" then return state end
        end
        if not step.preparation and step.phase == "prepare" and step.state ~= "earned" and step.receipt then
            local state = Settlement.effectState(step.receipt, false)
            if state == "waiting" then return "waiting" end
            if state ~= "canceled" and state ~= "rejected" then return "failed" end
        end
    end
    for _, binding in ipairs(record.borrowings) do
        local scope, candidate = binding.scope, binding.candidate
        pollPickups(scope)
        local member, proof = candidate.member, candidate.proof
        if candidate.phase == "prepare" and member and member.attempt and proof then
            if not borrowingLive(scope) or proof.invalid then return "failed" end
            local state = observeAttempt(proof, proof.attempts[member.attempt])
            if state == "waiting" then return "waiting" end
            if state ~= "rejected" then return "failed" end
        end
    end
    return "ready"
end

local function plannedReturn(action)
    local record = action and operation(action.character, action.toolkitQueueOperation)
    local step = record and record.actions[action]
    return step and step.returning
end

function Settlement.completionState(queue, action)
    local step = preparationStep(action)
    if step then
        local state = preparationState(step)
        if state ~= "ready" then return state end
    end
    local planned = plannedReturn(action)
    if planned then
        if planned.failure then return Settlement.cancellationState(queue, action) end
        local state = Settlement.returnState(planned.obligation)
        if state == "waiting" then return "waiting" end
        if state ~= "completed" and state ~= "rejected" then return "failed" end
        if state == "completed" then
            local record = operation(action.character, action.toolkitQueueOperation)
            record.actions[action].state = "earned"
        end
    end
    return Settlement.cancellationState(queue, action)
end

function Settlement.plannedReturnMatches(action)
    local planned = plannedReturn(action)
    return planned and Settlement.returnMatches(action, planned.obligation) or false
end

function Settlement.beginPlannedReturn(action, guard)
    local planned = plannedReturn(action)
    if not planned or type(guard) ~= "function" then return false end
    planned.guard = planned.guard or function(value)
        if value ~= action or plannedReturn(value) ~= planned or not guard(value) then return false end
        if planned.item and (not sameMember(value.item, planned.item) or value.srcContainer ~= planned.source
            or value.destContainer ~= planned.destination) then return false end
        if planned.owner then
            local holder = value.character:getInventory():getItemById(planned.owner.id)
            if not sameMember(holder, planned.owner) or type(holder.getInventory) ~= "function"
                or holder:getInventory() ~= value.destContainer
                or not Toolkit.ActionQueuePolicy.isCarriedContainer(value.destContainer, value.character) then return false end
        end
        return true
    end
    return Settlement.beginReturn(action, planned.obligation, planned.guard)
end

function Settlement.refreshPlannedReturn(action)
    local planned = plannedReturn(action)
    return planned and Settlement.refreshReturn(action, planned.obligation) or false
end

function Settlement.finishPlannedReturn(action, succeeded)
    local planned = plannedReturn(action)
    return planned and Settlement.finishReturn(planned.obligation, succeeded) or false
end

local function makeReturn(queue, id, expected, containers)
    local inventory, destination = queue.character:getInventory(), expected.destination
    local owner = expected.borrowed and expected.borrowed.sourceOwner
    if owner then
        local holder = inventory:getItemById(owner.id)
        -- Ground placement/Host pickup may replace the Java bag/container replica.
        -- Rebind only its captured exact owner, still carried by this actor.
        if not sameMember(holder, owner) or type(holder.getInventory) ~= "function" then return end
        destination = holder:getInventory()
        if not Toolkit.ActionQueuePolicy.isCarriedContainer(destination, queue.character) then return end
    end
    local item = not expected.ambiguous and inventory:getItemById(id)
    if not destination or not item or item:getID() ~= id or item:getFullType() ~= expected.fullType
        or item:getContainer() ~= inventory or item:getIsCraftingConsumed()
        or not destination:isExistYet() or not (containers:contains(destination)
            or Toolkit.ActionQueuePolicy.isCarriedContainer(destination, queue.character)) then return end
    local action = ISInventoryTransferUtil.newInventoryTransferAction(queue.character, item, inventory, destination)
    if action.Type ~= "ISInventoryTransferAction"
        and (isClient() or not Toolkit.ActionQueueCarts or not Toolkit.ActionQueueCarts.isTransfer(action)) then return end
    if action.Type == "ISInventoryTransferAction" then Toolkit.BulkActions.guardTransfer(action) end
    action:setAllowMissingItems(true)
    return action
end

local function bindPlannedReturn(action, scope, candidate, entry, preparedStep)
    -- A freshly checked entry commits only captured facts and private fields;
    -- tracking/settings and item getters must not run again after that read.
    local step = preparedStep or stepProof(Settlement.track(action, "cleanup"))
    if preparedStep and step.state == "pending" then step.phase = "cleanup" end
    local owner, obligation = action.toolkitQueueOperation, {token = action.toolkitQueueOperation}
    obligation[obligationScope] = function(value) if value == obligation then return scope, owner end end
    step.returning = {obligation = obligation,
        item = entry and {id = entry.id, fullType = entry.fullType} or {id = action.item:getID(), fullType = action.item:getFullType()},
        source = entry and entry.source or action.srcContainer, destination = entry and entry.destination or action.destContainer,
        owner = candidate.sourceOwner, scope = scope, candidate = candidate, waivable = candidate.executionOptional == true}
    candidate.plannedReturn, candidate.returnDestination = action, entry and entry.destination or action.destContainer
end

-- A descriptor never executes validation or reserves capacity. Only exact earned
-- optional loans can acquire this narrowly audited isolated-failure capability.
local function approvedExecutionGuard(guard)
    local execution = Toolkit.ActionQueueExecution
    return execution and guard == execution.matches and executionProof
        and type(executionProof.closure) == "function"
        and executionProof.closure(guard, "ActionQueueExecution.lua")
end
local failureTailChecker
local function independentReturnTail(queue, action)
    local policy = Toolkit.ActionQueuePolicy
    local checker = policy and policy.returnFailureIndependent
    if type(checker) ~= "function" or not executionProof
        or not executionProof.closure(checker, "ActionQueuePolicy.lua") then return false end
    if failureTailChecker and checker ~= failureTailChecker then return false end
    failureTailChecker = checker
    return checker(queue, action) == true
end
local function executionCandidate(action, guard)
    if not approvedExecutionGuard(guard) or not action then return end
    local record = operation(action.character, action.toolkitQueueOperation)
    local queue = record and record.queue
    local step = record and record.actions[action]
    -- This first slice is explicitly unsupported above 32 queue members. Deny
    -- before membership scans, user contracts or private-ledger traversal.
    if not step or not queue then return end
    if #queue.queue > MAX_EXECUTION_MEMBERS then return nil, "unsupported_queue_size" end
    if not queue.current
        or queue.queue[1] ~= queue.current or queue.toolkitCancel or queue.toolkitGroupCancel
        or getSpecificPlayer(action.character:getPlayerNum()) ~= action.character then return end
    local bucket = returnFailures[action.character]
    if bucket and bucket.count >= MAX_RETURN_FAILURES and not (step.returning and step.returning.failure) then return end
    local candidate, scope, owner
    local planned, budget = step.returning, {remaining = MAX_EXECUTION_BORROWING_WORK}
    if planned then
        candidate, scope = planned.candidate, planned.scope
        if planned.direction == "pickup" or not candidate or not scope or not planned.waivable
            or candidate.phase ~= "active" or candidate.plannedReturn ~= action or candidate.ambiguous
            or not candidate.step or candidate.step.state ~= "earned" or not borrowingLive(scope)
            or not sameMember(action.item, planned.item)
            or action.srcContainer ~= planned.source or action.destContainer ~= planned.destination then return end
        if sharedBorrowing(scope, candidate, budget) then
            return nil, budget.remaining < 0 and "unsupported_borrowing_work" or nil
        end
        if not queued(queue, action) then return end
        owner = record
    else
        if #record.borrowings == 0 then return end
        candidate, scope, owner = returnWaiverCandidate(action, guard, true, budget)
        if not candidate then return nil, budget.remaining < 0 and "unsupported_borrowing_work" or nil end
    end
    -- Only a private earned candidate may pay for suffix contract inspection.
    if not guard(action) or not independentReturnTail(queue, action) then return end
    return candidate, scope, owner, step
end
function Settlement.returnExecutionSupported(action, guard)
    local candidate, detail = executionCandidate(action, guard)
    return candidate ~= nil, not candidate and detail or nil
end
function Settlement.authorizeReturnRetention(action, guard)
    local candidate = executionCandidate(action, guard)
    if not candidate then return false end
    candidate.executionOptional = true
    return true
end
function Settlement.prepareReturnExecution(action, guard)
    local candidate, scope, record, step = executionCandidate(action, guard)
    if not candidate or record.queue.current ~= action or record.queue.queue[1] ~= action
        or action.action or action.started then return false end
    -- Owner liveness may call settings/adapter code too; finish it before the
    -- final source read rather than invalidating that evidence afterward.
    if not operationLive(record) or not borrowingLive(scope) then return false end
    local planned, plannedAction = step.returning, candidate.plannedReturn
    if planned and planned.execution then return false end
    -- Source/tail callbacks above can invalidate facts. Bind to the private
    -- adapter's identity/endpoints, preserving an already reviewed bag rebind.
    local execution = {guard = guard, actor = record.character, queue = record.queue,
        generation = record.queue.toolkitOperationGeneration or 0,
        source = planned and planned.source or candidate.destination,
        destination = planned and planned.destination or candidate.source,
        id = candidate.id, fullType = candidate.fullType}
    local ok, present = pcall(sourceEvidence, action, execution)
    if not ok or present ~= true or ISTimedActionQueue.queues[record.character] ~= record.queue
        or record.queue.character ~= record.character or not generationMatches(record.character, record.queue, record.generation, action)
        or record.queue.toolkitCancel or record.queue.toolkitGroupCancel
        or step.returning ~= planned or planned and planned.execution or candidate.plannedReturn ~= plannedAction
        or action.toolkitQueueOperation ~= record.token or record.queue.current ~= action or record.queue.queue[1] ~= action
        or action.action or action.started or (record.queue.toolkitOperationGeneration or 0) ~= execution.generation then return false end
    candidate.executionOptional = true
    if not planned then bindPlannedReturn(action, scope, candidate, execution, step); planned = step.returning end
    planned.execution = execution
    return true
end
local function unmovedReturn(action, planned)
    return retainedTransfer(action, planned.execution)
end
function Settlement.rejectReturnExecution(action, reason, guard)
    if not approvedExecutionGuard(guard) then return false end
    local record = action and operation(action.character, action.toolkitQueueOperation)
    local step = record and record.actions[action]
    local planned = step and step.returning
    local execution = planned and planned.execution
    local queue = execution and execution.queue
    if not execution or execution.guard ~= guard or planned.failure or not operationLive(record)
        or queue ~= ISTimedActionQueue.queues[action.character] or queue.current ~= action or queue.queue[1] ~= action
        or (queue.toolkitOperationGeneration or 0) ~= execution.generation
        or queue.toolkitCancel or queue.toolkitGroupCancel or action.character:isPlayerMoving()
        or action.character:pressedMovement(false) or not action.action or not guard(action)
        or action.srcContainer ~= execution.source or action.destContainer ~= execution.destination
        or not sameMember(action.item, execution) or not unmovedReturn(action, planned)
        or not independentReturnTail(queue, action) then return false end
    local native = action.action
    if reason == "server" then
        if not isClient() or returnAuthority(true, action.transactionId) ~= "rejected"
            or not Settlement.stopReturn(action, planned.obligation, guard)
            or Settlement.returnState(planned.obligation) ~= "rejected" then return false end
    elseif reason == "admission" then
        if action.started or action.transactionId ~= 0 or native:isStarted()
            or action.character:getCharacterActions():contains(native) or returnProof(planned.obligation) then return false end
    elseif reason == "unmoved" then
        local proof = returnProof(planned.obligation)
        local attempt = proof and proof.active
        if isClient() or not proof or proof.invalid or proof.sequenceError or not proof.ended or proof.next
            or #proof.members ~= 1 or not attempt or not attempt.finished or not attempt.succeeded
            or not sameMember(action.item, proof.members[1]) or #action.queueList ~= 0
            or action.character:getCharacterActions():contains(native) then return false end
        -- Native SP consumed the only group without moving its exact item. This
        -- is a no-effect disposition, never a fabricated multiplayer receipt.
        attempt.terminal, attempt.disposition = "rejected", "native-no-effect"
    else return false end
    local bucket = returnFailures[action.character]
    if not bucket then bucket = {count = 0, revision = 0, entries = {}, queue = queue}; returnFailures[action.character] = bucket end
    if bucket.count >= MAX_RETURN_FAILURES then return false end
    failureSerial = failureSerial + 1
    local failure = {id = failureSerial, action = action, record = record, planned = planned,
        candidate = planned.candidate, scope = planned.scope, queue = queue, generation = execution.generation,
        native = action.action, execution = execution, stop = action.stop, complete = action.onCompleteFunc,
        transferGuard = action.toolkitTransferGuard, item = action.item, source = execution.source, destination = execution.destination,
        itemId = execution.id, itemType = execution.fullType,
        title = action.item:getDisplayName(), reason = reason, state = "blocked"}
    planned.failure, step.state = failure, "blocked"
    bucket.entries[#bucket.entries + 1] = failure
    if bucket.activeQueue ~= queue or bucket.activeGeneration ~= execution.generation then
        bucket.activeQueue, bucket.activeGeneration, bucket.activeCount = queue, execution.generation, 0
    end
    bucket.activeCount = bucket.activeCount + 1
    bucket.count, bucket.revision = bucket.count + 1, bucket.revision + 1
    return true
end
-- A source-reviewed restoration producer may ask whether its exact return
-- would duplicate a still-undecided failed episode. This is only a suppression
-- fence: it never waives the loan, publishes Keep intent or executes an item.
local function singletonRestoration(action)
    local groups = action.queueList
    if type(groups) ~= "table" or getmetatable(groups) or type(groups[1]) ~= "table"
        or getmetatable(groups[1]) or type(groups[1].items) ~= "table" or getmetatable(groups[1].items) then return false end
    for key in pairs(groups) do if key ~= 1 then return false end end
    for key in pairs(groups[1].items) do if key ~= 1 then return false end end
    return groups[1].items[1] == action.item
end
local function exactReturnOwner(failure, root)
    local owner = failure.candidate.sourceOwner
    local destination = failure.destination
    if not owner then return type(destination.getContainingItem) == "function" and destination:getContainingItem() == nil end
    local holder = root:getItemById(owner.id)
    if not sameMember(holder, owner) or type(holder.getInventory) ~= "function"
        or holder:getInventory() ~= destination then return false end
    local seen = {}
    for _ = 1, 64 do
        if destination == root then return true end
        if not instanceof(destination, "ItemContainer") or seen[destination]
            or type(destination.getContainingItem) ~= "function" then return false end
        seen[destination] = true
        holder = destination:getContainingItem()
        if not instanceof(holder, "InventoryContainer") or type(holder.getInventory) ~= "function"
            or holder:getInventory() ~= destination or type(holder.getContainer) ~= "function" then return false end
        destination = holder:getContainer()
    end
    return false
end
function Settlement.returnRestorationBlocked(action)
    local character = action and action.character
    local bucket = character and returnFailures[character]
    local queue = bucket and ISTimedActionQueue.queues[character]
    if not bucket or not queue or queue.character ~= character or not Toolkit.Settings.actionQueue()
        or character:isDead() or getSpecificPlayer(character:getPlayerNum()) ~= character
        or #queue.queue ~= 0 or character:hasTimedActions() or action.action or action.started
        or action.Type ~= "ISInventoryTransferAction" or getmetatable(action) ~= ISInventoryTransferAction
        or not singletonRestoration(action) then return false end
    local root = character:getInventory()
    if action.srcContainer ~= root or action.destContainer == root or not instanceof(action.item, "InventoryItem") then return false end
    for _, failure in ipairs(bucket.entries) do
        local planned, candidate, previous = failure.planned, failure.candidate, failure.action
        local step = failure.record.actions[previous]
        if action.item == failure.item and action.destContainer == failure.destination
            and failure.state == "blocked" and failure.queue == queue and operationLive(failure.record)
            and (queue.toolkitOperationGeneration or 0) == failure.generation
            and planned.failure == failure and planned.execution == failure.execution
            and step and step.returning == planned and step.state == "blocked"
            and candidate and candidate.phase == "active" and not candidate.ambiguous
            and candidate.step and candidate.step.state == "earned" and candidate.plannedReturn == previous
            and approvedExecutionGuard(failure.execution.guard)
            and failure.native and previous.action == failure.native and previous.stop == failure.stop
            and previous.onCompleteFunc == failure.complete and previous.toolkitTransferGuard == failure.transferGuard
            and not character:getCharacterActions():contains(failure.native)
            and failure.execution.queue == queue and failure.execution.generation == failure.generation
            and failure.source == root and previous.srcContainer == root
            and previous.destContainer == failure.destination and action.destContainer == failure.destination
            and action.item == failure.item and previous.item == failure.item
            and sameMember(action.item, {id = failure.itemId, fullType = failure.itemType})
            and action.item:getContainer() == root and root:getItemById(failure.itemId) == action.item
            and not action.item:getIsCraftingConsumed() and exactReturnOwner(failure, root)
            and not sharedBorrowing(failure.scope, candidate, {remaining = MAX_EXECUTION_BORROWING_WORK}) then return true end
    end
    return false
end
-- O(1) observation hint, separate from historical UI notices. It performs no
-- item lookup or debt traversal and grants no exact restoration/Keep authority.
function Settlement.hasActiveBlockedReturn(character)
    if not Toolkit.Settings.actionQueue() then return false end
    local bucket = returnFailures[character]
    if not bucket or not bucket.activeCount or bucket.activeCount == 0 then return false end
    local queue = ISTimedActionQueue.queues[character]
    return queue ~= nil and queue == bucket.activeQueue and queue.character == character
        and (queue.toolkitOperationGeneration or 0) == bucket.activeGeneration
        and getSpecificPlayer(character:getPlayerNum()) == character and not character:isDead()
end
function Settlement.blockedReturnInfo(character)
    local bucket = returnFailures[character]
    if not bucket then return end
    return {count = bucket.count, revision = bucket.revision}
end
function Settlement.blockedReturns(character)
    local bucket, result = returnFailures[character], {}
    for _, failure in ipairs(bucket and bucket.entries or {}) do
        result[#result + 1] = {id = failure.id, itemId = failure.itemId, itemType = failure.itemType,
            title = failure.title, reason = failure.reason, state = failure.state}
    end
    return result
end
function Settlement.resetReturnFailures(queue)
    local bucket = queue and returnFailures[queue.character]
    if not bucket then return end
    for _, failure in ipairs(bucket.entries) do
        if failure.queue == queue then failure.state = "revoked" end
    end
    if bucket.activeQueue == queue then bucket.activeCount = 0 end
    bucket.revision = bucket.revision + 1
end
function Settlement.keepReturn(character, id)
    local bucket = returnFailures[character]
    if not bucket or character:isDead() or getSpecificPlayer(character:getPlayerNum()) ~= character then return false, "unavailable" end
    for index, failure in ipairs(bucket.entries) do
        if failure.id == id then
            if failure.state == "revoked" then
                -- Explicitly forget historical UI information. No old receipt,
                -- item lookup, retention intent or execution right is revived.
                table.remove(bucket.entries, index)
                bucket.count, bucket.revision = bucket.count - 1, bucket.revision + 1
                return true
            end
            local candidate = failure.candidate
            if not candidate or candidate.phase ~= "active" then return false, "unavailable" end
            local root = character:getInventory()
            local item = root:getItemById(failure.itemId)
            if item ~= failure.item or not sameMember(item, {id=failure.itemId, fullType=failure.itemType})
                or item:getContainer() ~= root then return false, "unavailable" end
            do
                if not operationLive(failure.record) or sharedBorrowing(failure.scope, candidate) then return false, "dependent" end
                -- Publish the same private exact-item retention intent as the
                -- pending-return cross. This never reconstructs or retries work.
                local proof = {action = failure.action, candidate = candidate, scope = failure.scope,
                    record = failure.record, item = item, source = failure.source,
                    destination = failure.destination, used = true, publishing = true}
                local handle = {}; handle[returnWaiverMarker] = function(value)if value == handle then return proof end end
                candidate.phase = "waived"
                local intent = Toolkit.ActionQueueTidyIntent
                if intent and type(intent.keepReturn) == "function" then
                    local ok, kept = pcall(intent.keepReturn, failure.action, handle)
                    proof.publishing = false
                    if not ok or kept ~= true then candidate.phase = "active"; return false, "unavailable" end
                end
            end
            table.remove(bucket.entries, index)
            if bucket.activeQueue == failure.queue and bucket.activeGeneration == failure.generation then
                bucket.activeCount = math.max(0, bucket.activeCount - 1)
            end
            bucket.count, bucket.revision = bucket.count - 1, bucket.revision + 1
            return true
        end
    end
    return false, "unavailable"
end
if Events and Events.OnGameStart then Events.OnGameStart.Add(function() returnFailures = {} end) end
if Events and Events.OnPlayerDeath then Events.OnPlayerDeath.Add(function(character) returnFailures[character] = nil end) end

-- An earned ground placement may require a native floor pickup before equipment
-- restoration. Observe that cleanup transaction without creating a new borrowing
-- obligation that would put the recovered bag back on the floor.
function Settlement.isCleanupPickup(action)
    local record = action and operation(action.character, action.toolkitQueueOperation)
    local step = record and record.actions[action]
    local planned = step and step.returning
    return step and step.required == true and step.phase == "cleanup" and planned and planned.direction == "pickup"
        and planned.preparation and planned.preparation.state == "earned"
        and action.Type == "ISInventoryTransferAction" and sameMember(action.item, planned.item)
        and action.srcContainer == planned.source and action.destContainer == planned.destination
        and planned.source:getType() == "floor" and planned.destination == record.character:getInventory() or false
end

function Settlement.observeCleanupTransfer(action, parent)
    local queue = parent and ISTimedActionQueue.queues[parent.character]
    local policy = Toolkit.ActionQueuePolicy
    if not action or action.Type ~= "ISInventoryTransferAction" or not action.item or not parent
        or not queue or queue.current ~= parent or queue.queue[1] ~= parent
        or parent.Type ~= "ISQueueActionsAction" or not requiredCleanup(parent, true)
        or action.character ~= parent.character or action.toolkitQueueOperation ~= parent.toolkitQueueOperation
        or not action.srcContainer or action.srcContainer:getType() ~= "floor"
        or action.destContainer ~= action.character:getInventory() or action.item:getContainer() ~= action.srcContainer
        or not policy or not policy.matchesCleanupPickupBinding(action) then return false end
    local parentRecord = operation(parent.character, parent.toolkitQueueOperation)
    local preparation
    for _, previous in ipairs(parentRecord.actions[parent].prerequisites or {}) do
        if previous.state == "earned" and previous.phase == "prepare" and previous.preparation
            and previous.action.Type == "ISDropWorldItemAction" and sameMember(action.item, previous.item) then
            preparation = previous; break
        end
    end
    local world = action.item:getWorldItem()
    local square = preparation and preparation.preparation.before and preparation.preparation.before.square
    if not preparation or not square or not world or world:getItem() ~= action.item or world:getSquare() ~= square
        or not square:getWorldObjects():contains(world) then return false end
    admitCleanup(queue, action)
    local step = stepProof(Settlement.track(action, "cleanup"))
    if step.returning then return false end
    Toolkit.BulkActions.guardTransfer(action)
    local scope, owner = Settlement.deferred(action.character, action.toolkitQueueOperation), action.toolkitQueueOperation
    local obligation = {token = owner}
    obligation[obligationScope] = function(value) if value == obligation then return scope, owner, "pickup" end end
    step.kind, step.required, step.prerequisites = action.Type, true, parentRecord.actions[parent].prerequisites
    step.item = {id = action.item:getID(), fullType = action.item:getFullType()}
    step.returning = {obligation = obligation, item = step.item, direction = "pickup", preparation = preparation,
        source = action.srcContainer, destination = action.destContainer}
    return true
end

function Settlement.enqueueBorrowedReturn(handle)
    local step = stepProof(handle)
    local binding = step and step.borrowing
    if not binding or not operationLive(step.operation) then return end
    local scope, candidate = binding.scope, binding.candidate
    pollPickups(scope)
    local queue = scope.queue
    local parent = queue and queue.current
    if not borrowingLive(scope) or candidate.phase ~= "active" or candidate.ambiguous
        or candidate.returning or candidate.plannedReturn or sharedBorrowing(scope, candidate)
        or not parent or queue.queue[1] ~= parent or parent.Type ~= "ISQueueActionsAction"
        or not requiredCleanup(parent, true) or parent.character ~= scope.character then return end
    local parentRecord = operation(parent.character, parent.toolkitQueueOperation)
    local authorized = false
    for _, prerequisite in ipairs(parentRecord.actions[parent].prerequisites or {}) do
        if prerequisite == step then authorized = true; break end
    end
    if not authorized then return end
    local action = makeReturn(queue, candidate.id, {fullType = candidate.fullType, destination = candidate.source, borrowed = candidate},
        ISInventoryPaneContextMenu.getContainers(queue.character))
    if not action or action.Type ~= "ISInventoryTransferAction" then return end
    action.toolkitQueueOperation = parent.toolkitQueueOperation
    -- Bind before enqueue: even an immediate native start must see its owner.
    if not Settlement.inheritCleanup(action, parent) then return end
    bindPlannedReturn(action, scope, candidate)
    ISTimedActionQueue.add(action)
    return action
end

-- Called only after the current native step/Host receipt has settled. Pickup
-- locations are intents: only the surviving exact direct-root item can activate
-- a return. Family adapters own any stronger effect/cleanup proof they require.
function Settlement.finish(queue, request, discard)
    local current, token = request.action, request.token
    if request.settlement or not queue or Settlement.cancellationState(queue, current) ~= "ready" or queue.current ~= current or queue.queue[1] ~= current
        or current.character ~= queue.character or current.toolkitQueueOperation ~= token then return false end
    local record = operation(current.character, token, true)
    if not record or record.settlement then return false end
    local state = {phase = "body", obligations = {}, discarded = 0}
    record.settlement, record.phase = state, "body"
    request.settlement = state
    local operations = Toolkit.ActionQueueOperations
    local inventory = queue.character:getInventory()
    local last = 1
    while token and queue.queue[last + 1] and queue.queue[last + 1].toolkitQueueOperation == token do last = last + 1 end
    local returns, cleanup, observed = {}, {}, {}
    -- Receipt-backed borrowing episodes supersede enqueue-only hints. A shared,
    -- returned, rejected or unresolved episode must never become an exclusive
    -- synthetic return just because its source action left the queue.
    for _, binding in ipairs(record.borrowings) do
        local scope, candidate = binding.scope, binding.candidate
        pollPickups(scope)
        observed[candidate.id] = true
        if borrowingLive(scope) and candidate.phase == "active" and not candidate.ambiguous
            and not candidate.returning and not candidate.plannedReturn and not sharedBorrowing(scope, candidate) then
            local previous = returns[candidate.id]
            if previous then previous.ambiguous = true
            else returns[candidate.id] = {fullType = candidate.fullType, destination = candidate.source, borrowed = candidate, scope = scope} end
        end
    end
    local function rememberReturn(item, destination)
        local id, fullType = item:getID(), item:getFullType()
        if observed[id] then return end
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
    state.phase, record.phase = "cleanup", "cleanup"
    for _, obligation in ipairs(cleanup) do
        insert(queue, obligation.action, index)
        state.obligations[#state.obligations + 1] = obligation
        index = index + 1
    end
    for id, expected in pairs(returns) do
        -- Replica replacement must preserve the exact ID/type. Conflicting history
        -- cannot choose a source by table iteration order or reclaim another item.
        local action = not ownedPickup(current, id) and makeReturn(queue, id, expected, containers)
        if action then
            insert(queue, action, index)
            if expected.borrowed and action.Type == "ISInventoryTransferAction" then
                bindPlannedReturn(action, expected.scope, expected.borrowed)
            end
            state.obligations[#state.obligations + 1] = {kind = "return", itemId = id,
                itemType = expected.fullType, destination = action.destContainer, action = action}
            index = index + 1
        end
    end
    state.phase, record.phase = "scheduled", "cleanup"
    local drain = cancellation(queue)
    if drain then drain.scheduled = true end
    return true
end

-- Replaced queues are no longer ticked by the native registry. Retire bounded
-- capabilities there as well as at explicit reset; do not retain old worlds.
if Events and Events.OnTick then
    Events.OnTick.Add(function()
        for queue in pairs(cancellations) do cancellation(queue) end
    end)
end
if Events and Events.OnMainMenuEnter then
    Events.OnMainMenuEnter.Add(function() cancellations = {} end)
end
return Settlement
