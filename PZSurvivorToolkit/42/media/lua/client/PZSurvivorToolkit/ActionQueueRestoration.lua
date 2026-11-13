-- Own restoration producers schedule cleanup; Settlement alone proves and pays debt.
local Toolkit = PZSurvivorToolkit
local Settlement = require "PZSurvivorToolkit/ActionQueueSettlement"
local Proof = require "PZSurvivorToolkit/SourceProof"
local Restoration = {}
Toolkit.ActionQueueRestoration = Restoration
local enqueue = Settlement.enqueueBorrowedReturn
local capture, origin = Proof.captureBindings, Proof.closure
local borrowedReturns

-- Snapshot before any source checks, native constructors or family callbacks.
-- Handles remain opaque: neither copied fields nor a producer flag earn a loan.
local function handlesSnapshot(handles)
    if type(handles) ~= "table" or getmetatable(handles) ~= nil then return end
    local size, result, seen = #handles, {}, {}
    for key in pairs(handles) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > size then return end
    end
    for index = 1, size do
        local handle = handles[index]
        if type(handle) ~= "table" or getmetatable(handle) ~= nil then return end
        if not seen[handle] then
            seen[handle] = true
            result[#result + 1] = handle
        end
    end
    return result
end

local function sourceLease()
    if PZSurvivorToolkit ~= Toolkit or Toolkit.ActionQueueRestoration ~= Restoration
        or Restoration.borrowedReturns ~= borrowedReturns or Toolkit.ActionQueueSettlement ~= Settlement
        or Proof.captureBindings ~= capture or Proof.closure ~= origin
        or Settlement.enqueueBorrowedReturn ~= enqueue then return end
    local watch = capture({
        {owner = _G, keys = {"PZSurvivorToolkit"}},
        {owner = Toolkit, keys = {"ActionQueueRestoration", "ActionQueueSettlement"}},
        {owner = Proof, keys = {"captureBindings", "closure"}},
        {owner = Restoration, keys = {"borrowedReturns"}},
        {owner = Settlement, keys = {"enqueueBorrowedReturn"}},
    })
    if watch and origin(enqueue, "ActionQueueSettlement.lua") and watch() then return watch end
end

-- Call inside the family's existing required cleanup expansion. Native enqueue
-- retains its ordering and ownership rules. The callback annotates each queued
-- child at the same boundary as the old family loop; it grants no authority.
-- No actionQueue setting gate: admitted cleanup can outlive disabling the editor.
borrowedReturns = function(handles, onEnqueued)
    local snapshot = handlesSnapshot(handles)
    if not snapshot or onEnqueued ~= nil and type(onEnqueued) ~= "function" then return nil, "invalid_batch" end
    if #snapshot == 0 then return 0 end
    local watch = sourceLease()
    if not watch then return nil, "source_changed" end
    local count = 0
    for _, handle in ipairs(snapshot) do
        if not watch() then return count, "source_changed" end
        -- Rechecks the exact native loan, current cleanup parent/dependencies,
        -- source identity/accessibility and prior planned return for every item.
        local action = enqueue(handle)
        if action then
            count = count + 1
            if onEnqueued then onEnqueued(action) end
        end
    end
    return count
end

Restoration.borrowedReturns = borrowedReturns
return Restoration
