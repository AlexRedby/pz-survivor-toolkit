-- Native request receipts are observations, never queue edit/cleanup authority.
local Toolkit = PZSurvivorToolkit
local Proof = require "PZSurvivorToolkit/SourceProof"
local own, origin = Proof.own, Proof.closure
local Requests = {pending = {}}
Toolkit.ActionQueueTransferRequests = Requests
local pending, watches = Requests.pending, {}
local function owned(callback)
    return Proof.own == own and Proof.closure == origin
        and type(callback) == "function" and origin(callback, "ActionQueueSettlement.lua")
end
local function release(binding)
    if watches[binding.actor] == binding then
        watches[binding.actor], pending[binding.actor] = nil, nil
    end
end
-- Validate before the owner's final source read. The returned private commit
-- closure only publishes captured fields, without callbacks/getters or a registry
-- of abandoned preparations. Its public pending map is just a Java lookup hint.
function Requests.prepare(action, guard, before, after)
    if Toolkit ~= PZSurvivorToolkit or Toolkit.ActionQueueTransferRequests ~= Requests
        or Requests.pending ~= pending or not owned(guard) or not owned(before) or not owned(after) then return end
    local actor = action and action.character
    local queue = actor and ISTimedActionQueue.queues[actor]
    if not queue or queue.character ~= actor or queue.current ~= action or queue.queue[1] ~= action then return end
    local binding = {actor = actor, action = action, queue = queue, list = queue.queue,
        token = action.toolkitQueueOperation, generation = queue.toolkitOperationGeneration or 0,
        guard = guard, before = before, after = after}
    local used = false
    return function()
        if used then return false end
        used = true
        watches[actor], pending[actor] = binding, action
        return true
    end
end
function Requests.clear(action)
    local actor = action and action.character
    local binding = actor and watches[actor]
    if binding and binding.action == action then release(binding)
    elseif actor and pending[actor] == action then pending[actor] = nil end
end
function Requests.reset(actor)
    if actor == nil then return end
    local binding = watches[actor]
    if binding then release(binding) else pending[actor] = nil end
end
local function live(binding)
    local queue, action = binding.queue, binding.action
    return Toolkit == PZSurvivorToolkit and Toolkit.ActionQueueTransferRequests == Requests and Requests.pending == pending
        and ISTimedActionQueue.queues[binding.actor] == queue and queue.character == binding.actor and queue.queue == binding.list
        and queue.current == action and queue.queue[1] == action and action.character == binding.actor
        and action.toolkitQueueOperation == binding.token and (queue.toolkitOperationGeneration or 0) == binding.generation
end
function Requests.observe(receipt)
    if type(receipt) ~= "userdata" or not instanceof(receipt, "NativeTransferRequestReceipt") then return end
    local actor = receipt:getActor()
    local binding = watches[actor]
    if not binding then return end
    if not live(binding) then release(binding); return end
    if receipt:getAction() ~= binding.action or not receipt:isCurrent(binding.action) then return end
    local phase = receipt:getPhase()
    if phase == "before" then
        -- Reentry cannot consume/replace the enclosing native request's record.
        if binding.receipt then binding.ambiguous = true; return end
        if not receipt:claim(binding.action) then return end
        binding.receipt = receipt
        local ok, accepted = pcall(binding.guard, binding.action)
        if not ok or accepted ~= true or not live(binding) then release(binding); return end
        local value
        ok, value = pcall(binding.before, binding.action, receipt)
        if not ok then release(binding); return end
        binding.value = value
    elseif phase == "submitted" or phase == "failed" then
        if binding.receipt ~= receipt or not receipt:claim(binding.action) then return end
        local value, ambiguous = binding.value, binding.ambiguous or receipt:hasNestedRequest()
        binding.receipt, binding.value, binding.ambiguous = nil, nil, nil
        if not pcall(binding.after, binding.action, value, receipt, ambiguous == true) then release(binding) end
    end
end
return Requests
