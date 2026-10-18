require 'PZSurvivorToolkit/Settings'
require 'TimedActions/ISTimedActionQueue'

local Acknowledgements = {}
PZSurvivorToolkit.ActionQueueAcknowledgements = Acknowledgements
local records = setmetatable({}, {__mode = 'k'})
local seen, pending = {}, {}

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
            if record and record.token == args.token and record.kind == args.kind
                and action.character:getOnlineID() == args.player then
                local character, queue = action.character, record.queue
                if record.state == 'started' and ISTimedActionQueue.queues[character] == queue
                    and getSpecificPlayer(player) == character and not character:isDead()
                    and record.generation == (queue.toolkitOperationGeneration or 0) then record.state = args.state end
                transactions[args.transaction] = nil
                return
            end
        end
        return
    end
    for character, queue in pairs(ISTimedActionQueue.queues) do
        local action = queue.current
        if current(queue, action) and character:getOnlineID() == args.player
            and action.toolkitNativeTransaction == args.transaction and action.toolkitNativeKind == args.kind then
            local record = records[action]
            if record and record.native ~= action.action then records[action], record = nil, nil end
            if args.state == 'started' then
                local player = character:getPlayerNum()
                local previous = seen[player] or {}
                if record or previous[args.transaction] == args.token then return end
                previous[args.transaction], seen[player] = args.token, previous
                records[action] = {queue = queue, native = action.action, generation = queue.toolkitOperationGeneration or 0,
                    token = args.token, transaction = args.transaction, kind = args.kind, state = 'started'}
                pending[player] = pending[player] or {}
                pending[player][args.transaction] = {action = action, record = records[action]}
            end
            return
        end
    end
end

function Acknowledgements.reset(queue)
    for _, transactions in pairs(pending) do
        for id, entry in pairs(transactions) do
            if entry.record.queue == queue then transactions[id] = nil end
        end
    end
end

function Acknowledgements.capture(action)
    local record = records[action]
    if record and current(record.queue, action)
        and record.native == action.action
        and record.generation == (record.queue.toolkitOperationGeneration or 0)
        and record.transaction == action.toolkitNativeTransaction and record.kind == action.toolkitNativeKind then return record end
end

function Acknowledgements.state(action, record)
    if record and Acknowledgements.capture(action) == record then return record.state end
end

Events.OnServerCommand.Add(receive)
return Acknowledgements
