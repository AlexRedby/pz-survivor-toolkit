require "PZSurvivorToolkit/Settings"
require "TimedActions/ISTimedActionQueue"
require "TimedActions/ISBaseTimedAction"
require "TimedActions/ISInventoryTransferAction"
require "TimedActions/ISQueueActionsAction"
require "ISUI/ISContextMenu"
require "ISUI/ISButton"
require "ISUI/ISInventoryPaneContextMenu"
require "ISUI/ISInventoryPane"
require "RadioCom/RadioWindowModules/RWMVolume"
local InventoryClasses = require "PZSurvivorToolkit/InventoryClasses"

local Operations = {}
PZSurvivorToolkit.ActionQueueOperations = Operations
local scope
local titleScope
local completionScope
local continuationScope
local continuationMarker = {}
local producers = {}
local commandMarker = {}
local commandLifecycle = {"new", "isValid", "isValidStart", "start", "waitToStart", "update", "stop", "perform", "complete", "forceComplete", "forceStop", "forceCancel"}
local commandClass = ISQueueActionsAction
local commandMethods = {}
for _, name in ipairs(commandLifecycle) do commandMethods[name] = commandClass and commandClass[name] end
local returnClass = ISInventoryTransferAction
local returnMethods = {}
local returnHelperGuards = {}
for _, name in ipairs({"new", "isValid", "isValidStart", "start", "update", "stop", "perform", "complete", "forceStop", "forceCancel"}) do
    returnMethods[name] = returnClass[name]
end

local function nativeReturn(action)
    local carts = PZSurvivorToolkit.ActionQueueCarts
    if carts and carts.isReturn(action) then return true end
    if getmetatable(action) ~= returnClass or action.Type ~= returnClass.Type or not action.allowMissingItems
        or action.srcContainer ~= action.character:getInventory() or action.destContainer == action.srcContainer
        or action.onStartFunc or action.onCancelFunc or action.onCompleteFunc then return false end
    for name, method in pairs(returnMethods) do if action[name] ~= method then return false end end
    for _, guard in ipairs(returnHelperGuards) do if not guard() then return false end end
    return true
end

function Operations.isTransfer(action)
    local carts = PZSurvivorToolkit.ActionQueueCarts
    return action.Type == "ISInventoryTransferAction" or (carts and carts.isTransfer(action))
end

function Operations.adoptReturnHooks(previous, replacement, guard)
    if type(guard) ~= "function" then return false,"missing_guard" end
    local available,reason=guard()
    if not available then return false,reason or "guard_changed" end
    if ISInventoryTransferAction ~= returnClass then return false,"return_class_changed" end
    for _, name in ipairs({"new", "perform"}) do
        if returnMethods[name] ~= previous[name] then return false,"previous_"..name end
        if returnClass[name] ~= replacement[name] then return false,"current_"..name end
        if type(replacement[name]) ~= "function" then return false,"invalid_"..name end
    end
    for _, name in ipairs({"new", "perform"}) do returnMethods[name] = replacement[name] end
    returnHelperGuards[#returnHelperGuards + 1] = guard
    return true
end

function Operations.adoptReturnMethods(previous, replacement, helpersUnchanged)
    if type(previous) ~= "table" or type(replacement) ~= "table" or type(helpersUnchanged) ~= "function"
        or ISInventoryTransferAction ~= returnClass or not helpersUnchanged() then return false end
    for _, name in ipairs({"isValid", "start", "perform", "stop"}) do
        if type(previous[name]) ~= "function" or type(replacement[name]) ~= "function"
            or returnMethods[name] ~= previous[name] or returnClass[name] ~= replacement[name] then return false end
    end
    for _, name in ipairs({"isValid", "start", "perform", "stop"}) do returnMethods[name] = replacement[name] end
    returnHelperGuards[#returnHelperGuards + 1] = helpersUnchanged
    return true
end

local function pack(...)
    return {n = select("#", ...), ...}
end

local function run(token, callback, ...)
    local previous, previousTitle = scope, titleScope
    scope = token
    titleScope = titleScope or {}
    local results = pack(pcall(callback, ...))
    scope, titleScope = previous, previousTitle
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2, results.n)
end

function Operations.run(callback, ...)
    return run(scope or {}, callback, ...)
end

function Operations.runWith(token, callback, ...)
    -- Native completion and cleanup must still execute after cancellation; async adapters use runContinuation.
    return run(token or scope or {}, callback, ...)
end

function Operations.invalidate(token)
    if type(token) == "table" then token.toolkitCancelled = true end
end

function Operations.invalidateQueue(queue)
    if not queue then return end
    if not queue.queue then queue = ISTimedActionQueue.queues[queue] end
    if queue then
        queue.toolkitOperationGeneration = (queue.toolkitOperationGeneration or 0) + 1
        for _, action in ipairs(queue.queue) do Operations.invalidate(action.toolkitQueueOperation) end
    end
end

function Operations.attachContinuation(token, character)
    if type(token) ~= "table" or token.toolkitCancelled then return end
    local queue = ISTimedActionQueue.getTimedActionQueue(character)
    token.toolkitContinuations = (token.toolkitContinuations or 0) + 1
    return {marker = continuationMarker, token = token, character = character, queue = queue,
        generation = queue.toolkitOperationGeneration or 0}
end

function Operations.finishContinuation(continuation)
    if not continuation or continuation.marker ~= continuationMarker or continuation.finished then return end
    continuation.finished = true
    local token = continuation.token
    token.toolkitContinuations = token.toolkitContinuations - 1
end

function Operations.isContinuationPending(token)
    return type(token) == "table" and (token.toolkitContinuations or 0) > 0
end

local function continuationValid(continuation)
    if not continuation or continuation.marker ~= continuationMarker or continuation.finished
        or continuation.token.toolkitCancelled then return false end
    local settings = PZSurvivorToolkit.Settings
    local character = continuation.character
    return (not settings or settings.actionQueue())
        and (not character.isDead or not character:isDead())
        and ISTimedActionQueue.queues[character] == continuation.queue
        and (continuation.queue.toolkitOperationGeneration or 0) == continuation.generation
end

function Operations.runContinuation(continuation, callback, ...)
    if continuation and continuation.running then return end
    if not continuationValid(continuation) then Operations.finishContinuation(continuation); return end
    local previous = continuationScope
    continuationScope, continuation.running = continuation, true
    local results = pack(pcall(run, continuation.token, callback, ...))
    continuationScope, continuation.running = previous, nil
    Operations.finishContinuation(continuation)
    if not results[1] then error(results[2], 0) end
    return unpack(results, 2, results.n)
end

local function waitForCompletion(action)
    -- SP starts the next action inside perform(), before complete() consumes the preceding inputs.
    if not action.toolkitCompletionWaited then action.toolkitCompletionWaited = true; return true end
    local record = action.toolkitQueueCommand
    return record and record.ready and not record.ready(action.character, record.snapshot) or false
end

local function startCommand(action)
    action:beginAddingActions()
    Operations.runWith(action.toolkitQueueOperation, action.addActionsFunction, action.character, unpack(action.args))
    action:endAddingActions()
    -- An invalid future target skips its command without clearing unrelated native actions.
    action:forceComplete()
end

function Operations.command(character, callback, snapshot, options)
    local action = ISQueueActionsAction:new(character, callback, snapshot)
    action.start, action.waitToStart = startCommand, waitForCompletion
    for key, value in pairs(options and options.fields or {}) do action[key] = value end
    action.toolkitQueueCommand = {marker = commandMarker, owner = action, callback = callback, args = action.args,
        snapshot = snapshot, ready = options and options.ready}
    return action
end

function Operations.adoptCommandLifecycle(name, previous, replacement)
    if commandMethods[name] ~= previous then return false end
    commandMethods[name] = replacement
    return true
end

function Operations.isCommand(action)
    local record = action and action.toolkitQueueCommand
    if not record or record.marker ~= commandMarker or record.owner ~= action
        or getmetatable(action) ~= commandClass or action.Type ~= commandClass.Type
        or action.addActionsFunction ~= record.callback or action.args ~= record.args or action.args[1] ~= record.snapshot
        or action.onStartFunc or action.onCompleteFunc or action.onCancelFunc then return false end
    for _, name in ipairs(commandLifecycle) do
        local expected = name == "start" and startCommand or name == "waitToStart" and waitForCompletion or commandMethods[name]
        if action[name] ~= expected then return false end
    end
    return true
end

function Operations.enqueue(character, callback, snapshot, options)
    return Operations.run(function()
        local action = Operations.command(character, callback, snapshot, options)
        if options and options.priority then action.toolkitQueuePriority = options.priority end
        return ISTimedActionQueue.add(action)
    end)
end

function Operations.deferCompletion(queue, action)
    if completionScope and completionScope.action == action and queue.queue[1] == action then
        completionScope.queue = queue
        return true
    end
end

-- Shared completion is enabled per producer after its native SP/Host child-order gates.
function Operations.registerProducer(id, supports, acceptsChild, sharedLifecycle)
    assert(type(id) == "string" and type(supports) == "function" and type(acceptsChild) == "function")
    assert(not producers[id], "duplicate action producer: " .. id)
    assert(sharedLifecycle == nil or type(sharedLifecycle) == "boolean")
    producers[id] = {supports = supports, acceptsChild = acceptsChild, sharedLifecycle = sharedLifecycle == true}
end

local function producerFor(action)
    for _, producer in pairs(producers) do
        if producer.supports(action) then return producer end
    end
end

function Operations.perform(action, callback, ...)
    local Craft = PZSurvivorToolkit.ActionQueueCraft
    local Settings = PZSurvivorToolkit.Settings
    local producer = producerFor(action)
    if (Settings and not Settings.actionQueue()) or (not producer and (not Craft or not Craft.supports(action))) then
        return callback(action, ...)
    end
    local lifecycle = PZSurvivorToolkit.ActionQueueLifecycle
    if (not producer or producer.sharedLifecycle) and lifecycle and lifecycle.current(action.character) == action then
        return callback(action, ...)
    end
    local previous = completionScope
    local pending = {action = action, acceptsChild = producer and producer.acceptsChild}
    completionScope = pending
    local results = pack(pcall(Operations.runWith, action.toolkitQueueOperation, callback, action, ...))
    completionScope = previous
    if not results[1] then error(results[2], 0) end
    -- Native MP handcraft callbacks add returns after base.perform; finish that same task before advancing.
    if pending.queue and pending.queue.current == action and pending.queue.queue[1] == action then
        pending.queue:onCompleted(action)
    end
    return unpack(results, 2, results.n)
end

local function stamp(action, token)
    if not action.toolkitQueueOperation then
        local queue = ISTimedActionQueue.queues[action.character]
        local current = queue and queue.queue[1]
        if current and current._isAddingActions then
            token = current.toolkitQueueOperation
            action.toolkitBatchIteration = current.toolkitBatchIteration
        end
        local lifecycle = PZSurvivorToolkit.ActionQueueLifecycle
        local completing = lifecycle and lifecycle.current(action.character)
        if completing and not scope then token = token or completing.toolkitQueueOperation end
        action.toolkitQueueOperation = token or scope or {}
    end
    if not action.ignoreAction and PZSurvivorToolkit.ActionQueueBatch then
        PZSurvivorToolkit.ActionQueueBatch.attach(action)
    end
    -- Keep original pickup locations after native transfers merge or leave the queue.
    local operation = action.toolkitQueueOperation
    if type(operation) == "table" and action.toolkitQueuePriority == "urgent" then operation.toolkitPriority = "urgent" end
    if type(operation) == "table" and Operations.isTransfer(action)
        and action.item and action.srcContainer and action.destContainer
        and action.destContainer == action.character:getInventory()
        and action.srcContainer ~= action.destContainer
        and action.item:getContainer() == action.srcContainer then
        operation.toolkitPickups = operation.toolkitPickups or {}
        if not operation.toolkitPickups[action.item] then
            operation.toolkitPickups[action.item] = action.srcContainer
        end
    end
end

-- Audited mod callbacks sometimes insert directly into the native queue array.
function Operations.adopt(action, token)
    stamp(action, token)
end

local function rememberTitle(action, queue, index, previousCount)
    local definitions = PZSurvivorToolkit.ActionQueueDefinitions
    if not definitions or action.ignoreAction then return end
    queue = queue or ISTimedActionQueue.queues[action.character]
    if not queue then return end
    -- This presentation summary lives only within one synchronous dispatch. Native
    -- completion, later commands and queue edits cannot reuse its old membership.
    local context = titleScope or {}
    if index and definitions.appendTaskTitle and definitions.appendTaskTitle(queue, action, index, previousCount, context) then return end
    local first, last = Operations.bounds(queue, action)
    if first then definitions.taskTitle(queue, first, last, true, context) end
end

-- Audited source callbacks may bypass enqueue hooks. Invalidate display only;
-- the next heading read rebuilds once, or ordinary enqueue refreshes it first.
function Operations.invalidateTitle(action)
    local definitions = PZSurvivorToolkit.ActionQueueDefinitions
    if definitions and definitions.invalidateTaskTitle then definitions.invalidateTaskTitle(action) end
end

local add = ISTimedActionQueue.add
ISTimedActionQueue.add = function(action)
    if continuationScope and not continuationValid(continuationScope) then return end
    stamp(action)
    local lifecycle = PZSurvivorToolkit.ActionQueueLifecycle
    local nativeParent = lifecycle and lifecycle.current(action.character)
    local current = completionScope and completionScope.action or nativeParent
    local queue = current and ISTimedActionQueue.queues[current.character]
    local sameOperation = queue and queue.queue[1] == current and action.character == current.character
        and action.toolkitQueueOperation == current.toolkitQueueOperation
        and not current._isAddingActions
    local accepted, placement
    if sameOperation and completionScope and completionScope.acceptsChild then accepted, placement = completionScope.acceptsChild(current, action) end
    -- Craft OnCreate may add unrelated mod actions; only audited returns inherit placement.
    if sameOperation and nativeParent and not completionScope then
        local producer = producerFor(current)
        if producer and producer.sharedLifecycle then
            accepted, placement = producer.acceptsChild(current, action)
        elseif current.Type ~= "ISCraftAction" and current.Type ~= "ISHandcraftAction" then
            accepted, placement = true, "before-returns"
        end
    end
    local returning = sameOperation and nativeReturn(action)
    if sameOperation and (returning or accepted) then
        local last = 1
        while queue.queue[last + 1] and queue.queue[last + 1].toolkitQueueOperation == current.toolkitQueueOperation do
            -- A native retry still needs the tools that the following return would remove.
            if accepted and not returning and placement == "before-returns" and nativeReturn(queue.queue[last + 1]) then break end
            last = last + 1
        end
        local result = add(action)
        local index = queue:indexOf(action)
        if index > last then
            table.remove(queue.queue, index)
            table.insert(queue.queue, last + 1, action)
            if titleScope then titleScope[queue] = nil end
            rememberTitle(action)
        end
        return result
    end
    -- Native deferred commands insert directly, bypassing addToQueue.
    local parentQueue = ISTimedActionQueue.queues[action.character]
    local parent = parentQueue and parentQueue.queue[1]
    local inserting = parent and parentQueue:isCurrentActionAddingOtherActions()
    local previousCount = inserting and #parentQueue.queue
    local index = inserting and 2 + parent._numAddedActions
    local result = add(action)
    if inserting and #parentQueue.queue == previousCount + 1 and parentQueue.queue[index] == action then
        rememberTitle(action, parentQueue, index, previousCount)
    end
    return result
end

local addToQueue = ISTimedActionQueue.addToQueue
ISTimedActionQueue.addToQueue = function(queue, action)
    if continuationScope and not continuationValid(continuationScope) then return end
    stamp(action)
    local previousCount = #queue.queue
    local result = addToQueue(queue, action)
    rememberTitle(action, queue, previousCount + 1, previousCount)
    return result
end

local addAfter = ISTimedActionQueue.addAfter
ISTimedActionQueue.addAfter = function(previous, action)
    if continuationScope and not continuationValid(continuationScope) then return end
    if not previous then return addAfter(previous, action) end
    stamp(previous)
    action.toolkitQueueOperation = previous.toolkitQueueOperation
    local queue, added = addAfter(previous, action)
    if added then
        stamp(added)
        previous.toolkitQueueLinked, added.toolkitQueueLinked = true, true
        if titleScope then titleScope[queue] = nil end
        rememberTitle(added)
    end
    return queue, added
end

function Operations.bounds(queue, action)
    local index = queue:indexOf(action)
    if index == -1 then return end
    local token = action.toolkitQueueOperation
    if not token then return index, index end
    local first, last = index, index
    while first > 1 and queue.queue[first - 1].toolkitQueueOperation == token do first = first - 1 end
    while last < #queue.queue and queue.queue[last + 1].toolkitQueueOperation == token do last = last + 1 end
    for i, queued in ipairs(queue.queue) do
        if (i < first or i > last) and queued.toolkitQueueOperation == token then return end
    end
    return first, last
end

local canMerge = ISInventoryTransferAction.canMergeAction
local function operationCanMerge(action, following)
    if PZSurvivorToolkit.Settings.actionQueue() and following
        and action.toolkitQueueOperation ~= following.toolkitQueueOperation then return false end
    return canMerge(action, following)
end
ISInventoryTransferAction.canMergeAction = operationCanMerge

-- Read-only provenance for adapters loaded after this boundary was installed.
function Operations.transferMergeDelegate(callback)
    if callback == operationCanMerge and ISInventoryTransferAction.canMergeAction == operationCanMerge then return canMerge end
end

local function wrap(class, method, fresh)
    local callback = class and class[method]
    if not callback then return end
    class[method] = function(...)
        if fresh then return run({}, callback, ...) end
        return Operations.run(callback, ...)
    end
end

-- UI callbacks enqueue preparation, the operation and native returns synchronously.
-- shortcut: plain add in async mod callbacks is ungrouped; add an adapter when supporting that callback.
wrap(ISContextMenu, "onMouseUp")
wrap(ISContextMenu, "onJoypadDown")
wrap(ISContextMenu, "onJoypadDirLeft")
wrap(ISContextMenu, "onKeyPress")
wrap(ISButton, "onMouseUp")
wrap(ISButton, "forceClick")
wrap(ISButton, "onJoypadDown")
wrap(ISInventoryPane, "onMouseUp")
wrap(ISInventoryPane, "onMouseDoubleClick")
wrap(ISInventoryPaneContextMenu, "readItem", true)

-- The native volume bar commits directly, or later from update() after a
-- joypad/+/- change. Scope the real producer rather than the earlier UI click.
local volumeProducer
function Operations.installVolumeProducer()
    local class, panel = RWMVolume, RWMPanel
    if volumeProducer then
        return class == volumeProducer.class and panel == volumeProducer.panel
            and class.onVolumeChange == volumeProducer.wrapper
    end
    local callback, walk = class and class.onVolumeChange, panel and panel.doWalkTo
    local proof = require "PZSurvivorToolkit/SourceProof"
    if not proof or not proof.closure(callback, "RWMVolume.lua") or not proof.closure(walk, "RWMPanel.lua")
        or not proof.matches("media/lua/client/RadioCom/RadioWindowModules/RWMVolume.lua", 1122481123, nil, true)
        or not proof.matches("media/lua/client/RadioCom/RadioWindowModules/RWMPanel.lua", 4229885986, nil, true) then return false end
    local wrapper
    wrapper = function(self, ...)
        if RWMVolume ~= class or RWMPanel ~= panel or class.onVolumeChange ~= wrapper
            or panel.doWalkTo ~= walk or self.doWalkTo ~= walk then return callback(self, ...) end
        return Operations.run(callback, self, ...)
    end
    volumeProducer = {class = class, panel = panel, wrapper = wrapper}
    class.onVolumeChange = wrapper
    return true
end
Operations.installVolumeProducer()

local transferPanes = {}
local function installTransferPane(class)
    if not class or transferPanes[class] or type(class.transferItemsByWeight) ~= "function" then return end
    transferPanes[class] = true
    local transfer = class.transferItemsByWeight
    class.transferItemsByWeight = function(...)
        local util = ISInventoryTransferUtil
        local create = util.newInventoryTransferAction
        -- CleanUI constructs the selected transfers now, but enqueues them next tick.
        -- Capture this command before its scope ends, without changing deferred execution.
        util.newInventoryTransferAction = function(...)
            local results = pack(create(...))
            if results[1] then Operations.adopt(results[1]) end
            return unpack(results, 1, results.n)
        end
        local results = pack(pcall(Operations.run, transfer, ...))
        -- Keep the current factory's identity outside this command: other adapters
        -- use its native provenance when checking unrelated actions.
        util.newInventoryTransferAction = create
        if not results[1] then error(results[2], 0) end
        return unpack(results, 2, results.n)
    end
end

local function installTransferPanes()
    InventoryClasses.panes(installTransferPane)
end
Events.OnGameStart.Add(function()
    Operations.installVolumeProducer()
    installTransferPanes()
    InventoryClasses.onToggle(installTransferPanes)
end)

return Operations
