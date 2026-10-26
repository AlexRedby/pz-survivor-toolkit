require 'PZSurvivorToolkit/Settings'
require 'TimedActions/ISTimedActionQueue'

local Acknowledgements = {}
PZSurvivorToolkit.ActionQueueAcknowledgements = Acknowledgements
-- Only a local slot's current action can capture a receipt. Late terminal
-- observation owns its separate record in pending, without retaining all actions.
local records = {}
local seen, pending = {}, {}
local receiptMarker, queueEpoch = {}, {}

-- The seal belongs to one exact receipt table. Retained receipts carry their own
-- identity; only the queue carries its current epoch, so reset revokes even a
-- completed receipt no longer present in either bounded registry.
local function identity(action, record)
    if type(record) ~= 'table' then return end
    local seal = rawget(record, receiptMarker)
    if type(seal) ~= 'function' then return end
    local captured = seal(record)
    if not captured or captured.action ~= action then return end
    local character, queue = captured.character, captured.queue
    if action.character == character and action.action == captured.native
        and action.toolkitNativeTransaction == captured.transaction and action.toolkitNativeKind == captured.kind
        and character:getPlayerNum() == captured.player and character:getOnlineID() == captured.online
        and getSpecificPlayer(captured.player) == character and not character:isDead()
        and ISTimedActionQueue.queues[character] == queue and queue[queueEpoch] == captured.epoch
        and ((queue.toolkitOperationGeneration or 0) == captured.generation
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
    local entry = character and records[character:getPlayerNum()]
    local record = entry and entry.action == action and entry.record
    local captured = identity(action, record)
    if captured and current(captured.queue, action) then
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
return Acknowledgements
