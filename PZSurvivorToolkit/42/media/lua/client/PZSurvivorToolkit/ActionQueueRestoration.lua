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

-- Native readItem already creates its optional return. Enroll that exact
-- producer without P4; do not create an additional action or prebind cleanup.
local observeNative, nativeSources, nativeReadRole
local prepare = Settlement.observePreparation
local remember = Settlement.rememberPreparation
local activatedMods = getActivatedMods
local firstLine = getFirstLineOfClosure
local filename = getFilenameOfClosure
local sourceMatches = Proof.matches
local nativeOperations = Toolkit.ActionQueueOperations
local nativeProducer = nativeOperations and nativeOperations.producer
local nativeProducerVerified
local function nativeDependencies()
    local policy, definitions, settings, operations = Toolkit.ActionQueuePolicy, Toolkit.ActionQueueDefinitions,
        Toolkit.Settings, Toolkit.ActionQueueOperations
    if type(policy) ~= "table" or getmetatable(policy) ~= nil
        or type(definitions) ~= "table" or getmetatable(definitions) ~= nil
        or type(settings) ~= "table" or getmetatable(settings) ~= nil
        or type(operations) ~= "table" or getmetatable(operations) ~= nil
        or type(settings.actionQueue) ~= "function" then return end
    -- Capture references before invoking metadata. nativeLease authenticates
    -- this candidate only after its source/export watch has been prepared.
    local saved = nativeSources or {policy = policy, definitions = definitions, settings = settings, operations = operations,
        matches = policy.matchesNative, ordinary = policy.isOrdinaryTransfer, carried = policy.isCarriedContainer,
        inspect = definitions.inspect, enabled = settings.actionQueue, producer = operations.producer}
    if policy ~= saved.policy or definitions ~= saved.definitions or settings ~= saved.settings or operations ~= saved.operations
        or policy.matchesNative ~= saved.matches or policy.isOrdinaryTransfer ~= saved.ordinary
        or policy.isCarriedContainer ~= saved.carried or definitions.inspect ~= saved.inspect
        or settings.actionQueue ~= saved.enabled or operations.producer ~= saved.producer then return end
    return saved
end
local function nativeLease()
    if P4TidyUpMeister ~= nil or PZSurvivorToolkit ~= Toolkit or Toolkit.ActionQueueRestoration ~= Restoration
        or Restoration.observeNative ~= observeNative or Toolkit.ActionQueueSettlement ~= Settlement
        or Settlement.observePreparation ~= prepare or Settlement.rememberPreparation ~= remember
        or Proof.captureBindings ~= capture or Proof.closure ~= origin or Proof.matches ~= sourceMatches
        or getActivatedMods ~= activatedMods or type(activatedMods) ~= "function"
        or getFirstLineOfClosure ~= firstLine or type(firstLine) ~= "function"
        or getFilenameOfClosure ~= filename or type(filename) ~= "function" then return end
    local saved = nativeDependencies()
    if not saved then return end
    local watch = capture({
        {owner = _G, keys = {"PZSurvivorToolkit", "P4TidyUpMeister", "getActivatedMods", "getFirstLineOfClosure", "getFilenameOfClosure", "ISInventoryPaneContextMenu"}},
        {owner = Toolkit, keys = {"ActionQueueRestoration", "ActionQueueSettlement", "ActionQueuePolicy", "ActionQueueDefinitions", "ActionQueueOperations", "Settings"}},
        {owner = Restoration, keys = {"observeNative"}},
        {owner = Settlement, keys = {"observePreparation", "rememberPreparation"}},
        {owner = Proof, keys = {"captureBindings", "closure", "matches"}},
        {owner = saved.policy, keys = {"matchesNative", "isOrdinaryTransfer", "isCarriedContainer"}},
        {owner = saved.definitions, keys = {"inspect"}},
        {owner = saved.operations, keys = {"producer"}},
        {owner = saved.settings, keys = {"actionQueue"}},
    })
    if not watch then return end
    if not nativeSources then
        if not origin(saved.matches, "ActionQueuePolicy.lua")
            or not origin(saved.ordinary, "ActionQueuePolicy.lua")
            or not origin(saved.carried, "ActionQueuePolicy.lua")
            or not origin(saved.inspect, "ActionQueueDefinitions.lua")
            or not origin(saved.producer, "ActionQueueOperations.lua")
            or not origin(prepare, "ActionQueueSettlement.lua")
            or not origin(remember, "ActionQueueSettlement.lua") or not watch() then return end
        nativeSources = saved
    end
    return watch, saved
end
observeNative = function(action)
    -- Existing P4 runs pay only this cheap check. Selection is checked separately
    -- below, so a selected mod with a delayed/missing global never enables us.
    if P4TidyUpMeister ~= nil or PZSurvivorToolkit ~= Toolkit
        or Toolkit.ActionQueueRestoration ~= Restoration or Restoration.observeNative ~= observeNative
        or Toolkit.ActionQueueOperations ~= nativeOperations
        or not nativeOperations or nativeOperations.producer ~= nativeProducer
        or Proof.closure ~= origin or getFilenameOfClosure ~= filename then return false end
    if not nativeProducerVerified then
        if not origin(nativeProducer, "ActionQueueOperations.lua") or P4TidyUpMeister ~= nil
            or PZSurvivorToolkit ~= Toolkit or Toolkit.ActionQueueRestoration ~= Restoration
            or Restoration.observeNative ~= observeNative or Toolkit.ActionQueueOperations ~= nativeOperations
            or nativeOperations.producer ~= nativeProducer or getFilenameOfClosure ~= filename
            or Proof.closure ~= origin then return false end
        nativeProducerVerified = true -- Immutable callback metadata only.
    end
    local callback, owner, method = nativeProducer(action)
    -- Unrelated enqueues do no source-file, mod-list or contract inspection.
    if owner ~= ISInventoryPaneContextMenu or method ~= "readItem" then return false end
    local watch, saved = nativeLease()
    if not watch or saved.producer ~= nativeProducer
        or not origin(callback, "ISInventoryPaneContextMenu.lua") or not watch() then return false end
    local lineOk, line = pcall(firstLine, callback)
    if not lineOk or (line ~= 2826 and line ~= 3255) or not watch() then return false end
    local ok, mods = pcall(activatedMods)
    if not ok or not mods or type(mods.contains) ~= "function" then return false end
    local selected, present = pcall(mods.contains, mods, "P4TidyUpMeister")
    if not selected or present ~= false or saved.enabled() ~= true or not watch() then return false end
    -- Cache immutable source qualification only, after the cheap provider and
    -- setting gates. Unsupported source is not reread for every book click.
    if nativeReadRole == nil then
        local path = "media/lua/client/ISUI/ISInventoryPaneContextMenu.lua"
        local role = false
        if sourceMatches(path, 4293448388) then role = 2826
        elseif sourceMatches(path, 1953753890) then role = 3255 end
        if not watch() then return false end
        nativeReadRole = role
    end
    if line ~= nativeReadRole or not watch() then return false end
    remember(action, saved.inspect)
    if not watch() or action.Type ~= "ISInventoryTransferAction" or not saved.matches(action)
        or not saved.ordinary(action) or not action.item
        or action.destContainer ~= action.character:getInventory()
        or not saved.carried(action.srcContainer, action.character) or not watch() then return false end
    local function guard(value)
        return value == action and watch() and saved.matches(value) and saved.ordinary(value) and watch()
    end
    local handle = prepare(action, {guard = guard,
        capture = function(value) return {source = value.srcContainer} end,
        observed = function() return false end})
    return handle ~= nil and watch()
end
Restoration.observeNative = observeNative

Restoration.borrowedReturns = borrowedReturns
return Restoration
