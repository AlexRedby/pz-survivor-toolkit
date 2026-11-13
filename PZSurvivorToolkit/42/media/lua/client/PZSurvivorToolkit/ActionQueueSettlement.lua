-- Cancellation settles already-earned obligations; it never undoes native effects.
local Toolkit = PZSurvivorToolkit
local Settlement = {}
Toolkit.ActionQueueSettlement = Settlement
local providers, byId, providerRevision = {}, {}, 0
local activeEditCleanupBinding
local transferListenerMethods
local executionProof = require "PZSurvivorToolkit/SourceProof"
require "PZSurvivorToolkit/ActionQueueTransfers"
local retainedBindingSource={capture=executionProof and executionProof.captureBindings,call=pcall,origin=executionProof and executionProof.closure,kind=type,meta=getmetatable,raw=rawget,equal=rawequal,match=string.match}
-- Keep the new dependency inside the existing source-owned wrapper boundary.
-- Unknown factories must never receive private callbacks or attempt records.
local function transferOutcomes(module)
    if type(module) ~= "table" or getmetatable(module) ~= nil or not executionProof
        or type(executionProof.own) ~= "function" or type(executionProof.closure) ~= "function"
        or type(executionProof.captureBindings) ~= "function" then return end
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
local requestModule = require "PZSurvivorToolkit/ActionQueueTransferRequests"
local requestMethods, requestAttempted, requestBinding
local function transferRequests()
    if requestMethods then return requestMethods end
    if requestAttempted or requestBinding or type(getFilenameOfClosure) ~= "function" then return end
    requestBinding = true
    local ok, methods = pcall(function()
        if type(requestModule) ~= "table" or getmetatable(requestModule) ~= nil or not executionProof then return end
        local own, origin = executionProof.own, executionProof.closure
        if type(own) ~= "function" or type(origin) ~= "function" then return end
        local result = {}
        for _, name in ipairs({"prepare", "clear", "reset", "observe"}) do
            local method = own(requestModule, name)
            if not origin(method, "ActionQueueTransferRequests.lua") then return end
            result[name] = method
        end
        if executionProof.own == own and executionProof.closure == origin then
            result.proofOwn, result.proofOrigin = own, origin
            return result
        end
    end)
    requestBinding, requestAttempted = false, true
    if ok then requestMethods = methods end
    return requestMethods
end

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

-- Operation seals capture actors/queues. Check their live native filename
-- without putting the seal into SourceProof's strong filename-metadata cache.
local function settlementSealTrusted(token,marker,seal)
    local api=retainedBindingSource
    if api.checkingSeal or api.kind(token)~="table" or api.meta(token)~=nil
        or api.kind(seal)~="function" or not api.equal(api.raw(token,marker),seal)
        or api.kind(executionProof)~="table" or api.meta(executionProof)~=nil or api.kind(api.origin)~="function"
        or not api.equal(api.raw(executionProof,"closure"),api.origin) then return false end
    local accessor=getFilenameOfClosure
    if api.kind(accessor)~="function" then return false end
    -- Refuse nested operation lookups while metadata runs. No seal/actor is
    -- stored in this transient fence, and captured pcall always releases it.
    api.checkingSeal=true
    local ok,path=api.call(accessor,seal)
    api.checkingSeal=nil
    if not ok or api.kind(path)~="string" or not api.equal(getFilenameOfClosure,accessor)
        or api.meta(token)~=nil or not api.equal(api.raw(token,marker),seal)
        or api.meta(executionProof)~=nil or not api.equal(api.raw(executionProof,"closure"),api.origin) then return false end
    -- Excluding both separators is the same suffix rule as normalize-then-
    -- match, without allocating a normalized copy of every native filename.
    return api.match(path,"([^/\\]+)$")=="ActionQueueSettlement.lua"
end
local function operationSealTrusted(token,seal)
    return settlementSealTrusted(token,operationMarker,seal)
end

local function operation(character, token, create)
    local api=retainedBindingSource
    if api.checkingSeal or api.kind(token)~="table" or api.meta(token)~=nil or not character then return end
    local seal=api.raw(token,operationMarker)
    if seal~=nil then
        if not operationSealTrusted(token,seal) then return end
        local opened,record=api.call(seal,token)
        if not opened or api.kind(record)~="table" or api.meta(record)~=nil
            or not api.equal(api.raw(record,"token"),token)
            or not api.equal(api.raw(record,"character"),character) then return end
        return operationLive(record) and record or nil
    end
    local queue = ISTimedActionQueue.queues[character]
    if not create or not queue then return end
    local record = {character = character, token = token, queue = queue,
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

local pickupApproachBinding
local function pickupApproach(action, container, character)
    local owner = Toolkit.ActionQueueApproach
    local checker = owner and owner.isContainer
    if not executionProof or not executionProof.closure(checker, "ActionQueueApproach.lua") then return false end
    if not pickupApproachBinding then pickupApproachBinding = {owner = owner, checker = checker} end
    return owner == pickupApproachBinding.owner and checker == pickupApproachBinding.checker
        and checker(action, container, character) == true
end

-- Failure isolation asks only about this private operation, never enqueue
-- pickup hints or a copied diagnostics table. Prior mutating work and earned
-- cleanup remain outside the unreceived singleton contract.
function Settlement.rejectedPickupUntouched(action, members)
    local record = action and operation(action.character, action.toolkitQueueOperation)
    local queue = record and record.queue
    local current = record and record.actions[action]
    if not current or not queue or queue.current ~= action or queue.queue[1] ~= action
        or #record.steps > 32 or #record.borrowings > 32 or type(members) ~= "table" or #members > 31 then return false end
    for _, step in ipairs(record.steps) do
        if step.state ~= "pending" or step.required or step.receipt then return false end
        -- Absence without a started receipt is unknown, not proof of no effect.
        if step ~= current and not step.started and queue:indexOf(step.action) <= 1 then return false end
        if step ~= current and step.started then
            local previous = step.action
            local walking = previous.Type == "ISWalkToTimedAction" or previous.Type == "ISWalkToTimedActionF"
                or previous.Type == "ISPathFindAction"
            if queue:indexOf(previous) ~= -1 then return false end
            if walking then
                if not Toolkit.ActionQueuePolicy.matchesNative(previous) then return false end
            elseif previous.Type ~= "ISQueueActionsAction"
                or not pickupApproach(previous, action.srcContainer, action.character) then return false end
        end
        for _, prerequisite in ipairs(step.prerequisites or {}) do
            if prerequisite.state ~= "pending" then return false end
        end
    end
    for _, binding in ipairs(record.borrowings) do
        local candidate = binding.candidate
        if not candidate or candidate.phase ~= "prepare" or candidate.ambiguous
            or candidate.step and candidate.step.state ~= "pending" then return false end
    end
    for _, member in ipairs(members) do
        local step = record.actions[member]
        if not step or member.toolkitQueueOperation ~= record.token or step.started or step.state ~= "pending"
            or requiredCleanup(member) then return false end
    end
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

-- A bounded observation of existing obligations, never an execution forecast.
-- Avoid operationLive: its cancellation bridge may retire state and invoke
-- settings/native callbacks. Missing history remains explicitly unknown.
local editLedgerOrigin = executionProof and executionProof.closure
local function editLedger(queue, current, budget)
    local function take()
        if not budget then return true end
        budget.remaining = budget.remaining - 1
        return budget.remaining >= 0
    end
    local function unknown() return {status = "unhandled", reason = "edit_obligation_unknown"} end
    -- Query-local list freshness only: retaining an old array in the private
    -- operation would also retain unrelated tail actions after replacement.
    local list = type(queue) == "table" and rawget(queue, "queue")
    if PZSurvivorToolkit ~= Toolkit or Toolkit.ActionQueueSettlement ~= Settlement
        or type(queue) ~= "table" or type(current) ~= "table" or type(queue.queue) ~= "table"
        or getmetatable(queue.queue) ~= nil or queue.current ~= current or queue.queue[1] ~= current
        or rawget(current, "character") ~= queue.character or not queue.character
        or not ISTimedActionQueue or not ISTimedActionQueue.queues
        or ISTimedActionQueue.queues[queue.character] ~= queue
        or queue.toolkitCancel or queue.toolkitGroupCancel or queue.toolkitResume
        or queue.toolkitOutcomeWait or queue.toolkitStopIntent or cancellations[queue] then return unknown() end
    local token, generation = rawget(current, "toolkitQueueOperation"), queue.toolkitOperationGeneration or 0
    if type(generation) ~= "number" or generation % 1 ~= 0
        or type(token) ~= "table" or getmetatable(token) ~= nil or token.toolkitCancelled
        or not executionProof or executionProof.closure ~= editLedgerOrigin
        or type(editLedgerOrigin) ~= "function" then return unknown() end
    local seal = rawget(token, operationMarker)
    if not operationSealTrusted(token,seal) then return unknown() end
    local ok, record = pcall(seal, token)
    if not ok or type(record) ~= "table" or getmetatable(record) ~= nil
        or record.token ~= token or record.queue ~= queue or list ~= queue.queue
        or record.character ~= queue.character or record.generation ~= generation or record.settlement
        or queue.current ~= current or queue.queue[1] ~= current or rawget(current, "character") ~= record.character
        or rawget(current, "toolkitQueueOperation") ~= token or token.toolkitCancelled
        or ISTimedActionQueue.queues[record.character] ~= queue or (queue.toolkitOperationGeneration or 0) ~= generation
        or queue.toolkitCancel or queue.toolkitGroupCancel or queue.toolkitResume
        or queue.toolkitOutcomeWait or queue.toolkitStopIntent or cancellations[queue] then return unknown() end
    local function boundedArray(values, maximum)
        if type(values) ~= "table" or getmetatable(values) ~= nil then return end
        local count, size = 0, #values
        if size > maximum then return end
        for key in pairs(values) do
            count = count + 1
            if not take() or count > maximum or type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > size then return end
        end
        if count == size then return size end
    end
    local stepCount, borrowingCount = boundedArray(record.steps, 32), boundedArray(record.borrowings, 32)
    if not stepCount or not borrowingCount or type(record.actions) ~= "table" or not record.actions[current] then return unknown() end
    local hints = rawget(token, "toolkitPickups")
    local hinted = hints ~= nil
    if type(hints) == "table" and getmetatable(hints) == nil then
        hinted = false
        for _ in pairs(hints) do hinted = true; break end
    end
    local result = {status = "observed", generation = generation, steps = {}, borrowings = {},
        legacyHints = hinted, providersPresent = #providers > 0}
    local visits = 0
    for index = 1, stepCount do
        if not take() then return unknown() end
        local step = record.steps[index]
        if type(step) ~= "table" or getmetatable(step) ~= nil or step.operation ~= record
            or type(step.action) ~= "table" or rawget(step.action, "character") ~= record.character
            or rawget(step.action, "toolkitQueueOperation") ~= token or record.actions[step.action] ~= step
            or (step.phase ~= "prepare" and step.phase ~= "body" and step.phase ~= "cleanup")
            or type(step.state) ~= "string" then return unknown() end
        local required = step.required == true
        if step.prerequisites ~= nil then
            local count = boundedArray(step.prerequisites, 128 - visits)
            if not count then return unknown() end
            visits = visits + count
            for position = 1, count do
                if not take() then return unknown() end
                local previous = step.prerequisites[position]
                if type(previous) ~= "table" or getmetatable(previous) ~= nil or previous.operation ~= record
                    or not previous.action or record.actions[previous.action] ~= previous then return unknown() end
                required = required or previous.state == "earned"
            end
        end
        result.steps[index] = {action = step.action, phase = step.phase, state = step.state,
            started = step.started == true, required = required, returning = step.returning ~= nil}
    end
    for index = 1, borrowingCount do
        if not take() then return unknown() end
        local binding = record.borrowings[index]
        local candidate = type(binding) == "table" and getmetatable(binding) == nil and binding.candidate
        if type(candidate) ~= "table" or getmetatable(candidate) ~= nil or candidate.owner ~= token
            or type(candidate.id) ~= "number" or candidate.id % 1 ~= 0
            or type(candidate.fullType) ~= "string" or type(candidate.phase) ~= "string"
            or candidate.source == nil or candidate.destination == nil
            or candidate.plannedReturn ~= nil and type(candidate.plannedReturn) ~= "table" then return unknown() end
        local owner = candidate.sourceOwner
        if owner ~= nil and (type(owner) ~= "table" or getmetatable(owner) ~= nil
            or type(owner.id) ~= "number" or owner.id % 1 ~= 0 or type(owner.fullType) ~= "string") then return unknown() end
        result.borrowings[index] = {id = candidate.id, fullType = candidate.fullType, state = candidate.phase,
            ambiguous = candidate.ambiguous == true, source = candidate.source, destination = candidate.destination,
            sourceOwner = owner and {id = owner.id, fullType = owner.fullType} or nil,
            returning = candidate.returning ~= nil, plannedReturn = candidate.plannedReturn}
    end
    return result, record
end
function Settlement.editLedger(queue, current)
    -- Keep private records out of the public multiple-return boundary.
    return (editLedger(queue, current))
end

-- Prepare only the source-owned listener context for an existing retained
-- transfer. This reads bounded private metadata, never endpoints or native
-- effects; the returned validator still needs fresh native physical facts.
-- The caller supplies its captured factory rather than discovering a replacement.
function Settlement.prepareRetainedTransferBinding(queue,current,action,factory)
    local adapters=Toolkit.ActionQueueItemEditAdapters
    local capture=retainedBindingSource.capture
    if Settlement.prepareRetainedTransferBinding~=retainedBindingSource.prepare
        or Toolkit.ActionQueueSettlement~=Settlement
        or type(adapters)~="table"or getmetatable(adapters)~=nil
        or type(factory)~="function"or adapters.deferredTransferBinding~=factory
        or not executionProof or executionProof.closure~=editLedgerOrigin
        or type(capture)~="function"or executionProof.captureBindings~=capture
        or type(action)~="table"or action==current or activeEditCleanupBinding~=nil then return end
    local watch=capture({
        {owner=_G,keys={"PZSurvivorToolkit","ISTimedActionQueue","pcall"}},
        {owner=Toolkit,keys={"ActionQueueSettlement","ActionQueueItemEditAdapters"}},
        {owner=adapters,keys={"deferredTransferBinding"}},
        {owner=Settlement,keys={"prepareRetainedTransferBinding","transferListenerBinding"}},
        {owner=executionProof,keys={"closure","captureBindings"}},
    })
    if not watch or not editLedgerOrigin(factory,"ActionQueueItemEditAdapters.lua")or not watch()then return end
    local revision=providerRevision
    local ledger,record=editLedger(queue,current,{remaining=128})
    if ledger.status~="observed"or ledger.providersPresent or providerRevision~=revision
        or not watch()or not rawget(current,"action")
        or #queue.queue<2 or #queue.queue>32 or getmetatable(action)~=ISInventoryTransferAction
        or rawget(action,"character")~=record.character
        or rawget(action,"toolkitQueueOperation")~=record.token
        or rawget(action,"action")~=nil or rawget(action,"started")then return end
    local found=false
    for index=2,#queue.queue do
        local member=queue.queue[index]
        if rawget(member,"toolkitQueueOperation")~=record.token then break end
        if member==action then if found then return end;found=true end
    end
    if not found then return end
    local previousContext=activeEditCleanupBinding
    activeEditCleanupBinding={record=record,queue=queue,current=current,action=action}
    local ok,validate,alias,sourceWatch=retainedBindingSource.call(factory,action,current)
    activeEditCleanupBinding=previousContext
    if not ok or not watch()or providerRevision~=revision or #providers>0
        or type(validate)~="function"or type(sourceWatch)~="function"then return end
    -- Keep this API/owner and the private provider revision fresh through the
    -- caller's final raw boundary; the factory's watch covers its own sources.
    return validate,alias,function()
        return watch()and providerRevision==revision and #providers==0 and sourceWatch()
    end
end

retainedBindingSource.prepare=Settlement.prepareRetainedTransferBinding

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
    providerRevision = providerRevision + 1
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
    -- A reader of an actual borrowed owner must retain its claim. Child
    -- transfers only name containerOwners, so Policy can distinguish read/read.
    local reads = contract and contract.locationReads
    if reads ~= nil then
        if type(reads) ~= "table" or getmetatable(reads) ~= nil then task.unknownInputs = true
        else
            for id, value in pairs(reads) do
                if type(id) ~= "number" or id ~= id or id <= -math.huge or id >= math.huge
                    or id % 1 ~= 0 or value ~= true then task.unknownInputs = true
                else task.items[id] = true end
            end
        end
    end
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
    local owner = operation(action.character, action.toolkitQueueOperation)
    local step = owner and owner.actions[action]
    local planned = step and step.returning
    local request = planned and planned.obligation == obligation and planned.execution and planned.execution.request
    if request and not request.paired and not request.ambiguous and request.phase == "submitted"
        and request.native == action.action and request.transaction == transaction and request.dispatcher == createItemTransaction
        and request.receipt and type(request.receipt.matchesTransaction) == "function"
        and request.receipt:matchesTransaction(action, transaction) then
        -- This is historical source evidence, not a capacity promise or physical
        -- completion. The existing authoritative/effect observer still decides.
        attempt.sourceRequest, request.paired = request, true
    end
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
    if requestMethods then requestMethods.clear(action) end
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
-- Waiver-only Host replica resolution. These captured private facts are never
-- passed to execution admission or accepted from a caller's item DTO.
local function waiverUnchanged(view, phase, item)
    local action, record, candidate, scope = view.action, view.record, view.candidate, view.scope
    local queue, step = record.queue, view.step
    if ISTimedActionQueue.queues[record.character] ~= queue or queue.character ~= record.character
        or queue.queue ~= view.list or queue.current ~= view.current or queue.queue[1] ~= view.current
        or view.current.character ~= record.character or view.current.action ~= view.native
        or (queue.toolkitOperationGeneration or 0) ~= view.generation or record.generation ~= view.generation
        or queue.toolkitCancel or queue.toolkitGroupCancel or record.settlement or record.token ~= view.token
        or view.token.toolkitCancelled or action.toolkitQueueOperation ~= view.token or action.character ~= record.character
        or record.actions[action] ~= step or action.action or action.started or step.started
        or step.state ~= "pending" or step.phase ~= view.stepPhase or step.required or step.returning or action.toolkitQueueReturn == cleanupMarker
        or action.Type ~= "ISInventoryTransferAction" or action.allowMissingItems ~= view.allowMissing or action.item ~= item
        or action.srcContainer ~= view.source or action.destContainer ~= view.destination
        or action.forceCancel ~= view.forceCancel or action.onCompleteFunc ~= view.onComplete
        or Toolkit.ActionQueuePolicy ~= view.policy or view.policy.matchesNative ~= view.matchesNative
        or not deferred(scope) or scope.phase == "retired" or scope.queue ~= queue or scope.character ~= record.character
        or scope.generation ~= view.generation or candidate.owner ~= view.token or candidate.phase ~= phase
        or candidate.id ~= view.id or candidate.fullType ~= view.fullType or candidate.sourceOwner ~= view.owner
        or view.owner and (view.owner.id ~= view.ownerId or view.owner.fullType ~= view.ownerType) or candidate.ambiguous
        or candidate.step ~= view.pickupStep or candidate.step.state ~= "earned"
        or candidate.returning or candidate.plannedReturn or candidate.source ~= view.destination
        or candidate.destination ~= view.source then return false end
    -- The last native inventory getter may reenter after the source guard.
    -- Compare the original singleton group without executing that guard again.
    if action.queueList ~= view.groups then return false end
    if view.groups ~= nil then
        if type(view.groups) ~= "table" or getmetatable(view.groups) ~= view.groupsMeta
            or rawget(view.groups, 1) ~= view.group then return false end
        for key in pairs(view.groups) do if key ~= 1 then return false end end
    end
    if view.group ~= nil then
        if type(view.group) ~= "table" or getmetatable(view.group) ~= view.groupMeta
            or rawget(view.group, "items") ~= view.items or type(view.items) ~= "table"
            or getmetatable(view.items) ~= view.itemsMeta or rawget(view.items, 1) ~= view.member then return false end
        for key in pairs(view.items) do if key ~= 1 then return false end end
    end
    local visits = 0
    for _, previous in ipairs(step.prerequisites or {}) do
        visits = visits + 1
        if visits > MAX_EXECUTION_BORROWING_WORK or previous.state == "earned" then return false end
    end
    local found = false
    for _, binding in ipairs(record.borrowings) do
        visits = visits + 1
        if visits > MAX_EXECUTION_BORROWING_WORK then return false end
        local other = binding.candidate
        if other.id == view.id and other.fullType == view.fullType
            and other.phase ~= "completed" and other.phase ~= "waived" then
            if phase == "active" and other == candidate and binding.scope == scope and not found then found = true
            else return false end
        elseif other == candidate and binding.scope == scope and phase == "waived" then found = true end
    end
    if not scope.tasks[view.token] then return false end
    for token, task in pairs(scope.tasks) do
        visits = visits + 1
        if visits > MAX_EXECUTION_BORROWING_WORK then return false end
        local pickup = task.pickups[view.id]
        if pickup and (pickup.ambiguous or pickup.fullType ~= view.fullType
            or pickup.container ~= view.destination or token ~= view.token)
            or token ~= view.token and claimedInput(scope, task, view.id) then return false end
    end
    return found and queued(queue, action)
end
local function waiverCarried(view, observed)
    local inventory, requested = view.source, view.requested
    if view.record.character:getInventory() ~= inventory or not sameMember(requested, view) then return end
    local item = observed or inventory:getItemById(view.id)
    if not instanceof(item, "InventoryItem") or not sameMember(item, view)
        or item ~= requested and not view.client or item:getContainer() ~= inventory or item:getIsCraftingConsumed() then return end
    local duplicate = view.destination:getItemById(view.id)
    if duplicate ~= nil or inventory:getItemById(view.id) ~= item then return end
    return item
end
local function returnWaiverCandidate(action, guard, allowCurrent, budget, allowReplica)
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
    -- The ordinary exact-reference path keeps its original native proof and
    -- single root lookup. Only an actual Host replacement pays for a view.
    local client = allowReplica and isClient()
    local current, list, native = queue.current, queue.queue, queue.current.action
    local nativeChecker = policy.matchesNative
    if client then
        local ok, valid = pcall(nativeChecker, action)
        if not ok or valid ~= true then return nil, "operation" end
    elseif not nativeChecker(action) then return nil, "operation" end
    local location = item:getContainer()
    if location ~= inventory and not client then return nil, "item_identity" end
    local carried, view = inventory:getItemById(item:getID()), nil
    if carried == item then
        if location ~= inventory or item:getIsCraftingConsumed() then return nil, "item_identity" end
    else
        if not client or not carried then return nil, "item_identity" end
        if #queue.queue > MAX_EXECUTION_MEMBERS then return nil, "unsupported_queue_size" end
        budget = budget or {remaining = MAX_EXECUTION_BORROWING_WORK}
        local groups = action.queueList
        local group = type(groups) == "table" and rawget(groups, 1) or nil
        local items = type(group) == "table" and rawget(group, "items") or nil
        view = {action = action, record = record, step = step, candidate = found, scope = foundScope,
            list = list, current = current, native = native,
            generation = record.generation, token = token, source = inventory, destination = found.source,
            policy = policy, matchesNative = nativeChecker, id = found.id, fullType = found.fullType,
            pickupStep = found.step, stepPhase = step.phase, requested = item, client = true,
            forceCancel = action.forceCancel, onComplete = action.onCompleteFunc, allowMissing = action.allowMissingItems,
            groups = groups, groupsMeta = type(groups) == "table" and getmetatable(groups) or nil,
            group = group, groupMeta = type(group) == "table" and getmetatable(group) or nil,
            items = items, itemsMeta = type(items) == "table" and getmetatable(items) or nil,
            member = type(items) == "table" and rawget(items, 1) or nil,
            owner = found.sourceOwner, ownerId = found.sourceOwner and found.sourceOwner.id,
            ownerType = found.sourceOwner and found.sourceOwner.fullType}
        local ok, present = pcall(waiverCarried, view, carried)
        if not ok or present ~= carried then return nil, "item_identity" end
    end
    if not queued(queue, action) then return nil, "operation" end
    local ok, valid = pcall(guard, action, {id = found.id, fullType = found.fullType})
    if not ok or valid ~= true then return nil, "native_guard" end
    if view then
        -- Native/source guards may reenter. Finish callback-bearing liveness and
        -- ownership checks before the last physical lookup, then check bindings.
        if not operationLive(record) or not borrowingLive(foundScope) or sharedBorrowing(foundScope, found, budget)
            or getSpecificPlayer(record.character:getPlayerNum()) ~= record.character
            or isClient() ~= view.client or not waiverUnchanged(view, "active", item) then return nil, "operation" end
        local present
        ok, present = pcall(waiverCarried, view)
        if not ok or present ~= carried or not waiverUnchanged(view, "active", item) then return nil, "item_identity" end
    end
    return found, foundScope, record, carried or item, view
end

function Settlement.canWaivePendingReturn(action, guard)
    local candidate, detail = returnWaiverCandidate(action, guard, false, nil, true)
    return candidate ~= nil, not candidate and detail or nil
end

function Settlement.pendingReturnWaiver(action, guard)
    local candidate, scope, record, carried, view = returnWaiverCandidate(action, guard, false, nil, true)
    if not candidate then return end
    local handle = {}
    local proof = {action = action, candidate = candidate, scope = scope, record = record, guard = guard,
        item = action.item, carried = carried, view = view, source = action.srcContainer, destination = action.destContainer}
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
    local inventory, item = character:getInventory(), nil
    if proof.view then
        if not borrowingLive(proof.scope)
            or sharedBorrowing(proof.scope, candidate, {remaining = MAX_EXECUTION_BORROWING_WORK})
            or getSpecificPlayer(character:getPlayerNum()) ~= character or proof.source ~= inventory then return end
        local ok
        ok, item = pcall(waiverCarried, proof.view)
        if not ok or item ~= proof.carried or not waiverUnchanged(proof.view, "waived", proof.item) then return end
    else
        -- Failed-return footer receipts and ordinary exact-reference waivers
        -- retain their original strict proof, including closed producer scopes.
        item = inventory:getItemById(candidate.id)
        if getSpecificPlayer(character:getPlayerNum()) ~= character or item ~= proof.item
            or not sameMember(item, candidate) or item:getContainer() ~= inventory
            or proof.source ~= inventory or action.srcContainer ~= proof.source
            or action.destContainer ~= proof.destination or action.item ~= item then return end
    end
    proof.retentionRead = true
    local owner = candidate.sourceOwner
    return {character = character, queue = proof.record.queue, generation = proof.record.generation,
        item = item, requestedItem = proof.view and proof.item ~= item and proof.item or nil,
        source = inventory, destination = proof.destination,
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
    local candidate, scope, record, carried = returnWaiverCandidate(action, guard, false, nil, true)
    if candidate ~= proof.candidate or scope ~= proof.scope or record ~= proof.record or carried ~= proof.carried
        or proof.view and not waiverUnchanged(proof.view, "active", proof.item) then return false end
    -- Keep publication sees the unchanged native item/group. Its private DTO
    -- alone describes the live Host member; no temporary binding is exposed.
    proof.used, candidate.phase = true, "waived"
    local function rollback()
        if candidate.phase == "waived" then candidate.phase = "active" end
        proof.used, proof.retentionRead = false, nil
        return false
    end
    local intent = Toolkit.ActionQueueTidyIntent
    if intent and type(intent.keepReturn) == "function" then
        proof.publishing = true
        local ok, kept = pcall(intent.keepReturn, action, handle)
        proof.publishing = false
        if not ok or kept ~= true then
            return rollback()
        end
    end
    -- Successful publication is the commit boundary. Bind only now, with no
    -- callback/getter afterward that could privately undo already-published Keep.
    if action.item == proof.item then action.item = carried end
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
    local transfers = Toolkit.ActionQueueTransfers
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
    local onMerged=function(action) Settlement.refreshPlannedReturn(action) end
    local canObserve=function(action) return Settlement.plannedReturnMatches(action) end
    local events={
        begin = function(action) return guard(action) and Settlement.beginPlannedReturn(action, guard) end,
        finish = function(action, succeeded) return Settlement.finishPlannedReturn(action, succeeded) end,
    }
    transfers.observeTransfers(onMerged,canObserve,events,Settlement.transferListenerBinding)
    local replacement = ISInventoryTransferAction and ISInventoryTransferAction.checkQueueList
    local valid, policy = previous == replacement, Toolkit.ActionQueuePolicy
    if not valid and policy and type(policy.adoptTransferQueueObserver) == "function" then
        valid = policy.adoptTransferQueueObserver(previous, replacement) == true
    end
    plannedReturnObserver = {transfers = transfers, observe = transfers.observeTransfers, valid = valid,
        callback=onMerged,canObserve=canObserve,events=events}
    return valid
end

function Settlement.preparationAvailable()
    local lifecycle, transfers = Toolkit.ActionQueueLifecycle, Toolkit.ActionQueueTransfers
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
    local onMerged=function(action)
        local step = preparationStep(action)
        if step and step.preparation.scope then Settlement.refreshPickup(step.preparation.scope, action) end
    end
    local canObserve=function(action)
        local step = preparationStep(action)
        return step and step.preparation.scope and preparationGuard(action) or false
    end
    local events={
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
    }
    transfers.observeTransfers(onMerged,canObserve,events,Settlement.transferListenerBinding)
    local replacement = ISInventoryTransferAction and ISInventoryTransferAction.checkQueueList
    local valid = previous == replacement
    local policy = Toolkit.ActionQueuePolicy
    if not valid and policy and type(policy.adoptTransferQueueObserver) == "function" then
        valid = policy.adoptTransferQueueObserver(previous, replacement) == true
    end
    preparationObserver = {lifecycle = lifecycle, register = lifecycle.registerObserver,
        transfers = transfers, observe = transfers.observeTransfers, valid = valid,
        callback=onMerged,canObserve=canObserve,events=events}
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

-- Source-reviewed native producers can keep body claims in the same private
-- preparation scope. Inspect only enrolled operations, not arbitrary enqueues.
function Settlement.rememberPreparation(action, inspector)
    local record = action and operation(action.character, action.toolkitQueueOperation)
    local scope = record and record.preparationScope
    if not scope or not borrowingLive(scope) or type(inspector) ~= "function"
        or not executionProof or not executionProof.closure(inspector, "ActionQueueDefinitions.lua") then return false end
    local contract = inspector(action)
    if record.preparationScope ~= scope or action.character ~= record.character
        or action.toolkitQueueOperation ~= record.token or not operationLive(record) then return false end
    return Settlement.remember(scope, action, contract)
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
    local result = planned and Settlement.finishReturn(planned.obligation, succeeded) or false
    local proof = planned and returnProof(planned.obligation)
    if requestMethods and proof and proof.ended then requestMethods.clear(action) end
    return result
end

local function resolveReturn(queue, id, expected, containers, observation)
    local inventory, destination = queue.character:getInventory(), expected.destination
    local owner = expected.borrowed and expected.borrowed.sourceOwner
    if owner then
        local holder = inventory:getItemById(owner.id)
        -- Ground placement/Host pickup may replace the Java bag/container replica.
        -- Rebind only its captured exact owner, still carried by this actor.
        if not sameMember(holder, owner) or type(holder.getInventory) ~= "function" then return end
        destination = holder:getInventory()
        if observation then
            if not observation.carried or observation.carried(destination, queue.character) ~= true then return end
        elseif not Toolkit.ActionQueuePolicy.isCarriedContainer(destination, queue.character) then return end
    end
    local item = not expected.ambiguous and inventory:getItemById(id)
    if not destination or not item or item:getID() ~= id or item:getFullType() ~= expected.fullType
        or item:getContainer() ~= inventory or item:getIsCraftingConsumed()
        or not destination:isExistYet() or not (observation and observation.endpoint(destination, queue.character)
            or not observation and (containers:contains(destination)
                or Toolkit.ActionQueuePolicy.isCarriedContainer(destination, queue.character))) then return end
    if observation then
        -- Fresh observation never grants construction or native admission. The
        -- opposite endpoint must not already hold the same physical identity.
        local duplicate = destination:getItemById(id)
        if duplicate ~= nil then return end
        if owner and (inventory:getItemById(owner.id) ~= observation.owner
            or observation.owner:getContainer() ~= inventory
            or observation.owner:getInventory() ~= destination) then return end
        if queue.character:getInventory() ~= inventory or inventory:getItemById(id) ~= item or item:getContainer() ~= inventory
            or item:getID() ~= id or item:getFullType() ~= expected.fullType or item:getIsCraftingConsumed() then return end
        duplicate = destination:getItemById(id)
        if duplicate ~= nil then return end
        if owner and (observation.owner:getContainer() ~= inventory or observation.owner:getInventory() ~= destination) then return end
    end
    return item, inventory, destination
end
local function makeReturn(queue, id, expected, containers)
    local item, inventory, destination = resolveReturn(queue, id, expected, containers)
    if not item then return end
    local action = ISInventoryTransferUtil.newInventoryTransferAction(queue.character, item, inventory, destination)
    if action.Type ~= "ISInventoryTransferAction"
        and (isClient() or not Toolkit.ActionQueueCarts or not Toolkit.ActionQueueCarts.isTransfer(action)) then return end
    if action.Type == "ISInventoryTransferAction" then Toolkit.BulkActions.guardTransfer(action) end
    action:setAllowMissingItems(true)
    return action
end

-- Fresh bounded facts for an opt-in edit projection. The metadata ledger above
-- remains callback-free; this layer reads exact endpoints, never native outcome
-- state, providers, constructors, validation, or capacity. Nothing here earns debt.
function Settlement.observeEditCleanup(queue, current)
    local function unknown() return {status = "unhandled", reason = "edit_obligation_unknown"} end
    local budget = {remaining = 128}
    local result, record = editLedger(queue, current, budget)
    if result.status ~= "observed" or not rawget(current, "action") then return unknown() end
    local watches, maps = {}, {}
    local meta, equal, raw, pairsOf, each, kind = getmetatable, rawequal, rawget, pairs, ipairs, type
    -- Own reads never dispatch __index on a removed field. The global/module
    -- records are tiny fixed selections, not snapshots of their whole tables.
    local function own(owner, key)
        if meta(owner) == nil then return raw(owner, key) end
        local count = 0
        for name, value in pairsOf(owner) do
            count = count + 1
            if count > 128 then return end
            if equal(name, key) then return value end
        end
    end
    local revision = providerRevision
    local function take()
        budget.remaining = budget.remaining - 1
        return budget.remaining >= 0
    end
    local function plain(value) return type(value) == "table" and getmetatable(value) == nil end
    local function watch(owner, key)
        local value = own(owner, key)
        watches[#watches + 1] = {owner = owner, key = key, value = value, meta = meta(owner)}
        return value
    end
    local function fields(owner, names)
        if not plain(owner) then return false end
        for _, key in ipairs(names) do watch(owner, key) end
        return true
    end
    local function array(values, maximum)
        if not plain(values) then return end
        local count, size = 0, #values
        if size > maximum then return end
        for key in pairs(values) do
            if not take() or type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > size then return end
            count = count + 1
            watch(values, key)
        end
        if count ~= size then return end
        maps[#maps + 1] = {value = values, count = count}
        return size
    end
    local function map(values, visit)
        if not plain(values) then return false end
        local count = 0
        for key, value in pairs(values) do
            if not take() then return false end
            count = count + 1
            watch(values, key)
            if visit and not visit(key, value) then return false end
        end
        maps[#maps + 1] = {value = values, count = count}
        return true
    end
    local list, actor, token, generation = queue.queue, record.character, record.token, record.generation
    local native = rawget(current, "action")
    if not array(list, 32) or not fields(record, {"character", "token", "queue", "generation", "phase", "settlement", "steps", "actions", "borrowings"}) then return unknown() end
    for _, key in ipairs({"character", "current", "queue", "toolkitOperationGeneration", "toolkitCancel", "toolkitGroupCancel",
        "toolkitResume", "toolkitOutcomeWait", "toolkitStopIntent"}) do watch(queue, key) end
    watch(token, "toolkitCancelled"); watch(token, "toolkitPickups")
    for _, key in ipairs({"character", "toolkitQueueOperation", "action", "started", "Type", "item"}) do watch(current, key) end
    local stepCount = array(record.steps, 32)
    local borrowingCount = array(record.borrowings, 32)
    if not stepCount or not borrowingCount then return unknown() end
    for index = 1, stepCount do
        local step = record.steps[index]
        if not fields(step, {"operation", "action", "phase", "state", "started", "required", "returning", "prerequisites", "borrowing"}) then return unknown() end
        watch(record.actions, step.action)
        watch(step.action, "character"); watch(step.action, "toolkitQueueOperation"); watch(step.action, "Type")
        if step.prerequisites and not array(step.prerequisites, 128) then return unknown() end
        for _, previous in ipairs(step.prerequisites or {}) do
            if not fields(previous, {"operation", "action", "state"}) then return unknown() end
        end
    end
    local activeIds, covered, scopes, entries, outstanding = {}, {}, {}, {}, 0
    for index = 1, borrowingCount do
        local binding, value = record.borrowings[index], result.borrowings[index]
        local candidate = binding.candidate
        if not fields(binding, {"scope", "candidate"})
            or not fields(candidate, {"owner", "id", "fullType", "phase", "ambiguous", "source", "destination", "sourceOwner",
                "step", "returning", "plannedReturn"}) then return unknown() end
        if candidate.sourceOwner and not fields(candidate.sourceOwner, {"id", "fullType"}) then return unknown() end
        covered[candidate.id] = true
        if candidate.phase ~= "completed" and candidate.phase ~= "waived" then
            activeIds[candidate.id] = (activeIds[candidate.id] or 0) + 1
            outstanding = outstanding + 1
        end
        entries[index] = {binding = binding, candidate = candidate, scope = binding.scope, value = value}
        value.disposition = "unresolved"
        if candidate.phase == "completed" or candidate.phase == "waived" then value.disposition = "settled" end
    end
    local hints = rawget(token, "toolkitPickups")
    result.legacyHints = false
    if hints ~= nil then
        if not map(hints, function(item)
            if not instanceof(item, "InventoryItem") then return false end
            local ok, id = pcall(function() return item:getID() end)
            if not ok or type(id) ~= "number" or id % 1 ~= 0 then return false end
            if not covered[id] then result.legacyHints = true end
            return true
        end) then return unknown() end
    end
    local policy, adapters = Toolkit.ActionQueuePolicy, Toolkit.ActionQueueItemEditAdapters
    local nativeFacts, nativeAliasFacts = toolkitLeafTransferFacts, toolkitLeafTransferAliasFacts
    local binding = type(adapters) == "table" and rawget(adapters, "deferredTransferBinding")
    local carried = type(policy) == "table" and rawget(policy, "isCarriedContainer")
    local world = type(adapters) == "table" and rawget(adapters, "worldContainer")
    local origin = editLedgerOrigin
    local carriedTrusted = type(carried) == "function" and origin(carried, "ActionQueuePolicy.lua")
    local worldTrusted = type(world) == "function" and origin(world, "ActionQueueItemEditAdapters.lua")
    local bindingTrusted = type(binding) == "function" and origin(binding, "ActionQueueItemEditAdapters.lua")
    local globals, queueClass, queueMap = _G, ISTimedActionQueue, ISTimedActionQueue.queues
    for _, key in ipairs({"PZSurvivorToolkit", "ISTimedActionQueue", "toolkitLeafTransferFacts", "toolkitLeafTransferAliasFacts"}) do watch(globals, key) end
    for _, key in ipairs({"ActionQueueSettlement", "ActionQueuePolicy", "ActionQueueItemEditAdapters"}) do watch(Toolkit, key) end
    watch(executionProof, "closure"); watch(queueClass, "queues"); watch(queueMap, actor)
    if kind(policy) == "table" then watch(policy, "isCarriedContainer") end
    if kind(adapters) == "table" then watch(adapters, "worldContainer"); watch(adapters, "deferredTransferBinding") end
    local function unchanged()
        for _, entry in each(watches) do
            if not equal(meta(entry.owner), entry.meta) or not equal(own(entry.owner, entry.key), entry.value) then return false end
        end
        for _, entry in each(maps) do
            local count = 0
            for _ in pairsOf(entry.value) do
                count = count + 1
                if count > entry.count then return false end
            end
            if count ~= entry.count then return false end
        end
        return equal(own(globals, "PZSurvivorToolkit"), Toolkit)
            and equal(own(Toolkit, "ActionQueueSettlement"), Settlement)
            and equal(own(executionProof, "closure"), origin)
            and equal(own(Toolkit, "ActionQueuePolicy"), policy)
            and equal(own(Toolkit, "ActionQueueItemEditAdapters"), adapters)
            and (kind(policy) ~= "table" or equal(own(policy, "isCarriedContainer"), carried))
            and (kind(adapters) ~= "table" or equal(own(adapters, "worldContainer"), world)
                and equal(own(adapters, "deferredTransferBinding"), binding))
            and equal(own(globals, "toolkitLeafTransferFacts"), nativeFacts)
            and equal(own(globals, "toolkitLeafTransferAliasFacts"), nativeAliasFacts)
            and equal(own(globals, "ISTimedActionQueue"), queueClass)
            and equal(own(queueClass, "queues"), queueMap) and equal(own(queueMap, actor), queue)
            and equal(own(queue, "current"), current) and equal(own(queue, "queue"), list)
            and equal(list[1], current) and equal(own(current, "action"), native)
            and not cancellations[queue] and providerRevision == revision
    end

    local root, alive, localActor
    local ok = pcall(function()
        root, alive = actor:getInventory(), not actor:isDead()
        localActor = getSpecificPlayer(actor:getPlayerNum()) == actor
    end)
    if not ok or not root or not alive or not localActor or not unchanged() then return unknown() end
    for _, entry in ipairs(entries) do
        local candidate, scope, binding, value = entry.candidate, entry.scope, entry.binding, entry.value
        local step = candidate.step
        if step ~= nil and not plain(step) then return unknown() end
        if outstanding == 1 and candidate.phase == "active" and activeIds[candidate.id] == 1 and not candidate.ambiguous
            and not candidate.returning and not candidate.plannedReturn and candidate.owner == token
            and candidate.destination == root and plain(scope) and step and step.operation == record and step.phase == "prepare" and step.state == "earned"
            and step.borrowing == binding and record.actions[step.action] == step then
            local scopeState = scopes[scope]
            if scopeState == nil then
                scopeState = {valid = deferred(scope) and scope.phase ~= "retired" and scope.character == actor
                    and scope.queue == queue and scope.generation == generation}
                scopes[scope] = scopeState
                if not fields(scope, {"marker", "character", "queue", "generation", "phase", "tasks", "equipmentItems"})
                    or not plain(scope.tasks) or not plain(scope.equipmentItems) then return unknown() end
                if not map(scope.tasks, function(taskToken, task)
                    return type(taskToken) == "table" and fields(task, {"items", "pickups", "unknownInputs", "readsEquipment"})
                        and plain(task.items) and plain(task.pickups)
                end) then return unknown() end
            end
            local exclusive = scopeState.valid and scope.tasks[token] ~= nil
            for taskToken, task in pairs(scope.tasks) do
                if not take() then return unknown() end
                local pickup = watch(task.pickups, candidate.id)
                local claimed = watch(task.items, candidate.id)
                local equipment = watch(scope.equipmentItems, candidate.id)
                if pickup ~= nil then
                    if not fields(pickup, {"ambiguous", "fullType", "container"}) then return unknown() end
                    if pickup.ambiguous or pickup.fullType ~= candidate.fullType or pickup.container ~= candidate.source
                        or taskToken ~= token then exclusive = false end
                end
                if taskToken ~= token and (task.unknownInputs or claimed or task.readsEquipment and equipment) then exclusive = false end
            end
            if exclusive and (carriedTrusted or worldTrusted) then
                local observation = {carried = carriedTrusted and carried or nil, endpoint = function(destination)
                    if carriedTrusted and carried(destination, actor) == true then return true end
                    return worldTrusted and world(destination, actor) ~= nil
                end}
                local owner = candidate.sourceOwner
                if owner then
                    ok, observation.owner = pcall(function() return root:getItemById(owner.id) end)
                    if not ok then observation.owner = nil end
                end
                local present, item, source, destination = pcall(resolveReturn, queue, candidate.id,
                    {fullType = candidate.fullType, destination = candidate.source, borrowed = candidate}, nil, observation)
                if not unchanged() then return unknown() end
                if present and item and source == root then
                    value.disposition, value.item, value.source, value.destination = "synthesize-return", item, source, destination
                end
            end
        end
    end
    local stillLive, valid = pcall(function()
        return not actor:isDead() and getSpecificPlayer(actor:getPlayerNum()) == actor and actor:getInventory() == root
    end)
    if not stillLive or not valid or not unchanged() then return unknown() end
    -- A source lease precedes the final callback-free JVM read. No metadata,
    -- native getter, provider or helper guard may run after that read. A missing
    -- contract retains the typed debt, with its physical effect still unknown.
    if outstanding == 1 and bindingTrusted and type(nativeFacts) == "function" and not result.providersPresent then
        for _, entry in ipairs(entries) do
            local value, prototype = entry.value, nil
            if value.disposition == "synthesize-return" then
                for index = 2, #list do
                    local member = list[index]
                    if rawget(member, "toolkitQueueOperation") ~= token then break end
                    if rawequal(rawget(member, "item"), value.item)
                        and rawequal(rawget(member, "srcContainer"), value.source)
                        and rawequal(rawget(member, "destContainer"), value.destination) then
                        if prototype then prototype = nil; break end
                        prototype = member
                    end
                end
                local bound, lease, aliasMember
                if prototype then
                    -- Private synchronous context lets our own listener attester
                    -- reuse this exact earned record without reopening a token
                    -- seal, invoking liveness callbacks or exporting handles.
                    local previousContext=activeEditCleanupBinding
                    activeEditCleanupBinding={record=record,queue=queue,current=current,action=prototype}
                    bound,lease,aliasMember=pcall(binding,prototype,current)
                    activeEditCleanupBinding=previousContext
                end
                if not unchanged() then return unknown() end
                if bound and type(lease) == "function" then
                    local read, facts
                    -- Native ID resolution proves only the prospective target;
                    -- old-member admission/weight and completion remain native.
                    if aliasMember~=nil then
                        if type(nativeAliasFacts)=="function" then
                            read,facts=pcall(nativeAliasFacts,actor,value.item,value.source,value.destination,value.id,value.fullType,aliasMember)
                        end
                    else
                        read,facts=pcall(nativeFacts,actor,value.item,value.source,value.destination,value.id,value.fullType)
                    end
                    -- Only plain DTO fields and private/source identities below.
                    local leased = lease(facts)
                    if not unchanged() then return unknown() end
                    if leased and read and kind(facts) == "table" and meta(facts) == nil and facts.schema == 2
                        and equal(facts.item, value.item) and equal(facts.source, value.source)
                        and equal(facts.destination, value.destination) and equal(facts.location, value.source)
                        and facts.id == value.id and facts.fullType == value.fullType then
                        value.effect = "native-leaf-location"
                        value.returnAction = prototype
                    end
                end
            end
        end
    end
    if not unchanged() then return unknown() end
    result.fresh = true
    return result
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
        candidate, scope, owner = returnWaiverCandidate(action, guard, true, budget, false)
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
-- The bridge proves the actual stock caller; this guard only selects our
-- private owner. Facts do not grant permissions, so do not repeat the full
-- planner/native-capability inspector here. Existing outcome guards retain it.
local function requestGuard(action)
    local planned = plannedReturn(action)
    local execution = planned and planned.execution
    -- A new observed call invalidates the previous unpaired observation even
    -- when its shape/source is now unsupported. Never recycle it by byte ID.
    if execution then execution.request = nil end
    return execution and execution.queue.current == action and execution.queue.queue[1] == action
        and action.srcContainer == execution.source and action.destContainer == execution.destination
        and action.character == execution.actor
        and (execution.queue.toolkitOperationGeneration or 0) == execution.generation or false
end
local requestMemberBinding
local function requestMember(action, member)
    if member == action.item then return true end
    local methods, owner = requestMethods, Toolkit.ActionQueueItemEditAdapters
    local own, origin = methods and methods.proofOwn, methods and methods.proofOrigin
    if not own or not origin or executionProof.own ~= own or executionProof.closure ~= origin
        or type(owner) ~= "table" or getmetatable(owner) ~= nil then return false end
    local binding = requestMemberBinding
    if not binding then
        local checker = own(owner, "matchesTransferMember")
        if not origin(checker, "ActionQueueItemEditAdapters.lua") then return false end
        binding = {owner = owner, checker = checker}
        requestMemberBinding = binding
    end
    if binding.owner ~= owner or own(owner, "matchesTransferMember") ~= binding.checker then return false end
    -- Native Host may rebind action.item while retaining an older same-ID group
    -- member. Reuse the source-owned alias proof; native arguments stay intact.
    local accepted = binding.checker(action, member) == true
    return accepted and Toolkit.ActionQueueItemEditAdapters == owner
        and own(owner, "matchesTransferMember") == binding.checker
        and executionProof.own == own and executionProof.closure == origin
end
local function requestBefore(action, receipt)
    local planned = plannedReturn(action)
    local execution = planned and planned.execution
    local group = action.queueList and action.queueList[1]
    if not execution or receipt:getSource() ~= execution.source or receipt:getDestination() ~= execution.destination
        or not group or receipt:getItems() ~= group.items or #group.items ~= 1 or not requestMember(action, group.items[1]) then return end
    local request = {native = action.action, boundary = receipt:getBoundary(), phase = "before", dispatcher = createItemTransaction,
        id = execution.id, fullType = execution.fullType}
    request.sourceExact = sourceEvidence(action, execution) == true
    execution.request = request
    return request
end
local function requestAfter(action, request, receipt, ambiguous)
    local planned = plannedReturn(action)
    local execution = planned and planned.execution
    if not request or not execution or execution.request ~= request or request.native ~= action.action then return end
    request.phase, request.transaction, request.ambiguous = receipt:getPhase(), receipt:getTransaction(), ambiguous == true
    request.receipt = receipt
end
-- Last observed supported call, not current transaction/admission authority.
-- Explicit diagnostics for native verification; no UI polling or permissions.
function Settlement.nativeRequestState(action)
    local planned = plannedReturn(action)
    local request = planned and planned.execution and planned.execution.request
    if not request then return end
    return {phase = request.phase, boundary = request.boundary, sourceExact = request.sourceExact, ambiguous = request.ambiguous,
        paired = request.paired == true,
        -- Explicit diagnostics only: resolve the captured native object while it
        -- still exists, rather than treating a historical byte as a live request.
        currentHandle = request.receipt and type(request.receipt.matchesTransaction) == "function"
            and type(action.transactionId) == "number" and request.receipt:matchesTransaction(action, action.transactionId) == true or false,
        nativeHandle = request.receipt and type(request.receipt.hasNativeHandle) == "function"
            and request.receipt:hasNativeHandle() == true or false,
        wireAmbiguous = not (request.receipt and type(request.receipt.isWireAmbiguous) == "function")
            or request.receipt:isWireAmbiguous() ~= false,
        transaction = request.transaction, id = request.id, fullType = request.fullType}
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
    local methods = transferRequests()
    local commitRequest = methods and methods.prepare(action, requestGuard, requestBefore, requestAfter)
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
    if commitRequest then commitRequest() end
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
    if requestMethods then requestMethods.clear(action) end
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
    if requestMethods and queue then requestMethods.reset(queue.character) end
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
-- Only our private in-progress observation can attest dormant listener state.
-- No public flags, token callbacks, outcome readers or liveness getters run here.
function Settlement.transferListenerBinding(action,onMerged,canObserve,events)
    local context=activeEditCleanupBinding
    if not context or not rawequal(context.action,action) or not transferListenerMethods
        or not executionProof or type(executionProof.captureBindings)~="function" then return end
    local observer
    for _,value in ipairs({plannedReturnObserver,preparationObserver}) do
        if value and rawequal(value.callback,onMerged) and rawequal(value.canObserve,canObserve)
            and rawequal(value.events,events) then observer=value;break end
    end
    if not observer or not observer.valid then return end
    local record=context.record
    local step=record.actions[action]
    if step and (step.returning or step.preparation) then return end
    local keys={}
    for key,value in pairs(transferListenerMethods) do
        if not rawequal(Settlement[key],value) then return end
        keys[#keys+1]=key
    end
    local specifications={
        {owner=record.actions,keys={action}}, {owner=observer,exact=true}, {owner=events,exact=true},
        {owner=record,keys={"actions","token","queue","character","generation","settlement"}},
        {owner=action,keys={"toolkitQueueOperation","character"}},
        {owner=Toolkit,keys={"ActionQueueSettlement","ActionQueueTransfers"}},
        {owner=Settlement,keys=keys},
    }
    if step then specifications[#specifications+1]={owner=step,keys={"returning","preparation"}} end
    local watch=executionProof.captureBindings(specifications)
    if not watch then return end
    return function()return watch()end
end
transferListenerMethods={}
for _,key in ipairs({"transferListenerBinding","refreshPlannedReturn","plannedReturnMatches","beginPlannedReturn",
    "finishPlannedReturn","refreshPickup","beforePickupMerge","beginPickup","finishPickup"}) do
    transferListenerMethods[key]=Settlement[key]
end
local sourceAdapters=Toolkit.ActionQueueItemEditAdapters
if sourceAdapters and sourceAdapters.registerSourceFactory then
    sourceAdapters.registerSourceFactory(Settlement,"transferListenerBinding",Settlement.transferListenerBinding)
end

-- Source-owned device admission uses the existing private operation steps.
local deviceBinding
local deviceCall = pcall
local deviceRaw, deviceSet, deviceKind, deviceMeta, deviceEach, devicePairs, deviceEqual = rawget, rawset, type, getmetatable, ipairs, pairs, rawequal
local function deviceOwner()
    local owner = Toolkit.ActionQueueDeviceTargets
    if type(owner) ~= "table" or getmetatable(owner) ~= nil or not executionProof
        or type(executionProof.own) ~= "function" or type(executionProof.closure) ~= "function" then return end
    if not deviceBinding then
        local methods = {}
        for _, name in ipairs({"owns", "validateNativeRole", "worldLost", "watchSources"}) do
            local method = executionProof.own(owner, name)
            if not executionProof.closure(method, "ActionQueueDeviceTargets.lua") then return end
            methods[name] = method
        end
        deviceBinding = {owner = owner, methods = methods, proof = executionProof,
            own = executionProof.own, origin = executionProof.closure, capture = executionProof.captureBindings}
    end
    local saved = deviceBinding
    if PZSurvivorToolkit ~= Toolkit or Toolkit.ActionQueueSettlement ~= Settlement
        or owner ~= saved.owner or executionProof ~= saved.proof
        or executionProof.own ~= saved.own or executionProof.closure ~= saved.origin
        or executionProof.captureBindings ~= saved.capture then return end
    for name, method in pairs(saved.methods) do if saved.own(owner, name) ~= method then return end end
    return saved
end
local function acceptedDevice(callback, ...)
    local ok, result = deviceCall(callback, ...)
    return ok and result == true
end
function Settlement.bindDeviceStep(action, descriptor)
    local owner = deviceOwner()
    if not owner or type(action) ~= "table"
        or not acceptedDevice(owner.methods.owns, action, descriptor) then return false end
    local record = operation(action.character, action.toolkitQueueOperation)
    local step = record and record.actions[action]
    if not step or step.device ~= nil or step.started or step.state ~= "pending"
        or action.action or action.started then return false end
    step.device = descriptor
    return true
end
function Settlement.deviceStep(action)
    local owner = deviceOwner()
    local record = owner and action and operation(action.character, action.toolkitQueueOperation)
    local step = record and record.actions[action]
    if step and step.device and acceptedDevice(owner.methods.owns, action, step.device) then return step.device end
end

-- Queue order, not ledger insertion order, selects the exact pending suffix.
-- A retained paid position head is never removed, canceled or invalidated.
function Settlement.prepareDeviceRefusal(queue, current, members)
    -- Unknown cleanup providers may retain obligations outside these steps.
    -- Refusal never calls their retain/ownsPickup callbacks to guess otherwise.
    if #providers > 0 then return end
    local deviceProviderRevision = providerRevision
    local raw, set, kind, meta, each, pairsOf, equal = deviceRaw, deviceSet, deviceKind, deviceMeta, deviceEach, devicePairs, deviceEqual
    local owner = deviceOwner()
    if not owner or kind(queue) ~= "table" or kind(current) ~= "table" or kind(members) ~= "table"
        or meta(members) ~= nil or #members < 1 or #members > 32
        or kind(members[1]) ~= "table" then return end
    local memberToken = raw(members[1], "toolkitQueueOperation")
    if kind(memberToken) ~= "table" or meta(memberToken) ~= nil then return end
    local record = operation(queue.character, memberToken)
    if not record then return end
    local function own(value, key)
        for name, entry in pairsOf(value) do if equal(name, key) then return entry end end
    end
    local token, actor, list, generation = record.token, record.character, queue.queue, record.generation
    if kind(list) ~= "table" or meta(list) ~= nil or #list < 1 or #list > 128 then return end
    local function array(values, maximum)
        if kind(values) ~= "table" or meta(values) ~= nil or #values > maximum then return false end
        local count = 0
        for key in pairsOf(values) do
            count = count + 1
            if count > maximum or kind(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #values then return false end
        end
        return count == #values
    end
    local methods, targets = owner.methods, {}
    local memberCount = 0
    for key, action in pairsOf(members) do
        if kind(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #members
            or kind(action) ~= "table" or targets[action] then return end
        memberCount = memberCount + 1; targets[action] = true
    end
    if memberCount ~= #members then return end
    local failed, descriptor, removedCurrent
    local function role(action, step, stage)
        if step.device == nil or not acceptedDevice(methods.owns, action, step.device) then return end
        local ok, result = pcall(methods.validateNativeRole, action, step.device, stage)
        if ok and (result == "device" or result == "position") then return result end
    end
    local function pending(action, step)
        return step.started ~= true and not own(action, "action") and not own(action, "started")
            and own(action, "toolkitNativeTransaction") == nil and own(action, "toolkitNativeKind") == nil
            and (own(action, "transactionId") == nil or own(action, "transactionId") == 0)
    end
    local function eligible()
        if #providers > 0 or providerRevision ~= deviceProviderRevision then return false end
        local fresh = deviceOwner()
        local liveRecord = operation(actor, token)
        if fresh ~= owner or liveRecord ~= record or record.token ~= token or record.queue ~= queue
            or record.character ~= actor or record.generation ~= generation
            or kind(generation) ~= "number" or generation % 1 ~= 0
            or rawget ~= raw or rawset ~= set or type ~= kind or getmetatable ~= meta
            or ipairs ~= each or pairs ~= pairsOf or rawequal ~= equal or pcall ~= deviceCall
            or not operationLive(record) or not actor:isLocalPlayer() or actor:isAsleep()
            or getSpecificPlayer(actor:getPlayerNum()) ~= actor
            or ISTimedActionQueue.queues[actor] ~= queue or queue.character ~= actor
            or queue.queue ~= list or queue.current ~= current or list[1] ~= current
            or own(current, "character") ~= actor or meta(record) ~= nil
            or not array(list, 128) or not array(record.steps, 32) or not array(record.borrowings, 32)
            or kind(record.actions) ~= "table" or meta(record.actions) ~= nil
            or queue.toolkitCancel or queue.toolkitGroupCancel or queue.toolkitResume
            or queue.toolkitOutcomeWait or queue.toolkitStopIntent
            or (record.phase ~= "prepare" and record.phase ~= "body")
            or (raw(token, "toolkitContinuations") ~= nil and raw(token, "toolkitContinuations") ~= 0)
            or raw(token, "toolkitCancelled")
            or record.preparationScope ~= nil
            or record.settlement ~= nil or #record.borrowings ~= 0 or raw(token, "toolkitPickups") ~= nil
            or cancellations[queue] or queue.toolkitOperationsInvalid
            or record.phase == "cleanup" then return false end
        local positions, queued = {}, {}
        for index, action in each(list) do
            if kind(action) ~= "table" then return false end
            if own(action, "toolkitQueueOperation") == token then
                if not record.actions[action] or queued[action] then return false end
                queued[action], positions[action] = true, index
            end
        end
        local deviceAction, deviceDescriptor, count, steps = nil, nil, 0, {}
        for _, step in each(record.steps) do
            if kind(step) ~= "table" or meta(step) ~= nil then return false end
            local action = step.action
            if steps[action] then return false end
            steps[action] = step
            if kind(step) ~= "table" or meta(step) ~= nil or step.operation ~= record
                or kind(action) ~= "table" or record.actions[action] ~= step
                or own(action, "character") ~= actor or own(action, "toolkitQueueOperation") ~= token
                or step.state ~= "pending" or (step.phase ~= "prepare" and step.phase ~= "body") or step.required or step.receipt
                or step.prerequisites ~= nil or step.returning or step.preparation or step.borrowing
                or own(action, "onCompleteFunc") or own(action, "onCancelFunc") or own(action, "onStartFunc")
                or own(action, "toolkitQueueContinuation") then return false end
            local index, nativeRole = positions[action]
            if targets[action] then
                if not index or not pending(action, step) then return false end
                nativeRole = role(action, step, "pending")
                if not nativeRole then return false end
                if nativeRole == "device" then
                    count = count + 1; deviceAction, deviceDescriptor = action, step.device
                end
            elseif action == current then
                if index ~= 1 or not step.started or not own(action, "action")
                    or role(action, step, "current-position") ~= "position" then return false end
            else
                if index or not step.started or role(action, step, "completed-position") ~= "position" then return false end
            end
        end
        local stepCount = 0
        for action, step in pairsOf(record.actions) do
            stepCount = stepCount + 1
            if stepCount > 32 or steps[action] ~= step then return false end
        end
        if stepCount ~= #record.steps then return false end
        -- One source-owned device body and its position steps only. Broader
        -- producers must supply an explicit common-target contract first.
        if count ~= 1 then return false end
        local last = 0
        for _, action in each(members) do
            if not targets[action] or not positions[action] or positions[action] <= last then return false end
            last = positions[action]
        end
        if failed and (deviceAction ~= failed or deviceDescriptor ~= descriptor) then return false end
        failed, descriptor, removedCurrent = deviceAction, deviceDescriptor, targets[current] == true
        return true
    end
    if not eligible() or #providers > 0 or providerRevision ~= deviceProviderRevision then return end

    -- Only primitive table/identity reads occur through this mirror. It is
    -- query-local, not a second operation ledger or an authorization cache.
    local watches = {}
    local function watch(value, keys, exact)
        if kind(value) ~= "table" then return false end
        local entries = {}
        if exact then
            local count = 0
            for key, entry in pairsOf(value) do
                count = count + 1; if count > 128 then return false end
                entries[#entries + 1] = {key = key, value = entry}
            end
        else
            for _, key in each(keys) do entries[#entries + 1] = {key = key, value = own(value, key)} end
        end
        watches[#watches + 1] = {owner = value, meta = meta(value), entries = entries, exact = exact}
        return true
    end
    watch(_G, {"PZSurvivorToolkit", "ISTimedActionQueue", "rawget", "rawset", "type", "getmetatable", "ipairs", "pairs", "rawequal", "pcall", "getSpecificPlayer"})
    watch(Toolkit, {"ActionQueueSettlement", "ActionQueueDeviceTargets", "Settings"})
    watch(Toolkit.Settings, {"actionQueue"})
    watch(owner.owner, {"owns", "validateNativeRole", "worldLost", "watchSources"})
    watch(executionProof, {"own", "closure", "captureBindings"})
    watch(ISTimedActionQueue, {"queues"}); watch(ISTimedActionQueue.queues, {actor})
    watch(cancellations, {queue})
    if not watch(queue, nil, true) or not watch(list, nil, true) or not watch(members, nil, true)
        or not watch(providers, nil, true)
        or not watch(token, nil, true) or not watch(record, nil, true)
        or not watch(record.steps, nil, true) or not watch(record.actions, nil, true)
        or not watch(record.borrowings, nil, true) then return end
    for _, step in each(record.steps) do
        if not watch(step, nil, true) or not watch(step.action, nil, true) then return end
    end
    if not record.actions[current] and not watch(current,nil,true)then return end
    local seen={}
    for _,entry in each(watches)do seen[entry.owner]=true end
    local function ancestry(value,depth)
        if value==nil then return true end
        if kind(value)~='table'or depth>8 then return false end
        if seen[value]then return true end
        seen[value]=true
        if not watch(value,nil,true)then return false end
        local index=own(value,'__index')
        if index~=nil and kind(index)~='table'then return false end
        return ancestry(meta(value),depth+1)and(index==nil or equal(index,value)or ancestry(index,depth+1))
    end
    if not ancestry(meta(current),1)then return end
    for _,step in each(record.steps)do if not ancestry(meta(step.action),1)then return end end
    local specifications,certificates={},{}
    for _,entry in each(watches)do
        local spec={owner=entry.owner,exact=entry.exact}
        if not entry.exact then
            spec.keys={}
            for _,field in each(entry.entries)do spec.keys[#spec.keys+1]=field.key end
        end
        specifications[#specifications+1]=spec
        if #specifications==32 then
            local certificate=owner.capture(specifications)
            if kind(certificate)~='function'or not certificate()then return end
            certificates[#certificates+1]=certificate;specifications={}
        end
    end
    if #specifications>0 then
        local certificate=owner.capture(specifications)
        if kind(certificate)~='function'or not certificate()then return end
        certificates[#certificates+1]=certificate
    end
    -- This retained primitive checks the real table metatable, including a
    -- protected replacement reporting the old public __metatable value. It
    -- never executes Lua getters, metadata readers or world callbacks.
    local function actualTables()
        for _,certificate in each(certificates)do if not certificate()then return false end end
        return true
    end
    if not actualTables()then return end
    local function unchanged()
        if providerRevision ~= deviceProviderRevision then return false end
        for _, entry in each(watches) do
            if not equal(meta(entry.owner), entry.meta) then return false end
            for _, field in each(entry.entries) do
                if not equal(own(entry.owner, field.key), field.value) then return false end
            end
            if entry.exact then
                local count = 0
                for _ in pairsOf(entry.owner) do count = count + 1; if count > #entry.entries then return false end end
                if count ~= #entry.entries then return false end
            end
        end
        return true
    end
    local used = false
    return function(checkWorld, watchSources)
        if used then return false end
        used = true
        if checkWorld ~= methods.worldLost or watchSources ~= methods.watchSources
            or not unchanged() or not eligible() or not unchanged() then return false end
        if not acceptedDevice(watchSources, failed, descriptor) or not unchanged() then return false end
        if not acceptedDevice(checkWorld, failed, descriptor) then return false end
        -- No Settings/isDead/operationLive/owner/native callback beyond here.
        if not unchanged() or not actualTables() then return false end
        local size = #list
        for index = size, 1, -1 do
            if targets[raw(list, index)] then
                for offset = index, size - 1 do set(list, offset, raw(list, offset + 1)) end
                set(list, size, nil); size = size - 1
            end
        end
        if removedCurrent then set(queue, "current", raw(list, 1)) end
        return true, removedCurrent
    end
end

-- Structural private-ledger fact only. Native admission, effects, capacity and
-- edit permission belong to the caller; missing history never means no debt.
local nativePlanReads = {kind=type, meta=getmetatable, raw=rawget, pairs=pairs, call=pcall,
    equal=rawequal, count=select, globals=_G,
    queueFields={'toolkitCancel','toolkitGroupCancel','toolkitResume','toolkitOutcomeWait','toolkitStopIntent','toolkitOperationsInvalid'},
    actionFields={'toolkitQueueReturn','toolkitQueueLinked','toolkitQueueContinuation','_isAddingActions',
        'onStartFunc','onCompleteFunc','onCancelFunc','onFailFunc','retriggerLastAction'},
    stepFields={'required','receipt','returning','preparation','prerequisites','borrowing','item','kind','device'}}
-- Own-slot reads remain safe for inherited native classes: Kahlua rawget
-- follows metatables, so only a plain owner takes the direct path.
local function nativePlanOwn(owner,key)
    local api=nativePlanReads
    if api.kind(owner)~='table'then return end
    if api.meta(owner)==nil then return api.raw(owner,key)end
    for name,value in api.pairs(owner)do if api.equal(name,key)then return value end end
end
local function nativePlanPlain(value)
    return nativePlanReads.kind(value)=='table'and nativePlanReads.meta(value)==nil
end
local function nativePlanPublic()
    local api=nativePlanReads
    return nativePlanPlain(api.globals)and nativePlanPlain(Toolkit)and nativePlanPlain(Settlement)and nativePlanPlain(executionProof)
        and api.equal(api.raw(api.globals,'PZSurvivorToolkit'),Toolkit)
        and api.equal(api.raw(Toolkit,'ActionQueueSettlement'),Settlement)
        and api.equal(api.raw(executionProof,'closure'),editLedgerOrigin)and api.kind(editLedgerOrigin)=='function'
end
-- Decision-local own-data mirrors. Checking a mirror never opens a seal or
-- invokes source metadata, actor/settings getters, providers or native actions.
local function nativePlanMirror()
    local api,records,byOwner=nativePlanReads,{},{}
    local function capture(owner,keys)
        if api.kind(owner)~='table'then return false end
        local previous=byOwner[owner]
        if previous then
            if not api.equal(api.meta(owner),previous.meta)then return false end
            if not previous.keys then return true end
            -- Never renew an earlier selected observation when another role
            -- needs more fields of the same table.
            for _,key in api.pairs(previous.keys)do
                if not api.equal(nativePlanOwn(owner,key),api.raw(previous.values,key))then return false end
            end
            if keys then
                for _,key in api.pairs(keys)do
                    if not previous.selected[key]then
                        previous.selected[key]=true;previous.keys[#previous.keys+1]=key
                        previous.values[key]=nativePlanOwn(owner,key)
                    end
                end
            else
                for key,value in api.pairs(owner)do
                    if not previous.selected[key]then previous.values[key]=value end
                    previous.count=previous.count+1
                end
                previous.keys=nil
            end
            return true
        end
        local values,count={},0
        local selected,fields
        if keys then
            selected,fields={},{}
            for _,key in api.pairs(keys)do
                selected[key]=true;fields[#fields+1]=key;values[key]=nativePlanOwn(owner,key)
            end
        else
            for key,value in api.pairs(owner)do values[key]=value;count=count+1 end
        end
        local record={owner=owner,meta=api.meta(owner),values=values,count=count,keys=fields,selected=selected}
        records[#records+1]=record;byOwner[owner]=record
        return true
    end
    local function unchanged()
        for _,record in api.pairs(records)do
            local owner=record.owner
            if not api.equal(api.meta(owner),record.meta)then return false end
            if record.keys then
                for _,key in api.pairs(record.keys)do
                    if not api.equal(nativePlanOwn(owner,key),api.raw(record.values,key))then return false end
                end
            else
                local count=0
                for key,value in api.pairs(owner)do
                    count=count+1
                    if not api.equal(value,api.raw(record.values,key))then return false end
                end
                if count~=record.count then return false end
            end
        end
        return true
    end
    return capture,unchanged
end
local function nativePlanContext(queue,action)
    local api=nativePlanReads
    if not nativePlanPublic()or api.kind(queue)~='table'then return end
    local state={queue=queue,actor=nativePlanOwn(queue,'character'),list=nativePlanOwn(queue,'queue'),
        front=nativePlanOwn(queue,'current'),generation=nativePlanOwn(queue,'toolkitOperationGeneration')or 0}
    if state.actor==nil or not nativePlanPlain(state.list)or api.kind(state.generation)~='number'
        or state.generation~=state.generation or state.generation%1~=0 then return end
    if action~=nil then
        if api.kind(action)~='table'or not api.equal(nativePlanOwn(action,'character'),state.actor)then return end
        state.action,state.token=action,nativePlanOwn(action,'toolkitQueueOperation')
        if not nativePlanPlain(state.token)then return end
    end
    return state
end
-- A descriptor only selects a private-ledger shape. Native item/container and
-- source-owned approach/equip contracts remain the caller's responsibility.
local function nativePlanGroups(groups)
    if groups==nil then return {}end
    local api=nativePlanReads
    if not nativePlanPlain(groups)then return end
    local selected,members,count={},{},0
    for token,group in api.pairs(groups)do
        count=count+1
        if count>32 or not nativePlanPlain(token)or not nativePlanPlain(group)then return end
        local allowed={approach=true,fetch=true,body=true,source=true,destination=true,item=true}
        local fields=0
        for key in api.pairs(group)do if not allowed[key]then return end;fields=fields+1 end
        if fields~=6 or group.source==nil or group.destination==nil or group.item==nil
            or api.equal(group.source,group.destination)then return end
        for _,name in api.pairs({'approach','fetch','body'})do
            local action=api.raw(group,name)
            if api.kind(action)~='table'or members[action]then return end
            members[action]=true
        end
        selected[token]=group
    end
    return selected
end
-- One shared dense-list/alias parser. Opted-in tokens must be exact contiguous
-- triplets; all other cohort tokens retain the singleton rule.
local function nativePlanRows(state,cohort,groups)
    local api,list=nativePlanReads,state.list
    local count,found,length=0,0,#list
    if cohort and(length<1 or length>32)then return end
    local rows,actions,tokens,selected
    if cohort then rows,actions,tokens={},{},{}end
    if cohort then selected=nativePlanGroups(groups);if not selected then return end end
    for index,member in api.pairs(list)do
        count=count+1
        if api.kind(index)~='number'or index%1~=0 or index<1 or index>length
            or api.kind(member)~='table'then return end
        if cohort then
            local token=nativePlanOwn(member,'toolkitQueueOperation')
            if actions[member]or not nativePlanPlain(token)
                or not api.equal(nativePlanOwn(member,'character'),state.actor)then return end
            actions[member]=true
            tokens[token]=tokens[token]or{}
            tokens[token][#tokens[token]+1]=index
            rows[index]={action=member,token=token,allowActive=index==1}
        elseif api.equal(member,state.action)then found=found+1
        elseif api.equal(nativePlanOwn(member,'toolkitQueueOperation'),state.token)then return end
    end
    if count~=length or not cohort and found~=1 then return end
    if cohort then
        for token,positions in api.pairs(tokens)do
            local group=selected[token]
            if group then
                if #positions~=3 then return end
                -- pairs(list) has no order guarantee.
                local first
                for _,index in api.pairs(positions)do if not first or index<first then first=index end end
                if not rows[first+2]or not api.equal(rows[first].action,group.approach)
                    or not api.equal(rows[first+1].action,group.fetch)or not api.equal(rows[first+2].action,group.body)
                    or not api.equal(rows[first+1].token,token)or not api.equal(rows[first+2].token,token)then return end
                rows[first].group=group;rows[first+1].groupChild=true;rows[first+2].groupChild=true
            elseif #positions~=1 then return end
        end
        for token in api.pairs(selected)do if not tokens[token]then return end end
        state.groups=selected
    end
    return rows or true
end
local function nativePlanCommon(state,removed)
    local api,queue=nativePlanReads,state.queue
    local registry=api.raw(api.globals,'ISTimedActionQueue')
    local queues=nativePlanOwn(registry,'queues')
    if not nativePlanPublic()or not nativePlanPlain(queues)or not api.equal(api.raw(queues,state.actor),queue)
        or not api.equal(nativePlanOwn(queue,'character'),state.actor)
        or not api.equal(nativePlanOwn(queue,'queue'),state.list)or not api.equal(nativePlanOwn(queue,'current'),state.front)
        or not api.equal(api.raw(state.list,1),state.front)and not(removed and(state.front==nil or removed[state.front]))
        or(nativePlanOwn(queue,'toolkitOperationGeneration')or 0)~=state.generation or cancellations[queue]then return false end
    for _,name in api.pairs(api.queueFields)do if nativePlanOwn(queue,name)then return false end end
    return true
end
local function nativePlanCapture(state,rows,groups)
    local api=nativePlanReads
    local capture,unchanged=nativePlanMirror()
    -- All external observations precede the first source metadata callback.
    capture(state.queue);capture(state.list)
    capture(api.globals,{'PZSurvivorToolkit','ISTimedActionQueue'})
    capture(Toolkit,{'ActionQueueSettlement'})
    capture(Settlement,{'nativePlanSingleton','nativePlanLease','nativePlanCohort'})
    capture(executionProof,{'closure'});capture(cancellations,{state.queue})
    local registry=api.raw(api.globals,'ISTimedActionQueue')
    local queues=nativePlanOwn(registry,'queues')
    if not nativePlanPlain(queues)then return end
    capture(registry,{'queues'});capture(queues,{state.actor})
    if rows then
        if groups~=nil and not capture(groups)then return end
        for _,group in api.pairs(state.groups)do if not capture(group)then return end end
        for index=1,#rows do capture(rows[index].action);capture(rows[index].token)end
    else
        capture(state.action);capture(state.token)
        for _,member in api.pairs(state.list)do
            if api.kind(member)~='table'then return end
            if not api.equal(member,state.action)then capture(member,{'toolkitQueueOperation','character'})end
        end
    end
    return capture,unchanged
end
local function nativePlanData(value,capture,maximum)
    if not nativePlanPlain(value)then return false end
    local count=0
    for _ in nativePlanReads.pairs(value)do count=count+1;if count>(maximum or 128)then return false end end
    return not capture or capture(value)
end
local function nativePlanOnly(value,allowed)
    for key in nativePlanReads.pairs(value)do if not allowed[key]then return false end end
    return true
end
local function nativePlanRecordCapture(record,capture)
    if not capture then return true end
    if not nativePlanData(record,capture)then return false end
    local api=nativePlanReads
    for _,name in api.pairs({'steps','actions','borrowings'})do
        if not nativePlanData(api.raw(record,name),capture,32)then return false end
    end
    for _,step in api.pairs(api.raw(record,'steps'))do
        if not nativePlanData(step,capture)or not nativePlanData(api.raw(step,'handle'),capture)then return false end
    end
    return true
end
local function nativePlanPending(state,record,token,action,allowActive,step)
    local api=nativePlanReads
    if api.raw(step,'started')then
        return allowActive==true and api.raw(step,'started')==true
            and api.raw(record,'phase')=='body'and api.raw(token,'toolkitStarted')==true
            and api.equal(state.front,action)and api.equal(api.raw(state.list,1),action)and nativePlanOwn(action,'action')~=nil
    end
    local transaction=nativePlanOwn(action,'transactionId')
    return api.raw(record,'phase')=='prepare'and not api.raw(token,'toolkitStarted')
        and not nativePlanOwn(action,'action')and not nativePlanOwn(action,'started')
        and nativePlanOwn(action,'toolkitNativeTransaction')==nil and nativePlanOwn(action,'toolkitNativeKind')==nil
        and(transaction==nil or transaction==0)
end
-- Inspect only sealed private data. In particular no item/container lookup is
-- used here: the caller separately proves the native descriptor after capture.
local function nativePlanCandidate(record,token,group,candidate,capture,observed)
    local api=nativePlanReads
    if not nativePlanData(candidate,capture)
        or not nativePlanOnly(candidate,{id=true,fullType=true,source=true,destination=true,owner=true,
            phase=true,sourceOwner=true,step=true,ambiguous=true})
        or api.raw(candidate,'phase')~='prepare'or api.raw(candidate,'ambiguous')
        or not api.equal(api.raw(candidate,'owner'),token)or not api.equal(api.raw(candidate,'source'),group.source)
        or not api.equal(api.raw(candidate,'destination'),group.destination)
        or not api.equal(api.raw(candidate,'step'),api.raw(record.actions,group.fetch))then return end
    local id,fullType=api.raw(candidate,'id'),api.raw(candidate,'fullType')
    local owner=api.raw(candidate,'sourceOwner')
    if api.kind(id)~='number'or id%1~=0 or api.kind(fullType)~='string'or fullType==''
        or not nativePlanData(owner,capture)or not nativePlanOnly(owner,{id=true,fullType=true})
        or api.kind(api.raw(owner,'id'))~='number'or api.raw(owner,'id')%1~=0
        or api.kind(api.raw(owner,'fullType'))~='string'or api.raw(owner,'fullType')==''then return end
    if observed then
        if observed.id==id and observed.fullType==fullType and observed.sourceOwner.id==api.raw(owner,'id')
            and observed.sourceOwner.fullType==api.raw(owner,'fullType')then return observed end
        return
    end
    return {hasBorrowing=true,id=id,fullType=fullType,
        sourceOwner={id=api.raw(owner,'id'),fullType=api.raw(owner,'fullType')}}
end
local function nativePlanClaim(tasks,equipment,seen,token,group,facts)
    local api=nativePlanReads
    local equipmentReaders={}
    for taskToken,task in api.pairs(tasks)do
        local pickup=api.raw(task.pickups,facts.id)
        if pickup and(api.raw(pickup,'ambiguous')or api.raw(pickup,'fullType')~=facts.fullType
            or not api.equal(api.raw(pickup,'container'),group.source)or not api.equal(taskToken,token))then return false end
        if not api.equal(taskToken,token)then
            if api.raw(task,'unknownInputs')or api.raw(task.items,facts.id)then return false end
            if api.raw(task,'readsEquipment')and api.raw(equipment,facts.id)then equipmentReaders[taskToken]=true end
        end
    end
    local task=api.raw(tasks,token)
    -- Pending implicit hand use is reported, not exclusive cleanup ownership.
    -- The caller must qualify every reported token as an untouched Equip write
    -- in this same cohort. Direct item/unknown claims above remain a denial.
    facts.equipmentReaders=equipmentReaders
    return task~=nil and api.raw(task.pickups,facts.id)~=nil and api.raw(seen,group.fetch)
        and api.raw(task.actions,group.approach)and api.raw(task.actions,group.fetch)and api.raw(task.actions,group.body)
end
local function nativePlanBorrowing(state,record,token,group,binding,capture)
    local api=nativePlanReads
    if not nativePlanData(binding,capture)or not nativePlanOnly(binding,{scope=true,candidate=true})then return end
    local scope,candidate=api.raw(binding,'scope'),api.raw(binding,'candidate')
    local parsed=state.scopes[scope]
    if parsed and not parsed[candidate]then return end
    local facts=nativePlanCandidate(record,token,group,candidate,capture,parsed and parsed[candidate])
    if not facts then return end
    -- Each real operation still opens its own seal. A shared producer scope
    -- only needs one source/ledger parse in this decision; reuse the original
    -- copied facts, never a fresh observation of already captured owners.
    if parsed then return parsed[candidate]end
    if not nativePlanData(scope,capture)
        or not nativePlanOnly(scope,{marker=true,character=true,token=true,queue=true,generation=true,tasks=true,
            equipmentItems=true,seen=true,mixed=true,phase=true,idleTicks=true,restoreToken=true,restored=true,[borrowingMarker]=true})
        or not api.equal(api.raw(scope,'marker'),deferredMarker)
        or(api.raw(scope,'phase')~='prepare'and api.raw(scope,'phase')~='cleanup')
        or not api.equal(api.raw(scope,'character'),state.actor)or not api.equal(api.raw(scope,'queue'),state.queue)
        or api.raw(scope,'generation')~=state.generation or not nativePlanPlain(api.raw(scope,'token'))
        or(api.raw(scope,'restored')~=nil and api.raw(scope,'restored')~=false)then return end
    local idle,restore=api.raw(scope,'idleTicks'),api.raw(scope,'restoreToken')
    if idle~=nil and(api.kind(idle)~='number'or idle<0 or idle%1~=0)
        or restore~=nil and not nativePlanData(restore,capture,0)then return end
    local tasks,seen,equipment=api.raw(scope,'tasks'),api.raw(scope,'seen'),api.raw(scope,'equipmentItems')
    if not nativePlanData(tasks,capture,32)or not nativePlanData(seen,capture)or not nativePlanData(equipment,capture)then return end
    for taskToken,task in api.pairs(tasks)do
        if not nativePlanPlain(taskToken)or not nativePlanData(task,capture)
            or not nativePlanOnly(task,{items=true,pickups=true,actions=true,unknownInputs=true,readsEquipment=true})then return end
        local items,pickups,actions=api.raw(task,'items'),api.raw(task,'pickups'),api.raw(task,'actions')
        if not nativePlanData(items,capture)or not nativePlanData(pickups,capture)or not nativePlanData(actions,capture)then return end
        for _,pickup in api.pairs(pickups)do
            if not nativePlanData(pickup,capture)or not nativePlanOnly(pickup,{container=true,fullType=true,ambiguous=true})then return end
        end
    end
    -- The mutable scope/task snapshot precedes its native filename callback.
    local seal=api.raw(scope,borrowingMarker)
    if not settlementSealTrusted(scope,borrowingMarker,seal)or not nativePlanPublic()or not state.unchanged()then return end
    local opened,ledger=api.call(seal,scope)
    if not opened or not nativePlanData(ledger,capture)
        or not nativePlanOnly(ledger,{candidates=true,actions=true,handles=true,executors=true,merging=true})then return end
    for _,name in api.pairs({'candidates','actions','handles','executors','merging'})do
        if not nativePlanData(api.raw(ledger,name),capture,32)then return end
    end
    for _ in api.pairs(ledger.handles)do return end
    for _ in api.pairs(ledger.merging)do return end
    local count,found,mapped,candidateFacts=0,false,{},{}
    for index,entry in api.pairs(ledger.candidates)do
        count=count+1
        if api.kind(index)~='number'or index%1~=0 or index<1 or index>#ledger.candidates
            or not nativePlanData(entry,capture)or api.raw(entry,'phase')~='prepare'or api.raw(entry,'ambiguous')then return end
        local step=api.raw(entry,'step')
        if not nativePlanData(step,capture)or not nativePlanRecordCapture(api.raw(step,'operation'),capture)then return end
        local action=api.raw(step,'action')
        local selected=state.groups[api.raw(entry,'owner')]
        local entryBinding=api.raw(step,'borrowing')
        if not selected or not api.equal(selected.fetch,action)or mapped[action]
            or not nativePlanData(entryBinding,capture)or not api.equal(api.raw(entryBinding,'scope'),scope)
            or not api.equal(api.raw(entryBinding,'candidate'),entry)
            or not api.equal(api.raw(ledger.actions,action),entry)then return end
        local entryFacts=nativePlanCandidate(api.raw(step,'operation'),api.raw(entry,'owner'),selected,entry,capture,
            api.equal(entry,candidate)and facts or nil)
        if not entryFacts or not nativePlanClaim(tasks,equipment,seen,api.raw(entry,'owner'),selected,entryFacts)then return end
        local executors=api.raw(ledger.executors,action)
        if not nativePlanData(executors,capture,1)or not api.equal(api.raw(executors,api.raw(entry,'id')),entry)then return end
        mapped[action]=true
        candidateFacts[entry]=api.equal(entry,candidate)and facts or entryFacts
        if api.equal(entry,candidate)then found=true end
    end
    if count~=#ledger.candidates or not found then return end
    local actions,executors=0,0
    for action in api.pairs(ledger.actions)do if not mapped[action]then return end;actions=actions+1 end
    for action in api.pairs(ledger.executors)do if not mapped[action]then return end;executors=executors+1 end
    if actions~=count or executors~=count then return end
    state.scopes[scope]=candidateFacts
    return candidateFacts[candidate]
end
-- The same private-record parser serves standalone and cohort observations.
-- Capture each real record before metadata for another token can mutate it.
local function nativePlanRecord(state,action,token,allowActive,capture,group)
    local api=nativePlanReads
    if not nativePlanPlain(token)or api.kind(action)~='table'then return false end
    local seal=api.raw(token,operationMarker)
    if not operationSealTrusted(token,seal)or not nativePlanPublic()then return false end
    local opened,record=api.call(seal,token)
    if not opened or not nativePlanPlain(record)or not nativePlanPublic()
        or not api.equal(nativePlanOwn(action,'character'),state.actor)
        or not api.equal(nativePlanOwn(action,'toolkitQueueOperation'),token)
        or not api.equal(api.raw(record,'character'),state.actor)or not api.equal(api.raw(record,'queue'),state.queue)
        or not api.equal(api.raw(record,'token'),token)or api.raw(record,'generation')~=state.generation
        or api.raw(record,'preparationScope')~=nil or api.raw(record,'settlement')~=nil then return false end
    if api.raw(token,'toolkitCancelled')or not group and api.raw(token,'toolkitPickups')~=nil
        or api.raw(token,'toolkitContinuations')~=nil and api.raw(token,'toolkitContinuations')~=0 then return false end
    for _,name in api.pairs(api.actionFields)do if nativePlanOwn(action,name)then return false end end
    local steps,actions,borrowings=api.raw(record,'steps'),api.raw(record,'actions'),api.raw(record,'borrowings')
    if not nativePlanPlain(steps)or not nativePlanPlain(actions)or not nativePlanPlain(borrowings)then return false end
    if group then
        if api.raw(record,'phase')~='prepare'or api.raw(token,'toolkitStarted')then return false end
        local hints=api.raw(token,'toolkitPickups')
        if not nativePlanData(hints,capture,1)or not api.equal(api.raw(hints,group.item),group.source)
            or not api.equal(nativePlanOwn(group.fetch,'item'),group.item)
            or not api.equal(nativePlanOwn(group.body,'item'),group.item)
            or not api.equal(nativePlanOwn(group.fetch,'srcContainer'),group.source)
            or not api.equal(nativePlanOwn(group.fetch,'destContainer'),group.destination)then return false end
        local members={group.approach,group.fetch,group.body}
        local count=0
        for key in api.pairs(steps)do count=count+1;if key~=1 and key~=2 and key~=3 then return false end end
        if count~=3 then return false end
        count=0
        for member in api.pairs(actions)do
            count=count+1
            if not api.equal(member,group.approach)and not api.equal(member,group.fetch)and not api.equal(member,group.body)then return false end
        end
        if count~=3 or not nativePlanRecordCapture(record,capture)then return false end
        local binding=api.raw(borrowings,1)
        for key in api.pairs(borrowings)do if key~=1 then return false end end
        for index,member in api.pairs(members)do
            local step=api.raw(steps,index)
            if not nativePlanPlain(step)or not api.equal(api.raw(actions,member),step)
                or not api.equal(api.raw(step,'operation'),record)or not api.equal(api.raw(step,'action'),member)
                or api.raw(step,'state')~='pending'or api.raw(step,'started')
                or not nativePlanPending(state,record,token,member,false,step)then return false end
            for _,name in api.pairs(api.actionFields)do if nativePlanOwn(member,name)then return false end end
            for _,name in api.pairs(api.stepFields)do
                if name~='borrowing'and api.raw(step,name)~=nil then return false end
            end
            if index==2 then
                if api.raw(step,'phase')~=(binding and 'prepare'or 'body')
                    or not api.equal(api.raw(step,'borrowing'),binding)then return false end
            elseif api.raw(step,'phase')~='body'or api.raw(step,'borrowing')~=nil then return false end
        end
        local facts
        if binding then facts=nativePlanBorrowing(state,record,token,group,binding,capture)
        else facts={hasBorrowing=false}end
        return facts~=nil and facts~=false,facts
    end
    for _ in api.pairs(borrowings)do return false end
    local step=api.raw(steps,1)
    if not nativePlanPlain(step)or not api.equal(api.raw(actions,action),step)then return false end
    for key in api.pairs(steps)do if key~=1 then return false end end
    for key in api.pairs(actions)do if not api.equal(key,action)then return false end end
    if not api.equal(api.raw(step,'operation'),record)or not api.equal(api.raw(step,'action'),action)
        or api.raw(step,'phase')~='body'or api.raw(step,'state')~='pending'then return false end
    for _,name in api.pairs(api.stepFields)do if api.raw(step,name)~=nil then return false end end
    return nativePlanPending(state,record,token,action,allowActive,step)and nativePlanRecordCapture(record,capture)
end
local function nativePlanValidate(lease,...)
    local api=nativePlanReads
    local arity=api.count('#',...)
    if arity<2 or arity>3 then return false end
    local queue,action,allowActive=...
    if allowActive~=nil and allowActive~=false and allowActive~=true then return false end
    local state=nativePlanContext(queue,action)
    if not state or api.kind(action)~='table'then return false end
    local capture,unchanged
    if lease then
        capture,unchanged=nativePlanCapture(state)
        if not capture then return false end
    end
    if not nativePlanRecord(state,action,state.token,allowActive,capture)
        or not nativePlanCommon(state)or not nativePlanRows(state,false)then return false end
    if not lease then return true end
    if unchanged()then return unchanged end
    return false
end
function Settlement.nativePlanSingleton(...)
    return nativePlanValidate(false,...)==true
end
function Settlement.nativePlanLease(...)
    local check=nativePlanValidate(true,...)
    if nativePlanReads.kind(check)=='function'then return check end
end
function Settlement.nativePlanCohort(...)
    local arity=nativePlanReads.count('#',...)
    if arity~=1 and arity~=2 then return end
    local queue,groups=...
    local state=nativePlanContext(queue)
    if not state then return end
    local rows=nativePlanRows(state,true,groups)
    if not rows then return end
    local capture,unchanged=nativePlanCapture(state,rows,groups)
    if not capture then return end
    state.scopes,state.unchanged={},unchanged
    local inputFacts={}
    for index=1,#rows do
        local row=rows[index]
        if not row.groupChild then
            local valid,facts=nativePlanRecord(state,row.action,row.token,row.allowActive,capture,row.group)
            if not valid then return end
            if row.group then
                inputFacts[row.token]=facts
                capture(facts)
                if facts.sourceOwner then capture(facts.sourceOwner)end
                if facts.equipmentReaders then capture(facts.equipmentReaders)end
            end
        end
    end
    capture(inputFacts)
    if nativePlanCommon(state)and unchanged()then return unchanged,inputFacts end
end

-- Queue calls this only after removing its validated whole operation and
-- invalidating the token. No native effect was admitted, so there is nothing
-- to complete or return; retain the historical claim as an explicit waiver.
function Settlement.discardUnstartedPickups(queue,token,members)
    local api=nativePlanReads
    local state=nativePlanContext(queue)
    if not state or not nativePlanPlain(token)or api.raw(token,'toolkitCancelled')~=true
        or api.raw(token,'toolkitStarted')or api.raw(token,'toolkitContinuations')~=nil
            and api.raw(token,'toolkitContinuations')~=0
        or not nativePlanPlain(members)or #members<1 or #members>32 then return false end
    local selected,count={},0
    for index,action in api.pairs(members)do
        count=count+1
        if api.kind(index)~='number'or index%1~=0 or index<1 or index>#members
            or api.kind(action)~='table'or selected[action]
            or not api.equal(nativePlanOwn(action,'character'),state.actor)
            or not api.equal(nativePlanOwn(action,'toolkitQueueOperation'),token)then return false end
        selected[action]=true
    end
    if count~=#members then return false end
    for _,action in api.pairs(state.list)do
        if selected[action]or api.equal(nativePlanOwn(action,'toolkitQueueOperation'),token)then return false end
    end
    state.action,state.token=api.raw(members,1),token
    local capture,unchanged=nativePlanCapture(state)
    if not capture or not capture(members)or not capture(Settlement,{'discardUnstartedPickups'})then return false end
    for action in api.pairs(selected)do capture(action)end
    local seal=api.raw(token,operationMarker)
    if not operationSealTrusted(token,seal)or not nativePlanPublic()then return false end
    local opened,record=api.call(seal,token)
    if not opened or not nativePlanPlain(record)or not api.equal(api.raw(record,'character'),state.actor)
        or not api.equal(api.raw(record,'queue'),queue)or not api.equal(api.raw(record,'token'),token)
        or api.raw(record,'generation')~=state.generation or api.raw(record,'phase')~='prepare'
        or api.raw(record,'preparationScope')~=nil or api.raw(record,'settlement')~=nil
        or not nativePlanRecordCapture(record,capture)then return false end
    local steps,actions,borrowings=record.steps,record.actions,record.borrowings
    local seen,bindings={},{}
    count=0
    for index,step in api.pairs(steps)do
        count=count+1
        if api.kind(index)~='number'or index%1~=0 or index<1 or index>#members
            or not nativePlanPlain(step)then return false end
        local action=api.raw(step,'action')
        if not selected[action]or seen[action]or not api.equal(api.raw(actions,action),step)
            or not api.equal(api.raw(step,'operation'),record)or api.raw(step,'state')~='pending'
            or(api.raw(step,'phase')~='body'and api.raw(step,'phase')~='prepare')or api.raw(step,'started')then return false end
        seen[action]=true
        local transaction=nativePlanOwn(action,'transactionId')
        if nativePlanOwn(action,'action')or nativePlanOwn(action,'started')
            or nativePlanOwn(action,'toolkitNativeTransaction')~=nil or nativePlanOwn(action,'toolkitNativeKind')~=nil
            or transaction~=nil and transaction~=0 then return false end
        for _,name in api.pairs(api.actionFields)do if nativePlanOwn(action,name)then return false end end
        for _,name in api.pairs(api.stepFields)do if name~='borrowing'and api.raw(step,name)~=nil then return false end end
        local binding=api.raw(step,'borrowing')
        if binding~=nil then if bindings[binding]then return false end;bindings[binding]=step end
    end
    if count~=#members then return false end
    count=0
    for action in api.pairs(actions)do if not seen[action]then return false end;count=count+1 end
    if count~=#members then return false end
    local candidates,covered,releases={},{},{}
    count=0
    for index,binding in api.pairs(borrowings)do
        count=count+1
        if api.kind(index)~='number'or index%1~=0 or index<1 or index>#borrowings
            or not nativePlanData(binding,capture)or not nativePlanOnly(binding,{scope=true,candidate=true})then return false end
        local step=bindings[binding]
        local scope,candidate=api.raw(binding,'scope'),api.raw(binding,'candidate')
        if not step or step.phase~='prepare'or not nativePlanData(scope,capture)
            or not nativePlanData(candidate,capture)or candidates[candidate]
            or not nativePlanOnly(candidate,{id=true,fullType=true,source=true,destination=true,owner=true,
                phase=true,sourceOwner=true,step=true,ambiguous=true})
            or candidate.phase~='prepare'or candidate.ambiguous or not api.equal(candidate.owner,token)
            or not api.equal(candidate.step,step)or candidate.source==nil or candidate.destination==nil
            or api.equal(candidate.source,candidate.destination)or api.kind(candidate.id)~='number'or candidate.id%1~=0
            or api.kind(candidate.fullType)~='string'or candidate.fullType==''
            or not api.equal(api.raw(scope,'marker'),deferredMarker)or not api.equal(scope.character,state.actor)
            or not api.equal(scope.queue,queue)or scope.generation~=state.generation
            or(scope.phase~='prepare'and scope.phase~='cleanup')then return false end
        if candidate.sourceOwner~=nil and(not nativePlanData(candidate.sourceOwner,capture)
            or not nativePlanOnly(candidate.sourceOwner,{id=true,fullType=true})
            or api.kind(candidate.sourceOwner.id)~='number'or candidate.sourceOwner.id%1~=0
            or api.kind(candidate.sourceOwner.fullType)~='string'or candidate.sourceOwner.fullType=='')then return false end
        local fetch=step.action
        if not api.equal(nativePlanOwn(fetch,'srcContainer'),candidate.source)
            or not api.equal(nativePlanOwn(fetch,'destContainer'),candidate.destination)then return false end
        local hint=nativePlanOwn(fetch,'item')
        if hint==nil or covered[hint]then return false end
        covered[hint]=candidate.source
        local release=releases[scope]
        if not release then
            local tasks,scopeSeen=api.raw(scope,'tasks'),api.raw(scope,'seen')
            if not nativePlanData(tasks,capture,32)or not nativePlanData(scopeSeen,capture)then return false end
            local task=api.raw(tasks,token)
            if not nativePlanData(task,capture)or task.unknownInputs
                or not nativePlanOnly(task,{items=true,pickups=true,actions=true,unknownInputs=true,readsEquipment=true})
                or not nativePlanData(task.items,capture)or not nativePlanData(task.pickups,capture)
                or not nativePlanData(task.actions,capture,32)then return false end
            local owned=0
            for member,value in api.pairs(task.actions)do
                if value~=true or not selected[member]or api.raw(scopeSeen,member)~=true then return false end
                owned=owned+1
            end
            if owned~=#members then return false end
            -- Another task cannot own an action being removed. Ancestor bag
            -- IDs in task.items are legitimate input facts, not extra actions.
            for otherToken,other in api.pairs(tasks)do
                if not api.equal(otherToken,token)then
                    if api.equal(other,task)or not nativePlanData(other,capture)
                        or not nativePlanData(other.actions,capture)then return false end
                    for member in api.pairs(other.actions)do if selected[member]then return false end end
                end
            end
            local sourceSeal=api.raw(scope,borrowingMarker)
            if not settlementSealTrusted(scope,borrowingMarker,sourceSeal)then return false end
            local valid,ledger=api.call(sourceSeal,scope)
            if not valid or not nativePlanData(ledger,capture)then return false end
            for _,name in api.pairs({'candidates','actions','handles','executors','merging'})do
                if not nativePlanData(api.raw(ledger,name),capture,32)then return false end
            end
            release={scope=scope,tasks=tasks,seen=scopeSeen,task=task,ledger=ledger,ids={}}
            releases[scope]=release
        end
        local ledger=release.ledger
        if not api.equal(api.raw(ledger.actions,fetch),candidate)or api.raw(ledger.handles,fetch)~=nil
            or api.raw(ledger.merging,fetch)~=nil then return false end
        local executors=api.raw(ledger.executors,fetch)
        if not nativePlanData(executors,capture,1)or not api.equal(api.raw(executors,candidate.id),candidate)then return false end
        local occurrences,size=0,0
        for key,entry in api.pairs(ledger.candidates)do
            size=size+1
            if api.kind(key)~='number'or key%1~=0 or key<1 or key>#ledger.candidates or not nativePlanPlain(entry)then return false end
            if api.equal(entry,candidate)then occurrences=occurrences+1 end
        end
        if size~=#ledger.candidates or occurrences~=1 then return false end
        if release.ids[candidate.id]then return false end
        release.ids[candidate.id]=candidate
        candidates[candidate]={scope=scope,fetch=fetch};bindings[binding]=nil
    end
    if count~=#borrowings then return false end
    for _ in api.pairs(bindings)do return false end
    local hints=api.raw(token,'toolkitPickups')
    if hints~=nil then
        if not nativePlanData(hints,capture,32)then return false end
        for item,source in api.pairs(hints)do
            if not api.equal(covered[item],source)and #borrowings>0 then return false end
        end
        for item,source in api.pairs(covered)do if not api.equal(api.raw(hints,item),source)then return false end end
    elseif #borrowings>0 then return false end
    for scope,release in api.pairs(releases)do
        for id,pickup in api.pairs(release.task.pickups)do
            local candidate=release.ids[id]
            if not candidate or not nativePlanData(pickup,capture)
                or not nativePlanOnly(pickup,{container=true,fullType=true,ambiguous=true})or pickup.ambiguous
                or pickup.fullType~=candidate.fullType or not api.equal(pickup.container,candidate.source)then return false end
        end
        for id in api.pairs(release.ids)do if api.raw(release.task.pickups,id)==nil then return false end end
        local ledger=release.ledger
        for _,candidate in api.pairs(ledger.candidates)do
            local owner=candidates[candidate]
            if owner and not api.equal(owner.scope,scope)then return false end
        end
        for fetch,candidate in api.pairs(ledger.actions)do
            local owner=candidates[candidate]
            if owner and(not api.equal(owner.scope,scope)or not api.equal(owner.fetch,fetch))then return false end
        end
        for fetch,executors in api.pairs(ledger.executors)do
            if not nativePlanData(executors,capture,32)then return false end
            for id,candidate in api.pairs(executors)do
                local owner=candidates[candidate]
                if owner and(id~=candidate.id or not api.equal(owner.scope,scope)or not api.equal(owner.fetch,fetch))then return false end
            end
        end
    end
    if not nativePlanCommon(state,selected)or not unchanged()then return false end
    for candidate in api.pairs(candidates)do candidate.phase='waived';candidate.waiverReason='cancelled-before-start'end
    -- Retain the waived candidate in record.borrowings as history, but release
    -- only this never-admitted operation's live producer claims. All writes
    -- below are to the exact plain tables checked above, with no callbacks.
    for scope,release in api.pairs(releases)do
        release.tasks[token]=nil
        for member in api.pairs(selected)do release.seen[member]=nil end
        local ledger=release.ledger
        for candidate,owner in api.pairs(candidates)do
            if api.equal(owner.scope,scope)then ledger.actions[owner.fetch]=nil;ledger.executors[owner.fetch]=nil end
        end
        local write,size=1,#ledger.candidates
        for read=1,size do
            local candidate=api.raw(ledger.candidates,read)
            if not candidates[candidate]then ledger.candidates[write]=candidate;write=write+1 end
        end
        for index=write,size do ledger.candidates[index]=nil end
    end
    return true
end

local explicitEquipmentRole={adler=1153211821,line=145}
local explicitEquipmentMatches=executionProof and executionProof.matches
local retainingExplicitEquipment=false
local function explicitPickupCapture(candidate,capture)
    local api=nativePlanReads
    if not nativePlanData(candidate,capture)then return false end
    for _,name in api.pairs({'sourceOwner','step','proof','member'})do
        local value=api.raw(candidate,name)
        if value~=nil and not nativePlanData(value,capture)then return false end
    end
    local proof=api.raw(candidate,'proof')
    if proof then
        for _,name in api.pairs({'members','byId','attempts','obligation'})do
            if not nativePlanData(api.raw(proof,name),capture,32)then return false end
        end
        for _,member in api.pairs(proof.members)do if not nativePlanData(member,capture)then return false end end
        for _,attempt in api.pairs(proof.attempts)do
            if not nativePlanData(attempt,capture)or not nativePlanData(attempt.members,capture,32)then return false end
        end
    end
    return true
end
local function retainExplicitEquipment(action,receipt)
    local api=nativePlanReads
    if not nativePlanPublic()or api.kind(action)~='table'then return false end
    local actor,token=nativePlanOwn(action,'character'),nativePlanOwn(action,'toolkitQueueOperation')
    if actor==nil or not nativePlanPlain(token)or api.raw(token,'toolkitCancelled')then return false end
    local capture,unchanged=nativePlanMirror()
    capture(action);capture(token)
    capture(api.globals,{'PZSurvivorToolkit','ISTimedActionQueue','getFilenameOfClosure','getFirstLineOfClosure',
        'getModFileReader','getGameFilesInput','getSpecificPlayer','getTimestampMs','isClient'})
    capture(Toolkit,{'ActionQueueSettlement','ActionQueueTidyIntent'})
    capture(Settlement,{'retainExplicitEquipment'})
    capture(executionProof,{'closure','matches'})
    local seal=api.raw(token,operationMarker)
    if not operationSealTrusted(token,seal)or not unchanged()then return false end
    local opened,record=api.call(seal,token)
    if not opened or not nativePlanPlain(record)or not api.equal(record.token,token)or not api.equal(record.character,actor)
        or not nativePlanPlain(record.actions)or not nativePlanPlain(record.borrowings)then return false end
    local step=api.raw(record.actions,action)
    if not nativePlanPlain(step)or not api.equal(step.operation,record)or not api.equal(step.action,action)then return false end
    -- Root equipment pays only its real private membership lookup. This true
    -- means no own loan needs bookkeeping; it grants no effect/edit authority.
    local borrowed=false
    for _ in api.pairs(record.borrowings)do borrowed=true;break end
    if not borrowed then return unchanged()end
    local state=nativePlanContext(record.queue,action)
    if not state or not api.equal(record.queue,state.queue)or record.generation~=state.generation
        or record.settlement~=nil or record.preparationScope~=nil or not nativePlanCommon(state)
        or step.phase~='body'or step.required or step.returning or step.preparation or step.prerequisites~=nil
        or not nativePlanRecordCapture(record,capture)or not capture(state.queue)or not capture(state.list)then return false end
    local registry=api.raw(api.globals,'ISTimedActionQueue');local queues=nativePlanOwn(registry,'queues')
    capture(registry,{'queues'});capture(queues,{actor})
    for _,binding in api.pairs(record.borrowings)do
        if not nativePlanData(binding,capture)or not nativePlanData(binding.scope,capture)
            or not explicitPickupCapture(binding.candidate,capture)then return false end
    end
    if not nativePlanData(receipt,capture)then return false end
    local effectSeal=api.raw(receipt,effectMarker)
    if not settlementSealTrusted(receipt,effectMarker,effectSeal)or not unchanged()then return false end
    local accepted,effect=api.call(effectSeal,receipt)
    if not accepted or not nativePlanData(effect,capture)or effect.confirmed~=true
        or not api.equal(effect.action,action)or not api.equal(effect.native,nativePlanOwn(action,'action'))or effect.native==nil
        or not api.equal(effect.character,actor)or not api.equal(effect.queue,state.queue)or effect.generation~=state.generation
        or effect.transaction~=nativePlanOwn(action,'toolkitNativeTransaction')or effect.kind~=nativePlanOwn(action,'toolkitNativeKind')
        or effect.terminal~=nil and effect.terminal~='completed'then return false end
    local intent=api.raw(Toolkit,'ActionQueueTidyIntent')
    local getter=nativePlanPlain(intent)and api.raw(intent,'confirmedEquipmentIntent')
    local firstLine=api.raw(api.globals,'getFirstLineOfClosure')
    if api.kind(getter)~='function'or api.kind(firstLine)~='function'or api.kind(explicitEquipmentMatches)~='function'
        or not api.equal(api.raw(executionProof,'matches'),explicitEquipmentMatches)then return false end
    capture(intent,{'confirmedEquipmentIntent'})
    if not editLedgerOrigin(getter,'ActionQueueTidyIntent.lua')or not unchanged()then return false end
    local lineOK,line=api.call(firstLine,getter)
    if not lineOK or line~=explicitEquipmentRole.line or not unchanged()then return false end
    local sourceOK,source=api.call(explicitEquipmentMatches,'media/lua/client/PZSurvivorToolkit/ActionQueueTidyIntent.lua',
        explicitEquipmentRole.adler,'PZSurvivorToolkit',true)
    if not sourceOK or source~=true or not unchanged()then return false end
    local intentOK,facts=api.call(getter,action,receipt)
    if not intentOK or not nativePlanData(facts,capture,2)or not nativePlanOnly(facts,{id=true,fullType=true})
        or api.kind(facts.id)~='number'or facts.id%1~=0 or api.kind(facts.fullType)~='string'or facts.fullType==''
        or not unchanged()then return false end
    local requested=nativePlanOwn(action,'item')
    if requested==nil or requested:getID()~=facts.id or requested:getFullType()~=facts.fullType
        or not unchanged()then return false end
    local found,binding
    for _,entry in api.pairs(record.borrowings)do
        local candidate=entry.candidate
        if candidate.id==facts.id and candidate.fullType==facts.fullType then
            if found then return false end
            found,binding=candidate,entry
        end
    end
    if not found then return true end
    if found.phase=='waived'or found.phase=='completed'then return true end
    if found.phase~='prepare'and found.phase~='active'or found.ambiguous or found.returning or found.plannedReturn
        or not api.equal(found.owner,token)or found.proof==nil or found.member==nil then return false end
    local scope,fetch=binding.scope,found.step and found.step.action
    if not nativePlanPlain(found.step)or not api.equal(found.step.operation,record)
        or not api.equal(api.raw(record.actions,fetch),found.step)or not api.equal(found.step.borrowing,binding)
        or not api.equal(scope.marker,deferredMarker)or scope.phase=='retired'or not api.equal(scope.character,actor)
        or not api.equal(scope.queue,state.queue)or scope.generation~=state.generation then return false end
    local scopeSeal=api.raw(scope,borrowingMarker)
    if not settlementSealTrusted(scope,borrowingMarker,scopeSeal)or not unchanged()then return false end
    local scopeOK,ledger=api.call(scopeSeal,scope)
    if not scopeOK or not nativePlanData(ledger,capture)then return false end
    for _,name in api.pairs({'actions','handles','executors','merging','candidates'})do
        if not nativePlanData(api.raw(ledger,name),capture,32)then return false end
    end
    local occurrences=0
    for _,entry in api.pairs(ledger.candidates)do
        if not nativePlanData(entry,capture)then return false end
        if api.equal(entry,found)then occurrences=occurrences+1
        elseif entry.id==facts.id and entry.fullType==facts.fullType and entry.phase~='waived'and entry.phase~='completed'then return false end
    end
    if occurrences~=1 then return false end
    local handle=api.raw(ledger.handles,fetch)
    if not api.equal(api.raw(ledger.actions,fetch),found)or api.raw(ledger.merging,fetch)~=nil
        or not nativePlanData(handle,capture)then return false end
    local pickupSeal=api.raw(handle,returnMarker)
    if not settlementSealTrusted(handle,returnMarker,pickupSeal)or not unchanged()then return false end
    local pickupOK,pickup=api.call(pickupSeal,handle)
    local member,attempt=found.member,found.proof.attempts[1]
    local executors=api.raw(ledger.executors,fetch)
    if not pickupOK or not api.equal(pickup,found.proof)or not nativePlanData(executors,capture,1)
        or not api.equal(api.raw(executors,facts.id),found)or not api.equal(pickup.scope,scope)
        or not api.equal(pickup.token,token)or pickup.direction~='pickup'or not api.equal(pickup.obligation,handle)
        or not api.equal(handle.token,token)or pickup.native==nil
        or not api.equal(pickup.action,fetch)or not api.equal(pickup.native,nativePlanOwn(fetch,'action'))
        or not api.equal(pickup.character,actor)or not api.equal(pickup.queue,state.queue)or pickup.generation~=state.generation
        or not api.equal(pickup.source,found.source)or not api.equal(pickup.destination,found.destination)
        or pickup.invalid or pickup.stopped or pickup.sequenceError or pickup.continuing or pickup.next
        or #pickup.members~=1 or #pickup.attempts~=1 or not nativePlanPlain(attempt)
        or not api.equal(pickup.members[1],member)or not api.equal(pickup.byId[facts.id],member)
        or member.id~=facts.id or member.fullType~=facts.fullType or not api.equal(member.borrowed,found)
        or member.attempt~=1 or #attempt.members~=1 or not api.equal(attempt.members[1],member)
        or not api.equal(pickup.active,attempt)or attempt.ordinal~=1 or attempt.phase~='perform'
        or attempt.invalid
        or attempt.terminal~=nil and attempt.terminal~='waiting'and attempt.terminal~='completed'then return false end
    local authority=pickup.client and'completed'or'native'
    if found.phase=='prepare'or member.completed~=true or attempt.terminal~='completed'or attempt.authority~=authority then
        if attempt.finished and not attempt.succeeded or attempt.authority~=nil and attempt.authority~='unavailable'
            and attempt.authority~=authority or not attempt.deadline or api.kind(getTimestampMs)~='function'
            or getTimestampMs()>=attempt.deadline or not unchanged()then return false end
        return nil -- Existing Compat.poll before Intent.update owns observation/retry.
    end
    if found.step.state~='earned'or not attempt.finished or not attempt.succeeded or not pickup.ended
        or found.attempt~=1 or found.authority~=attempt.authority
        or found.transaction~=(pickup.client and attempt.transaction or 0)then return false end
    local item=nativePlanOwn(action,'item')
    local primary,twoHands=nativePlanOwn(action,'primary'),nativePlanOwn(action,'twoHands')
    if item==nil or(primary~=true and primary~=false)or(twoHands~=true and twoHands~=false)then return false end
    local root=actor:getInventory()
    local held
    if primary then held=actor:getPrimaryHandItem()else held=actor:getSecondaryHandItem()end
    if actor:isDead()or getSpecificPlayer(actor:getPlayerNum())~=actor or isClient()~=pickup.client
        or not api.equal(root,found.destination)or not api.equal(root:getItemById(facts.id),item)
        or item:getID()~=facts.id or item:getFullType()~=facts.fullType or not api.equal(item:getContainer(),root)
        or item:getIsCraftingConsumed()or found.source:getItemById(facts.id)~=nil
        or not api.equal(held,item)
        or twoHands and(not api.equal(actor:getPrimaryHandItem(),item)or not api.equal(actor:getSecondaryHandItem(),item))
        or not api.equal(root:getItemById(facts.id),item)or not unchanged()then return false end
    found.phase='waived';found.waiverReason='explicit-equipment-intent'
    return true
end
function Settlement.retainExplicitEquipment(action,receipt)
    if retainingExplicitEquipment then return false end
    retainingExplicitEquipment=true
    local ok,result=nativePlanReads.call(retainExplicitEquipment,action,receipt)
    retainingExplicitEquipment=false
    if ok then return result end
    return false
end

return Settlement
