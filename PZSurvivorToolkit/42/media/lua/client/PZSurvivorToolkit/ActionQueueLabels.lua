require "PZSurvivorToolkit/ActionQueueDefinitions"

local Labels = {}
PZSurvivorToolkit.ActionQueueLabels = Labels

function Labels.describe(action)
    return PZSurvivorToolkit.ActionQueueDefinitions.describe(action)
end

function Labels.preparation(action)
    local role = Labels.describe(action).role
    return role == "preparation" or role == "return"
end

function Labels.title(action)
    local description = Labels.describe(action)
    return description.title, description.signature
end

function Labels.label(action)
    local description = Labels.describe(action)
    return description.title .. (description.target and ": " .. description.target or "")
end

function Labels.icon(action)
    return Labels.describe(action).icon()
end

function Labels.taskTitle(queue, first, last)
    return PZSurvivorToolkit.ActionQueueDefinitions.taskTitle(queue, first, last)
end

function Labels.decisionDetails(decision)
    if not decision or decision.allowed then return end
    local parts = {}
    local blocker = decision.blocker
    if blocker then
        local token = blocker.toolkitQueueOperation or blocker
        local title = token.presentation and token.presentation.title
        if not title and blocker.Type then title = Labels.label(blocker) end
        if title then parts[#parts + 1] = getText("UI_PZSurvivorToolkit_queue_blocked_by", title) end
    end
    local resource = PZSurvivorToolkit.ActionQueueDefinitions.resourceLabel(decision.resource)
    if resource then parts[#parts + 1] = getText("UI_PZSurvivorToolkit_queue_blocked_resource", resource) end
    return #parts > 0 and table.concat(parts, " <LINE> ") or nil
end

function Labels.priorityWaiting(reason)
    local key = "UI_PZSurvivorToolkit_queue_" .. reason
    local text = getText(key)
    if text == key then text = getText("UI_PZSurvivorToolkit_queue_operation_dependent") end
    return getText("UI_PZSurvivorToolkit_queue_priority_waiting", text)
end

return Labels
