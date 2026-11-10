-- Shared wait mechanics must not renew, rebind, or fabricate native outcomes.
local now, captures, observations = 100, 0, 0
local receipt, available = {state = "started"}, false
PZSurvivorToolkit = {ActionQueueAcknowledgements = {
    capture = function() captures = captures + 1; if available then return receipt end end,
    state = function(_, captured) observations = observations + 1; assert(captured == receipt); return receipt.state end,
}}
getTimestampMs = function() return now end
local wait = assert(loadfile(ProjectRoot .. "/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueOutcomeWait.lua"))()
local queue, action = {}, {action = {}}
assert(wait.observe(queue, action) == nil, "missing Started must retain native fallback")
now, available = 500, true
local record, state = wait.observe(queue, action)
assert(state == "started" and record.deadline == 30500 and wait.matches(queue, action, record))
local captureCount = captures
now = 30000
local same, pending = wait.observe(queue, action, record)
assert(same == record and pending == "started" and captures == captureCount and not wait.expired(record),
    "repeated observation must not recapture or renew the deadline")
now = 30500
assert(wait.expired(record), "deadline must include its boundary")
receipt.state = "completed"
assert(select(2, wait.observe(queue, action, record)) == "completed",
    "expiry must not mask a terminal result; the owner decides whether its effect matched")
for _, terminal in ipairs({"canceled", "rejected"}) do
    receipt.state = terminal
    assert(select(2, wait.observe(queue, action, record)) == terminal,
        "shared observation must preserve owner-specific terminal policy")
end
local native = action.action
for _, replacement in ipairs({"native", "generation"}) do
    if replacement == "native" then action.action = {} else queue.toolkitOperationGeneration = 1 end
    local previousObservations = observations
    local retained, missing = wait.observe(queue, action, record)
    assert(retained == record and missing == nil and not wait.matches(queue, action, record)
        and captures == captureCount and observations == previousObservations,
        "a replacement episode must not inherit or recapture the old wait")
    action.action, queue.toolkitOperationGeneration = native, nil
end
receipt.state = nil
assert(select(2, wait.observe(queue, action, record)) == nil, "unknown outcome must remain unknown")
print("PASS shared native outcome wait")
