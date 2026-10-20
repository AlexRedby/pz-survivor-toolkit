-- Failure cleanup belongs only to an explicitly promoted reading range, not all TV actions.
local Toolkit = PZSurvivorToolkit
local Reading, marker = {}, {}
Toolkit.ActionQueueReading = Reading

local function remember(action, kind)
    local record = {marker = marker, kind = kind, operation = action.toolkitQueueOperation,
        character = action.character, item = action.item, device = action.device, data = action.deviceData, mode = action.mode}
    action.toolkitReadingMove = record
    return record
end

function Reading.capture(queue, first, last)
    local current = queue.current
    remember(current, "read")
    for i = 2, first - 1 do
        local action = queue.queue[i]
        if action.Type == "ISInventoryTransferAction" and action.item == current.item and action.allowMissingItems
            and action.srcContainer == queue.character:getInventory() then
            local record = remember(action, "return")
            record.destination, record.source = action.destContainer, action.srcContainer
        end
    end
    local insertions, pickups = {}, {}
    for i = first, last do
        local action = queue.queue[i]
        local media = Toolkit.ActionQueueMedia
        local receipt = media and media.capture(action)
        if receipt then
            local record = remember(action, "media")
            record.receipt, record.mediaIndex = receipt, action.secondaryItem:getRecordedMediaIndex()
            local pickup = pickups[receipt.tape]
            if pickup and pickup.operation == record.operation and pickup.destination == receipt.root
                and pickup.source == receipt.container then record.pickup = pickup end
            insertions[action.deviceData:getParent()] = record
        elseif action.Type == "ISInventoryTransferAction" and Toolkit.ActionQueuePolicy.matchesNative(action) then
            local record = remember(action, "pickup")
            record.destination, record.source = action.destContainer, action.srcContainer
            record.action, record.queue, record.generation = action, queue, queue.toolkitOperationGeneration or 0
            pickups[record.item] = record
        elseif action.Type == "ISRadioAction" and instanceof(action.device, "IsoTelevision")
            and (action.mode == "ToggleOnOff" or action.mode == "TogglePlayMedia") then
            local _, source = Toolkit.ActionQueuePolicy.inspect(action)
            if source == "native.ISRadioAction" then
                local record = remember(action, "radio")
                if action.mode == "TogglePlayMedia" then record.insertion = insertions[action.device] end
            end
        end
    end
end

-- Called only after the shared native lifecycle has confirmed successful pickup
-- completion and removal from the Java stack. Do not infer success from an ID alone.
function Reading.completedPickup(queue, action)
    local pickup = action.toolkitReadingMove
    if not isClient() or not Toolkit.Settings.actionQueue() or not pickup or pickup.marker ~= marker
        or pickup.kind ~= "pickup" or pickup.action ~= action or pickup.queue ~= queue
        or pickup.generation ~= (queue.toolkitOperationGeneration or 0)
        or pickup.operation ~= action.toolkitQueueOperation or pickup.character ~= action.character
        or type(pickup.operation) == "table" and pickup.operation.toolkitCancelled
        or queue.current ~= action or queue.queue[1] ~= action or queue.toolkitCancel or queue.toolkitGroupCancel
        or action.action and action.action:hasStalled()
        or not Toolkit.ActionQueuePolicy.live(queue) or not Toolkit.ActionQueuePolicy.matchesNative(action)
        or action.srcContainer ~= pickup.source or action.destContainer ~= pickup.destination
        or not pickup.source:isExistYet() or not pickup.destination:isExistYet() then return end
    for i = 2, #queue.queue do
        local pending = queue.queue[i]
        local record = pending.toolkitReadingMove
        if record and record.marker == marker and record.kind == "media" and record.pickup == pickup
            and not record.skipped and not record.completion
            and record.operation == pending.toolkitQueueOperation and record.operation == pickup.operation
            and record.character == pending.character and record.character == pickup.character
            and record.receipt.tape == pickup.item then
            local receipt = Toolkit.ActionQueueMedia.afterPickup(pending, record.receipt, action)
            if receipt then record.receipt = receipt end
        end
    end
end

function Reading.resumed(previous, resumed)
    local record = previous.toolkitReadingMove
    if record and record.marker == marker and record.kind == "read" then remember(resumed, "read") end
end

local function mediaWait(queue, action, record)
    local acknowledgements = Toolkit.ActionQueueAcknowledgements
    local wait = record.completion
    if not wait then
        local receipt = acknowledgements and acknowledgements.capture(action)
        if not receipt then return end
        wait = {receipt = receipt, native = action.action, generation = queue.toolkitOperationGeneration or 0,
            deadline = getTimestampMs() + 30000}
        record.completion = wait
    end
    if wait.native ~= action.action or wait.generation ~= (queue.toolkitOperationGeneration or 0) then return wait end
    return wait, acknowledgements.state(action, wait.receipt)
end

-- Native validity runs before the update that observes Done. Preserve only an
-- already started, acknowledged insertion whose expected effects arrived early.
-- Server validation, native stop/cancel and native completion remain unchanged.
function Reading.keepPendingMedia(action)
    local record = action.toolkitReadingMove
    if not isClient() or not Toolkit.Settings.actionQueue() or not action.action
        or not action.action:isStarted() or not record or record.marker ~= marker or record.kind ~= "media"
        or record.operation ~= action.toolkitQueueOperation or record.character ~= action.character then return false end
    local queue = ISTimedActionQueue.queues[action.character]
    if not queue or queue.current ~= action or queue.queue[1] ~= action or not Toolkit.ActionQueuePolicy.live(queue)
        or queue.toolkitCancel or not Toolkit.ActionQueueMedia.hasReplicatedEffect(action, record.receipt) then return false end
    local wait, state = mediaWait(queue, action, record)
    return wait ~= nil and (state == "started" or state == "completed") and getTimestampMs() < wait.deadline
end

-- MP Done and device media replication use different network channels. Hold the
-- existing completion boundary until both have arrived, without replaying insertion.
function Reading.mediaCompletionState(queue, action)
    local record = action.toolkitReadingMove
    if not isClient() or not record or record.marker ~= marker or record.kind ~= "media" then return end
    if record.operation ~= action.toolkitQueueOperation or record.character ~= action.character then return "failed" end
    local result = Toolkit.ActionQueueMedia.completionState(action, record.receipt)
    if not result then return "failed" end
    local player = action.character
    if (action.stopOnRun and (player:isRunning() or player:isSprinting()) and player:isPlayerMoving())
        or (action.stopOnWalk and player:isPlayerMoving()) or (action.stopOnAim and player:isAiming()) then
        return "failed"
    end
    local wait, state = mediaWait(queue, action, record)
    if not wait then return end -- Preserve native fallback without the supported outcome protocol.
    if wait.native ~= action.action or wait.generation ~= (queue.toolkitOperationGeneration or 0) then return "failed" end
    if state == "completed" and result == "matched" then record.completion = nil; return end
    if not state or state == "canceled" or state == "rejected" or result == "unavailable"
        or getTimestampMs() >= wait.deadline then
        record.skipped, record.completion = true, nil
        return
    end
    return "waiting"
end

local function waitingMedia(character)
    if not character or not isClient() then return end
    local queue = ISTimedActionQueue.queues[character]
    local lifecycle = Toolkit.ActionQueueLifecycle
    local action = lifecycle and lifecycle.deferredAction(queue)
    local media=Toolkit.ActionQueueMedia
    if action and media and media.canCancelWait(action) then return queue end
    if not Toolkit.Settings.actionQueue() then return end
    local record = action and action.toolkitReadingMove
    if record and record.marker == marker and record.kind == "media"
        and record.operation == action.toolkitQueueOperation and record.character == character
        and Toolkit.ActionQueuePolicy.live(queue)
        and Toolkit.ActionQueueMedia.completionState(action, record.receipt) then return queue end
end

-- Retain native key, menu, dragging and gamepad rules. Only the captured removed
-- insertion needs a cancellable Lua continuation when the Java stack is empty.
local cancelHelpersInstalled = false
function Reading.installCancelHelpers()
    if cancelHelpersInstalled then return end
    local available, stop = isPlayerDoingActionThatCanBeCancelled, stopDoingActionThatCanBeCancelled
    if type(available) ~= "function" or type(stop) ~= "function" then return end
    isPlayerDoingActionThatCanBeCancelled = function(character)
        return available(character) or waitingMedia(character) ~= nil
    end
    stopDoingActionThatCanBeCancelled = function(character)
        local queue = waitingMedia(character)
        if queue then queue:resetQueue() end
        return stop(character)
    end
    cancelHelpersInstalled = true
end
Reading.installCancelHelpers()
Events.OnGameStart.Add(Reading.installCancelHelpers)

local function unavailable(action)
    local record = action.toolkitReadingMove
    if not record or record.marker ~= marker or record.operation ~= action.toolkitQueueOperation
        or record.character ~= action.character or action.action then return false end
    if record.kind == "media" then return Toolkit.ActionQueueMedia.canSkip(action, record.receipt) end
    local policy = Toolkit.ActionQueuePolicy
    if not policy.matchesNative(action) then return false end
    if record.kind == "read" then
        return action.Type == "ISReadABook" and action.item == record.item
            and not action.character:getInventory():getItemById(record.item:getID())
    elseif record.kind == "return" then
        return action.Type == "ISInventoryTransferAction" and action.item == record.item and action.allowMissingItems
            and action.srcContainer == record.source and action.destContainer == record.destination
            and (not record.destination:isExistYet() or not record.source:getItemById(record.item:getID()))
    elseif record.kind == "pickup" then
        return action.Type == "ISInventoryTransferAction" and action.item == record.item
            and action.srcContainer == record.source and action.destContainer == record.destination
            and (not record.source:isExistYet() or not record.destination:isExistYet())
    elseif record.kind == "radio" then
        if action.Type ~= "ISRadioAction" or action.device ~= record.device or action.deviceData ~= record.data
            or action.mode ~= record.mode then return false end
        local _, source = policy.inspect(action)
        if source ~= "native.ISRadioAction" then return false end
        local device, data = record.device, record.data
        if device:getObjectIndex() < 0 or not device:getSquare() or device:getDeviceData() ~= data then return true end
        if record.mode == "TogglePlayMedia" then
            return not data:getIsTurnedOn() or not data:hasMedia()
                or (record.insertion and (record.insertion.skipped or data:getMediaIndex() ~= record.insertion.mediaIndex))
        end
        return not (data:getIsBatteryPowered() and data:getPower() > 0 or data:canBePoweredHere())
    end
    return false
end

function Reading.skipUnavailable(queue)
    if not Toolkit.Settings.actionQueue() or not Toolkit.ActionQueuePolicy.live(queue)
        or queue.character:isPlayerMoving() or queue.character:pressedMovement(false) then return end
    while queue.queue[2] and unavailable(queue.queue[2]) do
        local action = table.remove(queue.queue, 2)
        action.toolkitReadingMove.skipped = true
        if Toolkit.ActionQueueBatch then Toolkit.ActionQueueBatch.discard(action) end
        action:forceCancel()
    end
end
return Reading
