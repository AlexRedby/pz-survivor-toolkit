-- Receipt observation only. The operation owner decides whether to wait, fail,
-- skip dependent work or retain native fallback; this module grants no edit or
-- replay rights and never advances the queue.
local Toolkit = PZSurvivorToolkit
local Wait = {}
Toolkit.ActionQueueOutcomeWait = Wait

function Wait.matches(queue, action, wait)
    return wait ~= nil and wait.native == action.action
        and wait.generation == (queue.toolkitOperationGeneration or 0)
end

function Wait.observe(queue, action, wait)
    local acknowledgements = Toolkit.ActionQueueAcknowledgements
    if not wait then
        local receipt = acknowledgements and acknowledgements.capture(action)
        if not receipt then return end
        wait = {receipt = receipt, native = action.action,
            generation = queue.toolkitOperationGeneration or 0,
            deadline = getTimestampMs() + 30000}
    end
    -- Do not recapture a replacement episode or renew the original deadline.
    if not Wait.matches(queue, action, wait) then return wait end
    return wait, acknowledgements.state(action, wait.receipt)
end

function Wait.expired(wait)
    return getTimestampMs() >= wait.deadline
end

return Wait
