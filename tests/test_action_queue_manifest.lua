if not NativeActionRoot then
    print('Manifest transfer isolation SKIP (pass native action root).'); return
end
local function read(path)
    if NativeReadText then return NativeReadText(path):gsub('\r', '') end
    local reader = assert(io.open(path)); local value = reader:read('*a'); reader:close(); return value:gsub('\r', '')
end
local function source(value, path) return assert(loadstring(value, '@' .. path))() end
local compatPath = ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/PZSurvivorToolkit/ActionQueueCompat.lua'
for _, mp in ipairs({false, true}) do
    local f = assert(loadfile(ProjectRoot .. '/tests/support/action_queue_native.lua'))()
    getFilenameOfClosure = NativeFilenameOfClosure or function(callback)
        return debug.getinfo(callback, 'S').source:gsub('^@', '')
    end
    isClient = function() return mp end
    getActivatedMods = function() return {contains = function() return false end} end
    f.project('ActionQueueOperations'); f.project('ActionQueueDefinitions')
    local policy = f.project('ActionQueuePolicy')
    local methods = {}
    for _, name in ipairs({'new', 'isValid', 'isValidStart', 'start', 'update', 'stop', 'perform', 'complete', 'transferItem'}) do
        methods[name] = ISInventoryTransferAction[name]
    end
    local previousRequire = require
    require = function(module)
        assert(module ~= 'LootSorter_Manifest', 'queue compatibility must not install a Manifest transfer observer')
        if module == 'PZSurvivorToolkit/ActionQueueTidyIntent' then return {observeTransfers=function() end} end
        if module == 'PZSurvivorToolkit/QuartermasterCraftContainers' then return {active = function() return false end} end
        if module == 'PZSurvivorToolkit/ActionQueueMembership' then
            return assert(loadfile(ProjectRoot .. '/PZSurvivorToolkit/42/media/lua/client/' .. module .. '.lua'))()
        end
        return previousRequire(module)
    end
    -- Exercise the complete module and its automatic install, including its no-mod branch.
    local compat = source(read(compatPath), compatPath)
    require = previousRequire
    for name, callback in pairs(methods) do
        assert(ISInventoryTransferAction[name] == callback, 'queue compatibility changed a native transfer method: ' .. name)
    end
    assert(not compat.isTransferPerform(methods.perform) and not compat.isTransferPerform(nil),
        'the compatibility callback query grants only observed Better Containers methods')
    local transactions = 0
    removeItemTransaction = function(id, retry)
        assert(id == 7 and retry == false); transactions = transactions + 1
    end
    local p = f.player
    p.setIsFarming = function(self, value) self.farming = value end
    ISLogSystem = {logAction = function(action) action.logged = (action.logged or 0) + 1 end}
    local function container()
        return {class = 'ItemContainer', getType = function() return 'crate' end,
            getContainingItem = function() end, getParent = function() end}
    end
    local function transfer()
        return f.action(ISInventoryTransferAction, {item = f.item('Base.Bandage'),
            srcContainer = container(), destContainer = container()})
    end
    for _, cancelled in ipairs({false, true}) do
        local action = transfer()
        local delta
        action.item.setJobDelta = function(_, value) delta = value end
        action.queueList, action.started, action.transactionId = {}, true, 7
        local previousTransactions = transactions
        local waitFinished = true
        action.action = {stopTimedActionAnim = function() end, setLoopedAction = function() end,
            setWaitForFinished = function(_, value) waitFinished = value end}
        local tail = f.action(ISReadABook, {item = f.item('Base.BookCarpentry1')})
        local queue, completed = f.queue(action, tail), 0
        queue.onCompleted = function(self, current)
            assert(current == action); completed = completed + 1
            table.remove(self.queue, 1); self.current = self.queue[1]
        end
        assert(policy.inspect(action), 'native transfer lost its policy contract')
        if cancelled then action.toolkitQueueOperation.toolkitCancelled = true end
        PZSurvivorToolkit.ActionQueueOperations.runWith(action.toolkitQueueOperation, action.perform, action)
        assert(completed == 1 and queue.current == tail and #queue.queue == 1 and action.logged == 1
            and action.started == false and delta == 0 and p.farming == false,
            'native transfer completion/cleanup must preserve the unrelated queue tail after Manifest isolation')
        assert(transactions == previousTransactions + (mp and 1 or 0) and action.transactionId == (mp and 0 or 7)
            and waitFinished == not mp,
            'native client completion must retain its transaction cleanup')
    end
    for _, callback in ipairs({function() error('foreign transfer callback must remain opaque') end,
        source('return function() error("forged manifest callback must remain opaque") end', 'media/lua/client/LootSorter_Manifest.lua')}) do
        ISInventoryTransferAction.perform = callback
        assert(not compat.isTransferPerform(callback) and not policy.inspect(transfer()),
            'unknown transfer wrapper acquired queue rights from the removed Manifest handoff')
    end
    ISInventoryTransferAction.perform = methods.perform
    local action = transfer()
    action.onCompleteFunc = function() error('foreign completion callback must remain opaque') end
    assert(not policy.inspect(action), 'unknown completion callback acquired native transfer rights')
    assert(policy.inspect(transfer()), 'restoring the native transfer callback must retain its original contract')
end
print('Manifest isolation: no transfer wrapper install, native completion/tail, cancellation cleanup and opaque callbacks passed (SP/client).')
