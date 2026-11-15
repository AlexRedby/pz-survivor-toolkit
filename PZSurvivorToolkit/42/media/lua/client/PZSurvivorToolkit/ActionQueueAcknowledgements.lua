require 'PZSurvivorToolkit/Settings'
require 'TimedActions/ISTimedActionQueue'

local Acknowledgements = {}
PZSurvivorToolkit.ActionQueueAcknowledgements = Acknowledgements
local Operations = PZSurvivorToolkit.ActionQueueOperations or require 'PZSurvivorToolkit/ActionQueueOperations'
local invalidateQueue = Operations and Operations.invalidateQueue
-- Only a local slot's current action can capture a receipt. Late terminal
-- observation owns its separate record in pending, without retaining all actions.
local records = {}
local seen, pending = {}, {}
local receiptMarker, queueEpoch = {}, {}
-- Retiring the editor revokes producers, not native work already queued. This
-- private transition receipt grants only native wait/completion, never an edit,
-- a resource projection or permission to reconstruct an optional return.
local editorEpisodes = {}
local editorInvalidating = {}
local function editorEpisode(queue)
    local state = editorEpisodes[queue]
    if not state then return end
    local actor = state.character
    if state.revoked or state.staging or ISTimedActionQueue.queues[actor] ~= queue or queue.character ~= actor
        or queue.queue ~= state.list or (queue.toolkitOperationGeneration or 0) ~= state.generation
        or actor:isDead() or actor:getPlayerNum() ~= state.player or actor:getOnlineID() ~= state.online
        or getSpecificPlayer(state.player) ~= actor then
        if not state.staging then state.revoked = true; editorEpisodes[queue] = nil end
        return
    end
    return state
end
local function editorMember(action, generation)
    local actor = action and action.character
    local queue = actor and ISTimedActionQueue.queues[actor]
    local state = queue and editorEpisode(queue)
    local member = state and state.members[action]
    if member and (action.toolkitQueueOperation ~= member.operation or member.operation.toolkitCancelled ~= true
        or member.allocated and action.action ~= member.allocated) then member.revoked = true end
    return member and not member.revoked and queue.current == action and state.list[1] == action
        and action.toolkitQueueOperation == member.operation and member.operation.toolkitCancelled == true
        and action.action == member.native
        and member.native ~= nil and (generation == nil or generation == member.nativeGeneration)
        and member or nil
end
local function beginEditorInvalidation(queue)
    if not isClient() or not queue or not PZSurvivorToolkit.Settings or PZSurvivorToolkit.Settings.actionQueue() ~= false
        or queue.toolkitOperationsInvalid or not queue.character or not queue.queue
        or ISTimedActionQueue.queues[queue.character] ~= queue or queue.character:isDead()
        or not instanceof(queue.character, 'IsoPlayer') or not queue.character:isLocalPlayer()
        or getSpecificPlayer(queue.character:getPlayerNum()) ~= queue.character then return end
    -- A legitimate later transition may carry only exact surviving members of
    -- its previous valid frame. Nested invalidation has a separate refusal fence.
    local previous = editorEpisodes[queue]
    if previous and editorEpisode(queue) ~= previous then return end
    if previous and not previous.reenabled then previous.revoked = true; editorEpisodes[queue] = nil; return end
    local state = {character = queue.character, player = queue.character:getPlayerNum(), online = queue.character:getOnlineID(),
        list = queue.queue, members = {}, tokens = {}, count = 0,
        generation = (queue.toolkitOperationGeneration or 0) + 1, staging = true}
    editorEpisodes[queue] = state
    local function capture(action)
        if editorEpisodes[queue] ~= state or not state.staging or action.character ~= state.character then return end
        local token = action.toolkitQueueOperation
        if type(token) ~= 'table' or getmetatable(token) ~= nil then return end
        local prior = state.tokens[token]
        if prior == nil then prior = token.toolkitCancelled ~= nil and token.toolkitCancelled ~= false; state.tokens[token] = prior end
        local old = previous and previous.members[action]
        local carried = old and not old.revoked and not old.removed and old.action == action
            and old.operation == token and token.toolkitCancelled == true and old.allocated == action.action
        if old and not carried then return end
        if previous and previous.tokens[token] ~= nil and not carried then return end
        if prior and not carried then return end
        local entry = records[state.character:getPlayerNum()]
        local record = carried and old.receipt or entry and entry.action == action and entry.record
        local member = {action = action, operation = token, allocated = action.action,
            allocationGeneration = carried and old.allocationGeneration or action.action and state.generation - 1 or nil}
        if state.members[action] then state.revoked = true; return end
        state.members[action] = member
        state.count = state.count + 1
        local receiptGeneration = carried and old.nativeGeneration or state.generation - 1
        if record and record.native == action.action and record.generation == receiptGeneration then
            local seal = rawget(record, receiptMarker)
            local captured = type(seal) == 'function' and seal(record)
            if captured and captured.action == action and captured.native == action.action then
                member.native, member.nativeGeneration, member.receipt = action.action, captured.generation, record
                captured.editorState, captured.editorMember = state, member
            end
        end
    end
    local function commit()
        if editorEpisodes[queue] ~= state then return false end
        state.staging = nil
        if not PZSurvivorToolkit.Settings or PZSurvivorToolkit.Settings.actionQueue() ~= false
            or previous and previous.revoked or editorEpisode(queue) ~= state then
            state.revoked = true; editorEpisodes[queue] = nil; return false
        end
        if previous then previous.revoked = true end
        if state.count == 0 then editorEpisodes[queue] = nil end
        return true
    end
    return capture, commit
end
function Acknowledgements.editorEnabled(queue)
    local state = editorEpisodes[queue]
    if state and not state.reenabled and PZSurvivorToolkit.Settings.actionQueue() == true
        and not queue.toolkitOperationsInvalid and editorEpisode(queue) == state then state.reenabled = true end
end
-- The snapshot closure never escapes this source-owned actual invalidation.
-- Public settings/generation writes cannot manufacture or commit its receipt.
function Acknowledgements.invalidateEditor(queue)
    if type(Operations) ~= 'table' or type(invalidateQueue) ~= 'function'
        or PZSurvivorToolkit.ActionQueueOperations ~= Operations or Operations.invalidateQueue ~= invalidateQueue then
        return false
    end
    if editorInvalidating[queue] ~= nil then
        editorInvalidating[queue] = false
        local state = editorEpisodes[queue]
        if state then state.revoked = true; editorEpisodes[queue] = nil end
        invalidateQueue(queue)
        return true
    end
    local attempt = {}
    editorInvalidating[queue] = attempt
    local ok, problem = pcall(function()
        local capture, commit = beginEditorInvalidation(queue)
        if editorInvalidating[queue] ~= attempt then
            local state = editorEpisodes[queue]
            if state then state.revoked = true; editorEpisodes[queue] = nil end
            capture, commit = nil, nil
        end
        invalidateQueue(queue, capture)
        if commit then commit() end
    end)
    editorInvalidating[queue] = nil
    if not ok then
        local state = editorEpisodes[queue]
        if state then state.revoked = true; editorEpisodes[queue] = nil end
        error(problem, 0)
    end
    return true
end
-- Queue calls this only after the original native begin allocated the action.
-- A pending row binds once; replacing an allocated native object never rebinds.
function Acknowledgements.bindEditorNative(action)
    local actor = action and action.character
    local queue = actor and ISTimedActionQueue.queues[actor]
    local state = queue and editorEpisode(queue)
    local member = state and state.members[action]
    if member and not member.allocated and queue.current == action and state.list[1] == action
        and action.toolkitQueueOperation == member.operation and member.operation.toolkitCancelled == true and action.action then
        member.allocated, member.allocationGeneration = action.action, state.generation
    end
end
function Acknowledgements.editorNativeCompletion(action, record)
    local member = editorMember(action)
    return not not (member and member.receipt == record)
end
local function retireEditorMember(queue, action)
    local state = editorEpisode(queue)
    local member = state and state.members[action]
    if member then
        state.members[action] = nil
        state.count = state.count - 1
        member.removed = true
        if not member.receipt then member.revoked = true end
        if state.count == 0 then editorEpisodes[queue] = nil end
    end
end
Acknowledgements.retireEditorMember = retireEditorMember
function Acknowledgements.completeEditorNative(queue, action)
    retireEditorMember(queue, action)
end
local function editorReceiptGeneration(action, captured)
    local state, member = captured.editorState, captured.editorMember
    if state and not state.staging and (ISTimedActionQueue.queues[state.character] ~= captured.queue
        or captured.queue.character ~= state.character or captured.queue.queue ~= state.list
        or (captured.queue.toolkitOperationGeneration or 0) ~= state.generation
        or state.character:isDead() or state.character:getPlayerNum() ~= state.player
        or state.character:getOnlineID() ~= state.online or getSpecificPlayer(state.player) ~= state.character) then
        state.revoked = true
    end
    if member and (action.action ~= member.native or action.toolkitQueueOperation ~= member.operation
        or member.operation.toolkitCancelled ~= true) then member.revoked = true end
    return state and member and not member.revoked and not state.staging and not state.revoked
        and ISTimedActionQueue.queues[state.character] == captured.queue
        and captured.queue.character == state.character and captured.queue.queue == state.list
        and state.character:getPlayerNum() == state.player and state.character:getOnlineID() == state.online
        and getSpecificPlayer(state.player) == state.character
        and (captured.queue.toolkitOperationGeneration or 0) == state.generation
        and member.action == action and action.action == member.native and captured.native == member.native
        and action.toolkitQueueOperation == member.operation and member.operation.toolkitCancelled == true
        and captured.generation == member.nativeGeneration
end

-- The seal belongs to one exact receipt table. Retained receipts carry their own
-- identity; only the queue carries its current epoch, so reset revokes even a
-- completed receipt no longer present in either bounded registry.
local function identity(action, record)
    if type(record) ~= 'table' then return end
    local seal = rawget(record, receiptMarker)
    if type(seal) ~= 'function' then return end
    local captured = seal(record)
    if not captured or captured.action ~= action then return end
    if captured.editorMember and not editorReceiptGeneration(action, captured) then return end
    local character, queue = captured.character, captured.queue
    if action.character == character and action.action == captured.native
        and action.toolkitNativeTransaction == captured.transaction and action.toolkitNativeKind == captured.kind
        and character:getPlayerNum() == captured.player and character:getOnlineID() == captured.online
        and getSpecificPlayer(captured.player) == character and not character:isDead()
        and ISTimedActionQueue.queues[character] == queue and queue[queueEpoch] == captured.epoch
        and ((queue.toolkitOperationGeneration or 0) == captured.generation
            or editorReceiptGeneration(action, captured)
            or PZSurvivorToolkit.ActionQueueSettlement
                and PZSurvivorToolkit.ActionQueueSettlement.cancellationGeneration(action, captured.generation))
        and record.queue == queue and record.native == captured.native and record.generation == captured.generation
        and record.transaction == captured.transaction and record.kind == captured.kind
        and record.token == captured.token and record.state == captured.state then return captured end
end

local function receipt(action, queue, args)
    local character = action.character
    queue[queueEpoch] = queue[queueEpoch] or {}
    local captured = {action = action, character = character, player = character:getPlayerNum(),
        online = character:getOnlineID(), queue = queue, native = action.action,
        generation = queue.toolkitOperationGeneration or 0, epoch = queue[queueEpoch],
        transaction = args.transaction, kind = args.kind, token = args.token, state = 'started',
        settingsOff = PZSurvivorToolkit.Settings ~= nil and PZSurvivorToolkit.Settings.actionQueue() == false,
        operation = action.toolkitQueueOperation,
        operationCanceled = type(action.toolkitQueueOperation) == 'table' and rawget(action.toolkitQueueOperation, 'toolkitCancelled'),
        operationsInvalid = rawget(queue, 'toolkitOperationsInvalid')}
    local record = {queue = queue, native = captured.native, generation = captured.generation,
        token = args.token, transaction = args.transaction, kind = args.kind, state = 'started'}
    record[receiptMarker] = function(candidate) if candidate == record then return captured end end
    local state = editorEpisode(queue)
    local member = state and state.members[action]
    if member and member.allocated == action.action and action.toolkitQueueOperation == member.operation
        and member.operation.toolkitCancelled == true then
        -- Started can arrive after the actual setting transition. Keep its
        -- original issued generation, rather than granting a replacement native.
        member.native, member.nativeGeneration = member.allocated, member.allocationGeneration
        captured.generation, record.generation = member.nativeGeneration, member.nativeGeneration
        captured.editorState, captured.editorMember = state, member
        member.receipt = record
    end
    return record
end

local function current(queue, action)
    local character = action and action.character
    return queue and character and queue.current == action and queue.queue[1] == action
        and ISTimedActionQueue.queues[character] == queue
        and getSpecificPlayer(character:getPlayerNum()) == character and not character:isDead()
end

local function receive(module, command, args)
    if module ~= 'PZSurvivorToolkitActions' or command ~= 'State' or not isClient()
        or type(args) ~= 'table' or args.protocol ~= 1 or type(args.player) ~= 'number'
        or type(args.transaction) ~= 'number' or args.transaction % 1 ~= 0
        or args.transaction < -128 or args.transaction > 127 or args.transaction == 0
        or type(args.kind) ~= 'string' or type(args.token) ~= 'string' or #args.token ~= 36
        or not args.token:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')
        or (args.state ~= 'started' and args.state ~= 'canceled' and args.state ~= 'completed' and args.state ~= 'rejected') then return end
    if args.state ~= 'started' then
        -- Native Done can advance the queue before its following receipt is dispatched.
        for player, transactions in pairs(pending) do
            local entry = transactions[args.transaction]
            local action, record = entry and entry.action, entry and entry.record
            if record and record.token == args.token and record.kind == args.kind then
                local captured = identity(action, record)
                if captured and captured.online == args.player then
                    if captured.state == 'started' then
                        captured.state, record.state = args.state, args.state
                    end
                    transactions[args.transaction] = nil
                    return
                end
            end
        end
        return
    end
    for character, queue in pairs(ISTimedActionQueue.queues) do
        local action = queue.current
        if current(queue, action) and character:getOnlineID() == args.player
            and action.toolkitNativeTransaction == args.transaction and action.toolkitNativeKind == args.kind then
            local player = character:getPlayerNum()
            local entry = records[player]
            local record = entry and entry.action == action and entry.record
            if record and record.native ~= action.action then records[player], record = nil, nil end
            if args.state == 'started' then
                local previous = seen[player] or {}
                if record or previous[args.transaction] == args.token then return end
                previous[args.transaction], seen[player] = args.token, previous
                record = receipt(action, queue, args)
                records[player] = {action = action, record = record}
                pending[player] = pending[player] or {}
                pending[player][args.transaction] = {action = action, record = record}
            end
            return
        end
    end
end

function Acknowledgements.reset(queue)
    if editorEpisodes[queue] then editorEpisodes[queue].revoked = true end
    editorEpisodes[queue] = nil
    if queue then queue[queueEpoch] = {} end
    for player, entry in pairs(records) do
        if entry.record.queue == queue then records[player] = nil end
    end
    for _, transactions in pairs(pending) do
        for id, entry in pairs(transactions) do
            if entry.record.queue == queue then transactions[id] = nil end
        end
    end
end

function Acknowledgements.capture(action)
    local character = action and action.character
    local queue = character and ISTimedActionQueue.queues[character]
    if queue then editorEpisode(queue) end
    local entry = character and records[character:getPlayerNum()]
    local record = entry and entry.action == action and entry.record
    local captured = identity(action, record)
    if captured and current(captured.queue, action) then
        if captured.editorMember and captured.editorMember.removed then return end
        captured.observed = true
        return record
    end
end

function Acknowledgements.state(action, record)
    if record and Acknowledgements.capture(action) == record then return record.state end
end

-- Pin the UI state already present at native Started, so unchanged disabled
-- bookkeeping cannot veto paid native completion. This grants no scheduler
-- ownership or queue edit rights; Lifecycle retains all native stop guards.
local function disabledNativeSettlement(action, record)
    local captured = identity(action, record)
    if not captured or not current(captured.queue, action)
        or not captured.settingsOff or not PZSurvivorToolkit.Settings or PZSurvivorToolkit.Settings.actionQueue() ~= false
        or action.toolkitQueueOperation ~= captured.operation
        or (captured.operation ~= nil and type(captured.operation) ~= 'table')
        or rawget(captured.queue, 'toolkitOperationsInvalid') ~= captured.operationsInvalid then return false end
    local canceled = type(action.toolkitQueueOperation) == 'table' and rawget(action.toolkitQueueOperation, 'toolkitCancelled')
    return canceled == captured.operationCanceled and captured or nil
end
function Acknowledgements.allowsDisabledNativeCompletion(action, record)
    local captured=disabledNativeSettlement(action,record)
    return not not(captured and captured.state=='completed')
end
function Acknowledgements.allowsDisabledNativeCompletionWait(action, record)
    local captured=disabledNativeSettlement(action,record)
    return not not(captured and (captured.state=='started'or captured.state=='completed'))
end

-- A captured receipt can settle after native Done advances the queue. This
-- read-only outcome deliberately does not participate in capture/state rights.
function Acknowledgements.observe(action, record)
    local captured = identity(action, record)
    if captured and captured.observed then return captured.state end
end

Events.OnServerCommand.Add(receive)
if Events.OnMainMenuEnter then
    Events.OnMainMenuEnter.Add(function()
        for _, state in pairs(editorEpisodes) do state.revoked = true end
        editorEpisodes = {}
    end)
end
if Events.OnPlayerDeath then
    Events.OnPlayerDeath.Add(function(actor)
        local queue = ISTimedActionQueue.queues[actor]
        local state = queue and editorEpisodes[queue]
        if state then state.revoked = true; editorEpisodes[queue] = nil end
    end)
end
return Acknowledgements
