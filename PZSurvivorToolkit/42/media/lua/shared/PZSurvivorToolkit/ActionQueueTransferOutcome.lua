-- Exact-item evidence for native transfers. Callers retain the sealed attempt,
-- queue/generation checks, admission and cleanup ownership. These observations
-- never execute a transfer, reserve space, grant an edit or replay an outcome.
local Outcome = {}

local function sameMember(item, member)
    return item and member and type(item.getID) == "function" and type(item.getFullType) == "function"
        and item:getID() == member.id and item:getFullType() == member.fullType
end
Outcome.sameMember = sameMember

-- Capture the existing native API bindings once per owner, not per attempt.
-- In SP neither predicate is required. An absent MP transaction can make both
-- predicates true, which is deliberately not a successful result.
function Outcome.authorityReader(done, rejected)
    return function(client, transaction)
        if not client then return "native" end
        if type(transaction) ~= "number" or transaction == 0 or transaction % 1 ~= 0
            or type(done) ~= "function" or type(rejected) ~= "function"
            or isItemTransactionDone ~= done or isItemTransactionRejected ~= rejected then return "unavailable" end
        local completed, refused = done(transaction), rejected(transaction)
        if completed == true and refused == false then return "completed" end
        if completed == false and refused == true then return "rejected" end
        return "unavailable"
    end
end

-- The existing attempt owns members and terminal evidence. The optional owner
-- callback runs once, after an exact member effect, for family-specific cleanup.
-- No per-observation tables or persistent argument registry are introduced.
function Outcome.observer(onArrived)
    if onArrived ~= nil and type(onArrived) ~= "function" then return end
    return function(transfer, attempt)
        if attempt.terminal then return attempt.terminal end
        if not attempt.finished then return "waiting" end
        if attempt.invalid or not attempt.succeeded or attempt.authority == "unavailable" then attempt.terminal = "unavailable"
        elseif attempt.authority == "rejected" then attempt.terminal = "rejected"
        elseif not attempt.deadline or type(getTimestampMs) ~= "function" or getTimestampMs() >= attempt.deadline
            or not transfer.destination:isExistYet() then attempt.terminal = "unavailable"
        else
            local completed = 0
            for _, member in ipairs(attempt.members) do
                if not member.completed then
                    local item, sourceItem = transfer.destination:getItemById(member.id), transfer.source:getItemById(member.id)
                    if sameMember(item, member) and item:getContainer() == transfer.destination and not item:getIsCraftingConsumed()
                        and not (sourceItem and sourceItem:getContainer() == transfer.source) then
                        member.completed = true
                        if onArrived then onArrived(transfer, member) end
                    end
                end
                if member.completed then completed = completed + 1 end
            end
            if completed == #attempt.members then attempt.terminal = "completed" end
        end
        return attempt.terminal or "waiting"
    end
end

-- Exact evidence that an outgoing root-inventory attempt had no item effect.
-- Keep these reads ordered: root and both lookups, source equality, ID/type,
-- current action.item identity, location/consumption, then opposite-endpoint absence.
function Outcome.retained(action, execution)
    local root = action.character:getInventory()
    local item = root:getItemById(execution.id)
    local destinationItem = execution.destination:getItemById(execution.id)
    return root == execution.source and sameMember(item, execution) and item == action.item
        and item:getContainer() == root and not item:getIsCraftingConsumed()
        and not (destinationItem and destinationItem:getContainer() == execution.destination)
end

return Outcome
